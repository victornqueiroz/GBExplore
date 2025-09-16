extends Node2D

# Map logical keys -> sprite nodes in the scene
@onready var _icons := {
	"circle":   $Icon1,
	"triangle": $Icon2,
	"square":   $Icon3,
}

# Unlit / lit textures per key
const _DARK := {
	"circle":   "res://art/icon1-circle.png",
	"triangle": "res://art/icon2-triangle.png",
	"square":   "res://art/icon3-square.png",
}
const _LIT := {
	"circle":   "res://art/icon1-circle-lit.png",
	"triangle": "res://art/icon2-triangle-lit.png",
	"square":   "res://art/icon3-square-lit.png",
}

func _ready() -> void:
	# Initialize from persisted state (so they stay lit if you re-enter the room)
	for key in _icons.keys():
		_apply_icon(key, RunState.button_is_active(key))

	# Live updates when any button changes
	if not RunState.is_connected("button_state_changed", _on_button_state_changed):
		RunState.button_state_changed.connect(_on_button_state_changed)

func _on_button_state_changed(key: String, active: bool) -> void:
	if _icons.has(key):
		_apply_icon(key, active)

func _apply_icon(key: String, active: bool) -> void:
	var node = _icons.get(key, null)
	if node == null:
		return
	var path = (_LIT[key] if active else _DARK[key])
	var tex := load(path)
	if tex:
		node.texture = tex
