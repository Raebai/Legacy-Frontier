class_name SpellGeometry
extends RefCounted
## Shared world-space geometry for spell effects — overlap tests and, crucially,
## WHERE two effects meet.
##
## Every live spectacle describes itself with a shape dictionary in the same form
## Telegraph.danger_shape() already uses:
##     {"shape": "circle", "center": Vector2, "radius": float}
##     {"shape": "line",   "from": Vector2, "to": Vector2, "width": float}
## A "line" is a CAPSULE, not an infinite ray: beams, lanes and walls all have a
## real length and thickness, and treating them as capsules makes beam-vs-beam,
## beam-vs-wall and blast-vs-beam one code path instead of three.
##
## THE TRAP THIS EXISTS TO AVOID: spell spectacle nodes park at the arena origin
## and draw in world coordinates, so their global_position is (0,0) and is NOT
## where the effect is. Anything here takes explicit world-space values; nothing
## reads a node's transform. Callers must build their shape from their own
## internal points, never from global_position.

const EPS: float = 0.00001


# ---- primitives ------------------------------------------------------------

## Closest point to `p` on segment a->b.
static func closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 <= EPS:
		return a
	return a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0)


static func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(closest_point_on_segment(p, a, b))


## The mutually-closest pair of points on two segments. Returns [on_a, on_b].
## This is what gives a crossing its LOCATION — Hollow Purple has to detonate
## where the two beams actually meet, not at either caster and not at a midpoint.
static func closest_points_on_segments(p1: Vector2, q1: Vector2,
		p2: Vector2, q2: Vector2) -> Array:
	var d1: Vector2 = q1 - p1
	var d2: Vector2 = q2 - p2
	var r: Vector2 = p1 - p2
	var a: float = d1.dot(d1)
	var e: float = d2.dot(d2)
	var f: float = d2.dot(r)
	var s: float = 0.0
	var t: float = 0.0
	if a <= EPS and e <= EPS:
		return [p1, p2]
	if a <= EPS:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c: float = d1.dot(r)
		if e <= EPS:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b: float = d1.dot(d2)
			var denom: float = a * e - b * b
			# denom == 0 means the segments are parallel; any s is as good as
			# another, so anchor at the start and solve t from it.
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if absf(denom) > EPS else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]


static func segment_distance(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> float:
	var pair: Array = closest_points_on_segments(p1, q1, p2, q2)
	return (pair[0] as Vector2).distance_to(pair[1] as Vector2)


# ---- shape dictionaries ----------------------------------------------------

static func circle(center: Vector2, radius: float) -> Dictionary:
	return {"shape": "circle", "center": center, "radius": radius}


static func capsule(from: Vector2, to: Vector2, width: float) -> Dictionary:
	return {"shape": "line", "from": from, "to": to, "width": width}


static func is_circle(s: Dictionary) -> bool:
	return String(s.get("shape", "")) == "circle"


## Do these two live effects touch? Dispatches on the pair of shape kinds; a
## capsule is a segment inflated by half its width, which reduces every case to a
## distance test against the sum of the two radii.
static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if is_circle(a) and is_circle(b):
		return (a["center"] as Vector2).distance_to(b["center"]) \
			<= float(a["radius"]) + float(b["radius"])
	if is_circle(a) and not is_circle(b):
		return point_segment_distance(a["center"], b["from"], b["to"]) \
			<= float(a["radius"]) + float(b["width"]) * 0.5
	if is_circle(b) and not is_circle(a):
		return point_segment_distance(b["center"], a["from"], a["to"]) \
			<= float(b["radius"]) + float(a["width"]) * 0.5
	return segment_distance(a["from"], a["to"], b["from"], b["to"]) \
		<= (float(a["width"]) + float(b["width"])) * 0.5


## Where the two effects meet — the point a reaction should be staged at.
## For two capsules this is the midpoint of their closest approach, which for
## crossing beams is the crossing itself.
static func meeting_point(a: Dictionary, b: Dictionary) -> Vector2:
	if a.is_empty() or b.is_empty():
		return Vector2.ZERO
	if is_circle(a) and is_circle(b):
		return (a["center"] as Vector2).lerp(b["center"] as Vector2, 0.5)
	if is_circle(a):
		return closest_point_on_segment(a["center"], b["from"], b["to"])
	if is_circle(b):
		return closest_point_on_segment(b["center"], a["from"], a["to"])
	var pair: Array = closest_points_on_segments(a["from"], a["to"], b["from"], b["to"])
	return (pair[0] as Vector2).lerp(pair[1] as Vector2, 0.5)


## Angle bisector of two capsules' directions — the axis a collapse should fire
## along, so an annihilation between two crossed beams throws its lance out
## between them rather than picking one arbitrarily.
static func bisector(a: Dictionary, b: Dictionary) -> Vector2:
	if is_circle(a) or is_circle(b):
		return Vector2.RIGHT
	var da: Vector2 = ((a["to"] as Vector2) - (a["from"] as Vector2)).normalized()
	var db: Vector2 = ((b["to"] as Vector2) - (b["from"] as Vector2)).normalized()
	var sum: Vector2 = da + db
	# Exactly opposed beams sum to zero and have no bisector; take the
	# perpendicular so the payoff still fires somewhere sensible.
	if sum.length_squared() <= EPS:
		return da.orthogonal()
	return sum.normalized()


static func contains_point(s: Dictionary, p: Vector2) -> bool:
	if s.is_empty():
		return false
	if is_circle(s):
		return (s["center"] as Vector2).distance_to(p) <= float(s["radius"])
	return point_segment_distance(p, s["from"], s["to"]) <= float(s["width"]) * 0.5
