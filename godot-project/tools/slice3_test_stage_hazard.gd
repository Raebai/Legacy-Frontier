# Run: godot --headless --path godot-project --script tools/slice3_test_stage_hazard.gd
# Runs on the first _process frame (not _init): StageHazard joins its group +
# builds its collider in _ready, and _ready only fires once the tree is live —
# in _init, add_child does NOT run _ready synchronously. Real physics overlap is
# never used: tests drive the directly-callable seams report_fallers /
# slide_bodies with hand-built stub bodies (slice2 idiom).
extends SceneTree

const HazardScript: GDScript = preload("res://scripts/combat/StageHazard.gd")

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_pit_reports_fighters_once()
	failed += _test_slope_slides_fighters()
	if failed > 0:
		printerr("Slice3 stage-hazard tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice3 stage-hazard tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_stub(group: String = "") -> Node2D:
	var stub := Node2D.new()
	if group != "":
		stub.add_to_group(group)
	root.add_child(stub)
	return stub


func _test_pit_reports_fighters_once() -> int:
	var failed: int = 0
	var pit: StageHazard = HazardScript.new()
	pit.mode = StageHazard.Mode.PIT
	root.add_child(pit)
	failed += _expect(pit.is_in_group("stage_hazard"), "hazard joins stage_hazard group in _ready")

	var hero: Node2D = _make_stub("hero")
	var enemy: Node2D = _make_stub("enemy")
	var crate: Node2D = _make_stub()   # non-fighter: must never report

	var fallen: Array = []
	pit.fighter_fell.connect(func(body) -> void: fallen.append(body))

	var emitted: int = pit.report_fallers([hero, enemy, crate])
	failed += _expect(emitted == 2, "pit reports exactly the 2 fighters (got %d)" % emitted)
	failed += _expect(fallen.size() == 2 and (hero in fallen) and (enemy in fallen), "fighter_fell emitted for hero + enemy")
	failed += _expect(not (crate in fallen), "non-fighter never triggers fighter_fell")

	# Same still-overlapping bodies again -> dedup, zero emits.
	emitted = pit.report_fallers([hero, enemy, crate])
	failed += _expect(emitted == 0, "same overlapping bodies are not re-reported (got %d)" % emitted)
	failed += _expect(fallen.size() == 2, "no duplicate fighter_fell signals")

	# A fresh fighter arriving alongside already-reported ones still emits.
	var late: Node2D = _make_stub("enemy")
	emitted = pit.report_fallers([hero, enemy, late])
	failed += _expect(emitted == 1 and (late in fallen), "a fresh fighter still emits (got %d)" % emitted)

	# Body leaves the pit -> dedup entry pruned -> a respawn can fall again.
	pit.report_fallers([])
	emitted = pit.report_fallers([hero])
	failed += _expect(emitted == 1, "a fighter that left can fall (and report) again (got %d)" % emitted)

	for n: Node in [pit, hero, enemy, crate, late]:
		root.remove_child(n)
		n.free()
	return failed


func _test_slope_slides_fighters() -> int:
	var failed: int = 0
	var slope: StageHazard = HazardScript.new()
	slope.mode = StageHazard.Mode.SLOPE
	slope.slide_dir = Vector2.RIGHT
	slope.slide_strength = 100.0
	root.add_child(slope)

	var fighter: Node2D = _make_stub("hero")
	var bystander: Node2D = _make_stub()   # non-fighter: must not be pushed
	fighter.global_position = Vector2.ZERO
	bystander.global_position = Vector2.ZERO

	slope.slide_bodies([fighter, bystander], 0.1)
	failed += _expect(
		fighter.global_position.is_equal_approx(Vector2(10, 0)),
		"fighter slides +10px in x (100 px/s * 0.1 s), got %s" % str(fighter.global_position)
	)
	failed += _expect(bystander.global_position.is_equal_approx(Vector2.ZERO), "non-fighter is not moved")

	# Zero slide_dir guard: no NaN, no movement.
	slope.slide_dir = Vector2.ZERO
	slope.slide_bodies([fighter], 0.1)
	failed += _expect(fighter.global_position.is_equal_approx(Vector2(10, 0)), "zero slide_dir is a safe no-op")

	for n: Node in [slope, fighter, bystander]:
		root.remove_child(n)
		n.free()
	return failed
