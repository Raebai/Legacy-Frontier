class_name EnergyNova
extends Node2D

## Who this nova's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## Self-centered ENERGY NOVA: the "get off me" panic button. An instant
## screen-push shockwave that bursts out FROM THE HERO — no telegraph, no
## windup (contrast: BlastSpell's targeted danger-bloom). Damage is a pure
## radius query on the "enemy" + "destructible" groups, mirroring BlastSpell's
## detonation but centered on the caster with harder outward knockback.
## Spectacle: big cyan-white energy burst + expanding shockwave ring + heavy
## juice. Cool energy palette so it reads distinctly from the warm blast.

const NOVA_RADIUS: float = 135.0
const NOVA_DAMAGE: int = 30
const NOVA_KNOCKBACK: float = 420.0
const SHOCKWAVE_TIME: float = 0.32
const CLEANUP_DELAY: float = 0.7
## Faint floor cracks under the caster: the shockwave visibly stresses the arena.
## Snapped down onto the actual floor (never the sky) + fades so it clears up.
const CRACK_RADIUS_FACTOR: float = 0.35
const CRACK_TINT: Color = Color(0.3, 0.4, 0.5, 0.45)
const CRACK_LIFETIME: float = 5.0  # seconds before the crack fades away
const DEBRIS_COUNT: int = 8
const DEBRIS_COLOR: Color = Color(0.45, 0.55, 0.62)  # cool shattered stone

var _shockwave_elapsed: float = -1.0  # < 0 means not yet fired.
## Element index (Elements.Element) applied as an ailment to enemies in radius.
var element_id: int = -1


## Public entry: place the nova on the caster and fire IMMEDIATELY.
func activate_at(pos: Vector2) -> void:
	global_position = pos
	_apply_nova_damage()
	_spawn_nova_burst()
	# Crack the FLOOR beneath the caster only — NEVER the sky (the maker's ask).
	# Airborne over a pit -> no crack, no debris; just the energy ring rings out.
	var hit: Dictionary = _floor_below(global_position, NOVA_RADIUS)
	if not hit.is_empty():
		var floor_pos: Vector2 = hit["position"]
		ScorchDecal.spawn(
			get_parent(), floor_pos,
			NOVA_RADIUS * CRACK_RADIUS_FACTOR, "crack", CRACK_TINT, CRACK_LIFETIME
		)
		DebrisChunk.spawn_burst(
			get_parent(), floor_pos, DEBRIS_COLOR, DEBRIS_COUNT, Vector2.UP, 240.0
		)
		GroundCrater.spawn(get_parent(), floor_pos, NOVA_RADIUS * 0.35, false)  # persistent gouge
	_shockwave_elapsed = 0.0
	queue_redraw()
	Juice.hit_stop(0.1)
	Juice.shake_camera(14.0)
	Juice.zoom_punch_camera(0.12, 0.22)
	PostProcess.shock(0.6)  # the nova blast rings the screen outward
	Sfx.play("nova", 1.0, 0.08)
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


## Downward raycast to the floor/platform (collision layer 1) within `max_dist`.
## Returns the intersect_ray dict ({} if nothing below — airborne over a pit) so
## the crack + debris land ON the ground, never mid-air ("no cracking the sky").
func _floor_below(from: Vector2, max_dist: float) -> Dictionary:
	var world: World2D = get_world_2d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, max_dist), 1)
	return world.direct_space_state.intersect_ray(query)


## Radius-query damage + OUTWARD knockback. Split out so headless tests can
## exercise the geometry without driving the VFX/juice side effects.
func _apply_nova_damage() -> void:
	for enemy: Node in get_tree().get_nodes_in_group(target_group):
		if not enemy is Node2D:
			continue
		if global_position.distance_to(enemy.global_position) > NOVA_RADIUS:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(NOVA_DAMAGE)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = (enemy.global_position - global_position).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			enemy.apply_knockback(away * NOVA_KNOCKBACK)
	# Crates around the caster shatter too (no knockback — they're static).
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if not prop is Node2D:
			continue
		if global_position.distance_to(prop.global_position) > NOVA_RADIUS:
			continue
		# Blow parts off outward from the nova centre (falls back to take_damage).
		if prop.has_method("damage_at"):
			var out: Vector2 = ((prop as Node2D).global_position - global_position).normalized()
			prop.damage_at(NOVA_DAMAGE, (prop as Node2D).global_position, out if out != Vector2.ZERO else Vector2.UP)
		elif prop.has_method("take_damage"):
			prop.take_damage(NOVA_DAMAGE)
	# Enemy bolts caught in the nova are cleared from the air (spell-vs-spell).
	for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
		if proj is Node2D and global_position.distance_to((proj as Node2D).global_position) <= NOVA_RADIUS \
				and proj.has_method("consume"):
			proj.call("consume")


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
	# Expanding energy ring: brighter and reaches further than the blast's.
	var r: float = lerpf(10.0, NOVA_RADIUS * 1.3, t)
	var alpha: float = 1.0 - t
	draw_arc(
		Vector2.ZERO, r, 0.0, TAU, 64,
		Color(0.6, 0.9, 1.0, 0.95 * alpha), lerpf(12.0, 2.0, t)
	, true)
	draw_arc(
		Vector2.ZERO, r * 0.8, 0.0, TAU, 48,
		Color(0.85, 0.95, 1.0, 0.6 * alpha), lerpf(7.0, 1.0, t)
	, true)
	# Hot white-blue flash core right at the burst.
	if t < 0.4:
		var flash: float = 1.0 - t / 0.4
		draw_circle(
			Vector2.ZERO, NOVA_RADIUS * 0.9 * flash,
			Color(1.4, 1.6, 1.9, 0.35 * flash)
		, true, -1.0, true)


## The shared burst builder, tuned for a big bright energy ring-out.
func _spawn_nova_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(0.75, 0.95, 1.0, 1.0), Color(0.25, 0.55, 1.0, 0.0),
		110, 0.55, 220.0, 520.0, 2.0, 6.0, 80.0, 160.0, true
	)
