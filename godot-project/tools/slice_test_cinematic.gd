# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_cinematic.gd
#
# CINEMATIC MODE — the gate that makes a bot-fight frame postable.
#
# The first clip anybody tried to post had the clip director's tuning readout
# (`heat 0.73 [ROLLING]`) burned into the bottom-left of every frame and the touch
# PAUSE button burned into the top-right. This suite pins the fix in BOTH directions,
# and the second direction is the one that matters:
#
#   1. WHAT IS HIDDEN IS HIDDEN. The heat readout and the pause-button layer are off
#      the screen while the mode is on.
#   2. WHAT IS KEPT IS STILL THERE. ⚠ AN ABSENCE-ONLY TEST PASSES TRIVIALLY ON A BLANK
#      SCREEN. "no debug label was visible" is satisfied perfectly by a HUD that failed
#      to build at all, or by a future change that hides the whole CanvasLayer and calls
#      it clean. So every hide assertion is paired with a MINIMUM-OCCURRENCE assertion
#      on the chrome the maker explicitly asked to keep: both fighter plates, with the
#      class name AND the HP number in them, and the centre clock line.
#   3. IT RESTORES WHAT IT HID, AND ONLY WHAT IT HID. Several marked nodes are already
#      conditionally invisible for their own reasons (`PerfOverlay` starts hidden, the
#      duel's intent line follows a toggle that is off by default). A naive
#      `visible = not enabled` would SHOW all of them on the way out, i.e. leaving the
#      mode would litter the screen with overlays nobody asked for.
#   4. THE DEFAULT IS OFF. ~69 capture tools render frames of this game and several of
#      them (`touch_capture`, `DirectorCapture`) exist to photograph EXACTLY the things
#      this mode hides. A default of ON would silently blank them.
#   5. THE CLIP TOOL TURNS IT ON. `python-tools/make_clip.py` passes no such flag and
#      must not have to — the capture tool owns it. Asserted against the tool's source,
#      because running it needs the GUI binary and a real renderer.
#
# ⚠ THE `failed += _test_x()` IDIOM IS BANNED IN THIS FILE. Reading a member that has
# moved is not a test failure in GDScript — it ABORTS the enclosing function and hands
# the caller the return type's zero, which that idiom reads as "no failures". It
# silently disabled 64 suites once; the write-up is in `tools/slice_test_loadout.gd`.
# So, exactly as that file does it:
#   1. failures accumulate on the MEMBER `_fails`, never on a return value;
#   2. every test's last line records a COMPLETION SENTINEL, so a test that aborts
#      half-way fails the suite BY ABSENCE, whatever the cause;
#   3. `quit(1)` and `quit(0)` are mutually exclusive branches — never both.
extends SceneTree

const CINEMATIC_SCRIPT: String = "res://scripts/combat/Cinematic.gd"
const MATCH_SCENE: String = "res://scenes/combat/BotMatch.tscn"
const MATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"
const CLIP_TOOL: String = "res://tools/directed_clip_capture.gd"

## Every test that must run to completion. A name missing from `_completed` at the end
## means that test aborted part-way and the suite fails.
const TESTS: Array[String] = [
	"default_is_off",
	"mark_hides_and_restores",
	"mark_does_not_resurrect_something_already_hidden",
	"mark_ignores_a_non_visual_node",
	"live_match_hides_the_heat_readout",
	"live_match_keeps_the_hud_that_makes_the_clip_readable",
	"live_match_hides_the_pause_button",
	"live_match_restores_on_the_way_out",
	"toggling_after_the_scene_is_built_still_works",
	"clip_tool_turns_it_on_before_building_the_scene",
]

