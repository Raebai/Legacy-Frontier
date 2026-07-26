# Throwaway visual check for the SPELL AUDIT sandbox. GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/spell_sandbox_capture.gd
# Saves user://spell_*.png — a few representative spells hitting the cover + dummies.
extends SceneTree

var _scene: Node


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellSandbox.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	for i in 40:
		await physics_frame                 # let _ready build + dummies settle
	# (name, spell index, frames to wait for the spectacle to land)
	var shots := [
		["spell_beam", 0, 45],              # Zoltraak beam
		["spell_ray", 7, 55],               # Judgment divine ray
		["spell_meteor", 11, 80],           # Meteor Sigil bombardment
		["spell_convergence", 10, 90],      # Heaven's Verdict
		["spell_boulder", 16, 55],          # Boulder Hurl
		["spell_pillar", 9, 55],            # Rock Pillar
	]
	for shot in shots:
		_scene.call("_reset_arena")
		for i in 24:
			await physics_frame
		_scene.set("_idx", int(shot[1]))
		_scene.call("_update_hud")
		_scene.call("_cast")
		for i in int(shot[2]):
			await physics_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if img != null:
			img.save_png("user://%s.png" % shot[0])
			print("spellcap saved ", shot[0], ".png")
	quit(0)
