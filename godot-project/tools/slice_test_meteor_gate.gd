# Run: godot --headless --path godot-project --script tools/slice_test_meteor_gate.gd
#
# THE SKY GATE MUST NOT MOVE THE DAMAGE. The gate added to MeteorSigil is pure
# scenery: it changes where the falling objects are BORN and nothing else. This
# suite is the guard rail on that claim, because the project's most-repeated bug
# is a visual that grew and a hitbox that did not follow (or vice versa) — six
# drawn-vs-damaged mismatches were found in this codebase in one week.
#
# What is pinned here:
#   1. Every rolled impact point lands inside the ellipse the CHARGE TELEGRAPH
#      draws (`_spread`) — the drawn danger area IS the damaged area.
#   2. The gate hangs ABOVE the footprint it feeds, never in it.
#   3. A body just outside METEOR_IMPACT_RADIUS takes nothing (the negative test).
#   4. The gate points are NOT damage sources — nothing is selected at a gate.
#   5. SHADOW opens no gate at all (its identity is an empty sky).
#
# MeteorSigil is load()ed at RUNTIME, never referenced by class_name, for the
# same reason slice4_test_spells does it: the spectacle reaches for the Sfx /
# Juice AUTOLOADS, which only exist once the main loop is live.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read ABORTS the enclosing function and hands back the return
# type's zero value, which under a `failed += _test_x()` idiom reads as "no
# failures". So: failures accumulate on the MEMBER `_fails`, and every test
# records that it reached its last line. A test missing from `_completed` fails
# the suite BY ABSENCE.

## Every test that must run to completion.
const TESTS: Array[String] = [
	"impacts_inside_drawn_footprint",
	"gate_hangs_above_footprint",
	"impact_radius_boundary",
	"gate_is_not_a_damage_source",
	"shadow_opens_no_gate",
]

