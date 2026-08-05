# DIAGNOSTIC PROBE — do two ordinary bolts clash, and can this probe see a
# reaction at all?
#
#   godot --headless --path godot-project --script tools/_probe_spell_clash.gd
#
# Read-only investigation tool. Asserts nothing; it PRINTS what the live reactor
# does. Three live cases, run against the REAL scripts (not stubs) so a "no
# reaction" answer cannot be an artefact of a fake participant:
#
#   A  bolt vs bolt         — the ask. Two Spell.tscn bolts on a collision course.
#   B  bolt vs ice wall     — POSITIVE CONTROL on the SAME bolt object. If this
#                             fires, the bolt is a working participant and A's
#                             silence is the TABLE, not the bolt.
#   C  beam vs beam         — POSITIVE CONTROL on two heavier participants.
#
# Spectacle setup is minimised to the fields the reaction contract reads
# (raise_wall()/fire() also do particles, sigils, floor raycasts and SFX that a
# headless run has no business doing). Every reaction accessor called is the
# script's own real method.
extends SceneTree

var _ran: bool = false
var _log: Array[String] = []


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("PROBE ABORT: SpellReactor autoload missing")
		quit(1)
		return true
	reactor.set_process(false)           # drive the sweep by hand
	reactor.set(&"spawn_effects", false) # detection only — no 1.6 s spectacles
	reactor.connect(&"reaction_fired", _on_fired)

	_bucket_census()
	_table_probe()
	_case_a_bolt_vs_bolt(reactor)
	_case_b_bolt_vs_ice_wall(reactor)
	_case_c_beam_vs_beam(reactor)
	_case_d_melee_swat_contract()
	_case_e_tick_window()

	print("\n================ PROBE SUMMARY ================")
	for line: String in _log:
		print("  ", line)
	quit(0)
	return true


func _on_fired(outcome: String, point: Vector2, a: Node, b: Node) -> void:
	print("      >> reaction_fired: %s at %s  (%s x %s)"
		% [outcome, point, a.get_class(), b.get_class()])


# ---------------------------------------------------------------- static reads

func _form_name(f: int) -> String:
	return ["BEAM", "BARRIER", "FIELD", "PROJECTILE", "IMPACT", "AURA"][f]


## Which of the 21 unordered form buckets any rule at all was authored for. This
## is the reactor's stage-2 sparse gate: a bucket with no rows is a hash miss and
## the pair dies before ANY geometry runs.
func _bucket_census() -> void:
	print("\n===== FORM-PAIR BUCKET CENSUS (what the reactor's stage-2 gate holds) =====")
	var buckets: Dictionary = {}
	for r: Dictionary in ReactionTable.rules():
		var k: int = ReactionTable.bucket_key(int(r["form_a"]), int(r["form_b"]))
		buckets[k] = int(buckets.get(k, 0)) + 1
	for a: int in range(6):
		for b: int in range(a, 6):
			var k: int = ReactionTable.bucket_key(a, b)
			var n: int = int(buckets.get(k, 0))
			if n > 0:
				print("   %-12s x %-12s : %d rule(s)" % [_form_name(a), _form_name(b), n])
	print("   -- buckets with NO rule (reactor never even measures these) --")
	for a: int in range(6):
		for b: int in range(a, 6):
			if not buckets.has(ReactionTable.bucket_key(a, b)):
				print("   %-12s x %-12s : NONE" % [_form_name(a), _form_name(b)])


## The table asked directly, with the exact arguments SpellReactor would pass for
## two hero bolts.
func _table_probe() -> void:
	print("\n===== ReactionTable.match_rule FOR TWO BOLTS =====")
	var E := Elements.Element
	var cases: Array = [
		["fire vs ice  (opposed)", E.FIRE, E.ICE],
		["fire vs fire (same)   ", E.FIRE, E.FIRE],
		["fire vs shadow (neutral)", E.FIRE, E.SHADOW],
	]
	for c: Array in cases:
		var rule: Dictionary = ReactionTable.match_rule(
			ReactionTable.Form.PROJECTILE, int(c[1]),
			ReactionTable.Form.PROJECTILE, int(c[2]),
			"different", SpellTier.Tier.QUICK, SpellTier.Tier.QUICK)
		print("   PROJECTILE x PROJECTILE, %s, owners different, both QUICK -> %s"
			% [c[0], "{} (NO RULE)" if rule.is_empty() else String(rule["outcome"])])
	# ...and the BEAM equivalent, which does have rows, for contrast.
	var beam: Dictionary = ReactionTable.match_rule(
		ReactionTable.Form.BEAM, Elements.Element.FIRE,
		ReactionTable.Form.BEAM, Elements.Element.SHADOW,
		"different", SpellTier.Tier.QUICK, SpellTier.Tier.QUICK)
	print("   BEAM       x BEAM      , fire vs shadow, owners different, both QUICK -> %s"
		% ["{} (NO RULE)" if beam.is_empty() else String(beam["outcome"])])


