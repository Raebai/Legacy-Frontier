# Run with the GUI (non-headless) binary so the real renderer produces pixels:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/verify_feel_capture.gd
# Renders a 2x2 sheet of LARGE cells to user://verify_sheet.png so the maker's
# feel-pass items are visible at a readable size:
#   [0] staff held (aim right, idle)   [1] jump dust puff (rising off the floor)
#   [2] parry SHIELD arc (aim left)    [3] cast pose + bolt (aim up-right)
# Faceless figure throughout (no eyes). Zooms the hero's camera out so the whole
# figure + effects frame cleanly.
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
const OUT: String = "user://verify_sheet.png"
const CELL: Vector2i = Vector2i(480, 270)
const SETTLE_FRAMES: int = 40  # let the hero drop to the ground first

var _sheet: Image = null
var _hero: Node2D = null


func _initialize() -> void:
	root.add_child((load(SCENE) as PackedScene).instantiate())
	_sheet = Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.04, 0.04, 0.06, 1.0))
	_run()


func _run() -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame
	_hero = _find_hero()
	if _hero != null:
		_zoom_camera(1.9)
	# [0] staff held — aim right, stand still.
	_aim(0.72, 0.5)
	await _wait(8)
	_grab(0)
	# [1] jump dust — press jump, catch the rising puff a few frames in.
	Input.action_press("jump")
	await _wait(2)
	Input.action_release("jump")
	await _wait(3)
	_grab(1)
	await _wait(30)  # land (a land puff fires here too)
	# [2] parry shield — aim left, press parry, catch the arc.
	_aim(0.28, 0.5)
	Input.action_press("parry")
	await _wait(1)
	Input.action_release("parry")
	await _wait(2)
	_grab(2)
	await _wait(20)
	# [3] cast pose + bolt — aim up-right, cast.
	_aim(0.80, 0.34)
	Input.action_press("cast")
	await _wait(3)
	Input.action_release("cast")
	_grab(3)
	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("verify: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("verify: save failed err=", err)
	quit(0)


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _aim(fx: float, fy: float) -> void:
	var ws: Vector2i = DisplayServer.window_get_size()
	Input.warp_mouse(Vector2(ws) * Vector2(fx, fy))


func _zoom_camera(z: float) -> void:
	for child: Node in _hero.get_children():
		if child is Camera2D:
			(child as Camera2D).zoom = Vector2(z, z)
			return


func _grab(cell: int) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var col: int = cell % 2
	var row: int = cell / 2
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))


func _find_hero() -> Node2D:
	var heroes: Array = get_nodes_in_group("hero")
	return heroes[0] as Node2D if not heroes.is_empty() else null