const METEOR_PATH: String = "res://scripts/combat/MeteorSigil.gd"

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_impacts_inside_drawn_footprint()
	_test_gate_hangs_above_footprint()
	_test_impact_radius_boundary()
	_test_gate_is_not_a_damage_source()
	_test_shadow_opens_no_gate()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails == 0:
		print("meteor gate tests: all PASS")
	else:
		printerr("meteor gate tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("  PASS  ", what)
	else:
		_fails += 1
		printerr("  FAIL  ", what)


func _completes(name: String) -> void:
	_completed[name] = true


## Build a live, rained-on sigil in the tree. In the tree matters: `_open_gates`
## reads the viewport for its in-frame clamp, and MagicCircle needs a real parent.
func _rained(effect: String, center: Vector2, radius: float, count: int) -> Node2D:
	var sigil: Node2D = (load(METEOR_PATH) as GDScript).new()
	root.add_child(sigil)
	sigil.call("rain", center, Color(1, 0.5, 0.2), radius, 20, count, effect)
	return sigil


## 1. THE CORE INVARIANT. `_spread` is what `_draw_charge_telegraph` draws its
## danger ellipse at; the scatter loop rolls impacts within the same `_spread`.
## If a future change lets the gate feed the scatter (e.g. by rolling impacts
## relative to a clamped gate position instead of the aim point), this catches it.
func _test_impacts_inside_drawn_footprint() -> void:
	for effect: String in ["fire", "earth"]:
		var center := Vector2(500.0, 400.0)
		var sigil: Node2D = _rained(effect, center, 135.0, 14)
		var spread: Vector2 = sigil.get("_spread")
		var meteors: Array = sigil.get("_meteors")
		_expect(meteors.size() == 14, "%s rolled every requested impact" % effect)
		var all_inside: bool = true
		for m: Dictionary in meteors:
			var d: Vector2 = (m["to"] as Vector2) - center
			# Normalised ellipse test; 1.001 absorbs float noise only.
			var q: float = (d.x / spread.x) * (d.x / spread.x) + (d.y / spread.y) * (d.y / spread.y)
			if q > 1.001:
				all_inside = false
		_expect(all_inside, "%s: every impact lands inside the DRAWN footprint" % effect)
		sigil.queue_free()
	_completes("impacts_inside_drawn_footprint")


## 2. The clamp may pull the gate down into frame, but never onto the fight.
func _test_gate_hangs_above_footprint() -> void:
	var center := Vector2(500.0, 400.0)
	for effect: String in ["fire", "earth"]:
		var sigil: Node2D = _rained(effect, center, 135.0, 8)
		var pts: PackedVector2Array = sigil.get("_gate_points")
		var lift: float = sigil.get("GATE_MIN_LIFT")
		_expect(not pts.is_empty(), "%s opens at least one gate" % effect)
		var above: bool = true
		for p: Vector2 in pts:
			if p.y > center.y - lift:
				above = false
		_expect(above, "%s: every gate hangs at least GATE_MIN_LIFT above the ground" % effect)
		sigil.queue_free()
	var earth: Node2D = _rained("earth", center, 135.0, 8)
	var epts: PackedVector2Array = earth.get("_gate_points")
	_expect(epts.size() == 3, "earth opens three separate holes, not one gate")
	earth.queue_free()
	_completes("gate_hangs_above_footprint")


## 3. THE NEGATIVE TEST. A body just outside the per-meteor blast takes nothing.
## Nothing in the gate work touched METEOR_IMPACT_RADIUS, and this is what proves
## it stayed put rather than drifting along with the new art.
func _test_impact_radius_boundary() -> void:
	var script: GDScript = load(METEOR_PATH)
	var r: float = script.get("METEOR_IMPACT_RADIUS")
	var at := Vector2(300.0, 300.0)
	var inside := Node2D.new()
	inside.global_position = at + Vector2(r - 2.0, 0.0)
	var outside := Node2D.new()
	outside.global_position = at + Vector2(r + 2.0, 0.0)
	root.add_child(inside)
	root.add_child(outside)
	var hit: Array = script.targets_in_radius(at, r, [inside, outside])
	_expect(inside in hit, "a body just INSIDE the blast is hit")
	_expect(not (outside in hit), "a body just OUTSIDE the blast takes zero")
	inside.queue_free()
	outside.queue_free()
	_completes("impact_radius_boundary")


## 4. The gate is scenery. A body parked at the gate's own position — up in the
## sky, far from any impact point — must not be selected by the impact test.
func _test_gate_is_not_a_damage_source() -> void:
	var center := Vector2(500.0, 400.0)
	var sigil: Node2D = _rained("fire", center, 135.0, 10)
	var pts: PackedVector2Array = sigil.get("_gate_points")
	var script: GDScript = load(METEOR_PATH)
	var r: float = script.get("METEOR_IMPACT_RADIUS")
	var bystander := Node2D.new()
	bystander.global_position = pts[0]
	root.add_child(bystander)
	var caught: bool = false
	for m: Dictionary in (sigil.get("_meteors") as Array):
		if bystander in script.targets_in_radius(m["to"] as Vector2, r, [bystander]):
			caught = true
	_expect(not caught, "a body sitting IN the gate is hit by nothing — the gate is scenery")
	bystander.queue_free()
	sigil.queue_free()
	_completes("gate_is_not_a_damage_source")


## 5. The Unmaking's identity is an EMPTY sky (see `_open_gates`). If someone
## later "fixes" shadow by giving it a circle too, this is the conversation.
func _test_shadow_opens_no_gate() -> void:
	var sigil: Node2D = _rained("shadow", Vector2(500.0, 400.0), 135.0, 8)
	var pts: PackedVector2Array = sigil.get("_gate_points")
	_expect(pts.is_empty(), "shadow opens NO gate — its tell is the sky staying empty")
	sigil.queue_free()
	_completes("shadow_opens_no_gate")
