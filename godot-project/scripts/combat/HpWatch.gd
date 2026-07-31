class_name HpWatch
extends RefCounted
## READING AND MOVING A FIGHTER'S HEALTH FROM OUTSIDE IT.
##
## Three of the drop-economy spells need something no spell in this codebase has
## ever needed: to observe or move a body's HP without being the thing that dealt
## the damage.
##   * `Chronostasis` BANKS damage — it has to notice that a frozen body lost HP
##     this frame, give it back, and pay it out later in one lump.
##   * `Petrify` SWALLOWS damage — a statue is stone and takes none, and the hit
##     that would have landed becomes the shove that throws it instead.
##   * `Equinox` MOVES HP toward a mean in both directions.
##
## WHY OBSERVATION AND NOT AN INTERCEPT. The honest way to do all three would be a
## hook inside `take_damage`, which lives on `Hero`/`Enemy` — files this agent does
## not own. Watching `hp` from the outside gets the same answer for EVERY damage
## source in the game (spells, melee, DoT ticks, hazards, other players) without a
## single edit to a damage path, and it cannot be forgotten by a future spell that
## routes its damage some new way. The cost is one frame of latency: a frozen body
## visibly flickers to its post-hit HP and back within a physics tick. UNTESTED
## FEEL GUESS that this is invisible in play; if it is not, the fix is the intercept
## and it belongs in `Hero.take_damage`, not here.
##
## ⚠ NEVER WRITE `hp` DOWNWARD TO KILL SOMETHING. `Hero.take_damage` is what runs
## `_die()`, emits `health_changed`, and (in co-op) routes through the victim's own
## authority. Setting `hp = 0` from outside produces a body at zero health that is
## still walking around. So every DOWNWARD move here goes through
## `SpellTargets.hurt()`, which is also the one call that copes with this codebase's
## two `take_damage` signatures. Only UPWARD moves and RESTORES write `hp` directly,
## and a restore can only ever put back a value the body itself had a frame ago.

## Current HP, or -1 for anything that does not publish one. -1 rather than 0 so a
## caller cannot mistake "no such property" for "dead".
static func hp_of(body: Object) -> int:
	if body == null or not is_instance_valid(body):
		return -1
	var v: Variant = body.get(&"hp")
	return -1 if v == null else int(v)


## Max HP, or -1. Used for the FRACTION Equinox levels; a body with no max is
## simply not part of the levelling rather than being treated as full health.
static func max_hp_of(body: Object) -> int:
	if body == null or not is_instance_valid(body):
		return -1
	var v: Variant = body.get(&"max_hp")
	return -1 if v == null else int(v)


## Health as 0..1, or -1.0 when the body does not publish both halves.
static func fraction_of(body: Object) -> float:
	var cur: int = hp_of(body)
	var mx: int = max_hp_of(body)
	if cur < 0 or mx <= 0:
		return -1.0
	return clampf(float(cur) / float(mx), 0.0, 1.0)


## Alive enough to be a target: valid, not queued for deletion, publishing HP > 0.
static func is_alive(body: Object) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var n: Node = body as Node
	if n != null and n.is_queued_for_deletion():
		return false
	return hp_of(body) > 0


## Put HP back to `value`, clamped to [1, max]. RESTORE ONLY — this is what
## Chronostasis and Petrify call to undo a hit they are swallowing, so the value
## passed is always one the body itself held moments ago.
##
## Clamped to a FLOOR OF 1, deliberately: a restore that could write 0 would leave a
## body at zero health that never ran its death path, which is the exact corpse-
## walking bug this file's header warns about, arrived at from the other direction.
static func restore(body: Object, value: int) -> void:
	if body == null or not is_instance_valid(body):
		return
	var mx: int = max_hp_of(body)
	if mx <= 0:
		return
	body.set(&"hp", clampi(value, 1, mx))
	_notify_health(body, mx)


## Raise HP by `amount`, preferring the body's own `heal()` (Hero has one, and it
## emits + flashes) and falling back to a clamped direct write for anything that
## does not (Enemy, Boss). Never lowers.
static func gain(body: Object, amount: int) -> void:
	if amount <= 0 or body == null or not is_instance_valid(body):
		return
	if body.has_method(&"heal"):
		body.call(&"heal", amount)
		return
	var mx: int = max_hp_of(body)
	var cur: int = hp_of(body)
	if mx <= 0 or cur < 0:
		return
	body.set(&"hp", mini(cur + amount, mx))
	_notify_health(body, mx)


## Nudge the HUD after a direct write. `health_changed` is Hero's; a body without it
## simply redraws from its own bar next frame. Wrapped because a bare
## `emit_signal` on a body that has no such signal is an error, and an error inside
## a static helper aborts whichever spell called it.
static func _notify_health(body: Object, mx: int) -> void:
	if body.has_signal(&"health_changed"):
		body.emit_signal(&"health_changed", hp_of(body), mx)
