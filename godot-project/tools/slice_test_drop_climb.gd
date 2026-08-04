# Run: godot --headless --path godot-project --script tools/slice_test_drop_climb.gd
#
# THE CLIMB SEED IN THE DROP TABLE. `tools/slice_test_drops.gd` pins the odds, the
# gates and the within-a-climb determinism; this pins the thing that changed on
# 2026-08-01 — that two CLIMBS roll different loot while two PEERS never do.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read is NOT a failure in GDScript: it logs, ABORTS the enclosing
# function, and hands back the return type's zero value. So failures accumulate on
# the MEMBER `_fails` (an abort cannot discard them) and every test records a
# completion sentinel — a test that aborts part-way fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"same_climb_is_stable",
	"different_climbs_differ",
	"unseeded_matches_legacy",
	"explicit_seed_wins",
	"floorgen_last_seed_is_the_default_source",
	"the_void_is_gated_deep",
	"final_guardian_always_pays",
	"variety_across_many_climbs",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_same_climb_is_stable()
	_test_different_climbs_differ()
	_test_unseeded_matches_legacy()
	_test_explicit_seed_wins()
	_test_floorgen_last_seed_is_the_default_source()
	_test_the_void_is_gated_deep()
	_test_final_guardian_always_pays()
	_test_variety_across_many_climbs()
	_reset()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Drop climb-seed tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Drop climb-seed tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Both seed statics back to "not told", so one test cannot leak into the next.
func _reset() -> void:
	# ⚠ THIS SUITE MEASURES THE TABLE; THE GAME FINDS NO SPELLS. Maker: "you shouldn't
	# be able to find spells in the tower." `SpellDrops.TOWER_SPELL_DROPS` is false, so
	# every roll returns "" before it touches the RNG — correct for the game, and it
	# makes every assertion in here vacuous (five of them went red reporting "/, /, /").
	# The test opts back in explicitly, so the distribution stays pinned and the ruling
	# can be lifted later without re-deriving what it used to be.
	SpellDrops.allow_drops_for_test = true
	SpellDrops.climb_seed = 0
	FloorGen.climb_seed = 0
	FloorGen.last_seed = 0


## Every floor's pickup + boss drop for one climb, as one comparable string.
func _tower_loot(floors: int = 5) -> String:
	var out: Array[String] = []
	for f: int in range(1, floors + 1):
		out.append("%s/%s" % [SpellDrops.roll_floor_drop(f), SpellDrops.roll_boss_drop(f)])
	return ", ".join(out)


## WITHIN a climb the roll must not move. This is the co-op contract: both peers
## build their own props from the same state with no packet, and they ask at
## different moments.
func _test_same_climb_is_stable() -> void:
	_reset()
	SpellDrops.climb_seed = 24601
	var a: String = _tower_loot()
	var b: String = _tower_loot()
	_expect(a == b, "the same climb rolls the same loot twice (%s vs %s)" % [a, b])
	_completes("same_climb_is_stable")


## ACROSS climbs it must move. This is the whole finding: floor 2 used to offer the
## identical thing forever.
func _test_different_climbs_differ() -> void:
	_reset()
	SpellDrops.climb_seed = 111
	var a: String = _tower_loot()
	SpellDrops.climb_seed = 222
	var b: String = _tower_loot()
	_expect(a != b, "two climbs roll different loot (both were %s)" % a)
	_completes("different_climbs_differ")


## Seed 0 — a live co-op session, or any harness that never built a tower — must
## reproduce the pre-climb-seed roll exactly. That is what makes the co-op pin a
## known limitation rather than a second code path.
func _test_unseeded_matches_legacy() -> void:
	_reset()
	_expect(SpellDrops.resolve_climb_seed() == 0, "no seed anywhere resolves to 0")
	_expect(SpellDrops._salt_for_climb() == SpellDrops.SEED_SALT,
		"an unseeded climb salts with the bare SEED_SALT")
	_completes("unseeded_matches_legacy")


## The policy order: an explicit SpellDrops seed beats FloorGen's, which beats the
## seed FloorGen last drew with.
func _test_explicit_seed_wins() -> void:
	_reset()
	FloorGen.last_seed = 7
	FloorGen.climb_seed = 8
	SpellDrops.climb_seed = 9
	_expect(SpellDrops.resolve_climb_seed() == 9, "an explicit SpellDrops.climb_seed wins")
	SpellDrops.climb_seed = 0
	_expect(SpellDrops.resolve_climb_seed() == 8, "FloorGen.climb_seed is next")
	FloorGen.climb_seed = 0
	_expect(SpellDrops.resolve_climb_seed() == 7, "FloorGen.last_seed is the fallback")
	_completes("explicit_seed_wins")


