# Run: godot --headless --path godot-project --script tools/slice_test_stage_layers.gd
#
# THE STAGE MUST NOT DRAW ON THE FIGHTERS' LAYER. This suite exists because three
# stage drawers — BreakablePlatform, DestructibleTerrain, StageHazard — set no
# z_index at all, defaulted to 0, and drew among the heroes. The maker played it and
# reported that he could not see the game.
#
# A comment could not have caught that: `ArenaTerrain` and `RuinPlatform` BOTH
# carried a comment explaining the scheme, and three later files simply never read
# them. So the scheme is data (`StageLayers.DRAWERS`) and this file is the thing that
# fails the build when a drawer is missing from it. Two rules:
#
#   1. EVERY registered drawer parks itself where the table says, in `_ready`.
#   2. EVERY StaticBody2D under `scripts/combat/` that owns a `_draw` is REGISTERED.
#      Rule 1 alone is vacuous — it only checks the drawers somebody remembered to
#      list, which is precisely the set that was never the problem. Rule 2 is what
#      makes a FOURTH unregistered drawer a red build instead of a silent regression.
#
# ⚠ AND RULE 2 MUST NOT BE TRIVIALLY TRUE OF AN EMPTY RESULT. A directory scan that
# finds nothing passes a "everything found is registered" check perfectly. So the
# scan asserts a MINIMUM number of hits as well, and the count is checked against the
# registry — if the scanner silently stops matching (a rename, a `.gd` moved, a regex
# that stops meaning what it meant), the suite goes red rather than quiet.
#
# ⚠ NEVER `failed += _test_x()`. A dead property read aborts the enclosing function
# and hands back the return type's zero, which reads as "no failures" — that idiom
# silently disabled 64 suites once. Failures accumulate on the MEMBER `_fails`, and
# every test's last line records a COMPLETION SENTINEL, so a test that aborts
# half-way fails the suite by absence. See tools/slice_test_loadout.gd.
extends SceneTree

const COMBAT_DIR: String = "res://scripts/combat"

## Loaded BY PATH, never by `class_name`: several of these scripts reference the
## Sfx / Juice / CombatVfx autoloads, and naming the class here would compile that
## whole chain at THIS script's parse time, before the main loop registers anything.
const SCRIPT_FMT: String = "res://scripts/combat/%s.gd"

## The lowest number of StaticBody2D-with-a-_draw files the scanner may find before
## we stop believing it. Seven are registered today; a scan that comes back with two
## has broken, not improved.
const MIN_SCANNED_DRAWERS: int = 4

