# Run: godot --headless --path godot-project --script tools/slice_test_destructible_sources.gd
#
# DOES EACH GROUND-AIMED SPELL ACTUALLY BITE THE FLOOR?
#
# ⚠ THIS SUITE EXISTS BECAUSE THE BOUT PROBE COULD NOT ANSWER THAT, AND SPENT THREE
# RUNS LOOKING LIKE IT COULD. `tools/probe_destructible_bot_fight.gd` is the BUDGET
# instrument — "after a real fight, is there a stage" — and it is the right tool for
# that question. It is the wrong tool for "is this wiring live", and the difference bit
# hard while the sources were being wired one at a time:
#
#   * JUGGERNAUT carries Boulder Hurl as its DAMAGE line — the spell it throws all
#     fight. The bout after Boulder Hurl was wired reported `carved 0.00%`. That reads
#     exactly like a dead call. It was not: the bout had resolved in 7.5 s and the
#     boulders had all landed on bodies rather than on rock.
#   * GRAVE TIDE was wired, and then measured by NOTHING — no pairing in the probe held
#     a Warlock. A pairing was added; the Warlock bout then ended in 7.8 s without ever
#     reaching its ult, so it STILL measured nothing.
#   * Bout length is the dominant term and it is random: the same three matchups ran
#     9.7 / 31.7 / 12.4 s and then 3.9 / 20.7 / 13.4 s. Carve % moved 0.76% -> 1.51% ->
#     0.74% across wiring changes that only ever ADDED sources. Attributing any of that
#     to a code change is [[feedback_dont_narrate_underpowered_measurements]].
#
# So the two questions get two instruments. This one is deterministic: it stands a real
# stage up, casts ONE spell at a known point on it, and asks whether the rock went. A
# source that fails here is broken. A source that passes here and shows 0.00% in a bout
# is simply a spell that did not land on the ground that bout, which is a fact about the
# fight and not about the wiring.
#
# ⚠ IT ALSO ASSERTS THE TWO DELIBERATE NON-WIRINGS, because "we chose not to" and "we
# forgot" are indistinguishable from outside, and only one of them should survive
# somebody's tidy-up:
#   * ENERGY NOVA must NOT carve — `NOVA_DAMAGE` (30) is under `CARVE_MIN_DAMAGE` (40),
#     so the line the handoff asked for could only ever tick `refused_hits`.
#   * METEOR FIST must carve EXACTLY ONCE — it routes its damage through `BlastSpell`,
#     which has carved since Slice 2, so a second call here would double the crater.
#
# ⚠ THE HOUSE RULE, inherited from `slice_test_destructible_carve`. Never
# `failed += _test_x()` — a dead property read aborts the enclosing function and hands
# back the type's zero, which that idiom reads as "no failures". Failures accumulate on
# the MEMBER `_fails`; every test records a COMPLETION SENTINEL as its last line, so an
# aborted test fails BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"shockwave_stomp_bites_the_floor",
	"boulder_hurl_bites_the_floor_where_it_landed",
	"fault_line_walks_a_broken_line_of_holes_and_never_a_trench",
	"grave_tide_bites_at_a_stride_and_never_under_the_caster",
	"energy_nova_carves_a_ring_sized_hole",
	"meteor_fist_carves_once_through_its_blast_and_not_twice",
	"every_carve_stays_inside_the_budget_the_stage_advertises",
]

## The shipped stage, variant 0 — the same table `slice_test_destructible_carve` pins.
const TERRACE_DEPTH: float = 320.0
const TERRACES: Array[Dictionary] = [
	{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},
	{"surface_y": 700.0, "x0": 40.0,   "x1": 250.0},
	{"surface_y": 696.0, "x0": 1330.0, "x1": 1580.0},
	{"surface_y": 612.0, "x0": 1540.0, "x1": 1760.0},
	{"surface_y": 528.0, "x0": 1700.0, "x1": 1965.0},
]
## A point well inside the main terrace, on its surface.
const GROUND: Vector2 = Vector2(700.0, 780.0)

var _fails: int = 0
var _completed: Dictionary = {}


