extends SceneTree
func _initialize() -> void: call_deferred("_g")
func _g() -> void:
	await process_frame
	root.size = Vector2i(1366, 768)
	await process_frame
	var gs: Node = root.get_node_or_null("/root/GameState")
	gs.call("enter_run")
	for i: int in 90: await process_frame
	var hero: Node2D = null
	for n: Node in root.get_tree().get_nodes_in_group("hero"): hero = n as Node2D
	var base: Vector2 = hero.global_position
	for i: int in 150:
		hero.global_position = base
		hero.set_physics_process(false)
		var fs: Array = root.get_tree().get_nodes_in_group("enemy")
		for f: Node in fs:
			(f as Node2D).set_physics_process(false)
			(f as Node2D).global_position = base + Vector2(0, -240)
		await process_frame
	var cam: Camera2D = null
	for c: Node in root.get_tree().get_nodes_in_group("combat_camera"):
		if c is Camera2D and (c as Camera2D).is_current(): cam = c as Camera2D
	print("hero=", hero.global_position, " camparent=", cam.get_parent().name,
		" camglobal=", cam.global_position, " offset=", cam.offset, " zoom=", cam.zoom,
		" screencenter=", cam.get_screen_center_position())
	print("canvas_xform=", root.get_canvas_transform())
	print("hero_screen_via_root=", root.get_canvas_transform() * hero.global_position)
	print("hero_screen_via_cam=", (hero.global_position - cam.get_screen_center_position()) * cam.zoom.x + Vector2(320, 180))
	print("viewport of cam == root? ", cam.get_viewport() == root)
	print("smoothing=", cam.position_smoothing_enabled, " ", cam.position_smoothing_speed)
	quit()
