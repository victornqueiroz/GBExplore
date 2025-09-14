# res://actors/ButtonSetup.gd
extends Node
# Lightweight, buttons-only room setup helper.

@export var buttons: Array[Dictionary] = []
# Each entry:
# { tile = Vector2i(x, y), key = "optional_unique_key", one_shot = true }
# - tile: REQUIRED (tile coordinate inside the room)
# - key:  OPTIONAL (if omitted, an auto-key "room_path|(x,y)" is used)
# - one_shot: OPTIONAL (default true)

@export var tile_size: int = 16  # override per room if your tiles aren't 16px

const FLOOR_BUTTON_SCENE := preload("res://actors/FloorButton.tscn")

func _ready() -> void:
	# Group lets ScreenManager find and trigger all setups under the current room
	add_to_group("button_setup")

func populate(room: Node) -> void:
	var attach_to := room.get_node_or_null("Props")
	if attach_to == null:
		attach_to = room  # fallback to room root

	for d in buttons:
		if not d.has("tile"):
			push_warning("ButtonSetup: entry missing 'tile' field, skipping.")
			continue

		var tile: Vector2i = d["tile"]
		var key: String = d.get("key", "")
		var one_shot: bool = d.get("one_shot", true)

		# Compute final key the same way FloorButton would if key is empty
		var final_key := (key if key != "" else "%s|%s" % [room.scene_file_path, tile])

		# Skip if already present (room reload safety)
		if _room_has_button_with_key(room, final_key):
			continue

		var b := FLOOR_BUTTON_SCENE.instantiate()
		# Configure exports on the FloorButton
		if b.has_variable("tile"):
			b.tile = tile
		if key != "" and b.has_variable("button_key"):
			b.button_key = key
		if b.has_variable("one_shot"):
			b.one_shot = one_shot

		# Position at tile center
		var T := tile_size
		b.position = Vector2(tile.x * T + T / 2, tile.y * T + T / 2)

		attach_to.add_child(b)

func _room_has_button_with_key(room: Node, key: String) -> bool:
	for child in room.get_children():
		if child.has_method("_resolved_key") and child._resolved_key() == key:
			return true
	return false
