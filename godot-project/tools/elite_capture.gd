# ELITE READ CAPTURE — can you tell an elite from an ordinary body BEFORE it hits
# you? That is the whole acceptance criterion for the affix system and no assertion
# can settle it, so this renders each elite NEXT TO the plain version of the same
# archetype and lets a human decide.
#
# Two images, because the question has two halves:
#   elite_read.png       each affix beside the plain version of the same archetype.
#   elite_in_a_wave.png  one elite hidden in a believable slice of a wave. This is
#                        the one that actually answers the question — a read that
#                        only works in a tidy side-by-side is not a read.
#
# GUI binary only (headless renders blank PNGs while reporting success):
#   python python-tools/run_capture.py elite
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"

## archetype id -> label. Chosen to span the roster's shapes: a fast weak backbone,
## a slow heavy, a kiter, a glass cannon.
const PAIRS: Array = [
	{"arch": 0, "name": "CHASER", "affix": "quickened"},
	{"arch": 1, "name": "BRUTE", "affix": "inked"},
	{"arch": 2, "name": "CASTER", "affix": "keen"},
	{"arch": 5, "name": "ASSASSIN", "affix": "volatile"},
	{"arch": 7, "name": "MAGE", "affix": "smudged"},
	{"arch": 3, "name": "CHARGER", "affix": "herald"},
]

## The arena wash the tower actually draws on (EnvTheme "underground"), so the read
## is judged against a real background rather than against a flattering one.
const WASH: Color = Color(0.16, 0.13, 0.20)
## The real fighter height (CharacterRig.height's own default). Not negotiable here:
## a read that only works on a scaled-up rig is not a read.
const RIG_H: float = 31.0

var _enc: Node = null


func _initialize() -> void:
	_run()


func _build(arch: int, affix: String, at: Vector2, height: float) -> Node:
	var data: Dictionary = {
		"boss": false, "arch": arch, "hp": 40, "spd": 95.0, "touch": 10,
		"tint": Color(0.9, 0.35, 0.3, 1), "tele": false, "x": at.x, "y": at.y,
	}
	if affix != "":
		data["elite"] = [affix]
	var e: Node = _enc.build_enemy_from_data(data)
	root.add_child(e)
	# Stills, not a sim: the bodies would otherwise fall straight out of frame.
	e.set_physics_process(false)
	var rig: Node = e.get_node_or_null(^"Rig")
	if rig != null:
		rig.set("height", height)
		rig.call("play", 0)
	return e


func _label(text: String, at: Vector2, col: Color, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04))
	l.add_theme_constant_override("outline_size", 4)
	root.add_child(l)


func _bg(size: Vector2) -> void:
	var bg := ColorRect.new()
	bg.color = WASH
	bg.size = size
	root.add_child(bg)


func _clear() -> void:
	for c: Node in root.get_children():
		if c == _enc:
			continue
		c.free()


func _shoot(path: String) -> void:
	for i: int in 70:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("elite_capture: saved ", ProjectSettings.globalize_path(path))


## ⚠ EVERYTHING HERE IS LAID OUT IN 640x360 LOGICAL UNITS, and that is not a
## simplification — it is the point. `project.godot` sets a 640x360 viewport with
## `stretch/mode="canvas_items"`, so the whole game is authored at phone resolution
## and upscaled to whatever window it is in. Laying the sheet out in those units and
## using the REAL 31px rig height means the capture is not a flattering diagram of the
## read; it IS the read, at the size a player gets it, blown up the same way a phone
## screen blows it up. The first cut of this file resized the window and placed bodies
## at 62px, which produced a handsome contact sheet that answered no question at all.
func _run() -> void:
	# ⚠ THE FIRST FRAME IS LOAD-BEARING. Building the board inside `_initialize`
	# before the tree has ticked once produced a picture with every LABEL in it and
	# not one BODY — the Controls drew, the rigs never did. One frame of settle first
	# and everything renders. It reports success either way, which is exactly the
	# failure mode `run_capture.py` exists to warn about.
	await process_frame
	_enc = load(ENCOUNTER_PATH).new()
	var view: Vector2 = root.get_visible_rect().size

	# ── 1 · every affix, next to the plain version of the same archetype ─────
	_bg(view)
	_label("ELITE vs ORDINARY  ·  same archetype, same hp", Vector2(6, 20),
		Color(0.86, 0.88, 0.94), 9)
	var step: float = view.x / float(PAIRS.size() + 1)
	var x: float = step
	for row: Dictionary in PAIRS:
		var arch: int = int(row["arch"])
		var affix: String = String(row["affix"])
		_build(arch, "", Vector2(x, 150.0), RIG_H)
		_build(arch, affix, Vector2(x, 300.0), RIG_H)
		_label(String(row["name"]), Vector2(x - 22.0, 156.0), Color(0.66, 0.68, 0.74), 7)
		x += step
	_label("ordinary", Vector2(4, 120.0), Color(0.55, 0.57, 0.63), 8)
	_label("elite", Vector2(4, 290.0), Color(0.85, 0.8, 0.6), 8)
	await _shoot("user://elite_read.png")

	# ── 2 · the question that actually matters: can you spot it in a wave? ───
	_clear()
	_bg(view)
	_label("A WAVE, ONE ELITE IN IT  ·  640x360, real rig height", Vector2(6, 20),
		Color(0.86, 0.88, 0.94), 9)
	_build(0, "", Vector2(90.0, 200.0), 31.0)
	_build(1, "", Vector2(175.0, 300.0), 31.0)
	_build(5, "", Vector2(255.0, 180.0), 31.0)
	_build(0, "quickened", Vector2(360.0, 260.0), 31.0)
	_build(2, "", Vector2(455.0, 190.0), 31.0)
	_build(0, "", Vector2(540.0, 300.0), 31.0)
	_build(3, "", Vector2(600.0, 210.0), 31.0)
	await _shoot("user://elite_in_a_wave.png")
	quit(0)
