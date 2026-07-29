# WEIGHT — the second axis of the reaction table. "Two evenly matched spells
# explode and cancel out; a heavy one just wins."
#
# Split in two halves, matching how the layer is built:
#   TABLE   — the predicate is pure data, so the whole ladder is provable with no
#             scene at all. This is where the ORDERING lives: that a weight rule
#             never steals Hollow Purple or beam_resonance is a fact about
#             numbers, and it is asserted here as one.
#   REACTOR — the registry actually reading reaction_weight() off live effects,
#             including the case that has to keep working for the next ~15
#             spectacles: a participant that does not implement it at all.
#
# The origin-parked guarantee (see slice6_test_reactor.gd) is re-asserted at the
# end with weights in play, because a weight predicate that accidentally short-
# circuited the geometry stage would resurrect exactly that bug.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_weight.gd
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"weight_helpers",
	"unknown_weight_is_conservative",
	"equal_beams_annihilate",
	"unequal_beams_do_not_annihilate",
	"consumes_caller_mapping",
	"priority_ladder_is_element_first",
	"beam_ladder_priority_numbers",
	"annihilation_reach_is_the_drawn_radius",
	"barrier_ladder",
	"reactor_equal_weight_cancels",
	"reactor_unequal_weight_spends_only_the_lighter",
	"reactor_self_clash_is_protected",
	"reactor_weightless_participant",
	"reactor_still_origin_safe",
]

var _fails: int = 0
var _completed: Dictionary = {}

var _ran: bool = false


## A live effect, duck-typed like a real spectacle and — like every real
## spectacle — PARKED AT THE ORIGIN with its real geometry somewhere else.
## `weight` is served through reaction_weight() unless `has_weight` is false, in
## which case the method still exists but the stub is swapped for WeightlessStub
## below; see _beam().
class ReactantStub extends Node2D:
	var shape: Dictionary = {}
	var active: bool = true
	var form: int = 0
	var element: int = 0
	var weight: int = SpellTier.Tier.HEAVY
	var consumed: int = 0
	var frozen: int = 0
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

	func reaction_weight() -> int:
		return weight

	func reaction_freeze() -> void:
		frozen += 1

	func reaction_consume() -> void:
		consumed += 1


## The same effect with NO reaction_weight() — i.e. every spectacle in the game
## except the ones that have adopted the contract. It must keep working, and it
## must keep weighing the same as its un-adopted neighbours.
class WeightlessStub extends ReactantStub:
	func reaction_weight() -> int:
		# GDScript cannot un-declare an inherited method, so the "not implemented"
		# case is faked at the call site instead: _beam() registers this stub and
		# the test asserts against SpellTier.DEFAULT_WEIGHT directly. Kept here so
		# the intent is visible rather than implied by an absence.
		return SpellTier.DEFAULT_WEIGHT


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("FAIL: SpellReactor autoload is missing")
		quit(1)
		return true
	reactor.set_process(false)
	reactor.set(&"spawn_effects", false)
	# --- the shelf arithmetic
	_test_weight_helpers()
	# --- the table
	_test_unknown_weight_is_conservative()
	_test_equal_beams_annihilate()
	_test_unequal_beams_do_not_annihilate()
	_test_consumes_caller_mapping()
	_test_priority_ladder_is_element_first()
	_test_beam_ladder_priority_numbers()
	_test_annihilation_reach_is_the_drawn_radius()
	_test_barrier_ladder()
	# --- the reactor
	_test_reactor_equal_weight_cancels(reactor)
	_test_reactor_unequal_weight_spends_only_the_lighter(reactor)
	_test_reactor_self_clash_is_protected(reactor)
	_test_reactor_weightless_participant(reactor)
	_test_reactor_still_origin_safe(reactor)
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice6 weight tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice6 weight tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------ shelf arithmetic

