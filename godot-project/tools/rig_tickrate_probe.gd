# Shared driver for the rig's tick-rate comparison. NOT a test suite on its own —
# `tools/rig_tickrate_trace.gd` (the diagnostic table) and
# `tools/slice_test_rig_tickrate.gd` (the pinned regression) both instantiate this so
# the motion script and the divergence maths exist exactly once.
#
# WHY THIS EXISTS AT ALL
#
# Every hand-tuned number in `CharacterRig` was signed off in the spike playground, and
# both spike hosts force `Engine.physics_ticks_per_second = 120`
# (`RigSpikeController`, `SpellPlaygroundController`). The shipped game runs 60
# (`project.godot [physics]`). So any part of the rig that is not tick-rate independent
# is a DIFFERENT CHARACTER in the game than the one the maker approved — silently, with
# nothing erroring and every test green. That is not hypothetical: it is what the gait
# was doing, at 19 px of foot drift on a 31 px figure.
#
# The method is a divergence trace. Drive two rigs through the SAME time-parameterised
# world motion, one at 1/60 and one at 1/120, sample both on a common clock, and compare.
# A tick-rate-independent channel converges; a dependent one does not.
extends RefCounted

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const HEIGHT: float = 31.0
## Hero.SPEED — the speed the gait is actually asked to walk at in a fight, and the
## speed at which its step cycle is narrowest in frames. Testing a slow amble would
## hide the very aliasing this exists to catch.
const WALK_SPEED: float = 210.0
const SAMPLE_HZ: float = 60.0
const DURATION: float = 4.0

## Channels traced, with the divergence above which the channel is called tick-rate
## DEPENDENT rather than merely imprecise. Units are the channel's own (px, rad, px/s).
##
## Tolerances are deliberately tight — a fraction of a pixel on a 31 px figure — because
## the failure being defended against was 60% of the figure's height. They are not
## "close enough" thresholds, they are "the two clocks agree" thresholds.
const CHANNELS: Array[Dictionary] = [
	{"name": "ride_y", "tol": 0.35, "unit": "px"},
	{"name": "pitch", "tol": 0.05, "unit": "rad"},
	{"name": "gait_speed", "tol": 6.0, "unit": "px/s"},
	{"name": "foot0_x", "tol": 1.2, "unit": "px"},
	{"name": "foot0_y", "tol": 1.2, "unit": "px"},
	{"name": "foot1_x", "tol": 1.2, "unit": "px"},
	{"name": "foot1_y", "tol": 1.2, "unit": "px"},
	{"name": "sim_foot_lead_y", "tol": 1.2, "unit": "px"},
	{"name": "sim_hand_lead_y", "tol": 1.2, "unit": "px"},
]


## Drive one rig for DURATION at `dt`, sampling every 1/SAMPLE_HZ of simulated time.
## Returns {channel_name: Array[float], "samples": int}.
##
## The motion is a pure function of `t`, so both tick rates traverse the IDENTICAL world
## trajectory and any divergence in the output is the rig's own doing.
##
## The rig is hosted under a MOVED PARENT rather than moved directly, because that is the
## in-game topology: Hero is the CharacterBody2D that travels, the rig is a child at local
## origin whose own `position.y` belongs to the ride spring. Moving the rig directly would
## fight `_apply_body_transform` for ownership of that axis.
func run(dt: float, tree_root: Node) -> Dictionary:
	var host := Node2D.new()
	tree_root.add_child(host)
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", HEIGHT)
	# ⚠ PIN THE FLAIL PHASE. `CharacterRig._flail_seed` is randomised per INSTANCE (the
	# spike does the same) so a room of knocked-down fighters does not churn in unison.
	# This probe builds a SEPARATE rig for each tick rate and diffs them, so an unpinned
	# phase means the two runs are given different inputs and the divergence it reports is
	# the seed, not the tick rate — measured at 1.3-2.1 px of false divergence on the
	# hand/foot channels, i.e. intermittently over the 1.2 px tolerance.
	#
	# This is NOT a widened tolerance. The bound is untouched; the two runs are simply
	# made comparable, which is what the suite always meant to be measuring.
	rig.set("_flail_seed", 0.0)
	host.add_child(rig)

	var out: Dictionary = {}
	# ⚠ Array, NOT PackedFloat64Array. Packed arrays are VALUE types, so
	# `out[name].append(x)` appends to a temporary copy and discards it — and the suite
	# then reports a flawless 0.0000 divergence on every channel because every trace is
	# EMPTY. That false green happened here on the first run of this tool. Array is a
	# reference type; the sample-count assertion below is the belt to that brace.
	for ch: Dictionary in CHANNELS:
		out[String(ch["name"])] = ([] as Array)

	var t: float = 0.0
	var next_sample: float = 0.0
	var sample_dt: float = 1.0 / SAMPLE_HZ
	var samples: int = 0
	rig.call("set_grounded", true)
	rig.call("play", 0)
	while t < DURATION:
		_pose_world(host, rig, t)
		rig.call("advance", dt)
		t += dt
		if t >= next_sample:
			for ch: Dictionary in CHANNELS:
				var cname: String = String(ch["name"])
				(out[cname] as Array).append(_read(rig, cname))
			samples += 1
			next_sample += sample_dt
	out["samples"] = samples
	host.free()
	return out


