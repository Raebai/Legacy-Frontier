extends SceneTree
## DOES THE SHOWCASE CAMERA KEEP THE FIGHTERS IN THE MIDDLE OF THE PICTURE?
##
## The maker's report is *"the camera in the bot fight needs to follow the players, it
## drifts to the side sometimes"*. "Sometimes" is the interesting word: a framer that is
## simply wrong is wrong every frame. One that is right until a condition trips is a
## CLAMP — and `_update_showcase_camera` clamps x to
##
##     clampf(focus.x, 340.0, STAGE_SIZE.x - 340.0)          # 340 .. 1660
##
## anchored to `STAGE_SIZE` (2000 wide, centred on 1000) while the fight floor is
## x 40..1400 (centred on 720). It is also a CONSTANT, and the world half-width of the
## frame is not: at zoom 1.25 it is 546 px, at 0.60 it is 1138.
##
## ⚠ READ THE DRAWN CHANNEL, NOT THE TARGET. `_build_showcase_camera` sets
## `position_smoothing_enabled = true`, so `Camera2D.global_position` is where the
## camera is being ASKED to go and `get_screen_center_position()` is where the frame
## actually is. The first version of this probe read `global_position`, reported
## nonsense in the thousands, and disagreed with a hand trace — because a target that
## tracks perfectly says nothing about a frame that lags 250 ms behind it. That lag IS
## part of what the maker is seeing.
##
## Run (one pair per process — the statics and the leaked nodes make a second arena in
## the same process untrustworthy):
##   godot --headless --path godot-project --script tools/probe_showcase_framing.gd -- 6 8

const ARENA := "res://scenes/combat/VersusArena.tscn"
const WARMUP: int = 90       # let the spawn settle and the zoom smooth before reading
const FRAMES: int = 1800     # ~30 s of fighting at 60 Hz
const NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut", "Cleric",
	"Cryomancer", "Stormcaller", "Necromancer", "Swordsaint",
]


func _initialize() -> void:
	# ⚠ The tree does not exist yet in `_initialize`. Everything below runs a frame later.
	call_deferred("_go")


func _go() -> void:
	await process_frame
	# ⚠ HEADLESS HAS NO WINDOW, SO IT HAS NO ASPECT. `DisplayServer.window_get_size()`
	# is (0, 0) under the headless driver and the stretch solve falls back to a SQUARE
	# 640x640 viewport. Every `get_visible_rect()` in here would then be measuring a
	# frame 280 px taller than the one the maker is looking at. Setting the root window
	# size makes the stretch solve produce the real logical 640x360.
	root.size = Vector2i(1366, 768)
	await process_frame
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	var a: int = int(argv[0]) if argv.size() > 0 else 6
	var b: int = int(argv[1]) if argv.size() > 1 else 8
	# Optional 3rd arg sweeps `Camera2D.position_smoothing_speed` WITHOUT editing the
	# source, so the number that gets shipped is the one that won a measurement.
	var speed: float = float(argv[2]) if argv.size() > 2 else -1.0
	var r: Dictionary = await _measure(a, b, speed)
	print("FRAMING spd=%-5s %-24s mean=%6.1f p95=%6.1f worst=%6.1f clamp=%5.1f%% off=%5.1f%% lag=%6.1f jerk=%5.2f zoom=%.2f..%.2f" % [
		("def" if speed < 0.0 else str(speed)), r["pair"], r["mean"], r["p95"], r["worst"], r["clamped"], r["off"], r["lag"], r["jerk"],
		r["zmin"], r["zmax"]])
	quit()


func _measure(a: int, b: int, speed: float = -1.0) -> Dictionary:
	var vs: Script = load("res://scripts/combat/VersusArena.gd") as Script
	vs.set("showcase_a", a)
	vs.set("showcase_b", b)
	vs.set("showcase_directed", false)
	var arena: Node = (load(ARENA) as PackedScene).instantiate()
	root.add_child(arena)
	if speed > 0.0:
		var c0: Camera2D = arena.get("_show_cam") as Camera2D
		if c0 != null:
			c0.position_smoothing_speed = speed
	for i: int in WARMUP:
		await process_frame
	var view: Vector2 = Vector2(root.get_visible_rect().size)
	var half_w: float = view.x * 0.5
	var offs: Array[float] = []
	var clamped: int = 0
	var offscreen: int = 0
	var read: int = 0
	var lags: Array[float] = []
	var zmin: float = 99.0
	var zmax: float = 0.0
	# JERK — the second difference of the drawn centre, in SCREEN px. Chasing harder
	# lowers the off-centre error; past some rate it buys that by snapping to every
	# twitch, and this is the column that shows it. Off-centre alone would happily
	# recommend an infinitely stiff camera.
	var jerks: Array[float] = []
	var prev1: float = NAN
	var prev2: float = NAN
	for i: int in FRAMES:
		await process_frame
		var cam: Camera2D = arena.get("_show_cam") as Camera2D
		if cam == null:
			continue
		var pts: Array[Vector2] = _fighter_points(arena)
		if pts.size() < 2:
			continue
		read += 1
		var mid_x: float = (pts[0].x + pts[1].x) * 0.5
		var z: float = cam.zoom.x
		zmin = minf(zmin, z)
		zmax = maxf(zmax, z)
		# THE DRAWN CENTRE, not the target. See the note at the top of this file.
		var shot_x: float = cam.get_screen_center_position().x
		lags.append(absf(shot_x - cam.global_position.x))
		offs.append(absf(mid_x - shot_x) * z)
		if not is_nan(prev2):
			jerks.append(absf(shot_x - 2.0 * prev1 + prev2) * z)
		prev2 = prev1
		prev1 = shot_x
		# Did the x clamp bite? It bit if the TARGET sits on a rail while the pair's
		# midpoint wanted it past that rail.
		if (absf(cam.global_position.x - 340.0) < 0.5 and mid_x < 339.5) \
				or (absf(cam.global_position.x - 1660.0) < 0.5 and mid_x > 1660.5):
			clamped += 1
		for p: Vector2 in pts:
			if absf(p.x - shot_x) * z > half_w:
				offscreen += 1
				break
	offs.sort()
	lags.sort()
	var jerk: float = 0.0
	for j: float in jerks:
		jerk += j
	if not jerks.is_empty():
		jerk /= float(jerks.size())
	var mean: float = 0.0
	for o: float in offs:
		mean += o
	if not offs.is_empty():
		mean /= float(offs.size())
	var denom: float = maxf(float(read), 1.0)
	return {
		"pair": "%s v %s" % [NAMES[a], NAMES[b]],
		"mean": mean,
		"p95": 0.0 if offs.is_empty() else offs[mini(int(float(offs.size()) * 0.95), offs.size() - 1)],
		"worst": 0.0 if offs.is_empty() else offs[offs.size() - 1],
		"clamped": 100.0 * float(clamped) / denom,
		"off": 100.0 * float(offscreen) / denom,
		"jerk": jerk,
		"lag": 0.0 if lags.is_empty() else lags[mini(int(float(lags.size()) * 0.95), lags.size() - 1)], "zmin": zmin, "zmax": zmax,
	}


func _fighter_points(arena: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var reg: Dictionary = arena.get("_registry") as Dictionary
	if reg == null:
		return out
	for entry: Dictionary in reg.values():
		var n: Node = entry["node"]
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			out.append((n as Node2D).global_position)
	return out
