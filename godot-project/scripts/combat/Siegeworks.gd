class_name Siegeworks
extends Node2D
## SIEGEWORKS — the JUGGERNAUT's Tier 3 boss drop, one charge.
##
## THE RULE IT BENDS: **the arena stops being a constant.** Every other spell in
## the game puts a shape INSIDE the room and asks you to leave it. This one takes
## the room away. Two stone faces rise at the edges of the ring and walk inward
## over `length` seconds, and the space you are allowed to stand in shrinks until
## there is almost none.
##
## That is the Juggernaut's locked identity — "the ground obeys" — as a rule
## rather than as a bigger rock. And it is the one Tier 3 that is not really about
## its damage: the walls hurt, but what they mostly do is decide WHERE the fight
## happens, which on a class built around holding a line is the point.
##
## THE ANSWER, because everything must have one: **the gap is always open at the
## start and closes from both sides, so leaving early is free and leaving late is
## impossible.** A dash out in the first second costs nothing. There is no exit in
## the last second. Everything between is the decision.
##
## ⚠ THE WALLS SHOVE, THEY DO NOT CRUSH TO DEATH. A body the wall reaches is
## pushed inward and damaged ONCE PER CONTACT with a cooldown, not per frame. A
## per-frame crush would delete anything caught in the first half second, which
## turns "the room is closing" into "you are dead", and the whole spell is about
## the pressure rather than the kill.
##
## UNPLAYTESTED. Every number is a reasoned first guess with the reasoning attached.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.EARTH
var caster_node: Node = null
var spell_tier: int = SpellTier.Tier.ULT

## How close the two faces get, as a fraction of the starting half-width. Not zero:
## a corridor that closes completely would grind bodies against each other with no
## legal position at all, and the physics of that is nobody's idea of a good time.
const CLOSE_TO: float = 0.18
## Seconds a given body is immune to the walls after being hit by one. This is the
## difference between "shoved along" and "deleted".
const CONTACT_COOLDOWN: float = 0.45
## How hard a face throws what it catches.
const SHOVE: float = 320.0
const RUBBLE: Color = Color(0.46, 0.36, 0.26)
const LIT: Color = Color(1.15, 0.82, 0.42)   # HDR — the leading edge grinds bright

var _center: Vector2 = Vector2.ZERO
var _radius: float = 300.0
var _damage: int = 90
var _life: float = 3.2
var _color: Color = RUBBLE
var _elapsed: float = 0.0
var _seed: int = 0
## instance id -> time (in this spell's own clock) the body may be hit again.
var _touched: Dictionary = {}


