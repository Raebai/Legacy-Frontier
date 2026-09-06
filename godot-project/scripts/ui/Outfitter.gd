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
##   4. **THE GRIMOIRE.** Eleven spells — the nine Tier 3s and both Tier 2s — could be
##      cast only by bots in the Watch Bots showcase; `SpellDrops.TOWER_SPELL_DROPS` is
##      false by the maker's own ruling, so a climber's hand on floor 41 was identical
##      to their hand on floor 1. `SpellLibrary` grew the mechanism (`equippable` /
##      `set_equipped` / `equipped_id` / `clear_equipped`) and NOTHING CALLED IT — the
##      pool was reachable from no screen in the game. The ✦ button below is the door.
##
## == THE GRIMOIRE AND "CHOOSE YOUR THREE" ARE TWO MECHANISMS, DELIBERATELY =====
## They answer different questions and neither replaces the other. Roles pick WHICH
## FOUR of a class's five AUTHORED spells it carries — every option is already that
## class's. The grimoire lays a Tier 2/3 over a SLOT INDEX, and a Tier 3 belongs to no
## class's role table at all, so there is no role to name it by. Overlaying by index is
## also what keeps them independent: re-order your roles and your equipped ult stays put.
## See the `_equipped` header in `SpellLibrary.gd` for the maker's fork and their answer.
##
## == THE COLOURWAY LEFT AS A ROW AND CAME BACK AS A MODE, AND BOTH ARE RIGHT ===
## Maker, first: *"remove that azure ember etc. options within the class selection"*. The
## colourway picker was the third ROW of this screen and it is still gone from the rows --
## "Azure / Ember / Void / Jade / Mono" are limb TINTS, and a tint is noise on the one
## screen whose entire question is which of nine fighters you are about to be.
##
## Maker, since: *"in the armoury I should also be able to change the colour of my stickman
## figure the colour of his head body and legs individually"*. So it is back, as the third
## MODE of the bounded scroll -- behind a door, exactly like the Grimoire -- and the two
## rulings do not contradict each other: what was cut was a cosmetic sitting IN the way of
## the class decision, and what is here is a cosmetic you have to go and ask for. Nothing
## on the default screen changed.
##
## See `_mode` for why a third mode rather than a third section (the answer is 22 px), and
## `_colour_part` for the two-tap gesture, which is the grimoire's slot-cursor verbatim.
##
## ⚠ THE PICKER WENT; THE PICK DID NOT. `chosen_colourway`, `colourways()` and
## `colourway_name()` below are still here and still exported, because THREE consumers
## outside this file read them and none of them is ours:
##     scripts/combat/PauseMenu.gd:953-1018  -- the appearance row, which is where a
##                                             cosmetic belongs and where it still is
##     scripts/Settings.gd:201,245-248       -- persists it across launches
##     tools/slice_test_settings.gd:334-372  -- pins that round-trip
## Deleting the static would have been a parse-time break in a file another agent owns.
##
## ⚠ AND IT IS CONNECTED NOW. When the button was cut, `GameState.colourway` (read at
## hero spawn) had NO WRITER anywhere in the tree — it was -1 before that edit and -1
## after, so nothing was stranded because nothing had ever been joined up. That missing
## writer is the property setter on `chosen_colourway` below, and it means the two
## consumers above now reach a spawning hero without either of them changing.
## Pinned by `tools/slice_test_appearance_relay.gd`.
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

## ══ THE THREE MARKS THIS SCREEN SPEAKS IN ═══════════════════════════════════
## `RARE_BADGE` says "the grimoire touched this" — it appears on the role row whose
## authored spell has been overridden, on the grimoire slot header, on a pool row you
## carry, and on the summary. `CARRIED_MARK` and `PLAIN_MARK` are the ordinary
## have/have-not pair.
##
## ⚠ THEY ARE CONSTS BECAUSE A TEST HARDCODED ONE AND A GLYPH SWEEP BROKE IT. These used
## to be `◈` / `◉` / `○` inline at five call sites, and `slice_test_outfitter` asserted
## the literal `◈` in a sixth place. None of those characters was ever DRAWN — the theme
## declares no font, so the fallback has no coverage above Latin-1 — and when they were
## replaced with glyphs that render, the sweep collapsed the rare badge and the carried
## mark onto the same dot. That is a real regression (the screen deliberately keeps them
## distinct) and the suite caught it, then failed again on its own hardcoded copy.
## One name, read by both sides, is the fix for both halves.
##
## ⚠ EVERY ONE IS VERIFIED PRESENT IN THE FALLBACK FONT. `slice_test_font_coverage` will
## fail the build if a future edit reaches for a prettier symbol the font cannot draw.
const RARE_BADGE: String = "‡"
const CARRIED_MARK: String = "•"
const PLAIN_MARK: String = "·"
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

## ⚠ THE SAME BODY YOU FIGHT WITH, and `preload`ed by PATH rather than named as
## `CharacterRig`, which it does have. Two reasons, and the second is the load-bearing
## one: a `class_name` reference resolves through
## `.godot/global_script_class_cache.cfg`, which this project has watched go stale after
## every new script for four sessions running (see CLAUDE.md, Sessions 6/8/9); and
## `Loadout.gd` has already proved a bare rig is headless-safe (no parent collider means
## `_align_feet_to_body` no-ops, and its `Sfx` lookup is tree-guarded). The preview cannot
## drift from the game because it IS the game's rig, which is the whole reason it is worth
## drawing instead of painting five swatches.
const RigScript := preload("res://scripts/combat/CharacterRig.gd")

## The preview box, in base units. Sized to hold the default 31 px figure at
## `PREVIEW_SCALE` with air around it; `PREVIEW_GAP` is the space between it and the
## panel's left edge. All four are consumed by `_build_preview`'s anchor maths — see there
## for why 30 px of the 640 is still free once they are spent.
const PREVIEW_W: float = 104.0
const PREVIEW_H: float = 104.0
const PREVIEW_GAP: float = 16.0
const PREVIEW_SCALE: float = 2.2
const PREVIEW_FEET_Y: float = 92.0

## Colourway display names, in `Hero.COLOURWAYS` order. Names only — the COLOURS are
## read off Hero at runtime, so a palette edit there cannot leave this lying. A
## colourway past the end of this list is shown by index rather than dropped.
const COLOURWAY_NAMES: Array[String] = ["Azure", "Ember", "Void", "Jade", "Mono"]

## THE CHOSEN COLOURWAY. A static, so it outlives the scene change into the arena — the
## same lifetime `SpellLibrary._chosen_roles` needs and for the same reason.
##
## ══ THE FIELD IT FEEDS HAD NO WRITER, AND THAT IS WHY THIS IS A PROPERTY ══════════
## Both halves of this feature were built, correct, and never introduced:
##
##   * THIS static is a real persisted preference — written by `PauseMenu`'s appearance
##     row and restored at boot by `Settings.apply_all` off `user://settings.cfg`.
##   * `GameState.colourway` is read AT SPAWN by `Hero._ready`, which hands it to
##     `GameState.colourway_parts()` as the middle link of the per-part fallback chain
##     (the part's own index -> `colourway` -> the caller's fallback).
##
## `GameState.colourway` **had no writer anywhere in the tree**. It was declared -1 and
## was still -1 at every spawn that has ever happened, so the middle link was dead, every
## unpainted part fell through to the hardcoded fallback, and a player who set their
## colour and quit came back the default colour.
##
## ⚠ IT DID NOT LOOK BROKEN, WHICH IS WHY IT LASTED. `PauseMenu._sync_colourway` REPLAYS
## the pick onto the live hero the first time that menu opens — so the colour was right
## the moment you went looking for it and wrong on every floor until you did. The fault
## was invisible from inside the only screen that could show it.
##
## ⚠ WHY A SETTER RATHER THAN A MIRROR CALL AT THE WRITE SITES. The two writers are
## `Settings.apply_all` (boot) and `PauseMenu._cycle_appearance` (live), and BOTH assign
## this field plainly. A `sync_appearance()` helper would have to be remembered at both,
## and forgetting it at the boot site is precisely the failure above — the preference
## would then work only for players who touch the pause menu every single run. As a
## property, every existing assignment feeds the relay and no other file changes at all.
## The same "there is no third path that writes one without the other" rule `chosen_parts`
## states below, enforced by the language instead of by discipline.
##
## ⚠ REACHED THROUGH `Engine.get_main_loop()`, NOT `get_node_or_null`. A setter on a
## static has no `self` to look a node up from. A suite with no autoloads registered — or
## the window between engine start and the tree existing — gets a silent no-op, which is
## what keeps this screen buildable bare (see `chosen_parts`).
static var chosen_colourway: int = 0:
	set(value):
		_chosen_colourway = value
		var loop: Object = Engine.get_main_loop()
		if not (loop is SceneTree):
			return
		var gs: Node = (loop as SceneTree).root.get_node_or_null(^"/root/GameState")
		if gs == null:
			return
		gs.set(&"colourway", value)
	get:
		return _chosen_colourway

