# READ-ONLY PROBE (safe to delete). Stages a Chronostasis over two figures and saves
# frames across the whole freeze, so the stopped-time bubble can be LOOKED AT.
#
#   godot-engine/Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_timestop.gd
#
# ⚠ NO --headless. The bubble is a `hint_screen_texture` shader plate; the dummy
# renderer draws nothing and writes blank PNGs while reporting success. That failure
# looks exactly like a pass, which is the trap this whole pipeline keeps re-learning.
#
# Frames land in %APPDATA%/Godot/app_userdata/Ashpire/timestop/.
extends SceneTree

const VIEW: Vector2i = Vector2i(1280, 720)
## Sampled across the freeze: before, the instant it lands, mid-hold, and the snap.
const SHOTS: Array[float] = [0.30, 0.75, 1.60, 2.60, 3.05, 3.30]

var _dir: String = "user://timestop"
var _t: float = 0.0
var _shot: int = 0
var _spell: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	get_root().set_content_scale_size(VIEW)
	var win: Window = get_root()
	win.size = VIEW
	await process_frame

	var arena := Node2D.new()
	get_root().add_child(arena)

	# A floor and some furniture, so there is a PICTURE to invert. A negative over an
	# empty background proves nothing — the whole claim is that the world stays
	# readable while reading as wrong.
	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.18, 0.17, 0.22)
	floor_rect.size = Vector2(2400, 300)
	floor_rect.position = Vector2(-400, 420)
	arena.add_child(floor_rect)
	for i: int in 7:
		var block := ColorRect.new()
		block.color = Color(0.32, 0.28, 0.38)
		block.size = Vector2(70, 70)
		block.position = Vector2(-200.0 + 220.0 * float(i), 350.0)
		arena.add_child(block)

	var cam := Camera2D.new()
	arena.add_child(cam)
	cam.global_position = Vector2(640, 330)
	cam.make_current()

	# Two figures, one inside the ring and one outside it — the bubble's whole point
	# is that those two are in different worlds for three seconds.
	var inside: Node = _figure(arena, Vector2(560, 400), Color(0.42, 0.72, 1.0))
	var outside: Node = _figure(arena, Vector2(1120, 400), Color(1.0, 0.62, 0.25))
	await process_frame

	var spell: SpellDef = SpellLibrary._spell_by_id().get("chronostasis") as SpellDef
	if spell == null:
		printerr("[timestop] no chronostasis in the library")
		quit(1)
		return
	print("[timestop] radius %.0f  length %.1f" % [spell.radius, spell.length])

	_spell = load("res://scripts/combat/Chronostasis.gd").new()
	_spell.set("target_group", "enemy")
	_spell.set("_target_group", "enemy")
	_spell.set("caster_node", inside)
	arena.add_child(_spell)
	_spell.call("cataclysm", inside, Vector2(560, 400), Vector2(640, 400), spell,
		Color(0.72, 0.92, 1.0), "ice")

	# ⚠ THE SPELL'S OWN CLOCK, NOT A FRAME COUNTER. The first version of this probe
	# advanced `_t` by 1/60 per rendered frame and shot against that — but this scene
	# renders far faster than 60 fps, so "3.32 s" was about one real second and the
	# capture showed a bubble that looked like it had failed to switch off. It had
	# not even reached its payout yet. Exactly the fault `directed_clip_capture`
	# documents ("the engine renders ~190 fps... a third of the clip budget").
	var guard: int = 0
	while _shot < SHOTS.size() and guard < 40000:
		await process_frame
		await RenderingServer.frame_post_draw
		guard += 1
		_t = float(_spell.get("_elapsed")) if is_instance_valid(_spell) else _t + 0.02
		if _t >= SHOTS[_shot]:
			var img: Image = get_root().get_texture().get_image()
			if img != null:
				img.save_png("%s/t%d_%.2fs.png" % [_dir, _shot, _t])
				print("[timestop] shot %d at %.2fs" % [_shot, _t])
			_shot += 1
	print("[timestop] DONE -> %s" % ProjectSettings.globalize_path(_dir))
	quit(0)


## A stick figure in the "enemy" group so Chronostasis catches it, with the real rig
## so what is inverted is what the game actually draws.
func _figure(parent: Node2D, at: Vector2, tint: Color) -> Node:
	var body := CharacterBody2D.new()
	body.add_to_group("enemy")
	body.add_to_group("mortal")
	parent.add_child(body)
	body.global_position = at
	var rig := CharacterRig.new()
	rig.name = "Rig"
	body.add_child(rig)
	rig.set("height", 46.0)
	rig.set_tint(tint)
	rig.set_aura(tint, 0.5)
	return body