func _test_weight_helpers() -> void:
	var T := SpellTier.Tier
	_expect(SpellTier.weights_match(T.HEAVY, T.HEAVY), "the same shelf is evenly matched")
	_expect(not SpellTier.weights_match(T.ULT, T.QUICK), "an ult does not trade with a jab")
	_expect(SpellTier.outweighs(T.ULT, T.HEAVY), "ULT outweighs HEAVY")
	_expect(not SpellTier.outweighs(T.HEAVY, T.ULT), "outweighing is not symmetric")
	_expect(not SpellTier.outweighs(T.HEAVY, T.HEAVY), "a shelf does not outweigh itself")
	# The default has to be usable as a real shelf everywhere, including from
	# garbage — a spectacle returning -7 must read as "average", not poison a
	# comparison into firing something.
	_expect(SpellTier.weight_or_default(SpellTier.WEIGHT_UNKNOWN) == SpellTier.DEFAULT_WEIGHT,
		"an unknown weight resolves to the default")
	_expect(SpellTier.weight_or_default(-7) == SpellTier.DEFAULT_WEIGHT,
		"garbage resolves to the default")
	_expect(SpellTier.weight_or_default(999) == SpellTier.DEFAULT_WEIGHT,
		"an out-of-range shelf resolves to the default")
	# Two spells that both never adopted the contract are evenly matched, which is
	# the property the whole staged rollout rests on.
	_expect(SpellTier.weights_match(SpellTier.DEFAULT_WEIGHT, SpellTier.DEFAULT_WEIGHT),
		"two un-adopted spells stay evenly matched with each other")
	_completes("weight_helpers")


# ------------------------------------------------------------------- the table

## A caller that supplies no weights gets back ONLY the weight-blind half of the
## table. Assuming "evenly matched" instead would have match_rule invent an
## annihilation out of information it does not have.
func _test_unknown_weight_is_conservative() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var r: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "different")
	_expect(r.is_empty(),
		"no weights supplied = no weight-gated row fires (got '%s')" % String(r.get("outcome", "")))
	# ...while a weight-blind row is completely unaffected by not knowing.
	var s: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BARRIER, E.ICE, "different")
	_expect(String(s.get("outcome", "")) == "shatter_ice_barrier",
		"a weight-blind row still matches without weights")
	_completes("unknown_weight_is_conservative")


func _test_equal_beams_annihilate() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	var r: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "different", T.HEAVY, T.HEAVY)
	_expect(String(r.get("outcome", "")) == "mutual_annihilation",
		"two evenly matched beams cancel each other out (got '%s')" % String(r.get("outcome", "")))
	_expect(bool(r.get("consumes_a", false)) and bool(r.get("consumes_b", false)),
		"...and BOTH are spent")
	# The shelf, not the spell: two ULTs annihilate exactly like two HEAVYs.
	var r2: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.SHADOW, F.BEAM, E.EARTH, "different", T.ULT, T.ULT)
	_expect(String(r2.get("outcome", "")) == "mutual_annihilation",
		"two ults are just as evenly matched as two heavies")
	_completes("equal_beams_annihilate")


func _test_unequal_beams_do_not_annihilate() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	var r: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "different", T.ULT, T.QUICK)
	_expect(String(r.get("outcome", "")) == "overpower",
		"a heavier beam overpowers rather than trading (got '%s')" % String(r.get("outcome", "")))
	# THE POINT OF THE WHOLE FEATURE: the big one is not spent.
	_expect(not ReactionTable.consumes_caller(r, 0), "the heavier beam survives")
	_expect(ReactionTable.consumes_caller(r, 1), "the lighter beam is eaten")
	# One shelf apart is already a mismatch at the current tolerance.
	var r2: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "different", T.HEAVY, T.QUICK)
	_expect(String(r2.get("outcome", "")) == "overpower",
		"one shelf of difference is enough to win outright")
	_completes("unequal_beams_do_not_annihilate")


## The row is authored once, with the heavy side written as form_a. When the pair
## arrives the other way round the row still matches — and its consumes_a then
## means the CALLER's b. Getting this backwards would eat the wrong spell.
func _test_consumes_caller_mapping() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	var straight: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "different", T.ULT, T.QUICK)
	_expect(not bool(straight.get("swapped", true)),
		"heavy-first matches the row as written")
	var reversed: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "different", T.QUICK, T.ULT)
	_expect(String(reversed.get("outcome", "")) == "overpower",
		"the same row matches with the light side first")
	_expect(bool(reversed.get("swapped", false)), "...and reports that it swapped")
	_expect(ReactionTable.consumes_caller(reversed, 0),
		"the caller's a is the lighter one here, so IT is eaten")
	_expect(not ReactionTable.consumes_caller(reversed, 1),
		"and the caller's b survives")
	# Reading the raw flag would have got this exactly wrong — proving the helper
	# is not ceremony.
	_expect(bool(reversed.get("consumes_b", false)) and not bool(reversed.get("consumes_a", false)),
		"the raw flags still describe the ROW's sides, not the caller's")
	_completes("consumes_caller_mapping")