## The backing store for the property above. Separate because a property setter that
## assigned to its own name would recurse.
static var _chosen_colourway: int = 0

## ══ THREE COLOURS, ONE FIGURE ═════════════════════════════════════════════════
## Maker: *"the colour of his head body and legs individually"*. Indices into the SAME
## `Hero.COLOURWAYS` the whole-figure pick uses, in `CharacterRig.set_part_tints(head,
## body, legs)` order. -1 means "this part was never chosen" and resolves to
## `chosen_colourway` — see `part_colourway`.
##
## ⚠ A STATIC **AND** A `GameState` FIELD, WHICH IS TWO HOMES FOR ONE FACT, AND THAT IS
## DELIBERATE — it is the same split `chosen_colourway` (static, persisted by `Settings`)
## and `SpellLibrary._chosen_roles` (static, persisted to `GameState.spell_roles`) both
## already live with, for two reasons that do not overlap:
##
##   * THE STATIC is what makes this screen work with NO AUTOLOADS AT ALL. Every suite
##     that opens the Outfitter builds it bare (`slice_test_town`, `slice_test_shell`,
##     `slice_test_outfitter`), and a picker whose state lived only in `/root/GameState`
##     would silently do nothing there — which is a picker nobody can test.
##   * `GameState` is what makes the pick reach the HERO and the DISK.
##     `Hero._configure_class` reads `GameState.colourway_parts()` at spawn and
##     `GameState._save_climber` writes `part_colourways` to `user://climber.json`.
##
## The rule that keeps them honest: `_ready` HYDRATES the static from `GameState` (the
## disk is authoritative on open), and every pick MIRRORS the static back into it in the
## same frame (`_persist_colours`). There is no third path that writes one without the
## other.
static var chosen_parts: Array[int] = [-1, -1, -1]

## The three regions, in `chosen_parts` order and named for the SAME slots the rig's gear
## uses (`CharacterRig._visible_gear`) — a helmet REPLACES the head and is drawn in the
## head's colour, so there is one vocabulary rather than two.
const PART_KEYS: Array[String] = ["head", "body", "legs"]
## What the cursor row calls each one, and what each one actually covers. The second
## string is what stops "BODY" being a guess: the maker asked for three colours, not five,
## so the arms went with the torso (an arm on a stick figure reads as trunk) and the feet
## went with the legs (a foot dot caps the shin — in the body colour it reads as a sock).
## Kept SHORT because both strings share the 96-character description line with a colour
## name, and that line reserves exactly two rows of height — see `_hint` in `_build`.
const PART_NAMES: Array[String] = ["HEAD", "BODY", "LEGS"]
const PART_COVERS: Array[String] = ["skull and helm", "torso and arms", "legs and feet"]

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
## A POOL SPELL whose description is showing. Only ever a grimoire spell: a role's
## description is resolved live from `_focus_role` instead, because `_toggle_role`
## re-orders the hand under it and a cached `SpellDef` would then describe the slot the
## role used to be in. Null means "no pool spell is focused", which is the normal state.
var _focus_spell: SpellDef = null
## A REASON, shown INSTEAD of a description, for the one tap on this screen that is
## refused rather than obeyed: an ult aimed at a slot that cannot hold one. Empty is the
## normal state and means "show the blurb".
##
## ⚠ CLEARED AT EVERY SITE THAT MOVES THE FOCUS (`refresh`, `_on_locked_row_input`,
## `_toggle_role`, `_toggle_grimoire`, `_focus_slot`, `_toggle_equip`), not inside
## `_refresh_blurb` — that function is called from `_redraw` and would eat the reason in
## the same frame it was set. A stale reason is a line describing a refusal that did not
## happen, which is worse than no line at all.
var _focus_reason: String = ""

# ── the grimoire ──────────────────────────────────────────────────────────────
## THE POOL, BUILT ONCE. `SpellLibrary.equippable()` constructs a fresh `SpellDef` per
## entry on every call and `_redraw` draws a row per entry, so calling it per-draw would
## rebuild the whole pool every time a thumb lands. Same rule the file already follows
## for `TuningConfig.quality_is_low()`: cache in `_ready`, never per-draw.
##
## ⚠ IT IS NOT ELEVEN ANY MORE — IT IS THE TIER 2s, THE TIER 3s **AND THE ORPHANS**,
## which is roughly 18-20 rows. Maker: *"it shouldnt prevent any player for taking any
## spell"*. The count is deliberately not written down here or anywhere else in this
## file: `equippable()` derives it, and a number copied into a comment is a number that
## goes stale the next time a spell is authored. What the extra rows cost this screen is
## nothing, because the list was ALREADY in a bounded scroll (`LIST_H`) — see `_mode`
## for why that bound is a height budget rather than a style choice, and
## `slice_test_outfitter` for the assertion that eighteen rows still do not grow the panel.
var _pool: Array = []
## `id -> SpellDef` over `_pool`. `equipped_id` hands back an id and every row, the slot
## line and the summary all need the def behind it.
var _pool_by_id: Dictionary = {}
## Which list the bounded scroll is showing. `HAND` is the screen exactly as it was.
##
## ⚠ A MODE, NOT A FIFTH SECTION, AND THAT IS A HEIGHT BUDGET RATHER THAN A TASTE CALL.
## `slice_test_outfitter` measures this column at 331 px in role mode and 338 px in the
## other two against a 360 px base viewport, so the whole screen has 22 px of slack —
## less than one `MIN_TAP` row (30) plus its separation (4). A grimoire list added BELOW
## the role list would have hung a phone's bottom button off the bottom of the phone,
## which no desktop playtest ever shows. Swapping the contents of the bounded scroll costs
## nothing, and the door into it shares the Armory's row.
##
## ⚠ AND THE THIRD MODE PAID EXACTLY THE SAME PRICE — ZERO. Three colour pickers as
## inline rows would have cost 3 x 34 = 102 px against 22 px of slack; as a MODE they cost
## one more button on a row that was already there. `_grimoire` became `_mode` rather than
## a second boolean, because two booleans have FOUR states and two of them (both true, and
## "which one wins") are states this screen has no drawing for.
enum Mode { HAND, GRIMOIRE, COLOURS }
var _mode: int = Mode.HAND
## WHICH SLOT THE NEXT PICK LANDS IN. The grimoire overlays by index, so a pick needs a
## slot before it needs a spell — the fixed row under the list names it and cycles it.
var _grim_slot: int = 0
var _grim_btn: Button = null
var _reset_btn: Button = null

