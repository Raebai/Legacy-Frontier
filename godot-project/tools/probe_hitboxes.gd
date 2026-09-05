# Run headless:
#   Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#       --script tools/probe_hitboxes.gd
#
# ══ FOUR CHANNELS THAT ALL CLAIM TO BE "THE STICK FIGURE", MEASURED SIDE BY SIDE ══
#
# A fighter in this game exists four times over, and nothing until now printed the
# four numbers next to each other:
#
#   DRAWN     what `CharacterRig._draw` actually puts on screen — the joints of
#             `_sim_pose()` fattened by their own stroke widths. This is the ONLY
#             channel the player can see, so it is the one every other channel is
#             wrong RELATIVE TO.
#   BOX       the `CollisionShape2D` under the CharacterBody2D. Decides where the
#             body rests on a floor, what it fits through, what stops it.
#   AREA      the `Hurtbox` Area2D — the physics shape a travelling bolt
#             (`Spell.gd` is an Area2D that damages on `body_entered` /
#             `area_entered`) collides with. Enemy builds one. Hero does not.
#   ANALYTIC  `body_distance()` + `hit_margin()` — the duck-typed silhouette
#             `SpellTargets` measures blasts, cones and beams against.
#
# The repo's own recorded bug is exactly a two-channel disagreement: an 18 px BOX
# under a 31 px DRAWN rig put the feet 6.5 px under the floor, `_plant_foot` clamped
# them back up, and 41% of the leg folded into the knees on every frame. The lesson
# written down afterwards was that the leg harness had no BODY under the rig, so it
# could never have shown the fault. So this probe measures the real shipped scenes,
# on a real floor, after physics has settled them.
#
# WHAT EACH COLUMN MEANS (all y down, all in BODY-LOCAL px unless it says world):
#   h            rig.height
#   rigY         rig.position.y — the feet-alignment offset `_align_feet_to_body`
#                wrote, plus the body spring's current ride.
#   box          collider top .. bottom, and its width
#   drawn        drawn silhouette top .. bottom, and its width
#   area         Hurtbox shapes' union, or "none"
#   analytic     the extent at which `body_distance(p) <= hit_margin()` stops being
#                true, probed along -y / +y / +x from the origin
#   SINK         world y of the LOWEST DRAWN PIXEL minus the world y of the floor.
#                Positive = drawn feet below the floor. Must read ~0.
#
# ⚠ THE FEET ARE CLAMPED, SO SINK ALONE UNDERSTATES THE FAULT. `_plant_foot` pins a
# grounded foot to the floor line, so a body whose box is too short does not draw its
# feet underground — it draws them at the floor with the leg CRUSHED. So `legExt` is
# printed too: the drawn hip->foot distance as a fraction of the leg the rig thinks it
# has (`LEG_LEN_FACTOR * h`). 1.00 is a standing leg. That is the number the recorded
# bug moved, and the one a fix has to move back.
extends SceneTree

const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"
const ENEMY_SCENE: String = "res://scenes/combat/Enemy.tscn"
const BOSS_SCENE: String = "res://scenes/combat/Boss.tscn"
const THRALL_SCENE: String = "res://scenes/combat/Thrall.tscn"

## World y of the floor's TOP face. Everything is reported against this.
const GROUND_Y: float = 300.0
## Physics frames allowed for a body to fall the short drop and settle. Generous:
## the spring sim in the rig rings for a while after the body itself stops, and
## measuring mid-ring is measuring the harness.
const SETTLE_FRAMES: int = 150
## Frames sampled per non-rest pose, taking the WORST (largest) extent seen.
const POSE_FRAMES: int = 40
## How fast the walk sample drags the body along x, px/s. Above
## `CharacterRig.GAIT_IDLE_SPEED` by a wide margin so the gait is genuinely running.
const WALK_SPEED: float = 150.0

var _rig_script: GDScript = null


