# DOES A STRIKE ACTUALLY LAND ON A TOWN DUMMY?
#
#   Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#       --script tools/probe_town_strike.gd
#
# THE REPORT THIS ANSWERS. Maker, playing: *"strike isnt regstering in the training"*.
# That has two possible meanings and they lead to opposite fixes:
#
#   a) the COACH never advances past its Strike step, or
#   b) the blow lands on nothing and the dummy takes no damage.
#
# (a) has a root cause already: `melee` is bound to physical keycode 70 — the letter F —
# and NOTHING on screen ever says so. No lesson step names its key, the card's only hint
# is "Press it to continue", and the desktop hotbar advertises RMB, Spc and 1-4 but never
# the strike. On mobile the melee IS the primary pad button, so the verb is central to
# the design and only the desktop affordance is missing.
#
# This exists to settle (b) independently, because fixing the label while the damage path
# is broken would look like a fix and ship the bug.
#
# ⚠ IT DRIVES THE REAL DAMAGE ENTRY POINT, NOT `Input`. Synthesising an F press proves
# something about the input map, which is already known. What is in question is whether
# the swing's own sweep FINDS a `town_dummy`, so this calls the melee the way the hero's
# own hit frame does and reads the dummy's hp either side.
extends SceneTree

const WORLD: String = "res://scenes/Main.tscn"


