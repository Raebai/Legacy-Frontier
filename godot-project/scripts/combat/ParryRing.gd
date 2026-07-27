class_name ParryRing
extends RefCounted
## THE GUARD RING — deflect as a visible, timed act instead of an invisible
## 0.16 s window.
##
## Hold the deflect button and a white circular boundary appears out at arm's
## length and SHRINKS toward the body. The tight band near the body is the
## PERFECT window: meet an incoming attack there and you get the full deflect
## (reflect + the loud payoff, and it is the only state that can turn an ult).
## Overshoot it and the ring bottoms out into a weaker SUSTAINED guard you may
## hold as long as you like — it still chips damage, but it cannot reflect and
## cannot stop an ult. Release and the ring resets to full, ready to be timed
## again.
##
## WHY A SHRINKING RING RATHER THAN A HIDDEN TIMER: a parry window you cannot see
## is a memorisation test. A ring you watch close is a READ — and it is legible
## to an opponent too, since they can see you commit to a guard and can bait it.
## It also gives the defender a real decision instead of a reflex: take the
## perfect window and risk whiffing, or settle for the safe sustained guard.
##
## Pure timing model — no nodes, no drawing. The rig renders `radius01()`, and
## `quality()` is what the damage path asks. Keeps the whole thing testable.

## Seconds from press until the ring reaches the perfect band.
const SHRINK_TIME: float = 0.42
## The perfect band, as a fraction of the shrink. Entering at 0.78 gives a window
## of ~0.09 s — demanding but reactable, and deliberately close to the old fixed
## PARRY_WINDOW of 0.16 s so existing muscle memory is not thrown away.
const PERFECT_START: float = 0.78
const PERFECT_END: float = 1.0
## Ring size at full extension and at its tightest, as a fraction of arm reach.
const RADIUS_MAX: float = 1.0
const RADIUS_MIN: float = 0.34
## What a sustained (overshot) guard still does. Not zero, or holding would be
## strictly pointless; not much, or holding would beat timing.
const SUSTAIN_REDUCTION: float = 0.35

enum Quality { NONE, SUSTAIN, PERFECT }

var held: bool = false
var _t: float = 0.0


## Press: the ring blooms at full radius and starts closing.
func press() -> void:
	held = true
	_t = 0.0


## Release: resets, so every attempt is a fresh committed read rather than a
## permanently-armed shield.
func release() -> void:
	held = false
	_t = 0.0


func tick(delta: float) -> void:
	if held:
		_t += delta


## 0..1 progress through the shrink, clamped once the ring bottoms out.
func progress() -> float:
	return clampf(_t / SHRINK_TIME, 0.0, 1.0)


## Ring radius as a fraction of arm reach — what the rig draws.
func radius01() -> float:
	if not held:
		return RADIUS_MAX
	return lerpf(RADIUS_MAX, RADIUS_MIN, progress())


## What a hit meeting this guard right now gets.
func quality() -> int:
	if not held:
		return Quality.NONE
	var p: float = progress()
	if p >= PERFECT_START and p <= PERFECT_END and _t <= SHRINK_TIME:
		return Quality.PERFECT
	if _t > SHRINK_TIME:
		return Quality.SUSTAIN     # overshot — the ring bottomed out
	return Quality.NONE            # still closing; too early to block anything


## Bridges to SpellDeflect's victim contract. 1.0 = a perfect read, which is the
## only value that clears the tight ult window; a sustained guard reports 0 so it
## can never turn an ult no matter how long it is held.
func freshness() -> float:
	return 1.0 if quality() == Quality.PERFECT else 0.0


## Damage multiplier this guard applies. A perfect read negates entirely; a
## sustained guard only chips.
func damage_mult() -> float:
	match quality():
		Quality.PERFECT:
			return 0.0
		Quality.SUSTAIN:
			return 1.0 - SUSTAIN_REDUCTION
	return 1.0


## Only a perfect read reflects. Holding a guard must never send things back, or
## the safe option would also be the strong one.
func can_reflect() -> bool:
	return quality() == Quality.PERFECT
