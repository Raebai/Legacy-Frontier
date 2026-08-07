# Run: godot --headless --path godot-project --script tools/slice_test_bot_rhythm.gd
#
# HOW BUSY IS A BOT, ACTUALLY? Nothing in this repo measured it, and "spam" has been
# a vibe in three separate playtest notes.
#
# Maker, three times now: *"arcanist is spamming its default spell"*, *"sometimes too
# difficult to watch"*, and *"the bot fights the cool downs are a little too low I
# think they are just spaming spells I want to mae it more interactive as well"*.
#
# ⚠ AND THE LAST ATTEMPT TO ANSWER IT FAILED FOR A REASON WORTH PINNING DOWN.
# A previous session raised all four pacing dials, failed `slice6_test_bot_brain`'s
# ">= 12 casts in a neutral window", backed off twice, got exactly 10 each time, and
# stopped — concluding the guard "binds harder than the dials move".
#
# It does not. THAT TEST COUNTS ONLY `cast_slot` (`if out.has("cast_slot")`). `fire`,
# `swing`, the three ability buttons, `guard` and `dash` are not counted at all. So
# `CAST_LATCH` is the single dial that assertion constrains — and it is the one that
# got raised. `FIRE_SPACING`, `ABILITY_SPACING` and the swing gate were invisible to
# it, and between them they emit far more of what a watcher reads as spam than the
# kit does, because the kit sits on 3-9 s cooldowns and they do not.
#
# THIS SUITE MEASURES THE THING THE OTHER ONE CANNOT SEE: total ACTIONS PER SECOND,
# every button, both directions. It asserts a CEILING (the complaint) and a FLOOR
# (the guard the other suite is protecting, restated in the units that matter). A
# number that has both is a rhythm; a number with only a floor is what shipped.
#
# ⚠ THE FLOOR IS NOT OPTIONAL. Every dial here can be turned up until the fight is
# calm, and a calm fight is a dead one. The maker's standing feel bar is "no dead air
# anywhere". So this file fails in BOTH directions on purpose.
#
# No bodies: two `BotBrain`s in a closed loop, positions integrated, cooldowns
# ticked. Pure math, deterministic, ~2 s. Same shape as `tools/bot_cast_probe.gd`.
#
# ⚠ NEVER `failed += _test_x()`. Failures accumulate on `_fails`; every test records a
# COMPLETION SENTINEL so one that aborts half-way fails the suite by absence.
extends SceneTree

const DT: float = 1.0 / 60.0
const DURATION: float = 20.0
const WALK_SPEED: float = 240.0
## A slot goes on this long a cooldown after a cast, so the scorer reaches around its
## kit instead of leaning on one slot. Mirrors `bot_cast_probe`.
const FAKE_COOLDOWN: float = 4.0
## The slowest real `melee_cd` in `Hero.CLASS_CONFIG`. The BODY, not the brain, is
## what actually paces a swing — see the note in `_step`.
const MELEE_BODY_COOLDOWN: float = 0.45

## Every class in the roster, so a single loud one cannot hide behind eight calm ones.
const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

## ══ THE CEILING IS ON SPELLS, AND THAT IS A DELIBERATE NARROWING ═══════════
## The maker's words were *"they are just spaming SPELLS"*, and the measurement backs
## the distinction up. Per fighter, before this change: fire 2.38/s (FIRE_SPACING was
## 0.42), abilities 1.25/s (ABILITY_SPACING 0.80), kit ~0.95/s -> about 4.6 spell
## emissions a second. After: 1.65 + 0.95 + 0.95 = 3.55, a 22% cut, and the whole
## roster now sits in a 2.85-3.60 band instead of spreading.
##
## ⚠ THE SWING IS DELIBERATELY NOT UNDER THIS CEILING. It is the single largest
## emitter the Brawler and Swordsaint have (2.85/s each, 45% of their total) and it is
## the only button with no spacing dial at all. Adding one is a one-line change and I
## did not make it, because the body already gates real damage at `melee_cd`
## (0.38-0.45) — so a brain-side floor above that would cut actual melee DPS, and the
## Brawler and Juggernaut are the bottom two of the roster at 33%. That is an
## unmeasured nerf to the two classes least able to take one, in answer to a note
## about spells. It wants the next balance sweep, not this commit.
const MAX_SPELLS_PER_SEC: float = 3.9
## The loose backstop on EVERYTHING, swings included. Set well above today's worst
## (6.45, the Brawler) so it does not fail on the melee cadence this commit chose to
## leave alone, but low enough to catch a genuine runaway.
const MAX_ACTIONS_PER_SEC: float = 7.2
## THE FLOOR. Below this a bot has gone quiet, which is the failure the `>= 12 casts`
## assertion in `slice6_test_bot_brain` exists to prevent — restated here in actions
## rather than in casts, so a change that starves the OTHER buttons is caught too.
const MIN_ACTIONS_PER_SEC: float = 0.9

