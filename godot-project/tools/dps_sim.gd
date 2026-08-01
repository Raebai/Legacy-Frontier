extends SceneTree
## SWORD vs SPELLS — a headless single-target damage estimator.
##
## Run:
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
##       --path godot-project --script tools/dps_sim.gd
##   ... --script tools/dps_sim.gd -- --window=60 --verbose
##
## Options (`--key=value`, order-independent):
##   --window=SEC   how long a rotation is simulated. Default 60.
##   --verbose      print every carried spell's id / damage / cooldown / tier.
##   --strict       exit 1 if any class's spell-only DPS loses to bare FISTS.
##
## ══ WHY THIS TOOL EXISTS ══════════════════════════════════════════════════════
## The fun audit measured melee at ~76 DPS (sword) against ~32 DPS for an
## Arcanist's whole three-spell kit, and read the consequence as "grab the sword,
## hold melee, cast as garnish" — the wrong dominant strategy for a game about
## absurd magic. That measurement was arithmetic on paper (sum of damage/cooldown).
## This runs the same question as a ROTATION, which is what a player actually does:
## cast whatever is off cooldown, punch in the gaps.
##
## ══ WHAT IT MEASURES, HONESTLY ════════════════════════════════════════════════
## SINGLE TARGET, standing still, everything connects, nobody dodges. That is the
## BOSS case on purpose — it is the fight the audit says matters and the one where
## AoE cannot rescue a caster. A crowd flips the comparison hard the other way
## (one nova hits seven bodies, one punch hits one), so nothing here should be read
## as "the sword is better than magic" in general. It is the floor of the caster's
## case, and the floor is what was broken.
##
## What it cannot tell you: whether casting FEELS better, whether you land the
## meteor, whether the windup gets you killed. A sim is not a playtest.
##
## ══ THE ONE JUDGEMENT CALL IN HERE ════════════════════════════════════════════
## `SpellDef.damage` is per-HIT, and some spells hit a single target more than
## once. `SINGLE_TARGET_HITS` below is an explicit, reviewable estimate per Kind
## rather than a hidden fudge — it is the only number in this file that is not read
## straight off the shipped data.

const LIB_PATH: String = "res://scripts/combat/SpellLibrary.gd"
const TIER_PATH: String = "res://scripts/combat/SpellTier.gd"
const INFO_PATH: String = "res://scripts/combat/ClassInfo.gd"

## Hero.gd constants, mirrored. Hero.gd cannot be loaded here (it drags the whole
## combat graph and the autoloads with it), so these are copied and the values are
## re-asserted by `tools/slice_test_melee_economy.gd` against the real file.
const MELEE_COOLDOWN: float = 0.34
const FISTS_DAMAGE: int = 14
const SWORD_DAMAGE: int = 26
const CAST_COOLDOWN: float = 0.35

## How many times one cast of a given Kind lands on ONE body. Everything absent is
## 1. Several spells declare `damage` PER TICK or PER PROJECTILE, so reading the
## field alone understates them by a factor of five. Read off the spectacle scripts:
##   TETHER   — `DrainTether.DRAIN_TIME 1.2 / TICK 0.24` = 5 ticks if never broken.
##   ZONE     — `ZoneSpell` lives 4.5 s and ticks every 0.4 s (11 max). A boss moves
##              at 66 px/s and the field is 135 px across, so it eats a lot of them;
##              4 is a deliberately conservative "stood in it for 1.6 seconds".
##   FLURRY   — `count` crescents fanned over 0.42 s; ~half cross one body.
##   MISSILES — `count` orbs on a spread; ~2-3 of 6 land on a single target.
##   METEOR   — a barrage over `radius`; ~3 of 10-12 land on a colossus.
##   CHAIN    — the primary bolt only; the hops are what pay in a crowd, not on a
##              boss, and the boss case is what this tool is for.
const SINGLE_TARGET_HITS: Dictionary = {
	"FLURRY": 3.0,
	"MISSILES": 2.5,
	"METEOR": 3.0,
	"TETHER": 5.0,
	"ZONE": 4.0,
}

