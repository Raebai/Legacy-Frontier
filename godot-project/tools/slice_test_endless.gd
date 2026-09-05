# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_endless.gd
#
# THE ENDLESS TOWER AND THE SCORE — the seam, the escalation, and the board.
#
# Design note: docs/superpowers/specs/2026-09-04-infinite-tower-and-score.md
#
# WHAT IS PINNED HERE, and why each one is a thing that silently breaks:
#
#   1. THE AUTHORED TEN ARE UNTOUCHED. The whole premise of the change is that the
#      hand-tuned spine is the opening act; a generator that quietly redefines floor
#      3 has replaced the good part of the game with the new part.
#   2. ENDLESSNESS IS ON IN THE GAME AND OFF IN THE BUILDER. Eight tools assert the
#      authored numbers against `build_default_tower()`; if that ever came back
#      endless, `slice_test_climb`'s conquer test would be describing a tower that
#      no longer exists.
#   3. TRASH HP IS 1.0 AT EVERY DEPTH, FOREVER. The maker's standing rule, and the
#      single easiest thing to break when asked to make a curve go up forever.
#   4. THE PRESSURE CAP CEILING IS DEPTH-GATED. `FloorGen` clamps a wave's cap at 8
#      so a redraw can never make a hand-tuned floor denser than authored — and that
#      clamp was silently eating the ascent's entire pressure escalation, which is
#      not visible anywhere because a clamped number is not a rejected one. Found by
#      `tools/probe_endless_curve.gd`; this is the regression guard.
#   5. A WIPE DEEP IN THE ASCENT COSTS A BAND, NOT THE CLIMB.
#      `DeathRules.resume_floor_after_game_over` CLAMPS its floor to its total, so
#      passing the authored ten would turn "you fell on 37" into "you fell on 10" and
#      resume you at 6 — twenty-seven floors deleted by one death, silently.
#   6. `GameState` DRAGS NO COMBAT SCRIPT INTO ITS COMPILE GRAPH. Naming
#      `FloorBuilder` there reaches `DestructibleProp.gd`, which calls the `Sfx`
#      AUTOLOAD — unresolvable in a `--script` harness's `_init`, where it fails the
#      whole compile with an error naming a crate sound effect.
#   7. THE SCORE ORDERS, RANKS AND ROUND-TRIPS. Including the JSON int/float trap
#      that has cost this project a save file once already.
#
# ⚠ AND `ClimbScore` IS EXERCISED THROUGH `preload`, WHICH IS THE POINT. It has no
# `class_name`, so a consumer holds the SCRIPT OBJECT and every entry point must be
# `static`. A plain `func` there fails at RUNTIME and not at parse time — so calling
# each one here is the only thing that can catch it.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
# A dead property read ABORTS the enclosing function and returns the type's zero, so
# failures accumulate on the MEMBER `_fails` and every test records a completion
# sentinel as its last line: a test that aborts part-way fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"spine_is_untouched",
	"ship_path_is_endless_builder_is_not",
	"ascent_floors_are_well_formed",
	"trash_hp_is_never_scaled",
	"type_rhythm_puts_a_guardian_before_every_checkpoint",
	"escalation_is_monotone_and_plateaus_where_stated",
	"the_seam_is_a_step_up",
	"ascent_is_deterministic",
	"cap_ceiling_is_depth_gated",
	"health_packs_taper_and_zero_is_obeyed",
	"health_pack_fractions_agree",
	"floor_affixes_only_ride_the_ascent",
	"gamestate_drags_no_combat_script_into_compile_scope",
	"climb_ceiling_and_labels",
	"a_wipe_deep_in_the_ascent_costs_a_band",
	"advancing_past_the_summit_keeps_climbing",
	"score_ranking_rule",
	"score_board_inserts_sorts_and_caps",
	"score_best_is_derived_not_stored",
	"score_rank_and_record",
	"score_survives_json",
	"score_wire_seam_round_trips",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const GS_PATH: String = "res://scripts/GameState.gd"
## ⚠ REACHED BY RUNTIME `load()`, NEVER NAMED. `FloorBuilder` preloads
## `DestructibleProp.tscn`, whose script calls the `Sfx` AUTOLOAD — and an autoload
## identifier cannot resolve while THIS script is being compiled, which is before the
## tree exists. Naming it here put a `Compile Error: Identifier not found: Sfx` into
## every run of this suite (measured: present in this suite, absent in two others,
## across four runs and independent of the MCP port). The harness treats any runtime
## SCRIPT ERROR as a failure, correctly — a suite can sail past one and still print
## all PASS. Loaded inside a function, after `_process`, the autoloads are registered
## and it resolves. Same trap, from the other end, as the note in `GameState`'s
## DEFAULT_HEALTH_PACK_FRACTIONS.
const FLOOR_BUILDER_PATH: String = "res://scripts/combat/FloorBuilder.gd"
## ⚠ THE CONSUMER'S OWN IDIOM. Reached by `preload`, which yields the script object
## and therefore only ever exposes `static` entry points. See the header.
const ClimbScore := preload("res://scripts/tower/ClimbScore.gd")

