class_name ShadowRoot
extends Node2D
## SHADOW ROOT — the Warlock's shadow signature, reworked per the maker's ask:
## shadows ERUPT FROM the stick figure itself and race along the ground toward
## the aim, then SNAP upward and ROOT whoever they catch in place. This is a
## different SHAPE of spell from a placed ground zone (which is why it is not
## ZoneSpell): the threat travels from the caster, telegraphs its grasp point,
## and gives a GENUINE dodge window (overhaul rule 2) — step off the mark or
## jump over the tendrils during the surge and it closes on empty air.
##
## The immobilise deliberately REUSES the existing status path instead of
## inventing a parallel CC system: apply_status(EARTH) drives StatusComponent's
## direct-root channel (freeze timer -> is_hard_cc() -> the Enemy suppresses
## attacks + freezes its rig), refreshed each REAPPLY_EVERY while the grip
## holds; apply_status(SHADOW) layers Weaken on top AND — applied last — sets
## the ailment overlay tint violet so the root reads as shadow, not ice/earth.
## The residual 32% freeze-drift is pinned by easing the victim back to its
## catch anchor, so "rooted" means rooted.
##
## Look: it EATS light — near-black cores voiding the background with a violet
## fray at the edges; HDR is reserved for sparse eruption sparks so bloom
## accents the darkness instead of washing it out.
##
## ── WORLD CONTRACT (docs/spell-world-contract.md) ────────────────────────────
## SPAWN.   The grasp point is resolved against the world before anything is drawn:
##          a wall STOPS the surge where it stands, and a pit ENDS it at the lip.
##          Nothing may end up below or inside the environment, and that includes a
##          grasp mark rolled onto thin air.
## IMPACT.  The catch runs a line-of-sight test FROM THE LOCK. See the ruling below.
## DEFLECT. The tendrils do not physically travel (the vein is cosmetic; the lock is
##          precomputed at cast time), so per SpellDeflect's split there is nothing
##          to send back — the damage line is threaded through `SpellDeflect.resolve`
##          and a correctly-timed guard EATS the grasp, root and all.
##
## ⚠ THE LINE-OF-SIGHT RULING — this spell was flagged as a possible ShadowCrawler-
## style "passes under walls" exemption, and it is NOT one. Two reasons, and they
## point the same way:
##   * ShadowCrawler's class docs name going under barriers as its IDENTITY — "the
##     kit's only answer to a barrier". If Shadow Root reached under walls too, the
##     crawler would have nothing of its own and the two shadow spells would
##     collapse into one.
##   * The vein is drawn racing ALONG THE FLOOR from the caster to the mark. A
##     visible ground threat that crosses a wall it is drawn stopping at is exactly
##     the maker's complaint ("a spell that meets a wall should IMPACT there").
## So: the surge is clipped by geometry, and the CATCH is line-of-sight tested. But
## the test runs from the LOCK, not from the caster — the tendrils erupt out of the
## ground under the victim, so what matters is whether anything stands between the
## grasp point and the body, not what the caster can see. In practice that culls
## only a victim separated from the mark by a pillar, which is correct.
##
## ⚠ ONE DRAWN-vs-DAMAGED LIE, FIXED. CATCH_HEIGHT used to be 100.0 while the whiff
## claws were drawn 46 px tall: the grasp reached more than twice as high as any
## picture of it, so a body standing on a ledge 90 px above the mark was rooted by
## tendrils that visibly ended far below its feet. One constant now feeds BOTH the
## draw and the catch. BALANCE, stated plainly: rooting is a meaningfully weaker
## spell than it was — the jump that dodges it is now roughly half as high, and it
## no longer reaches up onto a ledge. That is the honest direction; if it needs to
## grab higher, raise CATCH_HEIGHT and the claws grow with it.

