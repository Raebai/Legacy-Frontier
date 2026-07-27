# HandSlots — the two-button control model: left click uses what you hold, right
# click always deflects, scroll moves along the bar.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_hand_slots.gd
extends SceneTree

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_default_is_fists()
	failed += _test_primary_action_is_unambiguous()
	failed += _test_cycling()
	failed += _test_cooldowns()
	if failed > 0:
		printerr("Hand slot tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Hand slot tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _loadout() -> HandSlots:
	var h := HandSlots.new()
	h.rebuild(["sword", "hammer"], SpellLibrary.build())
	return h


## Slot 0 is always fists, so no loadout can strand a player with nothing to do
## when every spell is on cooldown.
func _test_default_is_fists() -> int:
	var ok: int = 0
	var fresh := HandSlots.new()
	ok += _expect(fresh.current_kind() == HandSlots.Kind.FISTS, "a fresh hand is fists")
	ok += _expect(fresh.primary_action() == "punch", "empty hands punch")
	ok += _expect(fresh.weapon_id() == "", "fists are not a weapon")
	ok += _expect(fresh.spell() == null, "fists are not a spell")
	var h := _loadout()
	ok += _expect(int(h.slots[0]["kind"]) == HandSlots.Kind.FISTS,
		"fists stay at slot 0 after a rebuild")
	return ok


## The single question the whole model exists to answer: what does left click do?
func _test_primary_action_is_unambiguous() -> int:
	var ok: int = 0
	var h := _loadout()
	h.select(0)
	ok += _expect(h.primary_action() == "punch", "on fists, left click punches")
	h.select(1)
	ok += _expect(h.primary_action() == "swing", "on a weapon, left click swings")
	ok += _expect(h.weapon_id() == "sword", "the weapon id drives which blade is drawn")
	ok += _expect(h.spell() == null, "a weapon slot exposes no spell to cast")
	# First spell slot sits after fists + 2 weapons.
	h.select(3)
	ok += _expect(h.primary_action() == "cast", "on a spell, left click casts")
	ok += _expect(h.spell() != null, "a spell slot exposes its SpellDef")
	ok += _expect(h.weapon_id() == "", "a spell slot reports no weapon")
	return ok


func _test_cycling() -> int:
	var ok: int = 0
	var h := _loadout()
	var n: int = h.slots.size()
	ok += _expect(n > 3, "the loadout built multiple slots (got %d)" % n)
	h.select(0)
	h.cycle(1)
	ok += _expect(h.selected == 1, "scrolling forward advances one slot")
	h.cycle(-1)
	ok += _expect(h.selected == 0, "scrolling back returns")
	# Wraps both ways — a scroll wheel that dead-ends reads as broken, and there
	# is no visible end to the bar to explain the stop.
	h.cycle(-1)
	ok += _expect(h.selected == n - 1, "scrolling back from the first slot wraps to the last")
	h.cycle(1)
	ok += _expect(h.selected == 0, "scrolling forward from the last wraps to the first")
	# A rebuild with fewer slots must not leave the selection out of bounds.
	h.select(n - 1)
	h.rebuild([], [])
	ok += _expect(h.selected == 0 and h.current_kind() == HandSlots.Kind.FISTS,
		"a shrinking rebuild clamps the selection instead of dangling")
	return ok


func _test_cooldowns() -> int:
	var ok: int = 0
	var h := _loadout()
	h.select(3)
	ok += _expect(h.current_ready(), "a fresh slot is ready")
	h.start_cooldown(3, 2.0)
	ok += _expect(not h.current_ready(), "a slot on cooldown is not ready")
	# Still selectable while cooling — blocking selection would make the bar lie
	# about what you own, and you need to see the sweep.
	h.select(3)
	ok += _expect(h.selected == 3, "a cooling slot can still be selected")
	h.tick(1.0)
	ok += _expect(not h.current_ready(), "still cooling part-way through")
	h.tick(1.5)
	ok += _expect(h.current_ready(), "ready again once the cooldown elapses")
	ok += _expect(float(h.slots[3]["cooldown"]) == 0.0, "cooldown floors at zero")
	# Fists never go on cooldown, so the panic option is always available.
	ok += _expect(h.is_ready(0), "fists are always ready")
	return ok
