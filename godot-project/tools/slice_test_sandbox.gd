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


## ⚠ PHYSICS FRAMES, NOT PROCESS FRAMES, AND THAT ONE WORD WAS THE WHOLE FLAKE.
##
## This suite was the repo's known intermittent: it passed 4/4 run alone and failed
## roughly one run in three under `--jobs 3`, on a clean tree, which made it look like
## contention or a stray port rather than a defect in the test.
##
## It settled with `await process_frame` -- the IDLE frame -- and then asserted about
## positions produced by gravity and `move_and_slide`, which advance on the PHYSICS
## frame. Those two are not locked together. Physics is paced by the wall clock at 60 Hz
## while headless idle frames run as fast as the machine allows, so "70 frames" bought a
## number of physics steps that depended entirely on how busy the CPU was. Run alone: few
## steps, the duellists have barely begun, everyone is near spawn. Run against two
## siblings: the same 70 idle frames span far more wall time, the bots get a real second
## of fighting in, and they have walked out of the leash the test draws around spawn.
##
## Measured, six concurrent runs of the OLD code: 4 of 6 FAILED, at x 866-875 with y
## identical to four decimal places (770.9275) in every one of them. The identical y is
## the tell and it is what rules out a settling problem -- the bodies had finished
## falling in all six. Only the horizontal wander differed, because only the horizontal
## wander is a function of how many steps of FIGHTING happened.
##
## Awaiting `physics_frame` makes the count mean the thing the assertion measures, so the
## settle is the same length in every process regardless of load. This is the same
## lesson already recorded in this project as "`Time.get_ticks_msec()` is ~20x wrong
## inside `--write-movie`, use frames" -- with the sharpener that it is not enough to
## count frames, you have to count the frames the subject moves on.
func _run() -> void:
	await _settle()

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


## SETTLED IS A STATE, NOT A FRAME COUNT, and confusing the two is what made this the
## repo's known intermittent suite.
##
## What it did before: `for i in 70: await process_frame`, then assert that each duellist
## is within 250 px of its own spawn. Two separate faults, stacked.
##
## FAULT ONE, the flake. It settled on the IDLE frame and asserted about positions
## produced by gravity and `move_and_slide`, which advance on the PHYSICS frame. Those
## are not locked together: physics is paced by the wall clock at 60 Hz while headless
## idle frames run as fast as the machine allows, so "70 frames" bought a number of
## physics steps that depended entirely on CPU load. Alone it passed 4/4; under
## `--jobs 3` it failed about one run in three, which read as contention rather than as a
## defect in the test. Measured, six concurrent runs of the old code: 4 of 6 FAILED, at
## x 866-875 with y identical to four decimals (770.9275) in all of them. That identical
## y is the tell, and it is what rules out a settling problem -- the bodies had finished
## FALLING in every one. Only the horizontal wander varied, because only the wander is a
## function of how many steps of FIGHTING happened.
##
## FAULT TWO, which fixing the first one exposed rather than caused. Awaiting
## `physics_frame` made 70 mean 70 everywhere -- and 70 physics frames is 1.17 s of two
## duellists closing on each other. They spawn at x 560 and x 1120 and walk toward the
## middle, so after a real second of fighting they are ~250 px from where they started
## BY DESIGN. Six concurrent runs still failed 4 of 6, now at a much tighter x 806-814:
## deterministic, and deterministically wrong. No frame count can make "near its own
## spawn" true once the fight has started; the number was never the thing being waited
## for.
##
## What the assertion actually wants is the moment gravity has finished and the fight has
## not begun -- which the file's own comment says out loud ("well inside this radius even
## after gravity settles them onto the ground surface"). So it waits for exactly that:
## every body on the floor. The 55 px drop from spawn to the ground surface takes ~14
## frames, so this returns long before anyone has walked anywhere, and it returns after
## the SAME amount of simulated falling on a loaded machine as on an idle one.
##
## `SETTLE_FRAMES` survives as the CAP rather than the count. A body that never lands is
## a real failure and must not hang the suite; reaching the cap simply falls through to
## the assertions, which then report the position honestly instead of timing out.
func _settle() -> void:
	for i: int in SETTLE_FRAMES:
		await physics_frame
		var all_down: bool = true
		var seen: int = 0
		for h: Node in root.get_tree().get_nodes_in_group("hero"):
			var body: CharacterBody2D = h as CharacterBody2D
			if body == null:
				continue
			seen += 1
			if not body.is_on_floor():
				all_down = false
				break
		# `seen > 0` guards the frame before the arena has built its duellists: "nobody
		# has failed to land" is trivially true of an empty room, and returning there
		# would assert about a stage with nothing on it.
		if all_down and seen > 0:
			return


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
