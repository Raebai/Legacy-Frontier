class_name MeteorSigil
extends Node2D
## Signature spectacle #3 — METEOR SIGIL. A huge magic circle opens high in the
## sky over the marked area and a BARRAGE of meteors streaks down, each a fiery
## head + trail that detonates on the ground with a burst + a small radius of
## damage. Staggered so it reads as a shower, climaxing on the last few. The
## area-bombardment counterpart to the beam (line) and divine ray (single
## column) — the third distinct spectacle silhouette.
##
## Per-meteor radius damage (targets_in_radius, pure/testable); rain() drives the
## timeline. Instantiate .new(), add to the arena, call rain().
##
## The trailing `effect` param picks the elemental CHARACTER of the shower
## ("fire" | "frost" | "arcane" | "holy") — same barrage silhouette, distinct
## head/trail palette + impact, so it reads different at a glance.

const CHARGE_TIME: float = 0.5     # sky sigil + ground telegraph
const FALL_TIME: float = 0.52      # per-meteor descent (slowed — less frantic)
const BARRAGE_TIME: float = 1.15   # window the meteors spawn across (slowed)
const FADE_TIME: float = 0.35
## Meteors streak in from just above the combat view (not far off-screen) so you
## SEE the shower coming down — readability + the "here it comes" tell.
const SKY_HEIGHT: float = 360.0
const DEFAULT_RADIUS: float = 135.0
const DEFAULT_DAMAGE: int = 22     # per meteor — many meteors overlap
const DEFAULT_COUNT: int = 10
const METEOR_IMPACT_RADIUS: float = 48.0
const KNOCKBACK: float = 240.0
const SLANT: Vector2 = Vector2(110.0, 0.0)  # meteors streak in from the upper-right

var _center: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.55, 0.2, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "fire"
var _elapsed: float = -1.0
var _circle: MagicCircle = null
var _circle_dismissed: bool = false
var _meteors: Array = []  # each: {delay, from, to, landed}
## Elemental ailment (Elements.Element) applied to enemies a meteor hits. -1=none.
var element_id: int = -1


