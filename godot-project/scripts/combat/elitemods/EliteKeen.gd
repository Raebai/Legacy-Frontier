extends EliteRider
## KEEN — "it was drawn watching you."
##
## It reads your bolts. A keen body hops clear of an incoming projectile, and at
## point-blank it swats one out of the air and fires back.
##
## ── WHY THIS IS THE CHEAPEST AFFIX IN THE SET, AND THE BEST ARGUED ───────────
## It writes NO new behaviour at all. `Enemy._try_evade()` and `Enemy._deflect()` are
## already built, already tuned and already tested — they are the top of the
## difficulty ladder (`Enemy.DIFFICULTY`, HARD unlocks the dodge and IMPOSSIBLE the
## deflect) and on the tower's default difficulty NO enemy ever reaches them. So the
## single best enemy behaviour in the file is dead content on every floor of the
## climb.
##
## An affix is exactly the right unlock for it: instead of raising the difficulty
## setting — which would turn EVERY body in the room into a duellist and make the
## floor a slog — one named, glowing, once-or-twice-a-floor body gets the reflexes,
## and the player learns them on something they can see coming.
##
## ── THE REFLEX IS DELIBERATELY SLOWER THAN IMPOSSIBLE ────────────────────────
## `DIFFICULTY[3].evade_cd` is the setting a player opted into. An affix is something
## the tower did TO them, so `EVADE_COOLDOWN` sits looser: it dodges often enough to
## be a wall you have to solve, not so often that quick spells simply stop existing.
## The answer the fight wants is a shaped spell (a cone, a zone, a wall) or a
## teammate — which is precisely the co-op conversation this game is for.

const EVADE_COOLDOWN: float = 0.85
## Seconds of reaction lag before it commits. Non-zero on purpose: a frame-perfect
## dodge is indistinguishable from cheating.
const REACT_DELAY: float = 0.16


func _setup() -> void:
	# AFTER Enemy._apply_difficulty, which writes all four of these outright from the
	# DIFFICULTY table — a _ready-time edit would be silently overwritten.
	enemy.set("_smart_dodge", true)
	enemy.set("_can_deflect", true)
	enemy.set("_evade_reflex", EVADE_COOLDOWN)
	enemy.set("_react_delay", REACT_DELAY)
