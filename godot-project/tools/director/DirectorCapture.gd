# PROOF THAT THE DIRECTOR ACTUALLY WORKS — drives the real thing and photographs it.
# ============================================================================
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project res://tools/director/DirectorCapture.tscn
#
# ⚠ THE **GUI** BINARY, NOT `--headless`, AND NOT `--script`. Two separate
# reasons, both of which have wasted time in this repo before:
#   * `--headless` runs the DUMMY renderer. Every frame it saves is blank, so a
#     capture tool run headlessly proves nothing while looking like it passed.
#   * `--script` DOES NOT REGISTER AUTOLOADS. The Arena needs `GameState`,
#     `Tuning`, `Sfx`, `Music` and `Perf` to be real. Running a SCENE (the
#     positional argument above) boots the project properly, autoloads and all —
#     which is why this is a `.tscn` with a driver script rather than a
#     `SceneTree` script like most of `tools/`.
#
# WHAT IT DOES: boots a real run, opens the real pause menu, opens the real
# director from the real row, and then drives the four claims that are worth
# doubting — jump a floor, summon a boss carrying modifiers, switch class and
# grant a spell, and flip the picture to the phone's LOW tier. A frame per step.
#
# It is a CAPTURE tool, not a test: `run_all_tests.py` excludes `*_capture`
# deliberately, and the assertion here is a human looking at eight PNGs.
extends Node

const ARENA: String = "res://scenes/combat/Arena.tscn"
const OUT_DIR: String = "user://director_capture"
## 1280x720 so the panel is legible in the frame. The game itself renders at a
## 640x360 base viewport and scales; the director's own rows are sized against
## that, which is why they still fit at the small end.
const WINDOW: Vector2i = Vector2i(1280, 720)

var _arena: Node = null
var _director: Node = null
var _menu: Node = null
var _shot: int = 0


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW)
	get_window().size = WINDOW
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run()


func _run() -> void:
	await _boot_a_run()
	await _shoot("arena", "the real Arena, floor 1, no director on screen")
	await _open_the_menu()
	await _open_the_director()
	await _jump_a_floor()
	await _summon_a_boss()
	await _drive_the_hero()
	await _flip_the_picture()
	await _freeze_it()
	_write_a_note()
	print("[capture] frames in ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


# ---------------------------------------------------------------------------
## A REAL RUN, WITHOUT A SCENE CHANGE. `GameState.enter_run()` would swap the
## current scene out from under this driver; `enter_coop_run(1)` sets exactly the
## same run state (`_run_active`, `mode = RUN`, the floor) and changes nothing
## else — so the Arena added below comes up in RUN mode, with floors, rather than
## in the F6 sandbox that has none.
func _boot_a_run() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("enter_coop_run"):
		gs.call("enter_coop_run", 1)
	_arena = (load(ARENA) as PackedScene).instantiate()
	add_child(_arena)
	await _hold(90)


func _open_the_menu() -> void:
	_menu = _find(get_tree().root, func(n: Node) -> bool: return n is PauseMenu)
	if _menu == null:
		push_error("[capture] no PauseMenu found — the director row lives on it")
		return
	get_tree().paused = true
	_menu.call("open")
	await _hold(6)
	await _shoot("pause_row", "the DIRECTOR row on the real pause menu (the route a phone has)")


func _open_the_director() -> void:
	_director = _find(get_tree().root, func(n: Node) -> bool:
		return n.is_in_group("director"))
	if _director == null:
		push_error("[capture] no director — PauseMenu.director_available() said no")
		return
	if _menu != null:
		_menu.call("close")
	get_tree().paused = false
	_director.call("set_open", true)
	await _hold(6)
	await _shoot("floor_tab", "director open, game still running underneath")


func _jump_a_floor() -> void:
	if _director == null:
		return
	_director.call("_jump_to_floor", 4)
	await _hold(70)
	await _shoot("floor_4", "one tap -> floor 4 rebuilt in place, new theme, new waves")


## The claim under test: any of the four bosses, carrying any of the six
## modifiers, without playing to the floor it lives on.
func _summon_a_boss() -> void:
	if _director == null:
		return
	_tab(1)
	_director.set("_sel_boss", BossRoster.CARTOGRAPHER)
	var mods: Dictionary = _director.get("_sel_mods")
	var ids: Array[String] = BossModifier.all_ids()
	for i: int in mini(2, ids.size()):
		mods[ids[i]] = true
	for cb: CheckButton in _director.get("_mod_checks"):
		if bool(mods.get(String(cb.get_meta("mod_id", "")), false)):
			cb.set_pressed_no_signal(true)
	_director.set("_boss_hp_mult", 0.5)
	_director.call("_refresh_all")
	await _hold(4)
	await _shoot("boss_tab", "boss + modifiers selected, before the summon")
	_director.call("_summon_selected_boss")
	await _hold(80)
	await _shoot("boss_summoned", "THE CARTOGRAPHER, on floor 4, carrying two modifiers")


func _drive_the_hero() -> void:
	if _director == null:
		return
	_tab(2)
	_director.call("_switch_class", 8)          # Swordsaint — the newest kit
	_director.set("_sel_slot", 0)
	var spells: Array = SpellLibrary.build_all()
	for s: SpellDef in spells:
		if s.id == "the_void":                  # a Tier 3 boss drop, never in a kit
			_director.call("_grant_spell", s)
			break
	_director.call("_toggle_god")
	await _hold(10)
	await _shoot("hero_tab", "class switched live, a Tier 3 drop granted into slot 1, GOD on")


## The only preview of the phone's picture that exists, since no APK has ever
## been built. AUTO -> HIGH -> LOW, so two presses from the default.
func _flip_the_picture() -> void:
	if _director == null:
		return
	_tab(4)
	_director.call("_cycle_quality")
	_director.call("_cycle_quality")
	await _hold(60)
	await _shoot("quality_low", "graphics forced LOW — no post-process grade, thinner motes")


func _freeze_it() -> void:
	if _director == null:
		return
	_director.call("_cycle_time")               # 0.5x
	_director.call("_toggle_freeze")
	await _hold(4)
	await _shoot("frozen", "world frozen at 0.5x — F8 would advance one frame")
	_director.call("_toggle_freeze")


func _write_a_note() -> void:
	if _director == null:
		return
	_director.call("_save_note",
		"written by tools/director/DirectorCapture.gd — proof the note path works")


# ------------------------------------------------------------------ plumbing
func _tab(i: int) -> void:
	var tabs: TabContainer = _director.get("_tabs") as TabContainer
	if tabs != null and i < tabs.get_tab_count():
		tabs.current_tab = i


func _hold(frames: int) -> void:
	for _i: int in frames:
		# PROCESS frames, not physics: the tree is deliberately PAUSED for some of
		# these shots and `await physics_frame` would never return there.
		await get_tree().process_frame


func _shoot(label: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("[capture] no image for " + label)
		return
	_shot += 1
	var path: String = "%s/%02d_%s.png" % [OUT_DIR, _shot, label]
	img.save_png(path)
	print("[capture] %s  <- %s" % [ProjectSettings.globalize_path(path), what])


func _find(n: Node, pred: Callable) -> Node:
	if bool(pred.call(n)):
		return n
	for c: Node in n.get_children():
		var f: Node = _find(c, pred)
		if f != null:
			return f
	return null
