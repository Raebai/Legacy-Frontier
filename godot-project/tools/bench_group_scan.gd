# Run: godot --headless --path godot-project --script tools/bench_group_scan.gd
#   optional: ++members=25 ++calls=20000
#
# WHAT DOES `get_nodes_in_group` ACTUALLY COST? There are 144 call sites of it in
# scripts/, several of them per-frame, and two have already been removed as hot-path
# mistakes (DamageNumber's cap check on every hit and DoT tick; ScorchDecal's and
# DebrisChunk's caps on every spawn). Before removing or throttling a third, it is
# worth knowing the unit price rather than assuming it — "group scans are slow" is
# folklore until somebody puts a number on it.
#
# Measures three things at the 25-entity ceiling:
#   RAW SCAN     — `get_nodes_in_group(g)`, which allocates a fresh Array every call.
#   SCAN + WORK  — the same, plus the bounding-box loop CombatCamera._frame_group_update
#                  does with the result. This is the real per-frame shape.
#   SIZE ONLY    — `.size()` on the result, the shape the removed cap checks used
#                  (allocate an array of everything, to read one integer off it).
#
# ⚠ Not a substitute for the frame measurement. A cost that is negligible per call
# can still matter at 144 call sites, and a cost that looks large here can be
# irrelevant if the call happens twice a second. Pair it with
# tools/stress_mobile_entities.gd, which prices the whole frame.
extends SceneTree

const GROUP: StringName = &"bench_group"

var _members: int = 25
var _calls: int = 20000
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_parse_args()
	var host := Node2D.new()
	root.add_child(host)
	for i: int in _members:
		var n := Node2D.new()
		n.position = Vector2(float(i) * 37.0, float(i % 7) * 11.0)
		host.add_child(n)
		n.add_to_group(GROUP)
	print("[scan] members=%d calls=%d" % [_members, _calls])

	var t0: int = Time.get_ticks_usec()
	for c: int in _calls:
		var a: Array = get_nodes_in_group(GROUP)
		if a.is_empty():
			break
	var raw: float = float(Time.get_ticks_usec() - t0) / float(_calls)

	t0 = Time.get_ticks_usec()
	for c: int in _calls:
		var mn := Vector2.ZERO
		var mx := Vector2.ZERO
		for e: Node in get_nodes_in_group(GROUP):
			if e is Node2D and is_instance_valid(e):
				var q: Vector2 = (e as Node2D).global_position
				mn = mn.min(q)
				mx = mx.max(q)
	var work: float = float(Time.get_ticks_usec() - t0) / float(_calls)

	t0 = Time.get_ticks_usec()
	var sink: int = 0
	for c: int in _calls:
		sink += get_nodes_in_group(GROUP).size()
	var sized: float = float(Time.get_ticks_usec() - t0) / float(_calls)

	print("[scan] raw scan        %7.3f us/call" % raw)
	print("[scan] scan + bbox     %7.3f us/call   (CombatCamera._frame_group_update)" % work)
	print("[scan] scan + .size()  %7.3f us/call   (the shape removed from the caps)" % sized)
	print("[scan] at 60 fps, one PER-FRAME scan+bbox costs %.3f ms/s of CPU"
		% (work * 60.0 / 1000.0))
	print("[scan] (sink %d, printed so the loop cannot be optimised away)" % sink)
	quit(0)
	return true


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_user_args())
	argv.append_array(OS.get_cmdline_args())
	for raw: String in argv:
		var a: String = raw.lstrip("+-")
		if not a.contains("="):
			continue
		var k: String = a.get_slice("=", 0)
		var v: String = a.get_slice("=", 1)
		match k:
			"members":
				_members = clampi(int(v), 1, 2000)
			"calls":
				_calls = clampi(int(v), 100, 2000000)
