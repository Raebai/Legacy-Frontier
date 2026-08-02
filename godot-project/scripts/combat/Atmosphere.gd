class_name Atmosphere
extends Node2D
## Net-new epic backdrop for the flat-ColorRect stages: a vertical GRADIENT sky,
## two layers of distant TOWER-SPIRE silhouettes (fits the Tower-of-God climb),
## slow drifting ambient MOTES, and a screen-space VIGNETTE for a cinematic
## frame. Built in code (house style — mirrors ScorchDecal's static-draw idiom).
## Call build(bounds, palette) from a stage's _build_background(). Themeable via
## the palette dict so floor themes can recolour it later.
##
## z layering: sky -30, spires -22 (this node's _draw), motes -21 — all behind
## the platforms (-5) + fighters (0). The vignette rides its own CanvasLayer
## above the world but below the HUD.

## Shared 2D-bloom environment (spell cores >1.0 radiate). Requires
## rendering/viewport/hdr_2d=true. Tune params in the .tres.
const GLOW_ENV_PATH: String = "res://scenes/combat/combat_glow.tres"

# ------------------------------------------------- ambient motes: the WARM-UP
## THE ARENA-ENTRY STALL, and why `preprocess` is now zero everywhere below.
##
## A drifting dust field has a chicken-and-egg problem: emission is continuous, so
## at t=0 no particles exist and the sky is empty for the first several seconds.
## `GPUParticles2D.preprocess` fixes that by simulating N seconds of the system
## before the first frame is shown — but it does it SYNCHRONOUSLY, by dispatching
## the particle compute shader `preprocess * fixed_fps` times inside the load
## frame. At the old `preprocess = 9.0` with the default 30 fixed_fps that is 270
## dispatches, twice (build_wash and _build_motes each own an emitter), in the one
## frame the arena opens. On a phone that is a multi-hundred-millisecond hitch at
## EVERY floor transition — the most-repeated moment in a tower climber.
##
## The fix keeps the look and moves the cost off the load frame: emit normally,
## but run the emitter FAST for a moment and then ease it back to real time. The
## same nine seconds of simulation happens, spread across ~90 render frames at a
## couple of dispatches each instead of 270 in one. `fixed_fps` also drops to 12,
## which is plenty for dust that moves at 3-14 px/s and cuts the ongoing per-frame
## simulation cost by 2.5x forever, not just during the warm-up.
const MOTE_WARMUP_SECONDS: float = 9.0   # simulated seconds the field needs to look full
const MOTE_WARMUP_REAL: float = 1.5      # real seconds we are willing to spend getting there
const MOTE_FIXED_FPS: int = 12           # dust does not need a 30 Hz simulation
## Mobile trims the field itself as well as the warm-up. These are small
## alpha-blended quads, and overdraw is the thing tile GPUs are worst at.
const MOTE_AMOUNT_WASH: int = 40
const MOTE_AMOUNT_WORLD: int = 48
const MOTE_AMOUNT_LOW: int = 16

## Untyped for the same reason DamageNumber._pool is: `build_wash` frees the
## previous floor's emitters and re-enrols new ones, so this array routinely holds
## a freed node, and reading one into a TYPED local raises an error that aborts
## the enclosing function.
var _warming: Array = []
var _warm_left: float = 0.0

## Fallback extent for the world-skyline mode, used only until `build()` is
## handed the caller's real bounds. Derived from LayoutDef's room_size rather
## than written as a literal: it used to read Rect2(0, 0, 1200, 760), which was
## the arena size at the time and silently became wrong the moment the default
## room shrank to 960x480 and started being driven by `LayoutDef.room_size`
## (Arena._apply_room_size). A default that tracks the real default cannot go
## stale again.
##
## ⚠ This does NOT affect the tower arena. That one uses `build_wash()`, which is
## SCREEN-space — its motes live on a CanvasLayer and are sized to the 640x360
## base viewport, so they are correct at any room size and must not be "fixed"
## into world coordinates. `build()` (the world skyline) is VersusArena's path,
## and it passes explicit bounds.
var _bounds: Rect2 = Rect2(Vector2.ZERO, LayoutDef.new().room_size)
var _sky_top: Color = Color(0.10, 0.13, 0.28)
var _sky_bottom: Color = Color(0.42, 0.60, 0.82)
var _sil_far: Color = Color(0.20, 0.24, 0.40)
var _sil_near: Color = Color(0.12, 0.15, 0.26)
var _accent: Color = Color(0.7, 0.85, 1.0)


## Add a WorldEnvironment (2D glow/bloom) under `parent` if it hasn't got one.
## Idempotent — safe to call once per arena _ready. Cheap screen post-process.
static func add_glow(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		if child is WorldEnvironment:
			return
	var env: Environment = load(GLOW_ENV_PATH)
	if env == null:
		return
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)


