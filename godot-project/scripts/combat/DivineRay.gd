class_name DivineRay
extends Node2D
## Signature spectacle #2 — JUDGMENT. A holy sigil opens in the sky and a SINGLE
## towering pillar of light crashes down on the ONE point you mark — a precise,
## high-commitment single-target smite (dodge the tell or eat a heavy hit), NOT a
## whole-row room-wipe. Radius damage on the pillar footprint (targets_in_radius,
## pure/testable); strike() drives the timeline. Instantiate .new(), add to the
## arena, call strike().
##
## The trailing `effect` param picks the elemental CHARACTER
## ("holy" | "frost" | "fire" | "arcane") — same pillar silhouette, distinct
## palette + impact, so it reads different at a glance.

const CHARGE_TIME: float = 0.42   # sky sigil + ground telegraph
const PILLAR_HOLD: float = 0.18   # the pillar held at full brightness
const FADE_TIME: float = 0.30
const SKY_HEIGHT: float = 560.0   # how far above the ground the sigil hangs
const DEFAULT_RADIUS: float = 70.0
const DEFAULT_DAMAGE: int = 95
const KNOCKBACK: float = 320.0

var _ground: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.92, 0.55, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "holy"
var _elapsed: float = -1.0
var _struck: bool = false
var _circle: MagicCircle = null
## Elemental ailment (Elements.Element) applied to enemies the pillar hits. -1=none.
var element_id: int = -1


## Public entry: smite the single point `target` with a pillar dealing `damage`
## over `radius`. Colour tints the spectacle; `effect` picks its character.
func strike(
	target: Vector2, color: Color = Color(1.0, 0.92, 0.55),
	radius: float = DEFAULT_RADIUS, damage: int = DEFAULT_DAMAGE,
	effect: String = "holy",
) -> void:
	_ground = target
	_color = color
	_radius = radius
	_damage = damage
	_effect = effect
	_elapsed = 0.0
	# The sky sigil hangs over the strike column, oversized so it presides over it.
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.global_position = _ground - Vector2(0.0, SKY_HEIGHT)
	_circle.appear(_color, _radius * 2.6, CHARGE_TIME * 0.85)
	# EDGE-ON along the vertical pillar: the sky sigil reads as a thin horizontal
	# gate the column of light drops through.
	_circle.set_orientation(true, Vector2.DOWN, 0.16)
	Sfx.play("cast", -4.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if not _struck and _elapsed >= CHARGE_TIME:
		_smite()
	if _circle != null and is_instance_valid(_circle) and _elapsed >= CHARGE_TIME:
		_circle.vanish(PILLAR_HOLD + FADE_TIME)  # idempotent
	if _elapsed >= CHARGE_TIME + PILLAR_HOLD + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## The pillar lands: radius damage once at the marked point, impact spray + mark,
## and a heavy screen kick (Judgment is a big single-target hit).
func _smite() -> void:
	_struck = true
	var at: Vector2 = _ground
	for enemy: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group("enemy")):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var away: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			enemy.apply_knockback((away if away != Vector2.ZERO else Vector2.UP) * KNOCKBACK)
	for prop: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)
	_impact_burst(at)
	_impact_mark(at)
	Juice.hit_stop(0.09)
	Juice.shake_camera(14.0)
	Juice.zoom_punch_camera(0.09, 0.24)
	Sfx.play("blast", 0.0, 0.08)


