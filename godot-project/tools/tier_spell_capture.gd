# Visual verification for the seven NEW drop spectacles (the three that reuse an
# existing spectacle — Arc of Fools, Meteor Storm — are already covered by the
# lightning and meteor capture tools).
# GUI binary required — the headless dummy renderer draws nothing:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/tier_spell_capture.gd
# Output lands in %APPDATA%\Godot\app_userdata\Legacy Frontier\.
#
# WHAT TO LOOK FOR — one claim per spell, and each is a claim the CODE makes that
# only a picture can settle:
#   PETRIFY       the statue must not look like a tinted stick figure. It is drawn
#                 BLOCKIER than the rig on purpose: "is that one petrified?" has to
#                 be answerable across the room.
#   GRAVITY FLIP  the motes have to say WHICH WAY, and the last second has to
#                 announce the landing. There is no ring to draw — this is the
#                 whole readability budget.
#   BLOOD PACT    the remaining-duration arc is at your own feet. If you cannot
#                 read how much bleeding is left without looking away from the
#                 fight, it has failed.
#   MIRROR IMAGE  the clone must NOT be mistakable for a second player. It is
#                 translucent violet with a shimmer ring for exactly that reason.
#   THE VOID      TWO rings: the wide one PULLS, the bright one KILLS. The trap is
#                 supposed to be visible.
#   CHRONOSTASIS  the boundary has to be hard — standing one pixel outside it is a
#                 different fight — and the frozen shards must NOT drift.
#   EQUINOX       scale-pans, not a ring: a ring says "stay outside me" and there
#                 is no outside. The afterglow marks who gained and who paid.
#
# Deliberately NOT the SpellPlayground — that scene pulls in scripts/spike, which
# other agents edit, and a capture tool that cannot render because someone else's
# file is mid-write is a capture tool that stops being used. Same reasoning (and
# the same bare arena) as tools/ward_capture.gd.
extends SceneTree

const STUB := "res://tools/_stub_body.gd"
const FLOOR_TOP: float = 200.0
const CASTER_AT := Vector2(-180.0, 170.0)

var _scene: Node2D = null
var _cam: Camera2D = null
var _caster: Node2D = null


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await _shoot("petrify", "res://scripts/combat/Petrify.gd", "hex",
		[["tier_1_petrify_telegraph.png", 30], ["tier_2_petrify_statue.png", 60]], 0.8)
	await _shoot("gravity_flip", "res://scripts/combat/GravityFlip.gd", "hex",
		[["tier_3_gravity_rising.png", 60], ["tier_4_gravity_warning.png", 480]], 0.62)
	await _shoot("blood_pact", "res://scripts/combat/BloodPact.gd", "hex",
		[["tier_5_bloodpact_ring.png", 40], ["tier_6_bloodpact_half_spent.png", 460]], 1.1)
	await _shoot("mirror_image", "res://scripts/combat/MirrorImage.gd", "hex",
		[["tier_7_mirror_clone.png", 140]], 1.0)
	await _shoot("the_void", "res://scripts/combat/VoidCollapse.gd", "cataclysm",
		[["tier_8_void_pull.png", 60], ["tier_9_void_collapse.png", 118]], 0.7)
	await _shoot("chronostasis", "res://scripts/combat/Chronostasis.gd", "cataclysm",
		[["tier_10_chronostasis_frozen.png", 90], ["tier_11_chronostasis_banked.png", 300]], 0.66)
	await _shoot("equinox", "res://scripts/combat/Equinox.gd", "cataclysm",
		[["tier_12_equinox_scales.png", 60], ["tier_13_equinox_afterglow.png", 105]], 0.7)
	quit(0)


## Stage a working, then save a frame at each requested tick count.
func _shoot(spell_id: String, script_path: String, entry: String,
		shots: Array, zoom: float) -> void:
	_build(zoom)
	var bodies: Array[Node2D] = _crowd()
	for i: int in 6:
		await physics_frame
	var spell: SpellDef = SpellLibrary.drop_by_id(spell_id)
	var node: Node2D = (load(script_path) as GDScript).new()
	_scene.add_child(node)
	# Stamped by hand, exactly as `SpellCaster._stamp` would. `target_group` is the
	# shared `mortal` group because friendly fire is live — these spells are
	# supposed to find the caster's own side.
	node.set(&"caster_node", _caster)
	node.set(&"element_id", spell.element)
	node.set(&"spell_tier", SpellTier.of(spell))
	node.set(&"target_group", "mortal")
	node.set(&"_target_group", "mortal")
	node.call(entry, _caster, CASTER_AT, Vector2(60.0, 170.0), spell,
		spell.resolve_color(Color(0.8, 0.7, 1.0)), spell.effect)
	# CHRONOSTASIS ONLY: bank something, or the "look how much is about to happen"
	# core never lights and the second frame is indistinguishable from the first.
	if spell_id == "chronostasis":
		for i: int in 20:
			await physics_frame
		for b: Node2D in bodies:
			b.call(&"take_damage", 40)
	# EQUINOX ONLY: an uneven room, or a levelling has nothing to level.
	if spell_id == "equinox":
		bodies[0].set(&"hp", 12)
		bodies[1].set(&"hp", 96)
	var seen: int = 0
	for shot: Array in shots:
		var want: int = int(shot[1])
		while seen < want:
			await physics_frame
			seen += 1
		await _save(String(shot[0]))
	_teardown()


## A caster and three bodies to be spelled at. Plain `Node2D` stubs rather than real
## heroes: `Hero.tscn` drags the whole rig + bot stack in, and none of it changes
## what these seven effects DRAW.
func _crowd() -> Array[Node2D]:
	_caster = _body(CASTER_AT, Color(0.4, 0.7, 1.0))
	var out: Array[Node2D] = []
	for x: float in [40.0, 110.0, 175.0]:
		out.append(_body(Vector2(x, 170.0), Color(0.95, 0.5, 0.25)))
	return out


func _body(at: Vector2, col: Color) -> Node2D:
	var n: Node2D = (load(STUB) as GDScript).new()
	_scene.add_child(n)
	n.global_position = at
	n.add_to_group(&"mortal")
	# A visible marker, so a frame shows WHERE the bodies were when the effect hit.
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(-7, 0), Vector2(7, 0), Vector2(7, -30), Vector2(-7, -30)])
	p.color = col
	n.add_child(p)
	return n


func _build(zoom: float) -> void:
	RenderingServer.set_default_clear_color(Color(0.12, 0.13, 0.17))
	_scene = Node2D.new()
	Atmosphere.add_glow(_scene)
	PostProcess.add(_scene)
	root.add_child(_scene)
	# A REAL collider: Petrify's throw clips against solid geometry, and a painted
	# rectangle would make this tool only ever capture the un-clipped case.
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_scene.add_child(body)
	body.global_position = Vector2(0.0, FLOOR_TOP + 40.0)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2000.0, 80.0)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.add_child(cs)
	var floor_poly := Polygon2D.new()
	floor_poly.polygon = PackedVector2Array([
		Vector2(-1000, -40), Vector2(1000, -40), Vector2(1000, 40), Vector2(-1000, 40)])
	floor_poly.color = Color(0.20, 0.22, 0.27)
	floor_poly.position = Vector2(0.0, FLOOR_TOP + 40.0)
	floor_poly.z_index = -5
	_scene.add_child(floor_poly)
	_cam = Camera2D.new()
	_cam.position = Vector2(0.0, 120.0)
	_cam.zoom = Vector2(zoom, zoom)
	_scene.add_child(_cam)
	_cam.make_current()


func _teardown() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	_caster = null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("tiercap saved ", fname)
