# Visual verification for RAISE THRALL and GRAVE TIDE.
# GUI binary required — the headless dummy renderer writes BLANK pngs while
# cheerfully reporting success:
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/thrall_capture.gd
# Output lands in %APPDATA%\Godot\app_userdata\Legacy Frontier\.
#
# WHAT TO LOOK FOR, because these are the claims only an eyeball can settle:
#
#   thrall_1_ceremony.png     THE MARK IS A CEREMONY, NOT A PUFF. A flat ring lying on
#                             the floor with a closing fill arc, a tether running back
#                             to the caster's hand, and hands starting to break the
#                             surface. If it reads as a particle burst, the summoning
#                             circle has failed and the fix is the circle.
#   thrall_2_risen.png        THE BODIES ARE VISIBLY YOURS. Grave-violet, next to the
#                             orange enemy line, at a glance, with no label.
#   thrall_3_low.png          THE SAME FRAME AT graphics_quality = LOW. The ring, the
#                             fill and the hands must all still be there; only the
#                             tether, the inner star and half the hands go.
#   tide_1_crest.png          THE FRONT IS UNMISTAKABLE. Two walls of hands moving out
#                             from the caster, denser at the leading edge. If you
#                             cannot tell which way it is going, the crest has failed.
#   tide_2_grip.png           THE DRAIN READS. Threads from every held body back to the
#                             Warlock. This is the only thing on screen that says the
#                             ult is feeding him.
#   tide_3_low.png            LOW. Crest and threads survive; the wake thins.
#   tide_4_wide_640x360.png   THE HONEST ONE — the project's real 640x360 base
#                             viewport. If the tide does not read here it does not read.
extends SceneTree

const RAISE_SCRIPT: String = "res://scripts/combat/RaiseThrall.gd"
const TIDE_SCRIPT: String = "res://scripts/combat/GraveTide.gd"
const ENEMY_SCENE: String = "res://scenes/combat/Enemy.tscn"

const FLOOR_TOP: float = 120.0
const NEAR_ZOOM: float = 1.5
## The project renders at a 640x360 base viewport, so this is what a phone shows.
const WIDE_ZOOM: float = 0.62
const SHADOW := Color(0.62, 0.45, 0.88)

var _scene: Node2D = null
var _cam: Camera2D = null
var _slab: StaticBody2D = null


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await physics_frame
	await _capture_raise(false, "thrall_1_ceremony.png", "thrall_2_risen.png")
	await _capture_raise(true, "", "thrall_3_low.png")
	await _capture_tide(false, NEAR_ZOOM, "tide_1_crest.png", "tide_2_grip.png")
	await _capture_tide(true, NEAR_ZOOM, "", "tide_3_low.png")
	await _capture_tide(false, WIDE_ZOOM, "", "tide_4_wide_640x360.png")
	quit(0)


# ------------------------------------------------------------------- RAISE THRALL
func _capture_raise(low: bool, mid_shot: String, late_shot: String) -> void:
	_quality(low)
	_build(Vector2(60.0, 40.0), NEAR_ZOOM)
	var caster: Node2D = _stick(Vector2(-90.0, FLOOR_TOP - 16.0), Color(0.45, 0.75, 1.0))
	# A corpse the raise can claim — the good case, and the one worth photographing.
	var raise_gs: GDScript = load(RAISE_SCRIPT) as GDScript
	raise_gs.call(&"clear_graves")
	raise_gs.call(&"note_grave", Vector2(120.0, FLOOR_TOP))
	_enemy(Vector2(300.0, FLOOR_TOP - 20.0))
	var rt: Node2D = _cast(RAISE_SCRIPT, caster, Vector2(-90.0, FLOOR_TOP - 10.0),
		Vector2(120.0, FLOOR_TOP), 0, 260.0, 58, 6.4)
	if mid_shot != "":
		await _hold(46)          # ~0.38 s — mid-ceremony, the ring filling
		await _save(mid_shot)
		await _hold(58)          # ...past the raise
	else:
		await _hold(60)
	if late_shot != "":
		await _save(late_shot)
	if is_instance_valid(rt):
		rt.queue_free()
	_teardown()


# --------------------------------------------------------------------- GRAVE TIDE
func _capture_tide(low: bool, zoom: float, crest_shot: String, grip_shot: String) -> void:
	_quality(low)
	_build(Vector2(0.0, 30.0), zoom)
	var caster: Node2D = _stick(Vector2(0.0, FLOOR_TOP - 16.0), Color(0.45, 0.75, 1.0))
	for x: float in [-360.0, -180.0, 190.0, 340.0]:
		_enemy(Vector2(x, FLOOR_TOP - 20.0))
	var tide: Node2D = _cast(TIDE_SCRIPT, caster, Vector2(0.0, FLOOR_TOP - 10.0),
		Vector2(200.0, FLOOR_TOP), 40, 520.0, 74, 9.0)
	if crest_shot != "":
		await _hold(70)          # ~0.58 s — lead spent, fronts mid-room
		await _save(crest_shot)
		await _hold(70)
	else:
		await _hold(130)
	if grip_shot != "":
		await _save(grip_shot)
	if is_instance_valid(tide):
		tide.queue_free()
	_teardown()


