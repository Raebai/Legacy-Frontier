class_name ChainBolt
extends Node2D
## CHAIN LIGHTNING (Stormcaller) / CHAIN-SMITE (Cleric, holy tint) — a jagged bolt
## that LEAPS enemy-to-enemy, up to N hops, shocking each with damage falloff.
## Nothing like a straight beam: it forks around the arena, hitting a whole chain.
## First target = nearest enemy in the aim direction; each hop = nearest unvisited
## within hop range. Instantiate .new(), add under the arena, call chain().
## Damage/target order is a pure static selector (build_chain) — headless-testable.

const FIRST_REACH: float = 560.0   # reach for the initial arc to target 1
const HOP_RANGE: float = 240.0     # leap distance between links
const FALLOFF: float = 0.82        # damage retained per hop
const LIFE: float = 0.34
const SEG: int = 6                 # jagged segments per link
const CORE_COLOR: Color = Color(1.7, 1.75, 1.9)  # HDR white-hot core (blooms)

var element_id: int = Elements.Element.LIGHTNING
var _color: Color = Color(1.0, 0.95, 0.4, 1.0)
var _points: PackedVector2Array = PackedVector2Array()
var _elapsed: float = -1.0
var _seed: float = 0.0


## Fire the chain from `origin` toward `aim`, hopping up to `max_hops` enemies.
func chain(
	origin: Vector2, aim: Vector2, color: Color,
	max_hops: int = 4, hop_range: float = HOP_RANGE, damage: int = 44, _effect: String = "lightning"
) -> void:
	_color = color
	var d: Vector2 = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	var links: Array = build_chain(origin, d, FIRST_REACH, hop_range, max_hops,
		get_tree().get_nodes_in_group("enemy"))
	_points = PackedVector2Array([origin])
	var dmg: float = float(damage)
	var tint: Color = Color(color.r, color.g, color.b, 1.0)
	for e: Node in links:
		if e is Node2D and is_instance_valid(e):
			_points.append((e as Node2D).global_position)  # capture BEFORE damage (may free)
		if e.has_method("take_damage"):
			e.take_damage(int(round(dmg)), tint)
		if e.has_method("apply_status"):
			e.apply_status(element_id, false)
		if e.has_method("apply_knockback"):
			e.apply_knockback(d * 110.0)
		dmg *= FALLOFF
	_elapsed = 0.0
	global_position = Vector2.ZERO  # drawn in world coords
	# Node-flash bursts at each strike point + juice.
	CombatVfx.spawn_burst(get_parent(), origin, CORE_COLOR, Color(color.r, color.g, color.b, 0.0),
		12, 0.3, 60.0, 160.0, 0.6, 1.6, 0.0, 0.0, true)
	for i in range(1, _points.size()):
		CombatVfx.spawn_burst(get_parent(), _points[i], CORE_COLOR, Color(color.r, color.g, color.b, 0.0),
			8, 0.3, 40.0, 130.0, 0.6, 1.5, 0.0, 0.0, true)
	Juice.shake_camera(6.0)
	Juice.zoom_pull_camera(0.12, 0.35, 0.12, 0.45)
	Sfx.play("zap", -1.0, 0.08)
	queue_redraw()


## Pure geometry (testable): the ordered chain of nodes struck. Target 1 = nearest
## node in the forward half-plane within `first_reach`; each subsequent = nearest
## unvisited within `hop_range` of the previous. Up to `max_hops` total.
static func build_chain(
	origin: Vector2, dir: Vector2, first_reach: float, hop_range: float, max_hops: int, nodes: Array
) -> Array:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var out: Array = []
	var first: Node2D = null
	var best: float = first_reach
	for n: Node in nodes:
		if not n is Node2D:
			continue
		var rel: Vector2 = (n as Node2D).global_position - origin
		if rel.dot(d) < 0.0:
			continue  # must be in the aim direction
		var dist: float = rel.length()
		if dist < best:
			best = dist
			first = n as Node2D
	if first == null:
		return out
	out.append(first)
	var cur: Vector2 = first.global_position
	while out.size() < max_hops:
		var nxt: Node2D = null
		var bestd: float = hop_range
		for n: Node in nodes:
			if n in out or not n is Node2D:
				continue
			var dd: float = cur.distance_to((n as Node2D).global_position)
			if dd < bestd:
				bestd = dd
				nxt = n as Node2D
		if nxt == null:
			break
		out.append(nxt)
		cur = nxt.global_position
	return out


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	_seed += delta * 90.0
	if _elapsed >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _elapsed < 0.0 or _points.size() < 2:
		return
	var intensity: float = clampf(1.0 - _elapsed / LIFE, 0.0, 1.0)
	for i in range(_points.size() - 1):
		_draw_link(_points[i], _points[i + 1], intensity)
	# Bright node flashes at each strike point.
	for i in range(_points.size()):
		draw_circle(_points[i], 6.0, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.6 * intensity), true, -1.0, true)


## One jagged link between two strike points (tapered jitter so ends connect).
func _draw_link(a: Vector2, b: Vector2, intensity: float) -> void:
	var perp: Vector2 = (b - a).orthogonal().normalized()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in SEG + 1:
		var t: float = float(i) / float(SEG)
		var base: Vector2 = a.lerp(b, t)
		var jit: float = sin(float(i) * 12.9 + _seed) * sin(t * PI) * 14.0
		pts.append(base + perp * jit)
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.25 * intensity), 6.0, true)
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.7 * intensity), 2.4, true)
	draw_polyline(pts, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.95 * intensity), 1.0, true)
