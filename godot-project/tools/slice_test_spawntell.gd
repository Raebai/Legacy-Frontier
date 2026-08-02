# Run: godot --headless --path godot-project --script tools/slice_test_spawntell.gd
# THE SPAWN TELL. Trash bodies used to materialise 190-230px from the hero with no
# mark, no flash and no warning, two at a time on a wave's vanguard. They are now
# ANNOUNCED: a scribble is drawn where the body will stand and the body lands in it
# SPAWN_TELL_LEAD later.
#
# TWO THINGS ARE BEING TESTED HERE AND ONLY ONE OF THEM IS COSMETIC.
#
#   1. THE ACCOUNTING (the half that can break the game). A body waiting on a mark
#      must COUNT AS ALIVE in both population counters. If it did not, the wave's
#      concurrent cap and the 25-entity budget would both gate on a population one
#      lead-time out of date, the wave would keep spawning into the gap, and the
#      feature meant to make the room feel LESS flooded would put more bodies in it
#      at once than before. Every cap assertion below exists for that one sentence.
#
#   2. THE DEGRADATION (the half that can only look wrong). `graphics_quality = LOW`
#      is the phone, and the phone must still be able to READ the mark. The stroke
#      plan is a pure static precisely so this is assertable without a renderer.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──────────
# A dead member read is NOT a failure in GDScript: it logs an error, ABORTS the
# enclosing function and hands back the return type's zero. So failures accumulate
# on the MEMBER `_fails` and every test records a COMPLETION SENTINEL as its last
# line — a test that aborts part-way fails the suite BY ABSENCE.
#
# ── ...and the OTHER vacuity trap ──────────────────────────────────────────────
# "No body ever spawned without a mark" is trivially true of a simulation in which
# nothing spawned. `_test_every_spawn_is_announced` therefore asserts a MINIMUM
# OCCURRENCE RATE first — this many bodies actually landed, across this many
# separate arrivals — and only then that every one of them was announced.
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const SPAWN_TELL_PATH: String = "res://scripts/combat/SpawnTell.gd"
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"

## SpawnTell stroke ids, restated so a renumber over there fails loudly here
## rather than silently comparing against a stale literal.
const S_GROUND: int = 0
const S_SPINE: int = 1
const S_HEAD: int = 2
const S_LEGS: int = 3
const S_ARMS: int = 4
const S_HATCH: int = 5
const S_BLOT: int = 6

## Encounter.Phase ordinals (same restatement rule).
const PHASE_WAVES: int = 1
const PHASE_SURGE: int = 2

## The floor must produce at least this many bodies and this many separate
## arrivals before "every arrival was announced" means anything at all.
const MIN_BODIES: int = 18
const MIN_ARRIVAL_TICKS: int = 6

const TESTS: Array[String] = [
	"plan_is_never_empty",
	"low_keeps_the_read_and_drops_the_garnish",
	"plan_only_grows",
	"heft_reads_by_archetype",
	"lead_cannot_be_misread_as_an_attack",
	"pending_bodies_count_against_both_caps",
	"the_cap_still_holds_under_tells",
	"every_spawn_is_announced",
	"marks_are_cleaned_up",
	"the_mark_actually_draws",
]

var _fails: int = 0
var _completed: Dictionary = {}


## `_initialize` + an awaiting `_run`, the shape slice_test_elites uses: one test
## down there needs real frames (the mark has to actually draw), and a `_process`
## entry point that awaits would hand the SceneTree a coroutine instead of a bool.
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_plan_is_never_empty()
	_test_low_keeps_the_read_and_drops_the_garnish()
	_test_plan_only_grows()
	_test_heft_reads_by_archetype()
	_test_lead_cannot_be_misread_as_an_attack()
	_test_pending_bodies_count_against_both_caps()
	_test_the_cap_still_holds_under_tells()
	_test_every_spawn_is_announced()
	_test_marks_are_cleaned_up()
	await _test_the_mark_actually_draws()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Spawn-tell tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Spawn-tell tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------- fixtures
func _tell_script() -> GDScript:
	return load(SPAWN_TELL_PATH) as GDScript


## A bare arena + a hero stand-in + an encounter whose own `_process` is OFF, so
## every test drives the clock by hand and nothing advances behind an assertion.
func _make_encounter() -> Array:
	var arena := Node2D.new()
	root.add_child(arena)
	var hero := Node2D.new()
	hero.add_to_group("hero")
	arena.add_child(hero)
	var enc: Node = load(ENCOUNTER_PATH).new()
	arena.add_child(enc)
	enc.set_process(false)
	return [arena, enc, hero]