func _init() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load(WORLD) as PackedScene
	if packed == null:
		printerr("could not load ", WORLD)
		quit(1)
		return
	root.add_child(packed.instantiate())
	for i: int in 20:
		await process_frame

	var dummies: Array = root.get_tree().get_nodes_in_group(&"town_dummy")
	var heroes: Array = root.get_tree().get_nodes_in_group(&"hero")
	var player: Node = null
	for h: Node in heroes:
		if not h.is_in_group(&"town_dummy"):
			player = h
			break

	print("")
	print("town_dummy bodies : %d" % dummies.size())
	print("hero bodies       : %d" % heroes.size())
	print("the player        : %s" % ("<none>" if player == null else String(player.name)))
	if player == null or dummies.is_empty():
		printerr("nothing to test with")
		quit(1)
		return

	print("")
	print("player faction    : %s   hostile_group: %s"
		% [String(player.get("faction_group")), String(player.get("hostile_group"))])
	print("attack scans      : %s   (hostile_group with friendly fire folded in)"
		% String(player.call("attack_group")))
	var d: Node = dummies[0]
	print("dummy groups      : %s" % [d.get_groups()])
	print("dummy in that group? %s"
		% ("YES" if d.is_in_group(String(player.call("attack_group"))) else "NO"))

	# Stand the player next to the dummy so the swing has something in reach, face it,
	# and swing. hp is read either side — that is the whole measurement.
	var dp: Vector2 = (d as Node2D).global_position
	(player as Node2D).global_position = dp + Vector2(-26.0, 0.0)
	player.set("facing", Vector2.RIGHT)
	for i: int in 4:
		await process_frame

	var before: float = float(d.get("hp"))
	var swung: bool = false
	# `_melee` is the swing itself; `_on_melee_hit_frame` is the sweep the rig's own
	# hit_frame signal fires frames later. Driving `_melee` exercises both.
	for m: String in ["_melee", "_primary_melee_combo", "_on_melee_hit_frame"]:
		if player.has_method(m):
			print("\ndriving %s() ..." % m)
			player.call(m)
			swung = true
			break
	if not swung:
		print("\nno melee entry point found on the hero — methods containing 'melee':")
		for mm: Dictionary in player.get_method_list():
			var n: String = String(mm.get("name", ""))
			if n.findn("melee") >= 0 or n.findn("attack") >= 0:
				print("    %s" % n)
		quit(2)
		return

	# ⚠ WATCH THE SWING WINDOW, or this harness cannot tell "the sweep missed" from
	# "no swing ever happened". `_on_melee_hit_frame` early-outs on
	# `_swing_window <= 0.0`, and the window is opened by `_melee` and closed by the
	# rig's own `hit_frame` — which is animation-driven, and a headless run still
	# processes the rig but nothing here had checked that it does.
	var peak: float = 0.0
	var frames_open: int = 0
	for i: int in 60:
		await process_frame
		var w: float = float(player.get("_swing_window"))
		peak = maxf(peak, w)
		if w > 0.0:
			frames_open += 1
	print("  swing window: peak %.3f, open for %d of 60 frames" % [peak, frames_open])
	print("  distance to dummy: %.1f px"
		% (player as Node2D).global_position.distance_to(dp))
	var reach: Variant = player.get("_melee_range")
	if reach != null:
		print("  melee range   : %s" % [reach])
	# ── ISOLATE THE SWEEP FROM THE ANIMATION ────────────────────────────────────
	# The window opened and closed without damage, which has two causes: the rig's
	# `hit_frame` never fired (animation-driven, so possibly a headless artifact), or
	# the sweep ran and found nothing. Force the window open and call the handler
	# directly — that tests the SWEEP alone.
	var mid: float = float(d.get("hp"))
	# ⚠ FACING IS SET IN THE SAME BREATH AS THE SWEEP, and the first version of this
	# probe is why. `facing` is aim-driven (twin-stick: the lead hand tracks the
	# cursor), so a `facing = RIGHT` written 60 frames earlier had been overwritten to
	# (-0.71, -0.71) by the time the sweep ran — the player was facing AWAY, the cone's
	# dot came out -0.708 against a 0.250 threshold, and the harness reported "the
	# strike does not damage dummies". That would have been a fabricated bug report.
	player.set("facing", (dp - (player as Node2D).global_position).normalized())
	player.set("_swing_window", 0.3)
	player.call("_on_melee_hit_frame")
	for i: int in 6:
		await process_frame
	var swept: float = float(d.get("hp"))
	print("")
	print("  sweep called DIRECTLY: dummy hp %.1f -> %.1f   %s"
		% [mid, swept, "sweep works" if swept < mid else "SWEEP ITSELF FINDS NOTHING"])
	# ── WHICH FILTER REJECTS IT ─────────────────────────────────────────────────
	# `in_cone` applies three: reach to the silhouette, the facing dot, and a
	# line-of-sight ray. Ask it directly, then ask the same question with the pieces
	# separated, so the answer names a filter rather than "it returned nothing".
	var grp: Array = root.get_tree().get_nodes_in_group(String(player.call("attack_group")))
	var cone: Array = SpellTargets.in_cone((player as Node2D).global_position,
		player.get("facing"), float(player.get("_melee_range")),
		float(player.get("_melee_arc_dot")), grp, [player], player)
	print("")
	print("  in_cone() over group '%s' (%d bodies) -> %d hit(s)"
		% [String(player.call("attack_group")), grp.size(), cone.size()])
	var toward: Vector2 = (dp - (player as Node2D).global_position).normalized()
	var f: Vector2 = player.get("facing")
	print("  facing %s  toward %s  dot %.3f  (needs > %.3f)"
		% [f, toward, f.dot(toward), float(player.get("_melee_arc_dot"))])
	# Line of sight, asked on its own.
	var space: PhysicsDirectSpaceState2D = (player as Node2D).get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(
		(player as Node2D).global_position, dp)
	q.exclude = [(player as CollisionObject2D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	print("  line of sight : %s" % ("CLEAR" if hit.is_empty()
		else "BLOCKED by %s" % [hit.get("collider")]))
	var after: float = float(d.get("hp"))
	print("")
	print("dummy hp %.1f -> %.1f   %s" % [before, after,
		"THE STRIKE LANDS" if after < before else "NO DAMAGE — the sweep found nothing"])
	quit(0 if after < before else 3)
