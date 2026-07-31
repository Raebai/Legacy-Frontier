class_name ShadowCrawler
extends Node2D
## CREEPING SHADE — a shadow peels off the caster's feet and RACES ALONG THE
## FLOOR until it reaches a body, then rears into a spike and launches them.
##
## The delivery shape is the point of this spell: the head is a real moving
## position doing a per-frame floor probe, so TERRAIN decides the path (it climbs
## slopes, follows steps down, dies in pits) and the victim's own position at the
## moment of arrival decides where it strikes. Nothing else in the kit has an
## emergent strike point — beams resolve instantly along the aim, bombardments
## resolve at a spot the player pre-marked, projectiles ignore the ground.
##
## Not a bigger ShadowRoot. ShadowRoot precomputes its grasp point at cast time
## and races a purely cosmetic vein toward it on a fixed timer; it ROOTS what it
## catches and is dodged POSITIONALLY (be off the mark). This travels for real,
## takes distance-proportional time, LAUNCHES what it catches, and is dodged by
## TIMING (be airborne when it passes under you).
##
## And it goes UNDER walls. RockWall/IceWall are layer-1 bodies whose collider
## sits ON the floor, so the head — which lives at floor level — is INSIDE them
## when it passes; the floor probe runs with hit_from_inside off and therefore
## skips them and finds the ground beneath. That is the spell's identity: the
## kit's only answer to a barrier, and the reason there is no separate horizontal
## wall raycast here (one would stop the shade dead on the first Rock Wall it met).
##
## Look: it EATS light — a near-black core trail with a violet fray, spikes
## sprouting from the path it has already covered, HDR sparks reserved for the
## head so bloom accents the darkness instead of washing it out.
##
## ── WORLD CONTRACT (docs/spell-world-contract.md) ────────────────────────────
## THIS SPELL IS THE DOCUMENTED EXCEPTION, and the exception is deliberately narrow.
## Two of the four contracts apply in full; two are opted out of, with reasons:
##
## ADOPTED — TRAVEL/SMASH. Cover is now chewed off the `smashed` list of a real
##   segment query along the path just travelled, so a destructible is torn through
##   wherever the shade actually crossed it. See `_chew_cover`.
## ADOPTED — DEFLECT. It travels, so it takes the reflect() half of SpellDeflect's
##   split (already present, verified) AND routes its strike through
##   `SpellDeflect.resolve`, because reflect() is a ONE-SHOT: a shade that has
##   already been turned once has no second reversal left, and without this a guard
##   press against the returning wave would do nothing at all.
##
## OPTED OUT — LINE OF SIGHT ON THE CATCH. This is the documented case in the
##   contract: the shade passes UNDER barriers, and that is the kit's only answer to
##   a wall. Culling a victim because a Rock Wall stands between the caster and them
##   would delete the spell's entire reason to exist.
## OPTED OUT — `SpellWorld.floor_below` FOR THE FLOOR PROBE. Not a style choice and
##   NOT laziness: `SpellWorld.first_solid` casts with `hit_from_inside = true`
##   (correct for it — a spell released inside a ledge must impact, not phase). The
##   head lives AT floor level and is therefore INSIDE any layer-1 wall it is
##   passing under, so a hit_from_inside probe would answer with the wall's own
##   underside and pin the shade there. `_floor_y` keeps its bespoke ray with
##   hit_from_inside OFF, which is precisely the mechanism behind "goes under
##   walls". If SpellWorld ever grows a `hit_from_inside` opt-out this can adopt it;
##   until then, do not "consolidate" this probe.
##
## THE PIT DEATH IS NOT A BUG EITHER. Running out of floor kills the spell
## (PIT_DROP) and running out of climb on a vertical face kills it (WALL_CLIMB).
## Losing the spell to terrain is the cost of a spell terrain steers.

