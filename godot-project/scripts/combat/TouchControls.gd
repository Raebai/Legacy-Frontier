class_name TouchControls
extends CanvasLayer
## Mobile-first TWIN-STICK touch layer (CLAUDE.md non-negotiable D-011: "every action
## must work via virtual joystick + tap"). Feeds the SAME named input actions the
## keyboard uses (move_*, aim_*, dash, cast, blast, blink, ultimate) so it composes
## with Hero with almost no combat-code changes.
##
## WHY TWO STICKS NOW. This layer used to publish only move_left / move_right /
## move_down — no upward component at all — and that was survivable only because Hero
## snapped the aim to the nearest enemy on touch. That auto-aim has been deleted (the
## locked rule is: you point, you throw, and landing it is your skill). The moment it
## went, a touch player could no longer aim at anything above them, because the input
## layer had no way to say "up". So aim gets its own stick, movement gets its missing
## up, and the two are fully decoupled — which also un-tangles the old mess where
## pushing the move stick DOWN both ducked you and aimed you at the floor.
##
## Layout (landscape, base viewport 640x360, canvas_items stretch):
##   LEFT THUMB  — DYNAMIC move stick (appears where you press in the left zone):
##                 full 360 analog move, push DOWN past a threshold = duck/ragdoll
##                 (move_down). JUMP and PARRY sit above it.
##   RIGHT THUMB — DYNAMIC aim stick (appears where you press in the right zone,
##                 anywhere that is not a button). Full 360 aim, and pushing past
##                 AIM_FIRE_THRESHOLD also holds `cast` — classic twin-stick. A dim
##                 home ring marks the natural resting spot. THREE SPELL BUTTONS sit
##                 on an arc swept around the bottom-right corner, with DASH in the
##                 corner itself; they consume their own taps, so a tap on a button
##                 never spawns a stick under it.
##   (Class / element / signature swapping is set in the hub, not mid-fight — ~14
##   keyboard actions won't fit two thumbs, so combat is consolidated to these.)
##
## THE CONSOLIDATION, and what it cost. This layer used to ship EIGHT corner-anchored
## buttons: JUMP / CAST / DASH / Q / G / BLINK / HIT / PARRY — a keyboard drawn on a
## phone. The spec is "left thumb: stick; right thumb: three spell buttons", so the
## right thumb now carries the three KIT SLOTS (`spell_1/2/3`) and nothing else but
## dash, and the primary attack moved onto the aim stick where it was already half
## living (AIM_STICK_FIRES). Four verbs lost their touch affordance in the trade:
##   * `melee` — the primary IS the melee swing for the melee classes
##     (Hero._cast dispatches per class), so a phone Brawler still punches.
##   * `blast` / `blink` / `nova` — the class ability trio. A phone player really is
##     short three verbs a desktop player has; that is a live design consequence and
##     not an oversight. `_button_layout()` below is one table — putting any of them
##     back is one row, which is why it is a table and not eight call sites.
##
## Every position/size below is computed from a handful of named constants (a thumb
## pivot, an arc radius, three angles) rather than typed in per button, so tuning the
## reach on a device moves the whole arc coherently instead of one button at a time.
##
## THE TWO-THUMB QUESTION. With the aim stick firing, the right thumb has two jobs:
## hold the stick to spray the primary, or lift onto a spell button. Lifting is safe
## because Hero HOLDS the last aim below its deadzone (Hero.TOUCH_AIM_DEADZONE) — the
## shot does not fling somewhere random while your thumb is off the stick. So the
## real loop is: steer left, aim+fire right, flick the right thumb onto 1/2/3 to spend
## a slot along the aim you were already holding. That is why the aim stick carries
## the primary and the spells stay as buttons, rather than the reverse.
##
## Shows only on a touchscreen (or force_visible for on-device-preview from desktop);
## desktop keyboard/mouse play is completely unaffected. On-device FEEL (button size,
## reach, stick radius, fire threshold) is the maker's tuning pass — the knobs are the
## consts below, and EVERY ONE of them is an untested guess: no touch device has ever
## run this.

## Force the pad visible on desktop to preview/verify (normally touchscreen-gated).
@export var force_visible: bool = false

