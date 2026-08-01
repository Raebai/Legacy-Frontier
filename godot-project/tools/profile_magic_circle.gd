# Run: godot --headless --path godot-project --script tools/profile_magic_circle.gd
#   optional: ++copies=64 ++frames=60
#
# THE SIGIL BENCH. `tools/profile_spectacles.gd` found that `MagicCircle` is
# **87.9% of all spell-spectacle `_draw` cost** across the roster — it opens on 31
# of 38 spells, so it is not one expensive spell, it is a tax on nearly every cast.
# What that tool CANNOT do is give a repeatable number for it: a sigil's draw
# depends on where in its own life it was caught (alpha, charge, snap, whether it
# has already bloomed out), and casting a spell and waiting N frames catches a
# different state every time. The same two spells measured 65/25 µs on one run and
# 22/84 µs on the next — state variance, not machine noise.
#
# So this builds sigils DIRECTLY, drives them to an IDENTICAL state, and A/Bs the
# draw. Every configuration in the ladder is measured the same way, which is what
# makes two runs comparable and therefore what makes a before/after mean anything.
#
# THE LADDER matters as much as the total. The sigil is the TELEGRAPH — the tier
# ladder (QUICK ring / HEAVY mechanism / ULT summoning band) and the element glyph
# band are the fairness contract, not garnish, so a saving has to come from drawing
# the SAME picture more cheaply. Splitting the measurement by tier and orientation
# is how you can tell those apart: a change that flattens ULT toward QUICK is a
# feel regression wearing a performance win's clothes.
#
# ⚠ THE PRIMARY RESULT IS A COUNT, NOT A TIME, and that is not timidity — it is
# because a time here is not measurable on this machine. An A/B probe drawing 250
# rings of 60 segments reported 0.42 µs/node; the same probe at 200 segments
# reported 9.14 µs/node. Non-monotonic by a factor of twenty, because a headless
# frame absorbs extra work into idle time until it crosses the pacing budget, at
# which point it appears all at once. (Same family as the trap already recorded in
# docs/mobile-export.md, where a harness confidently reported a perfect 16.67 ms
# because it was timing frame pacing rather than work.)
#
# SEGMENTS ISSUED PER SIGIL PER FRAME is exactly linear in the thing being cut,
# is what the CPU builds commands for AND what the GPU rasterises, and is identical
# on every machine and every run. The wall-clock figure is still printed, clearly
# labelled, because a rough cross-check is worth having — but the count is the
# result and the millisecond is the anecdote.
#
# Test-idiom note: a HARNESS, not an assertion suite — no pass/fail sentinels.
extends SceneTree

var _copies: int = 64
var _frames: int = 60
var _stage: Node2D = null
var _rows: Array[Dictionary] = []

## The configurations swept. `radius` values are the real ones: Hero's windup sigil
## sizes itself ~17 px (cheap jab) to ~34 px (ult), and spectacle muzzle sigils run
## bigger — see MagicCircle's TIER_RADIUS_* notes.
const CONFIGS: Array[Dictionary] = [
	{"name": "QUICK face", "tier": 0, "r": 20.0, "edge": false, "elem": 0},
	{"name": "HEAVY face", "tier": 1, "r": 30.0, "edge": false, "elem": 1},
	{"name": "ULT   face", "tier": 2, "r": 44.0, "edge": false, "elem": 3},
	{"name": "ULT   face big", "tier": 2, "r": 90.0, "edge": false, "elem": 4},
	{"name": "HEAVY edge", "tier": 1, "r": 30.0, "edge": true, "elem": 2},
	{"name": "ULT   edge", "tier": 2, "r": 44.0, "edge": true, "elem": 5},
	{"name": "HEAVY face noelem", "tier": 1, "r": 30.0, "edge": false, "elem": -1},
]

var _ci: int = 0
var _low: bool = false
var _phase_frames: int = 0
var _nodes: Array[MagicCircle] = []
var _act: Array[float] = []
var _qui: Array[float] = []
var _prev_active: bool = false
var _last_us: int = 0
var _boot: int = 2
var _done: bool = false


func _initialize() -> void:
	_parse_args()
	_stage = Node2D.new()
	root.add_child(_stage)


