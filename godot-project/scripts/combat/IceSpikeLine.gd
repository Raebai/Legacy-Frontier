class_name IceSpikeLine
extends Node2D

## GLACIAL SPINE — a crest of ice that ERUPTS FROM THE GROUND at the aimed point
## and races outward along the floor in both directions. The frost family used to
## be a sky bombardment (MeteorSigil's frost skin: spears rained on a marked
## circle); the maker's verdict mid-playtest was that it "reads as more an AoE
## spell — I don't think it would be used much, let's change it so it's not just
## a random zone of frost". So this is not an area you drop. It is a floor-denial
## LINE with one answer: be airborne when it reaches you.
##
## WHERE IT ERUPTS — READ THIS BEFORE "IMPROVING" IT.
## The origin is the point the player AIMED AT, full stop. It is NOT the nearest
## enemy, and nothing here ever looks at the enemy group to decide where to go.
## The intended play is "aim at their feet and the spine comes up under them" —
## but that is the PLAYER's aim doing the work, not the spell. Aim badly and it
## erupts on empty ground and hits nobody, exactly as it should. Snapping the
## origin (or the direction) to a target would be auto-aim, which is a locked
## design rule this project does not break. The only thing resolved for you is
## the ground BENEATH your aim (see _floor_below) — vertical, never lateral.
##
## WHY IT RUNS BOTH WAYS. With the origin sitting on top of the victim, "outward"
## has no caster-relative side to pick: SpellCaster's METEOR arm hands a
## spectacle the aimed ground point and nothing else — no caster node, no facing
## vector — and that dispatch table is owned elsewhere. A symmetric crest needs
## no facing, and it is the better mechanic anyway: you cannot side-step off the
## end of a line that grows in both directions, so the dodge is unambiguously the
## JUMP the maker asked for. A one-sided variant would need one line added to
## SpellCaster's METEOR arm (see the note at the bottom of this file).
##
## DAMAGE == WHAT IS DRAWN. Hard rule from the same playtest: "the spells
## shouldn't be able to get out the radius." There is no radius query anywhere in
## this file. Each spike damages exactly the box it is drawing this frame — its
## own half-width, its own CURRENT height — so a spike that is half-risen only
## catches something half a spike tall, and a body one pixel past the last
## spike's edge takes nothing. See point_in_spike() (pure, headless-tested).
##
## Instantiate .new(), add to the arena, call erupt(). Like every spectacle here
## the node parks at the arena origin and draws in WORLD coordinates, so
## global_position is (0,0) and is NOT where the effect is (SpellGeometry.gd
## documents that trap at length). Every point below is computed world-space.

## Who this line's damage hits. Default "enemy"; a boss caster would set "hero".
var target_group: String = "enemy"
## Elemental ailment (Elements.Element) applied on hit — Chill -> Freeze.
var element_id: int = Elements.Element.ICE
## One impact frame per WAVE, not per spike. See `_strike`.
var _punctuated: bool = false

# ---- THE DODGE BUDGET ------------------------------------------------------
# These five numbers ARE the counterplay, and they are UNTESTED GUESSES — this
# stack is headless-verified, not playtested. Tune them here, together.
#
# The line erupts ON TOP of whoever the caster aimed at, so there is no approach
# to read: unlike a travelling spell, the victim gets no "here it comes" window
# from the delivery itself. The whole warning is the ground tell, and the whole
# escape is being off the floor when the spike arrives.
## The FIRST spike's tell — frost blooms under the mark this long before the
## ground breaks. Sized as human reaction (~0.25 s) PLUS time to actually leave
## the floor, because this is the spike that erupts under someone's feet. A
## spike that erupts and damages on the same frame is undodgeable; that is the
## failure this constant exists to prevent.
const ORIGIN_TELL: float = 0.45
## Every OUTWARD spike's own tell. Much shorter, and fairly so: by then the crest
## is visibly marching at you, so the wave itself is doing most of the warning.
const SPIKE_TELL: float = 0.18
## Seconds between consecutive spikes...
const WAVE_STEP: float = 0.05
## ...over this spacing — together, a ~640 px/s outward crest. Fast enough to
## feel like an eruption, slow enough that you can see it coming three spikes
## out and still get airborne (ShadowCrawler's floor racer runs at 520 px/s for
## comparison, and that one has to cross the whole gap to reach you).
const SPIKE_SPACING: float = 32.0
## The stab-up. Damage tracks the DRAWN height, so a body standing tall is only
## caught once the blade is tall enough to reach its centre — this is a real, if
## brief, extra sliver of window rather than a cosmetic flourish.
const SPIKE_RISE: float = 0.09

# ---- spike shape / life ----------------------------------------------------
## Half-width of one spike, and therefore half-width of its damage box. Kept at
## exactly SPIKE_SPACING * 0.5 so neighbouring bases TOUCH: the crest is a
## continuous wall of ice with no holes to stand in, and the damage bands tile
## the drawn extent exactly — no gap, no overlap, no double-hit from one stance.
const SPIKE_HALF_W: float = 16.0
const SPIKE_HEIGHT: float = 96.0
## The spike over the mark is the focal one — taller, so the eruption point reads
## instantly in a screenshot and in motion.
const ORIGIN_HEIGHT_MULT: float = 1.3
const SPIKE_HOLD: float = 0.20     # standing, lethal
const SPIKE_SHATTER: float = 0.22  # fragments, harmless

# ---- floor probing (collision layer 1 == solid world) ----------------------
const WORLD_MASK: int = 1
## A spike may follow the floor UP this much per step and DOWN this much. One
## window doing two jobs on purpose: anything steeper than this in a 32 px stride
## is a wall face or a ledge, not terrain, and the probe simply finds nothing —
## which is the same "stop this side" answer we want for a pit. No second rule.
const STEP_UP_MAX: float = 26.0
const STEP_DOWN_MAX: float = 70.0
## The aimed point may be anywhere (mid-air, above a platform, slightly inside
## the floor), so the ORIGIN probe is deliberately generous in both directions.
const ORIGIN_PROBE_UP: float = 60.0
const ORIGIN_PROBE_DOWN: float = 420.0
## Heights (above the lower of two neighbouring bases) the wall probe sweeps at.
## Two is enough: one just off the deck to catch a low block, one at chest height
## to catch a raised wall whose foot is buried.
const BLOCK_PROBE_LOW: float = 18.0
const BLOCK_PROBE_HIGH: float = 54.0

# ---- impact feel -----------------------------------------------------------
## Impaled, not blasted: a hard vertical pop with a little outward drift. It is
## the punishment for having been on the floor, so it reads as "launched off it".
const KNOCK_UP: float = -300.0
const KNOCK_OUT: float = 90.0
## Ground-plane squash for every telegraph — markers are floor paint, never HUD
## (the same 0.45 the meteor markers settled on).
const GROUND_SQUASH: Vector2 = Vector2(1.0, 0.45)
const TELL_RADIUS: float = 26.0

var _color: Color = Color(0.62, 0.88, 1.0, 1.0)
var _damage: int = 38
var _effect: String = "frost"
var _origin: Vector2 = Vector2.ZERO
var _elapsed: float = -1.0
var _lifetime: float = 0.0
## Ordered outward from the mark: index 0 is the origin spike, then the pairs.
## Each: {base, hw, h, tilt, seed, step, erupt_at, tell_at, hit: Dictionary}
var _spikes: Array = []


# ---- pure geometry (headless-testable, no physics, no autoloads) -----------

## Is `p` inside the spike standing on `base` with half-width `hw` and CURRENT
## height `h`? An axis-aligned box, deliberately: it is the bounding box of the
## drawn blade and nothing wider, which is the whole "damage can't leave the
## radius" contract made literal. `h` is what the spike is drawing RIGHT NOW, not
## its final height, so a spike still climbing cannot hit what it has not reached.
##
## Asymmetric in y for a reason: a grounded body's centre rides ABOVE the floor
## the spike stands on, so anything between the base and the tip is speared;
## anything above the tip is airborne and safe (that IS the dodge), and anything
## below the base is on a lower floor and untouched.
static func point_in_spike(p: Vector2, base: Vector2, hw: float, h: float) -> bool:
	if h <= 0.0:
		return false
	return absf(p.x - base.x) <= hw and p.y <= base.y and p.y >= base.y - h


## Nodes speared by one spike this frame. Mirrors the targets_in_radius()
## selector every other spectacle exposes, so tests can drive it with no world.
static func targets_in_spike(base: Vector2, hw: float, h: float, nodes: Array) -> Array:
	var out: Array = []
	for n: Node in nodes:
		if n is Node2D and point_in_spike((n as Node2D).global_position, base, hw, h):
			out.append(n)
	return out


