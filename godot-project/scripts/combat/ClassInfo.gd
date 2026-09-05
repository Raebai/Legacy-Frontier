class_name ClassInfo
extends RefCounted
## Single source of class-card data for the hub Class-Select lobby. Indices MUST
## match Hero.HeroClass / Hero.CLASS_NAMES (0 Arcanist .. 8 Swordsaint). `color` is
## the class's element tint (used for the hub player + the card accent). Kit blurbs
## summarise the distinct PRIMARY + signature so the player can compare at a glance.
##
## ⚠ THE BLURB IS A PROMISE, AND IT WAS BEING BROKEN. These strings drifted out of
## sync with the real kits and the cards advertised spells the class did not have —
## "Ult Frostpiercer", "Ult Tempest", "Ult Void Barrage" were beams that lived only
## in the review harness and were in NOBODY's kit. That is a direct cause of the
## maker's "where are those cool heavy attack beams, why can I only see one or two":
## the card said they were equipped, and they were not.
##
## SO: the ULT NAMED HERE MUST BE THE `ult` ENTRY OF `SpellLibrary.CLASS_KITS[i]`,
## which is now the single source of truth for what a class actually holds. Every
## row below was re-derived from that table, not from this file's history. The Q
## slot is the class's AoE variant (`Hero.CLASS_CONFIG[i]["aoe"]`, labelled by
## `Hero._aoe_slot_name`) and the LMB is its `primary` — those are Hero's, not the
## library's, which is why the blurb reads across two sources.
##
## `tools/slice8_test_spell_kits.gd` sweeps `SpellLibrary.gd` for banned IP strings.
## ⚠ THESE KIT STRINGS ARE HAND-WRITTEN AND DO NOT FOLLOW `SpellLibrary`.
## Renaming a spell's `display_name` does NOT reach them, so a rename silently
## turns a class card into a lie. It happened on 2026-08-04 (The Ordinary Spell ->
## First Lance, Crescent Step -> Crescent Rush) and was caught by hand, not by a
## test. If you rename a spell, grep here.
##
## The renames that removed the last player-facing borrowed names — "The Ordinary
## Spell" and "Thunderclap" — are shipped; do not reintroduce the old ones here
## either, since these strings are read by a player on the class-select screen.

##
## ⚠ RE-DERIVED AGAIN FOR THE ANTI-RECOLOUR PASS. Every blurb below now names the
## spells that class ACTUALLY CARRIES (`SpellLibrary.CLASS_KITS` read through
## `SLOT_ROLES`), because five of the nine used to advertise a beam — Umbral Lance,
## Infernal Lance, Tempest — that has since left every kit entirely. Advertising a
## spell nobody holds is the precise failure this header was written about, and it
## had grown back.
const CLASSES: Array[Dictionary] = [
	# 0 ARCANIST — carries the Ordinary Spell, MIRROR IMAGE (promoted out of the drop
	# pool — the only self-duplication in the game) and the Meteor Sigil.
	{"name": "Arcanist", "fantasy": "Ranged arcane zoner",
		"kit": "First Lance · Mirror Image · Arcane Missiles · Ult Meteor Sigil", "color": Color(1.0, 0.78, 0.28)},
	# 1 SHADOWBLADE — the Umbral Lance was a violet copy of the Arcanist's beam; the
	# ult is THOUSAND CUTS now, and the carried middle is the Rift Dagger.
	{"name": "Shadowblade", "fantasy": "In-and-out assassin",
		"kit": "Blade Flurry · Rift Dagger · Creeping Shade · Ult Thousand Cuts", "color": Color(0.16, 0.11, 0.22)},
	# 2 BRAWLER — the card said "no magic" while the class threw a lightning lance
	# and a fire beam. Both are gone: a stomp and a fist that lands like a meteor.
	{"name": "Brawler", "fantasy": "Pure-melee knockout — no magic",
		"kit": "Shockwave Stomp · Rock Wall · Petrify · Ult Meteor Fist", "color": Color(0.68, 0.09, 0.09)},
	{"name": "Juggernaut", "fantasy": "Unbreakable siege tank",
		"kit": "Boulder Hurl · Rock Pillar · Gravity Flip · Ult Fault Line", "color": Color(0.78, 0.55, 0.28)},
	# 4 CLERIC — RADIANT VOLLEY is the archer signature, and the AEGIS WARD (the
	# game's only protective spell) is finally in somebody's hand.
	{"name": "Cleric", "fantasy": "Radiant lifesteal bruiser",
		"kit": "Radiant Volley · Aegis Ward · Judgment · Divine Ray · Ult Heaven's Verdict", "color": Color(1.0, 0.93, 0.6)},
	# 5 CRYOMANCER — SHATTER replaces the Frostpiercer beam, and the class's own
	# Blizzard is its set-up (3x damage on a frozen body).
	{"name": "Cryomancer", "fantasy": "Ice control caster",
		"kit": "Shatter · Blizzard · Ice Wall · Ult Glacial Spine", "color": Color(0.5, 0.85, 1.0)},
	# 6 STORMCALLER — inherits the Thunderclap off the Brawler, where a lightning
	# lance contradicted that class's whole card. Its ult is a storm CELL, not a beam.
	{"name": "Stormcaller", "fantasy": "Hyper-mobile chain caster",
		"kit": "Chain Lightning · Thunderclap · Shadowburst · Ult Heaven's Wrath", "color": Color(0.8, 1.0, 0.18)},
	# 7 WARLOCK — RAISE THRALL is the only summon in the game.
	{"name": "Warlock", "fantasy": "Dark attrition hexer",
		"kit": "Drain Tether · Raise Thrall · Shadow Root · Ult Grave Tide", "color": Color(0.6, 0.35, 0.9)},
	# 8 SWORDSAINT — the duelist. The only class whose DEFENCE produces its OFFENCE:
	# RMB is a held BLADE GUARD (ParryRing's shrinking ring) that banks what it turns
	# away and pays it back as one unsheathe cut. No blink; R is a rising cut.
	# Steel-white rather than an element tint, because the class deliberately applies
	# no ailment — the blade is just a blade.
	# Its damage line was `blade_flurry` — the SHADOWBLADE's spell worn by a second
	# class. IAI SLASH and CRESCENT STEP are the duelist's own, and Horizon Cut
	# (HorizonArc.gd) finally holds the ult slot it was authored for.
	{"name": "Swordsaint", "fantasy": "Guard-and-punish duelist",
		"kit": "Iai Slash · Crescent Rush · Blood Pact · Ult Horizon Cut", "color": Color(0.86, 0.9, 0.96)},
]


