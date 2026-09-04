extends Node2D
# THE TELEGRAPH DRAWING CODE AS IT STOOD BEFORE THE LEGIBILITY/COST PASS.
#
# ⚠ THIS IS A MEASURING INSTRUMENT, NOT SHIPPING CODE. Nothing in the game
# references it; only `tools/probe_tell_cost.gd` instantiates it.
#
# WHY IT EXISTS. A before/after on draw cost is worthless if the "before" is a
# number somebody remembered. Swapping the real file back and forth would work but
# is a footgun in a checkout several agents are editing at once, and `git` is not
# mine to run here. So the old `_draw` body lives on as a frozen copy that the
# probe can build side by side with the new one, in the same process, the same
# frame and the same state — which is the only way the two numbers are comparable.
#
# It is VERBATIM except for four things, each of which is required and none of
# which touches the drawing:
#   * no `class_name` (there may be exactly one `Telegraph` in the project, and it
#     is the real one);
#   * `_ready` does not join the `telegraph` group — a measuring dummy must not
#     appear on any dodging brain's threat board;
#   * the same `_bump` counters the new file carries, wired at every draw site so
#     the OLD call pattern is COUNTED rather than inferred. This is the whole
#     point: the before figure comes from running the before code.
#   * statics are this script's own, so counting here cannot contaminate
#     `Telegraph.work_stats()`.
#
# ⚠ DO NOT "FIX" ANYTHING BELOW. Every inefficiency in here is the measurement.

signal fired

const FADE_TIME: float = 0.15
const RING_COLOR: Color = Color(0.95, 0.16, 0.13, 0.9)
const CRESCENT_GHOSTS: int = 3
const CRESCENT_GHOST_STEP: float = 0.30
const CRESCENT_GHOST_FALLOFF: float = 0.45

enum Shape { CIRCLE, LINE }
enum Style { ZONE, MUZZLE, LANE, DART, GATHER, BOMB, FIST, CRESCENT }

var _radius: float = 0.0
var _windup: float = 0.0
var _elapsed: float = 0.0
var _running: bool = false
var _has_fired: bool = false
var _shape: Shape = Shape.CIRCLE
var _length: float = 0.0
var _width: float = 0.0
var _angle: float = 0.0

var source: Node2D = null
var accent: Color = RING_COLOR
var style: Style = Style.ZONE
var aim_dir: Vector2 = Vector2.RIGHT
var reach: float = 120.0

static var _work_calls: int = 0
static var _work_segments: int = 0
static var _work_tells: int = 0
static var _work_reach: float = 0.0


static func work_stats() -> Dictionary:
	return {
		"calls": _work_calls, "segments": _work_segments,
		"tells": _work_tells, "reach": _work_reach,
	}


static func reset_work() -> void:
	_work_calls = 0
	_work_segments = 0
	_work_tells = 0
	_work_reach = 0.0


func _bump(segs: int, r: float) -> void:
	_work_calls += 1
	_work_segments += segs
	if r > _work_reach:
		_work_reach = r


func start(radius: float, windup: float) -> void:
	_radius = radius
	_windup = maxf(windup, 0.001)
	_elapsed = 0.0
	_running = true
	_has_fired = false
	queue_redraw()


func start_line(length: float, width: float, angle: float, windup: float) -> void:
	_shape = Shape.LINE
	_length = length
	_width = width
	_angle = angle
	if style == Style.ZONE:
		style = Style.LANE
	start(maxf(width, 1.0), windup)


