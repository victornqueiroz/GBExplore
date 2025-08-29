# res://ui/StepsHUD.gd
extends Control

const PAD := 4
const MARGIN := 4
const BG := Color(0, 0, 0, 0.45)   # slightly transparent black
const FG := Color(1, 1, 1, 1)      # white
const FONT_SIZE := 10

var _last_steps: int = -999

func _ready() -> void:
	# lock to top-left and ignore input
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_update_text(true)
	set_process(true)

func _process(_dt: float) -> void:
	# If you have a RunState signal for steps changing, connect to it instead of polling.
	_update_text(false)

func _update_text(force: bool) -> void:
	var steps := int(RunState.steps_left)
	if not force and steps == _last_steps:
		return
	_last_steps = steps
	queue_redraw()

func _draw() -> void:
	var txt =  "STEPS "+ str(_last_steps)
	# If you prefer a label like "STEPS 12", use: var txt = "STEPS " + str(_last_steps)

	var font: Font = get_theme_default_font()
	if font == null:
		return

	var ascent := font.get_ascent(FONT_SIZE)
	var text_size := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE)

	# background box in top-left
	var bg_pos := Vector2(MARGIN, MARGIN)
	var bg_size := text_size + Vector2(PAD * 2.0, PAD * 2.0)
	draw_rect(Rect2(bg_pos, bg_size), BG)

	# text baseline
	var text_pos := bg_pos + Vector2(PAD, PAD + ascent)
	draw_string(font, text_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, FG)
