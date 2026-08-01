# Render THE FRIENDLY-FIRE READ so it can be LOOKED at. GUI binary only — a
# `--headless` run has a dummy renderer and saves a blank frame:
#
#   python python-tools/run_capture.py friendly_fire
#
# ⚠ THE THING BEING PHOTOGRAPHED IS AN ABSENCE THAT WAS FILLED. Friendly fire is
# this game's stated social engine and it shipped with NO acknowledgement: none of
# `Bark`'s 14 event categories covers hitting a teammate, damage numbers are the
# same colour whoever dealt them, and there was no distinct sound. So deleting your
# friend with the Void rendered exactly like a stray enemy hit — and comedy needs
# attribution, or it is just a bug report.
#
# Frame 1 — `user://friendly_fire_before.png`
#     Two heroes, nothing happening. The control shot: this is what a friendly hit
#     used to look like.
# Frame 2 — `user://friendly_fire_read.png`
#     The read. Gold "FRIENDLY FIRE −34" toast, a gold burst on the victim, and a
#     line over each figure's head — the attacker owning it, the victim objecting.
#     THE TEST: at a glance, can you tell that your friend did that?
extends SceneTree

const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"
const GROUND_Y: float = 300.0
const STAGE_SIZE: Vector2 = Vector2(960.0, 480.0)

var _a: Node2D = null
var _b: Node2D = null


func _initialize() -> void:
	_run()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var stage := Node2D.new()
	stage.name = "FFStage"
	root.add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color(0.19, 0.20, 0.26)
	bg.size = STAGE_SIZE
	bg.z_index = -100
	stage.add_child(bg)
	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.12, 0.13, 0.18)
	floor_rect.position = Vector2(0.0, GROUND_Y + 12.0)
	floor_rect.size = Vector2(STAGE_SIZE.x, 160.0)
	stage.add_child(floor_rect)
	var cam := Camera2D.new()
	# Framed on the FIGURES, not on the middle of the room: the bubbles sit above their
	# heads and the burst on the victim, so a camera parked at room-centre crops exactly
	# the half of the read being reviewed.
	cam.position = Vector2(430.0, 300.0)
	cam.zoom = Vector2(1.7, 1.7)
	stage.add_child(cam)
	cam.make_current()

	var hero: PackedScene = load(HERO_SCENE) as PackedScene
	_a = hero.instantiate() as Node2D       # the one who fired
	_b = hero.instantiate() as Node2D       # the one who got hit
	stage.add_child(_a)
	stage.add_child(_b)
	await _settle(24)

	await _shot("friendly_fire_before", "the control: two heroes, no read at all")

	# The read, fired exactly the way `Net.deal_damage` fires it in a live session.
	FriendlyFire.report(_b, _a, 34)
	await _settle(14)
	await _shot("friendly_fire_read", "gold toast + burst on the victim + a line over each head")
	quit(0)


## Both bodies are CharacterBody2Ds under real physics, so they are re-parked every
## frame or they drift out of the shot mid-capture.
func _settle(frames: int) -> void:
	for i: int in frames:
		if is_instance_valid(_a):
			_a.global_position = Vector2(360.0, GROUND_Y)
		if is_instance_valid(_b):
			_b.global_position = Vector2(500.0, GROUND_Y)
		await process_frame


func _shot(shot_name: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("friendly_fire_capture: no frame for %s" % shot_name)
		return
	var path: String = "user://%s.png" % shot_name
	img.save_png(path)
	print("friendly_fire_capture: %s -> %s (%s)" % [
		shot_name, ProjectSettings.globalize_path(path), what])
