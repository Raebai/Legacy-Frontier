# Run: godot --headless --path godot-project --script tools/slice_test_sandbox.gd
# Task 1 (Stick Fight Feel Foundation): boots the sandbox exactly like a real F5
# would — loads the packed VersusArena.tscn (project.godot's new main_scene), not
# just the bare script — settles ~70 frames (arena_wide_capture.gd's idiom: the
# fighters/dummies spawn a little above their surface and fall onto it) so
# gravity has actually landed everyone, then asserts the dummy contract: >=2
# practice dummies exist, each is in BOTH "enemy" (so every existing hero
# attack/spell — which targets that group — hits them with zero spell-file
# edits) and "dummy" (VersusArena._bots_alive excludes that group, so dummies
# can never block the win condition — see VersusArena.gd), each is flagged
# `passive`, and each sits near P1_SPAWN. SceneTree-runner shape mirrors
# slice_test_coop.gd / slice3_test_versus.gd.
extends SceneTree

const ARENA_SCENE_PATH: String = "res://scenes/combat/VersusArena.tscn"
const SETTLE_FRAMES: int = 70
## Loose leash around P1_SPAWN: dummies sit at fixed offsets either side of it
## (VersusArena.DUMMY_X_OFFSETS, +-120px), well inside this radius even after
## gravity settles them onto the ground surface.
const NEAR_SPAWN_RADIUS: float = 250.0

var _arena: Node2D = null


func _initialize() -> void:
	var arena_scene: PackedScene = load(ARENA_SCENE_PATH)
	_arena = arena_scene.instantiate()
	root.add_child(_arena)  # _ready builds the whole match + dummies synchronously
	_run()


func _run() -> void:
	for i: int in SETTLE_FRAMES:
		await process_frame

	var failed: int = 0
	failed += _test_dummies_exist_and_are_flagged()
	failed += _test_dummies_positioned_near_spawn()

	if failed > 0:
		printerr("sandbox tests: %d FAILED" % failed)
		quit(1)
	else:
		print("sandbox tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_dummies_exist_and_are_flagged() -> int:
	var failed: int = 0
	var dummies: Array = get_nodes_in_group("dummy")
	failed += _expect(
		dummies.size() >= 2, "at least 2 practice dummies exist, got %d" % dummies.size()
	)
	for d: Node in dummies:
		failed += _expect(
			d.is_in_group("enemy"), "dummy is also in group 'enemy' (so hero attacks hit it)"
		)
		failed += _expect(bool(d.get("passive")) == true, "dummy is flagged passive")
	return failed


func _test_dummies_positioned_near_spawn() -> int:
	var failed: int = 0
	var spawn: Vector2 = _arena.P1_SPAWN
	for d: Node in get_nodes_in_group("dummy"):
		if not d is Node2D:
			failed += _expect(false, "dummy %s is a Node2D" % str(d))
			continue
		var dist: float = (d as Node2D).global_position.distance_to(spawn)
		failed += _expect(
			dist <= NEAR_SPAWN_RADIUS,
			"dummy positioned near P1_SPAWN, got distance %.1f" % dist
		)
	return failed
