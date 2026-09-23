[![Open in MATLAB Online](https://www.mathworks.com/images/responsive/global/open-in-matlab-online.svg)](https://matlab.mathworks.com/open/github/v1?repo=armandogarcia17/Pipeline-Leak-Classification-Agentic)

<img width="3505" height="1268" alt="readme image" src="https://github.com/user-attachments/assets/b29849df-1de4-4829-a492-bc958596c31a" />

# Pipeline Design with MATLAB and Simulink

This project demonstrates a leak-classification workflow
using MATLAB, Simulink, Simscape Fluids, and machine learning. The main live
script, `main_live_script.mlx`, walks through the workflow from model
understanding to synthetic data generation, feature extraction, classifier
training, and app-based deployment.

The engineering scenario is a water pipeline sized for a target operating flow
of 50,000 bbl/day. The Simulink model is used first as a virtual plant, then as
a synthetic data source for training a leak-source classifier.

## First Steps

Open the MATLAB project from the repository root:

```matlab
openProject("pipeline-design-with-matlab-and-simulink.prj")
```

## Requirements

The demo is intended for MATLAB R2026a and uses:

- Simulink
- Simscape
- Simscape Fluids
- Statistics and Machine Learning Toolbox
- Parallel Computing Toolbox, optional, for faster synthetic-data sweeps

The live script also demonstrates an agent-assisted workflow using the MATLAB
MCP Server and the MATLAB and Simulink Agentic Toolkits. Those tools are useful
for recreating the development process, but the project files can still be
inspected and run directly in MATLAB.

