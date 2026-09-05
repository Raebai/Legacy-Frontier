# Run: godot --headless --path godot-project --script tools/slice_test_floorgen.gd
#
# THE SEEDED FLOOR GENERATOR. Five authored floors, drawn differently every climb.
# This suite exists to hold three lines that are easy to cross by accident:
#
#   1. CO-OP DETERMINISM. Both phones must draw the identical floor. One unseeded
#      `randi()` anywhere in the floor path desyncs the party, and it presents as a
#      mystery bug rather than as a generator bug. So: the same seed is rolled twice
#      and compared FIELD BY FIELD — room size, every ledge, every crate, every
#      pickup, every wave knob, the tint, the tags.
#   2. DIFFICULTY STAYS HONEST. The spec is explicit that depth escalates through
#      modifiers and composition, NEVER through HP. A previous pass pinned trash
#      `hp_multiplier` at 1.0 on every floor; this asserts the generator cannot
#      reintroduce HP-as-difficulty through the back door, and that a re-rolled floor
#      is the same amount of fight as the authored one.
#   3. NO UNWINNABLE OR DEGENERATE ROLLS. Every ledge, the exit, every pickup and
#      every crate must sit on a surface the reachability walk actually reached from
#      the ground; the ground stays a wall-to-wall runway; nothing overlaps.
#      Asserted over MANY seeds, because a generator bug that fires one roll in two
#      hundred is exactly the kind three seeds will miss.
#
# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read ABORTS the enclosing function and hands the caller the return
# type's zero value. So failures accumulate on the MEMBER `_fails`, and every test's
# last line records that it reached the end — a test that aborts part-way is missing
# from `_completed` and fails the suite BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"same_seed_is_byte_identical",
	"different_seeds_draw_different_rooms",
	"floor_identity_survives_the_redraw",
	"hp_is_never_a_difficulty_dial",
	"every_room_fits_one_screen",
	"geometry_invariants_hold",
	"everything_placed_is_reachable",
	"waves_conserve_and_escalate",
	"the_mix_stays_inside_its_threat_band",
	"seed_policy_cannot_desync_a_party",
	"tags_neither_grow_nor_clobber",
	"the_builder_raises_the_skyline",
	"spell_drops_land_where_they_can_be_picked_up",
]

## How many seeds the invariant sweeps walk. Deliberately hundreds: the failure this
## is guarding against is a rare geometry roll, not a systematic one.
const SEEDS: int = 400

