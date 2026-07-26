# Throwaway visual check for the physics-rig spike. Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/spike_capture.gd
# Saves user://spike.png — four RAGDOLL figures aiming in different directions
# (to see head shape, whether the arm follows the cursor, and the resting lean),
# the rightmost one mid-punch.
extends SceneTree

const OUT_PATH := "user://spike.png"
const FIG := preload("res://scripts/spike/SpikeFigure.gd")

var _figs: Array = []
var _aims: Array = []


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(980, 560)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.12, 0.16)
	bg.size = Vector2(980, 560)
	root.add_child(bg)

	# floor so the figures stand
	_floor(Vector2(490, 480), Vector2(940, 70))

	var xs := [170.0, 400.0, 620.0, 830.0]
	var aims := [Vector2(70, -70), Vector2(-70, -60), Vector2(70, 20), Vector2(60, -60)]
	for i in xs.size():
		var f = FIG.new()
		f.mode = SpikeFigure.Mode.RAGDOLL
		f.spawn_pos = Vector2(xs[i], 360)
		f.body_color = Color(0.62, 0.22, 0.30)
		root.add_child(f)
		_figs.append(f)
		_aims.append(Vector2(xs[i], 360) + aims[i])
	_run()


func _floor(pos: Vector2, size: Vector2) -> void:
	var b := StaticBody2D.new()
	b.position = pos
	b.collision_layer = SpikeFigure.WORLD_LAYER
	b.collision_mask = 0
	var c := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	root.add_child(b)
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	p.color = Color(0.20, 0.23, 0.28)
	p.position = pos
	root.add_child(p)


func _run() -> void:
	for step in 160:
		for i in _figs.size():
			_figs[i].ctrl_aim = _aims[i]
		if step == 145:
			_figs[3].punch()
		await physics_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_PATH)
		print("spike_capture: saved ", ProjectSettings.globalize_path(OUT_PATH))
	quit(0)
