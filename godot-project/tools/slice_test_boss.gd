# Run: godot --headless --path godot-project --script tools/slice_test_boss.gd
# Boss floor: Encounter.run_floor on a BOSS FloorDef spawns ONE scaled gold
# guardian (BRUTE base) with boss-scale HP, joined to the "enemy" group so the
# existing "alive == 0" clear gate waits for it. Needs the tree + a couple frames
# for Enemy._ready, so it uses the _initialize/await idiom (like combat_capture).
extends SceneTree

var _failed: int = 0


func _initialize() -> void:
	_run()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_failed += 1


func _run() -> void:
	var gs_script: GDScript = load("res://scripts/GameState.gd") as GDScript
	var enc_script: GDScript = load("res://scripts/combat/Encounter.gd") as GDScript

	# Real BOSS FloorDef = the Ashspire's floor 5.
	var tower: Resource = gs_script.build_default_tower()
	var boss_def: Resource = tower.floors[4]
	_expect(int(boss_def.floor_type) == 2, "Ashspire floor 5 is BOSS (type 2)")

	# Fake arena parent so Encounter.get_parent() has somewhere to add the guardian.
	var arena := Node2D.new()
	root.add_child(arena)
	var enc: Node = enc_script.new()
	arena.add_child(enc)

	enc.run_floor(boss_def)
	# Let the spawned Enemy run _ready (add_to_group, apply defaults, rig, bars).
	await process_frame
	await process_frame

	var enemies: Array = root.get_tree().get_nodes_in_group("enemy")
	_expect(not enemies.is_empty(), "boss floor spawned at least one enemy")

	# The guardian is the one with boss-scale HP (a normal brute on floor 5 is
	# ~70*1.6=112; the guardian is 520*1.6=832 before difficulty).
	var guardian: Node = null
	for e in enemies:
		if int(e.max_hp) >= 400:
			guardian = e
			break
	_expect(guardian != null, "a boss-scale guardian is present (max_hp >= 400)")
	if guardian != null:
		_expect(int(guardian.touch_damage) >= 20, "guardian hits hard (touch >= 20)")
		_expect(bool(guardian.uses_telegraphed_attack), "guardian telegraphs its heavy swing")
		var rig: Node = guardian.get_node_or_null("Rig")
		if rig != null and is_instance_valid(rig):
			_expect(float(rig.get("height")) > 30.0, "guardian rig is enlarged")

	# A non-boss (COMBAT) floor spawns NO boss up front.
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	await process_frame
	var enc2: Node = enc_script.new()
	arena.add_child(enc2)
	enc2.run_floor(tower.floors[0])   # COMBAT
	await process_frame
	await process_frame
	var after: Array = root.get_tree().get_nodes_in_group("enemy")
	var big: int = 0
	for e in after:
		if int(e.max_hp) >= 400:
			big += 1
	_expect(big == 0, "a COMBAT floor spawns no boss-scale guardian")

	if _failed > 0:
		printerr("Boss tests: %d FAILED" % _failed)
		quit(1)
	else:
		print("Boss tests: all PASS")
		quit(0)
