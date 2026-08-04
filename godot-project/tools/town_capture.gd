# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/town_capture.gd
# THE TOWN — the game's front door. Four frames, so the layout can be judged by
# eye rather than by arithmetic:
#   user://town_wide.png     the whole street, spawn to shops, in one shot
#   user://town_door.png     where you SPAWN — on the tower's doorstep
#   user://town_stations.png the armory rack and the spell lectern
#   user://town_altar.png    the class statue, with a townsperson mid-amble
#
# ⚠ Under `--headless` Godot uses the DUMMY renderer and every PNG comes out
# blank while reporting success. Use the GUI binary (run_capture.py always does).
extends SceneTree

const TOWN: String = "res://scenes/Main.tscn"

## Each shot: where to look, how far out, and where it lands.
const SHOTS: Array[Dictionary] = [
	{"out": "user://town_wide.png", "x": 560.0, "zoom": 0.46},
	{"out": "user://town_door.png", "x": 866.0, "zoom": 1.05},
	{"out": "user://town_stations.png", "x": 400.0, "zoom": 0.72},
	{"out": "user://town_altar.png", "x": 470.0, "zoom": 1.05},
	# ⚠ THE LEG SHOTS, AND THEY ARE THE POINT OF THIS FILE NOW. The maker has reported
	# "everyone's legs are still weird" three times, and every previous fix was judged
	# at a zoom where a bent knee is four pixels. These are 3.4x — the same figure the
	# player sees, big enough to see a joint. `y` is pulled UP to the feet rather than
	# left at the framing height, because at this zoom the ground line is the subject.
	{"out": "user://town_legs_player.png", "x": 876.0, "y": 430.0, "zoom": 3.4},
	{"out": "user://town_legs_dummy.png", "x": 172.0, "y": 430.0, "zoom": 3.4},
	{"out": "user://town_legs_statue.png", "x": 460.0, "y": 430.0, "zoom": 3.4},
	{"out": "user://town_legs_folk.png", "x": 320.0, "y": 430.0, "zoom": 3.4},
]

var _cam: Camera2D = null


func _initialize() -> void:
	Engine.max_fps = 60
	var packed: PackedScene = load(TOWN)
	if packed == null:
		printerr("town_capture: could not load %s" % TOWN)
		quit(1)
		return
	var town: Node = packed.instantiate()
	root.add_child(town)
	# The town's own camera lives on the player and is limit-clamped to the street,
	# which is exactly what we do NOT want for a wide shot. It also becomes current
	# in its own `_ready`, AFTER ours would — so it has to be switched off, not just
	# out-ranked, or every shot silently comes back framed on the player.
	for cam: Node in _all(town):
		if cam is Camera2D:
			(cam as Camera2D).enabled = false
	_cam = Camera2D.new()
	town.add_child(_cam)
	_cam.make_current()
	_shoot.call_deferred()


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out


func _shoot() -> void:
	for shot: Dictionary in SHOTS:
		_cam.position = Vector2(float(shot["x"]), float(shot.get("y", 330.0)))
		_cam.zoom = Vector2(float(shot["zoom"]), float(shot["zoom"]))
		# Several frames: the stick rigs settle over a few physics ticks and the
		# ambience (fireflies, campfire) needs time to have anything to draw.
		for i: int in 40:
			await process_frame
		var img: Image = root.get_texture().get_image()
		var err: int = img.save_png(String(shot["out"]))
		print("%s  %s" % ["ok " if err == OK else "ERR", shot["out"]])
	# THE LECTERN'S SCREEN, opened the way the station opens it. This is the only
	# proof available headlessly that a station reaches a real destination: the
	# other two go to AUTOLOADS (`ClassSelect`, `Loadout`) and a `--script` run does
	# not register autoloads, so they cannot be posed here at all.
	var town: Node = root.get_child(root.get_child_count() - 1)
	for n: Node in root.get_children():
		if n.has_method("open_outfitter"):
			town = n
	if town.has_method("open_outfitter"):
		town.call("open_outfitter")
		for i: int in 30:
			await process_frame
		var shot_img: Image = root.get_texture().get_image()
		print("%s  user://town_outfitter.png"
			% ["ok " if shot_img.save_png("user://town_outfitter.png") == OK else "ERR"])
	else:
		printerr("town_capture: the town does not offer open_outfitter()")
	quit(0)
