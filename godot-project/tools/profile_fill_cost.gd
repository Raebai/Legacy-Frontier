# Run WITH THE GUI BINARY (headless has no rasteriser and every row comes out equal):
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/profile_fill_cost.gd -- ++width=1920 ++height=1080 ++laps=9
#
# THE PER-PIXEL HALF OF THE FRAME. `tools/profile_draw_cost.gd` counts primitives
# and redraws — the geometry. It is structurally blind to everything that costs per
# PIXEL rather than per vertex: MSAA sample count, the fp16 HDR framebuffer, the
# full-screen post-process grade, and the framebuffer mipmap chain the grade's
# `filter_linear_mipmap` screen-texture sampler forces the renderer to build every
# frame. Those four issue about two primitives between them and can still be most
# of the frame at 1080p.
#
# ── HOW IT GETS A TRUSTWORTHY NUMBER OUT OF A LIAR ───────────────────────────
# Wall-clock in this repo is documented as non-monotonic by ~20x, and that warning
# is about SUB-MILLISECOND work being swallowed by frame pacing. This tool sidesteps
# all three legs of that trap rather than ignoring it:
#
#   1. VSYNC OFF, max_fps 0. With vsync on, every configuration cheaper than the
#      refresh interval measures the refresh interval, so the whole table reads
#      16.67 ms and the tool concludes nothing matters. That is precisely the
#      failure already recorded in docs/mobile-export.md.
#   2. THE TREE IS PAUSED and the scene is therefore STATIC. Identical geometry,
#      identical command buffers, identical everything except the one render
#      setting under test. A live fight varies the frame by more than any setting
#      does, which is why the naive version of this measurement produced a table
#      with negative costs in it.
#   3. ROUND-ROBIN, NOT BLOCK. Configurations are cycled A,B,C,A,B,C... for `laps`
#      laps rather than measured one after another. Background load and GPU clock
#      drift move across MINUTES; interleaving spreads that equally over every row
#      instead of donating it entirely to whichever row ran while a test sweep was
#      going. The reported figure is the MEDIAN of a config's laps, and each lap is
#      itself a median of its frames, so one hitch cannot move a row.
#
# What survives all that is still a wall-clock number and is still the weakest
# evidence in this repo. Treat a <5% gap between two rows as "no difference
# measured"; the settings worth changing here are the ones that move it by tens of
# percent, and those are unambiguous.
#
# ⚠ THIS MEASURES ONE GPU. An RTX 4070 Laptop's bandwidth headroom is nothing like
# a mid-range Android's, and MSAA + fp16 + a screen-reading shader are all BANDWIDTH,
# which is exactly where the two machines differ most. A row that costs 8% here can
# be the whole frame on a tile GPU. Read the ordering as portable and the magnitudes
# as desktop-only.
#
# Test-idiom note: a HARNESS, not an assertion suite — no pass/fail sentinels.
extends SceneTree

const DEFAULT_SCENE: String = "res://scenes/combat/Arena.tscn"
## Let the sandbox reach its steady population before freezing it (spawns are on a
## 1.2 s timer). A stage frozen at 2 bodies is not the picture being complained about.
const SETTLE_SECONDS: float = 9.0
## Frames measured per configuration per lap. The first few after a render-target
## reconfiguration are dominated by the reallocation itself, hence the discard.
const FRAMES_PER_LAP: int = 26
const DISCARD_PER_LAP: int = 8

## The sweep. `msaa` is a Viewport.MSAA_* value; -1 means "leave alone".
## Rows are deliberately one-change-at-a-time from BASELINE so a difference has
## exactly one candidate cause.
const CONFIGS: Array = [
	{"name": "BASELINE (as shipped)",   "msaa": -1, "hdr": true,  "post": true},
	{"name": "msaa 8x -> 4x",           "msaa": 2,  "hdr": true,  "post": true},
	{"name": "msaa 8x -> 2x",           "msaa": 1,  "hdr": true,  "post": true},
	{"name": "msaa 8x -> off",          "msaa": 0,  "hdr": true,  "post": true},
	{"name": "post-process off",        "msaa": -1, "hdr": true,  "post": false},
	{"name": "hdr_2d off",              "msaa": -1, "hdr": false, "post": true},
	{"name": "msaa off + post off",     "msaa": 0,  "hdr": true,  "post": false},
	{"name": "msaa 2x + post off + sdr","msaa": 1,  "hdr": false, "post": false},
]

