# Gear capture: render a row of stick-figure rigs, each with a class_preset, so the
# PixelLab equipment overlays (hat/hood/staff/sword/hammer/scythe/orb) are visible
# ON the sticks. MUST run with the GUI (non-headless) binary — dummy renders black:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/gear_capture.gd
# Output: user://gear.png
extends SceneTree

const CLASSES: Array = ["mage", "rogue", "warlock", "juggernaut", "summoner", "cleric"]
const TINTS: Array = [
	Color(0.55, 0.75, 1.0), Color(0.8, 0.85, 0.9), Color(0.7, 0.45, 1.0),
	Color(1.0, 0.7, 0.35), Color(0.4, 0.9, 0.6), Color(1.0, 0.95, 0.7),
]


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.14, 0.15, 0.19)
	bg.size = Vector2(760, 400)
	root.add_child(bg)
	var rig_script: GDScript = load("res://scripts/combat/CharacterRig.gd")
	var x: float = 90.0
	for i: int in CLASSES.size():
		var rig: Node2D = rig_script.new()
		rig.set("height", 74.0)
		root.add_child(rig)
		rig.position = Vector2(x, 250.0)
		if rig.has_method("set_tint"):
			rig.call("set_tint", TINTS[i])
		rig.call("class_preset", CLASSES[i])
		rig.call("play", 0)  # State.IDLE
		var label := Label.new()
		label.text = CLASSES[i]
		label.position = Vector2(x - 30.0, 300.0)
		root.add_child(label)
		x += 115.0
	_run()


func _run() -> void:
	for i: int in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://gear.png")
		print("gear_capture: saved ", ProjectSettings.globalize_path("user://gear.png"))
	quit(0)
