class_name BotAdapt
extends RefCounted
## IN-SESSION ADAPTATION — "it can learn from me", honestly.
##
## ⚠ READ THIS BEFORE THE CODE. THERE IS NO MACHINE LEARNING HERE AND THERE MUST
## NOT BE. Classical AI only is a locked project rule and an LLM never goes near
## combat. What this file does is ordinary STATISTICS: it counts a handful of
## things the human visibly does, turns those counts into a few bounded numbers,
## and feeds them into knobs the bot already had. That is all "learning" means in
## this game, and calling it anything grander would be a lie the maker would
## eventually catch in a playtest.
##
## ---------------------------------------------------------------------------
## THE FAIRNESS LINE, DRAWN EXPLICITLY.
##
## `BotProfile` promises that difficulty is reaction delay and aim error and
## NEVER privileged information or stat buffs. Adaptation is the one feature that
## could quietly break that promise, so the line is drawn here in code rather
## than in a comment somewhere else:
##
##   ALLOWED — counting what a human could also count while watching you play.
##     Where you like to stand. Which way you usually roll. Whether you jump or
##     dash out of a telegraph. How often you put a guard up. Which of the bot's
##     spells keep connecting. Whether you punish it for whiffing. Every one of
##     those is a thing a human sparring partner learns about you in ten minutes,
##     and every one of them is derived from something DRAWN ON SCREEN.
##
##   FORBIDDEN — and enforced by what this file does not have a field for.
##     Your cooldowns. Your mana. Your input buffer. Which button you are
##     holding. What you are about to press. None of that is observed, none of it
##     is stored, and none of it is reachable from here: this module is handed
##     the same blackboard the brain gets, and the observation calls take plain
##     floats from the arena's own polling loop.
##
##   ALSO FORBIDDEN — learning that makes the bot SEE FASTER OR AIM TRUER.
##     `shape_profile` deliberately refuses to touch `react`, `jitter`, `p_miss`
##     or `aim_error`, and there is an assertion-shaped guard (`PROTECTED_KEYS`)
##     that strips them if a future caller passes them in. Those four are the
##     difficulty dial and they belong to the maker. Learning may change WHAT the
##     bot chooses to do; it may never change how fast it notices or how well it
##     points. A bot that got faster the longer you played it would feel like the
##     game cheating, which is the exact feeling BotProfile exists to prevent.
##
##   AND THE AIM BIAS IS CAPPED BY THE BOT'S OWN ERROR. `shape_intent` may lean
##     the aim toward the side you habitually dodge to — a real read, and one a
##     human makes. It is capped at `AIM_BIAS_MAX` AND again at the profile's own
##     `aim_error`, so the correction can never be larger than the scatter the
##     bot is guaranteed to carry. Leading your habit can never add up to
##     auto-aim.
##
## ---------------------------------------------------------------------------
## SHAPE. Everything here is a STATIC function over plain Dictionaries, exactly
## like `BotProfile` and `BotBrain`. No nodes, no tree, no autoloads — so the
## whole thing is headlessly testable and the `--script` harness can compile it
## without dragging half the game in. The arena owns the record and the file;
## this module only transforms.
##
## THE RECORD IS PER HUMAN CLASS. How you play an Arcanist and how you play a
## Brawler are different problems, and averaging them produces a bot that has
## learned nothing about either. The store is `{class_id: record}`.

# ---------------------------------------------------------------------------
# PERSISTENCE
# ---------------------------------------------------------------------------
## Bumped whenever the record shape changes. Read through the int/float guard in
## `load_store` — Godot's `JSON.parse_string` returns every number as
## TYPE_FLOAT, so a JSON `1` arrives as `1.0` and a naive `typeof(v) == TYPE_INT`
## check fails. That exact mistake once wiped this project's NPC saves; the
## idiom below is copied verbatim from the fix in `NPC._load_persisted_state`.
const STORE_VERSION: int = 1
const STORE_DIR: String = "user://bot_adapt"
const STORE_FILE: String = "human_profile.json"
const STORE_PATH: String = STORE_DIR + "/" + STORE_FILE

