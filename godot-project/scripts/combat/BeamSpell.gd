class_name BeamSpell
extends Node2D

## Which group this beam's damage query hits. Default "enemy" (hero casts it);
## the Boss sets "hero" so it can fire the same beam AT the player.
var target_group: String = "enemy"
## Signature spectacle #1 — the Frieren "Zoltraak" SIGIL BEAM. A huge magic
## circle materialises at the muzzle, gathers for a beat (a fair telegraph —
## dodge-the-tell), then FIRES a screen-crossing energy beam along the aim,
## damaging everything on the line, with heavy juice (hitstop, big shake,
## zoom-punch) and impact spray at the far end. Then the beam fades and the
## circle dissolves.
##
## Damage is a pure geometric line test (targets_on_beam) so it's headless-
## testable; the fire() entry drives the visual/juice timeline. Instantiate
## .new(), add as a child of the arena, then call fire().
##
## The trailing `effect` param picks the elemental IDENTITY of the spectacle —
## and each element gets its own SILHOUETTE, not a tint-swap:
##   "fire"      = two serpentine dragons weaving around a thin spine.
##   "frost"     = steady cold lance + crystal shards + hexagonal muzzle lens.
##   "arcane"    = ZOLTRAAK: a hard-edged razor lance with an arrowhead point,
##                 crisp edge rails and compression rings racing forward.
##   "shadow"    = UMBRAL: a light-EATING void core that blacks out the
##                 background, violet fray gnawing its rim, wisps peeling
##                 backward off the beam.
##   "lightning" = TEMPEST: no solid beam at all — a braided storm torrent of
##                 four crackling strands, spark debris and strobing forks.
##   "holy"      = extra-wide feathery radiance (glow bands + motes).
## The damage corridor is IDENTICAL for all of them (same line test) — only
## the visual language changes, so no skin is a stealth balance change.

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
## SEIZED by a reaction (Hollow Purple's first beat): the timeline is pinned so
## the beam stays drawn exactly where it was and does nothing else. A single
## early-return, deliberately — the worst a bug here can do is make a beam
## LINGER, never damage twice.
var _frozen: bool = false
var _circle: MagicCircle = null
## Elemental ailment (Elements.Element) applied to enemies the beam hits. -1=none.
var element_id: int = -1
## Who cast this. Set by SpellCaster; drives the reaction layer's SAME-OWNER
## rules, which is how one caster combines two of their own spells. Not `owner`:
## that name is already Node's scene-ownership property.
var caster_node: Node = null


## Public entry: charge at `origin`, then fire a beam of `length`/`width` along
## `dir`, dealing `damage`. Colour tints the whole spectacle (element);
## `effect` picks its elemental identity ("frost"/"fire"/"arcane"/"shadow"/
## "lightning"/"holy" — each a distinct silhouette, see class doc).
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
	# Join the reaction system. Registering during the CHARGE is correct:
	# reaction_active() keeps the beam inert until it actually fires, so two
	# beams cannot annihilate while they are still only telegraphs.
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"register", self, ReactionTable.Form.BEAM, element_id)
	queue_redraw()


func _exit_tree() -> void:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor != null:
		reactor.call(&"unregister", self)


# --- reaction contract (see SpellReactor) -----------------------------------

## World-space geometry, built from `_origin` — NOT from global_position, which
## is (0, 0) because this node draws in world coordinates. Width matches the
## damage corridor (`_apply_beam_damage`'s half-width, doubled).
func reaction_shape() -> Dictionary:
	return SpellGeometry.capsule(_origin, _beam_tip(), _width + 16.0)


## LOAD-BEARING: false during the CHARGE_TIME telegraph, so two beams cannot
## annihilate while they are still only telegraphs. True for the beam's whole
## VISIBLE life — the held shot plus its fade — which is also what sets the
## self-combo window: two beams cast within ~0.48 s of each other are live at
## the same moment and can fuse. Deliberate double-tap, never an accident.
func reaction_active() -> bool:
	return _fired and not _frozen and _elapsed < CHARGE_TIME + FIRE_TIME + FADE_TIME


func reaction_element() -> int:
	return element_id


func reaction_form() -> int:
	return ReactionTable.Form.BEAM


func reaction_owner() -> Node:
	return caster_node


## Pinned in place: still drawn at its current intensity, doing nothing.
func reaction_freeze() -> void:
	_frozen = true


