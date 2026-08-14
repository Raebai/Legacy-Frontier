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
##
## ⚠ THE "WEIRD BLINDS COVERING THE FRONT OF THE MAP". The tower's floors call
## `build_wash()`, never `build()` — they have no world skyline, only a screen-space
## grade. But `_draw` painted the spires ANYWAY: a CanvasItem gets one draw pass on
## entering the tree whether or not anyone asked for it, and only `build()` ever
## parked this node on `SKYLINE`. So every tower floor got two rows of tall
## translucent blue-grey bars, at the DEFAULT z of 0 — the fighters' own rung —
## standing across the whole room and extending 400 px below it. That is the maker's
## "blinds", and it is the same bug `StageLayers` was written to close, reappearing
## on the one stage drawer the drawer scanner cannot see (it matches `extends
## StaticBody2D`, and this is a Node2D).
##
## Two independent fixes, because either alone would leave the trap armed:
##   1. `_skyline` gates `_draw`. It defaults to FALSE and only `build()` raises it,
##      so a bare `Atmosphere.new()` — which is exactly what the Arena makes — paints
##      nothing at all rather than painting a skyline nobody ordered.
##   2. `_ready` parks this node on `SKYLINE` unconditionally, so even a future draw
##      that slips past rule 1 lands in the background where it belongs. This node is
##      also now REGISTERED in `StageLayers.DRAWERS`, which is what makes rule 2 a
##      build failure rather than a comment.

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
##
## ⚠ THE WASH FIELD IS SMALLER THAN THE WORLD ONE, AND NOT FOR PERFORMANCE. The wash
## emitter lives on a CanvasLayer ABOVE the world, so its motes are drawn in front of
## the fighters — 40 of them, in the floor's ACCENT colour (floor 1's is a warm
## orange), drifting over a fight whose enemies are also warm. On the versus stage the
## same field sits in world space behind everything, where it is depth; here it was
## 40 moving objects competing with the ones you have to react to. Cut to a level that
## still reads as air and no longer reads as things.
const MOTE_AMOUNT_WASH: int = 22
const MOTE_AMOUNT_WORLD: int = 48
const MOTE_AMOUNT_LOW: int = 16

## The hard ceiling weather takes on LOW — a cap, not a proportional trim, because
## the weather field is BIGGER and FASTER than the dust and sits in the same place
## (in front of the fighters). `RAIN` asks for 40 and is the reason this is a `mini`
## rather than a scale factor: proportional thinning would still leave the densest
## floor the densest thing on a phone.
const WEATHER_AMOUNT_LOW: int = 10

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
## Does this Atmosphere own a WORLD SKYLINE? Only `build()` says yes. See the ⚠ block
## at the top of the file — this is the gate that keeps the spires off the tower.
var _skyline: bool = false


## Park on the SKYLINE rung the moment this node exists, not when someone remembers
## to call `build()`. An Atmosphere is background by definition; there is no mode in
## which it should share a rung with a fighter.
func _ready() -> void:
	StageLayers.apply(self, StageLayers.SKYLINE)


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
	_skyline = true          # THE ONLY PLACE THIS IS RAISED. See the ⚠ block above.
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
	# ⚠ LIGHTER AND STARTING FURTHER OUT THAN IT WAS (0.55 alpha from 0.42 of the
	# radius). Two things changed under it: the arena grew to 1220x560 and
	# `CombatCamera.FRAME_ZOOM_MIN` dropped to 0.42 to frame it, so fighters now spend
	# far more of the fight near the screen EDGE — which is precisely where this was
	# crushing to near-black. It is also not the only vignette on screen; `PostProcess`
	# lays its own filmic one over the top, and two stacked vignettes on a floor whose
	# wash is already (0.20, 0.18, 0.19) is how a room ends up unreadable in the corners.
	var grad := Gradient.new()
	grad.set_color(0, Color(tint.r * 0.4, tint.g * 0.4, tint.b * 0.5, 0.0))
	grad.set_color(1, Color(tint.r * 0.25, tint.g * 0.25, tint.b * 0.35, 0.34))
	grad.set_offset(0, 0.56)
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
	# Dimmer peak than the world field's 0.5, for the same reason the count is lower:
	# these are IN FRONT of the fighters. See MOTE_AMOUNT_WASH.
	ramp.add_point(0.5, Color(accent.r, accent.g, accent.b, 0.26))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	motes.process_material = mat
	layer.add_child(motes)
	_begin_warmup(motes)


