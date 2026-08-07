class_name Telegraph
extends Node2D
## Pre-attack danger indicator — redesigned into distinct, animated "prep noters"
## that read as a signal FROM the caster instead of a flat red shape planted on
## the target. Each archetype gets its own sigil built from the arcane-circle
## vocabulary (rings, runic ticks, stars, apertures, charge lanes), tinted with a
## per-archetype accent, and a bright TETHER back to the caster (`source`) so you
## always see WHO is doing it and WHAT. Pairs with CasterSignal (the charge-glow
## on the body). Emits `fired` once when the windup elapses, draws a brief fade,
## then frees itself.
##
## Geometry (Shape CIRCLE/LINE) + timing are UNCHANGED so the "snapshot the spot,
## dodge the tell" grammar and the headless tests still hold; only the visuals +
## the `style`/`accent`/`source`/`aim_dir` reads are new. Primitive-drawn.

signal fired

const FADE_TIME: float = 0.15
## Crisp danger-red baseline (this-will-hurt). Per-archetype accents tint toward
## the enemy's element so casters/chargers/assassins read distinct at a glance.
const RING_COLOR: Color = Color(0.95, 0.16, 0.13, 0.9)

## Geometry, depended on by the archetype tests. CIRCLE = a zone/point sigil;
## LINE = a charge lane. (Kept exactly — do not rename.)
enum Shape { CIRCLE, LINE }
## Visual flavour, chosen per archetype. ZONE = ground danger ring (brute + the
## default for the plain tests); the rest are the distinct sigils.
## ⚠ APPEND ONLY — callers set these by name but `Enemy._emit_telegraph` passes them
## through a Dictionary as ints, so reordering would silently repaint every archetype.
## FIST / CRESCENT are the HERO's melee strikes: not a place on the floor, a thing
## coming out of the hand. See `Hero._publish_swing_tell`.
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

## Set by the caster before start(): the enemy this tell emanates from (drawn as
## a tether), the accent colour, the aim direction + reach for muzzle/dart lines.
var source: Node2D = null
var accent: Color = RING_COLOR
var style: Style = Style.ZONE
var aim_dir: Vector2 = Vector2.RIGHT
var reach: float = 120.0

## Every live telegraph joins this group so a dodging brain can find the set of
## things currently threatening it in one scan. See the perception block below.
const GROUP: StringName = &"telegraph"


func _ready() -> void:
	add_to_group(GROUP)


func start(radius: float, windup: float) -> void:
	_radius = radius
	_windup = maxf(windup, 0.001)
	_elapsed = 0.0
	_running = true
	_has_fired = false
	queue_redraw()


## Line telegraph: a charge lane from the origin along `angle`. Reuses ALL of
## start()'s timing / advance() / fired logic — only _draw branches on the shape.
func start_line(length: float, width: float, angle: float, windup: float) -> void:
	_shape = Shape.LINE
	_length = length
	_width = width
	_angle = angle
	if style == Style.ZONE:
		style = Style.LANE
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


# ---- perception ------------------------------------------------------------
# A telegraph IS the game's promise that something is about to happen at a place.
# Every field describing that promise was private and the node joined no group, so
# an AI could not see the one thing it is supposed to dodge. These expose the
# danger as world-space geometry plus a countdown — nothing a human player cannot
# already read off the screen, which keeps a dodging bot fair by construction
# rather than by convention.
#
# Unlike the spell spectacles (which park at the arena origin and draw in world
# coordinates), a Telegraph node sits AT the danger point and draws in local
# space, so global_position is genuinely meaningful here.

## World-space danger footprint. Circle: {shape, center, radius}.
## Line: {shape, from, to, width}.
func danger_shape() -> Dictionary:
	if _shape == Shape.LINE:
		return {
			"shape": "line",
			"from": global_position,
			"to": global_position + Vector2.from_angle(_angle) * _length,
			"width": _width,
		}
	return {"shape": "circle", "center": global_position, "radius": _radius}


## Seconds until this fires. <= 0.0 means it has already gone off.
func time_to_impact() -> float:
	return _windup - _elapsed


## The TOTAL warning this tell ever gave, as opposed to what is left of it.
##
## A dodging brain needs both. `time_to_impact` answers "how long have I got"; this
## answers "how much was I ever going to get", which is what a guard band has to be
## measured against — see `BotBrain._caps`. A hero melee swing tells for 0.077 s, and a
## class whose preferred guard lead is 0.37 s can never satisfy a band it cannot reach,
## on any frame, however well it reacts.
func windup() -> float:
	return _windup


