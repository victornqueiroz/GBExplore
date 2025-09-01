# MapRoot.gd  (Control)
extends Control

# Appearance
const CELL := 12
const PAD := 8
const GAP := 2
const BG_COLOR := Color(0, 0, 0, 0.75)
const ROOM_COLOR := Color(0.65, 0.85, 1.0, 0.9)

# Door visuals (kept for flexibility; not drawing blocked ticks anymore)
const EXIT_OPEN_COLOR := Color(1, 1, 1, 0.95)
const EXIT_BLOCK_COLOR := Color(0, 0, 0, 0.95)
const CURRENT_COLOR := Color(1.0, 0.7, 0.2, 1.0)
const GRID_COLOR := Color(1, 1, 1, 0.08)

# how thick the door notch / connector is (in-room edge width)
const DOOR_THICK: float = (float(CELL) * 0.35) if (float(CELL) * 0.35) > 3.0 else 3.0
const STUB_LEN: float = float(GAP) * 0.9	# how far the stub sticks into the gap

# World hard-cap (keep in sync with ScreenManager)
const WORLD_W := 8
const WORLD_H := 8

# --- Inventory strip (under the map) ---
const INV_ICON: int = 16
const INV_GAP: int = 2
const INV_PAD_TOP: int = 6
const INV_BG: Color = Color(1, 1, 1, 0.90)

var _min: Vector2i = Vector2i.ZERO
var _max: Vector2i = Vector2i.ZERO
var _size_px: Vector2 = Vector2.ZERO

# optional: read helpers (and listen for updates) from ScreenManager when available
var _provider: Node = null

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_provider = get_tree().get_root().find_child("ScreenManager", true, false)
	if _provider and _provider.has_signal("map_state_changed"):
		_provider.connect("map_state_changed", Callable(self, "refresh"))

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

	# 1) draw room cells
	for coord in RunState.visited.keys():
		var v := Vector2i(coord)
		var r := _cell_rect(origin, v, cell_span_x, cell_span_y)
		draw_rect(r, ROOM_COLOR)

	# 2) draw connectors (only when BOTH sides are open AND neighbor exists)
	#    -> draw E and S to avoid double-draw
	for coord2 in RunState.visited.keys():
		var c := Vector2i(coord2)
		var r2 := _cell_rect(origin, c, cell_span_x, cell_span_y)

		if _is_exit_open_between(c, "E"):
			var x := r2.position.x + CELL
			var y := r2.position.y + (CELL - DOOR_THICK) * 0.5
			draw_rect(Rect2(Vector2(x, y), Vector2(GAP, DOOR_THICK)), ROOM_COLOR)

		if _is_exit_open_between(c, "S"):
			var x2 := r2.position.x + (CELL - DOOR_THICK) * 0.5
			var y2 := r2.position.y + CELL
			draw_rect(Rect2(Vector2(x2, y2), Vector2(DOOR_THICK, GAP)), ROOM_COLOR)

	# 3) open-door stubs: short connector-like pieces into the gap for open doors
	#    (only when neighbor is in-bounds and not yet visited)
	for coord3 in RunState.visited.keys():
		var v3 := Vector2i(coord3)
		var r3 := _cell_rect(origin, v3, cell_span_x, cell_span_y)
		_draw_open_stubs(r3, v3)

	# current position
	var cur := RunState.pos
	var cur_cell := Vector2(
		origin.x + PAD + (cur.x - _min.x) * cell_span_x,
		origin.y + PAD + (cur.y - _min.y) * cell_span_y
	)
	draw_circle(cur_cell + Vector2(CELL, CELL) * 0.5, 2.5, CURRENT_COLOR)

	# inventory under the map
	_draw_inventory(origin)

