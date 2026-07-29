# Run: godot --headless --path godot-project --script tools/slice0_test_targeting.gd
#
# This suite USED to prove the auto-aim helper worked. The design rule is now the
# opposite: no auto-aim and no homing on any player spell — you point, you throw,
# and hitting is your skill exactly as dodging is theirs. So the file keeps its
# name (every checklist in docs/ runs it by path) and inverts its job: it is the
# guard that stops aim assist being reintroduced.
#
# `Targeting` was the whole helper — nearest() / aim_direction() / assisted_aim().
# Nothing outside Hero and these suites ever called it, so it was deleted rather
# than left lying around as a one-import-away trap. Enemies were never customers:
# they have their own Enemy._nearest_hero(), and the rule is about the PLAYER —
# an enemy that could not find you would just be broken.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"helper_is_gone",
	"hero_has_no_aim_assist",
	"enemies_keep_their_own_targeting",
]

var _fails: int = 0
var _completed: Dictionary = {}

const TARGETING_PATH: String = "res://scripts/combat/Targeting.gd"
const HERO_PATH: String = "res://scripts/combat/Hero.gd"
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"

## Every name the deleted helper exposed. Any of these reappearing in Hero means
## the player is being aimed for again.
const BANNED_IN_HERO: Array[String] = ["Targeting", "assisted_aim", "aim_direction"]


func _init() -> void:
	_test_helper_is_gone()
	_test_hero_has_no_aim_assist()
	_test_enemies_keep_their_own_targeting()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice0 no-auto-aim tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice0 no-auto-aim tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Read a script's source text. Reading the FILE (not the parsed class) is the
## point: a call site can only be checked structurally, and a dead helper that
## still exists on disk is exactly the trap this suite exists to catch.
func _source(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _test_helper_is_gone() -> void:
	_expect(
		not ResourceLoader.exists(TARGETING_PATH),
		"the Targeting auto-aim helper is deleted, not merely unused")
	_completes("helper_is_gone")


func _test_hero_has_no_aim_assist() -> void:
	var src: String = _source(HERO_PATH)
	_expect(src != "", "Hero.gd is readable")
	for name: String in BANNED_IN_HERO:
		# Comments in this repo are dense enough that a bare word could appear in
		# prose, so match the CALL shape ("name(") rather than the word.
		_expect(
			not src.contains(name + "("),
			"Hero calls no aim-assist helper: %s(" % name)
	_completes("hero_has_no_aim_assist")


## The no-auto-aim rule constrains the PLAYER, not the AI. If this ever fails,
## someone deleted an enemy's ability to find its target while cleaning up aim
## assist — which is a bug, not a design win.
func _test_enemies_keep_their_own_targeting() -> void:
	var src: String = _source(ENEMY_PATH)
	_expect(
		src.contains("func _nearest_hero"),
		"enemies still own their targeting (the rule is about the player)")
	_completes("enemies_keep_their_own_targeting")
