class_name Chronostasis
extends Node2D
## CHRONOSTASIS — Tier 3 boss drop, one charge. Three seconds stop inside the ring.
## Nothing moves. Nothing LANDS — every point of damage dealt to a frozen body is
## held, and the whole ledger is paid out in one instant when time restarts.
##
## Your teammate is frozen too, and that is the decision the spell exists to force:
## the freeze is also three seconds of total immunity, so catching your friend
## either saves their life or wastes the only window you had to save it.
##
## ⚠ HOW THE BANKING WORKS — READ THIS BEFORE CHANGING IT. There is no hook inside
## `take_damage`; that lives on `Hero`/`Enemy`, files this agent does not own. So
## the ledger is kept by OBSERVATION: every physics frame this compares each frozen
## body's `hp` against the value it had last frame, and anything missing is banked
## and put straight back (`HpWatch`). The upside is that it catches damage from
## EVERY source — spells, melee, DoT ticks, hazards, the other player — with no
## edits anywhere. The two costs, both honest:
##   1. ONE FRAME OF FLICKER. A frozen body dips to its post-hit HP and is restored
##      within the same tick. UNTESTED whether that is visible; if it is, the fix is
##      a real intercept in `Hero.take_damage`, not a bigger number here.
##   2. A KILLING BLOW IS NOT SURVIVED, IT IS DEFERRED. If a hit would have taken a
##      body below zero, `take_damage` runs its death path before this file ever
##      sees the number. That is a deliberate carve-out rather than a bug: a spell
##      that made everything in a 235 px ring unkillable for three seconds would be
##      a defensive ult, and this is supposed to be a bomb.
##
## THE DETONATION IS PER-BODY. Each frozen body takes exactly what was banked
## against it, at its own position, with its own burst — so a fight where one enemy
## soaked everything reads completely differently from one where the damage was
## spread, which is the information the player needs to learn how to use it.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.ICE
var caster_node: Node = null
var spell_tier: int = SpellTier.Tier.ULT

## The freeze ring's colour language — pale, near-white ice with an HDR rim so the
## boundary is unmistakable. Being able to see EXACTLY where the edge is matters
## more here than for any other spell in the set: standing one pixel outside it is
## a completely different fight.
const RING_COLOR: Color = Color(0.72, 0.92, 1.0)
const RIM_COLOR: Color = Color(1.4, 1.7, 2.0)
## How long the pay-out flash lasts after the freeze breaks.
const PAYOUT_TIME: float = 0.35

var _center: Vector2 = Vector2.ZERO
var _radius: float = 235.0
var _life: float = 3.0
var _color: Color = RING_COLOR
var _elapsed: float = 0.0
var _paid: bool = false
## One row per caught body: {node, pos, hp (last seen), banked (int)}.
var _held: Array[Dictionary] = []
var _seed: int = 0


