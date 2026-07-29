# Run: godot --headless --path godot-project --script tools/slice_test_sandbox.gd
# Task 1 (Stick Fight Feel Foundation): boots the sandbox exactly like a real F5
# would — loads the packed VersusArena.tscn (project.godot's new main_scene), not
# just the bare script — settles ~70 frames (arena_wide_capture.gd's idiom: the
# fighters/dummies spawn a little above their surface and fall onto it) so
# gravity has actually landed everyone, then asserts the DUEL contract.
#
# THE PRACTICE DUMMIES ARE GONE, with the rest of the group battle ("remove that
# group battle"): booting the sandbox now drops you into the 1v1, so what this
# suite guards is that the two duellists land on solid rock near their spawns and
# that no trash-mob roster is left behind them. SceneTree-runner shape mirrors
# slice_test_coop.gd / slice3_test_versus.gd.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"dummies_exist_and_are_flagged",
	"dummies_positioned_near_spawn",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ARENA_SCENE_PATH: String = "res://scenes/combat/VersusArena.tscn"
const SETTLE_FRAMES: int = 70
## Loose leash around P1_SPAWN: dummies sit at fixed offsets either side of it
## (VersusArena.DUMMY_X_OFFSETS, +-120px), well inside this radius even after
## gravity settles them onto the ground surface.
const NEAR_SPAWN_RADIUS: float = 250.0

var _arena: Node2D = null


func _initialize() -> void:
	var arena_scene: PackedScene = load(ARENA_SCENE_PATH)
	_arena = arena_scene.instantiate()
	root.add_child(_arena)  # _ready builds the whole match + dummies synchronously
	_run()


func _run() -> void:
	for i: int in SETTLE_FRAMES:
		await process_frame

	_test_dummies_exist_and_are_flagged()
	_test_dummies_positioned_near_spawn()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("sandbox tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("sandbox tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Booting the packed scene is a DUEL, with nothing else on the stage: no
## five-bot roster, no practice dummies, nothing in group "enemy" for a spell to
## hit instead of the opponent.
func _test_dummies_exist_and_are_flagged() -> void:
	_expect(get_nodes_in_group("dummy").is_empty(),
		"no practice dummies (the group battle was removed), got %d"
			% get_nodes_in_group("dummy").size())
	_expect(get_nodes_in_group("enemy").is_empty(),
		"no trash-mob roster on the duel stage, got %d"
			% get_nodes_in_group("enemy").size())
	_expect(get_nodes_in_group("hero").size() == 2,
		"exactly two heroes — you and the bot, got %d" % get_nodes_in_group("hero").size())
	_completes("dummies_exist_and_are_flagged")


## Both duellists settle ON the rock near their own spawns — the ~70-frame settle
## above is what makes this a real gravity check rather than a spawn readout.
func _test_dummies_positioned_near_spawn() -> void:
	for h: Node in get_nodes_in_group("hero"):
		if not h is Node2D:
			_expect(false, "hero %s is a Node2D" % str(h))
			continue
		var pos: Vector2 = (h as Node2D).global_position
		var near: bool = pos.distance_to(_arena.DUEL_SPAWN_HUMAN) <= NEAR_SPAWN_RADIUS 			or pos.distance_to(_arena.DUEL_SPAWN_BOT) <= NEAR_SPAWN_RADIUS
		_expect(near, "a duellist settled near its own spawn, got %s" % pos)
	_completes("dummies_positioned_near_spawn")
