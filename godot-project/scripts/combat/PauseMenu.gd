class_name PauseMenu
extends Control
## Reusable pause overlay: a dim backdrop + PAUSED + Resume / Settings / Exit.
## Settings expands a sub-panel with a master-VOLUME slider and a CONTROLS
## reference (the maker's ask: "esc needs an exit button as well and settings
## like volume and other stuff like controls"). Built in code (house style, no
## .tscn); process_mode ALWAYS so its buttons work while the tree is paused. The
## host toggles open()/close() and wires the exit action via `exit_requested`.
##
## EXIT already lives on the MAIN column (`_exit_btn`, labelled by the host — "Exit
## to Hub" by default), so nothing here duplicates it into Settings. Settings owns
## the picture, the sound and the reference card; the main column owns the verbs.

signal resume_requested
signal exit_requested
## The on-screen PAUSE affordance was tapped. Hosts already wire `ui_cancel` to
## `open()`; they wire this to the same call and the menu stops being keyboard-only.
signal pause_requested

## ⚠ FALLBACK PROSE ONLY — `controls_text()` is what the menu actually shows, and it
## reads the live InputMap. This const survives because `FreePlay.gd:341` prints it on
## its welcome card and that file is not ours; point it at `controls_text()` and this
## whole string can go. Until then it is the answer for a build whose InputMap has been
## stripped, and it WILL drift, which is exactly why nothing on screen reads it.
const CONTROLS_TEXT: String = "A / D   Move          W / Up   Jump\nSpace   Dash          LMB   Cast\n1 / 2 / 3   Spells          RMB   Parry / Block\nF   Melee          R   Blink          Q   AoE          T   Nova\nG   Cast selected spell          V   Change selection\nTab   Class          X   Element          C   Colour\nEsc / the II button   Pause"

## The controls card as a TABLE OF ACTIONS, one inner array per printed line, each
## entry `[label, [action, ...]]`. No key letter appears here at all — the letters come
## out of `InputMap` at display time.
##
## ⚠ THIS IS THE MOBILE-FIRST REASON, not tidiness. Every input in this game is read
## through a named action (D-011), the touch pad fires those same actions, and a rebind
## screen would move the letters underneath a hardcoded card without touching it. The
## prose version was a second source of truth for the binding table guarded by no test
## at all — it happened to still be right, which is the only state that string is ever
## observed in until the day somebody notices it is not.
##
## Entries carrying SEVERAL actions print one key each (`move_left` + `move_right` ->
## "A / D"); an entry carrying ONE action prints up to two of its bindings, which is how
## Jump keeps both "Up" and "W". Rejected: printing every binding of every action, which
## turns Move into "A / Left / D / Right".
const CONTROL_ROWS: Array = [
	[["Move", ["move_left", "move_right"]], ["Jump", ["jump"]], ["Dash", ["dash"]]],
	[["Cast", ["cast"]], ["Melee", ["melee"]], ["Parry", ["parry"]]],
	# `ultimate` THROWS whichever of the three spell buttons is selected, and is what a
	# bot pulls; `cycle_signature` only moves that selection and casts nothing. Labelled
	# for what the thumb does — "ultimate" is an engine name, not a player-facing one.
	# ⚠ ALSO THE LONGEST LINE ON THE CARD, and the panel is 320 px wide with autowrap
	# off, so both labels are as short as they can be and still be true.
	[["Spells", ["spell_1", "spell_2", "spell_3"]], ["Throw selected", ["ultimate"]],
		["Pick spell", ["cycle_signature"]]],
	[["Blink", ["blink"]], ["AoE", ["blast"]], ["Nova", ["nova"]]],
	[["Class", ["switch_class"]], ["Element", ["cycle_element"]],
		["Colour", ["cycle_colourway"]]],
]
## The last line of the card, keys-then-label like every derived line above it so the
## eye scans one column. The key comes from `ui_cancel`; the `II` button is spelled out
## because it is a real second route into this menu that exists in no InputMap and can
## therefore only be asserted.
const CONTROLS_PAUSE_LINE: String = "%s  /  the II button   Pause"
## Gap between two entries on one line. Wide enough to read as a column break under a
## proportional font, where no amount of padding will actually align anything.
const CONTROLS_GAP: String = "     "

## -- brightness ---------------------------------------------------------------
## ⚠ THE SETTING THIS GAME NEEDS MOST AND HAD NO ROW FOR. Ten authored biomes, several
## of them underground, played on a phone that is often outdoors — "I cannot see the
## floor" is a hardware problem the graphics toggle does not touch, and no phone lets
## you reach the OS brightness slider without leaving the fight.
##
## THREE STEPS AND ONE ROW, not a slider. A slider costs a caption Label plus the
## HSlider — two rows in a panel that already scrolls to reach its bottom — for a knob
## nobody drags twice. Same trade the Graphics row below makes, and the maker's standing
## rule ("too much text and random UI pieces we dont need") decides it.
const BRIGHTNESS_LABELS: PackedStringArray = ["Dim", "Normal", "Bright"]
const BRIGHTNESS_DEFAULT: int = 1
## How black the DIM step lays over the frame, and how much white the BRIGHT step adds.
## Deliberately gentle: this is a legibility aid, not a grade, and it sits on top of
## `PostProcess`'s filmic pass — a heavy lift here would flatten that to milk.
## UNTESTED ON A DEVICE; both numbers are reasoning.
const BRIGHTNESS_DIM_ALPHA: float = 0.28
const BRIGHTNESS_LIFT_ALPHA: float = 0.13
## Above the pause button, the HUD and the director. The overlay covers the pause menu
## ITSELF on purpose: the player is looking at this panel while they cycle the row, and
## a brightness control you cannot see working is a brightness control you do not trust.
const BRIGHTNESS_LAYER: int = 120
## One overlay per scene, however many PauseMenus a host builds — two would stack, and
## `Dim` would land at twice its alpha for reasons no one could see. Same shape, and the
## same `_is_live` walk, as DIRECTOR_GROUP below.
const BRIGHTNESS_GROUP: StringName = &"brightness_overlay"
## ⚠ STORED AS META ON THE SCENE-TREE ROOT, WHICH IS NOT WHERE IT BELONGS. Every other
## picture knob here writes `Tuning.cfg`, and so should this — but `TuningConfig.gd` is
## another file, and `Object.set()` against a property a Resource never declared fails
## SILENTLY: the row would cycle, look right, and reset on the next scene change with
## nothing logged. The root `Window` is the one node that outlives
## `change_scene_to_file`, and `set_meta` needs no declaration to stick. Rejected: a
## plain member var, which forgets every time an arena builds a fresh menu — i.e. always.
const BRIGHTNESS_META: StringName = &"pause_menu_brightness"

