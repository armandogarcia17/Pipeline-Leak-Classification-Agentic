# Pipeline Design Demo Overview

This repository contains a MATLAB and Simulink demo for pipeline sizing and
pump-system simulation using Simscape Fluids. The main reference is
`Design/Pipeline Design Demo.docx`.

## Design Reference

The design document frames the demo around these requirements and assumptions:

- Fluid: water
- Required operating flow rate: 50,000 bbl/day
- Maximum allowable operating pressure: 1550 psi
- Pipeline outlet pressure: 100 psi
- Pump control: variable frequency drive (VFD)
- Selected pipeline outside diameter: 10 in
- Pump operating point: 1215 gpm at 1049 psi
- Unit conversion used in the design: 1 bbl/day = 0.024287 gpm
- Booster pump assumption: supplies fluid to the main pump at 100 psi
- Pump efficiency assumption: 70%
- Estimated pump power:

```text
HP = (1215 * 1049) / (1714 * 0.7) = 1063 hp
```

The design document states that system curves were generated with
MATLAB/Simscape, including hydrostatic pressure calculated by the software.
The system-curve result points to a 10 in pipeline as the preferred choice.

## Repository Layout

- `pipeline-design-with-matlab-and-simulink.prj` defines the MATLAB project.
- `Design/` contains the Word design reference and a PowerPoint pipeline sketch.
- `Data/` contains pump and curve data used by the model and supporting design
  material.
- `Figures/` contains the generated system-curve plot.
- `Simulations/` contains the active Simulink model and leak-analysis variant.
- `resources/project/` contains MATLAB project metadata.

## Main Simulink Model

The active model is:

```text
Simulations/pipeline_with_pump.slx
```

At the top level, the model contains:

- `Reservoir`
- `PumpSystem`
- `Controller`
- two thermal-liquid pipe segments
- two check valves
- `SensorStation1`
- `SensorStation2`
- displays and dashboard scopes for pump and pipeline behavior

The top-level outports are:

- `q1`
- `P1`
- `T1`
- `q2`
- `P2`
- `T2`

These expose flow rate, pressure, and temperature at the two sensor stations.

## Leak Simulation Model

The leak-analysis variant is:

```text
Simulations/pipeline_with_pump_leaks.slx
```

This model extends `pipeline_with_pump.slx` to simulate independent leaks in
either pipeline segment. Each original 15 mi pipe segment is split into two
7.5 mi thermal-liquid pipe blocks with a leak branch at the midpoint:

- `PipeSegment1A` and `PipeSegment1B`
- `PipeSegment2A` and `PipeSegment2B`

Each leak branch contains:

- a `Flow Coefficient Parameterized Valve (TL)` block
- a `Flow Rate Sensor (TL)` block
- a `Reservoir (TL)` block representing the external leak sink
- a `PS-Simulink Converter` that reports leak flow rate in gpm

The valve openings are independently controlled by model workspace variables:

```matlab
leak1_opening = 0;
leak2_opening = 0;
leak1_Cv_max = 1;
leak2_Cv_max = 1;
leak_reservoir_pressure = 14.7; % psi
```

`leak1_opening` and `leak2_opening` are normalized valve-opening commands.
A value of 0 closes the corresponding leak path, and a value near 1 opens it.
`leak1_Cv_max` and `leak2_Cv_max` tune leak severity.

The leak model has the original six root outports plus two leak-flow outports:

- `q1`
- `P1`
- `T1`
- `q2`
- `P2`
- `T2`
- `leak1_gpm`
- `leak2_gpm`

The model can simulate:

- no leaks, with both leak openings set to 0
- a leak in pipeline segment 1 only
- a leak in pipeline segment 2 only
- simultaneous leaks with different valve openings or flow coefficients

Example scripted setup for a segment 1 leak:

