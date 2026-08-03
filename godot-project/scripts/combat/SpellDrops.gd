class_name SpellDrops
extends RefCounted
## THE DROP TABLE — what appears on a floor, how often, and where.
##
## ══ RARITY IS THE BALANCE SYSTEM ═══════════════════════════════════════════════
## This file is the balance system. Not the damage numbers in `SpellLibrary`, not
## the cooldowns, not the clash weights — the odds in here.
##
## The spec is explicit and it is the right call: "Do not tune the big spells to be
## fair. Make them scarce." A Tier 2 that shows up every floor stops being an event
## and becomes part of your kit, at which point it has to be balanced like a kit
## spell, at which point it is not worth picking up. The loudness IS the design, and
## the only honest way to keep something loud is to make it rare. So the tuning
## lever for "Meteor Storm feels too strong" is `SIGNATURE_SHARE` or a floor gate,
## NOT the meteor count — and the same applies to every spell in the drop set.
##
## ══ WHAT THE ODDS ACTUALLY ARE ═════════════════════════════════════════════════
## Every number here is an UNTESTED GUESS in the house sense — reasoned, not felt —
## and they are all in one place precisely so the maker can move them after a
## playtest without reading a single spell file.
##
##   * A floor has a Tier 2 pickup `TIER2_FLOOR_CHANCE` (55%) of the time.
##   * When it does, `SIGNATURE_SHARE` (35%) of the time it is one of the five
##     authored Tier 2 SIGNATURES, and otherwise it is a spell from the COMMON BAND —
##     the real, tuned, role-tagged spells the classes author but do not carry
##     (`SpellLibrary.reserve_for_class`) PLUS the ones no class authors at all any
##     more (`SpellLibrary.unequipped_ids`, the anti-recolour pass's displaced beams
##     and bombardments). A genuine upgrade, not an event.
##   * So a SPECIFIC Tier 2 signature is about 0.55 x 0.35 / 5 ≈ 4% per floor. You
##     will see Petrify roughly once every twenty-five floors. That is the intent.
##   * `SIGNATURE_MIN_FLOOR` keeps the loudest (Meteor Storm) off the first two
##     floors entirely, so a run does not open on its own climax. Mirror Image used
##     to be gated with it and is no longer a drop at all — it is the Arcanist's
##     control slot now.
##   * A guardian drops a Tier 3 `TIER3_BOSS_CHANCE` (50%) of the time. Half the
##     floors you clear, you get nothing, and that is what makes the other half
##     mean something.
##
## ══ WHY THE ROLL IS SEEDED AND NOT RANDOM ══════════════════════════════════════
## Co-op. Both peers build their own floor props from the same `LayoutDef` with no
## message passing, so an unseeded `randf()` would put a different spell in a
## different place on each screen — the worst kind of desync, because both players
## can see a pickup and disagree about what it is. Seeding makes the roll a pure
## function of state both peers already share, and the whole problem disappears
## without a single packet. `_rng_for` is that seed.
##
## ══ ...AND WHY THE SEED IS NOT JUST THE FLOOR NUMBER ANY MORE ══════════════════
## It used to be `hash(Vector3i(SEED_SALT, floor_no, channel))` and nothing else,
## with `SEED_SALT` a compile-time constant. The fun audit named the consequence:
## EVERY CLIMB ROLLED THE IDENTICAL DROPS ON THE IDENTICAL FLOORS, FOREVER. Combined
## with a five-floor tower, most of the six Tier 2 signatures were not rare — they
## were unreachable, and the two or three that did land landed every single run. A
## scarcity dial wound that tight stops being a balance system and becomes a
## content-deletion system.
##
## So the CLIMB now goes into the seed alongside the floor, and it comes from
## `FloorGen` rather than from a second scheme of this file's own invention.
## `FloorGen.apply()` runs once per climb out of `GameState._load_or_build_tower`
## and records the seed it drew the tower with; reading that same number means the
## ROOM and the LOOT are two expressions of one climb, and a party that agrees about
## one necessarily agrees about the other. `resolve_climb_seed()` is that read, and
## it inherits FloorGen's co-op policy whole — including the honest limitation that
## a live co-op session PINS the seed to 0, so two phones re-roll the tower together
## or not at all. See the header of `FloorGen.gd`.
##
## What is unchanged: within ONE climb the same floor still rolls the same drop
## every time it is asked, which is what lets both peers build the floor with no
## packet and what `tools/slice_test_drops.gd` pins. `SEED_SALT` still re-rolls the
## whole tower when bumped.