## A seed the ascent is derived from in the determinism tests. Any non-zero value;
## pinned so a failure is reproducible rather than "it went red once".
const PIN_SEED: int = 424242


func _process(_delta: float) -> bool:
	# `_initialize()` runs before the tree exists and `FloorGen._coop_active()` reaches
	# through the main loop's root, so everything waits a frame.
	if _ran:
		return false
	_ran = true
	var GS: GDScript = load(GS_PATH) as GDScript

	_test_spine_is_untouched(GS)
	_test_ship_path_is_endless(GS)
	_test_ascent_well_formed(GS)
	_test_trash_hp(GS)
	_test_type_rhythm(GS)
	_test_escalation(GS)
	_test_the_seam(GS)
	_test_determinism(GS)
	_test_cap_ceiling(GS)
	_test_health_packs(GS)
	_test_pack_fractions_agree(GS)
	_test_floor_affixes(GS)
	_test_no_combat_in_compile_scope()
	_test_ceiling_and_labels(GS)
	_test_wipe_in_the_ascent(GS)
	_test_advance_past_summit(GS)
	_test_score_ranking()
	_test_score_board()
	_test_score_best_derived()
	_test_score_rank_and_record()
	_test_score_json()
	_test_score_wire()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Endless-tower tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Endless-tower tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## A GameState with the shipped (endless, generated) tower on it, at a pinned seed so
## every floor in this suite is reproducible. Freed by the caller.
func _endless(GS: GDScript, seed_value: int = PIN_SEED) -> Node:
	var gs: Node = GS.new()
	FloorGen.climb_seed = seed_value
	gs.active_tower = gs._load_or_build_tower()
	FloorGen.climb_seed = 0
	return gs


# ═══════════════════════════════════════════════════════════════════════════════
# 1 — THE SEAM
# ═══════════════════════════════════════════════════════════════════════════════
## The authored ten must be the SAME OBJECTS the tower holds, not regenerated
## lookalikes. Compared field-for-field against the tower's own array, because
## "floor_def_for(3) returns something plausible" is exactly what a bug would do.
func _test_spine_is_untouched(GS: GDScript) -> void:
	var gs: Node = _endless(GS)
	var spine: Array = gs.active_tower.floors
	_expect(spine.size() == int(GS.TOTAL_FLOORS),
		"the shipped tower still authors all %d spine floors (got %d)"
			% [int(GS.TOTAL_FLOORS), spine.size()])
	for f: int in range(1, spine.size() + 1):
		var got: FloorDef = gs.floor_def_for(f)
		_expect(got == spine[f - 1],
			"floor %d is the AUTHORED FloorDef itself, not a regenerated lookalike" % f)
	# And the authored table's own identity survives the generator, which is the
	# property `FloorGen` was written to hold and which the ascent must not disturb.
	var plain: Resource = GS.build_default_tower()
	for f2: int in range(1, mini(spine.size(), plain.floors.size()) + 1):
		var a: FloorDef = spine[f2 - 1]
		var b: FloorDef = plain.floors[f2 - 1]
		_expect(int(a.floor_type) == int(b.floor_type),
			"floor %d keeps its authored TYPE through the generator" % f2)
		_expect(a.waves.size() == b.waves.size(),
			"floor %d keeps its authored WAVE COUNT" % f2)
		_expect(a.enemy_budget == b.enemy_budget,
			"floor %d keeps its authored BODY COUNT (%d vs %d)"
				% [f2, a.enemy_budget, b.enemy_budget])
		_expect(is_equal_approx(a.boss_hp_multiplier, b.boss_hp_multiplier),
			"floor %d keeps its authored guardian curve" % f2)
	gs.free()
	_completes("spine_is_untouched")


## ⚠ THE LOAD-BEARING SPLIT. `build_default_tower()` is asserted against by eight
## tools; the game's own path is the one that goes infinite.
func _test_ship_path_is_endless(GS: GDScript) -> void:
	var plain: Resource = GS.build_default_tower()
	_expect(plain.endless == false,
		"build_default_tower() is FINITE — eight suites assert the authored ten against it")
	var gs: Node = _endless(GS)
	_expect(gs.active_tower.endless == true,
		"_load_or_build_tower() — the only path the game takes — is ENDLESS")
	_expect(gs.is_endless() == true, "…and GameState.is_endless() reports it")
	# A GameState with the plain tower must behave exactly as it did before.
	var gs2: Node = GS.new()
	gs2.active_tower = plain
	_expect(gs2.is_endless() == false, "a finite tower is still finite")
	_expect(gs2.climb_ceiling() == gs2.total_floors(),
		"…and its ceiling is still the authored height")
	gs.free()
	gs2.free()
	_completes("ship_path_is_endless_builder_is_not")


