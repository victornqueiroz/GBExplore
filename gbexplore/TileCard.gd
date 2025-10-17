extends Button
class_name TileCard

@export var thumb_size: Vector2i = Vector2i(128, 128)

var tile_key: String
var tile_path: String
var _preview: Texture2D

@onready var _thumb: TextureRect = $VBoxContainer/Thumb
@onready var _name: Label = $VBoxContainer/Name

func setup(p_tile_key: String, p_tile_path: String, p_preview: Texture2D, show_label:=true) -> void:
	tile_key = p_tile_key
	tile_path = p_tile_path
	_preview = p_preview
	_thumb.custom_minimum_size = thumb_size
	_thumb.texture = _preview
	_name.visible = show_label
	_name.text = p_tile_key

# optional hover style
func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
