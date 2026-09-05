extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════════
## THE SCORE. HOW HIGH YOU GOT, AND HOW FAST — IN THAT ORDER, AND NOTHING ELSE.
## ═══════════════════════════════════════════════════════════════════════════════
##
## Maker, 2026-09-04: *"revamp the tower so thats its infinite and you are scored on
## like how high you get ... and the game is just who can get highest in the tower"*.
##
## Design note: docs/superpowers/specs/2026-09-04-infinite-tower-and-score.md
##
## ── ⚠ NO `class_name`, AND EVERY ENTRY POINT IS `static` ─────────────────────
## Consumers reach this file as
##     const ClimbScore := preload("res://scripts/tower/ClimbScore.gd")
## which needs no import step and therefore cannot be broken by a stale global class
## cache — the trap this repo has hit in four separate sessions (Sessions 6, 8, 9,
## and again this one). ⚠ `preload` yields the SCRIPT OBJECT, not an instance, so a
## plain `func` here would fail at RUNTIME rather than at parse time. Everything
## below is static, and a new function that is not is a bug that green tests will
## not catch.
##
## ── THE RANKING RULE, IN ONE LINE ────────────────────────────────────────────
##     peak_floor DESC, elapsed_ms ASC
##
## PEAK FLOOR is the headline because it is the maker's ask verbatim, and because it
## is the only number in this game that cannot be farmed: the sole way to raise it is
## to go somewhere you have not been. (`GameState`'s XP purse exists precisely because
## kills CAN be farmed — a score must not reintroduce what that had to solve.)
##
## TIME IS A TIEBREAK AND IS DELIBERATELY NOT PART OF THE HEADLINE. Two climbers both
## reach floor 34 and something has to separate them; time needs no explanation and
## cannot be farmed. But a VISIBLE speed component would make the optimal play "rush
## and die", which inverts the game the score is supposed to measure. As a tiebreak it
## can only ever separate equals, which is all it is for.
##
## Kills, deaths, friendly fire and elements are REJECTED as inputs and kept as facts
## on the run card. The full argument per input is in SS3.2 of the design note.
##
## ── WHERE IT LIVES ───────────────────────────────────────────────────────────
## `user://scores.json`, written by `GameState` with the same tmp-then-rename atomic
## idiom `climber.json` uses. This file is the pure half: it builds, orders, ranks,
## parses and serialises, and it touches no disk and no tree, so every rule in it is
## headless-testable (`tools/slice_test_endless.gd`).
##
## ⚠ NOTHING IS STORED TWICE. The board is a `history` array kept in ranked order;
## the personal best is `history[0]`, DERIVED. A stored "best" beside the list it is
## the best of is the drift bug this codebase has written the same warning about
## three times (`Progression`'s Growth, `GameState`'s level, `MemoryUtils`' relations).

## Board schema version. Bumped + migrated only if the shape stops being defaultable.
## ⚠ AND THE PARSER DELIBERATELY NEVER BRANCHES ON IT — same policy, and same reason,
## as `GameState.CLIMBER_SAVE_VERSION`: the M9 bug was a version check that misread a
## JSON `2` as `2.0`, decided a valid save needed migrating, and destroyed it. A
## parser that never asks the version cannot make that mistake.
const VERSION: int = 1

## How many runs the local board remembers.
##
## 25 rather than 10 or 100. Ten is short enough that a bad evening erases the record
## of a good week; a hundred is a file nobody reads and a list nobody scrolls. 25 rows
## is about a fortnight of play at this game's session length, and it is small enough
## that the whole board can be re-sorted on every insert without anyone caring.
const MAX_HISTORY: int = 25

## Keys of one record. Named rather than inlined because the wire format (SS4.1 of the
## design note) is this exact shape and a typo'd key in one of the two would be a
## silent data loss rather than an error.
const K_FLOOR: String = "peak_floor"
const K_MS: String = "elapsed_ms"
const K_CLASS: String = "hero_class"
const K_DIED: String = "died"
const K_KILLS: String = "kills"
const K_WHEN: String = "when"
const K_COOP: String = "coop"


# ═══════════════════════════════════════════════════════════════════════════════
# BUILDING A RECORD
# ═══════════════════════════════════════════════════════════════════════════════
## One finished run, frozen.
##
## `kills`, `died` and `coop` are FACTS, not score inputs — they exist so the board
## can show what a run was without the ranking rule growing a third term. `when` is a
## Unix timestamp so the row can be dated without storing a formatted string that a
## locale change would make wrong.
##
## Everything is floored at a sane minimum here rather than at the call site: a
## record is the thing that gets written to disk and compared, so it is the last
## place where "floor 0" or "negative milliseconds" can be stopped cheaply.
static func make_record(peak_floor: int, elapsed_ms: int, hero_class: int = 0,
		died: bool = false, kills: int = 0, when_unix: int = 0,
		coop: bool = false) -> Dictionary:
	return {
		K_FLOOR: maxi(peak_floor, 1),
		K_MS: maxi(elapsed_ms, 0),
		K_CLASS: maxi(hero_class, 0),
		K_DIED: died,
		K_KILLS: maxi(kills, 0),
		K_WHEN: maxi(when_unix, 0),
		K_COOP: coop,
	}


