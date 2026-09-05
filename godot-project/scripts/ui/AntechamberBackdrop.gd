extends Node2D
## THE TAVERN — the room you stand in before the climb.
##
## Maker: *"make the lobby very different like a tavern vibe I like that feel way more,
## not outside at a campfire but instead inside of a tavern with warm lit and cool
## graphics and all the sorts — first brainstorm what you think would be nice and
## aesthetic then build it"*.
##
## ══ THE BRAINSTORM, AND WHAT IT RULED OUT ═══════════════════════════════════
## The previous version of this file was an OUTDOOR night: a colossal spire, a moon,
## two hill ridges, aurora ribbons, drifting cloud and falling blossom. The maker likes
## what that is WORTH — depth, motion, a silhouette you read in a quarter-second — and
## does not like WHERE it is. So the question was never "re-tint it warmer". A tavern
## is an INTERIOR, and an interior is defined by what it EXCLUDES: you cannot see a
## ridge, an aurora or a cloud band from inside a room. Every one of those either had
## to go or had to move BEHIND GLASS.
##
## What an aesthetic stick-figure tavern actually is, at 640x360, drawn in polygons:
##
##   1. **WARM INSIDE, COLD OUTSIDE, AND THE WINDOW IS THE JOINT.** A room only reads
##      as warm by CONTRAST. So the wall carries three tall windows onto the same night
##      the old backdrop was made of — the moon still hangs in one, the great spire
##      still stands in another. Nothing is thrown away; it is put outside where it
##      belongs, and the frame around it is what turns scenery into a VIEW.
##   2. **THE TOWER IS THE ONE COLD-LIT THING IN A WARM ROOM.** Every lamp here is
##      amber. The great window and the tower door under it are the only blue on the
##      screen, so the eye goes to the way out without a single arrow being drawn.
##   3. **DEPTH BY LAYERS, NOT BY DETAIL.** Plank wall → window band → timber posts and
##      the tie-beam → the bar and its shelf → hanging lamps and their light → drifting
##      haze. Six rungs of the same room, drawn back to front in ONE `_draw` (call order
##      IS depth inside a CanvasItem), each one a little warmer and a little more
##      contrasty than the one behind it. That is the whole trick, and it survives being
##      shrunk to a phone in a way that texture never does.
##   4. **LIGHT POOLS ON THINGS.** A lantern that only glows is a sticker. A lantern
##      with a shaft under it and an ellipse of light on the floorboards is a LAMP, and
##      it is what makes the floor read as a floor. This is the single biggest change
##      per draw call in the file.
##   5. **THE HEARTH IS NOT HERE.** It is `HubAmbience`'s, on the rung in front of this
##      one, because it has to sit in FRONT of the wall and light the furniture. This
##      file draws the room; that one furnishes it. Same split as before, new place.
##
## ══ WHERE IT SITS, AND WHY THE OLD `Atmosphere` IS STILL UNDERNEATH ═════════
## Everything here draws at `StageLayers.MOUNTAIN` (-18) — in front of `Atmosphere`'s
## sky (-30) and its distant spires (-22), behind the furniture (-6) and every fighter
## (0). That ordering is now LOAD-BEARING rather than incidental: the wall is painted
## as bands that stop at the window openings, so what shows THROUGH the glass is
## `Atmosphere`'s own night sky. There is no second sky drawn here and there must not
## be one — the window is a hole, and the thing behind the hole is the sky the room is
## already standing under.
##
## The DUST is the exception and needs its own node, because it is the one layer that
## must fall in FRONT of you. It gets `StageLayers.DEBRIS` (-1) — in front of the floor,
## behind every fighter — which is where a mote crossing the lamp light belongs.
##
## ══ IT MUST DEGRADE ═════════════════════════════════════════════════════════
## `TuningConfig.quality_is_low()` is read ONCE into `_low` (the `Telegraph._low`
## pattern — never per draw). LOW cuts the light SHAFTS entirely (they are the most
## alpha-blended area per unit of drama in the file), halves the haze bands, the bottles
## and the dust, drops the lamp halo rings, and drops the redraw rate to 12 Hz.
##
## ⚠ AND IT IS RATE-CAPPED EVEN AT HIGH, for the reason the outdoor version was: a
## `_draw()` this size at 60 Hz is 60 Hz of polygon churn to animate motion measured in
## fractions of a pixel per frame. At `REDRAW_HZ` 24 the fastest thing on screen moves
## well under a pixel between redraws, so the frames are bought and nothing is lost.

## Where the drawn room stops. `World` gives the town camera `limit_top = -420`, so
## anything above this is unreachable by any framing the player can get. Above the
## rafters it is all roof void anyway.
const SKY_TOP: float = -560.0

# ── the room shell ──────────────────────────────────────────────────────────
## The underside of the tie-beam, i.e. the ceiling line. 422 px above the floor, which
## at the town camera's 0.72 zoom is 304 of the 360 screen px — a HALL, not a cellar.
## It also has to sit BELOW the frame's top edge (the camera shows y -30..470), or the
## room has no ceiling in shot and stops reading as an interior at all;
## `slice_test_antechamber_sky` asserts exactly that.
const CEIL_Y: float = 30.0
const BEAM_H: float = 26.0
## How far past the town the wall runs. The camera can frame x -200..1180, so this is
## comfortably beyond both edges at every clamp.
const WALL_MARGIN: float = 340.0
## The wainscot. A darker panelled band along the bottom of the wall — the thing that
## stops a flat plank field reading as a fence, and the horizontal that gives the room
## a floor line independent of the actual collision floor.
const DADO_H: float = 96.0
## Plank stride on the back wall. Wide enough that a phone still resolves the seams.
const PLANK_W: float = 46.0

# ── the windows ─────────────────────────────────────────────────────────────
## ⚠ ONE SHARED Y BAND FOR EVERY WINDOW, AND IT IS A DRAWING DECISION BEFORE IT IS A
## TASTE ONE. The wall is painted as bands that stop at the openings; with every window
## on the same band that subtraction is three rectangles and cannot be got wrong, and
## with windows at different heights it is a general polygon-clipping problem drawn
## sixty times a second. A row of windows at one height is also simply what a hall has.
const WINDOW_TOP: float = 132.0
const WINDOW_BOTTOM: float = 308.0
## The great window, centred just RIGHT of the tower door so the door's own silhouette
## reads as standing IN FRONT of the view rather than dead-centre of it.
const GREAT_WINDOW_DX: float = 26.0
const GREAT_WINDOW_HALF: float = 112.0
## The two smaller windows over the room's left half.
const SIDE_WINDOW_HALF: float = 56.0
const SIDE_WINDOW_X: Array[float] = [206.0, 474.0]
## Mullion stride inside a window — the glazing bars. Fewer on LOW.
const MULLION_STEP: float = 38.0

