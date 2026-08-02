# THE DIRECTOR — the review rig.
# ============================================================================
#
# ⚠ THIS FILE LIVES IN `res://tools/` AND THAT IS LOAD-BEARING, NOT TIDINESS.
# `export_presets.cfg` excludes `res://tools/*` from the pack, so this script is
# not present in an exported build at all. `PauseMenu.director_available()`
# therefore finds nothing and never builds a row. That absence is the PRIMARY
# ship gate; `OS.is_debug_build()` is the second, independent one. Both are
# asserted by `tools/release_gate_dev_bridge.gd`.
#
# It has NO `class_name` on purpose. A global class registered from an excluded
# script is a dangling entry in the class cache at export time, and the whole
# point of this file is that its absence is uneventful. It is reached by
# `load()` + duck typing, exactly like `VersusArena._probe_begin` reaches its
# probe script.
#
# ---------------------------------------------------------------------------
# WHY IT EXISTS
#
# Nobody has ever played this game. The first review session has to judge 22+
# spells, 9 classes, 8 enemy archetypes, 4 bosses and 6 modifiers, across 5
# floors, in one sitting. Reaching a floor-5 boss carrying a specific modifier
# by PLAYING there is minutes per look; at that price the review does not
# happen, and the numbers stay reasoning instead of feel.
#
# So every row here answers one question: "what did I have to restart to see?"
#   * a boss + modifier combo          -> BOSS tab, two taps
#   * a class you have not tried       -> HERO tab, one tap, live, no respawn
#   * a spell that is not in your kit  -> HERO tab, granted into a chosen slot
#   * a floor you are not on           -> FLOOR tab, one tap, rebuilt in place
#   * the phone's picture              -> VIEW tab, LOW quality on the desktop
#   * a telegraph you cannot see       -> VIEW tab, 0.1x time or single frames
#   * a fight you keep dying to        -> HERO tab, GOD
#   * a thought you will forget        -> NOTES tab, or F9 without stopping
#
# ---------------------------------------------------------------------------
# EVERYTHING HERE GOES THROUGH A PUBLIC API OF A FILE THIS ONE DOES NOT OWN.
# There is no reaching into a private member anywhere below, because a debug
# tool that breaks when a `_private` is renamed is a debug tool that will be
# broken on the day it is needed. The seams used:
#
#   GameState.net_set_floor(f[, is_fall]) -> rebuilds a floor in place
#   GameState.enter_run() / game_over() or fall() / current_floor() / total_floors()
#   Arena.encounter()                    -> the live Encounter
#   Encounter.spawn_boss(mult, scale, boss_id, mods, seed)
#   Encounter.spawn(brute, hp_mult, roster)
#   BossRoster.roll(depth, seed)         -> THE seeded roll, not a copy of it
#   Hero.configure_class(i) / receive_spell(spell, nth) / revive()
#   SpellGrant.apply(hero, spell)
#   SpellLibrary.build_all()
#   Perf.toggle()
#   Tuning.cfg.graphics_quality
#   Cinematic.set_enabled(tree, on) -> the clean-frame gate the clip tool also sets
#
# ---------------------------------------------------------------------------
# HOTKEYS (also printed in the panel, because a hotkey nobody can see is a
# hotkey nobody uses)
#
#   F1   open / close the director        F4   god mode
#   F2   write a note (freezes first)     F7   cycle slow motion
#   F9   flag this moment (no freeze)     F8   advance one frame
#   F10  freeze / unfreeze the world      F3   perf overlay (PerfOverlay's own)
extends CanvasLayer

## Above the pause overlay's own contents (its host puts it on layer 90) so the
## director is legible when opened from the pause menu, and above the arena HUD
## (60) when opened mid-fight with the game still running.
const DIRECTOR_LAYER: int = 96

## Panel geometry, IN BASE-VIEWPORT UNITS. ⚠ THE GAME RENDERS AT A 640x360 BASE
## VIEWPORT and scales up (`canvas_items` stretch), so every number here is a
## fraction of 640 — not of the desktop window it happens to be shown in. The
## first build of this panel used 330, which looked reasonable at 1280x720 and
## was actually covering HALF THE ARENA. A review tool that hides the thing being
## reviewed is worse than no review tool.
##
## 206 is ~32% of the width: enough for a readable row, narrow enough that the
## fight, the boss bar and the hero all stay visible beside it.
const PANEL_WIDTH: float = 206.0
const PANEL_MARGIN: float = 5.0
## Width available to a row inside the panel, after content margins + scroll bar.
const ROW_WIDTH: float = PANEL_WIDTH - 26.0

## Font sizes, also in base-viewport units and therefore small numbers. At the
## 2x a 1280x720 window gives, 8 pt reads as 16 px; on a phone the scale factor
## is larger still. Sized DOWN from the first pass, which was legible on a
## desktop and would have been a wall of text on the target device.
const FONT_TITLE: int = 11
const FONT_STATUS: int = 8
const FONT_HEADING: int = 9
const FONT_BUTTON: int = 8
const FONT_NOTE: int = 7

## Slow motion. 1.0 first so the cycle always returns to normal speed, and 0.1
## last because that is the one that makes a 0.25 s telegraph readable.
const TIME_SCALES: Array[float] = [1.0, 0.5, 0.25, 0.1]

## God mode is implemented by INFLATING max_hp rather than by intercepting
## damage, because intercepting damage would mean editing `Hero.take_damage`,
## and this tool does not own that file. The consequence is deliberate and
## better: you still get hit, still get knocked back, still see the numbers and
## the flinch — you just do not die. Watching a boss's whole moveset is exactly
## the case this is for, and a hero that ignored hits entirely would tell you
## nothing about how those hits read.
const GOD_HP: int = 9999999

## Where a note lands. `user://` so it survives a scene change, a crash and a
## re-run; markdown so it can be pasted into a report unchanged.
const NOTES_PATH: String = "user://playtest-notes.md"

