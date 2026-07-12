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
const NOVA_PATH: String = "res://scenes/combat/EnergyNova.tscn"


## Cast `spell` from `caster_pos` toward `target_pos`, parented under `arena`.
## `fallback_color` is the caster's current element colour (used when the SpellDef
## inherits). Returns true if a spectacle was spawned.
static func cast(
	spell: SpellDef, arena: Node, caster_pos: Vector2, target_pos: Vector2, fallback_color: Color
) -> bool:
	if spell == null or arena == null or not arena.is_inside_tree():
		return false
	var col: Color = spell.resolve_color(fallback_color)
	var aim: Vector2 = (target_pos - caster_pos)
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	match spell.kind:
		SpellDef.Kind.BEAM:
			var beam: Node2D = (load(BEAM_PATH) as GDScript).new()
			arena.add_child(beam)
			beam.fire(caster_pos, aim.normalized(), col, spell.length, spell.width, spell.damage)
			return true
		SpellDef.Kind.DIVINE_RAY:
			# Lands on the ground point the player aims at, clamped to reach.
			var to: Vector2 = aim
			if to.length() > spell.reach:
				to = to.normalized() * spell.reach
			var ray: Node2D = (load(RAY_PATH) as GDScript).new()
			arena.add_child(ray)
			ray.strike(caster_pos + to, col, spell.radius, spell.damage)
			return true
		SpellDef.Kind.NOVA:
			var nova: Node2D = (load(NOVA_PATH) as PackedScene).instantiate()
			arena.add_child(nova)
			nova.call("activate_at", caster_pos)
			return true
		_:
			# METEOR + any unbuilt kind: safe no-op until its scene exists.
			return false