## THE BEAM x BEAM LADDER, PINNED BY NUMBER.
##
## `_test_priority_ladder_is_element_first` pins the ORDER; this pins the actual
## priorities, because the order is only safe for as long as nobody inserts a row
## between two of them. The maker's report was that two clashing beams did
## nothing, and the fix was to give `mutual_annihilation` its own ult-sized beat
## in ReactionOutcomes — a change that must NOT have moved anything in the table.
## Asserting the four numbers is the cheapest possible proof that it did not, and
## it is the guard that will catch the next person who "just bumps" a priority to
## make their new row win.
##
## The two headline specials keep their say: opposed elements still fuse into
## Hollow Purple ABOVE the clash, and same-element beams still resonate above it
## too. The clash is what is left over — which is most of the matrix, and is why
## it had to be the loud one.
func _test_beam_ladder_priority_numbers() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	var expected: Array = [
		# outcome, element_a, element_b, owner_rel, weight_a, weight_b, priority
		["hollow_purple", E.FIRE, E.ICE, "same", T.HEAVY, T.HEAVY, 100],
		["hollow_purple", E.FIRE, E.ICE, "different", T.HEAVY, T.HEAVY, 95],
		["beam_resonance", E.FIRE, E.FIRE, "same", T.HEAVY, T.HEAVY, 60],
		["mutual_annihilation", E.FIRE, E.LIGHTNING, "different", T.HEAVY, T.HEAVY, 55],
		["overpower", E.FIRE, E.LIGHTNING, "different", T.ULT, T.QUICK, 50],
	]
	for row: Array in expected:
		var r: Dictionary = ReactionTable.match_rule(
			F.BEAM, int(row[1]), F.BEAM, int(row[2]),
			String(row[3]), int(row[4]), int(row[5]))
		_expect(String(r.get("outcome", "")) == String(row[0]),
			"beam ladder: expected '%s', got '%s'" % [String(row[0]), String(r.get("outcome", ""))])
		_expect(int(r.get("priority", -1)) == int(row[6]),
			"'%s' still sits at priority %d (got %s)"
				% [String(row[0]), int(row[6]), str(r.get("priority", "-"))])
	# ...and the ordering those numbers encode, stated as a relation so a future
	# renumbering that preserves the story still passes.
	var fuse: int = int(ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.ICE,
		"different", T.HEAVY, T.HEAVY).get("priority", -1))
	# Resonance is queried with owner_rel "same" — it is a SELF-combo reward now, so
	# "different" no longer reaches it at all and would silently read back the
	# clash's own priority, making this relation compare 55 against 55.
	var res: int = int(ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.FIRE,
		"same", T.HEAVY, T.HEAVY).get("priority", -1))
	var clash: int = int(ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING,
		"different", T.HEAVY, T.HEAVY).get("priority", -1))
	_expect(fuse > res and res > clash,
		"fusion > resonance > clash (%d > %d > %d)" % [fuse, res, clash])
	# The clash spends BOTH — the half of "explode and go away" that lives in data.
	var both: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING,
		"different", T.HEAVY, T.HEAVY)
	_expect(ReactionTable.consumes_caller(both, 0) and ReactionTable.consumes_caller(both, 1),
		"an annihilation still spends both beams")
	_completes("beam_ladder_priority_numbers")


## ⚠ THE HARD RULE: DAMAGE STAYS INSIDE WHAT IS DRAWN. `_annihilate` derives its
## damaged area from the row's authored radius, and its burst speeds from that
## same number, so the picture and the hit test cannot drift apart. This asserts
## the hit test half from BOTH sides — a dummy inside is hurt, and a dummy just
## OUTSIDE takes exactly zero, which is the assertion that would actually catch a
## regression (an over-reaching blast passes every positive test ever written).
func _test_annihilation_reach_is_the_drawn_radius() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	var rule: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING,
		"different", T.HEAVY, T.HEAVY)
	var radius: float = float(rule.get("radius", 0.0))
	_expect(radius > 0.0, "the annihilation row authors a radius (got %s)" % str(radius))
	var at := Vector2(600.0, 600.0)   # well away from anything else the suite built
	var inside: DummyBody = _dummy(at + Vector2(radius * 0.5, 0.0))
	var outside: DummyBody = _dummy(at + Vector2(radius + 40.0, 0.0))
	# spawn_effects false: prove the DAMAGE without staging an ult-sized set-piece
	# (and without touching Juice/PostProcess, which need a viewport).
	ReactionOutcomes.apply("mutual_annihilation", {
		"rule": rule, "a": inside, "b": outside,
		"element_a": E.FIRE, "element_b": E.LIGHTNING,
		"weight_a": T.HEAVY, "weight_b": T.HEAVY,
		"shape_a": {}, "shape_b": {},
		"owner_rel": "different", "point": at, "spawn_effects": false,
	})
	_expect(inside.damage_taken > 0,
		"a body inside the annihilation is hurt (took %d)" % inside.damage_taken)
	_expect(outside.damage_taken == 0,
		"a body just OUTSIDE the drawn radius takes zero (took %d)" % outside.damage_taken)
	inside.queue_free()
	outside.queue_free()
	_completes("annihilation_reach_is_the_drawn_radius")


