class_name StarConvergence
extends Node2D
## Signature spectacle #4 — HEAVEN'S VERDICT. The sky closes in a RING of radiant
## lances around the marked point; they rush INWARD and slam together as one
## cataclysmic holy nova. Distinct from Judgment (a vertical single pillar) and
## the beams (a line): this is a radial CONVERGENCE + one big point detonation —
## the longest telegraph in the kit (over a second to dodge) and the biggest
## single hit as the payoff. Radius damage on the nova footprint
## (targets_in_radius, pure/testable); converge() drives the timeline.
##
## `effect` picks the elemental character (holy by default). Procedural, no assets.

const RING_RADIUS: float = 480.0    # how far out the lances start
const LANCE_COUNT: int = 8
const SKY_HEIGHT: float = 520.0
const CHARGE_TIME: float = 0.55     # sky sigil grows + ground danger ring
const CONVERGE_TIME: float = 0.55   # lances visibly streak inward
const IMPACT_HOLD: float = 0.12
const FADE_TIME: float = 0.45
const DEFAULT_RADIUS: float = 160.0
const DEFAULT_DAMAGE: int = 130
const KNOCKBACK: float = 380.0

var _ground: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.86, 0.4, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "holy"
var _elapsed: float = -1.0
var _detonated: bool = false
var _circle: MagicCircle = null
## Elemental ailment (Elements.Element) applied to enemies the nova hits. -1=none.
var element_id: int = -1


## Public entry: converge on `target`, dealing `damage` over `radius`.
func converge(
	target: Vector2, color: Color = Color(1.0, 0.86, 0.4),
	radius: float = DEFAULT_RADIUS, damage: int = DEFAULT_DAMAGE,
	effect: String = "holy",
) -> void:
	_ground = target
	_color = color
	_radius = radius
	_damage = damage
	_effect = effect
	_elapsed = 0.0
	# Face-on sky sigil (an AREA/portal spell, per MagicCircle's guidance) — the
	# seal the lances pour out of. Default (face-on) orientation, like the meteor.
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.global_position = _ground - Vector2(0.0, SKY_HEIGHT)
	_circle.appear(_color, _radius * 2.2, CHARGE_TIME * 0.85)
	Sfx.play("cast", -2.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if not _detonated and _elapsed >= CHARGE_TIME + CONVERGE_TIME:
		_detonate()
	if _circle != null and is_instance_valid(_circle) and _elapsed >= CHARGE_TIME + CONVERGE_TIME:
		_circle.vanish(IMPACT_HOLD + FADE_TIME)
	if _elapsed >= CHARGE_TIME + CONVERGE_TIME + IMPACT_HOLD + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## The lances slam together: radius damage once at the point + the biggest juice
## in the kit (this is the finisher).
func _detonate() -> void:
	_detonated = true
	var at: Vector2 = _ground
	for enemy: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group("enemy")):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			enemy.apply_knockback((away if away != Vector2.ZERO else Vector2.UP) * KNOCKBACK)
	for prop: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	_impact_burst(at)
	Juice.hit_stop(0.14)
	Juice.shake_camera(24.0)
	Juice.zoom_punch_camera(0.14, 0.3)
	Sfx.play("blast", 2.0, 0.1)


## Big radiant nova spray at the point (holy character; scaled up for the finisher).
func _impact_burst(at: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(1.0, 0.99, 0.9, 0.98), fade,
		64, 0.7, 120.0, 380.0, 1.5, 4.0, 1.0, 2.5, true
	)


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
		_draw_charge(c)
		return
	if _elapsed < CHARGE_TIME + CONVERGE_TIME:
		_draw_converge(c)
		return
	_draw_impact(c)


## Charge tell: a growing danger ring at the point + the ring of lance markers
## poised to close in.
func _draw_charge(c: Color) -> void:
	var tp: float = _elapsed / CHARGE_TIME
	draw_arc(_ground, _radius * (0.35 + 0.55 * tp), 0.0, TAU, 44, Color(c.r, c.g, c.b, 0.45 * tp), 2.5, true)
	for i: int in LANCE_COUNT:
		var ang: float = TAU * float(i) / float(LANCE_COUNT)
		var pos: Vector2 = _ground + Vector2.from_angle(ang) * RING_RADIUS
		var inward: Vector2 = (_ground - pos).normalized()
		draw_line(pos, pos + inward * 26.0, Color(c.r, c.g, c.b, 0.35 + 0.4 * tp), 2.0, true)
		draw_circle(pos, 3.0 + 2.0 * tp, Color(1.0, 1.0, 0.95, 0.4 + 0.4 * tp), true, -1.0, true)


## Convergence: the lances streak inward from the ring toward the point.
func _draw_converge(c: Color) -> void:
	var f: float = clampf((_elapsed - CHARGE_TIME) / CONVERGE_TIME, 0.0, 1.0)
	var eased: float = f * f  # accelerate inward
	for i: int in LANCE_COUNT:
		var ang: float = TAU * float(i) / float(LANCE_COUNT)
		var start: Vector2 = _ground + Vector2.from_angle(ang) * RING_RADIUS
		var head: Vector2 = start.lerp(_ground, eased)
		var tail: Vector2 = start.lerp(_ground, maxf(eased - 0.28, 0.0))
		draw_line(tail, head, Color(c.r, c.g, c.b, 0.5), 9.0, true)                  # wide soft lance
		draw_line(tail, head, Color(1.7, 1.6, 1.35, 0.85), 3.5, true)              # HDR bright core
		draw_circle(head, 6.0, Color(1.75, 1.75, 1.6, 0.9), true, -1.0, true)                    # HDR radiant head
	# The point brightens as they close in.
	draw_circle(_ground, _radius * 0.12 * eased, Color(c.r, c.g, c.b, 0.5 * eased), true, -1.0, true)


## Impact: the nova flash + two expanding shockwave rings fading out.
func _draw_impact(c: Color) -> void:
	var local: float = _elapsed - CHARGE_TIME - CONVERGE_TIME
	var intensity: float
	if local < IMPACT_HOLD:
		intensity = 1.0 if local > 0.04 else local / 0.04
	else:
		intensity = clampf(1.0 - (local - IMPACT_HOLD) / FADE_TIME, 0.0, 1.0)
	if intensity <= 0.01:
		return
	var t: float = clampf(local / (IMPACT_HOLD + FADE_TIME), 0.0, 1.0)
	draw_circle(_ground, _radius * (0.5 + 0.5 * intensity), Color(1.7, 1.65, 1.5, 0.5 * intensity), true, -1.0, true)
	draw_circle(_ground, _radius * 0.3 * intensity, Color(1.9, 1.9, 1.7, 0.8 * intensity), true, -1.0, true)
	for k: int in 2:
		var rr: float = _radius * (0.6 + (0.9 + 0.4 * float(k)) * t)
		draw_arc(_ground, rr, 0.0, TAU, 56, Color(c.r, c.g, c.b, (0.7 - 0.25 * float(k)) * intensity), lerpf(6.0, 1.0, t), true)
