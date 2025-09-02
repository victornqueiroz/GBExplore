extends StaticBody2D
class_name NPC

# ---- Visual / placement ----
@export var sprite_path: String = "res://npc/girl-portrait.png"
@export var tile: Vector2i = Vector2i(4, 4)
@export var tile_size: int = 16
@export var collider_size: Vector2 = Vector2(12, 12)
@export var z_index_sprite: int = 2

# ---- Dialogue (default / fallback) ----
@export var dialog_lines: PackedStringArray = [
	"Are you new here?",
	"",
	"My dad used to go fishing on the area north of our house but now I can't find him."
]
@export var portrait_face: Texture2D

# ---- Trade / Need ----
@export var required_item_id: String = ""
@export var required_amount: int = 1
@export var trade_uid: String = ""
@export var take_on_talk: bool = true
@export var intro_once: bool = true  # say need once first, then trade on next talk

@export var lines_before: PackedStringArray = []
@export var lines_on_give: PackedStringArray = []
@export var lines_after: PackedStringArray = []

@export var reward_item_id: String = ""
@export var reward_amount: int = 1

# ---- Nodes ----
@onready var spr: Sprite2D = $Sprite2D
@onready var col: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("npc")

	# Visual
	if sprite_path != "":
		var tex: Texture2D = load(sprite_path) as Texture2D
		if tex != null:
			spr.texture = tex
	spr.z_index = z_index_sprite
	self.z_index = z_index_sprite

	# Position from tile coords (centered on tile)
	position = Vector2((tile.x + 0.5) * tile_size, (tile.y + 0.5) * tile_size)

	# Collider
	var r: RectangleShape2D = RectangleShape2D.new()
	r.size = collider_size
	col.shape = r

	# Wall-like collision so player can't pass through
	collision_layer = GameConfig.WALL_LAYER
	collision_mask  = GameConfig.WALL_MASK

# ScreenManager calls this; we also handle the quest/trade here.
func get_dialog_lines() -> PackedStringArray:
	# No trade configured → plain dialogue
	if required_item_id == "" or trade_uid == "":
		return _choose_nonempty(dialog_lines, ["Hello."])

	var rs: Node = get_node_or_null("/root/RunState")

	# Already completed this trade?
	if rs and rs.has_method("was_trade_done") and rs.call("was_trade_done", trade_uid):
		return _choose_nonempty(lines_after, _choose_nonempty(dialog_lines, ["Thanks again!"]))

	# Show the "need" once first, even if the player already has the item.
	if intro_once and rs and rs.has_method("was_need_intro") and not rs.call("was_need_intro", trade_uid):
		if rs.has_method("mark_need_intro"):
			rs.call("mark_need_intro", trade_uid)
		return _choose_nonempty(lines_before, _choose_nonempty(dialog_lines, ["Hello."]))

	# Check inventories (both, if present)
	var invs: Array[Node] = _get_inventories()
	var have: int = 0
	for inv in invs:
		have = max(have, _inv_count(inv, required_item_id))
	if have < required_amount:
		return _choose_nonempty(lines_before,
			_choose_nonempty(dialog_lines, ["Have you seen my %s?" % required_item_id]))

	# We have enough → consume, reward, mark done, refresh UI
	if take_on_talk:
		for inv2 in invs:
			_inv_remove(inv2, required_item_id, required_amount)
		if reward_item_id != "":
			var give_amt: int = max(1, reward_amount)
			for inv3 in invs:
				_inv_add(inv3, reward_item_id, give_amt)
		for inv4 in invs:
			_emit_inv_changed(inv4)

		if rs and rs.has_method("mark_trade_done"):
			rs.call("mark_trade_done", trade_uid)

		_refresh_map_hud()
		return _choose_nonempty(lines_on_give, ["(They take your %s.)" % required_item_id])

	# Not auto-taking: prompt
	return _choose_nonempty(lines_before, ["Could I have your %s?" % required_item_id])

