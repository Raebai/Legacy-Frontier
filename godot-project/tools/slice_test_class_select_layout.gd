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
	"the_cursor_previews_a_class_without_becoming_it",
	"a_guarded_class_can_be_read_before_it_can_be_played",
	"every_character_on_the_screen_is_in_the_font_that_draws_it",
	"the_rail_wears_the_element_and_marks_the_class_you_are",
	"the_detail_column_draws_the_class_it_names",
	"the_screen_offers_change_spells_and_done_and_no_armoury",
	"an_on_element_spell_is_marked_and_a_class_with_none_is_not",
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
	await _test_the_cursor_previews_a_class_without_becoming_it()
	await _test_a_guarded_class_can_be_read_before_it_can_be_played()
	await _test_every_character_on_the_screen_is_in_the_font_that_draws_it()
	await _test_the_rail_wears_the_element_and_marks_the_class_you_are()
	await _test_the_detail_column_draws_the_class_it_names()
	await _test_the_screen_offers_change_spells_and_done_and_no_armoury()
	await _test_an_on_element_spell_is_marked_and_a_class_with_none_is_not()
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
	# THE TWO COLUMNS, SEPARATELY. The panel number alone cannot say WHICH column is
	# deciding the height, and that is the only number that matters when something is
	# added to one of them: the rail is nine fixed rows and cannot shrink, so every
	# addition to the detail column is free right up until it passes the rail and then
	# costs 1:1. Printed on every run so the next person adding a row can see the slack
	# instead of discovering it as an overflow.
	var rail: Control = sel.get("_rail") as Control
	var detail: Control = sel.get("_detail") as Control
	if rail != null and detail != null:
		# MINIMUMS, not drawn sizes. Both columns are stretched to the taller of the two
		# by the HBox, so a drawn number tells you nothing about which one is deciding.
		var rmin: Vector2 = rail.get_combined_minimum_size()
		var dmin: Vector2 = detail.get_combined_minimum_size()
		print("[layout] %s rail needs %.0fx%.0f | detail needs %.0fx%.0f -> the %s decides"
			% [label, rmin.x, rmin.y, dmin.x, dmin.y,
				"rail" if rmin.y >= dmin.y else "detail"]
			+ " (drawn band %.0f, %.0f px of the %.0f ceiling left on the panel)"
				% [rail.size.y, BASE_H - panel.get_combined_minimum_size().y, BASE_H])


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


# ---------------------------------------------------------------------------
# 7. the preview
# ---------------------------------------------------------------------------

