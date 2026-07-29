# THE NATURAL-INTERACTION MATRIX. The maker's ask was "cool interactions when
# certain spells collide — a fireball or thunder to an ice wall etc. All those
# interactions should be natural based on the spells and how they hit each other.
# HOLY VS SHADOW for example", and earlier: "use common sense for how they
# interact."
#
# Five rows were added to ReactionTable for that, plus one new outcome (`banish`).
# This suite proves three separate things, and the SECOND is the one that would
# otherwise fail invisibly:
#
#   1. THE NEW ROWS FIRE where they are supposed to, end to end through the
#      reactor — not just "the table matches" but "the payoff happened, inside the
#      radius it was drawn at, and NOT outside it".
#   2. NOTHING WAS STOLEN. Every added row shares a bucket with rows that already
#      existed, and a row slipped above a headline reaction stops that reaction
#      firing with no error anywhere — Hollow Purple would simply never happen
#      again and no suite would say so. So every pre-existing outcome is asserted
#      by NAME AND PRIORITY, which is the only assertion that catches a row
#      inserted one point too high.
#   3. THE DELIBERATE SILENCES SURVIVE. Two barriers merely touching is a
#      documented decision, not a gap, and the ram row must not have turned it into
#      one.
#
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice10_test_natural_reactions.gd
#
# ⚠ NOTHING HERE NAMES A SPECTACLE BY class_name. A `--script` tool is COMPILED
# BEFORE THE AUTOLOADS EXIST, and every spectacle in this family reaches `Sfx` — so
# naming one as a global class kills the whole file with "Identifier not found:
# Sfx". Same trap and same fix as slice9_test_wards.gd and slice_test_wall_reactions.gd.
# This suite needs no spectacle at all: it drives duck-typed stubs, which is also
# what lets it assert reach negatives that a real spell would make awkward.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so a suite prints all PASS while silently
# skipping every assertion after the dead line. Static typing does not help — a
# typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"ladder_unstolen",
	"new_rows_share_old_buckets",
	"banish_rows",
	"holy_shadow_is_asymmetric",
	"ward_answers_every_shadow_shape",
	"the_ram",
	"ordinary_barriers_stay_silent",
	"supercharge_reaches_blasts",
	"banish_through_the_reactor",
	"ram_through_the_reactor",
	"shadow_blast_pops_the_ward",
	"origin_parked_holds_for_the_new_rows",
]

## Long enough that a capsule stub reads as a real beam rather than a graze.
const BEAM_LEN: float = 900.0
## Full width handed to SpellGeometry.capsule for a barrier, matching what IceWall
## and RockWall publish (`REACTION_HALF_WIDTH * 2`). Half of it is the radius, so
## two barriers overlap when their bases are closer than this.
const BARRIER_WIDTH: float = 44.0
## How tall a barrier stub stands. Between IceWall's collider and AegisWard's pane.
const BARRIER_HEIGHT: float = 132.0

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _caster_a: Node = null
var _caster_b: Node = null


# ---------------------------------------------------------------------- stubs

## A live effect, duck-typed exactly like a real spectacle — and, like every real
## spectacle, PARKED AT THE ORIGIN with its geometry living somewhere else
## entirely. Copied in shape from tools/slice9_test_wards.gd rather than shared:
## a stub shared between suites is a stub that gets tuned for one of them and
## quietly stops proving what the other one thinks it proves.
class ReactantStub extends Node2D:
	var shape: Dictionary = {}
	var active: bool = true
	var form: int = 0
	var element: int = 0
	var weight: int = SpellTier.Tier.HEAVY
	var owner_node: Node = null
	var consumed: int = 0
	var frozen: int = 0
	var absorbed: int = 0
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
		frozen += 1

	func reaction_absorb(_at: Vector2) -> void:
		absorbed += 1

	func take_damage(amount: int) -> void:
		damaged += amount

	# Deliberately does NOT free itself, so the suite can count consumptions.
	func reaction_consume() -> void:
		consumed += 1


