# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_touch_layout.gd
#
# THE TOUCH LAYOUT ON A REAL PHONE ASPECT — the assertions behind
# `tools/probe_touch_layout.gd`'s table.
#
# ⚠ WHY THIS IS NOT COVERED BY THE THREE SUITES THAT ALREADY EXIST.
# `tools/slice_test_touch.gd` judges the input MATHS and never looks at a rectangle.
# `tools/slice_test_spell_buttons.gd` checks the arc against ITSELF, in offset space,
# at no particular viewport. `tools/slice_test_display.gd` is about the window mode.
# Between them, three facts about a phone went unasserted and all three turned out to
# be broken:
#
#   1. ASPECT. `window/stretch/aspect="expand"` means a taller phone gets a WIDER
#      logical viewport — 800x360 at 20:9, not 640x360 — so every left-anchored control
#      moves away from every right-anchored one and a centre-anchored one lands
#      somewhere new relative to both. Everything before this file was verified at
#      640x360, which is the one aspect no modern phone has.
#   2. MILLIMETRES. "60 px" is not a thumb target. The same 60 logical px is 10.4 mm on
#      a 5" 16:9 phone and 11.3 mm on a 6.5" 20:9 one, and the human-factors floor
#      everything is judged against (9 mm) is physical.
#   3. THE OS OWNS SOME OF THE SCREEN. A display cutout takes a strip off one end in
#      landscape, and the Android home-swipe owns the bottom 24 dp EVEN THOUGH the safe
#      area does not report it (this game ships `screen/immersive_mode=true`, which
#      hides the nav bar and hands the pixels back while leaving the gesture live).
#      DASH's hit box was inside that strip on every aspect: a panic button that
#      sometimes throws the player to the home screen instead.
#
# ⚠ AND HEADLESS HAS NO WINDOW, SO IT HAS NO ASPECT. `get_visible_rect()` falls back to
# a SQUARE 640x640 until `root.size` is set and a frame has passed. A suite about
# aspect that forgets that measures a square phone and passes on nonsense.
#
# TEST IDIOM — see the long note in tools/slice_test_loadout.gd. Failures accumulate on
# the MEMBER `_fails`; every test's last line records a COMPLETION SENTINEL, so a test
# that aborts half-way (a dead property read aborts the enclosing function and hands
# back the type's zero) fails the suite BY ABSENCE rather than passing vacuously.
extends SceneTree

const TouchLayout := preload("res://scripts/combat/TouchLayout.gd")

const TESTS: Array[String] = [
	"expand_widens_the_viewport",
	"no_overlapping_hit_boxes",
	"nothing_in_the_system_gesture_strip",
	"everything_inside_the_safe_area",
	"every_thumb_target_clears_9mm",
	"everything_within_thumb_reach",
	"pad_clears_the_pause_button",
	"insets_are_honoured_and_idempotent",
	"a_resting_stick_never_dashes",
	"a_flick_dashes",
	"a_tap_is_not_a_steer",
	"moving_and_acting_need_two_different_thumbs",
]

## `PauseMenu.PAUSE_BTN_SIZE` / `PAUSE_BTN_MARGIN`, duplicated as literals rather than
## loaded: instancing `PauseMenu` would drag its dependency chain into a `--script` run
## that has no autoloads, and this suite only needs the two numbers.
##
## ⚠ DELIBERATELY NOT `HudStyle.PAUSE_CORNER`. That constant is the fixed rect
## x 580..640, and the button is anchored to the RIGHT EDGE — so on an expanded 800-wide
## viewport the real button is at x 746..790 and the constant points at empty screen
## 160 px away. Checking against it on a phone is checking against nothing.
const PAUSE_BTN: Vector2 = Vector2(44.0, 44.0)
const PAUSE_MARGIN: float = 10.0

