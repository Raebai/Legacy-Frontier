class_name ElementFx
extends Node2D
## Per-element ORGANIC impact burst — the maker's "realistic + cool for ALL the
## elements ... organic not geometric" ask. One short-lived node per hit that draws
## the element's own SIGNATURE instead of a recolored dot-burst:
##   FIRE = flame plume (delegates to FlameBurst) · ICE = crystal shards + frost ring
##   LIGHTNING = branching arcs · SHADOW = inky smoke + tendrils · ARCANE = spinning
##   rune-sigil · EARTH = stone chunks + dust · HOLY = radiant rays + bloom · WIND =
##   wisp streaks. HDR cores (>1) bloom. Draw-time only (no autoloads); parent to arena.

const LIFE: float = 0.55

var _element: int = 0
var _size: float = 40.0
var _phase: float = 0.0
var _elapsed: float = 0.0
var _seeds: PackedFloat32Array = PackedFloat32Array()


## Spawn the organic burst for `element` (Elements.Element) at `world_pos`, ~`size`.
static func spawn(parent: Node, world_pos: Vector2, element: int, size: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if element == Elements.Element.FIRE:
		FlameBurst.spawn(parent, world_pos, size)  # fire = the flame plume
		return
	var fx := ElementFx.new()
	fx._element = element
	fx._size = size
	parent.add_child(fx)
	fx.global_position = world_pos
	fx.z_index = 40


func _ready() -> void:
	for i in 8:
		_seeds.append(randf() * TAU)


func _process(delta: float) -> void:
	_elapsed += delta
	_phase += delta
	if _elapsed >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = _elapsed / LIFE
	var s: float = clampf(t * 5.0, 0.0, 1.0) * (1.0 - smoothstep(0.35, 1.0, t))  # flare, then fade
	var r: float = _size * (0.6 + 0.6 * smoothstep(0.0, 0.4, t))                 # grow out
	if s <= 0.01:
		return
	match _element:
		Elements.Element.ICE: _ice(r, s)
		Elements.Element.LIGHTNING: _lightning(r, s)
		Elements.Element.SHADOW: _shadow(r, s)
		Elements.Element.ARCANE: _arcane(r, s)
		Elements.Element.EARTH: _earth(r, s)
		Elements.Element.HOLY: _holy(r, s)
		Elements.Element.WIND: _wind(r, s)
		_: _arcane(r, s)


## Crisp crystalline shards radiating out + a frost ring + a bright refractive core.
func _ice(r: float, s: float) -> void:
	var body := Color(0.5, 0.8, 1.0, 0.5 * s)
	var edge := Color(0.9, 0.98, 1.0, 0.95 * s)
	for i in 7:
		var dir: Vector2 = Vector2.from_angle(_seeds[i])
		var perp: Vector2 = dir.orthogonal()
		var length: float = r * (0.9 + 0.4 * sin(_seeds[i] * 3.0))
		var w: float = r * 0.12
		var pts := PackedVector2Array([
			perp * w, dir * length * 0.35 + perp * w * 0.6, dir * length,
			dir * length * 0.35 - perp * w * 0.6, -perp * w,
		])
		draw_colored_polygon(pts, body)
		draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 1.4, true)
	draw_arc(Vector2.ZERO, r * 0.5, 0.0, TAU, 20, Color(0.7, 0.92, 1.0, 0.4 * s), 1.5, true)
	draw_circle(Vector2.ZERO, r * 0.2, Color(1.3, 1.5, 1.7, 0.7 * s), true, -1.0, true)


## Branching white-hot arcs forking out in several directions.
func _lightning(r: float, s: float) -> void:
	var col := Color(1.0, 0.95, 0.5, 0.8 * s)
	var core := Color(1.7, 1.75, 1.9, 0.9 * s)
	for i in 6:
		var dir: Vector2 = Vector2.from_angle(_seeds[i])
		var perp: Vector2 = dir.orthogonal()
		var pts := PackedVector2Array()
		for k in 6:
			var tt: float = float(k) / 5.0
			var jag: float = sin(float(k) * 12.9 + _phase * 40.0 + _seeds[i]) * r * 0.18 * sin(tt * PI)
			pts.append(dir * r * tt + perp * jag)
		draw_polyline(pts, col, 2.4, true)
		draw_polyline(pts, core, 1.0, true)
	draw_circle(Vector2.ZERO, r * 0.24, core, true, -1.0, true)


