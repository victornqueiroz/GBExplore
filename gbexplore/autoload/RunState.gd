extends Node
# Autoloaded as "RunState" (no class_name here)

# ---------------- Config ----------------
const START_STEPS := 30

# Canonical world size (keep this in sync with ScreenManager or reference it from there)
const GRID_W := 8
const GRID_H := 8

const START_ROOM_PATH := "res://rooms/room_start.tscn"

# Mutable start room (so we can switch mid-run, e.g. after the tutorial)
var _start_room_path_runtime: String = START_ROOM_PATH

func set_start_room_path(p: String) -> void:
	_start_room_path_runtime = p

func get_start_room_path() -> String:
	return _start_room_path_runtime

# --- Destination / hint marker (e.g., Hidden Tower) ---
var _dest_marker_enabled: bool = false
var _dest_marker_coord: Vector2i = Vector2i(0, 0)

# With an even grid, there are 4 “central” tiles; we’ll pick (4,4)
const START_POS := Vector2i(1,0)   # -> (4, 4)

# The trade UID in tutorial_hut that should force steps to 1 after trade completes
const TUTORIAL_FISHER_TRADE_UID := "tut_fisherman_book"

# ---------------- State ----------------
var rng := RandomNumberGenerator.new()
var seed: int = 0
var steps_left: int = START_STEPS
var visited: Dictionary = {}      # key: Vector2i -> String path used for that coord
var pos: Vector2i = START_POS     # default; new_run() will also reset to START_POS

# --- Floor button persistence ---
var _buttons := {}  # Dictionary: key (String) -> bool (true = activated)

func button_is_active(key: String) -> bool:
	return _buttons.get(key, false)

func button_set_active(key: String, active: bool = true) -> void:
	_buttons[key] = active

func button_clear(key: String) -> void:
	_buttons.erase(key)

func buttons_clear_all() -> void:
	_buttons.clear()
	
# Track unique rooms used this run (by path)
var used_unique := {}

# Track which chests were opened this run
var _opened_chests := {}  # uid -> true

# Track completed NPC trades (one-time interactions)
var _npc_trades := {}  # uid -> true
func was_trade_done(uid: String) -> bool: return bool(_npc_trades.get(uid, false))

func mark_trade_done(uid: String) -> void:
	_npc_trades[uid] = true

	if uid == TUTORIAL_FISHER_TRADE_UID:
		# steps → 1
		if "set_steps" in self:
			set_steps(1)
		# switch to normal start next time
		set_start_room_path("res://rooms/room_start.tscn")
		# make all tutorial rooms non-draftable (your earlier logic)
		for d in ROOM_DEFS:
			if typeof(d) == TYPE_DICTIONARY and d.has("path"):
				var path := String(d["path"])
				if path.contains("tutorial_"):
					d["draftable"] = false
		# NEW: show a destination marker at (0,0)
		enable_destination_marker_at(Vector2i(0, 0))
			
# Has the NPC already explained their need this run?
var _npc_need_intro := {}  # uid -> true
func was_need_intro(uid: String) -> bool: return bool(_npc_need_intro.get(uid, false))
func mark_need_intro(uid: String) -> void: _npc_need_intro[uid] = true

# Items picked from room "pickups"
var _picked_items := {}
func was_item_picked(uid: String) -> bool: return bool(_picked_items.get(uid, false))
func mark_item_picked(uid: String) -> void: _picked_items[uid] = true

# ---------------- Curated Draft Rules ----------------
# Rules keyed by CURRENT room path.
# Each ruleset can optionally specify per-side arrays:
# { "N": [paths], "E": [paths], "S": [paths], "W": [paths], "_any": [paths] }
var _curated_drafts_by_room: Dictionary = {}   # String (room path) -> Dictionary

func set_draft_rules_for_room(room_path: String, rules: Dictionary) -> void:
	_curated_drafts_by_room[room_path] = rules.duplicate(true)

func clear_draft_rules_for_room(room_path: String) -> void:
	_curated_drafts_by_room.erase(room_path)

func clear_all_draft_rules() -> void:
	_curated_drafts_by_room.clear()

