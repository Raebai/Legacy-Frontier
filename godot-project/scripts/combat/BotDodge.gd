class_name BotDodge
extends RefCounted
## The DODGE BRAIN — pure threat geometry + response selection, with no body.
##
## Everything here is a static function over plain values, so the whole brain is
## headless-testable without spawning a scene, and the same module drives an
## Enemy today and a hero-shaped bot later. Nothing in this file knows what a
## Hero or an Enemy is; callers pass in what they can see and read back a
## decision.
##
## WHY THIS IS ANALYTICALLY SOLVABLE, not a search: every telegraphed attack in
## this game snapshots its target and plants a region that then never moves
## (Enemy._start_windup and friends). So the question is only ever "will my
## predicted position at fire time sit inside that region, and if so what is the
## shortest way out". No sampling, no pathfinding. It also means MOVING AT ALL
## beats a snapshot tell — which is exactly why the brain solves for an exit
## vector out of the region rather than just fleeing the caster.
##
## FAIRNESS IS STRUCTURAL: a bot may only be handed things a human can see on
## screen (a drawn telegraph, a visible projectile). Difficulty comes from the
## reaction delay and whiff rate in Reactions below — never from extra knowledge
## and never from damage buffs.

## How far ahead a projectile is worth solving for. Beyond this the prediction is
## noise, because the bot will have moved.
const HORIZON: float = 0.9
const BODY_R: float = 10.0
## Padding on every containment test. Dodging to the exact edge of a blast reads
## as getting clipped, so the brain treats regions as slightly larger than drawn.
const MARGIN: float = 14.0
## A dash only counts as an i-frame answer if impact lands inside the dash.
const IFRAME_LEAD: float = 0.16
## Above this share of vertical, an exit is better served by jumping than walking.
const VERTICAL_EXIT_DOT: float = 0.72


# ---- threat evaluation -----------------------------------------------------

## Closest approach of a moving point to a stationary bot. Treating the bot as
## static over the horizon is accurate enough at this game's projectile speeds
## (260-460 px/s) and keeps the solve to one dot product.
## Returns {t, miss}: when the pass happens and how near it comes.
static func closest_approach(me: Vector2, tpos: Vector2, tvel: Vector2,
		horizon: float = HORIZON) -> Dictionary:
	var v2: float = tvel.length_squared()
	if v2 <= 0.0001:
		return {"t": 0.0, "miss": me.distance_to(tpos)}
	var rel: Vector2 = tpos - me
	var t: float = clampf(-rel.dot(tvel) / v2, 0.0, horizon)
	return {"t": t, "miss": (rel + tvel * t).length()}


## A projectile is a threat when it will pass within body+margin inside the
## horizon. A receding projectile clamps t to 0 and therefore reports its current
## (large) distance, so it correctly reads as harmless.
static func threat_from_projectile(me: Vector2, tpos: Vector2, tvel: Vector2,
		margin: float = MARGIN) -> Dictionary:
	var ca: Dictionary = closest_approach(me, tpos, tvel)
	var reach: float = BODY_R + margin
	var hit: bool = float(ca["miss"]) < reach and float(ca["t"]) < HORIZON
	# Step off the lane sideways: perpendicular to travel is the shortest exit.
	var normal: Vector2 = tvel.orthogonal().normalized() if tvel.length_squared() > 0.0001 \
		else Vector2.RIGHT
	var side: float = signf((me - tpos).dot(normal))
	if side == 0.0:
		side = 1.0
	var need: float = maxf(reach - float(ca["miss"]), 0.0)
	return {
		"threatening": hit,
		"tti": float(ca["t"]),
		"exit": normal * side * need,
		"exit_len": need,
		"degenerate": false,
	}


