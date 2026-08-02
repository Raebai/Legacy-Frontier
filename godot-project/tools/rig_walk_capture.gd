# THE MAKER'S COMPLAINT IS ABOUT HOW THE WALK LOOKS, SO LOOK AT IT.
#
# A Muybridge strip of one walk: the camera is LOCKED, the floor is ruled, and the
# figure's pose is stamped onto the image every few frames as it crosses. Read it like
# a contact sheet —
#
#   * A WORLD-LOCKED foot appears at the SAME x in consecutive stamps and only the body
#     moves over it. A skating foot creeps forward in every stamp. That is the maker's
#     "walking on their legs" and it is visible here and nowhere else.
#   * The white tick under the floor is dropped on each `foot_planted`, at the plant's
#     real world x. Count them to read the CADENCE; measure between them to read the
#     STRIDE. A buzz shows up as a picket fence.
#   * The floor is ruled every 8 px (tall tick every 40) so a foot can be judged
#     against a fixed reference rather than against a memory of the last run.
#
# GUI binary — the headless one draws nothing and still reports success:
#   python python-tools/run_capture.py rig_walk
#
# ++tag=before / ++tag=after names the output, so a before/after is two runs of one
# binary rather than a memory of one. The `after` run also stitches whatever
# rigwalk_before.png it finds above its own row, so the comparison is ONE image:
#   user://rigwalk_<tag>.png        one rig, one walk
#   user://rigwalk_compare.png      before over after, written by the `after` run
#   user://rigwalk_spike.png        SpikeFigure doing the same walk, for the A/B
#
# ++speed=210 walks at Hero.SPEED (the default). ++spike=1 renders SpikeFigure instead,
# scaled and sped so it is the SAME body-size on screen moving at the SAME body-relative
# speed — the only comparison between an 86 px rig and a 31 px one that means anything.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const SPIKE_PATH: String = "res://scripts/spike/SpikeFigure.gd"
const GHOST_PATH: String = "res://scripts/combat/RigGhost.gd"
const RIG_H: float = 31.0
const SPIKE_H: float = 86.0
## Chosen so the 31 px figure is ~250 screen px tall and a whole gait cycle fits.
var ZOOM: float = 4.0
const FLOOR_Y: float = 60.0
const START_X: float = -68.0
## Sample every Nth physics frame. Dense enough to show the swing, sparse enough that
## the stamps do not merge into a smear.
var STAMP_EVERY: int = 13
var FRAMES: int = 118

var _world: Node2D
var _tag: String = "after"
var _speed: float = 210.0
var _spike: bool = false
var _plants: Array[float] = []
var _zoom: float = ZOOM


func _initialize() -> void:
	# 120 Hz: what both spike hosts force, so the two rigs are compared on the clock the
	# feel was signed off at. The shipped 60 Hz row is the tick-rate suite's job.
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_parse_args()
	_run()


## The capture runs inside the full game project, so the autoload HUD layers (rank
## banner, dimmers) render over the shot. Runtime visibility only; touches no game code.
func _hide_overlays() -> void:
	for child: Node in root.get_children():
		if child == _world:
			continue
		_hide_canvases(child)


func _hide_canvases(n: Node) -> void:
	if n is CanvasLayer or n is CanvasItem:
		(n as Node).set("visible", false)
		return
	for c: Node in n.get_children():
		_hide_canvases(c)


func _run() -> void:
	await process_frame
	if _spike:
		await _spike_strip()
	else:
		await _rig_strip()
	quit(0)


func _rig_strip() -> void:
	await _fresh_world(ZOOM)
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", RIG_H)
	_world.add_child(rig)
	rig.position = Vector2(-320.0 / ZOOM + 12.0, FLOOR_Y - RIG_H * 0.5)
	rig.call("set_grounded", true)
	rig.call("play", 0)
	rig.connect("foot_planted", Callable(self, "_on_plant").bind(rig))
	var dt: float = 1.0 / 120.0
	for _i: int in 40:
		rig.call("advance", dt)
	rig.call("play", 1)   # RUN
	for i: int in FRAMES:
		rig.position.x += _speed * dt
		rig.call("set_body_velocity", Vector2(_speed, 0.0))
		rig.call("advance", dt)
		if i % STAMP_EVERY == 0:
			_stamp(rig.call("_sim_pose"), rig.global_transform, RIG_H,
				float(i) / float(FRAMES))
	_label("%s  —  CharacterRig %.0f px at %.0f px/s (%.1f body-heights/s), %d plants"
			% [_tag, RIG_H, _speed, _speed / RIG_H, _plants.size()])
	await _save("rigwalk_%s.png" % _tag)
	if _tag == "after":
		await _compose()


