class_name EliteRoster
extends RefCounted
## HOW MANY ELITES A FLOOR GETS, AND WHICH AFFIX EACH ONE CARRIES.
##
## The trash-side twin of `BossRoster`, and written to the same rules: a TABLE and a
## DICE ROLL, nothing else. Everything here is static and pure — no tree, no
## autoloads, no side effects — so `roll()` returns the same answer for the same
## (depth, seed) on every machine, forever.
##
## ── HOW CO-OP STAYS HONEST ───────────────────────────────────────────────────
## Identical to the boss path, deliberately, because that path is already proven and
## already locked by `tools/slice_test_coop.gd`:
##
##   Encounter.spawn()                    host only (a client returns out of _process)
##     -> EliteRoster.roll(depth, randi(), archetype)   -> {"affixes": [...]}
##     -> the ids go into the spawn dictionary under `elite`
##     -> MultiplayerSpawner replicates the dict verbatim
##     -> Encounter.build_enemy_from_data(data)   runs on EVERY peer, reads `elite`
##
## `build_enemy_from_data` therefore stays what it is contractually required to be:
## pure construction from a dictionary, byte-identical on every peer, with no
## randomness of its own.
##
## ── RARITY IS THE DESIGN, AND IT IS A BUDGET RATHER THAN A CHANCE ────────────
## An elite has to be an EVENT. A flat per-spawn chance cannot deliver that: a floor
## spawns 27-58 bodies, so any chance high enough to reliably produce one produces
## four on a bad roll, and any chance low enough to keep four rare produces zero on
## most floors. Both failures are the same failure — the player cannot form an
## expectation, so the feature reads as noise.
##
## So the floor is handed a BUDGET (`budget()`), and `Encounter` spends it with
## remaining-budget-over-remaining-spawns pressure. That distributes the elites
## randomly through the floor's waves while GUARANTEEING the budget is spent by the
## last body — which is also what lets `tools/slice_test_elites.gd` assert that elites
## actually appear, rather than merely that they are well-formed on the rare floors
## where they do. (An invariant that is trivially true of an empty result is not an
## invariant; that lesson cost this repo a whole skyline once.)

## Elites per floor, by depth.
##
##   floor: 1  2  3  4  5  6+
##   elite: 0  1  1  2  2  2
##
## FLOOR 1 IS CLEAN, for the same reason `BossRoster.modifier_count(1)` is 0: the
## first room a player ever fights in owes them a clean reading of the eight
## archetypes before the tower starts editing them.
## The ceiling is 2 and stays 2. Depth escalates through the affix POOL getting
## nastier (`EliteModifier.REGISTRY.min_floor`) and through `affix_count`, not
## through the room filling up with named bodies — six glowing sticks is a light
## show, not an event.
const MAX_PER_FLOOR: int = 2


static func budget(depth: int) -> int:
	var d: int = maxi(depth, 1)
	if d <= 1:
		return 0
	if d <= 3:
		return 1
	return MAX_PER_FLOOR


## How many affixes ONE elite carries. Bosses stack up to four; an elite stacks one,
## and two only in the deep tower. The difference is screen budget: a boss owns the
## whole frame and a HUD row to explain itself, a trash mob owns one word over its
## head in a room with ten other bodies in it.
##
## ⚠ A THIRD WORD, AND ONLY IN THE ASCENT. The endless tower (`TowerDef.endless`)
## climbs past the authored ten, and the two dials this file owns — `budget` and
## `affix_count` — were both saturated by floor 5, so a floor-40 elite was the same
## body as a floor-6 one. The ceiling on BODIES stays 2 for the reason above (six
## glowing sticks is a light show), so the escalation has to be depth on ONE body.
## Three affixes is the whole pool for most archetypes, so it is also the last rung
## there is — the curve plateaus here rather than running away, which is the design
## note's stated shape.
##
##   floor: 1  5  21+
##   words: 1  2  3
##
## 21 rather than 11: the ascent's first band is already carrying a floor-wide affix
## on every body (`FloorGen.ascent_affix_count`), and stacking a third elite word on
## top of that in the same band is two escalations landing on one floor.
const ASCENT_AFFIX_DEPTH: int = 21


static func affix_count(depth: int) -> int:
	var d: int = maxi(depth, 1)
	if d >= ASCENT_AFFIX_DEPTH:
		return 3
	return 2 if d >= 5 else 1


