# Visual verification for HOLLOW PURPLE — the four beats, rendered (agent-owned;
# safe to delete). Modelled on tools/melee_agent_capture.gd. GUI binary required:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/hollow_purple_capture.gd
#
# Two beams are fired from the LEFT at +-30 degrees so they cross in front of the
# camera and their angle BISECTOR points right — the annihilation lance then runs
# across the frame instead of straight off the top of it.
#
# Hit-stop is disabled for the run so the beat timeline maps cleanly onto frame
# counts; everything else is the real spectacle.
extends SceneTree

const BEAM := "res://scripts/combat/BeamSpell.gd"
const FLOOR_Y := 300.0

## Both beams start on the LEFT and converge on CROSS; the bisector is (1, 0),
## so the lance runs right across the frame.
const CROSS := Vector2(0.0, 60.0)
const ORIGIN_LOW := Vector2(-520.0, 320.0)
const ORIGIN_HIGH := Vector2(-520.0, -200.0)

## Beat boundaries in physics frames after the cast, at 120 Hz with hit-stop off:
## charge ends at 41 and the reactor resolves within 4, so the circle opens at
## ~45; INTAKE ~45-117, HELD ~117-139, DISCHARGE ~139-249.
## [label, element A, element B, [[cumulative physics frame after cast, stage], ...]]
const RUNS: Array = [
	["fireice", Elements.Element.FIRE, Elements.Element.ICE, [
		[24, "1_charge"],
		[43, "2_live"],
		[52, "3a_circle_opens"],
		[68, "3b_caught"],
		[80, "3c_vortex_a"],
		[92, "3d_vortex_b"],
		[104, "3e_vortex_c"],
		[114, "3f_vortex_d"],
		[128, "4_held"],
		[145, "5_discharge"],
		[162, "6_lance"],
		[230, "7_aftermath"],
	]],
	# A different opposing pair = a different computed purple, from the same row.
	["shadowholy", Elements.Element.SHADOW, Elements.Element.HOLY, [
		[92, "3d_vortex_b"],
		[128, "4_held"],
		[145, "5_discharge"],
		[162, "6_lance"],
	]],
	["arcanewind", Elements.Element.ARCANE, Elements.Element.WIND, [
		[92, "3d_vortex_b"],
		[162, "6_lance"],
	]],
]


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_run()


func _run() -> void:
	await physics_frame  # the tree has to be live before /root lookups work
	# Hit-stop would stretch the beat timeline against the frame counter; the
	# spectacle itself is untouched.
	var tuning: Node = root.get_node_or_null(^"/root/Tuning")
	if tuning != null and tuning.get(&"cfg") != null:
		tuning.cfg.set(&"hit_stop_enabled", false)
	for entry: Array in RUNS:
		var label: String = entry[0]
		var ea: int = entry[1]
		var eb: int = entry[2]
		var stages: Array = entry[3]
		var scene: Node = _build_arena()
		root.add_child(scene)
		for i in 20:
			await physics_frame
		_fire(scene, ORIGIN_LOW, (CROSS - ORIGIN_LOW), ea)
		_fire(scene, ORIGIN_HIGH, (CROSS - ORIGIN_HIGH), eb)
		var done: int = 0
		for stage: Array in stages:
			while done < int(stage[0]):
				await physics_frame
				done += 1
			await _save("hp_%s_%s.png" % [label, stage[1]])
		scene.queue_free()
		await physics_frame
	quit(0)


## A bare arena: the bloom pass, the screen grade, a floor and a few blocks for
## scale, and a static camera parked on the crossing.
##
## Deliberately NOT the SpellPlayground — that scene pulls in scripts/spike,
## which another agent is editing, and a capture tool that cannot render because
## somebody else's file is mid-edit is a capture tool that stops being used.
## Everything the spectacle actually needs (glow + post-process) is set up here.
func _build_arena() -> Node2D:
	RenderingServer.set_default_clear_color(Color(0.13, 0.14, 0.18))
	var arena := Node2D.new()
	Atmosphere.add_glow(arena)     # 2D bloom, so the HDR cores actually radiate
	PostProcess.add(arena)         # the reactive grade, so the shock ripple shows
	_rect(arena, Vector2(0.0, FLOOR_Y + 60.0), Vector2(2400.0, 120.0), Color(0.20, 0.22, 0.27))
	for x: float in [-420.0, -140.0, 180.0, 470.0]:
		_rect(arena, Vector2(x, FLOOR_Y - 34.0), Vector2(68.0, 68.0), Color(0.26, 0.28, 0.34))
	var cam := Camera2D.new()
	cam.position = CROSS
	cam.zoom = Vector2(0.62, 0.62)
	arena.add_child(cam)
	cam.make_current()
	return arena


func _rect(parent: Node, at: Vector2, size: Vector2, col: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5), Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5), Vector2(-size.x * 0.5, size.y * 0.5)])
	p.color = col
	p.position = at
	p.z_index = -5
	parent.add_child(p)


func _fire(arena: Node, origin: Vector2, dir: Vector2, element: int) -> void:
	var beam: Node2D = (load(BEAM) as GDScript).new()
	arena.add_child(beam)
	beam.set("element_id", element)
	beam.call("fire", origin, dir.normalized(), Elements.color(element),
		1100.0, 30.0, 46, Elements.effect_name(element))


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("hpcap saved ", fname)
