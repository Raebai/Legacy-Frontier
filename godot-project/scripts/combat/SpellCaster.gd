class_name SpellCaster
extends RefCounted
## Turns a SpellDef (data) into an on-screen spectacle (behaviour). The single
## seam between the spell TREE (what the player equips) and the spell SCENES
## (BeamSpell / DivineRay / ...). Adding a new kind = one match arm here + a new
## spectacle scene; the loadout/UI/MP layers never change.
##
## Scripts are load()ed by path (never class_name) so the caller can invoke this
## from headless tools without early-compiling the autoload-referencing scenes.

const BEAM_PATH: String = "res://scripts/combat/BeamSpell.gd"
const RAY_PATH: String = "res://scripts/combat/DivineRay.gd"
const METEOR_PATH: String = "res://scripts/combat/MeteorSigil.gd"
const CONVERGENCE_PATH: String = "res://scripts/combat/StarConvergence.gd"
const NOVA_PATH: String = "res://scenes/combat/EnergyNova.tscn"


## Cast `spell` from `caster_pos` toward `target_pos`, parented under `arena`.
## `fallback_color` is the caster's current element colour (used when the SpellDef
## inherits). Returns true if a spectacle was spawned.
static func cast(
	spell: SpellDef, arena: Node, caster_pos: Vector2, target_pos: Vector2,
	fallback_color: Color, effect: String = ""
) -> bool:
	if spell == null or arena == null or not arena.is_inside_tree():
		return false
	var col: Color = spell.resolve_color(fallback_color)
	var fx: String = effect if effect != "" else spell.effect  # elemental character
	var elem: int = resolve_element(spell)  # ailment applied on hit
	var aim: Vector2 = (target_pos - caster_pos)
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	match spell.kind:
		SpellDef.Kind.BEAM:
			var beam: Node2D = (load(BEAM_PATH) as GDScript).new()
			arena.add_child(beam)
			beam.set("element_id", elem)
			beam.fire(caster_pos, aim.normalized(), col, spell.length, spell.width, spell.damage, fx)
			return true
		SpellDef.Kind.DIVINE_RAY:
			# Lands on the ground point the player aims at, clamped to reach.
			var to: Vector2 = aim
			if to.length() > spell.reach:
				to = to.normalized() * spell.reach
			var ray: Node2D = (load(RAY_PATH) as GDScript).new()
			arena.add_child(ray)
			ray.set("element_id", elem)
			ray.strike(caster_pos + to, col, spell.radius, spell.damage, fx)
			return true
		SpellDef.Kind.METEOR:
			# Rains on the ground point the player aims at, clamped to reach.
			var mto: Vector2 = aim
			if mto.length() > spell.reach:
				mto = mto.normalized() * spell.reach
			var meteor: Node2D = (load(METEOR_PATH) as GDScript).new()
			arena.add_child(meteor)
			meteor.set("element_id", elem)
			meteor.rain(caster_pos + mto, col, spell.radius, spell.damage, spell.count, fx)
			return true
		SpellDef.Kind.CONVERGENCE:
			# Converges on the ground point the player aims at, clamped to reach.
			var cto: Vector2 = aim
			if cto.length() > spell.reach:
				cto = cto.normalized() * spell.reach
			var conv: Node2D = (load(CONVERGENCE_PATH) as GDScript).new()
			arena.add_child(conv)
			conv.set("element_id", elem)
			conv.converge(caster_pos + cto, col, spell.radius, spell.damage, fx)
			return true
		SpellDef.Kind.NOVA:
			var nova: Node2D = (load(NOVA_PATH) as PackedScene).instantiate()
			arena.add_child(nova)
			nova.set("element_id", elem)
			nova.call("activate_at", caster_pos)
			return true
		_:
			# Any unbuilt kind: safe no-op until its scene exists.
			return false


## Elemental ailment index (Elements.Element) a signature applies on hit: the
## SpellDef's explicit element if set, else mapped from its `effect` character.
static func resolve_element(spell: SpellDef) -> int:
	if spell.element >= 0:
		return spell.element
	match spell.effect:
		"frost":
			return Elements.Element.ICE
		"fire":
			return Elements.Element.FIRE
		"holy":
			return Elements.Element.LIGHTNING  # divine smite reads as a shock
		"arcane":
			return Elements.Element.ARCANE
	return Elements.Element.ARCANE
