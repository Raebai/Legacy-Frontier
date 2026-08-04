# Run headless:
#   godot --headless --path godot-project --script tools/probe_boss_feet.gd
#
# DOES THE GUARDIAN SPAWN INSIDE THE FLOOR, AND CAN IT WALK OUT?
#
# Maker, playtesting: "the boss needs to be able to move, it gets stuck in the floor."
#
# Same family as the bug `CharacterRig._align_feet_to_body` just fixed — a body and
# the thing that draws it disagreeing about where the ground is — except this one is
# a SPAWN POSITION rather than a drawing offset, so it is a physics fault and not a
# cosmetic one.
#
# `Encounter.STAND_OFFSET` (40) is how far above the ground plane a spawned body's
# ORIGIN is placed. It is sized for a trash mob, whose collider reaches 10 px below
# its origin. `Boss.tscn`'s collider is 44x92 offset (0, 6), so it reaches **52 px**
# below the origin — 12 px MORE than the whole stand-off. Every guardian is therefore
# born with its box buried in the floor collider.
#
# This probe builds the real room geometry (Arena's four wall colliders, at Arena's
# own positions and sizes), spawns a guardian through the real
# `Encounter.spawn_boss` path so the spawn position is the shipped one, and prints:
#
#   spawn_y      where Encounter put the body
#   box_bottom   the collider's bottom edge = where physics wants it to rest
#   ground       the floor collider's top face
#   BURIED       box_bottom - ground at spawn. POSITIVE = born inside the floor.
#   settled_y    where it actually ended up after N physics frames
#   on_floor     whether is_on_floor() ever became true
#   moved_x      how far it walked toward the hero in those frames
#   feet         where the RIG draws its feet, vs `ground` (the cosmetic half)
#
# Two guardians are measured: the full colossus (body_scale 1.0, a BOSS floor) and
# the mini-guardian (body_scale 0.45, which is EVERY other floor).
extends SceneTree

const ENC: String = "res://scripts/combat/Encounter.gd"
const GS: String = "res://scripts/GameState.gd"
const WALL_THICKNESS: float = 16.0
const FRAMES: int = 420


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	for scale: float in [1.0, 0.45]:
		await _measure(scale)
		# ⚠ `queue_free` is DEFERRED, and the previous arena's hero stays in group
		# "hero" until it actually goes. The next guardian's `_ready` then latches
		# onto a corpse-to-be and reports `_hero` invalid one frame later, which is a
		# measurement of the harness rather than of the game. Wait it out.
		await process_frame
		await process_frame
		print("")
	quit(0)


