# Run: godot --headless --path godot-project --script tools/slice_test_bossvoice.gd
#
# DO THE NAMED THINGS ON A FLOOR ACTUALLY SPEAK — AND DOES THE FLOOR REDRAW ITSELF?
#
# Two features that shipped together because they are the same idea at two scales:
# a body with BILLING announces itself. An elite is a named event in a wave; a
# guardian is the hand that drew the floor. Neither of them had a mouth of its own.
#
# ── what this defends, in order of how expensive the bug would be ──────────────
#
#   1. **THE FLOOR REDRAW EXISTS AND IS BOUNDED.** The spec asks for the floor to
#      visibly redraw itself at boss phase transitions, "scripted, not simulated".
#      Scripted means a bounded list of strokes generated once — so this asserts
#      that a phase break produces one, that it does NOT on the intro phase, that
#      the stroke count is capped, and that `graphics_quality = LOW` genuinely
#      costs less. A redraw that costs 40 ms is not epic, it is a stutter, and the
#      CPU budget is this project's top technical risk.
#   2. **CO-OP: BOTH SCREENS GET REDRAWN.** `_apply_phase` is the ONE function both
#      the host path (`_enter_phase`) and the client path (`net_apply_phase`) run,
#      which is exactly why the redraw hangs off it. A redraw that fired only on the
#      authoritative side would read as the host lying, so the client path is
#      asserted directly.
#   3. **FOUR ARTISTS, FOUR VOICES.** `Gibberish.voice_of` reads a node's NAME, and
#      four boss scenes adopted into an arena get near-identical names — so before
#      the title-derived seed landed, the Scribble and the Illuminator were audibly
#      the same creature. This asserts they are four distinct voices and that every
#      one of them sits in the LOW pitch slice, because a guardian that rolled the
#      top band sounds like the thing it just ate.
#   4. **THE HASH-CORRELATION TRAP, WHICH THIS REPO HAS ALREADY PAID FOR ONCE.**
#      Godot's `String.hash` is DJB2-flavoured, so neighbouring inputs hash one
#      apart — and elites are seeded from spawn coordinates, which are neighbours by
#      construction. `Gibberish.seed_combine` is the fix and it is asserted over
#      hundreds of adjacent inputs, not over one lucky pair.
#   5. **THE MIX DOES NOT FLOOD.** A floor holds 25 entities. A floor-wide affix
#      rides EVERY one of them, so an undressed body must be silent — otherwise
#      sixteen mouths bury the hero's own gibberish, which is the thing the player
#      is actually listening for. Asserted on the gate itself, plus the rate limits.
#   6. **NO SECOND AUDIO POOL.** `speak_voice` is a new entry point into `Sfx`;
#      `slice_test_sfx_roster` locks the child count and this re-checks it through
#      the new door with banded voices, because the whole voice feature's one hard
#      constraint is that it rides the existing 32-voice pool.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ─────────
# Failures accumulate on the MEMBER `_fails` and each test records a COMPLETION
# SENTINEL, so a test aborted half-way by a moved member fails the suite BY ABSENCE
# rather than reading as "found zero failures". Never `failed += _test_x()`.
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
## ⚠ A PATH, AND EVERY BOSS ACCESS BELOW IS DUCK-TYPED. Naming `Boss` as a
## compile-time identifier here drags `Enemy.gd` into THIS script's compile chain,
## and `Enemy.gd` names the `Sfx` AUTOLOAD — which does not exist under `--script`.
## The result is not a clear error: the whole chain fails to compile and reports as
## "Nonexistent function '_ready'" on a boss that looks like it was built fine.
## `slice_test_bossnet.gd` carries the same rule for the same reason.
const BOSS_PATH: String = "res://scripts/combat/Boss.gd"

const GUARDIAN: String = "guardian"
const SCRIBBLE: String = "scribble"
const CARTOGRAPHER: String = "cartographer"
const ILLUMINATOR: String = "illuminator"
## THE WHOLE ROSTER, read off the table rather than restated here. It was a four-entry
## `const`, which meant a fifth artist could ship with no voice at all and this suite —
## the one whose entire job is "every boss has a mouth" — would pass. A `const` cannot
## call a function in GDScript, so this is a member initialised at instantiation.
var ALL_BOSSES: Array[String] = BossRoster.ids()