## Public entry: open a sigil over `target` and rain `count` meteors within
## `radius`. Colour tints the shower; `effect` picks its character
## ("fire"/"frost"/"arcane"/"holy").
func rain(
	target: Vector2, color: Color, radius: float = DEFAULT_RADIUS,
	damage: int = DEFAULT_DAMAGE, count: int = DEFAULT_COUNT,
	effect: String = "fire",
) -> void:
	_center = target
	_color = color
	_radius = radius
	_damage = damage
	_effect = effect
	_elapsed = 0.0
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.global_position = _center - Vector2(0.0, SKY_HEIGHT)
	_circle.appear(_color, radius * 1.9, CHARGE_TIME * 0.85)
	for i: int in count:
		var ang: float = randf() * TAU
		var dist: float = sqrt(randf()) * radius  # sqrt -> uniform over the disc
		var to: Vector2 = _center + Vector2.from_angle(ang) * dist
		# All streak in from the same upper-right slant so it reads as a shower.
		var from: Vector2 = to + SLANT + Vector2(0.0, -SKY_HEIGHT)
		var delay: float = (float(i) / float(count)) * BARRAGE_TIME + randf_range(0.0, 0.06)
		_meteors.append({"delay": delay, "from": from, "to": to, "landed": false})
	Sfx.play("cast", -3.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	for m: Dictionary in _meteors:
		if not m["landed"] and _elapsed >= CHARGE_TIME + float(m["delay"]) + FALL_TIME:
			_land(m)
	# Dissolve the sky sigil once the barrage has all launched (matches the
	# graceful vanish beam/ray get, instead of popping when we free).
	if not _circle_dismissed and _elapsed >= CHARGE_TIME + BARRAGE_TIME:
		_circle_dismissed = true
		if _circle != null and is_instance_valid(_circle):
			_circle.vanish(FALL_TIME + FADE_TIME)
	if _elapsed >= CHARGE_TIME + BARRAGE_TIME + FALL_TIME + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## One meteor lands: radius damage + fiery burst + a light screen kick.
func _land(m: Dictionary) -> void:
	m["landed"] = true
	var at: Vector2 = m["to"]
	for enemy: Node in targets_in_radius(at, METEOR_IMPACT_RADIUS, get_tree().get_nodes_in_group("enemy")):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			enemy.apply_knockback((away if away != Vector2.ZERO else Vector2.UP) * KNOCKBACK)
	for prop: Node in targets_in_radius(at, METEOR_IMPACT_RADIUS, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	# Parented to the arena (get_parent()), not self: later meteors' bursts +
	# debris must outlive this spectacle node so they settle/fade naturally.
	_impact_burst(at)
	Juice.shake_camera(5.0)
	Sfx.play("spell_impact", 0.0, 0.1)


## One meteor's impact spray + residue, charactered per effect.
func _impact_burst(at: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	match _effect:
		"frost":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.9, 0.98, 1.0, 0.95), fade,
				22, 0.4, 120.0, 300.0, 0.6, 1.6, 2.5, 5.0, true
			)
			ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.7, "crack",
				Color(0.62, 0.88, 1.0, 0.45), 5.0)
		"arcane":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1, 1, 1, 0.95), fade,
				22, 0.4, 80.0, 240.0, 1.5, 3.5, 0.0, 0.0, true
			)
		"holy":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.99, 0.9, 0.95), fade,
				24, 0.45, 50.0, 190.0, 1.0, 2.5, 1.0, 2.0, true
			)
		"lightning":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 1.0, 0.7, 0.95), fade,
				24, 0.3, 180.0, 420.0, 0.4, 1.2, 4.0, 8.0, true
			)
		"shadow":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.7, 0.45, 1.0, 0.95), Color(0.14, 0.05, 0.3, 0.0),
				24, 0.5, 70.0, 220.0, 1.2, 3.0, 1.0, 2.5, true
			)
		"earth":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.85, 0.62, 0.35, 0.9), Color(0.4, 0.28, 0.15, 0.0),
				20, 0.45, 60.0, 210.0, 1.6, 4.2
			)
			DebrisChunk.spawn_burst(get_parent(), at, Color(0.5, 0.38, 0.22), 4, Vector2.UP, 210.0)
			ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.7, "crack",
				Color(0.6, 0.45, 0.28, 0.5), 6.0)
		"wind":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.72, 1.0, 0.92, 0.9), fade,
				22, 0.35, 170.0, 420.0, 0.6, 1.7, 2.0, 5.0, true
			)
		_:
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.95, 0.7, 0.95), fade,
				22, 0.4, 80.0, 240.0, 1.5, 3.5, 0.0, 0.0, true
			)
			DebrisChunk.spawn_burst(get_parent(), at, Color(0.35, 0.3, 0.3), 3, Vector2.UP, 180.0)
			ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.7, "scorch",
				Color(0.06, 0.03, 0.02, 0.55), 8.0)


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
		# Telegraph: a growing danger ring on the ground footprint.
		var tp: float = _elapsed / CHARGE_TIME
		draw_arc(_center, _radius * (0.4 + 0.6 * tp), 0.0, TAU, 44, Color(c.r, c.g, c.b, 0.45 * tp), 2.5, true)
		return
	# Draw each in-flight meteor: a bright head + a fading motion trail.
	for m: Dictionary in _meteors:
		if m["landed"]:
			continue
		var start_t: float = CHARGE_TIME + float(m["delay"])
		if _elapsed < start_t:
			continue
		var f: float = clampf((_elapsed - start_t) / FALL_TIME, 0.0, 1.0)
		var from: Vector2 = m["from"]
		var to: Vector2 = m["to"]
		var pos: Vector2 = from.lerp(to, f)
		var trail: Vector2 = from.lerp(to, maxf(f - 0.38, 0.0))
		var inner: Color = _trail_inner_color()
		var core: Color = _effect_core_color()
		draw_line(trail, pos, Color(c.r, c.g, c.b, 0.5), 10.0, true)        # wide soft trail
		draw_line(trail, pos, Color(inner.r, inner.g, inner.b, 0.7), 4.0, true)  # bright inner trail
		draw_circle(pos, 13.0, Color(c.r, c.g, c.b, 0.4), true, -1.0, true)            # elemental halo
		draw_circle(pos, 8.0, Color(c.r, c.g, c.b, 0.95), true, -1.0, true)           # head
		draw_circle(pos, 4.5, core, true, -1.0, true)                                 # hot core


## Bright inner-trail tint per effect.
func _trail_inner_color() -> Color:
	match _effect:
		"frost":
			return Color(0.85, 0.97, 1.0)
		"arcane":
			return Color(1.0, 0.85, 1.0)
		"holy":
			return Color(1.0, 0.99, 0.85)
		"lightning":
			return Color(1.0, 1.0, 0.75)
		"shadow":
			return Color(0.8, 0.55, 1.0)
		"earth":
			return Color(0.9, 0.72, 0.45)
		"wind":
			return Color(0.8, 1.0, 0.95)
		_:
			return Color(1.0, 0.9, 0.6)


## Hot-core tint per effect (the white-hot centre of each meteor head).
func _effect_core_color() -> Color:
	match _effect:
		"frost":
			return Color(1.5, 1.6, 1.7, 1.0)  # HDR cores bloom
		"arcane":
			return Color(1.7, 1.5, 1.7, 1.0)
		"holy":
			return Color(1.75, 1.75, 1.5, 1.0)
		"lightning":
			return Color(1.9, 1.7, 0.9, 1.0)
		"shadow":
			return Color(1.5, 1.0, 1.9, 1.0)
		"earth":
			return Color(1.7, 1.35, 0.85, 1.0)
		"wind":
			return Color(1.35, 1.85, 1.7, 1.0)
		_:
			return Color(1.8, 1.6, 1.2, 1.0)
