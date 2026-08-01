# Run: godot --headless --path godot-project --script tools/profile_spectacles.gd
#   optional: ++copies=24 ++iters=400 ++quality=low ++spell=fireball ++crowd=8
#
# PER-SPECTACLE ATTRIBUTION. `tools/stress_mobile_entities.gd ++casting=1` proved
# the frame is expensive once spells are actually cast (~8.7 ms crowd-only ->
# ~32 ms at the 8-effect ceiling). It cannot say WHICH spectacle or WHICH HALF of
# one, and "the spells are slow" is not something anybody can act on.
#
# ── WHY THIS DOES NOT MEASURE FRAMES ──────────────────────────────────────────
# The obvious tool — cast spell X, time the frame, subtract a control — was built
# first and thrown away. Wall-clock on this machine is only good to about +-30%
# (two identical seeded runs timed 33 ms and 57 ms), and a whole-frame delta of a
# few hundred microseconds sits far inside that. It produced a table with -50 ms
# entries in it: spells that apparently made the frame half a frame cheaper.
#
# So this times the SPECTACLE'S OWN CALLBACKS instead, in tight loops:
#
#   CAST   µs to run `SpellCaster.cast()` once — construction, node building,
#          sigil, audio, the initial scan. Paid once per cast.
#   PROC   µs for ONE `_process`/`_physics_process` call, averaged over thousands.
#          The node is frozen (`set_process(false)`) and driven by hand with a
#          near-zero delta, so every iteration does IDENTICAL work from an
#          IDENTICAL state. That is what makes it repeatable where a frame delta
#          is not — and it deliberately measures the per-frame FLOOR, not the
#          timer-gated bursts, because the floor is what 8 concurrent effects
#          multiply by 60.
#   DRAW   µs for one `_draw()`. Measured across the real frame (a `_draw` cannot
#          be invoked by hand — `draw_*` outside the draw pass errors), by
#          redrawing `copies` frozen instances every frame and differencing
#          against the same instances not redrawing. Divided by the count, so the
#          signal is `copies`x the noise floor.
#
# ⚠ `_draw()` DOES run under `--headless` — verified, 21 draws in 21 frames — and
# lands inside `Performance.TIME_PROCESS`. What headless CANNOT see is the GPU:
# these numbers are the cost of BUILDING the draw commands, not of rasterising
# them. A cheap spectacle here can still be the most expensive thing on a tile GPU
# if it covers the screen. Only a device answers that.
#
# Test-idiom note: a HARNESS, not an assertion suite — no pass/fail sentinels, it
# prints a table for a human. `tools/slice_test_perf_budget.gd` is the suite.
extends SceneTree

const ROOM_WIDTH: float = 960.0
## Absurd on purpose: a crowd that dies mid-sweep makes later rows cheaper than
## earlier ones for reasons that have nothing to do with the spell.
const IMMORTAL_HP: int = 100000000
## Delta fed to the hand-driven `_process` calls. Small enough that thousands of
## iterations advance the spectacle by a fraction of one real frame (so the state
## — and therefore the work — is constant), but NOT zero: a few scripts divide by
## delta, and one that did would return `inf` rather than error, silently changing
## which branch is being timed.
const TINY_DT: float = 0.000001

var _arena: SimArena = null
var _hero: Node = null
var _spells: Array = []

var _copies: int = 24
var _iters: int = 400
var _crowd: int = 8
var _draw_frames: int = 40
## Frames the cohort runs NORMALLY before it is frozen and measured.
##
## NOT optional, and the first version of this tool did not have it: several
## spectacles open in a state where `_process` is a one-line early return (a beam
## sits at `_elapsed < 0` through its windup, and `_draw` returns with it), so
## measuring on the frame after the cast reported the cost of the WINDUP and
## printed 0.00 for half the roster. 12 frames is ~0.2 s — past every windup in
## the roster, short of the shortest lifetime.
var _warm: int = 12
var _force_low: bool = false
var _only: String = ""

enum Phase { IDLE, SPAWN, WARM, DRAW_AB, FINISH }
var _phase: int = Phase.IDLE
var _phase_frames: int = 0
var _spawn_delay: int = 2
var _spawned: bool = false
var _idx: int = 0
var _done: bool = false

