%% Generate synthetic leak data from pipeline_with_pump_leaks
% This script sweeps leak severity in both pipe segments and saves raw
% time-series data for machine-learning workflows.
%
% The leak model controls leaks with normalized valve openings, not direct
% flow-rate commands. This script maps a nominal 0-100 gpm leak severity to
% 0-1 valve opening and saves the measured leak1_gpm/leak2_gpm outputs for
% the actual simulated leak rates, including simultaneous-leak interactions.

scriptFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptFolder);

addpath(fullfile(projectRoot, 'Data'));
addpath(fullfile(projectRoot, 'Simulations'));

opts = defaultSweepOptions(projectRoot);

% Optional override for quick smoke runs or larger production sweeps:
% syntheticLeakSweepOptions = struct('LeakRateGridGpm', 0:5:100);
if exist('syntheticLeakSweepOptions', 'var')
    opts = mergeOptions(opts, syntheticLeakSweepOptions);
end

runFolder = createRunFolder(opts);
manifest = createScenarioManifest(opts);
in = createSimulationInputs(opts, manifest);

fprintf('Generating %d leak scenarios in:\n%s\n', height(manifest), runFolder);
fprintf('Leak grid: %s gpm per segment\n', mat2str(opts.LeakRateGridGpm));
fprintf('Nominal leak flow is mapped to valve opening using max %.1f gpm.\n', ...
    opts.MaxLeakFlowGpm);

saveManifest(runFolder, manifest, opts);

if opts.UseParallel && canUseParallel()
    pool = ensureParallelPool(opts.NumWorkers);
    fprintf('Running sweep in parallel with %d workers.\n', pool.NumWorkers);
    manifest = runParallelSweep(in, manifest, opts, runFolder);
else
    fprintf('Running sweep serially. Parallel Computing Toolbox is unavailable or disabled.\n');
    manifest = runSerialSweep(in, manifest, opts, runFolder);
end

saveManifest(runFolder, manifest, opts);
fprintf('Synthetic leak data generation complete.\n');
fprintf('Manifest: %s\n', fullfile(runFolder, 'sweep_manifest.csv'));

function opts = defaultSweepOptions(projectRoot)
opts = struct;
opts.ProjectRoot = projectRoot;
opts.ModelName = 'pipeline_with_pump_leaks';
opts.OutputRoot = fullfile(projectRoot, 'synthetic_leak_data');
opts.OutputRunTag = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));

% A full-factorial grid captures independent leaks and leak interactions.
opts.LeakRateGridGpm = 0:10:100;
opts.MaxLeakFlowGpm = 100;

% Cv is fixed across the sweep so fast restart can reuse compiled workers.
% Adjust if measured full-open leak rates are far from 100 gpm.
opts.LeakCvMax = 3.5;
opts.LeakReservoirPressurePsi = 14.7;

opts.StopTime = 10;
opts.UseFastRestart = true;
opts.UseParallel = true;
opts.NumWorkers = [];
opts.ShowProgress = 'on';

% Safeguards: force finite simulations, turn solver min-step warnings into
% errors, and cancel the background batch if it stops making progress.
opts.MaxConsecutiveMinStep = 1;
opts.MinStepSizeMsg = 'error';
opts.WatchdogPollSeconds = 30;
opts.NoProgressTimeoutSeconds = 20*60;
opts.BatchTimeoutSeconds = 8*60*60;

opts.SteadyStateWindowSeconds = 2;
end

function opts = mergeOptions(opts, overrides)
names = fieldnames(overrides);
for idx = 1:numel(names)
    opts.(names{idx}) = overrides.(names{idx});
end
end

function runFolder = createRunFolder(opts)
if ~exist(opts.OutputRoot, 'dir')
    mkdir(opts.OutputRoot);
end

runFolder = fullfile(opts.OutputRoot, opts.OutputRunTag);
if ~exist(runFolder, 'dir')
    mkdir(runFolder);
end
end

function manifest = createScenarioManifest(opts)
[leak1Grid, leak2Grid] = ndgrid(opts.LeakRateGridGpm, opts.LeakRateGridGpm);
leak1Gpm = leak1Grid(:);
leak2Gpm = leak2Grid(:);
numScenarios = numel(leak1Gpm);

