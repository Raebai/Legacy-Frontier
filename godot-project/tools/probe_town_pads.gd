# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_town_pads.gd
#
# ══ WHERE EVERYTHING IN THE TOWN ACTUALLY STANDS, AND WHOSE PROMPT REACHES WHOSE ══
#
# This is a PROBE, not a test: it asserts nothing and always exits 0. Its whole job is
# to print the one number that reasoning about this room keeps getting wrong — how far
# apart two things that both put an "[E] ..." label on the screen really are.
#
# ⚠ WHY IT HAD TO BUILD THE REAL SCENE. Every gap below could be arithmetic on the
# constants in `World.gd`, and that arithmetic has been wrong twice:
#
#   * the lectern and the Archivist shipped 58 px apart against a 46 px ring, so two
#     hints fought for one corner and the `talk` press went to whichever node the tree
#     reached first;
#   * the WARDEN's 40 px ring reached x=384 against the armoury pad at x=380 — a
#     townsperson and a station overlapping, which no amount of staring at the pad row's
#     own spacing constants can show you, because the two live in different files and
#     one of them MOVES.
#
# The second one is the reason this reads the live scene. A patrol is not a position, it
# is a SPAN, and a townsperson who starts clear of a pad still walks into it a second
# later. Both extremes are printed.
#
# READING THE OUTPUT: every `clear` figure is `centre distance - (ring + ring)`.
#   * positive  — the two prompts can never be on screen together. This is what you want.
#   * zero      — they touch at exactly one point.
#   * NEGATIVE  — ⚠ two "[E] ..." labels at once. `Interactables.wins()` arbitrates by
#                 distance so the press still lands somewhere sensible, but the PLAYER
#                 cannot tell which, and that is the bug.
extends SceneTree

const TOWN_SCENE: String = "res://scenes/Main.tscn"
const WORLD_SCRIPT: String = "res://scripts/World.gd"
const STATION_SCRIPT: String = "res://scripts/ArmoryStation.gd"
const NPC_SCRIPT: String = "res://scripts/NPC.gd"
const DOOR_SCRIPT: String = "res://scripts/TowerDoor.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	quit(0)
	return true


