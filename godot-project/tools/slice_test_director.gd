# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_director.gd
#
# THE DIRECTOR — the debug review rig (`tools/director/Director.gd`).
#
# What this suite is actually for. The director exists so the first review
# session can reach every boss, class, spell, archetype and floor without a
# restart. Two ways it could fail that are both SILENT:
#
#   1. A ROW THAT DOES NOTHING. Every action reaches a file the director does not
#      own, through that file's public API. If `Encounter.spawn_boss` grows an
#      argument, or `ClassInfo` gains a tenth class, or `SpellLibrary` gains a
#      spell, the panel does not error — it just quietly stops covering the thing
#      it was built to cover. So the tests below COUNT rows against the live
#      rosters rather than against a number written here.
#   2. A ROW THAT CRASHES THE REVIEW. Half the director's actions are meaningless
#      outside an Arena (no Encounter, no hero, no run). A missing guard there is
#      an error mid-playtest, which is the one moment it must not happen. So every
#      action is called with NOTHING present and asserted to report a reason.
#
# ⚠ AND IT MUST NOT SHIP. That is `tools/slice_test_release_gate.gd`'s job, not
# this one's; here we only pin the two properties that make that possible — the
# script lives under `res://tools/` (which the export preset excludes) and
# `PauseMenu.director_available()` is guarded on `OS.is_debug_build()`.
#
# ⚠ THE IDIOM. Failures accumulate on the MEMBER `_fails`; every test records a
# COMPLETION SENTINEL as its last line, so a test that aborts part-way fails the
# suite BY ABSENCE. Never `_fails += _test_x()`. `tools/slice_test_loadout.gd` is
# the reference.
#
# ⚠ AND THE OTHER TRAP: the hero fixture here is a REAL `Hero.tscn`, not a stub.
# A stub declaring members the shipped class does not have is a fixture more
# generous than reality, and this repo has already lost time to exactly that
# (`SpellHandoff` asking heroes for a `bot_driven` that existed nowhere). God
# mode writes `max_hp`/`hp`; if those move, this suite must be what says so.
extends SceneTree

const DIRECTOR_PATH: String = "res://tools/director/Director.gd"
const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const ENEMY_SRC: String = "res://scripts/combat/Enemy.gd"

## The Hero members the director reaches by name. Named here so a rename fails
## LOUDLY instead of turning god mode into a silent no-op (`set()` on an
## undeclared property is a SILENT no-op in GDScript — it does not even warn).
const HERO_MEMBERS_USED: Array[String] = ["max_hp", "hp"]
## ...and the methods.
const HERO_METHODS_USED: Array[String] = [
	"configure_class", "receive_spell", "revive", "current_class_name",
]

