class_name ShadowRoot
extends Node2D
## SHADOW ROOT — the Warlock's shadow signature, reworked per the maker's ask:
## shadows ERUPT FROM the stick figure itself and race along the ground toward
## the aim, then SNAP upward and ROOT whoever they catch in place. This is a
## different SHAPE of spell from a placed ground zone (which is why it is not
## ZoneSpell): the threat travels from the caster, telegraphs its grasp point,
## and gives a GENUINE dodge window (overhaul rule 2) — step off the mark or
## jump over the tendrils during the surge and it closes on empty air.
##
## The immobilise deliberately REUSES the existing status path instead of
## inventing a parallel CC system: apply_status(EARTH) drives StatusComponent's
## direct-root channel (freeze timer -> is_hard_cc() -> the Enemy suppresses
## attacks + freezes its rig), refreshed each REAPPLY_EVERY while the grip
## holds; apply_status(SHADOW) layers Weaken on top AND — applied last — sets
## the ailment overlay tint violet so the root reads as shadow, not ice/earth.
## The residual 32% freeze-drift is pinned by easing the victim back to its
## catch anchor, so "rooted" means rooted.
##
## Look: it EATS light — near-black cores voiding the background with a violet
## fray at the edges; HDR is reserved for sparse eruption sparks so bloom
## accents the darkness instead of washing it out.

const SURGE_TIME: float = 0.5      # the dodge window: cast -> lock, in seconds
const GRIP_TIME: float = 1.5       # how long a caught victim stays rooted
const RETRACT_TIME: float = 0.35   # tendrils sink back into the ground
const WHIFF_HOLD: float = 0.45     # claws grasp at air before retracting
const SNAP_FLASH: float = 0.14     # dark implosion beat at the lock moment
const REAPPLY_EVERY: float = 0.25  # refresh cadence for the EARTH root channel
const REAPPLY_CUTOFF: float = 0.55 # stop refreshing this early so the shatter
								   # ("breaks free") lands with the release
const CATCH_HEIGHT: float = 100.0  # jump higher than this above the lock = dodged
const MIN_RUN: float = 130.0       # tendrils always travel at least this far
const MAX_RUN: float = 460.0       # and never further than this
const CLAWS: int = 5               # tendrils per grasp

var element_id: int = Elements.Element.SHADOW

var _origin: Vector2 = Vector2.ZERO   # caster's feet (floor-snapped)
var _lock: Vector2 = Vector2.ZERO     # grasp point (floor-snapped)
var _color: Color = Color(0.6, 0.35, 0.9)
var _catch_r: float = 64.0            # horizontal half-width of the grasp
var _damage: int = 26
var _effect: String = "shadow"
var _elapsed: float = 0.0
var _snapped: bool = false
var _victims: Array[Dictionary] = []  # {node: Node2D, anchor: Vector2}
var _reapply_t: float = 0.0
var _seed: PackedFloat32Array = PackedFloat32Array()


## Entry point, mirroring the other spell scripts' single driver method:
## `origin` = caster position, `aim` = target-relative vector (target - caster).
## `radius` is the grasp half-width, `damage` the one-shot catch damage.
func erupt(
	origin: Vector2, aim: Vector2, color: Color, radius: float,
	damage: int, effect: String = "shadow"
) -> void:
	_color = color
	_catch_r = maxf(radius, 40.0)
	_damage = damage
	_effect = effect
	global_position = Vector2.ZERO
	var dir_sign: float = signf(aim.x)
	if dir_sign == 0.0:
		dir_sign = 1.0
	var run: float = clampf(absf(aim.x), MIN_RUN, MAX_RUN)
	_origin = _floor_snap(origin)
	_lock = _floor_snap(_origin + Vector2(dir_sign * run, -24.0))
	for i: int in 24:
		_seed.append(randf())
	# Eruption beat AT the caster — the spell visibly comes FROM the figure.
	CombatVfx.spawn_burst(get_parent(), _origin + Vector2(0.0, -6.0),
		Color(0.16, 0.04, 0.24, 0.9), Color(0.05, 0.0, 0.1, 0.0),
		12, 0.4, 60.0, 160.0, 0.8, 1.8, 0.0, 0.0, false,
		Vector2(dir_sign, -0.4), 40.0)
	Juice.shake_camera(3.0)
	Sfx.play("cast", -4.0, 0.1)
	queue_redraw()


