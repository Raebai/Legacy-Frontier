# Run: godot --headless --path godot-project --script tools/slice_test_elites.gd
#
# ELITE ENEMIES — the boss-modifier rider pattern applied to ordinary trash.
#
# What this suite is actually defending, in order of how expensive the bug would be:
#
#   1. **ELITES ACTUALLY APPEAR.** An invariant that is trivially true of an empty
#      result is not an invariant. This repo has already shipped a floor-geometry
#      suite that stayed green through three bugs which deleted the entire ledge
#      skyline, because "every ledge is legal" holds vacuously when there are no
#      ledges. So the first thing asserted here is an OCCURRENCE RATE: a floor at
#      depth d produces exactly `EliteRoster.budget(d)` elites, floor 1 produces
#      none, and the spend is checked over hundreds of rolls rather than one.
#   2. **NO AFFIX IS AN HP BUFF IN A COSTUME.** Trash `hp_multiplier` is pinned at
#      1.0 across the tower and `slice_test_floorgen` fails the build if a generated
#      floor carries one. An affix that wrote `max_hp` would be that rule's back
#      door, so `_test_no_affix_ever_writes_hp` READS THE SOURCE of every rider and
#      fails on a write. Reads are legal (VOLATILE needs the hp fraction for its
#      fizz); writes are not.
#   3. **CO-OP DETERMINISM.** The roll happens once on the host and the ids travel in
#      the spawn dictionary, exactly like BossRoster. Two Encounters handed the same
#      dictionary must build the same body — that is what `slice_test_coop` locks
#      about `build_enemy_from_data`, and this suite re-checks it with affixes on.
#   4. **THE 25-ENTITY CAP.** No affix may spawn a body.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──────────
# Failures accumulate on the MEMBER `_fails` and each test records a COMPLETION
# SENTINEL, so a test aborted half-way by a moved member fails the suite BY ABSENCE
# rather than reading as "found zero failures".
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const RIDER_DIR: String = "res://scripts/combat/elitemods/"
const GS_PATH: String = "res://scripts/GameState.gd"

## Field WRITES that would make an affix an HP buff. Reads (`enemy.get("hp")`) are
## deliberately absent from this list — VOLATILE has to know how close to death it is.
const HP_WRITE_PATTERNS: Array[String] = [
	'set("hp"', 'set(&"hp"', 'set("max_hp"', 'set(&"max_hp"',
	".hp =", ".hp +=", ".hp -=", ".max_hp =", ".max_hp +=", ".max_hp *=",
	"hp_multiplier", "damage_mult",
]

