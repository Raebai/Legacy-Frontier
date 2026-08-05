# Run: godot --headless --path godot-project --script tools/slice3_test_versus.gd
# First-_process-frame harness (slice1_test_weapon / slice3_test_stage_hazard
# idiom): VersusArena/Hero reference autoload globals (Sfx/Rank/Juice) and join
# groups in _ready, which only fires with a live tree — so the arena script is
# load()ed at runtime, never preload()ed. Real Area2D overlap is never used:
# ring-outs are driven through the directly-callable _on_fighter_fell seam,
# exactly as a pit's fighter_fell signal would.
#
# WHAT THIS SUITE NOW GUARDS (the group battle is gone):
#   * entering VersusArena IS the 1v1 — no five-bot roster, no practice dummies
#   * the ring-out stock ladder still works, on the two duellists
#   * running out of stocks ends the MATCH and restocks for the next one
#   * every knob that used to be an on-screen button lives in the Esc menu
#   * the boss-rush handoff arms Arena.boss_rush
#   * the bot-vs-bot SHOWCASE capture path still builds
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"duel_is_the_only_mode",
	"no_group_roster_or_dummies",
	"ring_out_burns_a_stock",
	"invuln_blocks_double_stock_loss",
	"stock_out_ends_and_restocks",
	"settings_moved_to_pause_menu",
	"pause_menu_injection_order",
	"boss_rush_handoff",
	"class_swap_in_the_duel",
	"showcase_capture_path_still_builds",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ARENA_SCRIPT_PATH: String = "res://scripts/combat/VersusArena.gd"
const TOWER_ARENA_SCRIPT_PATH: String = "res://scripts/combat/Arena.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true

	var arena_script: GDScript = load(ARENA_SCRIPT_PATH)
	var arena: Node2D = arena_script.new()
	root.add_child(arena)  # _ready builds the whole match synchronously

	_test_duel_is_the_only_mode(arena)
	_test_no_group_roster_or_dummies(arena)
	_test_ring_out_burns_a_stock(arena)
	_test_invuln_blocks_double_stock_loss(arena)
	_test_stock_out_ends_and_restocks(arena)
	_test_settings_moved_to_pause_menu(arena)
	_test_pause_menu_injection_order()
	_test_boss_rush_handoff(arena)
	_test_class_swap_in_the_duel(arena)
	root.remove_child(arena)
	arena.queue_free()
	_test_showcase_capture_path_still_builds(arena_script)

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice3 versus tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice3 versus tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _entry_of(arena: Node2D, body: Node2D) -> Dictionary:
	return arena._registry.get(body.get_instance_id(), {})


# ------------------------------------------------------------------ the mode
## Entering the scene drops you straight into the 1v1: two heroes, on opposed
## factions, with the bot carrying the shipped stack and the human reading Input.
func _test_duel_is_the_only_mode(arena: Node2D) -> void:
	_expect(arena._is_duel(), "a plain VersusArena is a DUEL with no setup at all")
	_expect(not arena._is_showcase(), "...and is not a showcase")
	var heroes: Array = get_nodes_in_group("hero")
	_expect(heroes.size() == 2, "exactly two heroes are on the stage, got %d" % heroes.size())
	_expect(arena._p1 != null and arena._duel_bot != null and arena._p1 != arena._duel_bot,
		"one human, one bot, distinct")
	_expect(arena._duel_ctrl != null, "the bot carries the shipped controller")
	_expect(arena._p1.get("controller") == null,
		"the human has NO controller, so it reads the real Input")
	_expect(arena._registry.size() == 2,
		"the registry holds exactly the two duellists, got %d" % arena._registry.size())
	_completes("duel_is_the_only_mode")


## THE GROUP BATTLE IS GONE. No five-bot roster, no practice dummies, and no
## leftover Enemy on the stage that a spell could hit instead of the bot.
func _test_no_group_roster_or_dummies(arena: Node2D) -> void:
	_expect(get_nodes_in_group("enemy").is_empty(),
		"no trash-mob roster spawns, got %d" % get_nodes_in_group("enemy").size())
	_expect(get_nodes_in_group("dummy").is_empty(),
		"no practice dummies spawn, got %d" % get_nodes_in_group("dummy").size())
	for gone_fn: String in ["_spawn_dummies", "_bots_alive", "_enter_duel", "_leave_duel"]:
		_expect(not arena.has_method(gone_fn),
			"the group-battle method `%s` was removed, not just unused" % gone_fn)
	_completes("no_group_roster_or_dummies")


