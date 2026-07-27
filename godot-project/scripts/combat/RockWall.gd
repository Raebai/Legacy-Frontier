class_name RockWall
extends Node2D
## Earthbending ROCK WALL. A temporary SOLID stone barrier SLAMS up out of the
## ground in the aim direction — heavy irregular slabs erupt one after another
## (bottom-first, with overshoot) so the raise reads as an upheaval, not a grow.
## A StaticBody2D on collision layer 1 blocks enemy BODIES + enemy PROJECTILES
## for a few seconds, then crumbles into rubble. Defensive at rest — but SHOVE
## it (see shove()) and it becomes a grinding projectile-wall that plows enemies,
## smashes crates, and slams to a stop against real world geometry.
## Instantiate .new(), add to arena, call raise_wall(). Draws in world coords.
##
## SHOVE CONTRACT (for the punch / RMB hook in SpikeFigure):
##   * every standing wall is in the "shoveable" group
##   * `shove(dir, speed)` starts the slide (returns false if crumbling/sliding)
##   * `wall_distance(pos)` = px from pos to the wall's footprint (for range checks)
##   * `RockWall.find_shoveable_near(tree, pos, max_dist)` = nearest shoveable or null

const WALL_OFFSET: float = 90.0     # how far in front of the caster it rises
const WALL_SIZE: Vector2 = Vector2(44.0, 124.0)  # thickness x height — CHUNKY (ice is slim)
const RISE_TIME: float = 0.34       # full upheaval: last slab locks just before this
const SLAB_RISE: float = 0.16       # one slab's pop-up time
const SLAB_STAGGER: float = 0.055   # delay between slab launches (bottom-first)
const LIFETIME: float = 4.5         # solid + blocking
const CRUMBLE_TIME: float = 0.5
const DEBRIS_COUNT: int = 22
const SLABS: int = 4                # few BIG slabs (ice is many thin spires)

## Shove tuning — the wall as a projectile. Speed sits below BoulderHurl's 900
## so the slide reads heavier than the throw; damage/knockback match a mid hit.
const SHOVE_SPEED: float = 820.0
const SHOVE_DAMAGE: int = 40
const SHOVE_KNOCKBACK: float = 560.0
const MAX_SLIDE: float = 2200.0     # off-map cap: despawn if nothing stopped it
const GRIND_DUST_INTERVAL: float = 0.06
const PLOW_PAD: float = 22.0        # extra reach on the enemy plow check

const BODY_COLOR: Color = Color(0.38, 0.27, 0.17)
const FACE_COLOR: Color = Color(0.5, 0.37, 0.23)
const LIT_COLOR: Color = Color(0.62, 0.46, 0.26)
const RIM_COLOR: Color = Color(1.15, 0.92, 0.55)  # HDR highlight (blooms)
const SEAM_COLOR: Color = Color(0.16, 0.11, 0.07)
const AMBER_RIM: Color = Color(0.85, 0.55, 0.15)
const DUST_TINT: Color = Color(0.55, 0.42, 0.28, 0.5)

var element_id: int = -1
var _floor_base: Vector2 = Vector2.ZERO
var _color: Color = Color(0.78, 0.55, 0.28)
var _elapsed: float = -1.0
var _crumbling: bool = false
var _body: StaticBody2D = null
var _collider: CollisionShape2D = null

# Slab geometry, built once at raise: local-space polys with y=0 at the floor.
var _slab_polys: Array[PackedVector2Array] = []
var _slab_base_y: PackedFloat32Array = PackedFloat32Array()  # local y of each slab's bottom
var _slab_delay: PackedFloat32Array = PackedFloat32Array()
var _slab_locked: Array[bool] = []
var _stack_h: float = 0.0

# Shove state.
var _sliding: bool = false
var _slide_dir: Vector2 = Vector2.RIGHT
var _slide_speed: float = SHOVE_SPEED
var _slide_traveled: float = 0.0
var _grind_t: float = 0.0
var _plowed: Dictionary = {}        # instance_id -> true (each enemy hit once per slide)


