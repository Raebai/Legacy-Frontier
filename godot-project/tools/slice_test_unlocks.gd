extends SceneTree
## UNLOCK STATE — "what is unlockable and what isnt … and how to unlock it".
##
## Maker, 2026-09-05, about BOTH the grimoire and the armoury. `Progression.gear_state` /
## `spell_state` are the one place that answers it; the two screens only draw the answer.
##
## ⚠ THIS SUITE NEVER READS `ALL_GEAR_UNLOCKED`. That flag is the escape hatch (same shape
## as `ALL_CLASSES_UNLOCKED`), and a suite that took its word for things would go green on
## the day someone flipped it and silently stopped testing the three states entirely. Every
## case below drives the pure function with explicit floor / level / class arguments, so
## the states stay provable whichever way the flag is set — which is exactly what the
## instruction "make sure the three states are real and testable when it is false" asks.
##
## Run: godot --headless --path godot-project --script tools/slice_test_unlocks.gd

const HELD: int = Progression.Owned.HELD
const EARNABLE: int = Progression.Owned.EARNABLE
const CLASS_LOCKED: int = Progression.Owned.CLASS_LOCKED


func _init() -> void:
	var failed: int = 0
	failed += _test_every_offered_piece_has_a_row()
	failed += _test_the_three_states_are_all_reachable()
	failed += _test_every_slot_opens_with_something_free()
	failed += _test_depth_and_level_are_thresholds_not_spends()
	failed += _test_a_class_piece_follows_the_class()
	failed += _test_spells_gate_by_shelf_never_by_class()
	failed += _test_an_equipped_spell_is_never_confiscated()
	failed += _test_every_locked_row_states_a_verb()
	if failed == 0:
		print("Unlock tests: all PASS")
	else:
		printerr("Unlock tests: %d FAILED" % failed)
	quit(1 if failed > 0 else 0)


## ⚠ A SILENT-DEFAULT HOLE IS HOW A REGISTRY STARTS LYING. `gear_state` fails OPEN for an
## id with no row (an item nobody can ever reach is worse than one anybody can), so the
## coverage has to be asserted here or a new piece would quietly ship as free forever.
func _test_every_offered_piece_has_a_row() -> int:
	var failed: int = 0
	var n: int = 0
	for slot: String in GearAbilities.PLACEHOLDER_SLOTS:
		for kind: String in GearAbilities.PLACEHOLDER_SLOTS[slot]:
			failed += _expect(Progression.GEAR_UNLOCK.has(kind),
				"'%s' has an unlock row - without one it is free forever and nobody notices" % kind)
			n += 1
	# An invariant true of an empty sweep is not an invariant.
	failed += _expect(n == 19, "all nineteen offered pieces were swept (got %d)" % n)
	# ...and nothing in the table is unreachable from the menu.
	for kind2: String in Progression.GEAR_UNLOCK:
		var offered: bool = false
		for slot2: String in GearAbilities.PLACEHOLDER_SLOTS:
			if (GearAbilities.PLACEHOLDER_SLOTS[slot2] as Array).has(kind2):
				offered = true
		failed += _expect(offered, "unlock row '%s' names a piece the armoury actually offers" % kind2)
	return failed


func _test_the_three_states_are_all_reachable() -> int:
	var failed: int = 0
	# A fresh climber: floor 1, level 1, Arcanist.
	failed += _expect(Progression.gear_state("pl_veilhood", 1, 1, 0) == HELD,
		"the free helm is HELD on a fresh save")
	failed += _expect(Progression.gear_state("pl_crown_of_hours", 1, 1, 0) == EARNABLE,
		"a floor-10 helm is EARNABLE at floor 1")
	failed += _expect(Progression.gear_state("pl_stormcoat", 30, 30, 0) == CLASS_LOCKED,
		"another class's coat is CLASS_LOCKED however deep you climbed")
	return failed


## ⚠ THE SHAPE OF THE SPREAD IS THE DESIGN. Every slot opens with one free piece, so the
## armoury is never a wall of grey on a fresh save — that is what makes it a shelf rather
## than a paywall, and it is the property most likely to be broken by a retune.
func _test_every_slot_opens_with_something_free() -> int:
	var failed: int = 0
	for slot: String in GearAbilities.PLACEHOLDER_SLOTS:
		var any_free: bool = false
		for kind: String in GearAbilities.PLACEHOLDER_SLOTS[slot]:
			if Progression.gear_state(kind, 1, 1, 0) == HELD:
				any_free = true
		failed += _expect(any_free, "slot '%s' has at least one piece a brand-new climber holds" % slot)
	return failed


## Depth and level are THRESHOLDS you pass, never a resource you burn — that is what keeps
## this compatible with the spec's Skill Points (the one spendable currency, tree only).
## Passing the threshold flips the state and passing it further never flips it back.
func _test_depth_and_level_are_thresholds_not_spends() -> int:
	var failed: int = 0
	failed += _expect(Progression.gear_state("pl_ironmarch", 4, 30, 0) == EARNABLE,
		"floor-5 greave still EARNABLE at floor 4")
	failed += _expect(Progression.gear_state("pl_ironmarch", 5, 1, 0) == HELD,
		"floor-5 greave is HELD the moment floor 5 is reached")
	failed += _expect(Progression.gear_state("pl_ironmarch", 40, 1, 0) == HELD,
		"and it stays HELD forever after - a threshold, not a spend")
	failed += _expect(Progression.gear_state("pl_thornmail", 40, 5, 0) == EARNABLE,
		"a LEVEL row ignores depth entirely - the two axes are separate")
	failed += _expect(Progression.gear_state("pl_thornmail", 1, 6, 0) == HELD,
		"...and level 6 alone buys it, from floor 1")
	return failed