func get_curated_draft_paths(current_room_path: String, exit_side: String) -> Array:
	var rules = _curated_drafts_by_room.get(current_room_path, null)
	if rules == null:
		return []
	var side_list: Array = rules.get(exit_side, [])
	if side_list.size() > 0:
		return side_list.duplicate(true)
	return rules.get("_any", []).duplicate(true)

func _current_room_path() -> String:
	# Resolve the path of the room where the player currently is
	if visited.has(pos):
		return String(visited[pos])
	return START_ROOM_PATH

# ---------------- Step Signals (optional but safe) ----------------
signal steps_changed(current: int)
signal steps_depleted
var _depleted_emitted := false

func spend_step(n: int) -> void:
	steps_left = max(steps_left - n, 0)
	emit_signal("steps_changed", steps_left)
	if steps_left == 0 and not _depleted_emitted:
		_depleted_emitted = true
		emit_signal("steps_depleted")

# NEW: safe setter used by the tutorial hut completion
func set_steps(n: int) -> void:
	steps_left = max(0, n)
	emit_signal("steps_changed", steps_left)
	if steps_left == 0 and not _depleted_emitted:
		_depleted_emitted = true
		emit_signal("steps_depleted")

# ---------------- Room Definitions ----------------
var ROOM_DEFS := [
	{
		"path": "res://rooms/room_start.tscn",
		"name": "Start",
		"type": "land",
		"tags": ["start"],
		"exits":      {"N": false, "E": true, "S": false, "W": true},
		"entry_open": {"N": false, "E": true, "S": false, "W": true},
		"weight": 4,
		"unique": true,
		"draftable": false
	},
	{
		"path": "res://rooms/tutorial_start.tscn",
		"name": "Start",
		"type": "land",
		"tags": ["start", "tutorial"],
		"exits":      {"N": false, "E": true, "S": false, "W": false},
		"entry_open": {"N": false, "E": true, "S": false, "W": false},
		"weight": 4,
		"unique": true,
		"draftable": false,
		"buttons": [
		{ "tile": Vector2i(4, 3), "key": "tutorial_start_btn_A", "one_shot": true },
		{ "tile": Vector2i(6, 5) }  # auto-key if no key provided
	]
	},
	{
		"path": "res://rooms/tutorial_path.tscn",
		"name": "???",
		"type": "land",
		"tags": ["path", "tutorial"],
		"exits":      {"N": false, "E": true, "S": false, "W": true},
		"entry_open": {"N": false, "E": true, "S": false, "W": true},
		"weight": 4,
		"pickups": [
			{"x": 4, "y": 4, "item_id": "map", "amount": 1, "uid": "map", "auto": false}],
		"unique": true,
		"draftable": true
	},
	{
		"path": "res://rooms/tutorial_path1.tscn",
		"name": "Path1",
		"type": "land",
		"tags": ["path", "tutorial"],
		"exits":      {"N": true, "E": true, "S": true, "W": false},
		"entry_open": {"N": true, "E": true, "S": true, "W": false},
		"weight": 4,
		"unique": false,
		"draftable": true
	},
	{
		"path": "res://rooms/tutorial_dead_end.tscn",
		"name": "Forest?",
		"type": "land",
		"tags": ["path", "tutorial"],
		"exits":      {"N": true, "E": true, "S": true, "W": true},
		"entry_open": {"N": true, "E": true, "S": true, "W": true},
		"weight": 4,
		"unique": false,
		"draftable": true
	},
	{
		"path": "res://rooms/tutorial_girl_path.tscn",
		"name": "Path",
		"type": "land",
		"tags": ["path", "tutorial"],
		"npcs": [ {
				"sprite": "res://npc/girl.png",
				"tile": Vector2i(4,4),
				"lines": [
					"I'm looking for a book I dropped in the forest, but I can't even find the forest anymore…",
					"Can you help me?"
				],
				"need": {
					"item_id":"book", "amount":1, "uid":"tut_girl_book",
					"lines_on_give":[
						"You found my book—thank you!",
						"…Wait, this isn’t mine. This one's cover has a… tower.",
						"And it does look exactly like the tower on this map you're holding!",
						"Where did you get it?!",
						"My dad is obsessed with maps—he would LOVE to see your map.",
						"Please take it to him. He’s out fishing somewhere nearby."
					],
					"lines_after":[ "I'll keep looking for my book. Try asking my dad about that map!" ]
				},
				"talk_uid":"tut_girl_intro"
			} ],
		"exits":      {"N": true, "E": false, "S": true, "W": true},
		"entry_open": {"N": true, "E": false, "S": true, "W": true},
		"weight": 4,
		"unique": true,
		"draftable": true
	},
	{
		"path": "res://rooms/tutorial_forest.tscn",
		"name": "Forest!",
		"type": "land",
		"tags": ["forest", "tutorial"],
		"exits":      {"N": true, "E": false, "S": true, "W": false},
		"entry_open": {"N": true, "E": false, "S": true, "W": false},
		"weight": 4,
		"pickups": [
			{"x": 4, "y": 4, "item_id": "book", "amount": 1, "uid": "book", "auto": false}],
		"unique": false,
		"draftable": true
	},
	{
		"path": "res://rooms/tutorial_hut.tscn",
		"name": "Hut",
		"type": "lake",
		"tags": ["land","water"],
		"exits":      {"N": false, "E": true, "S": false, "W": true},
		"entry_open": {"N": false, "E": true, "S": false, "W": true},
		"weight": 2,
		"unique": true,
		"npcs": [
			{
				"sprite": "res://npc/fisherman.png",
				"tile": Vector2i(4, 4),
				"lines": [
					"Are you new here?"
				],
				"talk_uid": "tut_fisher_intro",
				"need": {
					"item_id":"map", "amount":1, "uid":"tut_fisherman_book",
					"lines_on_give":[
						"Where did you find that map?!?!",
						"I've never seen anything like it.",
						"LOOK!!!",
						"There's a marked spot here! Could that be the location of the Hidden Tower?!",
						"You should go check it out before the ground starts shifting again!"
					],
					"lines_after":[ "You should go find the Hidden Tower before the ground starts shifting again!" ]
				},
			}
		]
	},
	
	{
	"path": "res://rooms/room_altair.tscn",
	"name": "Altair",
	"type": "puzzle",
	"tags": ["puzzle"],
	"exits":      {"N": true, "E": false, "S": true, "W": false},
	"entry_open": {"N": true, "E": false, "S": true, "W": false},
	"weight": 4,
	"unique": true,
	"buttons": [
		{ "tile": Vector2i(2, 5), "puzzle_index": 1, "one_shot": false, "auto_deactivate_on_exit": true },
		{ "tile": Vector2i(3, 5), "puzzle_index": 2, "one_shot": false, "auto_deactivate_on_exit": true },
		{ "tile": Vector2i(4, 5), "puzzle_index": 3, "one_shot": false, "auto_deactivate_on_exit": true },
		{ "tile": Vector2i(5, 5), "puzzle_index": 4, "one_shot": false, "auto_deactivate_on_exit": true },
		{ "tile": Vector2i(6, 5), "puzzle_index": 5, "one_shot": false, "auto_deactivate_on_exit": true }
	]
},
	{
		"path": "res://rooms/room_start2.tscn",
		"name": "Start",
		"type": "land",
		"tags": ["start"],
		"exits":      {"N": false, "E": true, "S": false, "W": true},
		"entry_open": {"N": false, "E": true, "S": false, "W": true},
		"weight": 4,
		"unique": true,
		"draftable": false
	},
	{
		"path": "res://rooms/room_hidden_tower.tscn",
		"name": "???",
		"type": "tower",
		"tags": ["tower"],
		"exits":      {"N": false, "E": false, "S": true, "W": false},
		"entry_open": {"N": false, "E": false, "S": true, "W": false},
		"weight": 4,
		"unique": true,
		"draftable": true
	},
	{
		"path": "res://rooms/room_windmill.tscn",
		"name": "Windmill",
		"type": "land",
		"tags": ["land"],
		"exits":      {"N": false, "E": true, "S": false, "W": true},
		"entry_open": {"N": false, "E": true, "S": false, "W": true},
		"weight": 4,
		"unique": true
	},
	{
		"path": "res://rooms/room_forest.tscn",
		"name": "Forest",
		"type": "forest",
		"tags": ["land","forest"],
		"exits":      {"N": true, "E": false, "S": true, "W": false},
		"entry_open": {"N": true, "E": false, "S": true, "W": false},
		"weight": 4,
		"unique": false
	},
	{
		"path": "res://rooms/room_forest2.tscn",
		"name": "Forest 2",
		"type": "forest",
		"tags": ["land","forest"],
		"exits":      {"N": true, "E": true, "S": true, "W": true},
		"entry_open": {"N": true, "E": true, "S": true, "W": true},
		"weight": 4,
		"pickups": [
			{"x": 4, "y": 4, "item_id": "shrimp", "amount": 1, "uid": "shrimp"}
		],
		"unique": true
	},
	{
		"path": "res://rooms/room_meadow.tscn",
		"name": "Meadow",
		"type": "meadow",
		"tags": ["land","meadow"],
		"exits":      {"N": false, "E": true, "S": true, "W": true},
		"entry_open": {"N": false, "E": true, "S": true, "W": true},
		"weight": 3,
		"unique": true
	},
	{
		"path": "res://rooms/room_path.tscn",
		"name": "Path",
		"type": "path",
		"tags": ["land","path"],
		"exits":      {"N": true, "E": true, "S": true, "W": false},
		"entry_open": {"N": true, "E": true, "S": true, "W": false},
		"weight": 3,
		"unique": true
	},
	{
		"path": "res://rooms/room_path2.tscn",
		"name": "Path SE",
		"type": "path",
		"tags": ["land","path"],
		"exits":      {"N": false, "E": true, "S": true, "W": false},
		"entry_open": {"N": false, "E": true, "S": true, "W": false},
		"weight": 3,
		"unique": false
	},
	{
		"path": "res://rooms/room_path3.tscn",
		"name": "Path SW",
		"type": "path",
		"tags": ["land","path"],
		"exits":      {"N": false, "E": false, "S": true, "W": true},
		"entry_open": {"N": false, "E": false, "S": true, "W": true},
		"weight": 3,
		"unique": false
	},
	{
		"path": "res://rooms/room_path4.tscn",
		"name": "Path NW",
		"type": "path",
		"tags": ["land","path"],
		"exits":      {"N": true, "E": false, "S": false, "W": true},
		"entry_open": {"N": true, "E": false, "S": false, "W": true},
		"weight": 3,
		"unique": false
	},
	{
		"path": "res://rooms/room_path5.tscn",
		"name": "Path NE",
		"type": "path",
		"tags": ["land","path"],
		"exits":      {"N": true, "E": true, "S": false, "W": false},
		"entry_open": {"N": true, "E": true, "S": false, "W": false},
		"weight": 3,
		"unique": false
	},
	{
		"path": "res://rooms/room_village.tscn",
		"name": "Village",
		"type": "town",
		"tags": ["land","town"],
		"exits":      {"N": false, "E": true, "S": true, "W": false},
		"entry_open": {"N": false, "E": true, "S": true, "W": false},
		"weight": 2,
		"unique": true,
		"npcs": [
			{
				"sprite": "res://npc/girl.png",
				"tile": Vector2i(4, 3),
				"lines": ["Hi!"],
				"need": {
					"item_id": "book",
					"amount": 1,
					"uid": "girl_book_01",
					"lines_before": ["Have you seen my book?"],
					"lines_on_give": ["Oh! You found it—thank you! Take this shrimp as a reward. My dad will tell you more about it."],
					"lines_after": ["I'm busy reading now!"],
					"reward": {"item_id": "shrimp", "amount": 1}
				}
			}
		]
	},
	{
		"path": "res://rooms/room_lake.tscn",
		"name": "Lake",
		"type": "lake",
		"tags": ["land","water"],
		"exits":      {"N": false, "E": true, "S": false, "W": true},
		"entry_open": {"N": false, "E": true, "S": false, "W": true},
		"weight": 2,
		"unique": true
	},
	{
		"path": "res://rooms/room_hut.tscn",
		"name": "Hut",
		"type": "lake",
		"tags": ["land","water"],
		"exits":      {"N": false, "E": true, "S": false, "W": true},
		"entry_open": {"N": false, "E": true, "S": false, "W": true},
		"weight": 2,
		"unique": true,
		"npcs": [
			{
				"sprite": "res://npc/fisherman.png",
				"tile": Vector2i(4, 4),
				"lines": ["Hello."],
				"need": {
					"item_id": "shrimp",
					"amount": 1,
					"uid": "fisherman_shrimp_01",
					"lines_before": ["Do you have a shrimp?"],
					"lines_on_give": ["Perfect bait—thanks!"],
					"lines_after": ["Back to the lake!"],
					"reward": {"item_id": "book", "amount": 1}
				}
			}
		]
	},
	{
		"path": "res://rooms/room_witch3.tscn",
		"name": "Witch",
		"type": "house",
		"tags": ["land","npc"],
		"exits":      {"N": false, "E": false, "S": true, "W": false},
		"entry_open": {"N": false, "E": false, "S": true, "W": false},
		"weight": 2,
		"unique": true
	},
	{
		"path": "res://rooms/room_farmer.tscn",
		"name": "Farm",
		"type": "land",
		"tags": ["land","npc"],
		"exits":      {"N": true, "E": false, "S": false, "W": true},
		"entry_open": {"N": true, "E": false, "S": false, "W": true},
		"weight": 2,
		"unique": true
	},
	{
		"path": "res://rooms/room_farm2.tscn",
		"name": "Plains",
		"type": "land",
		"tags": ["land"],
		"exits":      {"N": true, "E": false, "S": false, "W": true},
		"entry_open": {"N": true, "E": false, "S": false, "W": true},
		"weight": 2,
		"unique": true
	},
	{
		"path": "res://rooms/room_cave.tscn",
		"name": "Cave",
		"type": "cave",
		"tags": ["land","chest"],
		"exits":      {"N": false, "E": true, "S": false, "W": false},
		"entry_open": {"N": false, "E": true, "S": false, "W": false},
		"weight": 2,
		"unique": true
	},
	{
		"path": "res://rooms/room_rocky.tscn",
		"name": "Rocky",
		"type": "mountain",
		"tags": ["land","mountain"],
		"exits":      {"N": true, "E": true, "S": true, "W": true},
		"entry_open": {"N": true, "E": true, "S": true, "W": true},
		"weight": 2,
		"chests": [
			{ "tile": Vector2i(4, 1), "item_id": "shrimp", "amount": 1, "uid": "hut_chest_1" }
		],
		"unique": true
	},
	{
		"path": "res://rooms/room_beach.tscn",
		"name": "Beach",
		"type": "beach",
		"tags": ["water","beach"],
		"exits":        {"N": true, "E": true, "S": false, "W": true},
		"entry_open":   {"N": true, "E": true, "S": false, "W": true},
		"weight": 3,
		"unique": false
	},
	{
		"path": "res://rooms/room_beach_special.tscn",
		"name": "Beach ★",
		"type": "beach",
		"tags": ["water","beach"],
		"npcs": [
			{
				"sprite": "res://npc/mermaid.png",
				"tile": Vector2i(5, 5),
				"lines": [
					"嗨，陌生人！",
					"我要返屋企，但我唔識游水。",
					"如果我有一條魔鬼魚，我就可以騎住佢⋯"
				],
				
			}
		],
		"exits":        {"N": true, "E": true, "S": false, "W": true},
		"entry_open":   {"N": true, "E": true, "S": false, "W": true},
		"weight": 3,
		"unique": true
	},
	{
		"path": "res://rooms/room_house.tscn",
		"name": "House",
		"type": "mountain",
		"tags": ["mountain","house"],
		"exits":        {"N": false, "E": false, "S": true, "W": false},
		"entry_open":   {"N": false, "E": false, "S": true, "W": false},
		"allowed_entry": ["S"],
		"weight": 3,
		"unique": true
	},
	{
		"path": "res://rooms/room_mountain.tscn",
		"name": "Mountain",
		"type": "mountain",
		"tags": ["mountain"],
		"exits":        {"N": false, "E": false, "S": true, "W": false},
		"entry_open":   {"N": false, "E": false, "S": true, "W": false},
		"allowed_entry": ["S"],
		"weight": 3,
		"unique": true
	}
]
# Back-compat: if other code still references room_pool (paths only), keep it.
func _get_room_pool_paths() -> Array:
	var a: Array = []
	for d in ROOM_DEFS:
		a.append(String(d["path"]))
	return a

