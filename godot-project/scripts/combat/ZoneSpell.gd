class_name ZoneSpell
extends Node2D
## A persistent GROUND FIELD (SpellDef.Kind.ZONE) — Cryomancer's BLIZZARD (frost),
## Cleric's CONSECRATED GROUND (holy — heals allies standing in it) and the legacy
## shadow pool (Warlock's shadow ZONE now routes to ShadowRoot in the dispatcher).
## Aim-placed; every tick it damages + applies the element ailment to enemies
## inside, for its lifetime, then fades. Draws in world coordinates.
##
## FROST is no longer the recoloured puddle the maker called "boring and corny":
## it draws a full storm CELL above the footprint — wind-driven snow STREAKING
## sideways through the volume (the wind blows away from the caster), pulsing
## gust sheets, a ragged churning storm-front instead of a clean ring, and ice
## visibly ACCRETING on the ground (slab + growing icicles + HDR tip glints)
## for the squall's life. The slow that builds on victims comes free from the
## existing ICE ailment path (StatusComponent chill -> freeze), so standing in
## it visibly ices you over — the zone itself just has to LOOK like weather.

const TICK: float = 0.4
const FADE: float = 0.6
const HEAL_PER_TICK: int = 6
# Blizzard squall tuning — streak count/speed chosen so the motion reads at a
# glance without melting the draw pass (all polylines, one canvas item).
const SQUALL_FLAKES: int = 58
const SQUALL_WIND: float = 390.0    # horizontal drive px/s — violent, not drifting
const SQUALL_FALL: float = 90.0     # downward bias so streaks slant like sleet
const SQUALL_HEIGHT: float = 118.0  # storm cell height above the footprint
const ICICLE_COUNT: int = 9

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
var _wind: float = 1.0                                  # squall direction sign
var _fseed: PackedFloat32Array = PackedFloat32Array()   # per-flake px/py/speed/len
var _iseed: PackedFloat32Array = PackedFloat32Array()   # per-icicle x-frac/height


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
	for i: int in 10:
		_seed.append(randf() * TAU)
	if _effect == "frost":
		_wind = _wind_sign()
		for i: int in SQUALL_FLAKES * 4:
			_fseed.append(randf())
		for i: int in ICICLE_COUNT * 2:
			_iseed.append(randf())
		# Entrance gust: a horizontal blast of driven snow so the squall ARRIVES
		# instead of fading in — the "violent weather" first impression.
		CombatVfx.spawn_burst(get_parent(), _at + Vector2(-_wind * _radius * 0.5, -46.0),
			Color(0.98, 1.05, 1.2, 0.9), Color(0.7, 0.85, 1.0, 0.0),
			18, 0.55, 260.0, 460.0, 0.5, 1.4, 0.0, 0.0, true, Vector2(_wind, -0.08), 22.0)
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