```matlab
model = "pipeline_with_pump_leaks";
in = Simulink.SimulationInput(model);
in = in.setModelParameter("StopTime", "10");
in = in.setVariable("leak1_opening", 1, "Workspace", model);
in = in.setVariable("leak2_opening", 0, "Workspace", model);
out = sim(in);
```

## Model Parameters

The model preload callback loads pump data and defines the main pipeline
parameters:

```matlab
load("pump_data.mat");

D = (10/12)/3.281; % m
initPres = 100;    % psi
Ap = pi*D^2/4;
```

This gives:

- Pipeline diameter: about 0.254 m, equivalent to 10 in
- Outlet/reference pressure: 100 psi
- Pipe/pump cross-sectional area: about 0.0507 m^2

The two pipe blocks use:

- `pipe_diameter = D`
- `pipe_length = 15`

The outlet reservoir uses:

- `reservoir_pressure = initPres + 14.7`
- pressure unit: psi

The model configuration currently uses a variable-step solver and has
`StopTime = Inf`, so scripted runs should set a finite stop time explicitly.

## Controller

The controller targets the design flow rate:

```text
setpoint = 50000
```

The pump flow-rate feedback is converted from gpm to bbl/day with a gain of:

```text
34.285714286
```

The controller uses a PID Controller block configured effectively as integral
control:

- `P = 0`
- `I = 0.015`
- `D = 0`
- lower output saturation: 0
- upper output saturation: 1950

The controller also has an override-speed path. The override speed constant is:

```text
3540 rpm
```

## Pump System

`PumpSystem` wraps the main Simscape pump and related instrumentation. It
contains:

- a Centrifugal Pump (TL) block
- a flow-rate sensor
- pressure and temperature sensing
- an ideal torque source
- an ideal torque sensor
- a lookup table that maps speed to torque

The centrifugal pump is parameterized from 2-D pump data:

- flow-rate table: `pump_data.rate`
- speed table: `pump_data.speed`
- head table: `pump_data.head`
- power table: `pump_data.brake_hp`

The pump data speed vector is:

```text
600, 1200, 1500, 2200, 2800, 3540 rpm
```

## Data Files

`Data/curveData.csv` contains Flowserve pump-curve data with columns for:

- capacity
- rated head
- NPSH
- efficiency
- min/max head
- power
- speed-specific head curves

`Data/pump_data.mat` contains a `pump_data` struct with:

- `head`
- `brake_hp`
- `rate`
- `speed`
- `torque_speed`

`Data/pump_curves.mat` contains processed arrays:

- `brake_hp_curve`
- `pump_head_curves`
- `speed`
- `torque_vs_speed`

The PDF in `Data/` is a Flowserve hydraulic datasheet. Extracted highlights:

- Pump size/type: 6WXB-12A
- Rated capacity: 1250 USgpm
- Total developed head: 3000 ft
- Pump speed: 3540 rpm
- Liquid: fresh water
- Maximum allowable casing working pressure: 1885.5 psig

## Figures And Presentation Assets

`Figures/System Curves.svg` is the generated system-curve plot. The plot uses:

- x-axis: flow rate in thousands of bbl/day
- y-axis: pump pressure in psig
- diameter curves including 8 in, 10 in, and 16 in

`Design/Pipeline Model.pptx` contains a simple pipeline profile sketch with:

- 750 ft elevation reference
- two 15 mi pipeline sections
- outlet pressure of 100 psi
- several temperature annotations

## Validation Notes

The active Simulink model was structurally checked for:

- unconnected ports
- unconnected lines
- Stateflow lint issues

The model passed these structural checks.

The leak-analysis model was also structurally checked after adding the
parameterized valve leak branches. It passed checks for unconnected ports,
unconnected lines, and Stateflow lint issues. Verification simulations showed:

- closed leak valves produce near-zero `leak1_gpm` and `leak2_gpm`
- opening segment 1 produces `leak1_gpm` while `leak2_gpm` stays near zero
- opening segment 2 produces `leak2_gpm` while `leak1_gpm` stays near zero

