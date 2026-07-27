class_name BladeFlurry
extends Node2D
## Shadowblade ALT — BLADE FLURRY (SpellDef.Kind.FLURRY). A blur of dashing crescent
## slashes fans across the front of the hero; each slash cuts every enemy in the
## forward arc (multi-hit + Weaken + a shove). Mobility/burst read — a flurry of
## blades, not a beam or a meteor. Draws in world coordinates over a short window.
##
## Phase-2 redesign: the flurry used to be two `draw_arc` bands per slash, which
## read as a flat uniform ribbon — a highlighter stroke, not a cut. Every slash is
## now a tapered CRESCENT polygon (needle points at both tips, widest mid-arc) in
## three stacked passes — a soft element-tinted ghost, a saturated body, and a
## thin HDR white-hot core that clears 1.0 so the bloom catches only the edge.
## Consecutive slashes ALTERNATE sweep direction and sit at staggered radii, so
## the five cuts cross each other instead of nesting like tree rings, and each
## leaves a thinning afterimage. The caster's COIL windup (CastStyle) is the
## telegraph; the slashes themselves stay as fast as they always were.

const RANGE: float = 100.0
const ARC_DOT: float = 0.15      # forward cone (dot(dir, to_enemy) >= this)
const LIFE: float = 0.42
const KNOCKBACK: float = 150.0
const SLASH_VISIBLE: float = 0.18
const SLASH_SPAN: float = 0.60   # half-angle of a crescent, radians
const SLASH_THICKNESS: float = 15.0
const SLASH_SWEEP: float = 0.55  # radians a crescent travels over its visible life
const CRESCENT_STEPS: int = 18

var element_id: int = Elements.Element.SHADOW
var _origin: Vector2 = Vector2.ZERO
var _dir: Vector2 = Vector2.RIGHT
var _color: Color = Color(0.6, 0.35, 0.95, 1.0)
var _dmg: int = 18
var _count: int = 5
var _elapsed: float = -1.0
var _hit_at: PackedFloat32Array = PackedFloat32Array()
var _fired: int = 0


func flurry(origin: Vector2, aim: Vector2, color: Color, damage: int = 18, count: int = 5, _effect: String = "shadow") -> void:
	_origin = origin
	_dir = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	_color = color
	_dmg = damage
	_count = maxi(count, 3)
	for i in _count:
		_hit_at.append(LIFE * (0.1 + 0.8 * float(i) / float(_count)))
	global_position = Vector2.ZERO
	_elapsed = 0.0
	Juice.hit_stop(0.05)
	Juice.shake_camera(5.0)
	Sfx.play("melee_swing", 0.0, 0.05)
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	while _fired < _hit_at.size() and _elapsed >= _hit_at[_fired]:
		_fired += 1
		_slash()
	if _elapsed >= LIFE:
		queue_free()
		return
	queue_redraw()


## One slash: cut every enemy in the forward cone within RANGE.
func _slash() -> void:
	var tint: Color = Color(_color.r, _color.g, _color.b, 1.0)
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not e is Node2D or not is_instance_valid(e):
			continue
		var to: Vector2 = (e as Node2D).global_position - _origin
		if to.length() > RANGE or _dir.dot(to.normalized()) < ARC_DOT:
			continue
		if e.has_method("take_damage"):
			e.take_damage(_dmg, tint)
		if e.has_method("apply_status"):
			e.apply_status(element_id)
		if e.has_method("apply_knockback"):
			e.apply_knockback(_dir * KNOCKBACK)
	for prop: Node in get_tree().get_nodes_in_group("destructible"):
		if prop is Node2D and _origin.distance_to((prop as Node2D).global_position) <= RANGE and prop.has_method("take_damage"):
			prop.take_damage(_dmg)
	Sfx.play("melee_hit", -4.0, 0.1)
	CombatVfx.spawn_burst(get_parent(), _origin + _dir * RANGE * 0.6,
		Color(_color.r, _color.g, _color.b, 0.9), Color(_color.r, _color.g, _color.b, 0.0),
		8, 0.25, 60.0, 150.0, 0.6, 1.6, 0.0, 0.0, true)


## A slash shape: widest mid-arc, tapering to needle points at both tips. Walks
## the outer edge left tip -> right tip, then the inner edge back, so the result
## is one closed lens. `sin(t * PI)` is the taper — 0 at the tips, 1 at centre.
## draw_arc can't do this: its band is a constant width, which is exactly why
## the old flurry read as a ribbon instead of a blade.
func _crescent(radius: float, mid_angle: float, thickness: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in CRESCENT_STEPS + 1:
		var t: float = float(i) / float(CRESCENT_STEPS)
		var a: float = mid_angle - SLASH_SPAN + 2.0 * SLASH_SPAN * t
		pts.append(_origin + Vector2.from_angle(a) * (radius + thickness * 0.5 * sin(t * PI)))
	for i in CRESCENT_STEPS + 1:
		var t: float = 1.0 - float(i) / float(CRESCENT_STEPS)
		var a: float = mid_angle - SLASH_SPAN + 2.0 * SLASH_SPAN * t
		pts.append(_origin + Vector2.from_angle(a) * (radius - thickness * 0.5 * sin(t * PI)))
	return pts


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var ang: float = _dir.angle()
	var emissive: Color = Elements.emissive(element_id)
	for i in _count:
		var age: float = _elapsed - _hit_at[i]
		if age < 0.0 or age > SLASH_VISIBLE:
			continue
		var life: float = age / SLASH_VISIBLE
		var intensity: float = 1.0 - life * life        # ease-out: the cut lingers, then snaps away
		var t: float = _hit_at[i] / LIFE
		# Alternate the sweep direction so consecutive cuts CROSS rather than nest.
		var side: float = 1.0 if i % 2 == 0 else -1.0
		# The offset has to clear a full crescent (SLASH_SPAN) or the cuts merge
		# into one thick band instead of crossing.
		var mid: float = ang + side * (SLASH_SPAN + 0.22 * t) - side * SLASH_SWEEP * (0.5 - life)
		# Staggered radii keep five slashes from stacking; the base pushes the cuts
		# out IN FRONT of the caster rather than wrapping around the body.
		var r: float = RANGE * (0.72 + 0.34 * t + 0.09 * sin(float(i) * 2.4))
		var thick: float = SLASH_THICKNESS * (0.55 + 0.45 * intensity)
		# 1) soft ghost — the wide element-tinted smear that sells the motion blur.
		draw_colored_polygon(_crescent(r, mid, thick * 2.3),
			Color(_color.r, _color.g, _color.b, 0.20 * intensity))
		# 2) body — the saturated blade.
		draw_colored_polygon(_crescent(r, mid, thick),
			Color(_color.r * 1.25, _color.g * 1.15, _color.b * 1.35, 0.80 * intensity))
		# 3) core — thin, over 1.0, so bloom catches the EDGE and not the whole smear.
		draw_colored_polygon(_crescent(r, mid, thick * 0.28),
			Color(emissive.r, emissive.g, emissive.b, 0.95 * intensity))
		# Tip glints: the two points of the cut catch the light hardest.
		for tip_side: float in [-1.0, 1.0]:
			var tip: Vector2 = _origin + Vector2.from_angle(mid + tip_side * SLASH_SPAN) * r
			draw_circle(tip, 2.6 * intensity, Color(emissive.r, emissive.g, emissive.b,
				0.85 * intensity))
