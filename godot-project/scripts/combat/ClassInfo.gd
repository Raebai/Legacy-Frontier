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
		"kit": "LMB arcane bolt · First Lance · Mirror Image · Ult Meteor Sigil", "color": Color(1.0, 0.78, 0.28)},
	# 1 SHADOWBLADE — the Umbral Lance was a violet copy of the Arcanist's beam; the
	# ult is THOUSAND CUTS now, and the carried middle is the Rift Dagger.
	{"name": "Shadowblade", "fantasy": "In-and-out assassin",
		"kit": "LMB dagger flurry · Blade Flurry · Rift Dagger · Ult Thousand Cuts", "color": Color(0.16, 0.11, 0.22)},
	# 2 BRAWLER — the card said "no magic" while the class threw a lightning lance
	# and a fire beam. Both are gone: a stomp and a fist that lands like a meteor.
	{"name": "Brawler", "fantasy": "Pure-melee knockout — no magic",
		"kit": "LMB punch/kick combo · Shockwave Stomp · Rock Wall · Ult Meteor Fist", "color": Color(0.68, 0.09, 0.09)},
	{"name": "Juggernaut", "fantasy": "Unbreakable siege tank",
		"kit": "LMB heavy hammer · BLOCK · Boulder Hurl · Rock Pillar · Ult Fault Line", "color": Color(0.78, 0.55, 0.28)},
	# 4 CLERIC — RADIANT VOLLEY is the archer signature, and the AEGIS WARD (the
	# game's only protective spell) is finally in somebody's hand.
	{"name": "Cleric", "fantasy": "Radiant lifesteal bruiser",
		"kit": "LMB heal-bolt · Radiant Volley · Aegis Ward · Ult Heaven's Verdict", "color": Color(1.0, 0.93, 0.6)},
	# 5 CRYOMANCER — SHATTER replaces the Frostpiercer beam, and the class's own
	# Blizzard is its set-up (3x damage on a frozen body).
	{"name": "Cryomancer", "fantasy": "Ice control caster",
		"kit": "LMB frost CONE · Shatter · Blizzard · Ult Glacial Spine", "color": Color(0.5, 0.85, 1.0)},
	# 6 STORMCALLER — inherits the Thunderclap off the Brawler, where a lightning
	# lance contradicted that class's whole card. Its ult is a storm CELL, not a beam.
	{"name": "Stormcaller", "fantasy": "Hyper-mobile chain caster",
		"kit": "LMB chain bolt · Chain Lightning · Thunderclap · Ult Heaven's Wrath", "color": Color(0.8, 1.0, 0.18)},
	# 7 WARLOCK — RAISE THRALL is the only summon in the game.
	{"name": "Warlock", "fantasy": "Dark attrition hexer",
		"kit": "LMB drain-bolt · Drain Tether · Raise Thrall · Ult Grave Tide", "color": Color(0.6, 0.35, 0.9)},
	# 8 SWORDSAINT — the duelist. The only class whose DEFENCE produces its OFFENCE:
	# RMB is a held BLADE GUARD (ParryRing's shrinking ring) that banks what it turns
	# away and pays it back as one unsheathe cut. No blink; R is a rising cut.
	# Steel-white rather than an element tint, because the class deliberately applies
	# no ailment — the blade is just a blade.
	# Its damage line was `blade_flurry` — the SHADOWBLADE's spell worn by a second
	# class. IAI SLASH and CRESCENT STEP are the duelist's own, and Horizon Cut
	# (HorizonArc.gd) finally holds the ult slot it was authored for.
	{"name": "Swordsaint", "fantasy": "Guard-and-punish duelist",
		"kit": "LMB greatsword · RMB held GUARD (bank → cut) · Iai Slash · Crescent Rush · Ult Horizon Cut", "color": Color(0.86, 0.9, 0.96)},
]


static func count() -> int:
	return CLASSES.size()


static func color_for(i: int) -> Color:
	return CLASSES[i]["color"] if i >= 0 and i < CLASSES.size() else Color.WHITE


static func name_for(i: int) -> String:
	return String(CLASSES[i]["name"]) if i >= 0 and i < CLASSES.size() else "Class"