# -------------------------------------------------------------------- weather
## THE FLOOR'S AIR — what falls, drifts or rises through it. Ash over the ash verge,
## leaves over the green tier, embers rising out of the hot rooms, bubbles in the
## drowned one. `kind` is an `EnvTheme.Weather` ordinal, passed as a plain int so
## this combat script does not pull `scripts/tower/` into its compile graph.
##
## ⚠ CALL IT AFTER `build_wash`, NEVER BEFORE. `build_wash` frees every child of this
## node (`:149-150`), so weather built first is weather deleted before it draws.
##
## ⚠ ITS OWN CanvasLayer, AND THE NUMBER MATTERS. Layer 2 — in front of the wash tint
## and its vignette (layer 1), behind the `PostProcess` grade (layer 8) so the floor's
## colour treatment lands on the weather too rather than the weather sitting outside
## the picture. Everything from 40 up is HUD.
##
## ⚠ IT IS GARNISH AND IT DEFERS TO THE FIGHT. This field is drawn IN FRONT of the
## fighters, and the argument that cut the wash motes from 40 to 22 applies here with
## more force: these are bigger and they move faster. So the counts below are already
## the restrained version, `RAIN` — the only dense one — is the first thing cut on
## LOW, and nothing here carries information a player must react to. `ElementFx` is
## the opposite case and says so in its own header; the element read is not garnish
## and is not on this ramp.
func build_weather(kind: int, accent: Color) -> void:
	if kind <= 0:  # EnvTheme.Weather.NONE
		return
	var p: Dictionary = _weather_params(kind, accent)
	if p.is_empty():
		return
	# ⚠ RELEASE THE NAME BEFORE CLAIMING IT. `build_wash` frees the previous floor's
	# children with `queue_free()`, which is DEFERRED — the old Weather layer is still
	# in the tree when this runs one line later. Adding a second child called "Weather"
	# makes Godot silently rename the NEW one ("@Weather@2"), so from the second floor
	# onward `get_node("Weather")` returned the dying layer instead of the live one.
	#
	# It cost nothing in the game (nothing looks the layer up by name) and it wrecked
	# the perf probe, whose particle counts came back 34 / 0 / 42 / 0 — every other
	# floor reading zero, which is the signature of this and not of a build failure.
	# Renaming the corpse is one line and removes a whole class of confusion from the
	# remote scene tree as well.
	var stale: Node = get_node_or_null("Weather")
	if stale != null:
		stale.name = "WeatherStale"
	var layer := CanvasLayer.new()
	layer.name = "Weather"
	layer.layer = 2
	add_child(layer)
	var fall := GPUParticles2D.new()
	fall.amount = _weather_amount(int(p["amount"]))
	fall.lifetime = float(p["life"])
	# ⚠ TEXTURED, AND THAT IS WHY THE SCALES BELOW LOOK SMALL. An UNTEXTURED
	# GPUParticles2D draws a ONE-PIXEL point, so `scale` is measured in pixels and a
	# "scale 2.4" flake is 2.4 px — invisible. The first render of this field was a
	# sheet of empty rooms for exactly that reason. With a `PARTICLE_PX` texture the
	# scale is a FRACTION of that size instead, so a leaf at 0.55 is ~11 px and reads.
	# `CombatVfx` learned the same lesson and says so in its own header: the untextured
	# default "was the whole game's blocky confetti look".
	match String(p["shape"]):
		"leaf": fall.texture = _leaf_texture()
		"streak": fall.texture = _streak_texture()
		_: fall.texture = _dot_texture()
	# Emitted across a box wider and taller than the 640x360 base viewport so the
	# field is already full at the edges instead of visibly starting inside frame.
	fall.position = Vector2(320.0, 180.0)
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(380.0, 240.0, 0.0)
	mat.direction = Vector3(float(p["dir_x"]), float(p["dir_y"]), 0.0)
	mat.spread = float(p["spread"])
	mat.gravity = Vector3(0.0, float(p["grav"]), 0.0)
	mat.initial_velocity_min = float(p["vel_min"])
	mat.initial_velocity_max = float(p["vel_max"])
	mat.scale_min = float(p["scale_min"])
	mat.scale_max = float(p["scale_max"])
	# TUMBLE. A leaf that falls without rotating reads as a falling seed, and a rain
	# streak that rotates reads as debris — so the spin is per-kind and most kinds
	# take zero. `angle` seeds the starting rotation so a field does not begin with
	# every particle aligned.
	var spin: float = float(p["spin"])
	if spin > 0.0:
		mat.angle_min = -180.0
		mat.angle_max = 180.0
		mat.angular_velocity_min = -spin
		mat.angular_velocity_max = spin
	var col: Color = p["color"]
	var peak: float = float(p["alpha"])
	# Fades in and out over its life so nothing pops into or out of existence at the
	# frame edge — the same shape as the mote ramp above.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.22, Color(col.r, col.g, col.b, peak))
	ramp.add_point(0.78, Color(col.r, col.g, col.b, peak))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	fall.process_material = mat
	layer.add_child(fall)
	# ⚠ NOT OPTIONAL. `slice_test_mobile_config` walks every GPUParticles2D under an
	# Atmosphere and asserts preprocess == 0, fixed_fps == MOTE_FIXED_FPS and a
	# warm-up speed_scale > 1. A `preprocess` here would re-add the multi-hundred-ms
	# stall at every floor transition that `_begin_warmup` exists to have removed.
	_begin_warmup(fall)


