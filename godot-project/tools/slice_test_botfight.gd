# Run: godot --headless --path godot-project --script tools/slice_test_botfight.gd
#
# THE HUMAN-VS-BOT SLICE: `BotAdapt` (the in-session learning module), its
# persistence round-trip, and the two places it plugs into `BotController`.
#
# WHAT THIS SUITE IS REALLY GUARDING. Adaptation is the one feature in the bot
# stack that could quietly break the fairness promise `BotProfile` makes, so the
# most important tests here are the NEGATIVE ones: that learning never touches
# the four difficulty keys, that the aim lean is capped below the bot's own
# scatter, and that an empty record produces the stock bot unchanged. A bot that
# got faster the more you played it would pass every functional test in this file
# and still be the bug.
#
# ⚠ TEST HYGIENE, and it is not optional here. Reading a member that no longer
# exists is NOT a failure in GDScript — it logs an error, ABORTS the enclosing
# function, and hands the caller the return type's zero. Under a
# `fails += _test_x()` idiom that reads as "found zero failures", so this suite
# accumulates on the MEMBER `_fails` and every test records a COMPLETION SENTINEL
# as its last line. A test that dies half-way fails the suite by ABSENCE.
#
# ⚠ AUTOLOADS (Sfx / Tuning / Net / GameState / SpellReactor) are NOT registered
# under `--script`, so nothing below may name one — not even indirectly through a
# static function that mentions it.
extends SceneTree

## Every test that must run to completion. Missing from `_completed` = aborted.
const TESTS: Array[String] = [
	"empty_record_is_inert",
	"derived_reads",
	"profile_shaping_bounds",
	"protected_keys_are_untouchable",
	"aim_lean_is_capped",
	"slot_preference_needs_an_edge",
	"guard_bait",
	"anti_camp",
	"store_round_trip",
	"store_version_guard",
	"store_wipe",
	"controller_no_adapt_is_stock",
	"controller_adapt_is_applied",
	"summary_is_readable",
]

## A scratch directory so the round-trip tests never touch the maker's real
## learned profile. Removed at the end of the run.
const TEST_DIR: String = "user://bot_adapt_test"
const TEST_FILE: String = "suite.json"

var _fails: int = 0
var _completed: Dictionary = {}


func _initialize() -> void:
	print("=== bot-fight suite ===")
	_test_empty_record_is_inert()
	_test_derived_reads()
	_test_profile_shaping_bounds()
	_test_protected_keys_are_untouchable()
	_test_aim_lean_is_capped()
	print("-- batch 1 done --")
	_test_slot_preference_needs_an_edge()
	_test_guard_bait()
	_test_anti_camp()
	_test_store_round_trip()
	_test_store_version_guard()
	_test_store_wipe()
	print("-- batch 2 done --")
	_test_controller_no_adapt_is_stock()
	_test_controller_adapt_is_applied()
	_test_summary_is_readable()
	print("-- batch 3 done --")
	_cleanup()
	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("ABORTED (never completed): %s" % name)
	if _fails == 0:
		print("bot-fight tests: all PASS (%d tests)" % TESTS.size())
	else:
		printerr("bot-fight tests: %d FAILURE(S)" % _fails)
	quit(0 if _fails == 0 else 1)


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("  ok   %s" % what)
	else:
		_fails += 1
		printerr("  FAIL %s" % what)


func _completes(name: String) -> void:
	_completed[name] = true


# ---------------------------------------------------------------------------
# A record with enough samples to be believed, built once so every test that
# needs "a confident record" starts from the same numbers.
func _confident_record(samples: int = 1200) -> Dictionary:
	var rec: Dictionary = BotAdapt.empty_record()
	rec["samples"] = samples
	rec["range_sum"] = float(samples) * 90.0     # a player who lives at contact range
	rec["guard_ticks"] = int(samples * 0.4)      # ...and guards a lot
	rec["air_ticks"] = int(samples * 0.1)
	rec["dodge_left"] = 4
	rec["dodge_right"] = 36                      # breaks RIGHT, decisively
	rec["slot_casts"] = [10, 10, 10, 10, 10]
	rec["slot_hits"] = [1, 9, 2, 2, 2]           # the CONTROL slot keeps landing
	rec["bot_whiffs"] = 20
	rec["human_punishes"] = 16                   # punishes 80% of whiffs
	return rec


