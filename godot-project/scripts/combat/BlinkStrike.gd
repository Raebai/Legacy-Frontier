class_name BlinkStrike
extends Node2D
## Shadowblade SIGNATURE — SHADOW STEP (SpellDef.Kind.BLINK_STRIKE). You are simply
## THERE: no travel, no arc, no rush. A beat later the shadow you dragged with you
## collapses into a small burst at your feet.
##
## WHY IT CHANGED (maker, mid-playtest): "the teleportation spell isn't too helpful
## now that dash exists — it should just teleport instantly and then do a small
## explosion where it teleports to, to damage". The old version cut a 300-px-long
## corridor along the path travelled, which made it a dash that happened to cost a
## slot and 48 MP. The hero already HAS a dash (Hero.DASH_SPEED) and a movement
## blink (Hero._blink) with i-frames, both free. A spell whose whole verb is
## "traverse ground" was paying for a button the player already owns.
##
## The new verb is REPOSITION + PUNCTUATION: the movement is instant and free of
## risk, and the payoff is a small radius blast at the destination. Removed with the
## line: the path-crossing damage, the after-image streak band, the crescent slash,
## and the static `targets_on_line` helper (nothing outside this file used it —
## LightningRush carries its own copy).
##
## DODGEABILITY (locked design rule: every ability needs a real tell and a window).
## An instant teleport that instantly damaged would break that rule outright, so the
## rule is satisfied where it can honestly be satisfied: the TELEPORT is instant,
## the EXPLOSION is not. A Telegraph danger ring blooms at the destination for
## BLAST_TELL seconds — the dodge budget — before a single point of damage lands.
## Something standing where you arrived gets that long to walk out. Using the shared
## Telegraph (rather than drawing our own ring) buys two things for free: it is the
## danger grammar the rest of the game already teaches, and it joins the
## `telegraph` group, so BotDodge can perceive and dodge this spell like any other.
##
## DAMAGE STAYS INSIDE THE DRAWING (maker: "the spells shouldn't be able to get out
## the radius"). One number, BLAST_RADIUS, is the Telegraph's drawn ring, the
## expanding blast ring in _draw, AND the radius query in _detonate. There is no
## second, larger "effect" radius anywhere — see the negative case in
## tools/slice_test_blink_blast.gd.
##
## ⚠ ONE HONEST DIVERGENCE, ADDED WITH SpellTargets. The radius query now measures
## to a target's DRAWN SILHOUETTE plus that target's own `hit_margin()`, not to a
## zero-size point at its origin. So against a drawn enemy the effective reach is
## BLAST_RADIUS + ~3.7 px (~7 px on a 1.9x sparring dummy), measured from the
## nearest point of a ~31 px tall body — which along the vertical axis is up to
## half a rig height more than before. That growth IS the fix for the maker's
## "spells pass through heads without registering"; it is not a second radius.
## Everything without a silhouette (crates, bolts, test stubs) resolves at exactly
## BLAST_RADIUS as before, which is why the shipped suite's boundary case still
## holds. BALANCE: this ring now catches noticeably more than it used to at the
## same number. If it feels too big, lower BLAST_RADIUS — do NOT also touch
## Enemy.HIT_MARGIN_FACTOR, or the two forgiveness schemes compound.
##
## COVER BLOCKS THE BLAST. The radius query routes through SpellWorld's
## line-of-sight filter (on by default in SpellTargets), so an enemy standing on
## the far side of a wall inside the ring takes nothing. Destructible cover does
## NOT shield — it breaks, and this blast already chips it.
##
## DEFLECTABLE. Nothing physically travels here, so there is nothing to send back:
## per SpellDeflect's split, the damage line is threaded through
## `SpellDeflect.resolve` and a correctly-timed guard EATS the blast instead.
##
## NO AUTO-AIM: the destination is whatever SpellCaster resolved from the player's
## aim (clamped to `reach`), then vetted for legality by the caster's `blink_to`.
## Nothing here looks at where the enemies are.
##
## CO-OP: this node moves nobody and applies damage through `take_damage` /
## `apply_knockback`, which are themselves authority-routed on the victim (a hit on
## a client-side puppet is forwarded to the host — see Enemy.take_damage). So there
## is deliberately no Net gating here; adding one would double-gate and drop hits.
##
## Like every spectacle, this node PARKS AT THE ARENA ORIGIN and draws in world
## coordinates — `global_position` is (0,0) and is NOT where the effect is. See
## SpellGeometry.gd. The one exception is the Telegraph child, which is a real
## positioned node (it draws in local space), so it is placed AT the destination.