# ── the colours ───────────────────────────────────────────────────────────────
## WHICH PART THE NEXT COLOUR LANDS ON. The grimoire's `_grim_slot` verbatim, and for the
## identical reason: a colour has no way to imply which of three regions it is for, so the
## pick needs a target before it needs a colour. The fixed row under the list names the
## part and cycles it; the list under it is then unambiguously "colours for THAT part".
##
## The alternative — fifteen rows, three parts x five colours — was rejected on the same
## grounds the grimoire rejected a twelve-state cycling row: a scroll where every third
## row repeats the same five names is a list a thumb gets lost in.
var _colour_part: int = 0
var _colour_btn: Button = null
## THE FIGURE, LIVE, BESIDE THE PANEL. See `_build_preview` — it is an OVERLAY and not a
## column row, which is the only reason it costs zero of the 22 px.
var _preview: Control = null
var _preview_rig: Node2D = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pool = SpellLibrary.equippable()
	for s: Variant in _pool:
		_pool_by_id[String((s as SpellDef).id)] = s
	# THE DISK IS AUTHORITATIVE ON OPEN. `GameState` hydrates `part_colourways` from
	# `user://climber.json` in its own `_ready`, so by the time a player can reach this
	# screen it holds last session's figure. Reading it into the static here is what makes
	# the picker open showing what the player IS rather than what the process defaulted to.
	# See `chosen_parts` for why there are two homes.
	_hydrate_colours()
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

	# THE SIDE DOORS AND THE UNDO, ALL ON ONE ROW.
	#
	# ⚠ THE ARMORY WENT BACK TO HALF WIDTH, AND THE RULING THAT WIDENED IT IS UPDATED
	# RATHER THAN DELETED. It shared this row with the colourway picker; when that was
	# cut it took the full width because the extra tap area was free. The grimoire is not
	# free — the column has 11 px of slack against a 360 px phone (see `_mode`), so a
	# row of its own was never available. Sharing this one costs ZERO height, and a
	# half-width `MIN_TAP` button is still 158x30, which is a comfortable thumb. The
	# earlier ruling held while this row had one occupant; it has two again.
	#
	# ⚠ AND NOW THREE, FOR THE SAME REASON AND AGAINST A TIGHTER NUMBER. Maker: *"also add
	# a reset to default button to the grimoire"*. `slice_test_outfitter` measures this
	# column at 331 px in role mode and **338 px in grimoire mode** against a 360 px base
	# viewport, so the slack is 22 px — a row of its own is `MIN_TAP` (30) plus the
	# separation (4) = 34, which walks the Done button off the bottom of a phone. Thirds
	# cost NOTHING in height. A third of the panel is 104x30, which is still a comfortable
	# thumb and still clears `MIN_TAP`, the floor this screen's suite pins on every button.
	#
	# ⚠ WHY THE RESET IS SHOWN IN **BOTH** MODES rather than only inside the grimoire the
	# maker named it for: see `_reset_to_defaults` — it clears both halves of the hand,
	# because a button reading "reset" that left half the hand overridden would be lying on
	# the one line (`_summary`) the player can check it against.
	var doors := HBoxContainer.new()
	doors.add_theme_constant_override("separation", 4)
	# A third each, and allowed to STRETCH: `_button` sets a minimum, the expand flag
	# spends whatever the panel actually has. Sizing by minimum alone would leave the row
	# short of PANEL_W and the three buttons visibly not filling their own frame.
	# ⚠ THE ARMORY DOOR IS GONE FROM THE CLASS-CHANGING FLOW, AND THE MAKER ASKED TWICE.
	# Verbatim, 2026-09-05: *"no need for an armoury button within the chaning class
	# selection"*.
	#
	# WHICH FLOW LOST IT: the TOWN one — `show_class_picker == true`, the Outfitter the
	# class pad opens, the screen whose header button walks the roster. In the town the
	# armoury is its OWN pad twenty metres away (`World.ARMORY_X`, the rack), so the door
	# here was a second entrance to a room the player is already standing outside.
	#
	# WHICH FLOW STILL HAS IT: the LOBBY one — `show_class_picker == false`, the title
	# screen's Outfitter. That screen has no pads and no hub to walk, so this button is
	# the ONLY way to the armoury from there. Removing it everywhere would have deleted
	# the room rather than the duplicate door.
	#
	# The row keeps its thirds arithmetic either way: with two occupants they simply take
	# half each through `SIZE_EXPAND_FILL`, which costs no height, and the height budget
	# (see the 22 px note above) is what this row is judged on.
	#
	# ⚠ AND NOW A FOURTH DOOR ON THE SAME ROW, WHICH IS WHY THE ARITHMETIC IS COMPUTED
	# RATHER THAN THE WORD "third". Maker: *"i should also be able to change the colour of
	# my stickman figure the colour of his head body and legs individually"* — three
	# pickers, which as inline rows would cost 3 x 34 = 102 px against 22 px of slack. As
	# one more door onto a mode they cost NOTHING in height, and height is the only axis
	# this screen is short of. `_door_count` is what decides the share, so the town flow
	# (no armoury door — see below) still gets fat thirds and only the lobby flow pays
	# quarters. At 4 the share is 77 px, which still clears `MIN_TAP` on the axis that
	# matters (`MIN_TAP` is a HEIGHT floor) and still fits "↺ Reset Hand" once the row
	# steps down one font size — see `_door_font`.
	var share: float = (PANEL_W - 4.0 * float(_door_count() - 1)) / float(_door_count())
	var fs: int = _door_font()
	_grim_btn = _button("", _toggle_grimoire, fs, share)
	_grim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doors.add_child(_grim_btn)
	if not show_class_picker:
		var armory: Button = _button("†  Armory", _open_armory, fs, share)
		armory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		doors.add_child(armory)
	_colour_btn = _button("", _toggle_colours, fs, share)
	_colour_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doors.add_child(_colour_btn)
	# The word says WHAT it resets, not merely that it resets. "Reset" alone on a screen
	# carrying a class button, a role list, a grimoire and an armoury door is a button
	# whose blast radius a player has to find out by pressing it.
	#
	# ⚠ AND IT NOW RESETS WHAT THE MODE IS ABOUT — see `_reset_pressed`. One button, two
	# blast radii, and the label always names the live one.
	_reset_btn = _button("×  Reset Hand", _reset_pressed, fs, share)
	_reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doors.add_child(_reset_btn)
	col.add_child(doors)

	col.add_child(_button("Done", close, 14))

	# LAST, AND OUTSIDE THE COLUMN ENTIRELY. See `_build_preview`.
	_build_preview()


## HOW MANY DOORS SHARE THE BOTTOM ROW. The grimoire, the colours and the reset always;
## the armoury only in the LOBBY flow (the town has its own rack pad twenty metres away —
## see the block above). Derived rather than written down twice, so the width share and
## the font step below cannot disagree with what is actually built.
func _door_count() -> int:
	return 3 if show_class_picker else 4


## ONE SIZE DOWN WHEN THE ROW IS FULL. At three doors the share is 104 px and font 12 is
## comfortable; at four it is 77 px and "↺  Reset Hand" at 12 clips its last character.
## Dropping the row (not the screen) to 11 buys ~6 px of text and costs no height at all,
## because `_button` pins `MIN_TAP` regardless of the font.
func _door_font() -> int:
	return 12 if _door_count() <= 3 else 11


