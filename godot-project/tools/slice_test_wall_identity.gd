# THE TWO WALLS ARE NOT ONE SPELL IN TWO COLOURS.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice_test_wall_identity.gd
#
# Maker, reviewing in the spell playground: *"a rock wall and an ice wall must not
# be the same spell in two colours"*, and, in the same breath, *"a wall should be
# SHOVEABLE — you should be able to push it"*.
#
# Answering the second ask the obvious way would have failed the first one: give
# both walls a shove and you have restated the recolour complaint in verbs. So both
# walls now take the SAME second press and answer it OPPOSITELY —
#
#   ROCK  the press DISPLACES it. It survives, LEAVES, and grinds away as a ram.
#   ICE   the press DETONATES it. It does not move a pixel; it bursts where it is.
#
# ...and this suite is the proof, driven against REAL walls. Its centrepiece is
# `_test_the_two_answers_are_opposite`, which measures the displacement of each wall
# after an identical press: a nonzero number for the stone and an EXACTLY zero one
# for the ice. If someone ever "unifies" the two walls, that test is what fails.
#
# It also MEASURES the push — px/frame, total px, and the frames the ram is alive —
# because "you should be able to push it" is a claim about distance and time and
# neither of those is knowable from reading the constants (SHOVE_SPEED is px/s, but
# what the player experiences is how far it got before something stopped it).
#
# ⚠ NOTHING HERE MAY NAME `IceWall` OR `RockWall` BY class_name — the same note that
# sits atop tools/slice_test_wall_reactions.gd, tools/slice7_test_frost_field.gd and
# tools/slice_test_wall_two_beat.gd. Naming them pulls their raise paths (which
# reference the `Sfx` autoload) into THIS tool's compile-time dependency graph, and
# the whole harness then fails to compile with "Identifier not found: Sfx". Load by
# path, call statics through `script.call(...)`, read constants through
# `get_script_constant_map()`.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function, and hands the caller the return type's zero value.
# So failures accumulate on the MEMBER `_fails` (an abort cannot discard them) and
# every test's last line records that it reached the end. A test that aborts
# part-way is missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion.
const TESTS: Array[String] = [
	"both_walls_answer_the_same_verb",
	"ice_detonates_where_it_stands",
	"rock_travels_when_shoved",
	"the_two_answers_are_opposite",
	"ownership_adoption_reaches_both_walls",
	"a_spent_wall_refuses_the_press",
	"an_unfinished_ice_wall_cannot_be_detonated",
]

const ICE_WALL_PATH: String = "res://scripts/combat/IceWall.gd"
const ROCK_WALL_PATH: String = "res://scripts/combat/RockWall.gd"

## Every method `RockWall.find_shoveable_near()` and the playground's two-beat
## arbitration duck-type against. BOTH walls must answer all of them or the caster
## cannot ask one question of a wall without first asking what it is made of.
const SHOVE_CONTRACT: Array[String] = [
	"can_shove", "shove", "wall_distance", "time_since_raise",
	"is_raised_by", "footprint_center", "set_primed",
]

## Raised far from the arena origin ON PURPOSE: these nodes park at (0, 0) and draw
## in world coordinates, so a wall standing at the origin would let a detector that
## wrongly read transforms pass.
const RAISE_FROM := Vector2(600.0, 0.0)

## How many process frames the shoved wall is watched for.
##
## ⚠ FRAMES ARE NOT TIME HERE, and that is why the measurement below is taken in
## SECONDS and only then converted. A headless main loop runs uncapped — this
## harness measured ~235 fps — so "12 frames" was 51 ms, not 200, and a px/frame
## number read straight off it would be a quarter of what a player sees. The time
## base is the WALL'S OWN `_elapsed`, which accumulates the same `delta` its slide
## integrates, so the two can never disagree about how long the slide has run.
const SLIDE_FRAMES: int = 40
## The reference tick the px/frame figure is quoted at. The game runs its physics at
## 60+ Hz; this is the number a player would count.
const REPORT_HZ: float = 60.0

