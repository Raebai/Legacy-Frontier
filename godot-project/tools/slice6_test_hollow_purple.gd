# HOLLOW PURPLE, end to end — the SELF-COMBO path, with a real BeamSpell pair, a
# real SpellReactor sweep and a REAL spectacle node (spawn_effects left ON).
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_hollow_purple.gd
#
# WHY THIS FILE EXISTS. tools/slice6_test_reactor.gd proves DETECTION with
# `spawn_effects = false` — it deliberately never builds a HollowPurple, because
# a 1.7 s spectacle has no business inside a registry test. That seam is correct,
# and it is also exactly why the fusion could ship with its gate never opening:
# every automated check stopped one line before the spectacle was constructed.
# This suite starts where that one stops.
#
# THE REGRESSION IT PINS DOWN. Both hollow_purple rows carry a `require_owner`
# predicate ("same" at priority 100, "different" at 95), so a beam pair with NO
# caster matches NEITHER — `_owner_relation` reports "unowned", which satisfies
# neither. Any demo, capture or sandbox that spawns BeamSpells directly and
# forgets `caster_node` therefore stages nothing at all: no reaction, no node, no
# `_process`, no gate, no discharge — and no error, because nothing went wrong.
# `_test_ownerless_pair_is_inert` is that case, written down.
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
	"owner_predicate",
	"ownerless_pair_is_inert",
	"self_combo_stages_in_front",
	"gate_opens",
	"beats_run_to_completion",
	"cross_caster_stages_at_the_crossing",
]

var _fails: int = 0
var _completed: Dictionary = {}

const BEAM := "res://scripts/combat/BeamSpell.gd"
const HOLLOW_PURPLE := "res://scripts/combat/HollowPurple.gd"
## Long enough to clear ReactionOutcomes.MIN_BEAM_LENGTH by a wide margin.
const BEAM_LEN: float = 1100.0
## Fixed step used to pump the beats by hand. Beat boundaries are 0.60 / 0.78 /
## 1.70 s, so a 20 ms step lands inside every one of them without the suite
## having to spend 1.7 s of wall clock waiting for real frames.
const STEP: float = 0.02

## ⚠ WHY THE BEAT BOUNDARIES ARE FETCHED AND NOT WRITTEN `HollowPurple.DONE`.
## A `--script` tool is COMPILED BEFORE THE AUTOLOADS EXIST. Naming BeamSpell or
## HollowPurple as a global class here makes the parser compile them at that
## moment, and both call `Sfx`/`Juice` — so the whole suite dies with
## "Identifier not found: Sfx" and every `.new()` after it fails. Loading at
## RUNTIME and reading the constant map keeps the numbers in sync with the source
## without ever naming the class at parse time.
var _ran: bool = false


static func _const_of(path: String, name: StringName) -> Variant:
	var gd: GDScript = load(path) as GDScript
	return gd.get_script_constant_map().get(name)


## Kicked off from `_process` rather than run inside it, because the last test
## has to `await process_frame`: `queue_free()` is DEFERRED, so a node that
## correctly retires itself is still valid until the frame ends.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("FAIL: SpellReactor autoload is missing")
		quit(1)
		return
	# Hit-stop would set Engine.time_scale on the discharge beat and make the
	# whole suite's timing a function of real seconds.
	var tuning: Node = root.get_node_or_null(^"/root/Tuning")
	if tuning != null and tuning.get(&"cfg") != null:
		tuning.cfg.set(&"hit_stop_enabled", false)
	# Drive the sweep by hand instead of racing the 30 Hz timer. spawn_effects
	# stays TRUE — building the real spectacle is the entire point here.
	reactor.set_process(false)
	reactor.set(&"spawn_effects", true)
	_test_owner_predicate()
	_test_ownerless_pair_is_inert(reactor)
	_test_self_combo_stages_in_front(reactor)
	_test_gate_opens(reactor)
	await _test_beats_run_to_completion(reactor)
	_test_cross_caster_stages_at_the_crossing(reactor)
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Hollow Purple tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Hollow Purple tests: all PASS")
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


# ------------------------------------------------------------ harness