# ---------------------------------------------------------------------------
# CONFIDENCE
# ---------------------------------------------------------------------------
## Observation ticks before adaptation is at full strength. The arena samples at
## its own frame rate, so ~600 ticks is roughly ten seconds of an actual fight.
## Everything below scales by `confidence`, which is what stops the bot lurching
## into a whole new personality off three frames of data.
const CONFIDENCE_TICKS: float = 600.0
## Minimum casts of a slot before its hit rate is believed at all. Two casts that
## both landed is not a 100% hit rate, it is two casts.
const SLOT_MIN_SAMPLES: int = 4
## Minimum dodge observations before a directional bias is believed.
const DODGE_MIN_SAMPLES: int = 8

# ---------------------------------------------------------------------------
# BOUNDS — every one of these caps how far learning may move a knob.
# ---------------------------------------------------------------------------
## Maximum shift applied to `aggression` (a 0..1 knob). Deliberately small: this
## slides the spacing band by roughly a third of the distance between two
## adjacent difficulty tiers, so the bot re-spaces itself against you without
## turning into a different archetype.
const AGGRESSION_MAX_SHIFT: float = 0.20
## Maximum shift applied to `risk` — how willing the bot is to start a long
## channel with something on the board. Falls when you reliably punish whiffs.
const RISK_MAX_SHIFT: float = 0.22
## Maximum shift applied to `guard` skill. Rises when you crowd the bot, because
## crowding is what makes a guard worth having.
const GUARD_MAX_SHIFT: float = 0.15
## Maximum aim lean toward your habitual dodge side, in RADIANS (~4.6 degrees).
## Also capped by the profile's own `aim_error` — see the fairness note above.
const AIM_BIAS_MAX: float = 0.08
## How much better a slot's observed hit rate must be before the bot prefers it
## over the one the utility scorer picked. A margin, not a tie-break: without it
## the learned preference would override the brain's situational reasoning on
## statistical noise.
const SLOT_EDGE: float = 0.22
## Learned guard rate above which the bot starts WAITING OUT a raised guard
## instead of swinging into it. Below this it just fights.
const GUARD_BAIT_RATE: float = 0.28

# ---------------------------------------------------------------------------
# THE CAMP BREAKER (a liveness rule, not a learned one)
# ---------------------------------------------------------------------------
## Two ranged fighters that both prefer to be far away can settle at maximum
## separation and never trade a blow — measured in the bot sim as matches ending
## with literally zero damage on both sides. A human would exploit the same gap.
##
## This is a floor on ENGAGEMENT and nothing else: after `CAMP_SECONDS` with no
## offensive intent at all AND a separation past everything in any kit's range,
## the move vector is pointed at the foe. It never makes the bot smarter, faster
## or more accurate — it only makes it unwilling to stand in a stalemate, which
## is the same thing the round timer would eventually force anyway.
const CAMP_SECONDS: float = 3.0
## Past this separation nothing in any class kit reaches (the longest is the
## generic ult fallback at 640 px), so standing here is definitionally not a
## stance — it is two fighters refusing to fight.
const CAMP_ENGAGE_DISTANCE: float = 660.0

## Difficulty knobs that adaptation must never touch. See the fairness note.
const PROTECTED_KEYS: Array[String] = ["react", "jitter", "p_miss", "aim_error"]


# =========================================================================
# THE RECORD
# =========================================================================

