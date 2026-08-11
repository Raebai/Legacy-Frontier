class_name MeleeClash
extends RefCounted
## THE CLASH — two fighters throw a blow at each other inside the same short
## window, and instead of trading damage the blows MEET.
##
## This is the third thing in the defensive vocabulary, and it is worth being
## precise about why it is a separate verb rather than a variant of the other two:
##
##   PARRY  (ParryRing / SigilGuard) — YOU defended. One person committed to
##          offence, the other to defence, and the defender read it right.
##   DEFLECT (SpellDeflect)          — the same act, resolved at the moment a
##          spell's damage lands rather than at the moment something flew at you.
##   CLASH  (this file)              — NOBODY defended. Both committed to offence
##          and neither is wrong; the blows simply cannot both land.
##
## ⚠ A CLASH AND A PARRY CAN NEVER BE CONFUSED, AND THAT IS STRUCTURAL, NOT A
## PRESENTATION CHOICE. `ParryRing.blocks_attack()` is a locked balance rule —
## guarding locks out attacking — so a fighter holding a guard ring is physically
## incapable of declaring a swing, and a fighter declaring a swing has no ring up.
## The two outcomes therefore partition the space rather than overlapping in it.
## On top of that structural split, three read-level differences (see `_beat`):
##   · WHERE — a parry's payoff fires at the DEFENDER's guard; a clash fires at
##     the MIDPOINT between the two fighters, in the empty air where the fists met.
##   · WHAT MOVES — a parry leaves the defender planted and negates one attack; a
##     clash spends BOTH attacks and throws BOTH fighters apart. The symmetry is
##     the tell, and it is visible in one frame.
##   · WHAT IT SOUNDS LIKE — a parry is the bright `ding`; a clash is a heavier
##     ringing crash (see the SFX block).
##
## WHY IT LIVES HERE AND NOT IN Hero. The resolution is a pure decision — who
## declared what, when, aimed at whom, weighing how much — and everything after it
## is duck-typed pokes at whoever declared. Keeping it out of the fighter scripts
## means one rule serves Hero, Enemy, the playground SpikeFigure, bots and co-op
## puppets alike, and means the rule is headless-testable without a scene.
##
## ------------------------------------------------------------------ THE MODEL
##
## A swing DECLARES itself at the moment its owner COMMITS to it — button press /
## telegraph fire — not at the moment it deals damage. That ordering is the whole
## trick, and the obvious alternative does not work:
##
##   ✗ Declare at contact. Fighter A's blow lands and deals damage; 50 ms later B
##     swings and "clashes" with a blow that has already hurt them. To fix that you
##     would have to HOLD every punch for the length of the clash window before
##     resolving it, which taxes every single punch in the game with ~90 ms of
##     input latency to pay for a rare event. Unacceptable.
##   ✓ Declare at commit. Both fighters are inside their wind-up when the clash is
##     decided, the blows are spent BEFORE either could land, and a punch that
##     never meets anything costs exactly nothing. Zero added latency.
##
## So a fighter with a wind-up (Hero: ~77 ms from `_melee()` to the rig's
## `hit_frame`) declares at commit and asks `consume_spent()` at contact. A fighter
## whose commit IS its contact (an Enemy resolving a telegraphed strike, the
## playground's `punched` signal) uses `declare_and_spend()` and gets its answer in
## one call.

## ---------------------------------------------------------------------------
## THE ENTIRE CLASH TIMING BUDGET — kept together, named, because every number in
## this block is REASONED AND UNPLAYTESTED. Grouped the way ParryRing groups the
## defensive budget, so the maker tunes the feel in one place.
## ---------------------------------------------------------------------------