## -- the on-screen pause button (mobile) -------------------------------------
## ⚠ WITHOUT THIS THE SETTINGS MENU IS UNREACHABLE ON A PHONE. Every host opens the
## pause menu on `ui_cancel` and nothing else, and a phone has no Esc key — so volume,
## screen shake, hit-stop, aim assist and the graphics toggle were all keyboard-only
## on the one platform this game is being built for.
##
## Top-RIGHT, deliberately: the left thumb owns the move stick and the right thumb the
## three spell buttons, both near the bottom of the screen, so the top corners are the
## only real estate a thumb is never resting on. Right rather than left because a
## right-handed grip reaches it without crossing the aim stick.
const PAUSE_BTN_SIZE: Vector2 = Vector2(44.0, 44.0)
## Margin from the screen corner. Generous enough to clear a rounded corner and a
## notch cutout, which is the failure mode you only find on hardware.
const PAUSE_BTN_MARGIN: float = 10.0
## Resting transparency. Visible enough to find, faint enough not to sit in the middle
## of the fight. UNTESTED ON A DEVICE — every number in this block is reasoning.
const PAUSE_BTN_ALPHA: float = 0.55

## The layer the button draws on. Above the game, comfortably below the pause
## overlay's own contents, which are drawn by this Control at whatever layer the host
## put it on.
const PAUSE_BTN_LAYER: int = 50

## -- the director (debug review rig) -----------------------------------------
## ⚠ TWO INDEPENDENT SHIP GATES, AND THE FIRST ONE IS THE REAL ONE.
##
##   1. THE SCRIPT IS NOT IN AN EXPORTED BUILD. It lives under `res://tools/`,
##      which `export_presets.cfg` excludes from the pack, so `ResourceLoader.
##      exists()` answers false on a phone and no row is ever built. This is the
##      gate that cannot be forgotten, because it is not a decision made at
##      runtime — the bytes are absent.
##   2. `OS.is_debug_build()` — false in a release export. Belt to the braces,
##      and the thing that keeps the director out of a *debug* APK sideloaded
##      onto someone else's phone even if the exclude list is ever edited.
##
## `tools/release_gate_dev_bridge.gd` asserts BOTH: that the preset still
## excludes `res://tools/*`, and that this file still carries the
## `OS.is_debug_build()` guard and does not `preload` the director (a preload
## would drag an excluded script into the pack and break the export outright).
##
## Reached by `load()` + duck typing rather than a typed reference, exactly like
## `VersusArena._probe_begin` reaches its probe: a hard reference to a file that
## is deliberately absent half the time is a compile error waiting for an export.
const DIRECTOR_SCRIPT: String = "res://tools/director/Director.gd"
## One director per scene, however many PauseMenus a host builds — two would
## double every hotkey (F1 open + F1 close on the same press).
const DIRECTOR_GROUP: StringName = &"director"

var _pause_layer: CanvasLayer = null
var _pause_btn: Button = null
var _quality_btn: Button = null
## The Brightness row and the pane it tints. The rect is null in a menu that lost the
## dedupe race (a live sibling already owns the only overlay) — every path here treats
## that as normal, because the group sweep in `_apply_brightness` drives whichever one
## is real rather than only our own.
var _brightness_btn: Button = null
var _brightness_rect: ColorRect = null
var _pvp_btn: Button = null
## The Appearance row. Held so `open()` can re-read the live hero — `C` cycles the
## same palette, so a label written once at build time starts lying immediately.
var _colour_btn: Button = null
var _director: Node = null
## The friendly-fire row. Held so `open()` can re-read the live static — the director
## flips the SAME switch, and a label written once at build time starts lying the
## moment anything else touches it.
var _ff_check: CheckButton = null
var _ff_note: Label = null

var _main_col: VBoxContainer = null
var _settings_col: VBoxContainer = null
var _main_center: CenterContainer = null
var _settings_center: CenterContainer = null
var _exit_label: String = "Exit to Hub"
## Kept so injected items can be slotted ABOVE them — the exit stays the last
## thing on the main menu and Back stays the last thing in Settings, however many
## host-specific rows get added in between.
var _exit_btn: Button = null
var _back_btn: Button = null
## Settings rows are scrollable: the duel knobs pushed the column past the bottom
## of a 720p window, and a control you cannot reach is a control you do not have.
var _settings_scroll: ScrollContainer = null


## Build the overlay. `exit_label` names the exit button (e.g. "Exit to Hub" /
## "Quit"). Starts hidden — the host calls open() on Esc.
func build(exit_label: String = "Exit to Hub") -> void:
	_exit_label = exit_label
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so they don't fall through
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_build_main()
	_build_settings()
	_build_pause_button()
	_build_brightness_overlay()
	# Re-asserted on every build, not only when the row is tapped: a scene change throws
	# the overlay away with the old arena and stands a new one up here, so this is the
	# moment the stored choice becomes visible again.
	_apply_brightness()
	_build_director()


# ------------------------------------------------------------------ director
## Is the debug review rig available in THIS build? See the DIRECTOR_SCRIPT
## block above for why there are two conditions and why the first one is the one
## that matters.
##
## ⚠ DO NOT "SIMPLIFY" THIS BY DROPPING `OS.is_debug_build()`. A debug APK is a
## real thing this project intends to sideload (docs/mobile-export.md §1.5), and
## the file-presence check alone would let the director onto that phone the day
## somebody edits the exclude list for an unrelated reason.
static func director_available() -> bool:
	if not OS.is_debug_build():
		return false
	return ResourceLoader.exists(DIRECTOR_SCRIPT)


