# Full-resolution single-moment look at ONE ult, for when the contact sheet
# (tools/ult_sheet_capture.gd) shows a difference too small to judge at 300 px
# wide. Same fixed-camera bare arena, no downscale.
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/ult_focus_capture.gd -- <name> <frame> [zoom]
#
# <name> is a key in _defs below. Output: user://ult_focus_<name>_<frame>.png
extends SceneTree

const GROUND_Y: float = 260.0
const FLOOR_HALF_WIDTH: float = 1400.0
const FLOOR_THICKNESS: float = 120.0
const DEFAULT_ZOOM: float = 0.55
const CAM_OFFSET_Y: float = -190.0

var _arena: Node2D = null
var _name: String = "meteor_fire"
var _frame: int = 70
var _zoom: float = DEFAULT_ZOOM


func _defs() -> Dictionary:
	var at := Vector2(0.0, GROUND_Y)
	return {
		"converge": ["res://scripts/combat/StarConvergence.gd", "converge",
			[at, Color(1.0, 0.86, 0.4), 160.0, 130, "holy"], Elements.Element.HOLY],
		"judgment": ["res://scripts/combat/DivineRay.gd", "strike",
			[at, Color(1.0, 0.92, 0.55), 70.0, 95, "holy"], Elements.Element.LIGHTNING],
		"colossus": ["res://scripts/combat/DivineRay.gd", "strike",
			[at, Color(0.7, 0.6, 0.45), 80.0, 110, "holy"], Elements.Element.EARTH],
		"meteor_fire": ["res://scripts/combat/MeteorSigil.gd", "rain",
			[at, Color(1.0, 0.55, 0.2), 150.0, 22, 12, "fire"], Elements.Element.FIRE],
		"meteor_earth": ["res://scripts/combat/MeteorSigil.gd", "rain",
			[at, Color(0.75, 0.6, 0.4), 150.0, 22, 12, "earth"], Elements.Element.EARTH],
		"meteor_shadow": ["res://scripts/combat/MeteorSigil.gd", "rain",
			[at, Color(0.6, 0.35, 0.9), 150.0, 22, 12, "shadow"], Elements.Element.SHADOW],
		"nova": ["res://scenes/combat/EnergyNova.tscn", "activate_at",
			[Vector2(0.0, GROUND_Y - 20.0)], Elements.Element.ARCANE],
	}


func _initialize() -> void:
	Engine.max_fps = 60
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_name = args[0]
	if args.size() > 1:
		_frame = int(args[1])
	if args.size() > 2:
		_zoom = float(args[2])
	_build_arena()
	_run()


func _build_arena() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.size = Vector2(4000, 3000)
	bg.position = Vector2(-2000, -2000)
	root.add_child(bg)
	_arena = Node2D.new()
	root.add_child(_arena)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	floor_body.global_position = Vector2(0.0, GROUND_Y + FLOOR_THICKNESS * 0.5)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(FLOOR_HALF_WIDTH * 2.0, FLOOR_THICKNESS)
	shape.shape = rect
	floor_body.add_child(shape)
	_arena.add_child(floor_body)
	var floor_art := ColorRect.new()
	floor_art.color = Color(0.13, 0.12, 0.15)
	floor_art.size = Vector2(FLOOR_HALF_WIDTH * 2.0, FLOOR_THICKNESS)
	floor_art.position = Vector2(-FLOOR_HALF_WIDTH, GROUND_Y)
	_arena.add_child(floor_art)
	for dx: float in [-260.0, -90.0, 90.0, 300.0]:
		var e := Node2D.new()
		e.add_to_group("enemy")
		e.global_position = Vector2(dx, GROUND_Y)
		_arena.add_child(e)
		var rig := CharacterRig.new()
		rig.height = 31.0
		rig.limb_color = Color(0.55, 0.85, 0.6)
		e.add_child(rig)
	var cam := Camera2D.new()
	cam.zoom = Vector2(_zoom, _zoom)
	cam.global_position = Vector2(0.0, GROUND_Y + CAM_OFFSET_Y)
	_arena.add_child(cam)
	PostProcess.add(_arena)


func _run() -> void:
	for _i: int in 20:
		await process_frame
	var defs: Dictionary = _defs()
	if not defs.has(_name):
		printerr("ult_focus: unknown ", _name, " — have ", defs.keys())
		quit(1)
		return
	var d: Array = defs[_name]
	var path: String = String(d[0])
	var node: Node2D
	if path.ends_with(".tscn"):
		node = (load(path) as PackedScene).instantiate() as Node2D
	else:
		node = (load(path) as GDScript).new() as Node2D
	_arena.add_child(node)
	node.set("element_id", int(d[3]))
	node.callv(String(d[1]), d[2] as Array)
	for _i: int in maxi(_frame, 1):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var out: String = "user://ult_focus_%s_%d.png" % [_name, _frame]
	if img != null and img.save_png(out) == OK:
		print("ult_focus: saved ", ProjectSettings.globalize_path(out))
	else:
		printerr("ult_focus: save failed")
	quit(0)
