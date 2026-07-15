# Force-show the mobile TouchControls over VersusArena to review the pad layout.
# Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/touch_capture.gd
extends SceneTree


func _initialize() -> void:
	var scene: Node = (load("res://scenes/combat/VersusArena.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run()


func _run() -> void:
	for i: int in 70:
		await process_frame
	var pad := TouchControls.new()
	pad.force_visible = true
	root.add_child(pad)
	for i2: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://touch_pad.png")
		print("touch_capture: saved ", ProjectSettings.globalize_path("user://touch_pad.png"))
	quit()
