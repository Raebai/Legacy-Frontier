class_name TouchControls
extends CanvasLayer
## Mobile-first two-thumb touch layer (CLAUDE.md non-negotiable: "every action must
## work via virtual joystick + tap"). Feeds the SAME named input actions the keyboard
## uses (move_*, dash, cast, blast, blink, ultimate) so it composes with Hero with
## zero combat-code changes.
##
## Layout (landscape):
##   LEFT THUMB  — a DYNAMIC virtual joystick (appears where you press in the left
##                 zone): horizontal = analog move, push DOWN = duck/ragdoll
##                 (move_down). A JUMP button sits above it.
##   RIGHT THUMB — an arc of ability buttons: CAST (primary, hold to repeat), DASH,
##                 Q (AoE), ULT (G signature), BLINK. No aim-stick needed: on touch
##                 the Hero auto-aims the nearest enemy (Hero._touch_aim), so a fight
##                 is: steer with the left thumb, tap abilities with the right.
##   (Class / element / signature swapping is set in the hub, not mid-fight — ~14
##   keyboard actions won't fit two thumbs, so combat is consolidated to these.)
##
## Shows only on a touchscreen (or force_visible for on-device-preview from desktop);
## desktop keyboard/mouse play is completely unaffected. On-device FEEL (button size,
## reach, joystick deadzone) is the maker's tuning pass — the knobs are consts here.

## Force the pad visible on desktop to preview/verify (normally touchscreen-gated).
@export var force_visible: bool = false

const JOY_RADIUS: float = 66.0        # max knob travel from the origin
const JOY_DEADZONE: float = 0.18      # ignore tiny wobble
const JOY_DUCK_THRESHOLD: float = 0.6 # push down past this -> duck (move_down)
const LEFT_ZONE_FRAC: float = 0.45    # left this fraction of the screen = move zone
const BTN_SIZE: float = 66.0
const PAD_ALPHA: float = 0.34         # translucent so it doesn't hide the fight

var _joy_active: bool = false
var _joy_index: int = -99             # touch finger index (-1 = mouse preview)
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_cur: Vector2 = Vector2.ZERO
var _joy_base: Control = null
var _joy_knob: Control = null
var _held_move: Dictionary = {"move_left": false, "move_right": false, "move_down": false}


func _ready() -> void:
	layer = 70  # above the AbilityBar (60), below Conversation (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not (force_visible or DisplayServer.is_touchscreen_available()):
		visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return
	_build_joystick()
	_build_buttons()
	# Tell the hero to auto-aim (no cursor on touch). Re-found each frame is overkill;
	# set now + on the group. Any hero present adopts touch aim.
	for h: Node in get_tree().get_nodes_in_group("hero"):
		h.set("touch_input", true)


# --------------------------------------------------------------- left joystick
func _build_joystick() -> void:
	_joy_base = _circle(JOY_RADIUS * 2.0, Color(0.85, 0.9, 1.0, PAD_ALPHA * 0.7))
	_joy_base.visible = false
	add_child(_joy_base)
	_joy_knob = _circle(JOY_RADIUS * 0.9, Color(0.95, 0.97, 1.0, PAD_ALPHA + 0.15))
	_joy_knob.visible = false
	add_child(_joy_knob)


## Dynamic joystick + a jump/duck read live from the touch not on a button (buttons
## consume their own taps in _gui_input first, so those never reach here).
func _unhandled_input(event: InputEvent) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if not _joy_active and t.position.x < vp.x * LEFT_ZONE_FRAC:
				_start_joy(t.index, t.position)
		elif t.index == _joy_index:
			_stop_joy()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _joy_active and d.index == _joy_index:
			_joy_cur = d.position
	# Desktop preview: drive the same joystick with the mouse.
	elif event is InputEventMouseButton and (force_visible):
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _joy_active and mb.position.x < vp.x * LEFT_ZONE_FRAC:
				_start_joy(-1, mb.position)
			elif not mb.pressed and _joy_index == -1:
				_stop_joy()
	elif event is InputEventMouseMotion and _joy_active and _joy_index == -1:
		_joy_cur = (event as InputEventMouseMotion).position


func _start_joy(index: int, pos: Vector2) -> void:
	_joy_active = true
	_joy_index = index
	_joy_origin = pos
	_joy_cur = pos
	_joy_base.position = pos - _joy_base.size * 0.5
	_joy_base.visible = true
	_joy_knob.visible = true


