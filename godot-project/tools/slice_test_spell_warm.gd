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
extends SceneTree

var _failed: int = 0
var _done: Dictionary = {}

const EXPECTED: PackedStringArray = [
	"warm_loads_every_dispatch_path",
	"warm_is_idempotent",
	"warm_covers_the_dispatcher_constants",
	"warm_covers_the_nested_loads",
]


func _initialize() -> void:
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


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		print("FAIL: %s" % what)


func _completes(name: String) -> void:
	_done[name] = true


## After `warm()`, nothing in the list is still uncached — which is the whole point:
## a path left cold is a freeze still waiting to happen.
func _test_warm_loads_every_dispatch_path() -> void:
	SpellCaster.reset_warm()
	SpellCaster.warm()
	var cold: PackedStringArray = PackedStringArray()
	for p: String in SpellCaster.WARM_PATHS:
		if not ResourceLoader.has_cached(p):
			cold.append(p.get_file())
	_expect(cold.is_empty(),
		"every warm path is cached after warm() (still cold: %s)" % ", ".join(cold))
	_completes("warm_loads_every_dispatch_path")


## Cheap to call twice — it is going to be called from a floor build, and floors
## build repeatedly during a climb.
func _test_warm_is_idempotent() -> void:
	SpellCaster.reset_warm()
	SpellCaster.warm()
	_expect(SpellCaster.warm() == 0,
		"a second warm() loads nothing (got %d)" % SpellCaster.warm())
	_completes("warm_is_idempotent")


## THE ANTI-ROT ASSERTION. Every script path constant on the dispatcher must be in
## the warm list. Adding a spectacle arm without adding its path is the exact
## regression this suite exists to catch, and it is invisible at runtime.
func _test_warm_covers_the_dispatcher_constants() -> void:
	var declared: PackedStringArray = PackedStringArray()
	for p: String in [
		SpellCaster.BEAM_PATH, SpellCaster.RAY_PATH, SpellCaster.METEOR_PATH,
		SpellCaster.CONVERGENCE_PATH, SpellCaster.RUSH_PATH, SpellCaster.NOVA_PATH,
		SpellCaster.BOULDER_PATH, SpellCaster.PILLAR_PATH, SpellCaster.WALL_PATH,
		SpellCaster.ICE_WALL_PATH, SpellCaster.CHAIN_PATH, SpellCaster.ZONE_PATH,
		SpellCaster.MISSILES_PATH, SpellCaster.TETHER_PATH, SpellCaster.FLURRY_PATH,
		SpellCaster.BLINK_PATH, SpellCaster.SHADOW_ROOT_PATH, SpellCaster.CRAWLER_PATH,
		SpellCaster.DAGGER_PATH, SpellCaster.WARD_PATH, SpellCaster.ARC_PATH,
	]:
		if not SpellCaster.WARM_PATHS.has(p):
			declared.append(p.get_file())
	_expect(declared.is_empty(),
		"every dispatch-arm script is warmed (missing: %s)" % ", ".join(declared))

	# The two drop-economy fork TABLES, which are data rather than constants and so
	# are the easiest of the lot to extend without touching the warm list.
	var forks: PackedStringArray = PackedStringArray()
	for d: Dictionary in [SpellCaster.HEX_SCRIPTS, SpellCaster.CATACLYSM_SCRIPTS]:
		for k: String in d.keys():
			if not SpellCaster.WARM_PATHS.has(String(d[k])):
				forks.append(String(d[k]).get_file())
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
		MeteorSigil.SPIKE_LINE_PATH,
		ReactionOutcomes.HOLLOW_PURPLE_PATH,
		ReactionOutcomes.STEAM_CLOUD_PATH,
	]:
		if not SpellCaster.WARM_PATHS.has(p):
			nested.append(p.get_file())
	_expect(nested.is_empty(),
		"every nested spectacle load is warmed (missing: %s)" % ", ".join(nested))
	_completes("warm_covers_the_nested_loads")