## Drop a point onto the floor below it (world layer 1) so the tendrils hug
## the ground on slopes/platforms. Falls back to the input when nothing is hit
## (headless tests without physics still get sane geometry).
func _floor_snap(from: Vector2) -> Vector2:
	var world: World2D = get_world_2d()
	if world == null:
		return from
	var query := PhysicsRayQueryParameters2D.create(from + Vector2(0.0, -8.0), from + Vector2(0.0, 300.0), 1)
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else from


func _process(delta: float) -> void:
	_elapsed += delta
	if not _snapped and _elapsed >= SURGE_TIME:
		_snap()
	if _snapped and not _victims.is_empty():
		_hold_grip(delta)
	var hold: float = GRIP_TIME if not _victims.is_empty() else WHIFF_HOLD
	if _elapsed >= SURGE_TIME + hold + RETRACT_TIME:
		queue_free()
		return
	queue_redraw()


## The lock moment: whoever is still standing on the mark (and near the ground —
## airborne bodies above CATCH_HEIGHT have jumped the tendrils) gets caught.
func _snap() -> void:
	_snapped = true
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not e is Node2D or not is_instance_valid(e):
			continue
		var n: Node2D = e as Node2D
		if absf(n.global_position.x - _lock.x) > _catch_r:
			continue  # stepped off the mark during the surge — dodged
		var lift: float = _lock.y - n.global_position.y
		if lift > CATCH_HEIGHT or lift < -40.0:
			continue  # jumped over the tendrils (or on another floor) — dodged
		if e.has_method("take_damage"):
			e.take_damage(_damage, Color(_color.r, _color.g, _color.b, 1.0))
		if e.has_method("apply_status"):
			# EARTH first = the direct-root channel; SHADOW last = Weaken + the
			# violet overlay tint (StatusComponent tints from the LAST element).
			e.apply_status(Elements.Element.EARTH)
			e.apply_status(Elements.Element.SHADOW)
		_victims.append({"node": n, "anchor": n.global_position})
	# Dark implosion beat — heavier when something was actually caught.
	var caught: bool = not _victims.is_empty()
	CombatVfx.spawn_burst(get_parent(), _lock + Vector2(0.0, -10.0),
		Color(0.12, 0.02, 0.2, 0.95), Color(0.03, 0.0, 0.07, 0.0),
		18 if caught else 10, 0.45, 80.0, 220.0, 0.9, 2.0, 0.0, 0.0, false,
		Vector2.UP, 55.0)
	# A few HDR violet sparks so the eruption pops under bloom without glowing.
	var em: Color = Elements.emissive(element_id)
	CombatVfx.spawn_burst(get_parent(), _lock + Vector2(0.0, -12.0),
		em, Color(_color.r, _color.g, _color.b, 0.0),
		8, 0.3, 100.0, 240.0, 0.4, 1.0, 0.0, 0.0, true, Vector2.UP, 40.0)
	if caught:
		Juice.impact_frame(0.5, _lock)
		Juice.shake_camera(7.0)
		Sfx.play("spell_impact", -3.0, 0.1)
	else:
		Sfx.play("cast", -8.0, 0.3)  # a hollow whiff, quieter than the cast


## While the grip holds: refresh the EARTH root (until near the end, so the
## release shatter lands ON the release) and pin the residual freeze-drift
## back to the catch anchor. Gravity keeps owning y — only x is pinned.
func _hold_grip(delta: float) -> void:
	var t_grip: float = _elapsed - SURGE_TIME
	_reapply_t -= delta
	var refresh: bool = _reapply_t <= 0.0 and t_grip < GRIP_TIME - REAPPLY_CUTOFF
	if refresh:
		_reapply_t = REAPPLY_EVERY
	for v: Dictionary in _victims:
		var n: Node2D = v["node"] as Node2D
		if n == null or not is_instance_valid(n):
			continue
		if refresh and n.has_method("apply_status"):
			n.apply_status(Elements.Element.EARTH)
			n.apply_status(Elements.Element.SHADOW)
		var anchor: Vector2 = v["anchor"] as Vector2
		n.global_position.x = lerpf(n.global_position.x, anchor.x, minf(1.0, 14.0 * delta))


