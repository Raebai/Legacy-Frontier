class_name RuneOrbs
extends Node2D
## Arcanist SIGNATURE — ARCANE MISSILES (SpellDef.Kind.MISSILES). A fan of small
## spinning rune-glyphs launches from the weapon tip and HOMES onto the nearest
## enemies, each popping in a precise arcane burst (Unstable). Precise control —
## not a beam, not a meteor. `count` orbs, `reach` unused, damage per orb. Draws in
## world coordinates; each orb is a bright core under a slowly spinning glyph.

const SPEED: float = 430.0
const TURN: float = 6.5         # homing steer rate (higher = sharper curve)
const HIT_RADIUS: float = 16.0
const MAX_LIFE: float = 1.7
const ORB_R: float = 6.0

var element_id: int = Elements.Element.ARCANE
var _color: Color = Color(0.85, 0.5, 1.0, 1.0)
var _dmg: int = 24
var _orbs: Array = []   # each: {pos:Vector2, vel:Vector2, alive:bool, spin:float}
var _elapsed: float = 0.0


func launch(origin: Vector2, aim: Vector2, color: Color, count: int = 5, damage: int = 24, _effect: String = "arcane") -> void:
	_color = color
	_dmg = damage
	var base: Vector2 = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	for i in count:
		var spread: float = (float(i) - float(count - 1) * 0.5) * 0.3
		var dir: Vector2 = base.rotated(spread)
		_orbs.append({"pos": origin, "vel": dir * SPEED, "alive": true, "spin": float(i) * 1.3})
	global_position = Vector2.ZERO
	Sfx.play("cast", 1.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	var any_alive: bool = false
	for orb in _orbs:
		if not orb["alive"]:
			continue
		any_alive = true
		var target: Node2D = _nearest_enemy_node(orb["pos"])
		if target != null:
			var want: Vector2 = (target.global_position - orb["pos"]).normalized() * SPEED
			orb["vel"] = (orb["vel"] as Vector2).lerp(want, clampf(TURN * delta, 0.0, 1.0))
		orb["pos"] = (orb["pos"] as Vector2) + (orb["vel"] as Vector2) * delta
		orb["spin"] = float(orb["spin"]) + delta * 8.0
		var e: Node = _enemy_within(orb["pos"], HIT_RADIUS)
		if e != null:
			_pop(orb, e)
	if _elapsed >= MAX_LIFE:
		for orb in _orbs:
			orb["alive"] = false
	if not any_alive:
		queue_free()
		return
	queue_redraw()


func _pop(orb: Dictionary, e: Node) -> void:
	orb["alive"] = false
	if e.has_method("take_damage"):
		e.take_damage(_dmg, Color(_color.r, _color.g, _color.b, 1.0))
	if e.has_method("apply_status"):
		e.apply_status(element_id)
	CombatVfx.spawn_burst(get_parent(), orb["pos"],
		Color(_color.r, _color.g, _color.b, 0.95), Color(_color.r, _color.g, _color.b, 0.0),
		10, 0.3, 50.0, 140.0, 0.6, 1.6, 0.0, 0.0, true)


func _nearest_enemy_node(from: Vector2) -> Node2D:
	var best: Node2D = null
	var bd: float = 1.0e9
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if e is Node2D and is_instance_valid(e):
			var d: float = from.distance_to((e as Node2D).global_position)
			if d < bd:
				bd = d
				best = e as Node2D
	return best


func _enemy_within(p: Vector2, r: float) -> Node:
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if e is Node2D and is_instance_valid(e) and p.distance_to((e as Node2D).global_position) <= r:
			return e
	return null


func _draw() -> void:
	for orb in _orbs:
		if not orb["alive"]:
			continue
		var p: Vector2 = orb["pos"]
		var spin: float = orb["spin"]
		draw_circle(p, ORB_R * 1.7, Color(_color.r, _color.g, _color.b, 0.28), true, -1.0, true)  # halo
		draw_circle(p, ORB_R * 0.6, Color(1.4, 1.1, 1.7, 0.95), true, -1.0, true)                 # HDR core
		# Two counter-spinning rune triangles (a tiny arcane glyph).
		var tri := PackedVector2Array()
		for k in 4:
			tri.append(p + Vector2.from_angle(spin + TAU * float(k) / 3.0) * ORB_R)
		draw_polyline(tri, Color(_color.r, _color.g, _color.b, 0.9), 1.5, true)
		var tri2 := PackedVector2Array()
		for k in 4:
			tri2.append(p + Vector2.from_angle(-spin * 1.3 + TAU * float(k) / 3.0) * ORB_R * 0.6)
		draw_polyline(tri2, Color(1.2, 0.9, 1.5, 0.7), 1.0, true)
