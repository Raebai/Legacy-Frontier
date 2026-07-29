# PROTECTIVE SPELLS + the reaction OUTCOMES that were matching and doing nothing.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice9_test_wards.gd
#
# TWO THINGS ARE PROVED HERE, and they are the same system seen from two ends.
#
# 1. THE AEGIS WARD. A protective spell that is authored entirely as DATA — four
#    rows in ReactionTable, no predicate and no branch in SpellReactor. The tests
#    that matter are the ladder (a full ward eats everything, a half-spent ward is
#    breached by an ult, a nearly-dead one by a heavy) and the two REACH tests:
#    something just outside the drawn gate is untouched, and a ward cannot be
#    planted in or over terrain.
#
# 2. THE DORMANT OUTCOMES. ReactionOutcomes implemented `hollow_purple` and the
#    weight contests; `steam_cloud`, `supercharge`, `field_merge`,
#    `beam_resonance`, `shatter_ice_barrier`, `shrapnel_cone`, `void_charged`,
#    `ground_out` and `carve` were authored rows with no arm — so they MATCHED,
#    were MEMOIZED as handled, and then did nothing while the two spells passed
#    through each other. That is worse than having no row at all, and it is the
#    class of failure no existing suite could see, because slice6_test_reactions
#    proves the TABLE matches and slice6_test_reactor proves the REGISTRY fires.
#    Nothing proved the payoff existed.
#
# ⚠ WHY EVERY SPECTACLE IS LOADED BY PATH AND NEVER NAMED. A `--script` tool is
# COMPILED BEFORE THE AUTOLOADS EXIST. Naming `AegisWard` as a global class here
# makes the parser compile it at that moment, and it calls `Sfx` — so the whole
# suite would die with "Identifier not found: Sfx" and every `.new()` after it
# would fail. Same trap, same fix, as slice6_test_hollow_purple.
extends SceneTree

const AEGIS_WARD := "res://scripts/combat/AegisWard.gd"
const STEAM_CLOUD := "res://scripts/combat/SteamCloud.gd"

## Long enough that a capsule stub reads as a real beam rather than a graze.
const BEAM_LEN: float = 900.0

var _ran: bool = false
var _failed: int = 0
var _caster_a: Node = null
var _caster_b: Node = null


# ---------------------------------------------------------------------- stubs

## A live effect, duck-typed exactly like a real spectacle — and, like every real
## spectacle, PARKED AT THE ORIGIN with its geometry somewhere else entirely.
## Every counter it keeps is a question one of the outcomes has to answer.
class ReactantStub extends Node2D:
	var shape: Dictionary = {}
	var active: bool = true
	var form: int = 0
	var element: int = 0
	var weight: int = SpellTier.Tier.HEAVY
	var owner_node: Node = null
	var consumed: int = 0
	var shattered: int = 0
	var absorbed: int = 0
	var grown: float = -1.0
	var damaged: int = 0

	func reaction_shape() -> Dictionary:
		return shape

	func reaction_active() -> bool:
		return active

	func reaction_element() -> int:
		return element

	func reaction_form() -> int:
		return form

	func reaction_owner() -> Node:
		return owner_node

	func reaction_weight() -> int:
		return weight

	func reaction_freeze() -> void:
		pass

	# Deliberately does NOT free itself, so the suite can count consumptions.
	func reaction_consume() -> void:
		consumed += 1

	func shatter() -> void:
		shattered += 1

	func reaction_absorb(_at: Vector2) -> void:
		absorbed += 1

	func reaction_grow(radius: float) -> void:
		grown = radius

	func take_damage(amount: int) -> void:
		damaged += amount


## A barrier that PREDATES the reaction contract: it publishes `shatter()` and no
## `reaction_consume` at all — which is exactly IceWall today, whose shatter() has
## been documented as "the Phase 3 interaction hook" since long before the reactor
## existed. It is a separate class rather than a flag on ReactantStub because
## GDScript refuses to let a script override `has_method`, and faking the absence
## of a method is the only other way to test the fallback.
class LegacyBarrierStub extends Node2D:
	var shape: Dictionary = {}
	var form: int = ReactionTable.Form.BARRIER
	var element: int = 0
	var weight: int = SpellTier.Tier.HEAVY
	var shattered: int = 0

	func reaction_shape() -> Dictionary:
		return shape

	func reaction_active() -> bool:
		return true

	func reaction_element() -> int:
		return element

	func reaction_form() -> int:
		return form

	func reaction_weight() -> int:
		return weight

	func shatter() -> void:
		shattered += 1