## How many spikes fit on ONE side of the mark inside `half_length`. Floored, so
## the crest always ends INSIDE the declared extent rather than poking past it.
static func spikes_per_side(half_length: float) -> int:
	return maxi(0, int(floor((half_length - SPIKE_HALF_W) / SPIKE_SPACING)))


## The line's true drawn (and damaging) half-extent — always <= half_length.
## The pair (this, spikes_per_side) is what makes "declared radius", "drawn
## extent" and "damage extent" the same number instead of three near-numbers.
static func drawn_half_extent(half_length: float) -> float:
	return float(spikes_per_side(half_length)) * SPIKE_SPACING + SPIKE_HALF_W


# ---- entry point -----------------------------------------------------------

## Erupt a spine centred on `origin` — THE AIMED GROUND POINT (see the header:
## never a target's position looked up by this script). `half_length` is the
## declared reach of the crest to either side; the drawn and damaging extent is
## drawn_half_extent(half_length) <= half_length.
func erupt(
	origin: Vector2, color: Color, half_length: float = 210.0,
	damage: int = 38, effect: String = "frost"
) -> void:
	_color = color
	_damage = damage
	_effect = effect
	_origin = _floor_below(origin)
	_elapsed = 0.0
	_build_spikes(half_length)
	# Lifetime covers the LAST spike's full arc, not the first's.
	var last_step: int = spikes_per_side(half_length)
	_lifetime = ORIGIN_TELL + float(last_step) * WAVE_STEP \
		+ SPIKE_RISE + SPIKE_HOLD + SPIKE_SHATTER + 0.05
	# The gather: cold pulls IN toward the mark before anything comes out of it.
	CombatVfx.spawn_burst(
		get_parent(), _origin + Vector2(0.0, -6.0), Color(0.78, 0.94, 1.05, 0.7),
		Color(0.55, 0.8, 1.0, 0.0), 12, ORIGIN_TELL, 20.0, 60.0, 0.8, 2.0, 2.0, 4.0, true
	)
	Sfx.play("charge_up", -5.0, 0.05, 1.25)  # pitched UP — glassy, not boomy
	Juice.shake_camera(2.0)
	queue_redraw()


## Bake every spike's base, silhouette and schedule up front. Done once at cast
## rather than per frame so the crest's shape (and therefore its hitbox) is
## stable — re-rolling heights in _draw would shimmer AND make damage jitter.
func _build_spikes(half_length: float) -> void:
	_spikes.append(_make_spike(_origin, 0, ORIGIN_HEIGHT_MULT))
	var per_side: int = spikes_per_side(half_length)
	# Each side walks outward ONE STEP AT A TIME, anchored on the base it just
	# placed, which is what lets the crest follow a slope instead of assuming the
	# whole line sits at the mark's altitude. A side stops the moment the floor
	# runs out (pit / ledge) or something solid stands in the way (wall).
	for dir: float in [-1.0, 1.0]:
		var prev: Vector2 = _origin
		for step: int in range(1, per_side + 1):
			var x: float = _origin.x + dir * float(step) * SPIKE_SPACING
			var base: Vector2 = _step_floor(prev, x)
			if base == Vector2.INF:
				break
			if _blocked_between(prev, base):
				break
			_spikes.append(_make_spike(base, step, 1.0))
			prev = base


func _make_spike(base: Vector2, step: int, height_mult: float) -> Dictionary:
	var erupt_at: float = ORIGIN_TELL + float(step) * WAVE_STEP
	# The origin spike's tell is the WHOLE lead-in (it starts the instant the
	# spell is cast); outward spikes get the shorter shared lead.
	var lead: float = ORIGIN_TELL if step == 0 else SPIKE_TELL
	return {
		"base": base,
		"hw": SPIKE_HALF_W,
		"h": SPIKE_HEIGHT * height_mult * randf_range(0.82, 1.14),
		"tilt": randf_range(-0.16, 0.16),
		"seed": randf() * TAU,
		"step": step,
		"erupt_at": erupt_at,
		"tell_at": maxf(erupt_at - lead, 0.0),
		"hit": {},  # instance-id set: one spike hits a given body ONCE
	}


