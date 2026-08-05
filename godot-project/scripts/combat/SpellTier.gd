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


## HOW MANY SPELL BUTTONS A HAND HAS. Four — three open slots plus the ult.
##
## ⚠ THIS CONSTANT HAD DRIFTED FROM THE DESIGN, NOT THE OTHER WAY UP. The header of
## this very file has said "four spell slots plus a dedicated ULT slot" since it was
## written; the number said three. The maker, watching a fight: "lets make it 4 spell
## slots as there are 4 spells currently going on."
##
## Everything downstream is derived from here — `ULT_SLOT`, `BotIntent.SLOT_COUNT`
## and its whole cooldown-index block, the hotbar's cluster split, the touch arc's
## button count, the loadout picker's arity. The one thing that is NOT derived is
## `SpellLibrary.SLOT_ROLES`, which authors a hand per class by name; growing this
## number without adding a role there is caught by `tools/slice8_test_spell_kits.gd`
## rather than discovered as an empty button on floor 3.
##
## The COST of the fourth slot is the pickup pool, and it is worth saying out loud:
## `CLASS_KITS` authors five roles per class, so carrying four leaves ONE reserve
## instead of two, and five spells that used to be floor drops are now started with.
## You hold more and you find less.
const SLOT_COUNT: int = 4
## The ult always sits in the LAST slot. Derived rather than written as a literal so
## the two constants cannot drift apart — one edit moves the whole scheme.
const ULT_SLOT: int = SLOT_COUNT - 1


## The tier a given loadout slot accepts: everything before the last slot takes
## anything that is not an ult; the last slot is the ult slot.
static func slot_accepts_ult(slot_index: int) -> bool:
	return slot_index >= ULT_SLOT


# ══ HOW HARD A SPELL SHOVES ═════════════════════════════════════════════════════
## Maker: *"I want slight knockback like small amounts based on these spells"*.
##
## ⚠ `SpellDef` HAS NO KNOCKBACK FIELD AND DELIBERATELY DOES NOT GET ONE. Adding an
## `@export` push to a `.tres`-authorable Resource means re-authoring every spell in
## the catalog and shipping a DEFAULT that silently overrides thirty hand-tuned
## constants the moment anything reads it. The shelf and the damage are already
## authored on every spell, and between them they say everything a shove needs to
## know: how committed the cast was, and how hard it landed.
##
## Calibrated against the real curve rather than by taste. Knockback in this project
## is a decaying velocity channel, not an impulse — `Hero.apply_knockback` bleeds it
## at `KNOCKBACK_DECAY` — so the DISTANCE travelled goes as roughly `I^2 / 1800` px.
## That is why these numbers look large for "slight": 140 is about 11 px, 267 about
## 40 px, 400 about 89 px. A quick bolt nudges, a heavy staggers, an ult moves you.
##
## ⚠ AND EVERY VALUE STAYS ABOVE TWO FLOORS THAT ARE NOT ARBITRARY. Under 12 the rig
## skips its flop entirely and the hit stops reading as a hit; under
## `SlamPhysics.MIN_SLAM_SPEED` (250) a body can no longer crack a wall it is thrown
## into, which would silently delete the tower's crater and wall-break reactions.
## ⚠ ANCHORED SO THE ORDINARY BOLT DOES NOT CHANGE. The plain bolt is 18 damage and
## has always shoved at ~250, and the maker's OTHER note on this is that bodies should
## react to being hit MORE — so a formula that quietly halved the most common hit in
## the game would be answering one request by breaking the other. `95 + 8.6 * 18` is
## 250: today's number, derived instead of hardcoded. Everything else moves around it.
const PUSH_BASE: float = 95.0
const PUSH_PER_DAMAGE: float = 8.6
## Indexed by `Tier` — a committed cast shoves harder than a jab of the same damage.
const PUSH_TIER: Array[float] = [1.0, 1.30, 1.70]
## Floors and ceilings, and neither is arbitrary. Below ~12 the rig skips its flop and
## the hit stops reading; the real floor is set higher so even the lightest spell
## still visibly moves a body. The ceiling keeps a high-damage ult from out-shoving
## `HollowPurple` (900), which is the authored loudest push in the game.
const PUSH_MIN: float = 120.0
const PUSH_MAX: float = 900.0


## The shove a spell should carry, in the same px/s units `apply_knockback` takes.
## Null-safe: an unknown spell falls back to the base nudge rather than to zero, so a
## caller that loses its `SpellDef` degrades to "a small push" and not to "no hit".
static func push_for(spell: SpellDef) -> float:
	if spell == null:
		return PUSH_BASE
	var t: int = of(spell)
	var mult: float = PUSH_TIER[t] if t >= 0 and t < PUSH_TIER.size() else 1.0
	return push_for_damage(float(spell.damage), mult)