const TESTS: Array[String] = [
	"registry_is_well_formed",
	"no_affix_ever_writes_hp",
	"budget_curve_and_floor_one_is_clean",
	"roll_is_pure_and_varies",
	"excludes_are_respected",
	"a_floor_spends_its_elite_budget_exactly",
	"an_elite_wave_takes_the_whole_budget",
	"spawn_data_carries_the_affixes",
	"attach_dresses_an_elite_and_leaves_trash_bare",
	"an_elite_casts_a_spell_no_class_carries",
	"peers_build_the_same_elite_from_the_same_dict",
	"quickened_is_faster_not_tougher",
	"inked_refuses_to_be_shoved",
	"keen_unlocks_the_dodge_reflexes",
	"herald_lifts_then_restores_the_room",
	"volatile_bursts_on_death_and_not_on_teardown",
	"smudged_marks_then_moves",
	"no_affix_ever_spawns_a_body",
	"floor_affixes_ship_off_and_wire_up_when_on",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _arena: Node2D = null
var _hero: Node2D = null


func _initialize() -> void:
	_run()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _settle(n: int = 3) -> void:
	for i: int in n:
		await process_frame


## Bodies are ANNOUNCED before they exist: `Encounter.spawn()` draws a mark and the
## body lands `SPAWN_TELL_LEAD` later (see scripts/combat/SpawnTell.gd). A headless
## `process_frame` carries a delta of microseconds, so WAITING for that lead would
## take thousands of frames — the lead is handed to the encounter directly instead.
## Call this after any direct `spawn()` poke whose BODY the assertions need.
func _land(enc: Node) -> void:
	if enc.has_method("pending_spawn_count"):
		enc.call("_tick_spawn_tells", float(enc.get("SPAWN_TELL_LEAD")) + 0.01)


func _run() -> void:
	_arena = Node2D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_hero = _HeroStub.new()
	_hero.add_to_group("hero")
	_arena.add_child(_hero)
	_hero.global_position = Vector2(500.0, 300.0)
	await process_frame

	_test_registry_is_well_formed()
	_test_no_affix_ever_writes_hp()
	_test_budget_curve_and_floor_one_is_clean()
	_test_roll_is_pure_and_varies()
	_test_excludes_are_respected()
	_test_a_floor_spends_its_elite_budget_exactly()
	_test_an_elite_wave_takes_the_whole_budget()
	await _test_spawn_data_carries_the_affixes()
	await _test_attach_dresses_an_elite_and_leaves_trash_bare()
	await _test_an_elite_casts_a_spell_no_class_carries()
	_test_peers_build_the_same_elite_from_the_same_dict()
	await _test_quickened_is_faster_not_tougher()
	await _test_inked_refuses_to_be_shoved()
	await _test_keen_unlocks_the_dodge_reflexes()
	await _test_herald_lifts_then_restores_the_room()
	await _test_volatile_bursts_on_death_and_not_on_teardown()
	await _test_smudged_marks_then_moves()
	await _test_no_affix_ever_spawns_a_body()
	await _test_floor_affixes_ship_off_and_wire_up_when_on()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Elite tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Elite tests: all PASS")
		quit(0)


# ------------------------------------------------------------------- utilities
func _enc() -> Node:
	return load(ENCOUNTER_PATH).new()


## Build a trash body the way the game does: through Encounter's single construction
## path, from a spawn dictionary. That is the function co-op replicates, so testing
## through it is testing the real thing.
func _build(arch: int, elite: Array = [], aff: Array = []) -> Node:
	var enc: Node = _enc()
	var data: Dictionary = {
		"boss": false, "arch": arch, "hp": 40, "spd": 95.0, "touch": 10,
		"tint": Color(0.9, 0.35, 0.3, 1), "tele": false, "x": 700.0, "y": 300.0,
	}
	if not elite.is_empty():
		data["elite"] = elite
	if not aff.is_empty():
		data["aff"] = aff
	var e: Node = enc.build_enemy_from_data(data)
	enc.free()
	_arena.add_child(e)
	return e


## ⚠ UNTYPED ON PURPOSE. A typed `Node` parameter raises "previously freed instance"
## on the assignment itself when a test double-kills something — and in GDScript a
## runtime error ABORTS THE ENCLOSING FUNCTION, so the sentinel never gets recorded
## and the failure reads as an unrelated "test did not complete".
func _kill(n: Variant) -> void:
	if n != null and is_instance_valid(n) and n is Node:
		(n as Node).queue_free()


func _floor(depth: int, budget: int, tags: Array[String] = []) -> Resource:
	var f := FloorDef.new()
	f.floor_type = FloorDef.FloorType.COMBAT
	f.depth = depth
	f.special_tags = tags
	var w := WaveDef.new()
	w.enemy_budget = budget
	w.concurrent_cap = 4
	f.waves = [w] as Array[WaveDef]
	f.enemy_budget = budget
	return f


# ---------------------------------------------------------------- 1 · the table
func _test_registry_is_well_formed() -> void:
	var seen: Dictionary = {}
	for r: Dictionary in EliteModifier.REGISTRY:
		var id: String = String(r["id"])
		_expect(not seen.has(id), "affix id '%s' appears once" % id)
		seen[id] = true
		_expect(String(r["name"]) != "", "affix '%s' has a display name" % id)
		_expect(String(r["blurb"]) != "", "affix '%s' has a blurb (the floor card reads it)" % id)
		_expect(int(r["min_floor"]) >= 1, "affix '%s' has a sane min_floor" % id)
		var path: String = EliteModifier.rider_path(id)
		_expect(FileAccess.file_exists(path), "affix '%s' rider exists at %s" % [id, path])
		var src: String = _read(path)
		_expect(src.contains("extends EliteRider"),
			"affix '%s' rider extends EliteRider (so setup is deferred + authority-gated)" % id)
	_expect(EliteModifier.all_ids().size() == EliteModifier.REGISTRY.size(),
		"all_ids() covers the registry")
	# The two hardcoded floor-affix pools must agree. FloorGen keeps its own copy on
	# purpose (it must drag no combat script into a headless compile graph), and a
	# silent divergence would mean the generator stamping an affix the roster does
	# not consider floor-legal.
	_expect(str(FloorGen.FLOOR_AFFIX_POOL) == str(EliteRoster.FLOOR_AFFIX_POOL),
		"FloorGen and EliteRoster agree on the floor-affix pool (%s vs %s)"
			% [str(FloorGen.FLOOR_AFFIX_POOL), str(EliteRoster.FLOOR_AFFIX_POOL)])
	for fid: String in EliteRoster.FLOOR_AFFIX_POOL:
		_expect(EliteModifier.has(fid), "floor-affix pool entry '%s' is a real affix" % fid)
	_completes("registry_is_well_formed")


## THE HP BACK DOOR, closed. See the header block.
func _test_no_affix_ever_writes_hp() -> void:
	var files: Array[String] = _rider_files()
	_expect(files.size() >= EliteModifier.REGISTRY.size(),
		"the rider directory was actually read (%d files for %d affixes)"
			% [files.size(), EliteModifier.REGISTRY.size()])
	var offenders: Array[String] = []
	for f: String in files:
		var src: String = _read(RIDER_DIR + f)
		_expect(src != "", "rider %s is readable (an empty read would pass vacuously)" % f)
		for p: String in HP_WRITE_PATTERNS:
			if src.contains(p):
				offenders.append("%s writes hp via `%s`" % [f, p])
	_expect(offenders.is_empty(),
		"no elite affix touches hp — difficulty is behaviour, never a bigger number (%s)"
			% str(offenders))
	_completes("no_affix_ever_writes_hp")


func _test_budget_curve_and_floor_one_is_clean() -> void:
	_expect(EliteRoster.budget(1) == 0,
		"floor 1 has NO elites — the tower teaches the eight archetypes before it edits them")
	_expect(EliteRoster.budget(2) == 1, "floor 2 gets one elite")
	_expect(EliteRoster.budget(3) == 1, "floor 3 gets one elite")
	_expect(EliteRoster.budget(4) == EliteRoster.MAX_PER_FLOOR, "floor 4 reaches the ceiling")
	for d: int in range(1, 40):
		_expect(EliteRoster.budget(d) <= EliteRoster.MAX_PER_FLOOR,
			"depth %d never exceeds the per-floor ceiling" % d)
		_expect(EliteRoster.budget(d) >= EliteRoster.budget(maxi(d - 1, 1)),
			"the elite budget never goes back down (depth %d)" % d)
	_expect(EliteRoster.affix_count(1) == 1, "a shallow elite carries ONE word over its head")
	_expect(EliteRoster.affix_count(9) == 2, "a deep elite may carry two")
	# Depth escalates the POOL as well as the count.
	_expect(EliteModifier.eligible_ids(1).is_empty()
			or EliteModifier.eligible_ids(1).size() < EliteModifier.eligible_ids(9).size(),
		"deeper floors can draw from more of the registry")
	_completes("budget_curve_and_floor_one_is_clean")


func _test_roll_is_pure_and_varies() -> void:
	# PURE: the whole co-op story rests on this one property.
	for s: int in range(0, 60):
		var a: Dictionary = EliteRoster.roll(5, s * 7919 + 13, 1)
		var b: Dictionary = EliteRoster.roll(5, s * 7919 + 13, 1)
		_expect(str(a["affixes"]) == str(b["affixes"]),
			"roll(5, %d, BRUTE) is pure" % (s * 7919 + 13))
	# ...and it is not a constant dressed up as a roll.
	var seen: Dictionary = {}
	for s2: int in range(0, 400):
		var r: Dictionary = EliteRoster.roll(6, s2 * 31 + 5, 0)
		seen[str(r["affixes"])] = true
		var got: Array = r["affixes"]
		_expect(got.size() == EliteRoster.affix_count(6),
			"a depth-6 elite carries exactly %d affixes" % EliteRoster.affix_count(6))
		var dupe: Dictionary = {}
		for a2 in got:
			_expect(not dupe.has(String(a2)), "an elite never carries the same affix twice")
			dupe[String(a2)] = true
	_expect(seen.size() >= 3,
		"the roll produces genuinely different elites (%d distinct combinations)" % seen.size())
	# Shallow depth cannot draw the deep words.
	for s3: int in range(0, 200):
		for a3 in (EliteRoster.roll(2, s3 * 17 + 3, 0)["affixes"] as Array):
			_expect(int(EliteModifier.row(String(a3))["min_floor"]) <= 2,
				"a floor-2 elite never draws a deeper affix ('%s')" % String(a3))
	_completes("roll_is_pure_and_varies")


func _test_excludes_are_respected() -> void:
	var hit: int = 0
	for aid in EliteRoster.EXCLUDES:
		var banned: Array = EliteRoster.EXCLUDES[aid]
		for arch in banned:
			var a: int = int(arch)
			_expect(not EliteRoster.eligible(20, a).has(String(aid)),
				"'%s' is never eligible on archetype %d" % [String(aid), a])
			for s: int in range(0, 120):
				var got: Array = EliteRoster.roll(20, s * 101 + 7, a)["affixes"]
				if got.has(String(aid)):
					_expect(false, "'%s' was rolled onto archetype %d" % [String(aid), a])
				hit += 1
	_expect(hit > 0, "the exclusion table was actually walked (it is not empty)")
	_completes("excludes_are_respected")


# ------------------------------------------------------- 2 · elites APPEAR
## THE OCCURRENCE ASSERTION. A floor's elite budget is not a chance, it is a spend
## with remaining-over-remaining pressure, so it lands EXACTLY — which is the only
## reason this can be an equality rather than a hopeful ">= 0".
func _test_a_floor_spends_its_elite_budget_exactly() -> void:
	for depth: int in [1, 2, 3, 4, 5, 7]:
		var want: int = EliteRoster.budget(depth)
		var totals: Array[int] = []
		for trial: int in 40:
			var enc: Node = _enc()
			_arena.add_child(enc)
			enc.run_floor(_floor(depth, 30))
			enc.stop()
			# Walk the floor's whole spawn list through the REAL roll, so what is
			# measured is production code and not a re-implementation of it.
			for i: int in 30:
				enc.call("_roll_elite", i % 8)
				enc.set("_floor_spawned", i + 1)
			totals.append((enc.call("elite_log") as Array).size())
			enc.queue_free()
		var lo: int = totals[0]
		var hi: int = totals[0]
		for t: int in totals:
			lo = mini(lo, t)
			hi = maxi(hi, t)
		_expect(lo == want and hi == want,
			"depth %d produces exactly %d elite(s) on every roll (saw %d..%d)"
				% [depth, want, lo, hi])
	# ...and an authored opt-out still works.
	var enc2: Node = _enc()
	_arena.add_child(enc2)
	enc2.run_floor(_floor(6, 20, ["no_elites"] as Array[String]))
	enc2.stop()
	_expect(int(enc2.call("elites_remaining")) == 0, "`no_elites` pins a floor clean")
	enc2.queue_free()
	_completes("a_floor_spends_its_elite_budget_exactly")


func _test_spawn_data_carries_the_affixes() -> void:
	# End-to-end through the real spawn path: run a floor, force its whole budget onto
	# the next body, and check a live elite comes out with a rider on it.
	var enc: Node = _enc()
	_arena.add_child(enc)
	enc.run_floor(_floor(6, 4))
	enc.stop()
	enc.set("_floor_spawned", 3)     # last body of the floor: the spend is certain
	enc.set("_elite_left", 1)
	enc.call("spawn", 0.3, 1.0, [1] as Array[int])
	_land(enc)
	await _settle(2)
	var elites: Array = []
	for c: Node in _arena.get_children():
		if c.is_in_group("enemy") and c.has_node(^"EliteMark"):
			elites.append(c)
	_expect(elites.size() == 1, "the forced spend produced exactly one dressed elite (%d)" % elites.size())
	if elites.size() == 1:
		var log: Array = enc.call("elite_log")
		_expect(log.size() == 1, "the elite is recorded in the floor's log")
		for aid in (log[0]["affixes"] as Array):
			_expect(elites[0].has_node(NodePath("Elite_" + String(aid))),
				"rider Elite_%s is on the body" % String(aid))
	for e in elites:
		_kill(e)
	for c2: Node in _arena.get_children():
		if c2.is_in_group("enemy"):
			_kill(c2)
	enc.queue_free()
	await _settle(2)
	_completes("spawn_data_carries_the_affixes")


func _test_attach_dresses_an_elite_and_leaves_trash_bare() -> void:
	var plain: Node = _build(0)
	var elite: Node = _build(0, [EliteModifier.INKED])
	var affixed: Node = _build(0, [], [EliteModifier.INKED])
	await _settle(3)

	var plain_rig: Node = plain.get_node_or_null(^"Rig")
	var elite_rig: Node = elite.get_node_or_null(^"Rig")
	_expect(plain_rig != null and elite_rig != null, "both bodies have rigs")
	if plain_rig != null and elite_rig != null:
		# THE READ. Enemies are documented "bare sticks" — strength 0, always — so the
		# aura is what makes an elite the only glowing body in the room.
		_expect(float(plain_rig.get("aura_strength")) == 0.0, "ordinary trash stays a bare stick")
		_expect(float(elite_rig.get("aura_strength")) > 0.0, "an elite glows")
		_expect(int(elite_rig.get("aura_tier")) >= 3,
			"the elite aura reaches the ground-ring tier (readable behind cover)")
		_expect(float(elite_rig.get("height")) > float(plain_rig.get("height")),
			"an elite has a bigger silhouette — and therefore a bigger hurtbox")
	_expect(elite.has_node(^"EliteMark"), "an elite carries the word over its head")
	_expect(not plain.has_node(^"EliteMark"), "ordinary trash carries no word")
	# A FLOOR AFFIX is the same rider with NO dressing: sixteen glowing sticks is a
	# light show, not a read.
	_expect(affixed.has_node(NodePath("Elite_" + EliteModifier.INKED)),
		"a floor affix attaches its rider")
	_expect(not affixed.has_node(^"EliteMark"), "a floor affix dresses nobody")
	_kill(plain)
	_kill(elite)
	_kill(affixed)
	await _settle(2)
	_completes("attach_dresses_an_elite_and_leaves_trash_bare")


## ══ AN ELITE CASTS SOMETHING YOU HAVE NEVER HELD ═══════════════════
## Maker, watching the bot fights: *"I see all these cool classes spells and
## interactions and spells please ensure the main game has all of these"*, and, put to
## them as a fork, they chose to arm the ELITES and the guardians rather than every mob
## — so the spectacle is a spike you remember and not constant noise.
##
## Three properties, and the second is the one worth having:
##   1. an elite casts the ELITE row, ordinary trash of the same archetype does not;
##   2. the spell is an ORPHAN — in `SpellLibrary.unequipped_ids()`, i.e. authored,
##      tuned, carried by no class and (since the tower stopped dropping spells) never
##      cast by anything in the game. An elite throwing your own kit back at you is
##      `ModMirrored`'s job and having two of those makes neither mean anything;
##   3. the DAMAGE is this file's, not the library's. Library numbers are authored for
##      a hero's power budget and `colossus_pillar` is 96 against a roster whose
##      biggest hit is 22 — borrowing the id must never mean borrowing the number.
func _test_an_elite_casts_a_spell_no_class_carries() -> void:
	var script: GDScript = load("res://scripts/combat/Enemy.gd") as GDScript
	var elite_rows: Dictionary = script.get("ELITE_SPELLS")
	var plain_rows: Dictionary = script.get("ARCHETYPE_SPELLS")
	_expect(elite_rows.size() >= 5,
		"there are elite spell rows to test (%d)" % elite_rows.size())
	# Every id any class actually carries, so the orphan claim is checked against the
	# real kits rather than against a list somebody typed twice.
	var carried: Array = []
	for cls: int in SpellLibrary.CLASS_KITS.size():
		for s: SpellDef in SpellLibrary.build_for_class(cls):
			carried.append(s.id)
	var orphans: Array = SpellLibrary.unequipped_ids()
	var checked: int = 0
	for key: Variant in elite_rows:
		var arch: int = int(key)
		var row: Dictionary = elite_rows[key]
		var id: String = String(row["id"])
		_expect(orphans.has(id),
			"archetype %d's elite spell `%s` is an orphan — if it has been given to a"
				% [arch, id]
			+ " class since, an elite now casts that class's spell back at the player,"
			+ " which is a different feature that already exists (ModMirrored)")
		_expect(not carried.has(id),
			"...and no class STARTS with `%s`" % id)
		var lib: SpellDef = SpellLibrary.by_id(id)
		_expect(lib != null, "`%s` is really in the library" % id)
		if lib == null:
			continue
		_expect(int(row["dmg"]) < lib.damage,
			"`%s` is re-tuned DOWN for an enemy (%d, library says %d). A borrowed id"
				% [id, int(row["dmg"]), lib.damage]
			+ " must not bring a hero's damage number with it.")
		# ...and it is announced for longer than the light one, because it is heavier.
		var plain: Dictionary = plain_rows.get(key, {})
		if not plain.is_empty():
			# ...and UP from the trash beside it. This is the half that says the elite
			# row is an upgrade rather than merely a different id: bounded above by the
			# library and below by the ordinary mob, so it can be neither a hero number
			# nor a sidegrade. The first version of this test only checked the upper
			# bound and passed `void_barrage` at exactly the library value.
			_expect(int(row["dmg"]) > int(plain["dmg"]),
				"archetype %d's elite spell hits harder than its ordinary one (%d vs %d)"
					% [arch, int(row["dmg"]), int(plain["dmg"])])
			_expect(float(row["windup"]) >= float(plain["windup"]),
				"archetype %d's elite spell has at least the ordinary windup (%.2f vs %.2f)"
					% [arch, float(row["windup"]), float(plain["windup"])])
			_expect(float(row["cd"]) >= float(plain["cd"]),
				"...and comes round no faster (%.1f vs %.1f)"
					% [float(row["cd"]), float(plain["cd"])])
		# ══ THE LIVE BODIES ═══════════════════════════════════════════════════
		var trash: Node = _build(arch)
		var elite: Node = _build(arch, [EliteModifier.INKED])
		await _settle(3)
		_expect(String((trash.call("spell_row") as Dictionary).get("id", ""))
				== String(plain.get("id", "")),
			"ordinary archetype %d still casts its own spell" % arch)
		_expect(String((elite.call("spell_row") as Dictionary).get("id", "")) == id,
			"an elite archetype %d casts `%s`" % [arch, id])
		var built: SpellDef = elite.call("archetype_spell") as SpellDef
		_expect(built != null and built.id == id,
			"...and the SpellDef it builds is that spell")
		if built != null:
			_expect(built.damage == int(row["dmg"]),
				"...carrying THIS table's damage (%d), not the library's (%d)"
					% [built.damage, lib.damage])
		checked += 1
		_kill(trash)
		_kill(elite)
		await _settle(2)
	_expect(checked >= 5,
		"every elite row was exercised against a live body (%d)" % checked)
	_completes("an_elite_casts_a_spell_no_class_carries")


## CO-OP. `build_enemy_from_data` runs on every peer from a replicated dictionary and
## must produce the same body. Two independent Encounters stand in for two phones.
func _test_peers_build_the_same_elite_from_the_same_dict() -> void:
	var data: Dictionary = {
		"boss": false, "arch": 1, "hp": 70, "spd": 62.0, "touch": 18,
		"tint": Color(0.7, 0.25, 0.45, 1), "tele": true, "x": 400.0, "y": 200.0,
		"elite": [EliteModifier.KEEN, EliteModifier.INKED],
	}
	var host_enc: Node = _enc()
	var peer_enc: Node = _enc()
	var a: Node = host_enc.build_enemy_from_data(data)
	var b: Node = peer_enc.build_enemy_from_data(data)
	var names_a: Array[String] = []
	var names_b: Array[String] = []
	for c: Node in a.get_children():
		names_a.append(c.name)
	for c2: Node in b.get_children():
		names_b.append(c2.name)
	_expect(str(names_a) == str(names_b),
		"both peers build the same child set (%s vs %s)" % [str(names_a), str(names_b)])
	_expect(names_a.has("Elite_" + EliteModifier.KEEN) and names_a.has("Elite_" + EliteModifier.INKED),
		"both affixes attached from the dictionary alone")
	_expect(names_a.has("EliteMark"), "the read attached from the dictionary alone")
	_expect(int(a.get("max_hp")) == int(b.get("max_hp")) and int(a.get("max_hp")) == 70,
		"affixes did not move the hp the dictionary asked for")
	a.free()
	b.free()
	host_enc.free()
	peer_enc.free()
	_completes("peers_build_the_same_elite_from_the_same_dict")


# ------------------------------------------------------ 3 · the affixes work
func _test_quickened_is_faster_not_tougher() -> void:
	var plain: Node = _build(1)
	var fast: Node = _build(1, [EliteModifier.QUICKENED])
	await _settle(4)
	_expect(float(fast.get("move_speed")) > float(plain.get("move_speed")),
		"QUICKENED moves faster (%.1f vs %.1f)"
			% [float(fast.get("move_speed")), float(plain.get("move_speed"))])
	_expect(float(fast.get("_cd_speed")) > float(plain.get("_cd_speed")),
		"QUICKENED's attacks come round faster")
	_expect(float(fast.get("move_speed")) <= maxf(float(plain.get("move_speed")),
			load(EliteModifier.rider_path(EliteModifier.QUICKENED)).get("SPEED_CAP")),
		"QUICKENED is capped — an unreadable body is not a hard body")
	_expect(int(fast.get("max_hp")) == int(plain.get("max_hp")),
		"QUICKENED changed no hp whatsoever")
	_kill(plain)
	_kill(fast)
	await _settle(2)
	_completes("quickened_is_faster_not_tougher")


func _test_inked_refuses_to_be_shoved() -> void:
	var plain: Node = _build(1)
	var inked: Node = _build(1, [EliteModifier.INKED])
	await _settle(4)
	var shove := Vector2(600.0, 0.0)
	plain.call("apply_knockback", shove, false)
	inked.call("apply_knockback", shove, false)
	await _settle(3)
	var pk: float = absf((plain.get("_knockback") as Vector2).x)
	var ik: float = absf((inked.get("_knockback") as Vector2).x)
	_expect(ik < pk * 0.5,
		"INKED bleeds a shove off almost instantly (%.1f vs %.1f)" % [ik, pk])
	_expect(int(inked.get("max_hp")) == int(plain.get("max_hp")),
		"INKED changed no hp")
	_kill(plain)
	_kill(inked)
	await _settle(2)
	_completes("inked_refuses_to_be_shoved")


## KEEN unlocks `Enemy._try_evade` / `_deflect` — behaviour that is already built,
## already tuned, and unreachable on the tower's default difficulty.
func _test_keen_unlocks_the_dodge_reflexes() -> void:
	var plain: Node = _build(0)
	var keen: Node = _build(0, [EliteModifier.KEEN])
	await _settle(4)
	_expect(not bool(plain.get("_smart_dodge")),
		"ordinary trash does not dodge on the default difficulty")
	_expect(bool(keen.get("_smart_dodge")), "KEEN hops clear of incoming bolts")
	_expect(bool(keen.get("_can_deflect")), "KEEN swats a point-blank bolt")
	_expect(float(keen.get("_evade_reflex")) > 0.0, "KEEN's reflex has a real cooldown")
	_kill(plain)
	_kill(keen)
	await _settle(2)
	_completes("keen_unlocks_the_dodge_reflexes")


func _test_herald_lifts_then_restores_the_room() -> void:
	var mob: Node = _build(0)
	var control: Node = _build(1)
	var herald: Node = _build(1, [EliteModifier.HERALD])
	(herald as Node2D).global_position = (mob as Node2D).global_position + Vector2(40.0, 0.0)
	await _settle(4)
	var base: float = float(mob.get("move_speed"))
	var rider: Node = herald.get_node_or_null(NodePath("Elite_" + EliteModifier.HERALD))
	_expect(rider != null, "the herald rider attached")
	# Read before the kill below — the last leg of this test frees the herald.
	var herald_hp: int = int(herald.get("max_hp"))
	if rider != null:
		rider.call("_call_out")
		_expect(float(mob.get("move_speed")) > base,
			"a herald's call lifts the room (%.1f -> %.1f)" % [base, float(mob.get("move_speed"))])
		rider.call("_restore")
		_expect(is_equal_approx(float(mob.get("move_speed")), base),
			"...and puts it back EXACTLY, so two surges cannot compound into a drift")
		# The herald dying mid-surge must not leave the room permanently quickened.
		rider.call("_call_out")
		_kill(herald)
		await _settle(3)
		_expect(is_equal_approx(float(mob.get("move_speed")), base),
			"a herald dying mid-surge does not leave the room fast forever")
	_expect(herald_hp == int(control.get("max_hp")),
		"HERALD changed no hp (%d vs a plain brute's %d)"
			% [herald_hp, int(control.get("max_hp"))])
	_kill(mob)
	_kill(control)
	_kill(herald)
	await _settle(2)
	_completes("herald_lifts_then_restores_the_room")


func _test_volatile_bursts_on_death_and_not_on_teardown() -> void:
	# 1 · a real death detonates.
	var v: Node = _build(1, [EliteModifier.VOLATILE])
	await _settle(4)
	var before: int = _arena.get_child_count()
	SpellTargets.hurt(v, 9999)
	await _settle(4)
	_expect(_arena.get_child_count() > before - 1,
		"a volatile death leaves something behind in the arena (%d -> %d)"
			% [before, _arena.get_child_count()])
	var burst_seen: bool = false
	for c: Node in _arena.get_children():
		if c.get_script() != null and String(c.get_script().resource_path).contains("BlastSpell"):
			burst_seen = true
	_expect(burst_seen, "the burst is a real BlastSpell, stamped at the corpse")
	# 2 · a TEARDOWN must not. `tree_exiting` fires on every floor change and every
	#     headless teardown, and a blast dropped into a dying scene is a live bug.
	var v2: Node = _build(1, [EliteModifier.VOLATILE])
	await _settle(4)
	for c2: Node in _arena.get_children():
		if c2.get_script() != null and String(c2.get_script().resource_path).contains("BlastSpell"):
			c2.free()
	var before2: int = 0
	for c3: Node in _arena.get_children():
		if c3.get_script() != null and String(c3.get_script().resource_path).contains("BlastSpell"):
			before2 += 1
	_kill(v2)                                   # still at full hp: this is a teardown
	await _settle(4)
	var after2: int = 0
	for c4: Node in _arena.get_children():
		if c4.get_script() != null and String(c4.get_script().resource_path).contains("BlastSpell"):
			after2 += 1
	_expect(after2 == before2,
		"a volatile body leaving the tree ALIVE does not detonate (%d -> %d)" % [before2, after2])
	for c5: Node in _arena.get_children():
		if c5.is_in_group("enemy") or (c5.get_script() != null
				and String(c5.get_script().resource_path).contains("BlastSpell")):
			_kill(c5)
	await _settle(3)
	_completes("volatile_bursts_on_death_and_not_on_teardown")


func _test_smudged_marks_then_moves() -> void:
	var s: Node = _build(1, [EliteModifier.SMUDGED])
	(s as Node2D).global_position = _hero.global_position + Vector2(420.0, 0.0)
	await _settle(4)
	var rider: Node = s.get_node_or_null(NodePath("Elite_" + EliteModifier.SMUDGED))
	_expect(rider != null, "the smudge rider attached")
	if rider != null:
		var from: Vector2 = (s as Node2D).global_position
		rider.call("_begin", _hero.global_position)
		# THE MARK LANDS FIRST. "Step off the mark" is the entire play against this
		# affix, so a body that moved before its telegraph would be unanswerable.
		var marked: bool = false
		for c: Node in _arena.get_children():
			if c.get_script() != null and String(c.get_script().resource_path).contains("Telegraph"):
				marked = true
		_expect(marked, "a telegraph is on the ground before the body moves")
		_expect((s as Node2D).global_position.distance_to(from) < 1.0,
			"the body has not moved yet — the tell is a real window")
		rider.call("_land", _hero.global_position + Vector2(40.0, 0.0))
		_expect((s as Node2D).global_position.distance_to(from) > 100.0,
			"...and then it arrives somewhere else entirely")
	for c2: Node in _arena.get_children():
		if c2.is_in_group("enemy") or (c2.get_script() != null
				and String(c2.get_script().resource_path).contains("Telegraph")):
			_kill(c2)
	await _settle(3)
	_completes("smudged_marks_then_moves")


## THE 25-ENTITY CAP. `Encounter.can_spawn()` is the single authority on how many
## bodies may exist, and everything that spawns has to ask it. The cheapest way for
## an affix to break that is to spawn something itself, so: none of them may.
func _test_no_affix_ever_spawns_a_body() -> void:
	var bodies: Array[Node] = []
	for aid: String in EliteModifier.all_ids():
		bodies.append(_build(1, [aid]))
	await _settle(4)
	var before: int = root.get_tree().get_nodes_in_group("enemy").size()
	# Drive every rider hard: a full second of ticks, which is past HERALD's first
	# call and past SMUDGED's first smear.
	for i: int in 70:
		await process_frame
	var after: int = root.get_tree().get_nodes_in_group("enemy").size()
	_expect(after <= before,
		"no affix adds a body to the live-entity count (%d -> %d)" % [before, after])
	for b: Node in bodies:
		_kill(b)
	for c: Node in _arena.get_children():
		if c != _hero and c.is_in_group("enemy"):
			_kill(c)
	await _settle(3)
	_completes("no_affix_ever_spawns_a_body")


# --------------------------------------------------- 4 · floor affixes (OFF)
func _test_floor_affixes_ship_off_and_wire_up_when_on() -> void:
	_expect(FloorGen.floor_affixes_enabled == false,
		"FLOOR AFFIXES SHIP OFF. The design spec lists floor modifiers as out for v1; "
		+ "the mechanism is built and one flag from live, and that call is the maker's")
	# ⚠ NOT the bare `GameState` identifier: an autoload name is not a global under
	# `--script`, and naming one is a COMPILE error that takes the whole suite down.
	var tower: Resource = (load(GS_PATH) as GDScript).build_default_tower()
	# OFF: not a single floor carries a generated affix.
	var off_hits: int = 0
	for s: int in range(0, 60):
		var t: Resource = FloorGen.vary_tower(tower, s * 53 + 11)
		for f in (t.floors as Array):
			off_hits += (EliteRoster.parse_floor_affixes(f.special_tags) as Array).size()
	_expect(off_hits == 0, "with the flag off no floor carries an affix (%d found)" % off_hits)

	# ON: floors take a rule, floor 1 and BOSS floors never do, and applying twice
	# does not grow the tag array.
	FloorGen.floor_affixes_enabled = true
	var on_hits: int = 0
	var illegal: int = 0
	for s2: int in range(0, 60):
		var t2: Resource = FloorGen.vary_tower(tower, s2 * 53 + 11)
		for i: int in (t2.floors as Array).size():
			var f2 = t2.floors[i]
			var got: Array = EliteRoster.parse_floor_affixes(f2.special_tags)
			on_hits += got.size()
			if not got.is_empty():
				if int(f2.depth) < FloorGen.FLOOR_AFFIX_MIN_DEPTH:
					illegal += 1
				if int(f2.floor_type) == FloorDef.FloorType.BOSS:
					illegal += 1
				for a in got:
					if not EliteRoster.FLOOR_AFFIX_POOL.has(String(a)):
						illegal += 1
			# ...and every one of them is a real, attachable affix.
			for a2 in got:
				if not EliteModifier.has(String(a2)):
					illegal += 1
	_expect(on_hits > 0, "with the flag on, floors do take a rule (%d over 60 climbs)" % on_hits)
	_expect(illegal == 0, "no floor affix lands where it must not (%d violations)" % illegal)
	# The stamp is the generator's own scratchpad: applying it to an ALREADY-stamped
	# floor must rewrite it, never accumulate it.
	#
	# ⚠ THE ASSERTION IS "AT MOST ONE OF EACH PREFIX", NOT "THE TAG COUNT NEVER
	# GROWS". Re-running the generator over its own output is not idempotent and never
	# was — the second pass reads redrawn wave rosters, which consume a different
	# number of rng draws, so every downstream roll (shape, seed, affix) legitimately
	# lands somewhere else. What must hold is that no prefix is ever DUPLICATED.
	var once: Resource = FloorGen.vary_tower(tower, 4242)
	var twice: Resource = FloorGen.vary_tower(once, 4242)
	for i2: int in (twice.floors as Array).size():
		var counts: Dictionary = {}
		for t3 in (twice.floors[i2].special_tags as Array):
			var s3: String = String(t3)
			for p: String in [FloorGen.TAG_SHAPE, FloorGen.TAG_SEED, FloorGen.TAG_GEN_AFFIX]:
				if s3.begins_with(p):
					counts[p] = int(counts.get(p, 0)) + 1
		for p2 in counts:
			_expect(int(counts[p2]) <= 1,
				"prefix `%s` is rewritten, not accumulated (floor %d saw %d)"
					% [String(p2), i2, int(counts[p2])])
	# ...and the generator is still PURE: same input, same seed, same answer.
	var a1: Resource = FloorGen.vary_tower(tower, 909)
	var a2: Resource = FloorGen.vary_tower(tower, 909)
	for i3: int in (a1.floors as Array).size():
		_expect(str(a1.floors[i3].special_tags) == str(a2.floors[i3].special_tags),
			"the affix roll is pure (floor %d)" % i3)
	FloorGen.floor_affixes_enabled = false

	# AUTHORED pins survive a redraw — `aff:` is a designer's statement, `genaff:` is
	# the generator's scratchpad.
	var pinned: Resource = _floor(3, 10, ["aff:inked"] as Array[String])
	var redrawn: Resource = FloorGen.vary_floor(pinned, 3, "ashspire", 777)
	_expect((redrawn.special_tags as Array).has("aff:inked"),
		"an authored `aff:` pin survives the generator")
	_expect(EliteRoster.parse_floor_affixes(redrawn.special_tags).has(EliteModifier.INKED),
		"...and Encounter reads it")

	# ...and the whole floor actually wears it.
	var enc: Node = _enc()
	_arena.add_child(enc)
	enc.run_floor(_floor(3, 6, ["aff:inked", "no_elites"] as Array[String]))
	enc.stop()
	_expect(str(enc.call("floor_affixes")) == str([EliteModifier.INKED]),
		"the floor carries its rule")
	enc.call("spawn", 0.3, 1.0, [1] as Array[int])
	_land(enc)
	await _settle(3)
	var wore: int = 0
	var dressed: int = 0
	for c: Node in _arena.get_children():
		if not c.is_in_group("enemy"):
			continue
		if c.has_node(NodePath("Elite_" + EliteModifier.INKED)):
			wore += 1
		if c.has_node(^"EliteMark"):
			dressed += 1
		_kill(c)
	_expect(wore == 1, "the spawned body wears the floor's rule (%d)" % wore)
	_expect(dressed == 0, "...and is NOT dressed as an elite (%d)" % dressed)
	enc.queue_free()
	await _settle(2)
	_completes("floor_affixes_ship_off_and_wire_up_when_on")


# ------------------------------------------------------------------- file io
func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


func _rider_files() -> Array[String]:
	var out: Array[String] = []
	var d: DirAccess = DirAccess.open(RIDER_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if n.ends_with(".gd"):
			out.append(n)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


class _HeroStub extends Node2D:
	var hp: int = 100
	var max_hp: int = 100
	func take_damage(amount: int) -> void:
		hp = maxi(hp - amount, 0)
	func is_downed() -> bool:
		return hp <= 0


## ══ THE ELITE WAVE ════════════════════════════════════════════════════════════
## `EliteRoster` already makes an elite RARE. What it could not do is make one
## ARRIVE: the spend is uniform across the whole floor, so the named body turns up
## somewhere inside a wave of eleven and reads as a body with an aura rather than
## as a moment. `WaveDef.elite_wave` re-points the denominator at one wave.
##
## Two halves, and the second is the one that matters:
##   1. the flagged wave gets the WHOLE budget;
##   2. the ordinary waves get NONE — because if waves 1-2 spend in the usual way,
##      the wave the floor was authored around opens with nothing left to give and
##      the feature works perfectly while being invisible.
##
## ⚠ THE CONTROL IS PART OF THE TEST. The same floor with the flag OFF must scatter,
## or this is measuring an instrument that cannot fail. That is the trap this
## codebase keeps re-learning: an assertion nothing can violate is not an assertion.
func _test_an_elite_wave_takes_the_whole_budget() -> void:
	var depth: int = 4
	var want: int = EliteRoster.budget(depth)
	_expect(want >= 2, "depth %d has a budget worth concentrating (%d)" % [depth, want])
	var flagged_total: int = 0
	var flagged_outside: int = 0
	var control_outside: int = 0
	for trial: int in 30:
		flagged_total += _walk_floor(depth, true, 1)[0]
		flagged_outside += _walk_floor(depth, true, 1)[1]
		control_outside += _walk_floor(depth, false, 1)[1]
	_expect(flagged_outside == 0,
		"an ordinary wave never spends while the floor is holding for its elite wave (%d leaked)"
			% flagged_outside)
	_expect(flagged_total == want * 30,
		"the elite wave lands the whole budget every time (%d of %d)" % [flagged_total, want * 30])
	# THE CONTROL. Without the flag the same floor scatters, which is what makes the
	# two assertions above mean something.
	_expect(control_outside > 0,
		"...and WITHOUT the flag the same floor spends outside wave 1 (%d) — if this is 0 the "
		+ "test above is measuring nothing" % control_outside)
	_completes("an_elite_wave_takes_the_whole_budget")


## Drive a three-wave floor through the REAL `_start_wave` / `_roll_elite` pair and
## report [spent_in_wave `mark`, spent_anywhere_else].
func _walk_floor(depth: int, flag: bool, mark: int) -> Array[int]:
	var enc: Node = _enc()
	_arena.add_child(enc)
	var f := FloorDef.new()
	f.floor_type = FloorDef.FloorType.COMBAT
	f.depth = depth
	var list: Array[WaveDef] = []
	for i: int in 3:
		var w := WaveDef.new()
		w.enemy_budget = 10
		w.concurrent_cap = 4
		w.elite_wave = flag and i == mark
		list.append(w)
	f.waves = list
	f.enemy_budget = 30
	enc.run_floor(f)
	enc.stop()
	var inside: int = 0
	var outside: int = 0
	var spawned: int = 0
	for wi: int in 3:
		enc.call("_start_wave", wi)
		for i: int in 10:
			enc.set("_wave_spawned", i)
			var before: int = (enc.call("elite_log") as Array).size()
			enc.call("_roll_elite", i % 8)
			spawned += 1
			enc.set("_floor_spawned", spawned)
			var got: int = (enc.call("elite_log") as Array).size() - before
			if wi == mark:
				inside += got
			else:
				outside += got
	enc.queue_free()
	var out: Array[int] = [inside, outside]
	return out
