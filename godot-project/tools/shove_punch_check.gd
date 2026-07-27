# Proves the PUNCH -> wall-shove hookup the way a player reaches it, rather than
# calling shove() directly the way wall_agent_capture.gd does (which is what let
# the missing wiring go unnoticed). Casts a rock wall, then punches it.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/shove_punch_check.gd
extends SceneTree

var _scene: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	for i in 70:
		await physics_frame
	var fig: Node = _scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	var rock: SpellDef = _find(_scene.get("_spells"), "rock_wall")
	SpellCaster.cast(rock, _scene, origin, origin + Vector2(300.0, 0.0),
		Color(0.78, 0.84, 1.0), "")
	for i in 60:
		await physics_frame                      # let it finish rising
	var wall: Node2D = null
	for w: Node in get_nodes_in_group("shoveable"):
		wall = w as Node2D
	if wall == null:
		print("shovecheck FAIL: no standing wall to punch")
		quit(1)
		return
	var start_x: float = (wall.get("_floor_base") as Vector2).x
	# Aim right, at the wall, and throw a normal punch — the same path the
	# player's LMB takes (SpikeFigure.punch -> punched signal -> _on_punch).
	fig.set("ctrl_aim", wall.global_position)
	fig.call("punch")
	for i in 40:
		await physics_frame
	if not is_instance_valid(wall):
		print("shovecheck PASS: punch freed the wall (slid off the map)")
		quit(0)
		return
	var now_x: float = (wall.get("_floor_base") as Vector2).x
	var sliding: bool = bool(wall.get("_sliding")) or bool(wall.get("_crumbling"))
	print("shovecheck: start_x=", start_x, " now_x=", now_x, " moved=", now_x - start_x,
		" sliding_or_spent=", sliding)
	if absf(now_x - start_x) > 20.0:
		print("shovecheck PASS: the punch shoved the wall")
		quit(0)
	else:
		print("shovecheck FAIL: punch did not move the wall")
		quit(1)


func _find(spells: Array, id: String) -> SpellDef:
	for s: SpellDef in spells:
		if s.id == id:
			return s
	return null
