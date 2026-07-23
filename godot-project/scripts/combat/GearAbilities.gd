class_name GearAbilities
extends RefCounted
## Registry: every pixel gear piece carries a UNIQUE ability + identity (maker:
## "unique abilities on each gear piece"). This is the DATA FOUNDATION — name,
## description, and an element hint per piece — queryable by the loadout UI and by
## the Hero once the effects are activated.
##
## SCOPE NOTE (honest): the pieces already apply COSMETICALLY (CharacterRig.EQUIP_TEX
## overlays). Turning these into live GAMEPLAY modifiers (gear that grants/reshapes
## your kit) is a loadout + BALANCE design pass that needs playtest — see
## docs/superpowers/specs for the design. This registry is the seam that pass plugs
## into: swap the piece -> look up its ability here -> apply the effect. Kept as pure
## data (no combat wiring) so it can't destabilise the balanced classes before it's
## designed + felt.

## kind -> {name, desc, element, effect}. `effect` is a machine-readable modifier
## bag the Hero aggregates (Hero._aggregate_gear); ACTIVE effects are the ones with
## a single clean combat hook. `element` (string) is deliberately NOT the Elements
## enum so this file stays dependency-free — the Hero maps it. Descriptions match
## the WIRED behaviour (no promises the code doesn't keep).
##
## effect keys: element (str) | melee_damage/melee_knockback/melee_cd/max_hp/speed
## (float mults) | ward (float 0..1, first-hit reduction). {} = no hero effect
## (enemy/boss pieces — their "ability" is the roster AI behaviour they already drive).
const ABILITIES: Dictionary = {
	# --- caster weapons: your weapon defines your ELEMENT (the flagship gear ability) ---
	"staff":       {"name": "Arcane Focus", "desc": "Your spells strike as Arcane.",              "element": "arcane",    "effect": {"element": "arcane"}},
	"staff_ice":   {"name": "Frostbite",    "desc": "Your spells strike as Ice — foes are Chilled.", "element": "ice",    "effect": {"element": "ice"}},
	"staff_storm": {"name": "Chain Surge",  "desc": "Your spells strike as Lightning.",           "element": "lightning", "effect": {"element": "lightning"}},
	"staff_holy":  {"name": "Sanctify",     "desc": "Your spells strike as Holy.",                "element": "holy",      "effect": {"element": "holy"}},
	"scythe":      {"name": "Reap",         "desc": "Your spells strike as Shadow.",              "element": "shadow",    "effect": {"element": "shadow"}},
	"orb":         {"name": "Conjure",      "desc": "Your spells strike as Arcane.",              "element": "arcane",    "effect": {"element": "arcane"}},
	# --- martial weapons: melee profile ---
	"sword":       {"name": "Keen Edge",    "desc": "Sharper strikes (+15% melee damage).",       "element": "",          "effect": {"melee_damage": 1.15}},
	"dagger":      {"name": "Flurry",       "desc": "Faster, nimbler strikes.",                   "element": "",          "effect": {"melee_cd": 0.7, "speed": 1.06}},
	"hammer":      {"name": "Quake",        "desc": "Crushing blows: +20% damage, big knockback.", "element": "",         "effect": {"melee_damage": 1.2, "melee_knockback": 1.4}},
	"greatsword":  {"name": "Cleave",       "desc": "Massive strikes (+30% damage) but slower.",  "element": "",          "effect": {"melee_damage": 1.3, "melee_cd": 1.3}},
	# --- head ---
	"hat":         {"name": "Fortified",    "desc": "Hardier: +12% max HP.",                      "element": "",          "effect": {"max_hp": 1.12}},
	"hood":        {"name": "Fleet",        "desc": "Fleet-footed: +12% move speed.",             "element": "",          "effect": {"speed": 1.12}},
	"helmet":      {"name": "Ironclad",     "desc": "Heavy plate: +20% max HP.",                  "element": "",          "effect": {"max_hp": 1.2}},
	# --- body ---
	"robe":        {"name": "Warded",       "desc": "Wards the first hit each fight (-40%).",      "element": "",          "effect": {"ward": 0.4}},
	"cape":        {"name": "Windswept",    "desc": "A billowing cape: +12% move speed.",         "element": "",          "effect": {"speed": 1.12}},
	"armor":       {"name": "Plated",       "desc": "Plate armour: -15% damage from every hit.",  "element": "",          "effect": {"damage_reduction": 0.15}},
	# --- enemy / boss pieces (identity only; the roster AI already drives these) ---
	"club":        {"name": "Bludgeon",     "desc": "Heavy melee with extra knockback.",          "element": "",          "effect": {}},
	"spear":       {"name": "Lunge",        "desc": "Long reach; a dash-thrust charge.",          "element": "",          "effect": {}},
	"bomb":        {"name": "Volatile",     "desc": "Detonates in a fiery AoE.",                  "element": "fire",      "effect": {}},
	"crown":       {"name": "Sovereign",    "desc": "A guardian-king's regalia.",                 "element": "",          "effect": {}},
}


## The ability record for a gear kind, or {} if the piece has none.
static func of(kind: String) -> Dictionary:
	return ABILITIES.get(kind, {})


## The machine-readable effect bag for a gear kind (Hero aggregates these), or {}.
static func effect(kind: String) -> Dictionary:
	return (ABILITIES.get(kind, {}) as Dictionary).get("effect", {})


static func has_ability(kind: String) -> bool:
	return ABILITIES.has(kind)


## Short "Name — description" line for a piece (for the loadout UI / tooltips). "" if none.
static func label(kind: String) -> String:
	var a: Dictionary = ABILITIES.get(kind, {})
	if a.is_empty():
		return ""
	return "%s — %s" % [a.get("name", kind), a.get("desc", "")]