func raise_wall(
	from: Vector2, aim: Vector2, color: Color = Color(0.78, 0.55, 0.28), _effect: String = "earth"
) -> void:
	_color = color
	_floor_base = wall_center(from, aim, WALL_OFFSET)
	var hit: Dictionary = _floor_below(_floor_base, 220.0)
	if not hit.is_empty():
		_floor_base = hit["position"]
	_elapsed = 0.0
	_build_slabs()
	add_to_group("shoveable")  # the punch/RMB hook finds walls through this group
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
	# The ground BREAKS as the first slab tears out — a slam, not a fade-in.
	DebrisChunk.spawn_burst(get_parent(), _floor_base, Color(0.5, 0.38, 0.22), 8, Vector2.UP, 260.0)
	CombatVfx.spawn_burst(get_parent(), _floor_base, Color(0.85, 0.62, 0.35, 0.8),
		Color(0.4, 0.28, 0.15, 0.0), 20, 0.5, 80.0, 220.0, 1.5, 4.0)
	ScorchDecal.spawn(get_parent(), _floor_base, WALL_SIZE.x * 0.7, "crack",
		Color(0.5, 0.36, 0.22, 0.5), 6.0)
	Juice.shake_camera(7.0)
	Sfx.play("earth", -4.0, 0.08)
	queue_redraw()


## Pure geometry (testable): where the wall lands relative to the caster + aim.
static func wall_center(from: Vector2, aim: Vector2, offset: float = WALL_OFFSET) -> Vector2:
	var d: Vector2 = aim.normalized()
	if d == Vector2.ZERO:
		d = Vector2.RIGHT
	return from + d * offset


## Nearest standing shoveable wall within `max_dist` px of `pos`, or null.
## Cheap helper for the punch hook: one group scan, footprint-distance check.
static func find_shoveable_near(tree: SceneTree, pos: Vector2, max_dist: float = 140.0) -> Node2D:
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = max_dist
	for w: Node in tree.get_nodes_in_group("shoveable"):
		if not is_instance_valid(w) or not w.has_method("wall_distance"):
			continue
		var d: float = w.call("wall_distance", pos)
		if d <= best_d:
			best_d = d
			best = w as Node2D
	return best


## Where this wall actually STANDS right now. The node itself sits at the arena
## origin and everything is drawn in world coordinates, so `global_position` is
## not the wall — callers deciding "is it to my left or my right" must ask for
## this. Distinct from the static wall_center() above, which PREDICTS where a
## wall would land for a given caster + aim before one exists.
func footprint_center() -> Vector2:
	return _floor_base - Vector2(0.0, WALL_SIZE.y * 0.5)


## Distance from `pos` to this wall's blocking footprint (0 when touching it).
func wall_distance(pos: Vector2) -> float:
	var hw: float = WALL_SIZE.x * 0.5
	var nearest := Vector2(
		clampf(pos.x, _floor_base.x - hw, _floor_base.x + hw),
		clampf(pos.y, _floor_base.y - WALL_SIZE.y, _floor_base.y),
	)
	return pos.distance_to(nearest)


## THE MAKER'S PUSH MECHANIC: punch the wall and it SLIDES across the arena as a
## grinding mass — plows enemies (damage + heavy knockback), smashes destructible
## crates, stops with a slam on real world geometry, despawns off-map. Horizontal
## only (walls grind along the ground; the punch's y is ignored so a downward
## swing still shoves sideways). Returns false when there is nothing to shove.
func shove(dir: Vector2, speed: float = SHOVE_SPEED) -> bool:
	if _elapsed < 0.0 or _crumbling or _sliding:
		return false
	var sx: float = signf(dir.x)
	if sx == 0.0:
		sx = 1.0
	_slide_dir = Vector2(sx, 0.0)
	_slide_speed = maxf(speed, 100.0)
	_sliding = true
	_elapsed = maxf(_elapsed, RISE_TIME)  # a mid-rise shove snaps the wall solid first
	for i in SLABS:
		_slab_locked[i] = true
	# The send-off: dust kicks out BEHIND the wall + a real screen hit, so the
	# first frame of the slide already reads heavy.
	CombatVfx.spawn_burst(get_parent(), _floor_base - _slide_dir * WALL_SIZE.x * 0.6,
		Color(0.8, 0.62, 0.4, 0.85), Color(0.4, 0.28, 0.15, 0.0),
		18, 0.45, 90.0, 240.0, 1.6, 4.0, 0.0, 0.0, false, -_slide_dir, 55.0)
	DebrisChunk.spawn_burst(get_parent(), _floor_base, Color(0.5, 0.38, 0.22), 4, Vector2.UP, 180.0)
	Juice.on_hit({"dir": _slide_dir, "shake": 9.0, "kick": 7.0,
		"sfx": "earth", "sfx_pitch": 0.06, "hitstop": 0.04})
	queue_redraw()
	return true


