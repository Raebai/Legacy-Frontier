class_name SkyVista
extends Node2D
## THE FLOOR'S SKY — a great clerestory band opened in the back wall, with weather
## moving through it. Maker: *"build the sunset and eclipse make them beautiful and
## moving along with the sky and world"*.
##
## `FloorDecor` says WHERE you are, `Atmosphere.build_weather` says what the air is
## DOING, and this says what is BEYOND. It is the only one of the three that changes
## while you stand still, which is what makes a room feel like a place rather than a
## backdrop.
##
## ══ WHY A BAND, AND NOT A WINDOW OR A WHOLE SKY ═══════════════════════════════
## Three constraints meet here and the band is the only shape that satisfies all of
## them without a clipping pass.
##
##   1. THE ROOMS ARE INTERIORS. `RoomShell` paints the room's air as an OPAQUE rect
##      at `StageLayers.TERRAIN` (-6), and `FloorDecor` paints an opaque wall over
##      the whole room at `DECOR` (-5). Anything drawn BEHIND either is invisible, so
##      "put a sky at the back" is not available — the sky has to be an OPENING cut
##      into the wall, drawn OVER it.
##   2. THERE IS NO FREE RUNG TO PUT IT ON. The only unclaimed visible rung in a
##      tower room is -2, which is in FRONT of `PLATFORM` (-4) and `COVER` (-3) — a
##      sky there would draw over the ledges and the crates. So this shares `DECOR`
##      with `FloorDecor` and relies on TREE ORDER: `Arena` adds it after, so the
##      wall's ribs and motif are already down and this lands on top of them.
##   3. NOTHING MAY SPILL OUTSIDE THE OPENING. Godot's `draw_*` does not clip, and
##      the alternatives are a `clip_children` backbuffer pass or masking with
##      wall-coloured rects — and the mask would erase `FloorDecor`'s ribs and motif
##      in exactly the region it covered.
##
## A FULL-WIDTH HORIZONTAL BAND removes the third problem by construction rather
## than by machinery: every shape drawn inside it is bounded by clamping ONE axis.
## The sun is placed so its halo fits the band's height; clouds are horizontal, so
## they fit by definition; stars are points. Nothing needs clipping because nothing
## can leave.
##
## It also happens to be the right picture. A band of light across the upper wall,
## with mullions standing in it, reads as a clerestory — the row of high windows a
## real tower would carry — and it puts the sky where a climber looks.
##
## ══ THE TWO TRAPS THIS FILE INHERITS ══════════════════════════════════════════
## ⚠ A CanvasItem GETS ONE DRAW PASS ON ENTERING THE TREE whether or not anyone
## called a build method. That is the "weird blinds" bug (`Atmosphere.gd:14-32`) and
## the reason `FloorDecor` carries a `_built` flag. Both guards are here and they are
## INDEPENDENT: `_built` gates `_draw`, and `_ready` parks the z unconditionally, so
## a draw that slips past the first still lands in the background.
##
## ⚠ NOTHING RANDOM. Every position is hashed pseudo-noise (`_h`, lifted verbatim
## from `FloorDecor`, which lifted it from `ArenaTerrain`) and every motion is a pure
## function of elapsed time. A `_draw` that rolls dice shimmers between frames, and
## in co-op two phones paint different skies.
##
## ⚠ AND IT MUST DEGRADE. This redraws every frame, which is the one thing the rest
## of the stage layer does not do. LOW cuts the gradient to a third of its bands,
## drops the cloud parallax to a single layer, halves the stars and stops them
## twinkling. What it never drops is the gradient itself or the celestial body: those
## ARE the sky, and a floor with no sky is a different floor rather than a cheaper one
## — the same rule `FloorDecor` states for its structural elements.

## Which sky. Mirrors `EnvTheme.Sky`; taken as a plain int so this combat script does
## not pull `scripts/tower/` into its compile graph.
const KIND_NONE: int = 0
const KIND_SUNSET: int = 1
const KIND_ECLIPSE: int = 2

## The band, as a fraction of the wall's height. Top edge and bottom edge.
## Sized so the band clears the tallest authored ledge and still leaves the wall
## reading as a wall above and below it.
const BAND_TOP: float = 0.06
const BAND_BOTTOM: float = 0.46

