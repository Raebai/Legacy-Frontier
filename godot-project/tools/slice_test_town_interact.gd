# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_town_interact.gd
#
# ══ WHO GETS THE `talk` PRESS, AND WHO IS STANDING ON THE SPAWN POINT ══════════
#
# Three unrelated things in the town listen for `talk` in `_unhandled_input` and each
# one calls `set_input_as_handled()`: the townsfolk (`NPC`), the teleport pads
# (`ArmoryStation`) and the way out (`TowerDoor`). Nothing arbitrated between them, so
# the winner was whichever node `_unhandled_input` reached first -- and that is TREE
# ORDER, decided by the order `World` happens to add children. Townsfolk are added
# last, so a townsperson beat both of the others.
#
# It shipped, and the ranges made it inevitable rather than unlucky:
#
#   * `TowerDoor.PROXIMITY_RADIUS` is 150 px. The doorkeeper stood inside it, so E
#     near the door TALKED TO HIM instead of entering the tower. Walking in still
#     worked, which is exactly why nobody caught it: the feature was not dead, only
#     one of its two routes was, and only in one place.
#   * `ArmoryStation.PROXIMITY_RADIUS` is 46 px and the warden's 40 px ring reaches
#     x=384 against the armoury pad at x=380, so for part of every lap he walks,
#     standing ON the pad showed two hints and E talked to the warden.
#
# And underneath that, a worse one with no input in it at all: the player spawned
# INSIDE THE DOORKEEPER'S PATROL SPAN (he walked 838..886, the player materialised at
# 876). Not merely inside his hint ring -- inside the ground he paces. So the town
# opened with him frozen mid-stride and hint-lit before either of them had moved, and
# he could not amble or hop again until you walked away from your own spawn point.
# The maker's own "townsfolk need PERSONALITY, have them jump around" feature was
# switched off for the one townsperson every player is guaranteed to meet.
#
# WHAT IS PINNED HERE, and why each is a thing that silently comes back:
#   1. Nobody's patrol span contains the spawn point, and nobody's hint ring reaches
#      it. Both are position constants in two different files, so they drift apart
#      the moment either one is nudged.
#   2. Every `talk` listener is registered for arbitration and answers
#      `interact_ready()`. A new interactable that forgets to join does not error --
#      it silently goes back to winning or losing by tree order.
#   3. Arbitration actually picks the NEAREST ready one, checked on the real overlap
#      the town contains rather than on a constructed pair.
extends SceneTree

const TOWN_SCENE: String = "res://scenes/Main.tscn"
const NPC_SCRIPT: String = "res://scripts/NPC.gd"
const STATION_SCRIPT: String = "res://scripts/ArmoryStation.gd"
const DOOR_SCRIPT: String = "res://scripts/TowerDoor.gd"
const Interactables := preload("res://scripts/Interactables.gd")