# ── what is outside ─────────────────────────────────────────────────────────
## The spire, still here, now seen THROUGH the great window.
##
## ⚠ IT IS LESS THAN HALF THE WIDTH IT WAS (base half 190 -> 88) AND THAT IS THE WHOLE
## POINT OF PUTTING IT BEHIND GLASS. At 190 the shaft measured 291 px across the
## window's mid-height against a 224 px opening — it filled the frame edge to edge,
## which is a WALL of stone, not a tower. At 88 it measures ~135 px of that 224, so the
## taper is inside the opening and the thing reads as a tower standing some way off.
## Distance is what a window buys you; a silhouette that touches both jambs spends it.
const SPIRE_DX: float = 40.0
const SPIRE_BASE_HALF: float = 88.0
const SPIRE_TOP_HALF: float = 26.0
## The drawn top. Deliberately far above anything the camera can frame so the shaft
## NEVER terminates on screen: the tower is endless in the fiction and a visible cap
## would settle the question the whole game is about.
const SPIRE_TOP_Y: float = -1900.0
## The moon, placed in the LEFT window rather than in open sky — it is the one bright
## thing outside, and framing it is what tells the player the wall has holes in it.
const MOON_R: float = 26.0

# ── the lamps ───────────────────────────────────────────────────────────────
## Hanging lanterns along the tie-beam. The count is what LOW halves.
const LAMP_X: Array[float] = [-104.0, 132.0, 368.0, 604.0, 840.0, 1076.0]
const LAMP_DROP: float = 118.0      # chain length below the beam
const LAMP_R: float = 9.0
## The floor pool under each lamp. An ELLIPSE, not a circle: light on a floor seen from
## the side is squashed, and a circle there reads as a glowing disc lying on the boards.
const POOL_RX: float = 96.0
const POOL_RY: float = 15.0

# ── the bar ─────────────────────────────────────────────────────────────────
## ⚠ THE BAR LIVES IN THE ROOM THE LEFT WALL JUST GAVE BACK. Maker: *"the far left side
## of the lobby can be a little further out before the invisible barrier"*. `World`
## moved `BOUND_LEFT` out and moved the camera's `limit_left` with it (an unframed
## corridor would have been worse than a short one), and this is what that new floor is
## FOR — a room does not need more empty floor, it needs somewhere else to be.
const BAR_X0: float = -168.0
const BAR_X1: float = 44.0
const BAR_TOP: float = 400.0         # counter surface, 52 px above the boards
const SHELF_TOP: float = 262.0
const SHELF_STEP: float = 34.0
const SHELF_ROWS: int = 3
const BOTTLES_PER_ROW: int = 9
const BOTTLES_PER_ROW_LOW: int = 4

## Where the barrel stack at the open end of the bar sits, measured from `BAR_X1`.
##
## ⚠ 44 -> 24, AND IT IS A COLLISION NUMBER NOW. `World._build_ledges` puts a standable
## ledge on top of these barrels, and the first training dummy stands at x 110 with a
## ~9 px half-width. At +44 the stack spanned 66..110 and its ledge would have reached
## under the dummy's feet — which is the exact class of bug `probe_town_feet` was
## written for (a body reading its ground line off something that is not the floor).
## At +24 the stack spans 46..90 and clears him by 11 px.
const BARREL_DX: float = 24.0

# ── curves ──────────────────────────────────────────────────────────────────
## ⚠ THE ROOM WAS ALL RECTANGLES. Maker, after playing: *"add some cool curved
## structures etc. like make it more aesthetic"*. Curves are what make a built space
## read as BUILT rather than blocked out, and there are three of them here — arched
## window heads, arched knee braces on the posts, and vault ribs over the beam — all
## drawn as polygon fans off `_arc_points`, because a filled arch is a shape and
## `draw_arc` only gives you a stroke.
##
## ⚠ AND THE ARCH IS SUBTRACTED FROM THE OPENING, NOT ADDED TO THE GLASS. `_draw_wall`
## can only subtract RECTANGLES (see the note on `WINDOW_TOP`), so the window heads are
## made round by painting the two top CORNERS of each opening back in as wall. That
## keeps the wall arithmetic three rectangles and still gives a round-headed window.
const ARCH_SEGS: int = 10
const ARCH_SEGS_LOW: int = 5
## Rib spacing across the ceiling, and how far each rib bows down into the room.
const RIB_STEP: float = 236.0
const RIB_SAG: float = 26.0

# ── the air ─────────────────────────────────────────────────────────────────
## Slow warm haze crossing the lamp band. Inherits the old cloud-band code wholesale —
## same wrapped drift, same three-disc puffs — because smoke in a lit room and cloud in
## a lit sky are the same drawing with a different alpha and a different colour.
const HAZE_BANDS: int = 3
const HAZE_BANDS_LOW: int = 1
## Dust in the lamp beams. Counted against the FRAME, not picked: the town camera shows
## 889x500 of the field below, so a count of N puts roughly 55% of them on screen.
const DUST: int = 64
const DUST_LOW: int = 24
const DUST_TOP: float = 60.0

## Redraw budget. See the ⚠ block in the header for why this is not 60.
const REDRAW_HZ: float = 24.0
const REDRAW_HZ_LOW: float = 12.0

# ── the palette ─────────────────────────────────────────────────────────────
## ⚠ EVERY WARM TONE IS DECLARED HERE AND NOWHERE ELSE. The old file could take its
## colours from `World`'s sky because everything it drew was sky; a room has its own
## light, and a room whose timber is picked inline in six functions is a room nobody
## can re-grade later.
const TIMBER_DARK: Color = Color(0.113, 0.078, 0.058)
const TIMBER: Color = Color(0.168, 0.114, 0.079)
const TIMBER_LIT: Color = Color(0.232, 0.157, 0.101)
const BEAM_COL: Color = Color(0.086, 0.060, 0.046)
const ROOF_VOID: Color = Color(0.036, 0.027, 0.026)
const DADO_COL: Color = Color(0.093, 0.066, 0.052)
## The lit cap, borrowed from `StageLayers`'s visual grammar rule 1 — a warm pale line
## along the top edge of a horizontal surface. The counter, the wainscot and every stair
## tread wear it, so "this is something's top" is answerable at a glance here in exactly
## the language the fighting stages already use.
const CAP_LIT: Color = Color(0.86, 0.70, 0.46)
const LAMP_WARM: Color = Color(1.0, 0.76, 0.40)
const BRASS: Color = Color(0.55, 0.40, 0.20)

