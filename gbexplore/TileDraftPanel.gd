extends CanvasLayer
class_name TileDraftPanel

signal tile_chosen(tile_path: String)

@onready var _row := $MarginContainer/Panel/Row

var _cards: Array[TileCard] = []

func show_choices(choices: Array) -> void:
	# choices: Array of dictionaries like {key, path, preview:Texture2D}
	_row.queue_free_children()
	_cards.clear()

	for i in choices.size():
		var c: TileCard = preload("res://TileCard.tscn").instantiate()
		var data = choices[i]
		c.setup(data.key, data.path, data.preview, false) # no label (pure image)
		_row.add_child(c)
		_cards.append(c)
		c.pressed.connect(func():
			emit_signal("tile_chosen", data.path)
		)

	# keyboard flow: left/right between the three cards
	for i in _cards.size():
		var left = (i - 1 + _cards.size()) % _cards.size()
		var right = (i + 1) % _cards.size()
		_cards[i].focus_neighbor_left = _cards[left].get_path()
		_cards[i].focus_neighbor_right = _cards[right].get_path()

	visible = true
	await get_tree().process_frame
	if _cards:
		_cards[0].grab_focus()

func close() -> void:
	visible = false
