# LOOK AT WHAT THE CIRCLE SAYS THE SPELL IS.
#
# `sigil_matrix_capture.gd` sheets the first two signature axes — the element band
# and the tier ladder. This is the third: `MagicCircle.Motif`, the figure in the
# inner court that answers "which spell", added because the maker asked for the
# circle to be "relevant to the spell... meteor should be red and look slightly
# different — and do this for all the spells".
#
#   sigil_motifs.png      5x3 — every motif in the vocabulary at ULT, fully charged,
#                         each in the element it most often appears with. THE
#                         QUESTION: can you tell these thirteen apart, and does each
#                         one suggest what the spell does before you are told?
#   sigil_motifs_low.png  5x3 — the same grid at graphics_quality = LOW, which is the
#                         only phone preview there is. THE QUESTION: does the figure
#                         survive when the decoration is halved?
#   sigil_motifs_tiny.png 5x3 — the same grid rendered at the size a sigil actually
#                         occupies at 640x360 with 31 px fighters, then blown back up
#                         with NEAREST so you are judging the real pixels rather than
#                         a smooth enlargement. THE QUESTION THAT MATTERS MOST: does
#                         any of this read on a phone, or is it jewellery?
#   sigil_spells.png      3x2 — six REAL spectacles opened through `SpellSigil` rather
#                         than by hand, so the whole path is exercised: the table
#                         lookup, the stamp read, the element, the tier. THE
#                         QUESTION: does meteor look like meteor in the actual game
#                         code path, not just in a harness?
#
# GUI binary (must render — captures are black under --headless):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/sigil_motif_capture.gd
# PNGs land in %APPDATA%/Godot/app_userdata/Legacy Frontier/.
extends SceneTree

const CIRCLE: String = "res://scripts/combat/MagicCircle.gd"
const CELL: Vector2i = Vector2i(300, 240)
const RADIUS: float = 92.0
## The mobile framebuffer sheet 3 simulates. The game renders into 640x360 on a
## phone; sheet 3 downsizes the desktop grab to exactly that and then crops 1:1, so
## it shows real phone pixels rather than a resampled approximation of them.
const PHONE: Vector2i = Vector2i(640, 360)
## Sheet 3 keeps the sigil at its NORMAL world radius. The thing that shrinks on a
## phone is the frame, not the spell — modelling it the other way round is what made
## the first version of this sheet a false negative.
const TINY_UPSCALE: int = 5

## Every motif, paired with the element it most often ships alongside — so the sheet
## shows the combinations that actually occur rather than thirteen identical violets.
const ROWS: Array[Dictionary] = [
	{"m": MagicCircle.Motif.DESCENT, "e": Elements.Element.FIRE, "n": "DESCENT · meteor"},
	{"m": MagicCircle.Motif.LANCE, "e": Elements.Element.LIGHTNING, "n": "LANCE · beam"},
	{"m": MagicCircle.Motif.BARRIER, "e": Elements.Element.ICE, "n": "BARRIER · wall"},
	{"m": MagicCircle.Motif.ERUPTION, "e": Elements.Element.EARTH, "n": "ERUPTION · pillar"},
	{"m": MagicCircle.Motif.ORBIT, "e": Elements.Element.ARCANE, "n": "ORBIT · missiles"},
	{"m": MagicCircle.Motif.PULSE, "e": Elements.Element.ARCANE, "n": "PULSE · nova"},
	{"m": MagicCircle.Motif.SNARE, "e": Elements.Element.SHADOW, "n": "SNARE · root"},
	{"m": MagicCircle.Motif.BLADE, "e": Elements.Element.SHADOW, "n": "BLADE · flurry"},
	{"m": MagicCircle.Motif.WARD, "e": Elements.Element.HOLY, "n": "WARD · aegis"},
	{"m": MagicCircle.Motif.VOID, "e": Elements.Element.SHADOW, "n": "VOID · collapse"},
	{"m": MagicCircle.Motif.SPIRAL, "e": Elements.Element.WIND, "n": "SPIRAL · gravity"},
	{"m": MagicCircle.Motif.SUMMON, "e": Elements.Element.ARCANE, "n": "SUMMON · mirror"},
	{"m": MagicCircle.Motif.NONE, "e": Elements.Element.FIRE, "n": "NONE · (the before)"},
]

## Real spectacles, opened the way the game opens them. Script path -> label.
## Chosen to be the six the maker is most likely to throw in Free Play.
const SPELLS: Array[Dictionary] = [
	{"s": "res://scripts/combat/MeteorSigil.gd", "e": Elements.Element.FIRE,
		"t": SpellTier.Tier.ULT, "n": "Meteor Sigil (FIRE / ULT)"},
	{"s": "res://scripts/combat/BeamSpell.gd", "e": Elements.Element.LIGHTNING,
		"t": SpellTier.Tier.ULT, "n": "Tempest beam (LIGHTNING / ULT)"},
	{"s": "res://scripts/combat/IceWall.gd", "e": Elements.Element.ICE,
		"t": SpellTier.Tier.HEAVY, "n": "Ice Wall (ICE / HEAVY)"},
	{"s": "res://scripts/combat/RuneOrbs.gd", "e": Elements.Element.ARCANE,
		"t": SpellTier.Tier.HEAVY, "n": "Arcane Missiles (ARCANE / HEAVY)"},
	{"s": "res://scripts/combat/EnergyNova.gd", "e": Elements.Element.ARCANE,
		"t": SpellTier.Tier.ULT, "n": "Energy Nova (ARCANE / ULT)"},
	{"s": "res://scripts/combat/ShadowRoot.gd", "e": Elements.Element.SHADOW,
		"t": SpellTier.Tier.HEAVY, "n": "Shadow Root (SHADOW / HEAVY)"},
]

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
	bg.color = Color(0.09, 0.10, 0.14)
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
	await _motif_sheet(RADIUS, false, 1, "user://sigil_motifs.png")
	await _motif_sheet(RADIUS, true, 1, "user://sigil_motifs_low.png")
	await _motif_sheet(RADIUS, false, TINY_UPSCALE, "user://sigil_motifs_tiny.png")
	await _spell_sheet()
	quit(0)


