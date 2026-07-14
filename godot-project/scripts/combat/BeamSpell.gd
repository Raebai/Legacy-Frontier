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
##
## The trailing `effect` param picks the elemental CHARACTER of the spectacle
## ("frost" | "fire" | "arcane" | "holy") — same beam silhouette, distinct
## palette + particle language + lingering mark, so each legendary reads
## different at a glance.

const CHARGE_TIME: float = 0.34   # sigil gather (telegraph)
const FIRE_TIME: float = 0.26     # beam held at full intensity
const FADE_TIME: float = 0.22     # beam + circle dissolve
const DEFAULT_LENGTH: float = 1100.0
const DEFAULT_WIDTH: float = 30.0
const DEFAULT_DAMAGE: int = 46
const KNOCKBACK: float = 360.0
const CIRCLE_RADIUS_FACTOR: float = 3.3  # muzzle sigil radius = width * this (grand)

var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(0.95, 0.4, 0.85, 1.0)
var _length: float = DEFAULT_LENGTH
var _width: float = DEFAULT_WIDTH
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "arcane"
var _elapsed: float = -1.0     # < 0 = not fired yet
var _fired: bool = false       # damage/juice applied once at end of charge
var _circle: MagicCircle = null
## Elemental ailment (Elements.Element) applied to enemies the beam hits. -1=none.
var element_id: int = -1


## Public entry: charge at `origin`, then fire a beam of `length`/`width` along
## `dir`, dealing `damage`. Colour tints the whole spectacle (element);
## `effect` picks its particle character ("frost"/"fire"/"arcane"/"holy").
func fire(
	origin: Vector2,
	dir: Vector2,
	color: Color,
	length: float = DEFAULT_LENGTH,
	width: float = DEFAULT_WIDTH,
	damage: int = DEFAULT_DAMAGE,
	effect: String = "arcane",
) -> void:
	_origin = origin
	_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_color = color
	_length = length
	_width = width
	_damage = damage
	_effect = effect
	global_position = Vector2.ZERO  # we draw in world space from _origin
	_elapsed = 0.0
	# Muzzle sigil materialises during the charge, oriented at the origin.
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.global_position = _origin
	_circle.appear(_color, _width * CIRCLE_RADIUS_FACTOR, CHARGE_TIME * 0.9)
	# EDGE-ON: a beam's sigil faces the target, so side-on it's a thin gate
	# perpendicular to the beam that the bolt bursts through (not a flat circle).
	_circle.set_orientation(true, _dir, 0.14)
	# Gathering particles at the muzzle — energy pulled in before the shot,
	# charactered per effect. Parented to the arena (get_parent()), NOT self:
	# the burst outlives this short-lived spectacle node, matching Spell/Enemy
	# so it fades naturally after we free.
	_charge_burst()
	Sfx.play("cast", -2.0, 0.05)
	queue_redraw()


## Muzzle-gather particles, per effect: frost = fast sharp shards that snap to
## a cold stop, fire = slow flickery embers, holy = drifting feathery motes,
## arcane = the classic bright energy spark.
func _charge_burst() -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	match _effect:
		"frost":
			CombatVfx.spawn_burst(
				get_parent(), _origin, Color(0.85, 0.97, 1.0, 0.95), fade,
				16, CHARGE_TIME * 0.85, 70.0, 160.0, 0.6, 1.6, 2.5, 5.0
			)
		"fire":
			CombatVfx.spawn_burst(
				get_parent(), _origin, Color(1.0, 0.75, 0.3, 0.9), Color(0.9, 0.2, 0.05, 0.0),
				22, CHARGE_TIME, 20.0, 70.0, 1.2, 3.2
			)
		"holy":
			CombatVfx.spawn_burst(
				get_parent(), _origin, Color(1.0, 0.98, 0.85, 0.9), fade,
				26, CHARGE_TIME * 1.1, 15.0, 55.0, 0.8, 2.2, 1.0, 2.0
			)
		_:
			CombatVfx.spawn_burst(
				get_parent(), _origin, Color(1, 1, 1, 0.9), fade,
				18, CHARGE_TIME, 30.0, 90.0, 1.0, 2.5
			)


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
	_impact_burst(tip)
	_impact_mark(tip)
	Juice.hit_stop(0.09)
	Juice.shake_camera(16.0)
	Juice.zoom_punch_camera(0.1, 0.24)
	Sfx.play("blast", 1.0, 0.08)
	if _circle != null and is_instance_valid(_circle):
		_circle.vanish(FIRE_TIME + FADE_TIME)