func advance(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	if not _has_fired and _elapsed >= _windup:
		_has_fired = true
		fired.emit()
	if _has_fired and _elapsed >= _windup + FADE_TIME:
		_running = false
		queue_free()
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return
	_work_tells += 1
	if _shape == Shape.LINE:
		if style == Style.FIST:
			_draw_fist()
		elif style == Style.CRESCENT:
			_draw_crescent()
		else:
			_draw_lane()
		return
	if _has_fired:
		_draw_fired_circle()
		return
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	match style:
		Style.MUZZLE:
			_draw_muzzle(t)
		Style.GATHER:
			_draw_gather(t)
		Style.BOMB:
			_draw_bomb(t)
		Style.DART:
			_draw_dart(t)
		_:
			_draw_zone(t)
	if style == Style.ZONE or style == Style.DART:
		_draw_tether(t)


func _draw_tether(t: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	var from: Vector2 = to_local(source.global_position)
	var to: Vector2 = Vector2.ZERO
	if from.distance_to(to) < 4.0:
		return
	var c: Color = accent
	draw_line(from, to, Color(c.r, c.g, c.b, (0.12 + 0.22 * t)), 1.5)
	_bump(1, 0.0)
	for i: int in 2:
		var f: float = fposmod(_elapsed * 2.2 + 0.5 * float(i), 1.0)
		var p: Vector2 = from.lerp(to, f)
		draw_circle(p, 2.4, Color(c.r, c.g, c.b, (0.7 * t) * (1.0 - f * 0.4)))
		_bump(1, 0.0)


func _draw_fired_circle() -> void:
	var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
	var c: Color = accent
	draw_circle(Vector2.ZERO, _radius, Color(c.r, c.g, c.b, 0.4 * fade))
	_bump(1, _radius)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.7 * fade), 3.0)
	_bump(48, _radius)


func _draw_runic_ticks(r: float, count: int, spin: float, col: Color) -> void:
	for i: int in count:
		var th: float = spin + TAU * float(i) / float(count)
		var dirv: Vector2 = Vector2.from_angle(th)
		draw_line(dirv * r * 0.82, dirv * r, col, 1.5)
		_bump(1, r)


func _draw_zone(t: float) -> void:
	var danger: Color = accent
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(danger.r, danger.g, danger.b, 0.85), 2.0)
	_bump(48, _radius)
	var pulse: float = 1.0 + 0.05 * sin(_elapsed * 26.0) * t
	var inner_r: float = minf(_radius * t * pulse, _radius)
	var fill := Color(1.0, lerpf(0.5, 0.14, t), lerpf(0.28, 0.11, t), lerpf(0.16, 0.5, t))
	draw_circle(Vector2.ZERO, inner_r, fill)
	_bump(1, inner_r)
	if inner_r > 2.0:
		draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, 40, Color(1.0, 0.32, 0.18, 0.25 + 0.65 * t), 2.0)
		_bump(40, inner_r)


func _draw_muzzle(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	var spin: float = _elapsed * 2.2
	var dir: Vector2 = aim_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var end: Vector2 = dir * reach
	draw_line(Vector2.ZERO, end, Color(c.r, c.g, c.b, 0.12 + 0.2 * t), 1.5)
	_bump(1, reach)
	draw_line(Vector2.ZERO, dir * reach * (0.2 + 0.8 * t), Color(1.0, 1.0, 1.0, 0.25 + 0.45 * t), 1.5)
	_bump(1, reach)
	var ret_r: float = 5.0 + 2.0 * sin(_elapsed * 8.0)
	draw_arc(end, ret_r, 0.0, TAU, 16, Color(c.r, c.g, c.b, 0.5 + 0.4 * t), 1.5)
	_bump(16, reach + ret_r)
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.8), 2.0)
	_bump(32, R)
	_draw_runic_ticks(R * 0.92, 8, spin, Color(c.r, c.g, c.b, 0.5))
	draw_arc(Vector2.ZERO, R * 0.6, 0.0, TAU, 24, Color(c.r, c.g, c.b, 0.4), 1.5)
	_bump(24, R * 0.6)
	var core: float = R * (0.18 + 0.22 * t)
	draw_circle(Vector2.ZERO, core, Color(c.r, c.g, c.b, 0.4))
	_bump(1, core)
	draw_circle(Vector2.ZERO, core * 0.5, Color(1.0, 1.0, 1.0, 0.5 + 0.4 * t))
	_bump(1, core * 0.5)


