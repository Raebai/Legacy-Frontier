class_name BossRoster
extends RefCounted
## WHICH BOSS STANDS ON WHICH FLOOR, AND WHAT RIDES ALONG WITH IT.
##
## ── THE SPEC, restated so the next reader does not have to go and find it ─────
## "Do not procedurally generate bosses. Fixed hand-built roster, randomised
##  selection, plus modifiers that change behaviour rather than numbers. Four
##  bosses with six modifiers reads as more variety than twenty generated ones, at
##  a tenth of the cost. HIGHER FLOORS ADD MODIFIERS, NOT HP."
##
## So this file is a TABLE and a DICE ROLL, and nothing else. Everything in it is
## static and pure: no tree, no autoloads, no side effects. `roll()` takes a depth
## and an integer seed and returns the same answer every time — which is the whole
## reason co-op works (see the CO-OP block below).
##
## ── HOW CO-OP STAYS HONEST ───────────────────────────────────────────────────
## The dangerous shape here is "both phones roll their own boss". They would
## disagree, and the two players would fight different fights in the same room.
##
## The fix is NOT a shared random seed — that would need new networking, and the
## RNG streams would still have to stay in lockstep forever after. The fix is that
## THE ROLL HAPPENS ONCE, ON THE HOST, AND THE RESULT TRAVELS:
##
##   Encounter._begin_boss()   host only (clients return early in run_floor)
##     -> BossRoster.roll(depth, randi())        -> {"boss": id, "mods": [...]}
##     -> Encounter.spawn_boss(...)              -> puts `bid` + `mods` in the dict
##     -> MultiplayerSpawner replicates the dict verbatim
##     -> Encounter.build_enemy_from_data(data)  runs on EVERY peer, reads `bid`
##
## `build_enemy_from_data` therefore stays what tools/slice_test_coop.gd locks it
## as: pure construction from a dictionary, byte-identical on every peer, with no
## randomness of its own. The seed is carried in the dict too (`bseed`) — unused by
## construction, but it means a capture tool or a bug report can replay the exact
## fight.
##
## ── ADDING A BOSS ────────────────────────────────────────────────────────────
## Append a row to ENTRIES. Nothing else in the game needs to change: Encounter
## picks the scene by id, the floor window controls where it appears, and the three
## scalars below shape it WITHOUT touching the depth curve.

## The roster. `id` is what travels in spawn data — never renumber, never rename.
const GUARDIAN: String = "guardian"
const SCRIBBLE: String = "scribble"
const CARTOGRAPHER: String = "cartographer"
const ILLUMINATOR: String = "illuminator"
const ERASER: String = "eraser"
const ETCHER: String = "etcher"