static func count() -> int:
	return CLASSES.size()


static func color_for(i: int) -> Color:
	return CLASSES[i]["color"] if i >= 0 and i < CLASSES.size() else Color.WHITE


static func name_for(i: int) -> String:
	return String(CLASSES[i]["name"]) if i >= 0 and i < CLASSES.size() else "Class"


static func fantasy_for(i: int) -> String:
	return String(CLASSES[i]["fantasy"]) if i >= 0 and i < CLASSES.size() else ""


## THE CARD, DERIVED. `carried_spells(i)` asks `SpellLibrary` what this class is
## ACTUALLY holding right now and hands back the built defs, in hotbar order.
##
## ⚠ THIS IS THE ANSWER TO THIS FILE'S OWN HEADER. Everything above is hand-written
## and has drifted twice: once advertising three beams that were in nobody's kit, and
## again -- measured on 2026-09-04, and fixed in the same edit as this function -- with
## ALL NINE `kit` strings naming only THREE spells while the hand has held FOUR since
## `SpellTier.SLOT_COUNT` became 4. Nothing caught either drift, because a string cannot
## be wrong, only stale.
##
## So the class-select screen reads THIS, not `CLASSES[i]["kit"]`. The literal stays
## because `Lobby.gd` and `tools/director/Director.gd` still read the dictionary key and
## neither is ours to change -- but it is no longer the thing a player is shown, and
## `tools/slice_test_class_identity.gd` now pins it against this function BOTH ways: a
## carried spell missing from the string fails, and a spell NAMED in the string that the
## class does not carry fails. A rename is a red test now rather than a lie on a card.
##
## Returns `[]` when the library cannot answer (a bad index, or a headless harness with
## no library), because a card with no spells on it is honest and a card with invented
## spells on it is the bug this whole comment is about.
static func carried_spells(i: int) -> Array:
	if i < 0 or i >= CLASSES.size():
		return []
	var out: Array = []
	for spell: Variant in SpellLibrary.build_for_class(i):
		if spell != null:
			out.append(spell)
	return out


## The derived one-line kit summary, in the same "A · B · C · Ult D" shape the
## authored `kit` literal uses -- so a caller can swap to it without re-laying anything
## out, and so the suite can compare the two directly.
static func kit_for(i: int) -> String:
	var spells: Array = carried_spells(i)
	if spells.is_empty():
		return String(CLASSES[i]["kit"]) if i >= 0 and i < CLASSES.size() else ""
	var parts: Array[String] = []
	for n: int in spells.size():
		var nm: String = String((spells[n] as SpellDef).display_name)
		# The LAST slot is the ult slot -- `SpellLibrary.SLOT_ROLES` guarantees it, and
		# `slice8_test_spell_kits` pins it -- so the badge is positional rather than a
		# second tier lookup that could disagree with the table it came from.
		parts.append(("Ult " + nm) if n == spells.size() - 1 else nm)
	return " · ".join(parts)
