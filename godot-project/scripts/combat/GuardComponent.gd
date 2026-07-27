class_name GuardComponent
extends Node
## The BUFF half of the mitigation story — the structural twin of
## StatusComponent, which handles debuffs. One place that answers "how much of
## this hit actually lands".
##
## WHY IT EXISTS: mitigation was previously three ad-hoc fields inlined in
## Hero.take_damage (gear armour, a one-shot warding robe, and its used-flag).
## Hero-only, non-expiring, and invisible to Enemy, Boss or a bot. Adding ward
## spells on top of that would have produced two mitigation paths that silently
## disagree about the same hit. This subsumes them, so there is exactly one.
##
## Attach lazily to any body that takes damage; the grant path is duck-typed, so
## Enemy/Boss/bots work with no extra code. Draws nothing — purely arithmetic and
## timers, so it is fully headless-testable.
##
## ORDERING IS DELIBERATE and must not be shuffled casually — it decides how ward
## spells and gear interact:
##   immunity -> percentage reductions -> one-shot fraction -> absorb pool
## Percentages come first so an absorb pool soaks REDUCED damage and therefore
## lasts longer, which is what makes stacking armour with a ward feel worthwhile
## rather than redundant.

## Node name used when attaching, so lookups are cheap and repeatable.
const NODE_NAME: StringName = &"GuardComponent"

## Persistent percentage off every hit (gear armour). No expiry.
var persistent_reduction: float = 0.0
## Timed percentage off every hit (ward spells). Expires.
var timed_reduction: float = 0.0
var _reduction_timer: float = 0.0
## One-shot fractional soak (the gear warding robe): softens ONE hit, then spent.
var oneshot_fraction: float = 0.0
var _oneshot_used: bool = false
## Absorb pool — flat damage eaten before any reaches hp. Expires.
var absorb: float = 0.0
var _absorb_timer: float = 0.0
## Flat damage returned to a melee attacker per hit. FLAT, never a percentage:
## a percentage return off a 130-damage boss hit would hand back 65.
var reflect_flat: int = 0
var _reflect_timer: float = 0.0
## Total immunity (short, e.g. a perfect-guard frame).
var _immune_timer: float = 0.0


## Find or create the guard on a body. Cheap enough to call from a damage path.
static func of(body: Node) -> GuardComponent:
	if body == null or not is_instance_valid(body):
		return null
	var existing: Node = body.get_node_or_null(NodePath(String(NODE_NAME)))
	if existing != null:
		return existing as GuardComponent
	var g := GuardComponent.new()
	g.name = String(NODE_NAME)
	body.add_child(g)
	return g


## Only look it up, never create — for read-only checks in hot paths.
static func peek(body: Node) -> GuardComponent:
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null(NodePath(String(NODE_NAME))) as GuardComponent


func _process(delta: float) -> void:
	_reduction_timer = maxf(_reduction_timer - delta, 0.0)
	if _reduction_timer <= 0.0:
		timed_reduction = 0.0
	_absorb_timer = maxf(_absorb_timer - delta, 0.0)
	if _absorb_timer <= 0.0:
		absorb = 0.0
	_reflect_timer = maxf(_reflect_timer - delta, 0.0)
	if _reflect_timer <= 0.0:
		reflect_flat = 0
	_immune_timer = maxf(_immune_timer - delta, 0.0)


# ---- grants ----------------------------------------------------------------
# All of these REPLACE rather than stack. Stacking wards on top of dash i-frames
# and a free parry is the fastest route to an un-hittable player, and "my ward
# refreshed instead of doubling" is far easier to read than a hidden sum.

func grant_reduction(frac: float, duration: float) -> void:
	timed_reduction = maxf(timed_reduction, clampf(frac, 0.0, 0.95))
	_reduction_timer = maxf(_reduction_timer, duration)


func grant_absorb(amount: float, duration: float) -> void:
	absorb = maxf(absorb, amount)
	_absorb_timer = maxf(_absorb_timer, duration)


func grant_reflect(flat: int, duration: float) -> void:
	reflect_flat = maxi(reflect_flat, flat)
	_reflect_timer = maxf(_reflect_timer, duration)


func grant_immunity(duration: float) -> void:
	_immune_timer = maxf(_immune_timer, duration)


## Gear, not a spell: persistent armour plus a single-use robe soak. Re-applied
## whenever a loadout or class changes, which also re-arms the robe.
func set_gear(reduction: float, ward_fraction: float) -> void:
	persistent_reduction = clampf(reduction, 0.0, 0.95)
	oneshot_fraction = clampf(ward_fraction, 0.0, 0.95)
	_oneshot_used = false


func is_immune() -> bool:
	return _immune_timer > 0.0


## True when this guard is doing nothing at all, so callers can skip the work.
func is_idle() -> bool:
	return persistent_reduction <= 0.0 and timed_reduction <= 0.0 and absorb <= 0.0 \
		and _immune_timer <= 0.0 and reflect_flat <= 0 \
		and (oneshot_fraction <= 0.0 or _oneshot_used)


## How much of `amount` actually lands. CONSUMES one-shot soaks and the absorb
## pool, so call it exactly once per hit.
func mitigate(amount: int) -> int:
	if amount <= 0:
		return amount
	if _immune_timer > 0.0:
		return 0
	var remaining: float = float(amount)
	if persistent_reduction > 0.0:
		remaining = remaining * (1.0 - persistent_reduction)
	if timed_reduction > 0.0:
		remaining = remaining * (1.0 - timed_reduction)
	if oneshot_fraction > 0.0 and not _oneshot_used:
		remaining = remaining * (1.0 - oneshot_fraction)
		_oneshot_used = true
	if absorb > 0.0:
		var eaten: float = minf(absorb, remaining)
		absorb -= eaten
		remaining -= eaten
	return maxi(int(round(remaining)), 0)


## Damage to hand back to whoever just landed a melee hit, if anything.
func reflect_payload() -> int:
	return reflect_flat if _reflect_timer > 0.0 else 0
