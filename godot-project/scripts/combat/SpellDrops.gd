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
##   * When it does, `SIGNATURE_SHARE` (35%) of the time it is one of the six
##     authored Tier 2 SIGNATURES, and otherwise it is a spell from the CLASS
##     RESERVE — the real, tuned, role-tagged spells the classes author but do not
##     carry (`SpellLibrary.reserve_for_class`). Those are the common band: a
##     genuine upgrade, not an event.
##   * So a SPECIFIC Tier 2 signature is about 0.55 x 0.35 / 6 ≈ 3% per floor. You
##     will see Petrify roughly once every thirty floors. That is the intent.
##   * `SIGNATURE_MIN_FLOOR` keeps the two loudest (Meteor Storm, Mirror Image) off
##     the first two floors entirely, so a run does not open on its own climax.
##   * A guardian drops a Tier 3 `TIER3_BOSS_CHANCE` (50%) of the time. Half the
##     floors you clear, you get nothing, and that is what makes the other half
##     mean something.
##
## ══ WHY THE ROLL IS SEEDED AND NOT RANDOM ══════════════════════════════════════
## Co-op. Both peers build their own floor props from the same `LayoutDef` with no
## message passing, so an unseeded `randf()` would put a different spell in a
## different place on each screen — the worst kind of desync, because both players
## can see a pickup and disagree about what it is. Seeding on the floor number makes
## the roll a pure function of state both peers already share, and the whole problem
## disappears without a single packet. `_rng_for` is that seed.
##
## The consequence to know: the SAME floor number always rolls the SAME drop. That
## is a feature for a persistent climb (floor 7 has a Petrify on it, and the town
## can talk about floor 7) and it is why `SEED_SALT` exists — bump it and the whole
## tower re-rolls.

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
	"mirror_image": 3,
	"the_void": 1,        # Tier 3 gates are here too, for one place to look
}
## Change this to re-roll every floor in the tower.
const SEED_SALT: int = 0x5F3D

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
static func roll_boss_drop(floor_no: int) -> String:
	var rng: RandomNumberGenerator = _rng_for(floor_no, 2)
	if rng.randf() > TIER3_BOSS_CHANCE:
		return ""
	return _pick(rng, _eligible(SpellLibrary.build_tier3(), floor_no))


## THE COMMON BAND — every spell a class AUTHORS but does not carry, deduplicated
## across the roster. These are not filler: they are `rock_pillar`, `ice_wall`,
## `rift_dagger`, `creeping_shade` and friends, all fully tuned and all currently
## unreachable in play because `SLOT_ROLES` only carries three of each class's five
## roles. A previous agent reserved them for exactly this, and deriving the pool
## from `reserve_for_class` rather than hand-listing it is what stops the drop table
## drifting out of sync with the kits the way the class cards once did.
static func _common_pool() -> Array[String]:
	var out: Array[String] = []
	for cls: int in range(SpellLibrary.CLASS_KITS.size()):
		for s: SpellDef in SpellLibrary.reserve_for_class(cls):
			if not out.has(s.id):
				out.append(s.id)
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


## A generator seeded on the floor and a channel, so the floor roll and the boss
## roll are independent but both reproducible. `channel` exists so that changing
## whether a floor has a pickup does not also change what its guardian drops.
static func _rng_for(floor_no: int, channel: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(SEED_SALT, floor_no, channel))
	return rng


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
