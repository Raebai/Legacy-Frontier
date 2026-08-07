class_name Teardown
extends Node2D
## TEARDOWN — the BRAWLER's Tier 3 boss drop, one charge.
##
## THE RULE IT BENDS: **its damage does not come from the spell.** Every other
## attack in the game carries its own number; this one carries almost none and
## reads the ARENA instead. It rips every piece of cover inside the ring out of
## the floor and throws it, and what it deals is a function of how much there was
## to throw.
##
## That is the Brawler's locked identity stated as a rule — "no magic, fists and
## terrain". The class has no spells; it has the room. So its ult is the room.
##
## THREE BEATS:
##   HEAVE   — the ground under every destructible in `radius` lifts. `HEAVE_TIME`
##             seconds of visible warning, and the pieces that are about to become
##             ammunition are the ones glowing.
##   TEAR    — every one of them is destroyed at once and becomes debris.
##   THROW   — the debris is hurled outward through a ring WIDER than the one it
##             was torn from, damaging what it passes. Standing at the edge of the
##             ring is the worst place to be, which inverts every other AoE in the
##             game, where the edge is the safe part.
##
## ⚠ AN EMPTY ROOM IS A NEARLY-WASTED CHARGE, DELIBERATELY, AND IT IS THE ONE
## THING MOST LIKELY TO READ AS BROKEN. `BASE_DAMAGE` is what a bare floor pays.
## The spell is a read on the arena, and a Brawler who casts it in an empty
## corridor has misread. If playtest says that feels like a bug rather than a
## decision, raise `BASE_DAMAGE` — do NOT flatten `PER_PIECE`, which IS the spell.
##
## UNPLAYTESTED. Every number is a reasoned first guess with the reasoning attached.

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.EARTH
var caster_node: Node = null
var spell_tier: int = SpellTier.Tier.ULT

## What a bare floor pays. Deliberately small — see the warning above.
const BASE_DAMAGE: int = 40
## ...and what each torn piece of cover adds.
const PER_PIECE: int = 34
## The ceiling, in pieces. A room stuffed with crates must not scale forever, and
## eight is already more cover than any authored floor puts in one ring.
const MAX_PIECES: int = 8
const HEAVE_TIME: float = 0.55
const THROW_TIME: float = 0.40
## How much wider the thrown debris reaches than the ring it was torn from. This
## is the inversion — the danger is OUTSIDE the ring you can see being torn up.
const THROW_SCALE: float = 1.55
const STONE: Color = Color(0.52, 0.40, 0.28)
const LIT: Color = Color(1.25, 0.85, 0.45)   # HDR — the heave glows

var _center: Vector2 = Vector2.ZERO
var _radius: float = 200.0
var _color: Color = STONE
var _elapsed: float = 0.0
var _torn: bool = false
var _pieces: Array[Vector2] = []   # where each bit of cover WAS, captured at cast
var _toll: int = BASE_DAMAGE
var _seed: int = 0