func _process(_d: float) -> bool:
	if _done:
		return true
	if _boot > 0:
		_boot -= 1
		if _boot == 0:
			_force_quality()
			_build()
		return false
	_phase_frames += 1
	var now: int = Time.get_ticks_usec()
	var v: float = float(now - _last_us) / 1000.0
	_last_us = now
	if _phase_frames > 2:
		if _prev_active:
			_act.append(v)
		else:
			_qui.append(v)
	_prev_active = (_phase_frames % 2) == 0
	if _prev_active:
		for n: MagicCircle in _nodes:
			if is_instance_valid(n):
				n.queue_redraw()
	if _phase_frames >= _frames * 2:
		_close()
	return false


## One cohort, all in the SAME state: grown to full alpha, mid-charge, not
## vanishing. Driven by hand rather than by waiting, so the state is a decision
## rather than an accident of timing.
func _build() -> void:
	_nodes.clear()
	var c: Dictionary = CONFIGS[_ci]
	for i: int in _copies:
		var m: MagicCircle = MagicCircle.new()
		_stage.add_child(m)
		m.position = Vector2(float(i % 8) * 120.0, float(i / 8) * 120.0)
		m.appear(Color(0.6, 0.8, 1.0), float(c["r"]), 0.3)
		m.set_signature(int(c["elem"]), int(c["tier"]))
		if bool(c["edge"]):
			m.set_orientation(true, Vector2.RIGHT, 0.15)
		# Long hold so nothing blooms out mid-measurement.
		m.hold(600.0, 0.26)
		# Grow to full: grow_time 0.3 s, so 8 x 0.05 s is comfortably past it.
		for _k: int in 8:
			m._process(0.05)
		# Freeze. From here the only thing that runs is `_draw`.
		m.set_process(false)
		_nodes.append(m)
	MagicCircle.reset_work()
	_phase_frames = 0
	_act.clear()
	_qui.clear()
	_prev_active = false
	_last_us = Time.get_ticks_usec()


func _close() -> void:
	var c: Dictionary = CONFIGS[_ci]
	var us: float = maxf(_median(_act) - _median(_qui), 0.0) * 1000.0 \
		/ maxf(float(_copies), 1.0)
	# Per SIGIL per FRAME: the counters are totals over every `_draw` that ran during
	# the A/B, so dividing by `sigils` is what makes runs of different lengths
	# comparable.
	var w: Dictionary = MagicCircle.work_stats()
	var draws: float = maxf(float(w["sigils"]), 1.0)
	_rows.append({
		"name": String(c["name"]), "us": us,
		"segs": float(w["segments"]) / draws,
		"glyphs": float(w["glyphs"]) / draws,
		"blobs": float(w["blobs"]) / draws,
	})
	print("[sigil] %-20s %s  segments %7.1f  glyphs %5.1f  blobs %5.1f"
		% [c["name"], "LOW " if _low else "HIGH",
			float(w["segments"]) / draws, float(w["glyphs"]) / draws,
			float(w["blobs"]) / draws])
	for n: MagicCircle in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	_ci += 1
	if _ci >= CONFIGS.size():
		_report()
		_done = true
		quit(0)
		return
	_boot = 2


static func _median(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s: Array[float] = a.duplicate()
	s.sort()
	return s[s.size() / 2]


func _report() -> void:
	var tot: float = 0.0
	var segs: float = 0.0
	for r: Dictionary in _rows:
		tot += float(r["us"])
		segs += float(r["segs"])
	var n: float = maxf(float(_rows.size()), 1.0)
	print("[sigil] --------------------------------------------------")
	print("[sigil] quality %-4s  MEAN %.1f SEGMENTS per sigil per frame  (%d configs)"
		% ["LOW" if _low else "HIGH", segs / n, _rows.size()])
	# The spec's ceiling is 8 concurrent spell effects and nearly every one of them
	# is carrying one of these, so this is the sigil layer's whole per-frame bill.
	print("[sigil] 8 concurrent sigils = %.0f segments/frame" % (8.0 * segs / n))
	print("[sigil] (wall-clock, NOT trustworthy on this machine: %.1f us/sigil)"
		% (tot / n))


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
				_frames = clampi(int(v), 5, 400)
			"quality":
				_low = v.to_lower() == "low"


## ⚠ FROM A LIVE FRAME, NOT `_initialize`. Inside `_initialize` the SceneTree root
## is not the active tree yet, so `/root/Tuning` resolves to null, the guard
## swallows it, and every "LOW" run is a mislabelled HIGH one — the exact bug that
## invalidated every historical LOW figure in docs/mobile-export.md.
func _force_quality() -> void:
	if not _low:
		return
	var t: Node = root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		print("[sigil] ⚠ could not reach Tuning — LOW NOT APPLIED")
		return
	t.cfg.set(&"graphics_quality", TuningConfig.Quality.LOW)
