# Run: godot --headless --path godot-project --script tools/slice_test_destructible_hitpoint.gd
#
# THE MAKER'S CORRECTION TO DESTRUCTION, ASSERTED AS FOUR PROPERTIES.
#
#   *"when I say destructable I mean for all things where it was hit much like stick
#   fight — if I shoot a beam for example, one of arcanist's abilities, it creates a
#   hole where I struck but nothing more or less than that, just that definitive hole.
#   A meteor would do more destruction. But ensure that the damage done is kept
#   accurate to where it hit and not the entire thing breaks, but dependent on where you
#   hit, much like the ice in Stick Fight."*
#
#   1. HIT-POINT ACCURATE — the hole is centred where the strike met the rock. Proved
#      against the beam, which is the maker's own example and whose tip is ~700 px from
#      its terrain contact on the test geometry, so a regression cannot hide in rounding.
#   2. PROPORTIONATE — beam / dagger / nova / meteor produce VISIBLY different holes,
#      asserted as a minimum separation in px rather than eyeballed off a table.
#   3. EVERYTHING THAT HITS CARVES — no damage shelf turns a real strike away.
#   4. NOTHING CASCADES — carved area tracks the union of the craters asked for. A local
#      hit may not take out a region.
#
# ⚠ THE HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the
# enclosing function and hands back the type's zero, which that idiom reads as "no
# failures". Failures accumulate on the MEMBER `_fails`; every test records a COMPLETION
# SENTINEL as its last line, so an aborted test fails BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"the_size_table_separates_beam_dagger_nova_and_meteor",
	"a_beam_carves_where_it_met_the_rock_and_not_at_its_tip",
	"every_strike_in_the_roster_carves_something",
	"one_source_cannot_re_dig_the_hole_it_already_opened",
	"a_marching_source_still_carves_along_its_line",
	"nothing_cascades_the_carved_area_tracks_the_craters_asked_for",
	"many_small_holes_stay_inside_the_frame_budget",
	"a_boulder_and_a_pillar_take_a_bite_out_of_the_deck",
]

## The shipped stage, variant 0, from `VersusArena.STAGE_TERRACES[0]` + TERRACE_DEPTH.
const TERRACE_DEPTH: float = 320.0
const TERRACES: Array[Dictionary] = [
	{"surface_y": 780.0, "x0": 40.0,   "x1": 1400.0},
	{"surface_y": 700.0, "x0": 40.0,   "x1": 250.0},
	{"surface_y": 696.0, "x0": 1330.0, "x1": 1580.0},
	{"surface_y": 612.0, "x0": 1540.0, "x1": 1760.0},
	{"surface_y": 528.0, "x0": 1700.0, "x1": 1965.0},
]

## Two craters this far apart in RADIUS are ones a player can tell apart on sight. 2.5 px
## of radius is 5 px of hole and the grid is 4 px, so anything smaller than this could not
## survive cell quantisation anyway — it is the floor of "visibly different", not a
## comfortable margin.
const SIZE_DISTINCT_PX: float = 2.5

var _fails: int = 0
var _completed: Dictionary = {}


func _initialize() -> void:
	_go()


