# Throwaway visual check for the METEOR-family redesign (agent-owned; safe to
# delete). Modelled on tools/spell_playground_capture.gd. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/meteor_agent_capture.gd
# For each of the four bombardment elements it loads a FRESH SpellPlayground
# (so shots never overlap), casts the spell, and saves four stage PNGs:
# telegraph (charge ring + per-impact markers), falling (objects in flight),
# impact (mid-barrage), aftermath (ember pools / standing ice / late hits).
extends SceneTree

## build_all() indices: 11 meteor_sigil (fire), 12 void_barrage (shadow),
## 13 avalanche (earth), 14 frozen_comet (frost).
const CASTS: Array = [
	["fire", 11], ["frost", 14], ["earth", 13], ["shadow", 12],
]
## [cumulative physics frames after cast (120/s), stage name]. Earth falls
## slower (0.82 s), so its mid-air + impact beats sit later than the others.
const STAGES: Dictionary = {
	"fire": [[55, "telegraph"], [100, "falling"], [160, "impact"], [230, "aftermath"]],
	"frost": [[55, "telegraph"], [100, "falling"], [160, "impact"], [230, "aftermath"]],
	"earth": [[55, "telegraph"], [130, "falling"], [175, "impact"], [245, "aftermath"]],
	"shadow": [[55, "telegraph"], [100, "falling"], [160, "impact"], [230, "aftermath"]],
}


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	for entry: Array in CASTS:
		var elem: String = entry[0]
		var scene: Node = (load("res://scenes/spike/SpellPlayground.tscn") as PackedScene).instantiate()
		root.add_child(scene)
		for i in 70:
			await physics_frame                  # settle the figure + dummies
		# Hide the playground help HUD — it covers the top third of every shot.
		# Grabbed AFTER the settle loop: on the very first iteration the scene's
		# _ready (which builds the HUD) hasn't fired yet at add_child time.
		var hud: Label = scene.get("_hud")
		if hud != null:
			hud.visible = false
		var fig: Node = scene.get("_fig")
		var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
		var target := Vector2(90.0, 315.0)       # the cover + dummy cluster
		var spell: SpellDef = scene.get("_spells")[entry[1]]
		SpellCaster.cast(spell, scene, origin, target, Color(1, 1, 1), "")
		var elapsed_frames: int = 0
		for stage: Array in (STAGES[elem] as Array):
			for i in (int(stage[0]) - elapsed_frames):
				await physics_frame
			elapsed_frames = stage[0]
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			if img != null:
				var fname: String = "meteor_%s_%s.png" % [elem, stage[1]]
				img.save_png("user://" + fname)
				print("meteorcap saved ", fname)
		scene.queue_free()
		for i in 5:
			await physics_frame                  # let the old scene fully drop
	quit(0)
