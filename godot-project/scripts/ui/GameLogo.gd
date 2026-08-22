class_name GameLogo
extends Control
## THE MARK — a magic circle with a spire standing in it, and the wordmark under it,
## OR the cleft tower. Two emblems, one Control. See `Emblem`.
##
## ⚠ IT IS DRAWN, NOT IMPORTED, AND THAT IS THE POINT. The one thing this game has that
## a hundred other stick-figure brawlers do not is the CAST CIRCLE: every spell opens a
## rotating sigil under the caster, and the maker's stated bar is that those circles are
## the signature. A logo that was a piece of imported art would be the only thing in the
## product not made of the game's own vocabulary. This is built from the same primitives
## MagicCircle uses — a tick ring, a counter-rotating dashed ring, spokes — so the mark
## and the game cannot drift apart, and it renders at any size because nothing in it is
## a bitmap.
##
## Used in two places, which is why it is a Control and not a bespoke Lobby routine:
##   * the Lobby title, live and slowly turning;
##   * tools/render_logo.gd, which stamps it to PNG for the icon and the socials.
##
## ⚠ ONE SPELLING. The build once shipped config/name = "Ashpire" alongside a tower
## called "The Ashen Tower" — the same word, two ways, on the same screen. The 2026-08-22
## rename to STICKSPIRE settled it: the game is Stickspire, the tower is The Ashen
## Tower, and the two no longer rhyme. TITLE is the only place the name is spelled
## inside a drawing; GameState and TowerDef carry the other copies.

## The name. See the note above about there being exactly one of it.
const TITLE: String = "STICKSPIRE"
## Where the warm half of the compound ends — STICK|SPIRE.
const WORDMARK_SPLIT: int = 5
## The share of the mark's box the wordmark may occupy before it is shrunk to fit.
const WORDMARK_FIT: float = 0.82

# ── the look, shared with the Lobby palette ─────────────────────────────────
const PAPER: Color = Color(0.055, 0.052, 0.075)
const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)
## Ash is not grey, it is a fire that has gone out — so the mark keeps one ember in it.
const EMBER: Color = Color(0.98, 0.52, 0.20)

const TICKS: int = 28          # matches MagicCircle.TICKS
const DASHES: int = 22         # matches MagicCircle.DASH_SEGMENTS
const SPOKES: int = 8          # matches MagicCircle.SPOKES
const SPIN: float = 0.18       # a logo turns far slower than a cast circle

## ── WHICH EMBLEM ──────────────────────────────────────────────────────────────────
## ⚠ THERE ARE TWO, AND THE REASON IS A MISTAKE WORTH NOT REPEATING. The cast circle was
## replaced outright with the cleft tower when the maker picked a simpler mark for the
## socials — but this Control draws the LOBBY TITLE as well as the stamped PNGs, so
## "simplify the logo" silently took the spinning sigil off the front door too. Maker:
## *"no keep the cast circle in the lobby that was awesome ... I liked the spinning and
## stuff"*. They were right, and the two jobs have opposite requirements:
##
##   CAST_CIRCLE — the front door. Big, live, turning, ~70 elements. It is on screen at
##                 hundreds of pixels with nothing competing, and the density IS the
##                 ceremony.
##   CLEFT       — the avatar and the icon. Three shapes, no rotation. A platform draws
##                 it at ~100px inside a circular crop, where density is not detail,
##                 it is mush.
##
## Same palette, same wordmark, same file, so they cannot drift apart on colour or
## spelling — which is what having one Control was always for.
enum Emblem { CAST_CIRCLE, CLEFT }

## Defaults to the circle, so the Lobby — which sets nothing — is untouched.
@export var emblem: Emblem = Emblem.CAST_CIRCLE

## ── THE CLEFT, in fractions of the emblem radius so it scales instead of only looking
## right at the size it was drawn at.
## Half-width of the tower at its base. Measured off the chosen sketch, which runs a
## half-width of 30 against a height of 78 — 0.39. At 0.78 it came out nearly as wide as
## it was tall, which reads as a gatehouse rather than a spire.
const TOWER_BASE_HW: float = 0.48
## Half-width of the GAP. The two halves never touch — that is the whole mark, and it is
## a fraction of the radius so the split cannot be eaten as the mark shrinks.
const CLEFT_HW: float = 0.13
## How many stepped floors each half drops through on its outer edge.
const TOWER_TIERS: int = 3
## Where the outer edge has narrowed to by the top, as a share of the way in to the
## cleft. Tapering nearly all the way left each half a tenth of a radius wide at the
## peak — two antennae rather than a broken tower. 0.42 keeps a shoulder about a third
## of the base width, which is what reads as masonry.
const TOWER_TOP_TAPER: float = 0.42
## The ember sitting in the cleft.
const EMBER_R: float = 0.17
## The ember breathes. Slow on purpose — a coal, not a blinking light. The cleft never
## rotates: a tower that turns is a tower falling over.
const PULSE: float = 0.9