const SURGE_TIME: float = 0.5      # the dodge window: cast -> lock, in seconds
const GRIP_TIME: float = 1.5       # how long a caught victim stays rooted
const RETRACT_TIME: float = 0.35   # tendrils sink back into the ground
const WHIFF_HOLD: float = 0.45     # claws grasp at air before retracting
const SNAP_FLASH: float = 0.14     # dark implosion beat at the lock moment
const REAPPLY_EVERY: float = 0.25  # refresh cadence for the EARTH root channel
const REAPPLY_CUTOFF: float = 0.55 # stop refreshing this early so the shatter
								   # ("breaks free") lands with the release
## HOW HIGH THE TENDRILS REACH — and therefore how high you must be to have jumped
## them. THE SINGLE SOURCE OF TRUTH: `_draw_claw` is called with this exact value,
## so the picture and the hitbox cannot drift apart again (they were 46 vs 100).
## UNTESTED GUESS: 46.0 is the height the claws were already drawn at, chosen over
## raising the drawing to 100 because the contract is "fix in favour of what is
## drawn". Roughly one and a half rig heights — a grounded body is comfortably
## inside it, a real hop is comfortably outside.
const CATCH_HEIGHT: float = 46.0
## ...and how far BELOW the mark still counts. Small and negative: a step down, not
## a floor down, so a body on the platform beneath is never rooted through it.
const CATCH_BELOW: float = -40.0
const MIN_RUN: float = 130.0       # tendrils always travel at least this far
const MAX_RUN: float = 460.0       # and never further than this
const CLAWS: int = 5               # tendrils per grasp

# --- world-contract constants. ALL UNTESTED GUESSES: reasoning, not feel. -----

## The band the surge is tested against when asking "is there a wall in the way".
## A hairline ray along the floor slips under every ledge and through every raised
## lip; the vein is a visibly chunky ground effect, so it is clipped as a path of
## real height. UNTESTED GUESS: 36 px is a bit over one rig height — tall enough
## that a knee-high lip stops the surge, short enough that a low kerb does not.
const SURGE_HEIGHT: float = 36.0
## ...and how far above the floor the LOWEST sample of that band sits. NOT zero,
## and this one is load-bearing: a sample run exactly along the floor surface starts
## on the floor collider's own boundary, where `hit_from_inside` makes the answer
## ambiguous — it can report the ground itself at distance 0 and collapse every
## surge to the caster's feet. 6 px is clear of the seam and still under anything
## worth calling a step. UNTESTED GUESS.
const SURGE_CLEAR: float = 6.0
## How far above the raw sample line the floor probes START. The grasp point used
## to be found by probing from `y - 8`; this is that lift, named, and it is also
## the reason a rising slope in front of the caster is found rather than missed
## (a probe that starts inside the risen ground reports the ground it started in).
const LOCK_LIFT: float = 24.0
## Samples taken while walking the floor from the caster to the grasp point. 12
## across a 460 px maximum run is one probe every ~38 px — fine enough to find the
## lip of any pit worth falling into, cheap enough to run once at cast time.
const LOCK_SAMPLES: int = 12
## How far below the walk line a floor probe reaches before giving up and calling
## it a pit. Was a bare `300.0` inline in the old `_floor_snap`; kept at the same
## value so terrain that already worked still works. UNTESTED GUESS.
const FLOOR_REACH: float = 300.0

## WHO THIS SPELL MAY HURT. Stamped by SpellCaster._stamp() at cast time, so it
## follows the CASTER's faction rather than being fixed at "enemy" forever.
##
## Every spectacle used to scan the literal group "enemy", which is why a
## hero-shaped bot's spells passed harmlessly through another hero: the aim was
## right, the spectacle spawned and drew, and then it queried a group its target
## was not in. Nothing errored — the spell simply never hit anything, which reads
## as a physics bug rather than a targeting one.
##
## Defaults to "enemy", so every existing caster, capture tool and test is
## byte-identical and single player does not change by one branch.
var target_group: String = "enemy"
var element_id: int = Elements.Element.SHADOW

