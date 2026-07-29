class_name SpellLibrary
extends RefCounted
## The curated signature spells — the playable slice of the spell tree. Each is a
## SpellDef (pure data); build() returns them in cycle order. Hero equips one at a
## time (cycle with V, unleash with the Ultimate key), MP-gated. This is the code
## home of the tree today; any entry can move to a data/spells/*.tres later
## without touching the caster/loadout/UI (SpellDef is .tres-authorable).
##
## Flavour is the isekai / high-fantasy / divine north-star: giant sigils, screen-
## crossing beams, pillars of holy light. See docs/v2.0-spell-system-design.md
## for the full class / subclass / blend tree these are drawn from.
##
## NAMES ARE OURS. Mechanics are not ownable; named techniques from named works
## are. Nothing in this file borrows a spell name from another property — see the
## IP pass in docs/superpowers/specs/2026-07-27-swordsman-and-signature-ults.md
## §8, and the banned-string guard in tools/slice8_test_spell_kits.gd that stops
## a borrowed name quietly coming back.

## Element indices (Elements.Element): FIRE 0, ICE 1, LIGHTNING 2, SHADOW 3,
## ARCANE 4, EARTH 5, HOLY 6, WIND 7.
##
## EVERY spell declares a real element (never the SpellDef default of -1). Two
## things downstream depend on it and both fail QUIETLY when it is missing:
## SpellCaster.resolve_element() falls back to guessing from the `effect` string
## (and its "holy" arm answers LIGHTNING, a legacy from before HOLY existed as an
## element), and SpellReactor.register() drops an element-less effect out of the
## reaction system entirely. A spell with no element is therefore a spell with the
## wrong ailment AND no reactions — see the effect/element invariant test.


# ---------------------------------------------------------------- class kits
## The four spell slots + the ult slot, in the order they are handed to the hero.
## Slots 0-3 are the four spell slots and hold non-ULT spells; slot 4 is the ult
## slot (SpellTier.slot_accepts_ult). Tier is DERIVED from cast time / cooldown /
## MP, so a kit cannot lie about which shelf a spell sits on — retune a spell past
## the ult thresholds and it stops being legal in slots 0-3, loudly, in the tests.
##
## The keys are ROLES, not flavour. A kit that is four variations of one idea is a
## kit with one answer, so every class fills each role exactly once:
##   damage  — the reliable line you throw all fight
##   control — zoning: a field, a barrier, something that shapes the floor
##   answer  — the get-out: mobility, a gap-close, or a defensive / sustain tool
##   payoff  — the biggest non-ult hit in the kit, the one you set up for
##   ult     — the finisher, and the only slot a screen-crossing beam fits in
const ROLE_ORDER: Array[String] = ["damage", "control", "answer", "payoff", "ult"]