func build(bounds: Rect2, palette: Dictionary = {}) -> void:
	_bounds = bounds
	_sky_top = palette.get("sky_top", _sky_top)
	_sky_bottom = palette.get("sky_bottom", _sky_bottom)
	_sil_far = palette.get("silhouette_far", _sil_far)
	_sil_near = palette.get("silhouette_near", _sil_near)
	_accent = palette.get("accent", _accent)
	StageLayers.apply(self, StageLayers.SKYLINE)
	_build_sky()
	_build_motes()
	_build_vignette()
	queue_redraw()


# ------------------------------------------------------- screen-space WASH mode
## Themed atmosphere for the flat/box arena rooms (no world skyline): a faint
## colour tint + a theme-tinted vignette + drifting motes, all on a screen-space
## CanvasLayer. Re-callable per floor (clears first) so the climb re-tints as the
## band changes (surface -> underground -> sky). Use this instead of build().
func build_wash(tint: Color, accent: Color) -> void:
	for c: Node in get_children():
		c.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 1  # above the world, below the HUD (50/60/100)
	add_child(layer)
	# Faint flat colour tint (subtle — the room still reads through it).
	var flat := ColorRect.new()
	flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flat.color = Color(tint.r, tint.g, tint.b, 0.10)
	flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flat)
	# Theme-tinted vignette darkening the edges for depth.
	var grad := Gradient.new()
	grad.set_color(0, Color(tint.r * 0.4, tint.g * 0.4, tint.b * 0.5, 0.0))
	grad.set_color(1, Color(tint.r * 0.25, tint.g * 0.25, tint.b * 0.35, 0.55))
	grad.set_offset(0, 0.42)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	var vr := TextureRect.new()
	vr.texture = tex
	vr.stretch_mode = TextureRect.STRETCH_SCALE
	vr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vr)
	# Drifting ambient motes across the screen (accent dust).
	var motes := GPUParticles2D.new()
	motes.amount = _mote_amount(MOTE_AMOUNT_WASH)
	motes.lifetime = 9.0
	motes.position = Vector2(320, 180)  # viewport centre (640x360)
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(360.0, 220.0, 0.0)
	mat.direction = Vector3(0.15, -1.0, 0.0)
	mat.spread = 30.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 11.0
	mat.scale_min = 1.0
	mat.scale_max = 2.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(accent.r, accent.g, accent.b, 0.0))
	ramp.set_color(1, Color(accent.r, accent.g, accent.b, 0.0))
	ramp.add_point(0.5, Color(accent.r, accent.g, accent.b, 0.4))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	motes.process_material = mat
	layer.add_child(motes)
	_begin_warmup(motes)


# ------------------------------------------------------------------------ sky
func _build_sky() -> void:
	var grad := Gradient.new()
	grad.set_color(0, _sky_top)
	grad.set_color(1, _sky_bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)  # vertical top -> bottom
	tex.width = 8
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = _bounds.position
	rect.size = _bounds.size
	StageLayers.apply(rect, StageLayers.SKY)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)


# --------------------------------------------------------------- ambient motes
func _build_motes() -> void:
	var motes := GPUParticles2D.new()
	motes.amount = _mote_amount(MOTE_AMOUNT_WORLD)
	motes.lifetime = 9.0
	motes.position = _bounds.position + _bounds.size * 0.5
	StageLayers.apply(motes, StageLayers.MOTES)
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(_bounds.size.x * 0.5, _bounds.size.y * 0.5, 0.0)
	mat.direction = Vector3(0.1, -1.0, 0.0)
	mat.spread = 25.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 14.0
	mat.scale_min = 1.0
	mat.scale_max = 2.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(_accent.r, _accent.g, _accent.b, 0.0))
	ramp.set_color(1, Color(_accent.r, _accent.g, _accent.b, 0.0))
	# Fade in then out over life so motes twinkle rather than pop.
	ramp.add_point(0.5, Color(_accent.r, _accent.g, _accent.b, 0.5))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	motes.process_material = mat
	add_child(motes)
	_begin_warmup(motes)


# ------------------------------------------------------- the warm-up mechanism
## How many motes to emit. See MOTE_AMOUNT_LOW.
func _mote_amount(full: int) -> int:
	return MOTE_AMOUNT_LOW if TuningConfig.quality_is_low() else full


## Enrol an emitter in the spread-over-frames warm-up described at the top of the
## file. Explicitly zeroes `preprocess` rather than merely not setting it, because
## that zero IS the fix and a future edit that re-adds a preprocess value should
## have to delete this line to do it.
func _begin_warmup(p: GPUParticles2D) -> void:
	p.preprocess = 0.0
	p.fixed_fps = MOTE_FIXED_FPS
	p.speed_scale = MOTE_WARMUP_SECONDS / MOTE_WARMUP_REAL
	_warming.append(p)
	_warm_left = MOTE_WARMUP_REAL
	set_process(true)