## ⚠ DECLARED AS A FIELD so a headless suite can force the cheap picture with
## `set("_low", true)` without a Tuning autoload — the same affordance `Telegraph`
## documents, and the reason this is not a local in `build()`.
var _low: bool = false

var _town_w: float = 1180.0
var _ground_y: float = 452.0
var _tower_x: float = 980.0
var _spire_x: float = 1020.0
## The night colour the outside hazes toward, and the room's cold accent. Both handed
## down from `World`'s palette so this file cannot invent a seventh blue.
var _night: Color = Color(0.19, 0.16, 0.30)
var _accent: Color = Color(0.62, 0.70, 1.0)
var _phase: float = 0.0
var _redraw_acc: float = 0.0
var _dust: Node2D = null

## Deterministic scatter tables, seeded ONCE in `build`. No RNG is touched in `_draw`:
## a per-frame `randf()` would make every bottle twinkle independently every redraw,
## which is a starfield, not a shelf.
##
## ⚠ `_windows` IS SORTED BY x AND `_draw_wall` DEPENDS ON IT. The wall is painted as
## the GAPS between consecutive openings; out of order, a gap runs backwards and the
## band it should have painted is simply missing.
var _windows: Array[Rect2] = []
var _bottles: Array[Dictionary] = []   # {pos, h, col, seed}
var _haze: Array[Dictionary] = []      # {y, speed, scale, alpha, puffs}


## `town_width` / `ground_y` frame the room, `tower_x` is the DOOR's axis (the great
## window is centred just off it), `sky_bottom` is the night beyond the glass and
## `accent` is the room's cold hue — both handed down from `World`'s palette.
func build(town_width: float, ground_y: float, tower_x: float,
		sky_bottom: Color, accent: Color) -> void:
	_town_w = town_width
	_ground_y = ground_y
	_tower_x = tower_x
	_spire_x = tower_x + SPIRE_DX
	_night = sky_bottom
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
## bottle, haze and dust counts stay at their HIGH values, and the probe cheerfully
## reports that LOW costs the same as HIGH. `tools/probe_antechamber_backdrop.gd` calls
## this straight after the override so the numbers it prints are the numbers a phone
## actually gets.
func reseed() -> void:
	_windows.clear()
	_bottles.clear()
	_haze.clear()
	if _dust != null:
		remove_child(_dust)
		_dust.queue_free()
		_dust = null
	_seed_windows()
	_seed_bottles()
	_seed_haze()
	_build_dust()


func _process(delta: float) -> void:
	_phase += delta
	_redraw_acc += delta
	var step: float = 1.0 / (REDRAW_HZ_LOW if _low else REDRAW_HZ)
	if _redraw_acc < step:
		return
	_redraw_acc = 0.0
	queue_redraw()
	if _dust != null:
		_dust.set("phase", _phase)
		_dust.queue_redraw()


# ═══════════════════════════════════════════════════════════════════ seeding
## Hash-sine scatter (the `HubAmbience` idiom) rather than a `RandomNumberGenerator`:
## same numbers every boot, so the room the maker signs off on is the room that ships,
## and no seed has to be stored anywhere.
static func _hash01(i: float) -> float:
	return absf(fmod(sin(i * 12.9898) * 43758.5453, 1.0))


func _seed_windows() -> void:
	var h: float = WINDOW_BOTTOM - WINDOW_TOP
	for x: float in SIDE_WINDOW_X:
		_windows.append(Rect2(x - SIDE_WINDOW_HALF, WINDOW_TOP,
			SIDE_WINDOW_HALF * 2.0, h))
	var gx: float = _tower_x + GREAT_WINDOW_DX
	_windows.append(Rect2(gx - GREAT_WINDOW_HALF, WINDOW_TOP,
		GREAT_WINDOW_HALF * 2.0, h))
	# See the ⚠ on the declaration: `_draw_wall` paints the gaps BETWEEN these, so the
	# order is not cosmetic.
	_windows.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)


func _seed_bottles() -> void:
	var per_row: int = BOTTLES_PER_ROW_LOW if _low else BOTTLES_PER_ROW
	var i: int = 0
	for row: int in SHELF_ROWS:
		var y: float = SHELF_TOP + float(row) * SHELF_STEP
		for c: int in per_row:
			var t: float = (float(c) + 0.5) / float(per_row)
			var x: float = lerpf(BAR_X0 + 14.0, BAR_X1 - 14.0, t)
			# A fifth of the slots are empty. A shelf with every slot filled is a
			# warehouse; a shelf with gaps is a bar somebody drinks at.
			if _hash01(float(i) * 3.7 + 1.3) < 0.20:
				i += 1
				continue
			var hh: float = 12.0 + _hash01(float(i) * 5.1) * 9.0
			# Green, amber and a rare rose — glass colours, all dark enough that the
			# HIGHLIGHT on them is what you actually see. See `_draw_bar`.
			var pick: float = _hash01(float(i) * 9.7 + 4.2)
			var col: Color = Color(0.16, 0.28, 0.18)
			if pick > 0.66:
				col = Color(0.34, 0.20, 0.07)
			elif pick > 0.52:
				col = Color(0.30, 0.13, 0.19)
			_bottles.append({"pos": Vector2(x, y), "h": hh, "col": col,
				"seed": float(i) * 2.1})
			i += 1


func _seed_haze() -> void:
	var bands: int = HAZE_BANDS_LOW if _low else HAZE_BANDS
	for b: int in bands:
		var f: float = float(b) / float(maxi(bands - 1, 1))
		_haze.append({
			# Between the lamp bodies and the beam — the band lamp light actually
			# catches. Below this it would sit in front of the bar; above it, inside
			# the rafters where nothing is lit.
			"y": CEIL_Y + 96.0 + f * 74.0,
			# Higher band = further from the lamps = SLOWER and fainter. That is the
			# whole parallax cue and it costs one multiply.
			"speed": lerpf(6.0, 2.4, f),
			"scale": lerpf(1.0, 0.66, f),
			"alpha": lerpf(0.055, 0.030, f),
			"puffs": (4 if _low else 8),
		})


