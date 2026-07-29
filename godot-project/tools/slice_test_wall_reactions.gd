# THE WALLS JOIN THE REACTION LAYER. The maker's ask was "if any two of these
# line spells hit each other they should EXPLODE and go away — same if it hits the
# ice wall, use common sense for how they interact."
#
# Every one of those wall rows was already authored in ReactionTable and already
# implemented in ReactionOutcomes. What was missing was the other end: IceWall and
# RockWall did not implement the participant contract at all, so they never
# registered, the reactor never saw them, and `shatter_ice_barrier`,
# `shrapnel_cone`, `ground_out`, `carve`, `breach` and `barrier_blocks` were all
# authored, implemented, tested — and unreachable. This suite is the proof that
# they are reachable now, driven against REAL walls rather than stubs, because a
# stub cannot fail the way the walls were failing.
#
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice_test_wall_reactions.gd
#
# ⚠ NOTHING HERE MAY NAME `IceWall` OR `RockWall` BY class_name. Doing so pulls
# them into this tool's compile-time dependency graph, and their raise paths name
# the `Sfx` autoload, which does not exist as a global identifier until the main
# loop is live — the whole file then fails to compile with "Identifier not found:
# Sfx". So both scripts are load()ed by path, statics go through `script.call(...)`
# and constants through `get_script_constant_map()`. Same reason SpellCaster
# load()s its spectacle scripts by path, and the same note sits at the top of
# tools/slice7_test_frost_field.gd and tools/slice_test_wall_two_beat.gd.
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
	"contract_surface",
	"rock_wall_reports_earth",
	"registration",
	"rock_wall_rams_ice",
	"shape_is_the_wall_you_see",
	"fire_beam_shatters_ice",
	"holy_beam_shatters_ice",
	"lightning_grounds_out_on_stone",
	"beam_carves_stone",
	"ult_breaches_where_heavy_is_stopped",
	"projectile_shrapnels_ice",
	"consumed_wall_cleans_up_like_expiry",
	"origin_parked_holds_with_a_wall",
]

const ICE_WALL_PATH: String = "res://scripts/combat/IceWall.gd"
const ROCK_WALL_PATH: String = "res://scripts/combat/RockWall.gd"

## Every method the participant contract requires of a barrier. `reaction_freeze`
## is deliberately absent — it is the OPTIONAL seize beat and a wall has nothing
## sensible to do with it (a frozen wall is just a wall).
const REQUIRED_CONTRACT: Array[String] = [
	"reaction_shape", "reaction_active", "reaction_element", "reaction_form",
	"reaction_owner", "reaction_weight", "reaction_consume",
]

## Where the walls are raised from. Far from the arena origin ON PURPOSE: these
## nodes park at (0, 0) and draw in world coordinates, so any test that happened to
## stand a wall at the origin would pass for a detector that read transforms.
const RAISE_FROM := Vector2(600.0, 0.0)
## A beam capsule crossing the wall's standing extent at mid-height. Wide enough
## to be a beam, long enough to reach through the wall from both sides.
const BEAM_WIDTH: float = 40.0
const BEAM_Y: float = -60.0

var _fails: int = 0
var _completed: Dictionary = {}

var _ice: GDScript = null
var _rock: GDScript = null
var _ic: Dictionary = {}   # IceWall's constants
var _rc: Dictionary = {}   # RockWall's constants
var _arena: Node2D = null
var _reactor: Node = null
var _casters: Array[Node] = []


