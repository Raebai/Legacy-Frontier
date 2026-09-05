# THE REGISTRATION HALF OF THE REACTION SYSTEM — proved on the REAL spell scripts,
# not on stubs.
#
# ── WHY THIS SUITE EXISTS, AND WHY IT IS NOT MORE TABLE TESTS ─────────────────
# `tools/slice10_test_natural_reactions.gd` proves the TABLE: given two descriptors,
# the right row wins at the right priority. It proves it with duck-typed stubs,
# deliberately, and that is the right tool for the job it does. What no suite in the
# repo proved was the step BEFORE the table — that any real spell ever enters the
# registry at all.
#
# MEASURED (`tools/probe_reaction_count.gd`, full 36-bout round robin, three runs):
#     reactions fired   14 / 12 / 12   from 6 / 6 / 4 of 21 authored outcomes
#     pair tests        1336 / 593 / 707
#     registry          0.86 / 0.78 / 0.88 effects live on average
# A reaction needs TWO live effects. At 0.84 average the registry is almost never
# holding two of anything, and the reason is that TWENTY of the thirty-six spells in
# the nine kits never called `SpellReactor.register`. The matrix was not refusing the
# player, it was barely being asked. Three of those twenty adopted the contract with
# this suite: `ChainBolt` (the Stormcaller's damage line), `DivineRay` (the file
# `ReactionTable`'s own `banish` block names by hand as the missing adopter) and
# `Shatter` (the whole of the Cryomancer's damage output).
#
# ⚠ SO EVERY ASSERTION HERE IS ON A REAL INSTANCE OF A REAL SPELL SCRIPT. A stub that
# answers `reaction_form()` correctly proves nothing about whether the shipped file
# does, and "the file has a method with the right name" proves nothing about whether
# anything ever CALLS it. Each of the three is built, stamped the way `SpellCaster
# ._stamp()` stamps it, told to join the reactor through its OWN `_join_reactor()`,
# and then driven through the real `SpellReactor.resolve_now()` against a partner.
#
# ⚠ AND THE THREE NEGATIVES ARE THE POINT, not decoration:
#   1. NOT WHILE IT IS ONLY A TELEGRAPH. Judgment hangs a motionless thread for
#      0.55 s and Shatter's fuse etches for 0.28 s; both are dodge windows and both
#      are the spell's whole fairness contract. An effect that reacted during its own
#      tell would banish a field, or burst a wall, before the attack that caused it
#      had arrived — the payoff first, then the miss.
#   2. NOT AT THE ARENA ORIGIN. All three of these park at (0, 0) and draw in world
#      coordinates, which is the exact trap `SpellReactor`'s and `SpellGeometry`'s
#      headers are both built around: a detector that read transforms would report
#      every pair as touching, at the top-left of the arena. These files are new
#      adopters, so they are new chances to make that mistake.
#   3. AND IT MUST FIRE ONCE THE SHAPES REALLY MEET, or 1 and 2 pass vacuously — a
#      spell that never reacts satisfies both of them perfectly.
#
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice_test_reaction_registration.gd
#
# ⚠ NOTHING HERE NAMES A SPELL BY class_name, and the scripts are pulled in with
# `load()` at RUNTIME rather than `preload`. A `--script` tool is compiled before its
# own first frame, and naming a spectacle as a global class drags its whole
# dependency chain (Sfx, Juice, CombatVfx, PostProcess...) into that compile and
# kills the file with "Identifier not found". Same trap, same fix, as
# slice10_test_natural_reactions.gd and every capture tool in this project.
extends SceneTree

const CHAIN_PATH: String = "res://scripts/combat/ChainBolt.gd"
const RAY_PATH: String = "res://scripts/combat/DivineRay.gd"
const SHATTER_PATH: String = "res://scripts/combat/Shatter.gd"

## Where the "they are nowhere near each other" partner is parked. Far enough that no
## radius in the game reaches it, and NOT the origin — the origin is where the
## spectacle nodes themselves sit, so a bug that read transforms would place both
## sides there and the negative would pass for the wrong reason.
const FAR: Vector2 = Vector2(6000.0, 0.0)
## Where the real fight is staged. Deliberately far from (0, 0) for the same reason.
const HERE: Vector2 = Vector2(-1500.0, 240.0)
## DivineRay.SKY_HEIGHT, restated because this suite may not name the class.
const SKY_HEIGHT: float = 560.0