func cataclysm(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_center = target
	_radius = maxf(spell.radius, 30.0)
	_life = maxf(spell.length, 0.5)
	_color = color
	_seed = randi()
	global_position = Vector2.ZERO
	# Last in the frame: the pin below writes position and velocity, and every body
	# writes both in its own `_physics_process`. See `Petrify` for the same note.
	process_priority = 200
	process_physics_priority = 200
	_freeze()
	SpellSigil.open(self, _center, color, maxf(_radius * 1.2, 30.0) / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.12, 0.55)
	SpellDrops.sfx("ice_encase", -2.0, 0.05, 0.7)
	Juice.zoom_pull_camera(0.24, _life * 0.6, 0.2, 0.8)
	Juice.shake_camera(7.0)
	queue_redraw()


## Catch everyone inside the ring. Uses the RAW group, not `hostiles()`: "your
## teammate is frozen too" is the spec, and the caster standing in their own
## Chronostasis being frozen with everybody else is the correct reading of a spell
## that stops time in a place rather than for a side.
func _freeze() -> void:
	for n: Node in SpellTargets.in_radius(_center, _radius,
			get_tree().get_nodes_in_group(target_group), [], self):
		if not HpWatch.is_alive(n):
			continue
		_held.append({"node": n, "pos": (n as Node2D).global_position,
			"hp": HpWatch.hp_of(n), "banked": 0})
		if n.has_method("apply_status"):
			n.apply_status(element_id, false)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if not _paid and _elapsed >= _life:
		_pay_out()
	elif not _paid:
		_hold()
	elif _elapsed >= _life + PAYOUT_TIME:
		queue_free()
		return
	queue_redraw()


## Pin every held body and bank anything that hit it this frame.
func _hold() -> void:
	for row: Dictionary in _held:
		var n: Node = row["node"]
		if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var now: int = HpWatch.hp_of(n)
		var was: int = int(row["hp"])
		if now >= 0 and was >= 0 and now < was:
			row["banked"] = int(row["banked"]) + (was - now)
			HpWatch.restore(n, was)          # nothing LANDS while time is stopped
		else:
			row["hp"] = now
		n.set(&"velocity", Vector2.ZERO)
		(n as Node2D).global_position = row["pos"]


## Time restarts and the whole ledger arrives at once.
func _pay_out() -> void:
	_paid = true
	var tint := Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, 1.0)
	var total: int = 0
	for row: Dictionary in _held:
		var n: Node = row["node"]
		var owed: int = int(row["banked"])
		if owed <= 0 or n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		total += owed
		SpellTargets.hurt(n, owed, tint)
		var at: Vector2 = (n as Node2D).global_position
		CombatVfx.spawn_burst(get_parent(), at, Color(1.5, 1.8, 2.2, 1.0),
			Color(0.4, 0.7, 1.0, 0.0), 24, 0.5, 80.0, 260.0, 1.4, 4.0, 0.0, 0.0, true)
	if total > 0:
		Juice.on_hit({"shake": 22.0, "zoom": 0.18, "sfx": "ice_shatter", "sfx_pitch": 0.1,
			"hitstop": 0.14})
		PostProcess.shock(0.75, Juice.world_to_uv(_center))
		Juice.tier_frame(SpellTier.Tier.ULT, _center, element_id,
			{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})
	else:
		# Nothing was banked — the freeze was a whiff, and the spell says so rather
		# than ending in silence with a charge gone.
		SpellDrops.sfx("ice_shatter", -10.0, 0.1, 1.4)


## How much is currently owed across every held body. Public so the test suite can
## assert the banking without staging a full detonation, and so a future HUD can
## show the number climbing — which is exactly the read this spell wants.
func banked_total() -> int:
	var t: int = 0
	for row: Dictionary in _held:
		t += int(row["banked"])
	return t


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if _paid:
		_draw_payout()
		return
	var t: float = clampf(_elapsed / _life, 0.0, 1.0)
	# The boundary, hard and bright. Two rings: a solid rim and a thin inner line,
	# because a single arc at 640x360 disappears against a busy floor.
	draw_arc(_center, _radius, 0.0, TAU, 72, Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, 0.85), 3.0, true)
	draw_arc(_center, _radius - 5.0, 0.0, TAU, 72, Color(_color.r, _color.g, _color.b, 0.35), 1.4, true)
	draw_circle(_center, _radius, Color(_color.r, _color.g, _color.b, 0.07), true, -1.0, true)
	# A depleting sweep on the rim: how long the stop has left, readable without a
	# HUD element and without looking away from the fight.
	draw_arc(_center, _radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - t), 64,
		Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, 0.9), 2.6, true)
	# Frozen shards hanging motionless — the "nothing is moving" statement. They do
	# not animate ON PURPOSE; a drifting particle inside a time-stop is a lie.
	for i: int in 26:
		var ang: float = TAU * _hash01(_seed + i * 97)
		var rr: float = _radius * (0.25 + 0.7 * _hash01(_seed + i * 401))
		var p: Vector2 = _center + Vector2.RIGHT.rotated(ang) * rr
		draw_line(p, p + Vector2.RIGHT.rotated(ang + 1.2) * 7.0,
			Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, 0.5), 1.6, true)
	# The ledger, drawn as a filling core. Bigger bank = brighter middle, so "how
	# much is about to happen" is visible from across the room.
	var owed: float = clampf(float(banked_total()) / 400.0, 0.0, 1.0)
	if owed > 0.0:
		draw_circle(_center, _radius * 0.18 * owed,
			Color(1.6, 1.2, 1.9, 0.35 + 0.4 * owed), true, -1.0, true)


func _draw_payout() -> void:
	var t: float = clampf((_elapsed - _life) / PAYOUT_TIME, 0.0, 1.0)
	draw_arc(_center, _radius * (1.0 + 0.35 * t), 0.0, TAU, 72,
		Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, 1.0 - t), 6.0 * (1.0 - t) + 1.0, true)
