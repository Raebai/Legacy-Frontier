extends SceneTree
## DOES THE DIRECTED CAMERA — THE ONE THAT ACTUALLY FILMS A BOT FIGHT — HOLD THE PAIR?
##
## ⚠ THIS EXISTS BECAUSE `probe_showcase_framing` MEASURES A PATH THE BOT FIGHT DOES
## NOT USE. That probe instantiates `VersusArena` with `showcase_directed = false`, so
## it exercises `_update_showcase_camera`. But `BotMatch` — Lobby -> Watch Bots, and
## every clip capture — sets `showcase_directed = true`, and `_update_showcase_camera`
## returns immediately when the director frames the shot. So the fixes verified there
## cover free play and a played duel, and `ClipDirector` is what the maker is watching.
##
## Reports, on the DRAWN channel: how far off centre the pair's midpoint sits, whether
## anybody leaves the frame, and how much of the frame the fighters actually occupy —
## the last one because "the picture is mostly empty sky" is a framing fault that a
## containment solve will happily call a success.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_directed_framing.gd -- 3 8

const MATCH_SCENE := "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT := "res://scripts/combat/BotMatch.gd"
const SETTLE: int = 150
## ClipDirector.RIG_WORLD_PX, duplicated rather than imported: this probe drives a
## SceneTree and must not depend on the director being loadable as a class here.
const RIG_WORLD_PX: float = 31.0
const FRAMES: int = 2400
const NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut", "Cleric",
	"Cryomancer", "Stormcaller", "Necromancer", "Swordsaint",
]


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	# Headless has no window and so no aspect; the stretch solve falls back to a SQUARE
	# viewport, and every framing constant in ClipDirector is written in 640x360 design
	# units. Give it the real shape or the numbers describe a frame nobody sees.
	root.size = Vector2i(1366, 768)
	await process_frame
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	var a: int = int(argv[0]) if argv.size() > 0 else 3
	var b: int = int(argv[1]) if argv.size() > 1 else 8
	# ⚠ MEASURE THE SHAPE THAT IS ACTUALLY POSTED. Every clip that reaches a phone is
	# 9:16, and ClipDirector takes a COMPLETELY different branch there — its own zoom
	# clamps, its own ground anchor, its own recovery net. Measuring only 1366x768 was
	# measuring a frame no viewer sees, which is the same class of mistake that made
	# `probe_showcase_framing` describe a camera path the bot fight does not use.
	if argv.size() > 2 and String(argv[2]) == "portrait":
		root.size = Vector2i(1080, 1920)
		await process_frame

	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	script.set("class_a", a)
	script.set("class_b", b)
	script.set("auto_rematch", false)
	var m: Node = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(m)
	for i: int in SETTLE:
		await process_frame

	var view: Vector2 = Vector2(root.get_visible_rect().size)
	var offs: Array[float] = []
	var seps: Array[float] = []
	var zooms: Array[float] = []
	var offscreen: int = 0
	var read: int = 0
	for i: int in FRAMES:
		await process_frame
		var cam: Camera2D = root.get_camera_2d()
		if cam == null:
			continue
		var pts: Array[Vector2] = []
		for n: Node in root.get_tree().get_nodes_in_group(&"hero"):
			if n is Node2D and is_instance_valid(n) and not n.is_queued_for_deletion():
				pts.append((n as Node2D).global_position)
		if pts.size() < 2:
			continue
		read += 1
		var z: float = cam.zoom.x
		# THE DRAWN CENTRE, not the target — the camera smooths, so `global_position`
		# is where it is being asked to go, not where the picture is.
		var shot: Vector2 = cam.get_screen_center_position()
		var mid_x: float = (pts[0].x + pts[1].x) * 0.5
		offs.append(absf(mid_x - shot.x) * z)
		seps.append(absf(pts[0].x - pts[1].x) * z)
		zooms.append(z)
		for p: Vector2 in pts:
			if absf(p.x - shot.x) * z > view.x * 0.5:
				offscreen += 1
				break
	offs.sort()
	var zoom_mean: float = _mean(zooms)
	zooms.sort()
	var denom: float = maxf(float(read), 1.0)
	# SUBJECT SHARE is the number the maker is judging when they say the figures are
	# too small: what fraction of frame HEIGHT one fighter fills. ClipDirector computes
	# the same thing in `subject_share()`; it is recomputed here from the DRAWN zoom so
	# the probe reports the picture rather than the director's intention.
	var share: float = 100.0 * zoom_mean * RIG_WORLD_PX / maxf(view.y, 1.0)
	var shape: String = "portrait" if view.y > view.x else "landscape"
	print("DIRECTED %-24s [%s %dx%d] off-centre mean=%.1f p95=%.1f  offscreen=%.1f%%  zoom %.2f..%.2f (mean %.2f)  pair spans %.0f%% of frame width  SUBJECT %.1f%% of frame height" % [
		"%s v %s" % [NAMES[a], NAMES[b]], shape, int(view.x), int(view.y),
		_mean(offs), _pct(offs, 0.95), 100.0 * float(offscreen) / denom,
		zooms[0], zooms[zooms.size() - 1], zoom_mean,
		100.0 * _mean(seps) / view.x, share])
	quit()


func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var t: float = 0.0
	for v: float in a:
		t += v
	return t / float(a.size())


func _pct(sorted_a: Array[float], p: float) -> float:
	if sorted_a.is_empty():
		return 0.0
	return sorted_a[mini(int(float(sorted_a.size()) * p), sorted_a.size() - 1)]
