extends Control
signal finished

# ====== DESIGN HOOKS =================================================
@export var ui_font: FontFile
@export var dim_alpha: float = 0.55
@export var portrait_max_height: float = 56.0

# Fixed pixel height + separate margins from the screen edges
@export var bar_height_px: int = 44
@export var screen_margin_side_px: int = 10
@export var screen_margin_bottom_px: int = 6

# Box fill (inside the border)
@export var box_fill_color: Color = Color.BLACK
@export var box_fill_alpha: float = 0.8

# Code border (no texture). Two-line GB style.
@export var use_code_border: bool = true
@export var border_outer_color: Color = Color.BLACK
@export var border_inner_color: Color = Color("#A9B0B0")
@export var border_outer_px: int = 1
@export var border_gap_px: int = 0
@export var border_inner_px: int = 1
@export var inner_padding_px: int = 8
# inset to keep the outer line fully inside the DialogueBox rect (prevents edge clipping)
@export var border_outer_inset_px: int = 1


const TYPE_SPEED := 60.0

# ====== NODES ========================================================
@onready var dimmer: ColorRect           = $Dimmer
@onready var bg: ColorRect               = $BG
@onready var container: MarginContainer  = $MarginContainer
@onready var text: RichTextLabel         = $MarginContainer/RichTextLabel
@onready var hint: Label = $Label 
@onready var portrait: TextureRect       = $Portrait

# ====== STATE ========================================================
var _cooldown: float = 0.0
var _pages: PackedStringArray = PackedStringArray()
var _page_idx: int = 0
var _typing: bool = false
var _typed: float = 0.0
var _page_char_total: int = 0
var _blink_t: float = 0.0

# ====== HELPERS ======================================================
func _with_alpha(c: Color, a: float) -> Color:
	var n := c
	n.a = a
	return n

func _set_container_padding(p: int) -> void:
	container.add_theme_constant_override("margin_left", p)
	container.add_theme_constant_override("margin_right", p)
	container.add_theme_constant_override("margin_top", p)
	container.add_theme_constant_override("margin_bottom", p)

func _make_stylebox_outline(col: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(max(w, 0))
	sb.border_color = col
	return sb

# ====== LAYOUT =======================================================
# Fixed-pixel layout at the bottom with screen margins
func _apply_layout() -> void:
	# width: full, but inset by side margins
	anchor_left = 0.0; anchor_right = 1.0
	offset_left = screen_margin_side_px
	offset_right = -screen_margin_side_px
	
	# height: fixed pixels; bottom-aligned with bottom margin
	anchor_bottom = 1.0
	anchor_top = 1.0
	offset_bottom = -screen_margin_bottom_px
	offset_top = -(screen_margin_bottom_px + bar_height_px)

# Build a two-line border using two Panels (no textures)
func _ensure_code_border() -> void:
	if not use_code_border:
		if has_node("OuterBorder"): $OuterBorder.queue_free()
		if has_node("InnerBorder"): $InnerBorder.queue_free()
		_set_container_padding(inner_padding_px)
		_layout_bg_to_border()
		return

	var outer: Panel
	var inner: Panel

	if has_node("OuterBorder"):
		outer = $OuterBorder
	else:
		outer = Panel.new()
		outer.name = "OuterBorder"
		add_child(outer)
		move_child(outer, bg.get_index() + 1) # BG < borders < content

	if has_node("InnerBorder"):
		inner = $InnerBorder
	else:
		inner = Panel.new()
		inner.name = "InnerBorder"
		add_child(inner)
		move_child(inner, outer.get_index() + 1)

	for p in [outer, inner]:
		p.anchor_left = 0.0; p.anchor_right = 1.0
		p.anchor_top  = 0.0; p.anchor_bottom = 1.0
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.z_index = 205

	# keep the border fully inside the DialogueBox rect
	var k := border_outer_inset_px
	outer.offset_left   =  k
	outer.offset_right  = -k
	outer.offset_top    =  k
	outer.offset_bottom = -k

	outer.add_theme_stylebox_override("panel",
		_make_stylebox_outline(border_outer_color, border_outer_px))

	inner.add_theme_stylebox_override("panel",
		_make_stylebox_outline(border_inner_color, border_inner_px))

	# inner line sits inside outer line + gap + inset
	var inset := k + border_outer_px + border_gap_px
	inner.offset_left   =  inset
	inner.offset_right  = -inset
	inner.offset_top    =  inset
	inner.offset_bottom = -inset

	# padding so glyphs don't kiss the inner line
	_set_container_padding(inner_padding_px + border_inner_px)

	# BG should fill EXACTLY the space inside the outer border (match visual box)
	_layout_bg_to_border()

# Make BG ColorRect fill the same area that the OUTER border encloses
func _layout_bg_to_border() -> void:
	var k: int = 0
	if use_code_border:
		k = border_outer_inset_px

	bg.anchor_left = 0.0
	bg.anchor_right = 1.0
	bg.anchor_top = 0.0
	bg.anchor_bottom = 1.0

	bg.offset_left =  k
	bg.offset_right = -k
	bg.offset_top =   k
	bg.offset_bottom = -k

	bg.color = _with_alpha(box_fill_color, box_fill_alpha)

# ====== LIFECYCLE ====================================================
func _ready() -> void:
	_apply_layout()
	z_index = 200

	dimmer.color = _with_alpha(Color.BLACK, 0.0)

	_ensure_code_border()
	
	# Make the text fill the container; containers ignore anchors, use size flags.
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	# Make sure the MarginContainer fills the DialogueBox rect.
	container.anchor_left = 0.0;  container.anchor_right = 1.0
	container.anchor_top  = 0.0;  container.anchor_bottom = 1.0
	container.offset_left = 0;    container.offset_right = 0
	container.offset_top  = 0;    container.offset_bottom = 0


	# Text look
	if ui_font:
		text.add_theme_font_override("font", ui_font)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.scroll_active = false
	text.visible_characters = -1
	text.add_theme_color_override("default_color", Color(1, 1, 1, 1))
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	text.add_theme_constant_override("shadow_as_outline", 1)

	# ▼ cursor bottom-right
	if ui_font:
		hint.add_theme_font_override("font", ui_font)
	hint.text = "v"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint.anchor_left = 1.0; hint.anchor_right = 1.0
	hint.anchor_top  = 1.0; hint.anchor_bottom = 1.0
	hint.offset_left = -24; hint.offset_right = -60
	hint.offset_top  = -24; hint.offset_bottom = -40
	hint.visible = false
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.z_index = 220

	# Portrait
	portrait.visible = false
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.z_index = 220

	visible = false

# Called automatically when the control’s size changes (e.g., window resize)
func _size_changed() -> void:
	_apply_layout()
	_ensure_code_border()

# ====== OPEN/CLOSE & TYPEWRITER =====================================
func open(lines: PackedStringArray, face: Texture2D = null, side: String = "left") -> void:
	if face != null:
		portrait.texture = face
		portrait.modulate.a = 1.0
	else:
		portrait.texture = null
		portrait.visible = false

	_apply_layout()
	_ensure_code_border()

	visible = true
	text.text = ""
	hint.visible = true
	hint.modulate.a = 1.0
	_blink_t = 0.0
	_page_idx = 0
	_cooldown = 0.12

	var tw: Tween = create_tween()
	tw.tween_property(dimmer, "color", _with_alpha(Color.BLACK, dim_alpha), 0.12)

	await get_tree().process_frame
	if portrait.texture != null:
		_place_portrait(side)

	_pages = _build_pages_by_label(lines)
	if _pages.size() == 0:
		_pages.append("")
	_show_page()

func _process(delta: float) -> void:
	if _cooldown > 0.0: _cooldown -= delta

	if _typing:
		_typed += delta * TYPE_SPEED
		var target: int = int(_typed)
		if text.visible_characters < target:
			text.visible_characters = min(target, _page_char_total)
		if text.visible_characters >= _page_char_total:
			_typing = false
			hint.visible = true
			_blink_t = 0.0

	if hint.visible and not _typing:
		_blink_t += delta
		var a: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(_blink_t * 6.0))
		hint.modulate.a = a