func _initialize() -> void:
	# `_initialize` runs BEFORE the tree exists — every node built here would have no
	# parent and no physics. Defer one frame, exactly as every other probe in this
	# folder learned to.
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_rig_script = load("res://scripts/combat/CharacterRig.gd") as GDScript
	var world: Node2D = _build_world()
	await physics_frame

	print("")
	print("══ PER-ARCHETYPE CHANNEL COMPARISON ═════════════════════════════════")
	for entry: Array in [
		["hero", HERO_SCENE], ["enemy", ENEMY_SCENE],
		["boss", BOSS_SCENE], ["thrall", THRALL_SCENE],
	]:
		await _measure_archetype(world, String(entry[0]), String(entry[1]))
	await _melee_report(world)
	quit(0)


# ------------------------------------------------------------------ the fixture

## A floor on `CharacterRig.GROUND_MASK` (layer 1) wide enough that a walk sample
## cannot run off the end of it. Nothing else: no arena, no walls, no spawner. The
## question here is "does a body agree with its own drawing", and every extra node is
## a chance for the answer to be about something else.
func _build_world() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = int(_rig_script.get("GROUND_MASK"))
	floor_body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6000.0, 80.0)
	cs.shape = rect
	cs.position = Vector2(0.0, GROUND_Y + 40.0)
	floor_body.add_child(cs)
	world.add_child(floor_body)
	return world


func _spawn(world: Node2D, scene_path: String) -> Node2D:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var body: Node2D = packed.instantiate() as Node2D
	if body == null:
		return null
	world.add_child(body)
	# Dropped from a little above the floor rather than placed exactly on it: landing
	# is what makes physics choose the resting y, and a hand-placed y would just be
	# the probe asserting the answer it wanted.
	body.global_position = Vector2(0.0, GROUND_Y - 90.0)
	return body


# ------------------------------------------------------------------ measurement

func _measure_archetype(world: Node2D, label: String, scene_path: String) -> void:
	var body: Node2D = _spawn(world, scene_path)
	if body == null:
		print("  %-7s FAIL: could not instantiate %s" % [label, scene_path])
		return
	for i: int in SETTLE_FRAMES:
		# A Thrall with no summoner is an orphan and expires on a short grace timer.
		# Held open rather than worked around, because the thing being measured is its
		# SHAPE and a shape does not care why it was summoned.
		if is_instance_valid(body) and body.get(&"thrall_life") != null:
			body.set(&"thrall_life", 999.0)
		await physics_frame
	if not is_instance_valid(body):
		# A Thrall with no summoner despawns itself. Nothing wrong with the scene —
		# the harness simply is not the world it expects.
		print("  %-7s freed itself during settle (no owner in this fixture)" % label)
		return
	var rig: Node2D = body.get_node_or_null(^"Rig") as Node2D
	if rig == null:
		print("  %-7s FAIL: no Rig child" % label)
		body.queue_free()
		return
	var h: float = float(rig.get("height"))

	print("")
	print("── %s (%s) ──" % [label, scene_path.get_file()])
	print("   rig height        %7.2f     node scale %.2f" % [h, body.scale.y])
	print("   rig.position.y    %7.2f     (feet-align offset + body ride %.2f)"
		% [rig.position.y, float(rig.call("body_ride"))])

	var box: Rect2 = _box_bounds(body)
	var drawn: Rect2 = _drawn_bounds(rig)
	var area: Rect2 = _area_bounds(body)
	print("   BOX      y %7.2f .. %7.2f   w %6.2f" % [box.position.y, box.end.y, box.size.x])
	print("   DRAWN    y %7.2f .. %7.2f   w %6.2f" % [drawn.position.y, drawn.end.y, drawn.size.x])
	if area.size == Vector2.ZERO:
		print("   AREA     none — no Hurtbox. A travelling bolt can only collide with")
		print("            the BOX above, so anything the BOX does not cover is a")
		print("            hole the drawing does not show.")
	else:
		print("   AREA     y %7.2f .. %7.2f   w %6.2f" % [area.position.y, area.end.y, area.size.x])
		print("   AREA vs DRAWN   top %+.2f   bottom %+.2f   (0 = the physics shape sits"
			% [area.position.y - drawn.position.y, area.end.y - drawn.end.y]
			+ " exactly on the drawing)")
	_analytic_report(body)

	# THE TWO NUMBERS THE RECORDED BUG MOVED.
	var lowest_world: float = body.global_position.y + drawn.end.y
	# ⚠ TWO DIFFERENT "FEET", AND `probe_town_feet.gd` MEASURES THE OTHER ONE. That
	# probe's SINK is the NOMINAL foot — `origin + rig.position.y + height/2`, the
	# joint centre — and it must read 0 because that is exactly what
	# `_align_feet_to_body` solves for. This probe's SINK is the LOWEST DRAWN PIXEL,
	# which is the joint centre plus the foot capsule's own cap radius. Both are
	# printed so the two probes can never be read as contradicting each other.
	var nominal_world: float = body.global_position.y + rig.position.y + h * 0.5
	print("   SINK(nominal joint)  %+.2f px   — probe_town_feet's number; must be ~0"
		% (nominal_world - GROUND_Y))
	print("   SINK(drawn pixel)    %+.2f px   (lowest drawn %.2f vs floor %.2f)"
		% [lowest_world - GROUND_Y, lowest_world, GROUND_Y])
	print("   legExt   %.3f of the rig's own leg (1.000 = standing straight)"
		% _leg_extension(rig))

	# Worst-case extents through a walk and through a strike, because a hitbox cut for
	# a resting pose is a hitbox that stops matching the moment the fight starts.
	var walk: Rect2 = await _worst_bounds(body, rig, "walk")
	var atk: Rect2 = await _worst_bounds(body, rig, "attack")
	print("   DRAWN walk    y %7.2f .. %7.2f   w %6.2f" % [walk.position.y, walk.end.y, walk.size.x])
	print("   DRAWN attack  y %7.2f .. %7.2f   w %6.2f" % [atk.position.y, atk.end.y, atk.size.x])
	body.queue_free()
	await process_frame


