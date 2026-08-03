# LOOK AT THE FIVE MELEE SIGNATURES. Tests cannot settle whether a cut reads as a
# cut, and the whole point of these five spells is that no two of them look alike.
#
# GUI BINARY REQUIRED — the headless dummy renderer writes BLANK PNGs while
# reporting success:
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/melee_signature_capture.gd
# or:  python python-tools/run_capture.py melee_signature
# Output lands in %APPDATA%\Godot\app_userdata\Legacy Frontier\.
#
# ══════════════════════════════════════════════════════════════════════════════
# WHAT TO LOOK FOR — one claim per frame, each a claim the CODE makes that only a
# picture can settle.
# ══════════════════════════════════════════════════════════════════════════════
#  THOUSAND CUTS  the mark must read as a NOOSE closing on one body, and the cuts
#                 must come from DIFFERENT SIDES of it. If the crescents all fan out
#                 in front of the caster it has become Blade Flurry and failed.
#  IAI SLASH      one cut, and it must look COMMITTED — a single long tapered lens,
#                 not a swipe. The draw frame must state the corridor's width before
#                 anything happens.
#  CRESCENT STEP  the trail must be CONTINUOUS from the origin to the body. A gap
#                 anywhere reads as a teleport, which is the one thing it must not be.
#  SHOCKWAVE STOMP the ridge must FOLLOW THE STEP in the floor. That is why this rig
#                 builds one: on flat ground a terrain-tracking wave and a straight
#                 line are the same picture, so the test proves nothing.
#  METEOR FIST    the shadow on the landing ring is the only depth cue a falling body
#                 has. If you cannot tell how close the impact is from the shadow
#                 alone, it has failed.
#
# ── HOW THE TIMELINE IS DRIVEN ────────────────────────────────────────────────
# Every one of the five exposes `advance(delta)` (the deterministic step
# `BlinkStrike` established), so this tool switches their `_process` OFF and steps
# them by hand at a fixed dt while still awaiting REAL frames — which is what lets it
# photograph an exact moment rather than whichever moment the frame pacing landed on.
#
# Deliberately NOT the SpellPlayground: that scene pulls in `scripts/spike`, which
# other agents edit, and a capture tool that cannot render because someone else's file
# is mid-write is a capture tool that stops being used. Same bare-arena reasoning (and
# the same shape) as tools/tier_spell_capture.gd and tools/ward_capture.gd.
extends SceneTree

const CUTS_PATH: String = "res://scripts/combat/ThousandCuts.gd"
const IAI_PATH: String = "res://scripts/combat/IaiSlash.gd"
const STEP_PATH: String = "res://scripts/combat/CrescentStep.gd"
const STOMP_PATH: String = "res://scripts/combat/ShockwaveStomp.gd"
const FIST_PATH: String = "res://scripts/combat/MeteorFist.gd"

const STUB: String = "res://tools/_stub_body.gd"
const DT: float = 1.0 / 120.0
## Top of the main floor slab, in world y.
const FLOOR_TOP: float = 210.0
## Where the floor DROPS, and how far. The step is what makes Shockwave Stomp's
## terrain tracking photographable at all — on flat ground a wave that follows the
## floor and one that ignores it are the same picture.
##
## ⚠ A DROP AND NOT A RISE, AND THAT IS A FINDING ABOUT THE SPELL, NOT A STAGING
## CHOICE. `SpellWorld.ground_path` probes DOWNWARD from the caster's own foot height,
## so it can follow ground that falls away and cannot see ground that rises above the
## probe's start. The first version of this rig built a raised ledge and photographed
## a perfectly flat ridge, which looked like the tracking was dead when it was the
## probe direction. A step UP is a real limitation of the shared helper and is written
## up in the handoff; this rig photographs the case the helper actually supports.
const STEP_X: float = 150.0
const DROP_TOP: float = 268.0

