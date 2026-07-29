# SHADOW STEP redesign — the destination blast, and the dodge window that makes it
# fair. Locks the four promises the redesign is built on:
#   1. the teleport is instant but the DAMAGE is not — nothing lands during the tell
#   2. that tell is a real dodge budget — stepping out of the ring saves you
#   3. damage never leaves the drawn radius (the maker's "spells shouldn't be able
#      to get out the radius")
#   4. the old path-crossing line damage is GONE — standing between the two points
#      is safe now
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice_test_blink_blast.gd
extends SceneTree

# Loaded by PATH at runtime, never preloaded and never named as a class: naming
# BlinkStrike here would early-compile its Sfx/Juice autoload references before the
# main loop has registered the autoload globals. Same reason SpellCaster load()s
# every spectacle by path (and the reason this whole suite runs from _process).
const BLINK_PATH: String = "res://scripts/combat/BlinkStrike.gd"

var failed: int = 0
var _ran: bool = false


## A stand-in for Enemy: everything the blast duck-types against, and nothing else.
class FakeEnemy:
	extends Node2D
	var taken: int = 0
	var statuses: int = 0
	var shoves: Vector2 = Vector2.ZERO

	func _ready() -> void:
		add_to_group("enemy")

	func take_damage(amount: int, _tint: Color = Color.WHITE) -> void:
		taken += amount

	func apply_status(_element_id: int) -> void:
		statuses += 1

	func apply_knockback(impulse: Vector2) -> void:
		shoves += impulse


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_radius_geometry()
	_test_nothing_lands_during_the_tell()
	_test_the_dodge_actually_works()
	_test_damage_stays_inside_the_drawn_radius()
	_test_no_damage_along_the_crossed_path()
	_test_telegraph_is_published_at_the_destination()
	_test_safe_blast_point_is_a_noop_without_physics()
	if failed == 0:
		print("Blink blast tests: all PASS")
		quit(0)
	else:
		printerr("Blink blast tests: %d FAILED" % failed)
		quit(1)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failed += 1
		printerr("FAIL: ", msg)


func _script() -> GDScript:
	return load(BLINK_PATH) as GDScript


## A fresh arena per test: the spectacle spawns VFX under get_parent(), and every
## test wants its own "enemy" group population.
func _arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a


func _enemy(arena: Node, at: Vector2) -> FakeEnemy:
	var e := FakeEnemy.new()
	e.position = at
	arena.add_child(e)
	return e


## Cast a blink from `from` to `to` and hand back the live spectacle, un-advanced —
## the caller drives time so each test owns its own moment.
func _cast(arena: Node, from: Vector2, to: Vector2) -> Node2D:
	var b: Node2D = _script().new()
	arena.add_child(b)
	b.call("strike", from, to, Color(0.6, 0.35, 0.95), 40, "shadow")
	return b


# ---------------------------------------------------------------------- geometry
## The whole damage model is one radius query, so its boundary IS the spell's
## contract. `<=` at exactly the radius: what is drawn on the ring is still inside.
func _test_radius_geometry() -> void:
	var s: GDScript = _script()
	var c := Vector2(200.0, -50.0)
	var inside := Node2D.new()
	inside.position = c + Vector2(30.0, 0.0)
	var edge := Node2D.new()
	edge.position = c + Vector2(s.BLAST_RADIUS, 0.0)
	var outside := Node2D.new()
	outside.position = c + Vector2(s.BLAST_RADIUS + 0.5, 0.0)
	var hit: Array = s.targets_in_radius(c, s.BLAST_RADIUS, [inside, edge, outside])
	_expect(hit.has(inside), "a body inside the radius is caught")
	_expect(hit.has(edge), "a body exactly ON the radius is caught (<=)")
	_expect(not hit.has(outside), "a body half a pixel outside is NOT caught")
	inside.free()
	edge.free()
	outside.free()


# ------------------------------------------------------------- the dodge window
## The teleport is instant; the damage is not. If this ever goes green-to-red the
## spell has become an undodgeable point-and-delete, which the locked design rule
## forbids outright.
func _test_nothing_lands_during_the_tell() -> void:
	var s: GDScript = _script()
	var arena: Node2D = _arena()
	var dest := Vector2(600.0, 0.0)
	var victim: FakeEnemy = _enemy(arena, dest)          # standing exactly where we arrive
	var b: Node2D = _cast(arena, Vector2.ZERO, dest)
	b.call("advance", s.BLAST_TELL * 0.5)
	_expect(victim.taken == 0, "no damage half-way through the dodge budget (got %d)" % victim.taken)
	b.call("advance", s.BLAST_TELL * 0.5 + 0.01)         # cross the tell
	_expect(victim.taken > 0, "the blast lands once the tell elapses")
	_expect(victim.statuses == 1, "the blast applies its element ailment exactly once")
	_expect(victim.shoves != Vector2.ZERO, "the blast shoves what it caught")
	arena.free()


