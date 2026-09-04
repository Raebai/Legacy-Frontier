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

## ⚠ TWO SHARED SCRIPTS, BOTH `preload`ed AND NEITHER A `class_name`. A global class
## has to be registered in `.godot/global_script_class_cache.cfg`, which is rebuilt by
## an editor scan or an `--import`; a consumer compiled before that scan dies with
## "Could not find type X in the current scope" (Sessions 6/8/9 lost real time to
## exactly this trap). A `preload` resolves at load time with no cache involved.
const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const Settings := preload("res://scripts/Settings.gd")

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
const CONTROLS_TEXT: String = "A / D   Move          W / Up   Jump\nSpace   Dash          LMB   Cast\n1 / 2 / 3 / 4   Spells          RMB   Parry / Block\nF   Melee          R   Blink          Q   AoE          T   Nova\nG   Cast selected spell          V   Change selection\nTab   Class          X   Element          C   Colour\nEsc / the II button   Pause"

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
	[["Spells", ["spell_1", "spell_2", "spell_3", "spell_4"]], ["Throw selected", ["ultimate"]],
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
const BRIGHTNESS_DEFAULT: int = Settings.BRIGHTNESS_DEFAULT
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
##
## ⚠ THE META IS STILL WHERE THE LIVE VALUE LIVES; what changed is that the STEP is now
## also written to `user://settings.cfg` and pushed back onto this same meta at boot by
## `Settings.apply_all`, so it survives closing the game as well as a scene change. The
## key is declared in `Settings` and aliased here so there is one string, not two.
const BRIGHTNESS_META: StringName = Settings.BRIGHTNESS_META

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

## -- the card, and why it kept falling off the screen -------------------------
## ⚠ MEASURED, NOT GUESSED. `tools/probe_settings_panel.gd` printed this before the
## fix, on the real 640x360 base viewport:
##
##     scroll min      : (320.0, 520.0)
##     scroll rect     : y 0.0 .. 520.0
##     off-screen      : 160.0 px below
##     content height  : 1195.0 px   (scroll viewport 520.0)
##     never reachable : 160.0 px of content, at ANY scroll position
##
## A `ScrollContainer` inside a `CenterContainer` is handed its MINIMUM size, so a
## hardcoded 520 IS the panel — 160 px taller than the screen it sits on. Scrolling
## only moves content INSIDE that box, so the band hanging off the bottom stayed
## hidden at every scroll position: the last rows of the settings column could not be
## reached by scrolling, by resizing, or at all.
##
## The rule now is `min(content, screen)` — see `_fit_one`.
const SCREEN_MARGIN: float = 8.0    # air between the card and the screen edge
const PANEL_PAD: float = 10.0       # the card's own inner padding, per side
## The width the settings rows were authored against (240 px controls + air). Only an
## upper bound now: a column of short rows gets a narrower card.
const CARD_MAX_W: float = 330.0

## -- rebinding ----------------------------------------------------------------
## ⚠ THE PROJECT'S OWN BINDINGS ARE NEVER EDITED. `project.godot` is not this
## workstream's file, and it is rewritten by the clip pipeline mid-shoot besides. A
## rebind is a RUNTIME OVERLAY: `Settings` snapshots the shipped map at boot, applies
## the player's overrides on top, and "Reset to Defaults" puts the snapshot back.
##
## ⚠ AND IT IS KEYBOARD/MOUSE ONLY, WHICH IS A CORRECTNESS RULE RATHER THAN A SCOPE
## CUT. `Input.is_action_pressed` aggregates every device, so a joypad button bound to
## an action would drive player ONE whenever player TWO pressed it. This repo keeps the
## pad out of the action map on purpose (`PadController` reads raw per-device state);
## `Settings.is_rebindable_event` refuses everything that is not a key or a mouse button.
##
## ⚠ ESC CANNOT BE BOUND TO ANYTHING, because Esc is how you cancel a capture. It is
## the one key the picker spends. Pause keeps its shipped Esc binding unless the player
## deliberately moves it to another key.
const REBIND_PROMPT: String = "press a key…"
const REBIND_HINT: String = "tap a key to change it   ·   Esc cancels"

var _pause_layer: CanvasLayer = null
var _pause_btn: Button = null
var _quality_btn: Button = null
## The Brightness row and the pane it tints. The rect is null in a menu that lost the
## dedupe race (a live sibling already owns the only overlay) — every path here treats
## that as normal, because the group sweep in `_apply_brightness` drives whichever one
## is real rather than only our own.
var _brightness_btn: Button = null
var _fullscreen_btn: Button = null
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
## The settings page's own Resume row. Pinned to the very bottom alongside `_back_btn`
## so an injected knob never lands underneath the way out.
var _resume_btn: Button = null
## Settings rows are scrollable: the duel knobs pushed the column past the bottom
## of a 720p window, and a control you cannot reach is a control you do not have.
var _settings_scroll: ScrollContainer = null
## The MAIN column scrolls for the same reason and it is not hypothetical: hosts inject
## rows here too (`FreePlay` alone adds four, plus the director), and the main page had
## no scroll at all — it simply grew past the screen.
var _main_scroll: ScrollContainer = null

## -- the controls / rebinding page --------------------------------------------
## A THIRD PAGE rather than more rows in Settings, and the reason is the measurement
## above: twenty binding rows on the end of an already-1195px column is another 400 px
## of scrolling to reach "Back". It also retires the generated controls CARD, which was
## one 337-px-wide `Label` in a 320-px panel — it did not clip, it INFLATED the panel to
## 343 px, which is why the settings card was never the width it was authored at.
var _controls_center: CenterContainer = null
var _controls_scroll: ScrollContainer = null
var _controls_col: VBoxContainer = null
## action -> the Button showing its key cap, so a rebind or a reset repaints every row
## without rebuilding the page (a rebuild would drop the scroll position under the
## player's thumb mid-edit).
var _rebind_caps: Dictionary = {}
## The action currently listening for a key, or &"" when nothing is.
var _rebinding: StringName = &""
var _rebind_note: Label = null


## Build the overlay. `exit_label` names the exit button (e.g. "Exit to Hub" /
## "Quit"). Starts hidden — the host calls open() on Esc.
func build(exit_label: String = "Exit to Hub") -> void:
	_exit_label = exit_label
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so they don't fall through
	visible = false
	var dim := ColorRect.new()
	# The house scrim, from `HudStyle`, instead of this file's own near-black. It was
	# `(0.03, 0.03, 0.06, 0.74)` — one of eleven near-blacks the HUD survey found, each
	# rounded differently, which is most of what "unpolished" actually looks like.
	dim.color = HudStyle.scrim()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	# The shipped key map has to be snapshotted before anything can be reset TO it.
	# `Screen` does this at boot; repeated here because a headless suite or an F6 scene
	# has no autoloads, and it is idempotent.
	Settings.capture_input_defaults()
	_build_main()
	_build_settings()
	_build_controls()
	_build_pause_button()
	_build_brightness_overlay()
	# Re-asserted on every build, not only when the row is tapped: a scene change throws
	# the overlay away with the old arena and stands a new one up here, so this is the
	# moment the stored choice becomes visible again.
	_apply_brightness()
	_build_director()
	# Size the cards to whatever screen this actually is. Also re-run on every `open()`
	# — hosts inject rows AFTER `build()` returns (the duel adds five), so the height
	# measured here is not the height the player will meet.
	_fit_panels()
	# ⚠ AND AGAIN WHENEVER THE WINDOW CHANGES SHAPE. `stretch/aspect="expand"` keeps
	# 640 wide and grows the HEIGHT on a tall window (and vice versa), so the space a
	# card has is not a constant even at a fixed base viewport. Guarded because a host
	# may call `build()` before parenting us.
	if is_inside_tree():
		var vp: Viewport = get_viewport()
		if vp != null and not vp.size_changed.is_connected(_fit_panels):
			vp.size_changed.connect(_fit_panels)


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
	Settings.set_v(Settings.S_VIDEO, Settings.K_BRIGHTNESS, step)


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
	# Always lands on the main page, and `_show_page` also cancels a half-finished
	# rebind and re-fits the cards — hosts inject rows AFTER `build()` returns, so the
	# heights measured at build time are not the heights the player meets.
	_show_page(_main_center)
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


## ═════════════════════════════════════════════════════════ the three pages
## Every page is the same sandwich: a CenterContainer holding a styled PanelContainer
## holding a ScrollContainer holding the column. One shape, built once, so the pause
## menu, the settings and the controls page cannot drift into three different looks —
## which is precisely what the HUD survey found had happened everywhere else.
func _build_page(title_text: String, font_size: int) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	# ⚠ `HudStyle.panel()` VERBATIM, THEN TIGHTER MARGINS. The shape (PAPER ground, a
	# 1px accent rule, a 3px radius) is the one panel the maker has signed off on and is
	# kept exactly; its 26px side padding is authored for the full-width game-over card
	# and would eat 52 of a 640-wide screen's 330-px settings column.
	var box: StyleBoxFlat = HudStyle.panel(HudStyle.with_a(HudStyle.SKY, 0.45))
	box.content_margin_left = PANEL_PAD
	box.content_margin_right = PANEL_PAD
	box.content_margin_top = PANEL_PAD
	box.content_margin_bottom = PANEL_PAD
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	# Horizontal scrolling stays OFF: a settings card that slides sideways under a thumb
	# is a card whose rows are never where you left them. Everything here is authored to
	# fit the width instead.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll)
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)
	if title_text != "":
		var title := Label.new()
		title.text = title_text
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		HudStyle.label(title, font_size, HudStyle.CHALK)
		col.add_child(title)
	return [center, scroll, col]


