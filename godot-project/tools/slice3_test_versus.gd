# Run: godot --headless --path godot-project --script tools/slice3_test_versus.gd
# First-_process-frame harness (slice1_test_weapon / slice3_test_stage_hazard
# idiom): VersusArena/Hero/Enemy reference autoload globals (Sfx/Rank/Juice)
# and join groups in _ready, which only fires with a live tree — so the arena
# script is load()ed at runtime, never preload()ed. Real Area2D overlap is
# never used: ring-outs are driven through the directly-callable
# _on_fighter_fell seam, exactly as a pit's fighter_fell signal would.
extends SceneTree

const ARENA_SCRIPT_PATH: String = "res://scripts/combat/VersusArena.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0

	var arena_script: GDScript = load(ARENA_SCRIPT_PATH)
	var arena: Node2D = arena_script.new()
	root.add_child(arena)  # _ready builds the whole match synchronously

	failed += _test_match_setup(arena)
	failed += _test_ring_out_respawns_p1(arena)
	failed += _test_invuln_blocks_double_stock_loss(arena)
	failed += _test_ring_out_respawns_bot(arena)
	failed += _test_p1_elimination_ends_match(arena)
	failed += _test_dummy_never_blocks_victory()

	if failed > 0:
		printerr("Slice3 versus tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice3 versus tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _p1_of() -> Node2D:
	var heroes: Array = get_nodes_in_group("hero")
	return heroes[0] if not heroes.is_empty() else null


func _entry_of(arena: Node2D, body: Node2D) -> Dictionary:
	return arena._registry.get(body.get_instance_id(), {})


func _test_match_setup(arena: Node2D) -> int:
	var failed: int = 0
	failed += _expect(
		get_nodes_in_group("hero").size() == 1, "exactly one P1 exists (group 'hero')"
	)
	# Task 1 sandbox: VersusArena also spawns stationary practice dummies into
	# group "enemy" (so hero attacks/spells still hit them) AND group "dummy"
	# (so _bots_alive()/the win condition exclude them — see VersusArena.gd).
	# Exclude dummies here to keep asserting the real BOT_COUNT roster.
	var bots: Array = get_nodes_in_group("enemy").filter(
		func(n: Node) -> bool: return not n.is_in_group("dummy")
	)
	failed += _expect(
		bots.size() == arena.BOT_COUNT,
		"BOT_COUNT bots exist (group 'enemy', excluding dummies), got %d" % bots.size()
	)
	var dummies: Array = get_nodes_in_group("dummy")
	failed += _expect(
		dummies.size() == arena.DUMMY_COUNT,
		"DUMMY_COUNT practice dummies exist (group 'dummy'), got %d" % dummies.size()
	)
	failed += _expect(
		arena._registry.size() == arena.BOT_COUNT + arena.DUMMY_COUNT + 1,
		"registry holds BOT_COUNT+DUMMY_COUNT+1 fighters, got %d" % arena._registry.size()
	)
	for entry: Dictionary in arena._registry.values():
		var node: Node = entry["node"]
		if node != null and node.is_in_group("dummy"):
			# dummies get a near-infinite stock count — see DUMMY_STOCKS
			failed += _expect(
				int(entry.get("stocks", -1)) == arena.DUMMY_STOCKS,
				"dummy fighters start with DUMMY_STOCKS stocks, got %d" % int(entry.get("stocks", -1))
			)
			continue
		failed += _expect(
			int(entry.get("stocks", -1)) == arena.STOCKS,
			"every non-dummy fighter starts with STOCKS stocks"
		)
	return failed


func _test_ring_out_respawns_p1(arena: Node2D) -> int:
	var failed: int = 0
	var p1: Node2D = _p1_of()
	if p1 == null:
		return 1
	var entry: Dictionary = _entry_of(arena, p1)
	var spawn: Vector2 = entry["spawn"]

	# Shove P1 into the left pit region + damage it, then ring it out.
	p1.global_position = Vector2(30, 300)
	p1.hp = 10
	arena._on_fighter_fell(p1)

	failed += _expect(
		int(entry["stocks"]) == arena.STOCKS - 1,
		"ring-out burns one stock (got %d)" % int(entry["stocks"])
	)
	failed += _expect(
		p1.global_position.is_equal_approx(spawn),
		"P1 respawned at its spawn point, got %s" % str(p1.global_position)
	)
	failed += _expect(p1.hp == p1.max_hp, "respawn refills hp to max")
	failed += _expect(float(entry["invuln"]) > 0.0, "respawn arms the invuln window")
	failed += _expect(not arena._match_over, "match keeps running after a respawn")
	return failed


func _test_invuln_blocks_double_stock_loss(arena: Node2D) -> int:
	var failed: int = 0
	var p1: Node2D = _p1_of()
	if p1 == null:
		return 1
	var entry: Dictionary = _entry_of(arena, p1)

	# Invuln is still armed from the previous respawn: a second report in the
	# same beat must burn nothing.
	arena._on_fighter_fell(p1)
	failed += _expect(
		int(entry["stocks"]) == arena.STOCKS - 1,
		"a fall during invuln burns no stock (got %d)" % int(entry["stocks"])
	)
	return failed


func _test_ring_out_respawns_bot(arena: Node2D) -> int:
	var failed: int = 0
	# Filter out group "dummy" (also in "enemy" — see VersusArena._spawn_dummies)
	# so this test asserts against a real bot regardless of whether
	# _spawn_fighters() or _spawn_dummies() happens to run first.
	var bots: Array = get_nodes_in_group("enemy").filter(
		func(n: Node) -> bool: return not n.is_in_group("dummy")
	)
	if bots.is_empty():
		return 1
	var bot: Node2D = bots[0]
	var entry: Dictionary = _entry_of(arena, bot)
	var spawn: Vector2 = entry["spawn"]

	bot.global_position = Vector2(870, 300)  # right pit region
	arena._on_fighter_fell(bot)

	failed += _expect(
		int(entry["stocks"]) == arena.STOCKS - 1,
		"bot ring-out burns one stock (got %d)" % int(entry["stocks"])
	)
	failed += _expect(
		bot.global_position.is_equal_approx(spawn),
		"bot respawned at its own spawn point, got %s" % str(bot.global_position)
	)
	failed += _expect(bot.hp == bot.max_hp, "bot respawn refills hp to max")
	failed += _expect(not arena._match_over, "bots respawning never ends the match")
	return failed


func _test_p1_elimination_ends_match(arena: Node2D) -> int:
	var failed: int = 0
	var p1: Node2D = _p1_of()
	if p1 == null:
		return 1
	var entry: Dictionary = _entry_of(arena, p1)

	# Burn the remaining stocks (STOCKS-1 more falls), zeroing the respawn
	# invuln before each so every call actually lands.
	for i: int in arena.STOCKS - 1:
		entry["invuln"] = 0.0
		arena._on_fighter_fell(p1)

	failed += _expect(
		int(entry["stocks"]) == 0, "P1 ends at 0 stocks (got %d)" % int(entry["stocks"])
	)
	failed += _expect(arena._match_over, "_match_over latches once P1 is out of stocks")
	failed += _expect(
		arena._banner != null and arena._banner.visible, "match-over banner is shown"
	)
	failed += _expect(
		is_instance_valid(p1) and not p1.is_queued_for_deletion(),
		"eliminated P1 is never freed (its camera is the viewport)"
	)

	# Match over: further falls are ignored entirely.
	entry["invuln"] = 0.0
	arena._on_fighter_fell(p1)
	failed += _expect(
		int(entry["stocks"]) == 0, "post-match falls burn nothing"
	)
	return failed


## Regression: a dummy must NEVER block (or falsely trigger) the victory check.
## Runs against its OWN freshly-instantiated arena rather than the shared one
## the tests above mutate — _match_over latches permanently once P1's
## elimination test above ends the shared match in DEFEAT, and _on_fighter_fell
## early-returns once _match_over is true, so this scenario ("kill every real
## bot, leave the dummies alive, expect VICTORY") cannot be exercised on the
## already-finished shared arena. A second instance gives a clean, isolated
## match. Bots are looked up via THIS arena's own _registry (never a raw
## get_nodes_in_group query), since the shared arena's fighters are still
## live in the same SceneTree and would otherwise leak into the count.
##
## Why this guards the real bug class: if _bots_alive() ever stopped
## excluding group "dummy" (VersusArena.gd ~:230), the two permanently-alive,
## never-freed dummies would keep _bots_alive() stuck at >= 2 forever, and
## this match would never reach VICTORY no matter how many real bots die —
## the round-end check would hang after every real bot was eliminated.
func _test_dummy_never_blocks_victory() -> int:
	var failed: int = 0
	var arena2_script: GDScript = load(ARENA_SCRIPT_PATH)
	var arena2: Node2D = arena2_script.new()
	root.add_child(arena2)  # _ready builds a second, independent match

	var real_bot_ids: Array = []
	for id: int in arena2._registry.keys():
		var entry: Dictionary = arena2._registry[id]
		var node: Node = entry["node"]
		if node != null and node.is_in_group("enemy") and not node.is_in_group("dummy"):
			real_bot_ids.append(id)
	failed += _expect(
		real_bot_ids.size() == arena2.BOT_COUNT,
		"fresh arena has BOT_COUNT real bots to eliminate, got %d" % real_bot_ids.size()
	)

	# Kill every real bot through the same _on_fighter_fell ring-out path the
	# other tests use (STOCKS falls each, invuln zeroed first so every call
	# actually lands), leaving the dummies completely untouched.
	for id: int in real_bot_ids:
		var entry: Dictionary = arena2._registry[id]
		var node: Node2D = entry["node"]
		for i: int in arena2.STOCKS:
			entry["invuln"] = 0.0
			arena2._on_fighter_fell(node)

	failed += _expect(
		arena2._bots_alive() == 0,
		"_bots_alive() excludes the still-alive dummies, got %d" % arena2._bots_alive()
	)
	failed += _expect(
		arena2._match_over,
		"eliminating every real bot ends the match even though dummies remain"
	)
	failed += _expect(
		arena2._banner != null and arena2._banner.visible
			and arena2._banner.text.begins_with("VICTORY"),
		"the victory finish fires (banner reads VICTORY), got %s"
			% (arena2._banner.text if arena2._banner != null else "<no banner>")
	)

	var dummies_alive: int = 0
	for entry: Dictionary in arena2._registry.values():
		var node: Node = entry["node"]
		if node != null and is_instance_valid(node) and node.is_in_group("dummy") \
				and not node.is_queued_for_deletion():
			dummies_alive += 1
	failed += _expect(
		dummies_alive == arena2.DUMMY_COUNT,
		"every dummy is still alive + in group 'dummy' after the real-bot wipe, got %d"
			% dummies_alive
	)
	return failed
