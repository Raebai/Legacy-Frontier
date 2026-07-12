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
			"A seal opens in the heavens and a SINGLE pillar of holy light smites the "
			+ "exact ground you mark. Precise, punishing — dodge the tell or take the hit.",
			Color(1.0, 0.92, 0.55), 40, 2.6, 95, 70.0),   # single pillar, high-commit point strike
		_convergence("heavens_verdict", "Heaven's Verdict",
			"The sky closes in a ring of radiant lances that slam together as one "
			+ "cataclysmic nova. The longest telegraph in the tree — and the hardest-hitting.",
			Color(1.0, 0.86, 0.4), 85, 7.0, 130, 160.0),  # slow, biggest single hit in the kit
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
	s.effect = _effect_for_element(element)
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
	s.effect = _effect_for_element(element)
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.length = length
	s.width = width
	return s


## Elemental particle character from the element index (see Elements.Element):
## FIRE 0 -> fire, ICE 1 -> frost, ARCANE 4 -> arcane; others fall back to arcane.
static func _effect_for_element(element: int) -> String:
	match element:
		0: return "fire"
		1: return "frost"
		_: return "arcane"


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
	s.effect = "holy"
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.radius = radius
	s.reach = 280.0
	return s


## Heaven's Verdict's spectacle: a radial star-convergence nova (SpellDef.Kind
## .CONVERGENCE). Holy, no element tint; the longest telegraph + biggest single hit.
static func _convergence(
	id: String, name: String, desc: String, color: Color,
	mp: int, cd: float, dmg: int, radius: float
) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.kind = SpellDef.Kind.CONVERGENCE
	s.use_element_color = false
	s.color = color
	s.effect = "holy"
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.radius = radius
	s.reach = 320.0
	return s