## THE ROSTER. One row per boss.
##
##   min_floor / max_floor — the depth window this artist draws in. max_floor 0
##       means "no ceiling". This is the ESCALATION-AS-ARTISTIC-SKILL ladder from
##       the lore: the crude scribble is a shallow-page thing and stops appearing;
##       the illuminator only shows up once the tower can draw properly.
##   hp_scale   — per-boss SHAPE, not per-floor difficulty. A scribble is a short
##       violent fight and a master illuminator is a long one; that is identity.
##       The DEPTH curve lives entirely in FloorDef.boss_hp_multiplier and is not
##       touched here. Do not smuggle difficulty in through this column.
##   speed_scale — how fast the body moves, relative to Encounter.BOSS_MOVE_SPEED.
##   flies       — WHETHER THIS ARTIST'S BODY TOUCHES THE FLOOR AT ALL. See the
##       FLIGHT block below; it is an identity column like `artist`, not a dial.
##
## ── WHICH ARTISTS FLY, AND WHY IT IS DECIDED HERE ────────────────────────────
## Maker: *"make some of them able to fly for example"*. The complaint underneath it
## is a SAFE SPOT — a hero on a third-tier ledge that the guardian below can neither
## reach nor threaten. `Boss` answers that for the grounded half by fixing its leap;
## flight is the answer for the half whose fiction supports it.
##
## The choice is per ARTIST and it is made from the fiction, not from difficulty:
##   ILLUMINATOR — gold leaf on vellum, a cleric silhouette that gilds the page from
##       above. A seraph that has to walk is the wrong drawing. FLIES.
##   CARTOGRAPHER — it surveys the room and rules lines across it. A surveyor takes
##       the bearing from ABOVE the ground it is mapping. FLIES.
##   GUARDIAN — a stone colossus. Its weight IS the read; it answers height by
##       LEAPING, which is the verb its body already owns. Grounded.
##   SCRIBBLE — its verb is the dash. A flying scribble is a different fight, not a
##       better one. Grounded.
##   ERASER — it denies ground by standing on it. Grounded.
##   ETCHER — its whole fight is a breakable wind-up the player must reach. A flying
##       Etcher would put its own break out of reach, which is a WORSE fight, not a
##       harder one. Grounded.
##
## ⚠ IT LIVES ON THE ROSTER RATHER THAN AS A VIRTUAL ON EACH BOSS SCRIPT so that the
## question "which bosses fly?" has ONE answer a reader can see in one place, next to
## the other five identity columns. `Boss.boss_flies()` reads it and any subclass may
## still override that virtual if it ever needs to fly conditionally.
const ENTRIES: Array[Dictionary] = [
	{
		"id": SCRIBBLE,
		"scene": "res://scenes/combat/ScribbleBoss.tscn",
		"name": "THE SCRIBBLE",
		"artist": "a child, blunt pencil, lined paper",
		"min_floor": 1, "max_floor": 3,
		"hp_scale": 0.66, "speed_scale": 2.05,
		"flies": false,
	},
	{
		"id": GUARDIAN,
		"scene": "res://scenes/combat/Boss.tscn",
		"name": "THE ASHSPIRE GUARDIAN",
		"artist": "charcoal on stone",
		"min_floor": 1, "max_floor": 0,
		"hp_scale": 1.0, "speed_scale": 1.0,
		"flies": false,
	},
	{
		"id": CARTOGRAPHER,
		"scene": "res://scenes/combat/CartographerBoss.tscn",
		"name": "THE CARTOGRAPHER",
		"artist": "compass and ruler, ink on graph paper",
		"min_floor": 2, "max_floor": 0,
		"hp_scale": 0.88, "speed_scale": 0.62,
		"flies": true,
	},
	{
		"id": ILLUMINATOR,
		"scene": "res://scenes/combat/IlluminatorBoss.tscn",
		"name": "THE ILLUMINATOR",
		"artist": "gold leaf on vellum, and it wants you dead",
		"min_floor": 4, "max_floor": 0,
		"hp_scale": 1.12, "speed_scale": 0.86,
		"flies": true,
	},
	# ── APPENDED, AND THAT MATTERS ───────────────────────────────────────────
	# `entry()` falls back to `ENTRIES[1]` BY INDEX, so the Guardian has to stay at
	# index 1 forever: inserting a row above it would silently change what an
	# unknown boss id degrades to, with nothing anywhere reporting a fault.
	#
	# WHY THESE TWO EXIST. Measured over 200 climbs before they were written: the
	# eligible pool for floors 4-10 was THREE (the Scribble's window closes at 3 and
	# nothing replaced it), a 10-floor climb saw ~3.7 of 4 artists, and the Guardian
	# turned up ~3.3 times per climb and as many as 8. The modifiers re-skin a
	# repeat, but the QUESTION the fight asks repeats with it.
	{
		"id": ERASER,
		"scene": "res://scenes/combat/EraserBoss.tscn",
		"name": "THE ERASER",
		"artist": "worn rubber, and pink crumbs on the floor",
		# Shallow: it takes the page back, and by the deep half the pages are worth
		# keeping. Also the shallow band was the one with three artists in it.
		"min_floor": 1, "max_floor": 6,
		# Tanky and slow. It denies ground rather than chasing, and a fast body would
		# turn "walk into the pocket" into "get hit on the way in".
		"hp_scale": 0.94, "speed_scale": 0.80,
	},
	{
		"id": ETCHER,
		"scene": "res://scenes/combat/EtcherBoss.tscn",
		"name": "THE ETCHER",
		"artist": "needle and acid, on beaten copper",
		# Deep: it is the boss that fixes the deep pool, and its whole fight is a
		# breakable cast, which needs a player who already has damage to land.
		"min_floor": 3, "max_floor": 0,
		# The slowest body on the roster. The break has to be REACHABLE.
		"hp_scale": 1.05, "speed_scale": 0.55,
		"flies": false,
	},
]

