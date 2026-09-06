# Run: godot --headless --path godot-project --script tools/slice_test_element_affinity.gd
#
# ELEMENT AFFINITY — a spell whose element matches its CASTER'S CLASS element hits
# harder in that caster's hands, and in nobody else's.
#
# The maker's ruling, verbatim: *"the classes should amplify current spells but it
# shouldn't prevent any player from taking any spell."* Three axes were put to them —
# element affinity, a flat per-class multiplier, and a per-role one — and they chose
# ELEMENT AFFINITY. So the invariant this suite defends has two halves and the second
# is the one that is easy to lose:
#
#   1. ON-ELEMENT AMPLIFIES. `SpellCaster.AFFINITY_MULT` reaches the damage that is
#      actually thrown, through the one seam that is allowed to scale it.
#   2. OFF-ELEMENT IS NOT PUNISHED. There is no multiplier below 1.0 anywhere in the
#      table. A penalty would re-gate the Grimoire pool through the back door — an
#      off-element spell would stop being a different choice and start being the
#      wrong one — and the second half of the ruling would be dead in everything but
#      the UI. `_test_affinity_is_never_a_penalty` sweeps all 64 (caster, spell)
#      element pairs and asserts the floor directly, because "I did not write an
#      `else` that returns 0.8" is not something review can keep being right about.
#
# ── WHY THE INTEGRATION TESTS CALL `_blood_pacted` ─────────────────────────────
# Because that is where the feature lives, and asserting `affinity_mult()` alone
# would be asserting arithmetic nobody consumes. `affinity_mult` returning 1.25 while
# nothing multiplies by it is exactly the failure this repo has a scar from — a
# confident comment describing scoring that was never wired. So the tests that matter
# read `_blood_pacted`'s RETURNED `SpellDef.damage`: the number the spectacle is
# handed. A leading underscore is not privacy in GDScript and this is the honest
# seam.
#
# ── CONFIRMED TO FAIL WITH THE CHANGE DISABLED ────────────────────────────────
# A test that has never gone red is a test of the fixture. Commenting out the single
# line `mult *= affinity_mult(spell, caster)` in `SpellCaster._blood_pacted` takes
# this suite to **5 FAILED** (the four integration/coverage tests plus the completion
# sentinel for the one that aborts). With the line restored: all PASS. Both numbers
# were measured, not predicted.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ─────────
# `failed += _test_x()` IS BANNED. A dead property read is not a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function and hands the
# caller back the return type's zero, which under that idiom reads as "zero
# failures". So failures accumulate on the MEMBER `_fails`, and every test's last
# line records that it reached the end — a test that aborts part-way is missing from
# `_completed` and fails BY ABSENCE.
extends SceneTree

## Reached by `load`, not by `class_name`: `Hero.gd` deliberately has no `class_name`
## (see `tools/slice_test_cryomancer_kit.gd`, which reaches its members the same way),
## and naming a class here would force compile-time autoload resolution that a
## `--script` harness cannot satisfy.
const HERO_SCRIPT_PATH: String = "res://scripts/combat/Hero.gd"

const TESTS: Array[String] = [
	"on_element_amplifies_off_element_does_not",
	"affinity_is_never_a_penalty",
	"a_caster_that_does_not_answer_opts_out",
	"the_boost_reaches_the_thrown_damage",
	"affinity_composes_with_growth_in_one_rounding",
	"the_shared_catalog_resource_is_never_mutated",
	"it_reads_the_class_element_not_the_equipped_one",
	"every_class_amplifies_something_it_actually_carries",
	"wind_is_the_element_no_class_carries",
	"a_shared_element_is_allowed_and_is_not_a_collision",
]

