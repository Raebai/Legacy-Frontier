class_name BlinkSpark
extends Node2D
## THE STAR THAT SAYS SOMEBODY TELEPORTED.
##
## Maker: *"teleport should be more clear like when a user teleports maybe like a
## small star blink or something to show what just happened"*.
##
## ⚠ THE TELEPORTS WERE NOT UNDECORATED — THEY WERE DECORATED WRONG. Every blink path
## in `Hero` already spawns a `CombatVfx.spawn_burst` at each end. The problem is that
## a radial burst of round motes is the same primitive the game uses for a hit, a
## death, a crate breaking and a spell landing, so it says "something happened here"
## and nothing more. Nothing said WENT, and nothing tied the two ends together, so a
## body that vanished at A and appeared at B read as a rendering glitch.
##
## Three marks, and each one is doing a different job:
##
##   1. A FOUR-POINT STAR AT THE ORIGIN, collapsing inward. A star is not in the
##      game's impact vocabulary, so it cannot be misread as a hit — it is only ever
##      a teleport. Collapsing says "left".
##   2. A FOUR-POINT STAR AT THE DESTINATION, snapping outward. Says "arrived".
##   3. A TAPERED STREAK BETWEEN THEM, fat at the origin and pointed at the
##      destination. This is the one that matters: it is the only mark that shows the
##      two ends are the same event, and it is what turns "he vanished" into "he went
##      that way".
##
## PRIMITIVE-DRAWN and self-freeing, like `SwingArc`. No scene, no particles, no
## texture — so it costs one draw call and degrades to nothing at LOW quality with
## everything else in the frame.
##
## ⚠ PARENTED TO THE ARENA, NEVER TO THE BLINKER. The whole point is a mark at the
## place the body is no longer standing; parenting to the body would drag the origin
## star to the destination on the same frame it was drawn.

## Total life. Short — a teleport reads instantly or not at all, and a lingering mark
## turns into litter in a fight with two blinking classes in it.
const LIFE: float = 0.26
## How long the connecting streak lasts, as a fraction of LIFE. Shorter than the
## stars: the line is a "these are one event" cue, not a trail to look at.
const STREAK_FRACTION: float = 0.55
## Star size at full pop, px. Read against a ~31 px rig: big enough to see past the
## body, small enough not to look like a spell.
const STAR_RADIUS: float = 22.0
## The waist of each star point, as a fraction of its radius. Small = needle-sharp
## points, which is what makes it read as a star rather than as a cross.
const STAR_WAIST: float = 0.16
## Half-width of the streak at the origin end. It tapers to a point at the far end.
const STREAK_HALF: float = 7.0
## Beyond this the streak is not drawn at all: a 20 px hop has no direction worth
## announcing, and a line that short reads as a smudge on the body.
const MIN_STREAK_DISTANCE: float = 34.0

var _origin: Vector2 = Vector2.ZERO
var _dest: Vector2 = Vector2.ZERO
var _tint: Color = Color(0.75, 0.85, 1.0)
var _t: float = 0.0


## Mark a teleport from `origin` to `dest`, both in WORLD space. `parent` should be
## the arena (`hero.get_parent()`), never the body that moved.
##
## Silently does nothing without a parent in the tree, so a headless suite or a
## capture tool that stages a blink with no scene around it does not have to know
## this exists.
static func spawn(parent: Node, origin: Vector2, dest: Vector2,
		tint: Color = Color(0.75, 0.85, 1.0)) -> BlinkSpark:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var s := BlinkSpark.new()
	s._origin = origin
	s._dest = dest
	s._tint = tint
	# Above the fighters, below nothing in particular — same shelf `SwingArc` uses.
	s.z_index = 2
	s.z_as_relative = false
	parent.add_child(s)
	# The node draws in its own local space and both points are world, so it must sit
	# at the world origin or every mark is offset by wherever it happened to be added.
	s.global_position = Vector2.ZERO
	return s


## Stretch a live spark to a new destination instead of stacking another one on top
## of it.
##
## ⚠ THIS EXISTS FOR CRESCENT STEP, and anything shaped like it. That spell is six
## vetted 40 px hops through `Hero.blink_to` inside 0.22 s — six separate sparks with
## six stars and six streaks piled along one 240 px lane, which is a mess where a
## single clean streak is the picture. Merging keeps the origin where the body
## actually left from and walks the far end along with it, so a multi-hop verb draws
## exactly one teleport, because that is what it is.
func extend(dest: Vector2) -> void:
	_dest = dest
	# Wind the clock back a little so the arrival star has room to pop at the NEW far
	# end. Without this a late hop lands on a star that is already fading out.
	_t = minf(_t, LIFE * 0.35)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var u: float = clampf(_t / LIFE, 0.0, 1.0)
	var fade: float = 1.0 - u
	var hot: Color = Color(
		minf(_tint.r * 1.7 + 0.45, 3.0), minf(_tint.g * 1.7 + 0.45, 3.0),
		minf(_tint.b * 1.7 + 0.45, 3.0), fade)
	# 3 — the streak, drawn FIRST so both stars sit on top of it.
	var span: Vector2 = _dest - _origin
	if span.length() >= MIN_STREAK_DISTANCE:
		var su: float = clampf(_t / (LIFE * STREAK_FRACTION), 0.0, 1.0)
		if su < 1.0:
			var dir: Vector2 = span.normalized()
			var perp: Vector2 = dir.orthogonal()
			var half: float = STREAK_HALF * (1.0 - su)
			draw_colored_polygon(PackedVector2Array([
				_origin + perp * half, _origin - perp * half, _dest,
			]), Color(_tint.r, _tint.g, _tint.b, 0.45 * (1.0 - su)))
	# 1 — the origin star COLLAPSES: full size at t=0, nothing at the end.
	_star(_origin, STAR_RADIUS * (1.0 - u), hot)
	# 2 — the destination star SNAPS OUT: a fast ease so the arrival is the sharper
	# of the two reads. A linear grow would make leaving and arriving look identical,
	# and the arrival is the one the eye needs to find.
	_star(_dest, STAR_RADIUS * sqrt(u) * (0.4 + 0.6 * fade), hot)


## A four-point star as one polygon: alternating long points and a tight waist.
## `draw_polyline` would give a constant-width outline, which reads as a cross.
func _star(at: Vector2, radius: float, col: Color) -> void:
	if radius <= 0.5:
		return
	var pts := PackedVector2Array()
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var r: float = radius if i % 2 == 0 else radius * STAR_WAIST
		pts.append(at + Vector2.from_angle(a) * r)
	draw_colored_polygon(pts, col)
