extends SceneTree
## HOW MUCH IS ON SCREEN AT ONCE, SAMPLED THROUGH A REAL BOT FIGHT?
##
## Maker: *"there is currently near the middle of a fight way too much going on for the
## user to understand"*. "Too much" has been answered twice by tuning constants; this
## asks what the number actually IS, second by second, so the next change is aimed
## rather than sprayed.
##
## Samples every 0.25 s and reports the distribution — not just a peak, because a single
## spike is a moment and a sustained plateau is the problem being described. The MIDDLE
## of the fight is reported separately from the whole, since that is the window named.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_fight_density.gd

const MATCH := "res://scenes/combat/BotMatch.tscn"
const SAMPLE_EVERY: float = 0.25
const RUN_SECONDS: float = 26.0

var _t: float = 0.0
var _next: float = 0.0
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var scene: Node = (load(MATCH) as PackedScene).instantiate()
	root.add_child(scene)
	# Let the intro card and the opening beat pass — the fight is not the bell.
	for _i in 240:
		await physics_frame

	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	while _t < RUN_SECONDS:
		await physics_frame
		_t += 1.0 / 60.0
		if _t < _next:
			continue
		_next = _t + SAMPLE_EVERY
		_rows.append({
			"t": _t,
			# Live SPECTACLES — the reactor's own census, i.e. anything carrying an
			# `element_id`. This is the number austerity() is derived from.
			"spectacle": int(reactor.call("spectacle_count")) if reactor != null else 0,
			# Everything the eye has to parse, counted as nodes actually in the tree.
			"vfx": _count_group(&"vfx") + _count_class("CombatVfx"),
			"debris": _count_class("DebrisChunk"),
			"ghosts": _count_class("RigGhost"),
			"telegraph": _count_group(&"telegraph"),
			"projectile": _count_group(&"enemy_projectile") + _count_group(&"player_spell"),
			"children": root.get_child_count(),
		})
	_report()
	quit()


func _count_group(g: StringName) -> int:
	return root.get_tree().get_nodes_in_group(g).size()


## Count live nodes whose script is `name`.gd — the spectacles do not share a group.
func _count_class(cls: String) -> int:
	var n: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var sc: Script = node.get_script() as Script
		if sc != null and sc.resource_path.ends_with("/%s.gd" % cls):
			n += 1
		for c: Node in node.get_children():
			stack.append(c)
	return n


func _report() -> void:
	if _rows.is_empty():
		print("PROBE ABORTED: no samples — the match never ran")
		return
	print("\n== ON-SCREEN DENSITY THROUGH ONE BOT FIGHT (%d samples) ==" % _rows.size())
	print("  t      spect  vfx  debris ghost tele proj")
	for r: Dictionary in _rows:
		print("  %5.1f   %4d %5d %6d %5d %4d %4d"
			% [r["t"], r["spectacle"], r["vfx"], r["debris"], r["ghosts"],
				r["telegraph"], r["projectile"]])
	# The window the maker named.
	var lo: float = RUN_SECONDS * 0.33
	var hi: float = RUN_SECONDS * 0.67
	for key: String in ["spectacle", "vfx", "debris", "ghosts"]:
		var all: Array[int] = []
		var mid: Array[int] = []
		for r: Dictionary in _rows:
			all.append(int(r[key]))
			if float(r["t"]) >= lo and float(r["t"]) <= hi:
				mid.append(int(r[key]))
		print("  %-10s whole fight  mean %5.1f  peak %3d   |   MIDDLE THIRD  mean %5.1f  peak %3d"
			% [key, _mean(all), _peak(all), _mean(mid), _peak(mid)])


func _mean(a: Array[int]) -> float:
	if a.is_empty():
		return 0.0
	var s: int = 0
	for v: int in a:
		s += v
	return float(s) / float(a.size())


func _peak(a: Array[int]) -> int:
	var m: int = 0
	for v: int in a:
		m = maxi(m, v)
	return m