## Something a reaction can hurt. In group "enemy" so ReactionOutcomes.HURT_GROUPS
## finds it, with the three duck-typed hooks every spectacle in the game calls.
## `knock` is accumulated rather than overwritten precisely so "nothing shoved me"
## can be asserted as an EQUALITY with zero — which is how `banish` proves it is an
## erasure and not an explosion.
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
	# spectacle seam OFF — that seam suppresses the PICTURE, never the damage or the
	# consumption (see ReactionOutcomes._radial), which is exactly what lets the
	# reach negatives below be asserted at all.
	reactor.set_process(false)
	reactor.set(&"spawn_effects", false)
	_caster_a = _named_node("CasterA")
	_caster_b = _named_node("CasterB")

	_test_ladder_unstolen()
	_test_new_rows_share_old_buckets()
	_test_banish_rows()
	_test_holy_shadow_is_asymmetric()
	_test_ward_answers_every_shadow_shape()
	_test_the_ram()
	_test_ordinary_barriers_stay_silent()
	_test_supercharge_reaches_blasts()
	_test_banish_through_the_reactor(reactor)
	_test_ram_through_the_reactor(reactor)
	_test_shadow_blast_pops_the_ward(reactor)
	_test_origin_parked_holds_for_the_new_rows(reactor)

	_free_all([_caster_a, _caster_b])
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Natural-reaction tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Natural-reaction tests: all PASS")
		quit(0)


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


# ------------------------------------------------------------- table helpers

## Resolve a pair and assert BOTH the outcome and the priority it won at.
##
## The priority half is the point. An outcome assertion alone passes happily while
## a new row sits one point above the row under test in the SAME bucket, because
## the winner is still named the same thing in the cases the test happens to try.
## Pinning the number is what turns "a row was slipped in above this" into a
## failure instead of a silence.
func _assert_rule(label: String, expect_outcome: String, expect_priority: int,
		form_a: int, element_a: int, form_b: int, element_b: int,
		owner_rel: String = "different",
		weight_a: int = SpellTier.Tier.HEAVY,
		weight_b: int = SpellTier.Tier.HEAVY) -> void:
	var r: Dictionary = ReactionTable.match_rule(form_a, element_a, form_b, element_b,
		owner_rel, weight_a, weight_b)
	var got: String = String(r.get("outcome", ""))
	_expect(got == expect_outcome,
		"%s resolves to `%s` (got `%s`)" % [label, expect_outcome, got])
	var pri: int = int(r.get("priority", -1))
	_expect(pri == expect_priority,
		"%s wins at priority %d — nothing has been slipped above it (got %d)"
			% [label, expect_priority, pri])
	# ...and it matches the same way with the sides handed over in the other order,
	# which is the trap consumes_caller() exists for. A row that only resolves one
	# way round is a row that is silently absent half the time.
	var swapped: Dictionary = ReactionTable.match_rule(form_b, element_b, form_a, element_a,
		owner_rel, weight_b, weight_a)
	_expect(String(swapped.get("outcome", "")) == expect_outcome,
		"%s matches with the sides swapped too" % label)


func _assert_silent(label: String, form_a: int, element_a: int,
		form_b: int, element_b: int,
		weight_a: int = SpellTier.Tier.HEAVY,
		weight_b: int = SpellTier.Tier.HEAVY) -> void:
	var r: Dictionary = ReactionTable.match_rule(form_a, element_a, form_b, element_b,
		"different", weight_a, weight_b)
	_expect(r.is_empty(),
		"%s is deliberately silent (got `%s`)" % [label, String(r.get("outcome", ""))])


## Every authored row whose bucket is (form_a, form_b), in table order.
func _rules_in_bucket(form_a: int, form_b: int) -> Array:
	var key: int = ReactionTable.bucket_key(form_a, form_b)
	var out: Array = []
	for r: Dictionary in ReactionTable.rules():
		if ReactionTable.bucket_key(int(r["form_a"]), int(r["form_b"])) == key:
			out.append(r)
	return out


func _outcomes_in_bucket(form_a: int, form_b: int) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in _rules_in_bucket(form_a, form_b):
		out.append(String(r["outcome"]))
	return out


# ------------------------------------------------------------- THE REGRESSION

