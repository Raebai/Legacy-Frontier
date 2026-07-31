class_name VoidCollapse
extends Node2D
## THE VOID — Tier 3 boss drop, one charge. A singularity opens where you marked,
## drags the room into it, and closes. What was inside is gone. Allies included.
##
## THREE BEATS, and the middle one is what makes it a decision rather than a
## damage number:
##   OPEN     — a black disc with a bright event horizon. Loud, unmistakable, and
##              `PULL_TIME` long. If you cast this on top of your own team they
##              have that long to run, and they are being pulled the wrong way.
##   PULL     — every body in `PULL_RADIUS` is accelerated toward the centre. That
##              is the "answer" the spec demands every big spell have: a dash out
##              of the pull beats it, standing still does not.
##   COLLAPSE — one query at `radius`, full damage, no falloff. Anything inside
##              takes all of it.
##
## ⚠ NO FALLOFF IS DELIBERATE. Falloff would let a player hug the edge and pay a
## fraction, which turns a catastrophe into a resource-management problem. The
## spell is either something you were inside or something you were not.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.SHADOW
var caster_node: Node = null
var spell_tier: int = SpellTier.Tier.ULT

## The window between the singularity appearing and it closing. Long, because this
## is a one-charge boss drop and the whole room needs to be able to react to it.
## UNTESTED FEEL GUESS: 0.9 is well beyond the longest telegraph in the class kits
## (Heaven's Verdict channels 1.3 but its FOOTPRINT lands instantly).
const PULL_TIME: float = 0.9
## How far the drag reaches — wider than the kill radius on purpose, so the spell
## pulls people INTO a zone they were safely outside of. That is the trap, and it
## is visible: the pull ring is drawn.
const PULL_RADIUS_SCALE: float = 1.9
## Acceleration applied toward the centre, px/s^2 at the rim, scaling up to 2x at
## the core. Comparable to gravity so it is a real fight and not a tractor beam.
const PULL_ACCEL: float = 1500.0
const CLOSE_TIME: float = 0.28
const CORE_COLOR: Color = Color(0.02, 0.0, 0.05)
const HORIZON_COLOR: Color = Color(0.85, 0.45, 1.6)   # HDR — this one blooms

var _center: Vector2 = Vector2.ZERO
var _radius: float = 185.0
var _damage: int = 260
var _color: Color = Color(0.6, 0.3, 0.9)
var _elapsed: float = 0.0
var _collapsed: bool = false
var _seed: int = 0


