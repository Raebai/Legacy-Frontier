extends Node2D
## THE TAVERN'S FURNITURE AND ITS FIRE — everything that stands ON the floor.
##
## Maker: *"make the lobby very different like a tavern vibe … inside of a tavern with
## warm lit and cool graphics"*.
##
## ══ WHAT THIS FILE IS, AND WHY IT IS STILL A SEPARATE ONE ═══════════════════
## `AntechamberBackdrop` draws the ROOM — the plank wall, the windows onto the night,
## the posts, the bar, the hanging lamps. This draws what is IN it: tables, stools,
## barrels, crates, candles, and the hearth. The split is the same one it always was
## and it is a Z one, not a taste one: the shell parks on `StageLayers.MOUNTAIN` (-18),
## behind everything, and this sits on the TERRAIN rung (-6) so its furniture stands in
## FRONT of the wall and its firelight lands on the floor you are walking on.
##
## ══ WHAT REPLACED WHAT ══════════════════════════════════════════════════════
## This used to be a mystic FOREST: a starfield, two bands of pine silhouettes, glowing
## mushrooms, a campfire, fireflies and embers. Every one of those has an interior
## counterpart doing the same compositional job, which is why the file kept its shape:
##
##   * STARFIELD  -> deleted. There is a roof over the room now; the twinkle it bought
##     is on the bar's bottles in `AntechamberBackdrop` and on the candles below.
##   * PINE BANDS -> FURNITURE, in the same two parallax bands and for the same reason:
##     a far band hazed toward the wall behind it, a near band in near-black. Depth
##     comes from two ranks of silhouette, exactly as it did from two ranks of trees.
##   * GROUND GLOWS -> CANDLES on the tables. Warm instead of teal + violet, and they
##     sit on a surface instead of on the dirt.
##   * CAMPFIRE -> THE HEARTH. The flame drawing is kept VERBATIM — it is the best
##     thing in the file and a fire is a fire — and it is set into a stone fireplace
##     with a mantel, which is the whole difference between camping and being indoors.
##   * FIREFLIES -> deleted, and deliberately not re-tinted. The layer of drifting
##     motes now lives in `AntechamberBackdrop._Dust`, IN FRONT of the player where it
##     catches the lamp light; a second emitter here would be the same effect twice at
##     twice the cost.
##   * EMBERS -> kept, rising into the chimney.
##
## ══ IT MUST DEGRADE ═════════════════════════════════════════════════════════
## ⚠ AND IT DID NOT BEFORE. The forest version read no quality setting at all and called
## `queue_redraw()` EVERY FRAME — a full furniture-and-fire repaint at 60 Hz on a phone,
## to animate a flame flicker. `_low` is now read ONCE into a field (the `Telegraph._low`
## pattern, never per draw) and the repaint is rate-capped like the backdrop's. LOW also
## drops the far furniture band, the candle halos and the hearth's outer light ring.

## Redraw budget. The flame is the fastest thing here and it is a sub-pixel wobble
## between frames at 24 Hz, so the frames are bought and nothing is lost.
const REDRAW_HZ: float = 24.0
const REDRAW_HZ_LOW: float = 12.0

## ── the palette ─────────────────────────────────────────────────────────────
## Read from `AntechamberBackdrop` rather than re-declared, so the furniture cannot
## drift off the wall's own timber. `preload` and not a bare name: the backdrop has no
## `class_name`, which is what keeps it clear of the global-class-cache trap.
const Shell := preload("res://scripts/ui/AntechamberBackdrop.gd")
## Near furniture is drawn nearly black — it is the rank closest to the camera and its
## whole job is a readable silhouette against the lit floor.
const NEAR_WOOD: Color = Color(0.055, 0.040, 0.033)
## Far furniture is hazed toward the wall, so "further away = closer to the background"
## is structural here rather than a hand-picked second brown. Same idea `StageLayers.haze`
## applies to distant landforms, applied at four metres instead of four hundred.
const FAR_WOOD: Color = Color(0.098, 0.070, 0.055)
const STONE: Color = Color(0.135, 0.125, 0.125)
const STONE_LIT: Color = Color(0.215, 0.195, 0.180)
const CANDLE: Color = Color(1.0, 0.82, 0.48)