func _ready() -> void:
	# Example: Per-room (path) curated rules that always apply when you're IN this room.
	# Keys are TARGET ENTRY SIDES. Moving NORTH from the girl room means target entry "S".
	# Moving SOUTH from the girl room means target entry "N".
	set_draft_rules_for_room(
		"res://rooms/tutorial_start.tscn",
		{
			"W": [ "res://rooms/tutorial_path.tscn"]
		},
	)
	
	set_draft_rules_for_room(
		"res://rooms/tutorial_path.tscn",
		{
			"W": [ "res://rooms/tutorial_girl_path.tscn"]
		},
	)
	
	set_draft_rules_for_room(
		"res://rooms/tutorial_girl_path.tscn",
		{
			"S": [ "res://rooms/tutorial_forest.tscn"], # going NORTH
			"N": [ "res://rooms/tutorial_path1.tscn", "res://rooms/tutorial_forest.tscn" ]  # going SOUTH
		},
	)
	set_draft_rules_for_room(
		"res://rooms/tutorial_forest.tscn",
		{
			"S": [ "res://rooms/tutorial_dead_end.tscn"], # going NORTH
			"N": [ "res://rooms/tutorial_path1.tscn"]  # going SOUTH
		},
	)
	
	set_draft_rules_for_room(
		"res://rooms/tutorial_path1.tscn",
		{
			"S": [ "res://rooms/tutorial_dead_end.tscn"], # going NORTH
			"N": [ "res://rooms/tutorial_dead_end.tscn"],
			"W": [ "res://rooms/tutorial_hut.tscn"]  # going EAST
		},
	)
	# If you also want a one-off per-origin rule, call:
	# set_draft_rules_for_current_origin({ "N":[...], "S":[...] })
	new_run()