func _draw_gather(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	for i: int in 3:
		var f: float = fposmod(-_elapsed * 0.6 + float(i) / 3.0, 1.0)
		draw_arc(Vector2.ZERO, R * (0.4 + f * 1.1), 0.0, TAU, 40, Color(c.r, c.g, c.b, (1.0 - f) * 0.3), 2.0)
		_bump(40, R * (0.4 + f * 1.1))
	var spin: float = _elapsed * 1.6
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.85), 2.5)
	_bump(48, R)
	_draw_runic_ticks(R * 0.9, 10, spin, Color(c.r, c.g, c.b, 0.5))
	_draw_star(R * 0.62, 3, -spin * 0.8, Color(c.r, c.g, c.b, 0.7))
	_draw_star(R * 0.62, 3, -spin * 0.8 + PI, Color(c.r, c.g, c.b, 0.7))
	var core: float = R * (0.14 + 0.26 * t)
	draw_circle(Vector2.ZERO, core, Color(c.r, c.g, c.b, 0.35))
	_bump(1, core)
	draw_circle(Vector2.ZERO, core * 0.5, Color(1.0, 1.0, 1.0, 0.4 + 0.5 * t))
	_bump(1, core * 0.5)


func _draw_star(r: float, points: int, offset: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in points:
		pts.append(Vector2.from_angle(offset - PI / 2.0 + TAU * float(i) / float(points)) * r)
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0)
	_bump(points, r)


func _draw_bomb(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 56, Color(c.r, c.g, c.b, 0.8), 2.5)
	_bump(56, R)
	_draw_runic_ticks(R * 0.94, 16, _elapsed * 0.8, Color(c.r, c.g, c.b, 0.4))
	draw_arc(Vector2.ZERO, R * 0.8, -PI / 2.0, -PI / 2.0 + TAU * t, 48, Color(1.0, 0.5, 0.15, 0.85), 4.0)
	_bump(48, R * 0.8)
	var pulse: float = 1.0 + 0.08 * sin(_elapsed * (10.0 + 30.0 * t))
	var inner_r: float = R * (0.15 + 0.5 * t) * pulse
	draw_circle(Vector2.ZERO, inner_r, Color(1.0, lerpf(0.4, 0.1, t), 0.1, 0.2 + 0.4 * t))
	_bump(1, inner_r)
	draw_circle(Vector2.ZERO, R * 0.1 * pulse, Color(1.0, 0.95, 0.8, 0.5 + 0.5 * t))
	_bump(1, R * 0.1 * pulse)