## Build the director and give it a row on the MAIN menu (not Settings): it is
## the reason the maker opened the menu, not a preference they are adjusting.
##
## It goes on the main menu rather than behind F1 alone because F1 does not exist
## on a phone — the same reason the pause BUTTON exists at all. Two routes in,
## one of which survives having no keyboard.
func _build_director() -> void:
	if not director_available():
		return
	# ⚠ A DYING DIRECTOR MUST NOT BLOCK A NEW ONE. `queue_free()` lands at the end
	# of the frame and the node stays in its groups until then, so a host that
	# tears down one pause menu and builds another in the same frame would get NO
	# director at all — the same shape as the departed-peer puppet that used to
	# soft-lock Arena's party-wipe check.
	var tree: SceneTree = get_tree()
	if tree != null:
		for d: Node in tree.get_nodes_in_group(DIRECTOR_GROUP):
			if _is_live(d):
				return   # a live sibling PauseMenu already built one
	var script: Resource = load(DIRECTOR_SCRIPT)
	if script == null:
		return
	# The director is a CanvasLayer for the same reason the pause button is: this
	# node is `visible = false` whenever the menu is closed, and the director has
	# to be usable with the menu CLOSED and the game RUNNING. A CanvasLayer is not
	# a CanvasItem, so it does not inherit that hidden state.
	_director = (script as GDScript).new()
	add_child(_director)
	_director.add_to_group(DIRECTOR_GROUP)
	add_action("◆  DIRECTOR  (F1)", func() -> void:
		if _director != null and _director.has_method("set_open"):
			_director.call("set_open", true)
		resume_requested.emit())


## Is this node really still alive — or is it, or anything it hangs off, on its
## way out?
##
## ⚠ `queue_free()` DOES NOT MARK CHILDREN. Calling it on a PauseMenu marks the
## menu and leaves `is_queued_for_deletion()` FALSE on the director underneath
## it, while the whole subtree is nonetheless about to vanish and the director is
## still in its group. Checking only the node itself therefore sees a "live"
## director that will not exist next frame, and the next PauseMenu built in that
## window silently gets none. So the walk goes all the way up.
static func _is_live(n: Node) -> bool:
	if not is_instance_valid(n):
		return false
	var cur: Node = n
	while cur != null:
		if cur.is_queued_for_deletion():
			return false
		cur = cur.get_parent()
	return true


## The live director node, or null in a build that has none. Exposed so a host or
## a test can reach it without knowing where it was parented.
func director() -> Node:
	return _director


## The on-screen PAUSE affordance.
##
## ⚠ IT LIVES ON A `CanvasLayer`, AND THAT IS THE WHOLE TRICK RATHER THAN A STYLE
## CHOICE. This node is a Control that spends almost all of its life `visible = false`
## (that is what "the pause menu is closed" means) with `MOUSE_FILTER_STOP`, so it can
## host neither a visible child nor a clickable one: a Control child of a hidden
## Control is hidden, and making the parent visible instead would put a full-rect
## click-eater over the game. `CanvasLayer` is NOT a CanvasItem, so a parent Control's
## `visible` does not propagate into it — the button draws and takes taps while the
## menu around it is closed, and nothing else on screen is blocked.
##
## `PROCESS_MODE_ALWAYS` is inherited from this node, which is what lets it keep
## receiving input while the tree is paused.
func _build_pause_button() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = PAUSE_BTN_LAYER
	add_child(_pause_layer)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the button itself eats taps
	_pause_layer.add_child(holder)
	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.tooltip_text = "Pause"
	_pause_btn.custom_minimum_size = PAUSE_BTN_SIZE
	_pause_btn.add_theme_font_size_override("font_size", 18)
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.modulate = Color(1.0, 1.0, 1.0, PAUSE_BTN_ALPHA)
	# Styled to match the touch pad's buttons rather than left on the default theme:
	# on a phone this is the ONLY chrome outside the two thumb clusters, and a stock
	# grey rectangle in the corner reads as debug UI rather than as an affordance.
	# It also gets a real PRESS state, because a tap you cannot see land feels broken.
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		var down: bool = state == "pressed"
		sb.bg_color = Color(0.2, 0.24, 0.34, 0.55 + (0.3 if down else 0.0))
		sb.set_corner_radius_all(int(PAUSE_BTN_SIZE.x * 0.35))
		sb.border_color = Color(0.9, 0.96, 1.0, 0.85) if down else Color(0.8, 0.88, 1.0, 0.5)
		sb.set_border_width_all(3 if down else 2)
		_pause_btn.add_theme_stylebox_override(state, sb)
	# Pinned to the top-right corner by anchors, so it lands in the same place on a
	# phone, a tablet and a resized desktop window without anyone computing a position.
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.offset_left = -(PAUSE_BTN_SIZE.x + PAUSE_BTN_MARGIN)
	_pause_btn.offset_top = PAUSE_BTN_MARGIN
	_pause_btn.offset_right = -PAUSE_BTN_MARGIN
	_pause_btn.offset_bottom = PAUSE_BTN_MARGIN + PAUSE_BTN_SIZE.y
	_pause_btn.pressed.connect(_on_pause_pressed)
	holder.add_child(_pause_btn)
	# A touch affordance has no business in a desktop clip: it was burned into the
	# top-right corner of every frame of the first bot fight anybody tried to post.
	# The LAYER is marked, not the button, because the layer is what `open()`/`close()`
	# already drive — one owner for the visibility of this thing, not two.
	Cinematic.mark(_pause_layer)


## Tapped. TWO ROUTES, and the fallback is now a real one rather than a stopgap.
##
## If a host has connected `pause_requested`, that wins — an explicit wire is always
## better than a guess, and a host that wants to save the run or duck the music before
## opening needs somewhere to do it.
##
## OTHERWISE THIS BUTTON PAUSES THE GAME ITSELF: `get_tree().paused = true` + `open()`,
## which is verbatim what `Arena._set_paused(true)` and `VersusArena._set_paused(true)`
## do. RESUMING still goes out through `resume_requested`, so the host stays the owner
## of un-pausing and nothing about the Esc path moves.
##
## ⚠ IT USED TO SYNTHESIZE `ui_cancel` through `Input.parse_input_event`, and that was
## a stopgap with three real problems, not merely an inelegant one:
##   1. Input is PROCESS-GLOBAL. A synthesized action reaches every listener in the
##      tree — the class picker, the loadout screen, the conversation bar all treat
##      `ui_cancel` as "close me". Tapping PAUSE fired all of them.
##   2. It needed `_synth_cancel`, a one-frame flag racing an asynchronously dispatched
##      event, to stop this node reading its OWN synthetic press as "resume" and
##      closing the menu on the frame it opened. A timing flag guarding a timing bug.
##   3. It only worked at all because two hosts happened to listen for that exact
##      action. A third host, or a host that later moved to a dedicated `pause`
##      action, would have had a pause button that silently did nothing.
## Calling the pause directly has none of those failure modes and is the same two
## lines the hosts run.
func _on_pause_pressed() -> void:
	if pause_requested.get_connections().size() > 0:
		pause_requested.emit()
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.paused = true
	open()


