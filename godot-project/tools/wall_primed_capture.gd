# Look at THE TELL. The two-beat is only fair if the player can see, before they
# press, that the button will punch the wall instead of casting — so the primed
# crown has to be obviously different from the resting one at a glance.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/wall_primed_capture.gd
# Writes wall_crown_resting.png / wall_crown_primed.png to user://.
extends SceneTree

## By PATH, never class_name: a --script harness compiles before the autoloads
## exist and RockWall names Sfx. (Same trap as tools/slice_test_wall_two_beat.gd.)
const ROCK_WALL: String = "res://scripts/combat/RockWall.gd"

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
	for i in 70:
		await physics_frame                      # fully risen, judder settled
	var wall: Node2D = null
	for w: Node in get_nodes_in_group("shoveable"):
		wall = w as Node2D
	if wall == null:
		printerr("primedcap: no wall to photograph")
		quit(1)
		return
	# Freeze the controller: its per-frame arbitration would otherwise re-decide
	# the primed state from the live mouse aim between forcing it and drawing.
	_scene.set_physics_process(false)
	_scene.set_process(false)
	var cam: Camera2D = _scene.get("_cam")
	cam.zoom = Vector2(2.4, 2.4)
	cam.offset = Vector2.ZERO
	# Smoothing OFF or the camera keeps easing between the two shots and the A/B
	# stops being an A/B — the point here is that ONLY the crown changed.
	cam.position_smoothing_enabled = false
	cam.position = wall.call("footprint_center")
	cam.reset_smoothing()
	wall.call("set_primed", false)
	await _save(wall, "wall_crown_resting.png")
	wall.call("set_primed", true)
	# Park the pulse at its peak so the shot shows the tell at full strength
	# rather than wherever the sine happened to be.
	wall.set("_elapsed", _peak_elapsed(float(wall.get("_elapsed"))))
	await _save(wall, "wall_crown_primed.png")
	quit(0)


## Nearest _elapsed >= now that puts sin(t * HZ * TAU) at +1, i.e. pulse == 1.0.
func _peak_elapsed(now: float) -> float:
	var hz: float = load(ROCK_WALL).get_script_constant_map()["PRIME_PULSE_HZ"]
	var period: float = 1.0 / hz
	return (floorf(now / period) + 1.25) * period


func _save(wall: Node2D, fname: String) -> void:
	wall.queue_redraw()
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("primedcap saved ", fname)


func _find(spells: Array, id: String) -> SpellDef:
	for s: SpellDef in spells:
		if s.id == id:
			return s
	return null