# ── Vacuous-pass armour (idiom copied from tools/slice_test_spell_buttons.gd) ──
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function and hands the caller the return type's zero. Under a
# `failed += _test_x()` idiom that reads as "zero failures", so a suite prints all
# PASS while silently skipping every assertion after the dead line. So failures
# accumulate on the MEMBER `_fails`, and every test's last line records that it
# reached the end; a test missing from `_completed` fails the suite BY ABSENCE.
const TESTS: Array[String] = [
	"contract_surface",
	"entry_points_join_the_reactor",
	"chain_bolt_supercharges_a_frost_field",
	"divine_ray_banishes_a_shadow_field",
	"shatter_is_void_charged",
	"published_shapes_are_world_space",
]

## The seven methods `SpellReactor` documents as the participant contract, minus the
## two it marks OPTIONAL there (`reaction_heading`, `reaction_freeze`).
const CONTRACT: Array[StringName] = [
	&"reaction_shape", &"reaction_active", &"reaction_element", &"reaction_form",
	&"reaction_owner", &"reaction_weight", &"reaction_consume",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _caster_a: Node = null
var _caster_b: Node = null


## A partner to react WITH. Duck-typed exactly like a real spectacle and, like every
## real one, parked at the origin with its geometry somewhere else entirely.
class ReactantStub extends Node2D:
	var shape: Dictionary = {}
	var form: int = 0
	var element: int = 0
	var consumed: int = 0
	var owner_of: Node = null

	func reaction_shape() -> Dictionary:
		return shape

	func reaction_active() -> bool:
		return true

	func reaction_element() -> int:
		return element

	func reaction_form() -> int:
		return form

	func reaction_owner() -> Node:
		return owner_of

	func reaction_weight() -> int:
		return SpellTier.Tier.HEAVY

	# Deliberately does NOT free itself, so consumptions can be counted.
	func reaction_consume() -> void:
		consumed += 1


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
	# Drive the sweep by hand rather than racing the 30 Hz timer, and keep the
	# spectacle seam OFF: it suppresses the PICTURE, never the match, the damage or
	# the consumption, which is exactly what lets the negatives below be asserted.
	reactor.set_process(false)
	reactor.set(&"spawn_effects", false)
	_caster_a = _named_node("CasterA")
	_caster_b = _named_node("CasterB")

	_test_contract_surface()
	_test_entry_points_join_the_reactor(reactor)
	_test_chain_bolt_supercharges_a_frost_field(reactor)
	_test_divine_ray_banishes_a_shadow_field(reactor)
	_test_shatter_is_void_charged(reactor)
	_test_published_shapes_are_world_space()

	_free_all([_caster_a, _caster_b])
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Reaction-registration tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Reaction-registration tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# --------------------------------------------------------------- the contract

## Every one of the three answers the whole participant contract, and answers it with
## the FORM it was adopted as. A missing method is never an error in Godot:
## `SpellReactor` duck-types the lot, so an effect that does not implement
## `reaction_active` is simply skipped in the activity sweep, silently and forever.
func _test_contract_surface() -> void:
	var F := ReactionTable.Form
	for row: Array in [
		[CHAIN_PATH, "ChainBolt", F.IMPACT],
		[RAY_PATH, "DivineRay", F.BEAM],
		[SHATTER_PATH, "Shatter", F.IMPACT],
	]:
		var path: String = String(row[0])
		var label: String = String(row[1])
		var want_form: int = int(row[2])
		var n: Node = _build(path)
		for m: StringName in CONTRACT:
			_expect(n.has_method(m), "%s implements %s()" % [label, m])
		_expect(n.has_method(&"_join_reactor"),
			"%s has a _join_reactor() — a contract nothing calls is not adopted" % label)
		_expect(int(n.call(&"reaction_form")) == want_form,
			"%s registers as form %d (got %d)"
				% [label, want_form, int(n.call(&"reaction_form"))])
		# THE TELEGRAPH GUARANTEE, on a freshly-built instance: nothing has landed
		# yet, so nothing may react yet. See the header's negative 1.
		_expect(not bool(n.call(&"reaction_active")),
			"%s is INERT before it has landed" % label)
		n.free()
	# ...and the Colossus Pillar, the second spell wearing the DivineRay costume, is
	# an IMPACT rather than a BEAM. Registering 300 px of erupting slate as a beam
	# would hand it BEAM x BARRIER's wildcard floor (`barrier_blocks`, consumes_a), so
	# a mountain would be swallowed by any wall it happened to come up beside.
	var stone: Node = _build(RAY_PATH)
	stone.set("_stone", true)
	_expect(int(stone.call(&"reaction_form")) == F.IMPACT,
		"the stone arm of DivineRay is an IMPACT, not a BEAM")
	stone.free()
	_completes("contract_surface")


## ⚠ THE ASSERTION THE REST OF THIS SUITE CANNOT MAKE, and the reason it is worth
## the awkwardness of running three real cast entries inside a headless tool.
##
## Every other test here reaches `_join_reactor()` directly, so all of them would
## still pass with the call sites DELETED out of `chain()`, `_whiff()`, `strike()`
## and `hex()` — the contract would be implemented, correct, and never invoked, which
## is exactly the state all three files were already in before this change. "A
## comment is not an implementation" and a method nothing calls is not an adoption.
##
## So this drives the SHIPPED entry points — the same functions `SpellCaster` calls,
## with the stamp order it uses (add_child, then the properties, then the entry) —
## and asserts the registry grew. It runs them for real: sigils open, bursts spawn,
## sounds play into the null audio driver. That is the price of the assertion.
##
## `chain()` is deliberately fired with nothing in the target group, so it takes the
## `_whiff()` branch: a bolt that ripped down your aim and hit nothing is still a live
## arc, that branch has its OWN registration call, and a suite that only ever
## exercised the connected path would not notice if it were dropped.
func _test_entry_points_join_the_reactor(reactor: Node) -> void:
	var E := Elements.Element
	var white := Color(1.0, 1.0, 1.0, 1.0)

	var bolt: Node = _build(CHAIN_PATH)
	bolt.set("element_id", E.LIGHTNING)
	bolt.set("caster_node", _caster_b)
	bolt.call(&"chain", HERE, Vector2.RIGHT, white, 4, 240.0, 44, "lightning")
	_expect(int(reactor.call(&"live_count")) == 1,
		"ChainBolt.chain() registers the arc — including on a whiff (live_count %d)"
			% int(reactor.call(&"live_count")))
	_drop(reactor, [bolt])

	var ray: Node = _build(RAY_PATH)
	ray.set("element_id", E.HOLY)
	ray.set("caster_node", _caster_b)
	ray.call(&"strike", HERE, white, 70.0, 95, "holy")
	_expect(int(reactor.call(&"live_count")) == 1,
		"DivineRay.strike() registers the pillar (live_count %d)"
			% int(reactor.call(&"live_count")))
	_drop(reactor, [ray])

	# ...and the stone arm, which takes a different exit out of the same function and
	# would be the easy one to forget.
	var spire: Node = _build(RAY_PATH)
	spire.set("element_id", E.EARTH)
	spire.set("caster_node", _caster_b)
	spire.call(&"strike", HERE, white, 70.0, 95, "holy")
	_expect(bool(spire.get("_stone")),
		"...and holy+EARTH really did fork into the Colossus Pillar")
	_expect(int(reactor.call(&"live_count")) == 1,
		"DivineRay.strike() registers the SPIRE too (live_count %d)"
			% int(reactor.call(&"live_count")))
	_drop(reactor, [spire])

	var brk: Node = _build(SHATTER_PATH)
	brk.set("element_id", E.ICE)
	brk.set("caster_node", _caster_b)
	# `spell` is nullable on this entry (`if spell != null:`), which keeps a SpellDef
	# — and the whole loadout layer — out of a suite that is about the reactor.
	brk.call(&"hex", _caster_b, HERE, HERE + Vector2(220.0, 0.0), null, white, "frost")
	_expect(int(reactor.call(&"live_count")) == 1,
		"Shatter.hex() registers the mark (live_count %d)"
			% int(reactor.call(&"live_count")))
	_drop(reactor, [brk])
	_completes("entry_points_join_the_reactor")


# ----------------------------------------------- the three, through the reactor

## THE ROW THIS WHOLE CHANGE WAS FOR. `ReactionTable`'s `supercharge` block says it
## in its own words: "the Stormcaller carries the Blizzard in its control slot and
## throws lightning all fight. Drop the field, shoot through it." It had been
## authored and unreachable, because the arc never entered the registry.
func _test_chain_bolt_supercharges_a_frost_field(reactor: Node) -> void:
	var bolt: Node = _build(CHAIN_PATH)
	bolt.set("element_id", Elements.Element.LIGHTNING)
	bolt.set("caster_node", _caster_b)
	# The arc, in WORLD space, exactly as `chain()` fills it: origin then strike.
	bolt.set("_points", PackedVector2Array([HERE, HERE + Vector2(300.0, 0.0)]))
	bolt.call(&"_join_reactor")
	var before: int = int(reactor.call(&"live_count"))
	_expect(before == 1, "the arc put ITSELF in the registry (live_count %d)" % before)

	# Negative 1 — registered, shaped, overlapping, and NOT YET FIRED. `_elapsed` is
	# still the pre-cast -1.0, so `reaction_active()` must refuse.
	var field: ReactantStub = _field(reactor, HERE + Vector2(150.0, 0.0),
		Elements.Element.ICE)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"an arc that has not discharged does not supercharge anything")
	# Negative 2 — live now, but the field is 7500 px away. Both nodes sit at (0, 0);
	# only the published shapes say otherwise.
	bolt.set("_elapsed", 0.0)
	field.shape = SpellGeometry.circle(FAR, 160.0)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"...nor does one whose field is on the other side of the world")
	# ...and it DOES fire once the two really share space.
	field.shape = SpellGeometry.circle(HERE + Vector2(150.0, 0.0), 160.0)
	_expect(int(reactor.call(&"resolve_now")) == 1,
		"a live lightning arc through a frost field SUPERCHARGES")
	# The row spends nothing on either side, deliberately (see the two ⚠ blocks on
	# `supercharge` in ReactionTable): the ice is the conductor, not the victim.
	_expect(field.consumed == 0, "...and the field is still standing")
	_drop(reactor, [field, bolt])
	_completes("chain_bolt_supercharges_a_frost_field")