# ---------------------------------------------------------------- ring-outs
## A fall off the rim still costs a stock and returns the fighter to its spawn at
## full hp — the mechanic survived the mode removal.
func _test_ring_out_burns_a_stock(arena: Node2D) -> void:
	var p1: Node2D = arena._p1
	var spawn: Vector2 = _entry_of(arena, p1)["spawn"]
	p1.global_position = Vector2(-900.0, 400.0)   # off the left rim
	p1.set("hp", 3)
	arena._on_fighter_fell(p1)
	var entry: Dictionary = _entry_of(arena, p1)
	_expect(int(entry["stocks"]) == arena.STOCKS - 1,
		"a ring-out burns one stock, got %d" % int(entry["stocks"]))
	_expect(p1.global_position == spawn, "...and returns the fighter to its own spawn")
	_expect(int(p1.get("hp")) == int(p1.get("max_hp")), "...at full hp")
	_expect(float(entry["invuln"]) > 0.0, "...with the respawn invuln armed")
	_completes("ring_out_burns_a_stock")


## The invuln window is what stops a re-report in the same beat burning a second
## stock (moving a fighter to spawn clears the pit's own per-body dedup).
func _test_invuln_blocks_double_stock_loss(arena: Node2D) -> void:
	var p1: Node2D = arena._p1
	var before: int = int(_entry_of(arena, p1)["stocks"])
	arena._on_fighter_fell(p1)   # immediately again, still inside the invuln
	_expect(int(_entry_of(arena, p1)["stocks"]) == before,
		"a re-report inside the invuln window burns nothing")
	_completes("invuln_blocks_double_stock_loss")


## Out of stocks: the match is called, and BOTH fighters are restocked so the
## maker can keep fighting without reloading the scene. Nobody is freed — both
## duellists are heroes, and freeing one would take the hotbar/camera with it.
func _test_stock_out_ends_and_restocks(arena: Node2D) -> void:
	var bot: Node2D = arena._duel_bot
	for i: int in arena.STOCKS:
		_entry_of(arena, bot)["invuln"] = 0.0
		arena._on_fighter_fell(bot)
	_expect(is_instance_valid(bot) and not bot.is_queued_for_deletion(),
		"the bot is NOT freed on a stock-out (it is a hero, not a trash mob)")
	_expect(arena._banner != null and arena._banner.visible
			and arena._banner.text == "YOU WIN THE MATCH",
		"the banner calls the match for the human, got %s"
			% (arena._banner.text if arena._banner != null else "<no banner>"))
	for entry: Dictionary in arena._registry.values():
		_expect(int(entry["stocks"]) == arena.STOCKS,
			"every fighter is restocked for the next match, got %d" % int(entry["stocks"]))
	_expect(int(bot.get("hp")) == arena.DUEL_HP, "...and back at full hp")
	_completes("stock_out_ends_and_restocks")


# ------------------------------------------------------------- the Esc menu
## THE MAKER'S ASK: every duel knob lives in the Esc menu now, and NOTHING that
## tunes the fight is left as a button over the fight.
func _test_settings_moved_to_pause_menu(arena: Node2D) -> void:
	var menu: PauseMenu = arena._pause_menu
	_expect(menu != null, "the arena builds a pause menu")
	var settings: Array[String] = _button_texts(menu._settings_col)
	for want: String in ["Difficulty:", "Bot class:", "Learning:", "Show learned:",
			"Bot intent:", "Forget me"]:
		_expect(_any_starts_with(settings, want),
			"Esc -> Settings offers `%s` (got %s)" % [want, settings])
	var main: Array[String] = _button_texts(menu._main_col)
	for want2: String in ["Fight the Boss", "Rematch"]:
		_expect(_any_starts_with(main, want2),
			"Esc offers `%s` (got %s)" % [want2, main])

	# ...and the play HUD is clean: no arena Button outside the pause overlay.
	var stray: Array[String] = []
	for b: Button in _all_buttons(arena):
		if _under(b, menu):
			continue
		stray.append(b.text)
	_expect(stray.is_empty(),
		"no settings buttons are left on the play HUD, found %s" % [stray])

	# The live ones are still LIVE: Learning toggles without a reload and retexts.
	var was: bool = arena.duel_learning
	arena._toggle_duel_learning()
	_expect(arena.duel_learning != was, "Learning toggles in place")
	_expect(String((arena._duel_labels["learning"] as Button).text)
			== "Learning: %s" % ("ON" if arena.duel_learning else "OFF"),
		"...and the menu button retexts itself")
	arena._toggle_duel_learning()   # restore
	_completes("settings_moved_to_pause_menu")


