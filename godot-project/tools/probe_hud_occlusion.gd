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

const FRAMES: int = 2400
const SETTLE: int = 120
## Half-height/width of a stick fighter's drawn silhouette in WORLD px. The rig is ~31
## px tall (see `probe_town_feet`) and stands on its origin, so the body occupies
## roughly y-31..y and x-8..x+8.
const BODY_H: float = 31.0
const BODY_HW: float = 8.0


func _initialize() -> void:
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
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("HUDOCC FAIL no GameState autoload")
		quit()
		return
	# Ground floor of a fresh tower, exactly what the maker is looking at.
	gs.call("reset_climb") if gs.has_method("reset_climb") else null
	gs.call("enter_run")
	for i: int in SETTLE:
		await process_frame
	var view: Vector2 = Vector2(root.get_visible_rect().size)
	var bar_h: float = float(AbilityBar.occupied_height())
	var bar_top: float = view.y - bar_h
	var hits: int = 0
	var read: int = 0
	var worst: float = 0.0
	var worst_who: String = ""
	var lowest_seen: float = 0.0
	for i: int in FRAMES:
		await process_frame
		var cam: Camera2D = _live_camera()
		if cam == null:
			continue
		var xform: Transform2D = root.get_canvas_transform()
		var bodies: Array[Node2D] = _bodies()
		if bodies.is_empty():
			continue
		read += 1
		var any: bool = false
		for b: Node2D in bodies:
			var foot: Vector2 = xform * b.global_position
			var head: Vector2 = xform * (b.global_position - Vector2(0.0, BODY_H))
			lowest_seen = maxf(lowest_seen, foot.y)
			# Only count it if the body is actually ON SCREEN horizontally and its
			# silhouette reaches into the band the bar paints.
			if foot.x < -40.0 or foot.x > view.x + 40.0:
				continue
			if foot.y > bar_top:
				any = true
				if foot.y - bar_top > worst:
					worst = foot.y - bar_top
					worst_who = str(b.name)
			elif head.y > bar_top:
				any = true
		if any:
			hits += 1
	var denom: float = maxf(float(read), 1.0)
	print("HUDOCC view=%dx%d bar_h=%.1f bar_top=%.1f  occluded=%.2f%% worst=%.1fpx (%s) lowest_foot=%.1f frames=%d" % [
		int(view.x), int(view.y), bar_h, bar_top,
		100.0 * float(hits) / denom, worst, worst_who, lowest_seen, read])
	quit()


func _live_camera() -> Camera2D:
	for c: Node in root.get_tree().get_nodes_in_group("combat_camera"):
		if c is Camera2D and (c as Camera2D).is_current():
			return c as Camera2D
	return root.get_camera_2d()


func _bodies() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for g: String in ["player", "enemy"]:
		for n: Node in root.get_tree().get_nodes_in_group(g):
			if n is Node2D and is_instance_valid(n) and not n.is_queued_for_deletion():
				out.append(n as Node2D)
	return out
