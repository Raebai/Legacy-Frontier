class_name BlastSpell
extends Node2D
## The GIANT blast: telegraph blooms over a windup, then a huge AoE detonation.
## Damage is a pure radius query on the "enemy" group — no Area2D needed.
## Spectacle: big particle burst + expanding shockwave ring + heavy juice.

const BLAST_RADIUS: float = 92.0
const WINDUP: float = 0.55
const DAMAGE: int = 40
const KNOCKBACK: float = 340.0
const SHOCKWAVE_TIME: float = 0.25
const CLEANUP_DELAY: float = 0.7
# Every blast chars the floor beneath it: a scorch decal snapped down onto the
# ground (never a mid-air smear) that fades + clears after SCORCH_LIFETIME.
const SCORCH_RADIUS_FACTOR: float = 0.8  # decal size relative to BLAST_RADIUS
const SCORCH_TINT: Color = Color(0.09, 0.05, 0.03, 0.6)  # warm charred brown
const SCORCH_LIFETIME: float = 7.0  # seconds before the crater fades away
const DEBRIS_COUNT: int = 12  # rock/ember chunks blown up out of the crater
const DEBRIS_COLOR: Color = Color(0.36, 0.3, 0.26)  # charred stone

var _shockwave_elapsed: float = -1.0  # < 0 means not yet detonated.


## Public entry: place the blast, start the danger bloom.
func detonate_at(pos: Vector2) -> void:
	global_position = pos
	var telegraph := Telegraph.new()
	add_child(telegraph)
	telegraph.fired.connect(_detonate)
	telegraph.start(BLAST_RADIUS, WINDUP)


func _detonate() -> void:
	_apply_blast_damage()
	_spawn_blast_burst()
	# Crater mark + physics debris, snapped to the FLOOR below the blast (never a
	# mid-air smear) and given a lifetime so it clears up. Skipped over a pit.
	var hit: Dictionary = _floor_below(global_position, BLAST_RADIUS * 2.2)
	if not hit.is_empty():
		var floor_pos: Vector2 = hit["position"]
		ScorchDecal.spawn(
			get_parent(), floor_pos,
			BLAST_RADIUS * SCORCH_RADIUS_FACTOR, "scorch", SCORCH_TINT, SCORCH_LIFETIME
		)
		DebrisChunk.spawn_burst(
			get_parent(), floor_pos, DEBRIS_COLOR, DEBRIS_COUNT, Vector2.UP, 300.0
		)
	_shockwave_elapsed = 0.0
	queue_redraw()
	Juice.hit_stop(0.09)  # weighted: the AoE centerpiece, just under a kill
	Juice.shake_camera(12.0)
	Juice.zoom_punch_camera(0.1, 0.2)  # punch-zoom: the camera lunges in and eases back
	Sfx.play("blast")
	# Duck the music bed so the blast SFX owns the mix for a beat.
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("duck"):
		music.call("duck", 8.0, 0.4)
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


## Downward raycast to the nearest floor/platform (collision layer 1) within
## `max_dist`. Returns the intersect_ray dict ({} if nothing below — e.g. over a
## pit) so callers place scorch + debris ON the ground, never in the sky.
func _floor_below(from: Vector2, max_dist: float) -> Dictionary:
	var world: World2D = get_world_2d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, max_dist), 1)
	return world.direct_space_state.intersect_ray(query)


## Radius-query damage + outward knockback. Split out so headless tests can
## exercise the geometry without driving the Telegraph timing.
func _apply_blast_damage() -> void:
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Node2D:
			continue
		if global_position.distance_to(enemy.global_position) > BLAST_RADIUS:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(DAMAGE)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = (enemy.global_position - global_position).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			enemy.apply_knockback(away * KNOCKBACK)
	# Crates in the blast radius shatter too (no knockback — they're static).
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if not prop is Node2D:
			continue
		if global_position.distance_to(prop.global_position) > BLAST_RADIUS:
			continue
		if prop.has_method("take_damage"):
			prop.take_damage(DAMAGE)


func _process(delta: float) -> void:
	if _shockwave_elapsed < 0.0:
		return
	_shockwave_elapsed += delta
	queue_redraw()


func _draw() -> void:
	if _shockwave_elapsed < 0.0:
		return
	var t: float = clampf(_shockwave_elapsed / SHOCKWAVE_TIME, 0.0, 1.0)
	if t >= 1.0:
		return
	# Expanding shockwave ring: races out past the blast radius and fades.
	var r: float = lerpf(8.0, BLAST_RADIUS * 1.35, t)
	var alpha: float = 1.0 - t
	draw_arc(
		Vector2.ZERO, r, 0.0, TAU, 64,
		Color(1.0, 0.85, 0.5, 0.9 * alpha), lerpf(10.0, 2.0, t)
	)
	draw_arc(
		Vector2.ZERO, r * 0.78, 0.0, TAU, 48,
		Color(1.0, 0.5, 0.2, 0.5 * alpha), lerpf(6.0, 1.0, t)
	)
	# Hot flash core right after detonation.
	if t < 0.4:
		var flash: float = 1.0 - t / 0.4
		draw_circle(Vector2.ZERO, BLAST_RADIUS * flash, Color(1.0, 0.9, 0.6, 0.35 * flash))


## The shared burst builder, scaled way up for the centerpiece.
func _spawn_blast_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(1.0, 0.9, 0.45, 1.0), Color(1.0, 0.4, 0.1, 0.0),
		90, 0.6, 160.0, 420.0, 2.0, 6.0, 60.0, 140.0
	)