## Per-class kit, indexed by Hero.HeroClass (0 ARCANIST .. 7 WARLOCK).
##
## WHY YOU COULD ONLY EVER SEE ONE OR TWO BEAMS. Two causes stacked:
##
##   1. `_beam()` used to hand every beam the same 1.0 s channel, which is past
##      SpellTier.ULT_CAST_TIME — so all five were ULT-tier and only ONE could be
##      equipped at a time, by anyone, ever.
##   2. Only two of the five had a home in any class kit (the Arcanist's and the
##      Brawler's). `frostpiercer`, `umbral_lance` and `tempest` existed only in
##      build_all(), the review harness — unreachable in real play, while the
##      class-select cards cheerfully advertised all three.
##
## Both are fixed here. The family now spans two shelves — The Ordinary Spell and
## Frostpiercer are short-channel HEAVYs that live in DAMAGE slots and get thrown
## all fight; Infernal Lance, Umbral Lance and Tempest keep the full channel and
## are their class's ULT. All five are reachable, three of them at once across the
## roster, and the clash ladder finally has a gap to work with: a HEAVY beam is
## STOPPED by an ice wall and CARVES a rock wall, where before every beam breached
## every barrier and every beam-vs-beam was a mutual annihilation.
##
## The non-ult pool is 16 spells across 8 classes x 4 slots, so tools are SHARED
## between classes on purpose (the Brawler and the Stormcaller have always shared
## the Thunderclap). What must stay distinct is the four roles WITHIN a kit. Note
## a spell's role is per-KIT, not a property of the spell: Shadow Step is the
## Arcanist's escape and the Shadowblade's finisher, which is exactly why the
## roles live in this table and not on SpellDef.
##
## TWO THINGS THE POOL CANNOT CURRENTLY GIVE, both content gaps rather than kit
## choices, and both worth fixing with new spells rather than more reshuffling:
##   - MOBILITY is the one role every class needs and Shadow Step is the only pure
##     mobility tool that is not somebody's signature, so it carries four kits.
##   - Rift Dagger stays in the SHADOWBLADE kit ONLY. Not a balance call: it is a
##     two-beat spell (throw, then press again to tear through to the anchor), and
##     `tools/slice_test_summon.gd` reconfigures ONE hero through all eight classes
##     without freeing the anchor between them — so the second class holding it
##     takes the RECALL beat and never starts a summon windup. That is a fixture
##     bug in that test, not a fact about the spell; until it resets the anchor per
##     class, a second kit holding this spell turns that suite red. See the handoff.
const CLASS_KITS: Array[Dictionary] = [
	# 0 ARCANIST — ranged arcane zoner. The Ordinary Spell is the damage line it was
	# always described as being; the blink is the classic mage get-out; the spire is
	# the only conjuration heavy enough to be a payoff.
	{"damage": "ordinary_spell", "control": "blizzard", "answer": "blink_strike",
		"payoff": "rock_pillar", "ult": "meteor_sigil"},
	# 1 SHADOWBLADE — in-and-out assassin. Every entry is one of its own annotated
	# spells. Shadow Step is the PAYOFF, not the mobility: 85 in a 64 px burst is
	# the biggest non-ult hit in the tree, and Rift Dagger is the actual get-out.
	{"damage": "blade_flurry", "control": "creeping_shade", "answer": "rift_dagger",
		"payoff": "blink_strike", "ult": "umbral_lance"},
	# 2 BRAWLER — pure melee. The Rock Wall is its "answer" for a reason no other
	# class gets: the wall's second beat is a PUNCH (the two-beat shove), so a
	# defensive spell doubles as a brawler verb.
	{"damage": "thunderclap", "control": "chain_lightning", "answer": "rock_wall",
		"payoff": "boulder_hurl", "ult": "infernal_lance"},
	# 3 JUGGERNAUT — siege tank. Its "answer" is SUSTAIN, not mobility: a tank's
	# defensive answer is not dying, and the tether is the only sustain in the pool.
	# Deliberately off-school, like the Warlock's wall.
	{"damage": "boulder_hurl", "control": "rock_wall", "answer": "drain_tether",
		"payoff": "rock_pillar", "ult": "colossus_pillar"},
	# 4 CLERIC — radiant lifesteal bruiser. The tether IS the class fantasy, so it
	# is the "answer" (sustain) rather than the damage line, and the chain reads as
	# a smite leaping between sinners.
	{"damage": "rune_orbs", "control": "ice_wall", "answer": "drain_tether",
		"payoff": "chain_lightning", "ult": "heavens_verdict"},
	# 5 CRYOMANCER — ice control. Frostpiercer to poke, field to slow, wall to stop,
	# blink to leave — and the Glacial Spine as the ult, which is where the newly
	# rebuilt floor-line spectacle finally becomes reachable in real play at all.
	{"damage": "frostpiercer", "control": "blizzard", "answer": "ice_wall",
		"payoff": "blink_strike", "ult": "frozen_comet"},
	# 6 STORMCALLER — hyper-mobile chain caster, so the blink is the on-fantasy
	# answer. Blizzard is not filler: a LIGHTNING beam fired through an ICE field is
	# ReactionTable's `supercharge`, so this kit sets up its own ult (Tempest, BEAM
	# + LIGHTNING) with its control slot.
	{"damage": "chain_lightning", "control": "blizzard", "answer": "blink_strike",
		"payoff": "thunderclap", "ult": "tempest"},
	# 7 WARLOCK — dark attrition. Drain to live, root to hold, shade to finish. The
	# wall is the off-school pick: nothing in the shadow school is a get-out, and a
	# caster with no defensive answer is a caster who just dies to a gap-close.
	{"damage": "drain_tether", "control": "void_zone", "answer": "ice_wall",
		"payoff": "creeping_shade", "ult": "void_barrage"},
	# 8 SWORDSAINT — the guard-and-punish duelist. Its real defensive verb is not in
	# this table at all: RMB is a held BLADE guard (ParryRing's shrinking ring) that
	# banks what it turns away and returns it as one unsheathe cut. So the kit's job
	# is only to get it INTO range and keep it there.
	#
	#   damage  Blade Flurry — the blade, thrown all fight. On-fantasy and already
	#           the closest thing in the pool to a sword.
	#   control Rock Wall — a duelist SHAPES the floor rather than zoning with magic:
	#           drop a wall across a ranged class's line and the fight has to happen
	#           where it wants it. Same reasoning as the Brawler's pick.
	#   answer  Shadow Step — for a duelist the get-out is IN, not out. This class has
	#           no blink on R (mobility2 is an uppercut), so the gap-close lives here.
	#   payoff  Boulder Hurl — the only non-magic heavy in the pool; he rips the floor
	#           up and throws it.
	#   ult     Judgment · Divine Ray — see the PLACEHOLDER note below.
	#
	# ⚠ THE ULT IS A PLACEHOLDER, and deliberately a useful one. The class's authored
	# signature is HORIZON CUT — a travelling curved wall of edge that occupies a
	# vertical BAND you choose with the aim (`scripts/combat/HorizonArc.gd`, built and
	# covered by tools/slice9_test_swordsaint.gd). It cannot be equipped yet because a
	# SpellDef.Kind and a SpellCaster arm have to be appended first, and both files
	# were owned elsewhere when this landed. Judgment holds the slot in the meantime
	# because it is ULT-tier (cast_time 1.0) AND because it was equipped by NOBODY —
	# it existed only in build_all(), the review harness, which is exactly the
	# unreachable-spell gap the kit table was introduced to close. Swapping this one
	# id is the last step of the Horizon Cut handoff.
	{"damage": "blade_flurry", "control": "rock_wall", "answer": "blink_strike",
		"payoff": "boulder_hurl", "ult": "horizon_cut"},
]