## BotMatch members this suite reaches DYNAMICALLY. `BotMatch` is loaded BY PATH and
## never as an identifier — naming it here would compile its whole autoload-touching
## dependency chain at this script's parse time. Listed once so a relocation is NAMED
## rather than merely detected by a missing sentinel.
const MATCH_MEMBERS: Array[String] = ["_readout", "_plates", "_clock_label", "_arena"]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _cine: GDScript = null
var _match_script: GDScript = null
var _live: Node = null


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run_all()
	return false


func _run_all() -> void:
	_cine = load(CINEMATIC_SCRIPT) as GDScript
	_expect(_cine != null, "Cinematic.gd loads")
	if _cine == null:
		_report()
		return
	_test_default_is_off()
	_test_mark_hides_and_restores()
	_test_mark_does_not_resurrect()
	_test_mark_ignores_non_visual()
	await _test_live_match()
	_test_clip_tool_turns_it_on()
	# Belt and braces: whatever the tests above did, the flag is a STATIC and this
	# process may go on to do other things. Leave it the way the game ships.
	Cinematic.enabled = false
	_report()


func _report() -> void:
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Cinematic tests: %d FAILED" % _fails)
		quit(1)
		return
	print("Cinematic tests: all PASS")
	quit(0)


# ==========================================================================
# THE FLAG AND THE SWEEP, with no scene at all
# ==========================================================================

## ⚠ THE MOST IMPORTANT ASSERTION IN THE FILE. `python-tools/run_capture.py` drives ~69
## tools that render frames of this game, and several exist to photograph precisely
## what this mode hides — `touch_capture` is "force-show the mobile TouchControls to
## review the pad layout", `DirectorCapture` photographs the director panel. A default
## of ON would blank them while every one of them still reported success.
func _test_default_is_off() -> void:
	var fresh: Variant = _cine.get("enabled")
	_expect(fresh is bool, "Cinematic.enabled exists and is a bool")
	_expect(fresh == false,
		"cinematic mode is OFF by default — every existing capture tool depends on it")
	_expect(bool(_cine.call("shows_chrome")),
		"...and `shows_chrome()` agrees with the flag")
	_completes("default_is_off")


func _test_mark_hides_and_restores() -> void:
	Cinematic.enabled = false
	var n := Label.new()
	n.visible = true
	root.add_child(n)
	Cinematic.mark(n)
	_expect(n.visible, "marking with the mode OFF changes nothing")
	Cinematic.set_enabled(self, true)
	_expect(not n.visible, "turning the mode ON hides a marked node")
	Cinematic.set_enabled(self, false)
	_expect(n.visible, "turning it OFF puts it back")
	# Idempotence: two ONs in a row must not stash `false` as the "original" state and
	# then restore a permanently hidden node.
	Cinematic.set_enabled(self, true)
	Cinematic.set_enabled(self, true)
	Cinematic.set_enabled(self, false)
	_expect(n.visible, "ON twice then OFF still restores VISIBLE, not the hidden state")
	n.free()
	_completes("mark_hides_and_restores")


## Leaving cinematic mode must not turn ON an overlay the maker had switched OFF.
## `PerfOverlay` boots hidden; `VersusArena._intent_label` follows `duel_show_intent`,
## which defaults false. A `visible = not enabled` sweep would show both.
func _test_mark_does_not_resurrect() -> void:
	Cinematic.enabled = false
	var n := Label.new()
	n.visible = false
	root.add_child(n)
	Cinematic.mark(n)
	Cinematic.set_enabled(self, true)
	_expect(not n.visible, "an already-hidden marked node stays hidden")
	Cinematic.set_enabled(self, false)
	_expect(not n.visible,
		"...and leaving cinematic mode does NOT resurrect it (the naive-sweep bug)")
	n.free()
	_completes("mark_does_not_resurrect_something_already_hidden")