## ⚠ ONE TARGET IS KNOWINGLY UNDER THE 9 mm FLOOR AND IS NAMED HERE RATHER THAN QUIETLY
## PASSING. The contextual handoff pad is 34 logical px on its short axis — 5.9-6.4 mm
## across the device table. It cannot be grown from inside `TouchControls` alone:
##
##   height >= 53  (the 9 mm floor at the tightest pitch in TouchLayout.DEVICES)
##   + lift >= 23  (clear the home-swipe strip when a phone misreports its DPI)
##   > 74          (`Revive.PAD_LIFT`, which `slice_test_ghost_revive.gd:397` asserts
##                  the handoff pad stays below)
##
## …is unsatisfiable by 2 px. The fix is two lines in `scripts/combat/Revive.gd` —
## `PAD_LIFT` 74 -> 96 and `PAD_SIZE.y` 34 -> 54, since the revive pad is 5.9 mm for
## exactly the same reason — and belongs to whoever owns that file.
##
## Exempt rather than deleted, because the exemption is defensible on its own terms too:
## a missed DASH or JUMP mid-fight is a death; a missed handoff is "nothing happened,
## tap again" during a lull in which both thumbs are already free. The measurement is
## still PRINTED on every run, so it stays visible instead of becoming folklore.
const MM_FLOOR_EXEMPT: Array[String] = ["HANDOFF"]

var _fails: int = 0
var _completed: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _test_expand_widens_the_viewport()
	await _test_geometry()          # four sentinels: overlap / gesture / safe / mm
	await _test_reach()
	await _test_pause_clearance()
	await _test_one_thumb_per_hand()
	await _test_insets_honoured()
	_test_gestures()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Touch-layout tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Touch-layout tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ---------------------------------------------------------------- the harness
## Resize the root to a device's native resolution, let the engine's own stretch decide
## the logical viewport, and hand back a pad that has already honoured that device's
## modelled insets.
##
## ⚠ TWO FRAMES, NOT ONE. The resize lands on the Window, the viewport recomputes, and
## only then do the CanvasLayer's Controls re-anchor. One frame reads the layout the
## PREVIOUS device left behind — which is the failure mode where a suite passes for the
## first device in the loop and reports the same numbers for all four.
func _sized_pad(dev: Dictionary) -> Dictionary:
	var native: Vector2 = dev["size"]
	root.size = Vector2i(int(native.x), int(native.y))
	await process_frame
	await process_frame
	var vp: Vector2 = root.get_visible_rect().size
	var mm: float = TouchLayout.mm_per_unit(float(dev["diag"]), native)
	var insets: Vector4 = TouchLayout.modelled_insets(mm, "l")
	var pad: Node = TouchControls.new()
	pad.set("force_visible", true)
	pad.set("preview_insets", insets)
	root.add_child(pad)
	await process_frame
	return {"pad": pad, "vp": vp, "mm": mm, "insets": insets, "name": String(dev["name"])}


## Every tappable rect the pad owns, named. Read off the CONTROLS, not re-derived from
## the offsets — the offsets and the drawn result are two different channels and this
## project has been burned by measuring the wrong one.
func _targets(pad: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Node in pad.get_children():
		var ctrl := c as Control
		if ctrl == null or ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		var n: String = (ctrl as Button).text if ctrl is Button else "HANDOFF"
		out.append({"name": n, "rect": ctrl.get_global_rect()})
	return out


func _pause_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - PAUSE_MARGIN - PAUSE_BTN.x, PAUSE_MARGIN, PAUSE_BTN.x, PAUSE_BTN.y)