func _floor_with(waves: Array) -> FloorDef:
	var fd := FloorDef.new()
	fd.floor_type = FloorDef.FloorType.COMBAT
	fd.layout = LayoutDef.new()
	fd.wave_break = 0.3
	fd.hp_multiplier = 1.0
	fd.brute_chance = 0.3
	var list: Array[WaveDef] = []
	var total: int = 0
	for row: Array in waves:
		var w := WaveDef.new()
		w.enemy_budget = int(row[0])
		w.concurrent_cap = int(row[1])
		w.spawn_interval = 0.0
		list.append(w)
		total += int(row[0])
	fd.waves = list
	fd.enemy_budget = total
	return fd


## Live (not-yet-freed) mark nodes actually parented into the arena. Counted by
## SCRIPT rather than by group, because the mark is deliberately in NO group — it
## must never be scanned as a body.
func _marks_in(arena: Node) -> int:
	var script: GDScript = _tell_script()
	var n: int = 0
	for c: Node in arena.get_children():
		if c.get_script() == script and not c.is_queued_for_deletion():
			n += 1
	return n


func _wipe(arena: Node) -> void:
	for e: Node in get_nodes_in_group("enemy"):
		e.free()
	arena.free()


# ══════════════════════════════════════════════════════ 1. THE DEGRADATION
## THE READ SURVIVES EVERYTHING. There is no progress at which the mark is
## nothing — the ground scribble is on the page from the first frame, on the cheap
## picture as much as the full one. A tell you cannot see is worse than no tell,
## because the lead time is spent either way.
func _test_plan_is_never_empty() -> void:
	var s: GDScript = _tell_script()
	var samples: int = 0
	var empty_low: int = 0
	var missing_ground: int = 0
	for heft: float in [0.0, 0.3, 0.5, 0.85, 1.0]:
		var p: float = 0.0
		while p <= 1.2001:
			samples += 1
			var low: Array = s.stroke_plan(p, heft, true)
			var high: Array = s.stroke_plan(p, heft, false)
			if low.is_empty():
				empty_low += 1
			if not low.has(S_GROUND) or not high.has(S_GROUND):
				missing_ground += 1
			p += 0.02
	# MINIMUM OCCURRENCE: an "always" claim over zero samples is not a claim.
	_expect(samples >= 250, "the sweep actually sampled the lead (got %d)" % samples)
	_expect(empty_low == 0, "the cheap picture is never blank (%d/%d samples were)"
		% [empty_low, samples])
	_expect(missing_ground == 0,
		"the ground mark is on the page at every progress (%d samples missed it)" % missing_ground)
	# ...and before the mark exists at all there is genuinely nothing.
	_expect((s.stroke_plan(-0.01, 1.0, false) as Array).is_empty(),
		"nothing is drawn before the mark starts")
	_completes("plan_is_never_empty")


## LOW DROPS THE GARNISH, NEVER THE READ. The cheap plan is a strict SUBSET of the
## full one (so LOW can never draw something HIGH does not), it is strictly smaller
## once the garnish strokes are due, and it still carries the four strokes that
## make the mark legible as a body-shaped thing.
func _test_low_keeps_the_read_and_drops_the_garnish() -> void:
	var s: GDScript = _tell_script()
	var not_subset: int = 0
	var bigger: int = 0
	var p: float = 0.0
	while p <= 1.2001:
		for heft: float in [0.3, 1.0]:
			var low: Array = s.stroke_plan(p, heft, true)
			var high: Array = s.stroke_plan(p, heft, false)
			for id in low:
				if not high.has(id):
					not_subset += 1
			if low.size() > high.size():
				bigger += 1
		p += 0.02
	_expect(not_subset == 0, "the cheap plan never draws a stroke the full one does not")
	_expect(bigger == 0, "the cheap plan is never LARGER than the full one")
	# Strictly cheaper once the garnish is due — otherwise "LOW degrades" is a
	# claim about nothing.
	var low_late: Array = s.stroke_plan(0.95, 1.0, true)
	var high_late: Array = s.stroke_plan(0.95, 1.0, false)
	_expect(low_late.size() < high_late.size(),
		"a heavy mark at full progress costs LESS on the cheap picture (%d vs %d)"
			% [low_late.size(), high_late.size()])
	_expect(not low_late.has(S_ARMS) and not low_late.has(S_HATCH),
		"arms and hatching are the garnish, and the cheap picture drops both")
	# The readability floor, stated positively.
	_expect(low_late.has(S_GROUND) and low_late.has(S_SPINE)
			and low_late.has(S_HEAD) and low_late.has(S_LEGS),
		"the cheap mark still reads as a body: ground + spine + head + legs")
	var low_mid: Array = s.stroke_plan(0.5, 0.3, true)
	_expect(low_mid.has(S_SPINE) and low_mid.has(S_HEAD),
		"half-way through the lead the cheap mark already has a spine and a head")
	# The redraw rate is the other half of the cost, and it is also a number.
	_expect(float(s.redraw_hz(true)) < float(s.redraw_hz(false)),
		"the cheap picture redraws less often")
	_expect(float(s.redraw_hz(true)) >= 8.0,
		"...but often enough that the strokes still arrive as a hand working (got %.1f Hz)"
			% float(s.redraw_hz(true)))
	_completes("low_keeps_the_read_and_drops_the_garnish")