## Synthetic Leak Data Generation

Synthetic data for leak-source machine learning is generated from:

```text
Scripts/generate_synthetic_leak_data.m
```

The script runs `Simulations/pipeline_with_pump_leaks.slx` across a
full-factorial two-leak sweep so the dataset includes the interaction between
leaks in both pipeline sections. By default, both nominal leak severities vary
from 0 to 100 gpm in 10 gpm increments:

```matlab
opts.LeakRateGridGpm = 0:10:100;
```

This produces no-leak, segment 1 leak, segment 2 leak, and simultaneous-leak
cases. The manifest labels these cases as:

- `none`
- `segment1`
- `segment2`
- `both`

The model leak inputs are normalized valve openings rather than direct flow
commands, so the script maps each nominal 0-100 gpm leak severity to a 0-1
valve-opening command. The actual leak flow rates are still taken from the
model outputs `leak1_gpm` and `leak2_gpm`, because simultaneous leaks can
change the realized flow through each leak branch.

Each scenario saves one raw MATLAB data file under:

```text
synthetic_leak_data/<run_timestamp>/
```

The saved `sample` struct contains:

- metadata for the scenario, including nominal leak severities and leak-source
  label
- raw time series for pump outlet flow and pump outlet pressure
- raw time series for sensor station flow, pressure, and temperature outputs
- raw time series for `leak1_gpm` and `leak2_gpm`
- summary statistics over the final steady-state window

The sweep also writes:

```text
sweep_manifest.csv
sweep_manifest.mat
```

The manifest records each scenario ID, nominal leak severities, valve openings,
source label, simulation status, output file path, actual measured leak-flow
summaries, elapsed runtime, and any simulation error message.

The script uses `parsim` by default so multiple CPU cores can run scenarios in
parallel. It also includes safeguards for unstable simulations:

- finite stop time is forced for every scenario
- solver minimum-step warnings are promoted to errors
- `StopOnError` is disabled so one failed scenario does not stop the sweep
- failed scenarios are recorded in the manifest
- background parallel runs use a watchdog that cancels the batch if simulations
  stop making progress or exceed the batch timeout

Two short validation runs were created while developing the workflow:

```text
synthetic_leak_data/smoke_validation/
synthetic_leak_data/parallel_smoke_validation/
```

Both validation runs completed a no-leak scenario and measured near-zero leak
flow at both leak outputs.

## Leak Classification Training

A Classification Learner App export is available at:

```text
Scripts/trainClassifier.m
```

The function trains a leak-source classifier from the synthetic feature table
created by:

```text
Scripts/prepare_leak_training_features.m
```

The expected input is a MATLAB table with the response variable:

```text
leak_source
```

The response classes are:

- `none`
- `segment1`
- `segment2`
- `both`

The model uses statistical predictors extracted only from:

- `pump_outlet_flow_gpm`
- `pump_outlet_pressure_psi`

The nominal leak-rate variables `nominal_leak1_gpm` and
`nominal_leak2_gpm` are retained in the feature table for traceability, but
they are not used as predictors by `trainClassifier.m`.

The exported classifier is a multiclass error-correcting output codes model
trained with one-vs-one coding and linear SVM learners:

```matlab
template = templateLinear('Learner', 'SVM', ...
    'Lambda', 'auto', ...
    'BetaTolerance', 0.0001);

classificationLinear = fitcecoc(predictors, response, ...
    'Learners', template, ...
    'Coding', 'onevsone', ...
    'ClassNames', classNames);
```

The function returns:

- `trainedClassifier`, a struct with `predictFcn`, `RequiredVariables`,
  `ClassificationLinear`, `About`, and `HowToPredict`
- `validationAccuracy`, computed using 5-fold cross-validation

Example training workflow:

```matlab
load("synthetic_leak_data/20260915_123012/leak_training_feature_table.mat");
[trainedClassifier, validationAccuracy] = ...
    trainClassifier(trainingFeatureTable);
```

Predictions on a compatible feature table can be made with:

```matlab
[predictedLeakSource, scores] = ...
    trainedClassifier.predictFcn(newFeatureTable);
```

## Leak Classifier App

A programmatic UIFigure app was added at:

```text
LeakClassifierApp.m
```

The app provides an interactive workflow for leak-classification demos:

- segment 1 and segment 2 leak-flow controls from 0 to 100 gpm
- a Run Simulation button that simulates
  `Simulations/pipeline_with_pump_leaks.slx` with the selected leak settings
- feature extraction from the simulated `pump_outlet_flow_gpm` and
  `pump_outlet_pressure_psi` signals
- prediction through the exported `trainedClassifier.predictFcn`
- a lamp indicator that is green for the predicted `none` class and red for
  `segment1`, `segment2`, or `both`
- a summary table showing selected leak values, measured leak-flow outputs,
  pump outlet summaries, and simulation elapsed time

Launch the app from the project root with:

```matlab
app = LeakClassifierApp;
```

The app looks for `trainedClassifier` in the MATLAB base workspace first. If
it is not present, it looks for `Data/trainedClassifier.mat` or
`trainedClassifier.mat`. If no saved classifier is available, it trains one
from `Data/trainingFeatures.mat` using `Scripts/trainClassifier.m`.

The app uses the same statistical feature names expected by
`trainedClassifier.RequiredVariables`, so it can classify newly simulated
scenarios without writing intermediate files. The simulation defaults match
the synthetic-data workflow where relevant:

```matlab
StopTime = 10;
MaxLeakFlowGpm = 100;
LeakCvMax = 3.5;
LeakReservoirPressurePsi = 14.7;
```

Validation performed during app creation:

- MATLAB Code Analyzer reported no issues for `LeakClassifierApp.m`.
- App construction succeeded.
- A no-leak smoke simulation predicted `none`.
- A leak smoke simulation produced a non-`none` prediction, exercising the
  red-lamp path.

Observed classifier behavior: the exported classifier reports about 96.4%
validation accuracy when retrained from `Data/trainingFeatures.mat`, but a
100 gpm segment 1 scenario is predicted as `both` even when evaluated on the
original training row labeled `segment1`. The app uses the exported classifier
as-is, so this behavior reflects the trained model rather than the UI wiring.

The app implementation plan is recorded in:

```text
leak-classifier-app-plan.md
```

## Demo Flow

A likely walkthrough sequence is:

1. Start from the design requirements in `Design/Pipeline Design Demo.docx`.
2. Show the system curves in `Figures/System Curves.svg`.
3. Explain why the 10 in pipe was selected for the required 50,000 bbl/day
   operating point.
4. Show the Flowserve pump data in `Data/curveData.csv` and the processed
   MATLAB pump data files.
5. Open `Simulations/pipeline_with_pump.slx`.
6. Walk through the reservoir, pump system, two pipe segments, sensor stations,
   and flow-rate controller.
7. Run the model with a finite stop time and inspect flow rate, pressure, and
   temperature at both sensor stations.
8. Open `Simulations/pipeline_with_pump_leaks.slx` to demonstrate independent
   leak simulation in either pipeline segment.
9. Vary `leak1_opening` and `leak2_opening` to compare no-leak, segment 1
   leak, segment 2 leak, and simultaneous-leak cases.
10. Run `Scripts/generate_synthetic_leak_data.m` to create labeled synthetic
    data for leak-source machine-learning experiments.
11. Run `Scripts/prepare_leak_training_features.m`, then call
    `Scripts/trainClassifier.m` to train and validate the leak-source
    classification model.
12. Launch `LeakClassifierApp.m` to vary leak flows interactively, simulate
    the leak model, classify the simulated condition, and show the lamp status.