# =========================================================================
func _test_empty_record_is_inert() -> void:
	var rec: Dictionary = BotAdapt.empty_record()
	_expect(is_equal_approx(BotAdapt.confidence(rec), 0.0), "fresh record has zero confidence")
	_expect(BotAdapt.preferred_range(rec) < 0.0, "fresh record has no preferred range")
	_expect(is_equal_approx(BotAdapt.dodge_bias(rec), 0.0), "fresh record has no dodge habit")
	_expect(BotAdapt.best_slot(rec) == -1, "fresh record has no favourite slot")
	# The one that matters: with nothing learned, the bot is the shipped bot.
	var base: Dictionary = BotProfile.of(BotProfile.Tier.HARD)
	var shaped: Dictionary = BotAdapt.shape_profile(base, rec, 200.0)
	var same: bool = true
	for k: Variant in base.keys():
		if shaped.get(k) != base.get(k):
			same = false
	_expect(same, "an empty record leaves EVERY profile key untouched")
	var intent: Dictionary = {"aim": Vector2.RIGHT, "cast_slot": 0}
	var out: Dictionary = BotAdapt.shape_intent(intent, {}, rec, base)
	_expect(out.get("cast_slot") == 0 and out.get("aim") == Vector2.RIGHT,
		"an empty record leaves the intent untouched")
	_completes("empty_record_is_inert")


func _test_derived_reads() -> void:
	var rec: Dictionary = _confident_record()
	_expect(is_equal_approx(BotAdapt.confidence(rec), 1.0), "1200 ticks = full confidence")
	_expect(is_equal_approx(BotAdapt.preferred_range(rec), 90.0), "preferred range is the mean")
	_expect(absf(BotAdapt.guard_rate(rec) - 0.4) < 0.02, "guard rate reads back")
	_expect(BotAdapt.dodge_bias(rec) > 0.7, "a 36/4 right-bias reads as strongly right")
	_expect(absf(BotAdapt.punish_rate(rec) - 0.8) < 0.01, "punish rate is punishes/whiffs")
	_expect(BotAdapt.best_slot(rec) == 1, "the slot that keeps landing is the favourite")
	# Under-sampled slots must report "no opinion", not a confident 100%.
	var thin: Dictionary = BotAdapt.empty_record()
	thin["samples"] = 1200
	thin["slot_casts"] = [2, 0, 0, 0, 0]
	thin["slot_hits"] = [2, 0, 0, 0, 0]
	_expect(BotAdapt.slot_hit_rate(thin, 0) < 0.0, "2 casts is not a 100% hit rate")
	_expect(BotAdapt.best_slot(thin) == -1, "...and yields no favourite at all")
	# ...and so must an under-sampled dodge habit.
	var few: Dictionary = BotAdapt.empty_record()
	few["samples"] = 1200
	few["dodge_right"] = 3
	_expect(is_equal_approx(BotAdapt.dodge_bias(few), 0.0), "3 dodges is not a habit")
	_completes("derived_reads")


