class_name BossSigilMark
extends Node2D
## THE ARTIST'S MARK — the drawn-on flourish that turns a giant stick figure into a
## thing that was DRAWN by somebody.
##
## `BossAdornment` (the Ashspire Guardian's molten core, ember eyes and lava
## cracks) is bespoke: every colour in it is hard-coded orange, because it is a
## stone-and-ember colossus and nothing else. The three artists added alongside it
## are ink, graphite and gold leaf, and a molten heart in any of them would be
## wrong. So the new bosses shed the adornment and wear this instead.
##
## What it draws is deliberately NOT a second creature-anatomy: it is a SIGIL — a
## slowly counter-rotating rune ring at chest height, two mark-eyes, and a set of
## unfinished construction hatches around the body, all in the boss's own colour.
## That ties every boss in the roster to the same visual grammar the player already
## reads off every spell in the game (MagicCircle's rings and glyph bands), so a
## boss looks like a thing that was summoned onto the page rather than a sprite.
##
## `set_intensity(0..1)` cranks ring speed, glow, eye heat and the hatch count
## together, so phases escalate the whole mark from one call — same contract as
## BossAdornment, which is why swapping one for the other needs no other change.

const TICKS: int = 12

var _height: float = 90.0
var _colour: Color = Color(1.0, 0.85, 0.4)
var _intensity: float = 0.35
var _t: float = 0.0


func configure(rig_height: float, colour: Color) -> void:
	_height = maxf(rig_height, 8.0)
	_colour = colour
	z_index = 40   # above the rig + its aura, same shelf BossAdornment claims


func set_colour(colour: Color) -> void:
	_colour = colour


func set_intensity(v: float) -> void:
	_intensity = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta * (1.1 + 2.2 * _intensity)
	queue_redraw()


func _draw() -> void:
	var c: Color = _colour
	var glow: float = 0.35 + 0.65 * _intensity
	var pulse: float = 0.88 + 0.12 * sin(_t * 2.4)
	var chest := Vector2(0.0, -_height * 0.20)
	var r: float = _height * 0.20 * pulse

	# The rune ring: two counter-rotating arcs plus radial ticks. Same skeleton as a
	# MagicCircle's rim, cut down to what stays legible at 640x360 on a phone.
	var ring := Color(c.r, c.g, c.b, 0.34 * glow)
	draw_arc(chest, r, 0.0, TAU, 30, ring, maxf(1.4, _height * 0.016), true)
	draw_arc(chest, r * 0.66, 0.0, TAU, 24, Color(c.r, c.g, c.b, 0.24 * glow), 1.4, true)
	var lit: int = 4 + int(round(8.0 * _intensity))
	for i: int in TICKS:
		var th: float = _t * 0.8 + TAU * float(i) / float(TICKS)
		var d: Vector2 = Vector2.from_angle(th)
		var on: bool = i < lit
		var a: float = (0.55 if on else 0.16) * glow
		draw_line(chest + d * r * 0.82, chest + d * r * 1.16, Color(c.r, c.g, c.b, a), 1.4, true)

	# The core the mark is drawn around — the only near-white thing on the body, so
	# it is the pixel the eye lands on when the boss is a silhouette in a busy room.
	draw_circle(chest, r * 0.24 * pulse, Color(c.r, c.g, c.b, 0.4 * glow), true, -1.0, true)
	draw_circle(chest, r * 0.11 * pulse, Color(1.5, 1.5, 1.5, 0.55 + 0.35 * _intensity), true, -1.0, true)

	# Two mark-eyes. Cheap, and the single strongest "this is looking at you" cue
	# available on a rig that has no face.
	var eye_y: float = -_height * 0.35
	var dx: float = _height * 0.055
	var er: float = _height * 0.019 * (0.8 + 0.7 * _intensity)
	var eye := Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, 0.65 + 0.35 * _intensity)
	draw_circle(Vector2(-dx, eye_y), er, eye, true, -1.0, true)
	draw_circle(Vector2(dx, eye_y), er, eye, true, -1.0, true)

	# UNFINISHED CONSTRUCTION LINES — the guide strokes an artist never rubbed out.
	# They are the one detail that says "drawn" rather than "modelled", and they
	# multiply with intensity, so a boss in its last phase is visibly still being
	# worked on while it is trying to kill you.
	var hatches: int = 3 + int(round(4.0 * _intensity))
	var ha := Color(c.r, c.g, c.b, 0.16 + 0.2 * _intensity)
	for i: int in hatches:
		var f: float = float(i) / float(hatches)
		var y: float = -_height * (0.06 + 0.62 * f)
		var w: float = _height * (0.20 + 0.13 * sin(_t * 0.9 + f * 5.0))
		draw_line(Vector2(-w, y), Vector2(w, y), ha, 1.0, true)
