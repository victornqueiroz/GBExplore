extends Node
@export var buttons: Array[Dictionary] = []
@export var tile_size: int = 16

const FLOOR_BUTTON_SCENE := preload("res://actors/FloorButton.tscn")

func _ready() -> void:
	add_to_group("button_setup")

func populate(room: Node) -> void:
	var attach_to := room.get_node_or_null("Props")
	if attach_to == null:
		attach_to = room

	for d in buttons:
		if not d.has("tile"):
			push_warning("ButtonSetup: entry missing 'tile' field, skipping.")
			continue

		var tile: Vector2i = d["tile"]
		var key: String = d.get("key", "")
		var one_shot: bool = d.get("one_shot", true)

		var final_key := (key if key != "" else "%s|%s" % [room.scene_file_path, tile])

		if _room_has_button_with_key(room, final_key):
			continue

		var b := FLOOR_BUTTON_SCENE.instantiate()

		# Configure exports
		if b.has_variable("tile"):
			b.tile = tile
		if key != "" and b.has_variable("button_key"):
			b.button_key = key
		if b.has_variable("one_shot"):
			b.one_shot = one_shot

		# === NEW: style/texture selection for triangle ===
		if key == "triangle":
			if b.has_method("apply_style"):
				b.apply_style("triangle")
			elif b.has_variable("style"):
				b.style = "triangle"
			else:
				# Fallback: set textures directly if available
				if b.has_variable("idle_texture"):
					b.idle_texture = preload("res://actors/FloorButtonTriangle.png")
				if b.has_variable("pressed_texture"):
					b.pressed_texture = preload("res://actors/FloorButtonPressedTriangle.png")

		# Position at tile center
		var T := tile_size
		b.position = Vector2(tile.x * T + T / 2, tile.y * T + T / 2)

		attach_to.add_child(b)

func _room_has_button_with_key(room: Node, key: String) -> bool:
	for child in room.get_children():
		if child.has_method("_resolved_key") and child._resolved_key() == key:
			return true
	return false