## Impact spray at the beam tip, charactered per effect: frost = fast shards
## that snap to a cold stop, fire = a warm ember spray + physical ember debris,
## holy = a big feathery radiant flash, arcane = the classic white-hot spray.
func _impact_burst(tip: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	match _effect:
		"frost":
			CombatVfx.spawn_burst(
				get_parent(), tip, Color(0.9, 0.98, 1.0, 0.95), fade,
				40, 0.45, 180.0, 420.0, 0.7, 1.8, 3.0, 6.0, true
			)
		"fire":
			CombatVfx.spawn_burst(
				get_parent(), tip, Color(1.0, 0.85, 0.4, 0.95), Color(0.85, 0.15, 0.05, 0.0),
				46, 0.55, 100.0, 320.0, 1.5, 4.0, 0.0, 0.0, true
			)
			DebrisChunk.spawn_burst(get_parent(), tip, Color(0.55, 0.25, 0.1), 4, _dir, 200.0)
		"holy":
			CombatVfx.spawn_burst(
				get_parent(), tip, Color(1.0, 0.99, 0.9, 0.98), fade,
				52, 0.65, 60.0, 220.0, 1.0, 3.0, 1.0, 2.5, true
			)
		_:
			CombatVfx.spawn_burst(
				get_parent(), tip, Color(1, 1, 1, 0.95), fade,
				46, 0.5, 120.0, 360.0, 1.5, 4.0, 0.0, 0.0, true
			)


## Lingering ground mark at the impact, per effect: frost leaves an icy shard
## crack, fire a burnt scorch. Arcane/holy leave no residue (pure energy/light).
func _impact_mark(tip: Vector2) -> void:
	match _effect:
		"frost":
			ScorchDecal.spawn(
				get_parent(), tip, _width * 1.2, "crack",
				Color(0.62, 0.88, 1.0, 0.5), 6.0
			)
		"fire":
			ScorchDecal.spawn(
				get_parent(), tip, _width * 1.3, "scorch",
				Color(0.06, 0.03, 0.02, 0.6), 8.0
			)


## Beam damage: every enemy/destructible whose centre lies on the beam segment
## (within half-width) takes damage; enemies are shoved along the beam.
func _apply_beam_damage() -> void:
	var half: float = _width * 0.5 + 8.0  # a little forgiveness on the width
	for enemy: Node in targets_on_beam(_origin, _dir, _length, half, get_tree().get_nodes_in_group("enemy")):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
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
				Color(_color.r, _color.g, _color.b, 0.12 * tp), 2.0, true)
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
	var flick: float = _effect_flicker()
	var w: float = _width * intensity * flick
	var c: Color = _color
	var core: Color = _effect_core_color()
	# Layered beam: wide soft glow -> mid body -> hot core (core tinted per
	# effect: icy white / furnace yellow / radiant warm white / pure white).
	if _effect == "fire":
		# FIRE = two serpentine DRAGONS weaving around a thin spine (the hit
		# corridor is unchanged — this is a visual skin over the same line).
		_draw_beam_band(_origin, tip, w * 0.35, Color(core.r, core.g, core.b, 0.85 * intensity))
		_draw_fire_dragons(tip, w, intensity, c, core)
	else:
		if _effect == "holy":
			# Extra-wide feathery halo — holy reads as radiance, not a laser.
			_draw_beam_band(_origin, tip, w * 2.7, Color(c.r, c.g, c.b, 0.12 * intensity))
		_draw_beam_band(_origin, tip, w * 1.8, Color(c.r, c.g, c.b, 0.28 * intensity))
		_draw_beam_band(_origin, tip, w * 1.0, Color(c.r, c.g, c.b, 0.7 * intensity))
		_draw_beam_band(_origin, tip, w * 0.4, Color(core.r, core.g, core.b, 0.95 * intensity))
		_draw_effect_detail(tip, w, intensity)
	# Muzzle flash + impact flash.
	draw_circle(_origin, w * 1.4, Color(core.r, core.g, core.b, 0.5 * intensity), true, -1.0, true)
	draw_circle(tip, w * 1.2, Color(c.r, c.g, c.b, 0.5 * intensity), true, -1.0, true)
	draw_circle(tip, w * 0.6, Color(core.r, core.g, core.b, 0.6 * intensity), true, -1.0, true)
	# ICE = a hexagonal "freezing lens" flare at the muzzle (unmistakable ice read).
	if _effect == "frost":
		_draw_frost_lens(w, intensity, core)


