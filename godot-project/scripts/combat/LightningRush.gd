class_name LightningRush
extends Node2D
## Signature spectacle — CHIDORI / Thunderclap. The Brawler's ultimate: a brief
## crackling charge, then a JAGGED lightning LANCE rips down the aim in an instant
## — nothing like the clean Zoltraak beam. Everything on the line takes heavy
## damage + Shock and is thrown along the strike; the bolt then FORKS a chain-arc
## to a nearby straggler. Heavy juice: hitstop, big shake, zoom-punch, thunder crack.
##
## Damage is a pure line test (targets_on_line, headless-testable). rush() drives
## the visual/juice timeline. Instantiate .new(), add under the arena, call rush().
## The hero does its own forward lunge on cast (Hero._cast_signature) so it READS
## as a dash-punch; this node owns the bolt + damage + chain + screen kick.

const CHARGE_TIME: float = 0.16   # snappy — a chidori is instant, not a slow beam
const STRIKE_TIME: float = 0.10   # the bolt at full intensity
const FADE_TIME: float = 0.30     # crackle dissolve
const DEFAULT_LENGTH: float = 620.0
const DEFAULT_WIDTH: float = 26.0
const DEFAULT_DAMAGE: int = 62
const KNOCKBACK: float = 460.0    # brutal — it's a committed melee ultimate
const CHAIN_RANGE: float = 220.0  # fork-arc reach to a nearby straggler
const CHAIN_DAMAGE_FACTOR: float = 0.5
const BOLT_SEGMENTS: int = 12     # jagged bolt resolution
const CORE_COLOR: Color = Color(0.95, 0.98, 1.0)  # white-hot lightning core

var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(1.0, 0.9, 0.35, 1.0)
var _length: float = DEFAULT_LENGTH
var _width: float = DEFAULT_WIDTH
var _damage: int = DEFAULT_DAMAGE
var _elapsed: float = -1.0
var _fired: bool = false
var _chain_from: Vector2 = Vector2.ZERO
var _chain_to: Vector2 = Vector2.ZERO
var _has_chain: bool = false
var _flick_seed: float = 0.0  # per-frame jitter phase (varies the bolt shape)
## Elemental ailment (Elements.Element) applied to struck enemies — LIGHTNING.
var element_id: int = Elements.Element.LIGHTNING


## Public entry: charge at `origin`, then rip a lightning lance of length/width
## along `dir` for `damage`. Colour tints the arc (defaults to the lightning
## yellow); the core stays white-hot.
func rush(
	origin: Vector2,
	dir: Vector2,
	color: Color,
	length: float = DEFAULT_LENGTH,
	width: float = DEFAULT_WIDTH,
	damage: int = DEFAULT_DAMAGE,
	_effect: String = "lightning",
) -> void:
	_origin = origin
	_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_color = color
	_length = length
	_width = width
	_damage = damage
	global_position = Vector2.ZERO  # drawn in world space from _origin
	_elapsed = 0.0
	# Charge crackle at the fist — sharp electric sparks gathering.
	CombatVfx.spawn_burst(
		get_parent(), _origin, Color(1.0, 1.0, 0.85, 0.95), Color(_color.r, _color.g, _color.b, 0.0),
		20, CHARGE_TIME * 0.9, 60.0, 150.0, 0.6, 1.6, 2.5, 5.0
	)
	Sfx.play("cast", 2.0, 0.04)
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	_flick_seed += delta * 90.0  # fast re-jitter = crackling read
	if not _fired and _elapsed >= CHARGE_TIME:
		_discharge()
	if _elapsed >= CHARGE_TIME + STRIKE_TIME + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## The lance rips: line damage + Shock + shove, a fork-arc to a straggler, and a
