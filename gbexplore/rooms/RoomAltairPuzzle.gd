# res://rooms/RoomAltairPuzzle.gd
extends Node

@export var expected: Array[int] = [1, 3, 1, 5, 5, 4, 2]
var _pos: int = 0

func _ready() -> void:
	print("AltairPuzzle ready")
	# This will work if buttons are already in the scene (e.g., placed in editor).
	# ScreenManager will call connect_buttons() again after it spawns them.
	call_deferred("connect_buttons")

func connect_buttons() -> void:
	var room := get_parent()
	if room == null:
		return

	var buttons := room.find_children("", "Area2D", true, false)
	var connected := 0
	for n in buttons:
		if n.has_signal("pressed") and not n.pressed.is_connected(_on_button_pressed):
			n.pressed.connect(_on_button_pressed)
			connected += 1
	print("AltairPuzzle connected ", connected, " buttons")

func _on_button_pressed(_key: String, idx: int) -> void:
	if _pos < expected.size() and idx == expected[_pos]:
		_pos += 1
		print("[Altair] Step ", _pos, " / ", expected.size(), " — pressed ", idx)
		if _pos == expected.size():
			print("[Altair] ✅ CORRECT SEQUENCE!")
			_on_solved()
	else:
		var exp := expected[_pos] if _pos < expected.size() else -1
		print("[Altair] ❌ wrong (got ", idx, ", expected ", exp, "), resetting")
		_pos = 0

func _on_solved() -> void:
	# TODO: open a door, reward, etc.
	_pos = 0
