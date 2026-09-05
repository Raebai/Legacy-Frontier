# Run: godot --headless --path godot-project --script tools/slice_test_armory_layout.gd
#
# THE ARMOURY FITS A PHONE, AND ITS PAPER DOLL IS INSIDE ITS OWN BOX.
#
# This suite exists because the armoury has already shipped BROKEN AND UNNOTICED once:
# it measured 560x377 - seventeen pixels TALLER than the entire 640x360 base viewport -
# so the bottom of the panel was off the screen on the only platform this game targets.
# Nobody caught it because the panel's sole opener sat behind a literal `if false:`, and
# a screen nobody can reach is a screen nobody can measure. The rule that follows is
# that the layout gets asserted, not eyeballed.
#
# /!\ HEADLESS HAS NO WINDOW AND NO ASPECT. `get_visible_rect()` falls back to a SQUARE
# 640x640 unless the root viewport is sized explicitly, so a suite that trusts it is
# measuring a phone that does not exist - and a square viewport hides exactly the
# height overflow this file is here to catch. Every measurement below sets `root.size`
# and waits a frame first.
#
# TWO SIZES, because project.godot stretches with aspect="expand": a taller phone gets
# a WIDER logical viewport, not a taller one. 640x360 is the floor; 800x360 is the same
# height with the extra width a 20:9 handset hands over. Height is the budget that can
# actually be blown, so both cases pin it.
extends SceneTree

const LOADOUT_PATH: String = "res://scripts/Loadout.gd"
## ~9 mm of thumb at this scale. Matches the floor `slice_test_outfitter.gd` holds the
## Lobby to, deliberately - two screens with two different tap floors is one of them
## being wrong.
const MIN_TAP_H: float = 28.0
## The viewports every control is measured against.
const SIZES: Array[Vector2i] = [Vector2i(640, 360), Vector2i(800, 360)]

## Every test names itself here and calls `_completes` as its LAST line. A test that
## aborts halfway - because a member it reads has been renamed, which is the way these
## suites usually rot - prints no FAIL of its own and would otherwise pass VACUOUSLY.
const TESTS: Array[String] = [
	"the_panel_fits_every_phone",
	"every_tappable_clears_the_thumb_floor",
	"no_two_buttons_overlap",
	"the_doll_and_the_list_do_not_collide",
	"every_slot_marker_lands_on_the_doll",
	"the_menu_is_the_registry",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	# /!\ RETURNS FALSE, AND THAT IS LOAD-BEARING. `SceneTree._process` returning TRUE
	# quits the loop immediately - which would kill the coroutine below before its first
	# awaited frame and print NOTHING, the silent shape of a vacuous pass. `_run` owns
	# the quit; this only kicks it off.
	_run()
	return false


func _run() -> void:
	var lo: CanvasLayer = (load(LOADOUT_PATH) as GDScript).new() as CanvasLayer
	root.add_child(lo)
	await process_frame

	await _test_panel_fits(lo)
	await _test_tap_floor(lo)
	await _test_no_overlap(lo)
	await _test_doll_vs_list(lo)
	_test_markers_on_the_doll(lo)
	_test_menu_is_the_registry(lo)

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted - a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Armoury-layout tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Armoury-layout tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Size the root to a real phone and let the containers settle. TWO frames, not one:
## the first propagates the new root size, the second lets the nested containers
## (CenterContainer -> PanelContainer -> VBox -> HBox -> ScrollContainer) re-sort. One
## frame measures a layout mid-flight and reports numbers nobody will ever see.
func _at(size: Vector2i) -> void:
	root.size = size
	await process_frame
	await process_frame


## Collect every Button under `n`, depth-first.
func _buttons(n: Node, out: Array) -> void:
	for c: Node in n.get_children():
		if c is Button:
			out.append(c)
		_buttons(c, out)


## A control's rect as the PLAYER can reach it: its own rect, clipped by every
## ScrollContainer above it. A button scrolled out of view has a global rect that still
## sits wherever the content flowed to - overlapping whatever is drawn below the scroll -
## while being untappable and invisible. Comparing raw global rects therefore reports
## collisions that do not exist, which is how a measuring tool ends up lying with
## confidence. Returns a zero-sized rect when the control is fully clipped away.
func _visible_rect(c: Control) -> Rect2:
	var r: Rect2 = c.get_global_rect()
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			r = r.intersection((n as ScrollContainer).get_global_rect())
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				return Rect2()
		n = n.get_parent()
	return r


func _test_panel_fits(lo: CanvasLayer) -> void:
	for size: Vector2i in SIZES:
		await _at(size)
		lo.call("open")
		await process_frame
		var col: Control = lo.get("_col") as Control
		_expect(col != null, "the armoury column is reachable for measurement")
		if col == null:
			return
		# /!\ An invariant that is trivially true of a zero-sized control is not an
		# invariant. A container that never sorted measures 0x0 and would sail through
		# a fits-the-screen check while being completely broken.
		_expect(col.size.x > 100.0 and col.size.y > 100.0,
			"at %dx%d the column actually laid out (got %.0fx%.0f)"
				% [size.x, size.y, col.size.x, col.size.y])
		_expect(col.size.y <= float(size.y),
			"at %dx%d the armoury is %.0f px tall - the budget is %d"
				% [size.x, size.y, col.size.y, size.y])
		_expect(col.size.x <= float(size.x),
			"at %dx%d the armoury is %.0f px wide - the budget is %d"
				% [size.x, size.y, col.size.x, size.x])
		var g: Rect2 = col.get_global_rect()
		_expect(g.position.y >= -0.5 and g.end.y <= float(size.y) + 0.5,
			"at %dx%d the armoury sits ON screen vertically (y %.0f..%.0f)"
				% [size.x, size.y, g.position.y, g.end.y])
	_completes("the_panel_fits_every_phone")


func _test_tap_floor(lo: CanvasLayer) -> void:
	await _at(SIZES[0])
	lo.call("open")
	await process_frame
	var btns: Array = []
	_buttons(lo, btns)
	# 3 Defaults + 16 placeholders + Done. Pinned as a NUMBER because a sweep over an
	# empty list passes every assertion it contains.
	_expect(btns.size() == 20,
		"every piece is offered plus Default and Done (expected 20 buttons, found %d)"
			% btns.size())
	for b: Button in btns:
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"'%s' is at least %.0f px tall (got %.0f)"
				% [b.text, MIN_TAP_H, b.custom_minimum_size.y])
		_expect(b.size.x >= MIN_TAP_H,
			"'%s' is at least %.0f px wide (got %.0f)" % [b.text, MIN_TAP_H, b.size.x])
	_completes("every_tappable_clears_the_thumb_floor")


