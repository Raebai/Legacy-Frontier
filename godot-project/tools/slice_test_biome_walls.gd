# Run: godot --headless --path godot-project --script tools/slice_test_biome_walls.gd
#
# ALL TEN BIOME WALLS WERE DEAD CODE AND EVERY TEST IN THE REPO WAS GREEN OVER IT.
#
# `FloorDecor._draw_motif` is a ten-arm `match` on the biome's NAME — Ashfall's
# broken gantry, Verdant's canopy and hanging roots, Frostmarch's icicles, the
# Crimson Room's banners, the Vault's niches, Emberworks' furnace mouths,
# Glasswood's leaning panes, the Drowned Gallery's waterline, Stormreach's masts,
# the Apex's stars. Every one of them authored, shipped, and never once on screen.
#
# `Arena._apply_decor` passed `String(theme.resource_path).get_file().get_basename()`.
# `resource_path` is set by the LOADER, and no `EnvTheme` is ever loaded — every one
# is built in code and there is not a single theme `.tres` on disk. So the key was
# `""` on every floor of every run, no arm could match, and all ten fell through to
# the generic `_motif_arcade`. The climb looked like one room re-tinted ten times
# because that is exactly what it was.
#
# Nothing caught it because nothing could: both files were individually correct.
# The fault lived in the STRING that had to agree between them, and a string that
# has to agree between two files with no test on the agreement is a string that will
# stop agreeing. That is the class of bug this suite exists for, not just the one
# instance — rule 1 fails if either side renames a biome.
#
# ⚠ RULE 1 MUST NOT BE TRIVIALLY TRUE OF AN EMPTY SCAN. "Every name I found has an
# arm" passes perfectly when the scan finds no names. So the biome count is asserted
# against a floor as well.
#
# ⚠ NEVER `failed += _test_x()`. A dead property read aborts the enclosing function
# and hands back the return type's zero, which reads as "no failures". Failures
# accumulate on the MEMBER `_fails`, and every test's last line records a COMPLETION
# SENTINEL, so a test that aborts half-way fails the suite by absence.
extends SceneTree

## Loaded BY PATH, never by `class_name`. `GameState` is an autoload; naming it here
## would resolve that autoload at THIS script's parse time, before the main loop has
## registered anything, and take the whole dependency chain down with it.
const GAMESTATE_PATH: String = "res://scripts/GameState.gd"
const FLOORGEN_PATH: String = "res://scripts/tower/FloorGen.gd"
const ENVTHEME_PATH: String = "res://scripts/tower/EnvTheme.gd"
const FLOORDECOR_SRC: String = "res://scripts/tower/FloorDecor.gd"
const ARENA_SRC: String = "res://scripts/combat/Arena.gd"

## Ten biomes are authored. A table that comes back with three has broken, not
## shrunk — the scan is not to be believed below this.
const MIN_BIOMES: int = 10

