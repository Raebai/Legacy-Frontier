# Throwaway visual check for the four ranged signatures — Radiant Volley, Shatter,
# Heaven's Wrath and Fault Line. Each is caught at BOTH of its readable beats (the
# tell, then the payoff) so the "is this a recolour of the thing it replaced?"
# question can be answered by looking rather than by reading.
#
# ⚠ NEEDS THE GUI BINARY. `--headless` writes blank PNGs while reporting success:
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/ranged_signature_capture.gd
#
# The spells are instantiated DIRECTLY and handed the HEX entry function, exactly
# as `SpellCaster`'s HEX arm would: they are not in `HEX_SCRIPTS` yet (that edit is
# the maker's, in a file this agent does not own), and a capture tool that could
# only run after the wiring landed would be no use for deciding whether to land it.
extends SceneTree

const VOLLEY_PATH: String = "res://scripts/combat/RadiantVolley.gd"
const SHATTER_PATH: String = "res://scripts/combat/Shatter.gd"
const WRATH_PATH: String = "res://scripts/combat/HeavensWrath.gd"
const FAULT_PATH: String = "res://scripts/combat/FaultLine.gd"

var _scene: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _origin() -> Vector2:
	var fig: Node = _scene.get("_fig")
	return (fig.get("_torso") as Node2D).global_position


func _cast(path: String, target: Vector2, color: Color, fields: Dictionary) -> Node2D:
	var spec: Node2D = (load(path) as GDScript).new()
	_scene.add_child(spec)
	# What `SpellCaster._stamp()` writes. Kept here so the captured picture is the
	# one a real cast produces — the sigil reads `spell_tier` for its radius and
	# `element_id` for its rim band, so an un-stamped capture is a different image.
	spec.set("element_id", int(fields.get("element", -1)))
	spec.set("spell_tier", int(fields.get("tier", SpellTier.Tier.HEAVY)))
	spec.set("caster_node", null)
	spec.set("target_group", "enemy")
	spec.set("_target_group", "enemy")
	var spell := SpellDef.new()
	for k: String in fields:
		if k == "tier":
			continue
		spell.set(k, fields[k])
	spec.call("hex", null, _origin(), target, spell, color, "")
	return spec


func _run() -> void:
	for i in 90:
		await physics_frame   # settle the figure + dummies onto the floor

	# 1) RADIANT VOLLEY — the rack (tell), then the rank in flight (payoff).
	#    Aimed flat along the dummy line so the piercing read is visible.
	_cast(VOLLEY_PATH, Vector2(560.0, _origin().y),
		Color(1.0, 0.92, 0.55),
		{"damage": 14, "length": 760.0, "element": Elements.Element.HOLY,
		"tier": SpellTier.Tier.HEAVY})
	await create_timer(0.14).timeout
	await _save("ranged_volley_rack.png")
	await create_timer(0.46).timeout
	await _save("ranged_volley_flight.png")
	await create_timer(1.4).timeout

	# 2) SHATTER — on a FROZEN body, which is the whole point of the spell.
	#
	#    ⚠ THE FREEZE IS APPLIED DIRECTLY rather than by running a real Blizzard,
	#    and that is a deliberate correction to a first pass that did run one. The
	#    field's own three beats (rime -> encase -> its own shatter) fire on their
	#    own clock, so the photograph came back full of driven snow and a
	#    full-screen encase flash that had nothing to do with this spell — and the
	#    body had already thawed by the time the fuse burned. Two ice applications
	#    is exactly what the field does to a body at a full meter, minus the
	#    weather. (The Blizzard-rime path itself is covered by
	#    tools/slice_test_ranged_signatures.gd, which can assert it without a camera.)
	var frozen: Node2D = _nearest_dummy()
	var mark: Vector2 = Vector2(220.0, _origin().y)
	if frozen != null:
		mark = frozen.global_position
		if frozen.has_method("apply_status"):
			frozen.call("apply_status", Elements.Element.ICE, false)
			frozen.call("apply_status", Elements.Element.ICE, false)
	_cast(SHATTER_PATH, mark, Elements.color(Elements.Element.ICE),
		{"damage": 42, "radius": 104.0, "element": Elements.Element.ICE,
		"tier": SpellTier.Tier.HEAVY})
	await create_timer(0.20).timeout
	await _save("ranged_shatter_fuse.png")
	await create_timer(0.14).timeout
	await _save("ranged_shatter_break.png")
	await create_timer(1.2).timeout

	# 3) HEAVEN'S WRATH — a burning mark under the cloud (tell), then the bolt.
	_cast(WRATH_PATH, Vector2(180.0, _origin().y + 60.0),
		Elements.color(Elements.Element.LIGHTNING),
		{"damage": 42, "element": Elements.Element.LIGHTNING,
		"tier": SpellTier.Tier.ULT})
	await create_timer(0.58).timeout
	await _save("ranged_wrath_mark.png")
	await create_timer(0.22).timeout
	await _save("ranged_wrath_bolt.png")
	await create_timer(3.0).timeout

	# 4) FAULT LINE — the whole path lit before anything moves (tell), then the
	#    crest mid-travel with the scar behind it.
	_cast(FAULT_PATH, Vector2(700.0, _origin().y),
		Elements.color(Elements.Element.EARTH),
		{"damage": 105, "length": 760.0, "element": Elements.Element.EARTH,
		"tier": SpellTier.Tier.ULT})
	await create_timer(0.26).timeout
	await _save("ranged_fault_seam.png")
	await create_timer(0.62).timeout
	await _save("ranged_fault_crest.png")
	await create_timer(1.2).timeout
	quit(0)


func _nearest_dummy() -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for n: Node in root.get_tree().get_nodes_in_group("enemy"):
		if not n is Node2D or not is_instance_valid(n):
			continue
		var d: float = (n as Node2D).global_position.distance_to(_origin())
		if d < best_d:
			best_d = d
			best = n as Node2D
	return best


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("rangedcap saved ", fname)
