extends Area2D

signal pressed(key: String, idx: int)
signal released(key: String, idx: int)

@export var button_key: String = ""                 # group key, e.g. "triangle"
@export var tile: Vector2i = Vector2i.ZERO          # used for default instance id
@export var one_shot: bool = true                   # stays down once pressed
@export var auto_deactivate_on_exit: bool = false   # for hold-to-press puzzles
@export var puzzle_index: int = 0                   # optional label (1..N)
@export var instance_id: String = ""                # optional explicit instance id

@onready var _sprite_idle: Sprite2D    = get_node_or_null("SpriteIdle")
@onready var _sprite_pressed: Sprite2D = get_node_or_null("SpritePressed")
@onready var _sprite_legacy: Sprite2D  = get_node_or_null("Sprite2D")

var _already_triggered: bool = false   # per-plate, for one_shot behavior

func _ready() -> void:
	# Restore latched visual from per-instance persistence
	var down := RunState.button_instance_is_down(_resolved_instance_id())
	_already_triggered = down   # if it was down before, treat as already triggered
	_apply_state(down)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _resolved_instance_id() -> String:
	if instance_id != "":
		return instance_id
	var room_path := get_tree().current_scene.scene_file_path
	return "%s|%d,%d|%s" % [room_path, tile.x, tile.y, (button_key if button_key != "" else "_")]

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if one_shot and _already_triggered:
		return

	var iid := _resolved_instance_id()

	# If this plate is not yet down, press it now
	if not RunState.button_instance_is_down(iid):
		RunState.button_instance_set_down(iid, true)
		if button_key != "":
			RunState.button_group_add(button_key, +1)  # increment group pressed count
		_apply_state(true)
		pressed.emit(button_key, puzzle_index)

	if one_shot:
		_already_triggered = true

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	# Only auto-release if configured for hold-to-press puzzles
	if auto_deactivate_on_exit:
		var iid := _resolved_instance_id()
		if RunState.button_instance_is_down(iid):
			RunState.button_instance_set_down(iid, false)
			if button_key != "":
				RunState.button_group_add(button_key, -1)  # decrement group pressed count
			_apply_state(false)
			released.emit(button_key, puzzle_index)
			# In auto mode, allow re-triggering again even if one_shot
			if one_shot:
				_already_triggered = false

func _apply_state(active: bool) -> void:
	# Two-sprite setup preferred
	if _sprite_idle or _sprite_pressed:
		if _sprite_idle:
			_sprite_idle.visible = not active
		if _sprite_pressed:
			_sprite_pressed.visible = active
		return
	# Legacy single sprite fallback
	if _sprite_legacy:
		_sprite_legacy.position.y = (1 if active else 0)
		_sprite_legacy.modulate = (Color(0.8, 1.0, 0.8, 1.0) if active else Color(1, 1, 1, 1))

# Optional manual reset (e.g., puzzle controller)
func deactivate() -> void:
	var iid := _resolved_instance_id()
	if RunState.button_instance_is_down(iid):
		RunState.button_instance_set_down(iid, false)
		if button_key != "":
			RunState.button_group_add(button_key, -1)
	_apply_state(false)
	_already_triggered = false
