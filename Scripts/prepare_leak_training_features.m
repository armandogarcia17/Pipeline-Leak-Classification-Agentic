%% Prepare leak-sweep data for classification-model training
% Builds a scenario-level feature table from the synthetic leak sweep in
% synthetic_leak_data/20260915_123012.
%
% Features are extracted only from:
% - pump_outlet_flow_gpm
% - pump_outlet_pressure_psi

scriptFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptFolder);
runFolder = fullfile(projectRoot, 'synthetic_leak_data', '20260915_123012');

manifestFile = fullfile(runFolder, 'sweep_manifest.csv');
if ~isfile(manifestFile)
    error('PrepareLeakTrainingFeatures:MissingManifest', ...
        'Could not find manifest file: %s', manifestFile);
end

manifest = readtable(manifestFile, TextType='string');
completedRows = manifest.status == "completed" & manifest.output_file ~= "";
completedManifest = manifest(completedRows, :);

if isempty(completedManifest)
    error('PrepareLeakTrainingFeatures:NoCompletedScenarios', ...
        'No completed scenarios were found in %s.', manifestFile);
end

numScenarios = height(completedManifest);
featureRows = cell(numScenarios, 1);

for idx = 1:numScenarios
    outputFile = resolveOutputFile(completedManifest.output_file(idx), ...
        runFolder);

    loadedData = load(outputFile, 'sample');
    sample = loadedData.sample;

    flowFeatures = featureTableFromTimeseries( ...
        sample.signals.pump_outlet_flow_gpm, "pump_outlet_flow_gpm");
    pressureFeatures = featureTableFromTimeseries( ...
        sample.signals.pump_outlet_pressure_psi, ...
        "pump_outlet_pressure_psi");

    featureRows{idx} = [scenarioTable(completedManifest(idx, :)), ...
        flowFeatures, pressureFeatures];
end

trainingFeatureTable = vertcat(featureRows{:});
trainingFeatureTable.leak_source = categorical( ...
    trainingFeatureTable.leak_source, ...
    ["none" "segment1" "segment2" "both"]);

outputMatFile = fullfile(runFolder, 'leak_training_feature_table.mat');
outputCsvFile = fullfile(runFolder, 'leak_training_feature_table.csv');

save(outputMatFile, 'trainingFeatureTable');
writetable(trainingFeatureTable, outputCsvFile);

fprintf('Prepared %d training rows from %d manifest rows.\n', ...
    height(trainingFeatureTable), height(manifest));
fprintf('Skipped %d non-completed scenarios.\n', ...
    height(manifest) - height(trainingFeatureTable));
fprintf('Saved feature table to:\n%s\n%s\n', outputMatFile, outputCsvFile);

function outputFile = resolveOutputFile(manifestPath, runFolder)
outputFile = char(manifestPath);

if isfile(outputFile)
    return
end

% Fall back to the current run folder when an absolute path in the manifest
% no longer matches the checkout location.
[~, name, ext] = fileparts(outputFile);
outputFile = fullfile(runFolder, [name ext]);

if ~isfile(outputFile)
    error('PrepareLeakTrainingFeatures:MissingScenarioFile', ...
        'Could not find scenario file: %s', manifestPath);
end
end

function T = scenarioTable(row)
T = table;
T.scenario_id = row.scenario_id;
T.nominal_leak1_gpm = row.nominal_leak1_gpm;
T.nominal_leak2_gpm = row.nominal_leak2_gpm;
T.leak_source = row.leak_source;
end

function T = featureTableFromTimeseries(ts, prefix)
[timeSeconds, values] = timeseriesToFiniteVectors(ts);

stats = commonStats(timeSeconds, values);
names = string(fieldnames(stats))';
values = cellfun(@(name) stats.(name), cellstr(names));
varNames = matlab.lang.makeValidName(prefix + "_" + names);

T = array2table(values, VariableNames=varNames);
end

function [timeSeconds, values] = timeseriesToFiniteVectors(ts)
time = ts.Time(:);

if isduration(time)
    timeSeconds = seconds(time);
else
    timeSeconds = double(time);
end

values = squeeze(ts.Data);
values = double(values(:));

finiteIdx = isfinite(timeSeconds) & isfinite(values);
timeSeconds = timeSeconds(finiteIdx);
values = values(finiteIdx);

if numel(timeSeconds) > 1
    [timeSeconds, sortIdx] = sort(timeSeconds);
    values = values(sortIdx);
end
end

function stats = commonStats(timeSeconds, values)
if isempty(values)
    stats = emptyFeatureStats();
    return
end

diffValues = diff(values);

stats.num_samples = numel(values);
stats.duration_seconds = timeSeconds(end) - timeSeconds(1);
stats.mean = mean(values, 'omitnan');
stats.std = std(values, 0, 'omitnan');
stats.min = min(values, [], 'omitnan');
stats.max = max(values, [], 'omitnan');
stats.range = stats.max - stats.min;
stats.median = median(values, 'omitnan');
stats.q25 = percentileLocal(values, 25);
stats.q75 = percentileLocal(values, 75);
stats.iqr = stats.q75 - stats.q25;
stats.rms = sqrt(mean(values.^2, 'omitnan'));
stats.initial = values(1);
stats.final = values(end);
stats.delta = stats.final - stats.initial;
stats.mean_abs_diff = mean(abs(diffValues), 'omitnan');
stats.std_diff = std(diffValues, 0, 'omitnan');
stats.max_abs_diff = max(abs(diffValues), [], 'omitnan');
stats.trend_slope_per_sec = trendSlope(timeSeconds, values);
stats.area = trapz(timeSeconds, values);
end

function stats = emptyFeatureStats()
stats = struct( ...
    'num_samples', NaN, ...
    'duration_seconds', NaN, ...
    'mean', NaN, ...
    'std', NaN, ...
    'min', NaN, ...
    'max', NaN, ...
    'range', NaN, ...
    'median', NaN, ...
    'q25', NaN, ...
    'q75', NaN, ...
    'iqr', NaN, ...
    'rms', NaN, ...
    'initial', NaN, ...
    'final', NaN, ...
    'delta', NaN, ...
    'mean_abs_diff', NaN, ...
    'std_diff', NaN, ...
    'max_abs_diff', NaN, ...
    'trend_slope_per_sec', NaN, ...
    'area', NaN);
end

function p = percentileLocal(values, percentile)
values = sort(values(isfinite(values)));

if isempty(values)
    p = NaN;
    return
end

if isscalar(values)
    p = values;
    return
end

position = 1 + (numel(values) - 1) * percentile / 100;
lowerIdx = floor(position);
upperIdx = ceil(position);
fraction = position - lowerIdx;
p = values(lowerIdx) + fraction * (values(upperIdx) - values(lowerIdx));
end

function slope = trendSlope(timeSeconds, values)
if numel(values) < 2 || timeSeconds(end) == timeSeconds(1)
    slope = NaN;
    return
end

relativeTime = timeSeconds - timeSeconds(1);
coefficients = polyfit(relativeTime, values, 1);
slope = coefficients(1);
end