const SPEED: float = 520.0          # px/s along the floor
const CATCH_Y: float = 54.0         # a body's centre may be this far ABOVE the head
const CATCH_UNDER: float = -20.0    # ...and this far below (a step down, not a floor down)
const SNAP_TIME: float = 0.12       # rear-up beat between contact and damage
const SHRED_TIME: float = 0.25      # spike dissolve after the strike
const WHIFF_HOLD: float = 0.30      # claws at air when the travel budget runs out
const WALL_CLIMB: float = 110.0     # px it runs UP a vertical face before dying
const PIT_DROP: float = 260.0       # fall this far with no floor and it is gone
const TRAIL_MAX: int = 44           # ≈0.6 s of path kept for the draw
const KNOCK_UP: float = -430.0
const KNOCK_FWD: float = 140.0
const PROBE_UP: float = 40.0        # how far above the head the floor probe starts
const PROBE_DOWN: float = 80.0      # ...and how far below it reaches
const FALL_SPEED: float = 620.0     # descent when the probe finds nothing
## Rise-over-run above which the ground counts as a FACE rather than a slope. A
## rate (not a per-frame pixel budget) so the climb rule is framerate-independent
## and a long gentle hill never accumulates into a false "hit a wall".
const FACE_SLOPE: float = 1.35
const FANG_HEIGHT: float = 74.0
const SPARKS: int = 5

## How far ABOVE the floor the cover-chewing segment is cast. Not zero, and that
## matters: a ray run exactly along the floor surface starts on the floor
## collider's own boundary, where `hit_from_inside` makes the answer ambiguous —
## it can report the ground itself and truncate the smash list on frame one.
## 10 px sits inside the drawn wave (the core line is 7 px wide, the halo 12) and
## comfortably below the top of any crate worth chewing. UNTESTED GUESS.
const CHEW_LIFT: float = 10.0

enum State { TRAVEL, SNAP, SHRED, WHIFF, DEAD }

var element_id: int = Elements.Element.SHADOW

## The clash shelf this spell fights at (SpellTier.Tier), set by SpellCaster at
## cast time; also the dial deciding how hard the strike is to guard against.
## Middle shelf when nobody sets it, matching every un-adopted spectacle.
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## Who cast it, for the reaction layer's owner predicate. Named `caster_node` to
## match BeamSpell, which is the established idiom for this seam. Optional and
## null-safe: nothing sets it today, and "unowned" is the correct conservative
## answer rather than a wrong one.
var caster_node: Node = null

var _color: Color = Color(0.6, 0.35, 0.9)
var _range: float = 620.0
var _catch_x: float = 26.0
var _damage: int = 60
var _effect: String = "shadow"

var _head: Vector2 = Vector2.ZERO
var _prev: Vector2 = Vector2.ZERO
var _dir_sign: float = 1.0
var _travelled: float = 0.0
var _fall: float = 0.0
var _climb: float = 0.0
var _elapsed: float = 0.0
var _state: int = State.DEAD
var _state_t: float = 0.0
var _victim: Node2D = null
var _strike_at: Vector2 = Vector2.ZERO
var _trail: PackedVector2Array = PackedVector2Array()
var _seed: PackedFloat32Array = PackedFloat32Array()
var _chewed: Array[Node] = []       # destructibles already bitten, so a slow crawl
									# over a crate does not shred it every frame

## Read by the parry scans (SpikeFigure / any future rig) to skip a shade that is
## already flying back out.
var _reflected: bool = false
var _target_group: String = "enemy"