## ⭐ THE ONE NUMBER. How far apart two commits may sit and still count as
## SIMULTANEOUS. This tolerance IS the feature: a clash gated on the exact same
## frame would fire approximately never at 60 Hz, and a feature that never fires is
## a feature nobody knows exists.
##
## 0.09 s is ±5.4 frames at 60 Hz, an 0.18 s mutual band. Three reasons for that
## size rather than a rounder one:
##   1. It clears the noise floor. Frame quantisation (16.7 ms), input polling and
##      — once co-op is real — network jitter all sit an order of magnitude below
##      it, so the clash fires because two people meant it, not because the clock
##      was kind.
##   2. It is SMALLER THAN EVERY MELEE COOLDOWN IN THE GAME (the shortest is the
##      Brawler's 0.20 s). That bound is load-bearing: it means no fighter can ever
##      clash on two consecutive swings by cadence alone, which is the failure mode
##      that would turn every exchange into a clash and delete melee.
##   3. It is close to the BLADE perfect-parry band (~0.09 s, ParryRing). One
##      order of tolerance for "you two moved together" and "you read that right"
##      means the game asks for one standard of timing, not two.
##
## UNTESTED GUESS. If clashes feel too RARE in the first playtest, this is the
## number to raise, and 0.12 is the next stop. If every trade turns into a clash,
## drop it to 0.06 before touching anything else. Change THIS, not the reach.
const CLASH_WINDOW: float = 0.09

## Enforced gap before the same fighter may clash AGAIN. Without it the loop can
## lock: two fighters clash, are thrown apart, both swing on the way back in, clash
## again, forever, with neither ever taking damage. The refractory guarantees the
## second simultaneous swing is a real TRADE, so the rhythm is "clash, then a
## genuine exchange" rather than a stalemate machine. It also makes the window
## itself safe to be generous with, which is why it exists at all.
## UNTESTED GUESS: 0.45 s ≈ the time to be thrown apart and close again.
const CLASH_REFRACTORY: float = 0.45

## How long a declaration is remembered at all. Must comfortably exceed the longest
## commit->contact gap in the game so `consume_spent()` can still find its own
## entry (Hero ~0.08 s; an Enemy's telegraph resolves at commit, so it needs none).
## Longer than CLASH_WINDOW on purpose — these are two different lifetimes:
## PAIRING uses the window, REMEMBERING uses this.
const DECLARATION_TTL: float = 0.80

## Slack added to each fighter's reach for the clash test only. Declarations happen
## at COMMIT, and both fighters are still closing — every plain swing carries a
## forward lunge (Hero's MELEE_LUNGE_SPEED, SpikeFigure's punch_lunge) — so the gap
## measured at commit is wider than the gap the fists actually meet at. Without
## this the clash would demand the fighters already be touching.
## UNTESTED GUESS: about one lunge-step. Prefer tuning CLASH_WINDOW first; a bonus
## large enough to cover a whole approach would let people clash across a room.
const CLASH_REACH_BONUS: float = 22.0

## How squarely each fighter must be aimed at the other. Deliberately LOOSE (~81°
## either side of the swing direction): the clash's job is to catch "we both went
## for each other", and demanding near-perfect mutual alignment would make it as
## rare as the same-frame test this exists to avoid. It still refuses the cases
## that would read as a bug — swinging away from someone, or at the air past them.
const CLASH_AIM_DOT: float = 0.15

# ------------------------------------------------------------------ THE WEIGHT
## A clash is decided by SpellTier WEIGHT — the exact vocabulary the spell-clash
## system already speaks (equal weight → both cancel; heavier → overpowers). This
## is a deliberate refusal to invent a second notion of "how much does this blow
## weigh", because two such notions inevitably disagree and the player is then
## learning two rules that look like one.
##
## Where the spell system derives weight from what a spell COSTS YOU (cast time,
## cooldown, mana), melee has no mana and its wind-ups are already spent as the
## dodge/parry tell. So the melee axis is DAMAGE — which is also the honest answer
## to "which of these two blows looks heavier", and the one a player can predict
## without opening a menu.
##
## Note what is deliberately NOT in here: WIND-UP LENGTH. A long telegraph is what
## makes an attack dodgeable and parryable in the first place; charging it extra
## clash weight on top would pay it twice, and would make an Enemy brute's slam
## unbeatable by any player swing. Under the rule as written a brute's 22-damage
## slam is QUICK — a Juggernaut's greatsword sweeps it aside, a jab trades evenly
## with it and both are thrown. Both of those read correctly.
const WEIGHT_AUTO: int = -1
## At or above this damage a blow is HEAVY (Juggernaut 30, greatsword 26, the
## dash-strikes 16-24 sit below). UNTESTED GUESS: chosen to put exactly the swings
## that LOOK like two-handed commitments on the upper shelf.
const HEAVY_DAMAGE: int = 24
## ...and ULT. Nothing in melee reaches this today, on purpose: the top shelf is
## reserved for a boss finisher that should shrug off anything a player can throw,
## and such a caller opts in EXPLICITLY by passing its own weight rather than
## qualifying by accident through a damage buff.
const ULT_DAMAGE: int = 45