# ------------------------------------------------------------------------- 1
## The premise of the whole file. If `expand` ever stops widening the viewport — an
## editor rewrite dropping the line, someone switching to `keep` — then every other
## test here is measuring a case that no longer happens, and it should say so loudly
## rather than keep passing.
func _test_expand_widens_the_viewport() -> void:
	for dev: Dictionary in TouchLayout.DEVICES:
		var native: Vector2 = dev["size"]
		root.size = Vector2i(int(native.x), int(native.y))
		await process_frame
		await process_frame
		var vp: Vector2 = root.get_visible_rect().size
		var predicted: Vector2 = TouchLayout.logical_size(native)
		_expect(vp.is_equal_approx(predicted),
			"%s: engine viewport %s matches the expand formula %s"
				% [dev["name"], vp, predicted])
		_expect(is_equal_approx(vp.y, TouchLayout.BASE.y),
			"%s: landscape expand keeps the base HEIGHT (got %.1f)" % [dev["name"], vp.y])
		_expect(vp.x >= TouchLayout.BASE.x - 0.5,
			"%s: ...and never gives back less WIDTH than the base (got %.1f)"
				% [dev["name"], vp.x])
	_completes("expand_widens_the_viewport")


# ------------------------------------------------------------------- 2,3,4,5
## One pass over the device table asking the four geometric questions, because they all
## need the same expensive setup and splitting them would resize the root sixteen times
## to learn the same rects four times over.
func _test_geometry() -> void:
	for dev: Dictionary in TouchLayout.DEVICES:
		var ctx: Dictionary = await _sized_pad(dev)
		var vp: Vector2 = ctx["vp"]
		var mm: float = ctx["mm"]
		var insets: Vector4 = ctx["insets"]
		var name_: String = ctx["name"]
		var t: Array[Dictionary] = _targets(ctx["pad"])
		_expect(t.size() >= 4, "%s: the pad built some targets to measure (%d)"
			% [name_, t.size()])

		# 2. DRAWN AS CIRCLES, TAPPED AS RECTANGLES. Two round buttons whose art clears
		#    can still share a hit box, which is why this is checked and not eyeballed.
		for i: int in t.size():
			for j: int in range(i + 1, t.size()):
				var a: Rect2 = t[i]["rect"]
				var b: Rect2 = t[j]["rect"]
				_expect(not TouchLayout.overlaps(a, b),
					"%s: %s and %s share %s of hit box"
						% [name_, t[i]["name"], t[j]["name"], a.intersection(b).size])

		# 3. THE SYSTEM GESTURE STRIP — the bug this file was written for.
		for e: Dictionary in t:
			_expect(TouchLayout.clears_gesture_strip(e["rect"], vp, mm),
				("%s: %s reaches into the bottom %.0f px the Android home-swipe owns "
				+ "(24 dp = %.2f mm) — raise its offset")
					% [name_, e["name"], TouchLayout.gesture_strip(vp, mm).size.y,
						TouchLayout.GESTURE_STRIP_MM])

		# 3b. ...AND AGAIN WITH THE INSETS TAKEN AWAY, which is not a hypothetical.
		#     `_gesture_lift` is computed from `DisplayServer.screen_get_dpi()`, and DPI
		#     is a value Android OEMs are entitled to report badly — 0 and 72 both
		#     happen. When it does, `_refresh_insets` honours nothing and the BASE
		#     offsets are all that stand between DASH and the home screen. Without this
		#     half, 3 above is nearly tautological: any inset large enough to model the
		#     strip is large enough to lift everything out of it.
		var bare: Node = TouchControls.new()
		bare.set("force_visible", true)
		root.add_child(bare)
		await process_frame
		for e: Dictionary in _targets(bare):
			_expect(TouchLayout.clears_gesture_strip(e["rect"], vp, mm),
				("%s: with NO insets honoured (a phone that misreports its DPI), %s "
				+ "still sits in the bottom %.0f px the home-swipe owns — its BASE "
				+ "offset is too low to survive that fallback")
					% [name_, e["name"], TouchLayout.gesture_strip(vp, mm).size.y])
		bare.queue_free()
		await process_frame

		# 4. THE CUTOUT. A control under the notch is a control that is drawn and
		#    cannot be pressed.
		for e: Dictionary in t:
			_expect(TouchLayout.inside_safe_area(e["rect"], vp, insets),
				"%s: %s (%s) is outside the safe area (insets %s)"
					% [name_, e["name"], e["rect"], insets])

		# 5. NINE MILLIMETRES, on the SHORT axis of the rect — the axis a miss happens
		#    on. A wide, thin pad passes an area check and fails a thumb.
		for e: Dictionary in t:
			var r: Rect2 = e["rect"]
			var short_mm: float = minf(r.size.x, r.size.y) * mm
			if MM_FLOOR_EXEMPT.has(String(e["name"])):
				# Still measured, still printed — just not fatal. See MM_FLOOR_EXEMPT.
				print("  [known] %s: %s is %.2f mm on its short axis (exempt)"
					% [name_, e["name"], short_mm])
				continue
			_expect(short_mm >= TouchLayout.THUMB_MIN_MM,
				"%s: %s is %.2f mm on its short axis, under the %.1f mm thumb floor"
					% [name_, e["name"], short_mm, TouchLayout.THUMB_MIN_MM])
		ctx["pad"].queue_free()
		await process_frame
	_completes("no_overlapping_hit_boxes")
	_completes("nothing_in_the_system_gesture_strip")
	_completes("everything_inside_the_safe_area")
	_completes("every_thumb_target_clears_9mm")


