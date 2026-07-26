class_name DivineRay
extends Node2D

## Who this ray's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## Signature spectacle #2 — JUDGMENT. A holy sigil opens in the sky and a SINGLE
## towering pillar of light crashes down on the ONE point you mark — a precise,
## high-commitment single-target smite (dodge the tell or eat a heavy hit), NOT a
## whole-row room-wipe. Radius damage on the pillar footprint (targets_in_radius,
## pure/testable); strike() drives the timeline. Instantiate .new(), add to the
## arena, call strike().
##
## The trailing `effect` param picks the elemental CHARACTER
## ("holy" | "frost" | "fire" | "arcane" | ...) — same pillar silhouette,
## distinct palette + impact, so it reads different at a glance.
##
## EXCEPTION — "earth" (Colossus Pillar): not a light column at all. It runs a
## separate stone-eruption timeline: fissures crack outward + the ground heaves
## (long telegraph), then a titanic slate spire ERUPTS from below with dust,
## debris and a heavy landing thump, holds as area denial, then crumbles.

const CHARGE_TIME: float = 0.42   # sky sigil + ground telegraph
const PILLAR_HOLD: float = 0.18   # the pillar held at full brightness
const FADE_TIME: float = 0.30
const SKY_HEIGHT: float = 560.0   # how far above the ground the sigil hangs
const DEFAULT_RADIUS: float = 70.0
const DEFAULT_DAMAGE: int = 95
const KNOCKBACK: float = 320.0

# ── COLOSSUS PILLAR / stone mode ("earth" effect) ────────────────────────────
# The "earth" character is not a tinted light column — it is GEOLOGY: fissures
# spread, the ground heaves, then a titanic slate spire erupts UP out of the
# dirt. Deliberately the OPPOSITE of RockPillar's fast uppercut fang: slow tell
# (rule 2 — real reaction window), vast multi-slab mass, long area-denying hold.
const STONE_CHARGE: float = 0.85   # the dodge window — over 2x Judgment's tell
const STONE_RISE: float = 0.18
const STONE_HOLD: float = 0.60     # lingers (area denial) vs Judgment's 0.18 flash
const STONE_CRUMBLE: float = 0.45
const STONE_HEIGHT: float = 300.0  # 2x the RockPillar uppercut spike
const STONE_SLABS: int = 7
const STONE_CRACKS: int = 9
# Cold slate palette so the colossus cannot be mistaken for RockPillar's warm
# brown fang or for any light column. RIM is HDR (>1.0) so fresh fracture
# faces bloom like hot mineral seams.
const STONE_BODY: Color = Color(0.40, 0.36, 0.30)
const STONE_FACE: Color = Color(0.52, 0.46, 0.37)   # lit left facet — strata read as rock
const STONE_LIT: Color = Color(0.68, 0.60, 0.47)
const STONE_RIM: Color = Color(1.22, 1.06, 0.84)    # HDR mineral seam (subtle bloom, not wire)
const STONE_SEAM: Color = Color(0.15, 0.13, 0.10)
const STONE_DUST: Color = Color(0.62, 0.52, 0.38)

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

