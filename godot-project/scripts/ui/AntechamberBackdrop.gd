extends Node2D
## THE ANTECHAMBER'S SKY — and the thing you are about to climb, finally IN IT.
##
## Maker: *"optimise the lobby area where they can enter the tower, make it feel way
## more epic, change the background to make it feel cooler … I'll add some cool anime
## peaceful music for the entry area"*.
##
## ══ WHAT WAS ACTUALLY WRONG, MEASURED RATHER THAN FELT ══════════════════════
## The entry area's whole sky was a two-stop vertical gradient (`Atmosphere._build_sky`)
## with a row of hazed spires on it, and the only tower in the room was `TowerDoor`'s
## own shaft: base half-width 56 px, rising `TOWER_RISE` 300 px. At the town camera's
## 0.72 zoom that is a 112-px-wide post against an 889-px-wide frame — 12% of the
## screen. The room you stand in before an infinite tower climb did not contain a
## tower. That is the gap this file closes, and it closes it with a SILHOUETTE, which
## is the only thing that scales: one shape, read in a quarter-second, no art assets.
##
## ══ WHY IT IS A NEW FILE AND NOT MORE OF `HubAmbience` ══════════════════════
## `HubAmbience` owns the FOREST — stars, pines, fireflies, the campfire — all of it
## within ~330 px of the ground and all of it on the TERRAIN rung. This is the band
## ABOVE that: sky, distance and the spire. They are separate rungs of the ladder in
## `StageLayers`, they have different redraw budgets, and merging them would put a
## 2 000-px-tall tower in a file whose bounds are the treeline.
##
## (It lives under `scripts/ui/` rather than beside `HubAmbience` purely because that
## is the directory this pass was scoped to create files in. It is scenery, not UI —
## if it is ever moved, `World._build_backdrop` is its only caller.)
##
## ══ THE LADDER, AND WHY TWO NODES ═══════════════════════════════════════════
## Everything here draws in ONE `_draw()` at `StageLayers.MOUNTAIN` (-18): behind the
## forest (-6), in front of `Atmosphere`'s spires (-22) and its sky (-30). Draw ORDER
## inside a single CanvasItem is call order, so aurora → moon → ridges → spire →
## cloud is depth, for free, with no extra nodes.
##
## The PETALS are the exception and they need their own node, because they are the one
## thing that must fall in FRONT of you. They get `StageLayers.DEBRIS` (-1) — in front
## of the ground and the ledges, behind every fighter — which is exactly where a leaf
## drifting past the camera belongs.
##
## ══ AWE AND CALM, NOT NOISE ═════════════════════════════════════════════════
## The maker is scoring this room with quiet music, so every moving thing here is
## SLOW: the fastest element is a petal at 15 px/s and the cloud bands cross the
## street in about four minutes. Nothing strobes, nothing pulses on a beat. The one
## bright thing is the moon, and the tower is dark against it.
##
## ══ IT MUST DEGRADE ═════════════════════════════════════════════════════════
## `TuningConfig.quality_is_low()` is read ONCE into `_low` (the `Telegraph._low`
## pattern — never per draw) and it cuts the aurora entirely, halves the cloud puffs,
## the windows and the petals, and drops the redraw rate to 12 Hz.
##
## ⚠ AND IT IS RATE-CAPPED EVEN AT HIGH. A `_draw()` this size at 60 Hz is 60 Hz of
## polygon churn to animate motion measured in fractions of a pixel per frame. At
## `REDRAW_HZ` 24 the fastest thing on screen moves 0.6 px between redraws, which is
## below what a phone panel can show — so the frames are bought and nothing is lost.

## Where the sky stops being drawn. `World` gives the town camera `limit_top = -420`,
## so anything above this is unreachable by any framing the player can get.
const SKY_TOP: float = -560.0

