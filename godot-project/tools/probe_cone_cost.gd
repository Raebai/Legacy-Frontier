# THE CONE'S PRICE, NEXT TO EVERY OTHER TELL'S.
#
#   godot --headless --path godot-project --script tools/probe_cone_cost.gd
#
# `Telegraph` was rebuilt so that every style degrades through a pure static plan
# function and the tell layer's draw calls went 103 -> 60. A ninth style is a claim
# on that budget, so it does not get to be added without a number: this prints the
# `Telegraph.work_stats()` counters for every shipped configuration at HIGH and at
# LOW, so the CONE's cost is read next to the eight it joins rather than asserted.
#
# ⚠ COUNTS, NOT MILLISECONDS, and `Telegraph`'s own WORK COUNTERS block argues it at
# length: a frame absorbs extra work into idle time until it crosses the pacing
# budget, at which point the whole cost appears at once, so a wall-clock figure here
# is a coin toss and a primitive count is a fact.
#
# Test-idiom note: a HARNESS, not an assertion suite — it reports, it does not gate.
# The gate is `tools/slice_test_tell_budget.gd`, which walks the same table.
extends SceneTree

const TELL: GDScript = preload("res://scripts/combat/Telegraph.gd")

## The same nine-plus-three table `slice_test_tell_budget.gd` walks. Duplicated
## deliberately rather than imported: a probe that can only run when a suite compiles
## is a probe you cannot use to debug that suite.
const CONFIGS: Array[Dictionary] = [
	{"name": "ZONE brute", "style": 0, "r": 40.0, "w": 0.60},
	{"name": "ZONE mage", "style": 0, "r": 70.0, "w": 0.85},
	{"name": "MUZZLE caster", "style": 1, "r": 18.0, "w": 0.70},
	{"name": "LANE charger", "style": 2, "line": true, "len": 300.0, "wid": 34.0, "w": 0.70},
	{"name": "DART assassin", "style": 3, "r": 26.0, "w": 0.35},
	{"name": "GATHER summoner", "style": 4, "r": 24.0, "w": 0.80},
	{"name": "BOMB bomber", "style": 5, "r": 78.0, "w": 0.90},
	{"name": "FIST hero melee (old LANE shape)", "style": 6, "line": true,
		"len": 58.0, "wid": 10.4, "w": 0.077},
	{"name": "CRESCENT blade (old LANE shape)", "style": 7, "line": true,
		"len": 58.0, "wid": 10.4, "w": 0.077},
	{"name": "FIST melee CONE (light)", "style": 6, "cone": true, "reach": 58.0,
		"half": 1.2661, "wid": 10.4, "light": true, "w": 0.077},
	{"name": "CRESCENT melee CONE (light)", "style": 7, "cone": true, "reach": 58.0,
		"half": 1.2661, "wid": 10.4, "light": true, "w": 0.077},
	{"name": "CONE uppercut (full)", "style": 8, "cone": true, "reach": 70.0,
		"half": 1.7722, "w": 0.10},
	{"name": "CONE frost (full)", "style": 8, "cone": true, "reach": 118.0,
		"half": 1.0472, "w": 0.10},
]

const PHASE: float = 0.6

var _ran: bool = false
var _stage: Node2D = null


func _process(_d: float) -> bool:
	# ⚠ BOTH RETURNS ARE `false`, AND THE GUARD'S ONE IS THE SUBTLE ONE. A
	# `SceneTree._process` that returns `true` QUITS THE TREE on that frame. Returning
	# `true` from the already-ran guard therefore killed the coroutine on frame 2 —
	# after exactly one `await process_frame` — so the table printed its header, one
	# row's worth of work, and then the process exited clean with no error and no rows.
	# The tree has to stay alive for as long as `_run` is still awaiting frames.
	if _ran:
		return false
	_ran = true
	# ⚠ RETURNS FALSE, AND `_run` OWNS THE QUIT. A `SceneTree._process` that returns
	# `true` quits the tree on that frame — which kills `_run`'s coroutine before its
	# first `await process_frame` ever resumes, so the table prints its header and
	# nothing else. Measured that way once; the header was the only honest line in it.
	_run()
	return false


func _run() -> void:
	# Headless has no window and therefore no aspect: `get_visible_rect()` falls back
	# to a square 640x640 and a CanvasItem outside it is CULLED, so `_draw` never runs
	# and every row measures zero. Same trap `slice_test_tell_budget` records.
	root.size = Vector2i(1366, 768)
	_stage = Node2D.new()
	root.add_child(_stage)
	print("")
	print("== TELEGRAPH DRAW COST — calls / segments, one _draw at %d%% of the windup" % int(PHASE * 100.0))
	print("%-34s %10s %10s   %10s %10s" % ["style", "HIGH calls", "HIGH segs", "LOW calls", "LOW segs"])
	for c: Dictionary in CONFIGS:
		var hi: Dictionary = await _measure(c, false)
		var lo: Dictionary = await _measure(c, true)
		print("%-34s %10d %10d   %10d %10d"
			% [String(c["name"]), int(hi["calls"]), int(hi["segments"]),
				int(lo["calls"]), int(lo["segments"])])
	print("")
	print("Reach honesty (rule 2: a tell may not claim more ground than danger_shape reports):")
	for c: Dictionary in CONFIGS:
		if not bool(c.get("cone", false)):
			continue
		var hi: Dictionary = await _measure(c, false)
		print("  %-32s drawn reach %6.1f px   cone radius %6.1f px"
			% [String(c["name"]), float(hi["reach"]), float(c["reach"])])
	quit(0)


## ⚠ `queue_redraw` + TWO FRAMES, NOT A DIRECT `_draw()` CALL. Godot refuses every
## `draw_*` primitive outside a real draw pass ("Drawing is only allowed inside this
## node's `_draw()`"), so calling `_draw` by hand produces a table of zeroes with an
## error per row — which the first version of this probe did. The counters are
## static, so they are reset immediately before the frame that draws.
func _measure(c: Dictionary, low: bool) -> Dictionary:
	var t: Node2D = TELL.new()
	_stage.add_child(t)
	t.position = Vector2(500.0, 400.0)
	t.set("style", int(c["style"]))
	t.set("_low", low)
	var windup: float = float(c["w"])
	if bool(c.get("cone", false)):
		t.call("start_cone", float(c["reach"]), float(c["half"]), 0.35, windup,
			float(c.get("wid", 0.0)), bool(c.get("light", false)))
	elif bool(c.get("line", false)):
		t.call("start_line", float(c["len"]), float(c["wid"]), 0.35, windup)
	else:
		t.call("start", float(c["r"]), windup)
	t.set("_elapsed", windup * PHASE)
	t.set_process(false)
	TELL.reset_work()
	t.queue_redraw()
	await process_frame
	await process_frame
	var stats: Dictionary = TELL.work_stats()
	t.free()
	return stats
