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

## ══ THE GUARD IS A PLANE, AND WHAT YOU CATCH COMES OFF IT ═══════════════════
## Maker, live playtest: *"remember deflect should send the spell back out from the
## deflect angle as well"*.
##
## What was there: `Hero.try_parry` and `Hero._guard_deflect_sweep` both sent the
## caught thing straight down `_aim_dir`. That was already a deliberate choice over
## return-to-sender (see `Hero.try_parry`'s header, which argues it at length) and it
## is not wrong — but it is not an ANGLE. The exit direction ignored where the shot
## came from entirely, so in a duel, where both bots aim at each other, every parry
## looked exactly like return-to-sender and the guard's orientation meant nothing.
##
## What it is now: the guard is a PLANE whose normal is where you are aiming, and the
## incoming line is mirrored about it. Two consequences, both wanted:
##
##   * Meet a shot SQUARE and it goes straight back at whoever sent it. The most
##     satisfying outcome is still the most obvious input, so nothing that felt good
##     before feels worse now.
##   * Meet it at an angle and it skids off at TWICE that angle. Now the aim is a
##     real decision with a real ceiling: you must read the incoming line, not just
##     the timing.
##
## ⚠ THE ONE-LINE REVERT, because this is a feel change on top of a documented
## decision and it may not survive the maker's hands: make `return_dir` return `n`
## unconditionally and every call site is back to aim-direct.
##
## How square the guard must be before the mirror is worth doing. Below this the
## guard is barely in the shot's way, the mirror would let it slide past almost
## unchanged, and "I deflected that and nothing happened" reads as a bug — so a
## glancing guard shoves it along the guard line instead.
##
## It also buys the safety property outright: the mirror's own algebra gives
## `out.dot(n) == -incoming.dot(n)`, so gating on `incoming.dot(n) <= -MIN_FACE_DOT`
## guarantees `out.dot(n) >= MIN_FACE_DOT`. A deflected spell can never come back
## into the body that deflected it. Asserted in `slice_test_deflect_angle.gd`.
const MIN_FACE_DOT: float = 0.25

## ══ THE BEAT, so a deflect READS ════════════════════════════════════════════
## Maker: *"there should be a little like break when a deflect happens so that its
## clear what just happened ... so its more epic"*.
##
## The old beat was `hit_stop(0.09)` + `shake(4)` + a ding — the same weight as an
## ordinary bolt landing. A parry is the rarest good thing a player does and it was
## punctuated like the commonest. Three changes, in the order they matter:
##
##   1. A LONGER FREEZE. `Juice.hit_stop` drives `Engine.time_scale`, so the caught
##      spell visibly STOPS in the air for the duration and then leaves along the new
##      line. The freeze is not decoration — it is the frame that lets you see the
##      angle change, which is the whole of what was asked for.
##   2. A SPARK CONE ALONG THE EXIT. Radial sparks say "something happened here";
##      a cone says "and it went THAT way". This is the half that makes the new
##      deflect angle legible rather than merely correct.
##   3. A ring + a zoom punch, so it lands as a beat rather than a particle.
const DEFLECT_HITSTOP: float = 0.17
const EPIC_HITSTOP: float = 0.30
## ⚠ DELIBERATELY MODEST, and it went 4.0 -> 9.0 -> 6.0 inside one session. The
## first raise was reaching for weight with the wrong tool; the maker's *"the screen
## shake may be too strong ... instagram / tiktok viewers may be uncomfortable"*
## landed while it was still 9.0 and it is right. The freeze and the spark cone are
## what make a deflect READ; shake only makes it loud. Sustained, overlapping shake
## is what reads as nausea to a viewer, and a parry is one of the most frequent good
## things in a fight — so this one in particular must not be a slam.
const DEFLECT_SHAKE: float = 6.0
## How wide the exit spray is. Tight, because a wide cone reads as an explosion
## rather than as a direction.
const SPARK_SPREAD_DEG: float = 26.0

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