# ------------------------------------------------------------------- live cases

func _mk_bolt(at: Vector2, dir: Vector2, element: int, caster: Node, tier: int) -> Node:
	var scene: PackedScene = load("res://scenes/combat/Spell.tscn") as PackedScene
	var b: Node = scene.instantiate()
	root.add_child(b)
	b.set_physics_process(false)   # we step it by hand
	(b as Node2D).global_position = at
	b.call(&"launch", dir)
	b.set(&"element_id", element)
	b.set(&"caster", caster)
	b.set(&"spell_tier", tier)
	return b


## A — THE ASK. Two bolts fired at each other, stepped together frame by frame
## exactly as Spell._physics_process would move them, with the reactor resolved
## every step.
func _case_a_bolt_vs_bolt(reactor: Node) -> void:
	print("\n===== CASE A — BOLT vs BOLT (the ask) =====")
	var left: Node = Node2D.new(); left.name = "CasterL"; root.add_child(left)
	var right: Node = Node2D.new(); right.name = "CasterR"; root.add_child(right)
	var a: Node = _mk_bolt(Vector2(-60, 0), Vector2.RIGHT, Elements.Element.FIRE,
		left, SpellTier.Tier.QUICK)
	var b: Node = _mk_bolt(Vector2(60, 0), Vector2.LEFT, Elements.Element.SHADOW,
		right, SpellTier.Tier.QUICK)
	# Register EXACTLY as Spell.gd:342 does on its first physics frame.
	reactor.call(&"register", a, ReactionTable.Form.PROJECTILE, a.get(&"element_id"))
	reactor.call(&"register", b, ReactionTable.Form.PROJECTILE, b.get(&"element_id"))
	print("   live reactants: %d" % int(reactor.call(&"live_count")))
	print("   a.reaction_form=%s active=%s element=%d weight=%d owner=%s"
		% [_form_name(int(a.call(&"reaction_form"))), a.call(&"reaction_active"),
			int(a.call(&"reaction_element")), int(a.call(&"reaction_weight")),
			str(a.call(&"reaction_owner"))])
	print("   a.reaction_shape=%s" % [a.call(&"reaction_shape")])
	var total: int = 0
	var closest: float = 1e9
	for step: int in 40:
		var dt: float = 1.0 / 60.0
		(a as Node2D).global_position += Vector2.RIGHT * 460.0 * dt
		(b as Node2D).global_position += Vector2.LEFT * 460.0 * dt
		var d: float = (a as Node2D).global_position.distance_to((b as Node2D).global_position)
		closest = minf(closest, d)
		var sa: Dictionary = a.call(&"reaction_shape")
		var sb: Dictionary = b.call(&"reaction_shape")
		var touching: bool = SpellGeometry.overlaps(sa, sb)
		total += int(reactor.call(&"resolve_now"))
		if touching:
			print("   step %d: separation %.1f px  SHAPES OVERLAP  reactions so far=%d"
				% [step, d, total])
	print("   closest approach: %.1f px (sum of radii = 12.0)" % closest)
	print("   TOTAL REACTIONS: %d" % total)
	_log.append("A  bolt vs bolt        : %d reaction(s)  <-- the ask" % total)
	reactor.call(&"unregister", a)
	reactor.call(&"unregister", b)
	a.queue_free(); b.queue_free()
	left.queue_free(); right.queue_free()