## ══ THE FIGURE, LIVE, BESIDE THE PANEL ════════════════════════════════════════
## Five colour NAMES do not tell you what a stickman with an Ember head and Void legs
## looks like, and this screen's whole job in colours mode is that question.
##
## ⚠ IT IS AN OVERLAY, NOT A COLUMN ROW, AND THAT IS THE ENTIRE REASON IT EXISTS.
## `slice_test_outfitter` judges `_col.get_combined_minimum_size().y` against 360 px and
## the slack is 22 px, so a preview INSIDE the column — at any useful size — is refused by
## the suite before a player ever sees it. Anchored to the viewport centre instead, it
## participates in no layout, contributes nothing to any minimum size, and the measured
## column is identical with it and without it.
##
## HEIGHT IS SCARCE; WIDTH IS NOT. The panel is `PANEL_W` + two `PANEL_PAD_X` = 340 wide
## in a 640 base viewport, so 150 px sit unused on each side. The box is placed in the
## left one: 320 - 170 - 16 - 104 = 30 px from the screen edge. It is anchored to 0.5/0.5
## rather than to the left edge so it stays glued to the PANEL on a wider window instead
## of drifting away from it.
##
## ⚠ AND IT IS NOT PARENTED TO THE PANEL, which would have been the obvious move and is
## the wrong one: `CenterContainer` centres its children, `PanelContainer` sizes to its
## child, and either would have shoved the card off-centre by half the preview the moment
## the box appeared. The screen must not jump when a door is opened.
func _build_preview() -> void:
	_preview = Control.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_preview.anchor_left = 0.5
	_preview.anchor_right = 0.5
	_preview.anchor_top = 0.5
	_preview.anchor_bottom = 0.5
	_preview.offset_left = -(PANEL_W * 0.5 + PANEL_PAD_X + PREVIEW_GAP + PREVIEW_W)
	_preview.offset_right = -(PANEL_W * 0.5 + PANEL_PAD_X + PREVIEW_GAP)
	_preview.offset_top = -PREVIEW_H * 0.5
	_preview.offset_bottom = PREVIEW_H * 0.5
	_preview.draw.connect(_on_preview_draw)
	add_child(_preview)
	# The rig is a plain Node2D child: it draws itself every frame off its own
	# `_physics_process`, so there is no advance loop to own here. `Loadout` builds its
	# paper doll the same way, down to the scale-rather-than-height sizing — `height` is
	# what the gear geometry is derived from, so scaling the node keeps every proportion
	# the fighting figure has instead of re-deriving them at a new size.
	var rig: Node2D = RigScript.new() as Node2D
	rig.position = Vector2(PREVIEW_W * 0.5, PREVIEW_FEET_Y)
	rig.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_preview.add_child(rig)
	_preview_rig = rig


## The box the figure stands in. Same ground and same 1 px rule as the armoury's doll, so
## the two previews read as the same object seen on two screens.
func _on_preview_draw() -> void:
	if _preview == null:
		return
	var r := Rect2(Vector2.ZERO, _preview.size)
	_preview.draw_rect(r, Color(0.10, 0.11, 0.16, 0.85), true)
	_preview.draw_rect(r, HudStyle.with_a(_accent(), 0.5), false, 1.0)


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


## `width` defaults to the full panel; the paired bottom row passes half. The HEIGHT is
## never a parameter — `MIN_TAP` is the floor `slice_test_outfitter` pins on every button
## on this screen, and a caller allowed to shrink it is how that floor stops being one.
func _button(text: String, cb: Callable, font_size: int = 13,
		width: float = PANEL_W) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, MIN_TAP)
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
	# ...and neither would a POOL spell: the grimoire is per class, so the spell that was
	# focused for the Arcanist is not in the Swordsaint's slots. The slot cursor goes back
	# to 1 for the same reason — a cursor pointing at slot 3 of a class you just left is a
	# pick aimed at a hand the player has not looked at yet.
	_focus_spell = null
	_focus_reason = ""
	_grim_slot = 0
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
	# THE SAME BOUNDED SCROLL, THREE LISTS. See `_mode` for why this is a swap and not
	# a second section — and then a third one.
	match _mode:
		Mode.GRIMOIRE:
			for spell: Variant in _pool:
				_list.add_child(_pool_row(spell as SpellDef))
		Mode.COLOURS:
			# One row per colourway, for the ONE part the cursor is aiming at. The palette
			# is read off `Hero` at runtime (see `colourways`), so a colour edited there is
			# a row shown here and this list cannot name a colour that no longer exists.
			var palette: Array = colourways()
			for i: int in palette.size():
				_list.add_child(_colour_row(i, palette[i] as Color))
		_:
			for role: String in SpellLibrary.choosable_roles_for_class(_class_id):
				_list.add_child(_role_row(role, _carried.has(role), true))
	if _ult_slot_row != null:
		for child: Node in _ult_slot_row.get_children():
			_ult_slot_row.remove_child(child)
			child.queue_free()
		# THE FIXED ROW CARRIES THE MODE'S ONE UNCHOOSABLE FACT. In role mode that is the
		# ult; in grimoire mode it is WHICH SLOT the next pick lands in, which a pick by
		# index cannot be made without; in colours mode it is WHICH PART, for exactly the
		# same reason — a colour implies no target either. All three are one row of fixed
		# space under a scrolling list, which is what this shelf was built to hold.
		match _mode:
			Mode.GRIMOIRE:
				_ult_slot_row.add_child(_slot_cursor_row())
			Mode.COLOURS:
				_ult_slot_row.add_child(_part_cursor_row())
			_:
				_ult_slot_row.add_child(_role_row(_ult_role, true, false))
	_refresh_summary()
	_refresh_class_btn()
	_refresh_grim_btn()
	_refresh_colour_btn()
	_refresh_reset_btn()
	_refresh_preview()


## One role, as a thumb-sized row. The ult row is `enabled == false`: a class authors
## exactly one ult and the last slot only accepts an ult, so there is nothing to
## decide there — showing it anyway is what makes the hand read as three.
func _role_row(role: String, carried: bool, enabled: bool) -> Button:
	var spell: SpellDef = SpellLibrary.spell_for_role(_class_id, role)
	var tier: int = SpellTier.of(spell) if spell != null else SpellTier.Tier.QUICK
	var mark: String = CARRIED_MARK if carried else PLAIN_MARK
	# ⚠ A ROLE ROW SHOWS WHAT THE SLOT ACTUALLY CASTS, NOT WHAT THE CLASS AUTHORED.
	# `build_for_class` lays the grimoire over the role LAST and by index, so with a Tier 3
	# equipped this row's authored name is the one name on the screen that is not true —
	# and it is the row the player taps to change their hand. `‡` plus GOLD is the same
	# badge the pool list and the summary use, so the rare thing reads the same everywhere.
	var over: SpellDef = _equipped_in_slot(_slot_of_role(role))
	if over != null:
		spell = over
		tier = SpellTier.of(over)
		mark = RARE_BADGE
	var b := Button.new()
	b.text = "%s  %s  ·  %s" % [mark, role.to_upper(), spell.display_name if spell != null else "--"]
	b.tooltip_text = SpellTier.display_name(tier)
	b.custom_minimum_size = Vector2(PANEL_W - 16.0, MIN_TAP)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	# The shelf, in the colour the whole game badges shelves with — so "this is my
	# ult" is readable without reading. GOLD outranks the shelf colour when the slot is
	# equipped: `HudStyle.GOLD` is already what the ability bar badges an ult with, and an
	# equipped Tier 3 is the loudest, rarest thing on the hand.
	var ink: Color = SpellTier.color(tier) if carried else GRAPHITE
	if over != null:
		ink = HudStyle.GOLD
	b.add_theme_color_override("font_color", ink)
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
	_focus_reason = ""
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
	# The POOL focus is dropped rather than kept: the question this tap asked is about a
	# role, and `_refresh_blurb` resolves a role to whatever its slot actually casts.
	_focus_role = role
	_focus_spell = null
	_focus_reason = ""
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
	_persist()


## THE ONE SAVE CALL, SHARED BY BOTH MECHANISMS. `SpellLibrary.persist_to_state` writes
## `spell_roles` AND `spell_equipped` in one pass, so a grimoire pick that forgot to call
## it would not merely fail to save itself — it would leave the equipped table one write
## behind the roles table on disk. Reached through the tree, never as a bare global, so
## this script stays loadable in a headless harness with no autoloads registered.
func _persist() -> void:
	SpellLibrary.persist_to_state(get_node_or_null("/root/GameState"))


# ══════════════════════════════════════════════════════════════════ the grimoire
## PICK A SLOT, THEN PICK A SPELL, AND TAP IT AGAIN TO TAKE IT BACK OUT.
##
## Two taps, because the grimoire overlays BY INDEX and a Tier 3 belongs to no class's
## role table — there is no role for it to imply a slot through. The alternatives were
## both worse on a phone: cycling one row through twelve states (authored plus eleven
## spells) is a tap target that never tells you where it is going, and a nested
## slot-then-pool screen is a third modal on a screen already able to open two.
##
## The slot cursor is the fixed row under the list, so both halves of the decision are on
## screen at once, and the summary line already names all four slots and what is in them.


