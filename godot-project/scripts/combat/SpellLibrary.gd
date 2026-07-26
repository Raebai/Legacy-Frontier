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
		0:  # ARCANIST — arcane (keep the canonical Zoltraak beam; rune-orbs replace the meteor-clone)
			return [_zoltraak(), _rune_orbs()]
		1:  # SHADOWBLADE — shadow (mobility+burst: teleport-strike + blade flurry, NOT beams)
			return [_blink_strike(), _blade_flurry()]
		2:  # BRAWLER — lightning (Chidori) + fire
			return [_chidori(), _infernal_lance()]
		3:  # JUGGERNAUT — earth (the full earthbending kit: throw / pillar / wall + legacy ults)
			return [_boulder_hurl(), _rock_pillar(), _rock_wall(), _colossus_pillar(), _avalanche()]
		4:  # CLERIC — holy
			return [_heavens_verdict(), _judgment()]
		5:  # CRYOMANCER — ice (zoning: ice wall + blizzard field, no beam/meteor-clone)
			return [_ice_wall(), _blizzard()]
		6:  # STORMCALLER — lightning (chain leap, not a recolored beam)
			return [_chain_lightning(), _chidori()]
		7:  # WARLOCK — shadow (attrition: void zone + life-drain tether, not beams/meteors)
			return [_void_zone(), _drain_tether()]
	return build()


## Build the ordered signature list. Fresh instances each call (Resources are
## reference types — never share mutable state across heroes).
static func build() -> Array:
	return [
		_zoltraak(), _frostpiercer(), _infernal_lance(),
		_judgment(), _heavens_verdict(), _meteor_sigil(),
	]