const TESTS: Array[String] = [
	"every_biome_has_a_wall",
	"arena_passes_the_name_not_the_path",
	"code_built_themes_have_no_resource_path",
	"floors_get_distinct_biomes",
	"jitter_preserves_accent_and_light",
	"every_weather_kind_has_complete_params",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_every_biome_has_a_wall()
	_test_arena_passes_the_name_not_the_path()
	_test_code_built_themes_have_no_resource_path()
	_test_floors_get_distinct_biomes()
	_test_jitter_preserves_accent_and_light()
	_test_every_weather_kind_has_complete_params()
	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("biome_walls: TEST DID NOT COMPLETE — %s (it aborted part-way)" % name)
	if _fails == 0:
		print("biome wall tests: all PASS")
	else:
		printerr("biome wall tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("biome_walls: FAIL — %s" % what)


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func _biome_names() -> Array[String]:
	var gs: GDScript = load(GAMESTATE_PATH) as GDScript
	if gs == null:
		return []
	var rows: Array = gs.get_script_constant_map().get("BIOMES", []) as Array
	var out: Array[String] = []
	for row: Variant in rows:
		var d: Dictionary = row as Dictionary
		if d != null and d.has("n"):
			out.append(String(d["n"]))
	return out


# --------------------------------------------------------------------------- 1
## THE AGREEMENT. Every name in the BIOMES table must appear as a match arm in
## FloorDecor, or that biome silently wears the generic wall.
func _test_every_biome_has_a_wall() -> void:
	var names: Array[String] = _biome_names()
	_expect(names.size() >= MIN_BIOMES,
		"the BIOMES table returned %d rows — expected at least %d; the scan has "
		% [names.size(), MIN_BIOMES] + "broken rather than the table having shrunk")
	var decor: String = _read(FLOORDECOR_SRC)
	_expect(not decor.is_empty(), "could not read %s" % FLOORDECOR_SRC)
	for n: String in names:
		# The arm is a quoted literal in the `match`. A rename on either side
		# breaks this, which is the entire point.
		_expect(decor.contains('"%s"' % n),
			"biome '%s' has no motif arm in FloorDecor._draw_motif — it will fall " % n
			+ "through to the generic arcade wall and nobody will be told")
	_completed["every_biome_has_a_wall"] = true


# --------------------------------------------------------------------------- 2
## THE REGRESSION GUARD for the bug itself. `_apply_decor` must key off the theme's
## name. Reverting to `resource_path` must turn this suite red immediately.
func _test_arena_passes_the_name_not_the_path() -> void:
	var src: String = _read(ARENA_SRC)
	_expect(not src.is_empty(), "could not read %s" % ARENA_SRC)
	var at: int = src.find("func _apply_decor(")
	_expect(at >= 0, "Arena._apply_decor has been renamed or removed — this guard "
		+ "is now pointing at nothing and must be re-aimed")
	if at < 0:
		_completed["arena_passes_the_name_not_the_path"] = true
		return
	# Just the function body: the file-level comment above it NAMES `resource_path`
	# while explaining the bug, so scanning the whole file would always trip.
	var body_end: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (body_end - at) if body_end > at else -1)
	_expect(body.contains("theme.name"),
		"Arena._apply_decor no longer passes `theme.name` — that is the ONLY key "
		+ "FloorDecor._draw_motif matches on")
	_expect(not body.contains("resource_path"),
		"Arena._apply_decor reads `resource_path` again. It is empty on every "
		+ "EnvTheme because none is ever loaded, so this silently disables all ten "
		+ "biome walls. See the comment above that function.")
	_completed["arena_passes_the_name_not_the_path"] = true


# --------------------------------------------------------------------------- 3
## THE NEGATIVE CONTROL — it proves WHY the old key could never have worked, rather
## than merely asserting the new one does. If a future change starts loading themes
## from `.tres`, `resource_path` becomes non-empty and this test goes red, which is
## the correct moment to revisit the decision rather than a nuisance failure.
func _test_code_built_themes_have_no_resource_path() -> void:
	var gs: GDScript = load(GAMESTATE_PATH) as GDScript
	_expect(gs != null, "could not load %s" % GAMESTATE_PATH)
	if gs == null:
		_completed["code_built_themes_have_no_resource_path"] = true
		return
	for floor_no: int in range(1, MIN_BIOMES + 1):
		var theme: Resource = gs.floor_env(floor_no) as Resource
		_expect(theme != null, "floor_env(%d) returned null" % floor_no)
		if theme == null:
			continue
		_expect(String(theme.resource_path).is_empty(),
			"floor %d's theme has a resource_path (%s) — themes are now LOADED, so "
			% [floor_no, theme.resource_path]
			+ "the biome-key decision in Arena._apply_decor should be revisited")
		_expect(not String(theme.name).is_empty(),
			"floor %d's theme has an empty name — the biome key is blank and its "
			% floor_no + "wall will fall through to the generic arcade")
	_completed["code_built_themes_have_no_resource_path"] = true


# --------------------------------------------------------------------------- 4
## Ten floors must actually be ten places. A `biome_for` that collapsed to one row
## would leave every assertion above true and the climb still monotonous.
func _test_floors_get_distinct_biomes() -> void:
	var gs: GDScript = load(GAMESTATE_PATH) as GDScript
	if gs == null:
		_completed["floors_get_distinct_biomes"] = true
		return
	var seen: Dictionary = {}
	for floor_no: int in range(1, MIN_BIOMES + 1):
		var theme: Resource = gs.floor_env(floor_no) as Resource
		if theme != null:
			seen[String(theme.name)] = true
	_expect(seen.size() >= MIN_BIOMES,
		"floors 1-%d produced only %d distinct biomes — the climb repeats itself"
			% [MIN_BIOMES, seen.size()])
	_completed["floors_get_distinct_biomes"] = true


# --------------------------------------------------------------------------- 5
## The generator jitters the HUE. It must not quietly reset the other two fields.
## `light` is the "dim lights as you climb" dial and defaulting it to 1.0 flattened
## the exposure of every generated floor — the deeper you went, the less changed.
func _test_jitter_preserves_accent_and_light() -> void:
	var fg: GDScript = load(FLOORGEN_PATH) as GDScript
	var env: GDScript = load(ENVTHEME_PATH) as GDScript
	_expect(fg != null and env != null, "could not load FloorGen / EnvTheme")
	if fg == null or env == null:
		_completed["jitter_preserves_accent_and_light"] = true
		return
	var src: Resource = env.new() as Resource
	src.name = "Frostmarch"
	src.wash_tint = Color(0.30, 0.36, 0.44)
	src.accent_tint = Color(0.85, 0.95, 1.00, 1.0)
	src.light = 0.68
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var out: Resource = fg._jitter_theme(rng, src) as Resource
	_expect(out != null, "_jitter_theme returned null")
	if out == null:
		_completed["jitter_preserves_accent_and_light"] = true
		return
	_expect(String(out.name) == "Frostmarch",
		"the jitter lost the biome name — the wall goes generic")
	_expect(is_equal_approx(float(out.light), 0.68),
		"the jitter reset `light` to %f — the floor's exposure, and with it the "
		% float(out.light) + "shape of the climb, is gone")
	_expect(out.accent_tint.a > 0.0,
		"the jitter dropped `accent_tint` back to transparent — the biome's "
		+ "authored highlight falls back to a lightened wash")
	# And the thing it IS meant to do still happens.
	_expect(not out.wash_tint.is_equal_approx(src.wash_tint),
		"the jitter no longer varies the wash at all")
	_completed["jitter_preserves_accent_and_light"] = true


# --------------------------------------------------------------------------- 6
## THE AIR. Two failure modes, both silent until a player reaches that one floor:
##
##   1. A biome with no `wx` key falls back to Weather.NONE and that floor's air is
##      simply still, which looks like a floor nobody finished rather than a bug.
##   2. A `_weather_params` row missing a key crashes `build_weather` — but ONLY on
##      the floor that uses that kind. A typo in the RAIN row is invisible until
##      floor 9, which in a tower climber is a long way to walk to find a crash.
##
## So every kind the table can produce is built here, and every key the builder reads
## is required to be present.
func _test_every_weather_kind_has_complete_params() -> void:
	var gs: GDScript = load(GAMESTATE_PATH) as GDScript
	var atmo_script: GDScript = load("res://scripts/combat/Atmosphere.gd") as GDScript
	_expect(gs != null and atmo_script != null, "could not load GameState / Atmosphere")
	if gs == null or atmo_script == null:
		_completed["every_weather_kind_has_complete_params"] = true
		return
	# Every key `build_weather` reads out of the row. A missing one is a crash.
	var required: Array[String] = [
		"dir_x", "dir_y", "spread", "grav", "vel_min", "vel_max",
		"scale_min", "scale_max", "amount", "life", "alpha", "shape", "spin", "color",
	]
	var atmo: Node = atmo_script.new()
	var kinds_seen: Dictionary = {}
	for floor_no: int in range(1, MIN_BIOMES + 1):
		var theme: Resource = gs.floor_env(floor_no) as Resource
		if theme == null:
			continue
		var kind: int = int(theme.weather)
		_expect(kind > 0,
			"floor %d (%s) has no weather — its air is still while every other "
				% [floor_no, String(theme.name)]
			+ "floor moves, which reads as unfinished rather than as calm")
		kinds_seen[kind] = true
		var row: Dictionary = atmo.call("_weather_params", kind, Color.WHITE)
		_expect(not row.is_empty(),
			"weather kind %d (floor %d, %s) has no params row — build_weather would "
				% [kind, floor_no, String(theme.name)] + "silently build nothing")
		for key: String in required:
			_expect(row.has(key),
				"weather kind %d is missing the '%s' key — build_weather reads it and "
					% [kind, key] + "would crash on that floor and only that floor")
	atmo.free()
	# The variety claim: ten floors should not all breathe the same way.
	_expect(kinds_seen.size() >= 5,
		"only %d distinct weather kinds across %d floors — the air is repeating"
			% [kinds_seen.size(), MIN_BIOMES])
	_completed["every_weather_kind_has_complete_params"] = true