## The row `ReactionTable` wrote a note about instead of a spell: "The BEAM row is
## unreachable TODAY (no holy beam implements the participant contract yet —
## Judgment is a DIVINE_RAY whose spectacle has not adopted it)."
func _test_divine_ray_banishes_a_shadow_field(reactor: Node) -> void:
	var ray: Node = _build(RAY_PATH)
	ray.set("element_id", Elements.Element.HOLY)
	ray.set("caster_node", _caster_b)
	ray.set("_ground", HERE)
	ray.set("_radius", 70.0)
	ray.call(&"_join_reactor")
	_expect(int(reactor.call(&"live_count")) == 1,
		"the pillar put ITSELF in the registry")

	# Negative 1 — the tell. Judgment hangs a motionless thread for CHARGE_TIME and
	# the whole spell is "dodge the tell or take the hit"; a pillar that banished the
	# field during its own charge would show the payoff before the attack.
	var field: ReactantStub = _field(reactor, HERE + Vector2(0.0, -60.0),
		Elements.Element.SHADOW)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"a pillar still in its telegraph banishes nothing")
	# Negative 2 — struck, but nowhere near.
	ray.set("_struck", true)
	field.shape = SpellGeometry.circle(FAR, 160.0)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"...nor does one whose field is 6000 px away")
	# ...and light really does unmake the dark.
	field.shape = SpellGeometry.circle(HERE + Vector2(0.0, -60.0), 160.0)
	_expect(int(reactor.call(&"resolve_now")) == 1,
		"a holy pillar falling through a shadow field BANISHES it")
	_expect(field.consumed == 1, "...and the field is unmade")
	_drop(reactor, [field, ray])
	_completes("divine_ray_banishes_a_shadow_field")