## A live, ALREADY-FIRED beam. `fire()` starts a 0.34 s charge telegraph during
## which `reaction_active()` is false on purpose; rather than wait that out in
## real time, its own `_process` is switched off and pumped once past the charge
## boundary, which runs the genuine charge -> discharge transition.
func _beam(arena: Node2D, origin: Vector2, dir: Vector2, element: int, caster: Node) -> Node2D:
	var beam: Node2D = (load(BEAM) as GDScript).new()
	arena.add_child(beam)
	beam.set(&"element_id", element)
	beam.set(&"caster_node", caster)
	beam.call(&"fire", origin, dir.normalized(), Elements.color(element),
		BEAM_LEN, 30.0, 46, Elements.effect_name(element))
	beam.set_process(false)
	beam.call(&"_process", float(_const_of(BEAM, &"CHARGE_TIME")) + 0.01)
	return beam


func _arena() -> Node2D:
	var a := Node2D.new()
	root.add_child(a)
	return a


## The spectacle the reactor just staged, or null. Read off the reactor's global
## one-shot slot rather than by scanning children, because that slot IS the thing
## gameplay consults.
func _staged(reactor: Node) -> Node:
	var hp: Variant = reactor.get(&"_hollow_purple")
	return hp as Node if hp != null and is_instance_valid(hp) else null


## Free the whole test scene. The HollowPurple must go too: its `tree_exited`
## releases the reactor's one-shot slot, and without that every later test would
## bail out of `_hollow_purple` on the "one annihilation at a time" guard.
func _teardown(reactor: Node, arena: Node2D) -> void:
	var hp: Node = _staged(reactor)
	if hp != null:
		hp.free()
	arena.free()
	reactor.call(&"resolve_now")  # sweep the freed beams out of the registry


# ------------------------------------------------------------ tests

## The data half of the ownership predicate, with no scene at all.
func _test_owner_predicate() -> void:
	var E := Elements.Element
	var F := ReactionTable.Form
	var same: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.ICE, "same")
	_expect(String(same.get("outcome", "")) == "hollow_purple",
		"one caster's two opposing beams fuse")
	_expect(int(same.get("priority", 0)) == 100,
		"...on the SELF-COMBO row, which outranks the crossing row")
	var diff: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.ICE, "different")
	_expect(String(diff.get("outcome", "")) == "hollow_purple",
		"two casters' opposing beams still fuse")
	_expect(int(diff.get("priority", 0)) == 95, "...on the rarer crossing row")
	# THE ONE THAT WAS SILENTLY FAILING.
	var none: Dictionary = ReactionTable.match_rule(F.BEAM, E.FIRE, F.BEAM, E.ICE, "unowned")
	_expect(none.is_empty(),
		"a beam pair with NO caster matches neither row (got %s)" % String(none.get("outcome", "")))
	_completes("owner_predicate")


## ...and the same thing with real nodes: a BeamSpell whose `caster_node` was
## never assigned reports no owner, so the pair is inert. This is the exact shape
## of the bug — a demo that forgets one line stages nothing and says nothing.
func _test_ownerless_pair_is_inert(reactor: Node) -> void:
	var E := Elements.Element
	var arena: Node2D = _arena()
	var origin_a := Vector2(-520.0, 320.0)
	var origin_b := Vector2(-520.0, -200.0)
	var cross := Vector2(0.0, 60.0)
	_beam(arena, origin_a, cross - origin_a, E.FIRE, null)
	_beam(arena, origin_b, cross - origin_b, E.ICE, null)
	_expect(int(reactor.call(&"resolve_now")) == 0,
		"two ownerless crossing beams do not fuse")
	_expect(_staged(reactor) == null, "...and no spectacle is built")
	_teardown(reactor, arena)
	_completes("ownerless_pair_is_inert")