## WHERE A DEFLECTED SPELL GOES. `guard_dir` is where the defender is aiming — the
## NORMAL of the guard plane — and `incoming_dir` is the line the spell was flying
## down. Pure, static, and the only place the answer is computed; every deflect path
## in the game routes through here so a parry reads the same whoever did it.
##
## See MIN_FACE_DOT for the doctrine and the one-line revert.
static func return_dir(guard_dir: Vector2, incoming_dir: Vector2) -> Vector2:
	var n: Vector2 = _unit(guard_dir)
	if n == Vector2.ZERO:
		# No guard to speak of. Send it on rather than inventing an angle out of
		# nothing — a zero vector here would stop the spell dead in the air.
		var d0: Vector2 = _unit(incoming_dir)
		return d0 if d0 != Vector2.ZERO else Vector2.RIGHT
	var d: Vector2 = _unit(incoming_dir)
	if d == Vector2.ZERO:
		return n   # nothing known about the shot: the guard line is the best answer
	var facing: float = d.dot(n)
	# The guard is barely in the shot's way. Mirroring here would let it slide past
	# almost unchanged, which reads as a failed deflect. Shove it along the guard.
	if facing > -MIN_FACE_DOT:
		return n
	# Mirror about the plane with normal `n`. Meet it square (d == -n) and this is
	# exactly `n` — straight back at whoever sent it.
	var out: Vector2 = _unit(d - n * (2.0 * facing))
	return out if out != Vector2.ZERO else n


## The line a caught thing was travelling down, asked of the thing itself and only
## guessed as a last resort.
##
## The order matters: `travel_velocity` is the live vector (a bolt that has been
## curved or slowed reports honestly), `reaction_heading` is the clash layer's
## published version, `_dir` is the house member every spectacle keeps, and the
## fallback is the geometric line from the spell to the body it reached — which is
## right for anything that got here without ever declaring a direction.
static func incoming_dir_of(proj: Node, at: Vector2, defender_pos: Vector2) -> Vector2:
	if proj != null and is_instance_valid(proj):
		for m: StringName in [&"travel_velocity", &"reaction_heading"]:
			if proj.has_method(m):
				var v: Vector2 = proj.call(m)
				if v.length_squared() > 0.000001:
					return v.normalized()
		var raw: Variant = proj.get("_dir")
		if raw is Vector2 and (raw as Vector2).length_squared() > 0.000001:
			return (raw as Vector2).normalized()
	return _unit(defender_pos - at)


## The guard plane's normal for `victim`, discovered on the body rather than passed
## in — the same idiom `resolve` uses for `SigilGuard`, and the reason `resolve`'s
## frozen signature did not have to grow an argument to carry the new angle.
static func guard_dir_of(victim: Node) -> Vector2:
	if victim == null or not is_instance_valid(victim):
		return Vector2.ZERO
	for key: StringName in [&"_aim_dir", &"facing"]:
		var raw: Variant = victim.get(key)
		if raw is Vector2 and (raw as Vector2).length_squared() > 0.000001:
			return (raw as Vector2).normalized()
	return Vector2.ZERO


static func _unit(v: Vector2) -> Vector2:
	return v.normalized() if v.length_squared() > 0.000001 else Vector2.ZERO


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
	# Even a spell that cannot be sent back is turned along a LINE, and showing that
	# line is what makes the guard's angle legible. `dir` is the incoming heading and
	# the guard is discovered on the victim, so the sparks fly the same way here as
	# they do on the `reflect()` path — one read, two mechanisms.
	beat(at, return_dir(guard_dir_of(victim), dir), Color(1.0, 0.95, 0.8),
		window_fraction <= EPIC_THRESHOLD)
	return int(round(float(damage) * DEFLECTED_DAMAGE_MULT))


## THE ONE DEFLECT BEAT. Every path that turns something away calls this and nothing
## else: `resolve` above, `Hero.try_parry`, `Hero._guard_deflect_sweep` and
## `HorizonArc`'s sweep. Players must not have to learn two readings of "I blocked
## that", and before this the four sites had drifted into three different weights.
##
## `out_dir` is where the thing is now going. It is the argument that matters — see
## DEFLECT_HITSTOP for why the spray is a cone and not a puff.
## `weight` scales the FREEZE and the SHAKE only — never the sparks, which are the
## readability and must look the same every time. See `_payoff` for why the contact
## paths pass less than 1.0.
static func beat(at: Vector2, out_dir: Vector2, tint: Color = Color(1.0, 0.95, 0.8),
		epic: bool = false, weight: float = 1.0) -> void:
	var dir: Vector2 = _unit(out_dir)
	if epic:
		_epic_payoff(at, dir, tint)
	else:
		_payoff(at, dir, tint, clampf(weight, 0.2, 1.0))