manifest = table;
manifest.scenario_id = (1:numScenarios)';
manifest.nominal_leak1_gpm = leak1Gpm;
manifest.nominal_leak2_gpm = leak2Gpm;
manifest.leak1_opening = leak1Gpm ./ opts.MaxLeakFlowGpm;
manifest.leak2_opening = leak2Gpm ./ opts.MaxLeakFlowGpm;
manifest.leak1_present = leak1Gpm > 0;
manifest.leak2_present = leak2Gpm > 0;
manifest.leak_source = strings(numScenarios, 1);

for idx = 1:numScenarios
    manifest.leak_source(idx) = classifyLeakSource( ...
        manifest.leak1_present(idx), manifest.leak2_present(idx));
end

manifest.status = repmat("pending", numScenarios, 1);
manifest.output_file = strings(numScenarios, 1);
manifest.error_message = strings(numScenarios, 1);
manifest.elapsed_seconds = nan(numScenarios, 1);
manifest.actual_leak1_gpm_mean = nan(numScenarios, 1);
manifest.actual_leak2_gpm_mean = nan(numScenarios, 1);
manifest.actual_leak1_gpm_final = nan(numScenarios, 1);
manifest.actual_leak2_gpm_final = nan(numScenarios, 1);
end

function label = classifyLeakSource(leak1Present, leak2Present)
if leak1Present && leak2Present
    label = "both";
elseif leak1Present
    label = "segment1";
elseif leak2Present
    label = "segment2";
else
    label = "none";
end
end

function in = createSimulationInputs(opts, manifest)
numScenarios = height(manifest);
in(numScenarios, 1) = Simulink.SimulationInput(opts.ModelName);

for idx = 1:numScenarios
    in(idx) = Simulink.SimulationInput(opts.ModelName);
    in(idx) = in(idx).setModelParameter( ...
        'StopTime', num2str(opts.StopTime), ...
        'ReturnWorkspaceOutputs', 'on', ...
        'SaveOutput', 'on', ...
        'SaveFormat', 'Dataset', ...
        'OutputSaveName', 'yout', ...
        'SignalLogging', 'on', ...
        'SignalLoggingName', 'logsout', ...
        'MinStepSizeMsg', opts.MinStepSizeMsg, ...
        'MaxConsecutiveMinStep', num2str(opts.MaxConsecutiveMinStep));

    in(idx) = in(idx).setVariable('leak1_opening', ...
        manifest.leak1_opening(idx), 'Workspace', opts.ModelName);
    in(idx) = in(idx).setVariable('leak2_opening', ...
        manifest.leak2_opening(idx), 'Workspace', opts.ModelName);
    in(idx) = in(idx).setVariable('leak1_Cv_max', ...
        opts.LeakCvMax, 'Workspace', opts.ModelName);
    in(idx) = in(idx).setVariable('leak2_Cv_max', ...
        opts.LeakCvMax, 'Workspace', opts.ModelName);
    in(idx) = in(idx).setVariable('leak_reservoir_pressure', ...
        opts.LeakReservoirPressurePsi, 'Workspace', opts.ModelName);
end
end

function tf = canUseParallel()
tf = ~isempty(ver('parallel')) && license('test', 'Distrib_Computing_Toolbox');
end

function pool = ensureParallelPool(numWorkers)
pool = gcp('nocreate');
if isempty(pool)
    if isempty(numWorkers)
        pool = parpool('local');
    else
        pool = parpool('local', numWorkers);
    end
end
end

function manifest = runParallelSweep(in, manifest, opts, runFolder)
setupFcn = @() addpath( ...
    fullfile(opts.ProjectRoot, 'Data'), ...
    fullfile(opts.ProjectRoot, 'Simulations'));

parsimArgs = {'ShowProgress', opts.ShowProgress, ...
    'ShowSimulationManager', 'off', ...
    'StopOnError', 'off', ...
    'TransferBaseWorkspaceVariables', 'on', ...
    'SetupFcn', setupFcn, ...
    'RunInBackground', 'on'};

if opts.UseFastRestart
    parsimArgs = [parsimArgs, {'UseFastRestart', 'on'}];
