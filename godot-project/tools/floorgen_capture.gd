# LOOK AT THE ROLLS. Renders the SAME floor drawn several different ways, into real
# frames of the real arena, so "random" can be judged as VARIETY or dismissed as
# NOISE by eye — which is the only way that question has ever been answerable.
#
# MUST run with the GUI binary — the dummy renderer under --headless draws black:
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project \
#       --script tools/floorgen_capture.gd
#   ... --script tools/floorgen_capture.gd -- --floor=3 --rolls=6
#
# Outputs (user:// = %APPDATA%/Godot/app_userdata/Legacy Frontier/):
#   floorgen_f<N>_r<K>_<shape>.png   one per roll of floor N
#
# ── HOW IT GETS A ROOM ON SCREEN ─────────────────────────────────────────────
# By building the real Arena in run mode with a GENERATED tower installed, then
# STOPPING the encounter and clearing the room. A shot is then the floor's
# architecture — walls, ledges, cover, pickups, the exit — and not twelve stick
# figures standing in front of it. The hero is left in place for scale and kept
# alive: a dead hero ends the run, drops a floor and REBUILDS THE ARENA out from
# under the capture (the trap boss_capture documents).
#
# The camera is asked for fit-all framing, which is what a real floor uses, so the
# frame is the player's actual view of the room rather than a tool's private one.
extends SceneTree

const SETTLE: int = 22

var _floor: int = 1
var _rolls: int = 6
var _arena: Node = null


func _initialize() -> void:
	_run()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--floor="):
			_floor = clampi(arg.substr(8).to_int(), 1, 5)
		elif arg.begins_with("--rolls="):
			_rolls = clampi(arg.substr(8).to_int(), 1, 12)


func _settle(n: int) -> void:
	for i: int in n:
		_keep_hero_alive()
		await process_frame


func _keep_hero_alive() -> void:
	for h in root.get_tree().get_nodes_in_group("hero"):
		if h.get("max_hp") != null:
			h.set("hp", h.get("max_hp"))
		h.set("damage_pct", 0.0)


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("floorgen_capture: saved ", ProjectSettings.globalize_path(path))


## Everything the fight spawned, gone — a shot is the ROOM.
func _clear_room() -> void:
	for e in root.get_tree().get_nodes_in_group("enemy"):
		e.free()


## ⚠ FIT-ALL FRAMING NEEDS SOMETHING TO FIT. `CombatCamera._frame_group_update`
## spans the hero plus group "enemy", so an EMPTY room eases the camera back to its
## resting zoom and the shot comes back as a close-up of one stick figure with the
## architecture off-screen — which is exactly what the first pass of this tool
## produced. Two invisible markers pinned to the room's corners give the framing
## something to span, so the frame becomes the whole floor.
func _frame_the_room(size: Vector2) -> void:
	for corner: Vector2 in [Vector2(24.0, 24.0), size - Vector2(24.0, 24.0)]:
		var m := Node2D.new()
		m.add_to_group("enemy")
		_arena.add_child(m)
		m.global_position = corner
	# ...and park the hero in the middle, because the framing is deliberately biased
	# toward wherever the player is standing (HERO_FRAME_BIAS).
	for h in root.get_tree().get_nodes_in_group("hero"):
		if h is Node2D:
			(h as Node2D).global_position = size * 0.5


## STAGE THE ROOM FOR LEGIBILITY. The tower's own look is a near-black theme wash
## with an atmosphere layer over it, which is a mood the maker chose and which makes
## an architecture shot unreadable — the first legible pass of this tool came back as
## a black rectangle with two pixels of ledge in it. So for the capture only: lift the
## floor to a flat grey, drop the atmosphere, and hide the HUD, leaving the SHAPE of
## the room, which is the only thing these frames are being asked to show.
func _stage_for_legibility() -> void:
	var f: ColorRect = _arena.get_node_or_null("Floor") as ColorRect
	if f != null:
		f.color = Color(0.16, 0.17, 0.21, 1.0)
	for c: Node in _arena.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	# `Arena._build_theme_layer` parks the Atmosphere on `_atmo`; it is a plain
	# Node2D child, so it has to be reached by the field rather than by name.
	var atmo: Node = _arena.get("_atmo")
	if atmo != null and is_instance_valid(atmo):
		atmo.queue_free()


func _shape_of(fd: Resource) -> String:
	for t: String in (fd.special_tags as Array):
		if t.begins_with(FloorGen.TAG_SHAPE):
			return t.substr(FloorGen.TAG_SHAPE.length())
	return "unknown"


func _run() -> void:
	await process_frame
	_parse_args()
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("floorgen_capture: no GameState autoload")
		quit(1)
		return
	var base: Resource = gs.call("build_default_tower")
	for r: int in _rolls:
		var seed_value: int = 10007 * (r + 1) + 13
		gs.active_tower = FloorGen.vary_tower(base, seed_value)
		gs.set("_run_active", true)
		gs.set("_floor", _floor)
		gs.set("mode", 1)   # Mode.RUN
		if _arena != null:
			_arena.free()
		_arena = load("res://scenes/combat/Arena.tscn").instantiate()
		root.add_child(_arena)
		await _settle(SETTLE)
		# Stop the fight and empty the room so the frame is the architecture.
		var enc: Node = _arena.get_node_or_null("Encounter")
		if enc == null:
			for c: Node in _arena.get_children():
				if c.has_method("run_floor"):
					enc = c
		if enc != null:
			enc.call("stop")
		_clear_room()
		_stage_for_legibility()
		var fd: Resource = gs.active_tower.floors[_floor - 1]
		_frame_the_room(fd.layout.room_size)
		for cam: Node in root.get_tree().get_nodes_in_group("combat_camera"):
			if cam.has_method("set_frame_all"):
				cam.call("set_frame_all", true)
		# Long settle: the camera opens up at FRAME_ZOOM_SPEED_OUT rather than
		# snapping, so a short wait would shoot the room mid-zoom.
		await _settle(60)
		await _shoot("user://floorgen_f%d_r%d_%s.png" % [_floor, r + 1, _shape_of(fd)])
	quit(0)
