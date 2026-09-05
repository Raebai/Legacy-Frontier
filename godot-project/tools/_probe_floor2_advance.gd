# DIAGNOSTIC PROBE — READ-ONLY. Delete freely.
#   godot --headless --path godot-project --script tools/_probe_floor2_advance.gd
#
# "FLOOR 2 WILL NOT LET THE PLAYER SPAWN."
#
# probe_floor2_spawn.gd already proved the floor DATA is legal on every floor. So
# this probe does not ask about data. It drives the REAL advance path end to end —
#   enter_run -> Arena builds floor 1 -> hero stands on the exit -> ExitPortal fires
#   -> Arena._on_portal_taken -> GameState.advance_floor -> floor_advanced
#   -> Arena._on_floor_advanced -> _setup_floor(2)
# — and then asks the only question that matters: after all of that, IS THERE A HERO
# STANDING SOMEWHERE LEGAL?
#
# ⚠ THE REAL SAVE. advance_floor() writes user://climber.json and the autoload is
# inside the tree, so the guard in _save_climber does not fire. The file is snapshotted
# byte-for-byte on the way in and rewritten on the way out, and the probe prints
# whether the restore matched.
#
# ⚠ THE INSTRUMENT IS TESTED BEFORE IT IS TRUSTED. Two controls run through the exact
# same verdict function after the real measurement: the hero teleported onto floor 2's
# own authored hero_start (must read GREEN) and the hero teleported to (5000, 5000)
# (must read RED). If either control disagrees, the probe says so and the real result
# is not to be believed.
extends SceneTree

const CLIMBER: String = "user://climber.json"
## Seeds driven through the full real path. Chosen after the pure sweep below.
const REAL_SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
## Controls only need to run a couple of times — they are about the instrument, not
## about the seed. Running them on every seed just triples the wall clock.
const CONTROL_SEEDS: Array[int] = [1, 2, 6]
const WALL_T: float = 16.0
## Hero.tscn's collider: RectangleShape2D 18x18.
const HERO_BOX: Vector2 = Vector2(18.0, 18.0)

var _saved_climber: String = ""
var _instrument_ok: bool = true
var _tally: Array[Dictionary] = []


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	_snapshot_climber()
	var gs: Node = root.get_node_or_null(^"/root/GameState")
	if gs == null:
		print("FATAL: no /root/GameState (autoloads are nodes, not identifiers, under --script)")
		quit(1)
		return

	_pure_sweep(gs)
	for s: int in REAL_SEEDS:
		await _real_path(gs, s)
	await _leave_pad_leak(gs)

	_restore_climber()
	print("")
	print("═══ REAL-PATH TALLY ═══")
	var bad: int = 0
	for r: Dictionary in _tally:
		if not bool(r["ok"]):
			bad += 1
		print("  seed %3d  f1 h=%4.0f -> f2 h=%4.0f  (%s exit)   %s"
			% [int(r["seed"]), float(r["h1"]), float(r["h2"]),
				("LEDGE" if bool(r["ledge"]) else "ground"),
				("ok" if bool(r["ok"]) else "*** HERO LOST ***")])
	print("  %d / %d climbs lose the hero on the step onto floor 2" % [bad, _tally.size()])
	print("")
	print("instrument self-check: %s" % ("OK — controls read as expected" if _instrument_ok else "*** BROKEN — do not trust the results above ***"))
	quit(0)


