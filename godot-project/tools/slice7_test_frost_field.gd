# The FROST FIELD rework: the blizzard's rime -> encase -> shatter fuse, and the
# radius contract the maker asked for ("the spells shouldn't be able to get out
# the radius") for both ZoneSpell and IceWall.
#   godot --headless --path godot-project --script tools/slice7_test_frost_field.gd
#
# THE POINT OF THIS FILE IS THE NEGATIVE CASES. A field that damages everything
# it should is trivially true of a field that damages everything full stop; the
# tests that matter are the ones asserting a body a few pixels outside the drawn
# extent takes exactly ZERO. Without those, the mismatch silently comes back.
#
# extends SceneTree (the slice3_test_spell_collision idiom) because the
# integration half needs a real main loop: ZoneSpell drives its fuse from
# _process, and a physics space has to exist for the cover query.
#
# ⚠ NOTHING HERE MAY NAME `ZoneSpell` OR `IceWall` BY class_name. Doing so pulls
# them into this tool's compile-time dependency graph, and they reference the
# `Sfx` autoload, which does not exist as a global identifier until the main loop
# is live — the whole file then fails to compile with "Identifier not found: Sfx".
# So the scripts are load()ed in _run(), statics go through `script.call(...)`
# and constants through `get_script_constant_map()`. Same reason the rest of the
# codebase load()s spell scripts by path instead of by class.
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
	"frost_column",
	"ground_ellipse",
	"cell_height_shared",
	"ice_wall_reach",
	"zone_damage_stays_inside",
	"rime_fuse",
	"rime_decays_when_you_leave",
	"registers_as_a_field",
]

var _fails: int = 0
var _completed: Dictionary = {}

const ZONE_PATH: String = "res://scripts/combat/ZoneSpell.gd"
const WALL_PATH: String = "res://scripts/combat/IceWall.gd"

## Test field geometry. Deliberately NOT the shipped blizzard numbers — the
## contract has to hold for any radius, and hard-coding 135 would let a tweak in
## SpellLibrary quietly invalidate the test.
const AT := Vector2(0.0, 0.0)
const R: float = 120.0

var _zone: GDScript = null
var _wall: GDScript = null
var _zc: Dictionary = {}   # ZoneSpell's constants
var _wc: Dictionary = {}   # IceWall's constants


func _initialize() -> void:
	# Pin the tick rate: the frame counts below are seconds-of-game-time budgets
	# for a fuse measured in seconds, and at the 60 Hz default every one of them
	# would silently mean twice as long.
	Engine.physics_ticks_per_second = 120
	_run()


func _run() -> void:
	# One frame before anything touches the tree. _initialize() runs BEFORE the
	# main loop's first iteration, and a node added to `root` at that moment is not
	# yet "inside the active scene tree" — get_tree() comes back null and absolute
	# get_node paths throw.
	await process_frame
	_zone = load(ZONE_PATH) as GDScript
	_wall = load(WALL_PATH) as GDScript
	_zc = _zone.get_script_constant_map()
	_wc = _wall.get_script_constant_map()
	_test_frost_column()
	_test_ground_ellipse()
	_test_cell_height_shared()
	_test_ice_wall_reach()
	await _test_zone_damage_stays_inside()
	await _test_rime_fuse()
	await _test_rime_decays_when_you_leave()
	_test_registers_as_a_field()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Frost field tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Frost field tests: all PASS")
		quit(0)


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


func _inside(effect: String, radius: float, p: Vector2, at: Vector2 = AT) -> bool:
	return bool(_zone.call(&"footprint_contains", effect, at, radius, p))


func _cell_h(radius: float) -> float:
	return float(_zone.call(&"frost_cell_height", radius))


# ------------------------------------------------------------ pure containment

## FROST is the drawn storm COLUMN: half-width `radius`, from the top of the cell
## down to the bottom of the drawn ground ellipse.
func _test_frost_column() -> void:
	var h: float = _cell_h(R)
	_expect(_inside("frost", R, AT), "the centre of the field is inside it")
	_expect(_inside("frost", R, AT + Vector2(R - 1.0, 0.0)),
		"a body just inside the drawn edge is caught")
	# THE NEGATIVE CASE the whole rework exists to guarantee.
	_expect(not _inside("frost", R, AT + Vector2(R + 1.0, 0.0)),
		"a body ONE PIXEL past the drawn edge takes nothing")
	_expect(not _inside("frost", R, AT + Vector2(-R - 1.0, 0.0)),
		"...and the same on the upwind side")
	# Vertically: inside the storm cell is fair (the snow is drawn up there);
	# above it is not.
	_expect(_inside("frost", R, AT + Vector2(0.0, -h + 2.0)),
		"a body on a ledge inside the storm cell is caught")
	_expect(not _inside("frost", R, AT + Vector2(0.0, -h - 2.0)),
		"a body above the drawn storm cell takes nothing")
	_expect(not _inside("frost", R, AT + Vector2(0.0, R * 0.9)),
		"a body below the drawn ground ellipse takes nothing")
	# A zero footprint (the field still easing open) catches nobody.
	_expect(not _inside("frost", 0.0, AT),
		"a footprint that has not opened yet damages nothing")
	_completes("frost_column")


