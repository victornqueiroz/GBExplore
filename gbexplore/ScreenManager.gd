extends Node2D

# ----- Config -----
const TILE := 16
const MAP_W := 9
const MAP_H := 9
const SCREEN_SIZE := Vector2i(MAP_W * TILE, MAP_H * TILE)
const EXIT_BAND := 4

const ITEM_PICKUP_SCENE := preload("res://actors/ItemPickup.tscn")
const NPC_SCENE := preload("res://NPC.tscn")
const CHEST_SCENE := preload("res://actors/Chest.tscn")

# --- Edge rocks (visual + collider) ---
const ROCK_TEX := preload("res://art/boulder.png")
const ROCK_Z := 50
const ROCK_SCALE := Vector2(1, 1)
const ROCK_COLLIDER_SIZE := Vector2(12, 12)
var ROCK_LAYER := 1
var ROCK_MASK := 1

# World grid size cap (8x8 max)
const GRID_W := 8
const GRID_H := 8

# Edge blockers toggle
const USE_EDGE_BLOCKERS := false

# Visual debug (used by blocker debug polys)
const SHOW_EDGE_WALLS := true
const WALL_COLOR := Color(1, 0.2, 0.2, 0.45)
const WALL_ZINDEX := 100
const WALL_INSET := 2.0
const WALL_THICK := 16.0
const WALL_OVERHANG := 1.0
const WALL_LAYER := 1
const WALL_MASK := 1

signal map_state_changed
var _game_over_running: bool = false

# Game Over FX
const GAME_OVER_SHAKE_DUR: float = 1.8
const GAME_OVER_SHAKE_MAG: float = 8.0
const GAME_OVER_FADE_OUT: float = 3.0
const GAME_OVER_FADE_IN: float = 0.9

# ----- Nodes -----
@onready var screen_root: Node2D = $ScreenRoot
@onready var player: CharacterBody2D = $Player
@onready var steps_label: Label = $UI/StepsLabel
@onready var choice_panel: PanelContainer = $UI/ChoicePanel
@onready var option_buttons: Array[Button] = [
	$UI/ChoicePanel/MarginContainer/VBoxContainer/Option1,
	$UI/ChoicePanel/MarginContainer/VBoxContainer/Option2,
	$UI/ChoicePanel/MarginContainer/VBoxContainer/Option3
]
@onready var fade_layer: CanvasLayer = $UI/FadeLayer
@onready var fade_black: ColorRect 
@onready var map_overlay: Control = $MapOverlay/MapRoot
@onready var dialog_box: Control = $UI/DialogueBox

# ----- State -----
var pending_dir := Vector2i.ZERO
var candidate_defs: Array = []
var _menu_index: int = 0
var is_transitioning: bool = false	# only suppresses edge checks; player keeps moving

func _dev_enabled() -> bool:
	return GameConfig.DEV_MODE

func _show_edge_walls() -> bool:
	return GameConfig.DEV_MODE and GameConfig.SHOW_EDGE_WALLS

func _ready() -> void:
	ROCK_LAYER = GameConfig.WALL_LAYER
	ROCK_MASK = GameConfig.WALL_MASK
	print("Has /root/ItemDb? ", has_node("/root/ItemDb"))

	# make sure the fade overlay starts fully transparent
	_fade_reset_to_clear()
	
	RunState.start_tutorial()

	_load_room_at(RunState.pos, RunState.start_room_path)
	player.position = Vector2(SCREEN_SIZE.x / 2.0 + 16, SCREEN_SIZE.y / 2.0)
	_update_hud()
	_close_choice_panel()

	for i in range(option_buttons.size()):
		option_buttons[i].pressed.connect(_on_option_pressed.bind(i))

func _physics_process(_delta: float) -> void:
	if choice_panel.visible:
		return
	if is_transitioning:
		return
	_check_edges()

func _check_edges() -> void:
	var p := player.position
	var room_w := MAP_W * TILE
	var room_h := MAP_H * TILE
	if p.x <= EXIT_BAND:
		_propose_transition(Vector2i(-1, 0)); return
	if p.x >= room_w - EXIT_BAND:
		_propose_transition(Vector2i(1, 0)); return
	if p.y <= EXIT_BAND:
		_propose_transition(Vector2i(0, -1)); return
	if p.y >= room_h - EXIT_BAND:
		_propose_transition(Vector2i(0, 1)); return

# Map move direction -> entry side of the NEW room
func _entry_side_for_dir(dir: Vector2i) -> String:
	if dir == Vector2i(-1, 0):
		return "E"
	elif dir == Vector2i(1, 0):
		return "W"
	elif dir == Vector2i(0, -1):
		return "S"
	elif dir == Vector2i(0, 1):
		return "N"
	return "?"

