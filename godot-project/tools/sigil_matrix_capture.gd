# LOOK AT THE SUMMONING CIRCLES. Renders the MagicCircle signature vocabulary as
# three contact sheets so the element band and the tier ladder can be judged by eye
# rather than argued about:
#
#   sigil_elements.png  4x2 — all eight element glyph bands at ULT, fully charged.
#                       The question this answers: can you name the element from the
#                       RIM SHAPE with the colour ignored?
#   sigil_tiers.png     3x2 — QUICK / HEAVY / ULT, each mid-charge and at the snap.
#                       The question: is the tier countable at a glance?
#   sigil_quality.png   2x2 — the same ULT sigil at HIGH and LOW graphics quality,
#                       face-on and edge-on. The question: does the phone picture
#                       stay readable when the decoration is stripped?
#
# GUI binary (must render — captures are black under --headless):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/sigil_matrix_capture.gd
# PNGs land in %APPDATA%/Godot/app_userdata/Legacy Frontier/.
extends SceneTree

const CIRCLE: String = "res://scripts/combat/MagicCircle.gd"
const CELL: Vector2i = Vector2i(430, 300)
const RADIUS: float = 108.0

var _world: Node2D = null
var _cam: Camera2D = null
var _label_layer: CanvasLayer = null


func _initialize() -> void:
	Engine.max_fps = 60
	_world = Node2D.new()
	root.add_child(_world)
	var bg := ColorRect.new()
	bg.position = Vector2(-2000, -2000)
	bg.size = Vector2(4000, 4000)
	bg.color = Color(0.10, 0.11, 0.16)
	bg.z_index = -10
	_world.add_child(bg)
	_cam = Camera2D.new()
	_world.add_child(_cam)
	_cam.make_current()
	_label_layer = CanvasLayer.new()
	_label_layer.layer = 20
	root.add_child(_label_layer)
	_run()


func _run() -> void:
	await _elements_sheet()
	await _tiers_sheet()
	await _quality_sheet()
	quit(0)


# ---------------------------------------------------------------- sheet 1: elements
func _elements_sheet() -> void:
	var sheet := _blank(4, 2)
	for e: int in 8:
		var c: Node2D = _open(Elements.color(e), RADIUS)
		c.set_signature(e, SpellTier.Tier.ULT)
		# Charged to full so every glyph in the band is LIT — this sheet is about
		# whether the shapes are distinguishable, not about the fill animation.
		await _wait(34)
		c.snap(0.0)   # force _charge to 1 without leaving a flare over the shapes
		await _wait(2)
		_label("%s — ULT" % Elements.display_name(e))
		await _wait(2)
		_grab(sheet, e, 4)
		c.queue_free()
		await _wait(2)
	_save(sheet, "user://sigil_elements.png")


# ------------------------------------------------------------------ sheet 2: tiers
func _tiers_sheet() -> void:
	var sheet := _blank(3, 2)
	var tiers: Array[int] = [SpellTier.Tier.QUICK, SpellTier.Tier.HEAVY, SpellTier.Tier.ULT]
	for i: int in 3:
		# Row 0 = mid-gather (the telegraph the opponent reads).
		var c: Node2D = _open(Elements.color(Elements.Element.ARCANE), RADIUS)
		c.set_signature(Elements.Element.ARCANE, tiers[i])
		await _wait(16)
		_label("%s — gathering" % SpellTier.display_name(tiers[i]))
		await _wait(2)
		_grab(sheet, i, 3)
		# Row 1 = the release snap, two frames in, while the flare is still hot.
		c.snap(1.0)
		await _wait(3)
		_label("%s — RELEASE" % SpellTier.display_name(tiers[i]))
		await _wait(2)
		_grab(sheet, 3 + i, 3)
		c.queue_free()
		await _wait(2)
	_save(sheet, "user://sigil_tiers.png")


# ---------------------------------------------------------------- sheet 3: quality
func _quality_sheet() -> void:
	var sheet := _blank(2, 2)
	var cell: int = 0
	for low: bool in [false, true]:
		_force_quality(low)
		for edge: bool in [false, true]:
			var c: Node2D = _open(Elements.color(Elements.Element.FIRE), RADIUS)
			c.set_signature(Elements.Element.FIRE, SpellTier.Tier.ULT)
			if edge:
				c.set_orientation(true, Vector2.RIGHT, 0.16)
			await _wait(30)
			c.snap(0.0)
			await _wait(2)
			_label("%s — %s" % ["LOW" if low else "HIGH", "edge-on" if edge else "face-on"])
			await _wait(2)
			_grab(sheet, cell, 2)
			cell += 1
			c.queue_free()
			await _wait(2)
	_force_quality(false)
	_save(sheet, "user://sigil_quality.png")


## The quality dial reads the Tuning autoload, which exists under `--script` only if
## the project registers it; when it does not, HIGH is what everything sees. Writing
## the config field directly is the only way to preview the LOW picture from a tool.
func _force_quality(low: bool) -> void:
	var t: Node = root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		if low:
			push_warning("sigil_matrix_capture: no Tuning autoload — LOW cells will render HIGH")
		return
	t.cfg.set(&"graphics_quality", TuningConfig.Quality.LOW if low else TuningConfig.Quality.HIGH)


# ------------------------------------------------------------------------ plumbing
func _open(col: Color, r: float) -> Node2D:
	var c: Node2D = (load(CIRCLE) as GDScript).new()
	_world.add_child(c)
	c.global_position = Vector2.ZERO
	c.appear(col, r, 0.28)
	return c


func _blank(cols: int, rows: int) -> Image:
	var img := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.03, 0.03, 0.05, 1.0))
	return img


func _label(text: String) -> void:
	for ch: Node in _label_layer.get_children():
		ch.queue_free()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 22)
	l.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.85))
	l.position = Vector2(16, 10)
	_label_layer.add_child(l)


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab(sheet: Image, cell: int, cols: int) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL),
		Vector2i((cell % cols) * CELL.x, (cell / cols) * CELL.y))


func _save(sheet: Image, path: String) -> void:
	var err: int = sheet.save_png(path)
	if err == OK:
		print("sigil capture: saved ", ProjectSettings.globalize_path(path))
	else:
		printerr("sigil capture: save failed err=", err, " path=", path)
