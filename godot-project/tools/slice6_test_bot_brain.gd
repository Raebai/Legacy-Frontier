# BotBrain / BotProfile — the utility scorer, the reflex composition, the fairness
# guarantees, and the proof that the difficulty dial actually turns.
# The brain is pure math over a dictionary, so all of it is provable headlessly with
# no scene, no physics and no bodies.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice6_test_bot_brain.gd
extends SceneTree

# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ─────────
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function, and hands the caller back the return type's zero
# value. Under a `failed += _test_x()` idiom that reads as "zero failures", so a
# suite prints all PASS while silently skipping every assertion after the dead line.
# Static typing does not help. So: failures accumulate on the MEMBER `_fails` (an
# abort cannot discard them), and every test's last line records that it reached the
# end. A test that aborts part-way is missing from `_completed` and fails BY ABSENCE.
#
# That armour matters more here than usual, because this suite reaches into the kit
# tables of a file it does not own (SpellLibrary): if a spell is retuned out of a
# slot, several of these scenarios stop meaning what they say, and the sentinels are
# what turn that into a red suite instead of a quiet one.

const TESTS: Array[String] = [
	"profiles",
	"role_selection",
	"channel_gate",
	"reaction_delay",
	"dodges_planted_telegraph",
	"never_dodges_into_a_pit",
	"aim_error_present_and_bounded",
	"tier3_drop_is_wanted",
	"uses_the_whole_kit",
	"combo_setup_and_cash_in",
	"guard_lockout",
	"difficulty_dial",
	"reaches_a_foe_that_is_above_it",
	"never_stands_perfectly_still",
]