## The foreground dust. Its own node because it is the one layer that must be IN FRONT
## of the player — see the ladder note in the header.
func _build_dust() -> void:
	_dust = _Dust.new()
	_dust.set("count", DUST_LOW if _low else DUST)
	_dust.set("span", Rect2(Vector2(-260.0, DUST_TOP),
		Vector2(_town_w + 520.0, _ground_y - DUST_TOP + 20.0)))
	add_child(_dust)
	StageLayers.apply(_dust, StageLayers.DEBRIS)


# ══════════════════════════════════════════════════════════════════════ draw
## Call order IS depth. Do not reorder without reading the ladder note in the header —
## in particular `_draw_night` MUST come before `_draw_wall`, because the wall is what
## crops the night into three windows.
func _draw() -> void:
	_draw_night()
	_draw_wall()
	_draw_arch_heads()
	_draw_window_frames()
	_draw_vault()
	_draw_posts()
	_draw_bar()
	_draw_lamps()
	_draw_haze()


func _wall_left() -> float:
	return -WALL_MARGIN


func _wall_right() -> float:
	return _town_w + WALL_MARGIN


# -------------------------------------------------------------------- night
## WHAT IS OUTSIDE. Drawn full-bleed and then almost entirely painted over: only the
## three window openings survive `_draw_wall`. That is cheaper than clipping and it is
## exact, which polygon clipping at 24 Hz is not.
func _draw_night() -> void:
	_draw_moon()
	# A far roofline under the windows' horizon, hazed most of the way to the night so
	# it reads as distance rather than as a second building. Without it the glass is a
	# flat colour and the eye refuses to believe it is a hole.
	var roof: Color = StageLayers.haze(Color(0.05, 0.06, 0.11), _night, 0.55)
	var pts: PackedVector2Array = PackedVector2Array()
	var segs: int = (7 if _low else 16)
	for s: int in segs + 1:
		var t: float = float(s) / float(segs)
		var x: float = lerpf(_wall_left(), _wall_right(), t)
		var y: float = 252.0 - absf(sin(t * 7.1)) * 26.0 - absf(sin(t * 2.7 + 1.1)) * 14.0
		pts.append(Vector2(x, y))
	pts.append(Vector2(_wall_right(), WINDOW_BOTTOM + 8.0))
	pts.append(Vector2(_wall_left(), WINDOW_BOTTOM + 8.0))
	draw_colored_polygon(pts, roof)
	_draw_spire()


func _draw_moon() -> void:
	# In the LEFT window, not in open sky. Its whole job now is to prove the wall has a
	# hole in it, and a moon you can see the jamb of does that better than a big one.
	var c := Vector2(SIDE_WINDOW_X[0] + 6.0, WINDOW_TOP + 54.0)
	var pale := Color(0.90, 0.93, 1.0)
	if not _low:
		draw_circle(c, MOON_R * 3.0, Color(pale.r, pale.g, pale.b, 0.045))
	draw_circle(c, MOON_R * 1.5, Color(pale.r, pale.g, pale.b, 0.09))
	draw_circle(c, MOON_R, Color(pale.r, pale.g, pale.b, 0.88))
	# A crescent bite, cut with the NIGHT colour rather than with black — a black bite
	# is a hole, which is rule 3 of the visual grammar in `StageLayers`.
	draw_circle(c + Vector2(-MOON_R * 0.44, -MOON_R * 0.26), MOON_R * 0.94,
		Color(_night.r, _night.g, _night.b, 0.86))


## Half-width of the shaft at world y. One function so the body, the courses and the
## suite can never disagree about where the edge is.
func _spire_half_at(y: float) -> float:
	var t: float = clampf((_ground_y - y) / (_ground_y - SPIRE_TOP_Y), 0.0, 1.0)
	# Eased, not linear: a straight taper reads as a wedge. The square root keeps the
	# lower third nearly full width and does most of the narrowing high up, which is
	# what makes it read as a TOWER rather than as a pylon.
	return lerpf(SPIRE_BASE_HALF, SPIRE_TOP_HALF, sqrt(t))


func _draw_spire() -> void:
	# The body, as a stack of quads rather than one — each slice carries its own haze,
	# so the shaft dissolves upward instead of ending in a hard line. Only the slices
	# that can possibly land in the window band are drawn: everything else is painted
	# over by the wall a few lines later and was pure cost.
	var slices: int = (5 if _low else 10)
	var y0_all: float = WINDOW_BOTTOM + 20.0
	var step: float = (y0_all - (WINDOW_TOP - 40.0)) / float(slices)
	var stone := Color(0.075, 0.085, 0.125)
	for s: int in slices:
		var y0: float = y0_all - step * float(s)
		var y1: float = y0 - step
		var h0: float = _spire_half_at(y0)
		var h1: float = _spire_half_at(y1)
		var up: float = clampf(float(s) / float(slices), 0.0, 1.0)
		var col: Color = StageLayers.haze(stone, _night, lerpf(0.18, 0.62, up))
		draw_colored_polygon(PackedVector2Array([
			Vector2(_spire_x - h0, y0), Vector2(_spire_x + h0, y0),
			Vector2(_spire_x + h1, y1), Vector2(_spire_x - h1, y1),
		]), col)
	# The lit windows of the tower you are about to climb, seen across the dark. The one
	# warm thing OUTSIDE, and the reason the shape reads as inhabited rather than as a
	# cliff. Slow, unsynchronised phases so it breathes without landing on a beat.
	var rows: int = (3 if _low else 6)
	for r: int in rows:
		var wy: float = lerpf(WINDOW_BOTTOM - 14.0, WINDOW_TOP + 18.0,
			float(r) / float(maxi(rows - 1, 1)))
		var half: float = _spire_half_at(wy)
		var cols: int = (1 if _low else 2)
		for c: int in cols:
			var t: float = (float(c) + 0.5) / float(cols)
			var wx: float = _spire_x + lerpf(-half * 0.6, half * 0.6, t)
			var lit: float = 0.62 + 0.26 * sin(_phase * 0.8 + float(r) * 2.3 + float(c))
			draw_rect(Rect2(Vector2(wx - 1.0, wy - 2.5), Vector2(2.0, 5.0)),
				Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, 0.55 * lit))


