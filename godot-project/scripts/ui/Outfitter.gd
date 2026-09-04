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
##   3. **A COLOURWAY.** `cycle_colourway` is a real input action bound to `C` that no
##      player would ever find, and in co-op two identical stick figures at 640x360 is
##      a genuine readability problem. Pick your colour where you pick everything else.
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
var _class_btn: Button = null
var _title: Label = null
var _hint: Label = null
var _list: VBoxContainer = null
var _scroll: ScrollContainer = null
## The fixed ult slot, outside the scrolling list. See the note where it is built.
var _ult_slot_row: PanelContainer = null
var _summary: Label = null
var _colour_btn: Button = null
## The panel column. Held so a suite can assert the whole screen still fits 360 px —
## the thing that silently breaks the first time somebody adds one more row.
var _col: VBoxContainer = null
## Carried non-ult roles, OLDEST FIRST. The order is the feature: see `_toggle_role`.
var _carried: Array = []
var _ult_role: String = "ult"


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
	var panel := PanelContainer.new()
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(PANEL_W, 0)
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
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

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	col.add_child(_ult_slot_row)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 9)
	_summary.add_theme_color_override("font_color", Color(0.72, 0.86, 0.95))
	col.add_child(_summary)

	# The two OTHER customisations, paired on one row so they cost one row of height
	# between them rather than two. Both are still MIN_TAP tall.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var armory := _button("⚒  Armory", _open_armory, 13)
	armory.custom_minimum_size = Vector2(PANEL_W * 0.5 - 3.0, MIN_TAP)
	armory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(armory)
	_colour_btn = _button("", _cycle_colour, 13)
	_colour_btn.custom_minimum_size = Vector2(PANEL_W * 0.5 - 3.0, MIN_TAP)
	_colour_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_colour_btn)

	col.add_child(_button("Done", close, 14))


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
	_carried.clear()
	for role: Variant in SpellLibrary.slot_roles_for_class(_class_id):
		if String(role) != _ult_role:
			_carried.append(String(role))
	_redraw()


func _redraw() -> void:
	if _title != null:
		_title.text = "YOUR HAND — %s" % _class_display_name()
	if _hint != null:
		# ⚠ DERIVED, BECAUSE IT WAS WRONG. This line read "five spells · three buttons ·
		# pick the two you carry" — true until `SpellTier.SLOT_COUNT` became 4, and a
		# hand-typed count is a fact that goes stale silently while the screen underneath
		# it stays correct.
		var open_slots: int = SpellTier.SLOT_COUNT - 1
		_hint.text = "five spells · %d buttons · pick the %d you carry" % [
			SpellTier.SLOT_COUNT, open_slots]
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
	_refresh_colour()
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
		b.disabled = true
		b.modulate = Color(1.0, 1.0, 1.0, 0.85)
	return b


## Tap a role to carry it.
##
## A TAP ALWAYS DOES SOMETHING, which on a phone matters more than it sounds. With two
## of two slots full, tapping a third role does not refuse — it evicts the one you
## chose LONGEST ago (`_carried` is oldest-first) and takes its place. So a player can
## walk the whole kit with repeated taps and never has to work out which one to
## un-tap first. Tapping a carried role when both slots are full is the explicit
## un-tap, and is refused only when it would leave the hand short.
func _toggle_role(role: String) -> void:
	var open_slots: int = SpellTier.SLOT_COUNT - 1   # the last slot is the ult's
	if _carried.has(role):
		if _carried.size() <= 1:
			return   # a hand with one spell in it is not a choice, it is a bug
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


func _cycle_colour() -> void:
	var count: int = maxi(colourways().size(), 1)
	chosen_colourway = (chosen_colourway + 1) % count
	_refresh_colour()
	_sfx("ding", -8.0)


func _refresh_colour() -> void:
	if _colour_btn == null:
		return
	var palette: Array = colourways()
	_colour_btn.text = "◧  %s" % colourway_name(chosen_colourway)
	if chosen_colourway >= 0 and chosen_colourway < palette.size():
		_colour_btn.add_theme_color_override("font_color", palette[chosen_colourway] as Color)


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
