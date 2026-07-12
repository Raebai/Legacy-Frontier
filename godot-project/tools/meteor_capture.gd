# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/meteor_capture.gd
# Zoomed-out 2x2 time sequence of ONE Meteor Sigil so the whole shower reads:
# telegraph -> meteors streaking down -> impacts. -> user://meteor_seq.png
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
const OUT: String = "user://meteor_seq.png"
const CELL: Vector2i = Vector2i(480, 270)

var _sheet: Image = null
var _hero: Node2D = null


func _initialize() -> void:
	Engine.max_fps = 60  # pin the render rate so frame counts map to ~seconds/60
	root.add_child((load(SCENE) as PackedScene).instantiate())
	_sheet = Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.03, 0.03, 0.05, 1.0))
	_run()


func _run() -> void:
	for _i: int in 40:
		await process_frame
	_hero = _find_hero()
	_zoom(0.62)  # wide: see the sky sigil + the full fall
	var meteor: Node2D = (load("res://scripts/combat/MeteorSigil.gd") as GDScript).new()
	root.get_child(0).add_child(meteor)
	meteor.rain(_hero.global_position + Vector2(60.0, -40.0), Color(1.0, 0.55, 0.2), 150.0, 22, 12)
	# Grab across charge -> barrage -> impacts.
	var frames := [34, 46, 58, 72]  # ~0.57s / 0.77s / 0.97s / 1.2s: charge-end -> impacts
	var prev := 0
	for cell in 4:
		await _wait(frames[cell] - prev)
		prev = frames[cell]
		_grab(cell)
	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("meteor_seq: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("meteor_seq: save failed err=", err)
	quit(0)


func _wait(frames: int) -> void:
	for _i: int in maxi(frames, 1):
		await process_frame
	await RenderingServer.frame_post_draw


func _zoom(z: float) -> void:
	if _hero == null:
		return
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
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((cell % 2) * CELL.x, (cell / 2) * CELL.y))


func _find_hero() -> Node2D:
	var heroes: Array = get_nodes_in_group("hero")
	return heroes[0] as Node2D if not heroes.is_empty() else null