## Something a reaction can hurt. In group "enemy" so the selectors find it, with
## the three duck-typed hooks every spectacle in the game already calls.
class Dummy extends Node2D:
	var hp_lost: int = 0
	var status: int = -1
	var knock: Vector2 = Vector2.ZERO

	func _init() -> void:
		add_to_group(&"enemy")

	func take_damage(amount: int) -> void:
		hp_lost += amount

	func apply_status(element: int) -> void:
		status = element

	func apply_knockback(v: Vector2) -> void:
		knock += v


## An enemy bolt the ward's screen should eat. `consume()` is the exact duck-typed
## idiom IceWall.shatter already uses on the same group.
class Bolt extends Node2D:
	var eaten: int = 0

	func _init() -> void:
		add_to_group(&"enemy_projectile")

	func consume() -> void:
		eaten += 1


# ----------------------------------------------------------------- the runner

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("FAIL: SpellReactor autoload is missing")
		quit(1)
		return
	# Drive the sweep by hand instead of racing the 30 Hz timer, and keep the
	# spectacle seam OFF so nothing stages a 2.6 s cloud inside a test.
	reactor.set_process(false)
	reactor.set(&"spawn_effects", false)
	_caster_a = _named_node("CasterA")
	_caster_b = _named_node("CasterB")

	_test_ward_geometry()
	_test_ward_reach_negative()
	_test_ward_ladder_is_data()
	_test_steam_geometry()
	_test_ward_rows()
	_test_existing_barriers_untouched()
	_test_ward_through_the_reactor(reactor)
	_test_origin_parked_ward(reactor)
	_test_dormant_outcomes(reactor)
	await _test_real_ward_and_terrain(reactor)

	if _failed > 0:
		printerr("Ward + outcome tests: %d FAILED" % _failed)
		quit(1)
	else:
		print("Ward + outcome tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_failed += 1


func _named_node(n: String) -> Node:
	var c := Node2D.new()
	c.name = n
	root.add_child(c)
	return c


static func _const_of(path: String, name: StringName) -> Variant:
	return (load(path) as GDScript).get_script_constant_map().get(name)


static func _static_call(path: String, method: StringName, args: Array) -> Variant:
	return (load(path) as GDScript).callv(method, args)


# ------------------------------------------------------------ ward geometry

func _test_ward_geometry() -> void:
	var offset: float = float(_const_of(AEGIS_WARD, &"OFFSET"))
	var at: Vector2 = _static_call(AEGIS_WARD, &"plant_point",
		[Vector2(100.0, 50.0), Vector2(1.0, 0.0), offset])
	_expect(at.is_equal_approx(Vector2(100.0 + offset, 50.0)),
		"the gate plants OFFSET px along the aim, and nowhere else")
	# NO AUTO-AIM: a dead aim must resolve to a fixed direction, never to whatever
	# is nearest. There is no target search anywhere in the ward.
	var dead: Vector2 = _static_call(AEGIS_WARD, &"plant_point",
		[Vector2.ZERO, Vector2.ZERO, offset])
	_expect(dead.is_equal_approx(Vector2(offset, 0.0)),
		"a zero aim falls back to RIGHT rather than seeking anything")


## ⚠ THE NEGATIVE CASE, and the reason this suite exists in the shape it does.
## The maker's rule is "the spells shouldn't be able to get out the radius", and
## three drawn-vs-damaged mismatches have already been found in this codebase. So
## the assertions that matter are the ones about what is NOT affected.
func _test_ward_reach_negative() -> void:
	var h: float = float(_const_of(AEGIS_WARD, &"HEIGHT"))
	var thick: float = float(_const_of(AEGIS_WARD, &"THICKNESS"))
	var pad: float = float(_const_of(AEGIS_WARD, &"SCREEN_PAD"))
	var base := Vector2(0.0, 0.0)
	# Positive control first — a test that only proves misses proves nothing.
	_expect(bool(_static_call(AEGIS_WARD, &"screens_point",
		[base, 1.0, base - Vector2(0.0, h * 0.5)])),
		"a bolt in the middle of the risen gate IS screened")
	# Just outside the drawn thickness (plus its own published pad) — untouched.
	_expect(not bool(_static_call(AEGIS_WARD, &"screens_point",
		[base, 1.0, base + Vector2(thick * 0.5 + pad + 1.0, -h * 0.5)])),
		"a bolt one pixel outside the drawn gate is NOT screened")
	# Above the top of the pane — untouched. A gate that ate things over its own
	# head would be the reach bug in its most literal form.
	_expect(not bool(_static_call(AEGIS_WARD, &"screens_point",
		[base, 1.0, base - Vector2(0.0, h + pad + 1.0)])),
		"a bolt above the top of the gate is NOT screened")
	# Below the foot — untouched.
	_expect(not bool(_static_call(AEGIS_WARD, &"screens_point",
		[base, 1.0, base + Vector2(0.0, pad + 1.0)])),
		"a bolt below the gate's foot is NOT screened")
	# THE RISE. The screen may never reach higher than the gate is DRAWN, so a
	# quarter-risen ward cannot eat something at four-fifths of its final height.
	_expect(not bool(_static_call(AEGIS_WARD, &"screens_point",
		[base, 0.25, base - Vector2(0.0, h * 0.8)])),
		"a quarter-risen gate does not screen at four-fifths height")
	_expect(bool(_static_call(AEGIS_WARD, &"screens_point",
		[base, 0.25, base - Vector2(0.0, h * 0.1)])),
		"...but it does screen inside the part it HAS grown")
	# The collapse ring is drawn to SHATTER_RADIUS and damages to SHATTER_RADIUS.
	var sr: float = float(_const_of(AEGIS_WARD, &"SHATTER_RADIUS"))
	var centre: Vector2 = base - Vector2(0.0, h * 0.5)
	_expect(bool(_static_call(AEGIS_WARD, &"shatter_contains",
		[base, centre + Vector2(sr - 1.0, 0.0)])), "the collapse reaches its drawn ring")
	_expect(not bool(_static_call(AEGIS_WARD, &"shatter_contains",
		[base, centre + Vector2(sr + 2.0, 0.0)])),
		"...and not one pixel past it")


## The degradation ladder is a TABLE, not behaviour — so it is asserted as one.
func _test_ward_ladder_is_data() -> void:
	var T := SpellTier.Tier
	_expect(int(_static_call(AEGIS_WARD, &"weight_for_charges", [3])) == T.ULT,
		"a full ward fights on the ULT shelf")
	_expect(int(_static_call(AEGIS_WARD, &"weight_for_charges", [2])) == T.HEAVY,
		"one plate spent and it drops to HEAVY")
	_expect(int(_static_call(AEGIS_WARD, &"weight_for_charges", [1])) == T.QUICK,
		"one plate left and it is only QUICK")
	_expect(int(_static_call(AEGIS_WARD, &"weight_for_charges", [0])) == T.QUICK,
		"a spent ward never reports something heavier than QUICK")


func _test_steam_geometry() -> void:
	var end_frac: float = float(_const_of(STEAM_CLOUD, &"RADIUS_END_FRAC"))
	var start_frac: float = float(_const_of(STEAM_CLOUD, &"RADIUS_START_FRAC"))
	var r0: float = float(_static_call(STEAM_CLOUD, &"radius_at", [100.0, 0.0]))
	var r1: float = float(_static_call(STEAM_CLOUD, &"radius_at", [100.0, 1.0]))
	_expect(is_equal_approx(r0, 100.0 * start_frac), "the bank opens tight")
	_expect(is_equal_approx(r1, 100.0 * end_frac), "...and billows past the field's edge")
	_expect(r1 > r0, "the cloud grows rather than shrinking")
	# Concealment is measured against the DRIFTED centre, and — the assertion that
	# matters — stops exactly at the drawn radius.
	var at := Vector2(200.0, -40.0)
	var t: float = 0.5
	var centre: Vector2 = at + Vector2(0.0, float(_static_call(STEAM_CLOUD, &"rise_at", [t])))
	var rr: float = float(_static_call(STEAM_CLOUD, &"radius_at", [160.0, t]))
	_expect(bool(_static_call(STEAM_CLOUD, &"conceals", [at, 160.0, t, centre])),
		"the middle of the bank conceals")
	_expect(not bool(_static_call(STEAM_CLOUD, &"conceals",
		[at, 160.0, t, centre + Vector2(rr + 2.0, 0.0)])),
		"a point just outside the drawn bank is NOT concealed")
	_expect(not bool(_static_call(STEAM_CLOUD, &"conceals", [at, 160.0, 1.4, centre])),
		"a cloud past its own life conceals nothing")


# ------------------------------------------------------------- the ward rows

## The four authored rows, read straight out of the table. This is the whole
## protective-spell design: three outcomes, chosen by weight and element, with no
## code anywhere deciding any of it.
func _test_ward_rows() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	# FULL WARD (ULT) vs a HEAVY beam — eaten, and the ward stands.
	var r: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BARRIER, E.HOLY,
		"different", T.HEAVY, T.ULT)
	_expect(String(r.get("outcome", "")) == "ward_absorb",
		"a full ward EATS a heavy spell (got '%s')" % String(r.get("outcome", "")))
	_expect(ReactionTable.consumes_caller(r, 0), "...the spell is spent")
	_expect(not ReactionTable.consumes_caller(r, 1), "...and the ward is NOT")
	# HALF-SPENT WARD (HEAVY) vs an ULT — breached, and the ult carries on.
	var b: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BARRIER, E.HOLY,
		"different", T.ULT, T.HEAVY)
	_expect(String(b.get("outcome", "")) == "breach",
		"an ULT breaches a half-spent ward (got '%s')" % String(b.get("outcome", "")))
	_expect(ReactionTable.consumes_caller(b, 1), "...the ward is destroyed")
	_expect(not ReactionTable.consumes_caller(b, 0), "...and the ult keeps going")
	# NEARLY DEAD (QUICK) vs a HEAVY — breached too. The ladder has three rungs.
	var b2: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BARRIER, E.HOLY,
		"different", T.HEAVY, T.QUICK)
	_expect(String(b2.get("outcome", "")) == "breach",
		"a HEAVY breaches a one-plate ward")
	# THE ELEMENTAL ANSWER outranks the weight story: shadow pops a FULL ward.
	var s: Dictionary = ReactionTable.match_rule(F.BEAM, E.SHADOW, F.BARRIER, E.HOLY,
		"different", T.QUICK, T.ULT)
	_expect(String(s.get("outcome", "")) == "shatter_ward",
		"a SHADOW jab pops a full ward — bringing the right element IS the answer")
	_expect(ReactionTable.consumes_caller(s, 1), "...and the ward is spent by it")
	# A thrown thing answers a ward the same way a beam does.
	var p: Dictionary = ReactionTable.match_rule(F.PROJECTILE, E.EARTH, F.BARRIER,
		E.HOLY, "different", T.QUICK, T.ULT)
	_expect(String(p.get("outcome", "")) == "ward_absorb",
		"a projectile is eaten by a full ward too")
	# ⚠ THE SWAPPED-SIDE TRAP. The same pair, seen with the ward FIRST. The outcome
	# must be identical and consumes_caller must still name the SPELL — reading the
	# raw consumes_a here would eat the ward instead.
	var sw: Dictionary = ReactionTable.match_rule(F.BARRIER, E.HOLY, F.BEAM, E.FIRE,
		"different", T.ULT, T.HEAVY)
	_expect(String(sw.get("outcome", "")) == "ward_absorb",
		"the ward row matches with its sides reversed")
	_expect(ReactionTable.consumes_caller(sw, 1), "...and still spends the SPELL")
	_expect(not ReactionTable.consumes_caller(sw, 0), "...never the ward")