## Entry point, mirroring every other spectacle's single driver method. `origin`
## is the caster's feet, `aim` the normalised travel direction (only its x sign
## is used — the shade lives on the floor), `catch_r` the catch half-width in x.
func crawl(
	origin: Vector2, aim: Vector2, color: Color, range_px: float,
	catch_r: float, damage: int, effect: String = "shadow"
) -> void:
	_color = color
	_range = maxf(range_px, 120.0)
	_catch_x = maxf(catch_r, 14.0)
	_damage = damage
	_effect = effect
	global_position = Vector2.ZERO
	_dir_sign = signf(aim.x)
	if _dir_sign == 0.0:
		_dir_sign = 1.0
	_head = _floor_snap(origin)
	_prev = _head
	_trail.append(_head)
	for i: int in 24:
		_seed.append(randf())
	add_to_group("deflectable_spell")
	_state = State.TRAVEL
	# The peel-off beat, thrown ALONG the ground rather than up: the spell visibly
	# leaves the floor at the caster's feet, not their hands.
	CombatVfx.spawn_burst(get_parent(), _head + Vector2(0.0, -4.0),
		Color(0.16, 0.04, 0.24, 0.9), Color(0.05, 0.0, 0.1, 0.0),
		14, 0.4, 70.0, 200.0, 0.8, 1.9, 0.0, 0.0, false,
		Vector2(_dir_sign, -0.15), 26.0)
	Juice.shake_camera(3.0)
	Sfx.play("cast", -6.0, 0.06, 0.82)   # pitched DOWN — it comes from under you
	# Join the reaction system. PROJECTILE: this is the one shadow spell whose
	# position genuinely moves, and reaction_active() keeps it to the TRAVEL state
	# so the rear-up, the shred and the whiff claw are not live reagents.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.PROJECTILE, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) -----------------------------------

## World space, built from `_head` — NOT from global_position, which is (0,0)
## because this node draws in world coordinates. `_catch_x` is the same half-width
## the catch uses, so the reaction footprint and the hitbox are one number.
func reaction_shape() -> Dictionary:
	return SpellGeometry.circle(_head, _catch_x)


## Only while it is actually racing. Once it has rear-up on a victim the outcome is
## decided; a beam sweeping through the shred beat should not un-decide it.
func reaction_active() -> bool:
	return _state == State.TRAVEL


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.PROJECTILE


## Null until SpellCaster's CRAWLER arm sets `caster_node` — one line in a file
## owned elsewhere, reported rather than edited. Until then this reads "unowned",
## which satisfies neither owner predicate, exactly as SpellReactor intends.
func reaction_owner() -> Node:
	return caster_node


func reaction_weight() -> int:
	return spell_tier


## Spent by a reaction: gone, with none of the fang / claw / dissipate beats. The
## shade did not arrive anywhere — it was eaten on the way.
func reaction_consume() -> void:
	queue_free()


## How much of a victim's parry window counts against this hit. SpellDeflect's
## policy is that nothing is unparryable but an ult is brutal to time, so the tier
## the spell already declares picks the dial rather than this file inventing one.
func _deflect_window() -> float:
	return SpellDeflect.WINDOW_ULT if spell_tier == SpellTier.Tier.ULT \
		else SpellDeflect.WINDOW_NORMAL


## Where this spell physically IS, for the parry scans. The node parks at the
## arena origin and draws in world coordinates, so global_position is not it.
func deflect_point() -> Vector2:
	return _head


## Deflect contract (magic-overhaul rule 3): the shade is turned around and races
## back with a fresh travel budget, hunting whoever cast it.
func reflect(new_dir: Vector2, color: Color) -> void:
	if _reflected or _state != State.TRAVEL:
		return
	_reflected = true
	_dir_sign = signf(new_dir.x) if new_dir.x != 0.0 else -_dir_sign
	_target_group = "hero"
	_color = color
	_travelled = 0.0
	_climb = 0.0
	_fall = 0.0
	_chewed.clear()
	_trail.clear()
	_trail.append(_head)
	Sfx.play("ding", 0.0, 0.05)
	queue_redraw()


## AoE sweeps clear pending hazards through this (mirrors EnemyProjectile.consume).
func consume() -> void:
	queue_free()


## Drop a point onto the floor beneath it. hit_from_inside stays OFF so a wall the
## head is currently buried in is ignored and the ground under it is found — the
## mechanism behind "passes under barriers". Returns the input unchanged when
## there is no physics world (headless), so geometry stays sane.
##
## ⚠ DO NOT REPLACE THIS WITH `SpellWorld.floor_below`. It is the documented opt-out
## in the class header: SpellWorld casts with hit_from_inside ON, which would find
## the underside of the very wall this spell exists to pass beneath.
func _floor_snap(from: Vector2) -> Vector2:
	var y: float = _floor_y(from.x, from.y)
	return from if is_inf(y) else Vector2(from.x, y)