# ------------------------------------------------------------------ TUNING KNOBS
# All UNTESTED GUESSES — nothing here has been felt on a real phone yet.

## --- left move stick ---
const JOY_RADIUS: float = 66.0        # max knob travel from the origin (px, base space)
const JOY_DEADZONE: float = 0.18      # ignore tiny wobble before we call it "moving"
const JOY_DUCK_THRESHOLD: float = 0.6 # push down past this -> duck (move_down)
## Push the MOVE stick up past this to also press `jump`. OFF by default: there is a
## dedicated JUMP button, and a stick that jumps when you meant to walk up-left is a
## classic mobile annoyance. One flip to try it.
const LEFT_STICK_UP_JUMPS: bool = false
const JOY_UP_JUMP_THRESHOLD: float = 0.7
const LEFT_ZONE_FRAC: float = 0.45    # left of this fraction of the screen = move zone

## --- right aim stick ---
## Deliberately a little smaller than the move stick: aiming is a fine gesture made
## with the thumb tip, walking is a coarse one made with the pad of the thumb.
const AIM_RADIUS: float = 52.0
## Push past this (0..1 of AIM_RADIUS) and the stick also holds `cast`. It is well
## ABOVE Hero.TOUCH_AIM_DEADZONE (0.20) on purpose, which buys a quiet ring between
## the two: a gentle push RE-AIMS without shooting, a committed push shoots. If the
## maker wants aim and fire fully separated, set AIM_STICK_FIRES = false and the CAST
## button becomes the only trigger.
const AIM_FIRE_THRESHOLD: float = 0.55
const AIM_STICK_FIRES: bool = true
## Right of this fraction of the screen = aim zone. The gap between LEFT_ZONE_FRAC and
## this is a deliberate dead band down the middle: a stray tap in the centre of the
## screen must not yank the aim off target mid-fight.
const RIGHT_ZONE_FRAC: float = 0.55
## Where the dim "put your thumb here" ring sits, as (from the right edge, up from the
## bottom) in base-viewport px. Sits just INBOARD of the spell arc so the resting thumb
## is a short flick from every button. The stick itself is floating, so this ring is
## guidance, not a hitbox.
const AIM_HOME_OFFSET: Vector2 = Vector2(268.0, 88.0)

## --- the right thumb's arc ---
## Everything below is an UNTESTED GUESS: no touch device has ever run this layout.
## They are named and derived rather than hand-placed so a device pass moves the whole
## arc at once — change the radius and all three buttons stay a thumb-sweep apart.
##
## Where the right thumb PIVOTS, as (from the right edge, up from the bottom) in the
## 640x360 base space. Roughly the knuckle of a thumb on a phone held in landscape.
const THUMB_PIVOT: Vector2 = Vector2(30.0, 26.0)
## How far the thumb TIP sits from that pivot. The three spell buttons live on this arc.
const SPELL_ARC_RADIUS: float = 126.0
## Where on the arc, in degrees measured from "straight inboard" (toward the screen
## centre) round to "straight up". Spell 1 — the one you throw most — is the flattest
## and therefore the shortest reach.
##
## ⚠ THESE ARE NOT FREE. Buttons are drawn as circles but TAPPED as rectangles, so two
## neighbours whose circles clear each other can still have overlapping hit boxes.
## `SPELL_ARC_ANGLES` + `SPELL_ARC_RADIUS` + `SPELL_BTN_SIZE` are checked against each
## other in tools/slice_test_spell_buttons.gd; retune them there, not by eye.
const SPELL_ARC_ANGLES: Array[float] = [10.0, 50.0, 90.0]
const SPELL_BTN_SIZE: float = 60.0
## DASH lives in the corner itself — under the thumb at rest, because it is the panic
## button and the one press that must never need a reach.
const DASH_BTN_OFFSET: Vector2 = Vector2(16.0, 14.0)
const DASH_BTN_SIZE: float = 56.0
## Left thumb, stacked above the move-stick zone.
const JUMP_BTN_OFFSET: Vector2 = Vector2(14.0, 62.0)
const JUMP_BTN_SIZE: float = 54.0
## PARRY on the LEFT, which looks wrong and is not: a held guard ROOTS you (Hero zeroes
## move_x while ParryRing.blocks_attack), so it costs the left thumb nothing it was
## using — and it leaves the right thumb free to keep aiming through a block.
const PARRY_BTN_OFFSET: Vector2 = Vector2(14.0, 126.0)
const PARRY_BTN_SIZE: float = 52.0