## A blank observation record. Every field is a COUNT or a SUM, never a derived
## rate: rates are computed on read (`guard_rate`, `dodge_bias`, ...) so a record
## can be merged, halved or hand-edited without any of them going stale.
static func empty_record() -> Dictionary:
	return {
		"samples": 0,             # observation ticks contributed
		"sessions": 0,            # how many fights fed this record
		"range_sum": 0.0,         # sum of separations -> mean engage distance
		"guard_ticks": 0,         # ticks the human held a guard up
		"air_ticks": 0,           # ticks the human was off the floor
		"dodge_left": 0,          # lateral escapes under a live threat
		"dodge_right": 0,
		"dodge_vertical": 0,      # jumped out instead of stepping out
		"dodge_dash": 0,          # dashed out instead of walking out
		"slot_casts": [0, 0, 0, 0, 0],   # bot casts attempted, per kit slot
		"slot_hits": [0, 0, 0, 0, 0],    # ...that were followed by human damage
		"bot_whiffs": 0,          # bot casts that connected with nothing
		"human_punishes": 0,      # ...that the human then made the bot pay for
		"human_damage": 0,        # total damage the human dealt the bot
		"bot_damage": 0,          # total damage the bot dealt the human
	}


static func empty_store() -> Dictionary:
	return {"version": STORE_VERSION, "by_class": {}}


## The record for one human class, created on demand. Keys are STRINGS because
## that is what a JSON round-trip turns them into, and having the in-memory store
## disagree with the on-disk one is how a "learning" feature quietly forgets
## everything every time it is reloaded.
static func record_for(store: Dictionary, class_id: int) -> Dictionary:
	var by_class: Dictionary = store.get("by_class", {})
	if not (store.get("by_class") is Dictionary):
		by_class = {}
		store["by_class"] = by_class
	var key: String = str(class_id)
	if not by_class.has(key) or not (by_class[key] is Dictionary):
		by_class[key] = empty_record()
	return by_class[key]


## Fill in anything a record from an older build (or a hand-edit) is missing, so
## every reader below can index without a `.get` dance. Returns the same object.
static func repair_record(rec: Dictionary) -> Dictionary:
	var blank: Dictionary = empty_record()
	for k: Variant in blank.keys():
		if not rec.has(k):
			rec[k] = blank[k]
			continue
		# JSON hands every number back as a float and every array back untyped, so
		# the two array fields are rebuilt rather than trusted.
		if blank[k] is Array:
			var src: Variant = rec[k]
			var fixed: Array = [0, 0, 0, 0, 0]
			if src is Array:
				for i: int in mini((src as Array).size(), 5):
					fixed[i] = int((src as Array)[i])
			rec[k] = fixed
		elif blank[k] is int:
			rec[k] = int(rec[k])
		elif blank[k] is float:
			rec[k] = float(rec[k])
	return rec


# =========================================================================
# DERIVED READS — every one of these is safe on an empty record.
# =========================================================================

## 0..1 ramp on how much data is behind this record. Everything that shifts a
## knob multiplies by this, so a fresh record produces a bot that is byte-for-byte
## the shipped one.
static func confidence(rec: Dictionary) -> float:
	return clampf(float(rec.get("samples", 0)) / CONFIDENCE_TICKS, 0.0, 1.0)


## Mean separation the human chose to fight at, in pixels. -1 when unknown, which
## every caller treats as "do not adapt spacing".
static func preferred_range(rec: Dictionary) -> float:
	var n: int = int(rec.get("samples", 0))
	if n <= 0:
		return -1.0
	return float(rec.get("range_sum", 0.0)) / float(n)


## Fraction of observed time the human spent holding a guard.
static func guard_rate(rec: Dictionary) -> float:
	var n: int = int(rec.get("samples", 0))
	if n <= 0:
		return 0.0
	return clampf(float(rec.get("guard_ticks", 0)) / float(n), 0.0, 1.0)


## Fraction of observed time the human spent airborne — the "do they jump out of
## things" read.
static func air_rate(rec: Dictionary) -> float:
	var n: int = int(rec.get("samples", 0))
	if n <= 0:
		return 0.0
	return clampf(float(rec.get("air_ticks", 0)) / float(n), 0.0, 1.0)