# world-bounds helper
func _in_world_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GRID_W and c.y >= 0 and c.y < GRID_H

func _propose_transition(dir: Vector2i) -> void:
	if choice_panel.visible or is_transitioning:
		return

	pending_dir = dir
	var next := RunState.pos + dir

	# hard-cap to 8x8 → if out-of-bounds, just bonk
	if not _in_world_bounds(next):
		_show_no_exit_feedback(_dir_to_string(dir))
		return

	# If destination already placed, only enter if that side is open there
	if RunState.visited.has(next):
		var path_existing: String = RunState.visited[next]
		var entry_side_existing := _entry_side_for_dir(dir)
		var side_is_open := true
		if "entry_open_for_path" in RunState:
			side_is_open = RunState.entry_open_for_path(path_existing, entry_side_existing)

		if side_is_open:
			_perform_transition(next, path_existing)
		else:
			_refresh_edge_blockers_for_current_room()
			_refresh_edge_rocks_for_current_room()
		return

	# New destination: pick candidates
	var entry_side := _entry_side_for_dir(dir)
	var base_candidates: Array = RunState.pick_room_candidates(entry_side, 12)
	var tut: Array = RunState.pick_room_candidates_for_tutorial(entry_side, next, 12)
	if tut.size() > 0: base_candidates = tut

	# constrain options at map edges
	var nx := next.x
	var ny := next.y
	candidate_defs = _edge_constrained_candidates(base_candidates, nx, ny)

	# Prepare UI text
	for i in range(option_buttons.size()):
		if i < candidate_defs.size():
			var def: Dictionary = candidate_defs[i]
			var nice: String = ""
			if def.has("name"):
				nice = String(def["name"])
			else:
				var pth: String = String(def.get("path", ""))
				nice = pth.get_file().get_basename().capitalize().replace("_", " ")
			nice += "   " + _exit_arrows_inline(def, entry_side)
			option_buttons[i].text = nice
			option_buttons[i].visible = true
		else:
			option_buttons[i].visible = false

	# If nothing to show, treat like wall
	if candidate_defs.size() == 0:
		_refresh_edge_blockers_for_current_room()
		_refresh_edge_rocks_for_current_room()
		return

	_open_choice_panel()

# Southmost row → only "beach"; Leftmost col → only "path"
# --- kind helper used by edge constraints ---
func _has_kind(def: Dictionary, kind: String) -> bool:
	var k := kind.to_lower()
	if def.has("type") and String(def["type"]).to_lower() == k:
		return true
	if def.has("tags") and def["tags"] is Array:
		for t in def["tags"]:
			if String(t).to_lower() == k:
				return true
	var name_s := String(def.get("name", "")).to_lower()
	var path_s := String(def.get("path", "")).to_lower()
	return name_s.findn(k) != -1 or path_s.findn(k) != -1

# Southmost row → allow beach only there (forbid elsewhere)
# Top row → allow mountain only there (forbid elsewhere)
# Leftmost col → only "path" (unchanged rule)
func _edge_constrained_candidates(base: Array, nx:int, ny:int) -> Array:
	# Far-left column: only path
	if nx == 0:
		var only_path: Array = []
		for def in base:
			if typeof(def) == TYPE_DICTIONARY and _has_kind(def, "path"):
				only_path.append(def)
		return only_path if only_path.size() > 0 else base

	var filtered: Array = []
	var forbid_beach := (ny != GRID_H - 1)
	var forbid_mountain := (ny != 0)

	for def in base:
		if typeof(def) != TYPE_DICTIONARY:
			continue
		if forbid_beach and _has_kind(def, "beach"):
			continue
		if forbid_mountain and _has_kind(def, "mountain"):
			continue
		filtered.append(def)

	# If everything got filtered (rare), fall back so the player isn't stuck
	return filtered if filtered.size() > 0 else base

func _on_option_pressed(index: int) -> void:
	var next := RunState.pos + pending_dir
	var def: Dictionary = candidate_defs[index]
	var path: String = def["path"]

	if map_overlay and map_overlay.visible:
		map_overlay.refresh()

	# Place the room regardless (permissive)
	RunState.visited[next] = path
	if "mark_used_if_unique" in RunState:
		RunState.mark_used_if_unique(def)
	if "notify_room_picked" in RunState:
		RunState.notify_room_picked(next, path)
		
	emit_signal("map_state_changed")

	# Can we enter from this side NOW?
	var entry_side := _entry_side_for_dir(pending_dir)
	var can_enter_now := true
	if "entry_open_for_path" in RunState:
		can_enter_now = RunState.entry_open_for_path(path, entry_side)

	if can_enter_now:
		_perform_transition(next, path)
	else:
		_close_choice_panel()
		_refresh_edge_blockers_for_current_room()
		_refresh_edge_rocks_for_current_room()