# Stone-mode state (Colossus Pillar). Crack fan + slab jitter are seeded once in
# strike() so per-frame redraws don't shimmer.
var _stone: bool = false
var _rumble_accum: float = 0.0
var _crack_angles: PackedFloat32Array = PackedFloat32Array()
var _crack_lens: PackedFloat32Array = PackedFloat32Array()
var _slab_jitter: PackedFloat32Array = PackedFloat32Array()


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
	# FORCED-HOLY FIX (magic-overhaul phase 2): SpellLibrary._ray() hardcodes
	# effect="holy" on every DIVINE_RAY def and _colossus_pillar() never
	# overrides it, so the "titanic stone spire" arrived here as a brown-tinted
	# holy light column. The spell's EARTH identity DOES survive in element_id
	# (SpellCaster sets it before calling strike()), so reinterpret holy+EARTH
	# as stone. Judgment (holy, LIGHTNING ailment) and the Boss's fire rays are
	# untouched; if SpellLibrary later passes "earth" directly this is a no-op.
	if _effect == "holy" and element_id == Elements.Element.EARTH:
		_effect = "earth"
	_stone = _effect == "earth"
	_elapsed = 0.0
	if _stone:
		# Geology, not sky magic: no heaven sigil, no radiant chord. Seed the
		# deterministic crack fan + slab jitter once (redraws must not shimmer).
		for i: int in STONE_CRACKS:
			_crack_angles.append(TAU * (float(i) + randf_range(-0.3, 0.3)) / float(STONE_CRACKS))
			_crack_lens.append(randf_range(0.7, 1.25))
		for i: int in STONE_SLABS + 2:
			_slab_jitter.append(randf_range(-0.3, 0.3))
		Sfx.play("earth", -4.0, 0.08)  # the ground starts to groan
		Juice.shake_camera(3.0)
		queue_redraw()
		return
	# The sky sigil hangs over the strike column, oversized so it presides over it.
	_circle = MagicCircle.new()
	add_child(_circle)
	_circle.global_position = _ground - Vector2(0.0, SKY_HEIGHT)
	_circle.appear(_color, _radius * 2.6, CHARGE_TIME * 0.85)
	# EDGE-ON along the vertical pillar: the sky sigil reads as a thin horizontal
	# gate the column of light drops through.
	_circle.set_orientation(true, Vector2.DOWN, 0.16)
	Sfx.play("holy", -5.0, 0.05)  # radiant chord as the seal opens
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	var done: bool = _stone_step(delta) if _stone else _light_step()
	if done:
		queue_free()
		return
	queue_redraw()


## Light-column timeline (Judgment + every non-earth effect). Returns true when
## the spectacle is finished and the node should free.
func _light_step() -> bool:
	if not _struck and _elapsed >= CHARGE_TIME:
		_smite()
	if _circle != null and is_instance_valid(_circle) and _elapsed >= CHARGE_TIME:
		_circle.vanish(PILLAR_HOLD + FADE_TIME)  # idempotent
	return _elapsed >= CHARGE_TIME + PILLAR_HOLD + FADE_TIME


## Stone-eruption timeline (Colossus Pillar): rumbling telegraph, one heavy
## eruption, an area-denying hold shedding rubble, then crumble. Returns true
## when finished.
func _stone_step(delta: float) -> bool:
	if _elapsed < STONE_CHARGE:
		# Escalating rumble: shakes + dirt puffs come faster and harder as the
		# eruption nears, so the tell reads with peripheral vision too.
		_rumble_accum += delta
		var late: bool = _elapsed > STONE_CHARGE * 0.55
		if _rumble_accum >= (0.08 if late else 0.14):
			_rumble_accum = 0.0
			Juice.shake_camera(3.5 if late else 1.8)
			CombatVfx.spawn_burst(
				get_parent(), _ground + Vector2(randf_range(-0.6, 0.6) * _radius, 0.0),
				Color(0.7, 0.58, 0.4, 0.55), Color(0.4, 0.32, 0.2, 0.0),
				5 if late else 3, 0.4, 30.0, 100.0, 1.2, 3.0
			)
		return false
	if not _struck:
		_erupt_stone()
	var total: float = STONE_CHARGE + STONE_RISE + STONE_HOLD + STONE_CRUMBLE
	if _elapsed >= STONE_CHARGE + STONE_RISE + STONE_HOLD and _elapsed < total:
		# Crumble: shed rubble in staggered pops as the spire collapses.
		if fmod(_elapsed, 0.11) < delta:
			DebrisChunk.spawn_burst(
				get_parent(), _ground - Vector2(0.0, STONE_HEIGHT * 0.45),
				Color(0.42, 0.37, 0.30), 5, Vector2.ZERO, 200.0
			)
	if _elapsed >= total:
		# The eruption leaves a permanent-feeling scar, not a scorch.
		ScorchDecal.spawn(
			get_parent(), _ground, _radius * 0.6, "crack",
			Color(0.5, 0.45, 0.38, 0.55), 8.0
		)
		return true
	return false


