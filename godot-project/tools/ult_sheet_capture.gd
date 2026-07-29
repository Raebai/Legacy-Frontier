# THE ULT CONTACT SHEET — the only tool that can answer the maker's complaint
# ("most ults look the same — just are recolours or retypes of the same meteor
# type of thing"). One ROW per ultimate, one COLUMN per moment in its timeline,
# so the SILHOUETTE and the TIMING SHAPE of all of them are legible in a single
# image. A single screenshot of one ult at one instant cannot show either.
#
# Run with the GUI binary (the headless one renders nothing):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/ult_sheet_capture.gd
# Optional user arg picks the output name so BEFORE and AFTER can sit side by
# side:  ... --script tools/ult_sheet_capture.gd -- before
#
# WHY A BARE ARENA INSTEAD OF VersusArena.tscn (which meteor_capture.gd uses):
# CombatCamera auto-frames the hero + live bots every frame and eases its own
# zoom, so the framing drifts between rows and two ults are never shot from the
# same distance. Comparing silhouettes needs a FIXED camera above all else, so
# this builds its own arena: a flat floor body on layer 1 (so SpellWorld's
# floor probes and the ground-snapped residue behave as they do in game), a few
# CharacterRig dummies for scale reference, and one Camera2D that never moves.
extends SceneTree

const OUT_FMT: String = "user://ult_sheet_%s.png"
const CELL: Vector2i = Vector2i(300, 169)
const COLS: int = 6
## World-units the fixed camera shows across. The widest ult (Heaven's Verdict)
## opens a 480 px ring and hangs its sigil 520 px up, so anything tighter than
## ~1600 crops the very silhouette we are trying to judge.
const CAM_ZOOM: float = 0.4
## The camera sits ABOVE the ground line: every one of these spells is either a
## sky event or a ground event, and centring on the floor wastes the bottom half
## of the frame on empty rock.
const CAM_OFFSET_Y: float = -250.0
const GROUND_Y: float = 260.0
const FLOOR_HALF_WIDTH: float = 1400.0
const FLOOR_THICKNESS: float = 120.0

## Each row: a label, the script/scene to spawn, the method + args, the element
## ailment id, and the six frame counts (at a pinned 60 fps) to grab at.
## The frame lists are hand-derived from each spectacle's own timing constants —
## charge end, mid-event, the impact frame, and two beats of aftermath — because
## an evenly-spaced sample would miss the single most important frame of a spell
## whose payoff lasts 120 ms.
var _rows: Array = []

var _sheet: Image = null
var _arena: Node2D = null
var _out: String = OUT_FMT % "before"


func _initialize() -> void:
	Engine.max_fps = 60  # pin the render rate so frame counts map to ~seconds/60
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("-"):
			_out = OUT_FMT % arg
	_build_arena()
	_build_rows()
	_sheet = Image.create(CELL.x * COLS, CELL.y * _rows.size(), false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.02, 0.02, 0.03, 1.0))
	_run()


func _build_arena() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.size = Vector2(4000, 3000)
	bg.position = Vector2(-2000, -2000)
	root.add_child(bg)

	_arena = Node2D.new()
	root.add_child(_arena)

	# A real floor BODY on layer 1 — not decoration. SpellWorld.floor_below and
	# every ground-snapped residue node (GroundCrater, ScorchDecal) probe for
	# this, and without it the ults render their "over a pit" branch and drop
	# half their spectacle silently.
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

	# Scale references. Standing bodies are the only way to judge "how big is
	# this really" from a still, and the ults' whole problem is one of scale and
	# silhouette. Grouped as "enemy" so the damage paths run for real too.
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
	cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	cam.global_position = Vector2(0.0, GROUND_Y + CAM_OFFSET_Y)
	_arena.add_child(cam)
	cam.make_current()

	# The real screen grade, so what we judge is what the player sees (the ults
	# poke PostProcess.shock and it must have somewhere to land).
	PostProcess.add(_arena)