# -------------------------------
# Non-blocking transition orchestration
# -------------------------------
func _perform_transition(next_coord: Vector2i, path: String) -> void:
	if not is_instance_valid(fade_layer):
		_do_room_swap(next_coord, path)
		return

	is_transitioning = true

	fade_layer.fade_through_black(
		0.20,	# fade out
		0.30,	# fade in
		func() -> void:
			_do_room_swap(next_coord, path)
			is_transitioning = false
	)

func _do_room_swap(next_coord: Vector2i, path: String) -> void:
	_clear_room()

	# --- exact center of the middle tile on the opposite edge (9x9, 16px) ---
	var mid_col := (MAP_W - 1) / 2
	var mid_row := (MAP_H - 1) / 2
	var spawn := Vector2(SCREEN_SIZE.x / 2.0, SCREEN_SIZE.y / 2.0)

	if pending_dir == Vector2i(-1, 0):
		spawn = Vector2((MAP_W - 1 + 0.5) * TILE, (mid_row + 0.5) * TILE)
	elif pending_dir == Vector2i(1, 0):
		spawn = Vector2((0 + 0.5) * TILE, (mid_row + 0.5) * TILE)
	elif pending_dir == Vector2i(0, -1):
		spawn = Vector2((mid_col + 0.5) * TILE, (MAP_H - 1 + 0.5) * TILE)
	elif pending_dir == Vector2i(0, 1):
		spawn = Vector2((mid_col + 0.5) * TILE, (0 + 0.5) * TILE)

	var ps := load(path)
	if ps == null:
		push_error("Could not load room: " + path)
		_game_over()
		return
	var room := (ps as PackedScene).instantiate()
	screen_root.add_child(room)

	# Visual blockers / decorations
	_apply_edge_rocks(room, path, next_coord)
	if USE_EDGE_BLOCKERS:
		_apply_edge_blockers(room, path, next_coord)

	# --- NPCs, chests, pickups ---
	_spawn_npcs(room, path, next_coord)
	_spawn_chests(room, path, next_coord)
	_spawn_pickups(room, path, next_coord)

	# Update run state + spawn player
	RunState.pos = next_coord
	player.position = spawn

	if choice_panel.visible:
		_close_choice_panel()

	RunState.steps_left -= 1
	_update_hud()
	if RunState.steps_left <= 0:
		_game_over()

	if map_overlay and map_overlay.visible:
		map_overlay.refresh()

# -------------------------------
# HUD / basic helpers
# -------------------------------
func _update_hud() -> void:
	steps_label.text = "Steps: %d   Seed: %d" % [RunState.steps_left, RunState.seed]

func _clear_room() -> void:
	for c in screen_root.get_children():
		c.queue_free()

func _game_over() -> void:
	if _game_over_running:
		return
	_game_over_running = true

	# Allow movement, but stop room transitions during the sequence
	is_transitioning = true

	# Start quake in parallel (do NOT await)
	_shake_world(GAME_OVER_SHAKE_DUR, GAME_OVER_SHAKE_MAG)

	# Ensure the fade starts from fully clear (not pre-dark)
	_fade_reset_to_clear()

	# Long game-over fade; player can keep moving during fade-out
	if is_instance_valid(fade_layer):
		fade_layer.fade_through_black(
			GAME_OVER_FADE_OUT,	# ~3s fade to black from alpha 0
			GAME_OVER_FADE_IN,	# quick fade-in after reset
			func() -> void:
				# We are fully black now → freeze, reset, then re-enable for fade-in
				if "set_input_enabled" in player:
					player.set_input_enabled(false)

				RunState.new_run()
				_clear_room()
				_load_room_at(RunState.pos, RunState.start_room_path)
				player.position = Vector2(SCREEN_SIZE.x / 2.0 + 32, SCREEN_SIZE.y / 2.0 - 10)
				_update_hud()
				emit_signal("map_state_changed")

				is_transitioning = false

				if "set_input_enabled" in player:
					player.set_input_enabled(true)

				_game_over_running = false
		)
	else:
		# Fallback if no FadeLayer
		RunState.new_run()
		_clear_room()
		_load_room_at(RunState.pos, RunState.start_room_path)
		player.position = Vector2(SCREEN_SIZE.x / 2.0, SCREEN_SIZE.y / 2.0)

		_update_hud()
		emit_signal("map_state_changed")
		is_transitioning = false
		_game_over_running = false

