extends Area2D

signal pressed(key: String, idx: int)
signal released(key: String, idx: int)

@export var button_key: String = ""                 # group key, e.g. "triangle"
@export var tile: Vector2i = Vector2i.ZERO
@export var one_shot: bool = true
@export var auto_deactivate_on_exit: bool = false
@export var puzzle_index: int = 0
@export var instance_id: String = ""

# NEW: visual style + optional texture overrides
@export var style: String = ""                      # "", "triangle", etc.
@export var idle_texture: Texture2D                 # optional override
@export var pressed_texture: Texture2D              # optional override

@onready var _sprite_idle: Sprite2D    = get_node_or_null("SpriteIdle")
@onready var _sprite_pressed: Sprite2D = get_node_or_null("SpritePressed")
@onready var _sprite_legacy: Sprite2D  = get_node_or_null("Sprite2D")

var _already_triggered: bool = false

func _ready() -> void:
	# If no explicit style was set but the key is "triangle", adopt triangle style.
	if style == "" and button_key == "triangle":
		style = "triangle"

	# Apply style/texture overrides BEFORE restoring pressed state, so visuals match.
	_apply_style_textures()

	var down := RunState.button_instance_is_down(_resolved_instance_id())
	_already_triggered = down
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

	if not RunState.button_instance_is_down(iid):
		RunState.button_instance_set_down(iid, true)
		if button_key != "":
			RunState.button_group_add(button_key, +1)
		_apply_state(true)
		pressed.emit(button_key, puzzle_index)

		# OPTIONAL: triangle-specific SFX/logic
		if button_key == "triangle":
			if Engine.has_singleton("SoundManager"):
				Engine.get_singleton("SoundManager").play("ding_triangle")

	if one_shot:
		_already_triggered = true

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if auto_deactivate_on_exit:
		var iid := _resolved_instance_id()
		if RunState.button_instance_is_down(iid):
			RunState.button_instance_set_down(iid, false)
			if button_key != "":
				RunState.button_group_add(button_key, -1)
			_apply_state(false)
			released.emit(button_key, puzzle_index)
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

# === NEW: public helper so spawners can switch looks dynamically ===
func apply_style(s: String) -> void:
	style = s
	_apply_style_textures()

# === NEW: assign textures based on style/overrides ===
func _apply_style_textures() -> void:
	var idle_tex := idle_texture
	var pressed_tex := pressed_texture

	# If no explicit overrides were provided, choose by style
	if idle_tex == null or pressed_tex == null:
		match style:
			"triangle":
				if idle_tex == null:
					idle_tex = preload("res://actors/FloorButtonTriangle.png")
				if pressed_tex == null:
					pressed_tex = preload("res://actors/FloorButtonPressedTriangle.png")
			_:
				# leave nulls as-is; default textures already set in the scene
				pass

	# Assign to sprites if present
	if _sprite_idle and idle_tex:
		_sprite_idle.texture = idle_tex
	if _sprite_pressed and pressed_tex:
		_sprite_pressed.texture = pressed_tex
	if _sprite_legacy and idle_tex:
		_sprite_legacy.texture = idle_tex

# Optional manual reset
func deactivate() -> void:
	var iid := _resolved_instance_id()
	if RunState.button_instance_is_down(iid):
		RunState.button_instance_set_down(iid, false)
		if button_key != "":
			RunState.button_group_add(button_key, -1)
	_apply_state(false)
	_already_triggered = false
