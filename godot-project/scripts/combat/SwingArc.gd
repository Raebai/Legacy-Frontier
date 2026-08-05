class_name SwingArc
extends Node2D
## THE CRESCENT A HEAVY SWING THROWS. A short curved edge that leaves the blade,
## travels about as far as the swing already reaches, and fades.
##
## Maker: *"each swing of the sword basic attack should shoot out a short curved
## attack with low range to explain why the range is big for its basic attack"*.
##
## ⚠ IT IS EXPLANATORY, NOT A SECOND HITBOX, AND THAT IS THE WHOLE DESIGN. The
## Swordsaint's melee already reaches 86 px — the longest basic in the roster after
## the Juggernaut's hammer — and the complaint is precisely that nothing on screen
## SAID so: a stick figure waved a blade and something died most of a body-length
## away. Giving the crescent its own damage would not fix that, it would double the
## class's basic attack and quietly make the roster's slowest swinger its highest
## damage-per-swing. So this draws the reach that already exists.
##
## The consequence worth knowing: it can never desync from the hitbox, because it is
## told the reach it has to explain and travels exactly that far. A damaging twin
## would have needed its own range, and two ranges drift.
##
## ⚠ NO PHYSICS, NO AREA, NO COLLISION LAYER. It is a `Node2D` that draws and dies,
## which is also why it costs nothing to spawn on every swing of a 0.42 s cooldown.

## How long the crescent lives. Short — it is punctuation on a swing, and a crescent
## still hanging in the air when the next swing starts reads as a projectile that
## failed to hit something.
const LIFE: float = 0.22
## How wide the arc opens, in radians. A little over a quarter turn: enough to read as
## a slash, not so much that it becomes a ring.
const SWEEP: float = 1.35
## Fraction of the reach the crescent starts at, so it leaves the BLADE rather than
## the navel.
const START_FRAC: float = 0.35

var _dir: Vector2 = Vector2.RIGHT
var _reach: float = 86.0
var _color: Color = Color(0.92, 0.95, 1.0)
var _age: float = 0.0
var _from: Vector2 = Vector2.ZERO


## Throw a crescent from `at` along `dir`, reaching `reach` px. Null-safe: silently
## does nothing without a parent in the tree, the same contract every other spectacle
## helper in this codebase offers.
static func spawn(parent: Node, at: Vector2, dir: Vector2, reach: float,
		color: Color) -> void:
	if parent == null or not parent.is_inside_tree() or dir == Vector2.ZERO:
		return
	# Garnish, and the first thing to skip when the arena is already at its effect
	# budget — exactly like `ScorchDecal`. Nothing reads it to make a decision.
	if SpellReactorNode.vfx_over_budget():
		return
	var a := SwingArc.new()
	a._dir = dir.normalized()
	a._reach = maxf(reach, 20.0)
	a._color = color
	a._from = at
	a.z_index = 1          # over the floor and the body, under the HUD
	parent.add_child(a)
	a.global_position = Vector2.ZERO   # drawn in WORLD space, like every spectacle here


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_age / LIFE, 0.0, 1.0)
	# Travels out and thins as it goes — the edge is sharpest the moment it leaves the
	# blade, which is when the swing it belongs to is landing.
	var dist: float = lerpf(_reach * START_FRAC, _reach, t)
	var centre: Vector2 = _from + _dir * dist
	var base: float = _dir.angle()
	var fade: float = 1.0 - t
	# The crescent, as an arc around the travel direction rather than a straight bar:
	# the curve is what makes it read as something a blade threw.
	var r: float = _reach * 0.42
	draw_arc(centre - _dir * r * 0.65, r, base - SWEEP * 0.5, base + SWEEP * 0.5, 22,
		Color(_color.r, _color.g, _color.b, 0.85 * fade), maxf(4.5 * fade, 1.2), true)
	# A brighter inner line one notch tighter, so the edge has a hot core the way
	# every other slash in this game does.
	draw_arc(centre - _dir * r * 0.65, r * 0.88, base - SWEEP * 0.42, base + SWEEP * 0.42,
		18, Color(1.4, 1.4, 1.5, 0.6 * fade), maxf(2.0 * fade, 0.8), true)
