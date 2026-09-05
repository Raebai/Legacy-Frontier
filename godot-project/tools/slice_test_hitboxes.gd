# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#          --script tools/slice_test_hitboxes.gd
#
# ══ THE HITBOX MUST BE WHERE THE FIGURE IS DRAWN ═════════════════════════════
#
# A fighter in this game is four different shapes and only one of them is visible.
# `tools/probe_hitboxes.gd` prints all four; this pins the relationships between
# them, because every fault this suite exists for was a SILENT one: nothing errors,
# nothing looks wrong in isolation, and the only symptom is a maker saying shots do
# not register.
#
# THE THREE FAULTS IT WAS WRITTEN AGAINST, all measured before they were fixed:
#
#   1. THE ENEMY HURTBOX HAD SLID OFF THE HEAD AGAIN. `Enemy._sync_body_offset`
#      re-glued the Area2D to `rig.body_ride()` — the squash spring — but not to
#      `rig.position.y`, which ALSO carries the feet-alignment offset that
#      `CharacterRig._align_feet_to_body` writes (-5.50 on an enemy, +4.50 on a
#      guardian). Drawn head -21.13..-14.62 against an Area head -15.50..-8.98:
#      **86% of the skull had no collidable shape behind it**, so an aimed bolt
#      (`Spell.gd` damages on physics overlap, not on the silhouette) flew through.
#
#   2. THE HERO HAD NO HURTBOX AT ALL. Only the shipped 18x18 movement box, centred
#      on the origin, against a figure drawn -22.51..+10.18. The whole head, neck
#      and upper chest — 13.5 px, 41% of the drawing — were not there. Hero-vs-hero
#      is what the maker watches, so this was the worst of the three.
#
#   3. THE ANALYTIC SILHOUETTE STOPPED AT THE HIP. `body_distance` measured a
#      segment from the neck to the HIP, which on a stick figure sits a hair above
#      the mid-line — so from the belt down (38-39% of the figure) a blast measured
#      nothing. The same body's own physics hurtbox has always run neck-to-FEET, so
#      one fighter carried two hit shapes differing by more than a third of itself.
#
# ⚠ AND ONE THAT IS NOT A FAULT. The drawn feet overhang the floor by exactly the
# foot capsule's own cap radius (`LIMB_W_FACTOR * h * 0.5` — 1.16 px at 31, 3.56 px
# at 95, a flat 3.7% of height everywhere). Pulling the plant up by that radius would
# shorten the drawn leg by 3.7% of height, and a two-bone IK takes the SQUARE ROOT of
# a shortfall: it would put a 9.7%-of-height knee jut back into every standing figure
# — the exact "permanent half-squat" the posture pass was written to kill. So the
# overhang is DELIBERATE and this suite pins it as a constant rather than driving it
# to zero. See `_test_foot_overhang_is_the_cap_radius`.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
# A dead property read ABORTS the enclosing function and returns the type's zero, so
# a test that dies half-way would otherwise look like a test that passed. Failures
# accumulate on the MEMBER `_fails`, and every test records a completion sentinel as
# its last line — a test that aborts is then missing from `_completed` and fails the
# suite BY ABSENCE.

const TESTS: Array[String] = [
	"every_fighter_has_a_hurtbox",
	"hurtbox_tracks_the_drawn_body",
	"hurtbox_survives_a_subclass_tick",
	"analytic_shape_covers_head_to_feet",
	"analytic_shape_still_misses_a_miss",
	"hero_and_enemy_are_the_same_body",
	"hurtboxes_are_proportional_across_archetypes",
	"foot_overhang_is_the_cap_radius",
	"drawn_crescent_does_not_outreach_the_swing",
	"melee_autotarget_stays_in_front",
	"a_swing_connects_at_contact_range",
	"cone_tell_circle_encloses_its_cone",
	"charge_lane_is_the_charge",
	"every_archetype_spell_declares_where_it_warns",
	"a_spell_tell_describes_its_own_spell",
]

const HERO: String = "res://scenes/combat/Hero.tscn"
const ENEMY: String = "res://scenes/combat/Enemy.tscn"
const BOSS: String = "res://scenes/combat/Boss.tscn"
const THRALL: String = "res://scenes/combat/Thrall.tscn"

const GROUND_Y: float = 300.0
const SETTLE_FRAMES: int = 120

## How far the physics hurtbox may sit from the drawn silhouette, as a FRACTION of
## rig height rather than a flat pixel count — a guardian is three times a minion and
## a flat tolerance would either be meaningless on one or impossible on the other.
##
## 0.05 h is 1.55 px on a standard fighter. The bug this catches was 5.63 px (0.18 h)
## and the current state is 0.13-0.51 px, so there is roughly 3x headroom before a
## false red and 3.5x before the real fault would sneak under it.
const GLUE_TOLERANCE_FACTOR: float = 0.05
## The hurtbox may stop SHORT of the drawn bottom by up to this fraction of height
## (the foot cap overhang, 0.0375 h) plus slack. It may never extend BELOW the
## drawing at all — a hitbox hanging under the soles is a hit on empty floor.
const FOOT_SHORTFALL_FACTOR: float = 0.06
## The drawn crescent (`SwingArc`) may promise at most this much more reach than the
## swing actually queries. It is not zero on purpose: the crescent is explanatory
## garnish and a leading edge that stopped exactly on the damage boundary would read
## as falling short. See `_test_drawn_crescent_does_not_outreach_the_swing`.
const CRESCENT_OVERREACH_LIMIT: float = 0.20

var _fails: int = 0
var _completed: Dictionary = {}
var _rig: GDScript = null
var _world: Node2D = null