## Maker: *"in the class selection be able to press up and down and hover over the
## options so that you can see exactly whats within each one"*.
##
## The screen's standing contract is that ONE TAP COMMITS, so the thing that has to
## be proven is not that the arrow keys move something — it is that they move it
## WITHOUT committing. A preview that quietly wrote `selected_class` would look
## identical on screen and would change your class every time you scrolled past one.
##
## ⚠ DRIVEN THROUGH `push_input`, NOT BY CALLING `_move_cursor`. Calling the mover
## directly would pass on a build where the keys never reach it at all, and reaching
## it is the entire feature: Godot's own focus walk consumes `ui_up`/`ui_down` before
## `_unhandled_input` sees them, which is why the rail rows are `FOCUS_NONE`. A test
## that skips the input path cannot notice that regression.
func _test_the_cursor_previews_a_class_without_becoming_it() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var gs: Node = root.get_node_or_null("/root/GameState")
	_expect(gs != null, "GameState is up, so `selected_class` can be watched")
	if gs == null:
		_completes("the_cursor_previews_a_class_without_becoming_it")
		return
	var was: int = int(gs.get("selected_class"))
	_expect(int(sel.get("_cursor")) == was,
		"the cursor opens on the class you are (%d), not on the top of the list (%d)"
			% [was, int(sel.get("_cursor"))])
	_expect(int(sel.get("_detail_for")) == was,
		"...and the column opens describing that same class")
	await _press(&"ui_down")
	var moved: int = int(sel.get("_cursor"))
	_expect(moved != was,
		"DOWN did not move the cursor (still %d). The arrow never reached" % moved
		+ " `_unhandled_input` — check that the rail rows are still FOCUS_NONE, because a"
		+ " focusable Button eats ui_down for its own focus walk.")
	_expect(int(sel.get("_detail_for")) == moved,
		"the detail column followed the cursor to %d (it is showing %d)"
			% [moved, int(sel.get("_detail_for"))])
	# THE HALF THAT MATTERS.
	_expect(int(gs.get("selected_class")) == was,
		"scrolling the roster CHANGED YOUR CLASS from %d to %d. Moving the cursor is a"
			% [was, int(gs.get("selected_class"))]
		+ " preview; only a press may commit.")
	_expect(bool(sel.call("is_open")), "...and it did not close the screen either")
	# A HOVERING MOUSE IS THE SAME CURSOR, not a second one. Emitted rather than
	# simulated with a motion event: headless has no pointer, and what is being checked
	# is the wiring from the row's own signal.
	var cards: Array = sel.get("_cards") as Array
	var far: int = maxi(ClassInfo.count() - 1, 0)
	if far != moved and far < cards.size():
		(cards[far] as Button).mouse_entered.emit()
		await process_frame
		_expect(int(sel.get("_cursor")) == far,
			"hovering row %d left the cursor on %d" % [far, int(sel.get("_cursor"))])
		_expect(int(sel.get("_detail_for")) == far,
			"...and the column did not follow the hover")
		_expect(int(gs.get("selected_class")) == was,
			"a hover committed a class change")
	_completes("the_cursor_previews_a_class_without_becoming_it")
## The roster SHOWS the three guarded classes rather than hiding them, on the stated
## grounds that a player has to be able to want a thing before it can be a reward. Two
## properties follow from that, and both were broken:
##
##   1. A GUARDED ROW MUST LOOK GUARDED. `_refresh_locks` set `modulate.a = 0.45` and
##      `open()` then called a painter that assigned a whole `modulate`, alpha included,
##      so all nine rows were drawn at full strength and only the `· guarded` suffix
##      distinguished the three that cannot be played. Two writers, one property, and
##      the loser carried the meaning.
##   2. A GUARDED ROW MUST STILL BE READABLE. Godot's built-in focus walk skips
##      DISABLED controls, so keyboard navigation would have jumped over exactly the
##      three rows a preview is most for.
##
## ⚠ THE LOCK IS FORCED ON THE SCREEN, NOT ON THE SAVE, and that is deliberate.
## `Progression.ALL_CLASSES_UNLOCKED` is TRUE in this build (the maker asked to see the
## whole roster), so `is_class_unlocked` answers true for all nine and a test that drove
## this through `unlocked_classes` would pass by testing nothing — which is exactly what
## the first version of it did. Driving the screen's own `_unlocked` row instead pins the
## PAINTER'S contract, which is the thing that broke, and keeps holding whichever way the
## roster gate is set.
func _test_a_guarded_class_can_be_read_before_it_can_be_played() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var cards: Array = sel.get("_cards") as Array
	var unlocked: Array = sel.get("_unlocked") as Array
	_expect(cards.size() > 1 and unlocked.size() == cards.size(),
		"the screen tracks an unlock flag per row (%d rows, %d flags)"
			% [cards.size(), unlocked.size()])
	if cards.size() < 2 or unlocked.size() != cards.size():
		_completes("a_guarded_class_can_be_read_before_it_can_be_played")
		return
	# Read from the script rather than retyped, so a re-tune of the dim does not turn
	# this into a test of a number nobody uses any more.
	var consts: Dictionary = (load(SELECT_SCRIPT) as GDScript).get_script_constant_map()
	var dim: float = float(consts["LOCKED_DIM"])
	_expect(dim < 1.0, "LOCKED_DIM (%.2f) actually dims something" % dim)
	var guarded: int = cards.size() - 1          # the last row, whichever class that is
	var elsewhere: int = 0
	unlocked[guarded] = false
	(cards[guarded] as Button).disabled = true   # what `_refresh_locks` would have done
	sel.set("_cursor", elsewhere)
	sel.call("_paint_cursor")
	await process_frame
	var a: float = (cards[guarded] as Button).modulate.a
	_expect(is_equal_approx(a, dim),
		"a guarded row is drawn at alpha %.2f, not %.2f — it reads as available, and the"
			% [a, dim]
		+ " painter has gone back to overwriting the dim the way `_refresh_locks` used to"
		+ " have it overwritten")
	_expect(is_equal_approx((cards[elsewhere] as Button).modulate.a, 1.0),
		"an unguarded row was dimmed too — the alpha is not tracking the lock at all")
	# ...and it can still be READ. `disabled` is true on it, which is precisely what
	# Godot's focus walk refuses to visit.
	(cards[guarded] as Button).mouse_entered.emit()
	await process_frame
	_expect(int(sel.get("_detail_for")) == guarded,
		"a guarded row cannot be previewed (the column is on %d, not %d) — a locked class"
			% [int(sel.get("_detail_for")), guarded]
		+ " you cannot read is not a goal, it is an absence with a label on it")
	_expect(is_equal_approx((cards[guarded] as Button).modulate.a, dim),
		"the row stopped looking guarded as soon as the cursor landed on it")
	_completes("a_guarded_class_can_be_read_before_it_can_be_played")


