# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_touch_layout.gd
#
# WHERE EVERY THUMB TARGET ACTUALLY LANDS, ON A REAL PHONE ASPECT.
#
# ⚠ THIS IS A PROBE, NOT A SUITE. It asserts nothing and always exits 0; its job is to
# print the table a person reads. `tools/slice_test_touch_layout.gd` is the suite that
# fails on what this finds.
#
# ⚠ AND IT READS THE DRAWN RECTS, NOT THE FORMULA. It builds a real forced-visible
# `TouchControls`, resizes the root, waits a frame, and asks each Control for its own
# `get_global_rect()`. Re-deriving the offsets here would prove only that this file and
# `TouchControls` agree about arithmetic — which is exactly the class of measurement
# this project has been burned by (see the "verify the DRAWN channel" note in memory:
# four rig fixes read the computed value and the fault was in the drawn one).
#
# ⚠ HEADLESS HAS NO WINDOW AND THEREFORE NO ASPECT. `get_visible_rect()` falls back to
# a SQUARE 640x640 until the root is explicitly sized, so a probe that forgets to size
# it measures a square phone and reports nonsense. That matters more here than anywhere
# else in the project, because ASPECT IS THE SUBJECT: `window/stretch/aspect="expand"`
# means a taller phone gets a WIDER logical viewport (800x360 at 20:9, not 640x360),
# and every left-anchored control moves 160 logical pixels away from every right-
# anchored one. A layout verified only at 640x360 is verified at the one aspect no
# modern phone has.
extends SceneTree

const TouchLayout := preload("res://scripts/combat/TouchLayout.gd")

## The pause button's reserved corner, restated as the two numbers `PauseMenu` actually
## uses (`PAUSE_BTN_SIZE` 44x44, `PAUSE_BTN_MARGIN` 10) rather than as
## `HudStyle.PAUSE_CORNER`.
##
## ⚠ BECAUSE `HudStyle.PAUSE_CORNER` IS A FIXED RECT AT x 580..640 AND THE BUTTON IS
## NOT. `PauseMenu` anchors it to the RIGHT EDGE, so on an expanded 800-wide viewport
## the real button sits at x 746..790 and the constant points at empty screen 160 px
## away. Anything checked against the constant on a phone is checked against nothing.
const PAUSE_BTN: Vector2 = Vector2(44.0, 44.0)
const PAUSE_MARGIN: float = 10.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	print("")
	print("═══ TOUCH LAYOUT AS DRAWN ═══════════════════════════════════════════════")
	print("base viewport %s | stretch canvas_items / expand | orientation landscape"
		% TouchLayout.BASE)
	print("")
	for dev: Dictionary in TouchLayout.DEVICES:
		await _report_device(dev)
	print("═══ END ═════════════════════════════════════════════════════════════════")
	quit(0)