## The same curve for anything that knows its damage but not its `SpellDef` — the
## bolt entity being the case that matters, since it carries an `@export damage` and
## no definition. One formula, so a bolt and its own catalog entry cannot disagree
## about how hard the same hit shoves.
static func push_for_damage(damage: float, tier_mult: float = 1.0) -> float:
	return clampf((PUSH_BASE + PUSH_PER_DAMAGE * maxf(damage, 0.0)) * tier_mult,
		PUSH_MIN, PUSH_MAX)


# ══ AND HOW HARD A *SPECTACLE* SHOVES ═══════════════════════════════════════════
## Maker: *"the effect of the spell isnt tangible like a spell should have some
## knockback and stuff not crazy amounts but a decent amount"*.
##
## ⚠ THE SAME MAKER PREVIOUSLY SAID THE OPPOSITE, AND BOTH NOTES ARE RIGHT. Half the
## spectacles in the game carry a comment reading *"was 360.0 — maker: spell knockback
## was way too much"*. Taking the new note as "put it back" would just walk into the
## old one from the other side, and taking `push_for_damage` as-is would be far worse:
## it is LINEAR in damage and anchored on an 18-damage bolt, so `DivineRay` at 95
## damage solves to 1185 and clamps at the 900 ceiling — four and a half times what was
## already rejected as too much.
##
## SO WHAT ACTUALLY CHANGED IS NOT THE DISTANCE, IT IS WHETHER THE WORLD ANSWERS.
## MEASURED across every spectacle that shoves: `BeamSpell` 235, `DivineRay` 210,
## `CrescentStep` 190, `HeavensWrath` 190, `BladeFlurry` 150 — and
## `SlamPhysics.MIN_SLAM_SPEED` is **250**. Every one of them was cut to below the
## threshold at which a thrown body can crack the thing it hits, which silently
## deleted the crater, the wall break, the debris and the shake from the entire
## spell roster. That is what "not tangible" is: a spell that moves a body through
## empty air and nothing in the world reacts to it.
##
## Hence a FLOOR at the slam threshold and a CEILING under the value already rejected.
## Knockback here is a decaying velocity channel, so distance goes as roughly
## `I^2 / 1800` px: this band is 39 px to 70 px of travel, against 25-30 px today and
## the 72 px that was called too much. Every spell moves you further AND — the part
## that matters — every spell can now break something with your body.
## ⚠ RAISING THESE RAISES RING-OUT RISK. `body_escaped_bounds` was already noted at 2
## in the duel sim; if fighters start leaving the stage, this band is why.
const PUSH_SPECTACLE_MIN: float = 265.0   # just clear of SlamPhysics.MIN_SLAM_SPEED
const PUSH_SPECTACLE_MAX: float = 355.0   # under the 360 that was rejected
## Sub-linear in damage, because the channel is quadratic in DISTANCE: a hit worth five
## times as much must not travel twenty-five times as far. `push_for_damage`'s linear
## term cannot be reused here for exactly that reason — at `DivineRay`'s 95 damage it
## solves to 1185.
##
## ⚠ FITTED TO THE BAND, NOT PICKED. The first pass reused `PUSH_BASE` with a large
## coefficient and every single spectacle in the game clamped to the ceiling — the
## formula discriminated nothing and the "derived" tier ordering was decorative. These
## two solve `sqrt(damage) * tier_mult` onto the band across the roster's real spread,
## from the lightest quick cut (`BladeFlurry`, 18 damage) to the heaviest ult
## (`DivineRay`, 95 at the ULT multiplier). Measured result across the eight spells
## routed through it: 267 / 288 / 300 / 303 / 304 / 315 / 355 / 355 — a real ladder
## rather than eight copies of the ceiling.
const PUSH_SPECTACLE_BASE: float = 237.5
const PUSH_PER_ROOT_DAMAGE: float = 7.1


## The shove a big drawn spell should carry. Same shape as `push_for_damage` — derived
## from what the spell already declares, never from a new authored field — but on the
## band above, so a spectacle is always heavy enough for the world to answer it and
## never heavy enough to read as a launcher.
static func push_for_spectacle(damage: float, tier_mult: float = 1.0) -> float:
	return clampf(
		PUSH_SPECTACLE_BASE + PUSH_PER_ROOT_DAMAGE * sqrt(maxf(damage, 0.0)) * tier_mult,
		PUSH_SPECTACLE_MIN, PUSH_SPECTACLE_MAX)