## Floor height at `x` probing around `near_y`, or INF when nothing is under it.
func _floor_y(x: float, near_y: float) -> float:
	var world: World2D = get_world_2d()
	if world == null:
		return near_y
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(x, near_y - PROBE_UP), Vector2(x, near_y + PROBE_DOWN), 1)
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return float(hit["position"].y) if not hit.is_empty() else INF


func _process(delta: float) -> void:
	_elapsed += delta
	_state_t += delta
	match _state:
		State.TRAVEL:
			_travel(delta)
		State.SNAP:
			if _state_t >= SNAP_TIME:
				_strike()
		State.SHRED:
			if _state_t >= SHRED_TIME:
				queue_free()
				return
		State.WHIFF:
			if _state_t >= WHIFF_HOLD:
				queue_free()
				return
	queue_redraw()


## One step of the race. Order matters: move, then find the floor under the new
## position, then look for a body there — checking for victims before the snap
## would test them against last frame's ground height on a slope.
func _travel(delta: float) -> void:
	_prev = _head
	var step: float = SPEED * delta
	_head.x += _dir_sign * step
	var ground: float = _floor_y(_head.x, _head.y)
	if is_inf(ground):
		# Ran off a ledge. It keeps going and keeps looking — a drop it can still
		# land inside is a step down; anything deeper is a pit and kills the spell.
		_head.y += FALL_SPEED * delta
		_fall += FALL_SPEED * delta
		if _fall >= PIT_DROP:
			_dissipate()
			return
	else:
		var rise: float = _head.y - ground     # >0 = the ground came UP to meet us
		if rise > step * FACE_SLOPE:
			# Too steep to be a slope: the shade RUNS UP the face, and gives up if
			# the face outlasts its climb budget. Without this it would ride an
			# arbitrarily tall wall to the ceiling.
			_climb += rise
			if _climb >= WALL_CLIMB:
				_dissipate()
				return
		else:
			_climb = 0.0
		_head.y = ground
		_fall = 0.0
	_trail.append(_head)
	if _trail.size() > TRAIL_MAX:
		_trail.remove_at(0)
	_chew_cover()
	var caught: Node2D = _catch()
	if caught != null:
		_begin_snap(caught)
		return
	_travelled += step
	if _travelled >= _range:
		_whiff()


## First body standing in the head's column. STOPS on it — a piercing floor wave
## would just be a beam that takes longer, which is the sameness this spell exists
## to break. Airborne bodies above CATCH_Y are simply passed under.
##
## NO LINE-OF-SIGHT FILTER HERE, and that is the documented exemption rather than an
## oversight — see the class header. The only thing adopted from SpellTargets is the
## target's OWN forgiveness ring, which widens the column in proportion to how large
## the body is drawn (≈7 px on a 1.9x sparring dummy) and is the ONLY margin scheme
## allowed on top of `_catch_x`. `alive()` also drops anything that died earlier in
## this same frame, which used to be able to eat a whole snap beat.
func _catch() -> Node2D:
	# hostiles(): the crawler erupts from the caster's own feet.
	for e: Node in SpellTargets.alive(SpellTargets.hostiles(self, _target_group)):
		var n: Node2D = e as Node2D
		if caught_by(_head, n.global_position, _catch_x + SpellTargets.hit_margin(n)):
			return n
	return null