func _test_ascent_well_formed(GS: GDScript) -> void:
	var gs: Node = _endless(GS)
	var checked: int = 0
	for f: int in range(11, 61):
		var fd: FloorDef = gs.floor_def_for(f)
		checked += 1
		if fd == null:
			_expect(false, "floor %d exists" % f)
			continue
		_expect(fd.depth == f, "floor %d knows its own depth (got %d)" % [f, fd.depth])
		_expect(not fd.waves.is_empty(), "floor %d has waves" % f)
		_expect(fd.layout != null, "floor %d has a room" % f)
		_expect(fd.theme != null, "floor %d has a biome" % f)
		var bodies: int = 0
		for w: WaveDef in fd.waves:
			_expect(w.enemy_budget > 0, "floor %d wave budget is positive" % f)
			_expect(w.concurrent_cap >= 2, "floor %d wave cap is at least 2" % f)
			_expect(not w.archetypes.is_empty(), "floor %d wave names a roster" % f)
			bodies += w.enemy_budget
		_expect(bodies == fd.enemy_budget,
			"floor %d's flat budget agrees with its waves (%d vs %d)"
				% [f, fd.enemy_budget, bodies])
	_expect(checked == 50, "fifty ascent floors were built (%d)" % checked)
	gs.free()
	_completes("ascent_floors_are_well_formed")


# ═══════════════════════════════════════════════════════════════════════════════
# 2 — THE RULE
# ═══════════════════════════════════════════════════════════════════════════════
## "higher floors add modifiers, not HP." Checked on the BLUEPRINT and on the
## GENERATED floor, because the generator is perfectly capable of putting it back.
func _test_trash_hp(GS: GDScript) -> void:
	for d: int in [11, 12, 25, 40, 99, 200, 999]:
		var bp: FloorDef = GS.ascent_floor_def(d)
		_expect(is_equal_approx(bp.hp_multiplier, 1.0),
			"ascent blueprint at depth %d runs trash at 1.0x (got %.2f)" % [d, bp.hp_multiplier])
		for w: WaveDef in bp.waves:
			_expect(w.resolved_hp(bp.hp_multiplier) == 1.0,
				"every wave at depth %d resolves to 1.0x trash HP" % d)
	var gs: Node = _endless(GS)
	for f: int in range(11, 61):
		var fd: FloorDef = gs.floor_def_for(f)
		_expect(is_equal_approx(fd.hp_multiplier, 1.0),
			"generated floor %d runs trash at 1.0x (got %.2f)" % [f, fd.hp_multiplier])
	# The guardian is the ONE legitimate curve, and it is capped rather than open.
	for d2: int in [26, 50, 200, 999]:
		_expect(GS.ascent_floor_def(d2).boss_hp_multiplier <= GS.ASCENT_BOSS_HP_CAP + 0.001,
			"the guardian curve is capped at %.1fx even at depth %d"
				% [GS.ASCENT_BOSS_HP_CAP, d2])
	gs.free()
	_completes("trash_hp_is_never_scaled")


## Every band ends in a guardian, and the checkpoint you resume on after failing it
## is the floor immediately after. That alignment is the reason the period is 5.
func _test_type_rhythm(GS: GDScript) -> void:
	for d: int in [15, 20, 25, 30, 45, 100]:
		_expect(int(GS.ascent_floor_def(d).floor_type) == FloorDef.FloorType.BOSS,
			"floor %d is a guardian floor" % d)
		_expect(DeathRules.checkpoint_for(d + 1) == d + 1,
			"…and floor %d, right after it, is a checkpoint" % (d + 1))
	for d2: int in [13, 18, 23, 48]:
		_expect(int(GS.ascent_floor_def(d2).floor_type) == FloorDef.FloorType.ELITE,
			"floor %d is an elite floor" % d2)
	for d3: int in [11, 12, 14, 16, 17, 19]:
		_expect(int(GS.ascent_floor_def(d3).floor_type) == FloorDef.FloorType.COMBAT,
			"floor %d is an ordinary combat floor" % d3)
	_completes("type_rhythm_puts_a_guardian_before_every_checkpoint")


## The blueprint's axes rise and then STOP where the design note says they stop.
## Asserted on the blueprint rather than the generated floor because the generator
## deliberately jitters ±1 and this is a statement about the CURVE, not the draw.
func _test_escalation(GS: GDScript) -> void:
	var prev_bodies: int = 78
	var prev_boss: float = 2.4
	for d: int in range(11, 200):
		var fd: FloorDef = GS.ascent_floor_def(d)
		_expect(fd.enemy_budget >= prev_bodies,
			"bodies never decrease with depth (floor %d: %d after %d)"
				% [d, fd.enemy_budget, prev_bodies])
		_expect(fd.enemy_budget <= GS.ASCENT_BODY_CAP,
			"bodies never exceed the ceiling (floor %d: %d)" % [d, fd.enemy_budget])
		_expect(fd.concurrent_cap <= GS.ASCENT_CAP_MAX,
			"pressure never exceeds the ceiling (floor %d: %d)" % [d, fd.concurrent_cap])
		_expect(fd.waves.size() <= GS.ASCENT_MAX_WAVES,
			"a floor is never more than %d waves (floor %d: %d)"
				% [GS.ASCENT_MAX_WAVES, d, fd.waves.size()])
		_expect(fd.boss_hp_multiplier >= prev_boss - 0.001,
			"the guardian curve never decreases (floor %d)" % d)
		prev_bodies = fd.enemy_budget
		prev_boss = fd.boss_hp_multiplier
	# The plateaus, named. These are the numbers the design note commits to; if one
	# moves, the note is wrong and this is where that gets said out loud.
	_expect(GS.ascent_floor_def(16).enemy_budget == GS.ASCENT_BODY_CAP,
		"bodies reach their ceiling at floor 16")
	_expect(GS.ascent_floor_def(21).concurrent_cap == GS.ASCENT_CAP_MAX,
		"pressure reaches its ceiling at floor 21")
	_expect(is_equal_approx(GS.ascent_floor_def(26).boss_hp_multiplier, GS.ASCENT_BOSS_HP_CAP),
		"the guardian curve reaches its cap at floor 26")
	_completes("escalation_is_monotone_and_plateaus_where_stated")