## ⚠ THE ASSERTION THAT MATTERS MOST IN THIS FILE. Five rows were added to a live
## matrix, four of them into buckets that already had inhabitants. A priority
## chosen one point too high does not error, does not warn and does not fail any
## other suite — the headline reaction just stops happening, in play, weeks later.
## So every pre-existing outcome the new rows could plausibly have shadowed is
## pinned here by name AND by the number it wins at.
func _test_ladder_unstolen() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier

	# ── HOLLOW PURPLE, both rungs. Weight-blind by design, so it is asserted at a
	# lopsided pair as well: a signature combo that only fired when the shelves
	# lined up would be one the player cannot rely on.
	_assert_rule("the self-combo (opposed beams, one caster)", "hollow_purple", 100,
		F.BEAM, E.FIRE, F.BEAM, E.ICE, "same", T.HEAVY, T.HEAVY)
	_assert_rule("the self-combo at mismatched weights", "hollow_purple", 100,
		F.BEAM, E.SHADOW, F.BEAM, E.HOLY, "same", T.QUICK, T.ULT)
	_assert_rule("the cross-caster crossing", "hollow_purple", 95,
		F.BEAM, E.SHADOW, F.BEAM, E.HOLY, "different", T.HEAVY, T.HEAVY)
	# ── the rest of the BEAM x BEAM ladder.
	# Resonance is a SELF-combo reward now, so it needs the owner relation stated.
	# Two DUELLISTS on the same beam fall through to the clash and explode — the
	# mirror match was the likeliest duel case and it used to read as nothing
	# happening. Both halves pinned so neither can drift back.
	_assert_rule("one caster's own matched beams", "beam_resonance", 60,
		F.BEAM, E.FIRE, F.BEAM, E.FIRE, "same")
	_assert_rule("two duellists on the same beam", "mutual_annihilation", 55,
		F.BEAM, E.FIRE, F.BEAM, E.FIRE, "different")
	_assert_rule("two evenly matched neutral beams", "mutual_annihilation", 55,
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING)
	_assert_rule("a heavier beam against a lighter one", "overpower", 50,
		F.BEAM, E.FIRE, F.BEAM, E.LIGHTNING, "different", T.ULT, T.HEAVY)

	# ── BEAM x BARRIER, top to bottom. `banish` sits in a FIELD bucket and must not
	# have reached any of these; the ram sits in BARRIER x BARRIER and must not
	# either.
	_assert_rule("fire light on an ice wall", "shatter_ice_barrier", 90,
		F.BEAM, E.FIRE, F.BARRIER, E.ICE)
	_assert_rule("HOLY light on an ice wall", "shatter_ice_barrier", 90,
		F.BEAM, E.HOLY, F.BARRIER, E.ICE)
	_assert_rule("a shadow lance on a holy ward", "shatter_ward", 87,
		F.BEAM, E.SHADOW, F.BARRIER, E.HOLY)
	_assert_rule("lightning into stone", "ground_out", 82,
		F.BEAM, E.LIGHTNING, F.BARRIER, E.EARTH)
	_assert_rule("an ult beam against a lighter wall", "breach", 45,
		F.BEAM, E.ARCANE, F.BARRIER, E.ICE, "different", T.ULT, T.HEAVY)
	_assert_rule("an evenly matched beam boring stone", "carve", 40,
		F.BEAM, E.ARCANE, F.BARRIER, E.EARTH)
	_assert_rule("a beam eaten by a full ward", "ward_absorb", 30,
		F.BEAM, E.FIRE, F.BARRIER, E.HOLY)
	_assert_rule("a beam stopped by a wall it cannot beat", "barrier_blocks", 20,
		F.BEAM, E.ARCANE, F.BARRIER, E.ICE)

	# ── PROJECTILE x BARRIER.
	_assert_rule("a thrown thing bursting ice", "shrapnel_cone", 88,
		F.PROJECTILE, E.EARTH, F.BARRIER, E.ICE)
	_assert_rule("a shadow dagger on a holy ward", "shatter_ward", 86,
		F.PROJECTILE, E.SHADOW, F.BARRIER, E.HOLY)
	_assert_rule("a bolt eaten by a full ward", "ward_absorb", 29,
		F.PROJECTILE, E.FIRE, F.BARRIER, E.HOLY)

	# ── IMPACT x BARRIER. The bucket the new shatter_ward IMPACT row joined, so the
	# incumbent is pinned right next to it.
	_assert_rule("a blast cracking an ice wall", "shatter_ice_barrier", 85,
		F.IMPACT, E.EARTH, F.BARRIER, E.ICE)
	_assert_rule("a HOLY blast cracking an ice wall", "shatter_ice_barrier", 85,
		F.IMPACT, E.HOLY, F.BARRIER, E.ICE)

	# ── the FIELD buckets, which both new outcome rows joined.
	_assert_rule("fire boiling a frost field", "steam_cloud", 80,
		F.BEAM, E.FIRE, F.FIELD, E.ICE)
	_assert_rule("a fire BLAST boiling a frost field", "steam_cloud", 78,
		F.IMPACT, E.FIRE, F.FIELD, E.ICE)
	_assert_rule("lightning conducting through frost", "supercharge", 75,
		F.BEAM, E.LIGHTNING, F.FIELD, E.ICE)
	# void_charged is WILDCARD on the attacking side, so it is the row `banish` had
	# to be lifted over — and the row most likely to have been broken doing it.
	_assert_rule("a shadow blast inside a void field", "void_charged", 70,
		F.IMPACT, E.SHADOW, F.FIELD, E.SHADOW)
	_assert_rule("a FIRE blast inside a void field", "void_charged", 70,
		F.IMPACT, E.FIRE, F.FIELD, E.SHADOW)
	_assert_rule("a LIGHTNING blast inside a void field", "void_charged", 70,
		F.IMPACT, E.LIGHTNING, F.FIELD, E.SHADOW)
	_assert_rule("two same-element fields merging", "field_merge", 50,
		F.FIELD, E.ICE, F.FIELD, E.ICE)
	_completes("ladder_unstolen")


