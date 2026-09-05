class_name Outfitter
extends Control
## THE OUTFITTER — everything you decide BEFORE you climb, on one screen a thumb can
## reach. Three things, all of which already existed and none of which a player could
## get to:
##
##   1. **CHOOSE YOUR THREE.** `SpellLibrary.CLASS_KITS` authors FIVE roles per class
##      and the hand holds THREE, so every class has always had two spells it was
##      built with and shipped without. Which three you carry was a constant. Now it
##      is a choice: 4 non-ult roles choose 2 = SIX hands per class, 54 across the
##      roster, from zero new content. This is the only customisation in the game
##      that changes how you actually fight.
##   2. **THE ARMORY.** `Loadout.gd` — 3 slots x 19 pieces, real effect bags, live on
##      the hero — has been complete and unreachable behind an `if false:` in the
##      parked hub since it was written. One button opens it.
##   3. **WHAT EACH SPELL ACTUALLY DOES.** Tap a role and the line under the header
##      tells you, in one sentence (`SpellBlurbs`). A hand of four picked from a list
##      of names is a guess; the blurb is what makes it a choice.
##
## == THE COLOURWAY IS NOT HERE ANY MORE, AND THE STATE IT USED IS UNTOUCHED ====
## Maker: *"remove that azure ember etc. options within the class selection"*. The
## colourway picker was the third row of this screen and it is gone from it -- "Azure /
## Ember / Void / Jade / Mono" are limb TINTS, and a tint is noise on the one screen
## whose entire question is which of nine fighters you are about to be.
##
## ⚠ THE PICKER WENT; THE PICK DID NOT. `chosen_colourway`, `colourways()` and
## `colourway_name()` below are still here and still exported, because THREE consumers
## outside this file read them and none of them is ours:
##     scripts/combat/PauseMenu.gd:953-1018  -- the appearance row, which is where a
##                                             cosmetic belongs and where it still is
##     scripts/Settings.gd:201,245-248       -- persists it across launches
##     tools/slice_test_settings.gd:334-372  -- pins that round-trip
## Deleting the static would have been a parse-time break in a file another agent owns.
## What was checked before cutting the button: `GameState.colourway` (read at hero spawn,
## `Hero.gd:1787`) has NO WRITER anywhere in the tree, so it was -1 before this edit and
## it is -1 after -- nothing was stranded, because nothing was ever connected. The
## one-line hook that would connect it is named in the report for this pass.
##
## Built in code, house style (`ClassSelect` / `Loadout` / `PauseMenu` / `Lobby` all
## do this), laid out for the **640x360 base viewport in landscape** with every tap
## target at least `MIN_TAP` tall.
##
## Scene-safe and autoload-free: it reaches `GameState` and `Loadout` through the tree
## (`/root/...`), never as bare globals, so a headless suite can build one with no
## autoloads registered at all.

signal closed

# ── the look (borrowed from the Lobby so the two screens are one screen) ────
const PAPER: Color = Color(0.055, 0.052, 0.075)
const CHALK: Color = Color(0.93, 0.92, 0.86)
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)
const HIGHLIGHT: Color = Color(0.55, 0.9, 1.0)

## Every tappable row clears this in base units. At 640x360 upscaled to a real phone
## it is a comfortable thumb; below it, misses start. `tools/slice_test_shell.gd`
## pins the same floor on the Lobby.
const MIN_TAP: float = 30.0
const PANEL_W: float = 320.0

## FIXED height of the role list — the same trick the Lobby's host list uses, and for
## the same reason. A `ScrollContainer` reports zero minimum size on its scrolling
## axis, so this constant decides how tall the screen is, not the number of roles a
## class happens to author. Five roles or fifteen, the panel measures the same.
const LIST_H: float = 132.0

## Hero.gd has no `class_name`, so its constants are read through a runtime `load()`
## rather than a parse-time reference — the same idiom `Loadout.gd` uses, and for the
## same reason: a parse-time reference to Hero would drag its whole autoload-touching
## dependency chain into this script's compile.
const HERO_PATH: String = "res://scripts/combat/Hero.gd"

