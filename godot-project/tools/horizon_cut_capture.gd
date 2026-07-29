# Run with the GUI binary (the headless renderer draws nothing):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/horizon_cut_capture.gd
#
# HORIZON CUT, across its flight -> user://horizon_cut.png (2x2).
# The point of looking at this image is to check the two things a headless suite
# cannot: that the crescent READS as a curved wall of edge (hollow leading, tips
# ahead of the centre) rather than as a beam or a flat plate, and that it visibly
# WIDENS as it travels — which is the height band the whole spell is about.
#
#   [0] launch      narrow, close to the caster
#   [1] mid-flight  widening, the bow readable
#   [2] full extension at maximum half-height
#   [3] aimed diagonally, so the band is not confusable with "a horizontal beam"
extends SceneTree

const OUT: String = "user://horizon_cut.png"
const CELL: Vector2i = Vector2i(560, 315)
const ARC_PATH: String = "res://scripts/combat/HorizonArc.gd"

var _sheet: Image = null
var _world: Node2D = null


func _initialize() -> void:
	Engine.max_fps = 60
	_world = Node2D.new()
	root.add_child(_world)
	var bg := ColorRect.new()
	bg.position = Vector2(-2000, -2000)
	bg.size = Vector2(4000, 4000)
	bg.color = Color(0.10, 0.11, 0.16)
	bg.z_index = -10
	_world.add_child(bg)
	# Same ordering as tools/circle_capture.gd. Do NOT try to promote `_world` to
	# `current_scene` to make autoload lookups resolve — assigning it detaches the
	# world from the tree and the camera then refuses to become current. The
	# spectacle's own autoload helper already degrades to "no sound, no shake" when
	# there is nothing to find, which is the right behaviour for a capture.
	var cam := Camera2D.new()
	_world.add_child(cam)
	cam.make_current()
	# Zoomed out far enough that the FULL extension (600 px of wall) fits the frame:
	# the point of the sheet is the widening, and a clipped panel [2] hides it.
	cam.position = Vector2(430.0, 0.0)
	cam.zoom = Vector2(0.42, 0.42)
	_sheet = Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.03, 0.03, 0.05, 1.0))
	_run()


func _run() -> void:
	# One live cut, sampled at three points of its flight, then a diagonal one.
	var arc: Node2D = _spawn(Vector2.RIGHT)
	await _wait(6)
	_grab(0)
	await _wait(30)
	_grab(1)
	await _wait(40)
	_grab(2)
	if is_instance_valid(arc):
		arc.queue_free()
	await _wait(4)
	var diag: Node2D = _spawn(Vector2(1.0, -0.45).normalized())
	await _wait(52)
	_grab(3)
	if is_instance_valid(diag):
		diag.queue_free()
	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("horizon_cut: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("horizon_cut: save failed err=", err)
	quit(0)


func _spawn(dir: Vector2) -> Node2D:
	var arc: Node2D = (load(ARC_PATH) as GDScript).new()
	_world.add_child(arc)
	arc.set("element_id", Elements.Element.ARCANE)
	arc.call("sweep", Vector2.ZERO, dir, Color(0.86, 0.92, 1.0), 900.0, 30.0, 90.0, 300.0, 110)
	return arc


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab(cell: int) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL),
		Vector2i((cell % 2) * CELL.x, (cell / 2) * CELL.y))