const TESTS: Array[String] = [
	"director_lives_under_tools_so_the_export_excludes_it",
	"pause_menu_offers_a_director_row_and_only_one",
	"director_is_a_canvaslayer_so_the_hidden_menu_cannot_hide_it",
	"archetype_list_matches_the_enemy_enum",
	"every_boss_and_every_modifier_has_a_row",
	"every_class_and_every_spell_has_a_row",
	"hero_members_and_methods_the_director_uses_still_exist",
	"class_switch_and_spell_grant_land_on_a_real_hero",
	"god_mode_is_reversible",
	"time_and_freeze_controls_write_through",
	"notes_are_appended_with_context",
	"every_action_is_safe_with_no_arena_and_no_hero",
	"friendly_fire_toggle_writes_the_real_switch",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_lives_under_tools()
	_test_pause_menu_row()
	_test_is_canvaslayer()
	_test_archetypes_match_enum()
	_test_boss_and_modifier_rows()
	_test_class_and_spell_rows()
	_test_hero_surface()
	_test_class_and_grant_on_real_hero()
	_test_god_mode()
	_test_time_and_freeze()
	_test_notes()
	_test_safe_without_arena()
	_test_friendly_fire()
	# Leave nothing behind for the next suite in this process.
	Engine.time_scale = 1.0
	paused = false
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Director tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("Director tests: all PASS")
	quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ fixtures
func _make_director() -> Node:
	var script: Resource = load(DIRECTOR_PATH)
	if script == null:
		return null
	var d: Node = (script as GDScript).new()
	root.add_child(d)
	return d


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	return hero


## Every Button under `n` carrying `meta_key`.
func _buttons_with_meta(n: Node, meta_key: String, out: Array[Button]) -> void:
	var b := n as Button
	if b != null and b.has_meta(meta_key):
		out.append(b)
	for c: Node in n.get_children():
		_buttons_with_meta(c, meta_key, out)


func _collect(n: Node, type_check: Callable, out: Array) -> void:
	if bool(type_check.call(n)):
		out.append(n)
	for c: Node in n.get_children():
		_collect(c, type_check, out)


func _button_texts(n: Node) -> Array[String]:
	var out: Array[String] = []
	_gather_button_texts(n, out)
	return out


func _gather_button_texts(n: Node, out: Array[String]) -> void:
	var b := n as Button
	if b != null:
		out.append(b.text)
	for c: Node in n.get_children():
		_gather_button_texts(c, out)


func _status_text(d: Node) -> String:
	var l: Label = d.get("_status") as Label
	return l.text if l != null else ""


# =========================================================== IT MUST NOT SHIP
## The PRIMARY ship gate is not a runtime flag — it is that the bytes are not in
## the pack. `export_presets.cfg` excludes `res://tools/*`, so this path is the
## whole mechanism, and a director moved to `res://scripts/` would ship.
func _test_lives_under_tools() -> void:
	_expect(PauseMenu.DIRECTOR_SCRIPT.begins_with("res://tools/"),
		"the director lives under res://tools/ — the ONE directory the export "
		+ "preset excludes, which is what keeps it off a phone (got `%s`)"
		% PauseMenu.DIRECTOR_SCRIPT)
	_expect(ResourceLoader.exists(PauseMenu.DIRECTOR_SCRIPT),
		"...and it is present in THIS (development) build, or the review rig does not exist")
	var host: String = FileAccess.get_file_as_string("res://scripts/combat/PauseMenu.gd")
	_expect(host.contains("OS.is_debug_build()"),
		"the second, independent gate is still in PauseMenu.director_available()")
	_expect(PauseMenu.director_available(),
		"director_available() is true in a development build (both gates open)")
	_completes("director_lives_under_tools_so_the_export_excludes_it")


# =============================================================== THE PAUSE ROW
## F1 does not exist on a phone. The pause menu is the route that survives having
## no keyboard, and it is the same route the maker already reaches for.
func _test_pause_menu_row() -> void:
	var m := PauseMenu.new()
	root.add_child(m)
	m.build("Exit")
	_expect(m.director() != null, "building a PauseMenu builds a director")
	var texts: Array[String] = _button_texts(m)
	var found: bool = false
	for t: String in texts:
		if t.contains("DIRECTOR"):
			found = true
	_expect(found, "...and puts a DIRECTOR row on the MAIN menu (rows: %s)" % [texts])

	# A second PauseMenu in the same scene must NOT build a second director:
	# two would double every hotkey, so F1 would open and immediately close.
	var m2 := PauseMenu.new()
	root.add_child(m2)
	m2.build("Exit")
	_expect(m2.director() == null,
		"a second PauseMenu in the same scene does NOT build a second director "
		+ "(two would make F1 a no-op by cancelling each other)")
	m.queue_free()
	m2.queue_free()
	_completes("pause_menu_offers_a_director_row_and_only_one")


## The same trick the pause BUTTON needed, for the same reason: `PauseMenu` is a
## Control that is `visible = false` whenever the menu is closed, and the
## director has to be usable with the menu CLOSED and the game RUNNING. A Control
## child would be hidden exactly when it is wanted; a CanvasLayer is not a
## CanvasItem and does not inherit that.
func _test_is_canvaslayer() -> void:
	var m := PauseMenu.new()
	root.add_child(m)
	m.build("Exit")
	var d: Node = m.director()
	_expect(d is CanvasLayer,
		"the director is a CanvasLayer, so the closed (hidden) PauseMenu cannot hide it")
	if d != null:
		_expect(not m.visible, "the menu is closed...")
		d.call("set_open", true)
		_expect(bool(d.get("visible")),
			"...and the director can still be shown while it is (got visible=%s)"
			% [d.get("visible")])
		d.call("set_open", false)
	m.queue_free()
	_completes("director_is_a_canvaslayer_so_the_hidden_menu_cannot_hide_it")


# ============================================================== COVERAGE
## `Enemy.gd` has no `class_name`, so the director cannot reach `Enemy.Archetype`
## and carries a hardcoded name list. That is the drift risk this test exists for:
## a ninth archetype, or a reordering, would leave the SPAWN tab quietly mislabelled
## — you would tap "Bomber" and get a Mage and never know.
func _test_archetypes_match_enum() -> void:
	var src: String = FileAccess.get_file_as_string(ENEMY_SRC)
	_expect(not src.is_empty(), "Enemy.gd is readable")
	var start: int = src.find("enum Archetype")
	_expect(start >= 0, "Enemy.gd still declares `enum Archetype`")
	if start < 0:
		return  # deliberately NOT completed
	var open_brace: int = src.find("{", start)
	var close_brace: int = src.find("}", open_brace)
	var body: String = src.substr(open_brace + 1, close_brace - open_brace - 1)
	var names: Array[String] = []
	for raw: String in body.split(","):
		var n: String = raw.strip_edges()
		if n != "":
			names.append(n)
	var d: Node = _make_director()
	_expect(d != null, "the director script loads")
	if d == null:
		return  # deliberately NOT completed
	var listed: Array = d.get("ARCHETYPES")
	_expect(listed.size() == names.size(),
		"the SPAWN tab lists every archetype: enum has %d %s, director has %d %s"
		% [names.size(), names, listed.size(), listed])
	for i: int in mini(names.size(), listed.size()):
		_expect(String(listed[i]).to_upper() == names[i],
			"archetype %d is `%s` in the enum and `%s` in the director — the SPAWN "
			% [i, names[i], listed[i]]
			+ "button would spawn the wrong thing under the right label")
	d.queue_free()
	_completes("archetype_list_matches_the_enemy_enum")


## Four bosses and six modifiers is the entire content surface of Phase 5. If a
## fifth boss lands and the panel does not grow a row, the review that was
## supposed to judge it never sees it.
func _test_boss_and_modifier_rows() -> void:
	var d: Node = _make_director()
	if d == null:
		_expect(false, "the director script loads")
		return  # deliberately NOT completed
	var boss_btns: Array[Button] = []
	_buttons_with_meta(d, "boss_id", boss_btns)
	var ids: Array[String] = BossRoster.ids()
	_expect(boss_btns.size() == ids.size(),
		"every boss in the roster has a row: roster %d %s, panel %d"
		% [ids.size(), ids, boss_btns.size()])
	var seen: Dictionary = {}
	for b: Button in boss_btns:
		seen[String(b.get_meta("boss_id"))] = true
	for id: String in ids:
		_expect(seen.has(id), "boss `%s` is summonable from the panel" % id)

	var checks: Array = []
	_collect(d, func(n: Node) -> bool: return n is CheckButton and n.has_meta("mod_id"), checks)
	var mods: Array[String] = BossModifier.all_ids()
	_expect(checks.size() == mods.size(),
		"every modifier has a toggle: registry %d %s, panel %d" % [mods.size(), mods, checks.size()])
	d.queue_free()
	_completes("every_boss_and_every_modifier_has_a_row")


## The HERO tab is the answer to "22 spells and 9 classes in one sitting". It is
## built from `ClassInfo.count()` and `SpellLibrary.build_all()` — the same audit
## list the spell sandbox reviews — so nothing can be in the game and missing here.
func _test_class_and_spell_rows() -> void:
	var d: Node = _make_director()
	if d == null:
		_expect(false, "the director script loads")
		return  # deliberately NOT completed
	var texts: Array[String] = _button_texts(d)
	for i: int in ClassInfo.count():
		var want: String = ClassInfo.name_for(i)
		_expect(texts.has(want), "class `%s` has a live-switch row" % want)
	var spells: Array = SpellLibrary.build_all()
	_expect(spells.size() >= 22,
		"the catalogue is the size the review has to cover (got %d)" % spells.size())
	var missing: Array[String] = []
	for s: SpellDef in spells:
		var hit: bool = false
		for t: String in texts:
			if t.ends_with(s.display_name):
				hit = true
				break
		if not hit:
			missing.append(s.display_name)
	_expect(missing.is_empty(),
		"every spell in build_all() is grantable from the panel — missing: %s" % [missing])
	d.queue_free()
	_completes("every_class_and_every_spell_has_a_row")


# ================================================================ THE HERO
## `set()` on an undeclared property is a SILENT no-op, so god mode reaching a
## renamed `max_hp` would appear to work and would not save you from anything.
func _test_hero_surface() -> void:
	var hero: CharacterBody2D = _make_hero()
	var present: Dictionary = {}
	for p: Dictionary in hero.get_property_list():
		present[String(p["name"])] = true
	for n: String in HERO_MEMBERS_USED:
		_expect(present.has(n),
			"Hero still declares `%s` — the director writes it by name, and set() on "
			% n + "a missing property is a SILENT no-op")
	for m: String in HERO_METHODS_USED:
		_expect(hero.has_method(m), "Hero still has `%s()` — the director calls it" % m)
	hero.queue_free()
	_completes("hero_members_and_methods_the_director_uses_still_exist")


## The two rows that carry the most review value: switch class without a respawn,
## and put any spell in any slot. Asserted against a REAL Hero.tscn.
func _test_class_and_grant_on_real_hero() -> void:
	var d: Node = _make_director()
	var hero: CharacterBody2D = _make_hero()
	if d == null:
		_expect(false, "the director script loads")
		return  # deliberately NOT completed
	# Class switch, live, no respawn.
	d.call("_switch_class", int(ClassInfo.count()) - 1)
	_expect(String(hero.call("current_class_name")) == ClassInfo.name_for(ClassInfo.count() - 1),
		"the class row switched the live hero to `%s` (got `%s`)"
		% [ClassInfo.name_for(ClassInfo.count() - 1), hero.call("current_class_name")])
	# Grant into a FORCED slot.
	var spells: Array = SpellLibrary.build_all()
	var spell: SpellDef = spells[spells.size() - 1]
	d.set("_sel_slot", 1)
	d.call("_grant_spell", spell)
	var got: SpellDef = hero.call("signature_at", 1) as SpellDef
	_expect(got != null and got.id == spell.id,
		"granting `%s` into slot 2 landed there (slot 2 now holds `%s`)"
		% [spell.display_name, got.display_name if got != null else "<null>"])
	# ...and the auto slot still resolves through SpellGrant rather than guessing.
	d.set("_sel_slot", -1)
	d.call("_grant_spell", spells[0])
	_expect(_status_text(d).contains("(auto)"),
		"the auto row reports which slot SpellGrant chose (status: `%s`)" % _status_text(d))
	hero.queue_free()
	d.queue_free()
	_completes("class_switch_and_spell_grant_land_on_a_real_hero")


## GOD is a max_hp swap, deliberately: you still get hit, you just do not die,
## which is what makes it useful for judging how a boss's hits READ. It must be
## reversible — a one-way trip leaves a 9,999,999 bar for the rest of the session
## and every "that felt survivable" note after it is worthless.
func _test_god_mode() -> void:
	var d: Node = _make_director()
	var hero: CharacterBody2D = _make_hero()
	if d == null:
		_expect(false, "the director script loads")
		return  # deliberately NOT completed
	var real_max: int = int(hero.get("max_hp"))
	_expect(real_max > 0 and real_max < 10000, "the hero starts on a real max_hp (%d)" % real_max)
	d.call("_toggle_god")
	_expect(int(hero.get("max_hp")) == int(d.get("GOD_HP")),
		"GOD ON inflates max_hp (got %d)" % int(hero.get("max_hp")))
	_expect(int(hero.get("hp")) == int(d.get("GOD_HP")), "...and tops the current HP up to it")
	d.call("_toggle_god")
	_expect(int(hero.get("max_hp")) == real_max,
		"GOD OFF restores the REAL max_hp (%d, got %d)" % [real_max, int(hero.get("max_hp"))])
	_expect(int(hero.get("hp")) == real_max, "...and the current HP with it")
	hero.queue_free()
	d.queue_free()
	_completes("god_mode_is_reversible")


# ================================================================ THE VIEW
## Slow motion is how a 0.3 s telegraph becomes something you can have an opinion
## about, and the freeze/step pair is how an impact frame does. Both write to
## engine-global state, so both have to come back.
func _test_time_and_freeze() -> void:
	var d: Node = _make_director()
	if d == null:
		_expect(false, "the director script loads")
		return  # deliberately NOT completed
	_expect(is_equal_approx(Engine.time_scale, 1.0), "time starts at 1x")
	d.call("_cycle_time")
	_expect(Engine.time_scale < 1.0, "F7 slows time down (got %.3f)" % Engine.time_scale)
	var scales: Array = d.get("TIME_SCALES")
	for _i: int in scales.size() - 1:
		d.call("_cycle_time")
	_expect(is_equal_approx(Engine.time_scale, 1.0),
		"...and the cycle RETURNS to 1x rather than stranding the session in slow motion")

	_expect(not paused, "the world starts running")
	d.call("_toggle_freeze")
	_expect(paused, "F10 freezes the world")
	d.call("_toggle_freeze")
	_expect(not paused, "...and unfreezes it")
	# STEP from a running world freezes first (one key, one obvious meaning).
	d.call("_step_frame")
	_expect(paused, "F8 on a running world freezes it rather than doing nothing visible")
	paused = false
	d.queue_free()
	_completes("time_and_freeze_controls_write_through")


# =============================================================== THE NOTES
## A note without context is a note you cannot act on a week later. The append is
## tested against a TEMP path — writing to the real `user://playtest-notes.md`
## would put test noise into the maker's actual review log.
func _test_notes() -> void:
	var d: Node = _make_director()
	if d == null:
		_expect(false, "the director script loads")
		return  # deliberately NOT completed
	var tmp: String = "user://_director_test_notes.md"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	_expect(bool(d.call("_append", tmp, "- first\n")), "the first append creates the file")
	_expect(bool(d.call("_append", tmp, "- second\n")), "the second appends rather than truncating")
	var body: String = FileAccess.get_file_as_string(tmp)
	_expect(body.contains("- first") and body.contains("- second"),
		"BOTH notes survive — an append that truncated would lose the whole session (got `%s`)"
		% body)
	_expect(body.contains("# THE TOWER"), "...and the file gets a header on creation")
	var ctx: String = String(d.call("_context_line"))
	# No run and no hero here, so this is the floor of what a stamp always carries.
	_expect(ctx.contains("sandbox"), "the stamp says where you were (got `%s`)" % ctx)
	_expect(ctx.contains("gfx"), "...and what the picture was set to")
	_expect(ctx.contains("fps"), "...and what it was running at")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	d.queue_free()
	_completes("notes_are_appended_with_context")


## `SpellCaster.friendly_fire` is a public STATIC var and the only switch for the
## spec's whole social engine. It had no in-game control at all, so "is friendly
## fire the right default" could previously only be answered by editing a source
## file and relaunching. The toggle must write the real static — a local mirror
## would look right and change nothing.
func _test_friendly_fire() -> void:
	var d: Node = _make_director()
	if d == null:
		_expect(false, "the director script loads")
		return  # deliberately NOT completed
	var was: bool = SpellCaster.friendly_fire
	d.call("_toggle_friendly_fire")
	_expect(SpellCaster.friendly_fire != was,
		"the toggle writes SpellCaster.friendly_fire itself (still %s)" % SpellCaster.friendly_fire)
	d.call("_toggle_friendly_fire")
	_expect(SpellCaster.friendly_fire == was,
		"...and puts the shipped default back rather than stranding the session on it")
	d.queue_free()
	_completes("friendly_fire_toggle_writes_the_real_switch")


# ======================================================= NOTHING MAY CRASH
## ⚠ THE TEST THAT PROTECTS THE REVIEW SESSION ITSELF. Most of these actions are
## meaningless without an Arena, an Encounter, a hero or an active run, and the
## director is reachable from the Lobby and the hub too. A missing guard here is
## an error thrown in the middle of a playtest — the exact moment nobody wants to
## be reading a stack trace. Every one must report a reason on the status line
## instead.
func _test_safe_without_arena() -> void:
	var d: Node = _make_director()
	if d == null:
		_expect(false, "the director script loads")
		return  # deliberately NOT completed
	var calls: Array[Array] = [
		["_jump_to_floor", [3]],
		["_reroll_floor", []],
		["_force_fall", []],
		["_force_cleared", []],
		["_clear_enemies", []],
		["_summon_selected_boss", []],
		["_summon_rolled_boss", []],
		["_despawn_bosses", []],
		["_spawn_archetype", [0]],
		["_switch_class", [0]],
		["_reset_hero", []],
		["_toggle_perf", []],
		["_cycle_quality", []],
		["_refresh_all", []],
	]
	for c: Array in calls:
		d.callv(String(c[0]), c[1])
		# Reaching the next line at all is the assertion: an unguarded get_tree()
		# or a call on a null Encounter aborts the enclosing function, and every
		# `_expect` after it would never run — which the completion sentinel then
		# catches. The status line proves it reported rather than merely survived.
		_expect(_status_text(d) != "",
			"`%s` with no arena/hero/run said something on the status line" % c[0])
	_expect(String(d.get("_sel_boss")) != "",
		"a boss is preselected, so SUMMON is one tap and not two")
	d.queue_free()
	_completes("every_action_is_safe_with_no_arena_and_no_hero")
