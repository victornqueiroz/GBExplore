# FadeLayer.gd
extends CanvasLayer

@onready var rect: ColorRect = $ColorRect

func _ready() -> void:
	# Make sure the base color is opaque black; we'll animate visibility via self_modulate.
	var c := rect.color
	rect.color = Color(c.r, c.g, c.b, 1.0)
	# Start fully transparent
	rect.self_modulate.a = 0.0
	rect.visible = true
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

func fade_out(duration: float = 0.25) -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(rect, "self_modulate:a", 1.0, duration)
	await t.finished

func fade_in(duration: float = 0.25) -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(rect, "self_modulate:a", 0.0, duration)
	await t.finished

func fade_to(alpha: float, duration: float = 0.25) -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(rect, "self_modulate:a", alpha, duration)

# Out → callback while black → in
func fade_through_black(out_d: float, in_d: float, mid_cb: Callable) -> void:
	# Always start from fully clear so long fades look correct
	rect.self_modulate.a = 0.0
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(rect, "self_modulate:a", 1.0, out_d)
	t.tween_callback(mid_cb)
	t.tween_property(rect, "self_modulate:a", 0.0, in_d)