## --- shared ---
const PAD_ALPHA: float = 0.34         # translucent so it doesn't hide the fight
## Cooldown veil over a spell button, drawn as a bottom-anchored wipe that shrinks as
## the slot recovers — the same read as the hotbar's, so the two never disagree.
const CD_VEIL_COLOR: Color = Color(0.02, 0.03, 0.06, 0.66)
## The ready-flash: a slot that just came back flares its rim. A ready button should
## invite the press, not merely stop refusing it.
const READY_FLASH_COLOR: Color = Color(0.65, 0.95, 1.0)
## Resting rim of a spell button that is ready to throw, vs one that is not.
const RIM_READY: Color = Color(0.72, 0.92, 1.0, 0.85)
const RIM_COOLING: Color = Color(0.5, 0.53, 0.62, 0.5)

## Actions each stick owns. Kept as lists so a stick can release exactly its own
## actions on lift-off without stomping the other thumb's state.
const MOVE_ACTIONS: Array[String] = ["move_left", "move_right", "move_up", "move_down"]
const AIM_ACTIONS: Array[String] = ["aim_left", "aim_right", "aim_up", "aim_down"]

var _move_stick: Stick = null
var _aim_stick: Stick = null
var _aim_home: Control = null
## Every button and its cooldown/ready overlay, in build order...
var _buttons: Array[Button] = []
var _veils: Array[SpellVeil] = []
## ...and just the three spell ones, in kit-slot order.
var _spell_buttons: Array[Button] = []
var _spell_veils: Array[SpellVeil] = []
## Which stick the desktop-preview mouse is currently driving (null = none).
var _mouse_stick: Stick = null
## Every action this layer is currently holding down, so each press/release is
## edge-guarded and just_pressed/just_released stay clean for everyone else.
var _held_actions: Dictionary = {}


## Group joined by a LIVE pad, so the desktop hotbar can stand down without either of
## them importing the other. A pad that hid itself never joins, which is what makes
## "is the pad live" a different question from "does this device have a touchscreen"
## — a touchscreen laptop being played with a keyboard must keep its hotbar.
const PAD_GROUP: StringName = &"touch_pad"


func _ready() -> void:
	layer = 70  # above the AbilityBar (60), below Conversation (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not (force_visible or DisplayServer.is_touchscreen_available()):
		visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return
	add_to_group(PAD_GROUP)
	_build_sticks()
	_build_buttons()
	_adopt_heroes()


## Tell heroes the on-screen pad is live so they read the aim STICK instead of the
## mouse. On a real device Hero._touch_aim() is already true from DisplayServer, so
## this only really matters for force_visible desktop previews — which is also the
## only case where a hero can spawn after us, hence the re-adopt in _process.
func _adopt_heroes() -> void:
	for h: Node in get_tree().get_nodes_in_group("hero"):
		h.set("touch_input", true)


# ------------------------------------------------------------------------ sticks
func _build_sticks() -> void:
	_move_stick = _make_stick(JOY_RADIUS, Color(0.85, 0.9, 1.0, PAD_ALPHA * 0.7))
	# Warm tint so the two sticks are never confused at a glance mid-fight.
	_aim_stick = _make_stick(AIM_RADIUS, Color(1.0, 0.86, 0.68, PAD_ALPHA * 0.7))
	# Dim always-on ring showing where the aim thumb wants to live. Anchored to the
	# bottom-right corner so it scales with the window like everything else here.
	_aim_home = _circle(AIM_RADIUS * 1.5, Color(1.0, 0.86, 0.68, PAD_ALPHA * 0.35))
	_aim_home.anchor_left = 1.0
	_aim_home.anchor_right = 1.0
	_aim_home.anchor_top = 1.0
	_aim_home.anchor_bottom = 1.0
	var half: float = AIM_RADIUS * 0.75
	_aim_home.offset_left = -AIM_HOME_OFFSET.x - half
	_aim_home.offset_right = -AIM_HOME_OFFSET.x + half
	_aim_home.offset_top = -AIM_HOME_OFFSET.y - half
	_aim_home.offset_bottom = -AIM_HOME_OFFSET.y + half
	add_child(_aim_home)


