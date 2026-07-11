class_name Targeting
extends RefCounted
## Pure auto-aim helpers. No state; static functions only.


static func nearest(from: Vector2, targets: Array) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for t in targets:
		if not is_instance_valid(t):
			continue
		var d: float = from.distance_squared_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


static func aim_direction(from: Vector2, targets: Array, fallback: Vector2) -> Vector2:
	var target: Node2D = nearest(from, targets)
	if target == null:
		return fallback.normalized() if fallback != Vector2.ZERO else Vector2.RIGHT
	var dir: Vector2 = target.global_position - from
	return dir.normalized() if dir != Vector2.ZERO else fallback.normalized()


## Soft aim assist (twin-stick): start from `raw_aim` (the cursor direction) and
## bend it toward the nearest enemy that sits inside a forgiveness cone
## (dot(aim, toward) >= cone_dot) AND within `max_range`. `bend` in [0,1] is how
## far to rotate toward that enemy (1.0 = full snap). Returns `raw_aim` unchanged
## when no enemy qualifies, so open-space casting still goes exactly at the
## cursor. Keeps aiming precise-but-forgiving without hard lock-on. Pure/static.
static func assisted_aim(
	from: Vector2,
	raw_aim: Vector2,
	targets: Array,
	cone_dot: float = 0.95,
	max_range: float = 420.0,
	bend: float = 0.6,
) -> Vector2:
	var aim: Vector2 = raw_aim.normalized() if raw_aim != Vector2.ZERO else Vector2.RIGHT
	var best: Node2D = null
	var best_d: float = INF
	for t in targets:
		if not is_instance_valid(t):
			continue
		var to_t: Vector2 = t.global_position - from
		var dist: float = to_t.length()
		if dist <= 0.0 or dist > max_range:
			continue
		var dir: Vector2 = to_t / dist
		if aim.dot(dir) < cone_dot:
			continue
		if dist < best_d:
			best_d = dist
			best = t
	if best == null:
		return aim
	var target_dir: Vector2 = (best.global_position - from).normalized()
	if aim.dot(target_dir) >= 0.9999:
		return target_dir
	return aim.slerp(target_dir, clampf(bend, 0.0, 1.0))
