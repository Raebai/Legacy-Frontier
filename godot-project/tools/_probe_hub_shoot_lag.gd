# READ-ONLY DIAGNOSTIC. GUI BINARY ONLY.
#   Godot_v4.6.2-stable_win64.exe --path godot-project --script tools/_probe_hub_shoot_lag.gd
#
# MAKER: "it lags when I try shoot an NPC or the teleportation rings in the hub,
# probably because you are treating them like items."
#
# Shooting into empty air is the CONTROL and shooting a townsperson is the TEST, in
# the same room in the same run, so the number is a difference and not an impression.
# Frame time is sampled with `Time.get_ticks_usec` around the render, and the live
# node count comes with it — a leak and a stall look identical from the inside of a
# frame, and they want opposite fixes.
extends SceneTree

const TOWN: String = "res://scenes/Main.tscn"
const SAMPLES: int = 240

var _root: Node = null


func _initialize() -> void:
	Engine.max_fps = 0   # uncapped: a 60 fps cap would HIDE the very stall being hunted
	_root = (load(TOWN) as PackedScene).instantiate()
	root.add_child(_root)
	_run.call_deferred()


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out


func _run() -> void:
	for i: int in 150:
		await process_frame

	var hero: Node2D = root.get_tree().get_first_node_in_group("player") as Node2D
	if hero == null:
		printerr("[hublag] no player"); quit(1); return
	var npcs: Array = root.get_tree().get_nodes_in_group("npc")
	if npcs.is_empty():
		printerr("[hublag] no townsfolk"); quit(1); return
	var npc: Node2D = npcs[0] as Node2D
	print("[hublag] hero=%s  townsfolk=%d  first=%s layer=%s groups=%s"
		% [hero.name, npcs.size(), npc.name, npc.get("collision_layer"), str(npc.get_groups())])
	print("[hublag] hero hostile_group=%s" % [str(hero.get("hostile_group"))])

	# CONTROL: aim at open sky, well away from every body in the room.
	await _burst(hero, Vector2.UP, "CONTROL  (into empty air)")
	# TEST: aim along the line to the nearest townsperson and stand next to them.
	hero.global_position = npc.global_position + Vector2(-90.0, 0.0)
	for i: int in 30:
		await process_frame
	await _burst(hero, Vector2.RIGHT, "TEST     (at a townsperson)")
	quit(0)


func _burst(hero: Node2D, dir: Vector2, label: String) -> void:
	hero.set("_aim_dir", dir)
	hero.set("facing", dir)
	var worst: float = 0.0
	var total: float = 0.0
	var over_16: int = 0
	var nodes_before: int = _all(_root).size()
	for i: int in SAMPLES:
		# Hold the trigger the way a player does, rather than one clean shot: the
		# report is about shooting AT something, and a cooldown-gated cast that is
		# refused still runs every check on the way to refusing.
		if hero.has_method("_cast"):
			hero.call("_cast")
		var t0: int = Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		if ms > 16.7:
			over_16 += 1
	var nodes_after: int = _all(_root).size()
	print("[hublag] %s  mean %.2f ms  worst %.2f ms  frames>16.7ms %d/%d  nodes %d -> %d"
		% [label, total / float(SAMPLES), worst, over_16, SAMPLES, nodes_before, nodes_after])