# --------------------------------------------------------------- THE OUTCOME
## Impulse each fighter takes on an EVEN clash — symmetric, because symmetry is
## the honest default when neither side did anything better than the other.
const THROW_APART: float = 460.0
## What the LOSER of an uneven clash takes. Bigger than an even clash's share:
## being outweighed should look like being swatted, not like a mutual bounce.
const OVERPOWER_THROW: float = 620.0
## Freeze on an even clash. Heavier than a melee connect (Hero's 0.07) because the
## freeze is what sells the moment — but short of a full `impact_frame` freeze so
## the beat still belongs to combat rather than stopping the match.
const CLASH_HIT_STOP: float = 0.13
## ...and on an overpower. LIGHTER, because the winner's blow is still travelling
## and a long freeze would rob it of its follow-through.
const OVERPOWER_HIT_STOP: float = 0.06
const CLASH_SHAKE: float = 9.0
const OVERPOWER_SHAKE: float = 5.0
## Strength passed to the anime impact frame. Staged at the MEETING POINT, never at
## screen centre — `Juice.impact_frame` takes a world position precisely because a
## previous bug whited out the middle of the screen regardless of where the hit was.
const CLASH_FRAME_STRENGTH: float = 0.55
## Rig recoil: how limp the flop goes and how hard the limbs are jolted. Reuses the
## rigs' existing flop/limp machinery (maker directive: the rig is a Stick-Fight
## ACTIVE RAGDOLL, not canned poses) at clash amplitude.
const RECOIL_FLOP: float = 0.62
const RECOIL_FLOP_HOLD: float = 0.20
const RECOIL_LIMB_JOLT: float = 520.0

## THE SOUND. Named so that adopting the dedicated stem is one edit per outcome
## rather than a hunt through the beat.
##
## 🔔 REQUESTED FROM THE SOUND PASS: a key named "clash" — two blades / two fists
## MEETING head-on. Wanted character: a bright metallic ring with real body under
## it (weight, not just a tink), longer tail than `ding` since it is a rarer and
## bigger moment, and audibly DISTINCT from `ding` — `ding` already means "you
## blocked that" for both parry paths, and a clash must not be mistaken for a
## parry by ear. A second key "clash_overpower" would be welcome for the uneven
## case: duller, a grinding shove rather than a ring, so "I got swatted" and "we
## met evenly" are separable with your eyes shut.
##
## Until those keys exist these point at guaranteed-present stems, because
## `Sfx.play` warns and BAILS on an unknown key — a missing stem would silently
## mute the whole beat rather than failing loudly.
const SFX_CLASH: String = "ding"
const SFX_CLASH_BODY: String = "melee_hit"
const SFX_OVERPOWER: String = "melee_hit"

## Outcome strings, so callers and tests never spell one wrong.
const OUTCOME_NONE: String = "none"
const OUTCOME_EVEN: String = "even"
const OUTCOME_OVERPOWERED: String = "overpowered"   # this declarer WON
const OUTCOME_OUTWEIGHED: String = "outweighed"     # this declarer LOST

## Test seam, mirroring SpellReactor.spawn_effects: false = resolve and report
## exactly as normal but fire no juice. Lets the RULE be proven headlessly without
## a 0.13 s time-scale freeze and an impact-frame node inside a suite.
static var effects_enabled: bool = true

## Live declarations, newest last. Plain dicts, pruned by age on every declare, so
## this never needs a node, an autoload or a poll — and therefore works identically
## in the playground, the arena, a headless test and a co-op puppet.
## {node, id, pos, dir, reach, weight, ms, spent}
static var _live: Array[Dictionary] = []
## instance id -> ms of that fighter's last clash. Enforces CLASH_REFRACTORY.
static var _last_clash_ms: Dictionary = {}


# --------------------------------------------------------------- pure predicates
# Everything in this section is a total function of its arguments. They are the
# testable core; `declare()` is these three plus bookkeeping.

## Two commits count as simultaneous. `absi` on integer milliseconds rather than
## float seconds so the comparison cannot drift with accumulated error.
static func timing_matches(a_ms: int, b_ms: int) -> bool:
	return absi(a_ms - b_ms) <= int(round(CLASH_WINDOW * 1000.0))


