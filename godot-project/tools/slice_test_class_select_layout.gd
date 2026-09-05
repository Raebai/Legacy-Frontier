# Run: godot --headless --path godot-project --script tools/slice_test_class_select_layout.gd
#
# THE CLASS-SELECT SCREEN, MEASURED -- NOT LOOKED AT.
#
# The screen was rebuilt from a 3x3 grid of name-only cards into a roster rail plus a
# detail column carrying the four spells a class actually casts and one sentence per
# spell. That is strictly MORE on a screen that was already the tightest budget in the
# game, so the claim "it fits" has to be a number.
#
# == THE TWO APECTS, AND WHY THE SECOND ONE IS THE INTERESTING ONE =============
# `project.godot` is 640x360 with `stretch/mode="canvas_items"` and
# `stretch/aspect="expand"`. `expand` does NOT letterbox a taller phone -- it hands the
# game a WIDER LOGICAL VIEWPORT at the same logical height. A 20:9 handset therefore
# reports roughly 800x360, not 640x360 with bars. So:
#     * HEIGHT 360 is a hard ceiling on every device.
#     * WIDTH 640 is a FLOOR, and the honest second measurement is a WIDER viewport,
#       because a centred panel that fits 640 trivially fits 800 -- what a wide test
#       actually catches is anything that ANCHORS or STRETCHES and therefore changes
#       shape when the viewport grows.
# Both are measured below.
#
# == HEADLESS HAS NO WINDOW AND THEREFORE NO ASPECT ============================
# `get_visible_rect()` under `--headless` falls back to a SQUARE 640x640 -- taller than
# any phone, so a panel that overflows a real 360 px screen measures as fitting. Every
# measurement here therefore sets `root.size` explicitly and waits a frame for the
# layout pass, and `_test_the_harness_can_see_the_aspect` asserts the viewport really
# reports what was set before anything else is trusted. A probe that measures the
# fallback is a probe that cannot fail.
#
# == AND A LAID-OUT RECT, NOT A FRESH ONE ======================================
# `slice_test_outfitter` learned this the expensive way: it measured a column the
# instant it was built and read 1771 px against a 360 px budget -- not a real overflow,
# an unlaid-out one, because an autowrapping Label reports the height of one word per
# line until the container has told it how wide it is. So every read here happens after
# `await process_frame` and the suite asserts the numbers are non-zero and sane before
# comparing them to anything.
#
# -- Vacuous-pass armour (full write-up in tools/slice_test_spell_buttons.gd) --
# `failed += _test_x()` IS BANNED. A dead property read is not a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function and hands the caller
# back the return type's zero, which under that idiom reads as "zero failures". So
# failures accumulate on the MEMBER `_fails`, and every test records a completion
# sentinel -- a test that aborts part-way is missing from `_completed` and fails BY
# ABSENCE rather than passing by silence.
extends SceneTree

const TESTS: Array[String] = [
	"the_harness_can_see_the_aspect",
	"the_panel_fits_a_phone_at_640x360",
	"the_panel_fits_a_wide_phone_at_800x360",
	"every_row_clears_the_thumb_floor",
	"nothing_in_the_panel_overlaps",
	"the_roster_is_whole_and_unscrolled",
	"the_detail_column_names_the_spells_the_class_really_casts",
]

const SELECT_SCRIPT: String = "res://scripts/ClassSelect.gd"

## The base viewport from `project.godot`, and the wide logical viewport an `expand`
## stretch hands a 20:9 phone. Same 360 in both -- that is the point.
const BASE_W: float = 640.0
const BASE_H: float = 360.0
const WIDE_W: float = 800.0

## The thumb floor. `Outfitter.MIN_TAP` is 30 and `slice_test_outfitter` pins 28; this
## suite holds the row height to the stricter of the two that the screen claims.
const MIN_TAP_H: float = 30.0

var _fails: int = 0
var _completed: Dictionary = {}
var _sel: CanvasLayer = null


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _test_the_harness_can_see_the_aspect()
	await _test_the_panel_fits_a_phone_at_640x360()
	await _test_the_panel_fits_a_wide_phone_at_800x360()
	await _test_every_row_clears_the_thumb_floor()
	await _test_nothing_in_the_panel_overlaps()
	await _test_the_roster_is_whole_and_unscrolled()
	await _test_the_detail_column_names_the_spells_the_class_really_casts()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted -- a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Class select layout tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Class select layout tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(name: String) -> void:
	_completed[name] = true


