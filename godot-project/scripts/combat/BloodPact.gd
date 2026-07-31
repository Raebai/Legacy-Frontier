class_name BloodPact
extends Node2D
## BLOOD PACT — Tier 2 floor pickup. Everything you CAST hits far harder, and you
## pay for it in health for as long as it lasts. There is no way to end it early;
## that is the spell.
##
## TWO SEAMS, AND BOTH ARE ONES THIS AGENT OWNS.
##   THE BUFF   — `SpellCaster.cast()` asks `multiplier_for(caster)` before it
##                dispatches and casts a boosted DUPLICATE of the SpellDef. It has
##                to be a duplicate: a SpellDef is a Resource handed out by
##                `SpellLibrary`, and scaling `spell.damage` in place would leave
##                the hero permanently buffed the moment the pact expired.
##   THE COST   — this node bills the caster every second through
##                `SpellTargets.hurt`, which means the drain runs the real damage
##                path. YOU CAN DIE TO YOUR OWN PACT. That is deliberate and it is
##                the only reason the buff is allowed to be as large as it is.
##
## ⚠ IT DOES NOT BUFF MELEE, and the spell's own description says so. Melee damage
## is resolved inside `Hero`, which this agent does not own; there is no seam to
## multiply it through without an edit there. If that ever changes, the hook is one
## line in `Hero._primary_melee_combo` calling the same `multiplier_for(self)`.
##
## ⚠ THE PACT IS PER-CASTER, NOT GLOBAL. `multiplier_for` matches on the caster
## instance, so a hero drinking their own pact does not buff their teammate's
## spells — and two pacts on the same body deliberately do NOT stack (the largest
## wins), because stacking a self-damage buff is how a spell becomes a suicide
## button by arithmetic rather than by decision.

## The group every live pact joins, so `multiplier_for` is one group scan and never
## a walk of the whole arena.
const PACT_GROUP: StringName = &"blood_pact"

var target_group: String = "enemy"
var _target_group: String = "enemy"
var element_id: int = Elements.Element.SHADOW
var caster_node: Node = null
var spell_tier: int = SpellTier.DEFAULT_WEIGHT

## Ring drawn at the caster's feet. Deep arterial red against every element palette.
const RING_COLOR: Color = Color(0.85, 0.12, 0.18)
const RING_RADIUS: float = 30.0
## Drip cadence, seconds. Slow enough to read as a heartbeat rather than a leak.
const DRIP_INTERVAL: float = 0.28

var _life: float = 8.0
var _elapsed: float = 0.0
var _mult: float = 1.75
var _drain_per_second: float = 5.0
## Fractional HP owed. Damage is an int, so the drain accumulates and pays whole
## points — otherwise a 5 HP/s drain at 60 fps rounds to zero every single frame
## and the spell costs nothing at all.
var _owed: float = 0.0
var _drip: float = 0.0
var _color: Color = RING_COLOR


func hex(caster: Node, _origin: Vector2, _target: Vector2, spell: SpellDef,
		color: Color, _fx: String) -> void:
	caster_node = caster if caster_node == null else caster_node
	_life = maxf(spell.length, 0.5)
	# `radius` is the multiplier and `count` the drain — see the SpellDef's note on
	# the field-doubling this codebase already does for ZONE lifetimes.
	_mult = maxf(spell.radius, 1.0)
	_drain_per_second = maxf(float(spell.count), 0.0)
	_color = color
	global_position = Vector2.ZERO
	add_to_group(PACT_GROUP)
	SpellSigil.open(self, _caster_pos(), RING_COLOR, 0.9, false, Vector2.RIGHT, true, 0.1, 0.4)
	SpellDrops.sfx("cast_shadow", -3.0, 0.1, 0.62)
	Juice.shake_camera(4.0)
	queue_redraw()


## The multiplier every spell cast by `caster` is scaled by, or 1.0. Largest live
## pact wins; pacts never stack (see the header).
##
## `ctx` only has to be SOMETHING in the tree — the caster itself is the usual
## argument. Returns 1.0 with no tree, which is the headless / `--script` case and
## the conservative direction.
static func multiplier_for(caster: Object, ctx: Node) -> float:
	if caster == null or not is_instance_valid(caster) or ctx == null or not ctx.is_inside_tree():
		return 1.0
	var tree: SceneTree = ctx.get_tree()
	if tree == null:
		return 1.0
	var best: float = 1.0
	var want: int = (caster as Object).get_instance_id()
	for p: Node in tree.get_nodes_in_group(PACT_GROUP):
		if not is_instance_valid(p) or p.is_queued_for_deletion():
			continue
		var owner_node: Variant = p.get(&"caster_node")
		if owner_node == null or not is_instance_valid(owner_node as Object):
			continue
		if (owner_node as Object).get_instance_id() != want:
			continue
		best = maxf(best, float(p.get(&"_mult")))
	return best


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if not _caster_ok() or _elapsed >= _life:
		_end()
		return
	_owed += _drain_per_second * delta
	if _owed >= 1.0:
		var pay: int = int(floorf(_owed))
		_owed -= float(pay)
		# Through the real damage path: the pact must be able to kill you, and only
		# `take_damage` runs the death.
		SpellTargets.hurt(caster_node, pay, RING_COLOR)
	_drip += delta
	if _drip >= DRIP_INTERVAL:
		_drip = 0.0
		CombatVfx.spawn_burst(get_parent(), _caster_pos(), Color(0.9, 0.15, 0.2, 0.85),
			Color(0.35, 0.02, 0.05, 0.0), 4, 0.4, 20.0, 70.0, 0.8, 2.0)
	queue_redraw()


func _caster_ok() -> bool:
	return caster_node != null and is_instance_valid(caster_node) \
		and not caster_node.is_queued_for_deletion() and HpWatch.is_alive(caster_node)


func _caster_pos() -> Vector2:
	if caster_node is Node2D and is_instance_valid(caster_node):
		return (caster_node as Node2D).global_position
	return Vector2.ZERO


func _end() -> void:
	if is_in_group(PACT_GROUP):
		remove_from_group(PACT_GROUP)
	queue_free()


## A pulsing arterial ring under the caster plus a rising bar of how much of the
## pact is left. Both are drawn AT the caster every frame rather than parented to
## them, because a spectacle in this codebase never owns a transform.
func _draw() -> void:
	if not _caster_ok():
		return
	var at: Vector2 = _caster_pos()
	var beat: float = 0.5 + 0.5 * sin(_elapsed * 7.0)
	draw_arc(at + Vector2(0.0, 4.0), RING_RADIUS + 3.0 * beat, 0.0, TAU, 32,
		Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, 0.45 + 0.25 * beat), 2.6, true)
	draw_arc(at + Vector2(0.0, 4.0), RING_RADIUS * 0.6, 0.0, TAU, 24,
		Color(1.4, 0.3, 0.35, 0.4 + 0.3 * beat), 1.6, true)
	# Remaining-duration arc, drawn on the ring itself so the player never has to
	# look away from their own feet to know how much bleeding is left.
	var left: float = clampf(1.0 - _elapsed / _life, 0.0, 1.0)
	draw_arc(at + Vector2(0.0, 4.0), RING_RADIUS + 7.0, -PI * 0.5,
		-PI * 0.5 + TAU * left, 40, Color(1.5, 0.35, 0.4, 0.9), 3.0, true)