# --------------------------------------------------------------------- wall
## THE ROOM'S BACK WALL, painted as bands that STOP AT THE OPENINGS.
##
## Three bands: everything above the window row, everything below it, and — inside the
## row — the GAPS between consecutive windows. That is why `_windows` is sorted: the
## gaps are `[wall_left, w0.left]`, `[w0.right, w1.left]`, … `[wN.right, wall_right]`,
## which is only a list of gaps if the list is in order.
func _draw_wall() -> void:
	var l: float = _wall_left()
	var r: float = _wall_right()
	# The roof void above the beam. Near-black WARM rather than the sky's blue-black:
	# the darkness inside a lit room takes its colour from the lamps, not from outside.
	draw_rect(Rect2(Vector2(l, SKY_TOP), Vector2(r - l, CEIL_Y - SKY_TOP)), ROOF_VOID)
	_planks(l, r, CEIL_Y + BEAM_H, WINDOW_TOP)
	_planks(l, r, WINDOW_BOTTOM, _ground_y + 40.0)
	var cursor: float = l
	for w: Rect2 in _windows:
		if w.position.x > cursor:
			_planks(cursor, w.position.x, WINDOW_TOP, WINDOW_BOTTOM)
		cursor = maxf(cursor, w.end.x)
	if cursor < r:
		_planks(cursor, r, WINDOW_TOP, WINDOW_BOTTOM)
	# THE WAINSCOT. A darker panelled band along the bottom with a lit cap — rule 1 of
	# the `StageLayers` grammar, applied to a wall rather than to a ledge. It is what
	# gives the room a horizontal to read the floor against.
	var dy: float = _ground_y - DADO_H
	draw_rect(Rect2(Vector2(l, dy), Vector2(r - l, DADO_H + 40.0)), DADO_COL)
	# ⚠ THE CAP HERE IS A MOULDING, NOT A LIT LINE, AND THAT IS A CORRECTION. Maker,
	# after playing: *"there are random yellow lines on the taverns that dont really
	# make sense"*. A 3 px CAP_LIT band run across the ENTIRE width of the room is one
	# of them: the grammar's warm cap means "you can stand on this", and a horizontal
	# amber stroke on a vertical wall promises a ledge that is not there. It is drawn
	# in TIMBER now — a dado rail is a piece of wood, and it still gives the room its
	# horizontal without claiming to be a surface.
	draw_rect(Rect2(Vector2(l, dy - 2.0), Vector2(r - l, 5.0)), TIMBER_LIT)
	# Panel divisions, on the same stride as the planks so the two grids agree.
	var px: float = l
	while px < r:
		draw_rect(Rect2(Vector2(px, dy + 8.0), Vector2(1.0, DADO_H - 16.0)),
			Color(TIMBER_DARK.r, TIMBER_DARK.g, TIMBER_DARK.b, 0.7))
		px += PLANK_W * 2.0
	# THE TIE-BEAM. The heaviest horizontal in the room, and the thing every lamp hangs
	# from — so it has to be drawn before them and read as structure.
	draw_rect(Rect2(Vector2(l, CEIL_Y), Vector2(r - l, BEAM_H)), BEAM_COL)
	# ⚠ AND SO WAS THIS ONE — the same full-width warm stroke, on the underside of the
	# beam. Deleted for the same reason: nothing you can stand on is up there.


## Vertical plank strips over `[x0, x1) x [y0, y1)`, clamped to the interval so a band
## next to a window opening cannot bleed into it.
func _planks(x0: float, x1: float, y0: float, y1: float) -> void:
	if x1 - x0 <= 0.5 or y1 - y0 <= 0.5:
		return
	draw_rect(Rect2(Vector2(x0, y0), Vector2(x1 - x0, y1 - y0)), TIMBER)
	# Alternating tone plus a seam, on a phase derived from the plank's WORLD x rather
	# than from its index — otherwise the pattern restarts at every band boundary and
	# the wall visibly shears where the windows are.
	var i: int = int(floor(x0 / PLANK_W))
	var x: float = float(i) * PLANK_W
	while x < x1:
		var lo: float = maxf(x, x0)
		var hi: float = minf(x + PLANK_W, x1)
		if hi - lo > 0.5:
			var shade: float = _hash01(float(i) * 4.7)
			var col: Color = TIMBER_DARK.lerp(TIMBER_LIT, shade * 0.75)
			draw_rect(Rect2(Vector2(lo, y0), Vector2(hi - lo, y1 - y0)),
				Color(col.r, col.g, col.b, 0.55))
			if lo > x0 + 0.5:
				draw_rect(Rect2(Vector2(lo, y0), Vector2(1.0, y1 - y0)),
					Color(TIMBER_DARK.r, TIMBER_DARK.g, TIMBER_DARK.b, 0.85))
		i += 1
		x += PLANK_W


# ------------------------------------------------------------------ windows
## The joinery: a jamb, a sill, glazing bars, and the COLD SPILL. The spill is the one
## that matters — a rim of blue light on the inside of the sill and the jamb is what
## sells "that is outside and it is colder than in here", and it is the only blue in
## the room apart from the tower itself.
func _draw_window_frames() -> void:
	var cold := Color(_accent.r, _accent.g, _accent.b, 1.0)
	for w: Rect2 in _windows:
		# Jambs + head, drawn as a frame of four bars so the opening keeps its size.
		var t: float = 5.0
		draw_rect(Rect2(w.position + Vector2(-t, -t), Vector2(w.size.x + t * 2.0, t)),
			TIMBER_DARK)
		draw_rect(Rect2(Vector2(w.position.x - t, w.position.y), Vector2(t, w.size.y)),
			TIMBER_DARK)
		draw_rect(Rect2(Vector2(w.end.x, w.position.y), Vector2(t, w.size.y)),
			TIMBER_DARK)
		# The SILL, with the grammar's lit cap on it — it is a horizontal surface and
		# it is lit from OUTSIDE, so its cap is cold rather than amber.
		draw_rect(Rect2(Vector2(w.position.x - 10.0, w.end.y), Vector2(w.size.x + 20.0, 7.0)),
			TIMBER_DARK)
		draw_rect(Rect2(Vector2(w.position.x - 10.0, w.end.y), Vector2(w.size.x + 20.0, 2.0)),
			Color(cold.r, cold.g, cold.b, 0.30))
		# Glazing bars. One fewer division on LOW, and never so many that the glass
		# stops being glass.
		var step: float = MULLION_STEP * (1.6 if _low else 1.0)
		var mx: float = w.position.x + step
		while mx < w.end.x - 2.0:
			draw_rect(Rect2(Vector2(mx, w.position.y), Vector2(1.5, w.size.y)),
				Color(TIMBER_DARK.r, TIMBER_DARK.g, TIMBER_DARK.b, 0.85))
			mx += step
		draw_rect(Rect2(Vector2(w.position.x, w.position.y + w.size.y * 0.5),
			Vector2(w.size.x, 1.5)),
			Color(TIMBER_DARK.r, TIMBER_DARK.g, TIMBER_DARK.b, 0.85))
		if _low:
			continue
		# THE SPILL. A short cold wash on the wall under the sill, fading down.
		for s: int in 5:
			var f: float = float(s) / 5.0
			draw_rect(Rect2(Vector2(w.position.x - 6.0, w.end.y + 7.0 + f * 22.0),
				Vector2(w.size.x + 12.0, 5.0)),
				Color(cold.r, cold.g, cold.b, 0.055 * (1.0 - f)))


