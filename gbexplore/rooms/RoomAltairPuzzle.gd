# res://rooms/RoomAltairPuzzle.gd
extends Node

@export var expected: Array[int] = [1, 3, 4, 2, 5]  # final order
var _pressed_order: Array[int] = []
var _pressed_set := {}                  # acts like a Set<int>
var _buttons_by_idx := {}               # idx -> Area2D (FloorButton)
var _solved_once: bool = false
const GROUP_KEY := "square"

# Track "reset after leave last plate" flow
var _pending_reset: bool = false
var _last_pressed_idx: int = -1
var _last_pressed_button: Area2D = null

func _ready() -> void:
	print("AltairPuzzle ready")
	call_deferred("connect_buttons")

func connect_buttons() -> void:
	var room := get_parent()
	if room == null:
		return

	var buttons := room.find_children("", "Area2D", true, false)
	var connected := 0
	_buttons_by_idx.clear()

	for n in buttons:
		# Make sure these plates latch and don't release on exit
		# (We assume these are FloorButton instances)
		if "one_shot" in n:
			n.one_shot = true
		if "auto_deactivate_on_exit" in n:
			n.auto_deactivate_on_exit = false

		# Track by puzzle_index so we can reset later
		var idx := 0
		if "puzzle_index" in n:
			idx = int(n.puzzle_index)
		if idx > 0:
			_buttons_by_idx[idx] = n

		# Connect once
		if n.has_signal("pressed") and not n.pressed.is_connected(_on_button_pressed):
			n.pressed.connect(_on_button_pressed)
			connected += 1

	print("AltairPuzzle connected ", connected, " buttons")

func _on_button_pressed(_key: String, idx: int) -> void:
	# ignore duplicate presses in a single attempt
	if _pressed_set.has(idx):
		return

	_pressed_set[idx] = true
	_pressed_order.append(idx)
	_last_pressed_idx = idx
	_last_pressed_button = _buttons_by_idx.get(idx, null)
	print("[Altair] pressed idx=", idx, " → ", _pressed_order)

	# When we have all 5 pressed, decide if we should arm a deferred reset
	if _pressed_order.size() == expected.size():
		if _is_correct_order():
			print("[Altair] ✅ CORRECT SEQUENCE!")
			_on_solved()
		else:
			print("[Altair] ❌ WRONG ORDER → ", _pressed_order, " (expected ", expected, ")")
			# Arm "reset after leaving the last plate"
			_arm_reset_on_last_plate_exit()

func _is_correct_order() -> bool:
	if _pressed_order.size() != expected.size():
		return false
	for i in expected.size():
		if _pressed_order[i] != expected[i]:
			return false
	return true

func _arm_reset_on_last_plate_exit() -> void:
	_pending_reset = true

	# Listen only to the last-pressed plate's body_exited (Area2D signal)
	# so reset happens when the player steps off that plate.
	if _last_pressed_button and not _last_pressed_button.body_exited.is_connected(_on_last_plate_body_exited):
		_last_pressed_button.body_exited.connect(_on_last_plate_body_exited)

func _on_last_plate_body_exited(body: Node) -> void:
	# Only reset if we were waiting AND it's the player stepping off
	if not _pending_reset:
		return
	if not body.is_in_group("player"):
		return

	_pending_reset = false

	# Disconnect the temporary listener
	if _last_pressed_button and _last_pressed_button.body_exited.is_connected(_on_last_plate_body_exited):
		_last_pressed_button.body_exited.disconnect(_on_last_plate_body_exited)
	_last_pressed_button = null
	_last_pressed_idx = -1

	_reset_buttons()

func _on_solved() -> void:
	if not _solved_once:
		_solved_once = true
		if RunState.button_group_count(GROUP_KEY) < 1:
			RunState.button_group_add(GROUP_KEY, +1)
	# Keep plates down as success confirmation
	_clear_tracking_only()
	# If we were waiting to reset on exit for some reason, cancel it
	_pending_reset = false
	if _last_pressed_button and _last_pressed_button.body_exited.is_connected(_on_last_plate_body_exited):
		_last_pressed_button.body_exited.disconnect(_on_last_plate_body_exited)
	_last_pressed_button = null
	_last_pressed_idx = -1

func _reset_buttons() -> void:
	# Raise all pressed plates this attempt
	for idx in _pressed_order:
		var b = _buttons_by_idx.get(idx, null)
		if b and b.has_method("deactivate"):
			b.deactivate()
	_clear_tracking_only()

func _clear_tracking_only() -> void:
	_pressed_order.clear()
	_pressed_set.clear()
