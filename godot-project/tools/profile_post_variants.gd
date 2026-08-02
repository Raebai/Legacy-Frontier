# Run WITH THE GUI BINARY:
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/profile_post_variants.gd -- ++width=1920 ++height=1080 ++laps=9
#
# WHICH LINE OF post_process.gdshader COSTS WHAT.
#
# `tools/profile_fill_cost.gd` measures the grade as ONE row: turning it off saves
# about half the frame. That is enough to know it matters and not enough to do
# anything about it, because "the look" is not negotiable and deleting it is not a
# proposal anybody wants. So this takes the SHIPPING shader source, edits one thing
# at a time, and re-measures — which turns "the grade is expensive" into a list of
# individually-priced features that can be kept, cheapened or dropped on their own
# merits.
#
# The two suspects it exists to separate:
#
#   THE MIPMAP SAMPLER. `uniform sampler2D screen_tex : hint_screen_texture,
#   filter_linear_mipmap` makes the renderer build a full mipmap CHAIN of the
#   framebuffer every frame. The shader then samples it with screen-space UVs at
#   1:1, so the implicit derivatives are ~1 texel and every fetch lands on LOD 0.
#   The pyramid is built and never read. If that is what it costs, it is free to
#   remove and the image is bit-identical.
#
#   THE CHROMATIC ABERRATION. Three screen fetches instead of one, and the visible
#   red/blue fringing on every platform edge. Cost and readability point the same
#   way here, which is rare and worth knowing about precisely.
#
# Method is inherited wholesale from profile_fill_cost.gd — vsync off, tree paused
# so the geometry is identical between rows, round-robin laps so drift is shared,
# median of medians. Read its header for why each of those is load-bearing. Same
# caveat too: this is ONE desktop GPU, and the mipmap pyramid in particular is a
# bandwidth cost, which is where a phone differs from a 4070 most.
#
# Test-idiom note: a HARNESS, not an assertion suite — no pass/fail sentinels.
extends SceneTree

const DEFAULT_SCENE: String = "res://scenes/combat/Arena.tscn"
const SHADER_PATH: String = "res://scenes/combat/post_process.gdshader"
const SETTLE_SECONDS: float = 9.0
const FRAMES_PER_LAP: int = 26
const DISCARD_PER_LAP: int = 8

## Each variant is [name, Array of [find, replace] edits applied to the shipping
## source]. An edit whose `find` is absent is a LOUD failure, not a silent no-op —
## a variant that failed to apply would otherwise measure the baseline twice and
## report the feature as free.
const VARIANTS: Array = [
	["BASELINE (shipping shader)", []],
	# INVERTED ON PURPOSE. The shipping shader now samples `filter_linear`; this row
	# puts the mipmap chain BACK so the saving stays reproducible and a future reader
	# can re-derive it instead of taking the comment's word for it.
	["mipmap sampler RESTORED (the old cost)", [
		["hint_screen_texture, filter_linear;", "hint_screen_texture, filter_linear_mipmap;"],
	]],
	["no chromatic aberration (1 tap)", [
		["col.r = texture(screen_tex, uv + ab).r;", "col = texture(screen_tex, uv).rgb;"],
		["col.g = texture(screen_tex, uv).g;", ""],
		["col.b = texture(screen_tex, uv - ab).b;", ""],
	]],
	["no grain", [
		["uniform float grain = 0.025;", "uniform float grain = 0.0;"],
	]],
	# Same amount of noise, cheaper arithmetic. `sin()` of a ~1e6 argument is both
	# slow and precision-poor; the integer-ish variant is the standard replacement
	# and produces noise that is statistically identical and visually
	# indistinguishable — which is the whole bar a grain overlay has to clear.
	["cheap grain hash (same look)", [
		["return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);",
			"vec3 q = fract(vec3(p.xyx) * 0.1031);\n\tq += dot(q, q.yzx + 33.33);\n\treturn fract((q.x + q.y) * q.z);"],
	]],
	["no vignette", [
		["uniform float vignette_strength : hint_range(0.0, 1.0) = 0.34;",
			"uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;"],
	]],
	["also drop the aberration", [
		["col.r = texture(screen_tex, uv + ab).r;", "col = texture(screen_tex, uv).rgb;"],
		["col.g = texture(screen_tex, uv).g;", ""],
		["col.b = texture(screen_tex, uv - ab).b;", ""],
	]],
	["grade off entirely (rect hidden)", []],   # handled specially; the fill-cost bound
]

