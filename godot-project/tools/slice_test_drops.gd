# Run: godot --headless --path godot-project --script tools/slice_test_drops.gd
#
# THE DROP ECONOMY's data layer: the drop table, the grant ledger, Tier 3 charges,
# the floor reset and the player-to-player handoff. Everything here is pure data —
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


# ---------------------------------------------------------------- 1. the table

## THE SPEC'S ONE HARD RULE about these spells: "Never in the starting kit." A drop
## that a class already carries is not a drop, it is a duplicate — and worse, it
## would make `SpellGrant` displace a spell with itself.
func _test_drops_are_never_in_a_kit() -> void:
	var drops: Array[String] = SpellLibrary.drop_ids()
	_expect(drops.size() == 10, "ten drop spells exist (6 Tier 2 + 4 Tier 3), got %d" % drops.size())
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
	_completes("roll_is_deterministic")


## RARITY IS THE BALANCE SYSTEM, so it is the thing that gets a test. These bounds
## are wide on purpose — they exist to catch a constant being fat-fingered to 1.0 or
## a gate accidentally excluding everything, not to pin the exact feel.
func _test_rarity_is_actually_rare() -> void:
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
		_expect(early != "meteor_storm" and early != "mirror_image",
			"floor %d cannot roll a gated signature (got '%s')" % [f, early])
	# BOSS DROPS. Roughly half, and never nothing-at-all across a whole tower.
	var boss: int = 0
	for f: int in range(1, floors + 1):
		if SpellDrops.roll_boss_drop(f) != "":
			boss += 1
	var brate: float = float(boss) / float(floors)
	_expect(brate > 0.3 and brate < 0.7,
		"a guardian drops a Tier 3 roughly half the time (got %.2f)" % brate)
	_completes("rarity_is_actually_rare")


## The common band must be DERIVED from the class reserve, not hand-listed. That is
## what stops the drop table drifting out of sync with the kits.
func _test_common_band_is_the_class_reserve() -> void:
	var reserve: Array[String] = []
	for cls: int in range(SpellLibrary.CLASS_KITS.size()):
		for s: SpellDef in SpellLibrary.reserve_for_class(cls):
			if not reserve.has(s.id):
				reserve.append(s.id)
	_expect(reserve.size() >= 4, "the class reserve is non-trivial (%d spells)" % reserve.size())
	# The four the handoff notes name as explicitly reserved for the pickup pool.
	for id: String in ["rift_dagger", "creeping_shade", "rock_pillar", "ice_wall"]:
		_expect(reserve.has(id), "'%s' is still in the reserved pickup pool" % id)
	# Every common-band roll resolves to a real spell — a drop id that resolves to
	# null is an invisible pickup, the one failure nobody would ever report.
	for f: int in range(1, 120):
		var id2: String = SpellDrops.roll_floor_drop(f)
		if id2 == "":
			continue
		_expect(SpellDrops.spell_for_id(id2) != null,
			"floor %d's drop '%s' resolves to a real SpellDef" % [f, id2])
	_completes("common_band_is_the_class_reserve")


# ------------------------------------------------------------------ 2. the hand

## THE HAND DOES NOT GROW. Three buttons is the whole mobile control scheme; a
## fourth spell is a spell the player cannot press.
func _test_hand_replaces_never_grows() -> void:
	var hand := HandSlots.new()
	var kit: Array = SpellLibrary.build_for_class(0)
	hand.rebuild([], kit)
	var before: int = hand.slots.size()
	_expect(hand.spell_count() == SpellTier.SLOT_COUNT,
		"a fresh hand carries SLOT_COUNT spells (got %d)" % hand.spell_count())
	var drop: SpellDef = SpellLibrary.drop_by_id("petrify")
	_expect(hand.replace_spell(0, drop), "a drop lands in slot 0")
	_expect(hand.slots.size() == before, "the carousel did NOT grow (%d -> %d)"
		% [before, hand.slots.size()])
	_expect(String((hand.spell_at(0) as SpellDef).id) == "petrify", "slot 0 now holds the drop")
	# FISTS stays at index 0 — a hero must never be left with no melee option.
	_expect(int(hand.slots[0]["kind"]) == HandSlots.Kind.FISTS, "fists still occupy hand index 0")
	# The drop arrives READY. Inheriting the displaced spell's cooldown would mean a
	# pickup that is dark for eight seconds for reasons nothing on screen explains.
	hand.start_cooldown(hand.spell_slot_index(1), 9.0)
	hand.replace_spell(1, SpellLibrary.drop_by_id("gravity_flip"))
	_expect(hand.is_ready(hand.spell_slot_index(1)), "a freshly granted slot is READY")
	_expect(not hand.replace_spell(99, drop), "an out-of-range slot refuses rather than writing past the end")
	_expect(not hand.replace_spell(0, null), "a null spell is refused")
	_completes("hand_replaces_never_grows")


## A grant remembers what it displaced and puts it back. Tier 2 takes a non-ult
## slot, Tier 3 takes the ult slot.
func _test_grant_displaces_and_restores() -> void:
	var hero: Node = _stub_hero(0)
	var kit: Array = (hero.get("_signatures") as Array).duplicate()
	var t2: SpellDef = SpellLibrary.drop_by_id("blood_pact")
	var nth: int = SpellGrant.apply(hero, t2)
	_expect(nth >= 0 and nth < SpellTier.ULT_SLOT,
		"a Tier 2 takes a NON-ult slot (got %d)" % nth)
	_expect(String(((hero.get("_signatures") as Array)[nth] as SpellDef).id) == "blood_pact",
		"the hero's signature list carries the drop")
	_expect(String(((hero.get("_hand") as HandSlots).spell_at(nth) as SpellDef).id) == "blood_pact",
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
	SpellGrant.apply(hero, SpellLibrary.drop_by_id("petrify"))
	SpellGrant.consume_charge(hero, ordinary)
	_expect(SpellGrant.charges_left(hero, "petrify") == -1,
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
	SpellGrant.apply(hero, SpellLibrary.drop_by_id("mirror_image"))
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
