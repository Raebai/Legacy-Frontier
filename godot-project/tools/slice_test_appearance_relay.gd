# THE COLOUR YOU PICKED, ON THE STICKMAN YOU SPAWN AS — the relay that was missing.
#
#   godot --headless --path godot-project --script tools/slice_test_appearance_relay.gd
#
# ══ WHAT WAS BUILT, AND WHY NONE OF IT REACHED THE GAME ═══════════════════════════
#
# Every half of this feature existed and was correct on its own:
#
#   * `Outfitter.chosen_colourway` — the whole-figure pick. WRITTEN by the pause menu's
#     appearance row (`PauseMenu._cycle_appearance`) and RESTORED at boot by
#     `Settings.apply_all` off `user://settings.cfg`. A real, persisted preference.
#   * `GameState.colourway` — READ at spawn by `Hero._ready`, which feeds it to
#     `GameState.colourway_parts()` as the middle link of the per-part fallback chain
#     (the part's own index -> `colourway` -> the caller's fallback).
#
# The two never met. `GameState.colourway` **had no writer anywhere in the tree** — it
# was declared -1 and it was still -1 at every spawn that has ever happened. So the
# middle link of the chain was dead, every unpainted part fell through to the hardcoded
# fallback, and a player who set their colour and quit came back the default colour.
#
# ⚠ IT DID NOT LOOK BROKEN, WHICH IS WHY IT LASTED. `PauseMenu._sync_colourway` REPLAYS
# the pick onto the live hero the first time you open the menu — so the colour was right
# the moment you went looking for it, and wrong on every floor until you did. The bug was
# invisible from inside the only screen that could show it.
#
# ══ WHAT THIS SUITE PINS ═════════════════════════════════════════════════════════
# The relay, and the CONSEQUENCE of the relay — separately, because a relay that carries
# a value nothing acts on is the same dead feature one link further along.
#
# ⚠ THE PRECONDITION IS ASSERTED, NOT ASSUMED, AND NEVER `or`-ED AGAINST THE CLAIM.
# `colourway` is -1 before each write and a DIFFERENT index after it; a suite that only
# checked the value afterwards would pass against a leftover from the previous test, and
# `x == 3 or relay_ran` would pass on a tree where the relay had been deleted.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion sentinel, so
# a test aborted by a dead property read fails BY ABSENCE rather than reporting "no
# failures". NEVER write `failed += _test_x()` in this file.
extends SceneTree

## ⚠ LOADED BY PATH, NOT NAMED. `Outfitter` IS a `class_name`, and this project has
## watched `global_script_class_cache.cfg` go stale after a new script four sessions
## running (CLAUDE.md, Sessions 6/8/9) — a path load never consults it. `GameState` is an
## AUTOLOAD reached at `/root/GameState`: naming it in source makes the compiler resolve
## it at compile time, where under a `--script` main loop it does not exist yet.
const OUTFITTER_PATH: String = "res://scripts/ui/Outfitter.gd"

## The palette size the relay is exercised against. `Hero.COLOURWAYS` has five entries;
## this suite passes the size in explicitly (exactly as `Hero` does) rather than reaching
## the combat dependency chain for a number it only needs to be >= 4.
const PALETTE: int = 5

## Deliberately NOT 0 and NOT equal to `FALLBACK` below. If the relay is dead,
## `colourway_parts` resolves every part to `FALLBACK`; the two indices have to differ or
## a dead relay and a live one give the same array.
const PICK: int = 3
const FALLBACK: int = 0

const TESTS: Array[String] = [
	"the_pick_reaches_gamestate",
	"a_boot_restore_reaches_gamestate",
	"an_unpainted_part_follows_the_pick",
	"a_painted_part_still_overrides_the_pick",
]

var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	_test_the_pick_reaches_gamestate()
	_test_a_boot_restore_reaches_gamestate()
	_test_an_unpainted_part_follows_the_pick()
	_test_a_painted_part_still_overrides_the_pick()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Appearance relay tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Appearance relay tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## The live autoload — the node the relay actually targets. Reached by path for the
## reason in the header.
func _gs() -> Node:
	return root.get_node_or_null(^"/root/GameState")


func _outfitter_script() -> GDScript:
	return load(OUTFITTER_PATH) as GDScript


## Put both halves back to "nobody has chosen anything", so each test writes the fixture
## it asserts against. `chosen_colourway` is a static that outlives a scene change on
## purpose (see its header), which inside a suite means it outlives the PREVIOUS TEST.
##
## ⚠ THE RESET GOES THROUGH THE SETTER TOO, so it is undone here on `GameState` by hand
## rather than trusted to stay clean.
func _reset(gs: Node) -> void:
	_outfitter_script().set(&"chosen_parts", [-1, -1, -1])
	gs.set(&"part_colourways", {"head": -1, "body": -1, "legs": -1})
	gs.set(&"colourway", -1)


