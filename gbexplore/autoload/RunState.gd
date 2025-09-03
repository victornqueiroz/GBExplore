extends Node
# Autoloaded as "RunState" (no class_name here)

const START_STEPS := 30

# Canonical world size (keep this in sync with ScreenManager or reference it from there)
const GRID_W := 8
const GRID_H := 8

const START_ROOM_PATH := "res://rooms/room_start.tscn"
var start_room_path: String = START_ROOM_PATH   # <— use this everywhere instead of the const

# With an even grid, there are 4 “central” tiles; we’ll pick (4,4)
const START_POS := Vector2i(GRID_W / 2, GRID_H / 2)   # -> (4, 4)

var rng := RandomNumberGenerator.new()
var seed: int = 0
var steps_left: int = START_STEPS
var visited: Dictionary = {}      # key: Vector2i -> String path used for that coord
var pos: Vector2i = START_POS     # default; new_run() will also reset to START_POS

# Track unique rooms used this run (by path)
var used_unique := {}

# Track which chests were opened this run
var _opened_chests := {}  # uid -> true

# Track completed NPC trades (one-time interactions)
var _npc_trades := {}  # uid -> true
func was_trade_done(uid: String) -> bool: return bool(_npc_trades.get(uid, false))
func mark_trade_done(uid: String) -> void: _npc_trades[uid] = true

# Has the NPC already explained their need this run?
var _npc_need_intro := {}  # uid -> true
func was_need_intro(uid: String) -> bool: return bool(_npc_need_intro.get(uid, false))
func mark_need_intro(uid: String) -> void: _npc_need_intro[uid] = true


func was_chest_opened(uid: String) -> bool:
	return bool(_opened_chests.get(uid, false))

func mark_chest_opened(uid: String) -> void:
	_opened_chests[uid] = true
	
# -------- Tutorial / Act 1 ----------
enum GameMode { FREE, TUTORIAL }
var game_mode: int = GameMode.FREE
var tutorial_step: int = -1                      # -1 means inactive
var tutorial_overrides := {}                     # coord -> { "npcs":[], "pickups":[], ... }
var tutorial_hint_point: Vector2i = Vector2i(-1, -1)   # marker on the map (e.g. top-left)

# Start/End
func start_tutorial() -> void:
	start_room_path = "res://rooms/tutorial_start.tscn"
	game_mode = GameMode.TUTORIAL
	new_run()
	tutorial_step = 0
	tutorial_overrides.clear()
	tutorial_hint_point = Vector2i(-1, -1)
	print("[TUT] started")

func end_tutorial() -> void:
	game_mode = GameMode.FREE
	tutorial_step = -1
	tutorial_hint_point = Vector2i(-1, -1)
	start_room_path = START_ROOM_PATH

