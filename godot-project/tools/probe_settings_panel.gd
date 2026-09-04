# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/probe_settings_panel.gd
#
# WHAT THE SETTINGS PANEL AND THE RUN CARD ACTUALLY MEASURE — printed, not asserted.
#
# Three faults were reported by eye and every one of them is a NUMBER, so this prints
# the numbers before and after rather than arguing about them:
#
#   1. THE SETTINGS PANEL RESOLVES OFF-SCREEN. `PauseMenu` put a ScrollContainer with
#      `custom_minimum_size.y = 520` inside a CenterContainer on a 360-tall viewport.
#      A CenterContainer hands its child the child's MINIMUM size and centres it, so
#      the rect solves to y = -80 .. 440 and 80 px falls off each end. Worse, the
#      internal scrollbar only engages once the CONTENT passes 520 — so a column
#      between 360 and 520 tall is unreachable in BOTH directions: too tall for the
#      screen, too short to scroll.
#   2. THE CONTROLS CARD IS WIDER THAN THE PANEL. One generated line runs ~64 chars at
#      font 13 into a 320-wide scroll with `horizontal_scroll_mode` DISABLED and no
#      autowrap, so the right-hand end of it is simply not drawn anywhere.
#   3. THE RUN CARD'S "wielded" ROW OVERFLOWS from about six elements on — no
#      `clip_text`, no autowrap, 8 names into a 250-wide row.
#
# ⚠ HEADLESS HAS NO WINDOW AND THEREFORE NO ASPECT RATIO, so `get_visible_rect()`
# falls back to a SQUARE 640x640 and every vertical measurement here would be off by
# 280 px in the flattering direction. `root.size` is set to a real 16:9 window and a
# frame is waited on before anything is read; the printed viewport line is the proof
# that worked.
extends SceneTree

