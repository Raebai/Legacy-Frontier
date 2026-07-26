class_name DrainTether
extends Node2D
## Warlock — LIFE-DRAIN TETHER (SpellDef.Kind.TETHER). A writhing tendril WHIPS out
## along the aim, latches onto the first thing it physically crosses, and DRAINS it
## over a short channel: the victim bleeds shadow damage each tick while the caster
## is HEALED. Organic wavy tether — unmistakably not a clean beam. Draws in world
## coordinates.
##
## NO AUTO-LOCK (magic-overhaul rule 1): the tendril latches only onto a target
## inside a narrow CORRIDOR around the aim ray. Miss and it flails into empty air.
## And the latch is not a death sentence — the victim SNAPS the tether by opening
## more than BREAK_RANGE from where the caster stood (rule 2, counterplay).

const DURATION: float = 1.1
const TICK: float = 0.2
const RANGE: float = 440.0
const CORRIDOR: float = 42.0     # half-width of the aim corridor the whip covers
const BREAK_RANGE: float = 520.0 # run past this from the anchor and the tether snaps
const HEAL_PER_TICK: int = 5

var element_id: int = Elements.Element.SHADOW
var _origin: Vector2 = Vector2.ZERO
var _target: Node2D = null
var _color: Color = Color(0.55, 0.2, 0.6, 1.0)
var _tick_dmg: int = 10
var _elapsed: float = -1.0
var _tick_t: float = 0.0
var _aim: Vector2 = Vector2.RIGHT
var _snapped: float = 0.0   # >0 while the recoil of a broken/whiffed tether draws


func tether(origin: Vector2, aim: Vector2, color: Color, damage: int = 10, _effect: String = "shadow") -> void:
	_origin = origin
	_color = color
	_tick_dmg = damage
	var d: Vector2 = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	_aim = d
	_target = latch_target(origin, d, RANGE, CORRIDOR, get_tree().get_nodes_in_group("enemy"))
	global_position = Vector2.ZERO
	_elapsed = 0.0
	Sfx.play("cast", -2.0, 0.1)
	if _target == null:
		_snap()  # whiffed the aim corridor — the whip flails and recoils
		return
	_drain()  # bite the frame it lands
	queue_redraw()


## Pure geometry (testable): the first node the whip crosses — inside `corridor`
## perpendicular of the aim ray and within `reach` along it. Null if the aim missed;
## the tendril never bends to find a target.
static func latch_target(origin: Vector2, dir: Vector2, reach: float, corridor: float, nodes: Array) -> Node2D:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var perp: Vector2 = d.orthogonal()
	var best: Node2D = null
	var nearest: float = reach
	for e: Node in nodes:
		if not e is Node2D or not is_instance_valid(e):
			continue
		var rel: Vector2 = (e as Node2D).global_position - origin
		var along: float = rel.dot(d)
		if along < 0.0 or along > reach:
			continue
		if absf(rel.dot(perp)) > corridor:
			continue  # off the aim line — no auto-lock
		if along < nearest:
			nearest = along
			best = e as Node2D
	return best


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _snapped > 0.0:
		_snapped -= delta
		if _snapped <= 0.0:
			queue_free()
			return
		queue_redraw()
		return
	# The victim's counterplay: open enough distance and the tendril tears loose.
	if _target != null and is_instance_valid(_target) \
			and _origin.distance_to(_target.global_position) > BREAK_RANGE:
		_snap()
		return
	if _elapsed < DURATION and _target != null and is_instance_valid(_target):
		_tick_t -= delta
		if _tick_t <= 0.0:
			_tick_t = TICK
			_drain()
	if _elapsed >= DURATION or _target == null or not is_instance_valid(_target):
		queue_free()
		return
	queue_redraw()


## The tether tears loose (victim escaped, or the cast whiffed): a short recoil
## flick back toward the caster so the break READS instead of just vanishing.
func _snap() -> void:
	_snapped = 0.18
	_target = null
	CombatVfx.spawn_burst(get_parent(), _origin + _aim * 90.0,
		Color(_color.r, _color.g, _color.b, 0.9), Color(_color.r, _color.g, _color.b, 0.0),
		8, 0.25, 40.0, 120.0, 0.5, 1.4, 0.0, 0.0, true)
	Sfx.play("cast", -6.0, 0.12)
	queue_redraw()


func _drain() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _target.has_method("take_damage"):
		_target.take_damage(_tick_dmg, Color(_color.r, _color.g, _color.b, 1.0))
	if _target.has_method("apply_status"):
		_target.apply_status(element_id)
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p.has_method("heal"):
			p.call("heal", HEAL_PER_TICK)


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _snapped > 0.0:
		_draw_recoil()
		return
	if _target == null or not is_instance_valid(_target):
		return
	var a: Vector2 = _origin
	var b: Vector2 = _target.global_position
	var perp: Vector2 = (b - a).orthogonal().normalized()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 11:
		var t: float = float(i) / 10.0
		var base: Vector2 = a.lerp(b, t)
		var wob: float = sin(t * 10.0 + _elapsed * 18.0) * 8.0 * sin(t * PI)
		pts.append(base + perp * wob)
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.7), 3.0, true)
	draw_polyline(pts, Color(0.9, 0.6, 1.0, 0.5), 1.2, true)
	# A mote flowing FROM the target back to the caster (the life being drained).
	var flow: float = fposmod(_elapsed * 2.2, 1.0)
	draw_circle(b.lerp(a, flow), 3.0, Color(0.85, 0.45, 1.0, 0.85), true, -1.0, true)
	draw_circle(b, 8.0, Color(_color.r, _color.g, _color.b, 0.4), true, -1.0, true)


## The torn tether whipping back: a short, fast-shrinking wavy stub along the aim.
func _draw_recoil() -> void:
	var t: float = clampf(_snapped / 0.18, 0.0, 1.0)
	var reach: float = 120.0 * t
	var perp: Vector2 = _aim.orthogonal()
	var pts := PackedVector2Array()
	for i in 8:
		var f: float = float(i) / 7.0
		var wob: float = sin(f * 14.0 + _elapsed * 30.0) * 9.0 * sin(f * PI) * t
		pts.append(_origin + _aim * reach * f + perp * wob)
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.6 * t), 3.0, true)
	draw_polyline(pts, Color(0.9, 0.6, 1.0, 0.4 * t), 1.2, true)