## THE PERFORMANCE CLAIM, asserted rather than promised. SpellReactor gates every
## pair on a sparse bucket hash built from ReactionTable's authored forms BEFORE any
## geometry runs, so a row that opens a NEW bucket makes the reactor start doing
## real work on a pair shape it used to discard on a hash miss. Every row added here
## landed in a bucket that already had an inhabitant, which is what makes the claim
## "five new interactions, zero new pair tests" true.
func _test_new_rows_share_old_buckets() -> void:
	var F := ReactionTable.Form
	# Each entry: the bucket a new row joined, and an outcome that was already there.
	var shared: Array = [
		[F.BARRIER, F.BARRIER, "none"],            # the ram joined the silence row
		[F.IMPACT, F.BARRIER, "shatter_ice_barrier"],   # shatter_ward IMPACT
		[F.BEAM, F.FIELD, "steam_cloud"],          # banish BEAM
		[F.IMPACT, F.FIELD, "void_charged"],       # banish IMPACT + supercharge IMPACT
	]
	for entry: Array in shared:
		var outcomes: Array[String] = _outcomes_in_bucket(int(entry[0]), int(entry[1]))
		_expect(outcomes.has(String(entry[2])),
			"the bucket a new row joined already contained `%s` (has: %s)"
				% [String(entry[2]), str(outcomes)])
	_completes("new_rows_share_old_buckets")


# ----------------------------------------------------- HOLY vs SHADOW: BANISH

## The maker's named pair. Light meeting a field of dark UNMAKES it, and the row
## has to outrank `void_charged` to say so — otherwise a pillar of holy light
## falling into a void field is CORRUPTED by it and inverts into a pull, which is
## the exact opposite sentence.
func _test_banish_rows() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var T := SpellTier.Tier
	_assert_rule("holy light on a shadow field", "banish", 81,
		F.BEAM, E.HOLY, F.FIELD, E.SHADOW)
	_assert_rule("a holy BLAST on a shadow field", "banish", 79,
		F.IMPACT, E.HOLY, F.FIELD, E.SHADOW)
	# Weight-blind, like every row in the elemental band: bringing the light IS the
	# answer, and a cheap one still clears the dark.
	_assert_rule("a QUICK holy blast on an ULT shadow field", "banish", 79,
		F.IMPACT, E.HOLY, F.FIELD, E.SHADOW, "different", T.QUICK, T.ULT)
	# ...and it is YOUR OWN light too. No owner predicate, deliberately — a field you
	# cleared with your own blast is a field you cleared.
	_assert_rule("your own holy blast on your own shadow field", "banish", 79,
		F.IMPACT, E.HOLY, F.FIELD, E.SHADOW, "same")

	# THE RULE THAT SHAPES BOTH THIS AND steam_cloud, asserted as a NEGATIVE: a
	# field is answered by things that FILL a volume, never by things that merely
	# PASS THROUGH it. A holy bolt crossing a shadow field does nothing, and neither
	# does a fire bolt crossing a frost one — the two halves of one decision, and the
	# thing that stops a free, spammable basic cast deleting a control spell on
	# repeat. If a PROJECTILE row is ever wanted, these are the assertions to argue
	# with first.
	_assert_silent("a holy BOLT crossing a shadow field",
		F.PROJECTILE, E.HOLY, F.FIELD, E.SHADOW)
	_assert_silent("a fire BOLT crossing a frost field",
		F.PROJECTILE, E.FIRE, F.FIELD, E.ICE)
	# And the mirror does not exist either: there is no holy FIELD in the game, so
	# nothing may match one into being.
	_assert_silent("a shadow blast on a holy field",
		F.IMPACT, E.SHADOW, F.FIELD, E.HOLY)
	_completes("banish_rows")


