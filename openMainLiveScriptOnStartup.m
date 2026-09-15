%% Open the main live script when the MATLAB project starts
projectRoot = fileparts(mfilename("fullpath"));
liveScript = fullfile(projectRoot, "Scripts", "main_live_script.mlx");

if isfile(liveScript)
    open(liveScript);
else
    warning("PipelineDesign:MissingLiveScript", ...
        "Could not find the main live script: %s", liveScript);
end