## A live effect, duck-typed exactly like a real spectacle — and, like every real
## spectacle, PARKED AT THE ORIGIN with its geometry living somewhere else
## entirely. Copied in shape from tools/slice6_test_reactor.gd rather than shared,
## because a stub shared between suites is a stub that gets tuned for one of them.
class ReactantStub extends Node2D:
	var shape: Dictionary = {}
	var active: bool = true
	var form: int = 0
	var element: int = 0
	var weight: int = SpellTier.Tier.HEAVY
	var consumed: int = 0
	var frozen: int = 0
	var owner_node: Node = null

	func reaction_owner() -> Node:
		return owner_node

	func reaction_shape() -> Dictionary:
		return shape

	func reaction_active() -> bool:
		return active

	func reaction_element() -> int:
		return element

	func reaction_form() -> int:
		return form

	func reaction_weight() -> int:
		return weight

	func reaction_freeze() -> void:
		frozen += 1

	# Deliberately does NOT free itself, so the test can count consumptions.
	func reaction_consume() -> void:
		consumed += 1


func _initialize() -> void:
	# A GDScript error inside a coroutine kills that coroutine silently, so quit()
	# would never fire and the harness would spin forever. Fail loudly instead.
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("FAIL: harness watchdog fired — a test coroutine died before the end")
		quit(1))
	_run()


func _run() -> void:
	# One frame before anything touches the tree. _initialize() runs BEFORE the main
	# loop's first iteration, and a node added to `root` at that moment is not yet
	# "inside the active scene tree" — get_tree() comes back null and the absolute
	# /root/SpellReactor lookup inside raise_wall() throws.
	await process_frame
	_reactor = root.get_node_or_null(^"/root/SpellReactor")
	if _reactor == null:
		printerr("FAIL: SpellReactor autoload is missing")
		quit(1)
		return
	# Drive the sweep by hand instead of racing the 30 Hz timer, and suppress the
	# reaction SPECTACLE (not its consumption — see ReactionOutcomes._radial).
	_reactor.set_process(false)
	_reactor.set(&"spawn_effects", false)
	_ice = load(ICE_WALL_PATH) as GDScript
	_rock = load(ROCK_WALL_PATH) as GDScript
	_ic = _ice.get_script_constant_map()
	_rc = _rock.get_script_constant_map()
	_arena = Node2D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_test_contract_surface()
	_test_rock_wall_reports_earth()
	_test_registration()
	_test_rock_wall_rams_ice()
	_test_shape_is_the_wall_you_see()
	_test_fire_beam_shatters_ice()
	_test_holy_beam_shatters_ice()
	_test_lightning_grounds_out_on_stone()
	_test_beam_carves_stone()
	_test_ult_breaches_where_heavy_is_stopped()
	_test_projectile_shrapnels_ice()
	_test_consumed_wall_cleans_up_like_expiry()
	_test_origin_parked_holds_with_a_wall()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Wall reaction tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Wall reaction tests: all PASS")
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


# ---- harness ----------------------------------------------------------------

## Raise a REAL wall the way SpellCaster does: stamp identity FIRST (that is the
## order in SpellCaster.cast — `_stamp` then `raise_wall`, and it matters because
## registration captures the element), then raise it.
func _raise(script: GDScript, aim: Vector2, element: int, weight: int,
		caster: Node = null) -> Node2D:
	var w: Node2D = script.new()
	_arena.add_child(w)
	w.set("element_id", element)
	w.set("spell_tier", weight)
	w.set("caster_node", caster)
	w.call("raise_wall", RAISE_FROM, aim)
	return w


func _raise_ice(weight: int = SpellTier.Tier.HEAVY, caster: Node = null) -> Node2D:
	return _raise(_ice, Vector2.RIGHT, Elements.Element.ICE, weight, caster)


func _raise_rock(weight: int = SpellTier.Tier.HEAVY, caster: Node = null) -> Node2D:
	return _raise(_rock, Vector2.RIGHT, Elements.Element.EARTH, weight, caster)


## Where a wall raised by the helpers above actually stands. The node is at the
## origin; this is the only honest answer, and reading it off the wall's own
## published shape is the point.
func _wall_base(w: Node2D) -> Vector2:
	return w.get("_floor_base") as Vector2