func _build_main() -> void:
	# LEAD (20), not the old 40. At a 640x360 base, 40 px of "PAUSED" was a fifth of the
	# screen's height spent on a word nobody needs to read twice — and it was a seventh
	# authored font size in a HUD that now has five.
	var page: Array = _build_page("PAUSED", HudStyle.LEAD)
	_main_center = page[0] as CenterContainer
	_main_scroll = page[1] as ScrollContainer
	_main_col = page[2] as VBoxContainer
	_main_col.add_theme_constant_override("separation", 8)
	_main_col.add_child(_menu_button("Resume  (Esc)", func() -> void: resume_requested.emit()))
	_main_col.add_child(_menu_button("Settings", _open_settings))
	_exit_btn = _menu_button(_exit_label, func() -> void: exit_requested.emit())
	# The way OUT is the one row that is not the house blue. It is the only destructive
	# verb on the page and it should not look like "Resume".
	_style_button(_exit_btn, HudStyle.EMBER)
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
	var b: Button = _settings_row_button(text, cb)
	_settings_col.add_child(b)
	_pin_footer()
	return b


## A section heading in the SETTINGS sub-panel, so an injected block of knobs
## reads as its own group rather than as more audio sliders.
func add_setting_section(title: String) -> Label:
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# GOLD from the house palette, not this file's own `(1.0, 0.88, 0.62)` — one of the
	# seven near-identical golds the HUD survey found across seven files.
	HudStyle.label(l, HudStyle.BODY, HudStyle.GOLD)
	_settings_col.add_child(l)
	_pin_footer()
	return l