func _stop_joy() -> void:
	_joy_active = false
	_joy_index = -99
	_joy_base.visible = false
	_joy_knob.visible = false
	_release_all_move()


func _process(_delta: float) -> void:
	if not _joy_active:
		return
	var v: Vector2 = _joy_cur - _joy_origin
	if v.length() > JOY_RADIUS:
		v = v.normalized() * JOY_RADIUS
	_joy_knob.position = _joy_origin + v - _joy_knob.size * 0.5
	var nx: float = v.x / JOY_RADIUS
	var ny: float = v.y / JOY_RADIUS
	_set_move("move_right", nx, nx > JOY_DEADZONE)
	_set_move("move_left", -nx, nx < -JOY_DEADZONE)
	# Push down -> duck (hold move_down, the ragdoll flop). Up is the JUMP button.
	_set_move("move_down", 1.0, ny > JOY_DUCK_THRESHOLD)


## Press/release a move action with analog strength, edge-guarded so we only touch
## the input each transition (keeps just_pressed/released clean for other systems).
func _set_move(action: String, strength: float, on: bool) -> void:
	if on:
		Input.action_press(action, clampf(absf(strength), 0.0, 1.0))
		_held_move[action] = true
	elif _held_move.get(action, false):
		Input.action_release(action)
		_held_move[action] = false


func _release_all_move() -> void:
	for a: String in _held_move.keys():
		if _held_move[a]:
			Input.action_release(a)
			_held_move[a] = false


# ---------------------------------------------------------------- right buttons
## Sized/placed in the project's 640x360 base space (canvas_items stretch) and
## CORNER-ANCHORED so they stick to the thumbs at any resolution. off = (distance
## from the side, distance UP from the bottom). Sizes/positions are the on-device
## FEEL knobs the maker tunes.
func _build_buttons() -> void:
	# JUMP — left thumb, above the dynamic move-joystick zone. Presses "jump", NOT
	# "move_up": Hero polls the "jump" action, so pressing move_up made the touch
	# jump button silently do nothing at all on a device.
	_add_button("JUMP", "jump", "bl", Vector2(14, 60), 52.0)
	# Right-thumb ability arc, hugging the bottom-right corner.
	_add_button("CAST", "cast", "br", Vector2(16, 14), 58.0)   # primary (biggest, corner)
	_add_button("DASH", "dash", "br", Vector2(82, 12), 46.0)
	_add_button("Q", "blast", "br", Vector2(22, 82), 46.0)
	_add_button("G", "ultimate", "br", Vector2(86, 74), 50.0)  # the ultimate
	_add_button("BLINK", "blink", "br", Vector2(146, 28), 42.0)
	# Melee and parry had no touch affordance at all — both are core verbs (parry is
	# the whole defensive game), so on a phone they were simply unplayable.
	_add_button("HIT", "melee", "br", Vector2(150, 92), 44.0)
	_add_button("PARRY", "parry", "bl", Vector2(14, 124), 48.0)


func _add_button(label: String, action: String, corner: String, off: Vector2, size: float) -> void:
	var b := Button.new()
	b.text = label
	# The action this button drives, readable from outside so a test can assert the
	# wiring rather than just counting buttons.
	b.set_meta("action", action)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	b.add_theme_constant_override("outline_size", 3)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.24, 0.34, PAD_ALPHA + (0.22 if state == "pressed" else 0.0))
		sb.set_corner_radius_all(int(size * 0.5))
		sb.border_color = Color(0.8, 0.88, 1.0, 0.5)
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	# Anchor to the chosen bottom corner + place by pixel offset (resolution-safe).
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	if corner == "br":
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_left = -off.x - size
		b.offset_right = -off.x
	else:  # bottom-left
		b.offset_left = off.x
		b.offset_right = off.x + size
	b.offset_top = -off.y - size
	b.offset_bottom = -off.y
	# Hold-to-repeat for CAST; a tap for the buffered one-shots (dash/blast/blink/G).
	b.button_down.connect(func() -> void: Input.action_press(action))
	b.button_up.connect(func() -> void: Input.action_release(action))
	add_child(b)


## A round translucent Control (the joystick base/knob), drawn via a circular stylebox.
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
