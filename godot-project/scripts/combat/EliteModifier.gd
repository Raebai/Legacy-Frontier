class_name EliteModifier
extends RefCounted
## ELITE AFFIXES — the boss-modifier trick, applied to ordinary trash.
##
## ── WHY THIS FILE IS ALMOST A COPY OF BossModifier.gd, ON PURPOSE ─────────────
## `BossModifier` proved a shape: a modifier that must compose with a body whose
## script may not be edited cannot be a subclass, a mixin or an `if` — it has to be a
## RIDER, a plain Node parented to the body, poking the fields that body already
## exposes. Six of those gave four bosses the reading-surface of twenty.
##
## `Enemy.gd` is 1961 lines, has EIGHT archetypes, and is the single most-edited file
## in the combat layer. It is exactly the script that must not grow an `if` per
## variant. So the same seam applies here, and eight archetypes times a handful of
## riders is a very large amount of variety for one small directory.
##
## ── WHAT AN ELITE IS ALLOWED TO BE ───────────────────────────────────────────
## **NOT AN HP BUFF IN A COSTUME.** The spec is explicit — "higher floors add
## modifiers, not HP. HP scaling makes fights longer, not harder, and long is the
## enemy of chaos on a phone" — and trash `hp_multiplier` is pinned at 1.0 across the
## whole tower with a suite that fails the build if a generated floor carries one.
## An affix that quietly wrote `max_hp` would be that rule's back door, so
## `tools/slice_test_elites.gd` READS THE RIDER SOURCE and fails if any of them so
## much as mentions an hp field. Every affix below changes what the body DOES.
##
## ── IT HAS TO READ BEFORE IT HITS YOU ────────────────────────────────────────
## At 640x360 with eight archetypes already colour-coded, "slightly different shade
## of the same stick" is not a read. Three things carry it, and they are all in
## `EliteMark.gd`:
##
##   THE AURA   `CharacterRig.set_aura` is documented as "enemies stay bare sticks"
##              — strength 0, always. An elite is therefore the ONLY glowing body in
##              the room, with the tier-3 ground ring under it. That is the read.
##   THE WORD   one short capital word over its head, in the affix's own colour,
##              same mnemonic-not-sentence rule BossModifierHud settled on.
##   THE SIZE   a 12% taller silhouette. Not HP — the hurtbox follows the rig, so a
##              bigger elite is also an easier thing to hit, which is the correct
##              trade for something that is harder to fight.
##
## ── DETERMINISM (the thing that breaks a party if it is wrong) ───────────────
## Same rule as the boss roster, followed to the letter: the roll happens ONCE, on
## the host, inside `Encounter.spawn()`; the chosen ids travel in the spawn dictionary
## (`elite`); and `Encounter.build_enemy_from_data` — which runs on every peer and is
## locked byte-identical by `tools/slice_test_coop.gd` — merely READS them and calls
## `attach`. There is no randomness anywhere below this line.

## `id` is what travels in spawn data. Never rename one; append new rows.
const QUICKENED: String = "quickened"
const INKED: String = "inked"
const SMUDGED: String = "smudged"
const VOLATILE: String = "volatile"
const KEEN: String = "keen"
const HERALD: String = "herald"

const RIDER_DIR: String = "res://scripts/combat/elitemods/"
const MARK_SCRIPT: String = "res://scripts/combat/EliteMark.gd"

## THE REGISTRY.
##
##   min_floor — the shallowest depth an affix may be rolled at. Floor 1 has none at
##       all (see EliteRoster.budget): the first room a player ever fights in owes
##       them a clean reading of the eight archetypes before it starts editing them.
##   tint    — the colour the affix writes itself in, on the aura and on the word.
##       Chosen to sit OUTSIDE the eight archetype tints so an elite never reads as
##       "the orange one, but bluer".
##   verb    — the one-word promise, for a codex that does not exist yet.
const REGISTRY: Array[Dictionary] = [
	{
		"id": QUICKENED,
		"name": "QUICKENED",
		"blurb": "drawn in haste",
		"min_floor": 2,
		"tint": Color(1.0, 0.84, 0.30),
		"rider": "EliteQuickened.gd",
	},
	{
		"id": INKED,
		"name": "INKED",
		"blurb": "pressed too hard into the page",
		"min_floor": 2,
		"tint": Color(0.42, 0.52, 0.92),
		"rider": "EliteInked.gd",
	},
	{
		"id": SMUDGED,
		"name": "SMUDGED",
		"blurb": "the hand smeared it sideways",
		"min_floor": 3,
		"tint": Color(0.88, 0.86, 0.80),
		"rider": "EliteSmudged.gd",
	},
	{
		"id": VOLATILE,
		"name": "VOLATILE",
		"blurb": "the ink never dried",
		"min_floor": 3,
		"tint": Color(1.0, 0.46, 0.20),
		"rider": "EliteVolatile.gd",
	},
	{
		"id": KEEN,
		"name": "KEEN",
		"blurb": "it was drawn watching you",
		"min_floor": 4,
		"tint": Color(0.55, 0.92, 1.0),
		"rider": "EliteKeen.gd",
	},
	{
		"id": HERALD,
		"name": "HERALD",
		"blurb": "it calls the rest of the page",
		"min_floor": 5,
		"tint": Color(0.42, 0.92, 0.62),
		"rider": "EliteHerald.gd",
	},
]