# ══════════════════════════════════════════════════════════════════════ the relay
## THE MISSING WRITER. Assigning the pick has to land on `GameState`, because that field
## is what `Hero._ready` reads and there is no other path from the settings file to a
## spawning hero.
##
## The assignment is made through `Script.set()` rather than `Outfitter.chosen_colourway =`
## so it goes through the same property path an external writer uses — which is the whole
## mechanism under test. `PauseMenu` and `Settings` both assign it exactly this way.
func _test_the_pick_reaches_gamestate() -> void:
	var gs: Node = _gs()
	_expect(gs != null, "the GameState autoload is registered under a --script run")
	if gs == null:
		return
	_reset(gs)
	# PRECONDITION, STANDING ALONE. Never `or`-ed against the claim below: on a tree where
	# the relay had been deleted, `-1 or written` would still be green.
	_expect(int(gs.get(&"colourway")) == -1,
		"precondition: GameState.colourway is -1 before the pick is made")

	_outfitter_script().set(&"chosen_colourway", PICK)

	_expect(int(gs.get(&"colourway")) == PICK,
		("the whole-figure pick reaches GameState.colourway (got %d, wanted %d) — this is "
		+ "the writer the field never had") % [int(gs.get(&"colourway")), PICK])
	_completes("the_pick_reaches_gamestate")


## THE BOOT PATH, WHICH IS THE ONE THAT MATTERS MOST. `Settings.apply_all` restores the
## saved pick with a plain assignment at startup, before any scene loads. If the relay is
## a hand-written call somewhere instead of a property, that restore silently misses it
## and the preference is only honoured for players who touch the pause menu every run.
func _test_a_boot_restore_reaches_gamestate() -> void:
	var gs: Node = _gs()
	if gs == null:
		return
	_reset(gs)
	_expect(int(gs.get(&"colourway")) == -1,
		"precondition: GameState.colourway is -1 before the boot restore")

	# The exact shape of `Settings.apply_all`: a clamped int assigned to the static.
	var restored: int = clampi(PICK, 0, PALETTE - 1)
	_outfitter_script().set(&"chosen_colourway", restored)

	_expect(int(gs.get(&"colourway")) == restored,
		"a boot restore of the saved colourway reaches GameState without Settings.gd changing")
	_completes("a_boot_restore_reaches_gamestate")


# ═══════════════════════════════════════════════════════ the relay's consequence
## THE POINT OF THE RELAY. `colourway_parts` is what `Hero._ready` calls, and `colourway`
## is the middle link of its fallback chain — so a part nobody painted has to come back
## wearing the figure colour, not the caller's fallback.
##
## `FALLBACK` is passed deliberately DIFFERENT from `PICK`: with a dead relay every part
## resolves to `FALLBACK`, and an assertion that could not tell those apart would pass on
## the broken tree.
func _test_an_unpainted_part_follows_the_pick() -> void:
	var gs: Node = _gs()
	if gs == null:
		return
	_reset(gs)
	_outfitter_script().set(&"chosen_colourway", PICK)
	if not gs.has_method("colourway_parts"):
		_expect(false, "GameState still exposes colourway_parts (Hero._ready calls it)")
		return
	var parts: Array = gs.call("colourway_parts", PALETTE, FALLBACK)
	_expect(parts.size() == 3, "colourway_parts still answers with three indices")
	if parts.size() != 3:
		return
	_expect(int(parts[0]) == PICK and int(parts[1]) == PICK and int(parts[2]) == PICK,
		("all three unpainted parts spawn in the picked colourway (got %s, wanted [%d, %d, %d]) "
		+ "— a %s here is the dead middle link falling through to the caller's fallback")
		% [str(parts), PICK, PICK, PICK, str(FALLBACK)])
	_completes("an_unpainted_part_follows_the_pick")


## THE OTHER HALF OF THE CHAIN, AND THE REGRESSION THIS WIRING COULD CAUSE. A part the
## player painted in the armoury outranks the whole-figure pick — it always did, and
## giving the middle link a writer must not promote it over the part's own index.
func _test_a_painted_part_still_overrides_the_pick() -> void:
	var gs: Node = _gs()
	if gs == null:
		return
	_reset(gs)
	_outfitter_script().set(&"chosen_colourway", PICK)
	if not gs.has_method("set_colourway_part") or not gs.has_method("colourway_parts"):
		_expect(false, "GameState still exposes set_colourway_part + colourway_parts")
		return
	var painted: int = 1                      # != PICK and != FALLBACK
	gs.call("set_colourway_part", "head", painted)
	var parts: Array = gs.call("colourway_parts", PALETTE, FALLBACK)
	if parts.size() != 3:
		_expect(false, "colourway_parts still answers with three indices")
		return
	_expect(int(parts[0]) == painted,
		"a painted head keeps its own colour, not the figure pick (got %d)" % int(parts[0]))
	_expect(int(parts[1]) == PICK and int(parts[2]) == PICK,
		"the parts nobody painted still follow the figure pick (got %s)" % str(parts))
	_completes("a_painted_part_still_overrides_the_pick")