func _draw() -> void:
	var hold: float = GRIP_TIME if not _victims.is_empty() else WHIFF_HOLD
	var fade: float = 1.0
	var t_end: float = SURGE_TIME + hold
	if _elapsed >= t_end:
		fade = clampf(1.0 - (_elapsed - t_end) / RETRACT_TIME, 0.0, 1.0)
	_draw_vein(fade)
	if not _snapped:
		_draw_telegraph()
	else:
		_draw_snap_flash()
		var k: float = fade
		if _victims.is_empty():
			for i: int in CLAWS:
				_draw_claw(_lock, i, 46.0, k)
		else:
			for v: Dictionary in _victims:
				var n: Node2D = v["node"] as Node2D
				if n == null or not is_instance_valid(n):
					continue
				_draw_grip(n.global_position, k)


## The dark vein racing along the floor from the caster to the grasp point —
## a near-black core polyline with a violet fray and sprouting spikes, so the
## PATH of the threat is readable the whole way (the telegraph you can outrun).
func _draw_vein(fade: float) -> void:
	var p: float = clampf(pow(_elapsed / SURGE_TIME, 0.8), 0.0, 1.0)  # front-loaded race
	var head: Vector2 = _origin.lerp(_lock, p)
	var pts := PackedVector2Array()
	for k: int in 18:
		var u: float = float(k) / 17.0
		var at: Vector2 = _origin.lerp(head, u)
		at.y += sin(_seed[k % 24] * TAU + _elapsed * 10.0 + u * 9.0) * 2.0
		pts.append(at)
	# The dark core alone vanishes on a dark arena — the violet FRAY defines the
	# void's edge, so it gets a wide dim halo + a bright thin rim.
	draw_polyline(pts, Color(0.4, 0.18, 0.7, 0.22 * fade), 10.0, true)
	draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.95 * fade), 6.0, true)
	draw_polyline(pts, Color(0.62, 0.34, 1.0, 0.6 * fade), 2.0, true)
	# Spikes sprouting along the traversed path, writhing, taller near the head.
	for i: int in 10:
		var f: float = _seed[i] * 0.9 + 0.05
		if f > p:
			continue
		var base: Vector2 = _origin.lerp(_lock, f)
		var near_head: float = 1.0 - clampf(absf(p - f) * 3.0, 0.0, 0.7)
		var sh: float = (5.0 + 9.0 * _seed[i + 10]) * (0.5 + 0.5 * near_head)
		var sway: float = sin(_elapsed * 8.0 + _seed[i] * TAU) * 2.5
		var tip: Vector2 = base + Vector2(sway, -sh)
		draw_line(base + Vector2(-2.0, 0.0), tip, Color(0.05, 0.01, 0.1, 0.85 * fade), 2.2, true)
		draw_line(base + Vector2(2.0, 0.0), tip, Color(0.55, 0.28, 0.9, 0.55 * fade), 1.3, true)
	if not _snapped:
		# The racing head: a dark bulge ringed in violet with HDR sparks — the
		# unmissable "it's coming for you" of the surge.
		draw_circle(head, 10.0, Color(0.4, 0.18, 0.7, 0.25), true, -1.0, true)
		draw_circle(head, 8.0, Color(0.04, 0.0, 0.09, 0.95), true, -1.0, true)
		draw_arc(head, 10.5, 0.0, TAU, 20, Color(0.7, 0.4, 1.05, 0.75), 1.8, true)
		var em: Color = Elements.emissive(element_id)
		for i: int in 5:
			var off := Vector2(sin(_elapsed * 22.0 + float(i) * 2.1) * 7.0,
				-3.0 - 6.0 * _seed[(i + 20) % 24])
			draw_circle(head + off, 1.5, Color(em.r, em.g, em.b, 0.85), true, -1.0, true)


