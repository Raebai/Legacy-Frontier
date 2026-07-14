class_name ZoneSpell
extends Node2D
## A persistent GROUND FIELD (SpellDef.Kind.ZONE) — the shared spectacle behind
## Warlock's VOID ZONE (shadow), Cryomancer's BLIZZARD (frost) and (optionally)
## Cleric's CONSECRATED GROUND (holy — heals allies standing in it). Aim-placed;
## every tick it damages + applies the element ailment to enemies inside, for its
## lifetime, then fades. A flat ground sigil + an effect-flavoured fill. NOT a
## recolored beam/meteor — a zoning tool. Draws in world coordinates.

const TICK: float = 0.4
const FADE: float = 0.6
const HEAL_PER_TICK: int = 6

var element_id: int = Elements.Element.SHADOW
var _at: Vector2 = Vector2.ZERO
var _color: Color = Color(0.6, 0.3, 0.9)
var _radius: float = 120.0
var _tick_dmg: int = 10
var _effect: String = "shadow"
var _life: float = 4.5
var _elapsed: float = 0.0
var _tick_t: float = 0.0
var _seed: PackedFloat32Array = PackedFloat32Array()


func open(
	at: Vector2, color: Color, radius: float, tick_damage: int,
	effect: String = "shadow", lifetime: float = 4.5
) -> void:
	_at = at
	_color = color
	_radius = radius
	_tick_dmg = tick_damage
	_effect = effect
	_life = lifetime
	global_position = Vector2.ZERO
	var hit: Dictionary = _floor_below(at, 240.0)
	if not hit.is_empty():
		_at = hit["position"]
	for i in 10:
		_seed.append(randf() * TAU)
	Juice.shake_camera(4.0)
	Sfx.play("cast", -3.0, 0.12)
	_tick()  # immediate first tick so it bites the frame it lands
	queue_redraw()


func _floor_below(from: Vector2, max_dist: float) -> Dictionary:
	var world: World2D = get_world_2d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, max_dist), 1)
	return world.direct_space_state.intersect_ray(query)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < _life:
		_tick_t -= delta
		if _tick_t <= 0.0:
			_tick_t = TICK
			_tick()
	if _elapsed >= _life + FADE:
		queue_free()
		return
	queue_redraw()


## Damage + ail every enemy inside; holy zones also heal players inside.
func _tick() -> void:
	var tint: Color = Color(_color.r, _color.g, _color.b, 1.0)
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not e is Node2D or not is_instance_valid(e):
			continue
		if _at.distance_to((e as Node2D).global_position) > _radius:
			continue
		if e.has_method("take_damage"):
			e.take_damage(_tick_dmg, tint)
		if e.has_method("apply_status"):
			e.apply_status(element_id)
	if _effect == "holy":
		for p: Node in get_tree().get_nodes_in_group("player"):
			if p is Node2D and _at.distance_to((p as Node2D).global_position) <= _radius and p.has_method("heal"):
				p.call("heal", HEAL_PER_TICK)
	# A soft upward pulse of motes at the tick so the field reads as "active".
	CombatVfx.spawn_burst(get_parent(), _at + Vector2(0.0, 4.0),
		Color(_color.r, _color.g, _color.b, 0.7), Color(_color.r, _color.g, _color.b, 0.0),
		8, 0.5, 30.0, 70.0, 0.6, 1.6, 0.0, 0.0, true)


func _draw() -> void:
	var alpha: float = 1.0
	if _elapsed >= _life:
		alpha = clampf(1.0 - (_elapsed - _life) / FADE, 0.0, 1.0)
	var grow: float = smoothstep(0.0, 0.25, _elapsed)  # ease the footprint open
	var r: float = _radius * grow
	if r <= 1.0:
		return
	# Flat ground ellipse (squashed y) — a field on the floor, not a face-on disc.
	var squash: float = 0.42
	draw_set_transform(_at, 0.0, Vector2(1.0, squash))
	# Soft fill + rotating ring.
	draw_circle(Vector2.ZERO, r, Color(_color.r, _color.g, _color.b, 0.14 * alpha), true, -1.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(_color.r, _color.g, _color.b, 0.6 * alpha), 2.2, true)
	draw_arc(Vector2.ZERO, r * 0.7, _elapsed * 1.2, _elapsed * 1.2 + 4.5, 24,
		Color(_color.r, _color.g, _color.b, 0.4 * alpha), 1.6, true)
	# Effect-flavoured fill drawn in the same flat frame.
	match _effect:
		"shadow":
			_draw_tendrils(r, alpha)
		"frost":
			_draw_snow(r, alpha)
		"holy":
			_draw_radiance(r, alpha)
		_:
			_draw_tendrils(r, alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Void zone: writhing dark tendrils reaching in from the rim.
func _draw_tendrils(r: float, alpha: float) -> void:
	for i in _seed.size():
		var a0: float = _seed[i] + _elapsed * 0.6
		var pts := PackedVector2Array()
		for k in 5:
			var t: float = float(k) / 4.0
			var wob: float = sin(_elapsed * 4.0 + _seed[i] + t * 6.0) * 8.0 * (1.0 - t)
			var ang: float = a0 + wob * 0.02
			pts.append(Vector2.from_angle(ang) * r * (1.0 - t * 0.75) + Vector2.from_angle(ang).orthogonal() * wob)
		draw_polyline(pts, Color(0.35, 0.12, 0.5, 0.55 * alpha), 2.4, true)


## Blizzard: pale snow flecks swirling + a frost hexagon.
func _draw_snow(r: float, alpha: float) -> void:
	for i in _seed.size():
		var a: float = _seed[i] + _elapsed * 1.4
		var rad: float = r * (0.3 + 0.6 * fposmod(_seed[i] + _elapsed * 0.5, 1.0))
		draw_circle(Vector2.from_angle(a) * rad, 1.8, Color(0.9, 0.97, 1.0, 0.7 * alpha), true, -1.0, true)
	var hex := PackedVector2Array()
	for k in 7:
		hex.append(Vector2.from_angle(TAU * float(k) / 6.0 + _elapsed * 0.4) * r * 0.55)
	draw_polyline(hex, Color(0.75, 0.92, 1.0, 0.45 * alpha), 1.6, true)


## Consecrated ground: radiant spokes + a bright bloom (heals allies).
func _draw_radiance(r: float, alpha: float) -> void:
	for i in 12:
		var a: float = TAU * float(i) / 12.0 + _elapsed * 0.3
		draw_line(Vector2.from_angle(a) * r * 0.2, Vector2.from_angle(a) * r * 0.9,
			Color(1.3, 1.15, 0.6, 0.4 * alpha), 1.6, true)
	draw_circle(Vector2.ZERO, r * 0.3, Color(1.4, 1.2, 0.7, 0.35 * alpha), true, -1.0, true)