## Build the screen the way the game does -- the real script, opened, so what is
## measured is what a player sees. Rebuilt per aspect rather than resized, because a
## container that caches a minimum size from its first layout is exactly the bug a
## second aspect is here to find.
func _open_at(w: float, h: float) -> CanvasLayer:
	if _sel != null and is_instance_valid(_sel):
		_sel.queue_free()
		_sel = null
		await process_frame
	root.size = Vector2i(int(w), int(h))
	root.content_scale_size = Vector2i(int(w), int(h))
	await process_frame
	var scr: GDScript = load(SELECT_SCRIPT) as GDScript
	var node := CanvasLayer.new()
	node.set_script(scr)
	root.add_child(node)
	await process_frame
	node.call("open")
	# Two frames: one for `open()`'s own refresh, one for the container pass that
	# gives the autowrapping blurb labels a width to wrap against.
	await process_frame
	await process_frame
	_sel = node
	return node


func _panel_of(sel: CanvasLayer) -> Control:
	return sel.get("_panel") as Control


## Every Control under `from`, flattened. Used for the overlap sweep.
func _walk(from: Node, out: Array) -> void:
	if from is Control:
		out.append(from)
	for c: Node in from.get_children():
		_walk(c, out)


# ---------------------------------------------------------------------------
# 0. the instrument
# ---------------------------------------------------------------------------

## HARNESSES LIE. Under `--headless` there is no window, `get_visible_rect()` answers a
## square 640x640, and every "it fits 360" assertion below would then be measuring a
## screen 280 px taller than any phone. So the first thing asserted is that the aspect
## the suite ASKED for is the aspect the viewport REPORTS.
func _test_the_harness_can_see_the_aspect() -> void:
	root.size = Vector2i(int(BASE_W), int(BASE_H))
	root.content_scale_size = Vector2i(int(BASE_W), int(BASE_H))
	await process_frame
	var rect: Rect2 = root.get_visible_rect()
	_expect(is_equal_approx(rect.size.x, BASE_W) and is_equal_approx(rect.size.y, BASE_H),
		"the headless viewport reports the aspect this suite set (got %.0fx%.0f, wanted "
			% [rect.size.x, rect.size.y]
		+ "%.0fx%.0f -- a square 640x640 fallback would make every budget below vacuous)"
			% [BASE_W, BASE_H])
	root.size = Vector2i(int(WIDE_W), int(BASE_H))
	root.content_scale_size = Vector2i(int(WIDE_W), int(BASE_H))
	await process_frame
	rect = root.get_visible_rect()
	_expect(is_equal_approx(rect.size.x, WIDE_W),
		"...and it follows a change of aspect (got %.0f wide, wanted %.0f)"
			% [rect.size.x, WIDE_W])
	_completes("the_harness_can_see_the_aspect")


# ---------------------------------------------------------------------------
# 1 + 2. it fits, at both aspects
# ---------------------------------------------------------------------------

func _measure(sel: CanvasLayer, label: String, view_w: float) -> void:
	var panel: Control = _panel_of(sel)
	_expect(panel != null, "%s: the panel is reachable for measurement" % label)
	if panel == null:
		return
	var r: Rect2 = panel.get_global_rect()
	var need: Vector2 = panel.get_combined_minimum_size()
	# A ZERO IS NOT A PASS. An unlaid-out container reports nothing and would sail
	# under every ceiling below, which is how a screen ships broken with a green suite.
	_expect(r.size.x > 100.0 and r.size.y > 100.0,
		"%s: the panel reports a real drawn rect (got %.0fx%.0f)" % [label, r.size.x, r.size.y])
	_expect(need.y <= BASE_H,
		"%s: the class-select panel fits %.0f px of height (needs %.0f)"
			% [label, BASE_H, need.y])
	_expect(need.x <= view_w,
		"%s: it fits %.0f px of width (needs %.0f)" % [label, view_w, need.x])
	# ...and the DRAWN rect, not merely the requested minimum, is inside the viewport.
	# A `CenterContainer` will happily centre a panel that is wider than its parent,
	# which puts the left edge at a negative x with no error anywhere.
	_expect(r.position.x >= -0.5 and r.end.x <= view_w + 0.5,
		"%s: the drawn panel is inside the viewport horizontally (x %.0f .. %.0f of %.0f)"
			% [label, r.position.x, r.end.x, view_w])
	_expect(r.position.y >= -0.5 and r.end.y <= BASE_H + 0.5,
		"%s: and vertically (y %.0f .. %.0f of %.0f)"
			% [label, r.position.y, r.end.y, BASE_H])
	print("[layout] %s panel drawn %.0fx%.0f at (%.0f, %.0f), min %.0fx%.0f"
		% [label, r.size.x, r.size.y, r.position.x, r.position.y, need.x, need.y])