func _run() -> void:
	var packed: PackedScene = load(TOWN_SCENE)
	if packed == null:
		printerr("probe_town_pads: %s did not load" % TOWN_SCENE)
		return
	var town: Node = packed.instantiate()
	root.add_child(town)

	var world: GDScript = load(WORLD_SCRIPT) as GDScript
	var wc: Dictionary = world.get_script_constant_map()
	var spawn: Vector2 = wc.get("PLAYER_SPAWN", Vector2.ZERO)

	print("")
	print("== THE TOWN, MEASURED =====================================================")
	print("  scene            %s" % TOWN_SCENE)
	print("  street           x 0 .. %.0f" % float(wc.get("TOWN_WIDTH", 0.0)))
	print("  PLAYER_SPAWN     x %.0f   (TOWER_X %.0f - 128)"
		% [spawn.x, float(wc.get("TOWER_X", 0.0))])
	print("  PAD_FIRST_X %.0f  PAD_STEP %.0f"
		% [float(wc.get("PAD_FIRST_X", 0.0)), float(wc.get("PAD_STEP", 0.0))])

	# -- the pads --------------------------------------------------------------
	# Sorted by x so "neighbour" means what it looks like on screen. The ring is read
	# off the live script rather than re-typed here — a duplicated literal would agree
	# with the code by construction and prove nothing.
	var pads: Array = []
	_find(town, STATION_SCRIPT, pads)
	var pad_ring: float = float(load(STATION_SCRIPT).get("PROXIMITY_RADIUS"))
	var rows: Array = []
	for p: Node in pads:
		rows.append({"x": (p as Node2D).global_position.x, "kind": String(p.get("kind"))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["x"]) < float(b["x"]))

	print("")
	print("-- PADS (%d) -- ring %.0f px, so two pads need %.0f px of centre gap --"
		% [rows.size(), pad_ring, pad_ring * 2.0])
	print("   %-10s %7s %6s %14s %10s  %s"
		% ["kind", "x", "ring", "hint spans", "gap to L", "vs spawn"])
	for i: int in rows.size():
		var x: float = float(rows[i]["x"])
		var gap_l: String = "--"
		if i > 0:
			var d: float = x - float(rows[i - 1]["x"])
			gap_l = "%.0f%s" % [d, "" if d >= pad_ring * 2.0 else " !INSIDE RING"]
		print("   %-10s %7.0f %6.0f  %6.0f..%-6.0f %10s  %s"
			% [rows[i]["kind"], x, pad_ring, x - pad_ring, x + pad_ring, gap_l,
				("behind you  OK" if x < spawn.x
					else "!! PAST THE SPAWN - you walk back to it")])

	# -- the townsfolk ---------------------------------------------------------
	# The patrol SPAN, not the frame-one position. A townsperson who starts clear of a
	# pad and paces into it is the failure this whole probe exists for.
	var folk: Array = []
	_find(town, NPC_SCRIPT, folk)
	var people: Array = []
	for entry: Dictionary in (wc.get("TOWNSFOLK", []) as Array):
		var cx: float = float(entry.get("x", 0.0))
		var rng: float = float(entry.get("range", 0.0))
		people.append({
			"who": String(entry.get("res", "?")).get_file().get_basename(),
			"lo": cx - rng, "hi": cx + rng, "ring": _npc_ring(folk, cx),
		})

	print("")
	print("-- TOWNSFOLK (%d in the table, %d in the room) --" % [people.size(), folk.size()])
	print("   %-12s %14s %6s %16s  %s"
		% ["who", "paces", "ring", "hint spans", "clear of spawn"])
	for pr: Dictionary in people:
		var lo: float = float(pr["lo"])
		var hi: float = float(pr["hi"])
		var ring: float = float(pr["ring"])
		# How close their hint gets to the doorstep you materialise on. `slice_test_
		# town_interact` fails if this is negative; it shipped negative once, and the
		# doorkeeper spent every boot frozen and hint-lit on the player's spawn.
		var to_spawn: float = minf(absf(spawn.x - lo), absf(spawn.x - hi)) - ring
		var inside: bool = spawn.x >= lo and spawn.x <= hi
		print("   %-12s %6.0f..%-6.0f %6.0f  %7.0f..%-6.0f  %s"
			% [pr["who"], lo, hi, ring, lo - ring, hi + ring,
				("!! SPAWN IS INSIDE THEIR PATROL" if inside
					else ("%.0f px  OK" % to_spawn if to_spawn >= 0.0
						else "!! %.0f px - their prompt is up on frame one" % to_spawn))])

	# -- the crossing ----------------------------------------------------------
	# THE POINT OF THE FILE. Everything above is one list each; this is the pair.
	print("")
	print("-- PAD x TOWNSPERSON -- do two prompts fight for one spot? --")
	print("   %-10s %-12s %11s  %s" % ["pad", "who", "centre gap", "clear"])
	var worst: float = 1e9
	var worst_msg: String = "nothing measured"
	for r: Dictionary in rows:
		for pr2: Dictionary in people:
			var px: float = float(r["x"])
			# Distance from the pad's centre to the NEAREST point of the span they pace.
			var d2: float = maxf(maxf(float(pr2["lo"]) - px, px - float(pr2["hi"])), 0.0)
			var clear: float = d2 - (pad_ring + float(pr2["ring"]))
			if clear < worst:
				worst = clear
				worst_msg = "%s x %s" % [r["kind"], pr2["who"]]
			print("   %-10s %-12s %11.0f  %s"
				% [r["kind"], pr2["who"], d2,
					("%.0f px  OK" % clear if clear >= 0.0
						else "!! %.0f px - BOTH HINTS UP, arbitrated by distance only" % clear)])

	# -- the way out -----------------------------------------------------------
	var doors: Array = []
	_find(town, DOOR_SCRIPT, doors)
	var door_ring: float = float(load(DOOR_SCRIPT).get("PROXIMITY_RADIUS"))
	for d3: Node in doors:
		var dx: float = (d3 as Node2D).global_position.x
		print("")
		print("-- THE DOOR -- x %.0f, ring %.0f, spans %.0f..%.0f"
			% [dx, door_ring, dx - door_ring, dx + door_ring])
		print("   the spawn at x %.0f is %s the door's ring - the town costs %s to leave"
			% [spawn.x, "INSIDE" if absf(dx - spawn.x) < door_ring else "!! OUTSIDE",
				"one press" if absf(dx - spawn.x) < door_ring else "!! A WALK"])

	# -- the screens the pads open ---------------------------------------------
	# ⚠ NOT DECORATION. The class pad opens the `Outfitter`, whose class button opens
	# `ClassSelect`, whose armory button opens `Loadout` — and both of those are
	# autoloads on their OWN CanvasLayer. If the town's overlay layer is HIGHER than
	# theirs, the second screen opens BEHIND the first one's 0.93-opaque dimmer and the
	# player sees a dead button. It was 95 against their 90; that is what this prints.
	print("")
	print("-- OVERLAY LAYERS -- the town's screen must sit BELOW the autoload panels --")
	print("   %-22s %6s" % ["World.OVERLAY_LAYER", str(int(wc.get("OVERLAY_LAYER", -1)))])
	for path: String in ["/root/ClassSelect", "/root/Loadout"]:
		var n: Node = root.get_node_or_null(NodePath(path))
		if n == null:
			print("   %-22s %6s  (autoload not registered in this harness)" % [path, "--"])
			continue
		var lay: int = int(n.get("layer"))
		print("   %-22s %6d  %s" % [path, lay,
			("OK - opens on top of the town screen" if lay > int(wc.get("OVERLAY_LAYER", -1))
				else "!! BEHIND the town screen's dimmer")])

	print("")
	print("TIGHTEST PROMPT CLEARANCE IN THE ROOM: %.0f px (%s)" % [worst, worst_msg])
	print("")


## The live hint radius off a townsperson's own `ProximityArea`, matched to the table
## row by position. Read rather than re-typed: `scenes/NPC.tscn` owns that number and a
## literal here would silently keep printing 40 after somebody changed it to 60.
func _npc_ring(folk: Array, near_x: float) -> float:
	var best: Node2D = null
	var best_d: float = 1e9
	for n: Node in folk:
		var n2: Node2D = n as Node2D
		if n2 == null:
			continue
		var d: float = absf(n2.global_position.x - near_x)
		if d < best_d:
			best_d = d
			best = n2
	if best == null:
		return 0.0
	var area: Area2D = best.get_node_or_null(^"ProximityArea") as Area2D
	if area == null:
		return 0.0
	for c: Node in area.get_children():
		var cs: CollisionShape2D = c as CollisionShape2D
		if cs != null and cs.shape is CircleShape2D:
			return (cs.shape as CircleShape2D).radius
	return 0.0


func _find(from: Node, script_path: String, out: Array) -> void:
	var s: Script = from.get_script() as Script
	if s != null and s.resource_path == script_path:
		out.append(from)
	for c: Node in from.get_children():
		_find(c, script_path, out)
