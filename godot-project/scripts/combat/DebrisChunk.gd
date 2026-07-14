class_name DebrisChunk
extends RigidBody2D
## Real-physics rubble: a small tumbling stone chunk with actual gravity that
## pops UP and OUT from a hit, arcs, tumbles, lands on the platforms/floor,
## settles, then fades and frees. Replaces DestructibleTerrain's old
## tween-driven ColorRect rubble — these chunks live in the physics world, so
## where they land depends on where the hit came from (the maker's ask:
## "chunks that break off + FALL based on where hits land").
##
## Collision: layer value 32 (layer 6) — a DEDICATED bit nothing else scans,
## so chunks can never shove fighters and spells can never hit them. Mask 1
## ONLY: chunks rest on platforms/walls/destructible-tops (all of which
## include layer 1) but pass through hero (layer 2), enemies (layer 4) and
## each other.
##
## Headless-safe by design: no autoload references (Sfx/Juice/Rank/Tuning),
## pure physics + _draw, so tools/slice_test_debris.gd can load() and drive
## it under a dummy renderer.

const GROUP_NAME: String = "debris_chunk"
const MAX_LIVE_CHUNKS: int = 90  # global perf cap; spawn_burst refuses beyond it
const CHUNK_LAYER: int = 32  # layer 6 — dedicated, see header
const CHUNK_MASK: int = 1  # platforms/walls only
# Visual size band (px across, roughly).
const SIZE_MIN: float = 4.0
const SIZE_MAX: float = 9.0
# Lifetime: fly + settle for LIFETIME_*, then fade out over FADE_TIME.
# Longer settle + lingering rubble = Stick-Fight "permanence" (the world stays
# visibly impacted after the fight moment, not wiped a second later).
const LIFETIME_MIN: float = 2.6
const LIFETIME_MAX: float = 4.2
const FADE_TIME: float = 1.2
# Launch shaping (spawn_burst).
const SPEED_VARIANCE: float = 0.35  # +/- fraction of the requested speed
const SPREAD_ARC: float = 0.9  # rad each side around impact_dir
const UPWARD_BIAS: float = 0.65  # blended UP so chunks arc instead of skidding
const SPIN_MAX: float = 12.0  # rad/s initial tumble
const SPAWN_JITTER: float = 4.0  # px around the impact point
const COLOR_VARIANCE: float = 0.18  # per-chunk darken/lighten reach
# Settle feel: enough damping + friction that chunks come to rest instead of
# rolling off the map, a whisper of bounce so landings read.
const LINEAR_DAMP_AMOUNT: float = 0.35
const ANGULAR_DAMP_AMOUNT: float = 3.0
const SURFACE_FRICTION: float = 0.9
const SURFACE_BOUNCE: float = 0.12

var chunk_color: Color = Color(0.42, 0.44, 0.5)  # stone-ish default

var _size: float = 0.0
var _verts: PackedVector2Array = PackedVector2Array()
var _age: float = 0.0
var _lifetime: float = 1.0
## Initial launch applied ONCE via _integrate_forces (never by setting
## linear_velocity directly): spawn_burst is often called from a physics-flush
## signal (Spell.body_entered, DestructibleTerrain._shatter) where mutating a
## fresh RigidBody's state directly is unsafe. _integrate_forces is the safe seam.
var _pending_launch: Vector2 = Vector2.ZERO
var _pending_spin: float = 0.0
var _launched: bool = false


