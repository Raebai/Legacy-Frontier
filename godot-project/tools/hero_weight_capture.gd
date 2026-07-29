# THE IN-GAME PROOF — the same weight test, but on a REAL Hero in the REAL arena.
#
# MUST run with the GUI (non-headless) binary:
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/hero_weight_capture.gd
# Output: user://heroweight_00.png .. user://heroweight_05.png
#
# tools/rig_ragdoll_capture.gd drives a BARE CharacterRig, which isolates the springs
# but proves nothing about the shipped game: the rig there is not parented to a
# CharacterBody2D, is not fed by Hero.gd, and nothing is reading its silhouette. This
# one instantiates Hero.tscn into VersusArena, drops it from a height, then hits it —
# and logs the rig's ride/pitch alongside the hero's own velocity so the numbers can be
# checked against the picture rather than trusted.
#
# It also prints the head-silhouette offset every frame, because that is the regression
# that matters most: if the drawn head and the hit silhouette ever disagree, "spells
# pass through heads" is back. Here they are the same transform by construction, and
# the log makes that visible rather than assumed.
extends SceneTree

const ARENA: String = "res://scenes/combat/VersusArena.tscn"
const HERO: String = "res://scenes/combat/Hero.tscn"
## Shots are taken RELATIVE TO TOUCHDOWN, not on absolute frame numbers. The first
## draft used absolute frames and sampled straight past the landing — the squash is
## ~10 frames long and the hero's own gravity decides when it starts, so the only
## reliable trigger is the hero itself reporting is_on_floor(). Frame -1 is the last
## airborne frame; 0 is contact; 2/5/9 walk out the recovery.
const LAND_SHOTS: Array[int] = [0, 2, 5, 9]
## ...then the hit, counted from the blow.
const HIT_FRAME: int = 40
const HIT_SHOTS: Array[int] = [2, 8, 30]

var _hero: CharacterBody2D = null
var _rig: CharacterRig = null
var _shot: int = 0
var _land_step: int = -1     # frame is_on_floor() first went true
var _prev_air: bool = true


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	var arena: Node = (load(ARENA) as PackedScene).instantiate()
	root.add_child(arena)
	_run(arena)


func _run(arena: Node) -> void:
	await physics_frame
	await physics_frame
	# Use whatever hero the arena already spawned if there is one; otherwise add ours.
	var heroes: Array[Node] = root.get_tree().get_nodes_in_group("hero")
	if heroes.is_empty():
		_hero = (load(HERO) as PackedScene).instantiate() as CharacterBody2D
		arena.add_child(_hero)
	else:
		_hero = heroes[0] as CharacterBody2D
	_rig = _hero.get_node_or_null(^"Rig") as CharacterRig
	if _rig == null:
		printerr("hero_weight_capture: no Rig under the hero — nothing to measure")
		quit(1)
		return
	# Lift it well clear of the floor so the fall is a real one, and let the hero's own
	# gravity + move_and_slide bring it down. Nothing here fakes the drop.
	_hero.global_position += Vector2(0.0, -170.0)
	_hero.velocity = Vector2.ZERO

	var hit_at: int = -1
	for step: int in 140:
		# A real blow, through the same public entry points combat uses — fired once the
		# landing has fully settled so the two events never overlap in a frame.
		if _land_step >= 0 and hit_at < 0 and step >= _land_step + HIT_FRAME:
			hit_at = step
			_rig.play(CharacterRig.State.HURT)
			_rig.apply_impulse(Vector2(1.0, -0.2).normalized(), 900.0)
			_rig.flop(0.85, 0.5)
		await physics_frame
		# Touchdown detection, from the hero's own body rather than a guessed frame.
		var air: bool = not _hero.is_on_floor()
		if _prev_air and not air and _land_step < 0:
			_land_step = step
		_prev_air = air
		# Is this frame one we want? Two independent schedules, both relative to an
		# event the SIMULATION decides, never to a guessed absolute frame.
		var want: bool = false
		var tag: String = ""
		# The "still in the air" reference shot: taken once, while genuinely falling.
		if _land_step < 0 and air and _hero.velocity.y > 200.0 and _shot == 0:
			want = true
			tag = "falling"
		if _land_step >= 0:
			for d: int in LAND_SHOTS:
				if d >= 0 and step == _land_step + d:
					want = true
					tag = "land+%d" % d
		if hit_at >= 0:
			for d: int in HIT_SHOTS:
				if step == hit_at + d:
					want = true
					tag = "hit+%d" % d
		if want and _shot < 9:
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			var path: String = "user://heroweight_%02d_%s.png" % [_shot, tag]
			if img != null:
				img.save_png(path)
			# The head silhouette, computed the way Enemy._silhouette does it — analytic
			# local point pushed through the rig's global transform. Its offset from the
			# hero's own origin is the number that must MOVE with the squash and the lean.
			var head_local := Vector2(0.0, -_rig.height * 0.5 + _rig.height * 0.105)
			var head_w: Vector2 = _rig.global_transform * head_local
			var off: Vector2 = head_w - _hero.global_position
			print(("hero_weight: step %3d  vel.y=%7.1f  floor=%s  ride=%6.2f  pitch=%6.3f"
				+ "  head_off=(%6.2f,%6.2f)  -> %s")
				% [step, _hero.velocity.y, str(_hero.is_on_floor()),
					_rig.body_ride(), _rig.body_pitch(), off.x, off.y,
					ProjectSettings.globalize_path(path)])
			_shot += 1
	print("hero_weight_capture: done")
	quit(0)