func _test_profile_shaping_bounds() -> void:
	var rec: Dictionary = _confident_record()
	var base: Dictionary = BotProfile.of(BotProfile.Tier.NORMAL)
	# This player fights at 90 px; a caster band centred at 265 wants them further
	# away, so the bot should get LESS aggressive (push the band out).
	var caster: Dictionary = BotAdapt.shape_profile(base, rec, 265.0)
	_expect(float(caster["aggression"]) < float(base["aggression"]),
		"a player who crowds a caster makes it back off")
	_expect(absf(float(caster["aggression"]) - float(base["aggression"]))
		<= BotAdapt.AGGRESSION_MAX_SHIFT + 0.0001, "...by no more than the cap")
	# The mirror: a player who camps at 400 against a brawler band centred at 75
	# should make it MORE aggressive.
	var kiter: Dictionary = _confident_record()
	kiter["range_sum"] = 1200.0 * 400.0
	var brawler: Dictionary = BotAdapt.shape_profile(base, kiter, 75.0)
	_expect(float(brawler["aggression"]) > float(base["aggression"]),
		"a player who kites a brawler makes it chase")
	# An 80% punish rate must lower the willingness to start long channels.
	_expect(float(caster["risk"]) < float(base["risk"]),
		"a player who punishes whiffs makes the bot less channel-happy")
	_expect(float(base["risk"]) - float(caster["risk"])
		<= BotAdapt.RISK_MAX_SHIFT + 0.0001, "...by no more than the cap")
	# Being crowded is what makes a guard worth having.
	_expect(float(caster["guard"]) > float(base["guard"]),
		"being fought at contact range makes the bot invest in guarding")
	# Half-confidence must move a knob by less than full confidence does.
	var half: Dictionary = _confident_record(int(BotAdapt.CONFIDENCE_TICKS * 0.5))
	var soft: Dictionary = BotAdapt.shape_profile(base, half, 265.0)
	_expect(float(soft["aggression"]) > float(caster["aggression"]),
		"less data = a smaller adjustment")
	# The base profile itself must never be mutated (one bot's learning leaking
	# into the shared tier table is exactly the bug BotProfile.of duplicates for).
	_expect(is_equal_approx(float(base["aggression"]),
		float(BotProfile.of(BotProfile.Tier.NORMAL)["aggression"])),
		"shaping does not mutate the base profile")
	_completes("profile_shaping_bounds")


## THE FAIRNESS TEST. Learning may change WHAT the bot does; it may never change
## how fast it sees or how well it points.
func _test_protected_keys_are_untouchable() -> void:
	var rec: Dictionary = _confident_record()
	for tier: int in 4:
		var base: Dictionary = BotProfile.of(tier)
		var shaped: Dictionary = BotAdapt.shape_profile(base, rec, 265.0)
		for k: String in BotAdapt.PROTECTED_KEYS:
			_expect(shaped.get(k) == base.get(k),
				"tier %d: learning never touches '%s'" % [tier, k])
	# And a caller that tries to smuggle one in through the base is still held to
	# the base's own value — the guard re-copies from `base`, so an adaptation rule
	# added later cannot overwrite it by accident.
	var sneaky: Dictionary = BotProfile.of(BotProfile.Tier.EASY)
	sneaky["react"] = 0.01     # a "cheating" base, honoured as given...
	var out: Dictionary = BotAdapt.shape_profile(sneaky, rec, 265.0)
	_expect(is_equal_approx(float(out["react"]), 0.01),
		"...the guard copies the base through rather than inventing a value")
	_completes("protected_keys_are_untouchable")


