# Throwaway visual check for the FIVE BEAM SKINS (beam-agent-owned; named
# uniquely so parallel agents' capture scripts can't collide). GUI binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/beam_agent_capture.gd
# Casts each beam from the playground figure at a spread of angles, captures a
# PNG mid-fire (~0.44s after cast: charge 0.34 + 0.10 into the held beam), then
# lets the beam fully die before the next cast so shots don't overlap.
# Framing: the HUD label is hidden and each SpellDef's runtime `length` is
# shortened (in-memory data only — no file edits) so the WHOLE beam including
# its tip is judgeable in one 1280x720 frame.
extends SceneTree

var _scene: Node

const CAPTURE_LENGTH: float = 480.0  # fits origin->tip in frame at any angle

## build_all() order: 0 zoltraak (arcane) / 1 frostpiercer (frost) /
## 2 infernal_lance (fire) / 3 umbral_lance (shadow) / 4 tempest (lightning).
## Angles fan the beams out so lingering decals/particles from the previous
## shot sit off the new beam's lane.
const SHOTS: Array = [
	[0, "beam_zoltraak.png", 0.3],
	[1, "beam_frostpiercer.png", 2.84],
	[2, "beam_infernal_lance.png", 0.7],
	[3, "beam_umbral_lance.png", 3.5],
	[4, "beam_tempest.png", -0.35],
]


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	for i in 70:
		await physics_frame                      # settle the figure + dummies
	var hud: Label = _scene.get("_hud")
	if hud != null:
		hud.visible = false                      # clean full-frame beam shots
	var fig: Node = _scene.get("_fig")
	var origin: Vector2 = (fig.get("_torso") as Node2D).global_position
	var spells: Array = _scene.get("_spells")
	for shot: Array in SHOTS:
		var spell: SpellDef = spells[int(shot[0])]
		spell.length = CAPTURE_LENGTH            # runtime-only framing tweak
		var target: Vector2 = origin + Vector2.from_angle(float(shot[2])) * 400.0
		SpellCaster.cast(spell, _scene, origin, target, Color(0.78, 0.84, 1.0), "")
		for i in 53:
			await physics_frame                  # charge (41 ticks) + into full fire
		await _save(String(shot[1]))
		for i in 70:
			await physics_frame                  # let the beam fade fully (0.82s total)
	quit(0)


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("beamcap saved ", fname)
