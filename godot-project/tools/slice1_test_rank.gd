# Run: godot --headless --path godot-project --script tools/slice1_test_rank.gd
# Note: tests run on the first _process frame (not _init) because Rank.gd is
# an autoload script and fresh instances added under root need the main loop
# set up — so the script is load()ed at runtime, never preload()ed.
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
	"tier_and_title_boundaries",
	"add_power_crossing_emits_once",
	"add_power_mid_tier_is_silent",
	"set_power_emits_on_tier_change",
	"kill_power_constant",
	"rig_aura_tier_clamps",
]

var _fails: int = 0
var _completed: Dictionary = {}

const RANK_SCRIPT_PATH: String = "res://scripts/combat/Rank.gd"

var _ran: bool = false
var _emissions: Array = []


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_tier_and_title_boundaries()
	_test_add_power_crossing_emits_once()
	_test_add_power_mid_tier_is_silent()
	_test_set_power_emits_on_tier_change()
	_test_kill_power_constant()
	_test_rig_aura_tier_clamps()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 rank tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 rank tests: all PASS")
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


## Fresh Rank node under root, so _ready runs and the HUD builds headless.
func _make_rank() -> Node:
	var rank_script: GDScript = load(RANK_SCRIPT_PATH) as GDScript
	var rank: Node = rank_script.new() as Node
	root.add_child(rank)  # freed with root at exit
	return rank


func _on_rank_signal(new_tier: int, new_title: String) -> void:
	_emissions.append([new_tier, new_title])


## tier()/title() at every threshold boundary, including the clamp above the
## Ascendant threshold.
func _test_tier_and_title_boundaries() -> void:
	# ⚠ DERIVED FROM `TIER_POWER`, NOT HARDCODED — deliberately.
	# This test used to pin the literal thresholds 6/16/32/54/84. When the curve was
	# restretched (Rank maxed out in the first ~40 seconds of the game and then sat
	# pinned forever, so it had stopped being a reward signal at all), every one of
	# those literals broke at once and the suite reported eleven failures for one
	# intentional change. The BOUNDARY SEMANTICS are what matter and they are what is
	# asserted here: landing exactly on a threshold IS that tier, one point below is
	# still the tier beneath, and the title tracks the tier. Retuning the curve is now
	# a one-line change in `Rank`; breaking the semantics still fails loudly.
	var rank: Node = _make_rank()
	var thresholds: Array = rank.get("TIER_POWER")
	var titles: Array = rank.get("TIER_TITLE")
	_expect(thresholds.size() >= 2, "the curve has tiers to test (got %d)" % thresholds.size())
	_expect(thresholds.size() == titles.size(), "every tier has a title")
	_expect(int(thresholds[0]) == 0, "tier 0 starts at power 0")
	for i: int in range(thresholds.size()):
		var at: int = int(thresholds[i])
		rank.call("set_power", at)
		_expect(int(rank.call("tier")) == i, "power %d (the threshold) IS tier %d" % [at, i])
		_expect(String(rank.call("title")) == String(titles[i]),
			"power %d -> title %s" % [at, String(titles[i])])
		if i > 0:
			rank.call("set_power", at - 1)
			_expect(int(rank.call("tier")) == i - 1,
				"power %d (one below) is still tier %d" % [at - 1, i - 1])
	# Past the top threshold the tier clamps rather than running off the end.
	var top: int = int(thresholds[thresholds.size() - 1])
	rank.call("set_power", top * 4 + 999)
	_expect(int(rank.call("tier")) == thresholds.size() - 1, "power past the top clamps to the top tier")
	_expect(String(rank.call("title")) == String(titles[titles.size() - 1]), "...and keeps the top title")
	_completes("tier_and_title_boundaries")


