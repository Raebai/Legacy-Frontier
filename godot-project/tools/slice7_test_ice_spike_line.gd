# Run: godot --headless --path godot-project --script tools/slice7_test_ice_spike_line.gd
# Pure-geometry tests for GLACIAL SPINE (IceSpikeLine.gd) — the frost family's
# ground-erupting crest that replaced the ice bombardment.
#
# Two things are being pinned here, and they are the two the redesign can break:
#   1. DAMAGE == WHAT IS DRAWN. Each spike hits exactly its own box — its
#      half-width, its CURRENT height — and the crest never reaches past the
#      declared half-length ("the spells shouldn't be able to get out the
#      radius"). Every negative case below is a body that must take NOTHING.
#   2. THE DODGE IS THE JUMP. A body above the tip is airborne and safe; a body
#      standing on the floor is speared. If the airborne case ever starts
#      passing as a hit, the spell has become undodgeable.
#
# Scripts are load()ed at RUNTIME (never referenced by class_name) because the
# spectacles reach for the Sfx/Juice AUTOLOADS, which only register once the main
# loop is live — a compile-time class_name reference would fail to resolve them
# and (per the ledger's test trap) print a false PASS. Runs on the first _process
# frame, by which point the autoloads exist.
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
	"spike_box",
	"rise_gates_damage",
	"extent_never_exceeds_declared",
	"crest_tiles_without_gaps",
	"selector",
	"spell_def_wiring",
]

var _fails: int = 0
var _completed: Dictionary = {}

const SPIKE_LINE_PATH: String = "res://scripts/combat/IceSpikeLine.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_spike_box()
	_test_rise_gates_damage()
	_test_extent_never_exceeds_declared()
	_test_crest_tiles_without_gaps()
	_test_selector()
	_test_spell_def_wiring()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice7 ice spike line tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice7 ice spike line tests: all PASS")
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


## The damage box IS the drawn blade. Base on the floor at y=400, half-width 16,
## full height 96 -> the blade occupies x in [184,216], y in [304,400].
func _test_spike_box() -> void:
	var line: GDScript = load(SPIKE_LINE_PATH)
	var base := Vector2(200.0, 400.0)
	_expect(line.point_in_spike(Vector2(200.0, 360.0), base, 16.0, 96.0),
		"a body standing in the spike's column is speared")
	_expect(line.point_in_spike(Vector2(216.0, 360.0), base, 16.0, 96.0),
		"a body at the exact half-width edge is speared (bands must tile)")
	_expect(not line.point_in_spike(Vector2(218.0, 360.0), base, 16.0, 96.0),
		"a body 2px past the drawn edge takes NOTHING — damage cannot leave the silhouette")
	_expect(not line.point_in_spike(Vector2(200.0, 300.0), base, 16.0, 96.0),
		"an AIRBORNE body above the tip is missed — jumping IS the dodge")
	_expect(not line.point_in_spike(Vector2(200.0, 430.0), base, 16.0, 96.0),
		"a body below the base (a lower floor) is not speared through the deck")
	_completes("spike_box")


## The rise is part of the dodge budget: a spike that has only come up 20px
## cannot reach a body whose centre rides 40px above the floor.
func _test_rise_gates_damage() -> void:
	var line: GDScript = load(SPIKE_LINE_PATH)
	var base := Vector2(0.0, 0.0)
	var standing := Vector2(0.0, -40.0)  # centre 40px above the deck
	_expect(not line.point_in_spike(standing, base, 16.0, 0.0),
		"a spike that has not erupted damages nobody")
	_expect(not line.point_in_spike(standing, base, 16.0, 20.0),
		"a half-risen spike cannot reach a body it has not grown up to")
	_expect(line.point_in_spike(standing, base, 16.0, 96.0),
		"the fully risen spike reaches it")
	_completes("rise_gates_damage")