## The Cryomancer's whole damage output, which had no presence in the matrix at all.
## `void_charged` is chosen for the positive because it is the one row reachable here
## that spends NEITHER side, so the assertion is about the match and not a teardown.
func _test_shatter_is_void_charged(reactor: Node) -> void:
	var brk: Node = _build(SHATTER_PATH)
	brk.set("element_id", Elements.Element.ICE)
	brk.set("caster_node", _caster_b)
	brk.set("_at", HERE)
	brk.set("_radius", 104.0)
	brk.call(&"_join_reactor")
	_expect(int(reactor.call(&"live_count")) == 1,
		"the break put ITSELF in the registry")

	# Negative 1 — the fuse. Seventeen frames of drawn warning, and the mark must do
	# nothing for all of them.
	var field: ReactantStub = _field(reactor, HERE, Elements.Element.SHADOW)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"a mark still on its fuse reacts with nothing")
	# Negative 2 — broken, and far away.
	brk.set("_broken", true)
	field.shape = SpellGeometry.circle(FAR, 160.0)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"...nor does a break whose field is elsewhere")
	field.shape = SpellGeometry.circle(HERE, 160.0)
	_expect(int(reactor.call(&"resolve_now")) == 1,
		"a break inside a void field is VOID-CHARGED")
	_drop(reactor, [field, brk])
	_completes("shatter_is_void_charged")


