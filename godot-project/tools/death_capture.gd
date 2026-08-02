# LOOK AT THE DEATH. Tests cannot judge "small but cute" — the maker's actual words
# were *"where is the ragdoll when they die — maybe there should be some cool death
# animation, small but cute"* — so this renders it and you look.
#
# ⚠ MUST run with the GUI (non-headless) binary. `--headless` saves BLACK PNGs while
# reporting success, which is the single most expensive lie in this tool directory:
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/death_capture.gd
# Or: python python-tools/run_capture.py death_capture
#
# TWO SHEETS, because there are two different questions:
#
#   user://death_beat.png     THE ANIMATION ITSELF, in isolation and enlarged.
#                             Top row  = `DeathSmudge` — the fold into a heap and the
#                             RUB-OUT, which is what every ENEMY now leaves behind
#                             (they `queue_free()` on the frame they die, so there is
#                             no body left to ragdoll — see the header of DeathSmudge).
#                             Bottom row = `CharacterRig.collapse()` — the existing
#                             flop/limp machinery held at full ragdoll, which is what a
#                             body that STAYS does: a downed hero, a bot-match loser.
#                             Read left to right; a single frame proves nothing.
#
#   user://death_ko_NN.png    THE REAL THING. A real `BotMatch` played to a real KO at
#                             1920x1080, photographed across the frozen result beat.
#                             This is the frame the maker complained about: before this
#                             work the loser stood BOLT UPRIGHT at full health under
#                             the win card, and both fighters rendered RED because a
#                             hit-flash cannot expire on a paused tree. Both answers
#                             are in this sheet: is the loser on the floor, and is the
#                             left fighter YELLOW and the right one BLUE.
#
# The two sheets are rendered by two separate runs of this script (`--pass=beat` /
# `--pass=ko`, default: both, beat first) because the KO pass has to boot the real
# game scene and cannot share a viewport with a diagnostic strip.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const SMUDGE_PATH: String = "res://scripts/combat/DeathSmudge.gd"
const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"

# --- sheet 1: the isolated beat ---
const BEAT_W: int = 1120
const BEAT_H: int = 600
const FIG_H: float = 92.0          # ~3x the game rig, purely so the render is legible
const CELLS: int = 6
const CELL_X0: float = 110.0
const CELL_DX: float = 168.0
const SMUDGE_ROW_Y: float = 190.0
const COLLAPSE_ROW_Y: float = 400.0
## Real milliseconds after spawn at which each smudge cell is frozen. `DeathSmudge`
## is clocked in REAL time (it has to survive a paused tree), so the strip is built by
## spawning six of them staggered in real time rather than by stepping one.
const BEAT_MS: Array[int] = [0, 80, 160, 250, 350, 470]
## Physics steps after `collapse()` at which each collapse cell is sampled.
const COLLAPSE_STEPS: Array[int] = [0, 5, 11, 20, 34, 60]

# --- sheet 2: the real KO ---
const KO_W: int = 1920
const KO_H: int = 1080
## Real seconds after the decisive frame at which the frozen stage is photographed.
## `BotMatch.FREEZE_BEAT` is 0.55 (the card slams in) and `RESULT_HOLD` is 4.2.
const KO_SHOTS: Array[float] = [0.05, 0.20, 0.40, 0.75, 1.60]
## Hard wall-clock cap on how long we will wait for two bots to finish each other off.
const KO_WAIT_LIMIT: float = 240.0
## Side of the square blown up 4x around the loser. See `_crop_on_loser`.
const CROP: int = 240

var _do_beat: bool = true
var _do_ko: bool = true
## Everything the beat pass parents to `root`, so the KO pass can tear down exactly
## that and nothing else. See `_capture_ko`.
var _beat_nodes: Array[Node] = []


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pass="):
			var which: String = a.substr(7)
			_do_beat = which == "beat" or which == "both"
			_do_ko = which == "ko" or which == "both"
	_run()


func _run() -> void:
	if _do_beat:
		await _capture_beat()
	if _do_ko:
		await _capture_ko()
	print("death_capture: done")
	quit(0)


# ══════════════════════════════════════════════════ SHEET 1 — THE BEAT, ENLARGED