func _load_room_at(at_coord: Vector2i, path: String) -> void:
	var ps := load(path)
	if ps == null:
		push_error("Could not load room: " + path)
		return

	var room := (ps as PackedScene).instantiate()
	screen_root.add_child(room)

	RunState.visited[at_coord] = path
	emit_signal("map_state_changed")

	_apply_edge_rocks(room, path, at_coord)
	if USE_EDGE_BLOCKERS:
		_apply_edge_blockers(room, path, at_coord)

	_spawn_npcs(room, path, at_coord)
	_spawn_chests(room, path, at_coord)
	_spawn_pickups(room, path, at_coord)

# -------------------------------
# Input / UI
# -------------------------------
func _open_choice_panel() -> void:
	choice_panel.visible = true
	if "set_input_enabled" in player:
		player.set_input_enabled(false)

	_menu_index = 0
	for i in range(option_buttons.size()):
		if option_buttons[i].visible:
			_menu_index = i
			break
	option_buttons[_menu_index].grab_focus()

func _close_choice_panel() -> void:
	choice_panel.visible = false
	if "set_input_enabled" in player:
		player.set_input_enabled(true)

func _unhandled_input(event: InputEvent) -> void:
	# ignore menus while game-over FX are running
	if _game_over_running:
		return

	# If the choice panel is open, only handle its navigation.
	if choice_panel.visible:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
			var i := _menu_index - 1
			while i >= 0:
				if option_buttons[i].visible:
					_menu_index = i
					break
				i -= 1
			option_buttons[_menu_index].grab_focus()
			get_viewport().set_input_as_handled()
			return

		elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
			var i2 := _menu_index + 1
			while i2 < option_buttons.size():
				if option_buttons[i2].visible:
					_menu_index = i2
					break
				i2 += 1
			option_buttons[_menu_index].grab_focus()
			get_viewport().set_input_as_handled()
			return
		return

	# If a dialogue is visible, let the DialogueBox consume input.
	if is_instance_valid(dialog_box) and dialog_box.visible:
		return

	# Don't open dialogue over the map overlay.
	if map_overlay and map_overlay.visible:
		return

	# Interact with nearest NPC.
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		var npc := _nearest_npc()
		if npc != null:
			_start_dialog(npc)
			get_viewport().set_input_as_handled()
			return

func _input(event: InputEvent) -> void:
	# ignore extra input toggles while game-over FX are running
	if _game_over_running:
		return

	if event.is_action_pressed("show_map"):
		if map_overlay != null:
			map_overlay.toggle()
			if "set_input_enabled" in player:
				player.set_input_enabled(not map_overlay.visible)
			get_viewport().set_input_as_handled()

# Simple feedback when trying to walk outside the 8x8 world
func _show_no_exit_feedback(dir:String) -> void:
	var nudge := Vector2.ZERO
	match dir:
		"left":  nudge = Vector2(4, 0)
		"right":  nudge = Vector2(-4, 0)
		"up":  nudge = Vector2(0, 4)
		"down":  nudge = Vector2(0, -4)
	player.position += nudge

# -------------------------------
# ROCKS (MULTIPLE + COLLIDER)
# -------------------------------
func _apply_edge_rocks(room: Node2D, room_path: String, coord: Vector2i) -> void:
	if room.has_node("__EdgeRocks"):
		room.get_node("__EdgeRocks").queue_free()

	var root := Node2D.new()
	root.name = "__EdgeRocks"
	room.add_child(root)

	# 1) Is the edge blocked by neighbor/world?
	var blocked := {
		"N": _is_side_blocked_by_neighbor_or_edge(coord, "N"),
		"E": _is_side_blocked_by_neighbor_or_edge(coord, "E"),
		"S": _is_side_blocked_by_neighbor_or_edge(coord, "S"),
		"W": _is_side_blocked_by_neighbor_or_edge(coord, "W"),
	}

	# 2) Does THIS room actually have an opening on that edge?
	#    (If no opening here, we don't paint rocks.)
	var open_here := {
		"N": map_is_side_open_here(coord, "N"),
		"E": map_is_side_open_here(coord, "E"),
		"S": map_is_side_open_here(coord, "S"),
		"W": map_is_side_open_here(coord, "W"),
	}

	# Place rocks only when it's blocked AND we have an opening here
	var place := {
		"N": blocked["N"] and open_here["N"],
		"E": blocked["E"] and open_here["E"],
		"S": blocked["S"] and open_here["S"],
		"W": blocked["W"] and open_here["W"],
	}

	if place["W"]:
		for row in range(MAP_H):
			var p := _edge_pos_for_cell("W", 0, row)
			_spawn_rock(root, p)

	if place["E"]:
		for row in range(MAP_H):
			var p := _edge_pos_for_cell("E", MAP_W - 1, row)
			_spawn_rock(root, p)

	if place["N"]:
		for col in range(MAP_W):
			var p := _edge_pos_for_cell("N", col, 0)
			_spawn_rock(root, p)

	if place["S"]:
		for col in range(MAP_W):
			var p := _edge_pos_for_cell("S", col, MAP_H - 1)
			_spawn_rock(root, p)