## THE CLASS -> ELEMENT TABLE, FROZEN. Nine classes, in `Hero.HeroClass` order.
##
## Frozen rather than only derived because a derived-only assertion cannot notice the
## table CHANGING — it would happily re-derive "WIND has no class" into "FIRE has no
## class" and report all PASS. `_test_wind_is_the_element_no_class_carries` checks
## this literal against `Hero.CLASS_CONFIG` first, so a genuine re-elementing of a
## class fails HERE, loudly, next to the note explaining what the answer used to be.
const CLASS_ELEMENTS: Array[int] = [
	Elements.Element.ARCANE,     # 0 Arcanist
	Elements.Element.SHADOW,     # 1 Shadowblade
	Elements.Element.FIRE,       # 2 Brawler
	Elements.Element.EARTH,      # 3 Juggernaut
	Elements.Element.HOLY,       # 4 Cleric
	Elements.Element.ICE,        # 5 Cryomancer
	Elements.Element.LIGHTNING,  # 6 Stormcaller
	Elements.Element.SHADOW,     # 7 Warlock
	Elements.Element.ARCANE,     # 8 Swordsaint
]

## Every element index, so the penalty sweep is exhaustive rather than sampled.
const ALL_ELEMENTS: Array[int] = [
	Elements.Element.FIRE, Elements.Element.ICE, Elements.Element.LIGHTNING,
	Elements.Element.SHADOW, Elements.Element.ARCANE, Elements.Element.EARTH,
	Elements.Element.HOLY, Elements.Element.WIND,
]

## The one element no class carries. Nine classes over eight elements cannot be a
## bijection, and this is the leftover. Named as a KNOWN FACT so it is discovered
## once, here, rather than a second time by whoever authors a Wind spell and wonders
## why nobody amplifies it.
##
## It is a RESERVED SLOT, not a hole: WIND is the element of the designed-but-unbuilt
## AIR class (the one whose movement verb is a long hop-dash, per the class-identity
## mandate). Do not "fix" this by re-elementing an existing class into it — that would
## quietly move the amplification off whatever element that class holds today.
const ORPHAN_ELEMENT: int = Elements.Element.WIND

## ⚠ THE CLASSES ELEMENT AFFINITY PAYS NOTHING, AND WHY. Measured, not assumed — the
## first run of `_test_every_class_amplifies_something_it_actually_carries` found this
## and it is a REAL GAP, recorded here rather than papered over by weakening the
## assertion.
##
##   2 BRAWLER. Its class element is FIRE, and every spell in its hand is EARTH:
##   Shockwave Stomp, Petrify, Rock Wall, Boulder Hurl, Meteor Fist. So the Brawler
##   is the one class that gets nothing at all from this feature.
##
## It is COHERENT with the class (its card reads *"Pure-melee knockout — no magic"*,
## its FIRE shows up as `melee_element` — the fists apply burn — and melee deliberately
## does not go through the spell seam). But coherent is not the same as intended, and
## this is a design call for the maker, not something a damage seam may decide: either
## the Brawler's element is really EARTH and `Hero.CLASS_CONFIG` is stale, or the class
## wants one fire spell in hand, or the melee-only class is meant to sit this feature
## out. Whichever it is, it should be chosen once.
##
## Frozen as a literal so it cannot drift silently in EITHER direction: give the
## Brawler a fire spell and this test goes red pointing at this note, and if a SECOND
## class ever falls off the feature it goes red too instead of being absorbed into a
## vague "most classes" assertion.
const UNPAID_CLASSES: Array[int] = [2]  # Brawler — see above

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


