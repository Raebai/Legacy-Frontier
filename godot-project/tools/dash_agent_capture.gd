# Throwaway agent-owned A/B check for the DASH visual (safe to delete).
# Renders the REAL game Hero's dash (VersusArena) and the SpellPlayground
# SpikeFigure's dash at matched beats so the two afterimage trails can be
# compared side by side. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/dash_agent_capture.gd
extends SceneTree


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await _hero_dash()
	await _spike_dash()
	quit(0)


func _hero_dash() -> void:
	var scene: Node = load("res://scenes/combat/VersusArena.tscn").instantiate()
	root.add_child(scene)
	for i in 200:
		await physics_frame
	var heroes: Array = root.get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		print("dashcap: NO HERO")
		scene.queue_free()
		return
	var hero: Node = heroes[0]
	hero.set("_move_dir", Vector2.RIGHT)
	hero.call("_start_dash")
	for stage: Array in [[4, "early"], [10, "mid"], [17, "late"], [30, "after"]]:
		var target: int = int(stage[0])
		while target > 0:
			await physics_frame
			target -= 1
		await _save("dashcap_hero_%s.png" % stage[1])
	scene.queue_free()
	await physics_frame


func _spike_dash() -> void:
	var scene: Node = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(scene)
	for i in 90:
		await physics_frame
	(scene as Node).set_physics_process(false)
	var fig: Node = scene.get("_fig")
	fig.call("dash", Vector2(1.0, 0.0))
	for stage: Array in [[4, "early"], [10, "mid"], [17, "late"], [30, "after"]]:
		var target: int = int(stage[0])
		while target > 0:
			await physics_frame
			target -= 1
		await _save("dashcap_spike_%s.png" % stage[1])
	scene.queue_free()
	await physics_frame


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("dashcap saved ", fname)