## A beam-shaped reactant lying horizontally through `through`, long enough to
## cross the wall from both sides.
func _beam(form: int, element: int, weight: int, through: Vector2,
		caster: Node = null) -> ReactantStub:
	var s := ReactantStub.new()
	_arena.add_child(s)
	s.global_position = Vector2.ZERO
	s.form = form
	s.element = element
	s.weight = weight
	s.owner_node = caster if caster != null else _caster("attacker")
	s.shape = SpellGeometry.capsule(
		through - Vector2(500.0, 0.0), through + Vector2(500.0, 0.0), BEAM_WIDTH)
	_reactor.call(&"register", s, s.form, s.element)
	return s


## A distinct caster per call, so a beam and a wall read as DIFFERENT owners —
## which is the realistic case (your beam vs the boss's wall) and the one the
## weight-contest rows require.
func _caster(tag: String) -> Node:
	var n := Node.new()
	n.name = "Caster_%s" % tag
	root.add_child(n)
	_casters.append(n)
	return n


## Tear the arena back down between tests: MAX_LIVE is 12 and the groups
## ("ice_wall", "shoveable") are global, so a leaked wall poisons the next test.
## free() rather than queue_free() so each wall's _exit_tree — and therefore its
## unregister — runs synchronously, before the next test registers anything.
func _clear() -> void:
	for child: Node in _arena.get_children():
		_reactor.call(&"unregister", child)
		child.free()
	for c: Node in _casters:
		if is_instance_valid(c):
			c.free()
	_casters.clear()
	_expect(int(_reactor.call(&"live_count")) == 0,
		"teardown left the reactor empty (got %d)" % int(_reactor.call(&"live_count")))


# ---- the contract itself ----------------------------------------------------

## Both walls answer every question the reactor asks. This is the test that would
## have caught the whole gap: before tonight both walls failed it outright.
func _test_contract_surface() -> void:
	var F := ReactionTable.Form
	var ice: Node2D = _raise_ice()
	var rock: Node2D = _raise_rock()
	for m: String in REQUIRED_CONTRACT:
		_expect(ice.has_method(m), "IceWall implements %s()" % m)
		_expect(rock.has_method(m), "RockWall implements %s()" % m)
	_expect(int(ice.call("reaction_form")) == F.BARRIER, "an ice wall presents as a BARRIER")
	_expect(int(rock.call("reaction_form")) == F.BARRIER, "a rock wall presents as a BARRIER")
	_expect(int(ice.call("reaction_element")) == Elements.Element.ICE, "the ice wall is ICE")
	_expect(int(rock.call("reaction_element")) == Elements.Element.EARTH, "the rock wall is EARTH")
	_expect(int(ice.call("reaction_weight")) == SpellTier.Tier.HEAVY,
		"a stamped HEAVY ice wall reports HEAVY")
	_expect(int(rock.call("reaction_weight")) == SpellTier.Tier.HEAVY,
		"a stamped HEAVY rock wall reports HEAVY")
	_expect(bool(ice.call("reaction_active")) and bool(rock.call("reaction_active")),
		"a wall is a reactant from the frame it is raised — its collider already blocks")
	# The shapes are capsules, never circles: a barrier has a standing extent, and a
	# circle would be the one primitive that cannot express it.
	_expect(not SpellGeometry.is_circle(ice.call("reaction_shape")),
		"the ice wall publishes a capsule, not a circle")
	_expect(not SpellGeometry.is_circle(rock.call("reaction_shape")),
		"the rock wall publishes a capsule, not a circle")
	_clear()
	_completes("contract_surface")


