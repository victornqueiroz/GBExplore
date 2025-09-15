extends Area2D

signal pressed(key: String, idx: int)
signal released(key: String, idx: int)

@export var button_key: String = ""
@export var tile: Vector2i = Vector2i.ZERO
@export var one_shot: bool = true
@export var auto_deactivate_on_exit: bool = false   # NEW: turn on for Altair room
@export var puzzle_index: int = 0                   # NEW: 1..5 label used by the puzzle

@onready var _sprite_idle: Sprite2D    = get_node_or_null("SpriteIdle")
@onready var _sprite_pressed: Sprite2D = get_node_or_null("SpritePressed")
@onready var _sprite_legacy: Sprite2D  = get_node_or_null("Sprite2D")

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)  # NEW
	_apply_state(RunState.button_is_active(_resolved_key()))

func _resolved_key() -> String:
	if button_key != "":
		return button_key
	var room_path := get_tree().current_scene.scene_file_path
	return "%s|%s" % [room_path, tile]

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var key := _resolved_key()
	if not RunState.button_is_active(key):
		RunState.button_set_active(key, true)
		_apply_state(true)
	pressed.emit(key, puzzle_index)
	if one_shot:
		monitoring = false

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if auto_deactivate_on_exit:
		var key := _resolved_key()
		RunState.button_clear(key)
		_apply_state(false)
		released.emit(key, puzzle_index)
		# allow re-press
		if one_shot:
			monitoring = true

func _apply_state(active: bool) -> void:
	# Two-sprite layout
	if _sprite_idle or _sprite_pressed:
		if _sprite_idle:    _sprite_idle.visible = not active
		if _sprite_pressed: _sprite_pressed.visible = active
		return
	# Legacy single-sprite fallback
	if _sprite_legacy:
		_sprite_legacy.position.y = (1 if active else 0)
		_sprite_legacy.modulate = (Color(0.8, 1.0, 0.8, 1.0) if active else Color(1, 1, 1, 1))

# Optional helper if you want manual resets elsewhere
func deactivate() -> void:
	RunState.button_clear(_resolved_key())
	_apply_state(false)
	monitoring = true