func new_run() -> void:
	seed = int(Time.get_unix_time_from_system())
	rng.seed = seed
	steps_left = START_STEPS
	visited.clear()
	pos = START_POS            # <-- start in the middle of 8x8
	used_unique.clear()
	_npc_trades.clear()
	_npc_need_intro.clear()
	# If you also track pickups/opened chests persistently per run, reset here as needed:
	# _opened_chests.clear()
	# _picked_items.clear()
	_depleted_emitted = false
	#clear_destination_marker()

# ---------------- Public API ----------------

# Returns up to `count` defs filtered for an entry side (rules + exits + entry_open),
# respecting uniqueness; start room and non-draftables are excluded.
func pick_room_candidates(entry_side: String, count: int) -> Array:
	var pool: Array = []

	for d in ROOM_DEFS:
		if typeof(d) != TYPE_DICTIONARY:
			continue

		var path: String = String(d.get("path", ""))
		var tags: Array = []
		if d.has("tags") and d["tags"] is Array:
			tags = (d["tags"] as Array)

		var draftable: bool = true
		if d.has("draftable"):
			draftable = bool(d["draftable"])

		# 1) Exclude start room (by path, tag, or explicit flag)
		if path == START_ROOM_PATH:
			continue
		if tags.has("start"):
			continue
		if not draftable:
			continue

		# 2) If the room doesn't allow entry from the incoming side, skip it
		if d.has("entry_open") and d["entry_open"] is Dictionary:
			var eo: Dictionary = (d["entry_open"] as Dictionary)
			if not bool(eo.get(entry_side, true)):
				continue

		# 3) Skip unique rooms already used this run
		if d.get("unique", false) and _is_unique_used(path):
			continue

		pool.append(d)

	# --- Curated filter (by current room + side) ---
	var cur_path := _current_room_path()
	var curated_paths: Array = get_curated_draft_paths(cur_path, entry_side)
	if curated_paths.size() > 0:
		pool = pool.filter(func(d):
			var p := String(d.get("path", ""))
			return curated_paths.has(p)
		)

	# Shuffle deterministically per run (optional)
	var shuffler: RandomNumberGenerator = RandomNumberGenerator.new()
	shuffler.seed = int(seed)
	pool.shuffle()

	# Return up to 'count'
	var out: Array = []
	var limit: int = min(count, pool.size())
	for i in range(limit):
		out.append(pool[i])
	return out

