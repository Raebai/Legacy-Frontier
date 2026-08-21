# Run: godot --headless --path godot-project --script tools/slice_test_bout_runs_clean.gd
#
# A REAL BOUT ACTUALLY RUNS — two bots, casting, for long enough to matter.
#
# ⚠ WHY THIS SUITE EXISTS. Nothing in 167 suites had ever run a FIGHT. They built
# arenas, spawned heroes, pinned constants and drove single spells, and not one of them
# let two bots trade blows for ten seconds. So the 2026-08-07 batch shipped two faults
# that a single bout would have surfaced instantly, and both survived a week of green:
#
#   SCRIPT ERROR: Invalid assignment of property or key 'terraces'      (no terrain)
#   SCRIPT ERROR: Left operand of 'is' is a previously freed instance   (the ult banner)
#
# The second one is the sharper lesson. `CastName._heavy_label` guarded itself with
# `live is Node and is_instance_valid(live)` — the right check on the WRONG SIDE of the
# `and`, because `is` itself throws on a freed instance. It was unreachable by
# construction, and it fired about one second into every fight, because the label frees
# itself while the caster's meta goes on pointing at it. Nothing static could have found
# that. Only running the fight does.
#
# ⚠ THE VERDICT IS NOT THIS FILE'S TO GIVE. A GDScript suite cannot read the engine's
# stderr, so it cannot see a `SCRIPT ERROR` that GDScript treats as non-fatal. It does
# not have to: `run_all_tests.py` fails ANY suite that emits one. This file's whole job
# is to EXERCISE the path loudly enough that the gate has something to judge.
#
# ⚠ WHICH IS WHY THE ASSERTIONS BELOW ARE ABOUT REACH, NOT ABOUT ABSENCE. "No error
# occurred" is satisfied by a bout that never started. So this pins that the fight got
# far enough to be worth trusting: two live fighters, real spells in the world, and the
# naming path — the one that was broken — actually invoked. Verified by negative
# control: with the guard reverted, `botmatch_sim --pairs=2` reports the freed-instance
# error 9 times, so this path is genuinely reached rather than merely hoped for.
#
# ⚠ BY PATH, never by `class_name` — `BotMatch` and everything under it reach the
# autoloads, and this runs on the first frame for the same reason.
extends SceneTree

const BOT_MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
## ⚠ RETARGETED. This counted `CastName` nodes; there were TWO systems printing a
## spell's name (`CastName` at release in the CASTER's colour, `SignatureRite` at
## windup in the SPELL's) and the maker was seeing both at once. `SignatureRite` is now
## the only announcer, so this counts its card instead — same assertion, one owner.
const CARD_NODE_NAME: StringName = SignatureRite.CARD_NAME

## ⚠ DRIVEN BY THE WALL CLOCK, NOT BY A FRAME COUNT, and the first version of this file
## got that wrong. A `--script` SceneTree pumps `process_frame` as fast as the CPU
## allows and `delta` is REAL elapsed time, so 600 iterations is a fraction of a second
## of game time, not "ten seconds at 60 Hz" as the comment here used to claim. The bout
## never got anywhere near its own end and the suite could not have known.
## `tools/botmatch_sim.gd` already ran on a wall-clock cap for exactly this reason.
const WALL_SECONDS: float = 45.0
## How long to keep pumping AFTER the bell, through the result phase and the teardown
## into the next bout — the path that crashed.
const FRAMES_AFTER_END: int = 90
## Hard iteration ceiling so a stall fails loudly instead of eating the runner's 120 s.
const MAX_FRAMES: int = 200000

const TESTS: Array[String] = [
	"the_bout_stands_up",
	"both_fighters_are_alive_and_fighting",
	"spells_actually_reach_the_world",
	"the_cast_naming_path_is_exercised",
	"the_bout_actually_ends",
	"the_hud_survives_leaving_the_tree",
]

## ⚠ SHORTENED SO A BOUT ACTUALLY FINISHES INSIDE THIS SUITE. `round_seconds` ships at
## 75 and this suite walks ten seconds of frames, so before this line NO TEST IN THE
## REPO HAD EVER SEEN A BOUT END — and the end is where the next crash was:
##
##     Cannot call method 'get_visible_rect' on a null value
##         at: BotMatch._paint_hud   <- _process   (the result phase)
##
## One fight ran fine and the transition out of it took the game down. "It runs" and
## "it finishes" are different claims and only the first was ever being made.
const SHORT_ROUND: float = 4.0

