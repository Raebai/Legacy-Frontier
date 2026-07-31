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

# ------------------------------------------------------------------ burst POOL
## Retired bursts, ready to fire again. `GPUParticles2D.new()` is not an ordinary
## node allocation: constructing one asks the RenderingServer for a particle RID
## and a GPU buffer sized to `amount`, and freeing one hands both back. There are
## 140 `spawn_burst` call sites and the busy ones fire several times a second
## each, so on a phone this was a steady drip of GPU allocator traffic in the
## middle of combat.
##
## KEYED BY `amount`, which is the whole reason this works. Assigning a different
## `amount` to a recycled emitter REALLOCATES the GPU buffer, so a pool that
## handed a 20-particle emitter to a call wanting 60 would pay the allocation it
## was built to avoid. Call sites use constant tunings (the same property the
## material cache above relies on), so the buckets stay few and stable.
##
## Note what is NOT pooled: the per-burst `SceneTreeTimer`. It is a small
## RefCounted next to a GPU buffer, and it is DETERMINISTIC — it fires under the
## dummy renderer in headless tests, where particle simulation does not run and
## the `finished` signal therefore cannot be relied on to return anything to the
## pool. Trading a guaranteed reaper for a marginal saving is not a good trade.
static var _free: Dictionary = {}          # amount:int -> Array[GPUParticles2D]
const MAX_POOLED_PER_AMOUNT: int = 12
static var _pooled_total: int = 0


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
	var burst: GPUParticles2D = _acquire(parent, amount)
	burst.lifetime = lifetime
	# Additive is per-call-site, so a recycled emitter must be told BOTH ways —
	# clearing it matters as much as setting it, or a debris puff inherits the
	# white-hot blend from whatever spark burst last used this slot.
	burst.material = additive_mat() if additive else null
	burst.process_material = _process_mat(
		color_start, color_end, velocity_min, velocity_max,
		scale_min, scale_max, damping_min, damping_max, dir, spread_deg)
	burst.global_position = pos
	burst.visible = true
	burst.restart()
	burst.emitting = true
	parent.get_tree().create_timer(lifetime + 0.3).timeout.connect(_recycle.bind(burst, amount))
	return burst


## A burst emitter ready to be configured: a retired one from the matching
## `amount` bucket, otherwise a fresh node.
##
## A recycled emitter is moved to the END of the parent's child list. Bursts do
## not set a z_index — they rely on being the most recently added child to draw
## OVER the fight — so a reused node sitting at its old tree index would slide
## behind everything spawned since it was retired. That is the one behavioural
## difference between a fresh node and a recycled one, and this is where it is
## paid back.
static func _acquire(parent: Node, amount: int) -> GPUParticles2D:
	var bucket: Array = _free.get(amount, [])
	while not bucket.is_empty():
		var candidate: GPUParticles2D = bucket.pop_back()
		_pooled_total = maxi(_pooled_total - 1, 0)
		if not is_instance_valid(candidate):
			continue  # went down with the arena that owned it
		if candidate.is_inside_tree() and candidate.get_parent() == parent:
			parent.move_child(candidate, -1)
			return candidate
		candidate.queue_free()  # belongs to a floor we have already left
	var burst := GPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = amount          # sizes the GPU buffer — never reassigned after this
	burst.texture = _soft_dot()    # glowing round dots, not hard squares
	parent.add_child(burst)
	return burst


## Timer callback: the burst has finished playing. Park it rather than free it.
## Hidden and not emitting, so a parked emitter costs nothing to have around.
static func _recycle(burst: GPUParticles2D, amount: int) -> void:
	if not is_instance_valid(burst):
		return
	burst.emitting = false
	burst.visible = false
	if not burst.is_inside_tree() or _pooled_total >= MAX_POOLED_PER_AMOUNT * 8:
		burst.queue_free()
		return
	var bucket: Array = _free.get(amount, [])
	if bucket.size() >= MAX_POOLED_PER_AMOUNT:
		burst.queue_free()
		return
	bucket.append(burst)
	_free[amount] = bucket
	_pooled_total += 1


## Test hook + arena teardown: drop every parked emitter. Mirrors
## DamageNumber.reset_pool() / ImpactFrame.reset_arbiter().
static func reset_pool() -> void:
	for amount: int in _free.keys():
		for b: GPUParticles2D in _free[amount]:
			if is_instance_valid(b):
				b.queue_free()
	_free.clear()
	_pooled_total = 0


## Diagnostics (the perf overlay reads this): parked emitters across all buckets.
static func pooled_count() -> int:
	return _pooled_total


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