## ⚠ `preload` HANDS BACK THE SCRIPT OBJECT, NOT AN INSTANCE, so only `static func`
## entry points on it are callable. `SpellBlurbs` is written to that rule end to end;
## a plain `func` there would fail HERE, at runtime, in the frame a player opens this
## screen -- not at parse time. See that file's header.
const SpellBlurbs := preload("res://scripts/combat/SpellBlurbs.gd")

## ⚠ `preload`ed AND NOT A `class_name` — the same rule and the same reason as the line
## above. `HudStyle` has no `class_name`, so a named reference could not resolve without
## `.godot/global_script_class_cache.cfg` being current; a `preload` resolves at load
## time with no cache involved. `PauseMenu` reaches it exactly this way.
const HudStyle := preload("res://scripts/ui/HudStyle.gd")

## Colourway display names, in `Hero.COLOURWAYS` order. Names only — the COLOURS are
## read off Hero at runtime, so a palette edit there cannot leave this lying. A
## colourway past the end of this list is shown by index rather than dropped.
const COLOURWAY_NAMES: Array[String] = ["Azure", "Ember", "Void", "Jade", "Mono"]

## THE CHOSEN COLOURWAY, and the one piece of this screen that is not yet wired all
## the way through. See `PauseMenu`'s appearance row for what applies it and the
## honest note there about the one-line `Hero` hook that would do it properly at
## spawn. A static, so it outlives the scene change into the arena — the same
## lifetime `SpellLibrary._chosen_roles` needs and for the same reason.
static var chosen_colourway: int = 0

## ══ THE CLASS BUTTON — THE MERGE, AND WHY IT IS A FLAG ══════════════════════
## Maker's ruling on the town's pad row: *"I only want one for class within which I can
## edit spells, and one for armoury where I can look at my equipment"*. The lectern pad
## (which opened this screen) and the class pad merged into one, and THIS screen is what
## the survivor opens — so it grew a full-width header button carrying your class name,
## which opens `/root/ClassSelect` on top and re-aims this screen at whatever comes back.
##
## ⚠ WHY IT IS OFF BY DEFAULT. The Lobby (the title screen) opens the same `Outfitter`
## against its OWN `_selected_class`, which is not `GameState.selected_class` — the two
## are only equal by coincidence. A class button there would write the global while the
## Lobby went on believing its local pick, and the very next thing the player does on
## that screen would silently disagree with the class they just chose. The town owns the
## global, so the town is the only place that gets the button. `World.open_outfitter`
## sets this BEFORE `add_child`, because `_build()` runs inside `_ready()` and a property
## written afterwards has already missed it.
var show_class_picker: bool = false

var _class_id: int = 0
## The framed card. Held so its accent rule can be RE-TINTED when the class changes —
## see `_style_panel`. Without the reference the frame would be authored once, in
## whatever colour the screen happened to open on, and then lie for the rest of the
## session as the player walks the roster.
var _panel: PanelContainer = null
var _class_btn: Button = null
var _title: Label = null
var _hint: Label = null
var _list: VBoxContainer = null
var _scroll: ScrollContainer = null
## The fixed ult slot, outside the scrolling list. See the note where it is built.
var _ult_slot_row: PanelContainer = null
var _summary: Label = null
## The panel column. Held so a suite can assert the whole screen still fits 360 px —
## the thing that silently breaks the first time somebody adds one more row.
var _col: VBoxContainer = null
## Carried non-ult roles, OLDEST FIRST. The order is the feature: see `_toggle_role`.
var _carried: Array = []
var _ult_role: String = "ult"
## WHICH ROLE'S DESCRIPTION IS SHOWING. Empty means "not chosen yet", which
## `_refresh_blurb` resolves to the ULT -- the finisher is the most interesting line on
## any hand and the one row that is not a choice, so it is the only safe default that
## is never also a hint about what you should carry.
var _focus_role: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


## Point the screen at a class and redraw. Separate from `_ready` so the Lobby can
## re-aim the same instance as the player cycles classes.
func set_class(class_id: int) -> void:
	_class_id = maxi(class_id, 0)
	refresh()


func class_id() -> int:
	return _class_id


