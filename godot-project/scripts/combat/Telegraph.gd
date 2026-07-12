class_name Telegraph
extends Node2D
## Pre-attack danger indicator: a static outer ring marks the blast zone while
## an inner charge circle blooms 0 -> radius over the windup, reddening and
## pulsing as it fills. Emits `fired` exactly once when the windup elapses,
## draws a brief fade, then frees itself. Reusable for big spells now and
## floor-guardian attacks later. Primitive-drawn placeholder; shader VFX later.

signal fired

const FADE_TIME: float = 0.15
## Crisp, saturated danger-red (was a muddy orange at 0.55 alpha that blended to
## an ugly "pink" over the sky). Now it reads clearly as an enemy attack tell.
const RING_COLOR: Color = Color(0.95, 0.16, 0.13, 0.85)

enum Shape { CIRCLE, LINE }

var _radius: float = 0.0
var _windup: float = 0.0
var _elapsed: float = 0.0
var _running: bool = false
var _has_fired: bool = false
var _shape: Shape = Shape.CIRCLE
var _length: float = 0.0
var _width: float = 0.0
var _angle: float = 0.0


func start(radius: float, windup: float) -> void:
	_radius = radius
	_windup = maxf(windup, 0.001)
	_elapsed = 0.0
	_running = true
	_has_fired = false
	queue_redraw()


## Line telegraph: a growing rectangle from the origin along `angle`, marking a
## charge lane. Reuses ALL of start()'s timing / advance() / fired logic — only
## _draw branches on the shape. _radius is set to width so the _draw guard passes.
func start_line(length: float, width: float, angle: float, windup: float) -> void:
	_shape = Shape.LINE
	_length = length
	_width = width
	_angle = angle
	start(maxf(width, 1.0), windup)


func _process(delta: float) -> void:
	advance(delta)


## Deterministic time-step so headless tests can drive the bloom frame-free.
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
	if _shape == Shape.LINE:
		_draw_line_shape()
		return
	if _has_fired:
		# Brief afterglow while the BlastSpell's detonation takes over.
		var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		draw_circle(Vector2.ZERO, _radius, Color(1.0, 0.28, 0.16, 0.4 * fade))
		draw_arc(
			Vector2.ZERO, _radius, 0.0, TAU, 48,
			Color(1.0, 0.18, 0.13, 0.7 * fade), 3.0
		)
		return
	# Static outer danger ring — the boundary of what is about to hurt.
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, RING_COLOR, 2.0)
	# Inner charge: grows with the windup, reddens and pulses as it fills.
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	var pulse: float = 1.0 + 0.05 * sin(_elapsed * 26.0) * t
	var inner_r: float = minf(_radius * t * pulse, _radius)
	var fill := Color(
		1.0,
		lerpf(0.5, 0.14, t),
		lerpf(0.28, 0.11, t),
		lerpf(0.16, 0.5, t)
	)
	draw_circle(Vector2.ZERO, inner_r, fill)
	if inner_r > 2.0:
		draw_arc(
			Vector2.ZERO, inner_r, 0.0, TAU, 40,
			Color(1.0, 0.32, 0.18, 0.25 + 0.65 * t), 2.0
		)


## Charge-lane rectangle: grows from a stub to full length over the windup,
## reddening as it fills, then a brief afterglow post-fire.
func _draw_line_shape() -> void:
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	if _has_fired:
		var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		draw_rect(Rect2(0.0, -_width * 0.5, _length, _width), Color(1.0, 0.45, 0.2, 0.4 * fade), true)
	else:
		var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
		var grow: float = _length * (0.3 + 0.7 * t)
		var col := Color(1.0, lerpf(0.6, 0.25, t), lerpf(0.35, 0.12, t), 0.2 + 0.45 * t)
		draw_rect(Rect2(0.0, -_width * 0.5, grow, _width), col, true)
		draw_line(Vector2.ZERO, Vector2(grow, 0.0), Color(1.0, 0.5, 0.25, 0.4 + 0.4 * t), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