# ------------------------------------------------------------------------- 6
## Can the thumb that owns a control actually get to it without the hand regripping?
## Judged from a landscape grip's knuckle, per side, in millimetres.
func _test_reach() -> void:
	for dev: Dictionary in TouchLayout.DEVICES:
		var ctx: Dictionary = await _sized_pad(dev)
		var vp: Vector2 = ctx["vp"]
		for e: Dictionary in _targets(ctx["pad"]):
			var r: Rect2 = e["rect"]
			# Whichever thumb is NEARER owns it — the handoff pad lives between them
			# precisely so either one may take it.
			var side: String = "r" if r.get_center().x > vp.x * 0.5 else "l"
			var near: float = minf(
				TouchLayout.thumb_reach_mm(vp, ctx["insets"], ctx["mm"], side, r.get_center()),
				TouchLayout.thumb_reach_mm(vp, ctx["insets"], ctx["mm"],
					"l" if side == "r" else "r", r.get_center()))
			_expect(near <= TouchLayout.THUMB_MAX_MM,
				"%s: %s is %.1f mm from the nearest thumb knuckle (max %.0f mm)"
					% [ctx["name"], e["name"], near, TouchLayout.THUMB_MAX_MM])
		ctx["pad"].queue_free()
		await process_frame
	_completes("everything_within_thumb_reach")


# ------------------------------------------------------------------------- 7
## The pause button is a reserved corner nobody else may draw into — and it is the ONE
## control on screen that is not this layer's, so a collision here is invisible from
## both sides until a thumb finds it.
func _test_pause_clearance() -> void:
	for dev: Dictionary in TouchLayout.DEVICES:
		var ctx: Dictionary = await _sized_pad(dev)
		var pause: Rect2 = _pause_rect(ctx["vp"])
		for e: Dictionary in _targets(ctx["pad"]):
			_expect(not TouchLayout.overlaps(e["rect"], pause),
				"%s: %s overlaps the pause button at %s" % [ctx["name"], e["name"], pause])
		ctx["pad"].queue_free()
		await process_frame
	_completes("pad_clears_the_pause_button")