## Which way the human habitually escapes: -1 hard left, +1 hard right, 0 no
## readable habit. Returns 0 below DODGE_MIN_SAMPLES rather than reporting a
## confident bias off two rolls.
static func dodge_bias(rec: Dictionary) -> float:
	var l: int = int(rec.get("dodge_left", 0))
	var r: int = int(rec.get("dodge_right", 0))
	var total: int = l + r
	if total < DODGE_MIN_SAMPLES:
		return 0.0
	return clampf(float(r - l) / float(total), -1.0, 1.0)


## How often the human answers a whiffed cast with damage. The term that talks a
## bot out of long channels against a player who punishes them.
static func punish_rate(rec: Dictionary) -> float:
	var whiffs: int = int(rec.get("bot_whiffs", 0))
	if whiffs < SLOT_MIN_SAMPLES:
		return 0.0
	return clampf(float(rec.get("human_punishes", 0)) / float(whiffs), 0.0, 1.0)


## Observed hit rate of one kit slot against THIS human. -1 when there is not
## enough data to have an opinion.
static func slot_hit_rate(rec: Dictionary, slot: int) -> float:
	var casts: Array = rec.get("slot_casts", [])
	var hits: Array = rec.get("slot_hits", [])
	if slot < 0 or slot >= casts.size() or slot >= hits.size():
		return -1.0
	var n: int = int(casts[slot])
	if n < SLOT_MIN_SAMPLES:
		return -1.0
	return clampf(float(hits[slot]) / float(n), 0.0, 1.0)


## The slot that keeps landing on this human, or -1 when nothing has enough data.
## This is the "which spells keep landing on them" read, and it is deliberately a
## PREFERENCE the scorer can still overrule — see `shape_intent`.
static func best_slot(rec: Dictionary) -> int:
	var best: int = -1
	var best_rate: float = -1.0
	for i: int in 5:
		var r: float = slot_hit_rate(rec, i)
		if r > best_rate:
			best_rate = r
			best = i
	return best if best_rate >= 0.0 else -1


# =========================================================================
# FEEDBACK 1 — SHAPING THE PROFILE (runs BEFORE the brain decides)
# =========================================================================

## A copy of `base` with the learned adjustments folded in. The base profile is
## never mutated: it belongs to the difficulty tier, and one bot's learning
## leaking into the tier table would be the same bug `BotProfile.of` returns a
## duplicate to avoid.
##
## `band_centre` is the middle of the bot's own preferred spacing band (the
## caller reads it out of `BotBrain.CLASS_BAND`, or passes -1 to skip the spacing
## term). It is what turns "the human likes to fight at 90 px" into a decision:
## a caster whose band is 190-340 should push AWAY from a brawler who lives at
## 90, and a brawler whose band is 40-110 should chase a kiter who lives at 400.
static func shape_profile(base: Dictionary, rec: Dictionary,
		band_centre: float = -1.0) -> Dictionary:
	var out: Dictionary = base.duplicate()
	var conf: float = confidence(rec)
	if conf <= 0.0:
		return out

	# --- SPACING. The human's habitual distance versus where this bot wants to
	# stand. Positive `pull` = the human fights CLOSER than the bot likes, so the
	# bot backs its band off (lower aggression); negative = the human camps out
	# past the band, so the bot closes (higher aggression).
	var pref: float = preferred_range(rec)
	if band_centre > 0.0 and pref >= 0.0:
		# Normalised by the band centre so the same rule reads correctly for a
		# Brawler (centre ~75) and a Cryomancer (centre ~280) without a table.
		var pull: float = clampf((band_centre - pref) / maxf(band_centre, 1.0), -1.0, 1.0)
		var shift: float = -pull * AGGRESSION_MAX_SHIFT * conf
		out["aggression"] = clampf(_f(base, "aggression") + shift, 0.0, 1.0)

	# --- CHANNEL DISCIPLINE. A human who reliably punishes a whiffed cast makes
	# long channels a bad idea; `risk` is exactly the knob that decides how much
	# clear air the brain insists on before starting one.
	var punish: float = punish_rate(rec)
	if punish > 0.0:
		out["risk"] = clampf(_f(base, "risk") - punish * RISK_MAX_SHIFT * conf, 0.0, 1.0)

	# --- GUARD. Crowding is what makes a guard worth having, so a bot that keeps
	# being fought at contact range invests in its timing. Gated on the spacing
	# read so this cannot fire for a kiter the bot never has to block.
	if band_centre > 0.0 and pref >= 0.0 and pref < band_centre * 0.75:
		out["guard"] = clampf(_f(base, "guard") + GUARD_MAX_SHIFT * conf, 0.0, 1.0)

	# --- THE FAIRNESS GUARD. Whatever the rules above did, the four difficulty
	# keys come back from the base profile untouched. This is belt-and-braces: no
	# rule above writes them today, and this makes it impossible for one added
	# later to do so by accident.
	for k: String in PROTECTED_KEYS:
		if base.has(k):
			out[k] = base[k]
		else:
			out.erase(k)
	return out