# Neighbor-aware picker for a specific coord (recommended from ScreenManager)
func pick_room_candidates_for_coord(entry_side: String, coord: Vector2i, count: int) -> Array:
	var eligible: Array = []
	for def in ROOM_DEFS:
		if _is_def_eligible_for_entry(def, entry_side):
			var p: String = String(def["path"])
			if def.has("unique") and def["unique"] and used_unique.has(p):
				continue
			if def_compatible_with_neighbors(coord, entry_side, def):
				eligible.append(def)

	# Fallback if nothing matched strict rules
	if eligible.size() == 0:
		for def2 in ROOM_DEFS:
			var p2: String = String(def2["path"])
			if def2.has("unique") and def2["unique"] and used_unique.has(p2):
				continue
			if def_compatible_with_neighbors(coord, entry_side, def2):
				eligible.append(def2)

	# --- Curated filter (by current room + side) ---
	var cur_path := _current_room_path()
	var curated_paths: Array = get_curated_draft_paths(cur_path, entry_side)
	if curated_paths.size() > 0:
		eligible = eligible.filter(func(d):
			var p := String(d.get("path", ""))
			return curated_paths.has(p)
		)

	return _weighted_pick_without_replacement(eligible, count)

# Mark a room def as consumed if it's unique (call when the user picks one)
func mark_used_if_unique(def: Dictionary) -> void:
	if def.has("unique") and def["unique"]:
		var p: String = String(def["path"])
		used_unique[p] = true