# ---- floor resolution ------------------------------------------------------
#
# FOLLOW-UP, DELIBERATELY NOT DONE HERE: a shared SpellWorld.gd is being written
# in parallel to be the ONE home for exactly these two queries (floor_below /
# floor_point for the vertical probe, first_solid or can_reach for the wall
# sweep) — its whole reason for existing is that a dozen spectacles hand-roll
# eight slightly-divergent lines of raycast each, and this file would have been
# the thirteenth. It is written self-contained only because that file did not
# exist yet when this landed and is still in flight; the moment it settles,
# _floor_below / _step_floor / _blocked_between should be threaded through it and
# the constants below kept (they are this spell's terrain FEEL, not plumbing).

## The solid ground under the aimed point. Vertical ONLY — this is the one place
## the spell touches the world to decide where it goes, and it never moves the
## line sideways (that would be aim assist). Falls back to the aimed point itself
## when there is no physics world (headless tools) or no floor at all, so a cast
## into open sky degrades to a flat line rather than vanishing silently.
func _floor_below(at: Vector2) -> Vector2:
	var world: World2D = get_world_2d()
	if world == null:
		return at
	var q := PhysicsRayQueryParameters2D.create(
		at - Vector2(0.0, ORIGIN_PROBE_UP), at + Vector2(0.0, ORIGIN_PROBE_DOWN), WORLD_MASK)
	# Off, per the ShadowCrawler idiom: a raised wall's collider sits ON the
	# floor, so a probe that starts inside one would answer "the inside of this
	# wall" instead of "the ground". With it off the probe skips the body it
	# began in and finds the real deck underneath.
	q.hit_from_inside = false
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return at
	return hit["position"]


## The floor at `x`, probed relative to the base we just placed. Returns
## Vector2.INF when there is nothing inside the step window — no floor (a pit or
## a ledge to dive off) or floor too high to climb (a face). Either way the
## caller stops that side, which is the natural read: ice cracks along a floor,
## it does not march through solid rock or hang over a hole.
func _step_floor(prev: Vector2, x: float) -> Vector2:
	var world: World2D = get_world_2d()
	if world == null:
		return Vector2(x, prev.y)  # headless: assume the deck is flat
	var q := PhysicsRayQueryParameters2D.create(
		Vector2(x, prev.y - STEP_UP_MAX), Vector2(x, prev.y + STEP_DOWN_MAX), WORLD_MASK)
	q.hit_from_inside = false  # same wall-collider reason as _floor_below
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector2.INF
	return hit["position"]


## Solid world geometry standing between two neighbouring bases. Swept at two
## heights above the LOWER base so a rising slope never reads as a wall (the ray
## clears both decks) while an actual barrier does.
##
## Destructible cover is NOT a stopper — ice cracks a crate open. And group
## membership alone is not enough to spot one: a block that collapsed this frame
## leaves the "destructible" group immediately while its collider survives until
## the deferred free, so the sweep would see a group-less solid body and halt the
## crest on the very crate it just shattered. Anything already queued for
## deletion is smashed, gone (the trap RockWall._is_smashable documents).
func _blocked_between(prev: Vector2, base: Vector2) -> bool:
	var world: World2D = get_world_2d()
	if world == null:
		return false
	var deck_y: float = minf(prev.y, base.y)
	for h: float in [BLOCK_PROBE_LOW, BLOCK_PROBE_HIGH]:
		var y: float = deck_y - h
		var q := PhysicsRayQueryParameters2D.create(
			Vector2(prev.x, y), Vector2(base.x, y), WORLD_MASK)
		q.hit_from_inside = true  # the sweep may START inside a wall we are in
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Node = hit.get("collider") as Node
		if n != null and (n.is_in_group("destructible") or n.is_queued_for_deletion()):
			continue
		return true
	return false


# ---- runtime ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	for sp: Dictionary in _spikes:
		var h: float = _live_height(sp)
		if h > 0.0:
			_strike(sp, h)
	if _elapsed >= _lifetime:
		# One frost-crack stain where the spine came up, so the floor remembers.
		ScorchDecal.spawn(get_parent(), _origin, TELL_RADIUS * 1.4, "crack",
			Color(0.62, 0.88, 1.0, 0.4), 5.0)
		queue_free()
		return
	queue_redraw()


