extends SceneTree
## IS A FIGHTER DRAWN UNDERNEATH THE ABILITY BAR ON THE TOWER'S GROUND FLOOR?
##
## Maker: *"I dont want the bottom bar blocking the characters when they are on the
## ground floor of the tower"*. This was answered once already — `CombatCamera` now
## reserves `AbilityBar.occupied_height()` and shifts the frame up by half of it — and
## the report came back anyway. So stop reasoning about the reserve and MEASURE THE
## DRAWN CHANNEL: put every body through the real canvas transform, and ask whether its
## on-screen rect intersects the bar's on-screen rect.
##
## ⚠ WHY THE EXISTING RESERVE CAN STILL LEAVE A BODY BEHIND THE BAR:
##   1. `_frame_group_update` only runs while `_frame_all` is on, and its `count <= 1`
##      branch eases `_frame_offset` back to ZERO — which is where the HUD shift lives.
##      So the instant the last enemy on the floor dies, the shift unwinds and the hero
##      slides back down behind the bar.
##   2. The reserve is a FULL-WIDTH band, but on desktop the bar is 0.62x and tucked
##      into the bottom-LEFT (`origin_x = SIDE_MARGIN`). So the camera pays for a band
##      it does not need on the right — and yet a body in the bottom-left corner, which
##      is where the reserve is actually needed, is only guaranteed half of it.
##
## Reports the fraction of frames with any body overlapping the bar, and the worst
## overlap depth in screen px. Zero is the only passing answer.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_hud_occlusion.gd

const SETTLE: int = 90
## Half-height/width of a stick fighter's drawn silhouette in WORLD px. The rig is ~31
## px tall (`probe_town_feet`) and stands on its origin.
const BODY_H: float = 31.0
## The vertical spreads a real room can produce. `FloorGen.MAX_ROOM` is 1220x620 and
## the ledge skyline puts enemies on top of it, so the hero-on-the-floor /
## enemy-on-the-highest-ledge case runs to most of the room height.
const SPREADS: Array[float] = [0.0, 120.0, 240.0, 360.0, 480.0, 600.0]
## And the horizontal spreads, because `fit` is the MIN of the two axes: a wide group
## can be the binding constraint, which makes the vertical solve looser than the
## vertical numbers alone suggest.
const WIDTHS: Array[float] = [0.0, 400.0, 900.0, 1180.0]


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	# ⚠ HEADLESS HAS NO WINDOW, SO IT HAS NO ASPECT. `DisplayServer.window_get_size()`
	# is (0, 0) under the headless driver and the stretch solve falls back to a SQUARE
	# 640x640 viewport — a frame 280 px TALLER than the maker's. This probe is entirely
	# about the bottom of the frame, so that fallback would have made it answer "clear"
	# no matter what. Setting the root window size yields the real logical 640x360.
	root.size = Vector2i(1366, 768)
	await process_frame
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("HUDOCC FAIL no GameState autoload")
		quit()
		return
	gs.call("enter_run")
	for i: int in SETTLE:
		await process_frame
	var view: Vector2 = Vector2(root.get_visible_rect().size)
	var bar_h: float = float(AbilityBar.occupied_height())
	var bar_top: float = view.y - bar_h
	var hero: Node2D = _hero()
	# ⚠ EVERY ENEMY IN THE ROOM VOTES, NOT JUST THE ONE THIS PROBE MOVES.
	# `_frame_group_update` walks the whole "enemy" group, so a first version that
	# placed a single foe was reporting spreads it had not actually created — the rest
	# of the wave was still scattered across the room setting the real bounding box.
	# Every foe is placed together, so the spread on the left of the table is the
	# spread the framer sees.
	var foes: Array[Node2D] = _foes()
	if hero == null or foes.is_empty():
		print("HUDOCC FAIL hero=%s foes=%d" % [str(hero), foes.size()])
		quit()
		return
	# Freeze the bodies so physics does not undo the placement between frames.
	hero.set_physics_process(false)
	for f: Node2D in foes:
		f.set_physics_process(false)
	var base: Vector2 = hero.global_position
	print("HUDOCC view=%dx%d bar_h=%.1f bar_top=%.1f" % [view.x, view.y, bar_h, bar_top])
	print("  room=%s  hero_base=%s" % [str(_room_of()), str(base)])
	print("  vspread  hspread   fit   limB   camC  heroY  hero_foot_y  clear_by  verdict")
	var worst: float = 1e9
	for w: float in WIDTHS:
		for v: float in SPREADS:
			# Worst case for the bottom of the frame: the HERO is the lowest body and
			# everything else is above, which biases the framed centroid upward and
			# pushes the hero down the picture.
			# ⚠ RE-PLACED EVERY FRAME, NOT EVERY CASE. `Encounter` trickles new waves
			# in while the probe settles, and an arrival standing at its own spawn
			# point silently enlarges the bounding box the framer solves against. A
			# list captured once per case made the same reading move 65 px between
			# runs — which looked exactly like a real effect and was not.
			for i: int in 150:
				foes = _foes()
				hero.global_position = base
				hero.set_physics_process(false)
				for fi: int in foes.size():
					foes[fi].set_physics_process(false)
					var t: float = 0.0 if foes.size() < 2 else float(fi) / float(foes.size() - 1)
					foes[fi].global_position = base + Vector2(w * t, -v)
				await process_frame
			var xform: Transform2D = root.get_canvas_transform()
			var foot: Vector2 = xform * hero.global_position
			var cam: Camera2D = _live_camera()
			var fit: float = 0.0 if cam == null else cam.zoom.x
			var clear: float = bar_top - foot.y
			worst = minf(worst, clear)
			print("  %7.0f  %7.0f  %5.2f %6d %6.0f %6.0f  %10.1f  %8.1f  %s" % [
				v, w, fit, (0 if cam == null else cam.limit_bottom),
				(0.0 if cam == null else cam.get_screen_center_position().y),
				hero.global_position.y, foot.y, clear,
				"CLEAR" if clear > 0.0 else "*** UNDER ***"])
	print("HUDOCC WORST CLEARANCE %.1f px  (negative = a fighter is drawn behind the bar)" % worst)
	quit()


func _room_of() -> Vector2:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		return Vector2.ZERO
	var fd: Variant = gs.call("floor_def_for", 1)
	if fd == null:
		return Vector2.ZERO
	var lay: Variant = fd.get("layout")
	return Vector2.ZERO if lay == null else (lay.get("room_size") as Vector2)


func _live_camera() -> Camera2D:
	for c: Node in root.get_tree().get_nodes_in_group("combat_camera"):
		if c is Camera2D and (c as Camera2D).is_current():
			return c as Camera2D
	return root.get_camera_2d()


func _hero() -> Node2D:
	for n: Node in root.get_tree().get_nodes_in_group("hero"):
		if n is Node2D:
			return n as Node2D
	return null


func _foes() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for n: Node in root.get_tree().get_nodes_in_group("enemy"):
		if n is Node2D and is_instance_valid(n) and not n.is_queued_for_deletion():
			out.append(n as Node2D)
	return out