## The headline path. Both beams leave ONE muzzle, so there is no meaningful
## crossing to stage at — the gate belongs a fixed distance in FRONT of the
## caster, along the aim they were holding when they completed the combo.
func _test_self_combo_stages_in_front(reactor: Node) -> void:
	var E := Elements.Element
	var arena: Node2D = _arena()
	var caster := Node2D.new()
	arena.add_child(caster)
	var muzzle := Vector2(-600.0, 0.0)
	var aim_late := Vector2(1.0, 0.24).normalized()
	_beam(arena, muzzle, Vector2(1.0, -0.24), E.FIRE, caster)
	_beam(arena, muzzle, aim_late, E.ICE, caster)
	_expect(int(reactor.call(&"resolve_now")) == 1, "one caster's double-tap fuses")
	var hp: Node = _staged(reactor)
	_expect(hp != null, "a HollowPurple was actually built")
	if hp == null:
		_teardown(reactor, arena)
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var p: Vector2 = hp.get(&"_p")
	var axis: Vector2 = hp.get(&"_axis")
	var expected: Vector2 = muzzle + aim_late * ReactionOutcomes.SELF_COMBO_OFFSET
	_expect(p.distance_to(expected) < 1.0,
		"the gate opens SELF_COMBO_OFFSET in front of the muzzle (got %s, want %s)" % [p, expected])
	_expect(p.distance_to(muzzle) > 100.0,
		"...and NOT at the geometric meeting point, which for a self-combo is the muzzle")
	_expect(axis.dot(aim_late) > 0.999,
		"the annihilation fires along the LATER beam's aim (got %s)" % axis)
	# Both beams are spent, not left frozen: the bug this replaced was a fusion
	# that seized both beams and then quietly let go of them.
	_expect(hp.get_child_count() >= 2, "the spectacle owns its gate and its screen veil")
	_teardown(reactor, arena)
	_completes("self_combo_stages_in_front")


## THE FAILURE THE WHOLE FILE IS NAMED AFTER: does the magic-circle gate actually
## exist, sit where the fusion is, and become visible? `_circle` is assigned in
## `_open_circle()` during `begin()`; MagicCircle then fades itself in over its
## grow time inside its OWN `_process`, so this pumps both.
func _test_gate_opens(reactor: Node) -> void:
	var E := Elements.Element
	var arena: Node2D = _arena()
	var caster := Node2D.new()
	arena.add_child(caster)
	_beam(arena, Vector2(-600.0, 0.0), Vector2(1.0, -0.2), E.SHADOW, caster)
	_beam(arena, Vector2(-600.0, 0.0), Vector2(1.0, 0.2), E.HOLY, caster)
	reactor.call(&"resolve_now")
	var hp: Node = _staged(reactor)
	_expect(hp != null, "the shadow/holy pair fuses too")
	if hp == null:
		_teardown(reactor, arena)
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var circle: Variant = hp.get(&"_circle")
	_expect(circle != null and is_instance_valid(circle), "_circle was assigned")
	if circle == null or not is_instance_valid(circle):
		_teardown(reactor, arena)
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var mc: Node2D = circle
	_expect(mc.is_inside_tree() and mc.get_parent() == hp,
		"the gate is a live child of the fusion")
	_expect(mc.get(&"_edge_on") == true,
		"the gate stands EDGE-ON — side-on 2D reads a portal as a lens, not a disc")
	# ⚠ THE ORIGIN-PARKING TRAP (see SpellGeometry): the fusion node itself sits
	# at (0, 0) and draws in world coordinates, so a gate placed anywhere but
	# `_p` would render in the corner of the arena with nothing else wrong.
	var p: Vector2 = hp.get(&"_p")
	_expect(mc.global_position.distance_to(p) < 1.0,
		"the gate is at the fusion point, not at the node's (0,0) transform (got %s, want %s)"
			% [mc.global_position, p])
	_expect(float(mc.get(&"radius")) > 1.0,
		"the gate has a real radius (got %s)" % mc.get(&"radius"))
	# Pump the fade-in. `appear()` starts at alpha 0 — a gate tested on the frame
	# it is built looks identical to a gate that never opens.
	for i: int in 20:
		mc.call(&"_process", STEP)
	_expect(mc.get(&"_alpha") >= 0.99,
		"the gate fades all the way in (alpha %s)" % mc.get(&"_alpha"))
	_expect(mc.get(&"_vanishing") == false, "...and is not already dismissing itself")
	_teardown(reactor, arena)
	_completes("gate_opens")


