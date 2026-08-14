# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/weather_perf_probe.gd
#
# WHAT DOES THE FLOOR'S AIR ACTUALLY COST? Weather is drawn in front of the fighters on
# every floor, so "it looks fine on my desktop" is not an answer — the target is a
# phone, where alpha-blended overdraw is the thing tile GPUs are worst at.
#
# ⚠ THIS PROBE DELIBERATELY DOES NOT REPORT FRAME TIME, AND THAT IS THE HONEST CHOICE.
# Two attempts were made and both produced confident garbage:
#   * `TIME_PROCESS` is the SCRIPT's idle-process time. It read 53.488 ms for five
#     consecutive rows and 10.780 for the rest — a warm-up staircase, not a cost.
#   * `TIME_FPS` in a `--script` main loop read 1.000, then 2007.000. There is no real
#     scene driving frames, so the monitor is measuring the probe's own await loop.
# A number that moves by 2000 between identical measurements cannot detect an effect
# of a few percent. Rather than print it with a caveat nobody reads, it is gone. Frame
# time is a DEVICE measurement; take it with the in-game PerfOverlay (F3) on the phone.
#
# What it reports instead, all three of which are real:
#   COUNT       the emitter's LIVE amount, read back off the node — what shipped, not
#               what the table asked for, because `_weather_amount` may have capped it.
#   PRIMITIVES  measured. Two triangles per live particle; the direct GPU-side cost.
#   DRAW CALLS  measured. A GPUParticles2D is ONE call however many particles it draws,
#               so this is the number that says whether the field batches.
#   FILL        derived: count x (PARTICLE_PX x mean scale)^2 as a share of the 640x360
#               base viewport. THE MOBILE NUMBER. Overdraw is what costs on a tile GPU,
#               and overdraw is area, not particle count — a field of 20 big soft quads
#               is worse than 50 small ones and the count column alone hides that.
extends SceneTree

const GAMESTATE_PATH: String = "res://scripts/GameState.gd"
const ATMOSPHERE_PATH: String = "res://scripts/combat/Atmosphere.gd"

const SETTLE_FRAMES: int = 100
const SAMPLE_FRAMES: int = 180
## The base viewport weather is sized against (project stretch is 640x360).
const SCREEN_PX: float = 640.0 * 360.0

const KIND_NAMES: Array[String] = [
	"NONE (baseline)", "ASH", "LEAVES", "SNOW", "EMBERS",
	"BUBBLES", "RAIN", "GLINT", "STARFALL",
]

var _atmo: Node = null
var _rows: Array = []


func _initialize() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := Node2D.new()
	root.add_child(world)
	var room := ColorRect.new()
	room.size = Vector2(640, 360)
	room.color = Color(0.24, 0.34, 0.20)
	room.z_index = -10
	world.add_child(room)
	var cam := Camera2D.new()
	cam.position = Vector2(320, 180)
	world.add_child(cam)
	cam.zoom = Vector2.ONE * (1366.0 / 640.0)
	cam.call_deferred("make_current")
	_atmo = (load(ATMOSPHERE_PATH) as GDScript).new()
	root.add_child(_atmo)
	_run()


func _run() -> void:
	var gs: GDScript = load(GAMESTATE_PATH) as GDScript
	if gs == null:
		printerr("weather_perf: could not load GameState")
		quit(1)
		return
	var theme: Resource = gs.floor_env(2) as Resource
	var wash: Color = theme.lit_wash()
	var accent: Color = theme.accent()
	for kind: int in range(KIND_NAMES.size()):
		_atmo.call("build_wash", wash, accent)
		_atmo.call("build_weather", kind, accent)
		await _wait(SETTLE_FRAMES)
		_rows.append(await _sample(KIND_NAMES[kind]))
	_report()
	quit(0)


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame


func _sample(label: String) -> Dictionary:
	var calls: float = 0.0
	var prims: float = 0.0
	for _i: int in SAMPLE_FRAMES:
		await process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var n: float = float(SAMPLE_FRAMES)
	var live: GPUParticles2D = _live_emitter()
	var amount: int = 0
	var fill: float = 0.0
	if live != null:
		amount = live.amount
		var mat: ParticleProcessMaterial = live.process_material as ParticleProcessMaterial
		if mat != null:
			var mean_scale: float = (mat.scale_min + mat.scale_max) * 0.5
			var px: float = float(_atmo.get_script().get_script_constant_map()
				.get("PARTICLE_PX", 32)) * mean_scale
			fill = (float(amount) * px * px) / SCREEN_PX * 100.0
	return {"label": label, "calls": calls / n, "prims": prims / n,
		"amount": amount, "fill": fill}


## Read back off the LIVE node. A probe that reports the request rather than the
## result is the class of instrument this repo has been burned by before.
func _live_emitter() -> GPUParticles2D:
	var layer: Node = _atmo.get_node_or_null("Weather")
	if layer == null:
		return null
	for c: Node in layer.get_children():
		if c is GPUParticles2D:
			return c as GPUParticles2D
	return null


func _report() -> void:
	var base: Dictionary = _rows[0]
	print("")
	print("WEATHER COST — %d frames per row, uncapped, vsync off" % SAMPLE_FRAMES)
	print("=".repeat(72))
	print("%-18s %7s %11s %7s %10s" % ["kind", "count", "primitives", "calls", "fill %"])
	print("-".repeat(72))
	for r: Dictionary in _rows:
		print("%-18s %7d %11.0f %7.1f %9.2f%%" % [
			r["label"], int(r["amount"]), float(r["prims"]),
			float(r["calls"]), float(r["fill"])])
	print("=".repeat(72))
	var worst_fill: float = 0.0
	var worst_label: String = ""
	var worst_prims: float = float(base["prims"])
	for r: Dictionary in _rows:
		if float(r["fill"]) > worst_fill:
			worst_fill = float(r["fill"])
			worst_label = String(r["label"])
		worst_prims = maxf(worst_prims, float(r["prims"]))
	print("DRAW CALLS  %.0f -> %.0f   (+1: the whole field is one batched call)"
		% [float(base["calls"]), float(_rows[1]["calls"])])
	print("PRIMITIVES  %.0f -> %.0f worst case (+%.0f)"
		% [float(base["prims"]), worst_prims, worst_prims - float(base["prims"])])
	print("FILL        %.2f%% of one screen, worst case (%s)" % [worst_fill, worst_label])
	print("")
	# The verdict, stated against a threshold rather than as an opinion.
	if worst_fill < 5.0:
		print("VERDICT: negligible. The worst floor's air covers %.2f%% of one screen"
			% worst_fill)  # %% is literal here: the format arg is consumed above
		print("  and adds ONE draw call. For scale, a single full-screen ColorRect is")
		print("  100% fill and the wash tint + vignette already pay that twice.")
	elif worst_fill < 15.0:
		print("VERDICT: acceptable but worth watching on a device (%.2f%% fill)." % worst_fill)
	else:
		print("VERDICT: TOO EXPENSIVE for a field drawn in front of the fighters")
		print("  (%.2f%% fill). Cut the count or the scale on the worst kinds." % worst_fill)
	print("Frame time is NOT measurable in this harness — see the header. Take it on")
	print("the phone with PerfOverlay (F3).")