## `mark` is typed `Node` so it can take a `CanvasLayer` (which is not a `CanvasItem`
## but does carry `visible`). That width means it can also be handed something with no
## `visible` at all, and `set()` on an undeclared property is a SILENT no-op — so the
## guard has to be an explicit type test, not a hopeful assignment.
func _test_mark_ignores_non_visual() -> void:
	Cinematic.enabled = false
	var plain := Node.new()
	root.add_child(plain)
	Cinematic.mark(plain)
	_expect(not plain.is_in_group(Cinematic.HIDE_GROUP),
		"a node with no `visible` is refused rather than silently no-op'd")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	Cinematic.mark(layer)
	_expect(layer.is_in_group(Cinematic.HIDE_GROUP),
		"a CanvasLayer IS accepted — the pause button and the perf overlay are both one")
	Cinematic.set_enabled(self, true)
	_expect(not layer.visible, "...and it really hides")
	Cinematic.set_enabled(self, false)
	plain.free()
	layer.free()
	_completes("mark_ignores_a_non_visual_node")


# ==========================================================================
# THE LIVE MATCH — the thing that is actually filmed
#
# Source-reading cannot settle this. The readout is built in `_build_overlay`, the
# pause button in `PauseMenu._build_pause_button` two files away, and the question is
# what a RENDERED FRAME contains. A real `BotMatch` on a real stage is the only honest
# way to ask.
# ==========================================================================

func _test_live_match() -> void:
	var scene: PackedScene = load(MATCH_SCENE) as PackedScene
	_match_script = load(MATCH_SCRIPT) as GDScript
	if scene == null or _match_script == null:
		_expect(false, "the BotMatch scene + script load")
		return
	# ⚠ ON BEFORE THE SCENE IS BUILT — the same ordering `directed_clip_capture.gd`
	# uses. `Cinematic.mark()` applies the current mode the instant a node registers,
	# so chrome built under an already-on flag is born hidden. If that ordering ever
	# breaks, the readout is visible on frame one of every clip.
	Cinematic.enabled = true
	_match_script.set("auto_rematch", false)
	_live = scene.instantiate()
	root.add_child(_live)
	# Two frames: one for `_ready` to build the arena and the overlay, one for
	# `_process` to have painted the plates at least once.
	await process_frame
	await process_frame
	if not _require_match_members():
		_cleanup_live()
		return
	_test_readout_hidden()
	_test_kept_hud_present()
	_test_pause_button_hidden()
	_test_restores_on_the_way_out()
	await _test_toggle_after_build()
	_cleanup_live()


func _cleanup_live() -> void:
	if is_instance_valid(_live):
		_live.free()   # immediate, so `_exit_tree` unpauses before the suite reports
	_live = null
	paused = false
	Cinematic.enabled = false


## Name the casualty. The completion sentinels say "something died"; this says which
## member moved house, so the next relocation is a one-line diagnosis and not a hunt.
func _require_match_members() -> bool:
	if not is_instance_valid(_live):
		_expect(false, "the match instantiated")
		return false
	var ok: bool = true
	for m: String in MATCH_MEMBERS:
		if _live.get(m) == null:
			_expect(false, "BotMatch still has `%s` (it moved — every assertion "
				% m + "below it would abort silently)")
			ok = false
	return ok


func _test_readout_hidden() -> void:
	var readout: Variant = _live.get("_readout")
	_expect(readout is Label, "the match built its heat readout (member `_readout`)")
	if not (readout is Label):
		return
	_expect(not (readout as Label).visible,
		"the `heat 0.73 [ROLLING]` readout is OFF the frame in cinematic mode")
	_expect((readout as Label).is_in_group(Cinematic.HIDE_GROUP),
		"...because it registered itself, not because somebody hunted it down")
	_completes("live_match_hides_the_heat_readout")


