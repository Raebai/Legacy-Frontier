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
	_shockwave_elapsed = 0.0
	queue_redraw()
	Juice.hit_stop(0.09)
	Juice.shake_camera(12.0)
	Sfx.play("blast")
	get_tree().create_timer(CLEANUP_DELAY).timeout.connect(queue_free)


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


## Mirrors Spell._spawn_impact_burst, scaled way up for the centerpiece.
func _spawn_blast_burst() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var burst := GPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 90
	burst.lifetime = 0.6
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.spread = 180.0
	mat.initial_velocity_min = 160.0
	mat.initial_velocity_max = 420.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 60.0
	mat.damping_max = 140.0
	mat.scale_min = 2.0
	mat.scale_max = 6.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.45, 1.0))
	ramp.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	burst.process_material = mat
	parent.add_child(burst)
	burst.global_position = global_position
	burst.restart()
	burst.emitting = true
	get_tree().create_timer(0.9).timeout.connect(burst.queue_free)
