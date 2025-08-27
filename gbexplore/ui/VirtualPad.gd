extends CanvasLayer

# --- Actions ---
@export var action_interact: StringName = "interact"
@export var action_map: StringName      = "show_map"
@export var overlay_layer: int = 1000  # higher than any other CanvasLayer you use
@export var confirm_action: StringName  = "ui_accept" 

# --- Size / layout (25% of original) ---
@export var base_size: int     = 64
@export var scale_pct: float   = 0.25
@export var base_spacing: int  = 8
@export var base_margin: int   = 8

# --- Debug visuals (drawn as the button's own texture) ---
@export var show_debug: bool   = true
@export var dpad_color: Color  = Color(0.2, 1.0, 1.0, 0.35)  # cyan for arrows
@export var ab_color: Color    = Color(1.0, 0.2, 1.0, 0.35)  # magenta for A/B

@onready var interact_btn: TouchScreenButton = $InteractBtn
@onready var map_btn:      TouchScreenButton = $MapBtn
@onready var up_btn:       TouchScreenButton = $UpBtn
@onready var down_btn:     TouchScreenButton = $DownBtn
@onready var left_btn:     TouchScreenButton = $LeftBtn
@onready var right_btn:    TouchScreenButton = $RightBtn

var _dpad_size: int
var _ab_size: int
var _spacing: int
var _margin: int

func _ready() -> void:
	layer = overlay_layer
	visible = false
	
	interact_btn.action = action_interact
	# precompute sizes
	_dpad_size = int(round(base_size * scale_pct))
	_ab_size   = int(round(base_size * scale_pct))
	_spacing   = int(round(base_spacing * scale_pct))
	_margin    = int(round(base_margin * scale_pct))

	# link actions
	interact_btn.action = action_interact
	map_btn.action      = action_map
	up_btn.action       = "ui_up"
	down_btn.action     = "ui_down"
	left_btn.action     = "ui_left"
	right_btn.action    = "ui_right"

	# configure shapes + visuals
	for b in [up_btn, down_btn, left_btn, right_btn]:
		_setup_button(b, _dpad_size, dpad_color)
	for b in [interact_btn, map_btn]:
		_setup_button(b, _ab_size, ab_color)

	_layout()
	get_viewport().size_changed.connect(_layout)

func _setup_button(btn: TouchScreenButton, size: int, col: Color) -> void:
	btn.shape_centered = false
	var s: RectangleShape2D = RectangleShape2D.new()
	s.size = Vector2(size, size)
	btn.shape = s
	btn.passby_press = true

	if show_debug:
		# Use the button's OWN textures (so visuals == touch area, no sprites stealing input)
		var normal: Texture2D  = _make_rect_texture(size, size, col, true)
		var pressed: Texture2D = _make_rect_texture(size, size, col.darkened(0.3), true)
		btn.texture_normal  = normal
		btn.texture_pressed = pressed
	else:
		btn.texture_normal  = null
		btn.texture_pressed = null

func _layout() -> void:
	var sz: Vector2 = get_viewport().get_visible_rect().size
	var half_w: float = sz.x * 0.5

	# ----- LEFT HALF: cross-shaped D-pad -----
	var cross_w: float = float(_dpad_size * 3 + _spacing * 2)
	var cross_h: float = cross_w
	var cross_x: float = clampf(float(_margin), 0.0, maxf(0.0, half_w - float(_margin) - cross_w))
	var cross_y: float = sz.y - float(_margin) - cross_h
	var origin: Vector2 = Vector2(cross_x, cross_y)

	# [ ][U][ ]
	# [L][ ][R]
	# [ ][D][ ]
	up_btn.position    = origin + Vector2(_dpad_size + _spacing, 0.0)
	down_btn.position  = origin + Vector2(_dpad_size + _spacing, float(_dpad_size * 2 + _spacing * 2))
	left_btn.position  = origin + Vector2(0.0, _dpad_size + _spacing)
	right_btn.position = origin + Vector2(float(_dpad_size * 2 + _spacing * 2), _dpad_size + _spacing)

	# ----- RIGHT HALF: Interact + Map -----
	var right_start_x: float = half_w
	var map_pos: Vector2 = Vector2(sz.x - float(_margin) - float(_ab_size),
								   sz.y - float(_margin) - float(_ab_size))
	var interact_pos: Vector2 = map_pos + Vector2(-(_ab_size + _spacing), 0.0)

	if interact_pos.x < right_start_x + float(_margin):
		var shift: float = right_start_x + float(_margin) - interact_pos.x
		interact_pos.x += shift
		map_pos.x      += shift

	map_btn.position      = map_pos
	interact_btn.position = interact_pos

func _make_rect_texture(w: int, h: int, col: Color, with_border: bool) -> Texture2D:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(col)
	if with_border:
		var k: Color = Color(0, 0, 0, 1)
		for x in range(w):
			img.set_pixel(x, 0, k)
			img.set_pixel(x, h - 1, k)
		for y in range(h):
			img.set_pixel(0, y, k)
			img.set_pixel(w - 1, y, k)
	return ImageTexture.create_from_image(img)

func _on_interact_down() -> void:
	if String(confirm_action) != "":
		Input.action_press(confirm_action)

func _on_interact_up() -> void:
	if String(confirm_action) != "":
		Input.action_release(confirm_action)
