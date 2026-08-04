# Run: godot --headless --path godot-project --script tools/slice_test_rig_gait.gd
#
# Covers the two things this branch changed in CharacterRig:
#   1. the WORLD-LOCKED foot-plant gait ported from SpikeFigure (the anti-slide), and
#   2. gear that REPLACES body parts instead of overlaying them.
#
# Plus a smoke pass over the public rig surface, because CharacterRig drives the hero,
# every enemy AND the Boss — a silent break in any of those methods is a whole-game
# outage, not a cosmetic one.
#
# TEST HYGIENE (house rule): never `failed += _test_x()`. A dead property read aborts
# the function mid-way and the call still evaluates to 0, which reads as "no failures".
# Every test accumulates onto the `_failed` MEMBER and sets its own completion
# sentinel; the summary below refuses to pass unless every sentinel came back true.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"

var _ran: bool = false
var _failed: int = 0
var _done: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true

	_test_gait_seeds_and_locks()
	_test_gait_reads_as_a_stride()
	_test_a_planted_foot_can_reach_the_ground()
	_test_gait_steps_and_signals()
	_test_gait_disabled_when_airborne()
	_test_gear_hitbox_contract()
	_test_gear_registry()
	_test_public_surface()

	# Completion sentinels: a test that died half-way never sets its own flag, so a
	# crash inside one can't be mistaken for a clean run.
	const EXPECTED: Array[String] = [
		"seeds_and_locks", "reads_as_a_stride", "foot_can_reach", "steps_and_signals", "airborne",
		"gear_hitbox", "gear_registry", "public_surface",
	]
	for key: String in EXPECTED:
		if not bool(_done.get(key, false)):
			_failed += 1
			printerr("  FAIL: test '%s' did not run to completion" % key)

	if _failed == 0:
		print("rig gait/gear tests: all PASS")
	else:
		printerr("rig gait/gear tests: %d FAILED" % _failed)
	quit(1 if _failed > 0 else 0)
	return true


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_failed += 1
		printerr("  FAIL: ", label)


## A rig detached from any scene: the ground probe finds nothing (INF), so the gait
## falls back to the figure's own standing foot line. That fallback is exactly what
## makes these tests possible headlessly.
func _make_rig() -> Node2D:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", 31.0)
	rig.call("set_grounded", true)
	rig.call("play", 0)   # State.IDLE
	return rig


## Drive N frames at a fixed step, translating the rig by `vx` px/s so the gait sees
## real travel (it derives speed from the node's own world motion, not from
## set_body_velocity — Boss and the capture rigs never feed velocity).
func _drive(rig: Node2D, frames: int, dt: float, vx: float) -> void:
	for i: int in frames:
		rig.position.x += vx * dt
		rig.call("advance", dt)


func _test_gait_seeds_and_locks() -> void:
	var rig: Node2D = _make_rig()
	# One frame with no motion history seeds nothing; the second seeds the plants.
	_drive(rig, 3, 1.0 / 60.0, 0.0)
	_expect(bool(rig.get("_gait_ready")), "gait seeds its plants on a grounded frame")

	# THE ANTI-SLIDE. Run, then watch the SUPPORT foot's world position across frames
	# while it bears weight: it must not move at all. A phase-driven sine gait fails
	# this by construction, which is precisely why the old rig read as skating.
	rig.call("play", 1)   # State.RUN
	_drive(rig, 20, 1.0 / 60.0, 180.0)
	var locked_frames: int = 0
	var slid_frames: int = 0
	for i: int in 40:
		var swing: int = int(rig.get("_swing_foot"))
		var support: int = 1 - swing
		var before: Vector2 = rig.call("_gait_foot_world", support)
		rig.position.x += 180.0 * (1.0 / 60.0)
		rig.call("advance", 1.0 / 60.0)
		# Only judge frames where that foot was still the support foot afterwards —
		# the frame a step completes legitimately moves a plant.
		if int(rig.get("_swing_foot")) != support:
			var after: Vector2 = rig.call("_gait_foot_world", support)
			if before.distance_to(after) < 0.001:
				locked_frames += 1
			else:
				slid_frames += 1
	_expect(locked_frames > 10, "support foot stays world-locked across frames (%d locked)" % locked_frames)
	_expect(slid_frames == 0, "support foot never slides while planted (%d slid)" % slid_frames)
	rig.free()
	_done["seeds_and_locks"] = true