## The grasp-point telegraph during the surge: a gathering dark pool + a violet
## ring CONVERGING onto the mark. Converging (not expanding) = "get off this
## spot NOW" — the classic incoming-lock tell, ending exactly at SURGE_TIME.
func _draw_telegraph() -> void:
	var p: float = clampf(_elapsed / SURGE_TIME, 0.0, 1.0)
	draw_set_transform(_lock, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, _catch_r * (0.3 + 0.7 * p),
		Color(0.02, 0.0, 0.05, 0.45 * p), true, -1.0, true)
	draw_arc(Vector2.ZERO, _catch_r * (0.3 + 0.7 * p), 0.0, TAU, 32,
		Color(0.55, 0.28, 0.9, 0.5 * p), 1.6, true)
	draw_arc(Vector2.ZERO, _catch_r * (2.0 - p), 0.0, TAU, 40,
		Color(0.7, 0.4, 1.0, 0.20 + 0.5 * p), 2.2, true)
	# Cracks racing inward toward the mark — the floor is giving way HERE.
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0 + _seed[i] * 0.8
		var outer: Vector2 = Vector2.from_angle(a) * _catch_r * (1.6 - 0.55 * p)
		var inner: Vector2 = Vector2.from_angle(a) * _catch_r * (1.1 - 0.55 * p)
		draw_line(outer, inner, Color(0.5, 0.22, 0.8, 0.6 * p), 1.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The lock moment voids the background for a beat: a big dark disc + a violet
## fray ring bursting outward — "the light went out there".
func _draw_snap_flash() -> void:
	var t: float = _elapsed - SURGE_TIME
	if t > SNAP_FLASH:
		return
	var k: float = 1.0 - t / SNAP_FLASH
	draw_set_transform(_lock, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, _catch_r * 1.7, Color(0.01, 0.0, 0.03, 0.45 * k), true, -1.0, true)
	draw_arc(Vector2.ZERO, _catch_r * (1.0 + 1.2 * (1.0 - k)), 0.0, TAU, 40,
		Color(0.75, 0.45, 1.05, 0.7 * k), 2.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One erupted claw grasping at air (the whiff read) — dark, curling, violet-edged.
func _draw_claw(base: Vector2, i: int, height: float, k: float) -> void:
	var spread: float = (float(i) / float(CLAWS - 1) - 0.5) * 2.0  # -1..1 fan
	var wob: float = sin(_elapsed * 7.0 + _seed[i] * TAU)
	var tip: Vector2 = base + Vector2(spread * _catch_r * 0.5 + wob * 3.0,
		-height * (0.75 + 0.4 * _seed[i + 5]))
	var mid: Vector2 = base + Vector2(spread * _catch_r * 0.75, -height * 0.45)
	var pts := PackedVector2Array()
	for s: int in 8:
		var u: float = float(s) / 7.0
		var q: Vector2 = base.lerp(mid, u).lerp(mid.lerp(tip, u), u)  # quadratic bezier
		q.x += sin(_elapsed * 9.0 + u * 5.0 + _seed[i] * TAU) * 2.0 * u
		pts.append(q)
	draw_polyline(pts, Color(0.03, 0.0, 0.07, 0.9 * k), 4.0, true)
	draw_polyline(pts, Color(0.5, 0.25, 0.85, 0.4 * k), 1.3, true)


## Shadow visibly gripping a rooted victim: a light-eating disc behind them, a
## dark pool at their feet, claws wrapping up around the legs, orbiting motes.
func _draw_grip(at: Vector2, k: float) -> void:
	var foot: Vector2 = Vector2(at.x, _lock.y)
	# Eats light: a soft near-black disc voiding the background behind the body,
	# defined against the dark arena by a faint violet fray at its edge.
	draw_circle(at, 44.0, Color(0.02, 0.0, 0.05, 0.34 * k), true, -1.0, true)
	draw_arc(at, 44.0, 0.0, TAU, 32, Color(0.5, 0.25, 0.85, 0.16 * k), 1.6, true)
	draw_set_transform(foot, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 26.0, Color(0.02, 0.0, 0.05, 0.5 * k), true, -1.0, true)
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 24, Color(0.45, 0.2, 0.75, 0.35 * k), 1.4, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Claws wrap from the ground up around the lower body.
	var wrap_h: float = maxf(foot.y - at.y + 16.0, 30.0)
	for i: int in CLAWS:
		_draw_claw(foot, i, wrap_h, k)
	# Orbiting dark motes — the grip is ALIVE, not a decal.
	for i: int in 3:
		var a: float = _elapsed * (2.0 + 0.6 * float(i)) + _seed[i + 15] * TAU
		var orb: Vector2 = at + Vector2(cos(a) * 16.0, sin(a) * 9.0 + 6.0)
		draw_circle(orb, 2.2, Color(0.08, 0.01, 0.14, 0.8 * k), true, -1.0, true)
		draw_circle(orb, 1.0, Color(0.55, 0.3, 0.9, 0.5 * k), true, -1.0, true)
