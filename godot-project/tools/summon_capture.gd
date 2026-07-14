# Capture a hero mid-SUMMON (spell circle blooming) then at ERUPTION, to review the
# Phase-2 epic-windup feel. Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/summon_capture.gd
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
		print("summon_capture: no hero")
		quit()
		return
	_hero = heroes[0]
	# Cryomancer's ice_wall is an instant signature -> summon windup.
	_hero.call("configure_class", 5)
	_hero.set("_signature_index", 0)
	_hero.set("mp", 200.0)
	_hero.set("_signature_cd_timer", 0.0)
	_hero.set("_aim_dir", Vector2.RIGHT)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(1.5, 1.5)
	root.add_child(_cam)
	_cam.global_position = (_hero as Node2D).global_position + Vector2(60, -40)
	_cam.make_current()
	# Start the summon, then catch it mid-windup (circle blooming).
	_hero.call("_cast_signature")
	for i2: int in 10:  # ~0.17s in — sigil growing, pose committed
		await process_frame
	await _save("user://summon_windup.png")
	for i3: int in 24:  # let it erupt + the epic beat land
		await process_frame
	await _save("user://summon_erupt.png")
	quit()


func _save(path: String) -> void:
	if _cam != null and _hero != null:
		_cam.global_position = (_hero as Node2D).global_position + Vector2(60, -40)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("summon_capture: saved ", ProjectSettings.globalize_path(path))