# Optional editor/legacy path
func _on_interact() -> void:
	var face: Texture2D = portrait_face
	if face == null:
		face = load("res://npc/girl-portrait.png") as Texture2D
	var dlg: Node = get_node_or_null("/root/Main/UI/DialogueBox")
	if dlg == null:
		push_warning("[NPC] DialogueBox not found at /root/Main/UI/DialogueBox")
		return
	dlg.open(get_dialog_lines(), face, "left")

# ------------- helpers -------------
func _choose_nonempty(primary: PackedStringArray, fallback: PackedStringArray) -> PackedStringArray:
	return primary if primary.size() > 0 else fallback

func _get_inventories() -> Array[Node]:
	var arr: Array[Node] = []
	var invA: Node = get_node_or_null("/root/Inventory")
	if invA: arr.append(invA)
	var invB: Node = get_node_or_null("/root/InventoryLoad")
	if invB and invB != invA: arr.append(invB)
	return arr

func _emit_inv_changed(inv: Node) -> void:
	if inv and inv.has_signal("changed"):
		inv.emit_signal("changed")

func _inv_count(inv: Node, id: String) -> int:
	if inv == null: return 0
	if inv.has_method("count"):       return int(inv.call("count", id))
	if inv.has_method("get_count"):   return int(inv.call("get_count", id))
	if inv.has_method("quantity_of"): return int(inv.call("quantity_of", id))
	if inv.has_method("qty_of"):      return int(inv.call("qty_of", id))
	# As a last resort (dictionary-like stores)
	var dict_candidates: Array[String] = ["items","counts","store","bag","inventory","_items","_counts"]
	for k in dict_candidates:
		var dv: Variant = inv.get(k)
		if typeof(dv) == TYPE_DICTIONARY:
			var d: Dictionary = dv
			return int(d.get(id, 0))
	return 0

func _inv_remove(inv: Node, id: String, amt: int) -> void:
	if inv == null: return
	amt = max(1, amt)
	var before: int = _inv_count(inv, id)

	# Try common APIs
	if inv.has_method("remove"):
		inv.call("remove", id, amt)
	elif inv.has_method("take"):
		inv.call("take", id, amt)
	elif inv.has_method("consume"):
		inv.call("consume", id, amt)
	elif inv.has_method("remove_item"):
		inv.call("remove_item", id, amt)
	elif inv.has_method("add"):
		inv.call("add", id, -amt)  # some inventories accept negatives

	# Verify; if unchanged, patch common dictionary stores
	var after: int = _inv_count(inv, id)
	if after == before:
		_dict_decrement(inv, id, amt)

func _inv_add(inv: Node, id: String, amt: int) -> void:
	if inv == null: return
	amt = max(1, amt)
	if inv.has_method("add"):
		inv.call("add", id, amt)
	elif inv.has_method("give"):
		inv.call("give", id, amt)
	elif inv.has_method("add_item"):
		inv.call("add_item", id, amt)
	else:
		_dict_increment(inv, id, amt)

func _dict_decrement(inv: Node, id: String, amt: int) -> void:
	var keys: Array[String] = ["items","counts","store","bag","inventory","_items","_counts"]
	for k in keys:
		var dv: Variant = inv.get(k)
		if typeof(dv) == TYPE_DICTIONARY:
			var d: Dictionary = dv
			var n: int = int(d.get(id, 0)) - amt
			if n <= 0:
				d.erase(id)
			else:
				d[id] = n
			inv.set(k, d)
			return

func _dict_increment(inv: Node, id: String, amt: int) -> void:
	var keys: Array[String] = ["items","counts","store","bag","inventory","_items","_counts"]
	for k in keys:
		var dv: Variant = inv.get(k)
		if typeof(dv) == TYPE_DICTIONARY:
			var d: Dictionary = dv
			d[id] = int(d.get(id, 0)) + amt
			inv.set(k, d)
			return

func _refresh_map_hud() -> void:
	var map: Node = get_node_or_null("/root/Main/MapOverlay/MapRoot")
	if map:
		if map.has_method("refresh"): map.call("refresh")
		elif map.has_method("queue_redraw"): map.call("queue_redraw")