## Circle zone. Predict where I will be when it fires; if that point is inside,
## the shortest exit is straight out along the radius.
static func threat_from_circle(me: Vector2, my_vel: Vector2, center: Vector2,
		radius: float, tti: float, margin: float = MARGIN) -> Dictionary:
	var predicted: Vector2 = me + my_vel * maxf(tti, 0.0)
	var reach: float = radius + margin
	var away: Vector2 = predicted - center
	var dist: float = away.length()
	var need: float = maxf(reach - dist, 0.0)
	# Dead-centre: there is no shortest way out, every direction is equal. Report
	# it so the caller picks by open ground instead of by geometry.
	if dist <= 0.0001:
		return {"threatening": true, "tti": tti, "exit": Vector2.ZERO,
			"exit_len": reach, "degenerate": true}
	return {
		"threatening": dist < reach,
		"tti": tti,
		"exit": (away / dist) * need,
		"exit_len": need,
		"degenerate": false,
	}


## Lane / OBB zone. Work in the lane's own frame: rotate the predicted point back
## by the lane angle, then it is a plain box test, and the exit is perpendicular.
static func threat_from_lane(me: Vector2, my_vel: Vector2, from: Vector2, angle: float,
		length: float, width: float, tti: float, margin: float = MARGIN) -> Dictionary:
	var predicted: Vector2 = me + my_vel * maxf(tti, 0.0)
	var local: Vector2 = (predicted - from).rotated(-angle)
	var half: float = width * 0.5 + margin
	var inside: bool = local.x >= 0.0 and local.x <= length and absf(local.y) <= half
	var side: float = 1.0 if local.y >= 0.0 else -1.0
	var need: float = maxf(half - absf(local.y), 0.0)
	var normal: Vector2 = Vector2.from_angle(angle + PI * 0.5)
	return {
		"threatening": inside,
		"tti": tti,
		"exit": normal * side * need,
		"exit_len": need,
		"degenerate": false,
	}


# ---- safety ----------------------------------------------------------------

## Never dodge out of a blast and into a pit, and never into a second live
## telegraph. Scores each candidate exit and returns the safest, or Vector2.ZERO
## when every option is bad (caller should then stand and take it, or parry).
## `hazards` are world-space Rect2 pits; `regions` are other danger footprints in
## the {shape,...} form Telegraph.danger_shape() returns.
static func safest_exit(me: Vector2, candidates: Array[Vector2],
		hazards: Array[Rect2], regions: Array[Dictionary]) -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	for c: Vector2 in candidates:
		var landing: Vector2 = me + c
		var score: float = 0.0
		for pit: Rect2 in hazards:
			if pit.grow(MARGIN).has_point(landing):
				score -= 1000.0        # a pit is death; nothing outscores avoiding it
		for r: Dictionary in regions:
			if point_in_region(landing, r):
				score -= 100.0
		score -= c.length() * 0.01     # all else equal, prefer the shorter move
		if score > best_score:
			best_score = score
			best = c
	return best if best_score > -1000.0 else Vector2.ZERO


## Containment test against a Telegraph.danger_shape() dictionary.
static func point_in_region(p: Vector2, region: Dictionary) -> bool:
	match String(region.get("shape", "")):
		"circle":
			var c: Vector2 = region.get("center", Vector2.ZERO)
			return p.distance_to(c) < float(region.get("radius", 0.0)) + MARGIN
		"line":
			var a: Vector2 = region.get("from", Vector2.ZERO)
			var b: Vector2 = region.get("to", Vector2.ZERO)
			var seg: Vector2 = b - a
			var len2: float = seg.length_squared()
			if len2 <= 0.0001:
				return false
			var t: float = clampf((p - a).dot(seg) / len2, 0.0, 1.0)
			return p.distance_to(a + seg * t) < float(region.get("width", 0.0)) * 0.5 + MARGIN
	return false


# ---- response selection ----------------------------------------------------

