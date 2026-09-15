classdef LeakClassifierApp < handle
    %LEAKCLASSIFIERAPP Simulate and classify leak scenarios.

    properties (Constant, Access = private)
        ModelName = "pipeline_with_pump_leaks"
    end

    properties (Access = private)
        ProjectRoot string
        StopTime double
        MaxLeakFlowGpm double
        LeakCvMax double
        LeakReservoirPressurePsi double

        TrainedClassifier
        ValidationAccuracy double = NaN

        Figure
        Leak1Slider
        Leak1Edit
        Leak2Slider
        Leak2Edit
        StopTimeEdit
        RunButton
        PredictedField
        ValidationField
        ConditionLamp
        ResultsTable
        StatusText
        IsDeleting logical = false
    end

    methods
        function app = LeakClassifierApp(options)
            arguments
                options.ProjectRoot (1, 1) string = string(fileparts(mfilename("fullpath")))
                options.StopTime (1, 1) double {mustBePositive} = 10
                options.MaxLeakFlowGpm (1, 1) double {mustBePositive} = 100
                options.LeakCvMax (1, 1) double {mustBePositive} = 3.5
                options.LeakReservoirPressurePsi (1, 1) double {mustBePositive} = 14.7
            end

            app.ProjectRoot = options.ProjectRoot;
            app.StopTime = options.StopTime;
            app.MaxLeakFlowGpm = options.MaxLeakFlowGpm;
            app.LeakCvMax = options.LeakCvMax;
            app.LeakReservoirPressurePsi = options.LeakReservoirPressurePsi;

            app.configurePaths();
            app.createComponents();
            app.initializeClassifier();
        end

        function delete(app)
            if app.IsDeleting
                return
            end

            app.IsDeleting = true;
            if ~isempty(app.Figure) && isvalid(app.Figure)
                app.Figure.CloseRequestFcn = [];
                delete(app.Figure);
            end
        end

        function result = simulateAndClassify(app, leak1Gpm, leak2Gpm)
            arguments
                app
                leak1Gpm (1, 1) double {mustBeGreaterThanOrEqual(leak1Gpm, 0), mustBeLessThanOrEqual(leak1Gpm, 100)}
                leak2Gpm (1, 1) double {mustBeGreaterThanOrEqual(leak2Gpm, 0), mustBeLessThanOrEqual(leak2Gpm, 100)}
            end

            out = app.simulateSelectedLeaks(leak1Gpm, leak2Gpm);
            signals = app.extractSignals(out);
            featureTable = app.createFeatureTable( ...
                signals.pump_outlet_flow_gpm, ...
                signals.pump_outlet_pressure_psi);
            [predictedLabel, scores] = app.predictLeakSource(featureTable);

            app.updateResults(predictedLabel, scores, signals, out, ...
                leak1Gpm, leak2Gpm);

            result = struct;
            result.PredictedLabel = predictedLabel;
            result.Scores = scores;
            result.Summary = app.ResultsTable.Data;
            result.FeatureTable = featureTable;
        end
    end

    methods (Access = private)
        function configurePaths(app)
            folders = ["Data", "Scripts", "Simulations"];
            for idx = 1:numel(folders)
                folderPath = fullfile(app.ProjectRoot, folders(idx));
                if isfolder(folderPath)
                    addpath(folderPath);
                end
            end
        end

        function createComponents(app)
            app.Figure = uifigure( ...
                "Name", "Pipeline Leak Classifier", ...
                "Position", [100 100 980 620], ...
                "CloseRequestFcn", @(~, ~) delete(app));

            rootGrid = uigridlayout(app.Figure, [3 2]);
            rootGrid.RowHeight = {"fit", "1x", 72};
            rootGrid.ColumnWidth = {300, "1x"};
            rootGrid.Padding = [0 0 0 0];
            rootGrid.RowSpacing = 0;
            rootGrid.ColumnSpacing = 0;

            headerPanel = uipanel(rootGrid, "BorderType", "none");
            headerPanel.Layout.Row = 1;
            headerPanel.Layout.Column = [1 2];

            headerGrid = uigridlayout(headerPanel, [2 1]);
            headerGrid.Padding = [16 12 16 8];
            headerGrid.RowHeight = {"fit", "fit"};

            titleLabel = uilabel(headerGrid, ...
                "Text", "Pipeline Leak Classifier", ...
                "FontSize", 20, ...
                "FontWeight", "bold");
            titleLabel.Layout.Row = 1;

            modelLabel = uilabel(headerGrid, ...
                "Text", "Simulink model: " + app.ModelName);
            modelLabel.Layout.Row = 2;

            controlsPanel = uipanel(rootGrid, "Title", "Leak Inputs");
            controlsPanel.Layout.Row = 2;
            controlsPanel.Layout.Column = 1;

            controlsGrid = uigridlayout(controlsPanel, [9 2]);
            controlsGrid.RowHeight = {"fit", "fit", "fit", "fit", "fit", "fit", "fit", "1x", "fit"};
            controlsGrid.ColumnWidth = {"1x", 78};
            controlsGrid.Padding = [14 14 14 14];
            controlsGrid.RowSpacing = 12;

            leak1Label = uilabel(controlsGrid, ...
                "Text", "Segment 1 leak flow (gpm)", ...
                "FontWeight", "bold");
            leak1Label.Layout.Row = 1;
            leak1Label.Layout.Column = [1 2];

            app.Leak1Slider = uislider(controlsGrid, ...
                "Limits", [0 100], ...
                "MajorTicks", 0:20:100, ...
                "Value", 0, ...
                "ValueChangedFcn", @(~, ~) app.onLeak1Changed("slider"));
            app.Leak1Slider.Layout.Row = 2;
            app.Leak1Slider.Layout.Column = 1;

            app.Leak1Edit = uieditfield(controlsGrid, "numeric", ...
                "Limits", [0 100], ...
                "Value", 0, ...
                "LowerLimitInclusive", "on", ...
                "UpperLimitInclusive", "on", ...
                "ValueDisplayFormat", "%.1f", ...
                "ValueChangedFcn", @(~, ~) app.onLeak1Changed("edit"));
            app.Leak1Edit.Layout.Row = 2;
            app.Leak1Edit.Layout.Column = 2;

            leak2Label = uilabel(controlsGrid, ...
                "Text", "Segment 2 leak flow (gpm)", ...
                "FontWeight", "bold");
            leak2Label.Layout.Row = 3;
            leak2Label.Layout.Column = [1 2];

            app.Leak2Slider = uislider(controlsGrid, ...
                "Limits", [0 100], ...
                "MajorTicks", 0:20:100, ...
                "Value", 0, ...
                "ValueChangedFcn", @(~, ~) app.onLeak2Changed("slider"));
            app.Leak2Slider.Layout.Row = 4;
            app.Leak2Slider.Layout.Column = 1;

            app.Leak2Edit = uieditfield(controlsGrid, "numeric", ...
                "Limits", [0 100], ...
                "Value", 0, ...
                "LowerLimitInclusive", "on", ...
                "UpperLimitInclusive", "on", ...
                "ValueDisplayFormat", "%.1f", ...
                "ValueChangedFcn", @(~, ~) app.onLeak2Changed("edit"));
            app.Leak2Edit.Layout.Row = 4;
            app.Leak2Edit.Layout.Column = 2;

            stopTimeLabel = uilabel(controlsGrid, ...
                "Text", "Stop time (s)", ...
                "FontWeight", "bold");
            stopTimeLabel.Layout.Row = 5;
            stopTimeLabel.Layout.Column = 1;

            app.StopTimeEdit = uieditfield(controlsGrid, "numeric", ...
                "Limits", [0.1 Inf], ...
                "Value", app.StopTime, ...
                "LowerLimitInclusive", "on", ...
                "ValueDisplayFormat", "%.1f", ...
                "ValueChangedFcn", @(~, ~) app.onStopTimeChanged());
            app.StopTimeEdit.Layout.Row = 5;
            app.StopTimeEdit.Layout.Column = 2;

            openingLabel = uilabel(controlsGrid, ...
                "Text", "Valve opening is scaled from selected gpm.");
            openingLabel.Layout.Row = 6;
            openingLabel.Layout.Column = [1 2];

            app.RunButton = uibutton(controlsGrid, "push", ...
                "Text", "Run Simulation", ...
                "ButtonPushedFcn", @(~, ~) app.runSimulation());
            app.RunButton.Layout.Row = 7;
            app.RunButton.Layout.Column = [1 2];

            resultsPanel = uipanel(rootGrid, "Title", "Results");
            resultsPanel.Layout.Row = 2;
            resultsPanel.Layout.Column = 2;

            resultsGrid = uigridlayout(resultsPanel, [6 2]);
            resultsGrid.RowHeight = {"fit", "fit", "fit", "fit", "1x", "fit"};
            resultsGrid.ColumnWidth = {150, "1x"};
            resultsGrid.Padding = [14 14 14 14];
            resultsGrid.RowSpacing = 10;

            predictedLabel = uilabel(resultsGrid, ...
                "Text", "Predicted condition", ...
                "FontWeight", "bold");
            predictedLabel.Layout.Row = 1;
            predictedLabel.Layout.Column = 1;

            app.PredictedField = uieditfield(resultsGrid, "text", ...
                "Editable", "off", ...
                "Value", "Not run");
            app.PredictedField.Layout.Row = 1;
            app.PredictedField.Layout.Column = 2;

            lampLabel = uilabel(resultsGrid, ...
                "Text", "Leak status", ...
                "FontWeight", "bold");
            lampLabel.Layout.Row = 2;
            lampLabel.Layout.Column = 1;

            app.ConditionLamp = uilamp(resultsGrid, ...
                "Color", [0.5 0.5 0.5]);
            app.ConditionLamp.Layout.Row = 2;
            app.ConditionLamp.Layout.Column = 2;

            validationLabel = uilabel(resultsGrid, ...
                "Text", "Validation accuracy", ...
                "FontWeight", "bold");
            validationLabel.Layout.Row = 3;
            validationLabel.Layout.Column = 1;

            app.ValidationField = uieditfield(resultsGrid, "text", ...
                "Editable", "off", ...
                "Value", "Loading");
            app.ValidationField.Layout.Row = 3;
            app.ValidationField.Layout.Column = 2;

            tableLabel = uilabel(resultsGrid, ...
                "Text", "Simulation summary", ...
                "FontWeight", "bold");
            tableLabel.Layout.Row = 4;
            tableLabel.Layout.Column = [1 2];

            app.ResultsTable = uitable(resultsGrid, ...
                "Data", app.emptyResultsTable(), ...
                "ColumnEditable", [false false]);
            app.ResultsTable.Layout.Row = 5;
            app.ResultsTable.Layout.Column = [1 2];

            statusPanel = uipanel(rootGrid, "Title", "Status");
            statusPanel.Layout.Row = 3;
            statusPanel.Layout.Column = [1 2];

            statusGrid = uigridlayout(statusPanel, [1 1]);
            statusGrid.Padding = [8 6 8 8];

            app.StatusText = uitextarea(statusGrid, ...
                "Editable", "off", ...
                "Value", "Initializing.");
            app.StatusText.Layout.Row = 1;
            app.StatusText.Layout.Column = 1;
        end

        function initializeClassifier(app)
            app.RunButton.Enable = "off";
            drawnow;

            try
                app.loadOrTrainClassifier();
                app.ValidationField.Value = app.formatAccuracy(app.ValidationAccuracy);
                app.RunButton.Enable = "on";
                app.setStatus("Ready.");
            catch ME
                app.PredictedField.Value = "Classifier unavailable";
                app.ConditionLamp.Color = [0.5 0.5 0.5];
                app.ValidationField.Value = "Unavailable";
                app.setStatus("Classifier initialization failed: " + ...
                    string(getReport(ME, "basic", "hyperlinks", "off")));
            end
        end

        function loadOrTrainClassifier(app)
            if evalin("base", "exist('trainedClassifier', 'var')") == 1
                app.TrainedClassifier = evalin("base", "trainedClassifier");
                if evalin("base", "exist('validationAccuracy', 'var')") == 1
                    app.ValidationAccuracy = evalin("base", "validationAccuracy");
                end
                return
            end

            candidates = [
                fullfile(app.ProjectRoot, "Data", "trainedClassifier.mat")
                fullfile(app.ProjectRoot, "trainedClassifier.mat")
            ];

            for idx = 1:numel(candidates)
                if isfile(candidates(idx))
                    loadedData = load(candidates(idx));
                    if isfield(loadedData, "trainedClassifier")
                        app.TrainedClassifier = loadedData.trainedClassifier;
                        if isfield(loadedData, "validationAccuracy")
                            app.ValidationAccuracy = loadedData.validationAccuracy;
                        end
                        return
                    end
                end
            end

            trainingFile = fullfile(app.ProjectRoot, "Data", "trainingFeatures.mat");
            if ~isfile(trainingFile)
                error("LeakClassifierApp:MissingTrainingData", ...
                    "Could not find training feature data: %s", trainingFile);
            end

            loadedData = load(trainingFile, "trainingFeatureTable");
            [app.TrainedClassifier, app.ValidationAccuracy] = ...
                trainClassifier(loadedData.trainingFeatureTable);
        end

        function onLeak1Changed(app, source)
            if source == "slider"
                app.Leak1Edit.Value = app.roundLeakValue(app.Leak1Slider.Value);
            else
                app.Leak1Slider.Value = app.Leak1Edit.Value;
            end
            app.resetPrediction();
        end

        function onLeak2Changed(app, source)
            if source == "slider"
                app.Leak2Edit.Value = app.roundLeakValue(app.Leak2Slider.Value);
            else
                app.Leak2Slider.Value = app.Leak2Edit.Value;
            end
            app.resetPrediction();
        end

        function onStopTimeChanged(app)
            app.StopTime = app.StopTimeEdit.Value;
            app.resetPrediction();
        end

        function resetPrediction(app)
            app.PredictedField.Value = "Not run";
            app.ConditionLamp.Color = [0.5 0.5 0.5];
            app.setStatus("Inputs changed. Run simulation to update prediction.");
        end

        function runSimulation(app)
            app.setBusy(true);
            cleanup = onCleanup(@() app.setBusy(false));

            try
                leak1Gpm = app.Leak1Edit.Value;
                leak2Gpm = app.Leak2Edit.Value;
                app.setStatus(sprintf( ...
                    "Running %s with %.1f gpm in segment 1 and %.1f gpm in segment 2.", ...
                    app.ModelName, leak1Gpm, leak2Gpm));
                drawnow;

                app.simulateAndClassify(leak1Gpm, leak2Gpm);
                app.setStatus("Simulation complete.");
            catch ME
                app.PredictedField.Value = "Simulation failed";
                app.ConditionLamp.Color = [0.5 0.5 0.5];
                app.setStatus("Simulation failed: " + ...
                    string(getReport(ME, "basic", "hyperlinks", "off")));
            end

            clear cleanup
        end

        function out = simulateSelectedLeaks(app, leak1Gpm, leak2Gpm)
            model = app.ModelName;
            leak1Opening = leak1Gpm / app.MaxLeakFlowGpm;
            leak2Opening = leak2Gpm / app.MaxLeakFlowGpm;
            modelParams = app.loadPipelineModelParameters();

            in = Simulink.SimulationInput(model);
            in = in.setModelParameter( ...
                "StopTime", num2str(app.StopTime), ...
                "ReturnWorkspaceOutputs", "on", ...
                "SaveOutput", "on", ...
                "SaveFormat", "Dataset", ...
                "OutputSaveName", "yout", ...
                "SignalLogging", "on", ...
                "SignalLoggingName", "logsout", ...
                "MinStepSizeMsg", "error", ...
                "MaxConsecutiveMinStep", "1");
            in = in.setVariable("pump_data", modelParams.pump_data);
            in = in.setVariable("D", modelParams.D);
            in = in.setVariable("initPres", modelParams.initPres);
            in = in.setVariable("Ap", modelParams.Ap);
            in = in.setVariable("leak1_opening", leak1Opening, ...
                "Workspace", model);
            in = in.setVariable("leak2_opening", leak2Opening, ...
                "Workspace", model);
            in = in.setVariable("leak1_Cv_max", app.LeakCvMax, ...
                "Workspace", model);
            in = in.setVariable("leak2_Cv_max", app.LeakCvMax, ...
                "Workspace", model);
            in = in.setVariable("leak_reservoir_pressure", ...
                app.LeakReservoirPressurePsi, "Workspace", model);

            out = sim(in);
            errorMessage = string(out.ErrorMessage);
            if strlength(strtrim(errorMessage)) > 0
                error("LeakClassifierApp:SimulationError", "%s", errorMessage);
            end
        end

        function modelParams = loadPipelineModelParameters(app)
            pumpDataFile = fullfile(app.ProjectRoot, "Data", "pump_data.mat");
            if ~isfile(pumpDataFile)
                error("LeakClassifierApp:MissingPumpData", ...
                    "Could not find pump data file: %s", pumpDataFile);
            end

            loadedData = load(pumpDataFile, "pump_data");
            if ~isfield(loadedData, "pump_data")
                error("LeakClassifierApp:MissingPumpDataVariable", ...
                    "Pump data file does not contain variable pump_data: %s", ...
                    pumpDataFile);
            end

            modelParams = struct;
            modelParams.pump_data = loadedData.pump_data;
            modelParams.D = (10/12)/3.281;
            modelParams.initPres = 100;
            modelParams.Ap = pi*modelParams.D^2/4;
        end

        function signals = extractSignals(~, out)
            signals = struct;
            signals.pump_outlet_flow_gpm = ...
                out.logsout.get("pump_outlet_flow_gpm").Values;
            signals.pump_outlet_pressure_psi = ...
                out.logsout.get("pump_outlet_pressure_psi").Values;
            signals.leak1_gpm = out.yout{7}.Values;
            signals.leak2_gpm = out.yout{8}.Values;
        end

        function [predictedLabel, scores] = predictLeakSource(app, featureTable)
            missingVariables = setdiff( ...
                app.TrainedClassifier.RequiredVariables, ...
                featureTable.Properties.VariableNames);

            if ~isempty(missingVariables)
                error("LeakClassifierApp:MissingPredictors", ...
                    "Missing predictor variables: %s", ...
                    strjoin(string(missingVariables), ", "));
            end

            try
                [predictedLabel, scores] = ...
                    app.TrainedClassifier.predictFcn(featureTable);
            catch
                predictedLabel = app.TrainedClassifier.predictFcn(featureTable);
                scores = [];
            end
        end

        function updateResults(app, predictedLabel, scores, signals, out, ...
                leak1Gpm, leak2Gpm)
            labelText = app.formatPrediction(predictedLabel);
            app.PredictedField.Value = labelText;

            if string(predictedLabel) == "none"
                app.ConditionLamp.Color = [0.0 0.60 0.20];
            else
                app.ConditionLamp.Color = [0.85 0.10 0.10];
            end

            app.ResultsTable.Data = app.createResultsTable( ...
                predictedLabel, scores, signals, out, leak1Gpm, leak2Gpm);
        end

        function tableData = createResultsTable(app, predictedLabel, scores, ...
                signals, out, leak1Gpm, leak2Gpm)
            pumpFlow = app.summarizeTimeseries(signals.pump_outlet_flow_gpm);
            pumpPressure = app.summarizeTimeseries( ...
                signals.pump_outlet_pressure_psi);
            leak1 = app.summarizeTimeseries(signals.leak1_gpm);
            leak2 = app.summarizeTimeseries(signals.leak2_gpm);

            elapsedSeconds = ...
                out.SimulationMetadata.TimingInfo.ExecutionElapsedWallTime;

            metrics = [
                "Selected segment 1 leak"
                "Selected segment 2 leak"
                "Predicted condition"
                "Measured segment 1 leak mean"
                "Measured segment 1 leak final"
                "Measured segment 2 leak mean"
                "Measured segment 2 leak final"
                "Pump outlet flow mean"
                "Pump outlet flow final"
                "Pump outlet pressure mean"
                "Pump outlet pressure final"
                "Simulation elapsed"
            ];

            values = [
                string(sprintf("%.1f gpm", leak1Gpm))
                string(sprintf("%.1f gpm", leak2Gpm))
                app.formatPrediction(predictedLabel)
                string(sprintf("%.2f gpm", leak1.mean_abs))
                string(sprintf("%.2f gpm", leak1.final_abs))
                string(sprintf("%.2f gpm", leak2.mean_abs))
                string(sprintf("%.2f gpm", leak2.final_abs))
                string(sprintf("%.2f gpm", pumpFlow.mean))
                string(sprintf("%.2f gpm", pumpFlow.final))
                string(sprintf("%.2f psi", pumpPressure.mean))
                string(sprintf("%.2f psi", pumpPressure.final))
                string(sprintf("%.2f s", elapsedSeconds))
            ];

            if ~isempty(scores)
                [bestScore, bestIdx] = max(scores(1, :));
                classNames = string( ...
                    app.TrainedClassifier.ClassificationLinear.ClassNames);
                metrics(end + 1) = "Best score";
                values(end + 1) = string(sprintf("%s: %.4g", ...
                    classNames(bestIdx), bestScore));
            end

            tableData = table(metrics, values, ...
                'VariableNames', {'Metric', 'Value'});
        end

        function T = createFeatureTable(app, flowTimeseries, pressureTimeseries)
            T = [
                app.featureTableFromTimeseries(flowTimeseries, ...
                    "pump_outlet_flow_gpm"), ...
                app.featureTableFromTimeseries(pressureTimeseries, ...
                    "pump_outlet_pressure_psi")
            ];
        end

        function T = featureTableFromTimeseries(app, ts, prefix)
            [timeSeconds, values] = app.timeseriesToFiniteVectors(ts);
            stats = app.commonStats(timeSeconds, values);
            names = string(fieldnames(stats))';
            numericValues = cellfun(@(name) stats.(name), cellstr(names));
            varNames = matlab.lang.makeValidName(prefix + "_" + names);
            T = array2table(numericValues, ...
                'VariableNames', cellstr(varNames));
        end

        function stats = commonStats(app, timeSeconds, values)
            if isempty(values)
                stats = app.emptyFeatureStats();
                return
            end

            diffValues = diff(values);
            stats.num_samples = numel(values);
            stats.duration_seconds = timeSeconds(end) - timeSeconds(1);
            stats.mean = mean(values, "omitnan");
            stats.std = std(values, 0, "omitnan");
            stats.min = min(values, [], "omitnan");
            stats.max = max(values, [], "omitnan");
            stats.range = stats.max - stats.min;
            stats.median = median(values, "omitnan");
            stats.q25 = app.percentileLocal(values, 25);
            stats.q75 = app.percentileLocal(values, 75);
            stats.iqr = stats.q75 - stats.q25;
            stats.rms = sqrt(mean(values.^2, "omitnan"));
            stats.initial = values(1);
            stats.final = values(end);
            stats.delta = stats.final - stats.initial;

            if isempty(diffValues)
                stats.mean_abs_diff = NaN;
                stats.std_diff = NaN;
                stats.max_abs_diff = NaN;
            else
                stats.mean_abs_diff = mean(abs(diffValues), "omitnan");
                stats.std_diff = std(diffValues, 0, "omitnan");
                stats.max_abs_diff = max(abs(diffValues), [], "omitnan");
            end

            stats.trend_slope_per_sec = app.trendSlope(timeSeconds, values);
            stats.area = trapz(timeSeconds, values);
        end

        function stats = emptyFeatureStats(~)
            stats = struct( ...
                "num_samples", NaN, ...
                "duration_seconds", NaN, ...
                "mean", NaN, ...
                "std", NaN, ...
                "min", NaN, ...
                "max", NaN, ...
                "range", NaN, ...
                "median", NaN, ...
                "q25", NaN, ...
                "q75", NaN, ...
                "iqr", NaN, ...
                "rms", NaN, ...
                "initial", NaN, ...
                "final", NaN, ...
                "delta", NaN, ...
                "mean_abs_diff", NaN, ...
                "std_diff", NaN, ...
                "max_abs_diff", NaN, ...
                "trend_slope_per_sec", NaN, ...
                "area", NaN);
        end

        function [timeSeconds, values] = timeseriesToFiniteVectors(~, ts)
            if isa(ts, "timeseries")
                time = ts.Time(:);
                data = ts.Data;
            elseif istimetable(ts)
                time = ts.Properties.RowTimes;
                data = ts{:, 1};
            else
                error("LeakClassifierApp:UnsupportedSignalType", ...
                    "Expected timeseries or timetable signal data.");
            end

            if isduration(time)
                timeSeconds = seconds(time);
            else
                timeSeconds = double(time);
            end

            values = squeeze(data);
            values = double(values(:));

            finiteIdx = isfinite(timeSeconds) & isfinite(values);
            timeSeconds = timeSeconds(finiteIdx);
            values = values(finiteIdx);

            if numel(timeSeconds) > 1
                [timeSeconds, sortIdx] = sort(timeSeconds);
                values = values(sortIdx);
            end
        end

        function stats = summarizeTimeseries(app, ts)
            [~, values] = app.timeseriesToFiniteVectors(ts);
            if isempty(values)
                stats = struct("mean", NaN, "mean_abs", NaN, ...
                    "final", NaN, "final_abs", NaN);
                return
            end

            stats.mean = mean(values, "omitnan");
            stats.mean_abs = mean(abs(values), "omitnan");
            stats.final = values(end);
            stats.final_abs = abs(values(end));
        end

        function p = percentileLocal(~, values, percentile)
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
            p = values(lowerIdx) + fraction * ...
                (values(upperIdx) - values(lowerIdx));
        end

        function slope = trendSlope(~, timeSeconds, values)
            if numel(values) < 2 || timeSeconds(end) == timeSeconds(1)
                slope = NaN;
                return
            end

            relativeTime = timeSeconds - timeSeconds(1);
            coefficients = polyfit(relativeTime, values, 1);
            slope = coefficients(1);
        end

        function tableData = emptyResultsTable(~)
            tableData = table("No simulation run", "", ...
                'VariableNames', {'Metric', 'Value'});
        end

        function value = roundLeakValue(~, value)
            value = round(value, 1);
        end

        function labelText = formatPrediction(~, predictedLabel)
            switch string(predictedLabel)
                case "none"
                    labelText = "No leak";
                case "segment1"
                    labelText = "Segment 1 leak";
                case "segment2"
                    labelText = "Segment 2 leak";
                case "both"
                    labelText = "Leaks in both segments";
                otherwise
                    labelText = string(predictedLabel);
            end
        end

        function textValue = formatAccuracy(~, accuracy)
            if isnan(accuracy)
                textValue = "Unavailable";
            elseif accuracy <= 1
                textValue = sprintf("%.1f%%", 100 * accuracy);
            else
                textValue = sprintf("%.1f%%", accuracy);
            end
        end

        function setBusy(app, isBusy)
            if isBusy
                app.RunButton.Enable = "off";
                app.RunButton.Text = "Running...";
            else
                app.RunButton.Enable = "on";
                app.RunButton.Text = "Run Simulation";
            end
            drawnow;
        end

        function setStatus(app, message)
            app.StatusText.Value = splitlines(string(message));
        end
    end
end