## Impact spray at the footprint, charactered per effect.
func _impact_burst(at: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	match _effect:
		"frost":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.9, 0.98, 1.0, 0.96), fade,
				34, 0.5, 150.0, 360.0, 0.7, 1.8, 3.0, 6.0, true
			)
		"fire":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.85, 0.4, 0.95), Color(0.85, 0.15, 0.05, 0.0),
				38, 0.55, 90.0, 300.0, 1.5, 4.5, 0.0, 0.0, true
			)
			DebrisChunk.spawn_burst(get_parent(), at, Color(0.55, 0.25, 0.1), 3, Vector2.UP, 190.0)
		"arcane":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1, 1, 1, 0.96), fade,
				40, 0.5, 100.0, 320.0, 1.4, 4.0, 0.0, 0.0, true
			)
		"lightning":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 1.0, 0.7, 0.96), fade,
				38, 0.34, 200.0, 480.0, 0.4, 1.3, 4.0, 8.0, true
			)
		"shadow":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.7, 0.45, 1.0, 0.96), Color(0.14, 0.05, 0.3, 0.0),
				40, 0.6, 80.0, 240.0, 1.2, 3.2, 1.0, 2.5, true
			)
		"earth":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.85, 0.62, 0.35, 0.9), Color(0.4, 0.28, 0.15, 0.0),
				28, 0.5, 60.0, 220.0, 1.6, 4.5
			)
			DebrisChunk.spawn_burst(get_parent(), at, Color(0.5, 0.38, 0.22), 5, Vector2.UP, 220.0)
		"wind":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.72, 1.0, 0.92, 0.9), fade,
				36, 0.4, 190.0, 460.0, 0.6, 1.8, 2.0, 5.0, true
			)
		_:
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.99, 0.9, 0.98), fade,
				44, 0.6, 70.0, 260.0, 1.0, 3.0, 1.0, 2.5, true
			)


## Lingering ground mark under the pillar: frost cracks the ground with ice, fire
## scorches it. Holy/arcane leave no residue (pure light/energy).
func _impact_mark(at: Vector2) -> void:
	match _effect:
		"frost":
			ScorchDecal.spawn(
				get_parent(), at, _radius * 0.5, "crack",
				Color(0.62, 0.88, 1.0, 0.5), 6.0
			)
		"fire":
			ScorchDecal.spawn(
				get_parent(), at, _radius * 0.5, "scorch",
				Color(0.06, 0.03, 0.02, 0.6), 8.0
			)


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
	var sky_y: float = _ground.y - SKY_HEIGHT
	if _elapsed < CHARGE_TIME:
		# Telegraph: a single growing danger ring at the marked point (no full-row
		# line — that whole-map tell is exactly what the maker wanted gone).
		var tp: float = _elapsed / CHARGE_TIME
		draw_arc(_ground, _radius * (0.3 + 0.6 * tp), 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.45 * tp), 2.5, true)
		return
	var local: float = _elapsed - CHARGE_TIME
	var intensity: float
	if local < PILLAR_HOLD:
		intensity = 1.0 if local > 0.04 else local / 0.04
	else:
		intensity = clampf(1.0 - (local - PILLAR_HOLD) / FADE_TIME, 0.0, 1.0)
	if intensity <= 0.01:
		return
	_draw_pillar(_ground.x, sky_y, c, _effect_core_color(), intensity)


## Draw the column of light at ground x `px`, from `sky_y` down to the ground.
func _draw_pillar(px: float, sky_y: float, c: Color, core: Color, intensity: float) -> void:
	var flick: float = _effect_flicker()
	var w: float = _radius * 0.9 * intensity * flick
	var sky: Vector2 = Vector2(px, sky_y)
	var ground: Vector2 = Vector2(px, _ground.y)
	if _effect == "holy":
		_draw_column(sky, ground, w * 2.6, Color(c.r, c.g, c.b, 0.1 * intensity))
	_draw_column(sky, ground, w * 1.7, Color(c.r, c.g, c.b, 0.25 * intensity))
	_draw_column(sky, ground, w * 1.0, Color(c.r, c.g, c.b, 0.65 * intensity))
	# Bright core as a thick AA line (clean round-profile edges) instead of a
	# flat aliased quad; the soft outer bands stay polygons (no below-ground cap
	# bulge, MSAA is fine for their low alpha).
	draw_line(sky, ground, Color(core.r, core.g, core.b, 0.95 * intensity), w * 0.4, true)
	_draw_effect_detail(sky, ground, w, intensity)
	# Ground impact: bright flash disc + an expanding ring.
	draw_circle(ground, w * 1.5, Color(core.r, core.g, core.b, 0.5 * intensity), true, -1.0, true)
	var ring_r: float = _radius * (1.0 + 1.4 * (1.0 - intensity))
	draw_arc(ground, ring_r, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.6 * intensity), 4.0 * intensity, true)


