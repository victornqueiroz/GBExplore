extends Node
class_name VirtualPadManager

@export var default_enabled := true
@export_file("*.tscn") var pad_scene_path := "res://ui/virtual_pad.tscn"

var _pad: CanvasLayer

func _ready() -> void:
	if default_enabled:
		call_deferred("_deferred_enable")

func _deferred_enable() -> void:
	set_enabled(true)

func set_enabled(on: bool) -> void:
	if on:
		if _pad:
			return
		if not ResourceLoader.exists(pad_scene_path):
			push_error("VirtualPadManager: Scene not found: %s" % pad_scene_path)
			return
		var scene: PackedScene = load(pad_scene_path)
		if scene == null:
			push_error("VirtualPadManager: Failed to load scene at: %s" % pad_scene_path)
			return
		_pad = scene.instantiate()
		get_tree().root.call_deferred("add_child", _pad)
		print("[VirtualPad] enabled")
	else:
		if _pad and is_instance_valid(_pad):
			_pad.queue_free()
			_pad = null
			print("[VirtualPad] disabled")

func is_enabled() -> bool:
	return _pad != null
