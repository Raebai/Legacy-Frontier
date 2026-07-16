# Run: godot --headless --path godot-project --script tools/slice_test_boss.gd
# The Ashspire Guardian: Encounter spawns a real multi-phase Boss on BOSS floors.
# Verifies spawn/scale/clear-gate, HP-gated phase transitions + signals, per-phase
# attack sets, spectacle retargeting onto "hero", and death -> defeated + drops
# out of "enemy". Uses the _initialize/await idiom.
#
# NOTE: everything boss-specific is accessed by NAME (.get/.call/.connect) — never
# `is Boss` or `boss.method()` directly — so this test script does NOT compile-time
# depend on Boss.gd. That matters: referencing Boss at this script's compile time
# would pull its whole spell chain into early boot, before the Sfx autoload exists.
extends SceneTree

var _failed: int = 0


func _initialize() -> void:
	_run()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_failed += 1


func _find_boss() -> Node:
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if e.has_method("current_phase"):   # only the Boss exposes this
			return e
	return null


func _run() -> void:
	var gs_script: GDScript = load("res://scripts/GameState.gd") as GDScript
	var enc_script: GDScript = load("res://scripts/combat/Encounter.gd") as GDScript
	var tower: Resource = gs_script.build_default_tower()
	var boss_def: Resource = tower.floors[4]
	_expect(int(boss_def.floor_type) == 2, "Ashspire floor 5 is BOSS (type 2)")

	var arena := Node2D.new()
	root.add_child(arena)
	var enc: Node = enc_script.new()
	arena.add_child(enc)
	enc.run_floor(boss_def)
	await process_frame
	await process_frame

	var guardian: Node = _find_boss()
	_expect(guardian != null, "boss floor spawned a Boss")
	if guardian == null:
		_finish()
		return
	_expect(int(guardian.get("max_hp")) >= 400, "guardian has boss-scale HP (>= 400)")
	_expect(int(guardian.get("touch_damage")) >= 20, "guardian hits hard (touch >= 20)")
	_expect(guardian.is_in_group("enemy"), "guardian is in 'enemy' (clear gate waits for it)")
	var rig: Node = guardian.get_node_or_null("Rig")
	_expect(rig != null and float(rig.get("height")) > 60.0, "guardian rig is a colossus (height > 60)")

	# --- phases: start in INTRO, then HP-gated P1 -> P2 -> P3 ---
	_expect(int(guardian.call("current_phase")) == 0, "guardian starts in INTRO (phase 0)")
	var seen_phases: Array = []
	guardian.connect("phase_changed", func(p: int) -> void: seen_phases.append(p))
	guardian.call("_enter_phase", 1)   # skip the 2.6s intro timer for the test
	_expect(int(guardian.call("current_phase")) == 1, "entered P1")
	var mx: int = int(guardian.get("max_hp"))
	guardian.call("take_damage", int(mx * 0.4))
	_expect(int(guardian.call("current_phase")) == 2, "crossing 66% HP -> P2")
	guardian.call("take_damage", int(mx * 0.4))
	_expect(int(guardian.call("current_phase")) == 3, "crossing 33% HP -> P3")
	_expect(seen_phases.has(2) and seen_phases.has(3), "phase_changed fired for P2 + P3")

	# --- each phase has a real attack set ---
	for ph: int in [1, 2, 3]:
		_expect((guardian.call("_phase_attack_ids", ph) as Array).size() >= 2, "phase %d has >= 2 attacks" % ph)

	# --- spectacle retargeting: a hero-targeted blast hurts a "hero", not the boss ---
	var stub := _HeroStub.new()
	stub.add_to_group("hero")
	arena.add_child(stub)
	stub.global_position = Vector2(400, 300)
	var boss_hp_before: int = int(guardian.get("hp"))
	var blast: Node = load("res://scenes/combat/BlastSpell.tscn").instantiate()
	arena.add_child(blast)
	blast.configure({"target_group": "hero", "damage": 25, "radius": 90, "knockback": 0, "windup": 0.01})
	blast.detonate_now(Vector2(400, 300))
	await process_frame
	_expect(stub.hp < 100, "hero-targeted blast damaged the hero stub")
	_expect(int(guardian.get("hp")) == boss_hp_before, "hero-targeted blast did NOT damage the boss")

	# --- death -> defeated + leaves "enemy" -> floor can clear ---
	var was_defeated: Array = [false]
	guardian.connect("defeated", func() -> void: was_defeated[0] = true)
	guardian.call("take_damage", int(guardian.get("hp")) + 10)
	await process_frame
	await process_frame
	_expect(was_defeated[0], "boss emitted 'defeated' on death")
	_expect(_find_boss() == null, "dead boss left the 'enemy' group (clear gate satisfied)")

	# --- regression: a COMBAT floor spawns no Boss ---
	var enc2: Node = enc_script.new()
	arena.add_child(enc2)
	enc2.run_floor(tower.floors[0])
	await process_frame
	await process_frame
	_expect(_find_boss() == null, "a COMBAT floor spawns no Boss")

	_finish()


func _finish() -> void:
	if _failed > 0:
		printerr("Boss tests: %d FAILED" % _failed)
		quit(1)
	else:
		print("Boss tests: all PASS")
		quit(0)


## Minimal hero stand-in: a Node2D in group "hero" with hp + take_damage.
class _HeroStub extends Node2D:
	var hp: int = 100
	var max_hp: int = 100
	func take_damage(amount: int) -> void:
		hp = maxi(hp - amount, 0)