func _floor_below(from: Vector2, max_dist: float) -> Dictionary:
	var world: World2D = get_world_2d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, max_dist), 1)
	return world.direct_space_state.intersect_ray(query)


## Build the slab silhouette ONCE at raise: a few BIG irregular slabs, widest at
## the bottom, chipped edges, slight overlap — reads as stacked dumb mass where
## the ice wall reads as a grown crystal cluster.
func _build_slabs() -> void:
	var height_fracs: Array = [0.30, 0.27, 0.24, 0.19]
	var width_mults: Array = [1.3, 1.12, 0.98, 0.82]
	var cum: float = 0.0
	for i in SLABS:
		var h: float = WALL_SIZE.y * float(height_fracs[i]) * randf_range(0.92, 1.08)
		var w: float = WALL_SIZE.x * float(width_mults[i]) * 0.5 * randf_range(0.9, 1.08)
		var ox: float = randf_range(-5.0, 5.0)
		var y_bot: float = -cum
		var y_top: float = y_bot - h
		# Irregular chipped heptagon: side bulges + a bumpy top ridge.
		var poly := PackedVector2Array([
			Vector2(ox - w, y_bot),
			Vector2(ox - w - randf_range(2.0, 7.0), lerpf(y_bot, y_top, randf_range(0.3, 0.5))),
			Vector2(ox - w * 0.88 + randf_range(-3.0, 3.0), y_top + randf_range(0.0, 4.0)),
			Vector2(ox + randf_range(-7.0, 7.0), y_top - randf_range(1.0, 6.0)),
			Vector2(ox + w * 0.9 + randf_range(-3.0, 3.0), y_top + randf_range(0.0, 4.0)),
			Vector2(ox + w + randf_range(2.0, 7.0), lerpf(y_bot, y_top, randf_range(0.45, 0.65))),
			Vector2(ox + w * 0.95, y_bot),
		])
		_slab_polys.append(poly)
		_slab_base_y.append(y_bot)
		_slab_delay.append(float(i) * SLAB_STAGGER)
		_slab_locked.append(false)
		cum += h * 0.94  # slight overlap: slabs sit pressed into each other
	_stack_h = cum


## Ease-out-back: overshoots ~10% then settles — the "slab pops past its seat
## and slams down into place" read that makes the rise feel slam-driven.
func _rise_ease(u: float) -> float:
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	var t: float = u - 1.0
	return 1.0 + c3 * t * t * t + c1 * t * t


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _sliding and not _crumbling:
		_process_slide(delta)
		if _elapsed < 0.0:  # despawned mid-slide (off-map)
			return
	elif not _crumbling:
		_process_rise_locks()
		if _elapsed >= RISE_TIME + LIFETIME:
			_begin_crumble()
	if _crumbling and _elapsed >= RISE_TIME + LIFETIME + CRUMBLE_TIME:
		queue_free()
		return
	queue_redraw()


