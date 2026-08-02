# Shows the three things about blink that no assertion can settle: it goes where you
# AIM (including straight up, which the old movement-vector blink could not express),
# it PHASES THROUGH real cover, and it is REFUSED at a wall instead of dumping the
# hero outside the room. Renders before/after pairs from the real stages — the tower
# Arena's four walls, the versus stage's cover blocks. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/blink_aim_capture.gd
#
# THREE THINGS ARE LOAD-BEARING HERE, each of which produced a silently useless frame
# on the way to this version:
#
#   1. `set_physics_process(false)` on the hero. Not just so it stops falling:
#      Hero._physics_process REWRITES `_aim_dir` from the live cursor every tick, so
#      a capture that left it running blinks toward wherever the mouse is sitting
#      rather than the direction the shot is about.
#   2. `get_tree().paused = true`. The stage keeps playing otherwise — the bot fights,
#      props tumble, the camera drifts — and a before/after pair stops being a pair.
#   3. OUR OWN Camera2D. Both stages force FIT-ALL framing (Arena does it on every
#      floor, the versus camera tracks two fighters), which renders the hero about
#      twenty pixels tall — and "is the body on the far side of that block?" is not
#      answerable at that size. A camera we own and park is the only way to get a
#      stable, readable, identically-framed pair.
extends SceneTree

const AIM_ARROW: Color = Color(1.0, 0.9, 0.3, 0.95)
## Enough to read a stick figure against a wall without losing the geometry around it.
const SHOT_ZOOM: Vector2 = Vector2(2.4, 2.4)

var _cam: Camera2D = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await _through_cover()
	await _refused_at_wall()
	await _aimed_up_and_diagonal()
	quit(0)


## Load a stage, let it settle, then FREEZE it and take the camera. Returns
## [scene, hero]; hero is null if the stage produced none.
func _open(scene_path: String) -> Array:
	var scene: Node = load(scene_path).instantiate()
	root.add_child(scene)
	for i: int in 120:
		await physics_frame
	root.get_tree().paused = true
	_cam = Camera2D.new()
	_cam.zoom = SHOT_ZOOM
	_cam.position_smoothing_enabled = false
	_cam.ignore_rotation = true
	scene.add_child(_cam)
	_cam.make_current()
	var heroes: Array = root.get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		print("blinkcap: NO HERO in ", scene_path)
		return [scene, null]
	var hero: Node2D = heroes[0]
	hero.set_physics_process(false)
	return [scene, hero]


func _close(scene: Node) -> void:
	root.get_tree().paused = false
	_cam = null
	scene.queue_free()
	await physics_frame


## Aim, park the camera, shoot the BEFORE, blink, shoot the AFTER. One helper because
## the only thing that varies between the three demonstrations is where and which way.
func _shot(scene: Node, hero: Node2D, from: Vector2, aim: Vector2, tag: String) -> Vector2:
	var dist: float = float(hero.get("BLINK_DISTANCE"))
	hero.global_position = from
	hero.set("_aim_dir", aim)
	hero.set("_blink_cooldown_timer", 0.0)
	_mark(scene, from, aim * dist)
	# Framed on the MIDDLE of the intended blink, so both ends of it are in shot and
	# the two frames of the pair are identically framed. Pushed DOWN a little (which
	# lifts the world UP the frame) because the ability bar owns the bottom ~150 px:
	# a straight-up blink centred on its own midpoint puts the ORIGIN behind the HUD,
	# and a pair where you cannot see where the body started is not a pair.
	_cam.global_position = from + aim * dist * 0.5 + Vector2(0.0, 110.0)
	await _save("blinkcap_%s_before.png" % tag)
	hero.call("_blink")
	await _save("blinkcap_%s_after.png" % tag)
	var delta: Vector2 = hero.global_position - from
	print("blinkcap %s: aim %s -> moved %s (%.1f px), cooldown %.2f"
		% [tag, aim, delta, delta.length(), float(hero.get("_blink_cooldown_timer"))])
	return delta


