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
const LOBBY_SCRIPT: String = "res://scripts/ui/Lobby.gd"
## The screen the CLASS pad opens. It is the whole of "one pad for class within which I
## can edit spells" — see `_test_the_class_pad_edits_spells_too`.
const OUTFITTER_SCRIPT: String = "res://scripts/ui/Outfitter.gd"
## The base viewport the whole game is laid out for. A screen taller than this walks its
## bottom button off a phone, which nobody notices on a desktop.
const BASE_H: float = 360.0
## Every tappable target in the town clears this in base units.
const MIN_TAP: float = 30.0

## Every town-side script that a player's input can reach. All of them are grepped
## for the LLM stack.
const TOWN_SCRIPTS: Array[String] = [
	WORLD_SCRIPT, NPC_SCRIPT, PLAYER_SCRIPT, STATION_SCRIPT,
	DOOR_SCRIPT, LOBBY_SCRIPT,
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
	"town_scene_builds", "spawn_is_on_the_doorstep", "you_can_cast_in_the_lobby",
	"the_two_pads_answer", "the_class_pad_edits_spells_too",
	"townsfolk_speak_without_an_llm", "the_llm_stack_is_deleted",
	"no_town_script_names_ollama", "the_lobby_still_leads_with_climb",
	"tap_targets_clear_the_floor",
	"walking_in_reaches_the_threshold",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _town: Node = null


## ⚠ `_run()` IS A COROUTINE NOW AND QUITS ITSELF, which is why this returns FALSE and
## no longer does the sweep. One test measures a real `Control` and a `Control` has no
## size until a layout pass has run — see `_test_the_class_pad_edits_spells_too`. If the
## sweep stayed here it would run on the frame `_run` first AWAITED, i.e. before most of
## the tests had happened, and report every one of them as having aborted.
##
## `_process` rather than `_init`: a `SceneTree`'s `_init` has no `root` yet, and every
## test below builds the town under it.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	_test_walking_in_reaches_the_threshold()
	_test_town_scene_builds()
	_test_spawn_is_on_the_doorstep()
	_test_you_can_cast_in_the_lobby()
	_test_the_two_pads_answer()
	_test_townsfolk_speak_without_an_llm()
	_test_the_llm_stack_is_deleted()
	_test_no_town_script_names_ollama()
	_test_the_lobby_still_leads_with_climb()
	_test_tap_targets_clear_the_floor()
	# LAST, because it is the only one that awaits — and everything above it is pure
	# arithmetic and source reading that must not be delayed behind a frame.
	await _test_the_class_pad_edits_spells_too()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Town tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Town tests: all PASS")
		quit(0)


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

## ⚠ TWO CONSTRAINTS THAT PULL AGAINST EACH OTHER, WHICH IS WHY BOTH ARE ASSERTED.
## The trigger has to reach DOWN far enough that a walking hero enters it — it used to
## sit 41 px up, above the 18 px top of a standing body, so only a jump ever fired it.
## And it has to stay NARROW enough that `World.PLAYER_SPAWN` (TOWER_X - 104) is outside
## it, because you arrive on the doorstep and a trigger you spawn inside teleports you
## out of the town on frame one. Widen it carelessly to fix the first and you break the
## second silently — the town would simply never appear.
##
## Geometry rather than physics: a headless run has no reliable overlap tick, and the
## rectangle is the thing that was wrong.
func _test_walking_in_reaches_the_threshold() -> void:
	var door: Node2D = (load(DOOR_SCRIPT) as GDScript).new() as Node2D
	root.add_child(door)
	var step: Area2D = door.get_node_or_null(^"Threshold") as Area2D
	_expect(step != null, "the door has a named Threshold trigger")
	if step == null:
		return
	var cs: CollisionShape2D = null
	for c: Node in step.get_children():
		if c is CollisionShape2D:
			cs = c as CollisionShape2D
			break
	_expect(cs != null, "the Threshold carries a collision shape")
	if cs == null:
		return
	var box: RectangleShape2D = cs.shape as RectangleShape2D
	_expect(box != null, "the Threshold is a rectangle filling the doorway")
	if box == null:
		return
	var trigger := Rect2(cs.position - box.size * 0.5, box.size)

	# A hero is an 18x18 box (Hero.tscn) standing with its feet on the ground, so in
	# door-local space it occupies y -18..0.
	var standing := Rect2(Vector2(-9.0, -18.0), Vector2(18.0, 18.0))
	_expect(trigger.intersects(standing),
		"a WALKING hero must reach the threshold — trigger %s vs standing body %s"
			% [trigger, standing])

	# The same body, parked where the player actually spawns.
	var at_spawn := Rect2(Vector2(-104.0 - 9.0, -18.0), Vector2(18.0, 18.0))
	_expect(not trigger.intersects(at_spawn),
		"the spawn must be OUTSIDE the threshold or the town is skipped on frame one — "
			+ "trigger %s vs body at spawn %s" % [trigger, at_spawn])

	door.queue_free()
	_completes("walking_in_reaches_the_threshold")


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
	#
	# ⚠ THE CONSTANT'S EXISTENCE IS ASSERTED SEPARATELY, AND THAT IS NOT PEDANTRY. This
	# loop used to read `wc.get(key, 1e9)` alone — so when the pad row was cut to two and
	# `ALTAR_X` was renamed `CLASS_X`, the missing key fell through to the 1e9 default and
	# this reported "ALTAR_X is behind the spawn point" as a GEOMETRY failure. It cost a
	# real look at the map to find out the class pad had not moved anywhere near the
	# spawn; it simply no longer had that name. A missing constant and a badly placed one
	# are different bugs and must not share a message.
	#
	# ⚠ TWO KEYS, NOT THREE. `LECTERN_X` (the spell lectern) and `ARCHIVIST_X` (the spell
	# tree) are deleted with their pads — see `_test_the_two_pads_answer`.
	for key: String in ["ARMORY_X", "CLASS_X"]:
		_expect(wc.has(key),
			"World.%s still exists — if it was renamed, rename it here too rather than "
			% key + "letting the default make it look like a placement bug")
		if not wc.has(key):
			continue
		_expect(float(wc.get(key)) < spawn.x,
			"World.%s (x %.0f) is behind the spawn (x %.0f), so nothing stands between you and the tower"
				% [key, float(wc.get(key)), spawn.x])
	_completes("spawn_is_on_the_doorstep")


## ══ YOU CAN CAST IN THE LOBBY ═══════════════════════════════════════════════
## Maker: "you should be able to cast spells and stuff within the lobby instead of a
## training ground — just have standing immortal test dummies on one side."
##
## Three separate claims, and all three are load-bearing:
##   1. the body you drive is a COMBAT body (it has a spell kit at all);
##   2. the dummies exist, and are on a faction the player is hostile to — without
##      that they are scenery you cannot hit, which looks identical;
##   3. they cannot die, which is what "immortal" means and what stops the yard
##      emptying itself the first time somebody throws an ult.
func _test_you_can_cast_in_the_lobby() -> void:
	var town: Node = _get_town()
	if town == null:
		return
	var body: Node = town.get_tree().get_first_node_in_group("player")
	_expect(body != null, "the town has a body in the `player` group")
	if body == null:
		_completes("you_can_cast_in_the_lobby")
		return
	_expect(body.has_method("configure_class") and body.has_method("ability_hud_state"),
		"...and it is a combat body, so it can cast")
	var dummies: Array = town.get_tree().get_nodes_in_group(&"town_dummy")
	_expect(dummies.size() >= 1, "the dummy yard is standing (got %d)" % dummies.size())
	for d: Node in dummies:
		_expect(int(d.get("max_hp")) >= 999,
			"a dummy is effectively immortal (max_hp %d)" % int(d.get("max_hp")))
		# ⚠ IT HAS A CONTROLLER, AND THAT IS WHAT MAKES IT STAND STILL. A controller-less
		# `Hero` falls through to the GLOBAL `Input` singleton, so the yard would mirror
		# every button the player presses. This used to be asserted as
		# `not is_physics_processing()` — which stopped the mirroring by stopping
		# EVERYTHING, gravity and ragdoll included. The assertion has to move with the
		# mechanism or it pins the old workaround in place.
		_expect(d.get("controller") != null,
			"...and it has an input source of its own rather than reading the player's")
		_expect(d.is_physics_processing(),
			"...while still running its own physics, so it falls, flinches and ragdolls")
	_completes("you_can_cast_in_the_lobby")


## THE PAD ROW IS TWO PADS, and each one names the screen it opens. A station whose
## screen went missing is a walk to a dead end.
##
## ══ WHAT THE MAKER RULED ════════════════════════════════════════════════════
## Asked which of the four pads to keep: *"I only want one for class within which I can
## edit spells, and one for armoury where I can look at my equipment"*. So the LECTERN
## (kind `"spells"`) and the ARCHIVIST (kind `"tree"`) are gone, and the class pad
## absorbed the lectern's screen.
##
## ⚠ THE ABSENCES ARE ASSERTED, NOT JUST THE PRESENCES. A kinds-present-only check stays
## green if somebody re-adds the lectern next to the class pad, which is the exact shape
## of the thing that was just removed — and it would land 0 px from a pad whose ring is
## 46. Both halves, or this test does not defend the ruling.
func _test_the_two_pads_answer() -> void:
	var town: Node = _get_town()
	if town == null:
		return
	var doors: Array = []
	_find(town, DOOR_SCRIPT, doors)
	_expect(doors.size() == 1, "exactly one tower door (got %d)" % doors.size())

	# ⚠ THE CLASS ALTAR IS A STATION KIND NOW, not its own script. `ClassAltar.gd` was
	# a fourth hand-written copy of walk-up-and-press-E and it was absorbed into
	# `ArmoryStation` when every station became a teleport pad — so it is asserted
	# below, by kind, with the rest of the row.

	var stations: Array = []
	_find(town, STATION_SCRIPT, stations)
	# TWO PADS IN A SOLO VISIT: gear and class. The PARTY STONE is the third and is
	# co-op-only — `World._session_is_party()` keeps it out of a solo room, because a
	# station that answers "nobody here" to a lone player is a dead object teaching them
	# the room has broken parts.
	#
	# ⚠ THE SPARRING PAD IS GONE, DELIBERATELY. It teleported you out to `FreePlay`, a
	# whole second scene, to answer "what does this spell look like". The maker's
	# ruling: "you should be able to cast spells and stuff within the lobby instead of
	# a training ground — just have standing immortal test dummies on one side."
	# `_test_you_can_cast_in_the_lobby` above is that ruling, asserted.
	#
	# Asserted by KIND rather than by count alone, so adding a station cannot silently
	# replace one: a count-only check passes just as happily on the wrong two.
	var station_kinds: Dictionary = {}
	for st: Node in stations:
		station_kinds[String(st.get("kind"))] = true
	var kinds: Array = []
	for s: Node in stations:
		kinds.append(String(s.get("kind")))
	_expect(stations.size() == 2,
		"two pads in a solo room: gear and class (got %d — %s)" % [stations.size(), str(kinds)])
	_expect(station_kinds.has("armory"), "the gear pad is there (got %s)" % str(kinds))
	_expect(station_kinds.has("class"), "the class pad is there (got %s)" % str(kinds))
	_expect(not station_kinds.has("party"),
		"...and the party stone is NOT, because this is a solo visit")
	# THE DELETED HALF OF THE RULING. See the header of this test.
	_expect(not station_kinds.has("spells"),
		"the LECTERN is gone — its screen is what the class pad now opens, and a second "
		+ "pad to the same screen is the row the maker just cut in half (got %s)" % str(kinds))
	_expect(not station_kinds.has("tree"),
		"the ARCHIVIST is gone — its screen spends real points that reach no fight "
		+ "(`SpellTree.bindable_spells` has no caller), so the pad took something and "
		+ "gave nothing back (got %s)" % str(kinds))
	# ⚠ THE GAP CLEARS THE PROXIMITY RING, AND THIS IS THE RULE RESPACING BREAKS. Two
	# pads closer together than 2 x PROXIMITY_RADIUS put two "[E] ..." hints on screen at
	# once and the player cannot tell which one the key presses. This was real twice: the
	# lectern and the Archivist stood 58 px apart, and the armoury pad at x=380 sat
	# inside the WARDEN's ring (that second one is `slice_test_town_interact`'s, because
	# a townsperson MOVES and a pad does not).
	#
	# ⚠ AND IT MUST NOT GO VACUOUS ON A ONE-PAD ROOM. With `stations.size() == 1` this
	# loop runs zero times and reports nothing, which the suite's own idiom counts as a
	# pass. The pair count is asserted first so an empty loop cannot be the reason.
	var xs: Array[float] = []
	for st2: Node in stations:
		xs.append((st2 as Node2D).global_position.x)
	xs.sort()
	var ring: float = float(load(STATION_SCRIPT).get("PROXIMITY_RADIUS"))
	_expect(xs.size() >= 2, "there are at least two pads to measure a gap between")
	for i: int in range(1, xs.size()):
		_expect(xs[i] - xs[i - 1] >= ring * 2.0,
			"pads at x %.0f and x %.0f are %.0f px apart, inside the %.0f px hint ring — "
			% [xs[i - 1], xs[i], xs[i] - xs[i - 1], ring * 2.0]
			+ "two prompts would be up at once")

	# THE STATION IS THE SCREEN. Each one must reach a real destination.
	_expect(load(DOOR_SCRIPT) != null and _code_only(DOOR_SCRIPT).contains("enter_run"),
		"the door starts a run")
	var station_src: String = _code_only(STATION_SCRIPT)
	_expect(station_src.contains("/root/Loadout"), "the rack opens the armory")
	# ⚠ THE CLASS PAD OPENS THE OUTFITTER NOW, NOT `ClassSelect`. This used to assert
	# that `ArmoryStation` names `ClassSelect` — an assertion that would STILL PASS after
	# the merge, because `_overlay_open()` mentions that autoload for an unrelated reason.
	# The live-screen check is `_test_the_class_pad_edits_spells_too`; this half only
	# pins that the pad reaches the town's opener at all.
	_expect(station_src.contains("open_outfitter"),
		"the class pad opens the outfitter (which is where the spells are)")
	_expect(not station_src.contains("open_spell_tree"),
		"...and nothing in the pad row still reaches for the deleted Archivist screen")
	var world_src: String = _code_only(WORLD_SCRIPT)
	_expect(world_src.contains("func open_outfitter"),
		"and the town owns the outfitter's lifetime")
	_expect(not world_src.contains("func open_spell_tree"),
		"the town no longer offers an opener nothing calls — `SpellTreeScreen` is kept "
		+ "but reachable by nothing, and its header says what would bring the pad back")
	_completes("the_two_pads_answer")


## ══ THE MERGE: ONE PAD, BOTH DECISIONS, NO KEYBOARD ═════════════════════════
## Maker: *"I only want one for class within which I can edit spells"*. That is two
## claims and they fail in different ways, so both are checked against the LIVE screen
## the pad opens rather than against the source text:
##
##   1. pressing the class pad lands on the screen that edits spells (the Outfitter);
##   2. that screen offers a way to change class that a THUMB can reach. `ClassSelect`
##      also answers to the number keys 1..9 and to card focus, and both of those are
##      worth exactly nothing on the target platform (D-011: virtual joystick and a tap).
##      So "reachable" here means a real `Button`, `MIN_TAP` tall, with something
##      connected to it.
##
## ⚠ AND THE PANEL MUST STILL FIT A PHONE. `slice_test_outfitter` pins the 360 px budget
## for the LOBBY's Outfitter — which does NOT build this row, because `show_class_picker`
## is off there — so nothing but this assertion covers the town's taller variant. Adding
## one more row is exactly how the bottom button walks off the bottom of a 6-inch screen
## while every desktop playtest looks perfect.
func _test_the_class_pad_edits_spells_too() -> void:
	var town: Node = _get_town()
	if town == null:
		return
	_expect(town.has_method("open_outfitter"), "the town can open the outfitter")
	if not town.has_method("open_outfitter"):
		_completes("the_class_pad_edits_spells_too")
		return
	# ⚠ THE WINDOW HAS TO EXIST BEFORE ANYTHING IS MEASURED. Headless has no window, so
	# `get_visible_rect()` falls back to a SQUARE 640x640 — and this screen is laid out
	# for 640x360 in LANDSCAPE, so measuring against the fallback would give the panel
	# 280 px of headroom it does not have on a phone. Set the real aspect, let a frame
	# land, and the viewport reads 640x360.
	root.size = Vector2i(1366, 768)
	await process_frame

	town.call("open_outfitter")
	# ⚠ TWO FRAMES, AND THIS IS WHAT THE FIRST VERSION OF THIS TEST GOT WRONG. It
	# measured the column the instant `open_outfitter` returned and read **1771 px**
	# against a 360 px budget — not a real overflow, an unlaid-out one. `_hint` and
	# `_summary` are `AUTOWRAP_WORD_SMART` Labels, and an autowrapped Label's minimum
	# HEIGHT is a function of its WIDTH; before a layout pass that width is 0, so every
	# label reports the height of one word per line. The number was garbage and it was
	# confidently red, which is worse than being green.
	await process_frame
	await process_frame
	var out: Control = town.get("_outfitter") as Control
	_expect(out != null, "...and the class pad's screen really builds")
	if out == null:
		_completes("the_class_pad_edits_spells_too")
		return
	_expect(bool(out.get("show_class_picker")),
		"the TOWN's outfitter carries the class row (the flag the Lobby's copy leaves off)")

	# The tappable route to the other half of the pad.
	var buttons: Array = []
	_walk(out, buttons)
	var class_btn: Button = null
	for b: Button in buttons:
		if b.text.contains("change"):
			class_btn = b
			break
	_expect(class_btn != null,
		"the outfitter offers a CLASS button — without it the class pad only edits "
		+ "spells and half the maker's sentence is unbuilt (buttons: %d)" % buttons.size())
	if class_btn != null:
		_expect(class_btn.custom_minimum_size.y >= MIN_TAP,
			"the class button is %.0f px tall, under the %.0f px thumb floor"
				% [class_btn.custom_minimum_size.y, MIN_TAP])
		_expect(class_btn.pressed.get_connections().size() > 0,
			"...and pressing it is wired to something")
		_expect(class_btn.text.contains(ClassInfo.name_for(int(out.call("class_id")))),
			"...and it names the class you are actually in, so the button is also the "
			+ "readout (text was '%s')" % class_btn.text)

	# And the screen the button opens has to be able to answer back, or the Outfitter
	# would go on showing the OLD class's spells after a pick.
	var sel: Node = root.get_node_or_null(^"/root/ClassSelect")
	if sel != null:
		_expect(sel.has_signal(&"class_picked"),
			"ClassSelect announces a hub-side pick, so the merged screen can re-aim itself")
		# ══ THE MERGE, DRIVEN ══════════════════════════════════════════════════
		# ⚠ EVERYTHING ABOVE THIS POINT IS SHAPE, AND SHAPE IS NOT BEHAVIOUR. A button
		# that exists, is tall enough and has a connection can still open a screen whose
		# answer nobody listens to — in which case the class changes and the Outfitter
		# goes on showing the OLD class's spells, which is the merge silently not being
		# a merge. So: press the button for real, pick a card for real, and read back
		# what the screen is now aimed at.
		var before: int = int(out.call("class_id"))
		if class_btn != null:
			class_btn.pressed.emit()
			await process_frame
			_expect(bool(sel.call("is_open")),
				"pressing the class button really opens the chooser")
			# A DIFFERENT class, and an unlocked one — three of the nine are held by a
			# guardian and `_on_card_pressed` re-checks that, so a locked card would
			# refuse and this would look like a broken signal instead of a locked class.
			var cards: Array = []
			_walk(sel, cards)
			var target: int = -1
			for i: int in cards.size():
				if i != before and not (cards[i] as Button).disabled:
					target = i
					break
			_expect(target >= 0, "there is a second unlocked class to switch to")
			if target >= 0:
				(cards[target] as Button).pressed.emit()
				await process_frame
				_expect(not bool(sel.call("is_open")),
					"...and picking a card closes the chooser")
				_expect(int(out.call("class_id")) == target,
					"THE MERGE: after picking class %d the outfitter is aimed at %d, not the "
						% [target, int(out.call("class_id"))]
					+ "%d it opened on — otherwise the pad changes your class and goes on "
						% before
					+ "showing the previous class's spells")
				# ⚠ PUT BACK. `_on_card_pressed` writes `GameState.selected_class`, which
				# is a persisted global shared with every other suite and with the player's
				# own save. A test that leaves the player as a different class than they
				# chose is a test that broke the game to prove a point.
				var gs2: Node = root.get_node_or_null(^"/root/GameState")
				if gs2 != null:
					gs2.set("selected_class", before)
				out.call("set_class", before)
		# ⚠ THE LAYER ORDER IS THE MERGE'S ONE REAL TRAP AND IT WAS BROKEN. The town's
		# overlay layer was 95 and BOTH autoload panels draw at 90, so the Outfitter's
		# existing "⚒ Armory" button opened the armory BEHIND this screen's 0.93-opaque
		# dimmer — a dead button with no error anywhere. The class button would have done
		# the same. Asserted against the live autoload rather than against the literal 90.
		var world_layer: int = int((load(WORLD_SCRIPT) as GDScript)
			.get_script_constant_map().get("OVERLAY_LAYER", 1 << 30))
		_expect(world_layer < int(sel.get("layer")),
			"the town's overlay layer (%d) must sit BELOW ClassSelect's (%d) or the class "
			% [world_layer, int(sel.get("layer"))]
			+ "grid opens behind an opaque dimmer and the button looks dead")

	# THE PHONE BUDGET. Measured, and the measurement is itself checked for zero — a
	# container that reports nothing would otherwise sail under any ceiling.
	var col: Control = out.get("_col") as Control
	_expect(col != null, "the outfitter's column is reachable for measurement")
	if col != null:
		var needed: Vector2 = col.get_combined_minimum_size()
		_expect(needed.y > 0.0,
			"the column reports a real height (got %.0f — a zero measurement passes every "
				% needed.y + "ceiling and proves nothing)")
		_expect(needed.y <= BASE_H,
			"the town's outfitter fits %.0f px of height WITH the class row (needs %.0f)"
				% [BASE_H, needed.y])
	# Left as we found it, or the next test inherits a full-screen overlay.
	if out.has_method("close"):
		out.call("close")
	_completes("the_class_pad_edits_spells_too")


## Every Button under a node, for the tap-target checks.
func _walk(from: Node, out: Array) -> void:
	if from is Button:
		out.append(from)
	for c: Node in from.get_children():
		_walk(c, out)


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
	# ⚠ TWO, NOT THREE, AND THE COUNT IS PINNED TO THE TABLE. The maker asked for
	# "fewer of them", so the number is a decision that can move; what must never drift
	# is the table and the room disagreeing, which a `>=` cannot catch — it would stay
	# green if a `.tres` path went stale and a townsperson silently stopped spawning.
	_expect(folk.size() == town.get("TOWNSFOLK").size(),
		"every townsperson in the table is really in the room (%d of %d)"
			% [folk.size(), town.get("TOWNSFOLK").size()])
	_expect(folk.size() >= 1, "...and the room is not empty (got %d)" % folk.size())
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