const RUN_SUMMARY: String = "res://scripts/ui/RunSummary.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# A real 16:9 window, or `stretch/aspect="expand"` never resolves and the viewport
	# reads square. See the header.
	root.size = Vector2i(1366, 768)
	await process_frame
	await process_frame
	var vp: Vector2 = root.get_visible_rect().size
	print("viewport: %.0f x %.0f  (640x640 here means the window trick did not take)"
		% [vp.x, vp.y])

	var menu: PauseMenu = PauseMenu.new()
	root.add_child(menu)
	menu.build("Exit")
	menu.open()
	menu.call("_open_settings")
	await process_frame
	await process_frame

	print("")
	print("── 1. THE SETTINGS PANEL ─────────────────────────────────────────────")
	var scroll: ScrollContainer = menu.get("_settings_scroll") as ScrollContainer
	var col: VBoxContainer = menu.get("_settings_col") as VBoxContainer
	if scroll == null or col == null:
		printerr("  no _settings_scroll / _settings_col — the panel has been restructured")
	else:
		var r: Rect2 = scroll.get_global_rect()
		var content_h: float = col.get_combined_minimum_size().y
		print("  scroll min      : %s" % scroll.custom_minimum_size)
		print("  scroll rect     : y %.1f .. %.1f   x %.1f .. %.1f"
			% [r.position.y, r.end.y, r.position.x, r.end.x])
		print("  off-screen      : %.1f px above, %.1f px below"
			% [maxf(-r.position.y, 0.0), maxf(r.end.y - vp.y, 0.0)])
		print("  content height  : %.1f px   (scroll viewport %.1f)" % [content_h, r.size.y])
		var reachable: float = minf(r.end.y, vp.y) - maxf(r.position.y, 0.0)
		print("  visible band    : %.1f px of the panel is on screen" % reachable)
		print("  scrolls?        : %s   (a scrollbar only engages once content > the "
			% ("yes" if content_h > r.size.y else "NO")
			+ "scroll's own height)")
		# ⚠ THE HONEST NUMBER. Scrolling moves the content INSIDE the scroll viewport,
		# so a viewport hanging off the bottom of the screen keeps that band hidden at
		# every scroll position — scroll all the way down and the last N px of content
		# sit below the screen edge with nowhere further to go. Same at the top.
		print("  never reachable : %.1f px of content, at ANY scroll position"
			% (maxf(-r.position.y, 0.0) + maxf(r.end.y - vp.y, 0.0)))

	print("")
	print("── 2. TEXT WIDER THAN THE PANEL ──────────────────────────────────────")
	# ⚠ THE CONTENT WIDTH, NOT THE SCROLL'S WIDTH. A vertical scrollbar takes a slice
	# off the right of every ScrollContainer that has one, and a label measured against
	# the outer width reads as "fits" while its tail is under the bar.
	var panel_w: float = 320.0
	if scroll != null:
		panel_w = scroll.size.x
		var vbar: VScrollBar = scroll.get_v_scroll_bar()
		if vbar != null and vbar.visible:
			panel_w -= vbar.size.x
	var widest: float = 0.0
	var widest_text: String = ""
	var overflow: int = 0
	for l: Label in _labels(menu):
		var w: float = l.get_combined_minimum_size().x
		if w > panel_w:
			overflow += 1
		if w > widest:
			widest = w
			widest_text = l.text.split("\n")[0]
	print("  panel width     : %.1f px" % panel_w)
	print("  labels over it  : %d" % overflow)
	print("  widest label    : %.1f px  <- %s" % [widest, widest_text.substr(0, 60)])
	var buttons_over: int = 0
	for b: Button in _buttons(menu):
		if b.get_combined_minimum_size().x > panel_w:
			buttons_over += 1
	print("  buttons over it : %d" % buttons_over)

	print("")
	print("── 3. THE RUN CARD'S WIDEST ROW ──────────────────────────────────────")
	var rs: GDScript = load(RUN_SUMMARY) as GDScript
	var all_elements: Array = ["Fire", "Ice", "Shadow", "Storm", "Arcane", "Poison",
		"Holy", "Blood"]
	for n: int in [2, 4, 6, 8]:
		var run: Dictionary = {
			"floor_reached": 9, "total_floors": 10, "enemies_killed": 137,
			"boss_killed": true, "elements_used": all_elements.slice(0, n),
			"rank_title": "Ranked", "friendly_damage": 214, "highest_floor": 10,
			"falls": 5,
		}
		var value: String = ""
		for row: Array in rs.call("stat_rows", run):
			if String(row[0]) == "wielded":
				value = String(row[1])
		var lab := Label.new()
		lab.text = value
		lab.add_theme_font_size_override("font_size", 11)
		root.add_child(lab)
		await process_frame
		var w: float = lab.get_combined_minimum_size().x
		lab.queue_free()
		# STAT_W is 250 and the key label ("wielded") eats the left of it, so the value
		# has ~185 px. That is the number the row has to clear, not 250.
		print("  %d elements -> %-46s %6.1f px  %s"
			% [n, '"%s"' % value.substr(0, 44), w, "OVERFLOWS" if w > 185.0 else "fits"])

	print("")
	print("── 4. WHAT SURVIVES A RESTART ────────────────────────────────────────")
	var Settings: GDScript = load("res://scripts/Settings.gd") as GDScript
	if Settings == null:
		print("  scripts/Settings.gd does not exist — nothing but fullscreen persists")
	else:
		var keys: Array = Settings.call("known_keys")
		print("  settings routed through user://settings.cfg: %d" % keys.size())
		for k: Array in keys:
			print("    %-10s %s" % [k[0], k[1]])

	menu.queue_free()
	quit(0)


func _labels(n: Node) -> Array[Label]:
	var out: Array[Label] = []
	_walk_labels(n, out)
	return out


func _walk_labels(n: Node, out: Array[Label]) -> void:
	var l: Label = n as Label
	if l != null:
		out.append(l)
	for c: Node in n.get_children():
		_walk_labels(c, out)


func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	_walk_buttons(n, out)
	return out


func _walk_buttons(n: Node, out: Array[Button]) -> void:
	var b: Button = n as Button
	if b != null:
		out.append(b)
	for c: Node in n.get_children():
		_walk_buttons(c, out)
