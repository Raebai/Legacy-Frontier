# A HERO IS A BODY, NOT A POINT — and it agrees with an Enemy about what a body is.
#
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless \
#       --script tools/slice_test_hit_silhouette.gd
#
# `SpellTargets` picks who a blast hits by duck-typing a silhouette:
#
#     has_method("body_distance") -> measured against the DRAWN body
#     has_method("hit_margin")    -> that target's own forgiveness ring
#     ...otherwise                -> a point test on global_position, margin ZERO
#
# `Enemy`, `Boss` and `SpikeFigure` implemented it. `Hero` DID NOT, so every hero in
# the game — both bot duellists and the human player — was a dimensionless dot at
# hip height to every spell. Maker: "the stick figures will be sntading in the
# borders of the spell and it wont register".
#
# ⚠ THE SECOND TEST IS THE ONE THAT MATTERS LONGEST. Two independent silhouette
# implementations is exactly how "spells pass through heads" happened the first
# time, and this file now has two again (Hero's and Enemy's). So they are pinned
# against each other numerically: if either drifts, this goes red rather than one
# actor type quietly becoming harder to hit than the other.
extends SceneTree

const RIG_SCRIPT: String = "res://scripts/combat/CharacterRig.gd"

var _fails: int = 0
var _completed: Array[String] = []


func _initialize() -> void:
	# ⚠ AWAIT A FRAME BEFORE MEASURING ANYTHING. `@onready var rig` is assigned just
	# before `_ready()`, and `_initialize()` runs before the tree has processed a
	# single frame — so without this every body reports NO RIG, both actor types fall
	# back to the origin point test, and the "they agree" check below passes because
	# both are equally wrong. That is a vacuous pass of the exact kind this suite is
	# supposed to catch, and it is what the first run of this file actually did.
	await process_frame
	await process_frame
	_hero_implements_the_contract()
	_hero_and_enemy_agree()
	_the_rim_now_registers()
	_margin_factors_have_not_drifted()

	var expected: int = 4
	if _completed.size() != expected:
		print("hit-silhouette tests: FAIL — %d/%d reached their end (%s)"
			% [_completed.size(), expected, ", ".join(_completed)])
		quit(1)
		return
	if _fails > 0:
		print("hit-silhouette tests: %d FAILED" % _fails)
		quit(1)
		return
	print("hit-silhouette tests: all PASS")
	quit(0)


func _make(scene_path: String) -> Node2D:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var n: Node2D = packed.instantiate() as Node2D
	if n == null:
		return null
	root.add_child(n)
	n.global_position = Vector2.ZERO
	return n


func _hero_implements_the_contract() -> void:
	var h: Node2D = _make("res://scenes/combat/Hero.tscn")
	if h == null:
		print("  FAIL contract: could not instantiate Hero.tscn")
		_fails += 1
		_completed.append("hero_implements_the_contract")
		return
	for m: String in ["body_distance", "hit_margin", "head_point"]:
		if not h.has_method(m):
			print("  FAIL contract: Hero has no %s() — SpellTargets will fall back "
				% m + "to a ZERO-SIZE point test")
			_fails += 1
	if h.has_method("hit_margin"):
		var margin: float = float(h.call("hit_margin"))
		print("  hero hit_margin = %.2f px" % margin)
		if margin <= 0.0:
			print("  FAIL contract: hero forgiveness ring is %.3f" % margin)
			_fails += 1
	h.queue_free()
	_completed.append("hero_implements_the_contract")