## A floor wave should chew cover on its way past, so a crate is not a safe place
## to stand. Damage-once-per-crate; the shade does not stop for props.
##
## AUDIT FINDING, FIXED HERE. The old test compared the head to each prop's
## `global_position` inside two hand-tuned pads (`_catch_x + 10` across,
## `CATCH_Y + 30` / `CATCH_UNDER - 10` vertically). That is a third and fourth
## forgiveness scheme layered on `_catch_x`, and — worse — it only ever sees cover
## whose ORIGIN happens to sit near the head, so a wide destructible span the shade
## crossed the middle of was never touched. It is now the segment JUST TRAVELLED,
## and whatever the world says was torn through is what gets damaged.
##
## ⚠ `hit` IS DELIBERATELY IGNORED. This spell goes UNDER walls, so the query is
## used ONLY for its `smashed` list — never for its stop point. That single line IS
## the exemption. What SpellWorld buys in exchange is the smash rule itself: a crate
## that collapsed THIS FRAME has already left the "destructible" group while its
## collider survives until the deferred free, and a group-only test (which is what
## the old loop was) misses it.
func _chew_cover() -> void:
	var lift := Vector2(0.0, -CHEW_LIFT)
	var bitten: Dictionary = SpellWorld.first_solid(_prev + lift, _head + lift, [], self)
	for prop: Node in (bitten["smashed"] as Array[Node]):
		if prop in _chewed:
			continue
		_chewed.append(prop)
		if prop.has_method("damage_at"):
			prop.call("damage_at", _damage, _head, Vector2(_dir_sign, -0.2))
		elif prop.has_method("take_damage"):
			prop.call("take_damage", _damage)


## Contact. The head stops at the victim's column and rears up — no damage yet.
## This beat is the on-target telegraph rule 2 demands: the approach is visible
## from across the arena, and a late jump still escapes the fang.
func _begin_snap(n: Node2D) -> void:
	_state = State.SNAP
	_state_t = 0.0
	_victim = n
	_strike_at = Vector2(n.global_position.x, _head.y)
	_head.x = _strike_at.x
	_trail.append(_head)
	Sfx.play("cast", -9.0, 0.05, 1.35)   # the rear-up hiss, high and short


func _strike() -> void:
	_state = State.SHRED
	_state_t = 0.0
	var tint := Color(_color.r, _color.g, _color.b, 1.0)
	if _victim != null and is_instance_valid(_victim):
		# Deflect contract, second half. reflect() (above) is the FIRST half and is a
		# one-shot: a shade already turned once cannot be turned again, so without
		# this a guard press against the returning wave would be worth nothing. A
		# clean guard eats the strike whole — no damage, no ailment, no launch. `at`
		# is the victim's head, not this node's transform, which is (0,0).
		var dealt: int = SpellDeflect.resolve(_victim, _damage,
			Vector2(_dir_sign, 0.0), SpellTargets.aim_point(_victim), _deflect_window())
		if dealt > 0:
			# Through the adapter: a HERO victim declares take_damage(int) while an
			# Enemy declares take_damage(int, Color), and calling the two-arg form
			# on a hero is a runtime error that ABORTS this function — so the
			# ailment and the launch below would be skipped too. Unreachable until
			# the faction seam let a spell target a hero; found by the bot sim.
			SpellTargets.hurt(_victim, dealt, tint)
			if _victim.has_method("apply_status"):
				# SHADOW only. The launch IS the payload here — layering a root on
				# top would make this ShadowRoot with extra steps.
				_victim.call("apply_status", element_id)
			if _victim.has_method("apply_knockback"):
				_victim.call("apply_knockback", Vector2(_dir_sign * KNOCK_FWD, KNOCK_UP))
	# Dark implosion first, then sparse HDR violet on top: the burst should read as
	# the light going out, with bloom only on the flecks.
	CombatVfx.spawn_burst(get_parent(), _strike_at + Vector2(0.0, -14.0),
		Color(0.12, 0.02, 0.2, 0.95), Color(0.03, 0.0, 0.07, 0.0),
		18, 0.45, 90.0, 240.0, 0.9, 2.0, 0.0, 0.0, false, Vector2.UP, 42.0)
	var em: Color = Elements.emissive(element_id)
	CombatVfx.spawn_burst(get_parent(), _strike_at + Vector2(0.0, -20.0),
		em, Color(_color.r, _color.g, _color.b, 0.0),
		8, 0.32, 120.0, 280.0, 0.4, 1.0, 0.0, 0.0, true, Vector2.UP, 30.0)
	# The shadow family's shared mark — the negative (see ShadowRoot._erupt for
	# why all five shadow spells punctuate the same way). A little stronger than
	# the root's because this one is a STRIKE, not a hold.
	Juice.frame({
		"style": ImpactFrame.Style.INVERT, "strength": 1.0, "at": _strike_at,
		"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0,
	})
	Juice.hit_stop(0.07)
	Juice.shake_camera(9.0)
	Sfx.play("spell_impact", -2.0, 0.06, 0.86)


