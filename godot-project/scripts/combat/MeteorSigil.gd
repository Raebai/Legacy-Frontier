class_name MeteorSigil
extends Node2D

## Who this meteor storm's damage hits. Default "enemy"; the Boss sets "hero".
var target_group: String = "enemy"
## Signature spectacle #3 — the SKY BOMBARDMENT. A huge magic circle opens high
## over the marked area and a barrage falls, staggered so it reads as a shower.
##
## Phase-2 redesign: the four elements are NO LONGER recolors of one falling
## head. Each has its own falling-object identity + impact behaviour:
##   FIRE   — true meteors: tumbling molten rock with glowing cracks and a
##            ragged burning tail; impact explodes outward and leaves a
##            persistent scorch + a flickering ember pool.
##   FROST  — sheer crystal SPIKES that spear straight down (no arc, no tail —
##            just cold air-streaks), plant in the ground as standing jagged
##            crystal, then shatter into shards a beat later.
##   EARTH  — heavy dumb BOULDERS: slower, no tail, a looming ground shadow;
##            impact is a dust plume + debris chunks kicked sideways + the
##            hardest camera thump of the four.
##   SHADOW — not objects at all: TEARS rip open in the air, a column of void
##            drops from each, and the impact IMPLODES — pulls targets inward
##            instead of knocking them away.
##
## Dodgeability (overhaul rule 2): besides the 0.5 s sigil charge, EVERY impact
## point gets its own element-flavoured ground telegraph (scorch ring / frost
## bloom / looming dust shadow / dilating void slit) that starts BEFORE the
## object can hit, so each strike has a genuine per-point reaction window.
##
## Per-meteor radius damage (targets_in_radius, pure/testable); rain() drives
## the timeline. Instantiate .new(), add to the arena, call rain(). The
## trailing `effect` param picks the element ("fire"|"frost"|"earth"|"shadow"
## bespoke; anything else falls back to the classic head+trail template).

const CHARGE_TIME: float = 0.5     # sky sigil + ground telegraph before ANY launch
const FALL_TIME: float = 0.52      # fire + generic per-meteor descent
const BARRAGE_TIME: float = 1.15   # window the meteors spawn across
const FADE_TIME: float = 0.35
## Per-element descent times — the fall IS the personality: frost spears are
## quick (compensated by an earlier telegraph), earth boulders are ponderous
## mass, shadow spends most of its window visibly tearing open before the drop.
const FALL_TIME_FROST: float = 0.40
const FALL_TIME_EARTH: float = 0.82
const FALL_TIME_SHADOW: float = 0.55
## Frost's ground bloom starts this long BEFORE its spike launches, so the
## fast spear still gives a fair (0.30 + 0.40 = 0.70 s) reaction window.
const MARK_LEAD_FROST: float = 0.30
## Shadow tears open THIS far above the ground — low, menacing, readable.
const RIFT_HEIGHT: float = 115.0
## Fraction of shadow's fall spent opening the tear (the rest is the void drop).
const RIFT_OPEN_FRAC: float = 0.64
## Meteors streak in from just above the combat view (not far off-screen) so you
## SEE the shower coming down — readability + the "here it comes" tell.
const SKY_HEIGHT: float = 360.0
const DEFAULT_RADIUS: float = 135.0
const DEFAULT_DAMAGE: int = 22     # per meteor — many meteors overlap
const DEFAULT_COUNT: int = 10
const METEOR_IMPACT_RADIUS: float = 48.0
const KNOCKBACK: float = 240.0
const SLANT: Vector2 = Vector2(110.0, 0.0)  # fire meteors streak in from the upper-right
## VISUAL-ONLY: sky sigil circle size relative to the AoE `radius` passed to
## rain(). Does NOT feed damage — targets_in_radius()/_land() always use
## METEOR_IMPACT_RADIUS (per-meteor) for the actual hit query.
const SIGIL_VISUAL_RADIUS_FACTOR: float = 1.1
## The arena is SIDE-VIEW: the AoE `radius` is a ground FOOTPRINT, so impact
## points scatter across a y-squashed ellipse hugging the floor plane. A full
## disc put ~half the strikes (and their telegraphs) in empty sky, which
## destroyed the "this is where it lands" read and wasted damage on air.
const GROUND_SCATTER: Vector2 = Vector2(1.0, 0.35)
## Ground-plane squash for every per-impact marker (matches the 0.4–0.5 used
## by the charge telegraphs / decals) — markers are floor shading, never HUD.
const MARKER_SQUASH: Vector2 = Vector2(1.0, 0.45)

var _center: Vector2 = Vector2.ZERO
var _color: Color = Color(1.0, 0.55, 0.2, 1.0)
var _radius: float = DEFAULT_RADIUS
var _damage: int = DEFAULT_DAMAGE
var _effect: String = "fire"
var _elapsed: float = -1.0
var _circle: MagicCircle = null
var _circle_dismissed: bool = false
var _meteors: Array = []  # each: {delay, from, to, landed, seed, spin, verts}
## Elemental ailment (Elements.Element) applied to enemies a meteor hits. -1=none.
var element_id: int = -1