## Draw the wordmark under the emblem. Off for the app icon, which is square.
@export var show_wordmark: bool = true
## Emblem radius as a fraction of the smaller side (leaves room for the glow).
@export var emblem_scale: float = 1.0
## Hold the animation still — the PNG stamper wants a repeatable frame, not whatever
## phase the clock happened to be at when it fired.
@export var frozen_phase: float = -1.0

var _t: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if frozen_phase >= 0.0:
		return
	_t += delta
	queue_redraw()


func _phase() -> float:
	return frozen_phase if frozen_phase >= 0.0 else _t


func _draw() -> void:
	var wordmark_h: float = (size.y * 0.24) if show_wordmark else 0.0
	var box: float = minf(size.x, size.y - wordmark_h)
	if box <= 8.0:
		return
	var r: float = box * 0.5 * 0.86 * emblem_scale
	var c: Vector2 = Vector2(size.x * 0.5, (size.y - wordmark_h) * 0.52)
	var p: float = _phase()
	_draw_disc(c, r)
	if emblem == Emblem.CLEFT:
		_draw_cleft_tower(c, r)
		_draw_ember(c, r, p)
	else:
		_draw_rings(c, r, p)
		_draw_spire(c, r)
		_draw_embers(c, r, p)
	if show_wordmark:
		_draw_wordmark(Vector2(size.x * 0.5, size.y - wordmark_h * 0.42), box)


## ⚠ THE MARK STANDS ON ITS OWN DARK DISC, AND THE FIRST VERSION DID NOT.
## The ember was painted as a soft halo straight onto TRANSPARENCY, and orange at 3-7%
## alpha over nothing does not read as fire — it composites to a dirty grey ring, which
## is what the first stamp came back as. Warm light only reads warm when there is
## something dark behind it. The disc is also the right call for the job: an app icon
## and a social avatar are both cropped to a circle by the platform anyway, so the mark
## may as well own that circle instead of floating in a square of nothing.
func _draw_disc(c: Vector2, r: float) -> void:
	draw_circle(c, r * 1.03, PAPER)
	# Ember light INSIDE the disc, brightest at the base of the spire where the tower
	# is burning, not centred — a centred glow reads as a logo effect, an offset one
	# reads as a light source.
	# ⚠ AND THE GLOW HAS TO STAY INSIDE THE DISC. The offset hearth's widest ring
	# reached r*1.24 from centre against a disc of r*1.03, so the overspill landed on
	# transparency and produced the SAME dirty grey halo the disc was added to remove —
	# just offset downward, which reads as a drop shadow nobody asked for. The cap is
	# the geometry: OFFSET + widest radius must not exceed the disc.
	# ⚠ THE CLEFT WANTS A FLAT GROUND. This hearth exists to give seventy thin strokes
	# something warm to sit in; against three solid shapes it only turns the near-black
	# disc muddy brown and pulls the eye off the split. The cleft's ember carries its own
	# tight halo instead — light from the thing that is actually burning.
	if emblem == Emblem.CLEFT:
		return
	var offset: float = 0.34
	var hearth: Vector2 = Vector2(c.x, c.y + r * offset)
	var widest: float = 1.03 - offset
	# 16 steps rather than 7: at 7 the falloff was visibly BANDED into rings, which on
	# a mark this simple is the difference between "lit" and "drawn in Paint".
	for i: int in 16:
		var f: float = float(i) / 15.0
		draw_circle(hearth, r * widest * (1.0 - f * 0.72),
			Color(EMBER.r, EMBER.g, EMBER.b, 0.018 + f * 0.026))