func _effect_flicker() -> float:
	match _effect:
		"frost":
			return 1.0
		"fire":
			return 0.8 + 0.2 * sin(_elapsed * 85.0)
		"arcane":
			return 0.9 + 0.1 * sin(_elapsed * 60.0)
		"lightning":
			return 0.6 + 0.4 * sin(_elapsed * 95.0)
		"shadow":
			return 0.82 + 0.18 * sin(_elapsed * 18.0)
		"earth":
			return 1.0
		"wind":
			return 0.88 + 0.12 * sin(_elapsed * 70.0)
		_:
			return 0.94 + 0.06 * sin(_elapsed * 28.0)


func _effect_core_color() -> Color:
	match _effect:
		"frost":
			return Color(1.4, 1.5, 1.7)  # HDR cores bloom
		"fire":
			return Color(1.8, 1.55, 1.0)
		"arcane":
			return Color(1.6, 1.6, 1.7)
		"lightning":
			return Color(1.9, 1.7, 0.9)
		"shadow":
			return Color(1.5, 1.0, 1.9)
		"earth":
			return Color(1.7, 1.35, 0.85)
		"wind":
			return Color(1.35, 1.85, 1.7)
		_:
			return Color(1.85, 1.75, 1.45)


## Per-effect garnish drawn along the column so each element is unmistakable.
func _draw_effect_detail(sky: Vector2, ground: Vector2, w: float, intensity: float) -> void:
	match _effect:
		"frost":
			for i: int in 6:
				var t: float = (float(i) + 0.7) / 6.5
				var p: Vector2 = sky.lerp(ground, t)
				var side: float = 1.0 if i % 2 == 0 else -1.0
				var reach: float = w * (1.2 + 0.5 * absf(sin(float(i) * 12.9898)))
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(0.0, -w * 0.35), p + Vector2(0.0, w * 0.35),
					p + Vector2(side * reach, 0.0),
				]), Color(0.85, 0.97, 1.0, 0.7 * intensity))
		"fire":
			for i: int in 8:
				var t: float = fposmod(float(i) / 8.0 - _elapsed * 1.1 + sin(float(i) * 7.31) * 0.05, 1.0)
				var p: Vector2 = sky.lerp(ground, t) \
					+ Vector2(sin(_elapsed * 14.0 + float(i) * 2.1) * w * 1.1, 0.0)
				draw_circle(p, w * 0.16 + 1.5,
					Color(1.0, 0.55 + 0.3 * absf(sin(float(i) * 3.7)), 0.15, 0.8 * intensity), true, -1.0, true)
		"holy":
			for i: int in 7:
				var t: float = (float(i) + 0.5) / 7.0
				var p: Vector2 = sky.lerp(ground, t) \
					+ Vector2(sin(_elapsed * 6.0 + float(i) * 1.7) * w * 1.3, 0.0)
				var ma: float = (0.35 + 0.25 * sin(_elapsed * 9.0 + float(i))) * intensity
				draw_circle(p, w * 0.4, Color(1.0, 0.97, 0.8, ma * 0.5), true, -1.0, true)
				draw_circle(p, w * 0.16, Color(1.0, 1.0, 0.95, ma), true, -1.0, true)


## A vertical band of thickness `thick` from `sky` down to `ground`.
func _draw_column(sky: Vector2, ground: Vector2, thick: float, col: Color) -> void:
	var half: Vector2 = Vector2(thick * 0.5, 0.0)
	draw_colored_polygon(
		PackedVector2Array([sky - half, sky + half, ground + half, ground - half]), col
	)