# ---------------------------------------------------------------------------
# 8. the restyle: the font, the rail, the figure, the exits, the affinity mark
# ---------------------------------------------------------------------------

## ⚠ THIS IS THE ONE THAT WOULD HAVE CAUGHT THE BUG THE RESTYLE FOUND. The rail led
## every row with `SWATCH = "█"` (U+2588), described in the source as "the leading block
## on a rail row, drawn in the class colour" — the thing a player was supposed to read
## the roster by. It is not in the font. `assets/ui/stickspire_theme.tres` sets no font
## resource, so every Label and Button on this screen falls back to Godot's built-in Open
## Sans subset, and that font answers `has_char` FALSE for U+2588 — and for U+258C,
## U+2502, U+25C6, U+25CF, U+2726, U+2744 (❄), U+26A1 (⚡) and U+2694 (⚔), which is most
## of what a nicer rail row would reach for next. Only Latin-1 and General Punctuation
## come back true.
##
## Nothing on screen said so. A missing glyph is not an error, not a warning and not a
## crash — it is a blank, or a box, depending on the platform's own font fallback, which
## means it can look FINE on the machine that shipped it. So the rule is now a test:
## every character this screen draws must be in the font that will draw it.
##
## ⚠ ASKED OF THE CONTROL'S OWN FONT, NOT OF `ThemeDB.fallback_font`. The two are the
## same today only because the project theme declares no font; the moment somebody adds
## one, a test that kept asking the fallback would be checking a font nobody sees.
func _test_every_character_on_the_screen_is_in_the_font_that_draws_it() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var panel: Control = _panel_of(sel)
	if panel == null:
		_expect(false, "no panel to sweep for glyphs")
		_completes("every_character_on_the_screen_is_in_the_font_that_draws_it")
		return
	# Every class, because the detail column's text is per-class and only one class is
	# drawn at a time. A sweep of whatever happened to be selected is a sweep of one ninth.
	var checked: int = 0
	var seen: Dictionary = {}
	for c: int in ClassInfo.count():
		sel.call("_refresh_detail", c)
		await process_frame
		var all: Array = []
		_walk(panel, all)
		for node: Variant in all:
			var ctrl: Control = node as Control
			var text: String = ""
			if ctrl is Label:
				text = (ctrl as Label).text
			elif ctrl is Button:
				text = (ctrl as Button).text
			if text == "":
				continue
			var font: Font = ctrl.get_theme_font(&"font")
			if font == null:
				font = ThemeDB.fallback_font
			for k: int in text.length():
				var cp: int = text.unicode_at(k)
				if cp <= 32 or seen.has(cp):
					continue
				seen[cp] = true
				checked += 1
				_expect(font.has_char(cp),
					"the screen draws U+%04X ('%s', in '%s') and the font it will be drawn"
						% [cp, String.chr(cp), text]
					+ " with does not have that glyph — it renders as a blank or a box on"
					+ " the player's machine with no error anywhere. Draw it (a rect, a"
					+ " stylebox border) or use a Latin-1 character.")
	_expect(checked > 20,
		"the glyph sweep actually looked at something (%d distinct characters)" % checked)
	_completes("every_character_on_the_screen_is_in_the_font_that_draws_it")


