# THE TELL BENCH — what one telegraph costs to draw, per style, before and after.
#
#   godot --headless --path godot-project --script tools/probe_tell_cost.gd
#   optional: ++copies=80 ++frames=8
#
# WHY A DEDICATED BENCH. A `Telegraph` is on screen for every attack in the game
# — seven enemy archetypes, five archetype spells, four hero abilities, every
# melee swing and every placed blast — so it is a per-frame tax on the whole
# roster in the way `MagicCircle` is a tax on every cast. `profile_magic_circle`
# measures the sigil layer and nothing measured this one. It had no counters and
# no `graphics_quality` gate at all: the one layer that must stay readable on a
# phone was the one layer that never got cheaper on one.
#
# ⚠ THE BEFORE IS RUN, NOT REMEMBERED. `tools/_tell_before.gd` is a frozen copy of
# the old `_draw` body carrying the same counters, so both versions are built in
# the SAME process, driven to the SAME state and counted in the SAME frame. A
# before/after where the "before" is a number in a commit message is an assertion.
#
# ⚠ THE PRIMARY RESULT IS A COUNT, NOT A TIME, for the reason written out at
# length in `MagicCircle`'s WORK COUNTERS block and repeated in
# `tools/profile_magic_circle.gd`: a headless frame absorbs extra work into idle
# time until it crosses the pacing budget, at which point the whole cost appears
# at once, so microseconds here are non-monotonic by more than an order of
# magnitude. DRAW COMMANDS and SEGMENTS are exactly linear in the thing being cut
# and identical on every machine. The wall-clock A/B is printed at the end,
# clearly labelled as the anecdote.
#
# Test-idiom note: a HARNESS, not an assertion suite — no pass/fail sentinels.
# The pass/fail contract lives in `tools/slice_test_tell_budget.gd`.
extends SceneTree

const AFTER: GDScript = preload("res://scripts/combat/Telegraph.gd")
const BEFORE: GDScript = preload("res://tools/_tell_before.gd")

## Every style, at the size and windup the GAME actually uses it at — pulled from
## `Enemy`'s tuning block and `Hero`'s swing tell, not invented. Measuring a style
## at a made-up radius measures a picture nobody sees.
##   line   : LINE shape (length/width/angle) instead of a radius
##   tether : ZONE and DART draw a link back to the caster, so they need a source
const CONFIGS: Array[Dictionary] = [
	{"name": "ZONE brute", "style": 0, "r": 40.0, "w": 0.60, "tether": true},
	{"name": "ZONE mage", "style": 0, "r": 70.0, "w": 0.85, "tether": true},
	{"name": "MUZZLE caster", "style": 1, "r": 18.0, "w": 0.70, "reach": 130.0},
	{"name": "LANE charger", "style": 2, "line": true, "len": 300.0, "wid": 34.0, "w": 0.70},
	{"name": "DART assassin", "style": 3, "r": 26.0, "w": 0.35, "tether": true},
	{"name": "GATHER summoner", "style": 4, "r": 24.0, "w": 0.80},
	{"name": "BOMB bomber", "style": 5, "r": 78.0, "w": 0.90},
	{"name": "FIST hero melee", "style": 6, "line": true, "len": 58.0, "wid": 10.4, "w": 0.077},
	{"name": "CRESCENT blade", "style": 7, "line": true, "len": 58.0, "wid": 10.4, "w": 0.077},
]

## Where in its own life every tell is frozen. 0.6 of the windup: past the point
## where growing figures have grown, before anything has fired. A tell caught at a
## different phase draws a different amount, which is exactly the state variance
## `profile_magic_circle` was written to remove.
const PHASE: float = 0.6

var _copies: int = 80
var _frames: int = 8
var _stage: Node2D = null
var _source: Node2D = null

var _rows: Array[Dictionary] = []
var _nodes: Array[Node2D] = []
var _ci: int = 0
var _variant: int = 0        # 0 before/HIGH, 1 after/HIGH, 2 after/LOW
var _boot: int = 3
var _counted: int = 0
var _done: bool = false
var _clocking: bool = false
## Wall-clock A/B result, run once over a whole-roster cohort at the end.
var _clock_rows: Array[Dictionary] = []


func _initialize() -> void:
	_parse_args()
	# ⚠ HEADLESS HAS NO WINDOW AND THEREFORE NO ASPECT — `get_visible_rect()` falls
	# back to a SQUARE 640x640. Nothing here reads the viewport, but a tell is sized
	# against a 640x360 frame and a future addition might, so the root is put into
	# the shipping shape rather than left in the fallback one.
	root.size = Vector2i(1366, 768)
	_stage = Node2D.new()
	root.add_child(_stage)
	_source = Node2D.new()
	_stage.add_child(_source)
	_source.position = Vector2(-90.0, -30.0)