## ⚠ DECLARED AS A FIELD so a headless suite can force the cheap picture with
## `set("_low", true)` and then call `reseed()` — the same affordance the backdrop
## documents.
var _low: bool = false

var _bounds: Rect2 = Rect2(0, 0, 1180, 452)
var _ground_y: float = 452.0
var _fire: Vector2 = Vector2(800, 452)
var _phase: float = 0.0
var _redraw_acc: float = 0.0
## {x, w, h, kind, near} — kind is one of the `_KIND_*` values below.
var _props: Array[Dictionary] = []
## {pos, seed} — a candle flame standing on a table top.
var _candles: Array[Dictionary] = []

const _KIND_TABLE: int = 0
const _KIND_STOOL: int = 1
const _KIND_BARREL: int = 2
const _KIND_CRATE: int = 3

## ⚠ AUTHORED, NOT SCATTERED, AND THE REASON IS COLLISION-FREE FURNITURE.
## Nothing here has a body, so a randomly placed table can end up drawn through a
## training dummy, a teleport pad's glyph or the doorkeeper. Every x below is picked
## against `World`'s own layout: the dummies stand at 110/172/234, the pads at 460 and
## 580, the signboard at 630, the hearth at 800, the party stone at 860, the doorkeeper
## at 930 and the tower door's walk-in box is 946..1014. The gaps are what is furnished.
##
## `near` decides the rank (and therefore the colour and the scale); `w`/`h` are the
## silhouette in world px at the near rank and are shrunk for the far one.
const LAYOUT: Array[Dictionary] = [
	# ── far rank: against the wall, hazed, small. Read as depth, never as objects.
	{"x": 300.0, "kind": _KIND_STOOL, "near": false},
	{"x": 520.0, "kind": _KIND_TABLE, "near": false},
	{"x": 556.0, "kind": _KIND_STOOL, "near": false},
	{"x": 700.0, "kind": _KIND_BARREL, "near": false},
	{"x": 906.0, "kind": _KIND_TABLE, "near": false},
	{"x": 942.0, "kind": _KIND_STOOL, "near": false},
	{"x": 1060.0, "kind": _KIND_CRATE, "near": false},
	# ── near rank: the room you actually walk through.
	{"x": 386.0, "kind": _KIND_TABLE, "near": true},
	{"x": 344.0, "kind": _KIND_STOOL, "near": true},
	{"x": 428.0, "kind": _KIND_STOOL, "near": true},
	{"x": 690.0, "kind": _KIND_TABLE, "near": true},
	{"x": 648.0, "kind": _KIND_STOOL, "near": true},
	{"x": 1096.0, "kind": _KIND_CRATE, "near": true},
	{"x": 1146.0, "kind": _KIND_BARREL, "near": true},
]


## town_width / ground_y frame the room; fire_x is the hearth's x on the floor.
func build(town_width: float, ground_y: float, fire_x: float) -> void:
	_bounds = Rect2(0, 0, town_width, ground_y)
	_ground_y = ground_y
	_fire = Vector2(fire_x, ground_y)
	z_index = -6  # in front of the room shell, behind the characters
	_low = TuningConfig.quality_is_low()
	reseed()
	_build_embers()
	set_process(true)
	queue_redraw()


## Rebuild every seeded table from the CURRENT `_low`. Public and separate for the same
## measurement reason `AntechamberBackdrop.reseed` is: `build()` reads the live quality
## setting, so an override applied afterwards only flips the draw branches unless this
## is called, and a probe that skips it reports that LOW costs the same as HIGH.
func reseed() -> void:
	_props.clear()
	_candles.clear()
	_seed_props()