## Enemy archetypes, in `Enemy.Archetype` order. HARDCODED, with a test that
## pins it: `Enemy.gd` has no `class_name`, so the enum is not reachable from
## here. `tools/slice_test_director.gd` reads the enum out of the file text and
## fails if this list ever drifts from it.
const ARCHETYPES: Array[String] = [
	"Chaser", "Brute", "Caster", "Charger", "Summoner", "Assassin", "Bomber", "Mage",
]

## How many of an archetype the SPAWN tab drops per tap.
const SPAWN_COUNTS: Array[int] = [1, 3, 5]

## Boss HP multipliers offered in the BOSS tab. x0.25 is the review setting: a
## quarter-health guardian still shows every attack in its rotation, in a
## quarter of the time.
const BOSS_HP_MULTS: Array[float] = [0.25, 0.5, 1.0, 1.6]

## The highlight applied to the selected row in a mutually-exclusive group.
const SELECTED_TINT: Color = Color(1.0, 0.85, 0.4)

var _panel: PanelContainer = null
var _tabs: TabContainer = null
var _tab_btns: Array[Button] = []
var _status: Label = null
var _open: bool = false

# -- live director state ------------------------------------------------------
var _god: bool = false
## instance-id -> the hero's real max_hp, so GOD is reversible rather than a
## one-way trip that quietly leaves a 9,999,999 HP bar for the session.
var _god_saved: Dictionary = {}
var _time_idx: int = 0
## Frames of world time a STEP has bought. See `_process`.
var _step_frames: int = 0

# -- BOSS tab -----------------------------------------------------------------
var _sel_boss: String = ""
var _sel_mods: Dictionary = {}          # mod_id -> bool
var _boss_hp_mult: float = 1.0
var _boss_btns: Array[Button] = []
var _mod_checks: Array[CheckButton] = []
var _hp_btns: Array[Button] = []

# -- HERO tab -----------------------------------------------------------------
## -1 = "let SpellGrant choose the slot"; 0..2 = force that slot.
var _sel_slot: int = -1
var _slot_btns: Array[Button] = []
var _class_btns: Array[Button] = []

# -- SPAWN tab ----------------------------------------------------------------
var _spawn_count: int = 1
var _count_btns: Array[Button] = []

# -- NOTES tab ----------------------------------------------------------------
var _note_edit: LineEdit = null
var _note_log: RichTextLabel = null

# -- VIEW tab -----------------------------------------------------------------
var _quality_btn: Button = null
var _cinematic_btn: Button = null
var _god_btn: Button = null
var _time_btn: Button = null
var _freeze_btn: Button = null
var _ff_btn: Button = null


func _ready() -> void:
	# ALWAYS, so every row works while the world is frozen — which is the state
	# most of them are most useful in.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = DIRECTOR_LAYER
	_build()
	visible = false
	_open = false


# ============================================================================
# BUILD
# ============================================================================
func _build() -> void:
	# A full-rect holder that IGNORES input, with only the panel taking clicks.
	# Without this the director would eat every click on the arena the moment it
	# opened, and LMB is Cast — the tool would break the thing it is for.
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	# Right-hand column, full height. Anchored on all four sides rather than
	# sized to content: a Control outside a container keeps whatever rect its
	# offsets describe, and a content-sized panel would have collapsed to zero
	# height with nothing to say why.
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -(PANEL_WIDTH + PANEL_MARGIN)
	_panel.offset_right = -PANEL_MARGIN
	_panel.offset_top = PANEL_MARGIN
	_panel.offset_bottom = -PANEL_MARGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.94)
	sb.border_color = Color(1.0, 0.72, 0.25, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(5)
	_panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_panel.add_child(col)

	var title := Label.new()
	title.text = "◆ DIRECTOR   F1 closes"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.32))
	col.add_child(title)

	# The status line is the confirmation channel. Every action writes to it, so
	# a tap that silently did nothing is visible as a tap that said nothing.
	_status = Label.new()
	_status.text = "F2 note · F9 flag · F4 god · F7 slow · F10 freeze · F8 step"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(ROW_WIDTH, 0.0)
	_status.add_theme_font_size_override("font_size", FONT_STATUS)
	_status.add_theme_color_override("font_color", Color(0.62, 0.86, 0.70))
	col.add_child(_status)

	# ⚠ THE TAB BAR IS OURS, NOT TabContainer's. Six tabs do not fit across 206 px:
	# TabContainer silently degrades to a scrolling strip with little arrows, so
	# the sixth tab (NOTES — the one with a deadline attached, since the point is
	# to catch a thought before it evaporates) was OFF SCREEN behind an arrow.
	# A 3x2 grid of plain buttons always shows all six.
	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", FONT_BUTTON)

	_tabs.add_child(_tab_floor())
	_tabs.add_child(_tab_boss())
	_tabs.add_child(_tab_hero())
	_tabs.add_child(_tab_spawn())
	_tabs.add_child(_tab_view())
	_tabs.add_child(_tab_notes())

	col.add_child(_build_tab_strip())
	col.add_child(_tabs)
	col.add_child(_wide_button("Close  (F1)", func() -> void: set_open(false)))
	_refresh_tab_strip()


func _build_tab_strip() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for i: int in _tabs.get_tab_count():
		var page: String = _tabs.get_tab_title(i)
		var b: Button = _small_button(page, func() -> void:
			_tabs.current_tab = i
			_refresh_tab_strip())
		b.custom_minimum_size = Vector2((ROW_WIDTH - 4.0) / 3.0, 18)
		b.set_meta("tab_index", i)
		_tab_btns.append(b)
		grid.add_child(b)
	return grid


func _refresh_tab_strip() -> void:
	for b: Button in _tab_btns:
		b.modulate = SELECTED_TINT if int(b.get_meta("tab_index", -1)) == _tabs.current_tab else Color.WHITE