# Tutorial beats (each entry fixes the draft options and can inject content)
# We keep everything moving EAST to match your description.
var TUTORIAL_STEPS := [
	{ # 0) From start → only a Path to the EAST
		"entry": "W",
		"paths": ["res://rooms/tutorial_path.tscn"]
	},
	
	{ # 1) East again → Village with the Girl (intro: wants a book from the forest)
		"entry": "W",
		"paths": ["res://rooms/tutorial_girl_path.tscn"],
		"overrides": {
			"npcs": [ {
				"sprite": "res://npc/girl.png",
				"tile": Vector2i(4,4),
				"lines": [
					"I'm looking for a book I dropped in the forest, but I can't even find the forest anymore…",
					"Can you help me?"
				],
				# she wants a book; when you give it later she'll deliver extra lines
				"need": {
					"item_id":"book", "amount":1, "uid":"tut_girl_book",
					"lines_on_give":[
						"You found my book—thank you!",
						"…Wait, this isn’t mine. This one's cover has a… tower.",
						"And it does look exactly like the tower on this map you're holding!",
						"Where did you get it?!",
						"My dad is obsessed maps, he would LOVE to see your map.",
						"Please take it to him. He’s out fishing somewhere nearby."
					],
					"lines_after":[ "I'll keep looking for my book. Try asking my dad about that map!" ]
				},
				# tell the tutorial we’ve shown her intro once
				"talk_uid":"tut_girl_intro"
			} ]
		}
	},
	{ # NEXT STEP after the girl room
	# Apply ONLY when we are currently in tutorial_girl_path
	"from_path": "res://rooms/tutorial_girl_path.tscn",

	# Offer choices when the *target* room’s entry side is N or S
	# (Moving North from the girl room => entry_side == "S". Moving South => entry_side == "N")
	"entry_any": ["N", "S"],

	# Direction-specific lists:
	"paths_by_entry": {
		# If player goes SOUTH from girl room (target room entry is N):
		"N": [
			"res://rooms/room_path.tscn",
			"res://rooms/tutorial_forest.tscn"
		],

		# If player goes NORTH from girl room (target room entry is S):
		"S": [
			"res://rooms/tutorial_forest.tscn",
			"res://rooms/room_path.tscn"
		]
	}
}
,
	{ # 2) East again → show *three* choices: two Paths + one Forest
		"entry": ["N", "S"],
		"paths": [
			#"res://rooms/room_path2.tscn",
			#"res://rooms/room_path3.tscn",
			"res://rooms/tutorial_forest.tscn",
			"res://rooms/tutorial_forest.tscn",
			"res://rooms/tutorial_forest.tscn"
		],
		# If Forest is chosen, we’ll inject a BOOK pickup in that placed forest room.
		# (We don’t know coord at draft time; we’ll attach on pick.)
	}
	
]

	
# ---------------- Room Definitions ----------------
# Keys:
#   path:String, name:String, tags:Array, type:String (optional but useful for filters)
#   exits: {"N":bool,"E":bool,"S":bool,"W":bool}
#   entry_open: same shape as exits (actual walkable opening on center of that edge)
#   allowed_entry:Array (optional)  -> design rule
#   blocked_entry:Array (optional)  -> design rule
#   weight:int (>=1), unique:bool
#
# IMPORTANT: Set entry_open to match your TileMap collision (center edge tile).
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
		# NEW: pickups
		"pickups": [
			{"x": 2, "y": 4, "item_id": "book", "amount": 1, "uid": "book", "auto": false}],
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
		"draftable": false
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
		"path": "res://rooms/tutorial_girl_path.tscn",
		"name": "Path",
		"type": "land",
		"tags": ["path", "tutorial"],
		"exits":      {"N": true, "E": false, "S": true, "W": true},
		"entry_open": {"N": true, "E": false, "S": true, "W": true},
		"weight": 4,
		"unique": true,
		"draftable": true
	},
	{
		"path": "res://rooms/tutorial_forest.tscn",
		"name": "Forest?",
		"type": "land",
		"tags": ["forest", "tutorial"],
		"exits":      {"N": true, "E": false, "S": true, "W": false},
		"entry_open": {"N": true, "E": false, "S": true, "W": false},
		"weight": 4,
		"pickups": [
			{"x": 4, "y": 4, "item_id": "book", "amount": 1, "uid": "book", "auto": false}],
		"unique": true,
		"draftable": true
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
			# Optional default lines if nothing special
			"lines": ["Hi!"],
			# NEW: the trade/need
			"need": {
				"item_id": "book",
				"amount": 1,
				"uid": "girl_book_01",  # unique per run/quest
				"lines_before": ["Have you seen my book?"],
				"lines_on_give": ["Oh! You found it—thank you! Take this shrimp as a reward. My dad will tell you more about it."],
				"lines_after": ["I'm busy reading now!"],
				# optional reward:
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
				"uid": "fisherman_shrimp_01",   # << unique for this quest
				"lines_before": ["Do you have a shrimp?"],
				"lines_on_give": ["Perfect bait—thanks!"],
				"lines_after": ["Back to the lake!"],
				"reward": {"item_id": "book", "amount": 1}
			}
		}
	]
}
,
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
				{
				  "tile": Vector2i(4, 1),      # tile coordinates, 0–8 in a 9×9 room
				  "item_id": "shrimp",         # must match your ItemDb id
				  "amount": 1,
				  "uid": "hut_chest_1"         # unique ID so it stays open once opened
				}
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
	start_tutorial()
	#new_run()

func new_run() -> void:
	seed = int(Time.get_unix_time_from_system())
	rng.seed = seed
	steps_left = START_STEPS
	visited.clear()
	pos = START_POS            # <-- start in the middle of 8x8
	used_unique.clear()
	_npc_trades.clear()
	_npc_need_intro.clear()
	tutorial_overrides.clear()

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

	if eligible.size() == 0:
		for def2 in ROOM_DEFS:
			var p2: String = String(def2["path"])
			if def2.has("unique") and def2["unique"] and used_unique.has(p2):
				continue
			if def_compatible_with_neighbors(coord, entry_side, def2):
				eligible.append(def2)

	return _weighted_pick_without_replacement(eligible, count)

