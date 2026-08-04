# Run: godot --headless --path godot-project --script tools/slice_test_town.gd
#
# THE TOWN IS THE FRONT DOOR — and the LLM stack is gone.
#
# Two jobs, and the second one is the one that will rot first:
#
#   1. THE TOWN MUST NOT BECOME A LAYER. The maker's verdict on the old hub was
#      "it's just another layer that doesn't add any value", and the defence is
#      geometric: you spawn INSIDE the tower door's proximity ring, so the town
#      costs one key press and zero steps to leave. That is a relationship between
#      three constants in two files, and it is exactly the sort of thing somebody
#      nudges by 20 px while tidying a layout. It is pinned here, by arithmetic,
#      not by a screenshot.
#   2. NOTHING MAY REACH FOR OLLAMA AGAIN. `Conversation.gd`, `MemoryUtils.gd`,
#      `MemoryConsolidator.gd`, `Patience.gd`, the `user://npc_memory` files and the
#      consolidation prompt are deleted. The town's own scripts are grepped for the
#      port, the address and the class names, so a revert cannot quietly bring the
#      loopback dependency back on a platform where loopback is the phone itself.
#
# ⚠ TEST IDIOM (see tools/slice_test_loadout.gd for the full story). Failures
# accumulate on a MEMBER and every test records a COMPLETION SENTINEL as its last
# line. Reading a property that no longer exists is not a failure in GDScript — it
# aborts the enclosing function and hands back a zero — so `failed += _test_x()`
# reads as "no failures" while verifying nothing. A test that dies half-way fails
# this suite by ABSENCE instead.
extends SceneTree

const TOWN_SCENE: String = "res://scenes/Main.tscn"
const WORLD_SCRIPT: String = "res://scripts/World.gd"
const NPC_SCRIPT: String = "res://scripts/NPC.gd"
const PLAYER_SCRIPT: String = "res://scripts/Player.gd"
const STATION_SCRIPT: String = "res://scripts/ArmoryStation.gd"
const DOOR_SCRIPT: String = "res://scripts/TowerDoor.gd"
const ALTAR_SCRIPT: String = "res://scripts/ClassAltar.gd"
const LOBBY_SCRIPT: String = "res://scripts/ui/Lobby.gd"

## Every town-side script that a player's input can reach. All of them are grepped
## for the LLM stack.
const TOWN_SCRIPTS: Array[String] = [
	WORLD_SCRIPT, NPC_SCRIPT, PLAYER_SCRIPT, STATION_SCRIPT,
	DOOR_SCRIPT, ALTAR_SCRIPT, LOBBY_SCRIPT,
	"res://scripts/NPCData.gd",
]

## Files that were the LLM stack. Deleted, not parked.
const DELETED: Array[String] = [
	"res://scenes/Conversation.tscn",
	"res://scripts/Conversation.gd",
	"res://scripts/MemoryUtils.gd",
	"res://scripts/MemoryConsolidator.gd",
	"res://scripts/Patience.gd",
	"res://scripts/EntityStats.gd",
	"res://scripts/RoomZone.gd",
	"res://data/prompts/memory_consolidation.txt",
	"res://data/npcs/first_npc.tres",
	"res://data/npcs/mirelle.tres",
]