## How many particles this field may have. Weather is the first thing to go on a
## phone: it is in front of the fighters and it is pure garnish, so LOW takes a hard
## cap rather than the proportional trim `_mote_amount` applies to dust.
func _weather_amount(full: int) -> int:
	return mini(full, WEATHER_AMOUNT_LOW) if TuningConfig.quality_is_low() else full


## Per-kind physics + palette. Read as a table: each row is "what this air DOES".
##
## ⚠ EVERY VELOCITY IS SIZED FOR A 12 Hz SIMULATION (`MOTE_FIXED_FPS`). At 12 fps a
## particle moving 140 px/s jumps ~12 px between frames and reads as a dashed line
## rather than rain. Nothing here exceeds ~70 px/s for that reason — the fix for
## "rain looks steppy" is a slower drop, not a faster simulation, because the fps is
## test-pinned and the stall it prevents is worse than the stepping.
## ⚠ `scale` IS A FRACTION OF `PARTICLE_PX` (32), NOT A PIXEL COUNT. A leaf at 0.34
## is ~11 px; a snowflake at 0.14 is ~4.5 px. Read the comment on `fall.texture`
## before adjusting any of these — the first version of this table was written
## against an untextured emitter, where the same numbers meant single pixels and the
## whole field was invisible.
func _weather_params(kind: int, accent: Color) -> Dictionary:
	var white := Color(0.92, 0.95, 1.0)
	match kind:
		1:  # ASH — grey flakes, slow, falling
			return {"dir_x": 0.10, "dir_y": 1.0, "spread": 20.0, "grav": 6.0,
				"vel_min": 12.0, "vel_max": 24.0, "scale_min": 0.07, "scale_max": 0.15,
				"amount": 34, "life": 5.5, "alpha": 0.52, "shape": "dot", "spin": 0.0,
				"color": Color(0.74, 0.72, 0.70)}
		2:  # LEAVES — broad, tumbling, warm; the widest spread in the table
			return {"dir_x": 0.35, "dir_y": 1.0, "spread": 42.0, "grav": 9.0,
				"vel_min": 16.0, "vel_max": 32.0, "scale_min": 0.26, "scale_max": 0.46,
				"amount": 30, "life": 6.0, "alpha": 0.92, "shape": "leaf", "spin": 90.0,
				"color": accent}
		3:  # SNOW — white, slow, wide drift
			return {"dir_x": 0.15, "dir_y": 1.0, "spread": 30.0, "grav": 4.0,
				"vel_min": 9.0, "vel_max": 19.0, "scale_min": 0.10, "scale_max": 0.22,
				"amount": 42, "life": 7.5, "alpha": 0.82, "shape": "dot", "spin": 0.0,
				"color": white}
		4:  # EMBERS — small, RISING, hot
			return {"dir_x": 0.05, "dir_y": -1.0, "spread": 24.0, "grav": -7.0,
				"vel_min": 14.0, "vel_max": 28.0, "scale_min": 0.06, "scale_max": 0.13,
				"amount": 30, "life": 4.5, "alpha": 0.90, "shape": "dot", "spin": 0.0,
				"color": accent}
		5:  # BUBBLES — round, rising, slow
			return {"dir_x": 0.05, "dir_y": -1.0, "spread": 15.0, "grav": -5.0,
				"vel_min": 8.0, "vel_max": 17.0, "scale_min": 0.11, "scale_max": 0.26,
				"amount": 24, "life": 6.5, "alpha": 0.52, "shape": "dot", "spin": 0.0,
				"color": accent}
		6:  # RAIN — fast, steep, thin; the only STREAK and the densest field here
			return {"dir_x": 0.20, "dir_y": 1.0, "spread": 7.0, "grav": 28.0,
				"vel_min": 44.0, "vel_max": 68.0, "scale_min": 0.22, "scale_max": 0.40,
				"amount": 52, "life": 3.0, "alpha": 0.50, "shape": "streak", "spin": 0.0,
				"color": accent}
		7:  # GLINT — sparse hanging motes; still, enclosed air
			return {"dir_x": 0.10, "dir_y": -1.0, "spread": 48.0, "grav": 0.0,
				"vel_min": 2.0, "vel_max": 7.0, "scale_min": 0.08, "scale_max": 0.18,
				"amount": 20, "life": 9.0, "alpha": 0.54, "shape": "dot", "spin": 0.0,
				"color": accent}
		8:  # STARFALL — slow gold drift, sparse
			return {"dir_x": 0.25, "dir_y": 1.0, "spread": 22.0, "grav": 2.0,
				"vel_min": 5.0, "vel_max": 13.0, "scale_min": 0.09, "scale_max": 0.20,
				"amount": 24, "life": 8.5, "alpha": 0.76, "shape": "dot", "spin": 0.0,
				"color": accent}
	return {}