# -------------------------------
# helpers (drawing + topology)
# -------------------------------
func _cell_rect(origin: Vector2, v: Vector2i, span_x: float, span_y: float) -> Rect2:
	var cell_pos := Vector2(
		origin.x + PAD + (v.x - _min.x) * span_x,
		origin.y + PAD + (v.y - _min.y) * span_y
	)
	return Rect2(cell_pos, Vector2(CELL, CELL))

func _draw_open_stubs(r: Rect2, c: Vector2i) -> void:
	var cx := r.position.x + (CELL - DOOR_THICK) * 0.5
	var cy := r.position.y + (CELL - DOOR_THICK) * 0.5

	# North
	if _should_draw_stub(c, "N"):
		draw_rect(Rect2(Vector2(cx, r.position.y - STUB_LEN), Vector2(DOOR_THICK, STUB_LEN)), ROOM_COLOR)
	# South
	if _should_draw_stub(c, "S"):
		draw_rect(Rect2(Vector2(cx, r.position.y + CELL), Vector2(DOOR_THICK, STUB_LEN)), ROOM_COLOR)
	# West
	if _should_draw_stub(c, "W"):
		draw_rect(Rect2(Vector2(r.position.x - STUB_LEN, cy), Vector2(STUB_LEN, DOOR_THICK)), ROOM_COLOR)
	# East
	if _should_draw_stub(c, "E"):
		draw_rect(Rect2(Vector2(r.position.x + CELL, cy), Vector2(STUB_LEN, DOOR_THICK)), ROOM_COLOR)

func _should_draw_stub(c: Vector2i, side: String) -> bool:
	var d := _side_to_vec(side)
	var n := c + d
	# no stub outside world
	if not _in_bounds(n):
		return false
	# if neighbor is already placed, either a full connector will draw (both open)
	# or nothing (mismatch/closed). In both cases: no stub.
	if RunState.visited.has(n):
		return false
	# neighbor not placed: show stub only if this room’s side is open
	return _is_side_open_here(c, side)

func _side_to_vec(side: String) -> Vector2i:
	if side == "N": return Vector2i(0, -1)
	if side == "S": return Vector2i(0, 1)
	if side == "E": return Vector2i(1, 0)
	if side == "W": return Vector2i(-1, 0)
	return Vector2i.ZERO

func _opp(side: String) -> String:
	if side == "N": return "S"
	if side == "S": return "N"
	if side == "E": return "W"
	if side == "W": return "E"
	return side

func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < WORLD_W and c.y < WORLD_H

# --- Truth: these two defer to ScreenManager if present (else fall back to RunState) ---
func _is_side_open_here(c: Vector2i, side: String) -> bool:
	if _provider and _provider.has_method("map_is_side_open_here"):
		return _provider.map_is_side_open_here(c, side)
	# fallback: read from room def
	var path := String(RunState.visited.get(c, ""))
	if path == "":
		return false
	if "entry_open_for_path" in RunState:
		return RunState.entry_open_for_path(path, side)
	return true

func _is_exit_open_between(c: Vector2i, side: String) -> bool:
	if _provider and _provider.has_method("map_is_exit_open_between"):
		return _provider.map_is_exit_open_between(c, side)
	# fallback: both sides must be open and neighbor must exist in-bounds
	var d := _side_to_vec(side)
	var n := c + d
	if not _in_bounds(n):
		return false
	if not RunState.visited.has(n):
		return false
	return _is_side_open_here(c, side) and _is_side_open_here(n, _opp(side))

# -------------------------------
# Inventory
# -------------------------------
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
		var data: ItemData = ItemDb.get_item(id)
		if data and data.icon:
			draw_texture(data.icon, Vector2(x, start.y))
			var amt: int = InventoryLoad.count(id)
			if amt > 1 and data.stackable:
				var font: Font = get_theme_default_font()
				if font:
					var pos := Vector2(x + float(INV_ICON) - 6.0, start.y + float(INV_ICON) - 2.0)
					draw_string(font, pos, str(amt), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8.0, Color(1,1,1,1))
		x += float(INV_ICON + INV_GAP)
