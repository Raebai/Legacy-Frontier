# BotDodge — the dodge brain's geometry, response ladder and reaction timing.
# Pure module, so all of it is provable headlessly with no scene and no physics.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_bot_dodge.gd
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
	"projectile",
	"circle",
	"lane",
	"safety",
	"ladder",
	"reactions",
]

var _fails: int = 0
var _completed: Dictionary = {}

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_projectile()
	_test_circle()
	_test_lane()
	_test_safety()
	_test_ladder()
	_test_reactions()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Bot dodge tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Bot dodge tests: all PASS")
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


func _test_projectile() -> void:
	var me := Vector2.ZERO
	# Dead-on: 300 px away closing at 300 px/s -> passes through me in 1.0 s, but
	# the horizon is 0.9, so a bolt aimed from further out is only a threat once
	# it is close enough to matter. Use 200 px to sit inside the horizon.
	var head_on: Dictionary = BotDodge.threat_from_projectile(me, Vector2(200.0, 0.0), Vector2(-300.0, 0.0))
	_expect(bool(head_on["threatening"]), "a bolt aimed dead-on is a threat")
	_expect(absf(float(head_on["tti"]) - 0.6667) < 0.02,
		"time-to-impact solves to distance/speed (got %f)" % head_on["tti"])
	_expect(float(head_on["exit_len"]) > 0.0, "a dead-on bolt yields a real exit distance")
	# Offset well clear of the body -> harmless.
	var wide: Dictionary = BotDodge.threat_from_projectile(me, Vector2(200.0, 60.0), Vector2(-300.0, 0.0))
	_expect(not bool(wide["threatening"]), "a bolt passing 60 px wide is not a threat")
	# Receding: t* clamps to 0, so it reports its current distance and reads safe.
	var away: Dictionary = BotDodge.threat_from_projectile(me, Vector2(200.0, 0.0), Vector2(300.0, 0.0))
	_expect(not bool(away["threatening"]), "a bolt already past me is not a threat")
	_expect(is_equal_approx(float(away["t"] if away.has("t") else away["tti"]), 0.0),
		"a receding bolt clamps time-to-impact to 0")
	# The exit is SIDEWAYS out of the lane, not backwards down it.
	_expect(absf((head_on["exit"] as Vector2).y) > absf((head_on["exit"] as Vector2).x),
		"exit from a horizontal bolt is vertical (step off the lane)")
	_completes("projectile")


func _test_circle() -> void:
	# Standing still, 20 px off centre of a 90 px blast -> caught, exit points away.
	var caught: Dictionary = BotDodge.threat_from_circle(
		Vector2(20.0, 0.0), Vector2.ZERO, Vector2.ZERO, 90.0, 0.4)
	_expect(bool(caught["threatening"]), "standing inside a marked circle is a threat")
	_expect((caught["exit"] as Vector2).x > 0.0, "exit runs directly away from the centre")
	_expect(float(caught["exit_len"]) > 90.0 - 20.0 - 1.0,
		"exit clears the radius, not just the edge (got %f)" % caught["exit_len"])
	# Far outside -> ignored.
	var clear: Dictionary = BotDodge.threat_from_circle(
		Vector2(300.0, 0.0), Vector2.ZERO, Vector2.ZERO, 90.0, 0.4)
	_expect(not bool(clear["threatening"]), "standing well outside the circle is safe")
	# MOVING OUT already: prediction must be believed, or the bot dodges twice.
	var leaving: Dictionary = BotDodge.threat_from_circle(
		Vector2(80.0, 0.0), Vector2(400.0, 0.0), Vector2.ZERO, 90.0, 0.5)
	_expect(not bool(leaving["threatening"]),
		"already running out at speed means no second dodge is needed")
	# Dead centre has no shortest exit — must be flagged, not silently Vector2.ZERO.
	var dead: Dictionary = BotDodge.threat_from_circle(
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, 90.0, 0.4)
	_expect(bool(dead["degenerate"]), "dead-centre is reported as degenerate")
	_expect(bool(dead["threatening"]), "dead-centre is still a threat")
	_completes("circle")


