class_name BeamSpell
extends Node2D
## Signature spectacle #1 — the Frieren "Zoltraak" SIGIL BEAM. A huge magic
## circle materialises at the muzzle, gathers for a beat (a fair telegraph —
## dodge-the-tell), then FIRES a screen-crossing energy beam along the aim:
## white-hot core inside a fat element-coloured glow, damaging everything on the
## line, with heavy juice (hitstop, big shake, zoom-punch) and impact spray at
## the far end. Then the beam fades and the circle dissolves.
##
## Damage is a pure geometric line test (targets_on_beam) so it's headless-
## testable; the fire() entry drives the visual/juice timeline. Instantiate
## .new(), add as a child of the arena, then call fire().

const CHARGE_TIME: float = 0.34   # sigil gather (telegraph)
const FIRE_TIME: float = 0.26     # beam held at full intensity
const FADE_TIME: float = 0.22     # beam + circle dissolve
const DEFAULT_LENGTH: float = 1100.0
const DEFAULT_WIDTH: float = 30.0
const DEFAULT_DAMAGE: int = 46
const KNOCKBACK: float = 360.0
const CIRCLE_RADIUS_FACTOR: float = 2.4  # muzzle sigil radius = width * this

var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(0.95, 0.4, 0.85, 1.0)
var _length: float = DEFAULT_LENGTH
var _width: float = DEFAULT_WIDTH
var _damage: int = DEFAULT_DAMAGE
var _elapsed: float = -1.0     # < 0 = not fired yet
var _fired: bool = false       # damage/juice applied once at end of charge
var _circle: MagicCircle = null


## Public entry: charge at `origin`, then fire a beam of `length`/`width` along
## `dir`, dealing `damage`. Colour tints the whole spectacle (element).
func fire(
	origin: Vector2,
	dir: Vector2,
	color: Color,
	length: float = DEFAULT_LENGTH,
	width: float = DEFAULT_WIDTH,
	damage: int = DEFAULT_DAMAGE,
) -> void:
	_origin = origin
	_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_color = color
	_length = length
	_width = width
	_damage = damage
	global_position = Vector2.ZERO  # we draw in world space from _origin
	_elapsed = 0.0
	# Muzzle sigil materialises during the charge, oriented at the origin.
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.global_position = _origin
	_circle.appear(_color, _width * CIRCLE_RADIUS_FACTOR, CHARGE_TIME * 0.9)
	# Gathering spark at the muzzle — energy pulled in before the shot.
	CombatVfx.spawn_burst(
		self, _origin, Color(1, 1, 1, 0.9), Color(_color.r, _color.g, _color.b, 0.0),
		18, CHARGE_TIME, 30.0, 90.0, 1.0, 2.5
	)
	Sfx.play("cast", -2.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if not _fired and _elapsed >= CHARGE_TIME:
		_discharge()
	if _elapsed >= CHARGE_TIME + FIRE_TIME + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## The shot lands: apply beam damage once, spawn impact spray at the tip, and
## kick the whole screen. Dissolve the muzzle circle as the beam takes over.
func _discharge() -> void:
	_fired = true
	_apply_beam_damage()
	var tip: Vector2 = _beam_tip()
	CombatVfx.spawn_burst(
		self, tip, Color(1, 1, 1, 0.95), Color(_color.r, _color.g, _color.b, 0.0),
		46, 0.5, 120.0, 360.0, 1.5, 4.0
	)
	Juice.hit_stop(0.09)
	Juice.shake_camera(16.0)
	Juice.zoom_punch_camera(0.1, 0.24)
	Sfx.play("blast", 1.0, 0.08)
	if _circle != null and is_instance_valid(_circle):
		_circle.vanish(FIRE_TIME + FADE_TIME)


## Beam damage: every enemy/destructible whose centre lies on the beam segment
## (within half-width) takes damage; enemies are shoved along the beam.
func _apply_beam_damage() -> void:
	var half: float = _width * 0.5 + 8.0  # a little forgiveness on the width
	for enemy: Node in targets_on_beam(_origin, _dir, _length, half, get_tree().get_nodes_in_group("enemy")):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(_dir * KNOCKBACK)
	for prop: Node in targets_on_beam(_origin, _dir, _length, half, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)


## Pure geometry (testable): nodes whose centre projects onto the beam segment
## [0, length] along `dir` from `origin`, within `half_width` perpendicular.
static func targets_on_beam(
	origin: Vector2, dir: Vector2, length: float, half_width: float, nodes: Array
) -> Array:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var perp: Vector2 = d.orthogonal()
	var out: Array = []
	for n: Node in nodes:
		if not n is Node2D:
			continue
		var rel: Vector2 = (n as Node2D).global_position - origin
		var proj: float = rel.dot(d)
		if proj < 0.0 or proj > length:
			continue
		if absf(rel.dot(perp)) <= half_width:
			out.append(n)
	return out


func _beam_tip() -> Vector2:
	return _origin + _dir * _length


func _draw() -> void:
	if _elapsed < CHARGE_TIME:
		# During the charge, only a faint aiming line hints where the beam will go.
		if _elapsed >= 0.0:
			var tp: float = _elapsed / CHARGE_TIME
			draw_line(_origin, _origin + _dir * _length,
				Color(_color.r, _color.g, _color.b, 0.12 * tp), 2.0)
		return
	var since_fire: float = _elapsed - CHARGE_TIME
	# Intensity: a bright flash on the first frames, settling, then fading out.
	var intensity: float
	if since_fire < FIRE_TIME:
		intensity = 1.0 if since_fire > 0.04 else since_fire / 0.04  # snap up
		intensity = maxf(intensity, 1.0 - since_fire / (FIRE_TIME * 2.0))
	else:
		intensity = clampf(1.0 - (since_fire - FIRE_TIME) / FADE_TIME, 0.0, 1.0)
	if intensity <= 0.01:
		return
	var tip: Vector2 = _beam_tip()
	var flick: float = 0.9 + 0.1 * sin(_elapsed * 60.0)  # subtle energy flicker
	var w: float = _width * intensity * flick
	var c: Color = _color
	# Layered beam: wide soft glow -> mid body -> white-hot core.
	_draw_beam_band(_origin, tip, w * 1.8, Color(c.r, c.g, c.b, 0.28 * intensity))
	_draw_beam_band(_origin, tip, w * 1.0, Color(c.r, c.g, c.b, 0.7 * intensity))
	_draw_beam_band(_origin, tip, w * 0.4, Color(1, 1, 1, 0.95 * intensity))
	# Muzzle flash + impact flash.
	draw_circle(_origin, w * 1.4, Color(1, 1, 1, 0.5 * intensity))
	draw_circle(tip, w * 1.2, Color(c.r, c.g, c.b, 0.5 * intensity))
	draw_circle(tip, w * 0.6, Color(1, 1, 1, 0.6 * intensity))


## A filled beam band (rectangle) of thickness `thick` from `a` to `b`.
func _draw_beam_band(a: Vector2, b: Vector2, thick: float, col: Color) -> void:
	var d: Vector2 = (b - a)
	if d.length() < 0.001:
		return
	var perp: Vector2 = d.normalized().orthogonal() * (thick * 0.5)
	draw_colored_polygon(
		PackedVector2Array([a + perp, b + perp, b - perp, a - perp]), col
	)