## THE ANSWER TO "HOLY VS SHADOW", stated as a shape rather than as a list.
##
## The pair is ASYMMETRIC, and that is the read: light UNMAKES dark, dark SHATTERS
## light, and neither ever trades with the other or explodes the way the rest of
## the matrix does. Opposed BEAM x BEAM stays the one exception — it still fuses
## into Hollow Purple, which is the headline, and these are what the pair does
## everywhere else.
##
## The last assertion is the one with teeth: no holy/shadow pairing anywhere may
## resolve to the generic weight contest. The maker asked for this pair to "read
## differently", and a pairing that fell through to `mutual_annihilation` would
## look exactly like fire meeting lightning.
func _test_holy_shadow_is_asymmetric() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var attacking_forms: Array[int] = [F.BEAM, F.PROJECTILE, F.IMPACT]

	# LIGHT UNMAKES DARK — the field goes, the light walks away.
	for f: int in [F.BEAM, F.IMPACT]:
		var r: Dictionary = ReactionTable.match_rule(f, E.HOLY, F.FIELD, E.SHADOW,
			"different", SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
		_expect(String(r.get("outcome", "")) == "banish",
			"every space-filling holy shape banishes a shadow field")
		_expect(ReactionTable.consumes_caller(r, 1) and not ReactionTable.consumes_caller(r, 0),
			"...spending the FIELD and never the light that cleared it")

	# DARK SHATTERS LIGHT — the ward goes, the shadow walks away. All three attacking
	# shapes, because "shadow pops it outright" is printed on the ward's own card and
	# a promise kept for two shapes out of three is a promise the player cannot use.
	for f: int in attacking_forms:
		var r: Dictionary = ReactionTable.match_rule(f, E.SHADOW, F.BARRIER, E.HOLY,
			"different", SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
		_expect(String(r.get("outcome", "")) == "shatter_ward",
			"every shadow shape pops a holy ward (form %d gave `%s`)"
				% [f, String(r.get("outcome", ""))])
		_expect(ReactionTable.consumes_caller(r, 1) and not ReactionTable.consumes_caller(r, 0),
			"...spending the WARD and never the shadow that popped it")

	# ...and the headline is untouched: opposed beams still FUSE rather than doing
	# either of the above.
	_assert_rule("holy light crossing a shadow lance", "hollow_purple", 95,
		F.BEAM, E.HOLY, F.BEAM, E.SHADOW)

	# NO HOLY/SHADOW MEETING THE GAME CAN PRODUCE FALLS THROUGH TO A GENERIC CLASH.
	# Swept rather than listed, so a pairing nobody thought of is covered too.
	#
	# ⚠ THE SWEEP IS OVER THE SHAPES THESE TWO ELEMENTS ACTUALLY TAKE, and that is a
	# correction rather than a convenience: sweeping ALL six forms fails on holy
	# BEAM vs a shadow BARRIER with `barrier_blocks`, which is not a bug — it is the
	# authored wildcard floor of that bucket doing exactly its job ("a wall stops
	# what it has no elemental answer to", inherited for free by every future spell
	# of that shape). There is no shadow barrier in the game and there is no reason
	# a hypothetical one should be exempt from being a wall. Narrowing the sweep to
	# the shipped roster keeps the claim TRUE instead of keeping it loud, and the
	# lists double as a record of what each school can currently be:
	#   HOLY   — BARRIER (Aegis Ward), IMPACT (a holy hero's Q blast), PROJECTILE
	#            (their basic cast), BEAM (Judgment, the moment DIVINE_RAY's
	#            spectacle adopts the participant contract).
	#   SHADOW — BEAM (Umbral Lance), FIELD (Shadow Root), PROJECTILE (Rift Dagger,
	#            Creeping Shade), IMPACT (Shadow Step).
	var generic: Array[String] = ["mutual_annihilation", "overpower", "breach",
		"barrier_blocks", "carve"]
	var holy_forms: Array[int] = [F.BEAM, F.PROJECTILE, F.IMPACT, F.BARRIER]
	var shadow_forms: Array[int] = [F.BEAM, F.PROJECTILE, F.IMPACT, F.FIELD]
	for fa: int in holy_forms:
		for fb: int in shadow_forms:
			var r: Dictionary = ReactionTable.match_rule(fa, E.HOLY, fb, E.SHADOW,
				"different", SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
			var got: String = String(r.get("outcome", ""))
			_expect(not generic.has(got),
				"holy(form %d) vs shadow(form %d) must not read as a generic clash (got `%s`)"
					% [fa, fb, got])
	_completes("holy_shadow_is_asymmetric")


## The ward, seen from the side the new row changed. A NON-opposed blast still gets
## nothing from it — which is the assertion that keeps `shatter_ward` from having
## quietly become "any impact breaks any ward", and keeps the documented "IMPACT
## gets no blocks/breach rung" ruling true.
func _test_ward_answers_every_shadow_shape() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	_assert_rule("a shadow BLAST on a holy ward", "shatter_ward", 83,
		F.IMPACT, E.SHADOW, F.BARRIER, E.HOLY)
	# A blast is NOT swallowed, absorbed or blocked by a barrier it was never
	# travelling toward — the whole reason IMPACT has no rung on the barrier ladder.
	_assert_silent("a FIRE blast beside a holy ward", F.IMPACT, E.FIRE, F.BARRIER, E.HOLY)
	_assert_silent("a fire blast beside a stone wall", F.IMPACT, E.FIRE, F.BARRIER, E.EARTH)
	_completes("ward_answers_every_shadow_shape")


# ------------------------------------------------------------------- THE RAM

## STONE INTO ICE. The row RockWall's own class docs asked the table for by name.
## Both orderings are checked explicitly and — the part that actually breaks — the
## CONSUMPTION is checked in both, because a row written earth-then-ice also matches
## ice-first and then its `consumes_b` means the caller's `a`. Getting that backwards
## eats the rock wall and leaves the ice standing, which is the reaction running
## exactly wrong while still reporting as fired.
func _test_the_ram() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	_assert_rule("a shoved rock wall meeting an ice wall", "shatter_ice_barrier", 84,
		F.BARRIER, E.EARTH, F.BARRIER, E.ICE)
	# Rock seen first: the row matches straight, and its consumes_b is the caller's b.
	var straight: Dictionary = ReactionTable.match_rule(
		F.BARRIER, Elements.Element.EARTH, F.BARRIER, Elements.Element.ICE, "different",
		SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(not ReactionTable.consumes_caller(straight, 0),
		"the ramming STONE is not spent (rock seen first)")
	_expect(ReactionTable.consumes_caller(straight, 1),
		"the ICE is (rock seen first)")
	# Ice seen first: the row matched SWAPPED, so the flags mean the other sides.
	var swapped: Dictionary = ReactionTable.match_rule(
		F.BARRIER, Elements.Element.ICE, F.BARRIER, Elements.Element.EARTH, "different",
		SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(bool(swapped.get("swapped", false)),
		"the row really did match with its sides reversed")
	_expect(ReactionTable.consumes_caller(swapped, 0),
		"the ICE is still the side spent (ice seen first)")
	_expect(not ReactionTable.consumes_caller(swapped, 1),
		"...and the STONE still is not")
	# Weight-blind, like the other shatter rows: a mass of stone does not need to
	# out-shelf a sheet of ice to break it.
	_assert_rule("a QUICK rock wall ramming an ULT ice wall", "shatter_ice_barrier", 84,
		F.BARRIER, E.EARTH, F.BARRIER, E.ICE, "different",
		SpellTier.Tier.QUICK, SpellTier.Tier.ULT)
	_completes("the_ram")


## ⚠ THE DOCUMENTED SILENCE, which the ram row is the single most likely thing to
## have destroyed. "Two barriers touching is architecture, not an event" is a
## decision written into the table, and the ram must be the ONE named exception to
## it rather than the end of it. Every other barrier pair the game can actually
## produce is listed here, so the day someone widens the ram's element lists this
## fails instead of shipping walls that pop each other on contact.
func _test_ordinary_barriers_stay_silent() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	_assert_silent("two stone walls", F.BARRIER, E.EARTH, F.BARRIER, E.EARTH)
	_assert_silent("two ice walls", F.BARRIER, E.ICE, F.BARRIER, E.ICE)
	_assert_silent("a stone wall against a holy ward", F.BARRIER, E.EARTH, F.BARRIER, E.HOLY)
	_assert_silent("an ice wall against a holy ward", F.BARRIER, E.ICE, F.BARRIER, E.HOLY)
	_assert_silent("two holy wards", F.BARRIER, E.HOLY, F.BARRIER, E.HOLY)
	# ...including at lopsided weights, so the silence cannot be a weight accident.
	_assert_silent("an ULT stone wall against a QUICK stone wall",
		F.BARRIER, E.EARTH, F.BARRIER, E.EARTH, SpellTier.Tier.ULT, SpellTier.Tier.QUICK)
	# And the ICE wall is not simply fragile to everything: it takes STONE to ram it.
	_assert_silent("a holy ward against an ice wall", F.BARRIER, E.HOLY, F.BARRIER, E.ICE)
	_completes("ordinary_barriers_stay_silent")


## Lightning + frost, extended to the shape that can actually reach it. Only one
## kit's ULT is a lightning BEAM, but every hero's Q blast carries their own
## element — so a Stormcaller dropping a blast into the Blizzard in their own
## control slot is the set-up the pair was always describing.
func _test_supercharge_reaches_blasts() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var r: Dictionary = ReactionTable.match_rule(F.IMPACT, E.LIGHTNING, F.FIELD, E.ICE,
		"different", SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(String(r.get("outcome", "")) == "supercharge",
		"a lightning blast inside a frost field supercharges (got `%s`)"
			% String(r.get("outcome", "")))
	_expect(int(r.get("priority", -1)) == 73, "...at the priority it was authored at")
	_expect(not ReactionTable.consumes_caller(r, 0) and not ReactionTable.consumes_caller(r, 1),
		"supercharge spends NOTHING — the field stands and the blast still happened")
	# It is the ICE that conducts, not the field-ness: a lightning blast in a shadow
	# field is still void-charged, which the ladder test pins from the other side.
	_assert_rule("lightning inside a VOID field", "void_charged", 70,
		F.IMPACT, E.LIGHTNING, F.FIELD, E.SHADOW)
	_completes("supercharge_reaches_blasts")


# -------------------------------------------------- end to end, through the reactor

## BANISH, all the way through: the field is spent, what stood in it is BURNED by
## the light, what stood outside it is untouched, and NOTHING IS THROWN.
##
## The knockback assertion is not decoration. `banish` shares a bucket with
## `void_charged`, whose entire identity is an inverted shove, and the difference
## between "the dark was unmade" and "the dark sucked you in" is a single signed
## number in ReactionOutcomes. An equality against zero is the only way to state it.
func _test_banish_through_the_reactor(reactor: Node) -> void:
	var E := Elements.Element
	var field: ReactantStub = _field(reactor, Vector2.ZERO, 150.0, E.SHADOW)
	var light: ReactantStub = _impact(reactor, Vector2.ZERO, 70.0, E.HOLY)
	var inside: Dummy = _dummy(Vector2(90.0, 0.0))
	# Just outside the FIELD's own published radius. `_banish` damages the field's
	# drawn shape and nothing wider, so this body is the reach contract's negative.
	var outside: Dummy = _dummy(Vector2(400.0, 0.0))
	_expect(int(reactor.call(&"resolve_now")) == 1, "the light reaches the dark")
	_expect(field.consumed == 1, "the shadow field is UNMADE")
	_expect(light.consumed == 0, "...and the light that cleared it is not spent")
	_expect(inside.hp_lost > 0, "a body standing in the banished field is burned")
	_expect(inside.status == E.HOLY,
		"...by the LIGHT's ailment, not the shadow's (got %d)" % inside.status)
	_expect(inside.knock == Vector2.ZERO,
		"NOTHING is thrown — banish is an erasure, not an explosion (got %s)"
			% inside.knock)
	_expect(outside.hp_lost == 0,
		"a body outside the drawn field takes nothing — the reach contract")
	_expect(int(reactor.call(&"resolve_now")) == 0, "and the pair does not fire again")
	_drop(reactor, [field, light])
	_free_all([inside, outside])
	_completes("banish_through_the_reactor")


## THE RAM, all the way through. The assertion that would catch the swapped-side
## bug in the form it would actually ship as: the wrong wall dying.
func _test_ram_through_the_reactor(reactor: Node) -> void:
	var E := Elements.Element
	var rock: ReactantStub = _barrier(reactor, Vector2.ZERO, E.EARTH)
	var ice: ReactantStub = _barrier(reactor, Vector2(18.0, 0.0), E.ICE)
	var beside: Dummy = _dummy(Vector2(78.0, -60.0))
	var far: Dummy = _dummy(Vector2(400.0, -60.0))
	_expect(int(reactor.call(&"resolve_now")) == 1, "the stone reaches the ice")
	_expect(ice.consumed == 1, "the ICE wall bursts")
	_expect(rock.consumed == 0, "...and the STONE grinds on through it")
	_expect(beside.hp_lost > 0, "the shards hurt what was standing beside the ice")
	_expect(beside.status == E.EARTH,
		"the ailment left behind is the RAM's, not the ice's (got %d)" % beside.status)
	_expect(far.hp_lost == 0, "and nothing outside the burst")
	_drop(reactor, [rock, ice])
	_free_all([beside, far])
	_completes("ram_through_the_reactor")


## The row that makes the ward's own spell card true. Shadow Step is an IMPACT and
## is equipped in three kits; before this row it did nothing at all to a ward that
## advertises "shadow pops it outright".
func _test_shadow_blast_pops_the_ward(reactor: Node) -> void:
	var E := Elements.Element
	var ward: ReactantStub = _barrier(reactor, Vector2.ZERO, E.HOLY)
	var step: ReactantStub = _impact(reactor, Vector2(0.0, -60.0), 64.0, E.SHADOW)
	_expect(int(reactor.call(&"resolve_now")) == 1, "the shadow blast reaches the ward")
	_expect(ward.consumed == 1, "the ward is POPPED, exactly as its card promises")
	_expect(ward.absorbed == 0,
		"...popped, not merely absorbed — a plate would leave the gate standing")
	_expect(step.consumed == 0, "and the blast is not spent doing it")
	_drop(reactor, [ward, step])
	# The control: the same blast on a NON-holy barrier is still nothing, so the
	# assertion above cannot be passing because impacts now break every wall.
	var stone: ReactantStub = _barrier(reactor, Vector2.ZERO, E.EARTH)
	var step2: ReactantStub = _impact(reactor, Vector2(0.0, -60.0), 64.0, E.SHADOW)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"the same blast beside a STONE wall does nothing at all")
	_expect(stone.consumed == 0, "...and the stone stands")
	_drop(reactor, [stone, step2])
	_completes("shadow_blast_pops_the_ward")


## ⚠ THE REGRESSION THE WHOLE LAYER EXISTS FOR, re-asserted for the new rows. Every
## spectacle in this game parks at (0, 0) and draws in world coordinates, so a
## detector that ever started trusting transforms would report EVERY pair of live
## effects as touching, at the top-left of the arena. slice6_test_reactor.gd owns
## the canonical guard; this one exists because a NEW row is a new chance for a pair
## that used to die on a bucket miss to reach the geometry stage at all.
func _test_origin_parked_holds_for_the_new_rows(reactor: Node) -> void:
	var E := Elements.Element
	var field: ReactantStub = _field(reactor, Vector2(-4000.0, 0.0), 150.0, E.SHADOW)
	var light: ReactantStub = _impact(reactor, Vector2(4000.0, 0.0), 70.0, E.HOLY)
	_expect(field.global_position == Vector2.ZERO and light.global_position == Vector2.ZERO,
		"both participants really are parked at the origin")
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"a holy blast and a shadow field 8000 px apart do NOT banish anything")
	_expect(field.consumed == 0, "...and the field is untouched")
	# Positive control: same nodes, same transforms, the blast's SHAPE moved onto the
	# field. Without it the assertion above is satisfied by a row that never fires.
	light.shape = SpellGeometry.circle(Vector2(-4000.0, 0.0), 70.0)
	_expect(int(reactor.call(&"resolve_now")) == 1,
		"...and DO once the shapes actually meet")
	_expect(field.consumed == 1, "banishing it")
	_drop(reactor, [field, light])
	# The same guard for the ram, whose bucket used to resolve to silence for every
	# pair and therefore never reached geometry at all before tonight.
	var rock: ReactantStub = _barrier(reactor, Vector2(-4000.0, 0.0), E.EARTH)
	var ice: ReactantStub = _barrier(reactor, Vector2(4000.0, 0.0), E.ICE)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"two origin-parked walls 8000 px apart do NOT ram each other")
	_expect(ice.consumed == 0, "...and the ice stands")
	ice.shape = SpellGeometry.capsule(Vector2(-3990.0, 0.0),
		Vector2(-3990.0, -BARRIER_HEIGHT), BARRIER_WIDTH)
	_expect(int(reactor.call(&"resolve_now")) == 1, "...and DO once they actually meet")
	_expect(ice.consumed == 1, "bursting it")
	_drop(reactor, [rock, ice])
	_completes("origin_parked_holds_for_the_new_rows")


# ------------------------------------------------------------------- fixtures

func _named_node(n: String) -> Node:
	var c := Node2D.new()
	c.name = n
	root.add_child(c)
	return c


func _dummy(at: Vector2) -> Dummy:
	var d := Dummy.new()
	root.add_child(d)
	d.global_position = at
	return d


func _stub(reactor: Node, form: int, element: int, shape: Dictionary,
		owner_node: Node, weight: int = SpellTier.Tier.HEAVY) -> ReactantStub:
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


func _impact(reactor: Node, at: Vector2, radius: float, element: int) -> ReactantStub:
	return _stub(reactor, ReactionTable.Form.IMPACT, element,
		SpellGeometry.circle(at, radius), _caster_b)


func _field(reactor: Node, at: Vector2, radius: float, element: int) -> ReactantStub:
	return _stub(reactor, ReactionTable.Form.FIELD, element,
		SpellGeometry.circle(at, radius), _caster_a)


## A wall / ward: a vertical capsule standing on `base`. The same shape every real
## barrier publishes, and deliberately vertical even for the ram — a shoved rock
## wall is still a slab standing on its end (see RockWall.reaction_form).
func _barrier(reactor: Node, base: Vector2, element: int) -> ReactantStub:
	return _stub(reactor, ReactionTable.Form.BARRIER, element,
		SpellGeometry.capsule(base, base - Vector2(0.0, BARRIER_HEIGHT), BARRIER_WIDTH),
		_caster_a)


func _drop(reactor: Node, nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			reactor.call(&"unregister", n)
			n.free()


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.free()
