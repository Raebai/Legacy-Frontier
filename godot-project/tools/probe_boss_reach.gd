# Run headless:
#   godot --headless --path godot-project --script tools/probe_boss_reach.gd
#
# CAN A GUARDIAN ANSWER HIGH GROUND, OR CAN YOU JUST STAND ON A LEDGE AND WIN?
#
# Maker: "I really want the bosses to also be able to jump move around damage from
# wherever no way to just smurf them by sitting high up like make some of them able
# to fly for example and stuff."
#
# This probe builds the real room, hangs ONE ledge at a FloorGen-plausible height,
# parks a hero stub on top of it, spawns a real guardian through the shipped
# `Encounter.spawn_boss` path and then just watches. It prints, per body:
#
#   apex        the highest the body's origin ever got above its own resting y.
#               0 means it never left the ground at all.
#   air_frames  how many physics frames it spent off the floor.
#   air_dx      how far it travelled horizontally WHILE AIRBORNE. A ballistic leap
#               that only rises is a pogo, not a leap — this is the number that
#               tells the two apart.
#   dy_min      the smallest vertical gap it ever closed to the hero. If this never
#               drops below the ledge height, the hero was never reached.
#   reach_gap   dy_min minus what a fixed hop can clear. Positive = unreachable.
#
# No assertions: this is a MEASUREMENT, not a suite. The suite that locks the
# behaviour in is tools/slice_test_boss_reach.gd.
extends SceneTree

const ENC: String = "res://scripts/combat/Encounter.gd"
const GS: String = "res://scripts/GameState.gd"
const WALL_THICKNESS: float = 16.0
const FRAMES: int = 600
## A third-tier FloorGen ledge sits roughly this far above the ground plane.
const LEDGE_RISE: float = 250.0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	for body_scale: float in [1.0, 0.45]:
		await _measure(body_scale)
		await process_frame
		await process_frame
		print("")
	quit(0)


func _measure(body_scale: float) -> void:
	var gs_script: GDScript = load(GS) as GDScript
	var enc_script: GDScript = load(ENC) as GDScript
	var layout: Resource = gs_script.default_layout()
	var room: Vector2 = layout.room_size
	var ground: float = room.y - WALL_THICKNESS * 0.5

	var arena := Node2D.new()
	root.add_child(arena)
	_build_walls(arena, room)

	# The safe spot itself: one solid ledge, mid-room, at third-tier height.
	var ledge_y: float = ground - LEDGE_RISE
	_static_box(arena, Vector2(room.x * 0.5, ledge_y + 8.0), Vector2(200.0, 16.0))

	var hero := Node2D.new()
	hero.add_to_group("hero")
	hero.position = Vector2(room.x * 0.5, ledge_y - 24.0)
	arena.add_child(hero)

	var enc: Node = enc_script.new()
	arena.add_child(enc)
	enc.configure(layout.spawn_rect_min, layout.spawn_rect_max, layout.min_spawn_dist_from_hero)
	enc.configure_places(layout)
	var boss: Node2D = enc.spawn_boss(1.0, body_scale) as Node2D

	print("== guardian body_scale %.2f ==" % body_scale)
	print("  ground %.1f   ledge surface %.1f   hero y %.1f (%.0f px up)"
		% [ground, ledge_y, hero.position.y, ground - hero.position.y])

	var rest_y: float = boss.position.y
	var apex: float = 0.0
	var air_frames: int = 0
	var air_dx: float = 0.0
	var last_x: float = boss.position.x
	var dy_min: float = 1.0e9
	var was_air: bool = false
	## Frames spent STANDING on something at or above the ledge's surface — i.e. the
	## boss actually got up there rather than bouncing off the underside.
	var perch_frames: int = 0
	for i: int in FRAMES:
		await physics_frame
		if not is_instance_valid(boss):
			break
		# Settle first: the ground snap + depenetration own the first few frames.
		if i == 20:
			rest_y = boss.position.y
		if i < 20:
			last_x = boss.position.x
			continue
		var air: bool = not bool(boss.call("is_on_floor"))
		if air:
			air_frames += 1
			air_dx += absf(boss.position.x - last_x)
		was_air = air
		if not air and boss.position.y < ledge_y:
			perch_frames += 1
		apex = maxf(apex, rest_y - boss.position.y)
		dy_min = minf(dy_min, boss.position.y - hero.position.y)
		last_x = boss.position.x
	if not is_instance_valid(boss):
		print("  (boss freed before the measurement finished)")
		arena.queue_free()
		return

	print("  apex above rest     %.2f px" % apex)
	print("  air_frames          %d of %d" % [air_frames, FRAMES - 20])
	print("  air_dx              %.2f px travelled while airborne" % air_dx)
	print("  perch_frames        %d  (standing at or above the ledge surface)" % perch_frames)
	print("  final y             %.2f" % boss.position.y)
	print("  dy_min              %.2f px still below the hero at the closest" % dy_min)
	print("  final airborne      %s" % str(was_air))
	print("  velocity            (%.1f, %.1f)" % [boss.velocity.x, boss.velocity.y])
	arena.queue_free()


func _build_walls(arena: Node2D, room: Vector2) -> void:
	_static_box(arena, Vector2(room.x * 0.5, room.y - WALL_THICKNESS * 0.5),
		Vector2(room.x, WALL_THICKNESS))                                   # floor
	_static_box(arena, Vector2(room.x * 0.5, WALL_THICKNESS * 0.5),
		Vector2(room.x, WALL_THICKNESS))                                   # ceiling
	_static_box(arena, Vector2(WALL_THICKNESS * 0.5, room.y * 0.5),
		Vector2(WALL_THICKNESS, room.y))                                   # left
	_static_box(arena, Vector2(room.x - WALL_THICKNESS * 0.5, room.y * 0.5),
		Vector2(WALL_THICKNESS, room.y))                                   # right


func _static_box(parent: Node2D, at: Vector2, size: Vector2) -> void:
	var b := StaticBody2D.new()
	b.position = at
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	b.add_child(cs)
	parent.add_child(b)
