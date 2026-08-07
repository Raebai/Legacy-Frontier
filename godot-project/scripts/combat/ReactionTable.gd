class_name ReactionTable
extends RefCounted
## What happens when two live spell effects meet — authored as DATA.
##
## Keyed on physical FORM x an element predicate, deliberately NOT on
## SpellDef.Kind. Kind has 18 append-only values, so keying on it would give a
## mostly-empty 18x18x8x8 space in which a newly-added spell inherits NOTHING —
## exactly the outcome the curated-reaction design exists to avoid. Six forms
## give 21 ordered buckets, and a spell added next month with effect="fire"
## shatters ice walls with no code edit at all.
##
## Element predicates are wildcards by default: an empty element list matches any
## element, which is how the generic fallback rows are written. `require_opposed`
## covers all four opposing pairs with a single row rather than four near-copies.
##
## WEIGHT is the second axis, added for "two evenly matched spells annihilate, a
## heavy one just wins". It is a PREDICATE (`require_weight`) exactly like
## `require_opposed` and `require_owner`, never a branch in the reactor — the
## whole point of this file is that "an ult overpowers a jab" is a ROW someone can
## read, argue with and retune, not control flow buried in the detector. Weight
## itself is not redefined here: it is SpellTier's QUICK/HEAVY/ULT shelf, so a
## spell cannot weigh one thing in the loadout and another in a clash.

## The physical shape a spell presents to the world, derived from its Kind.
## Lossy on purpose — reactions care whether a thing is a lance, a barrier or a
## lingering field, not which of five lances it is.
enum Form { BEAM, BARRIER, FIELD, PROJECTILE, IMPACT, AURA }

## How opposed two headings must be for a `require_head_on` row to fire: the dot of
## the two normalised directions must be AT OR BELOW this. -0.6 is about 127 degrees
## of opposition, i.e. genuinely oncoming rather than merely converging.
##
## THE DIAL. Toward -1.0 means "only a dead-centre collision counts" (rarer, cleaner);
## toward 0.0 means "anything not travelling together counts" (commoner, and at 0.0 it
## is the unguarded row that makes ranged mirror matches unwinnable). This is a FEEL
## number and it has not been played yet.
const HEAD_ON_DOT: float = -0.6

## Elements that annihilate rather than merely mix. One row keyed on
## `require_opposed` then covers fire/ice, lightning/earth, shadow/holy and
## arcane/wind without four near-identical entries.
const OPPOSED: Dictionary = {
	Elements.Element.FIRE: Elements.Element.ICE,
	Elements.Element.ICE: Elements.Element.FIRE,
	Elements.Element.LIGHTNING: Elements.Element.EARTH,
	Elements.Element.EARTH: Elements.Element.LIGHTNING,
	Elements.Element.SHADOW: Elements.Element.HOLY,
	Elements.Element.HOLY: Elements.Element.SHADOW,
	Elements.Element.ARCANE: Elements.Element.WIND,
	Elements.Element.WIND: Elements.Element.ARCANE,
}


static func opposed(a: int, b: int) -> bool:
	return OPPOSED.get(a, -1) == b


## Kind -> Form. Anything unrecognised is an IMPACT, which is the least
## surprising default: a new spell reacts like a hit rather than silently
## matching nothing at all.
static func form_for_kind(kind: int) -> int:
	match kind:
		SpellDef.Kind.BEAM, SpellDef.Kind.DIVINE_RAY:
			return Form.BEAM
		SpellDef.Kind.WALL, SpellDef.Kind.ICE_WALL, SpellDef.Kind.PILLAR:
			return Form.BARRIER
		SpellDef.Kind.ZONE:
			return Form.FIELD
		SpellDef.Kind.BOULDER, SpellDef.Kind.MISSILES, SpellDef.Kind.THROWN_ANCHOR, \
		SpellDef.Kind.CRAWLER:
			return Form.PROJECTILE
		SpellDef.Kind.TETHER:
			return Form.AURA
	return Form.IMPACT


## Canonical bucket for an unordered form pair, so (BEAM, BARRIER) and
## (BARRIER, BEAM) land in the same place and each rule is written once.
static func bucket_key(form_a: int, form_b: int) -> int:
	return (mini(form_a, form_b) << 4) | maxi(form_a, form_b)