## Keep the settings page's two exits at the very bottom, in that order, however many
## knobs a host injects above them. It used to be one line repeated in both injectors
## and it only pinned `Back`; with a Resume row alongside it, an un-pinned second exit
## would drift up the column as rows arrive and end up in the middle of the duel's
## own settings.
func _pin_footer() -> void:
	var last: int = _settings_col.get_child_count() - 1
	if _back_btn != null:
		_settings_col.move_child(_back_btn, last)
	if _resume_btn != null:
		_settings_col.move_child(_resume_btn, last)


func _build_settings() -> void:
	# SCROLLED, and now also SIZED — see the SCREEN_MARGIN block for the measurement.
	# Hosts inject their own rows here (the duel's five knobs) on top of the built-ins.
	var page: Array = _build_page("SETTINGS", HudStyle.BODY)
	_settings_center = page[0] as CenterContainer
	_settings_scroll = page[1] as ScrollContainer
	_settings_col = page[2] as VBoxContainer
	_settings_center.visible = false

	_settings_col.add_child(_slider_row("Master Volume", 0.0, 1.0, 0.01,
		_current_master_linear(), _on_volume_changed))
	# Music volume — drives the dedicated Music bus (independent of Master/SFX).
	_settings_col.add_child(_slider_row("Music Volume", 0.0, 1.0, 0.01,
		_current_music_linear(), _on_music_volume_changed))
	# The "cool option": cycle the current mood's playlist (same as the M key).
	_settings_col.add_child(_settings_row_button("Next Track  (M)", func() -> void:
		var m: Node = get_node_or_null("/root/Music")
		if m != null and m.has_method("cycle_track"):
			m.call("cycle_track")))

	# Camera zoom (maker: "we should be able to alter the zoom in the setting").
	# Slider LEFT = wider view, RIGHT = tighter. Applies live + persists.
	_settings_col.add_child(_slider_row("Camera Zoom", 1.0, 2.6, 0.05,
		_current_zoom(), _on_zoom_changed))

	# Screen shake intensity (0 = off) — motion-sensitivity accessibility; drives
	# Tuning.cfg.shake_scale, which CombatCamera already reads live.
	_settings_col.add_child(_slider_row("Screen Shake", 0.0, 1.0, 0.05,
		_current_shake(), _on_shake_changed))

	# Hit-stop toggle — some players dislike the micro-freeze on impacts.
	var hs_btn := CheckButton.new()
	hs_btn.text = "Hit-Stop"
	hs_btn.button_pressed = _current_hit_stop()
	hs_btn.toggled.connect(_on_hit_stop_toggled)
	_style_check(hs_btn)
	_settings_col.add_child(hs_btn)

	# AIM ASSIST. Ships at 0 and 0 is inert — see SpellTargets.assist_aim, which
	# returns the aim it was given before it scans anything at that strength. The
	# slider exists so the spectrum the mobile spec asks for HAS a home without
	# reversing the maker's locked no-auto-aim decision, and so the question can be
	# answered by hand instead of by argument. It bends an aim you already chose by at
	# most SpellTargets.ASSIST_MAX_DEGREES; it never picks a target.
	_settings_col.add_child(_slider_row("Aim Assist  (0 = off)", 0.0, 1.0, 0.05,
		_current_aim_assist(), _on_aim_assist_changed))

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
	_style_check(ff_btn)
	_settings_col.add_child(ff_btn)
	_ff_check = ff_btn
	_ff_note = Label.new()
	_ff_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ff_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ff_note.custom_minimum_size = Vector2(240, 0)
	_ff_note.add_theme_font_size_override("font_size", HudStyle.SMALL)
	_settings_col.add_child(_ff_note)
	_refresh_friendly_fire()

	# GRAPHICS QUALITY. Three states rather than a checkbox because AUTO (the shipping
	# default: LOW on a mobile export, HIGH everywhere else) is a real answer and not
	# the absence of one. The reason it belongs in the player-facing menu rather than
	# staying an inspector field: forcing LOW on a desktop renders the PHONE'S PICTURE
	# without a phone, and no APK has ever been built — so this is currently the only
	# way to look at what the mobile build will look like.
	_quality_btn = _settings_row_button(_quality_label(), _on_quality_pressed)
	_settings_col.add_child(_quality_btn)
	# Directly under Graphics because the two are one question — "can I see what is
	# happening" — asked of the renderer and then of the panel it is played on.
	_brightness_btn = _settings_row_button(_brightness_label(), _on_brightness_pressed)
	_settings_col.add_child(_brightness_btn)
	# ⚠ FULLSCREEN GETS A ROW *AND* A KEY. Maker: *"this game needs full screen
	# capabilities"*. F11 is the muscle memory and `Screen` owns it globally, but a
	# setting that exists only as an unlabelled keybind is a setting most players never
	# find — and this panel is where they will look. Same cycling-label shape as the
	# quality and brightness rows above it.
	_fullscreen_btn = _settings_row_button(_fullscreen_label(), _on_fullscreen_pressed)
	_settings_col.add_child(_fullscreen_btn)
	# HOW A PVP FIGHT IS WON. Same cycling-button shape as quality above, and for
	# the same reason: two states and one label cost one row in a panel that is
	# already scrolled to reach its bottom on a 720p window.
	_pvp_btn = _settings_row_button(_pvp_label(), _on_pvp_pressed)
	_settings_col.add_child(_pvp_btn)

	# PERFORMANCE OVERLAY. Lives next to the quality toggle because the two are one
	# workflow: flip to LOW, watch the frame time. Silently absent when the Perf
	# autoload is not registered (a headless run, or a build that excluded it).
	if _perf_overlay() != null:
		_settings_col.add_child(_settings_row_button("Performance Overlay", func() -> void:
			var p: Node = _perf_overlay()
			if p != null and p.has_method("toggle"):
				p.call("toggle")))

	# ⚠ THE CONTROLS CARD IS GONE AND ITS REPLACEMENT IS EDITABLE. It was a single
	# generated `Label` whose longest line measured 337 px in a panel authored at 320
	# with `horizontal_scroll_mode` DISABLED and no autowrap — so it did not clip, it
	# INFLATED the whole settings card to 343 px wide, which is why this panel was never
	# the width it says it is. (On any viewport narrower than that it would clip
	# outright, with the right-hand keys simply not drawn.)
	#
	# It was also read-only, in a game that had NO key rebinding anywhere — and the
	# header on `CONTROL_ROWS` had already written down why that was cheap to fix: every
	# input goes through a named action (D-011), so the letters were always coming out of
	# `InputMap` at display time. The card is now one row per action with its key on a
	# button you can press to change it. Same table, same source of truth, one page over.
	_settings_col.add_child(_settings_row_button("Controls…", _open_controls))

	_build_appearance()

	_back_btn = _settings_row_button("Back", _close_settings)
	_settings_col.add_child(_back_btn)
	# ⚠ AND A WAY STRAIGHT BACK INTO THE GAME. Maker: *"pausing should have a resume
	# button as well when I pause"*. The MAIN page has always had one — but a host that
	# hangs its knobs here (the duel's Fighter A / Fighter B / Difficulty / Fighter HP
	# rows all arrive through `add_setting_button`) drops you on THIS page, whose only
	# exit was "Back" to a menu you then had to read again to find "Resume". Two
	# presses and a page change to undo a pause you only opened to nudge a dial.
	#
	# It emits the SAME `resume_requested` the main row does rather than closing
	# anything itself, so the host stays the owner of the actual unpause — see the note
	# on that signal.
	_resume_btn = _settings_row_button("Resume  (Esc)",
		func() -> void: resume_requested.emit())
	_settings_col.add_child(_resume_btn)


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
## ⚠ THE IMPLEMENTATION MOVED TO `Settings.event_label` AND THIS IS NOW A FORWARDER,
## because the rebinding page needs the identical answer and two copies of "what is
## printed on a key cap" is exactly how the printed card and the editable list would
## start disagreeing. It is kept as a member because `_key_hint` (and therefore the
## `controls_text()` that `FreePlay.gd` is pointed at) calls it.
##
## The reasoning that used to live here — physical keycode first, because every binding
## in `project.godot` is stored physically for AZERTY/QWERTZ and `keycode` is 0 on all
## of them; `as_text()` refused because it DECORATES ("A (Physical)"); pad events
## returning "" on purpose — is now on `Settings.event_label` and
## `Settings.is_rebindable_event`, which is where it is load-bearing.
static func _event_label(ev: InputEvent) -> String:
	return Settings.event_label(ev)


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
	Settings.set_v(Settings.S_LOOK, Settings.K_COLOURWAY, Outfitter.chosen_colourway)
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


