class_name MagicCircle
extends Node2D
## Procedural animated ARCANE SIGIL — the Frieren/isekai "a huge magic circle
## materialises" read. A deeply layered, multi-speed summoning circle:
##   - emanating pulse rings that ripple outward beyond the body
##   - an outer ring + a dashed "summoning" ring + runic tick-glyphs (spin CW)
##   - a counter-rotating mid ring with radial spokes (spin CCW)
##   - an inscribed hexagram (slow CW) over a counter-rotating square (CCW)
##   - bright glyph motes orbiting the seal
##   - a breathing white-hot core
## All element-tinted. It grows in (appear), spins + breathes, then blooms out
## (vanish + self-free). Reusable by every spectacle spell (beam muzzle, divine
## sky sigil, meteor sky sigil, summons). Pure Node2D draw — no scene file.

const SPIN_SPEED: float = 1.15         # rad/s base spin of the outer assembly
const TICKS: int = 28                  # runic tick-marks around the ring
const DASH_SEGMENTS: int = 22          # arc segments in the dashed summoning ring
const SPOKES: int = 8                  # radial spokes on the mid ring
const MOTES: int = 7                   # orbiting glyph motes
const PULSE_RINGS: int = 3             # emanating outward ripples
const GROW_TIME_DEFAULT: float = 0.3

@export var color: Color = Color(0.95, 0.4, 0.85, 1.0)
@export var radius: float = 130.0

var _phase: float = 0.0
var _alpha: float = 0.0     # 0..1 overall opacity (grow-in / fade-out)
var _scale: float = 0.35    # eases 0.35 -> 1.0 on appear, blooms on vanish
var _grow_time: float = GROW_TIME_DEFAULT
var _growing: bool = false
var _vanishing: bool = false
var _vanish_time: float = 0.2
var _vanish_elapsed: float = 0.0


## Materialise: fade + scale in over `grow_time`, then hold spinning + breathing.
func appear(circle_color: Color, circle_radius: float, grow_time: float = GROW_TIME_DEFAULT) -> void:
	color = circle_color
	radius = circle_radius
	_grow_time = maxf(grow_time, 0.01)
	_growing = true
	_alpha = 0.0
	_scale = 0.35
	queue_redraw()


## Bloom out over `fade_time`, then free. Safe to call once.
func vanish(fade_time: float = 0.2) -> void:
	if _vanishing:
		return
	_vanishing = true
	_growing = false
	_vanish_time = maxf(fade_time, 0.01)
	_vanish_elapsed = 0.0


func _process(delta: float) -> void:
	_phase += delta
	if _growing:
		_alpha = minf(_alpha + delta / _grow_time, 1.0)
		# Overshoot a touch on materialise, then settle to 1.0 (a satisfying snap).
		_scale = lerpf(0.35, 1.08, ease(_alpha, 0.4))
		if _alpha >= 1.0:
			_scale = 1.0
			_growing = false
	if _vanishing:
		_vanish_elapsed += delta
		var v: float = clampf(_vanish_elapsed / _vanish_time, 0.0, 1.0)
		_alpha = 1.0 - v
		_scale = lerpf(1.0, 1.5, ease(v, 0.6))  # blooms larger as it dissolves
		if v >= 1.0:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	var a: float = _alpha
	var c: Color = color
	var s: float = _scale
	var R: float = radius * s
	var ring: Color = Color(c.r, c.g, c.b, 0.9 * a)
	var soft: Color = Color(c.r, c.g, c.b, 0.5 * a)
	var white: Color = Color(1.0, 1.0, 1.0, a)
	var breath: float = 1.0 + 0.03 * sin(_phase * 4.0)  # whole-sigil breathing

	# 0. Emanating pulse rings — ripple outward beyond the body + fade.
	for i: int in PULSE_RINGS:
		var t: float = fposmod(_phase * 0.55 + float(i) / float(PULSE_RINGS), 1.0)
		var rr: float = R * (0.75 + t * 0.9)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 60, Color(c.r, c.g, c.b, (1.0 - t) * 0.22 * a), 2.0)

	# 1. Outer assembly (spins CW): main ring + inner highlight + dashed summoning
	#    ring + runic ticks.
	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED, Vector2(s, s) * breath)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 84, ring, 3.5)
	draw_arc(Vector2.ZERO, radius * 0.965, 0.0, TAU, 84, Color(1, 1, 1, 0.2 * a), 1.5)
	_draw_dashed_ring(radius * 0.88, DASH_SEGMENTS, 0.55, Color(c.r, c.g, c.b, 0.75 * a), 3.0)
	for i: int in TICKS:
		var dirv: Vector2 = Vector2.from_angle(TAU * float(i) / float(TICKS))
		draw_line(dirv * radius * 0.76, dirv * radius * 0.94, Color(c.r, c.g, c.b, 0.5 * a), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. Mid assembly (spins CCW): ring + radial spokes.
	draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.7, Vector2(s, s) * breath)
	draw_arc(Vector2.ZERO, radius * 0.64, 0.0, TAU, 60, soft, 2.0)
	for i: int in SPOKES:
		var sd: Vector2 = Vector2.from_angle(TAU * float(i) / float(SPOKES))
		draw_line(sd * radius * 0.34, sd * radius * 0.6, Color(c.r, c.g, c.b, 0.4 * a), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 3. Inscribed hexagram (slow CW).
	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED * 0.35, Vector2(s, s))
	_draw_star(radius * 0.55, 3, 0.0, ring)
	_draw_star(radius * 0.55, 3, PI / 3.0, ring)  # +60deg -> Star-of-David
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Counter-rotating inner square (CCW) — the second seal layer.
	draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.5, Vector2(s, s))
	_draw_star(radius * 0.4, 4, PI / 4.0, soft)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 5. Orbiting glyph motes (bright dots circling the seal, out of phase).
	for i: int in MOTES:
		var ang: float = _phase * 1.5 + TAU * float(i) / float(MOTES)
		var pos: Vector2 = Vector2.from_angle(ang) * R * 0.72
		var ma: float = clampf(0.55 + 0.35 * sin(_phase * 5.0 + float(i) * 1.6), 0.15, 1.0) * a
		draw_circle(pos, maxf(2.0, radius * 0.03), Color(c.r, c.g, c.b, ma * 0.4))
		draw_circle(pos, maxf(1.2, radius * 0.018), Color(1, 1, 1, ma))

	# 6. Breathing white-hot core: soft glow + a small ring + hot center.
	var pulse: float = 0.82 + 0.18 * sin(_phase * 7.5)
	draw_circle(Vector2.ZERO, radius * 0.22 * s * pulse, Color(c.r, c.g, c.b, 0.28 * a))
	draw_arc(Vector2.ZERO, radius * 0.15 * s, 0.0, TAU, 28, ring, 2.0)
	draw_circle(Vector2.ZERO, radius * 0.09 * s * pulse, white)


## `count` arc segments evenly spaced around a circle of radius `r`, each
## spanning `fill` of its slot (the rest a gap) — the dashed "summoning" ring.
func _draw_dashed_ring(r: float, count: int, fill: float, col: Color, width: float) -> void:
	var slot: float = TAU / float(count)
	for i: int in count:
		var start: float = slot * float(i)
		draw_arc(Vector2.ZERO, r, start, start + slot * fill, 6, col, width)


## Closed regular polygon (triangle/square/…) of `points` vertices inscribed at
## radius `r`, rotated by `offset`.
func _draw_star(r: float, points: int, offset: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in points:
		pts.append(Vector2.from_angle(offset - PI / 2.0 + TAU * float(i) / float(points)) * r)
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0)