## Which slot a role occupies, or -1 for a role this class authors but does not carry.
##
## Read from `SpellLibrary.slot_roles_for_class` rather than from `_carried`, and that is
## load-bearing: `slot_roles_for_class` is the exact array `build_for_class` walks to
## build the hero's hand, so a slot index derived from it cannot disagree with the slot
## the grimoire overlay lands on. `_carried` is this screen's working copy and is one
## `_commit` behind during a toggle.
func _slot_of_role(role: String) -> int:
	var roles: Array = SpellLibrary.slot_roles_for_class(_class_id)
	for i: int in roles.size():
		if String(roles[i]) == role:
			return i
	return -1


func _role_of_slot(slot: int) -> String:
	var roles: Array = SpellLibrary.slot_roles_for_class(_class_id)
	if slot < 0 or slot >= roles.size():
		return ""
	return String(roles[slot])


## The pool spell overlaying `slot`, or null for "this slot casts what the class
## authored". Resolved through `_pool_by_id` rather than by rebuilding the pool, and a
## `null` for an id the pool has never heard of — a save written by a build where a spell
## was since renamed reaches this function, and a missing row must read as "not equipped"
## rather than crash a town screen.
func _equipped_in_slot(slot: int) -> SpellDef:
	if slot < 0:
		return null
	var id: String = SpellLibrary.equipped_id(_class_id, slot)
	if id == "":
		return null
	return _pool_by_id.get(id) as SpellDef


## What a slot ACTUALLY casts: the overlay if there is one, else the authored role spell.
## The same order `SpellLibrary.build_for_class` applies, restated here because this
## screen needs it per-slot and that one only hands back the finished array.
func _slot_spell(slot: int) -> SpellDef:
	var over: SpellDef = _equipped_in_slot(slot)
	if over != null:
		return over
	var role: String = _role_of_slot(slot)
	return SpellLibrary.spell_for_role(_class_id, role) if role != "" else null


## The door. Swaps which list the bounded scroll is showing; see `_mode`.
##
## ⚠ EACH DOOR TOGGLES ITS OWN MODE AGAINST `HAND`, RATHER THAN THE THREE CYCLING. A
## cycler would have cost no button at all, and was rejected: the label can only ever name
## ONE destination, so reaching the colours from the hand would have flashed the whole
## grimoire on the way past — a list of eighteen spells appearing for one tap, on the way
## to picking a colour. Two doors that each go somewhere and come back is what a player
## can predict.
func _toggle_grimoire() -> void:
	_set_mode(Mode.HAND if _mode == Mode.GRIMOIRE else Mode.GRIMOIRE)


## The other door. Same shape, same rules, different list.
func _toggle_colours() -> void:
	_set_mode(Mode.HAND if _mode == Mode.COLOURS else Mode.COLOURS)


## ONE PLACE THAT CHANGES THE MODE, so the focus-clearing rules cannot be applied by one
## door and forgotten by the other. The blurb follows the door exactly as it follows a
## row: arriving in a new list with the previous mode's sentence still on screen would be
## a line describing something that is no longer under it.
func _set_mode(next: int) -> void:
	_mode = next
	_focus_spell = null
	_focus_reason = ""
	match _mode:
		Mode.GRIMOIRE:
			_focus_slot(_grim_slot)
		Mode.COLOURS:
			# There is no `SpellDef` behind a colour, so the description line is written
			# rather than looked up — see `_refresh_blurb`, which checks the mode BEFORE
			# it resolves a role. Clearing the role is what stops the previous mode's
			# spell sentence surviving into a screen with no spells on it.
			_focus_role = ""
		_:
			_focus_role = ""
	_redraw()
	_sfx("ding", -8.0)


func _refresh_grim_btn() -> void:
	if _grim_btn == null:
		return
	# The word is on it for the same reason "change" is on the class button: the glyph
	# says WHICH thing, nothing in a glyph says the row is a door, and this one sits
	# beside another door that goes somewhere else entirely.
	var here: bool = _mode == Mode.GRIMOIRE
	_grim_btn.text = "«  Your Hand" if here else "»  Grimoire"
	_grim_btn.add_theme_color_override("font_color", CHALK if here else HudStyle.GOLD)


## Point the description line at whatever a slot currently casts.
func _focus_slot(slot: int) -> void:
	var over: SpellDef = _equipped_in_slot(slot)
	_focus_spell = over
	_focus_role = "" if over != null else _role_of_slot(slot)
	_focus_reason = ""
	_refresh_blurb()


## THE SLOT CURSOR. Names the slot the next pick lands in, shows what is in it now, and
## cycles on tap. Four states, wrapping — short enough that a player finds the slot they
## want by tapping rather than by reading, which is the only interaction model that
## survives having no hover and no keyboard.
func _slot_cursor_row() -> Button:
	var spell: SpellDef = _slot_spell(_grim_slot)
	var over: bool = _equipped_in_slot(_grim_slot) != null
	var b := Button.new()
	# ⚠ THE CURSOR NAMES THE SHELF, because the list under it is now half ults and the rule
	# is about shelves. Aiming slot 1 at a list where every other row reads "(slot 4 only)"
	# is only legible if slot 4 is visibly THE ULT SLOT — without this the player has two
	# unrelated facts on screen and has to guess that they are the same fact. It costs six
	# characters on a row that already clips.
	var shelf: String = " · ULT" if _grim_slot == SpellTier.ULT_SLOT else ""
	b.text = "%s  EQUIP INTO SLOT %d%s ›  %s" % [
		RARE_BADGE if over else PLAIN_MARK, _grim_slot + 1, shelf,
		String(spell.display_name) if spell != null else "--"]
	b.tooltip_text = "Tap to aim at the next slot — only slot %d takes an ULT" \
		% (SpellTier.ULT_SLOT + 1)
	b.custom_minimum_size = Vector2(PANEL_W - 16.0, MIN_TAP)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.add_theme_color_override("font_color", HudStyle.GOLD if over else HudStyle.SKY)
	b.pressed.connect(_cycle_grim_slot)
	return b


func _cycle_grim_slot() -> void:
	_grim_slot = (_grim_slot + 1) % SpellTier.SLOT_COUNT
	_focus_slot(_grim_slot)
	_redraw()
	_sfx("ding", -10.0)


## ══ ONE ULT, AND IT GOES IN THE ULT SLOT ══════════════════════════════════════
## Maker: *"all the ults in the grimoire should only be able to be swapped with the
## existing ult, no one can have multiple ults"*. `SpellLibrary.set_equipped` is where
## that ruling is ENFORCED (it returns false for an ult aimed anywhere but
## `SpellTier.ULT_SLOT`); this is where the same ruling is DRAWN.
##
## ⚠ THE TWO HAVE TO AGREE, AND ONLY ONE OF THEM MAY OWN THE RULE. So this asks the same
## question from the same numbers — `SpellTier.of` derives the shelf from cast time,
## cooldown and mana — rather than keeping a list of which ids are ults. Re-tune a Tier 2
## up into ult territory and the library starts refusing it and this screen starts dimming
## it, from the one edit. A hardcoded list here would drift and the drift would look like
## a button that does nothing.
##
## Note the asymmetry is deliberate and matches the library: an ULT may only go in the ult
## slot, but a NON-ult may go anywhere including the ult slot. Nobody asked for a hand that
## is forbidden a fourth ordinary spell; what was asked for was that nobody carries four
## finishers.
func _can_equip_here(spell: SpellDef) -> bool:
	if spell == null:
		return false
	return SpellTier.of(spell) != SpellTier.Tier.ULT or _grim_slot == SpellTier.ULT_SLOT


