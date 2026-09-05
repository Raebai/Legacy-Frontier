# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_hero_plate.gd
#
# THE PLAYER'S HEALTH LEFT THE PLAYER'S HEAD, AND THIS IS WHAT HOLDS IT THERE.
#
# ══ WHAT WAS ACTUALLY WRONG ═══════════════════════════════════════════════════
# Maker: *"the health bar is blocking the stick figure, the main one"* and *"remove
# the mana bar, we don't have that when in the tower"*. Both were true and neither
# was visible to any existing suite, because every existing suite tests BEHAVIOUR:
#
#   * `Hero._ready` built a 52x7 world-space bar 26px over a 31px rig, in a frame the
#     camera tightens onto that same rig. It covered the figure by construction.
#   * Under it, a 52x3 MANA bar. `Hero.gd:977` says in as many words that mana gates
#     nothing, and `Hero._physics_process` regenerates it at 20/sec toward max — so
#     the bar was pinned at 100% for the whole life of every hero ever spawned. A bar
#     that cannot move is not a readout, it is a smudge.
#   * And it was invisible to review: `Hero.gd:991` and `BotMatch.gd:1681` each carry
#     a comment saying `configure(show_mp)` "has never been passed true", while
#     `Hero.gd:1820` reads `bars.configure(self, true, -26.0)`. Two comments asserted
#     the absence of the thing the maker was looking at. **That is why `draws_mana()`
#     is a function and not a comment** — the removal is now something a suite can
#     fail on rather than something a reader can be reassured about.
#
# ══ WHY EACH TEST IS A MEASUREMENT ════════════════════════════════════════════
# ⚠ COMPARING `HudStyle.HERO_PLATE_*` TO ITSELF PROVES NOTHING — it is one constant
# read twice. So the live tests below build a fighter, a bound `AbilityBar` and a real
# camera, put them in a real viewport, let frames pass, and read `get_global_rect()`
# off the Control that is actually on the screen.
#
# ⚠ HEADLESS HAS NO WINDOW SO IT HAS NO ASPECT: `get_visible_rect()` falls back to a
# SQUARE 640x640, which would make every vertical figure here meaningless. `root.size`
# is set and frames are waited for — see `_process`'s state machine. And it is set
# TWICE: `project.godot` runs `aspect="expand"`, so a taller phone hands the HUD a
# WIDER logical viewport (about 800x360), not letterboxing. Anything anchored to the
# left edge survives that; anything anchored to the right edge has to be measured at
# both widths or it is not measured at all. `HudStyle.PAUSE_CORNER` is the standing
# proof — a fixed rect at x 580..640 describing a button that on an 800-wide screen
# sits at 746..790, 160px away.
extends SceneTree

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const BARS := preload("res://scripts/combat/CharacterBars.gd")

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
# A dead property read ABORTS the enclosing function and returns the type's zero,
# which a `failed += _test_x()` idiom reads as "no failures". So failures accumulate
# on the MEMBER `_fails` and every test records a completion sentinel as its last
# line: a test that aborts part-way is missing from `_completed` and fails BY ABSENCE.
const TESTS: Array[String] = [
	"no_mana_is_drawn_anywhere",
	"a_driven_player_gets_a_screen_plate",
	"the_head_bar_is_gone_for_a_plated_player",
	"an_undriven_fighter_keeps_its_head_bar",
	"the_plate_is_immune_to_the_camera",
	"the_plate_binds_to_its_own_hero",
	"two_players_do_not_share_a_corner",
	"hiding_the_bars_hides_the_plate",
	"the_plate_clears_the_hotbar_at_both_widths",
	"the_plate_clears_every_band_and_the_pause_corner",
	"the_right_dock_follows_the_right_edge",
	"the_pause_corner_follows_the_right_edge",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _step: int = 0

## Live nodes, built in step 1.
var _hero_a: Node2D = null
var _hero_b: Node2D = null
var _mob: Node2D = null
var _bars_a: CharacterBars = null
var _bars_b: CharacterBars = null
var _bars_mob: CharacterBars = null
var _cam: Camera2D = null
## Plate rect at the camera's two extremes — the zoom-immunity measurement.
var _rect_wide: Rect2 = Rect2()
var _rect_tight: Rect2 = Rect2()


## A fighter, reduced to the three things `CharacterBars` actually reads: `hp`,
## `max_hp`, and membership of the `"hero"` group.
##
## ⚠ A STUB RATHER THAN A REAL `Hero`, deliberately. `Hero._ready` builds a rig, a
## hurtbox, a class kit and a camera, and reads the `GameState` AUTOLOAD — which a
## `--script` run has not registered. Standing one up would make this suite fail for
## reasons that have nothing to do with where a health bar is drawn.
class Fighter extends Node2D:
	var max_hp: int = 100
	var hp: float = 100.0


## `AbilityBar` is instanced for real — `_find_bound_ability_bar` matches on `is
## AbilityBar` and on `bound_hero`, so a duck-typed stub would prove the lookup works
## against a thing the game does not have. Its `_ready` touches no autoload and its
## `_draw` returns early on an empty `_slots`, so an unfed one is inert.
func _build() -> void:
	_cam = Camera2D.new()
	root.add_child(_cam)
	_cam.make_current()

	_hero_a = _spawn_fighter(true, Vector2(0.0, 0.0))
	_hero_b = _spawn_fighter(true, Vector2(80.0, 0.0))
	_mob = _spawn_fighter(false, Vector2(160.0, 0.0))
	_bars_a = _attach_bars(_hero_a, true)
	_bars_b = _attach_bars(_hero_b, true)
	_bars_mob = _attach_bars(_mob, false)

	# Player one bottom-left, player two bottom-right — the corners `LocalCoop`
	# actually hands out (`LocalCoop._build_bar_for` sets `dock_right = true`).
	_spawn_hotbar(_hero_a, false, 0)
	_spawn_hotbar(_hero_b, true, 0)


func _spawn_fighter(is_hero: bool, at: Vector2) -> Node2D:
	var f := Fighter.new()
	f.position = at
	if is_hero:
		f.add_to_group(&"hero")
	root.add_child(f)
	return f


func _attach_bars(target: Node2D, show_mp: bool) -> CharacterBars:
	var b: CharacterBars = BARS.new()
	target.add_child(b)
	# ⚠ `show_mp` TRUE FOR THE HEROES, WHICH IS WHAT `Hero.gd:1820` PASSES. Passing
	# false here would test a call the game does not make and would let a restored
	# mana draw sail straight through this suite.
	b.configure(target, show_mp, -26.0)
	return b


func _spawn_hotbar(hero: Node2D, dock_right: bool, dock_row: int) -> AbilityBar:
	var layer := CanvasLayer.new()
	layer.layer = HudStyle.LAYER_HUD
	root.add_child(layer)
	var bar := AbilityBar.new()
	bar.bound_hero = hero
	bar.dock_right = dock_right
	bar.dock_row = dock_row
	layer.add_child(bar)
	return bar


## ⚠ `SceneTree._process` RETURNING **true** MEANS "QUIT THE TREE". This suite needs a
## dozen frames — set the window, build, let `_process` resolve the plate, move the
## camera twice, resize the window — so every frame but the last returns FALSE. Written
## the other way round it exits on frame 0, prints neither a PASS nor a FAIL line, and
## looks for all the world like a suite that ran.
func _process(_delta: float) -> bool:
	match _step:
		0:
			root.size = Vector2i(640, 360)
		1:
			_build()
		2, 3:
			pass                            # layout + the frames the plate resolves in
		4:
			_test_mana()
			_test_plate_exists()
			_test_head_bar_gone()
			_test_undriven_keeps_head_bar()
			_test_binding()
			_test_corners()
			_test_hiding()
			_cam.zoom = Vector2(HudStyle.ZOOM_WIDE, HudStyle.ZOOM_WIDE)
		5:
			pass
		6:
			_rect_wide = _bars_a.plate_rect()
			_cam.zoom = Vector2(HudStyle.ZOOM_TIGHT, HudStyle.ZOOM_TIGHT)
		7:
			pass
		8:
			_rect_tight = _bars_a.plate_rect()
			_test_zoom_immunity()
			_cam.zoom = Vector2.ONE * HudStyle.ZOOM_REF
			# ⚠ THE SECOND WIDTH. A 20:9 phone gets ~800x360 here, not letterboxing.
			root.size = Vector2i(800, 360)
		9, 10:
			pass
		_:
			_run_geometry()
			_finish()
			return true
	_step += 1
	return false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _finish() -> void:
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("hero-plate tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("hero-plate tests: all PASS")
		quit(0)


# ══════════════════════════════════════════════════════════════════════ 1
## The mana bar is gone, and it is gone in a way a comment cannot claim.
func _test_mana() -> void:
	for pair: Array in [[_bars_a, "player one"], [_bars_b, "player two"],
			[_bars_mob, "an enemy"]]:
		var b: CharacterBars = pair[0]
		_expect(not b.draws_mana(),
			"%s draws no mana (nothing in the game can lower it — see Hero.gd:977)"
			% pair[1])
	# ⚠ AND THE VALUE IS NOT EVEN TRACKED. `draws_mana()` returning false is a promise
	# the draw code has to keep; `_mp_ratio` being absent is proof it cannot be broken
	# by accident, because there is no longer a number for a restored draw to reach for.
	_expect(_bars_a.get(&"_mp_ratio") == null,
		("`_mp_ratio` is still a member of CharacterBars — the mana poll survived the "
		+ "removal of the mana draw, which is how a dead readout gets restored later"))
	_completes("no_mana_is_drawn_anywhere")


# ══════════════════════════════════════════════════════════════════════ 2
func _test_plate_exists() -> void:
	_expect(_bars_a.has_plate(),
		("player one has no screen plate — `_resolve_plate` found no `AbilityBar` "
		+ "bound to them, so their health is still over their head"))
	_expect(_bars_b.has_plate(), "player two has no screen plate")
	var r: Rect2 = _bars_a.plate_rect()
	_expect(r.size.is_equal_approx(HudStyle.HERO_PLATE_SIZE),
		"the plate measures %s on screen, not the declared %s"
		% [r.size, HudStyle.HERO_PLATE_SIZE])
	_completes("a_driven_player_gets_a_screen_plate")


# ══════════════════════════════════════════════════════════════════════ 3
## The maker's ask, stated as something that can fail.
func _test_head_bar_gone() -> void:
	_expect(not _bars_a.draws_head_bar(),
		("player one is STILL drawing a bar over their own figure — this is the exact "
		+ "thing the maker asked to be moved"))
	_expect(not _bars_b.draws_head_bar(), "player two is still drawing a head bar")
	_completes("the_head_bar_is_gone_for_a_plated_player")


# ══════════════════════════════════════════════════════════════════════ 4
## ...and the other half of the rule. An enemy, a bot ally and a remote peer have no
## hotbar and no corner, and a body with no readout at all is worse than one with a
## small readout on its head.
func _test_undriven_keeps_head_bar() -> void:
	_expect(not _bars_mob.has_plate(),
		("a fighter nobody is driving built a screen plate — with six enemies alive "
		+ "that is six plates and no way to tell which body any of them is"))
	_expect(_bars_mob.draws_head_bar(),
		"an undriven fighter lost its head bar and now has no health readout at all")
	_completes("an_undriven_fighter_keeps_its_head_bar")


# ══════════════════════════════════════════════════════════════════════ 5
## THE POINT OF THE MOVE, MEASURED. The head bar was a `Node2D`, so its on-screen size
## was its world size times a camera zoom that swings 5.6x DURING a fight;
## `HudStyle.ui_scale()` existed to cancel that out every frame. A `CanvasLayer` is not
## transformed by the camera, so there is nothing to cancel — and this is the assertion
## that says so, taken at the camera's two real extremes rather than argued.
func _test_zoom_immunity() -> void:
	_expect(_rect_wide.size.is_equal_approx(_rect_tight.size),
		("the plate measures %s at zoom %.2f and %s at zoom %.2f — a screen-space "
		+ "readout must not change size with the camera")
		% [_rect_wide.size, HudStyle.ZOOM_WIDE, _rect_tight.size, HudStyle.ZOOM_TIGHT])
	_expect(_rect_wide.position.is_equal_approx(_rect_tight.position),
		("the plate sits at %s at zoom %.2f and %s at zoom %.2f — it is being dragged "
		+ "by the camera, which means it is not on a CanvasLayer")
		% [_rect_wide.position, HudStyle.ZOOM_WIDE, _rect_tight.position,
			HudStyle.ZOOM_TIGHT])
	_expect(_rect_wide.size.x > 0.0,
		"the zoom measurement read an empty rect — the plate was never built")
	_completes("the_plate_is_immune_to_the_camera")


# ══════════════════════════════════════════════════════════════════════ 6
## ⚠ THE BUG THIS FORECLOSES ALREADY HAPPENED ONCE, ONE WIDGET OVER. `AbilityBar`
## found its hero with `get_first_node_in_group("hero")` and drew player one's
## cooldowns to both players — "worse than no bar at all, because it looks right"
## (`LocalCoop.gd:419`). A plate resolved by tree order would do it again.
func _test_binding() -> void:
	_expect(_bars_a.plate_docks_right() == false,
		"player one's plate docked RIGHT — it took player two's hotbar")
	_expect(_bars_b.plate_docks_right() == true,
		"player two's plate docked LEFT — it took player one's hotbar")
	_completes("the_plate_binds_to_its_own_hero")


# ══════════════════════════════════════════════════════════════════════ 7
func _test_corners() -> void:
	var a: Rect2 = _bars_a.plate_rect()
	var b: Rect2 = _bars_b.plate_rect()
	_expect(not a.intersects(b),
		"the two players' plates overlap: %s and %s" % [a, b])
	_completes("two_players_do_not_share_a_corner")


# ══════════════════════════════════════════════════════════════════════ 8
## ⚠ A `CanvasLayer` DOES NOT INHERIT ITS PARENT'S VISIBILITY, and `BotMatch` hides
## every fighter's bars with `(c as CharacterBars).visible = false` (BotMatch.gd:957)
## because a match draws its own fixed plates. Without the notification hook the tower
## plate would have sailed through that and stacked on top of the match's.
func _test_hiding() -> void:
	_bars_a.visible = false
	var layer: CanvasLayer = _plate_layer_of(_bars_a)
	_expect(layer != null, "the plate's CanvasLayer is reachable to be checked")
	if layer != null:
		_expect(not layer.visible,
			("the bars were hidden and the plate stayed on screen — a CanvasLayer does "
			+ "not inherit its parent's visibility, so BotMatch's hide is a no-op on it"))
	_bars_a.visible = true
	if layer != null:
		_expect(layer.visible, "the plate did not come back when the bars did")
	_completes("hiding_the_bars_hides_the_plate")


func _plate_layer_of(bars: Node) -> CanvasLayer:
	for c: Node in bars.get_children():
		if c is CanvasLayer:
			return c as CanvasLayer
	return null


# ══════════════════════════════════════════════════════════════ 9, 10, 11, 12
## The pure-geometry half, run at BOTH widths and for both docks. These call
## `hero_plate_rect` directly rather than reading a live node, because the point is the
## full matrix — two widths x two docks x two device scales — and standing up eight
## live players to measure eight rects would measure the same function eight times
## through a lot more machinery.
func _run_geometry() -> void:
	var widths: Array[float] = [HudStyle.BASE_VIEWPORT.x, 800.0]
	# The two hotbar heights the game actually produces: `AbilityBar.occupied_height()`
	# is `(BOTTOM_MARGIN + SLOT_SIZE) * k + 9k` = 69k, and `slot_scale()` is 1.0 on a
	# touchscreen, `DESKTOP_SCALE` 0.62 otherwise.
	var reserved: Array[float] = [69.0 * 0.62, 69.0]
	var live: float = AbilityBar.occupied_height()
	_expect(reserved.has(snappedf(live, 0.001)) or absf(live - 69.0) < 0.01
			or absf(live - 42.78) < 0.05,
		("`AbilityBar.occupied_height()` reports %.2f, which is neither of the two "
		+ "heights this test reasons about (%.2f desktop / %.2f touch) — the hotbar "
		+ "was resized and the plate's clearance was computed against a stale number")
		% [live, reserved[0], reserved[1]])

	# ── 9. clears the hotbar underneath it ────────────────────────────────────
	for w: float in widths:
		for h: float in reserved:
			for right: bool in [false, true]:
				var view := Vector2(w, 360.0)
				var r: Rect2 = _framed(HudStyle.hero_plate_rect(view, right, h))
				var hotbar_top: float = view.y - h
				_expect(r.position.y + r.size.y <= hotbar_top + 0.01,
					("at %s dock_right=%s the plate's bottom edge is %.1f and the "
					+ "hotbar starts at %.1f — they overlap")
					% [view, right, r.position.y + r.size.y, hotbar_top])
				_expect(r.position.x >= -0.01 and r.position.x + r.size.x <= view.x + 0.01,
					"at %s dock_right=%s the plate runs off the screen: %s"
					% [view, right, r])
	_completes("the_plate_clears_the_hotbar_at_both_widths")

	# ── 10. clears every band above it and the pause corner ───────────────────
	var bands: Array = [
		["rank", HudStyle.BAND_RANK], ["floor banner", HudStyle.BAND_FLOOR_BANNER],
		["boss bar", HudStyle.BAND_BOSS_BAR], ["boss mods", HudStyle.BAND_BOSS_MODS],
		["affix card", HudStyle.BAND_AFFIX], ["shout", HudStyle.BAND_SHOUT],
	]
	for w: float in widths:
		for h: float in reserved:
			for right: bool in [false, true]:
				var view := Vector2(w, 360.0)
				var r: Rect2 = _framed(HudStyle.hero_plate_rect(view, right, h))
				for band: Array in bands:
					var span: Array = band[1]
					_expect(not _spans_overlap(r.position.y, r.position.y + r.size.y,
							float(span[0]), float(span[1])),
						("at %s dock_right=%s the plate (y %.1f-%.1f) runs into the "
						+ "`%s` band (y %.0f-%.0f)")
						% [view, right, r.position.y, r.position.y + r.size.y,
							band[0], float(span[0]), float(span[1])])
				# ⚠ `pause_corner(view)`, NOT `PAUSE_CORNER`. The const is a fixed rect
				# at x 580..640 and the button is anchored to the right edge; checking
				# an 800-wide screen against it is checking against empty screen.
				_expect(not r.intersects(HudStyle.pause_corner(view)),
					"at %s dock_right=%s the plate %s is inside the pause corner %s"
					% [view, right, r, HudStyle.pause_corner(view)])
	_completes("the_plate_clears_every_band_and_the_pause_corner")

	# ── 11. the right dock is anchored to the RIGHT EDGE ──────────────────────
	# The aspect="expand" fault, pinned. A right-docked plate computed off
	# `BASE_VIEWPORT.x` would sit 160px inside an 800-wide screen and look, on a
	# 16:9 monitor, completely correct.
	for w: float in widths:
		var view := Vector2(w, 360.0)
		var r: Rect2 = HudStyle.hero_plate_rect(view, true, 69.0)
		_expect(absf((view.x - (r.position.x + r.size.x)) - HudStyle.HERO_PLATE_MARGIN_X)
				< 0.01,
			("at %s the right-docked plate's right edge is %.1f from the screen edge, "
			+ "not the %.1f margin — it is anchored to a CONSTANT width, and a phone's "
			+ "logical viewport is wider than the base")
			% [view, view.x - (r.position.x + r.size.x), HudStyle.HERO_PLATE_MARGIN_X])
	var left: Rect2 = HudStyle.hero_plate_rect(Vector2(800.0, 360.0), false, 69.0)
	_expect(is_equal_approx(left.position.x, HudStyle.HERO_PLATE_MARGIN_X),
		"the left-docked plate left its margin on a wide screen: x %.1f" % left.position.x)
	_completes("the_right_dock_follows_the_right_edge")

	# ── 12. and the same fault in the pause corner itself ─────────────────────
	var at_base: Rect2 = HudStyle.pause_corner(HudStyle.BASE_VIEWPORT)
	_expect(at_base.is_equal_approx(HudStyle.PAUSE_CORNER),
		("`pause_corner(BASE_VIEWPORT)` is %s but the const says %s — the function "
		+ "must agree with the const on the one screen the const is right about")
		% [at_base, HudStyle.PAUSE_CORNER])
	var at_wide: Rect2 = HudStyle.pause_corner(Vector2(800.0, 360.0))
	_expect(is_equal_approx(at_wide.position.x + at_wide.size.x, 800.0),
		("`pause_corner(800x360)` right edge is %.1f, not 800 — `PauseMenu` anchors its "
		+ "button to the right edge, so on the expanded viewport a 20:9 phone actually "
		+ "gets, the real button is at x 746..790 and the fixed const points at empty "
		+ "screen 160px away") % [at_wide.position.x + at_wide.size.x])
	_completes("the_pause_corner_follows_the_right_edge")


## The plate PLUS its frame, which is what is actually painted. Measuring the bare rect
## is how a layout test passes on a HUD that visibly touches.
func _framed(r: Rect2) -> Rect2:
	return r.grow(HudStyle.HERO_PLATE_FRAME)


func _spans_overlap(a0: float, a1: float, b0: float, b1: float) -> bool:
	return a0 < b1 and b0 < a1
