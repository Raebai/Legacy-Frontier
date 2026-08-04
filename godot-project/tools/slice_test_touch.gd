# Run: godot --headless --path godot-project --script tools/slice_test_touch.gd
# Verifies the mobile TouchControls layer: self-hides on a non-touch desktop (so
# keyboard/mouse play is unaffected), builds its buttons when forced, and its two
# thumb sticks publish the real named input actions with analog strength.
#
# The part of a touch layer that CAN be judged without a device is the input maths,
# and that is what this file is for. Everything about reach, size and feel is
# unverifiable here and is the maker's on-device pass.
#
# The bug this suite now guards: TouchControls used to publish only move_left /
# move_right / move_down — no upward component ANYWHERE — which was survivable only
# while Hero auto-aimed at the nearest enemy. With auto-aim deleted (locked rule: you
# point, you throw), a touch player could not aim at anything above them. So: aim has
# its own stick and its own actions, movement got its missing up, and both are swept
# through a full 360 here looking for dead sectors.
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
	"hidden_on_desktop",
	"forced_builds_buttons",
	"buttons_drive_real_actions",
	"move_injection",
	"aim_actions_exist",
	"move_stick_publishes_up",
	"move_and_aim_are_decoupled",
	"aim_straight_up",
	"aim_full_360_no_dead_sector",
	"aim_deadzone_holds_last_aim",
	"aim_stick_fires",
	"hero_reads_the_aim_stick",
]

var _fails: int = 0
var _completed: Dictionary = {}

## Mirrors Hero's aim read EXACTLY (Hero._physics_process). If these two ever drift,
## the round-trip tests below stop meaning anything — so the formula lives in one
## obvious place and is commented as a mirror on both sides.
const HERO_PATH: String = "res://scripts/combat/Hero.gd"
## Hero.TOUCH_AIM_DEADZONE — the single magnitude deadzone for aiming. Duplicated as a
## literal rather than loaded, because loading Hero.gd pulls its whole dependency
## chain (autoloads included) into a --script run that has none of them registered.
const HERO_AIM_DEADZONE: float = 0.20

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_hidden_on_desktop()
	_test_forced_builds_buttons()
	_test_buttons_drive_real_actions()
	_test_move_injection()
	_test_aim_actions_exist()
	_test_move_stick_publishes_up()
	_test_move_and_aim_are_decoupled()
	_test_aim_straight_up()
	_test_aim_full_360_no_dead_sector()
	_test_aim_deadzone_holds_last_aim()
	_test_aim_stick_fires()
	_test_hero_reads_the_aim_stick()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Touch tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Touch tests: all PASS")
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


## A forced-visible pad, parented so its _ready runs and it builds its controls.
func _pad() -> TouchControls:
	var pad := TouchControls.new()
	pad.force_visible = true
	root.add_child(pad)
	return pad


## The aim vector a consumer (Hero) reads back out of the input map. MIRROR of
## Hero._physics_process — keep the two in step.
func _read_aim() -> Vector2:
	return Vector2(
		Input.get_action_strength("aim_right") - Input.get_action_strength("aim_left"),
		Input.get_action_strength("aim_down") - Input.get_action_strength("aim_up")
	)


