# Run: godot --headless --path godot-project --script tools/slice_test_grimoire.gd
#
# THE ELEVEN SPELLS ONLY THE BOTS COULD CAST.
#
# The maker, watching Lobby -> Watch Bots: *"when I watch the bot fights I see all these
# cool classes spells and interactions and spells please ensure the main game has all of
# these"*. Counted rather than assumed: the nine Tier 3s and both Tier 2s were reachable
# ONLY through `BotMatch._grant_showcase_drop`, a hand-written back door added because a
# duel has no floor to find them on. The front door did not exist — `TOWER_SPELL_DROPS`
# is false by the maker's own earlier ruling (*"you shouldn't be able to find spells in
# the tower"*), so a climber's hand on floor 41 was byte-identical to floor 1.
#
# The two rulings genuinely collide, so it went back to the maker as a fork. Their answer
# was EQUIP THEM IN THE HUB: the tower stays clean, and you choose at the door.
#
# == WHAT THIS SUITE IS ACTUALLY DEFENDING ====================================
# Two properties that pull in opposite directions, which is why both are here:
#
#   1. YOU CAN PUT ANY OF THE ELEVEN IN YOUR HAND. That is the feature.
#   2. YOU NEVER START WITH ONE. `slice_test_drops` has an invariant that a class does
#      not START with a drop spell, and it must survive this feature intact — the whole
#      reason equipping is an OVERLAY on `build_for_class` rather than an edit to
#      `CLASS_KITS`. A grimoire that leaked into the default hand would pass (1) and
#      quietly destroy (2).
#
# == AND A SAVE IS A FILE ON SOMEBODY ELSE'S DISK =============================
# Hydration goes back through `set_equipped`, so a hand-edited save, or one written by a
# build where an id has since been renamed, is refused PER ROW rather than trusted or
# thrown away whole. Asserted, because "we validate on the way in" is the kind of claim
# that is true right up until someone adds a faster path.
#
# -- Vacuous-pass armour (full write-up in tools/slice_test_spell_buttons.gd) --
# `failed += _test_x()` IS BANNED. A dead property read is not a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function and hands the caller
# back the return type's zero, which under that idiom reads as "zero failures". So
# failures accumulate on the MEMBER `_fails`, and every test records a completion
# sentinel — a test that aborts part-way is missing from `_completed` and fails BY
# ABSENCE rather than passing by silence.
extends SceneTree

const TESTS: Array[String] = [
	"the_pool_is_the_eleven_the_bots_had",
	"nobody_starts_with_one",
	"an_equipped_spell_lands_in_its_slot_and_only_there",
	"a_bad_pick_is_refused_rather_than_half_applied",
	"a_pick_survives_the_save_and_a_broken_save_does_not",
]

## The class the picks are made on. Arcanist — its authored hand is the one every other
## suite in this area uses, so a surprise here is about this feature and not about a kit.
const CLS: int = 0

var _fails: int = 0
var _completed: Dictionary = {}


## A stand-in for `GameState`, declaring exactly the two fields the library writes.
##
## ⚠ IT HAS TO DECLARE THEM. `Object.set()` on an undeclared property is a SILENT no-op
## in GDScript — which is the trap `SpellLibrary.persist_to_state` already guards against
## by reading the value back — so a stub with no fields would make every round-trip below
## pass by doing nothing at all.
class StateStub extends Node:
	var spell_roles: Dictionary = {}
	var spell_equipped: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_the_pool_is_the_eleven_the_bots_had()
	_test_nobody_starts_with_one()
	_test_an_equipped_spell_lands_in_its_slot_and_only_there()
	_test_a_bad_pick_is_refused_rather_than_half_applied()
	_test_a_pick_survives_the_save_and_a_broken_save_does_not()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Grimoire tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Grimoire tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _ids(hand: Array) -> Array:
	var out: Array = []
	for s: SpellDef in hand:
		out.append(s.id)
	return out


# ---------------------------------------------------------------------------
# 1. the pool
# ---------------------------------------------------------------------------