## The ordinary parry beat.
##
## ⚠ `weight` EXISTS BECAUSE THIS FIRES ON CONTACT HITS TOO. `Hero.take_damage` routes
## its two guard branches through here, and a raised guard can eat several blows in
## under a second — at full weight that is `hit_stop(0.17)` re-triggering before the
## last one has released, i.e. the game sitting at `Engine.time_scale = 0.05` for half
## a second. `Juice.hit_stop` REPLACES rather than stacks (a generation counter), so
## it is not unbounded, but a chain of them still reads as the game hanging, and the
## maker has already flagged comfort as a concern for anyone watching.
##
## The travelling-spell parries stay at 1.0: catching a bolt is a discrete, rarer,
## more deserving moment than blocking a punch.
static func _payoff(at: Vector2, out_dir: Vector2, tint: Color,
		weight: float = 1.0) -> void:
	_sfx("ding", 2.0)
	_sfx("blast", -6.0)   # a little body under the ding, so it lands as a HIT
	Juice.hit_stop(DEFLECT_HITSTOP * weight)
	Juice.shake_camera(DEFLECT_SHAKE * weight)
	Juice.zoom_punch_camera(0.045 * weight, 0.16)
	# Localized, so a deflect off to one side reads there and not at screen centre.
	# LOCAL, deliberately: an ordinary parry is a small crisp read that happens
	# several times a fight. Giving it a full-screen wash spends the loudest tool
	# in the game on the quietest moment, and makes the ULT turn below indistinct.
	Juice.frame({"style": ImpactFrame.Style.LOCAL, "strength": 0.8, "at": at})
	_sparks(at, out_dir, tint, 22, 0.34, 260.0, 620.0)


## Turning an ULT is the hardest read in the game, so it gets the loudest beat in
## the game: the full epic crescendo (camera pull-reveal, screen ripple, heavy
## freeze) staged ON the clash rather than at screen centre.
static func _epic_payoff(at: Vector2, out_dir: Vector2, tint: Color) -> void:
	_sfx("ding", 4.0)
	_sfx("cannon", 1.0)
	# CUT_IN — the climax mark, and the only place outside a boss death that earns
	# it. Turning an ULT is the hardest read in the game; it previously got the
	# same white wash as an ordinary parry, so the hardest thing a player can do
	# looked identical to the easiest.
	Juice.epic_moment({"strength": 1.35, "shake": 18.0, "frame": false, "at": at})
	Juice.frame({"style": ImpactFrame.Style.CUT_IN, "strength": 1.4, "at": at})
	Juice.hit_stop(EPIC_HITSTOP)
	CombatVfx.spawn_burst(_arena(), at,
		Color(2.2, 2.0, 1.4, 1.0), Color(1.0, 0.85, 0.4, 0.0),
		34, 0.55, 120.0, 420.0, 1.8, 4.6, 0.0, 0.0, true)
	_sparks(at, out_dir, tint, 40, 0.5, 360.0, 900.0)


## THE HALF THAT ANSWERS "what just happened". A tight cone of sparks down the exit
## line: the freeze holds the picture, the cone says which way it left. A radial puff
## would say neither.
##
## Silently does nothing on a zero direction rather than firing a radial burst — a
## deflect with no known exit should look like nothing rather than like a bomb.
static func _sparks(at: Vector2, out_dir: Vector2, tint: Color, count: int,
		life: float, v_min: float, v_max: float) -> void:
	if out_dir == Vector2.ZERO:
		return
	var arena: Node = _arena()
	if arena == null:
		return
	var hot: Color = Color(
		minf(tint.r * 1.8 + 0.5, 3.0), minf(tint.g * 1.8 + 0.5, 3.0),
		minf(tint.b * 1.8 + 0.5, 3.0), 1.0)
	CombatVfx.spawn_burst(arena, at, hot, Color(tint.r, tint.g, tint.b, 0.0),
		count, life, v_min, v_max, 1.0, 3.0, 0.0, 0.0, true,
		out_dir, SPARK_SPREAD_DEG)


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