## EVERY named spell in the tree, grouped by kind — for the spell-audit sandbox so
## each one can be reviewed individually. Fresh instances each call.
static func build_all() -> Array:
	return [
		# BEAMS (line lance)
		_zoltraak(), _frostpiercer(), _infernal_lance(), _umbral_lance(), _tempest(),
		# RUSH / CHAIN (lightning lances)
		_chidori(), _chain_lightning(),
		# DIVINE RAY / PILLAR (single-point smite)
		_judgment(), _colossus_pillar(), _rock_pillar(),
		# CONVERGENCE (radial finisher)
		_heavens_verdict(),
		# METEOR (bombardment)
		_meteor_sigil(), _void_barrage(), _avalanche(), _frozen_comet(),
		# MISSILES / BOULDER (projectiles)
		_rune_orbs(), _boulder_hurl(),
		# BLINK / FLURRY (melee bursts)
		_blink_strike(), _blade_flurry(),
		# ZONE / TETHER (fields + drain)
		_void_zone(), _blizzard(), _drain_tether(),
		# WALLS (barriers)
		_rock_wall(), _ice_wall(),
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
	# ...and the SPECTACLE must be stone too. `_ray()` hardcodes effect="holy" for
	# Judgment's sake, which this spell was silently inheriting — so a "titanic
	# stone spire" rendered as a holy light column wearing an earth-brown tint.
	s.effect = "earth"
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


## ICE WALL — Cryomancer. A temporary blocking barrier of ice that CHILLS on touch.
## Bespoke zoning identity (replaces the Frostpiercer beam-clone).
static func _ice_wall() -> SpellDef:
	var s := SpellDef.new()
	s.id = "ice_wall"
	s.display_name = "Ice Wall"
	s.description = "Raise a crystalline wall of ice in the aim direction — it blocks "\
		+ "enemy bodies and projectiles for a few seconds and CHILLS anything pressed "\
		+ "against it, then shatters."
	s.kind = SpellDef.Kind.ICE_WALL
	s.element = Elements.Element.ICE
	s.use_element_color = true
	s.effect = "frost"
	s.mp_cost = 40
	s.cooldown = 5.0
	s.damage = 0
	s.reach = 90.0
	return s


## CHAIN LIGHTNING — Stormcaller. A jagged bolt that leaps enemy-to-enemy.
## Bespoke mobile-chain identity (replaces the Tempest beam-clone). `count` = hops,
## `reach` = hop range.
static func _chain_lightning() -> SpellDef:
	var s := SpellDef.new()
	s.id = "chain_lightning"
	s.display_name = "Chain Lightning"
	s.description = "Loose a bolt that LEAPS from foe to foe — up to five links, "\
		+ "shocking each, the damage falling off with every jump."
	s.kind = SpellDef.Kind.CHAIN
	s.element = Elements.Element.LIGHTNING
	s.use_element_color = true
	s.effect = "lightning"
	s.mp_cost = 44
	s.cooldown = 3.0
	s.damage = 46
	s.count = 5      # max hops
	s.reach = 240.0  # hop range
	return s


## ARCANE MISSILES — Arcanist. A fan of homing rune-orbs (replaces the meteor-clone).
static func _rune_orbs() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rune_orbs"
	s.display_name = "Arcane Missiles"
	s.description = "Loose a fan of spinning rune-orbs that HOME onto your foes and "\
		+ "pop in precise arcane bursts."
	s.kind = SpellDef.Kind.MISSILES
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = "arcane"
	s.mp_cost = 50
	s.cooldown = 3.4
	s.damage = 24  # per orb
	s.count = 6
	return s


## SHADOW STEP — Shadowblade signature. Teleport-strike (replaces the Umbral beam).
static func _blink_strike() -> SpellDef:
	var s := SpellDef.new()
	s.id = "blink_strike"
	s.display_name = "Shadow Step"
	s.description = "Dissolve into shadow and reappear at the marked point mid-slash "\
		+ "— everything on the crossed line is cut and left WEAKENED."
	s.kind = SpellDef.Kind.BLINK_STRIKE
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 48
	s.cooldown = 3.2
	s.damage = 85  # was 55 — the assassin's signature should HURT (maker: "not strong")
	s.reach = 300.0  # blink distance
	return s


## BLADE FLURRY — Shadowblade alt. A burst of crescent slashes (replaces Void Barrage).
static func _blade_flurry() -> SpellDef:
	var s := SpellDef.new()
	s.id = "blade_flurry"
	s.display_name = "Blade Flurry"
	s.description = "A blur of dashing slashes fans across the front — every foe in "\
		+ "the arc is cut again and again."
	s.kind = SpellDef.Kind.FLURRY
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 44
	s.cooldown = 3.0
	s.damage = 16  # per slash
	s.count = 6
	return s


## VOID ZONE — Warlock signature. A persistent shadow field (replaces Void Barrage).
static func _void_zone() -> SpellDef:
	var s := SpellDef.new()
	s.id = "void_zone"
	s.display_name = "Void Zone"
	s.description = "Open a pool of writhing void on the marked ground — foes inside "\
		+ "bleed shadow and are WEAKENED for as long as they linger."
	s.kind = SpellDef.Kind.ZONE
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 60
	s.cooldown = 6.5
	s.damage = 10   # per tick
	s.radius = 130.0
	s.reach = 300.0
	s.length = 4.8  # field lifetime (see SpellCaster ZONE arm)
	return s


## LIFE-DRAIN TETHER — Warlock alt. Drain a foe + heal yourself (replaces Umbral beam).
static func _drain_tether() -> SpellDef:
	var s := SpellDef.new()
	s.id = "drain_tether"
	s.display_name = "Drain Tether"
	s.description = "Snap a writhing tendril to the nearest foe and DRAIN its life — "\
		+ "it bleeds while you are healed."
	s.kind = SpellDef.Kind.TETHER
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 46
	s.cooldown = 3.4
	s.damage = 11  # per tick
	return s


## BLIZZARD — Cryomancer alt. A persistent frost field (replaces the Frozen Comet meteor).
static func _blizzard() -> SpellDef:
	var s := SpellDef.new()
	s.id = "blizzard"
	s.display_name = "Blizzard"
	s.description = "Call a swirling snow field over the marked ground — everything "\
		+ "inside is chilled toward a FREEZE."
	s.kind = SpellDef.Kind.ZONE
	s.element = Elements.Element.ICE
	s.use_element_color = true
	s.effect = "frost"
	s.mp_cost = 58
	s.cooldown = 6.0
	s.damage = 8   # per tick
	s.radius = 135.0
	s.reach = 300.0
	s.length = 4.2  # field lifetime
	return s


## BOULDER HURL — Juggernaut earth. Rip a boulder from the ground and throw it.
static func _boulder_hurl() -> SpellDef:
	var s := SpellDef.new()
	s.id = "boulder_hurl"
	s.display_name = "Boulder Hurl"
	s.description = "Rip a boulder from the earth and HURL it down the aim — it shatters on impact, throwing everything back."
	s.kind = SpellDef.Kind.BOULDER
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = "earth"
	s.mp_cost = 50
	s.cooldown = 3.4
	s.damage = 52
	s.radius = 84.0
	return s


## ROCK PILLAR — Juggernaut earth. A telegraphed eruption that launches skyward.
static func _rock_pillar() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rock_pillar"
	s.display_name = "Rock Pillar"
	s.description = "A telegraphed stone spire ERUPTS from the ground, launching everything in its footprint skyward."
	s.kind = SpellDef.Kind.PILLAR
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = "earth"
	s.mp_cost = 52
	s.cooldown = 4.0
	s.damage = 58
	s.radius = 66.0
	s.reach = 280.0
	return s


## ROCK WALL — Juggernaut earth. A temporary blocking barrier of stone (no damage).
static func _rock_wall() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rock_wall"
	s.display_name = "Rock Wall"
	s.description = "Raise a temporary wall of stone in the aim direction — it blocks enemy bodies and projectiles for a few seconds, then crumbles."
	s.kind = SpellDef.Kind.WALL
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = "earth"
	s.mp_cost = 40
	s.cooldown = 5.0
	s.damage = 0
	s.reach = 90.0
	return s


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
	s.cast_time = 1.1  # levitating windup
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
	s.cast_time = 1.0  # levitating windup
	return s


## Elemental particle CHARACTER from the element index (see Elements.Element).
## Every element now has its own bespoke spectacle skin (was: only fire/frost/
## arcane; shadow/earth/wind/lightning fell through to arcane garnish).
static func _effect_for_element(element: int) -> String:
	match element:
		0: return "fire"       # FIRE
		1: return "frost"      # ICE
		2: return "lightning"  # LIGHTNING — jagged crackle + sparks
		3: return "shadow"     # SHADOW — inky violet tendrils
		5: return "earth"      # EARTH — chunky amber debris + dust
		6: return "holy"       # HOLY
		7: return "wind"       # WIND — fast teal wisps
		_: return "arcane"     # ARCANE (4) + anything unmapped


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
	s.cast_time = 1.0  # levitating windup
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
	s.cast_time = 1.3  # the finisher: longest levitating windup
	return s
