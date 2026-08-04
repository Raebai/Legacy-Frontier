# Run: godot --headless --path godot-project --script tools/slice_test_enemy_silhouette.gd
#
# Guards the "spells pass through heads without registering" fix. Enemy.tscn ships
# a 20x20 movement collider on the origin while the rig it DRAWS is 31 px tall and
# centred on that same origin, so the top half of the head circle had nothing solid
# behind it and every point-radius spell test aimed at a point ~10 px below the head
# (x1.9 on the SpellPlayground sparring dummies).
#
# The negative cases here matter as much as the positive ones: this fix must make an
# enemy as tall as it is DRAWN, never wider or more generous than that, so a stealth
# hitbox inflation cannot pass this suite.
#
# No stepped physics in a --script harness, so nothing here relies on real overlap:
# every assertion drives the directly-callable geometry seams (body_distance /
# head_point / hit_margin) and inspects the hurtbox shapes as data.
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
	"the_old_gap_is_real",
	"head_height_registers",
	"body_height_registers",
	"outside_the_silhouette_misses",
	"scale_awareness",
	"hurtbox_covers_the_drawn_figure",
	"hurtbox_is_not_wider_than_before",
	"boss_inherits_the_silhouette",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ENEMY_SCRIPT_PATH: String = "res://scripts/combat/Enemy.gd"
const BOSS_SCRIPT_PATH: String = "res://scripts/combat/Boss.gd"
const RigScript: GDScript = preload("res://scripts/combat/CharacterRig.gd")

## The shipped Enemy.tscn movement collider — the thing that was too short.
const SCENE_BODY_BOX: Vector2 = Vector2(20, 20)
## Rig geometry the fix mirrors (CharacterRig._compute_pose): head r = h * 0.18,
## head centre = -h/2 + r, hip = h * 0.1, feet = hip + h * 0.4.
const RIG_H: float = 31.0
const DUMMY_SCALE: float = 1.9  # SpellPlaygroundController sets this on its dummies

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_the_old_gap_is_real()
	_test_head_height_registers()
	_test_body_height_registers()
	_test_outside_the_silhouette_misses()
	_test_scale_awareness()
	_test_hurtbox_covers_the_drawn_figure()
	_test_hurtbox_is_not_wider_than_before()
	_test_boss_inherits_the_silhouette()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Enemy silhouette tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Enemy silhouette tests: all PASS")
		quit(0)
	return true


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


func _consts() -> Dictionary:
	return (load(ENEMY_SCRIPT_PATH) as GDScript).get_script_constant_map()


## Builds an Enemy the way Enemy.tscn does — Rig child + the 20x20 movement
## collider — so the hurtbox reads the same width the shipped scene would give it.
func _setup(node_scale: float = 1.0, script_path: String = ENEMY_SCRIPT_PATH) -> Dictionary:
	var arena := Node2D.new()
	root.add_child(arena)
	var enemy: CharacterBody2D = (load(script_path) as GDScript).new()
	enemy.collision_layer = 4
	var rig: CharacterRig = RigScript.new()
	rig.name = "Rig"
	enemy.add_child(rig)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = SCENE_BODY_BOX
	shape.shape = rect
	enemy.add_child(shape)
	arena.add_child(enemy)
	enemy.global_position = Vector2.ZERO
	enemy.scale = Vector2(node_scale, node_scale)
	enemy.set_physics_process(false)
	# _ready defers the re-cut (subclasses resize the rig after super._ready);
	# do it by hand here rather than pumping frames in a --script harness.
	enemy.call("refresh_hurtbox")
	return {"arena": arena, "enemy": enemy, "rig": rig}


func _teardown(ctx: Dictionary) -> void:
	var arena: Node2D = ctx["arena"]
	root.remove_child(arena)
	arena.free()


func _hurtbox_shapes(enemy: Node) -> Dictionary:
	var hb := enemy.get_node_or_null("Hurtbox") as Area2D
	if hb == null:
		return {}
	return {
		"area": hb,
		"head": hb.get_node_or_null("HurtHead") as CollisionShape2D,
		"body": hb.get_node_or_null("HurtBody") as CollisionShape2D,
	}