## ⚠ THE REGRESSION GUARD FOR ADDING ROWS TO A LIVE MATRIX. The ward is identified
## by carrying HOLY, which no existing barrier does — so none of the four new rows
## may change a single existing pairing. If a future ward is authored on EARTH or
## ICE, this is the test that will go red.
func _test_existing_barriers_untouched() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	var ice: Dictionary = ReactionTable.match_rule(F.BEAM, E.ARCANE, F.BARRIER, E.ICE,
		"different", T.QUICK, T.HEAVY)
	_expect(String(ice.get("outcome", "")) == "barrier_blocks",
		"an ice wall still simply BLOCKS an under-weight beam")
	var fire: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BARRIER, E.ICE,
		"different", T.QUICK, T.ULT)
	_expect(String(fire.get("outcome", "")) == "shatter_ice_barrier",
		"fire still shatters ice")
	var earth: Dictionary = ReactionTable.match_rule(F.BEAM, E.ARCANE, F.BARRIER,
		E.EARTH, "different", T.HEAVY, T.HEAVY)
	_expect(String(earth.get("outcome", "")) == "carve",
		"an evenly-matched beam still carves stone")
	var gnd: Dictionary = ReactionTable.match_rule(F.BEAM, E.LIGHTNING, F.BARRIER,
		E.EARTH, "different", T.HEAVY, T.HEAVY)
	_expect(String(gnd.get("outcome", "")) == "ground_out",
		"earth still grounds out lightning")
	# And the headline rows are still the headline rows.
	var hp: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.ICE,
		"same", T.HEAVY, T.HEAVY)
	_expect(String(hp.get("outcome", "")) == "hollow_purple",
		"the hollow_purple self-combo still outranks everything")
	var hp2: Dictionary = ReactionTable.match_rule(F.BEAM, E.SHADOW, F.BEAM, E.HOLY,
		"different", T.ULT, T.QUICK)
	_expect(String(hp2.get("outcome", "")) == "hollow_purple",
		"the cross-caster crossing is still weight-blind")