## SpikeFigure walking the same walk, drawn at the same ON-SCREEN size and the same
## BODY-RELATIVE speed. Real physics: its torso is a RigidBody2D, so it is driven by
## holding right rather than by translating it.
func _spike_strip() -> void:
	var spike_speed: float = _speed * SPIKE_H / RIG_H
	await _fresh_world(ZOOM * RIG_H / SPIKE_H)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40000.0, 60.0)
	cs.shape = rect
	cs.position = Vector2(0.0, 30.0)
	body.add_child(cs)
	body.position = Vector2(0.0, FLOOR_Y)
	_world.add_child(body)
	var fig: Node2D = (load(SPIKE_PATH) as GDScript).new() as Node2D
	# Spawn far enough left that the run-up happens OFF camera and the figure enters
	# the framed floor exactly as the strip starts — whatever zoom was asked for.
	var zoom_s: float = ZOOM * RIG_H / SPIKE_H
	var left_edge: float = -320.0 / zoom_s
	fig.set("spawn_pos", Vector2(left_edge - 160.0 / 120.0 * spike_speed, FLOOR_Y - 60.0))
	fig.set("move_speed", spike_speed)
	_world.add_child(fig)
	for _i: int in 80:
		await physics_frame
	# Run it up to speed OFF-CAMERA, then let it cross the framed floor.
	for _i: int in 160:
		fig.set("ctrl_move_x", 1.0)
		await physics_frame
	for i: int in FRAMES:
		fig.set("ctrl_move_x", 1.0)
		await physics_frame
		if i % STAMP_EVERY == 0:
			_stamp_spike(fig, float(i) / float(FRAMES))
	_label("spike  —  SpikeFigure %.0f px at %.0f px/s (%.1f body-heights/s)"
			% [SPIKE_H, spike_speed, spike_speed / SPIKE_H])
	await _save("rigwalk_spike.png")


func _on_plant(rig: Node2D) -> void:
	_plants.append(rig.global_position.x)
	var tick := ColorRect.new()
	tick.size = Vector2(0.6, 7.0)
	tick.position = Vector2(rig.global_position.x - 0.3, FLOOR_Y + 1.0)
	tick.color = Color(1.0, 1.0, 1.0, 0.85)
	_world.add_child(tick)


## Freeze this frame's pose into the image as a persistent ghost. `fade_time` is set
## past the life of the capture so nothing fades out from under the shot.
func _stamp(pose: Dictionary, xform: Transform2D, h: float, t: float) -> void:
	var g: Node2D = (load(GHOST_PATH) as GDScript).new() as Node2D
	g.set("pose", pose)
	g.set("equipment_slots", {})
	g.set("fig_height", h)
	g.set("fade_time", 1.0e6)
	# Older stamps dimmer, newest brightest: the direction of travel is then obvious
	# even though every stamp is the same figure.
	g.set("base_color", Color(0.45, 0.72, 1.0, 0.34 + 0.60 * t))
	_world.add_child(g)
	g.global_transform = xform


## The spike draws itself out of Line2D children rather than an immediate-mode pose, so
## it cannot be ghosted the same way. Stamp its SKELETON instead — the same joints, from
## its own public state — which is exactly what is being compared.
func _stamp_spike(fig: Node2D, t: float) -> void:
	var col := Color(1.0, 0.72, 0.35, 0.22 + 0.55 * t)
	var feet: Array = fig.get("_foot")
	var knees: Array = fig.get("_knee")
	# SpikeFigure.HIP_OFF / NECK_Y, in the torso's own (possibly pitched) frame.
	var torso: Node2D = fig.get("_torso") as Node2D
	if torso == null:
		return
	var hip: Vector2 = torso.to_global(Vector2(0.0, 12.0))
	var neck: Vector2 = torso.to_global(Vector2(0.0, -14.0))
	for i: int in 2:
		_line(hip, knees[i] as Vector2, col)
		_line(knees[i] as Vector2, feet[i] as Vector2, col)
	_line(hip, neck, col)


