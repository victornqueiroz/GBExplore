extends Node2D

@onready var _icons := {
	"circle":   $Icon1,
	"triangle": $Icon2,
	"square":   $Icon3,
}

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
	# Initialize from persisted GROUP COUNTS so presses in other rooms are respected
	for key in _icons.keys():
		_apply_icon(key, _is_key_lit(key))

	# Live updates when any group's count changes
	if not RunState.is_connected("button_state_changed", _on_button_state_changed):
		RunState.button_state_changed.connect(_on_button_state_changed)

func _on_button_state_changed(key: String, _active: bool) -> void:
	# key here is the GROUP key (e.g. "triangle") emitted by button_group_add()
	if _icons.has(key):
		_apply_icon(key, _is_key_lit(key))

func _is_key_lit(key: String) -> bool:
	# Use group counts for all icons (works for 1-or-more and thresholded cases)
	var count := RunState.button_group_count(key)
	match key:
		"triangle":
			return count >= 3   # ← require 3 pressed anywhere
		_:
			return count >= 1   # circle/square light if at least one is pressed

func _apply_icon(key: String, active: bool) -> void:
	var node = _icons.get(key, null)
	if node == null:
		return
	var path = (_LIT[key] if active else _DARK[key])
	var tex := load(path)
	if tex:
		node.texture = tex
