# Render the Ashen Guardian across its 3 phases.
# MUST run with the GUI binary (dummy renderer draws black):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/boss_capture.gd
# Outputs: user://boss_p1.png, boss_p2.png, boss_p3.png
# All boss access is duck-typed (.call/.get) — no compile-time Boss dependency.
#
# ⚠ THIS TOOL WROTE NOTHING FOR AS LONG AS IT HAS EXISTED IN ITS OLD FORM, and it
# said so only in one line of stderr. It used to force GameState to floor 5 (the
# BOSS floor), instantiate the Arena, settle 70 frames and expect the guardian to
# be standing there. That was true of an older Encounter. It is not true now: the
# guardian arrives in `Phase.BOSS`, which is the END of a floor, after WAVES and
# SURGE have been fought through. At frame 70 there is no boss on the stage and
# never will be, so `_find_boss()` returned null, the tool printed
# "no boss spawned" and quit, and `run_capture.py` reported NO FRAMES WRITTEN.
#
# The Arena grew a static for exactly this caller — `Arena.boss_rush`, whose own
# comment says "set true (by the duel's Esc menu, OR BY A TOOL) before this scene
# loads": the sandbox branch then builds the room, spawns the guardian and nothing
# else, and switches to boss framing. This tool was never migrated to it.
#
# Arming it is also the safer path: boss_rush leaves GameState untouched, so a
# capture can no longer leave a half-begun climb in the maker's save. Forcing
# `_run_active`/`_floor` the old way did write to it.
extends SceneTree

## By PATH, never by `class_name Arena` — a `--script` harness compiles whatever
## it names, and Arena's dependency chain reaches autoloads. Same idiom as
## `boot_check.gd` and `VersusArena._enter_boss_fight`, the two other callers.
const ARENA_SCRIPT: String = "res://scripts/combat/Arena.gd"
const ARENA_SCENE: String = "res://scenes/combat/Arena.tscn"


func _initialize() -> void:
	_run()


func _find_boss() -> Node:
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if e.has_method("current_phase"):
			return e
	return null


func _settle(n: int) -> void:
	for i: int in n:
		await process_frame


## Stand the (non-moving) hero right beside the boss so the camera frames both
## and the colossus scale reads. Cosmetic-only for the capture.
func _frame_with_hero(boss: Node) -> void:
	if boss == null:
		return
	for h in root.get_tree().get_nodes_in_group("hero"):
		if h is Node2D:
			(h as Node2D).global_position = (boss as Node2D).global_position + Vector2(150.0, 40.0)
			break


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("boss_capture: saved ", ProjectSettings.globalize_path(path))


func _run() -> void:
	await process_frame

	# Arm the boss rush BEFORE the scene loads — the flag is read in Arena._ready
	# and consumed there, so setting it afterwards does nothing at all.
	var arena_script: GDScript = load(ARENA_SCRIPT) as GDScript
	if arena_script == null:
		printerr("boss_capture: could not load ", ARENA_SCRIPT)
		quit(1)
		return
	arena_script.set("boss_rush", true)

	var packed: PackedScene = load(ARENA_SCENE) as PackedScene
	if packed == null:
		printerr("boss_capture: ", ARENA_SCENE, " did not load as a PackedScene")
		quit(1)
		return
	root.add_child(packed.instantiate())
	await _settle(70)

	var boss: Node = _find_boss()
	if boss == null:
		printerr("boss_capture: no boss spawned — Arena.boss_rush did not put a ",
			"node with current_phase() in the `enemy` group. Check ",
			"Encounter.spawn_boss and the sandbox branch of Arena._ready.")
		quit(1)
		return

	# P1 — waking colossus (stone tint, ember aura tier 3, dim core).
	boss.call("_enter_phase", 1)
	_frame_with_hero(boss)
	await _settle(30)
	await _shoot("user://boss_p1.png")

	# P2 — fury (heated tint, tier 4, brighter core).
	var mx: int = int(boss.get("max_hp"))
	boss.call("take_damage", int(mx * 0.34) + 1)
	_frame_with_hero(boss)
	await _settle(25)
	await _shoot("user://boss_p2.png")

	# P3 — ashfall (near-molten, tier 5, max core glow).
	boss = _find_boss()
	if boss != null:
		boss.call("take_damage", int(mx * 0.34) + 1)
		_frame_with_hero(boss)
		await _settle(30)
	await _shoot("user://boss_p3.png")

	quit(0)
