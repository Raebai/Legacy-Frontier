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
## TWO DEFLECT PATHS, AND WHY BOTH EXIST (settle this here rather than in review):
## there is a second contract in the codebase — `reflect()` / `_reflected` /
## `deflect_point()` plus group "deflectable_spell" — used by the bolt, the Rift
## Dagger and the Creeping Shade. They are NOT rivals; they cover different spell
## shapes, and the split is by whether the spell physically TRAVELS.
##
##   TRAVELS  (bolt, dagger, crawler, boulder, orbs) -> the reflect() path.
##            You catch it and send it back. Strictly better fantasy, so it wins
##            wherever it applies, and it is what "deflect" means to a player.
##   DOESN'T  (beams, meteors, zones, walls, pillars, convergence) -> this file.
##            There is nothing to send back — a meteor barrage cannot be returned
##            to sender — so a correctly-timed guard EATS the hit instead.
##
## The rule for new spells: if it has a position that moves, give it reflect().
## Otherwise route its damage through resolve() here. Both end in the same crisp
## ding and the same shield flourish, so players read one defensive verb, not two.
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
##
## THE CONTRACT AND resolve()'s SIGNATURE ARE FROZEN. About fifteen spell scripts
## are being written against `resolve(victim, damage, dir, at, window_fraction)`
## right now; growing an argument or a required method later means fifteen edits
## and a window where half of them are wrong. So the CLASS-SPECIFIC half of the
## guard — the mage's magic circle, which catches a spell and sends it back
## rather than merely eating it — is NOT threaded through here as a parameter.
## It is discovered on the victim, exactly the way GuardComponent is discovered on
## a body in Hero.take_damage: if a SigilGuard node is attached, a confirmed
## deflect is also an absorb. A swordsman has no such node and is unaffected, and
## a spell script never learns the difference exists.

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

## ---------------------------------------------------------------------------
## HOW MANY DEFLECTS HAVE ACTUALLY HAPPENED. Process-wide, monotonic, free.
##
## ⚠ THIS EXISTS BECAUSE "THE MACHINERY IS ALL THERE" IS NOT EVIDENCE THAT IT RUNS.
## `SigilGuard`, `GuardComponent`, the `BotProfile` guard-skill knob and this file
## have coexisted for a long time while nothing anywhere could answer "did a bot ever
## deflect anything". A past session found the entire reflex layer dead behind a
## null-returning helper and every suite stayed green throughout, because an
## invariant that is trivially true of an empty result is not an invariant.
##
## So the harness gets a MINIMUM-OCCURRENCE counter rather than an
## absence-of-badness check: a bot match that produces zero deflects is a failure to
## be reported, not a quiet pass. Keyed by victim group so "the bot deflected" and
## "the human-side body deflected" cannot be confused for one another.
static var deflect_count: int = 0
static var deflects_by_group: Dictionary = {}


## Reset the counters. For harnesses that measure one match at a time.
static func reset_counts() -> void:
	deflect_count = 0
	deflects_by_group = {}


## Record a deflect that did NOT come through `resolve`. There are three ways a
## raised guard turns a hit away in this game and only one of them is this file:
##
##   1. `resolve()` below      non-travelling spells — beams, meteors, zones, walls.
##   2. `Hero.try_parry`       travelling things, caught and SENT BACK via `reflect()`.
##   3. `Hero.take_damage`     melee / contact / charge, dropped by the parry window
##                             or by a PERFECT `ParryRing`.
##
## Counting only (1) is how a harness reports "1 deflect in 18 matches" while bots
## are busily parrying bolts — an understatement that reads exactly like a dead
## feature. One counter, three call sites, so the number means "a guard turned
## something away" rather than "one particular file ran".
static func note_deflect(victim: Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	_count(victim)


static func _count(victim: Node) -> void:
	deflect_count += 1
	# `hero` / `enemy` / `mortal` — whichever faction groups this body carries. A
	# body in none is filed under `ungrouped` rather than dropped, so the total and
	# the breakdown always agree.
	var filed: bool = false
	for g: StringName in [&"hero", &"enemy"]:
		if victim.is_in_group(g):
			deflects_by_group[String(g)] = int(deflects_by_group.get(String(g), 0)) + 1
			filed = true
	if not filed:
		deflects_by_group["ungrouped"] = int(deflects_by_group.get("ungrouped", 0)) + 1


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
	_count(victim)
	if victim.has_method("on_spell_deflected"):
		victim.call("on_spell_deflected", dir)
	# A CASTER catches it in the sigil and sends something back; everyone else
	# eats it. Both branches keep the shared payoff below, on purpose — the ding,
	# the hitstop and the impact frame are what tell the player "you blocked
	# that", and they must sound identical whichever class did it. What the sigil
	# adds on top is its own flare and the returned echo, so the outcome differs
	# without the READ differing. See SigilGuard for what "sent back" means when
	# the spell is a meteor barrage that cannot physically be returned.
	var sigil: SigilGuard = SigilGuard.peek(victim)
	if sigil != null and sigil.is_armed():
		sigil.absorb(damage, dir, at)
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
	# LOCAL, deliberately: an ordinary parry is a small crisp read that happens
	# several times a fight. Giving it a full-screen wash spends the loudest tool
	# in the game on the quietest moment, and makes the ULT turn below indistinct.
	Juice.frame({"style": ImpactFrame.Style.LOCAL, "strength": 0.55, "at": at})


## Turning an ULT is the hardest read in the game, so it gets the loudest beat in
## the game: the full epic crescendo (camera pull-reveal, screen ripple, heavy
## freeze) staged ON the clash rather than at screen centre.
static func _epic_payoff(at: Vector2) -> void:
	_sfx("ding", 4.0)
	_sfx("cannon", 1.0)
	# CUT_IN — the climax mark, and the only place outside a boss death that earns
	# it. Turning an ULT is the hardest read in the game; it previously got the
	# same white wash as an ordinary parry, so the hardest thing a player can do
	# looked identical to the easiest.
	Juice.epic_moment({"strength": 1.35, "shake": 18.0, "frame": false, "at": at})
	Juice.frame({"style": ImpactFrame.Style.CUT_IN, "strength": 1.4, "at": at})
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