## Released by a reaction that seized this beam and then could not stage itself.
## Without this the beam would hang frozen until it expired, which reads as the
## fusion grabbing it and then letting go for no reason.
func reaction_release() -> void:
	_frozen = false


## Spent by a reaction. Dismiss the muzzle sigil and go, WITHOUT the normal
## end-of-life beat — the beam did not land, it was eaten.
func reaction_consume() -> void:
	if _circle != null and is_instance_valid(_circle):
		_circle.vanish(0.12)
	queue_free()


## Muzzle-gather particles, per effect: frost = fast sharp shards that snap to
## a cold stop, fire = slow flickery embers, holy = drifting feathery motes,
## shadow = dark motes draining in, lightning = nervous static sparks,
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
		"shadow":
			# Slow dark motes fading to nothing — light being drained, not emitted.
			CombatVfx.spawn_burst(
				get_parent(), _origin, Color(0.45, 0.2, 0.75, 0.85), Color(0.05, 0.0, 0.1, 0.0),
				20, CHARGE_TIME, 25.0, 80.0, 1.2, 2.8
			)
		"lightning":
			# Fast sparks with hard damping — static snapping around the muzzle.
			CombatVfx.spawn_burst(
				get_parent(), _origin, Color(1.0, 0.95, 0.6, 0.95), fade,
				24, CHARGE_TIME * 0.7, 90.0, 200.0, 0.5, 1.4, 5.0, 9.0
			)
		_:
			CombatVfx.spawn_burst(
				get_parent(), _origin, Color(1, 1, 1, 0.9), fade,
				18, CHARGE_TIME, 30.0, 90.0, 1.0, 2.5
			)