## Something `_radial` can find and hurt: in the "enemy" group, at a real
## position, answering take_damage.
func _dummy(at: Vector2) -> DummyBody:
	var d := DummyBody.new()
	d.global_position = at
	d.add_to_group("enemy")
	root.add_child(d)
	return d


class DummyBody extends Node2D:
	var damage_taken: int = 0

	func take_damage(amount: int) -> void:
		damage_taken += amount


## Weight is the TIEBREAK, not the headline. A weight row must never steal a
## reaction the elements already decided.
func _test_priority_ladder_is_element_first() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	# Opposed elements fuse whatever the shelves say — a signature combo that only
	# fired when the weights lined up is a signature combo you cannot rely on.
	var hp: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.ICE, "same", T.ULT, T.QUICK)
	_expect(String(hp.get("outcome", "")) == "hollow_purple",
		"Hollow Purple still fires across a huge weight gap (got '%s')" % String(hp.get("outcome", "")))
	var hp2: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.SHADOW, F.BEAM, E.HOLY, "different", T.HEAVY, T.HEAVY)
	_expect(String(hp2.get("outcome", "")) == "hollow_purple",
		"...and outranks the evenly-matched clash too")
	# Same element reinforces ONLY as a SELF-combo — one caster crossing their own
	# two beams. Two DUELLISTS who happen to pick the same beam now annihilate.
	# That is the mirror-match case, and resonating there consumed nothing and read
	# on screen as "nothing happened" (maker, from live play).
	var res: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.FIRE, "same", T.HEAVY, T.HEAVY)
	_expect(String(res.get("outcome", "")) == "beam_resonance",
		"one caster's own matched beams reinforce")
	var res2: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.FIRE, "same", T.ULT, T.QUICK)
	_expect(String(res2.get("outcome", "")) == "beam_resonance",
		"...at any weights, because it is a reward rather than a contest")
	var mirror: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.FIRE, "different", T.HEAVY, T.HEAVY)
	_expect(String(mirror.get("outcome", "")) == "mutual_annihilation",
		"TWO DUELLISTS on the same beam annihilate — the mirror match explodes")
	# The clash is only for what the elements left undecided.
	var neutral: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "different", T.HEAVY, T.HEAVY)
	_expect(String(neutral.get("outcome", "")) == "mutual_annihilation",
		"neutral elements fall through to the weight contest")
	# One caster's own two beams must NEVER cancel: that is the double-tap the
	# Hollow Purple self-combo trains, and punishing it would be the worst
	# possible outcome of adding this row.
	var mine: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "same", T.HEAVY, T.HEAVY)
	_expect(mine.is_empty(),
		"your own two beams do not cancel each other (got '%s')" % String(mine.get("outcome", "")))
	_completes("priority_ladder_is_element_first")