func _test_no_overlap(lo: CanvasLayer) -> void:
	for size: Vector2i in SIZES:
		await _at(size)
		lo.call("open")
		await process_frame
		var btns: Array = []
		_buttons(lo, btns)
		_expect(btns.size() >= 2, "there are at least two buttons to compare at %dx%d" % [size.x, size.y])
		var seen: int = 0
		for i: int in btns.size():
			for j: int in range(i + 1, btns.size()):
				var a: Rect2 = _visible_rect(btns[i] as Button)
				var b: Rect2 = _visible_rect(btns[j] as Button)
				if a.size.x <= 0.0 or a.size.y <= 0.0 or b.size.x <= 0.0 or b.size.y <= 0.0:
					continue   # scrolled out of sight: nothing to tap, nothing to collide with
				seen += 1
				# grow(-0.5) so two buttons that merely SHARE an edge (which every
				# packed container produces) are not reported as overlapping.
				_expect(not a.grow(-0.5).intersects(b.grow(-0.5)),
					"at %dx%d '%s' overlaps '%s' - one of them cannot be tapped"
						% [size.x, size.y, (btns[i] as Button).text, (btns[j] as Button).text])
		# /!\ THE ARMOUR ON THE CLIP-AWARE RULE ABOVE. Skipping invisible buttons is
		# correct - and it is also the exact shape of a test that quietly stops testing,
		# because a layout that scrolled EVERYTHING out of view would skip every pair and
		# pass in silence. So the number of pairs actually compared is itself asserted.
		_expect(seen >= 40,
			"at %dx%d enough buttons are on screen to be worth comparing (%d pairs)"
				% [size.x, size.y, seen])
	_completes("no_two_buttons_overlap")


