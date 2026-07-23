# Run: godot --headless --path godot-project --script tools/slice_test_movement.gd
# Task 3 (weighty movement): asserts the five live TuningConfig knobs
# (move_gravity_rise/fall, move_jump_velocity, move_air_accel, move_max_fall)
# exist with the new "committed jump, low air control" defaults, that Hero.gd
# actually reads them through the existing _tune() live-tuning mechanism
# (not just that TuningConfig declares them), and that the resulting jump arc
# + air control read as WEIGHT rather than float.
#
# Note: Hero.gd references autoloads (Sfx, Targeting) so the hero scene is
# load()ed at runtime on the first _process frame, never preload()ed (repo
# test-trap idiom — see slice1_test_blink.gd / slice2_test_rogue.gd).
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const TUNING_CONFIG_PATH: String = "res://scripts/combat/TuningConfig.gd"
const TICK: float = 1.0 / 60.0  # one physics frame at 60fps

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_tuning_knobs_exist_with_new_defaults()
	failed += _test_hero_reads_tuning_knobs_live()
	failed += _test_jump_apex_matches_gravity_jump_formula()
	failed += _test_air_control_cannot_reach_full_speed_quickly()
	if failed > 0:
		printerr("movement tests: %d FAILED" % failed)
		quit(1)
	else:
		print("movement tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_hero() -> CharacterBody2D:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)  # freed with root at exit
	hero.set_physics_process(false)  # isolate — drive physics by hand, one tick at a time
	hero.global_position = Vector2(20000.0, 20000.0)  # open space, far from any geometry
	return hero


## (a) The five knobs exist on TuningConfig with the exact new "weighty" targets.
func _test_tuning_knobs_exist_with_new_defaults() -> int:
	var failed: int = 0
	var cfg: Resource = load(TUNING_CONFIG_PATH).new()
	failed += _expect(is_equal_approx(float(cfg.move_gravity_rise), 2600.0), "move_gravity_rise defaults to 2600")
	failed += _expect(is_equal_approx(float(cfg.move_gravity_fall), 3000.0), "move_gravity_fall defaults to 3000")
	failed += _expect(is_equal_approx(float(cfg.move_jump_velocity), -740.0), "move_jump_velocity defaults to -740")
	failed += _expect(is_equal_approx(float(cfg.move_air_accel), 750.0), "move_air_accel defaults to 750")
	failed += _expect(is_equal_approx(float(cfg.move_max_fall), 1400.0), "move_max_fall defaults to 1400")
	return failed


## (b) Hero.gd's own _tune() read (the exact mechanism _physics_process uses)
## resolves to the new knobs, not the old floaty hardcoded consts. This is the
## load-bearing check that Hero is actually WIRED to TuningConfig, not just
## that TuningConfig happens to declare the fields.
func _test_hero_reads_tuning_knobs_live() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	failed += _expect(
		is_equal_approx(hero._tune("move_gravity_rise", hero.GRAVITY), 2600.0),
		"hero._tune reads move_gravity_rise = 2600 (old const GRAVITY was 1500)"
	)
	failed += _expect(
		is_equal_approx(hero._tune("move_gravity_fall", hero.GRAVITY_FALL), 3000.0),
		"hero._tune reads move_gravity_fall = 3000 (old const GRAVITY_FALL was 2100)"
	)
	failed += _expect(
		is_equal_approx(hero._tune("move_jump_velocity", hero.JUMP_VELOCITY), -740.0),
		"hero._tune reads move_jump_velocity = -740 (old const JUMP_VELOCITY was -580)"
	)
	failed += _expect(
		is_equal_approx(hero._tune("move_air_accel", hero.AIR_ACCEL), 750.0),
		"hero._tune reads move_air_accel = 750 (old const AIR_ACCEL was 1450)"
	)
	failed += _expect(
		is_equal_approx(hero._tune("move_max_fall", hero.MAX_FALL), 1400.0),
		"hero._tune reads move_max_fall = 1400 (old const MAX_FALL was 1000)"
	)
	return failed


## (c) Fire a real jump through Hero's actual _physics_process (buffered-jump
## path at ~Hero.gd:568-573) and step real physics ticks — no floor nearby, so
## is_on_floor() stays false and gravity/jump integrate as free flight, exactly
## isolating the rise-gravity/jump-velocity formula. Apex time should land at
## |jump_velocity| / gravity_rise = 740/2600 ~= 0.285s (a COMMITTED hop, not
## the old floaty ~0.39s apex from GRAVITY=1500/JUMP_VELOCITY=-580).
func _test_jump_apex_matches_gravity_jump_formula() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.velocity = Vector2.ZERO
	# Force the buffered-jump branch to fire on the very next tick without
	# needing a real floor collider or an injected key event (mirrors how
	# other Hero tests poke private timers directly, e.g. slice1_test_blink.gd).
	hero._jump_buffer = 0.2
	hero._coyote = 0.2

	hero._physics_process(TICK)
	failed += _expect(
		is_equal_approx(hero.velocity.y, -740.0),
		"jump fires at move_jump_velocity (-740), got %.1f" % hero.velocity.y
	)

	var elapsed: float = TICK
	var ticks: int = 0
	while hero.velocity.y < 0.0 and ticks < 200:
		hero._physics_process(TICK)
		elapsed += TICK
		ticks += 1
	failed += _expect(ticks < 200, "jump apex reached within a sane number of ticks (didn't hang)")

	var jump_v: float = hero._tune("move_jump_velocity", hero.JUMP_VELOCITY)
	var g_rise: float = hero._tune("move_gravity_rise", hero.GRAVITY)
	var expected_apex: float = absf(jump_v) / g_rise  # ~0.28461s with the new defaults

	failed += _expect(
		absf(expected_apex - 0.28) <= 0.06,
		"target apex time %.3fs is in the committed-hop band 0.28s +-0.06" % expected_apex
	)
	failed += _expect(
		absf(elapsed - expected_apex) <= TICK * 2.0,
		"measured apex time %.3fs (over %d ticks) matches the gravity/jump-velocity formula %.3fs"
		% [elapsed, ticks + 1, expected_apex]
	)
	# The OLD floaty apex (580/1500 ~= 0.387s) must no longer be what we measure —
	# proves the rewire actually changed feel, not just added dead knobs.
	failed += _expect(elapsed < 0.35, "new apex (%.3fs) is meaningfully snappier than the old floaty ~0.387s" % elapsed)
	return failed


## (d) At the new low move_air_accel (750, was 1450), holding a mid-air
## directional input for a short window (0.1s, ~6 ticks) must NOT be able to
## steer velocity.x anywhere near full ground run speed — that's the "reduced
## air control, no free-steer" half of the weight fix. Verified two ways:
## the actual simulated velocity, and the closed-form reachable delta
## (air_accel * time) so the assertion doesn't depend on move_toward's
## exact overshoot handling.
func _test_air_control_cannot_reach_full_speed_quickly() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	hero.velocity = Vector2(0.0, 50.0)  # already airborne/falling, not on any floor
	Input.action_press("move_right")

	var window: float = 0.1  # ~6 ticks at 60fps
	var elapsed: float = 0.0
	while elapsed < window:
		hero._physics_process(TICK)
		elapsed += TICK
	Input.action_release("move_right")

	var spd: float = hero._tune("hero_speed", hero.SPEED)
	var air_accel: float = hero._tune("move_air_accel", hero.AIR_ACCEL)
	var reachable: float = air_accel * elapsed  # closed-form max |delta v| via move_toward

	failed += _expect(
		reachable < spd,
		"closed-form air-accel reach (%.1f px/s over %.3fs) stays below full run speed (%.1f) — proves low air_accel, not just a low read"
		% [reachable, elapsed, spd]
	)
	failed += _expect(
		hero.velocity.x < spd * 0.6,
		"simulated mid-air velocity.x (%.1f) can't reach full run speed (%.1f) within %.2fs — no free-steer"
		% [hero.velocity.x, spd, window]
	)
	failed += _expect(hero.velocity.x > 0.0, "air control still nudges velocity toward the held direction (not zero)")
	return failed