## "The spells shouldn't be able to get out the radius." The crest floors its
## spike count, so the outermost drawn (and damaging) edge always lands INSIDE
## the half-length the SpellDef declared — never level with it, never past it.
func _test_extent_never_exceeds_declared() -> void:
	var line: GDScript = load(SPIKE_LINE_PATH)
	for declared: float in [40.0, 96.0, 137.0, 210.0, 250.0, 600.0]:
		var extent: float = line.drawn_half_extent(declared)
		_expect(extent <= declared,
			"declared %.0f: drawn half-extent %.0f stays inside it" % [declared, extent])
	# And the shipped number specifically: 210 -> 6 spikes a side -> edge at 208.
	_expect(line.spikes_per_side(210.0) == 6,
		"the shipped 210px half-length builds 6 spikes per side")
	_expect(is_equal_approx(line.drawn_half_extent(210.0), 208.0),
		"...whose outer edge sits at 208px, inside the declared 210")
	# A half-length shorter than one spike degenerates to the origin spike alone
	# rather than producing a negative count.
	_expect(line.spikes_per_side(10.0) == 0,
		"a half-length under one spike-width yields the lone origin spike")
	_completes("extent_never_exceeds_declared")


## Neighbouring spikes must TOUCH: half-width is exactly half the spacing, so the
## crest is a continuous wall with no safe gap to stand in — and no overlap that
## would let one stance be hit by two spikes at once.
func _test_crest_tiles_without_gaps() -> void:
	var line: GDScript = load(SPIKE_LINE_PATH)
	var a := Vector2(0.0, 0.0)
	var b := Vector2(line.SPIKE_SPACING, 0.0)
	var midpoint := Vector2(line.SPIKE_SPACING * 0.5, -40.0)
	_expect(is_equal_approx(line.SPIKE_HALF_W, line.SPIKE_SPACING * 0.5),
		"spike half-width is exactly half the spacing")
	_expect(
		line.point_in_spike(midpoint, a, line.SPIKE_HALF_W, 96.0)
		or line.point_in_spike(midpoint, b, line.SPIKE_HALF_W, 96.0),
		"a body exactly between two spikes is caught by one of them — no gap")
	_completes("crest_tiles_without_gaps")


## The Array selector spectacles expose, driven with real nodes.
func _test_selector() -> void:
	var line: GDScript = load(SPIKE_LINE_PATH)
	var base := Vector2(100.0, 300.0)
	var speared: Node2D = _node_at(Vector2(104.0, 262.0))   # in the column, grounded
	var beside: Node2D = _node_at(Vector2(150.0, 262.0))    # past the half-width
	var jumped: Node2D = _node_at(Vector2(100.0, 180.0))    # above the tip
	var hit: Array = line.targets_in_spike(base, 16.0, 96.0, [speared, beside, jumped])
	_expect(speared in hit, "the grounded body is in the spike's hit list")
	_expect(not (beside in hit), "the body beside the crest is not")
	_expect(not (jumped in hit), "the airborne body is not")
	_completes("selector")


## The data row still routes to the crest: METEOR kind (SpellCaster's arm hands
## over the aimed ground point) + effect "frost" (MeteorSigil's fork key). If
## either drifts, the spell silently reverts to a sky bombardment.
func _test_spell_def_wiring() -> void:
	var spell: SpellDef = null
	for s: SpellDef in SpellLibrary.build_all():
		if s.id == "frozen_comet":
			spell = s
			break
	_expect(spell != null, "frozen_comet is still in the spell tree")
	if spell == null:
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	_expect(spell.kind == SpellDef.Kind.METEOR,
		"it dispatches through the METEOR arm (the only arm that hands over the aimed point)")
	_expect(spell.effect == "frost",
		"its effect is 'frost' — the key MeteorSigil.rain() forks on")
	var line: GDScript = load(SPIKE_LINE_PATH)
	_expect(line.drawn_half_extent(spell.radius) <= spell.radius,
		"the crest it builds stays inside the radius the row declares")
	_completes("spell_def_wiring")