func _line(a: Vector2, b: Vector2, col: Color) -> void:
	var ln := Line2D.new()
	ln.points = PackedVector2Array([a, b])
	ln.width = 5.5
	ln.default_color = col
	ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ln.end_cap_mode = Line2D.LINE_CAP_ROUND
	_world.add_child(ln)


## An opaque backdrop, a REAL StaticBody2D floor on layer 1 (so the rig's downward
## ground probe finds ground and the foot-plant IK engages exactly as it does in the
## arena), and a ruler. Comparing a foot against a fixed reference is the only way to
## judge a plant from a still.
func _fresh_world(zoom: float) -> void:
	_zoom = zoom
	_world = Node2D.new()
	root.add_child(_world)
	var bg := ColorRect.new()
	bg.size = Vector2(8000, 4000)
	bg.position = Vector2(-4000, -2000)
	bg.color = Color(0.13, 0.14, 0.18)
	_world.add_child(bg)
	if not _spike:
		var solid := StaticBody2D.new()
		solid.collision_layer = 1
		solid.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(8000, 40)
		cs.shape = rect
		cs.position = Vector2(0, 20)
		solid.add_child(cs)
		solid.position = Vector2(0, FLOOR_Y)
		_world.add_child(solid)
	var paint := ColorRect.new()
	paint.size = Vector2(8000, 40)
	paint.position = Vector2(-4000, FLOOR_Y)
	paint.color = Color(0.21, 0.23, 0.27)
	_world.add_child(paint)
	for i: int in 800:
		var x: float = -1600.0 + float(i) * 8.0
		var tall: bool = int(round(x)) % 40 == 0
		var tick := ColorRect.new()
		tick.size = Vector2(0.5, 9.0 if tall else 4.0)
		tick.position = Vector2(x, FLOOR_Y - (9.0 if tall else 4.0))
		tick.color = Color(0.42, 0.45, 0.52) if tall else Color(0.30, 0.32, 0.38)
		_world.add_child(tick)
	var cam := Camera2D.new()
	cam.zoom = Vector2(zoom, zoom)
	# Frame the floor near the bottom whatever the zoom: visible height is 360/zoom.
	cam.position = Vector2(0.0, FLOOR_Y - 360.0 / zoom * 0.30)
	_world.add_child(cam)
	cam.make_current()
	await process_frame
	_hide_overlays()
	await process_frame


## A Label lives in a WORLD the camera zooms and the 640x360 design canvas stretches
## again, so its font arrives ~8x magnified. Scaling the node back down is the fix.
func _label(text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	lab.add_theme_font_size_override("font_size", 16)
	var sc: float = 0.11 * ZOOM / _zoom
	lab.scale = Vector2(sc, sc)
	var cam_left: float = -320.0 / _zoom
	lab.position = Vector2(cam_left + 4.0, FLOOR_Y - 360.0 / _zoom * 0.28)
	_world.add_child(lab)


## Stack the `before` row above this `after` one, so the comparison survives as a file
## rather than as a memory of two files.
func _compose() -> void:
	var before: Image = Image.load_from_file(
		ProjectSettings.globalize_path("user://rigwalk_before.png"))
	var after: Image = Image.load_from_file(
		ProjectSettings.globalize_path("user://rigwalk_after.png"))
	if before == null or after == null:
		print("rigwalk: no before row to compose against — run with ++tag=before first")
		return
	var out := Image.create(before.get_width(),
		before.get_height() + after.get_height(), false, before.get_format())
	out.blit_rect(before, Rect2i(Vector2i.ZERO, before.get_size()), Vector2i.ZERO)
	out.blit_rect(after, Rect2i(Vector2i.ZERO, after.get_size()),
		Vector2i(0, before.get_height()))
	out.save_png("user://rigwalk_compare.png")
	print("rigwalk saved rigwalk_compare.png")


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("rigwalk saved ", fname)


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_user_args())
	argv.append_array(OS.get_cmdline_args())
	for raw: String in argv:
		var arg: String = raw.lstrip("+-")
		if not arg.contains("="):
			continue
		var k: String = arg.get_slice("=", 0)
		var v: String = arg.get_slice("=", 1)
		match k:
			"tag":
				_tag = v
			"speed":
				_speed = float(v)
			"spike":
				_spike = v != "0"
			"zoom":
				ZOOM = float(v)
			"every":
				STAMP_EVERY = int(v)
			"frames":
				FRAMES = int(v)