## Still worth dodging: running and not yet fired.
func is_armed() -> bool:
	return _running and not _has_fired


func _draw() -> void:
	if _radius <= 0.0:
		return
	if _shape == Shape.LINE:
		# The hero's melee strikes are lanes too, but they are drawn as the STRIKE
		# rather than as a runic charge corridor — a punch is not a charger.
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
	# Every off-body tell draws a tether back to its caster so the read is always
	# "that enemy is doing this," never a free-floating marker.
	if style == Style.ZONE or style == Style.DART:
		_draw_tether(t)


# ------------------------------------------------------------------ shared bits
## A bright animated link from the caster to this danger spot: a faint beam with a
## pulse of energy travelling along it toward the target.
func _draw_tether(t: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	var from: Vector2 = to_local(source.global_position)
	var to: Vector2 = Vector2.ZERO
	if from.distance_to(to) < 4.0:
		return
	var c: Color = accent
	draw_line(from, to, Color(c.r, c.g, c.b, (0.12 + 0.22 * t)), 1.5)
	# Energy pulses sliding toward the target end.
	for i: int in 2:
		var f: float = fposmod(_elapsed * 2.2 + 0.5 * float(i), 1.0)
		var p: Vector2 = from.lerp(to, f)
		draw_circle(p, 2.4, Color(c.r, c.g, c.b, (0.7 * t) * (1.0 - f * 0.4)))


func _draw_fired_circle() -> void:
	# Accent-tinted muzzle/detonation flash (was a hard red disc — read as a stray
	# "red circle on the target"). A caster's flash is now its own hue.
	var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
	var c: Color = accent
	draw_circle(Vector2.ZERO, _radius, Color(c.r, c.g, c.b, 0.4 * fade))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.7 * fade), 3.0)


## Rotating runic ticks around a ring — the shared "arcane" flourish.
func _draw_runic_ticks(r: float, count: int, spin: float, col: Color) -> void:
	for i: int in count:
		var th: float = spin + TAU * float(i) / float(count)
		var dirv: Vector2 = Vector2.from_angle(th)
		draw_line(dirv * r * 0.82, dirv * r, col, 1.5)


# ----------------------------------------------------------------- ZONE (brute)
## The classic ground danger ring + inner charge fill (kept, so the default/test
## path is unchanged), now accent-tinted with the caster tether added on top.
func _draw_zone(t: float) -> void:
	var danger: Color = accent
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, Color(danger.r, danger.g, danger.b, 0.85), 2.0)
	var pulse: float = 1.0 + 0.05 * sin(_elapsed * 26.0) * t
	var inner_r: float = minf(_radius * t * pulse, _radius)
	var fill := Color(1.0, lerpf(0.5, 0.14, t), lerpf(0.28, 0.11, t), lerpf(0.16, 0.5, t))
	draw_circle(Vector2.ZERO, inner_r, fill)
	if inner_r > 2.0:
		draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, 40, Color(1.0, 0.32, 0.18, 0.25 + 0.65 * t), 2.0)


# --------------------------------------------------------------- MUZZLE (caster)
## A small face-on sigil at the staff tip + a brightening aim-tracer along the
## shot line — "it's charging a bolt, aimed there."
func _draw_muzzle(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	var spin: float = _elapsed * 2.2
	# Aim tracer: a faint full line + a bright leading edge that grows over the tell.
	var dir: Vector2 = aim_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var end: Vector2 = dir * reach
	draw_line(Vector2.ZERO, end, Color(c.r, c.g, c.b, 0.12 + 0.2 * t), 1.5)
	draw_line(Vector2.ZERO, dir * reach * (0.2 + 0.8 * t), Color(1.0, 1.0, 1.0, 0.25 + 0.45 * t), 1.5)
	# Reticle at the aim end.
	draw_arc(end, 5.0 + 2.0 * sin(_elapsed * 8.0), 0.0, TAU, 16, Color(c.r, c.g, c.b, 0.5 + 0.4 * t), 1.5)
	# Face-on muzzle sigil: two counter-rotating rings + runic ticks + core.
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.8), 2.0)
	_draw_runic_ticks(R * 0.92, 8, spin, Color(c.r, c.g, c.b, 0.5))
	draw_arc(Vector2.ZERO, R * 0.6, 0.0, TAU, 24, Color(c.r, c.g, c.b, 0.4), 1.5)
	var core: float = R * (0.18 + 0.22 * t)
	draw_circle(Vector2.ZERO, core, Color(c.r, c.g, c.b, 0.4))
	draw_circle(Vector2.ZERO, core * 0.5, Color(1.0, 1.0, 1.0, 0.5 + 0.4 * t))


