extends Node2D
class_name Chest

@export var item_id: String = "shrimp"
@export var amount: int = 1
@export var chest_uid: String = ""


#** ScreenManager will set this after instancing the chest */
@export var dialog_box: Node = null

@onready var closed_sprite: Sprite2D = $ClosedSprite
@onready var open_sprite: Sprite2D = $OpenSprite
@onready var hint: Label = get_node_or_null("Label")  # optional hint label
@onready var _ItemDb: Node = (get_node("/root/ItemDb") if has_node("/root/ItemDb") else null)

const INTERACT_RADIUS: float = 20.0  # a bit generous to be sure

var _player_in := false
var _opened := false

func _ready() -> void:
	# Make sure we have a hint label (create one if missing)
	if hint == null:
		hint = Label.new()
		hint.name = "Label"
		hint.visible = false
		hint.position = Vector2(0, -14)
		hint.add_theme_font_size_override("font_size", 10)
		#add_child(hint)

	_opened = chest_uid != "" and RunState.was_chest_opened(chest_uid)
	_update_visuals()

func _process(_dt: float) -> void:
	var p: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if p == null:
		return

	var d: float = (p.global_position - global_position).length()
	var in_range: bool = d <= INTERACT_RADIUS

	# Show/Hide hint
	if in_range and not _opened:
		_player_in = true
		hint.text = "Z/Enter: Open"
		hint.visible = true
	else:
		_player_in = false
		hint.visible = false

	# Accept either 'interact' (Z) or 'ui_accept' (Enter/Space/A)
	if _player_in and not _opened and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept")):
		_open_chest()

func _open_chest() -> void:
	if _opened:
		return
	if _ItemDb == null:
		push_error("Autoload 'ItemDb' not found at /root/ItemDb.")
		return

	var data: ItemData = _ItemDb.get_item(item_id)
	if data == null:
		push_warning("Chest item id not found: %s" % item_id)
	else:
		InventoryLoad.add(item_id, amount)

	_opened = true
	if chest_uid != "":
		RunState.mark_chest_opened(chest_uid)

	_update_visuals()
	_show_get_dialog(data)

func _show_get_dialog(data: ItemData) -> void:
	var name_txt: String = item_id
	if data != null and data.display_name != "":
		name_txt = data.display_name
	var lines := PackedStringArray(["You got a %s!" % name_txt])

	# Prefer injected dialog_box, else use the same path as NPC
	var dlg: Node = dialog_box
	if dlg == null:
		dlg = get_node_or_null("/root/Main/UI/DialogueBox")
	if dlg == null:
		push_warning("[Chest] DialogueBox not found at /root/Main/UI/DialogueBox")
		return

	# Call with the same 3-arg signature your NPC uses
	# portrait = null (no portrait), side = "center" (or "left" if you prefer)
	if dlg.has_method("open"):
		dlg.call("open", lines, null, "center")

func _update_visuals() -> void:
	closed_sprite.visible = not _opened
	open_sprite.visible = _opened
