# Run: godot --headless --path godot-project --script tools/slice_test_ringout.gd
# Task 4 (Stick Fight Feel Foundation): the SANDBOX Smash model — damage % builds
# up, knockback scales with %, and the ONLY elimination is a ring-out. Gated behind
# GameState.ringout_mode so the tower keeps hp-death (its slice/climb tests stay
# green). Mirrors slice3_test_versus: first-_process-frame harness so Hero/Enemy/
# VersusArena _ready (autoload globals + group joins) runs against a live tree; the
# scene scripts are load()ed at runtime, never preload()ed.
extends SceneTree

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
	var failed: int = 0
	failed += _test_knockback_scale_is_pure()
	failed += _test_damage_pct_accrues_and_no_hp_death()
	failed += _test_knockback_grows_with_pct()
	failed += _test_ring_out_is_the_only_elimination()
	failed += _test_hero_ring_out()
	failed += _test_hp_death_still_works_when_off()
	if failed > 0:
		printerr("ringout tests: %d FAILED" % failed)
		quit(1)
	else:
		print("ringout tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


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
func _test_knockback_scale_is_pure() -> int:
	var f: int = 0
	var HeroS: GDScript = load(HERO_SCRIPT_PATH)
	var EnemyS: GDScript = load(ENEMY_SCRIPT_PATH)
	f += _expect(is_equal_approx(HeroS.ringout_knockback_scale(0.0), 1.0), "0%% -> 1.0x")
	f += _expect(is_equal_approx(HeroS.ringout_knockback_scale(100.0), 2.0), "100%% -> 2.0x")
	f += _expect(is_equal_approx(HeroS.ringout_knockback_scale(50.0), 1.5), "50%% -> 1.5x")
	f += _expect(
		HeroS.ringout_knockback_scale(100.0) > HeroS.ringout_knockback_scale(0.0),
		"scale grows with %%"
	)
	f += _expect(
		is_equal_approx(EnemyS.ringout_knockback_scale(100.0), HeroS.ringout_knockback_scale(100.0)),
		"Hero + Enemy scale agree"
	)
	return f


# ------------------------------------------------- damage % builds, no hp-death
## In ring-out mode, take_damage piles onto damage_pct and NEVER drains hp or fires
## a death — even at absurd damage. True for the hero AND a bot.
func _test_damage_pct_accrues_and_no_hp_death() -> int:
	var f: int = 0
	_set_ringout(true)

	var hero: Node2D = _make(HERO_SCENE_PATH)
	hero.global_position = Vector2(5000, 5000)  # open space, away from any collider
	var full_hp: int = int(hero.hp)
	hero.take_damage(50)
	f += _expect(hero.damage_pct > 0.0, "hero damage_pct rises on a hit (got %.1f)" % hero.damage_pct)
	f += _expect(int(hero.hp) == full_hp, "hero hp is untouched in ring-out mode (got %d)" % int(hero.hp))
	# Lethal-in-tower-terms damage must not kill in ring-out mode.
	hero.take_damage(99999)
	f += _expect(is_instance_valid(hero), "hero survives huge damage (only a ring-out removes it)")
	f += _expect(int(hero.hp) == full_hp, "hero hp still full after huge damage")
	f += _expect(hero.damage_pct > 50.0, "hero damage_pct kept climbing (got %.1f)" % hero.damage_pct)

	var bot: Node2D = _make(ENEMY_SCENE_PATH)
	bot.global_position = Vector2(6000, 6000)
	bot.take_damage(99999)
	f += _expect(is_instance_valid(bot) and not bot.is_queued_for_deletion(),
		"bot is NOT freed by damage in ring-out mode")
	f += _expect(bot.damage_pct > 0.0, "bot damage_pct rises on a hit (got %.1f)" % bot.damage_pct)

	hero.free()
	bot.free()
	return f


# ----------------------------------------------- knockback grows with % (live)
## The SAME impulse displaces a high-% fighter farther than a fresh one — the
## effect the pure scale promises, verified through apply_knockback end-to-end.
func _test_knockback_grows_with_pct() -> int:
	var f: int = 0
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

	f += _expect(k0 > 0.0, "baseline knockback is non-zero (got %.1f)" % k0)
	f += _expect(k100 > k0 * 1.9, "100%% knockback ~2x the 0%% knockback (%.1f vs %.1f)" % [k100, k0])
	hero.free()
	return f


# --------------------------------------------- ring-out is the ONLY elimination
## A whole VersusArena in ring-out mode: bots can't be damaged to death, but a
## ring-out through the StageHazard->_on_fighter_fell path still eliminates them;
## the round ends in VICTORY once every real bot is ringed out, dummies untouched.
func _test_ring_out_is_the_only_elimination() -> int:
	var f: int = 0
	# VersusArena is a script (no .tscn) — instantiate via .new() (slice3 idiom);
	# its _ready builds the whole match synchronously AND sets ringout_mode = true.
	var arena_script: GDScript = load(ARENA_SCRIPT_PATH)
	var arena: Node2D = arena_script.new()
	root.add_child(arena)
	f += _expect(_gs() != null and bool(_gs().get("ringout_mode")),
		"VersusArena._ready turned ring-out mode ON")

	# Real bots (registry, excluding dummies) — mirrors slice3_test_versus so the
	# other tests' loose Hero/Enemy nodes in the shared tree don't leak in.
	var real_bot_ids: Array = []
	for id: int in arena._registry.keys():
		var entry: Dictionary = arena._registry[id]
		var node: Node = entry["node"]
		if node != null and node.is_in_group("enemy") and not node.is_in_group("dummy"):
			real_bot_ids.append(id)
	f += _expect(real_bot_ids.size() == arena.BOT_COUNT,
		"arena has BOT_COUNT real bots, got %d" % real_bot_ids.size())

	# Damage alone must NOT remove a bot (hp-death is off in ring-out mode).
	if not real_bot_ids.is_empty():
		var first: Node2D = arena._registry[real_bot_ids[0]]["node"]
		first.take_damage(99999)
		f += _expect(is_instance_valid(first) and not first.is_queued_for_deletion(),
			"a bot survives lethal-in-tower damage; only a ring-out removes it")

	# Ring out every real bot through the pit path; the round must end in VICTORY.
	for id: int in real_bot_ids:
		var entry: Dictionary = arena._registry[id]
		var node: Node2D = entry["node"]
		for i: int in arena.STOCKS:
			entry["invuln"] = 0.0
			arena._on_fighter_fell(node)

	f += _expect(arena._bots_alive() == 0, "all real bots ringed out (bots_alive=0)")
	f += _expect(arena._match_over, "round ends once every real bot is ringed out")
	f += _expect(arena._banner != null and arena._banner.visible
		and arena._banner.text.begins_with("VICTORY"),
		"VICTORY banner shows")

	# Dummies are punching bags: still alive after the real-bot wipe.
	var dummies_alive: int = 0
	for entry: Dictionary in arena._registry.values():
		var node: Node = entry["node"]
		if node != null and is_instance_valid(node) and node.is_in_group("dummy") \
				and not node.is_queued_for_deletion():
			dummies_alive += 1
	f += _expect(dummies_alive == arena.DUMMY_COUNT,
		"dummies remain after the round ends, got %d" % dummies_alive)
	return f


# --------------------------------------------------------------- hero ring-out
## Ring-out isn't just a bot path: P1 (the hero body, VersusArena._p1) goes
## through the exact same _on_fighter_fell -> respawn/eliminate flow. A fall
## with stocks remaining must decrement stocks AND zero the accrued damage_pct
## (a fresh life starts light); the final fall (stocks hit 0) must fire the
## elimination path (_match_over + a DEFEAT banner), mirroring the bot half of
## _test_ring_out_is_the_only_elimination above.
func _test_hero_ring_out() -> int:
	var f: int = 0
	var arena_script: GDScript = load(ARENA_SCRIPT_PATH)
	var arena: Node2D = arena_script.new()
	root.add_child(arena)
	f += _expect(_gs() != null and bool(_gs().get("ringout_mode")),
		"VersusArena._ready turned ring-out mode ON (hero test)")

	var p1: Node2D = arena.get("_p1")
	f += _expect(p1 != null and is_instance_valid(p1), "arena has a live P1 hero body")
	var id: int = p1.get_instance_id()
	f += _expect(arena._registry.has(id), "P1 is registered in the fall registry")

	# Give the hero some accrued % (as a real fight would) before the first fall.
	p1.set("damage_pct", 42.0)
	var entry: Dictionary = arena._registry[id]
	var stocks_before: int = int(entry["stocks"])
	f += _expect(stocks_before == arena.STOCKS, "P1 starts at STOCKS stocks, got %d" % stocks_before)

	# Fall #1: stocks remain, so this must respawn (not eliminate).
	entry["invuln"] = 0.0
	arena._on_fighter_fell(p1)
	var stocks_after_1: int = int(arena._registry[id]["stocks"])
	f += _expect(stocks_after_1 == stocks_before - 1,
		"a hero fall decrements stocks (got %d, want %d)" % [stocks_after_1, stocks_before - 1])
	f += _expect(is_equal_approx(float(p1.get("damage_pct")), 0.0),
		"hero damage_pct resets to 0 on respawn (got %.1f)" % float(p1.get("damage_pct")))
	f += _expect(not arena._match_over, "match isn't over yet — P1 still has stocks left")

	# Burn the remaining stocks through the same pit path; the LAST one must
	# eliminate P1 (out of stocks -> _finish_match, DEFEAT branch of _eliminate).
	while int(arena._registry[id]["stocks"]) > 0:
		arena._registry[id]["invuln"] = 0.0
		arena._on_fighter_fell(p1)
	f += _expect(arena._match_over, "P1 running out of stocks ends the match")
	f += _expect(arena._banner != null and arena._banner.visible
		and arena._banner.text.begins_with("DEFEAT"),
		"DEFEAT banner shows once P1 is fully ringed out")
	return f


# ------------------------------------------------ hp-death intact when mode OFF
## With ring-out mode off (the tower's normal state), take_damage drains hp and a
## lethal hit fires _die -> queue_free, exactly as the tower/climb suites assert.
func _test_hp_death_still_works_when_off() -> int:
	var f: int = 0
	_set_ringout(false)

	var hero: Node2D = _make(HERO_SCENE_PATH)
	hero.global_position = Vector2(7000, 7000)
	var full_hp: int = int(hero.hp)
	hero.take_damage(25)
	f += _expect(int(hero.hp) == full_hp - 25, "hp drains on a hit in tower mode (got %d)" % int(hero.hp))
	f += _expect(is_equal_approx(hero.damage_pct, 0.0), "damage_pct stays 0 in tower mode")

	var bot: Node2D = _make(ENEMY_SCENE_PATH)
	bot.global_position = Vector2(8000, 8000)
	bot.take_damage(int(bot.max_hp) + 50)  # lethal
	f += _expect(bot.is_queued_for_deletion(), "a lethal hit kills the bot (hp-death -> queue_free)")

	hero.free()
	return f
