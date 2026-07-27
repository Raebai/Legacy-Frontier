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

	if bool(caps.get("dash_ready", false)) and float(caps.get("dash_dist", 0.0)) >= need \
			and dir != Vector2.ZERO:
		return {"action": "dash", "dir": dir}
	# Timing a dash so its i-frames cover impact beats a threat WITHOUT escaping
	# it. It is the strongest read available and looks like cheating when
	# unrestricted, so the caller gates it to the top difficulties.
	if bool(caps.get("dash_ready", false)) and bool(caps.get("allow_iframe", false)) \
			and tti <= IFRAME_LEAD:
		return {"action": "dash_iframe", "dir": dir if dir != Vector2.ZERO else Vector2.RIGHT}
	if bool(caps.get("blink_ready", false)) and float(caps.get("blink_dist", 0.0)) >= need \
			and dir != Vector2.ZERO:
		return {"action": "blink", "dir": dir}
	# Parry answers melee, contact and charge hits too — not just projectiles —
	# so it is a legitimate reply to a charger lane, not a projectile-only reflex.
	if bool(caps.get("can_parry", false)) and bool(caps.get("parry_ready", false)) \
			and tti <= float(caps.get("parry_window", 0.0)):
		return {"action": "parry", "dir": dir}
	if bool(caps.get("grounded", false)) and dir != Vector2.ZERO \
			and dir.dot(Vector2.UP) >= VERTICAL_EXIT_DOT:
		return {"action": "jump", "dir": dir}
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
