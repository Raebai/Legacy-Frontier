# Run: godot --headless --path godot-project --script tools/slice_test_bot_walls.gd
#
# NOBODY WALKS INTO A WALL FOREVER.
#
# Maker, watching Watch Bots: *"these guys get stuck in the corner of a wall then
# destroyed"*.
#
# THE MECHANISM WAS THREE THINGS, none of them a steering bug on its own:
#
#   1. `BotBrain` had NO terrain awareness at all — no raycast, no whisker, no
#      surface list. `_safest` reads pits and telegraphs; the blackboard carried
#      nothing solid. The brain could not tell "blocked" from "walking".
#   2. FOUR paths write a backwards direction and none asked what was behind: the
#      band's back-off, the under-pressure drift, the stagnation drift, and the
#      recoil flinch — which fires on 55% of hits taken, so being cornered actively
#      re-arms the thing that put you there.
#   3. `Hero` zeroes the walk against a wall and cannot step up. Three of the versus
#      stage's four risers are 90 px against a jump that apexes at 112 and a
#      documented COMFORTABLE step of 86 (`FloorGen.STEP_MAX`). So the bot pressed
#      full deflection into a face, went nowhere, and never learned anything.
#
# ⚠ AND NO EXISTING SUITE COULD HAVE CAUGHT IT. `slice_test_bot_steer.gd` integrates
# brain output straight into position with NO COLLISION — a wall cannot exist in that
# harness. `bot_sim_probe.actor_idle` needs `moved_px <= 6 AND presses <= 0`, and a
# wedged bot is pressing fire, cast, guard and move every frame, so the one detector
# that should have found this is structurally unable to: it detects a crashed brain,
# not a stuck body.
#
# ⚠ LOADED BY PATH for `Hero`, never by `class_name`: it reaches four autoloads that
# do not exist during a `--script` run. `BotBrain` is pure static logic over
# dictionaries and is safe to name.
#
# ⚠ NEVER `failed += _test_x()`. Failures accumulate on `_fails`; every test records a
# COMPLETION SENTINEL so one that aborts half-way fails the suite by absence.
extends SceneTree

const HERO_PATH: String = "res://scripts/combat/Hero.gd"
const CONTROLLER_PATH: String = "res://scripts/combat/BotController.gd"