func _measure(body_scale: float) -> void:
	var gs_script: GDScript = load(GS) as GDScript
	var enc_script: GDScript = load(ENC) as GDScript
	var layout: Resource = gs_script.default_layout()
	var room: Vector2 = layout.room_size

	var arena := Node2D.new()
	root.add_child(arena)
	_build_walls(arena, room)

	# A hero to walk at, parked far to one side so any horizontal drive is visible.
	var hero := CharacterBody2D.new()
	hero.add_to_group("hero")
	hero.position = Vector2(120.0, room.y - WALL_THICKNESS * 0.5 - 40.0)
	arena.add_child(hero)

	var enc: Node = enc_script.new()
	arena.add_child(enc)
	# Exactly what run_floor does for a floor with a layout — so the spawn position
	# below is the shipped one and not a probe's invention.
	enc.configure(layout.spawn_rect_min, layout.spawn_rect_max, layout.min_spawn_dist_from_hero)
	enc.configure_places(layout)
	var boss: Node2D = enc.spawn_boss(1.0, body_scale) as Node2D

	var ground: float = room.y - WALL_THICKNESS * 0.5
	var box_off: float = _box_bottom_offset(boss)
	var spawn_y: float = boss.position.y
	var start_x: float = boss.position.x

	print("== guardian body_scale %.2f ==" % body_scale)
	print("  room                %.1f x %.1f" % [room.x, room.y])
	print("  ground (floor top)  %.2f" % ground)
	print("  spawn_y             %.2f" % spawn_y)
	print("  collider reaches    %.2f px below the origin" % box_off)
	print("  box_bottom at spawn %.2f" % (spawn_y + box_off))
	print("  BURIED              %.2f px  (positive = born inside the floor)"
		% (spawn_y + box_off - ground))

	var on_floor_ever: bool = false
	var first_on_floor: int = -1
	# Per-frame trace of the three things that can zero the guardian's drive:
	# the INTRO gate, the `_busy` attack gate, and a lost hero reference.
	print("  frame     y     vel.x  on_floor  phase  busy  hero  atk_cd")
	for i: int in FRAMES:
		await physics_frame
		if not is_instance_valid(boss):
			break
		if bool(boss.call("is_on_floor")):
			on_floor_ever = true
			if first_on_floor < 0:
				first_on_floor = i
		if i % 40 == 0:
			print("  %5d %7.2f %7.2f  %8s  %5d  %4s  %4s  %6.2f" % [
				i, boss.position.y, boss.velocity.x, str(bool(boss.call("is_on_floor"))),
				int(boss.call("current_phase")), str(bool(boss.get("_busy"))),
				str(is_instance_valid(boss.get("_hero"))), float(boss.get("_attack_cd"))])
	if not is_instance_valid(boss):
		print("  (boss freed before the measurement finished)")
		arena.queue_free()
		return

	var rig: Node2D = boss.get_node_or_null(^"Rig") as Node2D
	var rig_h: float = float(rig.get("height")) if rig != null else NAN
	var feet: float = boss.global_position.y + rig.position.y + rig_h * 0.5 if rig != null else NAN

	print("  --- after %d physics frames ---" % FRAMES)
	print("  settled_y           %.2f   (box_bottom %.2f, ground %.2f)"
		% [boss.position.y, boss.position.y + box_off, ground])
	print("  still buried by     %.2f px" % (boss.position.y + box_off - ground))
	print("  is_on_floor ever    %s (first at frame %d)" % [str(on_floor_ever), first_on_floor])
	print("  velocity            (%.1f, %.1f)" % [boss.velocity.x, boss.velocity.y])
	print("  moved_x             %.2f px (hero is %.0f px away on x)"
		% [boss.position.x - start_x, absf(hero.position.x - start_x)])
	print("  boss phase          %d" % int(boss.call("current_phase")))
	print("  rig height          %.2f   rig.position.y %.2f" % [rig_h, rig.position.y])
	print("  drawn feet          %.2f   vs ground %.2f  -> FLOAT/SINK %.2f"
		% [feet, ground, feet - ground])
	arena.queue_free()


## The lowest bottom edge among the body's rectangle colliders, relative to its
## origin. Same rule `CharacterRig._align_feet_to_body` uses, so the two numbers in
## the report are comparable.
func _box_bottom_offset(body: Node) -> float:
	var best: float = -INF
	for c: Node in body.get_children():
		if not (c is CollisionShape2D):
			continue
		var shape: Shape2D = (c as CollisionShape2D).shape
		if not (shape is RectangleShape2D):
			continue
		best = maxf(best, (c as CollisionShape2D).position.y
			+ (shape as RectangleShape2D).size.y * 0.5)
	return best


## Arena._apply_room_size, reproduced exactly (positions, sizes, layer 1).
func _build_walls(arena: Node2D, size: Vector2) -> void:
	var w: float = maxf(size.x, WALL_THICKNESS * 4.0)
	var h: float = maxf(size.y, WALL_THICKNESS * 4.0)
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	arena.add_child(walls)
	_wall(walls, Vector2(w * 0.5, 0.0), Vector2(w, WALL_THICKNESS))
	_wall(walls, Vector2(w * 0.5, h), Vector2(w, WALL_THICKNESS))
	_wall(walls, Vector2(0.0, h * 0.5), Vector2(WALL_THICKNESS, h))
	_wall(walls, Vector2(w, h * 0.5), Vector2(WALL_THICKNESS, h))


func _wall(walls: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	cs.position = pos
	walls.add_child(cs)
