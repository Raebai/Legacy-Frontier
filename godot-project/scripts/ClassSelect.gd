extends CanvasLayer
## Hub Class-Select panel (autoload "ClassSelect"). A modal 8-card grid opened by
## the Class Altar in the hub; tap a card to pick your class (writes
## GameState.selected_class), which retints the hub player + updates the class HUD
## label, then closes. Built in code (house style, no .tscn) like PauseMenu.
##
## Scene-safe: only the hub Altar ever open()s it; the selection feedback no-ops
## when the player / label groups are absent (i.e. in the arena). Referenced
## elsewhere via /root/ClassSelect so headless tests never need the autoload.

## == THE ROSTER RAIL, AND THE TWO LAYOUTS IT BEAT ============================
## Maker: *"revamp how the class selection looks. Research the popular simple
## non-confusing ways of showing classes"*. There is no browser here, so nothing was
## surveyed -- the shape was reasoned from what this screen is for and from four
## measurements, and the constraints did most of the work.
##
## WHAT IT IS NOW: a **master-detail roster** -- a fixed rail of all nine classes down
## the left, and a detail column on the right showing the class you are CURRENTLY in:
## its fantasy line and the four spells it actually casts, each with one sentence
## saying what that spell does. Tap a rail row to become that class (one tap, as
## before); the detail follows the pad cursor in pad mode.
##
## WHY MASTER-DETAIL:
##   * 640x360 is a LANDSCAPE STRIP, and `stretch/aspect="expand"` means a taller phone
##     gets a WIDER logical viewport (a 20:9 handset reads 800x360), never a shorter
##     one. So HEIGHT is the fixed, scarce axis and WIDTH is the one that only grows.
##     A layout that spends width and leaves height alone cannot be broken by a device.
##   * Nine rows at `ROW_H` 30 px is 278 px of rail -- the whole roster on screen with
##     NO scrolling. Nothing a player must choose between is hidden behind a gesture.
##   * The detail column is where the spell descriptions finally have somewhere to
##     live, which is the other half of the same ask.
##
## REJECTED 1 -- THE 3x3 GRID THIS REPLACES. Nine 124x58 cards carrying the name and
## nothing else. Measured: 388 x 226, so it left ~250 px of width and ~130 px of height
## empty on the base viewport and MORE of both on a 20:9 phone, while answering only
## "what are they called". The grid was not too big; it was too empty to be worth a
## screen. It also forced `_move_cursor` to reason about a short last row.
##
## REJECTED 2 -- A CAROUSEL (one big class card, arrows either side). It is the layout
## that shows a class best, and it is the layout that COMPARES classes worst: nine
## classes means up to eight swipes to see the eighth, and the thing a player is doing
## here is comparing. It also needs two more tap targets (the arrows) on a screen the
## standing rule says to cut, and at `MIN_TAP` those arrows eat 60 px of the width the
## detail column wants.
##
## == ONE TAP STILL COMMITS, AND THAT IS A CONTRACT ===========================
## A rail row `pressed` PICKS the class and closes, exactly as the old cards did.
## Tap-to-preview / tap-again-to-confirm was drafted and dropped: `tools/slice_test_town.gd`
## drives the merge by emitting `pressed` on one card and asserting the screen closes and
## the Outfitter re-aims, so a two-tap confirm would silently break the merge test in a
## file this agent does not own. It is also the better screen -- the preview a two-tap
## flow would buy already exists one step later, on the Outfitter this returns to, which
## shows the new class's four roles WITH their blurbs and is one tap to change again.
## ══ WHO ASKED, AND WHO NEEDS TELLING ════════════════════════════════════════
## Emitted when the HUB path picks a class — i.e. from `_on_card_pressed`, after
## `GameState.selected_class` is written and before this screen closes. NOT emitted in
## pad mode, where `_confirm_cursor` is the confirm and `_pad_pick` is the one thing
## allowed to apply the choice (see the three rules in the pad-mode block below).
##
## ⚠ IT EXISTS BECAUSE THE CLASS PAD AND THE SPELL PAD MERGED. `Outfitter` now opens
## this screen from its own header button and has to re-aim itself at whatever comes
## back. A signal rather than the Outfitter polling `selected_class` every frame, and
## rather than this file reaching into the `town_overlay` group to find a screen it
## should not know exists: the chooser announces, the caller decides what that means.
signal class_picked(index: int)

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const SpellBlurbs := preload("res://scripts/combat/SpellBlurbs.gd")

## ONE COLUMN. Kept as a constant rather than inlined as `1` because `_move_cursor`
## still reasons in rows/columns and a future two-column rail should be one edit here,
## not a rewrite of the cursor walk.
const GRID_COLUMNS: int = 1