## Per-slab "lock" beat: when a slab finishes its pop it lands with a puff + a
## small shake, so the whole raise reads as four quick impacts, not one tween.
func _process_rise_locks() -> void:
	if _elapsed > RISE_TIME + SLAB_RISE:
		return
	for i in SLABS:
		if _slab_locked[i]:
			continue
		if _elapsed >= _slab_delay[i] + SLAB_RISE:
			_slab_locked[i] = true
			var base_world := _floor_base + Vector2(0.0, _slab_base_y[i])
			CombatVfx.spawn_burst(get_parent(), base_world, Color(0.8, 0.6, 0.38, 0.7),
				Color(0.4, 0.28, 0.15, 0.0), 6, 0.3, 50.0, 140.0, 1.2, 2.8)
			Juice.shake_camera(2.5)


func _begin_crumble() -> void:
	_crumbling = true
	_sliding = false
	remove_from_group("shoveable")
	if _collider != null:
		_collider.set_deferred("disabled", true)  # stops blocking once it crumbles
	DebrisChunk.spawn_burst(get_parent(), _floor_base - Vector2(0.0, WALL_SIZE.y * 0.5),
		Color(0.5, 0.38, 0.22), DEBRIS_COUNT, Vector2.DOWN, 200.0)
	ScorchDecal.spawn(get_parent(), _floor_base, WALL_SIZE.x * 0.9, "crack",
		Color(0.6, 0.45, 0.28, 0.55), 6.0)
	Juice.shake_camera(5.0)
	Sfx.play("enemy_death", -2.0, 0.1)


# ---- the slide (shoved wall as a projectile) ----

func _process_slide(delta: float) -> void:
	var prev_front_x: float = _front_edge_x()
	var step: Vector2 = _slide_dir * _slide_speed * delta
	_floor_base += step
	_slide_traveled += step.length()
	if _body != null:
		_body.global_position = _floor_base
	_plow_enemies()
	_smash_props()
	_grind_t -= delta
	if _grind_t <= 0.0:
		_grind_t = GRIND_DUST_INTERVAL
		# Grinding dust boils up off the trailing base edge the whole slide.
		CombatVfx.spawn_burst(get_parent(),
			_floor_base - _slide_dir * WALL_SIZE.x * 0.55 + Vector2(0.0, randf_range(-8.0, 0.0)),
			Color(0.75, 0.58, 0.38, 0.7), Color(0.4, 0.28, 0.15, 0.0),
			5, 0.35, 40.0, 120.0, 1.4, 3.2, 0.0, 0.0, false, -_slide_dir + Vector2.UP * 0.6, 40.0)
	if _hit_world(prev_front_x):
		_slam_stop()
	elif _slide_traveled >= MAX_SLIDE:
		# Nothing stopped it — the wall grinds off the map and is gone.
		CombatVfx.spawn_burst(get_parent(), _floor_base, DUST_TINT,
			Color(0.4, 0.28, 0.15, 0.0), 10, 0.4, 50.0, 140.0, 1.5, 3.5)
		_elapsed = -1.0
		queue_free()


func _front_edge_x() -> float:
	return _floor_base.x + _slide_dir.x * WALL_SIZE.x * 0.5


## Solid world geometry across the travelled front edge (3 heights, layer 1).
## Destructible crates are NOT solid to a shoved wall — _smash_props plows them —
## so the ray skips anything in the "destructible" group.
func _hit_world(prev_front_x: float) -> bool:
	var world: World2D = get_world_2d()
	if world == null:
		return false
	var front_x: float = _front_edge_x() + _slide_dir.x * 6.0
	var excludes: Array[RID] = []
	if _body != null:
		excludes.append(_body.get_rid())
	for hy: float in [14.0, WALL_SIZE.y * 0.5, WALL_SIZE.y - 16.0]:
		var y: float = _floor_base.y - hy
		var q := PhysicsRayQueryParameters2D.create(
			Vector2(prev_front_x, y), Vector2(front_x, y), 1)
		q.exclude = excludes
		q.hit_from_inside = true
		var hit: Dictionary = world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Node = hit.get("collider") as Node
		if n != null and _is_smashable(n):
			continue  # smashed through, not stopped
		return true
	return false