func _make_stick(radius: float, tint: Color) -> Stick:
	var s := Stick.new()
	s.radius = radius
	s.base = _circle(radius * 2.0, tint)
	s.base.visible = false
	add_child(s.base)
	s.knob = _circle(radius * 0.9, Color(tint.r + 0.1, tint.g + 0.07, tint.b + 0.05, PAD_ALPHA + 0.15))
	s.knob.visible = false
	add_child(s.knob)
	return s


## Both sticks are read live from raw touches, not from Controls: buttons consume
## their own taps in _gui_input first, so a tap on CAST never reaches here and never
## spawns a stick underneath it. Fingers are tracked by index so the two thumbs are
## genuinely independent (the whole point of twin-stick).
func _unhandled_input(event: InputEvent) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_try_start(t.index, t.position, vp)
		else:
			if _move_stick.index == t.index:
				_stop_move()
			if _aim_stick.index == t.index:
				_stop_aim()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _move_stick.active and _move_stick.index == d.index:
			_move_stick.cur = d.position
		elif _aim_stick.active and _aim_stick.index == d.index:
			_aim_stick.cur = d.position
	# Desktop preview: drive whichever stick the click landed in with the mouse. One
	# mouse can only hold one stick at a time, which is exactly why the preview can
	# never fully stand in for a device playtest.
	elif event is InputEventMouseButton and force_visible:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_stick = _try_start(-1, mb.position, vp)
			elif _mouse_stick != null:
				if _mouse_stick == _move_stick:
					_stop_move()
				else:
					_stop_aim()
				_mouse_stick = null
	elif event is InputEventMouseMotion and _mouse_stick != null:
		_mouse_stick.cur = (event as InputEventMouseMotion).position


## Route a fresh press to the stick whose zone it landed in. Returns the stick that
## took it, or null (centre dead band, or that thumb is already down).
func _try_start(index: int, pos: Vector2, vp: Vector2) -> Stick:
	if pos.x < vp.x * LEFT_ZONE_FRAC:
		if not _move_stick.active:
			_move_stick.start(index, pos)
			return _move_stick
	elif pos.x > vp.x * RIGHT_ZONE_FRAC:
		if not _aim_stick.active:
			_aim_stick.start(index, pos)
			return _aim_stick
	return null


func _stop_move() -> void:
	_move_stick.stop()
	_release(MOVE_ACTIONS)


func _stop_aim() -> void:
	_aim_stick.stop()
	_release(AIM_ACTIONS)
	# Lifting the aim thumb must stop the gun, but must NOT reset the aim: Hero holds
	# the last direction below its deadzone precisely so this lift is free.
	_release(["cast"])


func _process(_delta: float) -> void:
	# Desktop preview only: a hero spawned after us still needs adopting. On a device
	# DisplayServer already answers this, so this costs nothing where it matters.
	if force_visible:
		_adopt_heroes()
	_sync_buttons()
	if _move_stick.active:
		_move_stick.sync_knob()
		publish_move(_move_stick.vector())
	if _aim_stick.active:
		_aim_stick.sync_knob()
		publish_aim(_aim_stick.vector())


## Publish a move-stick vector (components in -1..1) onto the named move actions.
## Split out from _process so the input MATHS — the only part of a touch layer that
## can be judged without a device — is directly testable headlessly.
func publish_move(v: Vector2) -> void:
	_set_move("move_right", v.x, v.x > JOY_DEADZONE)
	_set_move("move_left", -v.x, v.x < -JOY_DEADZONE)
	# UP was simply missing before, which quietly broke more than aim: Hero._start_dash
	# reads get_vector(... "move_up" ...), so a touch dash could never go up-left or
	# up-right either. Publishing it fixes the dash and any future up-consumer for free.
	_set_move("move_up", -v.y, v.y < -JOY_DEADZONE)
	# Push down -> duck (hold move_down, the ragdoll flop). Deliberately a much higher
	# threshold than walking: you should have to MEAN it, since ducking suspends
	# abilities. No longer doubles as "aim at the floor" — that is the aim stick's job.
	_set_move("move_down", 1.0, v.y > JOY_DUCK_THRESHOLD)
	if LEFT_STICK_UP_JUMPS:
		_set_move("jump", 1.0, v.y < -JOY_UP_JUMP_THRESHOLD)