## Is a swing thrown from `from` along `dir` pointing at `toward`? Loose by design
## (see CLASH_AIM_DOT). A zero direction or a zero separation cannot aim at
## anything, and answers false rather than accidentally passing a dot of 0.
static func aims_at(from: Vector2, dir: Vector2, toward: Vector2) -> bool:
	var sep: Vector2 = toward - from
	if dir == Vector2.ZERO or sep.length_squared() <= 0.0001:
		return false
	return dir.normalized().dot(sep.normalized()) >= CLASH_AIM_DOT


## The shelf a blow fights on, from what it hits for. See the WEIGHT block above
## for why damage and not wind-up.
static func weight_for(damage: int) -> int:
	if damage >= ULT_DAMAGE:
		return SpellTier.Tier.ULT
	if damage >= HEAVY_DAMAGE:
		return SpellTier.Tier.HEAVY
	return SpellTier.Tier.QUICK


## What happens when a blow weighing `mine` meets one weighing `theirs`, from the
## point of view of the blow weighing `mine`.
##
## This delegates ENTIRELY to SpellTier rather than re-implementing the comparison,
## which is the point: retune a spell's tier thresholds and melee clashes move with
## them, and a player who has learned "my ult ate their jab" from a beam crossing
## already knows what a greatsword does to a punch.
static func resolve_outcome(mine: int, theirs: int) -> String:
	if SpellTier.weights_match(mine, theirs):
		return OUTCOME_EVEN
	return OUTCOME_OVERPOWERED if SpellTier.outweighs(mine, theirs) else OUTCOME_OUTWEIGHED


# ------------------------------------------------------------------- the API

## Commit a swing and resolve it against every other live commit.
##
## `dir` is the swing direction, `reach` its range, `damage` what it would hit for
## (used to derive weight unless `weight` is given). `now_ms` is a test seam:
## -1 reads the real clock. The clock is `Time.get_ticks_msec` — REAL time, not
## delta-accumulated, so a hit-stop freezing `Engine.time_scale` to 0.05 cannot
## stretch the clash window under the players' feet.
##
## Returns {clashed, spent, outcome, opponent, at}. `spent` is the one the caller
## acts on: true means this blow was consumed by the clash and MUST NOT also deal
## damage. A blow that outweighed its rival is NOT spent — it keeps going.
static func declare(attacker: Node, dir: Vector2, reach: float, damage: int,
		weight: int = WEIGHT_AUTO, now_ms: int = -1) -> Dictionary:
	var result: Dictionary = {
		"clashed": false, "spent": false, "outcome": OUTCOME_NONE,
		"opponent": null, "at": Vector2.ZERO,
	}
	var pos: Vector2 = _pos_of(attacker)
	if pos == Vector2.INF:
		return result   # nothing with a world position can meet anything
	var ms: int = now_ms if now_ms >= 0 else Time.get_ticks_msec()
	_prune(ms)
	var w: int = weight_for(damage) if weight == WEIGHT_AUTO else SpellTier.weight_or_default(weight)
	var mine: Dictionary = {
		"node": attacker, "id": attacker.get_instance_id(), "pos": pos,
		"dir": dir, "reach": reach, "weight": w, "ms": ms, "spent": false,
	}
	var rival: Dictionary = _find_rival(mine, ms)
	# Registered whether or not it clashed: an unmatched commit is exactly what the
	# NEXT fighter to commit needs to find, and `consume_spent` needs the entry to
	# report against even in the ordinary no-clash case.
	_live.append(mine)
	if rival.is_empty():
		return result
	var at: Vector2 = (Vector2(mine["pos"]) + Vector2(rival["pos"])) * 0.5
	var outcome: String = resolve_outcome(int(mine["weight"]), int(rival["weight"]))
	# BOTH sides are marked here, not one at a time on their own next call. The
	# clash is a single event with two victims, and resolving it twice (once per
	# fighter) is how the two halves would drift into disagreeing about it.
	_apply(mine, rival, outcome, at, ms)
	result["clashed"] = true
	result["spent"] = bool(mine["spent"])
	result["outcome"] = outcome
	result["opponent"] = rival["node"]
	result["at"] = at
	return result


