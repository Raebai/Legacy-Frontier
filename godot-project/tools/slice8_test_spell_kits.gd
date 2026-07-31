# Run: Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice8_test_spell_kits.gd
#
# Slice 8: the SPELL DATA suite. Everything here pins a fix that was made by
# editing numbers and strings in SpellLibrary.gd — the class of change that leaves
# no stack trace when it silently regresses, which is exactly why it needs a test.
#
# What it pins, and the bug each one caught:
#   1. TYPING — every spell declares a real element, and its `effect` is that
#      element's particle language. Judgment and Heaven's Verdict shipped with no
#      element at all, so SpellCaster.resolve_element() guessed LIGHTNING from
#      effect=="holy" and StarConvergence applied no ailment whatsoever.
#   2. KIT SHAPE — every class is exactly 4 spells + 1 ult, the four are non-ULT
#      and the fifth is ULT per SpellTier, and the four roles are distinct.
#   3. BEAM REACH — every beam is castable from a real class kit. Three of five
#      used to exist only in the review harness while the class cards advertised
#      them ("why can I only see one or two").
#   4. BEAM SHELVES — the family spans more than one SpellTier shelf, so a beam
#      can out-weigh another beam and a barrier can stop one. All-ULT made
#      `overpower`, `carve` and `barrier_blocks` unreachable between beams.
#   5. NO BORROWED NAMES — the IP rename cannot quietly come back.
#   6. STALE DESCRIPTIONS — the four rewritten blurbs cannot drift back to
#      describing behaviour that was deleted.
#
# Pure data: no scenes, no autoloads, no frames needed. SpellLibrary / SpellDef /
# SpellTier / Elements are all plain RefCounted+Resource classes, so this runs
# straight off SceneTree._process without instancing anything.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"element_typing",
	"kit_shape",
	"kit_roles_distinct",
	"beams_reachable",
	"beam_shelf_spread",
	"no_banned_names",
	"descriptions_match_behaviour",
]

var _fails: int = 0
var _completed: Dictionary = {}

## Read for the banned-string sweep. Scanning the SOURCE (rather than the built
## SpellDefs) is deliberate: a borrowed name can hide in a comment or a helper
## name where no runtime value would ever surface it.
const LIBRARY_PATH: String = "res://scripts/combat/SpellLibrary.gd"

## Names lifted from other properties. Mechanics are not ownable; these are.
const BANNED: Array[String] = ["chidori", "zoltraak", "frieren", "naruto"]

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_element_typing()
	_test_kit_shape()
	_test_kit_roles_distinct()
	_test_beams_reachable()
	_test_beam_shelf_spread()
	_test_no_banned_names()
	_test_descriptions_match_behaviour()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice8 spell-kit tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice8 spell-kit tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# --------------------------------------------------------------- 1. typing
## THE typing invariant: a spell's `effect` (which particle language it speaks)
## must be its `element`'s own language. The two are separate fields for a reason
## — Colossus Pillar has to override the holy default it inherits from `_ray()` —
## and separate fields drift. When they disagree the spell LOOKS like one element
## and REACTS as another, because `effect` drives the spectacle skin while
## `element` drives ailments and every ReactionTable predicate.
##
## The element >= 0 half is not cosmetic either. SpellCaster.resolve_element()
## falls back to guessing from `effect` when the element is missing (its "holy"
## arm answers LIGHTNING, from before HOLY was an element), and
## SpellReactor.register() refuses to register an element-less effect at all — so
## a spell with no element is a spell with the wrong ailment AND no reactions.
func _test_element_typing() -> void:
	for s: SpellDef in SpellLibrary.build_all():
		_expect(s.element >= 0,
			"%s declares a real element (not the -1 default)" % s.id)
		if s.element < 0:
			continue
		_expect(s.effect == Elements.effect_name(s.element),
			"%s: effect '%s' matches element %s ('%s')" % [
				s.id, s.effect, Elements.display_name(s.element),
				Elements.effect_name(s.element)])
	# The two that were actually broken, named so the regression is unmistakable.
	var by_id: Dictionary = _by_id()
	_expect(int(by_id["judgment"].element) == int(Elements.Element.HOLY),
		"Judgment is HOLY (was falling back to LIGHTNING via effect=='holy')")
	_expect(int(by_id["heavens_verdict"].element) == int(Elements.Element.HOLY),
		"Heaven's Verdict is HOLY (was applying no ailment at all)")
	# ...and the one that was already fixed by hand, so it stays fixed.
	_expect(int(by_id["colossus_pillar"].element) == int(Elements.Element.EARTH),
		"Colossus Pillar keeps its EARTH override over _ray()'s holy default")
	_completes("element_typing")