## A caster that answers `affinity_element` and nothing else.
##
## ⚠ EXTENDS `Node`, NOT `RefCounted`, and that is forced rather than chosen:
## `SpellCaster._blood_pacted` types its `caster` parameter as `Node`, so a
## `RefCounted` stub fails the typed-parameter check at the call and the test aborts
## into a vacuous pass. Freed by hand in `_free_stubs`; never enters the tree, so
## nothing in `_ready` runs and no autoload is touched.
class _Affine extends Node:
	var element: int = -1
	## ⚠ DECLARED, AND THAT IS LOAD-BEARING. `_test_it_reads_the_class_element_not_the
	## _equipped_one` writes a DECOY live element here, and `set()` on an UNDECLARED
	## property is a SILENT NO-OP in Godot 4 — the decoy would never be stored, an
	## implementation that wrongly read `_element` would find nothing to read, and the
	## test would pass vacuously while asserting the opposite of what it claims.
	## This is the same scar `tools/_stub_hero.gd` was written about.
	var _element: int = -1
	func affinity_element() -> int:
		return element


## A caster that answers BOTH duck-typed contracts, for the composition test.
class _AffineGrown extends Node:
	var element: int = -1
	var growth: float = 1.0
	func affinity_element() -> int:
		return element
	func growth_damage_mult() -> float:
		return growth


## A caster that answers NEITHER — an enemy, a bot, a thrall, a mirror image. The
## opt-out is "does not have the method", so the stub is a bare `Node`.
class _Mute extends Node:
	pass


