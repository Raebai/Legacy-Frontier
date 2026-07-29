# Visual verification for the IMPACT FRAME vocabulary + the arbiter (agent-owned;
# safe to delete). GUI binary required — the dummy renderer under --headless
# writes blank PNGs, and a blank PNG looks exactly like a mark that did not draw:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/impact_frame_capture.gd
#
# Impact frames are ENTIRELY a look. "Tests green" verifies the referee
# (tools/slice9_test_impact_frames.gd) and says nothing whatsoever about whether
# the frames are epic, so this renders every style over a staged fight — two
# fighters, a floor, and a bright spell shape — and saves the beat at two points
# in its life. What to look for, per style, is written on each RUN below.
#
# ⚠ WHY THE BEAT IS SAMPLED BY POKING `_start_us` RATHER THAN BY WAITING.
# The frames deliberately run on the REAL clock (see ImpactFrame's header), so
# "wait four physics frames and screenshot" samples a different point in the beat
# on every machine and every run — and a capture whose sample point drifts looks
# exactly like an effect that is broken. Rewinding the node's own start stamp
# puts the sample at an EXACT fraction of the beat, reproducibly.
#
# The staged spell shape (a bright eight-spoke wheel + a lance) is the whole
# point of the comparison: the recorded reason three ults in this codebase
# DELETED their impact frames was that a white blow-out buried the shape that
# identified them. Every "after" frame below has to be judged on whether the
# wheel and the lance are still readable.
extends SceneTree

const OUT_DIR: String = "user://"
## Where the "hit" is, in world space. Deliberately NOT the centre of the frame:
## a mark that only looks right when the blast is dead centre is the bug the
## world-position parameter was added to fix.
const HIT: Vector2 = Vector2(180.0, -40.0)
const CAM_AT: Vector2 = Vector2(0.0, 40.0)
const CAM_ZOOM: float = 0.55

## [file label, style, strength, element, lines, "what to look for"]
const RUNS: Array = [
	# --- THE BEFORE. The single white blow-out that every one of these moments
	# used to get, whatever the moment was.
	["before_blowout", ImpactFrame.Style.BLOWOUT, 1.15, -1, true,
		"BEFORE: white wash. The wheel + lance should be hard to make out."],
	# --- THE AFTER, per moment.
	["basic_local", ImpactFrame.Style.LOCAL, 0.55, -1, true,
		"A basic hit / a kill: a small ring ON the hit. Must not touch the rest of the screen."],
	["heavy_blowout", ImpactFrame.Style.BLOWOUT, 0.80, -1, true,
		"A heavy spell: the white pop, but weaker + shorter than the old ult one."],
	["ult_field_fire", ImpactFrame.Style.COLOR_FIELD, 1.15, Elements.Element.FIRE, true,
		"A FIRE ult: the screen goes orange. Compare with ult_field_ice — they must differ."],
	["ult_field_ice", ImpactFrame.Style.COLOR_FIELD, 1.15, Elements.Element.ICE, true,
		"An ICE ult: the screen goes cyan. This is the 'they're all recolours' fix."],
	["ult_silhouette", ImpactFrame.Style.SILHOUETTE, 1.25, -1, false,
		"A shape-payoff ult (beam / spoke wheel): black cut. The WHEEL AND LANCE MUST STILL READ."],
	["shadow_invert", ImpactFrame.Style.INVERT, 1.0, -1, true,
		"The shadow family: a negative. Everything still legible, everything wrong."],
	["climax_cutin", ImpactFrame.Style.CUT_IN, 1.40, -1, true,
		"A boss death: bars slam in, FIGHTERS STAY DRAWN in the band, slash across the hit."],
	# --- the accessibility path, rendered so it can be judged as an effect and
	# not merely trusted as a flag.
	["reduced_from_cutin", -1, 1.40, -1, true,
		"reduce_flashing ON, asking for the CUT_IN: must come out as the small ring."],
]

## Points in the beat to sample, as a fraction of its duration.
const SAMPLES: Array = [[0.12, "a_peak"], [0.55, "b_tail"]]

