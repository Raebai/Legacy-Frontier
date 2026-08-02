# Render THE FLOOR REDRAWING ITSELF at a boss phase break — all four artists.
# Also grabs each guardian's billing card (name + epithet) on the way past.
# MUST run with the GUI binary (dummy renderer draws black):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/boss_redraw_capture.gd
# Outputs: user://redraw_<artist>_card.png  and  user://redraw_<artist>_p2.png
#
# WHAT TO LOOK FOR, because no assertion can settle any of it:
#   * the WIPE — a band of blank page travelling across the room ahead of the new
#     lines. Does it read as "erased and redrawn", or just as a flash?
#   * the HAND — the scribble scrawls, the cartographer rules and ticks, the
#     illuminator gilds, the guardian hatches. Are they four different pages at a
#     glance, or four colours of the same page?
#   * READABILITY — the guardian is still standing on the floor and still has to be
#     fought through this. If the strokes bury the boss silhouette or the hero, the
#     stroke budget in Boss.PageRedraw is too high, not too low.
#
# All boss access is duck-typed (.call/.get) — naming `Boss` here would drag
# `Enemy.gd` and its bare `Sfx` autoload into this script's compile chain, which
# under `--script` fails the WHOLE chain and reports as a missing `_ready`.
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const ARTISTS: Array[String] = ["guardian", "scribble", "cartographer", "illuminator"]

## Frames after the phase call at which the page is caught. The redraw runs ~1.05 s
## and the wipe leads the strokes, so a shot near a third of the way in has both the
## band and the first lines on screen — which is the frame that shows whether the
## beat reads at all.
const MID_REDRAW_FRAMES: int = 18
## Frames after spawn for the billing card: past the fade-in, inside the hold.
const CARD_FRAMES: int = 40

var _arena: Node = null


func _initialize() -> void:
	_run()


func _settle(n: int) -> void:
	for i: int in n:
		await process_frame


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("boss_redraw_capture: saved ", ProjectSettings.globalize_path(path))


func _drop_existing_bosses() -> void:
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("current_phase"):
			e.queue_free()


func _spawn(bid: String) -> Node:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var b: Node = enc.build_enemy_from_data({
		"boss": true, "bid": bid, "hp": 900, "spd": 60.0, "touch": 24,
		"bscale": 1.0, "x": 760.0, "y": 300.0,
	})
	enc.free()
	_arena.add_child(b)
	return b


## Stand the hero beside the guardian so the shot carries scale — the redraw has to
## be legible with a body in it, not on an empty floor.
func _frame_with_hero(boss: Node) -> void:
	if boss == null or not (boss is Node2D):
		return
	for h in root.get_tree().get_nodes_in_group("hero"):
		if h is Node2D:
			(h as Node2D).global_position = (boss as Node2D).global_position + Vector2(170.0, 30.0)
			# Four guardians in one arena will kill a stationary hero long before the
			# fourth shot, and a GAME OVER banner across the frame is not a picture of
			# a redraw. Top it up each time; this is a camera rig, not a fight.
			var mx: Variant = h.get("max_hp")
			if mx != null:
				h.set("hp", mx)
			break


func _run() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("boss_redraw_capture: no GameState autoload (use the GUI binary, not --headless)")
		quit(1)
		return
	gs.active_tower = gs.build_default_tower()
	gs.set("_run_active", true)
	gs.set("_floor", 5)
	gs.set("mode", 1)   # Mode.RUN
	_arena = load("res://scenes/combat/Arena.tscn").instantiate()
	root.add_child(_arena)
	await _settle(70)

	for bid: String in ARTISTS:
		_drop_existing_bosses()
		await _settle(4)
		var b: Node = _spawn(bid)
		_frame_with_hero(b)
		# THE BILLING. Name card + epithet, mid-hold.
		await _settle(CARD_FRAMES)
		await _shoot("user://redraw_%s_card.png" % bid)
		if not is_instance_valid(b):
			continue
		# THE PAGE. Phase two: the hand takes the floor back.
		b.call("_apply_phase", 2, true)
		_frame_with_hero(b)
		await _settle(MID_REDRAW_FRAMES)
		await _shoot("user://redraw_%s_p2.png" % bid)
		await _settle(60)

	quit(0)
