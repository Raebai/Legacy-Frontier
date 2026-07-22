# Post-process "look" capture: boot a combat arena and grab full-res frames of the
# reactive grade in four states so the effect is verifiable by eye.
#
# MUST run with the GUI (non-headless) binary — the dummy renderer draws black:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/postprocess_capture.gd
#
# Outputs (in user://):
#   pp_idle.png    — the base grade at rest (aberration whisper + vignette + tone)
#   pp_trauma.png  — camera trauma pinned high (strong chromatic aberration smear)
#   pp_heat.png    — heat-haze pulsed (fire shimmer warp)
#   pp_shock.png   — a shockwave ripple mid-expansion
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
const SETTLE_FRAMES: int = 80


func _initialize() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		printerr("postprocess_capture: could not load ", SCENE)
		quit(1)
		return
	root.add_child(packed.instantiate())
	_run()


func _run() -> void:
	for i: int in SETTLE_FRAMES:
		await process_frame

	# 1) Idle — the base grade.
	await _grab("user://pp_idle.png")

	# 2) Trauma — pin the camera trauma high for a few frames (strong aberration).
	for f: int in 4:
		_pin_trauma()
		await process_frame
	_pin_trauma()
	await _grab("user://pp_trauma.png")

	# 3) Heat — pulse the heat-haze and hold it up.
	for f: int in 3:
		PostProcess.pulse_heat(0.9)
		await process_frame
	PostProcess.pulse_heat(0.9)
	await _grab("user://pp_heat.png")

	# 4) Shock — fire a strong ripple, let it expand a few frames, catch it mid-flight.
	PostProcess.shock(1.6)
	for f: int in 6:
		await process_frame
	await _grab("user://pp_shock.png")

	quit(0)


## Force the active combat camera's trauma toward max so the aberration reads.
func _pin_trauma() -> void:
	var cam: Node = root.get_tree().get_first_node_in_group("combat_camera")
	if cam != null and cam.has_method("add_trauma"):
		cam.call("add_trauma", 1.0)


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("postprocess_capture: null frame for ", path)
		return
	img.save_png(path)
	print("postprocess_capture: saved ", ProjectSettings.globalize_path(path))