func _show_page() -> void:
	if _page_idx >= _pages.size():
		close(); return
	var page: String = _pages[_page_idx]
	text.text = page
	if text.has_method("get_total_character_count"):
		_page_char_total = int(text.call("get_total_character_count"))
	else:
		_page_char_total = page.length()
	text.visible_characters = 0
	_typed = 0.0
	_typing = true
	hint.visible = false
	hint.modulate.a = 1.0

func _reveal_all_current() -> void:
	text.visible_characters = -1
	_typing = false
	hint.visible = true
	_blink_t = 0.0

func next() -> void:
	if not visible: return
	if _typing:
		_reveal_all_current(); return
	if _page_idx < _pages.size() - 1:
		_page_idx += 1
		_show_page()
	else:
		close()

func close() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(dimmer, "color", _with_alpha(Color.BLACK, 0.0), 0.08)
	await tw.finished
	visible = false
	_pages.clear()
	_page_idx = 0
	_typing = false
	_typed = 0.0
	text.visible_characters = -1
	text.text = ""
	portrait.visible = false
	emit_signal("finished")

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _cooldown > 0.0: return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		next(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close(); get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not visible or _cooldown > 0.0: return
	if event is InputEventMouseButton and event.pressed:
		next(); accept_event()

# ====== PAGINATION ===================================================
func _build_pages_by_label(lines: PackedStringArray) -> PackedStringArray:
	var pages := PackedStringArray()
	var page_buf := ""
	var max_h: float = _text_max_height()

	if max_h <= 1.0:
		max_h = max(size.y - 16.0, 64.0)
	for para in lines:
		var words := String(para).split(" ")
		for w in words:
			var candidate: String = (w if page_buf.strip_edges() == "" else page_buf + " " + w)
			text.text = candidate
			if text.get_content_height() > max_h:
				pages.append(page_buf.strip_edges())
				page_buf = w
			else:
				page_buf = candidate
		if page_buf != "":
			var with_break: String = page_buf + "\n"
			text.text = with_break
			if text.get_content_height() > max_h:
				pages.append(page_buf.strip_edges())
				page_buf = ""
			else:
				page_buf = with_break
	if page_buf.strip_edges() != "":
		pages.append(page_buf.strip_edges())
	if pages.size() == 0:
		pages.append("")
	return pages

# ====== PORTRAIT =====================================================
func _place_portrait(side: String) -> void:
	if portrait.texture == null: return
	portrait.z_index = 220
	var h: float = min(portrait_max_height, size.y * 0.95)
	portrait.size = Vector2(h, h)
	if side == "right":
		portrait.anchor_left = 1.0
		portrait.offset_left = -h - 6
	else:
		portrait.anchor_left = 0.0
		portrait.offset_left = 6
	portrait.anchor_top = 0.0
	portrait.offset_top = -h + 2   # change to 2 to place inside the bar
	portrait.visible = true

func _text_max_height() -> float:
	var h: float = float(bar_height_px)
	h -= 2.0 * float(inner_padding_px)
	if use_code_border:
		h -= float(border_outer_px + border_inner_px + 2*border_outer_inset_px + border_gap_px)
	return max(h, 16.0)
