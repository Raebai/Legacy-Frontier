# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_hud_layout.gd
#
# THE COMBAT HUD IS ONE LAYOUT, AND THIS IS WHAT HOLDS IT TO THAT.
#
# ══ WHAT WAS ACTUALLY WRONG ═══════════════════════════════════════════════════
# Ten HUD files each picked their own CanvasLayer index and their own offset_top,
# and a survey of the result found four collisions — none of them rare, all of them
# invisible to every existing suite because every existing suite tests BEHAVIOUR:
#
#   * `Hype.HUD_LAYER` was 55 and `Boss._build_bar`'s layer was 55. Two CanvasLayers
#     on the same index fall back to TREE ORDER, so which drew on top depended on
#     whether the Arena had built Hype before the boss spawned. And they overlapped
#     for real: the shout ran y62-96, the bar strip y64-79. Every boss fight.
#   * the chain counter (x480-628, y34+) sat on top of the pause BUTTON (44x44 at a
#     10px margin, x586-630, y10-54) — the only pause affordance a phone has.
#   * the rank title (y~2-25) and the floor banner (y~18-41) shared layer 50, were
#     both PRESET_TOP_WIDE and both centred on x=320; their outline bands overlapped.
#   * the floor affix card (y54-84) crossed the boss bar, and its wrap held exactly
#     two rows — a THIRD affix grew symmetrically out of the centred VBox and spilled
#     into `BossModifierHud.TOP` at y84. The boss bar's Control rect ALSO ran to y100
#     while drawing nothing below y79, so the modifier row at y84 was inside it and
#     the two were kept apart only by `APPEAR_DELAY = 1.35` — a timing coincidence.
#
# ══ WHY IT IS MEASURED AND NOT COMPARED ═══════════════════════════════════════
# ⚠ A TEST THAT COMPARES `HudStyle.BAND_X` TO THE `offset_top` A FILE TYPED PROVES
# NOTHING — it is the same two constants read twice. So every band below is measured
# off a LIVE node: the widget is built the way the game builds it, put in a real
# viewport, given a frame to lay out, and its `get_global_rect()` is read. That is
# the rect the player gets. The band constants are then the contract that rect must
# satisfy, and a widget that silently grows (a third affix row, a longer boss name,
# a louder shout) fails here rather than on the maker's screen.
#
# ⚠ HEADLESS HAS NO WINDOW SO IT HAS NO ASPECT: `get_visible_rect()` falls back to a
# SQUARE 640x640 and every vertical measurement would be taken against the wrong
# screen. `root.size` is set and a frame is waited for before anything is measured
# — see `_process`'s state machine.
extends SceneTree

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const AFFIX_HUD := preload("res://scripts/combat/FloorAffixHud.gd")
const BOSSMOD_HUD := preload("res://scripts/combat/BossModifierHud.gd")
const RANK_SCRIPT := preload("res://scripts/combat/Rank.gd")

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
# A dead property read ABORTS the enclosing function and returns the type's zero,
# which a `failed += _test_x()` idiom reads as "no failures". So failures accumulate
# on the MEMBER `_fails` and every test records a completion sentinel as its last
# line: a test that aborts part-way is missing from `_completed` and fails BY ABSENCE.
const TESTS: Array[String] = [
	"layer_allocation_is_the_declared_one",
	"declared_bands_do_not_overlap",
	"live_rects_sit_inside_their_bands",
	"chain_counter_clears_the_pause_corner",
	"chain_counter_clears_the_boss_bar_ink",
	"boss_bar_keeps_its_shape_on_a_wide_screen",
	"long_strings_are_ellipsised_not_run_off",
	"third_affix_does_not_grow_the_card",
	"body_attached_hud_holds_its_on_screen_size",
	"damage_numbers_draw_under_the_health_bars",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _step: int = 0

## Built in step 1, measured in step 2.
var _built: Dictionary = {}


## ⚠ `SceneTree._process` RETURNING **true** MEANS "QUIT THE TREE". This suite needs
## four frames — set the window, build, let the layout pass run, then measure — so
## every frame but the last returns FALSE. Written the other way round the first
## version of this file exited on frame 0, printed neither a PASS nor a FAIL line,
## and looked for all the world like a suite that had run.
func _process(_delta: float) -> bool:
	match _step:
		0:
			# ⚠ HEADLESS HAS NO ASPECT. Without this the viewport reports 640x640 and
			# every band assertion below is taken against a screen that does not exist.
			root.size = Vector2i(1366, 768)
			_step = 1
			return false
		1:
			_build()
			_step = 2
			return false
		2:
			# One more frame: a Control's rect is not final until the layout pass that
			# follows the frame it was added on.
			_step = 3
			return false
		_:
			_run()
			return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _run() -> void:
	_test_layers()
	_test_bands_disjoint()
	_test_live_rects()
	_test_pause_corner()
	_test_counter_vs_boss_ink()
	_test_boss_bar_shape()
	_test_ellipsis()
	_test_third_affix()
	_test_zoom_rule()
	_test_z_order()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("HUD-layout tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("HUD-layout tests: all PASS")
		quit(0)


# ═══════════════════════════════════════════════════════════════════ building
## Build every piece of the combat HUD the way the game builds it, in a real
## viewport. Each entry in `_built` is the node whose rect IS the band.
func _build() -> void:
	# 1. THE RANK TITLE. `Rank` is an autoload in the game; instantiating the script
	#    runs the same `_build_hud`. Forced visible because the label hides itself
	#    outside a run, and a hidden Control still has to obey the layout.
	var rank: Node = RANK_SCRIPT.new()
	root.add_child(rank)
	var rank_label: Label = _find_label(rank)
	if rank_label != null:
		rank_label.text = "Ascendant · Tier 5"
		rank_label.visible = true
	_built["rank"] = rank_label

	# 2. THE FLOOR BANNER. ⚠ THE ARENA IS NOT ADDED TO THE TREE. `Arena._ready` builds
	#    a room, an Encounter and a run's worth of state; all this test wants is the
	#    banner, so the builder is called on a detached instance and the CanvasLayer it
	#    made is reparented into the viewport. That measures the real widget without
	#    standing up the real scene.
	# ⚠ `load`, NOT `preload`. `Arena.gd` names the `GameState` AUTOLOAD, and a
	# preload is resolved while this suite is being COMPILED — before a `--script`
	# run has registered any autoload — so the whole suite failed to compile with
	# "Identifier not found: GameState" pointing at a file it does not test. The
	# same script loads fine at runtime; the trap is the resolution order, not the
	# dependency. Asserted non-null so a future move cannot make this a silent skip.
	var arena_script: GDScript = load("res://scripts/combat/Arena.gd") as GDScript
	_expect(arena_script != null, "Arena.gd loads (the floor banner is measured off it)")
	if arena_script == null:
		return
	var arena: Node2D = arena_script.new()
	arena.call(&"_build_floor_banner")
	var banner_layer: CanvasLayer = _first_canvas_layer(arena)
	if banner_layer != null:
		arena.remove_child(banner_layer)
		root.add_child(banner_layer)
	arena.free()
	_built["banner_layer"] = banner_layer
	var banner: Label = _find_label(banner_layer)
	if banner != null:
		banner.text = "Floor 3 / 10  ·  The Ashen Stair"
	_built["banner"] = banner

	# 3. THE BOSS BAR. Built the way `Boss._build_bar` builds it — on its own layer,
	#    told the boss's name. A null boss is fine: `_process` guards on it and the
	#    LAYOUT is what is under test.
	var boss_layer := CanvasLayer.new()
	boss_layer.layer = HudStyle.LAYER_BOSS_BAR
	root.add_child(boss_layer)
	var bar: BossBar = BossBar.new()
	boss_layer.add_child(bar)
	bar.setup(null, "THE ASHEN GUARDIAN")
	_built["boss_layer"] = boss_layer
	_built["boss_bar"] = bar

	# 4. THE BOSS MODIFIER ROW, with every modifier the game has turned on at once —
	#    the widest this row can ever be.
	var mods: CanvasLayer = BOSSMOD_HUD.new()
	mods.set(&"modifier_ids", BossModifier.all_ids())
	root.add_child(mods)
	_built["mods_layer"] = mods
	_built["mods"] = _first_control(mods)

	# 5. THE FLOOR AFFIX CARD, with THREE affixes — one more than the band holds,
	#    which is the case that used to spill into the row above.
	var affix_ids: Array[String] = EliteModifier.all_ids()
	var three: Array = [affix_ids[0], affix_ids[1], affix_ids[2]]
	var affix: CanvasLayer = AFFIX_HUD.new()
	affix.set(&"affix_ids", three)
	root.add_child(affix)
	_built["affix_layer"] = affix
	_built["affix"] = _first_control(affix)

	# 6. HYPE — the shout and the chain counter. Two kills so the counter is showing;
	#    the loudest shout the game has so the type is at its maximum.
	var hype: Hype = Hype.new()
	root.add_child(hype)
	hype.call(&"guardian_arrived")
	hype.notify_kill()
	hype.notify_kill()
	var hype_layer: CanvasLayer = _first_canvas_layer(hype)
	_built["hype_layer"] = hype_layer
	_built["shout"] = _find_label(hype_layer)
	_built["chain"] = _find_node_of_type(hype_layer, "VBoxContainer") as Control


# ══════════════════════════════════════════════════════════════════════ 1
func _test_layers() -> void:
	# The indices the files chose, read back off the LIVE CanvasLayers rather than
	# off the constants they were set from.
	var want: Array = [
		["banner_layer", HudStyle.LAYER_BANNER, "floor banner"],
		["boss_layer", HudStyle.LAYER_BOSS_BAR, "boss bar"],
		["mods_layer", HudStyle.LAYER_BOSS_MODS, "boss modifiers"],
		["affix_layer", HudStyle.LAYER_AFFIX, "floor affix card"],
		["hype_layer", HudStyle.LAYER_SHOUT, "hype shout + chain"],
	]
	for w: Array in want:
		var cl: CanvasLayer = _built.get(String(w[0])) as CanvasLayer
		_expect(cl != null, "%s built a CanvasLayer" % w[2])
		if cl != null:
			_expect(cl.layer == int(w[1]),
				"%s is on layer %d, not %d" % [w[2], int(w[1]), cl.layer])
	# ⚠ AND THEY MUST ALL BE DIFFERENT. This is the assertion that would have caught
	# the Hype/boss-bar collision: both were 55 and both were "correct" against their
	# own file's constant.
	var seen: Dictionary = {}
	for w: Array in want:
		var cl: CanvasLayer = _built.get(String(w[0])) as CanvasLayer
		if cl == null:
			continue
		_expect(not seen.has(cl.layer),
			("layer %d is claimed by BOTH `%s` and `%s` — two CanvasLayers on one "
			+ "index resolve by TREE ORDER, i.e. by build order, i.e. by accident")
			% [cl.layer, seen.get(cl.layer, ""), w[2]])
		seen[cl.layer] = String(w[2])
	# The rank title deliberately SHARES the banner layer (52) — one rung, two bands.
	# Asserted so a future move to its own layer is a deliberate edit, not a drift.
	var rank_label: Label = _built.get("rank") as Label
	_expect(rank_label != null, "the rank title built a label")
	if rank_label != null:
		var rank_layer: CanvasLayer = _canvas_layer_of(rank_label)
		_expect(rank_layer != null and rank_layer.layer == HudStyle.LAYER_BANNER,
			"the rank title sits on the banner layer (%d)" % HudStyle.LAYER_BANNER)
	_completes("layer_allocation_is_the_declared_one")


# ══════════════════════════════════════════════════════════════════════ 2
func _test_bands_disjoint() -> void:
	var bands: Array = _bands()
	for i: int in bands.size():
		for j: int in range(i + 1, bands.size()):
			var a: Array = bands[i]
			var b: Array = bands[j]
			_expect(not _spans_overlap(a[1], a[2], b[1], b[2]),
				"bands `%s` (%.0f-%.0f) and `%s` (%.0f-%.0f) overlap"
				% [a[0], a[1], a[2], b[0], b[1], b[2]])
	_completes("declared_bands_do_not_overlap")


# ══════════════════════════════════════════════════════════════════════ 3
## The real assertion: what each widget actually OCCUPIES, measured, against the
## strip it is allowed. Nothing here reads a file's `offset_top`.
func _test_live_rects() -> void:
	var vp: Vector2 = root.get_visible_rect().size
	_expect(is_equal_approx(vp.y, HudStyle.BASE_VIEWPORT.y),
		("the viewport is %.0f tall, not the %.0f base — headless has no aspect and "
		+ "falls back to a SQUARE viewport, which makes every band figure meaningless")
		% [vp.y, HudStyle.BASE_VIEWPORT.y])
	var checks: Array = [
		["rank", HudStyle.BAND_RANK, "rank title"],
		["banner", HudStyle.BAND_FLOOR_BANNER, "floor banner"],
		["boss_bar", HudStyle.BAND_BOSS_BAR, "boss bar"],
		["mods", HudStyle.BAND_BOSS_MODS, "boss modifiers"],
		["affix", HudStyle.BAND_AFFIX, "floor affix card"],
		["shout", HudStyle.BAND_SHOUT, "hype shout"],
	]
	var rects: Dictionary = {}
	for c: Array in checks:
		var ctrl: Control = _built.get(String(c[0])) as Control
		_expect(ctrl != null, "%s exists to be measured" % c[2])
		if ctrl == null:
			continue
		# ⚠ THE UNION OF THE WIDGET **AND EVERY CONTROL INSIDE IT**, not the widget's
		# own rect. A container's rect stays honest while its CONTENT spills: the
		# affix card's wrap reported a tidy 32px while the VBox inside it, with the
		# default 4px separation, drew 36. Measuring only the outer rect is how a
		# layout test passes on a HUD that visibly overlaps.
		var r: Rect2 = _content_rect(ctrl)
		rects[String(c[2])] = r
		var band: Array = c[1]
		_expect(r.position.y >= float(band[0]) - 0.51,
			"%s starts at y%.1f, above its band's %.0f" % [c[2], r.position.y, band[0]])
		_expect(r.end.y <= float(band[1]) + 0.51,
			("%s ends at y%.1f, past its band's %.0f — it grew, and the thing under "
			+ "it is now covered") % [c[2], r.end.y, band[1]])
	# ...and the measured rects must not intersect EACH OTHER either. The bands being
	# disjoint (test 2) plus everything being inside its band (above) implies this,
	# but asserting it directly is what makes the suite honest about the thing it
	# claims to prove: no two pieces of the HUD share a pixel.
	var names: Array = rects.keys()
	for i: int in names.size():
		for j: int in range(i + 1, names.size()):
			var ra: Rect2 = rects[names[i]]
			var rb: Rect2 = rects[names[j]]
			_expect(not ra.intersects(rb),
				"measured rects for `%s` %s and `%s` %s intersect"
				% [names[i], ra, names[j], rb])
	_completes("live_rects_sit_inside_their_bands")


# ══════════════════════════════════════════════════════════════════════ 4
func _test_pause_corner() -> void:
	var chain: Control = _built.get("chain") as Control
	_expect(chain != null, "the chain counter exists")
	if chain == null:
		return
	var r: Rect2 = chain.get_global_rect()
	_expect(not r.intersects(HudStyle.PAUSE_CORNER),
		("the chain counter %s enters the pause button's reserved corner %s — on a "
		+ "phone that is the combo label rendering over the only way to pause")
		% [r, HudStyle.PAUSE_CORNER])
	_expect(r.position.x >= 0.0 and r.end.x <= HudStyle.BASE_VIEWPORT.x + 0.51,
		"the chain counter %s runs off the side of a %.0f-wide screen"
		% [r, HudStyle.BASE_VIEWPORT.x])
	_completes("chain_counter_clears_the_pause_corner")


# ══════════════════════════════════════════════════════════════════════ 5
## The counter is a CORNER widget and the boss bar is a full-width STRIP, so a
## rect-vs-rect test against the bar's Control would fail for anything in a corner.
## The honest comparison is against the bar's INK — the pixels it actually draws.
func _test_counter_vs_boss_ink() -> void:
	var chain: Control = _built.get("chain") as Control
	var bar: BossBar = _built.get("boss_bar") as BossBar
	_expect(chain != null and bar != null, "the counter and the boss bar both exist")
	if chain == null or bar == null:
		return
	var ink: Rect2 = _boss_ink_rect(bar)
	_expect(not chain.get_global_rect().intersects(ink),
		"the chain counter %s overlaps the boss bar's drawn strip %s"
		% [chain.get_global_rect(), ink])
	_completes("chain_counter_clears_the_boss_bar_ink")


# ══════════════════════════════════════════════════════════════════════ 6
## ⚠ `aspect="expand"` MEANS THE CONTROL IS HANDED MORE THAN 640 PIXELS ON A PHONE.
## The bar's width was the only viewport-relative dimension in the widget, so a 20:9
## screen (size.x ~800) grew it to ~496px while its height, its y and its label
## stayed put — the bar changed SHAPE per device. Capping at the base width makes it
## one shape everywhere.
func _test_boss_bar_shape() -> void:
	var bar: BossBar = _built.get("boss_bar") as BossBar
	_expect(bar != null, "the boss bar exists")
	if bar == null:
		return
	var at_base: float = bar.bar_pixel_width(HudStyle.BASE_VIEWPORT.x)
	var at_wide: float = bar.bar_pixel_width(800.0)
	var at_narrow: float = bar.bar_pixel_width(480.0)
	_expect(is_equal_approx(at_base, at_wide),
		("the bar is %.1f px on a 640 screen and %.1f px on an 800 one — its aspect "
		+ "changes per device") % [at_base, at_wide])
	_expect(at_narrow < at_base,
		"a narrower screen than the base still shrinks the bar to fit (%.1f)" % at_narrow)
	_completes("boss_bar_keeps_its_shape_on_a_wide_screen")


# ══════════════════════════════════════════════════════════════════════ 7
## Nothing in the HUD may let a string leave its box. Three of these took arbitrary
## text with no length contract at all: a boss name from a subclass, a theme name
## from a `.tres`, and a floor affix's 49-character blurb.
func _test_ellipsis() -> void:
	var long_name: String = "THE ARCHIVIST OF THE SEVENTEENTH UNFINISHED MARGIN, SECOND DRAFT"
	var bar: BossBar = _built.get("boss_bar") as BossBar
	if bar != null:
		var lbl: Label = _find_label(bar)
		_expect(lbl != null, "the boss bar has a name label")
		if lbl != null:
			lbl.text = long_name
			_expect(lbl.clip_text and lbl.text_overrun_behavior
					== TextServer.OVERRUN_TRIM_ELLIPSIS,
				"a boss name is clipped + ellipsised rather than run off the screen")
			_expect(lbl.get_global_rect().end.x <= HudStyle.BASE_VIEWPORT.x + 0.51,
				"the boss name label %s stays on screen" % lbl.get_global_rect())
	for key: String in ["banner", "shout", "rank"]:
		var l: Label = _built.get(key) as Label
		_expect(l != null, "`%s` is a label" % key)
		if l != null:
			_expect(l.clip_text, "`%s` clips rather than overflowing" % key)
			_expect(l.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
				"`%s` ellipsises rather than cutting a glyph in half" % key)
	_completes("long_strings_are_ellipsised_not_run_off")


# ══════════════════════════════════════════════════════════════════════ 8
## The card was built with THREE affixes in `_build`. Two rows is what the band
## holds; the third used to grow the centred VBox symmetrically and push its bottom
## edge into the modifier row above it.
func _test_third_affix() -> void:
	var affix: Control = _built.get("affix") as Control
	_expect(affix != null, "the affix card exists")
	if affix == null:
		return
	var rows: int = 0
	var saw_more: bool = false
	for l: Label in _all_labels(affix):
		rows += 1
		if l.text.contains("MORE"):
			saw_more = true
	_expect(rows <= AFFIX_HUD.MAX_ROWS,
		"the affix card drew %d rows into a band that holds %d" % [rows, AFFIX_HUD.MAX_ROWS])
	_expect(saw_more,
		("a third affix is COUNTED (`+N MORE`) rather than silently dropped — a rule "
		+ "the player cannot see and is not told about is indistinguishable from a bug"))
	_expect(affix.get_global_rect().end.y <= HudStyle.BAND_AFFIX[1] + 0.51,
		"the three-affix card %s stays inside its band" % affix.get_global_rect())
	_completes("third_affix_does_not_grow_the_card")


# ══════════════════════════════════════════════════════════════════════ 9
## THE ONE ZOOM RULE, asserted as arithmetic on the real helper. A body-attached
## widget's ON-SCREEN size is world * zoom * ui_scale; the rule says that product is
## the same at both ends of the camera's range. Before the pass an enemy's health bar
## was 1.8 screen px at 0.46 and a crit number was 101 px at 2.6.
func _test_zoom_rule() -> void:
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	var probe := Node2D.new()
	root.add_child(probe)
	var world_px: float = 4.0        # an enemy HP bar's height
	var seen: Array[float] = []
	for z: float in [HudStyle.ZOOM_WIDE, 1.0, HudStyle.ZOOM_REF, HudStyle.ZOOM_TIGHT]:
		cam.zoom = Vector2(z, z)
		seen.append(world_px * z * HudStyle.ui_scale(probe))
	var lo: float = seen[0]
	var hi: float = seen[0]
	for v: float in seen:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_expect(absf(hi - lo) < 0.01,
		("a body-attached widget drawn at %.0f world px measures %.2f..%.2f screen px "
		+ "across the camera's range — it should be constant") % [world_px, lo, hi])
	# ...and it must be the size it was TUNED at, which is the reference zoom's. A
	# rule that holds the size constant at the WRONG size is a different bug.
	_expect(absf(lo - world_px * HudStyle.ZOOM_REF) < 0.01,
		("the held size is %.2f px, not the %.2f it has at the reference zoom — every "
		+ "widget in the HUD was tuned by eye at DEFAULT_ZOOM")
		% [lo, world_px * HudStyle.ZOOM_REF])
	# No camera at all (every headless suite) must draw as authored, so that a suite
	# measuring world geometry is not silently rescaled by this. Asked of a node that
	# is not in a tree, which is the state a `--script` harness's nodes are usually in.
	cam.queue_free()
	var orphan := Node2D.new()
	_expect(is_equal_approx(HudStyle.ui_scale(orphan), 1.0),
		"a node outside the tree scales by 1.0 (headless suites must be unaffected)")
	orphan.free()
	probe.queue_free()
	_completes("body_attached_hud_holds_its_on_screen_size")


# ═════════════════════════════════════════════════════════════════════ 10
## The world-space half of the same problem: `DamageNumber` sat at z_index 60 and
## `CharacterBars` at 30, so a number could cover the bar the hit it described had
## just moved.
func _test_z_order() -> void:
	_expect(HudStyle.Z_CHARACTER_BARS > HudStyle.Z_DAMAGE_NUMBER,
		"health bars (z %d) draw above damage numbers (z %d)"
		% [HudStyle.Z_CHARACTER_BARS, HudStyle.Z_DAMAGE_NUMBER])
	# Measured off a live node rather than off the constant, so a file that stops
	# reading `HudStyle` fails here.
	var bars := CharacterBars.new()
	root.add_child(bars)
	var body := Node2D.new()
	root.add_child(body)
	bars.configure(body)
	_expect(bars.z_index == HudStyle.Z_CHARACTER_BARS,
		"a configured CharacterBars takes z %d, not %d"
		% [HudStyle.Z_CHARACTER_BARS, bars.z_index])
	bars.queue_free()
	body.queue_free()
	_completes("damage_numbers_draw_under_the_health_bars")


# ══════════════════════════════════════════════════════════════════════ helpers
func _bands() -> Array:
	return [
		["rank", HudStyle.BAND_RANK[0], HudStyle.BAND_RANK[1]],
		["floor banner", HudStyle.BAND_FLOOR_BANNER[0], HudStyle.BAND_FLOOR_BANNER[1]],
		["boss bar", HudStyle.BAND_BOSS_BAR[0], HudStyle.BAND_BOSS_BAR[1]],
		["boss mods", HudStyle.BAND_BOSS_MODS[0], HudStyle.BAND_BOSS_MODS[1]],
		["floor affix", HudStyle.BAND_AFFIX[0], HudStyle.BAND_AFFIX[1]],
		["hype shout", HudStyle.BAND_SHOUT[0], HudStyle.BAND_SHOUT[1]],
	]


func _spans_overlap(a0: float, a1: float, b0: float, b1: float) -> bool:
	return a0 < b1 and b0 < a1


## The pixels the boss bar actually paints, in screen space — not its full-width
## Control rect. Built from the same three numbers `_draw` uses.
func _boss_ink_rect(bar: BossBar) -> Rect2:
	var full_w: float = bar.size.x
	var w: float = bar.bar_pixel_width(full_w)
	var x0: float = bar.global_position.x + (full_w - w) * 0.5
	var y0: float = bar.global_position.y + BossBar.BAR_TOP
	return Rect2(x0 - BossBar.FRAME, y0 - BossBar.FRAME,
		w + BossBar.FRAME * 2.0, bar.bar_height() + BossBar.FRAME * 2.0)


## A widget's true extent: its own rect unioned with every descendant Control's.
func _content_rect(root_ctrl: Control) -> Rect2:
	var r: Rect2 = root_ctrl.get_global_rect()
	for c: Control in _all_controls(root_ctrl):
		r = r.merge(c.get_global_rect())
	return r


func _all_controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c: Node in n.get_children():
		if c is Control:
			out.append(c as Control)
		out.append_array(_all_controls(c))
	return out


func _first_canvas_layer(n: Node) -> CanvasLayer:
	for c: Node in n.get_children():
		if c is CanvasLayer:
			return c as CanvasLayer
	return null


func _canvas_layer_of(n: Node) -> CanvasLayer:
	var p: Node = n
	while p != null:
		if p is CanvasLayer:
			return p as CanvasLayer
		p = p.get_parent()
	return null


func _first_control(n: Node) -> Control:
	for c: Node in n.get_children():
		if c is Control:
			return c as Control
	return null


func _find_label(n: Node) -> Label:
	if n == null:
		return null
	for c: Node in n.get_children():
		if c is Label:
			return c as Label
		var deep: Label = _find_label(c)
		if deep != null:
			return deep
	return null


func _all_labels(n: Node) -> Array[Label]:
	var out: Array[Label] = []
	if n == null:
		return out
	for c: Node in n.get_children():
		if c is Label:
			out.append(c as Label)
		out.append_array(_all_labels(c))
	return out


func _find_node_of_type(n: Node, cls: String) -> Node:
	if n == null:
		return null
	for c: Node in n.get_children():
		if c.is_class(cls):
			return c
		var deep: Node = _find_node_of_type(c, cls)
		if deep != null:
			return deep
	return null
