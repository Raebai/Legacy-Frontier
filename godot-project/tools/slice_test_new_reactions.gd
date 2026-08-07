# Run: godot --headless --path godot-project --script tools/slice_test_new_reactions.gd
#
# SIX MORE WAYS FOR TWO SPELLS TO MEET.
#
# Maker: *"i loved that fire ice efect that happened when they clasehd add that a lot
# as well like interactions and effects when certain spells interact"*.
#
# TWELVE OF THE TWENTY-ONE FORM BUCKETS WERE EMPTY, and the emptiest was also the
# busiest: `BEAM x PROJECTILE` had no row at all, so a bolt flew through a beam and
# neither noticed. Every caster throws bolts and four hold beams. `IMPACT x IMPACT`
# was empty too, with SIX registrants on that form.
#
# What was added, and why each one is reachable with spells that actually exist:
#   vaporise      BEAM x PROJ, any elements   a bolt dies in a beam
#   prism_burst   BEAM x PROJ, opposed        ...and opposed, it splits
#   annihilation  IMPACT x IMPACT, opposed    two blasts in the same place
#   banish        IMPACT x IMPACT, holy/shadow  the pair keeps its own story
#   bolt_fizzle   PROJ x IMPACT               a bolt caught in a detonation
#   molten_slag   BEAM(fire) x BARRIER(earth)  fire melts stone
#
# ⚠ TWO OF THEM ADD NO OUTCOME CODE, and that is the safest kind of new reaction. An
# outcome key with no arm in `ReactionOutcomes.apply` is WORSE than no row at all:
# `apply` returns true, the reactor memoizes the pair, and the two spells then pass
# through each other doing nothing forever. Pointing a new bucket at a proven arm
# cannot fall into that hole.
#
# ⚠ AND THE ROW THAT BROKE SOMETHING IS THE INTERESTING ONE. The opposed
# `IMPACT x IMPACT` row immediately stole HOLY-vs-SHADOW, which
# `slice10_test_natural_reactions` protects across every form pair those two schools
# can take — the light and the dark do not "cancel out", one banishes the other. That
# bucket was EMPTY when the sweep was written, so the pair passed there BY ABSENCE.
# The fix was the missing rung, not a narrower row, and `_test_ladder_unstolen` below
# is what stops the next row doing the same thing quietly.
#
# ⚠ LOADED BY PATH / duck-typed stubs, never by `class_name` for any spectacle: they
# reach the Sfx / Juice / CombatVfx autoloads, which do not exist during a `--script`
# run. `ReactionTable` is pure static data and is safe to name.
#
# ⚠ NEVER `failed += _test_x()`. Failures accumulate on `_fails`; every test records a
# COMPLETION SENTINEL so one that aborts half-way fails the suite by absence.
extends SceneTree

const F := ReactionTable.Form
const E := Elements.Element

