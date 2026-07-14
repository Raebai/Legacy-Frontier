class_name IceWall
extends Node2D
## Cryomancer ICE WALL — a temporary SOLID crystalline barrier rises from the
## ground in the aim direction: a StaticBody2D on collision layer 1, so it blocks
## enemy BODIES + enemy PROJECTILES for a few seconds, then shatters into shards.
## Distinct class identity (zoning, NOT a beam): enemies touching it get CHILLED.
## Forked from RockWall (proven blocking body) with a cyan faceted-crystal skin.
## Instantiate .new(), add to arena, call raise_wall(). Draws in world coords.

const WALL_OFFSET: float = 90.0
const WALL_SIZE: Vector2 = Vector2(30.0, 130.0)  # thickness x height (slightly slimmer than stone)
const RISE_TIME: float = 0.24
const LIFETIME: float = 4.5
const CRUMBLE_TIME: float = 0.5
const DEBRIS_COUNT: int = 20
const BLOCKS: int = 6
const CHILL_INTERVAL: float = 0.4  # re-chill cadence for anything touching it

const BODY_COLOR: Color = Color(0.42, 0.68, 0.92)
const LIT_COLOR: Color = Color(0.72, 0.9, 1.0)
const RIM_COLOR: Color = Color(1.3, 1.5, 1.7)      # HDR white-cyan rim (blooms)
const SEAM_COLOR: Color = Color(0.2, 0.34, 0.5)
const FACET_COLOR: Color = Color(0.95, 0.99, 1.0)

var element_id: int = Elements.Element.ICE
var _floor_base: Vector2 = Vector2.ZERO
var _color: Color = Color(0.55, 0.8, 1.0)
var _elapsed: float = -1.0
var _crumbling: bool = false
var _body: StaticBody2D = null
var _collider: CollisionShape2D = null
var _jitter: PackedFloat32Array = PackedFloat32Array()
var _chill_tick: float = 0.0


func raise_wall(
	from: Vector2, aim: Vector2, color: Color = Color(0.55, 0.8, 1.0), _effect: String = "frost"
) -> void:
	_color = color
	_floor_base = wall_center(from, aim, WALL_OFFSET)
	var hit: Dictionary = _floor_below(_floor_base, 220.0)
	if not hit.is_empty():
		_floor_base = hit["position"]
	_elapsed = 0.0
	for i in BLOCKS:
		_jitter.append(randf_range(-0.2, 0.2))
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
	# Frost burst as it forms + an immediate chill on anything already in the space.
	CombatVfx.spawn_burst(get_parent(), _floor_base, Color(0.75, 0.92, 1.0, 0.9),
		Color(0.4, 0.65, 1.0, 0.0), 16, 0.45, 70.0, 200.0, 0.8, 2.4, 0.0, 0.0, true)
	_chill_touching()
	Juice.shake_camera(5.0)
	Sfx.play("blast", -5.0, 0.1)
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


## Chill any enemy overlapping the wall footprint (touching the ice). Runs on
## raise + on a cadence while the wall stands so lingering enemies keep freezing.
func _chill_touching() -> void:
	var hw: float = WALL_SIZE.x * 0.5 + 14.0
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not e is Node2D or not is_instance_valid(e):
			continue
		var p: Vector2 = (e as Node2D).global_position
		if absf(p.x - _floor_base.x) > hw:
			continue
		if p.y > _floor_base.y + 12.0 or p.y < _floor_base.y - WALL_SIZE.y - 12.0:
			continue
		if e.has_method("apply_status"):
			e.apply_status(element_id)


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	# Keep chilling anything pressed against the wall while it stands.
	if not _crumbling:
		_chill_tick -= delta
		if _chill_tick <= 0.0:
			_chill_tick = CHILL_INTERVAL
			_chill_touching()
	if _elapsed >= RISE_TIME + LIFETIME and not _crumbling:
		_crumbling = true
		if _collider != null:
			_collider.set_deferred("disabled", true)
		DebrisChunk.spawn_burst(get_parent(), _floor_base - Vector2(0.0, WALL_SIZE.y * 0.5),
			Color(0.7, 0.9, 1.0), DEBRIS_COUNT, Vector2.DOWN, 200.0)
		CombatVfx.spawn_burst(get_parent(), _floor_base - Vector2(0.0, WALL_SIZE.y * 0.5),
			Color(0.85, 0.97, 1.0, 0.95), Color(0.5, 0.75, 1.0, 0.0), 16, 0.4, 80.0, 220.0, 0.6, 2.0, 0.0, 0.0, true)
		Juice.shake_camera(4.0)
		Sfx.play("spell_impact", -3.0, 0.12)  # ice shatter
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
		height = WALL_SIZE.y * (1.0 - pow(1.0 - _elapsed / RISE_TIME, 2.0))
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
		# Faceted crystal block — a slightly translucent icy body with a bright rim.
		var verts: PackedVector2Array = PackedVector2Array([
			Vector2(cx - hw, y_bot), Vector2(cx - hw * 0.86, y_top),
			Vector2(cx + hw * 0.9, y_top), Vector2(cx + hw, y_bot),
		])
		draw_colored_polygon(verts, Color(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b, 0.82 * alpha))
		# Internal facet highlight (a diagonal crystal fracture).
		draw_line(Vector2(cx - hw * 0.5, y_bot), Vector2(cx + hw * 0.3, y_top),
			Color(FACET_COLOR.r, FACET_COLOR.g, FACET_COLOR.b, 0.4 * alpha), 1.2, true)
		draw_line(Vector2(cx - hw * 0.86, y_top), Vector2(cx + hw * 0.9, y_top),
			Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, alpha), 2.5, true)
		draw_line(Vector2(cx - hw * 0.86, y_top), Vector2(cx - hw, y_bot),
			Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, alpha), 1.4, true)
		draw_line(Vector2(cx - hw, y_bot), Vector2(cx + hw, y_bot),
			Color(SEAM_COLOR.r, SEAM_COLOR.g, SEAM_COLOR.b, alpha), 2.0, true)
	# Bright HDR crown on the top block (blooms) + a frost skirt at the base.
	var top_y: float = _floor_base.y - height
	draw_line(Vector2(_floor_base.x - hw, top_y), Vector2(_floor_base.x + hw, top_y),
		Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, alpha), 2.2, true)
	draw_circle(_floor_base, WALL_SIZE.x * 0.85, Color(0.6, 0.85, 1.0, 0.3 * alpha), true, -1.0, true)