## First affordable rung wins. Ordered by how decisively each one beats a threat,
## not by cost: a dash that clears the region is strictly better than a parry
## that has to be timed, which is better than walking out and hoping.
##
## `caps` describes what this body can currently do:
##   dash_ready/dash_dist, blink_ready/blink_dist, can_parry/parry_ready,
##   parry_window, grounded, allow_iframe
## Returns {action, dir}. Actions: dash, dash_iframe, blink, parry, jump, walk, none.
static func choose_response(threat: Dictionary, caps: Dictionary) -> Dictionary:
	if not bool(threat.get("threatening", false)):
		return {"action": "none", "dir": Vector2.ZERO}
	var exit: Vector2 = threat.get("exit", Vector2.ZERO)
	var need: float = float(threat.get("exit_len", 0.0))
	var tti: float = float(threat.get("tti", 0.0))
	var dir: Vector2 = exit.normalized() if exit.length_squared() > 0.0001 else Vector2.ZERO

	# ⚠ THE VERTICAL EXIT IS A JUMP, AND IT HAS TO BE TESTED FIRST. This body has no
	# "walk up" and no "walk down" — a dash is expressed through the MOVEMENT keys,
	# so a dash whose direction is vertical flattens to (0, 0) at the intent seam and
	# presses dash with no direction at all.
	#
	# That is not a corner case, it is the COMMON case: two fighters stand on the
	# same floor, so a bolt crosses the gap horizontally, and the shortest way out of
	# a horizontal lane is perpendicular — i.e. straight up or straight down, every
	# single time. With the dash rung above the jump rung, every horizontal projectile
	# in the game produced a burnt dash, a latched reflex, and a bot standing still
	# inside the bolt for the length of the latch. That is the "the bot never dodges"
	# report, and this ordering is the fix.
	#
	# Both SIGNS are answered by a jump: a lane is symmetric, so leaving it upward is
	# the same escape as leaving it downward, and upward is the only one a body
	# standing on the floor actually has.
	var vertical: bool = absf(dir.y) >= VERTICAL_EXIT_DOT

	# ⚠ AND A READY GUARD OUTRANKS THE JUMP, WHICH IS WHY THE DEFLECT EXISTED ON PAPER
	# AND ALMOST NEVER ON SCREEN. MEASURED, 18 duels on the Hard tier: 2 deflects, in
	# 2 matches, against 464 frames of guard held — roughly a 6% conversion. The cause
	# was this ladder, not the guard: the vertical-exit jump above returned BEFORE the
	# parry rung below could be asked, and a horizontal bolt between two grounded
	# fighters yields a vertical exit EVERY frame (`tools/bot_duel_probe.gd` reports
	# `exit=(0,±24)` and `jump=true` for the canonical duel geometry). So the parry
	# rung was only ever reachable while AIRBORNE — i.e. almost never.
	#
	# This cannot degenerate into a bot that stands and guards forever, and that is
	# structural rather than hoped-for: `parry_ready` is `guard_ready and in_lead`
	# (`BotBrain.gd:919`), and `in_lead` is a slack-width band around THIS class's own
	# published `guard_lead` (`:901-906`). Outside that band the rung fails and the
	# body jumps exactly as it did before. The jump is still the answer to most bolts;
	# the parry is now the answer to the ones it can actually read.
	#
	# It is ordered above the jump rather than below it because the two are not
	# comparable on escape alone. A jump leaves the lane; a parry negates the hit,
	# banks the counter, and is the best-looking beat in the game. When both are
	# available in the same frame the parry is strictly the better outcome — for the
	# fight and for anyone watching it.
	if vertical and bool(caps.get("can_parry", false)) and bool(caps.get("parry_ready", false)) \
			and tti <= float(caps.get("parry_window", 0.0)):
		return {"action": "parry", "dir": dir}
	if vertical and bool(caps.get("grounded", false)):
		return {"action": "jump", "dir": dir}

	if bool(caps.get("dash_ready", false)) and float(caps.get("dash_dist", 0.0)) >= need \
			and dir != Vector2.ZERO and not vertical:
		return {"action": "dash", "dir": dir}
	# Timing a dash so its i-frames cover impact beats a threat WITHOUT escaping
	# it. It is the strongest read available and looks like cheating when
	# unrestricted, so the caller gates it to the top difficulties.
	#
	# This is also the airborne answer to a vertical exit: the direction cannot be
	# expressed, but the INVULNERABILITY can, and that is the whole point of the rung.
	# (The vertical-exit PARRY rung used to sit here, below the jump. It has moved to
	# the TOP of the ladder — see the block up there for the measurement that moved it.
	# It is not duplicated: a vertical exit is now answered by parry-then-jump, and
	# this position could only ever be reached when both of those had already failed.)
	#
	# ⚠ THE i-FRAME RUNG BELOW FABRICATES `Vector2.RIGHT` on a vertical exit, because a
	# dash cannot express a vertical direction on this body — so in that case it is not
	# a dodge at all, it is invulnerability standing still. That is why the parry is
	# asked first and why it is worth asking: it is exactly as non-escaping, costs a
	# cooldown this body was about to spend anyway, and reads.
	if bool(caps.get("dash_ready", false)) and bool(caps.get("allow_iframe", false)) \
			and tti <= IFRAME_LEAD:
		var iframe_dir: Vector2 = dir if dir != Vector2.ZERO and not vertical else Vector2.RIGHT
		return {"action": "dash_iframe", "dir": iframe_dir}
	# Blink is pressed through the same movement keys as the dash, so it inherits the
	# same inability to express a vertical direction.
	if bool(caps.get("blink_ready", false)) and float(caps.get("blink_dist", 0.0)) >= need \
			and dir != Vector2.ZERO and not vertical:
		return {"action": "blink", "dir": dir}
	# Parry answers melee, contact and charge hits too — not just projectiles —
	# so it is a legitimate reply to a charger lane, not a projectile-only reflex.
	if bool(caps.get("can_parry", false)) and bool(caps.get("parry_ready", false)) \
			and tti <= float(caps.get("parry_window", 0.0)):
		return {"action": "parry", "dir": dir}
	# (The old grounded-jump rung lived here, BELOW the dash. It was unreachable in
	# practice — the dash rung above it accepted the same vertical exits and always
	# won — so it has moved to the top of the ladder rather than being duplicated.)
	if dir == Vector2.ZERO:
		return {"action": "none", "dir": Vector2.ZERO}
	return {"action": "walk", "dir": dir}