var _laps: int = 9
var _width: int = 1920
var _height: int = 1080
var _scene_path: String = DEFAULT_SCENE

var _settled: float = 0.0
var _started: bool = false
var _baseline_msaa: int = 0
## config index -> Array[float] of per-lap median frame times (ms).
var _samples: Array = []


func _initialize() -> void:
	_parse_args()
	seed(20260802)
	if DisplayServer.get_name() == "headless":
		printerr("profile_fill_cost: HEADLESS — there is no rasteriser, every row would tie.")
		printerr("  Re-run with godot-engine/Godot_v4.6.2-stable_win64.exe.")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(_width, _height))
	# See the header, point 1. Without both of these the table measures the monitor.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		printerr("profile_fill_cost: could not load ", _scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	for i: int in CONFIGS.size():
		_samples.append([])
	print("[fill] scene=%s window=%dx%d laps=%d vsync=off"
		% [_scene_path, _width, _height, _laps])


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var bits: PackedStringArray = arg.trim_prefix("++").split("=")
		if bits.size() != 2:
			continue
		match bits[0]:
			"laps": _laps = maxi(int(bits[1]), 1)
			"width": _width = maxi(int(bits[1]), 320)
			"height": _height = maxi(int(bits[1]), 180)
			"scene": _scene_path = bits[1]


func _process(delta: float) -> bool:
	if _started:
		return false
	_settled += delta
	if _settled >= SETTLE_SECONDS:
		_started = true
		_run()
	return false


func _run() -> void:
	# Freeze. See the header, point 2 — this is what makes two readings comparable.
	root.get_tree().paused = true
	_baseline_msaa = int(root.msaa_2d)
	var prims: int = int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("[fill] frozen stage: %d primitives, %d draw calls, msaa_2d=%d, hdr_2d=%s"
		% [prims, int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
			_baseline_msaa, root.use_hdr_2d])
	for lap: int in _laps:
		for i: int in CONFIGS.size():
			_apply(CONFIGS[i])
			var ms: float = await _measure_lap()
			(_samples[i] as Array).append(ms)
	_apply(CONFIGS[0])   # leave the project as we found it
	_report()
	quit(0)


func _apply(cfg: Dictionary) -> void:
	var m: int = int(cfg["msaa"])
	root.msaa_2d = (_baseline_msaa if m < 0 else m) as Viewport.MSAA
	root.use_hdr_2d = bool(cfg["hdr"])
	# The grade owns its own visibility check every _process, but the tree is PAUSED,
	# so poking the Tuning flag would never be read. Hide the rect directly — which
	# is exactly what PostProcess._enabled() does when the dial says no, so this is
	# the shipping code path and not a special case invented for the harness.
	var pp: Node = root.get_tree().get_first_node_in_group(&"post_process")
	if pp != null:
		for r: Node in pp.find_children("*", "ColorRect", true, false):
			(r as ColorRect).visible = bool(cfg["post"])


## Median frame time over one lap, in ms, after discarding the frames that pay for
## the render-target reallocation an msaa/hdr change forces.
func _measure_lap() -> float:
	var times: Array[float] = []
	for f: int in FRAMES_PER_LAP:
		var t0: int = Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		var dt: float = float(Time.get_ticks_usec() - t0) / 1000.0
		if f >= DISCARD_PER_LAP:
			times.append(dt)
	times.sort()
	return times[times.size() / 2]


func _report() -> void:
	var base: float = _median(_samples[0])
	print("")
	print("══ FILL COST — median frame time, static stage, vsync off, %d laps ══" % _laps)
	print("  %-28s %9s %9s %9s" % ["config", "ms", "vs base", "spread"])
	for i: int in CONFIGS.size():
		var laps: Array = _samples[i]
		var m: float = _median(laps)
		var lo: float = laps.min()
		var hi: float = laps.max()
		var pct: float = (m - base) / maxf(base, 0.0001) * 100.0
		print("  %-28s %9.3f %+8.1f%% %9s"
			% [CONFIGS[i]["name"], m, pct, "%.2f-%.2f" % [lo, hi]])
	print("")
	print("  Baseline = whatever project.godot currently ships. A row within ~5%% of")
	print("  baseline is NOT a measured difference on this instrument — see the header.")


func _median(a: Array) -> float:
	var b: Array = a.duplicate()
	b.sort()
	if b.is_empty():
		return 0.0
	return float(b[b.size() / 2])