# -------------------------------------------------------------------- posts
## The timber frame: uprights from the tie-beam to the wainscot, with a knee brace at
## the top of each. They are the room's rhythm — the thing that makes a long wall read
## as a HALL you are standing in the middle of instead of a backdrop.
##
## A post that would cross a window is skipped, because a window is a hole and you
## cannot stand a post in one.
func _draw_posts() -> void:
	var half: float = 13.0
	var top: float = CEIL_Y + BEAM_H
	var bottom: float = _ground_y - DADO_H + 4.0
	var x: float = _wall_left() + 84.0
	while x < _wall_right():
		var clear: bool = true
		for w: Rect2 in _windows:
			if x + half > w.position.x - 12.0 and x - half < w.end.x + 12.0:
				clear = false
				break
		if clear:
			draw_rect(Rect2(Vector2(x - half, top), Vector2(half * 2.0, bottom - top)),
				TIMBER_DARK)
			# One lit edge down the side the lamps are on. Same warm-rim idea the old
			# spire used, borrowed for a vertical that is now three metres away.
			draw_rect(Rect2(Vector2(x - half, top), Vector2(1.5, bottom - top)),
				Color(TIMBER_LIT.r, TIMBER_LIT.g, TIMBER_LIT.b, 0.55))
			# Knee braces, CURVED. They were two right triangles, which is what a post
			# gets in a wireframe; a real one is a bent piece of oak, and the concave
			# edge is the whole difference between drawn and built.
			for side: float in [-1.0, 1.0]:
				var reach: float = 34.0
				var pts: PackedVector2Array = PackedVector2Array([
					Vector2(x + side * half, top),
					Vector2(x + side * (half + reach), top),
				])
				# The concave face, swept from the beam back down to the post.
				var c: Vector2 = Vector2(x + side * (half + reach), top + reach)
				var a0: float = -PI * 0.5
				var a1: float = PI if side < 0.0 else 0.0
				for q: Vector2 in _arc_points(c, Vector2(reach, reach), a0, a1):
					pts.append(q)
				draw_colored_polygon(pts, TIMBER_DARK)
		x += 236.0


# ---------------------------------------------------------------------- bar
## THE BAR — the counter, the back shelf and the bottles.
##
## The bottles are the `_bottles` scatter table and they are drawn DARK with a bright
## vertical highlight, not bright with a dark outline. That is the whole reason a shelf
## of them reads as glass: what you actually see across a room is the lamp REFLECTED in
## the bottle, and the glass itself is nearly black.
func _draw_bar() -> void:
	# Back shelf carcass, behind the bottles.
	draw_rect(Rect2(Vector2(BAR_X0, SHELF_TOP - 26.0),
		Vector2(BAR_X1 - BAR_X0, SHELF_STEP * float(SHELF_ROWS) + 34.0)),
		Color(TIMBER_DARK.r, TIMBER_DARK.g, TIMBER_DARK.b, 0.95))
	for row: int in SHELF_ROWS:
		var y: float = SHELF_TOP + float(row) * SHELF_STEP
		draw_rect(Rect2(Vector2(BAR_X0, y + 2.0), Vector2(BAR_X1 - BAR_X0, 3.0)), TIMBER)
		draw_rect(Rect2(Vector2(BAR_X0, y + 2.0), Vector2(BAR_X1 - BAR_X0, 1.0)),
			Color(CAP_LIT.r, CAP_LIT.g, CAP_LIT.b, 0.22))
	for b: Dictionary in _bottles:
		var p: Vector2 = b["pos"]
		var hh: float = float(b["h"])
		var col: Color = b["col"]
		draw_rect(Rect2(Vector2(p.x - 2.5, p.y + 2.0 - hh), Vector2(5.0, hh)), col)
		draw_rect(Rect2(Vector2(p.x - 1.0, p.y + 2.0 - hh - 5.0), Vector2(2.0, 6.0)), col)
		# The glint. Slow, per-bottle phase so the shelf shimmers without any of it
		# landing together.
		var g: float = 0.45 + 0.35 * sin(_phase * 0.7 + float(b["seed"]))
		draw_rect(Rect2(Vector2(p.x - 2.0, p.y + 1.0 - hh), Vector2(1.2, hh - 2.0)),
			Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, 0.55 * g))
	# The counter: a slab with the grammar's lit cap, and a dark apron under it so the
	# silhouette detaches from the wall behind it.
	var top: float = BAR_TOP
	# ⚠ THE FRONT BOWS OUT. A bar is the one piece of furniture in a room that is
	# ALWAYS curved — you stand in it, not at it — and a flat apron was the largest
	# rectangle left in the room after the wall. The belly is drawn as the counter's
	# slab plus a fan sagging below it, so the silhouette reads as a curve at 640x360
	# without a single extra colour.
	var apron: PackedVector2Array = PackedVector2Array([
		Vector2(BAR_X0 - 10.0, top), Vector2(BAR_X1 + 16.0, top),
		Vector2(BAR_X1 + 16.0, _ground_y - 22.0),
	])
	for q: Vector2 in _arc_points(Vector2((BAR_X0 + BAR_X1) * 0.5, _ground_y - 22.0),
			Vector2((BAR_X1 - BAR_X0) * 0.5 + 13.0, 22.0), 0.0, PI):
		apron.append(q)
	apron.append(Vector2(BAR_X0 - 10.0, _ground_y - 22.0))
	draw_colored_polygon(apron, TIMBER_DARK)
	draw_rect(Rect2(Vector2(BAR_X0 - 14.0, top - 7.0), Vector2(BAR_X1 - BAR_X0 + 34.0, 9.0)),
		TIMBER)
	draw_rect(Rect2(Vector2(BAR_X0 - 14.0, top - 7.0), Vector2(BAR_X1 - BAR_X0 + 34.0, 2.5)),
		CAP_LIT)
	# Barrel stack at the counter's open end — the mass that stops the bar dead-ending
	# into open floor.
	for i: int in 2:
		var c := Vector2(BAR_X1 + BARREL_DX, _ground_y - 20.0 - float(i) * 36.0)
		draw_rect(Rect2(c - Vector2(22.0, 17.0), Vector2(44.0, 34.0)), TIMBER)
		draw_rect(Rect2(c - Vector2(22.0, 17.0), Vector2(44.0, 2.0)),
			Color(CAP_LIT.r, CAP_LIT.g, CAP_LIT.b, 0.30))
		for hoop: float in [-9.0, 9.0]:
			draw_rect(Rect2(Vector2(c.x - 22.0, c.y + hoop), Vector2(44.0, 2.0)),
				Color(BRASS.r, BRASS.g, BRASS.b, 0.75))


