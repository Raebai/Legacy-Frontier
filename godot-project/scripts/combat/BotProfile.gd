class_name BotProfile
extends RefCounted
## THE DIFFICULTY DIAL — one table of data, and nothing else.
##
## Every difference between an Easy bot and an Impossible one lives in this file,
## as numbers. There is no second lever anywhere: no privileged information, no
## perfect aim, no stat buffs, no extra abilities, no shorter cooldowns. A bot on
## Impossible sees EXACTLY what a bot on Easy sees — the same drawn telegraphs and
## the same visible projectiles a human sees on screen — and fights with exactly
## the same kit. It is simply FASTER TO NOTICE and WRONG LESS OFTEN.
##
## That constraint is structural, not a promise: the brain is handed a blackboard
## built from what is on screen and a profile built from this table, and it has no
## other input. There is nowhere for a cheat to hide even if someone wanted one.
##
## WHY REACTION TIME IS THE RIGHT DIAL. Losing to a bot that reacted faster than
## you is a loss you understand and can train against; losing to one that had more
## health or knew where you were going to be is a loss that reads as the game
## lying. The first makes you replay the fight, the second makes you close it.
##
## WHY THERE IS A WHIFF RATE AT ALL. Reaction time on its own produces a bot that
## never misses a dodge once it has noticed — which past ~200 ms is indistinguishable
## from omniscience, because every telegraph in this game is longer than that. So
## `p_miss` is the second half of "beatable": with that probability the brain
## deliberately fumbles a given threat. The roll is taken ONCE per threat, at first
## sighting (see BotDodge.Reactions), so the bot commits to its mistake instead of
## flickering between committed and passive.
##
## THE PROFILE IS A PLAIN DICTIONARY at every boundary, like the blackboard and the
## intent. Callers can hand-build one, override two fields of a tier, or author a
## whole new row without this class knowing about it — and `get_f` / `get_b` below
## mean a partial dictionary never crashes the brain, it just falls back to Normal.

## The four shipped tiers, matching the difficulty cycle the arena already exposes.
## Ordered easiest-first so `tier + 1` is always "harder", which the tests lean on.
enum Tier { EASY, NORMAL, HARD, IMPOSSIBLE }