## Hard ceiling on how many modifiers may ride one boss. Four behavioural rewrites
## at once is already at the edge of readable on a 640x360 phone screen; a fifth
## would be noise, and noise is indistinguishable from unfairness.
const MAX_MODIFIERS: int = 4

## Tag prefixes an authored FloorDef may use to override the roll. See
## FloorDef.special_tags.
const TAG_BOSS: String = "boss:"
const TAG_MOD: String = "mod:"
const TAG_NO_MODS: String = "no_mods"


# ------------------------------------------------------------------- the table
static func entry(id: String) -> Dictionary:
	for e: Dictionary in ENTRIES:
		if String(e["id"]) == id:
			return e
	return ENTRIES[1]   # the Ashen Guardian is the fallback: it always existed


static func has(id: String) -> bool:
	for e: Dictionary in ENTRIES:
		if String(e["id"]) == id:
			return true
	return false


static func ids() -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in ENTRIES:
		out.append(String(e["id"]))
	return out


static func scene_path(id: String) -> String:
	return String(entry(id)["scene"])


static func display_name(id: String) -> String:
	return String(entry(id)["name"])


static func hp_scale(id: String) -> float:
	return float(entry(id)["hp_scale"])


static func speed_scale(id: String) -> float:
	return float(entry(id)["speed_scale"])


## Does this artist's body leave the floor for the whole fight? See the FLIGHT block
## above ENTRIES for who does and why. `get` with a default rather than a bare index
## so a row written before this column existed degrades to "grounded" instead of
## aborting the caller — a missing key is a runtime error in GDScript, and this is
## read from inside a boss's physics loop.
static func flies(id: String) -> bool:
	return bool(entry(id).get("flies", false))


## The same question asked by DISPLAY NAME instead of by id.
##
## ⚠ WHY THIS EXISTS AT ALL. A live `Boss` node does not know its own roster id —
## `Encounter.build_enemy_from_data` reads `bid` to pick the SCENE and then never
## tells the body which row built it. The one identity every boss does carry is
## `boss_title()`, which is a virtual per class and is already required to equal this
## table's `name` column (that is what `BossBar.setup` renders). So the title is the
## join key, and this is the join.
##
## Unknown titles answer `false` — a boss built outside the roster (a harness stub, a
## capture tool's hand-made body) stays grounded, which is the behaviour that shipped.
static func flies_for_title(title: String) -> bool:
	for e: Dictionary in ENTRIES:
		if String(e["name"]) == title:
			return bool(e.get("flies", false))
	return false


## Which artists draw at this depth. Never empty — the Guardian has no ceiling, so
## there is always at least one legal answer however deep the tower gets.
static func eligible(depth: int) -> Array[String]:
	var d: int = maxi(depth, 1)
	var out: Array[String] = []
	for e: Dictionary in ENTRIES:
		var lo: int = int(e["min_floor"])
		var hi: int = int(e["max_floor"])
		if d < lo:
			continue
		if hi > 0 and d > hi:
			continue
		out.append(String(e["id"]))
	if out.is_empty():
		out.append(GUARDIAN)
	return out


