# THE REACTIONS A REAL FIGHT CAN REACH — the rows added because a COUNT said the
# authored ones could not fire, plus the guard on the lookup that made them cheap.
#
# WHY THIS SUITE EXISTS AT ALL. `tools/probe_reaction_count.gd` ran 36 real bot
# bouts and counted every reaction that fired: 12 reactions, 6 of 21 authored
# outcomes, 0.33 per bout. `supercharge` and `banish` were both ZERO — and the
# reactor's registration tally said why. Over those bouts lightning entered the
# reaction system ONLY as a PROJECTILE (12 casts, 9.8 s live) and holy only as a
# BARRIER, a FIELD and a PROJECTILE, while every row written for those two pairs
# asks for a BEAM or an IMPACT. A holy blast is reachable on paper and did not
# happen once; a lightning beam cannot happen at all. The rows were written for
# the shapes those elements almost never take.
#
# So this proves three separate things, and the third is the one that would
# otherwise fail invisibly:
#
#   1. THE NEW ROWS RESOLVE, at the priority they were authored at, both ways round.
#   2. THEY FIRE END TO END through the reactor, spending the side the row names
#      and NOT the side it does not — and they stay silent when the two effects are
#      not actually touching.
#   3. THE BUCKET INDEX IS FAITHFUL. `ReactionTable.match_rule` no longer rebuilds
#      all 21 authored rows per pair test; it reads a cached per-bucket index. That
#      is a 19x cost win and it introduces exactly one new way to be wrong — the
#      rows are now SHARED, so stamping `swapped` into a winner in place would
#      leave the next lookup carrying the previous caller's orientation, and
#      `consumes_caller` reads that flag to decide which spell gets eaten. Both the
#      faithfulness and the leak are asserted below.
#
#   Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#       --script tools/slice_test_reaction_reach.gd
#
# ⚠ NAMES NO SPECTACLE BY class_name. A `--script` tool is compiled BEFORE the
# autoloads exist and every spectacle in this family reaches `Sfx`, so naming one
# kills the whole file with "Identifier not found: Sfx". Same trap and same fix as
# slice10_test_natural_reactions.gd; the stubs below are duck-typed.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function and hands the caller the return type's zero. Under
# `failed += _test_x()` that reads as "zero failures". So failures accumulate on the
# MEMBER `_fails`, and every test records that it reached its own last line; a test
# that aborted part-way is missing from `_completed` and fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"bucket_index_matches_a_full_scan",
	"swapped_does_not_leak_between_lookups",
	"lightning_bolt_supercharges_frost",
	"holy_banishes_shadow_in_the_shapes_holy_takes",
	"nothing_was_stolen",
	"supercharge_through_the_reactor",
	"banish_through_the_reactor",
	"reach_negative_bolt_outside_the_field",
	"the_element_read_is_actually_drawn",
]

## Full width a barrier stub publishes, matching what IceWall / RockWall / AegisWard
## do (`REACTION_HALF_WIDTH * 2`). Half of it is the capsule radius.
const BARRIER_WIDTH: float = 44.0
const BARRIER_HEIGHT: float = 132.0
## A control field's footprint, in the band ZoneSpell and ShadowRoot draw at.
const FIELD_RADIUS: float = 110.0
## A bolt is a short swept segment, which is exactly what `Spell.reaction_shape`
## publishes — the segment travelled since the last frame, not a point.
const BOLT_WIDTH: float = 24.0

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _caster_a: Node = null
var _caster_b: Node = null
## Where staged spectacle nodes land, so the element-read test can count them.
var _stage: Node = null


## Duck-typed exactly like a real spectacle, and PARKED AT THE ORIGIN with its
## geometry living somewhere else — every real spell effect draws in world
## coordinates from a node at (0,0), and a reactor that read a transform would
## report every pair as touching at the top-left of the arena.
class ReactantStub extends Node2D:
	var shape: Dictionary = {}
	var active: bool = true
	var form: int = 0
	var element: int = 0
	var weight: int = SpellTier.Tier.HEAVY
	var owner_node: Node = null
	var consumed: int = 0

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

	func reaction_owner() -> Node:
		return owner_node

	# Deliberately does NOT free itself, so the test can count consumptions and
	# still read the node afterwards.
	func reaction_consume() -> void:
		consumed += 1


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return true


