class_name SpellDrops
extends RefCounted
## THE DROP TABLE — what appears on a floor, how often, and where.
##
## ══ ⚠ READ THIS FIRST: THE TOWER DROPS NO SPELLS ANY MORE (2026-08-04) ══════════
## Maker's ruling, verbatim, from a live playtest: "you shouldn't be able to find
## spells in the tower so remove that blizzard and any other spells that are there,
## and the healing and stuff should be harder to find."
##
## So `TOWER_SPELL_DROPS` is false and BOTH rolls below return "" before they touch a
## table. Every word of the rarity essay that follows is still TRUE OF THE TABLE and
## still describes what happens the moment that constant is flipped back — which is
## exactly why the tables were left standing rather than emptied:
##
##   * `SpellLibrary.build_tier2()` / `build_tier3()` / `unequipped_ids()` are read by
##     four suites, by the audit sandbox and by the "no drop is ever in a starting
##     kit" guard. Deleting entries would have broken all of them to express a
##     decision that one boolean expresses better.
##   * This is ONE RULING, not a design deletion. The maker may want drops back, and
##     bringing them back must not be an archaeology exercise.
##
## What became inert in the tower as a result — named here rather than deleted, for
## the same reason: `SpellPickup` (the pickup entity), `SpellGrant`'s displace /
## restore / charge ledger, the charge pips `AbilityBar` and `LoadoutBar` draw, the
## Tier-3 "charges expire back into your class ult" path, `SpellHandoff` (the pad
## that lets one player pass a find to the other), and `BossDropWatcher`'s whole
## reason for existing. All still compile, still tested, still reachable from
## `tools/drop_capture.gd` and `tools/director/Director.gd`.
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


## ══════════════════════════════════════════════════════ THE RULING, AS ONE SWITCH
## Can a spell be FOUND in the tower at all? The maker says no (2026-08-04 playtest);
## see the header. One constant, guarding the two rolls, because the alternative was
## nine deletions across a file this agent does not own.
##
## ⚠ THIS IS THE ONLY THING TO FLIP TO GIVE DROPS BACK. Nothing downstream was
## deleted: flip this to `true` and the floor pickup, the guardian drop, the pickup
## entity, the handoff pad and the charge ledger all come back exactly as they were.
const TOWER_SPELL_DROPS: bool = false

## ⚠ TEST-ONLY, AND IT IS NOT A GAME PATH. The drop TABLE — the odds, the floor
## gates, the climb seeding, the common band — is still worth guarding: it is what
## comes back when `TOWER_SPELL_DROPS` flips, and a table that rotted while it was
## switched off would come back broken. So the suites that measure the table open
## this hatch, roll, and the game never touches it.
##
## A static var and not a parameter on purpose: the two roll functions are called from
## `FloorBuilder` and `BossDropWatcher`, which this agent does not own, so their
## signatures cannot move. Same shape and same reason as `climb_seed` below.
static var allow_drops_for_test: bool = false

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


## Is the drop system allowed to produce a spell at all? The maker's ruling, asked
## once, in one place, so both rolls answer it identically and a future reader finds
## a DECISION rather than two suspiciously dead functions.
static func drops_are_findable() -> bool:
	return TOWER_SPELL_DROPS or allow_drops_for_test


## The Tier 2 spell id this floor carries, or "" for none.
##
## ⚠ THE GUARD IS AT THE TOP, BEFORE THE RNG IS EVEN DRAWN. Not because it is faster
## — because the roll has to be untouched underneath it. Emptying the table or
## short-circuiting halfway through would leave the odds, the floor gates and the
## climb seeding in a state nobody could reason about when drops come back.
static func roll_floor_drop(floor_no: int) -> String:
	if not drops_are_findable():
		return ""
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
##
## ⚠ ...AND THE RULING OUTRANKS EVEN THAT. "The last guardian always pays" is a rule
## about WHICH floors pay when spells drop; it is not a licence for one spell to
## survive a ruling that says none of them do. The final guardian pays nothing while
## `TOWER_SPELL_DROPS` is false, and pays every time the moment it is true.
static func roll_boss_drop(floor_no: int) -> String:
	if not drops_are_findable():
		return ""
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


# ────────────────────────────────────────────────────────────────── HEALTH PACKS
## Does the health-pack site `site` on floor `floor_no` actually carry a pack?
##
## ══ THE RULING ═════════════════════════════════════════════════════════════════
## Maker, same playtest, same sentence: "the healing and stuff should be harder to
## find." Not "gone" — harder to find. So the sites stay, the fallback stays, the
## heal stays; what changes is whether a site pays out.
##
## ══ THE BEFORE AND AFTER, EXPLICITLY ═══════════════════════════════════════════
## BEFORE: there was NO ROLL ANYWHERE in the health path.
## `FloorBuilder.DEFAULT_HEALTH_PACKS` is two room-fractions, no authoring table
## fills `LayoutDef.health_pickups`, so the fallback was the live path and every
## floor got BOTH packs, every time:            2.00 packs per floor, 100% of floors.
## AFTER: each of the two sites rolls independently at `HEALTH_PACK_CHANCE` = 0.25:
##                                              0.50 packs per floor  (a 4x cut)
##   * 56% of floors carry NO healing at all   (0.75^2)
##   * 38% carry exactly ONE, across the room from wherever the fight is
##   *  6% carry both
##
## ══ WHY 0.25 AND NOT 0.5, DEFENDED ═════════════════════════════════════════════
## The packs arrived inside a difficulty pass that moved FIVE levers at once — hero
## HP x1.4, enemy damage -25%/-40%, enemy speed -15%, floor 1 -36% bodies, and these.
## The maker has since said the game got too easy in places. Of those five, the packs
## are the only one that adds a RECOVERY RESOURCE, and guaranteed per-floor recovery
## is what flattens attrition across a whole climb: it does not make one floor easier,
## it makes floor 7 start at the same health as floor 1. That is the specific thing
## being taken back.
##
## 0.25 is chosen so the MODAL FLOOR HAS NO HEALING (56%) — attrition is a real
## pressure again and arriving at a guardian hurt is once more a consequence — while a
## ten-floor climb still expects ~5 packs, so a long climb is not a slow death
## sentence. It is one constant, and it is the first number to turn if a playtest says
## the swing went too far: 0.35 gives 0.70 packs/floor and healing on 58% of floors.
##
## ⚠ NOTHING RANDOM, FOR THE SAME REASON AS THE SPELL ROLL. Both peers build their own
## props from the same `LayoutDef` with no message passing, and a pickup's wire
## identity is its POSITION (`Net.pos_key`). An unseeded roll here would leave a pack
## standing on one phone and absent on the other. Seeded on the climb + the floor +
## the site, so it is a pure function of state both peers already share.
const HEALTH_PACK_CHANCE: float = 0.25

static func roll_health_pack(floor_no: int, site: int) -> bool:
	# Channel `3 + site`, so pack sites can never collide with the floor drop's
	# channel 1 or the boss drop's channel 2 — and so two sites on ONE floor decide
	# separately instead of both taking the same coin flip.
	var rng: RandomNumberGenerator = _rng_for(floor_no, 3 + maxi(0, site))
	return rng.randf() <= HEALTH_PACK_CHANCE


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
