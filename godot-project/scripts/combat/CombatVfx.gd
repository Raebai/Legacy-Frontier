class_name CombatVfx
extends RefCounted
## Shared one-shot particle helpers. Factored from Spell._spawn_impact_burst /
## BlastSpell._spawn_blast_burst so spell hits, blasts and enemy deaths all
## share one radial-burst builder with per-call-site tuning.


## Cached soft round-dot texture so particles render as glowing dots, NOT hard
## 1px squares (the untextured default was the whole game's "blocky confetti"
## look). Built once, shared by every burst.
const DOT_SIZE: float = 16.0
## Compensate the caller's scale so a textured dot ends up ~2.4x the old square
## size (soft + a touch bigger reads as glow, not grit): mat.scale = s * FACTOR.
const SCALE_FACTOR: float = 0.15
static var _dot_tex: Texture2D = null

## Cached additive blend material. Overlapping energy motes SUM to white-hot
## (a real spark/fireball) instead of averaging to muddy grey. Shared static so
## every additive burst reuses one material (no per-cast alloc churn). Debris /
## dust / smoke bursts leave this off (`additive=false`) and stay alpha-blended.
static var _add_mat: CanvasItemMaterial = null

## Cached ParticleProcessMaterials keyed by the full tuning tuple. A burst
## material is read-only once built, so concurrent bursts safely share one
## instance — repeat casts of the same spell stop allocating a fresh
## ParticleProcessMaterial + Gradient + GradientTexture1D every call (§0.4
## GC-churn fix; worst offenders were meteor showers / blast / nova). Call
## sites use constant tunings, so the cache stays small and never invalidates.
static var _mat_cache: Dictionary = {}


static func additive_mat() -> CanvasItemMaterial:
	if _add_mat != null:
		return _add_mat
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add_mat = m
	return _add_mat


static func _soft_dot() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))  # radial falloff to transparent = soft glow
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = int(DOT_SIZE)
	tex.height = int(DOT_SIZE)
	_dot_tex = tex
	return _dot_tex


## Spawn a self-freeing radial GPUParticles2D burst under `parent` at `pos`.
## Particle color ramps from `color_start` to `color_end` (end alpha should
## be 0 so the burst fades out instead of popping off).
## `dir` + `spread_deg` (optional) make the burst a directional spark CONE
## instead of the default 360° radial — the Stick-Fight "sparks along the hit
## direction" recipe. Leave `dir` at ZERO for the classic radial burst.
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
	additive: bool = false,
	dir: Vector2 = Vector2.ZERO,
	spread_deg: float = 180.0,
) -> GPUParticles2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var burst := GPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = amount
	burst.lifetime = lifetime
	burst.texture = _soft_dot()  # glowing round dots, not hard squares
	if additive:
		burst.material = additive_mat()  # energy motes build to white-hot
	burst.process_material = _process_mat(
		color_start, color_end, velocity_min, velocity_max,
		scale_min, scale_max, damping_min, damping_max, dir, spread_deg)
	parent.add_child(burst)
	burst.global_position = pos
	burst.restart()
	burst.emitting = true
	parent.get_tree().create_timer(lifetime + 0.3).timeout.connect(burst.queue_free)
	return burst


## Cached ParticleProcessMaterial for a tuning tuple (see _mat_cache docs).
static func _process_mat(
	color_start: Color,
	color_end: Color,
	velocity_min: float,
	velocity_max: float,
	scale_min: float,
	scale_max: float,
	damping_min: float,
	damping_max: float,
	dir: Vector2,
	spread_deg: float,
) -> ParticleProcessMaterial:
	var key := "%s|%s|%.1f|%.1f|%.3f|%.3f|%.1f|%.1f|%.3f,%.3f|%.1f" % [
		color_start.to_html(true), color_end.to_html(true),
		velocity_min, velocity_max, scale_min, scale_max,
		damping_min, damping_max, dir.x, dir.y, spread_deg]
	var cached: Variant = _mat_cache.get(key)
	if cached != null:
		return cached
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	if dir != Vector2.ZERO:
		# Directional cone along the hit direction (impact sparks).
		mat.direction = Vector3(dir.x, dir.y, 0.0)
		mat.spread = clampf(spread_deg, 1.0, 180.0)
	else:
		mat.spread = 180.0  # classic full-circle radial burst
	mat.initial_velocity_min = velocity_min
	mat.initial_velocity_max = velocity_max
	mat.gravity = Vector3.ZERO
	mat.damping_min = damping_min
	mat.damping_max = damping_max
	# Compensate the caller's scale for the textured dot so sizes stay sensible.
	mat.scale_min = scale_min * SCALE_FACTOR
	mat.scale_max = scale_max * SCALE_FACTOR
	var ramp := Gradient.new()
	ramp.set_color(0, color_start)
	ramp.set_color(1, color_end)
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	_mat_cache[key] = mat
	return mat