## The clash shelf this spell fights at (SpellTier.Tier), set by SpellCaster at
## cast time; also the dial deciding how hard the grasp is to guard against.
## Middle shelf when nobody sets it, matching every un-adopted spectacle.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## Who cast it, for the reaction layer's owner predicate (a rule can require the
## SAME caster's two effects, or two DIFFERENT casters'). Named `caster_node` to
## match BeamSpell, which is the established idiom for this seam. Optional and
## null-safe: nothing sets it today, and "unowned" satisfies neither predicate,
## which is the correct conservative answer rather than a wrong one.
var caster_node: Node = null

var _origin: Vector2 = Vector2.ZERO   # caster's feet (floor-snapped)
var _lock: Vector2 = Vector2.ZERO     # grasp point (floor-snapped)
var _color: Color = Color(0.6, 0.35, 0.9)
var _catch_r: float = 64.0            # horizontal half-width of the grasp
var _damage: int = 26
var _effect: String = "shadow"
var _elapsed: float = 0.0
var _snapped: bool = false
var _victims: Array[Dictionary] = []  # {node: Node2D, anchor: Vector2}
var _reapply_t: float = 0.0
var _seed: PackedFloat32Array = PackedFloat32Array()


## Entry point, mirroring the other spell scripts' single driver method:
## `origin` = caster position, `aim` = target-relative vector (target - caster).
## `radius` is the grasp half-width, `damage` the one-shot catch damage.
func erupt(
	origin: Vector2, aim: Vector2, color: Color, radius: float,
	damage: int, effect: String = "shadow"
) -> void:
	_color = color
	_catch_r = maxf(radius, 40.0)
	_damage = damage
	_effect = effect
	global_position = Vector2.ZERO
	var dir_sign: float = signf(aim.x)
	if dir_sign == 0.0:
		dir_sign = 1.0
	var run: float = clampf(absf(aim.x), MIN_RUN, MAX_RUN)
	_origin = _floor_snap(origin)
	_lock = _resolve_lock(_origin, _origin + Vector2(dir_sign * run, 0.0))
	for i: int in 24:
		_seed.append(randf())
	# Eruption beat AT the caster — the spell visibly comes FROM the figure.
	CombatVfx.spawn_burst(get_parent(), _origin + Vector2(0.0, -6.0),
		Color(0.16, 0.04, 0.24, 0.9), Color(0.05, 0.0, 0.1, 0.0),
		12, 0.4, 60.0, 160.0, 0.8, 1.8, 0.0, 0.0, false,
		Vector2(dir_sign, -0.4), 40.0)
	# THE ERUPTION MARK. Laid flat at the caster's feet, because this is the one
	# shadow spell that comes out of the FLOOR rather than out of the hand — the
	# ground sigil is the visual promise that the tendrils are about to race along
	# it. Held for the surge so the mark is still lit while the veins are running.
	SpellSigil.open(self, _origin, color, 0.95, false, Vector2.RIGHT, true, 0.14, 0.55)
	Juice.shake_camera(3.0)
	Sfx.play("cast", -4.0, 0.1)
	# Join the reaction system. FIELD rather than BEAM or PROJECTILE: what another
	# spell can actually meet is the lingering grasp at the mark, not the cosmetic
	# vein. reaction_active() keeps it inert for the whole SURGE_TIME telegraph,
	# exactly as BeamSpell stays inert during its charge.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.FIELD, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) -----------------------------------

## World space, built from `_lock` — NOT from global_position, which is (0,0)
## because this node draws in world coordinates. `_catch_r` is the same number the
## grasp is drawn and damaged at, so the reaction footprint cannot drift from
## either.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(_lock, _catch_r)


## LOAD-BEARING, same rule as BeamSpell's charge: false for the whole SURGE_TIME,
## because until the snap this spell is nothing but a telegraph and a cosmetic
## vein. True from the lock moment until the retract has finished fading.
func reaction_active() -> bool:
	var hold: float = GRIP_TIME if not _victims.is_empty() else WHIFF_HOLD
	return _snapped and _elapsed < SURGE_TIME + hold + RETRACT_TIME


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.FIELD


