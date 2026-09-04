class_name SpellBoltVisual
extends Node2D
## The basic cast's projectile visual. Local +X is the travel axis — the parent
## Spell sets `rotation` from its direction in launch(), so this node draws along
## +X and never has to know where it is in the world.
##
## ================= WHY THIS FILE WAS REWRITTEN ===============================
## THE MAKER, LIVE, MID-PLAYTEST: "the direct attack isn't cool."
##
## He is describing the thing he fires more than everything else in the kit
## combined, so it sets the tone for the whole class whatever the ults do. What
## was here was a 5 px lozenge, a soft glow at 2.6x, and six evenly-spaced trail
## blobs — about 30 px of object total, travelling at 460 px/s. At 60 fps that is
## 7.7 px of movement per frame against a 30 px object, which is why it read as
## SLIDING rather than flying: there was no length for the eye to smear.
##
## Three structural problems, all fixed here:
##
##   1. NO MOTION. Fixed by LENGTH (see WAKE_LEN) — a long tapering wake behind
##      the head, plus off-axis slipstream, is what makes a projectile read as
##      fast. Nothing else in this file matters as much.
##   2. ONE FLAT SHAPE. A core and a glow of the same silhouette is one object
##      with a blur on it. Every bolt now has core + glow + FRINGE and an HDR
##      nose that blooms in the grade (the ChainBolt/LightningRush recipe).
##   3. ELEMENTS WERE TINTS. `set_tint` recoloured one shape eight ways, so a
##      fire bolt and a frost bolt were the same object with the hue rotated —
##      the identical criticism that forced the METEOR family's per-element
##      redesign. They are now different OBJECTS: fire is a burning comet, frost
##      is a faceted shard, lightning is a jagged filament that restrikes,
##      shadow is a hole with a rim, earth is a tumbling chip, holy is a
##      cross-flared lance, wind is a crescent of slipstream.
##
## ⚠ THE ONE HARD CONSTRAINT, and every shape below obeys it: THE WAKE GROWS
## BACKWARDS ONLY. The bolt's damaging nose stays at HEAD_HALF_LEN, which is the
## Spell.tscn collider half-length and Spell.BOLT_RADIUS. A trail behind the head
## is universally read as "already passed" and claims no space; a picture that
## reached PAST the nose would be the drawn-vs-damaged mismatch this project has
## already been bitten by six times. Do not add forward-reaching art here.

# ── silhouette ────────────────────────────────────────────────────────────────
## The bolt's DAMAGING extent. Matches Spell.tscn's RectangleShape2D (12x6) and
## Spell.BOLT_RADIUS — a measurement, not a feel number. Nothing may draw a hot,
## solid, "this is the bolt" mark beyond +HEAD_HALF_LEN on the local X axis.
const HEAD_HALF_LEN: float = 5.0
const CORE_HALF_WIDTH: float = 2.4
## How far BEHIND the head the wake reaches, in px. This is the single number
## that decides whether the bolt reads as travelling or sliding, so it is
## deliberately much longer than the head: ~9x, or six frames of travel at
## SPEED 460. UNTESTED GUESS — it is the first knob to turn on the playtest.
const WAKE_LEN: float = 46.0
## Outer soft-glow radius as a multiple of the core half-width.
const GLOW_SCALE: float = 2.8
## Fringe (the dim outermost halo, wider and much fainter than the glow) as a
## multiple of the core half-width. Three nested widths is what makes a bolt read
## as a volume of light instead of a coloured line. UNTESTED GUESS.
const FRINGE_SCALE: float = 5.2
## Stations the wake taper is sampled at. More = smoother taper; the taper is now
## ONE polygon rather than one line per station (see `_draw_wake`), so this is a
## vertex count and no longer a draw-call count.
const WAKE_SEGMENTS: int = 9
## The same at `graphics_quality = LOW`. Five stations still resolve the cubic
## falloff into a taper — the shape the whole file exists for — at 55% of the
## vertices. Not fewer: at four the head/tail ratio starts reading as a wedge.
const WAKE_SEGMENTS_LOW: int = 5

