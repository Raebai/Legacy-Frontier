class_name DivineRay
extends Node2D
## Signature spectacle #2 — DIVINE RAY / JUDGEMENT. A holy sigil opens in the
## sky and a ROW of towering PILLARS OF LIGHT crashes down across the WHOLE
## horizontal row at the target's Y — not a single point where you clicked, but
## a left-to-right sweep of smiting columns spanning the width of the arena.
## Each pillar is a white-hot core in a radiant column, a blinding ground flash
## and an expanding ring, with heavy juice. The row read makes it a wall of
## judgement from the sky rather than a single spotlight.
##
## The trailing `effect` param picks the elemental CHARACTER
## ("holy" | "frost" | "fire" | "arcane") — same pillar silhouette, distinct
## palette + impact, so it reads different at a glance.
##
## Each pillar deals radius damage on its ground footprint (targets_in_radius,
## pure/testable); strike() drives the timeline. Instantiate .new(), add to the
## arena, call strike().

const CHARGE_TIME: float = 0.42   # sky sigil + ground telegraph
const STRIKE_TIME: float = 0.34   # window the row of pillars sweeps across
const PILLAR_HOLD: float = 0.16   # each pillar held at full brightness
const FADE_TIME: float = 0.30
const SKY_HEIGHT: float = 560.0   # how far above the ground the sigil hangs
const DEFAULT_RADIUS: float = 90.0
const DEFAULT_DAMAGE: int = 52
const KNOCKBACK: float = 300.0
const ROW_SPACING: float = 110.0    # px between pillars along the row
const ROW_HALF_SPAN: float = 650.0  # pillars span ±this around the target x

var _ground: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.92, 0.55, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "holy"
var _elapsed: float = -1.0
var _circle: MagicCircle = null
## Each pillar: {"x": float, "delay": float, "struck": bool}. All share the
## target Y (_ground.y); delay staggers them left-to-right for the sweep read.
var _pillars: Array = []
var _row_min_x: float = 0.0
var _row_max_x: float = 0.0
## Elemental ailment (Elements.Element) applied to enemies a pillar hits. -1=none.
var element_id: int = -1


## Public entry: smite the WHOLE horizontal row at `target`'s Y with a swept
## wall of pillars, each dealing `damage` over `radius`. Colour tints the
## spectacle; `effect` picks its character ("holy"/"frost"/"fire"/"arcane").
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
	# Build the row of pillars: evenly spaced across ±ROW_HALF_SPAN of the
	# target x, all at the target Y, delay-staggered left-to-right for the sweep.
	var count: int = int(floor((ROW_HALF_SPAN * 2.0) / ROW_SPACING)) + 1
	_row_min_x = target.x - ROW_HALF_SPAN
	_row_max_x = target.x + ROW_HALF_SPAN
	for i: int in count:
		var px: float = _row_min_x + float(i) * ROW_SPACING
		var sweep: float = float(i) / float(maxi(count - 1, 1))
		_pillars.append({"x": px, "delay": sweep * STRIKE_TIME, "struck": false})
	# The sky sigil hangs over the target column, oversized so it feels like it
	# presides over the whole row.
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.global_position = _ground - Vector2(0.0, SKY_HEIGHT)
	_circle.appear(_color, _radius * 2.6, CHARGE_TIME * 0.85)
	# EDGE-ON along the vertical pillars: side-on, the sky sigil reads as a thin
	# horizontal gate the columns of light drop through.
	_circle.set_orientation(true, Vector2.DOWN, 0.16)
	Sfx.play("cast", -4.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	var since: float = _elapsed - CHARGE_TIME
	if since >= 0.0:
		for m: Dictionary in _pillars:
			if not m["struck"] and since >= float(m["delay"]):
				_smite_pillar(m)
	# Dissolve the sky sigil once the row has finished sweeping (vanish() is
	# idempotent — it self-guards against being started twice).
	if _circle != null and is_instance_valid(_circle) \
			and _elapsed >= CHARGE_TIME + STRIKE_TIME:
		_circle.vanish(PILLAR_HOLD + FADE_TIME)
	if _elapsed >= CHARGE_TIME + STRIKE_TIME + PILLAR_HOLD + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## One pillar of the row lands: radius damage once at its footprint, impact
## spray + mark, and a screen kick scaled down per-pillar (so the whole row
## doesn't nuke the camera). The central pillars kick hardest.
func _smite_pillar(m: Dictionary) -> void:
	m["struck"] = true
	var at: Vector2 = Vector2(float(m["x"]), _ground.y)
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
	# Parented to the arena (get_parent()), not self: bursts outlive this
	# short-lived spectacle node so they fade naturally after we free.
	_impact_burst(at)
	_impact_mark(at)
	# Central pillars (near the target x) shake hardest; the flanks are lighter.
	var closeness: float = 1.0 - clampf(absf(at.x - _ground.x) / ROW_HALF_SPAN, 0.0, 1.0)
	Juice.shake_camera(4.0 + 8.0 * closeness)
	if closeness > 0.85:
		Juice.hit_stop(0.08)
		Juice.zoom_punch_camera(0.08, 0.22)
	Sfx.play("blast", -2.0 + 2.0 * closeness, 0.08)


## Impact spray at a pillar's footprint, charactered per effect.
func _impact_burst(at: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	match _effect:
		"frost":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(0.9, 0.98, 1.0, 0.96), fade,
				34, 0.5, 150.0, 360.0, 0.7, 1.8, 3.0, 6.0
			)
		"fire":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.85, 0.4, 0.95), Color(0.85, 0.15, 0.05, 0.0),
				38, 0.55, 90.0, 300.0, 1.5, 4.5
			)
			DebrisChunk.spawn_burst(get_parent(), at, Color(0.55, 0.25, 0.1), 3, Vector2.UP, 190.0)
		"arcane":
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1, 1, 1, 0.96), fade,
				40, 0.5, 100.0, 320.0, 1.4, 4.0
			)
		_:
			CombatVfx.spawn_burst(
				get_parent(), at, Color(1.0, 0.99, 0.9, 0.98), fade,
				44, 0.6, 70.0, 260.0, 1.0, 3.0, 1.0, 2.5
			)