## The squall blows AWAY from whoever cast it (nearest player) — a directional
## storm, not an isotropic puddle. Falls back to rightward when no player group
## exists (headless tests / detached sandboxes) so captures stay deterministic.
func _wind_sign() -> float:
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Node2D:
			return 1.0 if _at.x >= (p as Node2D).global_position.x else -1.0
	return 1.0


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
	if _effect == "frost":
		# Wind-driven sleet gust from the upwind edge — the tick reads as WEATHER
		# pushing through, not motes floating up out of a stain.
		CombatVfx.spawn_burst(get_parent(), _at + Vector2(-_wind * _radius * 0.7, -30.0 - randf() * 60.0),
			Color(0.95, 1.0, 1.12, 0.8), Color(0.7, 0.85, 1.0, 0.0),
			10, 0.45, 240.0, 380.0, 0.5, 1.2, 0.0, 0.0, true, Vector2(_wind, 0.14), 16.0)
	else:
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
	if _effect == "frost":
		_draw_squall(r, alpha)  # blizzard owns its whole look — no generic puddle
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
		"holy":
			_draw_radiance(r, alpha)
		_:
			_draw_tendrils(r, alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## BLIZZARD: a violent, directional storm cell. Layer order matters — ground ice
## first (behind), then haze, gust sheets, and the snow streaks on top so the
## motion is the loudest read. Every alpha rides `alpha` so the fade-out kills
## the whole cell together.
func _draw_squall(r: float, alpha: float) -> void:
	var acc: float = smoothstep(0.0, _life * 0.65, _elapsed)  # ice accretion build
	var h: float = SQUALL_HEIGHT + r * 0.25
	# ---- ground plane (squashed frame): cold shadow, accreting slab, ragged rim.
	draw_set_transform(_at, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, r, Color(0.10, 0.16, 0.30, 0.16 * alpha), true, -1.0, true)
	draw_circle(Vector2.ZERO, r * (0.5 + 0.4 * acc),
		Color(0.62, 0.82, 0.98, (0.07 + 0.13 * acc) * alpha), true, -1.0, true)
	# Ragged storm-front: jittered rim dashes rotating with the wind — a churning
	# edge, deliberately NOT the clean ring every other zone had.
	for i: int in 26:
		var a0: float = TAU * float(i) / 26.0 + _elapsed * 0.9 * _wind
		var jag: float = 0.86 + 0.16 * sin(_seed[i % 10] * 7.0 + _elapsed * 5.0 + float(i))
		var flick: float = 0.35 + 0.30 * absf(sin(float(i) * 1.7 + _elapsed * 3.0))
		var span: float = 0.10 + 0.12 * _seed[(i + 3) % 10] / TAU
		draw_arc(Vector2.ZERO, r * jag, a0, a0 + span, 4,
			Color(0.80, 0.93, 1.05, flick * alpha), 2.0, true)
	# Inner vortex arcs — fast counter-rotating swirls say "cyclone", cheaply.
	draw_arc(Vector2.ZERO, r * 0.62, _elapsed * 2.6 * _wind, _elapsed * 2.6 * _wind + 2.2, 18,
		Color(0.85, 0.95, 1.1, 0.22 * alpha), 1.8, true)
	draw_arc(Vector2.ZERO, r * 0.40, -_elapsed * 3.4 * _wind, -_elapsed * 3.4 * _wind + 1.7, 14,
		Color(0.9, 1.0, 1.15, 0.18 * alpha), 1.4, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ---- icicles accreting upward off the slab (world frame, grow with `acc`).
	for i: int in ICICLE_COUNT:
		var xfrac: float = _iseed[i * 2]
		var hmul: float = _iseed[i * 2 + 1]
		var ih: float = acc * (6.0 + 13.0 * hmul)
		if ih < 2.0:
			continue
		var base: Vector2 = _at + Vector2((xfrac * 2.0 - 1.0) * r * 0.7, 2.0)
		var tip: Vector2 = base + Vector2(0.0, -ih)
		draw_line(base + Vector2(-2.2, 0.0), tip, Color(0.75, 0.90, 1.0, 0.75 * alpha), 1.4, true)
		draw_line(base + Vector2(2.2, 0.0), tip, Color(0.85, 0.95, 1.05, 0.6 * alpha), 1.2, true)
		# HDR glint on the tip so the accretion sparkles under bloom.
		var glint: float = 0.5 + 0.4 * sin(_elapsed * 9.0 + xfrac * 20.0)
		draw_circle(tip, 1.1, Color(1.3, 1.55, 1.8, glint * acc * alpha), true, -1.0, true)
	# ---- whiteout haze: translucent lobes drifting inside the cell. Two nested
	# discs per lobe = a cheap soft gradient, so no hard "UFO disc" edge shows.
	for i: int in 3:
		var ph: float = _elapsed * (0.6 + 0.2 * float(i)) + _seed[i]
		draw_set_transform(_at + Vector2(sin(ph) * r * 0.3, -h * (0.30 + 0.20 * float(i))),
			0.0, Vector2(1.25, 0.5))
		var la: float = (0.030 + 0.012 * float(i)) * alpha
		draw_circle(Vector2.ZERO, r * (0.5 + 0.12 * float(i)),
			Color(0.86, 0.93, 1.0, la), true, -1.0, true)
		draw_circle(Vector2.ZERO, r * (0.32 + 0.08 * float(i)),
			Color(0.9, 0.96, 1.05, la * 1.4), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ---- gust sheets: broad curved bands of driven snow, pulsing like gusts.
	for g: int in 3:
		var env: float = 0.35 + 0.65 * maxf(0.0, sin(_elapsed * (1.6 + 0.4 * float(g)) + _seed[g] * 3.0))
		var pts := PackedVector2Array()
		for k: int in 13:
			var u: float = float(k) / 12.0
			var gy: float = -h * (0.30 + 0.18 * float(g)) \
				+ sin(u * 4.5 - _wind * _elapsed * (5.0 + float(g)) + _seed[g]) * h * 0.10
			pts.append(_at + Vector2((u * 2.0 - 1.0) * r, gy))
		draw_polyline(pts, Color(1.0, 1.05, 1.15, 0.10 * env * alpha), 10.0, true)
		draw_polyline(pts, Color(0.92, 0.97, 1.05, 0.16 * env * alpha), 5.0, true)
	# ---- the snow itself: fast, slanted, wind-driven streaks wrapping the cell.
	for i: int in SQUALL_FLAKES:
		var px: float = _fseed[i * 4]
		var py: float = _fseed[i * 4 + 1]
		var sm: float = 0.7 + 0.7 * _fseed[i * 4 + 2]
		var lm: float = 0.6 + 0.8 * _fseed[i * 4 + 3]
		var vel := Vector2(_wind * SQUALL_WIND * sm, SQUALL_FALL * (0.5 + 0.5 * sm))
		var x: float = fposmod(px * r * 2.0 + _elapsed * vel.x, r * 2.0) - r
		var y: float = -h + fposmod(py * h + _elapsed * vel.y, h)
		# Fade at the cell edges so streaks never pop in/out of existence.
		var edge: float = (1.0 - pow(absf(x) / r, 2.4)) \
			* (1.0 - pow(absf(y + h * 0.5) / (h * 0.5), 3.0))
		if edge <= 0.03:
			continue
		var head: Vector2 = _at + Vector2(x, y)
		var dir: Vector2 = vel.normalized()
		var streak: float = (12.0 + 16.0 * lm) * edge
		# Tapered streak: bright short head + long faint tail = MOTION, not dots.
		draw_line(head, head - dir * streak * 0.4,
			Color(1.0, 1.08, 1.2, edge * alpha), 2.2, true)
		draw_line(head - dir * streak * 0.35, head - dir * streak,
			Color(0.8, 0.9, 1.0, 0.5 * edge * alpha), 1.3, true)
		if i % 5 == 0:  # sparse HDR sleet glints so the storm sparkles under bloom
			draw_circle(head, 1.2, Color(1.35, 1.55, 1.8, 0.7 * edge * alpha), true, -1.0, true)


## Void zone: writhing dark tendrils reaching in from the rim (legacy shadow
## fill — kept for any ZONE def that still routes shadow here).
func _draw_tendrils(r: float, alpha: float) -> void:
	for i: int in _seed.size():
		var a0: float = _seed[i] + _elapsed * 0.6
		var pts := PackedVector2Array()
		for k: int in 5:
			var t: float = float(k) / 4.0
			var wob: float = sin(_elapsed * 4.0 + _seed[i] + t * 6.0) * 8.0 * (1.0 - t)
			var ang: float = a0 + wob * 0.02
			pts.append(Vector2.from_angle(ang) * r * (1.0 - t * 0.75) + Vector2.from_angle(ang).orthogonal() * wob)
		draw_polyline(pts, Color(0.35, 0.12, 0.5, 0.55 * alpha), 2.4, true)


## Consecrated ground: radiant spokes + a bright bloom (heals allies).
func _draw_radiance(r: float, alpha: float) -> void:
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0 + _elapsed * 0.3
		draw_line(Vector2.from_angle(a) * r * 0.2, Vector2.from_angle(a) * r * 0.9,
			Color(1.3, 1.15, 0.6, 0.4 * alpha), 1.6, true)
	draw_circle(Vector2.ZERO, r * 0.3, Color(1.4, 1.2, 0.7, 0.35 * alpha), true, -1.0, true)