# ---- perception timing -----------------------------------------------------

## Models HUMAN reaction, which is the entire difficulty dial. A threat becomes
## visible to the brain only after a per-profile delay measured from FIRST
## SIGHTING; after that the brain tracks it live. Reading a permanently-stale
## world instead would make the bot look drunk rather than human.
##
## The whiff roll is taken ONCE, when a threat is first seen — not per frame, or
## the bot flickers between committed and passive. A bot that never misses a
## dodge is not beatable-feeling, which is why this exists at all.
class Reactions extends RefCounted:
	var _reveal: Dictionary = {}   # instance id -> time the brain may act on it
	var _whiff: Dictionary = {}    # instance id -> true = deliberately fumble this one

	## First sighting starts the clock. `roll` is supplied by the caller (0..1) so
	## the decision stays deterministic under test.
	func observe(id: int, now: float, delay: float, roll: float = 1.0,
			p_miss: float = 0.0) -> void:
		if _reveal.has(id):
			return
		_reveal[id] = now + delay
		_whiff[id] = roll < p_miss

	## Has this threat already been sighted? Callers ask BEFORE rolling, so the
	## random draws behind `observe` are spent once per threat rather than once per
	## frame per threat. Not just thrift: a caller re-rolling every frame would be
	## drawing from a stream whose length depends on the frame rate, which quietly
	## makes a bot's behaviour un-reproducible from a seed.
	func knows(id: int) -> bool:
		return _reveal.has(id)

	## True once the delay has elapsed and this threat was not rolled as a whiff.
	func visible(id: int, now: float) -> bool:
		if not _reveal.has(id) or bool(_whiff.get(id, false)):
			return false
		return now >= float(_reveal[id])

	## Drop bookkeeping for threats that no longer exist, so Godot recycling an
	## instance id cannot hand a brand-new threat an already-elapsed reveal time.
	func forget_missing(live_ids: Array) -> void:
		for id: int in _reveal.keys():
			if not live_ids.has(id):
				_reveal.erase(id)
				_whiff.erase(id)

	func tracked() -> int:
		return _reveal.size()