## Show or hide the on-screen pause button. Hosts that have no business showing one —
## a menu scene, a cutscene, a run that has already ended — turn it off; nothing else
## needs to care, because it defaults to on.
func set_pause_button_visible(v: bool) -> void:
	if _pause_layer != null:
		# CINEMATIC MODE WINS over a host that wants the button. A group sweep alone is
		# not enough here: this method and `close()` re-assert visibility on their own
		# schedule and would undo the sweep a frame later.
		_pause_layer.visible = v and Cinematic.shows_chrome()


# ---------------------------------------------------------------- brightness
## The full-screen tint the Brightness row drives.
##
## ⚠ A `CanvasLayer`, FOR THE SAME REASON THE PAUSE BUTTON IS ONE, and it is the whole
## trick rather than a style choice: this node is `visible = false` whenever the menu is
## closed, and brightness has to hold while the menu is CLOSED and the game is RUNNING.
## A CanvasLayer is not a CanvasItem, so a parent Control's `visible` never reaches it.
##
## ⚠ DELIBERATELY NOT `Cinematic.mark`ed. Everything else on a high layer here is chrome
## that must leave a recorded clip; this is the player's own screen preference, it draws
## literally nothing at the default step, and sweeping it away mid-capture would change
## the exposure of the footage halfway through.
func _build_brightness_overlay() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		for o: Node in tree.get_nodes_in_group(BRIGHTNESS_GROUP):
			if _is_live(o):
				return   # a live sibling PauseMenu already owns the one overlay
	var layer := CanvasLayer.new()
	layer.layer = BRIGHTNESS_LAYER
	add_child(layer)
	layer.add_to_group(BRIGHTNESS_GROUP)
	_brightness_rect = ColorRect.new()
	_brightness_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IGNORE, not STOP. A pane over the entire screen that ate input would eat the whole
	# game: every tap, every menu button underneath it, at every brightness step.
	_brightness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brightness_rect.visible = false
	layer.add_child(_brightness_rect)


## Dim -> Normal -> Bright -> Dim.
func _on_brightness_pressed() -> void:
	_set_brightness_step((_brightness_step() + 1) % BRIGHTNESS_LABELS.size())
	_apply_brightness()
	if _brightness_btn != null:
		_brightness_btn.text = _brightness_label()


func _brightness_step() -> int:
	var tree: SceneTree = get_tree()
	if tree == null or not tree.root.has_meta(BRIGHTNESS_META):
		return BRIGHTNESS_DEFAULT
	return clampi(int(tree.root.get_meta(BRIGHTNESS_META)), 0, BRIGHTNESS_LABELS.size() - 1)


func _set_brightness_step(step: int) -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.root.set_meta(BRIGHTNESS_META, step)


## Paint EVERY live overlay, not just the one this menu happens to own. The dedupe in
## `_build_brightness_overlay` means a second PauseMenu's `_brightness_rect` is null
## while its Brightness row is perfectly usable — driving only `_brightness_rect` would
## give that menu a row that cycles its label and changes nothing on screen.
func _apply_brightness() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var step: int = _brightness_step()
	for layer: Node in tree.get_nodes_in_group(BRIGHTNESS_GROUP):
		for rect: Node in layer.get_children():
			if rect is ColorRect:
				_paint_brightness(rect as ColorRect, step)


## DARKEN AND BRIGHTEN ARE TWO DIFFERENT OPERATIONS, which is why this is not one alpha.
## Darkening is black over the frame — ordinary alpha blending. Brightening cannot be:
## no alpha over any colour makes a pixel lighter than that colour. It needs ADDITIVE
## blend, which is a `CanvasItemMaterial` and not a property of the rect. Rejected: two
## stacked rects, one per direction, which is a second full-screen overdraw on a phone
## to save building one material.
func _paint_brightness(rect: ColorRect, step: int) -> void:
	match step:
		0:
			rect.material = null
			rect.color = Color(0.0, 0.0, 0.0, BRIGHTNESS_DIM_ALPHA)
			rect.visible = true
		2:
			if rect.material == null or not (rect.material is CanvasItemMaterial):
				var mat := CanvasItemMaterial.new()
				mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				rect.material = mat
			rect.color = Color(1.0, 1.0, 1.0, BRIGHTNESS_LIFT_ALPHA)
			rect.visible = true
		_:
			# Hidden rather than transparent: a hidden ColorRect costs no fill at all,
			# and NORMAL is the step nearly every player leaves it on.
			rect.visible = false


func _brightness_label() -> String:
	return "Brightness:  %s" % BRIGHTNESS_LABELS[_brightness_step()]


func open() -> void:
	visible = true
	_main_center.visible = true
	_settings_center.visible = false
	# Refreshed on every open rather than only when tapped: `graphics_quality` is also
	# reachable from the inspector and from Remote, so a label written once at build
	# time would start lying the moment anyone touched it there.
	if _quality_btn != null:
		_quality_btn.text = _quality_label()
	# Re-read for the same reason: the step lives on the tree root, so a SECOND pause
	# menu in the same scene (free play hangs its knobs on the arena's) can have moved
	# it since this row's label was written.
	if _brightness_btn != null:
		_brightness_btn.text = _brightness_label()
	if _pvp_btn != null:
		_pvp_btn.text = _pvp_label()
	_refresh_friendly_fire()
	# The lobby's colourway pick can only reach a hero that exists, and none did when
	# this menu was built. First open is the first moment one reliably does.
	_sync_colourway()
	if _colour_btn != null:
		_colour_btn.text = _colour_label()
	if _pause_layer != null:
		_pause_layer.visible = false  # the menu has its own Resume row


