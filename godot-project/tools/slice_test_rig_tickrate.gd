# Run: godot --headless --path godot-project --script tools/slice_test_rig_tickrate.gd
#
# THE RIG MUST FEEL THE SAME AT 60 Hz AS IT DOES AT 120 Hz. This suite is the permanent
# form of that requirement; tools/rig_tickrate_trace.gd is the diagnostic you run when
# this goes red, and tools/rig_tickrate_probe.gd carries the shared driver + reasoning.
#
# WHY IT IS WORTH A SUITE OF ITS OWN
#
# Every hand-tuned number in `CharacterRig` was signed off in the spike playground, and
# both spike hosts force `Engine.physics_ticks_per_second = 120` (`RigSpikeController`,
# `SpellPlaygroundController`). The shipped game runs 60 (`project.godot [physics]`). So
# a rig subsystem that quietly depends on the tick rate is a DIFFERENT CHARACTER in the
# game than the one the maker approved — and nothing errors, nothing goes red, and no
# other suite in this repo would notice, because they all drive the rig at one fixed dt.
#
# That is not a hypothetical. The gait was doing exactly this: its step cycle is ~3.5
# physics frames wide at Hero.SPEED on 60 Hz, its trigger aliased against the frame grid,
# and the world-locked plants landed up to 19 px — 60% of the figure's height — away from
# where the same walk puts them at 120 Hz. It read as a limp, and it survived a full
# green sweep. The fix was sub-stepping, not retuning; this suite is what stops the
# integration budget being quietly spent again.
#
# TEST HYGIENE (house rule, see tools/slice_test_loadout.gd): never `failed += _test_x()`.
# A dead property read aborts the enclosing function and the call still evaluates to 0,
# which reads as "no failures". Failures accumulate on the `_failed` MEMBER and every
# test sets its own completion sentinel, so a test that aborts fails BY ABSENCE.
extends SceneTree

const PROBE_PATH: String = "res://tools/rig_tickrate_probe.gd"
const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"

## The tick rates that must agree: what the game ships (project.godot) and what the
## spike playground the numbers were approved in forces.
const GAME_HZ: float = 60.0
const SPIKE_HZ: float = 120.0

const EXPECTED: Array[String] = [
	"channels_converge", "traces_are_not_empty",
	"substep_budget_has_headroom", "substep_resolution_holds_at_game_rate",
	"gait_is_substepped",
]

var _ran: bool = false
var _failed: int = 0
var _done: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true

	_test_traces_are_not_empty()
	_test_channels_converge()
	_test_substep_budget_has_headroom()
	_test_substep_resolution_holds_at_game_rate()
	_test_gait_is_substepped()

	for key: String in EXPECTED:
		if not bool(_done.get(key, false)):
			_failed += 1
			printerr("  FAIL: test '%s' did not run to completion" % key)

	if _failed == 0:
		print("rig tickrate tests: all PASS")
	else:
		printerr("rig tickrate tests: %d FAILED" % _failed)
	quit(1 if _failed > 0 else 0)
	return true


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failed += 1
		printerr("  FAIL: ", label)


func _probe() -> RefCounted:
	return (load(PROBE_PATH) as GDScript).new()


## Guard the guard. The first version of this trace reported a flawless 0.0000 on every
## channel because `PackedFloat64Array` is a value type and every `append` went into a
## discarded copy — a perfect green over nothing at all, which is the exact failure mode
## this repo's test-hygiene rule exists for. An empty trace must be a FAILURE, never a pass.
func _test_traces_are_not_empty() -> void:
	var probe: RefCounted = _probe()
	var a: Dictionary = probe.call("run", 1.0 / GAME_HZ, root)
	_expect(int(a["samples"]) > 200, "60 Hz run produced a full trace (%d samples)" % int(a["samples"]))
	for ch: Dictionary in (probe.get("CHANNELS") as Array):
		var cname: String = String(ch["name"])
		var trace: Array = a[cname]
		_expect(trace.size() == int(a["samples"]),
			"channel `%s` recorded every sample (%d of %d)" % [cname, trace.size(), int(a["samples"])])
	_done["traces_are_not_empty"] = true


## THE HEADLINE. Same walk, same jump, same landing, two clocks — every traced channel
## has to land in the same place.
func _test_channels_converge() -> void:
	var probe: RefCounted = _probe()
	var a: Dictionary = probe.call("run", 1.0 / GAME_HZ, root)
	var b: Dictionary = probe.call("run", 1.0 / SPIKE_HZ, root)
	for ch: Dictionary in (probe.get("CHANNELS") as Array):
		var cname: String = String(ch["name"])
		var d: Dictionary = probe.call("divergence", a[cname] as Array, b[cname] as Array)
		_expect(int(d["n"]) > 200, "channel `%s` had samples to compare" % cname)
		_expect(float(d["aligned"]) <= float(ch["tol"]),
			"channel `%s` converges across 60/120 Hz (%.4f %s, tol %.3f) — the %s"
			% [cname, float(d["aligned"]), String(ch["unit"]), float(ch["tol"]),
				"rig feels different in-game than it does in the playground"])
	_done["channels_converge"] = true