## heavy screen kick. Thunder crack SFX + music duck for the impact beat.
func _discharge() -> void:
	_fired = true
	var half: float = _width * 0.5 + 10.0  # forgiving hit corridor
	var struck: Array = targets_on_line(_origin, _dir, _length, half, get_tree().get_nodes_in_group("enemy"))
	for enemy: Node in struck:
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(_dir * KNOCKBACK)
	for prop: Node in targets_on_line(_origin, _dir, _length, half, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	_resolve_chain(struck)
	CombatVfx.spawn_burst(
		get_parent(), _beam_tip(), CORE_COLOR, Color(_color.r, _color.g, _color.b, 0.0),
		34, 0.4, 140.0, 380.0, 0.7, 2.0, 3.0, 6.0
	)
	Juice.hit_stop(0.1)
	Juice.shake_camera(15.0)
	Juice.zoom_punch_camera(0.11, 0.22)
	Juice.zoom_pull_camera(0.14, 0.3, 0.12, 0.45)  # brief pull to show the strike
	Sfx.play("blast", 2.0, 0.06)
	var music: Node = get_node_or_null("/root/Music")
	if music != null and music.has_method("duck"):
		music.call("duck", 7.0, 0.35)


## Fork a chain-arc to the nearest enemy NOT already on the line (a straggler),
## dealing partial damage + Shock so the strike jumps like real lightning.
func _resolve_chain(already_hit: Array) -> void:
	var tip: Vector2 = _beam_tip()
	var best: Node2D = null
	var best_d: float = CHAIN_RANGE
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if e in already_hit or not e is Node2D or not is_instance_valid(e):
			continue
		var d: float = tip.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	if best == null:
		return
	if best.has_method("take_damage"):
		best.take_damage(int(round(float(_damage) * CHAIN_DAMAGE_FACTOR)))
	if best.has_method("apply_status"):
		best.apply_status(element_id, false)  # no further chain
	_chain_from = tip
	_chain_to = best.global_position
	_has_chain = true


## Pure geometry (testable): nodes whose centre projects onto the segment
## [0, length] along `dir` from `origin`, within `half_width` perpendicular.
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


func _beam_tip() -> Vector2:
	return _origin + _dir * _length


## Deterministic-per-frame jagged offset for segment `i` of `n` (0..1 along the
## bolt), tapering to 0 at both ends so the lance connects cleanly.
func _jag(i: int, n: int) -> float:
	var t: float = float(i) / float(n)
	var taper: float = sin(t * PI)  # 0 at ends, 1 mid-bolt
	var noise: float = sin(float(i) * 12.9898 + _flick_seed) * 0.6 \
			+ sin(float(i) * 4.1 + _flick_seed * 1.7) * 0.4
	return noise * taper * _width * 1.6


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < CHARGE_TIME:
		# Charge: a tight crackle ball at the fist gathering to full.
		var cp: float = _elapsed / CHARGE_TIME
		draw_circle(_origin, _width * (0.4 + 0.5 * cp), Color(_color.r, _color.g, _color.b, 0.4 * cp))
		draw_circle(_origin, _width * 0.35 * cp, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.7 * cp))
		return
	var since: float = _elapsed - CHARGE_TIME
	var intensity: float
	if since < STRIKE_TIME:
		intensity = 1.0
	else:
		intensity = clampf(1.0 - (since - STRIKE_TIME) / FADE_TIME, 0.0, 1.0)
	if intensity <= 0.01:
		return
	var tip: Vector2 = _beam_tip()
	var perp: Vector2 = _dir.orthogonal()
	# Build the jagged bolt polyline.
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in BOLT_SEGMENTS + 1:
		var along: Vector2 = _origin.lerp(tip, float(i) / float(BOLT_SEGMENTS))
		pts.append(along + perp * _jag(i, BOLT_SEGMENTS))
	# Layered: wide soft glow -> arc body -> white-hot core.
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.22 * intensity), _width * 1.4)
	draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.65 * intensity), _width * 0.5)
	draw_polyline(pts, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.95 * intensity), _width * 0.18)
	# Branch forks off a few mid-bolt nodes (short jagged offshoots).
	for i: int in range(2, BOLT_SEGMENTS - 1, 3):
		var base: Vector2 = pts[i]
		var side: float = 1.0 if (i + int(_flick_seed)) % 2 == 0 else -1.0
		var fork_dir: Vector2 = (_dir + perp * side * 1.4).normalized()
		var fork_end: Vector2 = base + fork_dir * _width * (1.2 + absf(sin(float(i) + _flick_seed)))
		draw_line(base, fork_end, Color(_color.r, _color.g, _color.b, 0.6 * intensity), 2.0)
		draw_line(base, fork_end, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.5 * intensity), 1.0)
	# Muzzle + impact flash.
	draw_circle(_origin, _width * 1.3, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.55 * intensity))
	draw_circle(tip, _width * 1.1, Color(_color.r, _color.g, _color.b, 0.5 * intensity))
	draw_circle(tip, _width * 0.5, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.6 * intensity))
	# The fork-arc to a chained straggler (a thin jagged line).
	if _has_chain:
		var cperp: Vector2 = (_chain_to - _chain_from).orthogonal().normalized()
		var cpts: PackedVector2Array = PackedVector2Array()
		for i: int in 6:
			var t: float = float(i) / 5.0
			var base2: Vector2 = _chain_from.lerp(_chain_to, t)
			var jitter: float = sin(float(i) * 9.0 + _flick_seed) * sin(t * PI) * 10.0
			cpts.append(base2 + cperp * jitter)
		draw_polyline(cpts, Color(_color.r, _color.g, _color.b, 0.8 * intensity), 3.0)
		draw_polyline(cpts, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 0.7 * intensity), 1.2)