## The role -> spell-id map for a class, or {} for an unknown id. Public so the
## tests can assert the SHAPE of a kit (four roles + an ult, all distinct) without
## re-deriving the roles from the built SpellDefs, which would only prove the
## tests and the table agree with each other.
static func kit_for_class(class_id: int) -> Dictionary:
	if class_id < 0 or class_id >= CLASS_KITS.size():
		return {}
	return CLASS_KITS[class_id]


## Each class's curated kit: four spells then the ult, in ROLE_ORDER, so slot
## index is the hero's V-cycle index AND the loadout-bar slot. Fresh instances
## every call. Class ids match Hero.HeroClass; unknown ids fall back to the full
## cycle so a new class never boots spell-less.
static func build_for_class(class_id: int) -> Array:
	var kit: Dictionary = kit_for_class(class_id)
	if kit.is_empty():
		return build()
	var by_id: Dictionary = _spell_by_id()
	var out: Array = []
	for role: String in ROLE_ORDER:
		var s: Variant = by_id.get(String(kit.get(role, "")))
		# A typo'd id drops that slot rather than crashing the hero mid-configure;
		# the kit test is what turns it into a loud failure at build time.
		if s != null:
			out.append(s)
	return out


## Every spell in the tree keyed by id. build_all() already mints new SpellDefs on
## every call, so the values here are never shared between two heroes.
static func _spell_by_id() -> Dictionary:
	var out: Dictionary = {}
	for s: SpellDef in build_all():
		out[s.id] = s
	return out


## Build the ordered signature list. Fresh instances each call (Resources are
## reference types — never share mutable state across heroes).
static func build() -> Array:
	return [
		_ordinary_spell(), _frostpiercer(), _infernal_lance(),
		_judgment(), _heavens_verdict(), _meteor_sigil(),
	]