const TESTS: Array[String] = [
	"no_class_exceeds_the_ceiling",
	"no_class_falls_through_the_floor",
	"the_primary_is_not_the_whole_fight",
	"the_dials_are_where_the_comments_say",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
## class id -> {"actions": int, "fire": int, "cast": int}
var _tally: Dictionary = {}


class Fighter extends RefCounted:
	var cid: int = 0
	var pos: Vector2 = Vector2.ZERO
	var mem: BotBrain.Memory = BotBrain.Memory.new()
	var cds: Array[float] = []
	var actions: int = 0
	var fires: int = 0
	var casts: int = 0
	var swings: int = 0
	var abilities: int = 0

	func _init(class_id: int, x: float, seed_value: int) -> void:
		cid = class_id
		pos = Vector2(x, 0.0)
		mem.rng.seed = seed_value
		for _i: int in BotIntent.CD_COUNT:
			cds.append(0.0)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	for cid: int in CLASS_NAMES.size():
		_tally[cid] = _run_class(cid)
	for cid: int in CLASS_NAMES.size():
		print("  %-12s  actions/s %.2f   spells/s %.2f   (fire %.2f  kit %.2f  abil %.2f  swing %.2f)"
			% [CLASS_NAMES[cid], _rate(cid, "actions"), _rate(cid, "spells"),
				_rate(cid, "fires"), _rate(cid, "casts"), _rate(cid, "abilities"),
				_rate(cid, "swings")])
	_test_ceiling()
	_test_floor()
	_test_mix()
	_test_dials()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("bot_rhythm: TEST DID NOT COMPLETE — %s (aborted part-way)" % name)
	if _fails == 0:
		print("bot rhythm tests: all PASS")
	else:
		printerr("bot rhythm tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("bot_rhythm: FAIL — %s" % what)


## One class against a mirror of itself. Mirror matches on purpose: it removes the
## opponent as a variable, so a loud number is the class and not the matchup.
func _run_class(cid: int) -> Dictionary:
	var profile: Dictionary = BotProfile.of(BotProfile.Tier.HARD)
	var a := Fighter.new(cid, -110.0, 12345)
	var b := Fighter.new(cid, 110.0, 54321)
	var t: float = 0.0
	while t < DURATION:
		_step(a, b, profile, t)
		_step(b, a, profile, t)
		t += DT
	return {
		"actions": a.actions + b.actions,
		"fires": a.fires + b.fires,
		"casts": a.casts + b.casts,
		"swings": a.swings + b.swings,
		"abilities": a.abilities + b.abilities,
		"spells": a.fires + a.casts + a.abilities + b.fires + b.casts + b.abilities,
	}


func _step(me: Fighter, foe: Fighter, profile: Dictionary, now: float) -> void:
	for i: int in me.cds.size():
		me.cds[i] = maxf(me.cds[i] - DT, 0.0)
	var affordable: Array[bool] = []
	for i: int in BotIntent.SLOT_COUNT:
		affordable.append(me.cds[i] <= 0.0)
	var bb: Dictionary = {
		"self_pos": me.pos, "self_vel": Vector2.ZERO,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0,
		"on_floor": true, "on_wall": false, "wall_dir": 0.0,
		"facing": signf(foe.pos.x - me.pos.x),
		"foe_pos": foe.pos, "foe_vel": Vector2.ZERO,
		"foe_hp_frac": 1.0, "foe_facing": signf(me.pos.x - foe.pos.x),
		"foe_id": 1,
		"threats": [], "cooldowns": me.cds,
		"slot_affordable": affordable,
		"reach": 58.0, "now": now,
		"class_id": me.cid,
	}
	var intent: Dictionary = BotBrain.decide(bb, profile, me.mem)
	if intent.has("cast_slot"):
		var s: int = int(intent["cast_slot"])
		me.casts += 1
		me.actions += 1
		me.cds[s] = FAKE_COOLDOWN
	if bool(intent.get("fire", false)):
		me.fires += 1
		me.actions += 1
	for k: StringName in [&"ability_blast", &"ability_blink", &"ability_nova"]:
		if bool(intent.get(k, false)):
			me.abilities += 1
			me.actions += 1
	if bool(intent.get(&"swing", false)):
		me.swings += 1
		me.actions += 1
		# ⚠ THE BODY GATES THE SWING AND THIS PROBE WAS NOT MODELLING IT. Every class
		# has a `melee_cd` of 0.38-0.45 and `Hero` silently early-returns a swing
		# inside it, but this fixture left `CD_SWING` at zero forever — so the brain
		# was measured pressing at its own 0.34 floor with nothing answering, and the
		# swing looked like the single biggest emitter in the game at 2.85/s.
		#
		# That number was used to argue for a new spacing dial the brain does not
		# need. It was an artifact of the harness, not a property of the game.
		me.cds[BotIntent.CD_SWING] = MELEE_BODY_COOLDOWN
	# Move, so the pair actually close and separate rather than standing at a fixed
	# range where half the kit is permanently out of its band.
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	me.pos.x += signf(move.x) * WALK_SPEED * DT


func _rate(cid: int, key: String) -> float:
	var row: Dictionary = _tally.get(cid, {})
	# Two fighters, so divide by two to get per-fighter.
	return float(int(row.get(key, 0))) / (DURATION * 2.0)


# --------------------------------------------------------------------------- 1
## THE COMPLAINT, AS A NUMBER.
func _test_ceiling() -> void:
	for cid: int in CLASS_NAMES.size():
		var sp: float = _rate(cid, "spells")
		_expect(sp <= MAX_SPELLS_PER_SEC,
			"%s throws %.2f spells/sec, over the %.2f ceiling — that is the spam the "
				% [CLASS_NAMES[cid], sp, MAX_SPELLS_PER_SEC]
				+ "maker keeps reporting, and it is measurable now rather than a vibe")
		_expect(_rate(cid, "actions") <= MAX_ACTIONS_PER_SEC,
			"%s emits %.2f actions/sec of every kind — past the runaway backstop of "
				% [CLASS_NAMES[cid], _rate(cid, "actions")] + "%.2f"
				% MAX_ACTIONS_PER_SEC)
	_completed["no_class_exceeds_the_ceiling"] = true


# --------------------------------------------------------------------------- 2
## THE GUARD, RESTATED IN THE UNITS THAT MATTER. `slice6_test_bot_brain` protects
## this in CASTS only, so a change that starved `fire`, `swing` and the abilities
## while leaving the kit alone would pass there and produce a bot that stands around
## between cooldowns. The maker's standing bar is "no dead air anywhere".
func _test_floor() -> void:
	for cid: int in CLASS_NAMES.size():
		var r: float = _rate(cid, "actions")
		_expect(r >= MIN_ACTIONS_PER_SEC,
			"%s emits only %.2f actions/sec, under the %.2f floor — it has gone "
				% [CLASS_NAMES[cid], r, MIN_ACTIONS_PER_SEC] + "quiet")
	_completed["no_class_falls_through_the_floor"] = true


# --------------------------------------------------------------------------- 3
## A fight that is 90% primary is one button pressed quickly, whatever its rate. The
## kit has to be a real share of what happens, or "less spam" just means "less".
func _test_mix() -> void:
	for cid: int in CLASS_NAMES.size():
		var fires: float = _rate(cid, "fires")
		var casts: float = _rate(cid, "casts")
		var total: float = maxf(fires + casts, 0.001)
		_expect(fires / total <= 0.80,
			"%s is %.0f%% primary — the kit has stopped being part of the fight"
				% [CLASS_NAMES[cid], 100.0 * fires / total])
	_completed["the_primary_is_not_the_whole_fight"] = true


# --------------------------------------------------------------------------- 4
## ⚠ THE ONE THAT STOPS THE LESSON BEING RE-LEARNED. If somebody reaches for
## `CAST_LATCH` again to answer a spam note, this says so — it is the ONE dial the
## `>= 12 casts` assertion constrains, and the three below it are free.
func _test_dials() -> void:
	_expect(BotBrain.FIRE_SPACING >= 0.55,
		"FIRE_SPACING is back under 0.55 — the primary is the highest-frequency "
		+ "spell emitter in the game and this is the dial that governs it")
	_expect(BotBrain.ABILITY_SPACING >= 1.0,
		"ABILITY_SPACING is back under 1.0")
	# And the guarded one is left where the other suite needs it.
	_expect(BotBrain.CAST_LATCH <= 0.60,
		"CAST_LATCH has been raised past 0.60. That is the ONE pacing dial "
		+ "`slice6_test_bot_brain`'s `>= 12 casts` assertion constrains — raising it "
		+ "is what made the last attempt at this fail three times. Reach for "
		+ "FIRE_SPACING / ABILITY_SPACING instead; they are invisible to that guard "
		+ "and they emit far more of what reads as spam.")
	_completed["the_dials_are_where_the_comments_say"] = true