## ⚠ THE SEAM MUST BE A STEP UP, AND IT WAS NOT. The first version ramped a floor's
## MAXIMUM class breadth from 2, which made floors 11-15 NARROWER than floor 10 —
## whose finale already fields all four classes. Measured by
## `tools/probe_endless_curve.gd`, four of the first five ascent floors came back
## easier than the summit.
##
## The invariant that fixes it and keeps it fixed: EVERY ascent floor's last wave
## fields as many threat classes as the spine's last wave did.
func _test_the_seam(GS: GDScript) -> void:
	var summit: FloorDef = GS.build_default_tower().floors[int(GS.TOTAL_FLOORS) - 1]
	var summit_finale: int = _classes_in(summit.waves[summit.waves.size() - 1])
	_expect(summit_finale >= 4,
		"the authored summit's finale is four classes wide (got %d)" % summit_finale)
	for d: int in range(11, 40):
		var fd: FloorDef = GS.ascent_floor_def(d)
		var finale: int = _classes_in(fd.waves[fd.waves.size() - 1])
		_expect(finale >= summit_finale,
			"floor %d's finale is at least as wide as the summit's (%d vs %d)"
				% [d, finale, summit_finale])
		_expect(fd.enemy_budget >= summit.enemy_budget,
			"floor %d brings at least as many bodies as the summit (%d vs %d)"
				% [d, fd.enemy_budget, summit.enemy_budget])
	# ...and the OPENING is what escalates: a deep floor stops giving you a narrow
	# wave to settle into.
	_expect(_classes_in(GS.ascent_floor_def(11).waves[0])
			< _classes_in(GS.ascent_floor_def(30).waves[0]),
		"a deep floor OPENS wider than a shallow ascent floor")
	_completes("the_seam_is_a_step_up")


## How many distinct threat classes one wave fields.
func _classes_in(w: WaveDef) -> int:
	var seen: Dictionary = {}
	for a: int in w.archetypes:
		seen[FloorGen.threat_class(a)[0]] = true
	return seen.size() if not seen.is_empty() else 4


## Same tower, same seed, same floor — twice. This is the co-op property: two peers
## derive floor 37 independently and must agree on every field of it.
func _test_determinism(GS: GDScript) -> void:
	var a: Node = _endless(GS, PIN_SEED)
	var b: Node = _endless(GS, PIN_SEED)
	var differed: int = 0
	for f: int in [11, 23, 37, 50]:
		var fa: FloorDef = a.floor_def_for(f)
		var fb: FloorDef = b.floor_def_for(f)
		_expect(fa.layout.room_size == fb.layout.room_size,
			"floor %d draws the same room on both peers" % f)
		_expect(fa.layout.exit_point == fb.layout.exit_point,
			"floor %d puts the exit in the same place" % f)
		_expect(fa.layout.platforms == fb.layout.platforms,
			"floor %d draws the same skyline" % f)
		_expect(fa.special_tags == fb.special_tags,
			"floor %d carries the same tags (shape, seed, affixes)" % f)
		_expect(fa.enemy_budget == fb.enemy_budget,
			"floor %d is the same amount of fight" % f)
	# ...and a DIFFERENT seed must actually draw a different tower, or the whole
	# generator is decorative. Compared across several floors because any one room
	# can legitimately collide.
	var c: Node = _endless(GS, PIN_SEED + 1)
	for f2: int in [11, 23, 37, 50]:
		if a.floor_def_for(f2).layout.room_size != c.floor_def_for(f2).layout.room_size:
			differed += 1
	_expect(differed > 0, "a different climb seed draws a different ascent")
	a.free()
	b.free()
	c.free()
	_completes("ascent_is_deterministic")