var _scene: Node2D = null
var _caster: Node2D = null


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	# ⚠ ONE FRAME BEFORE ANYTHING IS BUILT, AND IT IS LOAD-BEARING. `_initialize()`
	# calls this synchronously, and at that point the SceneTree root is not yet
	# `inside_tree` — so every `get_node("/root/...")` made from a node added during
	# it FAILS with "Can't use get_node() with absolute paths from outside the active
	# scene tree". That is exactly how a spectacle reaches `SpellReactor`, so without
	# this line the FIRST spell in the shot list would quietly never join the reaction
	# system and would be photographed in a state the game never produces. (Measured:
	# `root.is_inside_tree()` is false on the first shot and true on every later one.)
	await process_frame
	await _shoot_cuts()
	await _shoot_iai()
	await _shoot_step()
	await _shoot_stomp()
	await _shoot_fist()
	quit(0)


# ═══════════════════════════════════════════════════════════════════════════════
## THOUSAND CUTS — the mark, mid-orbit, and the reappearance.
func _shoot_cuts() -> void:
	await _build(0.85, Vector2(-20.0, 90.0))
	var caster: Node2D = _figure(Vector2(-260.0, FLOOR_TOP), Color(0.45, 0.7, 1.0), true)
	_figure(Vector2(0.0, FLOOR_TOP), Color(0.95, 0.5, 0.25))       # the mark
	_figure(Vector2(130.0, FLOOR_TOP), Color(0.95, 0.5, 0.25))     # a body on the rim
	var spell: SpellDef = _def("thousand_cuts", SpellDef.Kind.HEX, Elements.Element.SHADOW,
		{"mp_cost": 72, "cooldown": 8.0, "damage": 16, "count": 7, "reach": 300.0})
	var node: Node2D = _cast(CUTS_PATH, spell, caster, caster.global_position,
		Vector2(0.0, FLOOR_TOP - 20.0))
	await _step_to(node, 0.34)
	await _save("melee_1_cuts_mark.png")          # the noose closing on the mark
	await _step_to(node, 0.90)
	await _save("melee_2_cuts_orbit.png")         # crescents from several sides at once
	# ⚠ NOT AT THE MOMENT OF THE FINISHER (t≈1.37). The shadow family's shared
	# punctuation is `ImpactFrame.Style.INVERT`, which turns the WHOLE SCREEN into a
	# colour negative for a beat — correct in play, and it photographs as a grey field
	# with the spell invisible inside it. This is a fifth of a second later, once the
	# negative has cleared and the heavier final crescent is still on screen.
	await _step_to(node, 1.56)
	await _save("melee_3_cuts_finish.png")        # the heavier reappearance
	await _teardown()


# ═══════════════════════════════════════════════════════════════════════════════
## IAI SLASH — the draw (the corridor stated) and the cut (one committed lens).
func _shoot_iai() -> void:
	await _build(0.85, Vector2(90.0, 40.0))
	var caster: Node2D = _figure(Vector2(-40.0, FLOOR_TOP), Color(0.45, 0.7, 1.0), true)
	_figure(Vector2(80.0, FLOOR_TOP), Color(0.95, 0.5, 0.25))
	var spell: SpellDef = _def("iai_slash", SpellDef.Kind.HEX, Elements.Element.ARCANE,
		{"mp_cost": 44, "cooldown": 5.0, "damage": 96, "reach": 118.0, "width": 52.0})
	var node: Node2D = _cast(IAI_PATH, spell, caster, caster.global_position,
		Vector2(200.0, FLOOR_TOP))
	await _step_to(node, 0.22)
	await _save("melee_4_iai_draw.png")           # the gleam + the corridor's width
	await _step_to(node, 0.36)
	await _save("melee_5_iai_cut.png")            # ONE lens, needle to needle
	await _teardown()


