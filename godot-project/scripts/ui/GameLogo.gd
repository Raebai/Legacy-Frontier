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

## ── WHAT BURNS IN THE CLEFT. Four takes on the same silhouette, for picking between.
##
## ⚠ THEY ALL SHARE ONE TOWER ON PURPOSE. The variation is in the LIGHT, not the stone,
## because the stone is the part that has to survive a 32 px favicon and a circular
## avatar crop — redrawing it four ways would mean re-solving legibility four times for
## a decision that is really about mood. One silhouette, four things happening in the
## gap, so whichever wins is already known to work at every size.
##
##   COAL  — a plain ember disc. The quietest, and the one that reads fastest at 16 px.
##   SIGIL — a small cast circle: keyline, ticks, a counter-turning broken ring. Says
##           what the game IS, at a tenth of the Lobby circle's element count.
##   RIFT  — no disc at all; the CRACK ITSELF is lit, a wedge of fire in the stone.
##   HALO  — a full ember ring behind the tower, so the spire stands against it.
enum CleftLook { COAL, SIGIL, RIFT, HALO }
## ⚠ SIGIL IS THE DEFAULT NOW. Maker picked it out of the four: *"2 is the best"*.
@export var cleft_look: CleftLook = CleftLook.SIGIL

## ── HOW THE STONE IS CUT. Four towers under the one chosen light.
##
## The light is now FIXED and the stone varies, which is the opposite of the last round
## and is the right way round for this question: the sigil has been tuned to nest inside
## the gap between the crowns, and every cut below ends its crown at the same width, so
## that tuning holds for all four instead of needing to be redone per shape.
##
##   STEPPED   three setbacks with a cornice at each — floors stacking.
##   BATTERED  one straight batter, no floors. A monolith. Survives smallest.
##   BUTTRESS  a wide plinth under two heavy setbacks. Fortress, not spire.
##   CHAMFER   the crowns' outer corners cut away, so the tops read BROKEN OFF.
enum TowerCut { STEPPED, BATTERED, BUTTRESS, CHAMFER }
## ⚠ CHAMFER IS THE DEFAULT NOW. Maker, round two: *"I like 4"*.
@export var tower_cut: TowerCut = TowerCut.CHAMFER

## ── COLOURWAYS. Maker picked the CHAMFER cut and asked to see it in other colours.
##
## ⚠ THESE OVERRIDE, THEY DO NOT REPLACE. PAPER / CHALK / EMBER stay `const` and stay
## the defaults, because the Lobby, the wordmark and the cast circle all read them and
## none of that should move because an avatar is being recoloured. A palette is a
## per-INSTANCE choice; the brand's colours are still the brand's colours.
##
## Each row is [paper, chalk, ember] — ground, stone, fire. The ground moves as well as
## the fire on purpose: an ember on near-black and a frost sigil on near-black are not
## the same design, because a cold light over a warm-black ground reads as a mistake
## rather than as a choice.
enum Palette { EMBER, ARCANE, FROST, VERDANT, GOLD, BONE }
@export var palette: Palette = Palette.EMBER

const PALETTES: Array[Array] = [
	# EMBER — the shipped one. Ash that has not quite gone out.
	[Color(0.055, 0.052, 0.075), Color(0.93, 0.92, 0.86), Color(0.98, 0.52, 0.20)],
	# ARCANE — violet fire on a blue-black ground. The most "magic" of the six.
	[Color(0.055, 0.048, 0.090), Color(0.91, 0.90, 0.94), Color(0.68, 0.42, 1.00)],
	# FROST — a cold star in the crack. Ground cooled to match, or it reads broken.
	[Color(0.040, 0.058, 0.082), Color(0.90, 0.94, 0.96), Color(0.36, 0.82, 1.00)],
	# VERDANT — witch-light. The only one that is not obviously fire, which is why it is
	# worth seeing: it makes the tower read as cursed rather than as burning.
	[Color(0.038, 0.058, 0.050), Color(0.90, 0.94, 0.88), Color(0.44, 0.94, 0.44)],
	# GOLD — treasure, not combustion. Warmest stone of the six.
	[Color(0.062, 0.052, 0.040), Color(0.96, 0.93, 0.84), Color(1.00, 0.78, 0.28)],
	# BONE — near-monochrome, one degree of warmth. The one that would survive being
	# printed in a single colour, which is the test the others would each fail.
	[Color(0.050, 0.050, 0.055), Color(0.95, 0.94, 0.91), Color(0.86, 0.80, 0.70)],
]