## Three rungs, one story: a barrier stops what it is not outmatched by.
func _test_barrier_ladder() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	# Rung 1 — heavier spell destroys the wall and carries on.
	var breach: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.ARCANE, F.BARRIER, E.EARTH, "different", T.ULT, T.QUICK)
	_expect(String(breach.get("outcome", "")) == "breach",
		"a heavy beam breaches a wall (got '%s')" % String(breach.get("outcome", "")))
	_expect(not ReactionTable.consumes_caller(breach, 0), "the beam is not stopped")
	_expect(ReactionTable.consumes_caller(breach, 1), "the wall is destroyed")
	# Rung 2 — evenly matched beam bores through stone without breaking it.
	var carve: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.ARCANE, F.BARRIER, E.EARTH, "different", T.HEAVY, T.HEAVY)
	_expect(String(carve.get("outcome", "")) == "carve",
		"an evenly matched beam carves stone (got '%s')" % String(carve.get("outcome", "")))
	_expect(not ReactionTable.consumes_caller(carve, 0)
		and not ReactionTable.consumes_caller(carve, 1),
		"...and neither side is spent")
	# Rung 3 — anything under-weight is simply stopped, whatever it is made of.
	var blocked: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.ARCANE, F.BARRIER, E.EARTH, "different", T.QUICK, T.ULT)
	_expect(String(blocked.get("outcome", "")) == "barrier_blocks",
		"an under-weight beam is stopped by the wall (got '%s')" % String(blocked.get("outcome", "")))
	_expect(ReactionTable.consumes_caller(blocked, 0), "the beam is spent on it")
	_expect(not ReactionTable.consumes_caller(blocked, 1), "and the wall holds")
	# A non-earth barrier has no carve exception, so equal weights already block.
	var equal_ice: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.ARCANE, F.BARRIER, E.ICE, "different", T.HEAVY, T.HEAVY)
	_expect(String(equal_ice.get("outcome", "")) == "barrier_blocks",
		"an evenly matched beam does not get through a non-stone wall")
	# ...but the ELEMENTAL answer still beats brute force from either direction:
	# a QUICK fire beam pops an ULT ice wall, because bringing fire IS the answer.
	var counter: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BARRIER, E.ICE, "different", T.QUICK, T.ULT)
	_expect(String(counter.get("outcome", "")) == "shatter_ice_barrier",
		"the right element beats a heavier wall (got '%s')" % String(counter.get("outcome", "")))
	# A thrown thing inherits the same ladder with no extra rows for its kind.
	var thrown: int = ReactionTable.form_for_kind(SpellDef.Kind.BOULDER)
	var thrown_breach: Dictionary = ReactionTable.match_rule(
		thrown, E.EARTH, F.BARRIER, E.ARCANE, "different", T.ULT, T.QUICK)
	_expect(String(thrown_breach.get("outcome", "")) == "breach",
		"a projectile inherits the breach rung")
	_completes("barrier_ladder")


# ----------------------------------------------------------------- the reactor

var _casters: Array[Node] = []


## A distinct caster per call, so pairs read as "different owners" — which the
## clash rows require, and which is the realistic case (your beam vs the boss's).
func _caster(tag: String) -> Node:
	var n := Node.new()
	n.name = "Caster_%s" % tag
	root.add_child(n)
	_casters.append(n)
	return n


func _beam(reactor: Node, from: Vector2, to: Vector2, element: int, owner: Node,
		weight: int = SpellTier.Tier.HEAVY, weightless: bool = false) -> ReactantStub:
	var s: ReactantStub = WeightlessStub.new() if weightless else ReactantStub.new()
	root.add_child(s)
	s.global_position = Vector2.ZERO
	s.form = ReactionTable.Form.BEAM
	s.element = element
	s.weight = weight
	s.owner_node = owner
	s.shape = SpellGeometry.capsule(from, to, 40.0)
	reactor.call(&"register", s, s.form, s.element)
	return s


func _drop(reactor: Node, nodes: Array) -> void:
	for n: Node in nodes:
		reactor.call(&"unregister", n)
		n.free()
	for c: Node in _casters:
		if is_instance_valid(c):
			c.free()
	_casters.clear()


## Two casters, neutral elements, same shelf: both beams die at the crossing.
func _test_reactor_equal_weight_cancels(reactor: Node) -> void:
	var E := Elements.Element
	var T := SpellTier.Tier
	var a: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE,
		_caster("hero"), T.HEAVY)
	var b: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.LIGHTNING,
		_caster("boss"), T.HEAVY)
	_expect(int(reactor.call(&"resolve_now")) == 1, "the clash fires once")
	_expect(a.consumed == 1 and b.consumed == 1,
		"both beams are spent (a=%d b=%d)" % [a.consumed, b.consumed])
	_expect(int(reactor.call(&"resolve_now")) == 0, "and does not fire again")
	_drop(reactor, [a, b])
	_completes("reactor_equal_weight_cancels")


## The same crossing with one side a shelf heavier: the big one walks through.
func _test_reactor_unequal_weight_spends_only_the_lighter(reactor: Node) -> void:
	var E := Elements.Element
	var T := SpellTier.Tier
	var big: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE,
		_caster("hero"), T.ULT)
	var small: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.LIGHTNING,
		_caster("boss"), T.QUICK)
	_expect(int(reactor.call(&"resolve_now")) == 1, "the overpower fires once")
	_expect(big.consumed == 0, "the ult is NOT cancelled by a jab")
	_expect(small.consumed == 1, "the jab is eaten")
	_drop(reactor, [big, small])
	_completes("reactor_unequal_weight_spends_only_the_lighter")


