**Implementation Plan: Leak Classifier App**

**Path:** UIFigure app
**Layout:** Explorer - a stable left control panel for leak inputs and a
right results panel for simulation status, measured outputs, and leak-source
classification.

**Structure:**
- Top header with the app title and model name.
- Left control panel with two leak-flow controls, each using a slider and
  numeric edit field constrained to 0-100 gpm.
- Left control panel action row with a Run Simulation button.
- Right results panel with a predicted-condition text field, a status lamp,
  a validation-accuracy field, and a compact table of measured leak-flow
  and pump outlet summary values.
- Bottom status area with the latest simulation message or error.

**Key behaviors:**
- Users select nominal leak flow for segment 1 and segment 2 in gpm.
- The Run Simulation button maps 0-100 gpm to the model's normalized
  `leak1_opening` and `leak2_opening` variables, then runs
  `pipeline_with_pump_leaks` through `Simulink.SimulationInput`.
- Simulation output is converted into the same pump outlet flow and pressure
  feature variables used by `trainClassifier.m`.
- The app predicts `none`, `segment1`, `segment2`, or `both` using
  `trainedClassifier.predictFcn`.
- The lamp is green only when the predicted class is `none`; otherwise it is
  red.

**Internal references that will be used:**

| Reference | Role in this app |
|-----------|------------------|
| `references/archetypes/explorer.md` | Establishes the control-left/results-right interaction pattern. |
| `references/uifigure/guide.md` | Defines UIFigure structure and grid-based layout basics. |
| `references/uifigure/components.md` | Confirms component choices for sliders, numeric fields, tables, labels, buttons, and lamps. |
| `references/uifigure/callbacks.md` | Defines callback/data-sharing patterns for the Run Simulation action. |
| `references/uifigure/layout-patterns.md` | Provides the sidebar/content layout pattern. |

**External skills:**
- `simulating-simulink-models` - used for the `SimulationInput`/`sim` workflow
  and logged-output extraction.

**File organization:**

```text
LeakClassifierApp.m
leak-classifier-app-plan.md
```

**Implementation sequence:**
1. Read the Explorer and UIFigure references to establish the layout and
   callback pattern.
2. Create `LeakClassifierApp.m` as a programmatic UIFigure app.
3. Implement startup path handling for `Data`, `Scripts`, and `Simulations`.
4. Load `trainedClassifier` from a MAT file when available; otherwise train it
   from `Data/trainingFeatures.mat` using `trainClassifier`.
5. Implement `SimulationInput` setup with finite stop time and leak variables.
6. Extract `pump_outlet_flow_gpm`, `pump_outlet_pressure_psi`, `leak1_gpm`,
   and `leak2_gpm` from simulation output.
7. Generate one-row feature tables with variable names matching
   `trainedClassifier.RequiredVariables`.
8. Update the predicted condition, lamp color, summary table, and status text
   after each simulation.