## Gradient resolution. The sky is painted as horizontal strips rather than as a
## texture so the palette can shift with the sun's height without rebuilding an
## image every frame; 22 strips is past the point the eye finds the seams.
const BANDS_HIGH: int = 22
const BANDS_LOW: int = 8

## How far the mullions stand apart, in pixels of wall. They are what make the band
## read as ARCHITECTURE instead of as a stripe of colour painted on a wall.
const MULLION_SPACING: float = 232.0
const MULLION_W: float = 13.0

## One full sun traverse, in seconds. Deliberately long: the sky should be different
## when you look up again, not animated at you.
const SUN_CYCLE: float = 220.0
## Cloud layers and how fast each drifts, slowest first. Parallax is the whole reason
## there is more than one — a single layer reads as a texture sliding.
const CLOUD_SPEED: Array[float] = [3.0, 6.5, 11.0, 17.0]
const CLOUDS_PER_LAYER_HIGH: int = 5
const CLOUDS_PER_LAYER_LOW: int = 3

const STARS_HIGH: int = 74
const STARS_LOW: int = 30
## Corona ray count and how far they reach past the disc, as a fraction of its radius.
const CORONA_RAYS: int = 28
const CORONA_REACH: float = 0.85

var room_size: Vector2 = Vector2(960, 480)
var tint: Color = Color(0.20, 0.18, 0.19)
var accent: Color = Color(0.85, 0.55, 0.35)
var kind: int = KIND_NONE

## Has anyone actually asked for a sky? A bare `SkyVista.new()` must paint nothing —
## see the ⚠ block above.
var _built: bool = false
## Elapsed seconds. The only thing that moves.
var _t: float = 0.0


func _ready() -> void:
	StageLayers.apply(self, StageLayers.DECOR)
	set_process(false)


## Open (or re-open) the sky for a floor. Safe to call repeatedly on the same node —
## the tower rebuilds every floor through this, exactly as `FloorDecor.build` is.
func build(size: Vector2, room_tint: Color, room_accent: Color, sky_kind: int) -> void:
	room_size = size
	if room_tint.a > 0.0:
		tint = room_tint
	if room_accent.a > 0.0:
		accent = room_accent
	kind = sky_kind
	_built = kind != KIND_NONE
	StageLayers.apply(self, StageLayers.DECOR)
	# A floor with no sky pays NOTHING — no process, no draw. Most floors are sealed
	# rooms and this is the common case, so it is the one that must be free.
	set_process(_built)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ------------------------------------------------------------------ the drawing
func _draw() -> void:
	if not _built:
		return
	var w: float = room_size.x
	var ground_y: float = room_size.y - 40.0
	var top: float = ground_y * BAND_TOP
	var bottom: float = ground_y * BAND_BOTTOM
	var band := Rect2(0.0, top, w, bottom - top)
	var low: bool = TuningConfig.quality_is_low()

	match kind:
		KIND_SUNSET:
			_draw_sunset(band, low)
		KIND_ECLIPSE:
			_draw_eclipse(band, low)
		_:
			return

	# The opening's own edges, drawn LAST so they sit over whatever the sky did at
	# the rim. A lintel above and a sill below turn a rectangle of colour into a
	# hole in a wall.
	var stone: Color = tint.darkened(0.42)
	draw_rect(Rect2(band.position.x, band.position.y - 9.0, band.size.x, 9.0), stone, true)
	draw_rect(Rect2(band.position.x, band.end.y, band.size.x, 13.0), stone, true)
	# The sill catches the light coming through — a warm lip under the opening. This
	# is the one line that ties the sky to the ROOM rather than leaving it a picture.
	draw_rect(Rect2(band.position.x, band.end.y, band.size.x, 3.0),
		Color(accent.r, accent.g, accent.b, 0.55), true)

	# Mullions. Standing in the opening, not painted over it — drawn in the wall's own
	# stone so they read as structure the sky is behind.
	var count: int = maxi(2, int(w / MULLION_SPACING))
	for i: int in range(1, count):
		var mx: float = w * float(i) / float(count) - MULLION_W * 0.5
		draw_rect(Rect2(mx, band.position.y, MULLION_W, band.size.y), stone, true)
		draw_rect(Rect2(mx + MULLION_W - 3.0, band.position.y, 3.0, band.size.y),
			tint.darkened(0.6), true)


