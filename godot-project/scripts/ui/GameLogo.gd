class_name GameLogo
extends Control
## THE MARK — a magic circle with a spire standing in it, and the wordmark under it.
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
## ⚠ ONE SPELLING. The build shipped config/name = "Ashpire" alongside a tower called
## "The Ashspire" — the same word, two ways, on the same screen. TITLE is the only place
## the name is spelled inside a drawing; GameState and TowerDef carry the other copies.

## The name. See the note above about there being exactly one of it.
const TITLE: String = "ASHPIRE"

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


## Letter-spaced by hand. A Label packs glyphs at their natural advance, which reads as
## UI; a wordmark wants air between the letters, and there is no theme constant for it.
func _draw_wordmark(centre: Vector2, box: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var px: int = int(maxf(box * 0.175, 8.0))
	var track: float = box * 0.030
	var total: float = 0.0
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
		# ASH carries the ember; PIRE is chalk. One warm word, one cold one.
		draw_string(font, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
			EMBER if i < 3 else CHALK)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
