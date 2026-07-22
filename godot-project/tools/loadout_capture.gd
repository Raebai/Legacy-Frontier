# Loadout UI capture: stand up the GameState + Loadout autoloads, open the panel,
# pick a few pieces, and grab a frame so the layout + ability read-out are verifiable.
# GUI binary only.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/loadout_capture.gd
extends SceneTree


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.11, 0.14)
	bg.size = Vector2(1365, 768)
	root.add_child(bg)
	var gs: Node = load("res://scripts/GameState.gd").new()
	gs.name = "GameState"
	root.add_child(gs)
	var lo: Node = load("res://scripts/Loadout.gd").new()
	lo.name = "Loadout"
	root.add_child(lo)
	_run(lo)


func _run(lo: Node) -> void:
	for i: int in 20:
		await process_frame
	lo.call("open")
	lo.call("_on_option", "weapon", "staff_ice")
	lo.call("_on_option", "head", "hat")
	lo.call("_on_option", "body", "robe")
	for i: int in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://loadout.png")
		print("loadout_capture: saved ", ProjectSettings.globalize_path("user://loadout.png"))
	quit(0)
