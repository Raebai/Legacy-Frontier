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
	var bots: Array = get_nodes_in_group("enemy")
	failed += _expect(
		bots.size() == arena.BOT_COUNT,
		"BOT_COUNT bots exist (group 'enemy'), got %d" % bots.size()
	)
	failed += _expect(
		arena._registry.size() == arena.BOT_COUNT + 1,
		"registry holds BOT_COUNT+1 fighters, got %d" % arena._registry.size()
	)
	for entry: Dictionary in arena._registry.values():
		failed += _expect(
			int(entry.get("stocks", -1)) == arena.STOCKS,
			"every fighter starts with STOCKS stocks"
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
	var bots: Array = get_nodes_in_group("enemy")
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
