# LOOK AT THE TWO CEREMONIES. A floor-1 mini-guardian and the floor-5 headline act,
# photographed at the same moment of their arrival, so "the ceremony scales with the
# fight" can be SEEN rather than inferred from constants.
#
# MUST run with the GUI binary (the dummy renderer saves black PNGs while reporting
# success):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/ceremony_capture.gd
# Outputs: user://ceremony_mini.png (body_scale 0.45), user://ceremony_full.png (1.0)
#
# All boss access is duck-typed (.call/.get) — no compile-time Boss dependency, same
# as tools/boss_capture.gd.
extends SceneTree

const BOSS_SCENE: String = "res://scenes/combat/Boss.tscn"


func _initialize() -> void:
	_run()


func _settle(n: int) -> void:
	for i: int in n:
		await process_frame


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("ceremony_capture: saved ", ProjectSettings.globalize_path(path))


## Spawn one guardian at `scale_v`, photograph it mid-card, then take it away.
func _shoot_ceremony(arena: Node, scale_v: float, path: String) -> void:
	var boss: Node = load(BOSS_SCENE).instantiate()
	boss.set("body_scale", scale_v)          # pre-_ready: this is what picks the ceremony
	boss.set("max_hp", 900)
	var heroes: Array[Node] = root.get_tree().get_nodes_in_group("hero")
	var at := Vector2(520.0, 300.0)
	if heroes.size() > 0 and heroes[0] is Node2D:
		at = (heroes[0] as Node2D).global_position + Vector2(200.0, 0.0)
	arena.add_child(boss)
	if boss is Node2D:
		(boss as Node2D).global_position = at
	# ~0.4 s in: the card is up in both settings, and the brief one is already
	# most of the way through its whole life.
	await _settle(24)
	print("  body_scale %.2f -> full_ceremony %s, intro %.2fs, card %d pt"
		% [scale_v, str(boss.call("full_ceremony")), float(boss.call("intro_time")),
			int((boss.call("card_style") as Dictionary)["size"])])
	await _shoot(path)
	boss.queue_free()
	await _settle(4)


func _run() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("ceremony_capture: no GameState autoload")
		quit(1)
		return
	gs.active_tower = gs.build_default_tower()
	gs.set("_run_active", true)
	gs.set("_floor", 1)
	gs.set("mode", 1)   # Mode.RUN
	var arena: Node = load("res://scenes/combat/Arena.tscn").instantiate()
	root.add_child(arena)
	await _settle(40)
	await _shoot_ceremony(arena, 0.45, "user://ceremony_mini.png")
	await _shoot_ceremony(arena, 1.0, "user://ceremony_full.png")
	quit(0)
