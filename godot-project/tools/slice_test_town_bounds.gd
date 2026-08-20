extends SceneTree
## YOU CANNOT LEAVE THE TOWN, AND IF YOU SOMEHOW DO YOU COME BACK.
##
## Maker: *"please make sure people cannot jump off the left panel in the lobby to get
## out the map, and if they fall out to respawn at the entrance"*.
##
## ⚠ THIS DRIVES A REAL BODY AT THE REAL WALLS RATHER THAN GREPPING FOR THEM. A source
## test would have passed the moment `_build_bounds` existed, whether or not the walls
## were on the right layer, in the right place, or tall enough to matter — and "the wall
## is built but the player goes through it" is exactly the bug being fixed. So: put a
## body outside, shove a body at speed, drop a body into the void, and ask the engine.
##
## Run:
##   godot --headless --path godot-project --script tools/slice_test_town_bounds.gd

const TOWN := "res://scenes/Main.tscn"
const TESTS: Array[String] = [
	"the_walls_exist_and_are_solid",
	"a_body_cannot_be_driven_off_the_left",
	"a_body_that_falls_out_returns_to_the_entrance",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _world: Node = null
var _player: Node2D = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var scene: Node = (load(TOWN) as PackedScene).instantiate()
	root.add_child(scene)
	for _i in 30:
		await physics_frame
	_world = scene
	var players: Array = root.get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_expect(false, "the town spawned a player body")
		_finish()
		return
	_player = players[0] as Node2D

	await _test_the_walls_exist_and_are_solid()
	await _test_a_body_cannot_be_driven_off_the_left()
	await _test_a_body_that_falls_out_returns_to_the_entrance()
	_finish()


func _finish() -> void:
	for t: String in TESTS:
		_expect(_completed.has(t), "test `%s` ran to completion" % t)
	if _fails > 0:
		printerr("Town bounds tests: %d FAILED" % _fails)
	else:
		print("Town bounds tests: all PASS")
	quit(1 if _fails > 0 else 0)


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("  FAIL: %s" % what)


func _k(name: String) -> float:
	var sc: GDScript = load("res://scripts/World.gd") as GDScript
	return float(sc.get_script_constant_map().get(name, 0.0))


## The walls are where the ground ends, not somewhere arbitrary.
func _test_the_walls_exist_and_are_solid() -> void:
	var left: float = _k("BOUND_LEFT")
	var right: float = _k("BOUND_RIGHT")
	var width: float = _k("TOWN_WIDTH")
	_expect(left < 0.0, "the left wall is at or beyond the ground's left edge (%.0f)" % left)
	_expect(right > width, "the right wall is past the town's width (%.0f)" % right)
	# Tall enough that the LOFT — the "left panel" — cannot be jumped over. The loft
	# sits 118 px up and a jump adds ~105 more.
	_expect(_k("BOUND_HEIGHT") > 118.0 + 105.0 + 60.0,
		"the walls are taller than a jump taken from the loft (%.0f)" % _k("BOUND_HEIGHT"))
	_completed["the_walls_exist_and_are_solid"] = true
	await process_frame


## THE REPORTED BUG. Stand on the loft's left edge and drive left at speed; the body
## must still be inside the world when it lands.
func _test_a_body_cannot_be_driven_off_the_left() -> void:
	var loft_c: Vector2 = _loft_center()
	var loft_w: float = _loft_size().x
	var left_edge: float = loft_c.x - loft_w * 0.5
	# On the loft, at its left lip, already moving left hard — worse than any jump a
	# player can actually take from there.
	_player.global_position = Vector2(left_edge + 4.0, loft_c.y - 20.0)
	_player.set(&"velocity", Vector2(-600.0, -420.0))
	for _i in 240:
		await physics_frame
	var x: float = _player.global_position.x
	_expect(x > _k("BOUND_LEFT"),
		"launched off the loft's left edge at 600 px/s, the body is still inside the "
		+ "world (ended at x %.0f, wall at %.0f)" % [x, _k("BOUND_LEFT")])
	# ...and it did not end up under the floor either.
	_expect(_player.global_position.y < _k("GROUND_Y") + _k("FALL_OUT_MARGIN"),
		"...and it is not below the world (y %.0f)" % _player.global_position.y)
	_completed["a_body_cannot_be_driven_off_the_left"] = true


## The belt to the walls' braces: put a body in the void by hand and it must come back
## to the doorstep, not keep falling.
func _test_a_body_that_falls_out_returns_to_the_entrance() -> void:
	var spawn: Vector2 = _spawn()
	_player.global_position = Vector2(-900.0, _k("GROUND_Y") + _k("FALL_OUT_MARGIN") + 200.0)
	_player.set(&"velocity", Vector2(0.0, 900.0))
	for _i in 30:
		await physics_frame
	_expect(_player.global_position.distance_to(spawn) < 90.0,
		"a body dropped into the void is put back at the entrance (ended %.0f px away)"
			% _player.global_position.distance_to(spawn))
	# The fall must not be carried through the teleport, or the body punches straight
	# back down through the floor it just arrived on.
	var v: Vector2 = _player.get(&"velocity")
	_expect(absf(v.y) < 400.0,
		"...and it does not arrive still carrying the fall (vy %.0f)" % v.y)
	_completed["a_body_that_falls_out_returns_to_the_entrance"] = true


func _spawn() -> Vector2:
	var sc: GDScript = load("res://scripts/World.gd") as GDScript
	return sc.get_script_constant_map().get("PLAYER_SPAWN", Vector2.ZERO)


func _loft_center() -> Vector2:
	var sc: GDScript = load("res://scripts/World.gd") as GDScript
	return sc.get_script_constant_map().get("LOFT_CENTER", Vector2.ZERO)


func _loft_size() -> Vector2:
	var sc: GDScript = load("res://scripts/World.gd") as GDScript
	return sc.get_script_constant_map().get("LOFT_SIZE", Vector2.ZERO)