## Every tab is a scroll over a column: the panel has to fit a 640x360 phone
## viewport and the HERO tab alone lists the whole spell catalogue.
## Returns the COLUMN; the caller hands `column.get_parent()` to the TabContainer.
func _scroll_tab(tab_name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	sc.add_child(v)
	return v


# ---------------------------------------------------------------- FLOOR tab
func _tab_floor() -> Node:
	var v: VBoxContainer = _scroll_tab("FLOOR")
	v.add_child(_heading("Jump to a floor"))
	v.add_child(_note_label(
		"Rebuilds the floor IN PLACE — new layout, new waves, new boss roll. No "
		+ "scene reload, no climb. Needs an active run: F5 boots one, the F6 "
		+ "sandbox has no floors."))
	var grid := GridContainer.new()
	grid.columns = 5
	# Read live from the tower rather than hardcoded at 5, so an authored tower
	# with more floors grows this row instead of silently hiding its top.
	for f: int in range(1, _total_floors() + 1):
		var b: Button = _small_button("F%d" % f, func() -> void: _jump_to_floor(f))
		b.custom_minimum_size = Vector2((ROW_WIDTH - 10.0) / 5.0, 18)
		grid.add_child(b)
	v.add_child(grid)

	v.add_child(_heading("This floor"))
	v.add_child(_wide_button("Re-roll  (rebuild, new dice)", _reroll_floor))
	v.add_child(_wide_button("Clear every enemy  (skip the wave)", _clear_enemies))
	v.add_child(_wide_button("Force CLEARED  (open the exit portal)", _force_cleared))

	v.add_child(_heading("Run"))
	v.add_child(_wide_button("Start a run  (from the sandbox)", _start_run))
	v.add_child(_wide_button("Trigger the death path", _force_fall))
	v.add_child(_note_label(
		"Goes through the REAL spine — counter ticked, save written — so what you "
		+ "review is the beat itself. The status line names the method it reached, "
		+ "because that policy has already changed once (fall -> game over)."))
	return v.get_parent()


# ----------------------------------------------------------------- BOSS tab
func _tab_boss() -> Node:
	var v: VBoxContainer = _scroll_tab("BOSS")
	v.add_child(_note_label(
		"Summons straight into the current room. The rolled option calls "
		+ "BossRoster.roll() itself — the same seeded function the co-op host "
		+ "uses — so what you review is what a real floor would produce."))

	v.add_child(_heading("Which artist"))
	var ids: Array[String] = BossRoster.ids()
	if not ids.is_empty():
		_sel_boss = ids[0]
	for id: String in ids:
		var b: Button = _small_button(BossRoster.display_name(id), func() -> void:
			_sel_boss = id
			_refresh_boss_btns()
			_say("boss: %s" % BossRoster.display_name(id)))
		b.set_meta("boss_id", id)
		_boss_btns.append(b)
		v.add_child(b)

	v.add_child(_heading("Modifiers  (behaviour, not numbers)"))
	for mid: String in BossModifier.all_ids():
		_sel_mods[mid] = false
		var cb := CheckButton.new()
		cb.text = BossModifier.name_for(mid)
		cb.tooltip_text = BossModifier.blurb_for(mid)
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", FONT_BUTTON)
		cb.set_meta("mod_id", mid)
		cb.toggled.connect(func(on: bool) -> void:
			_sel_mods[mid] = on
			_say("%s %s" % [BossModifier.name_for(mid), "ON" if on else "off"]))
		_mod_checks.append(cb)
		v.add_child(cb)
	v.add_child(_wide_button("All modifiers ON", func() -> void: _set_all_mods(true)))
	v.add_child(_wide_button("All modifiers off", func() -> void: _set_all_mods(false)))

	v.add_child(_heading("HP"))
	var hp_row := HBoxContainer.new()
	for m: float in BOSS_HP_MULTS:
		var b: Button = _small_button("x%s" % m, func() -> void:
			_boss_hp_mult = m
			_refresh_hp_btns()
			_say("boss HP multiplier x%s" % m))
		b.custom_minimum_size = Vector2((ROW_WIDTH - 8.0) / 4.0, 16)
		b.set_meta("hp_mult", m)
		_hp_btns.append(b)
		hp_row.add_child(b)
	v.add_child(hp_row)
	v.add_child(_note_label(
		"x0.25 is the review setting: the whole rotation, a quarter of the fight."))

	v.add_child(_heading("Go"))
	v.add_child(_wide_button("SUMMON  the selection", _summon_selected_boss))
	v.add_child(_wide_button("SUMMON  a seeded roll for this depth", _summon_rolled_boss))
	v.add_child(_wide_button("Despawn every boss", _despawn_bosses))
	return v.get_parent()


# ----------------------------------------------------------------- HERO tab
func _tab_hero() -> Node:
	var v: VBoxContainer = _scroll_tab("HERO")
	v.add_child(_heading("Class  (live, no respawn)"))
	var grid := GridContainer.new()
	grid.columns = 3
	for i: int in ClassInfo.count():
		var b: Button = _small_button(ClassInfo.name_for(i), func() -> void: _switch_class(i))
		b.custom_minimum_size = Vector2((ROW_WIDTH - 6.0) / 3.0, 17)
		b.tooltip_text = String(ClassInfo.CLASSES[i].get("kit", ""))
		_class_btns.append(b)
		grid.add_child(b)
	v.add_child(grid)

	v.add_child(_heading("Survival"))
	_god_btn = _wide_button("GOD: off   (F4)", _toggle_god)
	v.add_child(_god_btn)
	v.add_child(_wide_button("Full reset  (heal, clear cooldowns, un-down)", _reset_hero))

	v.add_child(_heading("Grant a spell into a slot"))
	v.add_child(_note_label(
		"The whole catalogue — class kits, floor pickups, boss drops. Judging one "
		+ "normally means rolling the right class or finding the right pickup. "
		+ "[Q] quick · [H] heavy · [U] ult, the clash weight it fights at."))
	var slot_row := HBoxContainer.new()
	for s: int in [-1, 0, 1, 2]:
		var label: String = "auto" if s < 0 else "slot %d" % (s + 1)
		var b: Button = _small_button(label, func() -> void:
			_sel_slot = s
			_refresh_slot_btns()
			_say("granting into %s" % label))
		b.custom_minimum_size = Vector2((ROW_WIDTH - 8.0) / 4.0, 16)
		_slot_btns.append(b)
		slot_row.add_child(b)
	v.add_child(slot_row)
	_refresh_slot_btns()

	# `build_all()` is the audit list — the same one the spell sandbox reviews —
	# so nothing can be in the game and missing from this panel.
	for spell: SpellDef in SpellLibrary.build_all():
		var tier: String = ["Q", "H", "U"][clampi(SpellTier.of(spell), 0, 2)]
		var b: Button = _small_button("[%s] %s" % [tier, spell.display_name],
			func() -> void: _grant_spell(spell))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = spell.description
		v.add_child(b)
	return v.get_parent()


# ---------------------------------------------------------------- SPAWN tab
func _tab_spawn() -> Node:
	var v: VBoxContainer = _scroll_tab("SPAWN")
	v.add_child(_note_label(
		"Drops archetypes into the live room through Encounter.spawn(), so they "
		+ "arrive with the same stats, telegraphs and spawn-distance rules a wave "
		+ "would give them."))
	v.add_child(_heading("How many per tap"))
	var row := HBoxContainer.new()
	for n: int in SPAWN_COUNTS:
		var b: Button = _small_button("x%d" % n, func() -> void:
			_spawn_count = n
			_refresh_count_btns()
			_say("spawning %d at a time" % n))
		b.custom_minimum_size = Vector2((ROW_WIDTH - 6.0) / 3.0, 16)
		_count_btns.append(b)
		row.add_child(b)
	v.add_child(row)
	_refresh_count_btns()

	v.add_child(_heading("Archetype"))
	for i: int in ARCHETYPES.size():
		v.add_child(_wide_button(ARCHETYPES[i], func() -> void: _spawn_archetype(i)))

	v.add_child(_heading("Room"))
	v.add_child(_wide_button("Clear every enemy", _clear_enemies))
	v.add_child(_note_label(
		"The 25-entity ceiling still applies to summoner minions and boss adds; "
		+ "these direct spawns deliberately bypass it so you can find the edge."))
	return v.get_parent()


# ----------------------------------------------------------------- VIEW tab
func _tab_view() -> Node:
	var v: VBoxContainer = _scroll_tab("VIEW")
	v.add_child(_heading("The phone's picture, without a phone"))
	v.add_child(_note_label(
		"LOW is what a mobile export resolves to: no post-process grade, "
		+ "paint-only impact frames, thinner motes, a tighter live-VFX budget. "
		+ "No APK has ever been built, so this is the only preview that exists."))
	_quality_btn = _wide_button("Graphics: ?", _cycle_quality)
	v.add_child(_quality_btn)
	v.add_child(_wide_button("Perf overlay  (F3)", _toggle_perf))
	v.add_child(_note_label("Watch `worst`, not FPS — one 90 ms hitch a second still reads as 60."))

	# THE CLEAN FRAME. `tools/directed_clip_capture.gd` sets this same flag for every
	# clip, so a screenshot taken here and a frame out of the clip engine hide exactly
	# the same things — one definition of "postable", not two that drift.
	v.add_child(_heading("A frame you can post"))
	v.add_child(_note_label(
		"Hides the DIAGNOSTIC chrome — the clip director's heat readout, the touch "
		+ "pause button, the perf overlay, the duel's bot-intent line — and keeps the "
		+ "health plates, the clock, damage numbers and speech. Close this panel "
		+ "(F1) before you shoot."))
	_cinematic_btn = _wide_button("Cinematic: ?", _toggle_cinematic)
	v.add_child(_cinematic_btn)

	v.add_child(_heading("Time"))
	v.add_child(_note_label(
		"A telegraph is a few tenths of a second and an impact frame is a handful "
		+ "of frames. At 0.1x they become things you can look at and have an "
		+ "opinion about."))
	_time_btn = _wide_button("Speed: 1x   (F7)", _cycle_time)
	v.add_child(_time_btn)
	_freeze_btn = _wide_button("Freeze the world  (F10)", _toggle_freeze)
	v.add_child(_freeze_btn)
	v.add_child(_wide_button("Advance one frame  (F8)", _step_frame))

	# FRIENDLY FIRE. `SpellCaster.friendly_fire` is a public static var and the
	# ONLY switch for the spec's whole social engine — flip it and `_stamp()`
	# starts writing the shared `mortal` group onto every dispatch arm instead of
	# a faction. It had no in-game control at all, so "is friendly fire the right
	# default" could only be answered by editing a source file and relaunching.
	v.add_child(_heading("Rules"))
	_ff_btn = _wide_button("Friendly fire: ?", _toggle_friendly_fire)
	v.add_child(_ff_btn)
	v.add_child(_note_label(
		"Affects spells cast AFTER the flip; anything already in the air keeps the "
		+ "targets it was stamped with."))
	return v.get_parent()


# ---------------------------------------------------------------- NOTES tab
func _tab_notes() -> Node:
	var v: VBoxContainer = _scroll_tab("NOTES")
	v.add_child(_note_label(
		"A feel note is worthless if the moment passes before it is written down. "
		+ "F2 freezes the game and puts the cursor here; F9 flags the moment "
		+ "without stopping. Both stamp floor, class, boss, quality and fps."))
	_note_edit = LineEdit.new()
	_note_edit.placeholder_text = "what just happened, in your words"
	_note_edit.max_length = 400
	_note_edit.keep_editing_on_text_submit = true
	_note_edit.custom_minimum_size = Vector2(ROW_WIDTH, 18.0)
	_note_edit.text_submitted.connect(func(t: String) -> void: _save_note(t))
	v.add_child(_note_edit)
	v.add_child(_wide_button("Save note  (Enter)", func() -> void: _save_note(_note_edit.text)))
	v.add_child(_wide_button("⚑ Flag this moment  (F9)", func() -> void: _save_note("")))

	v.add_child(_heading("This session"))
	_note_log = RichTextLabel.new()
	_note_log.custom_minimum_size = Vector2(ROW_WIDTH, 80.0)
	_note_log.scroll_following = true
	_note_log.add_theme_font_size_override("normal_font_size", FONT_NOTE)
	v.add_child(_note_log)
	v.add_child(_wide_button("Show the file path", func() -> void:
		_say(ProjectSettings.globalize_path(NOTES_PATH))))
	v.add_child(_note_label(
		"Pull them into the repo with:  python python-tools/playtest_notes.py"))
	return v.get_parent()


# ============================================================================
# OPEN / CLOSE / HOTKEYS
# ============================================================================
func is_open() -> bool:
	return _open


func set_open(v: bool) -> void:
	_open = v
	visible = v
	if v:
		_refresh_all()


func toggle() -> void:
	set_open(not _open)


## ⚠ `_input`, NOT `_unhandled_input`. The director has to be reachable while a
## Control has focus (the note field, the pause menu's own buttons) and while
## the tree is paused; `_unhandled_input` never sees a key the focused LineEdit
## consumed, which would make F1 stop working exactly after you used F2.
##
## Only these keycodes are ever consumed. Everything else falls straight through
## to the game, which is the difference between a debug panel and a broken one.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F1:
			toggle()
		KEY_F2:
			_note_moment()
		KEY_F4:
			_toggle_god()
		KEY_F7:
			_cycle_time()
		KEY_F8:
			_step_frame()
		KEY_F9:
			_save_note("")
		KEY_F10:
			_toggle_freeze()
		_:
			return
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## STEP: buy exactly one frame of world time, then put the freeze back.
## Decremented here rather than by a Timer because a Timer would itself be
## paused, which is the joke that eats an afternoon.
func _process(_delta: float) -> void:
	if _step_frames > 0:
		_step_frames -= 1
		if _step_frames == 0:
			var tree: SceneTree = get_tree()
			if tree != null:
				tree.paused = true
				_refresh_freeze_btn()


# ============================================================================
# FLOOR
# ============================================================================
## Rebuild the floor in place. `net_set_floor` is the co-op client's own
## receiver — it clamps, sets the run state and emits `floor_advanced`, which
## `Arena._on_floor_advanced` already turns into a full `_setup_floor`. Using it
## rather than poking `GameState._floor` means the jump takes the same path the
## game takes, so anything that would break in a real climb breaks here too.
func _jump_to_floor(f: int) -> void:
	var gs: Node = _gamestate()
	if gs == null:
		_say("no GameState — nothing to jump")
		return
	if not bool(gs.call("is_run_active")):
		_say("no run active. FLOOR > 'Start a run' first — the F6 sandbox has no floors.")
		return
	if not _set_floor(gs, f):
		_say("GameState has no net_set_floor() any more — the run spine moved")
		return
	_say("floor %d rebuilt" % f)
	_refresh_all()


## ⚠ ARITY-TOLERANT ON PURPOSE, AND THIS IS NOT DEFENSIVE PROGRAMMING FOR ITS OWN
## SAKE. `net_set_floor` was `(floor, is_fall)` and became `(floor)` while this
## file was being written, when the death policy changed from drop-two-floors to
## game-over. A hard two-argument call became a runtime error that killed the
## FLOOR tab and nothing else — silently, in the middle of a review.
##
## The director is a tool ABOUT files it does not own, so it reads the arity off
## the live object and passes what that signature wants. It costs one
## `get_method_list()` per jump and it means a signature change downgrades the
## director instead of breaking it.
func _set_floor(gs: Node, f: int) -> bool:
	var n: int = _arity(gs, "net_set_floor")
	if n < 1:
		return false
	var args: Array = [f]
	if n >= 2:
		args.append(false)   # `is_fall` on the signature that still has it
	gs.callv("net_set_floor", args)
	return true


## How many arguments `method` takes on THIS object, or -1 if it has no such
## method. `has_method()` alone cannot answer the question that actually bites.
func _arity(obj: Object, method: String) -> int:
	if obj == null or not obj.has_method(method):
		return -1
	for m: Dictionary in obj.get_method_list():
		if String(m.get("name", "")) == method:
			return (m.get("args", []) as Array).size()
	return -1


func _reroll_floor() -> void:
	var gs: Node = _gamestate()
	if gs == null or not bool(gs.call("is_run_active")):
		_say("no run active — nothing to re-roll")
		return
	var f: int = int(gs.call("current_floor"))
	if not _set_floor(gs, f):
		_say("GameState has no net_set_floor() any more — the run spine moved")
		return
	_say("floor %d re-rolled" % f)


func _start_run() -> void:
	var gs: Node = _gamestate()
	if gs == null:
		_say("no GameState")
		return
	if bool(gs.call("is_run_active")):
		_say("a run is already active")
		return
	gs.call("enter_run")
	_say("run started — the arena is reloading")


## The DEATH BEAT, whatever it currently is. This project has changed the policy
## once already mid-development — `fall()` (drop two floors, stay in the tower)
## became `game_over()` (the run ends, the town clocks it) — so the button asks
## for the outcome rather than for a named method, tries the current spelling
## first, and SAYS WHICH ONE IT GOT. A review that thinks it is testing a fall
## while the game is testing a game-over is worse than no test at all.
func _force_fall() -> void:
	var gs: Node = _gamestate()
	if gs == null or not bool(gs.call("is_run_active")):
		_say("no run active — the death path needs a climb to end")
		return
	for m: String in ["game_over", "fall"]:
		if gs.has_method(m):
			gs.call(m)
			_say("death path fired: GameState.%s()" % m)
			return
	_say("GameState has neither game_over() nor fall() — the run spine moved")


func _clear_enemies() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var n: int = 0
	for e: Node in tree.get_nodes_in_group("enemy"):
		e.queue_free()
		n += 1
	_say("cleared %d enemies" % n)


## Fire the Encounter's own `cleared` signal so the Arena runs its real
## floor-cleared path — portals, banner, music — rather than a fake of it.
func _force_cleared() -> void:
	var enc: Node = _encounter()
	if enc == null:
		_say("no Encounter in this scene")
		return
	enc.emit_signal("cleared")
	_say("floor forced CLEARED — take the portal")


# ============================================================================
# BOSS
# ============================================================================
func _selected_mods() -> Array[String]:
	var mods: Array[String] = []
	for mid: String in _sel_mods.keys():
		if bool(_sel_mods[mid]):
			mods.append(mid)
	mods.sort()   # same stable order the roll produces, so the HUD reads the same
	return mods


func _summon_selected_boss() -> void:
	_summon(_sel_boss, _selected_mods(), randi())


## The SEEDED path, deliberately: this calls `BossRoster.roll` — the exact
## function `Encounter._begin_boss` calls on the host — so what you review here
## is what a real floor at this depth would actually produce, modifier count
## included.
func _summon_rolled_boss() -> void:
	var depth: int = _depth()
	var seed_value: int = randi()
	var r: Dictionary = BossRoster.roll(depth, seed_value)
	var mods: Array[String] = []
	for m in r.get("mods", []):
		mods.append(String(m))
	_summon(String(r.get("boss", BossRoster.GUARDIAN)), mods, seed_value)


func _summon(boss_id: String, mods: Array[String], seed_value: int) -> void:
	var enc: Node = _encounter()
	if enc == null:
		_say("no Encounter in this scene — bosses need the Arena (F5 run or F6 sandbox)")
		return
	var bid: String = boss_id
	if bid == "" or not BossRoster.has(bid):
		bid = BossRoster.GUARDIAN
	enc.call("spawn_boss", _boss_hp_mult, 1.0, bid, mods, seed_value)
	var mod_text: String = "no modifiers"
	if not mods.is_empty():
		var names: Array[String] = []
		for m: String in mods:
			names.append(BossModifier.name_for(m))
		mod_text = ", ".join(names)
	_say("%s · %s · HPx%s · seed %d"
		% [BossRoster.display_name(bid), mod_text, _boss_hp_mult, seed_value])


func _despawn_bosses() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var n: int = 0
	for e: Node in tree.get_nodes_in_group("enemy"):
		# Every guardian in the roster extends `Boss` (TowerBoss extends it too),
		# so this is an identity test rather than a name or a group convention.
		if e is Boss:
			e.queue_free()
			n += 1
	_say("despawned %d boss(es)" % n)


func _set_all_mods(on: bool) -> void:
	for mid: String in _sel_mods.keys():
		_sel_mods[mid] = on
	for cb: CheckButton in _mod_checks:
		cb.set_pressed_no_signal(on)
	_say("all modifiers %s" % ("ON" if on else "off"))


# ============================================================================
# HERO
# ============================================================================
func _switch_class(i: int) -> void:
	var h: Node = _hero()
	if h == null:
		_say("no hero in this scene")
		return
	h.call("configure_class", i)
	var gs: Node = _gamestate()
	if gs != null:
		gs.set("selected_class", i)   # so the next run and the hub agree
	_say("class -> %s" % ClassInfo.name_for(i))
	_refresh_class_btns()


func _grant_spell(spell: SpellDef) -> void:
	var h: Node = _hero()
	if h == null:
		_say("no hero in this scene")
		return
	# Fresh instance per grant. SpellDefs are Resources — reference types — and
	# handing the same object to two heroes is shared mutable state.
	var s: SpellDef = spell.duplicate() as SpellDef
	if _sel_slot < 0:
		var slot: int = SpellGrant.apply(h, s)
		_say("%s -> slot %d (auto)" % [s.display_name, slot + 1])
	else:
		var ok: bool = bool(h.call("receive_spell", s, _sel_slot))
		_say("%s -> slot %d%s" % [s.display_name, _sel_slot + 1, "" if ok else "  (REFUSED)"])


## GOD is a max_hp swap, and it is REVERSIBLE — the real value is kept per hero
## instance and put back. Toggling it off on a hero that has since been freed is
## a no-op rather than an error.
func _toggle_god() -> void:
	_god = not _god
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for h: Node in tree.get_nodes_in_group("hero"):
		if _god:
			_god_saved[h.get_instance_id()] = int(h.get("max_hp"))
			_set_hp(h, GOD_HP)
		else:
			_set_hp(h, int(_god_saved.get(h.get_instance_id(), int(h.get("max_hp")))))
	if not _god:
		_god_saved.clear()
	_refresh_god_btn()
	_say("god mode %s — you still get hit, you just do not die"
		% ("ON" if _god else "off"))


func _set_hp(h: Node, value: int) -> void:
	h.set("max_hp", value)
	h.set("hp", value)
	if h.has_signal("health_changed"):
		h.emit_signal("health_changed", value, value)


func _reset_hero() -> void:
	var h: Node = _hero()
	if h == null:
		_say("no hero in this scene")
		return
	if h.has_method("revive"):
		h.call("revive")
		_say("hero reset — full HP, cooldowns cleared, un-downed")
	else:
		_say("hero has no revive()")


# ============================================================================
# VIEW
# ============================================================================
func _cycle_quality() -> void:
	var cfg: Object = _tuning_cfg()
	if cfg == null:
		_say("no Tuning autoload")
		return
	var v: Variant = cfg.get("graphics_quality")
	var cur: int = TuningConfig.Quality.AUTO if v == null else int(v)
	cfg.set("graphics_quality", (cur + 1) % 3)
	_refresh_quality_btn()
	_say("graphics: %s" % _quality_word())


func _toggle_perf() -> void:
	var p: Node = get_node_or_null(^"/root/Perf")
	if p == null or not p.has_method("toggle"):
		_say("no Perf overlay in this build")
		return
	if not Cinematic.shows_chrome():
		_say("cinematic mode is ON — the perf overlay is gated. Turn it off first.")
		return
	p.call("toggle")
	_say("perf overlay toggled")


## Flip the clean-frame gate for the WHOLE tree, live. Read back off the static rather
## than from a local mirror, for the same reason `_toggle_friendly_fire` does: a mirror
## starts lying the moment the clip tool, or another director, touches the real one.
func _toggle_cinematic() -> void:
	Cinematic.set_enabled(get_tree(), not Cinematic.enabled)
	_refresh_cinematic_btn()
	_say("cinematic %s" % ("ON — diagnostic chrome hidden; close this panel (F1) and shoot"
		if Cinematic.enabled else "off — the instruments are back"))


func _refresh_cinematic_btn() -> void:
	if _cinematic_btn != null:
		_cinematic_btn.text = "Cinematic: %s" % ("ON" if Cinematic.enabled else "off")


## Flip the shared-`mortal`-group switch. Read back from the static rather than
## from a local mirror, because a mirror would start lying the moment anything
## else touched it.
func _toggle_friendly_fire() -> void:
	SpellCaster.friendly_fire = not SpellCaster.friendly_fire
	_refresh_ff_btn()
	_say("friendly fire %s" % ("ON — you can hit your teammate" if SpellCaster.friendly_fire else "off"))


func _cycle_time() -> void:
	_time_idx = (_time_idx + 1) % TIME_SCALES.size()
	Engine.time_scale = TIME_SCALES[_time_idx]
	_refresh_time_btn()
	_say("speed %sx" % Engine.time_scale)


func _toggle_freeze() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.paused = not tree.paused
	_step_frames = 0
	_refresh_freeze_btn()
	_say("world %s" % ("FROZEN — F8 advances one frame" if tree.paused else "running"))


func _step_frame() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if not tree.paused:
		tree.paused = true
		_refresh_freeze_btn()
		_say("frozen — F8 again to advance")
		return
	tree.paused = false
	_step_frames = 1   # unpaused now; the next _process from here puts it back
	_say("+1 frame")


# ============================================================================
# NOTES
# ============================================================================
## F2: stop the world FIRST, then take the note. The failure this fixes is "I
## will write that down after this fight" — there is no after.
func _note_moment() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = true
		_refresh_freeze_btn()
	set_open(true)
	if _tabs != null:
		_tabs.current_tab = _tabs.get_tab_count() - 1
		_refresh_tab_strip()
	if _note_edit != null:
		_note_edit.grab_focus()
	_say("frozen for the note. Enter saves; F10 unfreezes.")


## Append one entry. Context is stamped automatically because a note that says
## "this felt bad" and does not say where is a note you cannot act on.
func _save_note(text: String) -> void:
	var body: String = text.strip_edges()
	var line: String = "- `%s`  %s\n  %s\n" % [
		Time.get_datetime_string_from_system(false, true),
		_context_line(),
		body if body != "" else "FLAGGED — no text (the context above is the note)",
	]
	if not _append(NOTES_PATH, line):
		_say("could not write %s" % NOTES_PATH)
		return
	if _note_edit != null:
		_note_edit.text = ""
	if _note_log != null:
		_note_log.append_text(line)
	_say("note saved -> %s" % NOTES_PATH)


## Append, creating the file with a header if it is not there yet. Returns false
## rather than erroring so a full disk cannot take the review session with it.
func _append(path: String, line: String) -> bool:
	var existed: bool = FileAccess.file_exists(path)
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
	if f == null:
		return false
	if existed:
		f.seek_end()
	else:
		f.store_string("# THE TOWER — playtest notes\n\n"
			+ "Written live by the director (F2 / F9). Newest at the bottom.\n\n")
	f.store_string(line)
	f.close()
	return true


## Floor, class, boss, quality, fps — everything you would otherwise have to
## remember, on the line you will read a week later.
func _context_line() -> String:
	var bits: Array[String] = []
	var gs: Node = _gamestate()
	if gs != null and bool(gs.call("is_run_active")):
		bits.append("floor %d" % int(gs.call("current_floor")))
	else:
		bits.append("sandbox")
	var h: Node = _hero()
	if h != null and h.has_method("current_class_name"):
		bits.append(String(h.call("current_class_name")))
	var bosses: Array[String] = []
	var tree: SceneTree = get_tree()
	if tree != null:
		for e: Node in tree.get_nodes_in_group("enemy"):
			if e is Boss:
				bosses.append(String(e.name))
	if not bosses.is_empty():
		bits.append("boss %s" % ",".join(bosses))
	bits.append("gfx %s" % _quality_word())
	bits.append("%.0f fps" % Engine.get_frames_per_second())
	if _god:
		bits.append("GOD")
	if not is_equal_approx(Engine.time_scale, 1.0):
		bits.append("%sx" % Engine.time_scale)
	return "· " + "  ·  ".join(bits)


# ============================================================================
# SPAWN
# ============================================================================
func _spawn_archetype(kind: int) -> void:
	var enc: Node = _encounter()
	if enc == null:
		_say("no Encounter in this scene — enemies need the Arena")
		return
	# roster = [kind] forces the archetype; brute_chance is then never consulted.
	var roster: Array[int] = [kind]
	for _i: int in _spawn_count:
		enc.call("spawn", 0.0, 1.0, roster)
	_say("spawned %d x %s"
		% [_spawn_count, ARCHETYPES[kind] if kind < ARCHETYPES.size() else str(kind)])


# ============================================================================
# LOOKUPS — every one guarded, every one a public API
# ============================================================================
func _gamestate() -> Node:
	return get_node_or_null(^"/root/GameState")


func _tuning_cfg() -> Object:
	var t: Node = get_node_or_null(^"/root/Tuning")
	return t.get("cfg") if t != null else null


## The hero this director drives: in co-op, the one THIS peer owns; otherwise
## the first one. Never a puppet — commands issued to a puppet are silently
## discarded by Hero's own authority guards, which would look like a dead button.
func _hero() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	# A hero already queued for deletion is still in the group until the end of the
	# frame. Driving one is driving a corpse: the call lands, nothing happens, and
	# the button looks broken. Same shape as Arena's departed-peer guard.
	var heroes: Array[Node] = []
	for h: Node in tree.get_nodes_in_group("hero"):
		if is_instance_valid(h) and not h.is_queued_for_deletion():
			heroes.append(h)
	for h: Node in heroes:
		if h.is_multiplayer_authority():
			return h
	return heroes[0] if not heroes.is_empty() else null


## The live Encounter. Reached through `Arena.encounter()` when the current
## scene answers to it; otherwise by walking the tree, so a host that embeds an
## Arena rather than being one still works.
func _encounter() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var cs: Node = tree.current_scene
	if cs != null and cs.has_method("encounter"):
		var e: Node = cs.call("encounter")
		if e != null:
			return e
	return _find_encounter(tree.root)


func _find_encounter(n: Node) -> Node:
	if n is Encounter:
		return n
	for c: Node in n.get_children():
		var found: Node = _find_encounter(c)
		if found != null:
			return found
	return null


func _total_floors() -> int:
	var gs: Node = _gamestate()
	if gs != null and gs.has_method("total_floors"):
		return maxi(int(gs.call("total_floors")), 1)
	return 5


func _depth() -> int:
	var gs: Node = _gamestate()
	if gs != null and bool(gs.call("is_run_active")):
		return int(gs.call("current_floor"))
	return 1


# ============================================================================
# UI HELPERS + REFRESH
# ============================================================================
## Everything the director does says so, on screen AND on stdout. The console
## line is what makes a session reconstructible afterwards from the log alone.
func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg
	print("[director] ", msg)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_HEADING)
	l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	return l