## The colossus lands: same damage/status/knockback contract as _smite(), but
## the spectacle is geological — grit ring, hanging dust, debris, a gouged
## crater and a deep pitched-down thump (a mountain landing, not artillery).
func _erupt_stone() -> void:
	_struck = true
	var at: Vector2 = _ground
	for enemy: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group(target_group)):
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
	# Fast grit blasting outward at the base + slow dust that HANGS in the air.
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.85, 0.72, 0.5, 0.95), Color(0.4, 0.33, 0.22, 0.0),
		40, 0.6, 120.0, 340.0, 1.8, 5.0
	)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.62, 0.52, 0.38, 0.6), Color(0.5, 0.42, 0.3, 0.0),
		26, 0.9, 40.0, 130.0, 3.0, 7.0
	)
	DebrisChunk.spawn_burst(get_parent(), at, Color(0.42, 0.37, 0.30), 14, Vector2.UP, 320.0)
	GroundCrater.spawn(get_parent(), at, _radius * 0.7, true)
	Juice.hit_stop(0.11)
	Juice.shake_camera(18.0)
	Juice.zoom_punch_camera(0.10, 0.26)
	PostProcess.shock(0.6)  # the whole screen feels the mass land
	Sfx.play("cannon", 1.0, 0.05, 0.72)  # pitched DOWN — heavy landing thump
	Sfx.play("earth", -1.0, 0.06)


## The pillar lands: radius damage once at the marked point, impact spray + mark,
## and a heavy screen kick (Judgment is a big single-target hit).
func _smite() -> void:
	_struck = true
	var at: Vector2 = _ground
	for enemy: Node in targets_in_radius(at, _radius, get_tree().get_nodes_in_group(target_group)):
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
	PostProcess.shock(0.55)  # the pillar-slam ripples the screen
	Sfx.play("cannon", 0.0, 0.06)  # the pillar slams down


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
	# The pillar crashing down GOUGES the ground (was scorch-only) — snapped to floor.
	GroundCrater.spawn(get_parent(), at, _radius * 0.6, true)


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
	if _stone:
		_draw_stone()
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


# ── Colossus Pillar (stone mode) rendering ───────────────────────────────────


func _draw_stone() -> void:
	if _elapsed < STONE_CHARGE:
		_draw_stone_telegraph(_elapsed / STONE_CHARGE)
		return
	var local: float = _elapsed - STONE_CHARGE
	var rise_t: float = clampf(local / STONE_RISE, 0.0, 1.0)
	var alpha: float = 1.0
	if local >= STONE_RISE + STONE_HOLD:
		alpha = clampf(1.0 - (local - STONE_RISE - STONE_HOLD) / STONE_CRUMBLE, 0.0, 1.0)
	if alpha <= 0.01:
		return
	# Ease-out rise: the mass decelerates as it locks into place.
	var h: float = STONE_HEIGHT * (1.0 - pow(1.0 - rise_t, 3.0))
	if h <= 2.0:
		return
	# Dust skirt widens slightly as the spire crumbles (settling cloud).
	var skirt: float = _radius * (0.9 + 0.3 * (1.0 - alpha))
	draw_circle(_ground, skirt, Color(STONE_DUST.r, STONE_DUST.g, STONE_DUST.b, 0.26 * alpha), true, -1.0, true)
	# Flanking shards erupt a beat late and lean OUTWARD — the multi-slab
	# cluster silhouette RockPillar's single fang never has.
	var side_t: float = clampf((local - 0.05) / STONE_RISE, 0.0, 1.0)
	var sh: float = STONE_HEIGHT * (1.0 - pow(1.0 - side_t, 3.0))
	if sh > 2.0:
		_draw_stone_shard(Vector2(_ground.x - _radius * 0.58, _ground.y), sh * 0.5, _radius * 0.34, -0.38, alpha, 7)
		_draw_stone_shard(Vector2(_ground.x + _radius * 0.62, _ground.y), sh * 0.62, _radius * 0.40, 0.32, alpha, 8)
	_draw_stone_spire(h, alpha)
	_draw_stone_rubble(alpha)