## B — POSITIVE CONTROL on the SAME bolt object. If this fires, the bolt is a
## fully working participant and case A's silence is a missing TABLE ROW.
func _case_b_bolt_vs_ice_wall(reactor: Node) -> void:
	print("\n===== CASE B — BOLT vs ICE WALL (positive control, same bolt) =====")
	var caster: Node = Node2D.new(); caster.name = "CasterB"; root.add_child(caster)
	var wall_caster: Node = Node2D.new(); wall_caster.name = "CasterW"; root.add_child(wall_caster)
	# ⚠ NAMED VIA RUNTIME `load()`, NEVER `IceWall.new()`. Under `--script` the
	# autoloads are not registered as global identifiers at COMPILE time, so a
	# static reference to any script that says `Sfx.play(...)` fails to compile and
	# the class name resolves to an unusable GDScript. Loading it here — inside
	# `_process`, after the autoloads exist — compiles it cleanly.
	var wall: Node = (load("res://scripts/combat/IceWall.gd") as GDScript).new()
	root.add_child(wall)
	wall.set_process(false)
	wall.set_physics_process(false)
	# Only the fields the reaction contract reads. raise_wall() additionally does
	# particles / sigils / SFX / a floor raycast, none of which this measures.
	wall.set(&"_floor_base", Vector2(0, 0))
	wall.set(&"_elapsed", 0.1)          # standing (reaction_active needs >= 0)
	wall.set(&"_shattered", false)
	wall.set(&"element_id", Elements.Element.ICE)
	wall.set(&"caster_node", wall_caster)
	wall.set(&"spell_tier", SpellTier.DEFAULT_WEIGHT)
	print("   wall.reaction_active=%s shape=%s weight=%d"
		% [wall.call(&"reaction_active"), wall.call(&"reaction_shape"),
			int(wall.call(&"reaction_weight"))])
	var bolt: Node = _mk_bolt(Vector2(-60, -60), Vector2.RIGHT, Elements.Element.FIRE,
		caster, SpellTier.Tier.QUICK)
	reactor.call(&"register", bolt, ReactionTable.Form.PROJECTILE, bolt.get(&"element_id"))
	reactor.call(&"register", wall, ReactionTable.Form.BARRIER, Elements.Element.ICE)
	var total: int = 0
	for step: int in 40:
		(bolt as Node2D).global_position += Vector2.RIGHT * 460.0 * (1.0 / 60.0)
		total += int(reactor.call(&"resolve_now"))
		if total > 0:
			print("   fired at step %d, bolt at %s" % [step, (bolt as Node2D).global_position])
			break
	print("   TOTAL REACTIONS: %d" % total)
	_log.append("B  bolt vs ice wall    : %d reaction(s)  <-- control (proves the bolt works)" % total)
	reactor.call(&"unregister", bolt)
	reactor.call(&"unregister", wall)
	if is_instance_valid(bolt):
		bolt.queue_free()
	if is_instance_valid(wall):
		wall.queue_free()
	caster.queue_free(); wall_caster.queue_free()


## C — POSITIVE CONTROL on two heavier participants: two live beams crossing.
func _case_c_beam_vs_beam(reactor: Node) -> void:
	print("\n===== CASE C — BEAM vs BEAM (positive control, two heavy spells) =====")
	var c1: Node = Node2D.new(); c1.name = "CasterB1"; root.add_child(c1)
	var c2: Node = Node2D.new(); c2.name = "CasterB2"; root.add_child(c2)
	var beams: Array = []
	var setup: Array = [
		[Vector2(-200, 0), Vector2.RIGHT, Elements.Element.FIRE, c1],
		[Vector2(0, -200), Vector2.DOWN, Elements.Element.SHADOW, c2],
	]
	var beam_script: GDScript = load("res://scripts/combat/BeamSpell.gd") as GDScript
	for s: Array in setup:
		var bm: Node = beam_script.new()
		root.add_child(bm)
		bm.set_process(false)
		bm.set_physics_process(false)
		bm.set(&"_origin", s[0])
		bm.set(&"_dir", s[1])
		bm.set(&"_fired", true)     # past the charge telegraph
		bm.set(&"_elapsed", 0.4)
		bm.set(&"_frozen", false)
		bm.set(&"element_id", int(s[2]))
		bm.set(&"caster_node", s[3])
		beams.append(bm)
		reactor.call(&"register", bm, ReactionTable.Form.BEAM, int(s[2]))
	for bm: Node in beams:
		# BeamSpell implements NO reaction_weight(), so the reactor resolves it to
		# SpellTier.DEFAULT_WEIGHT — printed here so the "equal weight" that
		# mutual_annihilation requires is visible rather than assumed.
		print("   beam active=%s shape=%s has_weight_method=%s owner=%s"
			% [bm.call(&"reaction_active"), bm.call(&"reaction_shape"),
				bm.has_method(&"reaction_weight"), str(bm.call(&"reaction_owner"))])
	var sa: Dictionary = (beams[0] as Node).call(&"reaction_shape")
	var sb: Dictionary = (beams[1] as Node).call(&"reaction_shape")
	print("   shapes overlap: %s at %s"
		% [SpellGeometry.overlaps(sa, sb), SpellGeometry.meeting_point(sa, sb)])
	var total: int = int(reactor.call(&"resolve_now"))
	print("   TOTAL REACTIONS: %d" % total)
	_log.append("C  beam vs beam        : %d reaction(s)  <-- control (heavy participants)" % total)
	for bm: Node in beams:
		if is_instance_valid(bm):
			reactor.call(&"unregister", bm)
	c1.queue_free(); c2.queue_free()