## ⚠ THE PAIRED ASSERTION. Everything above is an ABSENCE, and an absence is satisfied
## perfectly by a HUD that never built or by a future change that blanks the whole
## CanvasLayer and calls the result clean. This is the floor under that: the chrome the
## maker explicitly asked to KEEP is present, visible, and carries real text.
func _test_kept_hud_present() -> void:
	var plates: Variant = _live.get("_plates")
	if not (plates is Array) or (plates as Array).size() != 2:
		_expect(false, "the match built two fighter plates (got %s)" % str(plates))
		return
	var visible_names: int = 0
	for side: int in 2:
		var row: Variant = (plates as Array)[side]
		if not (row is Dictionary):
			_expect(false, "plate %d is a row" % side)
			return
		var name_label: Variant = (row as Dictionary).get("name")
		var draw: Variant = (row as Dictionary).get("draw")
		_expect(name_label is Label, "plate %d has its name label" % side)
		_expect(draw is Control, "plate %d has its bar" % side)
		if not (name_label is Label) or not (draw is Control):
			return
		_expect((name_label as Label).visible,
			"plate %d's name is STILL VISIBLE — cinematic mode must not blank the HUD" % side)
		_expect((draw as Control).visible, "plate %d's health bar is still visible" % side)
		# "STORMCALLER   211" — the class name AND the HP number, which is exactly what
		# the maker said gives the clip its context.
		var txt: String = (name_label as Label).text
		_expect(txt.strip_edges() != "", "plate %d's name has text" % side)
		_expect(txt.contains(" "), "plate %d reads `CLASS  HP`, not a bare word (%s)"
			% [side, txt])
		var digits: bool = false
		for c: String in txt:
			if c >= "0" and c <= "9":
				digits = true
		_expect(digits, "plate %d still carries an HP NUMBER (%s)" % [side, txt])
		if (name_label as Label).visible:
			visible_names += 1
	# A minimum occurrence rate, stated as such: two, not "at least zero".
	_expect(visible_names == 2,
		"BOTH fighter plates survive cinematic mode (%d of 2)" % visible_names)
	var clock: Variant = _live.get("_clock_label")
	_expect(clock is Label, "the centre clock line exists")
	if clock is Label:
		_expect((clock as Label).visible, "...and the `Impossible 0:34` line is kept")
		_expect((clock as Label).text.strip_edges() != "", "...with text in it")
	_completes("live_match_keeps_the_hud_that_makes_the_clip_readable")


## The touch PAUSE affordance, two files away in `PauseMenu`, on its own CanvasLayer.
func _test_pause_button_hidden() -> void:
	var menu: Object = _find_pause_menu()
	_expect(menu != null, "the showcase stage built a PauseMenu (it owns the button)")
	if menu == null:
		return
	var layer: Variant = menu.get("_pause_layer")
	_expect(layer is CanvasLayer, "the pause button lives on its own CanvasLayer")
	if not (layer is CanvasLayer):
		return
	_expect(not (layer as CanvasLayer).visible,
		"the top-right pause button is OFF the frame in cinematic mode")
	# ...and the host cannot put it back by accident. `close()` and
	# `set_pause_button_visible()` both re-assert visibility on their own schedule; a
	# group sweep alone would be undone by either of them a frame later.
	menu.call("set_pause_button_visible", true)
	_expect(not (layer as CanvasLayer).visible,
		"...and `set_pause_button_visible(true)` cannot override cinematic mode")
	menu.call("close")
	_expect(not (layer as CanvasLayer).visible,
		"...nor can closing the menu, which re-shows the button in normal play")
	_completes("live_match_hides_the_pause_button")


## Leaving the mode restores the readout — otherwise a maker who took one screenshot
## from the Director would have a permanently blind clip engine until they relaunched.
func _test_restores_on_the_way_out() -> void:
	Cinematic.set_enabled(self, false)
	var readout: Variant = _live.get("_readout")
	if not (readout is Label):
		_expect(false, "the readout is still reachable")
		return
	_expect((readout as Label).visible,
		"leaving cinematic mode brings the heat readout back (it is GATED, not deleted)")
	var menu: Object = _find_pause_menu()
	if menu != null:
		var layer: Variant = menu.get("_pause_layer")
		if layer is CanvasLayer:
			menu.call("close")
			_expect((layer as CanvasLayer).visible,
				"...and the pause button comes back with it")
	_completes("live_match_restores_on_the_way_out")