## Every other zone is the flat ellipse it draws. This is the exact shape of the
## bug that was found: the old code damaged in a FULL CIRCLE of `radius` while
## drawing an ellipse squashed to 0.42, so a body at 0.9r straight up was hit
## while standing more than twice the visible vertical extent away.
func _test_ground_ellipse() -> void:
	var squash: float = float(_zc["GROUND_SQUASH"])
	_expect(_inside("shadow", R, AT + Vector2(R * 0.95, 0.0)),
		"a body inside the ellipse's width is caught")
	_expect(not _inside("shadow", R, AT + Vector2(R + 1.0, 0.0)),
		"a body past the ellipse's width takes nothing")
	_expect(_inside("shadow", R, AT + Vector2(0.0, R * squash - 1.0)),
		"a body inside the ellipse's height is caught")
	_expect(not _inside("shadow", R, AT + Vector2(0.0, R * squash + 1.0)),
		"a body past the ellipse's HEIGHT takes nothing (the old circle hit it)")
	_expect(not _inside("shadow", R, AT + Vector2(0.0, R * 0.9)),
		"the regression case: 0.9r straight up is outside a 0.42-squashed ellipse")
	_expect(_inside("holy", R, AT + Vector2(0.0, 10.0)),
		"the holy heal uses the same ellipse")
	_completes("ground_ellipse")


## The draw and the damage query must read the cell height from ONE function, or
## they drift the moment either is tuned.
func _test_cell_height_shared() -> void:
	var base: float = float(_zc["SQUALL_HEIGHT"])
	var per_r: float = float(_zc["SQUALL_HEIGHT_PER_RADIUS"])
	_expect(is_equal_approx(_cell_h(0.0), base),
		"a zero-radius squall is exactly the base cell height")
	_expect(_cell_h(200.0) > _cell_h(0.0), "a wider squall is a taller squall")
	_expect(is_equal_approx(_cell_h(200.0), base + 200.0 * per_r),
		"cell height is the documented linear form")
	_completes("cell_height_shared")


## IceWall's two reaches, and the invariant that neither exceeds what the wall
## draws while it stands.
func _test_ice_wall_reach() -> void:
	var size: Vector2 = _wc["WALL_SIZE"] as Vector2
	var pad: float = float(_wc["CHILL_PAD"])
	var ypad: float = float(_wc["CHILL_Y_PAD"])
	var pool: float = float(_wc["GROUND_POOL_RADIUS"])
	var shatter_r: float = float(_wc["SHATTER_RADIUS"])
	var base := Vector2(500.0, 300.0)
	var hw: float = size.x * 0.5 + pad
	_expect(bool(_wall.call(&"chill_contains", base, base + Vector2(hw - 1.0, -40.0))),
		"an enemy pressed against the ice is chilled")
	_expect(not bool(_wall.call(&"chill_contains", base, base + Vector2(hw + 1.0, -40.0))),
		"an enemy a pixel clear of the ice is NOT chilled")
	_expect(not bool(_wall.call(&"chill_contains", base,
			base + Vector2(0.0, -size.y - ypad - 1.0))),
		"an enemy above the spires is not chilled")
	_expect(hw <= pool,
		"THE CONTRACT: the chill box (%s) never reaches past the drawn frost pool (%s)"
			% [hw, pool])
	var centre := Vector2(500.0, 240.0)
	_expect(bool(_wall.call(&"shatter_contains", centre, centre + Vector2(shatter_r - 1.0, 0.0))),
		"the shard burst catches a body inside its ring")
	_expect(not bool(_wall.call(&"shatter_contains", centre, centre + Vector2(shatter_r + 1.0, 0.0))),
		"the shard burst does NOT reach a body outside its ring")
	_completes("ice_wall_reach")


# ------------------------------------------------------------ integration