# ══ OWNERSHIP — A DIFFERENT AXIS FROM THE SHELF, DELIBERATELY ═════════════════
## Maker: *"the grimoire is cool but still not clear what is unlockable and what isnt …
## and how to unlock it"*.
##
## ⚠ THIS DOES NOT TOUCH THE ULT RULE AND MUST NOT. `_can_equip_here` answers WHICH SHELF
## a spell may sit on and is owned by `SpellLibrary.set_equipped`; this answers WHETHER
## THE SPELL IS YOURS AT ALL. A spell can fail either, both, or neither, and the row has
## to say which — so the two reasons are separate strings and the shelf one wins the
## caption when both apply (it is the one the slot cursor can fix in one tap).
##
## ⚠ ENFORCED HERE AND NOT IN THE LIBRARY, which is the opposite of the ult rule and is
## the right cut. `SpellLibrary` is pure and knows nothing about a climb; teaching it the
## floor you reached would put a save-shaped dependency inside the one file every hero is
## built through. The grimoire is the ONLY door into `set_equipped` for a player, so the
## door is where the gate belongs — and a spell already in the hand is grandfathered
## (`Progression.spell_state`'s `already_equipped`) so no gate can ever eat a save.
func _spell_state(spell: SpellDef) -> int:
	if spell == null:
		return Progression.Owned.HELD
	var id: String = String(spell.id)
	var equipped_now: bool = false
	for i: int in SpellTier.SLOT_COUNT:
		if SpellLibrary.equipped_id(_class_id, i) == id:
			equipped_now = true
			break
	var gs: Node = get_node_or_null("/root/GameState")
	var best: int = int(gs.call("highest_floor")) if gs != null and gs.has_method("highest_floor") else 1
	return Progression.spell_state(SpellTier.of(spell), best, equipped_now)


## The sentence an UNEARNED row puts on the description line. Names the verb, because the
## maker's ask was *how* to unlock it and "locked" on its own answers nothing.
func _unowned_reason(spell: SpellDef) -> String:
	return "NOT YOURS YET — %s. The tower is where the library opens." \
		% Progression.spell_unlock_verb(SpellTier.of(spell))


## The sentence a blocked row puts on the description line instead of its blurb. Names the
## slot by the number the cursor row shows (1-based), so the two rows agree on screen.
func _blocked_reason() -> String:
	return "ULT — a hand carries ONE, and it goes in slot %d. Aim the slot cursor there." \
		% (SpellTier.ULT_SLOT + 1)


## One pool spell, as a thumb-sized row. Marked `◈` and GOLD when it is the spell in the
## slot the cursor is aiming at — so the row that is already yours is the row that takes
## it back out, which is the same tap-again-to-undo gesture the role list uses.
func _pool_row(spell: SpellDef) -> Button:
	if spell == null:
		return Button.new()
	var id: String = String(spell.id)
	var mine: bool = SpellLibrary.equipped_id(_class_id, _grim_slot) == id
	# Equipped ELSEWHERE in this class's hand. Shown, because a player who has put Meteor
	# Storm in slot 2 and is now aiming at slot 3 needs to know it is already spoken for —
	# without it, the same spell can be put in two slots and the hand quietly loses one.
	var elsewhere: int = -1
	for i: int in SpellTier.SLOT_COUNT:
		if i != _grim_slot and SpellLibrary.equipped_id(_class_id, i) == id:
			elsewhere = i
			break
	var tier: int = SpellTier.of(spell)
	# ⚠ A ROW THAT CANNOT BE TAKEN MUST NOT LOOK LIKE A ROW THAT CAN. Before this, every
	# ult in the pool drew exactly like every other row while aiming slots 1-3, and the tap
	# reached `set_equipped`, was refused, and NOTHING HAPPENED — no movement, no message.
	# On a phone that reads as a broken button, and the player's only way to discover the
	# rule is to tap every ult in the list and watch nothing happen to any of them.
	# OWNERSHIP is the second reason a row can refuse — see `_spell_state`. It is folded
	# into the SAME `blocked` path rather than given a new one, because the row already
	# has a correct treatment for "cannot be taken, and here is why": dim, disabled,
	# `MOUSE_FILTER_PASS`, tap-says-why. A second mechanism would be a second thing to
	# keep in step for no gain.
	var unowned: bool = _spell_state(spell) != Progression.Owned.HELD
	var blocked: bool = not _can_equip_here(spell) or unowned
	var b := Button.new()
	var suffix: String = "" if elsewhere < 0 else "  (slot %d)" % (elsewhere + 1)
	# The reason is IN THE ROW, not only in the colour: "dimmed" says *something* is wrong
	# and a phone has no hover to ask what. The slot number is the answer and it is four
	# characters, which the row has room for even at `clip_text`.
	if not _can_equip_here(spell):
		suffix = "  (slot %d only)" % (SpellTier.ULT_SLOT + 1)
	elif unowned:
		# The SHELF reason wins the caption when both apply: it is the one the player can
		# clear in one tap of the slot cursor, so it is the one worth six characters.
		suffix = "  — %s" % Progression.spell_unlock_verb(tier)
	b.text = "%s  %s  ·  %s%s" % [
		RARE_BADGE if mine else ("×" if blocked else PLAIN_MARK), String(spell.display_name),
		SpellTier.display_name(tier), suffix]
	b.tooltip_text = _row_reason(spell) if blocked else SpellBlurbs.for_spell(spell)
	b.custom_minimum_size = Vector2(PANEL_W - 16.0, MIN_TAP)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	var ink: Color = GRAPHITE
	if mine:
		ink = HudStyle.GOLD
	elif elsewhere >= 0:
		ink = HudStyle.with_a(HudStyle.GOLD, 0.55)
	if blocked:
		# Dimmer than the plain unequipped row, and dimmer than "equipped elsewhere" — the
		# three states are then ordered by ink: yours, spoken for, not available here.
		ink = HudStyle.with_a(GRAPHITE, 0.40)
	b.add_theme_color_override("font_color", ink)
	if blocked:
		# ⚠ `disabled` AND `MOUSE_FILTER_PASS`, the same pairing the fixed ult ROLE row uses
		# a hundred lines up and for the same reason: a disabled Button emits NOTHING — not
		# `pressed`, not `gui_input` — so refusing the tap outright would also refuse the
		# question. `disabled` goes on refusing to EQUIP it; `PASS` lets the tap reach this
		# row's own handler and say why. Reading is not choosing.
		#
		# It is also what makes the refusal testable through the real button: `_toggle_equip`
		# is never CONNECTED here, so a suite that emits `pressed` on this row proves nothing
		# moved because nothing is listening — rather than proving the library said no.
		b.disabled = true
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.gui_input.connect(_on_blocked_row_input.bind(id))
		b.modulate = Color(1.0, 1.0, 1.0, 0.85)
	else:
		b.pressed.connect(_toggle_equip.bind(id))
	return b


## Tapping a blocked pool row changes nothing and SAYS SO. The description line carries the
## reason rather than the blurb, because the question a player asks by tapping a row that
## looks unavailable is "why", not "what does it do".
func _on_blocked_row_input(event: InputEvent, spell_id: String) -> void:
	var tap: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not tap:
		return
	_focus_spell = _pool_by_id.get(spell_id) as SpellDef
	_focus_role = ""
	_focus_reason = _row_reason(_focus_spell)
	_refresh_blurb()


## WHY THIS ROW REFUSED — the shelf reason or the ownership one, whichever applies. The
## shelf is checked first for the same reason it wins the caption: it is the fixable one.
func _row_reason(spell: SpellDef) -> String:
	if spell == null:
		return ""
	if not _can_equip_here(spell):
		return _blocked_reason()
	return _unowned_reason(spell)


## Put this spell in the aimed slot, or take it back out if it is already there.
##
## A TAP ALWAYS DOES SOMETHING, the same rule `_toggle_role` is built on: there is no
## separate "clear" button, because a clear button on a phone is a second target for a
## decision the player already has their thumb on.
func _toggle_equip(spell_id: String) -> void:
	# The tap that changes the slot is also the tap that asks what the spell does.
	_focus_spell = _pool_by_id.get(spell_id) as SpellDef
	_focus_role = ""
	_focus_reason = ""
	if SpellLibrary.equipped_id(_class_id, _grim_slot) == spell_id:
		# `""` clears the slot back to the class's authored spell — see `set_equipped`.
		SpellLibrary.set_equipped(_class_id, _grim_slot, "")
	elif not SpellLibrary.set_equipped(_class_id, _grim_slot, spell_id):
		# Refused (an id outside the pool). Nothing moved — but the description still
		# lands, for the same reason the refused role DROP still describes itself: the one
		# row a player cannot act on must not also be the one row that says nothing.
		_refresh_blurb()
		return
	_persist()
	_redraw()
	_sfx("ding", -8.0)