# ---------------- Helpers ----------------

func was_chest_opened(uid: String) -> bool:
	return bool(_opened_chests.get(uid, false))

func mark_chest_opened(uid: String) -> void:
	_opened_chests[uid] = true

func _is_unique_used(path: String) -> bool:
	return used_unique.has(path)

# Strict: for **existing placed rooms**, a missing entry_open map or side => CLOSED.
func entry_open_for_path(path: String, side: String) -> bool:
	var d: Dictionary = get_def_by_path(path)
	if d.size() == 0:
		return false
	if d.has("entry_open"):
		var m: Dictionary = (d["entry_open"] as Dictionary)
		if m.has(side):
			return bool(m[side])
	return false

# Eligibility for placing a NEW room given we enter from entry_side
func _is_def_eligible_for_entry(def: Dictionary, entry_side: String) -> bool:
	# 1) exits says that side exists
	if def.has("exits"):
		var exits: Dictionary = (def["exits"] as Dictionary)
		if exits.has(entry_side) and not bool(exits[entry_side]):
			return false

	# 2) design rules
	if def.has("allowed_entry"):
		var allowed: Array = (def["allowed_entry"] as Array)
		if not (entry_side in allowed):
			return false
	if def.has("blocked_entry"):
		var blocked: Array = (def["blocked_entry"] as Array)
		if entry_side in blocked:
			return false

	# 3) entry_open says that side is actually walkable
	if def.has("entry_open"):
		var eo: Dictionary = (def["entry_open"] as Dictionary)
		if eo.has(entry_side) and not bool(eo[entry_side]):
			return false

	# If missing entry_open, be permissive for NEW placement (treat as open)
	return true

