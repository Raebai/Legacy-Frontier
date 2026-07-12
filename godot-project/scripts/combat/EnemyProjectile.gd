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


func launch(dir: Vector2) -> void:
	_dir = dir.normalized()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	rotation = _dir.angle()


## Perfect-parry reversal: fly toward `new_dir` (sender / nearest enemy), switch
## allegiance to the "enemy" group, boost damage, recolor, and refresh lifetime.
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
	var prev: Vector2 = global_position
	global_position += _dir * SPEED * delta
	_traveled += SPEED * delta
	queue_redraw()
	if _check_wall(prev):
		return  # stopped on a platform/wall (no more pass-through)
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
		if global_position.distance_to((target as Node2D).global_position) > HIT_RADIUS:
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
