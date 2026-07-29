# Run: godot --headless --path godot-project --script tools/slice8_test_ults.gd
#
# Guards the ULT DISTINCTNESS + RADIUS HONESTY pass over the four ultimate
# spectacles (StarConvergence, DivineRay, MeteorSigil, EnergyNova).
#
# Two things are pinned here, and the second one is the unusual one:
#
#  1. RADIUS HONESTY — "the spells shouldn't be able to get out the radius".
#     Every selector gets a NEGATIVE case: a body one pixel outside the drawn
#     footprint must take nothing. Two of these fixed real lies (the nova damaged
#     1.24x wider than its ring was ever drawn; both vertical spells damaged a
#     ball at the foot of a shape that is drawn hundreds of pixels tall).
#
#  2. IDENTITY — the maker's verdict was "most ults look the same, just recolours
#     or retypes of the same meteor type of thing". Most of that fix is visual and
#     ONLY a human at F5 can sign it off. But the parts of it that are DATA —
#     each meteor family having a different footprint shape, a different timing
#     envelope, and fire sweeping in a direction rather than popping at random —
#     are testable, and pinning them is what stops the three families quietly
#     converging back into one spell with three palettes the next time someone
#     tunes a constant. A test that says "these three numbers must differ" is a
#     weak statement about beauty and a strong statement about intent.
#
# The scripts are load()ed at RUNTIME (never referenced by class_name) because
# they reference the Sfx AUTOLOAD, which only registers once the main loop is
# live — a compile-time class_name reference would fail to resolve it and (per
# the ledger's test trap) print a false PASS. Runs on the first _process frame,
# by which point the autoloads exist.
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
	"nova_draw_matches_damage",
	"nova_radius_negative",
	"convergence_radius_negative",
	"convergence_promises",
	"ray_column_shape",
	"ray_factors_within_drawing",
	"colossus_column_shape",
	"meteor_radius_negative",
	"meteor_families_differ",
	"meteor_fire_sweeps",
	"meteor_spread_matches_telegraph",
]

var _fails: int = 0
var _completed: Dictionary = {}

const CONVERGENCE_PATH: String = "res://scripts/combat/StarConvergence.gd"
const RAY_PATH: String = "res://scripts/combat/DivineRay.gd"
const METEOR_PATH: String = "res://scripts/combat/MeteorSigil.gd"
const NOVA_PATH: String = "res://scenes/combat/EnergyNova.tscn"

## Far from the origin on purpose: a selector that accidentally resolves at the
## arena origin (the classic "spectacle transform is (0,0)" trap) then finds
## nothing here and the test fails loudly instead of passing by luck.
const FAR: Vector2 = Vector2(9000.0, 4000.0)

var _ran: bool = false


class StubEnemy:
	extends CharacterBody2D
	var damage_taken: int = 0
	var last_knockback: Vector2 = Vector2.ZERO

	func take_damage(amount: int) -> void:
		damage_taken += amount

	func apply_knockback(vec: Vector2) -> void:
		last_knockback = vec


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_nova_draw_matches_damage()
	_test_nova_radius_negative()
	_test_convergence_radius_negative()
	_test_convergence_promises()
	_test_ray_column_shape()
	_test_ray_factors_within_drawing()
	_test_colossus_column_shape()
	_test_meteor_radius_negative()
	_test_meteor_families_differ()
	_test_meteor_fire_sweeps()
	_test_meteor_spread_matches_telegraph()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice8 ult tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice8 ult tests: all PASS")
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