func _run() -> void:
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("FAIL: SpellReactor autoload is missing")
		quit(1)
		return
	# Hand-drive the sweep rather than racing the 30 Hz timer.
	reactor.set_process(false)
	reactor.set(&"spawn_effects", false)
	_caster_a = _named_node("CasterA")
	_caster_b = _named_node("CasterB")
	_stage = _named_node("Stage")

	_test_bucket_index_matches_a_full_scan()
	_test_swapped_does_not_leak_between_lookups()
	_test_lightning_bolt_supercharges_frost()
	_test_holy_banishes_shadow_in_the_shapes_holy_takes()
	_test_nothing_was_stolen()
	_test_supercharge_through_the_reactor(reactor)
	_test_banish_through_the_reactor(reactor)
	_test_reach_negative_bolt_outside_the_field(reactor)
	_test_the_element_read_is_actually_drawn(reactor)

	for n: Node in [_caster_a, _caster_b, _stage]:
		if is_instance_valid(n):
			n.free()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Reaction reach tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Reaction reach tests: all PASS")
		quit(0)


# ------------------------------------------------ the bucket index is faithful

## THE GUARD ON THE OPTIMISATION. `match_rule` used to scan a freshly-built
## `rules()` on every call; it now reads a cached per-bucket index. This walks the
## ENTIRE input space the table is defined over — every ordered form pair, every
## ordered element pair, three owner relations and three weight pairings — and
## compares the indexed answer against a reference scan written here, in this file,
## over `rules()`.
##
## The reference is deliberately a SECOND IMPLEMENTATION rather than a call into
## the thing under test. A guard that asks the optimised path to check itself is
## not a guard.
func _test_bucket_index_matches_a_full_scan() -> void:
	var forms: int = ReactionTable.Form.size()
	var elements: int = Elements.Element.size()
	var rels: Array[String] = ["same", "different", "unowned"]
	var weights: Array[Vector2i] = [
		Vector2i(SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY),
		Vector2i(SpellTier.Tier.ULT, SpellTier.Tier.QUICK),
		Vector2i(SpellTier.Tier.QUICK, SpellTier.Tier.ULT),
	]
	var checked: int = 0
	var mismatches: int = 0
	for fa: int in forms:
		for fb: int in forms:
			for ea: int in elements:
				for eb: int in elements:
					for rel: String in rels:
						for w: Vector2i in weights:
							var got: Dictionary = ReactionTable.match_rule(
								fa, ea, fb, eb, rel, w.x, w.y,
								Vector2.RIGHT, Vector2.LEFT)
							var want: Dictionary = _reference_match(
								fa, ea, fb, eb, rel, w.x, w.y,
								Vector2.RIGHT, Vector2.LEFT)
							checked += 1
							if String(got.get("outcome", "")) != String(want.get("outcome", "")) \
									or int(got.get("priority", -1)) != int(want.get("priority", -1)) \
									or bool(got.get("swapped", false)) != bool(want.get("swapped", false)):
								mismatches += 1
	# 6 forms x 6 forms x 8 elements x 8 elements x 3 owner relations x 3 weight
	# pairings = 20,736. Asserted rather than assumed: a loop bound that quietly
	# collapses to nothing is the classic way a sweep passes while checking one case.
	_expect(checked == 20736,
		"the sweep actually covered the input space (%d lookups, wanted 20736)" % checked)
	_expect(mismatches == 0,
		"the bucket index agrees with a full scan on every input (%d mismatches of %d)"
			% [mismatches, checked])
	_completes("bucket_index_matches_a_full_scan")


## `match_rule` as it was written before the index: build every authored row fresh,
## scan the lot, keep the highest-priority match. Kept deliberately naive.
func _reference_match(form_a: int, element_a: int, form_b: int, element_b: int,
		owner_rel: String, weight_a: int, weight_b: int,
		heading_a: Vector2, heading_b: Vector2) -> Dictionary:
	var key: int = ReactionTable.bucket_key(form_a, form_b)
	var best: Dictionary = {}
	for r: Dictionary in ReactionTable.rules():
		if ReactionTable.bucket_key(int(r["form_a"]), int(r["form_b"])) != key:
			continue
		var swapped: bool = false
		if ReactionTable._sides_match(r, form_a, element_a, form_b, element_b,
				owner_rel, weight_a, weight_b, heading_a, heading_b):
			swapped = false
		elif ReactionTable._sides_match(r, form_b, element_b, form_a, element_a,
				owner_rel, weight_b, weight_a, heading_b, heading_a):
			swapped = true
		else:
			continue
		if best.is_empty() or int(r["priority"]) > int(best["priority"]):
			r["swapped"] = swapped
			best = r
	if not best.is_empty() and bool(best.get("suppress", false)):
		return {}
	return best


