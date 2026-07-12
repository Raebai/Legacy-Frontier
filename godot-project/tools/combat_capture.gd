# Combat capture: boot a combat scene, let bots fight, and render a CONTACT SHEET
# of N frames over a few seconds into ONE png (so motion / telegraphs / spell
# effects are visible in a single image), plus two full-res "money" frames.
#
# MUST run with the GUI (non-headless) binary — the dummy renderer draws black:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/combat_capture.gd -- <scene_res_path> <mode>
#
# Outputs (in user://):
#   combat_sheet.png   — a 4x3 contact sheet of the fight over ~4s
#   combat_full_a.png  — full-res frame mid-run
#   combat_full_b.png  — full-res frame late-run
# Optional user args (after --): a res:// scene path (default VersusArena);
#   "telegraphs" to force every archetype into a repeating windup so the tells
#   are guaranteed on-screen.
extends SceneTree

const DEFAULT_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const SHEET_PATH: String = "user://combat_sheet.png"
const FULL_A_PATH: String = "user://combat_full_a.png"
const FULL_B_PATH: String = "user://combat_full_b.png"
const SETTLE_FRAMES: int = 70      # spawn + drop + settle before the first tile
const TILES_COLS: int = 4
const TILES_ROWS: int = 3
const FRAME_GAP: int = 20           # physics frames between contact-sheet tiles
const TILE_W: int = 320
const TILE_H: int = 180

var _mode: String = "fight"


func _initialize() -> void:
	var scene_path: String = DEFAULT_SCENE
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("res://"):
			scene_path = arg
		elif arg == "telegraphs":
			_mode = "telegraphs"
		elif arg == "status":
			_mode = "status"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("combat_capture: could not load ", scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	_run()


func _run() -> void:
	for i: int in SETTLE_FRAMES:
		await process_frame
	var total: int = TILES_COLS * TILES_ROWS
	var tiles: Array = []
	var full_a: Image = null
	var full_b: Image = null
	for t: int in total:
		if _mode == "telegraphs":
			_force_windups()
		elif _mode == "status":
			_apply_statuses()
		for f: int in FRAME_GAP:
			await process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		if frame == null:
			continue
		if t == total / 3:
			full_a = frame.duplicate()
		if t == total - 2:
			full_b = frame.duplicate()
		var tile: Image = frame.duplicate()
		tile.resize(TILE_W, TILE_H, Image.INTERPOLATE_BILINEAR)
		tiles.append(tile)
	_save_sheet(tiles)
	if full_a != null:
		full_a.save_png(FULL_A_PATH)
		print("combat_capture: saved ", ProjectSettings.globalize_path(FULL_A_PATH))
	if full_b != null:
		full_b.save_png(FULL_B_PATH)
		print("combat_capture: saved ", ProjectSettings.globalize_path(FULL_B_PATH))
	quit(0)


## Force every enemy into an attack windup so the telegraphs are guaranteed
## on-screen for the showcase mode. Calls the archetype's own windup starter
## (reset the cooldown + ensure a hero target first).
func _force_windups() -> void:
	var enemies: Array = root.get_tree().get_nodes_in_group("enemy")
	for e: Node in enemies:
		if not is_instance_valid(e):
			continue
		if e.get("_attack_state") != 0:  # already winding up / charging
			continue
		e.set("_attack_cooldown", 0.0)


## Showcase the elemental ailments: paint each bot with a different element
## (re-applied each cycle so the overlays stay lit; a second ICE freezes).
func _apply_statuses() -> void:
	var enemies: Array = root.get_tree().get_nodes_in_group("enemy")
	var elems: Array = [0, 1, 2, 3, 4]  # fire, ice, lightning, shadow, arcane
	for i: int in enemies.size():
		var e: Node = enemies[i]
		if is_instance_valid(e) and e.has_method("apply_status"):
			e.apply_status(elems[i % elems.size()], false)


func _save_sheet(tiles: Array) -> void:
	if tiles.is_empty():
		printerr("combat_capture: no frames captured")
		return
	var sheet := Image.create(TILE_W * TILES_COLS, TILE_H * TILES_ROWS, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.07, 1.0))
	for i: int in tiles.size():
		var col: int = i % TILES_COLS
		var row: int = i / TILES_COLS
		var tile: Image = tiles[i]
		if tile.get_format() != Image.FORMAT_RGBA8:
			tile.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(
			tile, Rect2i(0, 0, TILE_W, TILE_H), Vector2i(col * TILE_W, row * TILE_H)
		)
	sheet.save_png(SHEET_PATH)
	print("combat_capture: saved ", ProjectSettings.globalize_path(SHEET_PATH))