end

futureOut = parsim(in, parsimArgs{:});
cancelFutureOnCleanup = onCleanup(@() cancelUnreadFutures(futureOut));

completedCount = 0;
batchTimer = tic;
progressTimer = tic;

while completedCount < numel(in)
    [idx, out] = fetchNextWithTimeout(futureOut, opts.WatchdogPollSeconds);

    if isempty(idx)
        if toc(batchTimer) > opts.BatchTimeoutSeconds
            manifest = markUnreadFuturesCancelled(manifest, futureOut, ...
                "cancelled_by_batch_timeout");
            saveManifest(runFolder, manifest, opts);
            cancel(futureOut);
            error('SyntheticLeakData:BatchTimeout', ...
                'Cancelled sweep after %.0f seconds.', toc(batchTimer));
        end

        if toc(progressTimer) > opts.NoProgressTimeoutSeconds
            manifest = markUnreadFuturesCancelled(manifest, futureOut, ...
                "cancelled_by_no_progress");
            saveManifest(runFolder, manifest, opts);
            cancel(futureOut);
            error('SyntheticLeakData:NoProgressTimeout', ...
                'Cancelled sweep after %.0f seconds without completed simulations.', ...
                toc(progressTimer));
        end

        continue
    end

    completedCount = completedCount + 1;
    progressTimer = tic;
    manifest = saveScenarioResult(out, idx, manifest, opts, runFolder);
    saveManifest(runFolder, manifest, opts);
end

clear cancelFutureOnCleanup
end

function [idx, out] = fetchNextWithTimeout(futureOut, timeoutSeconds)
try
    [idx, out] = fetchNext(futureOut, timeoutSeconds);
catch ME
    if contains(lower(ME.message), 'timeout')
        idx = [];
        out = [];
    else
        rethrow(ME);
    end
end
end

function cancelUnreadFutures(futureOut)
valid = isvalid(futureOut);
if ~any(valid)
    return
end

try
    unread = valid & ~[futureOut.Read];
    if any(unread)
        cancel(futureOut(unread));
    end
catch
end
end

function manifest = markUnreadFuturesCancelled(manifest, futureOut, status)
valid = isvalid(futureOut);
unread = valid & ~[futureOut.Read];
pendingRows = unread(:) & manifest.status == "pending";
manifest.status(pendingRows) = status;
manifest.error_message(pendingRows) = ...
    "Cancelled by synthetic leak sweep watchdog.";
end

function manifest = runSerialSweep(in, manifest, opts, runFolder)
for idx = 1:numel(in)
    try
        out = sim(in(idx));
        manifest = saveScenarioResult(out, idx, manifest, opts, runFolder);
    catch ME
        manifest.status(idx) = "failed";
        manifest.error_message(idx) = string(getReport(ME, 'basic', ...
            'hyperlinks', 'off'));
    end

    saveManifest(runFolder, manifest, opts);
end
end

function manifest = saveScenarioResult(out, idx, manifest, opts, runFolder)
elapsedSeconds = out.SimulationMetadata.TimingInfo.ExecutionElapsedWallTime;
manifest.elapsed_seconds(idx) = elapsedSeconds;

errorMessage = string(out.ErrorMessage);
if strlength(strtrim(errorMessage)) > 0
    manifest.status(idx) = "failed";
    manifest.error_message(idx) = errorMessage;
    return
end

sample = struct;
sample.metadata = scenarioMetadata(manifest, idx, opts);
sample.signals = extractSignals(out);
sample.summary = summarizeSignals(sample.signals, opts.SteadyStateWindowSeconds);

fileName = scenarioFileName(manifest, idx);
outputFile = fullfile(runFolder, fileName);
save(outputFile, 'sample', '-v7.3');

manifest.status(idx) = "completed";
manifest.output_file(idx) = string(outputFile);
manifest.actual_leak1_gpm_mean(idx) = sample.summary.leak1_gpm.mean_abs;
manifest.actual_leak2_gpm_mean(idx) = sample.summary.leak2_gpm.mean_abs;
manifest.actual_leak1_gpm_final(idx) = sample.summary.leak1_gpm.final_abs;
manifest.actual_leak2_gpm_final(idx) = sample.summary.leak2_gpm.final_abs;
end

