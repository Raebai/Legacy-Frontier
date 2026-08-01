# Render GHOST FORM and the REVIVE prompt so they can be LOOKED at instead of
# reasoned about. Every visual number in `GhostForm` and `Revive` is reasoning, and
# the one requirement that cannot be reasoned about is "it must read instantly at
# 640x360 on a phone". GUI binary only — a `--headless` run has a dummy renderer and
# saves a blank frame:
#
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/ghost_revive_capture.gd
#
# ⚠ A BESPOKE STAGE, NOT `VersusArena`. The first version of this tool captured the
# duel scene and the frames were unreadable: a bot mid-ULT put a full-screen beam
# across the shot, and the thing being photographed was a 40-px stickman behind it.
# A capture whose subject is 3% of the frame proves nothing. So this builds the
# smallest scene that can contain the mechanic — a flat floor, two real `Hero.tscn`
# bodies, one camera — and nothing else moves.
#
# Frame 1 — `user://ghost_form.png`
#     One hero alive, one a GHOST. THE READ TEST: at a glance, which one is dead?
#     The broken chalk ring is the primary signal; the eraser smudge and the rising
#     graphite motes are what make it chalk-and-graphite rather than a blue ghost.
# Frame 2 — `user://ghost_revive_prompt.png`
#     The rescuer has walked into `Revive.RANGE`: prompt, tether, empty ring. The
#     "can I tell what to press" test.
# Frame 3 — `user://ghost_revive_channel.png`
#     Mid-channel: the ring filling on the ghost and the HOLD bar on the touch pad.
#     The "does holding feel like it is doing something" test.
# Frame 4 — `user://ghost_haunt.png`
#     The HAUNT gust — the one verb a dead player has, and the reason being downed is
#     not 40 seconds of watching.
# Frame 5 — `user://ghost_revived.png`
#     The instant after: the "UP!" bloom and a body back in the fight.
extends SceneTree

## Inside `Revive.RANGE` (92), far enough apart that both rigs read separately.
const NEAR: Vector2 = Vector2(74.0, -24.0)
## Well outside it — frame 1 is the ghost with no prompt clutter, but both bodies
## still in shot, because the read being tested is "which of these two is dead".
const FAR: Vector2 = Vector2(190.0, -34.0)
const GROUND_Y: float = 300.0
const RESCUER_X: float = 400.0
const STAGE_SIZE: Vector2 = Vector2(960.0, 480.0)

var _revive: Revive = null
var _rescuer: Node2D = null
var _ghost: Node2D = null
## Where the ghost is pinned this beat. Both bodies are re-parked EVERY frame: one is
## a CharacterBody2D under real physics and the other is drifting with no gravity, so
## left alone they wander out of the shot mid-capture.
var _ghost_offset: Vector2 = FAR


func _initialize() -> void:
	_run(_build_stage())


## The smallest scene that can hold two heroes: a backdrop, a floor collider so the
## LIVING one stands rather than falls forever, and a camera framing both.
func _build_stage() -> Node2D:
	var stage := Node2D.new()
	stage.name = "GhostStage"
	root.add_child(stage)

	var bg := ColorRect.new()
	bg.color = Color(0.30, 0.31, 0.40)
	bg.size = STAGE_SIZE
	bg.z_index = -100
	stage.add_child(bg)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.17, 0.18, 0.24)
	floor_rect.position = Vector2(0.0, GROUND_Y + 12.0)
	floor_rect.size = Vector2(STAGE_SIZE.x, STAGE_SIZE.y - GROUND_Y)
	floor_rect.z_index = -90
	stage.add_child(floor_rect)

	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(STAGE_SIZE.x, 40.0)
	shape.shape = rect
	shape.position = Vector2(STAGE_SIZE.x * 0.5, GROUND_Y + 32.0)
	body.add_child(shape)
	stage.add_child(body)

	var hero_scene: PackedScene = load("res://scenes/combat/Hero.tscn") as PackedScene
	_rescuer = hero_scene.instantiate() as Node2D
	_rescuer.position = Vector2(RESCUER_X, GROUND_Y)
	stage.add_child(_rescuer)
	_ghost = hero_scene.instantiate() as Node2D
	_ghost.position = Vector2(RESCUER_X, GROUND_Y) + FAR
	stage.add_child(_ghost)

	# `Hero.tscn` carries its own Camera2D, and two of them fight over the viewport.
	# Kill both and drive one framing camera from here.
	for h: Node2D in [_rescuer, _ghost]:
		var cam: Node = h.get_node_or_null(^"Camera2D")
		if cam != null:
			cam.queue_free()
	var view := Camera2D.new()
	view.position = Vector2(RESCUER_X + 95.0, GROUND_Y - 44.0)
	view.zoom = Vector2(2.6, 2.6)
	stage.add_child(view)
	view.make_current()

	# The mechanic itself, parked exactly as `Arena._ready` parks it, with the phone pad
	# forced on so a thumb's view is in the frame on a desktop capture too.
	#
	# ⚠ `TouchControls` IS DELIBERATELY ABSENT. Adding it put six thumb pads across the
	# lower half of the shot and one of them landed exactly on the ghost — a capture
	# whose subject is hidden behind unrelated UI proves nothing. The revive pad is the
	# only touch affordance this task owns, so it is the only one photographed.
	_revive = Revive.new()
	_revive.force_pad = true
	stage.add_child(_revive)
	return stage


