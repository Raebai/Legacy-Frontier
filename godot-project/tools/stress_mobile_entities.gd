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
## Casts per second when `++casting=1`. 4 Hz keeps roughly 4-8 spectacles alive at
## once given typical spell lifetimes (0.3-1.6 s) — i.e. it sits ON the spec's
## 8-active-VFX ceiling rather than politely under it, which is the only rate that
## tells us anything about the ceiling.
const DEFAULT_CAST_HZ: float = 4.0

var _arena: SimArena = null
var _entities: int = DEFAULT_ENTITIES
var _seconds: float = DEFAULT_SECONDS
var _force_low: bool = false
## Cast real spells from the crowd. OFF by default so the historical baseline in
## docs/mobile-export.md stays reproducible with the same command line.
var _casting: bool = false
var _cast_hz: float = DEFAULT_CAST_HZ
## Ablation switch — see `_apply_ablation`. Measurement only; never a shipping path.
var _ablate: String = ""
## Cast ONE spell id over and over instead of cycling the roster. This is the
## attribution mode: the mixed roster tells you the frame is expensive, and only
## a per-spell sweep tells you WHICH spell to go and look at.
var _only_spell: String = ""
var _seed: int = 20260731
## Keep the crowd alive for the whole run. Without it the spells kill the crowd,
## the population halves halfway through, and the second half of the measurement is
## a different experiment from the first — which is most of why two runs of the same
## command used to disagree.
var _immortal: bool = false
var _hero: Node = null
var _spells: Array = []
var _spell_i: int = 0
var _cast_accum: float = 0.0
var _casts: int = 0
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
## Peak concurrent spell spectacles seen during the measured window — the number
## the spec's 8-active-VFX ceiling is about. Counted the same way the shipping
## census counts, so the harness and the cap cannot disagree.
var _peak_spectacles: int = 0
var _peak_nodes: int = 0


## Enemy HP when `++immortal=1`. See `_spawn_crowd`.
const IMMORTAL_HP: int = 100000000


