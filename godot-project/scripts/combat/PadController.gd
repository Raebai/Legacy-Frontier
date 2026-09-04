class_name PadController
extends RefCounted
## ONE GAMEPAD, DRIVING ONE HERO. The second implementer of `Hero.controller`.
##
## `BotController` proved the seam works by letting a brain drive a body; this does the
## same job for a HUMAN holding a specific pad. SEVEN duck-typed methods, exactly the
## ones a Hero calls on its driver — the six input reads behind
## `_pressed/_just/_released/_axis/_vector/_aim_point`, plus `tick` — so a Hero cannot
## tell a pad from a brain from a keyboard.
##
## ⚠ THIS DOCSTRING SAID "SIX" AND THE CLASS IMPLEMENTED SIX, AND THAT COST PLAYER TWO
## EVERY VERB THEY HAD. `Hero._physics_process` also calls `controller.tick(...)`; a
## missing method raises, a raise ABORTS the enclosing function, and player two's body
## therefore never reached its own movement code. Booting the arena found it in one
## frame; nothing that tested this class on its own could. See `tick` below.
##
## ⚠ THE PAD IS DELIBERATELY *NOT* BOUND IN THE ACTION MAP, and that is the whole design.
## `Input.is_action_pressed(action)` is aggregated across EVERY device: bind a stick to
## `move_left` and player 2's stick also walks player 1, because player 1 reads global
## `Input` through the `controller == null` path. Adding pad events to `[input]` would
## therefore break single player the moment a second pad was plugged in. Reading raw
## per-device state here instead means:
##   * solo play is byte-identical — not one line of the null-controller path changes,
##   * `project.godot` needs no new bindings at all,
##   * "both players on pads" is just two of these with different `device` ids.
##
## ⚠ EDGES ARE SNAPSHOTTED PER PHYSICS FRAME. Raw joypad reads have no notion of "just
## pressed" — that state has to be derived by comparing this frame against the last one.
## The snapshot is keyed on `Engine.get_physics_frames()` and taken lazily on the first
## query of a frame, so there is no tick() to forget to call and no ordering dependency
## on whoever owns this object. Physics is the right domain because every gameplay verb
## the Hero consumes (`dash`, `cast`, `jump`, the buffered actions) is read from
## `_physics_process`.
##
## ⚠ KNOWN GAP, WRITTEN DOWN RATHER THAN HIDDEN. `Hero._process` runs an EARLY input
## latch for buffered actions on the human path only (`controller != null` returns at
## `Hero.gd:2550`), which catches a press landing between two physics ticks. A pad player
## does not get that sub-tick latch, so their buffer window starts at the next physics
## frame — up to one tick (~16 ms) later than a keyboard player's. The physics-path
## buffering at `Hero.gd:2478/2501` still runs normally through this seam, so nothing is
## dropped; it is a few milliseconds of forgiveness, not a lost input. Revisit only if a
## playtest actually reports pad inputs feeling stickier than keyboard.

## Sticks. Below this the axis reads as centred — a resting stick must not walk anybody.
const STICK_DEADZONE: float = 0.22
## Analogue triggers are 0..1; half-pull is the press.
const TRIGGER_THRESHOLD: float = 0.5
## How far in front of the hero `aim_point` projects the stick direction. Placed spells
## need real ground coordinates, so this has to be a world POINT, not a direction — see
## the note on `Hero._aim_point`.
const AIM_REACH: float = 240.0

## THE LAYOUT. Xbox naming; a DualShock reports the same indices through Godot.
##
## Movement is the LEFT STICK ONLY, which frees the whole d-pad for the spell slots —
## the alternative was cramming four spells onto face buttons that already carry jump,
## dash, melee and the ult. `cast` sits on the right trigger because it is the one verb
## that is HELD (`Hero.gd:2259` polls `_pressed`, not `_just`), and a trigger is the only
## control on a pad built to be held.
const BUTTONS: Dictionary = {
	&"jump": JOY_BUTTON_A,
	&"dash": JOY_BUTTON_B,
	&"melee": JOY_BUTTON_X,
	&"ultimate": JOY_BUTTON_Y,
	&"blast": JOY_BUTTON_LEFT_SHOULDER,
	&"blink": JOY_BUTTON_RIGHT_SHOULDER,
	&"nova": JOY_BUTTON_DPAD_UP,
	&"spell_1": JOY_BUTTON_DPAD_LEFT,
	&"spell_2": JOY_BUTTON_DPAD_DOWN,
	&"spell_3": JOY_BUTTON_DPAD_RIGHT,
	&"spell_4": JOY_BUTTON_RIGHT_STICK,
	# ⚠ `class_menu`, NOT `switch_class`, AND THE NAME IS THE MECHANISM. `Hero` reads
	# `_just(&"switch_class")` and CYCLES to the next class — nine presses to reach the
	# ninth, rebuilding the rig and the whole spell config on every one, with nothing
	# on screen saying what you are about to become. That was the standing workaround
	# for player two having no class pick, and it is the thing being replaced.
	#
	# `class_menu` is read by `LocalCoop` and by NOTHING else in the game: it is not in
	# the InputMap, no Hero polls it, and `BotIntent`'s forbidden list is unaffected.
	# So a pad can no longer trip the cycle by accident, and the keyboard's own
	# `switch_class` binding in `project.godot` is untouched — solo is byte-identical.
	&"class_menu": JOY_BUTTON_BACK,
	# REVIVE (`Revive.REVIVE_ACTION` is &"talk"). On the stick click because it is a
	# HOLD taken while standing still over a downed ally, and every button a thumb
	# reaches mid-fight was already spoken for. First-pass binding: if it fights the
	# hand in a playtest, this line is the whole change.
	&"talk": JOY_BUTTON_LEFT_STICK,
}