## ⚠ THE ONE THAT WOULD HAVE FAILED SILENTLY. RockWall's element_id used to default
## to -1, and `SpellReactor.register()` REFUSES any effect with element < 0 — so a
## rock wall built without a stamp was turned away at the door and every earth row
## authored for it was unreachable, with nothing logged anywhere.
func _test_rock_wall_reports_earth() -> void:
	var bare: Node2D = _rock.new()
	_arena.add_child(bare)
	_expect(int(bare.get("element_id")) == Elements.Element.EARTH,
		"an UNSTAMPED rock wall is EARTH, not -1 (got %d)" % int(bare.get("element_id")))
	bare.call("raise_wall", RAISE_FROM, Vector2.RIGHT)
	_expect(int(_reactor.call(&"live_count")) == 1,
		"...so the reactor accepts it instead of dropping it at register()")
	# And the element genuinely reaches the table: these two rows are the entire
	# reason a rock wall has to be EARTH rather than merely non-negative.
	var E := Elements.Element
	var F := ReactionTable.Form
	var grounded: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.LIGHTNING, F.BARRIER, E.EARTH, "different",
		SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(String(grounded.get("outcome", "")) == "ground_out",
		"a lightning beam into stone resolves to ground_out (got '%s')"
			% String(grounded.get("outcome", "")))
	var carved: Dictionary = ReactionTable.match_rule(
		F.BEAM, E.ARCANE, F.BARRIER, E.EARTH, "different",
		SpellTier.Tier.HEAVY, SpellTier.Tier.HEAVY)
	_expect(String(carved.get("outcome", "")) == "carve",
		"an evenly matched beam into stone resolves to carve (got '%s')"
			% String(carved.get("outcome", "")))
	_clear()
	_completes("rock_wall_reports_earth")


## Raising registers, and leaving the tree unregisters — including the case that
## actually happens in play, where the wall frees itself on its own timeline and
## nobody calls unregister at all.
func _test_registration() -> void:
	var ice: Node2D = _raise_ice()
	_expect(int(_reactor.call(&"live_count")) == 1, "raising an ice wall registers it")
	var rock: Node2D = _raise_rock()
	_expect(int(_reactor.call(&"live_count")) == 2, "raising a rock wall registers it too")
	ice.free()
	_expect(int(_reactor.call(&"live_count")) == 1,
		"a freed wall unregisters itself through _exit_tree")
	rock.free()
	_expect(int(_reactor.call(&"live_count")) == 0, "and so does the other one")
	# THE SILENCE — but now with SAME-MATERIAL walls, which is what the authored
	# `none` row actually means. This assertion used to raise stone next to ice and
	# claim they do not react; that was a description of the table at the time, not
	# a design decision, and STONE x ICE is now a deliberate authored exception (the
	# RAM — a shoved rock wall grinding into a sheet of ice, which RockWall's own
	# reaction_form() doc asks the table for by name). Two barriers of the same
	# material touching is still architecture rather than an event.
	var a: Node2D = _raise_rock()
	var b: Node2D = _raise_rock()
	_expect(int(_reactor.call(&"live_count")) == 2, "setup: two stone walls are live")
	_expect(int(_reactor.call(&"resolve_now")) == 0,
		"two walls of the same material standing in one place do not react")
	_clear()
	_completes("registration")


## THE RAM, against REAL walls rather than stubs. The stub suites can prove the
## table matches; only this can prove the outcome lands on the right side — that
## the ICE dies through its own shatter() and the STONE grinds on. That asymmetry
## is the swapped-side trap: a row may match with its sides reversed, and reading
## the raw consumes_a/consumes_b flags instead of consumes_caller() would burst the
## wrong wall, which looks like a physics bug rather than a table bug.
func _test_rock_wall_rams_ice() -> void:
	var rock: Node2D = _raise_rock()
	var ice: Node2D = _raise_ice()
	_expect(int(_reactor.call(&"resolve_now")) == 1, "the stone meets the ice")
	_expect(bool(ice.get("_shattered")), "the ICE wall bursts")
	_expect(not bool(rock.get("_crumbling")), "...and the STONE grinds on through it")
	_clear()
	_completes("rock_wall_rams_ice")


