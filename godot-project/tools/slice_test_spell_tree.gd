# Run: godot --headless --path godot-project --script tools/slice_test_spell_tree.gd
# The spell trees. Pure data + pure functions, so this needs no scene and no disk.
# It asserts the trees against the REAL 49-spell catalog and the REAL CLASS_KITS,
# which is how five bad links in the design doc were caught before any UI existed.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion
# sentinel so a test that aborts part-way fails BY ABSENCE.

const TESTS: Array[String] = [
	"every_spell_in_every_tree_is_real",
	"every_native_matches_the_authored_kit",
	"no_class_can_buy_the_same_spell_twice",
	"ults_are_never_linked",
	"node_ids_are_stable_and_parseable",
	"the_starting_hand_is_free",
	"a_tree_is_about_one_climb",
	"you_cannot_buy_what_you_cannot_afford",
	"buying_grows_options_never_the_hand",
	"links_reach_outside_the_class",
	"junk_input_is_refused_not_crashed",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const CLASS_COUNT: int = 9


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_every_spell_in_every_tree_is_real()
	_test_every_native_matches_the_authored_kit()
	_test_no_class_can_buy_the_same_spell_twice()
	_test_ults_are_never_linked()
	_test_node_ids_are_stable_and_parseable()
	_test_the_starting_hand_is_free()
	_test_a_tree_is_about_one_climb()
	_test_you_cannot_buy_what_you_cannot_afford()
	_test_buying_grows_options_never_the_hand()
	_test_links_reach_outside_the_class()
	_test_junk_input_is_refused_not_crashed()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Spell tree tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Spell tree tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## ⚠ THE ONE THAT MATTERS MOST. A tree node naming a spell that does not exist
## would be a dead button in the UI, and the failure mode is silent: `by_id`
## returns null and the node simply grants nothing. Asserted against the live
## catalog, so deleting or renaming a spell fails HERE rather than in a player's
## hands three floors up.
func _test_every_spell_in_every_tree_is_real() -> void:
	var checked: int = 0
	for c: int in SpellTree.TREES.size():
		for role: String in SpellTree.ROLES:
			var branch: Dictionary = SpellTree.TREES[c].get(role, {})
			_expect(not branch.is_empty(), "class %d has a `%s` branch" % [c, role])
			for key: String in ["native", "linked"]:
				var id: String = String(branch.get(key, ""))
				if id == "":
					continue
				_expect(SpellLibrary.by_id(id) != null,
					"class %d %s.%s names a REAL spell (`%s` is not in the catalog)" % [c, role, key, id])
				checked += 1
	# NON-VACUOUS: "every spell is real" is trivially true of an empty tree.
	# 9 classes x (5 natives + 4 links) = 81.
	_expect(checked == 81, "all 81 tree entries were checked (got %d)" % checked)
	_completes("every_spell_in_every_tree_is_real")


## A branch's NATIVE must be the class's own authored kit spell for that role. If
## these drift, the tree is selling a class a spell it does not actually own, and
## the free-hand calculation below silently starts charging for the wrong things.
func _test_every_native_matches_the_authored_kit() -> void:
	for c: int in SpellTree.TREES.size():
		var kit: Dictionary = SpellLibrary.kit_for_class(c)
		_expect(not kit.is_empty(), "class %d has an authored kit" % c)
		for role: String in SpellTree.ROLES:
			var branch: Dictionary = SpellTree.TREES[c].get(role, {})
			_expect(String(branch.get("native", "")) == String(kit.get(role, "")),
				"class %d's %s native is its kit spell (tree says `%s`, kit says `%s`)"
				% [c, role, String(branch.get("native", "")), String(kit.get(role, ""))])
	_completes("every_native_matches_the_authored_kit")


## ⚠ THIS IS THE TEST THAT EARNED ITS KEEP BEFORE ANY UI EXISTED. Five of the
## design doc's mock trees linked a class to a spell it already owned as a native
## somewhere else in the SAME tree — the Shadowblade to `blink_strike`, the Brawler
## to `boulder_hurl`, the Cryomancer to `ice_wall`, the Warlock twice. A node that
## grants a spell you already have is a button that spends 2 points and does
## nothing, and it would look completely fine in a screenshot.
func _test_no_class_can_buy_the_same_spell_twice() -> void:
	for c: int in SpellTree.TREES.size():
		var seen: Dictionary = {}
		for n: String in SpellTree.nodes_for_class(c):
			var s: String = SpellTree.spell_of(n)
			_expect(not seen.has(s),
				"class %d offers `%s` twice (%s and %s) — the second is 2 points for nothing"
				% [c, s, String(seen.get(s, "?")), n])
			seen[s] = n
	_completes("no_class_can_buy_the_same_spell_twice")


## Your ult is why you picked the class. A tradable ult is a recolour with extra steps.
func _test_ults_are_never_linked() -> void:
	for c: int in SpellTree.TREES.size():
		var branch: Dictionary = SpellTree.TREES[c].get(SpellTree.ULT_ROLE, {})
		_expect(String(branch.get("linked", "")) == "",
			"class %d's ULT has no link — the class fantasy is not for sale" % c)
		_expect(String(branch.get("native", "")) != "", "class %d still HAS an ult" % c)
		# …and no other class's tree may reach it either.
		var my_ult: String = String(branch.get("native", ""))
		for other: int in SpellTree.TREES.size():
			if other == c:
				continue
			for role: String in SpellTree.ROLES:
				var ob: Dictionary = SpellTree.TREES[other].get(role, {})
				_expect(String(ob.get("linked", "")) != my_ult,
					"class %d cannot LINK to class %d's ult `%s`" % [other, c, my_ult])
	_completes("ults_are_never_linked")


## Node ids are what go in the save. They must be derived from POSITION, never from
## a spell name — this file has already had to re-point five links, and a name-keyed
## id would have orphaned every save that had bought one.
func _test_node_ids_are_stable_and_parseable() -> void:
	var seen: Dictionary = {}
	for c: int in CLASS_COUNT:
		for n: String in SpellTree.nodes_for_class(c):
			_expect(not seen.has(n), "node id `%s` is unique across every tree" % n)
			seen[n] = true
			_expect(SpellTree.spell_of(n) != "", "node `%s` resolves to a spell" % n)
			_expect(SpellTree.cost_of(n) == (SpellTree.COST_LINKED if n.ends_with(":linked")
					else SpellTree.COST_NATIVE), "node `%s` costs the right amount" % n)
	_expect(seen.size() == 81, "81 unique node ids across nine classes (got %d)" % seen.size())
	# A LINK COSTS MORE THAN A NATIVE — the price IS the "you went and got this".
	_expect(SpellTree.COST_LINKED > SpellTree.COST_NATIVE,
		"a linked node costs more than a native one")
	_completes("node_ids_are_stable_and_parseable")


## The three roles you already carry are already yours. Charging for a spell in your
## opening hand means a fresh climber's first purchase buys them nothing.
func _test_the_starting_hand_is_free() -> void:
	for c: int in CLASS_COUNT:
		var free: Array[String] = SpellTree.free_nodes(c)
		_expect(free.size() == SpellTier.SLOT_COUNT,
			"class %d starts with %d free nodes (got %d)" % [c, SpellTier.SLOT_COUNT, free.size()])
		for n: String in free:
			_expect(SpellTree.is_free(n), "`%s` is free" % n)
			_expect(SpellTree.is_unlocked(n, []), "…and therefore unlocked with nothing bought")
			_expect(not SpellTree.can_buy(n, c, 99, []), "…and cannot be bought again")
			# Free nodes are NATIVES. A link is never in an opening hand.
			_expect(not n.ends_with(":linked"), "a free node is always a native (`%s`)" % n)
		# A fresh climber can bind exactly their authored three and nothing else.
		_expect(SpellTree.bindable_spells(c, []).size() == SpellTier.SLOT_COUNT,
			"class %d binds exactly its authored hand before spending anything" % c)
	_completes("the_starting_hand_is_free")


## Mastering a class and climbing the tower once should be the same size of
## commitment. 5 natives (3 free) + 4 links = 10 points = level 11; one full climb
## lands at level 12. If either curve moves this is where it shows.
func _test_a_tree_is_about_one_climb() -> void:
	for c: int in CLASS_COUNT:
		var cost: int = SpellTree.total_cost(c)
		_expect(cost == 10, "class %d's whole tree costs 10 points (got %d)" % [c, cost])
		# The level at which the last node is affordable.
		var level_to_finish: int = cost + 1     # 1 point per level, level 1 gives none
		_expect(level_to_finish >= 8 and level_to_finish <= 16,
			"class %d completes near a full climb (level %d)" % [c, level_to_finish])
	_expect(SpellTree.points_earned(1) == 0, "level 1 has earned no points")
	_expect(SpellTree.points_earned(11) == 10, "level 11 has earned ten")
	_completes("a_tree_is_about_one_climb")


func _test_you_cannot_buy_what_you_cannot_afford() -> void:
	var linked: String = SpellTree.node_id(0, "damage", true)   # 2 points
	_expect(not SpellTree.can_buy(linked, 0, 1, []), "level 1 cannot afford a 2-point link")
	_expect(not SpellTree.can_buy(linked, 0, 2, []), "level 2 (1 point) still cannot")
	_expect(SpellTree.can_buy(linked, 0, 3, []), "level 3 (2 points) can")
	# Spending drains the balance.
	_expect(SpellTree.points_spent([linked]) == 2, "a link costs 2 when owned")
	_expect(SpellTree.points_available(3, [linked]) == 0, "…and the balance is spent")
	_expect(not SpellTree.can_buy(SpellTree.node_id(0, "control", true), 0, 3, [linked]),
		"a second link is unaffordable on a spent balance")
	# A FREE node never charges, however many are owned.
	var free_owned: Array = SpellTree.free_nodes(0)
	_expect(SpellTree.points_spent(free_owned) == 0,
		"the opening hand costs nothing even if it lands in `owned`")
	# The paid NATIVES (the two roles you do not start with) cost 1.
	var paid_natives: int = 0
	for n: String in SpellTree.nodes_for_class(0):
		if not n.ends_with(":linked") and not SpellTree.is_free(n):
			paid_natives += 1
			_expect(SpellTree.cost_of(n) == 1, "an unowned native costs 1 (`%s`)" % n)
	_expect(paid_natives == 2, "a class has exactly two natives it does not start with (got %d)" % paid_natives)
	_completes("you_cannot_buy_what_you_cannot_afford")


## ⚠ THE DESIGN PROMISE, ASSERTED: the tree grows your OPTIONS and never your HAND.
## The 3-of-5 carry is the existing balance surface and `slot_accepts_ult` protects
## it; a tree that quietly widened the hand would let a player carry five damage
## spells and no answer, which is not a build, it is a hole.
func _test_buying_grows_options_never_the_hand() -> void:
	var owned: Array = []
	var before: int = SpellTree.bindable_spells(0, owned).size()
	for n: String in SpellTree.nodes_for_class(0):
		if not SpellTree.is_free(n):
			owned.append(n)
	var after: int = SpellTree.bindable_spells(0, owned).size()
	_expect(after > before, "buying the tree grows what you can BIND (%d -> %d)" % [before, after])
	_expect(after == 9, "a fully-bought Arcanist can bind nine distinct spells (got %d)" % after)
	# THE HAND ITSELF IS UNCHANGED — still three slots, whatever is bought.
	_expect(int(SpellTier.SLOT_COUNT) == 3, "the hand is three, and the tree does not touch it")
	_expect(SpellTree.free_nodes(0).size() == 3, "…and the opening hand is still three")
	_completes("buying_grows_options_never_the_hand")


## "Cross-class links based on semi relevant links" — the links must actually LEAVE
## the class, or the tree is nine isolated ladders and the maker's ask is unmet.
func _test_links_reach_outside_the_class() -> void:
	var reached_out: int = 0
	for c: int in CLASS_COUNT:
		var own_kit: Dictionary = SpellLibrary.kit_for_class(c)
		var mine: Array = own_kit.values()
		for role: String in SpellTree.ROLES:
			var link: String = String((SpellTree.TREES[c].get(role, {}) as Dictionary).get("linked", ""))
			if link == "":
				continue
			if not mine.has(link):
				reached_out += 1
	# Most links must be genuinely foreign. Some legitimately are not — a spell can
	# fill a DIFFERENT role than the one the class authors it in — so this asserts a
	# strong majority rather than all, and fails loudly if the trees turn inward.
	_expect(reached_out >= 27,
		"at least 27 of the 36 links reach a spell outside the class's own kit (got %d)" % reached_out)
	_completes("links_reach_outside_the_class")


func _test_junk_input_is_refused_not_crashed() -> void:
	_expect(SpellTree.spell_of("") == "", "an empty node id resolves to nothing")
	_expect(SpellTree.spell_of("garbage") == "", "an unparseable node id resolves to nothing")
	_expect(SpellTree.spell_of("99:damage:native") == "", "an off-the-end class resolves to nothing")
	_expect(SpellTree.spell_of("0:nosuchrole:native") == "", "an unknown role resolves to nothing")
	_expect(SpellTree.nodes_for_class(-1).is_empty(), "a negative class has no nodes")
	_expect(SpellTree.nodes_for_class(99).is_empty(), "an off-the-end class has no nodes")
	_expect(not SpellTree.can_buy("garbage", 0, 99, []), "junk cannot be bought")
	_expect(not SpellTree.can_buy(SpellTree.node_id(1, "damage", true), 0, 99, []),
		"a node from ANOTHER class's tree cannot be bought")
	_expect(SpellTree.points_spent(["", "garbage"]) == 0, "junk in `owned` costs nothing")
	_expect(SpellTree.points_earned(-5) == 0, "a junk level earns nothing")
	_expect(SpellTree.points_available(1, ["0:damage:linked"]) == 0,
		"an over-spent balance floors at 0 rather than going negative")
	_completes("junk_input_is_refused_not_crashed")