static func _f(d: Dictionary, key: String) -> float:
	return BotProfile.get_f(d, key)


# =========================================================================
# FEEDBACK 2 — SHAPING THE INTENT (runs AFTER the brain decides)
# =========================================================================

## The brain's intent, adjusted by what has been learned. Three reads, all of
## them things a human sparring partner would also make:
##
##   1. LEAD THE HABIT — lean the aim toward the side this player usually escapes
##      to. Bounded by AIM_BIAS_MAX and again by the bot's own aim error.
##   2. PREFER WHAT LANDS — if a different slot has a clearly better observed hit
##      rate against this player AND is ready and affordable, swap to it.
##   3. DO NOT SWING INTO A RAISED GUARD — a player who guards a lot, currently
##      guarding (the ring is drawn on screen), is a player to wait out.
##
## `profile` is the SHAPED profile, read only for its `aim_error` cap.
static func shape_intent(intent: Dictionary, bb: Dictionary, rec: Dictionary,
		profile: Dictionary) -> Dictionary:
	var conf: float = confidence(rec)
	if conf <= 0.0 or intent.is_empty():
		return intent
	var out: Dictionary = intent.duplicate()

	# --- 1. aim lean.
	var bias: float = dodge_bias(rec)
	var aim: Variant = out.get("aim")
	if bias != 0.0 and aim is Vector2 and (aim as Vector2).length_squared() > 0.0001:
		out["aim"] = lean_aim(aim as Vector2, bias, conf, _f(profile, "aim_error"))

	# --- 2. prefer the slot that keeps landing. Only ever a SWAP of an already
	# committed cast: this never makes the bot cast when the scorer said not to,
	# so the threshold, the cooldown gate and the channel-safety gate all still
	# own the decision to press at all.
	var chosen: int = int(out.get("cast_slot", -1))
	if chosen >= 0:
		var swap: int = preferred_slot(rec, chosen, bb)
		if swap >= 0:
			out["cast_slot"] = swap

	# --- 3. wait out a raised guard. Suppresses the ATTACK only; movement, aim
	# and dodging all continue, so the bot circles rather than freezing.
	if guard_rate(rec) >= GUARD_BAIT_RATE and bool(bb.get("foe_guarding", false)):
		out.erase("cast_slot")
		out["fire"] = false
	return out


## The aim vector leaned toward `bias` (world +x when positive). Public so the
## test suite can assert the cap directly rather than inferring it from a fight.
##
## The lean is applied along the aim's PERPENDICULAR, which is the only direction
## that changes where a shot goes: nudging a horizontal aim along x changes its
## length and nothing else. That also means a target dodging straight along the
## firing line cannot be led, which is correct — you cannot lead someone running
## at you.
static func lean_aim(aim: Vector2, bias: float, conf: float, aim_error: float) -> Vector2:
	# THE CAP, twice. Once against the module's own ceiling, once against the
	# scatter this bot is guaranteed to carry — so the correction is always
	# smaller than the error, and leading a habit can never become auto-aim.
	var cap: float = minf(AIM_BIAS_MAX, absf(aim_error))
	var lean: float = clampf(bias * conf, -1.0, 1.0) * cap
	if absf(lean) <= 0.00001:
		return aim
	var perp: Vector2 = aim.orthogonal()
	# Pick the perpendicular whose x points the way this player runs.
	if signf(perp.x) * signf(lean) < 0.0:
		perp = -perp
	return (aim.normalized() + perp.normalized() * absf(tan(lean))).normalized()


