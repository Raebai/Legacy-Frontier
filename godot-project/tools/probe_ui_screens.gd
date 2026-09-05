# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_ui_screens.gd
#
# WHAT EVERY SCREEN ACTUALLY MEASURES — printed, not asserted.
#
# The maker's words were "cluttered", "too large", "clunky and unoptimised". None of
# those can be acted on. This turns each of them into a number:
#
#   * CLUTTER      -> controls per page, and rows per page.
#   * TOO LARGE    -> the fraction of the 360 px screen height one element eats.
#   * CLUNKY       -> content height / screen height. Above 1.0 the page scrolls, and
#                     the ratio IS the number of screens a thumb has to drag through.
#   * REACHABLE    -> every tap target's height in base px AND in millimetres.
#
# ══ THE MILLIMETRE CONVERSION, AND WHY IT IS NOT A GUESS ══════════════════════════
# `project.godot` is 640x360 with `stretch=canvas_items` and `aspect=expand`. Expand
# keeps the base HEIGHT and grows the WIDTH, so 360 logical px always maps to the
# whole SHORT edge of the physical screen — in landscape, the screen's height.
#
#   6.1" 19.5:9 phone  short edge 65.9 mm  ->  0.183 mm per logical px  ->  9 mm = 49 px
#   6.7" 19.5:9 phone  short edge 72.4 mm  ->  0.201 mm per logical px  ->  9 mm = 45 px
#
# Both are printed for every target, because the honest answer to "does this clear
# 9 mm" is "on which phone". The smaller device is the one a layout has to survive.
#
# ⚠ HEADLESS HAS NO WINDOW AND THEREFORE NO ASPECT RATIO. `get_visible_rect()` falls
# back to a SQUARE 640x640, so a page that overflows a 360-tall screen by 90 px reads
# as fitting with 190 px to spare — a measurement that is wrong in the flattering
# direction, which is the worst kind. `root.size` is set to a real window and two
# frames are waited on; the printed viewport line is the proof it took.
extends SceneTree

const LOBBY_SCENE: String = "res://scenes/ui/Lobby.tscn"

## The two shapes a phone actually presents. 16:9 is the base; 20:9 is a modern tall
## phone, which under `aspect=expand` is a WIDER logical viewport, not a letterboxed
## one — so a layout anchored to the right edge moves and a centred card does not.
const SHAPES: Array = [
	["16:9  640x360", Vector2i(1280, 720)],
	["20:9  800x360", Vector2i(1600, 720)],
]

## mm per logical px on the two reference phones. See the header for the arithmetic.
const MM_SMALL: float = 65.9 / 360.0
const MM_LARGE: float = 72.4 / 360.0
## The target the brief names.
const TAP_MM: float = 9.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("")
	print("mm per base px: %.3f (6.1\" phone)   %.3f (6.7\" phone)" % [MM_SMALL, MM_LARGE])
	print("9 mm therefore = %.0f px (6.1\") / %.0f px (6.7\")"
		% [TAP_MM / MM_SMALL, TAP_MM / MM_LARGE])
	for shape: Array in SHAPES:
		root.size = shape[1] as Vector2i
		await process_frame
		await process_frame
		var vp: Vector2 = root.get_visible_rect().size
		print("")
		print("═══ %s ═══  (viewport reads %.0f x %.0f — 640x640 means the window "
			% [shape[0], vp.x, vp.y] + "trick did not take)")
		await _probe_pause(vp)
		await _probe_lobby(vp)
	quit(0)


# ═══════════════════════════════════════════════════════════════════ the pause menu
func _probe_pause(vp: Vector2) -> void:
	var menu: PauseMenu = PauseMenu.new()
	root.add_child(menu)
	menu.build("Exit")
	menu.open()
	await process_frame
	await process_frame
	print("")
	print("── PAUSE MENU PAGES ─────────────────────────────────────────────────")
	print("  %-12s %5s %5s %6s %7s %6s  %s"
		% ["page", "rows", "ctrls", "card h", "content", "ratio", "verdict"])
	for named: Array in _pause_pages(menu):
		var scroll: ScrollContainer = named[1] as ScrollContainer
		var col: Control = named[2] as Control
		var center: Control = named[3] as Control
		if scroll == null or col == null or center == null:
			continue
		menu.call("_show_page", center)
		await process_frame
		await process_frame
		var r: Rect2 = scroll.get_global_rect()
		var content: float = col.get_combined_minimum_size().y
		var ratio: float = content / maxf(r.size.y, 1.0)
		var off: float = maxf(-r.position.y, 0.0) + maxf(r.end.y - vp.y, 0.0)
		var verdict: String = "fits"
		if off > 0.5:
			verdict = "%.0f px OFF SCREEN" % off
		elif ratio > 1.01:
			verdict = "scrolls %.1f screens" % ratio
		print("  %-12s %5d %5d %6.0f %7.0f %6.2f  %s"
			% [named[0], _rows(col), _count(center), r.size.y, content, ratio, verdict])
	menu.call("_show_page", menu.get("_main_center"))
	await process_frame
	print("")
	print("  tap targets (every Button/CheckButton/HSlider under the menu):")
	_report_targets(menu)
	menu.queue_free()
	await process_frame