## Injected rows never displace the two rows that must stay last.
func _test_pause_menu_injection_order() -> void:
	var menu := PauseMenu.new()
	root.add_child(menu)
	menu.build("Exit")
	menu.add_action("Injected Main", func() -> void: pass)
	menu.add_setting_section("Section")
	menu.add_setting_button("Injected Setting", func() -> void: pass)
	var main: Array[String] = _button_texts(menu._main_col)
	var settings: Array[String] = _button_texts(menu._settings_col)
	_expect(not main.is_empty() and main[main.size() - 1] == "Exit",
		"the exit button stays the LAST main-menu row, got %s" % [main])
	# ⚠ THE SETTINGS PAGE HAS TWO EXITS NOW, AND THE INVARIANT IS THE PAIR. Maker:
	# *"pausing should have a resume button as well when I pause"* — a host that hangs
	# its knobs here (the duel's Fighter A / Difficulty / Fighter HP rows) dropped you
	# on this page, whose only way out was "Back" to a menu you then had to re-read to
	# find "Resume". The claim under test never was "Back is last"; it was "an injected
	# row cannot land below the way out", and that is now a two-row footer.
	_expect(settings.size() >= 2
			and settings[settings.size() - 2] == "Back"
			and settings[settings.size() - 1] == "Resume  (Esc)",
		"Back + Resume stay the LAST TWO settings rows, in that order, got %s" % [settings])
	_expect(main.has("Injected Main") and settings.has("Injected Setting"),
		"...and both injected rows are actually present")
	# The point of the pin: the injected knob is ABOVE both exits, not between them.
	_expect(settings.find("Injected Setting") < settings.size() - 2,
		"an injected knob sits above the footer pair, got %s" % [settings])
	root.remove_child(menu)
	menu.queue_free()
	_completes("pause_menu_injection_order")


# --------------------------------------------------------------- boss rush
## The Esc menu's "Fight the Boss" arms the tower Arena's boss-rush static and
## nothing else — GameState is untouched, so it can never leave a half-run behind.
## Only the flag half is exercised: change_scene_to_file cannot run inside a
## --script SceneTree, so the handoff is split and the flag is what carries.
func _test_boss_rush_handoff(arena: Node2D) -> void:
	var tower: GDScript = load(TOWER_ARENA_SCRIPT_PATH) as GDScript
	_expect(tower != null, "the tower Arena script loads")
	tower.set("boss_rush", false)
	tower.set("boss_rush", true)
	_expect(bool(tower.get("boss_rush")), "Arena.boss_rush is a settable static")
	_expect(arena.has_method("_enter_boss_fight"),
		"VersusArena exposes the boss handoff the menu is wired to")
	_expect(String(arena.ARENA_SCENE) == "res://scenes/combat/Arena.tscn",
		"...pointed at the tower arena scene")
	tower.set("boss_rush", false)   # never leak an armed flag into another suite
	_completes("boss_rush_handoff")