## Was this fighter's most recent commit spent by a clash? CONSUMES the flag, so a
## swing can only be cancelled once.
##
## This is the second half of the deferred-contact case: a fighter whose blow lands
## some time after it commits (Hero, whose rig fires `hit_frame` ~77 ms into the
## swing) declares at commit and asks this at contact.
static func consume_spent(attacker: Node) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	var id: int = attacker.get_instance_id()
	# Newest first: a fighter mid-combo has several entries and only the live swing
	# can be the one being resolved right now.
	for i: int in range(_live.size() - 1, -1, -1):
		if int(_live[i]["id"]) != id:
			continue
		var spent: bool = bool(_live[i]["spent"])
		_live[i]["spent"] = false
		return spent
	return false


## Commit and answer "was it spent" in one call — for a fighter whose commit IS its
## contact (an Enemy resolving a telegraphed strike, the playground's `punched`).
static func declare_and_spend(attacker: Node, dir: Vector2, reach: float, damage: int,
		weight: int = WEIGHT_AUTO, now_ms: int = -1) -> bool:
	return bool(declare(attacker, dir, reach, damage, weight, now_ms)["spent"])


## Drop all state. For tests and for a scene change — instance ids from a freed
## arena must never pair with a fresh one.
static func reset() -> void:
	_live.clear()
	_last_clash_ms.clear()


## Live declaration count. Diagnostics + tests.
static func live_count() -> int:
	return _live.size()


# ------------------------------------------------------------------- internals

## The best rival for `mine`, or {} if this swing meets nothing.
##
## Note what is NOT here: any search of the world. Only DECLARED swings are
## candidates, so this is O(live commits) — a number that is 0 or 1 almost always —
## and it costs nothing at all in the overwhelmingly common case of one person
## punching a crate. It also means the rule needs no knowledge of teams, groups or
## scenes: anything that declares can clash, which is what makes bots, enemies,
## co-op partners and playground dummies all work with no extra code.
static func _find_rival(mine: Dictionary, ms: int) -> Dictionary:
	if _cooling_down(int(mine["id"]), ms):
		return {}
	var best: Dictionary = {}
	for i: int in range(_live.size() - 1, -1, -1):
		var other: Dictionary = _live[i]
		if int(other["id"]) == int(mine["id"]):
			continue                     # you cannot clash with yourself
		if bool(other["spent"]):
			continue                     # already consumed by another clash
		if not timing_matches(ms, int(other["ms"])):
			continue                     # ⭐ THE WINDOW — the negative case
		if _cooling_down(int(other["id"]), ms):
			continue
		var on: Node = other["node"]
		if on == null or not is_instance_valid(on):
			continue
		if not _mutually_engaged(mine, other):
			continue
		# Newest-first scan, so the FIRST match is the nearest in time. That is the
		# right tiebreak in a three-way: the two people who moved together clash,
		# and the straggler's blow lands on whoever is left.
		best = other
		break
	return best


## Are these two swings actually aimed at each other, in range of each other?
## BOTH directions are required. A one-sided test would let someone clash a blow
## thrown at somebody else entirely, which reads as a bug even when the timing was
## genuinely simultaneous.
static func _mutually_engaged(a: Dictionary, b: Dictionary) -> bool:
	var pa: Vector2 = a["pos"]
	var pb: Vector2 = b["pos"]
	if not aims_at(pa, a["dir"], pb) or not aims_at(pb, b["dir"], pa):
		return false
	# Reach measured to the DRAWN BODY, never to the origin. An enemy's head sits
	# ~10 px above its origin (19 px on the 1.9x sparring dummies) — a raw
	# global_position test is the maker-reported "spells pass through heads" bug,
	# and a clash test written that way would refuse clashes that visibly happened.
	return SpellTargets.hits(b["node"], pa, float(a["reach"]) + CLASH_REACH_BONUS) \
		and SpellTargets.hits(a["node"], pb, float(b["reach"]) + CLASH_REACH_BONUS)