## The union of the body's own rectangle colliders, in body-local px. Excludes the
## Hurtbox's shapes, which live under a child Area2D and are reported separately.
func _box_bounds(body: Node2D) -> Rect2:
	var out := Rect2()
	var got: bool = false
	for c: Node in body.get_children():
		var cs := c as CollisionShape2D
		if cs == null or not (cs.shape is RectangleShape2D):
			continue
		var half: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
		var r := Rect2(cs.position - half, half * 2.0)
		out = r if not got else out.merge(r)
		got = true
	return out


## The union of every shape under a `Hurtbox` Area2D, in BODY-local px — so it is
## directly comparable with `_box_bounds` and `_drawn_bounds`. Includes the Area2D's
## own offset, which is the whole point: that offset is what `Enemy._sync_body_offset`
## writes each frame to keep the shape glued to the drawn body.
func _area_bounds(body: Node2D) -> Rect2:
	var area := body.get_node_or_null(^"Hurtbox") as Area2D
	if area == null:
		return Rect2()
	var out := Rect2()
	var got: bool = false
	for c: Node in area.get_children():
		var cs := c as CollisionShape2D
		if cs == null:
			continue
		var r: Rect2
		if cs.shape is RectangleShape2D:
			var half: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
			r = Rect2(cs.position - half, half * 2.0)
		elif cs.shape is CircleShape2D:
			var rad: float = (cs.shape as CircleShape2D).radius
			r = Rect2(cs.position - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
		else:
			continue
		r.position += area.position
		out = r if not got else out.merge(r)
		got = true
	return out


## The DRAWN silhouette, in BODY-local px: every joint of the pose that is actually
## rendered, fattened by the radius the renderer strokes it with, pushed through the
## rig's own transform (which carries the feet-align offset, the body ride, the pitch
## and the facing flip).
##
## Limbs are sampled at their ENDPOINTS only. `draw_figure` bends a knee/elbow between
## them, and a bent joint bulges SIDEWAYS out of the endpoint hull — so the width here
## is a slight UNDER-estimate while the vertical extents (which is what the box and
## the floor argue about) are exact.
func _drawn_bounds(rig: Node2D) -> Rect2:
	var pose: Dictionary = rig.call("snapshot_pose")
	if pose.is_empty():
		return Rect2()
	var w: float = float(pose.get("w", 2.0))
	var samples: Array = [
		["head_center", float(pose.get("r", 3.0))],
		["neck", w * 0.5], ["shoulder", w * 0.5], ["hip", w * 0.5],
		["hand_lead", float(pose.get("hand_lead_r", w * 0.5))],
		["hand_off", float(pose.get("hand_off_r", w * 0.5))],
		["foot_lead", float(pose.get("foot_r", w * 0.5))],
		["foot_off", float(pose.get("foot_r", w * 0.5))],
	]
	var out := Rect2()
	var got: bool = false
	for s: Array in samples:
		if not pose.has(String(s[0])):
			continue
		var p: Vector2 = rig.transform * (pose[String(s[0])] as Vector2)
		var rad: float = float(s[1])
		var r := Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
		out = r if not got else out.merge(r)
		got = true
	return out


## Drawn hip->foot distance over the leg the rig believes it has. The recorded bug
## crushed this to ~0.59; a standing figure reads ~1.00.
func _leg_extension(rig: Node2D) -> float:
	var pose: Dictionary = rig.call("snapshot_pose")
	if pose.is_empty():
		return NAN
	var h: float = float(rig.get("height"))
	var leg: float = h * float(_rig_script.get("LEG_LEN_FACTOR"))
	if leg <= 0.0:
		return NAN
	var hip: Vector2 = pose["hip"]
	var best: float = 0.0
	for k: String in ["foot_lead", "foot_off"]:
		best = maxf(best, hip.distance_to(pose[k] as Vector2))
	return best / leg


## Where the duck-typed silhouette `SpellTargets` uses actually STOPS, probed by
## bisection along three directions from the body origin. This is the shape a blast
## or a melee cone is measured against, and it is a completely different code path
## from both the box and the Area2D — so it gets measured, not assumed.
func _analytic_report(body: Node2D) -> void:
	if not body.has_method("body_distance") or not body.has_method("hit_margin"):
		print("   ANALYTIC none — no body_distance()/hit_margin(), so SpellTargets")
		print("            falls back to a ZERO-SIZE point test at the origin.")
		return
	var m: float = float(body.call("hit_margin"))
	# ⚠ THE PROBE CANNOT START AT THE ORIGIN. A hero's own origin sits 7.1 px off its
	# spine (the hip is above the mid-line and the rig is lifted by the feet-align
	# offset), so it is OUTSIDE its own hit shape — a bisection anchored there reports
	# 0.00 in every direction and looks like a body with no silhouette at all. That is
	# a vacuous measurement, and the first run of this probe printed exactly it.
	# Anchored on the spine mid-point instead, which is inside by construction.
	var anchor: Vector2 = body.global_position
	if body.has_method("head_point"):
		anchor = (body.call("head_point") as Vector2).lerp(body.global_position, 0.5)
	var up: float = _analytic_extent(body, anchor, Vector2(0.0, -1.0), m)
	var down: float = _analytic_extent(body, anchor, Vector2(0.0, 1.0), m)
	var side: float = _analytic_extent(body, anchor, Vector2(1.0, 0.0), m)
	var a_y: float = anchor.y - body.global_position.y
	print("   ANALYTIC y %7.2f .. %7.2f   w %6.2f   (margin %.2f)"
		% [a_y - up, a_y + down, side * 2.0, m])


## Largest t for which `body_distance(from + dir * t) <= hit_margin()`. Bisection
## rather than a step scan so the answer is exact to a hundredth of a pixel without
## a thousand `call()`s per direction.
func _analytic_extent(body: Node2D, from: Vector2, dir: Vector2, margin: float) -> float:
	var lo: float = 0.0
	var hi: float = 400.0
	if float(body.call("body_distance", from + dir * hi)) <= margin:
		return hi  # runs off the end of the probe — report the cap rather than lie
	for i: int in 40:
		var mid: float = (lo + hi) * 0.5
		if float(body.call("body_distance", from + dir * mid)) <= margin:
			lo = mid
		else:
			hi = mid
	return lo


## The WORST (largest) drawn bounds seen across a driven pose.
##
## ⚠ THE BODY IS DRAGGED BY HAND, and it has to be. The gait reads the node's own
## world motion (`_track_body_motion`), so a rig told to RUN while its body stands
## still draws a standing figure. Writing `global_position` after each physics frame
## is the smallest thing that produces genuine motion without inventing an input
## stack for four different scripts.
func _worst_bounds(body: Node2D, rig: Node2D, mode: String) -> Rect2:
	var out := Rect2()
	var got: bool = false
	var state_run: int = int(_rig_script.get("State").get("RUN"))
	var state_punch: int = int(_rig_script.get("State").get("PUNCH"))
	for i: int in POSE_FRAMES:
		if not is_instance_valid(body) or not is_instance_valid(rig):
			break
		if mode == "walk":
			rig.call("set_body_velocity", Vector2(WALK_SPEED, 0.0))
			rig.call("play", state_run)
			body.global_position.x += WALK_SPEED / 60.0
		else:
			# One-shot states auto-return to IDLE, so it is re-played rather than held:
			# the goal is the widest frame of a strike, not one particular frame of it.
			rig.call("play", state_punch)
		await physics_frame
		var r: Rect2 = _drawn_bounds(rig)
		out = r if not got else out.merge(r)
		got = true
	return out


# ----------------------------------------------------------------- melee report

## THE SWING YOU SEE VS THE SWING THAT HITS.
##
## Two separate things draw a melee attack and neither of them is the hitbox:
##   * `CharacterRig._draw_slash_arc` sweeps at `SLASH_ARC_RADIUS_FACTOR * height`
##     around the figure — a wrist flourish, sized off the BODY.
##   * `SwingArc` (the heavy-swing crescent) is told the reach explicitly and
##     travels exactly that far — but it is spawned at `rig.get_weapon_tip()`, not
##     at the origin the damage cone is measured from.
## The damage is `SpellTargets.in_cone(global_position, facing, melee_range,
## melee_arc_dot, ...)`, which measures reach to the target's SILHOUETTE and adds
## the target's own `hit_margin` on top.
##
## So there are three different reaches in play per class and this prints all three.
func _melee_report(world: Node2D) -> void:
	var hero_script: GDScript = load("res://scripts/combat/Hero.gd") as GDScript
	var swing_script: GDScript = load("res://scripts/combat/SwingArc.gd") as GDScript
	var cfgs: Dictionary = hero_script.get("CLASS_CONFIG")
	var names: Array = hero_script.get("CLASS_NAMES")
	var default_range: float = float(hero_script.get("MELEE_RANGE"))
	var default_dot: float = float(hero_script.get("MELEE_ARC_DOT"))
	var slash_factor: float = float(_rig_script.get("SLASH_ARC_RADIUS_FACTOR"))
	var default_h: float = float(_rig_script.get("DEFAULT_HEIGHT"))
	# How far past its `reach` argument the crescent's OUTER EDGE actually travels.
	# `SwingArc._draw` puts the arc's centre at `from + dir * reach` on its last frame
	# and then draws a circle of radius `reach * 0.42` about a point pulled back by
	# `0.65` of that radius — so the leading edge lands at `reach * (1 + 0.42 - 0.273)`.
	var crescent_r: float = 0.42
	var crescent_pull: float = 0.65
	var edge_factor: float = 1.0 + crescent_r - crescent_r * crescent_pull
	print("")
	print("══ MELEE: DRAWN ARC vs QUERIED ARC ══════════════════════════════════")
	print("   rig slash-arc radius (what a punch/kick DRAWS around the body): %.2f px"
		% (slash_factor * default_h))
	print("   SwingArc outer edge = from + dir * reach * %.3f" % edge_factor)
	# The forgiveness a standard 31 px enemy adds on top of every one of these.
	var enemy_margin: float = default_h * float(load("res://scripts/combat/Enemy.gd")
		.get("HIT_MARGIN_FACTOR"))
	print("   %-12s %7s %8s %9s %9s %8s %8s" % [
		"class", "range", "arc_dot", "halfangle", "hits(px)", "tipOff", "drawn"])
	var hero: Node2D = _spawn(world, HERO_SCENE)
	for i: int in 30:
		await physics_frame
	for cls: int in cfgs.keys():
		var cfg: Dictionary = cfgs[cls]
		var rng: float = float(cfg.get("melee_range", default_range))
		var dot: float = float(cfg.get("melee_arc_dot", default_dot))
		# The crescent is spawned at the WEAPON TIP, not at the origin the cone is
		# measured from — so the class's weapon look decides how far ahead the drawing
		# starts. Measured on a real hero configured to that class rather than derived,
		# because the tip depends on the arm pose as well as the weapon.
		var tip_off: float = 0.0
		if hero != null and is_instance_valid(hero):
			hero.call("configure_class", cls)
			await physics_frame
			var rig: Node2D = hero.get_node_or_null(^"Rig") as Node2D
			if rig != null:
				var facing: Vector2 = Vector2.RIGHT
				tip_off = ((rig.call("get_weapon_tip") as Vector2)
					- hero.global_position).dot(facing)
		var drawn_reach: float = tip_off + rng * edge_factor
		var name: String = str(names[cls]) if cls < names.size() else str(cls)
		print("   %-12s %7.1f %8.2f %8.1f° %9.1f %8.1f %8.1f" % [
			name, rng, dot, rad_to_deg(acos(clampf(dot, -1.0, 1.0))),
			rng + enemy_margin, tip_off, drawn_reach])
	print("")
	print("   ── WHAT THE SWING HITS vs WHAT THE TELL DRAWS ──")
	print("   The auto-target is gone (maker ruling: NO auto-aim), so the CONE is now the")
	print("   whole of a swing. `_publish_swing_tell` draws it as a LANE, and a lane cannot")
	print("   represent a 66-90 degree wedge: the cone's own lateral extent at full reach")
	print("   is 2 * range * sin(half-angle), which is WIDER THAN THE SWING IS LONG for")
	print("   every class in the roster. Widening the lane to it would draw the blob the")
	print("   maker vetoed (\"i hate that circle thing for brawler\"); narrowing the cone to")
	print("   the lane would make melee a needle. Both are feel calls the maker owns, so")
	print("   the gap is MEASURED here rather than closed by this agent.")
	print("   %-12s %7s %9s %10s %10s %8s" % [
		"class", "range", "halfangle", "coneWidth", "laneWidth", "ratio"])
	var tell_w: float = float(hero_script.get("SWING_TELL_WIDTH"))
	var tell_min: float = float(hero_script.get("SWING_TELL_MIN_WIDTH"))
	for cls: int in cfgs.keys():
		var r2: float = float((cfgs[cls] as Dictionary).get("melee_range", default_range))
		var d2: float = float((cfgs[cls] as Dictionary).get("melee_arc_dot", default_dot))
		var a2: float = acos(clampf(d2, -1.0, 1.0))
		var cone_w: float = 2.0 * r2 * sin(a2)
		var lane_w: float = maxf(r2 * tell_w, tell_min)
		print("   %-12s %7.1f %8.1f° %10.1f %10.1f %7.1fx" % [
			str(names[cls]) if cls < names.size() else str(cls),
			r2, rad_to_deg(a2), cone_w, lane_w, cone_w / maxf(lane_w, 0.01)])
	print("   hits(px)  = queried cone reach against a standard 31 px enemy")
	print("   drawn(px) = how far the SwingArc crescent visibly travels from the origin")
	print("   ⚠ tipOff is measured AT REST, where the lead arm hangs BACK — hence the")
	print("     negative sign. Mid-swing the arm is forward, so `drawn` here is a LOWER")
	print("     bound on the crescent's real reach. The guard in")
	print("     tools/slice_test_hitboxes.gd pins the tip-independent half (range *")
	print("     1.147 vs range + margin), which is the part that cannot move under it.")
	if hero != null and is_instance_valid(hero):
		hero.queue_free()
