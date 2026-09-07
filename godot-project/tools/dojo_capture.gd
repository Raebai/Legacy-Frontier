# THE DOJO, AS DRAWN. GUI binary only (headless renders black):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/dojo_capture.gd
# -> user://dojo.png
#
# Answers three things no assertion settles: is the sensei a visible stick figure, are
# there dummies to hit, and does the lesson card name the key it is waiting for.
extends SceneTree

const SETTLE: float = 3.2


func _initialize() -> void:
	_run()


func _run() -> void:
	var fp: GDScript = load("res://scripts/combat/FreePlay.gd") as GDScript
	fp.set("dojo", true)
	fp.call("enter", self, 0)
	await create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("no frame")
		quit(1)
		return
	img.save_png("user://dojo.png")
	print("DOJO -> %s" % ProjectSettings.globalize_path("user://dojo.png"))
	quit(0)