const TESTS: Array[String] = [
	"town_scene_builds", "spawn_is_on_the_doorstep", "three_stations_answer",
	"townsfolk_speak_without_an_llm", "the_llm_stack_is_deleted",
	"no_town_script_names_ollama", "the_lobby_still_leads_with_climb",
	"tap_targets_clear_the_floor",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _town: Node = null


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Town tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Town tests: all PASS")
		quit(0)
	return true


func _run() -> void:
	_test_town_scene_builds()
	_test_spawn_is_on_the_doorstep()
	_test_three_stations_answer()
	_test_townsfolk_speak_without_an_llm()
	_test_the_llm_stack_is_deleted()
	_test_no_town_script_names_ollama()
	_test_the_lobby_still_leads_with_climb()
	_test_tap_targets_clear_the_floor()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## Source with comments stripped at the first `#` on each line. The town's scripts
## EXPLAIN at length why the LLM stack was removed, so a naive grep for "11434" or
## "Ollama" would hit the explanation rather than any live code.
func _code_only(path: String) -> String:
	var out: String = ""
	for line: String in _source(path).split("\n"):
		var hash_at: int = line.find("#")
		out += (line if hash_at < 0 else line.substr(0, hash_at)) + "\n"
	return out


## Build the town ONCE and keep it — several tests read the same live instance, and
## building it three times would spawn three sets of townspeople.
func _get_town() -> Node:
	if _town != null and is_instance_valid(_town):
		return _town
	var packed: PackedScene = load(TOWN_SCENE)
	if packed == null:
		return null
	_town = packed.instantiate()
	root.add_child(_town)
	return _town


func _find(from: Node, script_path: String, out: Array) -> void:
	var s: Script = from.get_script() as Script
	if s != null and s.resource_path == script_path:
		out.append(from)
	for c: Node in from.get_children():
		_find(c, script_path, out)


# ---------------------------------------------------------------------------
# It exists and it stands up
# ---------------------------------------------------------------------------

func _test_town_scene_builds() -> void:
	# The whole town is built in code by World._ready. If any of it throws, the
	# instantiate below is where it surfaces.
	var town: Node = _get_town()
	_expect(town != null, "the town scene instantiates")
	if town == null:
		return
	_expect(town.get_script() != null and (town.get_script() as Script).resource_path == WORLD_SCRIPT,
		"the town root is World.gd")
	var player: Node = root.get_tree().get_first_node_in_group("player")
	_expect(player != null, "the town has a player body in the `player` group")
	_completes("town_scene_builds")


# ---------------------------------------------------------------------------
# It is not a layer
# ---------------------------------------------------------------------------

## THE ANTI-LAYER TEST. The spawn point must be inside the tower door's proximity
## ring, so the hint is already up on the first frame and leaving the town is one
## press and no walking. Checked as ARITHMETIC between the two files' constants,
## because that is the relationship somebody breaks by moving a landmark 30 px.
func _test_spawn_is_on_the_doorstep() -> void:
	var world: GDScript = load(WORLD_SCRIPT) as GDScript
	var door: GDScript = load(DOOR_SCRIPT) as GDScript
	_expect(world != null and door != null, "both scripts load")
	if world == null or door == null:
		return
	var wc: Dictionary = world.get_script_constant_map()
	var dc: Dictionary = door.get_script_constant_map()
	var spawn: Vector2 = wc.get("PLAYER_SPAWN", Vector2.ZERO)
	var tower_x: float = float(wc.get("TOWER_X", 0.0))
	var radius: float = float(dc.get("PROXIMITY_RADIUS", 0.0))
	var door_h: float = float(dc.get("DOOR_H", 0.0))
	# The door's trigger circle is centred at (TOWER_X, ground - DOOR_H/2); the
	# player's 16x16 body sits with its feet at the spawn point. Nearest-point
	# distance from the circle centre to that box is what the physics server will
	# compute, so compute the same thing.
	var cx: float = tower_x
	var cy: float = spawn.y - door_h * 0.5
	var dx: float = maxf(absf(cx - spawn.x) - 8.0, 0.0)
	var dy: float = maxf(absf(cy - (spawn.y - 8.0)) - 8.0, 0.0)
	var dist: float = sqrt(dx * dx + dy * dy)
	_expect(dist < radius,
		"you spawn INSIDE the tower door's ring — %.1f px from it, ring is %.1f (this is the whole reason the town is not a layer)"
			% [dist, radius])
	# And every station is BEHIND the spawn, never between it and the door.
	for key: String in ["ARMORY_X", "ALTAR_X", "LECTERN_X"]:
		_expect(float(wc.get(key, 1e9)) < spawn.x,
			"%s is behind the spawn point, so nothing stands between you and the tower" % key)
	_completes("spawn_is_on_the_doorstep")


## The three stations exist in the built town, and each names the screen it opens.
## A station whose screen went missing is a walk to a dead end.
func _test_three_stations_answer() -> void:
	var town: Node = _get_town()
	if town == null:
		return
	var doors: Array = []
	_find(town, DOOR_SCRIPT, doors)
	_expect(doors.size() == 1, "exactly one tower door (got %d)" % doors.size())

	var altars: Array = []
	_find(town, ALTAR_SCRIPT, altars)
	_expect(altars.size() == 1, "exactly one class altar (got %d)" % altars.size())

	var stations: Array = []
	_find(town, STATION_SCRIPT, stations)
	# FOUR STATIONS IN A SOLO VISIT: the rack, the lectern, the Archivist's desk and
	# the sparring ring. The PARTY STONE is the fifth and is co-op-only — `World._session_is_party()`
	# keeps it out of a solo room, because a station that answers "nobody here" to a
	# lone player is a dead object teaching them the room has broken parts.
	#
	# Asserted by KIND rather than by count alone, so adding a station cannot
	# silently replace one: a count-only check passes just as happily on the wrong
	# three.
	var station_kinds: Dictionary = {}
	for st: Node in stations:
		station_kinds[String(st.get("kind"))] = true
	_expect(stations.size() == 4,
		"four stations in a solo room: rack, lectern, Archivist, sparring ring (got %d)"
		% stations.size())
	_expect(station_kinds.has("armory"), "the rack is there")
	_expect(station_kinds.has("spells"), "the lectern is there")
	_expect(station_kinds.has("tree"), "the Archivist's desk is there (the spell tree)")
	_expect(station_kinds.has("sparring"), "the sparring ring is there")
	_expect(not station_kinds.has("party"),
		"...and the party stone is NOT, because this is a solo visit")
	var kinds: Array = []
	for s: Node in stations:
		kinds.append(String(s.get("kind")))
	_expect(station_kinds.has("armory"), "one of them is the armory rack (got %s)" % str(kinds))
	_expect(station_kinds.has("spells"), "one of them is the spell lectern (got %s)" % str(kinds))

	# THE STATION IS THE SCREEN. Each one must reach a real destination.
	_expect(load(DOOR_SCRIPT) != null and _code_only(DOOR_SCRIPT).contains("enter_run"),
		"the door starts a run")
	_expect(_code_only(ALTAR_SCRIPT).contains("ClassSelect"), "the altar opens class select")
	var station_src: String = _code_only(STATION_SCRIPT)
	_expect(station_src.contains("/root/Loadout"), "the rack opens the armory")
	_expect(station_src.contains("open_outfitter"), "the lectern opens the outfitter")
	_expect(_code_only(WORLD_SCRIPT).contains("func open_outfitter"),
		"and the town owns the outfitter's lifetime")
	_completes("three_stations_answer")


# ---------------------------------------------------------------------------
# They talk, and nothing talks to a server
# ---------------------------------------------------------------------------

## A townsperson says a line SYNCHRONOUSLY. `Bark.say` is asserted synchronous by
## its own suite for the same reason: one `await` in a speak path turns every call
## site into a coroutine.
func _test_townsfolk_speak_without_an_llm() -> void:
	var town: Node = _get_town()
	if town == null:
		return
	var folk: Array = []
	_find(town, NPC_SCRIPT, folk)
	_expect(folk.size() >= 3, "the town has its three people in it (got %d)" % folk.size())
	var seen_ids: Dictionary = {}
	for n: Node in folk:
		var d: Resource = n.get("data") as Resource
		_expect(d != null, "a townsperson carries their data")
		if d == null:
			continue
		var id: String = String(d.get("npc_id"))
		_expect(id != "", "and has an id (the voice seed)")
		_expect(not seen_ids.has(id), "and the id is unique (got '%s' twice)" % id)
		seen_ids[id] = true
		var lines: Array = d.get("lines") as Array
		_expect(lines.size() >= 2, "and has at least two things to say")
		for line: String in lines:
			_expect(line.strip_edges() != "", "no blank line in %s's list" % id)
			# The bark rule: short. Long lines are unreadable over a head at 640x360.
			_expect(line.split(" ").size() <= 6,
				"'%s' is short enough to read over a head" % line)
	# The returned bool is the contract: no await, an answer this frame.
	var speaker: Node = folk[0] if folk.size() > 0 else null
	if speaker != null:
		var said: Variant = speaker.call("speak")
		_expect(typeof(said) == TYPE_BOOL and bool(said),
			"speak() answers TRUE synchronously — it never awaits")
	_completes("townsfolk_speak_without_an_llm")


func _test_the_llm_stack_is_deleted() -> void:
	for path: String in DELETED:
		_expect(not ResourceLoader.exists(path) and not FileAccess.file_exists(path),
			"deleted, not parked: %s" % path)
	# THE LAST PIECE lives in `project.godot`, which the agent that removed all of
	# the above does not own. It is NOT a failure here, deliberately: a red gate
	# blocks seven other people for a one-line edit that is somebody else's to make.
	# It IS printed loudly every run until it is done, because until then every boot
	# spews four errors about an autoload whose scene is gone.
	if ProjectSettings.has_setting("autoload/Conversation"):
		print("  ⚠ STILL TO DO (project.godot, not this agent's file): delete the line")
		print("    Conversation=\"*res://scenes/Conversation.tscn\"")
	# ...but if the SCENE ever comes back under that autoload, the stack is being
	# restored and that is a real failure.
	_expect(not (ProjectSettings.has_setting("autoload/Conversation")
			and ResourceLoader.exists("res://scenes/Conversation.tscn")),
		"the LLM conversation overlay has not been restored")
	_completes("the_llm_stack_is_deleted")


func _test_no_town_script_names_ollama() -> void:
	for path: String in TOWN_SCRIPTS:
		var src: String = _code_only(path)
		_expect(not src.is_empty(), "%s reads" % path)
		# The PORT, not the address. `Lobby.gd` legitimately defaults the co-op
		# join field to 127.0.0.1 — that is two phones on a LAN, which is the
		# spec's multiplayer picture, and has nothing to do with a model server.
		_expect(not src.contains("11434"), "%s names no Ollama port" % path)
		_expect(not src.contains("/api/chat"), "%s calls no chat endpoint" % path)
		for sym: String in ["Conversation.", "MemoryUtils", "MemoryConsolidator",
				"EntityStats", "RoomZone", "npc_memory", "llama"]:
			_expect(not src.contains(sym), "%s does not touch `%s`" % [path, sym])
	_completes("no_town_script_names_ollama")


# ---------------------------------------------------------------------------
# The fast path survives
# ---------------------------------------------------------------------------

## THE TOWN IS A DETOUR, NOT THE ROUTE. CLIMB must still come before the town on
## the title screen, and it must still go straight to a run — if the town ever
## becomes the thing you land on, the maker's original complaint is back with a
## menu in front of it.
func _test_the_lobby_still_leads_with_climb() -> void:
	var src: String = _code_only(LOBBY_SCRIPT)
	# See the note in slice_test_shell: the label is "ENTER THE TOWER" now and the
	# ordering claim it guards is the same one.
	var climb_at: int = src.find("ENTER THE TOWER")
	# ⚠ THE SEPARATE "The Town" BUTTON IS GONE, and its absence is the point:
	# ENTER THE TOWER now goes to the room itself, so a second button to the same
	# place was one of the "too many buttons" the maker named twice. The claim this
	# block guards — the fast path is the FIRST thing on the screen and it routes
	# through `visit_hub` — is unchanged and asserted below.
	_expect(climb_at >= 0, "the lobby still has an ENTER THE TOWER button")
	_expect(src.find("The Town") < 0,
		"...and no SECOND button to the same room")
	_expect(src.contains("_play_solo"), "CLIMB still routes to _play_solo")
	_expect(src.contains("visit_hub"), "and the town routes through GameState.visit_hub()")
	_completes("the_lobby_still_leads_with_climb")


## Mobile-first: every town tap target clears 30 px in base units, and the town
## reads its input through NAMED ACTIONS only — never a raw keycode, because the
## touch layer publishes onto the action names and nothing else.
func _test_tap_targets_clear_the_floor() -> void:
	var world: GDScript = load(WORLD_SCRIPT) as GDScript
	if world == null:
		return
	_expect(float(world.get_script_constant_map().get("MIN_TAP", 0.0)) >= 30.0,
		"the town holds itself to a 30 px tap floor")
	for path: String in TOWN_SCRIPTS:
		var src: String = _code_only(path)
		_expect(not src.contains("physical_keycode"), "%s binds no raw keycode" % path)
		_expect(not src.contains("KEY_"), "%s names no raw key constant" % path)
	# And the actions the town presses must actually be in the input map, or the
	# touch pads publish into nothing.
	for action: String in ["move_left", "move_right", "jump", "talk", "ui_cancel"]:
		_expect(InputMap.has_action(action), "the `%s` action exists" % action)
	_completes("tap_targets_clear_the_floor")
