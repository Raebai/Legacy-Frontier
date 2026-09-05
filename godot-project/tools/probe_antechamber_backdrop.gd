# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_antechamber_backdrop.gd
#
# WHAT THE ANTECHAMBER'S TAVERN ACTUALLY MEASURES — because a room is judged by eye
# and headless has no eye.
#
# ⚠ HEADLESS RUNS THE DUMMY RENDERER, so nothing here is a screenshot and nothing here
# proves the room looks good. What it CAN prove is the set of things that were wrong
# before and would go wrong again silently:
#
#   * the spire is FRAMED by the great window rather than filling it (the outdoor
#     version drew 291 px of stone across a 224 px opening);
#   * the camera's own numbers agree with the room they are meant to show — the
#     ceiling and the window band are both in shot, and the `limit_bottom` clamp is
#     not quietly throwing the offset away (it was);
#   * `_draw()` runs without a script error at BOTH quality settings;
#   * LOW really is cheaper — every seeded count actually drops.
#
# ⚠ EVERYTHING RUNS IN `_process`, NOT `_initialize`. `TuningConfig.quality_is_low()`
# resolves `/root/Tuning` through `get_node_or_null`, and an absolute path from outside
# an active scene tree is an engine ERROR — so building the node one callback too early
# prints a red backtrace on a run that is otherwise fine, which is how a probe teaches
# you to ignore its own output.
#
# It PRINTS rather than asserting: the pass/fail claims live in
# `tools/slice_test_antechamber_sky.gd`. This is the instrument you read when the maker
# says "it still doesn't feel big".
extends SceneTree

const BACKDROP: String = "res://scripts/ui/AntechamberBackdrop.gd"
const WORLD: String = "res://scripts/World.gd"
## The base viewport the whole game is laid out for. `project.godot` is 640x360 with
## `aspect=expand`, so HEIGHT is the fixed edge and width only ever grows.
const BASE: Vector2 = Vector2(640.0, 360.0)
## ⚠ `TREELINE` IS GONE WITH THE FOREST. It was `HubAmbience`'s tallest near pine, and
## the old probe printed how much clear SKY the camera bought above it. The room is an
## interior now (see the header of `AntechamberBackdrop`), so what that number was
## asking — "is the backdrop visible above the thing in front of it?" — is asked of the
## CEILING and the WINDOW BAND instead, and both come from the backdrop's own constants
## rather than from a number copied out of another file.

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var world: GDScript = load(WORLD) as GDScript
	var k: Dictionary = world.get_script_constant_map()
	var ground: float = float(k["GROUND_Y"])
	var town_w: float = float(k["TOWN_WIDTH"])
	var tower_x: float = float(k["TOWER_X"])

	# ── the frame the town camera actually gives you ──────────────────────────
	# Mirrors `World._place_player` exactly. If those numbers move, this reports the
	# new frame rather than a stale one.
	var zoom: float = 0.72
	var offset_y: float = -96.0
	var limit_top: float = -420.0
	var limit_bottom: float = ground + 18.0
	var view: Vector2 = BASE / zoom
	var want_centre: float = ground + offset_y
	var centre: float = clampf(want_centre, limit_top + view.y * 0.5,
		limit_bottom - view.y * 0.5)
	var top: float = centre - view.y * 0.5
	var bottom: float = centre + view.y * 0.5
	print("[camera] zoom %.2f shows %.0fx%.0f world px" % [zoom, view.x, view.y])
	print("[camera] centre wanted %.0f, clamped to %.0f -> visible y %.0f..%.0f"
		% [want_centre, centre, top, bottom])
	var script: GDScript = load(BACKDROP) as GDScript
	var bk: Dictionary = script.get_script_constant_map()
	print("[camera] slab below the floor line %.0f px | room above it %.0f px"
		% [maxf(bottom - ground, 0.0), maxf(ground - top, 0.0)])
	print("[camera] ceiling in shot %.0f px (line at %.0f) | window band %.0f..%.0f"
		% [maxf(float(bk["CEIL_Y"]) - top, 0.0), float(bk["CEIL_Y"]),
		float(bk["WINDOW_TOP"]), float(bk["WINDOW_BOTTOM"])])
	for low: bool in [false, true]:
		var b: Node2D = script.new()
		root.add_child(b)
		b.call("build", town_w, ground, tower_x, Color(0.105, 0.118, 0.235),
			Color(0.62, 0.70, 1.0))
		# `build` re-reads the LIVE quality, so the override has to land after it — and
		# `reseed()` has to follow, or the counts below are still the HIGH ones. See the
		# note on that function.
		b.set("_low", low)
		b.call("reseed")
		var tag: String = "LOW " if low else "HIGH"
		var wins: Array = b.get("_windows")
		var great: Rect2 = Rect2()
		for w: Variant in wins:
			var r: Rect2 = w
			if r.size.x > great.size.x:
				great = r
		var mid_y: float = great.position.y + great.size.y * 0.5
		var half_mid: float = float(b.call("_spire_half_at", mid_y))
		print("[%s] windows %d | great %.0f px wide (%.0f%% of the %.0f px frame)"
			% [tag, wins.size(), great.size.x, 100.0 * great.size.x / view.x, view.x])
		print("[%s] spire half-width: floor %.0f | window mid %.0f | fills %.0f%% of the opening"
			% [tag, float(b.call("_spire_half_at", ground)), half_mid,
			200.0 * half_mid / maxf(great.size.x, 1.0)])
		print("[%s] frame-top half-width %.0f (the shaft never terminates on screen)"
			% [tag, float(b.call("_spire_half_at", top))])
		var bottles: Array = b.get("_bottles")
		var haze: Array = b.get("_haze")
		var dust: Node = b.get("_dust")
		var n_dust: int = int(dust.get("count")) if dust != null else -1
		var span: Rect2 = dust.get("span") if dust != null else Rect2()
		var on_screen: float = float(n_dust) \
			* clampf(view.x / maxf(span.size.x, 1.0), 0.0, 1.0) \
			* clampf(view.y / maxf(span.size.y, 1.0), 0.0, 1.0)
		print("[%s] bottles %d | haze bands %d | dust %d (~%.0f on screen) | redraw %.0f Hz"
			% [tag, bottles.size(), haze.size(), n_dust, on_screen,
			float(bk["REDRAW_HZ_LOW"]) if low else float(bk["REDRAW_HZ"])])
		print("[%s] rungs: room z %d | dust z %d (fighters are 0)"
			% [tag, b.z_index, dust.z_index if dust != null else 999])
		# Force the paint. Under the dummy renderer this still runs `_draw`, so a bad
		# index or a null in there is a SCRIPT ERROR in this run rather than a black
		# screen on the maker's machine.
		b.call("_process", 0.5)
		b.queue_redraw()
		if dust != null:
			dust.set("phase", 3.0)
			dust.queue_redraw()
		root.remove_child(b)
		b.queue_free()
	print("[probe] antechamber tavern probe done")
	quit(0)
	return true