# Full compatibility against already-placed neighbors around coord
func def_compatible_with_neighbors(coord: Vector2i, incoming_side: String, def: Dictionary) -> bool:
	# Incoming side must be open here
	if def.has("entry_open"):
		var eo_in: Dictionary = (def["entry_open"] as Dictionary)
		if eo_in.has(incoming_side) and not bool(eo_in[incoming_side]):
			return false

	# Mutual openings with each existing neighbor
	var sides: Array = ["N","E","S","W"]
	for s in sides:
		var dvec: Vector2i = _side_to_dir(s)
		var ncoord: Vector2i = coord + dvec
		if visited.has(ncoord):
			var neighbor_path: String = String(visited[ncoord])
			# neighbor must be open on its opposite side
			var neighbor_open: bool = entry_open_for_path(neighbor_path, _opp(s))
			# this room must be open on s
			var this_open: bool = true
			if def.has("entry_open"):
				var m2: Dictionary = (def["entry_open"] as Dictionary)
				if m2.has(s):
					this_open = bool(m2[s])
			if not (this_open and neighbor_open):
				return false

	return true

# Weighted pick without replacement
func _weighted_pick_without_replacement(items: Array, count: int) -> Array:
	var result: Array = []
	if items.size() == 0:
		return result

	var pool: Array = items.duplicate()
	var weights: Array = []
	for d in pool:
		var w: int = 1
		if d.has("weight"):
			w = int(d["weight"])
			if w < 1:
				w = 1
		weights.append(w)

	var picks: int = count
	if picks > pool.size():
		picks = pool.size()

	for _i in range(picks):
		var total: int = 0
		for wv in weights:
			total += int(wv)
		if total <= 0:
			break

		var r: int = rng.randi_range(0, total - 1)
		var acc: int = 0
		var idx: int = 0
		for j in range(weights.size()):
			acc += int(weights[j])
			if r < acc:
				idx = j
				break

		result.append(pool[idx])
		pool.remove_at(idx)
		weights.remove_at(idx)

	return result