# ------------------------------------------------------------------------ helpers
func _cast(path: String, caster: Node, origin: Vector2, target: Vector2,
		dmg: int, reach: float, mp: int, cd: float) -> Node2D:
	var gs: GDScript = load(path) as GDScript
	if gs == null:
		return null
	var s := SpellDef.new()
	s.id = "capture"
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.SHADOW
	s.effect = "shadow"
	s.damage = dmg
	s.reach = reach
	s.mp_cost = mp
	s.cooldown = cd
	var n: Node2D = gs.new()
	_scene.add_child(n)
	n.set("element_id", Elements.Element.SHADOW)
	n.set("spell_tier", SpellTier.of(s))
	n.set("caster_node", caster)
	n.set("target_group", "mortal")
	n.set("_target_group", "mortal")
	n.call(&"hex", caster, origin, target, s, SHADOW, "shadow")
	return n


## A real Enemy, so the "is that one mine?" question is asked against the actual
## orange silhouette the game ships rather than against a coloured box.
##
## `hp` is raised well above the CHASER's shipped 24 for the tide shots on purpose:
## at stock HP the ult's own 40 damage kills every victim on contact, `_victims`
## empties on the same frame, and the DRAIN THREADS — the only thing on screen that
## says the ult is feeding the caster — never get drawn in the frame meant to show
## them. This is a photographic fixture, not a balance statement.
func _enemy(at: Vector2, hp: int = 24) -> Node:
	var e: Node = (load(ENEMY_SCENE) as PackedScene).instantiate()
	e.set(&"max_hp", hp)
	_scene.add_child(e)
	(e as Node2D).global_position = at
	return e


## The caster stand-in: a CharacterRig on a bare Node2D. Hero.tscn drags the whole
## input/HUD/net stack in and none of it is being photographed here.
func _stick(at: Vector2, col: Color) -> Node2D:
	var holder := Node2D.new()
	var rig := CharacterRig.new()
	rig.limb_color = col
	holder.add_child(rig)
	_scene.add_child(holder)
	holder.global_position = at
	return holder


## Force the cheap picture on / off.
##
## ⚠ AUTOLOADS ARE NOT REGISTERED UNDER `--script`, so `/root/Tuning` does not exist
## here and `TuningConfig.quality_is_low()` would answer AUTO -> desktop -> HIGH for
## every frame — i.e. the "LOW" captures would silently be the full picture, which is
## the exact opposite of what they are for. So the node is STOOD UP by hand under the
## name the static probe looks for, with a real TuningConfig on it.
func _quality(low: bool) -> void:
	var t: Node = root.get_node_or_null(^"/root/Tuning")
	if t == null:
		var gs: GDScript = load("res://scripts/combat/Tuning.gd") as GDScript
		if gs == null:
			return
		t = gs.new()
		t.name = "Tuning"
		root.add_child(t)
	if t.get(&"cfg") == null:
		t.set(&"cfg", TuningConfig.new())
	t.cfg.graphics_quality = TuningConfig.Quality.LOW if low else TuningConfig.Quality.HIGH
	if TuningConfig.quality_is_low() != low:
		printerr("capture: could not force graphics_quality — the LOW frames are a lie")


func _hold(frames: int) -> void:
	for _i: int in frames:
		await physics_frame


func _build(cam_at: Vector2, zoom: float) -> void:
	RenderingServer.set_default_clear_color(Color(0.10, 0.10, 0.14))
	_scene = Node2D.new()
	Atmosphere.add_glow(_scene)
	PostProcess.add(_scene)
	root.add_child(_scene)
	# A REAL StaticBody2D floor, not a decal: the tide walks `SpellWorld.ground_path`,
	# so without a collider these frames would show the flat fallback rather than the
	# terrain-following path the spell actually uses in game.
	_slab = StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1800.0, 60.0)
	cs.shape = shape
	_slab.add_child(cs)
	root.add_child(_slab)
	_slab.global_position = Vector2(0.0, FLOOR_TOP + 30.0)
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-900.0, 0.0), Vector2(900.0, 0.0),
		Vector2(900.0, 60.0), Vector2(-900.0, 60.0)])
	p.color = Color(0.18, 0.19, 0.24)
	p.position = Vector2(0.0, FLOOR_TOP)
	p.z_index = -5
	_scene.add_child(p)
	_cam = Camera2D.new()
	_cam.position = cam_at
	_cam.zoom = Vector2(zoom, zoom)
	_scene.add_child(_cam)
	_cam.make_current()


func _teardown() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	if _slab != null and is_instance_valid(_slab):
		_slab.queue_free()
	_scene = null
	_slab = null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("wrote ", fname)