func _test_the_panel_fits_a_phone_at_640x360() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	_measure(sel, "640x360", BASE_W)
	_completes("the_panel_fits_a_phone_at_640x360")


## The `expand` aspect, honestly. A 20:9 phone gets a WIDER logical viewport at the same
## logical height -- so the thing this catches is not overflow (a fit at 640 fits at
## 800) but anything that ANCHORS or STRETCHES and changes shape as the viewport grows.
func _test_the_panel_fits_a_wide_phone_at_800x360() -> void:
	var sel: CanvasLayer = await _open_at(WIDE_W, BASE_H)
	_measure(sel, "800x360", WIDE_W)
	var panel: Control = _panel_of(sel)
	if panel != null:
		var r: Rect2 = panel.get_global_rect()
		# Centred, not stretched: the panel keeps its shape and the extra width becomes
		# margin. A panel that GREW to 800 would be a panel whose detail column reflows,
		# which is a different screen on a device nobody tested on.
		var mid: float = r.position.x + r.size.x * 0.5
		_expect(absf(mid - WIDE_W * 0.5) <= 2.0,
			"the panel stays centred on a wide phone (centre %.0f, wanted %.0f)"
				% [mid, WIDE_W * 0.5])
		_expect(r.size.x <= BASE_W,
			"...and keeps its shape rather than stretching into the extra width (%.0f px)"
				% r.size.x)
	_completes("the_panel_fits_a_wide_phone_at_800x360")


# ---------------------------------------------------------------------------
# 3. every tap target clears the thumb floor
# ---------------------------------------------------------------------------

func _test_every_row_clears_the_thumb_floor() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var cards: Array = sel.get("_cards") as Array
	_expect(cards != null and cards.size() == ClassInfo.count(),
		"the rail carries one row per class (%d of %d)"
			% [0 if cards == null else cards.size(), ClassInfo.count()])
	if cards == null:
		_completes("every_row_clears_the_thumb_floor")
		return
	for i: int in cards.size():
		var b: Button = cards[i] as Button
		var r: Rect2 = b.get_global_rect()
		_expect(r.size.y >= MIN_TAP_H,
			"row '%s' is at least %.0f px tall for a thumb (drawn %.1f)"
				% [b.text, MIN_TAP_H, r.size.y])
		# ⚠ AND THE DECLARED FLOOR, NOT ONLY THE DRAWN ONE. Godot's default theme
		# already gives a Button about 31 px of minimum height at font 13, so the DRAWN
		# check above passes even when `ROW_H` is set to 18 -- measured, by setting it to
		# 18 and watching this suite stay green. The drawn number is what the player
		# touches and the declared number is what the screen PROMISES; the promise is the
		# one that a future theme change can quietly stop honouring, so both are pinned.
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"row '%s' also DECLARES the %.0f px thumb floor (declared %.1f -- the theme is "
				% [b.text, MIN_TAP_H, b.custom_minimum_size.y]
			+ "currently covering for it, which is not the same as the screen asking for it)")
		_expect(r.size.x >= MIN_TAP_H,
			"row '%s' is at least %.0f px wide (drawn %.1f)" % [b.text, MIN_TAP_H, r.size.x])
		# The text has to actually be in the box. `clip_text` hides an overflow rather
		# than reporting one, so a row whose label needs more width than it has would
		# silently lose its last characters -- which on a locked row is the word that
		# says it is locked.
		var wanted: float = b.get_minimum_size().x
		_expect(wanted <= r.size.x + 0.5,
			"row '%s' is wide enough for its own label (wants %.0f, has %.0f)"
				% [b.text, wanted, r.size.x])
	_completes("every_row_clears_the_thumb_floor")


# ---------------------------------------------------------------------------
# 4. nothing overlaps
# ---------------------------------------------------------------------------

