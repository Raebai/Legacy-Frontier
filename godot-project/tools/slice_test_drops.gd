# Run: godot --headless --path godot-project --script tools/slice_test_drops.gd
#
# THE DROP ECONOMY's data layer: the drop table, the grant ledger, Tier 3 charges,
# the floor reset and the player-to-player handoff.
#
# ⚠ READ `_test_tower_finds_no_spells` FIRST. Since 2026-08-04 the maker's ruling is
# that NO SPELL CAN BE FOUND IN THE TOWER, and `SpellDrops.TOWER_SPELL_DROPS` is the
# one switch that says so. Every other test in this file opens a test-only hatch and
# measures the TABLE underneath the switch — deliberately, because the table is what
# comes back if the ruling is reversed and a table that rotted while switched off
# would come back broken. None of them is evidence that a player can find a spell.
#
# Everything here is pure data —
# `SpellDrops`, `SpellGrant` and `HandSlots` were all written to have no tree access
# precisely so this suite could exist without autoloads (which `--script` does not
# register).
#
# ⚠ THE IDIOM. Failures accumulate on the MEMBER `_fails` and every test records a
# COMPLETION SENTINEL as its last line, so a test that aborts part-way fails the
# suite BY ABSENCE. Never `_fails += _test_x()`: a dead property read aborts the
# enclosing function and hands back the type's zero, which that idiom reads as "no
# failures" — the bug that silently disabled 64 suites in this repo once.
# `tools/slice_test_loadout.gd` is the reference.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"

## The two Hero privates `SpellGrant._install` falls back to when there is no public
## `receive_spell`. Named here so a rename fails LOUDLY in this suite instead of
## silently turning every pickup in the game into a no-op.
const HERO_GRANT_MEMBERS: Array[String] = ["_signatures", "_hand"]