## The same query, on both actor types, at the same place. They must not disagree.
func _hero_and_enemy_agree() -> void:
	var h: Node2D = _make("res://scenes/combat/Hero.tscn")
	var e: Node2D = _make("res://scenes/combat/Enemy.tscn")
	if h == null or e == null:
		print("  FAIL agree: could not instantiate both (hero=%s enemy=%s)"
			% [h != null, e != null])
		_fails += 1
		_completed.append("hero_and_enemy_agree")
		return
	# ⚠ OFF-AXIS ON PURPOSE. The spine is a VERTICAL segment at x = 0, so any probe
	# on that axis sits exactly on it and returns 0.0 — which tells you nothing about
	# whether a silhouette is being used at all. Standing beside the chest makes the
	# silhouette answer (~horizontal reach to the spine) and the origin-point answer
	# (the hypotenuse) clearly different numbers.
	var probe := Vector2(7.0, -10.0)
	var hd: float = float(h.call("body_distance", probe))
	var ed: float = float(e.call("body_distance", probe))
	# ⚠ PROVE THE SILHOUETTE IS LIVE BEFORE COMPARING. If neither body has a rig,
	# both return the plain origin distance and match perfectly while measuring
	# nothing. Refuse to call that agreement.
	var origin_d: float = probe.length()
	if absf(hd - origin_d) < 0.001 and absf(ed - origin_d) < 0.001:
		print("  FAIL agree: both bodies returned the ORIGIN-POINT distance "
			+ "(%.3f) — no rig was built, so this comparison is vacuous" % origin_d)
		_fails += 1
	var hm: float = float(h.call("hit_margin"))
	var em: float = float(e.call("hit_margin"))
	print("  at %s: hero d=%.3f m=%.3f | enemy d=%.3f m=%.3f" % [probe, hd, hm, ed, em])
	if absf(hd - ed) > 0.51:
		print("  FAIL agree: silhouette distances differ by %.3f px" % absf(hd - ed))
		_fails += 1
	if absf(hm - em) > 0.01:
		print("  FAIL agree: forgiveness rings differ by %.3f px" % absf(hm - em))
		_fails += 1
	h.queue_free()
	e.queue_free()
	_completed.append("hero_and_enemy_agree")


## THE REPORTED BUG, as a number. A point out at the edge of a hero's drawn body is
## inside the blast; under the old point-only test it was not.
func _the_rim_now_registers() -> void:
	var h: Node2D = _make("res://scenes/combat/Hero.tscn")
	if h == null:
		print("  FAIL rim: could not instantiate Hero.tscn")
		_fails += 1
		_completed.append("the_rim_now_registers")
		return
	var rig_h: float = load(RIG_SCRIPT).get("DEFAULT_HEIGHT")
	var m: float = float(h.call("hit_margin"))
	# A blast whose edge stops just BESIDE the hero's chest — the "standing in the
	# border of the spell" case, off-axis so it is a real silhouette query.
	var chest := Vector2(m * 0.85, -rig_h * 0.28)
	var d: float = float(h.call("body_distance", chest))
	var old_point_d: float = (h as Node2D).global_position.distance_to(chest)
	print("  chest-side probe %s: silhouette d=%.2f (margin %.2f) vs origin-point d=%.2f"
		% [chest, d, m, old_point_d])
	if d > m:
		print("  FAIL rim: a point beside the chest is still outside the hit shape")
		_fails += 1
	# ⚠ AND THE FAULT MUST BE REAL, or this asserts nothing. The OLD point test put
	# this same spot far outside any blast that was touching the body.
	if old_point_d <= m:
		print("  FAIL rim: the origin-point distance (%.2f) is already inside the "
			% old_point_d + "margin (%.2f) — this probe cannot show the fault" % m)
		_fails += 1
	else:
		print("  the old point test measured it %.1fx further out" % (old_point_d / maxf(d, 0.01)))
	h.queue_free()
	_completed.append("the_rim_now_registers")


## The canonical margin now lives on CharacterRig. Enemy still holds its own copy.
func _margin_factors_have_not_drifted() -> void:
	var rig: GDScript = load(RIG_SCRIPT) as GDScript
	var enemy: GDScript = load("res://scripts/combat/Enemy.gd") as GDScript
	if rig == null or enemy == null:
		print("  FAIL drift: could not load the two scripts")
		_fails += 1
		_completed.append("margin_factors_have_not_drifted")
		return
	var a: float = float(rig.get("HIT_MARGIN_FACTOR"))
	var b: float = float(enemy.get("HIT_MARGIN_FACTOR"))
	print("  margin factor: CharacterRig %.4f | Enemy %.4f" % [a, b])
	if absf(a - b) > 0.0001:
		print("  FAIL drift: the two forgiveness factors have diverged")
		_fails += 1
	_completed.append("margin_factors_have_not_drifted")