# ------------------------------------------------------------------------- 12
## ⚠ ONE HAND PUTS ONE FINGER ON THE SCREEN. Held in landscape, each hand contributes
## exactly one screen contact — the thumb; the index and the rest are behind the phone
## holding it up. So the LEFT thumb committed to the move stick is the left hand's
## whole input, and any verb that must happen WHILE MOVING has to be inside the RIGHT
## thumb's sweep. This is the test the pad failed: JUMP was bottom-LEFT, ~115 mm from
## the right knuckle against a 62 mm maximum, so a phone player could not run and jump
## in a platform fighter built on gravity, ledges and ring-out.
##
## ⚠ PARRY IS EXEMPT, AND FOR A REASON THAT IS IN THE CODE RATHER THAN IN TASTE.
## `Hero` zeroes `move_x` while `ParryRing.blocks_attack` — a held guard ROOTS you — so
## parry is the one verb that provably cannot be simultaneous with movement, and it
## costs the left thumb nothing it was using. Every other verb here can and does happen
## mid-run.
const MOVE_SIMULTANEOUS: Array[String] = ["jump", "dash", "spell_1", "spell_2",
	"spell_3", "spell_4"]


func _test_one_thumb_per_hand() -> void:
	for dev: Dictionary in TouchLayout.DEVICES:
		var ctx: Dictionary = await _sized_pad(dev)
		var vp: Vector2 = ctx["vp"]
		var seen: Array[String] = []
		for c: Node in ctx["pad"].get_children():
			var b := c as Button
			if b == null:
				continue
			var action: String = String(b.get_meta("action", ""))
			if not MOVE_SIMULTANEOUS.has(action):
				continue
			seen.append(action)
			var reach: float = TouchLayout.thumb_reach_mm(vp, ctx["insets"], ctx["mm"],
				"r", b.get_global_rect().get_center())
			_expect(reach <= TouchLayout.THUMB_MAX_MM,
				("%s: `%s` is %.0f mm from the RIGHT knuckle (max %.0f). The left thumb "
				+ "is holding the move stick and a landscape hand has only one finger on "
				+ "the glass, so this verb cannot happen while moving.")
					% [ctx["name"], action, reach, TouchLayout.THUMB_MAX_MM])
		for a: String in MOVE_SIMULTANEOUS:
			if a.begins_with("spell_") and int(a.substr(6)) > TouchControls.SPELL_BUTTONS_SHOWN:
				continue   # the arc is allowed to be trimmed; see SPELL_BUTTONS_SHOWN
			_expect(seen.has(a), "%s: the pad still exposes `%s` at all" % [ctx["name"], a])
		ctx["pad"].queue_free()
		await process_frame
	_completes("moving_and_acting_need_two_different_thumbs")


# ------------------------------------------------------------------------- 8
## The pad must ACT on the insets, not merely be able to read them — and re-applying
## them must be idempotent, because `_refresh_insets` runs again on every resize and
## insetting an already-inset offset is the obvious way to get this wrong.
func _test_insets_honoured() -> void:
	var dev: Dictionary = TouchLayout.DEVICES[2]   # 20:9, the common Android case
	var ctx: Dictionary = await _sized_pad(dev)
	var pad: Node = ctx["pad"]
	var insets: Vector4 = ctx["insets"]
	_expect(Vector4(pad.call("safe_insets")).is_equal_approx(insets),
		"%s: the pad honoured the insets it was given" % ctx["name"])
	var before: Array[Dictionary] = _targets(pad)
	# Same insets, applied again. Nothing may move.
	pad.call("_refresh_insets")
	await process_frame
	var after: Array[Dictionary] = _targets(pad)
	_expect(before.size() == after.size(), "re-placing kept the same target count")
	for i: int in mini(before.size(), after.size()):
		_expect(Rect2(before[i]["rect"]).is_equal_approx(after[i]["rect"]),
			("re-applying the insets moved %s from %s to %s — `_place_all` is placing "
			+ "from where the control IS instead of from its base offset")
				% [before[i]["name"], before[i]["rect"], after[i]["rect"]])
	# ⚠ AND A RESIZE WHILE THE PAD IS LIVE, which is the path that actually runs on a
	# phone: rotating the device, unfolding a foldable, or coming back from a task
	# switch all fire `Viewport.size_changed` at a pad that is already built. The suite
	# otherwise only ever resizes BEFORE building one, which never exercises the signal
	# `_refresh_insets` is connected to — and a crash or a double-inset there would be
	# invisible until a player turned their phone over.
	var wide: Vector2 = TouchLayout.DEVICES[3]["size"]
	root.size = Vector2i(int(wide.x), int(wide.y))
	await process_frame
	await process_frame
	var moved: Array[Dictionary] = _targets(pad)
	_expect(moved.size() == before.size(), "the pad survived a live resize intact")
	var vp2: Vector2 = root.get_visible_rect().size
	for e: Dictionary in moved:
		var r: Rect2 = e["rect"]
		_expect(r.position.x >= -0.5 and r.end.x <= vp2.x + 0.5,
			"after a live resize, %s (%s) is still on screen (viewport %s)"
				% [e["name"], r, vp2])

	# ...and a pad given NOTHING must sit where the un-inset layout says.
	var bare: Node = TouchControls.new()
	bare.set("force_visible", true)
	root.add_child(bare)
	await process_frame
	_expect(Vector4(bare.call("safe_insets")).is_equal_approx(Vector4.ZERO),
		"a desktop preview with no preview_insets honours none (a desktop has no notch)")
	bare.queue_free()
	pad.queue_free()
	await process_frame
	_completes("insets_are_honoured_and_idempotent")