var _nodes: Array[Node] = []
var _before: Dictionary = {}
var _cast_us: float = 0.0
var _proc_us: float = 0.0
## Ticking nodes per cast — a meteor is one spectacle and nine falling rocks.
var _ticking: float = 0.0
var _quiet_ms: float = 0.0
var _active_ms: float = 0.0
var _act: Array[float] = []
var _qui: Array[float] = []
var _prev_active: bool = false
var _last_us: int = 0
var _rows: Array[Dictionary] = []
## One bucket per SCRIPT among the nodes a cast produced. A/B'd one at a time.
var _groups: Array[Dictionary] = []
var _gi: int = 0
## script name -> {draw: total µs, casts: how many spells contributed}
var _by_script: Dictionary = {}


func _initialize() -> void:
	_parse_args()
	seed(20260801)
	print("[prof] copies=%d iters=%d crowd=%d quality=%s%s"
		% [_copies, _iters, _crowd, "LOW(forced)" if _force_low else "auto",
			"" if _only == "" else (" only=" + _only)])
	_arena = SimArena.new()
	root.add_child(_arena)


## ⚠ DRIVEN FROM `_process` (IDLE), NOT `_physics_process`, AND THAT IS LOAD-BEARING.
## `Performance.TIME_PROCESS` is an IDLE-frame counter and `_draw` runs in the idle
## step. Alternating redraw-on / redraw-off across PHYSICS ticks aliased against the
## idle frames they were meant to be measuring — two physics ticks can land inside
## one idle frame — and every single draw column came back 0.00 because the "quiet"
## and "active" samples were reading the same frames.
func _process(_delta: float) -> bool:
	if _done:
		return true
	# Fighters spawn a frame AFTER the arena: a node added inside `_initialize`
	# has not had `_ready` yet, so `@onready var rig` is null and configure_class
	# throws. Same trap, same fix, as the other harnesses.
	if _spawn_delay > 0:
		_spawn_delay -= 1
		if _spawn_delay == 0:
			_force_quality()
			_spawn_crowd()
		return false
	if not _spawned:
		return false

	_phase_frames += 1
	match _phase:
		Phase.SPAWN:
			_do_spawn()
		Phase.WARM:
			if _phase_frames >= _warm:
				_freeze()
				_time_process()
				_enter(Phase.DRAW_AB)
		Phase.DRAW_AB:
			_draw_ab()
	return false


## ⚠ MUST RUN FROM `_physics_process`, NOT `_initialize`. Inside `_initialize` the
## SceneTree root is not yet the active tree, so an absolute `get_node_or_null`
## returns null with a console warning and "force LOW" silently does nothing —
## the exact bug that made every historical LOW figure a mislabelled HIGH run.
func _force_quality() -> void:
	if not _force_low:
		return
	var t: Node = root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		print("[prof] ⚠ could not reach Tuning — LOW NOT APPLIED")
		return
	t.cfg.set(&"graphics_quality", TuningConfig.Quality.LOW)
	print("[prof] quality forced LOW (quality_is_low=%s)" % TuningConfig.quality_is_low())


func _spawn_crowd() -> void:
	var half: float = ROOM_WIDTH * 0.5
	_hero = _arena.spawn_hero(0, -half * 0.5)
	for i: int in maxi(_crowd, 0):
		_arena.spawn_enemy(i % 4, -half + fmod(float(i) * 137.0, ROOM_WIDTH), IMMORTAL_HP)
	_spells = SpellLibrary.build_all()
	if _only != "":
		var one: Array = []
		for s: SpellDef in _spells:
			if s.id.contains(_only):
				one.append(s)
		if one.is_empty():
			print("[prof] no spell id contains '%s' — sweeping the full roster" % _only)
		else:
			_spells = one
	_spawned = true
	print("[prof] crowd up (%d + hero), %d spells" % [_crowd, _spells.size()])
	_enter(Phase.SPAWN)


func _enter(p: int) -> void:
	_phase = p
	_phase_frames = 0
	_act.clear()
	_qui.clear()
	_prev_active = false
	_last_us = Time.get_ticks_usec()


