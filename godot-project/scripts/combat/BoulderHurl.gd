class_name BoulderHurl
extends Node2D
## Earthbending BOULDER HURL. The caster rips a boulder up out of the ground
## (rise + rubble), it hangs a beat, then HURLS along the aim as a heavy tumbling
## rock. On impact: radius damage + HEAVY knockback, shatters into physics debris
## + dust, gouges the ground (crack + hole). Grounded earth move — no float.
## Instantiate .new(), add to the arena, call hurl(). Node sits at arena origin;
## everything is drawn in world coordinates (mirrors DivineRay/MeteorSigil).

const RISE_TIME: float = 0.30      # rips up out of the ground
const HANG_TIME: float = 0.12      # hangs a beat at apex (anticipation)
const FLIGHT_SPEED: float = 900.0
const MAX_FLIGHT: float = 900.0    # px cap before auto-detonate
const RISE_HEIGHT: float = 46.0
const BOULDER_R: float = 26.0
const HIT_PAD: float = 14.0        # extra reach on the flight enemy-check
const IMPACT_RADIUS: float = 84.0
const DEFAULT_DAMAGE: int = 52
const KNOCKBACK: float = 460.0     # HEAVY (above Nova's 420)
const CLEANUP_DELAY: float = 0.8
const DEBRIS_COUNT: int = 16
const SHOCKWAVE_TIME: float = 0.28

const BODY_COLOR: Color = Color(0.34, 0.24, 0.15)
const LIT_COLOR: Color = Color(0.62, 0.46, 0.26)
const RIM_COLOR: Color = Color(1.15, 0.92, 0.55)  # HDR highlight (blooms)
const DUST_TINT: Color = Color(0.55, 0.42, 0.28, 0.5)

var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(0.78, 0.55, 0.28)
var _radius: float = IMPACT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var element_id: int = -1

var _elapsed: float = -1.0
var _ground_y: float = 0.0
var _pos: Vector2 = Vector2.ZERO
var _prev_pos: Vector2 = Vector2.ZERO
var _traveled: float = 0.0
var _spin: float = 0.0
var _flying: bool = false
var _done: bool = false
var _shockwave_elapsed: float = -1.0
var _shape: PackedVector2Array = PackedVector2Array()


func hurl(
	from: Vector2, aim: Vector2, color: Color = Color(0.78, 0.55, 0.28),
	radius: float = IMPACT_RADIUS, damage: int = DEFAULT_DAMAGE, _effect: String = "earth"
) -> void:
	_origin = from
	_dir = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	_color = color
	_radius = radius
	_damage = damage
	_elapsed = 0.0
	# Find the ground the boulder rips out of; if over a pit, rip from the caster.
	var hit: Dictionary = _floor_below(from, 260.0)
	_ground_y = float(hit["position"].y) if not hit.is_empty() else from.y + 30.0
	_pos = Vector2(from.x + _dir.x * 26.0, _ground_y)
	_prev_pos = _pos
	_shape = _make_boulder(BOULDER_R)
	# Ground cracks open as the rock tears out.
	DebrisChunk.spawn_burst(get_parent(), Vector2(_pos.x, _ground_y), Color(0.5, 0.38, 0.22), 5, Vector2.UP, 200.0)
	CombatVfx.spawn_burst(get_parent(), Vector2(_pos.x, _ground_y), Color(0.85, 0.62, 0.35, 0.8),
		Color(0.4, 0.28, 0.15, 0.0), 14, 0.4, 60.0, 180.0, 1.4, 3.5)
	ScorchDecal.spawn(get_parent(), Vector2(_pos.x, _ground_y), BOULDER_R * 1.3, "crack",
		Color(0.5, 0.36, 0.22, 0.6), 7.0)  # the HOLE left in the ground
	Juice.shake_camera(3.0)
	Sfx.play("blast", -6.0, 0.1)
	queue_redraw()


## Downward floor raycast (collision layer 1) — the ground the rock rips from.
func _floor_below(from: Vector2, max_dist: float) -> Dictionary:
	var world: World2D = get_world_2d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, max_dist), 1)
	return world.direct_space_state.intersect_ray(query)


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	_spin += delta * 9.0
	if _shockwave_elapsed >= 0.0:
		_shockwave_elapsed += delta
		queue_redraw()
		return
	if _elapsed < RISE_TIME:
		var u: float = _elapsed / RISE_TIME
		_pos.y = _ground_y - RISE_HEIGHT * (1.0 - pow(1.0 - u, 2.0))  # ease-out lift
	elif _elapsed < RISE_TIME + HANG_TIME:
		_pos.y = _ground_y - RISE_HEIGHT
	else:
		# FLIGHT
		if not _flying:
			_flying = true
			Sfx.play("melee_swing", -2.0, 0.1)
		_prev_pos = _pos
		_pos += _dir * FLIGHT_SPEED * delta
		_traveled += FLIGHT_SPEED * delta
		var hit_pos: Vector2 = _pos
		if _check_flight_collision(hit_pos):
			_impact(_hit_point)
			return
		if _traveled >= MAX_FLIGHT:
			_impact(_pos)
			return
	queue_redraw()