# ── animation ────────────────────────────────────────────────────────────────
## Only the shapes that genuinely need to CHANGE (flame tongues guttering,
## lightning restriking, earth tumbling) ask for redraws; the rest are static
## art moved by the parent and cost exactly one _draw for their whole lifetime.
## That distinction is why the old file refused per-frame redraws outright — in a
## bullet-heavy fight it was N redraws per frame for a near-invisible flicker.
## QUANTISED, not continuous: the shape snaps between discrete states at this
## rate, which is both cheaper and (for lightning especially) the thing that
## actually reads as electric. Same idiom as LightningRush.JITTER_HZ.
const ANIM_HZ: float = 26.0
## How often lightning re-rolls its whole filament, in Hz. Faster than ANIM_HZ
## would be pointless (nothing would render the intermediate states).
const LIGHTNING_HZ: float = 26.0
const LIGHTNING_KINKS: int = 7
## Peak lateral wander of the lightning filament, in px. Kept under the fringe
## width so the jag stays inside the bolt's own halo and the object still reads
## as one projectile rather than a scribble. UNTESTED GUESS.
const LIGHTNING_JAG: float = 3.4

# ── default palette (arcane / unset) ─────────────────────────────────────────
const CORE_COLOR: Color = Color(1.5, 1.45, 1.2, 1.0)  # HDR >1.0 so the core blooms
const TIP_COLOR: Color = Color(1.9, 1.9, 1.9, 0.98)   # HDR white-hot nose
const GLOW_COLOR: Color = Color(1.0, 0.7, 0.25, 0.35)
const TRAIL_COLOR: Color = Color(1.0, 0.58, 0.18, 0.55)

## Which OBJECT this bolt is. Set from the element by set_shape(); ARCANE is the
## fallback and is also what an elementless bolt draws.
enum Shape { ARCANE, FIRE, FROST, LIGHTNING, SHADOW, EARTH, HOLY, WIND }

## Live palette — starts at the warm defaults; set_tint() steers glow/wake fully
## toward the element colour and only nudges the hot core, so the bolt keeps its
## white-hot heart while reading unmistakably as its element.
var _core_color: Color = CORE_COLOR
var _glow_color: Color = GLOW_COLOR
var _trail_color: Color = TRAIL_COLOR
var _shape: Shape = Shape.ARCANE
## Animation clock. Only advances while _animated is true.
var _t: float = 0.0
## Last quantised tick we redrew on — the gate that keeps ANIM_HZ honest.
var _tick: int = -1
var _animated: bool = false
## Per-bolt random phase, so ten bolts in the air do not gutter in lockstep.
var _seed: float = 0.0


## ⚠ THIS CLASS IGNORED `graphics_quality` ENTIRELY. A bolt is the most numerous
## drawn object in the game and it was drawing its full desktop picture on a phone:
## nine wake commands, three nested halos (each a capsule = a line plus two filled
## circles) and then the per-element figure on top. What LOW drops is the FRINGE —
## the widest, faintest of the three halos, at 34% of the glow's alpha — and it
## coarsens the wake's taper. The core, the glow, the nose and every element's own
## silhouette are untouched, so the bolt still reads as its element and still reads
## as the same weight of projectile against everything else on screen.
## DECLARED so a headless suite can set it (the `SpawnTell` idiom).
var _low: bool = false


func _ready() -> void:
	_seed = randf() * TAU
	_low = TuningConfig.quality_is_low()
	set_process(_animated)


## Recolour the bolt toward an element colour (alphas preserved). Called by the
## parent Spell's set_element_color(); never called = the default warm look.
func set_tint(c: Color) -> void:
	_glow_color = Color(c.r, c.g, c.b, GLOW_COLOR.a)
	_trail_color = Color(c.r, c.g, c.b, TRAIL_COLOR.a)
	# HDR core: lift the element colour toward white then push >1.0 so the bolt's
	# heart BLOOMS in its own hue (shadow=violet, earth=amber, lightning=yellow)
	# instead of washing to generic white — keeps element identity through bloom.
	var lifted: Color = Color(c.r, c.g, c.b).lerp(Color(1, 1, 1), 0.4)
	var peak: float = maxf(lifted.r, maxf(lifted.g, lifted.b))
	var k: float = 1.62 / maxf(peak, 0.001)
	_core_color = Color(lifted.r * k, lifted.g * k, lifted.b * k, CORE_COLOR.a)
	queue_redraw()


