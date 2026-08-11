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
const CAST_NAME_SCRIPT: String = "res://scripts/combat/CastName.gd"

## Ten game-seconds at 60 Hz. The banner bug needed barely one; ten covers several
## casts per fighter and at least one cooldown cycle on every slot.
const FIGHT_FRAMES: int = 600
## Wall-clock guard so a hang fails loudly instead of eating the runner's 120 s.
const WALL_SECONDS: float = 90.0

const TESTS: Array[String] = [
	"the_bout_stands_up",
	"both_fighters_are_alive_and_fighting",
	"spells_actually_reach_the_world",
	"the_cast_naming_path_is_exercised",
]

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
	for i: int in FIGHT_FRAMES:
		await process_frame
		if not is_instance_valid(match_node):
			break
		max_heroes = maxi(max_heroes, get_nodes_in_group("hero").size())
		spells_seen = maxi(spells_seen, get_nodes_in_group("player_spell").size())
		names_seen += _count_cast_names(match_node)
		if float(Time.get_ticks_msec()) / 1000.0 - started > WALL_SECONDS:
			_expect(false, "the bout finished inside %.0f s of wall clock" % WALL_SECONDS)
			break

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

	if is_instance_valid(match_node):
		match_node.queue_free()
	_finish()


## Live `CastName` nodes anywhere under the match, found by SCRIPT PATH rather than by
## `class_name` — see the header.
func _count_cast_names(from: Node) -> int:
	var n: int = 0
	for child: Node in from.get_children():
		var s: Script = child.get_script() as Script
		if s != null and s.resource_path == CAST_NAME_SCRIPT:
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