## The spike's height for DAMAGE purposes: its current drawn height while it is
## rising or standing, and zero once it starts shattering. Shards are debris —
## if it is not a blade any more it does not cut. _draw_height() is the cosmetic
## twin; they agree on every frame the spike can hurt you, which is the point.
func _live_height(sp: Dictionary) -> float:
	var local: float = _elapsed - float(sp["erupt_at"])
	if local < 0.0 or local >= SPIKE_RISE + SPIKE_HOLD:
		return 0.0
	if local < SPIKE_RISE:
		# Snappy stab: nearly all the height in the first half of the rise.
		return float(sp["h"]) * (1.0 - pow(1.0 - local / SPIKE_RISE, 3.0))
	return float(sp["h"])


## Everything inside THIS spike's box, once per body per spike. No radius query,
## no falloff, no splash: a spike is a blade, and its reach is its silhouette.
func _strike(sp: Dictionary, h: float) -> void:
	var base: Vector2 = sp["base"]
	var hw: float = sp["hw"]
	var hit: Dictionary = sp["hit"]
	for enemy: Node in targets_in_spike(base, hw, h, get_tree().get_nodes_in_group(target_group)):
		var key: int = enemy.get_instance_id()
		if hit.has(key):
			continue
		hit[key] = true
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			# Launched OFF the floor they should have left — the punishment
			# phrased as the dodge they missed.
			var side: float = signf((enemy as Node2D).global_position.x - base.x)
			if side == 0.0:
				side = 1.0
			enemy.apply_knockback(Vector2(side * KNOCK_OUT, KNOCK_UP))
		# The wave CONNECTING is the payoff — the moment the dodge was missed —
		# so the mark lands on the first body it catches and not on the cast.
		# Guarded per-spell, because a wave is a dozen spikes and a mark per spike
		# is exactly the barrage shape the arbiter exists to refuse. Both guards
		# on purpose: this flag is the intent, the arbiter is the safety net.
		if not _punctuated:
			_punctuated = true
			Juice.tier_frame(SpellTier.Tier.HEAVY, base, element_id,
				{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	for prop: Node in targets_in_spike(base, hw, h, get_tree().get_nodes_in_group("destructible")):
		var pkey: int = prop.get_instance_id()
		if hit.has(pkey):
			continue
		hit[pkey] = true
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)


# ---- draw ------------------------------------------------------------------

func _draw() -> void:
	if _elapsed < 0.0:
		return
	# The rime seam first, UNDER the blades: consecutive erupted bases joined by
	# a bright crack in the floor, so fifteen spikes read as ONE spell.
	_draw_seam()
	for sp: Dictionary in _spikes:
		var local: float = _elapsed - float(sp["erupt_at"])
		if local < 0.0:
			if _elapsed >= float(sp["tell_at"]):
				var span: float = maxf(float(sp["erupt_at"]) - float(sp["tell_at"]), 0.001)
				_draw_tell(sp, clampf((_elapsed - float(sp["tell_at"])) / span, 0.0, 1.0))
			continue
		if local < SPIKE_RISE + SPIKE_HOLD:
			_draw_blade(sp, _live_height(sp), 1.0)
		elif local < SPIKE_RISE + SPIKE_HOLD + SPIKE_SHATTER:
			_draw_shards(sp, (local - SPIKE_RISE - SPIKE_HOLD) / SPIKE_SHATTER)


## Per-spike ground tell. Density discipline carried over from the meteor
## markers: AT MOST one thin stroke per point, with the countdown carried by
## FILLED ground shading that grows — fifteen stacked rings read as a HUD
## overlay and bury the spell itself. The ORIGIN spike is the exception and
## earns it: it is the one erupting under somebody, so it also gets the
## six-armed frost crystal that says "here, right here, move".
func _draw_tell(sp: Dictionary, u: float) -> void:
	var base: Vector2 = sp["base"]
	var s: float = float(sp["seed"])
	var big: bool = int(sp["step"]) == 0
	var r: float = TELL_RADIUS * (1.5 if big else 1.0)
	draw_set_transform(base, 0.0, GROUND_SQUASH)
	draw_circle(Vector2.ZERO, r * (0.3 + 0.7 * u),
		Color(0.62, 0.86, 1.0, 0.10 + 0.18 * u), true, -1.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 22,
		Color(0.82, 0.96, 1.1, 0.35 * u * u), 1.2, true)
	if big:
		for k: int in 6:
			var dirv: Vector2 = Vector2.from_angle(s + TAU * float(k) / 6.0)
			draw_line(Vector2.ZERO, dirv * r * 0.95 * u,
				Color(0.88, 0.98, 1.1, 0.55 * u), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One standing blade. Fixed cold palette rather than the cast tint: frost is
## frost, and the ice family's whole point is that you can name the element from
## a frame (the cast colour still drives the ground bloom above).
func _draw_blade(sp: Dictionary, h: float, alpha: float) -> void:
	if h <= 1.0:
		return
	var base: Vector2 = sp["base"]
	var hw: float = sp["hw"]
	var glint: float = 0.75 + 0.25 * sin(_elapsed * 13.0 + float(sp["seed"]))
	draw_set_transform(base, float(sp["tilt"]), Vector2.ONE)
	var body := PackedVector2Array([
		Vector2(0.0, -h),                 # tip
		Vector2(hw * 0.55, -h * 0.34),
		Vector2(hw, -h * 0.08),
		Vector2(hw * 0.8, 3.0),           # a hair below the deck: it SPLIT the floor
		Vector2(-hw * 0.8, 3.0),
		Vector2(-hw, -h * 0.08),
		Vector2(-hw * 0.55, -h * 0.34),
	])
	draw_colored_polygon(body, Color(0.55, 0.8, 1.0, 0.45 * alpha))
	var rim: PackedVector2Array = body.duplicate()
	rim.append(body[0])
	draw_polyline(rim, Color(1.15, 1.55, 1.75, 0.9 * alpha * glint), 1.4, true)
	draw_line(Vector2(0.0, 0.0), Vector2(0.0, -h * 0.9),
		Color(1.4, 1.6, 1.8, 0.5 * alpha * glint), 1.5, true)  # refractive core
	draw_circle(Vector2(0.0, -h), 2.6,
		Color(1.7, 1.85, 1.95, 0.9 * alpha), true, -1.0, true)  # HDR tip — blooms
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The collapse. Harmless by construction — _live_height() has already returned
## zero for this spike, so nothing here can damage anyone.
func _draw_shards(sp: Dictionary, t: float) -> void:
	var base: Vector2 = sp["base"]
	var s: float = float(sp["seed"])
	var a: float = 1.0 - t
	var h: float = sp["h"]
	for k: int in 5:
		var ang: float = -PI * 0.5 + sin(s + float(k) * 1.7) * 1.1
		var reach: float = (40.0 + 26.0 * float(k % 3)) * t
		var p: Vector2 = base + Vector2.from_angle(ang) * reach + Vector2(0.0, -h * 0.5)
		p.y += 210.0 * t * t  # gravity drags the chips back down
		var fs: float = 3.4 - 0.4 * float(k)
		var rot: float = (s + float(k)) * 5.0 * t
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(0.0, -fs).rotated(rot),
			p + Vector2(fs * 0.85, fs * 0.65).rotated(rot),
			p + Vector2(-fs * 0.85, fs * 0.65).rotated(rot),
		]), Color(0.8, 0.93, 1.0, 0.7 * a))


