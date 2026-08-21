class_name EnemyProjectile
extends Node2D
## A hostile bolt fired by the ranged CASTER enemy. Radius-queries the "hero"
## group (mirrors EnergyNova — no collision layers, deterministically testable).
## Primitive-drawn placeholder; shader VFX later.

const SPEED: float = 260.0
## Fly until a wall/target/clash stops it, or this far past any arena — no mid-air stop.
const MAX_TRAVEL: float = 2600.0
const DAMAGE: int = 16
const HIT_RADIUS: float = 16.0
const COLOR: Color = Color(0.7, 0.6, 1.0)

const REFLECT_DAMAGE_MULT: float = 1.5

var _dir: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0
## Flipped true by a perfectly-timed hero parry: the bolt reverses to hunt the
## "enemy" group with boosted damage, recolored to the hero's element.
var _reflected: bool = false
var _damage: int = DAMAGE
var _color: Color = COLOR
var _dead: bool = false
var element_id: int = -1
## WHO FIRED THIS. Same name and shape as BeamSpell.caster_node / ZoneSpell.caster_node
## so there is one spelling of "whose effect is this" across the codebase.
##
## Load-bearing the moment a bolt is registered with SpellReactor, and NOT bookkeeping:
## the reaction layer's ownership predicate reads reaction_owner(), and a null caster
## reports as "unowned", which satisfies neither `require_owner: "same"` nor
## `"different"`. An ownerless effect therefore matches NO clash row at all and is
## silently inert in the entire reaction system — no error, no warning, it just never
## reacts with anything. That exact omission is what made Hollow Purple look broken for
## two sessions. Enemy._spawn_enemy_bolt fills this in at launch.
##
## HONEST SCOPE: a bolt is not a SpellReactor participant yet (no reaction_shape /
## reaction_active / reaction_form), so today this only attributes the shot. The field
## and the accessor exist now so that attribution is REAL rather than a no-op `set()`
## the day someone registers bolts as Form.PROJECTILE.
var caster_node: Node = null
## Co-op: a client-side VISUAL twin of a host bolt (Net._spawn_projectile_twin).
## Flies + stops on walls + bursts for the LOOK, but never damages, clashes with a
## hero's spell, or is parried — the host's real bolt owns all of that via the
## damage router. Set true BEFORE add_child so _ready skips the clearable group.
var visual_only: bool = false


## Tint the bolt to an element (visual — so player + enemy spells read distinct).
func set_element(id: int) -> void:
	element_id = id
	if id >= 0:
		_color = Elements.color(id)


func _ready() -> void:
	if visual_only:
		return  # a cosmetic twin: not clearable, not queried — it just flies + draws
	add_to_group("enemy_projectile")  # so AoE spells can clear it from the air


## Cleared by an AoE detonation (blast/nova) sweeping over it: burst + free once.
func consume() -> void:
	if _dead:
		return
	_dead = true
	_burst_and_free()


## The SpellReactor participant accessor, duck-typed exactly like BeamSpell's. Safe to
## call before the rest of the contract exists — the reactor only ever asks this of
## effects it is already tracking.
func reaction_owner() -> Node:
	return caster_node


func launch(dir: Vector2) -> void:
	_dir = dir.normalized()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	rotation = _dir.angle()


## Perfect-parry reversal: fly along `new_dir` — the DEFENDER'S AIM, not a target —
## switch allegiance to the "enemy" group, boost damage, recolor, and refresh lifetime.
##
## `new_dir` used to be "sender / nearest enemy", and the comment saying so outlived
## the code by a session. Auto-aim is gone (a locked project rule): picking the victim
## for the player made a parry a homing missile you won by getting the TIMING right
## alone. Hero.try_parry now passes `_aim_dir`, so a parry is two stacked skills —
## time the window AND have the shield pointed where you want the bolt to go — and the
## bolt leaves along the same line the shield was just thrown up on, which is the
## picture already on screen. This function itself stays dumb: it takes a direction
## and flies down it. Whoever parries decides the direction.
func reflect(new_dir: Vector2, color: Color) -> void:
	_reflected = true
	_dir = new_dir.normalized()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	rotation = _dir.angle()
	_traveled = 0.0
	_damage = int(round(DAMAGE * REFLECT_DAMAGE_MULT))
	_color = color


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var prev: Vector2 = global_position
	global_position += _dir * SPEED * delta
	_traveled += SPEED * delta
	queue_redraw()
	if _check_wall(prev):
		return  # stopped on a platform/wall (no more pass-through)
	# Co-op twin: stops on walls + bursts for the look above, but skips ALL gameplay
	# (clash/hit/parry) — those would double-resolve on the client. The host's real
	# bolt applies the damage via the router; this copy exists only to be seen.
	if visual_only:
		if _traveled >= MAX_TRAVEL:
			queue_free()
		return
	if not _reflected and _check_clash():
		return  # a stronger player bolt fizzled us
	_check_hit()          # split out so headless tests can drive it
	if _traveled >= MAX_TRAVEL:
		queue_free()


## Stop on a platform/wall (collision layer 1): raycast the segment we just
## travelled; on a hit, snap to the surface, burst + free. No-op with no physics
## world (headless tests that drive _check_hit directly never reach here).
func _check_wall(prev: Vector2) -> bool:
	var world: World2D = get_world_2d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(prev, global_position, 1)
	query.hit_from_inside = true  # point-blank shots may start inside the block
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	global_position = hit["position"]
	_burst_and_free()
	return true


