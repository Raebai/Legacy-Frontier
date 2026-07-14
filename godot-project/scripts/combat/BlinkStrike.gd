class_name BlinkStrike
extends Node2D
## Shadowblade SIGNATURE — TELEPORT-STRIKE (SpellDef.Kind.BLINK_STRIKE). The hero
## dissolves into shadow and reappears at the marked point mid-slash; everything on
## the crossed line is cut (damage + Weaken + a shove along the dash). Nothing like
## a straight beam — a blink assassination. The HERO reposition is done in
## Hero._cast_signature (SpellCaster is static and can't move the caster); this node
## owns the streak/slash visuals + the line damage. Draws in world coordinates.

const HALF_WIDTH: float = 34.0     # forgiving cut corridor
const KNOCKBACK: float = 300.0
const LIFE: float = 0.34
const CORE: Color = Color(1.5, 1.3, 1.9)  # HDR violet-white (blooms)

var element_id: int = Elements.Element.SHADOW
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _color: Color = Color(0.6, 0.35, 0.95, 1.0)
var _elapsed: float = -1.0
var _seed: float = 0.0


## Cut the line from `from` to `to` (the pre/post teleport positions).
func strike(from: Vector2, to: Vector2, color: Color, damage: int = 50, _effect: String = "shadow") -> void:
	_from = from
	_to = to
	_color = color
	global_position = Vector2.ZERO
	var span: Vector2 = to - from
	var dir: Vector2 = span.normalized() if span != Vector2.ZERO else Vector2.RIGHT
	var length: float = span.length()
	var tint: Color = Color(color.r, color.g, color.b, 1.0)
	for e: Node in targets_on_line(from, dir, length, HALF_WIDTH, get_tree().get_nodes_in_group("enemy")):
		if e.has_method("take_damage"):
			e.take_damage(damage, tint)
		if e.has_method("apply_status"):
			e.apply_status(element_id)
		if e.has_method("apply_knockback"):
			e.apply_knockback(dir * KNOCKBACK)
	for prop: Node in targets_on_line(from, dir, length, HALF_WIDTH, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(damage)
	# Inky puff at the origin + a bright arrival flash at the destination.
	CombatVfx.spawn_burst(get_parent(), from, Color(0.35, 0.15, 0.5, 0.9), Color(0.1, 0.03, 0.2, 0.0),
		18, 0.4, 50.0, 150.0, 1.2, 3.0)
	CombatVfx.spawn_burst(get_parent(), to, CORE, Color(color.r, color.g, color.b, 0.0),
		20, 0.35, 70.0, 200.0, 0.7, 2.0, 0.0, 0.0, true)
	Juice.hit_stop(0.06)
	Juice.shake_camera(7.0)
	Sfx.play("blink", 0.0, 0.08)
	_elapsed = 0.0
	queue_redraw()


## Pure geometry (testable): nodes whose centre projects onto [0, length] along
## `dir` from `origin`, within `half_width` perpendicular.
static func targets_on_line(
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


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	_seed += delta * 60.0
	if _elapsed >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var intensity: float = clampf(1.0 - _elapsed / LIFE, 0.0, 1.0)
	# The dash streak (a fading after-image band from old -> new position).
	var perp: Vector2 = (_to - _from).orthogonal().normalized()
	var band: PackedVector2Array = PackedVector2Array([
		_from + perp * HALF_WIDTH * 0.5, _to + perp * HALF_WIDTH * 0.5,
		_to - perp * HALF_WIDTH * 0.5, _from - perp * HALF_WIDTH * 0.5,
	])
	draw_colored_polygon(band, Color(_color.r, _color.g, _color.b, 0.22 * intensity))
	draw_line(_from, _to, Color(CORE.r, CORE.g, CORE.b, 0.7 * intensity), 3.0, true)
	# A bright crescent slash at the destination, facing along the dash.
	var ang: float = (_to - _from).angle()
	draw_arc(_to, HALF_WIDTH * 0.9, ang - 1.1, ang + 1.1, 14, Color(CORE.r, CORE.g, CORE.b, 0.9 * intensity), 3.0, true)
	draw_arc(_to, HALF_WIDTH * 1.1, ang - 0.9, ang + 0.9, 14, Color(_color.r, _color.g, _color.b, 0.5 * intensity), 1.6, true)