## ⚠ THE REGRESSION THIS FILE EXISTS TO STOP, PINNED BY ITS THREE VISIBLE SYMPTOMS.
##
## The maker has reported "why are they walking on their legs" twice. Both times the
## world-locked plants themselves were fine — `_test_gait_seeds_and_locks` above was
## green throughout — and both times the walk was still wrong, because what a person
## SEES is none of the things that were being asserted. So assert those things:
##
##   CADENCE  the plants-per-second a person could count. The bug was 22 a second at
##            Hero.SPEED: a buzz, not a stride.
##   SLIDE    of the foot that is DRAWN, not of `_plant_w`. The plant held to 0.00 px
##            while the spring sim that drew it wandered 12.6 px — 41% of the whole
##            figure — around it. Reading `_gait_foot_world` here would have passed
##            through the entire bug, which is exactly what happened.
##   LIFT     as a fraction of BODY HEIGHT. The swing arc was commanded at 3.66 px and
##            drawn at 1.42 px, so the foot never visibly left the floor.
##
## Every bound is a MINIMUM OCCURRENCE as well as a limit — "at least N plants happened
## AND each held to within M px" — because "no bad plant was seen" is trivially true of
## a rig that never stepped at all.
func _test_gait_reads_as_a_stride() -> void:
	var rig: Node2D = _make_rig()
	var h: float = float(rig.get("height"))
	var vx: float = 210.0            # Hero.SPEED, where the complaint lives
	var dt: float = 1.0 / 60.0
	var seconds: float = 3.0
	var counter := _PlantCounter.new()
	rig.call("play", 1)   # RUN
	_drive(rig, 2, dt, 0.0)
	_drive(rig, 60, dt, vx)          # a second of warm-up: transients are not the walk
	rig.connect("foot_planted", Callable(counter, "on_plant"))

	var floor_w: float = rig.global_position.y + h * 0.5
	var max_slide: float = 0.0
	var max_lift: float = 0.0
	var stance_samples: int = 0
	# Per-foot: the world x it held when it touched down, and INF while it is airborne.
	var ref: Array[float] = [INF, INF]
	var was_swinging: Array[bool] = [false, false]
	for _i: int in int(seconds / dt):
		rig.position.x += vx * dt
		rig.call("advance", dt)
		# THE DRAWN pose. _sim_pose is what _draw() renders; _gait_foot_world is not.
		var pose: Dictionary = rig.call("_sim_pose")
		var swing: int = int(rig.get("_swing_foot"))
		var swinging: bool = float(rig.get("_swing_t")) < 1.0
		var fw: Array[Vector2] = [
			rig.to_global(pose["foot_lead"] as Vector2),
			rig.to_global(pose["foot_off"] as Vector2),
		]
		for i: int in 2:
			var lifting: bool = swinging and i == swing
			if lifting:
				max_lift = maxf(max_lift, floor_w - fw[i].y)
				ref[i] = INF
			elif was_swinging[i] or not is_finite(ref[i]):
				ref[i] = fw[i].x       # touch-down: this is the plant to hold
			else:
				stance_samples += 1
				max_slide = maxf(max_slide, absf(fw[i].x - ref[i]))
			was_swinging[i] = lifting
	rig.disconnect("foot_planted", Callable(counter, "on_plant"))

	var cadence: float = float(counter.count) / seconds
	# MINIMUM OCCURRENCE first: without these two, every bound below is vacuous.
	_expect(counter.count >= 15,
		"a 3 s run at %.0f px/s actually stepped (%d plants)" % [vx, counter.count])
	_expect(stance_samples >= 60,
		"feet actually bore weight to measure slide against (%d stance samples)" % stance_samples)
	_expect(cadence >= 5.0 and cadence <= 16.0,
		"cadence reads as a stride, not a buzz: %.1f steps/s (band 5-16)" % cadence)
	# 5% of height is generous: the pre-fix rig drew 4.6% and read as shuffling, and
	# SpikeFigure — the rig this one is a port of — sits at 15.1%.
	_expect(max_lift >= h * 0.10,
		"the swing foot visibly clears the floor: %.2f px = %.1f%% of height (min 10%%)"
				% [max_lift, 100.0 * max_lift / h])
	# The whole point of world-locked feet. The pre-fix rig drew 40.7% of height here.
	_expect(max_slide <= h * 0.05,
		"a foot bearing weight stays put: drew %.2f px = %.1f%% of height (max 5%%)"
				% [max_slide, 100.0 * max_slide / h])
	rig.free()
	_done["reads_as_a_stride"] = true


