# Run: godot --headless --path godot-project --script tools/slice_test_spell_warm.gd
#
# Pins `SpellCaster.warm()`.
#
# WHY THIS IS WORTH A SUITE. `SpellCaster` reaches its spectacles with `load()` by
# PATH rather than `preload`, deliberately, so headless tools can call `cast()`
# without early-compiling the autoload-referencing scenes. The cost of that is that
# the FIRST cast of each spell type parses and compiles its script on the spot:
# measured at 44-126 ms per script and 1411 ms across the roster
# (`tools/probe_cast_warmup.gd`), i.e. a single-frame freeze the first time the
# player throws each spell — roughly 130-630 ms on the target phone.
#
# `warm()` moves that cost into a loading beat. The thing most likely to rot is the
# PATH LIST: a new spectacle added to a dispatch arm, or a new nested `load()`
# inside a spectacle, is silently absent from the warm-up and quietly reintroduces
# exactly the freeze this exists to remove. Nothing errors. So the load-bearing
# assertion here is the CROSS-CHECK against the dispatcher's own constants.
#
# ⚠ TEST IDIOM. Never `failed += _test_x()`: a dead property read ABORTS the
# enclosing function and returns the type's zero, which that idiom reads as "no
# failures" — it silently disabled 64 suites once. Failures accumulate on a MEMBER
# and every test records a COMPLETION SENTINEL, so a test that aborts fails BY
# ABSENCE. `tools/slice_test_loadout.gd` is the reference.
#
# ⚠ AND THIS SUITE ITSELF WOULD NOT COMPILE, WHICH IS THE JOKE. It named
# `SpellCaster`, `MeteorSigil` and `ReactionOutcomes` as compile-time globals and ran
# them from `_initialize()`. Both halves are wrong for the same reason: `MeteorSigil`
# says `Sfx.play(...)`, autoload globals do not exist until the main loop is up, and
# naming a class forces it to compile NOW. So the chain died with
#
#   Compile Error: Identifier not found: Sfx        (MeteorSigil.gd:336)
#   Compile Error: Failed to compile depended scripts.
#   Failed to load script "res://tools/slice_test_spell_warm.gd"
#
# — the suite could not be loaded at all — and `run_all_tests.py` still scored it
# PASS, because it only ever read the summary line. A suite that never ran was
# reporting on the warm list for as long as that was true.
#
# So: BY PATH, and on the first `_process` frame, by which point the autoloads are
# registered. This is the same rule a dozen sibling suites already document.
extends SceneTree

const SPELLCASTER_PATH: String = "res://scripts/combat/SpellCaster.gd"
const METEOR_SIGIL_PATH: String = "res://scripts/combat/MeteorSigil.gd"
const REACTION_OUTCOMES_PATH: String = "res://scripts/combat/ReactionOutcomes.gd"

var _failed: int = 0
var _done: Dictionary = {}
var _ran: bool = false
var _sc_script: GDScript = null
var _sc_consts: Dictionary = {}

const EXPECTED: PackedStringArray = [
	"warm_loads_every_dispatch_path",
	"warm_is_idempotent",
	"warm_covers_the_dispatcher_constants",
	"warm_covers_the_nested_loads",
]


## `SpellCaster` loaded at runtime. See the header for why never by `class_name`.
func _sc() -> GDScript:
	if _sc_script == null:
		_sc_script = load(SPELLCASTER_PATH) as GDScript
		if _sc_script != null:
			_sc_consts = _sc_script.get_script_constant_map()
	return _sc_script


## One named constant off a path-loaded script.
func _const_of(path: String, name: String, fallback: Variant) -> Variant:
	var s: GDScript = load(path) as GDScript
	if s == null:
		return fallback
	return s.get_script_constant_map().get(name, fallback)


## The warm list, whatever container type it is declared as.
func _warm_paths() -> Variant:
	_sc()
	return _sc_consts.get("WARM_PATHS", PackedStringArray())


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	if _sc() == null:
		print("FAIL: could not load SpellCaster.gd")
		print("Spell warm tests: 1 FAILED")
		quit(1)
		return true
	_test_warm_loads_every_dispatch_path()
	_test_warm_is_idempotent()
	_test_warm_covers_the_dispatcher_constants()
	_test_warm_covers_the_nested_loads()

	for name: String in EXPECTED:
		if not _done.has(name):
			_failed += 1
			print("FAIL: %s never completed (aborted mid-test)" % name)
	if _failed == 0:
		print("Spell warm tests: all PASS")
	else:
		print("Spell warm tests: %d FAILED" % _failed)
	quit(1 if _failed > 0 else 0)
	return true


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		print("FAIL: %s" % what)


func _completes(name: String) -> void:
	_done[name] = true


