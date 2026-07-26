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
const RUSH_PATH: String = "res://scripts/combat/LightningRush.gd"
const NOVA_PATH: String = "res://scenes/combat/EnergyNova.tscn"
const BOULDER_PATH: String = "res://scripts/combat/BoulderHurl.gd"
const PILLAR_PATH: String = "res://scripts/combat/RockPillar.gd"
const WALL_PATH: String = "res://scripts/combat/RockWall.gd"
const ICE_WALL_PATH: String = "res://scripts/combat/IceWall.gd"
const CHAIN_PATH: String = "res://scripts/combat/ChainBolt.gd"
const ZONE_PATH: String = "res://scripts/combat/ZoneSpell.gd"
const MISSILES_PATH: String = "res://scripts/combat/RuneOrbs.gd"
const TETHER_PATH: String = "res://scripts/combat/DrainTether.gd"
const FLURRY_PATH: String = "res://scripts/combat/BladeFlurry.gd"
const BLINK_PATH: String = "res://scripts/combat/BlinkStrike.gd"
const SHADOW_ROOT_PATH: String = "res://scripts/combat/ShadowRoot.gd"


## Cast `spell` from `caster_pos` toward `target_pos`, parented under `arena`.
## `fallback_color` is the caster's current element colour (used when the SpellDef
## inherits). Returns true if a spectacle was spawned.
##
## `caster` is optional and only consulted by kinds that MOVE the caster (today
## just BLINK_STRIKE). Passing it is what lets a self-displacing spell go through
## this one seam instead of needing bespoke handling in every caster — see the
## `blink_to` duck-typed contract on the BLINK_STRIKE arm below.
static func cast(
	spell: SpellDef, arena: Node, caster_pos: Vector2, target_pos: Vector2,
	fallback_color: Color, effect: String = "", caster: Node = null
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
			Juice.zoom_pull_camera(0.15, 0.45, 0.16, 0.55)  # pull back to reveal the pillar
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
			Juice.zoom_pull_camera(0.2, 0.9, 0.2, 0.7)  # widest pull — the bombardment
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
			Juice.zoom_pull_camera(0.22, 1.0, 0.3, 0.8)  # longest tell, biggest reveal
			return true
		SpellDef.Kind.RUSH:
			# Chidori: a jagged lightning lance ripping along the aim from the caster.
			var rush: Node2D = (load(RUSH_PATH) as GDScript).new()
			arena.add_child(rush)
			rush.set("element_id", elem)
			rush.call("rush", caster_pos, aim.normalized(), col, spell.length, spell.width, spell.damage, fx)
			return true
		SpellDef.Kind.NOVA:
			var nova: Node2D = (load(NOVA_PATH) as PackedScene).instantiate()
			arena.add_child(nova)
			nova.set("element_id", elem)
			nova.call("activate_at", caster_pos)
			return true
		SpellDef.Kind.BOULDER:
			# Rips a boulder from the ground and hurls it along the aim.
			var b: Node2D = (load(BOULDER_PATH) as GDScript).new()
			arena.add_child(b)
			b.set("element_id", elem)
			b.call("hurl", caster_pos, aim.normalized(), col, spell.radius, spell.damage, fx)
			return true
		SpellDef.Kind.PILLAR:
			# Erupts a stone pillar under the marked ground point (uppercut launch).
			var pto: Vector2 = aim
			if pto.length() > spell.reach:
				pto = pto.normalized() * spell.reach
			var pil: Node2D = (load(PILLAR_PATH) as GDScript).new()
			arena.add_child(pil)
			pil.set("element_id", elem)
			pil.call("erupt", caster_pos + pto, col, spell.radius, spell.damage, fx)
			Juice.zoom_pull_camera(0.13, 0.4, 0.14, 0.5)
			return true
		SpellDef.Kind.WALL:
			# Raises a temporary blocking stone wall in the aim direction.
			var wl: Node2D = (load(WALL_PATH) as GDScript).new()
			arena.add_child(wl)
			wl.set("element_id", elem)
			wl.call("raise_wall", caster_pos, aim.normalized(), col, fx)
			return true
		SpellDef.Kind.ICE_WALL:
			# Raises a temporary blocking ICE wall in the aim direction (chills on touch).
			var iw: Node2D = (load(ICE_WALL_PATH) as GDScript).new()
			arena.add_child(iw)
			iw.set("element_id", elem)
			iw.call("raise_wall", caster_pos, aim.normalized(), col, fx)
			return true
		SpellDef.Kind.CHAIN:
			# A jagged bolt that leaps enemy-to-enemy from the caster along the aim.
			var ch: Node2D = (load(CHAIN_PATH) as GDScript).new()
			arena.add_child(ch)
			ch.set("element_id", elem)
			ch.call("chain", caster_pos, aim.normalized(), col, spell.count, spell.reach, spell.damage, fx)
			return true
		SpellDef.Kind.ZONE:
			# Shadow is no longer a placed puddle recoloured from blizzard — it ERUPTS
			# from the caster's feet and races along the ground to ROOT whoever the
			# tendrils catch, with a real dodge window before the grip locks. Same
			# ZONE kind (so loadouts/saves are untouched); the spectacle forks here.
			if fx == "shadow":
				var sr: Node2D = (load(SHADOW_ROOT_PATH) as GDScript).new()
				arena.add_child(sr)
				sr.set("element_id", elem)
				sr.call("erupt", caster_pos, aim, col, spell.radius, spell.damage, fx)
				Juice.zoom_pull_camera(0.12, 0.4, 0.14, 0.5)
				return true
			# A persistent ground field placed at the marked point (clamped to reach).
			var zto: Vector2 = aim
			if zto.length() > spell.reach:
				zto = zto.normalized() * spell.reach
			var zn: Node2D = (load(ZONE_PATH) as GDScript).new()
			arena.add_child(zn)
			zn.set("element_id", elem)
			# `length` doubles as the field lifetime for a ZONE (cast_time must stay 0
			# so it doesn't trigger the levitating channel); default 4.5s.
			var zlife: float = spell.length if spell.length > 0.5 and spell.length < 20.0 else 4.5
			zn.call("open", caster_pos + zto, col, spell.radius, spell.damage, fx, zlife)
			Juice.zoom_pull_camera(0.14, 0.5, 0.16, 0.55)
			return true
		SpellDef.Kind.MISSILES:
			# A fan of homing rune-orbs launched along the aim from the weapon tip.
			var mo: Node2D = (load(MISSILES_PATH) as GDScript).new()
			arena.add_child(mo)
			mo.set("element_id", elem)
			mo.call("launch", caster_pos, aim.normalized(), col, spell.count, spell.damage, fx)
			return true
		SpellDef.Kind.TETHER:
			# A life-drain tether locking the nearest enemy in the aim direction.
			var te: Node2D = (load(TETHER_PATH) as GDScript).new()
			arena.add_child(te)
			te.set("element_id", elem)
			te.call("tether", caster_pos, aim.normalized(), col, spell.damage, fx)
			return true
		SpellDef.Kind.BLINK_STRIKE:
			# Shadow-step: the caster TELEPORTS to the marked point mid-slash, and the
			# cut lands along the path travelled. Previously this had no arm here at
			# all — Hero special-cased it, so blink was dead in every other caster
			# (the playground included). The displacement is delegated: a caster that
			# implements `blink_to(dest) -> Vector2` vets the landing spot (Hero
			# refuses to blink into a pit) and returns where it ACTUALLY ended up, so
			# the slash is drawn to the real destination. Casters without the method
			# still get the cut, they just don't move.
			var bto: Vector2 = aim
			if bto.length() > spell.reach:
				bto = bto.normalized() * spell.reach
			var dest: Vector2 = caster_pos + bto
			if caster != null and caster.has_method("blink_to"):
				dest = caster.call("blink_to", dest)
			var bs: Node2D = (load(BLINK_PATH) as GDScript).new()
			arena.add_child(bs)
			bs.set("element_id", elem)
			bs.call("strike", caster_pos, dest, col, spell.damage, fx)
			return true
		SpellDef.Kind.FLURRY:
			# A burst of dashing crescent slashes in front of the caster.
			var fl: Node2D = (load(FLURRY_PATH) as GDScript).new()
			arena.add_child(fl)
			fl.set("element_id", elem)
			fl.call("flurry", caster_pos, aim.normalized(), col, spell.damage, spell.count, fx)
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
		"lightning":
			return Elements.Element.LIGHTNING
		"shadow":
			return Elements.Element.SHADOW
		"earth":
			return Elements.Element.EARTH
		"wind":
			return Elements.Element.WIND
	return Elements.Element.ARCANE