## ═══════════════════════════════════════════════════════════ page switching
## Exactly one page is up at a time, and switching goes through here so a page added
## tomorrow cannot be left visible underneath another one — which is what happens the
## third time two booleans are flipped by hand in four places.
func _show_page(which: Control) -> void:
	_cancel_rebind()
	for page: Control in [_main_center, _settings_center, _controls_center]:
		if page != null:
			page.visible = page == which
	_fit_panels()


func _open_settings() -> void:
	_show_page(_settings_center)


func _close_settings() -> void:
	_show_page(_main_center)


func _open_controls() -> void:
	_refresh_bindings()
	_show_page(_controls_center)


# ══════════════════════════════════════════════════════════ sizing the cards
## Re-fit every page to the screen this actually is.
func _fit_panels() -> void:
	if not is_inside_tree():
		return
	var avail: Vector2 = get_viewport_rect().size
	_fit_one(_main_scroll, _main_col, avail)
	_fit_one(_settings_scroll, _settings_col, avail)
	_fit_one(_controls_scroll, _controls_col, avail)


## ⚠ THE RULE THAT WAS MISSING: `min(content, screen)`.
##
## A `ScrollContainer` inside a `CenterContainer` is handed its MINIMUM size, so the
## minimum IS the panel — the old hardcoded `Vector2(320, 520)` was a 520-px-tall panel
## on a 360-px-tall screen, and 160 px of it lived below the bottom edge at every scroll
## position. See the SCREEN_MARGIN block for the measured before-numbers.
##
## Taking the CONTENT height while it is short matters as much as clamping it when it is
## tall: a fixed height would top-align a four-row main menu inside a full-screen box
## instead of centring it, which is worse-looking than the bug being fixed.
##
## ⚠ AND THE SCROLLBAR EATS WIDTH. A `VScrollBar` appearing takes a slice off the right
## of the content area, so a card sized to exactly its content hides the last few pixels
## of every row under the bar the moment it starts scrolling.
func _fit_one(scroll: ScrollContainer, col: Control, avail: Vector2) -> void:
	if scroll == null or col == null:
		return
	var max_h: float = maxf(avail.y - SCREEN_MARGIN * 2.0 - PANEL_PAD * 2.0, 80.0)
	var max_w: float = minf(maxf(avail.x - SCREEN_MARGIN * 2.0 - PANEL_PAD * 2.0, 120.0),
		CARD_MAX_W)
	var content: Vector2 = col.get_combined_minimum_size()
	var bar: float = 0.0
	if content.y > max_h:
		var vbar: VScrollBar = scroll.get_v_scroll_bar()
		bar = 12.0 if vbar == null or vbar.size.x <= 0.0 else vbar.size.x
	scroll.custom_minimum_size = Vector2(
		clampf(content.x + bar, 0.0, max_w), minf(content.y, max_h))


