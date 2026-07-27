class_name SpellDeflect
extends RefCounted
## Makes EVERY attack spell deflectable — including the 24 signature spectacles,
## none of which could be parried before.
##
## WHY THEY COULD NOT BE: the game has two parry paths and a signature fits
## neither. Hero's is projectile-driven (EnemyProjectile calls target.try_parry,
## which refuses anything without a reflect() method); the playground rig's is
## figure-driven (it scans for projectile nodes and calls reflect() on them).
## A signature is not a moving point body at all — it is a one-shot node drawn in
## world coordinates that applies damage ONCE through a geometry query against a
## group fixed at spawn. It never flies at anyone, so nothing ever asked it to be
## parried.
##
## The fix is to deflect at the moment of DAMAGE rather than at the moment of
## travel. Each spectacle passes its hit through resolve() inside the damage loop
## it already runs, so there are no new per-frame queries, no physics, and no
## change to how any spell is aimed or drawn.
##
## POLICY — nothing is unparryable. An ult is not exempt from the defensive verb;
## it is merely BRUTAL to time against, because only the first sliver of your
## parry window counts against it. Making some spells simply unblockable teaches
## players that the defensive read is unreliable, which costs more than any
## balance problem it fixes. Landing one is meant to be the best moment in a
## fight, so it pays off accordingly.
##
## VICTIM CONTRACT (duck-typed, matching this codebase's wall_distance/blink_to
## idiom so Hero, the spike rig, an Enemy and a future bot all work unchanged):
##   is_parrying() -> bool              required; no method = simply takes the hit
##   parry_freshness() -> float         optional; 1.0 = pressed this instant,
##                                      0.0 = window about to lapse. Absent means
##                                      the whole window counts (lenient), so an
##                                      un-upgraded victim never silently loses
##                                      its ability to block ordinary spells.
##   on_spell_deflected(dir: Vector2)   optional; consume the window + strike the pose

## Multiplier applied to a deflected spell's damage. Zero = a clean parry fully
## negates. Named because "chip damage through a parry" is a plausible balance
## answer later, and it must stay one number rather than 24 edits.
const DEFLECTED_DAMAGE_MULT: float = 0.0

## How much of the parry window counts against an ordinary spell: all of it.
const WINDOW_NORMAL: float = 1.0
## ...and against an ult. Only the opening fifth of the window connects, so with
## Hero's 0.16 s parry that is a ~35 ms read — you must commit BEFORE the hit
## rather than react to it. This is the "super hard" dial; raise it if ults end
## up feeling impossible rather than daunting.
const WINDOW_ULT: float = 0.22
## At or below this, a successful deflect is treated as the big moment.
const EPIC_THRESHOLD: float = 0.5


## Would this hit be deflected? Pure query, no side effects — for tests, and for
## callers that must branch before committing to an effect.
static func would_deflect(victim: Node, window_fraction: float = WINDOW_NORMAL) -> bool:
	if victim == null or not is_instance_valid(victim):
		return false
	if not victim.has_method("is_parrying") or not bool(victim.call("is_parrying")):
		return false
	if window_fraction >= WINDOW_NORMAL:
		return true
	# A victim that cannot report how fresh its parry is keeps the lenient
	# behaviour rather than being quietly unable to block ults at all.
	if not victim.has_method("parry_freshness"):
		return true
	return float(victim.call("parry_freshness")) >= (1.0 - window_fraction)


## Run a spell hit past the victim's guard. Returns the damage that should
## actually be applied, so a spell becomes deflectable by threading one call
## through the damage line it already had.
##
## `dir` is the direction the spell was travelling or facing, used to point the
## shield flourish. `at` is the WORLD hit position: spectacles park at the arena
## origin, so their own global_position is (0,0) and the payoff would otherwise
## fire in the wrong place.
static func resolve(victim: Node, damage: int, dir: Vector2, at: Vector2,
		window_fraction: float = WINDOW_NORMAL) -> int:
	if not would_deflect(victim, window_fraction):
		return damage
	if victim.has_method("on_spell_deflected"):
		victim.call("on_spell_deflected", dir)
	if window_fraction <= EPIC_THRESHOLD:
		_epic_payoff(at)
	else:
		_payoff(at)
	return int(round(float(damage) * DEFLECTED_DAMAGE_MULT))


## The ordinary parry beat, deliberately identical to the bolt parry's: players
## must not have to learn two different readings of "I blocked that".
static func _payoff(at: Vector2) -> void:
	_sfx("ding", 2.0)
	Juice.hit_stop(0.09)
	Juice.shake_camera(4.0)
	# Localized, so a deflect off to one side reads there and not at screen centre.
	Juice.impact_frame(0.45, at)


## Turning an ULT is the hardest read in the game, so it gets the loudest beat in
## the game: the full epic crescendo (camera pull-reveal, screen ripple, heavy
## freeze) staged ON the clash rather than at screen centre.
static func _epic_payoff(at: Vector2) -> void:
	_sfx("ding", 4.0)
	_sfx("cannon", 1.0)
	Juice.epic_moment({"strength": 1.35, "shake": 18.0, "frame": true, "at": at})
	CombatVfx.spawn_burst(_arena(), at,
		Color(2.2, 2.0, 1.4, 1.0), Color(1.0, 0.85, 0.4, 0.0),
		34, 0.55, 120.0, 420.0, 1.8, 4.6, 0.0, 0.0, true)


static func _sfx(name: String, pitch: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx: Node = tree.root.get_node_or_null(^"/root/Sfx")
	if sfx != null and sfx.has_method(&"play"):
		sfx.call("play", name, pitch, 0.02)


## Where one-off burst nodes should live. The current scene, not the victim —
## parenting the flourish to a body that dies to the same exchange would cut the
## effect off mid-flight.
static func _arena() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root