## The rail. `ROW_H` is the thumb floor (`Outfitter.MIN_TAP`, `slice_test_shell`'s
## floor, and the number `tools/slice_test_class_select_layout.gd` asserts against);
## `RAIL_W` is wide enough for "Cryomancer  · guarded" at font 13 without clipping.
const RAIL_W: float = 152.0
const ROW_H: float = 30.0
## The detail column. 300 px is what is left of the 640 base viewport once the rail,
## the gap and the panel's own margins are taken -- with ~170 px of slack, which is
## where the wider logical viewport of a tall phone goes.
const DETAIL_W: float = 300.0
const GAP: float = 6.0

## Appended to a locked row. Says WHERE the class is, not merely that it is gone —
## the difference between a goal and a smaller game. Two words instead of five.
##
## ⚠ IT IS A MIDDLE DOT NOW, NOT A NEWLINE. A newline was fine on a 58 px card and is
## not fine in a 30 px row: the second line is simply not drawn, so three of the nine
## rows would have said nothing about being locked at all.
const LOCK_SUFFIX: String = "  · guarded"
const HIGHLIGHT: Color = Color(0.55, 0.9, 1.0)

## The leading block on a rail row, drawn in the class colour by the row's own
## `font_color`. A glyph rather than a `ColorRect` child so the row stays ONE Button:
## `tools/slice_test_town.gd` walks this screen for Buttons and indexes the result BY
## CLASS, so any extra Button anywhere before the rail would renumber the roster under
## a test in a file this agent does not own.
const SWATCH: String = "█"

## ══ PLAYER TWO PICKS THEIR OWN CLASS, WITH A PAD AND NOTHING ELSE ═══════════════
## The standing known gap in same-screen co-op: a joining pad inherited player one's
## class and the only way out was `switch_class` (BACK), which CYCLES — nine presses
## to reach the ninth class, rebuilding the body on each, with nothing naming what you
## were about to become. This screen already IS the class pick; it simply could not be
## reached or driven without a mouse and a keyboard.
##
## ⚠ THREE THINGS ARE DIFFERENT IN PAD MODE, AND EACH IS A BUG IF IT IS NOT.
##   1. IT WRITES `GameState.set_local_class(device, i)`, NEVER `selected_class`.
##      That global is player ONE's class and is written by six other paths; parking
##      player two's pick there is the leak `slice_test_local_coop` exists to catch.
##   2. `_apply_feedback` IS NOT CALLED. It re-configures the whole "player" group and
##      retints the hub body — i.e. it would turn player one into player two's class.
##      The caller (`LocalCoop._on_class_picked`) re-configures exactly one body.
##   3. THE FULL-SCREEN DIMMER IS OFF. Player one is still fighting: dimming their
##      half of the screen because their friend opened a menu is not a modal, it is a
##      penalty. The panel is a panel; the fight keeps running behind it, unpaused,
##      and only the chooser's own pad is taken out of the hero's hands
##      (`PadController.suspended`).
##
## Solo is byte-identical: `_physics_process` is OFF unless a pad opened this, and every hub
## path below is untouched.
##
## Navigation is the LEFT STICK + A/B, which are the buttons a joining pad already
## used to get here. Deliberately NOT the d-pad: that is four spell slots.
const PAD_REPEAT_FIRST: float = 0.34    ## hold delay before the cursor auto-repeats
const PAD_REPEAT_RATE: float = 0.13     ## and how fast it walks after that
## What the cursor sits on. Brighter than `HIGHLIGHT` (which marks the CURRENT class)
## so "where I am" and "what I am" never read as the same thing.
const PAD_CURSOR: Color = Color(1.0, 0.95, 0.6)
## How far a guarded row is faded. It is a whole-row alpha rather than a greyed font
## because the class COLOUR is the only thing distinguishing nine rows of text, and a
## locked class you cannot recognise is not a goal.
const LOCKED_DIM: float = 0.45

var _cards: Array[Button] = []
## Per-row unlock state, kept because the row TINT has one writer now and it needs
## to know. See `_paint_cursor`.
var _unlocked: Array[bool] = []
## The right-hand column: who you currently are, and the four spells you cast.
## Rebuilt wholesale by `_refresh_detail` rather than diffed -- nine classes x five
## labels is nothing, and a diff is where a stale label survives a class change.
var _detail: VBoxContainer = null
## Which class the detail column is currently drawn for. `-1` forces the first draw.
var _detail_for: int = -1
var _detail_name: Label = null
var _detail_fantasy: Label = null
var _detail_names: Array[Label] = []
var _detail_blurbs: Array[Label] = []
var _detail_reserve: Label = null
var _panel: PanelContainer = null
var _dim: ColorRect = null