# ------------------------------------------------------------------- the table
static func row(affix_id: String) -> Dictionary:
	for r: Dictionary in REGISTRY:
		if String(r["id"]) == affix_id:
			return r
	return {}


static func has(affix_id: String) -> bool:
	return not row(affix_id).is_empty()


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in REGISTRY:
		out.append(String(r["id"]))
	return out


## Which affixes may be rolled at this depth.
static func eligible_ids(depth: int) -> Array[String]:
	var d: int = maxi(depth, 1)
	var out: Array[String] = []
	for r: Dictionary in REGISTRY:
		if d >= int(r["min_floor"]):
			out.append(String(r["id"]))
	return out


static func name_for(affix_id: String) -> String:
	var r: Dictionary = row(affix_id)
	return String(r["name"]) if not r.is_empty() else affix_id.to_upper()


static func blurb_for(affix_id: String) -> String:
	var r: Dictionary = row(affix_id)
	return String(r["blurb"]) if not r.is_empty() else ""


static func tint_for(affix_id: String) -> Color:
	var r: Dictionary = row(affix_id)
	return (r["tint"] as Color) if not r.is_empty() else Color.WHITE


static func rider_path(affix_id: String) -> String:
	var r: Dictionary = row(affix_id)
	return (RIDER_DIR + String(r["rider"])) if not r.is_empty() else ""


# -------------------------------------------------------------- application
## THE APPLICATION HOOK. Parent one rider per affix onto `body`.
##
## Call it on an enemy that is NOT yet in the tree — riders defer their own setup to
## their first `_process`, exactly like the boss ones, because that is the only point
## the single-player `add_child` path and the co-op MultiplayerSpawner path both pass
## through (`Encounter.build_enemy_from_data`).
##
## `dressed` is the one thing this does that `BossModifier.attach` does not.
##   true  — an ELITE: aura, word, silhouette. A named event in the wave.
##   false — a FLOOR AFFIX: the same behaviour riding EVERY body on the floor, with
##           no per-body dressing at all. Sixteen glowing sticks is not a read, it is
##           a light show; a floor-wide rule is announced once, by the floor.
## Re-entrant: a body that already carries an affix is not given it twice, so an
## elite standing on an affixed floor keeps one rider and its elite dressing.
static func attach(body: Node, affix_ids: Array, ctx: Dictionary = {}, dressed: bool = true) -> Array[String]:
	var applied: Array[String] = []
	if body == null or affix_ids.is_empty():
		return applied
	for a in affix_ids:
		var aid: String = String(a)
		if not has(aid) or applied.has(aid):
			continue
		var node_name: String = "Elite_" + aid
		if body.has_node(NodePath(node_name)):
			continue
		var gs: GDScript = load(rider_path(aid)) as GDScript
		if gs == null:
			push_warning("EliteModifier: missing rider script for '%s'" % aid)
			continue
		var rider: Node = gs.new()
		rider.name = node_name
		rider.set("affix_id", aid)
		rider.set("affix_ctx", ctx)
		body.add_child(rider)
		applied.append(aid)
	if applied.is_empty() or not dressed:
		return applied
	if body.has_node(^"EliteMark"):
		return applied
	var mark_gs: GDScript = load(MARK_SCRIPT) as GDScript
	if mark_gs == null:
		return applied
	var mark: Node = mark_gs.new()
	mark.name = "EliteMark"
	mark.set("affix_ids", applied)
	body.add_child(mark)
	return applied
