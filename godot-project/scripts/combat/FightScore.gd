class_name FightScore
extends RefCounted
## IS THIS FIGHT WORTH POSTING?
##
## Maker: *"ensure that the fights recorded are cool — have a threshold for good fights
## vs boring ones"*.
##
## A clip pipeline that shoots whatever the first roll gives it publishes a lot of
## nothing: 44% of measured bouts ended under five seconds and 31% were won with the
## winner still above 80% health (the numbers `BotMatch`'s own HP note records). Those
## are demolitions, not fights. This turns "cool" into a number so the pipeline can
## re-roll instead of shipping them.
##
## ⚠ IT SCORES WHAT A VIEWER FEELS, NOT WHAT A SIMULATION LIKES. Every axis below was
## chosen because it changes whether the clip is worth watching, and deliberately NOT
## for things that merely correlate with a long fight (total damage, number of casts) —
## a slugfest where nothing changes is boring at any length.
##
## Feed it a tally with `record_*` during the bout, then call `score()`.

## ── THE AXES, and what each is worth out of 100 ──────────────────────────────
## A fight that ends before the viewer has read the matchup is not a fight. Under
## FLOOR_SECONDS it cannot pass at all, whatever else it did.
const FLOOR_SECONDS: float = 7.0
## ...and past this it has stopped being short-form. A clip that never resolves is the
## other failure, and it is the one a "longer is better" score walks straight into.
const CEIL_SECONDS: float = 30.0
## The sweet spot the length score peaks at.
const IDEAL_SECONDS: float = 17.0
const W_LENGTH: float = 18.0

## HOW CLOSE IT WAS AT THE END. A winner limping over the line is the single strongest
## signal that the fight was worth watching.
const W_CLOSENESS: float = 26.0

## LEAD CHANGES — who was ahead on health, and how often that flipped. This is the
## comeback axis, and it is weighted highest because it is the only one that says the
## fight had a STORY rather than a slope.
const W_LEAD_CHANGES: float = 30.0
## Beyond this many changes there is no extra credit; it is a fight, not a metronome.
const LEAD_CHANGE_CAP: int = 5

## VARIETY — how much of the two kits actually appeared. A bout won with one button is
## a bad advert for a game whose whole pitch is spells.
const W_VARIETY: float = 16.0
const VARIETY_CAP: int = 8

## THE BIG MOMENT. At least one ultimate should land, or the clip has no peak.
const W_ULT: float = 10.0

## Below this a bout is not worth publishing. Tuned so an ordinary decent fight passes
## and a demolition does not; see `verdict()`.
const PASS_MARK: float = 55.0


## ── the tally ────────────────────────────────────────────────────────────────
var seconds: float = 0.0
## Final health FRACTION for each side, 0..1.
var final_hp: Array[float] = [1.0, 1.0]
## How many times the side with more health CHANGED.
var lead_changes: int = 0
## Distinct spell ids seen across both fighters.
var spells_seen: Dictionary = {}
var ults_landed: int = 0
## True if the bout ended by anything other than a clean KO/decision (a ringout, a
## timeout with nobody hurt). Recorded but not scored — see `verdict`.
var ended_early: bool = false

var _lead: int = -2      # -2 = nothing seen yet, -1 = level, 0/1 = that side ahead


## Call whenever either fighter's health changes. `a` and `b` are FRACTIONS.
func record_health(a: float, b: float) -> void:
	final_hp = [clampf(a, 0.0, 1.0), clampf(b, 0.0, 1.0)]
	var lead: int = -1
	if absf(a - b) > 0.02:            # a hair of deadband, or noise counts as drama
		lead = 0 if a > b else 1
	if _lead != -2 and lead != -1 and _lead != -1 and lead != _lead:
		lead_changes += 1
	if lead != -1 or _lead == -2:
		_lead = lead


func record_spell(id: String, is_ult: bool) -> void:
	if id != "":
		spells_seen[id] = true
	if is_ult:
		ults_landed += 1


## 0..100. See the weights above for what each axis is worth and why.
func score() -> float:
	var total: float = 0.0

	# LENGTH — a triangle peaking at IDEAL_SECONDS, zero outside the bounds.
	if seconds > FLOOR_SECONDS and seconds < CEIL_SECONDS:
		var span: float = (CEIL_SECONDS - FLOOR_SECONDS) * 0.5
		total += W_LENGTH * (1.0 - clampf(absf(seconds - IDEAL_SECONDS) / span, 0.0, 1.0))

	# CLOSENESS — the loser's remaining health is 0 by definition on a KO, so this
	# reads the WINNER's: the less they had left, the closer it was.
	var winner_hp: float = maxf(final_hp[0], final_hp[1])
	total += W_CLOSENESS * (1.0 - clampf(winner_hp, 0.0, 1.0))

	# LEAD CHANGES.
	total += W_LEAD_CHANGES * clampf(float(lead_changes) / float(LEAD_CHANGE_CAP), 0.0, 1.0)

	# VARIETY.
	total += W_VARIETY * clampf(float(spells_seen.size()) / float(VARIETY_CAP), 0.0, 1.0)

	# THE BIG MOMENT — binary, because two ults are not twice the peak.
	if ults_landed > 0:
		total += W_ULT

	return clampf(total, 0.0, 100.0)


## PASS / FAIL plus the reason, so a pipeline can log WHY it re-rolled rather than
## printing a number nobody can act on.
func verdict() -> Dictionary:
	var s: float = score()
	var why: Array[String] = []
	if seconds <= FLOOR_SECONDS:
		why.append("too short (%.1fs, floor %.1f)" % [seconds, FLOOR_SECONDS])
	if seconds >= CEIL_SECONDS:
		why.append("too long (%.1fs, ceiling %.1f)" % [seconds, CEIL_SECONDS])
	var winner_hp: float = maxf(final_hp[0], final_hp[1])
	if winner_hp > 0.75:
		why.append("a demolition (winner kept %.0f%%)" % (winner_hp * 100.0))
	if lead_changes == 0:
		why.append("never changed hands")
	if spells_seen.size() < 3:
		why.append("only %d distinct spells" % spells_seen.size())
	if ults_landed == 0:
		why.append("no ultimate landed")
	# ⚠ THE HARD FLOOR IS SEPARATE FROM THE SCORE. A three-second demolition can still
	# accumulate points on variety and length-adjacent axes; a bout under the floor is
	# never publishable regardless of what else it did.
	var passed: bool = s >= PASS_MARK and seconds > FLOOR_SECONDS and seconds < CEIL_SECONDS
	return {
		"pass": passed,
		"score": s,
		"seconds": seconds,
		"lead_changes": lead_changes,
		"spells": spells_seen.size(),
		"ults": ults_landed,
		"winner_hp": winner_hp,
		"why": why,
	}


## One line for a log or a pipeline's stdout.
func summary() -> String:
	var v: Dictionary = verdict()
	var head: String = "PASS" if bool(v["pass"]) else "REJECT"
	return "%s  score %.1f/100  %.1fs  leadchg %d  spells %d  ults %d  winner_hp %.0f%%%s" % [
		head, float(v["score"]), float(v["seconds"]), int(v["lead_changes"]),
		int(v["spells"]), int(v["ults"]), float(v["winner_hp"]) * 100.0,
		("  — " + ", ".join(v["why"])) if not (v["why"] as Array).is_empty() else "",
	]