## Public entry: open a sigil over `target` and rain `count` meteors within
## `radius`. Colour tints the shower; `effect` picks its character
## ("fire"/"frost"/"earth"/"shadow" bespoke, others generic).
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
	_circle.appear(_color, radius * SIGIL_VISUAL_RADIUS_FACTOR, CHARGE_TIME * 0.85)
	for i: int in count:
		var ang: float = randf() * TAU
		var dist: float = sqrt(randf()) * radius  # sqrt -> uniform over the disc
		# GROUND_SCATTER pins the whole shower to the floor band (see const WHY).
		var to: Vector2 = _center + Vector2.from_angle(ang) * dist * GROUND_SCATTER
		var delay: float = (float(i) / float(count)) * BARRAGE_TIME + randf_range(0.0, 0.06)
		var m: Dictionary = {
			"delay": delay, "from": _spawn_point(to), "to": to, "landed": false,
			"seed": randf() * TAU, "spin": randf_range(-2.2, 2.2),
			"verts": PackedVector2Array(),
		}
		# Rock silhouettes are baked ONCE per meteor so the tumbling shape stays
		# stable frame to frame (re-rolling per _draw would shimmer).
		match _effect:
			"fire":
				m["verts"] = _bake_rock(9.5, 0.45)
			"earth":
				m["verts"] = _bake_rock(17.0, 0.4)
				m["spin"] = randf_range(-3.4, 3.4)  # boulders tumble harder
		_meteors.append(m)
	Sfx.play("charge_up", -2.0, 0.05)  # sigil opens — epic build before the barrage
	queue_redraw()


## Where this element's falling object enters from. Fire keeps the classic
## upper-right slant (a shower streaking in); frost/earth drop near-vertically
## (spears and dead weight); shadow tears open LOW — nothing falls from the sky.
func _spawn_point(to: Vector2) -> Vector2:
	match _effect:
		"frost":
			return to + Vector2(randf_range(-10.0, 10.0), -SKY_HEIGHT)
		"earth":
			return to + Vector2(randf_range(-18.0, 18.0) + 26.0, -SKY_HEIGHT)
		"shadow":
			return to + Vector2(0.0, -RIFT_HEIGHT)
		_:
			return to + SLANT + Vector2(0.0, -SKY_HEIGHT)


## Per-element descent duration (see the constants' WHY note).
func _fall_time() -> float:
	match _effect:
		"frost":
			return FALL_TIME_FROST
		"earth":
			return FALL_TIME_EARTH
		"shadow":
			return FALL_TIME_SHADOW
		_:
			return FALL_TIME


## How long before launch this element's per-impact ground telegraph appears.
func _mark_lead() -> float:
	return MARK_LEAD_FROST if _effect == "frost" else 0.0


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	for m: Dictionary in _meteors:
		if not m["landed"] and _elapsed >= CHARGE_TIME + float(m["delay"]) + _fall_time():
			_land(m)
	# Dissolve the sky sigil once the barrage has all launched (matches the
	# graceful vanish beam/ray get, instead of popping when we free).
	if not _circle_dismissed and _elapsed >= CHARGE_TIME + BARRAGE_TIME:
		_circle_dismissed = true
		if _circle != null and is_instance_valid(_circle):
			_circle.vanish(_fall_time() + FADE_TIME)
	if _elapsed >= CHARGE_TIME + BARRAGE_TIME + _fall_time() + FADE_TIME:
		queue_free()
		return
	queue_redraw()


## One strike lands: radius damage + status (shared contract), then the
## element's own impact spectacle. Residue nodes are parented to the arena
## (get_parent()), never self — they must outlive this spectacle node.
func _land(m: Dictionary) -> void:
	m["landed"] = true
	var at: Vector2 = m["to"]
	_apply_damage(at)
	match _effect:
		"fire":
			_land_fire(at)
		"frost":
			_land_frost(at)
		"earth":
			_land_earth(at)
		"shadow":
			_land_shadow(at)
		_:
			_land_generic(at)


## Shared damage/status contract for every element; only the knockback
## CHARACTER differs — fire blasts away, frost pins (soft push), earth slams
## hardest, shadow PULLS INWARD (the implosion made mechanical).
func _apply_damage(at: Vector2) -> void:
	for enemy: Node in targets_in_radius(at, METEOR_IMPACT_RADIUS, get_tree().get_nodes_in_group(target_group)):
		if enemy.has_method("take_damage"):
			enemy.take_damage(_damage)
		if element_id >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(element_id)
		if enemy.has_method("apply_knockback"):
			var out: Vector2 = ((enemy as Node2D).global_position - at).normalized()
			if out == Vector2.ZERO:
				out = Vector2.UP
			match _effect:
				"shadow":
					enemy.apply_knockback(-out * 210.0)  # sucked toward the void
				"frost":
					enemy.apply_knockback(out * 150.0)   # speared, not blasted
				"earth":
					enemy.apply_knockback(out * 300.0)   # the heaviest thump
				_:
					enemy.apply_knockback(out * KNOCKBACK)
	for prop: Node in targets_in_radius(at, METEOR_IMPACT_RADIUS, get_tree().get_nodes_in_group("destructible")):
		if prop.has_method("take_damage"):
			prop.take_damage(_damage)


## FIRE impact: outward explosion — flame plume + ember burst + persistent
## scorch + a lingering EMBER POOL that keeps flickering after the blast.
func _land_fire(at: Vector2) -> void:
	if element_id >= 0:
		ElementFx.spawn(get_parent(), at, element_id, METEOR_IMPACT_RADIUS * 0.62)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(1.5, 0.7, 0.2, 0.95), Color(0.8, 0.2, 0.05, 0.0),
		18, 0.5, 60.0, 220.0, 1.0, 2.6, 0.5, 1.6, true
	)
	ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.7, "scorch",
		Color(0.08, 0.03, 0.02, 0.6), 8.0)
	EmberPool.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.6)
	GroundCrater.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.55, true)
	Juice.shake_camera(5.0)
	Sfx.play("spell_impact", 0.0, 0.08)