func _test_aim_lean_is_capped() -> void:
	var aim: Vector2 = Vector2.UP           # a vertical shot: perpendicular IS x
	# A large aim_error must not let the lean exceed the module's own ceiling.
	var leaned: Vector2 = BotAdapt.lean_aim(aim, 1.0, 1.0, 10.0)
	var delta: float = absf(aim.angle_to(leaned))
	_expect(delta <= BotAdapt.AIM_BIAS_MAX + 0.0001,
		"the lean never exceeds AIM_BIAS_MAX (%.4f rad)" % delta)
	_expect(delta > 0.0, "...but it does lean")
	# THE SECOND CAP: a precise bot (tiny aim_error) gets a tiny lean, so the
	# correction is always smaller than the scatter it is guaranteed to carry.
	var precise: Vector2 = BotAdapt.lean_aim(aim, 1.0, 1.0, 0.01)
	_expect(absf(aim.angle_to(precise)) <= 0.01 + 0.0001,
		"the lean is also capped by the bot's own aim_error")
	# Direction: a right-breaking habit leans the aim toward world +x.
	_expect(BotAdapt.lean_aim(aim, 1.0, 1.0, 10.0).x > 0.0, "a right habit leans right")
	_expect(BotAdapt.lean_aim(aim, -1.0, 1.0, 10.0).x < 0.0, "a left habit leans left")
	# No habit, no confidence, or no error = no change at all.
	_expect(BotAdapt.lean_aim(aim, 0.0, 1.0, 10.0).is_equal_approx(aim), "no habit, no lean")
	_expect(BotAdapt.lean_aim(aim, 1.0, 0.0, 10.0).is_equal_approx(aim), "no confidence, no lean")
	_expect(BotAdapt.lean_aim(aim, 1.0, 1.0, 0.0).is_equal_approx(aim), "no error budget, no lean")
	_expect(is_equal_approx(BotAdapt.lean_aim(aim, 1.0, 1.0, 10.0).length(), 1.0),
		"the leaned aim is still a unit vector")
	_completes("aim_lean_is_capped")


func _test_slot_preference_needs_an_edge() -> void:
	var rec: Dictionary = _confident_record()   # slot 1 lands 90%, slot 0 lands 10%
	var bb: Dictionary = {"cooldowns": [0.0, 0.0, 0.0, 0.0, 0.0],
		"slot_affordable": [true, true, true, true, true]}
	_expect(BotAdapt.preferred_slot(rec, 0, bb) == 1,
		"a slot that lands far more often is preferred over one that does not")
	_expect(BotAdapt.preferred_slot(rec, 1, bb) == -1,
		"already casting the favourite = no change")
	# The margin: two slots that land equally often must NOT trigger a swap.
	var flat: Dictionary = _confident_record()
	flat["slot_hits"] = [8, 9, 2, 2, 2]
	_expect(BotAdapt.preferred_slot(flat, 0, bb) == -1,
		"a 10-point difference is noise, not a preference")
	# The learned preference may never reach past a cooldown or an empty mana bar —
	# both are read from the same blackboard the brain used.
	var on_cd: Dictionary = {"cooldowns": [0.0, 3.0, 0.0, 0.0, 0.0],
		"slot_affordable": [true, true, true, true, true]}
	_expect(BotAdapt.preferred_slot(rec, 0, on_cd) == -1,
		"a favourite on cooldown is not substituted in")
	var broke: Dictionary = {"cooldowns": [0.0, 0.0, 0.0, 0.0, 0.0],
		"slot_affordable": [true, false, true, true, true]}
	_expect(BotAdapt.preferred_slot(rec, 0, broke) == -1,
		"an unaffordable favourite is not substituted in")
	# End to end through shape_intent.
	var intent: Dictionary = {"aim": Vector2.RIGHT, "cast_slot": 0}
	var shaped: Dictionary = BotAdapt.shape_intent(intent, bb, rec,
		BotProfile.of(BotProfile.Tier.NORMAL))
	_expect(int(shaped.get("cast_slot", -1)) == 1, "shape_intent applies the swap")
	# ...and it may NEVER invent a cast the scorer declined to make.
	var quiet: Dictionary = BotAdapt.shape_intent({"aim": Vector2.RIGHT}, bb, rec,
		BotProfile.of(BotProfile.Tier.NORMAL))
	_expect(not quiet.has("cast_slot"),
		"a frame with no cast stays a frame with no cast")
	_completes("slot_preference_needs_an_edge")


