extends CanvasLayer
signal finished

@onready var _backdrop: ColorRect   = $Overlay/Backdrop
@onready var _overlay: Control      = $Overlay
@onready var _fade: ColorRect       = $Overlay/Fade
@onready var _frame_a: TextureRect  = $Overlay/FrameA
@onready var _frame_b: TextureRect  = $Overlay/FrameB
@onready var _hint: Label           = $Overlay/SkipHint

var _restore_paused: bool = false
var _skippable: bool = true
var _running: bool = false
var _front_is_a: bool = true   # which frame is currently on top

func _ready() -> void:
	# Start COVERED immediately so nothing else can flash:
	visible = true
	_overlay.visible = true
	_backdrop.color.a = 1.0       # stays opaque during playback
	_fade.color.a = 1.0           # start fully black (global cover)
	_frame_a.modulate.a = 1.0
	_frame_b.modulate.a = 0.0
	_hint.visible = false
	set_process_input(true)
	
func _input(event: InputEvent) -> void:
	if not _running or not _skippable:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_finish_immediately()

# --- Public API -------------------------------------------------------

# New defaults: 2s per frame, 0.35s cross-fade between frames.
func play_images(frames: Array, per_frame_sec: float = 2.0, fade_in: float = 0.20, hold_last: float = 0.0, fade_out: float = 0.20, skippable: bool = true, pause_world: bool = true, crossfade_sec: float = 0.35) -> void:
	await _start(fade_in, skippable, pause_world)
	if frames.is_empty():
		await _end(0.0); return

	_set_front_texture(frames[0])

	# Reveal first frame from black
	await _fade_to(0.0, fade_in)   # this animates _fade.color.a from 1 → 0

	await _wait(per_frame_sec)
	for i in range(1, frames.size()):
		await _crossfade_to(frames[i], crossfade_sec)
		await _wait(per_frame_sec)

	if hold_last > 0.0:
		await _wait(hold_last)

	await _end(fade_out)

# Optional: still works with per-frame timing (uses cross-fade between items)
func play_comic(frames: Array, fade_in: float = 0.20, fade_out: float = 0.20, skippable: bool = true, pause_world: bool = true, crossfade_sec: float = 0.35) -> void:
	await _start(fade_in, skippable, pause_world)
	if frames.is_empty():
		await _end(0.0); return
	# first
	var first: Variant = frames[0].get("tex")
	_set_front_texture(first)
	await _wait(float(frames[0].get("sec", 0.4)))
	# rest
	for i in range(1, frames.size()):
		var tex: Variant = frames[i].get("tex")
		var hold: float = float(frames[i].get("sec", 0.4))
		await _crossfade_to(tex, crossfade_sec)
		await _wait(hold)
	await _end(fade_out)

# --- Internals --------------------------------------------------------

func _start(fade_in: float, skippable: bool, pause_world: bool) -> void:
	_skippable = skippable
	_running = true
	# visible and black already set in _ready()
	if pause_world:
		_restore_paused = get_tree().paused
		get_tree().paused = true

func _end(fade_out: float) -> void:
	_hint.visible = false

	# Step 1: fade to black (covers the last image)
	await _fade_to(1.0, fade_out)

	# Step 2: hide image layers now that screen is covered
	_frame_a.texture = null
	_frame_b.texture = null
	_frame_a.modulate.a = 0.0
	_frame_b.modulate.a = 0.0

	# Also fade out backdrop if you're still using it
	_backdrop.color.a = 0.0

	# Step 3: restore pause state
	if get_tree().paused and not _restore_paused:
		get_tree().paused = false
	elif not get_tree().paused and _restore_paused:
		get_tree().paused = true

	# Step 4: fade from black → game
	await _fade_to(0.0, 0.25)

	_cleanup_and_close()



func _finish_immediately() -> void:
	# Mark as not running so any loops bail
	_running = false
	_hint.visible = false

	# Cover the screen so we don't flash the last frame
	_fade.color.a = 1.0

	# Hide imagery while covered
	_frame_a.texture = null
	_frame_b.texture = null
	_frame_a.modulate.a = 0.0
	_frame_b.modulate.a = 0.0
	_backdrop.color.a = 0.0

	# Restore pause state (same as in _end)
	if get_tree().paused and not _restore_paused:
		get_tree().paused = false
	elif not get_tree().paused and _restore_paused:
		get_tree().paused = true

	# Notify listeners first, then free
	emit_signal("finished")
	queue_free()
	
	
func _cleanup_and_close() -> void:
	_running = false
	visible = false
	queue_free()
	emit_signal("finished")

# ---------- helpers ----------

func _tex_from(v: Variant) -> Texture2D:
	return (load(v) if v is String else v) as Texture2D

func _set_front_texture(tex_any: Variant) -> void:
	var front := (_frame_a if _front_is_a else _frame_b)
	front.texture = _tex_from(tex_any)
	front.modulate.a = 1.0
	var back := (_frame_b if _front_is_a else _frame_a)
	back.modulate.a = 0.0

func _crossfade_to(tex_any: Variant, dur: float) -> void:
	var front := (_frame_a if _front_is_a else _frame_b)
	var back  := (_frame_b if _front_is_a else _frame_a)
	back.texture = _tex_from(tex_any)
	back.modulate.a = 0.0

	var t := 0.0
	while t < dur:
		t += get_process_delta_time()
		var k = clamp(t / max(dur, 0.0001), 0.0, 1.0)
		front.modulate.a = 1.0 - k
		back.modulate.a  = k
		await get_tree().process_frame

	_front_is_a = not _front_is_a

func _fade_to(target_a: float, dur: float) -> void:
	var start_a := _fade.color.a
	var t := 0.0
	while t < dur:
		t += get_process_delta_time()
		var k = clamp(t / max(dur, 0.0001), 0.0, 1.0)
		var c := _fade.color
		c.a = lerp(start_a, target_a, k)
		_fade.color = c
		await get_tree().process_frame

func _wait(sec: float) -> void:
	if _skippable and not _hint.visible and sec >= 0.4:
		_hint.visible = true
	await get_tree().create_timer(sec, true, false, true).timeout
