# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/circle_capture.gd
# Focused showcase of the upgraded MagicCircle: a big sigil on a plain backdrop,
# 2x2 across its lifecycle -> user://circle_showcase.png:
#   [0] materialising   [1] full + spinning   [2] spinning (later phase)   [3] blooming out
extends SceneTree

const OUT: String = "user://circle_showcase.png"
const CELL: Vector2i = Vector2i(480, 270)

var _sheet: Image = null
var _circle: Node2D = null


func _initialize() -> void:
	Engine.max_fps = 60
	var world := Node2D.new()
	root.add_child(world)
	var bg := ColorRect.new()
	bg.position = Vector2(-1000, -1000)
	bg.size = Vector2(2000, 2000)
	bg.color = Color(0.14, 0.15, 0.22)  # dark so the glow pops
	bg.z_index = -10
	world.add_child(bg)
	var cam := Camera2D.new()
	world.add_child(cam)
	cam.make_current()
	cam.zoom = Vector2(1.05, 1.05)
	_circle = (load("res://scripts/combat/MagicCircle.gd") as GDScript).new()
	world.add_child(_circle)
	_circle.appear(Color(0.62, 0.42, 1.0), 190.0, 0.3)
	_sheet = Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.03, 0.03, 0.05, 1.0))
	_run()


func _run() -> void:
	await _wait(28)
	_grab(0)   # [0] FACE-ON (portal / summon / meteor)
	_circle.set_orientation(true, Vector2.RIGHT, 0.14)  # beam aimed right -> vertical gate
	await _wait(16)
	_grab(1)   # [1] EDGE-ON horizontal beam
	_circle.set_orientation(true, Vector2.DOWN, 0.16)   # vertical pillar -> horizontal gate
	await _wait(16)
	_grab(2)   # [2] EDGE-ON vertical (divine ray)
	_circle.set_orientation(true, Vector2(1.0, -0.6), 0.14)  # diagonal aim
	await _wait(16)
	_grab(3)   # [3] EDGE-ON diagonal beam
	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("circle_showcase: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("circle_showcase: save failed err=", err)
	quit(0)


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
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((cell % 2) * CELL.x, (cell / 2) * CELL.y))
