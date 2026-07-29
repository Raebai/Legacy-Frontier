# Look-test for the stickman-integrate rig work. Tests cannot judge this — the whole
# point is whether the figure READS as planted rather than skating, and whether gear
# reads as part of the body — so this renders PNGs to be looked at.
#
# GUI binary (the headless one draws nothing):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/rig_look_capture.gd
#
# Writes to user:// (%APPDATA%\Godot\app_userdata\Legacy Frontier\):
#   rigcap_gait_new_*.png   world-locked gait, six frames across one run
#   rigcap_gait_old_*.png   the SAME build with the gait suppressed, so the figure
#                           falls back to the old phase-driven sine legs — a true
#                           before/after of one binary rather than a memory of one
#   rigcap_gear_head.png    the four head pieces, each REPLACING the head
#   rigcap_gear_body.png    torso pieces + the bare stick for comparison
#   rigcap_gear_weapons.png every weapon kind, procedural, in the rig's own idiom
#   rigcap_air.png          mid-leap slack hang (legs trailing the momentum)
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const FLOOR_Y: float = 300.0
const RIG_H: float = 31.0

var _world: Node2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(1280, 720)
	# The project stretches a 640x360 design canvas to the window, so everything is
	# already drawn at 2x before the camera zoom is applied. Framing here is written
	# against the DESIGN canvas (640x360 around the camera) and then doubled — get this
	# wrong and the subject lands off-screen, which is exactly what happened first try.
	_run()


func _run() -> void:
	await process_frame
	await _gait_strip(true)
	await _gait_strip(false)
	await _gear_sheet(
		"rigcap_gear_head.png", "head",
		["", "helmet", "hat", "hood", "crown"]
	)
	await _gear_sheet(
		"rigcap_gear_body.png", "body",
		["", "armor", "robe"]
	)
	await _gear_sheet(
		"rigcap_gear_weapons.png", "weapon",
		["sword", "greatsword", "dagger", "hammer", "club", "spear", "scythe",
		 "staff", "staff_ice", "orb", "bomb"]
	)
	await _air_shot()
	quit(0)


## A fresh world with an opaque backdrop + a real StaticBody2D floor on layer 1, so
## the rig's downward ground probe finds something and the foot-plant IK engages
## exactly as it does in the arena.
func _fresh_world(zoom: float, cam_at: Vector2) -> void:
	if _world != null:
		_world.queue_free()
		await process_frame
	_world = Node2D.new()
	root.add_child(_world)
	var bg := ColorRect.new()
	bg.size = Vector2(4000, 2000)
	bg.position = Vector2(-2000, -1000)
	bg.color = Color(0.14, 0.15, 0.19)
	_world.add_child(bg)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 60)
	cs.shape = rect
	cs.position = Vector2(0, 30)
	floor_body.add_child(cs)
	floor_body.position = Vector2(0, FLOOR_Y)
	_world.add_child(floor_body)
	var floor_paint := ColorRect.new()
	floor_paint.size = Vector2(4000, 60)
	floor_paint.position = Vector2(-2000, FLOOR_Y)
	floor_paint.color = Color(0.22, 0.24, 0.28)
	_world.add_child(floor_paint)
	# Ruled marks every 20 px along the floor: the ONLY way to judge foot slide from a
	# still image is against a fixed reference the foot can be compared to.
	for i: int in 200:
		var tick := ColorRect.new()
		tick.size = Vector2(1, 10)
		tick.position = Vector2(-2000.0 + float(i) * 20.0, FLOOR_Y)
		tick.color = Color(0.36, 0.38, 0.44)
		_world.add_child(tick)
	var cam := Camera2D.new()
	cam.zoom = Vector2(zoom, zoom)
	cam.position = cam_at
	_world.add_child(cam)
	cam.make_current()
	await process_frame


func _make_rig(x: float, h: float = RIG_H) -> Node2D:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", h)
	rig.set("limb_color", Color(0.4, 0.7, 1.0))
	_world.add_child(rig)
	rig.position = Vector2(x, FLOOR_Y - h * 0.5)
	rig.call("set_grounded", true)
	rig.call("play", 0)
	return rig


## Six frames across one continuous run, at 4x zoom with the camera LOCKED (not
## following), so the floor ticks stay put and any foot slide is visible directly.
## `use_gait` false suppresses the world-locked plants every frame, dropping the
## figure back onto the old phase-driven sine legs for the before/after.
func _gait_strip(use_gait: bool) -> void:
	var tag: String = "new" if use_gait else "old"
	await _fresh_world(2.0, Vector2(0.0, FLOOR_Y - 24.0))
	var rig: Node2D = _make_rig(-62.0)
	rig.call("play", 1)   # RUN
	var dt: float = 1.0 / 60.0
	var vx: float = 180.0
	var shot: int = 0
	for i: int in 42:
		rig.position.x += vx * dt
		rig.call("set_body_velocity", Vector2(vx, 0.0))
		rig.call("advance", dt)
		if not use_gait:
			rig.set("_gait_ready", false)   # fall back to the old sine legs
		if i % 7 == 0 and shot < 6:
			shot += 1
			await _save("rigcap_gait_%s_%d.png" % [tag, shot])


func _gear_sheet(fname: String, slot: String, kinds: Array) -> void:
	var span: float = 34.0
	var first: float = -span * float(kinds.size() - 1) * 0.5
	await _fresh_world(2.2, Vector2(0.0, FLOOR_Y - 16.0))
	for i: int in kinds.size():
		var rig: Node2D = _make_rig(first + span * float(i))
		if String(kinds[i]) != "":
			rig.call("set_equipment", slot, String(kinds[i]))
		# A weapon sheet needs the arm out, or every piece is hidden behind the body.
		if slot == "weapon":
			rig.call("set_aim_arm", true)
			rig.call("set_aim", Vector2(0.6, -0.8))
		for f: int in 40:
			rig.call("advance", 1.0 / 60.0)
	await _save(fname)


## Mid-leap: the AIR target is now a slack hang whose legs TRAIL the momentum, so a
## figure launched right should show both legs swept back and left, not a jump pose.
func _air_shot() -> void:
	await _fresh_world(2.6, Vector2(20.0, FLOOR_Y - 46.0))
	var rig: Node2D = _make_rig(-24.0)
	rig.call("play", 8)   # AIR
	rig.call("set_grounded", false)
	rig.call("set_air_phase", true, false)
	for f: int in 26:
		rig.position += Vector2(3.2, -2.6)
		rig.call("set_body_velocity", Vector2(320.0, -160.0))
		rig.call("advance", 1.0 / 60.0)
	await _save("rigcap_air.png")


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("rigcap saved ", fname)