## The three inks, per instance. Every drawing call below goes through these rather than
## the consts, so a palette swap cannot miss a shape.
func _paper() -> Color:
	return PALETTES[palette][0] as Color


func _chalk() -> Color:
	return PALETTES[palette][1] as Color


func _ember() -> Color:
	return PALETTES[palette][2] as Color


## ── THE CLEFT, in fractions of the emblem radius so it scales instead of only looking
## right at the size it was drawn at.
## Half-width of the tower at its base. Measured off the chosen sketch, which runs a
## half-width of 30 against a height of 78 — 0.39. At 0.78 it came out nearly as wide as
## it was tall, which reads as a gatehouse rather than a spire.
const TOWER_BASE_HW: float = 0.38
## ⚠ THE CLEFT STOPS SHORT OF THE GROUND, AND THIS IS THE WHOLE READ OF THE MARK.
## It used to run the full height, which meant the two halves never touched at any
## point — so the silhouette was two mirrored towers with a slot between them, or a
## gatehouse, and never ONE tower that had been split. Leaving the bottom third solid
## joins them into a single mass with a fissure driven down into it, which is the thing
## the mark is called. Nothing else here changed the concept; this changed whether the
## concept is legible.
const CLEFT_FOOT: float = 0.13
## Half-width of the GAP at the foot of the cleft and at the peak. It OPENS as it rises,
## because a crack is widest where it is newest and tightest where it ran out of force —
## a constant-width slot reads as machined, which is the opposite of riven.
const CLEFT_HW_FOOT: float = 0.045
const CLEFT_HW_TOP: float = 0.15
## How many stepped floors each half drops through on its outer edge.
const TOWER_TIERS: int = 3
## Where the outer edge has narrowed to by the top, as a share of the way in to the
## cleft. Tapering nearly all the way left each half a tenth of a radius wide at the
## peak — two antennae rather than a broken tower. 0.42 keeps a shoulder about a third
## of the base width, which is what reads as masonry.
const TOWER_TOP_TAPER: float = 0.70
## ⚠ THE SETBACKS ARE NOT EVEN THIRDS. They used to be, and evenly-spaced identical
## steps read as a staircase glyph rather than as mass — the eye gets a repeating unit
## and stops seeing a building. Real massing loses more width low and stacks its floors
## closer as it climbs, so these are the heights each setback sits at as a share of the
## tower, front-loaded, with the width easing in over the same run.
## ⚠ `Array[float]`, not `PackedFloat32Array`: a Packed*Array CONSTRUCTOR is a call, and
## a call is not a constant expression, so the packed spelling fails to parse as a
## `const`. The literal array is fine and this is read once per draw.
const TIER_HEIGHTS: Array[float] = [0.22, 0.45, 0.66]
const TIER_WIDTHS: Array[float] = [0.62, 0.85, 1.0]
## ⚠ HOW TALL THE TOWER STANDS IN ITS OWN DISC. It was 0.60 down / 0.62 up against a
## half-width of 0.48 — 0.96 wide against 1.22 tall, a ratio of 0.79, which is a
## GATEHOUSE. A spire has to be unmistakably taller than it is wide before any of the
## detail matters, so the mass came in and the height went up.
const TOWER_FOOT_Y: float = 0.62
const TOWER_HEAD_Y: float = 0.78
## ⚠ THE CROWN IS FLAT, NOT A NEEDLE. Running the outer edge straight into the cleft's
## top corner made each half a triangle, and two inward-leaning triangles either side of
## a dark gap read as HORNS — or, with the base attached, as a letter M. A short flat at
## the top turns each one into a broken-off tower instead of a spike. Fraction of the
## tower's height that the crown occupies.
const CROWN_H: float = 0.055
## BATTERED — where the straight taper starts. Below this the sides are parallel, so
## the tower has a footing rather than coming to the ground on a slope like a tent.
const BATTER_FOOT: float = 0.10
## BUTTRESS — the plinth's height, how far the wall steps in off it, and two setbacks.
const BUTTRESS_PLINTH: float = 0.20
const BUTTRESS_IN: float = 0.84
const BUTTRESS_HEIGHTS: Array[float] = [0.44, 0.70]
const BUTTRESS_WIDTHS: Array[float] = [0.55, 1.0]
## CHAMFER — how far below the crown the cut starts, as a share of the tower height.
const CHAMFER_DROP: float = 0.085
## The ember sitting in the cleft.
const EMBER_R: float = 0.105
## ── THE GLOW. Six steps at 8.5% alpha produced six visible CONCENTRIC RINGS, which on
## a flat dark disc reads as a compression artifact rather than as light — it was the
## weakest thing in the mark. Banding is a step-count problem, so the fix is step count
## and a falloff curve, not a different colour.
const GLOW_STEPS: int = 44
## How far past the coal the light reaches, as a multiple of its radius.
const GLOW_REACH: float = 3.2
## Per-step alpha. These COMPOSITE — 44 steps at this value stack to a strong warm core,
## so it is far smaller than the old per-step figure rather than 1/44th of nothing.
const GLOW_ALPHA: float = 0.052
## Falloff exponent. Above 2 the light stays tight around the coal and fades out early,
## which is how a coal in a slot behaves; a linear ramp washes the whole disc orange.
const GLOW_FALLOFF: float = 2.4
## The bloom that sits in FRONT of the stone. Deliberately small and weak next to the
## glow behind it: this one has to survive being drawn on chalk without tinting it.
const CORE_STEPS: int = 18
const CORE_BLOOM: float = 0.38
const CORE_ALPHA: float = 0.055
## ⚠ HOW FAR UP THE LIGHT HANGS, as a share of the radius above the emblem centre.
## Maker: *"put the ball higher"*. It sat dead-centre, which put it at the WIDEST part
## of the tower rather than in the gap — so it overlapped stone on both sides and read
## as a badge stuck on the front. Higher up the cleft has opened, so it sits IN the
## split, which is where a thing burning in a crack belongs.
const SIGIL_Y: float = 0.34
## The small cast circle. Eight ticks and nine dashes against the Lobby circle's 28 and
## 22 — the same grammar at an element count that survives being 100 px wide.
const SIGIL_TICKS: int = 8
const SIGIL_DASHES: int = 9
const SIGIL_STROKE: float = 0.015
const SIGIL_CORE: float = 0.40
## ⚠ THE EMBLEM RADIUS BELOW WHICH THE SIGIL IS NOT DRAWN AT ALL. Its thinnest stroke is
## `r * SIGIL_STROKE` = r/67, so a stroke stops being a stroke somewhere near r = 90 px
## — which is a ~210 px box, i.e. everything from the 180 px favicon down. Chosen from
## that arithmetic and then confirmed by rendering: at 32 px the ring is mud, at 96 px
## it is a sigil.
const SIGIL_MIN_R: float = 90.0
## The ring the spire stands against in HALO. Thick on purpose: a hairline ring is the
## first thing to disappear at icon size.
const HALO_R: float = 0.62
const HALO_STROKE: float = 0.055
const HALO_Y: float = 0.14
## The bloom around the ring. Widening ARCS, so the light stays on the band.
const HALO_GLOW_STEPS: int = 26
const HALO_GLOW_ALPHA: float = 0.075
const HALO_GLOW_SPREAD: float = 5.5
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
		# ⚠ THE GLOW GOES BEHIND THE MASONRY, THE COAL IN FRONT OF IT. Drawing the whole
		# ember last painted 44 translucent orange rings ACROSS the chalk, which stained
		# the lower half of the tower a dirty yellow and turned the inside of the cleft
		# into a brown smear — the two things that read worst in the first stamp. Split
		# in two, the light now comes THROUGH the crack (which is what a cleft with a
		# fire in it should do) and the stone stays stone.
		match cleft_look:
			CleftLook.HALO:
				_draw_halo(c, r, p)
				_draw_cleft_tower(c, r)
			CleftLook.RIFT:
				_draw_ember_glow(c, r, p)
				_draw_cleft_tower(c, r)
				_draw_rift(c, r, p)
			CleftLook.SIGIL:
				_draw_ember_glow(c, r, p)
				_draw_cleft_tower(c, r)
				# ⚠ THE SIGIL FALLS BACK TO THE COAL WHEN IT IS TOO SMALL TO BE A SIGIL.
				# MEASURED: rendered at 32 px the ring, the ticks and the broken ring all
				# land under one pixel each and average together into a DULL BROWN
				# SMUDGE — strictly worse than the plain disc, because at least the disc
				# stays bright. Detail that cannot resolve is not neutral, it is dirt.
				# Above the threshold the ring is the mark; below it, the coal is.
				if r >= SIGIL_MIN_R:
					_draw_sigil(c, r, p)
				else:
					_draw_ember_core(c, r, p)
			_:
				_draw_ember_glow(c, r, p)
				_draw_cleft_tower(c, r)
				_draw_ember_core(c, r, p)
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
	draw_circle(c, r * 1.03, _paper())
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
			Color(_ember().r, _ember().g, _ember().b, 0.018 + f * 0.026))


