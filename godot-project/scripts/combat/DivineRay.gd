class_name DivineRay
extends Node2D
## Signature spectacle #2 — DIVINE RAY / smite. A holy magic circle opens in the
## sky above the target and a growing sigil marks the ground (a fair telegraph),
## then a towering PILLAR OF LIGHT crashes straight down: white-hot core in a
## radiant golden column, a blinding ground flash, an expanding holy ring, heavy
## juice. Damage is a radius query on the ground footprint (like the nova), so
## it's the vertical counterpart to the horizontal BeamSpell — very different
## silhouette, same spectacle language.
##
## Radius damage is a pure helper (targets_in_radius); strike() drives the
## timeline. Instantiate .new(), add to the arena, call strike().

const CHARGE_TIME: float = 0.42   # sky sigil + ground telegraph
const STRIKE_TIME: float = 0.20   # pillar at full brightness
const FADE_TIME: float = 0.30
const SKY_HEIGHT: float = 560.0   # how far above the target the sigil hangs
const DEFAULT_RADIUS: float = 90.0
const DEFAULT_DAMAGE: int = 52
const KNOCKBACK: float = 300.0

var _ground: Vector2 = Vector2.ZERO
var _sky: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.92, 0.55, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _elapsed: float = -1.0
var _struck: bool = false
var _circle: MagicCircle = null


## Public entry: mark `target` on the ground, hang a sigil `sky_height` above it,
## then smite. Colour tints the whole holy spectacle.
func strike(
	target: Vector2, color: Color = Color(1.0, 0.92, 0.55),
	radius: float = DEFAULT_RADIUS, damage: int = DEFAULT_DAMAGE,
) -> void:
	_ground = target
	_sky = target - Vector2(0.0, SKY_HEIGHT)
	_color = color
	_radius = radius
	_damage = damage
	_elapsed = 0.0
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.global_position = _sky
	_circle.appear(_color, _radius * 2.3, CHARGE_TIME * 0.85)
	# EDGE-ON along the vertical pillar: side-on, the sky sigil reads as a thin
	# horizontal gate the column of light drops through.
	_circle.set_orientation(true, Vector2.DOWN, 0.16)
	Sfx.play("cast", -4.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if not _struck and _elapsed >= CHARGE_TIME:
		_smite()
	if _elapsed >= CHARGE_TIME + STRIKE_TIME + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## The pillar lands: radius damage once, blinding impact spray + holy ring, and
## a heavy screen kick. The sky sigil dissolves as the light fades.
func _smite() -> void:
	_struck = true
	for enemy: Node in targets_in_radius(_ground, _radius, get_tree().get_nodes_in_group("enemy")):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - _ground).normalized()
			enemy.apply_knockback((away if away != Vector2.ZERO else Vector2.UP) * KNOCKBACK)
	for prop: Node in targets_in_radius(_ground, _radius, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	# Parented to the arena (get_parent()), not self: the burst outlives this
	# short-lived spectacle node so it fades naturally after we free.
	CombatVfx.spawn_burst(
		get_parent(), _ground, Color(1, 1, 1, 0.98), Color(_color.r, _color.g, _color.b, 0.0),
		52, 0.55, 90.0, 320.0, 1.5, 4.5
	)
	Juice.hit_stop(0.1)
	Juice.shake_camera(15.0)
	Juice.zoom_punch_camera(0.09, 0.24)
	Sfx.play("blast", 0.0, 0.08)
	if _circle != null and is_instance_valid(_circle):
		_circle.vanish(STRIKE_TIME + FADE_TIME)


## Pure geometry (testable): nodes within `radius` of `center`.
static func targets_in_radius(center: Vector2, radius: float, nodes: Array) -> Array:
	var out: Array = []
	for n: Node in nodes:
		if n is Node2D and center.distance_to((n as Node2D).global_position) <= radius:
			out.append(n)
	return out


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var c: Color = _color
	if _elapsed < CHARGE_TIME:
		# Telegraph: a growing bright ring on the ground where it will land.
		var tp: float = _elapsed / CHARGE_TIME
		var rr: float = _radius * (0.3 + 0.7 * tp)
		draw_arc(_ground, rr, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.5 * tp), 2.5)
		draw_circle(_ground, rr * 0.25 * tp, Color(c.r, c.g, c.b, 0.3 * tp))
		return
	var since: float = _elapsed - CHARGE_TIME
	var intensity: float
	if since < STRIKE_TIME:
		intensity = 1.0 if since > 0.04 else since / 0.04
	else:
		intensity = clampf(1.0 - (since - STRIKE_TIME) / FADE_TIME, 0.0, 1.0)
	if intensity <= 0.01:
		return
	var flick: float = 0.9 + 0.1 * sin(_elapsed * 55.0)
	var w: float = _radius * 0.9 * intensity * flick
	# Descending pillar: wide golden glow -> body -> white-hot core.
	_draw_column(w * 1.7, Color(c.r, c.g, c.b, 0.25 * intensity))
	_draw_column(w * 1.0, Color(c.r, c.g, c.b, 0.65 * intensity))
	_draw_column(w * 0.4, Color(1, 1, 1, 0.95 * intensity))
	# Ground impact: bright flash disc + an expanding holy ring.
	draw_circle(_ground, w * 1.5, Color(1, 1, 1, 0.5 * intensity))
	var ring_r: float = _radius * (1.0 + 1.4 * (1.0 - intensity))
	draw_arc(_ground, ring_r, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.6 * intensity), 4.0 * intensity)


## A vertical band of thickness `thick` from the sky sigil down to the ground.
func _draw_column(thick: float, col: Color) -> void:
	var half: Vector2 = Vector2(thick * 0.5, 0.0)
	draw_colored_polygon(
		PackedVector2Array([_sky - half, _sky + half, _ground + half, _ground - half]), col
	)