## HOW MANY MODIFIERS A FLOOR'S GUARDIAN CARRIES. **The only depth-difficulty dial
## in this file, and it is deliberately the only one.** Floor 1 is clean so the
## first boss a player ever meets is the boss and nothing else; after that it grows
## one per two floors and stops at MAX_MODIFIERS.
##
##   floor: 1  2  3  4  5  6  7  8+
##   mods:  0  1  1  2  2  3  3  4
##
## Note what is NOT here: an HP curve, a damage curve, a speed curve. A previous
## pass pinned trash `hp_multiplier` at 1.0 on every floor for exactly this reason
## and moved the guardian's own curve onto `FloorDef.boss_hp_multiplier`; this
## function is the replacement for what that curve used to be asked to do.
static func modifier_count(depth: int) -> int:
	return clampi(maxi(depth, 0) / 2, 0, MAX_MODIFIERS)


# -------------------------------------------------------------------- the roll
## Pick this floor's boss and its modifiers. PURE: same (depth, seed) -> same
## answer, on every machine, forever. `forced_boss` / `forced_mods` come from the
## floor's special_tags and win over the roll.
##
## Returns {"boss": String, "mods": Array[String], "seed": int, "depth": int}.
static func roll(
	depth: int, seed_value: int,
	forced_boss: String = "", forced_mods: Array = [], allow_mods: bool = true
) -> Dictionary:
	var d: int = maxi(depth, 0)
	var rng := RandomNumberGenerator.new()
	# Mixed with the depth so two adjacent floors handed the same run seed do not
	# produce the same fight twice in a row.
	rng.seed = _mix(seed_value, d)

	var boss_id: String = forced_boss
	if boss_id == "" or not has(boss_id):
		var pool: Array[String] = eligible(d)
		boss_id = pool[rng.randi_range(0, pool.size() - 1)]

	var mods: Array[String] = []
	for m in forced_mods:
		var mid: String = String(m)
		if BossModifier.has(mid) and not mods.has(mid):
			mods.append(mid)
	if allow_mods:
		var want: int = modifier_count(d)
		var pool_m: Array[String] = BossModifier.eligible_ids(d)
		# Drop anything already forced so a pinned modifier cannot be drawn twice.
		var avail: Array[String] = []
		for m2: String in pool_m:
			if not mods.has(m2):
				avail.append(m2)
		_shuffle(avail, rng)
		while mods.size() < want and not avail.is_empty():
			mods.append(avail.pop_back())
	mods.sort()   # stable order -> the HUD reads the same on both phones
	return {"boss": boss_id, "mods": mods, "seed": seed_value, "depth": d}


## Read the boss/modifier overrides out of a floor's `special_tags`.
## Returns {"boss": String, "mods": Array[String], "allow_mods": bool}.
static func parse_tags(tags: Array) -> Dictionary:
	var boss_id: String = ""
	var mods: Array[String] = []
	var allow: bool = true
	for t in tags:
		var s: String = String(t)
		if s == TAG_NO_MODS:
			allow = false
		elif s.begins_with(TAG_BOSS):
			var b: String = s.substr(TAG_BOSS.length())
			if has(b):
				boss_id = b
		elif s.begins_with(TAG_MOD):
			var m: String = s.substr(TAG_MOD.length())
			if BossModifier.has(m) and not mods.has(m):
				mods.append(m)
	return {"boss": boss_id, "mods": mods, "allow_mods": allow}


# ------------------------------------------------------------------- internals
## Fisher-Yates on the supplied rng. `Array.shuffle()` is NOT usable here: it draws
## from the engine's GLOBAL random stream, so it would ignore our seed entirely and
## quietly make `roll()` impure — the one property the whole co-op story rests on.
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Cheap 32-bit avalanche so adjacent depths land in unrelated parts of the stream.
## Masked to 32 bits at every step: GDScript ints are 64-bit and an unmasked
## multiply would drift away from the intended mixing.
static func _mix(a: int, b: int) -> int:
	var h: int = (a ^ (b * 0x9E3779B1)) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	h = (h * 0x7FEB352D) & 0xFFFFFFFF
	h = (h ^ (h >> 15)) & 0xFFFFFFFF
	h = (h * 0x846CA68B) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFFFFFF
