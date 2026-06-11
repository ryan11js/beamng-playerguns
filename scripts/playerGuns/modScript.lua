-- GE extensions: input poll + crosshair/aim ray + telemetry recorder.
load('extensions.playerGuns/input')
load('extensions.playerGuns/aim')
load('extensions.playerGuns/telemetry')
setExtensionUnloadMode('playerGuns/input', 'manual')
setExtensionUnloadMode('playerGuns/aim', 'manual')
setExtensionUnloadMode('playerGuns/telemetry', 'manual')