# ══════════════════════════════════════════════════════════════════ PART A: sweep
## Pure math, no scene. For each climb seed: where does the hero STAND when it takes
## floor 1's exit, and is that point still inside floor 2's room once floor 2 is built
## under it? Nothing here touches the arena — it is the frequency estimate that says
## whether the real-path result below is a fluke or the common case.
func _pure_sweep(gs: Node) -> void:
	print("═══ PART A — pure sweep: hero's floor-1 exit stance vs floor 2's room ═══")
	var bad_below: int = 0
	var bad_side: int = 0
	var total: int = 0
	var examples: Array[String] = []
	for s: int in range(1, 201):
		var t: TowerDef = FloorGen.apply(gs.call(&"build_default_tower"), s)
		if t == null or t.floors.size() < 2:
			continue
		var l1: LayoutDef = t.floors[0].layout
		var l2: LayoutDef = t.floors[1].layout
		if l1 == null or l2 == null:
			continue
		total += 1
		# Where the hero's BODY CENTRE is when it trips the portal: standing on the
		# ground under the exit marker (ExitPortal.RADIUS is 30, the marker itself sits
		# ground_y - 38, a standing hero centre is ground_y - 9).
		var stance: Vector2 = _stance_at_exit(l1)
		var v: Dictionary = _verdict_pure(stance, l2)
		if bool(v["below"]):
			bad_below += 1
		if bool(v["side"]):
			bad_side += 1
		if (bool(v["below"]) or bool(v["side"])) and examples.size() < 6:
			examples.append("  seed %3d  f1 room %s exit %s stance %s   ->  f2 room %s   %s"
				% [s, str(l1.room_size), str(l1.exit_point), str(stance), str(l2.room_size), str(v["why"])])
	print("  seeds swept: %d" % total)
	print("  hero ends up BELOW floor 2's bottom wall : %d  (%.0f%%)" % [bad_below, 100.0 * float(bad_below) / maxf(float(total), 1.0)])
	print("  hero ends up OUTSIDE floor 2 sideways    : %d  (%.0f%%)" % [bad_side, 100.0 * float(bad_side) / maxf(float(total), 1.0)])
	for e: String in examples:
		print(e)
	print("")


## The hero's body centre while standing under a floor's exit marker.
func _stance_at_exit(l: LayoutDef) -> Vector2:
	var ground_y: float = l.room_size.y - WALL_T * 0.5
	# A ledge exit leaves the hero up on the ledge; a ground exit leaves it on the floor.
	# Either way the hero's feet are on the surface the marker sits 38px above.
	return Vector2(l.exit_point.x, l.exit_point.y + 38.0 - HERO_BOX.y * 0.5)


## Is `p` (a hero body centre) still inside room `l`? Pure — no physics.
func _verdict_pure(p: Vector2, l: LayoutDef) -> Dictionary:
	var w: float = l.room_size.x
	var h: float = l.room_size.y
	var half: Vector2 = HERO_BOX * 0.5
	# The bottom wall is centred on y = h, thickness 16, so its underside is h + 8.
	# A hero whose whole box is under that is in the void with nothing to land on.
	var below: bool = (p.y - half.y) > (h + WALL_T * 0.5)
	var side: bool = (p.x + half.x) < (0.0 - WALL_T * 0.5) or (p.x - half.x) > (w + WALL_T * 0.5)
	var why: String = ""
	if below:
		why += "BELOW(y%.0f-%.0f > wall underside %.0f) " % [p.y, half.y, h + WALL_T * 0.5]
	if side:
		why += "SIDE(x%.0f vs 0..%.0f) " % [p.x, w]
	return {"below": below, "side": side, "why": why}