## Out of travel budget: the head rears into a grasping claw at empty floor.
func _whiff() -> void:
	_state = State.WHIFF
	_state_t = 0.0
	_strike_at = _head
	Sfx.play("cast", -12.0, 0.2, 1.1)   # hollow, quieter than the cast


## Fell into a pit, or ran out of climb on a wall face: no claw, no beat, it is
## just gone. Losing the spell to terrain is the cost of a spell terrain steers.
func _dissipate() -> void:
	_state = State.DEAD
	CombatVfx.spawn_burst(get_parent(), _head,
		Color(0.1, 0.02, 0.16, 0.7), Color(0.03, 0.0, 0.07, 0.0),
		8, 0.35, 30.0, 90.0, 0.7, 1.6)
	queue_free()


func _draw() -> void:
	if _trail.size() < 2:
		return
	var fade: float = 1.0
	if _state == State.SHRED:
		fade = clampf(1.0 - _state_t / SHRED_TIME, 0.0, 1.0)
	elif _state == State.WHIFF:
		fade = clampf(1.0 - _state_t / WHIFF_HOLD, 0.0, 1.0)
	_draw_wave(fade)
	if _state == State.TRAVEL:
		_draw_head()
	elif _state == State.SNAP or _state == State.SHRED:
		_draw_fang(fade)
	elif _state == State.WHIFF:
		_draw_claw(fade)


## The wave itself. Drawn as per-segment lines rather than one polyline because
## the whole point is the TAIL FADING OUT behind the head — a single-colour
## polyline reads as a painted stripe left on the floor, not a thing travelling
## along it. Three passes: a wide violet halo (the only thing that defines the
## void's edge on a dark arena), a light-eating core, a bright rim.
func _draw_wave(fade: float) -> void:
	var n: int = _trail.size()
	for i: int in n - 1:
		var a: Vector2 = _trail[i]
		var b: Vector2 = _trail[i + 1]
		var age: float = float(i + 1) / float(n)      # 1.0 at the head
		var k: float = age * age * fade               # squared: the tail dies fast
		draw_line(a, b, Color(0.4, 0.18, 0.7, 0.22 * k), 12.0, true)
		draw_line(a, b, Color(0.03, 0.0, 0.07, 0.95 * k), 7.0, true)
		draw_line(a, b, Color(0.62, 0.34, 1.0, 0.6 * k), 2.0, true)
	# Spikes sprouting off the path already covered, taller near the head and
	# swaying — the trail is ALIVE, not a decal.
	for i: int in range(0, n - 1, 3):
		var base: Vector2 = _trail[i]
		var s: float = _seed[i % 24]
		var near_head: float = float(i) / float(maxi(n - 1, 1))
		var h: float = (5.0 + 10.0 * s) * (0.45 + 0.75 * near_head) * fade
		var sway: float = sin(_elapsed * 8.0 + s * TAU) * 2.5
		var tip: Vector2 = base + Vector2(sway, -h)
		draw_line(base + Vector2(-2.0, 0.0), tip, Color(0.05, 0.01, 0.1, 0.85 * fade), 2.2, true)
		draw_line(base + Vector2(2.0, 0.0), tip, Color(0.55, 0.28, 0.9, 0.55 * fade), 1.3, true)


