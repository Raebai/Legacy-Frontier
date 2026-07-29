# Run: godot --headless --path godot-project --script tools/slice_test_coop.gd
# Co-op host-authoritative enemies. The load-bearing correctness property is that
# the host + every client build BYTE-IDENTICAL enemies from the same replicated
# spawn data — which requires Encounter's stat table to agree with Enemy's, and
# build_enemy_from_data to construct the right node. Both are pure construction
# (no tree, no autoloads, no networking), so they test headlessly here.
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
	"stat_tables_agree",
	"hp_mult_scaling",
	"build_enemy_from_data",
	"build_boss_from_data",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_stat_tables_agree()
	_test_hp_mult_scaling()
	_test_build_enemy_from_data()
	_test_build_boss_from_data()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Coop tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Coop tests: all PASS")
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


## Every archetype's Encounter stats must match Enemy.ARCHETYPE_DEFAULTS, or the host
## and a client would spawn differently-statted enemies from the same data.
func _test_stat_tables_agree() -> void:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var defaults: Dictionary = load(ENEMY_PATH).ARCHETYPE_DEFAULTS
	for kind: int in range(8):
		var s: Dictionary = enc._archetype_stats(kind, 1.0)
		var d: Dictionary = defaults[kind]
		_expect(int(s["hp"]) == int(d["hp"]), "hp mismatch archetype %d" % kind)
		_expect(float(s["spd"]) == float(d["speed"]), "speed mismatch archetype %d" % kind)
		_expect(int(s["touch"]) == int(d["touch"]), "touch mismatch archetype %d" % kind)
		_expect(s["tint"] == d["tint"], "tint mismatch archetype %d" % kind)
	# BRUTE (1) is the only telegraphed archetype.
	_expect(bool(enc._archetype_stats(1, 1.0)["tele"]), "brute should telegraph")
	_expect(not bool(enc._archetype_stats(0, 1.0)["tele"]), "chaser should not telegraph")
	enc.free()
	_completes("stat_tables_agree")


## hp_mult scales hp (the floor-difficulty knob) identically on both peers.
func _test_hp_mult_scaling() -> void:
	var enc: Node = load(ENCOUNTER_PATH).new()
	_expect(int(enc._archetype_stats(0, 2.0)["hp"]) == 48, "chaser hp x2.0 should be 48")   # 24*2
	_expect(int(enc._archetype_stats(1, 1.5)["hp"]) == 105, "brute hp x1.5 should be 105")  # 70*1.5
	enc.free()
	_completes("hp_mult_scaling")


## build_enemy_from_data reconstructs a plain enemy with the exact passed stats +
## position (set pre-_ready so _apply_archetype_defaults leaves them).
func _test_build_enemy_from_data() -> void:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var data: Dictionary = {
		"boss": false, "arch": 1, "hp": 70, "spd": 62.0, "touch": 18,
		"tint": Color(0.7, 0.25, 0.45, 1), "tele": true, "x": 100.0, "y": 200.0,
	}
	var e: Node = enc.build_enemy_from_data(data)
	_expect(e != null, "build should return a node")
	if e != null:
		_expect(int(e.archetype) == 1, "archetype set")
		_expect(int(e.max_hp) == 70, "max_hp set")
		_expect(int(e.touch_damage) == 18, "touch set")
		_expect(bool(e.uses_telegraphed_attack), "telegraph flag set")
		_expect((e as Node2D).position == Vector2(100.0, 200.0), "position set from data")
		e.free()
	enc.free()
	_completes("build_enemy_from_data")


## The boss builds from data too (a different scene, stats set pre-_ready).
func _test_build_boss_from_data() -> void:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var data: Dictionary = {"boss": true, "hp": 832, "spd": 66.0, "touch": 26, "x": 500.0, "y": 300.0}
	var e: Node = enc.build_enemy_from_data(data)
	_expect(e != null, "boss build should return a node")
	if e != null:
		_expect(int(e.max_hp) == 832, "boss max_hp set")
		_expect(int(e.touch_damage) == 26, "boss touch set")
		_expect((e as Node2D).position == Vector2(500.0, 300.0), "boss position set")
		e.free()
	enc.free()
	_completes("build_boss_from_data")