## Publish an aim-stick vector (components in -1..1) onto the named aim actions, and
## hold `cast` once it is pushed far enough to count as firing.
##
## NOTE there is no deadzone here on purpose. A per-AXIS deadzone would carve dead
## sectors: aiming 5 degrees above horizontal would zero the tiny vertical component
## and snap the shot flat — the exact "can't aim where I'm pointing" bug this task
## exists to kill. Both components go out at full analog value and the single
## magnitude deadzone lives in ONE place, Hero.TOUCH_AIM_DEADZONE, which is also what
## implements hold-the-last-aim when the thumb is lifted. One owner, no drift.
func publish_aim(v: Vector2) -> void:
	_set_move("aim_right", v.x, v.x > 0.0)
	_set_move("aim_left", -v.x, v.x < 0.0)
	_set_move("aim_up", -v.y, v.y < 0.0)
	_set_move("aim_down", v.y, v.y > 0.0)
	if AIM_STICK_FIRES:
		_set_move("cast", 1.0, v.length() >= AIM_FIRE_THRESHOLD)


## Press/release an action with analog strength, edge-guarded so we only touch the
## input on each transition (keeps just_pressed/released clean for other systems).
## Re-pressing while already held is harmless and self-healing: if the CAST button and
## the firing aim stick disagree for a frame, the next frame settles it.
func _set_move(action: String, strength: float, on: bool) -> void:
	if on:
		Input.action_press(action, clampf(absf(strength), 0.0, 1.0))
		_held_actions[action] = true
	elif _held_actions.get(action, false):
		Input.action_release(action)
		_held_actions[action] = false


## Release just these actions — per-stick, so lifting the move thumb cannot silently
## drop the aim thumb's state (they are independent fingers).
func _release(actions: Array) -> void:
	for a: String in actions:
		if _held_actions.get(a, false):
			Input.action_release(a)
			_held_actions[a] = false


# ---------------------------------------------------------------- the buttons
## THE WHOLE LAYOUT, as data. One row per button so adding, removing or moving one is
## a single edit — the previous version spread eight hand-placed call sites across the
## file and there was no way to see the layout without simulating it in your head.
##
## Positions are in the project's 640x360 base space (canvas_items stretch) and
## CORNER-ANCHORED, so they stick to the thumbs at any resolution. `off` = (distance
## from that side, distance UP from the bottom).
func _button_layout() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		# JUMP presses "jump", NOT "move_up": Hero polls the "jump" action, so pressing
		# move_up made the touch jump button silently do nothing at all on a device.
		{"label": "JUMP", "action": "jump", "corner": "bl",
			"off": JUMP_BTN_OFFSET, "size": JUMP_BTN_SIZE},
		{"label": "PARRY", "action": "parry", "corner": "bl",
			"off": PARRY_BTN_OFFSET, "size": PARRY_BTN_SIZE},
		{"label": "DASH", "action": "dash", "corner": "br",
			"off": DASH_BTN_OFFSET, "size": DASH_BTN_SIZE},
	]
	for i: int in SPELL_ARC_ANGLES.size():
		rows.append({
			"label": str(i + 1), "action": "spell_%d" % (i + 1), "corner": "br",
			"off": spell_button_offset(i), "size": SPELL_BTN_SIZE, "spell_slot": i,
		})
	return rows


## Where spell button `i` sits, as (from the right edge, up from the bottom). Static +
## public so the geometry test can check the arc for overlapping hit boxes without
## building a pad — the maths IS the layout, and it is the only part of a touch layer
## that can be judged without a device.
static func spell_button_offset(i: int) -> Vector2:
	var a: float = deg_to_rad(SPELL_ARC_ANGLES[clampi(i, 0, SPELL_ARC_ANGLES.size() - 1)])
	return THUMB_PIVOT + Vector2(cos(a), sin(a)) * SPELL_ARC_RADIUS