## THE RAIL'S TWO SIGNALS, WHICH USED TO BE ONE.
##
## `_paint_cursor` wrote `PAD_CURSOR` or `HIGHLIGHT` into a single `modulate`, so a row
## could say "you are here" or "this is you" but never both — and because `modulate`
## multiplies the WHOLE row, a cursor sitting on a class also washed the colour out of
## the one row the player was looking at. They are two channels now: the left border is
## the class's ELEMENT and widens on the class you are; the fill is the cursor.
##
## Driven through the screen's own painter with a real selection, not by reading the
## constants back: the constants were never the thing that broke.
func _test_the_rail_wears_the_element_and_marks_the_class_you_are() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var styles: Array = sel.get("_row_styles") as Array
	var cards: Array = sel.get("_cards") as Array
	_expect(styles != null and cards != null and styles.size() == cards.size(),
		"one row style per rail row (%d styles, %d rows)"
			% [0 if styles == null else styles.size(), 0 if cards == null else cards.size()])
	if styles == null or cards == null or styles.size() != cards.size():
		_completes("the_rail_wears_the_element_and_marks_the_class_you_are")
		return
	var chosen: int = int(sel.call("_selected_class"))
	# Park the cursor somewhere that is NOT the selected class, so "where I am" and
	# "what I am" are on two different rows and can be told apart at all.
	var elsewhere: int = 0 if chosen != 0 else 1
	sel.set("_cursor", elsewhere)
	sel.call("_paint_cursor")
	await process_frame
	var wide: int = 0
	for i: int in styles.size():
		var sb: StyleBoxFlat = styles[i] as StyleBoxFlat
		_expect(sb != null, "row %d has a StyleBoxFlat to paint" % i)
		if sb == null:
			continue
		var want: Color = Elements.color(int(sel.call("_element_of", i)))
		_expect(is_equal_approx(sb.border_color.r, want.r)
				and is_equal_approx(sb.border_color.g, want.g)
				and is_equal_approx(sb.border_color.b, want.b),
			"row %d (%s) wears element colour %s, not its own %s — the accent bar is the"
				% [i, ClassInfo.name_for(i), str(sb.border_color), str(want)]
			+ " only thing on the row that says which element the class is")
		_expect(sb.border_color.a > 0.0 and sb.get_border_width(SIDE_LEFT) > 0,
			"row %d has a visible accent bar at all" % i)
		if sb.get_border_width(SIDE_LEFT) > int(sel.get("_row_styles")[elsewhere]
				.get_border_width(SIDE_LEFT)):
			wide += 1
	var mine: StyleBoxFlat = styles[chosen] as StyleBoxFlat
	var other: StyleBoxFlat = styles[elsewhere] as StyleBoxFlat
	_expect(mine.get_border_width(SIDE_LEFT) > other.get_border_width(SIDE_LEFT),
		"the class you ARE (%d) has a louder accent bar than one you are not (%d vs %d px)"
			% [chosen, mine.get_border_width(SIDE_LEFT), other.get_border_width(SIDE_LEFT)])
	_expect(wide == 1,
		"exactly ONE row is marked as the class you are (found %d)" % wide)
	_expect(other.bg_color.a > 0.0,
		"the row under the CURSOR is filled, so 'where I am' reads separately from"
		+ " 'what I am' (alpha %.2f)" % other.bg_color.a)
	_expect(mine.bg_color.a < other.bg_color.a,
		"...and the cursor's fill is the louder of the two (%.2f vs %.2f), or walking the"
			% [other.bg_color.a, mine.bg_color.a]
		+ " rail loses track of where the cursor is")
	_completes("the_rail_wears_the_element_and_marks_the_class_you_are")