func close() -> void:
	visible = false
	if _pause_layer != null:
		_pause_layer.visible = Cinematic.shows_chrome()


func _build_main() -> void:
	_main_center = CenterContainer.new()
	_main_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_main_center)
	_main_col = VBoxContainer.new()
	_main_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_col.add_theme_constant_override("separation", 14)
	_main_center.add_child(_main_col)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_main_col.add_child(title)
	_main_col.add_child(_menu_button("Resume  (Esc)", func() -> void: resume_requested.emit()))
	_main_col.add_child(_menu_button("Settings", _open_settings))
	_exit_btn = _menu_button(_exit_label, func() -> void: exit_requested.emit())
	_main_col.add_child(_exit_btn)


# ------------------------------------------------------- host-injected items
## Add a button to the MAIN pause menu (e.g. "Fight the Boss"). Slotted above the
## exit button so leaving is always the last row no matter what a host injects.
##
## ⚠ THIS IS A PLAYER-FACING COLUMN AND HAS NO DEBUG GATE. Everything reached through
## here ships. The DIRECTOR row above is the only cheat in this menu and it pays for
## itself twice over (absent from the pack AND behind `OS.is_debug_build()`) before it
## is allowed to appear; an injected row pays nothing.
##
## OUTSTANDING VIOLATION at the time of writing: `FreePlay.gd:395` injects a **"Heal"**
## row — `hp = max_hp`, `damage_pct = 0` on the live hero, ungated. It is a debug
## affordance sitting on the pause menu of a shipping scene, and the maker has asked for
## it gone. It cannot be removed from here: this function is handed a label and a
## Callable and has no way to tell a cheat from a verb, and refusing rows by label would
## be silent action-at-a-distance — a host calling `add_action` and getting nothing back.
## The fix is deleting that one line in `FreePlay.gd`, or moving it behind that file's
## own `FileAccess.file_exists(DIRECTOR_SCRIPT)` dev block a few lines below it.
func add_action(text: String, cb: Callable) -> Button:
	var b: Button = _menu_button(text, cb)
	_main_col.add_child(b)
	if _exit_btn != null:
		_main_col.move_child(_exit_btn, _main_col.get_child_count() - 1)
	return b


## Add a button to the SETTINGS sub-panel — this is where a host puts its own
## knobs (the duel's difficulty / bot class / learning toggles). Slotted above
## "Back", which stays the last row.
func add_setting_button(text: String, cb: Callable) -> Button:
	var b: Button = _menu_button(text, cb)
	b.custom_minimum_size = Vector2(240, 30)
	b.add_theme_font_size_override("font_size", 14)
	_settings_col.add_child(b)
	if _back_btn != null:
		_settings_col.move_child(_back_btn, _settings_col.get_child_count() - 1)
	return b


## A section heading in the SETTINGS sub-panel, so an injected block of knobs
## reads as its own group rather than as more audio sliders.
func add_setting_section(title: String) -> Label:
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.62))
	_settings_col.add_child(l)
	if _back_btn != null:
		_settings_col.move_child(_back_btn, _settings_col.get_child_count() - 1)
	return l