var _laps: int = 9
var _width: int = 1920
var _height: int = 1080
var _settled: float = 0.0
var _started: bool = false
var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _source: String = ""
var _shaders: Array = []
var _samples: Array = []


func _initialize() -> void:
	_parse_args()
	seed(20260802)
	if DisplayServer.get_name() == "headless":
		printerr("profile_post_variants: HEADLESS — no rasteriser, every row would tie.")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(_width, _height))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var src: Shader = load(SHADER_PATH) as Shader
	if src == null:
		printerr("profile_post_variants: could not load ", SHADER_PATH)
		quit(1)
		return
	_source = src.code
	var packed: PackedScene = load(DEFAULT_SCENE)
	root.add_child(packed.instantiate())
	for i: int in VARIANTS.size():
		_samples.append([])
	print("[post] window=%dx%d laps=%d vsync=off" % [_width, _height, _laps])


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var bits: PackedStringArray = arg.trim_prefix("++").split("=")
		if bits.size() != 2:
			continue
		match bits[0]:
			"laps": _laps = maxi(int(bits[1]), 1)
			"width": _width = maxi(int(bits[1]), 320)
			"height": _height = maxi(int(bits[1]), 180)


func _process(delta: float) -> bool:
	if _started:
		return false
	_settled += delta
	if _settled >= SETTLE_SECONDS:
		_started = true
		_run()
	return false


func _run() -> void:
	var pp: Node = root.get_tree().get_first_node_in_group(&"post_process")
	if pp == null:
		printerr("[post] no PostProcess in the arena — nothing to measure.")
		quit(1)
		return
	for r: Node in pp.find_children("*", "ColorRect", true, false):
		_rect = r as ColorRect
		break
	if _rect == null or not (_rect.material is ShaderMaterial):
		printerr("[post] the grade's ColorRect has no ShaderMaterial.")
		quit(1)
		return
	_mat = _rect.material as ShaderMaterial
	if not _build_variants():
		quit(1)
		return
	root.get_tree().paused = true
	print("[post] frozen stage: %d primitives"
		% int(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
	# A warm lap that touches every variant before any of them is scored: a shader
	# pays a one-off pipeline compile on first use, and charging that to whichever
	# variant happened to run first is how a harness invents a 30% regression.
	for i: int in VARIANTS.size():
		_apply(i)
		await _measure_lap()
	for lap: int in _laps:
		for i: int in VARIANTS.size():
			_apply(i)
			await _measure_lap()
			(_samples[i] as Array).append(await _measure_lap())
	_apply(0)
	_report()
	quit(0)


func _build_variants() -> bool:
	for v: Array in VARIANTS:
		var code: String = _source
		for edit: Array in (v[1] as Array):
			var find: String = edit[0]
			if not code.contains(find):
				printerr("[post] variant %s: pattern NOT FOUND in the shipping shader:" % v[0])
				printerr("       %s" % find)
				printerr("       The shader changed under this tool. Fix the pattern rather than")
				printerr("       letting the variant silently measure the baseline again.")
				return false
			code = code.replace(find, edit[1])
		var sh := Shader.new()
		sh.code = code
		_shaders.append(sh)
	return true


func _apply(i: int) -> void:
	var hide: bool = String(VARIANTS[i][0]).begins_with("grade off")
	_rect.visible = not hide
	if not hide:
		_mat.shader = _shaders[i]


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
	print("══ POST-PROCESS SHADER, FEATURE BY FEATURE — median ms, static stage, %d laps ══" % _laps)
	print("  %-34s %9s %9s %9s" % ["variant", "ms", "vs base", "spread"])
	for i: int in VARIANTS.size():
		var laps: Array = _samples[i]
		var m: float = _median(laps)
		var pct: float = (m - base) / maxf(base, 0.0001) * 100.0
		print("  %-34s %9.3f %+8.1f%% %9s"
			% [VARIANTS[i][0], m, pct, "%.2f-%.2f" % [laps.min(), laps.max()]])
	print("")
	print("  A row within ~5%% of baseline is not a measured difference on this")
	print("  instrument. `grade off entirely` is the floor any edit is working toward.")


func _median(a: Array) -> float:
	var b: Array = a.duplicate()
	b.sort()
	return 0.0 if b.is_empty() else float(b[b.size() / 2])