func _process(_d: float) -> bool:
	if _done:
		return true
	if _clocking:
		return false     # parked: the clock coroutine owns the tree until it quits
	if _boot > 0:
		_boot -= 1
		if _boot == 0:
			_build()
		return false
	# Every frame: ask for a redraw, then read what the last frame's draws cost.
	for n: Node2D in _nodes:
		if is_instance_valid(n):
			n.queue_redraw()
	_counted += 1
	if _counted >= _frames:
		_close_cohort()
	return false


func _script_for_variant() -> GDScript:
	return BEFORE if _variant == 0 else AFTER


func _build() -> void:
	_nodes.clear()
	var c: Dictionary = CONFIGS[_ci]
	var s: GDScript = _script_for_variant()
	var low: bool = _variant == 2
	for i: int in _copies:
		var t: Node2D = s.new()
		_stage.add_child(t)
		t.position = Vector2(float(i % 10) * 140.0, float(i / 10) * 140.0)
		t.set("style", int(c["style"]))
		t.set("accent", Color(0.62, 0.52, 1.0, 1.0))
		# ⚠ A NO-OP ON THE `before` SCRIPT, AND THAT IS THE FINDING. `Object.set` on
		# a property a script has not declared is silent, so the old build simply
		# cannot be put into its cheap mode: it never had one.
		t.set("_low", low)
		if bool(c.get("tether", false)):
			t.set("source", _source)
		if bool(c.get("reach", 0.0) > 0.0):
			t.set("aim_dir", Vector2.RIGHT)
			t.set("reach", float(c["reach"]))
		var windup: float = float(c["w"])
		if bool(c.get("line", false)):
			t.call("start_line", float(c["len"]), float(c["wid"]), 0.35, windup)
		else:
			t.call("start", float(c["r"]), windup)
		# Frozen state, set rather than waited for: `advance()` would also fire the
		# signal and free the node, and a cohort that frees itself mid-measurement is
		# how the sigil bench first got two runs that disagreed by 4x.
		t.set("_elapsed", windup * PHASE)
		t.set_process(false)
		_nodes.append(t)
	BEFORE.reset_work()
	AFTER.reset_work()
	_counted = 0


func _close_cohort() -> void:
	var c: Dictionary = CONFIGS[_ci]
	var w: Dictionary = (BEFORE.work_stats() if _variant == 0 else AFTER.work_stats())
	var tells: float = maxf(float(w["tells"]), 1.0)
	_rows.append({
		"name": String(c["name"]), "variant": _variant,
		"calls": float(w["calls"]) / tells,
		"segments": float(w["segments"]) / tells,
		"reach": float(w["reach"]),
		"tells": int(w["tells"]),
	})
	for n: Node2D in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	_ci += 1
	if _ci >= CONFIGS.size():
		_ci = 0
		_variant += 1
		if _variant > 2:
			_report()
			# ⚠ FIRE-AND-FORGET, NOT `await`. A `SceneTree._process` that awaits
			# stops returning a bool and starts returning a coroutine object, the
			# engine reads that as "keep going", and the body never resumes — a
			# harness that then prints half its output and exits clean.
			# ⚠ NOT `_done`. `_done` makes `_process` return TRUE, which ENDS the
			# main loop — and a coroutine waiting on `process_frame` never resumes
			# once the loop it is waiting on has stopped. The first cut set it here
			# and the wall-clock section simply never printed, with a clean exit and
			# no error. `_clocking` parks `_process` without ending it.
			_clocking = true
			_clock_ab()
			return
	_boot = 2


