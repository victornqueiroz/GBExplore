# res://singletons/Inventory.gd
extends Node
class_name Inventory

signal changed

# id -> count
var _counts: Dictionary = {}

var _itemdb: Node = null

func _get_itemdb() -> Node:
	# Cache the ItemDB autoload instance (named "ItemDB" in Autoload)
	if _itemdb and is_instance_valid(_itemdb):
		return _itemdb
	if has_node("/root/ItemDb"):
		_itemdb = get_node("/root/ItemDb")
		return _itemdb
	push_error("Autoload 'ItemDb' not found at /root/ItemDb. Set its Node Name to 'ItemDb' in Project Settings → Autoload.")
	return null

func add(id: String, amount: int = 1) -> void:
	var itemdb = _get_itemdb()
	if itemdb == null:
		return
	var data: ItemData = itemdb.get_item(id)
	if data == null:
		push_warning("Item id not found: %s" % id)
		return

	if not data.stackable and has(id):
		_counts[id] = 1
	else:
		_counts[id] = int(_counts.get(id, 0)) + max(1, amount)

	changed.emit()

func has(id: String) -> bool:
	return int(_counts.get(id, 0)) > 0

func count(id: String) -> int:
	return int(_counts.get(id, 0))

func all_items() -> Array[String]:
	var out: Array[String] = []
	for k in _counts.keys():
		if int(_counts[k]) > 0:
			out.append(k)
	return out
