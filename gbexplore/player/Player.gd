extends CharacterBody2D

@export var speed := 80.0
@export var updown_step_interval := 0.12  # fake up/down steps when only 1-frame up/down

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

enum Facing { DOWN, UP, RIGHT, LEFT }
var facing: Facing = Facing.DOWN


var _ud_step_accum := 0.0
var _ud_flip := false   # mirror up/down while moving to fake a 2-step walk

# --- NEW: input freeze for menus ---
var input_enabled: bool = true
func set_input_enabled(v: bool) -> void:
	input_enabled = v
	if not input_enabled:
		# stop motion immediately and force idle visuals
		velocity = Vector2.ZERO
		_ud_step_accum = 0.0
		_ud_flip = false
		_update_animation(false)

func _ready() -> void:
	# Make sure animations can advance
	anim.speed_scale = 1.0
	# Start from a known state (change if you prefer another default):
	if anim.sprite_frames and anim.sprite_frames.has_animation("idle_down"):
		anim.play("idle_down")

func _physics_process(delta: float) -> void:
	# If input is disabled (e.g., choice menu open), stand still.
	if not input_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 1) movement
	var dir := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down")  - Input.get_action_strength("ui_up")
	)
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
	velocity = dir * speed
	move_and_slide()

	# 2) facing from velocity (last non-zero)
	if velocity.length_squared() > 0.0:
		if abs(velocity.x) > abs(velocity.y):
			facing = Facing.RIGHT if velocity.x > 0.0 else Facing.LEFT
		else:
			facing = Facing.DOWN if velocity.y > 0.0 else Facing.UP

	# 3) fake up/down stepping if moving vertically with only 1-frame sprites
	if (facing == Facing.UP or facing == Facing.DOWN) and velocity.length_squared() > 0.0:
		_ud_step_accum += delta
		if _ud_step_accum >= updown_step_interval:
			_ud_step_accum = 0.0
			_ud_flip = not _ud_flip
	else:
		_ud_step_accum = 0.0
		_ud_flip = false

	_update_animation(velocity.length_squared() > 0.0)

func _update_animation(moving: bool) -> void:
	match facing:
		Facing.LEFT:
			anim.flip_h = false
			_play_or_resume("walk_left" if moving else "idle_left")

		Facing.RIGHT:
			anim.flip_h = true   # mirror left strip for right
			_play_or_resume("walk_left" if moving else "idle_left")

		Facing.UP:
			anim.flip_h = _ud_flip if moving else false
			_play_or_resume("idle_up")   # 1-frame up; keep same anim name

		Facing.DOWN:
			anim.flip_h = _ud_flip if moving else false
			_play_or_resume("idle_down")

func _play_or_resume(name: String) -> void:
	# Only restart if switching animations, but also resume if somehow stopped.
	if anim.animation != name:
		anim.play(name)
	elif not anim.is_playing():
		anim.play(name)