## ══ BACK TO WHAT THE CLASS WAS AUTHORED WITH ═════════════════════════════════
## Maker: *"also add a reset to default button to the grimoire"*.
##
## ⚠ IT CLEARS **BOTH** MECHANISMS, AND THAT IS A DECISION WORTH THE PARAGRAPH. The obvious
## reading of the ask is `clear_equipped(_class_id)` alone — the button lives in the
## grimoire, so reset the grimoire. It is the wrong one, for a reason this screen makes
## visible: `_summary` is drawn straight from `build_for_class`, which carries the role
## picks AND the grimoire overlay. Clearing only half leaves that line showing a hand that
## is still not the default, one row under a button that just claimed to restore the
## default. The player has no way to tell which half a "reset" was supposed to mean; all
## they can see is that the button said default and the hand is not.
##
## So "default" means the thing the class shipped with: `SpellLibrary.SLOT_ROLES` for this
## class, with no overlay on any slot. Both tables, one class.
##
## ⚠ SCOPED TO ONE CLASS, DELIBERATELY. Both clear functions take `-1` to mean the whole
## roster and this passes neither. A player editing the Arcanist has said nothing about
## their Swordsaint, and a reset that silently wiped eight other hands is unrecoverable —
## there is no undo on this screen and the picks persist to disk on the very next line.
## ⚠ ONE BUTTON, TWO BLAST RADII, AND THE LABEL ALWAYS NAMES THE LIVE ONE.
##
## The row has no space for a fifth door (see `_door_count`), and a "Reset Hand" button
## sitting under a list of colours would be the one control on the screen that ignores
## the mode it is in — which on a phone reads as "this resets whatever I am looking at",
## which is exactly what a player would be wrong about. So the reset follows the mode,
## and `_refresh_reset_btn` renames it in the same `_redraw` that swapped the list.
##
## HAND and GRIMOIRE share one radius deliberately: `_reset_to_defaults` clears BOTH
## halves of the hand for the reason its own header gives, and the two modes are two views
## of one hand.
func _reset_pressed() -> void:
	if _mode == Mode.COLOURS:
		_reset_colours()
	else:
		_reset_to_defaults()


func _refresh_reset_btn() -> void:
	if _reset_btn == null:
		return
	_reset_btn.text = "×  Reset Colour" if _mode == Mode.COLOURS else "×  Reset Hand"


## ALL THREE PARTS BACK TO "NEVER CHOSEN", not to a hardcoded index. -1 is what makes a
## part resolve to `chosen_colourway` (see `part_colourway`), so a reset returns the
## figure to the ONE whole-figure colour the pause menu and the `C` key still drive —
## rather than to Azure, which would silently override a player's whole-figure pick with
## a "reset" they asked to undo their PART picks with.
func _reset_colours() -> void:
	chosen_parts = [-1, -1, -1]
	_persist_colours()
	_redraw()
	_sfx("ding", -6.0)


func _reset_to_defaults() -> void:
	SpellLibrary.clear_equipped(_class_id)
	SpellLibrary.clear_slot_roles(_class_id)
	# `refresh`, not `_redraw`: the ROLE list is seeded from `slot_roles_for_class` into
	# `_carried` and `_redraw` never re-reads it, so redrawing alone would leave this
	# screen's working copy of the hand standing over a library that had just been cleared —
	# and the next role tap would `_commit` the old hand straight back in.
	refresh()
	# Same save path every other pick on this screen takes: one call writing `spell_roles`
	# AND `spell_equipped` together, so the two tables cannot land on disk one write apart.
	_persist()
	_sfx("ding", -6.0)


## THE LINE THAT SAYS WHAT A SPELL DOES.
##
## Reads through `SpellBlurbs.for_spell`, so a `SpellDef` that ever authors its own
## `description` wins over the table -- see that file. Falls back to the class name
## rather than to an instruction, because an empty line here would read as a bug and a
## re-typed instruction is what this row used to be.
func _refresh_blurb() -> void:
	if _hint == null:
		return
	# A REFUSAL OUTRANKS A DESCRIPTION. The one tap on this screen that does nothing is the
	# one tap that has to explain itself, and "what this spell does" is not the question a
	# player asks by tapping a row that will not take. See `_focus_reason`.
	if _focus_reason != "":
		_hint.text = _focus_reason
		return
	# ⚠ COLOURS MODE HAS NO `SpellDef` TO DESCRIBE, so it is checked BEFORE the resolution
	# below rather than folded into it. Without this the line would fall through to "the
	# ult, if no role is focused" and put a spell description under a list of colours —
	# the exact stale-line bug `_focus_reason`'s own header was written about.
	#
	# ⚠ AND IT STAYS UNDER 96 CHARACTERS, which is not a style note. `_hint` reserves
	# exactly two lines (~71 chars each) so the panel measures the same height whatever is
	# on it; a third line grows the column and walks the Done button off a 360 px phone.
	# Longest case measured: "LEGS — legs and feet. Now Ember. Tap again to unpaint." = 54.
	if _mode == Mode.COLOURS:
		_hint.text = "%s — %s. Now %s. Tap again to unpaint." % [
			PART_NAMES[_colour_part], PART_COVERS[_colour_part],
			colourway_name(part_colourway(_colour_part))]
		return
	# A POOL spell is held directly (it has no role to be looked up by). A ROLE is
	# resolved LIVE — through the slot it occupies, so an equipped Tier 3 describes
	# itself rather than the authored spell it displaced, and so a re-ordered hand cannot
	# leave this line pointing at the slot a role used to be in.
	var spell: SpellDef = _focus_spell
	if spell == null:
		var role: String = _focus_role if _focus_role != "" else _ult_role
		spell = _equipped_in_slot(_slot_of_role(role))
		if spell == null:
			spell = SpellLibrary.spell_for_role(_class_id, role)
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
	# ⚠ IN COLOURS MODE THIS LINE ANSWERS THE MODE'S QUESTION, NOT THE HAND'S. The cursor
	# row can only show ONE part at a time, so without this the screen never states the
	# figure as a whole — and "what does head Ember / body Void / legs Jade actually look
	# like together" is the entire reason the mode exists. Same Label, same one colour,
	# same constant height; the 360 px budget does not move.
	if _mode == Mode.COLOURS:
		var worn: Array[String] = []
		for i: int in PART_NAMES.size():
			worn.append("%s %s" % [PART_NAMES[i], colourway_name(part_colourway(i))])
		_summary.text = "   ·   ".join(worn)
		return
	# ⚠ `build_for_class` ALREADY CARRIES THE GRIMOIRE — it lays `_equipped` over the
	# authored hand last and by index — so this line has always been the honest readout of
	# what the hero will hold. What it could not say is which of the four are the rare
	# ones, and this is a plain `Label` (one colour for the whole line, and it must stay
	# one so its measured height is a constant). So the badge is a GLYPH: `◈` is the same
	# mark the role rows and the pool list use, and it is the only part of this row that
	# needs to survive being drawn in one colour.
	var built: Array = SpellLibrary.build_for_class(_class_id)
	var names: Array = []
	for i: int in built.size():
		var spell: Variant = built[i]
		if spell == null:
			continue
		var mark: String = RARE_BADGE if _equipped_in_slot(i) != null else ""
		names.append("%s%s" % [mark, String((spell as SpellDef).display_name)])
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
	_class_btn.text = "§  %s  ·  change" % _class_display_name()
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