# ═══════════════════════════════════════════════════════ PART B: the real path
func _real_path(gs: Node, seed_value: int) -> void:
	print("═══ PART B — real path, climb seed %d ═══" % seed_value)
	FloorGen.climb_seed = seed_value
	gs.set(&"active_tower", null)
	gs.set(&"_run_active", false)
	gs.set(&"_floor", 1)
	gs.set(&"tower_conquered", false)
	gs.call(&"enter_run")                      # the real entry: builds the tower, loads Arena.tscn
	for i: int in 6:
		await process_frame
	var arena: Node = current_scene
	if arena == null:
		print("  FATAL: enter_run did not land an Arena (current_scene is null)")
		return
	print("  arena: %s   run_active=%s  floor=%d" % [arena.name, str(gs.call(&"is_run_active")), int(gs.call(&"current_floor"))])

	# Let floor 1 build + the hero settle onto the ground.
	for i2: int in 90:
		await physics_frame
	var hero: Node2D = _hero()
	if hero == null:
		print("  FATAL: no hero in group 'hero' on floor 1")
		return
	var l1: LayoutDef = arena.get(&"_current_floor_def").layout
	print("  floor 1: room=%s  hero_start=%s  exit=%s" % [str(l1.room_size), str(l1.hero_start), str(l1.exit_point)])
	print("           hero spawned at %s (Arena.DEFAULT_HERO_START, NOT layout.hero_start)  on_floor=%s"
		% [str(hero.global_position), str(hero.call(&"is_on_floor"))])

	# Clear the room the way a cleared floor does, then walk the hero onto the exit.
	for e: Node in get_nodes_in_group(&"enemy"):
		e.queue_free()
	arena.call(&"_on_floor_cleared")
	await physics_frame
	# ⚠ THE CYAN EXIT PORTAL NO LONGER SPAWNS ON A FLOOR THAT HAS A NEXT ONE. Maker:
	# *"when you pass a floor no need for the exit sigil only the one sigil is needed
	# where it asks if you want to go to the next floor or back"*. `Arena` builds it in
	# an `else` now — only the final floor, which has no choice to offer, still gets it.
	# So `_portal` is null here and this probe, which walked a hero into it, measured
	# nothing. The advance path itself is unchanged: the gold pad's "Keep climbing"
	# button routes through the same `_on_portal_taken`, so the probe drives THAT.
	var portal: Node = arena.get(&"_portal")
	var pad: Node = arena.get(&"_return_portal")
	print("  exit portal (final floors only): %s | choice pad: %s"
		% [str(portal != null), str(pad != null)])
	hero.global_position = _stance_at_exit(l1)
	print("  hero moved onto the exit: %s" % str(hero.global_position))
	var fired: bool = false
	if portal == null:
		# The choice route, which is what a cleared non-final floor actually offers.
		arena.call(&"_on_return_taken")
		await physics_frame
		arena.call(&"_climb_from_prompt")
	for i3: int in 120:
		await physics_frame
		if int(gs.call(&"current_floor")) == 2:
			fired = true
			break
	print("  portal fired -> advance: %s   GameState.current_floor()=%d"
		% [str(fired), int(gs.call(&"current_floor"))])
	if not fired:
		print("  *** the portal never fired — the advance path is blocked BEFORE the rebuild ***")
		return

	var l2: LayoutDef = arena.get(&"_current_floor_def").layout
	print("  floor 2: room=%s  hero_start=%s" % [str(l2.room_size), str(l2.hero_start)])
	print("  hero position the instant floor 2 was built: %s" % str(hero.global_position))

	# Let physics run: a hero standing in the void will fall, one inside a wall will be
	# pushed out or stay stuck. 150 ticks = 2.5s.
	for i4: int in 150:
		await physics_frame

	var m: Dictionary = _report("  MEASURED (hero left where the advance left it)", hero, l2, arena)
	_tally.append({"seed": seed_value, "h1": l1.room_size.y, "h2": l2.room_size.y,
		"ledge": l1.exit_point.y < l1.room_size.y - WALL_T * 0.5 - 60.0, "ok": bool(m["ok"])})

	if not CONTROL_SEEDS.has(seed_value):
		print("")
		return
	# ── CONTROLS. Same verdict function, two known answers. ──
	hero.global_position = l2.hero_start
	hero.set(&"velocity", Vector2.ZERO)
	for i5: int in 90:
		await physics_frame
	var ctrl_good: Dictionary = _report("  CONTROL A (hero placed on floor 2's hero_start — must be GREEN)", hero, l2, arena)
	if not bool(ctrl_good["ok"]):
		_instrument_ok = false
		print("  *** CONTROL A FAILED: the probe calls a legal spawn illegal. Instrument broken. ***")

	hero.global_position = Vector2(5000.0, 5000.0)
	hero.set(&"velocity", Vector2.ZERO)
	for i6: int in 10:
		await physics_frame
	var ctrl_bad: Dictionary = _report("  CONTROL B (hero teleported to 5000,5000 — must be RED)", hero, l2, arena)
	if bool(ctrl_bad["ok"]):
		_instrument_ok = false
		print("  *** CONTROL B FAILED: the probe calls an obviously-broken spawn fine. Instrument broken. ***")
	print("")


