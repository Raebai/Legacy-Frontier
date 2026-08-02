# THE MAKER'S COMPLAINT IS ABOUT HOW THE WALK LOOKS, SO LOOK AT IT.
#
# Renders the same walk twice in one image: the top figure advanced at 1/60 (what the
# shipped game runs, `project.godot [physics]`), the bottom at 1/120 (what both spike
# hosts force, and therefore the only tick rate the rig's hand-tuned numbers were ever
# signed off at). Same speed, same distance, same floor, same instant — so the two rows
# should be the SAME POSE in every frame. Where they are not, the rig is a different
# character in the game than the one that was approved.
#
# GUI binary — the headless one draws nothing and still reports success:
#   python python-tools/run_capture.py rig_tickrate
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/rig_tickrate_capture.gd
#
# ++tag=<name> renames the output, so a before/after is two runs of ONE binary rather
# than a memory of one:
#   ++tag=after   (default)
#
# Writes to user:// (%APPDATA%\Godot\app_userdata\Legacy Frontier\):
#   rigtick_<tag>_walk_N.png   eight frames across one continuous walk, both clocks
#   rigtick_<tag>_strip.png    the whole cycle as one contact sheet
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const RIG_H: float = 31.0
## Hero.SPEED. The gait's step cycle is narrowest in frames at full run, which is where
## a tick-rate difference shows; an amble would hide it.
const WALK_SPEED: float = 210.0
## Floor lines for the two rows, and the framing that shows BOTH figures whole.
## Worked out rather than eyeballed: the project stretches a 640x360 design canvas, so
## at zoom Z the visible height is 360/Z. The rows must contain the top figure's head
## (FLOOR_A - RIG_H) down to the bottom figure's feet (FLOOR_B) with margin, or the
## capture silently crops the very thing it exists to show — which is what the first
## run of this tool did.
const FLOOR_A: float = 260.0    # 60 Hz row
const FLOOR_B: float = 330.0    # 120 Hz row
const CAM_Y: float = 280.0
const CAM_ZOOM: float = 2.6
const FRAMES: int = 64
const SHOTS: int = 8

var _world: Node2D
var _tag: String = "after"


func _initialize() -> void:
	# The rig is driven by hand here (`advance`), so the engine's own tick rate does not
	# matter — but pin it anyway so nothing else in the frame drifts between runs.
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(1280, 720)
	_parse_args()
	_run()


func _run() -> void:
	await process_frame
	await _walk_compare()
	quit(0)


## Both rigs, both clocks, one continuous walk, camera LOCKED so the ruled floor stays
## put and any disagreement is read directly against it.
func _walk_compare() -> void:
	await _fresh_world(CAM_ZOOM, Vector2(0.0, CAM_Y))
	var rig_60: Node2D = _make_rig(-120.0, FLOOR_A, Color(0.4, 0.7, 1.0))
	var rig_120: Node2D = _make_rig(-120.0, FLOOR_B, Color(1.0, 0.72, 0.35))
	_label("60 Hz  (the shipped game)", FLOOR_A, Color(0.4, 0.7, 1.0))
	_label("120 Hz  (the spike playground the numbers were tuned in)", FLOOR_B,
		Color(1.0, 0.72, 0.35))
	rig_60.call("play", 1)    # RUN
	rig_120.call("play", 1)
	var dt: float = 1.0 / 60.0
	var shot: int = 0
	for i: int in FRAMES:
		# One 1/60 step for the top figure; TWO 1/120 steps for the bottom one, so both
		# have travelled the same distance in the same wall-clock time when we shoot.
		rig_60.position.x += WALK_SPEED * dt
		rig_60.call("set_body_velocity", Vector2(WALK_SPEED, 0.0))
		rig_60.call("advance", dt)
		for _h: int in 2:
			rig_120.position.x += WALK_SPEED * dt * 0.5
			rig_120.call("set_body_velocity", Vector2(WALK_SPEED, 0.0))
			rig_120.call("advance", dt * 0.5)
		if i % int(FRAMES / SHOTS) == 0 and shot < SHOTS:
			shot += 1
			await _save("rigtick_%s_walk_%d.png" % [_tag, shot])
	await _save("rigtick_%s_strip.png" % _tag)


## A world with an opaque backdrop and TWO real StaticBody2D floors on layer 1, so both
## rigs' downward ground probes find ground and the foot-plant IK engages exactly as it
## does in the arena. Ruled every 20 px: comparing a foot against a fixed reference is
## the only way to judge a plant from a still.
func _fresh_world(zoom: float, cam_at: Vector2) -> void:
	if _world != null:
		_world.queue_free()
		await process_frame
	_world = Node2D.new()
	root.add_child(_world)
	var bg := ColorRect.new()
	bg.size = Vector2(4000, 2000)
	bg.position = Vector2(-2000, -1000)
	bg.color = Color(0.14, 0.15, 0.19)
	_world.add_child(bg)
	for fy: float in [FLOOR_A, FLOOR_B]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(4000, 40)
		cs.shape = rect
		cs.position = Vector2(0, 20)
		body.add_child(cs)
		body.position = Vector2(0, fy)
		_world.add_child(body)
		var paint := ColorRect.new()
		paint.size = Vector2(4000, 40)
		paint.position = Vector2(-2000, fy)
		paint.color = Color(0.22, 0.24, 0.28)
		_world.add_child(paint)
		for i: int in 200:
			var tick := ColorRect.new()
			tick.size = Vector2(1, 8)
			tick.position = Vector2(-2000.0 + float(i) * 20.0, fy)
			tick.color = Color(0.36, 0.38, 0.44)
			_world.add_child(tick)
	var cam := Camera2D.new()
	cam.zoom = Vector2(zoom, zoom)
	cam.position = cam_at
	_world.add_child(cam)
	cam.make_current()
	await process_frame


## Name each row in the image itself. A two-row comparison that relies on the reader
## remembering which colour is which clock is a comparison that gets misread.
func _label(text: String, floor_y: float, tint: Color) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", tint)
	lab.add_theme_font_size_override("font_size", 16)
	# A Label is a Control living in a WORLD that is zoomed by the camera and then
	# stretched again by the 640x360 design canvas, so its font is magnified ~5x before
	# it reaches the PNG. Scaling the node back down is the fix; the first run left the
	# caption twice the height of the figure it was captioning and running off frame.
	lab.scale = Vector2(0.18, 0.18)
	lab.position = Vector2(-124.0, floor_y + 4.0)
	_world.add_child(lab)


func _make_rig(x: float, floor_y: float, tint: Color) -> Node2D:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", RIG_H)
	rig.set("limb_color", tint)
	_world.add_child(rig)
	rig.position = Vector2(x, floor_y - RIG_H * 0.5)
	rig.call("set_grounded", true)
	rig.call("play", 0)
	return rig


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("rigtick saved ", fname)


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_user_args())
	argv.append_array(OS.get_cmdline_args())
	for raw: String in argv:
		var arg: String = raw.lstrip("+-")
		if arg.begins_with("tag="):
			_tag = arg.get_slice("=", 1)