## Null until SpellCaster's ZONE arm sets `caster_node` — one line in a file owned
## elsewhere, reported rather than edited. Until then this reads "unowned", which
## satisfies neither the same-owner nor the different-owner predicate, exactly as
## SpellReactor._owner_relation intends.
func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: go WITHOUT the retract beat. The grip is released by the
## victims' own status timers lapsing, which is correct — the root was eaten, not
## dispelled.
func reaction_consume() -> void:
	queue_free()


## How much of a victim's parry window counts against this hit. SpellDeflect's
## policy is that nothing is unparryable but an ult is brutal to time, so the tier
## the spell already declares picks the dial rather than this file inventing one.
func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


## Drop a point onto the floor below it so the tendrils hug the ground on
## slopes/platforms. Probes from LOCK_LIFT above, so a floor that rose since the
## caller computed the point is still found. Falls back to the input when there is
## no floor (or no physics world at all) — the caller decides what that means.
func _floor_snap(from: Vector2) -> Vector2:
	var g: Dictionary = SpellWorld.floor_below(from + Vector2(0.0, -LOCK_LIFT),
		LOCK_LIFT + FLOOR_REACH, [], self)
	# Note the explicit `hit` check: on a miss `position` is the LIFTED probe start,
	# not the caller's point, so returning it raw would float the effect 24 px.
	return (g["position"] as Vector2) if bool(g["hit"]) else from


## Where the tendrils can ACTUALLY reach, resolved once at cast time. Two world
## rules, applied in order:
##
## 1. A WALL STOPS THE SURGE, at the wall. See the line-of-sight ruling in the
##    class docs for why this spell is not the one that goes under barriers. The
##    clip is a THICK query spanning SURGE_HEIGHT above the floor rather than a
##    hairline along it — a hairline slips under every raised lip the drawn vein
##    visibly slams into.
## 2. A PIT ENDS IT AT THE LIP. `ground_path` walks the floor per sample and stops
##    at the first x with nothing beneath it, so the grasp lands on the last solid
##    ground instead of being marked in mid-air over a chasm.
##
## Degenerate case, deliberately allowed: a wall right in front of the caster
## collapses the run to nothing and the grasp happens at their own feet. That is
## honest — the shadow had nowhere to go — and it still costs the cast.
func _resolve_lock(from: Vector2, desired: Vector2) -> Vector2:
	# Rule 1, sampled at mid-band height so the samples span SURGE_CLEAR ..
	# SURGE_CLEAR + SURGE_HEIGHT above the floor — clear of the floor seam.
	var lift := Vector2(0.0, -(SURGE_CLEAR + SURGE_HEIGHT * 0.5))
	var stopped: Vector2 = SpellWorld.clip(from + lift, desired + lift,
		SURGE_HEIGHT, [], self) - lift
	# Rule 2. Probing starts LOCK_LIFT above the walk line for the same reason
	# _floor_snap does: a probe begun inside risen ground answers with itself.
	var walk := Vector2(0.0, -LOCK_LIFT)
	var path: PackedVector2Array = SpellWorld.ground_path(
		from + walk, stopped + walk, LOCK_SAMPLES, LOCK_LIFT + FLOOR_REACH, [], self)
	if path.is_empty():
		return from  # no floor anywhere along the run — grasp at the caster's feet
	return path[path.size() - 1]


func _process(delta: float) -> void:
	_elapsed += delta
	if not _snapped and _elapsed >= SURGE_TIME:
		_snap()
	if _snapped and not _victims.is_empty():
		_hold_grip(delta)
	var hold: float = GRIP_TIME if not _victims.is_empty() else WHIFF_HOLD
	if _elapsed >= SURGE_TIME + hold + RETRACT_TIME:
		queue_free()
		return
	queue_redraw()