# -------------------------------------------------------------- GATHER (summoner)
## A face-on summoning circle — a growing vortex that pulls energy inward, runic
## ticks + an inscribed triangle-star, brightening core. "It's calling something."
func _draw_gather(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	# Rings pulled inward toward the centre (the "gathering" read).
	for i: int in 3:
		var f: float = fposmod(-_elapsed * 0.6 + float(i) / 3.0, 1.0)
		draw_arc(Vector2.ZERO, R * (0.4 + f * 1.1), 0.0, TAU, 40, Color(c.r, c.g, c.b, (1.0 - f) * 0.3), 2.0)
	var spin: float = _elapsed * 1.6
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.85), 2.5)
	_draw_runic_ticks(R * 0.9, 10, spin, Color(c.r, c.g, c.b, 0.5))
	# Two opposed triangles (a hexagram-ish summoning star), counter-spinning.
	_draw_star(R * 0.62, 3, -spin * 0.8, Color(c.r, c.g, c.b, 0.7))
	_draw_star(R * 0.62, 3, -spin * 0.8 + PI, Color(c.r, c.g, c.b, 0.7))
	var core: float = R * (0.14 + 0.26 * t)
	draw_circle(Vector2.ZERO, core, Color(c.r, c.g, c.b, 0.35))
	draw_circle(Vector2.ZERO, core * 0.5, Color(1.0, 1.0, 1.0, 0.4 + 0.5 * t))


func _draw_star(r: float, points: int, offset: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in points:
		pts.append(Vector2.from_angle(offset - PI / 2.0 + TAU * float(i) / float(points)) * r)
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0)