# ══════════════════════════════════════════════════════════════════ the look
## ⚠ WHY THERE IS A STYLE PASS AT ALL. Every button and every slider in this menu was
## on the STOCK GODOT THEME — flat grey rectangles — sitting next to a pause button
## three hundred lines above that this file had already hand-styled with a 15px radius
## and a 2px border, and directly on top of a game drawn in chalk on near-black paper.
## Three visual languages on one screen. Maker: *"the game is really ugly and
## unpolished"*.
##
## ⚠ NOTHING NEW IS INVENTED HERE. Every colour comes from `HudStyle`, which is itself a
## consolidation of colours that already existed in the codebase, and the shapes match
## the pause button's existing treatment (rounded, bordered, a real pressed state).
func _style_button(b: Button, accent: Color = HudStyle.SKY) -> void:
	b.add_theme_font_size_override("font_size", HudStyle.BODY)
	b.add_theme_color_override("font_color", HudStyle.CHALK)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", HudStyle.PAPER)
	b.add_theme_color_override("font_focus_color", accent)
	b.add_theme_color_override("font_disabled_color", HudStyle.with_a(HudStyle.GRAPHITE, 0.5))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		match state:
			"pressed":
				# A tap you cannot see land feels broken — the same reasoning the pause
				# button's own PRESS state was built on.
				sb.bg_color = HudStyle.with_a(accent, 0.85)
				sb.border_color = accent
			"hover", "focus":
				sb.bg_color = HudStyle.with_a(accent, 0.16)
				sb.border_color = HudStyle.with_a(accent, 0.9)
			"disabled":
				sb.bg_color = HudStyle.with_a(HudStyle.PAPER, 0.5)
				sb.border_color = HudStyle.with_a(HudStyle.GRAPHITE, 0.25)
			_:
				sb.bg_color = HudStyle.with_a(HudStyle.TRACK, 0.92)
				sb.border_color = HudStyle.with_a(accent, 0.45)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)   # HudStyle.panel()'s radius: one corner, everywhere
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		b.add_theme_stylebox_override(state, sb)


## The track and the filled part of a slider. The grabber texture is left on the theme
## deliberately: overriding it means shipping an image, and the stock grabber reads
## correctly once the track behind it stops being a grey slab.
func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = HudStyle.TRACK
	track.border_color = HudStyle.with_a(HudStyle.SKY, 0.35)
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HudStyle.with_a(HudStyle.SKY, 0.55)
	fill.set_corner_radius_all(3)
	s.add_theme_stylebox_override("grabber_area", fill)
	var fill_hot := StyleBoxFlat.new()
	fill_hot.bg_color = HudStyle.with_a(HudStyle.AZURE, 0.85)
	fill_hot.set_corner_radius_all(3)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hot)


