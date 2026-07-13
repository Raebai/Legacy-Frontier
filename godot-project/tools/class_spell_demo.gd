# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/class_spell_demo.gd
# Fires the NEW class spectacles in VersusArena and renders a 2x2 sheet to
# user://class_spell_demo.png so the new visuals read:
#   [0] Chidori lightning lance   [1] Fire-punch shockwave
#   [2] Colossus Pillar (earth)   [3] Umbral Lance (shadow beam)
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
const OUT: String = "user://class_spell_demo.png"
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
	_zoom(1.2)
	var o: Vector2 = _hero.global_position

	# [0] CHIDORI — jagged lightning lance ripping right.
	var rush: Node2D = (load("res://scripts/combat/LightningRush.gd") as GDScript).new()
	_arena.add_child(rush)
	rush.rush(o, Vector2.RIGHT, Elements.color(Elements.Element.LIGHTNING), 560.0, 26.0, 62)
	await _wait(14)  # just past the charge -> full strike
	_grab(0)
	await _wait(30)

	# [1] FIRE-PUNCH shockwave — a configured BlastSpell just in front of the fist.
	var punch: Node2D = (load("res://scenes/combat/BlastSpell.tscn") as PackedScene).instantiate()
	_arena.add_child(punch)
	punch.configure({"target_group": "enemy", "damage": 30, "radius": 66.0, "knockback": 430.0, "element_id": Elements.Element.FIRE})
	punch.detonate_now(o + Vector2(48.0, 0.0))
	await _wait(6)
	_grab(1)
	await _wait(30)

	# [2] COLOSSUS PILLAR — earth divine ray.
	var ray: Node2D = (load("res://scripts/combat/DivineRay.gd") as GDScript).new()
	_arena.add_child(ray)
	ray.strike(o + Vector2(60.0, 0.0), Elements.color(Elements.Element.EARTH), 96.0, 60, "holy")
	await _wait(28)
	_grab(2)
	await _wait(36)

	# [3] UMBRAL LANCE — shadow beam.
	var beam: Node2D = (load("res://scripts/combat/BeamSpell.gd") as GDScript).new()
	_arena.add_child(beam)
	beam.fire(o, Vector2.RIGHT, Elements.color(Elements.Element.SHADOW), 900.0, 30.0, 50, "arcane")
	await _wait(24)
	_grab(3)

	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("class_spell_demo: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("class_spell_demo: save failed err=", err)
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
