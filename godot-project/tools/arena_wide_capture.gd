# Wide overview of the whole VersusArena stage (to see the mountain + terrain).
# Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/arena_wide_capture.gd
extends SceneTree

const OUT: String = "user://arena_wide.png"


func _initialize() -> void:
	var scene: Node = (load("res://scenes/combat/VersusArena.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_cap()


func _cap() -> void:
	for i: int in 70:
		await process_frame
	# Add a wide framing camera AFTER the fighters settle + make it current (the
	# fighter's fit-all camera isn't in our group so it won't fight this).
	var cam := Camera2D.new()
	cam.position = Vector2(1000.0, 440.0)
	cam.zoom = Vector2(0.56, 0.56)
	root.add_child(cam)
	cam.make_current()
	for i2: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT)
		print("arena_wide_capture: saved ", ProjectSettings.globalize_path(OUT))
	quit(0)
