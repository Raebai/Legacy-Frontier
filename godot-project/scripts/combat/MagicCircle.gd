class_name MagicCircle
extends Node2D
## Procedural animated ARCANE SIGIL, in TWO orientations because this is a
## SIDE-ON 2D game and a sigil's look depends on the spell's geometry:
##
##  FACE-ON (set_orientation false) — the full summoning circle you see head-on:
##    emanating pulse rings, an outer ring + dashed summoning ring + runic ticks
##    (spin CW), a counter-rotating mid ring with radial spokes (CCW), an
##    inscribed hexagram over a counter-rotating square, orbiting glyph motes, a
##    breathing core. Used for AREA / portal spells (meteor sky sigil, summons,
##    ground AoE) — where magic pours out of a 2D disc.
##
##  EDGE-ON (set_orientation true, along the beam axis) — the sigil seen from the
##    SIDE: a thin lens/gate the beam bursts THROUGH. In side-on 2D a beam's
##    circle faces the target, so from the camera it's a LINE perpendicular to
##    the beam. Nested edge-on rings, rim glyphs orbiting (foreshortened front/
##    back), a bright central aperture, a breathing core. Used for BEAMS (the
##    Zoltraak muzzle sigil, the divine-ray sky sigil).
##
## Grows in (appear), spins + breathes, blooms out (vanish + self-free). Reusable
## by every spectacle spell. Pure Node2D draw — no scene file.

const SPIN_SPEED: float = 1.15
const TICKS: int = 28
const DASH_SEGMENTS: int = 22
const SPOKES: int = 8
const MOTES: int = 7
const PULSE_RINGS: int = 3
const GROW_TIME_DEFAULT: float = 0.3
const EDGE_TICKS: int = 12

@export var color: Color = Color(0.95, 0.4, 0.85, 1.0)
@export var radius: float = 130.0

var _phase: float = 0.0
var _alpha: float = 0.0
var _scale: float = 0.35
var _grow_time: float = GROW_TIME_DEFAULT
var _growing: bool = false
var _vanishing: bool = false
var _vanish_time: float = 0.2
var _vanish_elapsed: float = 0.0
## Orientation: face-on disc (default) or an edge-on gate aligned to an axis.
var _edge_on: bool = false
var _edge_thick: float = 0.15  # x-extent of the edge-on lens as a fraction of radius


func appear(circle_color: Color, circle_radius: float, grow_time: float = GROW_TIME_DEFAULT) -> void:
	color = circle_color
	radius = circle_radius
	_grow_time = maxf(grow_time, 0.01)
	_growing = true
	_alpha = 0.0
	_scale = 0.35
	queue_redraw()


## Orient the sigil. `edge_on` true = a thin gate seen from the side, aligned so
## `axis_dir` (the beam direction) passes through its centre; the node rotates so
## the gate is perpendicular to the beam. false = a full face-on circle.
func set_orientation(edge_on: bool, axis_dir: Vector2 = Vector2.RIGHT, thickness: float = 0.15) -> void:
	_edge_on = edge_on
	_edge_thick = clampf(thickness, 0.04, 0.5)
	rotation = axis_dir.angle() if edge_on and axis_dir != Vector2.ZERO else 0.0
	queue_redraw()


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
		_scale = lerpf(0.35, 1.08, ease(_alpha, 0.4))
		if _alpha >= 1.0:
			_scale = 1.0
			_growing = false
	if _vanishing:
		_vanish_elapsed += delta
		var v: float = clampf(_vanish_elapsed / _vanish_time, 0.0, 1.0)
		_alpha = 1.0 - v
		_scale = lerpf(1.0, 1.5, ease(v, 0.6))
		if v >= 1.0:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	if _edge_on:
		_draw_edge()
	else:
		_draw_face()