## D — ASK (B), THE MELEE SWAT. `Hero._on_melee_hit_frame` already sweeps
## "enemy_projectile" + "player_spell" inside the melee cone and calls
## `proj.consume()` on whatever it finds — gated on `has_method("consume")`.
## This asks every projectile-shaped script in the game whether it answers that
## call, so "the punch-swat is already built" and "the punch-swat can reach the
## basic bolt" are separated by measurement rather than by reading.
func _case_d_melee_swat_contract() -> void:
	print("\n===== CASE D — WHO ANSWERS Hero's melee `consume()` SWAT? =====")
	var paths: Array[String] = [
		"res://scripts/combat/EnemyProjectile.gd",
		"res://scripts/combat/BoulderHurl.gd",
		"res://scripts/combat/RiftDagger.gd",
		"res://scripts/combat/ShadowCrawler.gd",
		"res://scripts/combat/HorizonArc.gd",
		"res://scripts/combat/DrainTether.gd",
	]
	var missing: Array[String] = []
	# The basic bolt, via its real scene, exactly as Hero spawns it.
	var bolt: Node = (load("res://scenes/combat/Spell.tscn") as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.set_physics_process(false)
	print("   %-22s groups=%s  consume()=%s  fizzle()=%s  reaction_consume()=%s"
		% ["Spell.gd (basic bolt)", str(bolt.get_groups()),
			bolt.has_method(&"consume"), bolt.has_method(&"fizzle"),
			bolt.has_method(&"reaction_consume")])
	if not bolt.has_method(&"consume"):
		missing.append("Spell.gd")
	bolt.queue_free()
	for p: String in paths:
		var sc: GDScript = load(p) as GDScript
		var n: Node = sc.new()
		print("   %-22s consume()=%s" % [p.get_file(), n.has_method(&"consume")])
		if not n.has_method(&"consume"):
			missing.append(p.get_file())
		n.free()
	_log.append("D  melee `consume()` swat: scripts WITHOUT consume() = %s" % str(missing))


## E — THE TICK-RATE TRAP. Even with a PROJECTILE x PROJECTILE row authored, can
## the reactor SEE two bolts cross? The reactor resolves at 30 Hz; two head-on
## bolts close at 2 x SPEED = 920 px/s = 30.7 px per tick, while their overlap
## window is only radius+radius = 12 px wide. Swept over sub-tick phase offsets so
## the answer is a hit RATE, not one lucky alignment.
func _case_e_tick_window() -> void:
	print("\n===== CASE E — CAN A 30 Hz TICK EVEN SEE TWO BOLTS CROSS? =====")
	var speed: float = 460.0
	var r: float = 6.0
	for hz: float in [60.0, 30.0]:
		var dt: float = 1.0 / hz
		var caught: int = 0
		var phases: int = 200
		for i: int in phases:
			# Phase offset: where in the tick the bolts happen to be when they meet.
			var a: Vector2 = Vector2(-300.0 - float(i) / float(phases) * 2.0 * speed * dt, 0.0)
			var b: Vector2 = Vector2(300.0, 0.0)
			var seen: bool = false
			for _t: int in 200:
				a += Vector2.RIGHT * speed * dt
				b += Vector2.LEFT * speed * dt
				if SpellGeometry.overlaps(SpellGeometry.circle(a, r),
						SpellGeometry.circle(b, r)):
					seen = true
					break
				if a.x > b.x + 100.0:
					break
			if seen:
				caught += 1
		print("   %.0f Hz resolve, point shapes (r=%.0f): crossing detected in %d / %d phases (%.0f%%)"
			% [hz, r, caught, phases, 100.0 * float(caught) / float(phases)])
	# ...and the fix: a SWEPT capsule from last position to current, which is the
	# same anti-tunnelling idea Spell._resolve_segment already uses for physics.
	for hz: float in [30.0]:
		var dt: float = 1.0 / hz
		var caught: int = 0
		var phases: int = 200
		for i: int in phases:
			var a: Vector2 = Vector2(-300.0 - float(i) / float(phases) * 2.0 * speed * dt, 0.0)
			var b: Vector2 = Vector2(300.0, 0.0)
			var seen: bool = false
			for _t: int in 200:
				var pa: Vector2 = a
				var pb: Vector2 = b
				a += Vector2.RIGHT * speed * dt
				b += Vector2.LEFT * speed * dt
				if SpellGeometry.overlaps(SpellGeometry.capsule(pa, a, r * 2.0),
						SpellGeometry.capsule(pb, b, r * 2.0)):
					seen = true
					break
				if a.x > b.x + 100.0:
					break
			if seen:
				caught += 1
		print("   %.0f Hz resolve, SWEPT capsule prev->now: detected in %d / %d phases (%.0f%%)"
			% [hz, caught, phases, 100.0 * float(caught) / float(phases)])
