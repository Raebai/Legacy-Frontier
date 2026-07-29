# Throwaway visual check for THE CLASH (scripts/combat/MeleeClash.gd): stage two
# stick fighters facing each other, have BOTH commit a punch inside
# MeleeClash.CLASH_WINDOW, and save PNGs across the beat so the sparks, the freeze,
# the impact frame and the two rigs rebounding can actually be READ.
#
# Also captures the NEGATIVE for comparison: the same two figures punching well
# outside the window, which must look like an ordinary trade with none of the above.
#
# GUI binary (renders):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/clash_capture.gd
extends SceneTree

var _scene: Node
var _a: Node2D
var _b: Node2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	# A `--script` main loop has no current_scene, and MeleeClash._arena() (like
	# SpellDeflect._arena) parents its one-shot bursts to it — without this the spark
	# burst lands under the Window, where world coordinates are read as screen
	# coordinates and the sparks fly off frame. Setting it makes the capture match
	# how the game actually runs rather than quietly hiding half the beat.
	root.set_deferred(&"current_scene", _scene)
	_run()


func _run() -> void:
	for i in 80:
		await physics_frame                       # let the arena + figure settle
	_a = _scene.get("_fig")
	# The controller stomps ctrl_* from live Input every physics frame — mute it so
	# this script owns both figures' inputs.
	(_scene as Node).set_physics_process(false)
	# A second fighter, spawned face to face at fist range. Runtime load, NOT the
	# global identifier: a --script main loop compiles this file before autoloads
	# register.
	var fig_script: GDScript = load("res://scripts/spike/SpikeFigure.gd")
	_b = fig_script.new()
	_b.spawn_pos = _torso(_a).global_position + Vector2(78.0, 0.0)
	_b.body_color = Color(0.55, 0.78, 0.95)       # cool blue vs the default warm red
	_scene.add_child(_b)
	for i in 90:
		await physics_frame                       # let B drop and stand

	# ---------------------------------------------------------------- THE CLASH
	_face_each_other()
	_a.call("punch")
	for i in 4:                                   # ~33 ms apart at 120 Hz — inside the window
		await physics_frame
	_b.call("punch")
	await _save("clash_00_meet.png")              # the frame the blows meet
	for i in 4:
		await physics_frame
	await _save("clash_01_sparks.png")            # sparks + impact frame at the midpoint
	for i in 14:
		await physics_frame
	await _save("clash_02_thrown.png")            # both rigs rebounding apart

	# ------------------------------------------------- THE NEGATIVE (a plain trade)
	for i in 180:
		await physics_frame                       # settle + clear the refractory
	_face_each_other()
	_a.call("punch")
	for i in 40:                                  # ~330 ms apart — far outside the window
		await physics_frame
	_b.call("punch")
	for i in 4:
		await physics_frame
	await _save("clash_03_no_clash_trade.png")    # must look like an ordinary swing
	quit(0)


## Point both figures' aim at the other's torso, so `punch()` derives a direction
## straight at them and the mutual-aim gate passes.
func _face_each_other() -> void:
	var pa: Vector2 = _torso(_a).global_position
	var pb: Vector2 = _torso(_b).global_position
	_a.set("ctrl_aim", pb)
	_b.set("ctrl_aim", pa)


func _torso(fig: Node2D) -> RigidBody2D:
	return fig.get("_torso") as RigidBody2D


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("clashcap saved ", fname)