# ------------------------------------------------- the ward through the reactor

## End to end, with the REAL reactor and the REAL ReactionOutcomes: the ward eats,
## degrades, and is eventually broken.
func _test_ward_through_the_reactor(reactor: Node) -> void:
	var E := Elements.Element
	var T := SpellTier.Tier
	# A full ward standing at x = 0, and a beam fired straight into it.
	var ward: ReactantStub = _barrier(reactor, Vector2(0.0, 0.0), E.HOLY, T.ULT)
	var beam: ReactantStub = _beam(reactor, Vector2(-BEAM_LEN, -60.0), Vector2(60.0, -60.0),
		E.FIRE, T.HEAVY, _caster_b)
	_expect(int(reactor.call(&"resolve_now")) == 1, "the beam meets the ward")
	_expect(beam.consumed == 1, "the beam is EATEN")
	_expect(ward.consumed == 0, "the ward is NOT spent by absorbing")
	_expect(ward.absorbed == 1, "...it is told it paid, exactly once")
	_drop(reactor, [beam])

	# Now the same ward at HEAVY (one plate gone) against an ULT. The reactor polls
	# reaction_weight() every tick, which is the only reason changing this field
	# mid-life changes the outcome at all.
	ward.weight = T.HEAVY
	var ult: ReactantStub = _beam(reactor, Vector2(-BEAM_LEN, -60.0), Vector2(60.0, -60.0),
		E.FIRE, T.ULT, _caster_b)
	_expect(int(reactor.call(&"resolve_now")) == 1, "the ult meets the weakened ward")
	_expect(ward.consumed == 1, "the ward is BREACHED once it is out-weighed")
	_expect(ult.consumed == 0, "...and the ult carries on")
	_drop(reactor, [ward, ult])

	# The elemental answer, end to end: a QUICK shadow jab against a FULL ward.
	var ward2: ReactantStub = _barrier(reactor, Vector2(0.0, 0.0), E.HOLY, T.ULT)
	var jab: ReactantStub = _beam(reactor, Vector2(-BEAM_LEN, -60.0), Vector2(60.0, -60.0),
		E.SHADOW, T.QUICK, _caster_b)
	_expect(int(reactor.call(&"resolve_now")) == 1, "the shadow jab reaches the ward")
	_expect(ward2.consumed == 1, "a full ward is POPPED by its opposed school")
	_expect(ward2.absorbed == 0, "...and never gets to absorb it")
	_drop(reactor, [ward2, jab])