var _hit_point: Vector2 = Vector2.ZERO


## First enemy within reach OR a layer-1 wall along the travelled segment.
func _check_flight_collision(_unused: Vector2) -> bool:
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if e is Node2D and _pos.distance_to((e as Node2D).global_position) <= BOULDER_R + HIT_PAD:
			_hit_point = (e as Node2D).global_position
			return true
	var world: World2D = get_world_2d()
	if world != null:
		var q := PhysicsRayQueryParameters2D.create(_prev_pos, _pos, 1)
		q.hit_from_inside = true
		var wall: Dictionary = world.direct_space_state.intersect_ray(q)
		if not wall.is_empty():
			_hit_point = wall["position"]
			return true
	return false


func _impact(at: Vector2) -> void:
	_pos = at
	_apply_impact_damage(at)
	_shatter(at)
	_shockwave_elapsed = 0.0
	Juice.on_hit({"dir": _dir, "shake": 13.0, "kick": 10.0, "zoom": 0.11,
		"sfx": "blast", "sfx_pitch": 0.1, "hitstop": 0.1})
	Juice.zoom_pull_camera(0.12, 0.3, 0.12, 0.45)
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


func _shatter(at: Vector2) -> void:
	var hit: Dictionary = _floor_below(at, IMPACT_RADIUS * 2.2)
	var floor_pos: Vector2 = hit["position"] if not hit.is_empty() else at
	DebrisChunk.spawn_burst(get_parent(), floor_pos, Color(0.5, 0.38, 0.22), DEBRIS_COUNT, _dir, 340.0)
	CombatVfx.spawn_burst(get_parent(), at, Color(0.85, 0.62, 0.35, 0.9), Color(0.4, 0.28, 0.15, 0.0),
		30, 0.5, 80.0, 260.0, 1.8, 5.0)
	ScorchDecal.spawn(get_parent(), floor_pos, IMPACT_RADIUS * 0.6, "crack",
		Color(0.6, 0.45, 0.28, 0.6), 8.0)


## Pure geometry (testable): nodes within `radius` of `center`.
static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
	var out: Array = []
	for n: Node in nodes:
		if n is Node2D and center.distance_to((n as Node2D).global_position) <= radius:
			out.append(n)
	return out


func _apply_impact_damage(at: Vector2) -> void:
	for enemy: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group("enemy")):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			enemy.apply_knockback((away if away != Vector2.ZERO else Vector2.UP) * KNOCKBACK)
	for prop: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("damage_at"):
			prop.damage_at(_damage, (prop as Node2D).global_position, _dir)
		elif prop.has_method("take_damage"):
			prop.take_damage(_damage)
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if proj is Node2D and at.distance_to((proj as Node2D).global_position) <= _radius \
				and proj.has_method("consume"):
			proj.call("consume")


func _make_boulder(rad: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = 7
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var r: float = rad * randf_range(0.78, 1.12)
		pts.append(Vector2.from_angle(a) * r)
	return pts


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _shockwave_elapsed >= 0.0:
		_draw_shockwave()
		return
	# Boulder body at _pos, rotated by _spin.
	var rot: Transform2D = Transform2D(_spin, _pos)
	var body: PackedVector2Array = PackedVector2Array()
	var lit: PackedVector2Array = PackedVector2Array()
	for i in _shape.size():
		body.append(rot * _shape[i])
	draw_colored_polygon(body, BODY_COLOR)
	# Lit top edge (upper verts) + HDR rim highlight.
	for i in _shape.size():
		var a: Vector2 = rot * _shape[i]
		var b: Vector2 = rot * _shape[(i + 1) % _shape.size()]
		var mid: Vector2 = (a + b) * 0.5
		if mid.y < _pos.y:  # upper-facing edge catches light
			draw_line(a, b, LIT_COLOR, 2.0, true)
			if mid.x < _pos.x:
				draw_line(a, b, RIM_COLOR, 1.2, true)
	# Inner facet for chunk read.
	draw_circle(_pos, BOULDER_R * 0.34, Color(0.42, 0.3, 0.18), true, -1.0, true)
	# Dust smear trailing opposite travel.
	if _flying:
		draw_circle(_pos - _dir * BOULDER_R * 0.8, BOULDER_R * 0.7, DUST_TINT, true, -1.0, true)


func _draw_shockwave() -> void:
	var t: float = clampf(_shockwave_elapsed / SHOCKWAVE_TIME, 0.0, 1.0)
	if t >= 1.0:
		return
	var alpha: float = 1.0 - t
	var r: float = lerpf(8.0, IMPACT_RADIUS * 1.35, t)
	draw_arc(_pos, r, 0.0, TAU, 48, Color(0.85, 0.6, 0.3, 0.9 * alpha), lerpf(9.0, 2.0, t), true)
	if t < 0.4:
		var flash: float = 1.0 - t / 0.4
		draw_circle(_pos, IMPACT_RADIUS * 0.7 * flash, Color(1.3, 1.0, 0.6, 0.35 * flash), true, -1.0, true)
