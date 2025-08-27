extends Node
class_name ItemDB

var _by_id: Dictionary = {}

func _ready() -> void:
	var shrimp: ItemData = preload("res://items/shrimp.tres")
	_register(shrimp)

func _register(it: ItemData) -> void:
	if it: _by_id[StringName(it.id)] = it

func get_item(id: String) -> ItemData:
	return _by_id.get(StringName(id), null)