## Analogue triggers, read as buttons past `TRIGGER_THRESHOLD`.
const TRIGGERS: Dictionary = {
	&"cast": JOY_AXIS_TRIGGER_RIGHT,
	&"parry": JOY_AXIS_TRIGGER_LEFT,
}

## Directional actions, as (axis, sign). `move_down` is also the duck (`Hero.gd:2198`),
## which is why down is a real action and not just a negative `move_up`.
const AXES: Dictionary = {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	&"aim_left": [JOY_AXIS_RIGHT_X, -1.0],
	&"aim_right": [JOY_AXIS_RIGHT_X, 1.0],
	&"aim_up": [JOY_AXIS_RIGHT_Y, -1.0],
	&"aim_down": [JOY_AXIS_RIGHT_Y, 1.0],
}

var device: int = 0

## ⚠ THE HERO'S HANDS ARE TIED WHILE A MENU IS UP. Player two's class chooser is driven
## by the same stick and the same A button that jump and dash sit on, so without this
## they would sprint and dash their way across the floor while reading their own class
## grid.
##
## ⚠ IT GATES THE HERO CONTRACT, NOT THE SNAPSHOT, AND THE DIFFERENCE IS LOAD-BEARING.
## The obvious shape — zero `strength()` — zeroes `_refresh`'s snapshot too, and then
## THE MENU CANNOT READ THE PAD EITHER, because there is only one pad in the player's
## hands however many objects are pointed at it. It also manufactures a phantom press
## on the way out: A held down to confirm the menu reads as `just_pressed` on the frame
## the hero gets the pad back, and player two leaps into the air on leaving their own
## chooser.
##
## So the snapshot is always RAW and the six methods the HERO calls answer neutral while
## suspended; `menu_pressed` / `menu_just_pressed` read straight through it. A held
## button therefore has `_prev == _now == true` across the whole suspend, and produces
## no edge in either direction when it ends.
var suspended: bool = false

var _now: Dictionary = {}          ## action -> bool, this physics frame
var _prev: Dictionary = {}         ## action -> bool, the frame before
var _frame: int = -1
var _last_aim: Vector2 = Vector2.RIGHT


func _init(pad_device: int = 0) -> void:
	device = pad_device


## A PERSON is holding this, which is what separates it from `BotController` for
## anything counting the party. `Encounter.party_size` asks; a bot controller does not
## answer, and so cannot inflate the floor it was brought along to help with.
func is_human() -> bool:
	return true


# ------------------------------------------------------- the Hero.controller contract

## ⚠ THE SEAM IS SEVEN METHODS, NOT SIX, AND THIS ONE WAS MISSING — WHICH MADE PLAYER
## TWO COMPLETELY INERT.
##
## `Hero._physics_process` calls `controller.tick(self, _bot_clock)` unconditionally on
## every frame a hero HAS a driver (`Hero.gd:2071`), because until now the only driver
## was `BotController` and that call is how a brain gets to think. A `PadController` had
## no `tick`, so the call raised `Invalid call. Nonexistent function 'tick'` — and a
## GDScript error ABORTS THE ENCLOSING FUNCTION. `_physics_process` therefore returned
## at that line every single frame, above the movement integration, above the cast
## dispatch, above `move_and_slide`. Player two stood still for ever while the console
## filled at 60 lines a second, and none of it was visible from any test that built a
## `PadController` without putting it on a real Hero.
##
## It does nothing, and doing nothing is the correct implementation: a human IS the
## brain. The signature mirrors `BotController.tick(body, now)`; the return is ignored
## by the call site (only `BotIntent` reads a brain's dictionary), so `void` is honest
## about there being no intent to hand back.
func tick(_body: Object, _now: float) -> void:
	pass


func pressed(action: StringName) -> bool:
	return false if suspended else menu_pressed(action)


func just_pressed(action: StringName) -> bool:
	return false if suspended else menu_just_pressed(action)


