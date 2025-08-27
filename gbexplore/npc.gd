extends StaticBody2D

# ---- Visual / placement ----
@export var sprite_path: String = "res://npc/girl-portrait.png"
@export var tile: Vector2i = Vector2i(4, 4)         # tile position inside current room
@export var tile_size: int = 16
@export var collider_size: Vector2 = Vector2(12, 12)
@export var z_index_sprite: int = 2

# ---- Dialogue ----
@export var dialog_lines: PackedStringArray = [
	"Are you new here?",
	"",
	"My dad used to go fishing on the area north of our house but now I can't find him."
]

# Portrait to show in the dialogue box (set this in the Inspector)
# e.g. res://npc/girl-portrait.png  (Import: Filter OFF, Mipmaps OFF)
@export var portrait_face: Texture2D

# ---- Nodes ----
@onready var spr: Sprite2D = $Sprite2D
@onready var col: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("npc")
	# Visual
	if sprite_path != "":
		var tex: Resource = load(sprite_path)
		if tex is Texture2D:
			spr.texture = tex
	spr.z_index = z_index_sprite
	self.z_index = z_index_sprite

	# Position from tile coords (centered on tile)
	position = Vector2((tile.x + 0.5) * tile_size, (tile.y + 0.5) * tile_size)

	# Collider
	var r := RectangleShape2D.new()
	r.size = collider_size
	col.shape = r

	# Wall-like collision so player can't pass through
	collision_layer = GameConfig.WALL_LAYER
	collision_mask  = GameConfig.WALL_MASK

	print("[NPC] spawned ", name, " at ", position, " tile=", tile)


func _on_interact() -> void:
	# Use portrait from Inspector; if empty, try a sensible fallback path.
	var face: Texture2D = portrait_face
	if face == null:
		# NOTE: adjust if your file lives elsewhere
		face = load("res://npc/girl-portrait.png") as Texture2D

	print("[NPC] interact: face=", face)

	var dlg: Node = get_node_or_null("/root/Main/UI/DialogueBox")
	if dlg == null:
		push_warning("[NPC] DialogueBox not found at /root/Main/UI/DialogueBox")
		return

	# Open dialogue (portrait is optional)
	dlg.open(dialog_lines, face, "left")