## ⚠ THE REGRESSION GUARD FOR THE BUG THE PROBE FOUND. `vary_waves` clamps a wave's
## cap so a redraw can never make a hand-tuned floor denser than authored — and that
## same clamp was silently discarding the ascent's entire pressure escalation. A
## clamped number is not a rejected one, so nothing anywhere reported it.
func _test_cap_ceiling(GS: GDScript) -> void:
	_expect(FloorGen.ASCENT_WAVE_CAP_MAX > FloorGen.WAVE_CAP_MAX,
		"the ascent ceiling is above the authored one, or it buys nothing")
	# The authored spine must never exceed its own ceiling, under any seed.
	for s: int in range(1, 12):
		var gs: Node = _endless(GS, s * 1013)
		for f: int in range(1, int(GS.TOTAL_FLOORS) + 1):
			for w: WaveDef in gs.floor_def_for(f).waves:
				_expect(w.concurrent_cap <= FloorGen.WAVE_CAP_MAX,
					"authored floor %d never exceeds cap %d (seed %d gave %d)"
						% [f, FloorGen.WAVE_CAP_MAX, s * 1013, w.concurrent_cap])
		gs.free()
	# ...and a deep ascent floor must actually REACH above it, or the escalation is
	# being eaten again. Swept across seeds because any single draw may sit low.
	var reached: int = 0
	for s2: int in range(1, 12):
		var gs2: Node = _endless(GS, s2 * 1013)
		for f2: int in range(21, 40):
			for w2: WaveDef in gs2.floor_def_for(f2).waves:
				if w2.concurrent_cap > FloorGen.WAVE_CAP_MAX:
					reached += 1
		gs2.free()
	_expect(reached > 0,
		"the deep ascent actually reaches a pressure cap above %d — it was being "
		% FloorGen.WAVE_CAP_MAX + "clamped straight back to it, which is invisible")
	_completes("cap_ceiling_is_depth_gated")


## Healing, taken away — the terminal escalation, and the one that needed a new flag
## because "empty" already meant "no opinion".
func _test_health_packs(GS: GDScript) -> void:
	var gs: Node = _endless(GS)
	_expect(gs.floor_def_for(15).layout.health_pickups.size() == 2,
		"floor 15 still offers both packs")
	_expect(gs.floor_def_for(25).layout.health_pickups.size() == 1,
		"floor 25 offers one")
	_expect(gs.floor_def_for(40).layout.health_pickups.is_empty(),
		"floor 40 offers none")
	for f: int in [15, 25, 40]:
		_expect(gs.floor_def_for(f).layout.health_packs_authored,
			"floor %d STATES its packs, so an empty list means none rather than "
			% f + "'no opinion' — without the flag the builder would give it two")
	# The authored spine must keep taking the default pair.
	for f2: int in range(1, int(GS.TOTAL_FLOORS) + 1):
		_expect(not gs.floor_def_for(f2).layout.health_packs_authored,
			"authored floor %d has no opinion about packs and keeps the default pair" % f2)
	# And the BUILDER must honour it — the flag is worthless if `build_health_packs`
	# still falls through to the default.
	var l := LayoutDef.new()
	l.health_packs_authored = true
	var FB: GDScript = load(FLOOR_BUILDER_PATH) as GDScript
	var room := Node2D.new()
	root.add_child(room)
	FB.build_health_packs(room, l)
	_expect(room.get_child_count() == 0,
		"an authored-empty layout builds NO packs (built %d)" % room.get_child_count())
	var l2 := LayoutDef.new()
	var room2 := Node2D.new()
	root.add_child(room2)
	FB.build_health_packs(room2, l2)
	_expect(room2.get_child_count() == (FB.DEFAULT_HEALTH_PACKS as Array).size(),
		"a silent layout still gets the default pair (built %d)" % room2.get_child_count())
	room.queue_free()
	room2.queue_free()
	gs.free()
	_completes("health_packs_taper_and_zero_is_obeyed")


## ⚠ THE DUPLICATION GUARD. `GameState` cannot NAME `FloorBuilder` (see the compile
## -scope test below), so it carries its own copy of the pack fractions. Same trade
## `FloorGen.FLOOR_AFFIX_POOL` makes against `EliteRoster`'s, and the same guard:
## the two lists are checked against each other rather than hoped about.
func _test_pack_fractions_agree(GS: GDScript) -> void:
	var mine: Array = GS.DEFAULT_HEALTH_PACK_FRACTIONS
	var theirs: Array = (load(FLOOR_BUILDER_PATH) as GDScript).DEFAULT_HEALTH_PACKS
	_expect(mine.size() == theirs.size(),
		"GameState and FloorBuilder agree on how many default packs (%d vs %d)"
			% [mine.size(), theirs.size()])
	for i: int in mini(mine.size(), theirs.size()):
		_expect(Vector2(mine[i]).is_equal_approx(Vector2(theirs[i])),
			"default pack %d is the same point in both files (%s vs %s)"
				% [i, str(mine[i]), str(theirs[i])])
	_completes("health_pack_fractions_agree")