# Mark a room def as consumed if it's unique (call when the user picks one)
func mark_used_if_unique(def: Dictionary) -> void:
	if def.has("unique") and def["unique"]:
		var p: String = String(def["path"])
		used_unique[p] = true

# ---------------- Helpers ----------------

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

# In res://autoload/RunState.gd (near your chest vars)
var _picked_items := {}
func was_item_picked(uid: String) -> bool: return bool(_picked_items.get(uid, false))
func mark_item_picked(uid: String) -> void: _picked_items[uid] = true


func pick_room_candidates_for_tutorial(entry_side: String, coord: Vector2i, count: int) -> Array:
	if game_mode != GameMode.TUTORIAL or tutorial_step < 0 or tutorial_step >= TUTORIAL_STEPS.size():
		return []

	var step = TUTORIAL_STEPS[tutorial_step]

	# Optional: restrict to a specific current room
	if step.has("from_path"):
		var cur_path := String(visited.get(pos, ""))
		if cur_path != String(step["from_path"]):
			return []

	# Allow either a single entry side or a set
	if step.has("entry"):
		if String(step["entry"]) != entry_side:
			return []
	if step.has("entry_any"):
		var allowed: Array = step["entry_any"]
		if not allowed.has(entry_side):
			return []

	# Decide which path list to use
	var list_paths: Array = []
	if step.has("paths_by_entry") and step["paths_by_entry"] is Dictionary:
		var m: Dictionary = step["paths_by_entry"]
		if not m.has(entry_side):
			return []
		list_paths = m[entry_side]
	else:
		list_paths = step.get("paths", [])

	# Build defs
	var out: Array = []
	for p in list_paths:
		var d := get_def_by_path(String(p))
		if d.size() > 0:
			out.append(d)

	# Keep weighting/limit behavior consistent with your non-tutorial picker
	# (but usually the tutorial lists are short)
	return out


# Called from ScreenManager after the player chooses a draft option
func notify_room_picked(coord: Vector2i, path: String) -> void:
	if game_mode != GameMode.TUTORIAL: return
	if tutorial_step < 0 or tutorial_step >= TUTORIAL_STEPS.size(): return

	var step = TUTORIAL_STEPS[tutorial_step]
	# Attach per-tile overrides for this coord
	if step.has("overrides"):
		tutorial_overrides[coord] = step["overrides"]

	# Special: if this step offered the forest, and the player picked a forest,
	# inject the BOOK pickup into THAT forest's overrides.
	if tutorial_step == 3 and get_def_by_path(path).get("type","") == "forest":
		tutorial_overrides[coord] = {
			"pickups": [ { "tile": Vector2i(4,4), "item_id":"book", "amount":1, "uid":"tut_book_01" } ]
		}

	# Advance to next scripted beat
	tutorial_step += 1
	if tutorial_step >= TUTORIAL_STEPS.size():
		# From now on you’re in free play, but the story continues (girl trade, hut talk, etc.)
		end_tutorial()

# When spawners ask for the room def, merge in per-tile overrides (NPCs/pickups) if any.
# --- 3) Always merge overrides for a placed coord, even in FREE mode ---
func get_def_for_spawn(path: String, coord: Vector2i) -> Dictionary:
	var base := get_def_by_path(path).duplicate(true)
	if tutorial_overrides.has(coord):
		var ov: Dictionary = tutorial_overrides[coord]
		for k in ["npcs","pickups","chests"]:
			if ov.has(k):
				base[k] = ov[k]
	return base


func on_item_picked(uid: String) -> void:
	if game_mode != GameMode.TUTORIAL: return
	if uid == "tut_map_01" and tutorial_step < 2:
		# Player got the map; next beat is the village intro
		tutorial_step = 2

func on_npc_first_talk(uid: String) -> void:
	if game_mode != GameMode.TUTORIAL: return
	if uid == "tut_girl_intro" and tutorial_step < 3:
		# We showed the girl's “please help” lines once
		tutorial_step = 3

func on_trade_done(uid: String) -> void:
	if game_mode != GameMode.TUTORIAL: return
	if uid == "tut_girl_book":
		# After giving the book, we’ll look for the fisherman
		# When the fisherman talks, we’ll set a map marker (see NPC hook below)
		pass

func set_tutorial_hint_top_left() -> void:
	tutorial_hint_point = Vector2i(0, 0)    # mark top-left
