# Visual verification for the AEGIS WARD and the STEAM CLOUD (agent-owned; safe
# to delete). GUI binary required — the headless dummy renderer draws nothing:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/ward_capture.gd
# Output lands in %APPDATA%\Godot\app_userdata\Legacy Frontier\.
#
# WHAT TO LOOK FOR, because these are the two claims the code makes that only an
# eyeball can check:
#   * THE PLATE COUNT IS READABLE. Three lit runes = full, and a spent one is a
#     CRACKED outline rather than merely a dim dot — dim alone is indistinguishable
#     from far away, which is the whole failure mode "every defence must be
#     readable" exists to prevent.
#   * THE STEAM ACTUALLY HIDES THINGS. steam_cloud is the only reaction whose
#     payoff is vision, so a tasteful haze is a failed implementation. The frames
#     put two blocks behind the bank on purpose.
#
# Deliberately NOT the SpellPlayground — that scene pulls in scripts/spike, which
# other agents are editing, and a capture tool that cannot render because someone
# else's file is mid-write is a capture tool that stops being used. Same reasoning
# (and the same arena) as tools/hollow_purple_capture.gd.
extends SceneTree

const AEGIS_WARD := "res://scripts/combat/AegisWard.gd"
const STEAM_CLOUD := "res://scripts/combat/SteamCloud.gd"

const FLOOR_TOP: float = 180.0
## Where the caster stands. The ward plants OFFSET px to its right, which puts the
## gate at x = 0 and lets the camera sit on the origin.
const CASTER := Vector2(-108.0, 120.0)

## Close enough that the runes fill a meaningful part of the frame. ⚠ THE PROJECT
## STRETCHES: project.godot renders at a small base viewport and the window scales
## it ~2x, so world-to-pixel is TWICE the Camera2D zoom. At 1.0 the 132 px gate is
## ~264 screen px — a third of a 720-tall frame, which is roughly how big it will
## be in play.
const WARD_ZOOM: float = 1.0
const WARD_CAM := Vector2(0.0, 110.0)
## Wider for the cloud: a 160 px bank is 320 screen px at zoom 1.0, and the point
## is to see what it covers, not to fill the frame with it.
const STEAM_ZOOM: float = 0.75
const STEAM_CAM := Vector2(0.0, 90.0)

var _scene: Node2D = null
var _cam: Camera2D = null


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await physics_frame          # the tree must be live before /root lookups work
	await _capture_ward()
	await _capture_steam()
	quit(0)


## The ward: rising, standing full, one plate spent, two spent, collapsing.
func _capture_ward() -> void:
	_build_arena(WARD_CAM, WARD_ZOOM)
	for i: int in 10:
		await physics_frame
	var caster := Node2D.new()
	caster.name = "Caster"
	_scene.add_child(caster)
	caster.global_position = CASTER
	var ward: Node2D = (load(AEGIS_WARD) as GDScript).new()
	_scene.add_child(ward)
	ward.set(&"caster_node", caster)
	ward.call(&"raise_ward", CASTER, Vector2.RIGHT, Color(1.0, 0.93, 0.6), "holy")
	if not is_instance_valid(ward) or ward.is_queued_for_deletion():
		printerr("wardcap: the ward FIZZLED — there is no floor under the plant point")
		_teardown()
		return
	await _hold(8)
	await _save("ward_1_rising.png")
	await _hold(24)
	await _save("ward_2_standing_full.png")
	# Burn plates by hand rather than staging a beam: this tool is here to look at
	# the FACE of the ward, and a real absorb would put a beam across it.
	ward.call(&"reaction_absorb", ward.call(&"base_point") - Vector2(0.0, 40.0))
	await _hold(3)
	await _save("ward_3_one_plate_spent.png")
	await _hold(14)
	await _save("ward_4_two_left_settled.png")
	ward.call(&"reaction_absorb", ward.call(&"base_point") - Vector2(0.0, 70.0))
	await _hold(14)
	await _save("ward_5_one_plate_left.png")
	ward.call(&"shatter")
	await _hold(6)
	await _save("ward_6_collapse.png")
	_teardown()


## The cloud, with two blocks parked behind it so "does this actually conceal?" is
## answerable from the picture rather than from the constant.
func _capture_steam() -> void:
	_build_arena(STEAM_CAM, STEAM_ZOOM)
	for x: float in [-90.0, 90.0]:
		_rect(_scene, Vector2(x, 90.0), Vector2(64.0, 96.0), Color(0.62, 0.34, 0.34))
	for i: int in 10:
		await physics_frame
	var cloud: Node2D = (load(STEAM_CLOUD) as GDScript).new()
	_scene.add_child(cloud)
	cloud.call(&"boil", Vector2(0.0, 96.0), 160.0)
	await _hold(6)
	await _save("steam_1_boil.png")
	await _hold(30)
	await _save("steam_2_billowed.png")
	await _hold(90)
	await _save("steam_3_thinning.png")
	_teardown()


func _hold(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _build_arena(cam_at: Vector2, zoom: float) -> void:
	RenderingServer.set_default_clear_color(Color(0.13, 0.14, 0.18))
	_scene = Node2D.new()
	Atmosphere.add_glow(_scene)    # 2D bloom, so the HDR rails and runes radiate
	PostProcess.add(_scene)        # the reactive grade, so this matches the game
	root.add_child(_scene)
	# A REAL collider, not a painted rectangle: AegisWard refuses to plant without
	# ground under it, so a decorative floor would produce a tool that only ever
	# captures the fizzle.
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_scene.add_child(body)
	body.global_position = Vector2(0.0, FLOOR_TOP + 40.0)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1600.0, 80.0)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.add_child(cs)
	_rect(_scene, Vector2(0.0, FLOOR_TOP + 40.0), Vector2(1600.0, 80.0),
		Color(0.20, 0.22, 0.27))
	_cam = Camera2D.new()
	_cam.position = cam_at
	_cam.zoom = Vector2(zoom, zoom)
	_scene.add_child(_cam)
	_cam.make_current()            # only legal once the camera is in the tree


func _rect(parent: Node, at: Vector2, size: Vector2, col: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	p.color = col
	p.position = at
	p.z_index = -5
	parent.add_child(p)


func _teardown() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("wardcap saved ", fname)
