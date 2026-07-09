class_name CombatVfx
extends RefCounted
## Shared one-shot particle helpers. Factored from Spell._spawn_impact_burst /
## BlastSpell._spawn_blast_burst so spell hits, blasts and enemy deaths all
## share one radial-burst builder with per-call-site tuning.


## Spawn a self-freeing radial GPUParticles2D burst under `parent` at `pos`.
## Particle color ramps from `color_start` to `color_end` (end alpha should
## be 0 so the burst fades out instead of popping off).
static func spawn_burst(
	parent: Node,
	pos: Vector2,
	color_start: Color,
	color_end: Color,
	amount: int = 20,
	lifetime: float = 0.4,
	velocity_min: float = 60.0,
	velocity_max: float = 130.0,
	scale_min: float = 1.0,
	scale_max: float = 3.0,
	damping_min: float = 0.0,
	damping_max: float = 0.0,
) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var burst := GPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = amount
	burst.lifetime = lifetime
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.spread = 180.0
	mat.initial_velocity_min = velocity_min
	mat.initial_velocity_max = velocity_max
	mat.gravity = Vector3.ZERO
	mat.damping_min = damping_min
	mat.damping_max = damping_max
	mat.scale_min = scale_min
	mat.scale_max = scale_max
	var ramp := Gradient.new()
	ramp.set_color(0, color_start)
	ramp.set_color(1, color_end)
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	burst.process_material = mat
	parent.add_child(burst)
	burst.global_position = pos
	burst.restart()
	burst.emitting = true
	parent.get_tree().create_timer(lifetime + 0.3).timeout.connect(burst.queue_free)