## Become the element's OBJECT, not just its colour. `effect` is the
## Elements.effect_name() token ("fire"/"frost"/"lightning"/...); anything
## unrecognised (including "") stays the arcane lozenge.
func set_shape(effect: String) -> void:
	match effect:
		"fire":
			_shape = Shape.FIRE
		"frost":
			_shape = Shape.FROST
		"lightning":
			_shape = Shape.LIGHTNING
		"shadow":
			_shape = Shape.SHADOW
		"earth":
			_shape = Shape.EARTH
		"holy":
			_shape = Shape.HOLY
		"wind":
			_shape = Shape.WIND
		_:
			_shape = Shape.ARCANE
	# Only the shapes whose silhouette actually changes over time pay for a clock.
	_animated = _shape == Shape.FIRE or _shape == Shape.LIGHTNING \
		or _shape == Shape.EARTH or _shape == Shape.SHADOW
	set_process(_animated)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var hz: float = LIGHTNING_HZ if _shape == Shape.LIGHTNING else ANIM_HZ
	var tick: int = int(_t * hz)
	if tick == _tick:
		return  # inside the same quantised frame — nothing has changed to draw
	_tick = tick
	queue_redraw()


func _draw() -> void:
	# The three nested halos are shared by every shape: the FRINGE (widest,
	# faintest) then the GLOW then the CORE. Drawing them here rather than in each
	# arm is what guarantees every element reads as the same WEIGHT of projectile
	# even though the silhouettes differ.
	_draw_wake()
	_draw_halos()
	match _shape:
		Shape.FIRE:
			_draw_fire()
		Shape.FROST:
			_draw_frost()
		Shape.LIGHTNING:
			_draw_lightning()
		Shape.SHADOW:
			_draw_shadow()
		Shape.EARTH:
			_draw_earth()
		Shape.HOLY:
			_draw_holy()
		Shape.WIND:
			_draw_wind()
		_:
			_draw_arcane()


## The tapering streak behind the head — the motion cue, and the reason the bolt
## stopped reading as a sliding blob. Backwards only (see the ⚠ in the class doc).
##
## ⚠ ONE `draw_polygon`, NOT NINE `draw_line`s, AND THIS IS THE HIGHEST-LEVERAGE
## BATCH IN THE FILE. A bolt is the most numerous drawn object in the game — every
## class's primary, several a second, several in the air at once — and its wake was
## nine separate commands on every one of them. The stations, their x positions,
## their widths and their alphas are IDENTICAL to the loop this replaces; what
## changes is that the outline through those stations is submitted once, with the
## alpha carried as vertex colour.
##
## It is also, marginally, the picture the old comment already claimed. Nine butt-
## capped lines of constant width per segment are a STAIRCASE; the polygon through
## the same widths is the taper the comment described. At 0.7-5 px of width the
## difference is sub-pixel, and it is in the direction of the stated intent.
##
## ⚠ THE HEAD END IS PINNED AT `-HEAD_HALF_LEN` AND MUST STAY THERE. The class doc's
## one hard constraint: nothing may reach past the nose, because the nose is the
## damaging extent (`Spell.tscn`'s collider). This polygon only ever runs backwards.
func _draw_wake() -> void:
	var back: float = -HEAD_HALF_LEN
	var stations: int = WAKE_SEGMENTS_LOW if _low else WAKE_SEGMENTS
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize((stations + 1) * 2)
	cols.resize((stations + 1) * 2)
	for i: int in stations + 1:
		var f: float = float(i) / float(stations)
		var x: float = back - WAKE_LEN * f
		# Cubic falloff: bright and fat right behind the head, gone by the tail.
		# Linear looked like a stick; the curve is what makes it a streak.
		var k: float = (1.0 - f)
		k = k * k * k
		var w: float = maxf(CORE_HALF_WIDTH * k, 0.35)
		var col := Color(_trail_color.r, _trail_color.g, _trail_color.b, _trail_color.a * k)
		# Top edge forward, bottom edge written into the mirrored slot so the array
		# reads as one simple (non self-intersecting) outline head -> tail -> head.
		pts[i] = Vector2(x, -w)
		cols[i] = col
		pts[pts.size() - 1 - i] = Vector2(x, w)
		cols[cols.size() - 1 - i] = col
	draw_polygon(pts, cols)


