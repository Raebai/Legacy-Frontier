class_name ReactionOutcomes
extends RefCounted
## What an authored reaction actually DOES. One static function per outcome key;
## SpellReactor decides that two effects met, this decides what that means.
##
## Outcomes land one at a time. An outcome named in ReactionTable but not yet
## implemented here is a deliberate no-op: the reactor still memoizes the pair
## (so it cannot spam), nothing is consumed, and the game behaves exactly as it
## did before the row was written. That is what makes the ~28-row matrix
## shippable in slices instead of as one landing.

## For a CROSS-CASTER crossing the meeting must sit in the BODY of both beams,
## not at a muzzle graze — a beam clipping the very tip of another is a near-miss,
## and reading it as an annihilation feels arbitrary. A SELF-combo is exempt:
## both beams leave the same muzzle, so they always meet at t~0 by construction.
const CROSS_MIN_T: float = 0.08
const CROSS_MAX_T: float = 0.97
## No two stubs faking a collapse.
const MIN_BEAM_LENGTH: float = 300.0
## How far in front of the caster the fusion circle opens, along their aim.
const SELF_COMBO_OFFSET: float = 200.0

const HOLLOW_PURPLE_PATH: String = "res://scripts/combat/HollowPurple.gd"


## Dispatch. `ctx` carries {reactor, rule, a, b, element_a, element_b, shape_a,
## shape_b, point, spawn_effects}. Returns true when the event was handled and
## should be memoized; false leaves the pair free to try again next tick.
static func apply(outcome: String, ctx: Dictionary) -> bool:
	match outcome:
		"hollow_purple":
			return _hollow_purple(ctx)
	return true


# ------------------------------------------------------------ HOLLOW PURPLE

## Two beams of OPPOSING elements fuse. Both are absorbed into a magic circle,
## and the result erupts out of it in a line.
##
## WHERE the circle opens, and which way it fires, depends on whose beams these
## are — and that is the only place ownership is consulted, because the table
## already decided the rule applies:
##   SAME owner (the headline self-combo) — the circle opens a fixed distance in
##     FRONT of the caster along their aim, and fires along that aim. There is no
##     meaningful bisector when both beams leave the same muzzle.
##   DIFFERENT owners (the rarer crossing) — the circle opens at the geometric
##     crossing and fires along the two beams' angle bisector.
static func _hollow_purple(ctx: Dictionary) -> bool:
	var reactor: Node = ctx["reactor"]
	# Global one-shot: one annihilation owns the screen at a time.
	if reactor.call(&"hollow_purple_live"):
		return false
	var sa: Dictionary = ctx["shape_a"]
	var sb: Dictionary = ctx["shape_b"]
	if SpellGeometry.is_circle(sa) or SpellGeometry.is_circle(sb):
		return false
	var a0: Vector2 = sa["from"]
	var a1: Vector2 = sa["to"]
	var b0: Vector2 = sb["from"]
	var b1: Vector2 = sb["to"]
	var la: float = a0.distance_to(a1)
	var lb: float = b0.distance_to(b1)
	if la < MIN_BEAM_LENGTH or lb < MIN_BEAM_LENGTH:
		return false
	var self_combo: bool = String(ctx.get("owner_rel", "")) == "same"
	var p: Vector2 = ctx["point"]
	var axis: Vector2 = Vector2.RIGHT
	if self_combo:
		# `b` is the LATER registration, so its direction is the caster's most
		# recent aim — the one they were holding when they completed the combo.
		axis = (b1 - b0).normalized()
		p = b0 + axis * SELF_COMBO_OFFSET
	else:
		axis = SpellGeometry.bisector(sa, sb)
		var ta: float = (p - a0).dot((a1 - a0) / la) / la
		var tb: float = (p - b0).dot((b1 - b0) / lb) / lb
		if ta < CROSS_MIN_T or ta > CROSS_MAX_T or tb < CROSS_MIN_T or tb > CROSS_MAX_T:
			return false

	var node_a: Node = ctx["a"]
	var node_b: Node = ctx["b"]
	_freeze(node_a)
	_freeze(node_b)
	if not bool(ctx.get("spawn_effects", true)):
		# Detection-only mode (headless suites): the pair is spent, no spectacle.
		_consume(node_a)
		_consume(node_b)
		return true

	var parent: Node = node_a.get_parent()
	if parent == null:
		parent = node_b.get_parent()
	if parent == null or not parent.is_inside_tree():
		return false
	var rule: Dictionary = ctx["rule"]
	var hp: Node2D = (load(HOLLOW_PURPLE_PATH) as GDScript).new()
	parent.add_child(hp)
	reactor.call(&"claim_hollow_purple", hp)
	hp.call(&"begin", p, axis,
		_beam_data(node_a, sa, int(ctx["element_a"])),
		_beam_data(node_b, sb, int(ctx["element_b"])),
		rule)
	return true


## Everything the collapse needs to keep drawing a beam after the beam itself is
## gone. `_damage` / `target_group` are BeamSpell's; Object.get returns null for
## a participant that has neither, so the fallbacks keep this duck-typed.
static func _beam_data(node: Node, shape: Dictionary, element: int) -> Dictionary:
	var dmg: Variant = node.get(&"_damage")
	var grp: Variant = node.get(&"target_group")
	return {
		"from": shape["from"] as Vector2,
		"to": shape["to"] as Vector2,
		"width": float(shape["width"]),
		"element": element,
		"damage": int(dmg) if dmg != null else 40,
		"group": String(grp) if grp != null else "enemy",
		"node": node,
	}


static func _freeze(n: Node) -> void:
	if n != null and is_instance_valid(n) and n.has_method(&"reaction_freeze"):
		n.call(&"reaction_freeze")


static func _consume(n: Node) -> void:
	if n != null and is_instance_valid(n) and n.has_method(&"reaction_consume"):
		n.call(&"reaction_consume")