## ---------------------------------------------------------------------------
## EVERY NUMBER IN THIS TABLE IS REASONED AND UNPLAYTESTED. They are grouped here,
## named, so the maker retunes the whole difficulty feel in one place rather than
## hunting constants through the brain.
##
##   react     seconds from a threat APPEARING to the brain being allowed to act on
##             it. Human visual reaction to a simple stimulus is ~250 ms and to a
##             choice ~350-400 ms, so Normal sits on the honest human number and
##             Impossible (150 ms) sits just under it — fast, still not superhuman.
##   jitter    +/- randomisation of `react` per threat. A fixed delay reads as a
##             machine ticking; a varying one reads as a person. It is also what
##             stops two bots on the same tier dodging in perfect unison.
##   p_miss    probability the brain deliberately fumbles a threat (skips the
##             dodge, or takes the second-best exit). See the note above.
##   aim_error maximum aim scatter in RADIANS. NEVER zero, at any tier: no-auto-aim
##             is a locked design rule, so the bot points and can miss. 0.03 rad is
##             ~1.7 degrees — enough that a lance at range is not a guaranteed hit.
##   aggression 0..1. Pulls the preferred spacing band toward contact and raises the
##             weight of offensive slots. Low = a kiter, high = a brawler.
##   combo     0..1 "combo awareness". How much the scorer values setting up its own
##             reaction (drop a frost field, then fire lightning through it) and
##             cashing one in. At 0 the bot fights with single spells; at 1 it plays
##             the reaction matrix on purpose. This is the CLIP dial as much as the
##             difficulty one.
##   risk      0..1. Willingness to start a long channel with something on the board
##             and to hold ground near a pit. Low = only ever casts from safety.
##   guard     0..1 guard skill. Scales how accurately the brain aims for the middle
##             of ParryRing's perfect band; the remainder becomes a timing offset,
##             so a low-tier bot puts the ring up too early and eats the hit.
##   iframe    may the bot use the DASH-THROUGH-IMPACT read (dash i-frames cover the
##             hit without escaping the region)? It is the strongest read available
##             and looks like cheating when unrestricted, so it is gated to the top
##             two tiers rather than tuned.
##   period    seconds between re-scoring the ability layer. Also a cheapness knob —
##             this runs per bot per frame and the utility pass is the expensive
##             part — but mostly an anti-twitch one: a bot that re-picks its spell
##             every frame never finishes casting anything.
const TIERS: Array[Dictionary] = [
	# EASY — reads a telegraph about as fast as a distracted player, and fumbles
	# nearly half of them. Fights with its damage line and little else (combo 0.1).
	{"name": "Easy", "react": 0.38, "jitter": 0.12, "p_miss": 0.45, "aim_error": 0.20,
		"aggression": 0.35, "combo": 0.10, "risk": 0.25, "guard": 0.25,
		"iframe": false, "period": 0.45},
	# NORMAL — the honest human baseline. This is the tier every other number in the
	# brain was reasoned against.
	{"name": "Normal", "react": 0.30, "jitter": 0.09, "p_miss": 0.28, "aim_error": 0.12,
		"aggression": 0.50, "combo": 0.35, "risk": 0.45, "guard": 0.50,
		"iframe": false, "period": 0.35},
	# HARD — a good player. Starts playing the kit rather than the damage slot, and
	# gets the i-frame dash.
	{"name": "Hard", "react": 0.22, "jitter": 0.07, "p_miss": 0.12, "aim_error": 0.07,
		"aggression": 0.65, "combo": 0.70, "risk": 0.65, "guard": 0.75,
		"iframe": true, "period": 0.28},
	# IMPOSSIBLE — the ceiling, and deliberately NOT a perfect bot. It still whiffs
	# 3% of threats and still misses its aim by up to ~1.7 degrees, because the
	# top tier being unbeatable-by-construction is a worse product than the top tier
	# being merely very hard.
	{"name": "Impossible", "react": 0.15, "jitter": 0.045, "p_miss": 0.03, "aim_error": 0.03,
		"aggression": 0.80, "combo": 0.90, "risk": 0.80, "guard": 0.92,
		"iframe": true, "period": 0.22},
]


## A fresh profile dictionary for a tier. Returns a COPY: profiles get overridden
## per-bot (a cautious Impossible sparring partner, an aggressive Easy one) and a
## shared reference would let one bot's tweak leak into every other bot on the map.
static func of(tier: int) -> Dictionary:
	var t: int = clampi(tier, 0, TIERS.size() - 1)
	return TIERS[t].duplicate()


## A tier with named fields replaced. The intended way to author a matchup: the
## difficulty stays one row of the table, and the flavour is a two-key override at
## the call site rather than a fifth tier nobody can compare against the others.
static func with_overrides(tier: int, overrides: Dictionary) -> Dictionary:
	var p: Dictionary = of(tier)
	for k: Variant in overrides.keys():
		p[k] = overrides[k]
	return p


## Tier index from a name, case-insensitive; unknown names fall back to NORMAL.
## The arena's difficulty button already speaks in these words, so this is the
## adapter that keeps the brain from needing to know about that UI.
static func tier_from_name(name: String) -> int:
	var lower: String = name.to_lower()
	for i: int in range(TIERS.size()):
		if String(TIERS[i]["name"]).to_lower() == lower:
			return i
	return Tier.NORMAL


## ---------------------------------------------------------------------------
## SAFE READERS. The brain reads the profile through these and never with `[]`,
## because a caller is allowed to hand in a two-key dictionary. A missing key is
## answered from NORMAL rather than from zero: zero is a REAL value for several of
## these fields (aim_error 0 would be perfect aim, p_miss 0 a bot that never
## whiffs), so defaulting to it would silently hand out the exact cheats this file
## exists to make impossible.
static func get_f(profile: Dictionary, key: String) -> float:
	if profile.has(key):
		return float(profile[key])
	return float(TIERS[Tier.NORMAL].get(key, 0.0))


static func get_b(profile: Dictionary, key: String) -> bool:
	if profile.has(key):
		return bool(profile[key])
	return bool(TIERS[Tier.NORMAL].get(key, false))