## The crack in the floor left by spikes that have already come up. One dash per
## spike, exactly 2 * hw wide — and because the bases tile at that same pitch,
## the dashes butt up into ONE continuous crack with no bookkeeping about which
## spike neighbours which. Fifteen blades then read as a single spell rather than
## fifteen coincidences. Drawn before the blades so it sits under them.
func _draw_seam() -> void:
	for sp: Dictionary in _spikes:
		if _elapsed < float(sp["erupt_at"]):
			continue
		var base: Vector2 = sp["base"]
		var hw: float = sp["hw"]
		var a: float = clampf(1.0 - (_elapsed - float(sp["erupt_at"])) \
			/ (SPIKE_RISE + SPIKE_HOLD + SPIKE_SHATTER), 0.0, 1.0)
		draw_line(base - Vector2(hw, 1.0), base + Vector2(hw, -1.0),
			Color(0.78, 0.94, 1.05, 0.45 * a), 2.4, true)


## ---------------------------------------------------------------------------
## IF A ONE-SIDED (caster-facing) VARIANT IS EVER WANTED: this file already has
## everything except a direction. The single change needed lives in a file this
## script does not own — SpellCaster.gd's METEOR arm, which currently spawns the
## spectacle with only the aimed point:
##     meteor.set("caster_node", caster)   # <- the one line, mirroring the BEAM arm
## With that, MeteorSigil could forward the caster to erupt() and _build_spikes()
## would simply skip the side pointing back at them. Deliberately NOT done here:
## dispatch is owned elsewhere, and a symmetric crest is the better mechanic
## anyway (see the header).