## The lock moment: whoever is still standing on the mark (and near the ground —
## airborne bodies above CATCH_HEIGHT have jumped the tendrils) gets caught.
##
## ⚠ WHY THIS IS STILL A BAND TEST AND NOT `SpellTargets.on_line`. The contract doc
## flags the axis-aligned band spells as "one at a time with a feel check, not
## mechanical swaps", and this is the one where the swap would be wrong. The two
## axes MEAN DIFFERENT THINGS here — x is "did you step off the mark", y is "did you
## jump the tendrils" — and both are advertised dodges. A capsule rounds the band's
## ends by `half_width` (64 px), which would silently hand back most of the vertical
## reach the drawn-vs-damaged fix above just removed. So the rectangle stays.
##
## What IS adopted from SpellTargets is the part that matters: the target's own
## `hit_margin()` widens the band, so a 1.9x sparring dummy is forgiven in
## proportion to how big it is drawn, and that stays the ONLY forgiveness scheme —
## no second pad at this call site.
func _snap() -> void:
	_snapped = true
	var caught_nodes: Array = []
	# hostiles(): the tendrils erupt from the caster's own feet.
	for e: Node in SpellTargets.alive(SpellTargets.hostiles(self, target_group)):
		var n: Node2D = e as Node2D
		if absf(n.global_position.x - _lock.x) > _catch_r + SpellTargets.hit_margin(n):
			continue  # stepped off the mark during the surge — dodged
		var lift: float = _lock.y - n.global_position.y
		if lift > CATCH_HEIGHT or lift < CATCH_BELOW:
			continue  # jumped over the tendrils (or on another floor) — dodged
		caught_nodes.append(n)
	# Cover between the MARK and the body, not between the caster and the body: the
	# tendrils come out of the ground under the victim. See the ruling in the class
	# docs for why this spell is line-of-sight at all.
	#
	# ⚠ THE RAY STARTS SURGE_CLEAR ABOVE THE MARK, NOT ON IT. `_lock` sits exactly on
	# the floor surface, i.e. on the floor collider's own boundary, and SpellWorld
	# casts with hit_from_inside ON — so a ray begun there reports the ground it
	# started on and culls EVERY victim. Caught in the headless suite; without the
	# lift the spell silently never rooted anything on a real floor.
	var from: Vector2 = _lock + Vector2(0.0, -SURGE_CLEAR)
	for e: Node in SpellWorld.filter_reachable(from, caught_nodes, [], self):
		var n: Node2D = e as Node2D
		# Deflectable: nothing travels, so a correctly-timed guard EATS the grasp —
		# no damage, no root, no victim entry. The shove direction is up out of the
		# ground, which is where the tendrils came from.
		var dealt: int = SpellDeflect.resolve(n, _damage, Vector2.UP,
			SpellTargets.aim_point(n), _deflect_window())
		if dealt <= 0:
			continue
		if n.has_method("take_damage"):
			SpellTargets.hurt(n, dealt, Color(_color.r, _color.g, _color.b, 1.0))
		if n.has_method("apply_status"):
			# EARTH first = the direct-root channel; SHADOW last = Weaken + the
			# violet overlay tint (StatusComponent tints from the LAST element).
			n.apply_status(Elements.Element.EARTH)
			n.apply_status(Elements.Element.SHADOW)
		_victims.append({"node": n, "anchor": n.global_position})
	# ...and the SCENERY inside the same band. Tendrils tearing up through the floor
	# should take the crate standing on that patch of floor with them.
	#
	# Reuses the band test rather than a circle: the grasp is a COLUMN (wide in x,
	# bounded in y), and a bounding circle would reach cover a body standing in the
	# same place would not be caught by — the drawn mark would then be a lie in one
	# direction only, which is worse than being a lie in both.
	SpellSurfaces.in_shape(self, _lock, _damage, func(p: Vector2) -> bool:
		if absf(p.x - _lock.x) > _catch_r:
			return false
		var lift2: float = _lock.y - p.y
		return lift2 <= CATCH_HEIGHT and lift2 >= CATCH_BELOW)
	# Dark implosion beat — heavier when something was actually caught.
	var caught: bool = not _victims.is_empty()
	CombatVfx.spawn_burst(get_parent(), _lock + Vector2(0.0, -10.0),
		Color(0.12, 0.02, 0.2, 0.95), Color(0.03, 0.0, 0.07, 0.0),
		18 if caught else 10, 0.45, 80.0, 220.0, 0.9, 2.0, 0.0, 0.0, false,
		Vector2.UP, 55.0)
	# A few HDR violet sparks so the eruption pops under bloom without glowing.
	var em: Color = Elements.emissive(element_id)
	CombatVfx.spawn_burst(get_parent(), _lock + Vector2(0.0, -12.0),
		em, Color(_color.r, _color.g, _color.b, 0.0),
		8, 0.3, 100.0, 240.0, 0.4, 1.0, 0.0, 0.0, true, Vector2.UP, 40.0)
	if caught:
		# THE SHADOW FAMILY'S SHARED MARK: the negative, not the white blow-out.
		# Every shadow spell in the kit (root, crawler, rift, blink, drain) now
		# punctuates with `INVERT`, and that consistency is deliberate — it makes
		# "the screen went wrong for a moment" mean SHADOW, the way the colour
		# field makes a coloured screen mean an element. It is also the only style
		# that leaves the picture fully readable, which matters most here: the
		# whole point of a root is that you can see exactly who got caught.
		Juice.frame({
			"style": ImpactFrame.Style.INVERT, "strength": 0.8, "at": _lock,
			"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
		})
		Juice.shake_camera(7.0)
		Sfx.play("spell_impact", -3.0, 0.1)
	else:
		Sfx.play("cast", -8.0, 0.3)  # a hollow whiff, quieter than the cast


