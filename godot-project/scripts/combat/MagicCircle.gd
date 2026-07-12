class_name MagicCircle
extends Node2D
## Procedural animated ARCANE SIGIL — the Frieren/isekai "a huge magic circle
## materialises" read. Two counter-rotating runic rings, radial tick-glyphs, an
## inscribed hexagram, and a white-hot core, all element-tinted. It grows in
## (appear), holds and spins, then fades out (vanish + self-free). Reusable by
## every spectacle spell (BeamSpell muzzle sigil, DivineRay sky sigil, summons
## later). Pure Node2D draw — no scene file needed; instantiate .new() and call
## appear().

const SPIN_SPEED: float = 1.4          # rad/s of the outer assembly
const INNER_SPIN_FACTOR: float = -0.7  # inner ring counter-rotates, slower
const TICKS: int = 24                  # runic tick-marks around the ring
const GROW_TIME_DEFAULT: float = 0.28

@export var color: Color = Color(0.95, 0.4, 0.85, 1.0)
@export var radius: float = 90.0

var _phase: float = 0.0
var _alpha: float = 0.0     # 0..1 overall opacity (grow-in / fade-out)
var _scale: float = 0.4     # eases 0.4 -> 1.0 on appear, back down on vanish
var _grow_time: float = GROW_TIME_DEFAULT
var _growing: bool = false
var _vanishing: bool = false
var _vanish_time: float = 0.2
var _vanish_elapsed: float = 0.0


## Materialise the circle: fade + scale in over `grow_time`, then hold spinning.
func appear(circle_color: Color, circle_radius: float, grow_time: float = GROW_TIME_DEFAULT) -> void:
	color = circle_color
	radius = circle_radius
	_grow_time = maxf(grow_time, 0.01)
	_growing = true
	_alpha = 0.0
	_scale = 0.4
	queue_redraw()


## Fade + shrink out over `fade_time`, then free. Safe to call once.
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
		_scale = lerpf(0.4, 1.0, _alpha)
		if _alpha >= 1.0:
			_growing = false
	if _vanishing:
		_vanish_elapsed += delta
		var v: float = clampf(_vanish_elapsed / _vanish_time, 0.0, 1.0)
		_alpha = 1.0 - v
		_scale = lerpf(1.0, 1.25, v)  # bloom slightly larger as it dissolves
		if v >= 1.0:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	var a: float = _alpha
	var c: Color = color
	var ring: Color = Color(c.r, c.g, c.b, 0.9 * a)
	var soft: Color = Color(c.r, c.g, c.b, 0.5 * a)
	var white: Color = Color(1.0, 1.0, 1.0, a)

	# --- Outer assembly: two rings + runic ticks, rotating together. ---
	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED, Vector2(_scale, _scale))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, ring, 3.0)
	draw_arc(Vector2.ZERO, radius * 0.98, 0.0, TAU, 72, Color(1, 1, 1, 0.22 * a), 1.5)
	draw_arc(Vector2.ZERO, radius * 0.7, 0.0, TAU, 56, soft, 2.0)
	for i: int in TICKS:
		var ang: float = TAU * float(i) / float(TICKS)
		var dirv: Vector2 = Vector2.from_angle(ang)
		draw_line(dirv * radius * 0.72, dirv * radius * 0.95, Color(c.r, c.g, c.b, 0.55 * a), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- Inscribed hexagram, counter-rotating (the "seal"). ---
	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED * INNER_SPIN_FACTOR, Vector2(_scale, _scale))
	_draw_triangle(radius * 0.6, 0.0, ring)
	_draw_triangle(radius * 0.6, PI / 3.0, ring)  # +60° => Star-of-David hexagram
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- White-hot core glow (unrotated, pulses). ---
	var pulse: float = 0.85 + 0.15 * sin(_phase * 9.0)
	draw_circle(Vector2.ZERO, radius * 0.16 * _scale * pulse, Color(1, 1, 1, 0.45 * a))
	draw_circle(Vector2.ZERO, radius * 0.09 * _scale * pulse, white)


## Closed equilateral triangle inscribed at `r`, rotated by `offset`.
func _draw_triangle(r: float, offset: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 3:
		pts.append(Vector2.from_angle(offset - PI / 2.0 + TAU * float(i) / 3.0) * r)
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0)
