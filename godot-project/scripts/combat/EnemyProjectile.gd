class_name EnemyProjectile
extends Node2D
## A hostile bolt fired by the ranged CASTER enemy. Radius-queries the "hero"
## group (mirrors EnergyNova — no collision layers, deterministically testable).
## Primitive-drawn placeholder; shader VFX later.

const SPEED: float = 260.0
const LIFETIME: float = 2.0
const DAMAGE: int = 16
const HIT_RADIUS: float = 16.0
const COLOR: Color = Color(0.7, 0.6, 1.0)

var _dir: Vector2 = Vector2.RIGHT
var _life: float = LIFETIME


func launch(dir: Vector2) -> void:
	_dir = dir.normalized()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	rotation = _dir.angle()


func _physics_process(delta: float) -> void:
	global_position += _dir * SPEED * delta
	_life -= delta
	queue_redraw()
	_check_hit()          # split out so headless tests can drive it
	if _life <= 0.0:
		queue_free()


## Damage the first hero within HIT_RADIUS, then burst + free. Returns true on a
## hit (for tests).
func _check_hit() -> bool:
	for h in get_tree().get_nodes_in_group("hero"):
		if not h is Node2D:
			continue
		if global_position.distance_to((h as Node2D).global_position) <= HIT_RADIUS:
			if h.has_method("take_damage"):
				h.take_damage(DAMAGE)
			CombatVfx.spawn_burst(
				get_parent(), global_position,
				Color(COLOR.r, COLOR.g, COLOR.b, 0.9), Color(0.3, 0.2, 0.6, 0.0),
				16, 0.35, 60.0, 130.0
			)
			Sfx.play("spell_impact")
			queue_free()
			return true
	return false


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, COLOR)
	draw_circle(Vector2.ZERO, 8.0, Color(COLOR.r, COLOR.g, COLOR.b, 0.35))
	# short motion streak behind the bolt
	draw_line(Vector2.ZERO, Vector2(-12.0, 0.0), Color(COLOR.r, COLOR.g, COLOR.b, 0.5), 3.0)
