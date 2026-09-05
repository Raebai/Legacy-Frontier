# Run: godot --headless --path godot-project --script tools/probe_platform_carve_cost.gd
#
# WHAT DOES IT COST TO CARVE N LEDGES INSTEAD OF ONE GROUND?
#
# `DestructibleStage` has a `REBUILD_BUDGET_USEC` and counts deferrals rather than
# swallowing them, and the whole block partition exists because a FULL re-merge of the
# ground stage measured 8,587 us mean against a 16,667 us frame. Giving every floating
# platform its own grid multiplies that machinery by the ledge count, so "it is only a
# small grid" is a claim that has to be measured rather than asserted.
#
# This prints, for a realistic floor's worth of ledges:
#   * the grid each ledge actually gets (cells, blocks) — the number the design argument
#     in `DestructibleStage.attach_ledge` rests on;
#   * the worst and total `_process` re-merge cost across a burst of carves, summed over
#     every ledge in the room, i.e. the number a frame actually pays;
#   * deferrals, which must stay 0 — a ledge deferring a re-merge is a hole you can see
#     and cannot fall into, one frame late.
#
# ⚠ IT IS A PROBE, NOT A SUITE. It prints numbers and does not assert; the pass/fail
# properties live in `tools/slice_test_platform_carve.gd`.
extends SceneTree

## A generated floor runs 6-12 ledges; 12 is the busy end.
const LEDGES: int = 12
const CARVES_PER_LEDGE: int = 6


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var room := Node2D.new()
	root.add_child(room)
	var ruin: GDScript = load("res://scripts/combat/RuinPlatform.gd")
	var made: Array[StaticBody2D] = []
	for i: int in LEDGES:
		var p: StaticBody2D = ruin.new() as StaticBody2D
		# The width band `FloorGen` actually rolls (100-210), walked across the range so
		# both the one-block and the two-block cases are in the sample.
		p.set(&"platform_size", Vector2(100.0 + float(i) * 10.0, 24.0))
		room.add_child(p)
		p.global_position = Vector2(200.0 + float(i) * 240.0, 300.0)
		made.append(p)

	var g0: DestructibleStage = made[0].get_node_or_null(^"CarveGrid") as DestructibleStage
	var gN: DestructibleStage = made[LEDGES - 1].get_node_or_null(^"CarveGrid") as DestructibleStage
	print("ledges: %d" % LEDGES)
	print("  narrowest (%.0f px): %d x %d cells, %d block(s)"
		% [100.0, g0.cols, g0.rows, g0.block_count()])
	print("  widest    (%.0f px): %d x %d cells, %d block(s)"
		% [100.0 + float(LEDGES - 1) * 10.0, gN.cols, gN.rows, gN.block_count()])

	# Carve every ledge, then let one frame of `_process` pay for all of it — which is
	# the frame the measurement is about.
	var worst_frame: int = 0
	var total: int = 0
	var deferred: int = 0
	for c: int in CARVES_PER_LEDGE:
		for i: int in LEDGES:
			var p: StaticBody2D = made[i]
			DestructibleStage.carve_from_body(p, 60,
				p.global_position + Vector2(-40.0 + float(c) * 16.0, 0.0),
				Vector2.DOWN, 20.0)
		var t0: int = Time.get_ticks_usec()
		for i2: int in LEDGES:
			var g: DestructibleStage = made[i2].get_node_or_null(^"CarveGrid") as DestructibleStage
			if g != null:
				g._process(0.016)
		var dt: int = Time.get_ticks_usec() - t0
		total += dt
		worst_frame = maxi(worst_frame, dt)
	for i3: int in LEDGES:
		var g2: DestructibleStage = made[i3].get_node_or_null(^"CarveGrid") as DestructibleStage
		if g2 != null:
			deferred += g2.deferred_rebuilds

	print("re-merge cost, ALL %d ledges in one frame, over %d carve rounds:"
		% [LEDGES, CARVES_PER_LEDGE])
	print("  worst frame: %d us   mean frame: %d us   (frame budget 16667 us)"
		% [worst_frame, int(total / maxi(CARVES_PER_LEDGE, 1))])
	print("  deferred rebuilds: %d  (must be 0 — a deferral is a hole you can see and"
		% deferred + " cannot fall into, one frame late)")
	quit(0)