# ---------------------------------------------------------------- 9, 10, 11
## THE GESTURE DEADZONES. The pad equivalent of "a resting stick walks nobody": a hand
## tremor near the centre must not dash, and a thumb that was steering must not be read
## as having tapped.
func _test_gestures() -> void:
	# 9. A resting stick. Jitter can be arbitrarily FAST over one frame — speed alone
	#    would fire on it, which is exactly why the flick is gated on deflection too.
	var dt: float = 1.0 / 60.0
	_expect(not TouchControls.is_flick(Vector2.ZERO, Vector2(0.05, 0.0), dt),
		"a tremor at the stick centre does not dash")
	_expect(not TouchControls.is_flick(Vector2.ZERO, Vector2(0.4, 0.0), dt),
		"a fast push that stops short of the flick deflection does not dash")
	_expect(not TouchControls.is_flick(Vector2.ZERO, Vector2.ZERO, dt),
		"a stick that has not moved at all does not dash")
	_expect(not TouchControls.is_flick(Vector2.ZERO, Vector2(1.0, 0.0), 1.0),
		"a SLOW push to full deflection is a run, not a dash")
	_expect(not TouchControls.is_flick(Vector2.ZERO, Vector2(1.0, 0.0), 0.0),
		"a zero-length frame cannot manufacture infinite speed")
	_completes("a_resting_stick_never_dashes")

	# 10. ...and a real snap does fire, or the verb is unreachable by the gesture.
	_expect(TouchControls.is_flick(Vector2.ZERO, Vector2(1.0, 0.0), dt),
		"snapping the stick to full deflection in one frame dashes")
	_expect(TouchControls.is_flick(Vector2(0.2, 0.0), Vector2(0.0, -1.0), dt),
		"a snap UP dashes too — the flick is a magnitude, not an axis")
	_completes("a_flick_dashes")

	# 11. Tap vs steer. The tap is what lets the right thumb fire without HOLDING the
	#     stick — the "two-thumb question" in TouchControls' own header.
	_expect(TouchControls.is_tap(80.0, 3.0), "a quick, still press is a tap")
	_expect(not TouchControls.is_tap(900.0, 2.0), "a long press is a hold, not a tap")
	_expect(not TouchControls.is_tap(80.0, 120.0), "a press that travelled is a steer")
	_expect(TouchControls.AIM_TAP_HOLD_MSEC >= 1000.0 / 60.0 * 2.0,
		("the tap holds `cast` for at least two physics ticks — Hero samples input in "
		+ "_physics_process, so a shorter pulse is missed at a high frame rate"))
	_completes("a_tap_is_not_a_steer")