## Beam flicker character: frost is dead-steady (cold), fire rages, holy
## breathes slowly, arcane keeps the classic subtle energy flicker.
func _effect_flicker() -> float:
	match _effect:
		"frost":
			return 1.0
		"fire":
			return 0.8 + 0.2 * sin(_elapsed * 85.0)
		"holy":
			return 0.94 + 0.06 * sin(_elapsed * 28.0)
		_:
			return 0.9 + 0.1 * sin(_elapsed * 60.0)


## Hot-core tint per effect (the innermost band + flashes).
func _effect_core_color() -> Color:
	match _effect:
		"frost":
			return Color(1.4, 1.5, 1.7)  # HDR cores bloom
		"fire":
			return Color(1.8, 1.55, 1.0)
		"holy":
			return Color(1.85, 1.75, 1.45)
		_:
			return Color(1.6, 1.6, 1.7)


## Per-effect garnish drawn ALONG the beam so each element is unmistakable:
## frost = crystalline shards jutting off the beam, fire = drifting embers,
## holy = bobbing feathery motes. Arcane stays the clean energy beam.
func _draw_effect_detail(tip: Vector2, w: float, intensity: float) -> void:
	var perp: Vector2 = _dir.orthogonal()
	match _effect:
		"frost":
			for i: int in 11:
				var t: float = (float(i) + 0.7) / 11.5
				var p: Vector2 = _origin.lerp(tip, t)
				var side: float = 1.0 if i % 2 == 0 else -1.0
				var reach: float = w * (1.3 + 0.5 * sin(float(i) * 12.9898))
				var base_half: Vector2 = _dir * (w * 0.35)
				draw_colored_polygon(PackedVector2Array([
					p - base_half, p + base_half, p + perp * side * reach,
				]), Color(0.85, 0.97, 1.0, 0.75 * intensity))
		"fire":
			for i: int in 9:
				var t: float = fposmod(float(i) / 9.0 + _elapsed * 0.9 + sin(float(i) * 7.31) * 0.05, 1.0)
				var p: Vector2 = _origin.lerp(tip, t) \
					+ perp * sin(_elapsed * 14.0 + float(i) * 2.1) * w * 1.1
				draw_circle(p, w * 0.16 + 1.5,
					Color(1.0, 0.55 + 0.3 * absf(sin(float(i) * 3.7)), 0.15, 0.8 * intensity), true, -1.0, true)
		"holy":
			for i: int in 8:
				var t: float = (float(i) + 0.5) / 8.0
				var p: Vector2 = _origin.lerp(tip, t) \
					+ perp * sin(_elapsed * 6.0 + float(i) * 1.7) * w * 1.4
				var ma: float = (0.35 + 0.25 * sin(_elapsed * 9.0 + float(i))) * intensity
				draw_circle(p, w * 0.4, Color(1.0, 0.97, 0.8, ma * 0.5), true, -1.0, true)
				draw_circle(p, w * 0.16, Color(1.0, 1.0, 0.95, ma), true, -1.0, true)
		"arcane":
			for i: int in 5:
				var ap: Vector2 = _origin.lerp(tip, (float(i) + 0.5) / 5.0)
				var apulse: float = 0.5 + 0.5 * sin(_elapsed * 6.0 - float(i) * 1.3)
				var arr: float = w * (0.5 + 0.7 * apulse)
				draw_arc(ap, arr, 0.0, TAU, 18, Color(_color.r, _color.g, _color.b, 0.6 * intensity), 1.5, true)
				for k: int in 6:
					var av: Vector2 = Vector2.from_angle(_elapsed * 1.5 + TAU * float(k) / 6.0)
					draw_line(ap + av * arr * 0.7, ap + av * arr, Color(1.0, 0.9, 1.0, 0.5 * intensity), 1.5, true)


