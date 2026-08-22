class_name GameLogo
extends Control
## THE MARK — the tower, split, with one ember in the cleft.
##
## ⚠ IT IS DRAWN, NOT IMPORTED, AND THAT IS THE POINT. It renders at any size because
## nothing in it is a bitmap, and it followed the rename to STICKSPIRE without anyone
## redrawing anything.
##
## ⚠ THE CAST CIRCLE USED TO BE THIS MARK, AND IT WAS THE WRONG CALL. The first version
## was built from MagicCircle's own primitives — a 28-tick ring, a counter-rotating
## 22-dash ring, 8 spokes, a radial hearth — on the reasoning that the cast circle is
## the game's signature and the logo should be made of the game's vocabulary. That
## reasoning is still true about the GAME. It was wrong about the LOGO, for a reason
## that has nothing to do with taste: about seventy drawn elements inside a circle that
## a platform renders at roughly a hundred pixels is not a mark, it is texture. Maker,
## on seeing it as an avatar: *"theres too much going on in the logo"*.
##
## So the signature stays where it belongs — in the game, under every caster — and the
## mark is now the other half of the identity: THE TOWER YOU CLIMB, cleft in two, with a
## single ember burning in the gap. Three shapes. It reads at 32 px, which the ring
## never did.
##
## ⚠ AND THAT IS WHY NOTHING ROTATES ANY MORE. The old spin lived entirely on the rings;
## a tower that turns is a tower falling over. The one moving part is the ember, which
## breathes — see PULSE.
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
## Ash is not grey, it is a fire that has gone out — so the mark keeps one ember in it.
const EMBER: Color = Color(0.98, 0.52, 0.20)

## ── THE CLEFT, in fractions of the emblem radius so it scales instead of only looking
## right at the size it was drawn at.
## Half-width of the tower at its base.
##
## ⚠ MEASURED OFF THE CHOSEN SKETCH, NOT GUESSED. 0.78 came out squat: the sketch runs
## a half-width of 30 against a height of 78, i.e. 0.39, and 0.78 against a span of
## 1.22r gave 0.64 — a tower nearly as wide as it is tall, which reads as a gatehouse.
## 0.48 restores the ratio. A tower's proportions are most of what makes it read as one.
const TOWER_BASE_HW: float = 0.48
## Half-width of the GAP. The two halves never touch — that is the whole mark.
const CLEFT_HW: float = 0.13
## Where the outer edge has narrowed to by the top, as a share of the way from the base
## width in to the cleft.
##
## ⚠ THE FIRST VALUE MADE ANTENNAE. Tapering the outer edge all the way to ~1.7x the
## cleft left each half about a tenth of a radius wide at the shoulder, so the peaks
## came out as two thin spikes instead of a tower broken in half. Stopping at 0.42
## keeps a shoulder roughly a third of the base width, which is what reads as masonry.
const TOWER_TOP_TAPER: float = 0.42
## How many stepped floors each half drops through on its outer edge.
const TOWER_TIERS: int = 3
## The ember sitting in the cleft.
const EMBER_R: float = 0.17
## The ember breathes. The only animation left, and deliberately slow — this is a coal,
## not a blinking light. A tower that turns is a tower falling over, so nothing spins.
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
	_draw_cleft_tower(c, r)
	_draw_ember(c, r, p)
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
	# ⚠ AND THE DISC IS NOW FLAT. It used to carry a disc-wide radial hearth, offset down
	# to the base of the old five-tier spire. That glow existed to give seventy thin
	# strokes something warm to sit in. Against three solid shapes it did the opposite:
	# it turned the near-black ground a muddy brown and pulled the eye off the cleft.
	# The ember keeps its own tight halo (see `_draw_ember`), which is the only light
	# the mark needs — and it comes from the thing that is actually burning.


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