var _fails: int = 0
var _completed: Dictionary = {}

var _ice: GDScript = null
var _rock: GDScript = null
var _rc: Dictionary = {}
var _arena: Node2D = null

## Carried between the two single-wall tests so the comparison test can assert on
## measurements taken under IDENTICAL conditions rather than re-deriving them.
var _ice_travel: float = -1.0
var _rock_travel: float = -1.0


func _initialize() -> void:
	root.size = Vector2i(1366, 768)
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL: harness watchdog fired — a test coroutine died before the end")
		quit(1))
	_run()


func _run() -> void:
	# One frame before anything touches the tree: a node added to `root` during
	# _initialize() is not yet inside the ACTIVE tree, so get_tree() comes back null
	# and the absolute /root/SpellReactor lookup inside raise_wall() throws.
	await process_frame
	# ⚠ THE REACTOR IS SILENCED, AND FINDING OUT WHY COST A DEBUG CYCLE. This suite
	# stands an ice wall and a rock wall in the SAME place (they are raised from the
	# same point, on purpose, so the two-beat search sees an identical situation for
	# both). SpellReactor authors a `rock_wall_rams_ice` row — so the moment this
	# suite gained an `await` long enough for the 30 Hz sweep to run, the stone ATE
	# the crystal mid-test and every later line ran against a freed instance. The
	# failure looked like "a member has moved", which is exactly the wrong diagnosis.
	#
	# Reactions have their own suite (tools/slice_test_wall_reactions.gd) and this one
	# is about what a BUTTON PRESS does, so the sweep is driven by hand — i.e. never.
	# Same move, same reason, as that suite's own `set_process(false)`.
	var reactor: Node = root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		printerr("FAIL: SpellReactor autoload is missing")
		quit(1)
		return
	reactor.set_process(false)
	_ice = load(ICE_WALL_PATH) as GDScript
	_rock = load(ROCK_WALL_PATH) as GDScript
	_rc = _rock.get_script_constant_map()
	_arena = Node2D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	await _test_both_walls_answer_the_same_verb()
	await _test_ice_detonates_where_it_stands()
	await _test_rock_travels_when_shoved()
	_test_the_two_answers_are_opposite()
	await _test_ownership_adoption_reaches_both_walls()
	await _test_a_spent_wall_refuses_the_press()
	await _test_an_unfinished_ice_wall_cannot_be_detonated()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Wall identity tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Wall identity tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ---- harness ----------------------------------------------------------------

## Raise a REAL wall the way SpellCaster does: stamp identity FIRST (that is the
## order in SpellCaster.cast, and it matters because registration captures the
## element), then raise.
func _raise(script: GDScript, element: int, caster: Node = null) -> Node2D:
	var w: Node2D = script.new()
	_arena.add_child(w)
	w.set("element_id", element)
	w.set("spell_tier", SpellTier.Tier.HEAVY)
	w.set("caster_node", caster)
	w.call("raise_wall", RAISE_FROM, Vector2.RIGHT)
	return w


func _raise_ice(caster: Node = null) -> Node2D:
	return _raise(_ice, Elements.Element.ICE, caster)


func _raise_rock(caster: Node = null) -> Node2D:
	return _raise(_rock, Elements.Element.EARTH, caster)


## Tear the arena down between tests. `free()` rather than `queue_free()` so each
## wall's `_exit_tree` — and therefore its reactor unregister — runs synchronously,
## and so the global "shoveable" / "ice_wall" groups cannot leak into the next test.
func _clear() -> void:
	for child: Node in _arena.get_children():
		child.free()


## Run a wall forward until it has finished rising. The ice wall refuses a press
## until it has crystallised (`IceWall.can_shove` gates on RISE_TIME — that gate IS
## its tell, see the probe), so every test that asks it to answer a press has to let
## it finish first. Bounded, so a wall that never arms fails by timeout rather than
## hanging the harness.
func _arm(w: Node2D) -> void:
	for i in 200:
		if not is_instance_valid(w) or bool(w.call("can_shove")):
			return
		await process_frame