func _note_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(ROW_WIDTH, 0.0)
	l.add_theme_font_size_override("font_size", FONT_NOTE)
	l.add_theme_color_override("font_color", Color(0.66, 0.70, 0.80))
	return l


## FOCUS_NONE on every button, deliberately: a focused Control eats the keyboard,
## and this panel sits on top of a game driven by A/D/Space. A director that
## stole WASD after one click would be worse than no director.
func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FONT_BUTTON)
	b.custom_minimum_size = Vector2(0, 16)
	b.pressed.connect(cb)
	return b


func _wide_button(text: String, cb: Callable) -> Button:
	var b: Button = _small_button(text, cb)
	b.custom_minimum_size = Vector2(ROW_WIDTH, 18)
	return b


func _refresh_all() -> void:
	_refresh_quality_btn()
	_refresh_god_btn()
	_refresh_time_btn()
	_refresh_freeze_btn()
	_refresh_class_btns()
	_refresh_slot_btns()
	_refresh_count_btns()
	_refresh_boss_btns()
	_refresh_hp_btns()
	_refresh_tab_strip()
	_refresh_ff_btn()
	_refresh_cinematic_btn()


func _quality_word() -> String:
	var cfg: Object = _tuning_cfg()
	var v: Variant = cfg.get("graphics_quality") if cfg != null else null
	var cur: int = TuningConfig.Quality.AUTO if v == null else int(v)
	match cur:
		TuningConfig.Quality.HIGH:
			return "HIGH"
		TuningConfig.Quality.LOW:
			return "LOW (phone)"
	return "AUTO (%s)" % ("low" if TuningConfig.quality_is_low() else "high")


