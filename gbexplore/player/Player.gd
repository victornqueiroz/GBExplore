extends CharacterBody2D

@export var speed := 80.0
@export var updown_step_interval := 0.12
@export var push_wiggle_px := 1.0	# how far the sprite offsets while pushing
@export var push_anim_speed := 0.85	# slow the anim slightly while pushing

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

enum Facing { DOWN, UP, RIGHT, LEFT }
var facing: Facing = Facing.DOWN

var _ud_step_accum := 0.0
var _ud_flip := false
var _prev_pos: Vector2 = Vector2.ZERO

var input_enabled: bool = true
func set_input_enabled(v: bool) -> void:
	input_enabled = v
	if not input_enabled:
		velocity = Vector2.ZERO
		_ud_step_accum = 0.0
		_ud_flip = false
		anim.position = Vector2.ZERO
		anim.speed_scale = 1.0
		_update_animation(false)

func _ready() -> void:
	anim.speed_scale = 1.0
	if anim.sprite_frames and anim.sprite_frames.has_animation("idle_down"):
		anim.play("idle_down")
	_prev_pos = global_position

func _physics_process(delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		_prev_pos = global_position
		return

	# 1) Intent (what the player wants)
	var intent := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down")  - Input.get_action_strength("ui_up")
	)

	# 2) Face by intent (even if blocked)
	if intent.length_squared() > 0.0:
		if abs(intent.x) > abs(intent.y):
			facing = Facing.RIGHT if intent.x > 0.0 else Facing.LEFT
		else:
			facing = Facing.DOWN if intent.y > 0.0 else Facing.UP

	# 3) Move
	var dir := intent
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
	velocity = dir * speed

	var before := global_position
	move_and_slide()
	var after := global_position

	# 4) Movement state
	var moved := (after - before).length_squared() > 0.000001
	var has_intent := intent.length_squared() > 0.0
	var pushing := has_intent and not moved	# <- input but blocked
	var animating := has_intent				# <- animate when trying, even if blocked

	# 5) Up/down fake step while moving OR pushing
	if (facing == Facing.UP or facing == Facing.DOWN) and animating:
		_ud_step_accum += delta
		if _ud_step_accum >= updown_step_interval:
			_ud_step_accum = 0.0
			_ud_flip = not _ud_flip
	else:
		_ud_step_accum = 0.0
		_ud_flip = false

	# 6) Visual feedback for pushing (tiny offset + slightly slower anim)
	if pushing:
		anim.position = _facing_vec() * push_wiggle_px
		anim.speed_scale = push_anim_speed
	else:
		anim.position = Vector2.ZERO
		anim.speed_scale = 1.0

	# 7) Update visuals (walk/idle based on intent)
	_update_animation(animating)

	_prev_pos = after

func _update_animation(moving: bool) -> void:
	match facing:
		Facing.LEFT:
			anim.flip_h = false
			if moving:
				_play("walk_left")
			else:
				_idle_left()
		Facing.RIGHT:
			anim.flip_h = true
			if moving:
				_play("walk_left")
			else:
				_idle_left()
		Facing.UP:
			anim.flip_h = _ud_flip if moving else false
			_play("idle_up")
		Facing.DOWN:
			anim.flip_h = _ud_flip if moving else false
			_play("idle_down")

func _idle_left() -> void:
	if anim.animation != "idle_left":
		anim.play("idle_left")
	else:
		anim.stop()
		anim.frame = 0

func _play(name: String) -> void:
	if anim.animation != name:
		anim.play(name)
	elif not anim.is_playing():
		anim.play(name)

func _facing_vec() -> Vector2:
	match facing:
		Facing.LEFT: return Vector2(-1, 0)
		Facing.RIGHT: return Vector2(1, 0)
		Facing.UP: return Vector2(0, -1)
		Facing.DOWN: return Vector2(0, 1)
	return Vector2.ZERO