# ── the spire ───────────────────────────────────────────────────────────────
## Offset from the tower DOOR's x, not a world constant: the great spire has to stand
## on the same axis as the door you walk into or it is a different building. 40 px of
## offset is the parallax cheat — it puts the door's own shaft slightly off-centre at
## the spire's foot, so the shaft reads as a buttress in FRONT of the mass rather than
## as a thin line drawn down the middle of it.
const SPIRE_DX: float = 40.0
## Half-width at the ground line, and at the top of the drawn shaft. 190 makes the
## spire 380 px wide against the 889 px the town camera shows at 0.72 zoom — 43% of the
## frame, which is what "you are standing at the foot of it" costs.
const SPIRE_BASE_HALF: float = 190.0
const SPIRE_TOP_HALF: float = 54.0
## The drawn top. Deliberately far above `SKY_TOP` so the shaft NEVER terminates on
## screen: the tower is endless in the fiction and a visible cap would settle the
## question the whole game is about.
const SPIRE_TOP_Y: float = -1900.0
## Storey courses up the shaft, and the lit windows between them.
const COURSE_STEP: float = 108.0
const WINDOW_ROW_STEP: float = 54.0
const WINDOW_COLS: int = 4
const WINDOW_COLS_LOW: int = 2
## How far up windows are still worth drawing. Above this the haze has swallowed the
## shaft, so a lit rectangle there is a bright dot floating in fog.
const WINDOW_TOP_Y: float = -820.0

# ── the sky furniture ───────────────────────────────────────────────────────
const MOON_R: float = 40.0
## Left of the spire and just above the treeline, so the tower's edge CUTS it — the
## silhouette needs something bright behind it or it is a dark shape on a dark sky.
const MOON_DX: float = -290.0
const MOON_DY: float = -372.0
const CLOUD_BANDS: int = 4
const CLOUD_BANDS_LOW: int = 2
const AURORA_RIBBONS: int = 3
## ⚠ COUNTED AGAINST THE FRAME, NOT PICKED. The town camera shows 889x500 of a
## 1420x582 petal field, so a count of N puts roughly `N * 0.63 * 0.86` = 54% of them
## on screen. 34 gave 18 petals across the whole street — a drizzle. 56 gives 30, which
## is the density that reads as falling blossom without ever obscuring a body.
const PETALS: int = 56
const PETALS_LOW: int = 22
## The band petals occupy. Deliberately NOT `SKY_TOP`: the camera can never see above
## y -30 in this room (see the clamp arithmetic in `World._place_player`), so a field
## that reached -560 would spend nine tenths of its petals off-screen and the ones on
## screen would be nine tenths too sparse.
const PETAL_TOP: float = -130.0

## Redraw budget. See the ⚠ block in the header for why this is not 60.
const REDRAW_HZ: float = 24.0
const REDRAW_HZ_LOW: float = 12.0

## ⚠ DECLARED AS A FIELD so a headless suite can force the cheap picture with
## `set("_low", true)` without a Tuning autoload — the same affordance `Telegraph`
## documents, and the reason this is not a local in `build()`.
var _low: bool = false

var _town_w: float = 1180.0
var _ground_y: float = 452.0
var _spire_x: float = 1020.0
var _sky: Color = Color(0.10, 0.16, 0.24)
var _accent: Color = Color(0.5, 0.85, 0.8)
var _phase: float = 0.0
var _redraw_acc: float = 0.0
var _petals: Node2D = null

## Deterministic scatter tables, seeded ONCE in `build`. No RNG is touched in `_draw`:
## a per-frame `randf()` would make every window twinkle independently every redraw,
## which is a starfield, not a building.
var _windows: Array[Dictionary] = []   # {pos, seed}
var _clouds: Array[Dictionary] = []    # {y, speed, scale, alpha, puffs}


## `town_width` / `ground_y` frame the room, `tower_x` is the DOOR's axis (the spire
## stands on it), `sky_bottom` is the colour distance hazes toward and `accent` is the
## room's own hue — both handed down from `World`'s palette so this file cannot invent
## a seventh blue.
func build(town_width: float, ground_y: float, tower_x: float,
		sky_bottom: Color, accent: Color) -> void:
	_town_w = town_width
	_ground_y = ground_y
	_spire_x = tower_x + SPIRE_DX
	_sky = sky_bottom
	_accent = accent
	_low = TuningConfig.quality_is_low()
	StageLayers.apply(self, StageLayers.MOUNTAIN)
	reseed()
	set_process(true)
	queue_redraw()


