# SpellReactor — the detector that turns "two effects are touching" into an
# authored reaction. ReactionTable/SpellGeometry are proven by
# tools/slice6_test_reactions.gd; this proves the REGISTRY around them.
#   godot --headless --path godot-project --script tools/slice6_test_reactor.gd
extends SceneTree

var _ran: bool = false


## A live effect, duck-typed exactly like a real spectacle — and, like every
## real spectacle, PARKED AT THE ORIGIN with its geometry living somewhere else
## entirely. That is the whole point of this stub: if the reactor ever reads a
## transform, `_test_origin_parked` fails.
class ReactantStub extends Node2D:
	var shape: Dictionary = {}
	var active: bool = true
	var form: int = 0
	var element: int = 0
	var consumed: int = 0
	var frozen: int = 0
	## Who cast it. Real spectacles always have one (SpellCaster assigns
	## caster_node on every beam), so a stub without an owner is not a realistic
	## case — an ownerless effect satisfies neither "same" nor "different" and
	## would silently match no hollow-purple rule at all.
	var owner_node: Node = null

	func reaction_owner() -> Node:
		return owner_node

	func reaction_shape() -> Dictionary:
		return shape

	func reaction_active() -> bool:
		return active

	func reaction_element() -> int:
		return element

	func reaction_form() -> int:
		return form

	func reaction_freeze() -> void:
		frozen += 1

	# Deliberately does NOT free itself, so the test can count consumptions.
	func reaction_consume() -> void:
		consumed += 1


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("FAIL: SpellReactor autoload is missing")
		quit(1)
		return true
	# Drive the sweep by hand instead of racing the 30 Hz timer.
	reactor.set_process(false)
	reactor.set(&"spawn_effects", false)
	var failed: int = 0
	failed += _test_registration(reactor)
	failed += _test_unregistered_world_is_inert(reactor)
	failed += _test_origin_parked(reactor)
	failed += _test_charge_phase(reactor)
	failed += _test_one_shot(reactor)
	failed += _test_consumption(reactor)
	failed += _test_no_rule_no_reaction(reactor)
	failed += _test_budget(reactor)
	failed += _test_max_live(reactor)
	if failed > 0:
		printerr("Slice6 reactor tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice6 reactor tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## A beam-shaped reactant. `at_origin` stays true for every stub in this file —
## the node sits at (0, 0) and its real geometry is in `shape`.
## `owner` defaults to a shared stand-in so beams read as ONE caster's own two
## spells — the self-combo, which is the headline path. Pass distinct owners to
## exercise the rarer cross-caster crossing.
func _beam(reactor: Node, from: Vector2, to: Vector2, element: int,
		register: bool = true, owner: Node = null) -> ReactantStub:
	var s := ReactantStub.new()
	root.add_child(s)
	s.global_position = Vector2.ZERO
	s.form = ReactionTable.Form.BEAM
	s.element = element
	s.owner_node = owner if owner != null else _default_caster()
	s.shape = SpellGeometry.capsule(from, to, 40.0)
	if register:
		reactor.call(&"register", s, s.form, s.element)
	return s


var _caster: Node = null


## One stand-in caster reused across the file, so two beams built without an
## explicit owner belong to the SAME caster.
func _default_caster() -> Node:
	if _caster == null or not is_instance_valid(_caster):
		_caster = Node.new()
		_caster.name = "StubCaster"
		root.add_child(_caster)
	return _caster


func _drop(reactor: Node, nodes: Array) -> void:
	for n: Node in nodes:
		reactor.call(&"unregister", n)
		n.free()


func _test_registration(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	var a: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE)
	var b: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.ICE)
	ok += _expect(int(reactor.call(&"live_count")) == 2, "two registrations are tracked")
	reactor.call(&"unregister", a)
	ok += _expect(int(reactor.call(&"live_count")) == 1, "unregister removes exactly one")
	# A double registration must not double-count.
	reactor.call(&"register", b, b.form, b.element)
	ok += _expect(int(reactor.call(&"live_count")) == 1, "registering twice is idempotent")
	# A freed node is swept without anyone calling unregister.
	b.free()
	reactor.call(&"resolve_now")
	ok += _expect(int(reactor.call(&"live_count")) == 0, "a freed reactant is swept")
	a.free()
	return ok


## The system lands DARK. Nothing registered means nothing happens, whatever is
## on screen — which is what makes the rollout spell-by-spell safe.
func _test_unregistered_world_is_inert(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	var a: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE, false)
	var b: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.ICE, false)
	ok += _expect(int(reactor.call(&"live_count")) == 0, "an unregistered world is empty")
	ok += _expect(int(reactor.call(&"resolve_now")) == 0,
		"two crossed opposing beams that never registered do not react")
	ok += _expect(a.consumed == 0 and b.consumed == 0, "...and neither is consumed")
	_drop(reactor, [a, b])
	return ok


