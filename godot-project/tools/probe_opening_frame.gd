extends SceneTree
## WHERE IS THE CAMERA ON THE FIRST FRAME THE VIEWER SEES?
##
## Maker, on the finished clips: *"why does the video always start in the random top
## left corner or something the camera"*.
##
## ⚠ `probe_directed_framing` CANNOT SEE THIS. It sets `SETTLE = 150` and throws the
## first 150 frames away before it measures anything — which is a reasonable thing to
## do when the question is "does the shot hold a moving pair", and is exactly the wrong
## thing when the question is "what does the shot look like when it OPENS". The bug
## lived entirely inside that discarded window, which is why a green framing probe sat
## next to a visibly wrong opening for as long as it did.
##
## Measures the OPENING: the drawn centre against the pair's midpoint, per frame, from
## the very first frame the camera exists. The intro card holds over these frames, so
## this window is also the thumbnail.
##
## ⚠ IT UNDER-REPORTS THE DURATION, AND THE RENDERED FRAMES STAY THE AUTHORITY.
## Headless runs uncapped, so the FIRST processed frame carries a large `delta`, and
## `clampf(delta * POS_LERP, 0, 1)` saturates at 1.0 — a full snap. So an unfixed build
## measures 638.6 px off-centre on frame 0 (both fighters outside the frame) and then
## reads settled by frame 1. Inside `--write-movie` the timestep is fixed and small, the
## lerp does NOT saturate, and the same fault takes ~0.5 s of real travel — which is
## what the maker actually saw. Frame 0 is the honest signal here; the settle FRAME is
## not. Confirm a fix by pulling frames out of the finished mp4.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_opening_frame.gd -- 6 8

const MATCH_SCENE := "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT := "res://scripts/combat/BotMatch.gd"
## Long enough to cover the settle the lerp used to take (~0.5 s at 60 fps) with room
## either side.
const FRAMES: int = 90
const NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut", "Cleric",
	"Cryomancer", "Stormcaller", "Necromancer", "Swordsaint",
]


func _initialize() -> void:
	# `_initialize` runs BEFORE the tree exists — defer a frame or `root` is null.
	call_deferred("_go")


func _go() -> void:
	await process_frame
	# Headless has no window and so no aspect; the stretch solve falls back to a SQUARE
	# viewport, and every framing constant in ClipDirector is written in 640x360 design
	# units. Give it the real shape or the numbers describe a frame nobody sees.
	root.size = Vector2i(1366, 768)
	await process_frame
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	var a: int = int(argv[0]) if argv.size() > 0 else 6
	var b: int = int(argv[1]) if argv.size() > 1 else 8

	var script: GDScript = load(MATCH_SCRIPT) as GDScript
	script.set("class_a", a)
	script.set("class_b", b)
	script.set("auto_rematch", false)
	var m: Node = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(m)

	var view: Vector2 = Vector2(root.get_visible_rect().size)
	var worst: float = 0.0
	var worst_at: int = -1
	var first: float = -1.0
	var rows: Array[String] = []
	var settled_at: int = -1
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
		var z: float = cam.zoom.x
		# THE DRAWN CENTRE, not the target. `global_position` is where the camera is
		# being ASKED to go; the picture is `get_screen_center_position()`.
		var shot: Vector2 = cam.get_screen_center_position()
		var mid: Vector2 = (pts[0] + pts[1]) * 0.5
		# In SCREEN pixels, which is the unit the fault is visible in.
		var off: float = (mid - shot).length() * z
		# Is anybody outside the frame? That is the "one fighter missing" complaint.
		var out: int = 0
		for p: Vector2 in pts:
			if absf(p.x - shot.x) * z > view.x * 0.5 or absf(p.y - shot.y) * z > view.y * 0.5:
				out += 1
		if first < 0.0:
			first = off
		if off > worst:
			worst = off
			worst_at = i
		# "Settled" = within a tenth of the frame width of the pair midpoint, and
		# staying there.
		if settled_at < 0 and off <= view.x * 0.10 and out == 0:
			settled_at = i
		if i < 6 or i == 10 or i == 20 or i == 30 or i == 60:
			rows.append("    frame %2d  off-centre %6.1f px  zoom %.2f  offscreen %d/2"
				% [i, off, z, out])
	print("OPENING  %s v %s" % [NAMES[a], NAMES[b]])
	for r: String in rows:
		print(r)
	print("  first frame off-centre : %.1f px  (frame width %.0f)" % [first, view.x])
	print("  worst                  : %.1f px at frame %d" % [worst, worst_at])
	print("  settled within 10%% of  : frame %d%s" % [settled_at,
		"  <- the opening travels, and the VS card is over it" if settled_at > 2 else ""])
	quit()