## Rebuild every seeded count from the CURRENT `_low`.
##
## ⚠ IT IS A SEPARATE, PUBLIC FUNCTION FOR ONE REASON, AND IT IS A MEASUREMENT ONE.
## `build()` reads the live quality setting, so a harness that forces the cheap picture
## with `set("_low", true)` AFTER building only flips the branches inside `_draw` — the
## window, cloud and petal counts stay at their HIGH values, and the probe cheerfully
## reports that LOW costs the same as HIGH. `tools/probe_antechamber_backdrop.gd`
## calls this straight after the override so the numbers it prints are the numbers a
## phone actually gets.
func reseed() -> void:
	_windows.clear()
	_clouds.clear()
	if _petals != null:
		remove_child(_petals)
		_petals.queue_free()
		_petals = null
	_seed_windows()
	_seed_clouds()
	_build_petals()


func _process(delta: float) -> void:
	_phase += delta
	_redraw_acc += delta
	var step: float = 1.0 / (REDRAW_HZ_LOW if _low else REDRAW_HZ)
	if _redraw_acc < step:
		return
	_redraw_acc = 0.0
	queue_redraw()
	if _petals != null:
		_petals.set("phase", _phase)
		_petals.queue_redraw()


# ═══════════════════════════════════════════════════════════════════ seeding
## Hash-sine scatter (the `HubAmbience` idiom) rather than a `RandomNumberGenerator`:
## same numbers every boot, so the tower the maker signs off on is the tower that
## ships, and no seed has to be stored anywhere.
static func _hash01(i: float) -> float:
	return absf(fmod(sin(i * 12.9898) * 43758.5453, 1.0))


func _seed_windows() -> void:
	var cols: int = WINDOW_COLS_LOW if _low else WINDOW_COLS
	var y: float = _ground_y - 150.0
	var i: int = 0
	while y > WINDOW_TOP_Y:
		var half: float = _spire_half_at(y)
		for c: int in cols:
			# Columns are spread across the INNER 70% of the shaft: a window on the
			# silhouette's own edge reads as a chip out of the tower, not a lit room.
			var t: float = (float(c) + 0.5) / float(cols)
			var x: float = _spire_x + lerpf(-half * 0.7, half * 0.7, t)
			# A third of them are dark. A tower with every window lit is an office
			# block; a tower with gaps is inhabited.
			if _hash01(float(i) * 3.7 + 1.3) < 0.34:
				i += 1
				continue
			_windows.append({"pos": Vector2(x, y), "seed": float(i) * 2.1})
			i += 1
		y -= WINDOW_ROW_STEP
	# ⚠ ORDERED BOTTOM-UP BY CONSTRUCTION, and `_draw_windows` relies on it for the
	# height fade: the loop walks upward, so a later entry is always further away.


func _seed_clouds() -> void:
	var bands: int = CLOUD_BANDS_LOW if _low else CLOUD_BANDS
	for b: int in bands:
		var f: float = float(b) / float(maxi(bands - 1, 1))
		_clouds.append({
			# ⚠ 340, NOT THE 300 THIS STARTED AT, AND IT WAS MEASURED. `HubAmbience`'s
			# near pines top out around 360 px above the ground line, so the lowest band
			# at -300 sat INSIDE the forest and was never seen. From -340 up, every band
			# crosses the spire in open sky.
			"y": _ground_y - 340.0 - f * 300.0,
			# Higher band = further away = SLOWER. That is the whole parallax cue and
			# it costs one multiply.
			"speed": lerpf(7.0, 2.5, f),
			"scale": lerpf(1.0, 0.62, f),
			"alpha": lerpf(0.16, 0.09, f),
			"puffs": (5 if _low else 9),
		})


## The foreground petal drift. Its own node because it is the one layer that must be
## IN FRONT of the player — see the ladder note in the header.
func _build_petals() -> void:
	_petals = _Petals.new()
	_petals.set("count", PETALS_LOW if _low else PETALS)
	_petals.set("span", Rect2(Vector2(-120.0, PETAL_TOP), Vector2(_town_w + 240.0,
		_ground_y - PETAL_TOP + 30.0)))
	add_child(_petals)
	StageLayers.apply(_petals, StageLayers.DEBRIS)


# ══════════════════════════════════════════════════════════════════════ draw
## Call order IS depth. Do not reorder without reading the ladder note above.
func _draw() -> void:
	if not _low:
		_draw_aurora()
	_draw_moon()
	_draw_ridges()
	_draw_spire()
	_draw_clouds()


