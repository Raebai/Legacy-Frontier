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