func _build_settings() -> void:
	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	add_child(_settings_center)
	# SCROLLED. Hosts inject their own rows here (the duel's five knobs), and the
	# column already ran to the bottom of a 720p window with just the built-ins —
	# an unreachable control is not a control.
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.custom_minimum_size = Vector2(320, 520)
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_center.add_child(_settings_scroll)
	_settings_col = VBoxContainer.new()
	_settings_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_col.add_theme_constant_override("separation", 12)
	_settings_scroll.add_child(_settings_col)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	_settings_col.add_child(title)

	# Master volume.
	var vol_label := Label.new()
	vol_label.text = "Master Volume"
	vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(240, 20)
	slider.value = _current_master_linear()
	slider.value_changed.connect(_on_volume_changed)
	_settings_col.add_child(slider)

	# Music volume — drives the dedicated Music bus (independent of Master/SFX).
	var music_label := Label.new()
	music_label.text = "Music Volume"
	music_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(music_label)
	var music_slider := HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01
	music_slider.custom_minimum_size = Vector2(240, 20)
	music_slider.value = _current_music_linear()
	music_slider.value_changed.connect(_on_music_volume_changed)
	_settings_col.add_child(music_slider)
	# The "cool option": cycle the current mood's playlist (same as the M key).
	_settings_col.add_child(_menu_button("Next Track  (M)", func() -> void:
		var m: Node = get_node_or_null("/root/Music")
		if m != null and m.has_method("cycle_track"):
			m.call("cycle_track")))

	# Camera zoom (maker: "we should be able to alter the zoom in the setting").
	# Slider LEFT = wider view, RIGHT = tighter. Applies live + persists.
	var zoom_label := Label.new()
	zoom_label.text = "Camera Zoom"
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(zoom_label)
	var zoom_slider := HSlider.new()
	zoom_slider.min_value = 1.0
	zoom_slider.max_value = 2.6
	zoom_slider.step = 0.05
	zoom_slider.custom_minimum_size = Vector2(240, 20)
	zoom_slider.value = _current_zoom()
	zoom_slider.value_changed.connect(_on_zoom_changed)
	_settings_col.add_child(zoom_slider)

	# Screen shake intensity (0 = off) — motion-sensitivity accessibility; drives
	# Tuning.cfg.shake_scale, which CombatCamera already reads live.
	var shake_label := Label.new()
	shake_label.text = "Screen Shake"
	shake_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(shake_label)
	var shake_slider := HSlider.new()
	shake_slider.min_value = 0.0
	shake_slider.max_value = 1.0
	shake_slider.step = 0.05
	shake_slider.custom_minimum_size = Vector2(240, 20)
	shake_slider.value = _current_shake()
	shake_slider.value_changed.connect(_on_shake_changed)
	_settings_col.add_child(shake_slider)

	# Hit-stop toggle — some players dislike the micro-freeze on impacts.
	var hs_btn := CheckButton.new()
	hs_btn.text = "Hit-Stop"
	hs_btn.button_pressed = _current_hit_stop()
	hs_btn.toggled.connect(_on_hit_stop_toggled)
	_settings_col.add_child(hs_btn)

	# AIM ASSIST. Ships at 0 and 0 is inert — see SpellTargets.assist_aim, which
	# returns the aim it was given before it scans anything at that strength. The
	# slider exists so the spectrum the mobile spec asks for HAS a home without
	# reversing the maker's locked no-auto-aim decision, and so the question can be
	# answered by hand instead of by argument. It bends an aim you already chose by at
	# most SpellTargets.ASSIST_MAX_DEGREES; it never picks a target.
	var aim_label := Label.new()
	aim_label.text = "Aim Assist  (0 = off)"
	aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(aim_label)
	var aim_slider := HSlider.new()
	aim_slider.min_value = 0.0
	aim_slider.max_value = 1.0
	aim_slider.step = 0.05
	aim_slider.custom_minimum_size = Vector2(240, 20)
	aim_slider.value = _current_aim_assist()
	aim_slider.value_changed.connect(_on_aim_assist_changed)
	_settings_col.add_child(aim_slider)

	# ═══════════════════════════════════════════════════════════════ FRIENDLY FIRE
	# ⚠ THE PLAYER HAD NO SWITCH FOR THE MECHANIC THE GAME IS BUILT AROUND.
	# `SpellCaster.friendly_fire` shipped as a static bool with no settings row at
	# all: the DIRECTOR could flip it (a debug rig excluded from the export), and a
	# player could not. Effectively nobody in this genre ships flat-on friendly fire
	# without a dial — L4D2 scales it 0/.1/.3/.5 by difficulty, Deep Rock .10 -> .70
	# by hazard, Nine Parchments offers invert or a 50-50 split, and The Spell Brigade
	# makes disabling it COST a modifier slot. It is available everywhere; it is just
	# never free and never hidden.
	#
	# THIS SHIPS ON/OFF AND NOT A SCALE, DELIBERATELY. A graded multiplier has to live
	# where the damage is applied — `SpellTargets.hurt()`, which this workstream does
	# not own — and a dial that scaled only the basic bolt while every AoE stayed at
	# 100% would be worse than no dial. See the FriendlyFire header for the one-line
	# seam that unlocks the graded version.
	var ff_btn := CheckButton.new()
	ff_btn.text = "Friendly Fire"
	ff_btn.tooltip_text = ("ON: your spells hit your teammate. It is the point.
"
		+ "off: spells pass through each other — and through the crossfire jokes.")
	ff_btn.button_pressed = FriendlyFire.enabled()
	ff_btn.toggled.connect(_on_friendly_fire_toggled)
	_settings_col.add_child(ff_btn)
	_ff_check = ff_btn
	_ff_note = Label.new()
	_ff_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ff_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ff_note.custom_minimum_size = Vector2(240, 0)
	_ff_note.add_theme_font_size_override("font_size", 12)
	_settings_col.add_child(_ff_note)
	_refresh_friendly_fire()

	# GRAPHICS QUALITY. Three states rather than a checkbox because AUTO (the shipping
	# default: LOW on a mobile export, HIGH everywhere else) is a real answer and not
	# the absence of one. The reason it belongs in the player-facing menu rather than
	# staying an inspector field: forcing LOW on a desktop renders the PHONE'S PICTURE
	# without a phone, and no APK has ever been built — so this is currently the only
	# way to look at what the mobile build will look like.
	_quality_btn = _menu_button(_quality_label(), _on_quality_pressed)
	_quality_btn.custom_minimum_size = Vector2(240, 30)
	_quality_btn.add_theme_font_size_override("font_size", 14)
	_settings_col.add_child(_quality_btn)
	# Directly under Graphics because the two are one question — "can I see what is
	# happening" — asked of the renderer and then of the panel it is played on.
	_brightness_btn = _menu_button(_brightness_label(), _on_brightness_pressed)
	_brightness_btn.custom_minimum_size = Vector2(240, 30)
	_brightness_btn.add_theme_font_size_override("font_size", 14)
	_settings_col.add_child(_brightness_btn)
	# HOW A PVP FIGHT IS WON. Same cycling-button shape as quality above, and for
	# the same reason: two states and one label cost one row in a panel that is
	# already scrolled to reach its bottom on a 720p window.
	_pvp_btn = _menu_button(_pvp_label(), _on_pvp_pressed)
	_pvp_btn.custom_minimum_size = Vector2(240, 30)
	_pvp_btn.add_theme_font_size_override("font_size", 14)
	_settings_col.add_child(_pvp_btn)

	# PERFORMANCE OVERLAY. Lives next to the quality toggle because the two are one
	# workflow: flip to LOW, watch the frame time. Silently absent when the Perf
	# autoload is not registered (a headless run, or a build that excluded it).
	if _perf_overlay() != null:
		_settings_col.add_child(_menu_button("Performance Overlay", func() -> void:
			var p: Node = _perf_overlay()
			if p != null and p.has_method("toggle"):
				p.call("toggle")))

	# Controls reference.
	var ctrl_title := Label.new()
	ctrl_title.text = "Controls"
	ctrl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl_title.add_theme_font_size_override("font_size", 18)
	_settings_col.add_child(ctrl_title)
	var ctrl := Label.new()
	ctrl.text = controls_text()
	ctrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl.add_theme_font_size_override("font_size", 13)
	ctrl.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95))
	_settings_col.add_child(ctrl)

	_build_appearance()

	_back_btn = _menu_button("Back", _close_settings)
	_settings_col.add_child(_back_btn)


# ------------------------------------------------------------------ controls
## The controls card, built from the LIVE InputMap rather than from prose.
##
## Static, so the welcome card in `FreePlay.gd` can move off `CONTROLS_TEXT` onto this
## with a one-word edit whenever that file is next opened.
##
## An action the map does not carry is DROPPED rather than printed blank: a card that
## silently loses a line when a binding is deleted is honest, and one that offers a verb
## with no key next to it is not. If the whole map is missing — a stripped build, or a
## test that never loaded `project.godot` — the prose fallback is better than a blank
## panel, so that is what comes back.
static func controls_text() -> String:
	var lines: PackedStringArray = []
	for row: Array in CONTROL_ROWS:
		var entries: PackedStringArray = []
		for entry: Array in row:
			var keys: String = _key_hint(entry[1] as Array)
			if keys != "":
				entries.append("%s   %s" % [keys, entry[0]])
		if entries.size() > 0:
			lines.append(CONTROLS_GAP.join(entries))
	var pause_keys: String = _key_hint(["ui_cancel"])
	if pause_keys != "":
		lines.append(CONTROLS_PAUSE_LINE % pause_keys)
	if lines.is_empty():
		return CONTROLS_TEXT
	return "\n".join(lines)