func _go() -> void:
	await process_frame
	for t: String in TESTS:
		await call(t)
	for t: String in TESTS:
		_expect(_completed.has(t), "%s ran to completion" % t)
	print("slice_test_destructible_hitpoint: %s (%d failure(s))"
		% ["all PASS" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: %s" % what)


func _done(t: String) -> void:
	_completed[t] = true


# ── 1. the size rule ───────────────────────────────────────────────────────

## THE TABLE, PRINTED AND THEN ASSERTED. Printing it is how the numbers get reported;
## asserting the separation is what stops a later tuning pass from quietly collapsing two
## rows onto the same radius while the table still looks informative.
##
## Every row carries the SHIPPED numbers out of `SpellLibrary` and the spell files rather
## than invented ones, so the table is a readout of the game and not of this test.
func the_size_table_separates_beam_dagger_nova_and_meteor() -> void:
	await process_frame
	var rows: Array[Dictionary] = [
		{"n": "bolt (Spell, r6)",          "d": 45,  "f": 6.0},
		{"n": "dagger (blade hw4.2)",      "d": 34,  "f": 8.4},
		{"n": "beam Frostpiercer (w22)",   "d": 58,  "f": 11.0},
		{"n": "beam First Lance (w30)",    "d": 88,  "f": 15.0},
		{"n": "beam Infernal Lance (w42)", "d": 74,  "f": 21.0},
		{"n": "ice spike (hw16)",          "d": 38,  "f": 16.0},
		{"n": "fault bite (r20)",          "d": 105, "f": 20.0},
		{"n": "stomp (r30)",               "d": 54,  "f": 30.0},
		{"n": "divine ray (r70)",          "d": 95,  "f": 70.0},
		{"n": "boulder (rock r26)",        "d": 96,  "f": 26.0},
		{"n": "blast Q (r90)",             "d": 96,  "f": 90.0},
		{"n": "nova (r135)",               "d": 30,  "f": 135.0},
		{"n": "meteor sigil (r140)",       "d": 36,  "f": 140.0},
		{"n": "meteor storm (r210)",       "d": 30,  "f": 210.0},
	]
	print("  crater radius by strike (px):")
	for r: Dictionary in rows:
		var rad: float = DestructibleStage.carve_radius_for_strike(
			int(r["d"]), float(r["f"]))
		r["r"] = rad
		print("    %-28s dmg %3d  footprint %6.1f  ->  radius %5.1f  (hole %5.1f px)"
			% [r["n"], int(r["d"]), float(r["f"]), rad, rad * 2.0])

	var dagger: float = float(rows[1]["r"])
	var beam: float = float(rows[3]["r"])
	var boulder: float = float(rows[9]["r"])
	var nova: float = float(rows[11]["r"])
	var meteor: float = float(rows[13]["r"])
	# The maker named these shapes. Each neighbouring pair must be apart by more than the
	# grid can blur, and the ORDER must be the one the sentence describes: a beam is a
	# definitive little hole, a boulder takes a bite, a meteor "would do more destruction".
	_expect(beam - dagger >= SIZE_DISTINCT_PX,
		"beam %.1f and dagger %.1f are not visibly different radii" % [beam, dagger])
	_expect(boulder - beam >= SIZE_DISTINCT_PX,
		"boulder %.1f and beam %.1f are not visibly different radii" % [boulder, beam])
	_expect(meteor - boulder >= SIZE_DISTINCT_PX,
		"meteor %.1f and boulder %.1f are not visibly different radii" % [meteor, boulder])
	# ⚠ NOVA-vs-BOULDER IS DELIBERATELY NOT ORDERED HERE. The nova out-carves the
	# boulder (a 135 px scouring ring against 26 px of falling stone) and that is the
	# rule working, not failing — see the table in `DestructibleStage`. Asserting an
	# order between them would be asserting a tuning preference, so what is asserted is
	# only that they are both inside the band the roster is meant to occupy.
	_expect(nova > beam and nova < meteor,
		"the nova (%.1f) has left the band between a beam (%.1f) and a meteor (%.1f)"
			% [nova, beam, meteor])
	# ⚠ AND THE PROPERTY THE OLD DAMAGE-ONLY CURVE FAILED. The beam carries nearly THREE
	# TIMES the nova's damage and must still open the smaller hole, because the size is a
	# property of the STRIKE and not of the damage number attached to it. This one
	# assertion would have caught the shipped behaviour.
	_expect(int(rows[3]["d"]) > int(rows[11]["d"]) * 2,
		"the test's own premise is wrong: the beam no longer out-damages the nova 2:1")
	_expect(beam < nova,
		"an 88-damage beam still digs a wider hole (%.1f) than a 30-damage nova (%.1f)"
			% [beam, nova] + " — the size rule is back on damage")
	# Bounded at both ends, so no strike can produce a pinprick or eat the stage.
	_expect(DestructibleStage.carve_radius_for_strike(1, 0.5)
		>= DestructibleStage.CARVE_RADIUS_MIN - 0.001, "the floor holds")
	_expect(DestructibleStage.carve_radius_for_strike(99999, 99999.0)
		<= DestructibleStage.CARVE_RADIUS_MAX + 0.001, "the ceiling holds")
	_done("the_size_table_separates_beam_dagger_nova_and_meteor")


# ── 2. hit-point accuracy, against the maker's own example ─────────────────

## THE BEAM, WHICH CARVED NOTHING AT ALL BEFORE THIS WORK.
##
## The geometry is chosen so a lazy implementation cannot pass. The beam is fired from
## above the deck at 45 degrees down-right with the SHIPPED First Lance reach (1,150 px):
## it meets the 780 px deck about 80 px along, and its tip lands ~730 px further on and
## ~730 px BELOW the floor. So "carve at the tip", "carve at the origin" and "carve at
## the contact" are hundreds of px apart, and only one of them is inside the deck at all.
func a_beam_carves_where_it_met_the_rock_and_not_at_its_tip() -> void:
	await process_frame
	var stage: DestructibleStage = _live_stage()
	var origin := Vector2(400.0, 700.0)
	var dir: Vector2 = Vector2(1.0, 1.0).normalized()
	var beam: Node2D = (load("res://scripts/combat/BeamSpell.gd") as GDScript).new()
	beam.set("target_group", "enemies")
	root.add_child(beam)
	beam.call("fire", origin, dir, Color.WHITE, 1150.0, 30.0, 88, "arcane")
	await _pump(90)

	_expect(stage.carve_events == 1,
		"the beam carved %d time(s) — it fires once, so it opens ONE hole"
			% stage.carve_events)
	var hole: Rect2 = _carved_bounds(stage)
	_expect(hole.size.x > 0.0, "nothing was carved at all — the beam is not wired")
	var centre: Vector2 = hole.get_center()
	# Where the beam ACTUALLY meets the deck: 45 degrees down from y=700 to y=780.
	var expected := Vector2(origin.x + 80.0, 780.0)
	var tip: Vector2 = origin + dir * 1150.0
	print("    beam: carved centre %s, contact %s, tip %s" % [centre, expected, tip])
	# 14 px covers the half-disc's centroid sitting slightly below the surface line plus
	# cell quantisation; the wrong answers are 700+ px away.
	_expect(centre.distance_to(expected) <= 14.0,
		"the beam's hole is %.1f px from where it met the rock (centre %s vs %s)"
			% [centre.distance_to(expected), centre, expected])
	_expect(centre.distance_to(tip) > 400.0,
		"the beam carved at its TIP, not at its contact point")
	# ...and the hole is BEAM-SIZED. A 30 px beam that opens a 40 px-wide hole is the
	# spell arguing with its own picture.
	_expect(hole.size.x <= 34.0,
		"the beam opened a %.0f px-wide hole with a 30 px beam" % hole.size.x)
	await _teardown(stage, [beam])
	_done("a_beam_carves_where_it_met_the_rock_and_not_at_its_tip")


# ── 3. everything that hits carves ─────────────────────────────────────────

## REQUIREMENT 3, ASSERTED AS THE ABSENCE OF A SHELF. The old `CARVE_MIN_DAMAGE` of 40
## refused a zone tick (8), RadiantVolley (15), a Blade Flurry cut (24), an Iai cut (38),
## a nova (30) and a meteor (36). Every one of those is a thing that hit the ground.
func every_strike_in_the_roster_carves_something() -> void:
	await process_frame
	var stage: DestructibleStage = _stage()
	var x: float = 300.0
	for dmg: int in [8, 15, 24, 30, 36, 38, 45, 105, 260]:
		# A fresh point per hit, and `source = null` so the ledger cannot be the thing
		# that refuses — this test is about the DAMAGE shelf and nothing else.
		var removed: int = stage.damage_at(dmg, Vector2(x, 782.0), Vector2.UP, 15.0)
		_expect(removed > 0, "a %d-damage strike on solid rock removed nothing" % dmg)
		x += 140.0
	_expect(stage.refused_hits == 0,
		"%d strike(s) were refused by the damage shelf" % stage.refused_hits)
	stage.queue_free()
	_done("every_strike_in_the_roster_carves_something")


# ── 4. the anti-cascade ledger ─────────────────────────────────────────────

## THE THING THAT REPLACED THE DAMAGE SHELF. The shelf's stated purpose was never the
## jab, it was the REPEAT — "a `ZoneSpell` field ticking its scenery pass every `TICK` for
## eight seconds is the case that would genuinely dissolve the floor". A damage floor
## refuses the first tick as well as the hundredth; this refuses only the re-digging.
func one_source_cannot_re_dig_the_hole_it_already_opened() -> void:
	await process_frame
	var stage: DestructibleStage = _stage()
	var zone := Node2D.new()
	root.add_child(zone)
	var at := Vector2(700.0, 782.0)
	var first: int = stage.damage_at(8, at, Vector2.UP, 40.0, zone)
	_expect(first > 0, "the zone's FIRST tick must carve — it is a real hit")
	var after_first: int = stage.solid_count()
	# Eight seconds of a 0.25 s tick on the same square metre.
	#
	# ⚠ THE TICKS DRIFT, AND THEY HAVE TO. The first version fired all 32 at the exact
	# same point and it could not tell the ledger from nothing: 32 identical discs remove
	# the identical cells, so `solid_count` is unchanged whether the ledger holds or is
	# stubbed to admit everything. It passed with the mechanism DELETED — a vacuous test.
	# A real field is attached to a caster who is walking, so its ticks wander by a few
	# px, and a wandering disc absolutely does erode outward. The drift is kept well
	# inside `CARVE_REPEAT_BITE * radius` so the ledger is what refuses it, not distance.
	var drift: float = DestructibleStage.carve_radius_for_strike(8, 40.0) * 0.3
	for i: int in 32:
		var wobble := Vector2(cos(float(i) * 1.7), sin(float(i) * 2.3)) * drift
		stage.damage_at(8, at + wobble, Vector2.UP, 40.0, zone)
	_expect(stage.solid_count() == after_first,
		"32 further ticks on the same spot removed %d more cell(s) — the ledger is not"
			% (after_first - stage.solid_count())
		+ " holding and a zone can dissolve the floor")
	_expect(stage.repeat_refused_hits == 32,
		"the ledger counted %d refusals, expected 32" % stage.repeat_refused_hits)
	# ⚠ AND IT IS PER-SOURCE, NOT GLOBAL. A DIFFERENT spell hitting the same spot is a
	# different strike, and the maker's model is per-strike, so it must still carve.
	var other := Node2D.new()
	root.add_child(other)
	_expect(stage.damage_at(96, at, Vector2.UP, 90.0, other) > 0,
		"a second, different spell was refused at a spot the first had taken")
	zone.queue_free()
	other.queue_free()
	stage.queue_free()
	_done("one_source_cannot_re_dig_the_hole_it_already_opened")


## ...AND THE LEDGER MUST NOT BREAK THE WALKERS. A Fault Line marching along the deck at
## `CRATER_STRIDE` and a Grave Tide at `CARVE_STRIDE` are single sources carving many
## points, and if the spacing rule caught them each spell would open one hole instead of a
## line. Their shipped strides are read out of their own files rather than restated here.
func a_marching_source_still_carves_along_its_line() -> void:
	await process_frame
	var fault: GDScript = load("res://scripts/combat/FaultLine.gd") as GDScript
	var tide: GDScript = load("res://scripts/combat/GraveTide.gd") as GDScript
	var cases: Array[Dictionary] = [
		{"n": "FaultLine", "stride": float(fault.get("CRATER_STRIDE")),
			"d": 105, "f": 20.0},
		{"n": "GraveTide", "stride": float(tide.get("CARVE_STRIDE")),
			"d": 40, "f": 18.0},
	]
	for c: Dictionary in cases:
		var stage: DestructibleStage = _stage()
		var walker := Node2D.new()
		root.add_child(walker)
		var stride: float = float(c["stride"])
		var carved: int = 0
		for i: int in 8:
			var at := Vector2(300.0 + stride * float(i), 782.0)
			if stage.damage_at(int(c["d"]), at, Vector2.UP, float(c["f"]), walker) > 0:
				carved += 1
		var r: float = DestructibleStage.carve_radius_for_strike(
			int(c["d"]), float(c["f"]))
		print("    %s: stride %.0f px vs crater radius %.1f px -> %d of 8 bites landed"
			% [c["n"], stride, r, carved])
		_expect(carved == 8,
			"%s only landed %d of 8 bites — the anti-cascade spacing (%.1f px) is"
				% [c["n"], carved, r * DestructibleStage.CARVE_REPEAT_BITE]
			+ " catching its own stride (%.0f px)" % stride)
		walker.queue_free()
		stage.queue_free()
	_done("a_marching_source_still_carves_along_its_line")


# ── 5. nothing cascades ────────────────────────────────────────────────────

## *"not the entire thing breaks, but dependent on where you hit"*.
##
## The failure the maker warns about is a local hit taking out a region. There is no
## support or gravity simulation here that COULD propagate one, and the way to prove that
## is not to read the code but to weigh the result: the cells that came out must be
## exactly the cells inside the discs that were asked for, and no others.
##
## Reported as a RATIO, carved area over the sum of intended crater areas, in the two
## cases that answer different questions:
##
##   SAME source, same point — the ledger refuses the repeats, so the ratio must collapse
##   toward one crater's worth. A cascade would show as a ratio above 1.
##   DIFFERENT sources, same point — every strike is admitted, but overlapping craters
##   share cells, so the answer must be the UNION and never the sum.
func nothing_cascades_the_carved_area_tracks_the_craters_asked_for() -> void:
	await process_frame
	var cell: float = DestructibleStage.CHUNK * DestructibleStage.CHUNK
	var at := Vector2(700.0, 790.0)
	var one_crater: float = PI * pow(
		DestructibleStage.carve_radius_for_strike(96, 90.0), 2.0)

	# ── same source, 12 hits on one spot ──
	var s1: DestructibleStage = _stage()
	var one := Node2D.new()
	root.add_child(one)
	var asked1: float = 0.0
	for _i: int in 12:
		asked1 += one_crater
		s1.damage_at(96, at, Vector2.UP, 90.0, one)
	var got1: float = float(s1.carved_cells) * cell
	print("    same source x12 at one point: carved %.0f px2 of %.0f px2 asked -> %.3f"
		% [got1, asked1, got1 / asked1])
	_expect(got1 / asked1 <= 1.0,
		"12 hits at one point removed MORE than 12 craters' worth of rock (ratio %.3f)"
			% (got1 / asked1) + " — something is cascading")
	_expect(got1 <= one_crater * 1.15,
		"12 hits at one point took %.0f px2, more than the one crater (%.0f px2) the"
			% [got1, one_crater] + " ledger should have allowed")

	# ── twelve DIFFERENT sources, same spot: the union, never the sum ──
	var s2: DestructibleStage = _stage()
	var movers: Array = []
	var asked2: float = 0.0
	for _i: int in 12:
		var m := Node2D.new()
		root.add_child(m)
		movers.append(m)
		asked2 += one_crater
		s2.damage_at(96, at, Vector2.UP, 90.0, m)
	var got2: float = float(s2.carved_cells) * cell
	print("    12 different sources at one point: carved %.0f px2 of %.0f px2 -> %.3f"
		% [got2, asked2, got2 / asked2])
	_expect(got2 / asked2 <= 1.0,
		"12 separate strikes at one point removed MORE than their combined crater area"
			+ " (ratio %.3f) — the discs are cascading" % (got2 / asked2))
	_expect(got2 <= one_crater * 1.15,
		"12 overlapping craters removed %.0f px2 where their union is one crater (%.0f)"
			% [got2, one_crater])

	# ── and the union itself is exact: cells out == cells inside the disc ──
	var s3: DestructibleStage = _stage()
	var probe := Vector2(500.0, 790.0)
	var expect_cells: int = _cells_in_disc(s3, probe, 30.0)
	var removed3: int = s3.carve_disc(probe, 30.0)
	_expect(removed3 == expect_cells,
		"a 30 px disc removed %d cells where %d lie inside it — the carve is not"
			% [removed3, expect_cells] + " confined to its own footprint")

	for i: int in movers.size():
		if is_instance_valid(movers[i]):
			(movers[i] as Node).queue_free()
	one.queue_free()
	s1.queue_free()
	s2.queue_free()
	s3.queue_free()
	_done("nothing_cascades_the_carved_area_tracks_the_craters_asked_for")


# ── 6. the budget, re-measured against MANY SMALL holes ────────────────────

## THE COST THAT CHANGED SHAPE. The rebuild's price is not a hole's AREA, it is how many
## RECTANGLES the greedy merge must emit for the block afterwards — and letting everything
## carve trades a few big holes for many small ones, which is the direction that costs
## more per px removed.
##
## So the worst case is measured directly rather than inferred: a couple of blocks' worth
## of scattered small craters, rebuilt over a handful of frames, timed on the wall clock.
## The number is PRINTED whether it passes or not, because the budget is a number the next
## person has to be able to watch move.
func many_small_holes_stay_inside_the_frame_budget() -> void:
	await process_frame
	var stage: DestructibleStage = _live_stage()
	# 24 beam-sized holes strewn across ~2 blocks of deck. A whole bout does not do this
	# — the real pipeline measures 3-11 carve events per bout — so this is deliberately
	# the pathological frame and not the typical one.
	for i: int in 24:
		var src := Node2D.new()
		root.add_child(src)
		stage.damage_at(88, Vector2(420.0 + float(i) * 15.0, 786.0),
			Vector2.UP, 15.0, src)
		src.queue_free()
	await _pump(30)
	var frame_budget: int = 16667
	print("    24 beam holes: worst rebuild frame %d us of a %d us frame; %d shapes;"
		% [stage.rebuild_usec_worst, frame_budget, stage.shape_count()]
		+ " %.2f%% carved; %d deferral(s)"
			% [stage.carved_fraction() * 100.0, stage.deferred_rebuilds])
	_expect(stage.carve_events == 24,
		"only %d of 24 holes were opened — the measurement is not measuring what it says"
			% stage.carve_events)
	_expect(stage.rebuild_usec_worst < frame_budget,
		"worst rebuild frame %d us is over the %d us frame budget"
			% [stage.rebuild_usec_worst, frame_budget])
	await _teardown(stage, [])
	_done("many_small_holes_stay_inside_the_frame_budget")


# ── 7. the maker's worked example, live ────────────────────────────────────

## *"boulder of course for example should take a piece out of the floor."*
##
## The two heaviest GROUND-AIMED sources, driven end to end rather than through
## `damage_at` directly, because the interesting failure in both is UPSTREAM of the
## crater rule: the boulder used to throw away the raycast contact it already held and
## re-derive a point straight down from it, and the divine ray never asked the world
## anything at all. A unit test on the size curve cannot see either bug.
##
## Both are asserted on the SAME property as the beam — the hole is where the strike met
## the rock — because that is the requirement, and on the boulder's SIZE, because that is
## the maker's sentence.
func a_boulder_and_a_pillar_take_a_bite_out_of_the_deck() -> void:
	await process_frame

	# ── the boulder: thrown flat along the deck, so it plants in the terrace face ──
	var s1: DestructibleStage = _live_stage()
	var rock: Node2D = (load("res://scripts/combat/BoulderHurl.gd") as GDScript).new()
	rock.set("target_group", "enemies")
	root.add_child(rock)
	rock.call("hurl", Vector2(700.0, 760.0), Vector2(0.6, 1.0), Color.WHITE, 90.0, 96)
	await _pump(150)
	_expect(s1.carve_events >= 1, "the boulder carved nothing")
	var hole1: Rect2 = _carved_bounds(s1)
	print("    boulder: %d event(s), hole %.0f x %.0f px at %s; contact-vs-floor-snap"
		% [s1.carve_events, hole1.size.x, hole1.size.y, hole1.get_center()]
		+ " %.1f px" % float(rock.get("contact_vs_floor_px")))
	# A ~26 px rock. The hole must be rock-sized, not blast-sized: `_radius` was 90 above,
	# and sizing off that would give a 65 px-wide bite instead of a 35 px one.
	_expect(hole1.size.x > 0.0 and hole1.size.x <= 46.0,
		"the boulder opened a %.0f px-wide hole — a 26 px rock should leave ~35 px, and"
			% hole1.size.x + " anything near 65 px means it is sized off its BLAST")
	await _teardown(s1, [rock])

	# ── the same rock into a VERTICAL FACE, which is where the old snap was wrong ──
	# Terrace 2 stands at y=696 from x=1330, so its left face is a wall spanning
	# y 696..780 at x=1330, with the main deck (780) at its foot. A boulder thrown
	# horizontally into that face contacts the WALL; the floor snap the shipped code used
	# drops from there to the deck below. `contact_vs_floor_px` reports the gap in px, so
	# "the snap point and the contact point differ" stops being an argument from geometry.
	var s1b: DestructibleStage = _live_stage()
	var rock2: Node2D = (load("res://scripts/combat/BoulderHurl.gd") as GDScript).new()
	rock2.set("target_group", "enemies")
	root.add_child(rock2)
	rock2.call("hurl", Vector2(1150.0, 745.0), Vector2(1.0, 0.0), Color.WHITE, 90.0, 96)
	await _pump(150)
	var drift: float = float(rock2.get("contact_vs_floor_px"))
	var hole1b: Rect2 = _carved_bounds(s1b)
	print("    boulder into a wall: hole at %s; the old floor-snap point was %.1f px away"
		% [hole1b.get_center(), drift])
	_expect(s1b.carve_events >= 1, "the boulder carved nothing against the terrace face")
	_expect(drift > 8.0,
		"the wall shot measured only %.1f px between the contact and the floor snap —"
			% drift + " the geometry did not set up, so this measurement is vacuous")
	# THE HOLE IS IN THE WALL, NOT ON THE DECK AT ITS FOOT.
	_expect(hole1b.get_center().y < 780.0,
		"the hole landed at y=%.0f, on the deck below the face the rock actually hit"
			% hole1b.get_center().y)
	await _teardown(s1b, [rock2])

	# ── the divine ray: a vertical pillar onto an aim point 30 px ABOVE the deck ──
	# ⚠ THAT OFFSET IS THE TEST. `SpellCaster` hands `strike()` a raw aim point, which is
	# normally a body's chest and never snapped to a surface. A carve at the aim point
	# would open a bubble 30 px up in the air; the hole has to land on the deck at 780.
	var s2: DestructibleStage = _live_stage()
	var ray: Node2D = (load("res://scripts/combat/DivineRay.gd") as GDScript).new()
	ray.set("target_group", "enemies")
	root.add_child(ray)
	ray.call("strike", Vector2(900.0, 750.0), Color.WHITE, 70.0, 95, "holy")
	await _pump(180)
	_expect(s2.carve_events >= 1, "the divine ray carved nothing")
	var hole2: Rect2 = _carved_bounds(s2)
	print("    divine ray: %d event(s), hole %.0f x %.0f px at %s"
		% [s2.carve_events, hole2.size.x, hole2.size.y, hole2.get_center()])
	_expect(hole2.size.x > 0.0, "the divine ray opened no hole at all")
	_expect(absf(hole2.get_center().x - 900.0) <= 14.0,
		"the pillar's hole is at x=%.0f, not under the column at x=900"
			% hole2.get_center().x)
	# The top of the hole is the deck, not the aim point 30 px above it.
	_expect(hole2.position.y >= 776.0,
		"the pillar carved from y=%.0f — above the 780 px deck, i.e. in mid-air at the"
			% hole2.position.y + " raw aim point rather than at the contact")
	await _teardown(s2, [ray])
	_done("a_boulder_and_a_pillar_take_a_bite_out_of_the_deck")


# ── shared ─────────────────────────────────────────────────────────────────

func _terrace_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t: Dictionary in TERRACES:
		out.append(Rect2(Vector2(float(t["x0"]), float(t["surface_y"])),
			Vector2(float(t["x1"]) - float(t["x0"]), TERRACE_DEPTH)))
	return out


func _stage() -> DestructibleStage:
	var s := DestructibleStage.new()
	s.build_from_rects(_terrace_rects())
	return s


## ⚠ THE STALE-STAGE GUARD, INHERITED FROM `slice_test_destructible_sources`. A stage
## queued for deletion still answers group lookups and still answers rays, so a leaked one
## from an earlier test silently becomes the stage the next test measures. The instrument
## proves its own precondition or its zeroes mean nothing.
## [[feedback_harnesses_lie_verify_them]].
func _live_stage() -> DestructibleStage:
	var stale: int = root.get_tree().get_nodes_in_group(
		DestructibleStage.GROUP_NAME).size()
	_expect(stale == 0,
		"%d stage(s) were still in the group when this test began" % stale)
	var s: DestructibleStage = _stage()
	root.add_child(s)
	s.rebuild_collision(s)
	return s


func _teardown(stage: DestructibleStage, nodes: Array) -> void:
	if stage != null and is_instance_valid(stage):
		stage.remove_from_group(DestructibleStage.GROUP_NAME)
		if stage.get_parent() != null:
			stage.get_parent().remove_child(stage)
		stage.queue_free()
	# ⚠ VALIDITY ON THE ARRAY ELEMENT, BEFORE ANY TYPED ASSIGNMENT. A typed loop variable
	# assigned an already-freed instance raises and ABORTS this function, which would
	# leave the stage in the group for every later test. Same trap, same fix, as
	# `slice_test_destructible_sources._teardown`.
	for i: int in nodes.size():
		if not is_instance_valid(nodes[i]):
			continue
		var n: Node = nodes[i]
		if not n.is_queued_for_deletion():
			n.queue_free()
	await process_frame
	await process_frame


func _pump(n: int) -> void:
	for _i: int in n:
		await process_frame


## The world-space bounding box of every cell that WAS rock and is now air. Read off the
## stage's own `was_rock` / `is_solid` rather than reconstructed from the terrace table: a
## probe that rebuilt the silhouette outside that file once reported an 80 px hole on a
## stage where nothing had been carved. [[feedback_harnesses_lie_verify_them]].
func _carved_bounds(s: DestructibleStage) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var found: bool = false
	for cy: int in s.rows:
		for cx: int in s.cols:
			if not s.was_rock(cx, cy) or s.is_solid(cx, cy):
				continue
			found = true
			var p: Vector2 = s.origin + Vector2(
				float(cx), float(cy)) * DestructibleStage.CHUNK
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x + DestructibleStage.CHUNK),
				maxf(hi.y, p.y + DestructibleStage.CHUNK))
	if not found:
		return Rect2()
	return Rect2(lo, hi - lo)


## How many SOLID cells lie inside this disc right now. The independent count the carve is
## checked against — the same centre-sampling rule the carve uses, written out separately
## so a bug in one cannot cancel in the other.
func _cells_in_disc(s: DestructibleStage, at: Vector2, radius: float) -> int:
	var n: int = 0
	var r2: float = radius * radius
	for cy: int in s.rows:
		for cx: int in s.cols:
			if not s.is_solid(cx, cy):
				continue
			var c: Vector2 = s.origin + Vector2(
				(float(cx) + 0.5) * DestructibleStage.CHUNK,
				(float(cy) + 0.5) * DestructibleStage.CHUNK)
			if c.distance_squared_to(at) <= r2:
				n += 1
	return n