## EVERY named spell in the tree, grouped by kind — for the spell-audit sandbox so
## each one can be reviewed individually. Fresh instances each call.
static func build_all() -> Array:
	return [
		# BEAMS (line lance)
		_ordinary_spell(), _frostpiercer(), _infernal_lance(), _umbral_lance(), _tempest(),
		# RUSH / CHAIN (lightning lances)
		_thunderclap(), _chain_lightning(),
		# DIVINE RAY / PILLAR (single-point smite)
		_judgment(), _colossus_pillar(), _rock_pillar(),
		# CONVERGENCE (radial finisher)
		_heavens_verdict(),
		# ARC (travelling crescent wall)
		_horizon_cut(),
		# METEOR (bombardment)
		_meteor_sigil(), _void_barrage(), _avalanche(), _frozen_comet(),
		# MISSILES / BOULDER (projectiles)
		_rune_orbs(), _boulder_hurl(),
		# BLINK / FLURRY (melee bursts)
		_blink_strike(), _blade_flurry(),
		# ZONE / TETHER (fields + drain)
		_void_zone(), _blizzard(), _drain_tether(),
		# WALLS (barriers)
		_rock_wall(), _ice_wall(), _aegis_ward(),
		# NEW DELIVERY SHAPES (floor traveller + thrown anchor)
		_creeping_shade(), _rift_dagger(),
	]


# ------------------------------------------------------------- named signatures
## THE ORDINARY SPELL — Arcanist. Renamed in the IP pass: it used to carry a spell
## name borrowed from another work, and its description cited that work outright.
## Structure, not silhouettes. The FANTASY is untouched and is not anyone's
## property — the most basic offensive magic there is, practised until it is the
## only one you need. (The old name is deliberately not written here: the sweep in
## slice8_test_spell_kits.gd scans this file's SOURCE, comments included, so that
## a borrowed name cannot creep back in as an explanation of itself.)
##
## The rename also fixed a shelf that disagreed with the fantasy. At cast_time 1.0
## this was an ULT — a "basic spell" you could throw once a fight — so it is the
## short-channel HEAVY of the beam family and sits in the Arcanist's DAMAGE slot,
## which is what "the last one you need" is supposed to mean.
static func _ordinary_spell() -> SpellDef:
	return _beam("ordinary_spell", "The Ordinary Spell",
		"The first spell anyone learns, practised until it is the last one you "
		+ "need. A sigil blooms and a lance of mana crosses the whole arena.",
		4, 45, 3.2, 48, 1150.0, 30.0, 0.55)       # ARCANE / magenta — HEAVY


## FROSTPIERCER — Cryomancer. The thinnest, longest, cheapest beam in the family,
## so it is the other HEAVY: a precision poke you throw all fight, not a finisher.
static func _frostpiercer() -> SpellDef:
	return _beam("frostpiercer", "Frostpiercer",
		"A long, thin spear of absolute cold — pierces a whole rank in a line.",
		1, 40, 3.0, 40, 1250.0, 22.0, 0.5)        # ICE / cyan — HEAVY


## INFERNAL LANCE — Brawler's ult. The fattest, hardest-hitting beam (width 42),
## so it keeps the full 1.0 s channel and stays ULT: it out-weighs both HEAVY
## beams in a head-on clash instead of trading with them.
static func _infernal_lance() -> SpellDef:
	return _beam("infernal_lance", "Infernal Lance",
		"A fat, roaring beam of fire. Shorter reach, brutal width.",
		0, 55, 4.0, 58, 900.0, 42.0)              # FIRE / orange — ULT