## The key letters for one card entry. See CONTROL_ROWS for why the number of bindings
## printed depends on how many actions the entry names.
static func _key_hint(actions: Array) -> String:
	var per_action: int = 2 if actions.size() == 1 else 1
	var out: PackedStringArray = []
	for action: String in actions:
		if not InputMap.has_action(action):
			continue
		var taken: int = 0
		for ev: InputEvent in InputMap.action_get_events(action):
			if taken >= per_action:
				break
			var label: String = _event_label(ev)
			# Deduped because several actions legitimately share a binding — `jump` and
			# `move_up` are both W and Up — and "Up / Up" is not a control scheme.
			if label == "" or out.has(label):
				continue
			out.append(label)
			taken += 1
	return " / ".join(out)


## One InputEvent as the thing printed on a key cap.
##
## ⚠ PHYSICAL KEYCODE FIRST. Every binding in `project.godot` is stored physically so
## QWERTY and AZERTY players get the same layout (set in M1 and never revisited), which
## means `keycode` is 0 on all of them and reading it would print nothing at all.
##
## `as_text()` is not used at all, though it would be shorter: it DECORATES. A physical
## key comes back as "A (Physical)" and a mouse button as "Left Mouse Button" — neither
## fits a card whose whole job is to be scanned.
##
## ⚠ GAMEPAD EVENTS RETURN "" ON PURPOSE, which is a real editorial call and not a gap.
## `project.godot` binds no pad at all; the only joypad events in the map are the ones
## Godot ships on its built-in `ui_*` actions, so printing them would put "Joypad Button
## 1 (Bottom Action…)" on the Pause line of a game that cannot be played with a pad. The
## day a pad is actually bound, this is the function that has to learn about it.
static func _event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return OS.get_keycode_string(code) if code != 0 else ""
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
	return ""


# ---------------------------------------------------------------- appearance
## YOUR COLOURWAY, where a player can actually find it.
##
## `cycle_colourway` has been a real, bound input action (`C`) driving a real palette
## (`Hero.COLOURWAYS`, five limb tints) for a long time, and no player would ever have
## discovered it: it is on no HUD, in no menu, and — the part that matters for a game
## being built for phones — **there is no `C` key on a phone**, so the whole feature
## was unreachable on the target platform.
##
## It earns a row rather than being filed as vanity because of co-op. Two stick figures
## at 640x360 on a 6-inch screen, in a game whose social engine is friendly fire, is a
## genuine readability problem: "who did I just hit" has to be answerable at a glance.
##
## ⚠ HOW IT APPLIES, HONESTLY. This drives the LIVE hero by calling the same private
## cycle the `C` binding calls, so it is exactly the behaviour that already shipped,
## reached by thumb. What it is NOT is a choice that survives into the next run:
## `Hero` reads no colourway at spawn, so the Outfitter's lobby-side pick
## (`Outfitter.chosen_colourway`) can only be REPLAYED onto the hero once one exists,
## which is what `_sync_colourway` does the first time this menu opens. The clean
## version is one line in `Hero._ready` — read `Outfitter.chosen_colourway` next to
## where it reads the class — and `Hero.gd` was owned elsewhere when this landed.
func _build_appearance() -> void:
	if Outfitter.colourways().is_empty():
		return
	add_setting_section("Appearance")
	_colour_btn = add_setting_button(_colour_label(), _cycle_colour)


## The palette entry the local hero is actually wearing, or -1 if there is no hero in
## this scene (the pause menu is built by scenes that have none).
func _hero_colourway() -> int:
	var hero: Node = get_tree().get_first_node_in_group("hero")
	if hero == null:
		return -1
	var v: Variant = hero.get(&"_colourway")
	return int(v) if v != null else -1


func _colour_label() -> String:
	var i: int = _hero_colourway()
	if i < 0:
		i = Outfitter.chosen_colourway
	return "Colour:  %s" % Outfitter.colourway_name(i)


func _cycle_colour() -> void:
	var count: int = maxi(Outfitter.colourways().size(), 1)
	Outfitter.chosen_colourway = (Outfitter.chosen_colourway + 1) % count
	_sync_colourway()
	if _colour_btn != null:
		_colour_btn.text = _colour_label()


## Walk the live hero's colourway around to the chosen one by calling the SAME cycle
## the key binding calls — rather than writing `_colourway` and the rig tint directly,
## which would be two places to keep in step with a method that already does both.
## Bounded by the palette size, so a hero that does not answer cannot spin here.
func _sync_colourway() -> void:
	var hero: Node = get_tree().get_first_node_in_group("hero")
	if hero == null or not hero.has_method("_cycle_colourway"):
		return
	var count: int = Outfitter.colourways().size()
	for _i: int in count:
		if _hero_colourway() == Outfitter.chosen_colourway:
			return
		hero.call("_cycle_colourway")


func _open_settings() -> void:
	_main_center.visible = false
	_settings_center.visible = true


func _close_settings() -> void:
	_settings_center.visible = false
	_main_center.visible = true


## Standard sized menu button wired to a Callable.
func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 38)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b


# --------------------------------------------------------------- resume on Esc
## PauseMenu is PROCESS_MODE_ALWAYS, so it keeps getting input while the tree is
## paused — that's how Esc closes the menu even though the (pausable) host can't
## process input while paused. Only acts while the menu is open.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ audio (master bus)
func _master_bus() -> int:
	return AudioServer.get_bus_index("Master")


func _music_bus() -> int:
	return AudioServer.get_bus_index("Music")


func _current_music_linear() -> float:
	var idx: int = _music_bus()
	if idx < 0:
		return 1.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


func _on_music_volume_changed(v: float) -> void:
	var idx: int = _music_bus()
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0)