## ⚠ WALL-CLOCK BETWEEN IDLE FRAMES, AND IT HAS TO BE — THIS IS THE HEADLINE
## FINDING OF THIS TOOL.
##
## `Performance.TIME_PROCESS` DOES NOT INCLUDE `_draw`. Measured, not assumed: a
## probe with 200 nodes each issuing 200 `draw_line` calls — 40,000 draw primitives
## per frame, confirmed running by a counter inside `_draw` — moved TIME_PROCESS by
## **0.0000 ms**, while the wall-clock between the same two frames moved by
## **9.2 ms**. Godot's process counter closes before the canvas draw pass.
##
## The consequence is much bigger than this tool: EVERY NUMBER IN
## `docs/mobile-export.md` IS PROCESS+PHYSICS, so the entire `_draw` cost of all 32
## spell spectacles — which is where their time actually goes — was never in the
## ~30 ms at the 8-effect ceiling. It is on top of it.
##
## The obvious objection to wall-clock is the one already recorded in that doc: an
## early harness timed between frames and confidently reported 16.67 ms, i.e. it was
## measuring frame PACING, not work. That trap is real for a whole-frame average and
## is disarmed here by construction — this is a DIFFERENCE between two interleaved
## populations of frames in the same run, so anything constant (pacing, physics, the
## crowd, the machine) is in both sides and subtracts out. The probe above is the
## proof it has signal: 2.3 ms quiet vs 11.5 ms redrawing.
func _sample() -> float:
	var now: int = Time.get_ticks_usec()
	var v: float = float(now - _last_us) / 1000.0
	_last_us = now
	return v


## THE DRAW MEASUREMENT, and the reason it alternates frame by frame rather than
## running a quiet block then an active block. The block version was built first
## and reported a 10.7 ms per-instance `_draw` for Blizzard — arithmetically
## impossible (it implies a 256 ms frame, and the run would have taken an hour).
## It was a background-load spike that happened to land inside the active block.
##
## Alternating puts drift in BOTH samples, and taking the MEDIAN of each side
## throws the spike away instead of averaging it in.
##
## Runs ONE SCRIPT AT A TIME (`_groups[_gi]`), because "this spell costs 400 µs a
## frame to draw" is not actionable and "the sigil every spell opens costs 300 of
## it" is. The per-spell number is the sum of its groups.
func _draw_ab() -> void:
	var v: float = _sample()
	if _phase_frames > 2:                 # discard the transition frame
		if _prev_active:
			_act.append(v)
		else:
			_qui.append(v)
	_prev_active = (_phase_frames % 2) == 0
	if _prev_active:
		for n: Node in _groups[_gi]["nodes"]:
			if is_instance_valid(n):
				(n as CanvasItem).queue_redraw()
	if _phase_frames >= _draw_frames * 2:
		var g: Dictionary = _groups[_gi]
		# ms/frame for the whole cohort of this script -> µs of `_draw` for the
		# instances ONE cast of this spell contributes.
		g["draw"] = maxf(_median(_act) - _median(_qui), 0.0) * 1000.0 \
			/ maxf(float(_copies), 1.0)
		_gi += 1
		if _gi >= _groups.size():
			_close_row()
		else:
			_enter(Phase.DRAW_AB)