## THE SHAPE IS THE WALL. Five drawn-vs-damaged mismatches were found across this
## codebase, so the reaction volume is asserted against the wall's OWN authored
## footprint at both ends: it must cover the wall, and it must not promise reach
## past it. The capsule end-cap inset is what the top/bottom assertions are really
## testing — without it each wall would claim a half-width of phantom reach above
## its crown and the same again underground.
func _test_shape_is_the_wall_you_see() -> void:
	var isize: Vector2 = _ic["WALL_SIZE"] as Vector2
	var ihw: float = float(_ic["REACTION_HALF_WIDTH"])
	var pool: float = float(_ic["GROUND_POOL_RADIUS"])
	var ice: Node2D = _raise_ice()
	var ibase: Vector2 = _wall_base(ice)
	var ishape: Dictionary = ice.call("reaction_shape")
	_expect(ice.global_position == Vector2.ZERO,
		"the wall node really is parked at the origin — its shape is the only truth")
	_expect(SpellGeometry.contains_point(ishape, ibase + Vector2(0.0, -isize.y * 0.5)),
		"the ice wall's own mid-height is inside its reaction volume")
	_expect(SpellGeometry.contains_point(ishape, ibase + Vector2(ihw - 1.0, -isize.y * 0.5)),
		"...and so is a point a pixel inside its drawn edge")
	_expect(not SpellGeometry.contains_point(ishape, ibase + Vector2(ihw + 1.0, -isize.y * 0.5)),
		"...while a pixel outside it is NOT")
	_expect(not SpellGeometry.contains_point(ishape, ibase + Vector2(0.0, -isize.y - 2.0)),
		"the volume stops at the crown instead of capping over it")
	_expect(not SpellGeometry.contains_point(ishape, ibase + Vector2(0.0, 2.0)),
		"...and stops at the floor instead of reaching underground")
	# THE REACH CONTRACT this wall already had: nothing it does may reach past the
	# widest thing it draws while it stands (see IceWall's GROUND_POOL_RADIUS note).
	_expect(ihw <= pool,
		"the reaction half-width (%s) stays inside the drawn frost pool (%s)" % [ihw, pool])
	# The same volume the chill already uses, which is the whole point of reusing it:
	# one wall, one answer to "are you touching this".
	_expect(bool(_ice.call("chill_contains", ibase, ibase + Vector2(ihw - 1.0, -40.0))),
		"the reaction edge and the chill edge are the SAME edge")
	var rsize: Vector2 = _rc["WALL_SIZE"] as Vector2
	var rhw: float = float(_rc["REACTION_HALF_WIDTH"])
	var rock: Node2D = _raise_rock()
	var rbase: Vector2 = _wall_base(rock)
	var rshape: Dictionary = rock.call("reaction_shape")
	_expect(SpellGeometry.contains_point(rshape, rbase + Vector2(rhw - 1.0, -rsize.y * 0.5)),
		"a point a pixel inside the rock wall's drawn edge is inside its volume")
	_expect(not SpellGeometry.contains_point(rshape, rbase + Vector2(rhw + 1.0, -rsize.y * 0.5)),
		"...while a pixel outside it is NOT")
	_expect(not SpellGeometry.contains_point(rshape, rbase + Vector2(0.0, -rsize.y - 2.0)),
		"the rock volume stops at the crown")
	# A shoved wall's shape TRACKS it. The reaction layer reads _floor_base, which
	# _process_slide moves, so this needs nothing kept in sync — but a refactor that
	# cached the shape at raise time would break exactly here.
	_expect(bool(rock.call("shove", Vector2.RIGHT)), "setup: the wall accepts a shove")
	rock.set("_floor_base", rbase + Vector2(300.0, 0.0))
	var moved: Dictionary = rock.call("reaction_shape")
	_expect(not SpellGeometry.contains_point(moved, rbase + Vector2(0.0, -rsize.y * 0.5)),
		"a slid wall's volume left its old position behind")
	_expect(SpellGeometry.contains_point(moved, rbase + Vector2(300.0, -rsize.y * 0.5)),
		"...and is where the wall now is")
	_clear()
	_completes("shape_is_the_wall_you_see")