## True for anything a shoved wall grinds THROUGH rather than stops against.
## Group membership alone is not enough: `_smash_props()` runs earlier in the
## same frame, and a cover block that just collapsed leaves the "destructible"
## group immediately while its collider lives until the deferred free — so the
## ray would see a group-less solid body and slam the wall to a halt on the very
## crate it just broke. Anything already queued for deletion is smashed, gone.
func _is_smashable(n: Node) -> bool:
	return n.is_in_group("destructible") or n.is_queued_for_deletion()


## Anything caught in the wall's path gets plowed ONCE: real damage + a heavy
## up-and-out launch. One hit per enemy per slide (no per-frame damage ticks).
func _plow_enemies() -> void:
	var hw: float = WALL_SIZE.x * 0.5 + PLOW_PAD
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not e is Node2D or not is_instance_valid(e):
			continue
		var p: Vector2 = (e as Node2D).global_position
		if absf(p.x - _floor_base.x) > hw:
			continue
		if p.y > _floor_base.y + 14.0 or p.y < _floor_base.y - WALL_SIZE.y - 14.0:
			continue
		var id: int = e.get_instance_id()
		if _plowed.has(id):
			continue
		_plowed[id] = true
		if e.has_method("take_damage"):
			e.take_damage(SHOVE_DAMAGE)
		if element_id >= 0 and e.has_method("apply_status"):
			e.apply_status(element_id)
		if e.has_method("apply_knockback"):
			e.apply_knockback((_slide_dir + Vector2.UP * 0.4).normalized() * SHOVE_KNOCKBACK)
		CombatVfx.spawn_burst(get_parent(), p, Color(0.9, 0.7, 0.45, 0.9),
			Color(0.45, 0.3, 0.16, 0.0), 12, 0.35, 80.0, 220.0, 1.3, 3.0,
			0.0, 0.0, false, _slide_dir, 60.0)
		Juice.on_hit({"dir": _slide_dir, "shake": 8.0, "kick": 5.0,
			"sfx": "melee_hit", "sfx_pitch": 0.08, "hitstop": 0.05})


## Crates and props in the path get smashed; enemy bolts get eaten by the mass.
func _smash_props() -> void:
	var hw: float = WALL_SIZE.x * 0.5 + PLOW_PAD
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if not prop is Node2D or not is_instance_valid(prop):
			continue
		var p: Vector2 = (prop as Node2D).global_position
		if absf(p.x - _floor_base.x) > hw + 20.0 or absf(p.y - _floor_base.y) > WALL_SIZE.y:
			continue
		if prop.has_method("damage_at"):
			prop.damage_at(SHOVE_DAMAGE * 2, p, _slide_dir)
		elif prop.has_method("take_damage"):
			prop.take_damage(SHOVE_DAMAGE * 2)
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if proj is Node2D and wall_distance((proj as Node2D).global_position) <= PLOW_PAD \
				and proj.has_method("consume"):
			proj.call("consume")


## The slide ends against real geometry: one HEAVY beat (shake + kick + hitstop
## + blast), a debris spray up the obstacle, and the wall immediately crumbles —
## a thrown wall is spent, it doesn't go back to being a barrier.
func _slam_stop() -> void:
	_sliding = false
	var front := Vector2(_front_edge_x(), _floor_base.y - WALL_SIZE.y * 0.4)
	DebrisChunk.spawn_burst(get_parent(), front, Color(0.5, 0.38, 0.22), 12,
		-_slide_dir + Vector2.UP * 0.8, 300.0)
	CombatVfx.spawn_burst(get_parent(), front, Color(0.95, 0.75, 0.5, 0.9),
		Color(0.45, 0.3, 0.16, 0.0), 24, 0.5, 90.0, 260.0, 1.6, 4.2)
	ScorchDecal.spawn(get_parent(), Vector2(front.x, _floor_base.y), WALL_SIZE.x * 0.8,
		"crack", Color(0.55, 0.4, 0.25, 0.6), 7.0)
	Juice.on_hit({"dir": _slide_dir, "shake": 13.0, "kick": 10.0, "zoom": 0.1,
		"sfx": "blast", "sfx_pitch": 0.1, "hitstop": 0.09})
	_elapsed = RISE_TIME + LIFETIME  # jump straight onto the crumble timeline
	_begin_crumble()