# ---- the tests --------------------------------------------------------------

## ONE VERB, ASKED THE SAME WAY OF BOTH. This is the test that makes the rest
## meaningful: if the ice wall did not answer the whole duck-typed surface, the
## caster's `find_shoveable_near` would skip it, the press would fall through to a
## plain punch, and every "the ice detonates" assertion below would be describing a
## code path no button can reach.
func _test_both_walls_answer_the_same_verb() -> void:
	var ice: Node2D = _raise_ice()
	var rock: Node2D = _raise_rock()
	await _arm(ice)
	for m: String in SHOVE_CONTRACT:
		_expect(ice.has_method(m), "IceWall implements %s()" % m)
		_expect(rock.has_method(m), "RockWall implements %s()" % m)
	_expect(ice.is_in_group("shoveable"), "a standing ICE wall is in the shoveable registry")
	_expect(rock.is_in_group("shoveable"), "a standing ROCK wall is in the shoveable registry")
	_expect(bool(ice.call("can_shove")), "a standing ice wall would answer a press")
	_expect(bool(rock.call("can_shove")), "a standing rock wall would answer a press")
	# ...and the search the caster actually runs finds BOTH of them. `find_shoveable_near`
	# is duck-typed, but it is duck-typed in RockWall.gd — asserting the methods exist
	# is not the same as asserting the search returns the wall.
	var found: Node2D = _rock.call("find_shoveable_near", self, RAISE_FROM, 400.0)
	_expect(found != null, "the two-beat search finds a wall standing in front of you")
	_clear()
	_completes("both_walls_answer_the_same_verb")


## THE ICE ANSWER: it does not move, it comes apart.
func _test_ice_detonates_where_it_stands() -> void:
	var ice: Node2D = _raise_ice()
	await _arm(ice)
	var before: Vector2 = ice.call("footprint_center")
	_expect(bool(ice.call("shove", Vector2.RIGHT)), "the press is SPENT on the ice wall")
	# The burst is immediate and synchronous: the wall leaves both registries on the
	# same frame, so no second press and no reaction can find it again.
	_expect(not ice.is_in_group("ice_wall"), "a detonated ice wall leaves the ice_wall group")
	_expect(not ice.is_in_group("shoveable"), "...and the shoveable registry")
	_expect(not bool(ice.call("can_shove")), "...and refuses a second press")
	# Watch it for as long as the rock wall is watched below, so the two travel
	# numbers are measured over the same window.
	for i in SLIDE_FRAMES:
		await process_frame
	_ice_travel = 0.0
	if is_instance_valid(ice):
		_ice_travel = (ice.call("footprint_center") as Vector2).distance_to(before)
	_expect(is_equal_approx(_ice_travel, 0.0),
		"a punched ice wall does not travel (moved %.1f px — stone slides, crystal bursts)"
			% _ice_travel)
	_clear()
	_completes("ice_detonates_where_it_stands")


