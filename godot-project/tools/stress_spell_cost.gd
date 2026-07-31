# Run: godot --headless --path godot-project --script tools/stress_spell_cost.gd
#   optional: ++entities=25 ++quality=low ++window=90 ++settle=45 ++cast_hz=4
#
# PER-SPELL ATTRIBUTION. `tools/stress_mobile_entities.gd ++casting=1` proved the
# frame is expensive once spells are actually cast (9.4 ms crowd-only -> ~32 ms
# with the roster cycling). It cannot say WHICH spell, and "the spells are slow"
# is not something you can act on.
#
# This casts ONE spell id at a time against the same 25-entity crowd, with a
# settle gap between ids so the previous spectacle is gone before the next is
# measured, and prints a table sorted by cost. That table is the target list.
#
# ⚠ SAME CAVEAT AS THE CROWD HARNESS. Dummy renderer, CPU only. A spell that is
# cheap here can still be the most expensive thing on the phone if it covers the
# screen in overdraw — this measures script/physics/node churn and nothing about
# fill rate.
#
# ⚠ AND A SECOND ONE, SPECIFIC TO THIS TOOL. The crowd is LIVE while measuring, so
# each spell's window also contains 25 enemies thinking and colliding. That is
# deliberate (a spell's real cost includes the targets it scans and the damage
# numbers and ailments it produces) but it means the numbers are cost-IN-CONTEXT,
# not cost-in-isolation. The BASELINE row is the same crowd with nothing cast, and
# the delta against it is the honest per-spell figure.
#
# Test-idiom note: a HARNESS, not an assertion suite — no pass/fail sentinels, it
# prints numbers for a human. `tools/slice_test_perf_budget.gd` is the suite that
# asserts against these.
extends SceneTree

const ROOM_WIDTH: float = 960.0

var _arena: SimArena = null
var _entities: int = 25
var _force_low: bool = false
## Frames spent measuring one spell id.
var _window: int = 90
## Frames of quiet between ids, so a 1.6 s Hollow Purple is not still on screen
## while the next spell is being timed.
var _settle: int = 60
var _cast_hz: float = 4.0

## HP the crowd is spawned with. Absurd ON PURPOSE — see `_spawn_crowd`.
const IMMORTAL_HP: int = 100000000

var _spells: Array = []
var _idx: int = 0
## Each spell is measured against a baseline taken IMMEDIATELY BEFORE IT, not
## against one global baseline at the top of the run. The first version of this
## tool used a single baseline and produced a table with NEGATIVE costs in it —
## spells that apparently made the frame cheaper. They had not: the crowd was
## being killed off as the sweep ran, so later spells were timed against fewer
## enemies than the baseline was. A drifting control is worse than no control,
## because it looks like data. Immortal HP fixes the cause; re-baselining catches
## whatever else drifts (ailments, decals, pool growth, dead spectacles).
var _measuring_spell: bool = false
var _phase_frames: int = 0
var _settling: bool = true
var _cast_accum: float = 0.0
var _spawn_delay: int = 2
var _spawned: bool = false
var _hero: Node = null
var _aim_i: int = 0

var _sum_ms: float = 0.0
var _n: int = 0
var _worst: float = 0.0
var _peak_nodes: int = 0
var _rows: Array[Dictionary] = []
var _baseline: float = 0.0
var _done: bool = false


func _initialize() -> void:
	_parse_args()
	if _force_low:
		var t: Node = root.get_node_or_null(^"/root/Tuning")
		if t != null and t.get(&"cfg") != null:
			t.cfg.set(&"graphics_quality", TuningConfig.Quality.LOW)
	print("[cost] entities=%d window=%d settle=%d cast_hz=%.1f quality=%s"
		% [_entities, _window, _settle, _cast_hz, "LOW(forced)" if _force_low else "auto"])
	_arena = SimArena.new()
	root.add_child(_arena)