static func _median(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s: Array[float] = a.duplicate()
	s.sort()
	return s[s.size() / 2]


# ------------------------------------------------------------------ the passes
## Cast `copies` instances in ONE frame, so every instance is at the SAME point in
## its life when it is measured. (A population topped up over time would mix a
## fresh spectacle's opening frames with a spent one's, and those are different
## code paths.) Freezes them immediately: from here they are driven by hand.
func _do_spawn() -> void:
	_nodes.clear()
	_before.clear()
	var spell: SpellDef = _spells[_idx]
	var half: float = ROOM_WIDTH * 0.5
	for c: Node in _arena.get_children():
		_before[c] = true
	var t0: int = Time.get_ticks_usec()
	for i: int in _copies:
		var tx: float = -half + fmod(float(i) * 211.0, ROOM_WIDTH)
		SpellCaster.cast(spell, _arena, (_hero as Node2D).global_position,
			Vector2(tx, SimArena.FLOOR_Y - 50.0), Color(0.6, 0.8, 1.0),
			spell.effect, _hero, &"mortal")
	_cast_us = float(Time.get_ticks_usec() - t0) / maxf(float(_copies), 1.0)
	_enter(Phase.WARM)


## Everything the cast built, INCLUDING what it built during the warm-up (a meteor
## makes rocks, a chain makes arcs, a wall makes shards) and including sub-nodes,
## since those tick and draw on the spell's behalf and belong in its bill.
func _freeze() -> void:
	for c: Node in _arena.get_children():
		if not _before.has(c):
			_collect(c)
	for n: Node in _nodes:
		n.set_process(false)
		n.set_physics_process(false)
	# Bucket by script so each one can be A/B'd on its own.
	var by: Dictionary = {}
	for n2: Node in _nodes:
		if not _declares_draw(n2):
			continue
		var s: Script = n2.get_script() as Script
		# Scriptless nodes are bucketed by ENGINE CLASS, not lumped together: the
		# first run of this put 62% of all draw cost into one "(no script)" row,
		# which named no file anybody could go and open.
		var key: String = ("<" + n2.get_class() + ">") if s == null \
			else s.resource_path.get_file().get_basename()
		if not by.has(key):
			by[key] = {"script": key, "nodes": [] as Array[Node], "draw": 0.0}
		(by[key]["nodes"] as Array[Node]).append(n2)
	_groups.clear()
	for k: String in by.keys():
		_groups.append(by[k])
	if _groups.is_empty():
		# Nothing was built (a pure caster-state spell). Give the state machine one
		# empty bucket so it still closes the row instead of stalling on an
		# out-of-range index.
		_groups.append({"script": "-", "nodes": [] as Array[Node], "draw": 0.0})
	_gi = 0


## The three POOLED services are deliberately skipped. They are shared singleton
## pools parented under the arena, so a spell that happens to spawn one would have
## the harness freeze it and then free it at the end of the row — draining the pool
## and charging the NEXT spell for refilling it. Their cost is already governed by
## the VFX budget and reported by the WORK counters in
## `tools/stress_mobile_entities.gd`; it does not belong in a per-spectacle column.
const POOLED: PackedStringArray = ["DamageNumber", "CombatVfx", "ScorchDecal"]

func _collect(n: Node) -> void:
	var s: Script = n.get_script() as Script
	if s != null and POOLED.has(s.resource_path.get_file().get_basename()):
		return
	if n is CanvasItem:
		_nodes.append(n)
	for c: Node in n.get_children():
		_collect(c)


## Does this node's own script implement `_draw`?
##
## ⚠ THE A/B REDRAWS ONLY THESE, AND THE FIRST VERSION DID NOT — WHICH PRODUCED A
## FALSE HEADLINE. Forcing `queue_redraw()` on every CanvasItem put
## `<GPUParticles2D>` at the top of the table with 67% of all draw cost. That is an
## artefact of the measurement, not a cost the game pays: nothing in the game
## redraws a particle node every frame, and re-registering one does work that a
## real frame never asks for. Only a script with its own `_draw` — driven by its own
## per-frame `queue_redraw()` — is describing something the shipping game does.
static func _declares_draw(n: Node) -> bool:
	var s: Script = n.get_script() as Script
	if s == null:
		return false
	for m: Dictionary in s.get_script_method_list():
		if String(m["name"]) == "_draw":
			return true
	return false


## µs for ONE `_process` (or `_physics_process`) call. Hand-driven from a frozen
## state with `TINY_DT`, so iteration 400 does the same work as iteration 1.
func _time_process() -> void:
	_proc_us = 0.0
	if _nodes.is_empty():
		return
	var live: Array[Node] = []
	for n: Node in _nodes:
		if is_instance_valid(n) and n.is_inside_tree():
			live.append(n)
	if live.is_empty():
		return
	# Per NODE, not per cohort: a spell's cohort mixes the spectacle (`_process`)
	# with the debris it threw (`_physics_process`), and asking the first one what
	# the rest use would silently drop whichever half answered differently.
	var work: Array[Node] = []
	var names: Array[StringName] = []
	for n: Node in live:
		var s: Script = n.get_script() as Script
		if s == null:
			continue
		var has_p: bool = false
		var has_pp: bool = false
		for m: Dictionary in s.get_script_method_list():
			if String(m["name"]) == "_process":
				has_p = true
			elif String(m["name"]) == "_physics_process":
				has_pp = true
		if has_p:
			work.append(n)
			names.append(&"_process")
		elif has_pp:
			work.append(n)
			names.append(&"_physics_process")
	if work.is_empty():
		return
	var calls: int = 0
	var t0: int = Time.get_ticks_usec()
	for _i: int in _iters:
		for j: int in work.size():
			var w: Node = work[j]
			if is_instance_valid(w):
				w.call(names[j], TINY_DT)
				calls += 1
	var dt: int = Time.get_ticks_usec() - t0
	# Divided by the number of CASTS, not the number of ticking nodes, so the
	# column reads "what one live spell costs the frame" — a meteor that ticks
	# nine rocks is nine ticks expensive and should say so.
	_proc_us = float(dt) / maxf(float(_iters * _copies), 1.0)
	_ticking = float(calls) / maxf(float(_iters * _copies), 1.0)


func _close_row() -> void:
	var spell: SpellDef = _spells[_idx]
	var live: int = 0
	for n: Node in _nodes:
		if is_instance_valid(n):
			live += 1
	var draw_us: float = 0.0
	var parts: PackedStringArray = PackedStringArray()
	for g: Dictionary in _groups:
		var d: float = float(g["draw"])
		draw_us += d
		if d <= 0.0:
			continue
		var key: String = String(g["script"])
		parts.append("%s %.0f" % [key, d])
		if not _by_script.has(key):
			_by_script[key] = {"draw": 0.0, "casts": 0, "worst": 0.0}
		_by_script[key]["draw"] = float(_by_script[key]["draw"]) + d
		_by_script[key]["casts"] = int(_by_script[key]["casts"]) + 1
		_by_script[key]["worst"] = maxf(float(_by_script[key]["worst"]), d)
	_rows.append({
		"id": spell.id,
		"script": _script_name(_nodes),
		"cast": _cast_us,
		"proc": _proc_us,
		"draw": draw_us,
		"nodes": float(live) / maxf(float(_copies), 1.0),
		"tick": _ticking,
		"split": " | ".join(parts),
	})
	print("[prof]  %-22s cast %7.1f us  proc %6.2f us  draw %7.2f us  [%s]"
		% [spell.id, _cast_us, _proc_us, draw_us, " | ".join(parts)])
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_idx += 1
	if _idx >= _spells.size():
		_report()
		_done = true
		quit(0)
		return
	_enter(Phase.SPAWN)


static func _script_name(nodes: Array[Node]) -> String:
	for n: Node in nodes:
		if not is_instance_valid(n):
			continue
		var s: Script = n.get_script() as Script
		if s != null:
			return s.resource_path.get_file().get_basename()
	return "-"


func _report() -> void:
	# Sorted by PER-FRAME cost (proc + draw), because that is the number the
	# 8-effect ceiling multiplies by 60 every second. Cast cost is paid once and
	# is a different problem with a different fix.
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (float(a["proc"]) + float(a["draw"])) > (float(b["proc"]) + float(b["draw"])))
	print("[prof] ============================================================")
	print("[prof] %-22s %-16s %9s %8s %9s %9s %6s"
		% ["spell", "script", "cast us", "proc us", "draw us", "frame us", "nodes"])
	var tot: float = 0.0
	for r: Dictionary in _rows:
		var per_frame: float = float(r["proc"]) + float(r["draw"])
		tot += per_frame
		print("[prof] %-22s %-16s %9.1f %8.2f %9.2f %9.2f %6.1f"
			% [r["id"], r["script"], r["cast"], r["proc"], r["draw"], per_frame,
				r["nodes"]])
	# THE ACTIONABLE TABLE. Per-spell tells you which spell is expensive; per-SCRIPT
	# tells you which FILE to open, and a script that shows up under 30 spell ids is
	# a systemic cost rather than one bad spell.
	var srows: Array[Dictionary] = []
	for k: String in _by_script.keys():
		srows.append({"s": k, "d": _by_script[k]})
	srows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["d"]["draw"]) > float(b["d"]["draw"]))
	print("[prof] ---------------- DRAW COST BY SCRIPT ----------------")
	print("[prof] %-20s %8s %10s %10s %8s" % ["script", "spells", "mean us", "worst us", "share"])
	var grand: float = 0.0
	for r2: Dictionary in srows:
		grand += float(r2["d"]["draw"])
	for r3: Dictionary in srows:
		var d2: Dictionary = r3["d"]
		print("[prof] %-20s %8d %10.1f %10.1f %7.1f%%"
			% [r3["s"], int(d2["casts"]), float(d2["draw"]) / maxf(float(d2["casts"]), 1.0),
				float(d2["worst"]), 100.0 * float(d2["draw"]) / maxf(grand, 0.001)])
	print("[prof] ============================================================")
	print("[prof] roster mean frame cost %.2f us/instance;  8 concurrent = %.2f ms/frame"
		% [tot / maxf(float(_rows.size()), 1.0),
			8.0 * tot / maxf(float(_rows.size()), 1.0) / 1000.0])
	print("[prof] REMINDER: dummy renderer — draw cost here is COMMAND BUILDING only.")


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
			"copies":
				_copies = clampi(int(v), 1, 200)
			"iters":
				_iters = clampi(int(v), 10, 20000)
			"crowd":
				_crowd = clampi(int(v), 0, 60)
			"draw_frames":
				_draw_frames = clampi(int(v), 5, 400)
			"quality":
				_force_low = v.to_lower() == "low"
			"spell":
				_only = v
			"warm":
				_warm = clampi(int(v), 0, 300)
