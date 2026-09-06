class_name GearAbilities
extends RefCounted
## Registry: every pixel gear piece carries a UNIQUE ability + identity (maker:
## "unique abilities on each gear piece"). This is the DATA FOUNDATION — name,
## description, and an element hint per piece — queryable by the loadout UI and by
## the Hero once the effects are activated.
##
## SCOPE NOTE (honest): the balance pass this file used to be WAITING for has now been
## done for the armoury's nineteen pieces — they carry live, budgeted, mutually
## non-dominating stats, and the reasoning is written down at the armoury block below
## rather than left to be rediscovered. It is still pure DATA: nothing here reaches into
## combat, `Hero._aggregate_gear` pulls from it, and that direction is the whole reason
## a bad number here can be re-tuned without touching a class.
##
## ⚠ NONE OF IT HAS BEEN PLAYTESTED. Every number below is reasoned from the envelope
## the retired catalogue already established and asserted against the invariants that
## matter (no strict dominance, everything pays, everything inside the budget). That
## makes it defensible on paper and nothing more — "no item is unpickable" is not the
## same claim as "these are the right numbers", and only the maker's hands can close
## that gap. Re-tuning is a one-line edit per row, by design.

## kind -> {name, desc, element, effect}. `effect` is a machine-readable modifier
## bag the Hero aggregates (Hero._aggregate_gear); ACTIVE effects are the ones with
## a single clean combat hook. `element` (string) is deliberately NOT the Elements
## enum so this file stays dependency-free — the Hero maps it. Descriptions match
## the WIRED behaviour (no promises the code doesn't keep).
##
## effect keys: element (str) | melee_damage/melee_knockback/melee_cd/max_hp/speed
## (float mults) | ward (float 0..1, first-hit reduction) | damage_reduction (float
## 0..1, flat % off EVERY hit). {} = no hero effect (enemy/boss pieces — their
## "ability" is the roster AI behaviour they already drive).
##
## ⚠ THAT LIST IS THE WHOLE VOCABULARY, AND `Hero._aggregate_gear` IS THE ONLY READER.
## A key that is not on it is not "unsupported yet", it is INERT AND SILENT: the bag
## accepts it, the suites' well-formedness sweep skips it (it only walks known axes),
## the description promises it, and nothing ever applies it. That is the single
## cheapest way to ship a lie in this file, so a piece whose fantasy needs a verb that
## does not exist is wired to the CLOSEST REAL AXIS and described in those terms —
## never given an invented key. `pl_thornmail` "returns a share of every wound" with no
## reflect axis in the engine, so it is wired as the thing a spiked vest actually does
## to a body that closes on it (+35% knockback) and its description says exactly that.
##
## ⚠ `ward` AND `damage_reduction` COMBINE WITH `maxf`, NOT MULTIPLICATION. Two pieces
## carrying a ward do not stack — the bigger one simply wins and the other is wasted.
## So two wards in the SAME slot would be a straight downgrade for one of them, and two
## in DIFFERENT slots is a trap the player cannot see. `pl_sunmote` (weapon),
## `pl_crown_of_hours` (head) and `pl_stormcoat` (body) all carry 0.40 for exactly one
## reason: each is the ONLY ward its slot offers, so the choice is always "a ward or
## something else" and never "a ward or the same ward".
##
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
## STILL OPEN ON THE RETIRED CATALOGUE, AND A DESIGN CALL RATHER THAN A DEFECT: most
## of the sixteen RETIRED pieces above still strictly dominate the EMPTY slot. Only
## `greatsword`, `helmet` and `hammer` pay for anything, so for them "equip something"
## remains a checklist even though "equip WHICH" is a real choice. Closing that means
## giving most of the old roster a real cost, which changes how every class plays and
## wants the maker's hands on it. It is deliberately NOT closed here.
##
## ⚠ AND THE NINETEEN ARMOURY PIECES BELOW DO NOT MAKE IT WORSE — every one of them
## pays. That was the one rule the new catalogue could not inherit, because these are
## the pieces a player actually picks from: the sixteen above are off the menu, so
## their free lunch is inert, while a free lunch on an OFFERED piece is a live one. So
## each of the nineteen is worse than the empty slot on at least one axis the hero
## reads, and `slice_test_gear.gd` sweeps all four slots for it rather than the three
## the retired list occupied.
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
	# ⚠ THE PROMISES HAVE BEEN KEPT. The nineteen below WERE named promises with empty
	# effect bags and a COMING SOON tag; they are now real items with live stats. The old
	# rule ("every placeholder's effect is {}, and that is the point") existed to stop a
	# stub quietly becoming balance before anyone designed it. That danger is not dodged
	# by staying empty forever — it is retired by DESIGNING the thing, on the record, to
	# a stated budget, with the invariants asserted. Which is what follows.
	#
	# ⚠ THE BUDGET IS THE EXISTING CATALOGUE'S ENVELOPE, DELIBERATELY. Every number here
	# lands inside the range the retired sixteen already established and the balance pass
	# already lived with:
	#     max_hp 0.94–1.20  |  speed 0.92–1.12  |  melee_damage 0.82–1.30
	#     melee_cd 0.70–1.30 (LOWER IS BETTER)  |  melee_knockback 0.88–1.40
	#     ward 0.40 (one-shot)  |  damage_reduction 0.15 (flat, every hit)
	# Nothing here is stronger than something the game has already been tuned against, so
	# the armoury becomes a real choice without becoming a power creep. The alternative —
	# picking numbers that felt good per item — is how a catalogue ends up with a best
	# item, and a best item is the same dead content as a dominated one seen from the
	# other end.
	#
	# ⚠ DEPTH BUYS A SHARPER TRADE, NEVER A BIGGER NUMBER. `Progression.GEAR_UNLOCK` gates
	# these by floor / level / class, and the tempting reading is "floor 10 item > floor 1
	# item". That reading is FORBIDDEN by the no-dominance rule and it is also wrong for
	# this game: unlocks here are THRESHOLDS you pass, not a currency you spend, so a
	# strictly-better late piece would delete the early one from the game the moment you
	# walked past it. `pl_crown_of_hours` (floor 10) is not a better `pl_veilhood` (floor
	# 1) — it is a ward bought with your feet, which is a trade a fresh climber is not
	# offered rather than a trade that is simply better.
	#
	# ⚠ A NAME IS A PROMISE THE STATS HAVE TO KEEP. These were authored NAME-FIRST: read
	# the name, decide what the player would guess before reading a number, then find the
	# axes that mean it. `pl_ironbrow` is heavy and `pl_veilhood` is light because the
	# words say so, and an armoury a player can guess at is an armoury they can shop in at
	# a glance. Where the fantasy needed a verb the engine does not have (lifesteal,
	# reflect, line-of-sight, time-stop) it is wired to the nearest REAL axis and the
	# description is rewritten to say what actually happens — see the vocabulary note in
	# the header. No description here describes an effect the code does not apply.
	#
	# --- SPELLEMENTS (the `weapon` slot): attachments that reshape a spell you own ---
	# ⚠ SIX OF THE EIGHT SET YOUR ELEMENT, AND THAT IS A LATERAL TRADE, NOT A GAIN. A
	# spellement in this slot OVERRIDES the element your class already has (see
	# `Hero.GEAR_ELEMENT`), so "strikes as Fire" is a swap rather than a bonus and there is
	# no axis on which to charge for it. The retired staffs were EXEMPTED from the
	# pays-something rule for exactly that reason. These are not exempted: every one of
	# them ALSO pays a real numeric cost, so the exemption list does not have to grow and
	# the weapon slot holds itself to the same bar as the other three.
	# The two without an element (`pl_quickthread`, `pl_echostone`) are mechanisms rather
	# than elements — they keep whatever element you brought, which is its own reason to
	# take one.
	"pl_emberglass":  {"name": "Emberglass Sliver", "desc": "Your spells strike as Fire, and the shard bites deep (+18% melee damage) — but emberglass is brittle (-6% max HP).", "element": "fire", "effect": {"element": "fire", "melee_damage": 1.18, "max_hp": 0.94}},
	"pl_rimeshard":   {"name": "Rimeshard",         "desc": "Your spells strike as Ice and every blow shoves (+25% knockback), but the cold is in you too (-6% move speed).", "element": "ice", "effect": {"element": "ice", "melee_knockback": 1.25, "speed": 0.94}},
	"pl_stormtooth":  {"name": "Stormtooth",        "desc": "Your spells strike as Lightning and you strike far faster (-18% swing cooldown), but each bite lands light (-10% melee damage).", "element": "lightning", "effect": {"element": "lightning", "melee_cd": 0.82, "melee_damage": 0.9}},
	"pl_gravewick":   {"name": "Gravewick",         "desc": "Your spells strike as Shadow, and what it takes it keeps (+16% max HP) — but a burning wick has little bite left (-12% melee damage).", "element": "shadow", "effect": {"element": "shadow", "max_hp": 1.16, "melee_damage": 0.88}},
	"pl_sunmote":     {"name": "Sunmote",           "desc": "Your spells strike as Holy, and the first hit of every fight is turned aside (-40%) — but a mote of light is no weapon (-12% melee damage).", "element": "holy", "effect": {"element": "holy", "ward": 0.4, "melee_damage": 0.88}},
	"pl_voidpin":     {"name": "Voidpin",           "desc": "Your spells strike as Arcane and pin rather than shove: +20% melee damage, -12% knockback, so they stay in your reach.", "element": "arcane", "effect": {"element": "arcane", "melee_damage": 1.2, "melee_knockback": 0.88}},
	"pl_quickthread": {"name": "Quicksilver Thread","desc": "The shortest wind-up in the armoury: -26% swing cooldown, keeping whatever element you brought — but nothing that quick lands heavy (-16% melee damage).", "element": "", "effect": {"melee_cd": 0.74, "melee_damage": 0.84}},
	"pl_echostone":   {"name": "Echostone",         "desc": "Every strike lands with its own echo (+30% melee damage), but the stone needs time to ring again (+28% swing cooldown).", "element": "", "effect": {"melee_damage": 1.3, "melee_cd": 1.28}},
	# --- HELMS (the `head` slot) ---
	# The head slot is the LIGHT-vs-HEAVY axis the retired `hat`/`hood`/`helmet` trio used
	# to carry, and the names already sort themselves: a hood is light, an iron brow is
	# not. `pl_seers_circlet` is the odd one out on purpose — "sees the tell a beat
	# earlier" has no perception axis in this engine, so it is wired as the thing seeing a
	# tell early actually buys you (you answer sooner: -16% swing cooldown) and pays the
	# price a circlet obviously pays (it stops nothing: -6% max HP).
	"pl_seers_circlet": {"name": "Seer's Circlet",  "desc": "You read the tell a beat early and answer it: -16% swing cooldown — but a circlet turns nothing aside (-6% max HP).", "element": "", "effect": {"melee_cd": 0.84, "max_hp": 0.94}},
	"pl_ironbrow":      {"name": "Ironbrow",        "desc": "A heavy iron brow: +20% max HP, but it weighs on you (-6% move speed).", "element": "", "effect": {"max_hp": 1.2, "speed": 0.94}},
	"pl_veilhood":      {"name": "Veilhood",        "desc": "Light and loose: +10% move speed, with nothing between you and a hit (-6% max HP).", "element": "", "effect": {"speed": 1.1, "max_hp": 0.94}},
	"pl_crown_of_hours":{"name": "Crown of Hours",  "desc": "Time thickens around the first hit of every fight (-40%) — and around your feet with it (-8% move speed).", "element": "", "effect": {"ward": 0.4, "speed": 0.92}},
	# --- ARMOUR (the `body` slot) ---
	# ⚠ `pl_ashplate` AND `pl_thornmail` BOTH NAME A RETALIATION THE ENGINE CANNOT DO —
	# "burns whatever strikes you", "returns a share of every wound". There is no reflect
	# axis and inventing one would make both of them silently inert (see the vocabulary
	# note in the header). So each is wired to what its SHAPE really does to a body that
	# closes on it: the plate soaks (flat mitigation), the spiked vest throws them off
	# (knockback), and both descriptions were rewritten to say only that.
	"pl_ashplate":   {"name": "Ashplate",           "desc": "Ash-forged plate: -15% damage from every hit, at the cost of your feet (-8% move speed).", "element": "", "effect": {"damage_reduction": 0.15, "speed": 0.92}},
	"pl_tideweave":  {"name": "Tideweave Wrap",     "desc": "Bound tide-cloth knits you together: +12% max HP, but a wrapped arm swings soft (-10% melee damage).", "element": "", "effect": {"max_hp": 1.12, "melee_damage": 0.9}},
	"pl_thornmail":  {"name": "Thornmail Vest",     "desc": "Spiked: anything that closes gets thrown off you (+35% knockback), and the thorns catch your own swing (+12% swing cooldown).", "element": "", "effect": {"melee_knockback": 1.35, "melee_cd": 1.12}},
	"pl_stormcoat":  {"name": "Stormcoat",          "desc": "Storm-borne: the first hit of every fight breaks on it (-40%) and you ride the gale (+8% move speed) — but a coat is not armour (-6% max HP).", "element": "", "effect": {"ward": 0.4, "speed": 1.08, "max_hp": 0.94}},
	# --- GREAVES (the `legs` slot) ---
	# It exists because the maker asked for gear that REPLACES a body part, and the
	# lower leg is the third one a stick figure has. See `CharacterRig._draw_leg`.
	#
	# ⚠⚠ THESE THREE ARE THE ONLY PIECES IN THE ARMOURY WHOSE STATS DO NOT REACH THE HERO
	# YET, AND THE REASON IS ONE LINE IN A FILE THIS ONE DOES NOT OWN.
	# `Hero._aggregate_gear` iterates the literal `["weapon", "head", "body"]`. `legs` is
	# not in it, so a greave's bag is read by nobody. When the other eighteen went live
	# this was the one slot that could not follow, and there were exactly two honest ways
	# to handle it:
	#   * REJECTED — leave the greaves statless. Then they fail the "every piece must pay"
	#     rule for the only reason that is not a design reason (they give nothing, so they
	#     cost nothing), and the legs slot stays a decoration in a screen where the other
	#     three slots became decisions. The maker asked for nineteen real items.
	#   * TAKEN — author them properly, to the same budget and the same no-dominance bar
	#     as everything above, and flag them `unwired` so the SCREEN tells the truth while
	#     the wiring is one literal away. `Loadout` prints [SLOT NOT LIVE YET] on exactly
	#     these three, so the player is never sold a stat that does not fire.
	# The fix, for whoever owns Hero.gd:
	#     for slot: String in ["weapon", "head", "body", "legs"]:
	# and then delete the three `"unwired": true` flags below. `slice_test_gear.gd`
	# asserts those two halves move TOGETHER — it reads Hero's loop and fails if a greave
	# is flagged unwired while Hero reads legs, or unflagged while Hero does not. So this
	# cannot rot in either direction: fixing Hero without clearing the flags goes red, and
	# clearing the flags without fixing Hero goes red.
	#
	# `GameState.LOADOUT_SLOTS` already carries `legs`, because the save has to round-trip
	# the player's choice or the screen forgets it the moment they walk away.
	#
	# ⚠ `pl_ironmarch` NAMES A SHOVE-RESISTANCE THE ENGINE DOES NOT HAVE. `melee_knockback`
	# is the knockback you DEAL, not the knockback you SOAK, so wiring "hold your ground
	# against a shove" to it would have been backwards as well as inert. Iron greaves are
	# wired as weight — HP up, feet down — and described as weight.
	"pl_swiftsoles":  {"name": "Swiftsoles",        "desc": "Barely there: +12% move speed, with nothing to soak a hit (-6% max HP).", "element": "", "effect": {"speed": 1.12, "max_hp": 0.94}},
	"pl_ironmarch":   {"name": "Ironmarch Greaves", "desc": "Iron to the knee: +18% max HP, and every step costs you (-8% move speed).", "element": "", "effect": {"max_hp": 1.18, "speed": 0.92}},
	"pl_ashenstride": {"name": "Ashenstride Boots", "desc": "The middle road: +6% move speed and -10% swing cooldown, bought with your guard (-6% max HP).", "element": "", "effect": {"speed": 1.06, "melee_cd": 0.9, "max_hp": 0.94}},
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
##
## ⚠ THE CONST'S NAME IS NOW A MISNOMER AND IS KEPT ANYWAY. Nothing in it is a
## placeholder any more — these are the nineteen live items the armoury offers. The name
## survives because it is READ BY FILES THIS ONE DOES NOT OWN (`GameState.gd`'s save
## sanitiser) and by four suites, so renaming it is a cross-file change dressed up as a
## tidy-up, and the failure mode is a save sanitiser that silently matches nothing and
## drops every equipped piece. Read it as "the ids the armoury offers, per slot" — which
## is all any caller ever used it for.
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
##
## ⚠ NOTHING IN THE ARMOURY ANSWERS TRUE ANY MORE, AND THE FUNCTION STILL EXISTS ON
## PURPOSE. All nineteen `pl_*` pieces carry live stats now, so every caller correctly
## stops tagging them — but this is the seam the NEXT batch of promises will hang on,
## and deleting it would mean the next stub ships with no way to say it is a stub. It
## reads a per-row flag rather than a name prefix (`pl_`) for the same reason: the
## prefix is now a historical accident of these nineteen ids, not a statement about
## whether an item works, and a helper that confused the two would re-tag the entire
## working catalogue the moment someone trusted it.
static func is_placeholder(kind: String) -> bool:
	return bool((ABILITIES.get(kind, {}) as Dictionary).get("placeholder", false))


## True when the piece has real, designed stats that the HERO CANNOT READ YET because
## its slot is not in `Hero._aggregate_gear`'s loop. Today that is exactly the three
## greaves — see the ⚠⚠ block on the `legs` rows for the one-line fix and for why the
## flag exists instead of simply leaving those three statless.
##
## ⚠ THIS IS NOT A SOFTER `is_placeholder`. A placeholder has NO design behind it; an
## unwired piece is fully designed, fully budgeted and fully asserted, and is waiting on
## a literal in someone else's file. They are tagged differently in the armoury for that
## reason: one says "we have not built this", the other says "this slot is not live
## yet", and a player owed an explanation deserves the accurate one.
static func is_unwired(kind: String) -> bool:
	return bool((ABILITIES.get(kind, {}) as Dictionary).get("unwired", false))


## Every id offered in `slot` right now. Empty for an unknown slot (never null, so a
## caller can iterate the result without a guard).
static func options_for(slot: String) -> Array:
	return PLACEHOLDER_SLOTS.get(slot, [])