## Fringe + glow + core, the shared "volume of light" the head sits inside.
func _draw_halos() -> void:
	# The fringe is three draw commands (a capsule is a line plus two end-cap
	# circles) for the faintest band of a three-band glow. Dropped on the phone;
	# the glow and the core still make the bolt a volume of light rather than a
	# coloured line, which is what the three bands were for.
	if not _low:
		var fringe := Color(_glow_color.r, _glow_color.g, _glow_color.b, _glow_color.a * 0.34)
		_capsule(Vector2(-HEAD_HALF_LEN - 5.0, 0.0), Vector2(HEAD_HALF_LEN, 0.0),
			CORE_HALF_WIDTH * FRINGE_SCALE, fringe)
	_capsule(Vector2(-HEAD_HALF_LEN - 2.5, 0.0), Vector2(HEAD_HALF_LEN, 0.0),
		CORE_HALF_WIDTH * GLOW_SCALE, _glow_color)


## The classic energy lozenge, kept as the arcane/default look — now with the
## long wake and the three-band halo the rest of the family shares.
func _draw_arcane() -> void:
	_capsule(Vector2(-HEAD_HALF_LEN, 0.0), Vector2(HEAD_HALF_LEN, 0.0),
		CORE_HALF_WIDTH, _core_color)
	draw_circle(Vector2(HEAD_HALF_LEN, 0.0), CORE_HALF_WIDTH * 0.95, TIP_COLOR, true, -1.0, true)


## FIRE — a burning comet: round molten head, guttering flame tongues streaming
## back, ember flecks shed along the wake. Reads as something ON FIRE, not as a
## dart that happens to be orange.
func _draw_fire() -> void:
	for k: int in 3:
		var len_k: float = WAKE_LEN * (0.45 + 0.22 * float(k))
		var sway: float = sin(_t * (13.0 + 4.0 * float(k)) + _seed + float(k) * 2.1) * (1.6 + 1.3 * float(k))
		var tip := Vector2(-HEAD_HALF_LEN - len_k, sway)
		var tone := Color(_trail_color.r, _trail_color.g, _trail_color.b, 0.42 - 0.1 * float(k))
		draw_line(Vector2(-HEAD_HALF_LEN, 0.0), tip, tone, 5.0 - 1.3 * float(k), true)
	for e: int in 3:
		var back: float = HEAD_HALF_LEN + 9.0 + 11.0 * float(e)
		var wob: float = sin(_t * 19.0 + _seed + float(e) * 1.7) * (1.2 + 0.8 * float(e))
		draw_circle(Vector2(-back, wob), 1.7 - 0.35 * float(e),
			Color(_core_color.r, _core_color.g, _core_color.b, 0.62 - 0.14 * float(e)), true, -1.0, true)
	# Molten head: a round burning ball, not a lozenge.
	draw_circle(Vector2(HEAD_HALF_LEN * 0.35, 0.0), CORE_HALF_WIDTH * 1.35, _core_color, true, -1.0, true)
	draw_circle(Vector2(HEAD_HALF_LEN * 0.6, 0.0), CORE_HALF_WIDTH * 0.7, TIP_COLOR, true, -1.0, true)


## FROST — a faceted shard: a hard angular dart with a bright rim and a
## refractive spine, plus two cold slipstream lines. No glow bulge, no flicker;
## ice is SHARP and still where fire is soft and moving.
func _draw_frost() -> void:
	var w: float = CORE_HALF_WIDTH * 1.15
	var body := PackedVector2Array([
		Vector2(HEAD_HALF_LEN, 0.0),
		Vector2(HEAD_HALF_LEN * 0.1, w),
		Vector2(-HEAD_HALF_LEN - 6.0, w * 0.4),
		Vector2(-HEAD_HALF_LEN - 6.0, -w * 0.4),
		Vector2(HEAD_HALF_LEN * 0.1, -w),
	])
	draw_colored_polygon(body, Color(_glow_color.r, _glow_color.g, _glow_color.b, 0.55))
	var rim: PackedVector2Array = body.duplicate()
	rim.append(body[0])
	draw_polyline(rim, _core_color, 1.2, true)
	draw_line(Vector2(-HEAD_HALF_LEN - 4.0, 0.0), Vector2(HEAD_HALF_LEN, 0.0), TIP_COLOR, 1.4, true)
	# Cold air splitting off the shoulders — speed without heat.
	draw_line(Vector2(-HEAD_HALF_LEN, w * 0.9), Vector2(-HEAD_HALF_LEN - WAKE_LEN * 0.5, w * 2.2),
		Color(_glow_color.r, _glow_color.g, _glow_color.b, 0.28), 1.2, true)
	draw_line(Vector2(-HEAD_HALF_LEN, -w * 0.9), Vector2(-HEAD_HALF_LEN - WAKE_LEN * 0.5, -w * 2.2),
		Color(_glow_color.r, _glow_color.g, _glow_color.b, 0.28), 1.2, true)


