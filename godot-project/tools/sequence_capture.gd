# Drives scripted inputs on a combat scene and renders a 4x4 CONTACT SHEET of
# frames to user://seq_sheet.png, so motion / physics / aim / abilities are
# visible in ONE image (Claude reads that PNG to SEE the game in MOTION — the
# static screenshot.gd only ever shows an idle frame). Run with the GUI
# (non-headless) binary so the real renderer produces pixels:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/sequence_capture.gd -- <scene_res_path>
# Optional 2nd cmdline arg (after --) overrides the scene; defaults to the versus arena.
#
# The timeline: walk right (looking left) -> jump -> walk left (looking right)
# -> cast bolts at the floor -> meteor (Q) at the floor -> dash -> blink -> walk.
# Aim is driven by warping the mouse to a fraction of the window; casts also
# soft-assist toward enemies, so spells fly + impact regardless of aim precision.
extends SceneTree

const DEFAULT_SCENE: String = "res://scenes/combat/VersusArena.tscn"
const OUT_SHEET: String = "user://seq_sheet.png"
const COLS: int = 4
const ROWS: int = 4
const SHOTS: int = 16
const CELL: Vector2i = Vector2i(320, 180)
const STEP_FRAMES: int = 6  # process frames advanced between captures
const SETTLE_FRAMES: int = 18

## Every action this tool may press — released at the end so a re-run is clean.
const ALL_ACTIONS: Array[String] = [
	"move_left", "move_right", "jump", "dash", "cast", "blast", "blink", "nova", "fly",
]

var _scene_path: String = DEFAULT_SCENE
var _sheet: Image = null
var _hero: Node2D = null


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("res://"):
			_scene_path = arg
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		printerr("seq: could not load ", _scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	_sheet = Image.create(CELL.x * COLS, CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.04, 0.04, 0.06, 1.0))
	_run()


func _run() -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame
	_hero = _find_hero()
	for shot: int in SHOTS:
		_drive(shot)
		for _j: int in STEP_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		_grab(shot)
	_release_all()
	var err: int = _sheet.save_png(OUT_SHEET)
	if err == OK:
		print("seq: saved ", ProjectSettings.globalize_path(OUT_SHEET))
	else:
		printerr("seq: save failed err=", err)
	quit(0)


## Set the input + aim state for a given shot. Held actions (move_*, cast)
## persist until released; edge actions (jump/dash/blink/blast) fire once on the
## first frame after action_press, then get released so they can re-fire later.
func _drive(shot: int) -> void:
	match shot:
		0:
			Input.action_press("move_right")
			_aim(0.12, 0.42)   # look LEFT while running right (body/aim decouple)
		1:
			Input.action_press("jump")
		2:
			Input.action_release("jump")
		3:
			Input.action_release("move_right")
			Input.action_press("move_left")
			_aim(0.88, 0.42)   # look RIGHT while running left
		4:
			Input.action_release("move_left")
			_aim(0.66, 0.80)   # aim DOWN at the floor
			Input.action_press("cast")
		5, 6, 7:
			pass               # keep casting into the floor / enemies
		8:
			Input.action_release("cast")
			_aim(0.60, 0.86)   # meteor placed at the cursor (floor)
			Input.action_press("blast")
		9:
			Input.action_release("blast")
			_aim(0.90, 0.30)
			Input.action_press("dash")   # dash toward aim
		10:
			Input.action_release("dash")
		11:
			Input.action_press("blink")  # blink toward aim
		12:
			Input.action_release("blink")
			Input.action_press("move_right")
			_aim(0.15, 0.30)
		13, 14:
			pass
		15:
			Input.action_release("move_right")


## Aim by warping the OS cursor to a fraction of the window; get_global_mouse_position
## picks it up on the next poll. Fraction so it works whatever the window size is.
func _aim(fx: float, fy: float) -> void:
	var ws: Vector2i = DisplayServer.window_get_size()
	Input.warp_mouse(Vector2(ws) * Vector2(fx, fy))


## Grab the rendered viewport, downscale into this shot's grid cell.
func _grab(shot: int) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	# Full-res "money shots" of the blast detonation window (debris + crater +
	# no-sky-crack) so fine physics detail survives the contact-sheet downscale.
	if shot == 10 or shot == 11:
		img.save_png("user://seq_full_%02d.png" % shot)
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var col: int = shot % COLS
	var row: int = shot / COLS
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))


func _find_hero() -> Node2D:
	var heroes: Array = get_nodes_in_group("hero")
	if heroes.is_empty():
		return null
	return heroes[0] as Node2D


func _release_all() -> void:
	for action: String in ALL_ACTIONS:
		if Input.is_action_pressed(action):
			Input.action_release(action)