var _fails: int = 0
var _completed: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: PackedScene = load(BOT_MATCH_SCENE) as PackedScene
	if scene == null:
		_expect(false, "BotMatch.tscn loads")
		_finish()
		return
	# Before instantiating — `_ready` reads it. By path, never by `class_name`.
	var bm_script: GDScript = load("res://scripts/combat/BotMatch.gd") as GDScript
	if bm_script != null:
		bm_script.set("round_seconds", SHORT_ROUND)
	var match_node: Node = scene.instantiate()
	root.add_child(match_node)
	_expect(is_instance_valid(match_node), "the bot match stands up")
	_completed["the_bout_stands_up"] = true

	# Watch the fight rather than just waiting it out: the counters below are the only
	# thing separating "ran clean" from "never started".
	var started: float = float(Time.get_ticks_msec()) / 1000.0
	var max_heroes: int = 0
	var spells_seen: int = 0
	var names_seen: int = 0
	var ended: bool = false
	var frames_after_end: int = 0
	for i: int in MAX_FRAMES:
		await process_frame
		if not is_instance_valid(match_node):
			break
		max_heroes = maxi(max_heroes, get_nodes_in_group("hero").size())
		spells_seen = maxi(spells_seen, get_nodes_in_group("player_spell").size())
		names_seen += _count_cast_names(match_node)
		# ⚠ KEEP RUNNING AFTER THE BELL. The result phase and the teardown into the next
		# bout are a DIFFERENT code path from the fight, and they are the path that
		# crashed. Stopping at "match_over" would have walked away one frame before the
		# bug every single time.
		if match_node.has_method("match_over") and bool(match_node.call("match_over")):
			ended = true
		if ended:
			frames_after_end += 1
			if frames_after_end >= FRAMES_AFTER_END:
				break
		if float(Time.get_ticks_msec()) / 1000.0 - started > WALL_SECONDS:
			break

	_expect(ended,
		"the bout reached its end inside %.0f s with round_seconds = %.0f — if it never "
			% [WALL_SECONDS, SHORT_ROUND] + "ends, everything this suite says about the "
			+ "result phase is vacuous")
	_expect(frames_after_end >= FRAMES_AFTER_END,
		"…and the result phase ran for %d frames afterwards (wanted %d), which is the "
			% [frames_after_end, FRAMES_AFTER_END]
			+ "window where _paint_hud met a null viewport")
	if ended and frames_after_end >= FRAMES_AFTER_END:
		_completed["the_bout_actually_ends"] = true

	_expect(max_heroes >= 2,
		"two fighters were live during the bout (saw at most %d) — with fewer than "
			% max_heroes + "two, everything below this is vacuous")
	_completed["both_fighters_are_alive_and_fighting"] = true

	_expect(spells_seen > 0,
		"spells reached the world during the bout (saw none) — a silent fight proves "
			+ "nothing about the cast path")
	_completed["spells_actually_reach_the_world"] = true

	# ⚠ THE ONE THAT MATTERS. This is the path that was crashing. If it is never
	# invoked, a clean run is meaningless — which is exactly the state the whole test
	# suite was in before this file.
	_expect(names_seen > 0,
		"the cast-name path ran at least once (saw %d) — this is the code that threw "
			% names_seen + "'Left operand of is is a previously freed instance' on "
			+ "every fight, so a bout that never reaches it cannot clear it")
	_completed["the_cast_naming_path_is_exercised"] = true

	# ⚠ THE CRASH STATE, REPRODUCED DIRECTLY, because running a whole bout does NOT
	# produce it. Verified by negative control: with the `get_viewport() == null` guard
	# disabled, everything above still passed. `_process` keeps firing for a frame after
	# a node leaves the tree, and `get_viewport()` answers null there — which is the
	# teardown between bouts, not any moment inside one. So the honest test is not "play
	# longer", it is "ask the HUD to paint while it is out of the tree", which is
	# exactly what the engine did.
	#
	# There is no assertion here on purpose: a GDScript runtime error is not catchable
	# from inside the suite. `run_all_tests.py` fails any suite that emits `SCRIPT ERROR`,
	# so REACHING this line without one IS the pass, and the sentinel proves it was
	# reached rather than skipped.
	if is_instance_valid(match_node) and match_node.is_inside_tree():
		root.remove_child(match_node)
	if is_instance_valid(match_node) and match_node.has_method("_paint_hud"):
		match_node.call("_paint_hud")
		_completed["the_hud_survives_leaving_the_tree"] = true
	if is_instance_valid(match_node):
		match_node.queue_free()
	_finish()


## Live `CastName` nodes anywhere under the match, found by SCRIPT PATH rather than by
## `class_name` — see the header.
func _count_cast_names(from: Node) -> int:
	var n: int = 0
	for child: Node in from.get_children():
		var s: Script = child.get_script() as Script
		if child.name == String(CARD_NODE_NAME):
			n += 1
		n += _count_cast_names(child)
	return n


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("bout_runs_clean: FAIL — %s" % msg)


func _finish() -> void:
	for t: String in TESTS:
		if not _completed.has(t):
			_fails += 1
			printerr("bout_runs_clean: TEST DID NOT COMPLETE — %s" % t)
	if _fails > 0:
		printerr("bout tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("bout tests: all PASS")
		quit(0)