# ------------------------------------------------------------------------ SUNSET
## Warm gradient, a low sun sinking across the opening, four parallax cloud layers
## and a shaft of light on the sill. The palette is built FROM the floor's own accent
## rather than from fixed oranges, so a sunset over the green tier stays green-golden
## and the same code over a red floor would burn red. The sky belongs to the biome.
func _draw_sunset(band: Rect2, low: bool) -> void:
	# Sun height: 1 at the top of its arc, 0 at the sill. Slow, and it never fully
	# sets — a floor that goes dark while you fight in it is a lighting change, not
	# atmosphere.
	var phase: float = fposmod(_t / SUN_CYCLE, 1.0)
	var height: float = 0.30 + 0.55 * (0.5 + 0.5 * cos(phase * TAU))
	# ⚠ CLAMPED INSIDE THE BAND, DISC AND HALO TOGETHER. The first render had the sun
	# sliced clean off by the lintel: the arc's top reached above `band.position.y`
	# and nothing stopped it. The whole reason this is a horizontal band is that
	# clamping ONE axis is sufficient to keep everything inside (see the header) —
	# so this is that clamp, and the inset is the HALO's radius, not the disc's,
	# because the halo is the part that reads first.
	var halo_r: float = band.size.y * 0.135 * 1.55
	var sun := Vector2(
		band.position.x + band.size.x * (0.16 + 0.68 * phase),
		clampf(band.end.y - band.size.y * height * 0.82,
			band.position.y + halo_r + 3.0, band.end.y - halo_r * 0.5))

	# ⚠ THE PALETTE IS BUILT FROM THE FLOOR'S ACCENT, AND THE FIRST VERSION ONLY
	# CLAIMED TO BE. It multiplied the accent's blue by 0.42, which crushes any cool
	# hue to orange — so Frostmarch's pale blue accent and Verdant's yellow-green one
	# produced the SAME sunset, and the comment saying otherwise was simply wrong. It
	# was caught by rendering both side by side and seeing two identical skies.
	#
	# Now the horizon LEANS on the accent instead of being multiplied by it: a warm
	# base lerped most of the way toward the floor's own colour, so the green tier
	# gets a golden-green evening and the snowfield a pale, cold one from this same
	# code. The upper sky stays a deep twilight for all of them, because a sunset
	# whose ZENITH also changes stops reading as a sunset.
	var warm := Color(1.55, 1.02, 0.46, 1.0)
	var horizon: Color = warm.lerp(
		Color(accent.r * 1.30, accent.g * 1.26, accent.b * 1.22, 1.0), 0.62)
	var mid: Color = Color(
		lerpf(0.86, horizon.r * 0.72, 0.5),
		lerpf(0.34, horizon.g * 0.52, 0.5),
		lerpf(0.30, horizon.b * 0.62, 0.5), 1.0)
	var high := Color(0.10 + accent.b * 0.10, 0.06, 0.20 + accent.b * 0.12, 1.0)
	var low_c: Color = horizon
	_gradient(band, high, mid, low_c, low)

	# The glow the sun spills across the whole lower sky, before the disc itself, so
	# clouds crossing it are lit from behind.
	var glow_r: float = band.size.y * 0.92
	for i: int in 5:
		var f: float = 1.0 - float(i) / 5.0
		draw_circle(sun, glow_r * f,
			Color(low_c.r, low_c.g * 0.9, low_c.b * 0.7, 0.055 * f))

	if not low:
		_clouds(band, sun, low_c, 4)
	else:
		_clouds(band, sun, low_c, 1)

	# The disc. HDR (>1) so the bloom pass makes it burn rather than sit there as a
	# flat circle — the same trick the spell cores use.
	var disc_r: float = band.size.y * 0.135
	draw_circle(sun, disc_r * 1.55, Color(low_c.r, low_c.g * 0.8, low_c.b * 0.5, 0.30))
	draw_circle(sun, disc_r, Color(1.7, 1.35, 0.82, 1.0))

	# The path the light lays on the sill, brightest under the sun. Sold cheaply: a
	# few overlapping soft rects rather than a real shaft.
	if not low:
		for i: int in 4:
			var half: float = band.size.x * (0.06 + 0.05 * float(i))
			draw_rect(Rect2(sun.x - half, band.end.y - 4.0, half * 2.0, 4.0),
				Color(low_c.r, low_c.g, low_c.b, 0.16 - 0.03 * float(i)), true)