# ---------------------------------------------------------------- feel constants
# ALL OF THESE ARE REASONING, NOT FEEL. This spell is headless-verified and
# UNPLAYTESTED — every number below is a first guess with its rationale attached so
# the maker can move it after one F5 instead of re-deriving it.

## The dodge budget. THE load-bearing number of this redesign: the seconds between
## "the hero is standing there" and "the blast resolves". Sibling reference points:
## RiftDagger.RECALL_TELL is 0.18 (but that spell already spent a whole thrown-dagger
## flight as its tell) and BlastSpell.WINDUP is 0.55 (a giant AoE that SHOULD be
## walkable-out-of). 0.30 sits between: longer than a twitch, short enough that the
## blink still reads as one beat rather than a wind-up. If playtest says enemies
## stroll out of it every time, drop toward 0.20; if it feels undodgeable, raise it.
const BLAST_TELL: float = 0.30

## Blast radius — "small is the operative word". RiftDagger's arrival burst is 70
## and BlastSpell's giant is 92; this sits under both because Shadow Step is a
## one-press spell with no throw to land first. Also the ONLY radius in this file.
const BLAST_RADIUS: float = 64.0

## Radial shove out of the burst. Was 300 directional (along the old dash); pulled
## down slightly because a radial push catches everything around you, not just what
## you ran through. BlastSpell uses 340, RiftDagger's arrival 260.
const BLAST_KNOCKBACK: float = 280.0

## How long the detonation flash is drawn after it resolves. Must exceed
## Telegraph.FADE_TIME (0.15) so the ring's own fade isn't cut off mid-frame.
const FLASH_TIME: float = 0.26

## How long the "you came from over there" wisp lingers at the origin. Kept SHORT
## on purpose: the old streak band lived the whole spell and read as a dash path,
## and a lingering line at the origin would re-teach exactly the read we removed.
const DEPART_WISP_TIME: float = 0.14

## Total node lifetime: the tell, then the flash. Nothing else happens.
const LIFE: float = BLAST_TELL + FLASH_TIME

## Solid world geometry lives on collision layer 1 (same mask Hero's blink safety,
## RockWall._hit_world and Spell._resolve_segment all use).
const SOLID_MASK: int = 1

## How far off a surface a buried destination gets pushed when we have to rescue it
## (see safe_blast_point). Just enough that the blast centre is outside the collider
## rather than kissing it.
const SURFACE_PAD: float = 8.0

## HDR violet-white — > 1.0 so the arrival core blooms through the post grade.
const CORE: Color = Color(1.5, 1.3, 1.9)

## The danger ring keeps the game's DANGER hue rather than the spell's violet. Red
## is what this codebase has taught the player to read as "move" (Telegraph.RING_COLOR,
## used by every enemy tell and by the hero's own giant blast), and a violet ring on
## top of a violet arrival flash would be a tell nobody sees.
const TELL_ACCENT: Color = Color(0.95, 0.16, 0.13, 0.9)

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
## cast time. It is ALSO what decides how hard this blast is to parry: an ult only
## connects with the opening sliver of a guard window. Left at the middle shelf
## when nobody sets it, which is exactly how every un-adopted spectacle behaves.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _color: Color = Color(0.6, 0.35, 0.95, 1.0)
var _damage: int = 50
var _elapsed: float = -1.0     # < 0 means strike() has not run yet
var _detonated: bool = false
var _telegraph: Telegraph = null
## Who cast it. Kept for three things: the reaction layer's owner predicate, the
## line-of-sight exclude list, and _rescue_caster().
var _caster: Node = null