## THE ROOT CAUSE, asserted numerically so it can never quietly come back: the
## drawn head reaches HIGHER than the old movement collider's top edge, and the
## drawn feet reach LOWER than its bottom edge. Those two bands were the dead
## zones a bolt flew through.
func _test_the_old_gap_is_real() -> void:
	var c: Dictionary = _consts()
	var head_r: float = RIG_H * float(c["RIG_HEAD_R_FACTOR"])
	var head_top: float = -RIG_H * 0.5
	var feet_y: float = RIG_H * float(c["RIG_HIP_Y_FACTOR"]) + RIG_H * float(c["RIG_LEG_LEN_FACTOR"])
	var old_top: float = -SCENE_BODY_BOX.y * 0.5
	var old_bottom: float = SCENE_BODY_BOX.y * 0.5
	_expect(
		head_top < old_top,
		"the drawn head top (%.2f) sat ABOVE the old 20x20 collider top (%.2f)" % [head_top, old_top]
	)
	# How much of the head had no collider behind it, as a fraction of its diameter.
	var uncovered: float = (old_top - head_top) / (head_r * 2.0)
	_expect(
		uncovered > 0.4,
		"about half the head was unhittable (uncovered fraction %.2f)" % uncovered
	)
	_expect(
		feet_y > old_bottom,
		"the drawn feet (%.2f) reached BELOW the old collider bottom (%.2f)" % [feet_y, old_bottom]
	)
	_completes("the_old_gap_is_real")


## A hit aimed at HEAD height registers: dead centre is well inside, and the very
## top of the skull is on the surface (distance ~0), comfortably inside the margin.
func _test_head_height_registers() -> void:
	var ctx: Dictionary = _setup()
	var enemy: Node = ctx["enemy"]
	var head: Vector2 = enemy.call("head_point")
	var margin: float = enemy.call("hit_margin")
	var c: Dictionary = _consts()
	var head_r: float = RIG_H * float(c["RIG_HEAD_R_FACTOR"])

	_expect(
		head.y < -RIG_H * 0.25,
		"head_point sits well above the body origin (y=%.2f)" % head.y
	)
	_expect(
		float(enemy.call("body_distance", head)) <= 0.0,
		"a hit dead-centre on the head is INSIDE the silhouette"
	)
	var skull_top := Vector2(head.x, head.y - head_r)
	_expect(
		float(enemy.call("body_distance", skull_top)) <= margin,
		"a hit at the very top of the skull registers (d=%.2f, margin=%.2f)"
			% [float(enemy.call("body_distance", skull_top)), margin]
	)
	# The exact band the old collider missed: 1 px above its top edge, head height.
	var old_dead_zone := Vector2(0.0, -SCENE_BODY_BOX.y * 0.5 - 1.0)
	_expect(
		float(enemy.call("body_distance", old_dead_zone)) <= margin,
		"the old dead zone just above the 20x20 box now registers"
	)
	_teardown(ctx)
	_completes("head_height_registers")


## A hit at BODY height still registers — the spine segment, not just the head.
func _test_body_height_registers() -> void:
	var ctx: Dictionary = _setup()
	var enemy: Node = ctx["enemy"]
	var margin: float = enemy.call("hit_margin")
	# ⚠ THE PROBES FOLLOW THE FIGURE. `y` is measured from the body origin, and the
	# drawn spine sits `rig.position.y` above it now: `CharacterRig` aligns its FEET to
	# the bottom edge of the parent's collider, which is the fix for legs that were
	# permanently folded (a 20-tall box under a 31-tall rig was asking the figure to
	# stand 5.5 px underground). Read off the live rig rather than written as -5.5, so
	# a resized collider moves the probe and the body together.
	var rig_dy: float = (enemy.get_node(^"Rig") as Node2D).position.y
	for y: float in [-2.0, 0.0, 2.0]:
		_expect(
			float(enemy.call("body_distance", Vector2(0.0, y + rig_dy))) <= margin,
			"a hit on the spine at y=%.1f registers" % y
		)
	_teardown(ctx)
	_completes("body_height_registers")


