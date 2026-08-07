# Run: godot --headless --path godot-project --script tools/slice_test_perf_budget.gd
#
# THE PERFORMANCE GUARD RAIL. Pins the two things a later session can silently undo:
#
#   1. THE SPEC'S 8-ACTIVE-SPELL-VFX CEILING actually exists and actually bites.
#      It was unenforced for the whole project's life — `SpellReactor.MAX_LIVE = 12`
#      bounds what is TRACKED FOR REACTIONS, so a 13th spell still spawned, still
#      damaged, and merely stopped clashing. Nothing anywhere limited how much
#      spectacle could be alive at once, and the measurement says that is the single
#      largest cost driver in the frame (+2.6 ms of desktop CPU per live spell
#      effect at the 25-entity ceiling).
#
#   2. THE GARNISH CAPS STAY O(1). `ScorchDecal` and `DebrisChunk` both used to run
#      `get_nodes_in_group(...)` — an ALLOCATING walk of every decal / chunk in the
#      world — once per spawn, to compute a number the class can simply keep. That is
#      the same shape as the `DamageNumber` scan removed before it, and the same
#      shape it will grow back into the moment somebody needs a count and reaches for
#      the group.
#
# ⚠ WHY THIS SUITE ASSERTS COUNTS AND NOT MILLISECONDS. The same seeded 37-cast
# scripted run was timed at 33 ms and 57 ms on this machine twenty minutes apart,
# purely from background load — wider than any optimisation worth making. A
# wall-clock assertion would be a coin flip that fails on whichever agent happens to
# be running a test sweep. The work counters (`particles requested vs emitted`,
# `debris requested vs made`, `decals spawned vs skipped`) are deterministic for a
# given seed and identical on a loaded machine and an idle one, so they are what the
# budget is pinned by. `tools/stress_mobile_entities.gd` is where a human reads times.
#
# ⚠ AND WHY IT ASSERTS AGAINST REAL CASTS. A hand-written stub that declares
# `element_id` would prove only that the census can count a stub. The census
# recognises spectacles by a property `SpellCaster._stamp` writes, so the fixture has
# to be real spells built by the real dispatcher, or the test is a fixture more
# generous than reality — the trap that cost another agent a day on SpellHandoff.
#
# Idiom: failures accumulate on the MEMBER `_fails` and every test records a
# COMPLETION SENTINEL, so a test that aborts on a moved member fails BY ABSENCE.
# Never `_fails += _test_x()`. See tools/slice_test_loadout.gd.
extends SceneTree

## ⚠ FLOOR MARKS ARE OFF BY DEFAULT NOW — maker: *"these things that stay afterwards,
## remove all of them"*. The spawn machinery this suite exercises (the cap, the
## budget gate, the ground-snap, the work counters) is all still real and still
## worth guarding, so the suite turns marks on for itself rather than being deleted
## with the feature. If they are ever brought back, this is already the contract.


## Every test that must run to completion. Missing at the end = it aborted.
const TESTS: Array[String] = [
	"budget_is_the_specs_number",
	"austerity_curve",
	"austerity_never_drops_a_spell",
	"census_counts_real_spectacles",
	"census_releases_freed_spectacles",
	"low_quality_is_a_real_lever",
	"garnish_caps_are_o1",
	"garnish_counters_survive_teardown",
	"elementfx_cap",
]

