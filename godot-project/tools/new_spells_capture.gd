# Visual check for the bespoke class kits. Run with the GUI binary:
# Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/new_spells_capture.gd
# Saves user://new_spells.png. Shows Ice Wall, Chain Lightning, Void Zone, Rune Orbs,
# Blade Flurry, Blink Strike, Drain Tether across a spread of dummy enemies.
extends SceneTree

const OUT: String = "user://new_spells.png"


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.14)
	bg.size = Vector2(1360, 620)
	root.add_child(bg)
	var arena := Node2D.new()
	root.add_child(arena)
	# Dummy enemies within the 640x360 design canvas (the viewport scales it to the
	# window, so anything past x~640 lands off-screen).
	var spots := [Vector2(120, 210), Vector2(150, 235), Vector2(330, 205), Vector2(370, 230),
		Vector2(470, 205), Vector2(510, 220), Vector2(560, 205)]
	for s: Vector2 in spots:
		var e := Node2D.new()
		e.add_to_group("enemy")
		e.global_position = s
		arena.add_child(e)
		var er := CharacterRig.new()
		er.height = 30.0
		er.limb_color = Color(0.5, 0.85, 0.55)
		e.add_child(er)
	_cap(arena)


func _cap(arena: Node2D) -> void:
	await process_frame
	_spawn(arena, "res://scripts/combat/ZoneSpell.gd", "open", [Vector2(130, 220), Elements.color(Elements.Element.SHADOW), 70.0, 10, "shadow", 4.5], Elements.Element.SHADOW)
	_spawn(arena, "res://scripts/combat/RuneOrbs.gd", "launch", [Vector2(280, 205), Vector2(1, 0), Elements.color(Elements.Element.ARCANE), 6, 24, "arcane"], Elements.Element.ARCANE)
	_spawn(arena, "res://scripts/combat/DrainTether.gd", "tether", [Vector2(300, 300), Vector2(1, -0.3), Elements.color(Elements.Element.SHADOW), 11, "shadow"], Elements.Element.SHADOW)
	_spawn(arena, "res://scripts/combat/BladeFlurry.gd", "flurry", [Vector2(340, 230), Vector2(1, -0.1), Elements.color(Elements.Element.SHADOW), 16, 6, "shadow"], Elements.Element.SHADOW)
	_spawn(arena, "res://scripts/combat/BlinkStrike.gd", "strike", [Vector2(430, 205), Vector2(560, 205), Elements.color(Elements.Element.SHADOW), 55, "shadow"], Elements.Element.SHADOW)
	for i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT)
		print("new_spells_capture: saved ", ProjectSettings.globalize_path(OUT))
	quit(0)


func _spawn(arena: Node2D, path: String, method: String, args: Array, elem: int) -> void:
	var n: Node2D = (load(path) as GDScript).new()
	arena.add_child(n)
	n.set("element_id", elem)
	n.callv(method, args)