# -------------------------------------------------------------- class swap
## TAB MUST WORK MID-DUEL ("I WANT to be able to swap classes like the punch and
## stuff"). Four things have to survive the swap, and each of them is a bug the
## duel would have shipped:
##   the KIT + the MELEE change (that is the point of the swap)
##   the GUARD STYLE follows the class — Swordsaint holds a BLADE ring, the
##     casters keep the press-window parry
##   the BOT DOES NOT SWAP WITH YOU — Hero reads `switch_class` through the
##     controller seam, and a controller that reported the press would flip both
##   FACTIONS + CAMERAS are untouched, so the two can still hurt each other and
##     the pair-framing camera still owns the viewport
## ...plus the learned record re-keys to the class you just became, or a Brawler
## session would be filed against the Arcanist you stopped playing.
func _test_class_swap_in_the_duel(arena: Node2D) -> void:
	var human: Node2D = arena._p1
	var bot: Node2D = arena._duel_bot
	var before_class: int = int(human.get("_hero_class"))
	var before_bot_class: int = int(bot.get("_hero_class"))
	var before_faction: StringName = StringName(str(human.get("faction_group")))
	var before_hostile: StringName = StringName(str(human.get("hostile_group")))
	var before_melee: int = int(human.get("_melee_damage"))
	var before_kit: Array = human.get("_signatures")
	var kit_names: Array[String] = []
	for sig: Variant in before_kit:
		kit_names.append(String(sig.display_name))

	human.cycle_class_next()

	_expect(int(human.get("_hero_class")) != before_class,
		"Tab changes the human's class")
	_expect(int(bot.get("_hero_class")) == before_bot_class,
		"...and NEVER the bot's (its controller reports no `switch_class` press)")
	_expect(StringName(str(human.get("faction_group"))) == before_faction
			and StringName(str(human.get("hostile_group"))) == before_hostile,
		"...factions survive the swap, so the two can still hurt each other")
	var live_cams: int = 0
	for h: Node in [human, bot]:
		for child: Node in h.get_children():
			if child is Camera2D and (child as Camera2D).enabled:
				live_cams += 1
	_expect(live_cams == 0,
		"...neither hero camera wakes up to fight the pair-framing one, got %d" % live_cams)
	var after_kit: Array[String] = []
	for sig: Variant in human.get("_signatures"):
		after_kit.append(String(sig.display_name))
	_expect(after_kit != kit_names, "...the KIT changes with the class")
	_expect(int(human.get("_melee_damage")) != before_melee
			or not is_equal_approx(float(human.get("_melee_cd")), 0.0),
		"...the melee is re-tuned for the new class")

	# GUARD STYLE: the Swordsaint (class 8) is the only held BLADE ring.
	human.configure_class(8)
	_expect(human.get("_guard") != null, "the Swordsaint gets the held BLADE guard")
	human.configure_class(0)
	_expect(human.get("_guard") == null, "a caster keeps the press-window parry")

	# The learned record follows you to the class you just became.
	arena._learn_class = 99   # a class the human is definitely not
	arena._follow_class_swap()
	_expect(arena._learn_class == int(human.get("_hero_class")),
		"the learned record re-keys to the class actually being played, got %d"
			% arena._learn_class)
	_completes("class_swap_in_the_duel")


# ---------------------------------------------------------------- showcase
## The bot-vs-bot capture path (tools/bot_clip_capture.gd, the sim) must keep
## working — it is the only consumer of the showcase statics and it is how the
## clip engine renders class-vs-class.
func _test_showcase_capture_path_still_builds(arena_script: GDScript) -> void:
	arena_script.set("showcase_a", 0)   # ARCANIST
	arena_script.set("showcase_b", 5)   # CRYOMANCER
	var show: Node2D = arena_script.new()
	root.add_child(show)
	_expect(show._is_showcase(), "setting the two statics puts the scene in showcase mode")
	_expect(not show._is_duel(), "...and out of duel mode")
	_expect(show._registry.size() == 2, "two showcase fighters are registered, got %d"
		% show._registry.size())
	var with_ctrl: int = 0
	for entry: Dictionary in show._registry.values():
		if (entry["node"] as Node).get("controller") != null:
			with_ctrl += 1
	_expect(with_ctrl == 2, "BOTH showcase fighters are bot-driven, got %d" % with_ctrl)
	_expect(show._show_cam != null, "the pair-framing capture camera exists")
	root.remove_child(show)
	show.queue_free()
	arena_script.set("showcase_a", -1)
	arena_script.set("showcase_b", -1)
	_completes("showcase_capture_path_still_builds")


# ------------------------------------------------------------------ helpers
func _button_texts(col: Node) -> Array[String]:
	var out: Array[String] = []
	if col == null:
		return out
	for child: Node in col.get_children():
		if child is Button:
			out.append(String((child as Button).text))
	return out


func _any_starts_with(list: Array[String], prefix: String) -> bool:
	for s: String in list:
		if s.begins_with(prefix):
			return true
	return false


func _all_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node as Button)
	for child: Node in node.get_children():
		out.append_array(_all_buttons(child))
	return out


func _under(node: Node, ancestor: Node) -> bool:
	var n: Node = node
	while n != null:
		if n == ancestor:
			return true
		n = n.get_parent()
	return false
