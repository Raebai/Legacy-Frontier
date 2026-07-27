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