## The sub-step CEILING must not be the 60 Hz requirement itself.
##
## At 1/60 s the rig asks for exactly 8 sub-steps of 1/480 s. With the cap also at 8 —
## which is how it shipped — the nominal case sat precisely on the limit and every path
## that hands `advance()` a longer delta (Engine.time_scale > 1, an owner accumulating
## deltas, every capture harness driving the rig by hand) integrated COARSER than the
## springs were tuned for, with no margin whatsoever. Headroom is what this pins.
func _test_substep_budget_has_headroom() -> void:
	var rig: GDScript = load(RIG_PATH) as GDScript
	var substep: float = float(rig.get("BODY_SUBSTEP"))
	var cap: int = int(rig.get("BODY_MAX_SUBSTEPS"))
	var needed_at_game_rate: int = int(ceil((1.0 / GAME_HZ) / substep))
	_expect(is_equal_approx(substep, 1.0 / 480.0),
		"body sub-step is still the tuned 1/480 s (got 1/%.1f)" % (1.0 / substep))
	_expect(cap > needed_at_game_rate,
		"sub-step ceiling (%d) leaves headroom above the %d a 60 Hz frame needs"
		% [cap, needed_at_game_rate])
	_expect(cap >= int(ceil((1.0 / 30.0) / substep)),
		"sub-step ceiling (%d) still resolves a doubled 1/30 s frame at 1/480 s" % cap)
	_done["substep_budget_has_headroom"] = true


## Whatever the cap is, a frame at the SHIPPED tick rate must actually be integrated at
## 1/480 s. This is the property the constants were tuned under; the cap is only the
## mechanism. Checked across the frame lengths the rig realistically sees.
func _test_substep_resolution_holds_at_game_rate() -> void:
	var rig: GDScript = load(RIG_PATH) as GDScript
	var substep: float = float(rig.get("BODY_SUBSTEP"))
	var cap: int = int(rig.get("BODY_MAX_SUBSTEPS"))
	for hz: float in [30.0, GAME_HZ, SPIKE_HZ, 144.0]:
		var delta: float = 1.0 / hz
		var steps: int = clampi(int(ceil(delta / substep)), 1, cap)
		var sdt: float = delta / float(steps)
		# Float-exact equality is the wrong test here; one part in 10^4 of the sub-step
		# is well inside "the same integration" and well outside a halving.
		_expect(sdt <= substep * 1.0001,
			"a %.0f Hz frame integrates at 1/480 s or finer (got 1/%.1f)" % [hz, 1.0 / sdt])
	_done["substep_resolution_holds_at_game_rate"] = true


## The gait specifically — a behavioural test, not a constants test.
##
## Drive the SAME walk at both rates and compare where the feet actually get planted.
## Reads the plants directly rather than through the probe so this still fails loudly if
## someone "simplifies" the probe's channel list.
func _test_gait_is_substepped() -> void:
	var plants_60: Array = _walk_plants(1.0 / GAME_HZ)
	var plants_120: Array = _walk_plants(1.0 / SPIKE_HZ)
	_expect(plants_60.size() > 4, "the 60 Hz walk planted feet at all (%d)" % plants_60.size())
	_expect(absf(float(plants_60.size() - plants_120.size())) <= 1.0,
		"both clocks take the same number of steps over the same distance (%d vs %d)"
		% [plants_60.size(), plants_120.size()])
	# Steps land at the same WORLD positions: this is the anti-limp property. Before the
	# gait was sub-stepped these drifted apart by more than a full stride.
	var worst: float = 0.0
	for i: int in mini(plants_60.size(), plants_120.size()):
		worst = maxf(worst, absf(float(plants_60[i]) - float(plants_120[i])))
	_expect(worst < 1.0,
		"foot plants land at the same world x on both clocks (worst %.3f px)" % worst)
	_done["gait_is_substepped"] = true


## Walk a rig 400 px at Hero.SPEED and return the world x of every foot plant.
## Same host-moves-the-rig topology as the probe, for the same reason.
##
## ⚠ Plants are read off the `foot_planted` SIGNAL, not inferred by watching `_swing_t`
## cross 1.0. The inferred version was the first thing written here and it was wrong:
## a completed swing and the next step's trigger can fall in the same frame or in
## consecutive ones depending on the clock, so "t reached 1.0 OR the swing foot changed"
## counted one plant twice at 120 Hz and once at 60 Hz. That reported a 2-step, 18 px
## disagreement between two walks the trace had already shown to be IDENTICAL — i.e. the
## instrument was the bug. The signal fires exactly once per plant by construction, and
## reading it also puts the signal itself under test.
func _walk_plants(dt: float) -> Array:
	var host := Node2D.new()
	root.add_child(host)
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", 31.0)
	host.add_child(rig)
	var log := _PlantLog.new()
	log.rig = rig
	rig.connect("foot_planted", Callable(log, "on_plant"))
	rig.call("set_grounded", true)
	rig.call("play", 1)   # State.RUN
	var speed: float = 210.0
	var travelled: float = 0.0
	# Settle the stance first; the seeding frames are not steps.
	for i: int in 8:
		rig.call("advance", dt)
	log.xs.clear()
	while travelled < 400.0:
		host.position.x += speed * dt
		travelled += speed * dt
		rig.call("advance", dt)
	var out: Array = log.xs.duplicate()
	host.free()
	return out


## Records the world x of each foot plant as the rig emits it. The plant has already
## been committed to `_plant_w[_swing_foot]` when the signal fires, so that is the
## authoritative position.
class _PlantLog:
	extends RefCounted
	var rig: Node2D = null
	var xs: Array = []

	func on_plant() -> void:
		var plants: Array = rig.get("_plant_w")
		xs.append((plants[int(rig.get("_swing_foot"))] as Vector2).x)