# ══════════════════════════════════════════════════════════════════════ UI
func _build() -> void:
	# Nearly opaque, deliberately. The title screen behind this is a drawn tower plus
	# five rows of type, and at 0.78 every one of them still read straight through the
	# spell names — which on a 6-inch screen is not a mood, it is a legibility bug.
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # eat taps meant for the lobby behind
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# A real panel, like ClassSelect and the Armory — so the screen has an edge and
	# reads as a thing sitting ON the title screen rather than text floating over it.
	#
	# ⚠ IT WAS A BARE `PanelContainer` UNTIL NOW, i.e. Godot's DEFAULT theme box: a flat
	# mid-grey rounded rectangle that appears nowhere else in this game. The one screen
	# the maker reaches to change class was the one screen wearing the engine's stock
	# UI. `HudStyle.panel` is the shape the whole HUD was consolidated onto (PAPER
	# ground, a 1 px accent rule, a 3 px radius) and `PauseMenu` already sets the
	# precedent for taking it verbatim and then tightening the margins.
	#
	# ⚠ THE MARGINS ARE TIGHTENED, AND IT IS A HEIGHT BUDGET RATHER THAN A TASTE CALL.
	# `HudStyle.panel` authors 26 px sides and 16 px top/bottom for the full-width
	# game-over card. `slice_test_outfitter` measures this screen's COLUMN at 332 px
	# against a 360 px base viewport, so the stock 16+16 would put the drawn panel at
	# 364 — four pixels of a phone's bottom row hanging off the bottom of the phone.
	# 8+8 lands it at 348 and leaves the same 12 px of slack the column had.
	_panel = PanelContainer.new()
	center.add_child(_panel)
	_style_panel()

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_theme_constant_override("separation", 4)
	_panel.add_child(col)
	_col = col

	# ── THE HEADER: A BUTTON **OR** A TITLE, NEVER BOTH ────────────────────────
	# It is the first thing on the screen because it is the widest decision on it: every
	# row below is scoped to the class this header names, so changing it changes the
	# meaning of everything underneath. Full width and `MIN_TAP` tall because on a phone
	# this is the tap that has to be impossible to miss.
	#
	# ⚠ THE BUTTON **REPLACES** THE TITLE, AND THAT WAS A MEASUREMENT, NOT A PREFERENCE.
	# The first version added the button ABOVE the title and `tools/slice_test_town.gd`
	# measured the column at **363 px against a 360 px base viewport** — three pixels of
	# a bottom button hanging off the bottom of a phone, which no desktop playtest would
	# ever show. It also read badly on its own terms: the title is "YOUR HAND — Stormcaller"
	# and the button is "☗ Stormcaller · change", so the class name appeared twice, one
	# line apart. Cutting the duplicate is both the fix and the better screen, and it
	# obeys the standing rule — every screen should be cut, not added to. The hint line
	# directly below still says what the screen is for, so nothing is actually lost.
	if show_class_picker:
		_class_btn = _button("", _open_class_select, 14)
		col.add_child(_class_btn)
	else:
		_title = Label.new()
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title.add_theme_font_size_override("font_size", 17)
		_title.add_theme_color_override("font_color", CHALK)
		col.add_child(_title)

	# ⚠ THIS LINE USED TO BE AN INSTRUCTION AND IS NOW THE ANSWER. It read
	# "five spells - 4 buttons - pick the 3 you carry": a sentence a player reads once,
	# on a screen whose rows are already self-evidently pressable. It is now the
	# DESCRIPTION of whichever spell you last touched, which is the thing the maker
	# actually asked for and the thing this screen could not tell you. Same row, same
	# height budget, strictly more information -- the standing "cut, do not add" rule
	# is obeyed by replacement rather than by addition.
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# TWO LINES, RESERVED. `SpellBlurbs.MAX_LEN` is 96 characters and this label is
	# PANEL_W wide at font 9, which holds ~71 -- so every blurb is one or two lines and
	# never three. Reserving the second means the panel measures the SAME height for a
	# long blurb and a short one, so `slice_test_outfitter`'s 360 px budget is a fact
	# about the screen rather than about which role happened to be selected.
	_hint.custom_minimum_size = Vector2(PANEL_W, 22.0)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 9)
	_hint.add_theme_color_override("font_color", GRAPHITE)
	col.add_child(_hint)

	# THE BOUND — see LIST_H.
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(PANEL_W, LIST_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list)

	# ⚠ THE ULT ROW LIVES OUTSIDE THE SCROLL, and it has to. Inside, it was the fifth
	# row of a list four rows tall — so the one row that is not a choice, and the only
	# thing that makes the hand read as THREE rather than two, was the row that
	# scrolled off. It is fixed content in a fixed slot; it belongs in fixed space.
	_ult_slot_row = PanelContainer.new()
	# Styled for the same reason the outer panel now is — it was the second bare
	# `PanelContainer` on this screen, so the ONE row that is not a choice was drawn in
	# Godot's stock grey while every row that IS a choice was drawn in the house palette.
	# It reads as the shelf the finisher sits on, at a lower accent alpha than the frame
	# so it recedes rather than competing with it.
	_ult_slot_row.add_theme_stylebox_override("panel", _slot_box())
	col.add_child(_ult_slot_row)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 9)
	_summary.add_theme_color_override("font_color", Color(0.72, 0.86, 0.95))
	col.add_child(_summary)

	# THE ONE REMAINING SIDE DOOR. It shared this row with the colourway picker; with
	# that gone it takes the full width, which costs nothing (the row was already
	# `MIN_TAP` tall) and doubles the tap target on the screen's one non-obvious button.
	col.add_child(_button("⚒  Armory", _open_armory, 13))

	col.add_child(_button("Done", close, 14))