func cataclysm(caster: Node, _origin: Vector2, target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_center = target
	_radius = maxf(spell.radius, 30.0)
	_color = color
	_seed = randi()
	global_position = Vector2.ZERO
	_survey()
	SpellSigil.open(self, _center, color, maxf(_radius * 1.2, 30.0) / SpellSigil.RADIUS_HEAVY,
		false, Vector2.RIGHT, true, 0.12, 0.55)
	SpellDrops.sfx("rock_rise", -1.0, 0.06, 0.6)
	Juice.shake_camera(8.0)
	queue_redraw()


## Count and remember the cover, at cast. Positions are captured now because the
## pieces are about to be destroyed and their nodes freed — the drawing has to
## outlive them or the throw comes from nowhere.
func _survey() -> void:
	for prop: Node in SpellTargets.in_radius(_center, _radius,
			get_tree().get_nodes_in_group("destructible"), [caster_node], self):
		if prop is Node2D and _pieces.size() < MAX_PIECES:
			_pieces.append((prop as Node2D).global_position)
	_toll = toll_for(_pieces.size())


## What this cast is worth, given how much cover it found. Public and pure so the
## suite can assert "an empty room pays the floor, a full one pays more" without
## having to build an arena full of crates.
func toll_for(pieces: int) -> int:
	return BASE_DAMAGE + PER_PIECE * clampi(pieces, 0, MAX_PIECES)


func pieces_found() -> int:
	return _pieces.size()


func _process(delta: float) -> void:
	_elapsed += delta
	if not _torn and _elapsed >= HEAVE_TIME:
		_tear()
	elif _torn and _elapsed >= HEAVE_TIME + THROW_TIME:
		queue_free()
		return
	queue_redraw()


func _tear() -> void:
	_torn = true
	var tint := Color(LIT.r, LIT.g, LIT.b, 1.0)
	# 1 — destroy the cover. This is what ARMS the spell, so it happens first and
	# unconditionally; the damage below is already priced off what was found.
	for prop: Node in SpellTargets.in_radius(_center, _radius,
			get_tree().get_nodes_in_group("destructible"), [caster_node], self):
		if prop.has_method("take_damage"):
			prop.call("take_damage", 9999)   # torn out whole, not chipped
	# 2 — throw it. The wider ring is the danger, and it was drawn from frame one.
	for n: Node in SpellTargets.in_radius(_center, _radius * THROW_SCALE,
			SpellTargets.hostiles(self, StringName(target_group)), [caster_node], self):
		SpellTargets.hurt(n, _toll, tint)
		if n.has_method("apply_status"):
			n.call("apply_status", element_id)
		if n.has_method("apply_knockback") and n is Node2D:
			var away: Vector2 = ((n as Node2D).global_position - _center).normalized()
			if away == Vector2.ZERO:
				away = Vector2.UP
			n.call("apply_knockback", away * SpellTier.push_for_spectacle(
				float(_toll), SpellTier.PUSH_TIER[SpellTier.Tier.ULT]))
	# 3 — the debris itself, thrown outward from where each piece stood.
	for p: Vector2 in _pieces:
		var away: Vector2 = (p - _center).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		DebrisChunk.spawn_burst(get_parent(), p, STONE, 8, away, 340.0)
		GroundCrater.spawn(get_parent(), p, 26.0, true)
	CombatVfx.spawn_burst(get_parent(), _center, Color(1.3, 0.9, 0.5, 1.0),
		Color(0.3, 0.2, 0.12, 0.0), 34, 0.55, 90.0, 300.0, 1.4, 4.2, 0.0, 0.0, true)
	Juice.on_hit({"shake": 20.0 + 2.0 * float(_pieces.size()), "zoom": 0.18,
		"sfx": "blast", "sfx_pitch": -0.15, "hitstop": 0.14})
	PostProcess.shock(0.75, Juice.world_to_uv(_center))
	Juice.tier_frame(SpellTier.Tier.ULT, _center, element_id,
		{"zoom": 0.0, "shake": 0.0, "shock": 0.0, "hitstop": 0.0})


static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if _torn:
		_draw_throw()
		return
	var t: float = clampf(_elapsed / HEAVE_TIME, 0.0, 1.0)
	# THE THROW RING, drawn from frame one at the radius that will actually hurt.
	# It is WIDER than the tear ring, and showing that is the whole honesty of the
	# spell: the safe-looking edge is the lethal one.
	draw_arc(_center, _radius * THROW_SCALE, 0.0, TAU, 64,
		Color(LIT.r, LIT.g, LIT.b, 0.14 + 0.22 * t), 2.0 + 1.5 * t, true)
	# The tear ring, dimmer — this is where the ammunition comes FROM.
	draw_arc(_center, _radius, 0.0, TAU, 56,
		Color(_color.r, _color.g, _color.b, 0.30), 1.4, true)
	# Each doomed piece lifts and shakes.
	for i: int in _pieces.size():
		var p: Vector2 = _pieces[i]
		var shake: float = 3.0 * t * sin(_elapsed * 34.0 + _hash01(_seed + i * 41) * TAU)
		var lift: Vector2 = Vector2(shake, -10.0 * t)
		var s: float = 9.0 + 4.0 * _hash01(_seed + i * 197)
		draw_colored_polygon(PackedVector2Array([
			p + lift + Vector2(-s, -s * 0.6), p + lift + Vector2(s, -s * 0.45),
			p + lift + Vector2(s * 0.75, s * 0.7), p + lift + Vector2(-s * 0.8, s * 0.6),
		]), Color(LIT.r * (0.4 + 0.6 * t), LIT.g * (0.4 + 0.6 * t), LIT.b * 0.5, 0.85))
		# The seam it is being pulled out of.
		draw_arc(p, s * 1.5, 0.0, TAU, 14,
			Color(LIT.r, LIT.g, LIT.b, 0.3 + 0.5 * t), 1.6, true)


## The outward blast: a fast expanding ring plus the streaks of thrown stone.
func _draw_throw() -> void:
	var t: float = clampf((_elapsed - HEAVE_TIME) / THROW_TIME, 0.0, 1.0)
	var fade: float = 1.0 - t
	draw_arc(_center, _radius * THROW_SCALE * (0.35 + 0.65 * t), 0.0, TAU, 64,
		Color(LIT.r, LIT.g, LIT.b, fade), 6.0 * fade + 1.0, true)
	for i: int in _pieces.size():
		var p: Vector2 = _pieces[i]
		var away: Vector2 = (p - _center).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		var travel: float = _radius * 0.8 * t
		draw_line(p + away * travel, p + away * (travel - 22.0 * fade),
			Color(_color.r, _color.g, _color.b, fade), 3.0, true)