## Telegraph (the dodge window): a danger ring in the game's tell grammar, a
## fan of jagged fissures crawling outward, a heaving mound, and — in the last
## 40% — molten HDR light leaking up through the cracks (pressure building).
func _draw_stone_telegraph(tp: float) -> void:
	var c: Color = _color
	draw_arc(
		_ground, _radius * (0.35 + 0.65 * tp), 0.0, TAU, 40,
		Color(c.r, c.g, c.b, 0.5 * tp), 3.0, true
	)
	for i: int in STONE_CRACKS:
		var dirv: Vector2 = Vector2.from_angle(_crack_angles[i])
		var reach: float = _radius * _crack_lens[i] * tp
		if reach < 4.0:
			continue
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var p0: Vector2 = _ground + dirv * _radius * 0.08
		var mid: Vector2 = _ground + dirv * reach * 0.55 \
			+ Vector2(-dirv.y, dirv.x) * reach * 0.16 * side
		var p1: Vector2 = _ground + dirv * reach
		draw_line(p0, mid, Color(STONE_SEAM.r, STONE_SEAM.g, STONE_SEAM.b, 0.8 * tp), 2.6, true)
		draw_line(mid, p1, Color(STONE_SEAM.r, STONE_SEAM.g, STONE_SEAM.b, 0.65 * tp), 1.8, true)
		if tp > 0.6:
			var glow: float = (tp - 0.6) * 2.5
			draw_line(p0, mid, Color(1.55, 1.1, 0.45, 0.55 * glow), 1.1, true)
	# The ground swells upward — mass is coming.
	var bulge: float = 12.0 * tp * tp
	if bulge > 1.0:
		draw_colored_polygon(PackedVector2Array([
			_ground + Vector2(-_radius * 0.5, 0.0),
			_ground + Vector2(-_radius * 0.22, -bulge),
			_ground + Vector2(_radius * 0.05, -bulge * 1.15),
			_ground + Vector2(_radius * 0.3, -bulge * 0.7),
			_ground + Vector2(_radius * 0.5, 0.0),
		]), Color(0.42, 0.36, 0.28, 0.55 * tp))


## The central titan: stacked jagged slabs tapering to a crown. Each slab gets
## a lit top edge, an HDR rim on the sun side and a dark seam below — the same
## fracture grammar as RockPillar but at twice the scale and in cold slate.
func _draw_stone_spire(height: float, alpha: float) -> void:
	var base_w: float = _radius * 0.95
	var slab_h: float = height / float(STONE_SLABS)
	for i: int in STONE_SLABS:
		var f0: float = float(i) / float(STONE_SLABS)
		var f1: float = float(i + 1) / float(STONE_SLABS)
		var w0: float = base_w * (1.0 - 0.62 * f0)
		var w1: float = base_w * (1.0 - 0.62 * f1)
		var jx: float = _slab_jitter[i] * base_w * 0.3
		var y0: float = _ground.y - height * f0
		var y1: float = _ground.y - height * f1
		var cx: float = _ground.x + jx
		var verts := PackedVector2Array([
			Vector2(cx - w0 * 0.5, y0), Vector2(cx - w1 * 0.5 - 2.0, y1),
			Vector2(cx + w1 * 0.5 + 1.0, y1), Vector2(cx + w0 * 0.55, y0),
		])
		draw_colored_polygon(verts, Color(STONE_BODY.r, STONE_BODY.g, STONE_BODY.b, alpha))
		# Lit LEFT facet: without a second tone the slabs collapse into one dark
		# silhouette and the spire reads as edges, not rock faces.
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - w0 * 0.5, y0), Vector2(cx - w1 * 0.5 - 2.0, y1),
			Vector2(cx - w1 * 0.5 + w1 * 0.32, y1), Vector2(cx - w0 * 0.5 + w0 * 0.38, y0),
		]), Color(STONE_FACE.r, STONE_FACE.g, STONE_FACE.b, alpha))
		draw_line(
			Vector2(cx - w1 * 0.5 - 2.0, y1), Vector2(cx + w1 * 0.5 + 1.0, y1),
			Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, alpha), 3.2, true
		)
		draw_line(
			Vector2(cx - w1 * 0.5 - 2.0, y1), Vector2(cx - w0 * 0.5, y0),
			Color(STONE_RIM.r, STONE_RIM.g, STONE_RIM.b, 0.55 * alpha), 1.2, true
		)
		draw_line(
			Vector2(cx - w0 * 0.5, y0), Vector2(cx + w0 * 0.55, y0),
			Color(STONE_SEAM.r, STONE_SEAM.g, STONE_SEAM.b, alpha), 2.4, true
		)
	# Jagged crown: the top slab breaks into a two-point silhouette.
	var top_y: float = _ground.y - height
	var top_w: float = base_w * (1.0 - 0.62) * 0.5
	var cxt: float = _ground.x + _slab_jitter[STONE_SLABS - 1] * base_w * 0.3
	draw_colored_polygon(PackedVector2Array([
		Vector2(cxt - top_w, top_y),
		Vector2(cxt - top_w * 0.45, top_y - slab_h * 1.1),
		Vector2(cxt + top_w * 0.1, top_y - slab_h * 0.35),
		Vector2(cxt + top_w * 0.6, top_y - slab_h * 0.8),
		Vector2(cxt + top_w, top_y),
	]), Color(STONE_BODY.r, STONE_BODY.g, STONE_BODY.b, alpha))
	draw_line(
		Vector2(cxt - top_w, top_y), Vector2(cxt - top_w * 0.45, top_y - slab_h * 1.1),
		Color(STONE_RIM.r, STONE_RIM.g, STONE_RIM.b, 0.65 * alpha), 1.3, true
	)