## Mark both blows, throw both bodies, fire the beat.
static func _apply(mine: Dictionary, rival: Dictionary, outcome: String,
		at: Vector2, ms: int) -> void:
	var pa: Vector2 = mine["pos"]
	var pb: Vector2 = rival["pos"]
	# The axis they are thrown along: away from each other. Falls back to the
	# swing direction if two fighters are somehow exactly co-located.
	var apart: Vector2 = (pa - pb).normalized()
	if apart == Vector2.ZERO:
		apart = Vector2(-1.0, 0.0)
	_last_clash_ms[int(mine["id"])] = ms
	_last_clash_ms[int(rival["id"])] = ms
	match outcome:
		OUTCOME_EVEN:
			# Both blows spent, both fighters thrown, same force each way. Nobody
			# earned an advantage, so nobody gets one.
			mine["spent"] = true
			rival["spent"] = true
			_recoil(mine["node"], apart, THROW_APART)
			_recoil(rival["node"], -apart, THROW_APART)
		OUTCOME_OVERPOWERED:
			# `mine` is heavier: its blow is NOT spent — it keeps going and will
			# still land — while the lighter one is cancelled and its owner swatted.
			rival["spent"] = true
			_recoil(rival["node"], -apart, OVERPOWER_THROW)
		OUTCOME_OUTWEIGHED:
			mine["spent"] = true
			_recoil(mine["node"], apart, OVERPOWER_THROW)
	_beat(outcome, at)


