# Deterministic debris/crater money-shot: loads the versus arena, detonates a
# blast on the floor immediately (skipping the windup), shatters a cover block,
# then captures full-res once the physics chunks are mid-arc. Verifies the
# "spells hit the floor + bits fly off" physics that's too small/timing-flaky to
# catch in the contact sheet. Run with the GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/debris_demo.gd
extends SceneTree

const OUT_PATH: String = "user://debris_shot.png"


func _initialize() -> void:
	var scene: Node = load("res://scenes/combat/VersusArena.tscn").instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for _i: int in 30:
		await process_frame  # settle: fighters drop, camera frames P1

	# Shatter every cover block: clean physics-chunk debris flying off the map,
	# with no giant blast flash to obscure it (the "bits fly off" verification).
	for prop: Node in get_nodes_in_group("destructible"):
		if prop.has_method("take_damage"):
			prop.call("take_damage", 999)

	for _j: int in 13:
		await process_frame  # let the chunks launch + arc mid-flight
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		var err: int = img.save_png(OUT_PATH)
		if err == OK:
			print("debris_demo: saved ", ProjectSettings.globalize_path(OUT_PATH))
		else:
			printerr("debris_demo: save failed err=", err)
	quit(0)
