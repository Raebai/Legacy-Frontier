extends Node2D
## Mystic-forest hub ambience (maker: "campfire in the middle, cool glowing stars
## up top, a cool artsy mystic-forest feel"). Draws, in world space: a twinkling
## STARFIELD, layered dark FOREST-TREE silhouettes with bioluminescent glows, and
## a central animated CAMPFIRE (flickering flame + warm light pool). Adds drifting
## FIREFLY + rising EMBER particles. Built in code (house style, like Atmosphere).
## _process advances _phase for the flame flicker + star twinkle.

var _bounds: Rect2 = Rect2(0, 0, 1720, 452)
var _ground_y: float = 452.0
var _fire: Vector2 = Vector2(860, 452)
var _phase: float = 0.0
var _stars: Array[Dictionary] = []       # {pos, r, seed, glow}
var _trees: Array[Dictionary] = []       # {x, base_y, w, h, layer, glow_col}
var _glows: Array[Dictionary] = []       # bioluminescent dots {pos, r, col, seed}


## town_width / ground_y frame the forest; fire_x is the campfire's ground x.
func build(town_width: float, ground_y: float, fire_x: float) -> void:
	_bounds = Rect2(0, 0, town_width, ground_y)
	_ground_y = ground_y
	_fire = Vector2(fire_x, ground_y)
	z_index = -6  # behind the characters, in front of the sky/spires
	_seed_stars()
	_seed_trees()
	_seed_glows()
	_build_fireflies()
	_build_embers()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


# --------------------------------------------------------------------- seeding
## Deterministic star positions in the upper sky (no RNG -> stable frame-to-frame).
func _seed_stars() -> void:
	var n: int = 90
	for i: int in n:
		var fx: float = fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var fy: float = fmod(sin(float(i) * 78.233) * 12543.245, 1.0)
		fx = absf(fx)
		fy = absf(fy)
		# Stars sit in the sky BAND above the tree line + within the camera frame
		# (ground_y - 380 .. ground_y - 120), so they read as a glowing night sky.
		_stars.append({
			"pos": Vector2(_bounds.size.x * fx, _ground_y - 380.0 + fy * 260.0),
			"r": 0.8 + absf(sin(float(i) * 3.3)) * 1.6,
			"seed": float(i) * 1.7,
			"glow": (i % 6 == 0),  # a few bright glowing ones
		})


## Two layers of pine-ish tree silhouettes across the back of the forest.
func _seed_trees() -> void:
	var far_col := Color(0.09, 0.13, 0.16)
	var near_col := Color(0.05, 0.08, 0.10)
	var x: float = -60.0
	var i: int = 0
	while x < _bounds.size.x + 60.0:
		var far_h: float = 150.0 + absf(sin(x * 0.017 + 1.3)) * 90.0
		_trees.append({"x": x, "base_y": _ground_y + 6.0, "w": 54.0, "h": far_h, "col": far_col,
			"glow": Color(0.3, 0.7, 0.6, 0.0)})
		x += 78.0 + absf(sin(x)) * 20.0
		i += 1
	x = -30.0
	i = 0
	while x < _bounds.size.x + 60.0:
		var near_h: float = 200.0 + absf(sin(x * 0.013 + 3.1)) * 120.0
		# A few near trees carry a faint teal bioluminescent glow (mystic).
		var glow_a: float = 0.16 if i % 4 == 0 else 0.0
		_trees.append({"x": x, "base_y": _ground_y + 10.0, "w": 74.0, "h": near_h, "col": near_col,
			"glow": Color(0.35, 0.85, 0.7, glow_a)})
		x += 132.0 + absf(sin(x * 1.7)) * 26.0
		i += 1


## Bioluminescent ground dots (glowing mushrooms/flowers) scattered along the floor.
func _seed_glows() -> void:
	for i: int in 26:
		var fx: float = absf(fmod(sin(float(i) * 34.21) * 8123.7, 1.0))
		var teal := Color(0.4, 0.9, 0.75)
		var violet := Color(0.7, 0.5, 1.0)
		_glows.append({
			"pos": Vector2(_bounds.size.x * fx, _ground_y - 2.0 - absf(sin(float(i))) * 6.0),
			"r": 2.0 + absf(sin(float(i) * 5.5)) * 2.5,
			"col": teal if i % 2 == 0 else violet,
			"seed": float(i) * 2.3,
		})


# ---------------------------------------------------------------------- particles
## Drifting fireflies across the clearing — warm-green glowing motes.
func _build_fireflies() -> void:
	var ff := GPUParticles2D.new()
	ff.amount = 46
	ff.lifetime = 7.0
	ff.preprocess = 7.0
	ff.position = Vector2(_bounds.size.x * 0.5, _ground_y - 90.0)
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(_bounds.size.x * 0.5, 110.0, 0.0)
	mat.direction = Vector3(0.0, -0.2, 0.0)
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 16.0
	mat.scale_min = 1.2
	mat.scale_max = 3.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 1.0, 0.5, 0.0))
	ramp.set_color(1, Color(0.6, 1.0, 0.5, 0.0))
	ramp.add_point(0.5, Color(0.75, 1.0, 0.55, 0.85))  # twinkle in + out
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	ff.process_material = mat
	add_child(ff)


