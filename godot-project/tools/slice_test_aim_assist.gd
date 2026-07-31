# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_aim_assist.gd
#
# AIM ASSIST — shipped at 0, and 0 has to be PROVABLY inert.
#
# The maker's no-auto-aim rule is LOCKED, with a regression test asserting the old
# `Targeting` helper stays deleted (`tools/slice0_test_targeting.gd`). The mobile spec
# asks for a soft-lock spectrum. Those are only compatible if the spectrum EXISTS but
# starts at zero and zero changes nothing — so "changes nothing" is the claim this
# suite is here to make unfalsifiable, not a comment somebody wrote once.
#
# WHAT MAKES THIS ASSIST AND NOT AUTO-AIM, in three assertions:
#   * at strength 0 the aim comes back byte-identical, and it comes back before a
#     single target has been looked at;
#   * a target OUTSIDE `ASSIST_MAX_DEGREES` is never acquired at ANY strength — a miss
#     by a mile stays a miss by a mile;
#   * the bend is capped, so the shot always goes roughly where you pointed.
# Raise `ASSIST_MAX_DEGREES` past a handful of degrees and the second assertion is the
# one that fires, which is exactly where it should.
#
# Also covers the FACTION rule: the assist scans hostiles, never `mortal`. Friendly
# fire means you CAN hit your team-mate; it must never mean the game steers you into
# one. Same asymmetry the melee auto-target follows.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion sentinel
# as its last line, so a test that aborts part-way fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"zero_is_inert",
	"bend_is_capped",
	"far_targets_are_never_acquired",
	"strength_scales_the_bend",
	"skips_the_caster",
	"hero_default_leaves_aim_untouched",
	"no_auto_aim_helper_came_back",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"


class Foe extends Node2D:
	func _ready() -> void:
		add_to_group("enemy")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_zero_is_inert()
	_test_bend_is_capped()
	_test_far_targets()
	_test_strength_scales()
	_test_skips_caster()
	_test_hero_default()
	_test_no_targeting_helper()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Aim-assist tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("Aim-assist tests: all PASS")
	quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _foe(at: Vector2) -> Foe:
	var f := Foe.new()
	root.add_child(f)
	f.global_position = at
	return f


# ------------------------------------------------------------- 1. THE PROMISE
## Zero strength returns the argument, unchanged, with a target sitting right next to
## the aim line — the exact case a working assist WOULD bend.
func _test_zero_is_inert() -> void:
	var from: Vector2 = Vector2(1000.0, 0.0)
	var foe: Foe = _foe(from + Vector2(400.0, 20.0))  # ~2.9 deg off — well inside the cone
	var aim: Vector2 = Vector2.RIGHT
	var out: Vector2 = SpellTargets.assist_aim(from, aim, [foe], 0.0)
	_expect(out == aim,
		"strength 0 returns the aim IDENTICALLY (got %s, expected %s)" % [out, aim])
	# A negative or malformed strength is the same inert path, not an inverted bend.
	_expect(SpellTargets.assist_aim(from, aim, [foe], -1.0) == aim,
		"a negative strength is inert too, never an aim pushed AWAY from the target")
	# ...and with a target list that is empty, at full strength, nothing happens either.
	_expect(SpellTargets.assist_aim(from, aim, [], 1.0) == aim,
		"nothing to assist toward -> the aim is untouched")
	foe.queue_free()
	_completes("zero_is_inert")


## The cap IS the distinction between assist and auto-aim. At full strength a target
## inside the cone is reached exactly; nothing beyond it ever is.
func _test_bend_is_capped() -> void:
	var from: Vector2 = Vector2(2000.0, 0.0)
	# Just inside the cone: a bend of about 3 degrees.
	var near_angle: float = deg_to_rad(SpellTargets.ASSIST_MAX_DEGREES * 0.5)
	var foe: Foe = _foe(from + Vector2.RIGHT.rotated(near_angle) * 400.0)
	var out: Vector2 = SpellTargets.assist_aim(from, Vector2.RIGHT, [foe], 1.0)
	var bent: float = absf(Vector2.RIGHT.angle_to(out))
	_expect(absf(bent - near_angle) < 0.01,
		"full strength lands the aim ON an in-cone target (bent %.2f deg, target %.2f)"
			% [rad_to_deg(bent), rad_to_deg(near_angle)])
	_expect(bent <= deg_to_rad(SpellTargets.ASSIST_MAX_DEGREES) + 0.001,
		"the bend never exceeds the %.1f deg ceiling" % SpellTargets.ASSIST_MAX_DEGREES)
	foe.queue_free()
	_completes("bend_is_capped")