func _initialize() -> void:
	_parse_args()
	# DETERMINISM, and it is not optional for a tool that exists to compare two
	# builds. Spells are full of `randf()` — spread arcs, debris jitter, crack
	# geometry, meteor scatter — all drawn from the GLOBAL RNG, so two runs of the
	# same command took different paths through the frame and the harness reported a
	# +-40% spread. A 15% improvement is invisible inside that, which means an
	# unseeded run cannot answer the only question this tool is for.
	seed(_seed)
	print("[stress] entities=%d seconds=%.1f quality=%s casting=%s seed=%d%s%s"
		% [_entities, _seconds, "LOW(forced)" if _force_low else "auto",
			("%.1fHz" % _cast_hz) if _casting else "off", _seed,
			" immortal" if _immortal else "",
			("" if _ablate == "" else " ABLATE=" + _ablate)])
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
			_force_quality()
			_spawn_crowd()
		return false
	if not _spawned:
		return false
	if _warm < WARMUP_FRAMES:
		_warm += 1
	else:
		_phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		_proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_peak_nodes = maxi(_peak_nodes,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_frames += 1
	# Keep the pools genuinely exercised: a crowd that never takes a hit never
	# spawns a damage number, and the pooling work would go unmeasured.
	if _frames % 3 == 0:
		_churn()
	if _casting:
		_drive_casts(delta)
	if float(_frames) * delta >= _seconds:
		_report()
		_done = true
		quit(0)
	return false


## Force the cheap picture, exercising the mobile branches (thinned motes, no
## screen-reading shaders, the tighter VFX budget) on a desktop run.
##
## ⚠ THIS RUNS FROM `_physics_process`, NOT `_initialize`, AND THAT IS A BUG FIX.
## It used to sit in `_initialize`, where the SceneTree root is not yet the active
## tree — so `get_node_or_null("/root/Tuning")` printed "Can't use get_node() with
## absolute paths from outside the active scene tree", returned null, and the
## function quietly did nothing. `++quality=low` therefore never once forced LOW,
## and every "LOW" figure this harness has ever printed was a HIGH run wearing a
## LOW label. Silent because the null was handled gracefully — the guard that was
## supposed to make it safe under `--script` is what hid the failure.
func _force_quality() -> void:
	if not _force_low:
		return
	var t: Node = root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		print("[stress] ⚠ could not reach the Tuning autoload — LOW NOT APPLIED")
		return
	t.cfg.set(&"graphics_quality", TuningConfig.Quality.LOW)
	print("[stress] quality forced LOW (quality_is_low=%s)" % TuningConfig.quality_is_low())


func _spawn_crowd() -> void:
	# One hero (the player's body, the most expensive single entity — full rig,
	# spell caster, camera) plus enemies to the ceiling.
	var half: float = ROOM_WIDTH * 0.5
	_arena.spawn_hero(0, -half * 0.5)
	var foes: int = maxi(_entities - 1, 0)
	for i: int in foes:
		var x: float = -half + fmod(float(i) * 137.0, ROOM_WIDTH)
		if _immortal:
			_arena.spawn_enemy(ARCHETYPES[i % ARCHETYPES.size()], x, IMMORTAL_HP)
		else:
			_arena.spawn_enemy(ARCHETYPES[i % ARCHETYPES.size()], x)
	_spawned = true
	print("[stress] spawned %d entities (live count reports %d)"
		% [_entities, PerfOverlay.live_entity_count()])
	if _casting:
		_arm_casting()
	_apply_ablation()


# --------------------------------------------------------------------- casting
## THE REASON THIS HARNESS WAS EXTENDED. The original measured a CROWD: 25 bodies
## walking, colliding and thinking. It never cast a single spell, so every system
## added since — the magic-circle sigil that now opens on all 22 spells, the
## spell-vs-spell reaction sweep, the impact-frame arbiter, the particle bursts,
## the element ailments, the damage numbers those produce — contributed exactly
## nothing to the number in docs/mobile-export.md.
##
## That number was therefore a floor, not a ceiling, and it was being read as a
## ceiling. Casting is what makes it honest.
func _arm_casting() -> void:
	_hero = _arena.get_node_or_null(^"Hero") as Node
	for c: Node in _arena.get_children():
		if c is CharacterBody2D and c.is_in_group(&"hero"):
			_hero = c
			break
	# Every spell in the game, cycled, so no single cheap kind flatters the run.
	# `build_all` is the full roster including the Tier 2 / Tier 3 drop spells.
	_spells = SpellLibrary.build_all()
	if _only_spell != "":
		var one: Array = []
		for s: SpellDef in _spells:
			if s.id == _only_spell:
				one.append(s)
		if one.is_empty():
			print("[stress] no spell with id '%s' — casting the full roster" % _only_spell)
		else:
			_spells = one
	print("[stress] casting armed: %d spells%s, %.1f Hz, caster=%s"
		% [_spells.size(), "" if _only_spell == "" else " (only '%s')" % _only_spell,
			_cast_hz, "hero" if _hero != null else "NONE"])


func _drive_casts(delta: float) -> void:
	if _spells.is_empty() or _hero == null or not is_instance_valid(_hero):
		return
	_cast_accum += delta
	var period: float = 1.0 / maxf(_cast_hz, 0.01)
	while _cast_accum >= period:
		_cast_accum -= period
		var spell: SpellDef = _spells[_spell_i % _spells.size()]
		_spell_i += 1
		# Aim across the room, cycling so shots land in different places and the
		# reaction sweep sees genuinely crossing pairs rather than a stacked column.
		var half: float = ROOM_WIDTH * 0.5
		var tx: float = -half + fmod(float(_spell_i) * 211.0, ROOM_WIDTH)
		var origin: Vector2 = (_hero as Node2D).global_position
		SpellCaster.cast(spell, _arena, origin,
			Vector2(tx, SimArena.FLOOR_Y - 50.0), Color(0.6, 0.8, 1.0),
			spell.effect, _hero, &"mortal")
		_casts += 1
	_peak_spectacles = maxi(_peak_spectacles, _count_spectacles())


## Live spell spectacles under the arena. Counted by the property `SpellCaster`
## stamps onto every one of its 21 dispatch arms — `get()` on a property a node
## has not declared returns null, so this is exactly "a node built by the spell
## dispatcher" and nothing else.
func _count_spectacles() -> int:
	var n: int = 0
	for c: Node in _arena.get_children():
		if c.get(&"spell_tier") != null and c.get(&"caster_node") != null:
			n += 1
	return n


# ------------------------------------------------------------------- ablation
## MEASUREMENT ONLY — never a shipping path, and every mode here changes FEEL.
## The point is to answer "where does the frame actually go" by subtraction,
## because GDScript has no sampling profiler under `--script` and optimising from
## reasoning is how you spend a day making something 2% faster.
func _apply_ablation() -> void:
	match _ablate:
		"":
			return
		"rig":
			# Stop the character rigs ticking. Isolates the two body springs +
			# limb sim + gait across the whole crowd. The figures freeze mid-pose;
			# this tells us the rig's share of the frame and NOTHING about feel.
			var n: int = 0
			for body: Node in _arena.get_children():
				var rig: Node = body.get(&"rig") as Node
				if rig != null and is_instance_valid(rig):
					rig.set_physics_process(false)
					n += 1
			print("[stress] ABLATED rig: %d rigs stopped ticking" % n)
		"reactor":
			# Stop the 30 Hz spell-vs-spell pair sweep.
			var r: Node = root.get_node_or_null(^"/root/SpellReactor")
			if r != null:
				r.set_process(false)
				print("[stress] ABLATED reactor: pair sweep off")
		"ai":
			# Stop enemy brains. Isolates archetype AI + steering from physics.
			var n2: int = 0
			for body: Node in _arena.get_children():
				if body is CharacterBody2D and body.is_in_group(&"enemy"):
					body.set_physics_process(false)
					n2 += 1
			print("[stress] ABLATED ai: %d enemies stopped ticking" % n2)
		_:
			print("[stress] unknown ablation '%s' — running unmodified" % _ablate)


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
	print("[stress] nodes         %d (peak %d)"
		% [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), _peak_nodes])
	print("[stress] 2d bodies     %d" % int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)))
	if _casting:
		print("[stress] casts         %d  |  PEAK LIVE SPECTACLES %d  (budget %d)"
			% [_casts, _peak_spectacles, _vfx_budget()])
		print("[stress] reactor       tracked %d (MAX_LIVE %d)  reactions fired %d"
			% [_reactor_live(), SpellReactorNode.MAX_LIVE, _reactor_fired()])
	# THE PRIMARY RESULT. Deterministic for a given seed, and therefore the only
	# numbers here that can be compared between two runs on a machine somebody else
	# is also using. `granted` below `requested` is the VFX budget doing its job.
	# Guarded rather than called straight, so this harness still runs against a
	# build WITHOUT the budget in it. That is not defensiveness for its own sake:
	# the only honest before/after is the same measuring tool on both sides, and a
	# hard reference to `work_stats` would make the tool refuse to measure the
	# "before" it exists to compare against.
	_print_work("particles", CombatVfx, "requested", "granted", false)
	_print_work("debris", DebrisChunk, "requested", "granted", false)
	# Decals are skip-or-spawn, so the two keys SUM to the demand rather than the
	# second being a reduced form of the first.
	_print_work("decals", ScorchDecal, "spawned", "skipped", true)
	_print_work("elementfx", ElementFx, "requested", "granted", false)
	if _ablate != "":
		print("[stress] ⚠ ABLATED '%s' — this is a MEASUREMENT run, not a build" % _ablate)
	print("[stress] --------------------------------------------------")
	print("[stress] REMINDER: dummy renderer. This is CPU only — the GPU cost")
	print("[stress] that decides the phone's frame rate is not in these numbers.")