# ------------------------------------------------------------------ SOUND SEAM
## ⚠ WHY EVERY DROP-ECONOMY FILE PLAYS SOUND THROUGH HERE INSTEAD OF SAYING `Sfx`.
##
## `Sfx` is an AUTOLOAD and nothing else — `Sfx.gd` declares no `class_name`. So the
## bare identifier only resolves once the autoload is registered, and a `--script`
## harness never registers any. That is not a runtime warning: naming `Sfx` anywhere
## in a file makes the WHOLE FILE fail to compile under a test harness, and a
## `class_name` script that failed to compile still resolves to a GDScript object
## with none of its members on it. The symptom is "Nonexistent function
## 'mean_fraction' in base 'GDScript'" pointing at a function that is plainly there.
##
## This suite found that the expensive way. Four of the ten drop spells were
## unreachable from their own tests until the identifier came out of them.
##
## Same shape as `SpellDeflect._sfx`, which is the house precedent. A missing
## autoload here is silence, which is the correct degradation for a test harness.
static func sfx(name: String, db: float = 0.0, pitch_var: float = 0.0,
		pitch: float = 1.0) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var node: Node = tree.root.get_node_or_null(^"/root/Sfx")
	if node != null and node.has_method(&"play"):
		node.call(&"play", name, db, pitch_var, pitch)


## Odds. All UNTESTED GUESSES; this is the tuning surface.
const TIER2_FLOOR_CHANCE: float = 0.55
const SIGNATURE_SHARE: float = 0.35
const TIER3_BOSS_CHANCE: float = 0.5
## Floor before which a signature drop is re-rolled into the common band. Keyed by
## id; anything absent is available from floor 1.
const SIGNATURE_MIN_FLOOR: Dictionary = {
	"meteor_storm": 3,
	# `mirror_image` used to be gated here too. It is not a drop any more — the
	# anti-recolour pass promoted it into the Arcanist's control slot (see
	# `SpellLibrary.CLASS_KITS`) — so the key would gate an id nothing can roll. A
	# dead key here is not harmless bookkeeping: `_eligible` reads it by id, so a
	# stale entry silently claims to be protecting something.
	# THE VOID — a 260-damage ULT-weight nuke — used to sit at 1, i.e. no depth gate
	# at all, which made it obtainable from the floor-1 mini-guardian: a boss with
	# 190-288 HP handing you a thing that deletes 260. A Tier 3 is supposed to be the
	# reward for getting DEEP, and the two loudest Tier 2s are already held off the
	# first two floors for exactly this reason.
	"the_void": 4,
}
## Change this to re-roll every floor in the tower.
const SEED_SALT: int = 0x5F3D

## THE CLIMB. 0 = "not told", in which case the seed is taken from `FloorGen` — see
## `resolve_climb_seed()`. A plain static, like `FloorGen.climb_seed`, so a headless
## test and a capture tool can drive it the same way.
static var climb_seed: int = 0

## Where a floor's spell pickup is placed when the layout does not say. Fractions
## of the room, so it scales with `LayoutDef.room_size` instead of being a magic
## pixel coordinate that lands inside a wall on a small floor.
##
## DELIBERATELY NOT THE MIDDLE, and deliberately not next to the hero start. The
## spec wants pickups "visible and contested — both players can race for them", and
## a pickup on top of you is not a race. This puts it across the room and high, so
## going for it costs you position.
const DROP_ANCHOR: Vector2 = Vector2(0.72, 0.42)
## Where a boss drop lands: dead centre, where the guardian died. Nobody races for
## this one — the fight is over — so the only thing that matters is that it is
## impossible to miss.
const BOSS_ANCHOR: Vector2 = Vector2(0.5, 0.55)


