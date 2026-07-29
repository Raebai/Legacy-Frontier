# Throwaway render check for the FROST FIELD rework — the rime meter climbing a
# dummy, the casing sealing it, and the burst. Modelled on tools/zone_agent_capture.gd.
# GUI binary (the headless renderer draws nothing):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/frost_field_capture.gd
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
		await physics_frame                      # settle the figure + dummies
	var fig: Node = _scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	var bliz: SpellDef = null
	for s: SpellDef in _scene.get("_spells"):
		if s.id == "blizzard":
			bliz = s
	# The right-hand sparring dummy sits at x=220 on the floor (FLOOR_Y 340).
	SpellCaster.cast(bliz, _scene, origin, Vector2(220.0, 330.0), Color(0.5, 0.85, 1.0), "")
	for i in 45:
		await physics_frame
	_save("frost_a_squall.png")                  # ~0.4 s: storm open, rime starting
	for i in 90:
		await physics_frame
	_save("frost_b_rime.png")                    # ~1.1 s: meter most of the way round
	for i in 55:
		await physics_frame
	_save("frost_c_encased.png")                 # ~1.6 s: sealed in the casing
	for i in 90:
		await physics_frame
	_save("frost_d_after.png")                   # ~2.4 s: casing burst, squall running
	quit(0)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("frostcap saved ", fname)