func _build_rows() -> void:
	var at := Vector2(0.0, GROUND_Y)
	_rows = [
		{
			"label": "StarConvergence / holy",
			"path": "res://scripts/combat/StarConvergence.gd",
			"method": "converge",
			"args": [at, Color(1.0, 0.86, 0.4), 160.0, 130, "holy"],
			"element": Elements.Element.HOLY,
			# charge 0.70 + converge 0.60 + hold 0.12 + fade 0.55
			"frames": [21, 42, 63, 79, 88, 106],
		},
		{
			"label": "DivineRay / holy (Judgment)",
			"path": "res://scripts/combat/DivineRay.gd",
			"method": "strike",
			"args": [at, Color(1.0, 0.92, 0.55), 70.0, 95, "holy"],
			"element": Elements.Element.LIGHTNING,
			# charge 0.55 + hold 0.06 + fade 0.85
			"frames": [12, 25, 34, 39, 54, 76],
		},
		{
			"label": "DivineRay / earth (Colossus)",
			"path": "res://scripts/combat/DivineRay.gd",
			"method": "strike",
			"args": [at, Color(0.7, 0.6, 0.45), 80.0, 110, "holy"],
			"element": Elements.Element.EARTH,
			# stone: charge 0.85 + rise 0.18 + hold 0.60 + crumble 0.45
			"frames": [24, 45, 54, 68, 96, 122],
		},
		{
			"label": "MeteorSigil / fire",
			"path": "res://scripts/combat/MeteorSigil.gd",
			"method": "rain",
			"args": [at, Color(1.0, 0.55, 0.2), 150.0, 22, 12, "fire"],
			"element": Elements.Element.FIRE,
			# charge 0.5 + barrage 1.15 + fall 0.52 + fade 0.35
			"frames": [18, 33, 54, 78, 102, 126],
		},
		{
			"label": "MeteorSigil / earth",
			"path": "res://scripts/combat/MeteorSigil.gd",
			"method": "rain",
			"args": [at, Color(0.75, 0.6, 0.4), 150.0, 22, 12, "earth"],
			"element": Elements.Element.EARTH,
			# charge 0.5 + barrage 0.34 (the AVALANCHE cluster) + fall 0.82 + fade
			"frames": [18, 31, 54, 72, 90, 108],
		},
		{
			"label": "MeteorSigil / shadow",
			"path": "res://scripts/combat/MeteorSigil.gd",
			"method": "rain",
			"args": [at, Color(0.6, 0.35, 0.9), 150.0, 22, 12, "shadow"],
			"element": Elements.Element.SHADOW,
			# charge 0.5 + barrage 0.75 + fall 0.55 + fade 0.35
			"frames": [18, 33, 51, 69, 90, 111],
		},
		{
			"label": "EnergyNova (self-centred)",
			"path": "res://scenes/combat/EnergyNova.tscn",
			"method": "activate_at",
			"args": [Vector2(0.0, GROUND_Y - 20.0)],
			"element": Elements.Element.ARCANE,
			# instant; the whole event is the 0.26 s shove
			"frames": [2, 4, 7, 10, 14, 20],
		},
	]


func _run() -> void:
	for _i: int in 20:
		await process_frame
	for r: int in _rows.size():
		await _shoot_row(r)
	var err: int = _sheet.save_png(_out)
	if err == OK:
		print("ult_sheet: saved ", ProjectSettings.globalize_path(_out))
	else:
		printerr("ult_sheet: save failed err=", err)
	quit(0)


func _shoot_row(r: int) -> void:
	var row: Dictionary = _rows[r]
	# Hit-stop leaves Engine.time_scale mid-ramp; a row that starts slowed shoots
	# a different timeline than the row above it and the comparison is worthless.
	Engine.time_scale = 1.0
	_clear_residue()
	for _i: int in 6:
		await process_frame
	var node: Node2D = _spawn(String(row["path"]))
	if node == null:
		printerr("ult_sheet: could not spawn ", row["path"])
		return
	_arena.add_child(node)
	node.set("element_id", int(row["element"]))
	node.callv(String(row["method"]), row["args"] as Array)
	var frames: Array = row["frames"]
	var prev: int = 0
	for c: int in COLS:
		var want: int = int(frames[c])
		for _i: int in maxi(want - prev, 1):
			await process_frame
		prev = want
		await RenderingServer.frame_post_draw
		_grab(r, c)
	if is_instance_valid(node):
		node.queue_free()
	print("ult_sheet: row ", r, " ", row["label"])


## Instantiate a row's spectacle from either a .tscn (EnergyNova) or a .gd.
func _spawn(path: String) -> Node2D:
	if path.ends_with(".tscn"):
		var packed: PackedScene = load(path)
		return packed.instantiate() as Node2D if packed != null else null
	var gds: GDScript = load(path)
	return gds.new() as Node2D if gds != null else null


## Craters, scorch, ember pools and debris outlive their caster ON PURPOSE (they
## are parented to the arena). Left alone they accumulate under every subsequent
## row and the later ults get judged through the previous ults' litter.
func _clear_residue() -> void:
	for c: Node in _arena.get_children():
		if c is Camera2D or c is StaticBody2D or c is ColorRect or c is PostProcess:
			continue
		if c.is_in_group("enemy"):
			continue
		c.queue_free()


func _grab(r: int, c: int) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, r * CELL.y))