## Hero.HeroClass ids used by the scenarios below, named so a reader does not have
## to decode integers three tests deep.
const ARCANIST: int = 0
const BRAWLER: int = 2
const STORMCALLER: int = 6

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_profiles()
	_test_role_selection()
	_test_channel_gate()
	_test_reaction_delay()
	_test_dodges_planted_telegraph()
	_test_never_dodges_into_a_pit()
	_test_aim_error()
	_test_tier3_drop_is_wanted()
	_test_uses_the_whole_kit()
	_test_combo()
	_test_guard_lockout()
	_test_difficulty_dial()
	_test_reaches_a_foe_that_is_above_it()
	_test_never_stands_perfectly_still()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("BotBrain tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("BotBrain tests: all PASS")
	quit(0)
	return true


# =========================================================================
# FIXTURES
# =========================================================================

## A neutral blackboard: both fighters healthy, full mana, mid range, clear board,
## every slot ready. Each test overrides only the axis it is actually about, so a
## surprising result can only have come from that axis.
func _bb(over: Dictionary = {}) -> Dictionary:
	var bb: Dictionary = {
		"self_pos": Vector2.ZERO, "self_vel": Vector2.ZERO,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0,
		"on_floor": true, "facing": 1.0,
		"foe_pos": Vector2(200.0, 0.0), "foe_vel": Vector2.ZERO,
		"foe_hp_frac": 1.0, "foe_facing": -1.0,
		"threats": [], "cooldowns": [0.0, 0.0, 0.0, 0.0, 0.0],
		"reach": 58.0, "now": 0.0,
		"class_id": BRAWLER,
	}
	for k: Variant in over.keys():
		bb[k] = over[k]
	return bb


## A memory with a FIXED seed, so every scenario replays identically. Anything that
## reads differently between runs of this file is a real non-determinism bug in the
## brain, not test flake.
func _mem(seed_value: int = 12345) -> BotBrain.Memory:
	var m: BotBrain.Memory = BotBrain.Memory.new()
	m.rng.seed = seed_value
	return m


## A telegraph in the shape Telegraph.danger_shape() publishes, plus the `tti` the
## perception layer attaches. Circle, because that is what six of the seven enemy
## archetypes plant.
func _circle(id: int, at: Vector2, radius: float, tti: float) -> Dictionary:
	return {"id": id, "shape": "circle", "center": at, "radius": radius, "tti": tti}


func _argmax(scores: Array) -> int:
	var best: int = -1
	var best_v: float = -INF
	for i: int in range(scores.size()):
		if float(scores[i]) > best_v:
			best_v = float(scores[i])
			best = i
	return best


# =========================================================================
# TESTS
# =========================================================================

## The difficulty table is the fairness guarantee expressed as data, so the shape of
## it is worth asserting directly: harder tiers must be faster and more accurate, and
## NO tier may ever be handed perfect aim or a zero whiff rate.
func _test_profiles() -> void:
	for t: int in range(1, BotProfile.TIERS.size()):
		var lo: Dictionary = BotProfile.of(t - 1)
		var hi: Dictionary = BotProfile.of(t)
		_expect(float(hi["react"]) < float(lo["react"]),
			"tier %d reacts faster than tier %d" % [t, t - 1])
		_expect(float(hi["p_miss"]) < float(lo["p_miss"]),
			"tier %d whiffs less than tier %d" % [t, t - 1])
		_expect(float(hi["aim_error"]) < float(lo["aim_error"]),
			"tier %d aims tighter than tier %d" % [t, t - 1])
	for t: int in range(BotProfile.TIERS.size()):
		var p: Dictionary = BotProfile.of(t)
		# The two numbers that would silently become cheats if they ever hit zero.
		_expect(float(p["aim_error"]) > 0.0, "tier %d still has aim error (no auto-aim)" % t)
		_expect(float(p["p_miss"]) > 0.0, "tier %d still whiffs sometimes (beatable)" % t)
	# A partial profile must not crash the readers, and must fall back to Normal
	# rather than to zero — zero is a REAL value for these fields.
	var partial: Dictionary = {"react": 0.1}
	_expect(is_equal_approx(BotProfile.get_f(partial, "react"), 0.1),
		"a supplied field is read back")
	_expect(is_equal_approx(BotProfile.get_f(partial, "p_miss"),
		float(BotProfile.TIERS[BotProfile.Tier.NORMAL]["p_miss"])),
		"a missing field falls back to NORMAL, not to zero")
	_completed["profiles"] = true


## THE HEADLINE CLAIM: the bot picks a slot by SITUATION, not by habit. Four
## scenarios, four different winners, one kit.
func _test_role_selection() -> void:
	var prof: Dictionary = BotProfile.of(BotProfile.Tier.HARD)

	# 1. Nothing special is happening -> the damage line.
	var neutral: Array = BotBrain.score_slots(_bb(), prof, _mem(), 0.0, 0.0, 99.0)
	_expect(_argmax(neutral) == BotBrain.ROLE_DAMAGE,
		"neutral board -> damage line (got slot %d)" % _argmax(neutral))

	# 2. The foe is CHARGING me -> zone them. Control's whole term is `closing`.
	#
	# ⚠ ASKED OF THE ARCANIST, NOT THE BRAWLER (the fixture default), and the switch is
	# the point rather than a workaround. With a three-button hand each class carries
	# ONE utility spell chosen from control / answer / payoff, so "zone them" is only a
	# question you can ask of a class that actually brought a zone. The Arcanist is the
	# ranged zoner and carries the Blizzard field; the Brawler carries the Rock Wall,
	# which is an ANSWER and which the range gate correctly refuses at 200 px — you do
	# not drop a wall three body-lengths away. Asking the Brawler to zone would be
	# asserting that the scorer should ignore what the class is holding.
	var zoner_neutral: Array = BotBrain.score_slots(_bb({"class_id": ARCANIST}),
		prof, _mem(), 0.0, 0.0, 99.0)
	var closing_bb: Dictionary = _bb({"class_id": ARCANIST, "foe_vel": Vector2(-320.0, 0.0)})
	var closing: Array = BotBrain.score_slots(closing_bb, prof, _mem(), 0.0, 0.4, 99.0)
	_expect(_argmax(closing) == BotBrain.ROLE_UTILITY,
		"closing foe -> the zoner's control slot (got slot %d)" % _argmax(closing))
	_expect(float(closing[BotBrain.ROLE_UTILITY]) > float(zoner_neutral[BotBrain.ROLE_UTILITY]),
		"control scores higher against a closing foe than a stationary one")
	# ...and the SCORER IS FOLLOWING THE AUTHORED ROLE, not the slot number: the same
	# slot index on the Brawler holds an escape, so a closing foe must NOT make it the
	# top pick the way it does for the zoner.
	_expect(String(BotIntent.role_for(ARCANIST, BotBrain.ROLE_UTILITY)) == "control"
			and String(BotIntent.role_for(BRAWLER, BotBrain.ROLE_UTILITY)) == "answer",
		"the two classes really do put different roles in the same slot")

	# 3. Hurt, and something is in my face -> the get-out.
	var cornered_bb: Dictionary = _bb({"self_hp_frac": 0.15, "foe_pos": Vector2(60.0, 0.0)})
	var cornered: Array = BotBrain.score_slots(cornered_bb, prof, _mem(), 0.0, 0.9, 99.0)
	_expect(_argmax(cornered) == BotBrain.ROLE_ANSWER,
		"low HP under pressure -> the answer/escape slot (got slot %d)" % _argmax(cornered))

	# 4. The kill is there and the board is clear -> the ult. This is the one that
	# proves the ult is SAVED rather than dumped: same kit, same ranges, and the only
	# things that changed are the foe's health and that they are committing.
	var finish_bb: Dictionary = _bb({"foe_hp_frac": 0.10, "foe_vel": Vector2(-320.0, 0.0)})
	var finish: Array = BotBrain.score_slots(finish_bb, prof, _mem(), 0.0, 0.0, 99.0)
	_expect(_argmax(finish) == BotBrain.ROLE_ULT,
		"nearly-dead closing foe -> the ult (got slot %d)" % _argmax(finish))
	_expect(float(finish[BotBrain.ROLE_ULT]) > float(neutral[BotBrain.ROLE_ULT]) * 2.0,
		"the ult is worth far more as a finisher than on a neutral board")
	_completed["role_selection"] = true


## "Do not start a 1.25 s channel while being rushed." A levitating channel is
## interrupted by ANY landed hit, so committing to one with something already
## resolving inside the cast time is a spell donated to the opponent.
func _test_channel_gate() -> void:
	var prof: Dictionary = BotProfile.of(BotProfile.Tier.HARD)
	# THE ARCANIST, not the default Brawler. The Brawler's ult used to be the Infernal
	# Lance, a 1.0 s levitating channel; the anti-recolour pass gave the pure-melee
	# class the Meteor Fist instead, which declares `cast_time = 0.0` and telegraphs
	# itself (a channel would lift a leaping brawler off the floor he jumps from). So
	# the Brawler no longer has a channel to gate and the fixture had to move to a
	# class that does — the Arcanist's Meteor Sigil is a 1.1 s channel.
	var bb: Dictionary = _bb({"class_id": ARCANIST, "foe_hp_frac": 0.10,
		"foe_vel": Vector2(-320.0, 0.0)})
	# The fixture must actually BE a channel, or this whole test passes vacuously
	# against a spell there was never anything to gate.
	var ult: SpellDef = SpellLibrary.build_for_class(ARCANIST)[SpellTier.ULT_SLOT]
	_expect(ult.cast_time > 0.5,
		"the gate fixture really channels (%s, cast_time %.2f)" % [ult.id, ult.cast_time])
	# Clear board: the ult (Meteor Sigil, a 1.1 s channel) is the pick.
	var clear: Array = BotBrain.score_slots(bb, prof, _mem(), 0.0, 0.0, 99.0)
	_expect(float(clear[BotBrain.ROLE_ULT]) > 0.0, "channelled ult is available on a clear board")
	# Same scenario, but something lands in 0.8 s — inside cast_time + margin.
	var pressed: Array = BotBrain.score_slots(bb, prof, _mem(), 0.0, 0.5, 0.8)
	_expect(float(pressed[BotBrain.ROLE_ULT]) == 0.0,
		"a channelled ult is gated OUT with a threat landing inside its cast time")
	# ...and the gate is specific to channels, not a blanket "stop casting": the
	# instant slots are still live in the same frame.
	_expect(float(pressed[BotBrain.ROLE_DAMAGE]) > 0.0,
		"instant slots stay available under the same threat")
	_completed["channel_gate"] = true


## Reaction delay is the difficulty dial, so it has to be real: a threat that appears
## THIS frame cannot be answered this frame, however obvious it is.
func _test_reaction_delay() -> void:
	# Jitter and whiff removed so this measures the delay and nothing else.
	var prof: Dictionary = BotProfile.with_overrides(BotProfile.Tier.NORMAL,
		{"react": 0.25, "jitter": 0.0, "p_miss": 0.0})
	var m: BotBrain.Memory = _mem()
	var threats: Array = [_circle(101, Vector2.ZERO, 60.0, 0.5)]

	var t0: Dictionary = BotBrain.decide(_bb({"threats": threats, "now": 0.0}), prof, m)
	_expect(not bool(t0.get("dash", false)),
		"a threat seen THIS frame is not answered this frame")
	var t1: Dictionary = BotBrain.decide(_bb({"threats": threats, "now": 0.24}), prof, m)
	_expect(not bool(t1.get("dash", false)),
		"still not answered one frame before the reaction delay elapses")
	var t2: Dictionary = BotBrain.decide(_bb({"threats": threats, "now": 0.26}), prof, m)
	_expect(bool(t2.get("dash", false)),
		"answered once the reaction delay has elapsed")
	# ...and a threat that goes away is forgotten, or a recycled instance id inherits
	# an already-elapsed reveal time and gets a free instant reaction.
	BotBrain.decide(_bb({"threats": [], "now": 0.30}), prof, m)
	_expect(not m.reactions.knows(101), "a vanished threat is forgotten")
	_completed["reaction_delay"] = true


## The felt win: a telegraph is planted ON the bot (which is what every archetype in
## the game does — it snapshots your position) and the bot leaves the circle.
##
## This is also the DEGENERATE case: standing exactly at the centre there is no
## "shortest way out", every direction is equal. Left unhandled the ladder returns
## `none` and the bot stands in the blast it was warned about.
func _test_dodges_planted_telegraph() -> void:
	var prof: Dictionary = BotProfile.with_overrides(BotProfile.Tier.HARD,
		{"react": 0.05, "jitter": 0.0, "p_miss": 0.0})
	var m: BotBrain.Memory = _mem()
	var threats: Array = [_circle(202, Vector2.ZERO, 60.0, 0.5)]
	BotBrain.decide(_bb({"threats": threats, "now": 0.0}), prof, m)
	var out: Dictionary = BotBrain.decide(_bb({"threats": threats, "now": 0.20}), prof, m)
	_expect(bool(out.get("dash", false)), "dashes out of a telegraph planted on itself")
	var move: Vector2 = out.get("move", Vector2.ZERO)
	_expect(absf(move.x) > 0.5, "the dash carries a movement direction (dash fires along move, not aim)")
	# Away from the foe when every direction is otherwise equal — do not dive toward
	# the person hitting you.
	_expect(move.x < 0.0, "with all exits equal it steps AWAY from the foe")
	# A cast must not be issued in the same frame as the dive.
	_expect(not out.has("cast_slot"), "the reflex layer preempts casting")
	_completed["dodges_planted_telegraph"] = true


## Never dodge out of a blast and into a pit. The exit geometry says LEFT (away from
## the foe); the pit is on the left; the bot must take the worse-but-alive exit.
func _test_never_dodges_into_a_pit() -> void:
	var prof: Dictionary = BotProfile.with_overrides(BotProfile.Tier.HARD,
		{"react": 0.05, "jitter": 0.0, "p_miss": 0.0})
	var m: BotBrain.Memory = _mem()
	var threats: Array = [_circle(303, Vector2.ZERO, 60.0, 0.5)]
	var pit: Rect2 = Rect2(-260.0, -60.0, 240.0, 200.0)   # everything to the left
	var over: Dictionary = {"threats": threats, "hazards": [pit], "now": 0.0}
	BotBrain.decide(_bb(over), prof, m)
	over["now"] = 0.20
	var out: Dictionary = BotBrain.decide(_bb(over), prof, m)
	var move: Vector2 = out.get("move", Vector2.ZERO)
	_expect(bool(out.get("dash", false)), "still commits to a dodge with a pit on one side")
	_expect(move.x > 0.0, "dodges AWAY from the pit even though that is toward the foe")
	_completed["never_dodges_into_a_pit"] = true


## No auto-aim is a locked rule, so the aim must carry a real, bounded error at every
## tier — and a harder profile must aim measurably tighter. Both halves matter: zero
## error is a homing missile, unbounded error is a bot that cannot hit anything.
func _test_aim_error() -> void:
	var truth: Vector2 = Vector2.RIGHT
	for tier: int in [BotProfile.Tier.EASY, BotProfile.Tier.IMPOSSIBLE]:
		var prof: Dictionary = BotProfile.of(tier)
		var bound: float = float(prof["aim_error"])
		var m: BotBrain.Memory = _mem(777 + tier)
		var worst: float = 0.0
		var total: float = 0.0
		var n: int = 60
		for i: int in range(n):
			# Space the calls past `period` so the aim scatter is genuinely re-sampled.
			var out: Dictionary = BotBrain.decide(_bb({"now": float(i) * 1.0}), prof, m)
			var err: float = absf(truth.angle_to(out.get("aim", Vector2.RIGHT)))
			worst = maxf(worst, err)
			total += err
		_expect(worst <= bound + 0.0001,
			"tier %d aim error stays inside its bound (%.4f <= %.4f)" % [tier, worst, bound])
		_expect(worst > 0.0, "tier %d actually misses sometimes — it is not auto-aim" % tier)
		if tier == BotProfile.Tier.EASY:
			_completed["_easy_aim_mean"] = total / float(n)
		else:
			_expect(total / float(n) < float(_completed.get("_easy_aim_mean", 99.0)),
				"a harder profile aims measurably tighter than an easier one")
	_completed["aim_error_present_and_bounded"] = true


## "A bot that only throws its damage line is not a bot."
##
## Run with the kit's REAL cooldowns ticking, because that is the only version of
## this question that means anything: with every timer pinned at zero the highest-
## scoring slot correctly wins every frame, and asserting otherwise would be
## asserting that the bot should ignore its own scoring. The honest test is whether,
## over a stretch of neutral fighting, the whole kit gets used.
func _test_uses_the_whole_kit() -> void:
	var prof: Dictionary = BotProfile.of(BotProfile.Tier.HARD)
	var m: BotBrain.Memory = _mem()
	# Straight from the class kit, so a retune over there moves this test with it
	# rather than leaving it asserting against numbers that no longer exist.
	var spells: Array = SpellLibrary.build_for_class(BRAWLER)
	# Sized from the hand, not a literal: the kit shrank from five spells to three
	# when the control scheme became three thumb buttons, and a hardcoded five here
	# would tick timers for slots the class no longer has.
	var cds: Array = []
	for _s: int in BotIntent.SLOT_COUNT:
		cds.append(0.0)
	var used: Dictionary = {}
	var casts: int = 0
	var t: float = 0.0
	var step: float = 0.30                          # just past the HARD decision period
	for i: int in range(80):
		t += step
		for s: int in range(cds.size()):
			cds[s] = maxf(float(cds[s]) - step, 0.0)
		# A FIGHT, not a freeze-frame. The foe closes and backs off, both fighters
		# wear down. Asserting kit variety against a static board would be asserting
		# that the bot should ignore its own scoring — the roles exist precisely
		# because the situation changes, so the situation has to change.
		var phase: float = float(i) * 0.7
		var dist: float = 70.0 + 190.0 * (0.5 + 0.5 * sin(phase))
		var closing: float = -250.0 if cos(phase) < 0.0 else 250.0
		var out: Dictionary = BotBrain.decide(_bb({
			"now": t, "cooldowns": cds,
			"foe_pos": Vector2(dist, 0.0), "foe_vel": Vector2(closing, 0.0),
			"self_hp_frac": 1.0 - 0.75 * (float(i) / 80.0),
			"foe_hp_frac": 1.0 - 0.85 * (float(i) / 80.0),
		}), prof, m)
		if out.has("cast_slot"):
			var slot: int = int(out["cast_slot"])
			used[slot] = int(used.get(slot, 0)) + 1
			casts += 1
			cds[slot] = float((spells[slot] as SpellDef).cooldown)
	# ⚠ 12 -> 5, ON THE MAKER'S RULING, and what this line guards is unchanged: a bot
	# must never go QUIET. It was never a claim that 12 is the right number of casts —
	# it is the floor that separates "pacing itself" from "stopped working".
	#
	# The maker asked twice for fewer casts and counted the fault out loud ("3 in a 2
	# second window"), so CAST_LATCH went 0.55 -> 1.10, which roughly halves the rate
	# by design. 5 across this 80-frame window is still unmistakably an active bot; a
	# brain that has actually stopped returns 0-2 and still fails here. The assertions
	# BELOW carry the quality claim and are untouched — it must still use every slot,
	# and it must still not lean on one.
	_expect(casts >= 5, "the bot keeps casting through a neutral fight (%d casts)" % casts)
	# ⚠ THE NUMBER MOVED BECAUSE THE HAND DID, AND THE ASSERTION GOT STRONGER, NOT
	# WEAKER. This used to read "at least four of its five slots". The hand is three
	# spells now (three thumb buttons), so the same demand — "do not lean on one line"
	# — is now EVERY slot, with no spare to skip. Written against SLOT_COUNT so the
	# next control-scheme change moves it rather than silently relaxing it.
	_expect(used.size() >= BotIntent.SLOT_COUNT,
		"it uses ALL %d of its slots, not one (used %d)"
			% [BotIntent.SLOT_COUNT, used.size()])
	var most: int = 0
	for k: Variant in used.keys():
		most = maxi(most, int(used[k]))
	# The share a single slot may take. Perfectly even across three slots is 0.33, so
	# this leaves real headroom for a bot that legitimately favours its damage line
	# while still failing a bot that has collapsed onto one button. The old ceiling was
	# 0.45 against FIVE slots (even share 0.20) — proportionally far looser than this.
	_expect(float(most) / float(maxi(casts, 1)) <= 0.55,
		"no single slot dominates its casting (worst was %d/%d)" % [most, casts])
	_completed["uses_the_whole_kit"] = true


## The combo layer, both directions, on the Stormcaller — the kit ReactionTable's
## `supercharge` row was authored for (Blizzard in control, a LIGHTNING line to fire
## through it).
func _test_combo() -> void:
	var plays: Dictionary = BotProfile.with_overrides(BotProfile.Tier.HARD, {"combo": 1.0})
	var ignores: Dictionary = BotProfile.with_overrides(BotProfile.Tier.HARD, {"combo": 0.0})
	# ⚠ THE STORMCALLER'S *COMBO HAND*, CHOSEN EXPLICITLY — it is no longer the
	# DEFAULT one, and that is a real consequence of the anti-recolour pass rather
	# than a test detail. The class still AUTHORS Blizzard in its control role, but
	# its default carried three are damage / payoff / ult (Chain Lightning,
	# Thunderclap, Heaven's Wrath): Blizzard sat in three hands at once, which is
	# exactly the duplication the maker ruled against, so the Stormcaller sheds it to
	# the Cryomancer and picks up the Thunderclap off the Brawler instead.
	#
	# `set_slot_roles` is a real, legal, player-selectable hand (four non-ult roles
	# choose three since the fourth slot landed = four per class), so this is testing a
	# configuration a player can actually build, not a fixture invented for the test.
	# Restored at the end so no later suite inherits it.
	_expect(SpellLibrary.set_slot_roles(STORMCALLER,
			["damage", "control", "payoff", "ult"]),
		"the Stormcaller's combo hand (damage / control / payoff / ult) is a legal choice")
	var bb: Dictionary = _bb({"class_id": STORMCALLER})
	# And it really holds both halves — a field to lay and a LIGHTNING line to fire
	# through it — or the two directions below are asserting nothing.
	var hand: Array = SpellLibrary.build_for_class(STORMCALLER)
	_expect(String(hand[1].id) == "blizzard", "...and that hand carries the ice field")
	_expect(int(hand[SpellTier.ULT_SLOT].element) == int(Elements.Element.LIGHTNING),
		"...and a LIGHTNING second half to fire through it")

	# SET UP — no field on the board, but the bot holds both halves. A combo-aware
	# bot lays the ice field ON PURPOSE; a combo-blind one throws its damage line.
	var aware: Array = BotBrain.score_slots(bb, plays, _mem(), 0.0, 0.0, 99.0)
	var blind: Array = BotBrain.score_slots(bb, ignores, _mem(), 0.0, 0.0, 99.0)
	_expect(_argmax(aware) == BotBrain.ROLE_CONTROL,
		"a combo-aware bot lays the field first (got slot %d)" % _argmax(aware))
	_expect(_argmax(blind) == BotBrain.ROLE_DAMAGE,
		"a combo-blind bot just throws its damage line (got slot %d)" % _argmax(blind))
	_expect(float(aware[BotBrain.ROLE_CONTROL]) > float(blind[BotBrain.ROLE_CONTROL]),
		"combo awareness is what raised the control slot")

	# CASH IN — the ice field is now live, so the LIGHTNING slots are worth more than
	# they were. This is the second half of the clip.
	var with_field: Dictionary = bb.duplicate()
	with_field["fields"] = [{"element": Elements.Element.ICE,
		"pos": Vector2(200.0, 0.0), "radius": 135.0, "mine": true}]
	var cashing: Array = BotBrain.score_slots(with_field, plays, _mem(), 0.0, 0.0, 99.0)
	# ⚠ THE PAYOFF IS THE ULT NOW. With three buttons the Stormcaller carries damage /
	# control / ult, so the LIGHTNING spell the ice field is being laid for is Tempest
	# (BEAM + LIGHTNING) in the last slot — which is exactly what SpellLibrary's kit
	# note has always said this control pick was for: "this kit sets up its own ult
	# with its control slot". The old assertion pointed at slot 3 (Thunderclap), which
	# is now this class's drop-pool reserve.
	_expect(float(cashing[BotBrain.ROLE_ULT]) > float(aware[BotBrain.ROLE_ULT]),
		"a live ice field raises the lightning ULT the field was laid for (supercharge)")

	# AVOIDANCE — ReactionTable's `ground_out` consumes a lightning beam against an
	# earth wall, so firing the line into one must be actively penalised rather than
	# merely unrewarded.
	var walled: Dictionary = bb.duplicate()
	walled["barriers"] = [{"element": Elements.Element.EARTH,
		"pos": Vector2(100.0, 0.0), "radius": 50.0}]
	var vs_wall: Array = BotBrain.score_slots(walled, plays, _mem(), 0.0, 0.0, 99.0)
	_expect(float(vs_wall[BotBrain.ROLE_DAMAGE]) < float(aware[BotBrain.ROLE_DAMAGE]),
		"a lightning line is devalued when an earth wall is on the firing line")
	_completed["combo_setup_and_cash_in"] = true


## MeleeClash's locked rule: guarding locks out attacking. A guarding frame must
## therefore be a guarding frame and nothing else — and the guard has to be PRESSED
## EARLY, because ParryRing's perfect band opens ~0.37 s into the shrink.
func _test_guard_lockout() -> void:
	var prof: Dictionary = BotProfile.with_overrides(BotProfile.Tier.IMPOSSIBLE,
		{"react": 0.02, "jitter": 0.0, "p_miss": 0.0, "guard": 1.0})
	var m: BotBrain.Memory = _mem()
	# Dash and blink refused, so the ladder has to fall through to the guard rung.
	# tti is set to the middle of the BLADE perfect band.
	var threats: Array = [_circle(404, Vector2.ZERO, 400.0, BotBrain.GUARD_BAND_BLADE)]
	var over: Dictionary = {"threats": threats, "dash_ready": false, "blink_ready": false,
		"can_parry": true, "guard_style": 0, "now": 0.0}
	BotBrain.decide(_bb(over), prof, m)
	over["now"] = 0.05
	var out: Dictionary = BotBrain.decide(_bb(over), prof, m)
	_expect(bool(out.get("guard", false)),
		"guards when the blow will arrive inside the ring's perfect band")
	_expect(not out.has("cast_slot") and not bool(out.get("fire", false)),
		"a guarding frame issues no attack — guarding locks out attacking")
	# The press is HELD across frames: it was made early on purpose, so it must not
	# evaporate on the next tick before the blow arrives.
	var held: Dictionary = BotBrain.decide(_bb({"threats": threats, "now": 0.20}), prof, m)
	_expect(bool(held.get("guard", false)), "the guard is HELD until the blow lands")
	_completed["guard_lockout"] = true


## ⭐ THE PROOF THAT THE DIFFICULTY DIAL TURNS — and the only test here that answers
## the question the whole design rests on: does changing ONLY reaction time and error
## rate produce measurably better play?
##
## Identical scenario, identical kit, identical everything except the profile row: a
## telegraph blooms on the bot with 0.45 s of wind-up left, and we count how often it
## gets out before the blow lands. Nothing else differs — no stats, no extra
## abilities, no privileged information — so any separation in the numbers can ONLY
## have come from `react`, `jitter` and `p_miss`.
func _test_difficulty_dial() -> void:
	var trials: int = 300
	var windup: float = 0.45
	var rates: Array[float] = []
	for tier: int in range(BotProfile.TIERS.size()):
		var prof: Dictionary = BotProfile.of(tier)
		var escaped: int = 0
		for trial: int in range(trials):
			var m: BotBrain.Memory = _mem(4000 + trial)   # same seeds across tiers
			var got_out: bool = false
			var t: float = 0.0
			while t < windup:
				var threats: Array = [_circle(1, Vector2.ZERO, 60.0, windup - t)]
				var out: Dictionary = BotBrain.decide(_bb({"threats": threats, "now": t}), prof, m)
				if bool(out.get("dash", false)) or bool(out.get("jump", false)) \
						or bool(out.get("guard", false)):
					got_out = true
					break
				t += 1.0 / 60.0
			if got_out:
				escaped += 1
		rates.append(float(escaped) / float(trials))
	print("  [dial] escape rate by tier: Easy %.2f  Normal %.2f  Hard %.2f  Impossible %.2f"
		% [rates[0], rates[1], rates[2], rates[3]])
	for i: int in range(1, rates.size()):
		_expect(rates[i] > rates[i - 1],
			"tier %d escapes more often than tier %d (%.2f > %.2f)"
				% [i, i - 1, rates[i], rates[i - 1]])
	# The two ends must be genuinely different kinds of opponent, not a rounding
	# difference — and the top tier must still not be perfect, because a bot that
	# never fails is not a bot anyone enjoys losing to.
	_expect(rates[3] - rates[0] > 0.30,
		"Impossible is a materially different opponent from Easy (%.2f vs %.2f)"
			% [rates[3], rates[0]])
	_expect(rates[3] < 1.0, "even Impossible still fumbles a threat sometimes (%.2f)" % rates[3])
	_completed["difficulty_dial"] = true


# =========================================================================

## A TIER-3 DROP IN THE ULT SLOT IS STILL WANTED.
##
## ⚠ THIS IS A REGRESSION TEST FOR A SILENT ZERO. `SpellGrant.TIER3_SLOT` IS
## `SpellTier.ULT_SLOT`, so a showcase drop DISPLACES the ult rather than joining it,
## and `BotBrain._facts_of` labels a drop's role `"drop"`. `score_slots` builds its
## situational weight with `match String(f.get("role", ""))` over the five authored
## role names — and `"drop"` matched none of them, so `role` kept its initial 0.0 and
## the whole slot scored `0.0 * range_fit * safety`. Every hard gate said YES and the
## slot still could not be pressed unless a combo bonus happened to carry it alone.
##
## Measured on the shipped showcase config before the fix: 8 bouts, 482 looks at the
## slot, 9 of them (2%) scoring above zero, and an ultimate landing in 1 bout of 8.
##
## THE FIXTURE IS THE ASSERTION. The drop installed here is the class's OWN ult
## SpellDef — same range, same cast time, same kind, same everything — so the only
## thing that differs between the two scores below is the ROLE STRING. If a label
## ever costs a spell its score again, this fails and says so.
func _test_tier3_drop_is_wanted() -> void:
	var prof: Dictionary = BotProfile.of(BotProfile.Tier.HARD)
	var kit: Array = SpellLibrary.build_for_class(BRAWLER)
	if kit.size() <= SpellTier.ULT_SLOT:
		_expect(false, "the Brawler kit has no ult slot to displace")
		return
	var real_ult: SpellDef = kit[SpellTier.ULT_SLOT] as SpellDef
	# The board the ult is MEANT to be wanted on — a nearly-dead foe committing —
	# so a zero is unambiguous rather than "it just was not the moment".
	var board: Dictionary = {"foe_hp_frac": 0.10, "foe_vel": Vector2(-320.0, 0.0)}
	var as_kit: Array = BotBrain.score_slots(_bb(board), prof, _mem(), 0.0, 0.0, 99.0)

	# Same spell, same board, now carried as a DROP on a real body id.
	var body: RefCounted = RefCounted.new()
	BotBrain.note_drop(body, SpellTier.ULT_SLOT, real_ult)
	var drop_bb: Dictionary = _bb(board)
	drop_bb["self_id"] = body.get_instance_id()
	var as_drop: Array = BotBrain.score_slots(drop_bb, prof, _mem(), 0.0, 0.0, 99.0)
	BotBrain.forget_drops(body)

	var kit_score: float = float(as_kit[SpellTier.ULT_SLOT])
	var drop_score: float = float(as_drop[SpellTier.ULT_SLOT])
	_expect(kit_score > 0.0,
		"the fixture is sound: the kit ult scores above zero on a finisher board")
	_expect(drop_score > 0.0,
		"a tier-3 drop in the ult slot scores above ZERO (got %.3f) — if this is 0.0 "
		% drop_score + "its role string matched no arm in score_slots and the "
		+ "showpiece can never be cast")
	_expect(is_equal_approx(drop_score, kit_score),
		"the SAME spell scores the same whether it arrived in the kit (%.3f) or as a "
		% kit_score + "drop (%.3f) — only the role label differs" % drop_score)
	_completed["tier3_drop_is_wanted"] = true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("  FAIL: %s" % what)


## REACHING SOMETHING ABOVE YOU. Maker: the Brawler petrifies an enemy in mid-air and
## then cannot touch it. See the AIR_REACH_* block in BotBrain for why every rung that
## already existed was blind to this: the brain measures 2D distance, so a statue 60 px
## straight overhead reads as CORRECT SPACING and the bot holds position and punches
## into a cone that rejects anything not roughly horizontal.
func _test_reaches_a_foe_that_is_above_it() -> void:
	var prof: Dictionary = BotProfile.with_overrides(BotProfile.Tier.HARD,
		{"react": 0.05, "jitter": 0.0, "p_miss": 0.0})

	# A foe 90 px overhead and almost aligned: this is the reported case.
	var out: Dictionary = BotBrain.decide(_bb({
		"foe_id": 7, "foe_pos": Vector2(8.0, -90.0), "now": 0.0,
	}), prof, _mem())
	_expect(bool(out.get("jump", false)),
		"jumps to reach a foe 90 px above it (the petrified-in-the-air case)")

	# ...and it does NOT slide out from under the target while rising.
	var move: Vector2 = out.get("move", Vector2.ZERO)
	_expect(absf(move.x) < 0.01,
		"inside the alignment window it jumps straight up rather than shuffling")

	# A foe at the same height is not a vertical problem and must not make it hop —
	# this is the regression that would turn every bout into a jumping contest.
	var level: Dictionary = BotBrain.decide(_bb({
		"foe_id": 7, "foe_pos": Vector2(60.0, 0.0), "now": 0.0,
	}), prof, _mem())
	_expect(not bool(level.get("jump", false)), "a foe at the same height draws no hop")

	# Above but far to the side is a WALK, not a jump — otherwise the bot hops at
	# anything standing on any terrace anywhere on the map.
	var far: Dictionary = BotBrain.decide(_bb({
		"foe_id": 7, "foe_pos": Vector2(400.0, -90.0), "now": 0.0,
	}), prof, _mem())
	_expect(not bool(far.get("jump", false)), "a foe above but far to the side draws no hop")

	# Airborne already: re-pressing would spend the class's air jumps instantly and
	# cap the climb LOWER than one committed jump reaches.
	var midair: Dictionary = BotBrain.decide(_bb({
		"foe_id": 7, "foe_pos": Vector2(8.0, -90.0), "on_floor": false, "now": 0.0,
	}), prof, _mem())
	_expect(not bool(midair.get("jump", false)), "does not re-press the jump mid-arc")

	# Spaced, or it vibrates under the ledge. Same memory, immediately after a hop.
	var m: BotBrain.Memory = _mem()
	BotBrain.decide(_bb({"foe_id": 7, "foe_pos": Vector2(8.0, -90.0), "now": 0.0}), prof, m)
	var again: Dictionary = BotBrain.decide(_bb({
		"foe_id": 7, "foe_pos": Vector2(8.0, -90.0), "now": 0.1,
	}), prof, m)
	_expect(not bool(again.get("jump", false)),
		"one attempt, then it commits to the arc (AIR_REACH_SPACING)")

	# Above and offset beyond the alignment window: step under them first.
	var offset: Dictionary = BotBrain.decide(_bb({
		"foe_id": 7, "foe_pos": Vector2(90.0, -90.0), "now": 0.0,
	}), prof, _mem())
	_expect(offset.get("move", Vector2.ZERO).x > 0.0,
		"outside the alignment window it steps toward the target while rising")

	_completed["reaches_a_foe_that_is_above_it"] = true


## NOBODY IS EVER FULLY STILL. Maker: *"I dont think they should ever be fully standing
## still"*.
##
## The statue was a real branch, not a dropped frame: `_steer` resolves its intent to 0
## whenever the bot is INSIDE its spacing band with no committed direction — which is
## the state a well-behaved bot spends most of a fight in, because holding range is what
## the band is FOR. So the better the spacing logic worked, the more the fighter planted.
func _test_never_stands_perfectly_still() -> void:
	var prof: Dictionary = BotProfile.with_overrides(BotProfile.Tier.HARD,
		{"react": 0.05, "jitter": 0.0, "p_miss": 0.0})
	var m: BotBrain.Memory = _mem()
	# Dead centre of the Brawler's 35..70 band, nothing threatening, nowhere to be.
	var moved: int = 0
	var samples: int = 40
	for i: int in samples:
		var out: Dictionary = BotBrain.decide(_bb({
			"foe_id": 7, "foe_pos": Vector2(52.0, 0.0), "now": float(i) * 0.1,
		}), prof, m)
		if absf(out.get("move", Vector2.ZERO).x) > 0.01:
			moved += 1
	_expect(moved == samples,
		"settled in its own band, the bot still shifts its weight on every frame "
		+ "(%d of %d) — it must never plant" % [moved, samples])

	# ...and the shuffle is a SHUFFLE, not a walk. If this reads full-speed the bot
	# would drift out of the band it just worked to hold.
	var peak: float = 0.0
	for i: int in samples:
		var out2: Dictionary = BotBrain.decide(_bb({
			"foe_id": 7, "foe_pos": Vector2(52.0, 0.0), "now": float(i) * 0.1,
		}), prof, _mem())
		peak = maxf(peak, absf(out2.get("move", Vector2.ZERO).x))
	_expect(peak <= BotBrain.IDLE_JOCKEY + 0.01,
		"the settled shuffle stays under the walk (peak %.2f vs %.2f)"
			% [peak, BotBrain.IDLE_JOCKEY])

	# It must still be able to actually GO somewhere — a foe far away is a walk.
	var far: Dictionary = BotBrain.decide(_bb({
		"foe_id": 7, "foe_pos": Vector2(500.0, 0.0), "now": 0.0,
	}), prof, _mem())
	_expect(absf(far.get("move", Vector2.ZERO).x) > BotBrain.IDLE_JOCKEY,
		"a distant foe still draws a real walk, not a shuffle")
	_completed["never_stands_perfectly_still"] = true