func _draw_rings(c: Vector2, r: float, p: float) -> void:
	# Outer keyline.
	draw_arc(c, r, 0.0, TAU, 96, CHALK, maxf(r * 0.018, 1.0), true)
	# Tick ring, turning with the clock.
	var spin: float = p * SPIN
	for i: int in TICKS:
		var a: float = spin + TAU * float(i) / float(TICKS)
		var long: bool = (i % 7) == 0
		var inner: float = r * (0.86 if long else 0.91)
		draw_line(c + Vector2.from_angle(a) * inner,
			c + Vector2.from_angle(a) * (r * 0.975),
			EMBER if long else GRAPHITE, maxf(r * 0.014, 1.0), true)
	# Counter-rotating dashed ring — the read that says "this thing is casting".
	var back: float = -p * SPIN * 1.6
	for i: int in DASHES:
		var a0: float = back + TAU * float(i) / float(DASHES)
		draw_arc(c, r * 0.73, a0, a0 + TAU / float(DASHES) * 0.5, 8,
			Color(CHALK.r, CHALK.g, CHALK.b, 0.75), maxf(r * 0.012, 1.0), true)
	# Spokes, held still, so the mark has a stable skeleton under the moving parts.
	for i: int in SPOKES:
		var a: float = TAU * float(i) / float(SPOKES) + PI * 0.125
		draw_line(c + Vector2.from_angle(a) * (r * 0.60),
			c + Vector2.from_angle(a) * (r * 0.70),
			Color(GRAPHITE.r, GRAPHITE.g, GRAPHITE.b, 0.55), maxf(r * 0.010, 1.0), true)
	draw_arc(c, r * 0.58, 0.0, TAU, 72, Color(CHALK.r, CHALK.g, CHALK.b, 0.55),
		maxf(r * 0.010, 1.0), true)


## THE SPIRE — five tiers narrowing to a spike, which is the shape of the run: the
## tower IS the game, and it is climbed, so the silhouette reads bottom-heavy and
## points. Built from tier fractions rather than hand-placed points, so it stays
## proportional at every size instead of only looking right at the one it was drawn at.
func _draw_spire(c: Vector2, r: float) -> void:
	var base_y: float = c.y + r * 0.52
	var top_y: float = c.y - r * 0.58
	var tiers: int = 5
	var span: float = base_y - top_y
	var right: Array[Vector2] = []
	for i: int in tiers + 1:
		var f: float = float(i) / float(tiers)
		var y: float = base_y - span * f
		# The half-width tapers, with a lip at each tier so it reads as stacked floors.
		var hw: float = r * lerpf(0.44, 0.11, f)
		right.append(Vector2(c.x + hw, y))
		if i < tiers:
			# A pronounced lip, so the tiers read as FLOORS rather than as a taper.
			right.append(Vector2(c.x + hw * 1.06, y - span / float(tiers) * 0.05))
			right.append(Vector2(c.x + hw * 0.80, y - span / float(tiers) * 0.19))
	# The spike.
	right.append(Vector2(c.x + r * 0.036, top_y - r * 0.12))
	right.append(Vector2(c.x, top_y - r * 0.30))
	# Mirrored, so the silhouette is exactly symmetrical rather than nearly.
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(right.size() - 1, -1, -1):
		pts.append(Vector2(c.x - (right[i].x - c.x), right[i].y))
	for v: Vector2 in right:
		pts.append(v)
	draw_colored_polygon(pts, CHALK)
	# The ground the tower stands on, so it is planted instead of floating in the ring.
	# Kept well inside the dashed ring — at 0.66 it crossed the ring and read as a
	# strike-through rather than as ground.
	draw_line(Vector2(c.x - r * 0.50, base_y), Vector2(c.x + r * 0.50, base_y),
		Color(CHALK.r, CHALK.g, CHALK.b, 0.7), maxf(r * 0.016, 1.0), true)
	# One lit window per tier — the only warm thing inside the silhouette, so the eye
	# lands on the tower and not on the ring around it.
	for i: int in tiers:
		var f: float = (float(i) + 0.45) / float(tiers)
		draw_circle(Vector2(c.x, base_y - span * f), maxf(r * 0.026, 1.0), EMBER)


## Ash going UP, not falling — the climb again, in the particles.
func _draw_embers(c: Vector2, r: float, p: float) -> void:
	for i: int in 7:
		var jitter: float = sin(float(i) * 12.9898) * 43758.5453
		jitter -= floor(jitter)
		var rise: float = fposmod(p * 0.22 + float(i) * 0.143, 1.0)
		draw_circle(
			Vector2(c.x + (jitter - 0.5) * r * 1.25, c.y + r * 0.62 - rise * r * 1.35),
			maxf(r * 0.013, 1.0),
			Color(EMBER.r, EMBER.g, EMBER.b, sin(rise * PI) * 0.75))


