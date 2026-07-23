# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/nova_capture.gd
# Task 7 (right-size spell VFX) verification aid: fires the Arcanist's T (Nova)
# via EnergyNova.activate_at() at the combat camera's DEFAULT zoom (1.6, same as
# real play) so the shockwave-ring shrink (VISUAL_RADIUS_FACTOR) is visible at
# true in-game scale. -> user://nova_seq.png (2x2: pre-burst / peak ring / fading / settled)
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
const OUT: String = "user://nova_seq.png"
const CELL: Vector2i = Vector2i(480, 270)

var _sheet: Image = null
var _hero: Node2D = null


func _initialize() -> void:
	Engine.max_fps = 60
	root.add_child((load(SCENE) as PackedScene).instantiate())
	_sheet = Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.03, 0.03, 0.05, 1.0))
	_run()


func _run() -> void:
	for _i: int in 40:
		await process_frame
	_hero = _find_hero()
	_zoom(1.6)  # DEFAULT_ZOOM from CombatCamera.gd — the scale the maker actually plays at
	_grab(0)   # [0] before the nova fires
	var nova: Node2D = (load("res://scripts/combat/EnergyNova.gd") as GDScript).new()
	root.get_child(0).add_child(nova)
	nova.call("activate_at", _hero.global_position)
	await _wait(4)
	_grab(1)   # [1] near-peak ring
	await _wait(6)
	_grab(2)   # [2] fading
	await _wait(14)
	_grab(3)   # [3] settled (scorch/debris only)
	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("nova_seq: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("nova_seq: save failed err=", err)
	quit(0)


func _wait(frames: int) -> void:
	for _i: int in frames:
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
