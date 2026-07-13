class_name ClassInfo
extends RefCounted
## Single source of class-card data for the hub Class-Select lobby. Indices MUST
## match Hero.HeroClass / Hero.CLASS_NAMES (0 Arcanist .. 7 Warlock). `color` is
## the class's element tint (used for the hub player + the card accent). Kit blurbs
## summarise the distinct PRIMARY + signature so the player can compare at a glance.

const CLASSES: Array[Dictionary] = [
	{"name": "Arcanist", "fantasy": "Ranged arcane zoner",
		"kit": "LMB arcane bolt · Q Meteor · Ult Zoltraak", "color": Color(0.95, 0.4, 0.85)},
	{"name": "Shadowblade", "fantasy": "In-and-out assassin",
		"kit": "LMB dagger flurry · dash-strike · Ult Umbral Lance", "color": Color(0.6, 0.35, 0.9)},
	{"name": "Brawler", "fantasy": "Pure-melee knockout — no magic",
		"kit": "LMB punch/kick combo · double-jump · uppercut · Ult CHIDORI", "color": Color(1.0, 0.45, 0.15)},
	{"name": "Juggernaut", "fantasy": "Unbreakable siege tank",
		"kit": "LMB heavy hammer · BLOCK · Q Ground Slam · Ult Colossus", "color": Color(0.78, 0.55, 0.28)},
	{"name": "Cleric", "fantasy": "Radiant lifesteal bruiser",
		"kit": "LMB heal-bolt · Q Consecration · Ult Heaven's Verdict", "color": Color(1.0, 0.93, 0.6)},
	{"name": "Cryomancer", "fantasy": "Ice control caster",
		"kit": "LMB frost CONE · Q Blizzard · Ult Frostpiercer", "color": Color(0.5, 0.85, 1.0)},
	{"name": "Stormcaller", "fantasy": "Hyper-mobile chain caster",
		"kit": "LMB chain bolt · fast wind-dash · Ult Tempest", "color": Color(1.0, 0.9, 0.3)},
	{"name": "Warlock", "fantasy": "Dark attrition hexer",
		"kit": "LMB drain-bolt · Q Void Rupture · Ult Void Barrage", "color": Color(0.6, 0.35, 0.9)},
]


static func count() -> int:
	return CLASSES.size()


static func color_for(i: int) -> Color:
	return CLASSES[i]["color"] if i >= 0 and i < CLASSES.size() else Color.WHITE


static func name_for(i: int) -> String:
	return String(CLASSES[i]["name"]) if i >= 0 and i < CLASSES.size() else "Class"
