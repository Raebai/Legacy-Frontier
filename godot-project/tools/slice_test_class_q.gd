# Run: godot --headless --path godot-project --script tools/slice_test_class_q.gd
# Verifies the per-class DISTINCT Q spectacles (Phase-1b): each caster class fires
# a different spectacle scene, and firing it spawns a spectacle node without error
# (the runtime-safety check that compile + signature-matching can't fully prove).
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

## (class enum index, human name) for the five casters whose Q changed. Doubles as
## the sentinel roster below — one test function run five times is FIVE tests, and
## a single shared sentinel would be set by case 1 and hide an abort in case 3.
const CASES: Array = [
	[0, "MAGE/arcane_meteor"],
	[4, "CLERIC/consecrate"],
	[5, "CRYOMANCER/ice_shards"],
	[6, "STORMCALLER/call_lightning"],
	[7, "WARLOCK/curse_chain"],
]

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"MAGE/arcane_meteor",
	"CLERIC/consecrate",
	"CRYOMANCER/ice_shards",
	"STORMCALLER/call_lightning",
	"WARLOCK/curse_chain",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	for c: Array in CASES:
		_test_q_spawns(int(c[0]), String(c[1]))
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Class-Q tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Class-Q tests: all PASS")
		quit(0)
	return true


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


func _test_q_spawns(cls: int, label: String) -> void:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)
	hero.set_physics_process(false)
	hero.global_position = Vector2(600, 700)
	hero.configure_class(cls)
	hero.set("_aim_dir", Vector2.RIGHT)
	# Firing the Q must add a spectacle node under the hero's parent (root here)
	# and must not throw (a raised error aborts the whole --script run).
	var before: int = root.get_child_count()
	hero._blast()
	var after: int = root.get_child_count()
	_expect(after > before, "%s Q spawned a spectacle (%d -> %d)" % [label, before, after])
	hero.queue_free()
	_completes(label)  # per-CASE, not per-function — see CASES