# -------------------------------------------------------------- EDGE-ON (beams)
## A thin gate seen from the side (local +x = beam axis after the node rotation;
## the gate spans local y). The beam bursts through the centre along +x.
func _draw_edge() -> void:
	var a: float = _alpha
	var c: Color = color
	var s: float = _scale
	var R: float = radius * s
	var ex: float = maxf(R * _edge_thick, 3.0)   # half-thickness (along the beam)
	var ring: Color = Color(c.r, c.g, c.b, 0.9 * a)
	var soft: Color = Color(c.r, c.g, c.b, 0.5 * a)
	var white: Color = Color(1.7, 1.7, 1.8, a)  # HDR aperture/core blooms
	var breath: float = 1.0 + 0.04 * sin(_phase * 4.0)

	# Emanating edge-on ripples, expanding along the gate.
	for i: int in PULSE_RINGS:
		var t: float = fposmod(_phase * 0.55 + float(i) / float(PULSE_RINGS), 1.0)
		var k: float = 0.75 + t * 0.9
		draw_polyline(_ellipse_pts(ex * k, R * k, 48), Color(c.r, c.g, c.b, (1.0 - t) * 0.2 * a), 2.0, true)

	# Nested edge-on rings.
	draw_polyline(_ellipse_pts(ex * breath, R * breath, 56), ring, 3.0, true)
	draw_polyline(_ellipse_pts(ex * 0.72 * breath, R * 0.72 * breath, 48), soft, 2.0, true)
	draw_polyline(_ellipse_pts(ex * 0.46, R * 0.46, 40), soft, 1.5, true)

	# Rim glyphs orbiting the edge-on ring — foreshortened, brighter at the front.
	for i: int in MOTES:
		var th: float = _phase * 1.6 + TAU * float(i) / float(MOTES)
		var pos: Vector2 = Vector2(ex * cos(th), R * 0.94 * sin(th))
		var depth: float = 0.45 + 0.55 * (0.5 + 0.5 * cos(th))  # front (cos>0) bigger/brighter
		var ma: float = clampf(0.35 + 0.5 * depth, 0.12, 1.0) * a
		draw_circle(pos, maxf(2.0, R * 0.03) * depth, Color(c.r, c.g, c.b, ma * 0.5), true, -1.0, true)
		draw_circle(pos, maxf(1.2, R * 0.02) * depth, Color(1.0, 1.0, 1.0, ma), true, -1.0, true)

	# Runic ticks around the rim, extending outward, sliding with the spin.
	for i: int in EDGE_TICKS:
		var th2: float = _phase * 1.6 + TAU * float(i) / float(EDGE_TICKS)
		var p0: Vector2 = Vector2(ex * cos(th2), R * sin(th2))
		var p1: Vector2 = Vector2(ex * 1.7 * cos(th2), R * 1.07 * sin(th2))
		draw_line(p0, p1, Color(c.r, c.g, c.b, 0.4 * a), 1.5, true)

	# Central APERTURE — the bright slit the beam bursts from (pulses).
	var pulse: float = 0.8 + 0.2 * sin(_phase * 8.0)
	draw_line(Vector2(0.0, -R * 0.62), Vector2(0.0, R * 0.62), Color(c.r, c.g, c.b, 0.55 * a), maxf(3.0, ex * 1.3) * pulse, true)
	draw_line(Vector2(0.0, -R * 0.5), Vector2(0.0, R * 0.5), white, maxf(1.5, ex * 0.5) * pulse, true)
	# Hot core.
	draw_circle(Vector2.ZERO, R * 0.12 * pulse, Color(c.r, c.g, c.b, 0.3 * a), true, -1.0, true)
	draw_circle(Vector2.ZERO, R * 0.07 * pulse, white, true, -1.0, true)