var _scene: Node2D = null
var _cam: Camera2D = null


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await physics_frame
	# Hit-stop off for the whole capture: the marks are being judged, and a
	# time-scale of 0.05 changes nothing about how they DRAW while making every
	# await in this file take twenty times as long.
	var tuning: Node = root.get_node_or_null(^"/root/Tuning")
	_scene = _build_arena()
	root.add_child(_scene)
	_cam.make_current()
	for i in 20:
		await physics_frame
	for entry: Array in RUNS:
		var reduced: bool = int(entry[1]) < 0
		if tuning != null and tuning.get(&"cfg") != null:
			tuning.cfg.set(&"hit_stop_enabled", false)
			tuning.cfg.set(&"reduce_flashing", reduced)
		await _capture_style(entry, reduced)
	if tuning != null and tuning.get(&"cfg") != null:
		tuning.cfg.set(&"reduce_flashing", false)
	await _capture_barrage()
	quit(0)


## Render ONE style at two points in its beat.
func _capture_style(entry: Array, reduced: bool) -> void:
	var label: String = entry[0]
	var style: int = ImpactFrame.Style.CUT_IN if reduced else int(entry[1])
	print("ifcap --- %s : %s" % [label, entry[5]])
	ImpactFrame.reset_arbiter()   # each style is judged on its own, not budgeted
	var decision: Dictionary = ImpactFrame.decide({
		"style": style, "strength": float(entry[2]),
	})
	if not bool(decision["granted"]):
		printerr("ifcap: %s was REFUSED by the arbiter (%s) — nothing to look at"
			% [label, decision["reason"]])
		return
	if reduced:
		print("ifcap   reduce_flashing downgraded style %d -> %d" % [style, int(decision["style"])])
	var element: int = int(entry[3])
	var tint: Color = Elements.color(element) if element >= 0 else Color(1, 1, 1)
	var f: ImpactFrame = ImpactFrame.spawn(decision, HIT, tint, bool(entry[4]))
	if f == null:
		printerr("ifcap: %s produced no node" % label)
		return
	var dur: float = float(decision["duration"])
	# Freeze the node's own clock. Saving a PNG costs far more real time than the
	# shortest mark's whole life (INVERT is 0.07 s), so a frame left running its
	# own timer expires between two screenshots and the capture renders nothing.
	f.set_process(false)
	for s: Array in SAMPLES:
		f.apply_beat(float(s[0]) * dur)
		await _save("if_%s_%s.png" % [label, s[1]])
	f.queue_free()
	await physics_frame
	# Clear the slot before the next style so it is judged fresh.
	ImpactFrame.reset_arbiter()