# ══════════════════════════════════════════════ head, body and legs, separately
## WHICH COLOUR ONE PART IS WEARING, resolved. This is the FALLBACK CHAIN and it is the
## whole migration story in three lines:
##
##     the part's own pick  ->  the whole-figure `chosen_colourway`
##
## A player who has never opened this mode has three -1s and therefore three parts on the
## one colour they already had — so the picker opens showing what they ARE, and turning
## the mode on changes nothing until they tap. It is the same chain
## `GameState.colourway_parts` applies on the way to the hero, stated in both places
## because neither file may reach the other's state.
##
## ⚠ CLAMPED ON READ. `chosen_parts` is a static that outlives a scene change and
## `colourways()` is read off `Hero` at runtime, so a palette that shrinks between the two
## is a real sequence — and an unclamped index here is a crash on a town screen, not a
## wrong colour.
static func part_colourway(part: int) -> int:
	var count: int = maxi(colourways().size(), 1)
	if part < 0 or part >= chosen_parts.size():
		return clampi(chosen_colourway, 0, count - 1)
	var v: int = chosen_parts[part]
	return clampi(chosen_colourway if v < 0 else v, 0, count - 1)


## Read the saved figure out of `GameState` into the static. See `chosen_parts` for why
## there are two homes; this is the "disk is authoritative on open" half.
##
## Reached through the tree and shape-checked rather than trusted: this script has to stay
## loadable in a headless harness with NO autoloads, and `GameState.part_colourways` is a
## dictionary that has been through JSON — where every number comes back as a float. The
## `int()` is the M9 trap, and it is the same one `GameState.sanitize_part_colourways`
## guards on the other side.
func _hydrate_colours() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var raw: Variant = gs.get(&"part_colourways")
	if not (raw is Dictionary):
		return
	var out: Array[int] = [-1, -1, -1]
	for i: int in PART_KEYS.size():
		var v: Variant = (raw as Dictionary).get(PART_KEYS[i], -1)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			out[i] = maxi(int(v), -1)
	chosen_parts = out


## Mirror the static into `GameState`, which is what carries the pick to the HERO
## (`colourway_parts` at spawn) and to DISK (`_save_climber` writes `part_colourways`).
##
## `save_progress` is called by name only if it exists, the same defensive shape
## `_persist` uses for `SpellLibrary.persist_to_state`: a build without the autoload, or a
## suite that never registered it, must leave this screen working rather than erroring on
## every tap.
func _persist_colours() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	if not gs.has_method("set_colourway_part"):
		return
	for i: int in PART_KEYS.size():
		gs.call("set_colourway_part", PART_KEYS[i], chosen_parts[i])
	if gs.has_method("save_progress"):
		gs.call("save_progress")


## THE PART CURSOR. Names the part the next colour lands on, shows what it is wearing now,
## and cycles on tap. Three states, wrapping — the grimoire's `_slot_cursor_row` in every
## respect except what it is aiming at, because the problem is identical: a pick with no
## implied target, on a screen with no hover and no keyboard.
func _part_cursor_row() -> Button:
	var idx: int = part_colourway(_colour_part)
	var b := Button.new()
	b.text = "•  PAINT  %s ›  %s" % [PART_NAMES[_colour_part], colourway_name(idx)]
	b.tooltip_text = "Tap to aim at the next part — head, body, legs"
	b.custom_minimum_size = Vector2(PANEL_W - 16.0, MIN_TAP)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	# THE CURSOR IS DRAWN IN THE COLOUR IT IS POINTING AT. It is the one row on this screen
	# whose subject IS a colour, so naming it in chalk and showing the colour nowhere would
	# be a colour picker that never shows you a colour.
	b.add_theme_color_override("font_color", _swatch(idx))
	b.pressed.connect(_cycle_part_cursor)
	return b


func _cycle_part_cursor() -> void:
	_colour_part = (_colour_part + 1) % PART_KEYS.size()
	_redraw()
	_sfx("ding", -10.0)


## One colourway, as a thumb-sized row, for the part the cursor is aiming at. `◉` and the
## colour itself when it is the live pick — the same mark the role list uses for a carried
## role, so "this one is mine" reads the same everywhere on the screen.
func _colour_row(index: int, swatch: Color) -> Button:
	var mine: bool = part_colourway(_colour_part) == index
	var b := Button.new()
	# ⚠ THE SWATCH IS DRAWN, NOT TYPED, AND THAT IS A BUG FIX RATHER THAN A STYLE CHOICE.
	# This row used to read `"%s  %s  ·  %s   ███"` with `◉`/`○` for the state — and NOT
	# ONE of those three glyphs was ever drawn. `assets/ui/stickspire_theme.tres` declares
	# no font at all, so every control falls back to Godot's built-in Open Sans subset,
	# whose `has_char` is false for U+25C9, U+25CB and U+2588 alike. A colour picker was
	# shipping rows with no colour on them.
	#
	# So the hue is a StyleBoxFlat LEFT BORDER — the same primitive the class roster's
	# accent bar uses, for the same reason: it is a real drawn rectangle, it needs no
	# second control, and no font can fail to render it. The state mark falls back to
	# `•`/`·`, both of which ARE in the fallback font (verified, not assumed).
	b.text = "%s  %s  ·  %s" % [
		"•" if mine else "·", PART_NAMES[_colour_part], colourway_name(index)]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sb.border_color = _swatch(index)
	sb.set_border_width(SIDE_LEFT, 9.0 if mine else 5.0)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	b.tooltip_text = "Paint the %s %s" % [PART_NAMES[_colour_part].to_lower(),
		colourway_name(index)]
	b.custom_minimum_size = Vector2(PANEL_W - 16.0, MIN_TAP)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	# The unpicked rows draw in their own colour at half strength: bright enough that the
	# palette is visible at a glance, dim enough that the ONE row that is yours still wins.
	b.add_theme_color_override("font_color",
		_swatch(index) if mine else HudStyle.with_a(swatch, 0.55))
	b.pressed.connect(_pick_colour.bind(index))
	return b


## The colour a row/cursor draws its text in. Lightened, because `Hero.COLOURWAYS` is a
## palette of LIMB fills read against a stick figure, and the same value read as 12 px
## type on the near-black `PAPER` ground is a step too dark.
static func _swatch(index: int) -> Color:
	var palette: Array = colourways()
	if index < 0 or index >= palette.size():
		return CHALK
	return (palette[index] as Color).lightened(0.2)


## Paint the aimed part. A TAP ALWAYS DOES SOMETHING — the rule `_toggle_role` and
## `_toggle_equip` are both built on — so tapping the colour a part already wears is NOT a
## no-op: it puts the part back to -1, which hands it to the whole-figure colour. That is
## the same tap-again-to-undo gesture the other two lists use, and it is the only way to
## give a part back without a second control.
func _pick_colour(index: int) -> void:
	if _colour_part < 0 or _colour_part >= chosen_parts.size():
		return
	var parts: Array[int] = chosen_parts.duplicate()
	parts[_colour_part] = -1 if chosen_parts[_colour_part] == index else index
	chosen_parts = parts
	_persist_colours()
	_redraw()
	_sfx("ding", -8.0)


func _refresh_colour_btn() -> void:
	if _colour_btn == null:
		return
	var here: bool = _mode == Mode.COLOURS
	_colour_btn.text = "«  Your Hand" if here else "•  Colours"
	# Tinted with the BODY's live colour rather than a house accent, so the door advertises
	# what is behind it — the same argument that puts the class colour on the card frame.
	_colour_btn.add_theme_color_override("font_color",
		CHALK if here else _swatch(part_colourway(1)))


## THE FIGURE FOLLOWS EVERY TAP. Shown only in colours mode — everywhere else it is a
## stickman standing beside a list of spell names, answering a question nobody asked.
##
## ⚠ `set_part_tints`, NOT THREE `set_tint` CALLS. `CharacterRig.set_tint` is documented
## as "paint the whole figure" and CLEARS the per-part overrides, so three of them in a
## row would leave the figure in the last colour passed. See that function's header.
func _refresh_preview() -> void:
	if _preview == null:
		return
	_preview.visible = _mode == Mode.COLOURS
	_preview.queue_redraw()
	if _preview_rig == null or not _preview.visible:
		return
	var palette: Array = colourways()
	if palette.is_empty():
		return
	_preview_rig.call("set_part_tints",
		palette[part_colourway(0)] as Color,
		palette[part_colourway(1)] as Color,
		palette[part_colourway(2)] as Color)


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