## FROST impact: the spike SPEARS IN and stays — a standing crystal cluster
## that shatters a beat later (via IceSpikeCluster). No crater: ice doesn't
## gouge, it pierces; a frost-crack decal marks the plant point instead.
func _land_frost(at: Vector2) -> void:
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.9, 0.98, 1.0, 0.9), Color(0.7, 0.9, 1.0, 0.0),
		10, 0.3, 60.0, 170.0, 0.5, 1.3, 2.0, 4.0, true
	)
	ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.6, "crack",
		Color(0.62, 0.88, 1.0, 0.45), 5.0)
	IceSpikeCluster.spawn(get_parent(), at)
	Juice.shake_camera(3.5)
	Sfx.play("spell_impact", -2.0, 0.08, 1.35)  # higher pitch — glassy, not boomy


## EARTH impact: a real ground-thump — huge slow dust plume (alpha-blended so
## it reads as dirt, not light), debris chunks kicked SIDEWAYS, the biggest
## crater and the hardest shake of the four.
func _land_earth(at: Vector2) -> void:
	# One bright frame first: even dead weight needs a flash for the thump to
	# read on a dark arena (Stick-Fight rule — the hit moment is the brightest).
	CombatVfx.spawn_burst(
		get_parent(), at, Color(1.35, 1.15, 0.85, 0.9), Color(0.9, 0.7, 0.45, 0.0),
		8, 0.18, 90.0, 200.0, 0.8, 1.5, 2.0, 4.0, true
	)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.82, 0.68, 0.5, 0.95), Color(0.5, 0.4, 0.28, 0.0),
		30, 0.9, 40.0, 150.0, 3.0, 7.0, 2.0, 4.0
	)
	CombatVfx.spawn_burst(
		get_parent(), at, Color(0.95, 0.8, 0.58, 0.95), Color(0.55, 0.44, 0.3, 0.0),
		14, 0.4, 130.0, 280.0, 1.0, 2.0, 1.0, 2.0
	)
	DebrisChunk.spawn_burst(get_parent(), at, Color(0.5, 0.38, 0.22), 3, Vector2.LEFT, 250.0)
	DebrisChunk.spawn_burst(get_parent(), at, Color(0.46, 0.35, 0.2), 3, Vector2.RIGHT, 250.0)
	ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.7, "crack",
		Color(0.6, 0.45, 0.28, 0.5), 6.0)
	GroundCrater.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.8, true)
	Juice.shake_camera(7.5)
	Sfx.play("spell_impact", 2.0, 0.05, 0.7)  # pitched DOWN — dead weight, not energy


## SHADOW impact: an IMPLOSION — everything converges (VoidImplosion draws the
## collapse), targets get pulled inward in _apply_damage, and only a faint
## violet stain remains. No crater, no outward burst: the anti-explosion.
func _land_shadow(at: Vector2) -> void:
	if element_id >= 0:
		ElementFx.spawn(get_parent(), at, element_id, METEOR_IMPACT_RADIUS * 0.5)
	VoidImplosion.spawn(get_parent(), at, METEOR_IMPACT_RADIUS)
	ScorchDecal.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.55, "scorch",
		Color(0.08, 0.03, 0.14, 0.5), 5.0)
	Juice.shake_camera(4.5)
	Sfx.play("spell_impact", -1.0, 0.06, 0.8)


## Fallback impact for non-bespoke effects (arcane/holy/lightning/wind/etc):
## the classic energy burst + crater, charactered by the old per-effect arms.
func _land_generic(at: Vector2) -> void:
	if element_id >= 0:
		ElementFx.spawn(get_parent(), at, element_id, METEOR_IMPACT_RADIUS * 0.62)
	_impact_burst(at)
	GroundCrater.spawn(get_parent(), at, METEOR_IMPACT_RADIUS * 0.55, true)
	Juice.shake_camera(5.0)
	Sfx.play("spell_impact", 0.0, 0.1)


## Generic impact spray, charactered per (non-bespoke) effect.
func _impact_burst(at: Vector2) -> void:
	var fade: Color = Color(_color.r, _color.g, _color.b, 0.0)
	match _effect:
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


## Bake one irregular rock silhouette (7 verts) — fire meteor / earth boulder.
static func _bake_rock(size_px: float, irregularity: float) -> PackedVector2Array:
	var verts: PackedVector2Array = PackedVector2Array()
	var n: int = 7
	for i: int in n:
		var ang: float = TAU * float(i) / float(n) + randf_range(-irregularity, irregularity)
		var reach: float = size_px * randf_range(0.62, 1.0)
		verts.append(Vector2.from_angle(ang) * reach)
	return verts


func _draw() -> void:
	if _elapsed < 0.0:
		return
	if _elapsed < CHARGE_TIME:
		_draw_charge_telegraph(_elapsed / CHARGE_TIME)
	for m: Dictionary in _meteors:
		if m["landed"]:
			continue
		var launch_t: float = CHARGE_TIME + float(m["delay"])
		var land_t: float = launch_t + _fall_time()
		var mark_t: float = launch_t - _mark_lead()
		# Per-impact ground telegraph FIRST (under the falling object): the
		# element-flavoured "get out of THIS spot" marker (overhaul rule 2).
		if _elapsed >= mark_t:
			_draw_impact_marker(m, clampf((_elapsed - mark_t) / maxf(land_t - mark_t, 0.001), 0.0, 1.0))
		if _elapsed < launch_t:
			continue
		var f: float = clampf((_elapsed - launch_t) / _fall_time(), 0.0, 1.0)
		match _effect:
			"fire":
				_draw_fire_meteor(m, f)
			"frost":
				_draw_ice_spike(m, f)
			"earth":
				_draw_earth_boulder(m, f)
			"shadow":
				_draw_shadow_rift(m, f)
			_:
				_draw_generic_meteor(m, f)


