# Run: godot --headless --path godot-project --script tools/slice_test_bossroster.gd
#
# THE BOSS ROSTER AND THE SIX MODIFIERS — the pure half. Roster windows, the
# modifier-count curve, and above all THE DETERMINISM OF THE ROLL, which is the
# single property co-op correctness rests on: the host rolls once and the result
# travels in the spawn dictionary, so if `roll()` were impure the two phones would
# fight different bosses.
#
# Also guards the spec's own rule from the inside: no roster row and no modifier is
# allowed to scale HP with depth. `modifier_count` is asserted to be the ONLY thing
# that grows with the floor number.
#
# Everything here is static/pure: no arena, no tree, no autoloads.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──────────
# A dead property read is NOT a test failure in GDScript: it logs an error, ABORTS
# the enclosing function, and hands the caller the return type's zero. Under the old
# `failed += _test_x()` idiom that reads as "zero failures", so a suite could print
# all PASS while silently skipping every assertion after the dead line. So failures
# accumulate on the MEMBER `_fails`, and every test's last line records that it
# reached the end — a test that aborts is then missing from `_completed` and fails
# the suite BY ABSENCE.
extends SceneTree

const SPLIT_PATH: String = "res://scripts/combat/bossmods/ModSplit.gd"
const MIRROR_PATH: String = "res://scripts/combat/bossmods/ModMirrored.gd"