func _build_buttons() -> void:
	for row: Dictionary in _button_layout():
		_add_button(row)


func _add_button(row: Dictionary) -> void:
	var label: String = String(row["label"])
	var action: String = String(row["action"])
	var size: float = float(row["size"])
	var off: Vector2 = row["off"]
	var b := Button.new()
	b.text = label
	# The action this button drives, readable from outside so a test can assert the
	# wiring rather than just counting buttons.
	b.set_meta("action", action)
	if row.has("spell_slot"):
		b.set_meta("spell_slot", int(row["spell_slot"]))
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16 if row.has("spell_slot") else 12)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	b.add_theme_constant_override("outline_size", 3)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		# PRESS STATE. The press has to be visible on a screen your own thumb is
		# covering, so it brightens AND lifts its rim rather than only changing alpha.
		var down: bool = state == "pressed"
		sb.bg_color = Color(0.2, 0.24, 0.34, PAD_ALPHA + (0.3 if down else 0.0))
		sb.set_corner_radius_all(int(size * 0.5))
		sb.border_color = Color(0.9, 0.96, 1.0, 0.85) if down else Color(0.8, 0.88, 1.0, 0.5)
		sb.set_border_width_all(3 if down else 2)
		b.add_theme_stylebox_override(state, sb)
	# Anchor to the chosen bottom corner + place by pixel offset (resolution-safe).
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	if String(row["corner"]) == "br":
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_left = -off.x - size
		b.offset_right = -off.x
	else:  # bottom-left
		b.offset_left = off.x
		b.offset_right = off.x + size
	b.offset_top = -off.y - size
	b.offset_bottom = -off.y
	# Hold-to-repeat where the verb repeats (a held spell button re-fires the moment
	# its slot recovers — Hero._update_input_buffer), a tap for the one-shots. Both are
	# the same press/release pair; the difference lives in the consumer, not here.
	b.button_down.connect(func() -> void: Input.action_press(action))
	b.button_up.connect(func() -> void: Input.action_release(action))
	add_child(b)
	# EVERY button gets a veil, not just the spell ones. DASH and PARRY are cooldown
	# verbs too, and on a phone this pad is the ONLY cooldown readout there is — the
	# desktop hotbar stands down when the pad is live (see `AbilityBar`), because nine
	# slots across the bottom of the screen sat directly under the thumb cluster and
	# most of them named verbs a thumb cannot reach.
	var veil := SpellVeil.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(veil)
	_buttons.append(b)
	_veils.append(veil)
	if row.has("spell_slot"):
		_spell_buttons.append(b)
		_spell_veils.append(veil)


## Repaint every button from the hero's own state: the cooldown wipe, the ready rim
## and the just-came-back flash. Polled rather than pushed, the `AbilityBar` idiom —
## the numbers tick every frame anyway, and a HUD that subscribes to six signals is a
## HUD that can miss one.
##
## `Hero.spell_button_state` / `Hero.touch_button_state` are the single publishers, so
## this pad, the hotbar and the loadout bar cannot disagree about whether a button is
## ready — and neither of them depends on a slot's POSITION in some other array.
func _sync_buttons() -> void:
	if _buttons.is_empty():
		return
	var hero: Node = get_tree().get_first_node_in_group("hero")
	var live: bool = hero != null and hero.has_method("spell_button_state")
	for i: int in _buttons.size():
		var btn: Button = _buttons[i]
		var veil: SpellVeil = _veils[i]
		if not live:
			# No hero this scene (a hub, a menu): draw the buttons plain rather than
			# faking a ready state nobody can act on.
			veil.frac = 0.0
			veil.flash = 0.0
			veil.slot_ready = true
			veil.queue_redraw()
			continue
		var st: Dictionary
		if btn.has_meta("spell_slot"):
			st = hero.call("spell_button_state", int(btn.get_meta("spell_slot")))
			# The number stays the button's label (a thumb finds a shape, not a word),
			# but the SPELL's name rides the tooltip so a desktop preview can read it.
			btn.tooltip_text = String(st.get("name", ""))
			btn.disabled = not bool(st.get("filled", true))
		else:
			st = hero.call("touch_button_state", StringName(String(btn.get_meta("action", ""))))
		var total: float = float(st.get("total", 0.0))
		veil.frac = 0.0 if total <= 0.0 else clampf(float(st.get("remaining", 0.0)) / total, 0.0, 1.0)
		veil.flash = float(st.get("pulse", 0.0))
		veil.slot_ready = bool(st.get("ready", true))
		veil.queue_redraw()


