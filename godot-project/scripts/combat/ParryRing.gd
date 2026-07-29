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
##
## TWO STYLES, ONE CLOCK. Classes guard DIFFERENTLY — the swordsman parries with
## the blade, the mage catches the spell in a summoned sigil (see SigilGuard) —
## but they must never be two timing implementations. A second clock is exactly
## how the two guard paths drift apart: one gets a balance tweak, the other
## silently does not, and "the parry window" stops being one thing players can
## learn. So `style` is a dimension ON this clock: it moves NUMBERS and reports
## which presentation to draw, and every state machine below (press/release,
## progress, quality, re-arm) is shared verbatim.

## ---------------------------------------------------------------------------
## THE ENTIRE DEFENSIVE TIMING BUDGET. Every number in this block is REASONED,
## NOT FELT — none of it has been playtested. They are kept together, named, so
## the maker can tune the whole defensive feel in one place rather than hunting
## magic numbers through the guard, the sigil and the damage path.
## ---------------------------------------------------------------------------

## Seconds from press until the ring reaches the perfect band. SHARED by both
## styles deliberately: the gesture takes the same time to make whoever you are,
## so what differs between classes is how FORGIVING the catch is, not how long
## you must wait — a different shrink time would make the two guards feel like
## unrelated buttons rather than one verb with two costumes.
const SHRINK_TIME: float = 0.42
## The perfect band, as a fraction of the shrink. BLADE entering at 0.78 gives a
## window of ~0.09 s — demanding but reactable, and deliberately close to the old
## fixed PARRY_WINDOW of 0.16 s so existing muscle memory is not thrown away.
const PERFECT_START: float = 0.78
const PERFECT_END: float = 1.0
## SIGIL's band, ~0.057 s (about 3.4 frames at 60 Hz) — roughly two-thirds of the
## blade's. THIS IS THE MAGE'S PRICE. Catching a spell and sending it back is a
## strictly stronger outcome than eating it, so it must be strictly harder to
## land; paying for it in window width keeps the cost inside the same read the
## player is already making, instead of bolting on a resource to watch.
const SIGIL_PERFECT_START: float = 0.865
## Ring size at full extension and at its tightest, as a fraction of arm reach.
const RADIUS_MAX: float = 1.0
const RADIUS_MIN: float = 0.34
## What a sustained (overshot) BLADE guard still does. Not zero, or holding would
## be strictly pointless; not much, or holding would beat timing.
const SUSTAIN_REDUCTION: float = 0.35

enum Quality { NONE, SUSTAIN, PERFECT }
## BLADE = steel held in the way, SIGIL = a circle summoned to meet the spell.
enum Style { BLADE, SIGIL }

## Enforced gap between guards. Without it, releasing and re-pressing re-arms the
## perfect window instantly, so mashing the button carpets the fight in perfect
## reads and the timing stops being a skill at all.
const REARM_TIME: float = 0.35
## SIGIL re-arm — the mage's second price. A blade is already in your hand, so a
## whiffed parry costs you a beat; a sigil has to be SUMMONED again from nothing,
## so a whiffed catch costs you a good deal more than a beat. It also stops the
## tighter window being farmed by simply attempting the catch twice as often.
const SIGIL_REARM_TIME: float = 0.55

## Which presentation + outcome this guard uses. Set once by the owner from its
## class; never flipped mid-guard (the clock would jump bands under the player).
var style: int = Style.BLADE
var held: bool = false
var _t: float = 0.0
var _rearm: float = 0.0


## Convenience for owners that build the ring at class-setup time.
static func for_style(s: int) -> ParryRing:
	var r := ParryRing.new()
	r.style = s
	return r


## Where the perfect band opens for THIS style.
func perfect_start() -> float:
	return SIGIL_PERFECT_START if style == Style.SIGIL else PERFECT_START


## The perfect band in seconds — what the player is actually asked to hit.
func perfect_window() -> float:
	return (PERFECT_END - perfect_start()) * SHRINK_TIME


func rearm_time() -> float:
	return SIGIL_REARM_TIME if style == Style.SIGIL else REARM_TIME


## Does overshooting leave you with anything? A BLADE bottoms out into a weaker
## SUSTAINED guard — steel is still in the way whether or not you timed it. A
## SIGIL has no such fallback: a summoning that meets nothing COLLAPSES, and a
## collapsed circle blocks exactly nothing.
##
## This is the mage's third and largest price, and it is the one that carries the
## fantasy rather than just the maths. The swordsman's guard degrades gracefully;
## the mage's is all-or-nothing. It also removes the "hold the circle up forever"
## default that would otherwise make a sigil the safest object in the game.
func has_sustain() -> bool:
	return style != Style.SIGIL


## True once a SIGIL has been held past its band and fizzled. Always false for a
## blade, which bottoms out rather than collapsing.
func is_collapsed() -> bool:
	return held and not has_sustain() and _t > SHRINK_TIME


## Press: the ring blooms at full radius and starts closing. Refused while
## re-arming, so a mashed guard simply does not come up.
func press() -> bool:
	if held or _rearm > 0.0:
		return false
	held = true
	_t = 0.0
	return true


## Release: resets and starts the re-arm, so every attempt is a fresh committed
## read rather than a permanently-armed shield.
func release() -> void:
	if held:
		_rearm = rearm_time()
	held = false
	_t = 0.0


func tick(delta: float) -> void:
	if held:
		_t += delta
	else:
		_rearm = maxf(_rearm - delta, 0.0)


## False while the guard is recovering — the bar should show this, or the player
## cannot tell a refused press from a mistimed one.
func is_ready() -> bool:
	return _rearm <= 0.0


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
	if p >= perfect_start() and p <= PERFECT_END and _t <= SHRINK_TIME:
		return Quality.PERFECT
	if _t > SHRINK_TIME:
		# Overshot. A blade bottoms out into the weaker sustained guard; a sigil
		# has already collapsed and guards nothing at all (see has_sustain).
		return Quality.SUSTAIN if has_sustain() else Quality.NONE
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


## GUARDING LOCKS OUT ATTACKING. This is a balance rule, not a UI limitation, and
## it applies on every platform.
##
## It came out of a mobile constraint — the right thumb cannot hold the guard AND
## drag the blade at once — but the constraint turned out to be the correct rule.
## Without it, a sustained guard is free: you hold it permanently, take reduced
## damage forever, and keep swinging. Costing it your offence makes holding a real
## trade instead of a default state, and it removes the platform asymmetry where a
## desktop player could hold both buttons and a phone player could not.
##
## Callers must consult this before running the primary action.
##
## A COLLAPSED SIGIL IS THE ONE EXEMPTION. Once a mage's circle has fizzled there
## is nothing in the way and nothing being maintained, so holding the button past
## that point is not a guard — it is a finger resting on a key. Charging the
## offence lock for it would make the mage pay the sustained guard's price while
## receiving none of its protection, which is a bug dressed as a balance rule.
## The re-arm still only starts on RELEASE, so this cannot be farmed: you must
## let go (and eat the longer sigil re-arm) to get another circle.
func blocks_attack() -> bool:
	return held and not is_collapsed()