# ------------------------------------------------------------ 2. kit shape
## Four spells plus one ult, and the shelves have to agree with the slots. Tier is
## DERIVED from cast time / cooldown / MP, so this is what stops a retune from
## quietly promoting a spell-slot pick into an ult (or demoting an ult into a jab)
## without anyone noticing until a playtest.
## ⚠ THE HAND IS THREE SPELLS NOW, not five. The right thumb has three buttons, so
## three is how many a class can hold; the other two authored roles are not deleted,
## they become that class's share of the Tier 2 / Tier 3 drop pool
## (`SpellLibrary.reserve_for_class`). Everything below is written against
## `SpellTier.SLOT_COUNT` rather than a literal so the next change to the control
## scheme moves one constant and this suite follows it.
func _test_kit_shape() -> void:
	for cls: int in range(ClassInfo.count()):
		var kit: Array = SpellLibrary.build_for_class(cls)
		_expect(kit.size() == SpellTier.SLOT_COUNT,
			"class %d holds exactly %d spells (got %d)"
				% [cls, SpellTier.SLOT_COUNT, kit.size()])
		if kit.size() != SpellTier.SLOT_COUNT:
			continue
		for i: int in SpellTier.SLOT_COUNT:
			var tier: int = SpellTier.of(kit[i])
			var is_ult: bool = tier == SpellTier.Tier.ULT
			_expect(is_ult == SpellTier.slot_accepts_ult(i),
				"class %d slot %d holds a %s and slot_accepts_ult is %s (%s)" % [
					cls, i, SpellTier.display_name(tier),
					SpellTier.slot_accepts_ult(i), kit[i].id])
		# The carried roles have to be roles the class actually authored, or the hand
		# silently comes up short — `build_for_class` drops an unresolvable slot rather
		# than crashing mid-configure, which is the right runtime behaviour and exactly
		# the failure a test has to be the one to notice.
		var authored: Dictionary = SpellLibrary.kit_for_class(cls)
		var carried: Array = SpellLibrary.slot_roles_for_class(cls)
		_expect(carried.size() == SpellTier.SLOT_COUNT,
			"class %d names %d carried roles" % [cls, SpellTier.SLOT_COUNT])
		for role: String in carried:
			_expect(authored.has(role),
				"class %d carries the '%s' role and its CLASS_KITS row authors it" % [cls, role])
		_expect(carried[carried.size() - 1] == "ult",
			"class %d's LAST carried slot is the ult (got '%s')"
				% [cls, carried[carried.size() - 1]])
		# ...and nothing is lost: carried + reserve == the whole authored kit.
		_expect(carried.size() + SpellLibrary.reserve_for_class(cls).size()
				== SpellLibrary.ROLE_ORDER.size(),
			"class %d's carried hand plus its drop-pool reserve is the whole authored kit" % cls)
	_completes("kit_shape")


## Four variations of one idea is a kit with one answer. The roles live in
## SpellLibrary.CLASS_KITS as data precisely so this can be checked, and a role is
## per-KIT rather than per-spell — Shadow Step is the Arcanist's escape and the
## Shadowblade's finisher, which is a feature, not a contradiction.
func _test_kit_roles_distinct() -> void:
	for cls: int in range(ClassInfo.count()):
		var kit: Dictionary = SpellLibrary.kit_for_class(cls)
		_expect(not kit.is_empty(), "class %d has an authored kit" % cls)
		if kit.is_empty():
			continue
		var seen: Array[String] = []
		for role: String in SpellLibrary.ROLE_ORDER:
			_expect(kit.has(role),
				"class %d kit fills the '%s' role" % [cls, role])
			var id: String = String(kit.get(role, ""))
			_expect(not seen.has(id),
				"class %d does not use '%s' for two roles" % [cls, id])
			seen.append(id)
	_completes("kit_roles_distinct")


# --------------------------------------------------------- 3+4. the beams
## Every beam is castable by SOMEBODY. This is the maker's "where are those cool
## heavy attack beams" made mechanical: a beam that is in build_all() but in no
## class kit is a beam that exists only in the review sandbox.
func _test_beams_reachable() -> void:
	var equipped: Array[String] = _all_equipped_ids()
	var beams: int = 0
	for s: SpellDef in SpellLibrary.build_all():
		if int(s.kind) != int(SpellDef.Kind.BEAM):
			continue
		beams += 1
		_expect(equipped.has(s.id),
			"beam '%s' is reachable from a real class kit" % s.id)
	_expect(beams == 5, "the beam family is still five spells (got %d)" % beams)
	_completes("beams_reachable")