## The hand only ever ADDS. A stroke that appeared cannot un-appear part-way
## through the lead, or the mark would flicker instead of resolving.
func _test_plan_only_grows() -> void:
	var s: GDScript = _tell_script()
	var shrank: int = 0
	var steps: int = 0
	for low: bool in [false, true]:
		var prev: Array = []
		var p: float = 0.0
		while p <= 0.9999:
			var plan: Array = s.stroke_plan(p, 1.0, low)
			for id in prev:
				if not plan.has(id):
					shrank += 1
			prev = plan
			steps += 1
			p += 0.01
	_expect(steps >= 180, "the monotonicity sweep actually ran (got %d steps)" % steps)
	_expect(shrank == 0, "no stroke is ever taken back off the page (%d were)" % shrank)
	_completes("plan_only_grows")


## ARCHETYPE HINTING, cheaply. A BRUTE's scrawl is heavier than a CHASER's, and an
## ASSASSIN's is the thinnest scratch in the roster — but every archetype still
## produces the same legible mark, which is the "legibility first" rule.
func _test_heft_reads_by_archetype() -> void:
	var s: GDScript = _tell_script()
	var brute: float = float(s.heft_for_archetype(1))
	var chaser: float = float(s.heft_for_archetype(0))
	var assassin: float = float(s.heft_for_archetype(5))
	_expect(brute > chaser, "a BRUTE's mark is heavier than a CHASER's (%.2f vs %.2f)"
		% [brute, chaser])
	_expect(chaser > assassin, "a CHASER's mark is heavier than an ASSASSIN's (%.2f vs %.2f)"
		% [chaser, assassin])
	var seen: int = 0
	for kind: int in range(0, 8):
		var h: float = float(s.heft_for_archetype(kind))
		_expect(h > 0.0 and h <= 1.0, "archetype %d has a usable heft (got %.2f)" % [kind, h])
		# Legibility first: every archetype, at every weight, still gets the four
		# strokes that make the mark readable.
		var plan: Array = s.stroke_plan(0.95, h, true)
		if plan.has(S_GROUND) and plan.has(S_SPINE) and plan.has(S_HEAD) and plan.has(S_LEGS):
			seen += 1
	_expect(seen == 8, "all eight archetypes still draw a readable mark (got %d)" % seen)
	# ...and the weight actually changes the picture on the full one.
	_expect((s.stroke_plan(0.95, brute, false) as Array).has(S_HATCH),
		"a heavy archetype gets the cross-hatched weight")
	_expect(not (s.stroke_plan(0.95, assassin, false) as Array).has(S_HATCH),
		"a light one does not")
	_completes("heft_reads_by_archetype")