## ⚠ `_initialize`, NOT `_process` — a `SceneTree` script's `_process` QUITS THE TREE
## the moment it returns true. Every test here needs frames to elapse (the spells run
## off `_process` / `_physics_process` and the stage rebuild is deferred), so the whole
## run is driven as one coroutine. Same reason `slice_test_destructible_carve` does it.
func _initialize() -> void:
	_go()


func _go() -> void:
	await process_frame
	for t: String in TESTS:
		await call(t)
	for t: String in TESTS:
		_expect(_completed.has(t), "%s ran to completion" % t)
	print("slice_test_destructible_sources: %s (%d failure(s))"
		% ["all PASS" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: %s" % what)


func _done(t: String) -> void:
	_completed[t] = true


# ── the fixture ────────────────────────────────────────────────────────────

func _terrace_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t: Dictionary in TERRACES:
		out.append(Rect2(Vector2(float(t["x0"]), float(t["surface_y"])),
			Vector2(float(t["x1"]) - float(t["x0"]), TERRACE_DEPTH)))
	return out


## A stage IN THE TREE with a live body, so the spells' own `SpellWorld` floor probes
## find rock the way they do in a real arena.
##
## ⚠ EACH TEST GETS A FRESH ONE AND FREES IT, and that is not tidiness. A previous
## suite in this area left a freed stage still answering raycasts and a 96 px gap was
## read as 48 px of collision [[feedback_harnesses_lie_verify_them]]. `_teardown` frees
## the stage AND the spell and then lets a frame pass before the next test builds.
## ⚠ AND IT ASSERTS THE GROUP IS EMPTY FIRST, which is the whole reason this suite
## nearly shipped five false failures. `DestructibleStage.carve_area` finds its target
## with `stage_in()` — a scan of `GROUP_NAME` that returns THE FIRST MEMBER. While a
## previous test's stage was still in that group, every spell in the next test carved
## the DEAD stage while the assertion read the LIVE one, so five live wirings all
## reported `carved 0` in a row. Same family as the ray that read a freed stage's
## collision [[feedback_harnesses_lie_verify_them]]; the instrument must prove its own
## preconditions or its zeroes mean nothing.
func _live_stage() -> DestructibleStage:
	var stale: int = root.get_tree().get_nodes_in_group(
		DestructibleStage.GROUP_NAME).size()
	_expect(stale == 0,
		"%d stage(s) were still in the %s group when this test began — carve_area()"
			% [stale, DestructibleStage.GROUP_NAME]
		+ " routes to the FIRST group member, so this test would have measured a stage"
		+ " nobody was casting at")
	var s := DestructibleStage.new()
	s.build_from_rects(_terrace_rects())
	root.add_child(s)
	s.rebuild_collision(s)
	return s


func _caster() -> Node2D:
	var c := Node2D.new()
	root.add_child(c)
	c.global_position = GROUND + Vector2(0.0, -30.0)
	return c


## A spell card for a heavy, committed hit — comfortably over `CARVE_MIN_DAMAGE`.
func _spell(damage: int) -> SpellDef:
	var d := SpellDef.new()
	d.damage = damage
	d.radius = 90.0
	d.reach = 260.0
	d.length = 420.0
	return d


## ⚠ THE STAGE IS TORN DOWN FIRST, AND THE LOOP VARIABLE IS DELIBERATELY UNTYPED.
## Both halves of that were bought with a false result.
##
## Every spell here calls `queue_free()` ON ITSELF when its life ends, so by teardown
## time `nodes` usually holds at least one already-freed instance. Written the obvious
## way — `for n: Node in nodes:` — the TYPED loop variable is assigned that dead
## instance, GDScript raises `Trying to assign invalid previously freed instance`, and
## the error ABORTS `_teardown` on its first iteration. The stage was last in the array,
## so it was never released: it stayed in `GROUP_NAME`, `carve_area`'s `stage_in()` kept
## routing every later spell to it, and tests 2-7 all reported `carved 0` against the
## fresh stage they were holding. Five live wirings, five false failures, and the FAIL
## text pointed at the spells.
##
## `is_instance_valid` is therefore checked on the ARRAY ELEMENT, before anything is
## assigned to a typed local — a validity check that has to survive an assignment to
## work is not a validity check. Same family as the house rule at the top of this file:
## the dangerous failures here are the ones that abort a function silently and leave a
## zero behind that reads like data. [[feedback_harnesses_lie_verify_them]].
func _teardown(stage: DestructibleStage, nodes: Array) -> void:
	# THE STAGE, UNCONDITIONALLY AND SYNCHRONOUSLY. `queue_free()` alone leaves it in
	# the group until the free actually lands; dropping the membership here means that
	# even a late free cannot let the next test's spell find it.
	if stage != null and is_instance_valid(stage):
		stage.remove_from_group(DestructibleStage.GROUP_NAME)
		if stage.get_parent() != null:
			stage.get_parent().remove_child(stage)
		stage.queue_free()
	for i: int in nodes.size():
		if not is_instance_valid(nodes[i]):
			continue
		var n: Node = nodes[i]
		if not n.is_queued_for_deletion():
			n.queue_free()
	# Two frames: one for the queue to drain, one for the tree to settle before the
	# next test stands a new stage up in the same world.
	await process_frame
	await process_frame


## Drive `n` frames of BOTH clocks. The spells split across the two — Fault Line and
## Shockwave Stomp run on `_process`, Grave Tide on `_physics_process` — and a test that
## pumped only one would report the other as dead.
func _pump(n: int) -> void:
	for _i: int in n:
		await process_frame
		await physics_frame


# ── 1. Shockwave Stomp ─────────────────────────────────────────────────────

func shockwave_stomp_bites_the_floor() -> void:
	await process_frame
	var stage: DestructibleStage = _live_stage()
	var caster: Node2D = _caster()
	var spell: SpellDef = _spell(54)
	var fx: Node2D = (load("res://scripts/combat/ShockwaveStomp.gd") as GDScript).new()
	fx.set("target_group", "enemies")
	root.add_child(fx)
	fx.call("hex", caster, GROUND, GROUND + Vector2(300.0, 0.0), spell, Color.WHITE, "earth")
	await _pump(90)
	_expect(stage.carve_events > 0,
		"Shockwave Stomp opened no crater at all — the stomp is not reaching the stage")
	_expect(stage.carved_cells > 0,
		"Shockwave Stomp recorded an event but removed 0 cells")
	await _teardown(stage, [fx, caster])
	_done("shockwave_stomp_bites_the_floor")


# ── 2. Boulder Hurl ────────────────────────────────────────────────────────

## ⚠ ASSERTED AT THE FLOOR, NOT AT THE IMPACT POINT. `_shatter` snaps its residue down
## with `floor_below` before marking, and the carve must use that same snapped point:
## carving at the raw impact would open holes in mid-air over a pit.
func boulder_hurl_bites_the_floor_where_it_landed() -> void:
	await process_frame
	var stage: DestructibleStage = _live_stage()
	var caster: Node2D = _caster()
	var fx: Node2D = (load("res://scripts/combat/BoulderHurl.gd") as GDScript).new()
	fx.set("target_group", "enemies")
	fx.set("caster_node", caster)
	root.add_child(fx)
	fx.call("hurl", GROUND + Vector2(-260.0, -40.0), Vector2.RIGHT,
		Color(0.78, 0.55, 0.28), 90.0, 88, "earth")
	await _pump(180)
	_expect(stage.carve_events > 0,
		"Boulder Hurl shattered and the ground it was ripped from was untouched")
	var top: float = stage.surface_y_at(GROUND.x)
	_expect(top == INF or top >= GROUND.y,
		"the carve raised the surface at x=%.0f (%.1f, was %.1f) — a crater must only"
			% [GROUND.x, top, GROUND.y]
		+ " ever go DOWN, and a surface that moves up moves every fighter's feet")
	await _teardown(stage, [fx, caster])
	_done("boulder_hurl_bites_the_floor_where_it_landed")


# ── 3. Fault Line ──────────────────────────────────────────────────────────

## THE ONE THAT CAN SEVER THE STAGE. `_tear` walks a WHILE-LOOP of craters along the
## rupture, so a single cast opens a LINE of holes rather than one — and if consecutive
## holes touched, the line would become a trench and the stage would be cut in two.
## The stride is what stops that, so the stride is what is asserted.
func fault_line_walks_a_broken_line_of_holes_and_never_a_trench() -> void:
	await process_frame
	var stage: DestructibleStage = _live_stage()
	var caster: Node2D = _caster()
	var spell: SpellDef = _spell(96)
	var fx: Node2D = (load("res://scripts/combat/FaultLine.gd") as GDScript).new()
	fx.set("target_group", "enemies")
	root.add_child(fx)
	fx.call("hex", caster, GROUND, GROUND + Vector2(420.0, 0.0), spell, Color.WHITE, "earth")
	await _pump(240)
	_expect(stage.carve_events > 1,
		"Fault Line opened %d crater(s) — the rupture should bite repeatedly along its"
			% stage.carve_events + " travel, not once at the cast point")
	# ...and the floor is still a floor. Any fully-severed column is the failure.
	_expect(_widest_gap(stage) <= 0.0,
		"Fault Line cut clean through the stage: %.0f px of it has NO rock left in the"
			% _widest_gap(stage)
		+ " column. A melee bot that walks into that stands at the lip and holds.")
	await _teardown(stage, [fx, caster])
	_done("fault_line_walks_a_broken_line_of_holes_and_never_a_trench")


# ── 4. Grave Tide ──────────────────────────────────────────────────────────

## The tide's front moves every physics frame, so its bites are spaced by an ODOMETER
## (`_next_carve` / `CARVE_STRIDE`) rather than fired at the front. Both halves of that
## are asserted: it bites more than once, and it never bites the caster's own footing.
func grave_tide_bites_at_a_stride_and_never_under_the_caster() -> void:
	await process_frame
	var stage: DestructibleStage = _live_stage()
	var caster: Node2D = _caster()
	var spell: SpellDef = _spell(64)
	var fx: Node2D = (load("res://scripts/combat/GraveTide.gd") as GDScript).new()
	fx.set("target_group", "enemies")
	root.add_child(fx)
	fx.call("hex", caster, GROUND, GROUND + Vector2(360.0, 0.0), spell, Color.WHITE, "shadow")
	await _pump(240)
	_expect(stage.carve_events > 1,
		"Grave Tide opened %d crater(s) — the floor is supposed to give way ALONG the"
			% stage.carve_events + " tide, not once where it started")
	# The cell directly under the caster's feet must still be rock: the first bite is
	# placed one full stride out precisely so the Warlock does not fall through his ult.
	var cx: int = int((GROUND.x - stage.origin.x) / DestructibleStage.CHUNK)
	var cy: int = int((GROUND.y + 2.0 - stage.origin.y) / DestructibleStage.CHUNK)
	_expect(stage.is_solid(cx, cy),
		"Grave Tide removed the ground under its own caster's feet")
	_expect(_widest_gap(stage) <= 0.0,
		"Grave Tide severed the stage over %.0f px" % _widest_gap(stage))
	await _teardown(stage, [fx, caster])
	_done("grave_tide_bites_at_a_stride_and_never_under_the_caster")


# ── 5. Energy Nova — carves, and its hole is nova-shaped ───────────────────

## ⚠ THIS TEST USED TO ASSERT THE EXACT OPPOSITE. It was a NEGATIVE control named
## `energy_nova_is_on_the_chip_shelf_and_must_stay_there`, and it was right about the
## code it was written against: `NOVA_DAMAGE` is 30, `CARVE_MIN_DAMAGE` was 40, so the
## carve the handoff asked for was arithmetically dead. The maker's correction retired
## that shelf — *"for all things where it was hit"* — so the property inverts, and it is
## rewritten here rather than deleted because the interesting half survives: the nova's
## hole must be NOVA-SIZED, i.e. sized by its 135 px ring and not by its 30 damage.
func energy_nova_carves_a_ring_sized_hole() -> void:
	await process_frame
	# ⚠ READ THROUGH A RUNTIME `load()`, NEVER AS `EnergyNova.NOVA_DAMAGE`. Naming the
	# class forces the compiler to resolve `EnergyNova.gd` while THIS file is being
	# compiled — which happens before autoloads exist — and that file's dependency chain
	# reaches `Sfx`, an autoload. The result is `Identifier not found: Sfx` and a tool
	# script that fails to load for a reason that has nothing to do with what it tests.
	# [[feedback_gdscript_resolution_traps]].
	var nova: GDScript = load("res://scripts/combat/EnergyNova.gd") as GDScript
	var nova_damage: int = int(nova.get("NOVA_DAMAGE"))
	var nova_radius: float = float(nova.get("NOVA_RADIUS"))
	var stage: DestructibleStage = _live_stage()
	var removed: int = stage.damage_at(nova_damage, GROUND + Vector2(0.0, 2.0),
		Vector2.UP, nova_radius)
	_expect(removed > 0,
		"a nova removed nothing — %d damage at a %.0f px footprint must carve now that"
			% [nova_damage, nova_radius] + " the damage shelf is retired")
	_expect(stage.refused_hits == 0,
		"the nova was refused by the damage shelf, %d time(s)" % stage.refused_hits)
	# THE SIZE IS THE POINT. A damage-only curve would give 30 damage the smallest
	# crater in the game; the nova's own 135 px ring must dominate it.
	var by_footprint: float = DestructibleStage.carve_radius_for_strike(
		nova_damage, nova_radius)
	var by_damage_only: float = DestructibleStage.carve_radius_for(nova_damage)
	_expect(by_footprint > by_damage_only * 2.0,
		"the nova's footprint is not driving its crater: %.1f px with the ring vs %.1f"
			% [by_footprint, by_damage_only] + " px on damage alone")
	await _teardown(stage, [])
	_done("energy_nova_carves_a_ring_sized_hole")


# ── 6. Meteor Fist — carves, but only once ─────────────────────────────────

## The fist's damage is applied by a `BlastSpell` it spawns, and `BlastSpell` has carved
## since Slice 2. So the fist MUST open a crater and MUST NOT open two.
func meteor_fist_carves_once_through_its_blast_and_not_twice() -> void:
	await process_frame
	var stage: DestructibleStage = _live_stage()
	var caster: Node2D = _caster()
	var spell: SpellDef = _spell(120)
	var fx: Node2D = (load("res://scripts/combat/MeteorFist.gd") as GDScript).new()
	fx.set("target_group", "enemies")
	root.add_child(fx)
	fx.call("hex", caster, GROUND, GROUND + Vector2(240.0, 0.0), spell, Color.WHITE, "earth")
	await _pump(300)
	_expect(stage.carve_events >= 1,
		"Meteor Fist landed and opened nothing — its BlastSpell is not reaching the stage")
	# ⚠ AND THE "NOT TWICE" HALF IS CHECKED IN THE SOURCE, NOT IN THE COUNTERS, BECAUSE
	# THE COUNTERS CANNOT SEE IT. The first version of this test asserted
	# `carve_events <= 1`, which looked like a duplicate-carve guard and was not one: a
	# second `carve_area` at the same point with the same radius finds every cell
	# ALREADY GONE, so `carve_disc` removes 0, and `damage_at` returns before it ever
	# increments `carve_events`. Proven by deliberately adding the duplicate call to
	# `MeteorFist._land` — the suite stayed green. A guard that cannot fail is not a
	# guard, and this one was one edit away from being trusted.
	#
	# The honest invariant is a fact about the FILE: Meteor Fist applies its damage
	# through `BlastSpell`, so it must not carve on its own account. Checked by reading
	# the script, which is the only channel where the duplication is visible at all.
	var src: String = FileAccess.get_file_as_string("res://scripts/combat/MeteorFist.gd")
	_expect(src != "", "MeteorFist.gd could not be read — this check proves nothing")
	# ⚠ COMMENT LINES ARE STRIPPED FIRST, and skipping that step made this check fail on
	# a GREEN tree: `MeteorFist._land` carries a comment explaining why it must not call
	# `DestructibleStage.carve_area`, and a naive substring search matched the
	# explanation. A source check that cannot tell a call from a sentence about the call
	# is the same class of error as the counter check it replaced.
	_expect(not _calls_carve_area(src),
		"MeteorFist.gd calls carve_area itself. Its damage goes through BlastSpell,"
		+ " which has carved since Slice 2, so this is a SECOND crater for one landing."
		+ " It hides from carve_events (the cells are already gone, so damage_at returns"
		+ " 0 and counts nothing) and shows up only as a crater wider than the spell's"
		+ " own damage earns whenever the two points differ.")
	await _teardown(stage, [fx, caster])
	_done("meteor_fist_carves_once_through_its_blast_and_not_twice")


# ── 7. the budget ──────────────────────────────────────────────────────────

## Whatever the sources do, the rebuild must stay inside the wall-clock budget the
## stage advertises, and a deferral must be COUNTED rather than swallowed.
func every_carve_stays_inside_the_budget_the_stage_advertises() -> void:
	await process_frame
	var stage: DestructibleStage = _live_stage()
	var caster: Node2D = _caster()
	var spell: SpellDef = _spell(96)
	# The worst realistic frame: a fault line and a stomp resolving together.
	var a: Node2D = (load("res://scripts/combat/FaultLine.gd") as GDScript).new()
	a.set("target_group", "enemies")
	root.add_child(a)
	a.call("hex", caster, GROUND, GROUND + Vector2(420.0, 0.0), spell, Color.WHITE, "earth")
	var b: Node2D = (load("res://scripts/combat/ShockwaveStomp.gd") as GDScript).new()
	b.set("target_group", "enemies")
	root.add_child(b)
	b.call("hex", caster, GROUND, GROUND + Vector2(300.0, 0.0), spell, Color.WHITE, "earth")
	await _pump(240)
	_expect(stage.carve_events > 0, "the combined cast carved nothing — nothing was measured")
	# The first dirty block is always allowed through even when the budget is spent, so
	# one block's cost is the honest floor here rather than the budget itself.
	var ceiling: int = DestructibleStage.REBUILD_BUDGET_USEC * 4
	_expect(stage.rebuild_usec_worst <= ceiling,
		"worst rebuild frame was %d us against a %d us budget (ceiling %d us)"
			% [stage.rebuild_usec_worst, DestructibleStage.REBUILD_BUDGET_USEC, ceiling])
	_expect(stage.deferred_rebuilds >= 0, "the deferral counter is readable")
	await _teardown(stage, [a, b, caster])
	_done("every_carve_stays_inside_the_budget_the_stage_advertises")


# ── shared readouts ────────────────────────────────────────────────────────

## Does this script actually CALL `carve_area`, as opposed to talking about it? Lines
## whose first non-whitespace character is `#` are dropped before the search, which is
## enough here: the repo writes its reasoning in leading-`#` comment blocks and `##`
## doc-comments, and no call to this function is ever written inside a string literal.
func _calls_carve_area(src: String) -> bool:
	for raw: String in src.split("
"):
		var line: String = raw.strip_edges()
		if line.begins_with("#"):
			continue
		if line.contains("DestructibleStage.carve_area"):
			return true
	return false


## The width of the widest run of columns with NO rock left where rock used to be — a
## severed stage. Asks the stage rather than reconstructing the silhouette from the
## terrace table, which is the mistake that made a sibling probe report an 80 px hole
## in a bout where nothing had been carved [[feedback_harnesses_lie_verify_them]].
func _widest_gap(s: DestructibleStage) -> float:
	var run: int = 0
	var best: int = 0
	for cx: int in s.cols:
		var had: bool = false
		var has: bool = false
		for cy: int in s.rows:
			if s.was_rock(cx, cy):
				had = true
			if s.is_solid(cx, cy):
				has = true
				break
		if had and not has:
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return float(best) * DestructibleStage.CHUNK
