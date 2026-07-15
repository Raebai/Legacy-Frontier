# Fire a Brawler's fire Q in the arena and catch the explosion layered over the
# procedural flame + blast. Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/vfx_demo_capture.gd
extends SceneTree

var _hero: Node2D = null
var _cam: Camera2D = null


func _initialize() -> void:
	var scene: Node = (load("res://scenes/combat/VersusArena.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for i: int in 70:
		await process_frame
	for child: Node in scene.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var heroes: Array = get_nodes_in_group("hero")
	if heroes.is_empty():
		print("no hero"); quit(); return
	_hero = heroes[0]
	_hero.call("configure_class", 2)  # BRAWLER (fire) -> fist_shock Q
	_hero.set("_aim_dir", Vector2.RIGHT)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(1.6, 1.6)
	root.add_child(_cam)
	_cam.global_position = (_hero as Node2D).global_position + Vector2(80, -30)
	_cam.make_current()
	_hero.call("_blast")  # fire punch -> blast + FlameBurst + Vfx.explosion
	for i2: int in 10:  # ~0.17s in — explosion blooming
		await process_frame
	if _cam != null and _hero != null:
		_cam.global_position = (_hero as Node2D).global_position + Vector2(80, -30)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://vfx_demo.png")
		print("vfx_demo_capture: saved ", ProjectSettings.globalize_path("user://vfx_demo.png"))
	quit()