## THE MARK MUST NOT READ AS AN ATTACK. Telegraph is the roster's language for
## "a hit lands HERE"; the spawn mark borrows none of its clock. This locks the
## claim in Encounter's SPAWN_TELL_LEAD comment against the real numbers rather
## than against a remembered one.
func _test_lead_cannot_be_misread_as_an_attack() -> void:
	var enc: GDScript = load(ENCOUNTER_PATH) as GDScript
	var enemy: GDScript = load(ENEMY_PATH) as GDScript
	var lead: float = float(enc.get("SPAWN_TELL_LEAD"))
	_expect(lead > 0.0, "there is a lead at all (got %.2f)" % lead)
	_expect(lead < float(enc.get("SPAWN_TELL_LEAD")) + 0.001, "the lead is a real number")
	# Long enough to read and act on, short enough not to kill the pressure.
	_expect(lead >= 0.25 and lead <= 0.5,
		"the lead stays inside the readable-but-not-slack window (got %.2f)" % lead)
	# Longer than the trickle interval, so marks never stack into a second crowd.
	_expect(lead > float(enc.get("SPAWN_INTERVAL")),
		"the lead outlasts the trickle interval, so marks stay individually legible")
	for windup_name: String in ["ATTACK_WINDUP", "CASTER_WINDUP", "CHARGE_WINDUP",
			"SUMMON_WINDUP", "BOMB_WINDUP", "MAGE_WINDUP"]:
		var w: float = float(enemy.get(windup_name))
		_expect(w > 0.0, "Enemy.%s still exists (it is what the lead is measured against)"
			% windup_name)
		_expect(lead < w, "the spawn mark is shorter than Enemy.%s (%.2f vs %.2f)"
			% [windup_name, lead, w])
	_completes("lead_cannot_be_misread_as_an_attack")


# ══════════════════════════════════════════════════════ 2. THE ACCOUNTING
## THE DANGEROUS HALF. A body waiting on a mark counts as alive in BOTH counters —
## the 25-entity budget (`live_entity_count`, which summoner minions and boss adds
## also ask through Arena.spawn_extra_enemy) and the wave's own concurrent gate.
## And it counts EXACTLY ONCE: the mark node is in no group, so it cannot also be
## picked up by the group scans.
func _test_pending_bodies_count_against_both_caps() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	_expect(int(enc.call("pending_spawn_count")) == 0, "nothing is pending before a floor runs")
	_expect(int(enc.call("live_entity_count")) == 1, "the hero stand-in is the only body")
	var fd: FloorDef = _floor_with([[9, 4]])
	fd.waves[0].spawn_interval = 30.0   # only the vanguard can contribute here
	enc.call("run_floor", fd)
	enc.call("_process", 0.01)
	var pending: int = int(enc.call("pending_spawn_count"))
	_expect(pending > 0, "the wave opened by marking bodies (got %d)" % pending)
	_expect(get_nodes_in_group("enemy").is_empty(), "...and none of them has landed yet")
	_expect(_marks_in(arena) == pending,
		"one mark node per pending body (%d nodes vs %d pending)" % [_marks_in(arena), pending])
	# ONCE, not twice: hero + pending, with the mark nodes NOT also scanned.
	_expect(int(enc.call("live_entity_count")) == 1 + pending,
		"a body being drawn counts against the 25-entity budget exactly once (got %d, want %d)"
			% [int(enc.call("live_entity_count")), 1 + pending])
	_expect(int(enc.call("spawn_headroom")) == 25 - 1 - pending,
		"...so the headroom other spawners read is already reserved")
	# The mark is not a fighter.
	var script: GDScript = _tell_script()
	for c: Node in arena.get_children():
		if c.get_script() != script:
			continue
		_expect(not c.is_in_group("enemy"), "a mark is never in the `enemy` group")
		_expect(not c.is_in_group("mortal"), "a mark is never in the `mortal` group")
		_expect(not c.is_in_group("hero"), "a mark is never in the `hero` group")
	# ...and once it lands, the count transfers rather than doubling.
	enc.call("_process", float(enc.get("SPAWN_TELL_LEAD")))
	_expect(int(enc.call("pending_spawn_count")) == 0, "the marks resolved")
	_expect(get_nodes_in_group("enemy").size() == pending,
		"every marked body landed (%d of %d)" % [get_nodes_in_group("enemy").size(), pending])
	_expect(int(enc.call("live_entity_count")) == 1 + pending,
		"the population is unchanged by the hand-off from mark to body")
	_wipe(arena)
	_completes("pending_bodies_count_against_both_caps")


