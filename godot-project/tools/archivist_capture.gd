# Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/archivist_capture.gd
# THE ARCHIVIST — the spell tree, drawn. Three frames, because the whole point of
# the rewrite is a picture and a picture cannot be judged from a passing test:
#   user://archivist_fresh.png    a level-1 Arcanist: everything unbought
#   user://archivist_rich.png     the same tree with points to spend and half bought
#   user://archivist_other.png    a second class, so the layout is not tuned to one
#
# ⚠ Under `--headless` Godot uses the DUMMY renderer and every PNG comes out blank
# while reporting success. Use the GUI binary (run_capture.py always does).
#
# ⚠ IT DRIVES A FAKE GameState, not the player's save. The screen reads `level()` and
# `unlocked_nodes` off the `/root/GameState` autoload; writing the real one to take a
# screenshot is exactly the trap that made a test run bank xp into `climber.json`.
extends SceneTree

const SHOT_SIZE: Vector2i = Vector2i(1100, 760)


func _initialize() -> void:
	# ⚠ `root` IS the Window under `--script`, and `root.get_window()` is null at
	# `_initialize` time. Setting the size on `root` directly is the working form.
	Engine.max_fps = 60
	root.size = SHOT_SIZE
	_shoot.call_deferred()


## Buy the first `n` affordable nodes of `cls`, so the "half invested" shot is a real
## reachable state rather than a hand-written list that could name a node that moved.
func _fake_owned(cls: int, level: int, n: int) -> Array:
	var owned: Array = []
	for role: String in SpellTree.ROLES:
		for linked: bool in [false, true]:
			if owned.size() >= n:
				return owned
			var node: String = SpellTree.node_id(cls, role, linked)
			if SpellTree.spell_of(node) == "":
				continue
			if SpellTree.can_buy(node, cls, level, owned):
				owned.append(node)
	return owned


func _shoot() -> void:
	var gs: Node = root.get_node_or_null(^"/root/GameState")
	var shots: Array[Dictionary] = [
		{"out": "user://archivist_fresh.png", "cls": 0, "level": 1, "buy": 0},
		{"out": "user://archivist_rich.png", "cls": 0, "level": 12, "buy": 4},
		{"out": "user://archivist_other.png", "cls": 8, "level": 8, "buy": 2},
	]
	for shot: Dictionary in shots:
		var cls: int = int(shot["cls"])
		var level: int = int(shot["level"])
		if gs != null:
			gs.set("xp", 0)
			gs.set("unlocked_nodes", _fake_owned(cls, level, int(shot["buy"])))
		var screen: Control = SpellTreeScreen.new()
		root.add_child(screen)
		screen.call("set_class", cls)
		# Several frames: the growth lerp settles and the panel lays itself out.
		for i: int in 20:
			await process_frame
		var img: Image = root.get_texture().get_image()
		img.save_png(String(shot["out"]))
		print("ok   %s" % String(shot["out"]))
		screen.queue_free()
		await process_frame
	quit(0)
