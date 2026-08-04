# Run headless:
#   godot --headless --path godot-project --script tools/probe_wave_gate.gd
#
# WHEN DOES A WAVE SAY IT IS OVER, AND HOW MANY BODIES ARE STILL STANDING?
#
# Maker, playtesting: "wave 1 spawns two enemies but only clears after one was
# killed, that's a bug that needs to be fixed."
#
# Encounter hands a wave off to the next one while its last `_wave_handoff` bodies
# are still alive (the OVERLAP — see the PACING block in Encounter.gd). That is a
# deliberate feature, but the threshold is derived from `concurrent_cap`, NOT from
# the wave's own BUDGET, and on a small wave the cap is roughly the budget — so the
# "last few stragglers" become a majority of the wave.
#
# This probe answers that with numbers rather than argument. It prints, per wave:
#
#   budget      bodies the wave will spawn
#   cap         max alive at once
#   vanguard    how many land in the opening tick
#   handoff     alive-count at or below which the wave hands off
#   kills       budget - handoff = how many you must kill to advance the wave
#   left%       handoff / budget = the share of the wave still alive when it "clears"
#
# A row where `kills` < budget and left% is large is the bug the maker saw: you
# killed one of two and the wave moved on.
#
# It then RUNS floor 1 live with stub bodies and reports the actual alive count at
# the instant `wave_cleared` fires, so the static table above is not taken on trust.
extends SceneTree

const ENC: String = "res://scripts/combat/Encounter.gd"
const GS: String = "res://scripts/GameState.gd"


func _initialize() -> void:
	_run()


func _run() -> void:
	# ⚠ The tree is not live during `_initialize`: absolute-path lookups error and
	# `get_tree()` returns null, which is exactly what made the first cut of this
	# probe report alive=0 for every wave. One frame fixes it.
	await process_frame
	var enc_script: GDScript = load(ENC) as GDScript
	var gs_script: GDScript = load(GS) as GDScript

	print("== STATIC: authored Ashspire tower ==")
	print("floor wave  budget  cap  vanguard  handoff  kills  left%")
	var tower: Resource = gs_script.build_default_tower()
	for fi: int in tower.floors.size():
		_dump_floor(enc_script, "%d" % (fi + 1), tower.floors[fi])

	print("")
	print("== STATIC: synthesized floors (the null-tower / procedural fallback) ==")
	print("floor wave  budget  cap  vanguard  handoff  kills  left%")
	for f: int in range(1, 7):
		_dump_floor(enc_script, "s%d" % f, gs_script.synthesize_floor_def(f))

	print("")
	print("== LIVE: floor 1, stub bodies, killed one at a time ==")
	await _live(enc_script, gs_script)
	quit(0)


func _dump_floor(enc_script: GDScript, label: String, fd: Resource) -> void:
	var waves: Array = enc_script.resolved_waves(fd)
	for wi: int in waves.size():
		var w: Resource = waves[wi]
		# Mirrors Encounter._start_wave exactly (party of one).
		var budget: int = enc_script.party_budget(maxi(int(w.enemy_budget), 0), 1)
		var cap: int = enc_script.party_cap(maxi(int(w.concurrent_cap), 1), 1)
		var vanguard: int = clampi(w.resolved_vanguard(enc_script.vanguard_for_cap(cap)), 0, budget)
		var handoff: int = clampi(w.resolved_handoff(enc_script.handoff_for_cap(cap)), 0,
			enc_script.handoff_ceiling(budget))
		var kills: int = budget - handoff
		print("%5s %4d  %6d %4d  %8d  %7d  %5d  %4.0f%%" % [
			label, wi + 1, budget, cap, vanguard, handoff, kills,
			100.0 * float(handoff) / float(maxi(budget, 1))])


# ─────────────────────────────────────────────────────────── the live measurement
## ⚠ THE ENCOUNTER IS BUILT WITH `load()`, NEVER NAMED AT PARSE TIME. Encounter.gd
## preloads Enemy.tscn, whose script names the `Sfx` autoload — and a `--script`
## harness compiles this file BEFORE the autoloads are registered, so a
## `class Stub extends "res://scripts/combat/Encounter.gd"` here makes the whole
## probe fail to compile. Same trap slice_test_boss.gd documents at its top.
func _live(_enc_script: GDScript, gs_script: GDScript) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var hero := Node2D.new()
	hero.add_to_group("hero")
	hero.position = Vector2(200, 400)
	arena.add_child(hero)

	var enc: Node = _enc_script.new()
	arena.add_child(enc)
	var log: Array[String] = []
	enc.wave_started.connect(func(i: int, n: int) -> void:
		log.append("  wave %d/%d STARTED   alive=%d" % [i + 1, n, _alive()]))
	enc.wave_cleared.connect(func(i: int, n: int) -> void:
		log.append("  wave %d/%d CLEARED   alive=%d  <-- bodies still standing" % [i + 1, n, _alive()]))
	enc.boss_spawned.connect(func() -> void:
		log.append("  GUARDIAN arrives   alive=%d" % _alive()))
	enc.cleared.connect(func() -> void: log.append("  floor CLEARED"))

	var tower: Resource = gs_script.build_default_tower()
	enc.run_floor(tower.floors[0])

	# ⚠ DO NOT KILL ON A FRAME TIMER. Headless frames are ~1000x faster than the
	# wave's own 0.35s spawn interval, so a "kill every N frames" harness empties the
	# room faster than it fills and every wave hands off at alive=0 — which is a
	# measurement of the harness, not of the game. Instead: wait until the wave has
	# finished ARRIVING (budget spent, no marks pending), then kill one body per frame
	# and watch where the gate trips.
	var frames: int = 0
	while frames < 20000:
		await process_frame
		frames += 1
		var spawned: int = int(enc.get("_wave_spawned"))
		var budget: int = int(enc.get("_wave_budget"))
		var arrived: bool = spawned >= budget and int(enc.call("pending_spawn_count")) == 0
		if arrived and _alive() > 0:
			for b: Node in root.get_tree().get_nodes_in_group("enemy"):
				if b.has_method("current_phase"):
					continue     # keep the guardian until last, like a real fight
				log.append("    killed one -> alive=%d" % (_alive() - 1))
				b.remove_from_group("enemy")
				b.queue_free()
				break
		# The wave gate is all this measures — stop the moment the guardian is up
		# rather than idling out the 20000-frame budget waiting for it to die.
		if int(enc.phase()) >= 3:   # Phase.BOSS / DONE
			break
	for line: String in log:
		print(line)
	print("  (ran %d frames)" % frames)


func _alive() -> int:
	return root.get_tree().get_nodes_in_group("enemy").size()