## THE FAILURE THIS FEATURE COULD HAVE CAUSED, asserted directly: if pending bodies
## did not count, a wave at its cap would keep spawning through the lead and the
## room would hold MORE at once than before tells existed. Two ceilings, both
## driven hard: the wave's own concurrent cap and the hard 25-entity budget.
func _test_the_cap_still_holds_under_tells() -> void:
	# (a) the wave's concurrent cap, nothing ever killed.
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	enc.call("run_floor", _floor_with([[40, 4]]))
	var worst_cap: int = 0
	var samples: int = 0
	for i: int in 400:
		enc.call("_process", 0.05)
		samples += 1
		worst_cap = maxi(worst_cap,
			get_nodes_in_group("enemy").size() + int(enc.call("pending_spawn_count")))
	_expect(samples == 400, "the cap drive actually ran")
	_expect(worst_cap > 0, "...and it actually put bodies in the room (got %d)" % worst_cap)
	_expect(worst_cap <= 4,
		"bodies-plus-marks never exceed the wave's concurrent cap of 4 (peaked at %d)" % worst_cap)
	_wipe(arena)

	# (b) the hard 25-entity budget, with a cap high enough that only it can bite.
	var fx2: Array = _make_encounter()
	var arena2: Node = fx2[0]
	var enc2: Node = fx2[1]
	enc2.call("run_floor", _floor_with([[80, 80]]))
	var worst: int = 0
	var worst_bodies: int = 0
	for i: int in 400:
		enc2.call("_process", 0.05)
		var bodies: int = get_nodes_in_group("enemy").size()
		worst = maxi(worst, int(enc2.call("live_entity_count")))
		worst_bodies = maxi(worst_bodies, bodies)
	_expect(worst <= 25, "the 25-entity budget holds with marks in flight (peaked at %d)" % worst)
	_expect(worst_bodies >= 20,
		"...and the arena still filled rather than stalling behind the lead (got %d)" % worst_bodies)
	_expect(int(enc2.call("phase")) == PHASE_WAVES, "the wave is still running, just capped")
	_wipe(arena2)
	_completes("the_cap_still_holds_under_tells")


## EVERY BODY WAS ANNOUNCED — and the floor produced enough bodies for that to be
## a statement about something. The check is per-tick: whenever the live body count
## grows by k, at least k marks were already on the page at the END of the previous
## tick. A body that appeared out of nothing fails it.
##
## The drive STOPS at the guardian on purpose: the floor boss is deliberately not
## announced this way (it has its own arrival, and `_tick_boss` gates the floor's
## clear on it being present), so counting it here would assert the opposite of the
## design. Trash is what this feature is about.
func _test_every_spawn_is_announced() -> void:
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	var fd: FloorDef = _floor_with([[10, 5], [12, 6]])
	# Pinned to CHASER + BRUTE so no SUMMONER can appear: its minions arrive out of
	# its own telegraphed summon (Arena.spawn_extra_enemy), which is a different
	# path and deliberately not marked. Pinning keeps this measuring one thing.
	var roster: Array[int] = [0, 1]
	for w: WaveDef in fd.waves:
		w.archetypes = roster
	enc.call("run_floor", fd)
	var prev_bodies: int = 0
	var prev_pending: int = 0
	var landed_total: int = 0
	var arrival_ticks: int = 0
	var unannounced: int = 0
	for i: int in 600:
		enc.call("_process", 0.05)
		# The guardian arrives INSIDE the tick that beats the last wave, so the
		# check has to stop after that tick, not before the next one.
		if int(enc.call("phase")) > PHASE_SURGE:
			break
		var bodies: int = get_nodes_in_group("enemy").size()
		var pending: int = int(enc.call("pending_spawn_count"))
		var grew: int = bodies - prev_bodies
		if grew > 0:
			arrival_ticks += 1
			landed_total += grew
			if prev_pending < grew:
				unannounced += grew - prev_pending
		# Thin the room out so the wave keeps spending its budget instead of
		# stalling at its cap (and so wave 2 is reached).
		if bodies > 2:
			get_nodes_in_group("enemy")[0].free()
		prev_bodies = get_nodes_in_group("enemy").size()
		prev_pending = pending
	# MINIMUM OCCURRENCE RATE FIRST. "Nothing spawned unannounced" is trivially
	# true of a floor in which nothing spawned, so the sample size is asserted
	# before the invariant that depends on it.
	_expect(landed_total >= MIN_BODIES,
		"the floor actually produced bodies to check (got %d, want >= %d)"
			% [landed_total, MIN_BODIES])
	_expect(arrival_ticks >= MIN_ARRIVAL_TICKS,
		"...across enough separate arrivals to be a pattern (got %d, want >= %d)"
			% [arrival_ticks, MIN_ARRIVAL_TICKS])
	_expect(unannounced == 0,
		"every body that landed was drawn first (%d of %d appeared out of nothing)"
			% [unannounced, landed_total])
	_wipe(arena)
	_completes("every_spawn_is_announced")


