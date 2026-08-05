# READ-ONLY DIAGNOSTIC. GUI BINARY ONLY.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_visual_swordswing.gd
#
# The REAL sword swing, frame by frame, framed on the VICTIM — not `take_damage`
# called by hand. The full path fires things the direct call never does: the
# attacker's `cast_gesture(IGNITE_DROP)` orb at the sword hand (which at melee range
# lands ON TOP of the victim), `_draw_slash_arc`, `Juice.on_hit`'s hitstop, and
# `apply_status`. Any of those could be the "sphere-ish white thing".
#
# 26 consecutive rendered frames from the swing commit. Hit-stop drops
# Engine.time_scale to ~0.05, so the impact occupies MANY of them — which is the
# point: the maker sees that stretched moment, so the capture must too.
extends SceneTree

const ARENA: String = "res://scenes/combat/Arena.tscn"

var _cam: Camera2D = null
var _root: Node = null


func _initialize() -> void:
	Engine.max_fps = 60
	_root = (load(ARENA) as PackedScene).instantiate()
	root.add_child(_root)
	_run.call_deferred()


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out


func _run() -> void:
	for i: int in 120:
		await process_frame
	var heroes: Array = _root.get_tree().get_nodes_in_group("player")
	if heroes.is_empty():
		heroes = _root.get_tree().get_nodes_in_group("hero")
	var hero: Node2D = heroes[0] as Node2D
	var enemy: Node2D = null
	for n: Node in _root.get_tree().get_nodes_in_group("enemy"):
		enemy = n as Node2D
		break
	if hero == null or enemy == null:
		printerr("no hero/enemy"); quit(1); return

	for c: Node in _all(_root):
		if c is CanvasLayer and not (c is ImpactFrame):
			(c as CanvasLayer).visible = false
		if c is Camera2D:
			(c as Camera2D).enabled = false
	_cam = Camera2D.new()
	_root.add_child(_cam)
	_cam.make_current()
	_cam.zoom = Vector2(4.0, 4.0)

	hero.call("equip_weapon", "sword")
	enemy.set("hp", 9999)
	enemy.set("max_hp", 9999)
	enemy.global_position = hero.global_position + Vector2(40.0, 0.0)
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.set("facing", Vector2.RIGHT)
	for i: int in 30:
		await process_frame

	# Framed on the MIDPOINT between the two, so the contact point is centred and
	# nothing that happens between them can fall outside the shot.
	var mid: Vector2 = hero.global_position.lerp(enemy.global_position, 0.5)
	_cam.position = mid + Vector2(0.0, -8.0)

	hero.call("_melee")
	for i: int in 26:
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var p: String = "user://_pv_swing_%02d.png" % i
		if img.save_png(p) != OK:
			printerr("ERR ", p)
	print("ok  26 swing frames")
	quit(0)
