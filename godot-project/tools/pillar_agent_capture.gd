# Throwaway visual check for the PILLAR identity split (judgment regression
# guard + colossus_pillar stone eruption + rock_pillar fang). GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/pillar_agent_capture.gd
extends SceneTree

var _scene: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _spell(id: String) -> SpellDef:
	for s: SpellDef in _scene.get("_spells"):
		if s.id == id:
			return s
	push_error("pillar cap: no spell with id " + id)
	return null


func _run() -> void:
	for i in 70:
		await physics_frame  # settle the figure + dummies on the floor
	var fig: Node = _scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	var target := Vector2(90.0, 315.0)  # a cover + dummy in the cluster

	# 1) JUDGMENT — the regression guard. Charge 0.42, hold 0.18: capture the
	# pillar at full brightness ~0.5s after cast.
	SpellCaster.cast(_spell("judgment"), _scene, origin, target, Color(1.0, 0.92, 0.55), "")
	await create_timer(0.50).timeout
	await _save("pillar_judgment.png")
	await create_timer(1.0).timeout  # let it fade fully

	# 2) COLOSSUS PILLAR — telegraph mid-window (cracks + heave + glow leak),
	# then the erupted spire in its hold phase.
	SpellCaster.cast(_spell("colossus_pillar"), _scene, origin, target, Color(0.78, 0.55, 0.28), "")
	await create_timer(0.58).timeout   # tp ~0.68 of the 0.85s tell
	await _save("pillar_colossus_telegraph.png")
	await create_timer(0.60).timeout   # 1.18s in: charge 0.85 + rise 0.18 -> hold
	await _save("pillar_colossus_erupted.png")
	await create_timer(1.2).timeout    # crumble out

	# 3) ROCK PILLAR — the fast fang at full height (charge 0.40 + rise 0.14 -> hold).
	SpellCaster.cast(_spell("rock_pillar"), _scene, origin, target, Color(0.78, 0.55, 0.28), "")
	await create_timer(0.62).timeout
	await _save("pillar_rock_erupted.png")
	quit(0)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("pillarcap saved ", fname)
