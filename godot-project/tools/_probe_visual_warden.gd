# READ-ONLY DIAGNOSTIC. Run with the GUI binary (captures need a real renderer):
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_visual_warden.gd
#
# WHY THIS EXISTS: tools/probe_town_feet.gd finds a rig with `get_node_or_null(^"Rig")`.
# A townsperson's rig is built in code (`CharacterRig.new()` in NPC._ready), so it is
# named "@Node2D@nn" and the existing probe SKIPS EVERY NPC. The Warden has never been
# measured by it. This walks the tree and finds a CharacterRig by TYPE instead.
#
# It also freezes the hop (a townsperson bounces on a random timer, so any capture can
# catch one mid-air and slander the rig) and then takes tight big shots.
extends SceneTree

const TOWN: String = "res://scenes/Main.tscn"


func _initialize() -> void:
	Engine.max_fps = 60
	var town: Node = (load(TOWN) as PackedScene).instantiate()
	root.add_child(town)
	_run.call_deferred(town)


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out


func _find_rig(n: Node) -> CharacterRig:
	for c: Node in n.get_children():
		if c is CharacterRig:
			return c as CharacterRig
	return null


## Lowest bottom edge of the body's own rectangle colliders, in LOCAL y.
func _box_bottom(n: Node) -> float:
	var out: float = INF
	for c: Node in n.get_children():
		if not (c is CollisionShape2D):
			continue
		var s: Shape2D = (c as CollisionShape2D).shape
		if not (s is RectangleShape2D):
			continue
		var b: float = (c as CollisionShape2D).position.y + (s as RectangleShape2D).size.y * 0.5
		out = b if not is_finite(out) else maxf(out, b)
	return out


func _ground(body: Node2D, h: float) -> float:
	var q := PhysicsRayQueryParameters2D.create(
		body.global_position + Vector2(0.0, -h * 0.5),
		body.global_position + Vector2(0.0, h * 1.5),
		int(CharacterRig.GROUND_MASK))
	q.collide_with_areas = false
	var hit: Dictionary = body.get_world_2d().direct_space_state.intersect_ray(q)
	return INF if hit.is_empty() else (hit["position"] as Vector2).y


func _label(n: Node) -> String:
	for g: StringName in [&"player", &"town_dummy", &"npc"]:
		if n.is_in_group(g):
			var d: Variant = n.get("data")
			var who: String = ""
			if d != null and d.get("npc_id") != null:
				who = ":" + String(d.get("npc_id"))
			return "%s(%s%s)" % [n.name.substr(0, 10), String(g), who]
	return String(n.name).substr(0, 22)


