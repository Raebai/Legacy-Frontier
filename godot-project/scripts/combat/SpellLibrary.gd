class_name SpellLibrary
extends RefCounted
## The curated signature spells — the playable slice of the spell tree. Each is a
## SpellDef (pure data); build() returns them in cycle order. Hero equips one at a
## time (cycle with V, unleash with the Ultimate key), MP-gated. This is the code
## home of the tree today; any entry can move to a data/spells/*.tres later
## without touching the caster/loadout/UI (SpellDef is .tres-authorable).
##
## Flavour is the Frieren / isekai / divine north-star: giant sigils, screen-
## crossing beams, pillars of holy light. See docs/v2.0-spell-system-design.md
## for the full class / subclass / blend tree these are drawn from.

## Element indices (Elements.Element): FIRE 0, ICE 1, LIGHTNING 2, SHADOW 3, ARCANE 4.


## Build the ordered signature list. Fresh instances each call (Resources are
## reference types — never share mutable state across heroes).
static func build() -> Array:
	return [
		_beam("zoltraak", "Zoltraak · Arcane Beam",
			"Frieren's ordinary offensive magic, perfected. A sigil blooms and a "
			+ "lance of mana crosses the whole arena.",
			4, 45, 3.2, 48, 1150.0, 30.0),      # ARCANE / magenta
		_beam("frostpiercer", "Frostpiercer",
			"A long, thin spear of absolute cold — pierces a whole rank in a line.",
			1, 40, 3.0, 40, 1250.0, 22.0),      # ICE / cyan
		_beam("infernal_lance", "Infernal Lance",
			"A fat, roaring beam of fire. Shorter reach, brutal width.",
			0, 55, 4.0, 58, 900.0, 42.0),       # FIRE / orange
		_ray("judgment", "Judgment · Divine Ray",
			"A seal opens in the heavens and a pillar of holy light smites the "
			+ "ground you mark. The isekai divine descent.",
			Color(1.0, 0.92, 0.55), 50, 4.0, 54, 92.0),   # holy gold (no element)
		_ray("heavens_verdict", "Heaven's Verdict",
			"A vast divine circle and a cataclysmic ray — wide footprint, heavy toll.",
			Color(1.0, 0.86, 0.4), 68, 5.5, 64, 140.0),   # bright gold, big radius
		_meteor("meteor_sigil", "Meteor Sigil",
			"A colossal sigil opens in the sky and a barrage of meteors rains over "
			+ "the marked ground. The isekai bombardment.",
			0, 72, 6.0, 22, 140.0, 11),                   # FIRE / orange, 11 meteors
	]


static func _meteor(
	id: String, name: String, desc: String, element: int,
	mp: int, cd: float, dmg: int, radius: float, count: int
) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.kind = SpellDef.Kind.METEOR
	s.element = element
	s.use_element_color = true
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.radius = radius
	s.count = count
	s.reach = 300.0
	return s


static func _beam(
	id: String, name: String, desc: String, element: int,
	mp: int, cd: float, dmg: int, length: float, width: float
) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.kind = SpellDef.Kind.BEAM
	s.element = element
	s.use_element_color = true
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.length = length
	s.width = width
	return s


static func _ray(
	id: String, name: String, desc: String, color: Color,
	mp: int, cd: float, dmg: int, radius: float
) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.kind = SpellDef.Kind.DIVINE_RAY
	s.use_element_color = false
	s.color = color
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.radius = radius
	s.reach = 280.0
	return s