## Arrive at `to` (the caster has ALREADY been moved there by SpellCaster via the
## `blink_to` callback), then arm the destination blast.
##
## `from` is only used for the departure puff — no damage is dealt along the way any
## more. `caster` IS forwarded by SpellCaster's BLINK_STRIKE arm today, so
## _rescue_caster() is live: see its own note for what it does and does not fix.
func strike(
	from: Vector2, to: Vector2, color: Color, damage: int = 50,
	_effect: String = "shadow", caster: Node = null
) -> void:
	_from = from
	_color = color
	_damage = damage
	_caster = caster
	global_position = Vector2.ZERO  # spectacle parks at the origin; we draw in world space
	# The blast may never resolve inside terrain. For the Hero this is already true
	# (Hero.blink_to vetted the spot before we were even spawned) and the check costs
	# one point query; for a caster whose blink_to does NOT vet, it is the difference
	# between an explosion in open air and one buried in a wall.
	_to = safe_blast_point(_space_state(), from, to)
	if _to != to:
		_rescue_caster(caster)
	# Inky puff where we left, bright flash where we arrived. This departure/arrival
	# pair IS the teleport read now that the streak band is gone — the same grammar
	# RiftDagger uses on its recall, so a teleport looks like a teleport regardless
	# of which spell caused it.
	CombatVfx.spawn_burst(get_parent(), _from, Color(0.35, 0.15, 0.5, 0.9), Color(0.1, 0.03, 0.2, 0.0),
		18, 0.4, 50.0, 150.0, 1.2, 3.0)
	CombatVfx.spawn_burst(get_parent(), _to, CORE, Color(color.r, color.g, color.b, 0.0),
		20, 0.35, 70.0, 200.0, 0.7, 2.0, 0.0, 0.0, true)
	# Arrival is a light beat: the WEIGHT is spent on the detonation below, so the
	# two events don't blur into one indistinct thump.
	Juice.shake_camera(4.0)
	Sfx.play("blink", 0.0, 0.08)
	_arm_telegraph()
	_elapsed = 0.0
	# Join the reaction system. Registering during the TELL is correct and matches
	# BeamSpell: reaction_active() keeps this inert until the blast actually
	# detonates, so a danger ring cannot annihilate anything on its own.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.IMPACT, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) -----------------------------------

## World space, built from `_to` — NOT from global_position, which is (0,0)
## because this node draws in world coordinates. The SAME radius the ring is drawn
## at and the damage query uses, so the reaction footprint cannot drift from the
## picture the way a bespoke "effect radius" would.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(_to, BLAST_RADIUS)


## LOAD-BEARING, exactly as in BeamSpell: false for the whole BLAST_TELL, so the
## danger ring is a telegraph and nothing more. True only while the detonation is
## actually on screen (FLASH_TIME ≈ 0.26 s, about eight reactor ticks at 30 Hz —
## comfortably more than the one tick a reaction needs to be seen).
func reaction_active() -> bool:
	return _detonated and _elapsed < LIFE


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.IMPACT


func reaction_owner() -> Node:
	return _caster


## The clash shelf. Set by SpellCaster; middle shelf when nobody said.
func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: go WITHOUT the normal end-of-life beat. There is nothing
## to dismiss — the Telegraph is our own child and dies with us.
func reaction_consume() -> void:
	queue_free()


## How much of a victim's parry window counts against this hit. SpellDeflect's
## policy is that nothing is unparryable but an ult is BRUTAL to time — only the
## opening sliver of the window connects — so the tier the spell already declares
## picks the dial rather than each spell inventing one.
func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


