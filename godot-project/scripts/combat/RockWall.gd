class_name RockWall
extends Node2D
## Earthbending ROCK WALL. A temporary SOLID stone slab rises from the ground in
## the aim direction — a StaticBody2D on collision layer 1, so it blocks enemy
## BODIES (CharacterBody2D) and enemy PROJECTILES (which raycast layer 1) for a
## few seconds, then crumbles into rubble. Defensive: no damage.
## Instantiate .new(), add to arena, call raise_wall(). Draws in world coords.

const WALL_OFFSET: float = 90.0     # how far in front of the caster it rises
const WALL_SIZE: Vector2 = Vector2(34.0, 128.0)  # thickness x height
const RISE_TIME: float = 0.28
const LIFETIME: float = 4.5         # solid + blocking
const CRUMBLE_TIME: float = 0.5
const DEBRIS_COUNT: int = 20
const BLOCKS: int = 6

const BODY_COLOR: Color = Color(0.34, 0.24, 0.15)
const LIT_COLOR: Color = Color(0.62, 0.46, 0.26)
const RIM_COLOR: Color = Color(1.15, 0.92, 0.55)
const SEAM_COLOR: Color = Color(0.2, 0.14, 0.09)
const AMBER_RIM: Color = Color(0.85, 0.55, 0.15)

var element_id: int = -1
var _floor_base: Vector2 = Vector2.ZERO
var _color: Color = Color(0.78, 0.55, 0.28)
var _elapsed: float = -1.0
var _crumbling: bool = false
var _body: StaticBody2D = null
var _collider: CollisionShape2D = null
var _jitter: PackedFloat32Array = PackedFloat32Array()


func raise_wall(
	from: Vector2, aim: Vector2, color: Color = Color(0.78, 0.55, 0.28), _effect: String = "earth"
) -> void:
	_color = color
	_floor_base = wall_center(from, aim, WALL_OFFSET)
	var hit: Dictionary = _floor_below(_floor_base, 220.0)
	if not hit.is_empty():
		_floor_base = hit["position"]
	_elapsed = 0.0
	for i in BLOCKS:
		_jitter.append(randf_range(-0.22, 0.22))
	# Real blocking body — layer 1 stops enemy bodies + enemy projectiles.
	_body = StaticBody2D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_body.global_position = _floor_base
	var shape := RectangleShape2D.new()
	shape.size = WALL_SIZE
	_collider = CollisionShape2D.new()
	_collider.shape = shape
	_collider.position = Vector2(0.0, -WALL_SIZE.y * 0.5)  # extend UP from the base
	_body.add_child(_collider)
	# Ground breaks as it rises.
	DebrisChunk.spawn_burst(get_parent(), _floor_base, Color(0.5, 0.38, 0.22), 6, Vector2.UP, 220.0)
	CombatVfx.spawn_burst(get_parent(), _floor_base, Color(0.85, 0.62, 0.35, 0.8),
		Color(0.4, 0.28, 0.15, 0.0), 16, 0.45, 70.0, 200.0, 1.5, 4.0)
	Juice.shake_camera(6.0)
	Sfx.play("blast", -4.0, 0.08)
	queue_redraw()


## Pure geometry (testable): where the wall lands relative to the caster + aim.
static func wall_center(from: Vector2, aim: Vector2, offset: float = WALL_OFFSET) -> Vector2:
	var d: Vector2 = aim.normalized()
	if d == Vector2.ZERO:
		d = Vector2.RIGHT
	return from + d * offset


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
	if _elapsed >= RISE_TIME + LIFETIME and not _crumbling:
		_crumbling = true
		if _collider != null:
			_collider.set_deferred("disabled", true)  # stops blocking once it crumbles
		DebrisChunk.spawn_burst(get_parent(), _floor_base - Vector2(0.0, WALL_SIZE.y * 0.5),
			Color(0.5, 0.38, 0.22), DEBRIS_COUNT, Vector2.DOWN, 200.0)
		ScorchDecal.spawn(get_parent(), _floor_base, WALL_SIZE.x * 0.9, "crack",
			Color(0.6, 0.45, 0.28, 0.55), 6.0)
		Juice.shake_camera(5.0)
		Sfx.play("enemy_death", -2.0, 0.1)
	if _elapsed >= RISE_TIME + LIFETIME + CRUMBLE_TIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var height: float
	var alpha: float = 1.0
	if _elapsed < RISE_TIME:
		height = WALL_SIZE.y * (1.0 - pow(1.0 - _elapsed / RISE_TIME, 2.0))  # ease-out emerge
	elif not _crumbling:
		height = WALL_SIZE.y
	else:
		height = WALL_SIZE.y
		alpha = clampf(1.0 - (_elapsed - RISE_TIME - LIFETIME) / CRUMBLE_TIME, 0.0, 1.0)
	if height <= 1.0:
		return
	var block_h: float = height / float(BLOCKS)
	var hw: float = WALL_SIZE.x * 0.5
	for i in BLOCKS:
		var y_top: float = _floor_base.y - block_h * float(i + 1)
		var y_bot: float = _floor_base.y - block_h * float(i)
		var jx: float = _jitter[i] * WALL_SIZE.x * 0.5
		var cx: float = _floor_base.x + jx
		var verts: PackedVector2Array = PackedVector2Array([
			Vector2(cx - hw, y_bot), Vector2(cx - hw * 0.92, y_top),
			Vector2(cx + hw * 0.95, y_top), Vector2(cx + hw, y_bot),
		])
		draw_colored_polygon(verts, Color(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b, alpha))
		draw_line(Vector2(cx - hw * 0.92, y_top), Vector2(cx + hw * 0.95, y_top),
			Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, alpha), 3.0, true)
		draw_line(Vector2(cx - hw * 0.92, y_top), Vector2(cx - hw, y_bot),
			Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, alpha), 1.4, true)
		draw_line(Vector2(cx - hw, y_bot), Vector2(cx + hw, y_bot),
			Color(SEAM_COLOR.r, SEAM_COLOR.g, SEAM_COLOR.b, alpha), 2.0, true)
	# Amber "this is destructible" rim on the top block (echoes BreakablePlatform).
	var top_y: float = _floor_base.y - height
	draw_line(Vector2(_floor_base.x - hw, top_y), Vector2(_floor_base.x + hw, top_y),
		Color(AMBER_RIM.r, AMBER_RIM.g, AMBER_RIM.b, alpha * 0.8), 2.0, true)
	# Dust skirt.
	draw_circle(_floor_base, WALL_SIZE.x * 0.8, Color(0.55, 0.42, 0.28, 0.35 * alpha), true, -1.0, true)