func _draw_dart(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	var spin: float = _elapsed * 4.0
	draw_arc(Vector2.ZERO, R, spin, spin + TAU * 0.9, 24, Color(c.r, c.g, c.b, 0.6 + 0.3 * t), 2.0)
	_bump(24, R)
	var gap: float = R * (1.4 - 0.5 * t)
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dirv: Vector2 = Vector2.from_angle(a + spin)
		draw_line(dirv * gap, dirv * (gap + R * 0.5), Color(c.r, c.g, c.b, 0.5 + 0.4 * t), 2.0)
		_bump(1, gap + R * 0.5)
	draw_circle(Vector2.ZERO, R * 0.12, Color(1.0, 1.0, 1.0, 0.4 + 0.5 * t))
	_bump(1, R * 0.12)


func _draw_lane() -> void:
	var c: Color = accent
	if _has_fired:
		var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
		draw_rect(Rect2(0.0, -_width * 0.5, _length, _width), Color(1.0, 0.5, 0.2, 0.4 * fade), true)
		_bump(1, _length)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	var hw: float = _width * 0.5
	draw_rect(Rect2(0.0, -hw, _length, _width), Color(c.r, c.g, c.b, 0.1 + 0.12 * t), false)
	_bump(4, _length)
	var grow: float = _length * (0.15 + 0.85 * t)
	draw_rect(Rect2(0.0, -hw, grow, _width), Color(c.r, c.g, c.b, 0.14 + 0.28 * t), true)
	_bump(1, grow)
	var spacing: float = 26.0
	var scroll: float = fposmod(_elapsed * 160.0, spacing)
	var x: float = scroll
	while x < grow:
		draw_polyline(PackedVector2Array([
			Vector2(x - 8.0, -hw * 0.7), Vector2(x, 0.0), Vector2(x - 8.0, hw * 0.7),
		]), Color(1.0, 1.0, 1.0, 0.3 + 0.4 * t), 2.0)
		_bump(2, x)
		x += spacing
	draw_line(Vector2.ZERO, Vector2(grow, 0.0), Color(1.0, 1.0, 1.0, 0.35 + 0.4 * t), 2.0)
	_bump(1, grow)
	draw_colored_polygon(PackedVector2Array([
		Vector2(grow + 10.0, 0.0), Vector2(grow - 4.0, -hw), Vector2(grow - 4.0, hw),
	]), Color(c.r, c.g, c.b, 0.6 + 0.35 * t))
	_bump(3, grow + 10.0)
	draw_arc(Vector2.ZERO, hw * 1.1, 0.0, TAU, 20, Color(c.r, c.g, c.b, 0.6 + 0.3 * t), 2.0)
	_bump(20, hw * 1.1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_fist() -> void:
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	var dir: Vector2 = Vector2.from_angle(_angle)
	var fade: float = 1.0
	if _has_fired:
		fade = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		t = 1.0
	var c: Color = accent
	var reach_now: float = _length * (0.12 + 0.88 * t)
	var at: Vector2 = dir * reach_now
	var rr: float = maxf(_width * 0.5, 3.0)
	draw_line(Vector2.ZERO, dir * _length, Color(c.r, c.g, c.b, 0.10 * fade), 1.0, true)
	_bump(1, _length)
	draw_line(at - dir * rr * 2.2, at, Color(c.r, c.g, c.b, 0.35 * fade), rr * 0.9, true)
	_bump(1, reach_now)
	draw_circle(at, rr * fade, Color(c.r, c.g, c.b, 0.85 * fade))
	_bump(1, reach_now + rr)
	draw_circle(at, rr * 0.55 * fade, Color(1.0, 1.0, 1.0, 0.7 * fade))
	_bump(1, reach_now + rr * 0.55)
	var perp: Vector2 = dir.orthogonal()
	for sgn: float in [-1.0, 1.0]:
		draw_line(at + perp * rr * 0.55 * sgn, at + dir * rr * 0.9 + perp * rr * 0.3 * sgn,
			Color(c.r, c.g, c.b, 0.6 * fade), 1.4, true)
		_bump(1, reach_now + rr * 0.9)


func _draw_crescent() -> void:
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	var dir: Vector2 = Vector2.from_angle(_angle)
	var fade: float = 1.0
	if _has_fired:
		fade = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		t = 1.0
	var c: Color = accent
	var perp: Vector2 = dir.orthogonal()
	var reach_now: float = _length * (0.10 + 0.90 * t)
	var half: float = maxf(_width * 1.5, 11.0) * (0.45 + 0.55 * t)
	draw_line(Vector2.ZERO, dir * _length, Color(c.r, c.g, c.b, 0.10 * fade), 1.0, true)
	_bump(1, _length)
	var steps: int = 22
	for ghost: int in CRESCENT_GHOSTS + 1:
		var back: float = float(ghost) * CRESCENT_GHOST_STEP
		var lead: float = reach_now - half * back
		if lead <= 0.0:
			continue
		var g_fade: float = fade * pow(CRESCENT_GHOST_FALLOFF, float(ghost))
		var g_half: float = half * (1.0 - 0.16 * float(ghost))
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		var spine := PackedVector2Array()
		var far: float = 0.0
		for i: int in steps + 1:
			var off: float = (float(i) / float(steps) - 0.5) * 2.0
			var belly: float = 1.0 - off * off
			var bow: float = belly * g_half * 0.9
			var thick: float = belly * maxf(_width * 0.5, 3.5) * (0.4 + 0.6 * t)
			var mid: Vector2 = dir * (lead + bow) + perp * off * g_half
			spine.append(mid)
			outer.append(mid + dir * thick)
			inner.append(mid - dir * thick)
			far = maxf(far, mid.length() + thick)
		for i: int in inner.size():
			outer.append(inner[inner.size() - 1 - i])
		draw_colored_polygon(outer, Color(c.r, c.g, c.b, 0.42 * g_fade))
		_bump(outer.size(), far)
		draw_polyline(spine, Color(c.r, c.g, c.b, 0.85 * g_fade), 2.2 * g_fade + 0.4, true)
		_bump(steps, far)
		if ghost == 0:
			draw_polyline(spine, Color(1.6, 1.6, 1.6, 0.7 * g_fade), 1.2 * fade + 0.3, true)
			_bump(steps, far)