## One WORK line, or a note that this build has no counter to read.
static func _print_work(label: String, cls: Object, a: String, b: String,
		keys_sum: bool) -> void:
	if cls == null or not cls.has_method(&"work_stats"):
		print("[stress] WORK %-10s (not instrumented in this build)" % label)
		return
	var s: Dictionary = cls.call(&"work_stats")
	var av: int = int(s[a])
	var bv: int = int(s[b])
	var demand: int = (av + bv) if keys_sum else av
	var done: int = av if keys_sum else bv
	print("[stress] WORK %-10s %s %d, %s %d  (%.0f%% of demand cut)"
		% [label, a, av, b, bv, _cut_pct(demand, done)])


static func _cut_pct(requested: int, granted: int) -> float:
	if requested <= 0:
		return 0.0
	return 100.0 * (1.0 - float(granted) / float(requested))


func _vfx_budget() -> int:
	var r: Node = root.get_node_or_null(^"/root/SpellReactor")
	return 0 if r == null else int(r.call(&"vfx_budget"))


func _reactor_live() -> int:
	var r: Node = root.get_node_or_null(^"/root/SpellReactor")
	return 0 if r == null else int(r.call(&"live_count"))


func _reactor_fired() -> int:
	var r: Node = root.get_node_or_null(^"/root/SpellReactor")
	return 0 if r == null else int(r.get(&"fired_count"))


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
			"casting":
				_casting = v != "0" and v.to_lower() != "false"
			"cast_hz":
				_cast_hz = clampf(float(v), 0.1, 60.0)
			"ablate":
				_ablate = v.to_lower()
			"spell":
				_only_spell = v
			"seed":
				_seed = int(v)
			"immortal":
				_immortal = v != "0" and v.to_lower() != "false"