## THE TOWER, CLEFT. Two mirrored halves that never meet, each stepping down and out
## from a peak at the inner edge, with a hard vertical face along the split.
##
## ⚠ BUILT FROM FRACTIONS, NOT FROM POINTS, for the same reason the old spire was: a
## hand-placed silhouette looks right at exactly one size. Everything here is a share of
## `r`, so the 32 px favicon and the 1024 px avatar are the same drawing.
##
## The split is the idea, so it is the one measurement that must never collapse: at very
## small sizes two shapes a pixel apart merge into one and the mark becomes an ordinary
## tower. `CLEFT_HW` is a fraction of the radius, so the gap scales with everything else
## rather than being eaten by it.
func _draw_cleft_tower(c: Vector2, r: float) -> void:
	var base_y: float = c.y + r * 0.60
	var top_y: float = c.y - r * 0.62
	var span: float = base_y - top_y
	var inner: float = r * CLEFT_HW
	var outer: float = r * TOWER_BASE_HW
	for side: int in 2:
		var s: float = -1.0 if side == 0 else 1.0
		var pts: PackedVector2Array = PackedVector2Array()
		# Up the outer edge, stepping in once per floor.
		pts.append(Vector2(c.x + s * outer, base_y))
		for i: int in TOWER_TIERS:
			var f0: float = float(i) / float(TOWER_TIERS)
			var f1: float = float(i + 1) / float(TOWER_TIERS)
			var top_w: float = inner + (outer - inner) * TOWER_TOP_TAPER
			var w0: float = lerpf(outer, top_w, f0)
			var w1: float = lerpf(outer, top_w, f1)
			pts.append(Vector2(c.x + s * w0, base_y - span * f1 * 0.72))
			pts.append(Vector2(c.x + s * w1, base_y - span * f1 * 0.72))
		# The shoulder, leaning up to a peak that sits over the split.
		pts.append(Vector2(c.x + s * inner, top_y))
		# ...and straight back down the face of the cleft.
		pts.append(Vector2(c.x + s * inner, base_y))
		draw_colored_polygon(pts, CHALK)


## The one warm thing, and the only moving one. It sits IN the gap, so the eye is drawn
## to the split rather than to either half.
func _draw_ember(c: Vector2, r: float, p: float) -> void:
	# A coal breathing, not a light blinking: the amplitude is small on purpose, and the
	# glow underneath does most of the work so the disc reads lit rather than the circle
	# reading animated.
	var breath: float = 0.5 + 0.5 * sin(p * PULSE)
	var rad: float = r * EMBER_R * (0.93 + 0.07 * breath)
	for i: int in 6:
		var f: float = float(i) / 5.0
		draw_circle(c, rad * (1.0 + f * 1.25),
			Color(EMBER.r, EMBER.g, EMBER.b, 0.085 * (1.0 - f) * (0.7 + 0.3 * breath)))
	draw_circle(c, rad, EMBER)



## Letter-spaced by hand. A Label packs glyphs at their natural advance, which reads as
## UI; a wordmark wants air between the letters, and there is no theme constant for it.
func _draw_wordmark(centre: Vector2, box: float) -> void:
	var font: Font = ThemeDB.fallback_font
	# ⚠ SIZED TO FIT, NOT TO A CONSTANT. 0.175 was tuned against a SEVEN-letter
	# wordmark; STICKSPIRE is ten, and the same constant simply ran the mark off both
	# sides of the circle. Rather than swap one magic number for another that the next
	# rename breaks again, measure the word and shrink until it sits inside the box.
	var px: int = int(maxf(box * 0.175, 8.0))
	var track: float = box * 0.030
	var total: float = 0.0
	for ch: String in TITLE:
		total += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
	total -= track
	if total > box * WORDMARK_FIT:
		px = int(maxf(float(px) * (box * WORDMARK_FIT) / total, 8.0))
		track = box * 0.030 * (box * WORDMARK_FIT) / total
		total = 0.0
		for ch: String in TITLE:
			total += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
		total -= track
	var x: float = centre.x - total * 0.5
	for i: int in TITLE.length():
		var ch: String = TITLE[i]
		var at: Vector2 = Vector2(x, centre.y + float(px) * 0.36)
		# Outline first, so the mark survives on any backdrop — the socials will put it
		# over a video frame, not over PAPER.
		draw_string_outline(font, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
			maxi(int(box * 0.014), 2), Color(0.02, 0.02, 0.04, 0.92))
		# STICK carries the ember; SPIRE is chalk. One warm word, one cold one — the
		# split is the compound's own seam, so it is derived rather than a loose 3.
		draw_string(font, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
			EMBER if i < WORDMARK_SPLIT else CHALK)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