const TESTS: Array[String] = [
	"table_is_ordered", "nothing_sits_on_the_fighter_layer",
	"registered_drawers_park_correctly", "every_solid_drawer_is_registered",
	"cap_height_survives_thin_and_thick",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_table_is_ordered()
	_test_nothing_sits_on_the_fighter_layer()
	_test_registered_drawers_park_correctly()
	_test_every_solid_drawer_is_registered()
	_test_cap_height()
	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("stage_layers: TEST DID NOT COMPLETE — %s (it aborted part-way)" % name)
	if _fails == 0:
		print("stage layers tests: all PASS")
	else:
		printerr("stage layers tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("stage_layers: FAIL — %s" % what)


# --------------------------------------------------------------------------- 1
## The ladder has to actually be a ladder: sky furthest back, fighters in front of
## every scenery rung. A table whose numbers crossed would order the stage wrongly
## while every individual drawer still "matched its entry".
func _test_table_is_ordered() -> void:
	var ladder: Array[int] = [
		StageLayers.SKY, StageLayers.SKYLINE, StageLayers.MOTES,
		StageLayers.MOUNTAIN, StageLayers.BACKDROP, StageLayers.TERRAIN,
		StageLayers.HAZARD, StageLayers.PLATFORM, StageLayers.COVER,
		StageLayers.DEBRIS, StageLayers.FIGHTER,
	]
	for i: int in range(1, ladder.size()):
		_expect(ladder[i] > ladder[i - 1],
			"z ladder is out of order at index %d (%d must be > %d)"
				% [i, ladder[i], ladder[i - 1]])
	_expect(StageLayers.FIGHTER == 0, "fighters must own z 0")
	_completed["table_is_ordered"] = true


## THE INVARIANT THE MAKER'S BUG VIOLATED, stated directly.
func _test_nothing_sits_on_the_fighter_layer() -> void:
	_expect(not StageLayers.DRAWERS.is_empty(), "the drawer registry is empty")
	for name: String in StageLayers.DRAWERS.keys():
		var z: int = int(StageLayers.DRAWERS[name])
		_expect(z < StageLayers.FIGHTER,
			"%s is registered at z %d — scenery may never sit at or above the "
			% [name, z] + "fighter layer (0)")
	_completed["nothing_sits_on_the_fighter_layer"] = true


# --------------------------------------------------------------------------- 2
## Instantiate the REAL classes (no stubs — a stub would only prove the stub parks
## itself) and check where each one actually lands after `_ready`.
func _test_registered_drawers_park_correctly() -> void:
	var checked: int = 0
	for name: String in StageLayers.DRAWERS.keys():
		var path: String = SCRIPT_FMT % name
		var gs: GDScript = load(path) as GDScript
		if gs == null:
			_expect(false, "could not load %s — is it registered under a stale name?" % path)
			continue
		var node: Node = gs.new() as Node
		if node == null:
			_expect(false, "%s did not instantiate as a Node" % name)
			continue
		root.add_child(node)  # _ready is where a drawer parks itself
		var ci: CanvasItem = node as CanvasItem
		if not _declares_draw(gs):
			# A CONTAINER, not a drawer: `DestructibleFloor` is a Node2D that holds
			# StaticBody2D slabs, and the slabs are what paint and what park. Parking
			# the container as well would be actively wrong — its children set a
			# RELATIVE z, so a non-zero parent would push them a rung too far back.
			# It stays in the registry so a reader can find where its slabs live.
			checked += 1
		elif ci == null:
			_expect(false, "%s is registered as a stage drawer but is not a CanvasItem" % name)
		else:
			var want: int = int(StageLayers.DRAWERS[name])
			_expect(ci.z_index == want,
				"%s sits at z %d, table says %d" % [name, ci.z_index, want])
			checked += 1
		node.queue_free()
	_expect(checked == StageLayers.DRAWERS.size(),
		"only %d of %d registered drawers were actually checked"
			% [checked, StageLayers.DRAWERS.size()])
	_completed["registered_drawers_park_correctly"] = true


# --------------------------------------------------------------------------- 3
## THE RULE THAT CLOSES THE HOLE. Walk `scripts/combat/`, find every script that is
## solid stage geometry (a StaticBody2D that draws itself), and require it to be in
## the registry. This is what makes a FOURTH drawer defaulting to 0 impossible to
## ship quietly — nobody has to remember the rule, the build remembers it.
func _test_every_solid_drawer_is_registered() -> void:
	var found: Array[String] = _scan_solid_drawers()
	_expect(found.size() >= MIN_SCANNED_DRAWERS,
		"the scanner found only %d StaticBody2D drawers under %s — expected at least "
		% [found.size(), COMBAT_DIR]
		+ "%d. The scan has broken; it is not that the files vanished."
			% MIN_SCANNED_DRAWERS)
	for name: String in found:
		_expect(StageLayers.DRAWERS.has(name) or StageLayers.NOT_STAGE_GEOMETRY.has(name),
			"%s draws itself and blocks movement but is in neither " % name
			+ "StageLayers.DRAWERS nor NOT_STAGE_GEOMETRY — it will default to z 0 and "
			+ "draw on top of the fighters. Add it to the table.")
	_completed["every_solid_drawer_is_registered"] = true


## Does the OUTER class of this script paint anything itself? False for a container
## whose drawing is done by inner classes. Reflection, not a text scan, so it cannot
## be fooled by an inner class's `_draw`.
func _declares_draw(gs: GDScript) -> bool:
	for m: Dictionary in gs.get_script_method_list():
		if String(m.get("name", "")) == "_draw":
			return true
	return false


## Script basenames under `scripts/combat/` whose text contains BOTH `extends
## StaticBody2D` and a `_draw` — i.e. solid stage geometry that paints itself.
## Inner classes count (DestructibleFloor's slab is one), which is why this reads
## the file text rather than reflecting on the outer class.
func _scan_solid_drawers() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(COMBAT_DIR)
	if dir == null:
		_expect(false, "could not open %s to scan for stage drawers" % COMBAT_DIR)
		return out
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string("%s/%s" % [COMBAT_DIR, file_name])
		if text.is_empty():
			continue
		if text.contains("extends StaticBody2D") and text.contains("func _draw("):
			out.append(file_name.get_basename())
	return out


# --------------------------------------------------------------------------- 4
## The lit cap is the stage's "you can land here" signal, so it has to survive both
## framings: a 22 px tower ledge (where a fixed cap disappears) and a 64 px cover
## block (where a fixed cap would eat the face).
func _test_cap_height() -> void:
	_expect(StageLayers.cap_height(22.0) >= StageLayers.CAP_MIN,
		"a thin ledge's cap fell below CAP_MIN")
	_expect(StageLayers.cap_height(64.0) > StageLayers.cap_height(22.0),
		"cap height must grow with the body it caps")
	_expect(StageLayers.cap_height(64.0) < 64.0 * 0.5,
		"the cap must never be half the body — that is a solid, not a lit edge")
	# The legend depends on the cap being WARM and the fighters being blue: a cap
	# that drifted cool would put the stage back in the hero's own hue.
	_expect(StageLayers.CAP_LIT.r > StageLayers.CAP_LIT.b + 0.1,
		"CAP_LIT is no longer warm — it must not compete with the blue fighters")
	_expect(StageLayers.BREAK_AMBER.r > StageLayers.BREAK_AMBER.b + 0.3,
		"BREAK_AMBER is no longer amber")
	_completed["cap_height_survives_thin_and_thick"] = true