func _report() -> void:
	var label: Array[String] = ["BEFORE HIGH", "AFTER  HIGH", "AFTER  LOW "]
	print("")
	print("[tell] copies=%d  frames=%d  phase=%.2f of windup" % [_copies, _frames, PHASE])
	print("[tell] %-17s %-12s %8s %10s %9s" % ["style", "build", "calls", "segments", "reach px"])
	print("[tell] " + "-".repeat(62))
	var tot: Array[float] = [0.0, 0.0, 0.0]
	var tot_seg: Array[float] = [0.0, 0.0, 0.0]
	for ci: int in CONFIGS.size():
		for v: int in 3:
			var r: Dictionary = _row(ci, v)
			if r.is_empty():
				continue
			tot[v] += float(r["calls"])
			tot_seg[v] += float(r["segments"])
			print("[tell] %-17s %-12s %8.2f %10.1f %9.1f"
				% [String(CONFIGS[ci]["name"]) if v == 0 else "",
					label[v], float(r["calls"]), float(r["segments"]), float(r["reach"])])
		print("[tell]")
	print("[tell] " + "=".repeat(62))
	for v: int in 3:
		print("[tell] %-30s calls %7.2f   segments %8.1f"
			% [label[v] + " total over all styles", tot[v], tot_seg[v]])
	if tot[0] > 0.0:
		print("[tell] DRAW COMMANDS: after/HIGH is %.2fx the before, after/LOW is %.2fx"
			% [tot[1] / tot[0], tot[2] / tot[0]])
		print("[tell] SEGMENTS     : after/HIGH is %.2fx the before, after/LOW is %.2fx"
			% [tot_seg[1] / maxf(tot_seg[0], 1.0), tot_seg[2] / maxf(tot_seg[0], 1.0)])
	print("[tell] (a tell's `reach px` is the furthest any primitive got from its own")
	print("[tell]  origin — the honesty number, not a cost one. See Telegraph rule 2.)")


# ------------------------------------------------------------- THE ANECDOTE
## Wall-clock A/B over a WHOLE-ROSTER cohort — one of every style, `copies` times,
## which is the shape a busy floor actually puts on screen. Alternating frames
## redraw / do not redraw, and the difference of the MEDIANS is the draw cost.
##
## ⚠ REPORTED, NOT TRUSTED, and the counts above are the result. `profile_magic_circle`
## records the reason in full: a headless frame absorbs extra work into idle time
## until it crosses the pacing budget, at which point the whole cost appears at once,
## so the same probe at two sizes has reported figures a factor of twenty apart in
## the wrong direction. Medians over many frames tame that; they do not remove it.
## Read this as "the same order of magnitude as the counts say", never as a number.
func _clock_ab() -> void:
	print("")
	for variant: int in [0, 1]:
		_variant = variant
		var us: float = await _clock_one()
		_clock_rows.append({"variant": variant, "us": us})
	var before: float = float(_clock_rows[0]["us"])
	var after: float = float(_clock_rows[1]["us"])
	print("[tell] WALL CLOCK (the anecdote — see the header): whole roster, %d of each style"
		% _copies)
	print("[tell]   BEFORE %7.1f us/tell     AFTER %7.1f us/tell     %.2fx"
		% [before, after, after / maxf(before, 0.0001)])
	_source.free()
	_stage.free()
	quit(0)


func _clock_one() -> float:
	var s: GDScript = _script_for_variant()
	var built: Array[Node2D] = []
	var idx: int = 0
	for c: Dictionary in CONFIGS:
		for i: int in _copies:
			var t: Node2D = s.new()
			_stage.add_child(t)
			t.position = Vector2(float(idx % 40) * 34.0, float(idx / 40) * 34.0)
			idx += 1
			t.set("style", int(c["style"]))
			t.set("accent", Color(0.62, 0.52, 1.0, 1.0))
			if bool(c.get("tether", false)):
				t.set("source", _source)
			if float(c.get("reach", 0.0)) > 0.0:
				t.set("aim_dir", Vector2.RIGHT)
				t.set("reach", float(c["reach"]))
			var windup: float = float(c["w"])
			if bool(c.get("line", false)):
				t.call("start_line", float(c["len"]), float(c["wid"]), 0.35, windup)
			else:
				t.call("start", float(c["r"]), windup)
			t.set("_elapsed", windup * PHASE)
			t.set_process(false)
			built.append(t)
	var act: Array[float] = []
	var qui: Array[float] = []
	var last: int = Time.get_ticks_usec()
	for f: int in 120:
		var active: bool = (f % 2) == 0
		if active:
			for t: Node2D in built:
				t.queue_redraw()
		await process_frame
		var now: int = Time.get_ticks_usec()
		var ms: float = float(now - last) / 1000.0
		last = now
		if f >= 4:      # discard the warm-up frames
			if active:
				act.append(ms)
			else:
				qui.append(ms)
	for t: Node2D in built:
		t.free()
	return maxf(_median(act) - _median(qui), 0.0) * 1000.0 \
		/ maxf(float(_copies * CONFIGS.size()), 1.0)


static func _median(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s: Array[float] = a.duplicate()
	s.sort()
	return s[s.size() / 2]


func _row(ci: int, variant: int) -> Dictionary:
	for r: Dictionary in _rows:
		if String(r["name"]) == String(CONFIGS[ci]["name"]) and int(r["variant"]) == variant:
			return r
	return {}


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
				_copies = clampi(int(v), 1, 400)
			"frames":
				_frames = clampi(int(v), 2, 200)
