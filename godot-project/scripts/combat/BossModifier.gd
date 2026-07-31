class_name BossModifier
extends Resource
## THE SIX MODIFIERS — the spec's answer to "twenty generated bosses".
##
## "...plus modifiers that change BEHAVIOUR rather than numbers: Enraged (faster
##  phases), Split (dies into two copies), Void-touched (leaves damaging zones),
##  Mirrored (copies the last spell cast), Patient (does nothing until attacked).
##  Four bosses with six modifiers reads as more variety than twenty generated
##  ones, at a tenth of the cost. Higher floors add modifiers, not HP."
##
## The spec names five and asks for six. The sixth is UNFINISHED, and the reasoning
## is in its row below.
##
## ── WHY A RESOURCE PLUS A RIDER NODE ─────────────────────────────────────────
## A modifier has to be composable with ANY boss in the roster, including the
## Ashspire Guardian, whose script must not be edited. So a modifier may not be a
## subclass, a mixin, or an `if` inside a boss — it has to reach in from outside.
##
## What it reaches in with is a RIDER: a plain Node parented to the boss, ticking
## alongside it, nudging the fields and calling the methods the boss already
## exposes. `_attack_cd`, `_busy`, `_bphase`, `_enter_phase()` — all of that is
## ordinary GDScript member access from a child node, and none of it requires a
## line inside Boss.gd.
##
## ── WHERE THE RIDER IS ATTACHED, AND WHY IT MATTERS ──────────────────────────
## Inside `Encounter.build_enemy_from_data`, BEFORE the boss enters the tree.
##
## That is the only place that runs on every peer with identical data. The obvious
## alternative — attach after `add_child` — exists on the single-player path but
## NOT on the co-op one, because there the MultiplayerSpawner owns the add_child
## and it lives in Arena.gd. Attaching pre-tree means both paths converge, and the
## rider simply defers its own setup to its first `_process` (by which point the
## boss's `_ready` has certainly run and its rig, bar and phase exist).
##
## ── THE AUTHORITY RULE ───────────────────────────────────────────────────────
## Riders run on every peer, so anything that SPAWNS or DAMAGES is gated on the
## boss's multiplayer authority exactly the way `Boss._physics_process` gates
## itself. Purely visual work (tints, auras, the HUD) runs everywhere, because a
## client that cannot see the modifier cannot play around it.

## `id` is what travels in spawn data. Never rename one; append new rows.
const ENRAGED: String = "enraged"
const SPLIT: String = "split"
const VOID_TOUCHED: String = "void_touched"
const MIRRORED: String = "mirrored"
const PATIENT: String = "patient"
const UNFINISHED: String = "unfinished"

const RIDER_DIR: String = "res://scripts/combat/bossmods/"

## THE REGISTRY.
##
##   min_floor — the shallowest depth this may be rolled at. This is the "higher
##       floors add MORE AND NASTIER modifiers" half of the spec: a floor-2 boss
##       can only draw from the gentle end, a floor-8 boss can draw from all of it.
##       PATIENT sits at 1 because it is, honestly, a gift — a free opening.
##       MIRRORED sits at 5 because being answered with your own ult is the single
##       hardest thing in the set to play around.
##   tint    — the colour the modifier writes itself in, on the HUD and (where it
##       makes sense) on the boss. One glance has to say which ones are live.
const REGISTRY: Array[Dictionary] = [
	{
		"id": PATIENT,
		"name": "PATIENT",
		"blurb": "it does nothing until struck",
		"min_floor": 1,
		"tint": Color(0.62, 0.66, 0.74),
		"rider": "ModPatient.gd",
	},
	{
		"id": ENRAGED,
		"name": "ENRAGED",
		"blurb": "its phases come early and fast",
		"min_floor": 2,
		"tint": Color(1.0, 0.36, 0.24),
		"rider": "ModEnraged.gd",
	},
	{
		"id": VOID_TOUCHED,
		"name": "VOID-TOUCHED",
		"blurb": "the page rots where it stands",
		"min_floor": 2,
		"tint": Color(0.62, 0.34, 0.95),
		"rider": "ModVoidTouched.gd",
	},
	{
		# THE SIXTH, and the reason it is this one rather than another number tweak.
		#
		# The other five each rewrite something the boss DOES — its pace (Enraged),
		# its body count (Split), the ground (Void-touched), its repertoire
		# (Mirrored), its aggression (Patient). Not one of them touches WHERE IT IS.
		# Spacing is the axis a phone player actually plays: the whole game is thumb
		# distance and dodge timing, and every boss in the roster is built around a
		# specific range it wants to hold. Unfinished takes that away.
		#
		# It is also the modifier most native to the lore. The tower is DRAWN; each
		# floor is a sheet of paper under an unseen hand. Unfinished is the artist
		# who kept changing their mind — the boss is ERASED mid-fight and REDRAWN
		# somewhere else, and the redraw mark lands on the page a beat before the
		# body does, so it is answerable: step off the mark.
		"id": UNFINISHED,
		"name": "UNFINISHED",
		"blurb": "the artist keeps rubbing it out",
		"min_floor": 3,
		"tint": Color(0.86, 0.84, 0.78),
		"rider": "ModUnfinished.gd",
	},
	{
		"id": SPLIT,
		"name": "SPLIT",
		"blurb": "it dies into two of itself",
		"min_floor": 3,
		"tint": Color(0.4, 0.9, 0.62),
		"rider": "ModSplit.gd",
	},
	{
		"id": MIRRORED,
		"name": "MIRRORED",
		"blurb": "it answers with your own spell",
		"min_floor": 5,
		"tint": Color(0.45, 0.82, 1.0),
		"rider": "ModMirrored.gd",
	},
]