func _process(delta: float) -> void:
	_phase += delta
	_redraw_acc += delta
	var step: float = 1.0 / (REDRAW_HZ_LOW if _low else REDRAW_HZ)
	if _redraw_acc < step:
		return
	_redraw_acc = 0.0
	queue_redraw()


# --------------------------------------------------------------------- seeding
func _seed_props() -> void:
	var i: int = 0
	for entry: Dictionary in LAYOUT:
		var near: bool = bool(entry["near"])
		# LOW drops the far rank entirely. It is the rank that carries the least read
		# (it is hazed most of the way to the wall behind it) for a per-prop cost that
		# is identical to the near one, which makes it the honest thing to cut first.
		if _low and not near:
			i += 1
			continue
		var kind: int = int(entry["kind"])
		var scale: float = 1.0 if near else 0.72
		var w: float = 0.0
		var h: float = 0.0
		match kind:
			_KIND_TABLE:
				w = 68.0
				h = 26.0
			_KIND_STOOL:
				w = 18.0
				h = 17.0
			_KIND_BARREL:
				w = 30.0
				h = 36.0
			_KIND_CRATE:
				w = 34.0
				h = 30.0
		_props.append({
			"x": float(entry["x"]),
			"w": w * scale,
			"h": h * scale,
			"kind": kind,
			"near": near,
			# The far rank stands a little higher on the screen, which is the whole of
			# the perspective cue: the floor recedes upward.
			"base_y": _ground_y + (2.0 if near else -9.0),
			"seed": float(i) * 2.7,
		})
		# A table gets a candle on it, and that is the only light source in the room
		# that is not the hearth or a hanging lamp — so it is what makes a table read as
		# a place somebody sits rather than as a box.
		if kind == _KIND_TABLE:
			_candles.append({
				"pos": Vector2(float(entry["x"]) + w * scale * 0.24,
					_ground_y + (2.0 if near else -9.0) - h * scale),
				"seed": float(i) * 3.1,
				"near": near,
			})
		i += 1


# ---------------------------------------------------------------------- particles
## Embers rising off the hearth and up the chimney. The one particle system in the
## room — see the header for why the firefly emitter is gone rather than re-tinted.
func _build_embers() -> void:
	var em := GPUParticles2D.new()
	em.amount = (12 if _low else 30)
	# ⚠ 2.2 s -> 1.05 s, AND IT IS THE MAIN CAUSE OF "THE FIRE DOES NOT STAY IN THE
	# FURNACE". Maker, after playing: *"the fire should stay within the furnace"*. At
	# 2.2 s against 28-70 px/s of initial rise plus 18 px/s^2 of upward drift, an ember
	# travelled about 200 px before it died — and the firebox is only `MOUTH_H` = 92 px
	# tall. Every ember therefore flew UP THROUGH the mantel and out into the room, which
	# is exactly what a fire that has escaped its fireplace looks like. The budget is
	# arithmetic, not taste: `v_max * t + 0.5 * g * t^2` at 1.05 s and 44 px/s is ~56 px,
	# which dies inside the flue with room to spare.
	em.lifetime = 1.05
	em.preprocess = 1.05
	em.position = _fire + Vector2(0.0, -10.0)
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(9.0, 3.0, 0.0)
	mat.direction = Vector3(0.0, -1.0, 0.0)
	# Tighter than the campfire's 22 degrees: a fire in a fireplace is drawn UP a flue,
	# and a wide spread would have embers going into the room.
	mat.spread = 12.0
	mat.gravity = Vector3(0.0, -18.0, 0.0)  # embers drift UP
	mat.initial_velocity_min = 18.0
	mat.initial_velocity_max = 44.0
	mat.scale_min = 1.0
	mat.scale_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
	ramp.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	em.process_material = mat
	add_child(em)


