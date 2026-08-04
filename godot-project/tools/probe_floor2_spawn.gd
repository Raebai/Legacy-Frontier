# Run headless:
#   godot --headless --path godot-project --script tools/probe_floor2_spawn.gd
#
# WHY DOES FLOOR 2 NOT LET YOU SPAWN?
#
# Maker: "I killed the boss but floor 2 is buggy, not letting me spawn."
#
# Floor 1 is reached from the hub and works. Floor 2 is the first floor reached by
# TAKING THE CLIMB EXIT — and that exit was a dead trigger until this session (it had
# no collision mask and could not see a hero, measured at `overlaps=0`). So the
# advance path has effectively never been exercised, and "floor 2" is really "the
# first floor anyone has ever arrived at through a portal".
#
# This asks the three questions that would each produce that symptom:
#   1. does the floor DEFINE a legal place to stand — is `hero_start` above the floor
#      plane and inside the room, or has the layout put it in the void / in a wall?
#   2. do the two exits OVERLAP? They have opposite consequences (climb vs end the
#      run) and the leave-pad was moved to the middle of the room this session, which
#      is where a hero can also be standing.
#   3. does the leave-pad sit ON `hero_start`? If it does, a hero arriving on a
#      cleared floor lands inside a trigger.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("floor  room            hero_start        exit_point        pad(mid,ground)   flags")
	for f: int in range(1, 8):
		# The real entry: the authored tower, varied per floor, exactly as a climb does.
		var gs: Node = root.get_node_or_null(^"/root/GameState")
		if gs == null:
			print("no GameState"); break
		var varied: TowerDef = gs.call("_load_or_build_tower") as TowerDef
		if varied == null:
			print("no tower"); break
		var def: FloorDef = varied.floors[f - 1] if f - 1 < varied.floors.size() else null
		if def == null or def.layout == null:
			print("%5d  <no layout>" % f)
			continue
		var l: LayoutDef = def.layout
		var room: Vector2 = l.room_size
		var ground: float = room.y - 16.0 * 0.5          # Arena.WALL_THICKNESS * 0.5
		var pad := Vector2(room.x * 0.5, ground)
		var flags: Array[String] = []
		# 1. a legal place to stand
		if l.hero_start.x <= 0.0 or l.hero_start.x >= room.x:
			flags.append("HERO_X_OUTSIDE_ROOM")
		if l.hero_start.y > ground + 1.0:
			flags.append("HERO_BELOW_FLOOR(%.0f>%.0f)" % [l.hero_start.y, ground])
		if l.hero_start.y < 0.0:
			flags.append("HERO_ABOVE_ROOM")
		# 2. the two exits on top of each other
		if l.exit_point.distance_to(pad) < 60.0:
			flags.append("EXITS_OVERLAP(%.0f px)" % l.exit_point.distance_to(pad))
		# 3. the leave-pad on the spawn point
		if l.hero_start.distance_to(pad) < 60.0:
			flags.append("PAD_ON_SPAWN(%.0f px)" % l.hero_start.distance_to(pad))
		if l.exit_point.x <= 0.0 or l.exit_point.x >= room.x:
			flags.append("EXIT_OUTSIDE_ROOM")
		print("%5d  %-14s  %-16s  %-16s  %-16s  %s" % [
			f, str(room), str(l.hero_start), str(l.exit_point), str(pad),
			"ok" if flags.is_empty() else ", ".join(flags)])
	quit(0)