## ⚠ THE ASSERTION THAT KEEPS THIS FROM BECOMING AUTO-AIM. A target you are plainly
## not pointing at is never acquired, at ANY strength — so a wild shot stays wild and
## the assist can only ever tidy up the last degree or two of a hurried thumb.
func _test_far_targets() -> void:
	var from: Vector2 = Vector2(3000.0, 0.0)
	var wide: Foe = _foe(from + Vector2.RIGHT.rotated(deg_to_rad(35.0)) * 400.0)
	for strength: float in [0.25, 0.5, 1.0]:
		_expect(SpellTargets.assist_aim(from, Vector2.RIGHT, [wide], strength) == Vector2.RIGHT,
			"a target 35 deg off the aim is NOT acquired at strength %.2f" % strength)
	# ...and neither is one inside the cone but past the look-ahead range: at that
	# distance it is a different plan, not the thing you were aiming at.
	var distant: Foe = _foe(from + Vector2(SpellTargets.ASSIST_RANGE + 200.0, 4.0))
	_expect(SpellTargets.assist_aim(from, Vector2.RIGHT, [distant], 1.0) == Vector2.RIGHT,
		"a target beyond ASSIST_RANGE is out of scope even when perfectly lined up")
	wide.queue_free()
	distant.queue_free()
	_completes("far_targets_are_never_acquired")


## The slider is a real spectrum, not an on/off snap: half strength bends half way.
func _test_strength_scales() -> void:
	var from: Vector2 = Vector2(4000.0, 0.0)
	var target_angle: float = deg_to_rad(SpellTargets.ASSIST_MAX_DEGREES * 0.6)
	var foe: Foe = _foe(from + Vector2.RIGHT.rotated(target_angle) * 400.0)
	var half: Vector2 = SpellTargets.assist_aim(from, Vector2.RIGHT, [foe], 0.5)
	var full: Vector2 = SpellTargets.assist_aim(from, Vector2.RIGHT, [foe], 1.0)
	var half_bend: float = absf(Vector2.RIGHT.angle_to(half))
	var full_bend: float = absf(Vector2.RIGHT.angle_to(full))
	_expect(half_bend > 0.0001, "half strength bends SOMETHING")
	_expect(half_bend < full_bend, "half strength bends less than full")
	_expect(absf(half_bend - full_bend * 0.5) < 0.01,
		"half strength bends about half as far (%.2f vs %.2f deg)"
			% [rad_to_deg(half_bend), rad_to_deg(full_bend)])
	foe.queue_free()
	_completes("strength_scales_the_bend")


## The caster is in its own hostile group the moment two heroes are on opposite
## factions, and a spell that bent its aim onto its own thrower would be absurd.
func _test_skips_caster() -> void:
	var from: Vector2 = Vector2(5000.0, 0.0)
	var me: Foe = _foe(from + Vector2(2.0, 1.0))  # basically on top of the muzzle
	var real: Foe = _foe(from + Vector2(400.0, 15.0))
	var out: Vector2 = SpellTargets.assist_aim(from, Vector2.RIGHT, [me, real], 1.0, [me])
	var toward_real: Vector2 = (real.global_position - from).normalized()
	_expect(out.is_equal_approx(toward_real),
		"the skip list is honoured — the assist reached the real target, not the caster")
	me.queue_free()
	real.queue_free()
	_completes("skips_the_caster")


# ------------------------------------------------------ 6+7. the shipped state
## END TO END: a real Hero with the shipping settings resolves the SAME aim it would
## have resolved without any of this code. Headless has no Tuning autoload, so
## `assist_strength` answers 0.0 — which is itself the fallback that has to hold, since
## it is also what an older `data/tuning.tres` with no `aim_assist` field produces.
func _test_hero_default() -> void:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.set_physics_process(false)
	hero.global_position = Vector2(6000.0, 0.0)
	_expect(is_equal_approx(SpellTargets.assist_strength(hero), 0.0),
		"the shipped assist strength is 0 (no Tuning field / no autoload -> inert)")
	var foe: Foe = _foe(hero.global_position + Vector2(300.0, 12.0))
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.call("_apply_aim_assist")
	_expect((hero.get("_aim_dir") as Vector2) == Vector2.RIGHT,
		"a hero at the shipping default aims EXACTLY where it was pointed")
	foe.queue_free()
	hero.queue_free()
	_completes("hero_default_leaves_aim_untouched")


## Belt-and-braces against the locked rule, checked from this side too: the deleted
## auto-aim helper must not have crept back in under cover of the assist work.
## `slice0_test_targeting.gd` owns this assertion; duplicating the cheap half here
## means the aim-assist suite itself fails if the assist ever grows into a lock.
func _test_no_targeting_helper() -> void:
	_expect(not FileAccess.file_exists("res://scripts/combat/Targeting.gd"),
		"the deleted auto-aim helper has NOT come back as part of the assist work")
	_expect(not ClassDB.class_exists("Targeting"),
		"...and nothing has re-registered it as a global class")
	_completes("no_auto_aim_helper_came_back")
