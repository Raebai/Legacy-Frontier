class_name CasterSignal
extends Node2D
## A charge-up glow that rides ON the caster's body while it winds up an attack —
## the "signal FROM the caster" the maker asked for: energy gathers, motes spiral
## inward, a core brightens as the tell fills, so your eye goes to the DANGEROUS
## enemy, not to an abstract shape planted on the ground. Purely cosmetic; grows
## over the windup, briefly blooms, and self-frees. Reused by every archetype
## (accent-tinted), spawned as a child of the Enemy so it follows a shoved body.
## Pure Node2D draw — no scene file, headless-safe (only _process/_draw).

const FADE: float = 0.12
const MOTES: int = 7

var _color: Color = Color(1.0, 0.3, 0.2, 1.0)
var _windup: float = 0.6
var _elapsed: float = 0.0
var _running: bool = false
var _base_r: float = 13.0


## Begin the gather. `base_radius` scales the whole effect (small for a caster's
## bolt, bigger for a bomber's fuse). Auto-frees after windup + FADE.
func charge(color: Color, windup: float, base_radius: float = 13.0) -> void:
	_color = color
	_windup = maxf(windup, 0.05)
	_base_r = base_radius
	_elapsed = 0.0
	_running = true
	queue_redraw()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	if _elapsed >= _windup + FADE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if not _running:
		return
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	var fade: float = 1.0
	if _elapsed > _windup:
		fade = clampf(1.0 - (_elapsed - _windup) / FADE, 0.0, 1.0)
	var c: Color = _color
	var pulse: float = 0.85 + 0.15 * sin(_elapsed * 24.0)

	# Soft gathering glow, growing with the charge.
	var glow_r: float = _base_r * (0.55 + 0.85 * t) * pulse
	draw_circle(Vector2.ZERO, glow_r, Color(c.r, c.g, c.b, 0.13 * fade))
	draw_circle(Vector2.ZERO, glow_r * 0.6, Color(c.r, c.g, c.b, 0.16 * fade))

	# A ring that contracts inward — energy being pulled into the body.
	var ring_r: float = _base_r * (1.5 - 0.85 * t)
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.45 * t * fade), 2.0)

	# Motes spiralling in toward the core.
	for i: int in MOTES:
		var ang: float = _elapsed * 3.2 + TAU * float(i) / float(MOTES)
		var mr: float = maxf(_base_r * (1.55 - 1.15 * t) + 2.0 * sin(_elapsed * 6.0 + float(i)), 1.0)
		var pos: Vector2 = Vector2.from_angle(ang) * mr
		var a: float = clampf(0.35 + 0.5 * t, 0.0, 1.0) * fade
		draw_circle(pos, 2.0, Color(c.r, c.g, c.b, a * 0.5))
		draw_circle(pos, 1.1, Color(1.0, 1.0, 1.0, a))

	# Hot core, brightening as the tell fills.
	var core: float = _base_r * (0.1 + 0.26 * t) * pulse
	draw_circle(Vector2.ZERO, core, Color(c.r, c.g, c.b, 0.5 * fade))
	draw_circle(Vector2.ZERO, core * 0.55, Color(1.0, 1.0, 1.0, (0.45 + 0.45 * t) * fade))