## The four beats a guardian is given. Every one of them must resolve to a real row
## for every artist — through the variant if it has one, through the generic row if
## it does not.
const BOSS_BEATS: Array[StringName] = [
	&"boss_arrive", &"boss_phase", &"boss_final", &"boss_down",
]

const TESTS: Array[String] = [
	"every_elite_affix_has_an_announce",
	"every_boss_beat_resolves_for_every_artist",
	"say_variant_falls_back_rather_than_going_silent",
	"the_four_artists_are_four_low_voices",
	"seed_combine_decorrelates_neighbours",
	"an_elite_stamps_one_mouth_on_its_body",
	"a_floor_affix_body_stays_silent",
	"two_elites_in_a_room_never_share_a_voice",
	"the_rate_limits_are_ordered",
	"speak_voice_adds_no_second_pool",
	"a_phase_break_redraws_the_page",
	"the_client_path_redraws_too",
	"the_redraw_is_bounded_and_cheaper_at_low",
	"each_artist_redraws_in_its_own_hand",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _arena: Node2D = null
var _hero: Node2D = null


class HeroStub extends Node2D:
	var hp: int = 100
	var max_hp: int = 100
	func take_damage(amount: int) -> void:
		hp = maxi(hp - amount, 0)


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


func _run() -> void:
	_arena = Node2D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_hero = HeroStub.new()
	_hero.add_to_group("hero")
	_arena.add_child(_hero)
	_hero.global_position = Vector2(500.0, 300.0)
	await process_frame

	_test_every_elite_affix_has_an_announce()
	_test_every_boss_beat_resolves_for_every_artist()
	await _test_say_variant_falls_back_rather_than_going_silent()
	_test_the_four_artists_are_four_low_voices()
	_test_seed_combine_decorrelates_neighbours()
	await _test_an_elite_stamps_one_mouth_on_its_body()
	await _test_a_floor_affix_body_stays_silent()
	await _test_two_elites_in_a_room_never_share_a_voice()
	_test_the_rate_limits_are_ordered()
	await _test_speak_voice_adds_no_second_pool()
	await _test_a_phase_break_redraws_the_page()
	await _test_the_client_path_redraws_too()
	await _test_the_redraw_is_bounded_and_cheaper_at_low()
	await _test_each_artist_redraws_in_its_own_hand()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Boss voice tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Boss voice tests: all PASS")
		quit(0)


# ------------------------------------------------------------------- fixtures
## A REAL boss, built through the function co-op replicates. A stub declaring the
## members this suite happens to read would be a fixture more generous than reality.
func _boss(bid: String) -> Node:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var e: Node = enc.build_enemy_from_data({
		"boss": true, "bid": bid, "hp": 600, "spd": 66.0, "touch": 26,
		"bscale": 1.0, "x": 900.0, "y": 300.0,
	})
	enc.free()
	_arena.add_child(e)
	return e


## A real elite, same reasoning, same construction path.
func _elite(affixes: Array, x: float = 700.0, dressed: bool = true) -> Node:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var data: Dictionary = {
		"boss": false, "arch": 1, "hp": 40, "spd": 95.0, "touch": 10,
		"tint": Color(0.9, 0.35, 0.3, 1), "tele": false, "x": x, "y": 300.0,
	}
	data["elite" if dressed else "aff"] = affixes
	var e: Node = enc.build_enemy_from_data(data)
	enc.free()
	_arena.add_child(e)
	return e


## ⚠ UNTYPED ON PURPOSE — see tools/slice_test_elites.gd. A typed `Node` parameter
## raises on the assignment itself when a test double-kills something, and a runtime
## error ABORTS the enclosing function, so the sentinel never gets recorded and the
## failure reads as an unrelated "test did not complete".
func _kill(n: Variant) -> void:
	if n != null and is_instance_valid(n) and n is Node:
		(n as Node).queue_free()


func _redraws_under(who: Node) -> Array[Node]:
	var out: Array[Node] = []
	if who == null or not is_instance_valid(who):
		return out
	for c: Node in who.get_children():
		if c is Node2D and c.get("_strokes") != null:
			out.append(c)
	return out


# ------------------------------------------------------------------- 1 · lines
## An affix whose announce row is missing does not error — `Bark.line_for` returns
## "" and the bark silently never fires, which in play is indistinguishable from
## "the hook was never wired up". So the table is swept from the REGISTRY rather
## than from a hand-written list that drifts the first time an affix is added.
func _test_every_elite_affix_has_an_announce() -> void:
	for aid: String in EliteModifier.all_ids():
		var ev := StringName("elite_" + aid)
		_expect(Bark.LINES.has(ev), "affix '%s' has an announce row (%s)" % [aid, ev])
		_expect(Bark.MOODS.has(ev), "affix '%s' announce has a mood" % aid)
		_expect(Bark.line_for(ev, 0) != "", "affix '%s' announce actually yields a line" % aid)
	# The two beats that are MECHANICS rather than colour.
	for ev2: StringName in [&"elite_herald_call", &"elite_volatile_fizz"]:
		_expect(Bark.LINES.has(ev2), "the '%s' beat has lines" % ev2)
		_expect(Bark.MOODS.has(ev2), "the '%s' beat has a mood" % ev2)
	_completes("every_elite_affix_has_an_announce")


func _test_every_boss_beat_resolves_for_every_artist() -> void:
	var voices: Dictionary = {}
	for bid: String in ALL_BOSSES:
		var b: Node = _boss(bid)
		var suffix: String = ""
		if b.has_method(&"bark_suffix"):
			suffix = String(b.call(&"bark_suffix"))
		_expect(suffix != "", "'%s' names a bark row" % bid)
		voices[suffix] = true
		for beat: StringName in BOSS_BEATS:
			var special := StringName("%s_%s" % [beat, suffix])
			# It may fall back — but for the four shipped artists it must not, or
			# they are all still saying the same three lines.
			_expect(Bark.LINES.has(special),
				"'%s' has its own '%s' row" % [bid, beat])
			_expect(Bark.MOODS.has(special), "'%s_%s' has a mood" % [beat, suffix])
		# Billing: an epithet is what separates a god from a label.
		_expect(b.has_method(&"boss_epithet"), "'%s' can be billed" % bid)
		_expect(String(b.call(&"boss_epithet")) != "", "'%s' has an epithet" % bid)
		_kill(b)
	_expect(voices.size() == ALL_BOSSES.size(),
		"the four artists speak from four different rows (%d)" % voices.size())
	_completes("every_boss_beat_resolves_for_every_artist")


## THE FALLBACK IS THE DESIGN. A fifth boss added tomorrow with no rows of its own
## must speak in the generic voice, not go silent.
func _test_say_variant_falls_back_rather_than_going_silent() -> void:
	var who := Node2D.new()
	who.name = "NamelessArtist"
	_arena.add_child(who)
	await _settle(1)
	_expect(Bark.say_variant(who, &"boss_arrive", "no_such_artist", true, 0),
		"an unauthored suffix falls back to the generic row")
	_expect(not Bark.LINES.has(&"boss_arrive_no_such_artist"),
		"...and it really was unauthored (the test is not vacuous)")
	_kill(who)
	await _settle(2)
	_completes("say_variant_falls_back_rather_than_going_silent")


# ---------------------------------------------------------------- 2 · identity
func _test_the_four_artists_are_four_low_voices() -> void:
	var lo: float = Gibberish.PITCH_BANDS[Gibberish.BAND_BOSS.x]
	var hi: float = Gibberish.PITCH_BANDS[Gibberish.BAND_BOSS.y]
	var seen: Dictionary = {}
	for bid: String in ALL_BOSSES:
		var b: Node = _boss(bid)
		_expect(b.has_meta(Bark.SEED_META), "'%s' stamped a voice seed on itself" % bid)
		var v: Dictionary = Bark.voice_of_node(b)
		var key: String = "%s|%.3f|%.4f" % [String(v["bank"]), float(v["pitch"]), float(v["gap"])]
		_expect(not seen.has(key),
			"'%s' does not share a voice with %s" % [bid, str(seen.get(key, ""))])
		seen[key] = bid
		_expect(float(v["pitch"]) >= lo and float(v["pitch"]) <= hi,
			"'%s' speaks in the low slice (%.2f, want %.2f..%.2f)"
				% [bid, float(v["pitch"]), lo, hi])
		_expect(Bark.voice_db_of(b) > 0.0, "'%s' carries billing in the mix" % bid)
		_kill(b)
	_expect(seen.size() == ALL_BOSSES.size(),
		"four artists, four voices (%d distinct)" % seen.size())
	# ...and the pin is not a flattening: two bosses in the same slice still differ.
	var a: Dictionary = Gibberish.voice_in_bands(Gibberish.seed_for("THE SCRIBBLE"), 0, 2)
	var b2: Dictionary = Gibberish.voice_in_bands(Gibberish.seed_for("THE SCRIBBLE"), 0, 2)
	_expect(str(a) == str(b2), "a banded voice is still a pure function of its seed")
	_completes("the_four_artists_are_four_low_voices")


## THE TRAP THIS FILE'S HISTORY IS BUILT ON. Adjacent inputs must produce unrelated
## voices, because everything folded into an elite's seed — spawn coordinates, an
## archetype index — is adjacent by construction.
func _test_seed_combine_decorrelates_neighbours() -> void:
	var banks: Dictionary = {}
	var pitches: Dictionary = {}
	var gaps: Dictionary = {}
	# 300 bodies one pixel apart: the worst realistic case, and the exact shape that
	# gave a whole wave three cadences between them last time.
	for i in 300:
		var s: int = Gibberish.seed_combine([700 + i, 300, 1, 40])
		var v: Dictionary = Gibberish.voice(s)
		banks[String(v["bank"])] = true
		pitches[float(v["pitch"])] = true
		gaps[snappedf(float(v["gap"]), 0.002)] = true
	_expect(banks.size() == Gibberish.BANKS.size(),
		"neighbouring seeds still reach every vowel bank (%d of %d)"
			% [banks.size(), Gibberish.BANKS.size()])
	_expect(pitches.size() >= Gibberish.PITCH_BANDS.size() - 1,
		"...and nearly every pitch band (%d)" % pitches.size())
	_expect(gaps.size() >= 20,
		"...and a real spread of cadences, not three (%d distinct)" % gaps.size())
	# Order matters, and the fold is pure.
	_expect(Gibberish.seed_combine([1, 2]) != Gibberish.seed_combine([2, 1]),
		"the fold is order-sensitive (a bare xor would not be)")
	_expect(Gibberish.seed_combine([7, 9, 11]) == Gibberish.seed_combine([7, 9, 11]),
		"the fold is pure")
	_expect(Gibberish.seed_combine([]) >= 0, "an empty fold is still a legal seed")
	_completes("seed_combine_decorrelates_neighbours")


# ------------------------------------------------------------------ 3 · elites
func _test_an_elite_stamps_one_mouth_on_its_body() -> void:
	# TWO affixes on ONE body. Two riders, and they must agree on one mouth —
	# folding the affix id into the seed would give a single body two voices.
	var e: Node = _elite([EliteModifier.KEEN, EliteModifier.INKED])
	await _settle(4)
	_expect(e.has_meta(Bark.SEED_META), "a dressed elite carries a voice seed")
	_expect(e.has_meta(Bark.BAND_META), "...and a pitch slice")
	var seeds: Dictionary = {}
	var announcers: int = 0
	for aid: String in [EliteModifier.KEEN, EliteModifier.INKED]:
		var r: Node = e.get_node_or_null(NodePath("Elite_" + aid))
		_expect(r != null, "rider Elite_%s attached" % aid)
		if r == null:
			continue
		seeds[int(r.call("elite_voice_seed"))] = true
		if float(r.get("_announce_t")) >= 0.0 or bool(r.get("_announced")):
			announcers += 1
	_expect(seeds.size() == 1,
		"one body, one mouth — both riders derive the same seed (%d)" % seeds.size())
	_expect(announcers == 1,
		"exactly one rider owns the announce (%d claimed it)" % announcers)
	var band: Vector2i = e.get_meta(Bark.BAND_META) as Vector2i
	_expect(band == Gibberish.BAND_ELITE, "an elite speaks in the elite slice")
	_kill(e)
	await _settle(2)
	_completes("an_elite_stamps_one_mouth_on_its_body")


## THE FLOOD GATE. A floor-wide affix rides EVERY body on the floor. If those bodies
## spoke, sixteen mouths would bury the hero's own gibberish — so the voice is gated
## on the `EliteMark`, i.e. on being a NAMED event rather than a rule.
func _test_a_floor_affix_body_stays_silent() -> void:
	var plain: Node = _elite([EliteModifier.INKED], 640.0, false)
	await _settle(4)
	_expect(not plain.has_node(^"EliteMark"), "a floor-affix body is undressed (fixture check)")
	_expect(plain.has_node(NodePath("Elite_" + EliteModifier.INKED)),
		"...but it really does carry the rider (the test is not vacuous)")
	_expect(not plain.has_meta(Bark.SEED_META),
		"an undressed body is given no mouth at all")
	var r: Node = plain.get_node_or_null(NodePath("Elite_" + EliteModifier.INKED))
	if r != null:
		_expect(not bool(r.call("is_named_elite")), "the rider knows it is a rule, not an elite")
		_expect(not bool(r.call("elite_voice", Gibberish.Mood.TALK, 1)),
			"...and refuses to speak when asked")
	_kill(plain)
	await _settle(2)
	_completes("a_floor_affix_body_stays_silent")


func _test_two_elites_in_a_room_never_share_a_voice() -> void:
	var a: Node = _elite([EliteModifier.QUICKENED], 700.0)
	var b: Node = _elite([EliteModifier.QUICKENED], 940.0)
	await _settle(4)
	_expect(a.has_meta(Bark.SEED_META) and b.has_meta(Bark.SEED_META),
		"both elites were given mouths")
	if a.has_meta(Bark.SEED_META) and b.has_meta(Bark.SEED_META):
		_expect(int(a.get_meta(Bark.SEED_META)) != int(b.get_meta(Bark.SEED_META)),
			"two elites in one room have different seeds")
		var va: Dictionary = Bark.voice_of_node(a)
		var vb: Dictionary = Bark.voice_of_node(b)
		_expect(str(va) != str(vb), "...and therefore different voices")
	# The announce stagger is deterministic and non-zero, so a pair spawned in one
	# wave does not speak on the same frame.
	var ra: Node = a.get_node_or_null(NodePath("Elite_" + EliteModifier.QUICKENED))
	var rb: Node = b.get_node_or_null(NodePath("Elite_" + EliteModifier.QUICKENED))
	if ra != null and rb != null:
		_expect(not is_equal_approx(float(ra.call("_announce_delay")),
				float(rb.call("_announce_delay"))),
			"the two announces are staggered")
		for r2: Node in [ra, rb]:
			var d: float = float(r2.call("_announce_delay"))
			_expect(d >= EliteRider.ANNOUNCE_BASE
					and d <= EliteRider.ANNOUNCE_BASE + EliteRider.ANNOUNCE_SPREAD,
				"the stagger stays inside its window (%.2f)" % d)
	_kill(a)
	_kill(b)
	await _settle(2)
	_completes("two_elites_in_a_room_never_share_a_voice")


## THE BUDGET, asserted as an ORDERING rather than as magic numbers: whatever the
## values are tuned to with ears on them, the room-wide gate must be tighter than a
## single elite's own gap (otherwise it does nothing), and a bubble must be gone
## before the same mouth may open again.
func _test_the_rate_limits_are_ordered() -> void:
	_expect(EliteRider.ROOM_GAP > 0.0, "there is a room-wide gate at all")
	_expect(EliteRider.ROOM_GAP < EliteRider.VOICE_GAP,
		"the room gate is tighter than one elite's own gap (%.2f vs %.2f)"
			% [EliteRider.ROOM_GAP, EliteRider.VOICE_GAP])
	_expect(EliteRider.VOICE_GAP < Bark.COOLDOWN,
		"a mouth-only beat may fire more often than a bubbled one")
	_expect(Bark.HOLD < Bark.COOLDOWN, "a line is gone before the same mouth reopens")
	_expect(EliteRider.VOICE_DB <= Gibberish.MAX_DB and EliteRider.VOICE_DB > 0.0,
		"an elite is billed but never louder than a voice may be")
	var boss_gs: GDScript = load(BOSS_PATH) as GDScript
	_expect(boss_gs != null, "the boss script is readable")
	if boss_gs != null:
		_expect(float(boss_gs.get(&"VOICE_DB")) >= EliteRider.VOICE_DB,
			"a guardian is billed over an elite")
	_completes("the_rate_limits_are_ordered")


## The whole voice feature's one hard constraint, re-checked through the NEW door.
func _test_speak_voice_adds_no_second_pool() -> void:
	var sfx: Node = root.get_node_or_null(^"Sfx")
	if sfx == null:
		# No autoload in this context: nothing to assert, and asserting nothing
		# silently is how a suite rots. Say so, and still complete.
		print("NOTE: no Sfx autoload in this --script context; pool check skipped")
		_completes("speak_voice_adds_no_second_pool")
		return
	var before: int = sfx.get_child_count()
	for i in 40:
		var v: Dictionary = Gibberish.voice_in_bands(
			Gibberish.seed_combine([i, 3, 1]), 0, 2)
		sfx.call("speak_voice", v, i % Gibberish.Mood.size(), 3, 2.0)
	await _settle(2)
	_expect(sfx.get_child_count() == before,
		"speak_voice added NO second pool (%d -> %d)" % [before, sfx.get_child_count()])
	_completes("speak_voice_adds_no_second_pool")


# ------------------------------------------------------------------ 4 · the page
func _test_a_phase_break_redraws_the_page() -> void:
	var b: Node = _boss(SCRIBBLE)
	await _settle(3)
	# The INTRO gate is not a phase break and must not redraw — otherwise the page
	# is rewritten before the fight has begun.
	b.call("_apply_phase", 1, true)
	await _settle(1)
	_expect(_redraws_under(b).is_empty(), "phase 1 does not redraw the page")
	b.call("_apply_phase", 2, true)
	await _settle(1)
	_expect(_redraws_under(b).size() == 1,
		"a phase-2 break redraws the page (%d)" % _redraws_under(b).size())
	b.call("_apply_phase", 3, true)
	await _settle(1)
	_expect(_redraws_under(b).size() >= 1, "so does a phase-3 break")
	# ...and it CLEANS UP. A redraw that outlived its own life would leave the fight
	# reading through a lattice of leftover ink.
	var page: Node = _redraws_under(b)[0]
	var life: float = float(page.get("_life"))
	_expect(life > 0.0 and life <= 1.5,
		"the redraw is a beat, not a state (%.2fs)" % life)
	_kill(b)
	await _settle(2)
	_completes("a_phase_break_redraws_the_page")


## CO-OP. `net_apply_phase` is the client's entire escalation path; a redraw that
## fired only on the host would put the two phones in different fights.
func _test_the_client_path_redraws_too() -> void:
	var b: Node = _boss(CARTOGRAPHER)
	await _settle(3)
	b.call("net_apply_phase", 2)
	await _settle(1)
	_expect(_redraws_under(b).size() == 1,
		"the CLIENT path redraws the page too (%d)" % _redraws_under(b).size())
	# ...and it draws the SAME page: the generator seed is derived from the artist
	# and the phase, never from an RNG, so two peers produce identical strokes.
	var c: Node = _boss(CARTOGRAPHER)
	await _settle(3)
	c.call("_apply_phase", 2, true)
	await _settle(1)
	var host_pages: Array[Node] = _redraws_under(c)
	var peer_pages: Array[Node] = _redraws_under(b)
	if host_pages.size() == 1 and peer_pages.size() == 1:
		_expect(int(host_pages[0].get("gen_seed")) == int(peer_pages[0].get("gen_seed")),
			"both peers generate the page from the same seed")
		_expect((host_pages[0].get("_strokes") as Array).size()
				== (peer_pages[0].get("_strokes") as Array).size(),
			"...and therefore the same number of strokes")
	_kill(b)
	_kill(c)
	await _settle(2)
	_completes("the_client_path_redraws_too")


## SCRIPTED, NOT SIMULATED — and bounded, because the CPU budget is this project's
## top technical risk and a redraw that stutters is not a redraw.
func _test_the_redraw_is_bounded_and_cheaper_at_low() -> void:
	var b: Node = _boss(ILLUMINATOR)
	await _settle(3)
	b.call("_apply_phase", 2, true)
	await _settle(1)
	var pages: Array[Node] = _redraws_under(b)
	_expect(pages.size() == 1, "the illuminator redrew (%d)" % pages.size())
	if pages.size() == 1:
		# The budget constants come off the LIVE page's own script rather than off a
		# named `Boss.PageRedraw` — see the ⚠ on BOSS_PATH.
		var gs: GDScript = pages[0].get_script() as GDScript
		var hi: int = int(gs.get(&"STROKES_HIGH"))
		var lo: int = int(gs.get(&"STROKES_LOW"))
		var n: int = (pages[0].get("_strokes") as Array).size()
		_expect(n > 0, "the page actually has strokes on it")
		# The ceiling: styles that emit several segments per stroke are still bounded
		# by a small multiple of the budget, and nothing here may be open-ended.
		_expect(n <= hi * 4, "the stroke list is bounded (%d, ceiling %d)" % [n, hi * 4])
		# Every stroke is decided at birth — a `_draw` that generated would be a
		# simulation, and would also desync two peers.
		for s in (pages[0].get("_strokes") as Array):
			_expect((s as Dictionary).has("at") and (s as Dictionary).has("w"),
				"each stroke carries its own reveal time and weight")
			break
		_expect(lo < hi, "LOW quality draws fewer strokes (%d < %d)" % [lo, hi])
		_expect(float(gs.get(&"LIFE_LOW")) < float(gs.get(&"LIFE_HIGH")),
			"...and holds the screen for less time")
	_kill(b)
	await _settle(2)
	_completes("the_redraw_is_bounded_and_cheaper_at_low")


## FOUR ARTISTS, FOUR HANDS. If they all redrew identically the beat would be a
## screen wipe with a colour swap, which is the version of this that is not worth
## having.
func _test_each_artist_redraws_in_its_own_hand() -> void:
	var styles: Dictionary = {}
	var shapes: Dictionary = {}
	for bid: String in ALL_BOSSES:
		var b: Node = _boss(bid)
		await _settle(3)
		_expect(b.has_method(&"redraw_style"), "'%s' declares a redraw hand" % bid)
		var st: String = String(b.call(&"redraw_style"))
		styles[st] = true
		b.call("_apply_phase", 2, true)
		await _settle(1)
		var pages: Array[Node] = _redraws_under(b)
		_expect(pages.size() == 1, "'%s' redrew the page" % bid)
		if pages.size() == 1:
			_expect(String(pages[0].get("style")) == st,
				"'%s' redrew in its own hand ('%s')" % [bid, st])
			shapes["%s|%d|%d" % [st, (pages[0].get("_strokes") as Array).size(),
				(pages[0].get("_blocks") as Array).size()]] = true
		_kill(b)
		await _settle(2)
	_expect(styles.size() == ALL_BOSSES.size(),
		"four artists, four hands (%d distinct styles)" % styles.size())
	_expect(shapes.size() == ALL_BOSSES.size(),
		"...and four visibly different pages (%d distinct)" % shapes.size())
	_completes("each_artist_redraws_in_its_own_hand")
