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
## Element index (Elements.Element) applied as an ailment to enemies in radius.
var element_id: int = -1
## Configurable so the SAME spell serves the hero's giant blast AND an enemy
## MAGE's AoE aimed at the hero. Defaults reproduce the hero blast exactly.
var target_group: String = "enemy"   # who the radius query hurts
var damage: int = DAMAGE
var radius: float = BLAST_RADIUS
var knockback: float = KNOCKBACK
var windup: float = WINDUP


## Reconfigure before detonating (enemy MAGE aims it at group "hero", smaller
## radius, own element). Unspecified keys keep the hero-blast defaults.
func configure(opts: Dictionary) -> void:
	target_group = String(opts.get("target_group", target_group))
	damage = int(opts.get("damage", damage))
	radius = float(opts.get("radius", radius))
	knockback = float(opts.get("knockback", knockback))
	windup = float(opts.get("windup", windup))
	element_id = int(opts.get("element_id", element_id))


## Public entry: place the blast, start the danger bloom over the windup.
func detonate_at(pos: Vector2) -> void:
	global_position = pos
	var telegraph := Telegraph.new()
	add_child(telegraph)
	telegraph.fired.connect(_detonate)
	telegraph.start(radius, windup)


## Detonate immediately at `pos` (no windup) — used when the caller already ran
## its own telegraph (the enemy MAGE's Enemy-side tell) or for tests.
func detonate_now(pos: Vector2) -> void:
	global_position = pos
	_detonate()


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
	# ...then pull the frame back to reveal the whole detonation (the "show the big
	# spell" beat) — a gentle widen that holds through the shockwave and eases home.
	Juice.zoom_pull_camera(0.14, 0.35, 0.14, 0.5)
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


## Radius-query damage + outward knockback against `target_group`. Split out so
## headless tests can exercise the geometry without driving the Telegraph timing.
func _apply_blast_damage() -> void:
	for victim: Node in get_tree().get_nodes_in_group(target_group):
		if not victim is Node2D:
			continue
		if global_position.distance_to(victim.global_position) > radius:
			continue
		if victim.has_method("take_damage"):
			victim.take_damage(damage)
		if element_id >= 0 and victim.has_method("apply_status"):
			victim.apply_status(element_id)
		if victim.has_method("apply_knockback"):
			var away: Vector2 = (victim.global_position - global_position).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			victim.apply_knockback(away * knockback)
	# Crates in the blast radius shatter too (no knockback — they're static). An
	# enemy MAGE's blast can crack cover as well, so this isn't hero-gated.
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if not prop is Node2D:
			continue
		if global_position.distance_to(prop.global_position) > radius:
			continue
		# Blow parts off outward from the blast centre (falls back to take_damage).
		if prop.has_method("damage_at"):
			var out: Vector2 = ((prop as Node2D).global_position - global_position).normalized()
			prop.damage_at(damage, (prop as Node2D).global_position, out if out != Vector2.ZERO else Vector2.UP)
		elif prop.has_method("take_damage"):
			prop.take_damage(damage)
	# Only the HERO's blast clears enemy bolts from the air (spell-vs-spell); an
	# enemy blast must never eat its own team's projectiles.
	if target_group == "enemy":
		for proj: Node in get_tree().get_nodes_in_group("enemy_projectile"):
			if proj is Node2D and global_position.distance_to((proj as Node2D).global_position) <= radius \
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
	# Expanding shockwave ring: races out past the blast radius and fades.
	var r: float = lerpf(8.0, BLAST_RADIUS * 1.35, t)
	var alpha: float = 1.0 - t
	draw_arc(
		Vector2.ZERO, r, 0.0, TAU, 64,
		Color(1.0, 0.85, 0.5, 0.9 * alpha), lerpf(10.0, 2.0, t)
	, true)
	draw_arc(
		Vector2.ZERO, r * 0.78, 0.0, TAU, 48,
		Color(1.0, 0.5, 0.2, 0.5 * alpha), lerpf(6.0, 1.0, t)
	, true)
	# Hot flash core right after detonation.
	if t < 0.4:
		var flash: float = 1.0 - t / 0.4
		draw_circle(Vector2.ZERO, BLAST_RADIUS * flash, Color(1.7, 1.45, 0.9, 0.35 * flash), true, -1.0, true)


## The shared burst builder, scaled way up for the centerpiece.
func _spawn_blast_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(1.0, 0.9, 0.45, 1.0), Color(1.0, 0.4, 0.1, 0.0),
		90, 0.6, 160.0, 420.0, 2.0, 6.0, 60.0, 140.0, true
	)