var _window: float = 60.0
var _verbose: bool = false
var _strict: bool = false
var _ran: bool = false
var _losses: int = 0


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_parse_args()
	var lib: GDScript = load(LIB_PATH) as GDScript
	var tier: GDScript = load(TIER_PATH) as GDScript
	var info: GDScript = load(INFO_PATH) as GDScript
	print("")
	print("════════════════════════════════════════════════════════════════════")
	print(" SINGLE-TARGET DPS — spells vs melee   (window %.0fs)" % _window)
	print(" Rotation: cast anything off cooldown, punch in the gaps.")
	print(" A SIM IS NOT A PLAYTEST. Single target, everything connects.")
	print("════════════════════════════════════════════════════════════════════")
	print(" fists  %5.1f dps   (%d dmg / %.2fs)" % [
		float(FISTS_DAMAGE) / MELEE_COOLDOWN, FISTS_DAMAGE, MELEE_COOLDOWN])
	print(" sword  %5.1f dps   (%d dmg / %.2fs)" % [
		float(SWORD_DAMAGE) / MELEE_COOLDOWN, SWORD_DAMAGE, MELEE_COOLDOWN])
	print("")
	print(" %-13s %8s %8s %8s %8s" % ["class", "spells", "+fists", "+sword", "spell%"])
	print(" " + "-".repeat(50))
	var names: Array = _class_names(info)
	for cid: int in range(9):
		var kit: Array = lib.build_for_class(cid)
		var spells_only: float = _sim(kit, 0)
		var with_fists: float = _sim(kit, FISTS_DAMAGE)
		var with_sword: float = _sim(kit, SWORD_DAMAGE)
		var share: float = 0.0
		if with_sword > 0.0:
			share = 100.0 * spells_only / with_sword
		var flag: String = ""
		if spells_only < float(FISTS_DAMAGE) / MELEE_COOLDOWN:
			flag = "  <- loses to FISTS"
			_losses += 1
		print(" %-13s %8.1f %8.1f %8.1f %7.0f%%%s" % [
			names[cid] if cid < names.size() else str(cid),
			spells_only, with_fists, with_sword, share, flag])
		if _verbose:
			for s in kit:
				print("      %-16s dmg %3d  cd %4.2f  cast %4.2f  %-5s  x%.1f" % [
					String(s.get("id")), int(s.get("damage")), float(s.get("cooldown")),
					float(s.get("cast_time")), tier.display_name(tier.of(s)),
					_hits_for(tier, s)])
	print("")
	print(" spell%% = the share of your damage that came out of the SPELL BUTTONS")
	print(" while holding the sword. Below ~50%% the sword is the strategy and the")
	print(" kit is the garnish.")
	print("")
	if _strict and _losses > 0:
		printerr("dps_sim: %d class kit(s) do less single-target damage than bare fists" % _losses)
		quit(1)
	else:
		quit(0)
	return true


## One rotation. `melee_damage` 0 = never punch (the spell-only column).
func _sim(kit: Array, melee_damage: int) -> float:
	var dt: float = 0.01
	var cds: Array[float] = []
	var tier: GDScript = load(TIER_PATH) as GDScript
	for _s in kit:
		cds.append(0.0)
	var melee_cd: float = 0.0
	var gcd: float = 0.0
	var busy: float = 0.0            # cast_time commitment (levitating, no melee)
	var total: float = 0.0
	var t: float = 0.0
	while t < _window:
		if busy > 0.0:
			busy = maxf(busy - dt, 0.0)
		else:
			# Prefer the biggest ready hit, which is what a player converges on.
			var best: int = -1
			var best_dmg: float = 0.0
			for i: int in range(kit.size()):
				if cds[i] > 0.0 or gcd > 0.0:
					continue
				var d: float = float(kit[i].get("damage")) * _hits_for(tier, kit[i])
				if d > best_dmg:
					best_dmg = d
					best = i
			if best >= 0:
				total += best_dmg
				cds[best] = float(kit[best].get("cooldown"))
				gcd = CAST_COOLDOWN
				busy = float(kit[best].get("cast_time"))
			elif melee_damage > 0 and melee_cd <= 0.0:
				total += float(melee_damage)
				melee_cd = MELEE_COOLDOWN
		for i: int in range(cds.size()):
			cds[i] = maxf(cds[i] - dt, 0.0)
		melee_cd = maxf(melee_cd - dt, 0.0)
		gcd = maxf(gcd - dt, 0.0)
		t += dt
	return total / _window


func _hits_for(tier: GDScript, spell: Variant) -> float:
	var kind_name: String = _kind_name(int(spell.get("kind")))
	return float(SINGLE_TARGET_HITS.get(kind_name, 1.0))


## SpellDef.Kind ordinal -> name, without loading SpellDef (whose `class_name`
## resolves fine here but whose enum is easier to mirror than to reflect on).
func _kind_name(k: int) -> String:
	var names: Array[String] = [
		"BEAM", "DIVINE_RAY", "NOVA", "METEOR", "CONVERGENCE", "RUSH", "BOULDER",
		"PILLAR", "WALL", "ICE_WALL", "CHAIN", "ZONE", "MISSILES", "BLINK_STRIKE",
		"TETHER", "FLURRY", "CRAWLER", "THROWN_ANCHOR", "WARD", "ARC", "HEX",
		"CATACLYSM",
	]
	if k < 0 or k >= names.size():
		return "?"
	return names[k]


func _class_names(info: GDScript) -> Array:
	var out: Array = []
	var rows: Variant = info.get("CLASSES")
	if rows is Array:
		for r in (rows as Array):
			if r is Dictionary:
				out.append(String((r as Dictionary).get("name", "?")))
	return out


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--verbose":
			_verbose = true
		elif arg == "--strict":
			_strict = true
		elif arg.begins_with("--window="):
			_window = maxf(float(arg.substr(9)), 5.0)