## THE FIGURE. Maker: *"way more aesthetic"*, and a drawn body of the class you are about
## to become is the single biggest lever this screen had — it costs no panel height
## because it fits inside the detail column's measured slack against the rail.
##
## ⚠ WHAT IS ASSERTED IS THAT IT FOLLOWS THE CLASS, not that it exists. A doll that is
## built once and never re-dressed looks completely correct on the class the screen
## opened on and is a lie on the other eight — and that is a bug with no symptom until
## somebody scrolls.
func _test_the_detail_column_draws_the_class_it_names() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var doll: Control = sel.get("_doll") as Control
	var rig: Node2D = sel.get("_rig") as Node2D
	_expect(doll != null and rig != null, "the detail column carries a paper doll")
	if doll == null or rig == null:
		_completes("the_detail_column_draws_the_class_it_names")
		return
	var r: Rect2 = doll.get_global_rect()
	_expect(r.size.x > 24.0 and r.size.y > 24.0,
		"the doll has a real drawn rect (%.0fx%.0f) — a zero-size Control draws a rig"
			% [r.size.x, r.size.y]
		+ " that is clipped to nothing and reports no error")
	_expect(rig.get_parent() == doll, "the rig is inside the doll's own rect")
	# ⚠ CLIPPED. A Control does not bound its children, and a rig draws a hood, a hammer
	# and loose limbs well past its origin — unclipped, the figure is drawn ACROSS the
	# rail rows to its left and reads as a rendering fault.
	_expect(doll.clip_contents,
		"the doll clips its contents, or the figure spills over the rail beside it")
	# IT FOLLOWS THE CLASS. Two classes with different colours and different weapons.
	var tints: Array[Color] = []
	var weapons: Array[String] = []
	for c: int in ClassInfo.count():
		sel.call("_refresh_detail", c)
		await process_frame
		tints.append(rig.get("limb_color") as Color)
		weapons.append(String((rig.get("equipment") as Dictionary).get("weapon", "")))
	var distinct_tints: Dictionary = {}
	for t: Color in tints:
		distinct_tints[t.to_html(false)] = true
	_expect(distinct_tints.size() >= ClassInfo.count() - 1,
		"the figure is re-tinted per class (%d distinct tints over %d classes) — a doll"
			% [distinct_tints.size(), ClassInfo.count()]
		+ " that keeps one colour is a picture, not a preview")
	var distinct_weapons: Dictionary = {}
	for w: String in weapons:
		distinct_weapons[w] = true
	# ⚠ THE WEAPON, NOT ONLY THE COLOUR, and the class-identity ruling is why: four of the
	# nine presets name a generic "staff" or "sword" while the class actually carries
	# `staff_ice` / `staff_storm` / `void_rod` / `dagger_shadow`. Applying the preset alone
	# would put one stick in four hands and make the doll a recolour.
	_expect(distinct_weapons.size() >= 4,
		"the figure carries the class's OWN weapon (%d distinct over %d classes: %s)"
			% [distinct_weapons.size(), ClassInfo.count(), str(distinct_weapons.keys())])
	# ⚠ AND SPECIFICALLY THE `weapon_look`, WHICH THE PRESET ALONE DOES NOT GIVE. The
	# count above is not enough on its own — seven of the nine presets already name
	# different sticks, so it stays green on a doll dressed by `class_preset` only. The
	# Shadowblade is the case with teeth: its preset is "rogue", which hands out a plain
	# `sword`, while the class actually carries `dagger_shadow`. If this row reads
	# "sword", `Hero._apply_class`'s last step has been skipped and the assassin is
	# previewed holding the duelist's blade.
	var shadow: int = ClassInfo.names().find("Shadowblade")
	if shadow >= 0 and shadow < weapons.size():
		_expect(weapons[shadow] == "dagger_shadow",
			"the Shadowblade's doll holds '%s'. `class_preset(\"rogue\")` hands out a"
				% weapons[shadow]
			+ " generic sword; the class's `weapon_look` is what makes it the class's own"
			+ " dagger, and Hero applies it LAST for exactly this reason.")
	_completes("the_detail_column_draws_the_class_it_names")