## Throw one fighter, and make their RIG react.
##
## Duck-typed in the codebase's `wall_distance` / `blink_to` idiom, so Hero, Enemy,
## the playground SpikeFigure, a bot and a co-op puppet all work unchanged and a
## body that implements none of it simply does not move:
##   on_clash(dir, strength)         first choice — a body that wants its own recoil
##   apply_knockback(impulse, flop)  Hero / Enemy (already flops the rig for us)
##   hit(dir, strength)              SpikeFigure's knock-back-and-flinch
##
## The rig is driven SEPARATELY and additionally, because a clash recoil is not a
## knockback flop: the arm that just met steel should bounce back harder than the
## body does. `clash_recoil` is looked up on a `rig` member, so the shipped
## CharacterRig gets its reaction without the fighter script needing an edit.
static func _recoil(body: Node, dir: Vector2, strength: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_method(&"on_clash"):
		body.call(&"on_clash", dir, strength)
	elif body.has_method(&"apply_knockback"):
		# Flattened toward the horizontal for the same reason every radial shove is:
		# two fighters at the same height produce a near-horizontal axis anyway, but
		# a height difference would otherwise fire someone at the ceiling.
		body.call(&"apply_knockback", Juice.lateral_knockback(dir * strength), true)
	elif body.has_method(&"hit"):
		body.call(&"hit", dir, strength)
	var rig: Variant = body.get(&"rig")
	# ⚠ VALIDITY BEFORE `is`. `body` is checked further up, but the `hit` /
	# `apply_knockback` calls between there and here can KILL the body and free its rig
	# inside this same call — so the stale reference is manufactured a few lines above.
	if is_instance_valid(rig) and rig is Node and rig.has_method(&"clash_recoil"):
		rig.call(&"clash_recoil", dir, clampf(strength / OVERPOWER_THROW, 0.4, 1.0))


## THE BEAT. Composed from the same primitives, in the same order, as
## SpellDeflect._payoff — sfx, then camera, then the located frame, with the
## freeze LAST because it awaits and everything else must land before time stops.
## Keeping the grammar identical is deliberate: a clash is a different EVENT from a
## deflect, but it must not feel like it came from a different game.
static func _beat(outcome: String, at: Vector2) -> void:
	if not effects_enabled:
		return
	if outcome == OUTCOME_EVEN:
		# Two layers: the ring of steel meeting steel, and the body of the collision
		# under it. One stem alone reads either thin or muddy.
		_sfx(SFX_CLASH, 0.0, 0.72)
		_sfx(SFX_CLASH_BODY, 2.0, 0.9)
		Juice.shake_camera(CLASH_SHAKE)
		Juice.zoom_punch_camera(0.10, 0.20)
		# Sparks at the meeting point — white-hot core fading to gold, additive so
		# overlapping motes build rather than average to grey.
		CombatVfx.spawn_burst(_arena(), at,
			Color(2.4, 2.2, 1.6, 1.0), Color(1.0, 0.8, 0.35, 0.0),
			30, 0.45, 150.0, 480.0, 1.4, 3.8, 0.0, 0.0, true)
		# SILHOUETTE, not the white blow-out. A clash is a REACTION payoff, not a
		# concussion: the thing worth seeing is the shape of two fighters frozen
		# leaning into each other with the sparks between them, and white erases
		# exactly that. The black cut keeps both bodies and the spark core lit.
		Juice.frame({"style": ImpactFrame.Style.SILHOUETTE,
			"strength": CLASH_FRAME_STRENGTH, "at": at})
		# Fired AFTER impact_frame on purpose: impact_frame's own ripple is centred
		# on the screen, and shock is single-slot, so this overwrites it with one
		# staged at the actual crossing. Same reason resolve() passes `at` around.
		PostProcess.shock(1.0, Juice.world_to_uv(at))
		Juice.hit_stop(CLASH_HIT_STOP)
	else:
		# The uneven case is a SHOVE, not a meeting: no impact frame, no ripple, a
		# duller stem and a shorter freeze, so the winner's blow keeps its momentum.
		_sfx(SFX_OVERPOWER, -1.0, 0.5)
		Juice.shake_camera(OVERPOWER_SHAKE)
		CombatVfx.spawn_burst(_arena(), at,
			Color(1.6, 1.4, 1.0, 0.9), Color(0.8, 0.6, 0.25, 0.0),
			16, 0.35, 90.0, 260.0, 1.0, 2.6, 0.0, 0.0, true)
		Juice.hit_stop(OVERPOWER_HIT_STOP)


static func _cooling_down(id: int, ms: int) -> bool:
	if not _last_clash_ms.has(id):
		return false
	return ms - int(_last_clash_ms[id]) < int(round(CLASH_REFRACTORY * 1000.0))


## Drop declarations past their TTL, freed nodes, and stale refractory entries.
## Runs on every declare, which is the only moment the list can grow — so there is
## no timer, no `_process` and nothing to forget to tick.
static func _prune(ms: int) -> void:
	var ttl_ms: int = int(round(DECLARATION_TTL * 1000.0))
	for i: int in range(_live.size() - 1, -1, -1):
		# Untyped on purpose: assigning an already-freed instance to a typed `Node`
		# is itself an error in GDScript, which would make the sweep throw on
		# exactly the entries it exists to remove (the SpellReactor._sweep_invalid
		# idiom).
		var n: Variant = _live[i]["node"]
		if n == null or not is_instance_valid(n) or ms - int(_live[i]["ms"]) > ttl_ms:
			_live.remove_at(i)
	var refractory_ms: int = int(round(CLASH_REFRACTORY * 1000.0))
	for id: int in _last_clash_ms.keys():
		if ms - int(_last_clash_ms[id]) >= refractory_ms:
			_last_clash_ms.erase(id)


## World position of a declaring body, or INF when it has none — INF fails every
## `<=` test, so a non-positional declarer can never accidentally clash.
##
## ⚠ THE TRANSFORM TRAP, THE MELEE EDITION — the same one SpellReactor is built
## around, and it bit this file in its first capture. A `global_position` read is
## right for Hero and Enemy (CharacterBody2D — the node IS the body), and WRONG for
## the playground SpikeFigure, whose node never moves at all: its whole body hangs
## off a `_torso` RigidBody2D child, so `global_position` reports the spawn origin
## forever. Two figures brawling across an arena both answered (0, 0), the
## separation between them was zero, `aims_at` refused every pair, and the clash
## silently never fired. It was invisible in the code and obvious in the capture,
## which is the whole argument for rendering one.
##
## So the position is ASKED FOR first — duck-typed in the codebase's
## `body_distance` / `blink_to` idiom — and only falls back to the transform for
## bodies that genuinely are their own position.
static func _pos_of(body: Node) -> Vector2:
	if body == null or not is_instance_valid(body):
		return Vector2.INF
	if body.has_method(&"body_origin"):
		return body.call(&"body_origin") as Vector2
	var n2: Node2D = body as Node2D
	return n2.global_position if n2 != null else Vector2.INF


## ⚠ The autoloads are NOT registered under `--script`, and naming `Sfx` inside a
## static function is a COMPILE error that takes the whole dependency chain with
## it. Resolved off the tree instead, exactly as SpellDeflect._sfx does.
static func _sfx(key: String, db: float, pitch_var: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx: Node = tree.root.get_node_or_null(^"/root/Sfx")
	if sfx != null and sfx.has_method(&"play"):
		sfx.call("play", key, db, pitch_var)


## Where one-off burst nodes live: the current scene, never a fighter — parenting
## the sparks to a body that gets thrown (or dies to the follow-up) would drag or
## cut the effect off mid-flight.
static func _arena() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root