# ------------------------------------------------------------------- aurora
## Three slow ribbons in the room's own accent, at alphas low enough that they read as
## light rather than as paint. Cut entirely on LOW: it is the most draw calls per unit
## of drama on the screen and the one element the composition still works without.
func _draw_aurora() -> void:
	var segs: int = 22
	var x0: float = -200.0
	var x1: float = _town_w + 200.0
	for r: int in AURORA_RIBBONS:
		var rf: float = float(r)
		var base: float = _ground_y - 400.0 - rf * 78.0
		var amp: float = 30.0 + rf * 16.0
		var col := Color(_accent.r, _accent.g, _accent.b, 0.055 - rf * 0.012)
		var width: float = 34.0 - rf * 6.0
		var prev := Vector2.ZERO
		for s: int in segs + 1:
			var t: float = float(s) / float(segs)
			var x: float = lerpf(x0, x1, t)
			# Two incommensurate sines so the ribbon never visibly repeats along its
			# own length — one wave would read as a drawn arc.
			var y: float = base + sin(t * 5.1 + _phase * 0.09 + rf) * amp \
				+ sin(t * 11.3 - _phase * 0.05) * amp * 0.35
			var p := Vector2(x, y)
			if s > 0:
				draw_line(prev, p, col, width)
			prev = p


# --------------------------------------------------------------------- moon
func _draw_moon() -> void:
	var c := Vector2(_spire_x + MOON_DX, _ground_y + MOON_DY)
	var pale := Color(0.93, 0.95, 1.0)
	if not _low:
		# Three halo rings rather than a texture. The outermost is nearly invisible on
		# its own and is what stops the moon looking like a sticker.
		draw_circle(c, MOON_R * 4.2, Color(pale.r, pale.g, pale.b, 0.035))
		draw_circle(c, MOON_R * 2.4, Color(pale.r, pale.g, pale.b, 0.055))
	draw_circle(c, MOON_R * 1.35, Color(pale.r, pale.g, pale.b, 0.10))
	draw_circle(c, MOON_R, Color(pale.r, pale.g, pale.b, 0.90))
	# A crescent bite, cut with the SKY colour rather than with black — a black bite
	# on a blue sky is a hole, which is rule 3 of the visual grammar in `StageLayers`.
	draw_circle(c + Vector2(-MOON_R * 0.42, -MOON_R * 0.24), MOON_R * 0.94,
		Color(_sky.r, _sky.g, _sky.b, 0.82))


# ------------------------------------------------------------------- ridges
## Two hill bands between the sky and the forest. Both are pushed through
## `StageLayers.haze` toward the sky colour, so "further away = closer to the sky" is
## structural here rather than a pair of hand-picked greys that a palette edit breaks.
func _draw_ridges() -> void:
	for band: int in 2:
		var bf: float = float(band)
		var top: float = _ground_y - 250.0 + bf * 66.0
		var amp: float = 54.0 - bf * 18.0
		var col: Color = StageLayers.haze(Color(0.07, 0.11, 0.19), _sky, 0.72 - bf * 0.26)
		var pts: PackedVector2Array = PackedVector2Array()
		var segs: int = (9 if _low else 18)
		for s: int in segs + 1:
			var t: float = float(s) / float(segs)
			var x: float = lerpf(-200.0, _town_w + 200.0, t)
			var y: float = top - absf(sin(t * 6.4 + bf * 2.1)) * amp \
				- absf(sin(t * 2.3 + bf)) * amp * 0.5
			pts.append(Vector2(x, y))
		pts.append(Vector2(_town_w + 200.0, _ground_y + 40.0))
		pts.append(Vector2(-200.0, _ground_y + 40.0))
		draw_colored_polygon(pts, col)


# -------------------------------------------------------------------- spire
## Half-width of the shaft at world y. One function so the body, the courses and the
## window columns can never disagree about where the edge is.
func _spire_half_at(y: float) -> float:
	var t: float = clampf((_ground_y - y) / (_ground_y - SPIRE_TOP_Y), 0.0, 1.0)
	# Eased, not linear: a straight taper reads as a wedge. The square root keeps the
	# lower third nearly full width and does most of the narrowing high up, which is
	# what makes it read as a TOWER rather than as a pylon.
	return lerpf(SPIRE_BASE_HALF, SPIRE_TOP_HALF, sqrt(t))