## While the grip holds: refresh the EARTH root (until near the end, so the
## release shatter lands ON the release) and pin the residual freeze-drift
## back to the catch anchor. Gravity keeps owning y — only x is pinned.
func _hold_grip(delta: float) -> void:
	var t_grip: float = _elapsed - SURGE_TIME
	_reapply_t -= delta
	var refresh: bool = _reapply_t <= 0.0 and t_grip < GRIP_TIME - REAPPLY_CUTOFF
	if refresh:
		_reapply_t = REAPPLY_EVERY
	for v: Dictionary in _victims:
		# ⚠ VALIDITY BEFORE `as`. Casting a FREED object throws, and a GDScript
		# runtime error ABORTS the enclosing function — so the `is_instance_valid`
		# that used to sit on the next line could never run. Confirmed live:
		# "SCRIPT ERROR: Trying to cast a freed object."
		# `_victims` is filled once in `_snap()` and NEVER pruned, so a rooted enemy
		# that dies while held leaves a dangling entry here for the rest of the grip —
		# which is why one death produced ~100 frames of error, not one line. Every
		# victim after the dead one lost its root refresh and its anchor pin too.
		var raw: Variant = v["node"]
		if not is_instance_valid(raw):
			continue
		var n: Node2D = raw as Node2D
		if n == null:
			continue
		if refresh and n.has_method("apply_status"):
			n.apply_status(Elements.Element.EARTH)
			n.apply_status(Elements.Element.SHADOW)
		var anchor: Vector2 = v["anchor"] as Vector2
		n.global_position.x = lerpf(n.global_position.x, anchor.x, minf(1.0, 14.0 * delta))


func _draw() -> void:
	var hold: float = GRIP_TIME if not _victims.is_empty() else WHIFF_HOLD
	var fade: float = 1.0
	var t_end: float = SURGE_TIME + hold
	if _elapsed >= t_end:
		fade = clampf(1.0 - (_elapsed - t_end) / RETRACT_TIME, 0.0, 1.0)
	_draw_vein(fade)
	if not _snapped:
		_draw_telegraph()
	else:
		_draw_snap_flash()
		var k: float = fade
		if _victims.is_empty():
			for i: int in CLAWS:
				# CATCH_HEIGHT, not a literal: the whiff claws ARE the
					# picture of how high this spell grabs, so they are drawn at
					# exactly the height it grabs at. These two numbers used to
					# disagree by more than 2x — see the class docs.
					_draw_claw(_lock, i, CATCH_HEIGHT, k)
		else:
			for v: Dictionary in _victims:
				# ⚠ VALIDITY BEFORE `as` — see `_hold_grip`. Same unpruned `_victims`,
				# same freed-cast abort; here it stops the grip VISUALS updating.
				var raw: Variant = v["node"]
				if not is_instance_valid(raw):
					continue
				var n: Node2D = raw as Node2D
				if n == null:
					continue
				_draw_grip(n.global_position, k)


