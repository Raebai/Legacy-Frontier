# Throwaway visual check for GLACIAL SPINE — the ground-erupting ice crest that
# replaced the frost bombardment (agent-owned; safe to delete). GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/ice_spike_agent_capture.gd
#
# Three casts, each in a FRESH SpellPlayground so nothing overlaps:
#   flat   — open floor next to a practice dummy: the four beats of the spell
#            (origin tell -> origin spike erupting -> full crest -> shatter).
#   wall   — cast next to the left wall: the crest must STOP at it, not march
#            through solid rock.
#   ledge  — cast on the small floating platform: the crest must run the plank
#            and stop at both edges, not hang out over the drop.
# It parents its OWN Camera2D and make_current()s it, because the playground's
# controller pins its camera to the stick figure every frame.
extends SceneTree

const PLAYGROUND: String = "res://scenes/spike/SpellPlayground.tscn"
## [aim point, camera point, camera zoom, [[seconds after cast, name], ...]].
## The beats come straight off IceSpikeLine's dodge-budget constants:
## ORIGIN_TELL 0.45, then a spike every WAVE_STEP 0.05 out to 6 a side (0.75),
## rise 0.09 + hold 0.20, then a 0.22 shatter.
const CASTS: Array = [
	["flat", Vector2(220.0, 340.0), Vector2(140.0, 250.0), 1.15,
		[[0.30, "tell"], [0.55, "erupting"], [0.86, "crest"], [1.15, "shatter"]]],
	["wall", Vector2(-470.0, 340.0), Vector2(-400.0, 250.0), 1.15, [[0.86, "crest"]]],
	["ledge", Vector2(-320.0, 130.0), Vector2(-320.0, 60.0), 1.3, [[0.86, "crest"]]],
]
## The wall-stop case can't be shown through SpellCaster: the METEOR arm clamps
## the mark to the spell's 300px reach, so from the figure's spawn you cannot aim
## close enough to the arena wall for the crest to ever reach it. Driven directly
## instead, from a mark whose left side WANTS to run 200px into solid rock.
const WALL_MARK: Vector2 = Vector2(-520.0, 340.0)
const WALL_CAM: Vector2 = Vector2(-480.0, 250.0)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _spell(scene: Node, id: String) -> SpellDef:
	for s: SpellDef in scene.get("_spells"):
		if s.id == id:
			return s
	push_error("icecap: no spell with id " + id)
	return null


func _run() -> void:
	for entry: Array in CASTS:
		var tag: String = entry[0]
		var aim: Vector2 = entry[1]
		var scene: Node = (load(PLAYGROUND) as PackedScene).instantiate()
		root.add_child(scene)
		for i in 70:
			await physics_frame  # settle the figure + dummies onto the floor
		# Grabbed AFTER the settle loop: on the first iteration the scene's
		# _ready (which builds the HUD) hasn't fired yet at add_child time.
		var hud: Label = scene.get("_hud")
		if hud != null:
			hud.visible = false
		var cam := Camera2D.new()
		cam.position = entry[2]
		cam.zoom = Vector2(entry[3], entry[3])
		scene.add_child(cam)
		cam.make_current()
		var fig: Node = scene.get("_fig")
		var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
		SpellCaster.cast(_spell(scene, "frozen_comet"), scene, origin, aim,
			Color(0.62, 0.88, 1.0), "")
		var t: float = 0.0
		for stage: Array in (entry[4] as Array):
			await create_timer(float(stage[0]) - t).timeout
			t = float(stage[0])
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			if img != null:
				var fname: String = "icespike_%s_%s.png" % [tag, stage[1]]
				img.save_png("user://" + fname)
				print("icecap saved ", fname)
		scene.queue_free()
		for i in 5:
			await physics_frame  # let the old scene fully drop
	await _capture_wall_stop()
	quit(0)


func _capture_wall_stop() -> void:
	var scene: Node = (load(PLAYGROUND) as PackedScene).instantiate()
	root.add_child(scene)
	for i in 70:
		await physics_frame
	var hud: Label = scene.get("_hud")
	if hud != null:
		hud.visible = false
	var cam := Camera2D.new()
	cam.position = WALL_CAM
	cam.zoom = Vector2(1.3, 1.3)
	scene.add_child(cam)
	cam.make_current()
	var line: Node2D = (load("res://scripts/combat/IceSpikeLine.gd") as GDScript).new()
	scene.add_child(line)
	line.call("erupt", WALL_MARK, Color(0.62, 0.88, 1.0), 210.0, 38, "frost")
	await create_timer(0.62).timeout
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://icespike_wallstop.png")
		print("icecap saved icespike_wallstop.png")