# --------------------------------------------------------------------------- draw
## Call order is depth: the far rank, then the hearth (which lights them), then the
## near rank in front of its glow, then the candles on top of the tables they stand on.
func _draw() -> void:
	for p: Dictionary in _props:
		if not bool(p["near"]):
			_draw_prop(p)
	_draw_hearth()
	for p: Dictionary in _props:
		if bool(p["near"]):
			_draw_prop(p)
	_draw_candles()


## One piece of furniture. Everything wears the `StageLayers` grammar's lit cap along
## its top edge — the same warm pale band a ledge you can stand on wears in the arena —
## so a table top and a crate lid read as SURFACES at 640x360 without any detail.
func _draw_prop(p: Dictionary) -> void:
	var x: float = float(p["x"])
	var w: float = float(p["w"])
	var h: float = float(p["h"])
	var base: float = float(p["base_y"])
	var near: bool = bool(p["near"])
	var body: Color = NEAR_WOOD if near else StageLayers.haze(FAR_WOOD, Shell.TIMBER, 0.45)
	var cap: Color = Color(Shell.CAP_LIT.r, Shell.CAP_LIT.g, Shell.CAP_LIT.b,
		0.30 if near else 0.16)
	var top: float = base - h
	match int(p["kind"]):
		_KIND_TABLE:
			# A slab on two trestles. The gap under the top is what stops it reading as
			# a solid block, and it is one rect's worth of work.
			draw_rect(Rect2(Vector2(x - w * 0.5, top), Vector2(w, h * 0.26)), body)
			draw_rect(Rect2(Vector2(x - w * 0.5, top), Vector2(w, 2.0)), cap)
			for side: float in [-1.0, 1.0]:
				draw_rect(Rect2(Vector2(x + side * w * 0.34 - w * 0.045,
					top + h * 0.26), Vector2(w * 0.09, h * 0.74)), body)
		_KIND_STOOL:
			draw_rect(Rect2(Vector2(x - w * 0.5, top), Vector2(w, h * 0.30)), body)
			draw_rect(Rect2(Vector2(x - w * 0.5, top), Vector2(w, 1.5)), cap)
			for side: float in [-1.0, 1.0]:
				draw_rect(Rect2(Vector2(x + side * w * 0.32 - 1.5, top + h * 0.30),
					Vector2(3.0, h * 0.70)), body)
		_KIND_BARREL:
			draw_rect(Rect2(Vector2(x - w * 0.5, top), Vector2(w, h)), body)
			draw_rect(Rect2(Vector2(x - w * 0.5, top), Vector2(w, 2.0)), cap)
			for f: float in [0.32, 0.68]:
				draw_rect(Rect2(Vector2(x - w * 0.5, top + h * f), Vector2(w, 1.5)),
					Color(Shell.BRASS.r, Shell.BRASS.g, Shell.BRASS.b, 0.6))
		_KIND_CRATE:
			draw_rect(Rect2(Vector2(x - w * 0.5, top), Vector2(w, h)), body)
			draw_rect(Rect2(Vector2(x - w * 0.5, top), Vector2(w, 2.0)), cap)
			# A diagonal brace, which is the one line that says "crate" and not "box".
			draw_line(Vector2(x - w * 0.5, base), Vector2(x + w * 0.5, top),
				Color(Shell.TIMBER_LIT.r, Shell.TIMBER_LIT.g, Shell.TIMBER_LIT.b, 0.35),
				1.5)


## Candles on the tables. A flame the size of a pixel needs a HALO to be seen at all,
## which is why the halo is the part LOW cuts rather than the flame.
func _draw_candles() -> void:
	for c: Dictionary in _candles:
		var p: Vector2 = c["pos"]
		var pulse: float = 0.72 + 0.28 * sin(_phase * 4.3 + float(c["seed"]))
		draw_rect(Rect2(p - Vector2(1.5, 7.0), Vector2(3.0, 7.0)),
			Color(0.86, 0.82, 0.70, 0.85))
		if not _low:
			draw_circle(p - Vector2(0.0, 9.0), 11.0,
				Color(CANDLE.r, CANDLE.g, CANDLE.b, 0.07 * pulse))
		draw_circle(p - Vector2(0.0, 9.0), 4.0,
			Color(CANDLE.r, CANDLE.g, CANDLE.b, 0.16 * pulse))
		draw_circle(p - Vector2(0.0, 9.0), 1.7,
			Color(1.0, 0.95, 0.75, 0.95 * pulse))