func _is_side_blocked_by_neighbor_or_edge(coord: Vector2i, side: String) -> bool:
	var d := _side_to_vec_world(side)
	var n := coord + d
	# world edge blocks
	if n.x < 0 or n.x >= GRID_W or n.y < 0 or n.y >= GRID_H:
		return true

	# neighbor not placed yet => NOT blocked (we allow stepping to place)
	if not RunState.visited.has(n):
		return false

	var this_path := String(RunState.visited.get(coord, ""))
	var neigh_path := String(RunState.visited.get(n, ""))
	var this_open := RunState.entry_open_for_path(this_path, side)
	var opp := _opp_side(side)
	var neigh_open := RunState.entry_open_for_path(neigh_path, opp)

	# blocked if either side is closed
	return not (this_open and neigh_open)

func _side_to_vec_world(side: String) -> Vector2i:
	if side == "N": return Vector2i(0, -1)
	if side == "S": return Vector2i(0, 1)
	if side == "E": return Vector2i(1, 0)
	if side == "W": return Vector2i(-1, 0)
	return Vector2i.ZERO

func _opp_side(side: String) -> String:
	if side == "N": return "S"
	if side == "S": return "N"
	if side == "E": return "W"
	if side == "W": return "E"
	return side

# Position a rock along the edge centered on a tile's middle
func _edge_pos_for_cell(side: String, col: int, row: int) -> Vector2:
	var x_center := (col + 0.5) * TILE
	var y_center := (row + 0.5) * TILE
	match side:
		"W": return Vector2(0.5 * TILE, y_center)
		"E": return Vector2((MAP_W - 0.5) * TILE, y_center)
		"N": return Vector2(x_center, 0.5 * TILE)
		"S": return Vector2(x_center, (MAP_H - 0.5) * TILE)
	return Vector2(x_center, y_center)

# Spawn a sprite + collider for one rock
func _spawn_rock(parent: Node, pos: Vector2) -> void:
	if ROCK_TEX == null:
		return
	var spr := Sprite2D.new()
	spr.texture = ROCK_TEX
	spr.position = pos
	spr.z_index = ROCK_Z
	spr.scale = ROCK_SCALE
	parent.add_child(spr)

	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = ROCK_LAYER
	body.collision_mask = ROCK_MASK
	body.z_index = ROCK_Z
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = ROCK_COLLIDER_SIZE
	shape.shape = r
	body.add_child(shape)
	parent.add_child(body)