func cataclysm(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_center = target
	_radius = maxf(spell.radius, 40.0)
	_damage = spell.damage
	_life = maxf(spell.length, 0.5)
	_color = color
	_seed = randi()
	global_position = Vector2.ZERO
	# Runs AFTER every body has integrated its own motion, so a shove is not undone
	# by the same frame's `move_and_slide`. Same reason `Chronostasis` and
	# `VoidCollapse` raise theirs.
	process_physics_priority = 200
	SpellSigil.open(self, _center, color, maxf(_radius * 1.1, 30.0) / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.16, 0.7)
	SpellDrops.sfx("rock_rise", 0.0, 0.05, 0.75)
	Juice.zoom_pull_camera(0.26, _life * 0.7, 0.24, 0.9)
	Juice.shake_camera(10.0)
	queue_redraw()


## Half the gap between the two faces, right now. Public and pure so the suite can
## assert the closing curve without watching a fight: it must start at `_radius`,
## end at `CLOSE_TO * _radius`, and never widen.
func half_gap_at(t: float) -> float:
	var f: float = clampf(t / maxf(_life, 0.001), 0.0, 1.0)
	# Ease-in: the first second barely moves and the last one slams. Leaving early
	# has to be genuinely cheap or the spell is just a delayed room-wide hit.
	return _radius * lerpf(1.0, CLOSE_TO, f * f)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _life:
		_slam()
		queue_free()
		return
	_grind(delta)
	queue_redraw()


## Push anything the faces have reached back toward the middle, and bill it once
## per `CONTACT_COOLDOWN`.
func _grind(_delta: float) -> void:
	var gap: float = half_gap_at(_elapsed)
	var tint := Color(LIT.r, LIT.g, LIT.b, 1.0)
	for n: Node in SpellTargets.hostiles(self, StringName(target_group)):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or not (n is Node2D):
			continue
		if n == caster_node:
			continue
		var p: Vector2 = (n as Node2D).global_position
		# Only bodies within the ring's VERTICAL band are in the works at all — the
		# walls are a corridor, not a sphere, and somebody standing above it on a
		# platform is legitimately out of it.
		if absf(p.y - _center.y) > _radius:
			continue
		var dx: float = p.x - _center.x
		if absf(dx) < gap:
			continue   # still inside the gap: untouched
		var id: int = n.get_instance_id()
		if _elapsed < float(_touched.get(id, -1.0)):
			continue
		_touched[id] = _elapsed + CONTACT_COOLDOWN
		var inward: float = -signf(dx)
		if n.has_method("apply_knockback"):
			n.call("apply_knockback", Vector2(inward * SHOVE, -80.0))
		SpellTargets.hurt(n, _damage, tint)
		if n.has_method("apply_status"):
			n.call("apply_status", element_id)
		CombatVfx.spawn_burst(get_parent(), Vector2(_center.x + gap * signf(dx), p.y),
			Color(1.2, 0.85, 0.45, 0.9), Color(0.3, 0.22, 0.14, 0.0),
			10, 0.32, 60.0, 180.0, 1.0, 2.6)


## The faces meeting: rubble, a crater on each side, and the room handed back.
func _slam() -> void:
	var gap: float = _radius * CLOSE_TO
	for s: float in [-1.0, 1.0]:
		var at := Vector2(_center.x + gap * s, _center.y)
		DebrisChunk.spawn_burst(get_parent(), at, RUBBLE, 10, Vector2(-s, -0.4), 300.0)
		GroundCrater.spawn(get_parent(), at, 34.0, true)
	CombatVfx.spawn_burst(get_parent(), _center, Color(1.3, 0.95, 0.55, 1.0),
		Color(0.28, 0.2, 0.12, 0.0), 30, 0.5, 80.0, 260.0, 1.4, 4.0, 0.0, 0.0, true)
	Juice.on_hit({"shake": 22.0, "zoom": 0.16, "sfx": "blast", "sfx_pitch": -0.2,
		"hitstop": 0.12})
	PostProcess.shock(0.7, Juice.world_to_uv(_center))
	Juice.tier_frame(SpellTier.Tier.ULT, _center, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	var gap: float = half_gap_at(_elapsed)
	var t: float = clampf(_elapsed / _life, 0.0, 1.0)
	var top: float = _center.y - _radius
	var h: float = _radius * 2.0
	for s: float in [-1.0, 1.0]:
		var face_x: float = _center.x + gap * s
		# The wall body, running off to the side of the screen. Drawn as a slab
		# rather than a line so it reads as MASS arriving, which is the whole
		# threat — a thin line would read as another danger boundary.
		var back_x: float = face_x + s * _radius * 1.6
		draw_colored_polygon(PackedVector2Array([
			Vector2(face_x, top), Vector2(back_x, top),
			Vector2(back_x, top + h), Vector2(face_x, top + h),
		]), Color(_color.r, _color.g, _color.b, 0.82))
		# The grinding leading edge.
		draw_line(Vector2(face_x, top), Vector2(face_x, top + h),
			Color(LIT.r, LIT.g, LIT.b, 0.55 + 0.4 * t), 3.0 + 2.0 * t, true)
		# Broken teeth along it, so the face is stone and not a door.
		var teeth: int = 9
		for i: int in teeth:
			var y: float = top + h * (float(i) + 0.5) / float(teeth)
			var bite: float = 6.0 + 7.0 * _hash01(_seed + i * 53 + int(s) * 17)
			draw_line(Vector2(face_x, y), Vector2(face_x - s * bite, y),
				Color(_color.r * 1.3, _color.g * 1.2, _color.b, 0.9), 3.4, true)
	# The remaining floor, marked. This is the honest statement of how much room
	# is left, and it is the only number either fighter actually needs.
	draw_line(Vector2(_center.x - gap, _center.y + _radius),
		Vector2(_center.x + gap, _center.y + _radius),
		Color(LIT.r, LIT.g, LIT.b, 0.25 + 0.45 * t), 2.0, true)