## THE MOTION SCRIPT — position and animation state as a function of time only.
##
## Phases, chosen to exercise each regime the maker actually looks at:
##   0.0-1.0  idle, grounded           both springs at rest; the gait settles the stance
##   1.0-3.0  walk right at Hero.SPEED the gait steps; the pitch spring chases the lean
##   3.0-3.6  jump arc, airborne       PITCH_GAIN_AIR, "the loose one"
##   3.6-4.0  grounded again           touchdown squash + rebound, the ride spring
func _pose_world(host: Node2D, rig: Node2D, t: float) -> void:
	var x: float = 0.0
	var y: float = 0.0
	var airborne: bool = false
	if t >= 1.0:
		x = WALK_SPEED * (minf(t, 3.0) - 1.0)
	if t >= 3.0 and t < 3.6:
		airborne = true
		# Ballistic arc, apex ~28 px, back on the floor at 3.6 s. -y is up.
		var u: float = t - 3.0
		y = -(4.0 * 28.0 * u * (0.6 - u) / 0.36)
		x += WALK_SPEED * 0.5 * u
	elif t >= 3.6:
		x += WALK_SPEED * 0.5 * 0.6
	host.position = Vector2(x, y)
	rig.call("set_grounded", not airborne)
	rig.call("set_body_velocity", Vector2(WALK_SPEED if (t >= 1.0 and t < 3.0) else 0.0, 0.0))
	if airborne:
		rig.call("play", 8)        # State.AIR
		rig.call("set_air_phase", t < 3.3, false)
	elif t >= 1.0 and t < 3.0:
		rig.call("play", 1)        # State.RUN
	else:
		rig.call("play", 0)        # State.IDLE


## One channel's scalar for this sample. The foot plants are reported RELATIVE to the
## rig's own world x: they are held in world space (that is the whole anti-slide
## mechanism), so an absolute reading would be dominated by the shared trajectory and
## would hide the thing being measured.
func _read(rig: Node2D, cname: String) -> float:
	match cname:
		"ride_y":
			return float(rig.get("_ride"))
		"pitch":
			return float(rig.get("rotation"))
		"gait_speed":
			return float(rig.get("_gait_speed"))
		"foot0_x":
			return (rig.call("_gait_foot_world", 0) as Vector2).x - rig.global_position.x
		"foot0_y":
			return (rig.call("_gait_foot_world", 0) as Vector2).y - rig.global_position.y
		"foot1_x":
			return (rig.call("_gait_foot_world", 1) as Vector2).x - rig.global_position.x
		"foot1_y":
			return (rig.call("_gait_foot_world", 1) as Vector2).y - rig.global_position.y
		"sim_foot_lead_y":
			return ((rig.get("_sim") as Dictionary).get("foot_lead", Vector2.ZERO) as Vector2).y
		"sim_hand_lead_y":
			return ((rig.get("_sim") as Dictionary).get("hand_lead", Vector2.ZERO) as Vector2).y
	return 0.0


## Divergence between two traces of the same channel.
## Returns {"raw": float, "aligned": float, "rms": float, "n": int}.
##
## `raw` is the plain sample-for-sample maximum. `aligned` allows each sample to match
## its counterpart OR either NEIGHBOUR, and it is the figure the pass/fail is judged on.
##
## ⚠ THAT ALLOWANCE IS NOT SLOP, AND IT IS NOT A WAY TO GET TO GREEN. Two different tick
## grids cannot place a DISCONTINUOUS state change at the same instant: the frame where
## IDLE becomes RUN, or where airborne becomes grounded, exists at a different sub-sample
## offset on each clock, so the transient that follows is offset by up to one sample. The
## trajectories are identical, the phase is not. Allowing exactly one sample of slack
## measures "same motion" instead of "same motion at the same instant".
##
## It cannot launder a real failure, which is the point: the gait bug this tool was built
## for put the feet 19 px apart and kept them there for the whole walk. No one-sample
## shift touches that — a different trajectory stays different. Both figures are printed
## by the diagnostic so the raw number is never hidden.
func divergence(a: Array, b: Array) -> Dictionary:
	var n: int = mini(a.size(), b.size())
	var raw: float = 0.0
	var aligned: float = 0.0
	var acc: float = 0.0
	for i: int in n:
		var av: float = float(a[i])
		var d: float = absf(av - float(b[i]))
		raw = maxf(raw, d)
		acc += d * d
		var best: float = d
		if i > 0:
			best = minf(best, absf(av - float(b[i - 1])))
		if i + 1 < n:
			best = minf(best, absf(av - float(b[i + 1])))
		aligned = maxf(aligned, best)
	return {
		"raw": raw,
		"aligned": aligned,
		"rms": sqrt(acc / maxf(float(n), 1.0)),
		"n": n,
	}
