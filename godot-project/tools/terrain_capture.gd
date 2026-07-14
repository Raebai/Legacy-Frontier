# Frame the playable TERRAIN band of VersusArena (HUD hidden) so the terrain look
# can be reviewed. Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/terrain_capture.gd
extends SceneTree

const OUT: String = "user://terrain_look.png"


func _initialize() -> void:
	var scene: Node = (load("res://scenes/combat/VersusArena.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_cap(scene)


func _cap(scene: Node) -> void:
	for i: int in 75:
		await process_frame
	# Hide every screen-space HUD layer so it doesn't cover the terrain.
	for child: Node in scene.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var cam := Camera2D.new()
	cam.position = Vector2(1000.0, 600.0)
	cam.zoom = Vector2(0.66, 0.66)
	root.add_child(cam)
	cam.make_current()
	for i2: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT)
		print("terrain_capture: saved ", ProjectSettings.globalize_path(OUT))
	quit()