func _draw_spire() -> void:
	# The body, as a stack of quads rather than one — each slice can carry its own
	# haze, so the shaft dissolves upward instead of ending in a hard line.
	var slices: int = (7 if _low else 14)
	var y: float = _ground_y + 40.0
	var step: float = (y - SPIRE_TOP_Y) / float(slices)
	var stone := Color(0.055, 0.075, 0.115)
	for s: int in slices:
		var y0: float = y - step * float(s)
		var y1: float = y0 - step
		var h0: float = _spire_half_at(y0)
		var h1: float = _spire_half_at(y1)
		var up: float = clampf(float(s) / float(slices), 0.0, 1.0)
		# 0.10 at the foot to 0.86 at the top: the base is solid, the crown is fog.
		var col: Color = StageLayers.haze(stone, _sky, lerpf(0.10, 0.86, up * up))
		draw_colored_polygon(PackedVector2Array([
			Vector2(_spire_x - h0, y0), Vector2(_spire_x + h0, y0),
			Vector2(_spire_x + h1, y1), Vector2(_spire_x - h1, y1),
		]), col)
	_draw_courses()
	_draw_windows()
	# THE LIT EDGE. One warm rim down the moon-facing side, so the silhouette has a
	# direction of light and is not a flat cut-out. It is the same warm-cap idea rule 1
	# of `StageLayers`'s visual grammar uses on ledges, borrowed for a vertical.
	var rim := Color(0.80, 0.72, 0.62, 0.20)
	var ry: float = _ground_y
	var rim_prev := Vector2(_spire_x - _spire_half_at(ry), ry)
	for s: int in 12:
		ry = lerpf(_ground_y, -700.0, float(s + 1) / 12.0)
		var p := Vector2(_spire_x - _spire_half_at(ry), ry)
		draw_line(rim_prev, p, Color(rim.r, rim.g, rim.b,
			rim.a * (1.0 - float(s) / 12.0)), 2.0)
		rim_prev = p


## Storey courses. Four on the door's own shaft were "enough to scale it"; a shaft this
## tall needs them all the way up, so they are generated on a stride and hazed with
## height like the body they sit on.
func _draw_courses() -> void:
	var y: float = _ground_y - COURSE_STEP
	while y > -900.0:
		var half: float = _spire_half_at(y)
		var up: float = clampf((_ground_y - y) / (_ground_y + 900.0), 0.0, 1.0)
		var col: Color = StageLayers.haze(Color(0.11, 0.14, 0.20), _sky,
			lerpf(0.20, 0.88, up))
		draw_colored_polygon(PackedVector2Array([
			Vector2(_spire_x - half, y), Vector2(_spire_x + half, y),
			Vector2(_spire_x + half * 0.985, y + 6.0),
			Vector2(_spire_x - half * 0.985, y + 6.0),
		]), col)
		y -= COURSE_STEP


## The lit windows — the one warm thing on a cold silhouette, and the whole reason the
## shape reads as INHABITED rather than as a mountain. Each has its own slow phase, so
## the tower breathes without any of it landing on a beat.
func _draw_windows() -> void:
	for w: Dictionary in _windows:
		var p: Vector2 = w["pos"]
		var sd: float = float(w["seed"])
		# 0.55..1.0, over ~6 s. Slow enough that a still frame and a moving one look
		# like the same building.
		var lit: float = 0.78 + 0.22 * sin(_phase * 0.9 + sd)
		# Fade with height for the same reason the body hazes: a window at the top of
		# the fog would be brighter than the stone it is cut into.
		var up: float = clampf((_ground_y - p.y) / (_ground_y - WINDOW_TOP_Y), 0.0, 1.0)
		var a: float = lerpf(0.85, 0.10, up * up) * lit
		if a < 0.02:
			continue
		var warm := Color(1.0, 0.78, 0.42)
		if not _low:
			draw_circle(p, 7.0, Color(warm.r, warm.g, warm.b, a * 0.16))
		draw_rect(Rect2(p - Vector2(1.5, 3.5), Vector2(3.0, 7.0)),
			Color(warm.r, warm.g, warm.b, a))


