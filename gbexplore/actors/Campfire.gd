extends Node2D

@onready var area: Area2D = $Area2D
@onready var obstacle: StaticBody2D = $Obstacle


var _player_inside: bool = false
const PROMPT := "Go to sleep? (restart day)"

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	
	if obstacle:
		obstacle.collision_layer = GameConfig.WALL_LAYER
		obstacle.collision_mask  = GameConfig.WALL_MASK  # or 0 if you don’t need it

func _process(_dt: float) -> void:
	if not _player_inside:
		return
	# Use same interact keys you use for NPCs
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
		_show_prompt()

func _show_prompt() -> void:
	# Find the DialogueBox your ScreenManager already has
	var sm := get_tree().get_first_node_in_group("screen_manager")
	if sm == null:
		push_warning("Campfire: ScreenManager not found.")
		return
	var dlg := sm.get_node_or_null("UI/DialogueBox")
	if dlg == null:
		push_warning("Campfire: DialogueBox not found under ScreenManager/UI.")
		return
	if dlg.has_method("ask_yes_no"):
		# One-shot connect to capture the answer
		if not dlg.is_connected("choice_made", Callable(self, "_on_choice")):
			dlg.connect("choice_made", Callable(self, "_on_choice"), CONNECT_ONE_SHOT)
		dlg.call("ask_yes_no", PROMPT)
	else:
		push_warning("Campfire: DialogueBox.ask_yes_no(text) missing.")

func _on_choice(yes: bool) -> void:
	if not yes:
		return
	# Use your existing reset flow (shake/fade/new run)
	var sm := get_tree().get_first_node_in_group("screen_manager")
	if sm and sm.has_method("request_player_sleep"):
		sm.request_player_sleep()
	elif sm and sm.has_method("_game_over"):  # fallback if wrapper changes
		sm._game_over()
	else:
		push_warning("Campfire: no reset method on ScreenManager.")

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
