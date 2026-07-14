# Visual check for the Wave-1 bespoke kits (IceWall + ChainBolt). Run with the GUI
# binary: Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/new_spells_capture.gd
# Saves user://new_spells.png.
extends SceneTree

const OUT: String = "user://new_spells.png"


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.14)
	bg.size = Vector2(1120, 560)
	root.add_child(bg)
	var arena := Node2D.new()
	root.add_child(arena)
	# Dummy enemies (with rigs) for the chain to leap across.
	for i in 4:
		var e := Node2D.new()
		e.add_to_group("enemy")
		e.global_position = Vector2(640.0 + float(i) * 95.0, 340.0 - float(i % 2) * 44.0)
		arena.add_child(e)
		var er := CharacterRig.new()
		er.height = 46.0
		er.limb_color = Color(0.5, 0.85, 0.55)
		e.add_child(er)
	_cap(arena)


func _cap(arena: Node2D) -> void:
	await process_frame  # let the tree settle so get_tree() is valid on spawn
	# IceWall on the left.
	var iw: Node2D = (load("res://scripts/combat/IceWall.gd") as GDScript).new()
	arena.add_child(iw)
	iw.set("element_id", Elements.Element.ICE)
	iw.call("raise_wall", Vector2(180.0, 360.0), Vector2.RIGHT, Elements.color(Elements.Element.ICE), "frost")
	# ChainBolt across the enemies on the right.
	var cb: Node2D = (load("res://scripts/combat/ChainBolt.gd") as GDScript).new()
	arena.add_child(cb)
	cb.set("element_id", Elements.Element.LIGHTNING)
	cb.call("chain", Vector2(560.0, 320.0), Vector2.RIGHT, Elements.color(Elements.Element.LIGHTNING), 5, 240.0, 46, "lightning")
	for i: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT)
		print("new_spells_capture: saved ", ProjectSettings.globalize_path(OUT))
	quit(0)