var _stubs: Array[Node] = []


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_on_element_amplifies_off_element_does_not()
	_test_affinity_is_never_a_penalty()
	_test_a_caster_that_does_not_answer_opts_out()
	_test_the_boost_reaches_the_thrown_damage()
	_test_affinity_composes_with_growth_in_one_rounding()
	_test_the_shared_catalog_resource_is_never_mutated()
	_test_it_reads_the_class_element_not_the_equipped_one()
	_test_every_class_amplifies_something_it_actually_carries()
	_test_wind_is_the_element_no_class_carries()
	_test_a_shared_element_is_allowed_and_is_not_a_collision()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	_free_stubs()
	if _fails > 0:
		printerr("Element affinity tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Element affinity tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _affine(elem: int) -> _Affine:
	var n := _Affine.new()
	n.element = elem
	_stubs.append(n)
	return n


func _affine_grown(elem: int, growth: float) -> _AffineGrown:
	var n := _AffineGrown.new()
	n.element = elem
	n.growth = growth
	_stubs.append(n)
	return n


func _mute() -> _Mute:
	var n := _Mute.new()
	_stubs.append(n)
	return n


func _free_stubs() -> void:
	for n: Node in _stubs:
		if is_instance_valid(n):
			n.free()
	_stubs.clear()


## A throwaway spell with an EXPLICIT element, so the arithmetic tests never depend on
## `resolve_element`'s effect-string fallback. `SpellDef.new()` is a fresh Resource,
## never one out of the shared catalog — mutating a catalog spell is the exact hazard
## `_blood_pacted` exists to prevent and a test must not model it.
func _spell(elem: int, dmg: int) -> SpellDef:
	var s := SpellDef.new()
	s.id = "test_affinity_probe"
	s.kind = SpellDef.Kind.BEAM
	s.element = elem
	s.damage = dmg
	return s


# ════════════════════════════════════════════ 1. the rule, at its simplest
## On-element earns `AFFINITY_MULT`; every other element earns exactly 1.0.
func _test_on_element_amplifies_off_element_does_not() -> void:
	var cryo: _Affine = _affine(Elements.Element.ICE)
	_expect(is_equal_approx(
			SpellCaster.affinity_mult(_spell(Elements.Element.ICE, 40), cryo),
			SpellCaster.AFFINITY_MULT),
		"an ICE caster amplifies an ICE spell by AFFINITY_MULT (got %f)"
			% SpellCaster.affinity_mult(_spell(Elements.Element.ICE, 40), cryo))
	_expect(is_equal_approx(
			SpellCaster.affinity_mult(_spell(Elements.Element.FIRE, 40), cryo), 1.0),
		"an ICE caster does NOT amplify a FIRE spell (got %f)"
			% SpellCaster.affinity_mult(_spell(Elements.Element.FIRE, 40), cryo))
	# The constant is the feature's whole dial; a silent retune to 1.0 would leave
	# every other test in this file passing while the feature did nothing.
	_expect(SpellCaster.AFFINITY_MULT > 1.0,
		"AFFINITY_MULT is actually an amplification (it is %f)" % SpellCaster.AFFINITY_MULT)
	_completes("on_element_amplifies_off_element_does_not")


# ═══════════════════════════════════════ 2. the half that is easy to lose
## ⚠ THE RULING'S SECOND HALF, ASSERTED MECHANICALLY. All 64 (caster, spell) element
## pairs: none scores below 1.0, and EXACTLY the eight diagonal pairs score above it.
## The second clause matters as much as the first — a table that amplified everything
## would satisfy "never a penalty" and would still not be affinity.
func _test_affinity_is_never_a_penalty() -> void:
	var above: int = 0
	var checked: int = 0
	for caster_elem: int in ALL_ELEMENTS:
		var c: _Affine = _affine(caster_elem)
		for spell_elem: int in ALL_ELEMENTS:
			var m: float = SpellCaster.affinity_mult(_spell(spell_elem, 40), c)
			checked += 1
			_expect(m >= 1.0,
				"caster %s / spell %s is not a PENALTY (got %f)"
					% [Elements.display_name(caster_elem),
						Elements.display_name(spell_elem), m])
			if m > 1.0:
				above += 1
				_expect(caster_elem == spell_elem,
					"only the matching pair is amplified (%s caster boosted a %s spell)"
						% [Elements.display_name(caster_elem),
							Elements.display_name(spell_elem)])
	# Anti-vacuity: an empty sweep would pass every assertion above in silence.
	_expect(checked == ALL_ELEMENTS.size() * ALL_ELEMENTS.size(),
		"the sweep really covered all %d pairs (covered %d)"
			% [ALL_ELEMENTS.size() * ALL_ELEMENTS.size(), checked])
	_expect(above == ALL_ELEMENTS.size(),
		"exactly the %d matching pairs are amplified (got %d)"
			% [ALL_ELEMENTS.size(), above])
	_completes("affinity_is_never_a_penalty")


# ═══════════════════════════════════════════════ 3. the duck-typed opt-out
## An enemy, a bot, a thrall and a mirror image opt out of affinity by not answering.
## Asserted on a stub with no method rather than trusted to an `is Hero` check that
## does not exist — the whole point of the `has_method` contract is that no call site
## needs to know the roster of things that level or attune.
func _test_a_caster_that_does_not_answer_opts_out() -> void:
	_expect(is_equal_approx(
			SpellCaster.affinity_mult(_spell(Elements.Element.FIRE, 40), _mute()), 1.0),
		"a caster with no `affinity_element` gets no affinity")
	_expect(is_equal_approx(
			SpellCaster.affinity_mult(_spell(Elements.Element.FIRE, 40), null), 1.0),
		"a null caster gets no affinity (an unowned effect)")
	_expect(is_equal_approx(
			SpellCaster.affinity_mult(null, _affine(Elements.Element.FIRE)), 1.0),
		"a null spell is 1.0 rather than a crash")
	# A caster whose class element is unset (-1) matches nothing, and must not match
	# a spell whose `resolve_element` happens to floor at ARCANE.
	_expect(is_equal_approx(
			SpellCaster.affinity_mult(_spell(Elements.Element.ARCANE, 40), _affine(-1)), 1.0),
		"a caster with element -1 is on-element with nothing")
	_completes("a_caster_that_does_not_answer_opts_out")


# ══════════════════════════════ 4. THE ONE THAT GOES RED WITH THE CHANGE OFF
## The number the spectacle is actually handed. This is the test that fails when
## `mult *= affinity_mult(spell, caster)` is removed from `_blood_pacted`; everything
## above it would keep passing, because `affinity_mult` would still return 1.25 to
## nobody.
func _test_the_boost_reaches_the_thrown_damage() -> void:
	var base: int = 40
	var on: SpellDef = _spell(Elements.Element.ICE, base)
	var thrown_on: SpellDef = SpellCaster._blood_pacted(
		on, _affine(Elements.Element.ICE), null)
	var want: int = int(round(float(base) * SpellCaster.AFFINITY_MULT))
	_expect(thrown_on != null and thrown_on.damage == want,
		"an on-element cast is thrown at %d, not %d"
			% [want, (thrown_on.damage if thrown_on != null else -1)])
	var off: SpellDef = _spell(Elements.Element.FIRE, base)
	var thrown_off: SpellDef = SpellCaster._blood_pacted(
		off, _affine(Elements.Element.ICE), null)
	_expect(thrown_off != null and thrown_off.damage == base,
		"an off-element cast is thrown UNCHANGED at %d (got %d)"
			% [base, (thrown_off.damage if thrown_off != null else -1)])
	# The neutral path must still allocate nothing — the identity, not a copy.
	_expect(thrown_off == off,
		"a neutral cast returns the SAME SpellDef, not a duplicate (the common path "
		+ "allocates nothing)")
	_completes("the_boost_reaches_the_thrown_damage")


# ═════════════════════════════════════ 5. one rounding, not two
## Affinity and level growth COMPOSE MULTIPLICATIVELY inside a single `round`.
## Rounding each in turn would make the same hero's same spell depend on the order
## the multipliers were asked in — a number nobody could reproduce from a tooltip.
## 40 * 1.25 * 1.13 is 56.5, and the two orderings disagree (57 vs 56), so this test
## can actually tell them apart.
##
## ⚠ THE FIRST NUMBERS I PICKED HERE WERE VACUOUS AND THE SUITE SAID SO. base 40 /
## growth 1.13 gives 56 BOTH WAYS, because 40 * 1.25 is exactly 50 and there is no
## first rounding to differ about — the assertion below would have passed under
## either implementation and proved nothing. `base` must be a value whose 1.25x is a
## clean .5, and `growth` must be large enough to carry that half-point across the
## second rounding boundary: 42 * 1.25 = 52.5, and 78.75 -> 79 while 53 * 1.5 = 79.5
## -> 80. The `want != staged` guard below is what caught it, and it stays.
func _test_affinity_composes_with_growth_in_one_rounding() -> void:
	var base: int = 42
	var growth: float = 1.5
	var caster: _AffineGrown = _affine_grown(Elements.Element.SHADOW, growth)
	var thrown: SpellDef = SpellCaster._blood_pacted(
		_spell(Elements.Element.SHADOW, base), caster, null)
	var want: int = int(round(float(base) * SpellCaster.AFFINITY_MULT * growth))
	var staged: int = int(round(float(int(round(float(base) * SpellCaster.AFFINITY_MULT)))
		* growth))
	_expect(want != staged,
		"the fixture can tell one rounding from two (%d vs %d) — if these are equal "
			% [want, staged] + "the assertion below is vacuous and the numbers need "
			+ "re-picking")
	_expect(thrown != null and thrown.damage == want,
		"growth and affinity compose in ONE rounding: %d (got %d)"
			% [want, (thrown.damage if thrown != null else -1)])
	_completes("affinity_composes_with_growth_in_one_rounding")


# ═══════════════════════════════ 6. the shared catalog resource stays shared
## ⚠ THE HAZARD `_blood_pacted` EXISTS FOR. A `SpellDef` out of `SpellLibrary` is the
## SAME OBJECT every caster of that spell reads. Scaling it in place would buff the
## spell permanently, for enemies and bots and the other player, compounding once per
## cast. Cast a real carried spell twice and assert the catalog copy never moves.
func _test_the_shared_catalog_resource_is_never_mutated() -> void:
	var hand: Array = SpellLibrary.build_for_class(5)  # Cryomancer — ICE
	_expect(not hand.is_empty(), "the Cryomancer hand is non-empty (the fixture is real)")
	if hand.is_empty():
		return
	var caster: _Affine = _affine(Elements.Element.ICE)
	var touched: int = 0
	for s: SpellDef in hand:
		if s.damage <= 0:
			continue  # a wall / ward has no damage to scale; nothing to assert
		touched += 1
		var before: int = s.damage
		SpellCaster._blood_pacted(s, caster, null)
		SpellCaster._blood_pacted(s, caster, null)
		_expect(s.damage == before,
			"'%s' in the catalog is still %d after two casts (got %d — the shared "
				% [s.id, before, s.damage] + "resource is being scaled in place, and "
				+ "it COMPOUNDS)")
	_expect(touched > 0,
		"at least one carried Cryomancer spell deals damage (else this test asserted "
		+ "nothing)")
	_completes("the_shared_catalog_resource_is_never_mutated")


# ═══════════════════════════ 7. the class element, not the equipped one
## ⚠ THE DISTINCTION THE WHOLE FEATURE RESTS ON. `affinity_element` is `Hero`'s
## `_base_element` — the class picked at the altar — NOT `_element`, which a
## spellement weapon overwrites. If affinity read the live element, equipping a staff
## of your own element would make the bonus unconditional and there would be no
## choice left to make.
##
## Asserted from the outside, the only way a static helper can be asked: a caster
## whose `affinity_element` says FIRE is amplified on FIRE and not on ICE, no matter
## what else that object also reports. The stub carries a decoy `_element` so a
## future implementation that reached for the live element instead would go red here
## rather than silently double-count.
func _test_it_reads_the_class_element_not_the_equipped_one() -> void:
	var caster: _Affine = _affine(Elements.Element.FIRE)
	caster._element = Elements.Element.ICE  # the "equipped" decoy — a spellement staff
	# The decoy has to really be stored, or the assertions below prove nothing. This
	# read-back is the guard; see the note on `_Affine._element`.
	_expect(caster._element == Elements.Element.ICE,
		"the decoy live element was actually stored on the stub (else the two "
		+ "assertions below are vacuous)")
	_expect(is_equal_approx(
			SpellCaster.affinity_mult(_spell(Elements.Element.FIRE, 30), caster),
			SpellCaster.AFFINITY_MULT),
		"affinity follows the CLASS element (FIRE), which is what `affinity_element` "
		+ "answers")
	_expect(is_equal_approx(
			SpellCaster.affinity_mult(_spell(Elements.Element.ICE, 30), caster), 1.0),
		"affinity does NOT follow a decoy `_element` (ICE) — a spellement weapon must "
		+ "not make the bonus unconditional")
	# The name is the contract. If `Hero` renames the accessor, the `has_method` gate
	# starts answering false for everyone and the feature dies in silence.
	var hero_src: String = FileAccess.get_file_as_string(HERO_SCRIPT_PATH)
	_expect(hero_src.find("func affinity_element(") != -1,
		"Hero.gd still declares `affinity_element()` — the duck-typed contract this "
		+ "whole feature is asked through")
	_expect(hero_src.find("return _base_element") != -1,
		"Hero.affinity_element() still returns `_base_element` (not `_element`)")
	_completes("it_reads_the_class_element_not_the_equipped_one")


# ═════════════════════ 8. it reaches real hands, not just the unit fixture
## COVERAGE, AND THE ANTI-VACUITY GUARD FOR THE WHOLE FEATURE. A class must actually
## CARRY at least one damaging spell its own element amplifies, or the feature does
## nothing for it. A rule that is arithmetically perfect and fires for nobody is the
## failure mode this repo has a scar from — a comment describing scoring that was
## never wired.
##
## The exceptions are named in `UNPAID_CLASSES` rather than excused by a softer
## assertion, and the check runs BOTH WAYS: a listed class must still be unpaid, and
## an unlisted one must still be paid. Either drift is red.
##
## Also prints the table, because the interesting output of this suite is not "PASS",
## it is WHICH slots each class gets paid on and by how much.
func _test_every_class_amplifies_something_it_actually_carries() -> void:
	var classes_seen: int = 0
	for cls: int in range(CLASS_ELEMENTS.size()):
		var elem: int = CLASS_ELEMENTS[cls]
		var caster: _Affine = _affine(elem)
		var hand: Array = SpellLibrary.build_for_class(cls)
		var boosted: Array[String] = []
		for s: SpellDef in hand:
			if s.damage <= 0:
				continue
			if SpellCaster.affinity_mult(s, caster) > 1.0:
				var thrown: SpellDef = SpellCaster._blood_pacted(s, caster, null)
				boosted.append("%s %d->%d" % [s.id, s.damage, thrown.damage])
				# ⚠ THE PREDICATE IS NOT THE FEATURE. Asking `affinity_mult` alone
				# would keep answering 1.25 with the seam unplugged, and this whole
				# sweep would print `88->88` and report PASS — measured, on the red
				# run. The THROWN number is what the spectacle is handed, so that is
				# what is asserted.
				_expect(thrown.damage > s.damage,
					"%s's on-element '%s' is really thrown heavier (%d -> %d)"
						% [ClassInfo.name_for(cls), s.id, s.damage, thrown.damage])
		classes_seen += 1
		print("  [affinity] %-12s %-9s  %s" % [
			ClassInfo.name_for(cls), Elements.display_name(elem),
			(", ".join(boosted) if not boosted.is_empty() else "(nothing on-element)")])
		if UNPAID_CLASSES.has(cls):
			_expect(boosted.is_empty(),
				"%s is still the KNOWN unpaid class (it now amplifies %s) — the gap "
					% [ClassInfo.name_for(cls), ", ".join(boosted)]
					+ "recorded in UNPAID_CLASSES has been closed, so update that note")
		else:
			_expect(not boosted.is_empty(),
				"%s (%s) carries at least one damaging spell its own element amplifies "
					% [ClassInfo.name_for(cls), Elements.display_name(elem)]
					+ "— otherwise this class gets nothing from the feature at all. If "
					+ "that is intended, it belongs in UNPAID_CLASSES with a reason")
	_expect(classes_seen == CLASS_ELEMENTS.size(),
		"all %d classes were swept (swept %d)" % [CLASS_ELEMENTS.size(), classes_seen])
	# The exception list is a NOTE, not a licence: if it ever grew to most of the
	# roster the assertion above would be true of almost nobody and would stop meaning
	# "the feature reaches real hands".
	_expect(UNPAID_CLASSES.size() * 3 < CLASS_ELEMENTS.size(),
		"the unpaid-class exception list is still a minority (%d of %d) — past that "
			% [UNPAID_CLASSES.size(), CLASS_ELEMENTS.size()]
			+ "the feature is the exception rather than the rule")
	_completes("every_class_amplifies_something_it_actually_carries")


# ═══════════════════════════════════ 9. the element nobody carries
## Nine classes over eight elements: exactly one element belongs to no class, and a
## spell of that element is amplified by nobody. WIND, today.
##
## This is recorded rather than fixed. It is a real consequence — a Wind spell is
## strictly worse to author than any other — and it should be a decision somebody
## makes, not a surprise somebody discovers. If a class is ever re-elemented to WIND,
## this test goes red and points at the note.
##
## The frozen `CLASS_ELEMENTS` literal is checked against `Hero.CLASS_CONFIG` FIRST,
## so a re-elementing fails here loudly instead of being silently re-derived into a
## different orphan and reported as PASS.
func _test_wind_is_the_element_no_class_carries() -> void:
	var hero_script: GDScript = load(HERO_SCRIPT_PATH) as GDScript
	_expect(hero_script != null, "Hero.gd loaded (the class element table's source)")
	if hero_script == null:
		return
	var consts: Dictionary = hero_script.get_script_constant_map()
	_expect(consts.has("CLASS_CONFIG"),
		"Hero.gd still declares CLASS_CONFIG (the class element table moved)")
	if not consts.has("CLASS_CONFIG"):
		return
	var cfg: Dictionary = consts["CLASS_CONFIG"]
	_expect(cfg.size() == CLASS_ELEMENTS.size(),
		"the frozen table has a row per class (%d frozen, %d in CLASS_CONFIG)"
			% [CLASS_ELEMENTS.size(), cfg.size()])
	var covered: Dictionary = {}
	for cls: int in range(CLASS_ELEMENTS.size()):
		if not cfg.has(cls):
			_expect(false, "Hero.CLASS_CONFIG has a row for class %d" % cls)
			continue
		var live: int = int((cfg[cls] as Dictionary).get("element", -1))
		_expect(live == CLASS_ELEMENTS[cls],
			"%s is still %s in Hero.CLASS_CONFIG (it is now %s — the orphan element "
				% [ClassInfo.name_for(cls), Elements.display_name(CLASS_ELEMENTS[cls]),
					Elements.display_name(live)]
				+ "below has changed, and so has who the feature pays)")
		covered[CLASS_ELEMENTS[cls]] = true
	for e: int in ALL_ELEMENTS:
		if e == ORPHAN_ELEMENT:
			_expect(not covered.has(e),
				"%s is still the element NO class carries — a %s spell is amplified by "
					% [Elements.display_name(e), Elements.display_name(e)]
					+ "nobody. If a class now carries it, update ORPHAN_ELEMENT and "
					+ "decide whether that is intended")
		else:
			_expect(covered.has(e),
				"%s is carried by at least one class" % Elements.display_name(e))
	_completes("wind_is_the_element_no_class_carries")


# ══════════════════════════ 10. two classes may share an element
## ⚠ SHADOW IS SHARED (Shadowblade, Warlock) AND ARCANE IS SHARED (Arcanist,
## Swordsaint). THIS IS NOT A COLLISION AND MUST NOT BE "FIXED". Nine classes over
## eight elements cannot be a bijection; the shared pairs read as two takes on one
## element, not as a bug.
##
## Asserted positively so that someone "cleaning up" the duplicates has to delete a
## test that says, in words, why they are there — rather than finding an unwritten
## invariant and assuming it was an oversight.
func _test_a_shared_element_is_allowed_and_is_not_a_collision() -> void:
	var count: Dictionary = {}
	for e: int in CLASS_ELEMENTS:
		count[e] = int(count.get(e, 0)) + 1
	_expect(int(count.get(Elements.Element.SHADOW, 0)) == 2,
		"SHADOW is shared by exactly 2 classes (Shadowblade, Warlock) — got %d"
			% int(count.get(Elements.Element.SHADOW, 0)))
	_expect(int(count.get(Elements.Element.ARCANE, 0)) == 2,
		"ARCANE is shared by exactly 2 classes (Arcanist, Swordsaint) — got %d"
			% int(count.get(Elements.Element.ARCANE, 0)))
	# Both members of a shared pair get the SAME boost on the SAME spell: affinity is
	# a property of the element, never of the class, so there is no tiebreak anywhere.
	var probe: SpellDef = _spell(Elements.Element.SHADOW, 44)
	var rogue: float = SpellCaster.affinity_mult(probe, _affine(CLASS_ELEMENTS[1]))
	var lock: float = SpellCaster.affinity_mult(probe, _affine(CLASS_ELEMENTS[7]))
	_expect(is_equal_approx(rogue, lock) and rogue > 1.0,
		"Shadowblade and Warlock amplify the same SHADOW spell identically (%f vs %f)"
			% [rogue, lock])
	_completes("a_shared_element_is_allowed_and_is_not_a_collision")