## LIGHTNING — a jagged filament that RESTRIKES: the whole shape re-rolls at
## LIGHTNING_HZ instead of sliding smoothly, which is the lesson LightningRush
## learned the hard way ("one smooth wavy line" read as corny; braided,
## quantised kinks read as electric).
func _draw_lightning() -> void:
	var pts := PackedVector2Array()
	var span: float = HEAD_HALF_LEN + WAKE_LEN * 0.55
	for i: int in LIGHTNING_KINKS + 1:
		var f: float = float(i) / float(LIGHTNING_KINKS)
		var x: float = HEAD_HALF_LEN - span * f
		# Hash on the quantised tick, so the filament SNAPS to a new shape rather
		# than drifting — a drifting bolt is a rope, not a discharge.
		var h: float = sin(float(_tick) * 12.9898 + float(i) * 78.233 + _seed) * 43758.5453
		var jag: float = (h - floorf(h) - 0.5) * 2.0 * LIGHTNING_JAG * (1.0 - f * 0.35)
		pts.append(Vector2(x, 0.0 if i == 0 else jag))
	draw_polyline(pts, Color(_glow_color.r, _glow_color.g, _glow_color.b, 0.55), 4.0, true)
	draw_polyline(pts, _core_color, 1.6, true)
	# One forked offshoot per strike, kicking off a mid vertex. Unbranched
	# lightning is the tell that it came out of a for-loop.
	var m: int = 2 + (_tick % 3)
	if m < pts.size() - 1:
		var o: Vector2 = pts[m]
		var kick := Vector2(-6.0, LIGHTNING_JAG * (2.2 if (_tick % 2) == 0 else -2.2))
		draw_line(o, o + kick, Color(_core_color.r, _core_color.g, _core_color.b, 0.7), 1.1, true)
	draw_circle(Vector2(HEAD_HALF_LEN, 0.0), CORE_HALF_WIDTH * 0.85, TIP_COLOR, true, -1.0, true)


## SHADOW — the anti-bolt. A HOLE with a violet rim rather than a light source:
## the core is near-black, the brightness lives only on the edge, and the wake is
## a pair of grasping tendrils. The same "read it by absence" grammar The
## Unmaking uses, at bolt scale.
func _draw_shadow() -> void:
	var pulse: float = 0.85 + 0.15 * sin(_t * 9.0 + _seed)
	# Rim first, then punch the void over it.
	draw_circle(Vector2(HEAD_HALF_LEN * 0.3, 0.0), CORE_HALF_WIDTH * 1.75 * pulse,
		Color(_core_color.r, _core_color.g, _core_color.b, 0.9), true, -1.0, true)
	draw_circle(Vector2(HEAD_HALF_LEN * 0.3, 0.0), CORE_HALF_WIDTH * 1.2 * pulse,
		Color(0.02, 0.0, 0.04, 1.0), true, -1.0, true)
	for s: int in 2:
		var sign_s: float = 1.0 if s == 0 else -1.0
		var curl: float = sin(_t * 7.0 + _seed + float(s) * 1.9) * 2.4
		draw_line(
			Vector2(-HEAD_HALF_LEN, sign_s * 1.2),
			Vector2(-HEAD_HALF_LEN - WAKE_LEN * 0.62, sign_s * 3.6 + curl),
			Color(_core_color.r, _core_color.g, _core_color.b, 0.35), 1.6, true)


