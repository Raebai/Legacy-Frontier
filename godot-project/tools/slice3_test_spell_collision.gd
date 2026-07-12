# Run: godot --headless --path godot-project --script tools/slice3_test_spell_collision.gd
# Regression for the maker's "cast goes THROUGH items" bug: a Spell must STOP on
# solid cover (DestructibleTerrain) and plain walls (StaticBody2D), never phase
# through. Uses a REAL physics space (extends SceneTree + await physics_frame,
# the sequence_capture idiom) because the fix is a segment raycast in
# Spell._physics_process — a synchronous helper test can't exercise it.
#
# Runtime load()s (never preload): Spell/DestructibleTerrain scripts reference
# autoload globals (Sfx/Juice) that only register once the main loop is live.
extends SceneTree

const SPELL_SCENE: String = "res://scenes/combat/Spell.tscn"
const TERRAIN_SCRIPT: String = "res://scripts/combat/DestructibleTerrain.gd"
const STEP_FRAMES: int = 40  # >> the ~13 frames a 460px/s bolt needs to cross 100px


func _initialize() -> void:
	_run()  # fire-and-forget: awaits inside, quits when done


func _run() -> void:
	var failed: int = 0
	failed += await _test_terrain_stops_bolt()
	failed += await _test_wall_stops_bolt()
	failed += await _test_empty_space_flies_free()
	if failed > 0:
		printerr("Slice3 spell-collision tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice3 spell-collision tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_spell(at: Vector2, dir: Vector2) -> Area2D:
	var spell: Area2D = (load(SPELL_SCENE) as PackedScene).instantiate()
	root.add_child(spell)
	spell.global_position = at
	spell.launch(dir)
	return spell


## A destructible cover block (StaticBody2D, layer 5, group "destructible") in the
## bolt's path must be hit + damaged, and the bolt consumed — not passed through.
func _test_terrain_stops_bolt() -> int:
	var failed: int = 0
	var terrain: StaticBody2D = (load(TERRAIN_SCRIPT) as GDScript).new()
	terrain.global_position = Vector2(400.0, 0.0)
	root.add_child(terrain)
	var spell: Area2D = _make_spell(Vector2(300.0, 0.0), Vector2.RIGHT)
	await physics_frame  # register bodies in the space
	for _i: int in STEP_FRAMES:
		if not is_instance_valid(spell):
			break
		await physics_frame
	failed += _expect(not is_instance_valid(spell), "bolt consumed by cover (did not pass through)")
	failed += _expect(
		is_instance_valid(terrain) and terrain.hp < terrain.max_hp,
		"cover took spell damage (hp %s < %s)" % [
			terrain.hp if is_instance_valid(terrain) else -1, terrain.max_hp if is_instance_valid(terrain) else -1
		]
	)
	if is_instance_valid(terrain):
		terrain.queue_free()
	return failed


## A plain wall (StaticBody2D on layer 1, no group) must also stop the bolt.
func _test_wall_stops_bolt() -> int:
	var failed: int = 0
	var wall := StaticBody2D.new()
	wall.global_position = Vector2(400.0, 200.0)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64.0, 64.0)
	cs.shape = shape
	wall.add_child(cs)  # default collision_layer = 1
	root.add_child(wall)
	var spell: Area2D = _make_spell(Vector2(300.0, 200.0), Vector2.RIGHT)
	await physics_frame
	for _i: int in STEP_FRAMES:
		if not is_instance_valid(spell):
			break
		await physics_frame
	failed += _expect(not is_instance_valid(spell), "bolt stopped by a plain wall")
	wall.queue_free()
	return failed


## Control: with nothing in the way, the bolt keeps flying (the raycast must not
## false-positive and eat a bolt that hit nothing).
func _test_empty_space_flies_free() -> int:
	var failed: int = 0
	var spell: Area2D = _make_spell(Vector2(-2000.0, -2000.0), Vector2.RIGHT)
	await physics_frame
	for _i: int in 10:
		await physics_frame
	failed += _expect(is_instance_valid(spell), "bolt over empty space is still flying (no false stop)")
	if is_instance_valid(spell):
		spell.queue_free()
	return failed