## The NPC hint ring, from `scenes/NPC.tscn`. Duplicated as a literal on purpose: the
## point of test 1 is to catch the scene and `World.gd` drifting apart, and reading
## the radius out of the same scene the code reads it from would make the two agree
## by construction and prove nothing.
const NPC_RING: float = 40.0

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
const TESTS: Array[String] = [
	"nobody_is_standing_on_the_spawn_point",
	"every_talk_listener_is_registered",
	"arbitration_picks_the_nearest",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _town: Node = null


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_spawn_is_clear()
	_test_listeners_registered()
	_test_nearest_wins()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Town-interact tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Town-interact tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


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


# ------------------------------------------------------------------------- 1
## THE SPAWN POINT IS NOT SOMEBODY'S FLOOR.
##
## Checked against the AUTHORED table rather than against where the bodies happen to
## be standing on frame one, because a patrol is a moving fact: a townsperson who
## merely starts clear of the spawn still walks through it a second later, which is
## the failure the shipped build actually had. The span is the thing to test.
func _test_spawn_is_clear() -> void:
	var world_script: GDScript = load("res://scripts/World.gd") as GDScript
	_expect(world_script != null, "World.gd loads")
	if world_script == null:
		return
	var spawn: Vector2 = world_script.PLAYER_SPAWN
	var folk: Array = world_script.TOWNSFOLK
	_expect(folk.size() > 0, "the town has townsfolk to check (%d)" % folk.size())
	for entry: Dictionary in folk:
		var cx: float = float(entry.get("x", 0.0))
		var rng: float = float(entry.get("range", 0.0))
		var res: String = String(entry.get("res", "?")).get_file()
		# The span they pace.
		_expect(spawn.x < cx - rng or spawn.x > cx + rng,
			("%s paces x %.0f..%.0f and the player spawns at x %.0f — INSIDE it, so the "
			+ "town opens with them frozen and hint-lit and they can never amble again "
			+ "until you walk off your own spawn") % [res, cx - rng, cx + rng, spawn.x])
		# ...and the ring they light up, which is the wider constraint.
		var gap: float = minf(absf(spawn.x - (cx - rng)), absf(spawn.x - (cx + rng)))
		_expect(gap >= NPC_RING,
			("%s comes within %.1f px of the spawn and their hint ring is %.1f px, so "
			+ "the town opens with their prompt already up") % [res, gap, NPC_RING])
	_completes("nobody_is_standing_on_the_spawn_point")


# ------------------------------------------------------------------------- 2
## EVERY `talk` LISTENER COMPETES. A node that listens for the press but never joins
## the group does not error and does not warn — it just goes back to winning or
## losing by tree order, which is the original bug wearing the fix as a hat.
##
## Driven off the SOURCE (which scripts contain a `talk` handler) rather than off the
## group (which is the thing being tested), so a listener added tomorrow is caught by
## its absence rather than excused by it.
func _test_listeners_registered() -> void:
	var town: Node = _get_town()
	_expect(town != null, "the town scene instantiates")
	if town == null:
		return
	for script_path: String in [NPC_SCRIPT, STATION_SCRIPT, DOOR_SCRIPT]:
		var f: FileAccess = FileAccess.open(script_path, FileAccess.READ)
		_expect(f != null, "%s is readable" % script_path)
		if f == null:
			continue
		var src: String = f.get_as_text()
		if not src.contains('is_action_pressed("talk")'):
			continue    # not a listener; nothing to register
		var found: Array = []
		_find(town, script_path, found)
		_expect(found.size() > 0, "%s is present in the town" % script_path.get_file())
		for n: Node in found:
			_expect(n.is_in_group(Interactables.GROUP),
				("%s listens for `talk` but never joined the arbitration group, so it is "
				+ "back to winning by tree order") % script_path.get_file())
			_expect(n.has_method(&"interact_ready"),
				("%s is in the arbitration group but cannot say whether it is ready, so "
				+ "it competes for presses from across the room") % script_path.get_file())
	_completes("every_talk_listener_is_registered")


# ------------------------------------------------------------------------- 3
## ARBITRATION PICKS THE NEAREST — checked on the town's REAL geometry.
##
## Asked of `nearest_of`, the pure rule, rather than of `wins`. `wins` additionally
## filters on readiness, and readiness comes from `Area2D` overlaps that have not
## necessarily ticked on the frame a test moves a body — so a `wins`-based version of
## this test measures physics timing while claiming to measure arbitration. (It was
## written that way first and reported that all seven interactables won simultaneously,
## which is what sent me to make `wins` total; the finding was real, the instrument was
## not.) The registration half is test 2's job; this half is the rule.
func _test_nearest_wins() -> void:
	var town: Node = _get_town()
	if town == null:
		return
	var members: Array = town.get_tree().get_nodes_in_group(Interactables.GROUP)
	_expect(members.size() >= 2,
		"there are at least two interactables to arbitrate between (%d)" % members.size())
	if members.size() < 2:
		return
	# Standing exactly on a thing must select that thing. Trivial-looking, and it is
	# the whole contract: it fails the moment the rule stops being distance.
	for target: Node in members:
		var t: Node2D = target as Node2D
		if t == null:
			continue
		var got: Node2D = Interactables.nearest_of(members, t.global_position)
		_expect(got == t or (got != null and got.global_position.is_equal_approx(t.global_position)),
			"standing on %s at x=%.0f, the press went to %s at x=%.0f instead"
			% [t.name, t.global_position.x, "nothing" if got == null else got.name,
				0.0 if got == null else got.global_position.x])
	# THE OVERLAP THAT SHIPPED BROKEN. The doorkeeper used to sit inside the tower
	# door's 150 px ring, so every press near the door talked to him. Walk to the
	# door's own position and the DOOR has to win — if this ever flips, E stops
	# entering the tower again and walking in silently becomes the only route.
	var door: Array = []
	_find(town, DOOR_SCRIPT, door)
	_expect(door.size() == 1, "the town has exactly one tower door (%d)" % door.size())
	if door.size() == 1:
		var d: Node2D = door[0] as Node2D
		var at_door: Node2D = Interactables.nearest_of(members, d.global_position)
		_expect(at_door == d,
			("standing in the doorway, the press goes to %s rather than the door — this "
			+ "is the shipped bug: the doorkeeper stood inside the door's 150 px ring "
			+ "and won on tree order") % ["nothing" if at_door == null else at_door.name])
	_completes("arbitration_picks_the_nearest")