func _test_guard_bait() -> void:
	var rec: Dictionary = _confident_record()   # guards 40% of the time
	var prof: Dictionary = BotProfile.of(BotProfile.Tier.NORMAL)
	var bb: Dictionary = {"cooldowns": [0.0, 0.0, 0.0, 0.0, 0.0],
		"slot_affordable": [true, true, true, true, true], "foe_guarding": true}
	var out: Dictionary = BotAdapt.shape_intent(
		{"aim": Vector2.RIGHT, "cast_slot": 0, "fire": true, "move": Vector2.RIGHT},
		bb, rec, prof)
	_expect(not out.has("cast_slot"), "the bot waits out a raised guard (no cast)")
	_expect(not bool(out.get("fire", false)), "...and does not swing into it")
	_expect(out.get("move") == Vector2.RIGHT, "...but keeps moving, so it circles")
	# Guard down = fight normally.
	bb["foe_guarding"] = false
	var swing: Dictionary = BotAdapt.shape_intent(
		{"aim": Vector2.RIGHT, "cast_slot": 0, "fire": true}, bb, rec, prof)
	_expect(swing.has("cast_slot"), "guard down, the bot attacks")
	# A player who does NOT guard much never triggers the read, even mid-guard.
	var rare: Dictionary = _confident_record()
	rare["guard_ticks"] = 12
	bb["foe_guarding"] = true
	var normal: Dictionary = BotAdapt.shape_intent(
		{"aim": Vector2.RIGHT, "cast_slot": 0}, bb, rare, prof)
	_expect(normal.has("cast_slot"),
		"an occasional guard is not a habit worth playing around")
	_completes("guard_bait")


func _test_anti_camp() -> void:
	var bb: Dictionary = {"self_pos": Vector2.ZERO, "foe_pos": Vector2(900.0, 0.0),
		"foe_id": 99}
	var state: Dictionary = {}
	# An offensive frame resets the clock and changes nothing.
	var armed: Dictionary = BotAdapt.anti_camp({"fire": true, "move": Vector2.ZERO},
		bb, state, 0.0)
	_expect(armed.get("move") == Vector2.ZERO, "an attacking bot is left alone")
	# Still inside the grace window: still left alone.
	var early: Dictionary = BotAdapt.anti_camp({"move": Vector2.ZERO}, bb, state, 1.0)
	_expect(early.get("move") == Vector2.ZERO, "a brief lull is not a stalemate")
	# Past CAMP_SECONDS, far out of everyone's range: walk in.
	var late: Dictionary = BotAdapt.anti_camp({"move": Vector2.ZERO}, bb, state,
		BotAdapt.CAMP_SECONDS + 0.5)
	_expect(Vector2(late.get("move")).x > 0.0, "a camping bot is pointed at the foe")
	# ...but never when the foe is already in range — that is a STANCE, and
	# overriding it would break every kiting class in the roster.
	var close_bb: Dictionary = {"self_pos": Vector2.ZERO, "foe_pos": Vector2(300.0, 0.0),
		"foe_id": 99}
	var kiting: Dictionary = BotAdapt.anti_camp({"move": Vector2.ZERO}, close_bb, state,
		BotAdapt.CAMP_SECONDS + 0.5)
	_expect(kiting.get("move") == Vector2.ZERO, "holding a spacing band is not camping")
	# No foe at all = nothing to walk toward.
	var alone: Dictionary = BotAdapt.anti_camp({"move": Vector2.ZERO},
		{"self_pos": Vector2.ZERO, "foe_pos": Vector2(900.0, 0.0), "foe_id": 0},
		state, BotAdapt.CAMP_SECONDS + 0.5)
	_expect(alone.get("move") == Vector2.ZERO, "no foe, no charge")
	# The vertical component of the brain's own move must survive the override.
	var jumping: Dictionary = BotAdapt.anti_camp({"move": Vector2(0.0, -1.0)}, bb, state,
		BotAdapt.CAMP_SECONDS + 0.5)
	_expect(Vector2(jumping.get("move")).y < 0.0, "the camp breaker keeps a wanted jump")
	_completes("anti_camp")