## The Tier 2 spell id this floor carries, or "" for none.
static func roll_floor_drop(floor_no: int) -> String:
	var rng: RandomNumberGenerator = _rng_for(floor_no, 1)
	if rng.randf() > TIER2_FLOOR_CHANCE:
		return ""
	if rng.randf() <= SIGNATURE_SHARE:
		var sig: String = _pick(rng, _eligible(SpellLibrary.build_tier2(), floor_no))
		if sig != "":
			return sig
	return _pick(rng, _common_pool())


## The Tier 3 spell id this floor's guardian drops, or "" for none.
##
## THE LAST GUARDIAN ALWAYS PAYS. Everywhere else the 50% is the point — half the
## floors you clear you get nothing, and that is what makes the other half mean
## something. The tower's FINAL guardian is the one fight where that coin flip is
## indefensible: the audit measured floor 5's boss as ~23 seconds with no reward
## event in it at all, terminated by a 50/50 on whether the climactic fight of the
## whole climb pays out anything. It now always does.
static func roll_boss_drop(floor_no: int) -> String:
	var rng: RandomNumberGenerator = _rng_for(floor_no, 2)
	if rng.randf() > TIER3_BOSS_CHANCE and not is_final_floor(floor_no):
		return ""
	return _pick(rng, _eligible(SpellLibrary.build_tier3(), floor_no))


## Is this the tower's LAST floor? Asked of GameState through a guarded tree lookup
## rather than passed in, because the one caller (`BossDropWatcher`) is owned
## elsewhere and this needs no argument it cannot already find. Same reason and same
## shape as `sfx()` above; a harness with no GameState answers "no", which leaves
## every existing headless expectation exactly as it was.
static func is_final_floor(floor_no: int) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var gs: Node = tree.root.get_node_or_null(^"GameState")
	if gs == null or not gs.has_method(&"total_floors"):
		return false
	var total: int = int(gs.call(&"total_floors"))
	# EQUALITY, NOT `>=`. There is no floor past the last one — `GameState` clamps
	# the climb to `total_floors()` — so a `>=` here does not describe a deeper
	# tower, it just hands the guarantee to every hypothetical floor number anyone
	# ever asks about. (Which is exactly what it did: `slice_test_drops` sweeps 200
	# floor numbers to measure the 50% boss-drop rate and measured 0.99.)
	return total > 0 and floor_no == total


## THE COMMON BAND — every spell a class AUTHORS but does not carry, deduplicated
## across the roster. These are not filler: they are `rock_pillar`, `ice_wall`,
## `rift_dagger`, `creeping_shade` and friends, all fully tuned and all currently
## unreachable in play because `SLOT_ROLES` only carries three of each class's five
## roles. A previous agent reserved them for exactly this, and deriving the pool
## from `reserve_for_class` rather than hand-listing it is what stops the drop table
## drifting out of sync with the kits the way the class cards once did.
##
## ⚠ IT HAS A SECOND SOURCE NOW, AND THE REASON IS THE SAME REASON. The anti-recolour
## pass displaced seven fully-tuned spells out of `CLASS_KITS` altogether —
## `frostpiercer`, `infernal_lance`, `umbral_lance`, `tempest` (four of the five
## beams), `colossus_pillar`, `rune_orbs` and `void_barrage` — because five classes
## throwing one beam and four throwing one bombardment was the thing the maker ruled
## against. A spell in no kit is reachable through `reserve_for_class` only if some
## class still AUTHORS it, and these are authored by nobody, so without this union
## they would be deleted content that still costs a file. `SpellLibrary.unequipped_ids`
## derives them (and picks up `judgment` and `avalanche`, which had already gone
## orphan before this pass and which nobody had noticed).
##
## They land in the COMMON band and not among the `build_tier2()` signatures on
## purpose: the signature shelf carries balance invariants a displaced class ULT
## would break outright ("at most two Tier 2s are ULT-shelf", "every drop has a
## >= 0.35 s wind-up" — `rune_orbs` has no wind-up at all). The common band is where
## "a genuine upgrade, not an event" already lives, which is exactly what a real
## class spell you did not start with is.
static func _common_pool() -> Array[String]:
	var out: Array[String] = []
	for cls: int in range(SpellLibrary.CLASS_KITS.size()):
		for s: SpellDef in SpellLibrary.reserve_for_class(cls):
			if not out.has(s.id):
				out.append(s.id)
	for id: String in SpellLibrary.unequipped_ids():
		if not out.has(id):
			out.append(id)
	out.sort()   # deterministic across peers; group order is not guaranteed to be
	return out


