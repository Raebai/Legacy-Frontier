# Run: godot --headless --path godot-project --script tools/slice_test_dojo_feet.gd
#
# EVERY BODY IN THE DOJO STANDS ON THE FLOOR.
#
# Maker, playing the tutorial 2026-10-18: *"during the tutorial the bots are flying"*.
# Measured with `tools/probe_dojo_feet.gd`: four of the five figures hung 55 to 61 px
# above the surface under them, with a y velocity of 0.00 after 40 physics frames —
# not mid-fall, not falling at all.
#
# ⚠ WHY NOTHING CAUGHT IT, AND WHY THIS SUITE IS SHAPED LIKE THIS. Two separate
# mistakes had to line up, and either one alone is invisible:
#
#   1. The spawn y values were written as if the floor were ~60 px higher than it is.
#      `GROUND_TOP` is 780 and the ruin terrace is 696, but the dummies were placed at
#      716 and 626, and the sensei copied the hero's position on the frame it spawned —
#      which is `FREE_SPAWN`'s 716, BEFORE gravity has pulled the hero down to 771.
#   2. `set_physics_process(false)`, which is deliberate and must stay: a dummy has no
#      controller, so `Hero._pressed` falls through to the real `Input` and every dummy
#      would mirror the player's own buttons. Physics off is what stops the shadow-boxing.
#
# Gravity is what hid (1) everywhere else in the game — the hero spawns at the same
# wrong y and simply falls, landing at 771 with its feet on 780. The bodies that had
# physics switched off had nothing to correct them, so they kept the wrong number.
#
# So this asserts the thing the player SEES (feet on floor), not the thing that is easy
# to assert (a constant equals a constant). A constant check would pass the moment
# someone edited the constant and would never notice the terrace case at all.
extends SceneTree

## Feet may sit this far from the surface and still read as standing. The rig's own
## resting error is ~0.03 px (measured on the hero), so 2.0 is generous and still an
## order of magnitude under the 55 px bug.
const TOLERANCE: float = 2.0
const SETTLE_FRAMES: int = 40

var _fails: int = 0
var _checked: int = 0


func _initialize() -> void:
	_run()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _run() -> void:
	var fp: GDScript = load("res://scripts/combat/FreePlay.gd") as GDScript
	if fp == null:
		printerr("FAIL: FreePlay.gd did not load")
		printerr("Dojo-feet tests: 1 FAILED")
		quit(1)
		return
	fp.set("dojo", true)
	fp.call("enter", self, 0)

	for i: int in SETTLE_FRAMES:
		await physics_frame

	for n: Node in _all(root):
		var rig: Node = n.get_node_or_null(^"Rig")
		if rig == null or not (n is Node2D):
			continue
		var body := n as Node2D
		var h: float = float(rig.get("height"))
		var rig_foot: float = body.global_position.y 			+ float((rig as Node2D).position.y) + h * 0.5
		var ground: float = _ground_under(body, h)
		if not is_finite(ground):
			# Nothing underneath at all is its own bug, and a worse one.
			_expect(false, "%s has NO floor under it at x=%.0f — it is over a hole or "
				% [_label(n), body.global_position.x]
				+ "outside the stage")
			_checked += 1
			continue
		var gap: float = ground - rig_foot
		_checked += 1
		_expect(absf(gap) <= TOLERANCE,
			("%s is %.1f px %s the floor (feet %.1f, floor %.1f). A dojo body with "
			+ "physics disabled never falls, so a wrong spawn y is permanent — it hangs "
			+ "there for the whole lesson. Fix the SPAWN, not the rig.") % [
				_label(n), absf(gap), "above" if gap > 0.0 else "below", rig_foot, ground])

	_expect(_checked >= 4,
		"expected at least 4 bodies in the dojo (hero + sensei + %d dummies), found %d"
		% [3, _checked])

	if _fails > 0:
		printerr("Dojo-feet tests: %d FAILED" % _fails)
		quit(1)
		return
	print("Dojo-feet tests: all PASS (%d bodies, all within %.1f px of their floor)"
		% [_checked, TOLERANCE])
	quit(0)


func _label(n: Node) -> String:
	for g: Variant in [&"free_dummy", &"sensei", &"hero"]:
		if n.get_groups().has(g):
			return "%s (%s)" % [n.name, String(g)]
	return String(n.name)


## The same downward ray the rig casts, so this is the floor the rig itself acts on.
func _ground_under(body: Node2D, h: float) -> float:
	var space: PhysicsDirectSpaceState2D = body.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(
		body.global_position + Vector2(0.0, -h * 0.5),
		body.global_position + Vector2(0.0, h * 4.0),
		int(CharacterRig.GROUND_MASK))
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	return INF if hit.is_empty() else (hit["position"] as Vector2).y


func _all(from: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(from)
	for c: Node in from.get_children():
		_all(c, out)
	return out