# ═══════════════════════════════════════════════════════════════════════════════
## CRESCENT STEP — the promised lane, then the trail. THE FRAME THAT MATTERS is the
## second one: the ribbon must be unbroken from the origin to the body.
func _shoot_step() -> void:
	await _build(0.72, Vector2(90.0, 50.0))
	var caster: Node2D = _figure(Vector2(-180.0, FLOOR_TOP), Color(0.45, 0.7, 1.0), true)
	for x: float in [-60.0, 30.0]:
		_figure(Vector2(x, FLOOR_TOP), Color(0.95, 0.5, 0.25))
	var spell: SpellDef = _def("crescent_step", SpellDef.Kind.HEX, Elements.Element.ARCANE,
		{"mp_cost": 40, "cooldown": 4.6, "damage": 58, "reach": 240.0, "width": 44.0})
	var node: Node2D = _cast(STEP_PATH, spell, caster, caster.global_position,
		Vector2(200.0, FLOOR_TOP))
	await _step_to(node, 0.14)
	await _save("melee_6_step_lane.png")          # the whole lane, drawn before he moves
	await _step_to(node, 0.32)
	await _save("melee_7_step_travel.png")        # CONTINUOUS trail + leading blade
	await _teardown()


# ═══════════════════════════════════════════════════════════════════════════════
## SHOCKWAVE STOMP — the two lanes, then the ridges running. The right-hand ridge
## must DROP OVER THE STEP in the floor; a straight line here means the terrain
## tracking is dead. (See STEP_X for why the step goes down rather than up.)
func _shoot_stomp() -> void:
	await _build(0.60, Vector2(20.0, 60.0))
	var caster: Node2D = _figure(Vector2(-40.0, FLOOR_TOP), Color(0.45, 0.7, 1.0), true)
	_figure(Vector2(215.0, DROP_TOP), Color(0.95, 0.5, 0.25))      # below the step
	_figure(Vector2(-280.0, FLOOR_TOP), Color(0.95, 0.5, 0.25))    # on the flat, left
	var spell: SpellDef = _def("shockwave_stomp", SpellDef.Kind.HEX, Elements.Element.EARTH,
		{"mp_cost": 42, "cooldown": 4.0, "damage": 54, "reach": 300.0})
	var node: Node2D = _cast(STOMP_PATH, spell, caster, caster.global_position,
		Vector2(200.0, FLOOR_TOP))
	await _step_to(node, 0.16)
	await _save("melee_8_stomp_wind.png")         # the reach marked, before the boot
	await _step_to(node, 0.68)
	await _save("melee_9_stomp_ridges.png")       # both crests running; right one BELOW the step
	await _teardown()


# ═══════════════════════════════════════════════════════════════════════════════
## METEOR FIST — the marked ring, the body in the air over it, and the crater.
func _shoot_fist() -> void:
	await _build(0.55, Vector2(60.0, 20.0))
	var caster: Node2D = _figure(Vector2(-250.0, FLOOR_TOP), Color(0.45, 0.7, 1.0), true)
	_figure(Vector2(20.0, FLOOR_TOP), Color(0.95, 0.5, 0.25))
	var spell: SpellDef = _def("meteor_fist", SpellDef.Kind.HEX, Elements.Element.EARTH,
		{"mp_cost": 78, "cooldown": 8.5, "damage": 120, "radius": 110.0, "reach": 260.0})
	var node: Node2D = _cast(FIST_PATH, spell, caster, caster.global_position,
		Vector2(20.0, FLOOR_TOP))
	await _step_to(node, 0.30)
	await _save("melee_10_fist_mark.png")         # the ring at 1:1 with the blast radius
	await _step_to(node, 0.62)
	await _save("melee_11_fist_flight.png")       # the comet + THE SHADOW (the depth cue)
	await _step_to(node, 0.82)
	await _save("melee_12_fist_impact.png")       # the ult mark at the moment of contact
	# ⚠ AND A LATER ONE, because the ULT punctuation (`Juice.tier_frame`) floods the
	# whole screen with the element's colour field for a beat — the frame above is the
	# IMPACT and is supposed to look like that, but it makes the crater unreviewable.
	# `BlastSpell` runs on its own `_process` and outlives this node, so the wait is a
	# plain frame wait rather than another `_step_to`.
	await _wait(70)
	await _save("melee_13_fist_crater.png")       # the residue, once the flash has gone
	await _teardown()