## A record read out of untrusted JSON (a save file, or one day a wire payload).
##
## ⚠ `int()` ON EVERY NUMBER. `JSON.parse_string` returns numbers as TYPE_FLOAT, so a
## stored `34` arrives as `34.0`; comparing that against an int matches nothing and
## storing it back writes `34.0` into the file. This repo has lost a save to exactly
## this once (the M9 bug) and re-hit it twice since in list form. There is no branch
## here that can be reached without a coercion.
static func parse_record(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var d: Dictionary = raw
	# A row with no floor is not a run; refusing it is what keeps a hand-edited or
	# truncated file from putting a floor-0 ghost at the bottom of the board forever.
	if not d.has(K_FLOOR):
		return {}
	return make_record(
		int(d.get(K_FLOOR, 1)), int(d.get(K_MS, 0)), int(d.get(K_CLASS, 0)),
		bool(d.get(K_DIED, false)), int(d.get(K_KILLS, 0)),
		int(d.get(K_WHEN, 0)), bool(d.get(K_COOP, false))
	)


# ═══════════════════════════════════════════════════════════════════════════════
# THE RANKING RULE — one function, and everything else calls it
# ═══════════════════════════════════════════════════════════════════════════════
## Does `a` outrank `b`? Higher floor wins; equal floors, faster wins; still equal,
## the OLDER run keeps the higher slot.
##
## That last clause is not decoration. Without it, re-running an identical result
## bumps your own earlier row down the board, and a board where a tie reorders itself
## on every run is a board that cannot be trusted to be stable — which matters for
## the single thing a local board is for: recognising your own rows.
static func is_better(a: Dictionary, b: Dictionary) -> bool:
	var af: int = int(a.get(K_FLOOR, 0))
	var bf: int = int(b.get(K_FLOOR, 0))
	if af != bf:
		return af > bf
	var am: int = int(a.get(K_MS, 0))
	var bm: int = int(b.get(K_MS, 0))
	if am != bm:
		return am < bm
	return int(a.get(K_WHEN, 0)) <= int(b.get(K_WHEN, 0))


## `history`, in ranked order. A COPY — the caller's array is never re-ordered under
## it, which is what lets `rank_of` ask a hypothetical question without side effects.
static func ranked(history: Array) -> Array:
	var out: Array = []
	for r in history:
		if r is Dictionary and int((r as Dictionary).get(K_FLOOR, 0)) > 0:
			out.append(r)
	out.sort_custom(is_better)
	return out


## Insert one run and hand back the new board: ranked, and truncated to MAX_HISTORY.
##
## Truncation happens AFTER the sort, never before, so a great run inserted into a
## full board displaces the worst row rather than the oldest one.
static func insert(history: Array, rec: Dictionary) -> Array:
	var out: Array = ranked(history)
	if rec.has(K_FLOOR) and int(rec.get(K_FLOOR, 0)) > 0:
		out.append(rec)
		out.sort_custom(is_better)
	if out.size() > MAX_HISTORY:
		out.resize(MAX_HISTORY)
	return out


## The personal best — DERIVED, never stored. `{}` on an empty board, because there
## is an honest difference between "no best yet" and "a best of floor 1".
static func best(history: Array) -> Dictionary:
	var r: Array = ranked(history)
	return r[0] if not r.is_empty() else {}


## The best FLOOR alone, or 0 for "never climbed". Convenience for the HUD, which
## wants a number and not a dictionary.
static func best_floor(history: Array) -> int:
	var b: Dictionary = best(history)
	return int(b.get(K_FLOOR, 0)) if not b.is_empty() else 0


## What place would this run take on this board? 1-based. Answers the question the
## end-of-run card actually asks ("is this a record, and if not, where does it sit"),
## and answers it WITHOUT mutating the board — which is why `ranked` copies.
##
## The board is scanned for the FIRST row `rec` outranks; the size + 1 fallback is the
## honest answer for a run that beats nothing.
static func rank_of(history: Array, rec: Dictionary) -> int:
	var r: Array = ranked(history)
	for i: int in r.size():
		if is_better(rec, r[i]):
			return i + 1
	return r.size() + 1


## Is this run a new personal best? True on an empty board — the first climb is
## always a record, and saying otherwise would make the first run the only one that
## never gets the moment.
static func is_record(history: Array, rec: Dictionary) -> bool:
	var b: Dictionary = best(history)
	if b.is_empty():
		return true
	return is_better(rec, b)


# ═══════════════════════════════════════════════════════════════════════════════
# THE FILE
# ═══════════════════════════════════════════════════════════════════════════════
## The on-disk board. `GameState` does the IO; this decides the shape.
static func build_board(history: Array) -> Dictionary:
	var rows: Array = []
	for r in ranked(history):
		rows.append((r as Dictionary).duplicate())
	if rows.size() > MAX_HISTORY:
		rows.resize(MAX_HISTORY)
	return {"version": VERSION, "history": rows}


## Read a raw (JSON-loaded) board back. Malformed input yields an EMPTY board rather
## than an error: a board is a nice-to-have, and a corrupt one must never be able to
## stop the game from starting the way a corrupt climber save could.
static func parse_board(raw: Variant) -> Dictionary:
	var rows: Array = []
	if raw is Dictionary:
		var h: Variant = (raw as Dictionary).get("history", [])
		if h is Array:
			for r in (h as Array):
				var rec: Dictionary = parse_record(r)
				if not rec.is_empty():
					rows.append(rec)
	rows = ranked(rows)
	if rows.size() > MAX_HISTORY:
		rows.resize(MAX_HISTORY)
	return {"version": VERSION, "history": rows}


# ═══════════════════════════════════════════════════════════════════════════════
# DISPLAY — one implementation, so two screens cannot format the same run differently
# ═══════════════════════════════════════════════════════════════════════════════
## "12:04" / "1:07:22". Minutes and seconds until an hour, then hours.
static func format_time(ms: int) -> String:
	var total: int = maxi(ms, 0) / 1000
	@warning_ignore("integer_division")
	var h: int = total / 3600
	@warning_ignore("integer_division")
	var m: int = (total % 3600) / 60
	var s: int = total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]