func _test_gait_steps_and_signals() -> void:
	var rig: Node2D = _make_rig()
	var counter := _PlantCounter.new()
	rig.connect("foot_planted", Callable(counter, "on_plant"))
	rig.call("play", 1)   # RUN
	_drive(rig, 2, 1.0 / 60.0, 0.0)
	_drive(rig, 180, 1.0 / 60.0, 180.0)   # 3 s of running
	rig.disconnect("foot_planted", Callable(counter, "on_plant"))
	# 180 px/s over 3 s = 540 px travelled. The exact count is pinned by
	# `_test_gait_reads_as_a_stride` above; all this one needs is that the signal fires
	# at all and keeps firing, which is what the footstep SFX and the dust puffs hang on.
	_expect(counter.count > 8, "running fires foot_planted repeatedly (%d plants)" % counter.count)

	# Standing still: no steps at all. The old sine gait marched on the spot forever.
	var idle := _PlantCounter.new()
	rig.call("play", 0)   # IDLE
	rig.connect("foot_planted", Callable(idle, "on_plant"))
	_drive(rig, 120, 1.0 / 60.0, 0.0)
	rig.disconnect("foot_planted", Callable(idle, "on_plant"))
	_expect(idle.count == 0, "a standing figure never steps (%d plants)" % idle.count)
	rig.free()
	_done["steps_and_signals"] = true


func _test_gait_disabled_when_airborne() -> void:
	var rig: Node2D = _make_rig()
	rig.call("play", 1)
	_drive(rig, 30, 1.0 / 60.0, 180.0)
	var air := _PlantCounter.new()
	rig.connect("foot_planted", Callable(air, "on_plant"))
	rig.call("set_grounded", false)
	rig.call("play", 8)   # State.AIR
	_drive(rig, 60, 1.0 / 60.0, 180.0)
	rig.disconnect("foot_planted", Callable(air, "on_plant"))
	_expect(air.count == 0, "airborne figure takes no steps (%d plants)" % air.count)
	_expect(not bool(rig.get("_gait_ready")), "airborne drops gait readiness so landing re-seeds")

	# Landing must re-seed the plants UNDER the body, not drag them back to takeoff.
	var takeoff_x: float = rig.position.x
	rig.position.x += 400.0
	rig.call("set_grounded", true)
	rig.call("play", 0)
	_drive(rig, 4, 1.0 / 60.0, 0.0)
	var plants: Array = rig.get("_plant_w")
	_expect(
		absf((plants[0] as Vector2).x - rig.position.x) < 30.0,
		"landing re-seeds plants under the body, not at takeoff (%.1f vs %.1f)"
				% [(plants[0] as Vector2).x, takeoff_x]
	)
	rig.free()
	_done["airborne"] = true


## The silhouette the spells test (spine segment + head circle) must still match what
## is DRAWN now that gear substitutes for body parts. Enemy.body_distance measures
## against pose head_center/r and neck->hip; if equipping a helmet moved or shrank
## either, "spells pass through heads" comes straight back.
func _test_gear_hitbox_contract() -> void:
	var rig: Node2D = _make_rig()
	_drive(rig, 3, 1.0 / 60.0, 0.0)
	var bare: Dictionary = rig.call("_compute_pose")
	var rig_consts: Dictionary = (load(RIG_PATH) as GDScript).get_script_constant_map()
	for kind: String in (rig_consts["HEAD_GEAR"] as Array):
		rig.call("set_equipment", "head", kind)
		var geared: Dictionary = rig.call("_compute_pose")
		_expect(
			(geared["head_center"] as Vector2).distance_to(bare["head_center"] as Vector2) < 0.001,
			"head gear '%s' does not move the head centre" % kind
		)
		_expect(
			is_equal_approx(float(geared["r"]), float(bare["r"])),
			"head gear '%s' does not change the head radius" % kind
		)
	rig.call("set_equipment", "head", "")
	for kind: String in (rig_consts["TORSO_GEAR"] as Array):
		rig.call("set_equipment", "body", kind)
		var g2: Dictionary = rig.call("_compute_pose")
		_expect(
			(g2["neck"] as Vector2).distance_to(bare["neck"] as Vector2) < 0.001
					and (g2["hip"] as Vector2).distance_to(bare["hip"] as Vector2) < 0.001,
			"torso gear '%s' does not displace the spine segment" % kind
		)
	rig.call("set_equipment", "body", "")
	rig.free()
	_done["gear_hitbox"] = true