## The cooldown wipe + ready flare drawn over one spell button. An inner Control
## because a Button cannot draw over its own StyleBox, and a shader would be a whole
## dependency for two rectangles.
class SpellVeil extends Control:
	var frac: float = 0.0    # 1 = just cast, 0 = fully recovered
	var flash: float = 0.0   # 1 -> 0 across the ready-flash
	var slot_ready: bool = true

	func _draw() -> void:
		var r: float = size.x * 0.5
		var c: Vector2 = size * 0.5
		if frac > 0.0:
			# Bottom-anchored wipe that shrinks as the slot fills back up — the same
			# direction the hotbar sweeps, so the two read as one system.
			var h: float = size.y * frac
			draw_rect(Rect2(Vector2(0.0, size.y - h), Vector2(size.x, h)),
				TouchControls.CD_VEIL_COLOR)
		draw_arc(c, r - 2.0, 0.0, TAU, 28,
			TouchControls.RIM_READY if slot_ready else TouchControls.RIM_COOLING, 2.0, true)
		if flash > 0.0:
			# A rim that flares OUTWARD and fades: motion, which the eye catches in
			# peripheral vision while it is busy watching the fight.
			var grow: float = (1.0 - flash) * 7.0
			var f: Color = TouchControls.READY_FLASH_COLOR
			draw_arc(c, r + grow, 0.0, TAU, 28, Color(f.r, f.g, f.b, flash), 2.5, true)


## A round translucent Control (a stick base/knob, or the aim home ring), drawn via a
## circular stylebox.
func _circle(diameter: float, color: Color) -> Control:
	var c := Panel.new()
	c.custom_minimum_size = Vector2(diameter, diameter)
	c.size = Vector2(diameter, diameter)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter * 0.5))
	sb.border_color = Color(color.r, color.g, color.b, minf(color.a + 0.2, 1.0))
	sb.set_border_width_all(2)
	c.add_theme_stylebox_override("panel", sb)
	return c


## One floating thumb stick: where it was pressed, where the finger is now, and the
## two Controls that draw it. Both sticks are the same object so the aim stick cannot
## quietly drift out of sync with the move stick's behaviour.
class Stick extends RefCounted:
	var active: bool = false
	var index: int = -99          # touch finger index (-1 = desktop mouse preview)
	var origin: Vector2 = Vector2.ZERO
	var cur: Vector2 = Vector2.ZERO
	var radius: float = 66.0
	var base: Control = null
	var knob: Control = null

	## Floating/relative, NOT fixed: the stick materialises under wherever the thumb
	## lands in its zone. On a phone you cannot see your own thumb, and a fixed stick
	## means constantly re-finding it by feel; a floating one is always exactly where
	## you put your thumb. Cost is that the on-screen art moves around, which is why
	## the aim side also gets a static home ring as a visual anchor.
	func start(idx: int, pos: Vector2) -> void:
		active = true
		index = idx
		origin = pos
		cur = pos
		base.position = pos - base.size * 0.5
		base.visible = true
		knob.visible = true

	func stop() -> void:
		active = false
		index = -99
		base.visible = false
		knob.visible = false

	## Finger offset from the origin, clamped to the ring and normalised to -1..1.
	## Full 360 by construction — nothing here quantises to an axis or a sector.
	func vector() -> Vector2:
		if not active:
			return Vector2.ZERO
		var v: Vector2 = cur - origin
		if v.length() > radius:
			v = v.normalized() * radius
		return v / radius

	func sync_knob() -> void:
		knob.position = origin + vector() * radius - knob.size * 0.5
