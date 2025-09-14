extends Area2D

@export var button_key: String = ""
@export var tile: Vector2i = Vector2i.ZERO
@export var one_shot: bool = true

@onready var _sprite_idle: Sprite2D    = get_node_or_null("SpriteIdle")
@onready var _sprite_pressed: Sprite2D = get_node_or_null("SpritePressed")
@onready var _sprite_legacy: Sprite2D  = get_node_or_null("Sprite2D") # legacy single-sprite

func _ready() -> void:
	body_entered.connect(_on_body_entered)
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
	if RunState.button_is_active(key):
		return
	RunState.button_set_active(key, true)
	_apply_state(true)
	if one_shot:
		monitoring = false

func _apply_state(active: bool) -> void:
	# Two-sprite layout (recommended)
	if _sprite_idle or _sprite_pressed:
		if _sprite_idle:
			_sprite_idle.visible = not active
		if _sprite_pressed:
			_sprite_pressed.visible = active
		return

	# Legacy single-sprite layout (safe checks)
	if _sprite_legacy:
		_sprite_legacy.position.y = (1 if active else 0)
		_sprite_legacy.modulate = (Color(0.8, 1.0, 0.8, 1.0) if active else Color(1, 1, 1, 1))