## The texture registry is gone; GEAR_KINDS replaces it. Every kind must still carry
## an ability + label (the loadout UI reads those), and every enemy archetype weapon
## must name a kind the rig can actually draw.
func _test_gear_registry() -> void:
	var rig_consts: Dictionary = (load(RIG_PATH) as GDScript).get_script_constant_map()
	_expect(not rig_consts.has("EQUIP_TEX"), "the pixel-overlay registry is gone")
	var kinds: Array = rig_consts["GEAR_KINDS"]
	_expect(kinds.size() > 0, "GEAR_KINDS is populated")
	for kind: String in kinds:
		_expect(GearAbilities.has_ability(kind), "ability defined for '%s'" % kind)
		_expect(GearAbilities.label(kind) != "", "label non-empty for '%s'" % kind)
	# Clothing the maker asked to remove must no longer be a drawable piece.
	_expect(not kinds.has("cape"), "'cape' dropped — an accessory is not a body part")
	var enemy_consts: Dictionary = (load("res://scripts/combat/Enemy.gd") as GDScript).get_script_constant_map()
	for arch: int in (enemy_consts["ARCHETYPE_GEAR"] as Dictionary):
		var wk: String = (enemy_consts["ARCHETYPE_GEAR"] as Dictionary)[arch]
		_expect(kinds.has(wk), "archetype %d gear '%s' is a drawable kind" % [arch, wk])
	_done["gear_registry"] = true


## Smoke the whole public surface the rest of the codebase calls. Cheap, but this rig
## is the hero AND every enemy AND the Boss, so a missing method is a total outage.
func _test_public_surface() -> void:
	var rig: Node2D = _make_rig()
	var calls: Array = [
		["play", [1]], ["set_facing", [Vector2.LEFT]], ["set_facing", [Vector2.RIGHT]],
		["set_tint", [Color.RED]], ["flash", [0.05]], ["flash_color", [Color.BLUE, 0.05]],
		["set_aim", [Vector2.RIGHT]], ["set_aim_arm", [true]],
		["cast_gesture", [1, 0.6, 0]], ["set_equipment", ["weapon", "sword"]],
		["class_preset", ["mage"]], ["set_aura", [Color.CYAN, 1.0]], ["set_aura_tier", [3]],
		["set_airborne", [0.5]], ["set_grounded", [true]], ["set_air_phase", [true, false]],
		["set_body_velocity", [Vector2(180.0, 0.0)]], ["set_frozen", [false]],
		["set_hand_fire", [0.5, 0]], ["set_parry", [Vector2.RIGHT, 0.2]],
		["set_limp", [0.3]], ["flop", [0.7, 0.18]],
		["apply_impulse", [Vector2.RIGHT, 500.0]], ["clash_recoil", [Vector2.LEFT, 1.0]],
		["is_striking", []], ["get_weapon_tip", []], ["get_lead_hand_global", []],
	]
	for entry: Array in calls:
		var method: String = entry[0]
		_expect(rig.has_method(method), "rig exposes %s()" % method)
		if rig.has_method(method):
			rig.callv(method, entry[1])
	# Every class preset must survive a draw-pose computation with its gear on.
	for preset: String in ["mage", "rogue", "summoner", "brawler", "juggernaut",
			"cleric", "cryomancer", "stormcaller", "warlock"]:
		rig.call("class_preset", preset)
		rig.call("advance", 1.0 / 60.0)
		var pose: Dictionary = rig.call("_compute_pose")
		_expect(pose.has("head_center") and pose.has("w"), "preset '%s' computes a pose" % preset)
	_expect(float(rig.get("height")) > 0.0, "height is readable")
	rig.free()
	_done["public_surface"] = true


