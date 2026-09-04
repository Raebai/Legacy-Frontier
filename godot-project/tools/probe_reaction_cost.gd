# WHAT THE REACTION SWEEP COSTS — measured, at the worst case the reactor allows.
#
# The reaction system's whole performance claim is in one sentence of
# `SpellReactor.resolve_now`: "staged so the common case is free". This measures
# whether that is true, at the only load that matters — `MAX_LIVE` (12) reactants,
# which is 66 pair tests, thirty times a second.
#
# Three loads, because the stages have wildly different costs and a single number
# would hide which one is being paid:
#
#   BUCKET-MISS   12 effects whose form pairs nobody wrote a rule for. Every pair
#                 dies on one integer shift and a hash lookup. This is the floor.
#   NO-RULE       12 effects in a populated bucket whose predicates all refuse.
#                 Every pair pays a full `ReactionTable.rules()` rebuild + scan,
#                 which is the expensive stage and the one worth knowing about.
#   OVERLAP       12 effects that match a row AND touch, so geometry runs too.
#                 Memoised after the first tick, so this measures the steady state
#                 a real fight sits in after its first crossing.
#
#   Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#       --script tools/probe_reaction_cost.gd
#
# ⚠ `Time.get_ticks_msec` is ~20x wrong inside `--write-movie` and useless at this
# resolution anyway; this uses `get_ticks_usec` over 2000 ticks and reports the
# per-tick mean. Nothing here renders, so the clock is honest.
#
# ⚠ NAMES NO SPECTACLE BY class_name — a `--script` tool compiles before the
# autoloads exist. The stubs below are duck-typed, exactly like the ones in
# tools/slice6_test_reactor.gd.
extends SceneTree

## How many reactor ticks to time per load. 2000 at 30 Hz is 66 seconds of
## worst-case combat, which is longer than any bout in the game.
const TICKS: int = 2000
## The reactor's own ceiling. Timing anything less would flatter it.
const LIVE: int = 12

var _ran: bool = false


class ReactantStub extends Node2D:
	var shape: Dictionary = {}
	var form: int = 0
	var element: int = 0
	var weight: int = 1

	func reaction_shape() -> Dictionary:
		return shape

	func reaction_active() -> bool:
		return true

	func reaction_element() -> int:
		return element

	func reaction_form() -> int:
		return form

	func reaction_weight() -> int:
		return weight

	func reaction_consume() -> void:
		pass


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return true


func _run() -> void:
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("FAIL: SpellReactor autoload is missing")
		quit(1)
		return
	# Hand-drive the sweep and suppress the picture: this measures the DETECTOR,
	# and a spawned Hollow Purple would be timing a spectacle instead.
	reactor.set_process(false)
	reactor.set(&"spawn_effects", false)

	print("=== REACTION SWEEP COST — %d live effects (%d pair tests/tick), %d ticks ==="
		% [LIVE, LIVE * (LIVE - 1) / 2, TICKS])
	# BEAM x AURA: AURA has no authored row at all, so every pair dies at the
	# sparse-matrix gate. Far apart so nothing can touch even if a row appeared.
	_bench(reactor, "bucket-miss", 0, 5, 4, 4, 4000.0)
	# BARRIER x BARRIER with the SAME element: the bucket exists (the ram, and the
	# authored `none`), the ram's EARTH/ICE predicate refuses, and `none` suppresses
	# — so every pair pays the full rule scan and matches nothing.
	_bench(reactor, "no-rule", 1, 1, 5, 5, 4000.0)
	# PROJECTILE x BARRIER, overlapping: matches `barrier_blocks` and touches, so
	# geometry runs on tick 1 and the memo answers every tick after.
	_bench(reactor, "overlap", 3, 1, 4, 4, 0.0)
	quit(0)


## One timed load. `spread` is how far apart the two halves are placed, which is
## what decides whether geometry can ever say yes.
func _bench(reactor: Node, label: String, form_a: int, form_b: int,
		elem_a: int, elem_b: int, spread: float) -> void:
	reactor.call(&"reset_gate_stats")
	var stubs: Array[Node] = []
	for i: int in LIVE:
		var s: ReactantStub = ReactantStub.new()
		s.form = form_a if i % 2 == 0 else form_b
		s.element = elem_a if i % 2 == 0 else elem_b
		var at: Vector2 = Vector2(spread * float(i % 2), float(i) * 3.0)
		s.shape = SpellGeometry.circle(at, 60.0)
		root.add_child(s)
		stubs.append(s)
		reactor.call(&"register", s, s.form, s.element)
	var live: int = int(reactor.call(&"live_count"))
	# One untimed tick so first-touch costs (the rules() array's first build, the
	# memo's first insert) are not billed to the measurement.
	reactor.call(&"resolve_now")
	var t0: int = Time.get_ticks_usec()
	for _t: int in TICKS:
		reactor.call(&"resolve_now")
	var us: float = float(Time.get_ticks_usec() - t0) / float(TICKS)
	var script: GDScript = load("res://scripts/combat/SpellReactor.gd") as GDScript
	print("  %-12s %2d live   %7.1f us/tick   %5.2f%% of a 60 fps frame   "
			% [label, live, us, 100.0 * us / 16667.0]
		+ "(pairs %d  bucket-miss %d  no-rule %d  memo %d  applied %d)"
			% [int(script.get("pair_tests")), int(script.get("gate_bucket_miss")),
				int(script.get("gate_no_rule")), int(script.get("gate_memo")),
				int(script.get("gate_applied"))])
	for s: Node in stubs:
		reactor.call(&"unregister", s)
		s.free()
