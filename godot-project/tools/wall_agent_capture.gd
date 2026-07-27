# Throwaway visual check for the WALL redesigns (rock vs ice + shove + shatter).
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/wall_agent_capture.gd
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
	var fig: Node = _scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	var spells: Array = _scene.get("_spells")
	var rock: SpellDef = _find(spells, "rock_wall")
	var ice: SpellDef = _find(spells, "ice_wall")
	# 1) ROCK WALL erupts to the RIGHT of the figure: mid-upheaval, then settled.
	SpellCaster.cast(rock, _scene, origin, origin + Vector2(300.0, 0.0), Color(0.78, 0.84, 1.0), "")
	for i in 14:
		await physics_frame
	await _save("wall_rock_rising.png")
	for i in 40:
		await physics_frame
	await _save("wall_rock_raised.png")
	# 2) ICE WALL crystallises to the LEFT — same shot = direct silhouette compare.
	SpellCaster.cast(ice, _scene, origin, origin + Vector2(-300.0, 0.0), Color(0.78, 0.84, 1.0), "")
	for i in 14:
		await physics_frame
	await _save("wall_ice_growing.png")
	for i in 40:
		await physics_frame
	await _save("wall_ice_raised.png")
	# 3) SHOVE the rock wall right: it smashes the crate at x=90, plows the dummy
	# at x=220, smashes the crate at x=360, slams the arena wall at x~560.
	var rw: Node2D = null
	for w: Node in get_nodes_in_group("shoveable"):
		rw = w as Node2D
	if rw != null:
		rw.call("shove", Vector2.RIGHT)
	var mid_saved := false
	for i in 300:
		await physics_frame
		if not is_instance_valid(rw):
			print("wallcap slide: wall freed at frame ", i)
			break
		var fb: Vector2 = rw.get("_floor_base")
		if i % 10 == 0:
			print("wallcap slide f=", i, " x=", fb.x, " ts=", Engine.time_scale,
				" crumb=", rw.get("_crumbling"))
		if not mid_saved and fb.x >= origin.x + 260.0:
			mid_saved = true
			await _save("wall_rock_shove_mid.png")
		if rw.get("_crumbling"):
			print("wallcap slide: slam at x=", fb.x, " frame=", i)
			await _save("wall_rock_shove_impact.png")
			break
	if not mid_saved:
		await _save("wall_rock_shove_mid.png")
	# 4) SHATTER the ice wall (drive it directly — the Phase 3 hook).
	var iw: Node2D = null
	for w: Node in get_nodes_in_group("ice_wall"):
		iw = w as Node2D
	if iw != null:
		iw.call("shatter")
	for i in 14:
		await physics_frame
	await _save("wall_ice_shatter.png")
	quit(0)


func _find(spells: Array, id: String) -> SpellDef:
	for s: SpellDef in spells:
		if s.id == id:
			return s
	return null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("wallcap saved ", fname)
