extends Node
class_name ItemDB

var _by_id: Dictionary = {}

func _ready() -> void:
	var shrimp: ItemData = preload("res://items/shrimp.tres")
	var book: ItemData = preload("res://items/book.tres")
	var map: ItemData = preload("res://items/map.tres")	
	var flower: ItemData = preload("res://items/flower.tres")	
	var necklace: ItemData = preload("res://items/necklace.tres")
	var shell: ItemData = preload("res://items/shell.tres")
	
	_register(book)
	_register(shrimp)
	_register(map)
	_register(flower)
	_register(necklace)
	_register(shell)
	

func _register(it: ItemData) -> void:
	if it: _by_id[StringName(it.id)] = it

func get_item(id: String) -> ItemData:
	return _by_id.get(StringName(id), null)