## The dark vein racing along the floor from the caster to the grasp point —
## a near-black core polyline with a violet fray and sprouting spikes, so the
## PATH of the threat is readable the whole way (the telegraph you can outrun).
func _draw_vein(fade: float) -> void:
	var p: float = clampf(pow(_elapsed / SURGE_TIME, 0.8), 0.0, 1.0)  # front-loaded race
	var head: Vector2 = _origin.lerp(_lock, p)
	var pts := PackedVector2Array()
	for k: int in 18:
		var u: float = float(k) / 17.0
		var at: Vector2 = _origin.lerp(head, u)
		at.y += sin(_seed[k % 24] * TAU + _elapsed * 10.0 + u * 9.0) * 2.0
		pts.append(at)
	# The dark core alone vanishes on a dark arena — the violet FRAY defines the
	# void's edge, so it gets a wide dim halo + a bright thin rim.
	draw_polyline(pts, Color(0.4, 0.18, 0.7, 0.22 * fade), 10.0, true)
	draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.95 * fade), 6.0, true)
	draw_polyline(pts, Color(0.62, 0.34, 1.0, 0.6 * fade), 2.0, true)
	# Spikes sprouting along the traversed path, writhing, taller near the head.
	for i: int in 10:
		var f: float = _seed[i] * 0.9 + 0.05
		if f > p:
			continue
		var base: Vector2 = _origin.lerp(_lock, f)
		var near_head: float = 1.0 - clampf(absf(p - f) * 3.0, 0.0, 0.7)
		var sh: float = (5.0 + 9.0 * _seed[i + 10]) * (0.5 + 0.5 * near_head)
		var sway: float = sin(_elapsed * 8.0 + _seed[i] * TAU) * 2.5
		var tip: Vector2 = base + Vector2(sway, -sh)
		draw_line(base + Vector2(-2.0, 0.0), tip, Color(0.05, 0.01, 0.1, 0.85 * fade), 2.2, true)
		draw_line(base + Vector2(2.0, 0.0), tip, Color(0.55, 0.28, 0.9, 0.55 * fade), 1.3, true)
	if not _snapped:
		# The racing head: a dark bulge ringed in violet with HDR sparks — the
		# unmissable "it's coming for you" of the surge.
		draw_circle(head, 10.0, Color(0.4, 0.18, 0.7, 0.25), true, -1.0, true)
		draw_circle(head, 8.0, Color(0.04, 0.0, 0.09, 0.95), true, -1.0, true)
		draw_arc(head, 10.5, 0.0, TAU, 20, Color(0.7, 0.4, 1.05, 0.75), 1.8, true)
		var em: Color = Elements.emissive(element_id)
		for i: int in 5:
			var off := Vector2(sin(_elapsed * 22.0 + float(i) * 2.1) * 7.0,
				-3.0 - 6.0 * _seed[(i + 20) % 24])
			draw_circle(head + off, 1.5, Color(em.r, em.g, em.b, 0.85), true, -1.0, true)