## The budget has to BUY something. An enemy that uses it to walk clear of the ring
## takes nothing at all — that is the difference between a tell and a decoration.
func _test_the_dodge_actually_works() -> void:
	var s: GDScript = _script()
	var arena: Node2D = _arena()
	var dest := Vector2(600.0, 0.0)
	var dodger: FakeEnemy = _enemy(arena, dest)
	var b: Node2D = _cast(arena, Vector2.ZERO, dest)
	b.call("advance", s.BLAST_TELL * 0.6)
	dodger.position = dest + Vector2(s.BLAST_RADIUS + 20.0, 0.0)   # steps out of the ring
	b.call("advance", s.BLAST_TELL * 0.4 + 0.01)
	_expect(dodger.taken == 0, "stepping out of the ring during the tell takes zero damage")
	arena.free()


# ------------------------------------------------ damage stays inside the drawing
## Maker, verbatim: "the spells shouldn't be able to get out the radius". The ring
## the Telegraph draws and the query _detonate runs are the same number, so a body a
## couple of pixels past the edge must be untouched even though it LOOKS close.
func _test_damage_stays_inside_the_drawn_radius() -> void:
	var s: GDScript = _script()
	var arena: Node2D = _arena()
	var dest := Vector2(-400.0, 120.0)
	var inside: FakeEnemy = _enemy(arena, dest + Vector2(s.BLAST_RADIUS - 2.0, 0.0))
	var outside: FakeEnemy = _enemy(arena, dest + Vector2(s.BLAST_RADIUS + 2.0, 0.0))
	var b: Node2D = _cast(arena, Vector2.ZERO, dest)
	b.call("advance", s.BLAST_TELL + 0.01)
	_expect(inside.taken > 0, "just inside the drawn ring is hit")
	_expect(outside.taken == 0, "just OUTSIDE the drawn ring takes nothing (got %d)" % outside.taken)
	_expect(outside.shoves == Vector2.ZERO, "and is not shoved either")
	arena.free()


## The behaviour this redesign deliberately DELETED. The old spell cut a corridor
## from `from` to `to`, which is what made it read as a dash-with-a-slot-cost; a
## body sitting mid-path is now simply a bystander.
func _test_no_damage_along_the_crossed_path() -> void:
	var s: GDScript = _script()
	var arena: Node2D = _arena()
	var from := Vector2.ZERO
	var dest := Vector2(600.0, 0.0)
	var bystander: FakeEnemy = _enemy(arena, Vector2(300.0, 0.0))   # dead centre of the old cut
	var b: Node2D = _cast(arena, from, dest)
	b.call("advance", s.BLAST_TELL + 0.01)
	_expect(bystander.taken == 0, "a body on the crossed path takes nothing any more")
	arena.free()


# ------------------------------------------------------------------- the tell UI
## The tell must be findable and honest: BotDodge (and any future brain) reads the
## danger off the `telegraph` group, so a blast whose ring never joined that group
## is undodgeable-by-construction for everything that isn't a human.
func _test_telegraph_is_published_at_the_destination() -> void:
	var s: GDScript = _script()
	var arena: Node2D = _arena()
	var dest := Vector2(140.0, -220.0)
	var b: Node2D = _cast(arena, Vector2.ZERO, dest)
	var found: Telegraph = null
	for t: Node in get_nodes_in_group(Telegraph.GROUP):
		if t is Telegraph and (t as Telegraph).get_parent() == b:
			found = t as Telegraph
	_expect(found != null, "the arrival tell is published to the telegraph group")
	if found != null:
		var shape: Dictionary = found.danger_shape()
		_expect((shape.get("center") as Vector2).is_equal_approx(dest),
			"the tell sits at the destination, in world space (got %s)" % [shape.get("center")])
		_expect(is_equal_approx(float(shape.get("radius")), s.BLAST_RADIUS),
			"the drawn danger radius IS the blast radius")
		_expect(is_equal_approx(found.time_to_impact(), s.BLAST_TELL),
			"the countdown starts at the full dodge budget")
	arena.free()


# ------------------------------------------------------------ destination safety
## The landing check is a physics query, and a bare headless run has no world. It
## must degrade to "leave the point alone" rather than throwing or snapping the
## blast home — every other headless tool in tools/ casts this spell without physics.
func _test_safe_blast_point_is_a_noop_without_physics() -> void:
	var s: GDScript = _script()
	var to := Vector2(512.0, -64.0)
	_expect(s.safe_blast_point(null, Vector2.ZERO, to) == to,
		"with no physics world the requested destination survives untouched")
