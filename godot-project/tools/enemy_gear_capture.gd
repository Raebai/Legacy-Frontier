# Enemy gear capture: render the archetype weapons on stick rigs (brute club,
# charger spear, assassin dagger, bomber bomb, caster staff, summoner orb) so the
# roster's PixelLab weapons are verifiable. GUI binary only.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/enemy_gear_capture.gd
extends SceneTree

const KINDS: Array = ["club", "spear", "dagger", "bomb", "staff", "orb"]
const NAMES: Array = ["brute", "charger", "assassin", "bomber", "caster", "summoner"]
const TINTS: Array = [
	Color(0.7, 0.25, 0.45), Color(0.9, 0.6, 0.2), Color(0.82, 0.86, 0.92),
	Color(0.34, 0.35, 0.4), Color(0.55, 0.45, 0.95), Color(0.35, 0.8, 0.55),
]


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.14, 0.15, 0.19)
	bg.size = Vector2(1365, 768)
	root.add_child(bg)
	var rig_script: GDScript = load("res://scripts/combat/CharacterRig.gd")
	var x: float = 110.0
	for i: int in KINDS.size():
		var rig: Node2D = rig_script.new()
		rig.set("height", 74.0)
		root.add_child(rig)
		rig.position = Vector2(x, 250.0)
		if rig.has_method("set_tint"):
			rig.call("set_tint", TINTS[i])
		rig.call("set_equipment", "weapon", KINDS[i])
		rig.call("play", 0)
		var label := Label.new()
		label.text = NAMES[i]
		label.position = Vector2(x - 34.0, 300.0)
		root.add_child(label)
		x += 200.0
	for i: int in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://enemy_gear.png")
		print("enemy_gear_capture: saved ", ProjectSettings.globalize_path("user://enemy_gear.png"))
	quit(0)
