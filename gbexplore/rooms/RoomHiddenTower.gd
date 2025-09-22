extends Node2D

@onready var _icons := {
	"circle":   $Icon1,
	"triangle": $Icon2,
	"square":   $Icon3,
}

const _DARK := {
	"circle":   "res://art/icon1-circle.png",
	"triangle": "res://art/icon2-triangle.png",
	"square":   "res://art/icon3-square.png",
}
const _LIT := {
	"circle":   "res://art/icon1-circle-lit.png",
	"triangle": "res://art/icon2-triangle-lit.png",
	"square":   "res://art/icon3-square-lit.png",
}

# ------- DOOR (TileMap) CONFIG -------
@export var door_tilemap: NodePath = ^"TileMap"
@export var door_layer: int = 0
@export var door_cell: Vector2i = Vector2i(4, 3)

@export var door_source_id_closed: int = 2
@export var door_atlas_closed: Vector2i = Vector2i(4, 2)  # confirm this
@export var door_source_id_open: int = 2
@export var door_atlas_open: Vector2i = Vector2i(4, 3)
@export var door_alternative: int = 0

# ---- ENTERING THE DOOR ----
@export var target_room_path: String = "res://rooms/room_witch.tscn"
@export var trigger_margin_px: int = 2

var _door_open := false
var _door_trigger: Area2D = null

func _ready() -> void:
	RunState.button_group_add("triangle", 3)
	RunState.button_group_add("square", 1)
	for key in _icons.keys():
		_apply_icon(key, _is_key_lit(key))
	_update_door_now()

	if not RunState.is_connected("button_state_changed", _on_button_state_changed):
		RunState.button_state_changed.connect(_on_button_state_changed)

func _on_button_state_changed(key: String, _active: bool) -> void:
	if _icons.has(key):
		_apply_icon(key, _is_key_lit(key))
	if key == "triangle" or key == "square":
		_update_door_now()

func _is_key_lit(key: String) -> bool:
	var count := RunState.button_group_count(key)
	match key:
		"triangle":
			return count >= 3
		_:
			return count >= 1

func _apply_icon(key: String, active: bool) -> void:
	var node = _icons.get(key, null)
	if node == null:
		return
	var path = (_LIT[key] if active else _DARK[key])
	var tex := load(path)
	if tex:
		node.texture = tex

# -------- Door helpers --------
func _should_be_open() -> bool:
	return _is_key_lit("triangle") and _is_key_lit("square")

func _update_door_now() -> void:
	var want_open := _should_be_open()
	if want_open != _door_open:
		_apply_door(want_open)
		_door_open = want_open
	_sync_trigger_to_state()

func _apply_door(open: bool) -> void:
	var tm: TileMap = get_node_or_null(door_tilemap)
	if tm == null:
		return
	if open:
		tm.set_cell(door_layer, door_cell, door_source_id_open, door_atlas_open, door_alternative)
	else:
		tm.set_cell(door_layer, door_cell, door_source_id_closed, door_atlas_closed, door_alternative)

func _sync_trigger_to_state() -> void:
	var tm: TileMap = get_node_or_null(door_tilemap)
	if tm == null:
		return

	# Create trigger ONCE as a child of the TileMap (local coords are easy)
	if _door_trigger == null:
		_door_trigger = Area2D.new()
		_door_trigger.name = "DoorTrigger"
		# Layers: put trigger on some unused layer (irrelevant), but mask must include the player.
		# Default fallback assumes player layer=1; try to detect from ScreenManager if possible.
		var player_layer := 1
		var sm := get_tree().get_first_node_in_group("screen_manager")
		if sm and "player" in sm and sm.player:
			player_layer = sm.player.collision_layer
		_door_trigger.collision_layer = 0
		_door_trigger.collision_mask = player_layer

		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		var ts := tm.tile_set.tile_size
		rect.size = Vector2(10,10)
		cs.shape = rect
		_door_trigger.add_child(cs)
		_door_trigger.visible = false
		_door_trigger.monitoring = true
		_door_trigger.monitorable = true
		tm.add_child(_door_trigger)  # parent to TileMap

		# connect once
		_door_trigger.body_entered.connect(_on_door_trigger_body_entered)

	# Position to the center of the door cell (TileMap-local)
	var top_left := tm.map_to_local(door_cell)
	var ts2 := tm.tile_set.tile_size
	_door_trigger.position = top_left + Vector2(ts2.x * 0.5, ts2.y * 0.5)

	# Enable only when door is open
	_door_trigger.set_deferred("monitoring", _door_open)
	_door_trigger.set_deferred("monitorable", _door_open)

func _on_door_trigger_body_entered(body: Node) -> void:
	if not _door_open: return
	if not body.is_in_group("player"): return
	_enter_target_room()

func _enter_target_room() -> void:
	if target_room_path == "":
		return

	RunState.pos = Vector2i(0, 1)  # optional: update where this room is mapped to
	var sm := get_tree().get_first_node_in_group("screen_manager")
	if sm and sm.has_method("enter_room_direct"):
		sm.enter_room_direct(target_room_path, Vector2i(4, 7))  # tile coords!
	else:
		get_tree().change_scene_to_file(target_room_path)
