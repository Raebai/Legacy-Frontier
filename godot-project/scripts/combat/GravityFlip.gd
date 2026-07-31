class_name GravityFlip
extends Node2D
## GRAVITY FLIP — Tier 2 floor pickup. For `length` seconds, everything with feet
## leaves the floor. The caster included. There is no edge to stand outside.
##
## ⚠ HOW THE INVERSION IS ACHIEVED, because it is NOT a gravity constant being
## flipped. `Hero.GRAVITY` / `Enemy.GRAVITY` are `const`s inside files this agent
## does not own, and there is no global gravity these bodies read. So this field
## OVERPOWERS gravity from outside instead: every physics frame it adds an upward
## acceleration to every body in the shared `mortal` group, sized so the sum of it
## and the body's own downward gravity is a net RISE.
##
## That has one honest consequence worth writing down: the numbers here are tuned
## against `Hero.GRAVITY_FALL` (2100) and `Enemy.GRAVITY` (1500). If either of
## those changes, `LIFT` has to change with it or the flip becomes a hover. There
## is a test (`tools/slice_test_tier_spells.gd`) that pins `LIFT` above the larger
## of the two, so the drift fails loudly instead of feeling mushy.
##
## THE LANDING IS PART OF THE SPELL. Nothing is done to soften the moment it ends —
## a room full of bodies at the ceiling all fall at once, and the pile-up is the
## payoff. That is why the duration is a flat 5 s rather than a fade.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.WIND
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## Upward acceleration applied per second, in px/s^2. Must exceed the heaviest
## gravity in the game (`Hero.GRAVITY_FALL` = 2100) by enough that the NET is a
## clear rise rather than a slow float — a body that drifts upward at 200 px/s
## reads as broken physics; one that is lifted reads as a spell.
## UNTESTED FEEL GUESS: 3400 gives a net ~1300 px/s^2 upward on a hero.
const LIFT: float = 3400.0
## Terminal RISE speed, so bodies pin to the ceiling instead of accelerating into
## orbit and leaving the camera. Mirrors the fall clamp every body already has.
const MAX_RISE: float = 520.0
## How long the "it is about to end" warning lasts. The wisps invert and thicken
## over this window so the landing is telegraphed rather than sprung.
const WARN_TIME: float = 0.8
## Drifting motes drawn across the room so the inversion is visible even when
## nobody happens to be airborne yet.
const MOTES: int = 46
const MOTE_SPAN: Vector2 = Vector2(1100.0, 620.0)

var _life: float = 5.0
var _elapsed: float = 0.0
var _color: Color = Color(0.55, 0.95, 0.9)
var _center: Vector2 = Vector2.ZERO
var _seed: int = 0


func hex(caster: Node, origin: Vector2, _target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_life = maxf(spell.length, 0.5)
	_color = color
	_center = origin
	_seed = randi()
	global_position = Vector2.ZERO   # world-space draw, like every spectacle here
	SpellSigil.open(self, origin, color, 1.4, false, Vector2.UP, true, 0.16, 0.5)
	SpellDrops.sfx("levitate", -1.0, 0.12, 0.7)
	Juice.zoom_pull_camera(0.2, _life * 0.5, 0.25, 0.7)   # pull back: the room matters now
	Juice.shake_camera(5.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _life:
		_end()
		return
	_lift_everyone(delta)
	queue_redraw()


## The whole mechanic. Note there is NO caster exclusion and no `hostiles()` call:
## the spec says "caster included", so this deliberately reads the raw group. It is
## the one effect in the drop set that is supposed to reach its own thrower.
func _lift_everyone(delta: float) -> void:
	for n: Node in get_tree().get_nodes_in_group(target_group):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var v: Variant = n.get(&"velocity")
		if v == null or not (v is Vector2):
			continue   # not a moving body — nothing to invert
		var vel: Vector2 = v as Vector2
		vel.y = maxf(vel.y - LIFT * delta, -MAX_RISE)
		n.set(&"velocity", vel)


## Gravity comes back. Nothing is done to the bodies — they simply stop being
## pushed, and every one of them is now somewhere near the ceiling.
func _end() -> void:
	CombatVfx.spawn_burst(get_parent(), _center, Color(_color.r, _color.g, _color.b, 0.7),
		Color(_color.r, _color.g, _color.b, 0.0), 18, 0.5, 60.0, 220.0, 1.2, 3.2)
	Juice.shake_camera(8.0)
	SpellDrops.sfx("rx_ground_out", -4.0, 0.1, 0.6)
	queue_free()


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


## Motes streaming UPWARD across the room. This is the entire readability budget of
## the spell — there is no zone ring to draw because there is no zone — so they are
## drawn wide, and they THICKEN in the last `WARN_TIME` so the landing is announced.
func _draw() -> void:
	var remaining: float = _life - _elapsed
	var warn: float = clampf(1.0 - remaining / WARN_TIME, 0.0, 1.0)
	var alpha: float = 0.35 + 0.4 * warn
	for i: int in MOTES:
		var fx: float = _hash01(_seed + i * 131)
		var fy: float = _hash01(_seed + i * 977 + 7)
		var speed: float = 70.0 + 130.0 * _hash01(_seed + i * 53 + 3)
		# Wraps rather than resetting, so the field looks continuous from the frame
		# it opens instead of starting empty.
		var y: float = fposmod(fy * MOTE_SPAN.y - _elapsed * speed, MOTE_SPAN.y)
		var p := Vector2(_center.x - MOTE_SPAN.x * 0.5 + fx * MOTE_SPAN.x,
			_center.y + MOTE_SPAN.y * 0.5 - y)
		var len: float = 8.0 + 16.0 * warn
		draw_line(p, p + Vector2.UP * len,
			Color(_color.r, _color.g, _color.b, alpha * (0.4 + 0.6 * fx)), 1.6, true)
	# A rising floor-line that climbs as the effect runs — the "up is over there now"
	# read, and the only thing on screen that says how much time is left.
	var lift_line: float = _center.y + MOTE_SPAN.y * 0.4 - MOTE_SPAN.y * 0.75 * (_elapsed / _life)
	draw_line(Vector2(_center.x - MOTE_SPAN.x * 0.5, lift_line),
		Vector2(_center.x + MOTE_SPAN.x * 0.5, lift_line),
		Color(_color.r, _color.g, _color.b, 0.18 + 0.3 * warn), 2.0, true)