## Area telegraph during the sigil charge — flavoured so the DANGER ZONE itself
## already reads as the element before anything falls.
func _draw_charge_telegraph(tp: float) -> void:
	var r: float = _radius * (0.4 + 0.6 * tp)
	match _effect:
		"fire":
			var flick: float = 0.06 * sin(_elapsed * 24.0)
			draw_arc(_center, r, 0.0, TAU, 44, Color(1.1, 0.45, 0.12, (0.4 + flick) * tp), 2.5, true)
			draw_arc(_center, r * 0.82, 0.0, TAU, 40, Color(1.4, 0.7, 0.2, 0.22 * tp), 1.5, true)
		"frost":
			draw_arc(_center, r, 0.0, TAU, 44, Color(0.72, 0.92, 1.0, 0.42 * tp), 2.0, true)
			for k: int in 16:  # crystalline rim ticks — a ring of hoarfrost
				var dirv: Vector2 = Vector2.from_angle(TAU * float(k) / 16.0)
				draw_line(_center + dirv * r * 0.94, _center + dirv * (r * 0.94 + 7.0),
					Color(0.9, 1.0, 1.1, 0.5 * tp), 1.4, true)
		"earth":
			draw_set_transform(_center, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, r * 0.9, Color(0.5, 0.4, 0.28, 0.16 * tp), true, -1.0, true)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.85, 0.68, 0.44, 0.55 * tp), 3.0, true)
			draw_arc(Vector2.ZERO, r * 0.8, 0.0, TAU, 36, Color(0.66, 0.52, 0.34, 0.35 * tp), 1.8, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"shadow":
			draw_set_transform(_center, 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, r * 0.85, Color(0.05, 0.02, 0.1, 0.2 * tp), true, -1.0, true)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.75, 0.32, 1.15, 0.45 * tp), 2.2, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_:
			draw_arc(_center, r, 0.0, TAU, 44,
				Color(_color.r, _color.g, _color.b, 0.45 * tp), 2.5, true)