## Bloom the danger ring at the destination and let IT own the countdown.
##
## The telegraph's `_process` is switched off and we advance it by hand from
## advance() instead. That is deliberate: one clock. If the ring counted its own
## frames while _elapsed counted ours, the drawn tell and the damage could drift a
## frame apart — and a tell that lies about when the hit lands is worse than none.
## It also makes the whole timeline drivable from a headless test.
func _arm_telegraph() -> void:
	_telegraph = Telegraph.new()
	add_child(_telegraph)
	# Our parent transform is the identity (we park at the origin), so a plain
	# position IS the world position — but set global_position anyway so this keeps
	# working if a spectacle is ever parented somewhere offset.
	_telegraph.global_position = _to
	_telegraph.accent = TELL_ACCENT
	_telegraph.style = Telegraph.Style.ZONE
	_telegraph.set_process(false)
	_telegraph.fired.connect(_detonate)
	_telegraph.start(BLAST_RADIUS, BLAST_TELL)


## Pure-ish geometry (testable): nodes within `radius` of `center`.
##
## RETAINED, NOT DELETED, and that is a deliberate exception to
## `docs/spell-world-contract.md`'s "delete the local helper outright": the shipped
## suites tools/slice_test_blink_blast.gd and tools/slice4_test_spells.gd assert on
## this exact static, and those files are owned elsewhere. The BODY is gone though
## — it now forwards to the shared selector, so there is one implementation in the
## game rather than seven, which was the point of the consolidation.
##
## Line of sight is OFF here on purpose. This entry point is the PURE-GEOMETRY one:
## it takes a bare node list with no caster and no world context, which is exactly
## how the suites call it. The real damage path (`_detonate`) calls
## `SpellTargets.in_radius` directly WITH line of sight, so cover blocks the blast
## where it matters.
static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
	return SpellTargets.in_radius(center, radius, nodes, [], null, false)


## The point the blast may legally occupy. `space` may be null (headless / no
## physics world) in which case `to` is returned untouched.
##
## This is a POINT test, not a segment test, and that distinction is load-bearing: a
## blink is ALLOWED to phase through a thin wall (Hero._safe_blink_destination
## documents the same rule — "only the resting spot matters"). A segment raycast
## from `from` to `to` would report every legally-crossed wall as a hit and drag the
## blast back off the hero, decoupling the explosion from the body it belongs to.
static func safe_blast_point(
	space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2
) -> Vector2:
	if space == null:
		return to
	if not _is_buried(space, to):
		return to  # the common case, and ALWAYS the case for Hero
	# Buried in solid geometry. Walk back along the blink toward the origin, which is
	# on the map by construction (you cast from somewhere you were standing), and
	# stop just short of the surface we came through.
	var span: Vector2 = to - from
	if span.length() < 1.0:
		return from
	var back := PhysicsRayQueryParameters2D.create(to, from, SOLID_MASK)
	back.hit_from_inside = true       # the ray STARTS inside the solid we're stuck in
	back.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(back)
	if hit.is_empty():
		return from                   # no surface found — fall all the way home
	return (hit["position"] as Vector2) + (from - to).normalized() * SURFACE_PAD


## True when `at` sits inside non-smashable solid geometry.
##
## Destructible cover is on layer 1 alongside real terrain, so a crate would
## otherwise read as "solid" — and per the trap RockWall._is_smashable documents, a
## block that just collapsed has already left the "destructible" group while its
## collider survives until the deferred free. Anything queued for deletion therefore
## counts as gone, not as a wall.
static func _is_buried(space: PhysicsDirectSpaceState2D, at: Vector2) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = at
	q.collision_mask = SOLID_MASK
	q.collide_with_bodies = true
	q.collide_with_areas = false
	for h: Dictionary in space.intersect_point(q, 8):
		# The smash rule lives in ONE place now. It used to be re-rolled here, which
		# is how the "a crate that just collapsed still counts as a wall" trap gets
		# reintroduced one file at a time.
		if SpellWorld.is_smashable(h.get("collider")):
			continue  # smashed, or about to be smashed by this very blast
		return true
	return false