func just_released(action: StringName) -> bool:
	if suspended:
		return false
	_refresh()
	return bool(_prev.get(action, false)) and not bool(_now.get(action, false))


## Analogue, NOT the boolean press — a stick half over walks at half speed, the way the
## keyboard's -1/0/+1 never could.
func axis(neg: StringName, pos: StringName) -> float:
	return 0.0 if suspended else strength(pos) - strength(neg)


# ---- the same two reads, THROUGH a suspend ------------------------------------
# For whoever owns the pad while the hero does not: today that is player two's class
# chooser. Named rather than a `force` flag so a call site says which side of the
# suspend it is on.

func menu_pressed(action: StringName) -> bool:
	_refresh()
	return bool(_now.get(action, false))


func menu_just_pressed(action: StringName) -> bool:
	_refresh()
	return bool(_now.get(action, false)) and not bool(_prev.get(action, false))


func vector(nx: StringName, px: StringName, ny: StringName, py: StringName) -> Vector2:
	var v := Vector2(axis(nx, px), axis(ny, py))
	# Matches `Input.get_vector`: clamp the magnitude so a diagonal is not faster than a
	# cardinal, which on a square-gated stick it otherwise would be.
	return v if v.length_squared() <= 1.0 else v.normalized()


## A world point along the right stick. With the stick at rest this holds the last
## direction aimed rather than snapping to a default — the same rule the bot path uses,
## and the reason a pad player's aim does not flick back to centre between flicks.
func aim_point(from: Vector2) -> Vector2:
	# Reads raw rather than through `strength`, so the suspend has to be repeated here
	# — otherwise a menu-navigating stick would go on re-aiming the body behind it.
	# Suspended, `_last_aim` is HELD rather than zeroed, so the body is still facing
	# where it was facing when the menu opened.
	var stick := Vector2.ZERO if suspended \
		else Vector2(_raw_axis(JOY_AXIS_RIGHT_X), _raw_axis(JOY_AXIS_RIGHT_Y))
	if stick.length() > STICK_DEADZONE:
		_last_aim = stick.normalized()
	return from + _last_aim * AIM_REACH


# ----------------------------------------------------------------------- raw reading

## 0..1 for any mapped action. Buttons are 0 or 1; sticks and triggers report how far.
## ⚠ RAW, AND DELIBERATELY BLIND TO `suspended` — see the note on that field. The
## snapshot is built from this, and a zeroed snapshot would blind the menu too.
func strength(action: StringName) -> float:
	if not _connected():
		return 0.0
	if AXES.has(action):
		var spec: Array = AXES[action]
		var v: float = _raw_axis(int(spec[0])) * float(spec[1])
		if v <= STICK_DEADZONE:
			return 0.0
		# Rescale past the deadzone so the usable travel still spans a full 0..1 —
		# without this the first fifth of every push is silently thrown away.
		return clampf((v - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
	if TRIGGERS.has(action):
		return clampf(_raw_axis(int(TRIGGERS[action])), 0.0, 1.0)
	if BUTTONS.has(action):
		return 1.0 if _button_raw(int(BUTTONS[action])) else 0.0
	return 0.0


# ---- the three device reads, isolated so a test can fake a pad -----------------
# Every hardware touch in this class goes through these. A suite subclasses and
# overrides them, which is the only way to exercise deadzones and press EDGES on a
# machine with no controller plugged in - and edges are derived state, so "it compiles"
# says nothing about whether they fire once or every frame.

func _connected() -> bool:
	return Input.get_connected_joypads().has(device)


func _button_raw(b: int) -> bool:
	return Input.is_joy_button_pressed(device, b)


func _raw_axis(a: int) -> float:
	return Input.get_joy_axis(device, a)


## Is a mapped action down right now, as a boolean?
func _is_down(action: StringName) -> bool:
	if TRIGGERS.has(action):
		return strength(action) >= TRIGGER_THRESHOLD
	return strength(action) > 0.0


## Roll the snapshot forward, at most once per physics frame. Lazy on purpose: no owner
## has to remember to tick this, and two Heroes sharing one pad would still agree.
func _refresh() -> void:
	var f: int = Engine.get_physics_frames()
	if f == _frame:
		return
	_frame = f
	_prev = _now
	var snap: Dictionary = {}
	for action: StringName in BUTTONS:
		snap[action] = _is_down(action)
	for action: StringName in TRIGGERS:
		snap[action] = _is_down(action)
	for action: StringName in AXES:
		snap[action] = _is_down(action)
	_now = snap


## Every action this pad can drive. The join flow uses it to check a pad is alive, and
## the suite uses it to assert the layout covers the Hero's whole vocabulary.
static func mapped_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for a: StringName in BUTTONS:
		out.append(a)
	for a: StringName in TRIGGERS:
		out.append(a)
	for a: StringName in AXES:
		out.append(a)
	return out
