extends Node
## Flip this to false for a clean release build.
var DEV_MODE := false

## Debug visuals for edge walls (only if DEV_MODE is true)
var SHOW_EDGE_WALLS := true

## Edge-wall defaults (you can tweak here, no code changes needed)
var EDGE_INSET := 0
var EDGE_THICK := 1
var EDGE_OVERHANG := 1.0
var EDGE_COLOR := Color(1, 0.2, 0.2, 0.45)  # translucent red
var EDGE_Z := 100

## Collision layers/masks for walls (must match your Player)
var WALL_LAYER := 1
var WALL_MASK := 1