## ⚠ THE INVARIANT THE WHOLE DETECTOR IS BUILT AROUND, re-asserted with a ward in
## the pair. Both nodes sit at (0, 0) — as every real spectacle does — with their
## effects 4000 px apart. A detector reading transforms would report every ward in
## the arena as being hit by everything.
func _test_origin_parked_ward(reactor: Node) -> void:
	var E := Elements.Element
	var T := SpellTier.Tier
	var ward: ReactantStub = _barrier(reactor, Vector2(2200.0, 0.0), E.HOLY, T.ULT)
	var beam: ReactantStub = _beam(reactor, Vector2(-2400.0, 0.0), Vector2(-1800.0, 0.0),
		E.FIRE, T.HEAVY, _caster_b)
	_expect(ward.global_position == Vector2.ZERO and beam.global_position == Vector2.ZERO,
		"both stubs really are parked at the origin")
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"a ward across the arena is NOT hit by a beam parked at the same origin")
	_expect(ward.absorbed == 0 and beam.consumed == 0, "...and nothing is spent")
	_drop(reactor, [ward, beam])


# ------------------------------------------------------- the dormant outcomes

## Each of these rows matched, memoized and did nothing before this suite existed.
## The assertion is always the same shape: the row's authored consumption happened,
## AND something observable came out the other side.
func _test_dormant_outcomes(reactor: Node) -> void:
	var E := Elements.Element
	var T := SpellTier.Tier

	# ── steam_cloud — fire boils a frost field off. Vision, not damage.
	var field: ReactantStub = _field(reactor, Vector2(0.0, 0.0), 150.0, E.ICE, T.HEAVY)
	var fire: ReactantStub = _beam(reactor, Vector2(-BEAM_LEN, 0.0), Vector2(60.0, 0.0),
		E.FIRE, T.HEAVY, _caster_b)
	_expect(int(reactor.call(&"resolve_now")) == 1, "fire reaches the frost field")
	_expect(field.consumed == 1, "the field is boiled away")
	_expect(fire.consumed == 0, "...and the beam is not spent doing it")
	_drop(reactor, [field, fire])

	# ── supercharge — lightning through frost. Nothing is spent; the FIELD's own
	# shape is the damaged area, and something just outside it takes nothing.
	var f2: ReactantStub = _field(reactor, Vector2(0.0, 0.0), 150.0, E.ICE, T.HEAVY)
	var bolt: ReactantStub = _beam(reactor, Vector2(-BEAM_LEN, 0.0), Vector2(60.0, 0.0),
		E.LIGHTNING, T.HEAVY, _caster_b)
	var inside: Dummy = _dummy(Vector2(20.0, 0.0))
	var outside: Dummy = _dummy(Vector2(320.0, 0.0))
	_expect(int(reactor.call(&"resolve_now")) == 1, "lightning conducts through the field")
	_expect(f2.consumed == 0 and bolt.consumed == 0, "supercharge spends nothing")
	_expect(inside.hp_lost > 0, "a body standing in the charged field is hurt")
	_expect(inside.status == E.LIGHTNING, "...and shocked, not chilled")
	_expect(outside.hp_lost == 0,
		"a body OUTSIDE the drawn field takes nothing — the reach contract")
	_drop(reactor, [f2, bolt])
	_free_all([inside, outside])

	# ── field_merge — two same-element fields become one bigger one.
	var f3: ReactantStub = _field(reactor, Vector2(-40.0, 0.0), 120.0, E.ICE, T.HEAVY)
	var f4: ReactantStub = _field(reactor, Vector2(40.0, 0.0), 120.0, E.ICE, T.HEAVY)
	_expect(int(reactor.call(&"resolve_now")) == 1, "two frost fields meet")
	_expect(f3.consumed + f4.consumed == 1, "exactly one of them is absorbed")
	_expect(f3.grown > 0.0 or f4.grown > 0.0, "...and the survivor is told to grow")
	_drop(reactor, [f3, f4])

	# ── beam_resonance — same element reinforces instead of annihilating.
	var r1: ReactantStub = _beam(reactor, Vector2(-400.0, 0.0), Vector2(400.0, 0.0),
		E.FIRE, T.HEAVY, _caster_a)
	# _caster_a on BOTH: resonance is a SELF-combo now (one caster crossing their
	# own two beams). Two DIFFERENT casters on the same element annihilate, because
	# a mirror match resolving to "nothing is consumed" read on screen as nothing
	# happening — the maker reported exactly that from live play.
	var r2: ReactantStub = _beam(reactor, Vector2(0.0, -400.0), Vector2(0.0, 400.0),
		E.FIRE, T.HEAVY, _caster_a)
	var at_cross: Dummy = _dummy(Vector2(10.0, 10.0))
	var far: Dummy = _dummy(Vector2(900.0, 900.0))
	_expect(int(reactor.call(&"resolve_now")) == 1, "matched beams resonate")
	_expect(r1.consumed == 0 and r2.consumed == 0, "resonance destroys neither beam")
	_expect(at_cross.hp_lost > 0, "the crossing hurts what is standing in it")
	_expect(far.hp_lost == 0, "and nothing outside the bloom")
	_drop(reactor, [r1, r2])
	_free_all([at_cross, far])

	# ── void_charged — the knockback INVERTS into a pull. The sign is the whole row.
	var vf: ReactantStub = _field(reactor, Vector2(0.0, 0.0), 150.0, E.SHADOW, T.HEAVY)
	var blast: ReactantStub = _impact(reactor, Vector2(0.0, 0.0), 70.0, E.FIRE, T.HEAVY)
	var pulled: Dummy = _dummy(Vector2(80.0, 0.0))
	_expect(int(reactor.call(&"resolve_now")) == 1, "a blast inside a void field charges it")
	_expect(pulled.hp_lost > 0, "the void-charged blast hurts")
	_expect(pulled.knock.x < 0.0,
		"...and PULLS toward the detonation instead of shoving away")
	_drop(reactor, [vf, blast])
	_free_all([pulled])

	# ── shatter_ice_barrier, through the legacy `shatter()` fallback. IceWall has
	# published shatter() since before the reaction contract existed, so a barrier
	# with no reaction_consume must still die properly.
	var wall: LegacyBarrierStub = _legacy_barrier(reactor, Vector2(0.0, 0.0), E.ICE, T.HEAVY)
	var flame: ReactantStub = _beam(reactor, Vector2(-BEAM_LEN, -60.0), Vector2(60.0, -60.0),
		E.FIRE, T.QUICK, _caster_b)
	var near_wall: Dummy = _dummy(Vector2(40.0, -60.0))
	_expect(int(reactor.call(&"resolve_now")) == 1, "fire meets the ice wall")
	_expect(wall.shattered == 1,
		"a barrier with no reaction_consume dies through its own shatter()")
	_expect(near_wall.hp_lost > 0, "and the shards hurt what was beside it")
	_expect(near_wall.status == E.FIRE,
		"the ailment left behind is the ATTACKER's, not the wall's")
	_drop(reactor, [wall, flame])
	_free_all([near_wall])

	# ── shrapnel_cone — the same event with a direction. Behind the thrower is safe.
	var wall2: ReactantStub = _barrier(reactor, Vector2(0.0, 0.0), E.ICE, T.HEAVY)
	var thrown: ReactantStub = _projectile(reactor, Vector2(-300.0, -60.0),
		Vector2(30.0, -60.0), E.EARTH, T.HEAVY)
	var in_cone: Dummy = _dummy(Vector2(90.0, -60.0))
	var behind: Dummy = _dummy(Vector2(-90.0, -60.0))
	_expect(int(reactor.call(&"resolve_now")) == 1, "a thrown thing punches the ice wall")
	_expect(wall2.consumed == 1, "the wall comes apart")
	_expect(in_cone.hp_lost > 0, "shards fly the way the projectile was going")
	_expect(behind.hp_lost == 0,
		"...and NOT backward — standing behind the thrower is safe")
	_drop(reactor, [wall2, thrown])
	_free_all([in_cone, behind])

	# ── carve — the porous exception. Nothing is spent; the stone takes the damage.
	var stone: ReactantStub = _barrier(reactor, Vector2(0.0, 0.0), E.EARTH, T.HEAVY)
	var borer: ReactantStub = _beam(reactor, Vector2(-BEAM_LEN, -60.0), Vector2(60.0, -60.0),
		E.ARCANE, T.HEAVY, _caster_b)
	_expect(int(reactor.call(&"resolve_now")) == 1, "an even beam bores into stone")
	_expect(borer.consumed == 0, "carve does NOT stop the beam — that is the whole row")
	_expect(stone.consumed == 0, "...nor break the wall")
	_expect(stone.damaged > 0, "but the wall takes the damage the row names")
	_drop(reactor, [stone, borer])

	# ── ground_out — earth eats a lightning beam and stands.
	var stone2: ReactantStub = _barrier(reactor, Vector2(0.0, 0.0), E.EARTH, T.HEAVY)
	var lightning: ReactantStub = _beam(reactor, Vector2(-BEAM_LEN, -60.0),
		Vector2(60.0, -60.0), E.LIGHTNING, T.HEAVY, _caster_b)
	_expect(int(reactor.call(&"resolve_now")) == 1, "lightning meets earth")
	_expect(lightning.consumed == 1, "the beam is grounded out")
	_expect(stone2.consumed == 0, "and the wall is untouched")
	_drop(reactor, [stone2, lightning])