func _node_at(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	root.add_child(n)
	n.global_position = pos
	return n


func _enemy_at(pos: Vector2) -> StubEnemy:
	var e := StubEnemy.new()
	e.add_to_group("enemy")
	root.add_child(e)
	e.global_position = pos
	return e


# ────────────────────────────────────────────────────────── EnergyNova

## THE REGRESSION GUARD FOR THE LIE THAT WAS ACTUALLY FOUND. The shockwave used
## to be drawn to `NOVA_RADIUS * 0.62 * 1.3` (~109 px) while the damage query used
## the raw 135 px, so the nova hit 1.24x further than it drew. The fix pinned the
## drawn ring to the damage radius; this asserts the factor cannot silently drift
## back off 1.0 — which is the only way that lie can return.
func _test_nova_draw_matches_damage() -> void:
	var nova: Node2D = (load(NOVA_PATH) as PackedScene).instantiate()
	root.add_child(nova)
	var factor: float = float(nova.VISUAL_RADIUS_FACTOR)
	_expect(
		absf(factor - 1.0) < 0.0001,
		"nova's drawn ring ends exactly on its damage radius (VISUAL_RADIUS_FACTOR=%f, want 1.0)" % factor
	)
	nova.queue_free()
	_completes("nova_draw_matches_damage")


func _test_nova_radius_negative() -> void:
	var nova: Node2D = (load(NOVA_PATH) as PackedScene).instantiate()
	root.add_child(nova)
	nova.global_position = FAR
	var r: float = float(nova.NOVA_RADIUS)
	var inside: StubEnemy = _enemy_at(FAR + Vector2(r - 1.0, 0.0))
	var outside: StubEnemy = _enemy_at(FAR + Vector2(r + 1.0, 0.0))
	nova.call("_apply_nova_damage")
	_expect(inside.damage_taken > 0, "nova hits a body 1 px inside the drawn ring")
	_expect(
		outside.damage_taken == 0,
		"NEGATIVE: nova does NOT hit a body 1 px outside the drawn ring (got %d)" % outside.damage_taken
	)
	inside.queue_free()
	outside.queue_free()
	nova.queue_free()
	_completes("nova_radius_negative")


# ────────────────────────────────────────────────── StarConvergence

func _test_convergence_radius_negative() -> void:
	var conv: GDScript = load(CONVERGENCE_PATH)
	var radius: float = 160.0
	var inside: Node2D = _node_at(FAR + Vector2(radius - 1.0, 0.0))
	var outside: Node2D = _node_at(FAR + Vector2(radius + 1.0, 0.0))
	var hit: Array = conv.targets_in_radius(FAR, radius, [inside, outside])
	_expect(hit.has(inside), "convergence hits a body 1 px inside the footprint")
	_expect(
		not hit.has(outside),
		"NEGATIVE: convergence does NOT hit a body 1 px outside the footprint"
	)
	inside.queue_free()
	outside.queue_free()
	_completes("convergence_radius_negative")


## The two promises this spell's redesign rests on, both of which are silently
## breakable by a one-character edit:
##   * the DODGE BUDGET is real (the longest telegraph in the game, because it is
##     the biggest hit — bigger spectacle must buy MORE counterplay, not less);
##   * the residue never claims more ground than the damage did. A starburst scar
##     drawn out to the ignition ring would tell the player the spell reached 3x
##     further than it can.
func _test_convergence_promises() -> void:
	var conv: GDScript = load(CONVERGENCE_PATH)
	var charge: float = float(conv.CHARGE_TIME)
	var close: float = float(conv.CONVERGE_TIME)
	var window: float = float(conv.DODGE_WINDOW)
	_expect(
		absf(window - (charge + close)) < 0.0001,
		"DODGE_WINDOW is the whole tell (%f vs %f)" % [window, charge + close]
	)
	_expect(
		window >= 1.0,
		"the dodge budget is a real reaction window, >= 1.0 s (got %f)" % window
	)
	_expect(
		float(conv.SCAR_REACH) <= 1.0,
		"the starburst scar never reaches past the damaged footprint (SCAR_REACH=%f)" % float(conv.SCAR_REACH)
	)
	_completes("convergence_promises")


# ───────────────────────────────────────────────────────────── DivineRay

## THE SHAPE FIX, in its clearest form. Damage used to be one `_radius` ball at
## the foot of a pillar drawn from the sky to the ground, so a body standing HIGH
## inside the column — on a platform, mid-jump — had light drawn straight through
## it and took nothing. It now damages the column as a capsule.
##
## The negative case is the one that keeps the fix honest: widening a hit shape is
## easy, and the test that matters is that it did not widen everywhere.
func _test_ray_column_shape() -> void:
	var ray: Node2D = (load(RAY_PATH) as GDScript).new()
	root.add_child(ray)
	var radius: float = 70.0
	ray.set("_ground", FAR)
	ray.set("_radius", radius)
	var half: float = radius * float(ray.COLUMN_HALF_FACTOR)
	var height: float = float(ray.SKY_HEIGHT)

	var at_foot: Node2D = _node_at(FAR + Vector2(radius - 2.0, 0.0))
	var up_in_beam: Node2D = _node_at(FAR + Vector2(0.0, -height * 0.6))
	var up_beside_beam: Node2D = _node_at(FAR + Vector2(half + 12.0, -height * 0.6))
	var pool: Array = [at_foot, up_in_beam, up_beside_beam]
	var hit: Array = ray.call("_column_targets", height, half, radius, pool)

	_expect(hit.has(at_foot), "Judgment still hits the ground footprint")
	_expect(
		hit.has(up_in_beam),
		"Judgment hits a body high up INSIDE the drawn column (this is the fix)"
	)
	_expect(
		not hit.has(up_beside_beam),
		"NEGATIVE: Judgment does NOT hit a body beside the column at the same height"
	)
	for n: Node2D in pool:
		n.queue_free()
	ray.queue_free()
	_completes("ray_column_shape")


## THE BOUND, not just the shape.
##
## `_test_ray_column_shape` derives its probe points FROM the factor under test,
## so it stays self-consistent if someone widens the factor — mutating
## COLUMN_HALF_FACTOR from 0.5 to 5.0 left it happily green, which is exactly the
## kind of hole that lets a hitbox quietly inflate behind a passing suite. This
## pins the factors against what is actually DRAWN instead:
##   * the light column's bright band is `_radius * 0.9` wide, so half of it is
##     0.45; anything past ~0.6 is damaging air the pillar never covered.
##   * the Colossus's slab stack is `_radius * 0.95` wide at the base (half 0.475)
##     and its broken-rubble hump spans `+/- _radius * 0.85`.
## These are ceilings on a hit shape, so they are one-sided on purpose: making a
## spell damage LESS than it draws is disappointing, making it damage MORE is the
## bug the maker reported.
func _test_ray_factors_within_drawing() -> void:
	var ray: GDScript = load(RAY_PATH)
	_expect(
		float(ray.COLUMN_HALF_FACTOR) <= 0.6,
		"Judgment's damaging half-width stays inside its drawn column (%f > 0.6)"
			% float(ray.COLUMN_HALF_FACTOR)
	)
	_expect(
		float(ray.STONE_COLUMN_FACTOR) <= 0.5,
		"the Colossus's damaging half-width stays inside its drawn slabs (%f > 0.5)"
			% float(ray.STONE_COLUMN_FACTOR)
	)
	_expect(
		float(ray.STONE_BASE_FACTOR) <= 0.85,
		"the Colossus's base splash stays inside its drawn rubble hump (%f > 0.85)"
			% float(ray.STONE_BASE_FACTOR)
	)
	_completes("ray_factors_within_drawing")


## The Colossus had the same bug in both directions at once: it damaged a circle
## WIDER than the rubble it draws at ground level, and blind to everything above
## knee height on a 300 px spire. Now: tall and narrow, with the wider splash only
## at the foot where the broken slabs actually are.
func _test_colossus_column_shape() -> void:
	var ray: Node2D = (load(RAY_PATH) as GDScript).new()
	root.add_child(ray)
	var radius: float = 80.0
	ray.set("_ground", FAR)
	ray.set("_radius", radius)
	var half: float = radius * float(ray.STONE_COLUMN_FACTOR)
	var base: float = radius * float(ray.STONE_BASE_FACTOR)
	var height: float = float(ray.STONE_HEIGHT)

	var up_the_spire: Node2D = _node_at(FAR + Vector2(0.0, -height * 0.7))
	var past_the_rubble: Node2D = _node_at(FAR + Vector2(base + 3.0, 0.0))
	var beside_the_spire: Node2D = _node_at(FAR + Vector2(half + 15.0, -height * 0.7))
	var pool: Array = [up_the_spire, past_the_rubble, beside_the_spire]
	var hit: Array = ray.call("_column_targets", height, half, base, pool)

	_expect(
		hit.has(up_the_spire),
		"the Colossus hits a body level with the middle of the drawn spire (this is the fix)"
	)
	_expect(
		not hit.has(past_the_rubble),
		"NEGATIVE: the Colossus does NOT hit past the drawn rubble hump at ground level"
	)
	_expect(
		not hit.has(beside_the_spire),
		"NEGATIVE: the Colossus does NOT hit a body standing clear of the spire's width"
	)
	for n: Node2D in pool:
		n.queue_free()
	ray.queue_free()
	_completes("colossus_column_shape")


# ──────────────────────────────────────────────────────────── MeteorSigil

func _test_meteor_radius_negative() -> void:
	var meteor: GDScript = load(METEOR_PATH)
	var r: float = float(meteor.METEOR_IMPACT_RADIUS)
	var inside: Node2D = _node_at(FAR + Vector2(r - 1.0, 0.0))
	var outside: Node2D = _node_at(FAR + Vector2(r + 1.0, 0.0))
	var hit: Array = meteor.targets_in_radius(FAR, r, [inside, outside])
	_expect(hit.has(inside), "a meteor hits a body 1 px inside its impact radius")
	_expect(
		not hit.has(outside),
		"NEGATIVE: a meteor does NOT hit a body 1 px outside its impact radius"
	)
	inside.queue_free()
	outside.queue_free()
	_completes("meteor_radius_negative")


## THE ANTI-RECOLOUR GUARD. Fire, earth and shadow must differ in the two things
## the eye actually reads at a glance — the SHAPE of the footprint and the SHAPE
## of the timing — not merely in palette. If someone later flattens these back to
## a single spread and a single window, the three families are once again the same
## spell three times and this test is the thing that says so out loud.
func _test_meteor_families_differ() -> void:
	var made: Array = []
	var spreads: Dictionary = {}
	var windows: Dictionary = {}
	for fx: String in ["fire", "earth", "shadow"]:
		var m: Node2D = (load(METEOR_PATH) as GDScript).new()
		root.add_child(m)
		m.set("_effect", fx)
		spreads[fx] = float(m.call("_spread_factor"))
		windows[fx] = float(m.call("_barrage_time"))
		made.append(m)
	_expect(
		float(spreads["fire"]) > float(spreads["shadow"]),
		"fire's front is WIDER than shadow's (%f vs %f)" % [spreads["fire"], spreads["shadow"]]
	)
	_expect(
		float(spreads["earth"]) < float(spreads["shadow"]),
		"earth's cluster is TIGHTER than shadow's (%f vs %f)" % [spreads["earth"], spreads["shadow"]]
	)
	_expect(
		float(windows["earth"]) < float(windows["shadow"])
			and float(windows["shadow"]) < float(windows["fire"]),
		"three distinct timing envelopes, earth < shadow < fire (%f / %f / %f)"
			% [windows["earth"], windows["shadow"], windows["fire"]]
	)
	for m: Node2D in made:
		m.queue_free()
	_completes("meteor_families_differ")


## Fire is THE BOMBARDMENT: its strikes are ordered along the entry diagonal so
## the barrage reads as one wave crossing the ground instead of as popcorn.
## Ordering an existing barrage costs nothing and is the biggest readability win
## in the file, so it is worth a pin.
##
## SLANT brings the meteors in from the upper RIGHT, so the wave must start at the
## highest x and travel left: after scheduling, delays must be non-increasing in x.
func _test_meteor_fire_sweeps() -> void:
	var m: Node2D = (load(METEOR_PATH) as GDScript).new()
	root.add_child(m)
	m.set("_effect", "fire")
	var rolls: Array = []
	# Deliberately shuffled input: a scheduler that merely preserved input order
	# would pass a pre-sorted list by accident.
	for x: float in [-200.0, 300.0, -50.0, 150.0, 0.0, -320.0]:
		rolls.append({
			"delay": 0.0, "from": Vector2.ZERO, "to": FAR + Vector2(x, 0.0),
			"landed": false, "seed": 0.0, "spin": 0.0, "verts": PackedVector2Array(),
		})
	m.set("_meteors", rolls)
	m.call("_schedule_barrage")
	var scheduled: Array = m.get("_meteors")
	var window: float = float(m.call("_barrage_time"))
	# Jitter is bounded by SWEEP_JITTER of the window, so consecutive slots can
	# never overtake each other by more than that; compare with the slack.
	var slack: float = window * float(m.SWEEP_JITTER)
	for i: int in scheduled.size() - 1:
		var a: Dictionary = scheduled[i]
		var b: Dictionary = scheduled[i + 1]
		_expect(
			(a["to"] as Vector2).x >= (b["to"] as Vector2).x,
			"fire's barrage is ordered right-to-left along its entry diagonal"
		)
		_expect(
			float(a["delay"]) <= float(b["delay"]) + slack,
			"fire's strike delays advance with the sweep (%f then %f)" % [a["delay"], b["delay"]]
		)
	m.queue_free()
	_completes("meteor_fire_sweeps")


## THE TELEGRAPH MUST PROMISE THE AREA THE STRIKES ARE ROLLED IN. Widening fire's
## front was the change most likely to reintroduce "the spell got out of its
## radius": if the per-family spread multiplier fed the scatter but the tell was
## still drawn at the raw `radius`, fire would rain 70% wider than the danger zone
## it advertised. One stored `_spread` feeds both, and this pins that it is the
## multiplied extent rather than the raw radius.
func _test_meteor_spread_matches_telegraph() -> void:
	var radius: float = 150.0
	for fx: String in ["fire", "earth", "shadow"]:
		var m: Node2D = (load(METEOR_PATH) as GDScript).new()
		root.add_child(m)
		m.set("target_group", "nobody")  # keep the harness out of the damage path
		m.call("rain", FAR, Color.WHITE, radius, 10, 6, fx)
		var spread: Vector2 = m.get("_spread")
		var want_x: float = radius * float(m.GROUND_SCATTER.x) * float(m.call("_spread_factor"))
		var want_y: float = radius * float(m.GROUND_SCATTER.y)
		_expect(
			absf(spread.x - want_x) < 0.001,
			"%s's telegraph extent is its real scatter extent (x %f vs %f)" % [fx, spread.x, want_x]
		)
		_expect(
			absf(spread.y - want_y) < 0.001,
			"%s's ground band is unchanged (y %f vs %f)" % [fx, spread.y, want_y]
		)
		# Every rolled strike must land inside the advertised ellipse.
		for entry: Dictionary in (m.get("_meteors") as Array):
			var d: Vector2 = (entry["to"] as Vector2) - FAR
			var norm: float = (d.x / maxf(spread.x, 0.001)) ** 2.0 + (d.y / maxf(spread.y, 0.001)) ** 2.0
			_expect(
				norm <= 1.0001,
				"NEGATIVE: no %s strike is rolled outside the drawn danger ellipse (norm %f)" % [fx, norm]
			)
		m.queue_free()
	_completes("meteor_spread_matches_telegraph")