# --------------------------------------------------------- particle silhouettes
## Edge length of the generated particle textures. Scales in `_weather_params` are
## fractions of this, so changing it rescales every field at once.
const PARTICLE_PX: int = 32

static var _dot_tex: Texture2D = null
static var _streak_tex: Texture2D = null
static var _leaf_tex: Texture2D = null


## A LEAF, and it needs its own silhouette rather than a tint on the dot.
##
## ⚠ THE FIRST VERSION OF THIS FIELD USED THE SOFT DOT AND READ AS FIRELIES. That is
## not a figure of speech — a round shape with a squared alpha falloff IS a firefly,
## and `HubAmbience` already builds actual fireflies that way. Foliage needs an
## elongated blade with a defined EDGE: the eye reads "leaf" from the outline and
## from the fact that it tumbles, never from its colour.
##
## Drawn as a pointed oval — widest at the middle, tapering to both ends — with a
## nearly hard rim (the `smoothstep` band is ~1.5 px) so it is a shape rather than a
## glow. Paired with `angular_velocity` at the call site; a leaf that falls without
## rotating reads as a falling seed.
static func _leaf_texture() -> Texture2D:
	if _leaf_tex != null:
		return _leaf_tex
	var img := Image.create(PARTICLE_PX, PARTICLE_PX, false, Image.FORMAT_RGBA8)
	var c: float = float(PARTICLE_PX) * 0.5
	for y: int in PARTICLE_PX:
		for x: int in PARTICLE_PX:
			var ny: float = (float(y) - c + 0.5) / c        # -1 .. 1 along the blade
			var nx: float = (float(x) - c + 0.5) / c        # -1 .. 1 across it
			# Half-width at this point along the blade: a lens, zero at both tips.
			var half: float = 0.42 * sqrt(maxf(0.0, 1.0 - ny * ny))
			var d: float = absf(nx) - half
			# Hard-ish edge: opaque inside, ~1.5 px of anti-aliasing at the rim.
			var a: float = 1.0 - smoothstep(-0.03, 0.03, d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_leaf_tex = ImageTexture.create_from_image(img)
	return _leaf_tex


## A soft round flake — falls off to nothing at the rim so it reads as a mote of
## something rather than a sprite. Built once and shared by every field; the same
## discipline as `CombatVfx._dot_tex`, which exists for the same reason.
static func _dot_texture() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var img := Image.create(PARTICLE_PX, PARTICLE_PX, false, Image.FORMAT_RGBA8)
	var c: float = float(PARTICLE_PX) * 0.5
	for y: int in PARTICLE_PX:
		for x: int in PARTICLE_PX:
			var d: float = Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c
			# squared falloff: a solid middle with a soft rim, not a linear blur
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


## A vertical streak for RAIN. A round dot falling at 68 px/s reads as hail; the
## streak is what makes the same motion read as water. Narrow and soft-ended.
static func _streak_texture() -> Texture2D:
	if _streak_tex != null:
		return _streak_tex
	var img := Image.create(PARTICLE_PX, PARTICLE_PX, false, Image.FORMAT_RGBA8)
	var c: float = float(PARTICLE_PX) * 0.5
	for y: int in PARTICLE_PX:
		for x: int in PARTICLE_PX:
			# across: tight. along: full height, fading at both ends.
			var ax: float = clampf(1.0 - absf(float(x) - c + 0.5) / 2.2, 0.0, 1.0)
			var ay: float = clampf(1.0 - absf(float(y) - c + 0.5) / c, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, ax * ax * sqrt(ay)))
	_streak_tex = ImageTexture.create_from_image(img)
	return _streak_tex


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
	# A wash-mode Atmosphere has no skyline to draw. Returning here rather than
	# relying on the z-order is deliberate: the tower's room is only ~980x500, so a
	# spire row inside it is a wall of bars whether it is in front of the fight or
	# behind it. Not drawing them is the difference between "receded" and "absent",
	# and absent is what a screen-space wash wants.
	if not _skyline:
		return
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
