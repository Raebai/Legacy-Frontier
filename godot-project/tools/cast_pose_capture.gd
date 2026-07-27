# Visual check for the per-spell CAST POSES (magic-overhaul rule 4). Renders the
# rig mid-windup in each CastStyle.Pose so the body language can be compared.
# GUI binary (must render):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/cast_pose_capture.gd
extends SceneTree

## Fractions THROUGH each pose's own window to shoot at. Fixed frame counts don't
## work: the windows differ per pose (a lash is 0.18s, a channel 0.46s), so frame
## 20 is the release of one and the anticipation of another. Proportional shots
## make the poses actually comparable.
const EARLY_FRAC: float = 0.35
const LATE_FRAC: float = 0.85
## The rig is ~40px tall in a 1280-wide arena shot — arm angles are a few pixels
## at default zoom, which is useless for judging body language. Push in.
const REVIEW_ZOOM: float = 3.0

var _scene: Node
var _fig: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	for i in 90:
		await physics_frame          # let the figure settle on the floor
	_fig = _scene.get("_fig")
	# The HUD covers the top third of the frame and makes the rig hard to read.
	var hud: Node = _scene.get("_hud")
	if hud != null and hud is CanvasItem:
		(hud as CanvasItem).visible = false
	var cam: Node = _scene.get("_cam")
	if cam != null and cam is Camera2D:
		(cam as Camera2D).zoom = Vector2(REVIEW_ZOOM, REVIEW_ZOOM)
	for pose: Array in [
		[CastStyle.Pose.POINT, "point"],
		[CastStyle.Pose.SLAM, "slam"],
		[CastStyle.Pose.CIRCLE, "circle"],
		[CastStyle.Pose.CHANNEL, "channel"],
		[CastStyle.Pose.COIL, "coil"],
		[CastStyle.Pose.LASH, "lash"],
		[CastStyle.Pose.SWEEP, "sweep"],
		[CastStyle.Pose.THROW, "throw"],
	]:
		await _shoot(int(pose[0]), String(pose[1]))
	quit(0)


## Fire one pose (no spell — the BODY is what's under review) and shoot it at the
## same two points through its own window, whatever that window's length.
func _shoot(pose: int, name: String) -> void:
	var total: int = maxi(2, int(CastStyle.duration(pose) * float(Engine.physics_ticks_per_second)))
	var early: int = maxi(1, int(float(total) * EARLY_FRAC))
	var late: int = maxi(early + 1, int(float(total) * LATE_FRAC))
	_fig.call("cast", Vector2.RIGHT, pose)
	for i in early:
		await physics_frame
	await _save("cast_%s_early.png" % name)
	for i in (late - early):
		await physics_frame
	await _save("cast_%s_late.png" % name)
	for i in 50:
		await physics_frame          # let the rig settle before the next pose
	await physics_frame


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("castcap saved ", fname)
