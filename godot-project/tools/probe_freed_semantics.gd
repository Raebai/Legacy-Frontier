# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_freed_semantics.gd
#
# SCRATCH PROBE — measure, do not assume, what a FREED Object does in Godot 4.6.2.
# Two contradictory claims were in play: the bug report's "a freed Object compares
# EQUAL TO null", and this repo's own comment in BossModRider.nearest_hero ("a freed
# Object is not null"). Only one can be true and the fix depends on which.
extends SceneTree


func _process(_d: float) -> bool:
	var n: Node = Node.new()
	var holder: Array = [n]
	var dict_holder: Dictionary = {"n": n}
	n.free()

	print("== raw comparisons ==")
	print("  arr[0] == null            -> ", holder[0] == null)
	print("  arr[0] != null            -> ", holder[0] != null)
	print("  is_instance_valid(arr[0]) -> ", is_instance_valid(holder[0]))
	print("  typeof(arr[0])            -> ", typeof(holder[0]), " (OBJECT=", TYPE_OBJECT, ")")

	print("== the EliteHerald._restore line 119 shape ==")
	print("  about to do: var e: Node = dict['n'] where dict['n'] is freed")
	var e: Node = dict_holder["n"]           # <-- expected fault site
	print("  SURVIVED the typed assignment; e == null -> ", e == null)
	print("  is_instance_valid(e) -> ", is_instance_valid(e))

	print("== the untyped shape ==")
	var v: Variant = dict_holder["n"]
	print("  untyped assign ok; is_instance_valid(v) -> ", is_instance_valid(v))
	return true