const TESTS: Array[String] = [
	"the_body_publishes_wall_contact",
	"a_bot_that_is_not_walled_is_untouched",
	"pushing_into_a_wall_turns_around",
	"walking_ALONG_a_wall_is_left_alone",
	"a_wedged_bot_eventually_jumps",
	"it_still_jumps_when_the_turn_breaks_contact",
	"the_clock_resets_when_it_gets_free",
	"the_guard_runs_after_the_recoil_flinch",
	"a_body_with_no_wall_state_still_walks",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_body_publishes()
	_test_not_walled()
	_test_turns_around()
	_test_along_the_wall()
	_test_eventually_jumps()
	_test_jumps_through_the_bounce()
	_test_clock_resets()
	_test_after_the_flinch()
	_test_fails_open()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("bot_walls: TEST DID NOT COMPLETE — %s (aborted part-way)" % name)
	if _fails == 0:
		print("bot walls tests: all PASS")
	else:
		printerr("bot walls tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("bot_walls: FAIL — %s" % what)


func _mem() -> BotBrain.Memory:
	var m: BotBrain.Memory = BotBrain.Memory.new()
	m.rng.seed = 12345
	return m


func _bb(over: Dictionary = {}) -> Dictionary:
	var bb: Dictionary = {
		"self_pos": Vector2.ZERO, "self_vel": Vector2.ZERO,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0,
		"on_floor": true, "on_wall": false, "wall_dir": 0.0, "facing": 1.0,
		"foe_pos": Vector2(200.0, 0.0), "foe_vel": Vector2.ZERO,
		"foe_hp_frac": 1.0, "foe_facing": -1.0,
		"threats": [], "cooldowns": [0.0, 0.0, 0.0, 0.0, 0.0],
		"reach": 58.0, "now": 0.0, "class_id": 2,
	}
	for k: Variant in over.keys():
		bb[k] = over[k]
	return bb


# --------------------------------------------------------------------------- 1
## The brain can only respect a wall it is TOLD about. This is the half that was
## missing entirely, so it is asserted at the source rather than inferred.
func _test_body_publishes() -> void:
	var hero: String = FileAccess.get_file_as_string(HERO_PATH)
	_expect(not hero.is_empty(), "could not read Hero.gd")
	_expect(hero.contains("\"on_wall\": is_on_wall()"),
		"Hero.bot_body_state no longer publishes wall contact — the brain is blind "
		+ "to terrain again and every guard below is guarding nothing")
	_expect(hero.contains("\"wall_dir\":"),
		"Hero.bot_body_state no longer publishes which way the wall is")
	# ...and the default must FAIL OPEN, or a body that publishes nothing (a stub, an
	# Enemy, a dummy) would believe it is walled in and refuse to walk at all.
	var ctrl: String = FileAccess.get_file_as_string(CONTROLLER_PATH)
	_expect(ctrl.contains("\"on_wall\": false"),
		"BotController's blackboard default for on_wall is not FALSE — a body that "
		+ "publishes no wall state would think it was cornered")
	_completed["the_body_publishes_wall_contact"] = true


# --------------------------------------------------------------------------- 2
## The common case: no wall, no interference. A guard that quietly reshapes ordinary
## steering would be far worse than the bug.
func _test_not_walled() -> void:
	var m: BotBrain.Memory = _mem()
	var intent: Dictionary = {"move": Vector2.RIGHT}
	BotBrain._unwall(intent, _bb(), m, 0.0)
	_expect((intent["move"] as Vector2) == Vector2.RIGHT,
		"a bot touching nothing had its movement changed (got %s)" % intent["move"])
	_expect(m.wall_since < 0.0, "the wall clock started with no wall")
	_completed["a_bot_that_is_not_walled_is_untouched"] = true


# --------------------------------------------------------------------------- 3
## THE ASK. Pressing into a wall is turned around — NOT vetoed to zero, because
## standing still in a corner is the exact failure being fixed.
func _test_turns_around() -> void:
	for dir: float in [1.0, -1.0]:
		var m: BotBrain.Memory = _mem()
		var intent: Dictionary = {"move": Vector2(dir, 0.0)}
		BotBrain._unwall(intent, _bb({"on_wall": true, "wall_dir": dir}), m, 1.0)
		var got: Vector2 = intent["move"]
		_expect(signf(got.x) == -dir,
			"a bot pressing into a wall on side %.0f was not turned around (got %s)"
				% [dir, got])
		_expect(got.x != 0.0,
			"the answer was HOLD, not turn — standing in the corner is the bug")
		_expect(m.wall_since >= 0.0, "the wall clock did not start")
		_expect(not intent.has("jump"),
			"it jumped on the FIRST frame against a wall — brushing a riser "
			+ "mid-approach must not make a bot hop")
	_completed["pushing_into_a_wall_turns_around"] = true


# --------------------------------------------------------------------------- 4
## Walking ALONG a wall, or away from one, is not being stuck on it. If this ever
## started interfering, a bot would be unable to hug cover.
func _test_along_the_wall() -> void:
	var m: BotBrain.Memory = _mem()
	var bb: Dictionary = _bb({"on_wall": true, "wall_dir": 1.0})
	# Moving AWAY from the wall.
	var intent: Dictionary = {"move": Vector2.LEFT}
	BotBrain._unwall(intent, bb, m, 1.0)
	_expect((intent["move"] as Vector2) == Vector2.LEFT,
		"a bot walking away from a wall was turned around (got %s)" % intent["move"])
	_expect(m.wall_since < 0.0, "the clock ran while the bot was leaving the wall")
	# Not moving horizontally at all.
	var still: Dictionary = {"move": Vector2.ZERO}
	BotBrain._unwall(still, bb, m, 1.0)
	_expect((still["move"] as Vector2) == Vector2.ZERO, "a standing bot was pushed")
	_completed["walking_ALONG_a_wall_is_left_alone"] = true


# --------------------------------------------------------------------------- 5
## Turning around is not always enough — a bot in a CORNER is walled whichever way
## the band wants it. The way out of a 90 px riser is up, and a jump is the only verb
## `Hero` has that clears one. The brain otherwise emits jump ONLY as a dodge answer,
## i.e. never for terrain.
func _test_eventually_jumps() -> void:
	var m: BotBrain.Memory = _mem()
	var bb: Dictionary = _bb({"on_wall": true, "wall_dir": 1.0})
	var t: float = 0.0
	var jumped_at: float = -1.0
	# ⚠ MEASURED FROM THE FIRST PRESS, NOT FROM `m.wall_since`. The jump RE-ARMS the
	# clock as it fires (otherwise the bot pogos, requesting a jump on every subsequent
	# frame against the wall), so reading `wall_since` afterwards reports 0.00 s and
	# this assertion accuses the guard of hopping instantly. Instrument, not behaviour.
	var first_press: float = -1.0
	# Press into it every frame, the way a cornered bot's band does.
	for i: int in 40:
		t += 0.05
		var intent: Dictionary = {"move": Vector2.RIGHT}
		BotBrain._unwall(intent, bb, m, t)
		if first_press < 0.0:
			first_press = t
		if bool(intent.get("jump", false)) and jumped_at < 0.0:
			jumped_at = t - first_press
	_expect(jumped_at >= 0.0,
		"a bot pressed into a wall for two full seconds and never jumped — that is "
		+ "the corner it dies in")
	_expect(jumped_at >= BotBrain.WALL_STUCK_SECONDS - 0.06,
		"it jumped after only %.2f s — below WALL_STUCK_SECONDS (%.2f), so a "
			% [jumped_at, BotBrain.WALL_STUCK_SECONDS]
			+ "glancing touch would make it hop")
	_completed["a_wedged_bot_eventually_jumps"] = true


# -------------------------------------------------------------------------- 5b
## ⚠ THE TEST ABOVE PASSED WHILE THE FEATURE WAS DEAD, AND THIS IS THE ONE THAT CATCHES
## IT. `_test_eventually_jumps` holds `on_wall: true` on EVERY frame — but rung one
## turns the bot around, which breaks wall contact on the very next frame. So it asserts
## the jump under a condition the fix itself prevents from ever occurring.
##
## In play the shape is a BOUNCE: pressed → turned away → off the wall → steering (whose
## opinion has not changed) walks back in → pressed again. The old code cleared the
## clock on every off-wall frame, so elapsed time never grew past a frame and
## `intent["jump"]` was unreachable. `WALL_CLEAR_GRACE` is what bridges the bounce.
##
## Modelled as alternating frames, which is the fastest bounce the body can produce and
## therefore the hardest case for the grace to survive.
func _test_jumps_through_the_bounce() -> void:
	var m: BotBrain.Memory = _mem()
	var t: float = 0.0
	var jumped: bool = false
	var pressed_frames: int = 0
	for i: int in 80:
		t += 0.05
		var touching: bool = i % 2 == 0
		var bb: Dictionary = _bb({
			"on_wall": touching, "wall_dir": 1.0 if touching else 0.0})
		var intent: Dictionary = {"move": Vector2.RIGHT}
		BotBrain._unwall(intent, bb, m, t)
		if touching:
			pressed_frames += 1
		if bool(intent.get("jump", false)):
			jumped = true
			break
	_expect(pressed_frames > 0, "the harness actually pressed it into a wall")
	_expect(jumped,
		"a bot bouncing off a wall it keeps walking back into never jumped in 4 "
			+ "seconds — rung two of the guard is unreachable in play, which is the "
			+ "corner it dies in")
	_completed["it_still_jumps_when_the_turn_breaks_contact"] = true


# --------------------------------------------------------------------------- 6
## And once it IS free, the clock must reset, or the next brush against anything
## makes it jump immediately for the rest of the bout.
##
## ⚠ THE RESET IS NOW GRACED, NOT INSTANT, and this assertion changed WITH the fix
## rather than around it. A single off-wall frame must NOT clear the clock — that
## instant reset is exactly what made rung two unreachable (see 5b). What must still
## hold is the property this test was written for: a bot that genuinely got away is
## forgotten, so it does not hop the moment it brushes the next riser.
func _test_clock_resets() -> void:
	var m: BotBrain.Memory = _mem()
	var walled: Dictionary = _bb({"on_wall": true, "wall_dir": 1.0})
	for i: int in 20:
		var a: Dictionary = {"move": Vector2.RIGHT}
		BotBrain._unwall(a, walled, m, float(i) * 0.05)
	_expect(m.wall_since >= 0.0, "the clock never started")
	# One free frame: the clock must SURVIVE, or the bounce clears it every time.
	var blink: Dictionary = {"move": Vector2.RIGHT}
	BotBrain._unwall(blink, _bb(), m, 1.0)
	_expect(m.wall_since >= 0.0,
		"a single off-wall frame cleared the stuck clock — that is the instant reset "
			+ "that made the jump rung dead code")
	# Genuinely away, for longer than the grace: now it must be forgotten.
	var free: Dictionary = {"move": Vector2.RIGHT}
	BotBrain._unwall(free, _bb(), m, 1.0 + BotBrain.WALL_CLEAR_GRACE + 0.05)
	_expect(m.wall_since < 0.0,
		"the wall clock survived getting genuinely free for longer than "
			+ "WALL_CLEAR_GRACE (%.2f s)" % BotBrain.WALL_CLEAR_GRACE)
	_completed["the_clock_resets_when_it_gets_free"] = true


# --------------------------------------------------------------------------- 7
## ⚠ THE ORDERING ASSERTION, AND THE ONE THAT MATTERS MOST. The recoil flinch writes
## `intent["move"]` AFTER `_steer` returns, and it is the single most likely path to
## start a wedge (55% of every hit taken, 0.28 s of forced retreat, no checks). A
## guard placed inside `_steer` would look correct and miss it entirely.
func _test_after_the_flinch() -> void:
	var brain: String = FileAccess.get_file_as_string("res://scripts/combat/BotBrain.gd")
	_expect(not brain.is_empty(), "could not read BotBrain.gd")
	var flinch: int = brain.find("if now < m.recoil_until:")
	var guard: int = brain.find("_unwall(intent, bb, m, now)")
	var steer: int = brain.find("intent[\"move\"] = _steer(")
	_expect(steer >= 0 and flinch >= 0 and guard >= 0,
		"could not locate the steer / flinch / unwall trio — this test is now "
		+ "measuring nothing")
	_expect(guard > flinch and guard > steer,
		"the wall guard no longer runs after every writer of intent[\"move\"] — "
		+ "the recoil flinch will walk a bot into a corner unchecked")
	_completed["the_guard_runs_after_the_recoil_flinch"] = true


# --------------------------------------------------------------------------- 8
## A blackboard missing the keys entirely (an older seam, a hand-built fixture) must
## behave exactly as it did before this feature existed.
func _test_fails_open() -> void:
	var m: BotBrain.Memory = _mem()
	var bare: Dictionary = {"self_pos": Vector2.ZERO, "foe_pos": Vector2(200.0, 0.0)}
	var intent: Dictionary = {"move": Vector2.RIGHT}
	BotBrain._unwall(intent, bare, m, 1.0)
	_expect((intent["move"] as Vector2) == Vector2.RIGHT,
		"a blackboard with no wall keys changed the bot's movement (got %s)"
			% intent["move"])
	_expect(not intent.has("jump"), "a keyless blackboard made the bot jump")
	_completed["a_body_with_no_wall_state_still_walks"] = true
