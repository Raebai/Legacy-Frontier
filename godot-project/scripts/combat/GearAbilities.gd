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

## kind -> {name, desc, element}. element is a hint string ("" = none) for the
## eventual effect, deliberately NOT the Elements enum so this file has zero deps.
const ABILITIES: Dictionary = {
	# --- caster staves (hero) ---
	"staff":       {"name": "Arcane Focus", "desc": "Basic casts pierce the first target and gain range.", "element": "arcane"},
	"staff_ice":   {"name": "Frostbite",    "desc": "Hits apply Chill, slowing what they touch.",          "element": "ice"},
	"staff_storm": {"name": "Chain Surge",  "desc": "Hits arc to one nearby enemy.",                       "element": "lightning"},
	"staff_holy":  {"name": "Sanctify",     "desc": "Casts heal you for a sliver of the damage dealt.",    "element": "holy"},
	# --- martial weapons (hero) ---
	"sword":       {"name": "Riposte",      "desc": "A perfect parry counters for bonus damage.",          "element": ""},
	"dagger":      {"name": "Backstab",     "desc": "Strikes from behind land as crits.",                  "element": ""},
	"hammer":      {"name": "Quake",        "desc": "Heavy hits send a shockwave along the ground.",       "element": "earth"},
	"scythe":      {"name": "Reap",         "desc": "Kills heal you and refund a little cooldown.",        "element": "shadow"},
	"orb":         {"name": "Conjure",      "desc": "Passively orbits a homing wisp that strikes foes.",   "element": "arcane"},
	# --- enemy / boss pieces (identity; effects shared with the roster AI) ---
	"club":        {"name": "Bludgeon",     "desc": "Melee lands with extra knockback.",                   "element": ""},
	"spear":       {"name": "Lunge",        "desc": "Longer reach; opens with a dash-thrust.",             "element": ""},
	"bomb":        {"name": "Volatile",     "desc": "Detonates in a fiery AoE on death.",                  "element": "fire"},
	"crown":       {"name": "Sovereign",    "desc": "Commands nearby allies; bolsters their resolve.",     "element": ""},
	"robe":        {"name": "Warded",       "desc": "A cloth ward softens the first hit each fight.",      "element": ""},
	"hat":         {"name": "Insight",      "desc": "Faster ability cooldowns.",                           "element": ""},
	"hood":        {"name": "Shadowstep",   "desc": "Dash leaves no trace and briefly cloaks you.",        "element": ""},
}


## The ability record for a gear kind, or {} if the piece has none.
static func of(kind: String) -> Dictionary:
	return ABILITIES.get(kind, {})


static func has_ability(kind: String) -> bool:
	return ABILITIES.has(kind)


## Short "Name — description" line for a piece (for the loadout UI / tooltips). "" if none.
static func label(kind: String) -> String:
	var a: Dictionary = ABILITIES.get(kind, {})
	if a.is_empty():
		return ""
	return "%s — %s" % [a.get("name", kind), a.get("desc", "")]