## Ids from `pool` that this floor is deep enough for.
static func _eligible(pool: Array, floor_no: int) -> Array[String]:
	var out: Array[String] = []
	for s: SpellDef in pool:
		if floor_no >= int(SIGNATURE_MIN_FLOOR.get(s.id, 1)):
			out.append(s.id)
	return out


static func _pick(rng: RandomNumberGenerator, ids: Array[String]) -> String:
	if ids.is_empty():
		return ""
	return ids[rng.randi() % ids.size()]


## THE CLIMB SEED, under FloorGen's policy rather than a second one of our own:
##   1. an explicit `SpellDrops.climb_seed` -> use it (tests, capture tools).
##   2. `FloorGen.climb_seed`               -> the hook a future host broadcast sets.
##   3. `FloorGen.last_seed`                -> the seed this climb's tower was ACTUALLY
##      drawn with, recorded by `FloorGen.apply()` once per run. This is the normal
##      path, and it is why the room and the loot vary together.
##
## Case 3 answers 0 in exactly two situations, both of which are correct: a live
## co-op session (FloorGen deliberately PINS to 0 so two phones cannot disagree) and
## a harness that never built a tower. 0 reproduces the pre-climb-seed behaviour
## byte for byte, so neither case is a special case.
##
## ⚠ THERE IS NO `randi()` ANYWHERE IN THIS PATH AND THERE MUST NEVER BE. An
## unseeded roll here puts a different spell on each screen, and the players can SEE
## the pickup — it would read as a mystery bug, not as a desync.
static func resolve_climb_seed() -> int:
	if climb_seed != 0:
		return climb_seed
	if FloorGen.climb_seed != 0:
		return FloorGen.climb_seed
	return FloorGen.last_seed


## A generator seeded on the climb, the floor and a channel, so the floor roll and
## the boss roll are independent but both reproducible. `channel` exists so that
## changing whether a floor has a pickup does not also change what its guardian
## drops; the climb is mixed in FIRST, through the same avalanche `FloorGen` uses,
## so two adjacent climbs land in unrelated parts of the stream instead of drawing
## near-identical towers.
static func _rng_for(floor_no: int, channel: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(_salt_for_climb(), floor_no, channel))
	return rng


## SEED_SALT mixed with this climb's seed. Kept separate from `_rng_for` so a test
## can assert that two climbs salt differently without rolling a whole tower.
static func _salt_for_climb() -> int:
	var s: int = resolve_climb_seed()
	if s == 0:
		return SEED_SALT
	return FloorGen.mix_seed(SEED_SALT, s)


## Any spell id resolved to a SpellDef — drops first, then the whole library, so
## the common band (which lives in `build_all`, not in the drop list) resolves too.
static func spell_for_id(id: String) -> SpellDef:
	if id == "":
		return null
	var drop: SpellDef = SpellLibrary.drop_by_id(id)
	if drop != null:
		return drop
	for s: SpellDef in SpellLibrary.build_all():
		if s.id == id:
			return s
	return null


## Which shelf a drop id belongs to, for the pickup's colour and label. Derived
## from the spell rather than from a second table, so a spell cannot be a Tier 3 in
## one place and a Tier 2 in another.
static func is_tier3(id: String) -> bool:
	var s: SpellDef = spell_for_id(id)
	return s != null and s.kind == SpellDef.Kind.CATACLYSM
