# Run with the GUI binary:
#   python python-tools/run_capture.py tavern
# THE TAVERN, WITH NOTHING ON TOP OF IT — the antechamber's own artwork, framed the
# way the player sees it, with every CanvasLayer hidden. `town_capture` shoots the same
# room but the tutorial card, the ability bar and the class label cover most of it, and
# what the maker is judging here is the ROOM.
#
#   user://tavern_wide.png       the whole room in one shot
#   user://tavern_bar.png        the bar end, the barrels and the dummy yard
#   user://tavern_stations.png   the two pads and the signpost — "what ARE these?"
#   user://tavern_door.png       the hearth, the tower door and the great window
#   user://tavern_ceiling.png    the beam, the lamps, the vault ribs and the haze
#
# ⚠ Under `--headless` Godot uses the DUMMY renderer and every PNG comes out blank
# while reporting success. Use the GUI binary (run_capture.py always does).
extends SceneTree

const TOWN: String = "res://scenes/Main.tscn"

const SHOTS: Array[Dictionary] = [
	{"out": "user://tavern_wide.png", "x": 470.0, "y": 300.0, "zoom": 0.50},
	{"out": "user://tavern_bar.png", "x": 20.0, "y": 340.0, "zoom": 1.00},
	{"out": "user://tavern_stations.png", "x": 540.0, "y": 330.0, "zoom": 1.00},
	{"out": "user://tavern_door.png", "x": 900.0, "y": 330.0, "zoom": 1.00},
	{"out": "user://tavern_ceiling.png", "x": 470.0, "y": 130.0, "zoom": 0.80},
]

var _cam: Camera2D = null


func _initialize() -> void:
	Engine.max_fps = 60
	var packed: PackedScene = load(TOWN)
	if packed == null:
		printerr("tavern_capture: could not load %s" % TOWN)
		quit(1)
		return
	var town: Node = packed.instantiate()
	root.add_child(town)
	_strip.call_deferred(town)
	_shoot.call_deferred()


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out


## Hide everything that is NOT the room. Deferred, because the coach and the touch pad
## are built during `_ready` and the HUD's ability bar adds children on its own first
## frame — stripping in `_initialize` would run before any of them exist.
func _strip(town: Node) -> void:
	for n: Node in _all(town):
		if n is Camera2D:
			(n as Camera2D).enabled = false
		# Every overlay in this scene is a CanvasLayer: the HUD (40), the touch pad (70)
		# and the tutorial coach. Hiding the layer takes its whole subtree with it.
		elif n is CanvasLayer:
			(n as CanvasLayer).visible = false
		# ⚠ AND `CharacterBars` ITSELF, NOT JUST ITS LAYER. It owns a `CanvasLayer` for
		# the hero's corner plate and re-shows that layer every frame from
		# `_set_plate_visible(is_visible_in_tree())` — so hiding the layer above does
		# nothing and the plate photographs over the room anyway. Hiding the BARS makes
		# `is_visible_in_tree()` false and the plate follows.
		elif n.has_method("has_plate") and n is CanvasItem:
			(n as CanvasItem).visible = false
	_cam = Camera2D.new()
	town.add_child(_cam)
	_cam.make_current()


func _shoot() -> void:
	# After `_strip` — both are deferred and call order is registration order, but the
	# camera only exists once `_strip` has run, so this waits rather than assuming.
	while _cam == null:
		await process_frame
	for shot: Dictionary in SHOTS:
		_cam.position = Vector2(float(shot["x"]), float(shot.get("y", 330.0)))
		_cam.zoom = Vector2(float(shot["zoom"]), float(shot["zoom"]))
		# Several frames: the haze drifts, the lamps flicker and the rigs settle over a
		# few physics ticks.
		for i: int in 40:
			await process_frame
		var img: Image = root.get_texture().get_image()
		var err: int = img.save_png(String(shot["out"]))
		print("%s  %s" % ["ok " if err == OK else "ERR", shot["out"]])
	quit(0)