## Which slot to actually throw, given the scorer chose `chosen`. Returns -1 for
## "no change". The candidate must beat the chosen slot's observed rate by
## SLOT_EDGE, be off cooldown, and be affordable — all three read from the same
## blackboard the brain used, so this cannot reach information the brain lacked.
static func preferred_slot(rec: Dictionary, chosen: int, bb: Dictionary) -> int:
	var best: int = best_slot(rec)
	if best < 0 or best == chosen:
		return -1
	var mine: float = slot_hit_rate(rec, chosen)
	if mine < 0.0:
		mine = 0.0
	if slot_hit_rate(rec, best) - mine < SLOT_EDGE:
		return -1
	var cds: Array = bb.get("cooldowns", [])
	if best < cds.size() and float(cds[best]) > 0.0:
		return -1
	var afford: Array = bb.get("slot_affordable", [])
	if best < afford.size() and not bool(afford[best]):
		return -1
	return best


# =========================================================================
# THE CAMP BREAKER
# =========================================================================

## Refuse to stand in a stalemate. `state` is per-bot scratch owned by the caller
## (`{"last_offense_at": float}`); it is a plain Dictionary so a test can inspect
## the whole thing.
##
## Returns the intent, with `move` pointed at the foe when the bot has done
## nothing offensive for CAMP_SECONDS and is standing past every kit's range.
## Deliberately does NOT touch aim, cast or dodge — the bot walks in and then its
## own brain takes over again the moment anything is in range.
static func anti_camp(intent: Dictionary, bb: Dictionary, state: Dictionary,
		now: float) -> Dictionary:
	var offensive: bool = int(intent.get("cast_slot", -1)) >= 0 \
		or bool(intent.get("fire", false)) or bool(intent.get("swing", false))
	if offensive or not state.has("last_offense_at"):
		state["last_offense_at"] = now
		return intent
	var idle_for: float = now - float(state["last_offense_at"])
	if idle_for < CAMP_SECONDS:
		return intent
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	if int(bb.get("foe_id", 0)) == 0 or me.distance_to(foe) <= CAMP_ENGAGE_DISTANCE:
		return intent
	var out: Dictionary = intent.duplicate()
	var toward: float = signf(foe.x - me.x)
	if toward == 0.0:
		toward = 1.0
	var move: Vector2 = out.get("move", Vector2.ZERO)
	out["move"] = Vector2(toward, move.y)
	return out


# =========================================================================
# OBSERVATION — called by the arena's polling loop, once per sample.
# =========================================================================

## One frame of watching the human. Everything passed in is read off a drawn
## thing: two positions, whether the ring is up, whether the feet are on the
## floor. No inputs, no cooldowns, no intent.
static func observe_tick(rec: Dictionary, separation: float, guarding: bool,
		airborne: bool) -> void:
	rec["samples"] = int(rec.get("samples", 0)) + 1
	rec["range_sum"] = float(rec.get("range_sum", 0.0)) + separation
	if guarding:
		rec["guard_ticks"] = int(rec.get("guard_ticks", 0)) + 1
	if airborne:
		rec["air_ticks"] = int(rec.get("air_ticks", 0)) + 1


## The human broke away from something. `dir_x` is which way they went, `vertical`
## is whether they left the ground doing it, `dashed` whether they spent a dash.
## Called only while a threat is actually live, so a stroll is not filed as a
## dodge.
static func observe_dodge(rec: Dictionary, dir_x: float, vertical: bool,
		dashed: bool) -> void:
	if dir_x < 0.0:
		rec["dodge_left"] = int(rec.get("dodge_left", 0)) + 1
	elif dir_x > 0.0:
		rec["dodge_right"] = int(rec.get("dodge_right", 0)) + 1
	if vertical:
		rec["dodge_vertical"] = int(rec.get("dodge_vertical", 0)) + 1
	if dashed:
		rec["dodge_dash"] = int(rec.get("dodge_dash", 0)) + 1