# ---- the previously-unreachable rows ----------------------------------------

## THE HEADLINE. "Same if it hits the ice wall — use common sense." Fire meets ice:
## the wall goes, through its OWN authored death (shards, the group exit, the
## collider disable), and the beam walks away.
func _test_fire_beam_shatters_ice() -> void:
	var wall: Node2D = _raise_ice()
	var base: Vector2 = _wall_base(wall)
	var beam: ReactantStub = _beam(ReactionTable.Form.BEAM, Elements.Element.FIRE,
		SpellTier.Tier.HEAVY, base + Vector2(0.0, BEAM_Y))
	_expect(int(_reactor.call(&"resolve_now")) == 1, "the fire beam meets the ice wall once")
	_expect(bool(wall.get("_shattered")), "the wall SHATTERED")
	_expect(not wall.is_in_group("ice_wall"), "...and left the ice_wall group doing it")
	_expect(not bool(wall.call("reaction_active")), "...and is no longer a reactant")
	_expect(beam.consumed == 0, "the beam is not spent — fire beats ice, it does not trade")
	_expect(int(_reactor.call(&"resolve_now")) == 0, "and the pair does not fire again")
	_clear()
	_completes("fire_beam_shatters_ice")


## The row names HOLY as well as FIRE, and one element list is exactly the kind of
## thing that gets half-asserted.
func _test_holy_beam_shatters_ice() -> void:
	var wall: Node2D = _raise_ice()
	var base: Vector2 = _wall_base(wall)
	var beam: ReactantStub = _beam(ReactionTable.Form.BEAM, Elements.Element.HOLY,
		SpellTier.Tier.HEAVY, base + Vector2(0.0, BEAM_Y))
	_expect(int(_reactor.call(&"resolve_now")) == 1, "holy light meets the ice wall")
	_expect(bool(wall.get("_shattered")), "the wall shatters for holy too")
	_expect(beam.consumed == 0, "...and the beam is not spent")
	_clear()
	_completes("holy_beam_shatters_ice")


## EARTH GENUINELY COUNTERS A SCHOOL. The row spends the BEAM and leaves the wall
## standing, which is the opposite side of every other barrier row and therefore
## the one most likely to be wired backwards.
func _test_lightning_grounds_out_on_stone() -> void:
	var wall: Node2D = _raise_rock()
	var base: Vector2 = _wall_base(wall)
	var beam: ReactantStub = _beam(ReactionTable.Form.BEAM, Elements.Element.LIGHTNING,
		SpellTier.Tier.HEAVY, base + Vector2(0.0, BEAM_Y))
	_expect(int(_reactor.call(&"resolve_now")) == 1, "the lightning beam meets the stone")
	_expect(beam.consumed == 1, "the beam is GROUNDED OUT — earth eats lightning")
	_expect(not bool(wall.get("_crumbling")), "...and the wall is untouched")
	_expect(bool(wall.call("reaction_active")), "...and still a reactant")
	_clear()
	_completes("lightning_grounds_out_on_stone")


## CARVE — the authored exception where a barrier is porous. Stone is bored
## THROUGH by an evenly matched beam: nothing at all is spent, which is a reaction
## whose whole content is "the wall did not stop you".
func _test_beam_carves_stone() -> void:
	var wall: Node2D = _raise_rock()
	var base: Vector2 = _wall_base(wall)
	var beam: ReactantStub = _beam(ReactionTable.Form.BEAM, Elements.Element.ARCANE,
		SpellTier.Tier.HEAVY, base + Vector2(0.0, BEAM_Y))
	_expect(int(_reactor.call(&"resolve_now")) == 1, "the beam bores into the stone")
	_expect(beam.consumed == 0, "the beam is NOT stopped — that is the whole row")
	_expect(not bool(wall.get("_crumbling")), "...and the wall is not broken either")
	_clear()
	_completes("beam_carves_stone")