func _capture_beat() -> void:
	# The project stretches a 640x360 BASE viewport up to the window; a diagnostic
	# strip wants 1:1 pixels instead. Same reason `rig_ragdoll_capture` does this.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(BEAT_W, BEAT_H)
	root.content_scale_size = Vector2i(BEAT_W, BEAT_H)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.16)
	bg.size = Vector2(BEAT_W, BEAT_H)
	_own(bg)
	_label("DeathSmudge — every ENEMY (the body is freed, so it folds + is RUBBED OUT)",
		Vector2(12, 8), Color(0.72, 0.80, 0.95))
	_label("CharacterRig.collapse() — a body that STAYS (downed hero / bot-match loser)",
		Vector2(12, 250), Color(0.72, 0.95, 0.80))
	for i: int in CELLS:
		_label("+%d ms" % BEAT_MS[i], Vector2(CELL_X0 + CELL_DX * float(i) - 26.0, 30.0),
			Color(0.5, 0.55, 0.68))
		_label("+%d f" % COLLAPSE_STEPS[i],
			Vector2(CELL_X0 + CELL_DX * float(i) - 26.0, 272.0), Color(0.5, 0.55, 0.68))
		_floor_line(SMUDGE_ROW_Y + FIG_H * 0.5, CELL_X0 + CELL_DX * float(i))
		_floor_line(COLLAPSE_ROW_Y + FIG_H * 0.5, CELL_X0 + CELL_DX * float(i))
	# ⚠ A REAL COLLIDER UNDER THE COLLAPSE ROW, not just the drawn line. `CharacterRig`
	# clamps its limbs to the floor its downward probe finds, and its ride spring only
	# has something to sit on when there IS one. The first run of this capture had only
	# the drawn line, and the collapse row read as a figure cartwheeling into an
	# unreadable blob — the body was drooping THROUGH a floor that did not exist. That
	# was a bug in the measuring instrument, not in the collapse.
	_floor_body(COLLAPSE_ROW_Y + FIG_H * 0.5)

	# --- bottom row FIRST: six live rigs, collapsed together, each frozen (by having
	# its process stopped) at its own sample step. That gives a real strip of ONE
	# motion rather than six independent guesses at it.
	var rigs: Array[Node2D] = []
	for i: int in CELLS:
		var rig: Node2D = _make_rig(Vector2(CELL_X0 + CELL_DX * float(i), COLLAPSE_ROW_Y))
		rigs.append(rig)
	await physics_frame
	for rig: Node2D in rigs:
		rig.call("set_grounded", true)
		rig.call("collapse", Vector2(1.0, -0.5))
	for step: int in (COLLAPSE_STEPS[CELLS - 1] + 1):
		for i: int in CELLS:
			if step == COLLAPSE_STEPS[i]:
				rigs[i].set_physics_process(false)   # freeze this cell here
		await physics_frame

	# --- top row: six smudges, spawned staggered in REAL milliseconds so each cell
	# sits at its own age when the shutter opens. They self-free at `duration`, so the
	# oldest is spawned first and the sheet is taken the instant the last one exists.
	var smudge_script: GDScript = load(SMUDGE_PATH) as GDScript
	var probe: Node2D = _make_rig(Vector2(-9999.0, SMUDGE_ROW_Y))
	await physics_frame
	var ordered: Array[int] = []
	for i: int in CELLS:
		ordered.append(i)
	ordered.reverse()                                # oldest cell spawns first
	var t0: int = Time.get_ticks_msec()
	var oldest: int = BEAT_MS[CELLS - 1]
	for i: int in ordered:
		var want: int = oldest - BEAT_MS[i]
		while Time.get_ticks_msec() - t0 < want:
			await process_frame
		probe.position = Vector2(CELL_X0 + CELL_DX * float(i), SMUDGE_ROW_Y)
		# Force the probe to publish its transform this frame, or every smudge is
		# spawned at the position the probe had when it was created.
		probe.force_update_transform()
		# The SHIPPED beat length, not a stretched one: a strip of a slowed-down
		# animation tells you nothing about the animation that ships.
		smudge_script.call("spawn", root, probe, Color(0.95, 0.62, 0.30),
			Vector2.RIGHT, Vector2.ZERO, smudge_script.get("DURATION"))
	probe.queue_free()
	await RenderingServer.frame_post_draw
	_save("user://death_beat.png")


func _make_rig(at: Vector2) -> Node2D:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", FIG_H)
	rig.set("limb_color", Color(0.95, 0.62, 0.30))
	rig.position = at
	_own(rig)
	rig.call("set_grounded", true)
	rig.call("play", 0)          # CharacterRig.State.IDLE — reached by ordinal, since
	return rig                   # naming the enum would need the class in scope here.


## Parent to `root` AND remember it, so the KO pass can clear the strip without
## clearing the autoloads next to it.
func _own(n: Node) -> void:
	root.add_child(n)
	_beat_nodes.append(n)


func _label(text: String, at: Vector2, col: Color) -> void:
	var l: Label = Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override("font_color", col)
	_own(l)


## A drawn ground line only — no collider. `CharacterRig` falls back to its own
## standing foot line when its downward probe finds nothing, which is exactly what a
## strip like this wants (a real StaticBody2D under six cells would have them all
## probing each other's floors).
## A real solid on GROUND_MASK (physics layer 1) spanning the whole collapse row, so
## the rigs there have something to lie ON. See the note at the call site.
func _floor_body(y: float) -> void:
	var b: StaticBody2D = StaticBody2D.new()
	b.position = Vector2(float(BEAT_W) * 0.5, y + 24.0)
	b.collision_layer = 1
	b.collision_mask = 0
	var c: CollisionShape2D = CollisionShape2D.new()
	var sh: RectangleShape2D = RectangleShape2D.new()
	sh.size = Vector2(float(BEAT_W), 48.0)
	c.shape = sh
	b.add_child(c)
	_own(b)