# ---- drawing ----

func _draw() -> void:
	if _elapsed < 0.0:
		return
	var alpha: float = 1.0
	if _crumbling:
		alpha = clampf(1.0 - (_elapsed - RISE_TIME - LIFETIME) / CRUMBLE_TIME, 0.0, 1.0)
	# Slam vibration while erupting: the whole stack judders, decaying to zero.
	var rise_u: float = clampf(_elapsed / RISE_TIME, 0.0, 1.0)
	var judder: float = (1.0 - rise_u) * 2.4
	var shake_off := Vector2(sin(_elapsed * 80.0) * judder, 0.0)
	# Sliding lean: the top of the stack trails the motion — mass reads in the tilt.
	var lean_px: float = -_slide_dir.x * 9.0 if _sliding else 0.0
	var top_slab: int = -1
	for i in SLABS:
		var u: float = clampf((_elapsed - _slab_delay[i]) / SLAB_RISE, 0.0, 1.0)
		if u <= 0.02:
			break
		top_slab = i
		var s: float = _rise_ease(u)
		var base_y: float = _slab_base_y[i]
		var poly: PackedVector2Array = _slab_polys[i]
		var pts := PackedVector2Array()
		for v in poly:
			var y: float = base_y + (v.y - base_y) * s
			var lean: float = lean_px * clampf(-y / maxf(_stack_h, 1.0), 0.0, 1.0)
			pts.append(_floor_base + shake_off + Vector2(v.x + lean, y))
		draw_colored_polygon(pts, Color(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b, alpha))
		# Lit face wedge (upper-left half catches the light) — gives each slab volume.
		var face := PackedVector2Array([pts[0], pts[1], pts[2], pts[3]])
		draw_colored_polygon(face, Color(FACE_COLOR.r, FACE_COLOR.g, FACE_COLOR.b, 0.85 * alpha))
		# Dark seams around the whole slab: chunky stacked-block read.
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(SEAM_COLOR.r, SEAM_COLOR.g, SEAM_COLOR.b, alpha), 2.2, true)
		# Top ridge catches light hard.
		draw_line(pts[2], pts[3], Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, alpha), 3.2, true)
		draw_line(pts[3], pts[4], Color(LIT_COLOR.r, LIT_COLOR.g, LIT_COLOR.b, alpha), 3.2, true)
	# HDR amber rim on the crown — the "you can interact with this" cue
	# (echoes BreakablePlatform; here it marks the wall as shoveable).
	if top_slab >= 0:
		var crown: PackedVector2Array = _slab_polys[top_slab]
		var cb: float = _slab_base_y[top_slab]
		var cu: float = clampf((_elapsed - _slab_delay[top_slab]) / SLAB_RISE, 0.0, 1.0)
		var cs: float = _rise_ease(cu)
		var a := _floor_base + shake_off + Vector2(crown[2].x + lean_px, cb + (crown[2].y - cb) * cs)
		var b := _floor_base + shake_off + Vector2(crown[4].x + lean_px, cb + (crown[4].y - cb) * cs)
		draw_line(a, b, Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, alpha * 0.9), 2.0, true)
		draw_line(a, (a + b) * 0.5, Color(AMBER_RIM.r, AMBER_RIM.g, AMBER_RIM.b, alpha * 0.8), 3.4, true)
	# Dust skirt at the base; while sliding it smears out behind the wall.
	draw_circle(_floor_base + shake_off, WALL_SIZE.x * 0.8,
		Color(0.55, 0.42, 0.28, 0.35 * alpha), true, -1.0, true)
	if _sliding:
		for k in 3:
			var trail := _floor_base - _slide_dir * WALL_SIZE.x * (0.7 + 0.55 * float(k))
			draw_circle(trail + Vector2(0.0, -4.0 - 3.0 * float(k)),
				WALL_SIZE.x * (0.5 - 0.1 * float(k)),
				Color(0.6, 0.46, 0.3, (0.3 - 0.08 * float(k)) * alpha), true, -1.0, true)