## THE LADDER, on the wall that has no carve exception. An ULT breaches; a HEAVY —
## evenly matched with the wall — is merely stopped and spent on it. The pair is
## asserted together because either half alone is satisfied by a wall that always
## wins (or always loses).
func _test_ult_breaches_where_heavy_is_stopped() -> void:
	var wall: Node2D = _raise_ice()
	var base: Vector2 = _wall_base(wall)
	var heavy: ReactantStub = _beam(ReactionTable.Form.BEAM, Elements.Element.ARCANE,
		SpellTier.Tier.HEAVY, base + Vector2(0.0, BEAM_Y))
	_expect(int(_reactor.call(&"resolve_now")) == 1, "the evenly matched beam meets the wall")
	_expect(heavy.consumed == 1, "a HEAVY beam is STOPPED by a HEAVY wall")
	_expect(not bool(wall.get("_shattered")), "...and the wall holds")
	_clear()
	var wall2: Node2D = _raise_ice()
	var base2: Vector2 = _wall_base(wall2)
	var ult: ReactantStub = _beam(ReactionTable.Form.BEAM, Elements.Element.ARCANE,
		SpellTier.Tier.ULT, base2 + Vector2(0.0, BEAM_Y))
	_expect(int(_reactor.call(&"resolve_now")) == 1, "the ult meets the same wall")
	_expect(bool(wall2.get("_shattered")), "an ULT beam BREACHES it")
	_expect(ult.consumed == 0, "...and is not spent doing so — an ult must feel like one")
	_clear()
	_completes("ult_breaches_where_heavy_is_stopped")


## SHRAPNEL_CONE — a thrown thing bursting an ice wall throws the shards ALONG its
## flight rather than in a ring, so breaking a wall toward someone is a play. The
## outcome's directionality is ReactionOutcomes' business; what is proved here is
## that a PROJECTILE reaches the row at all, which it could not before.
func _test_projectile_shrapnels_ice() -> void:
	var fired: Dictionary = {}
	var seen: Callable = func(outcome: String, _p: Vector2, _a: Node, _b: Node) -> void:
		fired[outcome] = true
	_reactor.connect(&"reaction_fired", seen)
	var wall: Node2D = _raise_ice()
	var base: Vector2 = _wall_base(wall)
	var shot: ReactantStub = _beam(ReactionTable.Form.PROJECTILE, Elements.Element.EARTH,
		SpellTier.Tier.HEAVY, base + Vector2(0.0, BEAM_Y))
	_expect(int(_reactor.call(&"resolve_now")) == 1, "the projectile meets the ice wall")
	_expect(fired.has("shrapnel_cone"),
		"...and it is SHRAPNEL_CONE, not the generic barrier_blocks (fired: %s)"
			% str(fired.keys()))
	_expect(bool(wall.get("_shattered")), "the wall bursts")
	_expect(shot.consumed == 0, "...and the thrown thing punches through")
	_reactor.disconnect(&"reaction_fired", seen)
	_clear()
	_completes("projectile_shrapnels_ice")