## THE HEARTH. Stone surround, an ARCHED mouth, a mantel and the campfire's own flame
## drawing set into it.
##
## ⚠ THE FLAME CODE IS UNCHANGED FROM THE CAMPFIRE ON PURPOSE. It was the best thing in
## the forest version — three layered flickering teardrops, outer orange to a white
## core — and a fire indoors is the same fire. What changed is everything AROUND it, and
## that is the whole difference between camping and being in a tavern.
##
## ⚠ AND THE LIGHT IS NOW BOUNDED BY THE FIREPLACE, WHICH IS A BUG FIX. Maker, after
## playing: *"the fire should stay within the furnace"*. The first pass drew the old
## campfire's light as two radial discs centred on the fire at radius 92 and 150 —
## correct for a fire in the open, and 150 px is nearly TWICE the surround's own
## half-width, so the room had a glowing orange circle spilling out of both sides of a
## stone fireplace. The cause was the shape, not the brightness, so the fix is the
## shape: the glow now lives INSIDE the firebox, and what reaches the room is a flat
## floor spill in front of the mouth that is narrower than the surround.
const MOUTH_HALF: float = 46.0
const MOUTH_H: float = 92.0
const SURROUND_HALF: float = 78.0
## The floor spill's half-width. Deliberately less than `SURROUND_HALF`, so no lit pixel
## is ever outside the fireplace's own footprint — see the ⚠ above.
const SPILL_RX: float = 62.0
const ARCH_SEGS: int = 14
const ARCH_SEGS_LOW: int = 7


