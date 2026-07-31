# Run: godot --headless --path godot-project --script tools/stress_mobile_entities.gd
#   optional: ++entities=25 ++seconds=20 ++quality=low
#
# Phase 6.8. Spawns the spec's 25-entity ceiling on the shared `SimArena` stage
# and reports frame timing, so "does the ceiling cost what we think it costs" has
# a number instead of an opinion.
#
# ⚠ READ THIS BEFORE BELIEVING THE OUTPUT. Headless runs the DUMMY renderer.
# Every number below is CPU: script, AI, physics, spell logic, node churn. The
# GPU cost — which on a tile-based mobile GPU is the thing that actually decides
# whether this game holds 30 fps — is NOT measured here and CANNOT be measured
# here. This harness answers "did we write an algorithm that falls over at 25
# entities", and that is all it answers. The renderer question is answered by the
# in-game overlay (PerfOverlay, F3 / three-finger tap) on a real device, and
# nothing else substitutes for it.
#
# What it is good for, concretely: catching an O(n^2) that only shows up in a
# crowd. Pass ++entities=8 and ++entities=25 and compare — if per-frame cost more
# than triples for a 3x entity count, something in the frame scales worse than
# linearly and the crowd is what will find it on the phone.
#
# Test-idiom note: this is a HARNESS, not an assertion suite, so it has no
# pass/fail sentinels. It always exits 0 unless it could not build the stage; the
# numbers are for a human to read. `tools/slice_test_mobile_config.gd` is the
# suite with assertions.
extends SceneTree

const DEFAULT_ENTITIES: int = 25
const DEFAULT_SECONDS: float = 15.0
## Frames discarded before measurement starts. The first frames after a spawn
## burst are dominated by _ready(), rig construction and shader/material
## first-use, none of which recur — averaging them in would flatter a steady
## state that has not begun yet.
const WARMUP_FRAMES: int = 60
## Enemy archetypes cycled through, so the crowd is a MIX. A field of 25 of the
## same archetype measures one code path 25 times; the mix is what the floor
## actually spawns.
const ARCHETYPES: Array[int] = [0, 1, 2, 3]
## Spawn spread, matched to the REAL arena width rather than SimArena's 1800px
## test floor. DENSITY is the thing that scales here — the 2D broadphase pairs
## bodies by proximity, and 25 fighters packed into 960px collide with each other
## far more than 25 strung across 1800px would. Measuring the loose version would
## flatter the crowd the game actually builds.
const ROOM_WIDTH: float = 960.0

var _arena: SimArena = null
var _entities: int = DEFAULT_ENTITIES
var _seconds: float = DEFAULT_SECONDS
var _force_low: bool = false
var _spawn_delay: int = 2
var _spawned: bool = false
var _frames: int = 0
var _warm: int = 0
## ⚠ NOT wall-clock between ticks. The first version of this harness timed
## `Time.get_ticks_usec()` across physics frames and reported a rock-solid
## 16.67 ms average — which is 1/60 exactly, i.e. it was measuring the engine's
## frame PACING (the sleep between ticks), not the work. Godot's own counters
## report time actually spent inside the process/physics callbacks and are
## immune to that. Keep it this way.
var _phys_ms: PackedFloat64Array = PackedFloat64Array()
var _proc_ms: PackedFloat64Array = PackedFloat64Array()
var _done: bool = false


func _initialize() -> void:
	_parse_args()
	print("[stress] entities=%d seconds=%.1f quality=%s"
		% [_entities, _seconds, "LOW(forced)" if _force_low else "auto"])
	if _force_low:
		# Exercises the mobile code paths (thinned motes, no screen-reading
		# shaders) on a desktop run. Cosmetic under the dummy renderer, but it
		# also flips the branches those decisions live in, so a crash in the LOW
		# path shows up here rather than on the phone.
		var t: Node = root.get_node_or_null(^"/root/Tuning")
		if t != null and t.get(&"cfg") != null:
			t.cfg.set(&"graphics_quality", TuningConfig.Quality.LOW)
	_arena = SimArena.new()
	root.add_child(_arena)