## Drop everything this suite may have left held, so one test can never poison the
## next (Input state is global and survives the node being freed).
func _clear_input() -> void:
	for a: String in ["move_left", "move_right", "move_up", "move_down",
			"aim_left", "aim_right", "aim_up", "aim_down", "cast", "jump"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


## Headless (no touchscreen) + not forced -> the pad hides, so desktop is untouched.
func _test_hidden_on_desktop() -> void:
	var pad := TouchControls.new()
	root.add_child(pad)
	_expect(not pad.visible, "pad hides on non-touch desktop")
	pad.queue_free()
	_completes("hidden_on_desktop")


## Forced visible -> the pad renders + builds its thumb buttons.
func _test_forced_builds_buttons() -> void:
	var pad := _pad()
	var buttons: int = 0
	for c: Node in pad.get_children():
		if c is Button:
			buttons += 1
	_expect(pad.visible, "forced pad is visible")
	# The hand + dash + jump + parry. Deliberately an EQUALITY: the point of the
	# consolidation pass was that a phone is not a keyboard, so a layer that quietly grew
	# an extra button should fail here rather than pass a `>=`. DERIVED from
	# `SpellTier.SLOT_COUNT` rather than written as 6, because the spell buttons are the
	# one part of this pad that is allowed to move and it just did (3 -> 4).
	var want: int = SpellTier.SLOT_COUNT + 3
	_expect(buttons == want, "pad built the %d thumb buttons (got %d)" % [want, buttons])
	pad.queue_free()
	_completes("forced_builds_buttons")


## Every action a touch button drives must EXIST in the input map AND be an action
## something actually polls. The JUMP button shipped pressing "move_up" while
## Hero polls "jump", so touch jump was dead on a device — and the old test still
## passed, because counting buttons never checks what they are wired to.
##
## ⚠ THE REQUIRED LIST CHANGED, DELIBERATELY, with the three-spell-button pass. It
## used to demand `cast` and `melee` as buttons. Neither is one any more:
##   * `cast` (the primary) moved onto the AIM STICK — pushing it past
##     AIM_FIRE_THRESHOLD holds the action, which `_test_aim_stick_fires` pins. The
##     verb is still reachable with one thumb; it just is not a button.
##   * `melee` lost its touch affordance outright. For the melee classes the primary
##     IS the swing (Hero._cast dispatches per class), so nobody is left unable to
##     hit anything — see the consolidation note in TouchControls' header.
## What replaced them is the thing the spec actually asked for: one button per kit
## slot, so the required list now names all three by number.
func _test_buttons_drive_real_actions() -> void:
	var pad := _pad()
	var seen: Array[String] = []
	for c: Node in pad.get_children():
		if not (c is Button):
			continue
		var action: String = String(c.get_meta("action", ""))
		if action == "":
			continue
		seen.append(action)
		_expect(InputMap.has_action(action),
			"touch button '%s' drives a real action '%s'" % [(c as Button).text, action])
	# The verbs a phone player cannot play without.
	for required: String in ["jump", "dash", "parry", "spell_1", "spell_2", "spell_3",
			"spell_4"]:
		_expect(seen.has(required), "touch pad exposes '%s'" % required)
	pad.queue_free()
	_completes("buttons_drive_real_actions")


## The move stick drives the SAME named actions the keyboard uses, with strength.
func _test_move_injection() -> void:
	var pad := _pad()
	pad._set_move("move_right", 0.8, true)
	_expect(Input.is_action_pressed("move_right"), "move_right pressed via joystick")
	_expect(Input.get_action_strength("move_right") > 0.5, "analog strength applied")
	pad._set_move("move_right", 0.0, false)
	_expect(not Input.is_action_pressed("move_right"), "move_right released on recenter")
	pad.queue_free()
	_clear_input()
	_completes("move_injection")


## The aim actions must be in the input map at all. Input.action_press on a missing
## action errors out and silently publishes nothing, which on a device would look
## exactly like "the aim stick does nothing".
func _test_aim_actions_exist() -> void:
	for a: String in TouchControls.AIM_ACTIONS:
		_expect(InputMap.has_action(a), "input map has '%s'" % a)
	for a: String in TouchControls.MOVE_ACTIONS:
		_expect(InputMap.has_action(a), "input map has '%s'" % a)
	_completes("aim_actions_exist")


## THE ORIGINAL BUG, on the movement side: the stick could not say "up". Beyond aim,
## Hero._start_dash reads get_vector(... "move_up" ...), so a touch dash could never
## travel up-left or up-right either.
func _test_move_stick_publishes_up() -> void:
	var pad := _pad()
	pad.publish_move(Vector2(0.0, -1.0))
	_expect(Input.is_action_pressed("move_up"), "pushing the move stick UP presses move_up")
	_expect(Input.get_action_strength("move_up") > 0.9, "full push -> full up strength")
	_expect(not Input.is_action_pressed("move_down"), "up does not also press down")
	pad.publish_move(Vector2.ZERO)
	_expect(not Input.is_action_pressed("move_up"), "move_up released on recenter")
	pad.queue_free()
	_clear_input()
	_completes("move_stick_publishes_up")


## Aim and movement must be genuinely independent thumbs. The old scheme read aim off
## the MOVE stick, which meant pushing down both ducked you and pointed the shot at
## the floor — one gesture, two contradictory meanings.
func _test_move_and_aim_are_decoupled() -> void:
	var pad := _pad()
	pad.publish_move(Vector2(1.0, 1.0))  # run right, duck
	_expect(_read_aim() == Vector2.ZERO, "the move stick publishes NO aim")
	pad.publish_move(Vector2.ZERO)
	pad.publish_aim(Vector2(0.0, -1.0))  # aim straight up
	_expect(not Input.is_action_pressed("move_up"), "the aim stick publishes NO movement")
	_expect(not Input.is_action_pressed("move_down"), "the aim stick does not duck you")
	pad.publish_aim(Vector2.ZERO)
	pad.queue_free()
	_clear_input()
	_completes("move_and_aim_are_decoupled")


## Straight up, called out on its own because it is the literal thing a touch player
## could not do before: no upward component existed anywhere in the input layer.
func _test_aim_straight_up() -> void:
	var pad := _pad()
	pad.publish_aim(Vector2(0.0, -1.0))
	var r: Vector2 = _read_aim()
	_expect(r.length() > HERO_AIM_DEADZONE, "straight-up aim clears the deadzone")
	_expect(r.normalized().is_equal_approx(Vector2(0.0, -1.0)),
		"straight up reads back as straight up (got %s)" % r)
	pad.publish_aim(Vector2.ZERO)
	pad.queue_free()
	_clear_input()
	_completes("aim_straight_up")


## Sweep the whole circle in 5-degree steps: every direction must survive the trip
## through the named actions with its angle intact. A per-axis deadzone anywhere in
## the chain would show up here as a sector near an axis snapping flat — which is
## precisely why TouchControls publishes raw components and the aim_* actions carry
## deadzone 0.0 in project.godot.
func _test_aim_full_360_no_dead_sector() -> void:
	var pad := _pad()
	var worst: float = 0.0
	var worst_deg: float = 0.0
	for i: int in range(72):
		var deg: float = float(i) * 5.0
		var want: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(deg))
		pad.publish_aim(want)
		var got: Vector2 = _read_aim()
		if got.length() <= HERO_AIM_DEADZONE:
			_expect(false, "DEAD SECTOR at %.0f deg — a full push read as %s" % [deg, got])
			continue
		var err: float = absf(got.angle_to(want))
		if err > worst:
			worst = err
			worst_deg = deg
	# 1 degree of slop is generous; the maths is exact, so this is really a canary for
	# a deadzone or a clamp creeping back into the chain.
	_expect(worst < deg_to_rad(1.0),
		"360 sweep keeps its angle (worst %.3f deg at %.0f deg)" % [rad_to_deg(worst), worst_deg])
	pad.publish_aim(Vector2.ZERO)
	pad.queue_free()
	_clear_input()
	_completes("aim_full_360_no_dead_sector")