## We corrected a destination that the caster's own `blink_to` let stand, which means
## the body is inside terrain right now. Push it onto the corrected point.
##
## THIS SEAM IS LIVE. SpellCaster's BLINK_STRIKE arm forwards `caster` to strike()
## (`bs.call("strike", caster_pos, dest, col, spell.damage, fx, caster)`), so this
## runs whenever safe_blast_point had to correct a destination. It matters because
## Hero.blink_to vets its landing spot but the SpellPlayground's SpikeFigure.blink_to
## teleports raw — and the playground is where the magic work is being playtested.
## (An earlier revision of this comment claimed the seam was dead; it was already
## wired by then.)
func _rescue_caster(caster: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	if not caster.has_method("blink_to"):
		return  # never move a body through a contract it didn't opt into
	# Re-enter the caster's own vetting with the corrected point, and trust whatever
	# it hands back — the caster, not this spell, owns where its body may rest.
	_to = caster.call("blink_to", _to)


## The blast. Radius query only — same shape as BlastSpell._apply_blast_damage, and
## every distance test below uses BLAST_RADIUS, the number the ring was drawn at.
##
## Two things changed when this adopted SpellTargets, and both are the maker's
## reported bugs rather than balance choices:
##   * the query measures to the target's DRAWN BODY, so a hit at head height
##     registers where it used to sail through a zero-size point at the stomach;
##   * line of sight is on, so the ring no longer leaks damage through a wall.
## The caster is excluded from the LOS rays: a ray that starts inside a body it can
## see reports an instant block, which would cull the whole result set. Layers make
## that impossible today (heroes are layer 2, the ray masks layer 1) and it is free.
func _detonate() -> void:
	_detonated = true
	var tint := Color(_color.r, _color.g, _color.b, 1.0)
	var skip: Array = [_caster]
	for e: Node in SpellTargets.in_radius(_to, BLAST_RADIUS,
			get_tree().get_nodes_in_group(target_group), skip, self):
		# Deflectable (SpellDeflect rule): this blast does not travel, so there is
		# nothing to send back — a correctly-timed guard EATS it and the shove with
		# it. `_to` is the world hit point; the node's own transform is (0,0).
		var dealt: int = SpellDeflect.resolve(e, _damage, (e as Node2D).global_position - _to,
			_to, _deflect_window())
		if dealt <= 0:
			continue  # guarded clean: no damage, no ailment, no shove
		# Through the adapter: Hero declares take_damage(int), Enemy declares
		# take_damage(int, Color). Calling the two-arg form on a hero throws, and a
		# GDScript runtime error ABORTS this function — so the blast dealt NO damage
		# AND skipped the ailment and the knockback below. Harmless while every
		# target was an Enemy; it silently disarmed the spell the moment versus,
		# co-op friendly fire and the duel mode could point it at a hero.
		SpellTargets.hurt(e, dealt, tint)
		if e.has_method("apply_status"):
			e.call("apply_status", element_id)   # shadow -> Weaken, as before
		if e.has_method("apply_knockback"):
			# Radially OUT of the burst, not along a dash direction any more. The
			# degenerate case (something standing exactly on the centre) is shoved UP
			# so it still reacts instead of silently taking a zero-length impulse.
			var away: Vector2 = ((e as Node2D).global_position - _to).normalized()
			e.call("apply_knockback", (away if away != Vector2.ZERO else Vector2.UP) * BLAST_KNOCKBACK)
	for prop: Node in SpellTargets.in_radius(_to, BLAST_RADIUS,
			get_tree().get_nodes_in_group("destructible"), skip, self):
		# Chip the blast-FACING side where the prop is available for it, so cover
		# breaks where it was hit (the same call BlastSpell makes).
		if prop.has_method("damage_at"):
			var pp: Vector2 = (prop as Node2D).global_position
			var toward: Vector2 = (_to - pp).normalized()
			var contact: Vector2 = pp + toward * minf(_to.distance_to(pp), 30.0)
			prop.call("damage_at", _damage, contact, -toward if toward != Vector2.ZERO else Vector2.UP)
		elif prop.has_method("take_damage"):
			prop.call("take_damage", _damage)
	# Arriving inside a volley clears it — the same defensive payoff RiftDagger's
	# recall burst gives, and the reason a blink INTO danger is a real option.
	for proj: Node in SpellTargets.in_radius(_to, BLAST_RADIUS,
			get_tree().get_nodes_in_group("enemy_projectile"), skip, self):
		if proj.has_method("consume"):
			proj.call("consume")
	# The weight lands here, not on the arrival: hitstop + a shake a notch above the
	# arrival's 4.0, so the burst is clearly the payoff beat.
	Juice.hit_stop(0.06)
	Juice.shake_camera(7.0)
	# The shadow family's shared mark — the negative (see ShadowRoot._erupt).
	# Fired on the BURST, not on the arrival, for the same reason the hitstop and
	# shake are: the arrival is a move, the burst is the payoff.
	Juice.frame({
		"style": ImpactFrame.Style.INVERT, "strength": 0.85, "at": _to,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})
	Sfx.play("blast", -7.0, 0.06, 1.25)  # quieter + higher than the giant blast = smaller
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


## Deterministic time-step (mirrors Telegraph.advance) so a headless test can drive
## the tell -> detonation timeline without waiting on real frames.
func advance(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	# One clock: the ring's countdown is OUR countdown (its _process is off).
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.advance(delta)
	if _elapsed >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _elapsed < 0.0:
		return
	# A brief wisp where the body USED to be. Without the old streak band this is the
	# only thing left saying "they came from over there" — kept short so it never
	# reads as a path you could have been hit along.
	var depart: float = clampf(1.0 - _elapsed / DEPART_WISP_TIME, 0.0, 1.0)
	if depart > 0.0:
		draw_arc(_from, 10.0 + 16.0 * (1.0 - depart), 0.0, TAU, 20,
			Color(_color.r, _color.g, _color.b, 0.4 * depart), 2.0, true)
	if not _detonated:
		_draw_gather()
		return
	_draw_burst()


## The tell, drawn on top of the Telegraph's danger ring: shards of shadow sliding
## INWARD to the arrival point. The ring says "here"; the convergence says "now" —
## the closer the shards get, the less time is left.
func _draw_gather() -> void:
	var t: float = clampf(_elapsed / BLAST_TELL, 0.0, 1.0)
	for i: int in 6:
		var ang: float = TAU * float(i) / 6.0 + t * 1.2
		var dir: Vector2 = Vector2.from_angle(ang)
		var outer: float = BLAST_RADIUS * (1.0 - 0.75 * t)
		var inner: float = outer - BLAST_RADIUS * 0.28
		draw_line(_to + dir * outer, _to + dir * maxf(inner, 4.0),
			Color(_color.r, _color.g, _color.b, 0.35 + 0.5 * t), 2.4, true)
	draw_circle(_to, 4.0 + 9.0 * t, Color(CORE.r, CORE.g, CORE.b, 0.5 + 0.4 * t), true, -1.0, true)


## The detonation. The expanding ring is capped at EXACTLY BLAST_RADIUS and the
## boundary arc is held at exactly BLAST_RADIUS for the whole fade — this drawing is
## the promise that the damage query used the same number, and the maker's rule is
## that nothing may land outside what was drawn.
func _draw_burst() -> void:
	var f: float = clampf((_elapsed - BLAST_TELL) / FLASH_TIME, 0.0, 1.0)
	var alpha: float = 1.0 - f
	draw_arc(_to, BLAST_RADIUS, 0.0, TAU, 48,
		Color(_color.r, _color.g, _color.b, 0.45 * alpha), 2.0, true)          # the hard edge
	draw_arc(_to, BLAST_RADIUS * f, 0.0, TAU, 48,
		Color(CORE.r, CORE.g, CORE.b, 0.9 * alpha), lerpf(7.0, 1.5, f), true)  # the wave, capped
	if f < 0.5:
		var flash: float = 1.0 - f / 0.5
		draw_circle(_to, BLAST_RADIUS * 0.55 * flash,
			Color(CORE.r, CORE.g, CORE.b, 0.4 * flash), true, -1.0, true)


## The physics space, or null when there is no world (headless tools / bare tests).
## Kept as one accessor so safe_blast_point can stay static and pure.
func _space_state() -> PhysicsDirectSpaceState2D:
	var world: World2D = get_world_2d()
	return world.direct_space_state if world != null else null