func _refresh_quality_btn() -> void:
	if _quality_btn != null:
		_quality_btn.text = "Graphics: %s" % _quality_word()


func _refresh_ff_btn() -> void:
	if _ff_btn != null:
		_ff_btn.text = "Friendly fire: %s" % ("ON" if SpellCaster.friendly_fire else "off")


func _refresh_god_btn() -> void:
	if _god_btn != null:
		_god_btn.text = "GOD: %s   (F4)" % ("ON" if _god else "off")


func _refresh_time_btn() -> void:
	if _time_btn != null:
		_time_btn.text = "Speed: %sx   (F7)" % Engine.time_scale


func _refresh_freeze_btn() -> void:
	if _freeze_btn == null:
		return
	var tree: SceneTree = get_tree()
	var frozen: bool = tree != null and tree.paused
	_freeze_btn.text = "%s  (F10)" % ("UNFREEZE the world" if frozen else "Freeze the world")


## The selected row is TINTED rather than disabled: a disabled button is
## unreadable at 11 pt, and you still want to re-press the class you are already
## on after a spell grant scrambled the kit.
func _refresh_class_btns() -> void:
	var h: Node = _hero()
	var cur: String = ""
	if h != null and h.has_method("current_class_name"):
		cur = String(h.call("current_class_name"))
	for i: int in _class_btns.size():
		_class_btns[i].modulate = SELECTED_TINT if ClassInfo.name_for(i) == cur else Color.WHITE


func _refresh_slot_btns() -> void:
	for i: int in _slot_btns.size():
		var slot: int = i - 1   # the row is [auto, 1, 2, 3]
		_slot_btns[i].modulate = SELECTED_TINT if slot == _sel_slot else Color.WHITE


func _refresh_count_btns() -> void:
	for i: int in _count_btns.size():
		var on: bool = i < SPAWN_COUNTS.size() and SPAWN_COUNTS[i] == _spawn_count
		_count_btns[i].modulate = SELECTED_TINT if on else Color.WHITE


func _refresh_boss_btns() -> void:
	for b: Button in _boss_btns:
		b.modulate = SELECTED_TINT if String(b.get_meta("boss_id", "")) == _sel_boss else Color.WHITE


func _refresh_hp_btns() -> void:
	for b: Button in _hp_btns:
		var m: float = float(b.get_meta("hp_mult", 1.0))
		b.modulate = SELECTED_TINT if is_equal_approx(m, _boss_hp_mult) else Color.WHITE