func _run(_stage: Node2D) -> void:
	await _settle(30)

	# ── 1. THE READ TEST: two bodies, one dead. Which one, at a glance? ─────────
	_ghost_offset = FAR
	# Zero the hp before going down. `_enter_downed` is called directly (routing real
	# damage through `take_damage` would hit the sandbox reset, because this stage has
	# no active run), and a ghost floating under a FULL health bar is a lie the capture
	# would be telling about the mechanic.
	_ghost.set(&"hp", 0)
	_ghost.emit_signal("health_changed", 0, int(_ghost.get(&"max_hp")))
	_ghost.call(&"_enter_downed")
	await _settle(40)
	await _shot("ghost_form", "GHOST FORM: broken chalk ring + eraser smudge + graphite motes")

	# ── 2. the prompt ─────────────────────────────────────────────────
	_ghost_offset = NEAR
	await _settle(20)
	await _shot("ghost_revive_prompt", "in range: [E] REVIVE, the tether, the empty ring")

	# ── 3. mid-channel ──────────────────────────────────────────────
	# Driven by holding the REAL action, not by writing `_progress`: the point is the
	# path a thumb takes, and a hand-set field would render a state the game cannot be in.
	Input.action_press(Revive.REVIVE_ACTION)
	var target: float = Revive.CHANNEL_TIME * 0.6
	var guard: int = 0
	while _revive._progress < target and guard < 600:
		guard += 1
		await _settle(1)
	await _shot("ghost_revive_channel", "channelling ~60%: ring filling + pad HOLD bar")
	Input.action_release(Revive.REVIVE_ACTION)

	# ── 4. HAUNT — the ghost's one verb ─────────────────────────────────
	_ghost.call(&"_ghost_haunt")
	await _settle(7)
	await _shot("ghost_haunt", "HAUNT: the chalk gust that shoves enemies off your rescuer")

	# ── 5. the comeback ────────────────────────────────────────────
	Revive.apply(_ghost)
	await _settle(5)
	await _shot("ghost_revived", "UP!: the bloom, the chalk gone, a body back in the fight")
	quit(0)


## Advance `frames` frames, re-pinning both bodies each one. One is a CharacterBody2D
## under real physics and the other is drifting with no gravity, so left alone they
## wander out of the shot part-way through a capture.
func _settle(frames: int) -> void:
	for i: int in frames:
		_rescuer.global_position = Vector2(RESCUER_X, GROUND_Y)
		_ghost.global_position = Vector2(RESCUER_X, GROUND_Y) + _ghost_offset
		await process_frame


func _shot(shot_name: String, what: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("ghost_revive_capture: no frame for %s" % shot_name)
		return
	var path: String = "user://%s.png" % shot_name
	img.save_png(path)
	print("ghost_revive_capture: %s -> %s (%s)" % [
		shot_name, ProjectSettings.globalize_path(path), what])