func _test_lane() -> void:
	# Lane from origin, straight right, 200 long, 40 wide (half = 20 + margin 14 = 34).
	var inside: Dictionary = BotDodge.threat_from_lane(
		Vector2(100.0, 10.0), Vector2.ZERO, Vector2.ZERO, 0.0, 200.0, 40.0, 0.4)
	_expect(bool(inside["threatening"]), "a point inside the lane is a threat")
	_expect((inside["exit"] as Vector2).y > 0.0, "exit is perpendicular, toward the near side")
	# Just outside the half-width+margin band.
	var beside: Dictionary = BotDodge.threat_from_lane(
		Vector2(100.0, 40.0), Vector2.ZERO, Vector2.ZERO, 0.0, 200.0, 40.0, 0.4)
	_expect(not bool(beside["threatening"]), "a point beside the lane is safe")
	# Past the end of the lane.
	var past: Dictionary = BotDodge.threat_from_lane(
		Vector2(260.0, 0.0), Vector2.ZERO, Vector2.ZERO, 0.0, 200.0, 40.0, 0.4)
	_expect(not bool(past["threatening"]), "a point beyond the lane length is safe")
	# Behind the origin.
	var behind: Dictionary = BotDodge.threat_from_lane(
		Vector2(-30.0, 0.0), Vector2.ZERO, Vector2.ZERO, 0.0, 200.0, 40.0, 0.4)
	_expect(not bool(behind["threatening"]), "a point behind the lane origin is safe")
	# A rotated lane must behave identically in its own frame.
	var rot: Dictionary = BotDodge.threat_from_lane(
		Vector2(0.0, 100.0), Vector2.ZERO, Vector2.ZERO, PI * 0.5, 200.0, 40.0, 0.4)
	_expect(bool(rot["threatening"]), "a rotated lane still contains its centreline")
	_completes("lane")


func _test_safety() -> void:
	var me := Vector2.ZERO
	var left := Vector2(-60.0, 0.0)
	var right := Vector2(60.0, 0.0)
	# A pit under the left exit must push the choice right, even though both are
	# the same length.
	var pit := Rect2(Vector2(-120.0, -40.0), Vector2(100.0, 200.0))
	var pick: Vector2 = BotDodge.safest_exit(me, [left, right], [pit], [])
	_expect(pick == right, "never dodge into a pit (picked %s)" % pick)
	# A second live telegraph over the right exit flips it back.
	var other: Dictionary = {"shape": "circle", "center": Vector2(60.0, 0.0), "radius": 30.0}
	var pick2: Vector2 = BotDodge.safest_exit(me, [left, right], [], [other])
	_expect(pick2 == left, "never dodge into another live telegraph (picked %s)" % pick2)
	# Both bad -> report no safe exit rather than inventing one.
	var pick3: Vector2 = BotDodge.safest_exit(me, [left, right],
		[Rect2(Vector2(-500.0, -500.0), Vector2(1000.0, 1000.0))], [])
	_expect(pick3 == Vector2.ZERO, "no safe exit is reported honestly")
	# Region containment for a lane shape.
	_expect(BotDodge.point_in_region(Vector2(50.0, 0.0),
		{"shape": "line", "from": Vector2.ZERO, "to": Vector2(200.0, 0.0), "width": 40.0}),
		"lane region contains its centreline")
	_expect(not BotDodge.point_in_region(Vector2(50.0, 200.0),
		{"shape": "line", "from": Vector2.ZERO, "to": Vector2(200.0, 0.0), "width": 40.0}),
		"lane region excludes a far point")
	_completes("safety")