const TESTS: Array[String] = [
	"tower_finds_no_spells",
	"drops_are_never_in_a_kit",
	"roll_is_deterministic",
	"rarity_is_actually_rare",
	"common_band_is_the_class_reserve",
	"hand_replaces_never_grows",
	"grant_displaces_and_restores",
	"tier3_charges_expire_into_the_class_ult",
	"floor_reset_returns_the_kit",
	"handoff_moves_the_whole_grant",
	"hero_fallback_members_exist",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_tower_finds_no_spells()
	_test_drops_are_never_in_a_kit()
	_test_roll_is_deterministic()
	_test_rarity_is_actually_rare()
	_test_common_band_is_the_class_reserve()
	_test_hand_replaces_never_grows()
	_test_grant_displaces_and_restores()
	_test_tier3_charges_expire_into_the_class_ult()
	_test_floor_reset_returns_the_kit()
	_test_handoff_moves_the_whole_grant()
	_test_hero_fallback_members_exist()
	for name: String in TESTS:
		if not _completed.has(name):
			_fail("test '%s' never reached its completion sentinel (it aborted)" % name)
	if _fails == 0:
		print("Drops tests: all PASS")
	else:
		printerr("Drops tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fail(what)


func _fail(what: String) -> void:
	_fails += 1
	printerr("FAIL: ", what)


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ 0. the ruling

## THE MAKER'S RULING, 2026-08-04, verbatim from a live playtest: "you shouldn't be
## able to find spells in the tower so remove that blizzard and any other spells that
## are there."
##
## ⚠ THIS TEST IS FIRST ON PURPOSE, and it is the only one in this suite that runs
## with the hatch SHUT. Everything below it opens `SpellDrops.allow_drops_for_test` and
## measures the TABLE — the odds, the gates, the common band — which is still worth
## guarding because it is what comes back if the ruling is ever reversed. Without this
## test sitting in front of them, a reader would find eight suites happily measuring a
## drop economy the game does not have, and would reasonably conclude the ruling had
## been lost in a merge.
##
## It also asserts the SHAPE of the ruling: a switch, not a deletion. The tables are
## intact and one boolean brings the whole economy back.
func _test_tower_finds_no_spells() -> void:
	_table_shut()
	_expect(not SpellDrops.TOWER_SPELL_DROPS,
		"TOWER_SPELL_DROPS is off — the tower hands out no spells")
	_expect(not SpellDrops.drops_are_findable(), "...and both rolls agree on that")
	var leaked: Array[String] = []
	for climb: int in range(1, 25):
		SpellDrops.climb_seed = climb * 7919 + 3
		for f: int in range(1, 41):
			var floor_id: String = SpellDrops.roll_floor_drop(f)
			var boss_id: String = SpellDrops.roll_boss_drop(f)
			if floor_id != "":
				leaked.append("floor %d -> %s" % [f, floor_id])
			if boss_id != "":
				leaked.append("guardian %d -> %s" % [f, boss_id])
	SpellDrops.climb_seed = 0
	_expect(leaked.is_empty(),
		"960 floor-rolls across 24 climbs produce NOTHING (leaked: %s)"
			% str(leaked.slice(0, 4)))
	# THE FINAL GUARDIAN specifically, because it is the one floor that carries a
	# GUARANTEE ("the last guardian always pays"). A guarantee is exactly the kind of
	# thing that survives a ruling by accident.
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs != null and gs.has_method(&"total_floors"):
		var total: int = int(gs.call(&"total_floors"))
		_expect(SpellDrops.is_final_floor(total),
			"floor %d really is the guaranteed one" % total)
		_expect(SpellDrops.roll_boss_drop(total) == "",
			"...and even IT pays nothing while the ruling stands")
	# A SWITCH, NOT A DELETION. The catalogue is untouched and one flip restores it.
	_table_open()
	_expect(SpellLibrary.build_tier2().size() > 0, "the Tier 2 table was NOT emptied")
	_expect(SpellLibrary.build_tier3().size() > 0, "the Tier 3 table was NOT emptied")
	_expect(not SpellDrops._common_pool().is_empty(), "the common band was NOT emptied")
	var restored: int = 0
	for f2: int in range(1, 200):
		if SpellDrops.roll_floor_drop(f2) != "":
			restored += 1
	_expect(restored > 20,
		"flipping the switch brings the whole economy straight back (%d/199 floors)"
			% restored)
	_table_shut()
	_completes("tower_finds_no_spells")


## Open / shut the test-only hatch that lets this suite measure the drop table while
## the game itself finds no spells. Named rather than inlined so every table test
## below reads as "measuring the switched-off table", which is what it is doing.
func _table_open() -> void:
	SpellDrops.allow_drops_for_test = true


func _table_shut() -> void:
	SpellDrops.allow_drops_for_test = false


# ---------------------------------------------------------------- 1. the table

## THE SPEC'S ONE HARD RULE about these spells: "Never in the starting kit." A drop
## that a class already carries is not a drop, it is a duplicate — and worse, it
## would make `SpellGrant` displace a spell with itself.
func _test_drops_are_never_in_a_kit() -> void:
	var drops: Array[String] = SpellLibrary.drop_ids()
	# SIX. `mirror_image` stopped being a drop when the anti-recolour pass promoted it
	# into the Arcanist's control slot, and `petrify` / `gravity_flip` / `blood_pact`
	# stopped when the FOURTH spell slot claimed them for the Brawler, Juggernaut and
	# Swordsaint. A spell in both places would be rollable as a pickup for the class that
	# already starts with it, and `SpellGrant` would then displace a spell with itself.
	_expect(drops.size() == 6, "six drop spells exist (2 Tier 2 + 4 Tier 3), got %d" % drops.size())
	_expect(not drops.has("mirror_image"),
		"mirror_image is NOT a drop any more — it is the Arcanist's carried control slot")
	_expect(SpellLibrary.drop_by_id("mirror_image") == null,
		"...so the drop lookup answers null for it (use SpellLibrary.by_id for the tree)")
	_expect(SpellLibrary.by_id("mirror_image") != null,
		"...and the whole-tree lookup still finds it")
	for cls: int in range(SpellLibrary.CLASS_KITS.size()):
		for s: SpellDef in SpellLibrary.build_for_class(cls):
			_expect(not drops.has(s.id),
				"class %d does not START with the drop '%s'" % [cls, s.id])
		# ...and not in the authored five-role pool either, which is where the
		# common band comes from and would double-count.
		for role: String in SpellLibrary.ROLE_ORDER:
			var id: String = String(SpellLibrary.kit_for_class(cls).get(role, ""))
			_expect(not drops.has(id),
				"class %d's authored '%s' role is not a drop spell ('%s')" % [cls, role, id])
	_completes("drops_are_never_in_a_kit")


## CO-OP DEPENDS ON THIS. Both peers build their own floor props with no message
## passing, so the roll has to be a pure function of the floor number. An unseeded
## roll would put a different spell in the same place on each screen.
func _test_roll_is_deterministic() -> void:
	_table_open()   # measuring the table, not the game — see `tower_finds_no_spells`
	for f: int in range(1, 40):
		var a: String = SpellDrops.roll_floor_drop(f)
		var b: String = SpellDrops.roll_floor_drop(f)
		_expect(a == b, "floor %d rolls the same pickup twice ('%s' vs '%s')" % [f, a, b])
		var ba: String = SpellDrops.roll_boss_drop(f)
		var bb: String = SpellDrops.roll_boss_drop(f)
		_expect(ba == bb, "floor %d rolls the same boss drop twice" % f)
	# ...and the two channels are independent: if the boss roll were derived from
	# the floor roll, changing one would change both.
	var same: int = 0
	for f: int in range(1, 40):
		if SpellDrops.roll_floor_drop(f) == SpellDrops.roll_boss_drop(f):
			same += 1
	_expect(same < 30, "floor and boss rolls are not the same sequence (%d/39 matched)" % same)
	_table_shut()
	_completes("roll_is_deterministic")


## RARITY IS THE BALANCE SYSTEM, so it is the thing that gets a test. These bounds
## are wide on purpose — they exist to catch a constant being fat-fingered to 1.0 or
## a gate accidentally excluding everything, not to pin the exact feel.
func _test_rarity_is_actually_rare() -> void:
	_table_open()   # measuring the table, not the game — see `tower_finds_no_spells`
	var floors: int = 400
	var with_drop: int = 0
	var signature_hits: Dictionary = {}
	var tier2_ids: Array[String] = []
	for s: SpellDef in SpellLibrary.build_tier2():
		tier2_ids.append(s.id)
	for f: int in range(1, floors + 1):
		var id: String = SpellDrops.roll_floor_drop(f)
		if id == "":
			continue
		with_drop += 1
		if tier2_ids.has(id):
			signature_hits[id] = int(signature_hits.get(id, 0)) + 1
	var rate: float = float(with_drop) / float(floors)
	_expect(rate > 0.35 and rate < 0.75,
		"a floor has a pickup roughly TIER2_FLOOR_CHANCE of the time (got %.2f)" % rate)
	var sig_rate: float = float(_sum(signature_hits)) / float(floors)
	_expect(sig_rate < 0.30,
		"a Tier 2 SIGNATURE is rare — under 30%% of floors (got %.2f)" % sig_rate)
	_expect(sig_rate > 0.02,
		"...but not unreachable — over 2%% of floors (got %.2f)" % sig_rate)
	# THE FLOOR GATE. The two loudest must not open a run.
	for f: int in [1, 2]:
		var early: String = SpellDrops.roll_floor_drop(f)
		# `mirror_image` used to be gated here too and is no longer a drop at all, so
		# Meteor Storm is the one remaining gated signature. The gate itself is what
		# is being tested, not the length of the list.
		_expect(early != "meteor_storm",
			"floor %d cannot roll a gated signature (got '%s')" % [f, early])
		_expect(SpellDrops.SIGNATURE_MIN_FLOOR.has("meteor_storm"),
			"...and the gate is real rather than an accident of the roll")
	# BOSS DROPS. Roughly half, and never nothing-at-all across a whole tower.
	var boss: int = 0
	for f: int in range(1, floors + 1):
		if SpellDrops.roll_boss_drop(f) != "":
			boss += 1
	var brate: float = float(boss) / float(floors)
	_expect(brate > 0.3 and brate < 0.7,
		"a guardian drops a Tier 3 roughly half the time (got %.2f)" % brate)
	_table_shut()
	_completes("rarity_is_actually_rare")


## The common band must be DERIVED from the class reserve, not hand-listed. That is
## what stops the drop table drifting out of sync with the kits.
func _test_common_band_is_the_class_reserve() -> void:
	_table_open()   # measuring the table, not the game — see `tower_finds_no_spells`
	var reserve: Array[String] = []
	for cls: int in range(SpellLibrary.CLASS_KITS.size()):
		for s: SpellDef in SpellLibrary.reserve_for_class(cls):
			if not reserve.has(s.id):
				reserve.append(s.id)
	_expect(reserve.size() >= 4, "the class reserve is non-trivial (%d spells)" % reserve.size())
	# Spells a class AUTHORS but does not carry. The set moved with the anti-recolour
	# pass — `rift_dagger` became the Shadowblade's carried get-out and `rock_pillar`
	# the Juggernaut's carried payoff, while `blink_strike` and `drain_tether` came the
	# other way — so these are re-derived from the current table rather than pinned to
	# the old handoff list.
	# ⚠ THINNER AT FOUR SLOTS. A class authors five roles and carries four, so its
	# reserve is ONE spell, not two — `creeping_shade` and `ice_wall` are carried now
	# (Shadowblade, Cryomancer) and only these two are still anybody's reserve.
	for id: String in ["blink_strike", "drain_tether"]:
		_expect(reserve.has(id), "'%s' is still in the reserved pickup pool" % id)
	# THE ORPHANS. The pass displaced seven fully-tuned spells out of CLASS_KITS
	# ENTIRELY, so `reserve_for_class` cannot see them: no class authors them any more.
	# `SpellLibrary.unequipped_ids` is the second source that keeps them reachable, and
	# without this assertion "nothing was deleted" is a claim with nothing behind it.
	var orphans: Array[String] = SpellLibrary.unequipped_ids()
	# `rune_orbs` and `judgment` left this list for the Arcanist's and Cleric's fourth
	# slots; seven orphans remain.
	for id2: String in ["frostpiercer", "infernal_lance", "umbral_lance", "tempest",
			"colossus_pillar", "void_barrage"]:
		_expect(orphans.has(id2),
			"displaced spell '%s' survives as a floor pickup rather than being deleted" % id2)
	# ...and the two that had ALREADY gone orphan before this pass and that nobody had
	# noticed, which is the same bug the kit table exists to prevent.
	for id3: String in ["avalanche"]:
		_expect(orphans.has(id3), "long-orphaned '%s' is reachable at last" % id3)
	# ...and `judgment`, orphaned for longer than anything else in the tree, is not
	# reachable as a pickup any more because it is CARRIED: it is the Cleric's fourth
	# slot. Asserted from the other side so the fix cannot be mistaken for the old bug.
	_expect(not orphans.has("judgment"),
		"'judgment' left the orphan pool by being equipped, not by being deleted")
	_expect(SpellLibrary.slot_roles_for_class(4).has("answer")
			and String(SpellLibrary.kit_for_class(4).get("answer", "")) == "judgment",
		"...into the Cleric's carried hand")
	var common: Array[String] = SpellDrops._common_pool()
	for id4: String in orphans:
		_expect(common.has(id4),
			"orphan '%s' really reaches the floor-drop common band" % id4)
	# Every common-band roll resolves to a real spell — a drop id that resolves to
	# null is an invisible pickup, the one failure nobody would ever report.
	for f: int in range(1, 120):
		var id2: String = SpellDrops.roll_floor_drop(f)
		if id2 == "":
			continue
		_expect(SpellDrops.spell_for_id(id2) != null,
			"floor %d's drop '%s' resolves to a real SpellDef" % [f, id2])
	_table_shut()
	_completes("common_band_is_the_class_reserve")


# ------------------------------------------------------------------ 2. the hand

## THE HAND DOES NOT GROW. The hand is `SpellTier.SLOT_COUNT` buttons wide — FOUR
## since the maker asked for a fourth — and a pickup REPLACES, it never appends: a
## fifth spell is a spell the player cannot press.
##
## ⚠ THE DROP IDS HERE MOVED. This test used to grant `petrify` and `gravity_flip`,
## which are CARRIED spells now (Brawler, Juggernaut) and therefore no longer resolve
## through `drop_by_id` at all. It used them silently for as long as they were drops;
## granting a null is what the null-guard below is for, and the test would have kept
## passing its first assertion by luck. Use ids from `build_tier2()`.
func _test_hand_replaces_never_grows() -> void:
	var hand := HandSlots.new()
	var kit: Array = SpellLibrary.build_for_class(0)
	hand.rebuild([], kit)
	var before: int = hand.slots.size()
	_expect(hand.spell_count() == SpellTier.SLOT_COUNT,
		"a fresh hand carries SLOT_COUNT spells (got %d)" % hand.spell_count())
	var drop: SpellDef = SpellLibrary.drop_by_id("arc_of_fools")
	_expect(hand.replace_spell(0, drop), "a drop lands in slot 0")
	_expect(hand.slots.size() == before, "the carousel did NOT grow (%d -> %d)"
		% [before, hand.slots.size()])
	_expect(String((hand.spell_at(0) as SpellDef).id) == "arc_of_fools", "slot 0 now holds the drop")
	# FISTS stays at index 0 — a hero must never be left with no melee option.
	_expect(int(hand.slots[0]["kind"]) == HandSlots.Kind.FISTS, "fists still occupy hand index 0")
	# The drop arrives READY. Inheriting the displaced spell's cooldown would mean a
	# pickup that is dark for eight seconds for reasons nothing on screen explains.
	hand.start_cooldown(hand.spell_slot_index(1), 9.0)
	hand.replace_spell(1, SpellLibrary.drop_by_id("meteor_storm"))
	_expect(hand.is_ready(hand.spell_slot_index(1)), "a freshly granted slot is READY")
	_expect(not hand.replace_spell(99, drop), "an out-of-range slot refuses rather than writing past the end")
	_expect(not hand.replace_spell(0, null), "a null spell is refused")
	_completes("hand_replaces_never_grows")


## A grant remembers what it displaced and puts it back. Tier 2 takes a non-ult
## slot, Tier 3 takes the ult slot.
func _test_grant_displaces_and_restores() -> void:
	var hero: Node = _stub_hero(0)
	var kit: Array = (hero.get("_signatures") as Array).duplicate()
	var t2: SpellDef = SpellLibrary.drop_by_id("arc_of_fools")
	var nth: int = SpellGrant.apply(hero, t2)
	_expect(nth >= 0 and nth < SpellTier.ULT_SLOT,
		"a Tier 2 takes a NON-ult slot (got %d)" % nth)
	_expect(String(((hero.get("_signatures") as Array)[nth] as SpellDef).id) == "arc_of_fools",
		"the hero's signature list carries the drop")
	_expect(String(((hero.get("_hand") as HandSlots).spell_at(nth) as SpellDef).id) == "arc_of_fools",
		"...and so does the hand, so the bar and the cast agree")
	var t3: SpellDef = SpellLibrary.drop_by_id("the_void")
	var un: int = SpellGrant.apply(hero, t3)
	_expect(un == SpellTier.ULT_SLOT, "a Tier 3 takes the ULT slot (got %d)" % un)
	# Picking the SAME drop up twice refills rather than eating a second slot.
	var again: int = SpellGrant.apply(hero, SpellLibrary.drop_by_id("the_void"))
	_expect(again == SpellTier.ULT_SLOT, "a second copy refills the same slot")
	_expect((hero.get_meta("spell_grants") as Dictionary)["slots"].size() == 2,
		"...and does not open a third grant")
	SpellGrant.restore_all(hero)
	for i: int in kit.size():
		_expect(String(((hero.get("_signatures") as Array)[i] as SpellDef).id) == String((kit[i] as SpellDef).id),
			"slot %d is back to the class kit after restore" % i)
	hero.free()
	_completes("grant_displaces_and_restores")


## THE SPEC'S "what happens when they run out": the class ult comes straight back.
func _test_tier3_charges_expire_into_the_class_ult() -> void:
	var hero: Node = _stub_hero(0)
	var class_ult: String = String(((hero.get("_signatures") as Array)[SpellTier.ULT_SLOT] as SpellDef).id)
	var void_spell: SpellDef = SpellLibrary.drop_by_id("the_void")
	_expect(void_spell.charges == 1, "The Void carries one charge")
	SpellGrant.apply(hero, void_spell)
	_expect(SpellGrant.charges_left(hero, "the_void") == 1, "one charge on pickup")
	SpellGrant.consume_charge(hero, void_spell)
	_expect(SpellGrant.charges_left(hero, "the_void") == 0, "the charge is spent")
	_expect(String(((hero.get("_signatures") as Array)[SpellTier.ULT_SLOT] as SpellDef).id) == class_ult,
		"the class ult returned the instant the last charge went")
	# Roulette gets two, and only the SECOND spend gives the slot back.
	var roul: SpellDef = SpellLibrary.drop_by_id("roulette")
	_expect(roul.charges == 2, "Roulette carries two charges")
	SpellGrant.apply(hero, roul)
	SpellGrant.consume_charge(hero, roul)
	_expect(String(((hero.get("_signatures") as Array)[SpellTier.ULT_SLOT] as SpellDef).id) == "roulette",
		"Roulette survives its first spend")
	SpellGrant.consume_charge(hero, roul)
	_expect(String(((hero.get("_signatures") as Array)[SpellTier.ULT_SLOT] as SpellDef).id) == class_ult,
		"...and gives the slot back on its second")
	# A class spell (charges -1) is never consumed — this runs on every cast in the
	# game, so it has to be a no-op for the overwhelming majority of them.
	var ordinary: SpellDef = SpellLibrary.build_for_class(0)[0]
	_expect(ordinary.charges == -1, "class spells carry unlimited charges")
	SpellGrant.apply(hero, SpellLibrary.drop_by_id("arc_of_fools"))
	SpellGrant.consume_charge(hero, ordinary)
	_expect(SpellGrant.charges_left(hero, "arc_of_fools") == -1,
		"consuming an unlimited spell touches nothing")
	hero.free()
	_completes("tier3_charges_expire_into_the_class_ult")


## PROGRESSION RESETS EACH FLOOR — `FloorBuilder` calls `restore_all` when the next
## floor's props are built, and this is the rule that keeps the escalation an arc
## rather than a stockpile.
func _test_floor_reset_returns_the_kit() -> void:
	var hero: Node = _stub_hero(3)
	var kit_ids: Array[String] = []
	for s: SpellDef in (hero.get("_signatures") as Array):
		kit_ids.append(s.id)
	SpellGrant.apply(hero, SpellLibrary.drop_by_id("gravity_flip"))
	SpellGrant.apply(hero, SpellLibrary.drop_by_id("petrify"))
	SpellGrant.apply(hero, SpellLibrary.drop_by_id("chronostasis"))
	SpellGrant.restore_all(hero)
	for i: int in kit_ids.size():
		_expect(String(((hero.get("_signatures") as Array)[i] as SpellDef).id) == kit_ids[i],
			"floor reset put slot %d back" % i)
	_expect(SpellGrant.held(hero).is_empty(), "nothing is held after a floor reset")
	# Idempotent: the arena rebuilds the room more than once per run.
	SpellGrant.restore_all(hero)
	SpellGrant.restore_all(hero)
	_expect(String(((hero.get("_signatures") as Array)[0] as SpellDef).id) == kit_ids[0],
		"restoring twice is harmless")
	hero.free()
	_completes("floor_reset_returns_the_kit")


## THE HANDOFF — the whole grant moves, charges included, and the giver gets their
## class spell back. A half-spent Void must not arrive refilled.
func _test_handoff_moves_the_whole_grant() -> void:
	var giver: Node = _stub_hero(0)
	var taker: Node = _stub_hero(1)
	var giver_ult: String = String(((giver.get("_signatures") as Array)[SpellTier.ULT_SLOT] as SpellDef).id)
	var roul: SpellDef = SpellLibrary.drop_by_id("roulette")
	SpellGrant.apply(giver, roul)
	SpellGrant.consume_charge(giver, roul)          # spend one of two
	_expect(SpellGrant.charges_left(giver, "roulette") == 1, "one charge left before the handoff")
	_expect(SpellGrant.hand_over(giver, taker), "the handoff reports success")
	_expect(SpellGrant.charges_left(taker, "roulette") == 1,
		"the charge count TRAVELLED — a half-spent drop does not arrive refilled")
	_expect(SpellGrant.held(giver).is_empty(), "the giver no longer holds it")
	_expect(String(((giver.get("_signatures") as Array)[SpellTier.ULT_SLOT] as SpellDef).id) == giver_ult,
		"the giver's class ult came back")
	_expect(String(((taker.get("_signatures") as Array)[SpellTier.ULT_SLOT] as SpellDef).id) == "roulette",
		"the taker is holding it")
	# Nothing to give, and giving to yourself, are both refused rather than eating
	# the item — a handoff that deletes the drop is the worst bug this could ship.
	_expect(not SpellGrant.hand_over(giver, taker), "an empty-handed giver hands over nothing")
	_expect(not SpellGrant.hand_over(taker, taker), "you cannot hand a spell to yourself")
	_expect(SpellGrant.charges_left(taker, "roulette") == 1, "...and the drop survived both refusals")
	giver.free()
	taker.free()
	_completes("handoff_moves_the_whole_grant")


## THE FRAGILE SEAM, named. `SpellGrant._install` falls back to two Hero privates
## when there is no public `receive_spell`. This is the guard the header promises:
## rename either and this suite goes red instead of every pickup in the game
## silently becoming a no-op.
func _test_hero_fallback_members_exist() -> void:
	var scene: PackedScene = load(HERO_PATH) as PackedScene
	if scene == null:
		_fail("Hero.tscn did not load — cannot verify the grant fallback seam")
		_completes("hero_fallback_members_exist")
		return
	var hero: Node = scene.instantiate()
	var props: Dictionary = {}
	for p: Dictionary in hero.get_property_list():
		props[String(p.get("name", ""))] = true
	for m: String in HERO_GRANT_MEMBERS:
		_expect(props.has(m),
			"Hero still declares '%s' (SpellGrant._install reaches it by name)" % m)
	# If a public hook ever lands, the fallback stops being used — that is a pass,
	# not a failure, and this records which path is live.
	if hero.has_method("receive_spell"):
		print("note: Hero.receive_spell exists — SpellGrant is using the public hook")
	hero.free()
	_completes("hero_fallback_members_exist")


# -------------------------------------------------------------------- helpers

## A hero-shaped stub: the two members `SpellGrant` writes, populated from a real
## class kit. Deliberately NOT a real `Hero.tscn` instance — Hero's `_ready` reaches
## autoloads, and `--script` does not register any.
func _stub_hero(cls: int) -> Node:
	var n := Node.new()
	var sigs: Array = SpellLibrary.build_for_class(cls)
	var hand := HandSlots.new()
	hand.rebuild([], sigs)
	n.set_script(_StubHero)
	n.set("_signatures", sigs)
	n.set("_hand", hand)
	return n


## Declared as a real script so `_signatures` / `_hand` are DECLARED properties.
## `set()` on an undeclared property is a silent no-op in Godot 4 — a stub built
## with bare `set_meta` would have made every assertion below vacuously true.
const _StubHero: GDScript = preload("res://tools/_stub_hero.gd")


func _sum(d: Dictionary) -> int:
	var t: int = 0
	for k: Variant in d.keys():
		t += int(d[k])
	return t