## The Director route: the flag is flipped on a scene that is ALREADY STANDING, so the
## group sweep — not the born-hidden path — has to do the work.
func _test_toggle_after_build() -> void:
	Cinematic.set_enabled(self, false)
	await process_frame
	var readout: Variant = _live.get("_readout")
	if not (readout is Label):
		_expect(false, "the readout is still reachable")
		return
	_expect((readout as Label).visible, "precondition: the readout is showing")
	Cinematic.set_enabled(self, true)
	var swept: int = Cinematic.refresh(self)
	_expect(swept >= 2,
		"the sweep reached at least the readout and the pause layer (touched %d)" % swept)
	_expect(not (readout as Label).visible,
		"flipping the flag on a live scene hides the readout (the F1 route)")
	var menu: Object = _find_pause_menu()
	if menu != null:
		var layer: Variant = menu.get("_pause_layer")
		if layer is CanvasLayer:
			_expect(not (layer as CanvasLayer).visible,
				"...and the pause button with it")
	_completes("toggling_after_the_scene_is_built_still_works")


## The PauseMenu is built by `VersusArena`, which `BotMatch` holds as `_arena`. Reached
## through the arena's own public `pause_menu()` accessor rather than by walking the
## tree, so this test breaks loudly if that seam moves instead of quietly finding
## nothing.
func _find_pause_menu() -> Object:
	if not is_instance_valid(_live):
		return null
	var arena: Variant = _live.get("_arena")
	if arena == null or not (arena is Object):
		return null
	if not (arena as Object).has_method("pause_menu"):
		return null
	return (arena as Object).call("pause_menu") as Object


# ==========================================================================
# THE CLIP TOOL
# ==========================================================================

## `python-tools/make_clip.py` passes no cinematic argument and must never have to —
## the maker's one-line clip command cannot depend on remembering a flag. So the
## capture tool owns the decision, and it has to make it BEFORE the scene is built.
##
## Asserted against the tool's SOURCE because running it needs the GUI binary and a
## real renderer; under `--headless` the dummy renderer writes blank PNGs while
## reporting success, which is the exact failure this project keeps re-learning.
func _test_clip_tool_turns_it_on() -> void:
	var f: FileAccess = FileAccess.open(CLIP_TOOL, FileAccess.READ)
	_expect(f != null, "the clip tool is readable")
	if f == null:
		return
	var src: String = f.get_as_text()
	f.close()
	_expect(src.contains(CINEMATIC_SCRIPT),
		"the clip tool reaches Cinematic.gd BY PATH (never by `class_name` — that is a "
		+ "parse-time autoload trap under --script)")
	_expect(src.contains("_set_cinematic"), "...through a named step, not inline")
	var set_at: int = src.find("_set_cinematic()")
	var build_at: int = src.find("(load(MATCH_SCENE) as PackedScene).instantiate()")
	_expect(set_at >= 0 and build_at >= 0,
		"both the cinematic step and the scene build are present")
	if set_at < 0 or build_at < 0:
		return
	_expect(set_at < build_at,
		"⚠ the flag is set BEFORE the scene instantiates — chrome built under an "
		+ "already-on flag is born hidden; the other order flashes it on frame one")
	_expect(src.contains("var _cinematic: bool = true"),
		"...and it defaults to ON, so make_clip.py needs no new argument")
	_completes("clip_tool_turns_it_on_before_building_the_scene")


# ------------------------------------------------------------------- plumbing
## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort.
func _expect(cond: bool, msg: String) -> void:
	if cond:
		return
	_fails += 1
	printerr("  FAIL: %s" % msg)


func _completes(name: String) -> void:
	_completed[name] = true