func _floor_line(y: float, cx: float) -> void:
	var p: Polygon2D = Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-70.0, 0.0), Vector2(70.0, 0.0), Vector2(70.0, 3.0), Vector2(-70.0, 3.0),
	])
	p.color = Color(0.24, 0.27, 0.34)
	p.position = Vector2(cx, y)
	_own(p)


# ═══════════════════════════════════════════════════ SHEET 2 — A REAL BOT-MATCH KO

func _capture_ko() -> void:
	# ⚠ FREE ONLY WHAT THE BEAT PASS BUILT. The first version cleared every child of
	# `root`, which on this tree means THE AUTOLOADS — `Rank`, `Tuning`, `Net` — and the
	# next scene came up screaming "Invalid access to property 'rank_changed' on a base
	# object of type 'previously freed'". `root` is not an empty stage.
	for c: Node in _beat_nodes:
		if is_instance_valid(c):
			c.queue_free()
	_beat_nodes.clear()
	await process_frame
	# The real game's stretch, at the resolution the maker records at.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(0, 0)
	root.size = Vector2i(KO_W, KO_H)
	var match_node: Node = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(match_node)

	# Wait for a real KO. Wall-clocked so a stalemate cannot hang the capture.
	var began: int = Time.get_ticks_msec()
	while true:
		await process_frame
		var outcome: Variant = match_node.get("_outcome")
		if outcome != null and int(outcome) != 0:
			break
		if float(Time.get_ticks_msec() - began) / 1000.0 > KO_WAIT_LIMIT:
			printerr("death_capture: no KO inside %.0fs — nothing photographed."
				% KO_WAIT_LIMIT)
			return
	var decided: int = Time.get_ticks_msec()
	print("death_capture: KO after %.1fs of fighting"
		% (float(decided - began) / 1000.0))
	for i: int in KO_SHOTS.size():
		var want_ms: int = int(KO_SHOTS[i] * 1000.0)
		while Time.get_ticks_msec() - decided < want_ms:
			await process_frame
		await RenderingServer.frame_post_draw
		_report_fighters(KO_SHOTS[i])
		var img: Image = root.get_texture().get_image()
		_write(img, "user://death_ko_%02d.png" % i)
		# ...and a ZOOMED CROP on the loser. The pair-framing camera pulls back far
		# enough that a 26 px stick figure is a smudge in a 1920x1080 frame — the first
		# run of this pass was unjudgeable for exactly that reason. The crop is what
		# actually answers "is the loser on the floor".
		_write(_crop_on_loser(img), "user://death_ko_%02d_zoom.png" % i)


## Print what the PIXELS should be showing, so a black or mis-framed capture is
## caught here rather than by squinting at a PNG.
func _report_fighters(at: float) -> void:
	var line: String = "death_capture: +%.2fs " % at
	for h: Node in get_nodes_in_group("hero"):
		var rig: Variant = h.get("rig")
		if rig == null:
			continue
		line += "[x=%.0f hp=%s limb=%s flash_left=%.3f limp=%.2f pitch=%.2f] " % [
			(h as Node2D).global_position.x, str(h.get("hp")),
			str((rig as Object).get("limb_color")),
			float((rig as Object).get("_flash_timer")),
			float((rig as Object).get("_limp")),
			(rig as Node2D).rotation,
		]
	print(line)


## A 4x blow-up of a `CROP` box centred on whichever fighter is limp — i.e. the one
## that just died. Falls back to the frame centre if nothing is collapsing, so the
## crop never silently photographs empty sky.
func _crop_on_loser(img: Image) -> Image:
	if img == null:
		return null
	var at: Vector2 = Vector2(float(KO_W) * 0.5, float(KO_H) * 0.5)
	var xf: Transform2D = root.get_final_transform() * root.get_canvas_transform()
	for h: Node in get_nodes_in_group("hero"):
		var rig: Variant = h.get("rig")
		if rig == null:
			continue
		if float((rig as Object).get("_limp")) > 0.4:
			at = xf * (h as Node2D).global_position
			break
	var x: int = clampi(int(at.x) - CROP / 2, 0, maxi(KO_W - CROP, 0))
	var y: int = clampi(int(at.y) - CROP / 2, 0, maxi(KO_H - CROP, 0))
	var out: Image = img.get_region(Rect2i(x, y, mini(CROP, KO_W), mini(CROP, KO_H)))
	out.resize(out.get_width() * 4, out.get_height() * 4, Image.INTERPOLATE_NEAREST)
	return out


func _write(img: Image, path: String) -> void:
	if img == null:
		printerr("death_capture: no image for %s" % path)
		return
	img.save_png(path)
	print("death_capture: wrote %s" % ProjectSettings.globalize_path(path))


func _save(path: String) -> void:
	_write(root.get_texture().get_image(), path)
