# Force a floor-5 (BOSS) run and render the Arena so the guardian is visible.
# MUST run with the GUI (non-headless) binary — the dummy renderer draws black:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/boss_capture.gd
# Output: user://boss_floor.png
extends SceneTree

const OUT_PATH: String = "user://boss_floor.png"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame   # let autoloads (GameState/Music/Rank) settle under root
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("boss_capture: no GameState autoload")
		quit(1)
		return
	# Force a BOSS-floor run before the Arena reads GameState in _ready.
	gs.active_tower = gs.build_default_tower()
	gs.set("_run_active", true)
	gs.set("_floor", 5)
	gs.set("mode", 1)   # Mode.RUN
	var arena: Node = load("res://scenes/combat/Arena.tscn").instantiate()
	root.add_child(arena)
	for i: int in 120:   # settle: spawn guardian + adds, let them approach
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_PATH)
		print("boss_capture: saved ", ProjectSettings.globalize_path(OUT_PATH))
	quit(0)