## After `warm()`, nothing in the list is still uncached — which is the whole point:
## a path left cold is a freeze still waiting to happen.
func _test_warm_loads_every_dispatch_path() -> void:
	_sc().call("reset_warm")
	_sc().call("warm")
	var cold: PackedStringArray = PackedStringArray()
	for p: String in _warm_paths():
		if not ResourceLoader.has_cached(p):
			cold.append(p.get_file())
	_expect(cold.is_empty(),
		"every warm path is cached after warm() (still cold: %s)" % ", ".join(cold))
	_completes("warm_loads_every_dispatch_path")


## Cheap to call twice — it is going to be called from a floor build, and floors
## build repeatedly during a climb.
func _test_warm_is_idempotent() -> void:
	_sc().call("reset_warm")
	_sc().call("warm")
	_expect(int(_sc().call("warm")) == 0,
		"a second warm() loads nothing (got %d)" % int(_sc().call("warm")))
	_completes("warm_is_idempotent")


## THE ANTI-ROT ASSERTION. Every script path constant on the dispatcher must be in
## the warm list. Adding a spectacle arm without adding its path is the exact
## regression this suite exists to catch, and it is invisible at runtime.
func _test_warm_covers_the_dispatcher_constants() -> void:
	# ⚠ EVERY `*_PATH` CONSTANT ON THE DISPATCHER, READ OFF THE SCRIPT RATHER THAN
	# LISTED HERE. The old hand-written list could not see a NEW arm — the exact rot
	# this test exists to catch was invisible to the test itself. Reading the constant
	# map means an arm added tomorrow is checked without touching this file.
	_sc()
	var arm_names: Array = []
	for key: String in _sc_consts.keys():
		# ⚠ `.tscn` TOO, NOT JUST `.gd`. `NOVA_PATH` is a packed SCENE while the other
		# twenty are scripts, and a `.gd`-only filter silently dropped it — which is
		# the same shape of bug as the hand-written list it replaces, just automated.
		var v: String = str(_sc_consts[key])
		if key.ends_with("_PATH") and (v.ends_with(".gd") or v.ends_with(".tscn")):
			arm_names.append(key)
	arm_names.sort()
	_expect(arm_names.size() >= 21,
		"the dispatcher still declares its spectacle arms as *_PATH constants "
			+ "(found %d, expected at least the 21 that existed)" % arm_names.size())
	var declared: PackedStringArray = PackedStringArray()
	for key: String in arm_names:
		var p: String = str(_sc_consts[key])
		if not _warm_paths().has(p):
			declared.append(p.get_file())
	_expect(declared.is_empty(),
		"every dispatch-arm script is warmed (missing: %s)" % ", ".join(declared))

	# The two drop-economy fork TABLES, which are data rather than constants and so
	# are the easiest of the lot to extend without touching the warm list.
	var forks: PackedStringArray = PackedStringArray()
	for d: Dictionary in [
		_sc_consts.get("HEX_SCRIPTS", {}) as Dictionary,
		_sc_consts.get("CATACLYSM_SCRIPTS", {}) as Dictionary,
	]:
		for k: String in d.keys():
			if not _warm_paths().has(str(d[k])):
				forks.append(str(d[k]).get_file())
	_expect(forks.is_empty(),
		"every HEX/CATACLYSM fork script is warmed (missing: %s)" % ", ".join(forks))
	_completes("warm_covers_the_dispatcher_constants")


## The nested loads — a spectacle that loads ANOTHER spectacle by path. These do not
## appear in any dispatch arm, so nothing about the dispatcher hints they exist.
## `frozen_comet` is why this assertion is here: it measured a 61 ms first cast while
## its own arm's script (MeteorSigil) was already cached, because MeteorSigil forks
## to IceSpikeLine from inside `rain()`.
func _test_warm_covers_the_nested_loads() -> void:
	var nested: PackedStringArray = PackedStringArray()
	for p: String in [
		str(_const_of(METEOR_SIGIL_PATH, "SPIKE_LINE_PATH", "")),
		str(_const_of(REACTION_OUTCOMES_PATH, "HOLLOW_PURPLE_PATH", "")),
		str(_const_of(REACTION_OUTCOMES_PATH, "STEAM_CLOUD_PATH", "")),
	]:
		# An empty string means the constant MOVED, which is the rot this guards —
		# silently skipping it would be the vacuous pass all over again.
		_expect(p != "", "the nested-load constants are still where this test reads them")
		if p != "" and not _warm_paths().has(p):
			nested.append(p.get_file())
	_expect(nested.is_empty(),
		"every nested spectacle load is warmed (missing: %s)" % ", ".join(nested))
	_completes("warm_covers_the_nested_loads")