func _initialize() -> void:
	# `_initialize` runs BEFORE the tree exists, so nothing built here would have a
	# parent, a physics world or a floor to stand on. Defer one frame.
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_rig = load("res://scripts/combat/CharacterRig.gd") as GDScript
	_world = _build_floor()
	await physics_frame

	await _test_every_fighter_has_a_hurtbox()
	await _test_hurtbox_tracks_the_drawn_body()
	await _test_hurtbox_survives_a_subclass_tick()
	await _test_analytic_shape_covers_head_to_feet()
	await _test_analytic_shape_still_misses_a_miss()
	await _test_hero_and_enemy_are_the_same_body()
	await _test_hurtboxes_are_proportional_across_archetypes()
	await _test_foot_overhang_is_the_cap_radius()
	_test_drawn_crescent_does_not_outreach_the_swing()
	await _test_melee_autotarget_stays_in_front()
	await _test_a_swing_connects_at_contact_range()
	_test_cone_tell_circle_encloses_its_cone()
	_test_charge_lane_is_the_charge()
	_test_every_archetype_spell_declares_where_it_warns()
	await _test_a_spell_tell_describes_its_own_spell()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Hitbox tests: %d FAILED" % _fails)
		quit(1)
		return
	print("Hitbox tests: all PASS")
	quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ the fixture

func _build_floor() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	var body := StaticBody2D.new()
	body.collision_layer = int(_rig.get("GROUND_MASK"))
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6000.0, 80.0)
	cs.shape = rect
	cs.position = Vector2(0.0, GROUND_Y + 40.0)
	body.add_child(cs)
	world.add_child(body)
	return world


## A settled fighter standing on the floor, or null. Dropped from above so PHYSICS
## chooses the resting y — a hand-placed y would be the test asserting its own answer.
func _stand(scene_path: String) -> Node2D:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var body: Node2D = packed.instantiate() as Node2D
	if body == null:
		return null
	_world.add_child(body)
	body.global_position = Vector2(0.0, GROUND_Y - 90.0)
	for i: int in SETTLE_FRAMES:
		# A Thrall with no summoner expires on an orphan grace timer. Held open: the
		# thing under test is its SHAPE, which does not care who summoned it.
		if is_instance_valid(body) and body.get(&"thrall_life") != null:
			body.set(&"thrall_life", 999.0)
		await physics_frame
	return body if is_instance_valid(body) else null


func _all_fighters() -> Array[Array]:
	return [["hero", HERO], ["enemy", ENEMY], ["boss", BOSS], ["thrall", THRALL]]


