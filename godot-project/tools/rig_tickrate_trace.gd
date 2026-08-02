# Run: godot --headless --path godot-project --script tools/rig_tickrate_trace.gd
#   optional: ++csv=user://rig_trace.csv  ++verbose=1
#
# DIAGNOSTIC table for "does CharacterRig feel the same at 60 Hz as at 120 Hz". The
# pinned regression is tools/slice_test_rig_tickrate.gd; this is the one you run when it
# goes red and you need to see WHICH channel and WHEN. Both share
# tools/rig_tickrate_probe.gd, which carries the reasoning.
#
# Reading the table: `raw` is the sample-for-sample maximum, `aligned` allows one sample
# of phase (a state change cannot land on the same instant on two different tick grids —
# see the ⚠ on `divergence`). The verdict is on `aligned`; `raw` is printed so a genuine
# constant offset is still visible.
#
# ++verbose=1 prints every sample where the two clocks disagree, which is how you tell a
# one-frame transition transient from a channel that is wrong for the whole walk.
extends SceneTree

const PROBE_PATH: String = "res://tools/rig_tickrate_probe.gd"

var _ran: bool = false
var _verbose: bool = false
var _csv: String = ""


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_parse_args()

	var probe: RefCounted = (load(PROBE_PATH) as GDScript).new()
	var channels: Array = probe.get("CHANNELS")
	var a: Dictionary = probe.call("run", 1.0 / 60.0, root)
	var b: Dictionary = probe.call("run", 1.0 / 120.0, root)

	print("[tick-trace] CharacterRig at 60 Hz vs 120 Hz — %.1f s, %d samples"
		% [float(probe.get("DURATION")), int(a["samples"])])
	print("[tick-trace] motion: 1.0 s idle -> 2.0 s walk @ %d px/s -> jump -> land -> settle"
		% int(float(probe.get("WALK_SPEED"))))
	print("[tick-trace] %-18s %9s %9s %9s %7s  %s"
		% ["channel", "raw", "aligned", "rms", "tol", "verdict"])

	var dependent: Array[String] = []
	for ch: Dictionary in channels:
		var cname: String = String(ch["name"])
		var ta: Array = a[cname]
		var tb: Array = b[cname]
		var d: Dictionary = probe.call("divergence", ta, tb)
		if int(d["n"]) == 0:
			printerr("[tick-trace] channel `%s` produced NO samples — the trace is BROKEN, not clean." % cname)
			quit(1)
			return true
		var tol: float = float(ch["tol"])
		var ok: bool = float(d["aligned"]) <= tol
		if not ok:
			dependent.append(cname)
		print("[tick-trace] %-18s %9.4f %9.4f %9.4f %7.3f  %s"
			% [cname, d["raw"], d["aligned"], d["rms"], tol,
				"ok" if ok else "TICK-RATE DEPENDENT"])
		if _verbose:
			_dump(cname, ta, tb, float(probe.get("SAMPLE_HZ")))

	if not _csv.is_empty():
		_write_csv(probe, channels, a, b)

	if dependent.is_empty():
		print("[tick-trace] PASS — every traced channel converges. The rig is tick-rate independent.")
		quit(0)
	else:
		printerr("[tick-trace] FAIL — %d channel(s) depend on the tick rate: %s"
			% [dependent.size(), ", ".join(dependent)])
		printerr("[tick-trace] These are the channels whose FEEL differs between the 120 Hz")
		printerr("[tick-trace] spike playground the numbers were tuned in and the 60 Hz game.")
		quit(1)
	return true


func _dump(cname: String, ta: Array, tb: Array, hz: float) -> void:
	var n: int = mini(ta.size(), tb.size())
	for i: int in n:
		var d: float = float(ta[i]) - float(tb[i])
		if absf(d) > 0.001:
			print("[tick-trace]   %s t=%.4f  60Hz=%+9.4f  120Hz=%+9.4f  d=%+8.4f"
				% [cname, float(i) / hz, ta[i], tb[i], d])


func _write_csv(probe: RefCounted, channels: Array, a: Dictionary, b: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(_csv, FileAccess.WRITE)
	if f == null:
		printerr("[tick-trace] could not open %s" % _csv)
		return
	var hz: float = float(probe.get("SAMPLE_HZ"))
	var header: PackedStringArray = PackedStringArray(["t"])
	for ch: Dictionary in channels:
		header.append(String(ch["name"]) + "_60")
		header.append(String(ch["name"]) + "_120")
	f.store_line(",".join(header))
	var n: int = mini(int(a["samples"]), int(b["samples"]))
	for i: int in n:
		var row: PackedStringArray = PackedStringArray(["%.5f" % (float(i) / hz)])
		for ch: Dictionary in channels:
			var cname: String = String(ch["name"])
			row.append("%.6f" % float((a[cname] as Array)[i]))
			row.append("%.6f" % float((b[cname] as Array)[i]))
		f.store_line(",".join(row))
	f.close()
	print("[tick-trace] csv -> %s" % ProjectSettings.globalize_path(_csv))


func _parse_args() -> void:
	var argv: Array = []
	argv.append_array(OS.get_cmdline_user_args())
	argv.append_array(OS.get_cmdline_args())
	for raw: String in argv:
		var arg: String = raw.lstrip("+-")
		if not arg.contains("="):
			continue
		var k: String = arg.get_slice("=", 0)
		var v: String = arg.get_slice("=", 1)
		match k:
			"csv":
				_csv = v if v.ends_with(".csv") else v + ".csv"
			"verbose":
				_verbose = v != "0"
