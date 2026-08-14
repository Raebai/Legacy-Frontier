# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/sky_capture.gd
# LOOK AT THE SKY. The three floors that open onto one, each at two points in its
# cycle so the MOVEMENT is visible in a still -> user://sky_sheet.png (3x2) plus
# full-resolution singles.
#
# ⚠ IT BUILDS A REAL `FloorDecor` UNDERNEATH, and that is not set dressing. `SkyVista`
# is an OPENING CUT INTO THAT WALL — it shares the DECOR rung and relies on being
# added second so it lands on top. Photographed on a bare background it would look
# fine and prove nothing, because the one thing that can go wrong is the two nodes'
# relationship: a sky drawn first is buried under an opaque rect and is
# indistinguishable from a sky that never drew.
#
# ⚠ TIME IS SET, NOT WAITED FOR. The sun takes `SkyVista.SUN_CYCLE` = 220 s to cross,
# so photographing "later" honestly would mean sitting through minutes per cell. The
# tool writes `_t` directly instead. That is legitimate here precisely because every
# motion in the file is a pure function of elapsed time and nothing integrates — if a
# frame at t=90 needed the frames before it, this shortcut would be a lie.
#
# ⚠ NEEDS THE GUI BINARY. Under --headless Godot uses the DUMMY renderer: this runs,
# reports success, and writes empty PNGs.
extends SceneTree

const OUT: String = "user://sky_sheet.png"
const CELL: Vector2i = Vector2i(640, 360)
const COLS: int = 2
const ROWS: int = 3
## Room the sky is opened in. `FloorGen.MAX_ROOM` — the biggest a floor gets, which
## is also the hardest case for a full-width band.
const ROOM: Vector2 = Vector2(1220.0, 620.0)
## The two moments each floor is photographed at, in seconds of sky time.
const MOMENTS: Array[float] = [6.0, 96.0]

const GAMESTATE_PATH: String = "res://scripts/GameState.gd"
const SKY_PATH: String = "res://scripts/combat/SkyVista.gd"
const DECOR_PATH: String = "res://scripts/tower/FloorDecor.gd"

## The floors that open onto a sky, by floor number.
const SKY_FLOORS: Array[int] = [2, 3, 10]

var _sheet: Image = null
var _decor: Node = null
var _sky: Node = null
var _room: ColorRect = null
var _label: Label = null
var _cam: Camera2D = null


func _initialize() -> void:
	Engine.max_fps = 60
	var world := Node2D.new()
	root.add_child(world)

	_room = ColorRect.new()
	_room.size = ROOM
	_room.z_index = -10
	world.add_child(_room)

	# The wall FIRST, then the sky — the exact order `Arena._apply_theme` uses, and
	# the thing this capture exists to check.
	_decor = (load(DECOR_PATH) as GDScript).new()
	world.add_child(_decor)
	_sky = (load(SKY_PATH) as GDScript).new()
	world.add_child(_sky)

	_cam = Camera2D.new()
	_cam.position = ROOM * 0.5
	world.add_child(_cam)
	_cam.zoom = Vector2.ONE * (1366.0 / ROOM.x)

	var layer := CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.94))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_label)

	_sheet = Image.create(CELL.x * COLS, CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.03, 0.03, 0.05, 1.0))
	_run()


func _run() -> void:
	# ⚠ `make_current` AFTER A FRAME, NOT DEFERRED FROM `_initialize`. Deferred, it
	# did not take for the first grabs: the eclipse single came back framed on a
	# different transform from the sheet cell of the same moment, which is how this
	# was noticed. One frame in the tree, then claim the camera.
	await _wait(2)
	if _cam != null:
		_cam.make_current()
	var gs: GDScript = load(GAMESTATE_PATH) as GDScript
	if gs == null:
		printerr("sky_capture: could not load GameState")
		quit(1)
		return
	var cell: int = 0
	for floor_no: int in SKY_FLOORS:
		var theme: Resource = gs.floor_env(floor_no) as Resource
		if theme == null:
			continue
		var wash: Color = theme.lit_wash()
		_room.color = Color(wash.r * 1.4, wash.g * 1.4, wash.b * 1.4, 1.0)
		_decor.call("build", ROOM, wash, theme.accent(), String(theme.name))
		_sky.call("build", ROOM, wash, theme.accent(), int(theme.sky))
		for moment: float in MOMENTS:
			_sky.set("_t", moment)
			_sky.call("queue_redraw")
			_label.text = "%d  %s      t = %.0fs" % [floor_no, String(theme.name), moment]
			await _wait(4)
			_grab_full(floor_no, String(theme.name), moment)
			_grab(cell)
			cell += 1
		print("  %s  sky=%d" % [String(theme.name), int(theme.sky)])
	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("sky_sheet: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("sky_sheet: save failed err=", err)
	quit(0)


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw


## The full-res single is the one that settles it — the corona's rays are 1-3 px wide
## and the star field is sub-pixel once a 1366-wide viewport is squeezed into a
## 640-wide cell.
func _grab_full(floor_no: int, biome: String, moment: float) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	var slug: String = biome.to_lower().replace(" ", "_")
	var path: String = "user://sky_%02d_%s_t%03d.png" % [floor_no, slug, int(moment)]
	if img.save_png(path) == OK:
		print("  full  ", ProjectSettings.globalize_path(path))


func _grab(cell: int) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL),
		Vector2i((cell % COLS) * CELL.x, (cell / COLS) * CELL.y))