@export var id: String = ""
@export var display_name: String = ""
@export var blurb: String = ""
@export var min_floor: int = 1
@export var tint: Color = Color.WHITE
@export var rider_script: String = ""


# ------------------------------------------------------------------- the table
static func row(mod_id: String) -> Dictionary:
	for r: Dictionary in REGISTRY:
		if String(r["id"]) == mod_id:
			return r
	return {}


static func has(mod_id: String) -> bool:
	return not row(mod_id).is_empty()


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in REGISTRY:
		out.append(String(r["id"]))
	return out


## Which modifiers may be rolled at this depth (the "nastier with depth" gate).
static func eligible_ids(depth: int) -> Array[String]:
	var d: int = maxi(depth, 1)
	var out: Array[String] = []
	for r: Dictionary in REGISTRY:
		if d >= int(r["min_floor"]):
			out.append(String(r["id"]))
	return out


static func name_for(mod_id: String) -> String:
	var r: Dictionary = row(mod_id)
	return String(r["name"]) if not r.is_empty() else mod_id.to_upper()


static func blurb_for(mod_id: String) -> String:
	var r: Dictionary = row(mod_id)
	return String(r["blurb"]) if not r.is_empty() else ""


static func tint_for(mod_id: String) -> Color:
	var r: Dictionary = row(mod_id)
	return (r["tint"] as Color) if not r.is_empty() else Color.WHITE


## The Resource form, for a caller that wants to pass one around / inspect one.
static func make(mod_id: String) -> BossModifier:
	var r: Dictionary = row(mod_id)
	if r.is_empty():
		return null
	var m := BossModifier.new()
	m.id = String(r["id"])
	m.display_name = String(r["name"])
	m.blurb = String(r["blurb"])
	m.min_floor = int(r["min_floor"])
	m.tint = r["tint"] as Color
	m.rider_script = RIDER_DIR + String(r["rider"])
	return m


# -------------------------------------------------------------- application
## THE APPLICATION HOOK. Parent one rider per modifier onto `boss`, plus the HUD
## that tells the player which ones are live.
##
## Call this on a boss that is NOT yet in the tree (see the class doc): riders
## defer their own setup to their first `_process`, so ordering is not a hazard.
##
## `ctx` carries what a rider may need to rebuild the boss (Split does) — the spawn
## dictionary the boss was built from. Kept as a plain Dictionary so it survives the
## co-op replication path unchanged.
static func attach(boss: Node, mod_ids: Array, ctx: Dictionary = {}) -> void:
	if boss == null or mod_ids.is_empty():
		return
	var applied: Array[String] = []
	for m in mod_ids:
		var mid: String = String(m)
		var r: Dictionary = row(mid)
		if r.is_empty() or applied.has(mid):
			continue
		var script_path: String = RIDER_DIR + String(r["rider"])
		var gs: GDScript = load(script_path) as GDScript
		if gs == null:
			push_warning("BossModifier: missing rider script %s" % script_path)
			continue
		var rider: Node = gs.new()
		rider.name = "Mod_" + mid
		rider.set("modifier_id", mid)
		rider.set("modifier_ctx", ctx)
		boss.add_child(rider)
		applied.append(mid)
	if applied.is_empty():
		return
	var hud_gs: GDScript = load("res://scripts/combat/BossModifierHud.gd") as GDScript
	if hud_gs == null:
		return
	var hud: Node = hud_gs.new()
	hud.name = "ModifierHud"
	hud.set("modifier_ids", applied)
	boss.add_child(hud)