## THE ROCK ANSWER: it survives the press and LEAVES. Also the measurement — the
## maker's ask is about being able to PUSH a wall, and a push is a distance over a
## time, neither of which is readable off SHOVE_SPEED alone.
func _test_rock_travels_when_shoved() -> void:
	var rock: Node2D = _raise_rock()
	var before: Vector2 = rock.call("footprint_center")
	_expect(bool(rock.call("shove", Vector2.RIGHT)), "the press is SPENT on the rock wall")
	var t0: float = float(rock.get("_elapsed"))
	var steps: int = 0
	var last: Vector2 = before
	for i in SLIDE_FRAMES:
		await process_frame
		if not is_instance_valid(rock):
			break
		var now: Vector2 = rock.call("footprint_center")
		# Every sampled frame must ADVANCE it: a slide that arrives in one jump is a
		# teleport wearing a slide's name, and the dust trail would be drawn along a
		# path nothing travelled.
		_expect(now.distance_to(last) > 0.0, "every frame of the slide advances the wall")
		last = now
		steps += 1
	var dt: float = float(rock.get("_elapsed")) - t0 if is_instance_valid(rock) else 0.0
	_rock_travel = last.distance_to(before)
	var px_s: float = (_rock_travel / dt) if dt > 0.0 else 0.0
	print("[measure] rock shove: %.1f px in %.3f s (%d frames of an UNCAPPED headless loop)"
		% [_rock_travel, dt, steps])
	print("[measure] rock shove: %.0f px/s measured = %.1f px per frame at %d Hz"
		% [px_s, px_s / REPORT_HZ, int(REPORT_HZ)])
	print("[measure] rock shove: %.0f px max slide / %.0f px/s = %.2f s (%d frames) of ram"
		% [float(_rc["MAX_SLIDE"]), float(_rc["SHOVE_SPEED"]),
			float(_rc["MAX_SLIDE"]) / float(_rc["SHOVE_SPEED"]),
			int(REPORT_HZ * float(_rc["MAX_SLIDE"]) / float(_rc["SHOVE_SPEED"]))])
	_expect(_rock_travel > 20.0,
		"a punched rock wall travels (moved only %.1f px)" % _rock_travel)
	_expect(steps >= 2, "the slide was sampled over more than one frame")
	# The measured speed IS the constant. This is what stops the px/frame figure
	# above from being an artefact of whatever frame rate the harness happened to
	# run at — if they ever disagree, the number quoted to the maker is wrong.
	_expect(absf(px_s - float(_rc["SHOVE_SPEED"])) < float(_rc["SHOVE_SPEED"]) * 0.05,
		"the measured slide speed is SHOVE_SPEED (%.0f px/s measured vs %.0f declared)"
			% [px_s, float(_rc["SHOVE_SPEED"])])
	_clear()
	_completes("rock_travels_when_shoved")


## THE ANTI-RECOLOUR ASSERTION, and the reason this file exists. Two walls, one
## press, two OPPOSITE outcomes — measured, not asserted from the source.
##
## If someone later gives the ice wall a slide (or takes the rock wall's away),
## this is the test that fails, and it fails with both numbers in the message.
func _test_the_two_answers_are_opposite() -> void:
	_expect(_rock_travel >= 0.0 and _ice_travel >= 0.0,
		"both travel measurements were taken (rock=%.1f ice=%.1f)" % [_rock_travel, _ice_travel])
	_expect(_ice_travel < 1.0 and _rock_travel > 20.0,
		"the same press moves stone and not ice — rock %.1f px vs ice %.1f px"
			% [_rock_travel, _ice_travel])
	print("[measure] one press: rock travelled %.1f px, ice travelled %.1f px"
		% [_rock_travel, _ice_travel])
	_completes("the_two_answers_are_opposite")


## `adopt_new_shoveable` used to cast `w as RockWall`, which silently skipped the ice
## wall the moment it joined the registry — so an ice wall could never be CLAIMED,
## and the claimable half of the two-beat (the primed tell, which requires
## `is_raised_by(you)`) would never light for it. Nothing would have errored.
func _test_ownership_adoption_reaches_both_walls() -> void:
	var owner_a := Node.new()
	owner_a.name = "CasterA"
	root.add_child(owner_a)
	var before: Array = _rock.call("snapshot_shoveable", self)
	var ice: Node2D = _raise_ice()
	var rock: Node2D = _raise_rock()
	await _arm(ice)
	var claimed: int = _rock.call("adopt_new_shoveable", self, before, owner_a)
	_expect(claimed == 2, "the cast bracket claims BOTH new walls (claimed %d)" % claimed)
	_expect(bool(ice.call("is_raised_by", owner_a)), "the ice wall knows who raised it")
	_expect(bool(rock.call("is_raised_by", owner_a)), "the rock wall knows who raised it")
	# ...and the claimable search — the one that decides whether the tell lights —
	# now returns the ice wall for its owner and nobody else.
	var owner_b := Node.new()
	owner_b.name = "CasterB"
	root.add_child(owner_b)
	var mine: Node2D = _rock.call("find_shoveable_near", self, RAISE_FROM, 400.0, owner_a)
	var theirs: Node2D = _rock.call("find_shoveable_near", self, RAISE_FROM, 400.0, owner_b)
	_expect(mine != null, "your own wall is claimable by you")
	_expect(theirs == null, "...and never by somebody else")
	# An already-owned wall is never re-stamped, so a nested cast cannot steal it.
	var again: int = _rock.call("adopt_new_shoveable", self,
		_rock.call("snapshot_shoveable", self), owner_b)
	_expect(again == 0, "a second bracket claims nothing that already has an owner")
	_expect(bool(ice.call("is_raised_by", owner_a)), "...and the ice wall keeps its owner")
	_clear()
	owner_a.free()
	owner_b.free()
	_completes("ownership_adoption_reaches_both_walls")