## --- pad mode state. `_pad_device < 0` means every line of it is dead. ---
var _pad_device: int = -1
var _pad: PadController = null
var _pad_pick: Callable = Callable()
var _cursor: int = 0
var _repeat_left: float = 0.0
var _held_dir: Vector2i = Vector2i.ZERO
var _title: Label = null
## ⚠ THE PHYSICS FRAME THIS OPENED ON, AND IT IS NOT BOOKKEEPING — IT IS THE FIX FOR A
## SCREEN THAT OPENED AND SHUT IN THE SAME BREATH.
##
## BACK opens the chooser and BACK also backs out of it, and `PadController` holds a
## press EDGE for the whole physics frame it lands on. So `LocalCoop` saw the edge and
## opened this, and then this file's own tick — running later in that same frame,
## against that same live edge — read it as "back out" and closed again. Measured in the
## real arena: `BACK -> chooser open = false`, with no error anywhere, because both
## halves did exactly what they were told.
##
## An edge that opened a screen must not also act INSIDE it. Nothing is read until the
## frame turns over.
var _opened_frame: int = -1


func _ready() -> void:
	layer = 90
	visible = false
	set_physics_process(false)   # pad mode is the only thing that needs a tick
	var dim := ColorRect.new()
	_dim = dim
	dim.color = Color(0.03, 0.03, 0.06, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # eat taps behind the panel
	dim.gui_input.connect(_on_dim_input)          # tap-outside dismisses
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var vbox := VBoxContainer.new()
	# 4, not the old 10. The screen is a rail and a column now rather than three loose
	# blocks, and a 10 px gutter between the title and a 278 px rail is the difference
	# between fitting 360 px with room and fitting it by luck.
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)
	var title := Label.new()
	_title = title
	title.text = "CHOOSE YOUR CLASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Was 20. `HudStyle.BODY` is the size this game gives a menu row, and the title of a
	# screen that is already unmistakably a class list does not need to be the loudest
	# thing on it -- the 6 px it gives back go to the rail.
	HudStyle.label(title, HudStyle.BODY, HudStyle.CHALK)
	vbox.add_child(title)

	# THE TWO COLUMNS. The rail is fixed-width; the detail column is fixed-width; the
	# HBox is therefore fixed-width, which is what lets a probe assert a rect instead
	# of hoping about one.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(GAP))
	vbox.add_child(body)

	var rail := VBoxContainer.new()
	rail.custom_minimum_size = Vector2(RAIL_W, 0)
	# 0, not the grid's 8. Nine rows at 8 px of gutter is 64 px of nothing -- a fifth of
	# the height budget spent on gaps, on the one axis a phone cannot give more of. The
	# rows are told apart by the colour block at the head of each, and by the cursor /
	# highlight tint, neither of which needs a gap to read. MEASURED: at 1 px of
	# separation the panel came to 349 px against the 360 ceiling; at 0 it is 341, and
	# `tools/slice_test_class_select_layout.gd` prints the number on every run.
	rail.add_theme_constant_override("separation", 0)
	body.add_child(rail)
	_build_cards(rail)

	_detail = VBoxContainer.new()
	_detail.custom_minimum_size = Vector2(DETAIL_W, 0)
	_detail.add_theme_constant_override("separation", 2)
	body.add_child(_detail)
	_build_detail()
	# The hint line is still gone. It read "tap a class - Esc / tap-away to cancel", an
	# instruction for tapping a list of nine buttons, which is the one interaction on
	# earth nobody needs told. Both routes it described still work.