## A closed ellipse polyline with x half-extent `ex`, y half-extent `ey`.
func _ellipse_pts(ex: float, ey: float, n: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n + 1:
		var t: float = TAU * float(i) / float(n)
		pts.append(Vector2(ex * cos(t), ey * sin(t)))
	return pts


# ------------------------------------------------------------ FACE-ON (portals)
func _draw_face() -> void:
	var a: float = _alpha
	var c: Color = color
	var s: float = _scale
	var R: float = radius * s
	var ring: Color = Color(c.r, c.g, c.b, 0.9 * a)
	var soft: Color = Color(c.r, c.g, c.b, 0.5 * a)
	var white: Color = Color(1.7, 1.7, 1.8, a)  # HDR aperture/core blooms
	var breath: float = 1.0 + 0.03 * sin(_phase * 4.0)

	for i: int in PULSE_RINGS:
		var t: float = fposmod(_phase * 0.55 + float(i) / float(PULSE_RINGS), 1.0)
		var rr: float = R * (0.75 + t * 0.9)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 60, Color(c.r, c.g, c.b, (1.0 - t) * 0.22 * a), 2.0, true)

	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED, Vector2(s, s) * breath)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 84, ring, 3.5, true)
	draw_arc(Vector2.ZERO, radius * 0.965, 0.0, TAU, 84, Color(1, 1, 1, 0.2 * a), 1.5, true)
	_draw_dashed_ring(radius * 0.88, DASH_SEGMENTS, 0.55, Color(c.r, c.g, c.b, 0.75 * a), 3.0)
	for i: int in TICKS:
		var dirv: Vector2 = Vector2.from_angle(TAU * float(i) / float(TICKS))
		draw_line(dirv * radius * 0.76, dirv * radius * 0.94, Color(c.r, c.g, c.b, 0.5 * a), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.7, Vector2(s, s) * breath)
	draw_arc(Vector2.ZERO, radius * 0.64, 0.0, TAU, 60, soft, 2.0, true)
	for i: int in SPOKES:
		var sd: Vector2 = Vector2.from_angle(TAU * float(i) / float(SPOKES))
		draw_line(sd * radius * 0.34, sd * radius * 0.6, Color(c.r, c.g, c.b, 0.4 * a), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED * 0.35, Vector2(s, s))
	_draw_star(radius * 0.55, 3, 0.0, ring)
	_draw_star(radius * 0.55, 3, PI / 3.0, ring)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.5, Vector2(s, s))
	_draw_star(radius * 0.4, 4, PI / 4.0, soft)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for i: int in MOTES:
		var ang: float = _phase * 1.5 + TAU * float(i) / float(MOTES)
		var pos: Vector2 = Vector2.from_angle(ang) * R * 0.72
		var ma: float = clampf(0.55 + 0.35 * sin(_phase * 5.0 + float(i) * 1.6), 0.15, 1.0) * a
		draw_circle(pos, maxf(2.0, radius * 0.03), Color(c.r, c.g, c.b, ma * 0.4), true, -1.0, true)
		draw_circle(pos, maxf(1.2, radius * 0.018), Color(1, 1, 1, ma), true, -1.0, true)

	var pulse: float = 0.82 + 0.18 * sin(_phase * 7.5)
	draw_circle(Vector2.ZERO, radius * 0.22 * s * pulse, Color(c.r, c.g, c.b, 0.28 * a), true, -1.0, true)
	draw_arc(Vector2.ZERO, radius * 0.15 * s, 0.0, TAU, 28, ring, 2.0, true)
	draw_circle(Vector2.ZERO, radius * 0.09 * s * pulse, white, true, -1.0, true)


func _draw_dashed_ring(r: float, count: int, fill: float, col: Color, width: float) -> void:
	var slot: float = TAU / float(count)
	for i: int in count:
		var start: float = slot * float(i)
		draw_arc(Vector2.ZERO, r, start, start + slot * fill, 6, col, width, true)


func _draw_star(r: float, points: int, offset: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in points:
		pts.append(Vector2.from_angle(offset - PI / 2.0 + TAU * float(i) / float(points)) * r)
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0, true)