func _test_the_pool_is_the_eleven_the_bots_had() -> void:
	SpellLibrary.clear_equipped()
	var pool: Array = SpellLibrary.equippable_ids()
	_expect(pool.size() >= 11,
		"the hub offers every Tier 2 and Tier 3 (%d, expected 11 or more as the tables"
			% pool.size() + " grow)")
	# Named, not counted, because a count passes while the table holds eleven copies of
	# one spell. These are the ids `BotMatch.CLASS_DROP` hands its fighters.
	for id: String in ["the_void", "chronostasis", "equinox", "roulette", "severance",
			"zanshin", "teardown", "siegeworks", "the_circuit",
			"arc_of_fools", "meteor_storm"]:
		_expect(pool.has(id),
			"`%s` is equippable in the hub — it was reachable only through" % id
			+ " `BotMatch._grant_showcase_drop`, i.e. only a bot could ever cast it")
		_expect(SpellLibrary.by_id(id) != null,
			"...and the whole-tree lookup resolves it, so equipping it can build a spell")
	_completes("the_pool_is_the_eleven_the_bots_had")


# ---------------------------------------------------------------------------
# 2. the invariant this feature must not break
# ---------------------------------------------------------------------------

## `slice_test_drops` asserts a class does not START with a drop. That test measures the
## DEFAULT hand, and this feature makes the hand configurable — so the invariant only
## keeps its meaning if the default is genuinely untouched with nothing equipped.
func _test_nobody_starts_with_one() -> void:
	SpellLibrary.clear_equipped()
	var pool: Array = SpellLibrary.equippable_ids()
	for cls: int in SpellLibrary.CLASS_KITS.size():
		for id: String in _ids(SpellLibrary.build_for_class(cls)):
			_expect(not pool.has(id),
				"class %d STARTS with `%s`, which is a hub pick. Equipping is an overlay:"
					% [cls, id]
				+ " an empty grimoire must leave the authored hand byte-identical.")
	_completes("nobody_starts_with_one")


# ---------------------------------------------------------------------------
# 3. the feature
# ---------------------------------------------------------------------------

func _test_an_equipped_spell_lands_in_its_slot_and_only_there() -> void:
	SpellLibrary.clear_equipped()
	var before: Array = _ids(SpellLibrary.build_for_class(CLS))
	_expect(before.size() == SpellTier.SLOT_COUNT,
		"the authored hand is %d spells (got %d) — everything below indexes into it"
			% [SpellTier.SLOT_COUNT, before.size()])
	if before.size() != SpellTier.SLOT_COUNT:
		_completes("an_equipped_spell_lands_in_its_slot_and_only_there")
		return
	var slot: int = SpellTier.ULT_SLOT
	_expect(SpellLibrary.set_equipped(CLS, slot, "the_void"),
		"a Tier 3 can be equipped into the ult slot")
	var after: Array = _ids(SpellLibrary.build_for_class(CLS))
	_expect(after.size() == before.size(),
		"equipping replaced a slot rather than growing the hand (%d -> %d)"
			% [before.size(), after.size()])
	_expect(after[slot] == "the_void",
		"slot %d now holds the pick (holds `%s`)" % [slot, String(after[slot])])
	# ...AND NOTHING ELSE MOVED. A pick that quietly re-ordered the other three would
	# change which key throws what, which is the one thing a hotbar may never do.
	for i: int in before.size():
		if i == slot:
			continue
		_expect(after[i] == before[i],
			"slot %d was `%s` and is now `%s` — equipping one slot moved another"
				% [i, String(before[i]), String(after[i])])
	_expect(SpellLibrary.equipped_id(CLS, slot) == "the_void",
		"the screen can read back what is equipped, to draw it")
	# And it comes back off.
	SpellLibrary.clear_equipped(CLS, slot)
	_expect(_ids(SpellLibrary.build_for_class(CLS)) == before,
		"clearing the slot restores the authored hand exactly")
	_completes("an_equipped_spell_lands_in_its_slot_and_only_there")


# ---------------------------------------------------------------------------
# 4. the refusals
# ---------------------------------------------------------------------------

