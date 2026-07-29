class_name SpellTier
extends RefCounted
## QUICK / HEAVY / ULT — what a spell costs you to throw.
##
## The loadout is four spell slots plus a dedicated ULT slot, so a spell has to
## know which shelf it belongs on. Rather than hand-tagging 26 spells (and every
## future one), the tier is DERIVED from what the spell already declares: how
## long you commit to casting it, how long you wait to use it again, and what it
## costs. Those three numbers are the commitment, and commitment is exactly what
## separates a jab from a finisher.
##
## Deriving it also means a spell cannot lie about its tier — retune a spell to
## be slower and pricier and it moves shelf on its own, instead of staying tagged
## QUICK because someone forgot.

enum Tier { QUICK, HEAVY, ULT }

## An ult commits you: a long wind-up or a long wait between uses.
const ULT_CAST_TIME: float = 0.9
const ULT_COOLDOWN: float = 7.0
const ULT_MP: int = 70
## A quick spell is one you can throw in the middle of a fight without planning.
const QUICK_COOLDOWN: float = 3.6
const QUICK_MP: int = 45


static func of(spell: Variant) -> int:
	if spell == null:
		return Tier.QUICK
	var cast_time: float = float(spell.get(&"cast_time"))
	var cooldown: float = float(spell.get(&"cooldown"))
	var mp: int = int(spell.get(&"mp_cost"))
	# Any ONE of these is enough to make it an ult: a spell you must stand still
	# and commit to is a finisher even if it happens to be cheap.
	if cast_time >= ULT_CAST_TIME or cooldown >= ULT_COOLDOWN or mp >= ULT_MP:
		return Tier.ULT
	if cooldown <= QUICK_COOLDOWN and mp <= QUICK_MP and cast_time <= 0.01:
		return Tier.QUICK
	return Tier.HEAVY


# ------------------------------------------------------------ reaction WEIGHT
## The reaction layer asks a spell a second question: not "which shelf does it
## sit on in the loadout" but "how much does it WEIGH when it meets another spell
## head-on". Those are the same question, so weight IS the tier — QUICK < HEAVY <
## ULT, already ordered by the enum — rather than a second notion of power that
## could quietly disagree with this one. Retune a spell to be slower and pricier
## and it both moves shelf AND starts winning clashes, from one edit.
##
## Only the ORDER of the enum is load-bearing: every comparison below is a
## difference between two Tier ordinals, so a shelf inserted between HEAVY and ULT
## would keep working. Never reorder Tier.

## "Nobody told me." A caller with no weight information passes this, and
## ReactionTable then refuses to match any weight-gated rule at all — the
## conservative direction, so a caller that knows nothing about weight only ever
## sees the weight-agnostic half of the table. SpellReactor never passes it: it
## resolves an unimplemented spectacle to DEFAULT_WEIGHT first.
const WEIGHT_UNKNOWN: int = -1

## What a spell weighs when it has not said — the MIDDLE shelf, deliberately.
## An effect that has not implemented reaction_weight() is then neither trivially
## breached by everything nor unstoppable by anything, and — the part that
## matters for a staged rollout — every un-implemented spectacle weighs the SAME
## as every other, so they stay evenly matched with each other exactly as they
## are today while ~15 spells catch up one at a time.
## UNTESTED GUESS: it is a shelf, not a tuned number.
const DEFAULT_WEIGHT: int = Tier.HEAVY

## How far apart two weights may sit and still count as EVENLY MATCHED — the one
## number that decides whether two spells annihilate each other or one of them
## simply wins. 0 = strictly the same shelf.
## UNTESTED GUESS: 0 because "same shelf, same fate" is a rule a player can learn
## from a single clash, and because 1 would make HEAVY trade evenly with ULT,
## which is the exact feeling ("my ult got cancelled by a jab") this exists to
## prevent. Raise it to 1 if ULTs turn out to bully everything.
const WEIGHT_MATCH_TOLERANCE: int = 0


## Any as-given weight resolved to a real shelf. Anything outside the enum —
## including WEIGHT_UNKNOWN — becomes DEFAULT_WEIGHT, so a spectacle returning
## garbage degrades to "average spell" instead of poisoning a comparison.
static func weight_or_default(w: int) -> int:
	if w < 0 or w > Tier.ULT:
		return DEFAULT_WEIGHT
	return w


## Evenly matched — neither side outweighs the other by more than the tolerance.
## This is the predicate behind "two beams explode and cancel each other out".
static func weights_match(a: int, b: int) -> bool:
	return absi(weight_or_default(a) - weight_or_default(b)) <= WEIGHT_MATCH_TOLERANCE


## Does `a` strictly OUTWEIGH `b`? The "an ult should feel like an ult" test: the
## heavier spell is not cancelled, it eats the lighter one and keeps going.
static func outweighs(a: int, b: int) -> bool:
	return weight_or_default(a) - weight_or_default(b) > WEIGHT_MATCH_TOLERANCE


static func display_name(tier: int) -> String:
	match tier:
		Tier.ULT:
			return "ULT"
		Tier.HEAVY:
			return "HEAVY"
	return "QUICK"


## Colour used to badge a slot, so the shelf is readable at a glance on the bar.
static func color(tier: int) -> Color:
	match tier:
		Tier.ULT:
			return Color(1.0, 0.80, 0.35)      # gold — the one you save
		Tier.HEAVY:
			return Color(0.72, 0.62, 1.0)      # violet — costs you something
	return Color(0.55, 0.85, 0.95)             # cyan — throwaway


## Every spell in `spells` whose tier matches, preserving library order.
static func filter(spells: Array, tier: int) -> Array:
	var out: Array = []
	for s in spells:
		if of(s) == tier:
			out.append(s)
	return out


## The tier a given loadout slot accepts. Slots 0-3 are the four spell slots and
## take anything that is not an ult; slot 4 is the ult slot.
static func slot_accepts_ult(slot_index: int) -> bool:
	return slot_index >= 4
