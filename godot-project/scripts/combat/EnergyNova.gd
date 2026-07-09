class_name EnergyNova
extends Node2D
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
const CRACK_RADIUS_FACTOR: float = 0.35
const CRACK_TINT: Color = Color(0.3, 0.4, 0.5, 0.45)

var _shockwave_elapsed: float = -1.0  # < 0 means not yet fired.


## Public entry: place the nova on the caster and fire IMMEDIATELY.
func activate_at(pos: Vector2) -> void:
	global_position = pos
	_apply_nova_damage()
	_spawn_nova_burst()
	# Cracked floor under the burst point — cool-tinted, unlike blast scorch.
	ScorchDecal.spawn(
		get_parent(), global_position,
		NOVA_RADIUS * CRACK_RADIUS_FACTOR, "crack", CRACK_TINT
	)
	_shockwave_elapsed = 0.0
	queue_redraw()
	Juice.hit_stop(0.1)
	Juice.shake_camera(14.0)
	Juice.zoom_punch_camera(0.12, 0.22)
	Sfx.play("blast", 2.0, 0.1)
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


## Radius-query damage + OUTWARD knockback. Split out so headless tests can
## exercise the geometry without driving the VFX/juice side effects.
func _apply_nova_damage() -> void:
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Node2D:
			continue
		if global_position.distance_to(enemy.global_position) > NOVA_RADIUS:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(NOVA_DAMAGE)
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
		if prop.has_method("take_damage"):
			prop.take_damage(NOVA_DAMAGE)


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
	)
	draw_arc(
		Vector2.ZERO, r * 0.8, 0.0, TAU, 48,
		Color(0.85, 0.95, 1.0, 0.6 * alpha), lerpf(7.0, 1.0, t)
	)
	# Hot white-blue flash core right at the burst.
	if t < 0.4:
		var flash: float = 1.0 - t / 0.4
		draw_circle(
			Vector2.ZERO, NOVA_RADIUS * 0.9 * flash,
			Color(0.85, 0.95, 1.0, 0.35 * flash)
		)


## The shared burst builder, tuned for a big bright energy ring-out.
func _spawn_nova_burst() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position,
		Color(0.75, 0.95, 1.0, 1.0), Color(0.25, 0.55, 1.0, 0.0),
		110, 0.55, 220.0, 520.0, 2.0, 6.0, 80.0, 160.0
	)