func _test_ladder() -> void:
	var threat := {"threatening": true, "tti": 0.4, "exit": Vector2(0.0, -50.0), "exit_len": 50.0}
	# Dash clears 87 px > 50 px needed -> dash wins outright, for a HORIZONTAL exit.
	var flat := {"threatening": true, "tti": 0.4, "exit": Vector2(-50.0, 0.0), "exit_len": 50.0}
	var r1: Dictionary = BotDodge.choose_response(flat,
		{"dash_ready": true, "dash_dist": 87.0, "grounded": true})
	_expect(String(r1["action"]) == "dash", "prefers a dash that clears the region")
	# ⚠ THIS EXPECTATION WAS FLIPPED, and the old one was the bug. It asserted that a
	# grounded body answers a VERTICAL exit with a dash. A dash is pressed through the
	# movement keys, `BotBrain._flatten` has to drop a vertical component (there is no
	# "walk down"), so that dash reached the body with no direction and did nothing —
	# while latching the reflex layer for the length of the dodge latch. Since a bolt
	# crossing between two fighters on the same floor is horizontal, its exit is always
	# vertical, so this was EVERY projectile dodge in a duel.
	var r1b: Dictionary = BotDodge.choose_response(threat,
		{"dash_ready": true, "dash_dist": 87.0, "grounded": true})
	_expect(String(r1b["action"]) == "jump", "jumps a vertical exit even with the dash up")
	# Dash cooling, exit is vertical, grounded -> jump.
	var r2: Dictionary = BotDodge.choose_response(threat,
		{"dash_ready": false, "grounded": true})
	_expect(String(r2["action"]) == "jump", "falls to a jump for a vertical exit")
	# Airborne with a vertical exit: cannot jump, cannot express the direction. It must
	# NOT hand back a dash the body will drop — i-frames are the only honest answer.
	var r2b: Dictionary = BotDodge.choose_response(threat,
		{"dash_ready": true, "dash_dist": 87.0, "grounded": false})
	_expect(String(r2b["action"]) != "dash", "never dashes a vertical exit it cannot steer")
	# Dash cooling, airborne, horizontal exit -> walk it out.
	var side := {"threatening": true, "tti": 0.5, "exit": Vector2(50.0, 0.0), "exit_len": 50.0}
	var r3: Dictionary = BotDodge.choose_response(side, {"dash_ready": false, "grounded": false})
	_expect(String(r3["action"]) == "walk", "falls to walking out")
	# Blink covers what a dash cannot.
	var far := {"threatening": true, "tti": 0.5, "exit": Vector2(150.0, 0.0), "exit_len": 150.0}
	var r4: Dictionary = BotDodge.choose_response(far,
		{"dash_ready": true, "dash_dist": 87.0, "blink_ready": true, "blink_dist": 175.0})
	_expect(String(r4["action"]) == "blink", "blinks when the dash cannot reach")
	# Parry only inside its window.
	var soon := {"threatening": true, "tti": 0.1, "exit": Vector2(150.0, 0.0), "exit_len": 150.0}
	var r5: Dictionary = BotDodge.choose_response(soon,
		{"can_parry": true, "parry_ready": true, "parry_window": 0.16})
	_expect(String(r5["action"]) == "parry", "parries a hit landing inside the window")
	var late := {"threatening": true, "tti": 0.6, "exit": Vector2(150.0, 0.0), "exit_len": 150.0}
	var r6: Dictionary = BotDodge.choose_response(late,
		{"can_parry": true, "parry_ready": true, "parry_window": 0.16})
	_expect(String(r6["action"]) != "parry", "does not parry a hit that is still far off")
	# i-frame dash is gated: same threat, allow_iframe off vs on.
	var imminent := {"threatening": true, "tti": 0.1, "exit": Vector2.ZERO, "exit_len": 400.0}
	var r7: Dictionary = BotDodge.choose_response(imminent,
		{"dash_ready": true, "dash_dist": 87.0, "allow_iframe": false})
	_expect(String(r7["action"]) != "dash_iframe", "i-frame dash is off by default")
	var r8: Dictionary = BotDodge.choose_response(imminent,
		{"dash_ready": true, "dash_dist": 87.0, "allow_iframe": true})
	_expect(String(r8["action"]) == "dash_iframe", "i-frame dash unlocks at the top tiers")
	# Not threatening -> do nothing at all.
	var r9: Dictionary = BotDodge.choose_response({"threatening": false}, {"dash_ready": true})
	_expect(String(r9["action"]) == "none", "no threat means no reaction")
	_completes("ladder")


func _test_reactions() -> void:
	var r := BotDodge.Reactions.new()
	r.observe(1, 0.0, 0.25)
	_expect(not r.visible(1, 0.24), "a threat is invisible before the reaction delay")
	_expect(r.visible(1, 0.26), "a threat becomes visible after the reaction delay")
	# Re-observing must not restart the clock, or the bot never reacts.
	r.observe(1, 0.30, 0.25)
	_expect(r.visible(1, 0.31), "re-sighting does not reset an elapsed reaction")
	# Whiff is rolled once, at first sighting, and sticks.
	var w := BotDodge.Reactions.new()
	w.observe(2, 0.0, 0.1, 0.01, 0.45)      # roll below p_miss -> fumble this one
	_expect(not w.visible(2, 5.0), "a whiffed threat stays unreacted-to")
	w.observe(3, 0.0, 0.1, 0.99, 0.45)      # roll above p_miss -> react normally
	_expect(w.visible(3, 0.2), "a non-whiffed threat is reacted to")
	# Forgetting, so a recycled instance id cannot inherit an elapsed reveal.
	_expect(w.tracked() == 2, "tracks both threats before pruning")
	w.forget_missing([3])
	_expect(w.tracked() == 1, "prunes threats that no longer exist")
	w.observe(2, 10.0, 0.25, 0.99, 0.0)
	_expect(not w.visible(2, 10.1), "a recycled id starts a fresh reaction clock")
	_completes("reactions")