## JUDGMENT — a single holy pillar. `_ray()` leaves `element` at the SpellDef
## default of -1, which was NOT harmless: SpellCaster.resolve_element() then guesses
## from effect=="holy" and answers LIGHTNING (a fallback from before HOLY existed
## as an element), so a pillar of holy light was applying a Shock, opposing EARTH
## instead of SHADOW, and failing the `elements_a: [FIRE, HOLY]` predicate on
## ReactionTable's own shatter_ice_barrier row. Declared explicitly, exactly as
## _colossus_pillar() already declares EARTH. The gold tint is unaffected —
## `_ray()` sets use_element_color = false, so `color` still wins the visual.
## HORIZON CUT — Swordsaint ult. A crescent wall of edge that widens as it travels
## and cuts at the HEIGHT you aimed at. Deflectable: a turned cut comes back.
##
## THREE SEPARATE DODGE WINDOWS, stacked, which is why it can hit this hard: the
## 1.25 s channel, then ~1.4 s of visible approach as it crosses the arena, then
## the height band itself — it cuts where you aimed, so ducking or jumping the band
## beats it outright. `length` is a travel BUDGET, not a range clamp, and `reach` is
## the half-height at full extension rather than a cast range; SpellCaster's ARC arm
## documents why it must not clamp them the way the placed bombardments do.
static func _horizon_cut() -> SpellDef:
	var s := SpellDef.new()
	s.id = "horizon_cut"
	s.display_name = "Horizon Cut"
	s.description = "Draw the blade slowly and a crescent leaves the sheath with "\
		+ "it — a curved wall of edge that widens as it crosses the arena and cuts "\
		+ "everything at the height you chose. Duck it, or be somewhere else."
	s.kind = SpellDef.Kind.ARC
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = "arcane"
	s.mp_cost = 78
	s.cooldown = 6.5
	s.damage = 110
	s.cast_time = 1.25   # channel tier — the first of its three dodge windows
	s.length = 900.0     # travel budget (px)
	s.width = 30.0       # thickness ALONG travel = the whole damaging depth
	s.radius = 90.0      # half-height at launch
	s.reach = 300.0      # half-height at full extension
	return s


static func _judgment() -> SpellDef:
	var s := _ray("judgment", "Judgment · Divine Ray",
		"A seal opens in the heavens and a SINGLE pillar of holy light smites the "
		+ "exact ground you mark. Precise, punishing — dodge the tell or take the hit.",
		Color(1.0, 0.92, 0.55), 40, 2.6, 95, 70.0)
	s.element = Elements.Element.HOLY  # Radiance burn, and opposes SHADOW
	return s


## HEAVEN'S VERDICT — Cleric's ult. Same missing-element bug as Judgment, with an
## extra bite: StarConvergence gates its ailment on `element_id >= 0`, so the
## biggest spell in the tree was landing 130 damage and applying NOTHING.
static func _heavens_verdict() -> SpellDef:
	var s := _convergence("heavens_verdict", "Heaven's Verdict",
		"The sky closes in a ring of radiant lances that slam together as one "
		+ "cataclysmic nova. The longest telegraph in the tree — and the hardest-hitting.",
		Color(1.0, 0.86, 0.4), 85, 7.0, 130, 160.0)
	s.element = Elements.Element.HOLY
	return s


static func _meteor_sigil() -> SpellDef:
	return _meteor("meteor_sigil", "Meteor Sigil",
		"A colossal sigil opens in the sky and a barrage of meteors rains over "
		+ "the marked ground. The isekai bombardment.",
		0, 72, 6.0, 22, 140.0, 11)                # FIRE / orange, 11 meteors


## THUNDERCLAP — the Brawler's lightning lance, and the Stormcaller's payoff. A
## jagged bolt rips down the aim from a charged fist.
##
## Renamed in the IP pass: the id was a named technique from a named work. Ids are
## checked (nothing persists spell ids — GameState saves the class and the gear
## slots, never a spell) so this one was safe to change outright rather than
## leaving a borrowed string load-bearing. `tools/lightning_agent_capture.gd`
## looks this up by id and needs the same edit; it is a throwaway capture tool
## owned elsewhere — see the handoff notes.
static func _thunderclap() -> SpellDef:
	var s := SpellDef.new()
	s.id = "thunderclap"
	s.display_name = "Thunderclap"
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


## UMBRAL LANCE — Shadowblade's ult. Kept on the full 1.0 s channel (ULT): it is
## the class's only ranged threat, so it has to be the one that wins the clash.
static func _umbral_lance() -> SpellDef:
	return _beam("umbral_lance", "Umbral Lance",
		"A lance of condensed shadow — pierces a line and leaves the struck WEAKENED.",
		Elements.Element.SHADOW, 46, 3.4, 50, 1100.0, 30.0)   # ULT


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


