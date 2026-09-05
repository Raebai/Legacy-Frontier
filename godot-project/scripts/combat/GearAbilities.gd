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
## ⚠ NO ITEM MAY STRICTLY DOMINATE ANOTHER IN THE SAME SLOT. Two did, and a
## strictly-dominated item is not "weak" — it is UNPICKABLE. There was no hero, no
## class and no situation in which it was the right answer, so it was dead content
## wearing an icon:
##   * `hat` (+12% hp) vs `helmet` (+20% hp) — better on one axis, tied on every
##     other. `helmet` now pays -6% speed, so hat is the light option and helmet is
##     the heavy one.
##   * `sword` (+15% dmg) vs `hammer` (+20% dmg, +40% knockback) — the hammer was
##     better on two axes and worse on none. It now pays +15% swing cooldown, which
##     is the same currency `greatsword` already pays in.
## `slice_test_gear.gd` asserts the no-dominance rule directly, per slot.
##
## STILL OPEN, AND A DESIGN CALL RATHER THAN A DEFECT: 17 of 19 pieces still
## strictly dominate the EMPTY slot. Only `greatsword` and now `helmet`/`hammer`
## pay for anything, so "equip something" remains a checklist even though "equip
## WHICH" is now a real choice. Closing that means giving most of the roster a real
## cost, which changes how every class plays and wants the maker's hands on it.
const ABILITIES: Dictionary = {
	# --- caster weapons: your weapon defines your ELEMENT (the flagship gear ability) ---
	"staff":       {"name": "Arcane Focus", "desc": "Your spells strike as Arcane.",              "element": "arcane",    "effect": {"element": "arcane"}},
	"staff_ice":   {"name": "Frostbite",    "desc": "Your spells strike as Ice — foes are Chilled.", "element": "ice",    "effect": {"element": "ice"}},
	"staff_storm": {"name": "Chain Surge",  "desc": "Your spells strike as Lightning.",           "element": "lightning", "effect": {"element": "lightning"}},
	"staff_holy":  {"name": "Sanctify",     "desc": "Your spells strike as Holy.",                "element": "holy",      "effect": {"element": "holy"}},
	"scythe":      {"name": "Reap",         "desc": "Your spells strike as Shadow.",              "element": "shadow",    "effect": {"element": "shadow"}},
	"orb":         {"name": "Conjure",      "desc": "Your spells strike as Arcane.",              "element": "arcane",    "effect": {"element": "arcane"}},
	# --- martial weapons: melee profile ---
	"sword":       {"name": "Keen Edge",    "desc": "Sharper strikes: +15% damage, but it cuts instead of shoving (-12% knockback).", "element": "", "effect": {"melee_damage": 1.15, "melee_knockback": 0.88}},
	"dagger":      {"name": "Flurry",       "desc": "Fast and nimble: much quicker strikes, but each one lands light (-18% damage).", "element": "", "effect": {"melee_cd": 0.7, "speed": 1.06, "melee_damage": 0.82}},
	# The SHADOWBLADE'S own knife. Cosmetic-only today — the class keeps `weapon:
	# "sword"` as its stats row and names this in `weapon_look`, so nothing reads the
	# effect below. It is here because `GEAR_KINDS` is the registry of legal kinds and
	# a kind with no ability row is one of the silent-default holes `SpellDef`'s header
	# warns about: if this ever becomes equippable, it behaves like the dagger it is
	# instead of falling through to nothing. Same numbers as `dagger`, deliberately.
	"dagger_shadow": {"name": "Flurry",     "desc": "Fast and nimble: much quicker strikes, but each one lands light (-18% damage).", "element": "", "effect": {"melee_cd": 0.7, "speed": 1.06, "melee_damage": 0.82}},
	"hammer":      {"name": "Quake",        "desc": "Crushing blows: +20% damage and big knockback, but slower.", "element": "", "effect": {"melee_damage": 1.2, "melee_knockback": 1.4, "melee_cd": 1.15}},
	"greatsword":  {"name": "Cleave",       "desc": "Massive strikes (+30% damage) but slower.",  "element": "",          "effect": {"melee_damage": 1.3, "melee_cd": 1.3}},
	# --- head ---
	"hat":         {"name": "Fortified",    "desc": "Padded: +12% max HP, and a little slower for it (-4% speed).", "element": "", "effect": {"max_hp": 1.12, "speed": 0.96}},
	"hood":        {"name": "Fleet",        "desc": "Fleet-footed: +12% move speed, with nothing between you and a hit (-6% max HP).", "element": "", "effect": {"speed": 1.12, "max_hp": 0.94}},
	"helmet":      {"name": "Ironclad",     "desc": "Heavy plate: +20% max HP, but it weighs on you (-6% speed).", "element": "", "effect": {"max_hp": 1.2, "speed": 0.94}},
	# --- body ---
	"robe":        {"name": "Warded",       "desc": "Wards the first hit each fight (-40%), but it is cloth (-6% max HP).", "element": "", "effect": {"ward": 0.4, "max_hp": 0.94}},
	"cape":        {"name": "Windswept",    "desc": "A billowing cape: +12% move speed, and it catches on your swing (-10% melee rate).", "element": "", "effect": {"speed": 1.12, "melee_cd": 1.10}},
	"armor":       {"name": "Plated",       "desc": "Plate armour: -15% damage from every hit, at the cost of your feet (-8% speed).", "element": "", "effect": {"damage_reduction": 0.15, "speed": 0.92}},
	# --- enemy / boss pieces (identity only; the roster AI already drives these) ---
	"club":        {"name": "Bludgeon",     "desc": "Heavy melee with extra knockback.",          "element": "",          "effect": {}},
	"spear":       {"name": "Lunge",        "desc": "Long reach; a dash-thrust charge.",          "element": "",          "effect": {}},
	"bomb":        {"name": "Volatile",     "desc": "Detonates in a fiery AoE.",                  "element": "fire",      "effect": {}},
	"crown":       {"name": "Sovereign",    "desc": "A guardian-king's regalia.",                 "element": "",          "effect": {}},
	# ─────────────────────────────────────────────────────────────────────────────
	# THE ARMOURY MENU — PLACEHOLDERS. Maker, verbatim: "Armoury — remove all of the
	# options right now. That is where we can have players equip custom cool armour
	# pieces and cool spellements to add attributes to their current tools, but right
	# now I don't think we have any of those if I'm not mistaken, so add placeholder
	# cool names of stuff that we can then introduce later."
	#
	# ⚠ WHAT WAS REMOVED WAS THE MENU, NOT THE MACHINERY, AND NOT THE ROWS ABOVE.
	# `Loadout.OPTIONS` no longer offers `hat`/`helmet`/`hammer`/`staff_ice`/... — but
	# those rows STAY here, because three things that are not the armoury read them and
	# two of them are other people's files:
	#   * `CharacterRig.GEAR_KINDS` is the list of pieces the rig can DRAW, and
	#     `tools/slice_test_rig_gait.gd` asserts every drawable kind carries an ability
	#     + a non-empty label. Deleting the rows red-lights a suite this change has no
	#     business touching.
	#   * `Enemy.ARCHETYPE_GEAR` names `club`/`spear`/`bomb`/`crown` — enemy identity.
	#   * `tools/slice_test_class_movement.gd` equips `hat` on a real Hero and reads the
	#     effect back. Stripping the bag would break a test that is about MOVEMENT.
	# Un-offered is enough: `Hero._aggregate_gear` only ever reads `_gear_override`, and
	# the only things that write it are the player's armoury choice and `set_loadout`.
	# A piece nobody can pick applies nothing to anybody.
	#
	# ⚠ EVERY PLACEHOLDER'S `effect` IS `{}`, AND THAT IS THE POINT. A placeholder that
	# quietly applied +15% damage would be WORSE than no placeholder: it would look like
	# content, behave like balance, and get tuned around before anyone noticed it was a
	# stub. `slice_test_gear.gd` now asserts the empty bag directly, per placeholder, so
	# the day someone "just adds a small bonus" the suite says no.
	#
	# The `desc` opens with a literal COMING SOON tag rather than only carrying the
	# `placeholder` flag, because the flag is invisible to the person holding the phone.
	# The reader of the description IS the player, and they must not be able to mistake
	# a promise for a stat. Descriptions are written in the FUTURE tense for the same
	# reason ("will chill", not "chills").
	#
	# --- SPELLEMENTS (the `weapon` slot): attachments that reshape a spell you own ---
	"pl_emberglass":  {"name": "Emberglass Sliver", "desc": "COMING SOON — will set your spells alight, burning what they touch.", "element": "", "effect": {}, "placeholder": true},
	"pl_rimeshard":   {"name": "Rimeshard",         "desc": "COMING SOON — will chill on contact, slowing what you hit.",          "element": "", "effect": {}, "placeholder": true},
	"pl_stormtooth":  {"name": "Stormtooth",        "desc": "COMING SOON — will arc your spells on to a second target.",           "element": "", "effect": {}, "placeholder": true},
	"pl_gravewick":   {"name": "Gravewick",         "desc": "COMING SOON — will drain a sliver of life back on every hit.",        "element": "", "effect": {}, "placeholder": true},
	"pl_sunmote":     {"name": "Sunmote",           "desc": "COMING SOON — will turn every third cast into a mend, not a wound.",  "element": "", "effect": {}, "placeholder": true},
	"pl_voidpin":     {"name": "Voidpin",           "desc": "COMING SOON — will drag enemies toward the point of impact.",         "element": "", "effect": {}, "placeholder": true},
	"pl_quickthread": {"name": "Quicksilver Thread","desc": "COMING SOON — will shorten the wind-up on every spell you cast.",     "element": "", "effect": {}, "placeholder": true},
	"pl_echostone":   {"name": "Echostone",         "desc": "COMING SOON — will echo your last spell back at half strength.",      "element": "", "effect": {}, "placeholder": true},
	# --- HELMS (the `head` slot) ---
	"pl_seers_circlet": {"name": "Seer's Circlet",  "desc": "COMING SOON — will show you an enemy's tell a beat earlier.",         "element": "", "effect": {}, "placeholder": true},
	"pl_ironbrow":      {"name": "Ironbrow",        "desc": "COMING SOON — will shrug off the first stun of every floor.",         "element": "", "effect": {}, "placeholder": true},
	"pl_veilhood":      {"name": "Veilhood",        "desc": "COMING SOON — will break their line of sight for a moment after a dash.", "element": "", "effect": {}, "placeholder": true},
	"pl_crown_of_hours":{"name": "Crown of Hours",  "desc": "COMING SOON — will slow the world for a heartbeat when you fall low.", "element": "", "effect": {}, "placeholder": true},
	# --- ARMOUR (the `body` slot) ---
	"pl_ashplate":   {"name": "Ashplate",           "desc": "COMING SOON — will burn whatever strikes you in close.",              "element": "", "effect": {}, "placeholder": true},
	"pl_tideweave":  {"name": "Tideweave Wrap",     "desc": "COMING SOON — will knit you back together while you stand still.",    "element": "", "effect": {}, "placeholder": true},
	"pl_thornmail":  {"name": "Thornmail Vest",     "desc": "COMING SOON — will return a share of every wound you take.",          "element": "", "effect": {}, "placeholder": true},
	"pl_stormcoat":  {"name": "Stormcoat",          "desc": "COMING SOON — will discharge a shock the moment your ward breaks.",   "element": "", "effect": {}, "placeholder": true},
	# --- GREAVES (the `legs` slot) — NEW ---
	# ⚠ A FOURTH SLOT, AND THE THREE-LITERAL CONTRACT ABOVE IS NOT BROKEN BY IT.
	# `Hero._aggregate_gear` still iterates "weapon"/"head"/"body" and still owns the
	# stat maths; `legs` is deliberately outside that loop, which costs NOTHING here
	# because every piece below carries the same empty effect bag as the rest of the
	# armoury. The day a greave gets a real stat, the fix is one literal in Hero.gd —
	# and until then a slot Hero cannot read cannot silently apply anything.
	# `GameState.LOADOUT_SLOTS` DOES carry it, because the save has to round-trip the
	# player's choice or the screen forgets it the moment they walk away.
	#
	# It exists because the maker asked for gear that REPLACES a body part, and the
	# lower leg is the third one a stick figure has. See `CharacterRig._draw_leg`.
	"pl_swiftsoles":  {"name": "Swiftsoles",        "desc": "COMING SOON — will let you keep your speed through a turn.",          "element": "", "effect": {}, "placeholder": true},
	"pl_ironmarch":   {"name": "Ironmarch Greaves", "desc": "COMING SOON — will hold your ground against a shove.",                "element": "", "effect": {}, "placeholder": true},
	"pl_ashenstride": {"name": "Ashenstride Boots", "desc": "COMING SOON — will leave a scorch trail where you dash.",             "element": "", "effect": {}, "placeholder": true},
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


## ⚠ THE ARMOURY MENU LIVES HERE, NOT IN THE UI. `Loadout.OPTIONS` is built from this
## table rather than typing the ids a second time, because a menu that duplicates its
## own catalogue is a menu that can disagree with it — and the failure mode is silent:
## a typo'd id shows a button captioned with the raw id, equips a kind with no ability
## row, and reads as a broken stat rather than as a missing item.
##
## SLOT KEYS ARE STILL "weapon"/"head"/"body" AND THAT IS A CONTRACT, NOT A LEFTOVER.
## `Hero._aggregate_gear` iterates those three literals, `GameState.LOADOUT_SLOTS`
## sanitises saves against them, and both files belong to someone else. The armoury
## reads the slots differently now (a spellement and two pieces of armour — see
## `Loadout.SLOT_LABELS`), but renaming the KEYS would silently drop every player's
## saved loadout on the floor while looking like a cosmetic change.
const PLACEHOLDER_SLOTS: Dictionary = {
	"weapon": ["pl_emberglass", "pl_rimeshard", "pl_stormtooth", "pl_gravewick",
		"pl_sunmote", "pl_voidpin", "pl_quickthread", "pl_echostone"],
	"head": ["pl_seers_circlet", "pl_ironbrow", "pl_veilhood", "pl_crown_of_hours"],
	"body": ["pl_ashplate", "pl_tideweave", "pl_thornmail", "pl_stormcoat"],
	"legs": ["pl_swiftsoles", "pl_ironmarch", "pl_ashenstride"],
}


## True when the piece is a NAMED PROMISE rather than a working item. The armoury
## reads this to tag the button and to refuse to pretend on the paper doll; the
## suites read it to assert the effect bag is empty.
static func is_placeholder(kind: String) -> bool:
	return bool((ABILITIES.get(kind, {}) as Dictionary).get("placeholder", false))


## Every id offered in `slot` right now. Empty for an unknown slot (never null, so a
## caller can iterate the result without a guard).
static func options_for(slot: String) -> Array:
	return PLACEHOLDER_SLOTS.get(slot, [])
