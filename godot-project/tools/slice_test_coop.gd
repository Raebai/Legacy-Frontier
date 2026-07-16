# Run: godot --headless --path godot-project --script tools/slice_test_coop.gd
# Co-op host-authoritative enemies. The load-bearing correctness property is that
# the host + every client build BYTE-IDENTICAL enemies from the same replicated
# spawn data — which requires Encounter's stat table to agree with Enemy's, and
# build_enemy_from_data to construct the right node. Both are pure construction
# (no tree, no autoloads, no networking), so they test headlessly here.
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_stat_tables_agree()
	failed += _test_hp_mult_scaling()
	failed += _test_build_enemy_from_data()
	failed += _test_build_boss_from_data()
	if failed > 0:
		printerr("Coop tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Coop tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## Every archetype's Encounter stats must match Enemy.ARCHETYPE_DEFAULTS, or the host
## and a client would spawn differently-statted enemies from the same data.
func _test_stat_tables_agree() -> int:
	var f: int = 0
	var enc: Node = load(ENCOUNTER_PATH).new()
	var defaults: Dictionary = load(ENEMY_PATH).ARCHETYPE_DEFAULTS
	for kind: int in range(8):
		var s: Dictionary = enc._archetype_stats(kind, 1.0)
		var d: Dictionary = defaults[kind]
		f += _expect(int(s["hp"]) == int(d["hp"]), "hp mismatch archetype %d" % kind)
		f += _expect(float(s["spd"]) == float(d["speed"]), "speed mismatch archetype %d" % kind)
		f += _expect(int(s["touch"]) == int(d["touch"]), "touch mismatch archetype %d" % kind)
		f += _expect(s["tint"] == d["tint"], "tint mismatch archetype %d" % kind)
	# BRUTE (1) is the only telegraphed archetype.
	f += _expect(bool(enc._archetype_stats(1, 1.0)["tele"]), "brute should telegraph")
	f += _expect(not bool(enc._archetype_stats(0, 1.0)["tele"]), "chaser should not telegraph")
	enc.free()
	return f


## hp_mult scales hp (the floor-difficulty knob) identically on both peers.
func _test_hp_mult_scaling() -> int:
	var f: int = 0
	var enc: Node = load(ENCOUNTER_PATH).new()
	f += _expect(int(enc._archetype_stats(0, 2.0)["hp"]) == 48, "chaser hp x2.0 should be 48")   # 24*2
	f += _expect(int(enc._archetype_stats(1, 1.5)["hp"]) == 105, "brute hp x1.5 should be 105")  # 70*1.5
	enc.free()
	return f


## build_enemy_from_data reconstructs a plain enemy with the exact passed stats +
## position (set pre-_ready so _apply_archetype_defaults leaves them).
func _test_build_enemy_from_data() -> int:
	var f: int = 0
	var enc: Node = load(ENCOUNTER_PATH).new()
	var data: Dictionary = {
		"boss": false, "arch": 1, "hp": 70, "spd": 62.0, "touch": 18,
		"tint": Color(0.7, 0.25, 0.45, 1), "tele": true, "x": 100.0, "y": 200.0,
	}
	var e: Node = enc.build_enemy_from_data(data)
	f += _expect(e != null, "build should return a node")
	if e != null:
		f += _expect(int(e.archetype) == 1, "archetype set")
		f += _expect(int(e.max_hp) == 70, "max_hp set")
		f += _expect(int(e.touch_damage) == 18, "touch set")
		f += _expect(bool(e.uses_telegraphed_attack), "telegraph flag set")
		f += _expect((e as Node2D).position == Vector2(100.0, 200.0), "position set from data")
		e.free()
	enc.free()
	return f


## The boss builds from data too (a different scene, stats set pre-_ready).
func _test_build_boss_from_data() -> int:
	var f: int = 0
	var enc: Node = load(ENCOUNTER_PATH).new()
	var data: Dictionary = {"boss": true, "hp": 832, "spd": 66.0, "touch": 26, "x": 500.0, "y": 300.0}
	var e: Node = enc.build_enemy_from_data(data)
	f += _expect(e != null, "boss build should return a node")
	if e != null:
		f += _expect(int(e.max_hp) == 832, "boss max_hp set")
		f += _expect(int(e.touch_damage) == 26, "boss touch set")
		f += _expect((e as Node2D).position == Vector2(500.0, 300.0), "boss position set")
		e.free()
	enc.free()
	return f
