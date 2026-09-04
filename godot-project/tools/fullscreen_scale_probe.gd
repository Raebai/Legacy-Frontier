# Run (NOT headless — it needs a real window):
#   godot --path godot-project --script tools/fullscreen_scale_probe.gd
#
# DOES THE PICTURE ACTUALLY SCALE WHEN THE WINDOW GOES FULLSCREEN?
#
# The maker reports fullscreen "just shows the small screen in a full screen setting".
# `Screen.gd` and the stretch config both READ as correct (canvas_items / expand from a
# 640x360 base), so the question is not what the settings say — it is what the window
# actually does. [[feedback_measure_the_channel_the_viewer_gets]].
#
# THE NUMBER THAT MATTERS is the canvas scale: the root window's final transform. In
# `canvas_items` stretch the logical viewport STAYS 640x360 and the content is scaled up,
# so `get_visible_rect()` is NOT the tell — it reads 640x360 in both states whether
# scaling works or not. A scale of 1.0 against a 1920-wide window means the game is
# being drawn at 640x360 in the corner of a black screen, which is the reported bug.
# A scale of ~3.0 means the stretch is doing its job and the fault is elsewhere.
extends SceneTree

## Uses `_initialize`, NOT `_process`. A SceneTree script's `_process` returning true
## ENDS the main loop, so the frame after the one that kicks the work off tears the tree
## down and every pending `await process_frame` is abandoned silently - the probe printed
## nothing at all on its first run for exactly that reason.
func _initialize() -> void:
	_go()


func _go() -> void:
	if DisplayServer.get_name() == "headless":
		print("fullscreen probe: SKIPPED — headless has no window to measure.")
		quit(0)
		return

	# ⚠ BOOT THE REAL MAIN SCENE. The first version of this probe measured a bare
	# root window with NO game in it and reported the stretch working — which was true
	# of the window and said nothing about what the player is looking at. If anything in
	# the actual scene tree (a CanvasLayer, the post-process rect, a fixed-size Control)
	# is what stays small, only the real scene shows it.
	var main_path: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var main: PackedScene = load(main_path) as PackedScene
	if main != null:
		root.add_child(main.instantiate())
		print("  booted main scene: %s" % main_path)
	else:
		print("  WARNING: could not load main scene %s — measuring a bare window" % main_path)

	for _i: int in 30:
		await process_frame
	var before: Dictionary = _sample()

	var scr: Node = root.get_node_or_null(^"/root/Screen")
	if scr == null:
		print("fullscreen probe: FAIL — /root/Screen autoload is missing.")
		quit(1)
		return
	scr.call("set_fullscreen", true)
	for _i: int in 20:
		await process_frame
	var after: Dictionary = _sample()

	scr.call("set_fullscreen", false)
	for _i: int in 5:
		await process_frame

	print("\n== fullscreen scale probe ==")
	print("  screen size            : %s" % DisplayServer.screen_get_size())
	_report("windowed  ", before)
	_report("fullscreen", after)

	var sx: float = float(after["scale"].x)
	var win_w: float = float(after["window"].x)
	var expected: float = win_w / 640.0
	print("")
	if is_equal_approx(sx, 1.0) and win_w > 700.0:
		print("  VERDICT: BROKEN — canvas scale is 1.0 on a %.0f px window." % win_w)
		print("           The game is drawn at 640x360 inside a black screen.")
	elif absf(sx - expected) < 0.35:
		print("  VERDICT: THE STRETCH WORKS — scale %.2fx against an expected %.2fx." % [sx, expected])
		print("           The picture fills the window, so this code path is NOT the bug.")
	else:
		print("  VERDICT: UNCLEAR — scale %.2fx, expected about %.2fx." % [sx, expected])
	quit(0)


func _sample() -> Dictionary:
	# `get_final_transform()` is what the renderer applies to the whole canvas — the
	# drawn channel, not the configured intent.
	var t: Transform2D = root.get_final_transform()
	return {
		"window": DisplayServer.window_get_size(),
		"logical": root.get_visible_rect().size,
		"scale": t.get_scale(),
		"mode": DisplayServer.window_get_mode(),
	}


func _report(label: String, s: Dictionary) -> void:
	print("  %s: window %s  logical viewport %s  canvas scale %s  mode %d"
		% [label, s["window"], s["logical"], s["scale"], int(s["mode"])])