## ⚠ EACH REFUSAL IS CHECKED FOR ITS EFFECT, NOT ONLY ITS RETURN VALUE. A function that
## returns false and writes anyway is the failure mode worth having a test for; a
## function that returns false is not.
func _test_a_bad_pick_is_refused_rather_than_half_applied() -> void:
	SpellLibrary.clear_equipped()
	var authored: Array = _ids(SpellLibrary.build_for_class(CLS))
	_expect(not SpellLibrary.set_equipped(CLS, SpellTier.SLOT_COUNT, "the_void"),
		"a slot past the end of the hand is refused")
	_expect(not SpellLibrary.set_equipped(CLS, -1, "the_void"),
		"a negative slot is refused")
	# A REAL SPELL THAT IS NOT IN THE POOL. `ordinary_spell` is a class kit spell: it
	# exists, `by_id` finds it, and it still may not be equipped — otherwise the hub
	# becomes a way to put any spell on any class, which is the recolour ruling's
	# problem, not this feature's.
	_expect(SpellLibrary.by_id("ordinary_spell") != null,
		"`ordinary_spell` really is a spell — otherwise the next line proves nothing")
	_expect(not SpellLibrary.set_equipped(CLS, 0, "ordinary_spell"),
		"a spell outside the Tier 2 / Tier 3 pool is refused even though it exists")
	_expect(not SpellLibrary.set_equipped(CLS, 0, "no_such_spell_at_all"),
		"an id that is not a spell at all is refused")
	_expect(_ids(SpellLibrary.build_for_class(CLS)) == authored,
		"...and not one of those four refusals changed the hand")
	# The empty id is the CLEAR, not a refusal — the screen needs a way to say "back to
	# what my class brought".
	_expect(SpellLibrary.set_equipped(CLS, 0, ""),
		"an empty id clears the slot and reports success")
	_completes("a_bad_pick_is_refused_rather_than_half_applied")


# ---------------------------------------------------------------------------
# 5. the round trip
# ---------------------------------------------------------------------------

func _test_a_pick_survives_the_save_and_a_broken_save_does_not() -> void:
	SpellLibrary.clear_equipped()
	var authored: Array = _ids(SpellLibrary.build_for_class(CLS))
	var state := StateStub.new()
	root.add_child(state)
	SpellLibrary.set_equipped(CLS, SpellTier.ULT_SLOT, "chronostasis")
	var wanted: Array = _ids(SpellLibrary.build_for_class(CLS))
	_expect(SpellLibrary.persist_to_state(state), "the pick writes to the save state")
	_expect(state.spell_equipped.size() > 0,
		"...and the field really holds something (a `set()` on an undeclared property"
		+ " is a silent no-op, which is why this reads the value back)")
	# Wipe the live table the way a fresh process would.
	SpellLibrary.clear_equipped()
	_expect(_ids(SpellLibrary.build_for_class(CLS)) == authored,
		"the table really was cleared — otherwise the hydrate below proves nothing")
	_expect(SpellLibrary.hydrate_from_state(state), "the save hydrates back")
	_expect(_ids(SpellLibrary.build_for_class(CLS)) == wanted,
		"the hand after a reload is the hand before the save")

	# ══ A HAND-EDITED SAVE ═════════════════════════════════════════════════════
	# One good row, one impossible slot, one id that is not a spell. The good row must
	# survive; the other two must not reach a hand. Keys are written as FLOATS on
	# purpose — that is what JSON hands back, and the int/float confusion has already
	# cost this project a wiped save file once.
	SpellLibrary.clear_equipped()
	state.spell_equipped = {
		float(CLS): {
			float(SpellTier.ULT_SLOT): "equinox",
			99.0: "the_void",
			0.0: "not_a_spell",
		}
	}
	SpellLibrary.hydrate_from_state(state)
	var hand: Array = _ids(SpellLibrary.build_for_class(CLS))
	_expect(hand.size() == authored.size(),
		"a broken save did not change the SIZE of the hand (%d -> %d)"
			% [authored.size(), hand.size()])
	_expect(hand[SpellTier.ULT_SLOT] == "equinox",
		"the one valid row survived the two broken ones beside it (ult is `%s`)"
			% String(hand[SpellTier.ULT_SLOT]))
	_expect(hand[0] == authored[0],
		"the row naming a spell that does not exist was refused (slot 0 is `%s`,"
			% String(hand[0]) + " should be the authored `%s`)" % String(authored[0]))
	SpellLibrary.clear_equipped()
	state.queue_free()
	_completes("a_pick_survives_the_save_and_a_broken_save_does_not")
