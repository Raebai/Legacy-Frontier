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
## The renames that removed the last player-facing borrowed names — "The Ordinary
## Spell" and "Thunderclap" — are shipped; do not reintroduce the old ones here
## either, since these strings are read by a player on the class-select screen.

const CLASSES: Array[Dictionary] = [
	# 0 ARCANIST — ult Meteor Sigil (was advertising a borrowed beam name it did not
	# even equip; that was the last player-facing IP borrow outside SpellLibrary).
	{"name": "Arcanist", "fantasy": "Ranged arcane zoner",
		"kit": "LMB arcane bolt · Q ArcaneStorm · Ult Meteor Sigil", "color": Color(0.95, 0.4, 0.85)},
	{"name": "Shadowblade", "fantasy": "In-and-out assassin",
		"kit": "LMB dagger flurry · dash-strike · Ult Umbral Lance", "color": Color(0.6, 0.35, 0.9)},
	# 2 BRAWLER — the Thunderclap is a HEAVY now and cannot sit in an ult slot, so
	# the class's actual finisher is the Infernal Lance.
	{"name": "Brawler", "fantasy": "Pure-melee knockout — no magic",
		"kit": "LMB punch/kick combo · double-jump · uppercut · Ult Infernal Lance", "color": Color(1.0, 0.45, 0.15)},
	{"name": "Juggernaut", "fantasy": "Unbreakable siege tank",
		"kit": "LMB heavy hammer · BLOCK · Q Slam · Ult Colossus Pillar", "color": Color(0.78, 0.55, 0.28)},
	{"name": "Cleric", "fantasy": "Radiant lifesteal bruiser",
		"kit": "LMB heal-bolt · Q Consecrate · Ult Heaven's Verdict", "color": Color(1.0, 0.93, 0.6)},
	# 5 CRYOMANCER — Frostpiercer became the DAMAGE line (a short-channel heavy you
	# throw all fight), so the ult is the Glacial Spine.
	{"name": "Cryomancer", "fantasy": "Ice control caster",
		"kit": "LMB frost CONE · Q IceShards · Ult Glacial Spine", "color": Color(0.5, 0.85, 1.0)},
	{"name": "Stormcaller", "fantasy": "Hyper-mobile chain caster",
		"kit": "LMB chain bolt · fast wind-dash · Ult Tempest", "color": Color(1.0, 0.9, 0.3)},
	{"name": "Warlock", "fantasy": "Dark attrition hexer",
		"kit": "LMB drain-bolt · Q CurseChain · Ult Void Barrage", "color": Color(0.6, 0.35, 0.9)},
	# 8 SWORDSAINT — the duelist. The only class whose DEFENCE produces its OFFENCE:
	# RMB is a held BLADE GUARD (ParryRing's shrinking ring) that banks what it turns
	# away and pays it back as one unsheathe cut. No blink; R is a rising cut.
	# Steel-white rather than an element tint, because the class deliberately applies
	# no ailment — the blade is just a blade.
	# The ult named here is the one it ACTUALLY equips. Horizon Cut is the class's
	# authored signature and is built (HorizonArc.gd), but it needs a SpellDef.Kind
	# and a SpellCaster arm before it can hold the slot — so the card must not promise
	# it yet. That promise-vs-reality gap is the exact bug this file's header is about.
	{"name": "Swordsaint", "fantasy": "Guard-and-punish duelist",
		"kit": "LMB greatsword · RMB held GUARD (bank → cut) · Ult Horizon Cut", "color": Color(0.86, 0.9, 0.96)},
]


static func count() -> int:
	return CLASSES.size()


static func color_for(i: int) -> Color:
	return CLASSES[i]["color"] if i >= 0 and i < CLASSES.size() else Color.WHITE


static func name_for(i: int) -> String:
	return String(CLASSES[i]["name"]) if i >= 0 and i < CLASSES.size() else "Class"