## TEMPEST — Stormcaller's ult. Full channel (ULT) because its kit is built to set
## it up: fire it through the Blizzard in the same kit's control slot and
## ReactionTable's `supercharge` row (LIGHTNING beam x ICE field) fires.
static func _tempest() -> SpellDef:
	return _beam("tempest", "Tempest",
		"A screaming beam of raw storm — everything on the line is shocked.",
		Elements.Element.LIGHTNING, 48, 3.2, 50, 1200.0, 28.0)   # ULT


## GLACIAL SPINE — Cryomancer. A crest of ice that erupts from the FLOOR at the
## aimed point and races outward along it (Chill → Freeze). Was "Frozen Comet",
## the fourth of four identical sky bombardments; the maker's playtest verdict
## was that the frost family "reads as more an AoE spell — I don't think it would
## be used much, let's change it so it's not just a random zone of frost". So it
## stopped being an area you drop and became a line you have to JUMP.
##
## AIM, NOT AUTO-AIM. The intended play is "aim at their feet and the spine comes
## up under them", but the spell never looks for a target: it erupts wherever the
## player pointed, and on empty ground if that is where they pointed. IceSpikeLine
## has the long version of this note — it is exactly the distinction a future
## reader will get wrong.
##
## Built by hand rather than through _meteor() because the shared factory's
## `radius`/`count` mean "bombardment footprint" and "how many meteors", and here
## they mean something else entirely (below). The KIND still has to be METEOR:
## SpellCaster's Kind->spectacle table is owned elsewhere, its METEOR arm already
## passes the aimed ground point clamped to reach, and MeteorSigil forks on
## effect=="frost" into IceSpikeLine. The other three meteors are untouched.
static func _frozen_comet() -> SpellDef:
	var s := SpellDef.new()
	s.id = "frozen_comet"          # id unchanged — loadouts/saves reference it
	s.display_name = "Glacial Spine"
	s.description = "Ice tears out of the ground where you aim and races along "\
		+ "the floor in both directions. It cannot be side-stepped — it is jumped."
	s.kind = SpellDef.Kind.METEOR
	s.element = Elements.Element.ICE
	s.use_element_color = true
	s.effect = "frost"             # THE fork key (see MeteorSigil.rain)
	s.mp_cost = 65
	s.cooldown = 6.0
	# Per SPIKE, and a body is speared by one spike, not by a stack of eleven
	# overlapping meteors — so this is the whole hit, not a share of it.
	s.damage = 38
	# Half-length of the crest, i.e. its declared extent to either side. The
	# spectacle floors the spike count so the DRAWN and DAMAGING extent is always
	# <= this: "the spells shouldn't be able to get out the radius" made literal.
	s.radius = 210.0
	s.count = 0                    # unused: spike count comes from radius/spacing
	s.reach = 300.0                # how far from the caster the mark can be placed
	s.cast_time = 1.1              # levitating windup, unchanged
	return s


## ICE WALL — Cryomancer. A temporary blocking barrier of ice that CHILLS on touch.
## Bespoke zoning identity (replaces the Frostpiercer beam-clone).
## AEGIS WARD — the first PROTECTIVE spell. A standing gate of holy light planted
## in the aim direction that EATS magic aimed through it and visibly wears out
## doing it: three rune plates, one per spell it stops.
##
## ⚠ THE ELEMENT IS LOAD-BEARING, NOT FLAVOUR. ReactionTable identifies this ward
## by HOLY — the one element no other barrier carries, which is what let four ward
## rows be added to a live reaction matrix without touching the rock or ice walls.
## A ward authored on any other element is a ward with NO reaction rows at all: it
## would stand there and stop nothing, silently.
##
## COSTED AS AN ULT ON PURPOSE. SpellTier derives ULT from the 11 s cooldown, so
## this occupies the ult slot and competes with the class's finisher — protection
## OR the big damage, never both. That is the best balance lever available (see
## docs/superpowers/specs/2026-07-27-protection-spells.md §6) and it keeps uptime
## at 4.0 s / 11.0 s = 36%, under the 45% ceiling protective spells are held to.
static func _aegis_ward() -> SpellDef:
	var s := SpellDef.new()
	s.id = "aegis_ward"
	s.display_name = "Aegis Ward"
	s.description = "Plant a standing gate of light. It EATS spells aimed through "\
		+ "it three times — you can count what is left on its face — then breaks. "\
		+ "Anything heavier than it gets through; shadow pops it outright."
	s.kind = SpellDef.Kind.WARD
	s.element = Elements.Element.HOLY
	s.use_element_color = true
	s.effect = "holy"
	s.mp_cost = 42
	s.cooldown = 11.0
	s.damage = 0
	s.reach = 108.0
	return s


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


