# Throwaway visual check for the two NEW delivery shapes — creeping_shade
# (CRAWLER) and rift_dagger (THROWN_ANCHOR). Agent-owned; safe to delete.
# Modelled on tools/melee_agent_capture.gd. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/newshape_agent_capture.gd
# Each entry gets a FRESH SpellPlayground so shots never overlap. A stage named
# "!recall" fires the dagger's SECOND beat instead of saving a frame.
extends SceneTree

## load()ed by path, NEVER by class_name: a tool script is compiled before the
## autoloads exist, and a class_name reference would drag RiftDagger through that
## compile, fail on Sfx, and leave the cached script permanently statics-less.
const DAGGER_PATH: String = "res://scripts/combat/RiftDagger.gd"

## [spell id, tag, aim offset from the caster, camera centre, camera zoom,
## [[cumulative physics frames after the cast (120/s), stage name], ...]].
## The playground camera chases the figure at 0.55 zoom, which is both too wide
## to judge a 7 px trail and useless for a spell whose whole point is the ground
## BETWEEN two places — so each entry pins its own framing instead.
const CASTS: Array = [
	["creeping_shade", "", Vector2(320.0, -10.0), Vector2(150.0, 250.0), 1.5,
		[[10, "launch"], [30, "race"], [46, "approach"], [56, "rear"],
		[66, "strike"], [86, "shred"]]],
	# ZERO offset = aim at the first dummy's actual centre. Hand-picked offsets
	# kept planting the blade in scenery: the throw leaves at torso height and
	# the dummies' centres sit much lower, so anything eyeballed missed by more
	# than the 27 px flight window.
	["rift_dagger", "body", Vector2.ZERO, Vector2(-40.0, 250.0), 1.6,
		[[6, "throw"], [14, "flight"], [34, "stuck"], [100, "anchor"],
		[101, "!recall"], [114, "tell"], [132, "arrival"]]],
	# Up-and-right over both dummies into the far arena wall (~668 px of flight),
	# so the recall is a real cross-arena teleport to a wall-planted blade.
	["rift_dagger", "wall", Vector2(560.0, -364.0), Vector2(230.0, 120.0), 0.78,
		[[10, "throw"], [64, "flight"], [116, "stuck"],
		[117, "!recall"], [130, "tell"], [148, "arrival"]]],
	# THE IDENTITY CHECK: a Rock Wall goes up first, then the shade is sent at it.
	# It must pass UNDER the barrier and still reach the dummy behind it.
	["creeping_shade", "underwall", Vector2(320.0, -10.0), Vector2(150.0, 250.0), 1.5,
		[[24, "at_wall"], [44, "past_wall"], [70, "strike"]], "rock_wall"],
]


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	for entry: Array in CASTS:
		var id: String = entry[0]
		var tag: String = entry[1]
		var aim_off: Vector2 = entry[2]
		var stages: Array = entry[5]
		var scene: Node = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
		root.add_child(scene)
		for i in 70:
			await physics_frame                  # settle the figure + dummies
		var hud: Node = scene.get("_hud")
		if hud is CanvasItem:
			(hud as CanvasItem).visible = false  # it covers the top third of the frame
		# Our own camera, made current, so the controller's chase cam (which it
		# rewrites every _process) can keep doing its thing and be ignored.
		var cam := Camera2D.new()
		scene.add_child(cam)
		cam.position = entry[3] as Vector2
		cam.zoom = Vector2(float(entry[4]), float(entry[4]))
		cam.make_current()
		var fig: Node = scene.get("_fig")
		var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
		var spell: SpellDef = _find(scene.get("_spells"), id)
		if spell == null:
			print("newcap: NO SUCH SPELL ", id)
			scene.queue_free()
			continue
		var target: Vector2 = origin + aim_off
		if aim_off == Vector2.ZERO:
			target = (scene.get("_dummies")[0] as Node2D).global_position
		# Optional 7th field: a spell cast (and allowed to finish rising) BEFORE
		# the one under review, so an interaction can be shot in one frame.
		if entry.size() > 6:
			var pre: SpellDef = _find(scene.get("_spells"), String(entry[6]))
			if pre != null:
				SpellCaster.cast(pre, scene, origin, target, Color(0.78, 0.84, 1.0), "", fig)
				for i in 60:
					await physics_frame
		SpellCaster.cast(spell, scene, origin, target,
			Color(0.78, 0.84, 1.0), "", fig)
		var done: int = 0
		for stage: Array in stages:
			while done < int(stage[0]):
				await physics_frame
				done += 1
			var stage_name: String = String(stage[1])
			if stage_name.begins_with("!"):
				(load(DAGGER_PATH) as GDScript).try_recall(scene.get_tree(), fig)
				continue
			var prefix: String = id if tag == "" else "%s_%s" % [id, tag]
			await _save("new_%s_%s.png" % [prefix, stage_name])
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
		print("newcap saved ", fname)