# -------------------------------
# EDGE BLOCKERS (optional)
# -------------------------------
func _apply_edge_blockers(room: Node, room_path: String, coord: Vector2i = RunState.pos) -> void:
	var open_N := true
	var open_E := true
	var open_S := true
	var open_W := true

	if "get_def_by_path" in RunState:
		var def := RunState.get_def_by_path(room_path)
		if def.size() > 0 and def.has("entry_open"):
			var eo = def["entry_open"]
			if eo.has("N"): open_N = bool(eo["N"])
			if eo.has("E"): open_E = bool(eo["E"])
			if eo.has("S"): open_S = bool(eo["S"])
			if eo.has("W"): open_W = bool(eo["W"])

	if "entry_open_for_path" in RunState:
		var ncoord := coord + Vector2i(0, -1)
		if RunState.visited.has(ncoord) and not RunState.entry_open_for_path(String(RunState.visited[ncoord]), "S"):
			open_N = false
		var ecoord := coord + Vector2i(1, 0)
		if RunState.visited.has(ecoord) and not RunState.entry_open_for_path(String(RunState.visited[ecoord]), "W"):
			open_E = false
		var scoord := coord + Vector2i(0, 1)
		if RunState.visited.has(scoord) and not RunState.entry_open_for_path(String(RunState.visited[scoord]), "N"):
			open_S = false
		var wcoord := coord + Vector2i(-1, 0)
		if RunState.visited.has(wcoord) and not RunState.entry_open_for_path(String(RunState.visited[wcoord]), "E"):
			open_W = false

	if room.has_node("__EdgeBlockers"):
		room.get_node("__EdgeBlockers").queue_free()

	var container := Node2D.new()
	container.name = "__EdgeBlockers"
	room.add_child(container)

	var inset := GameConfig.EDGE_INSET
	var thick := GameConfig.EDGE_THICK
	var over  := GameConfig.EDGE_OVERHANG
	var zed   := GameConfig.EDGE_Z
	var lay   := GameConfig.WALL_LAYER
	var mask  := GameConfig.WALL_MASK

	if not open_W:
		_add_wall(container, Rect2(inset, -over, thick, SCREEN_SIZE.y + 2.0 * over), "WALL_W", lay, mask, zed)
	if not open_E:
		_add_wall(container, Rect2(SCREEN_SIZE.x - inset - thick, -over, thick, SCREEN_SIZE.y + 2.0 * over), "WALL_E", lay, mask, zed)
	if not open_N:
		_add_wall(container, Rect2(-over, inset, SCREEN_SIZE.x + 2.0 * over, thick), "WALL_N", lay, mask, zed)
	if not open_S:
		_add_wall(container, Rect2(-over, SCREEN_SIZE.y - inset - thick, SCREEN_SIZE.x + 2.0 * over, thick), "WALL_S", lay, mask, zed)

	if _show_edge_walls():
		print("[EdgeBlockers] ", room_path, " @", coord, " open(N/E/S/W) = ",
			open_N, "/", open_E, "/", open_S, "/", open_W)

func _add_wall(parent: Node, rect: Rect2, label: String, layer: int, mask: int, zed: int) -> void:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = mask
	body.z_index = zed

	var shape := CollisionShape2D.new()
	var rshape := RectangleShape2D.new()
	rshape.size = rect.size
	shape.shape = rshape
	body.position = rect.position + rect.size * 0.5
	shape.position = Vector2.ZERO
	body.add_child(shape)
	parent.add_child(body)

	if _show_edge_walls():
		var col := GameConfig.EDGE_COLOR
		var poly := Polygon2D.new()
		poly.color = col
		poly.z_index = zed
		var hx := rect.size.x * 0.5
		var hy := rect.size.y * 0.5
		poly.polygon = PackedVector2Array([
			Vector2(-hx, -hy),
			Vector2( hx, -hy),
			Vector2( hx,  hy),
			Vector2(-hx,  hy),
		])
		poly.position = body.position
		parent.add_child(poly)

# Rebuild blockers for the CURRENT room using neighbor info
func _refresh_edge_blockers_for_current_room() -> void:
	if not USE_EDGE_BLOCKERS:
		return
	var room := _get_current_room()
	if room == null:
		return
	var cur_path := ""
	if RunState.visited.has(RunState.pos):
		cur_path = String(RunState.visited[RunState.pos])
	_apply_edge_blockers(room, cur_path, RunState.pos)

# Rebuild ROCKS for the CURRENT room using up-to-date neighbor info
func _refresh_edge_rocks_for_current_room() -> void:
	var room := _get_current_room()
	if room == null:
		return
	var cur_path := ""
	if RunState.visited.has(RunState.pos):
		cur_path = String(RunState.visited[RunState.pos])
	_apply_edge_rocks(room, cur_path, RunState.pos)

func _get_current_room() -> Node2D:
	for c in screen_root.get_children():
		if c is Node2D:
			return c
	return null

# --- Exit helpers ---
func _def_open_map(def: Dictionary) -> Dictionary:
	if def.has("entry_open"):
		return def["entry_open"]
	if def.has("exits"):
		return def["exits"]
	return {"N": true, "E": true, "S": true, "W": true}

func _def_exit_sides(def: Dictionary) -> Array[String]:
	var m := _def_open_map(def)
	var sides: Array[String] = []
	if m.has("N") and m["N"]:
		sides.append("N")
	if m.has("E") and m["E"]:
		sides.append("E")
	if m.has("S") and m["S"]:
		sides.append("S")
	if m.has("W") and m["W"]:
		sides.append("W")
	return sides

func _arrow_for_side(side: String) -> String:
	if side == "N":
		return "↑"
	if side == "E":
		return "→"
	if side == "S":
		return "↓"
	if side == "W":
		return "←"
	return "?"