## THE TWO EXITS, AND THE ONE THE MAKER ASKED TO REMOVE.
##
## Verbatim: *"there should be class selection as the main theme and then a change spells
## button, no need for the armoury button within the class selection"*.
##
## ⚠ THE FOOTER MUST NOT RENUMBER THE ROSTER. `tools/slice_test_town.gd` drives the
## class/spell-pad merge by walking THIS screen for Buttons and indexing the result BY
## CLASS — so a Button added anywhere ahead of the rail would silently make card 0 mean
## something else in a suite this file does not own. Asserted here rather than discovered
## there.
func _test_the_screen_offers_change_spells_and_done_and_no_armoury() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var panel: Control = _panel_of(sel)
	var all: Array = []
	_walk(panel, all)
	var buttons: Array[Button] = []
	for node: Variant in all:
		if node is Button:
			buttons.append(node as Button)
	var cards: Array = sel.get("_cards") as Array
	_expect(buttons.size() == cards.size() + 2,
		"the screen has the nine rows plus exactly two exits (%d buttons, %d rows)"
			% [buttons.size(), cards.size()])
	for i: int in mini(cards.size(), buttons.size()):
		_expect(buttons[i] == cards[i],
			"button %d in tree order is still class row %d — a Button ahead of the rail"
				% [i, i]
			+ " renumbers the roster under `slice_test_town`'s merge test")
	var words: String = ""
	for b: Button in buttons:
		words += b.text.to_lower() + "|"
	_expect(words.contains("change spells"),
		"the footer offers CHANGE SPELLS (buttons: %s)" % words)
	_expect(words.contains("done"), "the footer offers DONE (buttons: %s)" % words)
	_expect(not words.contains("armo"),
		"the armoury button is GONE from this screen — the maker asked by name, and the"
		+ " armoury is its own pad in the town and its own door on the lobby Outfitter"
		+ " (buttons: %s)" % words)
	for i: int in range(cards.size(), buttons.size()):
		var b: Button = buttons[i]
		_expect(b.get_global_rect().size.y >= MIN_TAP_H,
			"exit '%s' clears the %.0f px thumb floor (drawn %.1f)"
				% [b.text, MIN_TAP_H, b.get_global_rect().size.y])
		# ⚠ `FOCUS_NONE`, FOR THE SAME REASON THE RAIL ROWS ARE. Godot's focus walk eats
		# `ui_up`/`ui_down` before `_unhandled_input` ever sees them, so the instant a
		# player clicked one of these the arrow-key preview would stop working — with no
		# error, and only on a build where somebody had touched the footer first.
		_expect(b.focus_mode == Control.FOCUS_NONE,
			"exit '%s' is FOCUS_NONE, or clicking it kills the arrow-key preview" % b.text)
	# DONE ACTUALLY CLOSES. A footer button that only looks like an exit is the failure
	# this whole file is written against.
	var done: Button = null
	for b: Button in buttons:
		if b.text.to_lower().contains("done"):
			done = b
	if done != null:
		done.pressed.emit()
		await process_frame
		_expect(not bool(sel.call("is_open")), "pressing DONE really closes the screen")
	_completes("the_screen_offers_change_spells_and_done_and_no_armoury")


