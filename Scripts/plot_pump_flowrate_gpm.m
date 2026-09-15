%% Run pipeline model and plot pump flowrate in GPM
scriptFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptFolder);

addpath(fullfile(projectRoot, 'Data'));
addpath(fullfile(projectRoot, 'Simulations'));

fileGenConfig = Simulink.fileGenControl('getConfig');
fileGenCleanup = onCleanup(@() Simulink.fileGenControl( ...
    'setConfig', 'config', fileGenConfig));
Simulink.fileGenControl('set', ...
    'CacheFolder', projectRoot, ...
    'CodeGenFolder', projectRoot, ...
    'createDir', true);

modelName = 'pipeline_with_pump';
bpdPerGpm = 34.285714286;

runIDsBefore = Simulink.sdi.getAllRunIDs;

in = Simulink.SimulationInput(modelName);
in = in.setModelParameter('StopTime', '10');
out = sim(in);

flowTs = [];
runIDsAfter = Simulink.sdi.getAllRunIDs;
newRunIDs = setdiff(runIDsAfter, runIDsBefore, 'stable');

if ~isempty(newRunIDs)
    runObj = Simulink.sdi.getRun(newRunIDs(end));
    flowSignal = findSdiSignalByName(runObj, 'flowrate');

    if ~isempty(flowSignal)
        flowTs = flowSignal.Values;
    end
end

if isempty(flowTs)
    % q1 is the first root output and is saved in bbl/day.
    flowTs = out.yout{1}.Values;
end

pumpFlowGpm = flowTs.Data ./ bpdPerGpm;

fig = figure('Name', 'Pump Flowrate in GPM', 'Color', 'w');
plot(flowTs.Time, pumpFlowGpm, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Pump flowrate (GPM)');
title('Pump Flowrate for pipeline\_with\_pump');
xlim([0 10]);

outputFile = fullfile(scriptFolder, 'pump_flowrate_gpm.png');
exportgraphics(fig, outputFile, 'Resolution', 300);
fprintf('Saved pump flowrate plot to %s\n', outputFile);

function signal = findSdiSignalByName(runObj, signalName)
signal = [];

for idx = 1:runObj.SignalCount
    candidate = runObj.getSignalByIndex(idx);

    if strcmp(candidate.Name, signalName)
        signal = candidate;
        return
    end
end
end