## FIRE beam skin: two serpentine dragon bodies weaving in counter-phase around
## the beam centerline (the hit corridor is unchanged — visual only).
func _draw_fire_dragons(tip: Vector2, w: float, intensity: float, c: Color, core: Color) -> void:
	_draw_dragon_body(tip, w, intensity, core, 1.0, 0.0)
	_draw_dragon_body(tip, w, intensity, core, -1.0, PI)


func _draw_dragon_body(tip: Vector2, w: float, intensity: float, core: Color, side_sign: float, phase_offset: float) -> void:
	var perp: Vector2 = _dir.orthogonal()
	var seg: int = 14
	var amp: float = w * 1.5
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in seg + 1:
		var t: float = float(i) / float(seg)
		var along: Vector2 = _origin.lerp(tip, t)
		var off: float = sin(t * 5.0 - _elapsed * 9.0 + phase_offset) * amp * side_sign * (0.35 + 0.65 * t)
		pts.append(along + perp * off)
	draw_polyline(pts, Color(1.0, 0.4, 0.1, 0.35 * intensity), w * 1.3, true)
	draw_polyline(pts, Color(1.0, 0.6, 0.2, 0.7 * intensity), w * 0.55, true)
	draw_polyline(pts, Color(core.r, core.g, core.b, 0.9 * intensity), w * 0.22, true)
	var head: Vector2 = pts[pts.size() - 1]
	var hdir: Vector2 = (head - pts[pts.size() - 2]).normalized()
	var hperp: Vector2 = hdir.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		head + hdir * w * 1.1, head + hperp * w * 0.7, head - hperp * w * 0.7,
	]), Color(1.0, 0.7, 0.2, 0.9 * intensity))
	draw_circle(head, w * 0.35, Color(core.r, core.g, core.b, intensity), true, -1.0, true)
	for i: int in range(3, seg, 3):
		var p: Vector2 = pts[i]
		var d: Vector2 = (pts[i] - pts[i - 1]).normalized()
		draw_line(p, p + d.orthogonal() * side_sign * w * 0.9, Color(1.0, 0.5, 0.1, 0.7 * intensity), 2.0, true)


## ICE muzzle "freezing lens": a hexagonal crystal facet at the beam origin.
func _draw_frost_lens(w: float, intensity: float, core: Color) -> void:
	var r: float = w * 1.3
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 6:
		pts.append(_origin + Vector2.from_angle(_dir.angle() + TAU * float(i) / 6.0) * r)
	draw_colored_polygon(pts, Color(0.8, 0.95, 1.0, 0.35 * intensity))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.9, 0.98, 1.0, 0.9 * intensity), 2.0, true)
	draw_circle(_origin, w * 0.4, Color(core.r, core.g, core.b, intensity), true, -1.0, true)


## A filled beam band (rectangle) of thickness `thick` from `a` to `b`.
func _draw_beam_band(a: Vector2, b: Vector2, thick: float, col: Color) -> void:
	var d: Vector2 = (b - a)
	if d.length() < 0.001:
		return
	var perp: Vector2 = d.normalized().orthogonal() * (thick * 0.5)
	draw_colored_polygon(
		PackedVector2Array([a + perp, b + perp, b - perp, a - perp]), col
	)