## Inky violet smoke: dark expanding puffs + swirling tendril arcs.
func _shadow(r: float, s: float) -> void:
	for i in 6:
		var spread: float = 0.3 + 0.6 * fposmod(_seeds[i] + _phase * 0.5, 1.0)
		var d: Vector2 = Vector2.from_angle(_seeds[i] + _phase * 0.8) * r * spread
		draw_circle(d, r * 0.28, Color(0.18, 0.06, 0.3, 0.32 * s), true, -1.0, true)
	for i in 3:
		var a0: float = _phase * 1.2 + PI * float(i)
		draw_arc(Vector2.ZERO, r * (0.55 + 0.22 * float(i)), a0, a0 + PI * 0.9, 12, Color(0.45, 0.2, 0.62, 0.5 * s), 2.4, true)
	draw_circle(Vector2.ZERO, r * 0.3, Color(0.36, 0.12, 0.5, 0.5 * s), true, -1.0, true)


## A spinning rune-sigil: counter-rotating rings + a hexagram + a hot core.
func _arcane(r: float, s: float) -> void:
	var col := Color(0.95, 0.5, 1.0, 0.8 * s)
	draw_arc(Vector2.ZERO, r * 0.8, _phase * 2.0, _phase * 2.0 + TAU * 0.92, 28, col, 2.0, true)
	draw_arc(Vector2.ZERO, r * 0.55, -_phase * 2.5, -_phase * 2.5 + TAU * 0.85, 24, Color(col.r, col.g, col.b, 0.6 * s), 1.5, true)
	var tri := PackedVector2Array()
	for k in 4:
		tri.append(Vector2.from_angle(_phase * 1.5 + TAU * float(k) / 3.0) * r * 0.62)
	draw_polyline(tri, col, 1.6, true)
	var tri2 := PackedVector2Array()
	for k in 4:
		tri2.append(Vector2.from_angle(-_phase * 1.5 + PI + TAU * float(k) / 3.0) * r * 0.62)
	draw_polyline(tri2, col, 1.6, true)
	draw_circle(Vector2.ZERO, r * 0.18, Color(1.4, 1.0, 1.7, 0.9 * s), true, -1.0, true)


## Chunky flying stone + a dust ring (earth reads solid, not lit).
func _earth(r: float, s: float) -> void:
	var prog: float = _elapsed / LIFE
	for i in 6:
		var c: Vector2 = Vector2.from_angle(_seeds[i]) * r * (0.4 + 0.55 * prog) * (0.7 + 0.4 * sin(_seeds[i] * 2.0))
		var sz: float = r * 0.16
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-sz, -sz * 0.6), c + Vector2(sz, -sz * 0.4), c + Vector2(sz * 0.7, sz), c + Vector2(-sz * 0.8, sz * 0.7),
		]), Color(0.42, 0.32, 0.2, 0.9 * s))
	draw_arc(Vector2.ZERO, r * 0.7, 0.0, TAU, 20, Color(0.6, 0.46, 0.28, 0.3 * s), 3.0, true)


## Soft radiant light: bloomed core + light rays fanning out.
func _holy(r: float, s: float) -> void:
	var col := Color(1.5, 1.4, 0.8, 0.85 * s)
	for i in 12:
		var a: float = TAU * float(i) / 12.0 + _phase * 0.4
		draw_line(Vector2.from_angle(a) * r * 0.2, Vector2.from_angle(a) * r * (0.8 + 0.2 * sin(_phase * 3.0 + float(i))), col, 1.8, true)
	draw_circle(Vector2.ZERO, r * 0.5, Color(1.5, 1.45, 1.0, 0.32 * s), true, -1.0, true)
	draw_circle(Vector2.ZERO, r * 0.22, Color(1.7, 1.6, 1.2, 0.8 * s), true, -1.0, true)


## Wispy teal streaks swirling outward (spiral arcs).
func _wind(r: float, s: float) -> void:
	var col := Color(0.72, 1.0, 0.92, 0.7 * s)
	for i in 3:
		var pts := PackedVector2Array()
		for k in 10:
			var tt: float = float(k) / 9.0
			var a: float = _phase * 2.5 + PI * float(i) * 0.66 + tt * TAU * 0.7
			pts.append(Vector2.from_angle(a) * r * (0.2 + tt * 0.9))
		draw_polyline(pts, col, 1.8, true)