func cataclysm(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_center = target
	_radius = maxf(spell.radius, 30.0)
	_damage = spell.damage
	_color = color
	_seed = randi()
	global_position = Vector2.ZERO
	process_physics_priority = 200   # pull AFTER bodies have integrated their own motion
	SpellSigil.open(self, _center, color, maxf(_radius * 1.4, 30.0) / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.14, 0.6)
	SpellDrops.sfx("void_pull", -1.0, 0.05, 0.55)
	Juice.zoom_pull_camera(0.26, 1.0, 0.22, 0.8)
	Juice.shake_camera(9.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if not _collapsed:
		_pull(delta)
		if _elapsed >= PULL_TIME:
			_collapse()
	elif _elapsed >= PULL_TIME + CLOSE_TIME:
		queue_free()
		return
	queue_redraw()


## Drag everything toward the centre. Uses the raw group rather than `hostiles()`:
## the pull is not damage, and a singularity that politely refuses to tug its own
## summoner would give the spell an obvious safe spot at its worst moment.
func _pull(delta: float) -> void:
	var reach: float = _radius * PULL_RADIUS_SCALE
	for n: Node in get_tree().get_nodes_in_group(target_group):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or not (n is Node2D):
			continue
		var to: Vector2 = _center - (n as Node2D).global_position
		var d: float = to.length()
		if d > reach or d < 1.0:
			continue
		var v: Variant = n.get(&"velocity")
		if v == null or not (v is Vector2):
			continue
		# Stronger the closer you already are — the last stretch is the one you
		# cannot walk out of, which is what makes the dash the answer and not
		# holding a movement key.
		var strength: float = PULL_ACCEL * lerpf(2.0, 1.0, clampf(d / reach, 0.0, 1.0))
		n.set(&"velocity", (v as Vector2) + to.normalized() * strength * delta)


func _collapse() -> void:
	_collapsed = true
	var tint := Color(HORIZON_COLOR.r, HORIZON_COLOR.g, HORIZON_COLOR.b, 1.0)
	for n: Node in SpellTargets.in_radius(_center, _radius,
			SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self):
		SpellTargets.hurt(n, _damage, tint)
		if n.has_method("apply_status"):
			n.apply_status(element_id)
	for prop: Node in SpellTargets.in_radius(_center, _radius,
			get_tree().get_nodes_in_group("destructible"), [caster_node], self):
		if prop.has_method("take_damage"):
			prop.call("take_damage", _damage)
	CombatVfx.spawn_burst(get_parent(), _center, Color(1.6, 0.9, 2.0, 1.0),
		Color(0.1, 0.0, 0.16, 0.0), 40, 0.6, 30.0, 320.0, 1.6, 5.0, 0.0, 0.0, true)
	ScorchDecal.spawn(get_parent(), _center, _radius * 0.7, "burn",
		Color(0.12, 0.02, 0.18, 0.7), 9.0)
	Juice.on_hit({"shake": 26.0, "zoom": 0.2, "sfx": "ult_unmaking", "sfx_pitch": -0.1,
		"hitstop": 0.16})
	PostProcess.shock(0.9, Juice.world_to_uv(_center))
	Juice.tier_frame(SpellTier.Tier.ULT, _center, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if _collapsed:
		_draw_close()
		return
	var t: float = clampf(_elapsed / PULL_TIME, 0.0, 1.0)
	# The PULL ring, drawn honestly at the radius that actually tugs you. Bigger
	# than the kill ring, and that is the trap being shown rather than hidden.
	draw_arc(_center, _radius * PULL_RADIUS_SCALE, 0.0, TAU, 60,
		Color(_color.r, _color.g, _color.b, 0.16 + 0.12 * t), 1.6, true)
	# THE KILL RING. Solid, bright, and the one the eye locks onto.
	draw_arc(_center, _radius, 0.0, TAU, 64,
		Color(HORIZON_COLOR.r, HORIZON_COLOR.g, HORIZON_COLOR.b, 0.55 + 0.45 * t), 3.2, true)
	# The core, growing as it swallows.
	draw_circle(_center, _radius * (0.18 + 0.5 * t), CORE_COLOR, true, -1.0, true)
	draw_arc(_center, _radius * (0.18 + 0.5 * t), 0.0, TAU, 48,
		Color(HORIZON_COLOR.r, HORIZON_COLOR.g, HORIZON_COLOR.b, 0.9), 2.0, true)
	# Infalling streaks — the visual statement of which way the room is moving.
	for i: int in 22:
		var ang: float = TAU * _hash01(_seed + i * 71)
		var phase: float = fposmod(_hash01(_seed + i * 311) + _elapsed * 1.4, 1.0)
		var far: float = lerpf(_radius * PULL_RADIUS_SCALE, _radius * 0.25, phase)
		var dir: Vector2 = Vector2.RIGHT.rotated(ang)
		draw_line(_center + dir * far, _center + dir * (far - 26.0 * (1.0 - phase)),
			Color(_color.r, _color.g, _color.b, 0.7 * (1.0 - phase)), 2.0, true)


## The closing beat: a white-out ring snapping inward to nothing.
func _draw_close() -> void:
	var t: float = clampf((_elapsed - PULL_TIME) / CLOSE_TIME, 0.0, 1.0)
	draw_circle(_center, _radius * (1.0 - t), Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, 1.0 - t),
		true, -1.0, true)
	draw_arc(_center, _radius * (1.0 - t) + 6.0 * t, 0.0, TAU, 64,
		Color(1.8, 1.4, 2.4, 1.0 - t), 5.0 * (1.0 - t) + 1.0, true)