## THE ONE NEW WAY TO BE WRONG that the index introduced. The rows are shared now,
## so a `swapped` flag written into the winner IN PLACE would survive into the next
## lookup of that same row — and `consumes_caller` reads exactly that flag to decide
## which of the two spells gets eaten. The bug would be a spell surviving something
## that should have consumed it, INTERMITTENTLY, depending on which way round the
## previous unrelated pair happened to match.
##
## `shatter_ice_barrier` is the row used because it is asymmetric in both the ways
## that matter: its two sides are different forms AND it consumes only one of them.
func _test_swapped_does_not_leak_between_lookups() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	# The row is authored fire-beam-first, so handing the WALL over first matches it
	# with the sides reversed.
	var reversed: Dictionary = ReactionTable.match_rule(
		F.BARRIER, E.ICE, F.BEAM, E.FIRE, "different",
		SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(String(reversed.get("outcome", "")) == "shatter_ice_barrier",
		"an ice wall seen before the fire beam still resolves to shatter_ice_barrier")
	_expect(bool(reversed.get("swapped", false)),
		"...and reports that it matched with its sides reversed")
	# The caller's side 1 is the BEAM here, side 0 the WALL, so the WALL (side 0)
	# is what must be spent.
	_expect(ReactionTable.consumes_caller(reversed, 0),
		"the reversed match spends the caller's side 0 — the wall")
	_expect(not ReactionTable.consumes_caller(reversed, 1),
		"...and not the beam")

	# A lookup the other way round, which must not disturb the first.
	var forward: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.FIRE, F.BARRIER, E.ICE, "different",
		SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(not bool(forward.get("swapped", true)),
		"the forward match reports sides in the authored order")
	_expect(ReactionTable.consumes_caller(forward, 1),
		"the forward match spends the caller's side 1 — the wall")

	# ⚠ THE ASSERTION, AND ITS ORDER IS LOAD-BEARING. This must be read IMMEDIATELY
	# after the forward lookup and BEFORE any further one. The first version of this
	# test asked for the reversed orientation a third time first, which set the
	# shared flag back to `true` — so with the bug deliberately reintroduced (stamp
	# the winner in place instead of duplicating it) the suite still passed. Proven
	# by reverting the fix and running: it printed all PASS, which is exactly the
	# vacuous guard this repo has been bitten by before. Read the STALE handle while
	# the other orientation is the most recent one, or this proves nothing.
	_expect(bool(reversed.get("swapped", false)),
		"the dictionary handed out EARLIER was not rewritten by the later lookup")
	_expect(ReactionTable.consumes_caller(reversed, 0),
		"...so it still says to spend the WALL, not the beam — which is the bug "
		+ "this guards: a spell surviving what should have eaten it, intermittently, "
		+ "depending on which way round some unrelated pair matched last")

	# ...and asking for it again still answers correctly, which is the half that
	# would keep working even with the bug and is therefore not the assertion.
	var again: Dictionary = ReactionTable.match_rule(
		F.BARRIER, E.ICE, F.BEAM, E.FIRE, "different",
		SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(bool(again.get("swapped", false)),
		"the reversed orientation is still reported after a forward lookup")
	_completes("swapped_does_not_leak_between_lookups")


# ----------------------------------------------------------- the new rows

## LIGHTNING INTO FROST, THROWN — the row `supercharge` needed to be a reaction
## anyone has ever seen. Measured: lightning enters the reactor only as a
## PROJECTILE, so the authored BEAM and IMPACT arms could never fire.
func _test_lightning_bolt_supercharges_frost() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	_assert_rule("a lightning bolt crossing a blizzard", "supercharge", 71,
		F.PROJECTILE, E.LIGHTNING, F.FIELD, E.ICE)
	var r: Dictionary = ReactionTable.match_rule(
		F.PROJECTILE, E.LIGHTNING, F.FIELD, E.ICE, "different",
		SpellTier.Tier.QUICK, SpellTier.Tier.HEAVY)
	# The row spends the BOLT and keeps the FIELD. Both halves matter: the spend is
	# the rate limiter on the highest-traffic reactant in the game, and keeping the
	# field is what stops a free basic cast deleting a heavy control spell.
	_expect(ReactionTable.consumes_caller(r, 0), "the bolt is spent conducting")
	_expect(not ReactionTable.consumes_caller(r, 1), "the frost field keeps standing")
	# The SAME caster's own bolt through their own field must work — the Stormcaller
	# carries the Blizzard, and that self-combo is the whole set-up.
	var mine: Dictionary = ReactionTable.match_rule(
		F.PROJECTILE, E.LIGHTNING, F.FIELD, E.ICE, "same",
		SpellTier.Tier.QUICK, SpellTier.Tier.HEAVY)
	_expect(String(mine.get("outcome", "")) == "supercharge",
		"a caster shooting through their OWN blizzard supercharges it")
	# ...and no other element does. A fire bolt is a different sentence entirely and
	# a wildcard here would have made the row meaningless.
	var wrong: Dictionary = ReactionTable.match_rule(
		F.PROJECTILE, E.ARCANE, F.FIELD, E.ICE, "different",
		SpellTier.Tier.QUICK, SpellTier.Tier.HEAVY)
	_expect(wrong.is_empty(), "an arcane bolt through frost is still silent")
	_completes("lightning_bolt_supercharges_frost")


## HOLY vs SHADOW, in the two shapes holy actually takes. The table's own holy /
## shadow block promises that "a player who has seen one holy/shadow meeting can
## predict the rest without being told"; measured, it could not keep that promise
## once, because the Cleric's three light spells never register at all and the only
## shapes holy takes are BARRIER (the ward) and FIELD.
func _test_holy_banishes_shadow_in_the_shapes_holy_takes() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	_assert_rule("a consecrated field over a void zone", "banish", 77,
		F.FIELD, E.HOLY, F.FIELD, E.SHADOW)
	_assert_rule("an aegis ward standing in a void zone", "banish", 76,
		F.BARRIER, E.HOLY, F.FIELD, E.SHADOW)
	# Both spend the DARK and nothing else — banish is an erasure, not a trade.
	for pair: Array in [[F.FIELD, 77], [F.BARRIER, 76]]:
		var r: Dictionary = ReactionTable.match_rule(
			int(pair[0]), E.HOLY, F.FIELD, E.SHADOW, "different",
			SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
		_expect(ReactionTable.consumes_caller(r, 1), "the void field is unmade")
		_expect(not ReactionTable.consumes_caller(r, 0), "the light is not spent doing it")
	# ⚠ STILL NO PROJECTILE TWIN. A holy basic cast is free and spammable, and the
	# documented rule is that a field is answered by things that FILL a volume.
	var bolt: Dictionary = ReactionTable.match_rule(
		F.PROJECTILE, E.HOLY, F.FIELD, E.SHADOW, "different",
		SpellTier.Tier.QUICK, SpellTier.Tier.HEAVY)
	_expect(bolt.is_empty(),
		"a holy BOLT still cannot erase a void field (got `%s`)"
			% String(bolt.get("outcome", "")))
	_completes("holy_banishes_shadow_in_the_shapes_holy_takes")


## THE ROWS ABOVE SHARE BUCKETS WITH ROWS THAT ALREADY EXISTED, and a row slipped
## above a headline reaction stops that reaction firing with no error anywhere. So
## every neighbour is asserted by NAME AND PRIORITY — the only assertion that
## catches a row inserted one point too high.
func _test_nothing_was_stolen() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	# FIELD x FIELD: the new banish must not have displaced same-element merging.
	_assert_rule("two frost fields overlapping", "field_merge", 50,
		F.FIELD, E.ICE, F.FIELD, E.ICE, "different")
	# PROJECTILE x FIELD was an EMPTY bucket before the bolt row, so nothing there
	# could be stolen — but the neighbouring FIELD rows must be untouched.
	_assert_rule("a lightning BEAM in a frost field", "supercharge", 75,
		F.BEAM, E.LIGHTNING, F.FIELD, E.ICE)
	_assert_rule("a lightning BLAST in a frost field", "supercharge", 73,
		F.IMPACT, E.LIGHTNING, F.FIELD, E.ICE)
	_assert_rule("a holy BLAST over a void field", "banish", 79,
		F.IMPACT, E.HOLY, F.FIELD, E.SHADOW)
	_assert_rule("any blast inside a void field", "void_charged", 70,
		F.IMPACT, E.EARTH, F.FIELD, E.SHADOW)
	_assert_rule("fire boiling a frost field", "steam_cloud", 78,
		F.IMPACT, E.FIRE, F.FIELD, E.ICE)
	# BARRIER x FIELD was empty before the ward row. An ordinary stone wall standing
	# in a void field must still be silent — the row is about LIGHT, not about walls.
	var stone: Dictionary = ReactionTable.match_rule(
		F.BARRIER, E.EARTH, F.FIELD, E.SHADOW, "different",
		SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(stone.is_empty(),
		"a stone wall in a void field is still silent (got `%s`)"
			% String(stone.get("outcome", "")))
	_completes("nothing_was_stolen")


# -------------------------------------------------------- through the reactor

func _test_supercharge_through_the_reactor(reactor: Node) -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var at: Vector2 = Vector2(900.0, 400.0)
	var field: ReactantStub = _stub(F.FIELD, E.ICE, _caster_a,
		SpellGeometry.circle(at, FIELD_RADIUS), SpellTier.Tier.HEAVY)
	# The swept segment a bolt publishes, crossing the middle of the field.
	var bolt: ReactantStub = _stub(F.PROJECTILE, E.LIGHTNING, _caster_b,
		SpellGeometry.capsule(at + Vector2(-30.0, 0.0), at + Vector2(30.0, 0.0),
			BOLT_WIDTH), SpellTier.Tier.QUICK)
	var seen: Array[String] = _collect(reactor, [field, bolt])
	_expect(seen.has("supercharge"),
		"a lightning bolt inside a frost field supercharges it (saw %s)" % str(seen))
	_expect(bolt.consumed == 1, "the bolt was spent (consumed %d)" % bolt.consumed)
	_expect(field.consumed == 0,
		"the frost field kept standing (consumed %d)" % field.consumed)
	_free_all([field, bolt])
	_completes("supercharge_through_the_reactor")


func _test_banish_through_the_reactor(reactor: Node) -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var at: Vector2 = Vector2(1400.0, 600.0)
	var void_field: ReactantStub = _stub(F.FIELD, E.SHADOW, _caster_a,
		SpellGeometry.circle(at, FIELD_RADIUS), SpellTier.Tier.HEAVY)
	var ward: ReactantStub = _stub(F.BARRIER, E.HOLY, _caster_b,
		SpellGeometry.capsule(at + Vector2(0.0, BARRIER_HEIGHT * 0.5),
			at - Vector2(0.0, BARRIER_HEIGHT * 0.5), BARRIER_WIDTH),
		SpellTier.Tier.HEAVY)
	var seen: Array[String] = _collect(reactor, [void_field, ward])
	_expect(seen.has("banish"),
		"an aegis ward standing in a void field banishes it (saw %s)" % str(seen))
	_expect(void_field.consumed == 1,
		"the void field was unmade (consumed %d)" % void_field.consumed)
	_expect(ward.consumed == 0,
		"the ward was not spent doing it (consumed %d)" % ward.consumed)
	_free_all([void_field, ward])
	_completes("banish_through_the_reactor")


## THE REACH NEGATIVE, and it is the assertion that stops the row above being a
## vacuous pass. A rule that matched would fire on any two live effects if the
## geometry stage were broken, and every one of these stubs is parked at the origin
## — so a reactor reading transforms would report them as touching.
func _test_reach_negative_bolt_outside_the_field(reactor: Node) -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var at: Vector2 = Vector2(2000.0, 300.0)
	var field: ReactantStub = _stub(F.FIELD, E.ICE, _caster_a,
		SpellGeometry.circle(at, FIELD_RADIUS), SpellTier.Tier.HEAVY)
	# Well outside the field's own radius, and nowhere near the origin either.
	var far: Vector2 = at + Vector2(FIELD_RADIUS * 4.0, 0.0)
	var bolt: ReactantStub = _stub(F.PROJECTILE, E.LIGHTNING, _caster_b,
		SpellGeometry.capsule(far, far + Vector2(60.0, 0.0), BOLT_WIDTH),
		SpellTier.Tier.QUICK)
	var seen: Array[String] = _collect(reactor, [field, bolt])
	_expect(seen.is_empty(),
		"a bolt passing WIDE of the field does nothing (saw %s)" % str(seen))
	_expect(bolt.consumed == 0, "...and is not spent")
	_free_all([field, bolt])
	_completes("reach_negative_bolt_outside_the_field")


# ------------------------------------------------------------------ the read

## A REACTION THAT FIRES INVISIBLY IS THE SAME AS ONE THAT DOES NOT FIRE. Every
## outcome in `ReactionOutcomes` drew exactly one thing — a particle spray tinted
## by the LERP of the two element colours — so fire meeting ice and shadow meeting
## earth were the same picture in a different hue, and a lerp of two hues is often
## a third colour belonging to neither. `ElementFx` already draws each element's own
## signature and was used by eleven spell impacts and by NO reaction at all.
##
## This asserts the signatures are really staged, by counting the nodes that appear
## — not by trusting a counter the same code increments.
func _test_the_element_read_is_actually_drawn(reactor: Node) -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	# The picture is what is under test, so the spectacle seam comes ON for this
	# one test and goes off again afterwards.
	reactor.set(&"spawn_effects", true)
	var at: Vector2 = Vector2(2600.0, 900.0)
	var field: ReactantStub = _stub(F.FIELD, E.ICE, _caster_a,
		SpellGeometry.circle(at, FIELD_RADIUS), SpellTier.Tier.HEAVY)
	var bolt: ReactantStub = _stub(F.PROJECTILE, E.LIGHTNING, _caster_b,
		SpellGeometry.capsule(at + Vector2(-30.0, 0.0), at + Vector2(30.0, 0.0),
			BOLT_WIDTH), SpellTier.Tier.QUICK)
	# Both stubs are parented to the same staging node, which is what
	# `ReactionOutcomes._stage_parent` hands the spectacle.
	var before: int = _element_fx_children()
	var seen: Array[String] = _collect(reactor, [field, bolt])
	var after: int = _element_fx_children()
	reactor.set(&"spawn_effects", false)
	_expect(seen.has("supercharge"), "the reaction fired with the picture on")
	_expect(after - before >= 2,
		"BOTH elements' signatures were drawn (%d ElementFx nodes appeared, wanted 2)"
			% [after - before])
	_free_all([field, bolt])
	_completes("the_element_read_is_actually_drawn")


## Live `ElementFx` nodes under the staging parent, counted by SCRIPT rather than by
## class_name — see the ⚠ at the top of the file.
func _element_fx_children() -> int:
	var n: int = 0
	for c: Node in _stage.get_children():
		var s: Script = c.get_script() as Script
		if s != null and s.resource_path.ends_with("ElementFx.gd"):
			n += 1
	return n


# ------------------------------------------------------------------ helpers

func _assert_rule(label: String, expect_outcome: String, expect_priority: int,
		form_a: int, element_a: int, form_b: int, element_b: int,
		owner_rel: String = "different") -> void:
	var r: Dictionary = ReactionTable.match_rule(form_a, element_a, form_b, element_b,
		owner_rel, SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(String(r.get("outcome", "")) == expect_outcome,
		"%s resolves to `%s` (got `%s`)" % [label, expect_outcome, String(r.get("outcome", ""))])
	_expect(int(r.get("priority", -1)) == expect_priority,
		"%s wins at priority %d — nothing was slipped above it (got %d)"
			% [label, expect_priority, int(r.get("priority", -1))])
	# ...and the same the other way round. A row that only resolves one way is a row
	# that is silently absent half the time.
	var swapped: Dictionary = ReactionTable.match_rule(form_b, element_b, form_a, element_a,
		owner_rel, SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(String(swapped.get("outcome", "")) == expect_outcome,
		"%s matches with the sides swapped too" % label)


## Register the given stubs, drive ONE resolution sweep, and report the outcomes
## the reactor emitted. Everything is unregistered again afterwards so tests cannot
## leak reactants into each other.
func _collect(reactor: Node, stubs: Array) -> Array[String]:
	var seen: Array[String] = []
	var sink: Callable = func(outcome: String, _p: Vector2, _a: Node, _b: Node) -> void:
		seen.append(outcome)
	reactor.connect(&"reaction_fired", sink)
	for s: Node in stubs:
		reactor.call(&"register", s, s.get("form"), s.get("element"))
	reactor.call(&"resolve_now")
	for s: Node in stubs:
		reactor.call(&"unregister", s)
	reactor.disconnect(&"reaction_fired", sink)
	return seen


func _stub(form: int, element: int, owner_node: Node, shape: Dictionary,
		weight: int) -> ReactantStub:
	var s: ReactantStub = ReactantStub.new()
	s.form = form
	s.element = element
	s.owner_node = owner_node
	s.shape = shape
	s.weight = weight
	_stage.add_child(s)
	return s


func _named_node(n: String) -> Node:
	var node: Node = Node2D.new()
	node.name = n
	root.add_child(node)
	return node


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.free()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: ", what)


func _completes(name: String) -> void:
	_completed[name] = true