## Affixes that must never ride certain archetypes, and why.
##
##   SMUDGED on CHARGER / ASSASSIN — both already own a commit-and-close move (the
##       lane dash, the lunge). A third way of arriving suddenly is not a third
##       reading, it is noise, and noise is indistinguishable from unfairness.
##   HERALD on SUMMONER — the summoner is already the roster's threat multiplier.
##       Stacking the two makes one body responsible for the entire wave, which is a
##       spike rather than a curve.
##   VOLATILE on BOMBER — the bomber's whole identity is "it detonates". An affix
##       that says the same thing says nothing.
const EXCLUDES: Dictionary = {
	EliteModifier.SMUDGED: [3, 5],     # CHARGER, ASSASSIN
	EliteModifier.HERALD: [4],         # SUMMONER
	EliteModifier.VOLATILE: [6],       # BOMBER
}

## Which affixes make sense applied to EVERY body on a floor rather than to one.
## See `FloorGen.floor_affixes_enabled` — this is the pool that feature draws from,
## and it is deliberately the three that describe a PAGE rather than a fighter.
## KEEN (a whole floor that dodges) and HERALD (heralds heralding heralds) are
## excluded on sight; SMUDGED is excluded because a room where every body blinks is
## not a floor with a character, it is a slideshow.
const FLOOR_AFFIX_POOL: Array[String] = [
	EliteModifier.QUICKENED, EliteModifier.INKED, EliteModifier.VOLATILE,
]

## Tags an authored FloorDef may carry. See FloorDef.special_tags.
const TAG_NO_ELITES: String = "no_elites"
const TAG_AFFIX: String = "aff:"          # authored pin, survives a FloorGen re-stamp
const TAG_GEN_AFFIX: String = "genaff:"   # generator-owned, stripped and re-stamped


# ------------------------------------------------------------------- the table
## Which affixes may ride this archetype at this depth. Never assumes non-empty —
## a shallow floor with an awkward archetype legitimately has nothing to give it,
## and the caller simply spawns an ordinary body.
static func eligible(depth: int, archetype: int) -> Array[String]:
	var out: Array[String] = []
	for aid: String in EliteModifier.eligible_ids(depth):
		var bad: Array = EXCLUDES.get(aid, [])
		if bad.has(archetype):
			continue
		out.append(aid)
	return out


# -------------------------------------------------------------------- the roll
## Pick the affixes for ONE elite. PURE: same (depth, seed, archetype) -> same answer
## on every machine, forever.
##
## Returns {"affixes": Array[String], "seed": int, "depth": int}.
static func roll(depth: int, seed_value: int, archetype: int) -> Dictionary:
	var d: int = maxi(depth, 1)
	var pool: Array[String] = eligible(d, archetype)
	var out: Array[String] = []
	if pool.is_empty():
		return {"affixes": out, "seed": seed_value, "depth": d}
	var rng := RandomNumberGenerator.new()
	# Mixed with depth AND archetype so two elites rolled a frame apart from adjacent
	# seeds do not come back as the same word twice.
	rng.seed = _mix(_mix(seed_value, d), archetype + 1)
	_shuffle(pool, rng)
	var want: int = mini(affix_count(d), pool.size())
	for i: int in want:
		out.append(pool[i])
	out.sort()   # stable order -> the word over its head reads the same on both phones
	return {"affixes": out, "seed": seed_value, "depth": d}


## Read a floor's affix pins out of `special_tags`. Both prefixes are honoured:
## `aff:` is an AUTHORED pin (FloorGen never strips it) and `genaff:` is the
## generator's own stamp (stripped and re-written every time it redraws the floor).
## Unknown ids are dropped rather than trusted.
static func parse_floor_affixes(tags: Array) -> Array[String]:
	var out: Array[String] = []
	for t in tags:
		var s: String = String(t)
		var id: String = ""
		if s.begins_with(TAG_AFFIX):
			id = s.substr(TAG_AFFIX.length())
		elif s.begins_with(TAG_GEN_AFFIX):
			id = s.substr(TAG_GEN_AFFIX.length())
		else:
			continue
		if EliteModifier.has(id) and not out.has(id):
			out.append(id)
	return out


static func elites_allowed(tags: Array) -> bool:
	for t in tags:
		if String(t) == TAG_NO_ELITES:
			return false
	return true


# ------------------------------------------------------------------- internals
## Fisher-Yates on the supplied rng. `Array.shuffle()` is NOT usable here: it draws
## from the engine's GLOBAL random stream, so it would ignore our seed entirely and
## quietly make `roll()` impure — the one property the whole co-op story rests on.
## (The same note is on BossRoster._shuffle and FloorGen's header. It keeps being
## worth writing because the mistake is invisible until two phones disagree.)
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## The shared 32-bit avalanche, lifted verbatim from BossRoster._mix / FloorGen._mix
## so every seeded roll in the tower behaves identically.
static func _mix(a: int, b: int) -> int:
	var h: int = (a ^ (b * 0x9E3779B1)) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	h = (h * 0x7FEB352D) & 0xFFFFFFFF
	h = (h ^ (h >> 15)) & 0xFFFFFFFF
	h = (h * 0x846CA68B) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFFFFFF
