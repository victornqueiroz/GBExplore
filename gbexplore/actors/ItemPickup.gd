# res://actors/ItemPickup.gd
extends Area2D
class_name ItemPickup

@export var item_id: String = "shrimp" : set = set_item_id
@export var amount: int = 1
@export var pickup_uid: String = ""     # unique per pickup
@export var auto_pickup: bool = false   # true = collect on touch
@export var hint_text: String = "Pick up"

@onready var _hint: Label = get_node_or_null("Label")
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D

var _player_inside: bool = false
var _taken: bool = false

func _ready() -> void:
	# Make sure the area actually detects bodies
	monitoring = true
	monitorable = true
	# (Optional) while debugging, you can broaden mask:
	# collision_mask = 0xFFFFFFFF

	# Wire signals exactly once
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	# Hint
	if _hint:
		_hint.text = hint_text
		_hint.visible = false

	_apply_icon()

func set_item_id(v: String) -> void:
	item_id = v
	if is_inside_tree():
		_apply_icon()

func _apply_icon() -> void:
	if not is_instance_valid(_sprite):
		return
	var db := get_node_or_null("/root/ItemDb")
	if db and db.has_method("get_item"):
		var data = db.call("get_item", item_id)
		if data and "icon" in data and data.icon:
			_sprite.texture = data.icon
			return
	# fallback if no icon found
	_sprite.texture = null

func _on_body_entered(body: Node) -> void:
	if _taken:
		return
	_player_inside = true
	if _hint:
		_hint.visible = not auto_pickup
	if auto_pickup:
		_do_pickup()

func _on_body_exited(body: Node) -> void:
	_player_inside = false
	if _hint:
		_hint.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _taken or not _player_inside or auto_pickup:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_do_pickup()

func _do_pickup() -> void:
	if _taken:
		return
	_taken = true

	# Add to whichever inventory singleton your HUD uses
	var added := false
	var inv := get_node_or_null("/root/Inventory")
	if inv and inv.has_method("add"):
		inv.call("add", item_id, amount)
		added = true
		if inv.has_signal("changed"):
			inv.emit_signal("changed")

	if not added:
		var invL := get_node_or_null("/root/InventoryLoad")
		if invL:
			if invL.has_method("add"):
				invL.call("add", item_id, amount)
			elif invL.has_method("give"):
				invL.call("give", item_id, amount)
			elif invL.has_method("add_item"):
				invL.call("add_item", item_id, amount)
			if invL.has_signal("changed"):
				invL.emit_signal("changed")
			added = true

	# Mark as collected for this run
	var run := get_node_or_null("/root/RunState")
	if run and pickup_uid != "":
		if run.has_method("mark_item_picked"):
			run.call("mark_item_picked", pickup_uid)
		elif run.has_method("mark_chest_opened"):
			run.call("mark_chest_opened", pickup_uid)

	# Nudge HUD/map overlay to refresh
	var map := get_node_or_null("/root/Main/MapOverlay/MapRoot")
	if map:
		if map.has_method("refresh"):
			map.call("refresh")
		elif map.has_method("queue_redraw"):
			map.call("queue_redraw")

	# Tiny confirmation
	var itemdb := get_node_or_null("/root/ItemDb")
	var pretty := item_id
	if itemdb and itemdb.has_method("get_item"):
		var data = itemdb.call("get_item", item_id)
		if data and "name" in data and str(data.name) != "":
			pretty = str(data.name)
	var dlg := get_node_or_null("/root/Main/UI/DialogueBox")
	if dlg and dlg.has_method("open"):
		dlg.call("open", ["You picked up: %s x%d" % [pretty, amount]], null, "center")

	queue_free()