# ---------------------------------------------------------------- the geometry

## THE TRAP, ASSERTED DIRECTLY. Every one of these three parks its node at the arena
## origin and draws in world coordinates, so `global_position` is (0, 0) and is NOT
## where the effect is. A `reaction_shape()` that read the transform would be
## invisible to the tests above — those place the partner where the shape SAYS the
## effect is, and if both sides answered (0, 0) they would overlap there and pass.
func _test_published_shapes_are_world_space() -> void:
	var bolt: Node = _build(CHAIN_PATH)
	var tip: Vector2 = HERE + Vector2(300.0, 0.0)
	bolt.set("_points", PackedVector2Array([HERE, tip, HERE + Vector2(40.0, 400.0)]))
	var s: Dictionary = bolt.call(&"reaction_shape")
	_expect(String(s.get("shape", "")) == "line", "the arc publishes a capsule")
	_expect((s.get("from", Vector2.ZERO) as Vector2).is_equal_approx(HERE)
			and (s.get("to", Vector2.ZERO) as Vector2).is_equal_approx(tip),
		"...spanning the FIRST link — the one the player aimed — rather than the "
		+ "fold back toward the caster that a whole-chain capsule would cover "
		+ "instead (got %s -> %s)" % [str(s.get("from")), str(s.get("to"))])
	_expect((bolt.get("global_position") as Vector2) == Vector2.ZERO,
		"...while the NODE itself is still parked at the origin")
	bolt.free()

	var ray: Node = _build(RAY_PATH)
	ray.set("_ground", HERE)
	ray.set("_radius", 70.0)
	var r: Dictionary = ray.call(&"reaction_shape")
	_expect((r.get("to", Vector2.ZERO) as Vector2).is_equal_approx(HERE),
		"the pillar's capsule ends on the marked ground")
	_expect(absf((r.get("from", Vector2.ZERO) as Vector2).y - (HERE.y - SKY_HEIGHT)) < 0.5,
		"...and starts SKY_HEIGHT above it, which is the corridor _smite() damages")
	ray.free()

	var brk: Node = _build(SHATTER_PATH)
	brk.set("_at", HERE)
	brk.set("_radius", 104.0)
	var b: Dictionary = brk.call(&"reaction_shape")
	_expect(String(b.get("shape", "")) == "circle", "the break publishes a circle")
	_expect((b.get("center", Vector2.ZERO) as Vector2).is_equal_approx(HERE)
			and absf(float(b.get("radius", 0.0)) - 104.0) < 0.5,
		"...at the mark, at the drawn footprint radius")
	brk.free()
	_completes("published_shapes_are_world_space")


# ------------------------------------------------------------------- fixtures

## Built the way `SpellCaster` builds one — `load()` at runtime, never `preload` and
## never by class_name (see the ⚠ in the header) — then parked at the origin exactly
## as the real spawn does. Processing is off and it is hidden: this suite drives the
## reactor by hand, and a spectacle running its own `_process` would age itself past
## its life and free out from under the assertions.
func _build(path: String) -> Node:
	var n: Node2D = (load(path) as GDScript).new() as Node2D
	n.set_process(false)
	n.visible = false
	root.add_child(n)
	n.global_position = Vector2.ZERO
	return n


func _named_node(n: String) -> Node:
	var c := Node2D.new()
	c.name = n
	root.add_child(c)
	return c


func _field(reactor: Node, at: Vector2, element: int) -> ReactantStub:
	var s := ReactantStub.new()
	root.add_child(s)
	s.global_position = Vector2.ZERO   # parked at the origin, like every real one
	s.form = ReactionTable.Form.FIELD
	s.element = element
	s.shape = SpellGeometry.circle(at, 160.0)
	s.owner_of = _caster_a
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