## The grasp-point telegraph during the surge: a gathering dark pool + a violet
## ring CONVERGING onto the mark. Converging (not expanding) = "get off this
## spot NOW" — the classic incoming-lock tell, ending exactly at SURGE_TIME.
func _draw_telegraph() -> void:
	var p: float = clampf(_elapsed / SURGE_TIME, 0.0, 1.0)
	draw_set_transform(_lock, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, _catch_r * (0.3 + 0.7 * p),
		Color(0.02, 0.0, 0.05, 0.45 * p), true, -1.0, true)
	draw_arc(Vector2.ZERO, _catch_r * (0.3 + 0.7 * p), 0.0, TAU, 32,
		Color(0.55, 0.28, 0.9, 0.5 * p), 1.6, true)
	draw_arc(Vector2.ZERO, _catch_r * (2.0 - p), 0.0, TAU, 40,
		Color(0.7, 0.4, 1.0, 0.20 + 0.5 * p), 2.2, true)
	# Cracks racing inward toward the mark — the floor is giving way HERE.
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + _seed[i] * 0.8
		var outer: Vector2 = Vector2.from_angle(a) * _catch_r * (1.6 - 0.55 * p)
		var inner: Vector2 = Vector2.from_angle(a) * _catch_r * (1.1 - 0.55 * p)
		draw_line(outer, inner, Color(0.5, 0.22, 0.8, 0.6 * p), 1.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The lock moment voids the background for a beat: a big dark disc + a violet
## fray ring bursting outward — "the light went out there".
func _draw_snap_flash() -> void:
	var t: float = _elapsed - SURGE_TIME
	if t > SNAP_FLASH:
		return
	var k: float = 1.0 - t / SNAP_FLASH
	draw_set_transform(_lock, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, _catch_r * 1.7, Color(0.01, 0.0, 0.03, 0.45 * k), true, -1.0, true)
	draw_arc(Vector2.ZERO, _catch_r * (1.0 + 1.2 * (1.0 - k)), 0.0, TAU, 40,
		Color(0.75, 0.45, 1.05, 0.7 * k), 2.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One erupted claw grasping at air (the whiff read) — dark, curling, violet-edged.
func _draw_claw(base: Vector2, i: int, height: float, k: float) -> void:
	var spread: float = (float(i) / float(CLAWS - 1) - 0.5) * 2.0  # -1..1 fan
	var wob: float = sin(_elapsed * 7.0 + _seed[i] * TAU)
	var tip: Vector2 = base + Vector2(spread * _catch_r * 0.5 + wob * 3.0,
		-height * (0.75 + 0.4 * _seed[i + 5]))
	var mid: Vector2 = base + Vector2(spread * _catch_r * 0.75, -height * 0.45)
	var pts := PackedVector2Array()
	for s: int in 8:
		var u: float = float(s) / 7.0
		var q: Vector2 = base.lerp(mid, u).lerp(mid.lerp(tip, u), u)  # quadratic bezier
		q.x += sin(_elapsed * 9.0 + u * 5.0 + _seed[i] * TAU) * 2.0 * u
		pts.append(q)
	draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.9 * k), 4.0, true)
	draw_polyline(pts, Color(0.5, 0.25, 0.85, 0.4 * k), 1.3, true)


## Shadow visibly gripping a rooted victim: a light-eating disc behind them, a
## dark pool at their feet, claws wrapping up around the legs, orbiting motes.
func _draw_grip(at: Vector2, k: float) -> void:
	var foot: Vector2 = Vector2(at.x, _lock.y)
	# Eats light: a soft near-black disc voiding the background behind the body,
	# defined against the dark arena by a faint violet fray at its edge.
	draw_circle(at, 44.0, Color(0.02, 0.0, 0.05, 0.34 * k), true, -1.0, true)
	draw_arc(at, 44.0, 0.0, TAU, 32, Color(0.5, 0.25, 0.85, 0.16 * k), 1.6, true)
	draw_set_transform(foot, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 26.0, Color(0.02, 0.0, 0.05, 0.5 * k), true, -1.0, true)
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 24, Color(0.45, 0.2, 0.75, 0.35 * k), 1.4, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Claws wrap from the ground up around the lower body.
	var wrap_h: float = maxf(foot.y - at.y + 16.0, 30.0)
	for i: int in CLAWS:
		_draw_claw(foot, i, wrap_h, k)
	# Orbiting dark motes — the grip is ALIVE, not a decal.
	for i: int in 3:
		var a: float = _elapsed * (2.0 + 0.6 * float(i)) + _seed[i + 15] * TAU
		var orb: Vector2 = at + Vector2(cos(a) * 16.0, sin(a) * 9.0 + 6.0)
		draw_circle(orb, 2.2, Color(0.08, 0.01, 0.14, 0.8 * k), true, -1.0, true)
		draw_circle(orb, 1.0, Color(0.55, 0.3, 0.9, 0.5 * k), true, -1.0, true)