## One flanking shard: a tilted triangular slab with a lit face and HDR edge.
func _draw_stone_shard(
	base: Vector2, height: float, width: float, tilt: float, alpha: float, ji: int
) -> void:
	var dirv := Vector2(sin(tilt), -cos(tilt))
	var perp := Vector2(-dirv.y, dirv.x)
	var tip: Vector2 = base + dirv * height + perp * _slab_jitter[ji] * width * 0.4
	var kink: Vector2 = base + dirv * height * 0.55 - perp * width * 0.62
	var verts := PackedVector2Array([
		base - perp * width * 0.5, kink, tip, base + perp * width * 0.55,
	])
	draw_colored_polygon(verts, Color(STONE_BODY.r, STONE_BODY.g, STONE_BODY.b, alpha))
	# Lit facet toward the kink side so the shard reads as an angled rock face.
	draw_colored_polygon(PackedVector2Array([
		base - perp * width * 0.5, kink, base.lerp(tip, 0.55),
	]), Color(STONE_FACE.r, STONE_FACE.g, STONE_FACE.b, alpha))
	draw_line(kink, tip, Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, alpha), 2.2, true)
	draw_line(tip, base + perp * width * 0.55, Color(STONE_RIM.r, STONE_RIM.g, STONE_RIM.b, 0.5 * alpha), 1.2, true)


## Broken slabs heaped where the spire punched through — sells "ERUPTED out of
## the ground" instead of "placed on top of it".
func _draw_stone_rubble(alpha: float) -> void:
	var r: float = _radius
	var hump := PackedVector2Array([
		_ground + Vector2(-r * 0.85, 0.0),
		_ground + Vector2(-r * 0.6, -10.0),
		_ground + Vector2(-r * 0.3, -16.0),
		_ground + Vector2(r * 0.15, -13.0),
		_ground + Vector2(r * 0.55, -17.0),
		_ground + Vector2(r * 0.85, 0.0),
	])
	draw_colored_polygon(hump, Color(0.36, 0.32, 0.26, 0.9 * alpha))
	draw_line(
		_ground + Vector2(-r * 0.6, -10.0), _ground + Vector2(-r * 0.3, -16.0),
		Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 0.7 * alpha), 2.0, true
	)
	draw_line(
		_ground + Vector2(r * 0.15, -13.0), _ground + Vector2(r * 0.55, -17.0),
		Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, 0.6 * alpha), 2.0, true
	)