func _exit_arrows_inline(def: Dictionary, entry_side: String) -> String:
	if not def.has("entry_open"):
		return ""
	var eo: Dictionary = def["entry_open"]
	var arrows := []
	if eo.get("W", false) and entry_side != "W": arrows.append("←")
	if eo.get("N", false) and entry_side != "N": arrows.append("↑")
	if eo.get("S", false) and entry_side != "S": arrows.append("↓")
	if eo.get("E", false) and entry_side != "E": arrows.append("→")
	return " ".join(arrows)

func _def_exit_tooltip(def: Dictionary) -> String:
	var sides: Array[String] = _def_exit_sides(def)
	var label_map := {"N":"North","E":"East","S":"South","W":"West"}
	var human: Array[String] = []
	for s in sides:
		human.append(label_map[s])
	return "Exits: %s (%d)" % [", ".join(human), sides.size()]

# helper for debug text on out-of-bounds
func _dir_to_string(d: Vector2i) -> String:
	if d == Vector2i.LEFT: return "left"
	if d == Vector2i.RIGHT: return "right"
	if d == Vector2i.UP: return "up"
	if d == Vector2i.DOWN: return "down"
	return str(d)

# -------------------------------
# NPCs
# -------------------------------
func _spawn_npcs(room: Node2D, room_path: String, coord: Vector2i) -> void:
	var def: Dictionary = RunState.get_def_for_spawn(room_path, coord)
	if def.size() == 0 or not def.has("npcs"):
		return
	var arr: Array = def["npcs"] as Array
	if arr.is_empty():
		return

	var root := Node2D.new()
	root.name = "__NPCs"
	room.add_child(root)

	for item in arr:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item as Dictionary
		var npc := NPC_SCENE.instantiate()
		if d.has("sprite"):
			npc.set("sprite_path", String(d["sprite"]))
		if d.has("tile"):
			npc.set("tile", d["tile"])
		npc.set("tile_size", TILE)
		if d.has("lines"):
			npc.set("dialog_lines", d["lines"])
		# --- NEW: wire up the "need" (trade) if present ---
		if d.has("need") and d["need"] is Dictionary:
			var need := d["need"] as Dictionary
			if need.has("item_id"): npc.set("required_item_id", String(need["item_id"]))
			if need.has("amount"):  npc.set("required_amount", int(need["amount"]))
			if need.has("uid"):     npc.set("trade_uid", String(need["uid"]))
			# texts
			if need.has("lines_before"): npc.set("lines_before", need["lines_before"])
			if need.has("lines_on_give"): npc.set("lines_on_give", need["lines_on_give"])
			if need.has("lines_after"): npc.set("lines_after", need["lines_after"])
			# reward
			if need.has("reward") and need["reward"] is Dictionary:
				var rw := need["reward"] as Dictionary
				if rw.has("item_id"): npc.set("reward_item_id", String(rw["item_id"]))
				if rw.has("amount"):  npc.set("reward_amount", int(rw["amount"]))
			# auto-consume on talk (default true; override by passing "take_on_talk": false)
			if need.has("take_on_talk"):
				npc.set("take_on_talk", bool(need["take_on_talk"]))

		root.add_child(npc)

func _nearest_npc(max_dist: float = 18.0) -> StaticBody2D:
	var best: StaticBody2D = null
	var best_d: float = INF
	for obj in get_tree().get_nodes_in_group("npc"):
		if not (obj is StaticBody2D):
			continue
		var npc: StaticBody2D = obj as StaticBody2D
		var d: float = (npc.global_position - player.global_position).length()
		if d <= max_dist and d < best_d:
			best = npc
			best_d = d
	return best

func _start_dialog(npc: Node) -> void:
	if not is_instance_valid(dialog_box):
		print("DialogueBox not found!")
		return
	if "set_input_enabled" in player:
		player.set_input_enabled(false)

	var lines: PackedStringArray = PackedStringArray()

	if npc.has_method("get_dialog_lines"):
		var tmp: Variant = npc.call("get_dialog_lines")
		if tmp is PackedStringArray:
			lines = tmp
		elif tmp is Array:
			lines = PackedStringArray(tmp)
		elif tmp is String:
			lines = PackedStringArray([tmp])
	else:
		var raw: Variant = npc.get("dialog_lines")
		if raw is PackedStringArray:
			lines = raw
		elif raw is Array:
			lines = PackedStringArray(raw)
		elif raw is String:
			lines = PackedStringArray([raw])

	if dialog_box.has_method("open"):
		dialog_box.call("open", lines)
	else:
		print("DialogueBox has no `open(lines)` method")

	if dialog_box.is_connected("finished", Callable(self, "_on_dialog_finished")):
		dialog_box.disconnect("finished", Callable(self, "_on_dialog_finished"))
	dialog_box.connect("finished", Callable(self, "_on_dialog_finished"))

