# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/weather_capture.gd
# LOOK AT THE FLOOR'S AIR. One cell per biome, all ten, each showing that floor's
# wash + vignette + weather over a stand-in room -> user://weather_sheet.png (5x2).
#
# ⚠ THE TWO BLUE BARS IN EVERY CELL ARE THE POINT, NOT SET DRESSING. Weather is drawn
# IN FRONT of the fighters, and the argument that cut the wash mote field from 40 to
# 22 was exactly that it "was 40 moving objects competing with the ones you have to
# react to". A weather sheet photographed over an EMPTY room cannot answer that
# question — it would look beautiful and tell you nothing. The bars stand in for the
# two fighters at roughly rig scale, so the only question this sheet exists to settle
# is askable: can you still read the bodies through the air?
#
# ⚠ NEEDS THE GUI BINARY. Under --headless Godot uses the DUMMY renderer: this runs,
# reports success, and writes an empty PNG. Use python-tools/run_capture.py, which
# refuses to be talked out of the GUI binary.
extends SceneTree

const OUT: String = "user://weather_sheet.png"
const CELL: Vector2i = Vector2i(480, 270)
const COLS: int = 5
const ROWS: int = 2
## Real frames to let a field fill before photographing it. `_begin_warmup` runs the
## emitter at 6x for MOTE_WARMUP_REAL (1.5 s) and then hands it back to real time, so
## anything less than ~90 frames photographs a field that is still filling and makes
## every biome look sparser than it ships.
const WARM_FRAMES: int = 96

const GAMESTATE_PATH: String = "res://scripts/GameState.gd"
const ATMOSPHERE_PATH: String = "res://scripts/combat/Atmosphere.gd"

var _sheet: Image = null
var _atmo: Node = null
var _room: ColorRect = null
var _label: Label = null


func _initialize() -> void:
	Engine.max_fps = 60
	var world := Node2D.new()
	root.add_child(world)

	# A stand-in room: floor slab + two ledges, so the air has something to fall past.
	_room = ColorRect.new()
	_room.position = Vector2(0, 0)
	_room.size = Vector2(640, 360)
	_room.z_index = -10
	world.add_child(_room)
	for r: Rect2 in [Rect2(0, 300, 640, 60), Rect2(90, 232, 150, 12),
			Rect2(400, 214, 160, 12)]:
		var led := ColorRect.new()
		led.position = r.position
		led.size = r.size
		led.color = Color(0.10, 0.10, 0.12, 1.0)
		led.z_index = -6
		world.add_child(led)

	# THE FIGHTERS. Roughly rig-height (31 px) at the framing this sheet uses, in the
	# hero's own blue, standing on the slab. If the weather makes these hard to pick
	# out, the weather is wrong however pretty the cell looks.
	for x: float in [232.0, 392.0]:
		var body := ColorRect.new()
		body.position = Vector2(x, 268.0)
		body.size = Vector2(14, 32)
		body.color = Color(0.40, 0.70, 1.0, 1.0)
		body.z_index = 0
		world.add_child(body)

	var cam := Camera2D.new()
	cam.position = Vector2(320, 180)
	world.add_child(cam)
	cam.make_current()
	# Fill the frame with the 640x360 stand-in room. The first sheet left a black band
	# below and beside it, which wastes the cell and — worse — photographs the weather
	# over emptiness instead of over the room it has to read against.
	# ⚠ HARDCODED, because `root.get_visible_rect()` inside `_initialize` returns the
	# BASE 640x360 rather than the window's 1366x768 — the viewport has not been sized
	# yet at that point. Deriving it there yielded zoom 1.0 and left the band in place.
	cam.zoom = Vector2.ONE * (1366.0 / 640.0)

	var name_layer := CanvasLayer.new()
	name_layer.layer = 60  # above the weather (2), below nothing that matters here
	root.add_child(name_layer)
	_label = Label.new()
	_label.position = Vector2(10, 6)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	name_layer.add_child(_label)

	_atmo = (load(ATMOSPHERE_PATH) as GDScript).new()
	root.add_child(_atmo)

	_sheet = Image.create(CELL.x * COLS, CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.03, 0.03, 0.05, 1.0))
	_run()


func _run() -> void:
	var gs: GDScript = load(GAMESTATE_PATH) as GDScript
	if gs == null:
		printerr("weather_capture: could not load GameState")
		quit(1)
		return
	for i: int in range(COLS * ROWS):
		var theme: Resource = gs.floor_env(i + 1) as Resource
		if theme == null:
			continue
		var wash: Color = theme.lit_wash()
		_room.color = Color(wash.r * 1.4, wash.g * 1.4, wash.b * 1.4, 1.0)
		_label.text = "%d  %s" % [i + 1, String(theme.name)]
		# The real per-floor order: wash first (it frees every child), weather second.
		_atmo.call("build_wash", wash, theme.accent())
		_atmo.call("build_weather", int(theme.weather), theme.accent())
		await _wait(WARM_FRAMES)
		_grab_full(i, String(theme.name))
		_grab(i)
		print("  cell %d  %s  weather=%d" % [i, String(theme.name), int(theme.weather)])
	var err: int = _sheet.save_png(OUT)
	if err == OK:
		print("weather_sheet: saved ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("weather_sheet: save failed err=", err)
	quit(0)


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw


## ⚠ THE FULL-RES SINGLE IS THE ONE THAT SETTLES IT, NOT THE SHEET. A snowflake is
## ~4 px and an ember ~3 px; the contact sheet downsamples a 1366-wide viewport into
## a 480-wide cell, so a 3 px particle arrives as one pixel and EVERY field looks
## thinner than it ships. The sheet answers "are the ten floors different from each
## other". Only these answer "can you see it".
func _grab_full(cell: int, biome: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	var slug: String = biome.to_lower().replace(" ", "_")
	var path: String = "user://weather_%02d_%s.png" % [cell + 1, slug]
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
