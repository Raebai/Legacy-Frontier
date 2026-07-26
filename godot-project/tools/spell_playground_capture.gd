# Throwaway visual check for the SPELL PLAYGROUND. GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/spell_playground_capture.gd
extends SceneTree

var _scene: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	for i in 70:
		await physics_frame                      # settle the figure + dummies on the floor
	await RenderingServer.frame_post_draw
	_save("playground_idle.png")
	var fig: Node = _scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	var target := Vector2(90.0, 315.0)           # a cover + dummy in the cluster
	# beam
	SpellCaster.cast(_scene.get("_spells")[0], _scene, origin, target, Color(0.78, 0.84, 1.0), "")
	for i in 40:
		await physics_frame
	_save("playground_beam.png")
	# meteor
	SpellCaster.cast(_scene.get("_spells")[11], _scene, origin, target, Color(1.0, 0.5, 0.2), "")
	for i in 75:
		await physics_frame
	_save("playground_meteor.png")
	quit(0)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("pgcap saved ", fname)
