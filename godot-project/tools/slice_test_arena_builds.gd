# Run: godot --headless --path godot-project --script tools/slice_test_arena_builds.gd
#
# THE DUEL STAGE ACTUALLY BUILDS — asserted on the node that reaches the renderer,
# not on the constant it was authored from.
#
# ⚠ WHY THIS SUITE EXISTS. `slice_test_stage_variants` checked all three stage
# variants eight different ways and every check passed, while `VersusArena` was
# throwing on EVERY bout and drawing no terrain at all:
#
#   SCRIPT ERROR: Invalid assignment of property or key 'terraces' with value of
#   type 'Array' on a base object of type 'Node2D (ArenaTerrain)'.
#       at: VersusArena._build_terrain (VersusArena.gd:862)
#
# `active_terraces()` returns a bare `Array` (it indexes `STAGE_TERRACES:
# Array[Array]`, and GDScript cannot express `Array[Array[Dictionary]]`), and
# `ArenaTerrain.terraces` is `Array[Dictionary]`. The old code assigned the typed
# const `TERRACES` straight across, so the variant work is what un-typed it.
#
# THREE THINGS HID IT, and all three are the same mistake:
#   1. `slice_test_stage_variants` reads `get_script_constant_map()`. It tests the
#      AUTHORED table. The table was always fine.
#   2. `slice_test_sandbox` DOES boot the packed scene — and passed, because a
#      failed property set is not fatal: `_ready` runs on past it, the fighters
#      still spawn, and its assertions are all about fighters.
#   3. `run_all_tests.py` only reads a suite's own pass/fail line, so a
#      `SCRIPT ERROR` on stderr scored as a clean PASS.
#
# So the rule this file encodes: FOR ANYTHING THE PLAYER LOOKS AT, ASSERT THE
# VALUE THAT ARRIVED AT THE NODE. A constant is not evidence that it was applied.
#
# ⚠ FOUND BY THE SCRIPT PATH, NOT BY `class_name ArenaTerrain`: naming the class in
# a `--script` run drags its compile-time dependencies in, which is the same reason
# `slice_test_stage_variants` loads `VersusArena` by path.
extends SceneTree

const ARENA_SCENE_PATH: String = "res://scenes/combat/VersusArena.tscn"
const ARENA_SCRIPT_PATH: String = "res://scripts/combat/VersusArena.gd"
const TERRAIN_SCRIPT: String = "res://scripts/combat/ArenaTerrain.gd"

## Enough frames for `_ready` and one draw pass; the terrain is built synchronously
## in `_ready`, so this is settle margin rather than a wait.
const SETTLE_FRAMES: int = 8

## Pinned so the expected row count is knowable. Every variant must build, so the
## suite walks all of them rather than trusting the roll.
const TESTS: Array[String] = [
	"every_variant_builds_its_terrain",
	"the_terrain_carries_the_rows_it_was_built_from",
	"the_builders_after_the_terrain_still_run",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _script: GDScript = null


func _initialize() -> void:
	_script = load(ARENA_SCRIPT_PATH) as GDScript
	if _script == null:
		printerr("arena_builds: FAIL — could not load VersusArena.gd")
		printerr("arena build tests: 1 FAILED")
		quit(1)
		return
	_run()


func _run() -> void:
	var variants: Array = _script.get_script_constant_map().get("STAGE_TERRACES", []) as Array
	if variants.is_empty():
		_expect(false, "VersusArena has no STAGE_TERRACES at all")

	var built_all: bool = true
	var rows_matched: bool = true
	var heroes_ok: bool = true

	for i: int in variants.size():
		# Pin the layout BEFORE instantiating — `_ready` builds the stage.
		_script.set("stage_layout", i)
		var scene: PackedScene = load(ARENA_SCENE_PATH) as PackedScene
		var arena: Node = scene.instantiate()
		root.add_child(arena)
		for f: int in SETTLE_FRAMES:
			await process_frame

		var terrain: Node = _find_terrain(arena)
		if terrain == null:
			built_all = false
			_expect(false,
				"variant %d built NO ArenaTerrain node — the stage draws bare sky. "
					% i + "A failed property set is not fatal, so `_ready` walks on "
					+ "and only the rock is missing.")
		else:
			var got: Array = terrain.get("terraces") as Array
			var want: int = (variants[i] as Array).size()
			if got.size() != want:
				rows_matched = false
				_expect(false,
					"variant %d's terrain carries %d rows, authored %d — the node the "
						% [i, got.size(), want] + "renderer reads is not the table the "
						+ "suite checks")

		if get_nodes_in_group("hero").size() != 2:
			heroes_ok = false
			_expect(false, "variant %d spawned %d heroes, expected 2"
				% [i, get_nodes_in_group("hero").size()])

		arena.queue_free()
		await process_frame

	_script.set("stage_layout", -1)

	if built_all:
		_completed["every_variant_builds_its_terrain"] = true
	if rows_matched:
		_completed["the_terrain_carries_the_rows_it_was_built_from"] = true
	if heroes_ok:
		_completed["the_builders_after_the_terrain_still_run"] = true

	for t: String in TESTS:
		if not _completed.has(t):
			_fails += 1
			printerr("arena_builds: TEST DID NOT PASS — %s" % t)
	if _fails > 0:
		printerr("arena build tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("arena build tests: all PASS")
		quit(0)


## The terrain by script path — see the header for why not by `class_name`.
func _find_terrain(arena: Node) -> Node:
	for child: Node in arena.get_children():
		var s: Script = child.get_script() as Script
		if s != null and s.resource_path == TERRAIN_SCRIPT:
			return child
	return null


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("arena_builds: FAIL — %s" % msg)