## The doll and the piece list share one horizontal band, which is the whole reason the
## panel fits 360 px. If they ever overlap, the figure is drawn under the buttons.
func _test_doll_vs_list(lo: CanvasLayer) -> void:
	for size: Vector2i in SIZES:
		await _at(size)
		lo.call("open")
		await process_frame
		var doll: Control = lo.get("_doll") as Control
		var scroll: Control = lo.get("_scroll") as Control
		_expect(doll != null and scroll != null, "the doll and the list are both reachable")
		if doll == null or scroll == null:
			return
		_expect(doll.size.x > 10.0 and doll.size.y > 10.0,
			"at %dx%d the doll actually laid out (%.0fx%.0f)" % [size.x, size.y, doll.size.x, doll.size.y])
		_expect(not doll.get_global_rect().grow(-0.5).intersects(scroll.get_global_rect().grow(-0.5)),
			"at %dx%d the doll and the piece list do not overlap" % [size.x, size.y])
		var col: Control = lo.get("_col") as Control
		if col != null:
			_expect(col.get_global_rect().grow(1.0).encloses(doll.get_global_rect()),
				"at %dx%d the doll is inside the panel" % [size.x, size.y])
	_completes("the_doll_and_the_list_do_not_collide")


## The schematic markers are drawn in doll-LOCAL coordinates from the rig geometry, so a
## change to RIG_SCALE or RIG_FEET_Y moves them. This asserts they cannot walk off the
## edge of their own box, where they would read as a rendering fault rather than a
## diagram. Pure geometry - no frame needed.
func _test_markers_on_the_doll(lo: CanvasLayer) -> void:
	var consts: Dictionary = (load(LOADOUT_PATH) as GDScript).get_script_constant_map()
	var w: float = float(consts["DOLL_W"])
	var h: float = float(consts["DOLL_H"])
	var box := Rect2(Vector2.ZERO, Vector2(w, h))
	var slots: Array = consts["SLOTS"]
	_expect(slots.size() == 3, "there are three slots to place markers for (got %d)" % slots.size())
	const RING_R: float = 9.0
	for slot: String in slots:
		var c: Vector2 = lo.call("_slot_anchor", slot)
		_expect(box.has_point(c - Vector2(RING_R, RING_R)) and box.has_point(c + Vector2(RING_R, RING_R)),
			"the '%s' marker (ring at %.0f,%.0f r%.0f) sits inside the %.0fx%.0f doll box"
				% [slot, c.x, c.y, RING_R, w, h])
	# The three markers must also be distinguishable from each other, or the doll says
	# nothing about WHICH slot is filled.
	var head: Vector2 = lo.call("_slot_anchor", "head")
	var body: Vector2 = lo.call("_slot_anchor", "body")
	var weapon: Vector2 = lo.call("_slot_anchor", "weapon")
	_expect(head.distance_to(body) >= RING_R * 2.0, "the helm and armour markers do not sit on top of each other")
	_expect(weapon.distance_to(body) >= RING_R * 2.0, "the spellement and armour markers do not sit on top of each other")
	_completes("every_slot_marker_lands_on_the_doll")


## The menu is BUILT FROM `GearAbilities.PLACEHOLDER_SLOTS` rather than typed twice. A
## menu that duplicates its own catalogue can disagree with it, and the failure is
## silent: a typo'd id draws a button captioned with the raw id and equips a kind that
## has no ability row - which reads to a player as a broken item, not a missing one.
func _test_menu_is_the_registry(lo: CanvasLayer) -> void:
	var opts: Dictionary = lo.get("_options") as Dictionary
	_expect(not opts.is_empty(), "the armoury built its option lists")
	var offered: int = 0
	for slot: String in (load(LOADOUT_PATH) as GDScript).get_script_constant_map()["SLOTS"]:
		var list: Array = opts.get(slot, [])
		_expect(list.size() >= 2, "slot '%s' offers Default plus at least one piece" % slot)
		_expect(String(list[0]) == "", "slot '%s' offers Default first" % slot)
		var want: Array = GearAbilities.options_for(slot)
		_expect(list.size() == want.size() + 1,
			"slot '%s' offers exactly the registry (%d) plus Default, got %d"
				% [slot, want.size(), list.size()])
		for kind: String in want:
			_expect(list.has(kind), "slot '%s' offers registry piece '%s'" % [slot, kind])
			_expect(GearAbilities.has_ability(kind), "'%s' has an ability row to caption its button" % kind)
			offered += 1
	_expect(offered == 16, "all sixteen placeholders reach the menu (got %d)" % offered)
	_completes("the_menu_is_the_registry")