# ---------------------------------------------------------------- BOMB (bomber)
## A big pulsing rune ring centred on the bomber with a COUNTDOWN arc that fills
## as the fuse burns + an intensifying red core. "This thing is about to blow."
func _draw_bomb(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	# Outer danger boundary (what's about to hurt).
	draw_arc(Vector2.ZERO, R, 0.0, TAU, 56, Color(c.r, c.g, c.b, 0.8), 2.5)
	_draw_runic_ticks(R * 0.94, 16, _elapsed * 0.8, Color(c.r, c.g, c.b, 0.4))
	# Countdown: an arc that sweeps all the way round as the fuse burns out.
	draw_arc(Vector2.ZERO, R * 0.8, -PI / 2.0, -PI / 2.0 + TAU * t, 48, Color(1.0, 0.5, 0.15, 0.85), 4.0)
	# Inner fill reddening + a fast pulse as it nears zero.
	var pulse: float = 1.0 + 0.08 * sin(_elapsed * (10.0 + 30.0 * t))
	var inner_r: float = R * (0.15 + 0.5 * t) * pulse
	draw_circle(Vector2.ZERO, inner_r, Color(1.0, lerpf(0.4, 0.1, t), 0.1, 0.2 + 0.4 * t))
	draw_circle(Vector2.ZERO, R * 0.1 * pulse, Color(1.0, 0.95, 0.8, 0.5 + 0.5 * t))


# -------------------------------------------------------------- DART (assassin)
## A crosshair reticle at the marked strike point + the tether does the rest
## (drawn by the caller) — "the silver one is about to dart HERE, from over there."
func _draw_dart(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	var spin: float = _elapsed * 4.0
	draw_arc(Vector2.ZERO, R, spin, spin + TAU * 0.9, 24, Color(c.r, c.g, c.b, 0.6 + 0.3 * t), 2.0)
	# Snapping crosshair ticks that close in as the (fast) tell fills.
	var gap: float = R * (1.4 - 0.5 * t)
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dirv: Vector2 = Vector2.from_angle(a + spin)
		draw_line(dirv * gap, dirv * (gap + R * 0.5), Color(c.r, c.g, c.b, 0.5 + 0.4 * t), 2.0)
	draw_circle(Vector2.ZERO, R * 0.12, Color(1.0, 1.0, 1.0, 0.4 + 0.5 * t))


# --------------------------------------------------------------- LANE (charger)
## A runic charge lane that ORIGINATES at the charger and fills with chevrons of
## energy rushing toward the target end, capped by an arrowhead — replaces the
## old flat red rectangle "line I don't know what it does."
func _draw_lane() -> void:
	var c: Color = accent
	if _has_fired:
		var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
		draw_rect(Rect2(0.0, -_width * 0.5, _length, _width), Color(1.0, 0.5, 0.2, 0.4 * fade), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	var hw: float = _width * 0.5
	# Faint full-lane boundary (where it WILL reach), then a filling body.
	draw_rect(Rect2(0.0, -hw, _length, _width), Color(c.r, c.g, c.b, 0.1 + 0.12 * t), false)
	var grow: float = _length * (0.15 + 0.85 * t)
	draw_rect(Rect2(0.0, -hw, grow, _width), Color(c.r, c.g, c.b, 0.14 + 0.28 * t), true)
	# Chevrons of energy rushing down the lane toward the target.
	var spacing: float = 26.0
	var scroll: float = fposmod(_elapsed * 160.0, spacing)
	var x: float = scroll
	while x < grow:
		draw_polyline(PackedVector2Array([
			Vector2(x - 8.0, -hw * 0.7), Vector2(x, 0.0), Vector2(x - 8.0, hw * 0.7),
		]), Color(1.0, 1.0, 1.0, 0.3 + 0.4 * t), 2.0)
		x += spacing
	# Bright core line + an arrowhead at the leading edge.
	draw_line(Vector2.ZERO, Vector2(grow, 0.0), Color(1.0, 1.0, 1.0, 0.35 + 0.4 * t), 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(grow + 10.0, 0.0), Vector2(grow - 4.0, -hw), Vector2(grow - 4.0, hw),
	]), Color(c.r, c.g, c.b, 0.6 + 0.35 * t))
	# Origin burst sigil at the charger.
	draw_arc(Vector2.ZERO, hw * 1.1, 0.0, TAU, 20, Color(c.r, c.g, c.b, 0.6 + 0.3 * t), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------- FIST / CRESCENT (hero melee)
## A SMALL GLOVE-SIZED FIST THAT TRAVELS OUT ALONG THE PUNCH.
##
## Maker: *"just show like a little fire fist or something coming out when I punch,
## small, the size of the glove, in the direction being punched, that can be dodged"*.
##
## It is drawn at where the strike HAS REACHED, not across the whole lane, so the
## thing on screen is the blow arriving rather than a corridor being reserved. The
## faint line behind it is the only "where this goes" hint, and it is deliberately
## thin — the fist is the read.
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
	# The travel hint: where it is going, at a weight that cannot be mistaken for
	# the strike itself.
	draw_line(Vector2.ZERO, dir * _length, Color(c.r, c.g, c.b, 0.10 * fade), 1.0, true)
	# A short motion streak BEHIND the fist — this is what makes it read as thrown
	# rather than as a dot sliding along a line.
	draw_line(at - dir * rr * 2.2, at, Color(c.r, c.g, c.b, 0.35 * fade), rr * 0.9, true)
	# THE GLOVE. Element-tinted core with a hot centre, so a fire fist is a fire fist
	# and an ice one is not the same picture in a different hue.
	draw_circle(at, rr * fade, Color(c.r, c.g, c.b, 0.85 * fade))
	draw_circle(at, rr * 0.55 * fade, Color(1.0, 1.0, 1.0, 0.7 * fade))
	# Knuckle flare on the leading edge.
	var perp: Vector2 = dir.orthogonal()
	for sgn: float in [-1.0, 1.0]:
		draw_line(at + perp * rr * 0.55 * sgn, at + dir * rr * 0.9 + perp * rr * 0.3 * sgn,
			Color(c.r, c.g, c.b, 0.6 * fade), 1.4, true)


## A THIN CURVE OF AIR OFF A BLADE — the same idea as the fist, cut differently.
## Sweeps out along the lane as an arc whose belly leads, so it reads as a slash
## leaving the sword rather than as a projectile.
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
	var half: float = maxf(_width * 0.9, 6.0) * (0.5 + 0.5 * t)
	draw_line(Vector2.ZERO, dir * _length, Color(c.r, c.g, c.b, 0.10 * fade), 1.0, true)
	# The arc, as a polyline bowed forward at its middle. `draw_arc` cannot do this —
	# a constant-width band reads as a ribbon, and the taper is what makes it a cut.
	var pts := PackedVector2Array()
	var steps: int = 9
	for i: int in steps + 1:
		var f: float = float(i) / float(steps)
		var off: float = (f - 0.5) * 2.0
		var bow: float = (1.0 - off * off) * half * 0.55
		pts.append(dir * (reach_now + bow) + perp * off * half)
	draw_polyline(pts, Color(c.r, c.g, c.b, 0.8 * fade), 2.6 * fade + 0.4, true)
	draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.55 * fade), 1.1 * fade + 0.2, true)