function metadata = scenarioMetadata(manifest, idx, opts)
metadata = struct;
metadata.model = opts.ModelName;
metadata.stop_time_seconds = opts.StopTime;
metadata.scenario_id = manifest.scenario_id(idx);
metadata.leak_source = manifest.leak_source(idx);
metadata.nominal_leak1_gpm = manifest.nominal_leak1_gpm(idx);
metadata.nominal_leak2_gpm = manifest.nominal_leak2_gpm(idx);
metadata.leak1_opening = manifest.leak1_opening(idx);
metadata.leak2_opening = manifest.leak2_opening(idx);
metadata.leak_Cv_max = opts.LeakCvMax;
metadata.leak_reservoir_pressure_psi = opts.LeakReservoirPressurePsi;
end

function signals = extractSignals(out)
signals = struct;

signals.pump_outlet_flow_gpm = out.logsout.get('pump_outlet_flow_gpm').Values;
signals.pump_outlet_pressure_psi = ...
    out.logsout.get('pump_outlet_pressure_psi').Values;

% Root outports from pipeline_with_pump_leaks:
% 1 q1, 2 P1, 3 T1, 4 q2, 5 P2, 6 T2, 7 leak1_gpm, 8 leak2_gpm.
signals.sensor1_flow_bpd = out.yout{1}.Values;
signals.sensor1_pressure_psi = out.yout{2}.Values;
signals.sensor1_temperature_degF = out.yout{3}.Values;
signals.sensor2_flow_bpd = out.yout{4}.Values;
signals.sensor2_pressure_psi = out.yout{5}.Values;
signals.sensor2_temperature_degF = out.yout{6}.Values;
signals.leak1_gpm = out.yout{7}.Values;
signals.leak2_gpm = out.yout{8}.Values;
end

function summary = summarizeSignals(signals, steadyStateWindowSeconds)
names = fieldnames(signals);
summary = struct;

for idx = 1:numel(names)
    name = names{idx};
    summary.(name) = summarizeTimeseries(signals.(name), ...
        steadyStateWindowSeconds);
end
end

function stats = summarizeTimeseries(ts, steadyStateWindowSeconds)
time = ts.Time(:);
data = squeeze(ts.Data);

if isempty(time) || isempty(data)
    stats = emptyStats();
    return
end

if isduration(time)
    timeSeconds = seconds(time);
else
    timeSeconds = double(time);
end

if isvector(data)
    data = data(:);
else
    data = reshape(data, size(data, 1), []);
end

finalValues = data(end, :);
windowStart = max(timeSeconds(1), timeSeconds(end) - steadyStateWindowSeconds);
windowData = data(timeSeconds >= windowStart, :);
windowData = windowData(:);
windowData = windowData(isfinite(windowData));

stats.final = mean(finalValues(isfinite(finalValues)));
stats.final_abs = mean(abs(finalValues(isfinite(finalValues))));

if isempty(windowData)
    stats.mean = NaN;
    stats.mean_abs = NaN;
    stats.std = NaN;
else
    stats.mean = mean(windowData);
    stats.mean_abs = mean(abs(windowData));
    stats.std = std(windowData);
end
end

function stats = emptyStats()
stats = struct('final', NaN, 'final_abs', NaN, ...
    'mean', NaN, 'mean_abs', NaN, 'std', NaN);
end

function fileName = scenarioFileName(manifest, idx)
fileName = sprintf('scenario_%04d_l1_%s_gpm_l2_%s_gpm.mat', ...
    manifest.scenario_id(idx), ...
    formatLeakValue(manifest.nominal_leak1_gpm(idx)), ...
    formatLeakValue(manifest.nominal_leak2_gpm(idx)));
end

function textValue = formatLeakValue(value)
textValue = strrep(sprintf('%06.2f', value), '.', 'p');
end

function saveManifest(runFolder, manifest, opts)
save(fullfile(runFolder, 'sweep_manifest.mat'), 'manifest', 'opts');
writetable(manifest, fullfile(runFolder, 'sweep_manifest.csv'));
end