func _current_master_linear() -> float:
	var idx: int = _master_bus()
	if idx < 0:
		return 1.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


func _on_volume_changed(v: float) -> void:
	var idx: int = _master_bus()
	if idx < 0:
		return
	# A linear 0 slider = silence; otherwise map to dB.
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) if v > 0.0 else -80.0)


# ------------------------------------------------------------------ camera zoom
## Current resting zoom from GameState (falls back to a sensible middle).
func _current_zoom() -> float:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var v: Variant = gs.get("camera_zoom")
		if v != null:
			return float(v)
	return 1.6


## Live-apply the zoom to every combat camera (they persist it to GameState).
func _on_zoom_changed(v: float) -> void:
	for cam: Node in get_tree().get_nodes_in_group("combat_camera"):
		if cam.has_method("set_base_zoom"):
			cam.call("set_base_zoom", v)


## The Tuning autoload's live config resource (holds shake_scale, hit_stop_enabled).
func _tuning_cfg() -> Object:
	var t: Node = get_node_or_null("/root/Tuning")
	if t != null:
		return t.get("cfg")
	return null


func _current_shake() -> float:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		var v: Variant = cfg.get("shake_scale")
		if v != null:
			return float(v)
	return 1.0


## Screenshake slider → Tuning.cfg.shake_scale (CombatCamera reads it live via
## trauma * trauma * shake_scale). Persists across scenes (Tuning is an autoload).
func _on_shake_changed(v: float) -> void:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		cfg.set("shake_scale", v)


# ------------------------------------------------------------------ aim assist
func _current_aim_assist() -> float:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		var v: Variant = cfg.get("aim_assist")
		if v != null:
			return clampf(float(v), 0.0, 1.0)
	return 0.0


## Slider → Tuning.cfg.aim_assist, which `SpellTargets.assist_strength` reads live on
## the frame the aim is resolved, so dragging it changes the feel without a restart.
func _on_aim_assist_changed(v: float) -> void:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		cfg.set("aim_assist", v)


# ------------------------------------------------------------- friendly fire
## ⚠ WRITES `FriendlyFire.set_enabled`, WHICH WRITES `SpellCaster.friendly_fire` —
## the one static the whole mechanic hangs off. It is NOT mirrored into a local bool
## here: the director's VIEW tab toggles the same static, and two mirrors of one
## switch is how a player ends up turning friendly fire "off" and still deleting
## their friend.
func _on_friendly_fire_toggled(on: bool) -> void:
	FriendlyFire.set_enabled(on)
	_refresh_friendly_fire()


func _refresh_friendly_fire() -> void:
	var on: bool = FriendlyFire.enabled()
	if _ff_check != null:
		_ff_check.set_pressed_no_signal(on)
	if _ff_note == null:
		return
	# The note is the SIGNPOST as much as the setting is. Magicka 2 puts "friendly
	# fire is always on" in its own Steam feature list; Frozenbyte publicly conceded
	# that Nine Parchments' friendly fire "was not well represented in trailers and
	# descriptions, which was a clear mistake". If it is the engine, it has to be
	# stated somewhere the player will actually meet it.
	_ff_note.text = ("your spells hit your friend. that is the game."
		if on else "spells pass through your friend.")
	_ff_note.add_theme_color_override("font_color",
		FriendlyFire.TEAM_TINT if on else Color(0.66, 0.70, 0.80))


# ------------------------------------------------------------ graphics quality
## AUTO -> HIGH -> LOW -> AUTO. A cycling button rather than three radio rows: the
## panel is already scrolled to reach its bottom on a 720p window, and a setting with
## three states and one label costs one row instead of four.
func _on_quality_pressed() -> void:
	var cfg: Object = _tuning_cfg()
	if cfg == null:
		return
	var v: Variant = cfg.get("graphics_quality")
	var cur: int = TuningConfig.Quality.AUTO if v == null else int(v)
	cfg.set("graphics_quality", (cur + 1) % 3)
	if _quality_btn != null:
		_quality_btn.text = _quality_label()


## The label says what the setting IS *and*, for AUTO, what it currently RESOLVES to —
## because "Auto" alone leaves the one question the maker actually has ("am I looking
## at the phone's picture right now?") unanswered on the screen that is supposed to
## answer it.
func _quality_label() -> String:
	var cfg: Object = _tuning_cfg()
	var v: Variant = cfg.get("graphics_quality") if cfg != null else null
	var cur: int = TuningConfig.Quality.AUTO if v == null else int(v)
	match cur:
		TuningConfig.Quality.HIGH:
			return "Graphics: HIGH"
		TuningConfig.Quality.LOW:
			return "Graphics: LOW  (phone preview)"
	return "Graphics: AUTO  (%s)" % ("low" if TuningConfig.quality_is_low() else "high")


func _perf_overlay() -> Node:
	return get_node_or_null(^"/root/Perf")


func _current_hit_stop() -> bool:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		var v: Variant = cfg.get("hit_stop_enabled")
		if v != null:
			return bool(v)
	return true


func _on_hit_stop_toggled(on: bool) -> void:
	var cfg: Object = _tuning_cfg()
	if cfg != null:
		cfg.set("hit_stop_enabled", on)


## ⚠ HEALTH <-> STOCKS. The maker's ask, verbatim: "I like health instead for the
## pvp (or in settings give the users the options to choose lives vs percentages)".
##
## Both models were ALREADY fully built in `VersusArena` — hp-drain, and the Smash
## damage-%/ring-out model with respawns and invuln. The sandbox simply forced the
## second one. This chooses; `GameState.pvp_rules` is the single owner.
##
## Takes effect on the NEXT duel rather than mid-fight: `VersusArena._ready` reads
## it once, and switching the win condition out from under a live fight would be a
## worse bug than the one this fixes.
func _on_pvp_pressed() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.set("pvp_rules", 1 - int(gs.get("pvp_rules")))
	if _pvp_btn != null:
		_pvp_btn.text = _pvp_label()


func _pvp_label() -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	var cur: int = 0 if gs == null else int(gs.get("pvp_rules"))
	# Named for what the player SEES happen, not the internal flag: "stocks" is the
	# word for the mode where you are knocked off the stage and lose a life.
	return "PvP: Health" if cur == 0 else "PvP: Stocks + %"
