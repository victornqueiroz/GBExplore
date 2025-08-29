# MapRoot.gd  (Control)
extends Control

# Appearance
const CELL := 12
const PAD := 8
const GAP := 2
const BG_COLOR := Color(0, 0, 0, 0.75)
const ROOM_COLOR := Color(0.65, 0.85, 1.0, 0.9)
const EXIT_OPEN_COLOR := Color(1, 1, 1, 0.9)      # was EXIT_COLOR
const EXIT_BLOCK_COLOR := Color(0, 0, 0, 0.9)     # blocked/out-of-bounds/closed
const CURRENT_COLOR := Color(1.0, 0.7, 0.2, 1.0)
const GRID_COLOR := Color(1, 1, 1, 0.08)

# --- Inventory strip (under the map) ---
const INV_ICON: int = 16
const INV_GAP: int = 2
const INV_PAD_TOP: int = 6
const INV_BG: Color = Color(1, 1, 1, 0.90)  # 0..1 range

var _min: Vector2i = Vector2i.ZERO
var _max: Vector2i = Vector2i.ZERO
var _size_px: Vector2 = Vector2.ZERO

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if InventoryLoad and not InventoryLoad.changed.is_connected(_on_inventory_changed):
		InventoryLoad.changed.connect(_on_inventory_changed)

func toggle() -> void:
	visible = not visible
	if visible:
		refresh()

func show_map() -> void:
	if not visible:
		visible = true
		refresh()

func hide_map() -> void:
	visible = false

func refresh() -> void:
	# compute bounds of placed rooms
	if RunState.visited.size() == 0:
		_min = Vector2i.ZERO
		_max = Vector2i.ZERO
	else:
		var first := true
		for coord in RunState.visited.keys():
			var v := Vector2i(coord)
			if first:
				_min = v; _max = v; first = false
			else:
				if v.x < _min.x: _min.x = v.x
				if v.y < _min.y: _min.y = v.y
				if v.x > _max.x: _max.x = v.x
				if v.y > _max.y: _max.y = v.y

	var w_cells := (_max.x - _min.x + 1)
	var h_cells := (_max.y - _min.y + 1)
	var cell_span_x := float(CELL + GAP)
	var cell_span_y := float(CELL + GAP)
	_size_px = Vector2(
		PAD * 2.0 + w_cells * cell_span_x - GAP,
		PAD * 2.0 + h_cells * cell_span_y - GAP
	)

	queue_redraw()

func _draw() -> void:
	if not visible:
		return

	# center the map on screen
	var vp := get_viewport_rect().size
	var origin := (vp - _size_px) * 0.5

	# panel background
	draw_rect(Rect2(origin, _size_px), BG_COLOR)

	# grid
	var w_cells := (_max.x - _min.x + 1)
	var h_cells := (_max.y - _min.y + 1)
	var cell_span_x := float(CELL + GAP)
	var cell_span_y := float(CELL + GAP)
	for xi in range(w_cells + 1):
		var x := origin.x + PAD + xi * cell_span_x - GAP * 0.5
		draw_line(Vector2(x, origin.y + PAD), Vector2(x, origin.y + _size_px.y - PAD), GRID_COLOR, 1.0)
	for yi in range(h_cells + 1):
		var y := origin.y + PAD + yi * cell_span_y - GAP * 0.5
		draw_line(Vector2(origin.x + PAD, y), Vector2(origin.x + _size_px.x - PAD, y), GRID_COLOR, 1.0)

	# rooms
	for coord in RunState.visited.keys():
		var v := Vector2i(coord)
		var cell_pos := Vector2(
			origin.x + PAD + (v.x - _min.x) * cell_span_x,
			origin.y + PAD + (v.y - _min.y) * cell_span_y
		)
		var r := Rect2(cell_pos, Vector2(CELL, CELL))
		draw_rect(r, ROOM_COLOR)

		# exits: white if accessible, black if blocked
		var access := RunState.exit_access_map(v) if RunState.has_method("exit_access_map") else {
			"N": true, "E": true, "S": true, "W": true
		}

		var m := 3.0
		var north_col := EXIT_OPEN_COLOR if access.get("N", false) else EXIT_BLOCK_COLOR
		var south_col := EXIT_OPEN_COLOR if access.get("S", false) else EXIT_BLOCK_COLOR
		var west_col  := EXIT_OPEN_COLOR if access.get("W", false) else EXIT_BLOCK_COLOR
		var east_col  := EXIT_OPEN_COLOR if access.get("E", false) else EXIT_BLOCK_COLOR

		# edge ticks
		draw_line(Vector2(r.position.x + m, r.position.y),
				  Vector2(r.position.x + CELL - m, r.position.y), north_col, 1.0)
		draw_line(Vector2(r.position.x + m, r.position.y + CELL),
				  Vector2(r.position.x + CELL - m, r.position.y + CELL), south_col, 1.0)
		draw_line(Vector2(r.position.x, r.position.y + m),
				  Vector2(r.position.x, r.position.y + CELL - m), west_col, 1.0)
		draw_line(Vector2(r.position.x + CELL, r.position.y + m),
				  Vector2(r.position.x + CELL, r.position.y + CELL - m), east_col, 1.0)

	# current position
	var cur := RunState.pos
	var cur_cell := Vector2(
		origin.x + PAD + (cur.x - _min.x) * cell_span_x,
		origin.y + PAD + (cur.y - _min.y) * cell_span_y
	)
	draw_circle(cur_cell + Vector2(CELL, CELL) * 0.5, 2.5, CURRENT_COLOR)

	# inventory under the map
	_draw_inventory(origin)

func _on_inventory_changed() -> void:
	if visible:
		queue_redraw()

func _draw_inventory(origin: Vector2) -> void:
	if not ("all_items" in InventoryLoad):
		return
	var ids: Array[String] = InventoryLoad.all_items()
	if ids.is_empty():
		return
	ids.sort()

	var item_count: int = ids.size()

	# Position just under the map
	var start := Vector2(
		origin.x + float(PAD),
		origin.y + float(_size_px.y) + float(INV_PAD_TOP)
	)

	var total_w: int = item_count * INV_ICON + max(0, item_count - 1) * INV_GAP + int(PAD)
	var total_h: int = INV_ICON + int(PAD * 0.5)

	# Background bar
	draw_rect(
		Rect2(start - Vector2(float(PAD) * 0.5, float(PAD) * 0.25), Vector2(total_w, total_h)),
		INV_BG
	)

	# Icons + counts
	var x: float = start.x
	for id in ids:
		var data: ItemData = ItemDb.get_item(id) # or ItemDB if that's your autoload name
		if data and data.icon:
			draw_texture(data.icon, Vector2(x, start.y))
			var amt: int = InventoryLoad.count(id)
			if amt > 1 and data.stackable:
				var font: Font = get_theme_default_font()
				if font:
					var pos := Vector2(x + float(INV_ICON) - 6.0, start.y + float(INV_ICON) - 2.0)
					draw_string(font, pos, str(amt), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8.0, Color(1,1,1,1))
		x += float(INV_ICON + INV_GAP)