# ─────────────────────────────────────────────────────────────────── the frame
## THE CARD, IN THE CLASS'S OWN COLOUR.
##
## `HudStyle.panel` verbatim, then two changes, both of which have a reason:
##
##   * TIGHTER MARGINS — see the height-budget note where the panel is built.
##   * THE ACCENT IS THE CLASS'S, at 0.5 alpha. Every other framed card in the game
##     takes the house SKY; this one is the screen whose entire question is WHICH of
##     the nine you are, so the frame answers it before you have read a word. It is the
##     same `ClassInfo.color_for` the header button, `ClassSelect`'s cards and the hub
##     stick figure all read, so the four cannot disagree.
##
## Idempotent and re-callable: `_redraw` calls it on every class change, which is the
## only way the frame can follow the pick rather than freeze on whatever the screen
## opened with.
const PANEL_PAD_X: float = 10.0
const PANEL_PAD_Y: float = 8.0


func _accent() -> Color:
	if _class_id >= 0 and _class_id < ClassInfo.CLASSES.size():
		return ClassInfo.color_for(_class_id)
	return HIGHLIGHT


func _style_panel() -> void:
	if _panel == null:
		return
	var box: StyleBoxFlat = HudStyle.panel(HudStyle.with_a(_accent(), 0.5))
	box.content_margin_left = PANEL_PAD_X
	box.content_margin_right = PANEL_PAD_X
	box.content_margin_top = PANEL_PAD_Y
	box.content_margin_bottom = PANEL_PAD_Y
	_panel.add_theme_stylebox_override("panel", box)


## The ult row's shelf. Same shape as the card, one step quieter: a barely-there fill
## over PAPER and a 0.22-alpha rule, so it separates the fixed slot from the choosable
## rows without becoming a second frame competing with the first.
func _slot_box() -> StyleBoxFlat:
	var box: StyleBoxFlat = HudStyle.panel(HudStyle.with_a(_accent(), 0.22))
	box.bg_color = HudStyle.TRACK
	box.content_margin_left = 4.0
	box.content_margin_right = 4.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box


