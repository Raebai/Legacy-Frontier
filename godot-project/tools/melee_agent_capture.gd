# Throwaway visual check for the three spells the Phase-2 sweep has not judged
# yet — blade_flurry, boulder_hurl, heavens_verdict (agent-owned; safe to
# delete). Modelled on tools/meteor_agent_capture.gd. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/melee_agent_capture.gd
# Each spell gets a FRESH SpellPlayground (so shots never overlap) and is cast
# toward the dummy on the right, saving stage PNGs across its timeline.
extends SceneTree

## [spell id, aim offset from the caster, [[cumulative physics frames after cast
## (120/s), stage name], ...]]
const CASTS: Array = [
	["blade_flurry", Vector2(290.0, -10.0), [[6, "windup"], [22, "slash"], [44, "late"]]],
	# Aimed UP-right over the cover block: flat right, the crate is ~45 px away and
	# the rock detonates within 6 frames, so the mid-air beat is never visible.
	# rise 0.30 + hang 0.12 also means nothing leaves the ground before frame ~50.
	# Nothing leaves the ground before frame ~50 (rise 0.30 + hang 0.12); with a
	# clear lane the rock then runs MAX_FLIGHT 900 px at 900 px/s before it
	# auto-detonates, so the impact beat lands around frame 170.
	["boulder_hurl", Vector2(230.0, -270.0),
		[[28, "rip"], [56, "flight"], [100, "arc"], [172, "impact"]]],
	["heavens_verdict", Vector2(290.0, -10.0),
		[[40, "telegraph"], [110, "converge"], [150, "nova"], [210, "aftermath"]]],
]


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	for entry: Array in CASTS:
		var id: String = entry[0]
		var aim_off: Vector2 = entry[1]
		var stages: Array = entry[2]
		var scene: Node = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
		root.add_child(scene)
		for i in 70:
			await physics_frame                  # settle the figure + dummies
		var fig: Node = scene.get("_fig")
		var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
		var spell: SpellDef = _find(scene.get("_spells"), id)
		if spell == null:
			print("meleecap: NO SUCH SPELL ", id)
			scene.queue_free()
			continue
		SpellCaster.cast(spell, scene, origin, origin + aim_off,
			Color(0.78, 0.84, 1.0), "")
		var done: int = 0
		for stage: Array in stages:
			while done < int(stage[0]):
				await physics_frame
				done += 1
			await _save("melee_%s_%s.png" % [id, stage[1]])
		scene.queue_free()
		await physics_frame
	quit(0)


func _find(spells: Array, id: String) -> SpellDef:
	for s: SpellDef in spells:
		if s.id == id:
			return s
	return null


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("meleecap saved ", fname)