## Spawn up to `count` physics rubble chunks under `parent` at world `pos`,
## launched as a spread around `impact_dir` (ZERO -> full-circle burst) and
## biased upward so they arc out of the hit, then fall + settle. Respects the
## MAX_LIVE_CHUNKS global cap (spawns only the remaining headroom). Null-safe:
## silently skips when the parent is gone (e.g. a blast resolving during
## teardown) — mirrors CombatVfx.spawn_burst / ScorchDecal.spawn.
static func spawn_burst(
	parent: Node,
	pos: Vector2,
	base_color: Color,
	count: int,
	impact_dir: Vector2 = Vector2.ZERO,
	speed: float = 240.0,
) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var headroom: int = MAX_LIVE_CHUNKS - _live_count(parent.get_tree())
	var to_spawn: int = clampi(count, 0, maxi(headroom, 0))
	for i: int in to_spawn:
		var chunk: DebrisChunk = DebrisChunk.new()
		chunk.chunk_color = _vary_color(base_color)
		parent.add_child(chunk)
		chunk.global_position = pos + Vector2(
			randf_range(-SPAWN_JITTER, SPAWN_JITTER),
			randf_range(-SPAWN_JITTER, SPAWN_JITTER)
		)
		var out_dir: Vector2
		if impact_dir == Vector2.ZERO:
			out_dir = Vector2.from_angle(randf() * TAU)
		else:
			out_dir = impact_dir.normalized().rotated(randf_range(-SPREAD_ARC, SPREAD_ARC))
		# Blend an upward pull into the outward direction: chunks POP up-and-out
		# from the hit, arc under gravity, then land — not a flat radial skid.
		var launch_dir: Vector2 = (out_dir + Vector2.UP * UPWARD_BIAS).normalized()
		chunk._pending_launch = launch_dir * speed \
			* randf_range(1.0 - SPEED_VARIANCE, 1.0 + SPEED_VARIANCE)
		chunk._pending_spin = randf_range(-SPIN_MAX, SPIN_MAX)


## Live (not-yet-freed) chunk count across the whole tree, for the global cap.
static func _live_count(tree: SceneTree) -> int:
	if tree == null:
		return 0
	var live: int = 0
	for chunk: Node in tree.get_nodes_in_group(GROUP_NAME):
		if is_instance_valid(chunk) and not chunk.is_queued_for_deletion():
			live += 1
	return live


## Slight per-chunk tint variance so a burst reads as many stones, not clones.
static func _vary_color(base_color: Color) -> Color:
	var shift: float = randf_range(-COLOR_VARIANCE, COLOR_VARIANCE)
	if shift < 0.0:
		return base_color.darkened(-shift)
	return base_color.lightened(shift)


func _ready() -> void:
	add_to_group(GROUP_NAME)
	collision_layer = CHUNK_LAYER
	collision_mask = CHUNK_MASK
	gravity_scale = 1.0
	linear_damp = LINEAR_DAMP_AMOUNT
	angular_damp = ANGULAR_DAMP_AMOUNT
	contact_monitor = false  # no contact reports needed — cheapest config
	max_contacts_reported = 0
	var surface: PhysicsMaterial = PhysicsMaterial.new()
	surface.friction = SURFACE_FRICTION
	surface.bounce = SURFACE_BOUNCE
	physics_material_override = surface
	_lifetime = randf_range(LIFETIME_MIN, LIFETIME_MAX)
	if _verts.is_empty():
		_generate_shape()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2.ONE * _size * 0.7  # a touch inside the drawn silhouette
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	queue_redraw()


## Apply the launch impulse ONCE, safely, on the first physics step — works no
## matter what context spawn_burst was called from (default gravity still runs;
## we only override velocity on frame one, then let physics take over -> arc).
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _launched:
		return
	_launched = true
	state.linear_velocity = _pending_launch
	state.angular_velocity = _pending_spin


## Age out: fly + settle for _lifetime, fade over FADE_TIME, then free.
func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime + FADE_TIME:
		queue_free()
	elif _age >= _lifetime:
		modulate.a = clampf(1.0 - (_age - _lifetime) / FADE_TIME, 0.0, 1.0)


## Bake one irregular tri/quad silhouette per chunk (ScorchDecal's pre-bake
## approach) so _draw() stays deterministic while the body tumbles.
func _generate_shape() -> void:
	_size = randf_range(SIZE_MIN, SIZE_MAX)
	_verts.clear()
	var corners: int = 3 if randf() < 0.35 else 4
	for i: int in corners:
		var angle: float = TAU * float(i) / float(corners) + randf_range(-0.35, 0.35)
		var reach: float = _size * randf_range(0.35, 0.55)
		_verts.append(Vector2.from_angle(angle) * reach)


func _draw() -> void:
	if _verts.size() < 3:
		return
	draw_colored_polygon(_verts, chunk_color)
	# Subtle darker edge (softened from a harsh outline so small chunks read as
	# solid stones, not spiky asterisks): closed polyline back to the first vertex.
	var outline: PackedVector2Array = _verts.duplicate()
	outline.append(_verts[0])
	draw_polyline(outline, chunk_color.darkened(0.3), 1.0)