# ---------------------------------------------- the real node, with real ground

## The terrain rules, on the REAL AegisWard against a REAL collider — the half no
## stub can prove. "Nothing may sit inside or below terrain" is two separate
## refusals and both are asserted.
func _test_real_ward_and_terrain(reactor: Node) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	# A floor slab under x in [-200, 200], and a solid block of rock further right.
	_solid(arena, Vector2(0.0, 200.0), Vector2(400.0, 40.0))
	_solid(arena, Vector2(700.0, 60.0), Vector2(200.0, 320.0))
	# The physics server needs a frame before intersect_ray/intersect_shape see
	# bodies added this frame; without this every probe reports an empty world and
	# the terrain assertions below would pass for the wrong reason.
	await physics_frame
	await physics_frame

	var offset: float = float(_const_of(AEGIS_WARD, &"OFFSET"))
	var charges: int = int(_const_of(AEGIS_WARD, &"CHARGES"))

	# 1. Legal ground: it plants, it sits ON the floor, and it joins the reactor.
	var ok_ward: Node2D = _raise(arena, Vector2(-offset, 100.0), Vector2.RIGHT)
	await physics_frame
	_expect(is_instance_valid(ok_ward) and ok_ward.is_inside_tree(),
		"a ward over solid ground actually stands up")
	if is_instance_valid(ok_ward) and ok_ward.is_inside_tree():
		var base: Vector2 = ok_ward.call(&"base_point")
		_expect(absf(base.y - 180.0) < 2.0,
			"...planted on the floor SURFACE, not at the caster's height (got y=%.1f)" % base.y)
		_expect(int(ok_ward.call(&"charges")) == charges, "...with a full set of plates")
		_expect(int(ok_ward.call(&"reaction_weight")) == SpellTier.Tier.ULT,
			"...fighting on the ULT shelf while it is full")
		# A plate burns, and the shelf drops with it. This is the degradation
		# mechanic observed on the real node rather than on the static table.
		ok_ward.call(&"reaction_absorb", base - Vector2(0.0, 40.0))
		_expect(int(ok_ward.call(&"charges")) == charges - 1, "absorbing burns exactly one plate")
		_expect(int(ok_ward.call(&"reaction_weight")) == SpellTier.Tier.HEAVY,
			"...and the ward is measurably lighter for it")

	# 2. Over a pit: there is no floor out at x = -900, so it must refuse to exist
	# rather than hang in the void.
	var pit_ward: Node2D = _raise(arena, Vector2(-900.0 - offset, 100.0), Vector2.RIGHT)
	await physics_frame
	_expect(not is_instance_valid(pit_ward) or pit_ward.is_queued_for_deletion(),
		"a ward aimed over a pit FIZZLES instead of floating there")

	# 3. Inside solid rock: the gate's own volume is occupied, so it must refuse.
	var buried: Node2D = _raise(arena, Vector2(700.0 - offset, 60.0), Vector2.RIGHT)
	await physics_frame
	_expect(not is_instance_valid(buried) or buried.is_queued_for_deletion(),
		"a ward whose gate would be inside terrain FIZZLES")

	# 4. The projectile screen on the real node, with its negative case.
	if is_instance_valid(ok_ward) and ok_ward.is_inside_tree():
		var base2: Vector2 = ok_ward.call(&"base_point")
		var h: float = float(_const_of(AEGIS_WARD, &"HEIGHT"))
		var thick: float = float(_const_of(AEGIS_WARD, &"THICKNESS"))
		var pad: float = float(_const_of(AEGIS_WARD, &"SCREEN_PAD"))
		var hit_bolt: Bolt = _bolt(arena, base2 - Vector2(0.0, h * 0.5))
		var miss_bolt: Bolt = _bolt(arena,
			base2 + Vector2(thick * 0.5 + pad + 6.0, -h * 0.5))
		# Enough frames to clear SCREEN_INTERVAL and the rise.
		for i: int in 30:
			await physics_frame
		_expect(hit_bolt.eaten >= 1, "the gate eats an enemy bolt flying into it")
		_expect(miss_bolt.eaten == 0,
			"a bolt just outside the drawn gate is NOT eaten — the reach contract")
		ok_ward.queue_free()
	arena.queue_free()
	await physics_frame
	# The ward may still be registered if it was freed mid-life; make sure the
	# registry is clean so a later suite in the same session starts empty.
	reactor.call(&"resolve_now")