# ---- Side / mapping utils ----
func _opp(side: String) -> String:
	if side == "N": return "S"
	if side == "S": return "N"
	if side == "E": return "W"
	if side == "W": return "E"
	return side

func _dir_to_side(dir: Vector2i) -> String:
	# Entry side in the NEW room (same mapping as ScreenManager)
	if dir == Vector2i(-1, 0): return "E"
	if dir == Vector2i(1, 0):  return "W"
	if dir == Vector2i(0, -1): return "S"
	if dir == Vector2i(0, 1):  return "N"
	return "?"

func _side_to_dir(side: String) -> Vector2i:
	if side == "N": return Vector2i(0, 1)   # neighbor is above new room
	if side == "S": return Vector2i(0, -1)
	if side == "E": return Vector2i(-1, 0)
	if side == "W": return Vector2i(1, 0)
	return Vector2i.ZERO

# Lookup by path
func get_def_by_path(path: String) -> Dictionary:
	for d in ROOM_DEFS:
		if String(d["path"]) == path:
			return d
	return {}

# ---- Map helpers: exit accessibility for a visited coord (DISPLAY-FRIENDLY) ----
# Uses entry_open if present; otherwise falls back to exits for openness.
func _open_for_display(path: String, side: String) -> bool:
	var d: Dictionary = get_def_by_path(path)
	if d.size() == 0:
		return false
	if d.has("entry_open"):
		var eo: Dictionary = (d["entry_open"] as Dictionary)
		if eo.has(side):
			return bool(eo[side])
	# fallback to exits if entry_open missing/unspecified
	if d.has("exits"):
		var ex: Dictionary = (d["exits"] as Dictionary)
		if ex.has(side):
			return bool(ex[side])
	return false

func exit_is_accessible(coord: Vector2i, side: String) -> bool:
	# Must be a placed room
	if not visited.has(coord):
		return false

	var path: String = String(visited[coord])

	# 1) This room must be open on that side (display-friendly)
	if not _open_for_display(path, side):
		return false

	# 2) Neighbor must be in-bounds
	var dvec: Vector2i = _side_to_dir(side)
	var ncoord: Vector2i = coord + dvec
	if ncoord.x < 0 or ncoord.x >= GRID_W or ncoord.y < 0 or ncoord.y >= GRID_H:
		return false

	# 3) If neighbor exists, it must be open on the opposite side too (display-friendly)
	if visited.has(ncoord):
		var opp := _opp(side)
		return _open_for_display(String(visited[ncoord]), opp)

	# 4) Neighbor not placed yet → treat as accessible (you can step there and place)
	return true

func exit_access_map(coord: Vector2i) -> Dictionary:
	return {
		"N": exit_is_accessible(coord, "N"),
		"E": exit_is_accessible(coord, "E"),
		"S": exit_is_accessible(coord, "S"),
		"W": exit_is_accessible(coord, "W"),
	}


func enable_destination_marker_at(coord: Vector2i) -> void:
	_dest_marker_enabled = true
	_dest_marker_coord = coord

func clear_destination_marker() -> void:
	_dest_marker_enabled = false

func has_destination_marker() -> bool:
	return _dest_marker_enabled

func get_destination_marker_coord() -> Vector2i:
	return _dest_marker_coord