func _draw_rings(c: Vector2, r: float, p: float) -> void:
	# Outer keyline.
	draw_arc(c, r, 0.0, TAU, 96, _chalk(), maxf(r * 0.018, 1.0), true)
	# Tick ring, turning with the clock.
	var spin: float = p * SPIN
	for i: int in TICKS:
		var a: float = spin + TAU * float(i) / float(TICKS)
		var long: bool = (i % 7) == 0
		var inner: float = r * (0.86 if long else 0.91)
		draw_line(c + Vector2.from_angle(a) * inner,
			c + Vector2.from_angle(a) * (r * 0.975),
			_ember() if long else GRAPHITE, maxf(r * 0.014, 1.0), true)
	# Counter-rotating dashed ring — the read that says "this thing is casting".
	var back: float = -p * SPIN * 1.6
	for i: int in DASHES:
		var a0: float = back + TAU * float(i) / float(DASHES)
		draw_arc(c, r * 0.73, a0, a0 + TAU / float(DASHES) * 0.5, 8,
			Color(_chalk().r, _chalk().g, _chalk().b, 0.75), maxf(r * 0.012, 1.0), true)
	# Spokes, held still, so the mark has a stable skeleton under the moving parts.
	for i: int in SPOKES:
		var a: float = TAU * float(i) / float(SPOKES) + PI * 0.125
		draw_line(c + Vector2.from_angle(a) * (r * 0.60),
			c + Vector2.from_angle(a) * (r * 0.70),
			Color(GRAPHITE.r, GRAPHITE.g, GRAPHITE.b, 0.55), maxf(r * 0.010, 1.0), true)
	draw_arc(c, r * 0.58, 0.0, TAU, 72, Color(_chalk().r, _chalk().g, _chalk().b, 0.55),
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
	draw_colored_polygon(pts, _chalk())
	# The ground the tower stands on, so it is planted instead of floating in the ring.
	# Kept well inside the dashed ring — at 0.66 it crossed the ring and read as a
	# strike-through rather than as ground.
	draw_line(Vector2(c.x - r * 0.50, base_y), Vector2(c.x + r * 0.50, base_y),
		Color(_chalk().r, _chalk().g, _chalk().b, 0.7), maxf(r * 0.016, 1.0), true)
	# One lit window per tier — the only warm thing inside the silhouette, so the eye
	# lands on the tower and not on the ring around it.
	for i: int in tiers:
		var f: float = (float(i) + 0.45) / float(tiers)
		draw_circle(Vector2(c.x, base_y - span * f), maxf(r * 0.026, 1.0), _ember())


## Ash going UP, not falling — the climb again, in the particles.
func _draw_embers(c: Vector2, r: float, p: float) -> void:
	for i: int in 7:
		var jitter: float = sin(float(i) * 12.9898) * 43758.5453
		jitter -= floor(jitter)
		var rise: float = fposmod(p * 0.22 + float(i) * 0.143, 1.0)
		draw_circle(
			Vector2(c.x + (jitter - 0.5) * r * 1.25, c.y + r * 0.62 - rise * r * 1.35),
			maxf(r * 0.013, 1.0),
			Color(_ember().r, _ember().g, _ember().b, sin(rise * PI) * 0.75))


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
## ⚠ ONE POLYGON, NOT TWO MIRRORED ONES. The halves now MEET below the cleft, and two
## polygons sharing a vertical edge down the centreline would show that edge: MSAA
## resolves each polygon's coverage separately, so both sides land ~50% at the seam and
## composite to a visible hairline down the middle of a solid mass. Tracing the whole
## silhouette as a single closed loop has no interior edge to betray.
func _draw_cleft_tower(c: Vector2, r: float) -> void:
	var base_y: float = c.y + r * TOWER_FOOT_Y
	var top_y: float = c.y - r * TOWER_HEAD_Y
	var span: float = base_y - top_y
	var outer: float = r * TOWER_BASE_HW
	var foot_y: float = base_y - span * CLEFT_FOOT
	var top_w: float = r * CLEFT_HW_TOP + (outer - r * CLEFT_HW_TOP) * TOWER_TOP_TAPER

	# ⚠ ONE PROFILE, MIRRORED — NOT TWO CODE PATHS. The previous version walked the outer
	# edge upward for the left half and downward for the right, which is two chances to
	# get the same shape right and a mirror bug waiting to happen (it had to be MEASURED
	# against the mark's own reflection to rule one out). Building the right-hand profile
	# once and negating x for the left makes asymmetry unrepresentable.
	var prof: Array[Vector2] = _side_profile(base_y, top_y, span, outer, top_w)
	var pts: PackedVector2Array = PackedVector2Array()
	for v: Vector2 in prof:
		pts.append(Vector2(c.x - v.x, v.y))
	pts.append(Vector2(c.x - r * CLEFT_HW_TOP, top_y))
	# Down the face of the cleft to where it runs out, then across the solid foot.
	pts.append(Vector2(c.x - r * CLEFT_HW_FOOT, foot_y))
	pts.append(Vector2(c.x + r * CLEFT_HW_FOOT, foot_y))
	pts.append(Vector2(c.x + r * CLEFT_HW_TOP, top_y))
	for i: int in range(prof.size() - 1, -1, -1):
		pts.append(Vector2(c.x + prof[i].x, prof[i].y))
	draw_colored_polygon(pts, _chalk())


## The RIGHT-hand outer edge, bottom to crown, as offsets from the centreline. Four
## cuts of the same tower — the maker picked the SIGIL light and asked to "optimise the
## towers", so the stone is what varies now and the light is held fixed.
##
## ⚠ THE CROWN ALWAYS ENDS AT `top_w`, whatever the cut does on the way up. That is what
## keeps the gap between the crowns the same width in all four, which is what lets the
## sigil be tuned ONCE rather than per-cut.
func _side_profile(base_y: float, top_y: float, span: float,
		outer: float, top_w: float) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(outer, base_y)]
	match tower_cut:
		TowerCut.BATTERED:
			# A monolith: one straight batter from footing to crown, no floors at all.
			# The quietest silhouette and the one that survives smallest, because there is
			# nothing on the edge that can turn to fuzz.
			out.append(Vector2(outer, base_y - span * BATTER_FOOT))
		TowerCut.BUTTRESS:
			# A fortress: a wide plinth carrying two heavy setbacks. Fewer, bolder steps
			# than STEPPED, so each one still reads as a floor at avatar size instead of
			# three of them merging into a taper.
			out.append(Vector2(outer, base_y - span * BUTTRESS_PLINTH))
			out.append(Vector2(outer * BUTTRESS_IN, base_y - span * BUTTRESS_PLINTH))
			for i: int in BUTTRESS_HEIGHTS.size():
				var by: float = base_y - span * BUTTRESS_HEIGHTS[i]
				var bw: float = lerpf(outer * BUTTRESS_IN, top_w, BUTTRESS_WIDTHS[i])
				out.append(Vector2(out[out.size() - 1].x, by))
				out.append(Vector2(bw, by))
		_:
			# STEPPED and CHAMFER share the floor rhythm; they differ only at the crown.
			for i: int in TIER_HEIGHTS.size():
				var y: float = base_y - span * TIER_HEIGHTS[i]
				var w_above: float = lerpf(outer, top_w, TIER_WIDTHS[i])
				out.append(Vector2(out[out.size() - 1].x, y))
				out.append(Vector2(w_above, y))
	# The crown. STEPPED and BUTTRESS get a flat top; CHAMFER gets its outer corner cut
	# away, so the tops read as BROKEN OFF rather than as finished parapets — which is
	# the one cut that says something happened to this tower.
	if tower_cut == TowerCut.CHAMFER:
		out.append(Vector2(top_w, top_y + span * CHAMFER_DROP))
	else:
		out.append(Vector2(top_w, top_y + span * CROWN_H))
		out.append(Vector2(top_w, top_y))
	return out