## Every test that must run to completion.
const TESTS: Array[String] = [
	"roster_table_is_sane",
	"modifier_table_is_sane",
	"floor_windows",
	"modifier_count_curve",
	"roll_is_deterministic",
	"roll_respects_windows",
	"roll_is_actually_random",
	"roll_pins_and_no_mods",
	"parse_tags",
	"split_carve_conserves_the_pool",
	"mirror_matcher",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_roster_table_is_sane()
	_test_modifier_table_is_sane()
	_test_floor_windows()
	_test_modifier_count_curve()
	_test_roll_is_deterministic()
	_test_roll_respects_windows()
	_test_roll_is_actually_random()
	_test_roll_pins_and_no_mods()
	_test_parse_tags()
	_test_split_carve_conserves_the_pool()
	_test_mirror_matcher()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Boss roster tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Boss roster tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ the tables
func _test_roster_table_is_sane() -> void:
	var ids: Array[String] = BossRoster.ids()
	_expect(ids.size() == 4, "the roster is FOUR hand-built bosses (got %d)" % ids.size())
	var seen: Dictionary = {}
	for e: Dictionary in BossRoster.ENTRIES:
		var id: String = String(e["id"])
		_expect(not seen.has(id), "roster id '%s' is unique" % id)
		seen[id] = true
		_expect(ResourceLoader.exists(String(e["scene"])),
			"roster '%s' points at a scene that exists (%s)" % [id, e["scene"]])
		_expect(String(e["name"]) != "", "roster '%s' has a display name" % id)
		_expect(String(e["artist"]) != "", "roster '%s' names its artist (the lore beat)" % id)
		_expect(float(e["hp_scale"]) > 0.0, "roster '%s' has a positive hp_scale" % id)
		_expect(float(e["speed_scale"]) > 0.0, "roster '%s' has a positive speed_scale" % id)
	# The Guardian must have no ceiling, or a deep floor could have NO legal boss.
	_expect(int(BossRoster.entry(BossRoster.GUARDIAN)["max_floor"]) == 0,
		"the Ashspire Guardian has no depth ceiling (it is the always-legal fallback)")
	# An unknown id must degrade to the Guardian rather than crash a spawn.
	_expect(BossRoster.scene_path("nonsense_id") == BossRoster.scene_path(BossRoster.GUARDIAN),
		"an unknown boss id falls back to the Guardian")
	_completes("roster_table_is_sane")


func _test_modifier_table_is_sane() -> void:
	var ids: Array[String] = BossModifier.all_ids()
	_expect(ids.size() == 6, "there are SIX modifiers (got %d)" % ids.size())
	# The five the spec names by name, plus the sixth.
	for required: String in [
		BossModifier.ENRAGED, BossModifier.SPLIT, BossModifier.VOID_TOUCHED,
		BossModifier.MIRRORED, BossModifier.PATIENT, BossModifier.UNFINISHED,
	]:
		_expect(BossModifier.has(required), "modifier '%s' is registered" % required)
	var seen: Dictionary = {}
	for r: Dictionary in BossModifier.REGISTRY:
		var id: String = String(r["id"])
		_expect(not seen.has(id), "modifier id '%s' is unique" % id)
		seen[id] = true
		_expect(ResourceLoader.exists(BossModifier.RIDER_DIR + String(r["rider"])),
			"modifier '%s' has a rider script on disk" % id)
		_expect(int(r["min_floor"]) >= 1, "modifier '%s' has a sane min_floor" % id)
		_expect(String(r["blurb"]) != "", "modifier '%s' has a blurb" % id)
	# The Resource form round-trips.
	var m: BossModifier = BossModifier.make(BossModifier.SPLIT)
	_expect(m != null and m.id == BossModifier.SPLIT, "make() builds the Resource form")
	_expect(m != null and m.rider_script.ends_with("ModSplit.gd"), "make() resolves the rider path")
	_expect(BossModifier.make("nonsense_id") == null, "make() of an unknown id is null")
	_completes("modifier_table_is_sane")


# ---------------------------------------------------------------- floor windows
func _test_floor_windows() -> void:
	var f1: Array[String] = BossRoster.eligible(1)
	_expect(f1.has(BossRoster.SCRIBBLE), "floor 1 can draw the crude scribble")
	_expect(not f1.has(BossRoster.CARTOGRAPHER), "floor 1 is too shallow for the cartographer")
	_expect(not f1.has(BossRoster.ILLUMINATOR), "floor 1 is far too shallow for the illuminator")
	var f4: Array[String] = BossRoster.eligible(4)
	_expect(f4.has(BossRoster.ILLUMINATOR), "floor 4 unlocks the illuminator")
	_expect(not f4.has(BossRoster.SCRIBBLE), "floor 4 has left the crude artist behind")
	# EVERY floor must offer a genuine choice, or "randomised selection" is a lie at
	# that depth and the whole climb becomes one fixed boss per floor.
	for d: int in range(1, 20):
		_expect(BossRoster.eligible(d).size() >= 2,
			"depth %d has at least two artists to choose between (got %d)" % [d, BossRoster.eligible(d).size()])
	# ...and every hand-built boss must actually be reachable somewhere.
	var reachable: Dictionary = {}
	for d: int in range(1, 20):
		for id: String in BossRoster.eligible(d):
			reachable[id] = true
	_expect(reachable.size() == BossRoster.ids().size(),
		"every boss in the roster is reachable at some depth (%d of %d)" % [reachable.size(), BossRoster.ids().size()])
	var f9: Array[String] = BossRoster.eligible(9)
	_expect(not f9.has(BossRoster.SCRIBBLE),
		"the scribble stops appearing once the tower can draw properly (escalation = skill)")
	_expect(f9.has(BossRoster.ILLUMINATOR), "deep floors keep the illuminator")
	# Never empty, at any depth, or a floor would soft-lock with no guardian.
	for d: int in [0, 1, 3, 7, 50, 999]:
		_expect(BossRoster.eligible(d).size() > 0, "depth %d has at least one legal boss" % d)
	_completes("floor_windows")


## THE ONE DEPTH DIAL. The spec: "higher floors add MODIFIERS, NOT HP." So the
## modifier count is asserted to grow, to be monotonic, and to be capped — and
## nothing else in this file is allowed to be a function of depth at all.
func _test_modifier_count_curve() -> void:
	var expected: Dictionary = {1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3, 7: 3, 8: 4, 12: 4, 99: 4}
	for d in expected:
		_expect(BossRoster.modifier_count(int(d)) == int(expected[d]),
			"floor %d carries %d modifiers (got %d)" % [d, expected[d], BossRoster.modifier_count(int(d))])
	var prev: int = -1
	for d: int in range(0, 40):
		var n: int = BossRoster.modifier_count(d)
		_expect(n >= prev, "the modifier curve is monotonic at depth %d" % d)
		_expect(n <= BossRoster.MAX_MODIFIERS, "the modifier curve is capped at depth %d" % d)
		prev = n
	_expect(BossRoster.modifier_count(0) == 0,
		"an unknown depth (0) rolls NO modifiers — the sandbox/legacy boss is unchanged")
	_completes("modifier_count_curve")


# ------------------------------------------------------------------- the roll
## CO-OP'S WHOLE CORRECTNESS ARGUMENT. If this ever goes red, two players in the
## same room are fighting different bosses.
func _test_roll_is_deterministic() -> void:
	for i: int in 240:
		var depth: int = 1 + (i % 12)
		var s: int = 0x51ED270B + i * 7919
		var a: Dictionary = BossRoster.roll(depth, s)
		var b: Dictionary = BossRoster.roll(depth, s)
		if String(a["boss"]) != String(b["boss"]) or _joined(a["mods"]) != _joined(b["mods"]):
			_expect(false, "roll(%d, %d) is not deterministic (%s/%s vs %s/%s)" % [
				depth, s, a["boss"], _joined(a["mods"]), b["boss"], _joined(b["mods"])])
			break
	# Different depths on the same seed must not collapse to the same fight, or a
	# whole climb would be one boss repeated.
	var same_seed_varies: bool = false
	for d: int in range(2, 12):
		if String(BossRoster.roll(d, 4242)["boss"]) != String(BossRoster.roll(2, 4242)["boss"]):
			same_seed_varies = true
			break
	_expect(same_seed_varies, "one seed across depths does not produce the same boss every floor")
	_completes("roll_is_deterministic")


func _test_roll_respects_windows() -> void:
	for depth: int in range(1, 15):
		var legal: Array[String] = BossRoster.eligible(depth)
		var want: int = BossRoster.modifier_count(depth)
		for i: int in 60:
			var r: Dictionary = BossRoster.roll(depth, 1000 + i * 31)
			_expect(legal.has(String(r["boss"])),
				"depth %d rolled '%s', which is outside its window" % [depth, r["boss"]])
			var mods: Array = r["mods"]
			if mods.size() != want:
				_expect(false, "depth %d rolled %d modifiers, wanted %d" % [depth, mods.size(), want])
				break
			var seen: Dictionary = {}
			var bad: bool = false
			for m in mods:
				var mid: String = String(m)
				if seen.has(mid):
					_expect(false, "depth %d rolled '%s' twice" % [depth, mid])
					bad = true
				seen[mid] = true
				if depth < BossModifier.make(mid).min_floor:
					_expect(false, "depth %d rolled '%s', which needs floor %d" % [
						depth, mid, BossModifier.make(mid).min_floor])
					bad = true
			if bad:
				break
	_completes("roll_respects_windows")


## "Randomised selection" has to actually be random — a roll that is deterministic
## per FLOOR rather than per RUN would give every player the same five fights
## forever, which is the failure this whole feature exists to avoid.
func _test_roll_is_actually_random() -> void:
	var bosses: Dictionary = {}
	var mod_sets: Dictionary = {}
	for i: int in 400:
		var r: Dictionary = BossRoster.roll(5, i * 2654435761)
		bosses[String(r["boss"])] = true
		mod_sets[_joined(r["mods"])] = true
	_expect(bosses.size() >= 3,
		"depth 5 produces a variety of bosses across seeds (got %d distinct)" % bosses.size())
	_expect(mod_sets.size() >= 5,
		"depth 5 produces a variety of modifier pairs (got %d distinct)" % mod_sets.size())
	_completes("roll_is_actually_random")


func _test_roll_pins_and_no_mods() -> void:
	var pinned: Dictionary = BossRoster.roll(6, 99, BossRoster.ILLUMINATOR)
	_expect(String(pinned["boss"]) == BossRoster.ILLUMINATOR, "an authored boss pin wins the roll")
	var bad_pin: Dictionary = BossRoster.roll(6, 99, "not_a_boss")
	_expect(BossRoster.eligible(6).has(String(bad_pin["boss"])),
		"an unknown boss pin falls back to a legal roll instead of breaking the floor")
	var forced: Dictionary = BossRoster.roll(6, 99, "", [BossModifier.MIRRORED])
	_expect((forced["mods"] as Array).has(BossModifier.MIRRORED), "a forced modifier is applied")
	_expect((forced["mods"] as Array).size() == BossRoster.modifier_count(6),
		"a forced modifier counts toward the floor's budget rather than being extra")
	var clean: Dictionary = BossRoster.roll(9, 99, "", [], false)
	_expect((clean["mods"] as Array).is_empty(), "allow_mods=false rides clean at any depth")
	var clean_forced: Dictionary = BossRoster.roll(9, 99, "", [BossModifier.PATIENT], false)
	_expect(_joined(clean_forced["mods"]) == BossModifier.PATIENT,
		"allow_mods=false still honours an explicit pin (the author asked for it)")
	_completes("roll_pins_and_no_mods")


func _test_parse_tags() -> void:
	var t: Dictionary = BossRoster.parse_tags([
		"no_crates", "boss:cartographer", "mod:enraged", "mod:enraged",
		"mod:not_a_modifier", "boss:not_a_boss",
	])
	_expect(String(t["boss"]) == BossRoster.CARTOGRAPHER, "boss: tag is read")
	_expect(_joined(t["mods"]) == BossModifier.ENRAGED, "mod: tags dedupe and reject unknowns")
	_expect(bool(t["allow_mods"]), "allow_mods defaults true")
	var off: Dictionary = BossRoster.parse_tags(["no_mods"])
	_expect(not bool(off["allow_mods"]), "no_mods tag turns the roll off")
	var none: Dictionary = BossRoster.parse_tags([])
	_expect(String(none["boss"]) == "" and (none["mods"] as Array).is_empty(),
		"an untagged floor pins nothing")
	_completes("parse_tags")


# ------------------------------------------------------------ modifier internals
## SPLIT MUST NOT BE AN HP BUFF WEARING A COSTUME. Parent + both copies must sum to
## the pool the boss was rolled with, or the modifier has quietly reintroduced the
## depth-HP curve the spec spent a whole rule banning.
func _test_split_carve_conserves_the_pool() -> void:
	var split: GDScript = load(SPLIT_PATH) as GDScript
	_expect(split != null, "ModSplit.gd loads")
	if split == null:
		return
	var parent_frac: float = float(split.get("PARENT_FRACTION"))
	var copy_frac: float = float(split.get("COPY_FRACTION"))
	_expect(is_equal_approx(parent_frac + 2.0 * copy_frac, 1.0),
		"parent + 2 copies == 100%% of the original pool (got %.3f)" % (parent_frac + 2.0 * copy_frac))

	var original: int = 1000
	var parent_data: Dictionary = {
		"boss": true, "bid": BossRoster.SCRIBBLE, "hp": original, "spd": 100.0,
		"touch": 20, "bscale": 0.9, "x": 10.0, "y": 20.0,
		"mods": [BossModifier.SPLIT, BossModifier.PATIENT, BossModifier.VOID_TOUCHED],
	}
	var copy: Dictionary = split.call("copy_spawn_data", parent_data, original, Vector2(300, 400), 2)
	_expect(int(copy["hp"]) == int(round(float(original) * copy_frac)),
		"a copy carries exactly its carved share (got %d)" % int(copy["hp"]))
	_expect(bool(copy["boss"]), "a copy is still a boss body")
	_expect(String(copy["bid"]) == BossRoster.SCRIBBLE, "a copy is the same artist")
	_expect(float(copy["bscale"]) < float(parent_data["bscale"]), "a copy is physically smaller")
	_expect(float(copy["spd"]) > float(parent_data["spd"]), "a copy is quicker than the parent")
	_expect(is_equal_approx(float(copy["x"]), 300.0) and is_equal_approx(float(copy["y"]), 400.0),
		"a copy spawns where it was told")
	var inherited: Array = copy["mods"]
	_expect(not inherited.has(BossModifier.SPLIT),
		"THE RECURSION GUARD: a copy never inherits Split")
	_expect(not inherited.has(BossModifier.PATIENT),
		"a copy never inherits Patient (a copy standing still reads as a spawn failure)")
	_expect(inherited.has(BossModifier.VOID_TOUCHED), "a copy DOES inherit everything else")
	_expect(bool(copy["quiet"]), "a copy is quiet — no second boss bar, no second name card")
	_expect(int(copy["qphase"]) == 2, "a copy starts in the phase its parent died in")
	# The parent dict must not be mutated — it is the dict the boss was built from.
	_expect((parent_data["mods"] as Array).size() == 3, "building a copy does not mutate the parent data")
	_completes("split_carve_conserves_the_pool")


func _test_mirror_matcher() -> void:
	var mirror: GDScript = load(MIRROR_PATH) as GDScript
	_expect(mirror != null, "ModMirrored.gd loads")
	if mirror == null:
		return
	# Every mapped script path must exist, or the mirror would silently never fire
	# for that spell — the failure mode this map is written out by hand to avoid.
	var map: Dictionary = mirror.get("KIND_FOR_SCRIPT")
	_expect(map.size() >= 15, "the mirror knows a real spread of spells (got %d)" % map.size())
	for path in map:
		_expect(ResourceLoader.exists(String(path)), "mirror map path exists: %s" % path)

	var beam: SpellDef = mirror.call("match_spell",
		"res://scripts/combat/BeamSpell.gd", Elements.Element.FIRE, SpellTier.Tier.ULT)
	_expect(beam != null and beam.kind == SpellDef.Kind.BEAM,
		"a hero beam is answered with a beam")
	_expect(beam == null or beam.element == Elements.Element.FIRE,
		"...of the same element when the library has one")
	var zone: SpellDef = mirror.call("match_spell",
		"res://scripts/combat/ZoneSpell.gd", Elements.Element.SHADOW, SpellTier.Tier.HEAVY)
	_expect(zone != null and zone.kind == SpellDef.Kind.ZONE, "a hero zone is answered with a zone")
	# Determinism: the same observation must always produce the same answer, or two
	# co-op peers watching the same cast would mirror different spells.
	var again: SpellDef = mirror.call("match_spell",
		"res://scripts/combat/BeamSpell.gd", Elements.Element.FIRE, SpellTier.Tier.ULT)
	_expect(beam == null or (again != null and again.id == beam.id),
		"the matcher is deterministic")
	_expect(mirror.call("match_spell", "res://scripts/combat/NotASpell.gd", -1, -1) == null,
		"an unknown spectacle is not mirrored")
	# Caster-displacement kinds are declined: SpellCaster hands displacement to a
	# duck-typed `blink_to` that only the Hero implements, so mirroring one would
	# spawn a spectacle that visibly fizzles.
	_expect(mirror.call("match_spell", "res://scripts/combat/LightningRush.gd", -1, -1) == null,
		"a caster-displacing spell is declined rather than mirrored into a fizzle")
	_completes("mirror_matcher")


func _joined(a: Variant) -> String:
	var parts: Array[String] = []
	for x in (a as Array):
		parts.append(String(x))
	return ",".join(parts)