## A stub body in the "enemy" group that records what was done to it. Matches the
## duck-typed surface ZoneSpell actually calls (Enemy.take_damage takes a tint,
## apply_status takes a chain flag).
class StubEnemy extends Node2D:
	var damage: int = 0
	var hits: int = 0
	var statuses: int = 0

	func _ready() -> void:
		add_to_group("enemy")

	func take_damage(amount: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		damage += amount
		hits += 1

	func apply_status(_element: int, _can_chain: bool = true) -> void:
		statuses += 1


func _stub(at: Vector2) -> StubEnemy:
	var s := StubEnemy.new()
	s.global_position = at
	root.add_child(s)
	return s


func _open_blizzard(radius: float, lifetime: float, damage: int = 8) -> Node2D:
	var z: Node2D = _zone.new()
	root.add_child(z)
	z.set("element_id", Elements.Element.ICE)
	z.call("open", AT, Color(0.5, 0.85, 1.0), radius, damage, "frost", lifetime)
	return z


## The headline correctness test. Three bodies: one dead centre, one a hair
## OUTSIDE the drawn half-width, one above the drawn storm cell. Only the first
## may ever be touched.
func _test_zone_damage_stays_inside() -> void:
	var inside: StubEnemy = _stub(AT + Vector2(20.0, -20.0))
	var beside: StubEnemy = _stub(AT + Vector2(R + 6.0, -20.0))
	var above: StubEnemy = _stub(AT + Vector2(0.0, -_cell_h(R) - 20.0))
	var z: Node2D = _open_blizzard(R, 1.2)
	for _i: int in 130:  # ~1.08 s at 120 Hz: several ticks, short of the 1.4 s fuse
		await physics_frame
	_expect(inside.damage > 0, "a body in the squall is chipped (got %d)" % inside.damage)
	_expect(beside.damage == 0 and beside.hits == 0,
		"a body JUST OUTSIDE the drawn radius takes ZERO (got %d over %d hits)"
			% [beside.damage, beside.hits])
	_expect(beside.statuses == 0, "...and is never chilled either")
	_expect(above.damage == 0 and above.statuses == 0,
		"a body above the drawn storm cell takes ZERO (got %d)" % above.damage)
	if is_instance_valid(z):
		z.queue_free()
	inside.queue_free()
	beside.queue_free()
	above.queue_free()
	await physics_frame
	_completes("zone_damage_stays_inside")


## The identity: stand in it long enough and you are sealed, then the casing
## bursts for real damage. This is the beat the field was missing.
func _test_rime_fuse() -> void:
	var shatter_dmg: int = int(_zc["ENCASE_SHATTER_DAMAGE"])
	var victim: StubEnemy = _stub(AT + Vector2(0.0, -20.0))
	# Lifetime comfortably past RIME_TO_ENCASE + ENCASE_HOLD so the whole fuse
	# runs inside the field's life rather than leaning on the outlive-the-fade path.
	var z: Node2D = _open_blizzard(R, 3.5, 4)
	for _i: int in 175:  # ~1.46 s: the meter fills at ~1.4 s
		await physics_frame
	var chip: int = victim.damage
	_expect(victim.statuses >= 3,
		"entry chill + the two encase applications landed (got %d)" % victim.statuses)
	for _i: int in 120:  # ~1.0 s more: the casing holds, then bursts
		await physics_frame
	var burst: int = victim.damage - chip
	_expect(burst >= shatter_dmg,
		"the casing SHATTERED for its payoff (got %d, expected >= %d)" % [burst, shatter_dmg])
	if is_instance_valid(z):
		z.queue_free()
	victim.queue_free()
	await physics_frame
	_completes("rime_fuse")


## The dodge. Walk out and the fuse drains — no encase, no shatter. If this ever
## fails the field is a trap you cannot escape, which is the "ice is not fair"
## failure StatusComponent.FREEZE_DURATION was already shortened to avoid.
func _test_rime_decays_when_you_leave() -> void:
	var shatter_dmg: int = int(_zc["ENCASE_SHATTER_DAMAGE"])
	var runner: StubEnemy = _stub(AT + Vector2(0.0, -20.0))
	var z: Node2D = _open_blizzard(R, 3.5, 4)
	for _i: int in 60:  # ~0.5 s inside: fuse part-lit, well short of 1.4 s
		await physics_frame
	runner.global_position = AT + Vector2(R * 3.0, -20.0)  # sprint clear of the squall
	var at_exit: int = runner.damage
	for _i: int in 240:  # ~2 s outside — far longer than the fuse had left
		await physics_frame
	_expect(runner.damage == at_exit,
		"leaving the squall stops ALL of it (took %d more)" % (runner.damage - at_exit))
	_expect(runner.damage - at_exit < shatter_dmg,
		"a body that left is never encased and never shattered")
	if is_instance_valid(z):
		z.queue_free()
	runner.queue_free()
	await physics_frame
	_completes("rime_decays_when_you_leave")


## The field is now the FIELD side of the reaction matrix. The outcomes are
## no-ops in ReactionOutcomes today, so this asserts the WIRING, not a payoff:
## the participant contract is complete and the authored rows resolve against it.
func _test_registers_as_a_field() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var z: Node2D = _zone.new()
	root.add_child(z)
	z.set("element_id", E.ICE)
	_expect(z.has_method("reaction_shape") and z.has_method("reaction_active")
			and z.has_method("reaction_element") and z.has_method("reaction_form")
			and z.has_method("reaction_consume"),
		"the field implements the whole participant contract")
	_expect(int(z.call("reaction_form")) == F.FIELD, "a zone presents as a FIELD")
	_expect(not bool(z.call("reaction_active")),
		"an unopened field is inert (nothing to react with yet)")
	_expect(SpellGeometry.is_circle(z.call("reaction_shape")),
		"the field's reaction shape is a circle")
	var steam: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.FIELD, E.ICE)
	_expect(String(steam.get("outcome", "")) == "steam_cloud",
		"a fire beam into this field resolves to steam_cloud")
	var charge: Dictionary = ReactionTable.match_rule(F.BEAM, E.LIGHTNING, F.FIELD, E.ICE)
	_expect(String(charge.get("outcome", "")) == "supercharge",
		"a lightning beam through this field resolves to supercharge")
	z.queue_free()
	_completes("registers_as_a_field")
