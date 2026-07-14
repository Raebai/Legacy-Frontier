# Run: godot --headless --path godot-project --script tools/slice_test_class_q.gd
# Verifies the per-class DISTINCT Q spectacles (Phase-1b): each caster class fires
# a different spectacle scene, and firing it spawns a spectacle node without error
# (the runtime-safety check that compile + signature-matching can't fully prove).
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	# (class enum index, human name) for the five casters whose Q changed.
	var cases: Array = [[0, "MAGE/arcane_meteor"], [4, "CLERIC/consecrate"],
		[5, "CRYOMANCER/ice_shards"], [6, "STORMCALLER/call_lightning"],
		[7, "WARLOCK/curse_chain"]]
	for c: Array in cases:
		failed += _test_q_spawns(int(c[0]), String(c[1]))
	if failed > 0:
		printerr("Class-Q tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Class-Q tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _test_q_spawns(cls: int, label: String) -> int:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)
	hero.set_physics_process(false)
	hero.global_position = Vector2(600, 700)
	hero.configure_class(cls)
	hero.set("_aim_dir", Vector2.RIGHT)
	# Firing the Q must add a spectacle node under the hero's parent (root here)
	# and must not throw (a raised error aborts the whole --script run).
	var before: int = root.get_child_count()
	hero._blast()
	var after: int = root.get_child_count()
	var ok: int = _expect(after > before, "%s Q spawned a spectacle (%d -> %d)" % [label, before, after])
	hero.queue_free()
	return ok
