# Visual check for the SHIPPED hero's casting PROCESS (not the spike rig — see
# cast_pose_capture.gd for that one). Renders Hero mid-windup for spells whose
# CastStyle poses differ, so three things can be judged by eye rather than by
# assertion: the body language is per-spell, the sigil hangs ABOVE the caster, and
# the levitation is a flourish rather than a jump.
#
# GUI binary (must render):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/cast_windup_capture.gd
# PNGs land in %APPDATA%/Godot/app_userdata/Legacy Frontier/.
extends SceneTree

## Fraction through each windup to shoot at. Late enough that the lift has eased in
## and the sigil has grown, early enough that the spell has not fired.
const SHOT_FRAC: float = 0.7
## The hero is ~40 px tall in a 1280-wide frame; arm angles and a 6 px lift are
## invisible at default zoom. Push in hard — this is a review shot, not gameplay.
const REVIEW_ZOOM: float = 2.6
const GROUND_Y: float = 120.0

var _arena: Node2D
var _hero: CharacterBody2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	_arena = Node2D.new()
	root.add_child(_arena)
	_build_ground()
	_hero = (load("res://scenes/combat/Hero.tscn") as PackedScene).instantiate()
	_arena.add_child(_hero)
	_hero.global_position = Vector2(0.0, GROUND_Y - 40.0)
	_run()


## A slab under the hero so they land and the rig settles into a GROUNDED idle —
## a windup shot off a falling figure would be judging the fall, not the pose.
func _build_ground() -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1600.0, 60.0)
	shape.shape = rect
	body.add_child(shape)
	_arena.add_child(body)
	body.global_position = Vector2(0.0, GROUND_Y + 30.0)


func _run() -> void:
	for i in 120:
		await physics_frame  # land + settle
	# The hero's own Camera2D carries the TOWER's limits (limit_left = 0 and friends),
	# which shove a review shot into the corner. Use a fresh unlimited camera instead
	# of fighting those — this is a lab shot, not a gameplay view.
	var hero_cam := _hero.get_node_or_null("Camera2D") as Camera2D
	if hero_cam != null:
		hero_cam.enabled = false
	var cam := Camera2D.new()
	_arena.add_child(cam)
	cam.zoom = Vector2(REVIEW_ZOOM, REVIEW_ZOOM)
	cam.global_position = _hero.global_position + Vector2(0.0, -34.0)
	cam.make_current()
	# One spell per DISTINCT body language, so the shots are actually comparable:
	# a wall is slammed out of the ground, a chain flicks off one hand, a zone is a
	# deliberate ritual, a boulder is thrown over the shoulder.
	for row: Array in [
		[SpellDef.Kind.WALL, "slam_wall"],
		[SpellDef.Kind.CHAIN, "lash_chain"],
		[SpellDef.Kind.ZONE, "circle_zone"],
		[SpellDef.Kind.THROWN_ANCHOR, "throw_dagger"],
	]:
		await _shoot_summon(int(row[0]), String(row[1]))
	await _shoot_channel()
	quit(0)


## Drive a real windup through Hero's own physics loop (never _process_summon by
## hand) so the shot shows exactly what the game does — lift, sigil growth and all.
func _shoot_summon(kind: int, label: String) -> void:
	var spell := SpellDef.new()
	spell.kind = kind
	spell.mp_cost = 50
	spell.cooldown = 5.0
	_hero._aim_dir = Vector2.RIGHT
	_hero._begin_summon(spell, false, 0)
	var total: float = float(_hero.get("_summon_total"))
	var frames: int = maxi(2, int(total * SHOT_FRAC * float(Engine.physics_ticks_per_second)))
	for i in frames:
		await physics_frame
	await _save("herocast_%s.png" % label)
	# Abandon the cast rather than letting it fire: the spectacle would cover the
	# body, and the BODY is what is under review here.
	_hero._cancel_summon()
	for i in 60:
		await physics_frame  # settle back to idle before the next one


## The float-channel is the other ceremony, and the one the duplicate-circle bug
## was reported on (a channelled beam). Shot mid-channel: sigil above, hero lifted.
func _shoot_channel() -> void:
	var spell := SpellDef.new()
	spell.kind = SpellDef.Kind.BEAM
	spell.mp_cost = 70
	spell.cooldown = 8.0
	spell.cast_time = 1.0
	_hero._aim_dir = Vector2.RIGHT
	_hero._begin_channel(spell, false)
	var frames: int = int(spell.cast_time * SHOT_FRAC * float(Engine.physics_ticks_per_second))
	for i in frames:
		await physics_frame
	await _save("herocast_channel_beam.png")
	_hero._cancel_channel()


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("user://" + fname)
		print("herocast saved ", fname)