# ----------------------------------------------------------- sheets 1-3: the grid
## `upscale` > 1 renders small and blows the grab back up with NEAREST, which is the
## only honest way to preview a phone frame on a desktop monitor — a bilinear resize
## invents detail that the phone will never have.
func _motif_sheet(r: float, low: bool, upscale: int, path: String) -> void:
	_force_quality(low)
	var sheet := _blank(5, 3)
	for i: int in ROWS.size():
		var row: Dictionary = ROWS[i]
		var c: Node2D = _open(Elements.color(int(row["e"])), r)
		c.set_signature(int(row["e"]), SpellTier.Tier.ULT)
		c.set_motif(int(row["m"]))
		await _wait(30)
		c.snap(0.0)   # force the gather to full without leaving a flare over the figure
		await _wait(2)
		_label("%s%s" % [row["n"], "  [LOW]" if low else ""])
		await _wait(2)
		_grab(sheet, i, 5, upscale)
		c.queue_free()
		await _wait(2)
	_force_quality(false)
	_save(sheet, path)


# -------------------------------------------------- sheet 4: through the real path
## Opens each spectacle through `SpellSigil.open` exactly as the spell does, so a
## broken table key or a lost stamp shows up here as a circle with no figure in it.
## The spectacle is never activated — only stamped and asked for its sigil — because
## what is being looked at is the TELEGRAPH, which is what exists before the spell.
func _spell_sheet() -> void:
	var sheet := _blank(3, 2)
	for i: int in SPELLS.size():
		var row: Dictionary = SPELLS[i]
		var script: GDScript = load(String(row["s"])) as GDScript
		var spec: Object = script.new()
		if spec is not Node:
			continue
		_world.add_child(spec as Node)
		(spec as Node).set(&"element_id", int(row["e"]))
		(spec as Node).set(&"spell_tier", int(row["t"]))
		var circle: MagicCircle = SpellSigil.open(
			spec as Node, Vector2.ZERO, Elements.color(int(row["e"])), 0.9)
		# ⚠ A BARE SPECTACLE MAY FREE ITSELF. Several of these `queue_free()` from
		# `_process` when they have nothing to do (RuneOrbs with no live orbs is the
		# reliable one). The sigil is a CHILD, so it goes with the parent — every
		# handle here has to be re-validated after any await or the sheet dies on a
		# freed-object cast.
		_label(String(row["n"]))
		await _wait(24)
		if is_instance_valid(circle):
			circle.snap(0.0)
		await _wait(2)
		_grab(sheet, i, 3, 1)
		if is_instance_valid(spec):
			(spec as Node).queue_free()
		await _wait(2)
	_save(sheet, "user://sigil_spells.png")


## See the note in sigil_matrix_capture.gd: the quality dial lives on the Tuning
## autoload, which a `--script` tool may not have.
func _force_quality(low: bool) -> void:
	var t: Node = root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		if low:
			push_warning("sigil_motif_capture: no Tuning autoload — LOW cells will render HIGH")
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
	l.add_theme_font_size_override(&"font_size", 20)
	l.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.85))
	l.position = Vector2(14, 8)
	_label_layer.add_child(l)


func _wait(frames: int) -> void:
	for _i: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab(sheet: Image, cell: int, cols: int, upscale: int) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if upscale > 1:
		# ⚠ THE PHONE PREVIEW MUST NOT BE A SHRINK. The first version of this resized
		# the grab down by 5x and back up, which produced a 7 px blob and "proved"
		# every motif illegible. That was the harness lying: it modelled a sigil five
		# times smaller than the phone will ever draw.
		#
		# The honest simulation is the FRAMEBUFFER, not the object. Resize the grab to
		# a real 640x360 phone frame — which is exactly what the game renders into —
		# and then CROP a cell-sized window out of it at 1:1. No second resample, so
		# what you are looking at is literally the pixels the phone would light up.
		img.resize(PHONE.x, PHONE.y, Image.INTERPOLATE_BILINEAR)
		var origin := Vector2i((PHONE.x - CELL.x) / 2, (PHONE.y - CELL.y) / 2)
		var win := Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
		win.blit_rect(img, Rect2i(origin, CELL), Vector2i.ZERO)
		img = win
	else:
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL),
		Vector2i((cell % cols) * CELL.x, (cell / cols) * CELL.y))


func _save(sheet: Image, path: String) -> void:
	var err: int = sheet.save_png(path)
	if err == OK:
		print("sigil motif capture: saved ", ProjectSettings.globalize_path(path))
	else:
		printerr("sigil motif capture: save failed err=", err, " path=", path)