func _physics_process(delta: float) -> bool:
	if _done:
		return true
	# Fighters spawn a frame AFTER the arena — a node added inside _initialize has
	# no _ready yet, so `@onready var rig` is null and configure_class throws. Same
	# trap, same fix, as tools/stress_mobile_entities.gd and tools/bot_sim.gd.
	if _spawn_delay > 0:
		_spawn_delay -= 1
		if _spawn_delay == 0:
			_spawn_crowd()
		return false
	if not _spawned:
		return false

	_phase_frames += 1
	if _settling:
		if _phase_frames >= _settle:
			_begin_measure()
		return false

	if _measuring_spell:
		_drive_casts(delta)
	var ms: float = (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		+ Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	_sum_ms += ms
	_worst = maxf(_worst, ms)
	_n += 1
	_peak_nodes = maxi(_peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	if _phase_frames >= _window:
		_close_row()
	return false


func _spawn_crowd() -> void:
	var half: float = ROOM_WIDTH * 0.5
	_hero = _arena.spawn_hero(0, -half * 0.5)
	for i: int in maxi(_entities - 1, 0):
		var x: float = -half + fmod(float(i) * 137.0, ROOM_WIDTH)
		# IMMORTAL, and this is the whole reason the table means anything. A normal
		# 90 HP enemy dies to the first spell measured, so by the twentieth id the
		# "25-entity crowd" is four survivors and a pile of corpses — every later
		# spell gets timed on an emptier stage than the earlier ones and the ranking
		# is an artefact of roster order. Huge HP keeps the population, the collision
		# density and the target-scan lengths constant for the whole sweep, which is
		# the only condition under which two rows are comparable.
		_arena.spawn_enemy(i % 4, x, IMMORTAL_HP)
	_spells = SpellLibrary.build_all()
	_spawned = true
	_settling = true
	_phase_frames = 0
	print("[cost] crowd up (%d entities, immortal), %d spells to sweep"
		% [_entities, _spells.size()])


func _begin_measure() -> void:
	_settling = false
	_phase_frames = 0
	_sum_ms = 0.0
	_worst = 0.0
	_n = 0
	_peak_nodes = 0


func _close_row() -> void:
	var avg: float = _sum_ms / maxf(float(_n), 1.0)
	if not _measuring_spell:
		# Control window for the spell about to be cast.
		_baseline = avg
		_measuring_spell = true
		_settling = true
		_phase_frames = 0
		return
	var s: SpellDef = _spells[_idx]
	_rows.append({
		"id": s.id, "kind": int(s.kind),
		"avg": avg, "delta": avg - _baseline, "base": _baseline,
		"worst": _worst, "nodes": _peak_nodes,
	})
	print("[cost]   %-22s base %6.2f  avg %6.2f  delta %+6.2f"
		% [s.id, _baseline, avg, avg - _baseline])
	_idx += 1
	_measuring_spell = false
	if _idx >= _spells.size():
		_report()
		_done = true
		quit(0)
		return
	_settling = true
	_phase_frames = 0


func _drive_casts(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	_cast_accum += delta
	var period: float = 1.0 / maxf(_cast_hz, 0.01)
	while _cast_accum >= period:
		_cast_accum -= period
		_aim_i += 1
		var half: float = ROOM_WIDTH * 0.5
		var tx: float = -half + fmod(float(_aim_i) * 211.0, ROOM_WIDTH)
		SpellCaster.cast(_spells[_idx], _arena, (_hero as Node2D).global_position,
			Vector2(tx, SimArena.FLOOR_Y - 50.0), Color(0.6, 0.8, 1.0),
			_spells[_idx].effect, _hero, &"mortal")


func _report() -> void:
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["delta"]) > float(b["delta"]))
	print("[cost] ==================================================")
	print("[cost] %-22s %7s %8s %8s %8s %7s"
		% ["spell", "base", "avg ms", "delta", "worst", "nodes"])
	for r: Dictionary in _rows:
		print("[cost] %-22s %7.2f %8.2f %8.2f %8.2f %7d"
			% [r["id"], r["base"], r["avg"], r["delta"], r["worst"], r["nodes"]])
	print("[cost] ==================================================")
	print("[cost] `delta` is the spell's own cost above the live crowd. Sorted by it.")
	print("[cost] REMINDER: dummy renderer — CPU only, no fill rate in these numbers.")


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_user_args())
	argv.append_array(OS.get_cmdline_args())
	for raw: String in argv:
		var a: String = raw.lstrip("+-")
		if not a.contains("="):
			continue
		var k: String = a.get_slice("=", 0)
		var v: String = a.get_slice("=", 1)
		match k:
			"entities":
				_entities = clampi(int(v), 1, 200)
			"window":
				_window = clampi(int(v), 10, 600)
			"settle":
				_settle = clampi(int(v), 5, 600)
			"cast_hz":
				_cast_hz = clampf(float(v), 0.1, 60.0)
			"quality":
				_force_low = v.to_lower() == "low"