## SIBLINGS ONLY. A child is supposed to sit inside its parent, so a naive all-pairs
## sweep reports every container in the tree as overlapping its own contents. What is
## actually a bug is two SIBLINGS sharing pixels -- a row drawn over the row beneath it,
## or the rail drawn over the detail column -- which is what a container reports when it
## has been given a minimum size it cannot honour.
func _test_nothing_in_the_panel_overlaps() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var panel: Control = _panel_of(sel)
	if panel == null:
		_expect(false, "no panel to sweep")
		_completes("nothing_in_the_panel_overlaps")
		return
	var all: Array = []
	_walk(panel, all)
	_expect(all.size() > 12, "the sweep found a real tree to check (%d controls)" % all.size())
	var checked: int = 0
	for node: Variant in all:
		var parent: Control = node as Control
		var kids: Array[Control] = []
		for c: Node in parent.get_children():
			if c is Control and (c as Control).visible:
				kids.append(c as Control)
		for a: int in kids.size():
			for b: int in range(a + 1, kids.size()):
				var ra: Rect2 = kids[a].get_global_rect()
				var rb: Rect2 = kids[b].get_global_rect()
				if ra.size.x <= 0.0 or ra.size.y <= 0.0 or rb.size.x <= 0.0 or rb.size.y <= 0.0:
					continue
				# `intersects` is inclusive of touching edges in Godot when the second
				# argument is true; the default (exclusive) is what we want, since
				# stacked rows in a VBox share an edge by construction.
				checked += 1
				_expect(not ra.intersects(rb),
					"'%s' and '%s' overlap (%s vs %s)"
						% [kids[a].name, kids[b].name, str(ra), str(rb)])
	_expect(checked > 20, "the overlap sweep actually compared something (%d pairs)" % checked)
	_completes("nothing_in_the_panel_overlaps")


# ---------------------------------------------------------------------------
# 5. the roster is whole
# ---------------------------------------------------------------------------

## NINE ON SCREEN, NO SCROLLING. The rail exists so that the thing a player is choosing
## between is never behind a gesture. A `ScrollContainer` anywhere in this screen would
## mean some of the roster is hidden on the smallest device, so its absence is asserted
## rather than assumed -- and every row's drawn rect is checked to be inside the panel.
func _test_the_roster_is_whole_and_unscrolled() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var panel: Control = _panel_of(sel)
	var all: Array = []
	_walk(panel, all)
	for node: Variant in all:
		_expect(not (node is ScrollContainer),
			"the class rail must not scroll -- all %d classes have to be on screen at once"
				% ClassInfo.count())
	var cards: Array = sel.get("_cards") as Array
	if cards != null and panel != null:
		var pr: Rect2 = panel.get_global_rect()
		for i: int in cards.size():
			var r: Rect2 = (cards[i] as Control).get_global_rect()
			_expect(pr.encloses(r) or (r.position.y >= pr.position.y - 0.5
					and r.end.y <= pr.end.y + 0.5),
				"class row %d is inside the panel (row %s, panel %s)" % [i, str(r), str(pr)])
	_completes("the_roster_is_whole_and_unscrolled")


# ---------------------------------------------------------------------------
# 6. the detail column tells the truth
# ---------------------------------------------------------------------------

## THE POINT OF THE REBUILD. The screen used to be able to show
## `ClassInfo.CLASSES[i]["kit"]`, a hand-written string that has drifted from the real
## kit TWICE. The detail column derives from `SpellLibrary.build_for_class`, so this
## walks all nine classes and asserts the drawn names ARE the built hand and every one
## of them carries a description.
func _test_the_detail_column_names_the_spells_the_class_really_casts() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var names: Array = sel.get("_detail_names") as Array
	var blurbs: Array = sel.get("_detail_blurbs") as Array
	_expect(names != null and names.size() == SpellTier.SLOT_COUNT,
		"the detail column has one row per hotbar button (%d of %d)"
			% [0 if names == null else names.size(), SpellTier.SLOT_COUNT])
	if names == null or blurbs == null:
		_completes("the_detail_column_names_the_spells_the_class_really_casts")
		return
	for i: int in ClassInfo.count():
		sel.call("_refresh_detail", i)
		await process_frame
		var hand: Array = SpellLibrary.build_for_class(i)
		for n: int in mini(names.size(), hand.size()):
			var spell: SpellDef = hand[n] as SpellDef
			var drawn: String = (names[n] as Label).text
			_expect(drawn.contains(String(spell.display_name)),
				"%s slot %d draws the spell it really casts (drew '%s', casts '%s')"
					% [ClassInfo.name_for(i), n + 1, drawn, spell.display_name])
			var bl: String = (blurbs[n] as Label).text
			_expect(bl.strip_edges() != "",
				"%s / %s has a description on the class card"
					% [ClassInfo.name_for(i), spell.display_name])
	_completes("the_detail_column_names_the_spells_the_class_really_casts")