## The normal shipping path: nobody sets anything, `FloorGen.apply()` runs once per
## climb out of GameState and records its seed, and the loot follows the rooms.
func _test_floorgen_last_seed_is_the_default_source() -> void:
	_reset()
	FloorGen.last_seed = 4242
	var a: String = _tower_loot()
	FloorGen.last_seed = 99991
	var b: String = _tower_loot()
	_expect(a != b, "the loot follows FloorGen.last_seed (both climbs were %s)" % a)
	FloorGen.last_seed = 4242
	_expect(_tower_loot() == a, "the same FloorGen seed replays the same loot")
	_completes("floorgen_last_seed_is_the_default_source")


## A 260-damage ULT-weight nuke must not be reachable from a floor-1 guardian.
func _test_the_void_is_gated_deep() -> void:
	_reset()
	var gate: int = int(SpellDrops.SIGNATURE_MIN_FLOOR.get("the_void", 1))
	_expect(gate >= 4, "the_void is gated to floor 4 or deeper (got %d)" % gate)
	for climb: int in range(1, 40):
		SpellDrops.climb_seed = climb * 7919 + 3
		for f: int in range(1, gate):
			_expect(SpellDrops.roll_boss_drop(f) != "the_void",
				"the_void never drops on floor %d (climb %d)" % [f, climb])
	_completes("the_void_is_gated_deep")


## The climactic fight of the whole climb cannot pay out nothing, and every floor
## before it still can. NOTE the autoload IS reachable here: a `--script` harness
## registers no global IDENTIFIERS but the autoload NODES are on the tree, which is
## exactly why `SpellDrops.is_final_floor` looks it up rather than naming it.
func _test_final_guardian_always_pays() -> void:
	_reset()
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs == null or not gs.has_method(&"total_floors"):
		_expect(false, "GameState is reachable from the harness tree")
		_completes("final_guardian_always_pays")
		return
	var total: int = int(gs.call(&"total_floors"))
	_expect(total > 0, "the tower has floors (%d)" % total)
	_expect(SpellDrops.is_final_floor(total), "floor %d is the final floor" % total)
	_expect(not SpellDrops.is_final_floor(total - 1), "floor %d is not" % (total - 1))
	# `>=` here would have silently guaranteed every floor number past the last, so
	# pin that it does not.
	_expect(not SpellDrops.is_final_floor(total + 1),
		"a floor number past the tower is not 'final' either")
	var empties: int = 0
	for climb: int in range(1, 41):
		SpellDrops.climb_seed = climb * 40503 + 7
		if SpellDrops.roll_boss_drop(total) == "":
			empties += 1
	_expect(empties == 0,
		"the final guardian drops a Tier 3 on all 40 climbs (%d were empty)" % empties)
	_completes("final_guardian_always_pays")


## THE FINDING, MEASURED. Over many climbs the tower must offer a real spread of
## spells, not the same two or three. The old table could only ever produce ONE
## tower's worth of loot; the bar here is deliberately modest (the drop table is
## still mostly the common band by design) but it is far above 1.
func _test_variety_across_many_climbs() -> void:
	_reset()
	var seen: Dictionary = {}
	var towers: Dictionary = {}
	for climb: int in range(1, 61):
		SpellDrops.climb_seed = climb * 2654435761 % 2147483647
		var loot: String = _tower_loot()
		towers[loot] = true
		for f: int in range(1, 6):
			var a: String = SpellDrops.roll_floor_drop(f)
			var b: String = SpellDrops.roll_boss_drop(f)
			if a != "":
				seen[a] = true
			if b != "":
				seen[b] = true
	_expect(seen.size() >= 8,
		"60 climbs offer at least 8 distinct spells (got %d: %s)" % [seen.size(), str(seen.keys())])
	_expect(towers.size() >= 40,
		"60 climbs produce at least 40 distinct towers of loot (got %d)" % towers.size())
	print("  [variety] 60 climbs -> %d distinct spells across %d distinct towers"
		% [seen.size(), towers.size()])
	_completes("variety_across_many_climbs")
