# Run with the GUI (NON-headless) binary so the real renderer produces pixels:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/screenshot.gd -- <scene_res_path>
# Saves the rendered viewport to user://shot.png (Claude reads that file to SEE
# the game). Headless/dummy-renderer runs produce a black frame — must be the GUI
# binary. Optional 2nd cmdline arg overrides the scene; defaults to the versus arena.
extends SceneTree

const DEFAULT_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const OUT_PATH: String = "user://shot.png"
const SETTLE_FRAMES: int = 75  # let the scene spawn + fighters drop + settle


func _initialize() -> void:
	var scene_path: String = DEFAULT_SCENE
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("res://"):
			scene_path = arg
	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("screenshot: could not load ", scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	_capture()


func _capture() -> void:
	for i: int in SETTLE_FRAMES:
		await process_frame
	# Wait for the frame to actually finish drawing before grabbing pixels.
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("screenshot: null viewport image")
		quit(1)
		return
	var err: int = img.save_png(OUT_PATH)
	if err == OK:
		print("screenshot: saved ", ProjectSettings.globalize_path(OUT_PATH))
	else:
		printerr("screenshot: save failed err=", err)
	quit(0)