## Per-impact-point ground marker. `u` ramps 0 -> 1 across the reaction window.
## Density pass (post-review): with count~11, the old 2–3 stroked arcs PER
## POINT stacked into a screen-filling spirograph that read as a HUD overlay
## and buried the impacts themselves. Every element now gets AT MOST one thin
## stroke; the countdown read comes from FILLED ground-shading that grows and
## darkens toward impact. Same timing window (overhaul rule 2 intact) — only
## the visual volume knob moved. Everything is drawn y-squashed (MARKER_SQUASH)
## so markers are unmistakably floor paint, never floating UI.
func _draw_impact_marker(m: Dictionary, u: float) -> void:
	var at: Vector2 = m["to"]
	var close_r: float = lerpf(METEOR_IMPACT_RADIUS * 1.6, METEOR_IMPACT_RADIUS, u)
	match _effect:
		"fire":
			# Ember heat pooling in the strike spot + ONE closing scorch ring.
			var flick: float = 0.06 * sin(_elapsed * 26.0 + float(m["seed"]) * 7.0)
			draw_set_transform(at, 0.0, MARKER_SQUASH)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.3 + 0.55 * u),
				Color(1.1, 0.4, 0.1, 0.1 + 0.16 * u + flick), true, -1.0, true)
			# Ring kept FAINT: at count~11 even one ring per point stacks up, so
			# the growing ember pool carries the read and the ring only whispers.
			draw_arc(Vector2.ZERO, close_r, 0.0, TAU, 30,
				Color(1.3, 0.6, 0.18, 0.08 + 0.24 * u), 1.3, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"frost":
			# Frost bloom: a rime pool creeps over the ground while a six-armed
			# ice crystal grows in it — the arms ARE the countdown; the single
			# thin ring just marks the true footprint late.
			draw_set_transform(at, 0.0, MARKER_SQUASH)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.25 + 0.6 * u),
				Color(0.65, 0.85, 1.0, 0.08 + 0.12 * u), true, -1.0, true)
			for k: int in 6:
				var dirv: Vector2 = Vector2.from_angle(float(m["seed"]) + TAU * float(k) / 6.0)
				var arm: Vector2 = dirv * METEOR_IMPACT_RADIUS * 0.85 * u
				draw_line(Vector2.ZERO, arm, Color(0.85, 0.97, 1.0, 0.5 * u), 1.5, true)
				var elbow: Vector2 = dirv * METEOR_IMPACT_RADIUS * 0.5 * u
				var side: Vector2 = dirv.orthogonal() * METEOR_IMPACT_RADIUS * 0.18 * u
				draw_line(elbow, elbow + side + dirv * 5.0, Color(0.85, 0.97, 1.0, 0.35 * u), 1.2, true)
				draw_line(elbow, elbow - side + dirv * 5.0, Color(0.85, 0.97, 1.0, 0.35 * u), 1.2, true)
			draw_arc(Vector2.ZERO, METEOR_IMPACT_RADIUS, 0.0, TAU, 30,
				Color(0.8, 0.95, 1.1, 0.35 * u * u), 1.2, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"earth":
			# NO strokes at all: the boulder's shadow is displaced dust — a soft
			# pale smudge at the footprint plus a darkening core that grows as
			# the rock nears. Shading the ground (not outlining it) is what
			# keeps the impact spectacle in front of its own telegraph.
			draw_set_transform(at, 0.0, MARKER_SQUASH)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.45 + 0.55 * u),
				Color(0.58, 0.48, 0.34, 0.11 + 0.17 * u), true, -1.0, true)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * 0.62 * u,
				Color(0.07, 0.05, 0.04, 0.55 * u), true, -1.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"shadow":
			# Void slit: a dark ground tear dilating open with ONE violet rim,
			# plus a few ticks CONVERGING inward — this spot is about to swallow.
			draw_set_transform(at, 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * 0.8 * u,
				Color(0.05, 0.02, 0.1, 0.22 + 0.3 * u), true, -1.0, true)
			draw_arc(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.5 + 0.5 * u), 0.0, TAU, 26,
				Color(0.7, 0.3, 1.1, 0.22 + 0.33 * u), 1.6, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for k: int in 5:
				var dirv2: Vector2 = Vector2.from_angle(float(m["seed"]) + TAU * float(k) / 5.0)
				var reach: float = lerpf(METEOR_IMPACT_RADIUS * 1.5, METEOR_IMPACT_RADIUS * 0.4, u)
				var p0: Vector2 = at + Vector2(dirv2.x, dirv2.y * 0.4) * reach
				var p1: Vector2 = at + Vector2(dirv2.x, dirv2.y * 0.4) * (reach - 9.0)
				draw_line(p0, p1, Color(0.6, 0.28, 0.95, 0.25 + 0.35 * u), 1.4, true)
		_:
			# Generic: a soft tinted pool + ONE closing ring.
			draw_set_transform(at, 0.0, MARKER_SQUASH)
			draw_circle(Vector2.ZERO, METEOR_IMPACT_RADIUS * (0.3 + 0.55 * u),
				Color(_color.r, _color.g, _color.b, 0.07 + 0.13 * u), true, -1.0, true)
			draw_arc(Vector2.ZERO, close_r, 0.0, TAU, 30,
				Color(_color.r, _color.g, _color.b, 0.18 + 0.36 * u), 1.4, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## FIRE in flight: a tumbling molten rock — dark silhouette, HDR glowing
## cracks, a white-hot leading edge — dragging a ragged three-tongue burning
## tail that sheds embers. THE meteor.
func _draw_fire_meteor(m: Dictionary, f: float) -> void:
	var from: Vector2 = m["from"]
	var to: Vector2 = m["to"]
	var pos: Vector2 = from.lerp(to, f)
	var dir: Vector2 = (to - from).normalized()
	var perp: Vector2 = dir.orthogonal()
	var s: float = float(m["seed"])
	# Ragged burning tail: three wavering tongues, widest+dimmest at the back.
	for k: int in 3:
		var tongue_len: float = (58.0 + 16.0 * float(k)) * (0.55 + 0.45 * f)
		var sway: float = sin(_elapsed * (11.0 + 3.0 * float(k)) + s + float(k) * 2.1) * (3.0 + 2.5 * float(k))
		var tail: Vector2 = pos - dir * tongue_len + perp * sway
		var tones: Array = [
			Color(1.0, 0.42, 0.1, 0.28), Color(1.2, 0.6, 0.15, 0.4), Color(1.5, 0.85, 0.3, 0.55),
		]
		draw_line(tail, pos, tones[k], 12.0 - 3.5 * float(k), true)
	# Embers shed along the wake.
	for e: int in 5:
		var back: float = 14.0 + 13.0 * float(e)
		var wob: Vector2 = perp * sin(_elapsed * 17.0 + s + float(e) * 1.7) * (2.0 + float(e))
		draw_circle(pos - dir * back + wob, 2.4 - 0.3 * float(e),
			Color(1.6, 0.7, 0.2, 0.7 - 0.11 * float(e)), true, -1.0, true)
	# Heat halo, then the tumbling rock body with glowing cracks.
	draw_circle(pos, 16.0, Color(1.0, 0.4, 0.12, 0.28), true, -1.0, true)
	var verts: PackedVector2Array = m["verts"]
	draw_set_transform(pos, s + _elapsed * float(m["spin"]), Vector2.ONE)
	draw_colored_polygon(verts, Color(0.26, 0.15, 0.11, 1.0))
	draw_line(verts[0] * 0.7, verts[3] * 0.75, Color(1.7, 0.75, 0.2, 0.9), 1.6, true)
	draw_line(verts[1] * 0.65, verts[4] * 0.7, Color(1.5, 0.55, 0.15, 0.8), 1.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# White-hot leading edge — air friction, HDR so it blooms.
	draw_circle(pos + dir * 7.0, 4.0, Color(1.9, 1.3, 0.6, 0.9), true, -1.0, true)


## FROST in flight: a sheer crystal spear falling point-down — translucent
## faceted body, HDR rim + refractive core line, cold air-streaks instead of
## any burning tail. Reads "javelin", not "rock".
func _draw_ice_spike(m: Dictionary, f: float) -> void:
	var pos: Vector2 = (m["from"] as Vector2).lerp(m["to"], f)
	var s: float = float(m["seed"])
	var spear_len: float = 50.0
	var w: float = 7.5
	draw_set_transform(pos, sin(s) * 0.1, Vector2.ONE)
	var body := PackedVector2Array([
		Vector2(0.0, spear_len * 0.58),           # tip — leading, points DOWN
		Vector2(w, spear_len * 0.1),
		Vector2(w * 0.5, -spear_len * 0.42),
		Vector2(0.0, -spear_len * 0.5),
		Vector2(-w * 0.5, -spear_len * 0.42),
		Vector2(-w, spear_len * 0.1),
	])
	draw_colored_polygon(body, Color(0.6, 0.83, 1.0, 0.5))   # translucent crystal
	var rim: PackedVector2Array = body.duplicate()
	rim.append(body[0])
	draw_polyline(rim, Color(1.2, 1.55, 1.75, 1.0), 1.5, true)  # HDR facet rim
	draw_line(Vector2(0.0, -spear_len * 0.42), Vector2(0.0, spear_len * 0.5),
		Color(1.6, 1.7, 1.85, 0.9), 2.2, true)                  # refractive core
	draw_circle(Vector2(0.0, spear_len * 0.5), 3.0, Color(1.7, 1.8, 1.9, 0.85), true, -1.0, true)  # tip glint
	# Cold air-streaks trailing above — pure speed, no fire.
	draw_line(Vector2(0.0, -spear_len * 0.6), Vector2(0.0, -spear_len * 1.15),
		Color(0.75, 0.92, 1.0, 0.3), 2.5, true)
	draw_line(Vector2(w * 0.6, -spear_len * 0.5), Vector2(w * 0.6, -spear_len * 0.95),
		Color(0.75, 0.92, 1.0, 0.18), 1.5, true)
	draw_line(Vector2(-w * 0.6, -spear_len * 0.5), Vector2(-w * 0.6, -spear_len * 0.95),
		Color(0.75, 0.92, 1.0, 0.18), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## EARTH in flight: a big dumb boulder — flat opaque rock tones, hard tumble,
## NO tail (a whisper of falling dust only). Mass, not energy.
func _draw_earth_boulder(m: Dictionary, f: float) -> void:
	var pos: Vector2 = (m["from"] as Vector2).lerp(m["to"], f)
	var verts: PackedVector2Array = m["verts"]
	# A dusty speed-smear behind (NOT a burning tail — displaced air + grit),
	# so the dark mass separates from the dark sky while it falls.
	var up: Vector2 = ((m["from"] as Vector2) - (m["to"] as Vector2)).normalized()
	draw_line(pos + up * 16.0, pos + up * 52.0, Color(0.62, 0.52, 0.38, 0.22), 9.0, true)
	draw_line(pos + up * 16.0, pos + up * 38.0, Color(0.72, 0.6, 0.44, 0.18), 4.0, true)
	draw_set_transform(pos, float(m["seed"]) + _elapsed * float(m["spin"]), Vector2.ONE)
	# Lit rock: warm mid-tone body + sun-side highlight facet + dark under-edge.
	# The old 0.45/0.35/0.23 fill vanished against the dark arena sky.
	draw_colored_polygon(verts, Color(0.56, 0.45, 0.31, 1.0))
	var highlight := PackedVector2Array([
		verts[0] * 0.9, verts[1] * 0.9, verts[2] * 0.55, Vector2.ZERO,
	])
	draw_colored_polygon(highlight, Color(0.74, 0.62, 0.44, 1.0))
	var outline: PackedVector2Array = verts.duplicate()
	outline.append(verts[0])
	draw_polyline(outline, Color(0.24, 0.18, 0.12, 1.0), 1.8, true)
	# Facet lines so the rock reads 3D while it tumbles.
	draw_line(verts[1] * 0.85, verts[4] * 0.8, Color(0.3, 0.23, 0.15, 0.8), 1.2, true)
	draw_line(verts[2] * 0.8, verts[5] * 0.85, Color(0.78, 0.66, 0.48, 0.7), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d: int in 3:
		var dust: Vector2 = pos + up * (20.0 + 13.0 * float(d)) + Vector2(
			sin(_elapsed * 9.0 + float(d) * 2.2 + float(m["seed"])) * 5.0, 0.0)
		draw_circle(dust, 2.6, Color(0.68, 0.57, 0.42, 0.2), true, -1.0, true)


## SHADOW in flight: nothing falls from the sky. A lens-shaped TEAR rips open
## low above the mark (violet HDR rim around a void interior, reality-cracks
## converging into it), then a column of void slams down to the ground.
func _draw_shadow_rift(m: Dictionary, f: float) -> void:
	var to: Vector2 = m["to"]
	var rift: Vector2 = m["from"]  # = to + (0, -RIFT_HEIGHT), see _spawn_point
	var s: float = float(m["seed"])
	var open_f: float = clampf(f / RIFT_OPEN_FRAC, 0.0, 1.0)
	var half_w: float = 42.0 * open_f
	if half_w > 0.5:
		# A soft darkness halo BEHIND the tear — the air dims around a wound
		# in reality, which sells "hole", not "purple ellipse".
		draw_circle(rift, half_w * 1.5, Color(0.03, 0.01, 0.07, 0.35 * open_f), true, -1.0, true)
		draw_set_transform(rift, sin(s) * 0.15, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, half_w, Color(0.02, 0.0, 0.05, 0.95), true, -1.0, true)
		draw_arc(Vector2.ZERO, half_w, 0.0, TAU, 32, Color(1.1, 0.5, 1.6, 0.95), 2.6, true)
		draw_arc(Vector2.ZERO, half_w * 0.8, 0.0, TAU, 28, Color(0.6, 0.25, 1.0, 0.5), 1.4, true)
		# The rim SEETHES: a bright HDR glint racing around the edge.
		var glint: Vector2 = Vector2.from_angle(_elapsed * 9.0 + s) * half_w
		draw_circle(glint, 2.6, Color(1.5, 1.0, 1.8, 0.9), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Motes + reality-cracks being SUCKED into the tear while it opens.
	if f < RIFT_OPEN_FRAC + 0.1:
		for k: int in 8:
			var dirv: Vector2 = Vector2.from_angle(s + TAU * float(k) / 8.0)
			var pull: float = fposmod(_elapsed * 1.8 + float(k) * 0.37, 1.0)
			var reach: float = lerpf(64.0, 8.0, pull)
			var mote: Vector2 = rift + Vector2(dirv.x, dirv.y * 0.55) * reach
			draw_line(mote, mote + Vector2(dirv.x, dirv.y * 0.55) * -10.0,
				Color(0.75, 0.38, 1.1, (0.2 + 0.5 * open_f) * (1.0 - pull * 0.4)), 1.6, true)
			draw_circle(mote, 1.8, Color(0.9, 0.55, 1.3, (0.3 + 0.5 * open_f) * pull), true, -1.0, true)
	# The drop: a void column slams from the tear to the ground.
	if f > RIFT_OPEN_FRAC:
		var t2: float = (f - RIFT_OPEN_FRAC) / (1.0 - RIFT_OPEN_FRAC)
		var tip: Vector2 = rift.lerp(to, t2)
		draw_line(rift, tip, Color(0.07, 0.02, 0.13, 0.9), 15.0, true)
		draw_line(rift, tip, Color(0.5, 0.2, 0.8, 0.7), 7.0, true)
		draw_line(rift, tip, Color(1.2, 0.7, 1.7, 0.9), 2.5, true)  # HDR seam


## Fallback in-flight draw (non-bespoke effects): the classic head + trail.
func _draw_generic_meteor(m: Dictionary, f: float) -> void:
	var from: Vector2 = m["from"]
	var to: Vector2 = m["to"]
	var pos: Vector2 = from.lerp(to, f)
	var trail: Vector2 = from.lerp(to, maxf(f - 0.38, 0.0))
	var c: Color = _color
	var inner: Color = _trail_inner_color()
	var core: Color = _effect_core_color()
	draw_line(trail, pos, Color(c.r, c.g, c.b, 0.5), 10.0, true)
	draw_line(trail, pos, Color(inner.r, inner.g, inner.b, 0.7), 4.0, true)
	draw_circle(pos, 13.0, Color(c.r, c.g, c.b, 0.4), true, -1.0, true)
	draw_circle(pos, 8.0, Color(c.r, c.g, c.b, 0.95), true, -1.0, true)
	draw_circle(pos, 4.5, core, true, -1.0, true)


## Bright inner-trail tint (generic template only).
func _trail_inner_color() -> Color:
	match _effect:
		"arcane":
			return Color(1.0, 0.85, 1.0)
		"holy":
			return Color(1.0, 0.99, 0.85)
		"lightning":
			return Color(1.0, 1.0, 0.75)
		"wind":
			return Color(0.8, 1.0, 0.95)
		_:
			return Color(1.0, 0.9, 0.6)


## Hot-core tint (generic template only). HDR cores bloom.
func _effect_core_color() -> Color:
	match _effect:
		"arcane":
			return Color(1.7, 1.5, 1.7, 1.0)
		"holy":
			return Color(1.75, 1.75, 1.5, 1.0)
		"lightning":
			return Color(1.9, 1.7, 0.9, 1.0)
		"wind":
			return Color(1.35, 1.85, 1.7, 1.0)
		_:
			return Color(1.8, 1.6, 1.2, 1.0)


## ---------------------------------------------------------------------------
## Residue nodes. Inner classes so this redesign stays inside ONE file (other
## spell files are being edited in parallel). All are parented to the ARENA at
## spawn so they outlive the sigil node, and use NO autoloads (pure draw +
## the headless-safe CombatVfx/DebrisChunk statics), matching ScorchDecal.


## FIRE residue: a pool of embers that keeps flickering after the blast — the
## "the ground is still burning" beat that a one-shot burst can't sell.
class EmberPool extends Node2D:
	const LIFE: float = 2.8

	var radius: float = 30.0
	var _age: float = 0.0
	var _embers: Array = []  # each: {pos, size, phase}

	static func spawn(parent: Node, world_pos: Vector2, pool_radius: float) -> void:
		if parent == null or not parent.is_inside_tree():
			return
		var pool := EmberPool.new()
		pool.radius = pool_radius
		pool.z_index = -1  # embers sit ON the floor, under the fighters
		parent.add_child(pool)
		pool.global_position = world_pos

	func _ready() -> void:
		for i: int in 9:
			_embers.append({
				# Squash y so the pool hugs the ground plane like the crater/decals.
				"pos": Vector2.from_angle(randf() * TAU) * (sqrt(randf()) * radius) * Vector2(1.0, 0.5),
				"size": randf_range(1.6, 3.4),
				"phase": randf() * TAU,
			})

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade: float = 1.0 - smoothstep(0.55, 1.0, _age / LIFE)
		if fade <= 0.01:
			return
		# Low heat-glow over the scorch, then the individual winking embers.
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.35, 0.08, 0.07 * fade), true, -1.0, true)
		for e: Dictionary in _embers:
			var flick: float = 0.5 + 0.5 * sin(_age * 9.0 + float(e["phase"]))
			var a: float = (0.35 + 0.6 * flick) * fade
			var p: Vector2 = e["pos"]
			draw_circle(p, float(e["size"]) * (0.8 + 0.3 * flick),
				Color(1.6, 0.55, 0.12, a * 0.8), true, -1.0, true)
			draw_circle(p, float(e["size"]) * 0.45, Color(1.9, 1.1, 0.4, a), true, -1.0, true)  # HDR heart


## FROST residue: the speared-in crystal cluster — stands as jagged ice for a
## beat (the spike's whole identity: it PLANTS, it doesn't splash), then
## shatters into flying fragments + a frost burst.
class IceSpikeCluster extends Node2D:
	const STAND_TIME: float = 0.6
	const SHATTER_TIME: float = 0.24
	const EMERGE_TIME: float = 0.09  # spear-in pop: scale up fast, don't blink in

	var _age: float = 0.0
	var _shattered: bool = false
	var _spears: Array = []  # each: {off, len, hw, tilt}
	var _frags: Array = []   # each: {dir, speed, size, spin}

	static func spawn(parent: Node, world_pos: Vector2) -> void:
		if parent == null or not parent.is_inside_tree():
			return
		var cluster := IceSpikeCluster.new()
		parent.add_child(cluster)
		cluster.global_position = world_pos

	func _ready() -> void:
		for i: int in 3:
			_spears.append({
				"off": Vector2(float(i - 1) * randf_range(7.0, 11.0), randf_range(-2.0, 2.0)),
				"len": randf_range(34.0, 52.0) * (1.0 if i == 1 else 0.72),  # center spear tallest
				"hw": randf_range(4.0, 6.5),
				"tilt": float(i - 1) * randf_range(0.14, 0.24),
			})
		for i: int in 10:
			_frags.append({
				"dir": Vector2.from_angle(randf_range(-PI, 0.0)),  # upward half only
				"speed": randf_range(60.0, 170.0),
				"size": randf_range(2.0, 4.2),
				"spin": randf_range(-9.0, 9.0),
			})

	func _process(delta: float) -> void:
		_age += delta
		if _age >= STAND_TIME and not _shattered:
			_shattered = true
			# The shatter beat: a frost burst + a couple of physical ice chips.
			CombatVfx.spawn_burst(
				get_parent(), global_position, Color(0.9, 0.98, 1.0, 0.95),
				Color(0.7, 0.9, 1.0, 0.0), 22, 0.4, 120.0, 300.0, 0.6, 1.6, 2.5, 5.0, true
			)
			DebrisChunk.spawn_burst(get_parent(), global_position,
				Color(0.72, 0.86, 0.95), 3, Vector2.UP, 200.0)
		if _age >= STAND_TIME + SHATTER_TIME:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		if not _shattered:
			_draw_standing()
		else:
			_draw_fragments()

	func _draw_standing() -> void:
		var pop: float = clampf(_age / EMERGE_TIME, 0.0, 1.0)  # spear-in growth
		var glint: float = 0.75 + 0.25 * sin(_age * 13.0)
		for sp: Dictionary in _spears:
			var off: Vector2 = sp["off"]
			var spear_len: float = float(sp["len"]) * pop
			var hw: float = sp["hw"]
			draw_set_transform(off, float(sp["tilt"]), Vector2.ONE)
			var body := PackedVector2Array([
				Vector2(0.0, -spear_len),        # crystal tip points UP now
				Vector2(hw, -spear_len * 0.25),
				Vector2(hw * 0.7, 2.0),
				Vector2(-hw * 0.7, 2.0),
				Vector2(-hw, -spear_len * 0.25),
			])
			draw_colored_polygon(body, Color(0.55, 0.8, 1.0, 0.42))
			var rim: PackedVector2Array = body.duplicate()
			rim.append(body[0])
			draw_polyline(rim, Color(1.15, 1.5, 1.7, 0.85 * glint), 1.3, true)
			draw_line(Vector2(0.0, 0.0), Vector2(0.0, -spear_len * 0.92),
				Color(1.4, 1.6, 1.8, 0.5 * glint), 1.4, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_fragments() -> void:
		var t: float = (_age - STAND_TIME) / SHATTER_TIME
		var a: float = 1.0 - t
		for fr: Dictionary in _frags:
			var p: Vector2 = (fr["dir"] as Vector2) * float(fr["speed"]) * t * SHATTER_TIME * 4.0
			p.y += 220.0 * t * t * SHATTER_TIME  # gravity pulls the chips back down
			var fs: float = fr["size"]
			var rot: float = float(fr["spin"]) * t
			var tri := PackedVector2Array([
				p + Vector2(0.0, -fs).rotated(rot),
				p + Vector2(fs * 0.8, fs * 0.6).rotated(rot),
				p + Vector2(-fs * 0.8, fs * 0.6).rotated(rot),
			])
			draw_colored_polygon(tri, Color(0.8, 0.93, 1.0, 0.7 * a))


## SHADOW impact: the IMPLOSION — rings and streaks CONVERGE onto the point
## (the exact inverse of every other element's outward burst), then the
## collapse snaps to a single HDR violet star and blinks out.
class VoidImplosion extends Node2D:
	const LIFE: float = 0.5
	const COLLAPSE_FRAC: float = 0.66  # converge for 2/3, flash out for 1/3

	var radius: float = 48.0
	var _age: float = 0.0
	var _seeds: PackedFloat32Array = PackedFloat32Array()

	static func spawn(parent: Node, world_pos: Vector2, impact_radius: float) -> void:
		if parent == null or not parent.is_inside_tree():
			return
		var imp := VoidImplosion.new()
		imp.radius = impact_radius
		imp.z_index = 40
		parent.add_child(imp)
		imp.global_position = world_pos

	func _ready() -> void:
		for i: int in 10:
			_seeds.append(randf() * TAU)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = _age / LIFE
		if t < COLLAPSE_FRAC:
			var tt: float = t / COLLAPSE_FRAC
			var ease_in: float = tt * tt  # accelerating collapse — gravity, not a fade
			var rr: float = lerpf(radius * 1.5, radius * 0.12, ease_in)
			draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - 0.6 * tt),
				Color(0.05, 0.01, 0.1, 0.75), true, -1.0, true)
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, 30,
				Color(0.8, 0.35, 1.3, 0.5 + 0.4 * tt), 2.5, true)
			draw_arc(Vector2.ZERO, rr * 1.35, 0.0, TAU, 30,
				Color(0.6, 0.25, 1.0, 0.3 + 0.2 * tt), 1.5, true)
			for i: int in 10:
				var dirv: Vector2 = Vector2.from_angle(_seeds[i])
				var p_out: Vector2 = dirv * lerpf(radius * 1.7, radius * 0.15, ease_in)
				draw_line(p_out, p_out - dirv * 14.0 * (1.0 - tt * 0.5),
					Color(0.9, 0.5, 1.4, 0.6), 1.6, true)
		else:
			var t2: float = (t - COLLAPSE_FRAC) / (1.0 - COLLAPSE_FRAC)
			# The snap: one HDR violet star + a thin escaping ring — the only
			# outward element, and it's light, not matter.
			draw_circle(Vector2.ZERO, lerpf(3.0, radius * 0.45, t2),
				Color(1.4, 0.9, 1.8, (1.0 - t2) * 0.9), true, -1.0, true)
			draw_arc(Vector2.ZERO, radius * (0.3 + 0.9 * t2), 0.0, TAU, 30,
				Color(0.9, 0.5, 1.4, (1.0 - t2) * 0.5), 1.5, true)