func _process(delta: float) -> void:
	if _elapsed < 0.0 or _frozen:
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
	PostProcess.shock(0.6)  # a screen ripple rides the beam discharge (scaled, not the full ult warp)
	Sfx.play("beam", 1.0, 0.06)  # laser discharge
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
		"lightning":
			CombatVfx.spawn_burst(
				get_parent(), tip, Color(1.0, 1.0, 0.7, 0.95), fade,
				42, 0.32, 240.0, 560.0, 0.4, 1.3, 4.0, 8.0, true
			)
		"shadow":
			CombatVfx.spawn_burst(
				get_parent(), tip, Color(0.7, 0.45, 1.0, 0.95), Color(0.14, 0.05, 0.3, 0.0),
				44, 0.6, 90.0, 260.0, 1.2, 3.2, 1.0, 2.5, true
			)
		"earth":
			# Dusty chunky debris — NOT additive (reads as rock, not light).
			CombatVfx.spawn_burst(
				get_parent(), tip, Color(0.85, 0.62, 0.35, 0.9), Color(0.4, 0.28, 0.15, 0.0),
				30, 0.5, 70.0, 240.0, 1.6, 4.5
			)
			DebrisChunk.spawn_burst(get_parent(), tip, Color(0.5, 0.38, 0.22), 6, _dir, 240.0)
		"wind":
			CombatVfx.spawn_burst(
				get_parent(), tip, Color(0.72, 1.0, 0.92, 0.9), fade,
				40, 0.4, 210.0, 500.0, 0.6, 1.8, 2.0, 5.0, true
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
	for enemy: Node in targets_on_beam(_origin, _dir, _length, half, get_tree().get_nodes_in_group(target_group)):
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


## Deterministic 0..1 hash from an int — stable pseudo-random for drawn
## garnish (no RNG state, so redraws don't pop; feed quantized time for
## electric "snap" motion).
static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if _elapsed < CHARGE_TIME:
		_draw_charge_hint()
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
	# Per-element SILHOUETTE — each beam is a different shape, not a recolor.
	match _effect:
		"fire":
			# FIRE = two serpentine DRAGONS weaving around a thin spine (the hit
			# corridor is unchanged — this is a visual skin over the same line).
			_draw_beam_band(_origin, tip, w * 0.35, Color(core.r, core.g, core.b, 0.85 * intensity))
			_draw_fire_dragons(tip, w, intensity, c, core)
		"arcane":
			_draw_zoltraak_lance(tip, w, intensity, c, core)
		"shadow":
			_draw_umbral_void(tip, w, intensity, c, core)
		"lightning":
			_draw_tempest_torrent(tip, w, intensity, c, core)
		_:
			if _effect == "holy":
				# Extra-wide feathery halo — holy reads as radiance, not a laser.
				_draw_beam_band(_origin, tip, w * 2.7, Color(c.r, c.g, c.b, 0.12 * intensity))
			_draw_beam_band(_origin, tip, w * 1.8, Color(c.r, c.g, c.b, 0.28 * intensity))
			_draw_beam_band(_origin, tip, w * 1.0, Color(c.r, c.g, c.b, 0.7 * intensity))
			_draw_beam_band(_origin, tip, w * 0.4, Color(core.r, core.g, core.b, 0.95 * intensity))
			_draw_effect_detail(tip, w, intensity)
	# Muzzle flash + impact flash — per identity: shadow gets an IMPLOSION
	# (dark disc + violet ring, a white flash would break the light-eating
	# read); arcane gets a TIGHT surgical glint (a soft ball would blow out
	# the razor); everyone else keeps the classic hot ball.
	match _effect:
		"shadow":
			_draw_umbral_flashes(tip, w, intensity, core)
		"arcane":
			_draw_zoltraak_glints(tip, w, intensity, core)
		_:
			draw_circle(_origin, w * 1.4, Color(core.r, core.g, core.b, 0.5 * intensity), true, -1.0, true)
			draw_circle(tip, w * 1.2, Color(c.r, c.g, c.b, 0.5 * intensity), true, -1.0, true)
			draw_circle(tip, w * 0.6, Color(core.r, core.g, core.b, 0.6 * intensity), true, -1.0, true)
	# ICE = a hexagonal "freezing lens" flare at the muzzle (unmistakable ice read).
	if _effect == "frost":
		_draw_frost_lens(w, intensity, core)


## Charge-phase telegraph, charactered per element so the TELL already tells
## you what's coming: arcane = twin hairline rails compressing onto the cut
## line, shadow = the lane visibly DARKENS, lightning = a nervous jittering
## thread, everything else = the classic faint aiming line.
func _draw_charge_hint() -> void:
	if _elapsed < 0.0:
		return
	var tp: float = _elapsed / CHARGE_TIME
	var tip: Vector2 = _origin + _dir * _length
	var perp: Vector2 = _dir.orthogonal()
	match _effect:
		"arcane":
			# The razor's sheath forming: two rails squeeze toward the centreline.
			var gap: float = _width * (1.5 - 1.15 * tp)
			var rail: Color = Color(_color.r, _color.g, _color.b, 0.18 * tp)
			draw_line(_origin + perp * gap, tip + perp * gap, rail, 1.0, true)
			draw_line(_origin - perp * gap, tip - perp * gap, rail, 1.0, true)
		"shadow":
			# The world dims along the lane before the void rips open.
			draw_line(_origin, tip, Color(0.02, 0.0, 0.06, 0.35 * tp), _width * 0.9 * tp, true)
			draw_line(_origin, tip, Color(_color.r, _color.g, _color.b, 0.10 * tp), 2.0, true)
		"lightning":
			# A thin thread of static, snapping between positions.
			var tq: int = int(floorf(_elapsed * 30.0))
			var pts: PackedVector2Array = PackedVector2Array()
			for i: int in 13:
				var t: float = float(i) / 12.0
				var jag: float = (_hash01(i * 17 + tq * 31) * 2.0 - 1.0) * _width * 0.5 * sin(t * PI)
				pts.append(_origin.lerp(tip, t) + perp * jag)
			draw_polyline(pts, Color(_color.r, _color.g, _color.b, 0.20 * tp), 1.5, true)
		_:
			draw_line(_origin, tip, Color(_color.r, _color.g, _color.b, 0.12 * tp), 2.0, true)


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
		"lightning":
			return 0.6 + 0.4 * sin(_elapsed * 95.0)  # fast electric crackle
		"shadow":
			return 0.82 + 0.18 * sin(_elapsed * 18.0)  # slow ominous pulse
		"earth":
			return 1.0  # rock is steady, no shimmer
		"wind":
			return 0.88 + 0.12 * sin(_elapsed * 70.0)  # breezy flutter
		_:
			return 0.96 + 0.04 * sin(_elapsed * 60.0)  # arcane: razor stays near-rigid


## Hot-core tint per effect (the innermost band + flashes).
func _effect_core_color() -> Color:
	match _effect:
		"frost":
			return Color(1.4, 1.5, 1.7)  # HDR cores bloom
		"fire":
			return Color(1.8, 1.55, 1.0)
		"holy":
			return Color(1.85, 1.75, 1.45)
		"lightning":
			return Color(1.9, 1.7, 0.9)
		"shadow":
			return Color(1.5, 1.0, 1.9)
		"earth":
			return Color(1.7, 1.35, 0.85)
		"wind":
			return Color(1.35, 1.85, 1.7)
		_:
			return Color(1.6, 1.6, 1.7)


## Per-effect garnish drawn ALONG the beam for the skins that still use the
## generic band-stack: frost = crystalline shards jutting off the beam,
## holy = bobbing feathery motes. (Fire/arcane/shadow/lightning have whole
## bespoke silhouettes and never reach here.)
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
		"holy":
			for i: int in 8:
				var t: float = (float(i) + 0.5) / 8.0
				var p: Vector2 = _origin.lerp(tip, t) \
					+ perp * sin(_elapsed * 6.0 + float(i) * 1.7) * w * 1.4
				var ma: float = (0.35 + 0.25 * sin(_elapsed * 9.0 + float(i))) * intensity
				draw_circle(p, w * 0.4, Color(1.0, 0.97, 0.8, ma * 0.5), true, -1.0, true)
				draw_circle(p, w * 0.16, Color(1.0, 1.0, 0.95, ma), true, -1.0, true)


## ZOLTRAAK skin (arcane) — Frieren's razor: THIN, hard-edged, almost
## architectural (the visual opposite of the fire dragons). The interior is a
## DENSE dark magenta — brightness lives only at the rims, the racing edge
## glints and the arrowhead tip. The profile tapers toward the point (the
## speed read comes from shape + glints, not stamped symbols).
func _draw_zoltraak_lance(tip: Vector2, w: float, intensity: float, c: Color, core: Color) -> void:
	var perp: Vector2 = _dir.orthogonal()
	var head_len: float = minf(w * 5.0, _length * 0.14)
	var neck: Vector2 = tip - _dir * head_len
	# Tapering half-widths: base -> neck. THIN — a razor, not a slab.
	var e0: float = w * 0.5
	var e1: float = w * 0.34
	# Barely-there sheath hugging the blade.
	draw_line(_origin, neck, Color(c.r, c.g, c.b, 0.10 * intensity), w * 1.15, true)
	# Dense interior — deep SATURATED magenta, quiet enough that the rims cut
	# but clearly coloured (a near-black fill would read as umbral's cousin).
	draw_colored_polygon(PackedVector2Array([
		_origin + perp * e0, neck + perp * e1, neck - perp * e1, _origin - perp * e0,
	]), Color(c.r * 0.62, c.g * 0.4, c.b * 0.68, 0.92 * intensity))
	# Arrowhead: the one place the interior burns white — energy concentrates
	# at the leading edge.
	draw_colored_polygon(PackedVector2Array([
		neck + perp * e1, tip, neck - perp * e1,
	]), Color(core.r, core.g, core.b, 0.9 * intensity))
	# HDR razor rims converging on the point — the brightness belongs HERE.
	var rail: Color = Color(1.7, 1.25, 1.9, 0.9 * intensity)
	draw_polyline(PackedVector2Array([_origin + perp * e0, neck + perp * e1, tip]), rail, 1.5, true)
	draw_polyline(PackedVector2Array([_origin - perp * e0, neck - perp * e1, tip]), rail, 1.5, true)
	# Dim hairline filament down the middle — hints at the compressed core
	# without lighting up the interior.
	draw_line(_origin, neck, Color(core.r, core.g, core.b, 0.3 * intensity), w * 0.12, true)
	# Edge GLINTS: short ultra-fast highlights racing along each rim toward the
	# tip — unevenly spaced, swept; suggestions of speed, not road markings.
	for i: int in 3:
		var t0: float = fposmod(_hash01(i * 47 + 5) + _elapsed * (3.5 + 0.6 * float(i)), 1.0)
		var t1: float = minf(t0 + 0.05, 1.0)
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var a_pt: Vector2 = _origin.lerp(neck, t0) + perp * side * lerpf(e0, e1, t0)
		var b_pt: Vector2 = _origin.lerp(neck, t1) + perp * side * lerpf(e0, e1, t1)
		draw_line(a_pt, b_pt, Color(1.9, 1.6, 2.0, 0.85 * intensity), 2.2, true)


## UMBRAL skin (shadow) — light-EATER. The core is near-black and near-opaque:
## it VOIDS the background instead of adding light. The only emission is the
## violet fray gnawing its rim, a flickering anti-light seam trapped inside,
## and wisps of shadow peeling off and trailing BACKWARD against the flight.
## HDR lives in the rim + seam so it still blooms without becoming a glow tube.
func _draw_umbral_void(tip: Vector2, w: float, intensity: float, c: Color, core: Color) -> void:
	var perp: Vector2 = _dir.orthogonal()
	# Faint violet corona — the light the void hasn't finished eating.
	draw_line(_origin, tip, Color(c.r, c.g, c.b, 0.20 * intensity), w * 2.5, true)
	# Darkness bleeding OUTWARD over the corona in two steps: a gradient of
	# black eating the glow, so only the outermost fringe of violet survives.
	draw_line(_origin, tip, Color(0.02, 0.0, 0.06, 0.5 * intensity), w * 1.8, true)
	# THE VOID: near-opaque core, blacking out everything beneath it.
	draw_line(_origin, tip, Color(0.02, 0.0, 0.06, 0.92 * intensity), w * 1.1, true)
	# Frayed rims: two ragged HDR violet threads per side gnawing at the void's
	# edge (an inner bright fray + a dim outer echo for depth).
	var fray_col: Color = Color(1.25, 0.6, 2.0, 0.7 * intensity)
	var fray_dim: Color = Color(0.9, 0.4, 1.5, 0.35 * intensity)
	for side: float in [-1.0, 1.0]:
		var pts: PackedVector2Array = PackedVector2Array()
		var pts_out: PackedVector2Array = PackedVector2Array()
		var n: int = 26
		for i: int in n + 1:
			var t: float = float(i) / float(n)
			var gnaw: float = sin(t * 47.0 + _elapsed * 11.0 * side) * 0.45 \
				+ sin(t * 19.0 - _elapsed * 7.0) * 0.35 \
				+ sin(t * 83.0 + _elapsed * 17.0) * 0.20
			var p: Vector2 = _origin.lerp(tip, t)
			pts.append(p + perp * side * (w * 0.58 + gnaw * w * 0.30))
			pts_out.append(p + perp * side * (w * 0.95 + gnaw * w * 0.45))
		draw_polyline(pts, fray_col, 1.6, true)
		draw_polyline(pts_out, fray_dim, 1.3, true)
	# Anti-light seam: a HAIRLINE violet-white flicker trapped inside the
	# darkness — kept dim so the void stays a void, not a glow tube.
	var seam_a: float = (0.25 + 0.2 * sin(_elapsed * 24.0)) * intensity
	draw_line(_origin, tip, Color(core.r, core.g, core.b, seam_a), w * 0.1, true)
	# Peeling wisps: shadow flakes off the rim, curling backward and drifting
	# toward the muzzle (the beam sheds darkness against its own flight).
	for i: int in 10:
		var t: float = fposmod(_hash01(i * 31 + 7) - _elapsed * 0.45, 1.0)
		if t < 0.06 or t > 0.94:
			continue
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var curl: float = 0.6 + 0.8 * _hash01(i * 13)
		var root: Vector2 = _origin.lerp(tip, t) + perp * side * w * 0.58
		draw_polyline(PackedVector2Array([
			root,
			root - _dir * w * 0.9 + perp * side * w * 0.5 * curl,
			root - _dir * w * 2.0 + perp * side * w * 1.2 * curl,
		]), Color(c.r * 1.3, c.g, c.b * 1.5, 0.65 * intensity * sin(t * PI)), 2.2, true)


## Arcane endpoint treatment: TIGHT, hard, small — a pin-point flash + thin
## cross glints at muzzle and tip, keeping the surgical read (never a soft
## ball wider than the beam itself).
func _draw_zoltraak_glints(tip: Vector2, w: float, intensity: float, core: Color) -> void:
	var perp: Vector2 = _dir.orthogonal()
	var g: Color = Color(1.9, 1.7, 2.0, 0.9 * intensity)
	draw_circle(_origin, w * 0.42, Color(core.r, core.g, core.b, 0.9 * intensity), true, -1.0, true)
	draw_line(_origin - perp * w * 1.5, _origin + perp * w * 1.5, g, 1.4, true)
	draw_line(_origin - _dir * w * 0.9, _origin + _dir * w * 0.9, g, 1.4, true)
	draw_circle(tip, w * 0.35, Color(core.r, core.g, core.b, 0.85 * intensity), true, -1.0, true)
	draw_line(tip - perp * w * 1.1, tip + perp * w * 1.1, g, 1.2, true)


## Shadow endpoint treatment: dark discs ringed in HDR violet — an IMPLOSION
## read at muzzle and tip, replacing the white-hot flashes every other beam
## gets (a bright flash would betray the light-eating identity).
func _draw_umbral_flashes(tip: Vector2, w: float, intensity: float, core: Color) -> void:
	var ring: Color = Color(1.25, 0.6, 2.0, 0.8 * intensity)
	var pulse: float = 1.0 + 0.12 * sin(_elapsed * 20.0)
	draw_circle(_origin, w * 1.25, Color(0.03, 0.0, 0.08, 0.75 * intensity), true, -1.0, true)
	draw_arc(_origin, w * 1.4 * pulse, 0.0, TAU, 40, ring, 2.0, true)
	draw_circle(tip, w * 1.1, Color(0.03, 0.0, 0.08, 0.7 * intensity), true, -1.0, true)
	draw_arc(tip, w * 1.3 * pulse, 0.0, TAU, 40, ring, 2.0, true)
	draw_circle(tip, w * 0.35, Color(core.r, core.g, core.b, 0.7 * intensity), true, -1.0, true)


## TEMPEST skin (lightning) — NOT a solid beam: a braided storm torrent. Four
## turbulent strands helix around the damage corridor in counter-phase, with a
## time-QUANTIZED crackle jitter so they SNAP like electricity instead of
## swaying like water; spark debris streaks race down the lane and jagged
## forks strobe off the braid. Only a faint haze marks the true hit corridor.
func _draw_tempest_torrent(tip: Vector2, w: float, intensity: float, c: Color, core: Color) -> void:
	var perp: Vector2 = _dir.orthogonal()
	var tq: int = int(floorf(_elapsed * 32.0))  # quantized time — electric snap
	# Faint corridor haze — the only hint of the actual damage lane.
	draw_line(_origin, tip, Color(c.r, c.g, c.b, 0.10 * intensity), w * 2.1, true)
	# Braided strands, converging at muzzle and tip (a torrent, not a tube).
	var n: int = 30
	for s: int in 4:
		var phase: float = TAU * float(s) / 4.0
		var freq: float = 2.4 + 0.7 * float(s)
		var amp: float = w * (0.8 + 0.35 * _hash01(s * 71 + 3))
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in n + 1:
			var t: float = float(i) / float(n)
			var env: float = 0.3 + 0.7 * sin(t * PI)
			var off: float = sin(TAU * t * freq - _elapsed * (15.0 + 2.5 * float(s)) + phase) * amp * env
			off += (_hash01(i * 7 + s * 131 + tq * 17) * 2.0 - 1.0) * w * 0.38 * env
			pts.append(_origin.lerp(tip, t) + perp * off)
		draw_polyline(pts, Color(c.r, c.g, c.b, 0.45 * intensity), w * 0.30, true)
		draw_polyline(pts, Color(core.r, core.g, core.b, 0.8 * intensity), w * 0.12, true)
	# Spark debris streaking down the torrent (reads as carried wind-borne grit).
	for i: int in 12:
		var t: float = fposmod(_hash01(i * 53 + 11) + _elapsed * (1.5 + _hash01(i * 3) * 0.9), 1.0)
		var drift: float = (_hash01(i * 29 + tq) * 2.0 - 1.0) * w * 0.9
		var p: Vector2 = _origin.lerp(tip, t) + perp * drift
		draw_line(p - _dir * w * 1.4, p + _dir * w * 0.7,
			Color(1.9, 1.8, 1.1, 0.8 * intensity * sin(t * PI)), 1.8, true)
	# Jagged forks flicking off the braid — hash-gated so they strobe on/off.
	for i: int in 3:
		if _hash01(i * 397 + tq) < 0.45:
			continue
		var t: float = 0.2 + 0.6 * _hash01(i * 211 + tq * 7)
		var side: float = -1.0 if _hash01(i * 61 + tq) < 0.5 else 1.0
		var base_p: Vector2 = _origin.lerp(tip, t)
		var out: Vector2 = perp * side
		draw_polyline(PackedVector2Array([
			base_p,
			base_p + out * w * 0.9 + _dir * w * 0.5,
			base_p + out * w * 1.5 - _dir * w * 0.2,
			base_p + out * w * 2.4 + _dir * w * 0.4,
		]), Color(1.9, 1.7, 0.9, 0.8 * intensity), 1.8, true)


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
	if (b - a).length() < 0.001:
		return
	# A thick ANTIALIASED line = a round-profile capsule with smooth edges and
	# round caps — a cleaner, rounder beam than the old flat aliased quad
	# (draw_colored_polygon has no AA arg; draw_line does).
	draw_line(a, b, col, thick, true)
