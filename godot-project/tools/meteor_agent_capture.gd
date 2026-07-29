# Throwaway visual check for the METEOR-family redesign (agent-owned; safe to
# delete). Modelled on tools/spell_playground_capture.gd. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/meteor_agent_capture.gd
# For each bombardment element it loads a FRESH SpellPlayground (so shots never
# overlap), casts the spell, and saves four stage PNGs: telegraph (charge ring +
# per-impact markers), falling (objects in flight), impact (mid-barrage),
# aftermath (ember pools / late hits).
#
# ⚠ FROST IS NOT CAPTURED HERE ANY MORE, and this file used to lie about that.
# `frozen_comet` was forked out of the METEOR spectacle into IceSpikeLine — a
# ground crest that rises along the aim, not a bombardment. It has no "falling"
# beat and no per-impact markers, so three of the four stage names below were
# meaningless for it while it still shot four PNGs claiming otherwise. It is now
# simply not in CASTS; use tools/ice_spike_agent_capture.gd for that spell. The
# three real bombardments are unaffected.
#
# Spells are looked up BY ID, not by index into build_all(). The previous version
# hard-coded "11 = meteor_sigil, 12 = void_barrage, ...", which is one insertion
# into the middle of the library away from silently capturing the wrong spell and
# filing the PNGs under the right name — a stale-by-default scheme for a tool
# whose entire job is to show you what a spell looks like.
extends SceneTree

## [spell id, element key used for the stage table + filenames].
const CASTS: Array = [
	["meteor_sigil", "fire"], ["avalanche", "earth"], ["void_barrage", "shadow"],
]
## [cumulative physics frames after cast (120/s), stage name]. Earth falls
## slower (0.82 s), so its mid-air + impact beats sit later than the others.
const STAGES: Dictionary = {
	"fire": [[55, "telegraph"], [100, "falling"], [160, "impact"], [230, "aftermath"]],
	"earth": [[55, "telegraph"], [130, "falling"], [175, "impact"], [245, "aftermath"]],
	"shadow": [[55, "telegraph"], [100, "falling"], [160, "impact"], [230, "aftermath"]],
}


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


## The spell with `id` out of the playground's list, or null. Loud on a miss: a
## capture tool that silently skips the spell you asked for is worse than one that
## stops, because you only find out by staring at PNGs that never changed.
func _find_spell(spells: Array, id: String) -> SpellDef:
	for s: SpellDef in spells:
		if s != null and s.id == id:
			return s
	printerr("meteorcap: no spell with id '%s' in the playground library" % id)
	return null


func _run() -> void:
	for entry: Array in CASTS:
		var spell_id: String = entry[0]
		var elem: String = entry[1]
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
		var spell: SpellDef = _find_spell(scene.get("_spells") as Array, spell_id)
		if spell == null:
			scene.queue_free()
			continue
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