## 1. THROUGH STUFF. Line the hero up so the raw endpoint lands INSIDE a real cover
## block. The after-frame must show the body on the FAR side of it.
func _through_cover() -> void:
	var pair: Array = await _open("res://scenes/combat/VersusArena.tscn")
	var scene: Node = pair[0]
	var hero: Node2D = pair[1]
	if hero == null:
		await _close(scene)
		return
	var cover: Node2D = _nearest_in_group(hero, "destructible")
	if cover == null:
		print("blinkcap: no cover on the versus stage")
		await _close(scene)
		return
	var dist: float = float(hero.get("BLINK_DISTANCE"))
	var from: Vector2 = cover.global_position - Vector2(dist, 0.0)
	await _shot(scene, hero, from, Vector2.RIGHT, "through")
	print("blinkcap through: cover centre x=%.0f, hero ended x=%.0f (past it: %s)"
		% [cover.global_position.x, hero.global_position.x,
			hero.global_position.x > cover.global_position.x])
	await _close(scene)


## 2. REFUSED. Nose against the right wall of a real tower room, aiming into it. The
## after-frame must show the hero in exactly the same place, and the printed cooldown
## must be 0 — the press cost nothing rather than being swallowed.
func _refused_at_wall() -> void:
	var pair: Array = await _open("res://scenes/combat/Arena.tscn")
	var scene: Node = pair[0]
	var hero: Node2D = pair[1]
	if hero == null:
		await _close(scene)
		return
	var wall_x: float = _right_wall_x(scene)
	var from := Vector2(wall_x - 18.0, hero.global_position.y)
	await _shot(scene, hero, from, Vector2.RIGHT, "wall")
	await _close(scene)


## 3. THE ACTUAL COMPLAINT. Straight UP and a diagonal — the two directions the old
## `_move_dir` blink was structurally incapable of producing, since that vector's Y
## is hard-zero.
func _aimed_up_and_diagonal() -> void:
	var pair: Array = await _open("res://scenes/combat/Arena.tscn")
	var scene: Node = pair[0]
	var hero: Node2D = pair[1]
	if hero == null:
		await _close(scene)
		return
	var home: Vector2 = hero.global_position
	await _shot(scene, hero, home, Vector2.UP, "up")
	await _shot(scene, hero, home, Vector2(0.7, -0.7).normalized(), "diagonal")
	await _close(scene)


## The aim the shot is about, drawn into the world so a still frame can show a
## DIRECTION at all. Replaced on each shot, never accumulated.
func _mark(scene: Node, from: Vector2, span: Vector2) -> void:
	var old: Node = scene.get_node_or_null("BlinkCapMark")
	if old != null:
		old.free()
	var line := Line2D.new()
	line.name = "BlinkCapMark"
	line.width = 3.0
	line.default_color = AIM_ARROW
	line.z_index = 400
	line.points = PackedVector2Array([from, from + span])
	scene.add_child(line)


func _nearest_in_group(to: Node2D, group: String) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for n: Node in to.get_tree().get_nodes_in_group(group):
		if not n is Node2D:
			continue
		var d: float = (n as Node2D).global_position.distance_to(to.global_position)
		if d < best_d:
			best_d = d
			best = n as Node2D
	return best


## The inner face of the room's right wall, read off the collider Arena actually
## built rather than from a number copied out of LayoutDef.
func _right_wall_x(scene: Node) -> float:
	var cs: CollisionShape2D = scene.get_node_or_null("Walls/WallRight") as CollisionShape2D
	if cs == null:
		return 900.0
	var rect: RectangleShape2D = cs.shape as RectangleShape2D
	var half: float = rect.size.x * 0.5 if rect != null else 8.0
	return cs.global_position.x - half


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("blinkcap saved ", fname)