# -------------------------------------------------------------------- cloud
## Slow mist bands crossing the spire. Drawn LAST so they pass in FRONT of it — that
## crossing is the single beat that says "this thing is enormous", and it is the only
## reason the bands exist at all.
func _draw_clouds() -> void:
	var pale: Color = _sky.lightened(0.34)
	for i: int in _clouds.size():
		var band: Dictionary = _clouds[i]
		var by: float = float(band["y"])
		var sc: float = float(band["scale"])
		var a: float = float(band["alpha"])
		var puffs: int = int(band["puffs"])
		# Wrapped drift over a span wider than the town, so a band never pops in at
		# the edge of a camera that can pan the whole street.
		var span: float = _town_w + 700.0
		var drift: float = fmod(_phase * float(band["speed"]), span)
		for p: int in puffs:
			var pf: float = float(p)
			var base_x: float = -350.0 + span * (pf / float(puffs))
			var x: float = base_x + drift
			if x > _town_w + 350.0:
				x -= span
			var wob: float = sin(pf * 2.7 + float(i)) * 16.0
			var r: float = (58.0 + _hash01(pf + float(i) * 7.0) * 46.0) * sc
			# Three overlapping discs per puff: one circle is a ball, three is a cloud.
			draw_circle(Vector2(x, by + wob), r, Color(pale.r, pale.g, pale.b, a))
			draw_circle(Vector2(x + r * 0.72, by + wob + r * 0.20), r * 0.72,
				Color(pale.r, pale.g, pale.b, a * 0.85))
			draw_circle(Vector2(x - r * 0.68, by + wob + r * 0.26), r * 0.64,
				Color(pale.r, pale.g, pale.b, a * 0.8))


# ═════════════════════════════════════════════════════════════════════ petals
## THE ANIME-PEACEFUL LAYER, and the one the maker's music is for. Pale petals falling
## in FRONT of the room at 15 px/s with a sine sway, wrapping forever.
##
## An INNER class, deliberately: it has no `class_name`, so it needs no entry in
## `.godot/global_script_class_cache.cfg` and cannot hit the "Could not find type X in
## the current scope" trap that Sessions 6/8/9 lost real time to. It is also fully
## self-contained (its own constants, no reach back into the outer scope), which is
## what lets it stay unnamed — see `Lobby._Paper` for the alternative, where the outer
## script had to take a `class_name` purely so its inner class could see the palette.
class _Petals extends Node2D:
	const FALL: float = 15.0        # px/s. Slower than gravity; this is drifting.
	const SWAY: float = 22.0        # px of horizontal wander, each side
	const PETAL: Color = Color(1.0, 0.80, 0.86)

	var count: int = 34
	var span: Rect2 = Rect2(0.0, 0.0, 1400.0, 1000.0)
	var phase: float = 0.0

	func _draw() -> void:
		for i: int in count:
			var fi: float = float(i)
			var h1: float = absf(fmod(sin(fi * 12.9898) * 43758.5453, 1.0))
			var h2: float = absf(fmod(sin(fi * 78.233) * 12543.245, 1.0))
			var speed: float = FALL * (0.6 + h2 * 0.9)
			# `fposmod` rather than `fmod`: the drift is always positive here, but a
			# negative `phase` (a suite scrubbing time backwards) would put half the
			# petals off-world with plain `fmod`, and the bug would only appear there.
			var y: float = span.position.y + fposmod(h1 * span.size.y + phase * speed,
				span.size.y)
			var x: float = span.position.x + h2 * span.size.x \
				+ sin(phase * 0.6 + fi) * SWAY
			# Fade in at the top and out at the bottom so nothing ever pops.
			var t: float = (y - span.position.y) / span.size.y
			var a: float = clampf(minf(t * 6.0, (1.0 - t) * 5.0), 0.0, 1.0) * 0.55
			if a < 0.02:
				continue
			# A four-point diamond, tumbling. A circle here reads as dust; the tumble
			# is what makes it a petal.
			var spin: float = phase * 1.3 + fi
			var w: float = 2.2 + absf(sin(spin)) * 1.6
			var hh: float = 3.4
			var p := Vector2(x, y)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0.0, -hh), p + Vector2(w, 0.0),
				p + Vector2(0.0, hh), p + Vector2(-w, 0.0),
			]), Color(PETAL.r, PETAL.g, PETAL.b, a))