class _PlantCounter:
	extends RefCounted
	var count: int = 0

	func on_plant() -> void:
		count += 1


## ⚠ A PLANTED FOOT MUST BE SOMEWHERE THE LEG CAN ACTUALLY REACH.
##
## Maker, looking at a walk capture: "why are their legs lagging in that weird way".
## It was arithmetic. A support foot is ON THE FLOOR, so the leg spends its whole
## standing length (LEG_LEN_FACTOR) covering the hip height before any of it is
## available for trailing behind. The stride dip buys back at most
## MAX_STRIDE_DIP_FACTOR. What is left is the horizontal ceiling:
##
##     sqrt(rest^2 - (rest - dip)^2)
##
## `MAX_TRAIL_FACTOR` was AUTHORED at 0.34 against a ceiling of 0.222, so at run
## speed the leash held a foot down half again further than the leg could span. The
## IK then straightens the leg and points it at a plant it cannot touch — a rigid
## limb raked out behind the body. It is now DERIVED from the same three numbers.
##
## This asserts the RELATION, not the value: retune the leg, the stand height or the
## dip and the ceiling moves with them, and nothing here has to be edited.
func _test_a_planted_foot_can_reach_the_ground() -> void:
	var rig: Node2D = _make_rig()
	var RigT: GDScript = load(RIG_PATH) as GDScript
	var rest: float = float(RigT.get("LEG_LEN_FACTOR"))
	var dip: float = float(RigT.get("MAX_STRIDE_DIP_FACTOR"))
	var ceiling: float = sqrt(maxf(rest * rest - (rest - dip) * (rest - dip), 0.0))
	_expect(ceiling > 0.0, "the leg has SOME horizontal budget with a foot down")
	_expect(float(RigT.get("MAX_TRAIL_FACTOR")) <= ceiling + 0.0001,
		"the trail leash (%.3f) is inside what the leg can span (%.3f)"
			% [float(RigT.get("MAX_TRAIL_FACTOR")), ceiling])
	_expect(float(RigT.get("STEP_TRIGGER_FACTOR")) <= ceiling + 0.0001,
		"...and so is the step trigger (%.3f)" % float(RigT.get("STEP_TRIGGER_FACTOR")))
	# MEASURED, not just declared: run the thing and watch every support plant.
	var h: float = float(rig.get("height"))
	rig.call("play", 1)   # State.RUN
	_drive(rig, 20, 1.0 / 60.0, 180.0)
	var worst: float = 0.0
	var samples: int = 0
	for i: int in 90:
		_drive(rig, 1, 1.0 / 60.0, 180.0)
		var swing: int = int(rig.get("_swing_foot"))
		var plants: Array = rig.get("_plant_w")
		for f: int in 2:
			if f == swing and float(rig.get("_swing_t")) < 1.0:
				continue   # a lifted foot is allowed to be anywhere; its arc raises it
			worst = maxf(worst, absf((plants[f] as Vector2).x - rig.position.x))
			samples += 1
	# An invariant that is trivially true of an empty sample set is not an invariant.
	_expect(samples > 50, "actually sampled some support plants (got %d)" % samples)
	# ⚠ THE MEASURED BOUND IS THE STATIC CEILING PLUS A MID-SWING ALLOWANCE, and
	# the allowance is not fudge. The step trigger cannot fire while a foot is
	# already swinging (`_swing_t >= 1.0` gates it), so the support foot keeps
	# trailing for the rest of that swing. At Hero speed on a 31 px figure the rig is
	# genuinely AT its geometric limit — which this file already says out loud:
	# "Something with legs that short going that fast cannot take longer strides — it
	# runs out of leg". Demanding the static ceiling here would be demanding the
	# figure stop running.
	#
	# 1.25x still catches the bug this test was written for: with MAX_TRAIL_FACTOR
	# authored at 0.34 the worst trail was past this bound, and the CONSTANT check
	# above fails outright.
	var allow: float = h * ceiling * 1.25
	_expect(worst <= allow,
		"no support foot trailed absurdly past the leg's reach (worst %.2f px, allow %.2f)"
			% [worst, allow])
	rig.free()
	_done["foot_can_reach"] = true