# ══════════════════════════════════════════════════════════════════════ the rig
## Build the spectacle, stamp it exactly as `SpellCaster._stamp` would, and fire it.
##
## ⚠ THE STAMP IS ALL FIVE PROPERTIES, both spellings of the group. `set()` on an
## undeclared property is a silent no-op, and `target_group` is the shared `mortal`
## group here because friendly fire is always on — these spells are supposed to be
## able to find the caster's own side.
func _cast(path: String, spell: SpellDef, caster: Node2D, from: Vector2,
		to: Vector2) -> Node2D:
	var node: Node2D = (load(path) as GDScript).new()
	_scene.add_child(node)
	node.set(&"caster_node", caster)
	node.set(&"element_id", spell.element)
	node.set(&"spell_tier", SpellTier.of(spell))
	node.set(&"target_group", "mortal")
	node.set(&"_target_group", "mortal")
	# OUR clock, not the frame pacer's — see the header. Without this the moment each
	# PNG lands on drifts with the machine's load.
	node.set_process(false)
	node.call(&"hex", caster, from, to, spell,
		spell.resolve_color(Color(0.8, 0.7, 1.0)), spell.effect)
	return node


## Advance the spell to an ABSOLUTE `seconds` on its own clock, one real frame per
## step, so the particle systems and the post grade get frames to run in while the
## spell's timeline stays exactly where this tool put it.
##
## ⚠ ABSOLUTE, NOT RELATIVE, AND THAT IS THE WHOLE POINT: it reads the spectacle's own
## `_elapsed` rather than counting its own steps. A relative version silently ADDS the
## shot times together, so the third frame of a three-frame sequence asks for a moment
## past the end of the spell's life, the node has already freed itself, and the tool
## errors out having photographed only the first two. (It did exactly that on the
## first run of this file.) Every shot time below is therefore a timestamp that can be
## read straight off the spell's own constants.
func _step_to(node: Node2D, seconds: float) -> void:
	while true:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			# NOT `node.get_class()` in this message: the node may already be freed, and
			# calling anything on it here turns a useful warning into a script error.
			printerr("meleecap: the spell ended before t=%.2f — the shot list is past "
				% seconds + "its life, or a reaction consumed it")
			return
		if float(node.get(&"_elapsed")) >= seconds:
			return
		await physics_frame
		node.call(&"advance", DT)


## Let real frames pass without touching any spell clock. For photographing what
## OUTLIVES a spectacle — `BlastSpell` frees itself on its own timer long after
## `MeteorFist` is gone.
func _wait(frames: int) -> void:
	for i: int in frames:
		await physics_frame


## A SpellDef built here rather than looked up: these five are not in `SpellLibrary`
## yet (that file is owned elsewhere — see the handoff). Only the fields each spell
## actually reads are set; everything else keeps the resource's own defaults.
func _def(id: String, kind: int, element: int, fields: Dictionary) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = id
	s.kind = kind
	s.element = element
	s.use_element_color = true
	s.effect = Elements.effect_name(element)
	for k: String in fields:
		s.set(k, fields[k])
	return s


## A body-shaped marker. `_stub_body.gd` for the four properties a spectacle actually
## touches, plus a drawn rectangle so a frame shows WHERE the bodies were when the
## effect hit. Real `Hero.tscn` instances are deliberately avoided: they drag the whole
## rig + bot stack in and none of it changes what these five effects DRAW.
##
## `is_caster` bodies are given the duck-typed `blink_to` contract by a tiny inline
## script, because three of the five RELOCATE their caster and a figure that cannot be
## moved would photograph the spell with its subject standing still.
func _figure(feet: Vector2, col: Color, is_caster: bool = false) -> Node2D:
	var n: Node2D
	if is_caster:
		var gd := GDScript.new()
		gd.source_code = "extends Node2D\n" \
			+ "var hp: int = 1000\nvar max_hp: int = 1000\n" \
			+ "var velocity: Vector2 = Vector2.ZERO\n" \
			+ "func take_damage(_a: int) -> void:\n\tpass\n" \
			+ "func blink_to(dest: Vector2) -> Vector2:\n" \
			+ "\tglobal_position = dest\n\treturn dest\n"
		gd.reload()
		n = gd.new()
	else:
		n = (load(STUB) as GDScript).new()
	_scene.add_child(n)
	n.global_position = feet
	n.add_to_group(&"mortal")
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-7, 0), Vector2(7, 0), Vector2(7, -34), Vector2(-7, -34)])
	p.color = col
	n.add_child(p)
	if is_caster:
		_caster = n
	return n


