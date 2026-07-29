# Run: godot --headless --path godot-project --script tools/slice6_test_bot_sim.gd
#
# The bot simulation's ANOMALY DETECTORS, tested against known-good and known-bad
# inputs. A bug-finder nobody trusts is worse than no bug-finder, and the only way
# to trust one is to prove it says "yes" when something IS wrong and "no" when it
# is not. Every check therefore gets both halves.
#
# ── Vacuous-pass armour (the house rule; see tools/slice_test_loadout.gd) ──────
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function, and hands the caller back the return type's zero
# value. Under a `failed += _test_x()` idiom that reads as "zero failures", so a
# suite can print all PASS while silently skipping every assertion after the dead
# line — 64 suites in this repo were passing exactly that way. Static typing does
# not help; a typed reference to a renamed field compiles clean and dies the same.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.
extends SceneTree

## Every test that must run to completion.
const TESTS: Array[String] = [
	"broken_positions", "bounds", "floor", "damage_outlier", "fast_kill",
	"no_damage", "hp_range", "stalemate", "idle", "never_fired", "mana",
	"records_and_csv", "summary", "arena_bounds_contain_the_stage",
]

## BotSimProbe members reached by name. Listed once so a relocation is named
## rather than merely detected.
const PROBE_METHODS: Array[String] = [
	"position_is_broken", "escaped_bounds", "below_floor", "damage_outlier",
	"fast_kill", "no_damage_exchanged", "hp_out_of_range", "stalemate",
	"actor_idle", "never_fired", "never_spent_mana", "anomaly", "csv_row",
	"csv_header", "csv_cell", "summarize",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_require_methods()
	_test_broken_positions()
	_test_bounds()
	_test_floor()
	_test_damage_outlier()
	_test_fast_kill()
	_test_no_damage()
	_test_hp_range()
	_test_stalemate()
	_test_idle()
	_test_never_fired()
	_test_mana()
	_test_records_and_csv()
	_test_summary()
	_test_arena_bounds_contain_the_stage()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("bot_sim tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("bot_sim tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort survives the abort instead of being discarded with the aborted
## function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## The completion sentinel says "something died"; this says WHICH detector did.
func _require_methods() -> void:
	# Asked of the SCRIPT RESOURCE, not of the class name. `BotSimProbe.has_method`
	# is a parse error — GDScript reads it as calling a non-static method on the
	# class itself — so the check goes through the loaded GDScript's own method
	# list, which is also what makes it see the STATIC functions.
	var script: GDScript = load("res://tools/bot_sim_probe.gd") as GDScript
	_expect(script != null, "bot_sim_probe.gd still loads")
	if script == null:
		return
	var present: Dictionary = {}
	for entry: Dictionary in script.get_script_method_list():
		present[String(entry["name"])] = true
	for m: String in PROBE_METHODS:
		_expect(present.has(m),
			"BotSimProbe still declares `%s` (moved or renamed — the check that used it is dead)" % m)


# ---- geometry ---------------------------------------------------------------

func _test_broken_positions() -> void:
	_expect(not BotSimProbe.position_is_broken(Vector2(10.0, -40.0)), "a normal point is fine")
	_expect(BotSimProbe.position_is_broken(Vector2(NAN, 0.0)), "NaN x is broken")
	_expect(BotSimProbe.position_is_broken(Vector2(0.0, NAN)), "NaN y is broken")
	_expect(BotSimProbe.position_is_broken(Vector2(INF, 0.0)), "+INF is broken")
	_expect(BotSimProbe.position_is_broken(Vector2(0.0, -INF)), "-INF is broken")
	_completes("broken_positions")


func _test_bounds() -> void:
	var box: Rect2 = Rect2(Vector2(-100.0, -100.0), Vector2(200.0, 200.0))
	_expect(not BotSimProbe.escaped_bounds(Vector2.ZERO, box), "the centre is inside")
	_expect(not BotSimProbe.escaped_bounds(Vector2(-99.0, 99.0), box), "just inside is inside")
	_expect(BotSimProbe.escaped_bounds(Vector2(101.0, 0.0), box), "past the right edge escaped")
	_expect(BotSimProbe.escaped_bounds(Vector2(0.0, -101.0), box), "above the top escaped")
	# A broken coordinate is not inside ANYTHING — it must never read as contained,
	# or a NaN body would quietly pass the containment check every frame.
	_expect(BotSimProbe.escaped_bounds(Vector2(NAN, NAN), box), "a NaN point counts as escaped")
	_completes("bounds")


func _test_floor() -> void:
	# y grows DOWNWARD, so "below the floor" is a LARGER y.
	_expect(not BotSimProbe.below_floor(700.0, 700.0), "standing exactly on the floor is fine")
	_expect(not BotSimProbe.below_floor(740.0, 700.0, 48.0), "inside the tolerance is fine")
	_expect(BotSimProbe.below_floor(760.0, 700.0, 48.0), "past the tolerance is through the floor")
	_expect(not BotSimProbe.below_floor(-200.0, 700.0), "high in the air is not below the floor")
	_expect(BotSimProbe.below_floor(NAN, 700.0), "a NaN height counts as through the floor")
	_completes("floor")


# ---- damage -----------------------------------------------------------------

func _test_damage_outlier() -> void:
	_expect(not BotSimProbe.damage_outlier(12, 100), "12 of 100 is an ordinary hit")
	_expect(not BotSimProbe.damage_outlier(39, 100), "just under the threshold is ordinary")
	_expect(BotSimProbe.damage_outlier(40, 100), "40% in one hit is an outlier")
	_expect(BotSimProbe.damage_outlier(95, 100), "a near-oneshot is an outlier")
	_expect(not BotSimProbe.damage_outlier(0, 100), "no damage is not an outlier")
	_expect(not BotSimProbe.damage_outlier(-30, 100), "a HEAL is not a damage outlier")
	# A mis-configured fighter must not divide by zero and poison the whole run.
	_expect(not BotSimProbe.damage_outlier(50, 0), "max_hp 0 reports no outlier instead of dividing by zero")
	_completes("damage_outlier")


func _test_fast_kill() -> void:
	_expect(BotSimProbe.fast_kill(0.4), "dying in 0.4s is a fast kill")
	_expect(not BotSimProbe.fast_kill(6.0), "dying at 6s is a normal kill")
	# -1.0 is the "still alive" sentinel and must never read as a kill at all.
	_expect(not BotSimProbe.fast_kill(-1.0), "the still-alive sentinel is not a kill")
	_completes("fast_kill")


## The headline check: the exact signature of hero-vs-hero damage being routed by
## the hardwired group `"enemy"` rather than by faction.
func _test_no_damage() -> void:
	_expect(BotSimProbe.no_damage_exchanged(0, 20.0), "a 20s fight with no damage is a defect")
	_expect(not BotSimProbe.no_damage_exchanged(5, 20.0), "any damage at all clears it")
	# A short match proves nothing — one fighter may simply not have connected yet.
	_expect(not BotSimProbe.no_damage_exchanged(0, 2.0), "a 2s sample is too short to claim")
	_completes("no_damage")


func _test_hp_range() -> void:
	_expect(not BotSimProbe.hp_out_of_range(50, 100), "50 of 100 is legal")
	_expect(not BotSimProbe.hp_out_of_range(0, 100), "0 is legal (dead)")
	_expect(not BotSimProbe.hp_out_of_range(100, 100), "full is legal")
	_expect(BotSimProbe.hp_out_of_range(140, 100), "over-heal past max is out of range")
	_expect(BotSimProbe.hp_out_of_range(-5, 100), "negative hp is out of range")
	_completes("hp_range")


# ---- liveness ---------------------------------------------------------------

func _test_stalemate() -> void:
	# Nothing may be claimed until a full window has actually elapsed.
	_expect(not BotSimProbe.stalemate(0, 3.0, 10.0), "a partial window cannot claim a stalemate")
	_expect(BotSimProbe.stalemate(0, 10.0, 10.0), "a full window with no HP movement is a stall")
	_expect(BotSimProbe.stalemate(1, 12.0, 10.0), "1 point of drift still counts as stalled")
	_expect(not BotSimProbe.stalemate(40, 12.0, 10.0), "a fight that is landing hits is not stalled")
	_completes("stalemate")


func _test_idle() -> void:
	_expect(not BotSimProbe.actor_idle(0.0, 0, 2.0), "a partial window cannot claim idleness")
	_expect(BotSimProbe.actor_idle(0.0, 0, 6.0), "no movement and no presses for a window is idle")
	# EITHER signal alone clears it: a bot pinned against a wall while still
	# pressing buttons is thinking, and a bot walking silently is still acting.
	_expect(not BotSimProbe.actor_idle(0.0, 40, 6.0), "pressing buttons is not idle even when stuck")
	_expect(not BotSimProbe.actor_idle(300.0, 0, 6.0), "moving is not idle even when silent")
	_completes("idle")


# ---- reachability -----------------------------------------------------------

func _test_never_fired() -> void:
	_expect(BotSimProbe.never_fired(9, 0), "9 open-gate asks and no cast is unreachable")
	_expect(not BotSimProbe.never_fired(9, 1), "one successful cast clears it")
	# One failed press proves nothing — the bot may have been interrupted.
	_expect(not BotSimProbe.never_fired(1, 0), "a single ask is not evidence")
	_expect(not BotSimProbe.never_fired(0, 0), "a slot never asked for is not a finding")
	_completes("never_fired")


func _test_mana() -> void:
	_expect(BotSimProbe.never_spent_mana(0.0, 20.0), "a whole fight with no mana spent is a defect")
	_expect(not BotSimProbe.never_spent_mana(35.0, 20.0), "spending mana clears it")
	_expect(not BotSimProbe.never_spent_mana(0.0, 1.0), "a 1s sample is too short to claim")
	_completes("mana")


# ---- record construction ----------------------------------------------------

## An anomaly must carry enough to REPLAY it. A finding without its seed and its
## pairing is a rumour, so those fields are asserted rather than assumed.
func _test_records_and_csv() -> void:
	var a: Dictionary = BotSimProbe.anomaly(
		"spell_never_fired", BotSimProbe.SEV_ERROR, "BRAWLER_vs_CRYOMANCER",
		20260727, 12.3456, "thing, with a comma and a \"quote\"", {"spell": "blizzard"})
	_expect(String(a["kind"]) == "spell_never_fired", "the kind survives")
	_expect(String(a["pairing"]) == "BRAWLER_vs_CRYOMANCER", "the pairing survives")
	_expect(int(a["seed"]) == 20260727, "the SEED survives — without it there is no repro")
	_expect(is_equal_approx(float(a["t"]), 12.35), "the timestamp is rounded, not dropped")
	_expect(String(a["context"]["spell"]) == "blizzard", "the context survives")
	# CSV must survive a detail string containing the two characters that break
	# CSV. A report that silently loses a column is worse than no report.
	var row: String = BotSimProbe.csv_row(a)
	_expect(row.begins_with("\"spell_never_fired\""), "the row starts with the quoted kind")
	_expect(row.contains("\"\"quote\"\""), "embedded quotes are doubled, not dropped")
	_expect(BotSimProbe.csv_header().split(",").size()
		== row.split("\",\"").size(), "the row has as many columns as the header")
	_completes("records_and_csv")


func _test_summary() -> void:
	var rows: Array = [
		BotSimProbe.anomaly("a", BotSimProbe.SEV_ERROR, "p", 1, 0.0, ""),
		BotSimProbe.anomaly("a", BotSimProbe.SEV_ERROR, "p", 1, 0.0, ""),
		BotSimProbe.anomaly("b", BotSimProbe.SEV_WARN, "p", 1, 0.0, ""),
	]
	var s: Dictionary = BotSimProbe.summarize(rows)
	_expect(int(s["total"]) == 3, "every row is counted")
	_expect(int(s["errors"]) == 2, "errors are counted separately")
	_expect(int(s["warns"]) == 1, "warns are counted separately")
	_expect(int(s["by_kind"]["a"]) == 2, "kinds are tallied")
	_expect(BotSimProbe.summarize([]).get("total", -1) == 0, "an empty run summarises cleanly")
	_completes("summary")


## The arena's declared bounds must actually CONTAIN its own floor, or the
## "a body left the world" check fires on frame one for every fighter standing
## still — the detector would be permanently, uselessly red.
func _test_arena_bounds_contain_the_stage() -> void:
	var b: Rect2 = SimArena.bounds()
	_expect(b.has_point(Vector2(SimArena.FLOOR_X0, SimArena.FLOOR_Y - 40.0)),
		"the left end of the floor is inside the bounds")
	_expect(b.has_point(Vector2(SimArena.FLOOR_X1, SimArena.FLOOR_Y - 40.0)),
		"the right end of the floor is inside the bounds")
	_expect(b.has_point(Vector2(0.0, SimArena.FLOOR_Y - 600.0)),
		"a high jump is still inside the bounds")
	_expect(not b.has_point(Vector2(SimArena.FLOOR_X1 + 5000.0, 0.0)),
		"a body launched far past the stage is outside")
	_completes("arena_bounds_contain_the_stage")