# ----------------------------------------------------------------------- ECLIPSE
## A black disc with a living corona over a bruised sky, stars out in the middle of
## the day, and the light going wrong. The Apex's sky, and the one that should make a
## climber stop.
func _draw_eclipse(band: Rect2, low: bool) -> void:
	var high := Color(0.04, 0.03, 0.09, 1.0)
	var mid := Color(0.12, 0.07, 0.20, 1.0)
	var horizon := Color(
		minf(accent.r * 0.55 + 0.10, 1.0),
		accent.g * 0.28,
		minf(accent.b * 0.50 + 0.14, 1.0), 1.0)
	_gradient(band, high, mid, horizon, low)

	_stars(band, low)

	# ⚠ CENTRED AND SIZED SO THE CORONA FITS, NOT SO THE DISC DOES. The first render
	# had the crown sliced off by the lintel: the disc at 0.42 of the band with
	# r = 0.20 sits comfortably inside, but a ray reaches
	# `r * (1 + CORONA_REACH * 1.45)` = 2.23r at full flicker, which is 0.446 of the
	# band — further above the centre than the centre is below the top edge.
	# At 0.50 and r = 0.18 the longest possible ray ends at 0.10 of the band and the
	# whole crown clears. Sizing to the DISC is the mistake; the corona is the part
	# that reads, and it is twice the radius.
	var centre := Vector2(band.position.x + band.size.x * 0.5,
		band.position.y + band.size.y * 0.50)
	var r: float = band.size.y * 0.18

	# ── THE CORONA, and it is drawn BEFORE the disc on purpose: the rays come from
	# behind the moon, so the disc must land on top of their inner ends and cut them
	# off cleanly. Drawing them after would leave every ray crossing the black face.
	var breathe: float = 0.86 + 0.14 * sin(_t * 1.15)
	var spin: float = _t * 0.06
	for i: int in CORONA_RAYS:
		var a: float = TAU * float(i) / float(CORONA_RAYS) + spin
		# Each ray keeps its own length and its own flicker rate, hashed off its
		# index so the crown is uneven the way a real one is.
		var seed_a: float = _h(i, 17)
		var seed_b: float = _h(i, 41)
		var flick: float = 0.72 + 0.28 * sin(_t * (1.4 + seed_b * 2.6) + seed_a * TAU)
		var reach: float = r * (1.0 + CORONA_REACH * (0.45 + seed_a) * flick * breathe)
		var from: Vector2 = centre + Vector2(cos(a), sin(a)) * r * 0.98
		var to: Vector2 = centre + Vector2(cos(a), sin(a)) * reach
		draw_line(from, to, Color(1.5, 1.25, 1.9, 0.34 + 0.26 * seed_b),
			1.0 + 2.4 * seed_a)

	# The inner glow ring, HDR so it blooms into a halo.
	for i: int in 4:
		var f: float = 1.0 - float(i) / 4.0
		draw_arc(centre, r * (1.02 + 0.10 * float(i)), 0.0, TAU, 48,
			Color(1.6, 1.3, 2.0, 0.42 * f * breathe), 2.2 + 1.4 * f, true)

	# The moon. Not pure black — a disc of true black on a dark sky is a hole, and a
	# hole reads as a rendering fault. A hair above the sky's own darkest value.
	draw_circle(centre, r, Color(0.015, 0.012, 0.03, 1.0))
	# The rim: the last light bending round the edge, brightest opposite the spin.
	draw_arc(centre, r * 0.995, 0.0, TAU, 56,
		Color(1.4, 1.15, 1.7, 0.55 + 0.25 * breathe), 1.6, true)


# ------------------------------------------------------------------------ shared
## The sky itself: horizontal strips from `high` at the top through `mid` to
## `horizon` at the sill. Strips rather than a gradient texture so the palette can
## follow the sun without rebuilding an image every frame.
func _gradient(band: Rect2, high: Color, mid: Color, horizon: Color, low: bool) -> void:
	var n: int = BANDS_LOW if low else BANDS_HIGH
	var h: float = band.size.y / float(n)
	for i: int in n:
		var f: float = float(i) / float(maxi(n - 1, 1))
		# Two-stop ramp, biased so most of the change happens near the horizon —
		# which is where a real sky puts it.
		var col: Color = high.lerp(mid, minf(f * 2.0, 1.0)) if f < 0.5 \
			else mid.lerp(horizon, (f - 0.5) * 2.0)
		draw_rect(Rect2(band.position.x, band.position.y + h * float(i),
			band.size.x, h + 1.0), col, true)