const TESTS: Array[String] = [
	"a_bolt_dies_in_a_beam",
	"opposed_beam_and_bolt_split_instead",
	"a_caster_may_shoot_through_their_own_beam",
	"two_opposed_blasts_annihilate",
	"holy_and_shadow_still_banish_everywhere",
	"a_bolt_caught_in_a_blast_fizzles",
	"fire_melts_stone",
	"every_new_outcome_has_an_arm",
	"every_new_outcome_has_a_voice",
	"the_ladder_was_not_stolen",
	"the_rows_are_symmetric",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_vaporise()
	_test_prism()
	_test_own_beam()
	_test_impact_pair()
	_test_banish_survives()
	_test_bolt_in_blast()
	_test_molten()
	_test_arms_exist()
	_test_voices_exist()
	_test_ladder_unstolen()
	_test_symmetry()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("new_reactions: TEST DID NOT COMPLETE — %s (aborted part-way)" % name)
	if _fails == 0:
		print("new reaction tests: all PASS")
	else:
		printerr("new reaction tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("new_reactions: FAIL — %s" % what)


## ⚠ HEADINGS ARE NOT OPTIONAL FOR EVERY ROW. `require_head_on` fails CLOSED against
## a zero heading, so a call that omits them silently cannot match `bolt_fizzle`'s
## PROJ x PROJ rung — which is how the first draft of this file "discovered" that an
## existing reaction had stopped working when it had not.
func _match(fa: int, ea: int, fb: int, eb: int, rel: String = "different",
		wa: int = SpellTier.Tier.HEAVY, wb: int = SpellTier.Tier.HEAVY,
		ha: Vector2 = Vector2.ZERO, hb: Vector2 = Vector2.ZERO) -> Dictionary:
	return ReactionTable.match_rule(fa, ea, fb, eb, rel, wa, wb, ha, hb)


## Asserts the outcome AND the exact priority. The priority is what catches a row
## slipped in one point too high — the outcome alone would pass for a row that is
## quietly out-ranking something it should sit under.
func _assert_rule(label: String, want: String, want_pri: int,
		fa: int, ea: int, fb: int, eb: int, rel: String = "different") -> void:
	var r: Dictionary = _match(fa, ea, fb, eb, rel)
	var got: String = String(r.get("outcome", ""))
	_expect(got == want, "%s -> `%s` (got `%s`)" % [label, want, got])
	if got == want:
		_expect(int(r.get("priority", -1)) == want_pri,
			"%s sits at priority %d, not %d" % [label, int(r.get("priority", -1)), want_pri])


# --------------------------------------------------------------------------- 1
func _test_vaporise() -> void:
	_assert_rule("an arcane bolt into a lightning beam", "vaporise", 46,
		F.BEAM, E.LIGHTNING, F.PROJECTILE, E.ARCANE)
	# The bucket really was empty before, so the negative control is that the OLD
	# behaviour is gone rather than that the new one exists.
	var r: Dictionary = _match(F.BEAM, E.LIGHTNING, F.PROJECTILE, E.ARCANE)
	_expect(bool(r.get("consumes_b", false)) or bool(r.get("consumes_a", false)),
		"a vaporised bolt is not consumed by anything — it would fly on through")
	_completed["a_bolt_dies_in_a_beam"] = true


# --------------------------------------------------------------------------- 2
## The element story must OUTRANK the wildcard in its own bucket. If these two ever
## swap, every opposed meeting silently becomes the quiet one.
func _test_prism() -> void:
	_assert_rule("a fire bolt into an ice beam", "prism_burst", 92,
		F.BEAM, E.ICE, F.PROJECTILE, E.FIRE)
	var wild: Dictionary = _match(F.BEAM, E.LIGHTNING, F.PROJECTILE, E.ARCANE)
	var opp: Dictionary = _match(F.BEAM, E.ICE, F.PROJECTILE, E.FIRE)
	_expect(int(opp.get("priority", 0)) > int(wild.get("priority", 0)),
		"the opposed beam/bolt row no longer outranks the wildcard in its bucket — "
		+ "every opposed meeting would collapse into the quiet one")
	_completed["opposed_beam_and_bolt_split_instead"] = true


# --------------------------------------------------------------------------- 3
## ⚠ SHOOTING THROUGH YOUR OWN BEAM IS A COMBO, NOT A CLASH. Without the owner
## predicate this row would eat a caster's own bolts, which punishes exactly the play
## the reaction matrix exists to reward.
func _test_own_beam() -> void:
	var same: Dictionary = _match(F.BEAM, E.LIGHTNING, F.PROJECTILE, E.ARCANE, "same")
	_expect(String(same.get("outcome", "")) != "vaporise",
		"a caster's own bolt is vaporised by their own beam")
	_completed["a_caster_may_shoot_through_their_own_beam"] = true


# --------------------------------------------------------------------------- 4
func _test_impact_pair() -> void:
	_assert_rule("a fire blast over an ice blast", "mutual_annihilation", 91,
		F.IMPACT, E.FIRE, F.IMPACT, E.ICE)
	# NOT for two of the same school: two EARTH stomps overlapping is a co-op
	# picture, and cancelling teammates is the failure mode `bolt_fizzle`'s own
	# header spends a paragraph on.
	var same_school: Dictionary = _match(F.IMPACT, E.EARTH, F.IMPACT, E.EARTH)
	_expect(String(same_school.get("outcome", "")) != "mutual_annihilation",
		"two blasts of the SAME element annihilate — that cancels teammates")
	_completed["two_opposed_blasts_annihilate"] = true


# --------------------------------------------------------------------------- 5
## THE REGRESSION THIS COMMIT CAUSED AND FIXED, stated directly. Swept over every
## form pair, exactly as `slice10_test_natural_reactions` does, because the failure
## was that one uncovered combination existed at all.
func _test_banish_survives() -> void:
	_assert_rule("a holy blast over a shadow blast", "banish", 93,
		F.IMPACT, E.HOLY, F.IMPACT, E.SHADOW)
	var generic: Array[String] = ["mutual_annihilation", "overpower", "breach",
		"barrier_blocks", "carve", "vaporise"]
	for fa: int in [F.BEAM, F.PROJECTILE, F.IMPACT, F.BARRIER]:
		for fb: int in [F.BEAM, F.PROJECTILE, F.IMPACT, F.FIELD]:
			var got: String = String(_match(fa, E.HOLY, fb, E.SHADOW).get("outcome", ""))
			_expect(not generic.has(got),
				"holy(form %d) vs shadow(form %d) reads as a generic clash (`%s`) — "
					% [fa, fb, got] + "the light and the dark do not cancel out")
	_completed["holy_and_shadow_still_banish_everywhere"] = true


# --------------------------------------------------------------------------- 6
func _test_bolt_in_blast() -> void:
	_assert_rule("a bolt caught in a blast", "bolt_fizzle", 42,
		F.PROJECTILE, E.ARCANE, F.IMPACT, E.EARTH)
	# The BLAST survives: a volume is not cancelled by a point passing through it.
	var r: Dictionary = _match(F.PROJECTILE, E.ARCANE, F.IMPACT, E.EARTH)
	var swapped: bool = bool(r.get("swapped", false))
	# `consumes_a` names the PROJECTILE side of the authored row; `swapped` tells us
	# which way round the caller asked. Read it through the helper, never directly.
	_expect(ReactionTable.consumes_caller(r, 0 if not swapped else 1),
		"the bolt survives being caught in a detonation")
	_expect(not ReactionTable.consumes_caller(r, 1 if not swapped else 0),
		"the BLAST is consumed by a bolt flying into it")
	_completed["a_bolt_caught_in_a_blast_fizzles"] = true


# --------------------------------------------------------------------------- 7
func _test_molten() -> void:
	_assert_rule("a fire lance on a rock wall", "molten_slag", 86,
		F.BEAM, E.FIRE, F.BARRIER, E.EARTH)
	# The pair was REACHABLE and fell through to the weight contest before, so the
	# negative control is that it no longer settles on tier.
	var r: Dictionary = _match(F.BEAM, E.FIRE, F.BARRIER, E.EARTH,
		"different", SpellTier.Tier.QUICK, SpellTier.Tier.ULT)
	_expect(String(r.get("outcome", "")) == "molten_slag",
		"fire melting stone still depends on which side is heavier — the element "
		+ "story must outrank the weight story")
	# ...and it does NOT melt ICE or HOLY barriers, which have their own rows.
	_expect(String(_match(F.BEAM, E.FIRE, F.BARRIER, E.ICE).get("outcome", ""))
		== "shatter_ice_barrier", "fire on an ice wall stopped shattering it")
	_completed["fire_melts_stone"] = true


# --------------------------------------------------------------------------- 8
## ⚠ THE ONE THAT PREVENTS THE WORST FAILURE IN THIS SYSTEM. A row whose outcome has
## no arm makes `apply` return true, the reactor memoize the pair, and the two spells
## pass through each other doing nothing — silently, forever. Checked by source text
## because `ReactionOutcomes` reaches four autoloads and cannot be loaded here.
func _test_arms_exist() -> void:
	var whole: String = FileAccess.get_file_as_string(
		"res://scripts/combat/ReactionOutcomes.gd")
	_expect(not whole.is_empty(), "could not read ReactionOutcomes.gd")
	# ⚠ SCOPED TO `apply`'s BODY, and matched WITHOUT the trailing colon. Several
	# outcomes deliberately share one arm (`"overpower", "breach", "barrier_blocks",
	# ... : return _contest(ctx)`), so a per-key `"name":` search reports five
	# perfectly-wired outcomes as missing. Scoping to the dispatch keeps a name that
	# appears only in a comment from passing.
	var from: int = whole.find("func apply(")
	var to: int = whole.find("
	return true", from)
	_expect(from >= 0 and to > from, "could not locate ReactionOutcomes.apply")
	var src: String = whole.substr(from, to - from) if from >= 0 and to > from else ""
	var seen: Dictionary = {}
	for row: Dictionary in ReactionTable.rules():
		var out: String = String(row.get("outcome", ""))
		if out == "" or out == "none" or seen.has(out):
			continue
		seen[out] = true
		_expect(src.contains("\"%s\"" % out),
			"outcome `%s` has a ROW but no arm in ReactionOutcomes.apply — the "
				% out + "reactor will memoize the pair and the two spells will pass "
				+ "through each other doing nothing")
	_expect(seen.size() >= 14,
		"only %d distinct outcomes found — the scan has stopped working" % seen.size())
	_completed["every_new_outcome_has_an_arm"] = true


# --------------------------------------------------------------------------- 9
## Silence is legal; a NEAR-MISS is not. An outcome absent from the table resolves to
## "" and plays nothing, which is indistinguishable from a missing recording.
func _test_voices_exist() -> void:
	for out: String in ["vaporise", "prism_burst", "molten_slag"]:
		_expect(Sfx.REACTION_SOUND.has(out),
			"outcome `%s` has no entry in Sfx.REACTION_SOUND — it will be silent, "
				% out + "and silent-by-omission is indistinguishable from broken")
	_completed["every_new_outcome_has_a_voice"] = true


# --------------------------------------------------------------------------- 10
## ⚠ THE ASSERTION THAT MATTERS MOST IN THIS FILE. Every pre-existing outcome in
## every bucket these rows touch, re-asserted by NAME and by PRIORITY. This is what
## catches a new row stealing an old story — which is exactly what happened once
## already in this commit.
func _test_ladder_unstolen() -> void:
	_assert_rule("opposed beams still fuse", "hollow_purple", 100,
		F.BEAM, E.FIRE, F.BEAM, E.ICE, "same")
	_assert_rule("same-element beams still resonate", "beam_resonance", 60,
		F.BEAM, E.FIRE, F.BEAM, E.FIRE, "same")
	_assert_rule("equal beams still annihilate", "mutual_annihilation", 55,
		F.BEAM, E.ARCANE, F.BEAM, E.LIGHTNING)
	# Head-on, because that row requires it and fails closed without headings.
	var two_bolts: Dictionary = _match(F.PROJECTILE, E.ARCANE, F.PROJECTILE,
		E.LIGHTNING, "different", SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY,
		Vector2.RIGHT, Vector2.LEFT)
	_expect(String(two_bolts.get("outcome", "")) == "bolt_fizzle",
		"two head-on bolts stopped fizzling (got `%s`)" % two_bolts.get("outcome", ""))
	_expect(int(two_bolts.get("priority", -1)) == 54,
		"the two-bolt fizzle moved off priority 54")
	_assert_rule("a fire beam still shatters ice", "shatter_ice_barrier", 90,
		F.BEAM, E.FIRE, F.BARRIER, E.ICE)
	_assert_rule("lightning still grounds out on stone", "ground_out", 82,
		F.BEAM, E.LIGHTNING, F.BARRIER, E.EARTH)
	_assert_rule("a bolt still shrapnels an ice wall", "shrapnel_cone", 88,
		F.PROJECTILE, E.ARCANE, F.BARRIER, E.ICE)
	_assert_rule("a fire beam still steams a frost field", "steam_cloud", 80,
		F.BEAM, E.FIRE, F.FIELD, E.ICE)
	_assert_rule("holy still banishes a shadow field", "banish", 81,
		F.BEAM, E.HOLY, F.FIELD, E.SHADOW)
	_assert_rule("two fields still merge", "field_merge", 50,
		F.FIELD, E.ICE, F.FIELD, E.ICE)
	_completed["the_ladder_was_not_stolen"] = true


# --------------------------------------------------------------------------- 11
## `match_rule` tries both orderings and sets `swapped` on the winner, so a row
## authored one way round must fire the other way round too. A row that only matched
## in the order it was written would fire about half the time, which is the hardest
## kind of bug to see from the outside.
func _test_symmetry() -> void:
	var pairs: Array = [
		["vaporise", F.PROJECTILE, E.ARCANE, F.BEAM, E.LIGHTNING],
		["prism_burst", F.PROJECTILE, E.FIRE, F.BEAM, E.ICE],
		["molten_slag", F.BARRIER, E.EARTH, F.BEAM, E.FIRE],
		["bolt_fizzle", F.IMPACT, E.EARTH, F.PROJECTILE, E.ARCANE],
		["banish", F.IMPACT, E.SHADOW, F.IMPACT, E.HOLY],
	]
	for p: Array in pairs:
		var got: String = String(_match(int(p[1]), int(p[2]), int(p[3]), int(p[4]))
			.get("outcome", ""))
		_expect(got == String(p[0]),
			"`%s` does not fire with the sides swapped (got `%s`) — it would only "
				% [String(p[0]), got] + "react about half the time")
	_completed["the_rows_are_symmetric"] = true
