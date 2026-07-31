# Run: godot --headless --path godot-project --script tools/slice_test_hype.gd
# THE MOMENT-TO-MOMENT REWARD LOOP (scripts/combat/Hype.gd): kill streaks,
# multi-kills, close calls and the wave flourish. This is the "endorphin" half of
# the pacing pass, so the assertions are about the loop actually FIRING and
# actually LAPSING — a reward that never lands and a chain that never breaks are
# the two ways this becomes decoration.
#
# Hype is deliberately NOT an autoload (the Arena builds it, group "hype" finds
# it), which is what makes it drivable here at all: it is instantiated bare, its
# own _process is disabled, and every timer is stepped by hand.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read is NOT a test failure in GDScript: it logs an error, ABORTS
# the enclosing function, and hands back the return type's zero value. So
# failures accumulate on the MEMBER `_fails`, and every test records a completion
# sentinel — a test that aborts part-way is missing from `_completed` and fails
# the suite BY ABSENCE.

## Every test that must run to completion.
const TESTS: Array[String] = [
	"chain_counts_and_lapses",
	"rungs_announce_once_each",
	"multikill_resolves_on_the_window",
	"wave_beats_shout_and_move_the_camera",
	"close_call_needs_you_to_actually_survive",
	"death_is_not_a_close_call",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const HYPE_PATH: String = "res://scripts/combat/Hype.gd"


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_chain_counts_and_lapses()
	_test_rungs_announce_once_each()
	_test_multikill_resolves_on_the_window()
	_test_wave_beats_shout_and_move_the_camera()
	_test_close_call_needs_you_to_actually_survive()
	_test_death_is_not_a_close_call()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Hype tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Hype tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ fixtures
## A bare Hype in the tree with its own _process disabled, so every timer below
## is stepped by hand and nothing advances behind an assertion.
func _make_hype() -> Node:
	var h: Node = load(HYPE_PATH).new()
	root.add_child(h)
	h.set_process(false)
	return h


## What the shout label currently reads (the one observable the whole reward
## layer funnels through).
func _shout(h: Node) -> String:
	var lbl: Label = h.get("_shout") as Label
	return lbl.text if lbl != null else "<no shout label>"


# -------------------------------------------------------------------- chain
## The chain counts up, and — the load-bearing half — it LAPSES. A streak you
## cannot lose is not a streak, it is a tally, and a tally does not make anyone
## push forward.
func _test_chain_counts_and_lapses() -> void:
	var h: Node = _make_hype()
	_expect(int(h.call("combo")) == 0, "a fresh arena has no chain")
	h.call("notify_kill")
	h.call("notify_kill")
	_expect(int(h.call("combo")) == 2, "two kills chain (got %d)" % int(h.call("combo")))
	# Just inside the window: still alive.
	h.call("_process", float(h.get("COMBO_WINDOW")) - 0.1)
	_expect(int(h.call("combo")) == 2, "the chain survives right up to its window")
	h.call("notify_kill")
	_expect(int(h.call("combo")) == 3, "a kill inside the window extends it")
	# Past the window: gone.
	h.call("_process", float(h.get("COMBO_WINDOW")) + 0.1)
	_expect(int(h.call("combo")) == 0, "the chain LAPSES when you stop killing")
	_expect(int(h.call("best_combo")) == 3, "...but the best is remembered (got %d)" % int(h.call("best_combo")))
	h.free()
	_completes("chain_counts_and_lapses")


## Each named rung shouts ONCE per chain. Re-announcing RAMPAGE on every kill
## after the third would turn the one thing that has to read instantly into
## wallpaper you learn to ignore.
func _test_rungs_announce_once_each() -> void:
	var h: Node = _make_hype()
	var rungs: Array = h.get("STREAK_RUNGS") as Array
	_expect(rungs.size() >= 3, "there is a ladder of named rungs to climb")
	var first_at: int = int(rungs[0][0])
	for i: int in first_at:
		h.call("notify_kill")
	_expect(_shout(h) == String(rungs[0][1]),
		"crossing rung 0 shouts '%s' (got '%s')" % [String(rungs[0][1]), _shout(h)])
	# One more kill is NOT another rung — the shout must not re-fire.
	var lbl: Label = h.get("_shout") as Label
	lbl.text = "<cleared>"
	h.call("notify_kill")
	_expect(_shout(h) == "<cleared>", "a kill between rungs does not re-shout")
	# Climb to rung 1.
	while int(h.call("combo")) < int(rungs[1][0]):
		h.call("notify_kill")
	_expect(_shout(h) == String(rungs[1][1]), "the next rung announces itself")
	# Break the chain and re-climb: the rungs are available again.
	h.call("_process", float(h.get("COMBO_WINDOW")) + 0.1)
	lbl.text = "<cleared>"
	for i: int in first_at:
		h.call("notify_kill")
	_expect(_shout(h) == String(rungs[0][1]), "a NEW chain can earn the same rung again")
	h.free()
	_completes("rungs_announce_once_each")


## The multi-kill is the AoE payoff. It resolves when the window lapses (so a
## triple is not reported as three doubles), and a lone kill reports nothing.
func _test_multikill_resolves_on_the_window() -> void:
	var h: Node = _make_hype()
	var lbl: Label = h.get("_shout") as Label
	var window: float = float(h.get("MULTI_WINDOW"))
	# One kill inside the window is not a multi-kill.
	h.call("notify_kill")
	lbl.text = "<cleared>"
	h.call("_process", window + 0.05)
	_expect(_shout(h) == "<cleared>", "a single kill is not a multi-kill")
	# Three in one breath is.
	h.call("notify_kill")
	h.call("notify_kill")
	h.call("notify_kill")
	lbl.text = "<cleared>"
	_expect(_shout(h) == "<cleared>", "the multi-kill waits for its window to close")
	h.call("_process", window + 0.05)
	var shouts: Array = h.get("MULTI_SHOUTS") as Array
	_expect(_shout(h) == String(shouts[3]),
		"three at once reads '%s' (got '%s')" % [String(shouts[3]), _shout(h)])
	h.free()
	_completes("multikill_resolves_on_the_window")


## The wave beats: each one shouts, and each one MOVES THE CAMERA. The camera is
## the pressure instrument — a wave that arrives and a wave that dies have to
## land physically, not just as text.
func _test_wave_beats_shout_and_move_the_camera() -> void:
	var h: Node = _make_hype()
	var cam := _CamStub.new()
	cam.add_to_group("combat_camera")
	root.add_child(cam)

	h.call("wave_opened", 0, 3)
	_expect(_shout(h).contains("WAVE 1"), "an opening wave announces which one it is (got '%s')" % _shout(h))
	_expect(cam.pulls == 1, "the camera PULLS BACK to receive the incoming wave (got %d)" % cam.pulls)

	h.call("wave_beaten", 0, 3)
	_expect(_shout(h).contains("DOWN"), "a beaten wave reads as a WIN (got '%s')" % _shout(h))
	_expect(cam.punches == 1, "...and lands as a camera punch (got %d)" % cam.punches)

	h.call("guardian_arrived")
	_expect(_shout(h) != "", "the guardian announces itself")
	_expect(cam.pulls == 2, "the guardian pulls the camera back too (got %d)" % cam.pulls)
	_expect(cam.trauma > 0.0, "...with a shake behind it (got %.2f)" % cam.trauma)
	cam.free()
	h.free()
	_completes("wave_beats_shout_and_move_the_camera")


## A close call is SURVIVING the red, not entering it. Being hit again re-arms
## the timer, so chip damage while dying never pays out a celebration.
func _test_close_call_needs_you_to_actually_survive() -> void:
	var h: Node = _make_hype()
	var lbl: Label = h.get("_shout") as Label
	var survive: float = float(h.get("CLOSE_CALL_SURVIVE"))
	h.call("_on_hero_health", 10, 100)          # into the red
	lbl.text = "<cleared>"
	h.call("_process", survive * 0.5)
	_expect(_shout(h) == "<cleared>", "being in the red is not yet a close call")
	h.call("_on_hero_health", 6, 100)           # hit again — the clock restarts
	h.call("_process", survive * 0.7)
	_expect(_shout(h) == "<cleared>", "taking another hit re-arms the survival clock")
	h.call("_process", survive * 0.5)
	_expect(_shout(h) == "CLOSE CALL", "surviving the red pays out (got '%s')" % _shout(h))
	# ...and only once.
	lbl.text = "<cleared>"
	h.call("_process", survive + 1.0)
	_expect(_shout(h) == "<cleared>", "a close call does not repeat while you stay healthy")
	h.free()
	_completes("close_call_needs_you_to_actually_survive")


## Dying is not a heroic survival, and it takes the chain with it.
func _test_death_is_not_a_close_call() -> void:
	var h: Node = _make_hype()
	var lbl: Label = h.get("_shout") as Label
	h.call("notify_kill")
	h.call("notify_kill")
	# Flush the multi-kill window FIRST: those two kills are a legitimate DOUBLE
	# KILL and it would land on the shout label mid-assertion below.
	h.call("_process", float(h.get("MULTI_WINDOW")) + 0.05)
	h.call("_on_hero_health", 8, 100)
	lbl.text = "<cleared>"
	h.call("_on_hero_health", 0, 100)
	h.call("_process", float(h.get("CLOSE_CALL_SURVIVE")) + 1.0)
	_expect(_shout(h) == "<cleared>", "dying does not pay out a CLOSE CALL")
	_expect(int(h.call("combo")) == 0, "dying breaks the chain")
	h.free()
	_completes("death_is_not_a_close_call")


## Stand-in camera: joins "combat_camera" and counts what the reward loop asked
## it to do. Only the three methods Hype reaches for.
class _CamStub extends Node2D:
	var pulls: int = 0
	var punches: int = 0
	var trauma: float = 0.0

	func zoom_pull(_amount: float, _hold: float = 0.5) -> void:
		pulls += 1

	func zoom_punch(_amount: float, _duration: float = 0.18) -> void:
		punches += 1

	func add_trauma(amount: float) -> void:
		trauma += amount
