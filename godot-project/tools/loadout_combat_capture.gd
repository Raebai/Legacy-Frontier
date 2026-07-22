# Full-stack capture: set a custom LOADOUT (ice staff + hat + robe) on GameState, boot
# the combat arena, and grab a frame — the geared hero + geared enemies + post-process
# grade all together (the ultimate "does it all work" visual). GUI binary only.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/loadout_combat_capture.gd
extends SceneTree


func _initialize() -> void:
	var gs: Node = root.get_node_or_null("GameState")  # autoload lives at /root/GameState
	if gs != null:
		gs.set("loadout", {"weapon": "staff_ice", "head": "hat", "body": "robe"})
		gs.set("selected_class", 0)  # mage -> with the ice staff loadout it casts ICE
	else:
		print("loadout_combat_capture: no GameState autoload — capturing default loadout")
	root.add_child((load("res://scenes/combat/VersusArena.tscn") as PackedScene).instantiate())
	_run()


func _run() -> void:
	for i: int in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://loadout_combat.png")
		print("loadout_combat_capture: saved ", ProjectSettings.globalize_path("user://loadout_combat.png"))
	quit(0)