## add_power crossing a threshold flips the tier AND emits rank_changed
## exactly once, carrying the new tier + title.
func _test_add_power_crossing_emits_once() -> void:
	# Also derived from the curve — see the note in _test_tier_and_title_boundaries.
	var rank: Node = _make_rank()
	var thresholds: Array = rank.get("TIER_POWER")
	var titles: Array = rank.get("TIER_TITLE")
	var t1: int = int(thresholds[1])          # the first threshold above zero
	var below: int = t1 - 1
	_emissions = []
	rank.connect("rank_changed", _on_rank_signal)
	rank.call("set_power", below)              # still tier 0 — must not emit
	_expect(_emissions.is_empty(), "set_power within tier 0 does not emit")
	rank.call("add_power", 3)                  # crosses into tier 1
	_expect(
		_emissions.size() == 1,
		"crossing threshold %d emits rank_changed exactly once (got %d)" % [t1, _emissions.size()]
	)
	if _emissions.size() == 1:
		var e: Array = _emissions[0]
		_expect(
			int(e[0]) == 1 and String(e[1]) == String(titles[1]),
			"emission carries (1, %s) (got %s)" % [String(titles[1]), e]
		)
	_expect(int(rank.get("power")) == below + 3, "power accumulated to %d" % (below + 3))
	_completes("add_power_crossing_emits_once")


## add_power that stays inside the current tier must be silent.
func _test_add_power_mid_tier_is_silent() -> void:
	var rank: Node = _make_rank()
	_emissions = []
	rank.connect("rank_changed", _on_rank_signal)
	rank.call("add_power", 3)  # 0 -> 3, still tier 0
	rank.call("add_power", 2)  # 3 -> 5, still tier 0
	_expect(
		_emissions.is_empty(),
		"mid-tier add_power emits nothing (got %d emissions)" % _emissions.size()
	)
	_expect(int(rank.call("tier")) == 0, "still tier 0 at power 5")
	_completes("add_power_mid_tier_is_silent")


## set_power emits on any tier change (up or down), silent otherwise.
func _test_set_power_emits_on_tier_change() -> void:
	# Derived from the curve — see the note in _test_tier_and_title_boundaries.
	var rank: Node = _make_rank()
	var thresholds: Array = rank.get("TIER_POWER")
	var titles: Array = rank.get("TIER_TITLE")
	var top_tier: int = thresholds.size() - 1
	var top: int = int(thresholds[top_tier])
	_emissions = []
	rank.connect("rank_changed", _on_rank_signal)
	rank.call("set_power", top)  # 0 -> top tier in ONE jump: still exactly one emission
	_expect(
		_emissions.size() == 1, "set_power(%d) emits once (got %d)" % [top, _emissions.size()]
	)
	if _emissions.size() == 1:
		var e: Array = _emissions[0]
		_expect(
			int(e[0]) == top_tier and String(e[1]) == String(titles[top_tier]),
			"emission carries (%d, %s) (got %s)" % [top_tier, String(titles[top_tier]), e]
		)
	rank.call("set_power", top + 6)  # still the top tier — silent
	_expect(
		_emissions.size() == 1, "set_power within the top tier stays silent"
	)
	_completes("set_power_emits_on_tier_change")


## Enemy._die hands the literal 3 to add_power; keep it locked to KILL_POWER.
func _test_kill_power_constant() -> void:
	var rank: Node = _make_rank()
	_expect(
		int(rank.get("KILL_POWER")) == 3, "KILL_POWER is 3 (Enemy._die literal)"
	)
	_completes("kill_power_constant")


## CharacterRig.set_aura_tier clamps to 0..5 (tier 0 = aura off).
func _test_rig_aura_tier_clamps() -> void:
	var rig: CharacterRig = CharacterRig.new()
	root.add_child(rig)
	_expect(rig.aura_tier == 1, "rig defaults to tier 1 (baseline aura)")
	rig.set_aura_tier(9)
	_expect(rig.aura_tier == 5, "set_aura_tier(9) clamps to 5")
	rig.set_aura_tier(-2)
	_expect(rig.aura_tier == 0, "set_aura_tier(-2) clamps to 0")
	rig.set_aura_tier(3)
	_expect(rig.aura_tier == 3, "set_aura_tier(3) lands on 3")
	_completes("rig_aura_tier_clamps")