## The rail: one row per class, the whole roster visible with no scrolling.
##
## The row carries the NAME and a leading block in the class's own colour -- the same
## `ClassInfo.color_for` the hero rig is tinted with, so the row and the body you walk
## away in match. It is deliberately not an icon: there are no class icons in this
## project, and a screen that needs nine new pieces of art to read is a screen that
## does not ship.
func _build_cards(rail: VBoxContainer) -> void:
	for i: int in ClassInfo.count():
		var info: Dictionary = ClassInfo.CLASSES[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(RAIL_W, ROW_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# clip, not wrap. A wrapped row grows and nine grown rows walk the panel off a
		# phone; a clipped one loses a character and the layout survives. Nothing here
		# is long enough to clip at RAIL_W, which the layout probe measures rather than
		# assumes.
		b.clip_text = true
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.text = "%s  %s" % [SWATCH, String(info["name"])]
		b.add_theme_color_override("font_color", (info["color"] as Color).lightened(0.25))
		# ⚠ NO FOCUS, ON PURPOSE, AND IT IS WHAT MAKES UP/DOWN WORK AT ALL. Godot walks
		# focus between Buttons itself on `ui_up`/`ui_down` and CONSUMES those actions
		# before `_unhandled_input` ever sees them — so a focused rail and this file's
		# own cursor would be two cursors fighting over one keypress. Worse, the built-in
		# walk SKIPS DISABLED CONTROLS, which is exactly the three guarded classes the
		# roster deliberately shows so a player can want them: keyboard navigation would
		# have jumped straight over the only rows a preview is really for.
		# The cursor tint is the focus indicator now, and it is the same one the pad
		# already used.
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_card_pressed.bind(i))
		# HOVER PREVIEWS, CLICK COMMITS. A mouse crossing a row is free — it decides
		# nothing — so it moves the same cursor the keyboard moves rather than a second
		# one, and a disabled Button still reports the crossing.
		b.mouse_entered.connect(_on_row_hovered.bind(i))
		rail.add_child(b)
		_cards.append(b)
	_refresh_locks()


# ============================================================ THE DETAIL COLUMN
## Build the column ONCE with empty labels, then let `_refresh_detail` fill them.
##
## Built once and refilled rather than rebuilt per class, for the reason the Outfitter
## learned the hard way: a container whose children are freed and re-added re-measures
## between the remove and the free, and the panel visibly jumps a row. Fixed labels
## cannot do that, and it also means the panel's height is decided at build time by
## `SPELL_ROWS`, so a class that somehow answered with more spells cannot grow the
## screen off a phone.
##
## `SPELL_ROWS` is `SpellTier.SLOT_COUNT` -- the number of buttons the right thumb has,
## which is what "the spells you cast" means. Read, not typed: it was literally 3 in
## nine hand-written `ClassInfo.kit` strings when the hand became 4, and nothing
## noticed for months.
func _build_detail() -> void:
	var name_l := Label.new()
	name_l.clip_text = true
	HudStyle.label(name_l, HudStyle.LEAD, HudStyle.CHALK)
	_detail.add_child(name_l)
	_detail_name = name_l

	var fant := Label.new()
	fant.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fant.custom_minimum_size = Vector2(DETAIL_W, 0)
	HudStyle.label(fant, HudStyle.MICRO, HudStyle.GRAPHITE)
	_detail.add_child(fant)
	_detail_fantasy = fant

	# A hairline between "who" and "what they cast". One pixel of rule does the job a
	# blank row would take eleven pixels to do.
	var rule := ColorRect.new()
	rule.color = HudStyle.with_a(HudStyle.GRAPHITE, 0.35)
	rule.custom_minimum_size = Vector2(DETAIL_W, 1)
	_detail.add_child(rule)

	for n: int in SpellTier.SLOT_COUNT:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		_detail.add_child(row)
		var nm := Label.new()
		nm.clip_text = true
		HudStyle.label(nm, HudStyle.SMALL, HudStyle.CHIP)
		row.add_child(nm)
		var blurb := Label.new()
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# TWO LINES RESERVED, ALWAYS. `SpellBlurbs.MAX_LEN` is set so no entry needs a
		# third at this width, and a fixed reservation means the column measures the
		# same for every class -- so the layout probe's numbers are the shipped numbers
		# and not "whichever class happened to be selected when it ran".
		blurb.custom_minimum_size = Vector2(DETAIL_W, float(HudStyle.MICRO) * 2.0 + 4.0)
		blurb.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		HudStyle.label(blurb, HudStyle.MICRO, HudStyle.GRAPHITE)
		row.add_child(blurb)
		_detail_names.append(nm)
		_detail_blurbs.append(blurb)

	var reserve := Label.new()
	reserve.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reserve.custom_minimum_size = Vector2(DETAIL_W, 0)
	HudStyle.label(reserve, HudStyle.MICRO, HudStyle.with_a(HudStyle.GRAPHITE, 0.75))
	_detail.add_child(reserve)
	_detail_reserve = reserve


## Point the detail column at a class.
##
## \u26a0 EVERY SPELL NAMED HERE IS ONE THE CLASS IS ACTUALLY HOLDING, because it comes
## from `ClassInfo.carried_spells` -> `SpellLibrary.build_for_class` -- the same call
## `Hero._configure_class` makes to build the hand. This is the whole reason the
## screen was rebuilt rather than restyled: the string it used to be able to show
## (`ClassInfo.CLASSES[i]["kit"]`) has drifted from the real kit TWICE, once
## advertising three beams nobody carried and once, measured during this pass, naming
## only three of four spells on all nine classes. A screen that derives cannot drift.
func _refresh_detail(index: int) -> void:
	if _detail == null or _detail_name == null:
		return
	var i: int = clampi(index, 0, maxi(ClassInfo.count() - 1, 0))
	_detail_for = i
	var col: Color = ClassInfo.color_for(i)
	_detail_name.text = ClassInfo.name_for(i).to_upper()
	_detail_name.add_theme_color_override("font_color", col.lightened(0.35))
	_detail_fantasy.text = ClassInfo.fantasy_for(i)
	var spells: Array = ClassInfo.carried_spells(i)
	for n: int in _detail_names.size():
		var nm: Label = _detail_names[n]
		var bl: Label = _detail_blurbs[n]
		if n >= spells.size():
			# An honest hole. A class that answered with fewer spells than the thumb has
			# buttons is a real bug somewhere else, and blanking the row shows it rather
			# than leaving the PREVIOUS class's spell sitting there reading as this one's.
			nm.text = ""
			bl.text = ""
			continue
		var spell: SpellDef = spells[n] as SpellDef
		var last: bool = n == spells.size() - 1
		# The number is the HOTBAR KEY, so the list reads in the order the thumb will
		# meet it. The last slot is the ult slot by `SpellLibrary.SLOT_ROLES`.
		nm.text = "%d  %s%s" % [n + 1, String(spell.display_name), "   ULT" if last else ""]
		nm.add_theme_color_override("font_color", HudStyle.GOLD if last else HudStyle.CHIP)
		bl.text = SpellBlurbs.for_spell(spell)
	# The fifth authored role -- the one this hand does NOT start with. Named as a
	# place to go rather than as a fact, because the Outfitter is one tap away and is
	# where it gets swapped in.
	var reserve: Array = SpellLibrary.reserve_for_class(i)
	if _detail_reserve != null:
		if reserve.is_empty():
			_detail_reserve.text = ""
		else:
			var held: SpellDef = reserve[0] as SpellDef
			_detail_reserve.text = "+ %s in reserve \u2014 swap it in at the Outfitter" % (
				String(held.display_name) if held != null else "one more spell")


## ⚠ LOCKED CLASSES ARE SHOWN, NOT HIDDEN. Three of the nine are withheld until a
## guardian is felled (`Progression.LOCKED_CLASSES`), and the difference between a
## card that says "a guardian holds this" and a card that is simply absent is the
## difference between a goal and a smaller game. A player has to be able to WANT the
## thing before they can be rewarded with it.
##
## Re-read on every `open()` rather than only at build time, because a class can be
## earned between two visits to the altar — and a stale card would go on refusing a
## class the save already says is unlocked.
func _refresh_locks() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var owned: Array = [] if gs == null else (gs.get("unlocked_classes") as Array)
	_unlocked.resize(_cards.size())
	for i: int in _cards.size():
		var unlocked: bool = Progression.is_class_unlocked(i, owned)
		var b: Button = _cards[i]
		b.disabled = not unlocked
		# ⚠ THE DIM MOVED OUT OF HERE, AND IT WAS NEVER VISIBLE FROM HERE. This line used
		# to be `b.modulate.a = 1.0 if unlocked else 0.45` — and `open()` calls
		# `_refresh_locks()` and THEN a painter that assigns a whole `modulate`, alpha
		# included. So the guarded rows were written at 0.45 and immediately overwritten
		# back to 1.0, every single time the altar opened: three of the nine classes were
		# advertised as available and only the `· guarded` suffix said otherwise. Two
		# writers for one property, and the loser was the one that carried the meaning.
		_unlocked[i] = unlocked
		# Idempotent: `open()` re-runs this, and appending unconditionally would grow
		# the label a little more every single time the altar is used.
		var has_suffix: bool = b.text.ends_with(LOCK_SUFFIX)
		if not unlocked and not has_suffix:
			b.text += LOCK_SUFFIX
		elif unlocked and has_suffix:
			b.text = b.text.substr(0, b.text.length() - LOCK_SUFFIX.length())


func is_open() -> bool:
	return visible


func open() -> void:
	# The hub altar. Clears any pad mode first so the two can never be half-open at
	# once — a chooser showing "PLAYER 2" and writing `selected_class` is the worst of
	# both, and it is exactly what a stale field would produce.
	_end_pad_mode()
	_title.text = "CHOOSE YOUR CLASS"
	if _dim != null:
		_dim.visible = true
	_refresh_locks()
	# THE CURSOR STARTS ON THE CLASS YOU ARE. So the first thing the column shows is
	# still a readout of yourself — the screen has not stopped being that — and one
	# press of DOWN is already a preview of the next class rather than a jump to the
	# top of a list you were not looking at.
	_cursor = clampi(_selected_class(), 0, maxi(_cards.size() - 1, 0))
	_paint_cursor()
	visible = true


func close() -> void:
	_end_pad_mode()
	visible = false


# ═════════════════════════════════════════════════════ PAD MODE (player two)
## Open the chooser for ONE local player, driven entirely by their pad.
##
## `on_pick` is called as `on_pick(device, index)` and is the ONLY thing that applies
## the choice — this screen deliberately does not know how to dress a body or which
## body is theirs. `LocalCoop._on_class_picked` does both.
## `seat` is which player they are on the couch (2, 3, 4) — NOT the device id. The first
## version put `device + 2` in the title, which reads "PLAYER 5" for anybody whose pad
## happens to enumerate as joypad 3. A device id is a hardware detail and must never
## reach a player's eyes.
func open_for_pad(device: int, pad: PadController, on_pick: Callable, seat: int = 2) -> void:
	if pad == null:
		return
	if visible and _pad_device != device:
		# Two people opening their choosers at once would share one panel and one
		# cursor. First one keeps it; the second press is simply ignored, which is
		# better than the alternative of stealing the panel out from under them.
		return
	_pad_device = device
	# ⚠ THE HERO'S OWN PAD, HANDED OVER, NOT A SECOND ONE BUILT HERE. There is one pad
	# in the player's hands; building a second `PadController` for the same device was
	# the first shape of this and it is untestable by construction — a probe's fake pad
	# cannot be behind an object this file constructs for itself. `LocalCoop` suspends
	# the HERO's side of this same object while the chooser is up, and the chooser reads
	# through the suspend with `menu_*`. See `PadController.suspended`.
	_pad = pad
	_pad_pick = on_pick
	_held_dir = Vector2i.ZERO
	_repeat_left = 0.0
	if _dim != null:
		_dim.visible = false     # player one is still fighting behind this
	if _title != null:
		_title.text = "PLAYER %d — CHOOSE YOUR CLASS" % maxi(seat, 2)
	_refresh_locks()
	var start: int = _local_class_of(device)
	_cursor = start if start >= 0 and start < _cards.size() else 0
	_paint_cursor()   # also draws the detail column for the class under the cursor
	visible = true
	_opened_frame = Engine.get_physics_frames()
	set_physics_process(true)


## Is the chooser currently up for THIS device? `LocalCoop` polls it to know when the
## pad belongs to the hero again — one owner of that answer rather than two.
func is_open_for(device: int) -> bool:
	return visible and _pad_device == device


func close_for(device: int) -> void:
	if _pad_device == device:
		close()


func _end_pad_mode() -> void:
	if _pad_device < 0:
		return
	_pad_device = -1
	_pad = null
	_pad_pick = Callable()
	set_physics_process(false)
	if _dim != null:
		_dim.visible = true
	if _title != null:
		_title.text = "CHOOSE YOUR CLASS"
	_refresh_highlight()   # drop the cursor tint, leave the hub's own highlight


func _local_class_of(device: int) -> int:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("local_class_of"):
		return -1
	var v: int = int(gs.call("local_class_of", device))
	# -1 is "inherit player one", which as a STARTING CURSOR means "start on the class
	# you are actually standing in" rather than on card zero.
	return _selected_class() if v < 0 else v


## ⚠ PHYSICS, NOT IDLE, FOR THE SAME REASON `LocalCoop._physics_process` is. Confirm
## and back-out are EDGES, and a `PadController` edge lives for exactly one physics
## frame — while Godot may run up to eight physics steps inside one slow idle frame, in
## which case an idle-frame read of an edge finds it already rolled past. That failure
## is silent and frame-rate dependent: it works on an empty floor and stops working in
## the fight where somebody actually wants to change class.
func _physics_process(delta: float) -> void:
	if _pad == null or not visible:
		return
	# See `_opened_frame`: the press that opened this is still live, and reading it here
	# closes the screen on the frame it appeared.
	if Engine.get_physics_frames() == _opened_frame:
		return
	var dir := Vector2i(
		1 if _pad.menu_pressed(&"move_right") else (-1 if _pad.menu_pressed(&"move_left") else 0),
		1 if _pad.menu_pressed(&"move_down") else (-1 if _pad.menu_pressed(&"move_up") else 0))
	# ⚠ EDGE, THEN A REPEAT ON A CLOCK. A raw per-frame read walks the cursor across
	# nine cards in a sixth of a second — the grid is unusable and it looks broken
	# rather than fast. A pure edge is the other failure: holding the stick does
	# nothing and you press nine times. Both, then: the first push moves immediately,
	# and holding walks at `PAD_REPEAT_RATE`.
	if dir != _held_dir:
		_held_dir = dir
		_repeat_left = PAD_REPEAT_FIRST
		if dir != Vector2i.ZERO:
			_move_cursor(dir)
	elif dir != Vector2i.ZERO:
		_repeat_left -= delta
		if _repeat_left <= 0.0:
			_repeat_left = PAD_REPEAT_RATE
			_move_cursor(dir)
	# A confirms, B backs out. The same two buttons that got them into the game.
	# ⚠ `menu_just_pressed`, NOT `just_pressed` — the hero side of this pad is suspended
	# while the chooser is up, and the suspended side answers neutral to everything.
	if _pad.menu_just_pressed(&"jump"):
		_confirm_cursor()
	elif _pad.menu_just_pressed(&"dash") or _pad.menu_just_pressed(&"class_menu"):
		close()


## Walk the grid, clamped rather than wrapped. A wrapping cursor on a 3x3 grid means
## pushing right off the end of a row lands you on the far left of the SAME row, which
## reads as the stick having missed the input.
func _move_cursor(dir: Vector2i) -> void:
	var n: int = _cards.size()
	if n == 0:
		return
	var rows: int = int(ceil(float(n) / float(GRID_COLUMNS)))
	var col: int = _cursor % GRID_COLUMNS
	var row: int = _cursor / GRID_COLUMNS
	# ⚠ ON A ONE-COLUMN RAIL, SIDEWAYS ALSO WALKS THE LIST. With `GRID_COLUMNS == 1`
	# the `dir.x` clamp below can only ever be a no-op, so a push left or right would do
	# NOTHING -- and `tools/slice_test_local_coop.gd` drives exactly that
	# (`pad.axes[JOY_AXIS_LEFT_X] = 1.0`) and asserts the cursor moved. It is also the
	# right behaviour on its own terms: on a vertical list a sideways push is a thumb
	# that missed, and answering it by moving one step is more forgiving than answering
	# it with silence. Folded into `dir.y` rather than special-cased at the call site so
	# a future two-column rail gets the ordinary clamp back for free.
	var step_y: int = dir.y
	if GRID_COLUMNS <= 1 and dir.x != 0:
		step_y = dir.x
	col = clampi(col + dir.x, 0, GRID_COLUMNS - 1)
	row = clampi(row + step_y, 0, rows - 1)
	# The last row can be short (the roster moves, and the rail is one column deep).
	_cursor = clampi(row * GRID_COLUMNS + col, 0, n - 1)
	_paint_cursor()


## The cursor tint, drawn over the hub's "this is your class" highlight so both read,
## and THE ONLY WRITER OF `modulate` on a rail row.
##
## ⚠ THE DETAIL FOLLOWS THE CURSOR, NOT THE SELECTION — IN BOTH MODES NOW. The rule
## has always been that an input which COMMITS may not also preview, and the reverse:
## an input that commits nothing is free to. Pad mode had such an input (the stick)
## and hub mode was recorded here as having none, because the only hub input this
## screen took was a tap, and a tap picks.
##
## The maker supplied the missing input: *"in the class selection be able to press up
## and down and hover over the options so that you can see exactly whats within each
## one"*. Arrow keys and a hovering mouse commit nothing, so they preview, and they
## drive THE SAME cursor the stick drives rather than a second one — which is why
## this function stopped being pad-only rather than being copied.
##
## ONE TAP STILL COMMITS. The contract at the top of this file is untouched: moving
## the cursor never writes `selected_class`, and a row `pressed` still picks and
## closes on the first press.
func _paint_cursor() -> void:
	var sel: int = _local_class_of(_pad_device) if _pad_device >= 0 else _selected_class()
	for i: int in _cards.size():
		var tint: Color = Color.WHITE
		if i == _cursor:
			tint = PAD_CURSOR
		elif i == sel:
			tint = HIGHLIGHT
		# The guarded rows are dimmed HERE rather than in `_refresh_locks`, because this
		# assignment is what used to erase them. See the note there.
		tint.a = 1.0 if (i < _unlocked.size() and _unlocked[i]) else LOCKED_DIM
		_cards[i].modulate = tint
	_refresh_detail(_cursor)


## ⚠ NOT `_on_card_pressed`. That one writes `selected_class` and calls
## `_apply_feedback` — player ONE's class and player ONE's body. This is the whole
## reason pad mode is a separate confirm rather than a fake button press.
func _confirm_cursor() -> void:
	if _cursor < 0 or _cursor >= _cards.size():
		return
	var gs: Node = get_node_or_null("/root/GameState")
	# Locks are re-checked here for the same reason `_on_card_pressed` re-checks them:
	# `disabled` is a display state, and a cursor can be parked on a disabled card.
	# Player two does NOT get to spend player one's banked guardian pick — that is a
	# one-shot reward on a shared save, and spending it from a pad nobody chose to give
	# it to is not a decision anybody made.
	if gs != null and not Progression.is_class_unlocked(_cursor, gs.get("unlocked_classes") as Array):
		return
	var picked: int = _cursor
	if _pad_pick.is_valid():
		_pad_pick.call(_pad_device, picked)
	close()


## A mouse crossing a rail row. Hub mode only: in pad mode the cursor belongs to
## player two's stick, and a stray mouse on player one's desk must not move it.
func _on_row_hovered(index: int) -> void:
	if _pad_device >= 0 or not visible:
		return
	if index == _cursor:
		return
	_cursor = index
	_paint_cursor()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _on_card_pressed(index: int) -> void:
	# ⚠ THE HUB PATH ONLY. In pad mode the cards are still real Buttons with real
	# focus, so player one hitting Enter (or clicking) while player two's chooser is up
	# would fire this and write PLAYER TWO's card into `selected_class` — the exact
	# leak the separate store exists to prevent. `_confirm_cursor` is pad mode's
	# confirm, and it is the only one.
	if _pad_device >= 0:
		return
	var gs: Node = get_node_or_null("/root/GameState")
	# ⚠ RE-CHECKED, not trusted from `disabled`. A card built before a save loaded, or
	# a keyboard/gamepad focus walk that lands on a disabled button, would otherwise
	# hand out a class the climber has not earned — and `selected_class` persists, so
	# it would stick.
	if gs != null and not Progression.is_class_unlocked(index, gs.get("unlocked_classes") as Array):
		# ...UNLESS A GUARDIAN BANKED A PICK. This is where the floor-5 reward is
		# actually spent: pressing a locked card with a pick in hand CLAIMS that class.
		# The altar is the right place for it — the choosing is the part you remember,
		# and it happens somewhere you chose to walk to rather than in a pop-up over a
		# corpse.
		if not (gs.has_method("spend_class_choice") and bool(gs.call("spend_class_choice", index))):
			return
		_refresh_locks()
	if gs != null:
		gs.set("selected_class", index)
	_apply_feedback(index)
	# ⚠ ANNOUNCED BEFORE `close()`, NOT AFTER. `close()` calls `_end_pad_mode()`, and a
	# listener that reacts by opening or rebuilding something wants the state settled
	# but the screen still accounted for. Emitting after would also mean any listener
	# that re-opened this screen fought the close it was standing on.
	class_picked.emit(index)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif _pad_device < 0 and (event.is_action_pressed("ui_up", true)
			or event.is_action_pressed("ui_down", true)
			or event.is_action_pressed("ui_left", true)
			or event.is_action_pressed("ui_right", true)):
		# `true` = allow echo, so HOLDING an arrow walks the rail. The pad has its own
		# repeat clock (`PAD_REPEAT_FIRST`/`RATE`) because a stick has no key-repeat to
		# borrow; a keyboard already ships one, and running both would give the two
		# inputs different speeds down the same list.
		var dir := Vector2i(
			1 if event.is_action_pressed("ui_right", true) else (
				-1 if event.is_action_pressed("ui_left", true) else 0),
			1 if event.is_action_pressed("ui_down", true) else (
				-1 if event.is_action_pressed("ui_up", true) else 0))
		_move_cursor(dir)
		get_viewport().set_input_as_handled()
	elif _pad_device < 0 and event.is_action_pressed("ui_accept"):
		# The keyboard's commit. It goes through `_on_card_pressed` and not through
		# `_confirm_cursor`: this is the HUB path, and the two differ in which store they
		# write — the whole reason pad mode has a separate confirm at all.
		_on_card_pressed(_cursor)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_1 \
			and event.keycode < KEY_1 + _cards.size():
		# ⚠ WAS `<= KEY_8`, WITH NINE CLASSES. The ninth was unreachable by key for as
		# long as there have been nine — a hard-coded bound outliving the roster it was
		# written for. Derived now.
		_on_card_pressed(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()


func _selected_class() -> int:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var v: Variant = gs.get("selected_class")
		if v != null:
			return int(v)
	return 0


## Brighten the currently-selected card so the choice reads.
func _refresh_highlight() -> void:
	# ⚠ DELEGATES NOW, rather than being the second writer of `modulate`. It ran AFTER
	# `_refresh_locks` inside `open()` and assigned a full-alpha colour to every row,
	# which is what made the guarded rows look unguarded. One painter, one truth.
	if _cursor < 0 or _cursor >= _cards.size():
		_cursor = clampi(_selected_class(), 0, maxi(_cards.size() - 1, 0))
	_paint_cursor()


## Re-dress the hub body + update the class HUD label. No-ops in scenes without
## those nodes (the arena), so the autoload is scene-safe.
##
## ⚠ IT RE-CONFIGURES THE BODY NOW, NOT JUST ITS COLOUR. The town used to be driven by
## `Player`, which has no kit — a tint was the whole of "you are a Cryomancer now". The
## town body is a `Hero` since casting moved into the lobby, so a class change that
## only recoloured it would leave you standing there in ice-blue throwing the
## Arcanist's spells. `configure_class` is the one call that rebuilds the hand.
func _apply_feedback(index: int) -> void:
	var col: Color = ClassInfo.color_for(index)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		if player.has_method("configure_class"):
			player.call("configure_class", index)
		if player.has_method("set_class_tint"):
			player.call("set_class_tint", col)  # retint the stick figure
	for label: Node in get_tree().get_nodes_in_group("class_hud_label"):
		if label is Label:
			# Just the name — `World._reflect_selected_class` writes the same string, and
			# two writers disagreeing about a "Class: " prefix is how a label starts
			# flickering between two forms depending on which one ran last.
			(label as Label).text = ClassInfo.name_for(index)
	_refresh_highlight()