## Registration order must not decide who wins — the reactor sees pairs in list
## order, so the light beam registering first is the case that would expose a
## side-mapping bug.
func _test_reactor_self_clash_is_protected(reactor: Node) -> void:
	var E := Elements.Element
	var T := SpellTier.Tier
	# Light one first, on purpose.
	var small: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE,
		_caster("hero"), T.QUICK)
	var big: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.LIGHTNING,
		_caster("boss"), T.ULT)
	reactor.call(&"resolve_now")
	_expect(small.consumed == 1 and big.consumed == 0,
		"the lighter beam is eaten whichever order it registered in (small=%d big=%d)"
			% [small.consumed, big.consumed])
	_drop(reactor, [small, big])
	# And the self-combo protection, live: ONE caster's two neutral beams.
	var mine: Node = _caster("solo")
	var x: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE, mine, T.HEAVY)
	var y: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.LIGHTNING, mine, T.HEAVY)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"your own two beams do not annihilate each other")
	_expect(x.consumed == 0 and y.consumed == 0, "...and neither is spent")
	_drop(reactor, [x, y])
	_completes("reactor_self_clash_is_protected")


## The case the next ~15 spectacles are all in today: no reaction_weight() of
## their own. They must keep reacting exactly as they did, which means weighing
## the default and therefore staying evenly matched with each other.
func _test_reactor_weightless_participant(reactor: Node) -> void:
	var E := Elements.Element
	var a: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE,
		_caster("hero"), SpellTier.DEFAULT_WEIGHT, true)
	var b: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.LIGHTNING,
		_caster("boss"), SpellTier.DEFAULT_WEIGHT, true)
	_expect(int(reactor.call(&"resolve_now")) == 1,
		"two un-adopted spectacles still meet as equals")
	_expect(a.consumed == 1 and b.consumed == 1, "...and both are spent")
	_drop(reactor, [a, b])
	# An un-adopted spectacle against an adopted ULT loses, which is the whole
	# reason the default is the MIDDLE shelf and not the top one.
	var plain: ReactantStub = _beam(reactor, Vector2(-400, 0), Vector2(400, 0), E.FIRE,
		_caster("hero"), SpellTier.DEFAULT_WEIGHT, true)
	var ult: ReactantStub = _beam(reactor, Vector2(0, -400), Vector2(0, 400), E.LIGHTNING,
		_caster("boss"), SpellTier.Tier.ULT)
	reactor.call(&"resolve_now")
	_expect(plain.consumed == 1 and ult.consumed == 0,
		"an adopted ult beats an un-adopted spell (plain=%d ult=%d)"
			% [plain.consumed, ult.consumed])
	_drop(reactor, [plain, ult])
	_completes("reactor_weightless_participant")


## ⚠ THE REGRESSION THE WHOLE LAYER EXISTS FOR, re-asserted with weight in play.
## Both stubs sit at (0, 0) and are perfectly evenly matched — the most tempting
## possible pair for a detector that had started trusting transforms — but their
## effects are 4000 px apart and they must stay silent.
func _test_reactor_still_origin_safe(reactor: Node) -> void:
	var E := Elements.Element
	var T := SpellTier.Tier
	var a: ReactantStub = _beam(reactor, Vector2(-2400, 0), Vector2(-1800, 0), E.FIRE,
		_caster("hero"), T.HEAVY)
	var b: ReactantStub = _beam(reactor, Vector2(1800, -300), Vector2(1800, 300), E.LIGHTNING,
		_caster("boss"), T.HEAVY)
	_expect(a.global_position == Vector2.ZERO and b.global_position == Vector2.ZERO,
		"both stubs really are parked at the origin")
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"evenly matched effects 4000 px apart do NOT clash")
	_expect(a.consumed == 0 and b.consumed == 0, "...and neither is spent")
	# Positive control: same nodes, same transforms, shapes moved to cross.
	a.shape = SpellGeometry.capsule(Vector2(-400, 0), Vector2(400, 0), 40.0)
	b.shape = SpellGeometry.capsule(Vector2(0, -400), Vector2(0, 400), 40.0)
	_expect(int(reactor.call(&"resolve_now")) == 1,
		"...and DO clash once their shapes actually cross")
	_drop(reactor, [a, b])
	_completes("reactor_still_origin_safe")