## `[name, scroll, col, center]` for every page the menu owns, including any page
## added after this probe was written — the names are read off the node, not typed
## in here, so a fifth page cannot be silently un-measured.
func _pause_pages(m: PauseMenu) -> Array:
	var out: Array = []
	for key: String in ["main", "settings", "audio", "video", "feel", "game", "controls"]:
		var scroll: Variant = m.get("_%s_scroll" % key)
		var col: Variant = m.get("_%s_col" % key)
		var center: Variant = m.get("_%s_center" % key)
		if scroll == null or col == null or center == null:
			continue
		out.append([key, scroll, col, center])
	return out


# ══════════════════════════════════════════════════════════════════════ the lobby
func _probe_lobby(vp: Vector2) -> void:
	var packed: PackedScene = load(LOBBY_SCENE) as PackedScene
	if packed == null:
		print("")
		print("── TITLE SCREEN ── %s did not load" % LOBBY_SCENE)
		return
	var lobby: Control = packed.instantiate() as Control
	root.add_child(lobby)
	await process_frame
	await process_frame
	print("")
	print("── TITLE SCREEN ─────────────────────────────────────────────────────")
	var col: Control = lobby.get("_col") as Control
	if col != null:
		var need: Vector2 = col.get_combined_minimum_size()
		print("  column needs    : %.0f x %.0f px  (%.0f%% of the %.0f px screen height)"
			% [need.x, need.y, need.y / maxf(vp.y, 1.0) * 100.0, vp.y])
		print("  column rect     : y %.1f .. %.1f   x %.1f .. %.1f"
			% [col.get_global_rect().position.y, col.get_global_rect().end.y,
			col.get_global_rect().position.x, col.get_global_rect().end.x])
		print("  visible rows    : %d   controls in tree: %d" % [_rows(col), _count(lobby)])
		# THE SINGLE BIGGEST ELEMENT. "Too large" is one element eating the page, and
		# naming it is the whole point of this line.
		var worst: Control = null
		var worst_h: float = 0.0
		for c: Node in col.get_children():
			var cc: Control = c as Control
			if cc == null or not cc.visible:
				continue
			var h: float = cc.get_combined_minimum_size().y
			if h > worst_h:
				worst_h = h
				worst = cc
		if worst != null:
			print("  tallest element : %s  %.0f px = %.0f%% of the screen height"
				% [worst.get_class(), worst_h, worst_h / maxf(vp.y, 1.0) * 100.0])
	print("  tap targets:")
	_report_targets(lobby)
	lobby.queue_free()
	await process_frame


# ══════════════════════════════════════════════════════════════════════ helpers
## Rows a player actually sees: visible direct children with a height. A hidden
## sub-panel is excluded because a `Container` excludes it from its minimum size too,
## so counting it would describe a screen nobody is looking at.
func _rows(col: Control) -> int:
	var n: int = 0
	for c: Node in col.get_children():
		var cc: Control = c as Control
		if cc != null and cc.visible:
			n += 1
	return n


func _count(from: Node) -> int:
	var n: int = 1 if from is Control else 0
	for c: Node in from.get_children():
		n += _count(c)
	return n


## Every tap target under a subtree, smallest first, with its millimetre size on both
## reference phones. Only VISIBLE ones: the collapsed co-op panel and the three hidden
## settings sub-pages are not things a thumb can currently miss.
func _report_targets(from: Node) -> void:
	var seen: Dictionary = {}
	for c: Control in _tappable(from):
		var h: float = maxf(c.get_combined_minimum_size().y, c.size.y)
		var label: String = c.get("text") if c.get("text") != null else c.get_class()
		var key: String = "%s|%.0f" % [String(label).substr(0, 26), h]
		if seen.has(key):
			continue
		seen[key] = h
	var rows: Array = []
	for key: String in seen:
		rows.append([float(seen[key]), key.split("|")[0]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var under: int = 0
	for r: Array in rows:
		var h: float = r[0]
		var ok: bool = h * MM_SMALL >= TAP_MM
		if not ok:
			under += 1
		print("    %6.1f px  %5.1f mm (6.1\")  %5.1f mm (6.7\")  %s  %s"
			% [h, h * MM_SMALL, h * MM_LARGE, "   " if ok else "  <", r[1]])
	print("    %d of %d distinct targets are under %.0f mm on the 6.1\" reference"
		% [under, rows.size(), TAP_MM])


func _tappable(from: Node) -> Array[Control]:
	var out: Array[Control] = []
	_walk_tappable(from, out)
	return out


func _walk_tappable(n: Node, out: Array[Control]) -> void:
	# ⚠ THE DIRECTOR IS NOT A SCREEN THIS BRIEF COVERS, AND COUNTING IT WAS ACTIVELY
	# MISLEADING. `PauseMenu` hangs the F1 review rig off itself in a debug build, and
	# its 22 tab and hotkey buttons are 26 px each — so the first run of this probe
	# reported "27 of 27 targets under 9 mm" when only 5 of them were player-facing.
	# `export_presets.cfg` excludes `res://tools/*` from the pack, so none of these
	# bytes reach a phone; a thumb can never miss them.
	if n.is_in_group(&"director"):
		return
	var c: Control = n as Control
	if c != null and not c.visible:
		return   # a hidden page is not a target a thumb can miss
	if (n is Button or n is HSlider) and c != null:
		out.append(c)
	for child: Node in n.get_children():
		_walk_tappable(child, out)