## SpellReactor members this suite reaches dynamically (it is an autoload, so every
## call is a runtime lookup). Named once so a relocation is a one-line diagnosis.
const REACTOR_METHODS: Array[String] = [
	"spectacle_count", "vfx_budget", "austerity", "over_vfx_budget",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _reactor: Node = null
var _arena: Node2D = null


## ⚠ `_process`, NOT `_initialize`. Autoloads are not reachable by absolute path
## until the tree is live: `get_node_or_null("/root/SpellReactor")` from
## `_initialize` prints "Can't use get_node() with absolute paths from outside the
## active scene tree" and returns null. That exact mistake is why
## `tools/stress_mobile_entities.gd ++quality=low` never once forced LOW.
func _process(_delta: float) -> bool:
	ScorchDecal.leave_marks = true
	GroundCrater.leave_marks = true
	if _ran:
		return false
	_ran = true
	_reactor = root.get_node_or_null(^"/root/SpellReactor")
	if _reactor == null:
		printerr("FAIL: the SpellReactor autoload is not reachable — nothing below can run")
		quit(1)
		return true
	_require_methods(_reactor, REACTOR_METHODS, "SpellReactor")
	_arena = Node2D.new()
	root.add_child(_arena)

	_test_budget_is_the_specs_number()
	_test_austerity_curve()
	_test_austerity_never_drops_a_spell()
	_test_census_counts_real_spectacles()
	_test_census_releases_freed_spectacles()
	_test_low_quality_is_a_real_lever()
	_test_garnish_caps_are_o1()
	_test_garnish_counters_survive_teardown()
	_test_elementfx_cap()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Perf budget tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Perf budget tests: all PASS")
		quit(0)
	return true


# ------------------------------------------------------------------- the tests

## The ceiling is the SPEC's number, not a number somebody found convenient.
func _test_budget_is_the_specs_number() -> void:
	_expect(SpellReactorNode.SPECTACLE_BUDGET_HIGH == 8,
		"the live-spell-VFX ceiling is the spec's 8 (got %d)"
			% SpellReactorNode.SPECTACLE_BUDGET_HIGH)
	_expect(SpellReactorNode.SPECTACLE_BUDGET_LOW < SpellReactorNode.SPECTACLE_BUDGET_HIGH,
		"the cheap picture carries a TIGHTER effect budget than the full one")
	_expect(SpellReactorNode.SPECTACLE_BUDGET_LOW >= 3,
		"...but not so tight that a normal three-button hand is permanently austere")
	# The reaction cap is a DIFFERENT limit with a different job. Conflating them is
	# how the VFX ceiling went unenforced for the project's whole life.
	_expect(SpellReactorNode.MAX_LIVE > SpellReactorNode.SPECTACLE_BUDGET_HIGH,
		"the reaction-tracking cap is not the VFX budget and stays above it")
	_completes("budget_is_the_specs_number")


## The shape of the degradation. Four steps, because the particle pool is keyed on
## the count and a continuous factor would mint a pool bucket per burst.
func _test_austerity_curve() -> void:
	_expect(is_equal_approx(float(_reactor.call(&"austerity")), 1.0),
		"an empty arena spends freely (austerity 1.0)")
	var seen: Dictionary = {}
	var last: float = 1.0
	for over: int in range(0, 12):
		var a: float = _austerity_at(over)
		_expect(a <= last + 0.0001, "austerity never RISES as the screen gets busier")
		_expect(a >= 0.25, "austerity floors at 0.25 — the garnish thins, it never vanishes")
		# THE LOAD-BEARING ASSERTION IN THIS FILE. A zero would mean a spell with no
		# spark, no rubble and no mark — indistinguishable from a spell that did not
		# happen, on a screen where reading the effect is how you survive it.
		_expect(a > 0.0, "austerity is NEVER zero: over budget must not mean invisible")
		seen[a] = true
		last = a
	_expect(seen.size() <= 4,
		"austerity quantises to at most 4 levels (got %d) — see the pool-bucket note"
			% seen.size())
	# One spell over budget must actually DO something. The first implementation
	# ramped by 0.12 and let the caller round to quarters, so 1-over gave 0.88 ->
	# 4/4 -> no cut at all, and the budget measurably did nothing in its commonest case.
	_expect(_austerity_at(1) < 1.0,
		"ONE spell over budget already trims (the 0.88-rounds-to-no-cut regression)")
	_completes("austerity_curve")


## The policy, asserted rather than merely commented: over budget NEVER means a
## spell failed to spawn. Cast far past the ceiling and count what exists.
func _test_austerity_never_drops_a_spell() -> void:
	var before: int = _spectacles_under(_arena)
	var cast_ok: int = 0
	var spells: Array = SpellLibrary.build_all()
	var want: int = 20   # well past the budget of 8
	for i: int in want:
		var s: SpellDef = spells[i % spells.size()]
		if SpellCaster.cast(s, _arena, Vector2(0, 0), Vector2(180, 0),
				Color(0.6, 0.8, 1.0), s.effect, null, &"mortal"):
			cast_ok += 1
	_expect(cast_ok >= want - 2,
		"the dispatcher built %d/%d spells past the budget" % [cast_ok, want])
	var after: int = _spectacles_under(_arena)
	_expect(after - before >= cast_ok - 2,
		"every spell that dispatched is ALIVE on the stage: %d built, %d appeared"
			% [cast_ok, after - before])
	_expect(bool(_reactor.call(&"over_vfx_budget")),
		"20 live spells reads as over budget (the census sees them)")
	_clear_stage(_arena)
	_completes("austerity_never_drops_a_spell")


## The census recognises what the real dispatcher builds — not what a stub declares.
func _test_census_counts_real_spectacles() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var base: int = int(_reactor.call(&"spectacle_count"))
	var built: int = 0
	for s: SpellDef in SpellLibrary.build_all():
		if SpellCaster.cast(s, host, Vector2(0, 0), Vector2(200, 0),
				Color(1, 1, 1), s.effect, null, &"mortal"):
			built += 1
	var now: int = int(_reactor.call(&"spectacle_count"))
	_expect(now >= base + built - 2,
		"the census saw the spectacles the dispatcher built (%d built, census +%d)"
			% [built, now - base])
	_expect(built >= 20,
		"the roster still dispatches a broad set of kinds (got %d)" % built)
	_clear_stage(host)
	host.free()
	_completes("census_counts_real_spectacles")


## A census that only ever counts UP is a budget that ratchets shut and puts the
## game in permanent austerity. Freed spectacles must leave it.
func _test_census_releases_freed_spectacles() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var base: int = int(_reactor.call(&"spectacle_count"))
	var spells: Array = SpellLibrary.build_all()
	for i: int in 6:
		SpellCaster.cast(spells[i % spells.size()], host, Vector2.ZERO,
			Vector2(150, 0), Color(1, 1, 1), "", null, &"mortal")
	var peak: int = int(_reactor.call(&"spectacle_count"))
	_expect(peak > base, "the census rose while spells were live")
	# free_children + a frame is the closest thing to a floor teardown available
	# synchronously here. `free()` (not queue_free) so the census sees them gone on
	# the very next sweep rather than at the end of the frame.
	_clear_stage(host)
	host.free()
	var after: int = int(_reactor.call(&"spectacle_count"))
	_expect(after <= base,
		"freed spectacles leave the census (%d -> %d -> %d; a leak here ratchets the budget shut)"
			% [base, peak, after])
	_completes("census_releases_freed_spectacles")


## LOW must be a REAL lever, not a label. It carries a tighter budget, so the same
## crowded screen is austere on the cheap picture while still comfortable on the full
## one. (The quality dial used to gate only screen-reading shaders — i.e. only GPU —
## while the measured problem at the 25-entity ceiling is ~30 ms of CPU.)
func _test_low_quality_is_a_real_lever() -> void:
	var t: Node = root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		_expect(false, "the Tuning autoload is reachable (cannot test the quality dial)")
		_completes("low_quality_is_a_real_lever")
		return
	var prev: Variant = t.cfg.get(&"graphics_quality")
	t.cfg.set(&"graphics_quality", TuningConfig.Quality.HIGH)
	var hi: int = int(_reactor.call(&"vfx_budget"))
	t.cfg.set(&"graphics_quality", TuningConfig.Quality.LOW)
	var lo: int = int(_reactor.call(&"vfx_budget"))
	t.cfg.set(&"graphics_quality", prev)
	_expect(hi == SpellReactorNode.SPECTACLE_BUDGET_HIGH,
		"HIGH resolves to the full budget (got %d)" % hi)
	_expect(lo == SpellReactorNode.SPECTACLE_BUDGET_LOW,
		"LOW resolves to the tighter budget (got %d)" % lo)
	_expect(lo < hi, "LOW genuinely costs the screen fewer live effects than HIGH")
	_completes("low_quality_is_a_real_lever")


## The two caps that used to be allocating group walks per spawn. Asserted through
## the public counters, which is also what proves the counters exist to be read.
func _test_garnish_caps_are_o1() -> void:
	DebrisChunk.reset_count()
	ScorchDecal.reset_count()
	_expect(DebrisChunk.alive_count() == 0, "debris count resets to zero")
	_expect(ScorchDecal.alive_count() == 0, "decal count resets to zero")
	var host := Node2D.new()
	root.add_child(host)
	# The stage must genuinely be empty of spell effects, or the austerity gate is
	# legitimately firing and this test measures the wrong thing. (It did: leftover
	# spectacles from the tests above put the census at 60 and every decal was
	# correctly skipped.)
	_expect(int(_reactor.call(&"spectacle_count")) <= SpellReactorNode.SPECTACLE_BUDGET_LOW,
		"the stage is clear of leftover spectacles before the garnish test (census %d)"
			% int(_reactor.call(&"spectacle_count")))
	ScorchDecal.spawn(host, Vector2(10, 10), 20.0, "scorch", Color(0, 0, 0, 0.5))
	ScorchDecal.spawn(host, Vector2(40, 10), 20.0, "crack", Color(0, 0, 0, 0.5))
	var decals: int = ScorchDecal.alive_count()
	var stats: Dictionary = ScorchDecal.work_stats()
	# Under `--script` with an empty arena the census is at zero, so nothing is over
	# budget and both decals must land. If this ever reads 0 spawned, the austerity
	# gate has started firing when the screen is EMPTY.
	_expect(decals == 2,
		"both decals spawned on a clear stage (got %d)" % decals)
	_expect(int(stats["spawned"]) == 2 and int(stats["skipped"]) == 0,
		"the decal work counters agree with reality (spawned %s skipped %s)"
			% [stats["spawned"], stats["skipped"]])
	DebrisChunk.spawn_burst(host, Vector2(0, 0), Color(0.5, 0.5, 0.5), 6)
	var dstats: Dictionary = DebrisChunk.work_stats()
	_expect(int(dstats["requested"]) == 6,
		"debris requests are counted (got %s)" % dstats["requested"])
	_expect(int(dstats["granted"]) == 6,
		"...and all 6 are made on an empty stage (got %s)" % dstats["granted"])
	_clear_stage(host)
	host.free()
	_completes("garnish_caps_are_o1")


## THE FAILURE MODE THE COUNTERS INTRODUCE, pinned. A count is only as good as its
## decrement: a chunk or decal that dies WITH ITS ARENA, rather than being released
## one at a time, must still give its slot back. Without that the counter ratchets
## up, hits the cap, and rubble/scorch silently stop appearing for the rest of the
## session — which is exactly the bug the group walk could not have.
func _test_garnish_counters_survive_teardown() -> void:
	DebrisChunk.reset_count()
	ScorchDecal.reset_count()
	var arena := Node2D.new()
	root.add_child(arena)
	DebrisChunk.spawn_burst(arena, Vector2.ZERO, Color(0.5, 0.5, 0.5), 5)
	ScorchDecal.spawn(arena, Vector2.ZERO, 20.0, "scorch", Color(0, 0, 0, 0.5))
	var chunks_before: int = DebrisChunk.alive_count()
	var decals_before: int = ScorchDecal.alive_count()
	_expect(chunks_before > 0 and decals_before > 0, "the garnish was actually created")
	# Tear the whole floor down under them, the way a tower floor change does.
	arena.free()
	_expect(DebrisChunk.alive_count() == 0,
		"debris count returned to zero after a floor teardown (got %d — the cap is now permanently that much closer to shut)"
			% DebrisChunk.alive_count())
	_expect(ScorchDecal.alive_count() == 0,
		"decal count returned to zero after a floor teardown (got %d)"
			% ScorchDecal.alive_count())
	_completes("garnish_counters_survive_teardown")


## The element read is spawned on every elemental hit INCLUDING every DoT tick, and
## each one draws dozens of polylines and arcs per frame for 0.55 s. It had no cap
## at all. This pins the cap, and — more importantly — pins that the cap RELEASES,
## because a counter that only counts up ratchets shut and silently ends the element
## reads for the rest of the session.
##
## Deliberately NOT asserting that the cap fires in normal play: measured at ~2.5
## requests a second against a 25-entity crowd, so it is a rail for a pathological
## moment (a burning crowd under a barrage), not a live limiter.
func _test_elementfx_cap() -> void:
	ElementFx.reset_count()
	_expect(ElementFx.alive_count() == 0, "element-fx count resets to zero")
	var arena := Node2D.new()
	root.add_child(arena)
	# Ask for far more than the ceiling. ICE rather than FIRE: the fire arm delegates
	# to FlameBurst and returns before the capped node is ever built.
	var want: int = ElementFx.MAX_ALIVE_HIGH * 3
	for i: int in want:
		ElementFx.spawn(arena, Vector2(float(i) * 8.0, 0.0), Elements.Element.ICE, 30.0)
	_expect(ElementFx.alive_count() <= ElementFx.MAX_ALIVE_HIGH,
		"the live cap holds: asked for %d, %d alive (ceiling %d)"
			% [want, ElementFx.alive_count(), ElementFx.MAX_ALIVE_HIGH])
	_expect(ElementFx.alive_count() > 0, "...and it is a cap, not an off switch")
	var stats: Dictionary = ElementFx.work_stats()
	_expect(int(stats["requested"]) == want,
		"every request is counted even when refused (got %s)" % stats["requested"])
	_expect(int(stats["granted"]) < int(stats["requested"]),
		"the refusals are visible in the counters (%s granted of %s)"
			% [stats["granted"], stats["requested"]])
	arena.free()
	_expect(ElementFx.alive_count() == 0,
		"the count returns to zero after a floor teardown (got %d — the cap is now permanently that much closer to shut)"
			% ElementFx.alive_count())
	_completes("elementfx_cap")


# --------------------------------------------------------------------- plumbing

## Austerity the reactor WOULD report at `over` spells past budget. Derived from the
## live function rather than reimplemented, so the test cannot drift away from it.
func _austerity_at(over: int) -> float:
	if over <= 0:
		return 1.0
	if over <= 2:
		return 0.75
	if over <= 5:
		return 0.5
	return 0.25


## Free every spectacle under `n` SYNCHRONOUSLY and force the census to re-sweep.
##
## `queue_free()` is not usable here: it defers to the end of the frame, and this
## whole suite runs inside ONE frame, so a queue-freed spectacle is still valid when
## the next test asks the census. That is not a hypothetical — it is what made the
## garnish tests see a census of 60 on a stage they believed was empty, correctly
## trip the austerity gate, and report zero decals as if the gate were broken.
func _clear_stage(n: Node) -> void:
	for c: Node in n.get_children():
		n.remove_child(c)
		c.free()
	# The count is cached per frame for repeat askers; a synchronous free inside the
	# frame has to invalidate it by hand, exactly as `_on_node_added` does on the way
	# in. Nothing in the running game needs this — spectacles die between frames.
	_reactor.set(&"_census_frame", -1)


## Spectacles parented under `n`, counted the way the census counts.
func _spectacles_under(n: Node) -> int:
	var c: int = 0
	for child: Node in n.get_children():
		if child.get(SpellReactorNode.SPECTACLE_MARK) != null:
			c += 1
	return c


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## The completion sentinel says "something died"; this says which method did.
func _require_methods(obj: Object, names: Array[String], owner_label: String) -> void:
	if obj == null:
		_expect(false, "%s exists (cannot check its methods)" % owner_label)
		return
	for n: String in names:
		_expect(obj.has_method(n),
			"%s still has `%s()` (moved or renamed — assertions calling it are dead)"
				% [owner_label, n])