const GS_PATH: String = "res://scripts/GameState.gd"
const CAMERA_PATH: String = "res://scripts/combat/CombatCamera.gd"
const BUILDER_PATH: String = "res://scripts/combat/FloorBuilder.gd"

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _tower: Resource = null


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	_tower = (load(GS_PATH) as GDScript).build_default_tower()
	_test_same_seed_is_byte_identical()
	_test_different_seeds_draw_different_rooms()
	_test_floor_identity_survives_the_redraw()
	_test_hp_is_never_a_difficulty_dial()
	_test_every_room_fits_one_screen()
	_test_geometry_invariants_hold()
	_test_everything_placed_is_reachable()
	_test_waves_conserve_and_escalate()
	_test_the_mix_stays_inside_its_threat_band()
	_test_seed_policy_cannot_desync_a_party()
	_test_tags_neither_grow_nor_clobber()
	_test_the_builder_raises_the_skyline()
	_test_spell_drops_land_where_they_can_be_picked_up()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("FloorGen tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("FloorGen tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ---------------------------------------------------------------- 1 · determinism
## THE CO-OP PROOF. Two independent rolls of the same seed, compared field by field
## on both peers' worth of data. Not "the same number of crates" — the same crates.
func _test_same_seed_is_byte_identical() -> void:
	for s: int in [1, 7, 4242, 999983, 0x7FFFFFFF]:
		var a: Resource = FloorGen.vary_tower(_tower, s)
		var b: Resource = FloorGen.vary_tower(_tower, s)
		_expect((a.floors as Array).size() == (b.floors as Array).size(),
			"seed %d: same floor count" % s)
		for i: int in (a.floors as Array).size():
			var fa: FloorDef = a.floors[i]
			var fb: FloorDef = b.floors[i]
			_expect(_floor_eq(fa, fb),
				"seed %d floor %d is byte-identical across two independent rolls" % [s, i + 1])
	# ...and `apply` with an explicit seed is the same thing again, so the entry point
	# the game calls is covered and not just the helper underneath it.
	var c: Resource = FloorGen.apply(_tower, 4242)
	var d: Resource = FloorGen.vary_tower(_tower, 4242)
	for i: int in (c.floors as Array).size():
		_expect(_floor_eq(c.floors[i], d.floors[i]),
			"apply(seed) matches vary_tower(seed) on floor %d" % (i + 1))
	_completes("same_seed_is_byte_identical")


## ...and it is a GENERATOR, not a constant: different seeds have to actually draw
## different rooms, or "deterministic" is being satisfied by doing nothing.
func _test_different_seeds_draw_different_rooms() -> void:
	var shapes: Dictionary = {}
	var rooms: Dictionary = {}
	var same_as_previous: int = 0
	var prev: Resource = null
	for s: int in range(1, 121):
		var t: Resource = FloorGen.vary_tower(_tower, s * 7919)
		for i: int in (t.floors as Array).size():
			var f: FloorDef = t.floors[i]
			rooms[str(f.layout.room_size)] = true
			for tag: String in f.special_tags:
				if tag.begins_with(FloorGen.TAG_SHAPE):
					shapes[tag] = true
		if prev != null and _floor_eq(prev.floors[0], t.floors[0]):
			same_as_previous += 1
		prev = t
	_expect(rooms.size() >= 30,
		"120 seeds produce many distinct room sizes (got %d)" % rooms.size())
	_expect(shapes.size() >= 5,
		"all five layout shapes get drawn across 120 seeds (got %d)" % shapes.size())
	_expect(same_as_previous == 0,
		"no two consecutive seeds drew an identical floor 1 (got %d)" % same_as_previous)
	# ⚠ THE ANTI-VACUOUS GATE, and it has already earned its keep. Every geometry
	# invariant in this suite is trivially true of a floor with NO ledges, so a bug
	# that quietly dropped the whole skyline (a reachability pruner matching surfaces
	# by identity) left the tower a bare box with the suite fully green. The floors
	# have to actually be DRAWN, and this is where that is asserted.
	var with_ledges: int = 0
	var with_two: int = 0
	var breakables: int = 0
	var counted: int = 0
	for s2: int in SEEDS:
		var t2: Resource = FloorGen.vary_tower(_tower, s2 * 17 + 101)
		for i2: int in (t2.floors as Array).size():
			if int(t2.floors[i2].floor_type) == int(FloorDef.FloorType.BOSS):
				continue   # the guardian's arena is meant to be clean
			counted += 1
			var n: int = (t2.floors[i2].layout.platforms as Array).size()
			if n >= 1:
				with_ledges += 1
			if n >= 2:
				with_two += 1
			for p: Dictionary in t2.floors[i2].layout.platforms:
				if bool(p["breakable"]):
					breakables += 1
	_expect(float(with_ledges) / float(maxi(counted, 1)) >= 0.7,
		"most non-boss floors are drawn with a skyline (%d of %d)" % [with_ledges, counted])
	_expect(float(with_two) / float(maxi(counted, 1)) >= 0.35,
		"a good share have a real skyline, not one slab (%d of %d)" % [with_two, counted])
	_expect(breakables > 0, "deeper floors draw ledges that shatter and re-form")
	_completes("different_seeds_draw_different_rooms")


# ------------------------------------------------------------------- 2 · identity
## The floor's IDENTITY is not up for redraw: its type, its depth, its guardian
## curve, its difficulty band and how much fight it is.
func _test_floor_identity_survives_the_redraw() -> void:
	var bad_type: int = 0
	var bad_depth: int = 0
	var bad_boss: int = 0
	var bad_brute: int = 0
	var bad_budget: int = 0
	var bad_wave_count: int = 0
	for s: int in SEEDS:
		var t: Resource = FloorGen.vary_tower(_tower, s * 31 + 5)
		for i: int in (t.floors as Array).size():
			var src: FloorDef = _tower.floors[i]
			var f: FloorDef = t.floors[i]
			if int(f.floor_type) != int(src.floor_type):
				bad_type += 1
			if f.depth != src.depth:
				bad_depth += 1
			if not is_equal_approx(f.boss_hp_multiplier, src.boss_hp_multiplier):
				bad_boss += 1
			if not is_equal_approx(f.brute_chance, src.brute_chance):
				bad_brute += 1
			if f.enemy_budget != src.enemy_budget:
				bad_budget += 1
			if (f.waves as Array).size() != (src.waves as Array).size():
				bad_wave_count += 1
	_expect(bad_type == 0, "floor_type never moves (%d violations)" % bad_type)
	_expect(bad_depth == 0, "depth never moves (%d violations)" % bad_depth)
	_expect(bad_boss == 0, "the guardian's depth curve never moves (%d violations)" % bad_boss)
	_expect(bad_brute == 0, "brute_chance never moves (%d violations)" % bad_brute)
	_expect(bad_budget == 0,
		"a re-rolled floor is the same amount of fight (%d budget violations)" % bad_budget)
	_expect(bad_wave_count == 0, "the wave count never moves (%d violations)" % bad_wave_count)
	_completes("floor_identity_survives_the_redraw")


## THE BACK DOOR THIS SUITE EXISTS TO KEEP SHUT. "Higher floors add modifiers, not
## HP." If anyone ever reaches for an hp_multiplier to make a generated floor harder,
## this fails.
func _test_hp_is_never_a_difficulty_dial() -> void:
	var floor_hp: int = 0
	var wave_hp: int = 0
	for s: int in SEEDS:
		var t: Resource = FloorGen.vary_tower(_tower, s * 131 + 17)
		for i: int in (t.floors as Array).size():
			var f: FloorDef = t.floors[i]
			if not is_equal_approx(f.hp_multiplier, 1.0):
				floor_hp += 1
			for w: WaveDef in f.waves:
				# < 0 is the inherit sentinel; anything >= 0 is a generated HP dial.
				if w.hp_multiplier >= 0.0:
					wave_hp += 1
	_expect(floor_hp == 0, "trash hp_multiplier stays 1.0 on every roll (%d violations)" % floor_hp)
	_expect(wave_hp == 0, "no generated wave carries an HP multiplier (%d violations)" % wave_hp)
	_completes("hp_is_never_a_difficulty_dial")


# ------------------------------------------------------------------ 3 · geometry
## ONE SCREEN, with the arithmetic read off CombatCamera rather than re-typed —
## FloorGen hardcodes 980x500 to keep combat scripts out of its compile graph, and
## this is the assertion that the hardcode cannot rot.
func _test_every_room_fits_one_screen() -> void:
	var cam: GDScript = load(CAMERA_PATH) as GDScript
	var mx: Vector2 = cam.FRAME_VIEWPORT / cam.FRAME_ZOOM_MIN - cam.FRAME_PAD
	_expect(FloorGen.MAX_ROOM.x <= mx.x and FloorGen.MAX_ROOM.y <= mx.y,
		"FloorGen.MAX_ROOM %s is inside the camera's %s" % [str(FloorGen.MAX_ROOM), str(mx)])
	var too_big: int = 0
	var too_small: int = 0
	for s: int in SEEDS:
		var t: Resource = FloorGen.vary_tower(_tower, s * 7 + 3)
		for i: int in (t.floors as Array).size():
			var sz: Vector2 = t.floors[i].layout.room_size
			if sz.x > mx.x or sz.y > mx.y:
				too_big += 1
			if sz.x < FloorGen.MIN_ROOM.x or sz.y < FloorGen.MIN_ROOM.y:
				too_small += 1
	_expect(too_big == 0, "no generated room overflows one screen (%d violations)" % too_big)
	_expect(too_small == 0, "no generated room shrinks below the arena floor (%d)" % too_small)
	_completes("every_room_fits_one_screen")


## The ledge invariants, named in FloorGen._legal_platform. The one that matters most
## is the GROUND CORRIDOR: it is what makes "walled in by cover" unrepresentable
## rather than merely unlikely.
func _test_geometry_invariants_hold() -> void:
	var outside: int = 0
	var too_wide: int = 0
	var corridor: int = 0
	var ceiling: int = 0
	var overlap: int = 0
	for s: int in SEEDS:
		var t: Resource = FloorGen.vary_tower(_tower, s * 977 + 11)
		for i: int in (t.floors as Array).size():
			var l: LayoutDef = t.floors[i].layout
			var w: float = l.room_size.x
			var ground_y: float = l.room_size.y - FloorGen.WALL_THICKNESS * 0.5
			var plats: Array = l.platforms
			for a: int in plats.size():
				var p: Dictionary = plats[a]
				var px: float = float(p["x"])
				var py: float = float(p["y"])
				var pw: float = float(p["w"])
				var ph: float = float(p["h"])
				if px - pw * 0.5 < FloorGen.WALL_THICKNESS or px + pw * 0.5 > w - FloorGen.WALL_THICKNESS:
					outside += 1
				if pw > w * 0.55:
					too_wide += 1
				if py + ph * 0.5 > ground_y - FloorGen.GROUND_CORRIDOR:
					corridor += 1
				if py - ph * 0.5 < FloorGen.CEILING_CLEARANCE:
					ceiling += 1
				for b: int in range(a + 1, plats.size()):
					var o: Dictionary = plats[b]
					var ox: float = float(o["x"])
					var oy: float = float(o["y"])
					var ow: float = float(o["w"])
					var oh: float = float(o["h"])
					if absf(px - ox) >= (pw + ow) * 0.5:
						continue
					if absf(py - oy) < (ph + oh) * 0.5:
						overlap += 1
	_expect(outside == 0, "no ledge pokes through a wall (%d violations)" % outside)
	_expect(too_wide == 0, "no ledge cuts the room in two (%d violations)" % too_wide)
	_expect(corridor == 0,
		"the ground stays a wall-to-wall runway — nobody can be sealed in (%d violations)" % corridor)
	_expect(ceiling == 0, "every ledge has headroom to stand under (%d violations)" % ceiling)
	_expect(overlap == 0, "no two ledges intersect (%d violations)" % overlap)
	_completes("geometry_invariants_hold")


## NO UNWINNABLE ROLL. Everything the floor places is drawn from the reachability
## walk, so this re-runs that walk independently and checks the results landed inside
## it — including that the exit is not on top of the hero, and that no ledge is
## stranded scenery a leaping enemy could beach itself on.
func _test_everything_placed_is_reachable() -> void:
	var exit_bad: int = 0
	var pickup_bad: int = 0
	var crate_bad: int = 0
	var ledge_bad: int = 0
	var hero_bad: int = 0
	var exit_on_hero: int = 0
	for s: int in SEEDS:
		var t: Resource = FloorGen.vary_tower(_tower, s * 613 + 29)
		for i: int in (t.floors as Array).size():
			var l: LayoutDef = t.floors[i].layout
			var w: float = l.room_size.x
			var h: float = l.room_size.y
			var ground_y: float = h - FloorGen.WALL_THICKNESS * 0.5
			var surfaces: Array = _surfaces_of(l, ground_y)
			var reach: Array = FloorGen.reachable_surfaces(surfaces)
			if reach.size() != surfaces.size():
				ledge_bad += 1
			if l.hero_start.x <= 0.0 or l.hero_start.x >= w \
					or l.hero_start.y <= 0.0 or l.hero_start.y >= h:
				hero_bad += 1
			if not _on_reachable(reach, l.exit_point, 60.0):
				exit_bad += 1
			if l.exit_point.distance_to(l.hero_start) < 120.0:
				exit_on_hero += 1
			for p: Vector2 in l.weapon_pickups:
				if not _on_reachable(reach, p, 46.0):
					pickup_bad += 1
			for c: Vector2 in l.crate_positions:
				if not _on_reachable(reach, c, 30.0):
					crate_bad += 1
				if c.x <= 0.0 or c.y <= 0.0 or c.x >= w or c.y >= h:
					crate_bad += 1
	_expect(ledge_bad == 0, "every ledge is reachable from the ground (%d floors with a stranded one)" % ledge_bad)
	_expect(hero_bad == 0, "the hero always starts inside the room (%d violations)" % hero_bad)
	_expect(exit_bad == 0, "the exit always sits on a reachable surface (%d violations)" % exit_bad)
	_expect(exit_on_hero == 0, "the exit is never on top of the spawn (%d violations)" % exit_on_hero)
	_expect(pickup_bad == 0, "every pickup sits on a reachable surface (%d violations)" % pickup_bad)
	_expect(crate_bad == 0, "every crate rests on a reachable surface, inside the room (%d)" % crate_bad)
	_completes("everything_placed_is_reachable")


# --------------------------------------------------------------------- 4 · waves
func _test_waves_conserve_and_escalate() -> void:
	var sum_bad: int = 0
	var budget_mono: int = 0
	var cap_mono: int = 0
	var empty: int = 0
	var burst_bad: int = 0
	for s: int in SEEDS:
		var t: Resource = FloorGen.vary_tower(_tower, s * 89 + 41)
		for i: int in (t.floors as Array).size():
			var src: Array = _tower.floors[i].waves
			var got: Array = t.floors[i].waves
			var want: int = 0
			for w in src:
				want += int(w.enemy_budget)
			var have: int = 0
			var prev_b: int = -1
			var prev_c: int = -1
			for w2 in got:
				have += int(w2.enemy_budget)
				if int(w2.enemy_budget) < 1:
					empty += 1
				if int(w2.enemy_budget) < prev_b:
					budget_mono += 1
				if int(w2.concurrent_cap) < prev_c:
					cap_mono += 1
				if int(w2.vanguard) > int(w2.enemy_budget):
					burst_bad += 1
				prev_b = int(w2.enemy_budget)
				prev_c = int(w2.concurrent_cap)
			if have != want:
				sum_bad += 1
	_expect(sum_bad == 0, "a redrawn floor spawns exactly as many bodies (%d violations)" % sum_bad)
	_expect(budget_mono == 0, "wave budgets never shrink across a floor (%d violations)" % budget_mono)
	_expect(cap_mono == 0, "wave pressure caps never shrink across a floor (%d violations)" % cap_mono)
	_expect(empty == 0, "every wave is a wave (%d empty ones)" % empty)
	_expect(burst_bad == 0, "an opening burst never exceeds the wave's budget (%d)" % burst_bad)
	_completes("waves_conserve_and_escalate")


## "Differently interesting, not randomly harder": an entry may be swapped for its
## CLASSMATE (chaser <-> assassin, brute <-> charger, caster <-> mage, summoner <->
## bomber) and never for a threat the wave was not authored to carry.
func _test_the_mix_stays_inside_its_threat_band() -> void:
	var out_of_band: int = 0
	var never_varied: bool = true
	for s: int in SEEDS:
		var t: Resource = FloorGen.vary_tower(_tower, s * 37 + 13)
		for i: int in (t.floors as Array).size():
			var src: Array = _tower.floors[i].waves
			var got: Array = t.floors[i].waves
			for k: int in mini(src.size(), got.size()):
				var allowed: Dictionary = {}
				for a in (src[k].archetypes as Array):
					for m: int in FloorGen.threat_class(int(a)):
						allowed[m] = true
				var authored: Array = src[k].archetypes as Array
				var rolled: Array = got[k].archetypes as Array
				if str(authored) != str(rolled):
					never_varied = false
				for a2 in rolled:
					if not allowed.has(int(a2)):
						out_of_band += 1
	_expect(out_of_band == 0,
		"no wave ever gains a threat class it was not authored to carry (%d violations)" % out_of_band)
	_expect(not never_varied, "the mix does actually get redrawn (it never varied at all)")
	_completes("the_mix_stays_inside_its_threat_band")


# ------------------------------------------------------------- 5 · the seed policy
func _test_seed_policy_cannot_desync_a_party() -> void:
	var saved: int = FloorGen.climb_seed
	# An explicitly-set seed always wins — this is the hook a host-shipped seed uses.
	FloorGen.climb_seed = 123456
	_expect(FloorGen.resolve_seed() == 123456, "an explicit climb seed is used verbatim")
	# Unset, with no co-op session: a fresh non-zero roll every time (solo variety).
	FloorGen.climb_seed = 0
	var a: int = FloorGen.resolve_seed()
	var b: int = FloorGen.resolve_seed()
	_expect(a != 0 and b != 0, "an unset seed still resolves to a usable one")
	_expect(a != b, "solo climbs re-roll (got the same seed twice)")
	# `apply` records what it used, so a roll can be replayed from a bug report.
	var t: Resource = FloorGen.apply(_tower)
	_expect(FloorGen.last_seed != 0, "apply records the seed it used")
	var again: Resource = FloorGen.vary_tower(_tower, FloorGen.last_seed)
	for i: int in (t.floors as Array).size():
		_expect(_floor_eq(t.floors[i], again.floors[i]),
			"the recorded seed replays floor %d exactly" % (i + 1))
	# ⚠ THE CO-OP BRANCH, ASSERTED RATHER THAN ASSUMED. With a live session and no
	# explicit seed, the policy MUST pin to 0 so both phones derive the same floor
	# from (tower, depth) alone. A stub standing in for the autoload proves the branch
	# is real — the alternative is trusting a code path nothing ever executes until
	# two players are in a room and the floors disagree.
	#
	# ⚠ THE REAL `Net` AUTOLOAD IS ALREADY AT /root, EVEN UNDER `--script` — a stub
	# added alongside it is simply renamed to `@Node@nn` and never found, which the
	# first cut of this test discovered by failing. So the real one is stepped aside
	# for the duration and put back afterwards. (The standing "autoloads are not
	# registered under --script" trap is about naming one as a bare IDENTIFIER inside
	# a static function, which is a compile error; the NODES exist fine.)
	var real_net: Node = root.get_node_or_null(^"Net")
	if real_net != null:
		real_net.name = "NetParkedForTest"
	var stub := _NetStub.new()
	stub.name = "Net"
	root.add_child(stub)
	FloorGen.climb_seed = 0
	_expect(FloorGen.resolve_seed() == 0, "a live co-op session pins the climb seed")
	_expect(FloorGen.resolve_seed() == 0, "...and keeps pinning it")
	# An explicit seed still wins in co-op — that is the hook for a host broadcast.
	FloorGen.climb_seed = 8675309
	_expect(FloorGen.resolve_seed() == 8675309,
		"a host-shipped seed overrides the co-op pin")
	FloorGen.climb_seed = 0
	stub.active = false
	_expect(FloorGen.resolve_seed() != 0, "a dead session goes back to rolling")
	root.remove_child(stub)
	stub.free()
	if real_net != null:
		real_net.name = "Net"
	# The seed is mixed, so adjacent floors of one climb are not near-copies.
	var s1: int = FloorGen.floor_seed("ashspire", 1, 99)
	var s2: int = FloorGen.floor_seed("ashspire", 2, 99)
	_expect(s1 != s2, "adjacent floors of the same climb draw from different streams")
	_expect(FloorGen.floor_seed("ashspire", 1, 99) == s1, "floor_seed is pure")
	FloorGen.climb_seed = saved
	_completes("seed_policy_cannot_desync_a_party")


func _test_tags_neither_grow_nor_clobber() -> void:
	var src := FloorDef.new()
	src.floor_type = FloorDef.FloorType.COMBAT
	src.depth = 3
	src.layout = LayoutDef.new()
	src.theme = EnvTheme.new()
	src.special_tags = ["boss:illuminator", "mod:mirrored", "no_mods"]
	var once: FloorDef = FloorGen.vary_floor(src, 3, "ashspire", 77)
	var twice: FloorDef = FloorGen.vary_floor(once, 3, "ashspire", 77)
	for pin: String in ["boss:illuminator", "mod:mirrored", "no_mods"]:
		_expect(once.special_tags.has(pin), "the authored pin %s survives the redraw" % pin)
		_expect(twice.special_tags.has(pin), "the authored pin %s survives a SECOND redraw" % pin)
	_expect(once.special_tags.size() == twice.special_tags.size(),
		"re-applying does not grow special_tags (%d -> %d)"
			% [once.special_tags.size(), twice.special_tags.size()])
	var shapes: int = 0
	for t: String in twice.special_tags:
		if t.begins_with(FloorGen.TAG_SHAPE):
			shapes += 1
	_expect(shapes == 1, "exactly one shape tag is stamped (got %d)" % shapes)
	# The input resource is never written through — `_load_or_build_tower` can hand us
	# a CACHED .tres, and mutating that would corrupt the tower for the whole process.
	_expect(src.special_tags.size() == 3, "the source floor's tags were not mutated")
	_expect(src.layout.platforms.is_empty(), "the source layout was not mutated")
	_completes("tags_neither_grow_nor_clobber")


# ------------------------------------------------------------------ 6 · the build
## The generated skyline becomes real bodies. FloorBuilder is reached BY PATH (its
## dependency chain touches autoloads that a `--script` harness does not have).
func _test_the_builder_raises_the_skyline() -> void:
	var builder: GDScript = load(BUILDER_PATH) as GDScript
	var room := Node2D.new()
	root.add_child(room)
	var l := LayoutDef.new()
	l.platforms = [
		{"x": 300.0, "y": 320.0, "w": 180.0, "h": 24.0, "breakable": false},
		{"x": 640.0, "y": 240.0, "w": 150.0, "h": 24.0, "breakable": true},
	]
	builder.call("build_platforms", room, l)
	var bodies: Array = []
	for c: Node in room.get_children():
		if c is StaticBody2D:
			bodies.append(c)
	_expect(bodies.size() == 2, "both ledges were raised (got %d)" % bodies.size())
	if bodies.size() != 2:
		room.free()
		return   # deliberately NOT completed: the missing sentinel fails the suite
	_expect((bodies[0] as Node2D).global_position.is_equal_approx(Vector2(300.0, 320.0)),
		"the permanent ledge stands where the layout put it")
	_expect(Vector2(bodies[0].get("platform_size")).is_equal_approx(Vector2(180.0, 24.0)),
		"the ledge is the size the layout asked for")
	# THE TWO LEDGE KINDS ARE GENUINELY DIFFERENT, and the difference is deliberate:
	# a RuinPlatform is permanent architecture and joins NO damage group (spells pass
	# through it, melee cannot chew it), while a BreakablePlatform joins
	# "destructible" + "breakable_platform" and sits on collision layer 5, so spells
	# stop on it and eventually shatter it — and then it re-forms.
	#
	# ⚠ THE GROUP HALF OF THAT STANDS; THE "SPELLS PASS THROUGH IT" HALF NO LONGER DOES.
	# Maker: *"please make the floating platforms destroyable into bits just like the
	# floor was beforehand as well"*. BOTH kinds now hang a `DestructibleStage` chunk
	# grid on themselves and lose chunks where they are hit. What separates them is
	# unchanged and is still exactly what the groups say: an amber BreakablePlatform can
	# be REMOVED FROM THE WORLD, a stone RuinPlatform can only be holed and knits back.
	# A RuinPlatform still must NOT join `"destructible"` — `SpellWorld.is_smashable`
	# would then blind every floor query in the game to it — so it is reached by
	# `BODY_META` / `carve_from_body` alone. See both scripts' headers.
	_expect(not bodies[0].is_in_group("destructible"),
		"the permanent ledge is permanent (it is not in the damage contract)")
	_expect(bodies[1].is_in_group("destructible"),
		"the breakable ledge takes damage like every other prop")
	_expect(bodies[1].is_in_group("breakable_platform"),
		"the breakable ledge is the breakable one (it shatters and re-forms)")
	_expect(not bodies[0].is_in_group("breakable_platform"),
		"the permanent ledge is NOT breakable")
	# The collider is built in _ready from platform_size, so setting the size after
	# add_child would leave a mismatched shape — this is that ordering, asserted.
	#
	# ⚠ IT IS NO LONGER ONE BOX OF EXACTLY `platform_size`, AND THAT IS THE CARVE.
	# The old assertion read `size.is_equal_approx(Vector2(150, 24))` against the single
	# `RectangleShape2D` the ledge used to build. A ledge's collision is now whatever its
	# chunk grid merges to — one rectangle per block while it is whole, more once it has
	# holes in it — each grown sideways by `SEAM_OVERLAP_X` and down by `seam_grow_down`
	# to kill seams. So an exact-size test would now be asserting the seam constants, not
	# the ordering it was written for.
	#
	# What it was ACTUALLY written for survives intact and is what is asserted instead:
	# a ledge whose `platform_size` had been set after `add_child` would have built its
	# grid from the 190x24 DEFAULT, so its span would read ~190 and its top edge would
	# sit at -12 of the wrong slab. Span-and-top-edge catches that; it also catches the
	# invariant that actually hurts if it slips, which the exact-size test never did —
	# THE WALKING SURFACE MUST LAND EXACTLY ON THE SLAB'S TOP EDGE
	# ([[feedback_rig_feet_vs_collider]]).
	var left: float = INF
	var right: float = -INF
	var top: float = INF
	var shapes: int = 0
	for c2: Node in bodies[1].get_children():
		var cs: CollisionShape2D = c2 as CollisionShape2D
		if cs == null:
			continue
		var rr: RectangleShape2D = cs.shape as RectangleShape2D
		if rr == null:
			continue
		shapes += 1
		left = minf(left, cs.position.x - rr.size.x * 0.5)
		right = maxf(right, cs.position.x + rr.size.x * 0.5)
		top = minf(top, cs.position.y - rr.size.y * 0.5)
	_expect(shapes > 0, "the ledge built no rectangle collider at all")
	if shapes > 0:
		# 150 authored, +4 seam (SEAM_OVERLAP_X on each end), +up to CHUNK (4) because
		# the grid's origin is SNAPPED DOWN to a chunk multiple and its cells are
		# CENTRE-SAMPLED — a 150 px slab from -75 lands on a 152 px grid. Measured: 156.
		# A range, not a point: what this is catching is a ledge built from the 190x24
		# DEFAULT because the size was set after `add_child`, which reads ~194 and is
		# nowhere near this band.
		var span: float = right - left
		_expect(span >= 150.0 and span <= 158.0,
			"the collider spans %.2f px, the layout authored 150 (expect 150-158 after"
				% span + " seam + chunk snap) — the size was set AFTER add_child and the"
			+ " grid used the 190 px default")
		_expect(absf(top - (-12.0)) < 0.001,
			"the walking surface is at local y %.3f, the authored 24 px slab says -12"
				% top)
	room.free()
	_completes("the_builder_raises_the_skyline")


## THE TIER 2 DROP HAS TO BE COLLECTABLE. `SpellDrops.DROP_ANCHOR` is a fraction of
## the room, which puts it hundreds of pixels above the floor — visible, and out of
## reach of a 112px jump. FloorBuilder settles it onto whatever is underneath; this
## checks the settled point lands on a surface the reachability walk reached, on
## every roll of every floor.
func _test_spell_drops_land_where_they_can_be_picked_up() -> void:
	var builder: GDScript = load(BUILDER_PATH) as GDScript
	var drops: GDScript = load("res://scripts/combat/SpellDrops.gd") as GDScript
	var bad: int = 0
	var floated: int = 0
	for s: int in SEEDS:
		var t: Resource = FloorGen.vary_tower(_tower, s * 251 + 7)
		for i: int in (t.floors as Array).size():
			var l: LayoutDef = t.floors[i].layout
			var ground_y: float = l.room_size.y - FloorGen.WALL_THICKNESS * 0.5
			var reach: Array = FloorGen.reachable_surfaces(_surfaces_of(l, ground_y))
			for frac: Vector2 in [drops.DROP_ANCHOR, drops.BOSS_ANCHOR]:
				var raw := Vector2(l.room_size.x * frac.x, l.room_size.y * frac.y)
				if raw.y < ground_y - 120.0:
					floated += 1   # this anchor really was hanging in mid-air
				var pt: Vector2 = builder.call("settle_onto_surface", l, raw)
				if not _on_reachable(reach, pt, 40.0):
					bad += 1
	_expect(bad == 0, "every spell drop settles onto a reachable surface (%d violations)" % bad)
	_expect(floated > 0,
		"the raw anchors really were hanging in mid-air (so the settle is doing work)")
	_completes("spell_drops_land_where_they_can_be_picked_up")


# ------------------------------------------------------------------- comparators
## Field-by-field floor comparison. Deliberately explicit rather than leaning on
## `==` over Resources (which compares identity) or over Dictionaries (whose
## semantics have moved between engine versions).
func _floor_eq(a: FloorDef, b: FloorDef) -> bool:
	if int(a.floor_type) != int(b.floor_type):
		return false
	if a.depth != b.depth or a.enemy_budget != b.enemy_budget \
			or a.concurrent_cap != b.concurrent_cap:
		return false
	if not is_equal_approx(a.hp_multiplier, b.hp_multiplier) \
			or not is_equal_approx(a.boss_hp_multiplier, b.boss_hp_multiplier) \
			or not is_equal_approx(a.brute_chance, b.brute_chance):
		return false
	if str(a.special_tags) != str(b.special_tags):
		return false
	if not _theme_eq(a.theme, b.theme):
		return false
	if not _layout_eq(a.layout, b.layout):
		return false
	if (a.waves as Array).size() != (b.waves as Array).size():
		return false
	for i: int in (a.waves as Array).size():
		if not _wave_eq(a.waves[i], b.waves[i]):
			return false
	return true


func _theme_eq(a: EnvTheme, b: EnvTheme) -> bool:
	if a == null or b == null:
		return a == b
	return a.name == b.name and a.wash_tint.is_equal_approx(b.wash_tint)


func _layout_eq(a: LayoutDef, b: LayoutDef) -> bool:
	if a == null or b == null:
		return a == b
	if not a.room_size.is_equal_approx(b.room_size):
		return false
	if not a.hero_start.is_equal_approx(b.hero_start) \
			or not a.exit_point.is_equal_approx(b.exit_point):
		return false
	if not a.spawn_rect_min.is_equal_approx(b.spawn_rect_min) \
			or not a.spawn_rect_max.is_equal_approx(b.spawn_rect_max):
		return false
	if not is_equal_approx(a.min_spawn_dist_from_hero, b.min_spawn_dist_from_hero):
		return false
	if str(a.crate_positions) != str(b.crate_positions):
		return false
	if str(a.weapon_pickups) != str(b.weapon_pickups):
		return false
	if (a.platforms as Array).size() != (b.platforms as Array).size():
		return false
	for i: int in (a.platforms as Array).size():
		var pa: Dictionary = a.platforms[i]
		var pb: Dictionary = b.platforms[i]
		for k: String in ["x", "y", "w", "h"]:
			if not is_equal_approx(float(pa[k]), float(pb[k])):
				return false
		if bool(pa["breakable"]) != bool(pb["breakable"]):
			return false
	return true


func _wave_eq(a: WaveDef, b: WaveDef) -> bool:
	return a.enemy_budget == b.enemy_budget and a.concurrent_cap == b.concurrent_cap \
		and is_equal_approx(a.brute_chance, b.brute_chance) \
		and is_equal_approx(a.hp_multiplier, b.hp_multiplier) \
		and is_equal_approx(a.spawn_interval, b.spawn_interval) \
		and a.vanguard == b.vanguard and a.handoff_alive == b.handoff_alive \
		and a.elite_wave == b.elite_wave \
		and str(a.archetypes) == str(b.archetypes)


## Rebuild the surface list the way FloorGen does, independently of it, so the
## reachability assertion is a second opinion rather than an echo.
func _surfaces_of(l: LayoutDef, ground_y: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{
		"y": ground_y,
		"x0": FloorGen.WALL_THICKNESS,
		"x1": l.room_size.x - FloorGen.WALL_THICKNESS,
		"ground": true,
	}]
	for p: Dictionary in l.platforms:
		out.append({
			"y": float(p["y"]) - float(p["h"]) * 0.5,
			"x0": float(p["x"]) - float(p["w"]) * 0.5,
			"x1": float(p["x"]) + float(p["w"]) * 0.5,
			"ground": false,
		})
	return out


## Stands in for the `Net` autoload, which a `--script` harness does not have.
class _NetStub extends Node:
	var active: bool = true

	func is_active() -> bool:
		return active


## Does `pt` sit on (just above) one of the reachable surfaces?
func _on_reachable(reach: Array, pt: Vector2, drop: float) -> bool:
	for s in reach:
		var sy: float = float(s["y"])
		if pt.x < float(s["x0"]) - 4.0 or pt.x > float(s["x1"]) + 4.0:
			continue
		if pt.y <= sy + 2.0 and pt.y >= sy - drop - 2.0:
			return true
	return false