func _button(text: String, cb: Callable, font_size: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(PANEL_W, MIN_TAP)
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE   # a stray focus ring on a phone reads as a bug
	b.clip_text = true
	b.pressed.connect(cb)
	return b


# ═══════════════════════════════════════════════════════════ choose your three
## Rebuild from the live `SpellLibrary` answer for this class. Cheap, and far simpler
## than diffing five rows.
func refresh() -> void:
	_ult_role = SpellLibrary.ult_role_for_class(_class_id)
	# Seed from whatever the class is ACTUALLY carrying — the player's pick if they
	# made one, else the authored hand. So opening this screen never silently
	# rearranges a hand just by being opened.
	# A new class means a new hand; keeping the previous class's focused role would
	# describe a spell that is no longer on this screen (roles are shared names, and
	# `damage` on the Cleric is not `damage` on the Warlock).
	_focus_role = ""
	_carried.clear()
	for role: Variant in SpellLibrary.slot_roles_for_class(_class_id):
		if String(role) != _ult_role:
			_carried.append(String(role))
	_redraw()


func _redraw() -> void:
	# THE FRAME FOLLOWS THE PICK. Re-tinting here rather than only at build time is the
	# whole point of holding `_panel`: `set_class` funnels into this function, so walking
	# the roster in `ClassSelect` re-colours the card you come back to.
	_style_panel()
	if _ult_slot_row != null:
		_ult_slot_row.add_theme_stylebox_override("panel", _slot_box())
	if _title != null:
		_title.text = "YOUR HAND — %s" % _class_display_name()
	_refresh_blurb()
	if _list == null:
		return
	for child: Node in _list.get_children():
		# Removed BEFORE freeing: `queue_free` defers to the end of the frame, so a
		# row left parented is still measured by the layout pass in between and the
		# list flickers one row taller.
		_list.remove_child(child)
		child.queue_free()
	for role: String in SpellLibrary.choosable_roles_for_class(_class_id):
		_list.add_child(_role_row(role, _carried.has(role), true))
	if _ult_slot_row != null:
		for child: Node in _ult_slot_row.get_children():
			_ult_slot_row.remove_child(child)
			child.queue_free()
		_ult_slot_row.add_child(_role_row(_ult_role, true, false))
	_refresh_summary()
	_refresh_class_btn()


## One role, as a thumb-sized row. The ult row is `enabled == false`: a class authors
## exactly one ult and the last slot only accepts an ult, so there is nothing to
## decide there — showing it anyway is what makes the hand read as three.
func _role_row(role: String, carried: bool, enabled: bool) -> Button:
	var spell: SpellDef = SpellLibrary.spell_for_role(_class_id, role)
	var tier: int = SpellTier.of(spell) if spell != null else SpellTier.Tier.QUICK
	var mark: String = "◉" if carried else "○"
	var b := Button.new()
	b.text = "%s  %s  ·  %s" % [mark, role.to_upper(), spell.display_name if spell != null else "--"]
	b.tooltip_text = SpellTier.display_name(tier)
	b.custom_minimum_size = Vector2(PANEL_W - 16.0, MIN_TAP)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	# The shelf, in the colour the whole game badges shelves with — so "this is my
	# ult" is readable without reading.
	b.add_theme_color_override("font_color",
		SpellTier.color(tier) if carried else GRAPHITE)
	if enabled:
		b.pressed.connect(_toggle_role.bind(role))
	else:
		# ⚠ THE ULT ROW IS `disabled`, AND A DISABLED BUTTON EMITS NOTHING -- not
		# `pressed`, not `gui_input`. So the one spell on this screen a player cannot
		# change was also the one they could not ask about. `mouse_filter = PASS` lets
		# the tap reach this row's own handler while `disabled` goes on refusing to
		# TOGGLE it, which is the distinction that matters: reading is not choosing.
		b.disabled = true
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.gui_input.connect(_on_locked_row_input.bind(role))
		b.modulate = Color(1.0, 1.0, 1.0, 0.85)
	return b


## Tapping the fixed ult row shows its description and changes nothing else.
func _on_locked_row_input(event: InputEvent, role: String) -> void:
	var tap: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) 		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not tap:
		return
	_focus_role = role
	_refresh_blurb()


## Tap a role to carry it.
##
## A TAP ALWAYS DOES SOMETHING, which on a phone matters more than it sounds. With two
## of two slots full, tapping a third role does not refuse — it evicts the one you
## chose LONGEST ago (`_carried` is oldest-first) and takes its place. So a player can
## walk the whole kit with repeated taps and never has to work out which one to
## un-tap first. Tapping a carried role when both slots are full is the explicit
## un-tap, and is refused only when it would leave the hand short.
func _toggle_role(role: String) -> void:
	# The tap that changes the hand is also the tap that asks "what IS this one" -- so
	# the blurb line follows it. There is no hover on a phone and no second gesture to
	# spend, so the two questions share one tap and the answer arrives with the change.
	_focus_role = role
	var open_slots: int = SpellTier.SLOT_COUNT - 1   # the last slot is the ult's
	if _carried.has(role):
		if _carried.size() <= 1:
			# A hand with one spell in it is not a choice, it is a bug -- so the DROP is
			# refused. The description is not.
			#
			# ⚠ THIS USED TO BE A BARE `return`, AND THE BLURB LINE TURNED IT INTO A
			# BUG. Caught by `slice_test_outfitter`, not by looking: walking the
			# Swordsaint's four roles, the last one left carried refused the tap and
			# fell out of this function BEFORE `_redraw`, so the header line went on
			# describing the PREVIOUS role. The one spell a player cannot drop was the
			# one spell they could not read about, and it was silent about both.
			_refresh_blurb()
			return
		_carried.erase(role)
	else:
		_carried.append(role)
		while _carried.size() > open_slots:
			_carried.pop_front()
	_commit()
	_redraw()
	_sfx("ding", -8.0)