## Below the deadzone the aim must go QUIET, not go to zero-and-be-used: a lifted
## thumb has to leave Hero holding its last aim, or tapping an ability button would
## fling the shot in whatever direction the thumb happened to be sliding through.
## This checks the publisher's half (it releases cleanly, so the read vector falls
## under the deadzone); Hero's half — `if length > deadzone` guarding the ONLY write
## to _aim_dir, with no else that resets it — is asserted in the next test.
func _test_aim_deadzone_holds_last_aim() -> void:
	var pad := _pad()
	pad.publish_aim(Vector2(0.0, -1.0))
	var held: Vector2 = _read_aim()
	pad.publish_aim(Vector2(0.05, -0.05))  # thumb resting near centre
	var idle: Vector2 = _read_aim()
	_expect(idle.length() <= HERO_AIM_DEADZONE,
		"a near-centred thumb reads under the deadzone (%.3f)" % idle.length())
	pad.publish_aim(Vector2.ZERO)  # thumb lifted entirely
	_expect(_read_aim() == Vector2.ZERO, "lifting the thumb releases every aim action")
	_expect(held.length() > HERO_AIM_DEADZONE, "…and the aim it was holding was a real one")
	pad.queue_free()
	_clear_input()
	_completes("aim_deadzone_holds_last_aim")


## Twin-stick firing: pushing the aim stick past AIM_FIRE_THRESHOLD holds `cast`,
## while a gentle push only re-aims. That quiet ring between the two thresholds is
## the whole reason a player can re-point without spraying.
func _test_aim_stick_fires() -> void:
	var pad := _pad()
	if not TouchControls.AIM_STICK_FIRES:
		# The maker may have turned this off; then the CAST button is the only trigger
		# and there is nothing to assert here.
		pad.queue_free()
		_completes("aim_stick_fires")  # a deliberate skip still COMPLETED
		return
	var gentle: float = (HERO_AIM_DEADZONE + TouchControls.AIM_FIRE_THRESHOLD) * 0.5
	pad.publish_aim(Vector2.RIGHT * gentle)
	_expect(not Input.is_action_pressed("cast"), "a gentle push re-aims WITHOUT firing")
	_expect(_read_aim().length() > HERO_AIM_DEADZONE, "…and that gentle push still aims")
	pad.publish_aim(Vector2.RIGHT)
	_expect(Input.is_action_pressed("cast"), "a committed push fires")
	pad.publish_aim(Vector2.ZERO)
	_expect(not Input.is_action_pressed("cast"), "lifting the thumb stops firing")
	pad.queue_free()
	_clear_input()
	_completes("aim_stick_fires")


## Source-level guard on the consumer side. Hero cannot be instantiated in a --script
## run (no autoloads, no scene), so this reads the file: it must consume the aim_*
## actions, it must still gate the write to _aim_dir on the deadzone, and it must not
## have quietly gone back to reading aim off the MOVE stick.
func _test_hero_reads_the_aim_stick() -> void:
	var src: String = FileAccess.get_file_as_string(HERO_PATH)
	_expect(src != "", "read %s" % HERO_PATH)
	if src == "":
		return  # bail-out: the _expect above already failed
	for a: String in ["aim_right", "aim_left", "aim_up", "aim_down"]:
		_expect(src.contains("\"%s\"" % a), "Hero reads the '%s' action" % a)
	_expect(src.contains("TOUCH_AIM_DEADZONE"),
		"Hero still gates the aim write on the deadzone (hold-last-aim)")
	# The regression that started all this: aim resolved from the movement actions.
	_expect(not src.contains("Input.get_action_strength(\"move_down\")"),
		"Hero does NOT derive aim from the move stick any more")
	_completes("hero_reads_the_aim_stick")