func _physics_process(delta: float) -> bool:
	if _done:
		return true
	# ⚠ FIGHTERS SPAWN A FRAME AFTER THE ARENA, never in the same call. A node
	# added while the SceneTree is still inside `_initialize` does not get its
	# `_ready` synchronously, so `@onready var rig` is still null and
	# `configure_class` throws. Same trap, same fix, as tools/bot_sim.gd.
	if _spawn_delay > 0:
		_spawn_delay -= 1
		if _spawn_delay == 0:
			_spawn_crowd()
		return false
	if not _spawned:
		return false
	if _warm < WARMUP_FRAMES:
		_warm += 1
	else:
		_phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		_proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_frames += 1
	# Keep the pools genuinely exercised: a crowd that never takes a hit never
	# spawns a damage number, and the pooling work would go unmeasured.
	if _frames % 3 == 0:
		_churn()
	if float(_frames) * delta >= _seconds:
		_report()
		_done = true
		quit(0)
	return false


func _spawn_crowd() -> void:
	# One hero (the player's body, the most expensive single entity — full rig,
	# spell caster, camera) plus enemies to the ceiling.
	var half: float = ROOM_WIDTH * 0.5
	_arena.spawn_hero(0, -half * 0.5)
	var foes: int = maxi(_entities - 1, 0)
	for i: int in foes:
		var x: float = -half + fmod(float(i) * 137.0, ROOM_WIDTH)
		_arena.spawn_enemy(ARCHETYPES[i % ARCHETYPES.size()], x)
	_spawned = true
	print("[stress] spawned %d entities (live count reports %d)"
		% [_entities, PerfOverlay.live_entity_count()])


## Drive the two pools at a combat-plausible rate so their cost is inside the
## measurement rather than beside it.
func _churn() -> void:
	if _arena == null or not _arena.is_inside_tree():
		return
	var half: float = ROOM_WIDTH * 0.5
	DamageNumber.spawn(_arena, Vector2(randf_range(-half, half),
		SimArena.FLOOR_Y - 60.0), randi_range(4, 30), Color(1, 0.8, 0.4))
	CombatVfx.spawn_burst(_arena, Vector2(randf_range(-half, half),
		SimArena.FLOOR_Y - 60.0), Color(1, 0.7, 0.3, 1), Color(1, 0.3, 0.1, 0), 20, 0.35)


## avg / p50 / p95 / worst for a sample set, in ms.
func _stats(samples: PackedFloat64Array) -> Dictionary:
	var sorted: Array = Array(samples)
	sorted.sort()
	var total: float = 0.0
	for v: float in sorted:
		total += v
	var n: int = sorted.size()
	return {
		"n": n,
		"avg": total / float(n),
		"p50": sorted[n / 2],
		# p95, not the mean, is the number that decides whether the game FEELS
		# smooth: a mean hides the one frame in twenty that stutters.
		"p95": sorted[mini(int(float(n) * 0.95), n - 1)],
		"worst": sorted[n - 1],
	}


func _report() -> void:
	if _phys_ms.is_empty():
		print("[stress] no samples — the run was shorter than the warm-up")
		return
	var ph: Dictionary = _stats(_phys_ms)
	var pr: Dictionary = _stats(_proc_ms)
	print("[stress] --------------------------------------------------")
	print("[stress] entities   %d   frames sampled %d" % [_entities, ph["n"]])
	print("[stress] physics ms   avg %.2f  p50 %.2f  p95 %.2f  worst %.2f"
		% [ph["avg"], ph["p50"], ph["p95"], ph["worst"]])
	print("[stress] process ms   avg %.2f  p50 %.2f  p95 %.2f  worst %.2f"
		% [pr["avg"], pr["p50"], pr["p95"], pr["worst"]])
	print("[stress] cpu total    avg %.2f ms  (budget: 33.3 at 30fps, 16.7 at 60)"
		% (ph["avg"] + pr["avg"]))
	print("[stress] per entity   avg %.3f ms" % ((ph["avg"] + pr["avg"]) / maxf(float(_entities), 1.0)))
	print("[stress] pools         dmg alive %d pooled %d | vfx pooled %d"
		% [DamageNumber.alive_count(), DamageNumber.pooled_count(),
			CombatVfx.pooled_count()])
	print("[stress] nodes         %d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	print("[stress] 2d bodies     %d" % int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)))
	print("[stress] --------------------------------------------------")
	print("[stress] REMINDER: dummy renderer. This is CPU only — the GPU cost")
	print("[stress] that decides the phone's frame rate is not in these numbers.")


func _parse_args() -> void:
	# Godot hands user arguments back through two different calls depending on
	# whether they were separated by `--` or `++`; scanning both means the caller
	# does not have to remember which. Copied from tools/bot_sim.gd deliberately —
	# one arg convention across the harnesses.
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
			"seconds":
				_seconds = clampf(float(v), 1.0, 300.0)
			"quality":
				_force_low = v.to_lower() == "low"