## THE BARRAGE — the proof the arbiter holds against the LIVE clock in the real
## engine, not the injected one the headless suite uses. Twenty requests with
## ASCENDING strength (the adversarial case: every one of them is entitled to
## supersede the one before it) fired as fast as the engine will run them.
##
## ⚠ THE MEASUREMENT, NOT THE COUNT, IS THE RESULT. The first version of this
## asserted "at most 2 of 20 became marks" and reported a strobe — wrongly.
## Saving a PNG costs tens of milliseconds, so the twenty requests were spread
## across several real seconds and six marks over several seconds is the ceiling
## working exactly as specified. The rule is per SECOND, so the check has to be
## per second: record when each mark started and find the worst one-second window
## anywhere on the timeline. No screenshots inside the loop, for the same reason.
func _capture_barrage() -> void:
	ImpactFrame.reset_arbiter()
	print("ifcap --- barrage : 20 ascending requests, no saves (they distort the clock).")
	var starts: Array[int] = []
	var t0: int = Time.get_ticks_msec()
	for i in 20:
		if Juice.frame({
				"style": ImpactFrame.Style.BLOWOUT,
				"strength": 0.3 + 0.065 * float(i), "at": HIT,
				"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0}):
			starts.append(Time.get_ticks_msec())
		for k in 3:
			await physics_frame
	var span: int = Time.get_ticks_msec() - t0
	var worst: int = 0
	for s: int in starts:
		var n: int = 0
		for o: int in starts:
			if o >= s and o < s + 1000:
				n += 1
		worst = maxi(worst, n)
	print("ifcap barrage: %d of 20 became marks over %d ms; worst 1s window = %d (ceiling %d)"
		% [starts.size(), span, worst, ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND])
	if worst > ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND:
		printerr("ifcap: BARRAGE STROBED — %d flashes inside one second" % worst)
	else:
		print("ifcap barrage: NO STROBE — the ceiling held under the live clock.")
	# ...and one look at what a barrage actually shows, sampled well apart so the
	# saves cannot distort what they are measuring.
	ImpactFrame.reset_arbiter()
	for shot in 4:
		Juice.frame({"style": ImpactFrame.Style.BLOWOUT, "strength": 0.5 + 0.3 * float(shot),
			"at": HIT, "zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
		await _save("if_barrage_%02d.png" % shot)


## A staged fight to judge the marks against: a floor, blocks for scale, two
## fighter silhouettes, and a bright spell shape (spoke wheel + lance) at the hit.
## The spell shape is the actual subject of the test — see the file header.
func _build_arena() -> Node2D:
	RenderingServer.set_default_clear_color(Color(0.13, 0.14, 0.18))
	var arena := Node2D.new()
	Atmosphere.add_glow(arena)   # 2D bloom, so the HDR cores read as they will in game
	PostProcess.add(arena)       # the grade, and the backbuffer the INVERT style samples
	_rect(arena, Vector2(0.0, 300.0), Vector2(2400.0, 120.0), Color(0.20, 0.22, 0.27), -5)
	for x: float in [-520.0, -260.0, 60.0, 380.0, 620.0]:
		_rect(arena, Vector2(x, 206.0), Vector2(70.0, 70.0), Color(0.26, 0.28, 0.34), -4)
	# Two fighters, as plain silhouettes. Their job is to answer one question per
	# style: can you still tell who is where?
	_figure(arena, Vector2(-120.0, 200.0), Color(0.55, 0.78, 1.0))
	_figure(arena, Vector2(250.0, 200.0), Color(1.0, 0.55, 0.35))
	# The spell shape at the hit: eight bright spokes + a lance, standing in for
	# StarConvergence's wheel and HollowPurple's lance.
	var spell := Node2D.new()
	spell.position = HIT
	spell.z_index = 3
	spell.draw.connect(_draw_spell.bind(spell))
	arena.add_child(spell)
	_cam = Camera2D.new()
	_cam.position = CAM_AT
	_cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	# The mark projects the world hit position through the camera's canvas
	# transform, so the capture needs a REAL camera or every frame would draw at
	# viewport centre and prove nothing about the thing this parameter fixed.
	arena.add_child(_cam)
	return arena


func _draw_spell(node: Node2D) -> void:
	var em := Color(1.9, 1.2, 0.4, 1.0)
	for i in 8:
		var d: Vector2 = Vector2.from_angle(TAU * float(i) / 8.0)
		node.draw_line(d * 30.0, d * 210.0, em, 7.0, true)
	node.draw_line(Vector2(-420.0, 40.0), Vector2(520.0, -60.0), Color(1.8, 1.6, 2.2, 1.0), 13.0, true)
	node.draw_circle(Vector2.ZERO, 26.0, Color(2.0, 1.8, 1.4, 1.0), true, -1.0, true)


func _figure(parent: Node, at: Vector2, col: Color) -> void:
	_rect(parent, at, Vector2(18.0, 74.0), col, 2)
	_rect(parent, at - Vector2(0.0, 52.0), Vector2(28.0, 28.0), col, 2)


func _rect(parent: Node, at: Vector2, size: Vector2, col: Color, z: int) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	p.color = col
	p.position = at
	p.z_index = z
	parent.add_child(p)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + fname)
		print("ifcap saved ", fname)
