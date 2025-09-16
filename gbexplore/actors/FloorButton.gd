# actors/FloorButton.gd
extends Area2D

signal pressed(key: String, idx: int)
signal released(key: String, idx: int)

@export var button_key: String = ""                 # e.g. "circle", "triangle", "square"
@export var tile: Vector2i = Vector2i.ZERO          # used for auto-key fallback
@export var one_shot: bool = true                   # latches ON once pressed
@export var auto_deactivate_on_exit: bool = false   # for non-latching puzzles (Altair)
@export var puzzle_index: int = 0                   # optional label (1..N)

@onready var _sprite_idle: Sprite2D    = get_node_or_null("SpriteIdle")
@onready var _sprite_pressed: Sprite2D = get_node_or_null("SpritePressed")
@onready var _sprite_legacy: Sprite2D  = get_node_or_null("Sprite2D")

func _ready() -> void:
	# Ensure we reflect persisted state the moment we spawn
	var active := RunState.button_is_active(_resolved_key())
	_apply_state(active)

	# Basic triggers
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _resolved_key() -> String:
	# Prefer explicit key so rooms can share persistence across copies/loads
	if button_key != "":
		return button_key
	# Fallback: unique per-room, per-tile key
	var room_path := get_tree().current_scene.scene_file_path
	return "%s|%s" % [room_path, tile]

func _on_body_entered(body: Node) -> void:
	# Only the player should trigger
	if not body.is_in_group("player"):
		return

	var key := _resolved_key()

	# If already active and it's a latching button, ignore re-presses
	if one_shot and RunState.button_is_active(key):
		return

	# Set ON (RunState will emit button_state_changed if it actually changed)
	RunState.button_set_active(key, true)
	_apply_state(true)
	pressed.emit(key, puzzle_index)

	# For one_shot buttons, stop detecting until we’re reset manually
	if one_shot:
		monitoring = false

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	# Non-latching mode: turn OFF when the player steps off
	if auto_deactivate_on_exit:
		var key := _resolved_key()
		if RunState.button_is_active(key):
			RunState.button_set_active(key, false)  # preserves signal semantics
		_apply_state(false)
		released.emit(key, puzzle_index)

		# Allow re-press if this button is also marked one_shot
		if one_shot:
			monitoring = true

func _apply_state(active: bool) -> void:
	# Preferred: two-sprite (Idle/Pressed)
	if _sprite_idle or _sprite_pressed:
		if _sprite_idle:
			_sprite_idle.visible = not active
		if _sprite_pressed:
			_sprite_pressed.visible = active
		return

	# Fallback: single sprite nudge + tint
	if _sprite_legacy:
		_sprite_legacy.position.y = (1 if active else 0)
		_sprite_legacy.modulate = (Color(0.8, 1.0, 0.8, 1.0) if active else Color(1, 1, 1, 1))

# Optional public reset (e.g., puzzle scripts can call this)
func deactivate() -> void:
	var key := _resolved_key()
	if RunState.button_is_active(key):
		RunState.button_set_active(key, false)
	_apply_state(false)
	monitoring = true