func _test_store_round_trip() -> void:
	BotAdapt.wipe(TEST_DIR, TEST_FILE)
	var store: Dictionary = BotAdapt.empty_store()
	var rec: Dictionary = BotAdapt.record_for(store, 5)
	rec["samples"] = 900
	rec["range_sum"] = 900.0 * 123.0
	rec["dodge_right"] = 20
	rec["slot_casts"] = [7, 0, 0, 0, 0]
	rec["slot_hits"] = [6, 0, 0, 0, 0]
	_expect(BotAdapt.save_store(store, TEST_DIR, TEST_FILE), "the store writes")
	_expect(FileAccess.file_exists(TEST_DIR + "/" + TEST_FILE), "...to the expected path")
	_expect(not FileAccess.file_exists(TEST_DIR + "/" + TEST_FILE + ".tmp"),
		"the atomic tmp file is renamed away, not left behind")
	var back: Dictionary = BotAdapt.load_store(TEST_DIR, TEST_FILE)
	var loaded: Dictionary = BotAdapt.record_for(back, 5)
	_expect(int(loaded["samples"]) == 900, "sample count survives the round trip")
	_expect(is_equal_approx(BotAdapt.preferred_range(loaded), 123.0),
		"the derived range survives the round trip")
	# THE JSON INT/FLOAT TRAP. Every number comes back as a float; the array fields
	# in particular must be usable as ints without the caller casting.
	_expect(int((loaded["slot_casts"] as Array)[0]) == 7, "slot arrays survive as ints")
	_expect(absf(BotAdapt.slot_hit_rate(loaded, 0) - (6.0 / 7.0)) < 0.001,
		"a hit rate computed from reloaded data is right")
	# A class that was never played comes back blank rather than missing.
	var unplayed: Dictionary = BotAdapt.record_for(back, 8)
	_expect(int(unplayed.get("samples", -1)) == 0, "an unseen class gets a blank record")
	_completes("store_round_trip")


## A file from a future (or corrupted) build must start clean, and — unlike the
## NPC-memory bug this idiom was written to avoid — must not be destroyed on read.
func _test_store_version_guard() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var path: String = TEST_DIR + "/" + TEST_FILE
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"version": 99, "by_class": {"0": {"samples": 5}}}')
	f.close()
	var out: Dictionary = BotAdapt.load_store(TEST_DIR, TEST_FILE)
	_expect(int(BotAdapt.record_for(out, 0).get("samples", -1)) == 0,
		"an unknown version starts clean")
	_expect(FileAccess.file_exists(path), "...without deleting the file it could not read")
	# A JSON number is parsed as a FLOAT: `1` arrives as `1.0`. A version check that
	# demanded TYPE_INT would reject a perfectly good file — the exact bug that once
	# wiped this project's NPC saves.
	var g: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	g.store_string('{"version": 1.0, "by_class": {"3": {"samples": 42}}}')
	g.close()
	var ok: Dictionary = BotAdapt.load_store(TEST_DIR, TEST_FILE)
	_expect(int(BotAdapt.record_for(ok, 3).get("samples", -1)) == 42,
		"a version stored as a JSON float is still accepted")
	# Garbage must not crash the game on boot.
	var h: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	h.store_string("this is not json")
	h.close()
	_expect(int(BotAdapt.record_for(BotAdapt.load_store(TEST_DIR, TEST_FILE), 0)
		.get("samples", -1)) == 0, "unparseable content starts clean")
	_completes("store_version_guard")


func _test_store_wipe() -> void:
	var store: Dictionary = BotAdapt.empty_store()
	BotAdapt.record_for(store, 2)["samples"] = 500
	BotAdapt.save_store(store, TEST_DIR, TEST_FILE)
	_expect(BotAdapt.wipe(TEST_DIR, TEST_FILE), "wipe reports success")
	_expect(not FileAccess.file_exists(TEST_DIR + "/" + TEST_FILE), "the file is gone")
	_expect(BotAdapt.wipe(TEST_DIR, TEST_FILE), "wiping nothing is still success")
	_expect(int(BotAdapt.record_for(BotAdapt.load_store(TEST_DIR, TEST_FILE), 2)
		.get("samples", -1)) == 0, "after a wipe the bot knows nothing about you")
	_completes("store_wipe")