## A class piece is that class's IDENTITY, not a trophy: you hold it while you are them.
func _test_a_class_piece_follows_the_class() -> int:
	var failed: int = 0
	failed += _expect(Progression.gear_state("pl_stormcoat", 1, 1, 6) == HELD,
		"the Stormcaller holds the Stormcoat from floor 1")
	failed += _expect(Progression.gear_state("pl_stormcoat", 1, 1, 5) == CLASS_LOCKED,
		"the Cryomancer next door does not")
	failed += _expect(Progression.gear_state("pl_sunmote", 1, 1, 4) == HELD,
		"the Cleric holds the Sunmote")
	# ⚠ AND IT SPENDS NO PICK. The banked guardian pick buys exactly one thing, a CLASS.
	# A gear table that quietly consumed one would break the mechanic it borrowed from.
	failed += _expect(not Progression.GEAR_UNLOCK.values().any(func(c): return (c as Dictionary).has("pick")),
		"no gear row spends a banked class pick")
	return failed


## ⚠ THE MAKER'S STANDING RULING: *"it shouldnt prevent any player for taking any spell"*.
## So the grimoire gates by SHELF and DEPTH and never by class — `CLASS_LOCKED` is
## deliberately unreachable for a spell, and this is the line that keeps it that way.
func _test_spells_gate_by_shelf_never_by_class() -> int:
	var failed: int = 0
	for f: int in [1, 3, 5, 12, 40]:
		for t: int in Progression.SPELL_UNLOCK_FLOOR.size():
			failed += _expect(Progression.spell_state(t, f) != CLASS_LOCKED,
				"no spell is ever CLASS_LOCKED (tier %d at floor %d)" % [t, f])
	failed += _expect(Progression.spell_state(SpellTier.Tier.QUICK, 1) == HELD,
		"the shallow shelf is HELD from the first step")
	# ⚠ HEAVY IS HELD FROM FLOOR 1 AND THAT IS THE POINT, not an oversight. Sixteen of
	# the eighteen pool spells derive as ULT, so gating HEAVY too would have opened the
	# grimoire on eighteen locked rows — see the measurement above SPELL_UNLOCK_FLOOR.
	failed += _expect(Progression.spell_state(SpellTier.Tier.HEAVY, 1) == HELD,
		"a HEAVY is HELD on floor 1 - the body of the library is never walled")
	failed += _expect(Progression.spell_state(SpellTier.Tier.ULT, 4) == EARNABLE,
		"the finisher shelf IS gated - one row a fresh climber can see and cannot take")
	failed += _expect(Progression.spell_state(SpellTier.Tier.ULT, 5) == HELD, "ult at floor 5")
	# The two shelves must not collapse into each other: if a retune ever made them equal,
	# the grimoire would show one state and the "how do I unlock it" question comes back.
	failed += _expect(Progression.spell_unlock_floor(SpellTier.Tier.ULT)
			> Progression.spell_unlock_floor(SpellTier.Tier.HEAVY),
		"the ult shelf is strictly deeper than the heavy one")
	return failed


## ⚠ A GATE THAT RETROACTIVELY CONFISCATES SOMETHING READS AS A LOST SAVE. Anything already
## in the hand is grandfathered, whatever the table says.
func _test_an_equipped_spell_is_never_confiscated() -> int:
	var failed: int = 0
	failed += _expect(Progression.spell_state(SpellTier.Tier.ULT, 1, true) == HELD,
		"an ult already in the hand survives a table that would not grant it")
	failed += _expect(Progression.spell_state(SpellTier.Tier.ULT, 1, false) == EARNABLE,
		"...and the same spell NOT in the hand is still gated - the grandfather is the only difference")
	return failed


## The maker asked *how* to unlock it. "Locked" answers nothing; a VERB does. Every state
## that refuses must hand the UI a non-empty sentence, or the row is dim for no stated reason.
func _test_every_locked_row_states_a_verb() -> int:
	var failed: int = 0
	var names: Array = ClassInfo.names()
	for kind: String in Progression.GEAR_UNLOCK:
		var verb: String = Progression.gear_unlock_verb(kind, names)
		failed += _expect(verb != "", "'%s' states a verb, not merely a lock" % kind)
		failed += _expect(verb.length() <= 44,
			"'%s' verb fits a phone row (%d chars)" % [kind, verb.length()])
	for t: int in Progression.SPELL_UNLOCK_FLOOR.size():
		failed += _expect(Progression.spell_unlock_verb(t) != "", "tier %d states a verb" % t)
	# A class row names WHO, because "another class" is not an instruction.
	failed += _expect(Progression.gear_unlock_verb("pl_stormcoat", names).contains("Stormcaller"),
		"a class-locked row names the class by name")
	return failed


func _expect(cond: bool, msg: String) -> int:
	if cond:
		return 0
	printerr("FAIL: %s" % msg)
	return 1
