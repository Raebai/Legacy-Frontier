# CUSTOMISATION capture: the three screens a player now has that they did not before —
# the title screen's new PREPARE row, the OUTFITTER (choose which three of your class's
# five spells you carry, plus the colourway), and the ARMORY, which was complete and
# unreachable and did not fit a phone.
#
# Rendered at the 640x360 BASE VIEWPORT on purpose. These screens are pinned to that
# budget by tools/slice_test_outfitter.gd, and a capture at desktop size would prove
# nothing about the one platform this game is for — everything fits at 1365x768.
# GUI binary only.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/outfitter_capture.gd
extends SceneTree

## The base viewport from project.godot, landscape.
const W: int = 640
const H: int = 360


func _initialize() -> void:
	# A `--script` run registers NO autoloads, so the two the lobby and the outfitter
	# reach for through the tree are stood up by hand under the names they look for.
	var gs: Node = load("res://scripts/GameState.gd").new()
	gs.name = "GameState"
	root.add_child(gs)
	var lo: Node = load("res://scripts/Loadout.gd").new()
	lo.name = "Loadout"
	root.add_child(lo)
	_run(lo)


func _run(lo: Node) -> void:
	# The WINDOW, not just the root Control: `root.size` on the main window is
	# advisory (Godot warns and ignores it), so the frame comes out at whatever the
	# desktop default is — which would make a capture that claims to prove a 640x360
	# budget and proves nothing.
	DisplayServer.window_set_size(Vector2i(W, H))
	var win: Window = root
	win.content_scale_size = Vector2i(W, H)
	for i: int in 5:
		await process_frame
	var lobby: Control = (load("res://scenes/ui/Lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	# The lobby's paper backdrop draws its reveal over ~2.6 s; let it finish so the
	# shot is the screen a player sits looking at rather than a half-drawn tower.
	for i: int in 200:
		await process_frame
	await _shot("customise_1_lobby")

	# ── the outfitter, on the class the lobby is showing ──
	lobby.call("_open_outfitter")
	for i: int in 20:
		await process_frame
	await _shot("customise_2_outfitter")

	# ...and again after swapping the hand, so the shot shows the pick doing something.
	var out: Control = lobby.get("_outfitter")
	var choosable: Array = SpellLibrary.choosable_roles_for_class(int(out.call("class_id")))
	if choosable.size() >= 3:
		out.call("_toggle_role", String(choosable[2]))
	for i: int in 15:
		await process_frame
	await _shot("customise_3_hand_swapped")

	# ── the armory, at phone size, which is the thing it never used to survive ──
	lo.call("open")
	lo.call("_on_option", "weapon", "staff_ice")
	lo.call("_on_option", "head", "hat")
	lo.call("_on_option", "body", "robe")
	for i: int in 20:
		await process_frame
	await _shot("customise_4_armory")

	SpellLibrary.clear_slot_roles()
	quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("outfitter_capture: no frame for ", name)
		return
	var path: String = "user://%s.png" % name
	img.save_png(path)
	print("outfitter_capture: saved ", ProjectSettings.globalize_path(path))