## The beams must not all sit on one shelf. SpellTier's shelf is also the spell's
## CLASH WEIGHT: equal weights annihilate, a heavier one overpowers, and a barrier
## stops what it is not outmatched by. When every beam shared cast_time = 1.0 they
## were all ULT, so beam-vs-beam was ALWAYS mutual annihilation and beam-vs-wall
## was ALWAYS a breach — `overpower`, `carve` and `barrier_blocks` were authored
## rows no pair of hero beams could ever reach.
##
## The lower bound is HEAVY, never QUICK: QUICK requires cast_time <= 0.01, i.e.
## no levitating channel, and a beam with no channel has no telegraph — which
## breaks the locked "every ability needs a real tell and a dodge window" rule.
func _test_beam_shelf_spread() -> void:
	var shelves: Dictionary = {}
	for s: SpellDef in SpellLibrary.build_all():
		if int(s.kind) != int(SpellDef.Kind.BEAM):
			continue
		var tier: int = SpellTier.of(s)
		shelves[tier] = int(shelves.get(tier, 0)) + 1
		_expect(tier != SpellTier.Tier.QUICK,
			"beam '%s' keeps a real windup (QUICK would mean no telegraph)" % s.id)
		_expect(s.cast_time > 0.0,
			"beam '%s' still levitates + channels (cast_time > 0)" % s.id)
	_expect(shelves.size() >= 2,
		"the beam family spans more than one shelf (got %d)" % shelves.size())
	_expect(int(shelves.get(SpellTier.Tier.HEAVY, 0)) > 0,
		"at least one beam is HEAVY — something a wall can actually stop")
	_expect(int(shelves.get(SpellTier.Tier.ULT, 0)) > 0,
		"at least one beam is ULT — something that overpowers a HEAVY beam")
	# The consequence, stated as the outcome rather than the shelf: an ULT beam has
	# to strictly out-weigh a HEAVY one, or "an ult feels like an ult" is a claim
	# with nothing behind it.
	var by_id: Dictionary = _by_id()
	_expect(
		SpellTier.outweighs(SpellTier.of(by_id["infernal_lance"]),
			SpellTier.of(by_id["ordinary_spell"])),
		"Infernal Lance (ULT) out-weighs The Ordinary Spell (HEAVY) in a clash")
	_expect(
		SpellTier.weights_match(SpellTier.of(by_id["ordinary_spell"]),
			SpellTier.of(by_id["frostpiercer"])),
		"the two HEAVY beams are evenly matched with each other")
	_completes("beam_shelf_spread")


# --------------------------------------------------------------- 5. the IP
## The guard that stops the rename quietly coming back. Scans the SOURCE, so a
## borrowed name reintroduced in a comment or a helper name fails too.
func _test_no_banned_names() -> void:
	var f: FileAccess = FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	_expect(f != null, "SpellLibrary.gd is readable for the IP sweep")
	if f == null:
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var src: String = f.get_as_text().to_lower()
	f.close()
	for name: String in BANNED:
		_expect(not src.contains(name),
			"no borrowed name '%s' survives anywhere in SpellLibrary.gd" % name)
	_completes("no_banned_names")


# ------------------------------------------------- 6. descriptions vs reality
## A description that promises deleted behaviour is worse than no description: the
## player reads it, builds a plan around it, and the plan silently does not work.
## Each check below names the behaviour that was actually removed from the
## spectacle, so the assertion explains itself when it fires.
func _test_descriptions_match_behaviour() -> void:
	var by_id: Dictionary = _by_id()

	# BlinkStrike.gd deleted the 300 px path-crossing corridor; damage is now one
	# radius query at the destination.
	var blink: String = String(by_id["blink_strike"].description).to_lower()
	_expect(not blink.contains("crossed line") and not blink.contains("weakened"),
		"Shadow Step no longer promises the deleted damage corridor")

	# RuneOrbs.gd: the fan "never changes where the orb ends up" (no-auto-aim rule).
	var orbs: String = String(by_id["rune_orbs"].description).to_lower()
	_expect(not orbs.contains("home"),
		"Arcane Missiles no longer claim to home (the homing was removed)")

	# DrainTether.gd: a hook lashed down the aim that "never bends to find a target".
	var tether: String = String(by_id["drain_tether"].description).to_lower()
	_expect(not tether.contains("nearest"),
		"Drain Tether no longer claims to auto-lock the nearest foe")

	# frozen_comet's spectacle became IceSpikeLine — a ground-travelling line, not
	# a sky bombardment. The id stays so saved loadouts keep resolving.
	var spine: SpellDef = by_id["frozen_comet"]
	_expect(spine.display_name == "Glacial Spine",
		"frozen_comet still presents as the Glacial Spine")
	var spine_desc: String = String(spine.description).to_lower()
	_expect(
		spine_desc.contains("ground") or spine_desc.contains("floor"),
		"Glacial Spine's blurb describes the FLOOR line it became, not a bombardment")
	_expect(not spine_desc.contains("rain") and not spine_desc.contains("sky"),
		"Glacial Spine's blurb no longer describes a sky bombardment")
	_completes("descriptions_match_behaviour")


# ------------------------------------------------------------------ helpers
func _by_id() -> Dictionary:
	var out: Dictionary = {}
	for s: SpellDef in SpellLibrary.build_all():
		out[s.id] = s
	return out


## Every spell id equipped by any class, across all five slots.
func _all_equipped_ids() -> Array[String]:
	var out: Array[String] = []
	for cls: int in range(ClassInfo.count()):
		for s: SpellDef in SpellLibrary.build_for_class(cls):
			if not out.has(s.id):
				out.append(s.id)
	return out