## ARCANE MISSILES — a staggered fan of rune-orbs. The description used to say the
## orbs HOME onto your foes; the homing was removed under the no-auto-aim rule and
## RuneOrbs.gd is now explicit that the ribboning "never changes where the orb ends
## up" — the spread is the caster's aim and the stagger between launches is the
## target's dodge window. Saying "home" made the spell read as a spell that hits
## for you, which is the one promise this kit must not make.
static func _rune_orbs() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rune_orbs"
	s.display_name = "Arcane Missiles"
	s.description = "Loose a fan of spinning rune-orbs down the aim — they ribbon "\
		+ "apart as they fly and pop in precise arcane bursts."
	s.kind = SpellDef.Kind.MISSILES
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = "arcane"
	s.mp_cost = 50
	s.cooldown = 3.4
	s.damage = 24  # per orb
	s.count = 6
	return s


## SHADOW STEP — the reposition-and-punctuate blink. The description used to
## promise "everything on the crossed line is cut and left WEAKENED", which was
## true of the old version: a 300 px damage corridor along the path travelled.
## BlinkStrike.gd was rewritten (maker: "it should just teleport instantly and then
## do a small explosion where it teleports to") — the corridor, the after-image
## band and the slash are all gone, and the whole damage model is now one radius
## query at the destination inside a telegraphed BLAST_RADIUS of 64 px.
##
## DAMAGE DELIBERATELY LEFT AT 85. It was raised 55 -> 85 by hand ("not strong"),
## and dropping it back would be a second nerf on top of one the maker did not
## ask for: losing the corridor already cut this spell from "everything on a
## 300 px line" to "whatever is inside 64 px of where I landed", which is most of
## its output gone. 85 on a single body is also in band for a HEAVY (Thunderclap
## 62, Rock Pillar 58) and it is the kits' PAYOFF pick precisely because it is the
## biggest non-ult number in the tree. Flagged for the maker: if it over-performs
## in play, 60 is the lever — one number, this line.
static func _blink_strike() -> SpellDef:
	var s := SpellDef.new()
	s.id = "blink_strike"
	s.display_name = "Shadow Step"
	s.description = "Step through shadow to the marked point — the dark you "\
		+ "dragged with you collapses into a burst at your feet."
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


## SHADOW ROOT — Warlock signature. Shadows erupt FROM the caster and race along the
## ground; dodge the converging mark or be ROOTED in place and weakened.
##
## Was "Void Zone", a straight recolour of Blizzard's ground ellipse. Kept on the
## ZONE kind and the `void_zone` id so loadouts and saved cycles keep resolving —
## SpellCaster's ZONE arm forks on effect=="shadow" to the eruption spectacle.
static func _void_zone() -> SpellDef:
	var s := SpellDef.new()
	s.id = "void_zone"
	s.display_name = "Shadow Root"
	s.description = "Shadows erupt from your feet and race along the ground — dodge "\
		+ "the converging mark or be ROOTED in place, weakened, while the dark grips."
	s.kind = SpellDef.Kind.ZONE
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 55
	s.cooldown = 6.5
	s.damage = 26   # one-shot damage on the catch (no longer a per-tick field)
	s.radius = 64.0  # grasp half-width at the lock point
	s.reach = 300.0
	return s


