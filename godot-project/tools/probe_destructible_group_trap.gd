# Run: godot --headless --path godot-project --script tools/probe_destructible_group_trap.gd
#
# WHY THE DESTRUCTIBLE STAGE MAY NOT JOIN THE `"destructible"` GROUP — measured.
#
# The obvious wiring for Slice 2 is the one the shipped damage contract already uses
# everywhere: put the stage's collider in group `"destructible"`, give it `damage_at`,
# and every one of the 33 files that already speak that contract carves the ground for
# free. It is one line and it looks right.
#
# It is a trap, and this is the number that says so. `SpellWorld.is_smashable` returns
# TRUE for anything in that group — deliberately, because a crate that just collapsed
# leaves the group while its collider lingers, and a spell must not die on it. Every
# `first_solid` query takes `smash_destructibles` and it DEFAULTS TO TRUE. So the moment
# the ground is "destructible", the ground stops existing for:
#
#     floor_below   — BoulderHurl's rip point, BlastSpell's crater, every snapped decal
#     floor_point   — FaultLine's origin, GraveTide's base
#     ground_path   — FaultLine's travel profile, GraveTide's front
#     is_blocked    — AegisWard's plant test, BoulderHurl's spawn legality
#
# This probe builds a bare floor, fires the same downward floor query across it twice —
# once with the body out of the group and once in it — and counts how many queries stop
# finding a floor. A pass here is not "0 failures", it is a NUMBER: if the second row
# reports 0 misses then the trap does not exist and the `DestructibleStage` header is
# wrong, which is worth knowing either way.
extends SceneTree

const SAMPLES: int = 40
const FLOOR_TOP: float = 780.0
const FLOOR_X0: float = 40.0
const FLOOR_X1: float = 1400.0
const PROBE_FROM_Y: float = 700.0
const PROBE_DIST: float = 400.0


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var holder := Node2D.new()
	root.add_child(holder)
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(FLOOR_X1 - FLOOR_X0, 320.0)
	cs.shape = shape
	body.position = Vector2((FLOOR_X0 + FLOOR_X1) * 0.5, FLOOR_TOP + 160.0)
	body.add_child(cs)
	holder.add_child(body)
	for _f: int in 4:
		await process_frame

	# CONTROL FIRST. If the plain query cannot find a floor that is demonstrably there,
	# every number below is measuring the harness rather than the trap.
	var plain: int = _count_hits(holder)
	print("[group-trap] CONTROL — body NOT in \"destructible\": %d/%d floor queries hit"
		% [plain, SAMPLES])
	if plain != SAMPLES:
		printerr("[group-trap] the control failed — the harness cannot see its own floor."
			+ " Nothing below this means anything.")
		holder.queue_free()
		quit(1)
		return

	body.add_to_group(&"destructible")
	var grouped: int = _count_hits(holder)
	print("[group-trap] body IN \"destructible\" (the trap): %d/%d floor queries hit"
		% [grouped, SAMPLES])
	print("[group-trap] is_smashable(floor) reports %s"
		% [str(SpellWorld.is_smashable(body))])

	# ...and the same query with the opt-out the callers do NOT pass, to show the
	# behaviour is the default and not some special case of this harness.
	var opted_out: int = _count_hits(holder, false)
	print("[group-trap] ...same body, smash_destructibles=false: %d/%d hit"
		% [opted_out, SAMPLES])

	print("[group-trap] VERDICT: joining \"destructible\" costs %d of %d floor queries."
		% [plain - grouped, SAMPLES])
	body.remove_from_group(&"destructible")
	holder.queue_free()
	quit(0)


func _count_hits(ctx: Node, smash: bool = true) -> int:
	var hits: int = 0
	for i: int in SAMPLES:
		var x: float = FLOOR_X0 + (FLOOR_X1 - FLOOR_X0) * (float(i) + 0.5) / float(SAMPLES)
		var r: Dictionary = SpellWorld.floor_below(
			Vector2(x, PROBE_FROM_Y), PROBE_DIST, [], ctx, smash)
		if bool(r["hit"]):
			hits += 1
	return hits