func _run(town: Node) -> void:
	for i: int in 90:
		await physics_frame

	# ── FREEZE THE HOP so nothing below is a body caught mid-air ──────────────
	for n: Node in _all(town):
		if n.is_in_group(&"npc"):
			n.set("_hop_wait", 9999.0)
			(n as CharacterBody2D).velocity = Vector2.ZERO
	for i: int in 90:
		await physics_frame

	print("")
	print("body                       body_y  onfloor  vel.y  boxbot  rig.y  height  FEET   GROUND   SINK")
	print("--------------------------------------------------------------------------------------------")
	for n: Node in _all(town):
		if not (n is Node2D):
			continue
		var rig: CharacterRig = _find_rig(n)
		if rig == null:
			continue
		var b := n as Node2D
		var h: float = rig.height
		var feet: float = b.global_position.y + rig.position.y + h * 0.5
		var g: float = _ground(b, h)
		var on_floor: Variant = (n as CharacterBody2D).is_on_floor() if n is CharacterBody2D else null
		var vy: float = (n as CharacterBody2D).velocity.y if n is CharacterBody2D else NAN
		print("%-24s %7.2f %8s %6.1f %7.2f %6.2f %7.2f %7.2f %8.2f %7.2f" % [
			_label(n), b.global_position.y, str(on_floor), vy,
			_box_bottom(n), rig.position.y, h, feet, g, feet - g])

	# ── THE DRAWN CHANNEL, NOT THE COMPUTED ONE ──────────────────────────────
	# `feet` above is arithmetic on the node transform. This asks the rig for the pose
	# it is about to DRAW and reports where those feet actually land in world y.
	print("")
	print("body                     grnd state limp airloose gaitrdy  groundY   ride  headY   hipY  footLeadY footOffY")
	print("-------------------------------------------------------------------------------------------------------")
	for n: Node in _all(town):
		if not (n is Node2D):
			continue
		var rig: CharacterRig = _find_rig(n)
		if rig == null:
			continue
		var p: Dictionary = rig.call("_sim_pose")
		print("%-24s %5s %5s %4.2f %8.3f %7s %8.2f %6.2f %6.2f %6.2f %9.2f %8.2f" % [
			_label(n), str(rig.get("_grounded")), str(rig.get("state")),
			float(rig.get("_limp")), float(rig.get("_air_loose")),
			str(rig.get("_gait_ready")), float(rig.get("_ground_world_y")),
			float(rig.get("_ride")),
			rig.to_global(p["head_center"] as Vector2).y, rig.to_global(p["hip"] as Vector2).y,
			rig.to_global(p["foot_lead"] as Vector2).y,
			rig.to_global(p["foot_off"] as Vector2).y])

	# ── WHAT DOES THE RIG'S OWN DOWNWARD RAY ACTUALLY HIT? ───────────────────
	# The rig probes on GROUND_MASK from its own origin. If a townsperson's BODY is on
	# that layer, the townsperson is floor to himself.
	print("")
	for n: Node in _all(town):
		var rig: CharacterRig = _find_rig(n)
		if rig == null:
			continue
		var lay: Variant = (n as CollisionObject2D).collision_layer if n is CollisionObject2D else -1
		var msk: Variant = (n as CollisionObject2D).collision_mask if n is CollisionObject2D else -1
		var q := PhysicsRayQueryParameters2D.create(
			rig.global_position + Vector2(0.0, -rig.height * 0.5),
			rig.global_position + Vector2(0.0, rig.height * 1.5),
			int(CharacterRig.GROUND_MASK))
		q.collide_with_areas = false
		var hit: Dictionary = rig.get_world_2d().direct_space_state.intersect_ray(q)
		var who: String = "(nothing)"
		if not hit.is_empty():
			var c: Object = hit["collider"]
			who = "%s [%s] y=%.2f" % [
				(c as Node).name, (c as Node).get_class(), (hit["position"] as Vector2).y]
			if c == n:
				who += "   <<< ITS OWN BODY"
		print("%-24s layer=%s mask=%s  ray hits: %s" % [_label(n), str(lay), str(msk), who])

	# ── AND NOW LOOK AT HIM, BIG ─────────────────────────────────────────────
	# The HUD is a CanvasLayer and does not scroll with the camera, so at any real
	# zoom the ability bar sits on top of the subject. Off, or the shot is of a bar.
	for c: Node in _all(town):
		if c is Camera2D:
			(c as Camera2D).enabled = false
		elif c is CanvasLayer:
			(c as CanvasLayer).visible = false
	var cam := Camera2D.new()
	town.add_child(cam)
	cam.make_current()
	var shots: Array[Dictionary] = [
		{"out": "user://_pv_warden_big.png", "x": 320.0, "y": 425.0, "zoom": 5.0},
		{"out": "user://_pv_doorkeeper_big.png", "x": 862.0, "y": 425.0, "zoom": 5.0},
		{"out": "user://_pv_player_big.png", "x": 866.0, "y": 425.0, "zoom": 5.0},
		{"out": "user://_pv_pair.png", "x": 600.0, "y": 420.0, "zoom": 1.6},
	]
	for s: Dictionary in shots:
		cam.position = Vector2(float(s["x"]), float(s["y"]))
		cam.zoom = Vector2(float(s["zoom"]), float(s["zoom"]))
		for i: int in 20:
			await process_frame
		var img: Image = root.get_texture().get_image()
		print("%s %s" % ["ok " if img.save_png(String(s["out"])) == OK else "ERR", s["out"]])

	# ══ THE PROPOSED FIX, APPLIED AT RUNTIME ═════════════════════════════════
	# NPC.tscn MEANS to put a townsperson on layer 2 but writes it as an attribute
	# inside the [node] header, where the scene parser ignores it — so the body ships
	# on layer 1, which IS CharacterRig.GROUND_MASK. Setting the property for real is
	# the whole patch; if the legs come back here, the .tscn line is the fix.
	for n: Node in _all(town):
		if n.is_in_group(&"npc"):
			(n as CollisionObject2D).collision_layer = 2
	for i: int in 60:
		await physics_frame
	print("")
	print("AFTER collision_layer = 2:")
	for n: Node in _all(town):
		if not n.is_in_group(&"npc"):
			continue
		var rig2: CharacterRig = _find_rig(n)
		var p2: Dictionary = rig2.call("_sim_pose")
		print("  %-22s groundY=%.2f hipY=%.2f footLeadY=%.2f footOffY=%.2f  legLen=%.2f" % [
			_label(n), float(rig2.get("_ground_world_y")),
			rig2.to_global(p2["hip"] as Vector2).y,
			rig2.to_global(p2["foot_lead"] as Vector2).y,
			rig2.to_global(p2["foot_off"] as Vector2).y,
			rig2.to_global(p2["foot_off"] as Vector2).y - rig2.to_global(p2["hip"] as Vector2).y])
	cam.position = Vector2(320.0, 425.0)
	cam.zoom = Vector2(5.0, 5.0)
	for i: int in 20:
		await process_frame
	var fixed: Image = root.get_texture().get_image()
	print("%s user://_pv_warden_FIXED.png"
		% ["ok " if fixed.save_png("user://_pv_warden_FIXED.png") == OK else "ERR"])
	quit(0)