## Parallax cloud bars. Horizontal by construction, so they cannot leave the band —
## see the ⚠ block on why nothing here needs clipping.
func _clouds(band: Rect2, sun: Vector2, lit: Color, layers: int) -> void:
	var per: int = CLOUDS_PER_LAYER_LOW if layers <= 1 else CLOUDS_PER_LAYER_HIGH
	for layer: int in layers:
		var speed: float = CLOUD_SPEED[mini(layer, CLOUD_SPEED.size() - 1)]
		var depth: float = float(layer + 1) / float(layers + 1)
		for i: int in per:
			var seed_y: float = _h(layer * 31 + i, 7)
			var seed_w: float = _h(layer * 31 + i, 23)
			var y: float = band.position.y + band.size.y * (0.12 + 0.66 * seed_y)
			var cw: float = band.size.x * (0.10 + 0.16 * seed_w) * (0.6 + depth)
			var ch: float = band.size.y * (0.030 + 0.028 * seed_w)
			# Wrap across the band's width plus one cloud, so a cloud leaving the
			# right edge re-enters from the left instead of popping.
			var span: float = band.size.x + cw * 2.0
			var x: float = band.position.x - cw + fposmod(
				band.size.x * seed_y + _t * speed, span)
			# Lit from behind when it crosses the sun: the closer in x, the hotter.
			var near: float = 1.0 - clampf(absf((x + cw * 0.5) - sun.x)
				/ maxf(band.size.x * 0.35, 1.0), 0.0, 1.0)
			var col := Color(
				lerpf(0.16, lit.r, 0.30 + 0.55 * near),
				lerpf(0.13, lit.g * 0.9, 0.28 + 0.5 * near),
				lerpf(0.20, lit.b, 0.26 + 0.4 * near),
				0.30 + 0.26 * depth)
			# ⚠ THREE STACKED RECTS, NOT ONE. A single rect is a BAR, and the first
			# render read as exactly that — dark horizontal stripes ruled across the
			# sky. A cloud is recognised by its SILHOUETTE, so each one is built from
			# a wide flat base with two narrower, offset tiers above it. Still three
			# draw calls and no texture; the shape is doing the work, not the fidelity.
			var tiers: int = 1 if layers <= 1 else 3
			for tier: int in tiers:
				var t: float = float(tier)
				var shrink: float = 1.0 - 0.26 * t
				var off: float = cw * (0.10 + 0.16 * _h(layer * 91 + i, 5 + tier)) * t
				var tier_col := Color(col.r, col.g, col.b,
					col.a * (1.0 - 0.16 * t))
				draw_rect(Rect2(x + off, y - ch * 0.62 * t,
					cw * shrink, ch * (1.0 - 0.12 * t)), tier_col, true)
			# A brighter underside where the low sun catches it.
			draw_rect(Rect2(x, y + ch - 2.0, cw, 2.0),
				Color(lit.r, lit.g, lit.b, (0.18 + 0.42 * near) * depth), true)


## Stars, hashed to fixed positions so they do not crawl, twinkling on their own
## phases. On LOW they hold still — a twinkle is the first thing worth losing.
func _stars(band: Rect2, low: bool) -> void:
	var n: int = STARS_LOW if low else STARS_HIGH
	for i: int in n:
		var sx: float = band.position.x + band.size.x * _h(i, 3)
		var sy: float = band.position.y + band.size.y * 0.86 * _h(i, 11)
		var base: float = 0.26 + 0.5 * _h(i, 29)
		var a: float = base
		if not low:
			a = base * (0.55 + 0.45 * sin(_t * (0.7 + 1.9 * _h(i, 53))
				+ _h(i, 71) * TAU))
		draw_circle(Vector2(sx, sy), 0.7 + 1.1 * _h(i, 97),
			Color(0.86, 0.88, 1.0, a))


## Cheap deterministic pseudo-noise in [0,1) from two ints. Lifted from `FloorDecor`
## verbatim, which lifted it from `ArenaTerrain` — a second hash would be a second
## thing to get subtly wrong, and all three drawers jittering identically is the
## point.
func _h(a: int, b: int) -> float:
	var n: int = (a * 73856093) ^ (b * 19349663)
	n = (n << 13) ^ n
	var m: int = (n * (n * n * 15731 + 789221) + 1376312589) & 0x7fffffff
	return float(m) / 2147483647.0
