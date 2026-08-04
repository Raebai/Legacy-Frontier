# THE LEGS, BIG ENOUGH TO JUDGE. Not a test — tests cannot see a leg.
#
# GUI binary (headless renders blank PNGs while reporting success):
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/rig_legs_capture.gd
#
# Every previous look at this rig was taken at the size the fighter appears in a
# CLIP — about 90 px tall, 8% of frame height — where a wrong knee is invisible and
# a correct one is indistinguishable from it. So this renders FEW figures, LARGE,
# against a ruled floor, in the poses the maker actually sees:
#   rigleg_stand.png   standing still, every class preset side by side
#   rigleg_walk_*.png  one figure walking, six frames, filling the shot
#   rigleg_enemy.png   the ENEMY presets — "everyone's legs", not just the hero's
#
# Output: %APPDATA%/Godot/app_userdata/Legacy Frontier/
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const FLOOR_Y: float = 300.0
const RIG_H: float = 31.0

var _world: Node2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(1600, 900)
	_run()


func _run() -> void:
	await process_frame
	await _stand_sheet()
	await _walk_strip()
	await _enemy_sheet()
	quit(0)


func _fresh_world(zoom: float, cam_at: Vector2) -> void:
	if _world != null:
		_world.queue_free()
		await process_frame
	_world = Node2D.new()
	root.add_child(_world)
	var bg := ColorRect.new()
	bg.size = Vector2(6000, 3000)
	bg.position = Vector2(-3000, -1500)
	bg.color = Color(0.14, 0.15, 0.19)
	_world.add_child(bg)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6000, 60)
	cs.shape = rect
	cs.position = Vector2(0, 30)
	floor_body.add_child(cs)
	floor_body.position = Vector2(0, FLOOR_Y)
	_world.add_child(floor_body)
	var paint := ColorRect.new()
	paint.size = Vector2(6000, 60)
	paint.position = Vector2(-3000, FLOOR_Y)
	paint.color = Color(0.22, 0.24, 0.28)
	_world.add_child(paint)
	# Ruled marks: the only way to judge foot slide and foot height from a still.
	for i: int in 400:
		var tick := ColorRect.new()
		tick.size = Vector2(1, 8)
		tick.position = Vector2(-2000.0 + float(i) * 10.0, FLOOR_Y)
		tick.color = Color(0.34, 0.36, 0.42)
		_world.add_child(tick)
	var cam := Camera2D.new()
	cam.zoom = Vector2(zoom, zoom)
	cam.position = cam_at
	_world.add_child(cam)
	cam.make_current()
	# ⚠ A PHYSICS FRAME, NOT JUST AN IDLE ONE — and this is the difference between
	# an instrument and a liar. `CharacterRig._update_ground_probe` raycasts for the
	# floor every frame, and the foot clamp that keeps a stride ON the ground is
	# skipped entirely when that ray finds nothing. A StaticBody2D added during an
	# idle frame is not in the physics space yet, so awaiting only `process_frame`
	# meant the floor built here did not exist as far as the ray was concerned: the
	# rig walked with clamping disabled and the capture showed feet sinking through
	# a floor it could see but not feel.
	await process_frame
	await physics_frame


func _make_rig(x: float, preset: String = "") -> Node2D:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", RIG_H)
	rig.set("limb_color", Color(0.45, 0.72, 1.0))
	_world.add_child(rig)
	rig.position = Vector2(x, FLOOR_Y - RIG_H * 0.5)
	if preset != "":
		rig.call("class_preset", preset)
	rig.call("set_grounded", true)
	rig.call("play", 0)
	return rig


func _save(fname: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("user://" + fname)
	print("rigleg saved ", fname)


## STANDING. If a knee is bent at rest, that is visible here and nowhere else —
## a walk cycle hides a bad rest pose inside the motion.
func _stand_sheet() -> void:
	await _fresh_world(7.0, Vector2(0.0, FLOOR_Y - 16.0))
	var span: float = 26.0
	var presets: Array[String] = ["mage", "rogue", "brawler", "juggernaut", "cleric"]
	var first: float = -span * float(presets.size() - 1) * 0.5
	for i: int in presets.size():
		var rig: Node2D = _make_rig(first + span * float(i), presets[i])
		for _f: int in 30:
			rig.call("advance", 1.0 / 60.0)
	await _save("rigleg_stand.png")


## WALKING, one figure, filling the shot. Six frames across one continuous stride.
func _walk_strip() -> void:
	for shot: int in 6:
		await _fresh_world(11.0, Vector2(0.0, FLOOR_Y - 14.0))
		var rig: Node2D = _make_rig(-40.0)
		rig.call("play", 1)   # RUN
		var dt: float = 1.0 / 60.0
		var vx: float = 180.0
		# Walk far enough to be past the start transient, then hold the shot.
		var frames: int = 24 + shot * 4
		for _i: int in frames:
			rig.position.x += vx * dt
			rig.call("set_body_velocity", Vector2(vx, 0.0))
			rig.call("advance", dt)
		# Park the camera on the figure so it fills the frame at this zoom.
		for c: Node in _world.get_children():
			if c is Camera2D:
				(c as Camera2D).position = Vector2(rig.position.x, FLOOR_Y - 14.0)
		await _save("rigleg_walk_%d.png" % [shot + 1])


## THE ENEMY PRESETS. The maker's words were "everyone's legs", and enemies drive
## the same CharacterRig — so if the fix did not reach them, it shows here.
func _enemy_sheet() -> void:
	await _fresh_world(7.0, Vector2(0.0, FLOOR_Y - 16.0))
	var span: float = 26.0
	var presets: Array[String] = ["brute", "runner", "caster", "charger", "bomber"]
	var first: float = -span * float(presets.size() - 1) * 0.5
	for i: int in presets.size():
		var rig: Node2D = _make_rig(first + span * float(i), presets[i])
		rig.call("play", 1)   # RUN — enemies are almost always moving
		for _f: int in 34:
			rig.call("set_body_velocity", Vector2(120.0, 0.0))
			rig.call("advance", 1.0 / 60.0)
	await _save("rigleg_enemy.png")