## The one warm thing, and the only moving one. It sits IN the gap, so the eye is drawn
## to the split rather than to either half.
func _draw_ember_glow(c: Vector2, r: float, p: float) -> void:
	# A coal breathing, not a light blinking: the amplitude is small on purpose, and the
	# glow underneath does most of the work so the disc reads lit rather than the circle
	# reading animated.
	var breath: float = 0.5 + 0.5 * sin(p * PULSE)
	var rad: float = r * EMBER_R * (0.93 + 0.07 * breath)
	# ⚠ OUTSIDE IN, and that ordering is load-bearing. Each ring is drawn OVER the last,
	# so painting outward would put the faintest, widest wash on top of the core and
	# haze it; painting inward lets the alphas accumulate toward the middle, which is
	# what makes the centre read hot without any single ring being visible.
	var reach: float = rad * GLOW_REACH
	var sc: Vector2 = _light_centre(c, r)
	for i: int in range(GLOW_STEPS, 0, -1):
		var f: float = float(i) / float(GLOW_STEPS)      # 1 at the outer edge
		var a: float = GLOW_ALPHA * pow(1.0 - f, GLOW_FALLOFF) * (0.75 + 0.25 * breath)
		draw_circle(sc, rad + (reach - rad) * f, Color(_ember().r, _ember().g, _ember().b, a))