## ELEMENT AFFINITY, WHERE A PLAYER CAN ACTUALLY LEARN IT.
##
## A spell of the class's own element is worth `SpellCaster.AFFINITY_MULT` in that
## class's hands. The fight rings the slot; this screen is the OTHER place, and it is the
## one you read before you have committed to the class.
##
## ⚠ AND THE BRAWLER IS ASSERTED TO SHOW NOTHING. Its class element is FIRE while every
## spell in its hand is EARTH, so affinity pays it nothing at all. That is a live design
## question for the maker (`SpellCaster.affinity_mult` says so at length) and NOT a thing
## this screen may paper over — a layout that always marked something would quietly claim
## every class has an amplified spell.
func _test_an_on_element_spell_is_marked_and_a_class_with_none_is_not() -> void:
	var sel: CanvasLayer = await _open_at(BASE_W, BASE_H)
	var names: Array = sel.get("_detail_names") as Array
	if names == null or names.is_empty():
		_expect(false, "no spell rows to read the affinity mark from")
		_completes("an_on_element_spell_is_marked_and_a_class_with_none_is_not")
		return
	var tag: String = String(sel.get("_affinity_tag")).strip_edges()
	_expect(tag != "" and tag.contains("25"),
		"the mark is derived from SpellCaster.AFFINITY_MULT (%.2f), so a re-tune cannot"
			% SpellCaster.AFFINITY_MULT
		+ " leave the card quoting a number the fight stopped paying (got '%s')" % tag)
	var marked_classes: int = 0
	var brawler: int = -1
	for c: int in ClassInfo.count():
		if ClassInfo.name_for(c) == "Brawler":
			brawler = c
		sel.call("_refresh_detail", c)
		await process_frame
		var elem: int = int(sel.call("_element_of", c))
		var hand: Array = ClassInfo.carried_spells(c)
		var marked_here: int = 0
		var should: int = 0
		for n: int in mini(names.size(), hand.size()):
			var spell: SpellDef = hand[n] as SpellDef
			var drawn: String = (names[n] as Label).text
			var on_element: bool = SpellCaster.resolve_element(spell) == elem
			if on_element:
				should += 1
			if drawn.contains(tag):
				marked_here += 1
			_expect(drawn.contains(tag) == on_element,
				"%s / %s: the card %s the affinity mark and the fight %s amplify it"
					% [ClassInfo.name_for(c), spell.display_name,
						"shows" if drawn.contains(tag) else "omits",
						"does" if on_element else "does not"])
		_expect(marked_here == should,
			"%s marks %d of the %d spells its own element amplifies"
				% [ClassInfo.name_for(c), marked_here, should])
		if marked_here > 0:
			marked_classes += 1
	_expect(marked_classes >= 5,
		"the mark reaches most of the roster (%d of %d classes) — if it reaches almost"
			% [marked_classes, ClassInfo.count()]
		+ " none, the rule being read here is not the rule the fight uses")
	# ⚠ THE HOLE WAS CLOSED AND THIS ASSERTION IS THE OTHER HALF OF THE SAME GUARD.
	# It used to read "the Brawler is marked as having an on-element spell … if that
	# changed, the maker changed it, and this line is the notice" — and the maker did
	# change it: *"make the brawler an earth rank"* (`Hero.CLASS_CONFIG`, commit
	# da6ec14). Its class element is EARTH now and its whole hand — Stomp, Petrify,
	# Rock Wall, Boulder Hurl, Meteor Fist — is EARTH, so it is the class affinity pays
	# MOST, not least. Flipping the assertion rather than deleting it keeps the same
	# tripwire pointed the other way: the melee class falling back off the affinity
	# ladder now goes red here.
	#
	# It stays a SEPARATE named case rather than folding into the loop above because
	# this class is the one the roster-wide `marked_classes >= 5` line can never speak
	# for: a five-of-nine floor passes with the Brawler unpaid, which is exactly the
	# state that shipped.
	if brawler >= 0:
		sel.call("_refresh_detail", brawler)
		await process_frame
		var marked: int = 0
		for n: int in names.size():
			if (names[n] as Label).text.contains(tag):
				marked += 1
		_expect(marked > 0,
			"the Brawler's card marks no on-element spell. Its class element is EARTH"
			+ " and its whole hand is EARTH, so affinity should pay it on every slot —"
			+ " if the class was re-elemented again, this line is the notice.")
	_completes("an_on_element_spell_is_marked_and_a_class_with_none_is_not")


## One keypress, delivered the way the game gets it. `InputEventAction` is enough:
## everything on this screen reads actions, never keycodes, which is the D-011 rule
## that lets a virtual pad drive the same screen.
func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	root.push_input(ev)
	await process_frame
