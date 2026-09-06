# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_plate_in_real_scenes.gd
#
# DOES THE HERO'S SCREEN PLATE RESOLVE IN A SCENE THE GAME ACTUALLY BUILDS?
#
# ⚠ WHY THIS EXISTS. `slice_test_hero_plate` and `probe_hero_hud` both build their own
# fighter and then `root.add_child(layer)` — they parent the hotbar's CanvasLayer
# DIRECTLY to the scene-tree root. `CharacterBars._find_bound_ability_bar` walks
# `tree.root.get_children()` and only descends into children that ARE CanvasLayers, so
# that one arrangement is the only one it can find. No scene in this game uses it:
# `Arena`, `LocalCoop._build_bar_for` and `World._spawn_hud` all `add_child(layer)` onto
# THEMSELVES, one level below the root. So both instruments were measuring a shape that
# only they produce.
#
# This one boots the REAL scenes and prints what a player gets. It asserts nothing — it
# is a probe, and the number is the point.
extends SceneTree

const TOWN: String = "res://scenes/Main.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out


func _run() -> void:
	# Headless has no window and therefore no aspect; without this the viewport reports
	# a square 640x640 and `_layout_plate` is measured against a screen that does not
	# exist. See the ⚠ in `probe_hero_hud`.
	root.size = Vector2i(640, 360)
	await process_frame
	var packed: PackedScene = load(TOWN)
	if packed == null:
		printerr("probe_plate: could not load %s" % TOWN)
		quit(1)
		return
	var town: Node = packed.instantiate()
	root.add_child(town)
	# The plate polls for `PLATE_WINDOW` (4 s) at `PLATE_POLL` (0.25 s), so a handful of
	# frames is not enough — wait past the whole window before believing a "no".
	for i: int in 300:
		await process_frame

	var bars: Array[Node] = []
	var bar_hosts: Array[String] = []
	for n: Node in _all(town):
		if n.get_class() == "Node2D" and n.has_method("has_plate"):
			bars.append(n)
			bar_hosts.append(String(n.get_parent().name))
	print("[probe_plate] TOWN: %d CharacterBars found" % bars.size())
	for i: int in bars.size():
		var b: Node = bars[i]
		var host: Node = b.get_parent()
		var is_local: bool = host.is_in_group("player")
		print("   %-22s local=%-5s plate=%-5s head_bar=%s"
			% [bar_hosts[i], str(is_local), str(bool(b.call("has_plate"))),
				str(bool(b.call("draws_head_bar")))])

	# And where the hotbars actually live, which is the whole question.
	for n: Node in _all(town):
		if n is CanvasLayer:
			var depth: int = 0
			var walk: Node = n
			while walk != null and walk != root:
				depth += 1
				walk = walk.get_parent()
			print("[probe_plate] CanvasLayer '%s' sits %d levels under root (the search"
				% [n.name, depth] + " only enters CanvasLayers at depth 1)")
	quit(0)