## A wall spent by a reaction must clean up EXACTLY like one that expired on its
## own — same group exit, same collider disable, same teardown. A second, private
## teardown path is how a wall ends up freed while still in the group the two-beat
## searches, which would break the maker's "first press summons, second press
## punches" combo without breaking any test that only looked at reactions.
func _test_consumed_wall_cleans_up_like_expiry() -> void:
	# ICE: the reaction must go through shatter(), the wall's own documented death.
	var ice: Node2D = _raise_ice()
	_expect(ice.is_in_group("ice_wall"), "setup: a standing ice wall is grouped")
	ice.call("reaction_consume")
	_expect(bool(ice.get("_shattered")), "reaction_consume() runs the wall's own shatter()")
	_expect(not ice.is_in_group("ice_wall"), "...which leaves the group")
	ice.call("reaction_consume")
	_expect(bool(ice.get("_shattered")), "...and consuming twice is harmless (shatter is idempotent)")
	# ROCK: the crumble, reached the same way _slam_stop() reaches it — and the
	# "shoveable" registry the two-beat searches must be left clean.
	var rock: Node2D = _raise_rock()
	_expect(rock.is_in_group("shoveable"), "setup: a standing rock wall is shoveable")
	_expect(bool(rock.call("can_shove")), "setup: and can answer a punch")
	rock.call("reaction_consume")
	_expect(bool(rock.get("_crumbling")), "reaction_consume() crumbles the rock wall")
	_expect(not rock.is_in_group("shoveable"), "...and takes it out of the shoveable registry")
	_expect(not bool(rock.call("can_shove")), "...so a press cannot be eaten by a dead wall")
	_expect(not bool(rock.call("reaction_active")), "...and it is no longer a reactant")
	# THE TWO-BEAT'S OWN SEARCH agrees — it is the thing that actually spends a
	# button press, so it is asserted directly rather than inferred from the group.
	_expect(_rock.call("find_shoveable_near", self, _wall_base(rock), 400.0) == null,
		"find_shoveable_near() no longer offers a consumed wall")
	# ...and a wall that has NOT been consumed is still found, so the assertion above
	# cannot be passing because the search is simply broken.
	var live: Node2D = _raise_rock()
	_expect(_rock.call("find_shoveable_near", self, _wall_base(live), 400.0) == live,
		"...while a standing wall still is")
	_clear()
	_completes("consumed_wall_cleans_up_like_expiry")


## ⚠ THE REGRESSION THE WHOLE LAYER EXISTS FOR, re-asserted with a REAL WALL in the
## pairing. Walls park at (0, 0) and draw in world coordinates exactly like the ten
## spell spectacles that motivated this design, so a detector that started trusting
## transforms would report a wall in Ashspire as touching a beam across the arena —
## and would report it for EVERY pair, at the top-left corner. This suite adds the
## case slice6_test_reactor.gd could not: a live participant whose (0, 0) transform
## is real production code rather than a stub's.
func _test_origin_parked_holds_with_a_wall() -> void:
	var wall: Node2D = _raise_ice()
	var base: Vector2 = _wall_base(wall)
	# A fire beam 4000 px away — the pair that WOULD have shattered the wall if it
	# were anywhere near it.
	var beam: ReactantStub = _beam(ReactionTable.Form.BEAM, Elements.Element.FIRE,
		SpellTier.Tier.HEAVY, base - Vector2(4000.0, 0.0))
	_expect(wall.global_position == Vector2.ZERO and beam.global_position == Vector2.ZERO,
		"both participants really are parked at the origin")
	_expect(base.distance_to(Vector2.ZERO) > 100.0,
		"...and the wall's real position is nowhere near it (%s)" % base)
	_expect(int(_reactor.call(&"resolve_now")) == 0,
		"an origin-parked WALL and an origin-parked beam 4000 px apart do NOT react")
	_expect(not bool(wall.get("_shattered")), "...and the wall is untouched")
	# Positive control: same nodes, same transforms, the beam's SHAPE moved onto the
	# wall. If this stops firing, the assertion above has started passing for the
	# wrong reason (a wall that can never react passes it trivially).
	beam.shape = SpellGeometry.capsule(
		base + Vector2(-500.0, BEAM_Y), base + Vector2(500.0, BEAM_Y), BEAM_WIDTH)
	_expect(int(_reactor.call(&"resolve_now")) == 1,
		"...and DO react once the beam's shape actually reaches the wall")
	_expect(bool(wall.get("_shattered")), "...shattering it")
	_clear()
	_completes("origin_parked_holds_with_a_wall")
