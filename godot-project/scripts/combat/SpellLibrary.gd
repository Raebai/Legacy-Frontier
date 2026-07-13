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


## Each class's themed signature loadout — the hero-fantasy ultimate FIRST, a
## thematic alt second (cycle with V). Fresh instances every call. Class ids match
## Hero.HeroClass (0 ARCANIST .. 7 WARLOCK). Unknown ids fall back to the full cycle.
static func build_for_class(class_id: int) -> Array:
	match class_id:
		0:  # ARCANIST — arcane
			return [_zoltraak(), _meteor_sigil()]
		1:  # SHADOWBLADE — shadow
			return [_umbral_lance(), _void_barrage()]
		2:  # BRAWLER — lightning (Chidori) + fire
			return [_chidori(), _infernal_lance()]
		3:  # JUGGERNAUT — earth
			return [_colossus_pillar(), _avalanche()]
		4:  # CLERIC — holy
			return [_heavens_verdict(), _judgment()]
		5:  # CRYOMANCER — ice
			return [_frostpiercer(), _frozen_comet()]
		6:  # STORMCALLER — lightning
			return [_tempest(), _chidori()]
		7:  # WARLOCK — shadow
			return [_void_barrage(), _umbral_lance()]
	return build()


## Build the ordered signature list. Fresh instances each call (Resources are
## reference types — never share mutable state across heroes).
static func build() -> Array:
	return [
		_zoltraak(), _frostpiercer(), _infernal_lance(),
		_judgment(), _heavens_verdict(), _meteor_sigil(),
	]


# ------------------------------------------------------------- named signatures
static func _zoltraak() -> SpellDef:
	return _beam("zoltraak", "Zoltraak · Arcane Beam",
		"Frieren's ordinary offensive magic, perfected. A sigil blooms and a "
		+ "lance of mana crosses the whole arena.",
		4, 45, 3.2, 48, 1150.0, 30.0)             # ARCANE / magenta


static func _frostpiercer() -> SpellDef:
	return _beam("frostpiercer", "Frostpiercer",
		"A long, thin spear of absolute cold — pierces a whole rank in a line.",
		1, 40, 3.0, 40, 1250.0, 22.0)             # ICE / cyan


static func _infernal_lance() -> SpellDef:
	return _beam("infernal_lance", "Infernal Lance",
		"A fat, roaring beam of fire. Shorter reach, brutal width.",
		0, 55, 4.0, 58, 900.0, 42.0)              # FIRE / orange


static func _judgment() -> SpellDef:
	return _ray("judgment", "Judgment · Divine Ray",
		"A seal opens in the heavens and a SINGLE pillar of holy light smites the "
		+ "exact ground you mark. Precise, punishing — dodge the tell or take the hit.",
		Color(1.0, 0.92, 0.55), 40, 2.6, 95, 70.0)


static func _heavens_verdict() -> SpellDef:
	return _convergence("heavens_verdict", "Heaven's Verdict",
		"The sky closes in a ring of radiant lances that slam together as one "
		+ "cataclysmic nova. The longest telegraph in the tree — and the hardest-hitting.",
		Color(1.0, 0.86, 0.4), 85, 7.0, 130, 160.0)


static func _meteor_sigil() -> SpellDef:
	return _meteor("meteor_sigil", "Meteor Sigil",
		"A colossal sigil opens in the sky and a barrage of meteors rains over "
		+ "the marked ground. The isekai bombardment.",
		0, 72, 6.0, 22, 140.0, 11)                # FIRE / orange, 11 meteors


## CHIDORI — the Brawler's ultimate. A jagged lightning lance rips down the aim.
static func _chidori() -> SpellDef:
	var s := SpellDef.new()
	s.id = "chidori"
	s.display_name = "Chidori · Thunderclap"
	s.description = "Charge lightning into the fist, then RIP a jagged lance down "\
		+ "the aim — everything on the line is shocked and thrown, and the bolt forks to a straggler."
	s.kind = SpellDef.Kind.RUSH
	s.element = Elements.Element.LIGHTNING
	s.use_element_color = true
	s.effect = "lightning"
	s.mp_cost = 50
	s.cooldown = 3.4
	s.damage = 62
	s.length = 620.0
	s.width = 26.0
	return s


## UMBRAL LANCE — Shadowblade / Warlock. A violet beam that weakens on hit.
static func _umbral_lance() -> SpellDef:
	return _beam("umbral_lance", "Umbral Lance",
		"A lance of condensed shadow — pierces a line and leaves the struck WEAKENED.",
		Elements.Element.SHADOW, 46, 3.4, 50, 1100.0, 30.0)


## VOID BARRAGE — Warlock / Shadowblade. A shadow meteor bombardment (Unstable pops).
static func _void_barrage() -> SpellDef:
	return _meteor("void_barrage", "Void Barrage",
		"A rift tears open and a rain of collapsing void-shards hammers the marked ground.",
		Elements.Element.SHADOW, 70, 6.2, 22, 135.0, 11)


## COLOSSUS PILLAR — Juggernaut. A titanic stone spire slams the marked spot (Stagger).
static func _colossus_pillar() -> SpellDef:
	var s := _ray("colossus_pillar", "Colossus Pillar",
		"The earth answers: a titanic stone spire erupts on the marked ground, "
		+ "staggering everything caught beneath it.",
		Elements.color(Elements.Element.EARTH), 42, 2.8, 96, 74.0)
	s.element = Elements.Element.EARTH  # Stagger ailment (not the holy default)
	return s


## AVALANCHE — Juggernaut. An earth meteor bombardment (falling boulders, Stagger).
static func _avalanche() -> SpellDef:
	return _meteor("avalanche", "Avalanche",
		"A cliff-face of boulders rains down over the marked ground.",
		Elements.Element.EARTH, 72, 6.4, 22, 145.0, 11)


## TEMPEST — Stormcaller. A crackling lightning beam that shocks a line.
static func _tempest() -> SpellDef:
	return _beam("tempest", "Tempest",
		"A screaming beam of raw storm — everything on the line is shocked.",
		Elements.Element.LIGHTNING, 48, 3.2, 50, 1200.0, 28.0)


## FROZEN COMET — Cryomancer. An ice meteor bombardment (Chill → Freeze).
static func _frozen_comet() -> SpellDef:
	return _meteor("frozen_comet", "Frozen Comet",
		"Shards of a shattered comet rain from a frozen sky over the marked ground.",
		Elements.Element.ICE, 70, 6.0, 22, 138.0, 11)


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