## Union of the shapes under the body's `Hurtbox` Area2D, in BODY-local px, INCLUDING
## the Area's own offset — that offset is the thing fault #1 was hiding in.
func _area_bounds(body: Node2D) -> Rect2:
	var area := body.get_node_or_null(^"Hurtbox") as Area2D
	if area == null:
		return Rect2()
	var out := Rect2()
	var got: bool = false
	for c: Node in area.get_children():
		var cs := c as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		var r: Rect2
		if cs.shape is RectangleShape2D:
			var half: Vector2 = (cs.shape as RectangleShape2D).size * 0.5
			r = Rect2(cs.position - half, half * 2.0)
		elif cs.shape is CircleShape2D:
			var rad: float = (cs.shape as CircleShape2D).radius
			r = Rect2(cs.position - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
		else:
			continue
		r.position += area.position
		out = r if not got else out.merge(r)
		got = true
	return out


## The DRAWN silhouette in BODY-local px: the joints of the pose the rig actually
## renders, each fattened by the radius it is stroked with, pushed through the rig's
## own transform (which is where the feet-align offset, the ride and the pitch live).
func _drawn_bounds(rig: Node2D) -> Rect2:
	var pose: Dictionary = rig.call("snapshot_pose")
	if pose.is_empty():
		return Rect2()
	var w: float = float(pose.get("w", 2.0))
	var samples: Array = [
		["head_center", float(pose.get("r", 3.0))],
		["neck", w * 0.5], ["shoulder", w * 0.5], ["hip", w * 0.5],
		["foot_lead", float(pose.get("foot_r", w * 0.5))],
		["foot_off", float(pose.get("foot_r", w * 0.5))],
	]
	var out := Rect2()
	var got: bool = false
	for s: Array in samples:
		if not pose.has(String(s[0])):
			continue
		var p: Vector2 = rig.transform * (pose[String(s[0])] as Vector2)
		var rad: float = float(s[1])
		var r := Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
		out = r if not got else out.merge(r)
		got = true
	return out


# ------------------------------------------------------------------- the tests

## Every fighter presents a PHYSICS shape for the drawn body — because a bolt is an
## Area2D and never consults the silhouette seam. This is fault #2's guard: for as
## long as `Spell.gd` damages on `body_entered` / `area_entered`, a fighter without a
## Hurtbox is a fighter whose head is not there.
func _test_every_fighter_has_a_hurtbox() -> void:
	for f: Array in _all_fighters():
		var body: Node2D = await _stand(String(f[1]))
		if body == null:
			_expect(false, "%s: could not stand a body up to measure" % f[0])
			continue
		var area := body.get_node_or_null(^"Hurtbox") as Area2D
		_expect(area != null, "%s has a Hurtbox Area2D" % f[0])
		if area != null:
			_expect(area.monitorable, "%s's Hurtbox is monitorable (a bolt must SEE it)" % f[0])
			_expect(area.collision_layer == body.get(&"collision_layer"),
				"%s's Hurtbox shares the body's collision layer (%d vs %d) — a bolt masks"
				% [f[0], area.collision_layer, body.get(&"collision_layer")]
				+ " the layer, not the node")
			_expect(_area_bounds(body).size.y > 0.0, "%s's Hurtbox has real shapes" % f[0])
		body.queue_free()
		await process_frame
	_completes("every_fighter_has_a_hurtbox")


## THE CENTRAL INVARIANT. The physics hurtbox sits on the drawing, not near it.
## This is what fault #1 broke and what a future edit to `_sync_body_offset`,
## `_sync_hurtbox` or `_align_feet_to_body` will break again.
func _test_hurtbox_tracks_the_drawn_body() -> void:
	for f: Array in _all_fighters():
		var body: Node2D = await _stand(String(f[1]))
		if body == null:
			_expect(false, "%s: could not stand a body up to measure" % f[0])
			continue
		var rig: Node2D = body.get_node_or_null(^"Rig") as Node2D
		if rig == null:
			_expect(false, "%s has no Rig to compare against" % f[0])
			body.queue_free()
			continue
		var h: float = float(rig.get("height"))
		var area: Rect2 = _area_bounds(body)
		var drawn: Rect2 = _drawn_bounds(rig)
		var tol: float = h * GLUE_TOLERANCE_FACTOR
		# ⚠ PROVE THE RIG OFFSET IS NON-ZERO FIRST. If `_align_feet_to_body` ever
		# stopped running, the offset would be 0, the Area would trivially line up with
		# the origin-framed drawing, and this test would pass while measuring nothing.
		# That is exactly the vacuous pass this suite's armour is about.
		_expect(absf(rig.position.y) > 0.5,
			"%s's rig carries a real feet-align offset (%.2f) — with 0 this comparison"
			% [f[0], rig.position.y] + " is vacuous")
		_expect(absf(area.position.y - drawn.position.y) <= tol,
			"%s: hurtbox TOP is on the drawn head (area %.2f vs drawn %.2f, tol %.2f)"
			% [f[0], area.position.y, drawn.position.y, tol])
		var shortfall: float = drawn.end.y - area.end.y
		_expect(shortfall >= -0.01,
			"%s: hurtbox hangs %.2f px BELOW the drawn feet — that is a hit on empty floor"
			% [f[0], -shortfall])
		_expect(shortfall <= h * FOOT_SHORTFALL_FACTOR,
			"%s: hurtbox stops %.2f px short of the drawn feet (max %.2f)"
			% [f[0], shortfall, h * FOOT_SHORTFALL_FACTOR])
		body.queue_free()
		await process_frame
	_completes("hurtbox_tracks_the_drawn_body")


## ⚠ THE GUARDIAN RUNS A DIFFERENT TICK, AND THAT IS HOW IT LOST ITS HITBOX.
##
## Godot calls `_physics_process` on the MOST DERIVED script only, and
## `Boss._physics_process` re-implements the whole tick without chaining
## `super._physics_process`. While the hurtbox sync lived there, every guardian in
## the game ran with an Area2D that was never re-glued to its rig — measured 8 px of
## its own legs outside its own hitbox, permanently. The sync moved to `_process`,
## which a subclass inherits whether or not it chains anything.
##
## So this asserts the MECHANISM, not just today's numbers: move the rig, tick, and
## the hurtbox must have followed. A body whose sync lives somewhere a subclass can
## shadow will fail here even if it happens to be aligned at spawn.
func _test_hurtbox_survives_a_subclass_tick() -> void:
	for f: Array in _all_fighters():
		var body: Node2D = await _stand(String(f[1]))
		if body == null:
			_expect(false, "%s: could not stand a body up to measure" % f[0])
			continue
		var rig: Node2D = body.get_node_or_null(^"Rig") as Node2D
		var area := body.get_node_or_null(^"Hurtbox") as Area2D
		if rig == null or area == null:
			_expect(false, "%s: no rig or no hurtbox to test the sync with" % f[0])
			if is_instance_valid(body):
				body.queue_free()
			continue
		# Shove the rig somewhere it would never go on its own, then let the game run.
		# Whatever owns the sync has one frame to notice.
		var moved: float = rig.position.y - 17.0
		rig.position.y = moved
		await process_frame
		await physics_frame
		await process_frame
		_expect(absf(area.position.y - rig.position.y) <= 0.01,
			"%s: hurtbox followed the rig (area %.2f vs rig %.2f) — if it did not, the"
			% [f[0], area.position.y, rig.position.y]
			+ " sync lives in a tick this class overrides")
		body.queue_free()
		await process_frame
	_completes("hurtbox_survives_a_subclass_tick")


## FAULT #3's guard. The duck-typed silhouette `SpellTargets` measures against must
## contain the whole drawn body on its centre line — head crown to soles — not just
## the half above the hip.
func _test_analytic_shape_covers_head_to_feet() -> void:
	for f: Array in _all_fighters():
		var body: Node2D = await _stand(String(f[1]))
		if body == null:
			_expect(false, "%s: could not stand a body up to measure" % f[0])
			continue
		if not body.has_method("body_distance") or not body.has_method("hit_margin"):
			_expect(false, "%s does not implement body_distance/hit_margin — SpellTargets"
				% f[0] + " falls back to a ZERO-SIZE point at the origin")
			body.queue_free()
			continue
		var rig: Node2D = body.get_node_or_null(^"Rig") as Node2D
		var h: float = float(rig.get("height"))
		var m: float = float(body.call("hit_margin"))
		_expect(m > 0.0, "%s publishes a real forgiveness ring (%.2f)" % [f[0], m])
		# Three points ON the drawn centre line: the crown, the belt, the soles. All
		# three are places a player can visibly aim at.
		var probes: Dictionary = {
			"crown": rig.global_position + Vector2(0.0, -h * 0.5 + 1.0),
			"belt": rig.global_position,
			"soles": rig.global_position + Vector2(0.0, h * 0.5 - 1.0),
		}
		for name: String in probes:
			var d: float = float(body.call("body_distance", probes[name] as Vector2))
			_expect(d <= m,
				"%s: a shot at its own %s registers (distance %.2f vs margin %.2f)"
				% [f[0], name, d, m])
		body.queue_free()
		await process_frame
	_completes("analytic_shape_covers_head_to_feet")


## ...AND THE SHAPE MUST STILL END. Growing a hitbox to cover the drawing is only a
## fix if a genuine miss still misses; otherwise it is a stealth inflation wearing a
## bug fix's clothes. A point a body-height out to the side is not a hit at any size.
func _test_analytic_shape_still_misses_a_miss() -> void:
	for f: Array in _all_fighters():
		var body: Node2D = await _stand(String(f[1]))
		if body == null:
			_expect(false, "%s: could not stand a body up to measure" % f[0])
			continue
		var rig: Node2D = body.get_node_or_null(^"Rig") as Node2D
		var h: float = float(rig.get("height"))
		var m: float = float(body.call("hit_margin"))
		for off: Vector2 in [Vector2(h, 0.0), Vector2(0.0, -h * 1.2), Vector2(0.0, h * 1.2)]:
			var d: float = float(body.call("body_distance", rig.global_position + off))
			_expect(d > m,
				"%s: a clear miss at %s still misses (distance %.2f vs margin %.2f)"
				% [f[0], off, d, m])
		body.queue_free()
		await process_frame
	_completes("analytic_shape_still_misses_a_miss")


## ⚠ TWO SILHOUETTE IMPLEMENTATIONS IS HOW "SPELLS PASS THROUGH HEADS" HAPPENED THE
## FIRST TIME. `Hero.body_distance` and `Enemy.body_distance` are separate functions
## in separate files; they must answer the same question with the same number, or one
## actor type quietly becomes harder to hit than the other in a hero-vs-enemy game
## AND in a hero-vs-hero one. `slice_test_hit_silhouette` pins the CHEST case; this
## pins the LEGS, which is where they most recently diverged.
func _test_hero_and_enemy_are_the_same_body() -> void:
	var hero: Node2D = await _stand(HERO)
	var enemy: Node2D = await _stand(ENEMY)
	if hero == null or enemy == null:
		_expect(false, "could not stand up both a hero and an enemy")
		_completes("hero_and_enemy_are_the_same_body")
		return
	var hr: Node2D = hero.get_node_or_null(^"Rig") as Node2D
	var er: Node2D = enemy.get_node_or_null(^"Rig") as Node2D
	var h: float = float(hr.get("height"))
	_expect(is_equal_approx(h, float(er.get("height"))),
		"the two rigs are the same height (%.2f vs %.2f) — otherwise this comparison"
		% [h, float(er.get("height"))] + " is about size, not about shape")
	# Beside the SHIN, off-axis so the answer is a real silhouette query rather than
	# a point sitting on the segment.
	for frac: float in [0.20, 0.35, 0.48]:
		var off := Vector2(5.0, h * frac)
		var hd: float = float(hero.call("body_distance", hr.global_position + off))
		var ed: float = float(enemy.call("body_distance", er.global_position + off))
		_expect(absf(hd - ed) <= 0.51,
			"hero and enemy measure a point beside the leg the same (%.3f vs %.3f at %s)"
			% [hd, ed, off])
	_expect(absf(float(hero.call("hit_margin")) - float(enemy.call("hit_margin"))) <= 0.01,
		"hero and enemy publish the same forgiveness ring (%.3f vs %.3f)"
		% [float(hero.call("hit_margin")), float(enemy.call("hit_margin"))])
	hero.queue_free()
	enemy.queue_free()
	await process_frame
	_completes("hero_and_enemy_are_the_same_body")


## A big fighter must not carry a small fighter's hitbox, or the other way round.
## Measured as the hurtbox's HEIGHT over the rig's height: every archetype cuts the
## same shape from the same constants, so the ratio is the thing that must not drift
## when someone authors a new body with a hand-typed collider.
func _test_hurtboxes_are_proportional_across_archetypes() -> void:
	var ratios: Dictionary = {}
	for f: Array in _all_fighters():
		var body: Node2D = await _stand(String(f[1]))
		if body == null:
			_expect(false, "%s: could not stand a body up to measure" % f[0])
			continue
		var rig: Node2D = body.get_node_or_null(^"Rig") as Node2D
		var h: float = float(rig.get("height"))
		var area: Rect2 = _area_bounds(body)
		if h > 0.0 and area.size.y > 0.0:
			ratios[String(f[0])] = area.size.y / h
		body.queue_free()
		await process_frame
	_expect(ratios.size() == 4, "all four archetypes reported a ratio (%d did)" % ratios.size())
	var lo: float = INF
	var hi: float = -INF
	for k: String in ratios:
		lo = minf(lo, float(ratios[k]))
		hi = maxf(hi, float(ratios[k]))
	# The shapes are cut from `-h/2` (head top) to `HIP_Y + LEG_LEN` (= +h/2), so the
	# honest answer is 1.00 for every archetype. Allowed 0.04 of spread rather than
	# pinned exactly, because a body spring mid-ring moves the union a hair.
	_expect(hi - lo <= 0.04,
		"hurtbox height / rig height agrees across archetypes (%.3f .. %.3f: %s)"
		% [lo, hi, str(ratios)])
	_expect(lo >= 0.90,
		"no archetype's hurtbox is shorter than 90%% of its own rig (%.3f: %s)"
		% [lo, str(ratios)])
	_completes("hurtboxes_are_proportional_across_archetypes")


## THE DELIBERATE ONE. See the header: the drawn feet overhang the floor line by the
## foot capsule's own cap radius and that is left alone on purpose, because pulling
## it up puts a visible knee bend back into every standing figure. Pinned as a
## CONSTANT so it stays a known 3.7% of height rather than drifting into a real sink.
func _test_foot_overhang_is_the_cap_radius() -> void:
	for f: Array in _all_fighters():
		var body: Node2D = await _stand(String(f[1]))
		if body == null:
			_expect(false, "%s: could not stand a body up to measure" % f[0])
			continue
		var rig: Node2D = body.get_node_or_null(^"Rig") as Node2D
		var h: float = float(rig.get("height"))
		# The NOMINAL foot joint — what `probe_town_feet.gd` measures, and what
		# `_align_feet_to_body` solves to put exactly on the floor.
		var nominal: float = body.global_position.y + rig.position.y + h * 0.5
		_expect(absf(nominal - GROUND_Y) <= 0.35,
			"%s: the foot JOINT rests on the floor (%.2f vs %.2f) — this is"
			% [f[0], nominal, GROUND_Y] + " probe_town_feet's SINK and it must be ~0")
		# ...and the drawn cap below it, which is allowed to overlap by its radius.
		var cap: float = maxf(1.6, h * float(_rig.get("LIMB_W_FACTOR"))) * 0.5
		var drawn_bottom: float = body.global_position.y + _drawn_bounds(rig).end.y
		var overhang: float = drawn_bottom - GROUND_Y
		_expect(overhang >= -0.35,
			"%s: the drawn feet are not FLOATING (%.2f above the floor)" % [f[0], -overhang])
		_expect(overhang <= cap + 0.35,
			"%s: the drawn feet sink %.2f px, more than the foot cap radius %.2f — that"
			% [f[0], overhang, cap]
			+ " is a real box/rig disagreement, not the deliberate capsule overlap")
		body.queue_free()
		await process_frame
	_completes("foot_overhang_is_the_cap_radius")


## THE ARC YOU SEE VS THE ARC THAT HITS.
##
## `SwingArc`'s own header promises it "is told the reach it has to explain and
## travels exactly that far". It does not, quite: its last frame centres the crescent
## at `from + dir * reach` and then draws a circle of radius `0.42 * reach` about a
## point pulled back by `0.65` of that radius, so the LEADING EDGE lands at
## `reach * 1.147`. Against a standard 31 px enemy the swing itself reaches
## `melee_range + hit_margin`.
##
## Both numbers are pinned together rather than forced equal, because a crescent whose
## tip stopped exactly on the damage boundary would read as falling short of its own
## hit. What must not happen is the picture promising a swing the hitbox does not
## have — that is the complaint the crescent was added to answer, arriving from the
## other direction.
func _test_drawn_crescent_does_not_outreach_the_swing() -> void:
	var hero: GDScript = load("res://scripts/combat/Hero.gd") as GDScript
	var enemy: GDScript = load("res://scripts/combat/Enemy.gd") as GDScript
	var swing: GDScript = load("res://scripts/combat/SwingArc.gd") as GDScript
	if hero == null or enemy == null or swing == null:
		_expect(false, "could not load Hero / Enemy / SwingArc to compare reaches")
		_completes("drawn_crescent_does_not_outreach_the_swing")
		return
	# ⚠ DERIVED FROM SwingArc'S OWN CONSTANTS WHERE THEY EXIST. `SWEEP` is exported as
	# a const and is read here so a widened crescent is noticed; the 0.42 / 0.65 pair
	# are `_draw` locals, so they are named here with the arithmetic spelled out. If
	# `_draw` is retuned, this number must move with it — that is the point of pinning.
	var edge_factor: float = 1.0 + 0.42 - 0.42 * 0.65
	_expect(float(swing.get("START_FRAC")) < 1.0,
		"the crescent still LEAVES the blade rather than starting at full reach")
	var cfgs: Dictionary = hero.get("CLASS_CONFIG")
	var names: Array = hero.get("CLASS_NAMES")
	var default_range: float = float(hero.get("MELEE_RANGE"))
	var enemy_margin: float = float(_rig.get("DEFAULT_HEIGHT")) \
		* float(enemy.get("HIT_MARGIN_FACTOR"))
	var checked: int = 0
	for cls: int in cfgs.keys():
		var rng: float = float((cfgs[cls] as Dictionary).get("melee_range", default_range))
		var drawn: float = rng * edge_factor
		var hits: float = rng + enemy_margin
		var over: float = (drawn - hits) / hits
		_expect(over <= CRESCENT_OVERREACH_LIMIT,
			"%s: the drawn crescent reaches %.1f px where the swing hits %.1f (%.0f%% over,"
			% [str(names[cls]) if cls < names.size() else str(cls), drawn, hits, over * 100.0]
			+ " limit %.0f%%)" % (CRESCENT_OVERREACH_LIMIT * 100.0))
		checked += 1
	_expect(checked >= 9, "every class in the roster was checked (%d)" % checked)
	_completes("drawn_crescent_does_not_outreach_the_swing")


## THE SWING CANNOT LAND BEHIND YOU — TESTED THROUGH THE DAMAGE PATH.
##
## `_on_melee_hit_frame` used to append `_nearest_enemy_in_melee_range()` at ANY angle
## on top of its facing cone, so every basic attack was a full disc. Removed on the
## maker's standing **"NO auto-aim"** ruling; see the block above that function.
##
## ⚠ IT DRIVES `_on_melee_hit_frame`, NOT THE HELPER. The helper survives as a faction
## seam (`slice6_test_bot_seams` and `slice_test_friendly_fire` assert through it) and
## still scans a disc, exactly as before — so a test that asked the helper would now
## pass while proving nothing about what a swing hits. The behaviour the ruling is
## about lives at the call site, so that is what is driven.
##
## Both directions are asserted, because only one of them means anything on its own: a
## swing that hit NOTHING would pass the behind case for free.
func _test_melee_autotarget_stays_in_front() -> void:
	var hero: Node2D = await _stand(HERO)
	if hero == null:
		_expect(false, "could not stand a hero up to swing")
		_completes("melee_autotarget_stays_in_front")
		return
	hero.call("configure_class", 2)   # BRAWLER — default arc_dot 0.30, range 58
	# ⚠ BOTH GROUPS, AND THE FIRST VERSION OF THIS TEST ONLY JOINED ONE. The two halves
	# of the old swing scanned DIFFERENT groups: the cone scans `attack_group()`, which
	# is `mortal` once friendly fire is on, while the auto-target scanned
	# `hostile_group`, which is `enemy`. A stub in only `mortal` is invisible to the
	# auto-target, so the "behind" case below passed whether or not the auto-target
	# existed — and it did: restoring the deleted append left this suite GREEN. Joining
	# both is what makes the assertion able to fail.
	var mark := HitCounter.new()
	mark.add_to_group(String(hero.call("attack_group")))
	mark.add_to_group(String(hero.get(&"hostile_group")))
	_world.add_child(mark)

	# IN FRONT and inside the cone — the control. Without this the behind case below
	# could pass simply because no swing lands at all.
	mark.global_position = hero.global_position + Vector2(30.0, -6.0)
	await physics_frame
	_swing(hero, Vector2.RIGHT)
	_expect(mark.hits == 1,
		"a swing lands on a body in front of the swinger (hits %d)" % mark.hits)

	# DIRECTLY BEHIND, well inside reach. This is the one that used to connect.
	mark.hits = 0
	mark.global_position = hero.global_position + Vector2(-20.0, 0.0)
	await physics_frame
	_swing(hero, Vector2.RIGHT)
	_expect(mark.hits == 0,
		"a body standing BEHIND the swinger takes nothing (hits %d) — the auto-target"
		% mark.hits + " snap is gone")

	mark.queue_free()
	hero.queue_free()
	await process_frame
	_completes("melee_autotarget_stays_in_front")


## ══ A MOB STANDING ON TOP OF YOU IS HITTABLE ═════════════════════
##
## Maker: *"the mobs that are TOO close to the brawler don't get hit by the left click
## attack, please fix that."*
##
## THE FAULT, MEASURED (`tools/probe_hitboxes.gd`, the OVERLAP sweep). It is not a
## minimum range — a point target connects at 0.5 px on every bearing inside the arc,
## for all nine classes. It is that `SpellTargets.in_cone` measures REACH to the
## silhouette but ANGLE between the two ORIGINS, and two overlapping bodies have no
## meaningful relative direction. Brawler, signed offset along the facing:
##
##   offset  -12   -8   -4   -2   -1    0    1    2    4    8   20
##   before  MISS MISS MISS MISS MISS  hit  hit  hit  hit  hit  hit
##
## One pixel past your own origin and the swing goes through them. Walking into
## someone is how a mob arrives, so this is the common case, not a corner.
##
## ⚠ AND THE FIX MUST NOT REINTRODUCE THE AUTO-TARGET. Both edges are asserted here
## for that reason: contact range connects, and a body 20 px behind — well outside any
## silhouette overlap and squarely in the ground the "NO auto-aim" ruling reclaimed —
## still takes nothing. A contact core that grew to melee reach would pass the first
## assertion and fail the second, which is the point of having both.
func _test_a_swing_connects_at_contact_range() -> void:
	var hero: Node2D = await _stand(HERO)
	if hero == null:
		_expect(false, "could not stand a hero up for the contact-range check")
		_completes("a_swing_connects_at_contact_range")
		return
	hero.call("configure_class", 2)   # Brawler, the class the maker named
	# Both groups, for the reason `melee_autotarget_stays_in_front` records at length.
	var mark := HitCounter.new()
	mark.add_to_group(String(hero.call("attack_group")))
	mark.add_to_group(String(hero.get(&"hostile_group")))
	_world.add_child(mark)
	await physics_frame
	# The maker's case: the mob's origin has crossed the swinger's, bodies overlapping.
	for off: float in [-1.0, -3.0]:
		mark.hits = 0
		mark.global_position = hero.global_position + Vector2(off, 0.0)
		await physics_frame
		_swing(hero, Vector2.RIGHT)
		_expect(mark.hits == 1,
			"a mob overlapping the swinger at offset %.0f px is hit (hits %d) — the swing"
			% [off, mark.hits] + " must not have a hole where the bodies touch")
	# ...and the auto-target stays dead. 20 px is no overlap by any silhouette on a
	# 31 px rig, and it is the exact distance `melee_autotarget_stays_in_front` uses.
	mark.hits = 0
	mark.global_position = hero.global_position + Vector2(-20.0, 0.0)
	await physics_frame
	_swing(hero, Vector2.RIGHT)
	_expect(mark.hits == 0,
		"the contact core did NOT grow back into the auto-target: a body 20 px behind"
		+ " still takes nothing (hits %d)" % mark.hits)
	mark.queue_free()
	hero.queue_free()
	await process_frame
	_completes("a_swing_connects_at_contact_range")


## Counts melee landings. `take_damage` is the whole contract `_on_melee_hit_frame`
## needs; `hp` keeps `HpWatch.is_alive` happy so the body stays a legal target.
class HitCounter extends Node2D:
	var hits: int = 0
	var hp: int = 999
	var max_hp: int = 999

	func take_damage(_amount: int) -> void:
		hits += 1


## Point the hero and resolve one swing, IN THE SAME FRAME.
##
## ⚠ THE FACING MUST BE SET WITH NO `await` AFTER IT, and the first version of this
## test got that wrong. `Hero._physics_process` ends with `facing = _aim_dir`
## (Hero.gd:2202 / :7151), so a facing written before an `await physics_frame` is
## overwritten by the hero's own tick before the swing runs — this suite set RIGHT and
## measured a hero pointing at (-0.707, -0.707), i.e. it was asserting something about
## a swing aimed down-left. That is a harness bug that reads exactly like a code bug.
## Setting it immediately before is also the honest ordering: the real path reads
## `facing` in the same frame the swing resolves.
##
## `_swing_window` is opened first because `_on_melee_hit_frame` refuses to land
## without a declared swing — the rig fires `hit_frame` for any punch or kick, and
## four abilities play one without meaning to swing.
func _swing(hero: Node2D, dir: Vector2) -> void:
	hero.set(&"_aim_dir", dir)
	hero.set(&"facing", dir)
	_expect((hero.get(&"facing") as Vector2).is_equal_approx(dir),
		"the hero is actually facing %s when its swing resolves (it faces %s)"
		% [str(dir), str(hero.get(&"facing"))])
	hero.set(&"_swing_window", hero.get(&"SWING_WINDOW"))
	hero.call("_on_melee_hit_frame")


## `Telegraph.cone_bound` claims to return the smallest circle CONTAINING a wedge.
## Containment is the half that matters — a tell smaller than its attack is the whole
## fault — so it is checked by SAMPLING the wedge rather than by re-deriving the
## formula, which would only prove the formula equals itself.
##
## ⚠ MOVED FROM `Hero._cone_tell_circle`, WHICH IS DELETED, AND IT NOW GUARDS A
## DIFFERENT THING. It used to guard a circle DRAWN in place of a cone; `Telegraph`
## has a real CONE style now and the uppercut and frost cone draw wedges. What this
## formula still backs is `Telegraph.danger_shape()`'s machine-readable summary,
## which reports a cone AS a circle because six consumers this repo owns branch on
## `shape == "circle" or "line"` and would drop a third case on the floor. So the
## circle is what every bot in the game dodges, and it must still contain the wedge.
func _test_cone_tell_circle_encloses_its_cone() -> void:
	var tell: GDScript = load("res://scripts/combat/Telegraph.gd") as GDScript
	if tell == null:
		_expect(false, "could not load Telegraph.gd to check the cone bound geometry")
		_completes("cone_tell_circle_encloses_its_cone")
		return
	# Spans all three branches of the derivation: narrow (< 45 deg), wide (45-90) and
	# reflex (> 90), plus the two the game actually ships.
	for case: Array in [
		[118.0, 0.5], [70.0, -0.2], [58.0, 0.30], [96.0, 0.0],
		[60.0, 0.9], [80.0, -0.9],
	]:
		var reach: float = float(case[0])
		var min_dot: float = float(case[1])
		var a: float = acos(clampf(min_dot, -1.0, 1.0))
		var circle: Vector2 = tell.call("cone_bound", reach, a)
		var centre := Vector2(circle.x, 0.0)
		var worst: float = 0.0
		# The wedge's whole boundary: the apex, the two straight edges, and the arc.
		for i: int in 65:
			var f: float = float(i) / 64.0
			for pt: Vector2 in [
				Vector2.from_angle(a) * reach * f,
				Vector2.from_angle(-a) * reach * f,
				Vector2.from_angle(-a + 2.0 * a * f) * reach,
			]:
				worst = maxf(worst, centre.distance_to(pt))
		_expect(worst <= circle.y + 0.01,
			"reach %.0f dot %.2f: the tell circle (c %.2f r %.2f) contains its cone"
			% [reach, min_dot, circle.x, circle.y]
			+ " — worst wedge point is %.2f out" % worst)
		# ...and it is not vacuously huge. The wedge's own extent is `reach`, so a
		# circle much bigger than that is a warning about ground nothing can reach.
		_expect(circle.y <= reach * 1.05,
			"reach %.0f dot %.2f: the tell circle (r %.2f) is not larger than the"
			% [reach, min_dot, circle.y] + " attack's own reach")
	_completes("cone_tell_circle_encloses_its_cone")


## THE CHARGER'S LANE IS THE CHARGE. The drawn lane was 34 px wide over a 52 px catch
## (9 px of unmarked lethal ground per side) and 300 px long over 208 px of travel.
## Both are derived now; this is what stops a future hand-typed literal.
func _test_charge_lane_is_the_charge() -> void:
	var e: GDScript = load("res://scripts/combat/Enemy.gd") as GDScript
	if e == null:
		_expect(false, "could not load Enemy.gd to check the charge lane")
		_completes("charge_lane_is_the_charge")
		return
	var hit_r: float = float(e.get("CHARGE_HIT_RADIUS"))
	var travel: float = float(e.get("CHARGE_SPEED")) * float(e.get("CHARGE_TIME"))
	_expect(hit_r > 0.0 and travel > 0.0,
		"the charge has a real catch radius (%.1f) and real travel (%.1f)" % [hit_r, travel])
	_expect(is_equal_approx(float(e.get("CHARGE_WIDTH")), hit_r * 2.0),
		"the drawn lane is exactly as wide as the catch (%.1f vs %.1f)"
		% [float(e.get("CHARGE_WIDTH")), hit_r * 2.0])
	_expect(is_equal_approx(float(e.get("CHARGE_LEN")), travel + hit_r),
		"the drawn lane is exactly as long as the charge reaches (%.1f vs %.1f)"
		% [float(e.get("CHARGE_LEN")), travel + hit_r])
	_completes("charge_lane_is_the_charge")


## ⚠ A NEW ARCHETYPE MUST NOT INHERIT THE OLD SILENT DEFAULT. Four of the five spell
## rows warned on the wrong body because `_start_spell_windup` had one hard-coded
## answer for where a tell goes. The answer is a row key now, and a row that forgets
## it fails HERE rather than shipping a warning planted on the hero for a spell that
## erupts from the caster.
func _test_every_archetype_spell_declares_where_it_warns() -> void:
	var e: GDScript = load("res://scripts/combat/Enemy.gd") as GDScript
	if e == null:
		_expect(false, "could not load Enemy.gd to check the archetype spell table")
		_completes("every_archetype_spell_declares_where_it_warns")
		return
	var rows: Dictionary = e.get("ARCHETYPE_SPELLS")
	_expect(rows.size() >= 5, "the archetype spell table is real (%d rows)" % rows.size())
	for k: Variant in rows:
		var row: Dictionary = rows[k]
		_expect(row.has("tell_at"),
			"archetype %s declares where its tell is planted ('%s' has no tell_at)"
			% [str(k), String(row.get("id", "?"))])
		_expect(String(row.get("tell_at", "")) in ["caster", "target"],
			"archetype %s's tell_at is caster or target (got '%s')"
			% [str(k), String(row.get("tell_at", ""))])
	_completes("every_archetype_spell_declares_where_it_warns")


## ...AND THE TELL IT ACTUALLY EMITS MATCHES THE SPELL IT WILL ACTUALLY CAST.
## Behavioural: a real Enemy is driven through `_start_spell_windup` and the live
## `Telegraph`'s own `danger_shape()` — the dictionary `BotDodge` reads — is compared
## against `archetype_spell()`, which is the same SpellDef `_cast_archetype_spell`
## hands to `SpellCaster`. A table-vs-table check would only prove the table agrees
## with itself.
func _test_a_spell_tell_describes_its_own_spell() -> void:
	var script: GDScript = load("res://scripts/combat/Enemy.gd") as GDScript
	if script == null:
		_expect(false, "could not load Enemy.gd to drive a spell windup")
		_completes("a_spell_tell_describes_its_own_spell")
		return
	var rows: Dictionary = script.get("ARCHETYPE_SPELLS")
	var checked: int = 0
	for arch: Variant in rows:
		var body: CharacterBody2D = script.new()
		body.collision_layer = 4
		var rig: Node2D = (load("res://scripts/combat/CharacterRig.gd") as GDScript).new()
		rig.name = "Rig"
		body.add_child(rig)
		body.set(&"archetype", arch)
		_world.add_child(body)
		body.global_position = Vector2(0.0, GROUND_Y - 400.0)
		# No brain: this suite wants the windup's GEOMETRY, not an AI tick that reaches
		# for autoloads a --script harness never registered.
		body.set_physics_process(false)
		body.set_process(false)
		var mark := Node2D.new()
		mark.add_to_group("hero")
		_world.add_child(mark)
		mark.global_position = body.global_position + Vector2(200.0, 0.0)
		body.set(&"_hero", mark)
		await process_frame
		body.call("_start_spell_windup")
		var tele: Node2D = body.get(&"_telegraph")
		var spell: Resource = body.call("archetype_spell")
		if tele == null or spell == null:
			_expect(false, "archetype %s emitted no telegraph or has no spell" % str(arch))
		else:
			var shape: Dictionary = tele.call("danger_shape")
			var at_caster: bool = String((rows[arch] as Dictionary).get("tell_at", "")) == "caster"
			var want: Vector2 = body.global_position if at_caster else mark.global_position
			_expect((shape["center"] as Vector2).distance_to(want) <= 0.01,
				"archetype %s (%s) warns on the right body (tell at %s, wanted %s)"
				% [str(arch), String(spell.get("id")), str(shape["center"]), str(want)])
			_expect(is_equal_approx(float(shape["radius"]), float(spell.get("radius"))),
				"archetype %s (%s) warns at the spell's own radius (%.1f vs %.1f)"
				% [str(arch), String(spell.get("id")), float(shape["radius"]),
					float(spell.get("radius"))])
			# COLOUR MEANS ELEMENT. A shadow root drawn in caster-purple teaches the
			# wrong thing about what is coming.
			var want_c: Color = Elements.color(SpellCaster.resolve_element(spell))
			_expect(tele.get(&"accent").is_equal_approx(want_c),
				"archetype %s (%s) warns in its ELEMENT's colour, not its archetype's"
				% [str(arch), String(spell.get("id"))])
			checked += 1
		if is_instance_valid(tele):
			tele.queue_free()
		mark.queue_free()
		body.queue_free()
		await process_frame
	_expect(checked == rows.size(),
		"every archetype spell was driven through a real windup (%d of %d)"
		% [checked, rows.size()])
	_completes("a_spell_tell_describes_its_own_spell")
