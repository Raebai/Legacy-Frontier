class_name DrainTether
extends Node2D
## Warlock — LIFE-DRAIN TETHER (SpellDef.Kind.TETHER). A writhing tendril snaps to
## the nearest enemy in the aim direction and DRAINS it over a short channel: the
## enemy bleeds shadow damage each tick while the caster is HEALED. Organic wavy
## tether that follows the target — unmistakably not a clean beam. Draws in world
## coordinates; locks the target at cast.

const DURATION: float = 1.1
const TICK: float = 0.2
const RANGE: float = 440.0
const HEAL_PER_TICK: int = 5

var element_id: int = Elements.Element.SHADOW
var _origin: Vector2 = Vector2.ZERO
var _target: Node2D = null
var _color: Color = Color(0.55, 0.2, 0.6, 1.0)
var _tick_dmg: int = 10
var _elapsed: float = -1.0
var _tick_t: float = 0.0


func tether(origin: Vector2, aim: Vector2, color: Color, damage: int = 10, _effect: String = "shadow") -> void:
	_origin = origin
	_color = color
	_tick_dmg = damage
	var d: Vector2 = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	var best: Node2D = null
	var bd: float = RANGE
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not e is Node2D or not is_instance_valid(e):
			continue
		var rel: Vector2 = (e as Node2D).global_position - origin
		if rel.dot(d) < 0.0:
			continue  # only enemies in the aim direction
		var dist: float = rel.length()
		if dist < bd:
			bd = dist
			best = e as Node2D
	_target = best
	global_position = Vector2.ZERO
	_elapsed = 0.0
	Sfx.play("cast", -2.0, 0.1)
	_drain()  # bite the frame it lands
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _elapsed < DURATION and _target != null and is_instance_valid(_target):
		_tick_t -= delta
		if _tick_t <= 0.0:
			_tick_t = TICK
			_drain()
	if _elapsed >= DURATION or _target == null or not is_instance_valid(_target):
		queue_free()
		return
	queue_redraw()


func _drain() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _target.has_method("take_damage"):
		_target.take_damage(_tick_dmg, Color(_color.r, _color.g, _color.b, 1.0))
	if _target.has_method("apply_status"):
		_target.apply_status(element_id)
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p.has_method("heal"):
			p.call("heal", HEAL_PER_TICK)


func _draw() -> void:
	if _elapsed < 0.0 or _target == null or not is_instance_valid(_target):
		return
	var a: Vector2 = _origin
	var b: Vector2 = _target.global_position
	var perp: Vector2 = (b - a).orthogonal().normalized()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 11:
		var t: float = float(i) / 10.0
		var base: Vector2 = a.lerp(b, t)
		var wob: float = sin(t * 10.0 + _elapsed * 18.0) * 8.0 * sin(t * PI)
		pts.append(base + perp * wob)
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.7), 3.0, true)
	draw_polyline(pts, Color(0.9, 0.6, 1.0, 0.5), 1.2, true)
	# A mote flowing FROM the target back to the caster (the life being drained).
	var flow: float = fposmod(_elapsed * 2.2, 1.0)
	draw_circle(b.lerp(a, flow), 3.0, Color(0.85, 0.45, 1.0, 0.85), true, -1.0, true)
	draw_circle(b, 8.0, Color(_color.r, _color.g, _color.b, 0.4), true, -1.0, true)