## Where the light hangs — up in the gap, not down at the emblem's centre. One function
## so the glow, the coal and the sigil can never drift apart from each other.
func _light_centre(c: Vector2, r: float) -> Vector2:
	return Vector2(c.x, c.y - r * SIGIL_Y)


## The coal itself, plus a short bloom tight enough to sit ON the stone without washing
## it — the halo that says "this is hot", not the light it throws into the room.
func _draw_ember_core(c: Vector2, r: float, p: float) -> void:
	var breath: float = 0.5 + 0.5 * sin(p * PULSE)
	var rad: float = r * EMBER_R * (0.93 + 0.07 * breath)
	var sc: Vector2 = _light_centre(c, r)
	for i: int in range(CORE_STEPS, 0, -1):
		var f: float = float(i) / float(CORE_STEPS)
		var a: float = CORE_ALPHA * pow(1.0 - f, 1.8) * (0.75 + 0.25 * breath)
		draw_circle(sc, rad * (1.0 + CORE_BLOOM * f), Color(_ember().r, _ember().g, _ember().b, a))
	draw_circle(sc, rad, _ember())


## SIGIL — the coal, ringed. Maker: *"maybe replace the ball with a magic circle"*, and
## it is the right instinct: every spell in the game opens a rotating sigil, so a mark
## that carries one says what the game is without a word of copy.
##
## ⚠ IT IS NOT `_draw_rings`. That has ~70 elements because it is drawn on the Lobby at
## hundreds of pixels; at avatar size it turns to grey mush, which is the entire reason
## CLEFT was split off from CAST_CIRCLE. This is the same grammar — keyline, ticks, a
## counter-turning broken ring — at an element count that survives a circular crop.
func _draw_sigil(c: Vector2, r: float, p: float) -> void:
	var breath: float = 0.5 + 0.5 * sin(p * PULSE)
	var sc: Vector2 = _light_centre(c, r)
	var rad: float = r * EMBER_R * (0.93 + 0.07 * breath)
	var lw: float = maxf(r * SIGIL_STROKE, 1.0)
	draw_arc(sc, rad, 0.0, TAU, 64, _ember(), lw, true)
	var spin: float = p * SPIN
	for i: int in SIGIL_TICKS:
		var a: float = spin + TAU * float(i) / float(SIGIL_TICKS)
		var long: bool = (i % 2) == 0
		draw_line(sc + Vector2.from_angle(a) * (rad * (1.12 if long else 1.20)),
			sc + Vector2.from_angle(a) * (rad * 1.34), _ember(), lw, true)
	var back: float = -p * SPIN * 1.6
	for i: int in SIGIL_DASHES:
		var a0: float = back + TAU * float(i) / float(SIGIL_DASHES)
		draw_arc(sc, rad * 1.56, a0, a0 + TAU / float(SIGIL_DASHES) * 0.46, 10,
			Color(_ember().r, _ember().g, _ember().b, 0.85), lw, true)
	draw_circle(sc, rad * SIGIL_CORE, _ember())