## One authored rule. Plain dictionaries rather than a Resource so the table is
## readable in one screen and diffable in review; it can be promoted to .tres
## files later without changing the lookup.
##   outcome        : dispatch key the reactor turns into an effect
##   elements_a/b   : allowed elements, [] = any. Matched against whichever side
##                    sits on form_a, and BOTH orderings are tried.
##   require_opposed: only fires when the two elements annihilate
##   require_same   : only fires when the two elements match
##   require_owner  : "same"      — one caster combining their OWN two spells
##                    "different" — two casters' effects meeting
##                    "any"       — either (the default)
##                  Ownership is a PREDICATE like any other, so "combine your own
##                  spells" and "your beam meets the boss's" are two rows of data
##                  rather than a branch in the reactor.
##   require_weight : "equal"     — the two spells are evenly matched
##                                  (SpellTier.WEIGHT_MATCH_TOLERANCE apart)
##                    "a_heavier" — the side sitting on form_a outweighs the other
##                    "b_heavier" — the mirror
##                    "any"       — weight is irrelevant to this row (the default)
##                  Both orderings of a pair are tried, so "a_heavier" written
##                  ONCE covers "whichever of these two is the heavier" — the row
##                  simply describes the heavy side as form_a. "b_heavier" exists
##                  so an asymmetric bucket (BEAM vs BARRIER) can be written in
##                  whichever direction reads naturally, not because it is needed.
##                  A row with a weight predicate NEVER matches when the caller
##                  supplied no weights: see match_rule.
##   priority       : higher wins when several rules match a pair
##   consumes_a/b   : the effect is spent by the reaction. ⚠ These name the RULE's
##                  own sides, which are not necessarily the caller's — the row
##                  may have matched with its sides swapped. Read them through
##                  consumes_caller(), never directly.
##   swapped        : filled in by match_rule, not by the author. True when the
##                  winning row matched with its sides reversed.
static func _rule(outcome: String, form_a: int, form_b: int, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = {
		"outcome": outcome,
		"form_a": form_a,
		"form_b": form_b,
		"elements_a": opts.get("elements_a", []),
		"elements_b": opts.get("elements_b", []),
		"require_opposed": opts.get("require_opposed", false),
		"require_same": opts.get("require_same", false),
		"require_owner": opts.get("require_owner", "any"),
		"require_weight": opts.get("require_weight", "any"),
		# Both effects must be travelling INTO each other. See HEAD_ON_DOT.
		"require_head_on": opts.get("require_head_on", false),
		"priority": opts.get("priority", 0),
		"consumes_a": opts.get("consumes_a", false),
		"consumes_b": opts.get("consumes_b", false),
		"radius": opts.get("radius", 0.0),
		"damage": opts.get("damage", 0),
		"suppress": opts.get("suppress", false),
		"swapped": false,
	}
	return r


## The authored matrix. Headliners first — these are the ones that must land.
##
## THE PRIORITY LADDER, and the one sentence that explains it —
## **the ELEMENT story outranks the WEIGHT story.** What two spells are made of is
## the thing the player picked, learned and built a loadout around; how much they
## weigh is the tiebreak for everything the elements have nothing to say about.
## Bands:
##   100-95  headline FUSIONS (Hollow Purple). Deliberately weight-blind: a
##           signature combo that only fired when the shelves happened to line up
##           would be a signature combo the player cannot rely on, which is the
##           worst possible property for one.
##    90-70  ELEMENTAL counters and field reactions (fire shatters ice, earth
##           grounds lightning, fire boils frost, holy BANISHES shadow, stone rams
##           ice). Also weight-blind, same reason: bringing the right element is
##           supposed to BE the answer, and a jab of fire should still pop an ice
##           wall. Two shapes of ordering matter inside this band and both are
##           written at their rows: a SPECIFIC element pair must outrank a WILDCARD
##           one that would otherwise swallow it (banish 79 over void_charged 70),
##           and a row authored for several FORMS steps down one point per form so
##           the family reads in order (beam, then projectile, then impact) even
##           though separate buckets mean they never actually compete.
##       60  same-element reinforcement (beam_resonance).
##    55-44  WEIGHT contests — everything the elements left undecided. Evenly
##           matched spells annihilate; a heavier one eats the lighter and walks
##           through.
##       40  carve — the authored exception where a barrier is porous.
##    32-29  the WARD rungs. A protective spell eats what a plain wall would only
##           block, and unlike a wall it is not spent doing it — it is DEGRADED,
##           which it expresses by getting lighter (see the seam note below). They
##           sit under breach on purpose: a ward that could absorb something
##           heavier than itself would have no counter at all.
##       20  a barrier as the wall of last resort: it stops what it is not
##           outmatched by.
##       10  explicit silence.
static func rules() -> Array:
	var E := Elements.Element
	return [
		# HOLLOW PURPLE, the SELF-COMBO — the headline path. ONE caster fires two
		# opposing-element spells inside a short window and fuses them: both are
		# absorbed into a circle in front of them and the result erupts along
		# their aim.
		#
		# Same-owner is the PRIMARY row because the cross-caster version is
		# almost unreachable: it would need two casters, opposing elements,
		# simultaneous casts AND the beams physically overlapping. As a
		# self-combo it is available in every fight, it rewards loadout planning,
		# and it turns four equipped spells into a combo web.
		_rule("hollow_purple", Form.BEAM, Form.BEAM, {
			"require_opposed": true, "require_owner": "same", "priority": 100,
			"consumes_a": true, "consumes_b": true, "radius": 190.0, "damage": 150,
		}),
		# ...and a genuine cross-caster crossing still works, as the rarer
		# surprise: co-op partners, or a boss beam meeting the hero's. Same
		# outcome, staged at the geometric crossing instead of in front of a
		# caster. One field of data is the whole difference.
		_rule("hollow_purple", Form.BEAM, Form.BEAM, {
			"require_opposed": true, "require_owner": "different", "priority": 95,
			"consumes_a": true, "consumes_b": true, "radius": 190.0, "damage": 150,
		}),
		# Two beams of the SAME element reinforce instead of annihilating — the
		# constructive case matters, or players learn that every meeting is
		# destruction and stop experimenting.
		# `require_owner: "same"` — reinforcement is now a SELF-combo reward, not
		# what happens when two duellists happen to pick the same spell. The maker's
		# instruction was explicit and repeated: "if any two of these line spells hit
		# each other they should EXPLODE and go away." Without this predicate the
		# single most likely duel case — a MIRROR MATCH, both sides on the same beam
		# — resolved to resonance, which consumes nothing and reads on screen as
		# "nothing happened". The constructive case still exists and still matters;
		# it now belongs to one caster crossing their own two beams, where it is a
		# discovery rather than an anticlimax.
		_rule("beam_resonance", Form.BEAM, Form.BEAM, {
			"require_same": true, "require_owner": "same",
			"priority": 60, "damage": 40,
		}),
		# THE CLASH. Two beams that are neither the same element nor opposing ones
		# have no elemental story to tell, so the only question left is which is
		# the bigger spell — and when neither is, they blow each other apart. This
		# is the common, readable case: most element pairs are neutral, so "beams
		# meeting cancel" is what a player actually learns, with resonance and
		# Hollow Purple as the two exceptions they discover afterwards.
		#
		# require_owner "different" is LOAD-BEARING, not decoration. Without it,
		# firing two of your own beams in quick succession — the exact double-tap
		# the Hollow Purple self-combo teaches you to do — would cancel both of
		# them whenever the elements happened not to oppose. Punishing the player
		# for attempting the headline combo is the one outcome this row must not
		# have. Two casters' beams meeting is the fight this is for.
		_rule("mutual_annihilation", Form.BEAM, Form.BEAM, {
			"require_weight": "equal", "require_owner": "different", "priority": 55,
			"consumes_a": true, "consumes_b": true, "radius": 150.0, "damage": 30,
		}),
		# TWO BOLTS MEETING HEAD-ON POP EACH OTHER. Maker: "if two defaults hit each
		# other they can potentially fizzle out."
		#
		# The same sentence the row above already tells for BEAMS, told for the shape
		# players actually throw all day. The bolt has implemented the full participant
		# contract the whole time — it registers on its first physics frame and answers
		# all seven methods — so nothing was missing except a row for its own bucket:
		# every authored PROJECTILE rule paired it with a BARRIER, so the pair died at
		# the reactor's sparse-matrix gate before any geometry ran.
		#
		# ⚠ `require_head_on` IS WHAT MAKES THIS SHIPPABLE. Cast cooldowns run 0.22-0.45 s,
		# so a ranged duel is two people throwing 2-4 bolts a second down a shared lane.
		# A bare PROJECTILE x PROJECTILE row would make ranged MIRROR MATCHES
		# unwinnable — every shot meets a shot, nobody lands anything, and the answer
		# becomes "stop shooting". It would also cancel two co-op teammates spraying the
		# same corridor, which friendly fire already makes a common picture. Requiring
		# genuine opposition means shooting AT each other cancels while shooting PAST
		# each other, ALONGSIDE a teammate, or AT anything heavier all still land.
		#
		# `damage: 0` on purpose — two cancelled jabs are a pop, not a splash. Priority
		# one under the beam twin so the ladder reads in weight order.
		_rule("bolt_fizzle", Form.PROJECTILE, Form.PROJECTILE, {
			"require_weight": "equal", "require_owner": "different",
			"require_head_on": true, "priority": 54,
			"consumes_a": true, "consumes_b": true, "radius": 46.0, "damage": 0,
		}),
		# ══ FIVE MORE WAYS FOR TWO SPELLS TO MEET ═══════════════════════════════
		# Maker: *"i loved that fire ice efect that happened when they clasehd add
		# that a lot as well like interactions and effects when certain spells
		# interact"*.
		#
		# TWELVE OF THE TWENTY-ONE FORM BUCKETS WERE EMPTY, and the emptiest one was
		# also the busiest: `BEAM x PROJECTILE` had no row at all, so a bolt flew
		# through a beam and neither noticed. Every caster in the game throws bolts
		# and four of them hold beams, which makes it the single most-often-missed
		# meeting on the board. `IMPACT x IMPACT` was empty too, with SIX registrants
		# on that form.
		#
		# Two of the five below need no new outcome code at all — they point existing
		# arms at buckets that had nothing. That is deliberate: an outcome key with no
		# arm in `ReactionOutcomes.apply` is WORSE than no row, because `apply`
		# returns true, the reactor memoizes the pair, and the two spells then pass
		# through each other doing nothing at all. Reusing a proven arm cannot fall
		# into that hole.

		# A BOLT MEETS A BEAM. The beam is a sustained channel and the bolt is a
		# thrown thing, so this is not a trade — the bolt is vaporised and the beam
		# carries on. Weight-blind on purpose: even an ult bolt is a discrete object
		# passing through a continuous one.
		#
		# `require_owner: "different"`, because a caster firing a bolt through their
		# own beam is a combo, not a clash, and eating it would punish exactly the
		# play the reaction matrix exists to reward.
		_rule("vaporise", Form.BEAM, Form.PROJECTILE, {
			"require_owner": "different", "priority": 46,
			"consumes_b": true, "radius": 60.0, "damage": 0,
		}),
		# ...unless the two are OPPOSED, in which case the meeting is the event. Sits
		# in the 90s with the other element stories, above the weight-blind row above
		# it, because a specific element pair must outrank a wildcard in its bucket.
		_rule("prism_burst", Form.BEAM, Form.PROJECTILE, {
			"require_opposed": true, "priority": 92,
			"consumes_b": true, "radius": 170.0, "damage": 60,
		}),
		# TWO BLASTS GOING OFF IN THE SAME PLACE. Six spectacles register as IMPACT
		# and none of them could ever meet. Opposed only — two EARTH stomps
		# overlapping is a co-op picture, not a fusion.
		# ⚠ HOLY MEETING SHADOW KEEPS ITS OWN STORY, WHEREVER THEY MEET, and this row
		# exists because the one below broke that. `slice10_test_natural_reactions`
		# sweeps every form pair those two schools can currently take and asserts none
		# of them falls through to a generic clash — the light and the dark do not
		# "cancel out", one BANISHES the other. `IMPACT x IMPACT` was empty when that
		# sweep was written, so the pair was silent there and passed by absence; the
		# generic opposed row below would have made it read as a mutual annihilation.
		#
		# Above 91 so it wins its own bucket, exactly as `banish` (81/79) sits above
		# `void_charged` (70) in the field buckets.
		_rule("banish", Form.IMPACT, Form.IMPACT, {
			"elements_a": [Elements.Element.HOLY], "elements_b": [Elements.Element.SHADOW],
			"priority": 93, "consumes_b": true, "damage": 34,
		}),
		_rule("mutual_annihilation", Form.IMPACT, Form.IMPACT, {
			"require_opposed": true, "require_owner": "different", "priority": 91,
			"consumes_a": true, "consumes_b": true, "radius": 175.0, "damage": 45,
		}),
		# A BOLT CAUGHT IN A DETONATION. The blast is a volume and the bolt is a point
		# passing through it, so the bolt loses and the blast is untouched. Reuses the
		# fizzle arm, which is exactly this shape.
		_rule("bolt_fizzle", Form.PROJECTILE, Form.IMPACT, {
			"require_owner": "different", "priority": 42,
			"consumes_a": true, "radius": 52.0, "damage": 0,
		}),
		# FIRE MELTS STONE. The first FIRE/EARTH row in the table — the pair was
		# reachable (`infernal_lance` against `rock_wall` / `rock_pillar`) and fell
		# through to the weight contest, so a lance and a boulder wall settled it by
		# tier rather than by being fire and rock. Same band as the other "this
		# element beats that one" rows.
		_rule("molten_slag", Form.BEAM, Form.BARRIER, {
			"elements_a": [Elements.Element.FIRE], "elements_b": [Elements.Element.EARTH],
			"priority": 86, "consumes_b": true, "radius": 140.0, "damage": 38,
		}),
		# ...and the whole point of weight mattering: a heavier spell does NOT
		# trade with a lighter one. It eats it and keeps going. An ult that could
		# be cancelled by a jab would not feel like an ult.
		_rule("overpower", Form.BEAM, Form.BEAM, {
			"require_weight": "a_heavier", "require_owner": "different", "priority": 50,
			"consumes_b": true, "radius": 110.0, "damage": 20,
		}),
		# Fire (or holy) light against an ice barrier shatters it.
		_rule("shatter_ice_barrier", Form.BEAM, Form.BARRIER, {
			"elements_a": [E.FIRE, E.HOLY], "elements_b": [E.ICE],
			"priority": 90, "consumes_b": true, "radius": 120.0, "damage": 30,
		}),
		# ...and the same rule for a physical hit, so a boulder works like a beam.
		_rule("shatter_ice_barrier", Form.IMPACT, Form.BARRIER, {
			"elements_b": [E.ICE], "priority": 85, "consumes_b": true,
			"radius": 120.0, "damage": 30,
		}),
		_rule("shrapnel_cone", Form.PROJECTILE, Form.BARRIER, {
			"elements_b": [E.ICE], "priority": 88, "consumes_b": true,
			"radius": 140.0, "damage": 45,
		}),
		# Fire into a frost field boils it into steam — the one reaction whose
		# payoff is VISION rather than damage.
		_rule("steam_cloud", Form.BEAM, Form.FIELD, {
			"elements_a": [E.FIRE], "elements_b": [E.ICE],
			"priority": 80, "consumes_b": true, "radius": 160.0,
		}),
		_rule("steam_cloud", Form.IMPACT, Form.FIELD, {
			"elements_a": [E.FIRE], "elements_b": [E.ICE],
			"priority": 78, "consumes_b": true, "radius": 160.0,
		}),
		# Lightning through a frost field conducts harder.
		_rule("supercharge", Form.BEAM, Form.FIELD, {
			"elements_a": [E.LIGHTNING], "elements_b": [E.ICE],
			"priority": 75, "damage": 55,
		}),
		# ...and the same for a BLAST detonating inside one, which is the half a
		# player can actually reach today: only the Stormcaller's ult is a lightning
		# BEAM, but every hero's Q blast carries their OWN element, so dropping it
		# into the Blizzard sitting in that same kit's control slot is the set-up
		# this pair has always been describing. One point under the beam row purely
		# so the ladder reads in order; they are different buckets and never compete.
		#
		# Both rows spend NOTHING. The field keeps standing and the attack carries
		# on — the ice is simply a very bad place to be for one moment, which is what
		# makes this the reaction you WANT to walk into your opponent.
		_rule("supercharge", Form.IMPACT, Form.FIELD, {
			"elements_a": [E.LIGHTNING], "elements_b": [E.ICE],
			"priority": 73, "damage": 55,
		}),
		# ── HOLY vs SHADOW ─────────────────────────────────────────────────────
		# The maker named this pair specifically, and the answer it wanted is NOT
		# another clash. Everything else in this table meets and detonates: two
		# beams annihilate, a projectile shrapnels a wall, a blast is void-charged.
		# Light meeting dark is the one pairing where an explosion is the WRONG
		# picture — dark is not a substance that blows up, it is an absence that
		# stops being there. So `banish` is an ERASURE: the field is unmade, nothing
		# is thrown, nothing is shoved, and what is left is a lit floor. It is the
		# only outcome in the file with zero knockback, on purpose (see _banish).
		#
		# It is also deliberately ASYMMETRIC, which is the second half of the read.
		# Light UNMAKES dark (here); dark SHATTERS light (the shatter_ward rows
		# below, now including impacts). Neither side ever trades with the other, and
		# neither reads like the generic contest — so a player who has seen one
		# holy/shadow meeting can predict the rest without being told. Opposed
		# BEAM x BEAM is untouched and still fuses into Hollow Purple: that stays the
		# headline, and these are what the pair does everywhere ELSE.
		#
		# ⚠ IT MUST OUTRANK void_charged (70), which is wildcard on the attacking
		# side and would otherwise swallow this: a pillar of holy light falling into
		# a void field would get CORRUPTED by it and invert into a pull, which is the
		# exact opposite of the sentence being told here.
		#
		# WHY ONLY BEAM AND IMPACT, and no PROJECTILE twin — the rule that also
		# governs steam_cloud, stated once here because both decisions turn on it:
		# **a field is answered by things that FILL a volume, never by things that
		# merely PASS THROUGH it.** A beam floods the space with light and a blast
		# occupies it; a bolt is a point crossing it and has no business deleting a
		# whole control spell. That distinction is physical rather than defensive,
		# and it happens to keep a free, spammable basic cast from erasing a HEAVY
		# field on repeat — which a projectile row would have done.
		#
		# The BEAM row is unreachable TODAY (no holy beam implements the participant
		# contract yet — Judgment is a DIVINE_RAY whose spectacle has not adopted it)
		# and is authored anyway: that is the whole promise of keying on FORM, and it
		# costs one row rather than a code edit later.
		_rule("banish", Form.BEAM, Form.FIELD, {
			"elements_a": [E.HOLY], "elements_b": [E.SHADOW],
			"priority": 81, "consumes_b": true, "damage": 34,
		}),
		_rule("banish", Form.IMPACT, Form.FIELD, {
			"elements_a": [E.HOLY], "elements_b": [E.SHADOW],
			"priority": 79, "consumes_b": true, "damage": 34,
		}),
		# Anything detonating inside a void field is void-charged: the knockback
		# inverts into a pull. Wildcard on the attacking side, which is why `banish`
		# above has to sit over it rather than beside it.
		_rule("void_charged", Form.IMPACT, Form.FIELD, {
			"elements_b": [E.SHADOW], "priority": 70, "radius": 175.0, "damage": 40,
		}),
		# Earth grounds out lightning — a barrier that genuinely counters a school.
		_rule("ground_out", Form.BEAM, Form.BARRIER, {
			"elements_a": [E.LIGHTNING], "elements_b": [E.EARTH],
			"priority": 82, "consumes_a": true,
		}),
		# HOW A WALL DEFENDS, in three rungs. One story, not two systems: a barrier
		# stops whatever it is not outmatched by. Which rung you get is decided
		# purely by weight, because the elemental counters above (fire/holy shatter
		# ice, earth grounds lightning, a projectile shrapnels ice) have already
		# taken every pairing where the material itself is the answer.
		#
		# Rung 1 — a HEAVIER spell simply destroys the barrier and carries on. This
		# is what stops walls from being a hard counter to ults, which is the
		# failure mode a defensive spell most easily falls into.
		_rule("breach", Form.BEAM, Form.BARRIER, {
			"require_weight": "a_heavier", "priority": 45,
			"consumes_b": true, "radius": 140.0, "damage": 40,
		}),
		# ...and the same for a thrown thing, so a hurled boulder behaves like a
		# beam without a second story. One point lower only so the ladder stays
		# readable when both somehow apply; they never do (different buckets).
		_rule("breach", Form.PROJECTILE, Form.BARRIER, {
			"require_weight": "a_heavier", "priority": 44,
			"consumes_b": true, "radius": 140.0, "damage": 40,
		}),
		# Rung 2 — the authored exception. An EVENLY MATCHED beam boring into stone
		# gets through without breaking the wall: rock is porous to a sustained
		# beam in a way ice and force barriers are not. `require_weight` "equal" is
		# what keeps this from being a second, competing answer to "does the spell
		# get through" — an under-weight beam falls to rung 3 like everything else.
		_rule("carve", Form.BEAM, Form.BARRIER, {
			"elements_b": [E.EARTH], "require_weight": "equal",
			"priority": 40, "damage": 25,
		}),
		# Rung 3 — the wall of last resort, and the row that makes a barrier worth
		# casting at all: anything that has not out-weighed it and has no elemental
		# answer to it is STOPPED, and spent. Wildcard on both elements on purpose;
		# this is the floor of the BEAM/PROJECTILE-vs-BARRIER bucket, so every
		# future spell of those shapes inherits "walls block me" for free.
		_rule("barrier_blocks", Form.BEAM, Form.BARRIER, {
			"priority": 20, "consumes_a": true, "radius": 80.0,
		}),
		_rule("barrier_blocks", Form.PROJECTILE, Form.BARRIER, {
			"priority": 20, "consumes_a": true, "radius": 80.0,
		}),
		# IMPACT is deliberately NOT given a blocks/breach rung. A blast is not a
		# thing travelling toward a wall that the wall can be in the way of — a
		# meteor landing next to a barrier should crack it, which is what the
		# shatter_ice_barrier IMPACT row already does, not be swallowed by it.
		#
		# ── SEAM: PROTECTIVE SPELLS ────────────────────────────────────────────
		# Wards / shields / counterspells are coming, and they need NO new
		# machinery — a protective spell is just a BARRIER or AURA whose whole job
		# is to lose on purpose. Two things already carry the design:
		#   • WEIGHT says how much it can eat. A ward authored as an ULT stops
		#     everything up to an ULT and only a heavier spell gets through, which
		#     is the entire balance knob, expressed as its cast time and cooldown
		#     rather than as a hitpoint number nobody can see.
		#   • The three rungs above are already the right story for it. A ward
		#     shaped as a BARRIER inherits breach / barrier_blocks for free and is
		#     playable the day its spectacle exists, with zero rows written.
		# Only author a row when a ward wants something the rungs do NOT say:
		#   ABSORB (eat the spell, ward survives) — the same shape as
		#     barrier_blocks but WITHOUT consuming itself, at a priority above 20:
		#       _rule("ward_absorb", Form.BEAM, Form.AURA, {
		#           "require_weight": "b_heavier", "priority": 30, "consumes_a": true})
		#   REFLECT — one outcome key, and the geometry is already in ctx: the
		#     shapes and meeting point that ReactionOutcomes gets are exactly what
		#     re-aiming a beam back down its own axis needs.
		#   NEGATE A SCHOOL (an anti-fire ward) — an `elements_a` list, like
		#     shatter_ice_barrier, and it lands above the weight rungs on its own
		#     because the elemental band outranks them.
		# What a ward must NOT be authored as is a special case in SpellReactor.
		# If one ever seems to need that, the missing thing is a predicate here.
		#
		# ── THE SEAM, TAKEN UP: THE AEGIS WARD ─────────────────────────────────
		# Four rows, and NOT ONE new predicate — which is the claim the seam above
		# was making, now cashed.
		#
		# HOW THE WARD IS IDENTIFIED: by its ELEMENT, exactly as
		# `shatter_ice_barrier` keys on E.ICE to mean "the ice wall" and
		# `ground_out` keys on E.EARTH to mean "the rock wall". HOLY is the only
		# element no existing barrier carries (rock and pillar are EARTH, ice is
		# ICE), so these rows are provably unreachable by anything already built —
		# which is what makes adding a ward a zero-risk edit to a live matrix.
		#
		# HOW IT DEGRADES, WITHOUT A HITPOINT NUMBER ANYWHERE: the ward's
		# `reaction_weight()` STEPS DOWN as its charges burn (ULT -> HEAVY ->
		# QUICK), and SpellReactor polls weight every tick precisely so an effect
		# "getting LIGHTER as it is spent" is authorable. So a full ward outweighs
		# everything and eats it (ward_absorb, 30); a half-spent ward is outweighed
		# by an ult and gets breached (breach, 45); a nearly-dead ward loses to a
		# heavy. One number the player can READ off the plates, three outcomes, no
		# new machinery, and the counter to a ward is "bring something bigger" —
		# a decision rather than a stat check.
		_rule("shatter_ward", Form.BEAM, Form.BARRIER, {
			"elements_b": [E.HOLY], "require_opposed": true,
			"priority": 87, "consumes_b": true, "radius": 130.0, "damage": 24,
		}),
		# ...and the same for a thrown thing, so a hurled dagger answers a ward the
		# way a beam does. One point lower purely to keep the ladder readable.
		_rule("shatter_ward", Form.PROJECTILE, Form.BARRIER, {
			"elements_b": [E.HOLY], "require_opposed": true,
			"priority": 86, "consumes_b": true, "radius": 130.0, "damage": 24,
		}),
		# ...and for a BLAST, which is the row that makes the ward's own description
		# true. Aegis Ward's card says outright: "shadow pops it outright". Two of
		# the three shadow shapes in the game already did — Umbral Lance is a BEAM,
		# Rift Dagger and Creeping Shade are PROJECTILEs — but Shadow Step, the most
		# widely equipped shadow spell in the roster (it is in three kits), lands as
		# an IMPACT and did nothing at all to a ward. A promise printed on a spell
		# card and not kept by the matrix is worse than a missing interaction: the
		# player is told the answer, brings it, and watches it fail.
		#
		# This does NOT contradict the "IMPACT gets no blocks/breach rung" ruling
		# below. That ruling is about a blast being SWALLOWED by a barrier it was
		# never travelling toward; this is the same sentence the IMPACT arm of
		# shatter_ice_barrier already says — a detonation next to a barrier CRACKS
		# it. Disjoint from that row on `elements_b` (ICE there, HOLY here), so the
		# two can never contest each other.
		_rule("shatter_ward", Form.IMPACT, Form.BARRIER, {
			"elements_b": [E.HOLY], "require_opposed": true,
			"priority": 83, "consumes_b": true, "radius": 130.0, "damage": 24,
		}),
		# THE ABSORB. Above barrier_blocks (20) so a ward eats rather than merely
		# stops, and below breach (45) and carve (40) so both of those keep their
		# say. `consumes_a` only: the attacker is spent, the ward is not — the ward
		# pays in a CHARGE, which ReactionOutcomes tells it about and which shows on
		# its face. Elements wildcard on the attacking side on purpose: a ward that
		# only answered some schools would need the player to read a table.
		#
		# ⚠ NO `require_owner` PREDICATE, DELIBERATELY. Your own beam fired into
		# your own ward is eaten by it, and burns a charge. That reads harsh until
		# you notice it is the only thing stopping the ward being planted in front
		# of your own face and forgotten: with it, the ward is a PLACE you commit
		# to and shoot around. It is the single most likely thing in this feature to
		# be wrong, and it is one predicate to reverse if playtest says so.
		_rule("ward_absorb", Form.BEAM, Form.BARRIER, {
			"elements_b": [E.HOLY], "priority": 30,
			"consumes_a": true, "radius": 90.0,
		}),
		_rule("ward_absorb", Form.PROJECTILE, Form.BARRIER, {
			"elements_b": [E.HOLY], "priority": 29,
			"consumes_a": true, "radius": 90.0,
		}),
		# ───────────────────────────────────────────────────────────────────────
		# Same-element fields merge and strengthen rather than stacking two rings.
		_rule("field_merge", Form.FIELD, Form.FIELD, {
			"require_same": true, "priority": 50, "consumes_b": true, "radius": 190.0,
		}),
		# ── THE RAM ────────────────────────────────────────────────────────────
		# STONE INTO ICE. The one BARRIER x BARRIER pairing that is an EVENT rather
		# than architecture, and the row RockWall's own class docs asked for by name:
		# *"What IS genuinely missing is 'ram the ice wall and burst it', because
		# BARRIER vs BARRIER is the authored `none` row. That is a TABLE decision."*
		# This is the table answering.
		#
		# It exists because the rock wall has a SECOND BEAT. Every other barrier in
		# the game stands still; this one is punched and grinds across the arena at
		# 820 px/s, and a slab of stone arriving at a sheet of ice has exactly one
		# common-sense outcome. Leaving it inert was the single most disappointing
		# silence left in the matrix — the player performs a deliberate two-press
		# combo, aims it at the most obviously breakable thing on the floor, and the
		# two objects pass the moment doing nothing.
		#
		# WHY IT REUSES `shatter_ice_barrier` RATHER THAN EARNING A NEW OUTCOME: it
		# is the same event. The IMPACT arm of that row is already "any physical hit
		# bursts ice", wildcard on the attacking element — and 124 px of moving stone
		# is the most physical hit in the game. Same radius (120, which is IceWall's
		# own SHATTER_RADIUS, so drawn and damaged agree), same shards, same EARTH
		# ailment carried by the attacker. A new key here would be a second name for
		# one thing.
		#
		# ⚠ THE ONE THING THIS ROW MUST NOT DO is fire for two walls merely STANDING
		# next to each other, and it is gated by ELEMENTS rather than by motion. A
		# stationary overlap needs two casters (no single kit holds both rock_wall
		# and ice_wall), both aiming into the same 90 px pocket, in the ~4 s both are
		# up — vanishingly rarer than the shove, and when it does happen "the stone
		# went up through the ice and broke it" is still the right picture. Every
		# OTHER barrier pair — stone/stone, ice/ice, either against the holy ward —
		# falls straight through to the silence below, which is where the deliberate
		# part of that decision lives. There is no motion predicate to gate on and
		# inventing one would be a special case in the detector; see RockWall's
		# reaction_form() for why a shoved wall stays a BARRIER at all.
		#
		# Priority 84 puts it in the ELEMENTAL band with the other shatter rows,
		# where it belongs: this is the material being the answer, not the weights.
		# It is the only non-suppress row in its bucket, so nothing can be stolen
		# from — and the bucket already existed for `none`, so the reactor's sparse
		# gate probes exactly the pairs it probed before.
		_rule("shatter_ice_barrier", Form.BARRIER, Form.BARRIER, {
			"elements_a": [E.EARTH], "elements_b": [E.ICE],
			"priority": 84, "consumes_b": true, "radius": 120.0, "damage": 30,
		}),
		# Explicit NULL row: two barriers touching is architecture, not an event.
		# Written down so the silence is a decision rather than a gap. STILL THE
		# FLOOR of this bucket after the ram above — it is wildcard on both elements
		# at priority 10, so every barrier pair the ram does not name (stone/stone,
		# ice/ice, anything meeting the holy ward) resolves here and stays silent.
		# match_rule takes the highest-priority match and only THEN honours
		# `suppress`, so an EARTH/ICE meeting reaches the ram and everything else
		# reaches this.
		_rule("none", Form.BARRIER, Form.BARRIER, {"priority": 10, "suppress": true}),
	]


## Best matching rule for a pair of live effects, or {} when they simply coexist.
## `a` and `b` are {form, element} descriptors. Both orderings are tried, so a
## rule written fire-beam-vs-ice-wall also fires when the wall is seen first.
##
## `owner_rel` is how the two effects' casters relate: "same", "different",
## "unowned", or "" when the caller has no ownership information at all — in
## which case the owner predicate is simply not applied, so the table stays
## testable in isolation. SpellReactor always supplies a real value.
##
## `weight_a`/`weight_b` are SpellTier shelves, and they take the OPPOSITE
## convention to owner_rel: an unsupplied weight makes every weight-gated row fail
## rather than skipping the predicate. A caller that knows nothing about weight
## should get back only the rows that genuinely do not care about it, because
## "assume they're evenly matched" would have this function invent an
## annihilation out of missing information — the loud-in-the-wrong-direction
## failure this whole layer is built to avoid. SpellReactor always supplies a real
## shelf (it resolves an un-implemented spectacle to SpellTier.DEFAULT_WEIGHT
## before calling), so production never takes this branch.
##
## The returned rule carries a `swapped` flag saying which way round it matched;
## read consumes_a/consumes_b through consumes_caller() rather than directly.
static func match_rule(form_a: int, element_a: int, form_b: int, element_b: int,
		owner_rel: String = "", weight_a: int = SpellTier.WEIGHT_UNKNOWN,
		weight_b: int = SpellTier.WEIGHT_UNKNOWN,
		heading_a: Vector2 = Vector2.ZERO,
		heading_b: Vector2 = Vector2.ZERO) -> Dictionary:
	var key: int = bucket_key(form_a, form_b)
	var best: Dictionary = {}
	for r: Dictionary in rules():
		if bucket_key(int(r["form_a"]), int(r["form_b"])) != key:
			continue
		var swapped: bool = false
		if _sides_match(r, form_a, element_a, form_b, element_b, owner_rel,
				weight_a, weight_b, heading_a, heading_b):
			swapped = false
		elif _sides_match(r, form_b, element_b, form_a, element_a, owner_rel,
				weight_b, weight_a, heading_b, heading_a):
			swapped = true
		else:
			continue
		if best.is_empty() or int(r["priority"]) > int(best["priority"]):
			# Safe to write into: rules() builds fresh dictionaries on every call,
			# so there is no shared authored row to corrupt.
			r["swapped"] = swapped
			best = r
	if not best.is_empty() and bool(best.get("suppress", false)):
		return {}
	return best


## Does the winning rule spend the CALLER's side 0 (`a`) or side 1 (`b`)?
## Necessary because a row written "fire beam vs ice wall" also matches when the
## wall was seen first, and then its consumes_a means the caller's `b`. Reading
## the raw flag in that case consumes the wrong effect — a bug that would look
## like a random spell surviving something that should have eaten it.
static func consumes_caller(rule: Dictionary, caller_side: int) -> bool:
	if rule.is_empty():
		return false
	var rule_side: int = (1 - caller_side) if bool(rule.get("swapped", false)) else caller_side
	return bool(rule.get("consumes_b" if rule_side == 1 else "consumes_a", false))


static func _sides_match(r: Dictionary, form_a: int, element_a: int,
		form_b: int, element_b: int, owner_rel: String = "",
		weight_a: int = SpellTier.WEIGHT_UNKNOWN,
		weight_b: int = SpellTier.WEIGHT_UNKNOWN,
		heading_a: Vector2 = Vector2.ZERO,
		heading_b: Vector2 = Vector2.ZERO) -> bool:
	if int(r["form_a"]) != form_a or int(r["form_b"]) != form_b:
		return false
	# HEAD-ON, and it is the predicate that keeps `bolt_fizzle` from firing on every
	# parallel exchange. Two bolts crossing at 70 degrees do not read as a collision;
	# two nose-to-nose do. Fails CLOSED when a heading is missing, on the same
	# reasoning `require_weight` does below: an effect that cannot say which way it is
	# going has not earned a row that is about which way it is going.
	if bool(r.get("require_head_on", false)):
		if heading_a == Vector2.ZERO or heading_b == Vector2.ZERO:
			return false
		if heading_a.normalized().dot(heading_b.normalized()) > HEAD_ON_DOT:
			return false
	var need_owner: String = String(r.get("require_owner", "any"))
	# "unowned" satisfies neither "same" nor "different" — without two known
	# casters there is no relationship to require.
	if need_owner != "any" and owner_rel != "" and need_owner != owner_rel:
		return false
	# Weight, oriented with the sides: `weight_a` always belongs to whichever
	# effect is currently being tried against the row's form_a.
	var need_weight: String = String(r.get("require_weight", "any"))
	if need_weight != "any":
		if weight_a == SpellTier.WEIGHT_UNKNOWN or weight_b == SpellTier.WEIGHT_UNKNOWN:
			return false
		match need_weight:
			"equal":
				if not SpellTier.weights_match(weight_a, weight_b):
					return false
			"a_heavier":
				if not SpellTier.outweighs(weight_a, weight_b):
					return false
			"b_heavier":
				if not SpellTier.outweighs(weight_b, weight_a):
					return false
			_:
				# An unrecognised predicate is an authoring typo. Fail closed: a
				# silent row is a bug someone finds, a row that fires for every
				# pair is a bug that ships.
				return false
	if bool(r["require_opposed"]) and not opposed(element_a, element_b):
		return false
	if bool(r["require_same"]) and element_a != element_b:
		return false
	var ea: Array = r["elements_a"]
	var eb: Array = r["elements_b"]
	if not ea.is_empty() and not ea.has(element_a):
		return false
	if not eb.is_empty() and not eb.has(element_b):
		return false
	return true
