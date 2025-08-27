# FadeLayer.gd
extends CanvasLayer
@onready var rect := $ColorRect

func _ready():
	rect.visible = true
	rect.modulate.a = 0.0  # start transparent

func fade_out(duration := 0.25):
	print("FADE OUT")
	var t := create_tween()
	t.tween_property(rect, "modulate:a", 1.0, duration)
	await t.finished

func fade_in(duration := 0.25):
	print("FADE IN")
	var t := create_tween()
	t.tween_property(rect, "modulate:a", 0.0, duration)
	#await t.finished

func fade_to(alpha: float, duration := 0.25) -> void:
	var t := create_tween()
	t.tween_property($ColorRect, "modulate:a", alpha, duration)
	# no await -> non-blocking

# tabs used below
func fade_through_black(out_d: float, in_d: float, mid_cb: Callable) -> void:
	var t := create_tween()
	t.tween_property($ColorRect, "modulate:a", 1.0, out_d)
	t.tween_callback(mid_cb)
	t.tween_property($ColorRect, "modulate:a", 0.0, in_d)
