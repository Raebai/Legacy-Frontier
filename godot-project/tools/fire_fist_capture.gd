# Throwaway visual check for the organic flaming fist (item 3). Run with the GUI
# binary: Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/fire_fist_capture.gd
# Saves user://fire_fist.png — three big rigs: idle+flaming-fist, punch+flaming-fist,
# and a fire cast-gesture, so the new _draw_flame look is visible.
extends SceneTree

const OUT_PATH: String = "user://fire_fist.png"


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.14)
	bg.size = Vector2(960, 540)
	root.add_child(bg)
	var holder := Node2D.new()
	root.add_child(holder)

	var r1 := CharacterRig.new()
	r1.height = 150.0
	r1.position = Vector2(200, 340)
	r1.limb_color = Color(0.4, 0.7, 1.0)
	holder.add_child(r1)
	r1.set_aim_arm(true)
	r1.set_aim(Vector2(1, -0.4))
	r1.set_hand_fire(1.0, Elements.Element.FIRE)
	r1.play(CharacterRig.State.IDLE)

	var r2 := CharacterRig.new()
	r2.height = 150.0
	r2.position = Vector2(500, 340)
	r2.limb_color = Color(1.0, 0.55, 0.35)
	holder.add_child(r2)
	r2.set_hand_fire(1.0, Elements.Element.FIRE)
	r2.play(CharacterRig.State.PUNCH)

	var r3 := CharacterRig.new()
	r3.height = 150.0
	r3.position = Vector2(780, 340)
	r3.limb_color = Color(0.6, 0.4, 0.95)
	holder.add_child(r3)
	r3.set_aim(Vector2(1, -0.5))
	r3.play(CharacterRig.State.CAST)
	r3.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 1.0, Elements.Element.FIRE)
	_capture()


func _capture() -> void:
	# Advance the rigs a few frames so the sim + flame phase animate to a lively frame.
	for i: int in 40:
		for rig: Node in root.get_children():
			if rig is Node2D:
				for c: Node in rig.get_children():
					if c is CharacterRig:
						(c as CharacterRig).advance(0.03)
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_PATH)
		print("fire_fist_capture: saved ", ProjectSettings.globalize_path(OUT_PATH))
	quit(0)