## THE IMPORTANT ONE. Points clearly off the drawn figure must NOT register, or
## this "fix" is just a bigger hitbox wearing a silhouette costume.
func _test_outside_the_silhouette_misses() -> void:
	var ctx: Dictionary = _setup()
	var enemy: Node = ctx["enemy"]
	var margin: float = enemy.call("hit_margin")
	var misses: Dictionary = {
		"a spell sailing over the head": Vector2(0.0, -RIG_H),
		"a spell passing under the feet": Vector2(0.0, RIG_H),
		"a spell going wide at head height": Vector2(40.0, -RIG_H * 0.32),
		"a spell going wide at chest height": Vector2(40.0, 0.0),
		"a spell that misses on the diagonal": Vector2(-30.0, -30.0),
	}
	for label: String in misses:
		var d: float = enemy.call("body_distance", misses[label])
		_expect(d > margin, "%s does NOT register (d=%.2f, margin=%.2f)" % [label, d, margin])
	# ...and the arms/legs are deliberately excluded: a point out at arm's length
	# on the horizontal is a miss, exactly as it is for the player figure.
	_expect(
		float(enemy.call("body_distance", Vector2(RIG_H * 0.32, 0.0))) > margin,
		"a flailing limb does not catch hits (spine + head only, same as SpikeFigure)"
	)
	_teardown(ctx)
	_completes("outside_the_silhouette_misses")


## The SpellPlayground dummies are scale 1.9. Everything must scale with the rig
## rather than being one hardcoded constant.
func _test_scale_awareness() -> void:
	var plain: Dictionary = _setup(1.0)
	var big: Dictionary = _setup(DUMMY_SCALE)
	var e1: Node = plain["enemy"]
	var e2: Node = big["enemy"]

	var h1: Vector2 = e1.call("head_point")
	var h2: Vector2 = e2.call("head_point")
	_expect(
		is_equal_approx(h2.y, h1.y * DUMMY_SCALE),
		"a %.1fx dummy's head sits %.1fx further above the origin (%.2f vs %.2f)"
			% [DUMMY_SCALE, DUMMY_SCALE, h2.y, h1.y]
	)
	_expect(
		is_equal_approx(float(e2.call("hit_margin")), float(e1.call("hit_margin")) * DUMMY_SCALE),
		"the forgiveness margin scales with the rig too"
	)
	# The reported symptom, at the scale it was reported at: aiming at a 1.9x
	# dummy's head is 18.9 px above its origin — outside a 20x20 box, inside the
	# silhouette.
	_expect(
		h2.y < -18.0,
		"a 1.9x dummy's head is >18px above global_position (y=%.2f) — a point test at the origin misses it" % h2.y
	)
	_expect(
		float(e2.call("body_distance", h2)) <= 0.0,
		"...and the silhouette test hits it"
	)
	_teardown(plain)
	_teardown(big)
	_completes("scale_awareness")