## EARTH — a tumbling stone chip: an opaque irregular polygon that SPINS, with a
## grit wake instead of a glow. Mass, not energy — the same separation the
## avalanche makes against the meteor storm.
func _draw_earth() -> void:
	var r: float = CORE_HALF_WIDTH * 1.5
	var chip := PackedVector2Array([
		Vector2(r * 1.15, -r * 0.2), Vector2(r * 0.35, r * 0.95),
		Vector2(-r * 0.85, r * 0.55), Vector2(-r * 0.7, -r * 0.7), Vector2(r * 0.3, -r),
	])
	draw_set_transform(Vector2(HEAD_HALF_LEN * 0.3, 0.0), _t * 7.0 + _seed, Vector2.ONE)
	# ⚠ THE FILL HAS TO OUT-VALUE THE RIM. The first render used a dark 0.56/0.45/
	# 0.31 stone tone under an HDR amber outline, and under the arena's bloom the
	# rim swallowed the body: the chip read as a hollow ring, not as a rock. A lit
	# stone face plus a DARK outline is the same recipe MeteorSigil's boulder uses.
	draw_colored_polygon(chip, Color(0.86, 0.7, 0.47, 1.0))
	var edge: PackedVector2Array = chip.duplicate()
	edge.append(chip[0])
	draw_polyline(edge, Color(0.24, 0.18, 0.12, 0.95), 1.1, true)
	# One lit facet so it reads 3D while it tumbles.
	draw_colored_polygon(
		PackedVector2Array([chip[0], chip[1], Vector2.ZERO]), Color(1.0, 0.84, 0.58, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d: int in 3:
		var back: float = HEAD_HALF_LEN + 10.0 + 12.0 * float(d)
		draw_circle(Vector2(-back, sin(_t * 6.0 + float(d) * 2.2 + _seed) * 2.2), 1.5,
			Color(0.68, 0.57, 0.42, 0.24), true, -1.0, true)


## HOLY — a lance with a cross-flare at the nose. Symmetric, clean, radiant;
## nothing else in the kit draws a cross, so it is identifiable in one frame.
func _draw_holy() -> void:
	_capsule(Vector2(-HEAD_HALF_LEN - 3.0, 0.0), Vector2(HEAD_HALF_LEN, 0.0),
		CORE_HALF_WIDTH * 0.8, _core_color)
	var f: float = CORE_HALF_WIDTH * 3.4
	draw_line(Vector2(HEAD_HALF_LEN * 0.45, -f), Vector2(HEAD_HALF_LEN * 0.45, f),
		Color(_core_color.r, _core_color.g, _core_color.b, 0.75), 1.3, true)
	# The long axis of the flare stops AT the nose, never past it (see the ⚠).
	draw_line(Vector2(-HEAD_HALF_LEN - 6.0, 0.0), Vector2(HEAD_HALF_LEN, 0.0),
		Color(TIP_COLOR.r, TIP_COLOR.g, TIP_COLOR.b, 0.8), 1.0, true)
	draw_circle(Vector2(HEAD_HALF_LEN * 0.45, 0.0), CORE_HALF_WIDTH * 0.9, TIP_COLOR, true, -1.0, true)


## WIND — a crescent of compressed air with slipstream arcs peeling off it.
## Almost no core: wind is a SHAPE the air makes, so the bolt reads as an edge.
func _draw_wind() -> void:
	var w: float = CORE_HALF_WIDTH * 2.3
	var crescent := PackedVector2Array([
		Vector2(HEAD_HALF_LEN, 0.0), Vector2(-HEAD_HALF_LEN * 0.2, w),
		Vector2(-HEAD_HALF_LEN - 3.0, w * 0.55), Vector2(-HEAD_HALF_LEN * 0.5, 0.0),
		Vector2(-HEAD_HALF_LEN - 3.0, -w * 0.55), Vector2(-HEAD_HALF_LEN * 0.2, -w),
	])
	crescent.append(crescent[0])
	draw_polyline(crescent, _core_color, 1.5, true)
	for s: int in 2:
		var sign_s: float = 1.0 if s == 0 else -1.0
		draw_line(Vector2(-HEAD_HALF_LEN, sign_s * w * 0.7),
			Vector2(-HEAD_HALF_LEN - WAKE_LEN * 0.55, sign_s * w * 1.5),
			Color(_glow_color.r, _glow_color.g, _glow_color.b, 0.3), 1.2, true)
	draw_circle(Vector2(HEAD_HALF_LEN * 0.7, 0.0), CORE_HALF_WIDTH * 0.6, TIP_COLOR, true, -1.0, true)


## Elongated capsule/lozenge: a thick line with round end-caps.
func _capsule(from_point: Vector2, to_point: Vector2, half_width: float, col: Color) -> void:
	draw_line(from_point, to_point, col, half_width * 2.0, true)
	draw_circle(from_point, half_width, col, true, -1.0, true)
	draw_circle(to_point, half_width, col, true, -1.0, true)