func _on_dialog_finished() -> void:
	if "set_input_enabled" in player:
		player.set_input_enabled(true)

# -------------------------------
# CHESTS
# -------------------------------
func _spawn_chests(room: Node2D, room_path: String, coord: Vector2i) -> void:
	var def: Dictionary = RunState.get_def_for_spawn(room_path, coord)
	if def.size() == 0 or not def.has("chests"):
		return
	var arr: Array = def["chests"] as Array
	if arr.is_empty():
		return

	var root := Node2D.new()
	root.name = "__Chests"
	room.add_child(root)

	for item in arr:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item as Dictionary

		# Skip if already opened (by UID), if your RunState tracks this
		var uid := String(d.get("uid", ""))
		if uid != "":
			var skip := false
			if "was_chest_opened" in RunState:
				skip = RunState.was_chest_opened(uid)
			if skip:
				continue

		var chest := CHEST_SCENE.instantiate()
		if d.has("item_id"):
			chest.set("item_id", String(d["item_id"]))
		if d.has("amount"):
			chest.set("amount", int(d["amount"]))
		if uid != "":
			chest.set("chest_uid", uid)

		# Position: prefer 'tile' Vector2i; otherwise {x,y}
		if d.has("tile"):
			var t: Vector2i = d["tile"]
			chest.position = Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)
		else:
			var cx := int(d.get("x", 0))
			var cy := int(d.get("y", 0))
			chest.position = Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)

		root.add_child(chest)

# -------------------------------
# PICKUPS (data-driven ground items)
# -------------------------------
func _spawn_pickups(room: Node2D, room_path: String, coord: Vector2i) -> void:
	var def: Dictionary = RunState.get_def_for_spawn(room_path, coord)
	if def.size() == 0 or not def.has("pickups"):
		return
	var arr: Array = def["pickups"] as Array
	if arr.is_empty():
		return

	# Make a container so we can clear them cleanly on swap
	if room.has_node("__Pickups"):
		room.get_node("__Pickups").queue_free()
	var root := Node2D.new()
	root.name = "__Pickups"
	room.add_child(root)

	for item in arr:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item as Dictionary

		var uid := String(d.get("uid", ""))
		if uid != "":
			var picked := false
			if "was_item_picked" in RunState:
				picked = RunState.was_item_picked(uid)
			elif "was_chest_opened" in RunState:
				# fallback if you haven't added item tracking yet
				picked = RunState.was_chest_opened(uid)
			if picked:
				continue

		var node := ITEM_PICKUP_SCENE.instantiate()

		# set properties BEFORE add_child (so _ready uses the right item_id)
		if d.has("item_id"): node.item_id = String(d["item_id"])
		if d.has("amount"):  node.amount  = int(d["amount"])
		if uid != "":        node.pickup_uid = uid
		if d.has("auto"):    node.auto_pickup = bool(d["auto"])

		# position
		var pos: Vector2
		if d.has("tile"):
			var t: Vector2i = d["tile"]
			pos = Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)
		else:
			var px := int(d.get("x", 0))
			var py := int(d.get("y", 0))
			pos = Vector2((px + 0.5) * TILE, (py + 0.5) * TILE)
		node.position = pos

		# now add to the scene
		root.add_child(node)

# --- Map query helpers (used by MapRoot) ---
func map_is_side_open_here(coord: Vector2i, side: String) -> bool:
	var path := String(RunState.visited.get(coord, ""))
	if path == "":
		return false
	if "entry_open_for_path" in RunState:
		return RunState.entry_open_for_path(path, side)
	return true

func map_is_exit_open_between(coord: Vector2i, side: String) -> bool:
	var d := _side_to_vec_world(side)
	var n := coord + d
	if not _in_world_bounds(n):
		return false
	if not RunState.visited.has(n):
		return false
	return not _is_side_blocked_by_neighbor_or_edge(coord, side)

# -------------------------------
# FX helpers
# -------------------------------
func _shake_world(duration: float = 0.6, magnitude: float = 6.0) -> void:
	var t := 0.0
	var orig := screen_root.position
	while t < duration:
		var decay := 1.0 - (t / duration)	# ease out
		var off := Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * magnitude * decay
		screen_root.position = orig + off
		await get_tree().process_frame
		t += get_process_delta_time()
	# restore
	screen_root.position = orig

func _fade_reset_to_clear() -> void:
	if is_instance_valid(fade_black):
		var c := fade_black.color
		fade_black.color = Color(c.r, c.g, c.b, 0.0)	# start fully transparent
