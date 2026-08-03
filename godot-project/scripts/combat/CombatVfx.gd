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

# ------------------------------------------------------------------ work counters
## Particles ASKED FOR versus particles actually EMITTED, cumulative.
##
## These exist because wall-clock on a dev machine is not a usable regression
## metric: the same 38-cast scripted run was timed at 38 ms and 57 ms twenty
## minutes apart, purely from background load, which is far wider than any
## optimisation worth making. Counters are DETERMINISTIC — the same seeded run
## produces the same numbers on a loaded machine and an idle one — so they are what
## `tools/slice_test_perf_budget.gd` asserts against and what the stress harness
## reports as its primary result. Time is reported alongside, as a sanity check
## rather than as the measurement.
static var _requested: int = 0
static var _granted: int = 0
static var _bursts: int = 0


## (bursts, particles requested, particles granted) since boot / last reset.
static func work_stats() -> Dictionary:
	return {"bursts": _bursts, "requested": _requested, "granted": _granted}


static func reset_work_stats() -> void:
	_requested = 0
	_granted = 0
	_bursts = 0


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
	amount = _budgeted(amount)
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


## The particle count this burst is actually allowed, given how much spell effect
## is already alive (see SpellReactorNode.austerity). The burst ALWAYS fires — a hit
## with no spark reads as a hit that did not land — it just fires thinner.
##
## ⚠ QUANTISED, and that is not tidiness. `amount` is the POOL'S BUCKET KEY: assigning
## a different amount to a recycled emitter reallocates its GPU buffer, which is the
## exact cost the pool exists to avoid. A continuous scale factor would mint a new
## bucket for almost every burst and quietly turn the pool back into an allocator.
## Four steps means at most four buckets per call site, and step 4 returns the
## original integer unchanged so the common (in-budget) case is byte-identical.
## What LOW takes off every burst, before crowding is even considered.
##
## THE GAP THIS CLOSES: austerity used to come ONLY from `vfx_austerity()`, which is
## driven by how many spell effects are live against the budget. So on a quiet
## screen — one spell, no crowd — LOW emitted exactly as many particles as HIGH,
## and `graphics_quality = LOW` on the desktop showed the maker a picture the phone
## will never draw. LOW is the only preview of the phone there is, and a preview
## that only differs when the screen is already busy is not one.
##
## 0.6 rather than something braver because this is COSMETIC AUSTERITY AND NOTHING
## ELSE: a burst is garnish laid over a hit that has already been resolved, so
## thinning it cannot change what an attack does, where it reaches or when it lands.
## No spell is dropped and no telegraph is quieted — those are the two things that
## would make this a fairness change rather than a fidelity one.
##
## ⚠ UNTESTED BY EYE. Nobody has seen 0.6 on a screen yet. It is one constant, and
## 1.0 restores the old behaviour exactly.
const LOW_PARTICLE_SCALE: float = 0.6
## Floor, matching the crowding path's: below this a burst stops reading as a burst
## and starts reading as a bug.
const MIN_PARTICLES: int = 4


static func _budgeted(amount: int) -> int:
	_bursts += 1
	_requested += amount
	var step: int = int(round(SpellReactorNode.vfx_austerity() * 4.0))
	var out: int = amount if step >= 4 else maxi(MIN_PARTICLES, (amount * step) / 4)
	if TuningConfig.quality_is_low():
		out = maxi(MIN_PARTICLES, int(round(float(out) * LOW_PARTICLE_SCALE)))
	_granted += out
	return out


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
		# ⚠ Variant FIRST. Assigning an already-freed node straight into a typed
		# local raises "Trying to assign invalid previously freed instance", and a
		# runtime error in GDScript ABORTS THE ENCLOSING FUNCTION — so this would
		# have returned null to spawn_burst the first time an arena was torn down
		# with emitters still banked. See the matching note on DamageNumber._pool.
		var raw: Variant = bucket.pop_back()
		_pooled_total = maxi(_pooled_total - 1, 0)
		if not is_instance_valid(raw):
			continue  # went down with the arena that owned it
		var candidate: GPUParticles2D = raw
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
## ⚠ `raw` IS UNTYPED, AND THAT IS THE WHOLE GUARD. This runs off a scene timer armed
## in `spawn_burst`, so anything that frees the emitter first — an arena teardown, a
## scene change, this pool's own `queue_free` — makes the bound argument a freed
## instance. A TYPED parameter is converted at the CALL BOUNDARY, and that conversion
## throws ("Cannot convert argument 1 from Object to Object") BEFORE one line of this
## body runs: the `is_instance_valid` check below was unreachable for the exact case
## it was written for, and every bot-sim run printed that error on a loop. Same idiom,
## and same reason, as `BotController.perceive_elemental`'s freed-node skip.
static func _recycle(raw: Variant, amount: int) -> void:
	if raw == null or not is_instance_valid(raw):
		return
	var burst: GPUParticles2D = raw as GPUParticles2D
	if burst == null:
		return
	burst.emitting = false
	burst.visible = false
	if not burst.is_inside_tree() or _pooled_total >= MAX_POOLED_PER_AMOUNT * 8:
		burst.queue_free()
		return
	var bucket: Array = _free.get(amount, [])
	if bucket.has(burst):
		return  # already banked — banking twice would hand the same emitter to two
		        # concurrent bursts, which reads as one of them silently not firing
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
		for raw: Variant in _free[amount]:
			if is_instance_valid(raw):
				(raw as GPUParticles2D).queue_free()
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