## A CheckButton keeps its stock on/off glyph — that shape is the affordance and
## redrawing it would be inventing art — but loses the grey slab behind the label.
func _style_check(c: CheckButton) -> void:
	c.add_theme_font_size_override("font_size", HudStyle.BODY)
	c.add_theme_color_override("font_color", HudStyle.CHALK)
	c.add_theme_color_override("font_hover_color", HudStyle.SKY)
	c.add_theme_color_override("font_pressed_color", HudStyle.SKY)
	for state: String in ["normal", "pressed", "hover", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = HudStyle.with_a(HudStyle.TRACK, 0.0 if state == "normal" else 0.7)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 4.0
		sb.content_margin_right = 4.0
		c.add_theme_stylebox_override(state, sb)


## The scrollbar is part of the card now that the card actually scrolls. Left stock it
## is a wide grey channel down the right of a chalk-on-paper panel.
func _style_scrollbar(scroll: ScrollContainer) -> void:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	if bar == null:
		return
	var channel := StyleBoxFlat.new()
	channel.bg_color = HudStyle.with_a(HudStyle.INK, 0.55)
	channel.set_corner_radius_all(3)
	channel.content_margin_left = 2.0
	channel.content_margin_right = 2.0
	bar.add_theme_stylebox_override("scroll", channel)
	bar.add_theme_stylebox_override("scroll_focus", channel)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var g := StyleBoxFlat.new()
		g.bg_color = HudStyle.with_a(HudStyle.SKY,
			0.45 if state == "grabber" else 0.85)
		g.set_corner_radius_all(3)
		bar.add_theme_stylebox_override(state, g)


# ══════════════════════════════════════════════════════════════════ row makers
## A captioned slider as ONE widget. It was five hand-written lines per knob, six knobs
## over, and the copies had already drifted (every slider was 240x20 except that the
## captions were plain `Label.new()` with no colour at all, so they rendered in the
## theme's default white against a menu written in chalk).
func _slider_row(caption: String, lo: float, hi: float, step: float, value: float,
		cb: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var l := Label.new()
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudStyle.label(l, HudStyle.SMALL, HudStyle.GRAPHITE)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(240, 16)
	s.value = value
	s.value_changed.connect(cb)
	_style_slider(s)
	box.add_child(s)
	return box


## The settings page's row shape. ⚠ EVERY row on that page uses it, including the ones
## that were left on `_menu_button`: a 220-px "Next Track" stacked between two 240-px
## rows is exactly the near-miss the eye reads as sloppiness without being able to name
## it, which is most of what the "ugly and unpolished" note is about.
func _settings_row_button(text: String, cb: Callable) -> Button:
	var b: Button = _menu_button(text, cb)
	b.custom_minimum_size = Vector2(240, 28)
	return b


## Standard sized menu button wired to a Callable.
func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 30)
	b.pressed.connect(cb)
	_style_button(b)
	return b


# ═════════════════════════════════════════════════ the controls / rebind page
## ⚠ THIS GAME HAD NO KEY REBINDING ANYWHERE, and the reason it was cheap to add is a
## decision made in Milestone 1 and never revisited: every input goes through a NAMED
## ACTION (D-011, the mobile-first rule — the touch pad fires the same actions), so the
## letters were always being read out of `InputMap` at display time. The old controls
## card already did that. It just could not be pressed.
##
## Every row here is DERIVED FROM `CONTROL_ROWS`, the table that already drove the
## printed card, so the two can never disagree about which verbs exist. An action the
## map does not carry is dropped rather than shown blank — exactly as `controls_text`
## drops it, and for the same reason.
static func rebindable_rows() -> Array:
	var out: Array = []
	for row: Array in CONTROL_ROWS:
		for entry: Array in row:
			var actions: Array = entry[1] as Array
			for a: String in actions:
				if not InputMap.has_action(StringName(a)):
					continue
				var label: String = String(entry[0])
				# An entry naming several actions ("Move" -> move_left + move_right)
				# needs one ROW each, and they cannot all be called "Move".
				if actions.size() > 1:
					label = "%s  %s" % [label, _row_suffix(a)]
				out.append([StringName(a), label])
	if InputMap.has_action(&"ui_cancel"):
		out.append([&"ui_cancel", "Pause"])
	return out


## `move_left` -> "Left", `spell_1` -> "1". The part after the last underscore, which
## is the only part that distinguishes two rows sharing an entry label.
static func _row_suffix(action: String) -> String:
	var parts: PackedStringArray = action.split("_")
	return parts[parts.size() - 1].capitalize() if parts.size() > 0 else action


func _build_controls() -> void:
	var page: Array = _build_page("CONTROLS", HudStyle.BODY)
	_controls_center = page[0] as CenterContainer
	_controls_scroll = page[1] as ScrollContainer
	_controls_col = page[2] as VBoxContainer
	_controls_col.add_theme_constant_override("separation", 2)
	_controls_center.visible = false
	_rebind_note = Label.new()
	_rebind_note.text = REBIND_HINT
	_rebind_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rebind_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rebind_note.custom_minimum_size = Vector2(240, 0)
	HudStyle.label(_rebind_note, HudStyle.SMALL, HudStyle.GRAPHITE)
	_controls_col.add_child(_rebind_note)
	for row: Array in rebindable_rows():
		_controls_col.add_child(_binding_row(row[0] as StringName, String(row[1])))
	_controls_col.add_child(_settings_row_button("Reset to Defaults", _reset_bindings))
	_controls_col.add_child(_settings_row_button("Back", _open_settings))


## One row: what the verb is called, and a button carrying the key it answers to.
##
## ⚠ `clip_text` ON BOTH HALVES. This is the fault that put the old card 337 px wide
## into a 320-px panel: a `Label` with no autowrap and no clip does not shrink, it
## pushes its container out. A row that cannot be honest about its width should at
## least not silently resize the card around it.
func _binding_row(action: StringName, label: String) -> Control:
	var line := HBoxContainer.new()
	line.custom_minimum_size = Vector2(240, 0)
	line.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.clip_text = true
	HudStyle.label(l, HudStyle.SMALL, HudStyle.GRAPHITE)
	line.add_child(l)
	var cap: Button = _menu_button(Settings.binding_label(action),
		_begin_rebind.bind(action))
	# ⚠ `.bind`, NOT A LAMBDA. A GDScript lambda captures by VALUE at creation, and a
	# loop variable captured that way is a class of bug this repo has already paid for.
	cap.custom_minimum_size = Vector2(96, 24)
	cap.clip_text = true
	line.add_child(cap)
	_rebind_caps[action] = cap
	return line


func _begin_rebind(action: StringName) -> void:
	_cancel_rebind()
	_rebinding = action
	var cap: Button = _rebind_caps.get(action) as Button
	if is_instance_valid(cap):
		cap.text = REBIND_PROMPT
	if _rebind_note != null:
		_rebind_note.text = "press a key or a mouse button   ·   Esc cancels"


func _cancel_rebind() -> void:
	if _rebinding == &"":
		return
	_rebinding = &""
	_refresh_bindings()


## Repaint every cap from the LIVE map rather than from anything remembered here. The
## director, a reset, and a rebind all move the same map, and a cached label is how a
## settings screen ends up lying about the game it is a settings screen for.
func _refresh_bindings() -> void:
	for action: StringName in _rebind_caps:
		var cap: Button = _rebind_caps[action] as Button
		if is_instance_valid(cap):
			cap.text = Settings.binding_label(action)
	if _rebind_note != null:
		_rebind_note.text = REBIND_HINT


func _reset_bindings() -> void:
	Settings.reset_all_bindings()
	Settings.flush()      # a reset is one deliberate press, not a drag: write it now
	_rebinding = &""
	_refresh_bindings()


## ⚠ `_input`, NOT `_unhandled_input`, AND ONLY WHILE CAPTURING. The whole job is to
## take the key BEFORE anything else acts on it — pressing `F` to rebind Melee must not
## also swing, and pressing `1` must not also cast. Outside a capture this returns on
## its first line, so nothing about normal input handling moves.
##
## ⚠ ESC IS SPENT ON CANCEL and therefore cannot be assigned to anything. That is the
## universal convention and the alternative is a picker with no way out on a keyboard.
## Pause keeps its shipped Esc binding; it just cannot be moved BACK onto Esc once moved.
##
## ⚠ A PAD EVENT IS REFUSED SILENTLY. `Input.is_action_pressed` aggregates every device,
## so a joypad button on an action would drive player one whenever player two pressed
## it — see the note on `Settings.is_rebindable_event`. The capture simply keeps
## waiting, which is the right feedback: the button did nothing because it cannot.
func _input(event: InputEvent) -> void:
	if _rebinding == &"":
		return
	var captured: InputEvent = null
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		get_viewport().set_input_as_handled()
		if k.physical_keycode == KEY_ESCAPE or k.keycode == KEY_ESCAPE:
			_cancel_rebind()
			return
		captured = k
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		get_viewport().set_input_as_handled()
		captured = mb
	else:
		return
	if captured == null or not Settings.is_rebindable_event(captured):
		return
	var action: StringName = _rebinding
	_rebinding = &""
	if not Settings.rebind(action, captured):
		_refresh_bindings()
		return
	_refresh_bindings()
	# ⚠ A CLASH IS REPORTED, NOT REFUSED. `jump` and `move_up` share W in the SHIPPED
	# map, so a rule that forbade collisions would forbid the defaults. The player sees
	# the same cap appear on two rows and is told which ones.
	var clash: Array[StringName] = Settings.actions_bound_to(captured, action)
	if not clash.is_empty() and _rebind_note != null:
		var names: PackedStringArray = []
		for other: StringName in clash:
			names.append(String(other))
		_rebind_note.text = "%s is also: %s" % [Settings.event_label(captured),
			", ".join(names)]


# --------------------------------------------------------------- resume on Esc
## PauseMenu is PROCESS_MODE_ALWAYS, so it keeps getting input while the tree is
## paused — that's how Esc closes the menu even though the (pausable) host can't
## process input while paused. Only acts while the menu is open.
##
## ⚠ ON THE CONTROLS PAGE ESC GOES BACK ONE PAGE INSTEAD OF RESUMING. Esc is already
## the cancel key for a capture on that page, so having the same key ALSO quit the menu
## from the same screen is the kind of near-miss that reads as a bug. Everywhere else
## the shipped behaviour is untouched: Esc resumes.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _controls_center != null and _controls_center.visible:
			_open_settings()
			return
		resume_requested.emit()


# ------------------------------------------------------------------ audio (master bus)
func _master_bus() -> int:
	return AudioServer.get_bus_index("Master")


func _music_bus() -> int:
	return AudioServer.get_bus_index("Music")


func _current_music_linear() -> float:
	return Settings.bus_linear("Music")


## ⚠ EVERY SETTING WRITER IN THIS FILE NOW HAS THE SAME TWO LINES: apply it live, then
## record it. Before this, the ONLY setting in the whole project that survived closing
## the game was fullscreen — volume, music, camera zoom, screenshake, hit-stop, aim
## assist, friendly fire, graphics quality, brightness and colourway all reset on every
## launch, because each was written straight into whatever owned it at runtime
## (`AudioServer`, a `res://` Resource `Tuning.gd` only ever LOADS, `GameState` fields
## outside the save payload, metadata on the SceneTree root, two class statics).
##
## `Settings.set_v` does NOT touch the disk — `HSlider` emits on every pixel of a drag
## and that would be ~60 file writes a second. It marks dirty; `Screen` flushes once the
## value has been still for `Settings.FLUSH_DELAY_MSEC`, and immediately on quit or on
## the app being backgrounded.
func _on_music_volume_changed(v: float) -> void:
	Settings.set_bus_linear("Music", v)
	Settings.set_v(Settings.S_AUDIO, Settings.K_MUSIC, v)


func _current_master_linear() -> float:
	return Settings.bus_linear("Master")


func _on_volume_changed(v: float) -> void:
	# A linear 0 slider = silence; otherwise map to dB. See `Settings.set_bus_linear`.
	Settings.set_bus_linear("Master", v)
	Settings.set_v(Settings.S_AUDIO, Settings.K_MASTER, v)


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
##
## ⚠ `GameState` IS ALSO WRITTEN DIRECTLY, and that is a fix rather than belt-and-braces.
## The comment above was true and insufficient: it is the CAMERA that writes
## `GameState.camera_zoom`, so a zoom set from a screen with no combat camera on it —
## the lobby, the antechamber, a run summary — moved nothing and was forgotten before
## the next frame. The camera write is idempotent, so both paths agree.
func _on_zoom_changed(v: float) -> void:
	for cam: Node in get_tree().get_nodes_in_group("combat_camera"):
		if cam.has_method("set_base_zoom"):
			cam.call("set_base_zoom", v)
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("camera_zoom", v)
	Settings.set_v(Settings.S_CAMERA, Settings.K_ZOOM, v)


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
	Settings.set_v(Settings.S_FEEL, Settings.K_SHAKE, v)


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
	Settings.set_v(Settings.S_FEEL, Settings.K_AIM_ASSIST, v)


# ------------------------------------------------------------- friendly fire
## ⚠ WRITES `FriendlyFire.set_enabled`, WHICH WRITES `SpellCaster.friendly_fire` —
## the one static the whole mechanic hangs off. It is NOT mirrored into a local bool
## here: the director's VIEW tab toggles the same static, and two mirrors of one
## switch is how a player ends up turning friendly fire "off" and still deleting
## their friend.
func _on_friendly_fire_toggled(on: bool) -> void:
	FriendlyFire.set_enabled(on)
	Settings.set_v(Settings.S_GAME, Settings.K_FRIENDLY_FIRE, on)
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
## The window mode lives on the `Screen` autoload, which also persists it — see that
## file for why it is the only setting in the project that survives a restart.
func _fullscreen_label() -> String:
	var scr: Node = get_node_or_null(^"/root/Screen")
	var on: bool = scr != null and bool(scr.call("is_fullscreen"))
	return "Fullscreen:  %s   (F11)" % ("ON" if on else "OFF")


func _on_fullscreen_pressed() -> void:
	var scr: Node = get_node_or_null(^"/root/Screen")
	if scr == null:
		return
	scr.call("toggle")
	if _fullscreen_btn != null and is_instance_valid(_fullscreen_btn):
		_fullscreen_btn.text = _fullscreen_label()


func _on_quality_pressed() -> void:
	var cfg: Object = _tuning_cfg()
	if cfg == null:
		return
	var v: Variant = cfg.get("graphics_quality")
	var cur: int = TuningConfig.Quality.AUTO if v == null else int(v)
	var next: int = (cur + 1) % 3
	cfg.set("graphics_quality", next)
	Settings.set_v(Settings.S_VIDEO, Settings.K_QUALITY, next)
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
	Settings.set_v(Settings.S_FEEL, Settings.K_HIT_STOP, on)


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
	var next: int = 1 - int(gs.get("pvp_rules"))
	gs.set("pvp_rules", next)
	Settings.set_v(Settings.S_GAME, Settings.K_PVP_RULES, next)
	if _pvp_btn != null:
		_pvp_btn.text = _pvp_label()


func _pvp_label() -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	var cur: int = 0 if gs == null else int(gs.get("pvp_rules"))
	# Named for what the player SEES happen, not the internal flag: "stocks" is the
	# word for the mode where you are knocked off the stage and lose a life.
	return "PvP: Health" if cur == 0 else "PvP: Stocks + %"