## Write the hand through to `SpellLibrary`, which is the ONLY thing that has to
## happen for it to reach the run: `Hero._configure_class` funnels every hero through
## `SpellLibrary.build_for_class`, which asks `slot_roles_for_class`. Refused hands
## leave the previous one standing.
func _commit() -> void:
	var roles: Array = _carried.duplicate()
	roles.append(_ult_role)
	if not SpellLibrary.set_slot_roles(_class_id, roles):
		return
	# No-op until `GameState.spell_roles` exists; see SpellLibrary.persist_to_state.
	SpellLibrary.persist_to_state(get_node_or_null("/root/GameState"))


## THE LINE THAT SAYS WHAT A SPELL DOES.
##
## Reads through `SpellBlurbs.for_spell`, so a `SpellDef` that ever authors its own
## `description` wins over the table -- see that file. Falls back to the class name
## rather than to an instruction, because an empty line here would read as a bug and a
## re-typed instruction is what this row used to be.
func _refresh_blurb() -> void:
	if _hint == null:
		return
	var role: String = _focus_role if _focus_role != "" else _ult_role
	var spell: SpellDef = SpellLibrary.spell_for_role(_class_id, role)
	var text: String = SpellBlurbs.for_spell(spell)
	if text == "":
		# A HOLE, SHOWN. `tools/slice_test_class_identity.gd` asserts every id a class
		# can carry has a blurb, so reaching this branch means the suite is stale or a
		# spell was added without one -- and the name alone is still more useful than a
		# sentence apologising for itself.
		text = String(spell.display_name) if spell != null else ""
	_hint.text = text


func _refresh_summary() -> void:
	if _summary == null:
		return
	var names: Array = []
	for spell: Variant in SpellLibrary.build_for_class(_class_id):
		if spell != null:
			names.append(String((spell as SpellDef).display_name))
	# ⚠ THE KEY ROW IS COUNTED, NOT TYPED. It was the literal "1 · 2 · 3" and the hand
	# grew to four. `Hero.SPELL_KEYS` is the real list, but `Hero` is not a `class_name`
	# — naming it here would not compile — and reaching it by `load()` would drag the
	# whole combat chain into a town screen. The number row IS the labels by
	# construction, and `tools/slice_test_spell_buttons.gd` is what pins that: it
	# asserts `SPELL_KEYS` matches the bindings and is `SLOT_COUNT` long.
	var keys: Array[String] = []
	for i: int in SpellTier.SLOT_COUNT:
		keys.append(str(i + 1))
	_summary.text = "%s      %s" % [" · ".join(keys), "      ".join(names)]


# ══════════════════════════════════════════════════════════════ which of the nine
## The header button, tinted in the class's own colour so it matches the body you walk
## away in — the same `ClassInfo.color_for` `ClassSelect`'s cards and the hub stick
## figure both use.
##
## The word "change" is on it deliberately, against this project's standing "remove the
## words, keep the picture" rule. The picture (the glyph, the colour) says WHICH class;
## nothing in a glyph says the thing is PRESSABLE, and this row sits above a list of
## rows that are all pressable for a different reason. One word buys the distinction.
func _refresh_class_btn() -> void:
	if _class_btn == null:
		return
	_class_btn.text = "☗  %s  ·  change" % _class_display_name()
	if _class_id >= 0 and _class_id < ClassInfo.CLASSES.size():
		_class_btn.add_theme_color_override(
			"font_color", ClassInfo.color_for(_class_id).lightened(0.25))