# ------------------------------------------------------------------- curves
## ⚠ `_draw_stair` WAS HERE AND IT IS DELETED, WHICH IS HALF OF THE "RANDOM YELLOW
## LINES" REPORT. It drew a stringer and seven treads, each tread capped with a warm
## CAP_LIT line, under `World`'s LOFT and STEP platforms — and the maker had those two
## platforms REMOVED from the room earlier the same day (*"remove the platforms on the
## training area at the entrance on the left"*). So what was left on the wall was seven
## short amber strokes climbing to nothing: marks whose meaning nobody could state, on
## a wall you cannot climb. The rule the deletion enforces is the general one — the
## grammar's warm cap MEANS "you can stand on this", so it may not be drawn on scenery
## that is not standable.
##
## What replaces it is standable for real: `World._build_ledges` puts colliders on the
## bar top and the barrel stack, both of which are already drawn objects.


## A fan of points along an arc, for a FILLED curve. `draw_arc` only strokes, and every
## curve in this room is a piece of masonry rather than a line.
func _arc_points(c: Vector2, r: Vector2, a0: float, a1: float) -> PackedVector2Array:
	var segs: int = ARCH_SEGS_LOW if _low else ARCH_SEGS
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in segs + 1:
		var t: float = float(i) / float(segs)
		var a: float = lerpf(a0, a1, t)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


## ROUND-HEADED WINDOWS, made by painting the opening's two top corners back in as
## wall. See the ⚠ on `ARCH_SEGS`: the wall subtraction can only handle rectangles, so
## the arch is cut out of the rectangle afterwards instead of being built into it.
func _draw_arch_heads() -> void:
	for w: Rect2 in _windows:
		var cx: float = w.position.x + w.size.x * 0.5
		var rx: float = w.size.x * 0.5
		# A semicircular head whose rise is half the opening's width, springing from a
		# line that far down the jamb.
		var spring: float = w.position.y + rx
		for side: float in [-1.0, 1.0]:
			var pts: PackedVector2Array = PackedVector2Array()
			pts.append(Vector2(cx + side * rx, w.position.y))
			pts.append(Vector2(cx + side * rx, spring))
			var a0: float = PI if side < 0.0 else 0.0
			var a1: float = PI * 1.5 if side < 0.0 else PI * 1.5
			for q: Vector2 in _arc_points(Vector2(cx, spring), Vector2(rx, rx), a0, a1):
				pts.append(q)
			draw_colored_polygon(pts, TIMBER)
		# The voussoir band that makes it read as an ARCH rather than as a rounded hole.
		var ring: PackedVector2Array = _arc_points(Vector2(cx, spring),
			Vector2(rx + 5.0, rx + 5.0), PI, TAU)
		var prev: Vector2 = Vector2.ZERO
		for i: int in ring.size():
			if i > 0:
				draw_line(prev, ring[i], TIMBER_DARK, 5.0)
			prev = ring[i]


## VAULT RIBS. Shallow arcs springing from the tie-beam and sagging into the room, on
## the post stride so the ceiling and the walls share one rhythm. It is the cheapest
## possible "this room has a roof over it" — three lines per rib, no fill.
func _draw_vault() -> void:
	if _low:
		return  # the ribs are pure texture; the beam alone still says "ceiling".
	var top: float = CEIL_Y + BEAM_H
	var x: float = _wall_left() + 84.0
	while x < _wall_right():
		var pts: PackedVector2Array = _arc_points(
			Vector2(x + RIB_STEP * 0.5, top - RIB_SAG),
			Vector2(RIB_STEP * 0.5, RIB_SAG * 2.0), PI * 0.15, PI * 0.85)
		var prev: Vector2 = Vector2.ZERO
		for i: int in pts.size():
			if i > 0:
				draw_line(prev, pts[i], BEAM_COL, 5.0)
			prev = pts[i]
		x += RIB_STEP