## One board row as a single line. Deliberately terse — this is a leaderboard row,
## not a paragraph, and it has to fit a 640px-wide phone screen.
static func format_row(rec: Dictionary, place: int = 0) -> String:
	var prefix: String = ("%d. " % place) if place > 0 else ""
	return "%sFloor %d  ·  %s%s" % [
		prefix, int(rec.get(K_FLOOR, 0)), format_time(int(rec.get(K_MS, 0))),
		("  ·  fell" if bool(rec.get(K_DIED, false)) else ""),
	]


# ═══════════════════════════════════════════════════════════════════════════════
# ⚠ THE REMOTE SEAM — AND WHAT IS DELIBERATELY NOT HERE
# ═══════════════════════════════════════════════════════════════════════════════
## THERE IS NO ONLINE LEADERBOARD, AND ONE CANNOT BE BUILT FROM INSIDE THIS REPO.
## The maker asked for one ("with online people"); the honest answer is that it needs
## three things that are not code:
##
##   1. A SERVICE — something to POST to, that stays up, that costs money, and that
##      somebody operates. There is no server here and no hosting.
##   2. IDENTITY — a board without accounts is a board of nicknames, which is a board
##      anybody can impersonate. Accounts mean sign-in, stored personal data, and the
##      legal surface both bring.
##   3. ANTI-CHEAT, which is the hard one. EVERY NUMBER IN THIS FILE IS COMPUTED ON
##      THE PLAYER'S OWN MACHINE and stored in a plain text file at a documented
##      path. Raising your floor to 900 is an edit, not an exploit. A credible board
##      needs server-authoritative simulation (the server runs the fight — enormous)
##      or replay verification (ship the input stream, re-simulate — large, and it
##      requires the game to be deterministic, which combat currently is not).
##
## So a "GLOBAL" tab that read local rows, or a stub returning five invented names,
## is NOT here. It would look finished, it would be believed, and it would be a lie
## in a shipped build.
##
## WHAT IS HERE IS THE SEAM. `to_wire` produces the exact payload such a service
## would receive and `from_wire` reads one back; a real board attaches by
## implementing two calls (submit one record, fetch the top N) against this shape and
## nothing else in the game changes.
##
## `climber_id` is whatever identity the caller has. Today `GameState` has none, so
## it passes "" and the payload is anonymous — which is correct, and is the field
## that step 2 above is about.
static func to_wire(rec: Dictionary, climber_id: String = "",
		tower_id: String = "", game_version: String = "") -> Dictionary:
	return {
		"v": VERSION,
		"climber": climber_id,
		"tower": tower_id,
		"build": game_version,
		"floor": int(rec.get(K_FLOOR, 0)),
		"ms": int(rec.get(K_MS, 0)),
		"class": int(rec.get(K_CLASS, 0)),
		"died": bool(rec.get(K_DIED, false)),
		"kills": int(rec.get(K_KILLS, 0)),
		"at": int(rec.get(K_WHEN, 0)),
		"coop": bool(rec.get(K_COOP, false)),
	}


## The inverse. Every number coerced, for the reason in `parse_record`, and doubly so
## here: a wire payload is the most untrusted input in the whole system.
static func from_wire(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var d: Dictionary = raw
	if not d.has("floor"):
		return {}
	return make_record(
		int(d.get("floor", 1)), int(d.get("ms", 0)), int(d.get("class", 0)),
		bool(d.get("died", false)), int(d.get("kills", 0)),
		int(d.get("at", 0)), bool(d.get("coop", false))
	)