## The bot committed a kit slot. Counted at the press, so the hit rate below has
## an honest denominator including the ones that went nowhere.
static func observe_bot_cast(rec: Dictionary, slot: int) -> void:
	var casts: Array = rec.get("slot_casts", [])
	if slot >= 0 and slot < casts.size():
		casts[slot] = int(casts[slot]) + 1


## The cast credited above connected. Resolved by the caller inside a short
## window after the press — see the arena's `_credit_window` for why attribution
## is a window and not a signal (the hero has no took-damage signal to hang one on).
static func observe_bot_hit(rec: Dictionary, slot: int, damage: int) -> void:
	var hits: Array = rec.get("slot_hits", [])
	if slot >= 0 and slot < hits.size():
		hits[slot] = int(hits[slot]) + 1
	rec["bot_damage"] = int(rec.get("bot_damage", 0)) + maxi(damage, 0)


## The cast connected with nothing. The denominator of `punish_rate`.
static func observe_bot_whiff(rec: Dictionary) -> void:
	rec["bot_whiffs"] = int(rec.get("bot_whiffs", 0)) + 1


## The human hurt the bot. `punished` is true when it landed inside the window
## after a whiffed bot cast, which is the "do they punish a whiff" read.
static func observe_human_damage(rec: Dictionary, damage: int, punished: bool) -> void:
	rec["human_damage"] = int(rec.get("human_damage", 0)) + maxi(damage, 0)
	if punished:
		rec["human_punishes"] = int(rec.get("human_punishes", 0)) + 1


# =========================================================================
# INSPECTION — the maker must be able to SEE what it learned.
# =========================================================================