## Projectile-vs-projectile: if a player Spell is within reach, the stronger one
## wins — the weaker fizzles. A tie leaves us flying (we fizzle the spell). Only
## non-reflected (still-hostile) bolts clash with the player's spells.
func _check_clash() -> bool:
	for s: Node in get_tree().get_nodes_in_group("player_spell"):
		if not (s is Node2D) or not is_instance_valid(s):
			continue
		if global_position.distance_to((s as Node2D).global_position) > HIT_RADIUS + 6.0:
			continue
		var spell_dmg: int = 0
		var d: Variant = s.get("damage")
		if d != null:
			spell_dmg = int(d)
		if spell_dmg > _damage:
			_burst_and_free()  # the stronger spell survives; we die
			return true
		if s.has_method("fizzle"):
			s.call("fizzle")  # we're stronger-or-equal: the spell fizzles, we fly on
		CombatVfx.spawn_burst(
			get_parent(), global_position,
			Color(1.0, 1.0, 1.0, 0.9), Color(_color.r, _color.g, _color.b, 0.0),
			10, 0.25, 60.0, 150.0
		)
		return false
	return false


## Damage the first target within HIT_RADIUS, then burst + free. Targets the
## "hero" group normally; a reflected bolt targets "enemy" instead. On a normal
## hit, a perfectly-timed hero parry reverses the bolt rather than taking damage.
## Returns true on a hit (for tests).
func _check_hit() -> bool:
	var group: String = "enemy" if _reflected else "hero"
	for target in get_tree().get_nodes_in_group(group):
		if not target is Node2D:
			continue
		# ⚠ THIS MEASURED TO THE ORIGIN, WHICH IS WHY BOLTS WENT THROUGH HEADS.
		# Maker: *"some spells go through the characters head and dont register as a
		# hit"*. `global_position` on a fighter is the middle of the body, and the
		# drawn figure is `rig.height` (31) tall centred on it — so the top of the head
		# is about 22 px up. Against a flat `HIT_RADIUS` of 16 that is 22 > 16: a bolt
		# aimed at the head passes through and registers nothing, every time. The dead
		# zone is bigger on a scaled body, which is why it was aimable on purpose.
		#
		# The codebase already solved this once and wrote down the lesson: `Enemy`'s
		# HIT SILHOUETTE block says "two different silhouette tests is precisely how
		# 'spells pass through heads' happened". `Hero` and `Enemy` both publish
		# `body_distance` (spine segment + head circle, mirrored from the rig's own
		# pose maths) and `hit_margin`. This was simply not asking them.
		#
		# ⚠ AND IT IS AN *ENEMY* PROJECTILE, so this is the tower — the real game —
		# not the bot fights. Maker, same message: *"all these changes should also of
		# course apply to the real game as well"*.
		#
		# The radius stays as the fallback for any target that publishes no
		# silhouette (a prop, a dummy, a future body), so nothing loses its hitbox.
		# ⚠ A UNION, NOT A SWAP, AND THE TEST SUITE IS WHY. Swapping the radius out
		# for the silhouette made bolts HARDER to land, not easier: `hit_margin` is
		# `height * HIT_MARGIN_FACTOR`, a few px of forgiveness around a spine that is
		# thinner than a flat 16 px disc, so four parry tests that fire a bolt near the
		# origin stopped connecting. Losing hits is the opposite of the report.
		# So the bolt lands if EITHER test says it did: the old disc keeps every hit it
		# already registered, and the silhouette ADDS the head and the feet on top.
		var near: bool = global_position.distance_to(
			(target as Node2D).global_position) <= HIT_RADIUS
		if not near and target.has_method("body_distance") and target.has_method("hit_margin"):
			near = float(target.body_distance(global_position)) 				<= float(target.hit_margin())
		if not near:
			continue
		# Not reflected: the hero may parry us (it performs the reflect on us and
		# returns true), in which case we keep flying — now toward the enemies.
		if not _reflected and target.has_method("try_parry") and target.try_parry(self):
			return false
		if target.has_method("take_damage"):
			target.take_damage(_damage)
		if _reflected and target.has_method("apply_knockback"):
			target.apply_knockback(_dir * 200.0)
		_burst_and_free()
		return true
	return false


## Impact particle burst + sfx + self-free (shared by hero-hit and reflected-hit).
func _burst_and_free() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(_color.r, _color.g, _color.b, 0.9), Color(0.3, 0.2, 0.6, 0.0),
		16, 0.35, 60.0, 130.0
	)
	Sfx.play("spell_impact")
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, _color)
	draw_circle(Vector2.ZERO, 8.0, Color(_color.r, _color.g, _color.b, 0.35))
	# short motion streak behind the bolt
	draw_line(Vector2.ZERO, Vector2(-12.0, 0.0), Color(_color.r, _color.g, _color.b, 0.5), 3.0)


## Where this bolt is GOING, in px/s. The bot's threat solver predicts an
## interception point from a projectile's velocity, and without this it had to
## guess — the duplicated fallback in BotController hardcoded 260.0, which is a
## second copy of this constant waiting to drift. Same name as Spell.travel_velocity()
## so one duck-typed call covers both bolt kinds.
func travel_velocity() -> Vector2:
	return _dir * SPEED