## CLEANUP. A mark must never outlive its floor or spawn a body into a room that no
## longer exists. Three teardown paths, all of which happen in the real game:
## `stop()`, a floor swap straight into `run_floor`, and the encounter leaving the
## tree with the arena.
func _test_marks_are_cleaned_up() -> void:
	# (a) stop()
	var fx: Array = _make_encounter()
	var arena: Node = fx[0]
	var enc: Node = fx[1]
	enc.call("run_floor", _floor_with([[9, 4]]))
	enc.call("_process", 0.01)
	_expect(int(enc.call("pending_spawn_count")) > 0, "there are marks to clean up")
	enc.call("stop")
	_expect(int(enc.call("pending_spawn_count")) == 0, "stop() drops every pending mark")
	_expect(_marks_in(arena) == 0, "...and frees the mark nodes with them")
	# ...and nothing lands afterwards, however long the clock runs.
	for i: int in 40:
		enc.call("_process", 0.1)
	_expect(get_nodes_in_group("enemy").is_empty(),
		"a stopped encounter never spawns the bodies it had already drawn")
	_wipe(arena)

	# (b) the floor swap: Arena._setup_floor calls straight through to run_floor.
	var fx2: Array = _make_encounter()
	var arena2: Node = fx2[0]
	var enc2: Node = fx2[1]
	enc2.call("run_floor", _floor_with([[9, 4]]))
	enc2.call("_process", 0.01)
	var before: int = int(enc2.call("pending_spawn_count"))
	_expect(before > 0, "floor one had marks in flight")
	enc2.call("run_floor", _floor_with([[9, 4]]))
	_expect(int(enc2.call("pending_spawn_count")) == 0,
		"the previous floor's marks do not land on the new one")
	_expect(_marks_in(arena2) == 0, "...and their nodes went with them")
	_wipe(arena2)

	# (c) leaving the tree (arena teardown / scene change).
	var fx3: Array = _make_encounter()
	var arena3: Node = fx3[0]
	var enc3: Node = fx3[1]
	enc3.call("run_floor", _floor_with([[9, 4]]))
	enc3.call("_process", 0.01)
	_expect(int(enc3.call("pending_spawn_count")) > 0, "there are marks in flight")
	arena3.remove_child(enc3)
	_expect(int(enc3.call("pending_spawn_count")) == 0,
		"an encounter that left the tree drops its marks rather than spawning into a dead scene")
	enc3.free()
	_wipe(arena3)
	_completes("marks_are_cleaned_up")


## THE PICTURE IS ACTUALLY DRAWN, AND NEVER ABORTS.
##
## `_draw` DOES run under `--headless` (measured: the dummy renderer still issues
## NOTIFICATION_DRAW), but a runtime error inside it is invisible — GDScript aborts
## the function and the engine emits the `draw` signal regardless, so "it drew" is
## not evidence. SpawnTell therefore counts `_draw` calls ENTERED and COMPLETED,
## and an abort anywhere in the stroke code shows up here as entered > completed.
##
## Driven at both weights and BOTH quality settings, across the whole ramp
## including the blot tail, because the cheap branch is a different code path and
## nobody has ever seen it run on a phone.
func _test_the_mark_actually_draws() -> void:
	var s: GDScript = _tell_script()
	var marks: Array[Node2D] = []
	for cheap: bool in [false, true]:
		for heft: float in [0.3, 1.0]:
			var t: Node2D = s.new()
			# A long lead so the whole ramp (and then the blot) is covered by the
			# frames below rather than raced past.
			t.call("configure", 3.0, Color(0.9, 0.5, 0.2, 1), heft)
			root.add_child(t)
			t.set("_low", cheap)   # a DECLARED property, so this is not a silent no-op
			marks.append(t)
	for i: int in 90:
		await process_frame
	var total_drawn: int = 0
	var aborted: int = 0
	for t: Node2D in marks:
		if not is_instance_valid(t):
			continue
		var c: Vector2i = t.call("draw_counts")
		total_drawn += c.y
		if c.x != c.y:
			aborted += 1
		_expect(int(t.call("redraws")) > 0, "the mark asked to be redrawn")
	_expect(total_drawn >= 8,
		"the mark actually drew across the ramp (%d completed draws over 4 variants)"
			% total_drawn)
	_expect(aborted == 0,
		"no _draw ever aborted part-way (%d of %d variants did)" % [aborted, marks.size()])
	for t: Node2D in marks:
		if is_instance_valid(t):
			t.free()
	_completes("the_mark_actually_draws")
