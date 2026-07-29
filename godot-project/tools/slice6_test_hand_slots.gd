# HandSlots — the two-button control model: left click uses what you hold, right
# click always deflects, scroll moves along the bar.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_hand_slots.gd
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
	"default_is_fists",
	"primary_action_is_unambiguous",
	"cycling",
	"cooldowns",
]

var _fails: int = 0
var _completed: Dictionary = {}

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_default_is_fists()
	_test_primary_action_is_unambiguous()
	_test_cycling()
	_test_cooldowns()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Hand slot tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Hand slot tests: all PASS")
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


func _loadout() -> HandSlots:
	var h := HandSlots.new()
	h.rebuild(["sword", "hammer"], SpellLibrary.build())
	return h


## Slot 0 is always fists, so no loadout can strand a player with nothing to do
## when every spell is on cooldown.
func _test_default_is_fists() -> void:
	var fresh := HandSlots.new()
	_expect(fresh.current_kind() == HandSlots.Kind.FISTS, "a fresh hand is fists")
	_expect(fresh.primary_action() == "punch", "empty hands punch")
	_expect(fresh.weapon_id() == "", "fists are not a weapon")
	_expect(fresh.spell() == null, "fists are not a spell")
	var h := _loadout()
	_expect(int(h.slots[0]["kind"]) == HandSlots.Kind.FISTS,
		"fists stay at slot 0 after a rebuild")
	_completes("default_is_fists")


## The single question the whole model exists to answer: what does left click do?
func _test_primary_action_is_unambiguous() -> void:
	var h := _loadout()
	h.select(0)
	_expect(h.primary_action() == "punch", "on fists, left click punches")
	h.select(1)
	_expect(h.primary_action() == "swing", "on a weapon, left click swings")
	_expect(h.weapon_id() == "sword", "the weapon id drives which blade is drawn")
	_expect(h.spell() == null, "a weapon slot exposes no spell to cast")
	# First spell slot sits after fists + 2 weapons.
	h.select(3)
	_expect(h.primary_action() == "cast", "on a spell, left click casts")
	_expect(h.spell() != null, "a spell slot exposes its SpellDef")
	_expect(h.weapon_id() == "", "a spell slot reports no weapon")
	_completes("primary_action_is_unambiguous")


func _test_cycling() -> void:
	var h := _loadout()
	var n: int = h.slots.size()
	_expect(n > 3, "the loadout built multiple slots (got %d)" % n)
	h.select(0)
	h.cycle(1)
	_expect(h.selected == 1, "scrolling forward advances one slot")
	h.cycle(-1)
	_expect(h.selected == 0, "scrolling back returns")
	# Wraps both ways — a scroll wheel that dead-ends reads as broken, and there
	# is no visible end to the bar to explain the stop.
	h.cycle(-1)
	_expect(h.selected == n - 1, "scrolling back from the first slot wraps to the last")
	h.cycle(1)
	_expect(h.selected == 0, "scrolling forward from the last wraps to the first")
	# A rebuild with fewer slots must not leave the selection out of bounds.
	h.select(n - 1)
	h.rebuild([], [])
	_expect(h.selected == 0 and h.current_kind() == HandSlots.Kind.FISTS,
		"a shrinking rebuild clamps the selection instead of dangling")
	_completes("cycling")


func _test_cooldowns() -> void:
	var h := _loadout()
	h.select(3)
	_expect(h.current_ready(), "a fresh slot is ready")
	h.start_cooldown(3, 2.0)
	_expect(not h.current_ready(), "a slot on cooldown is not ready")
	# Still selectable while cooling — blocking selection would make the bar lie
	# about what you own, and you need to see the sweep.
	h.select(3)
	_expect(h.selected == 3, "a cooling slot can still be selected")
	h.tick(1.0)
	_expect(not h.current_ready(), "still cooling part-way through")
	h.tick(1.5)
	_expect(h.current_ready(), "ready again once the cooldown elapses")
	_expect(float(h.slots[3]["cooldown"]) == 0.0, "cooldown floors at zero")
	# Fists never go on cooldown, so the panic option is always available.
	_expect(h.is_ready(0), "fists are always ready")
	_completes("cooldowns")