## Floor-wide affixes ride the ASCENT and nothing else. `docs/THE-TOWER-mobile-plan.md`
## lists floor modifiers as out for v1, and floors 1-10 are the whole game today.
func _test_floor_affixes(GS: GDScript) -> void:
	var gs: Node = _endless(GS)
	for f: int in range(1, int(GS.TOTAL_FLOORS) + 1):
		var got: Array[String] = EliteRoster.parse_floor_affixes(gs.floor_def_for(f).special_tags)
		_expect(got.is_empty(),
			"authored floor %d rides clean (got %s)" % [f, str(got)])
	_expect(FloorGen.ascent_affix_count(10) == 0, "floor 10 has no floor affix")
	_expect(FloorGen.ascent_affix_count(11) == 1, "floor 11 gains one")
	_expect(FloorGen.ascent_affix_count(26) == 2, "floor 26 gains a second")
	_expect(FloorGen.ascent_affix_count(41) == 3, "floor 41 gains a third")
	_expect(FloorGen.ascent_affix_count(999) == 3, "…and three is the whole pool, so it stops")
	for f2: int in [11, 26, 41]:
		var got2: Array[String] = EliteRoster.parse_floor_affixes(
			gs.floor_def_for(f2).special_tags)
		_expect(got2.size() == FloorGen.ascent_affix_count(f2),
			"floor %d actually carries %d affix(es), got %d"
				% [f2, FloorGen.ascent_affix_count(f2), got2.size()])
		# Drawn without replacement — two of the same word is one rule, not two.
		var uniq: Dictionary = {}
		for a: String in got2:
			uniq[a] = true
		_expect(uniq.size() == got2.size(), "floor %d's affixes are distinct" % f2)
	gs.free()
	_completes("floor_affixes_only_ride_the_ascent")


## ⚠ `GameState` IS LOADED BY A LOT OF SUITES, AND EVERY COMPILE-SCOPE DEPENDENCY IT
## GAINS IS PAID BY ALL OF THEM. Naming `FloorBuilder` here reaches
## `DestructibleProp.tscn` -> `DestructibleProp.gd` -> `Sfx.play(...)`, and `Sfx` is
## an AUTOLOAD rather than a `class_name`: in any `--script` harness that `load()`s
## GameState from `_init`, autoloads are not registered yet, the identifier does not
## resolve, and the WHOLE compile fails with an error naming a crate sound effect and
## pointing nowhere near the tower. `slice_test_runend` did exactly that.
##
## Source-text, not behaviour, because the failure is a COMPILE-graph property and by
## the time this suite is running the compile has already succeeded or not.
func _test_no_combat_in_compile_scope() -> void:
	var src: String = FileAccess.get_file_as_string(GS_PATH)
	_expect(src != "", "GameState source is readable")
	var offenders: int = 0
	var line_no: int = 0
	for line: String in src.split("\n"):
		line_no += 1
		var t: String = line.strip_edges()
		if t.begins_with("#"):
			continue          # a comment may name it; only CODE puts it in the graph
		if t.contains("FloorBuilder."):
			offenders += 1
			_expect(false,
				"GameState.gd:%d names FloorBuilder in CODE — that drags DestructibleProp "
				% line_no + "and the Sfx autoload into every context that loads GameState")
	_expect(offenders == 0, "GameState reaches no combat script at compile scope")
	_completes("gamestate_drags_no_combat_script_into_compile_scope")


# ═══════════════════════════════════════════════════════════════════════════════
# 3 — THE CLIMB
# ═══════════════════════════════════════════════════════════════════════════════
func _test_ceiling_and_labels(GS: GDScript) -> void:
	var gs: Node = _endless(GS)
	_expect(gs.climb_ceiling() == int(GS.MAX_CLIMB_FLOOR),
		"an endless climb's ceiling is the guard rail, not the authored ten")
	gs._floor = 4
	_expect(gs.has_next_floor(), "there is a floor above 4")
	gs._floor = int(GS.TOTAL_FLOORS)
	_expect(gs.has_next_floor(),
		"…and there is a floor above the SUMMIT, which is the whole change")
	_expect(gs.floor_label(7).contains("/"),
		"a spine floor still reads 'Floor 7 / 10' (got '%s')" % gs.floor_label(7))
	_expect(not gs.floor_label(34).contains("/"),
		"an ascent floor reads 'Floor 34' with no total (got '%s')" % gs.floor_label(34))
	_expect(gs.floor_label(34).contains("34"), "…and it names the floor")
	gs.free()
	_completes("climb_ceiling_and_labels")


## ⚠ THE SILENT-DELETION GUARD. `DeathRules.resume_floor_after_game_over` CLAMPS its
## floor to its total before taking the band, so handing it `total_floors()` on an
## endless tower turns "you fell on floor 37" into "you fell on floor 10" and resumes
## you at 6 — twenty-seven floors deleted by one death, with nothing reporting it.
func _test_wipe_in_the_ascent(GS: GDScript) -> void:
	var gs: Node = _endless(GS)
	gs._run_active = true
	gs._floor = 37
	gs._highest_floor = 37
	gs._falls = 2
	gs.game_over()
	_expect(gs._falls == 3, "a wipe still ticks the fall counter")
	_expect(gs._highest_floor == 37, "…and never rolls your best backwards")
	_expect(gs._floor == DeathRules.checkpoint_for(37),
		"a wipe on floor 37 resumes at its band (%d), not at the spine's (got %d)"
			% [DeathRules.checkpoint_for(37), gs._floor])
	_expect(gs._floor > int(GS.TOTAL_FLOORS),
		"…which is to say it leaves you IN the ascent rather than back on the spine")
	_expect(int(gs.last_run.get("floor_reached", 0)) == 37,
		"the card is handed the floor you actually died on")
	gs.free()
	_completes("a_wipe_deep_in_the_ascent_costs_a_band")