# ══════════════════════════ PART C: does declining "LEAVE" leak onto the next floor?
## `_cancel_leave` sets `_return_pending = true` and `_process` re-builds the LEAVE
## pad once every hero has stepped clear of `_return_pt`. Nothing clears that flag on a
## floor advance, so this asks whether a player who says "keep climbing" and then takes
## the climb exit gets a run-ending pad standing in the middle of floor 2's live fight.
func _leave_pad_leak(gs: Node) -> void:
	print("═══ PART C — does a declined LEAVE prompt leak a run-ending pad onto floor 2? ═══")
	FloorGen.climb_seed = 1                       # a seed whose hero survives the step
	gs.set(&"active_tower", null)
	gs.set(&"_run_active", false)
	gs.set(&"_floor", 1)
	gs.set(&"tower_conquered", false)
	gs.call(&"enter_run")
	for i: int in 6:
		await process_frame
	var arena: Node = current_scene
	for i2: int in 60:
		await physics_frame
	for e: Node in get_nodes_in_group(&"enemy"):
		e.queue_free()
	arena.call(&"_on_floor_cleared")
	await physics_frame
	print("  floor 1 cleared. leave pad present: %s   _return_pt=%s"
		% [str(arena.get(&"_return_portal") != null), str(arena.get(&"_return_pt"))])
	# The player steps on the LEAVE pad and says "keep climbing".
	arena.call(&"_on_return_taken")
	arena.call(&"_cancel_leave")
	print("  said 'keep climbing' -> _return_pending=%s" % str(arena.get(&"_return_pending")))
	# ...then walks into the CLIMB exit instead.
	var hero: Node2D = _hero()
	var l1: LayoutDef = arena.get(&"_current_floor_def").layout
	hero.global_position = _stance_at_exit(l1)
	for i3: int in 120:
		await physics_frame
		if int(gs.call(&"current_floor")) == 2:
			break
	print("  advanced to floor %d.  _return_pending is STILL %s"
		% [int(gs.call(&"current_floor")), str(arena.get(&"_return_pending"))])
	# Walk away from the old return point so the re-arm condition is satisfied.
	hero.global_position = Vector2(120.0, 200.0)
	for i4: int in 30:
		await physics_frame
	var leaked: bool = arena.get(&"_return_portal") != null
	print("  LEAVE-THE-TOWER pad standing on floor 2 mid-fight: %s%s"
		% [str(leaked), ("   *** LEAK ***" if leaked else "")])
	print("")


func _hero() -> Node2D:
	for h: Node in get_nodes_in_group(&"hero"):
		if is_instance_valid(h) and h is Node2D:
			return h as Node2D
	return null


## Every question the maker's symptom could be. Prints them all; returns {"ok": bool}.
func _report(label: String, hero: Node2D, l: LayoutDef, arena: Node) -> Dictionary:
	var flags: Array[String] = []
	var p: Vector2 = hero.global_position
	if not is_instance_valid(hero):
		flags.append("HERO_FREED")
	if not hero.is_inside_tree():
		flags.append("NOT_IN_TREE")
	if not hero.visible:
		flags.append("INVISIBLE")
	if not hero.is_physics_processing():
		flags.append("PHYSICS_OFF")
	if hero.has_method(&"is_downed") and bool(hero.call(&"is_downed")):
		flags.append("DOWNED")
	var v: Dictionary = _verdict_pure(p, l)
	if bool(v["below"]):
		flags.append("BELOW_THE_ROOM")
	if bool(v["side"]):
		flags.append("OUTSIDE_SIDEWAYS")
	var on_floor: bool = bool(hero.call(&"is_on_floor"))
	if not on_floor:
		flags.append("NOT_ON_ANY_FLOOR")
	var embedded: int = _overlaps(hero, arena)
	if embedded > 0:
		flags.append("INSIDE_GEOMETRY(%d bodies)" % embedded)
	var ok: bool = flags.is_empty()
	print("%s\n      pos=%s  vel=%s  room=%s  on_floor=%s  verdict=%s"
		% [label, str(p), str(hero.get(&"velocity")), str(l.room_size), str(on_floor),
			("OK" if ok else ", ".join(flags))])
	return {"ok": ok}


## How many solid bodies the hero's own collider is sitting inside.
func _overlaps(hero: Node2D, _arena: Node) -> int:
	var space: PhysicsDirectSpaceState2D = (hero as CollisionObject2D).get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = HERO_BOX * 0.9      # shrunk so resting ON a surface is not "inside" it
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, hero.global_position)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [hero.get_rid()]
	return space.intersect_shape(q, 8).size()


# ───────────────────────────────────────────────────────────── the real save
func _snapshot_climber() -> void:
	if not FileAccess.file_exists(CLIMBER):
		_saved_climber = ""
		print("note: no climber.json to protect")
		return
	var f: FileAccess = FileAccess.open(CLIMBER, FileAccess.READ)
	_saved_climber = f.get_as_text()
	f.close()
	print("climber.json snapshotted (%d bytes)" % _saved_climber.length())


func _restore_climber() -> void:
	if _saved_climber == "":
		return
	var f: FileAccess = FileAccess.open(CLIMBER, FileAccess.WRITE)
	f.store_string(_saved_climber)
	f.close()
	var g: FileAccess = FileAccess.open(CLIMBER, FileAccess.READ)
	var back: String = g.get_as_text()
	g.close()
	print("climber.json restored: %s" % ("byte-identical" if back == _saved_climber else "*** MISMATCH ***"))
