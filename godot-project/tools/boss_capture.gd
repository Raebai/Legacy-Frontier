# Force a floor-5 (BOSS) run and render the Ashen Guardian across its 3 phases.
# MUST run with the GUI binary (dummy renderer draws black):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/boss_capture.gd
# Outputs: user://boss_p1.png, boss_p2.png, boss_p3.png
# All boss access is duck-typed (.call/.get) — no compile-time Boss dependency.
extends SceneTree


func _initialize() -> void:
	_run()


func _find_boss() -> Node:
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if e.has_method("current_phase"):
			return e
	return null


func _settle(n: int) -> void:
	for i: int in n:
		await process_frame


## Stand the (non-moving) hero right beside the boss so the camera frames both
## and the colossus scale reads. Cosmetic-only for the capture.
func _frame_with_hero(boss: Node) -> void:
	if boss == null:
		return
	for h in root.get_tree().get_nodes_in_group("hero"):
		if h is Node2D:
			(h as Node2D).global_position = (boss as Node2D).global_position + Vector2(150.0, 40.0)
			break


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("boss_capture: saved ", ProjectSettings.globalize_path(path))


func _run() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("boss_capture: no GameState autoload")
		quit(1)
		return
	gs.active_tower = gs.build_default_tower()
	gs.set("_run_active", true)
	gs.set("_floor", 5)
	gs.set("mode", 1)   # Mode.RUN
	var arena: Node = load("res://scenes/combat/Arena.tscn").instantiate()
	root.add_child(arena)
	await _settle(70)

	var boss: Node = _find_boss()
	if boss == null:
		printerr("boss_capture: no boss spawned")
		quit(1)
		return

	# P1 — waking colossus (stone tint, ember aura tier 3, dim core).
	boss.call("_enter_phase", 1)
	_frame_with_hero(boss)
	await _settle(30)
	await _shoot("user://boss_p1.png")

	# P2 — fury (heated tint, tier 4, brighter core).
	var mx: int = int(boss.get("max_hp"))
	boss.call("take_damage", int(mx * 0.34) + 1)
	_frame_with_hero(boss)
	await _settle(25)
	await _shoot("user://boss_p2.png")

	# P3 — ashfall (near-molten, tier 5, max core glow).
	boss = _find_boss()
	if boss != null:
		boss.call("take_damage", int(mx * 0.34) + 1)
		_frame_with_hero(boss)
		await _settle(30)
	await _shoot("user://boss_p3.png")

	quit(0)