# -------------------------------------------------------------------- lamps
## THE LAMPS, AND THE REASON THE ROOM READS AS LIT RATHER THAN AS PAINTED WARM.
##
## Each is four things: a chain to the beam, a small brass body with a flame in it, a
## SHAFT of light falling from it, and a POOL of light where that shaft lands. Only the
## last two make the floor look lit; the lamp itself is almost incidental.
##
## The shaft is the most alpha-blended area in the file, so it is the first thing LOW
## drops — a phone still gets the pool and the glow, which carry most of the read.
func _draw_lamps() -> void:
	var beam_bottom: float = CEIL_Y + BEAM_H
	var step: int = (2 if _low else 1)
	var i: int = 0
	while i < LAMP_X.size():
		var lx: float = LAMP_X[i]
		var ly: float = beam_bottom + LAMP_DROP
		# The flicker is SLOW and shallow — a hanging oil lamp is not a campfire, and a
		# strobing room is the opposite of the calm the maker scored this area for.
		var flick: float = 0.90 + 0.07 * sin(_phase * 2.3 + float(i) * 1.7) \
			+ 0.03 * sin(_phase * 5.1 + float(i))
		draw_rect(Rect2(Vector2(lx - 0.75, beam_bottom), Vector2(1.5, LAMP_DROP)),
			Color(BRASS.r, BRASS.g, BRASS.b, 0.8))
		if not _low:
			# THE SHAFT. A trapezoid from the lamp to the pool, at an alpha low enough
			# that it reads as air rather than as a drawn cone.
			draw_colored_polygon(PackedVector2Array([
				Vector2(lx - LAMP_R * 0.8, ly),
				Vector2(lx + LAMP_R * 0.8, ly),
				Vector2(lx + POOL_RX * 0.86, _ground_y),
				Vector2(lx - POOL_RX * 0.86, _ground_y),
			]), Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, 0.030 * flick))
		# THE POOL on the boards.
		_ellipse(Vector2(lx, _ground_y - 1.0), POOL_RX * flick, POOL_RY,
			Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, 0.075 * flick))
		_ellipse(Vector2(lx, _ground_y - 1.0), POOL_RX * 0.55 * flick, POOL_RY * 0.62,
			Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, 0.075 * flick))
		# The lamp itself: a brass cage, a glass, a core.
		if not _low:
			draw_circle(Vector2(lx, ly), LAMP_R * 3.6,
				Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, 0.055 * flick))
		draw_circle(Vector2(lx, ly), LAMP_R * 1.9,
			Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, 0.11 * flick))
		draw_colored_polygon(PackedVector2Array([
			Vector2(lx - LAMP_R, ly - LAMP_R * 0.4),
			Vector2(lx + LAMP_R, ly - LAMP_R * 0.4),
			Vector2(lx + LAMP_R * 0.6, ly + LAMP_R),
			Vector2(lx - LAMP_R * 0.6, ly + LAMP_R),
		]), BRASS)
		draw_circle(Vector2(lx, ly + 1.0), LAMP_R * 0.55,
			Color(1.0, 0.93, 0.72, 0.92 * flick))
		i += step


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var segs: int = (10 if _low else 20)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in segs:
		var a: float = TAU * float(i) / float(segs)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


# --------------------------------------------------------------------- haze
## Slow warm haze crossing the lamp band. Drawn LAST so it passes in FRONT of the beam,
## the posts and the bar — that crossing is the one beat that says the air in here is
## thick with smoke, and it is the only reason the bands exist at all.
func _draw_haze() -> void:
	for i: int in _haze.size():
		var band: Dictionary = _haze[i]
		var by: float = float(band["y"])
		var sc: float = float(band["scale"])
		var a: float = float(band["alpha"])
		var puffs: int = int(band["puffs"])
		# Wrapped drift over a span wider than the town, so a band never pops in at the
		# edge of a camera that can pan the whole room.
		var span: float = _town_w + 900.0
		var drift: float = fmod(_phase * float(band["speed"]), span)
		for p: int in puffs:
			var pf: float = float(p)
			var base_x: float = -450.0 + span * (pf / float(puffs))
			var x: float = base_x + drift
			if x > _town_w + 450.0:
				x -= span
			var wob: float = sin(pf * 2.7 + float(i)) * 12.0
			var r: float = (62.0 + _hash01(pf + float(i) * 7.0) * 44.0) * sc
			# Three overlapping discs per puff: one is a ball, three is smoke.
			draw_circle(Vector2(x, by + wob), r, Color(LAMP_WARM.r, LAMP_WARM.g,
				LAMP_WARM.b, a))
			draw_circle(Vector2(x + r * 0.72, by + wob + r * 0.18), r * 0.72,
				Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, a * 0.85))
			draw_circle(Vector2(x - r * 0.68, by + wob + r * 0.24), r * 0.64,
				Color(LAMP_WARM.r, LAMP_WARM.g, LAMP_WARM.b, a * 0.8))


# ══════════════════════════════════════════════════════════════════════ dust
## THE LAYER IN FRONT OF YOU. Motes turning over in the lamp light, drifting down at
## 9 px/s with a sine sway, wrapping forever.
##
## ⚠ IT REPLACES THE FALLING BLOSSOM AND THAT IS A PLACE CHANGE, NOT A COLOUR ONE.
## Petals falling indoors is the single detail that would have given the whole illusion
## away, and re-tinting them warm would have kept the tell. Dust is what actually hangs
## in a lit room, and it is CIRCLES rather than tumbling diamonds because a mote has no
## shape to read at this size — the tumble was what made a petal a petal.
##
## An INNER class, deliberately: it has no `class_name`, so it needs no entry in
## `.godot/global_script_class_cache.cfg` and cannot hit the "Could not find type X in
## the current scope" trap that Sessions 6/8/9 lost real time to. It is also fully
## self-contained (its own constants, no reach back into the outer scope), which is
## what lets it stay unnamed — see `Lobby._Paper` for the alternative, where the outer
## script had to take a `class_name` purely so its inner class could see the palette.
class _Dust extends Node2D:
	const FALL: float = 9.0         # px/s. Slower than the blossom was; this is dust.
	const SWAY: float = 17.0        # px of horizontal wander, each side
	const MOTE: Color = Color(1.0, 0.86, 0.62)

	var count: int = 40
	var span: Rect2 = Rect2(0.0, 0.0, 1400.0, 1000.0)
	var phase: float = 0.0

	func _draw() -> void:
		for i: int in count:
			var fi: float = float(i)
			var h1: float = absf(fmod(sin(fi * 12.9898) * 43758.5453, 1.0))
			var h2: float = absf(fmod(sin(fi * 78.233) * 12543.245, 1.0))
			var speed: float = FALL * (0.5 + h2 * 1.0)
			# `fposmod` rather than `fmod`: the drift is always positive here, but a
			# negative `phase` (a suite scrubbing time backwards) would put half the
			# motes off-world with plain `fmod`, and the bug would only appear there.
			var y: float = span.position.y + fposmod(h1 * span.size.y + phase * speed,
				span.size.y)
			var x: float = span.position.x + h2 * span.size.x \
				+ sin(phase * 0.45 + fi) * SWAY
			# Fade in at the top and out at the bottom so nothing ever pops.
			var t: float = (y - span.position.y) / span.size.y
			var a: float = clampf(minf(t * 6.0, (1.0 - t) * 5.0), 0.0, 1.0) * 0.40
			if a < 0.02:
				continue
			# The twinkle is what makes dust catch the light rather than fall through
			# it — a mote passing out of a lamp beam should go dark.
			var tw: float = 0.35 + 0.65 * absf(sin(phase * 0.9 + fi * 1.7))
			var r: float = 0.9 + h1 * 0.9
			draw_circle(Vector2(x, y), r, Color(MOTE.r, MOTE.g, MOTE.b, a * tw))