func _report_device(dev: Dictionary) -> void:
	var native: Vector2 = dev["size"]
	var diag: float = float(dev["diag"])

	# THE REAL CHANNEL: hand the engine the device resolution and let ITS OWN stretch
	# code decide the logical viewport, rather than trusting this file's arithmetic.
	root.size = Vector2i(int(native.x), int(native.y))
	await process_frame
	await process_frame
	var vp: Vector2 = root.get_visible_rect().size

	var predicted: Vector2 = TouchLayout.logical_size(native)
	var scale: float = TouchLayout.device_scale(native)
	var mm: float = TouchLayout.mm_per_unit(diag, native)

	print("─── %s  ·  %.1f\" ─────────────────────────────────" % [dev["name"], diag])
	print("  logical viewport: engine says %s | formula says %s | %s"
		% [vp, predicted, "AGREE" if vp.is_equal_approx(predicted) else "*** DISAGREE ***"])
	print("  1 logical px = %.3f device px = %.4f mm   (a %.0f px button is %.1f mm)"
		% [scale, mm, 60.0, 60.0 * mm])

	# The modelled OS claim: cutout on the LEFT end (the worse of the two for this
	# layout, whose heavy side is the right), plus the edge-swipe columns.
	var insets: Vector4 = TouchLayout.modelled_insets(mm, "l")
	var strip: Rect2 = TouchLayout.gesture_strip(vp, mm)
	print("  modelled OS insets (l,t,r,b) = (%.1f, %.1f, %.1f, %.1f) logical px"
		% [insets.x, insets.y, insets.z, insets.w])
	print("  system gesture strip: bottom %.1f logical px (%.2f mm)"
		% [strip.size.y, TouchLayout.GESTURE_STRIP_MM])

	# ⚠ MEASURED WITH THE INSETS APPLIED, via `preview_insets`. A headless run has no
	# touchscreen, so `TouchControls._refresh_insets` would otherwise honour nothing and
	# this table would report the layout on a phone with no cutout and no gesture bar —
	# i.e. the one phone that does not exist. Handing it the modelled insets measures
	# what the DEVICE path will produce.
	var pad: Node = _build_pad(insets)
	await process_frame
	var rows: Array[Dictionary] = _collect(pad, vp)
	rows.append(_pause_row(vp))
	var honoured: Vector4 = pad.call("safe_insets")
	print("  pad honoured insets: (%.1f, %.1f, %.1f, %.1f)  %s"
		% [honoured.x, honoured.y, honoured.z, honoured.w,
			"APPLIED" if honoured.is_equal_approx(insets) else "*** NOT APPLIED ***"])

	print("  %-10s %-26s %-24s %5s %6s  %s"
		% ["CONTROL", "HIT RECT (logical px)", "HIT RECT (device px)", "mm", "reach", "FLAGS"])
	for r: Dictionary in rows:
		var hit: Rect2 = r["hit"]
		var side: String = String(r["side"])
		var reach: float = TouchLayout.thumb_reach_mm(vp, insets, mm, side, hit.get_center())
		var flags: Array[String] = []
		if not TouchLayout.clears_gesture_strip(hit, vp, mm):
			flags.append("GESTURE-BAR")
		if not TouchLayout.inside_safe_area(hit, vp, insets):
			flags.append("OUTSIDE-SAFE-AREA")
		if minf(hit.size.x, hit.size.y) * mm < TouchLayout.THUMB_MIN_MM:
			flags.append("UNDER-9mm")
		if reach > TouchLayout.THUMB_MAX_MM:
			flags.append("UNREACHABLE")
		elif reach > TouchLayout.THUMB_COMFORT_MM:
			flags.append("STRETCH")
		print("  %-10s %-26s %-24s %5.1f %6.1f  %s"
			% [r["name"],
				"x %.0f..%.0f  y %.0f..%.0f" % [hit.position.x, hit.end.x, hit.position.y, hit.end.y],
				"x %.0f..%.0f  y %.0f..%.0f" % [hit.position.x * scale, hit.end.x * scale,
					hit.position.y * scale, hit.end.y * scale],
				minf(hit.size.x, hit.size.y) * mm, reach,
				"ok" if flags.is_empty() else ", ".join(flags)])

	# Every pair, because a round button is TAPPED AS A RECTANGLE and two circles that
	# clear each other can still have overlapping hit boxes.
	var clashes: int = 0
	for i: int in rows.size():
		for j: int in range(i + 1, rows.size()):
			var a: Rect2 = rows[i]["hit"]
			var b: Rect2 = rows[j]["hit"]
			if TouchLayout.overlaps(a, b):
				clashes += 1
				var gap: Rect2 = a.intersection(b)
				print("  ⚠ OVERLAP: %s x %s  — %.0f x %.0f logical px of shared hit box"
					% [rows[i]["name"], rows[j]["name"], gap.size.x, gap.size.y])
	if clashes == 0:
		print("  overlaps: none")

	# The floating stick zones, which are not Controls and so are not in the table.
	var lz: float = vp.x * float(pad.get("LEFT_ZONE_FRAC"))
	var rz: float = vp.x * float(pad.get("RIGHT_ZONE_FRAC"))
	print("  stick zones: move x 0..%.0f | dead band %.0f..%.0f | aim x %.0f..%.0f"
		% [lz, lz, rz, rz, vp.x])
	for r: Dictionary in rows:
		var hit: Rect2 = r["hit"]
		if String(r["side"]) == "l" and hit.end.x > lz:
			print("  ⚠ %s crosses out of the move-stick zone (right edge %.0f > %.0f)"
				% [r["name"], hit.end.x, lz])
		if String(r["side"]) == "r" and hit.position.x < rz and String(r["name"]) != "PAUSE":
			print("  ⚠ %s reaches into the centre dead band (left edge %.0f < %.0f)"
				% [r["name"], hit.position.x, rz])
	pad.queue_free()
	print("")


## A forced-visible pad on the tree, so its `_ready` builds the real Controls.
func _build_pad(insets: Vector4) -> Node:
	var pad: Node = TouchControls.new()
	pad.set("force_visible", true)
	pad.set("preview_insets", insets)
	root.add_child(pad)
	return pad


## Every tappable Control the pad built, with the rect the ENGINE gave it.
func _collect(pad: Node, vp: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Node in pad.get_children():
		var ctrl := c as Control
		if ctrl == null:
			continue
		# MOUSE_FILTER_IGNORE means it is decoration (a stick ring), not a target.
		if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		var name_: String = ctrl.name
		if ctrl is Button:
			name_ = (ctrl as Button).text
		elif not ctrl.visible:
			name_ = "HANDOFF*"   # contextual: measured where it WOULD draw
		var hit: Rect2 = ctrl.get_global_rect()
		out.append({"name": name_, "hit": hit,
			"side": "r" if hit.get_center().x > vp.x * 0.5 else "l"})
	return out


## The pause button, computed from `PauseMenu`'s own two constants rather than read off
## a node — instancing `PauseMenu` would drag its dependency chain into a `--script`
## run that has no autoloads.
func _pause_row(vp: Vector2) -> Dictionary:
	var hit := Rect2(vp.x - PAUSE_MARGIN - PAUSE_BTN.x, PAUSE_MARGIN, PAUSE_BTN.x, PAUSE_BTN.y)
	return {"name": "PAUSE", "hit": hit, "side": "r"}