## ⚠ THE CHOOSER IS AN AUTOLOAD ON ITS OWN `CanvasLayer` AT 90, and this screen is on
## the town's overlay layer at 80 — so it lands ON TOP, which is the only reason the
## merge works at all without reparenting anything. `World.OVERLAY_LAYER` carries the
## measurement; at the 95 it used to be, this call would have opened a screen the player
## could not see, behind this screen's 0.93-opaque dimmer.
##
## Reached through the tree rather than as a bare global, like `_open_armory` and for
## the same reason: this script stays loadable in a headless harness with no autoloads.
func _open_class_select() -> void:
	var sel: Node = get_node_or_null("/root/ClassSelect")
	if sel == null or not sel.has_method("open"):
		return
	# Guarded rather than one-shot: a player who opens the grid, taps away to dismiss it
	# and opens it again would otherwise stack a second connection and re-aim this screen
	# twice on the next pick.
	if sel.has_signal(&"class_picked") and not sel.is_connected(&"class_picked", _on_class_picked):
		sel.connect(&"class_picked", _on_class_picked)
	sel.call("open")
	_sfx("ding", -6.0)


## The pick came back. `set_class` re-reads `SpellLibrary` for the NEW class, so the
## role list, the ult row and the summary all become that class's — which is the whole
## point of merging the two pads rather than merely stacking their screens.
func _on_class_picked(index: int) -> void:
	set_class(index)


## True while one of the two autoload panels this screen can open is up. Both draw ABOVE
## this one, so while either is showing, this screen is not the thing the player is
## looking at and must not answer for their Back press. See `_unhandled_input`.
func _modal_over_me() -> bool:
	for path: String in ["/root/ClassSelect", "/root/Loadout"]:
		var n: Node = get_node_or_null(path)
		if n != null and n.has_method("is_open") and bool(n.call("is_open")):
			return true
	return false


# ═══════════════════════════════════════════════════════════════ the armory
## `Loadout` is an autoload (`/root/Loadout`) and draws on its own `CanvasLayer` at
## layer 90, so it lands cleanly on top of this screen with no reparenting. Reached
## through the tree rather than as a bare global so this script stays loadable in a
## headless harness with no autoloads registered.
func _open_armory() -> void:
	var lo: Node = get_node_or_null("/root/Loadout")
	if lo != null and lo.has_method("open"):
		lo.call("open")
		_sfx("ding", -6.0)


func armory_available() -> bool:
	var lo: Node = get_node_or_null("/root/Loadout")
	return lo != null and lo.has_method("open")


# ══════════════════════════════════════════════════════════════ the colourway
## The palette, read off `Hero` at runtime so a colour edited there is a colour shown
## here. Empty if Hero ever loses the constant, which the button copes with.
static func colourways() -> Array:
	var script: GDScript = load(HERO_PATH) as GDScript
	if script == null:
		return []
	var raw: Variant = script.get_script_constant_map().get("COLOURWAYS", [])
	return raw as Array if raw is Array else []


static func colourway_name(index: int) -> String:
	if index >= 0 and index < COLOURWAY_NAMES.size():
		return COLOURWAY_NAMES[index]
	return "Colour %d" % (index + 1)


# ══════════════════════════════════════════════════════════════════ helpers
func _class_display_name() -> String:
	if _class_id >= 0 and _class_id < ClassInfo.CLASSES.size():
		return String((ClassInfo.CLASSES[_class_id] as Dictionary).get("name", "Class %d" % _class_id))
	return "Class %d" % _class_id


func close() -> void:
	closed.emit()


## ⚠ BACK IS REFUSED WHILE A PANEL IS OPEN OVER THIS ONE, AND THAT IS A REAL BUG, NOT
## TIDINESS. `_unhandled_input` propagates in REVERSE tree order, and both panels this
## screen can open (`ClassSelect`, `Loadout`) are autoloads — added to the root long
## before the town, therefore reached AFTER it. So a bare handler here eats the Back
## press meant for the class grid, closes the Outfitter out from under it, and leaves an
## orphaned chooser floating over a town nothing is frozen for. The layer order says
## those two are in front; the input order has to agree.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or _modal_over_me():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _sfx(key: String, db: float = 0.0) -> void:
	var s: Node = get_node_or_null("/root/Sfx")
	if s != null and s.has_method("play"):
		s.call("play", key, db)