func _draw_hearth() -> void:
	var base: Vector2 = _fire
	var flick: float = 0.82 + 0.18 * sin(_phase * 11.0) + 0.06 * sin(_phase * 23.0)
	var stack_top: float = _ground_y - 196.0
	# The surround, and the flue narrowing above it — the taper is what makes it a
	# chimney rather than a slab with a hole in it.
	draw_rect(Rect2(Vector2(base.x - SURROUND_HALF, stack_top),
		Vector2(SURROUND_HALF * 2.0, _ground_y - stack_top)), STONE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(base.x - SURROUND_HALF, stack_top),
		Vector2(base.x + SURROUND_HALF, stack_top),
		Vector2(base.x + SURROUND_HALF * 0.62, stack_top - 74.0),
		Vector2(base.x - SURROUND_HALF * 0.62, stack_top - 74.0),
	]), STONE.darkened(0.15))
	# THE ARCHED MOUTH. Maker: *"add some cool curved structures"* — and the fireplace
	# is where an arch actually carries something, so it is the honest place to put one.
	# Near-black, never pure black: rule 3 of the `StageLayers` grammar reserves a true
	# void for a thing that kills you, and a fireplace is not one.
	var spring: float = _ground_y - MOUTH_H + MOUTH_HALF
	var mouth: PackedVector2Array = PackedVector2Array([
		Vector2(base.x - MOUTH_HALF, _ground_y),
		Vector2(base.x - MOUTH_HALF, spring),
	])
	var segs: int = ARCH_SEGS_LOW if _low else ARCH_SEGS
	for i: int in segs + 1:
		var a: float = lerpf(PI, TAU, float(i) / float(segs))
		mouth.append(Vector2(base.x + cos(a) * MOUTH_HALF, spring + sin(a) * MOUTH_HALF))
	mouth.append(Vector2(base.x + MOUTH_HALF, _ground_y))
	draw_colored_polygon(mouth, Color(0.045, 0.032, 0.030))
	# The voussoirs — one lighter ring of stone following the arch, which is what turns
	# a rounded hole into something that was built.
	var prev: Vector2 = Vector2.ZERO
	for i: int in segs + 1:
		var a: float = lerpf(PI, TAU, float(i) / float(segs))
		var q := Vector2(base.x + cos(a) * (MOUTH_HALF + 5.0),
			spring + sin(a) * (MOUTH_HALF + 5.0))
		if i > 0:
			draw_line(prev, q, STONE_LIT, 5.0)
		prev = q
	# THE GLOW, INSIDE THE MOUTH. Two discs whose radius is capped by the opening, so
	# the light cannot reach the stone's outer edge, let alone the room.
	draw_circle(base + Vector2(0.0, -10.0), MOUTH_HALF * 0.92 * flick,
		Color(1.0, 0.52, 0.18, 0.10))
	draw_circle(base + Vector2(0.0, -10.0), MOUTH_HALF * 0.55 * flick,
		Color(1.0, 0.66, 0.28, 0.11))
	# THE FLOOR SPILL. Flat, in front of the mouth, and narrower than the surround —
	# this is the only firelight that leaves the fireplace, and it lies on the boards
	# rather than hanging in the air.
	var spill: PackedVector2Array = PackedVector2Array()
	var ssegs: int = 10 if _low else 20
	for i: int in ssegs:
		var a: float = TAU * float(i) / float(ssegs)
		spill.append(base + Vector2(cos(a) * SPILL_RX * flick, sin(a) * 11.0))
	draw_colored_polygon(spill, Color(1.0, 0.58, 0.22, 0.09))
	# The mantel. The strongest horizontal on this half of the room, so it is what the
	# eye uses to place the fire in space.
	#
	# ⚠ ITS HIGHLIGHT IS STONE, NOT `CAP_LIT`. Maker: *"there are random yellow lines on
	# the taverns that dont really make sense"*. A warm amber cap is the grammar's word
	# for "you can stand on this", and a mantelpiece 104 px up is not standable — so it
	# gets a pale STONE edge, which says "lit shelf" without making a promise.
	draw_rect(Rect2(Vector2(base.x - SURROUND_HALF - 8.0, _ground_y - MOUTH_H - 12.0),
		Vector2(SURROUND_HALF * 2.0 + 16.0, 12.0)), STONE_LIT)
	draw_rect(Rect2(Vector2(base.x - SURROUND_HALF - 8.0, _ground_y - MOUTH_H - 12.0),
		Vector2(SURROUND_HALF * 2.0 + 16.0, 2.5)), STONE_LIT.lightened(0.35))
	# Log pile (two crossed dark logs), kept from the campfire.
	draw_line(base + Vector2(-14, 2), base + Vector2(14, -4), Color(0.22, 0.14, 0.09), 5.0)
	draw_line(base + Vector2(-14, -4), base + Vector2(14, 2), Color(0.28, 0.17, 0.10), 5.0)
	# Flame: layered flickering teardrops (outer orange -> inner yellow -> white core).
	#
	# ⚠ THE TALLEST OF THEM IS CAPPED AT `MOUTH_H - 18`. At 46 px x a 1.06 flicker the
	# outer teardrop reached 49 px, which fitted — but nothing in the file said so, and
	# the next person to make the fire bigger would have had it lick out through the
	# arch with no test to catch it. The cap makes "the flame is inside the furnace" a
	# property of the code rather than a coincidence of two numbers.
	var fh: float = minf(46.0 * flick, MOUTH_H - 18.0)
	_draw_flame(base + Vector2(0, -6), 20.0, fh, Color(1.0, 0.45, 0.12, 0.85), 0.0)
	_draw_flame(base + Vector2(0, -6), 13.0, fh * 0.74, Color(1.0, 0.72, 0.22, 0.9), 1.7)
	_draw_flame(base + Vector2(0, -6), 7.0, fh * 0.48, Color(1.0, 0.95, 0.6, 0.95), 3.1)
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
