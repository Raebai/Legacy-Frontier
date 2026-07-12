# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/spell_demo_capture.gd
# Fires the spectacle signature spells in VersusArena and renders a 2x2 sheet to
# user://spell_demo.png so the magic-circle beam / divine ray read is visible:
#   [0] beam charge (sigil)   [1] beam fire   [2] divine-ray column   [3] beam fade
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
const OUT: String = "user://spell_demo.png"
const CELL: Vector2i = Vector2i(480, 270)

var _sheet: Image = null
var _arena: Node2D = null
var _hero: Node2D = null


func _initialize() -> void:
	_arena = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_arena)
	_sheet = Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.03, 0.03, 0.05, 1.0))
	_run()


func _run() -> void:
	for _i: int in 40:
		await process_frame
	_hero = _find_hero()
	_zoom(1.15)
	var beam_script: GDScript = load("res://scripts/combat/BeamSpell.gd")
	var ray_script: GDScript = load("res://scripts/combat/DivineRay.gd")
	var color := Color(0.6, 0.4, 1.0)

	# --- Beam: fire from the hero toward the right, capture charge/fire/fade. ---
	var beam: Node2D = beam_script.new()
	_arena.add_child(beam)
	beam.fire(_hero.global_position, Vector2.RIGHT, color, 900.0, 30.0, 46)
	await _wait(16)
	_grab(0)   # charging sigil
	await _wait(8)
	_grab(1)   # fire flash
	await _wait(26)
	_grab(3)   # fading

	# --- Divine ray: crash a column down on a point to the hero's right. ---
	var ray: Node2D = ray_script.new()
	_arena.add_child(ray)
	ray.strike(_hero.global_position + Vector2(150.0, 0.0), Color(1.0, 0.92, 0.55), 90.0, 50)
	await _wait(27)   # just past the 0.42s charge -> pillar at full brightness
	root.get_texture().get_image().save_png("user://divine_ray_full.png")
	_grab(2)   # column crashing down

	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("spell_demo: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("spell_demo: save failed err=", err)
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