## Human-readable lines for the in-game overlay and for the headless dump. Kept
## here rather than in the arena so the test suite can assert on the same text
## the maker reads.
static func summary_lines(rec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var conf: float = confidence(rec)
	out.append("confidence %d%%  (%d ticks, %d sessions)"
		% [int(conf * 100.0), int(rec.get("samples", 0)), int(rec.get("sessions", 0))])
	var pref: float = preferred_range(rec)
	out.append("likes to fight at %s px" % ("?" if pref < 0.0 else "%d" % int(pref)))
	out.append("guards %d%% of the time, airborne %d%%"
		% [int(guard_rate(rec) * 100.0), int(air_rate(rec) * 100.0)])
	var bias: float = dodge_bias(rec)
	var side: String = "no habit yet"
	if bias < -0.15:
		side = "usually breaks LEFT"
	elif bias > 0.15:
		side = "usually breaks RIGHT"
	out.append("%s  (%dL / %dR, %d air, %d dash)"
		% [side, int(rec.get("dodge_left", 0)), int(rec.get("dodge_right", 0)),
			int(rec.get("dodge_vertical", 0)), int(rec.get("dodge_dash", 0))])
	out.append("punishes a whiff %d%% of the time" % int(punish_rate(rec) * 100.0))
	var names: Array[String] = ["damage", "control", "answer", "payoff", "ult"]
	var slots: PackedStringArray = PackedStringArray()
	for i: int in 5:
		var r: float = slot_hit_rate(rec, i)
		slots.append("%s %s" % [names[i], "?" if r < 0.0 else "%d%%" % int(r * 100.0)])
	out.append("lands on you: " + ", ".join(slots))
	out.append("damage traded: you %d / bot %d"
		% [int(rec.get("human_damage", 0)), int(rec.get("bot_damage", 0))])
	return out


# =========================================================================
# STORE I/O — the NPC-memory idiom, copied deliberately.
# =========================================================================

## Write the store atomically: JSON to `<file>.tmp`, then a directory-relative
## rename onto the real name. On Windows that is `MoveFileEx(REPLACE_EXISTING)`,
## so a crash mid-write cannot leave a half-written file where the good one was.
## Verbatim the pattern in `NPC.save_memory`, including the relative filenames —
## `DirAccess.rename` resolves against the directory it was opened on.
static func save_store(store: Dictionary, dir_path: String = STORE_DIR,
		file_name: String = STORE_FILE) -> bool:
	var user_dir: DirAccess = DirAccess.open("user://")
	if user_dir == null:
		push_error("BotAdapt.save_store: could not open user://")
		return false
	var leaf: String = dir_path.trim_prefix("user://")
	if leaf != "" and not user_dir.dir_exists(leaf):
		user_dir.make_dir_recursive(leaf)
	store["version"] = STORE_VERSION
	var tmp_name: String = file_name + ".tmp"
	var f: FileAccess = FileAccess.open(dir_path + "/" + tmp_name, FileAccess.WRITE)
	if f == null:
		push_error("BotAdapt.save_store: could not open %s/%s" % [dir_path, tmp_name])
		return false
	f.store_string(JSON.stringify(store, "\t"))
	f.close()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("BotAdapt.save_store: could not open %s" % dir_path)
		return false
	var err: int = dir.rename(tmp_name, file_name)
	if err != OK:
		push_error("BotAdapt.save_store: rename %s -> %s failed (err=%d)"
			% [tmp_name, file_name, err])
		return false
	return true


## Read the store back, or a blank one when there is nothing readable there.
##
## ⚠ THE VERSION READ IS THE TRAP. `JSON.parse_string` returns numbers as
## TYPE_FLOAT, so a stored `1` comes back as `1.0` and a `typeof(v) == TYPE_INT`
## test fails on a perfectly good file. In this project that exact mistake once
## routed valid saves into a migration branch and wiped them. Same idiom as
## `NPC._load_persisted_state`: accept INT or FLOAT, cast through `int()`, and
## only treat a genuinely non-numeric value as unreadable.
static func load_store(dir_path: String = STORE_DIR,
		file_name: String = STORE_FILE) -> Dictionary:
	var path: String = dir_path + "/" + file_name
	if not FileAccess.file_exists(path):
		return empty_store()
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("BotAdapt.load_store: could not read %s" % path)
		return empty_store()
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("BotAdapt.load_store: %s is not a JSON object" % path)
		return empty_store()
	var dict: Dictionary = parsed
	var raw_version: Variant = dict.get("version", 0)
	var is_numeric: bool = typeof(raw_version) == TYPE_INT or typeof(raw_version) == TYPE_FLOAT
	var version: int = int(raw_version) if is_numeric else 0
	if version != STORE_VERSION:
		# No migration exists yet and none is owed: this file is a convenience, not
		# a save game. Starting clean is the correct, non-destructive answer — and
		# unlike the NPC bug, nothing here overwrites the old file until the next
		# successful save, so a future migration can still read it.
		push_warning("BotAdapt.load_store: %s is version %d, expected %d — starting fresh"
			% [path, version, STORE_VERSION])
		return empty_store()
	var by_class: Variant = dict.get("by_class", {})
	if not (by_class is Dictionary):
		return empty_store()
	for key: Variant in (by_class as Dictionary).keys():
		var rec: Variant = (by_class as Dictionary)[key]
		if rec is Dictionary:
			repair_record(rec as Dictionary)
	return {"version": STORE_VERSION, "by_class": by_class}


## Forget everything. Deletes the file rather than writing an empty one, so
## "reset" and "never played" are the same state and there is no half-wiped
## middle. Returns true when the file is gone afterwards, whether or not this
## call is what removed it.
static func wipe(dir_path: String = STORE_DIR, file_name: String = STORE_FILE) -> bool:
	var path: String = dir_path + "/" + file_name
	if not FileAccess.file_exists(path):
		return true
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return false
	dir.remove(file_name)
	return not FileAccess.file_exists(path)
