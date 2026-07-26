# Throwaway Phase-1 rig+feel visual check: drives the SpellPlayground figure through
# punch / jump / dash / parry-deflect / cast and saves a PNG a few frames into each
# so the new speed-lines, dash ghosts, parry shell + reflected bolt can be READ.
# GUI binary (renders):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/phase1_rig_capture.gd
extends SceneTree

var _scene: Node
var _fig: Node2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	for i in 80:
		await physics_frame                      # settle on the floor
	_fig = _scene.get("_fig")
	# The controller stomps ctrl_* from live Input every physics frame — mute it so
	# this script owns the figure's inputs (camera _process keeps following).
	(_scene as Node).set_physics_process(false)
	_fig.connect("parried", func(p: Vector2) -> void: print("phase1cap PARRIED at ", p))
	_fig.connect("casting", func(d: Vector2) -> void: print("phase1cap CASTING dir ", d))
	var torso := _torso()

	# 1) PUNCH — warm tight speed-line cone ahead of the fist (punch LEFT: open space)
	_fig.set("ctrl_aim", torso.global_position + Vector2(-220.0, -10.0))
	_fig.call("punch")
	for i in 5:
		await physics_frame
	await _save("phase1_punch.png")

	# 2) JUMP — cool upward fan from the feet (walk clear of the dummy first,
	# capture just after liftoff)
	for i in 30:
		await physics_frame
	_fig.set("ctrl_move_x", 1.0)
	for i in 45:
		await physics_frame
	_fig.set("ctrl_move_x", 0.0)
	for i in 20:
		await physics_frame
	_fig.set("ctrl_jump", true)
	for i in 2:
		await physics_frame
	_fig.set("ctrl_jump", false)
	for i in 2:
		await physics_frame
	await _save("phase1_jump.png")

	# 3) DASH into open space (LEFT) — ghosts spread along the burst line
	for i in 100:
		await physics_frame                      # land + dash cooldown clear
	_fig.call("dash", Vector2(-1.0, 0.0))
	for i in 12:
		await physics_frame
	await _save("phase1_dash.png")

	# 4) PARRY + incoming bolt — shell arc, ding, reflected bolt flying back out.
	# Bolt needs (96-50)/260 ≈ 0.18s to enter reach; parry opened ~6 frames into the
	# flight so it arrives mid-window.
	for i in 90:
		await physics_frame
	torso = _torso()
	# runtime load, NOT the global class identifier — a --script main loop compiles this
	# file BEFORE autoloads register, and EnemyProjectile's dependency chain needs them
	var proj: Node2D = (load("res://scripts/combat/EnemyProjectile.gd") as GDScript).new()
	_scene.add_child(proj)
	proj.global_position = torso.global_position + Vector2(96.0, -8.0)
	proj.launch((torso.global_position - proj.global_position).normalized())
	_fig.set("ctrl_aim", torso.global_position + Vector2(200.0, 0.0))
	for i in 6:
		await physics_frame
	_fig.call("parry")
	for i in 4:
		await physics_frame
	await _save("phase1_parry_shell.png")        # shell up, bolt incoming
	for i in 12:
		await physics_frame
	await _save("phase1_parry_deflect.png")      # bolt reflected + impact frame
	for i in 30:
		await physics_frame

	# 5) CAST pose — both arms thrust along the cast line (give the springs a beat)
	torso = _torso()
	_fig.set("ctrl_aim", torso.global_position + Vector2(200.0, -60.0))
	_fig.call("cast", Vector2(1.0, -0.25))
	for i in 10:
		await physics_frame
	await _save("phase1_cast_pose.png")

	quit(0)


func _torso() -> RigidBody2D:
	return _fig.get("_torso") as RigidBody2D


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("phase1cap saved ", fname)