## The physics hurtbox (what a bolt's Area2D actually collides with) spans the
## whole drawn figure: head circle top at -h/2, body box bottom at the feet.
func _test_hurtbox_covers_the_drawn_figure() -> void:
	var c: Dictionary = _consts()
	var ctx: Dictionary = _setup()
	var enemy: Node = ctx["enemy"]
	var parts: Dictionary = _hurtbox_shapes(enemy)
	_expect(not parts.is_empty(), "a Hurtbox area is built on _ready")
	if parts.is_empty():
		_teardown(ctx)
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var area: Area2D = parts["area"]
	_expect(area.monitorable, "the hurtbox is monitorable (spell Area2Ds can see it)")
	_expect(not area.monitoring, "the hurtbox does not monitor (it is a target, not a sensor)")
	_expect(area.collision_layer == enemy.collision_layer,
		"the hurtbox sits on the same layer spells already scan")

	var head: CollisionShape2D = parts["head"]
	var torso: CollisionShape2D = parts["body"]
	var head_r: float = (head.shape as CircleShape2D).radius
	var box: Vector2 = (torso.shape as RectangleShape2D).size
	var top: float = head.position.y - head_r
	var bottom: float = torso.position.y + box.y * 0.5
	var feet_y: float = RIG_H * float(c["RIG_HIP_Y_FACTOR"]) + RIG_H * float(c["RIG_LEG_LEN_FACTOR"])
	_expect(
		is_equal_approx(top, -RIG_H * 0.5),
		"the hurtbox top is the drawn head top (%.2f, want %.2f)" % [top, -RIG_H * 0.5]
	)
	_expect(
		is_equal_approx(bottom, feet_y),
		"the hurtbox bottom is the drawn feet (%.2f, want %.2f)" % [bottom, feet_y]
	)
	_expect(
		bottom - top > SCENE_BODY_BOX.y,
		"the hurtbox is TALLER than the old 20x20 box (%.2f vs %.2f)" % [bottom - top, SCENE_BODY_BOX.y]
	)
	# Head circle and body box must touch, or there is a gap at the neck.
	var neck_gap: float = torso.position.y - box.y * 0.5 - (head.position.y + head_r)
	_expect(
		absf(neck_gap) < 0.001, "head circle and body box meet at the neck (gap %.4f)" % neck_gap
	)
	_teardown(ctx)
	_completes("hurtbox_covers_the_drawn_figure")


## No stealth inflation: the hurtbox is exactly as WIDE as the collider that was
## already there, so this change only ever adds HEIGHT.
func _test_hurtbox_is_not_wider_than_before() -> void:
	var ctx: Dictionary = _setup()
	var parts: Dictionary = _hurtbox_shapes(ctx["enemy"])
	if parts.is_empty():
		_teardown(ctx)
		_expect(false, "hurtbox exists (width check)")
		return
	var box: Vector2 = ((parts["body"] as CollisionShape2D).shape as RectangleShape2D).size
	var head_r: float = ((parts["head"] as CollisionShape2D).shape as CircleShape2D).radius
	_expect(
		is_equal_approx(box.x, SCENE_BODY_BOX.x),
		"the hurtbox body is the shipped collider width (%.2f, want %.2f)" % [box.x, SCENE_BODY_BOX.x]
	)
	_expect(
		head_r * 2.0 <= SCENE_BODY_BOX.x + 0.001,
		"the head circle is no wider than that either (%.2f vs %.2f)" % [head_r * 2.0, SCENE_BODY_BOX.x]
	)
	_teardown(ctx)
	_completes("hurtbox_is_not_wider_than_before")


## The Guardian extends Enemy, so it must inherit the same silhouette at its own
## 95 px rig height — one scheme, not a special case.
func _test_boss_inherits_the_silhouette() -> void:
	var ctx: Dictionary = _setup(1.0, BOSS_SCRIPT_PATH)
	var boss: Node = ctx["enemy"]
	var rig: CharacterRig = ctx["rig"]
	_expect(
		is_equal_approx(rig.height, 95.0),
		"Boss._ready bumps the rig to RIG_HEIGHT (got %.1f)" % rig.height
	)
	var parts: Dictionary = _hurtbox_shapes(boss)
	if parts.is_empty():
		_teardown(ctx)
		_expect(false, "the Guardian gets a hurtbox too")
		return
	var head: CollisionShape2D = parts["head"]
	var head_r: float = (head.shape as CircleShape2D).radius
	_expect(
		is_equal_approx(head.position.y - head_r, -rig.height * 0.5),
		"the Guardian's hurtbox reaches its own drawn head top"
	)
	_expect(
		float(boss.call("body_distance", boss.call("head_point"))) <= 0.0,
		"a hit on the Guardian's head registers"
	)
	_expect(
		float(boss.call("body_distance", Vector2(0.0, -rig.height))) > float(boss.call("hit_margin")),
		"...and a shot sailing over the Guardian still misses"
	)
	_teardown(ctx)
	_completes("boss_inherits_the_silhouette")