# ------------------------------------------------------------------- fixtures

func _raise(arena: Node, from: Vector2, aim: Vector2) -> Node2D:
	var w: Node2D = (load(AEGIS_WARD) as GDScript).new()
	arena.add_child(w)
	w.set(&"caster_node", _caster_a)
	w.call(&"raise_ward", from, aim, Color(1.0, 0.93, 0.6), "holy")
	return w


func _solid(parent: Node, at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1     # solid world geometry; see SpellWorld.SOLID_MASK
	body.collision_mask = 0
	parent.add_child(body)
	body.global_position = at
	var shape := RectangleShape2D.new()
	shape.size = size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


func _bolt(parent: Node, at: Vector2) -> Bolt:
	var b := Bolt.new()
	parent.add_child(b)
	b.global_position = at
	return b


func _dummy(at: Vector2) -> Dummy:
	var d := Dummy.new()
	root.add_child(d)
	d.global_position = at
	return d


func _stub(reactor: Node, form: int, element: int, weight: int, shape: Dictionary,
		owner_node: Node) -> ReactantStub:
	var s := ReactantStub.new()
	root.add_child(s)
	s.global_position = Vector2.ZERO   # parked at the origin, like every real one
	s.form = form
	s.element = element
	s.weight = weight
	s.shape = shape
	s.owner_node = owner_node
	reactor.call(&"register", s, form, element)
	return s


func _beam(reactor: Node, from: Vector2, to: Vector2, element: int, weight: int,
		owner_node: Node) -> ReactantStub:
	return _stub(reactor, ReactionTable.Form.BEAM, element, weight,
		SpellGeometry.capsule(from, to, 40.0), owner_node)


func _projectile(reactor: Node, from: Vector2, to: Vector2, element: int,
		weight: int) -> ReactantStub:
	return _stub(reactor, ReactionTable.Form.PROJECTILE, element, weight,
		SpellGeometry.capsule(from, to, 24.0), _caster_b)


func _impact(reactor: Node, at: Vector2, radius: float, element: int,
		weight: int) -> ReactantStub:
	return _stub(reactor, ReactionTable.Form.IMPACT, element, weight,
		SpellGeometry.circle(at, radius), _caster_b)


func _field(reactor: Node, at: Vector2, radius: float, element: int,
		weight: int) -> ReactantStub:
	return _stub(reactor, ReactionTable.Form.FIELD, element, weight,
		SpellGeometry.circle(at, radius), _caster_a)


## A ward / wall: a vertical capsule standing on `base`, which is what every
## barrier in the game publishes.
func _barrier(reactor: Node, base: Vector2, element: int, weight: int) -> ReactantStub:
	return _stub(reactor, ReactionTable.Form.BARRIER, element, weight,
		SpellGeometry.capsule(base, base - Vector2(0.0, 132.0), 26.0), _caster_a)


## A pre-contract barrier, registered the same way. Its shape matches `_barrier`'s
## so the two are interchangeable in a test.
func _legacy_barrier(reactor: Node, base: Vector2, element: int,
		weight: int) -> LegacyBarrierStub:
	var s := LegacyBarrierStub.new()
	root.add_child(s)
	s.global_position = Vector2.ZERO
	s.element = element
	s.weight = weight
	s.shape = SpellGeometry.capsule(base, base - Vector2(0.0, 132.0), 26.0)
	reactor.call(&"register", s, s.form, element)
	return s


func _drop(reactor: Node, nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			reactor.call(&"unregister", n)
			n.free()


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.free()
