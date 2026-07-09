class_name Telegraph
extends Node2D
## Pre-attack danger indicator: a static outer ring marks the blast zone while
## an inner charge circle blooms 0 -> radius over the windup, reddening and
## pulsing as it fills. Emits `fired` exactly once when the windup elapses,
## draws a brief fade, then frees itself. Reusable for big spells now and
## floor-guardian attacks later. Primitive-drawn placeholder; shader VFX later.

signal fired

const FADE_TIME: float = 0.15
const RING_COLOR: Color = Color(1.0, 0.35, 0.2, 0.55)

var _radius: float = 0.0
var _windup: float = 0.0
var _elapsed: float = 0.0
var _running: bool = false
var _has_fired: bool = false


func start(radius: float, windup: float) -> void:
	_radius = radius
	_windup = maxf(windup, 0.001)
	_elapsed = 0.0
	_running = true
	_has_fired = false
	queue_redraw()


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
	if _has_fired:
		# Brief afterglow while the BlastSpell's detonation takes over.
		var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		draw_circle(Vector2.ZERO, _radius, Color(1.0, 0.45, 0.2, 0.35 * fade))
		draw_arc(
			Vector2.ZERO, _radius, 0.0, TAU, 48,
			Color(1.0, 0.35, 0.2, 0.6 * fade), 3.0
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
		lerpf(0.72, 0.28, t),
		lerpf(0.4, 0.12, t),
		lerpf(0.14, 0.45, t)
	)
	draw_circle(Vector2.ZERO, inner_r, fill)
	if inner_r > 2.0:
		draw_arc(
			Vector2.ZERO, inner_r, 0.0, TAU, 40,
			Color(1.0, 0.5, 0.25, 0.25 + 0.65 * t), 2.0
		)
