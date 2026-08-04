# Run: godot --headless --path godot-project --script tools/slice_test_ringout.gd
# Task 4 (Stick Fight Feel Foundation): the SANDBOX Smash model — damage % builds
# up, knockback scales with %, and the ONLY elimination is a ring-out. Gated behind
# GameState.ringout_mode so the tower keeps hp-death (its slice/climb tests stay
# green). Mirrors slice3_test_versus: first-_process-frame harness so Hero/Enemy/
# VersusArena _ready (autoload globals + group joins) runs against a live tree; the
# scene scripts are load()ed at runtime, never preload()ed.
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
	"knockback_scale_is_pure",
	"damage_pct_accrues_and_no_hp_death",
	"knockback_grows_with_pct",
	"health_is_the_shipped_pvp_default",
	"ring_out_is_the_only_elimination",
	"hero_ring_out",
	"hp_death_still_works_when_off",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const ENEMY_SCENE_PATH: String = "res://scenes/combat/Enemy.tscn"
const ARENA_SCRIPT_PATH: String = "res://scripts/combat/VersusArena.gd"
const HERO_SCRIPT_PATH: String = "res://scripts/combat/Hero.gd"
const ENEMY_SCRIPT_PATH: String = "res://scripts/combat/Enemy.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_knockback_scale_is_pure()
	_test_damage_pct_accrues_and_no_hp_death()
	_test_knockback_grows_with_pct()
	_test_health_is_the_shipped_pvp_default()
	_test_ring_out_is_the_only_elimination()
	_test_hero_ring_out()
	_test_hp_death_still_works_when_off()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("ringout tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("ringout tests: all PASS")
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


func _gs() -> Node:
	return root.get_node_or_null("GameState")


func _set_ringout(on: bool) -> void:
	var gs: Node = _gs()
	if gs != null:
		gs.set("ringout_mode", on)


func _make(path: String) -> Node2D:
	var scene: PackedScene = load(path)
	var n: Node2D = scene.instantiate()
	root.add_child(n)  # _ready runs synchronously against the live tree
	return n


# ---------------------------------------------------------------- pure scale
## The %-> knockback multiplier is pure + static: 0% -> 1.0x, 100% -> 2.0x, and it
## rises monotonically. Hero + Enemy must agree (same feel for both sides).
func _test_knockback_scale_is_pure() -> void:
	var HeroS: GDScript = load(HERO_SCRIPT_PATH)
	var EnemyS: GDScript = load(ENEMY_SCRIPT_PATH)
	_expect(is_equal_approx(HeroS.ringout_knockback_scale(0.0), 1.0), "0%% -> 1.0x")
	_expect(is_equal_approx(HeroS.ringout_knockback_scale(100.0), 2.0), "100%% -> 2.0x")
	_expect(is_equal_approx(HeroS.ringout_knockback_scale(50.0), 1.5), "50%% -> 1.5x")
	_expect(
		HeroS.ringout_knockback_scale(100.0) > HeroS.ringout_knockback_scale(0.0),
		"scale grows with %%"
	)
	_expect(
		is_equal_approx(EnemyS.ringout_knockback_scale(100.0), HeroS.ringout_knockback_scale(100.0)),
		"Hero + Enemy scale agree"
	)
	_completes("knockback_scale_is_pure")


# ------------------------------------------------- damage % builds, no hp-death
## In ring-out mode, take_damage piles onto damage_pct and NEVER drains hp or fires
## a death — even at absurd damage. True for the hero AND a bot.
func _test_damage_pct_accrues_and_no_hp_death() -> void:
	_set_ringout(true)

	var hero: Node2D = _make(HERO_SCENE_PATH)
	hero.global_position = Vector2(5000, 5000)  # open space, away from any collider
	var full_hp: int = int(hero.hp)
	hero.take_damage(50)
	_expect(hero.damage_pct > 0.0, "hero damage_pct rises on a hit (got %.1f)" % hero.damage_pct)
	_expect(int(hero.hp) == full_hp, "hero hp is untouched in ring-out mode (got %d)" % int(hero.hp))
	# Lethal-in-tower-terms damage must not kill in ring-out mode.
	hero.take_damage(99999)
	_expect(is_instance_valid(hero), "hero survives huge damage (only a ring-out removes it)")
	_expect(int(hero.hp) == full_hp, "hero hp still full after huge damage")
	_expect(hero.damage_pct > 50.0, "hero damage_pct kept climbing (got %.1f)" % hero.damage_pct)

	var bot: Node2D = _make(ENEMY_SCENE_PATH)
	bot.global_position = Vector2(6000, 6000)
	bot.take_damage(99999)
	_expect(is_instance_valid(bot) and not bot.is_queued_for_deletion(),
		"bot is NOT freed by damage in ring-out mode")
	_expect(bot.damage_pct > 0.0, "bot damage_pct rises on a hit (got %.1f)" % bot.damage_pct)

	hero.free()
	bot.free()
	_completes("damage_pct_accrues_and_no_hp_death")


# ----------------------------------------------- knockback grows with % (live)
## The SAME impulse displaces a high-% fighter farther than a fresh one — the
## effect the pure scale promises, verified through apply_knockback end-to-end.
func _test_knockback_grows_with_pct() -> void:
	_set_ringout(true)
	var hero: Node2D = _make(HERO_SCENE_PATH)
	hero.global_position = Vector2(5000, 9000)

	hero.damage_pct = 0.0
	hero._knockback = Vector2.ZERO
	hero.apply_knockback(Vector2(200, 0), false)
	var k0: float = hero._knockback.length()

	hero.damage_pct = 100.0
	hero._knockback = Vector2.ZERO
	hero.apply_knockback(Vector2(200, 0), false)
	var k100: float = hero._knockback.length()

	_expect(k0 > 0.0, "baseline knockback is non-zero (got %.1f)" % k0)
	_expect(k100 > k0 * 1.9, "100%% knockback ~2x the 0%% knockback (%.1f vs %.1f)" % [k100, k0])
	hero.free()
	_completes("knockback_grows_with_pct")


# --------------------------------------------- ring-out is the ONLY elimination
## A whole VersusArena in ring-out mode. It is a 1v1 DUEL now (the five-bot group
## battle was removed at maker request), so the subject is the duel BOT: damage
## alone must not remove it, but the StageHazard -> _on_fighter_fell path still
## burns its stocks, and running out calls the match.
func _test_ring_out_is_the_only_elimination() -> void:
	# VersusArena is a script (no .tscn) — instantiate via .new() (slice3 idiom);
	# its _ready builds the whole match synchronously AND sets ringout_mode = true.
	var arena_script: GDScript = load(ARENA_SCRIPT_PATH)
	# ⚠ RING-OUT IS A PREFERENCE NOW, NOT A PROPERTY OF THE ARENA. The maker asked
	# for HEALTH as the pvp default ("I like health instead for the pvp"), with the
	# Smash model kept as a setting — so `VersusArena._ready` reads
	# `GameState.pvp_rules` instead of forcing stocks on. This suite is about the
	# ring-out MECHANIC, so it opts into that mode explicitly rather than relying on
	# a default that has deliberately moved.
	if _gs() != null:
		_gs().set("pvp_rules", 1)   # PvpRules.STOCKS
	var arena: Node2D = arena_script.new()
	root.add_child(arena)
	_expect(_gs() != null and bool(_gs().get("ringout_mode")),
		"VersusArena._ready turned ring-out mode ON")

	var bot: Node2D = arena.get("_duel_bot")
	_expect(bot != null and is_instance_valid(bot), "the duel bot exists")
	_expect(arena._registry.size() == 2,
		"the registry holds exactly the two duellists, got %d" % arena._registry.size())

	# Damage alone must NOT remove a fighter (hp-death is off in ring-out mode).
	bot.take_damage(99999)
	_expect(is_instance_valid(bot) and not bot.is_queued_for_deletion(),
		"a fighter survives lethal-in-tower damage; only a ring-out removes it")

	# Ring the bot out through the pit path until its stocks run out.
	var entry: Dictionary = arena._registry[bot.get_instance_id()]
	for i: int in arena.STOCKS:
		entry["invuln"] = 0.0
		arena._on_fighter_fell(bot)
	_expect(arena._banner != null and arena._banner.visible
		and arena._banner.text == "YOU WIN THE MATCH",
		"the match is called for the human once the bot is out of stocks")
	# ...and BOTH sides are restocked, so the next match starts without a reload.
	for e: Dictionary in arena._registry.values():
		_expect(int(e["stocks"]) == arena.STOCKS,
			"every fighter is restocked for the next match, got %d" % int(e["stocks"]))
	_completes("ring_out_is_the_only_elimination")


# --------------------------------------------------------------- hero ring-out
## Ring-out isn't just a bot path: P1 (the hero body, VersusArena._p1) goes
## through the exact same _on_fighter_fell -> respawn/eliminate flow. A fall
## with stocks remaining must decrement stocks AND zero the accrued damage_pct
## (a fresh life starts light); the final fall (stocks hit 0) must fire the
## elimination path (_match_over + a DEFEAT banner), mirroring the bot half of
## _test_ring_out_is_the_only_elimination above.
func _test_hero_ring_out() -> void:
	var arena_script: GDScript = load(ARENA_SCRIPT_PATH)
	# ⚠ RING-OUT IS A PREFERENCE NOW, NOT A PROPERTY OF THE ARENA. The maker asked
	# for HEALTH as the pvp default ("I like health instead for the pvp"), with the
	# Smash model kept as a setting — so `VersusArena._ready` reads
	# `GameState.pvp_rules` instead of forcing stocks on. This suite is about the
	# ring-out MECHANIC, so it opts into that mode explicitly rather than relying on
	# a default that has deliberately moved.
	if _gs() != null:
		_gs().set("pvp_rules", 1)   # PvpRules.STOCKS
	var arena: Node2D = arena_script.new()
	root.add_child(arena)
	_expect(_gs() != null and bool(_gs().get("ringout_mode")),
		"VersusArena._ready turned ring-out mode ON (hero test)")

	var p1: Node2D = arena.get("_p1")
	_expect(p1 != null and is_instance_valid(p1), "arena has a live P1 hero body")
	var id: int = p1.get_instance_id()
	_expect(arena._registry.has(id), "P1 is registered in the fall registry")

	# Give the hero some accrued % (as a real fight would) before the first fall.
	p1.set("damage_pct", 42.0)
	var entry: Dictionary = arena._registry[id]
	var stocks_before: int = int(entry["stocks"])
	_expect(stocks_before == arena.STOCKS, "P1 starts at STOCKS stocks, got %d" % stocks_before)

	# Fall #1: stocks remain, so this must respawn (not eliminate).
	entry["invuln"] = 0.0
	arena._on_fighter_fell(p1)
	var stocks_after_1: int = int(arena._registry[id]["stocks"])
	_expect(stocks_after_1 == stocks_before - 1,
		"a hero fall decrements stocks (got %d, want %d)" % [stocks_after_1, stocks_before - 1])
	_expect(is_equal_approx(float(p1.get("damage_pct")), 0.0),
		"hero damage_pct resets to 0 on respawn (got %.1f)" % float(p1.get("damage_pct")))
	_expect(not arena._match_over, "match isn't over yet — P1 still has stocks left")

	# Burn the remaining stocks through the same pit path; the LAST one calls the
	# match for the BOT and restocks both sides (nobody is freed — both duellists
	# are heroes, and freeing P1 would take the hotbar and camera with it).
	# Exactly the stocks P1 has LEFT (fall #1 above already burned one) — one more
	# after the restock would start eating into the fresh match's stocks.
	for i: int in int(arena._registry[id]["stocks"]):
		arena._registry[id]["invuln"] = 0.0
		arena._on_fighter_fell(p1)
	_expect(is_instance_valid(p1) and not p1.is_queued_for_deletion(),
		"P1 is never freed on a stock-out")
	_expect(arena._banner != null and arena._banner.visible
		and arena._banner.text == "BOT WINS THE MATCH",
		"the match is called for the bot once P1 is fully ringed out")
	_expect(int(arena._registry[id]["stocks"]) == arena.STOCKS,
		"P1 is restocked for the next match")
	_completes("hero_ring_out")


# ------------------------------------------------ hp-death intact when mode OFF
## With ring-out mode off (the tower's normal state), take_damage drains hp and a
## lethal hit fires _die -> queue_free, exactly as the tower/climb suites assert.
func _test_hp_death_still_works_when_off() -> void:
	_set_ringout(false)

	var hero: Node2D = _make(HERO_SCENE_PATH)
	hero.global_position = Vector2(7000, 7000)
	var full_hp: int = int(hero.hp)
	hero.take_damage(25)
	_expect(int(hero.hp) == full_hp - 25, "hp drains on a hit in tower mode (got %d)" % int(hero.hp))
	_expect(is_equal_approx(hero.damage_pct, 0.0), "damage_pct stays 0 in tower mode")

	var bot: Node2D = _make(ENEMY_SCENE_PATH)
	bot.global_position = Vector2(8000, 8000)
	bot.take_damage(int(bot.max_hp) + 50)  # lethal
	_expect(bot.is_queued_for_deletion(), "a lethal hit kills the bot (hp-death -> queue_free)")

	hero.free()
	_completes("hp_death_still_works_when_off")


## SHIPPED POLICY, pinned the same way `DeathRules` pins its two forks: a PvP fight
## is decided by HEALTH unless the player says otherwise. The maker chose this
## ("I like health instead for the pvp"), and it is a design call rather than a
## constant that happens to be zero — so flipping the default has to be done twice.
func _test_health_is_the_shipped_pvp_default() -> void:
	var GS: GDScript = load("res://scripts/GameState.gd") as GDScript
	_expect(GS != null, "GameState.gd loads")
	if GS == null:
		return  # deliberately NOT completed
	var gs: Node = GS.new()
	_expect(int(gs.get("pvp_rules")) == 0,
		"SHIPPED POLICY: PvP is decided by HEALTH by default (pvp_rules == HEALTH). "
		+ "Stocks + percentage is a settings opt-in. If you meant to flip it, update this test.")
	gs.free()
	_completes("health_is_the_shipped_pvp_default")