## ⚠ THE REGRESSION THIS WHOLE DESIGN EXISTS FOR. Both stubs sit at (0, 0) —
## like BeamSpell, ZoneSpell, ChainBolt and seven others — but their effects are
## 4000 px apart. A detector comparing transforms would fire here, and it would
## fire for EVERY pair of live spectacles, at the top-left of the arena.
func _test_origin_parked(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	var a: ReactantStub = _beam(reactor, Vector2(-2400, 0), Vector2(-1800, 0), E.FIRE)
	var b: ReactantStub = _beam(reactor, Vector2(1800, -300), Vector2(1800, 300), E.ICE)
	ok += _expect(a.global_position == Vector2.ZERO and b.global_position == Vector2.ZERO,
		"both stubs really are parked at the origin")
	ok += _expect(int(reactor.call(&"resolve_now")) == 0,
		"origin-parked effects with distant shapes do NOT react")
	# Positive control: same nodes, same transforms, shapes moved to cross.
	a.shape = SpellGeometry.capsule(Vector2(-400, 0), Vector2(400, 0), 40.0)
	b.shape = SpellGeometry.capsule(Vector2(0, -400), Vector2(0, 400), 40.0)
	ok += _expect(int(reactor.call(&"resolve_now")) == 1,
		"...and DO react once their shapes actually cross")
	_drop(reactor, [a, b])
	return ok


## A beam inside its 0.34 s charge telegraph is registered but not yet real.
func _test_charge_phase(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	var a: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.SHADOW)
	var b: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.HOLY)
	a.active = false
	ok += _expect(int(reactor.call(&"resolve_now")) == 0,
		"a charging beam cannot annihilate anything")
	ok += _expect(a.consumed == 0 and b.consumed == 0, "...and nothing is spent")
	a.active = true
	ok += _expect(int(reactor.call(&"resolve_now")) == 1,
		"the same pair reacts the moment both are live")
	_drop(reactor, [a, b])
	return ok


## One crossing, one reaction — even though the pair keeps overlapping every
## tick for as long as both effects live.
func _test_one_shot(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	var before: int = int(reactor.get(&"fired_count"))
	var a: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.ARCANE)
	var b: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.WIND)
	ok += _expect(int(reactor.call(&"resolve_now")) == 1, "the crossing fires")
	ok += _expect(int(reactor.call(&"resolve_now")) == 0, "and does not fire again")
	ok += _expect(int(reactor.call(&"resolve_now")) == 0, "or the tick after that")
	ok += _expect(int(reactor.get(&"fired_count")) == before + 1,
		"exactly one reaction is counted for one crossing")
	_drop(reactor, [a, b])
	return ok


## Hollow Purple spends both beams — and seizes them first.
func _test_consumption(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	var a: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.LIGHTNING)
	var b: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.EARTH)
	reactor.call(&"resolve_now")
	ok += _expect(a.frozen == 1 and b.frozen == 1, "both beams are SEIZED, once each")
	ok += _expect(a.consumed == 1 and b.consumed == 1, "both beams are spent, once each")
	# A crossing that is only a muzzle graze is not an annihilation.
	var c: ReactantStub = _beam(reactor, Vector2(-400, 200), Vector2(400, 200), E.FIRE)
	var d: ReactantStub = _beam(reactor, Vector2(-400, 220), Vector2(-360, 220), E.ICE)
	ok += _expect(int(reactor.call(&"resolve_now")) == 0,
		"a stub too short to be a beam cannot collapse one")
	_drop(reactor, [a, b, c, d])
	return ok


func _test_no_rule_no_reaction(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	# Fire and lightning are neither opposed nor the same: no authored row.
	var a: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE)
	var b: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.LIGHTNING)
	ok += _expect(int(reactor.call(&"resolve_now")) == 0,
		"beams with no authored relationship simply coexist")
	_drop(reactor, [a, b])
	return ok


## A barrage must not resolve eleven reactions in one tick.
func _test_budget(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	var stubs: Array = []
	for i: int in 4:
		# Four same-element beams all crossing near the origin = six pairs, every
		# one of them matching the resonance row.
		var ang: float = float(i) * 0.4
		var d: Vector2 = Vector2.from_angle(ang) * 400.0
		stubs.append(_beam(reactor, -d, d, E.FIRE))
	var fired: int = int(reactor.call(&"resolve_now"))
	ok += _expect(fired == 2, "a tick fires at most MAX_REACTIONS_PER_TICK (got %d)" % fired)
	_drop(reactor, stubs)
	return ok


func _test_max_live(reactor: Node) -> int:
	var ok: int = 0
	var E := Elements.Element
	var stubs: Array = []
	for i: int in 20:
		stubs.append(_beam(reactor, Vector2(-400, float(i) * 60.0), Vector2(400, float(i) * 60.0), E.FIRE))
	ok += _expect(int(reactor.call(&"live_count")) == 12,
		"registrations are capped at MAX_LIVE (got %d)" % int(reactor.call(&"live_count")))
	_drop(reactor, stubs)
	ok += _expect(int(reactor.call(&"live_count")) == 0, "the registry empties again")
	return ok
