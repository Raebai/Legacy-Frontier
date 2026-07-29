# Visual check for the reworked DRAIN TETHER. GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/drain_tether_capture.gd
# Saves four PNGs to user:// — one per beat of the spell, because the whole point
# of the rework is that the spell HAS beats now:
#   drain_tether_1_coil.png   the telegraph (dashed lance + coiling whip)
#   drain_tether_2_lash.png   the hook mid-flight (the thing you dodge)
#   drain_tether_3_bite.png   the catch
#   drain_tether_4_strain.png the victim dragging the barb toward the break ring
#
# The dummies are plain Node2D + ColorRect rather than CharacterRig, so this tool
# keeps rendering while other agents are mid-edit in the rig — a visual check that
# can be blocked by an unrelated file is a visual check you stop running.
#
# ⚠ DrainTether is load()ed, never named as a class: a --script tool compiles
# before the autoloads exist and the spell calls Sfx (see slice6_test_drain_tether).
extends SceneTree

const TETHER_PATH: String = "res://scripts/combat/DrainTether.gd"
## Composed inside the 640x360 design canvas — anything past it is off-screen.
const HAND := Vector2(96.0, 190.0)
const VICTIM := Vector2(330.0, 190.0)

var _arena: Node2D = null
var _whip: Node2D = null
var _victim: Node2D = null
var _shot: int = 0


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.size = Vector2(1400, 800)
	root.add_child(bg)
	_arena = Node2D.new()
	root.add_child(_arena)
	_victim = _dummy(VICTIM, Color(0.5, 0.85, 0.55))
	_dummy(Vector2(210.0, 120.0), Color(0.45, 0.55, 0.85))  # a body OFF the aim line —
	_dummy(Vector2(430.0, 262.0), Color(0.45, 0.55, 0.85))  # proof the whip does not bend
	_run()


## A stand-in body: a Node2D (what the selectors read) with a visible slab under it.
func _dummy(at: Vector2, col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_to_group("enemy")
	_arena.add_child(n)
	n.global_position = at
	var r := ColorRect.new()
	r.color = col
	r.size = Vector2(12.0, 30.0)
	r.position = Vector2(-6.0, -15.0)
	n.add_child(r)
	return n


func _run() -> void:
	await process_frame
	_whip = (load(TETHER_PATH) as GDScript).new()
	_arena.add_child(_whip)
	_whip.set("element_id", Elements.Element.SHADOW)
	_whip.call("tether", HAND, Vector2.RIGHT, Elements.color(Elements.Element.SHADOW), 11, "shadow")
	var windup: float = float((load(TETHER_PATH) as GDScript).get_script_constant_map()["WINDUP"])
	var pull: float = float((load(TETHER_PATH) as GDScript).get_script_constant_map()["BREAK_PULL"])
	var frames: int = 0
	while frames < 400 and is_instance_valid(_whip):
		await process_frame
		frames += 1
		var state: int = int(_whip.get("_state"))
		var t: float = float(_whip.get("_t"))
		# 0 = COIL, 1 = LASH, 2 = DRAIN (see DrainTether.State).
		if _shot == 0 and state == 0 and t > windup * 0.6:
			await _save("drain_tether_1_coil.png")
		elif _shot == 1 and state == 1 and t > 0.09:
			await _save("drain_tether_2_lash.png")
		elif _shot == 2 and state == 2 and t > 0.24:
			# Deliberately AFTER the shared impact frame has faded: at t≈0 the
			# Juice flash whites out the screen (working as designed) and the maw
			# cannot be inspected under it.
			await _save("drain_tether_3_bite.png")
		elif _shot == 3 and state == 2:
			# Drag the victim toward the break so the strain read + break ring are
			# on screen at the moment the shot is taken.
			_victim.global_position.x = VICTIM.x + pull * 0.78
			if t > 0.45:
				await _save("drain_tether_4_strain.png")
				break
	quit(0)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("drain_tether_capture: saved ", fname)
	_shot += 1