# ---------------------------------------------------------------------------
# The controller seam. A stub brain keeps these about the PLUMBING rather than
# about the real brain's decisions — which have their own suite.
class StubBrain extends RefCounted:
	var last_profile: Dictionary = {}
	var out: Dictionary = {}
	func decide(_bb: Dictionary, profile: Dictionary) -> Dictionary:
		last_profile = profile
		return out.duplicate()


func _test_controller_no_adapt_is_stock() -> void:
	var brain := StubBrain.new()
	brain.out = {"aim": Vector2.UP, "cast_slot": 0, "move": Vector2.ZERO}
	var ctrl := BotController.new()
	ctrl.brain = brain
	ctrl.profile = BotProfile.of(BotProfile.Tier.HARD)
	# A detached body: build_blackboard returns early with no tree, which is
	# exactly the isolation this test wants.
	var intent: Dictionary = ctrl.tick(null, 0.0)
	_expect(brain.last_profile.get("aggression") == ctrl.profile.get("aggression"),
		"with no learned record the brain gets the configured profile")
	_expect(brain.last_profile.get("react") == ctrl.profile.get("react"),
		"...including the difficulty keys")
	_expect(int(intent.get("cast_slot", -1)) == 0, "the intent passes through unchanged")
	_expect(intent.get("aim") == Vector2.UP, "...aim included")
	_completes("controller_no_adapt_is_stock")


func _test_controller_adapt_is_applied() -> void:
	var brain := StubBrain.new()
	brain.out = {"aim": Vector2.UP, "cast_slot": 0, "move": Vector2.ZERO}
	var ctrl := BotController.new()
	ctrl.brain = brain
	ctrl.profile = BotProfile.of(BotProfile.Tier.NORMAL)
	ctrl.adapt = _confident_record()
	ctrl.band_centre = 265.0
	var intent: Dictionary = ctrl.tick(null, 0.0)
	_expect(float(brain.last_profile["aggression"]) < float(ctrl.profile["aggression"]),
		"the brain is handed the SHAPED profile")
	_expect(brain.last_profile["react"] == ctrl.profile["react"],
		"...with the difficulty keys still stock")
	_expect(ctrl.effective_profile.has("aggression"),
		"the shaped profile is published for the debug overlay")
	# The aim was leaned toward the learned habit (right), and the slot swapped to
	# the one that keeps landing — the blackboard is empty here, so `preferred_slot`
	# sees no cooldowns and no affordability array and must treat that as permissive.
	_expect(Vector2(intent["aim"]).x > 0.0, "the aim leaned toward the learned habit")
	_expect(int(intent.get("cast_slot", -1)) == 1, "the learned favourite was substituted in")
	# Turning learning off mid-fight is an empty record, and must be instant.
	ctrl.adapt = {}
	var stock: Dictionary = ctrl.tick(null, 0.1)
	_expect(int(stock.get("cast_slot", -1)) == 0, "clearing the record reverts the bot at once")
	_expect(stock.get("aim") == Vector2.UP, "...aim included")
	_completes("controller_adapt_is_applied")


func _test_summary_is_readable() -> void:
	var lines: Array[String] = BotAdapt.summary_lines(_confident_record())
	_expect(lines.size() >= 6, "the overlay has something to say")
	var joined: String = "\n".join(lines)
	_expect(joined.contains("RIGHT"), "it names the dodge habit it learned")
	_expect(joined.contains("90"), "it names the range you like to fight at")
	_expect(joined.contains("confidence"), "it says how sure it is")
	# It must also be safe on a blank record — the overlay is on before the first
	# fight has produced any data.
	var blank: Array[String] = BotAdapt.summary_lines(BotAdapt.empty_record())
	_expect(blank.size() == lines.size(), "a blank record still renders every line")
	_expect("\n".join(blank).contains("?"), "...and says 'unknown' rather than lying")
	_completes("summary_is_readable")


func _cleanup() -> void:
	BotAdapt.wipe(TEST_DIR, TEST_FILE)
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.dir_exists("bot_adapt_test"):
		dir.remove("bot_adapt_test")