## A press must never be swallowed by a wall that cannot answer it. This is the
## same guarantee `can_shove()` exists for on the stone, asserted on the crystal:
## the burst is idempotent, so the SECOND press has to be refused and handed back.
func _test_a_spent_wall_refuses_the_press() -> void:
	var ice: Node2D = _raise_ice()
	await _arm(ice)
	_expect(bool(ice.call("shove", Vector2.RIGHT)), "first press bursts it")
	_expect(not bool(ice.call("shove", Vector2.RIGHT)),
		"a second press is REFUSED, not swallowed by an already-bursting wall")
	var rock: Node2D = _raise_rock()
	_expect(bool(rock.call("shove", Vector2.RIGHT)), "first press sends it")
	_expect(not bool(rock.call("shove", Vector2.RIGHT)),
		"a wall already grinding away refuses a second press")
	_clear()
	_completes("a_spent_wall_refuses_the_press")


## THE TELL IS THE RISE. A wall that could be detonated on the frame it appears has
## a windup of one frame and a 120 px burst, i.e. negative dodge slack against every
## movement verb in the game — see `tools/probe_owned_spell_dodge.gd`, which is where
## this gate came from. The rise is 0.30 s of visible crystallisation with the frost
## sigil open beneath it, and it is now load-bearing rather than decorative.
##
## The ROCK wall deliberately has no such gate (its `shove()` snaps a mid-rise wall
## solid and sends it), because a ram's tell is the 820 px/s of travel between it and
## you. Asserted here so a future "consistency" pass cannot quietly give the crystal
## the stone's rule.
func _test_an_unfinished_ice_wall_cannot_be_detonated() -> void:
	var ice: Node2D = _raise_ice()
	_expect(not bool(ice.call("can_shove")),
		"an ice wall still crystallising refuses the press")
	_expect(not bool(ice.call("shove", Vector2.RIGHT)),
		"...and shove() refuses it too, so the press is handed back rather than eaten")
	_expect(ice.is_in_group("ice_wall"), "...and the wall is still standing")
	var rock: Node2D = _raise_rock()
	_expect(bool(rock.call("can_shove")),
		"a rock wall mid-rise DOES answer — its tell is the travel, not the rise")
	await _arm(ice)
	_expect(bool(ice.call("can_shove")),
		"...and the ice wall arms once it has finished rising")
	var armed_at: float = float(ice.call("time_since_raise"))
	var rise: float = float(_ice.get_script_constant_map()["RISE_TIME"])
	print("[measure] ice wall arms at %.3f s (RISE_TIME %.2f s = %d frames at %d Hz of tell)"
		% [armed_at, rise, int(rise * REPORT_HZ), int(REPORT_HZ)])
	_expect(armed_at >= rise, "...no earlier than RISE_TIME (%.3f s)" % armed_at)
	_clear()
	_completes("an_unfinished_ice_wall_cannot_be_detonated")