## Lingering ground mark under a pillar: frost cracks the ground with ice, fire
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
		# Telegraph: a bright line across the WHOLE row + a growing ring at each
		# pillar footprint, so the player reads "the whole row is coming".
		var tp: float = _elapsed / CHARGE_TIME
		draw_line(Vector2(_row_min_x, _ground.y), Vector2(_row_max_x, _ground.y),
			Color(c.r, c.g, c.b, 0.35 * tp), 2.0)
		for m: Dictionary in _pillars:
			var px: float = float(m["x"])
			var rr: float = _radius * (0.3 + 0.6 * tp)
			draw_arc(Vector2(px, _ground.y), rr, 0.0, TAU, 28, Color(c.r, c.g, c.b, 0.4 * tp), 2.0)
		return
	# Each pillar draws with its own intensity envelope keyed off its strike time.
	var since: float = _elapsed - CHARGE_TIME
	var core: Color = _effect_core_color()
	for m: Dictionary in _pillars:
		var local: float = since - float(m["delay"])
		if local < 0.0:
			continue
		var intensity: float
		if local < PILLAR_HOLD:
			intensity = 1.0 if local > 0.04 else local / 0.04
		else:
			intensity = clampf(1.0 - (local - PILLAR_HOLD) / FADE_TIME, 0.0, 1.0)
		if intensity <= 0.01:
			continue
		_draw_pillar(float(m["x"]), sky_y, c, core, intensity)


## Draw one column of light at ground x `px`, from `sky_y` down to the ground.
func _draw_pillar(px: float, sky_y: float, c: Color, core: Color, intensity: float) -> void:
	var flick: float = _effect_flicker()
	var w: float = _radius * 0.9 * intensity * flick
	var sky: Vector2 = Vector2(px, sky_y)
	var ground: Vector2 = Vector2(px, _ground.y)
	if _effect == "holy":
		# Extra-wide feathery halo — holy reads as radiance, not a laser.
		_draw_column(sky, ground, w * 2.6, Color(c.r, c.g, c.b, 0.1 * intensity))
	_draw_column(sky, ground, w * 1.7, Color(c.r, c.g, c.b, 0.25 * intensity))
	_draw_column(sky, ground, w * 1.0, Color(c.r, c.g, c.b, 0.65 * intensity))
	_draw_column(sky, ground, w * 0.4, Color(core.r, core.g, core.b, 0.95 * intensity))
	_draw_effect_detail(sky, ground, w, intensity)
	# Ground impact: bright flash disc + an expanding ring.
	draw_circle(ground, w * 1.5, Color(core.r, core.g, core.b, 0.5 * intensity))
	var ring_r: float = _radius * (1.0 + 1.4 * (1.0 - intensity))
	draw_arc(ground, ring_r, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.6 * intensity), 4.0 * intensity)


## Column flicker character (matches BeamSpell): frost steady/cold, fire rages,
## holy breathes slowly, arcane keeps a subtle energy flicker.
func _effect_flicker() -> float:
	match _effect:
		"frost":
			return 1.0
		"fire":
			return 0.8 + 0.2 * sin(_elapsed * 85.0)
		"arcane":
			return 0.9 + 0.1 * sin(_elapsed * 60.0)
		_:
			return 0.94 + 0.06 * sin(_elapsed * 28.0)


## Hot-core tint per effect (innermost band + ground flash).
func _effect_core_color() -> Color:
	match _effect:
		"frost":
			return Color(0.9, 0.98, 1.0)
		"fire":
			return Color(1.0, 0.93, 0.62)
		"arcane":
			return Color(1, 1, 1)
		_:
			return Color(1.0, 0.98, 0.88)


## Per-effect garnish drawn along a column so each element is unmistakable:
## frost = crystalline shards jutting off the column, fire = drifting embers,
## holy = bobbing feathery motes. Arcane stays the clean column.
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
					Color(1.0, 0.55 + 0.3 * absf(sin(float(i) * 3.7)), 0.15, 0.8 * intensity))
		"holy":
			for i: int in 7:
				var t: float = (float(i) + 0.5) / 7.0
				var p: Vector2 = sky.lerp(ground, t) \
					+ Vector2(sin(_elapsed * 6.0 + float(i) * 1.7) * w * 1.3, 0.0)
				var ma: float = (0.35 + 0.25 * sin(_elapsed * 9.0 + float(i))) * intensity
				draw_circle(p, w * 0.4, Color(1.0, 0.97, 0.8, ma * 0.5))
				draw_circle(p, w * 0.16, Color(1.0, 1.0, 0.95, ma))


## A vertical band of thickness `thick` from `sky` down to `ground`.
func _draw_column(sky: Vector2, ground: Vector2, thick: float, col: Color) -> void:
	var half: Vector2 = Vector2(thick * 0.5, 0.0)
	draw_colored_polygon(
		PackedVector2Array([sky - half, sky + half, ground + half, ground - half]), col
	)
