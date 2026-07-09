# Run: godot --headless --path godot-project --script tools/slice1_test_rank.gd
# Note: tests run on the first _process frame (not _init) because Rank.gd is
# an autoload script and fresh instances added under root need the main loop
# set up — so the script is load()ed at runtime, never preload()ed.
extends SceneTree

const RANK_SCRIPT_PATH: String = "res://scripts/combat/Rank.gd"

var _ran: bool = false
var _emissions: Array = []


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_tier_and_title_boundaries()
	failed += _test_add_power_crossing_emits_once()
	failed += _test_add_power_mid_tier_is_silent()
	failed += _test_set_power_emits_on_tier_change()
	failed += _test_kill_power_constant()
	failed += _test_rig_aura_tier_clamps()
	if failed > 0:
		printerr("Slice1 rank tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 rank tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


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
func _test_tier_and_title_boundaries() -> int:
	var failed: int = 0
	var rank: Node = _make_rank()
	var powers: Array[int] = [0, 5, 6, 15, 16, 31, 32, 53, 54, 83, 84, 999]
	var tiers: Array[int] = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5]
	var titles: Array[String] = [
		"Nameless", "Nameless", "Climber", "Climber", "Ranked", "Ranked",
		"Adept", "Adept", "Ranker", "Ranker", "Ascendant", "Ascendant",
	]
	for i: int in range(powers.size()):
		rank.call("set_power", powers[i])
		var got_tier: int = int(rank.call("tier"))
		var got_title: String = String(rank.call("title"))
		failed += _expect(
			got_tier == tiers[i],
			"power %d -> tier %d (got %d)" % [powers[i], tiers[i], got_tier]
		)
		failed += _expect(
			got_title == titles[i],
			"power %d -> title %s (got %s)" % [powers[i], titles[i], got_title]
		)
	return failed


## add_power crossing a threshold flips the tier AND emits rank_changed
## exactly once, carrying the new tier + title.
func _test_add_power_crossing_emits_once() -> int:
	var failed: int = 0
	var rank: Node = _make_rank()
	_emissions = []
	rank.connect("rank_changed", _on_rank_signal)
	rank.call("set_power", 5)  # still tier 0 — must not emit
	failed += _expect(
		_emissions.is_empty(), "set_power within tier 0 does not emit"
	)
	rank.call("add_power", 3)  # 5 -> 8, crosses the tier-1 threshold (6)
	failed += _expect(
		_emissions.size() == 1,
		"crossing threshold 6 emits rank_changed exactly once (got %d)" % _emissions.size()
	)
	if _emissions.size() == 1:
		var e: Array = _emissions[0]
		failed += _expect(
			int(e[0]) == 1 and String(e[1]) == "Climber",
			"emission carries (1, Climber) (got %s)" % [e]
		)
	failed += _expect(int(rank.get("power")) == 8, "power accumulated to 8")
	return failed


## add_power that stays inside the current tier must be silent.
func _test_add_power_mid_tier_is_silent() -> int:
	var failed: int = 0
	var rank: Node = _make_rank()
	_emissions = []
	rank.connect("rank_changed", _on_rank_signal)
	rank.call("add_power", 3)  # 0 -> 3, still tier 0
	rank.call("add_power", 2)  # 3 -> 5, still tier 0
	failed += _expect(
		_emissions.is_empty(),
		"mid-tier add_power emits nothing (got %d emissions)" % _emissions.size()
	)
	failed += _expect(int(rank.call("tier")) == 0, "still tier 0 at power 5")
	return failed


## set_power emits on any tier change (up or down), silent otherwise.
func _test_set_power_emits_on_tier_change() -> int:
	var failed: int = 0
	var rank: Node = _make_rank()
	_emissions = []
	rank.connect("rank_changed", _on_rank_signal)
	rank.call("set_power", 84)  # 0 -> tier 5 in one jump
	failed += _expect(
		_emissions.size() == 1, "set_power(84) emits once (got %d)" % _emissions.size()
	)
	if _emissions.size() == 1:
		var e: Array = _emissions[0]
		failed += _expect(
			int(e[0]) == 5 and String(e[1]) == "Ascendant",
			"emission carries (5, Ascendant) (got %s)" % [e]
		)
	rank.call("set_power", 90)  # still tier 5 — silent
	failed += _expect(
		_emissions.size() == 1, "set_power within tier 5 stays silent"
	)
	return failed


## Enemy._die hands the literal 3 to add_power; keep it locked to KILL_POWER.
func _test_kill_power_constant() -> int:
	var rank: Node = _make_rank()
	return _expect(
		int(rank.get("KILL_POWER")) == 3, "KILL_POWER is 3 (Enemy._die literal)"
	)


## CharacterRig.set_aura_tier clamps to 0..5 (tier 0 = aura off).
func _test_rig_aura_tier_clamps() -> int:
	var failed: int = 0
	var rig: CharacterRig = CharacterRig.new()
	root.add_child(rig)
	failed += _expect(rig.aura_tier == 1, "rig defaults to tier 1 (baseline aura)")
	rig.set_aura_tier(9)
	failed += _expect(rig.aura_tier == 5, "set_aura_tier(9) clamps to 5")
	rig.set_aura_tier(-2)
	failed += _expect(rig.aura_tier == 0, "set_aura_tier(-2) clamps to 0")
	rig.set_aura_tier(3)
	failed += _expect(rig.aura_tier == 3, "set_aura_tier(3) lands on 3")
	return failed