## ⚠ AWAIT THIS. It yields — see the physics-flush note at the end.
func _build(zoom: float, cam_offset: Vector2) -> void:
	RenderingServer.set_default_clear_color(Color(0.11, 0.12, 0.16))
	_scene = Node2D.new()
	Atmosphere.add_glow(_scene)
	PostProcess.add(_scene)
	root.add_child(_scene)
	# REAL colliders, not painted rectangles. Shockwave Stomp probes the floor per
	# sample and Meteor Fist snaps its landing to it; with only a painted floor this
	# tool would forever photograph the flat fallback and never the real path.
	_slab(-1400.0, STEP_X, FLOOR_TOP)
	_slab(STEP_X, 1400.0, DROP_TOP)
	var cam := Camera2D.new()
	cam.position = cam_offset
	cam.zoom = Vector2(zoom, zoom)
	_scene.add_child(cam)
	cam.make_current()
	# ⚠ LET THE PHYSICS SERVER TAKE THE COLLIDERS BEFORE ANY SPELL IS FIRED, and this
	# is the second silent-failure this tool has caught. A StaticBody2D added to the
	# tree does not exist to `intersect_ray` until the physics server has flushed, and
	# `_cast` used to run in the SAME frame as `_build`. So every floor probe missed,
	# Shockwave Stomp fell through to its flat fallback, Meteor Fist never snapped its
	# landing — and the frames looked plausible, just flat. The tool was photographing
	# a world with no ground in it. (`tools/tier_spell_capture.gd` waits six frames for
	# the same reason.)
	for i: int in 4:
		await physics_frame


## One floor slab spanning x in [`x_from`, `x_to`] with its TOP at `top_y`: a
## StaticBody2D on collision layer 1 (the layer every floor probe in the game masks)
## plus a matching drawn polygon so it is visible in the frame.
func _slab(x_from: float, x_to: float, top_y: float) -> void:
	var size := Vector2(x_to - x_from, 400.0)
	var top_centre := Vector2((x_from + x_to) * 0.5, top_y)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_scene.add_child(body)
	body.global_position = top_centre + Vector2(0.0, size.y * 0.5)
	var shape := RectangleShape2D.new()
	shape.size = size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.add_child(cs)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	poly.color = Color(0.19, 0.21, 0.26)
	poly.position = body.global_position
	poly.z_index = -5
	_scene.add_child(poly)


## Tear the rig down and WAIT FOR IT TO ACTUALLY BE GONE.
##
## ⚠ THE WAIT IS LOAD-BEARING AND THIS TOOL LEARNED IT THE HARD WAY. Every spectacle
## registers with `SpellReactor` and only unregisters in `_exit_tree`, which does not
## run until the deferred free lands. Without the wait, the PREVIOUS shot's effect was
## still live in the reaction table when the next one registered — same form, same
## element, overlapping shapes, because every rig is built around the origin — and the
## reactor consumed one of them mid-capture. Crescent Step vanished at t≈0.3 and the
## frame photographed an empty lane.
##
## Three frames rather than one: `queue_free` lands on the next idle, and the
## colliders must also be out of the physics space before the next rig's are built.
func _teardown() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	_caster = null
	for i: int in 3:
		await physics_frame


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("meleecap saved ", fname)