## The summit becomes a milestone instead of an ending — but ONLY on an endless
## tower. A finite one must still conquer and stop, because eight suites say so.
func _test_advance_past_summit(GS: GDScript) -> void:
	var gs: Node = _endless(GS)
	gs._run_active = true
	gs._floor = int(GS.TOTAL_FLOORS)
	gs._highest_floor = gs._floor
	var advanced: Array = []
	gs.floor_advanced.connect(func(nf: int) -> void: advanced.append(nf))
	gs.advance_floor()
	_expect(gs._floor == int(GS.TOTAL_FLOORS) + 1,
		"clearing the summit of an ENDLESS tower climbs into the ascent (got %d)" % gs._floor)
	_expect(gs.tower_conquered, "…and still banks the conquest milestone")
	_expect(gs._run_active, "…and does NOT end the run")
	_expect(advanced.size() == 1 and int(advanced[0]) == int(GS.TOTAL_FLOORS) + 1,
		"…and emits floor_advanced so every peer rebuilds its Arena")
	# Re-entering must not send a conquered endless climber back to floor 1.
	gs._run_active = false
	gs._floor = 23
	gs.tower_conquered = true
	gs._floor = clampi(gs._floor, 1, gs.climb_ceiling())
	_expect(gs._floor == 23,
		"a conquered ENDLESS climb resumes where it was, not at floor 1")

	# The finite tower is unchanged: conquer, no floor_advanced, run over.
	var gs2: Node = GS.new()
	gs2.active_tower = GS.build_default_tower()
	gs2._run_active = true
	gs2._floor = int(gs2.total_floors())
	var advanced2: Array = []
	gs2.floor_advanced.connect(func(nf: int) -> void: advanced2.append(nf))
	gs2.advance_floor()
	_expect(gs2.tower_conquered, "a FINITE tower still conquers at its last floor")
	_expect(advanced2.is_empty(), "…and still emits no floor_advanced")
	_expect(not gs2._run_active, "…and still ends the run")
	gs.free()
	gs2.free()
	_completes("advancing_past_the_summit_keeps_climbing")


# ═══════════════════════════════════════════════════════════════════════════════
# 4 — THE SCORE
# ═══════════════════════════════════════════════════════════════════════════════
## peak_floor DESC, elapsed_ms ASC. The whole rule.
func _test_score_ranking() -> void:
	var high: Dictionary = ClimbScore.make_record(34, 900000)
	var low: Dictionary = ClimbScore.make_record(33, 10)
	_expect(ClimbScore.is_better(high, low),
		"a higher floor outranks a lower one however slow it was — height is the game")
	var fast: Dictionary = ClimbScore.make_record(34, 500000, 0, false, 0, 100)
	var slow: Dictionary = ClimbScore.make_record(34, 900000, 0, false, 0, 100)
	_expect(ClimbScore.is_better(fast, slow), "equal floors: the faster climb wins")
	_expect(not ClimbScore.is_better(slow, fast), "…and the rule is not symmetric")
	var older: Dictionary = ClimbScore.make_record(34, 500000, 0, false, 0, 100)
	var newer: Dictionary = ClimbScore.make_record(34, 500000, 0, false, 0, 200)
	_expect(ClimbScore.is_better(older, newer),
		"a dead-equal repeat does not bump your own earlier row down the board")
	_completes("score_ranking_rule")


func _test_score_board() -> void:
	var board: Array = []
	for i: int in 40:
		board = ClimbScore.insert(board, ClimbScore.make_record(i + 1, 1000, 0, false, 0, i))
	_expect(board.size() == ClimbScore.MAX_HISTORY,
		"the board caps at %d rows (got %d)" % [ClimbScore.MAX_HISTORY, board.size()])
	_expect(int(board[0][ClimbScore.K_FLOOR]) == 40, "the best row is first")
	# ⚠ TRUNCATION AFTER THE SORT, NOT BEFORE. A great run inserted into a full board
	# must displace the WORST row, never the oldest — which is what a naive
	# prepend-then-resize would do.
	var kept_low: int = int(board[board.size() - 1][ClimbScore.K_FLOOR])
	_expect(kept_low == 16,
		"the 25 rows kept are the BEST 25 (lowest kept is floor %d, expected 16)" % kept_low)
	var ranked: Array = ClimbScore.ranked(board)
	for i2: int in range(1, ranked.size()):
		_expect(int(ranked[i2 - 1][ClimbScore.K_FLOOR]) >= int(ranked[i2][ClimbScore.K_FLOOR]),
			"the board is ordered at row %d" % i2)
	# `ranked` must not reorder the caller's array — `rank_of` asks a hypothetical.
	var src: Array = [ClimbScore.make_record(2, 5), ClimbScore.make_record(9, 5)]
	var before: int = int(src[0][ClimbScore.K_FLOOR])
	var _r: Array = ClimbScore.ranked(src)
	_expect(int(src[0][ClimbScore.K_FLOOR]) == before,
		"ranked() copies rather than sorting the caller's board underneath it")
	_completes("score_board_inserts_sorts_and_caps")


