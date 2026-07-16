class_name RockPillar
extends Node2D

## Who this pillar's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## Earthbending ROCK PILLAR (the uppercut). A telegraphed danger ring + rumble,
## then a chunky stone column ERUPTS up from the ground at the marked point,
## launching everything in its footprint straight UP (big vertical knockback) +
## damage + Stagger, then crumbles into rubble and leaves a cracked ground.
## Instantiate .new(), add to arena, call erupt(). Draws in world coordinates.

const CHARGE_TIME: float = 0.40    # telegraphed danger ring + rumble
const ERUPT_RISE: float = 0.14     # column shoots up
const PILLAR_HOLD: float = 0.22
const CRUMBLE_TIME: float = 0.34
const PILLAR_HEIGHT: float = 150.0
const PILLAR_WIDTH: float = 46.0
const DEFAULT_RADIUS: float = 66.0
const DEFAULT_DAMAGE: int = 58
const UP_KNOCKBACK: float = 620.0  # BIG vertical launch — routed into velocity.y
const DEBRIS_COUNT: int = 18
const BLOCKS: int = 5

const BODY_COLOR: Color = Color(0.34, 0.24, 0.15)
const LIT_COLOR: Color = Color(0.62, 0.46, 0.26)
const RIM_COLOR: Color = Color(1.15, 0.92, 0.55)
const SEAM_COLOR: Color = Color(0.2, 0.14, 0.09)

var _ground: Vector2 = Vector2.ZERO
var _color: Color = Color(0.78, 0.55, 0.28)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var element_id: int = -1

var _elapsed: float = -1.0
var _erupted: bool = false
var _rumble_accum: float = 0.0
var _jitter: PackedFloat32Array = PackedFloat32Array()


func erupt(
	target: Vector2, color: Color = Color(0.78, 0.55, 0.28),
	radius: float = DEFAULT_RADIUS, damage: int = DEFAULT_DAMAGE, _effect: String = "earth"
) -> void:
	_ground = target
	var hit: Dictionary = _floor_below(target, 200.0)
	if not hit.is_empty():
		_ground = hit["position"]
	_color = color
	_radius = radius
	_damage = damage
	_elapsed = 0.0
	for i in BLOCKS:
		_jitter.append(randf_range(-0.28, 0.28))
	Sfx.play("earth", -3.0, 0.08)
	Juice.shake_camera(3.0)
	queue_redraw()


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
	if _elapsed < CHARGE_TIME:
		# Rumble pulses during the tell.
		_rumble_accum += delta
		if _rumble_accum >= 0.12:
			_rumble_accum = 0.0
			Juice.shake_camera(2.0)
			CombatVfx.spawn_burst(get_parent(), _ground, Color(0.7, 0.52, 0.3, 0.5),
				Color(0.4, 0.28, 0.15, 0.0), 4, 0.35, 30.0, 90.0, 1.0, 2.5)
	elif not _erupted:
		_erupted = true
		_apply_launch()
		DebrisChunk.spawn_burst(get_parent(), _ground, Color(0.5, 0.38, 0.22), DEBRIS_COUNT, Vector2.UP, 300.0)
		CombatVfx.spawn_burst(get_parent(), _ground, Color(0.85, 0.62, 0.35, 0.9),
			Color(0.4, 0.28, 0.15, 0.0), 24, 0.5, 90.0, 280.0, 1.6, 4.5)
		Juice.on_hit({"shake": 15.0, "zoom": 0.1, "sfx": "blast", "sfx_pitch": 0.08, "hitstop": 0.09})
		Juice.zoom_pull_camera(0.14, 0.4, 0.14, 0.5)
	var total: float = CHARGE_TIME + ERUPT_RISE + PILLAR_HOLD + CRUMBLE_TIME
	if _elapsed >= CHARGE_TIME + ERUPT_RISE + PILLAR_HOLD and _elapsed < total:
		# Crumble: shed rubble as it collapses (a couple of staggered pops).
		if fmod(_elapsed, 0.12) < delta:
			DebrisChunk.spawn_burst(get_parent(), _ground - Vector2(0.0, PILLAR_HEIGHT * 0.6),
				Color(0.5, 0.38, 0.22), 6, Vector2.ZERO, 170.0)
	if _elapsed >= total:
		ScorchDecal.spawn(get_parent(), _ground, _radius * 0.5, "crack",
			Color(0.6, 0.45, 0.28, 0.55), 7.0)
		queue_free()
		return
	queue_redraw()


static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
	var out: Array = []
	for n: Node in nodes:
		if n is Node2D and center.distance_to((n as Node2D).global_position) <= radius:
			out.append(n)
	return out


func _apply_launch() -> void:
	for enemy: Node in targets_in_radius(_ground, _radius, get_tree().get_nodes_in_group(target_group)):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			# Straight up (small horizontal jitter) — the uppercut launch.
			var up: Vector2 = Vector2(randf_range(-0.2, 0.2), -1.0).normalized()
			enemy.apply_knockback(up * UP_KNOCKBACK)
	for prop: Node in targets_in_radius(_ground, _radius, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < CHARGE_TIME:
		var tp: float = _elapsed / CHARGE_TIME
		draw_arc(_ground, _radius * (0.3 + 0.6 * tp), 0.0, TAU, 40,
			Color(_color.r, _color.g, _color.b, 0.5 * tp), 2.5, true)
		return
	# Column height + fade.
	var local: float = _elapsed - CHARGE_TIME
	var height: float
	var alpha: float = 1.0
	if local < ERUPT_RISE:
		height = PILLAR_HEIGHT * (1.0 - pow(1.0 - local / ERUPT_RISE, 2.0))
	elif local < ERUPT_RISE + PILLAR_HOLD:
		height = PILLAR_HEIGHT
	else:
		height = PILLAR_HEIGHT
		alpha = clampf(1.0 - (local - ERUPT_RISE - PILLAR_HOLD) / CRUMBLE_TIME, 0.0, 1.0)
	if height <= 1.0:
		return
	_draw_column(height, alpha)
	# Dust skirt at base.
	draw_circle(_ground, PILLAR_WIDTH * 0.9, Color(0.55, 0.42, 0.28, 0.35 * alpha), true, -1.0, true)


func _draw_column(height: float, alpha: float) -> void:
	var block_h: float = height / float(BLOCKS)
	for i in BLOCKS:
		var y_top: float = _ground.y - block_h * float(i + 1)
		var y_bot: float = _ground.y - block_h * float(i)
		var jx: float = _jitter[i] * PILLAR_WIDTH
		var hw: float = PILLAR_WIDTH * 0.5 * (1.0 - 0.06 * float(i))  # slight taper up
		var cx: float = _ground.x + jx
		var verts: PackedVector2Array = PackedVector2Array([
			Vector2(cx - hw, y_bot), Vector2(cx - hw * 0.85, y_top),
			Vector2(cx + hw * 0.9, y_top), Vector2(cx + hw, y_bot),
		])
		draw_colored_polygon(verts, Color(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b, alpha))
		# Lit top edge + HDR corner + dark seam.
		draw_line(Vector2(cx - hw * 0.85, y_top), Vector2(cx + hw * 0.9, y_top),
			Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, alpha), 3.0, true)
		draw_line(Vector2(cx - hw * 0.85, y_top), Vector2(cx - hw, y_bot),
			Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, alpha), 1.4, true)
		draw_line(Vector2(cx - hw, y_bot), Vector2(cx + hw, y_bot),
			Color(SEAM_COLOR.r, SEAM_COLOR.g, SEAM_COLOR.b, alpha), 2.0, true)
