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

var _bounds: Rect2 = Rect2(0, 0, 1200, 760)
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
	z_index = -22
	z_as_relative = false
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
	motes.amount = 40
	motes.lifetime = 9.0
	motes.preprocess = 9.0
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
	rect.z_index = -30
	rect.z_as_relative = false
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)


# --------------------------------------------------------------- ambient motes
func _build_motes() -> void:
	var motes := GPUParticles2D.new()
	motes.amount = 48
	motes.lifetime = 9.0
	motes.preprocess = 9.0  # already spread across the sky when the scene opens
	motes.position = _bounds.position + _bounds.size * 0.5
	motes.z_index = -21
	motes.z_as_relative = false
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
func _draw() -> void:
	var horizon: float = _bounds.position.y + _bounds.size.y * 0.60
	_draw_spires(horizon + 26.0, _sil_far, 90.0, 30.0, 22.0, 0.9)
	_draw_spires(horizon + 58.0, _sil_near, 150.0, 42.0, 30.0, 1.0)


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