## Embers rising from the campfire.
func _build_embers() -> void:
	var em := GPUParticles2D.new()
	em.amount = 30
	em.lifetime = 2.2
	em.preprocess = 2.2
	em.position = _fire + Vector2(0.0, -8.0)
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(10.0, 4.0, 0.0)
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 22.0
	mat.gravity = Vector3(0.0, -18.0, 0.0)  # embers drift UP
	mat.initial_velocity_min = 28.0
	mat.initial_velocity_max = 70.0
	mat.scale_min = 1.0
	mat.scale_max = 2.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
	ramp.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	em.process_material = mat
	add_child(em)


# --------------------------------------------------------------------------- draw
func _draw() -> void:
	_draw_stars()
	_draw_trees()
	_draw_glows()
	_draw_campfire()


func _draw_stars() -> void:
	for s: Dictionary in _stars:
		var tw: float = 0.55 + 0.45 * sin(_phase * 1.6 + float(s["seed"]))
		var p: Vector2 = s["pos"]
		var r: float = float(s["r"])
		if bool(s["glow"]):
			# A soft halo around the bright ones.
			draw_circle(p, r * 3.2, Color(0.7, 0.82, 1.0, 0.10 * tw))
			draw_circle(p, r * 1.8, Color(0.85, 0.92, 1.0, 0.20 * tw))
		draw_circle(p, r, Color(1.0, 1.0, 1.0, 0.5 + 0.5 * tw))


func _draw_trees() -> void:
	for t: Dictionary in _trees:
		var x: float = t["x"]
		var base_y: float = t["base_y"]
		var w: float = t["w"]
		var h: float = t["h"]
		var col: Color = t["col"]
		# A stacked-triangle pine silhouette.
		var tiers: int = 3
		for k: int in tiers:
			var kf: float = float(k) / float(tiers)
			var ty: float = base_y - h * kf
			var tw: float = w * (1.0 - kf * 0.55)
			var th: float = h * 0.5
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - tw * 0.5, ty), Vector2(x + tw * 0.5, ty), Vector2(x, ty - th),
			]), col)
		# Bioluminescent glow on the mystic near-trees — subtle, not a big blob.
		var glow: Color = t["glow"]
		if glow.a > 0.0:
			var gy: float = base_y - h * 0.55
			var pulse: float = 0.6 + 0.4 * sin(_phase * 1.2 + x)
			draw_circle(Vector2(x, gy), w * 0.28, Color(glow.r, glow.g, glow.b, glow.a * pulse))


func _draw_glows() -> void:
	for g: Dictionary in _glows:
		var pulse: float = 0.5 + 0.5 * sin(_phase * 2.0 + float(g["seed"]))
		var c: Color = g["col"]
		var p: Vector2 = g["pos"]
		var r: float = float(g["r"])
		draw_circle(p, r * 2.6, Color(c.r, c.g, c.b, 0.10 * pulse))
		draw_circle(p, r, Color(c.r, c.g, c.b, 0.55 + 0.35 * pulse))


func _draw_campfire() -> void:
	var base: Vector2 = _fire
	# Warm light pool on the ground (flickers with the flame).
	var flick: float = 0.82 + 0.18 * sin(_phase * 11.0) + 0.06 * sin(_phase * 23.0)
	draw_circle(base, 120.0 * flick, Color(1.0, 0.6, 0.25, 0.06))
	draw_circle(base, 70.0 * flick, Color(1.0, 0.65, 0.3, 0.09))
	# Log pile (two crossed dark logs).
	draw_line(base + Vector2(-14, 2), base + Vector2(14, -4), Color(0.22, 0.14, 0.09), 5.0)
	draw_line(base + Vector2(-14, -4), base + Vector2(14, 2), Color(0.28, 0.17, 0.10), 5.0)
	# Flame: layered flickering teardrops (outer orange -> inner yellow -> white core).
	_draw_flame(base + Vector2(0, -6), 20.0, 46.0 * flick, Color(1.0, 0.45, 0.12, 0.85), 0.0)
	_draw_flame(base + Vector2(0, -6), 13.0, 34.0 * flick, Color(1.0, 0.72, 0.22, 0.9), 1.7)
	_draw_flame(base + Vector2(0, -6), 7.0, 22.0 * flick, Color(1.0, 0.95, 0.6, 0.95), 3.1)
	draw_circle(base + Vector2(0, -6), 4.0, Color(1.0, 1.0, 0.9, 0.9))


## One flickering flame teardrop: a fan of points from the base to a wavering tip.
func _draw_flame(origin: Vector2, width: float, height: float, col: Color, ph: float) -> void:
	var sway: float = sin(_phase * 7.0 + ph) * width * 0.35
	var tip: Vector2 = origin + Vector2(sway, -height)
	var pts: PackedVector2Array = PackedVector2Array([
		origin + Vector2(-width * 0.5, 0),
		origin + Vector2(-width * 0.3, -height * 0.4),
		tip,
		origin + Vector2(width * 0.3, -height * 0.4),
		origin + Vector2(width * 0.5, 0),
	])
	draw_colored_polygon(pts, col)