## All three beats, pumped on a fixed step: INTAKE -> HELD -> DISCHARGE -> gone.
## `_did_held` / `_did_discharge` are the one-shot latches the beats set, so this
## proves the sequence RAN rather than merely that time passed.
func _test_beats_run_to_completion(reactor: Node) -> void:
	var E := Elements.Element
	var arena: Node2D = _arena()
	var caster := Node2D.new()
	arena.add_child(caster)
	_beam(arena, Vector2(-600.0, 0.0), Vector2(1.0, -0.2), E.ARCANE, caster)
	_beam(arena, Vector2(-600.0, 0.0), Vector2(1.0, 0.2), E.WIND, caster)
	reactor.call(&"resolve_now")
	var hp: Node = _staged(reactor)
	_expect(hp != null, "the arcane/wind pair fuses")
	if hp == null:
		_teardown(reactor, arena)
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	hp.set_process(false)  # pump by hand; see STEP
	_expect(not bool(hp.get(&"_did_held")), "the held beat has not fired at t=0")
	var held_at: float = -1.0
	var discharge_at: float = -1.0
	var retired_at: float = -1.0
	var t: float = 0.0
	for i: int in 120:   # 2.4 s of pumped time, comfortably past DONE (1.70)
		hp.call(&"_process", STEP)
		t += STEP
		if held_at < 0.0 and bool(hp.get(&"_did_held")):
			held_at = t
		if discharge_at < 0.0 and bool(hp.get(&"_did_discharge")):
			discharge_at = t
		# `queue_free()` is DEFERRED — the node stays valid for the rest of the
		# frame, and this loop is one frame. The retirement is observable here
		# only as the deletion FLAG; the actual free is awaited below.
		if hp.is_queued_for_deletion():
			retired_at = t
			break
	var intake_end: float = float(_const_of(HOLLOW_PURPLE, &"INTAKE_END"))
	var held_end: float = float(_const_of(HOLLOW_PURPLE, &"HELD_END"))
	var done: float = float(_const_of(HOLLOW_PURPLE, &"DONE"))
	_expect(absf(held_at - intake_end) < 0.05,
		"the HELD beat lands at INTAKE_END (got %s, want %s)" % [held_at, intake_end])
	_expect(absf(discharge_at - held_end) < 0.05,
		"the DISCHARGE beat lands at HELD_END (got %s, want %s)" % [discharge_at, held_end])
	_expect(retired_at > 0.0 and absf(retired_at - done) < 0.08,
		"the fusion retires itself at DONE (got %s, want %s)" % [retired_at, done])
	# Two frames, not one: `process_frame` fires DURING the idle frame, and the
	# deletion queue is flushed at the END of it, so the node is still alive when
	# the first signal comes back.
	await process_frame
	await process_frame
	_expect(_staged(reactor) == null,
		"...and releases the one-shot slot, so the next fusion can happen")
	arena.free()
	reactor.call(&"resolve_now")
	_completes("beats_run_to_completion")


## The rarer row, kept honest: two SEPARATE casters' beams stage at the geometric
## crossing and fire along the bisector — the case the self-combo row must not
## have quietly replaced.
func _test_cross_caster_stages_at_the_crossing(reactor: Node) -> void:
	var E := Elements.Element
	var arena: Node2D = _arena()
	var west := Node2D.new()
	var north := Node2D.new()
	arena.add_child(west)
	arena.add_child(north)
	# A horizontal beam and a vertical one crossing at the origin, each long
	# enough that the crossing sits in the BODY of both (CROSS_MIN/MAX_T).
	_beam(arena, Vector2(-550.0, 0.0), Vector2.RIGHT, E.FIRE, west)
	_beam(arena, Vector2(0.0, -550.0), Vector2.DOWN, E.ICE, north)
	_expect(int(reactor.call(&"resolve_now")) == 1, "two casters' beams cross and fuse")
	var hp: Node = _staged(reactor)
	_expect(hp != null, "a HollowPurple was built for the crossing")
	if hp == null:
		_teardown(reactor, arena)
		return  # bail-out: the _expect above already failed, and the missing sentinel says so twice
	var p: Vector2 = hp.get(&"_p")
	_expect(p.length() < 40.0,
		"the crossing fusion stages at the crossing, not in front of a caster (got %s)" % p)
	var axis: Vector2 = hp.get(&"_axis")
	_expect(absf(axis.x - axis.y) < 0.05,
		"...and fires along the bisector of the two beams (got %s)" % axis)
	_teardown(reactor, arena)
	_completes("cross_caster_stages_at_the_crossing")