## RIFT — no disc at all. The crack itself is lit, so the fire is INSIDE the tower
## rather than parked in front of it. The simplest of the four and the boldest: two
## values, one shape, nothing to resolve at small size.
func _draw_rift(c: Vector2, r: float, p: float) -> void:
	var breath: float = 0.5 + 0.5 * sin(p * PULSE)
	var base_y: float = c.y + r * TOWER_FOOT_Y
	var top_y: float = c.y - r * TOWER_HEAD_Y
	var span: float = base_y - top_y
	var foot_y: float = base_y - span * CLEFT_FOOT
	# Exactly the cleft's own outline, so the light fills the gap and never spills onto
	# the stone — the fault that made the first glow stain the chalk yellow.
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(c.x - r * CLEFT_HW_TOP, top_y),
		Vector2(c.x + r * CLEFT_HW_TOP, top_y),
		Vector2(c.x + r * CLEFT_HW_FOOT, foot_y),
		Vector2(c.x - r * CLEFT_HW_FOOT, foot_y)])
	draw_colored_polygon(pts, Color(_ember().r, _ember().g, _ember().b, 0.90 + 0.10 * breath))


## HALO — a full ring behind the spire, so the tower is a silhouette against fire
## instead of a shape with a light on it. Thick, because a hairline ring is the first
## thing to vanish at icon size.
func _draw_halo(c: Vector2, r: float, p: float) -> void:
	var breath: float = 0.5 + 0.5 * sin(p * PULSE)
	var hc: Vector2 = Vector2(c.x, c.y - r * HALO_Y)
	var rad: float = r * HALO_R
	# ⚠ A RING GLOWS AS A RING, NOT AS A DISC. Stacking filled circles put the light
	# INSIDE the ring as well as around it, and orange at low alpha over near-black is
	# brown — so the whole interior went muddy and the tower stood in mud rather than
	# against fire. Widening arcs keep the light on the band where the ring actually is
	# and leave the middle as dark as the paper.
	var lw: float = maxf(r * HALO_STROKE, 1.5)
	for i: int in range(HALO_GLOW_STEPS, 0, -1):
		var f: float = float(i) / float(HALO_GLOW_STEPS)
		var a: float = HALO_GLOW_ALPHA * pow(1.0 - f, 2.0) * (0.75 + 0.25 * breath)
		draw_arc(hc, rad, 0.0, TAU, 96, Color(_ember().r, _ember().g, _ember().b, a),
			lw * (1.0 + HALO_GLOW_SPREAD * f), true)
	draw_arc(hc, rad, 0.0, TAU, 96, _ember(), lw, true)



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
			_ember() if i < WORDMARK_SPLIT else _chalk())
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