## The racing head: a dark bulge ringed in violet with HDR sparks, plus a low
## bow-wave ellipse ahead of it so the direction of travel is readable at a glance.
func _draw_head() -> void:
	draw_set_transform(_head, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2(_dir_sign * 16.0, 0.0), 20.0, Color(0.35, 0.15, 0.62, 0.18), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(_head, 11.0, Color(0.4, 0.18, 0.7, 0.25), true, -1.0, true)
	draw_circle(_head, 8.5, Color(0.04, 0.0, 0.09, 0.95), true, -1.0, true)
	draw_arc(_head, 11.5, 0.0, TAU, 20, Color(0.7, 0.4, 1.05, 0.75), 1.8, true)
	var em: Color = Elements.emissive(element_id)
	for i: int in SPARKS:
		var off := Vector2(
			sin(_elapsed * 22.0 + float(i) * 2.1) * 8.0 + _dir_sign * 4.0,
			-3.0 - 7.0 * _seed[(i + 18) % 24])
		draw_circle(_head + off, 1.5, Color(em.r, em.g, em.b, 0.85), true, -1.0, true)


## The rear-up: one tapered fang growing out of the floor over SNAP_TIME, then
## shredding. Deliberately narrow — a wide one would read as RockPillar's column.
func _draw_fang(fade: float) -> void:
	var grow: float = clampf(_state_t / SNAP_TIME, 0.0, 1.0) if _state == State.SNAP else 1.0
	var h: float = FANG_HEIGHT * grow * (0.55 + 0.45 * fade)
	var lean: float = _dir_sign * 10.0 * grow
	var w: float = 9.0 * (0.6 + 0.4 * fade)
	var tip: Vector2 = _strike_at + Vector2(lean, -h)
	var body := PackedVector2Array([
		_strike_at + Vector2(-w, 2.0),
		_strike_at + Vector2(w, 2.0),
		tip + Vector2(_dir_sign * 2.0, 0.0),
	])
	draw_colored_polygon(body, Color(0.03, 0.0, 0.07, 0.95 * fade))
	draw_line(_strike_at + Vector2(-w, 0.0), tip, Color(0.55, 0.28, 0.9, 0.5 * fade), 1.6, true)
	draw_line(_strike_at + Vector2(w, 0.0), tip, Color(0.62, 0.34, 1.0, 0.7 * fade), 1.4, true)
	var em: Color = Elements.emissive(element_id)
	draw_circle(tip, 3.0 * fade, Color(em.r, em.g, em.b, 0.9 * fade), true, -1.0, true)
	# A dark pool spreading at the base so the fang looks torn OUT of the floor.
	draw_set_transform(_strike_at, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 26.0 * grow, Color(0.02, 0.0, 0.05, 0.45 * fade), true, -1.0, true)
	draw_arc(Vector2.ZERO, 28.0 * grow, 0.0, TAU, 24, Color(0.5, 0.25, 0.85, 0.3 * fade), 1.4, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The whiff read: a small fan of curling claws grasping at empty floor.
func _draw_claw(fade: float) -> void:
	for i: int in 4:
		var spread: float = (float(i) / 3.0 - 0.5) * 2.0
		var s: float = _seed[(i + 6) % 24]
		var tip: Vector2 = _strike_at + Vector2(
			spread * 18.0 + sin(_elapsed * 7.0 + s * TAU) * 3.0,
			-34.0 * (0.7 + 0.5 * s) * fade)
		var mid: Vector2 = _strike_at + Vector2(spread * 24.0, -16.0 * fade)
		var pts := PackedVector2Array()
		for k: int in 7:
			var u: float = float(k) / 6.0
			pts.append(_strike_at.lerp(mid, u).lerp(mid.lerp(tip, u), u))
		draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.9 * fade), 3.4, true)
		draw_polyline(pts, Color(0.5, 0.25, 0.85, 0.4 * fade), 1.2, true)


## Pure geometry (testable): is a body at `at` inside the head's catch window?
## x is a half-width column; y is asymmetric — generous upward (a body's centre
## rides above the floor) and tight downward (so a target one floor DOWN is not
## caught through the ceiling).
static func caught_by(head: Vector2, at: Vector2, catch_x: float) -> bool:
	if absf(at.x - head.x) > catch_x:
		return false
	var lift: float = head.y - at.y
	return lift <= CATCH_Y and lift >= CATCH_UNDER