func _process(delta: float) -> void:
	if _warm_left <= 0.0:
		return
	_warm_left -= delta
	if _warm_left > 0.0:
		return
	# Done: hand the field back to real time and stop paying for _process at all.
	for raw: Variant in _warming:
		if is_instance_valid(raw):
			(raw as GPUParticles2D).speed_scale = 1.0
	_warming.clear()
	set_process(false)


# -------------------------------------------------------------------- vignette
func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1  # above the world (layer 0), below the HUD (50/60/100)
	add_child(layer)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.02, 0.02, 0.05, 0.55))
	grad.set_offset(0, 0.5)  # clear centre until halfway, then darken to the edge
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)


# ---------------------------------------------------------------- spire skyline
## ⚠ THE "BLUE LINES". The maker played the versus stage and reported, verbatim:
## *"the blue lines mean I cant see anything they should be in the background of the
## map"*. These spires were them.
##
## Two things made a BACKGROUND element the loudest thing on screen. They were drawn
## in their palette colour at alpha 0.9 / 1.0, so at the played framing the near row
## sat at HIGHER contrast against the graded sky than the ledges did — and their
## colour is blue-grey, which is the hero's own hue. A row of tall blue bars, in the
## player's colour, standing exactly in the airspace he is trying to read platforms
## in. Nothing was wrong with the z-order; they were simply too PRESENT.
##
## The fix is atmospheric perspective as a rule rather than as a palette choice:
## every row is pushed toward the horizon colour by `StageLayers.haze` and drawn
## translucent, so distance is structural and a future theme cannot undo it by
## picking a punchy silhouette. The near row also loses height — it used to reach
## 150 px up, well into the jumping space.
## ⚠ HAZE TOWARD THE SKY AT THE SPIRE'S OWN HEIGHT, not toward `_sky_bottom`. The
## first pass at this fix lerped toward the gradient's bottom endpoint, which on the
## versus stage is a pale warm horizon colour several hundred pixels BELOW the
## skyline — so the spires came out LIGHTER than the sky they stood against and
## turned from blue bars into pale pickets. Rendered and looked at. Sampling the
## gradient at the baseline is what makes "recedes" true rather than hoped.
const HAZE_FAR: float = 0.86     # all but dissolved into the sky
const HAZE_NEAR: float = 0.70
const ALPHA_FAR: float = 0.5
const ALPHA_NEAR: float = 0.66
## ...and land just UNDER the sky's value afterwards. A distant mass that is lighter
## than the air in front of it reads as foreground, whichever hue it is.
const HAZE_DARKEN: float = 0.12


func _draw() -> void:
	var horizon: float = _bounds.position.y + _bounds.size.y * 0.60
	_draw_spires(horizon + 26.0, _recede(_sil_far, horizon + 26.0, HAZE_FAR),
		66.0, 30.0, 22.0, ALPHA_FAR)
	_draw_spires(horizon + 58.0, _recede(_sil_near, horizon + 58.0, HAZE_NEAR),
		104.0, 42.0, 30.0, ALPHA_NEAR)


## The sky gradient's colour at world y — the same lerp `_build_sky`'s texture bakes.
func _sky_at(y: float) -> Color:
	if _bounds.size.y <= 0.0:
		return _sky_bottom
	return _sky_top.lerp(_sky_bottom,
		clampf((y - _bounds.position.y) / _bounds.size.y, 0.0, 1.0))


func _recede(col: Color, at_y: float, amount: float) -> Color:
	return StageLayers.haze(col, _sky_at(at_y), amount).darkened(HAZE_DARKEN)


## A row of distant tower spires (rect body + pointed cap) across the bounds
## width. Heights vary deterministically (sin of x) so the skyline is stable
## frame-to-frame. `col`+`alpha` set the depth shade; bodies extend well below
## the view so no gap shows under them.
func _draw_spires(baseline: float, col: Color, max_h: float, w: float, gap: float, alpha: float) -> void:
	var c := Color(col.r, col.g, col.b, alpha)
	var x: float = _bounds.position.x - 120.0
	var i: int = 0
	var right: float = _bounds.position.x + _bounds.size.x + 120.0
	while x < right:
		var h: float = max_h * (0.35 + 0.65 * absf(sin(x * 0.011 + float(i) * 1.7)))
		draw_rect(Rect2(x, baseline - h, w, h + 400.0), c)  # body extends down past view
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, baseline - h),
			Vector2(x + w, baseline - h),
			Vector2(x + w * 0.5, baseline - h - w * 0.85),
		]), c)  # pointed cap
		# A faint lit window strip so the far towers read as structures.
		if alpha >= 1.0:
			draw_rect(Rect2(x + w * 0.4, baseline - h * 0.7, w * 0.2, h * 0.5),
				Color(_accent.r, _accent.g, _accent.b, 0.06))
		x += w + gap
		i += 1
