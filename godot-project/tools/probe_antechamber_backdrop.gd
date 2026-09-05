# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_antechamber_backdrop.gd
#
# WHAT THE ANTECHAMBER'S SKY ACTUALLY MEASURES — because a backdrop is judged by eye
# and headless has no eye.
#
# ⚠ HEADLESS RUNS THE DUMMY RENDERER, so nothing here is a screenshot and nothing here
# proves the room looks good. What it CAN prove is the set of things that were wrong
# before and would go wrong again silently:
#
#   * the spire is actually WIDE in the frame the town camera gives you (the old
#     `TowerDoor` shaft was 112 px of an 889 px frame — 12%);
#   * the camera's own numbers agree with the sky they are meant to show, i.e. the
#     `limit_bottom` clamp is not quietly throwing the offset away (it was);
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
## `HubAmbience`'s tallest near pine, measured from its own seeding: `near_h` tops out
## at 320 and the third tier's apex sits `1.167 * h` above the base. The spire has to
## be readable ABOVE this or it is a tower behind a hedge.
const TREELINE: float = 360.0

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
	print("[camera] dirt below the ground line %.0f px | sky above it %.0f px | clear sky above the treeline %.0f px"
		% [maxf(bottom - ground, 0.0), maxf(ground - top, 0.0),
		maxf((ground - TREELINE) - top, 0.0)])

	var script: GDScript = load(BACKDROP) as GDScript
	var bk: Dictionary = script.get_script_constant_map()
	for low: bool in [false, true]:
		var b: Node2D = script.new()
		root.add_child(b)
		b.call("build", town_w, ground, tower_x, Color(0.19, 0.16, 0.30),
			Color(0.62, 0.70, 1.0))
		# `build` re-reads the LIVE quality, so the override has to land after it — and
		# `reseed()` has to follow, or the counts below are still the HIGH ones. See the
		# note on that function.
		b.set("_low", low)
		b.call("reseed")
		var tag: String = "LOW " if low else "HIGH"
		var half_ground: float = float(b.call("_spire_half_at", ground))
		var half_tree: float = float(b.call("_spire_half_at", ground - TREELINE))
		var half_top: float = float(b.call("_spire_half_at", top))
		print("[%s] spire half-width: ground %.0f | treeline %.0f | frame-top %.0f"
			% [tag, half_ground, half_tree, half_top])
		print("[%s] spire fills %.0f%% of the %.0f px frame at the treeline"
			% [tag, 200.0 * half_tree / view.x, view.x])
		var wins: Array = b.get("_windows")
		var clouds: Array = b.get("_clouds")
		var petals: Node = b.get("_petals")
		var n_petals: int = int(petals.get("count")) if petals != null else -1
		var span: Rect2 = petals.get("span") if petals != null else Rect2()
		var on_screen: float = float(n_petals) \
			* clampf(view.x / maxf(span.size.x, 1.0), 0.0, 1.0) \
			* clampf(view.y / maxf(span.size.y, 1.0), 0.0, 1.0)
		print("[%s] lit windows %d | cloud bands %d | petals %d (~%.0f on screen) | redraw %.0f Hz"
			% [tag, wins.size(), clouds.size(), n_petals, on_screen,
			float(bk["REDRAW_HZ_LOW"]) if low else float(bk["REDRAW_HZ"])])
		print("[%s] rungs: backdrop z %d | petals z %d (fighters are 0)"
			% [tag, b.z_index, petals.z_index if petals != null else 999])
		# Force the paint. Under the dummy renderer this still runs `_draw`, so a bad
		# index or a null in there is a SCRIPT ERROR in this run rather than a black
		# screen on the maker's machine.
		b.call("_process", 0.5)
		b.queue_redraw()
		if petals != null:
			petals.set("phase", 3.0)
			petals.queue_redraw()
		root.remove_child(b)
		b.queue_free()
	print("[probe] antechamber backdrop probe done")
	quit(0)
	return true