## The personal best is DERIVED. Nothing stores it, so nothing can drift from it.
func _test_score_best_derived() -> void:
	_expect(ClimbScore.best([]).is_empty(),
		"an empty board has no best — which is not the same as a best of floor 1")
	_expect(ClimbScore.best_floor([]) == 0, "…and its best floor reads 0")
	var board: Array = ClimbScore.insert([], ClimbScore.make_record(12, 400))
	board = ClimbScore.insert(board, ClimbScore.make_record(31, 900))
	board = ClimbScore.insert(board, ClimbScore.make_record(7, 100))
	_expect(ClimbScore.best_floor(board) == 31, "the best is the best, whenever it happened")
	_expect(ClimbScore.best(board) == ClimbScore.ranked(board)[0],
		"best() IS the top of the ranked board — one source, so they cannot disagree")
	_completes("score_best_is_derived_not_stored")


func _test_score_rank_and_record() -> void:
	var board: Array = []
	for f: int in [40, 30, 20, 10]:
		board = ClimbScore.insert(board, ClimbScore.make_record(f, 1000))
	_expect(ClimbScore.rank_of(board, ClimbScore.make_record(45, 1000)) == 1, "a new best is 1st")
	_expect(ClimbScore.rank_of(board, ClimbScore.make_record(35, 1000)) == 2, "…and 35 is 2nd")
	_expect(ClimbScore.rank_of(board, ClimbScore.make_record(5, 1000)) == 5,
		"a run that beats nothing places last+1")
	_expect(ClimbScore.is_record(board, ClimbScore.make_record(41, 1000)), "41 is a record")
	_expect(not ClimbScore.is_record(board, ClimbScore.make_record(39, 1000)), "39 is not")
	_expect(ClimbScore.is_record([], ClimbScore.make_record(1, 1)),
		"the FIRST climb is always a record — otherwise it is the only one that never gets the moment")
	_completes("score_rank_and_record")


## ⚠ THE M9 TRAP, IN THE NEW FILE. `JSON.parse_string` returns every number as
## TYPE_FLOAT, so a stored `34` comes back as `34.0`; comparing that against an int
## matches nothing and writing it back puts `34.0` in the file. This project has lost
## a save to precisely this once.
func _test_score_json() -> void:
	var board: Array = ClimbScore.insert([], ClimbScore.make_record(34, 512345, 3, true, 91, 1700))
	var payload: Dictionary = ClimbScore.build_board(board)
	var text: String = JSON.stringify(payload)
	var back: Dictionary = ClimbScore.parse_board(JSON.parse_string(text))
	var rows: Array = back["history"]
	_expect(rows.size() == 1, "the row survives the round trip")
	if rows.is_empty():
		_completes("score_survives_json")
		return
	var r: Dictionary = rows[0]
	_expect(typeof(r[ClimbScore.K_FLOOR]) == TYPE_INT,
		"peak_floor comes back an INT, not the float JSON handed us")
	_expect(typeof(r[ClimbScore.K_MS]) == TYPE_INT, "elapsed_ms comes back an int")
	_expect(typeof(r[ClimbScore.K_CLASS]) == TYPE_INT, "hero_class comes back an int")
	_expect(int(r[ClimbScore.K_FLOOR]) == 34, "…and the value survives")
	_expect(bool(r[ClimbScore.K_DIED]), "…as does the death flag")
	# Garbage in must not be able to stop the game starting.
	_expect((ClimbScore.parse_board(null)["history"] as Array).is_empty(),
		"a null board parses to empty rather than erroring")
	_expect((ClimbScore.parse_board({"history": "not an array"})["history"] as Array).is_empty(),
		"a malformed board parses to empty")
	_expect(ClimbScore.parse_record({"nothing": 1}).is_empty(),
		"a row with no floor is not a run and is dropped")
	_completes("score_survives_json")


## The remote seam. There is no server; this is the shape one would be handed.
func _test_score_wire() -> void:
	var rec: Dictionary = ClimbScore.make_record(34, 512345, 3, true, 91, 1700, true)
	var wire: Dictionary = ClimbScore.to_wire(rec, "climber-1", "ashspire", "0.9")
	_expect(int(wire.get("floor", 0)) == 34, "the wire payload carries the height")
	_expect(String(wire.get("climber", "")) == "climber-1", "…and whatever identity there is")
	var back: Dictionary = ClimbScore.from_wire(wire)
	_expect(int(back[ClimbScore.K_FLOOR]) == 34, "…and it round-trips")
	_expect(int(back[ClimbScore.K_MS]) == 512345, "…including the tiebreak")
	_expect(bool(back[ClimbScore.K_COOP]), "…and the co-op fact")
	# A wire payload is the most untrusted input in the system.
	_expect(ClimbScore.from_wire("not a dict").is_empty(), "junk off the wire is refused")
	_expect(ClimbScore.from_wire({"ms": 1}).is_empty(), "a payload with no floor is refused")
	_completes("score_wire_seam_round_trips")