## DRAIN TETHER — the Warlock's damage line and the Cleric's sustain. The
## description used to say it snaps to "the nearest foe", which is auto-aim, and
## DrainTether.gd was rewritten precisely because that version was undodgeable
## (maker: "is this dodgeable? I don't like it"). It is now a coiled windup and a
## real travelling hook lashed down the aim that "never bends to find a target".
static func _drain_tether() -> SpellDef:
	var s := SpellDef.new()
	s.id = "drain_tether"
	s.display_name = "Drain Tether"
	s.description = "Coil the dark at your hand, then LASH a writhing hook down the "\
		+ "aim — whatever it catches bleeds its life into you until the cable breaks."
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


## CREEPING SHADE — Shadowblade third signature. A shadow peels off the caster's
## feet and RACES ALONG THE FLOOR, hugging terrain, until it reaches a body — then
## it rears into a spike and launches them. Passes UNDER walls; dies in pits.
##
## `reach` is the travel BUDGET (not a distance to the cursor — the strike point
## is emergent) and `radius` the catch half-width. cast_time stays 0 so it goes
## through the summon path: the levitating channel would lift the caster off the
## floor the spell is supposed to leave from.
static func _creeping_shade() -> SpellDef:
	var s := SpellDef.new()
	s.id = "creeping_shade"
	s.display_name = "Creeping Shade"
	s.description = "Peel your own shadow off the ground and send it racing along "\
		+ "the floor — it follows every slope, slips under walls, and SPIKES the "\
		+ "first thing it reaches into the air. Jump it or wear it."
	s.kind = SpellDef.Kind.CRAWLER
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 52
	s.cooldown = 5.5
	s.damage = 60
	s.reach = 620.0
	s.radius = 26.0
	return s


## RIFT DAGGER — Shadowblade / Arcanist. Throw a dagger that sticks where it lands
## (wall, crate, or a body that walks away with it); press again to TEAR yourself
## through to it. Two beats, one button.
##
## Damage is deliberately low on BOTH halves: this is a positioning tool, and a
## teleport that also killed would make the second beat automatic. `length` is the
## anchor lifetime (the same double-duty ZONE already gives it), and the cooldown
## does not start until the anchor resolves.
static func _rift_dagger() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rift_dagger"
	s.display_name = "Rift Dagger"
	s.description = "Hurl a dagger down the aim — it sticks in whatever it reaches. "\
		+ "Press again and the rift tears you through to it, bursting on arrival."
	s.kind = SpellDef.Kind.THROWN_ANCHOR
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 46
	s.cooldown = 4.5
	s.damage = 34
	s.reach = 700.0
	s.radius = 70.0
	s.length = 4.0
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


## CAST TIME IS THE BEAM FAMILY'S ONE REAL DESIGN AXIS, so it is a parameter and
## not the flat 1.0 every beam used to share. It buys two different things at once
## and they point the same way:
##
##   1. The DODGE WINDOW. cast_time is the levitating channel (Hero._begin_channel)
##      — the seconds the opponent gets to read the sigil and leave. Longer wind-up
##      = more warning = a spell that has to be worth the warning.
##   2. The CLASH WEIGHT. SpellTier.of() derives QUICK/HEAVY/ULT from cast time,
##      cooldown and MP, and that shelf is now also what a spell WEIGHS when two
##      spells meet: equal shelves annihilate, a heavier one overpowers and keeps
##      going, and a barrier stops what it is not outmatched by.
##
## So "commit longer, hit through more" is one number saying one thing twice. When
## every beam shared cast_time = 1.0 they were all ULT, which made beam-vs-beam
## *always* mutual annihilation (overpower unreachable) and beam-vs-wall *always*
## a breach (no wall could ever stop a beam). Spreading the family across two
## shelves is what makes that ladder reachable at all.
##
## The floor is deliberately NOT zero. SpellTier.QUICK requires cast_time <= 0.01,
## i.e. no channel — and an instant screen-crossing lance has no tell, which
## breaks the locked "every ability needs a real telegraph and a dodge window"
## rule. So no beam is QUICK: the family spans HEAVY and ULT only.
static func _beam(
	id: String, name: String, desc: String, element: int,
	mp: int, cd: float, dmg: int, length: float, width: float,
	cast_time: float = 1.0
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
	s.cast_time = cast_time  # levitating windup — see the note above
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
