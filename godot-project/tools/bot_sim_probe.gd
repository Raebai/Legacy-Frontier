class_name BotSimProbe
extends RefCounted
## THE ANOMALY DETECTORS — pure predicates over plain values, with no world.
##
## Every check the bot simulation makes lives here as a static function taking
## numbers in and handing a verdict back, for one reason: a bug-finder nobody
## trusts is worse than no bug-finder, and the only way to trust one is to be
## able to test it headlessly against known-good and known-bad inputs. See
## `tools/slice6_test_bot_sim.gd`.
##
## ⚠ WHY EVERY POSITION CHECK TAKES A POSITION RATHER THAN A NODE. Almost every
## spell spectacle in this codebase PARKS AT THE ARENA ORIGIN and draws in world
## coordinates — `global_position` is (0, 0) and is emphatically NOT where the
## effect is (see the header of `scripts/combat/Spell.gd`, which documents itself
## as the one exception because a bolt genuinely is a moving body). So nothing in
## this file may reach into a node and read a transform. The caller decides what
## geometry an effect actually reports, and passes that in.
##
## Nothing here names an autoload. These are static functions, and naming an
## autoload inside one is a COMPILE error under `--script` (the whole dependency
## chain fails to load), not a runtime one — so it cannot be caught by testing.

## Anomaly severities. ERROR means "this is a bug"; WARN means "this is a signal
## for the maker, look at it" — a balance outlier is not automatically a defect,
## and the harness must never pretend otherwise.
const SEV_ERROR: String = "error"
const SEV_WARN: String = "warn"

## A single hit taking this share of a fighter's max HP is implausible enough to
## be worth a row. UNTESTED GUESS: nothing in the kits is designed to do half a
## health bar in one connect, so 0.40 flags the genuinely strange while leaving
## room for a legitimately scary payoff spell.
const DAMAGE_OUTLIER_FRACTION: float = 0.40
## A kill faster than this reads as a one-shot rather than a fight.
const FAST_KILL_SECONDS: float = 1.0
## Below this much total HP movement over the stalemate window, the fight is not
## progressing — either a softlock or two bots that cannot reach each other.
const STALEMATE_HP_EPSILON: int = 1
## How still (px) and how quiet (presses) a fighter has to be, for how long,
## before it counts as having stopped acting.
const IDLE_MOVE_EPSILON: float = 6.0
const IDLE_SECONDS: float = 5.0
## Attempts required before "this spell never fired" is a claim rather than noise.
const NEVER_FIRED_MIN_ATTEMPTS: int = 3


# ---- geometry / world-integrity checks -------------------------------------

## A coordinate that is NaN or infinite. This is its own check rather than being
## folded into the bounds test because the two have different causes: a NaN comes
## from a division or a normalize() on a zero vector somewhere in the physics,
## while an out-of-bounds body was merely launched too hard. Note `x != x` is not
## used — `is_finite` covers both NaN and ±INF in one call.
static func position_is_broken(pos: Vector2) -> bool:
	return not is_finite(pos.x) or not is_finite(pos.y)


## Left the playable world. `bounds` is the arena rect grown by whatever slack
## the caller thinks a legitimate knockback deserves; anything outside it has
## either been launched into the void or tunnelled through a wall.
static func escaped_bounds(pos: Vector2, bounds: Rect2) -> bool:
	if position_is_broken(pos):
		return true       # a broken coordinate is by definition not inside anything
	return not bounds.has_point(pos)


## Fell through the floor. Separate from `escaped_bounds` on purpose: this is the
## single most common shape of world bug in this codebase (spells and bodies
## resolving BELOW the ground plane), so it gets its own row rather than being
## lumped in with "went off the side", which is usually just a big knockback.
static func below_floor(y: float, floor_y: float, tolerance: float = 48.0) -> bool:
	if not is_finite(y):
		return true
	return y > floor_y + tolerance


## Inside solid ground — the honest version of `below_floor`, which takes the SPAN
## as well as the line.
##
## ⚠ PAST THE EDGE OF THE SLAB THERE IS NOTHING TO BE BELOW. `below_floor` is a bare
## y-comparison, so every projectile that overshoots the ±FLOOR_X slab and flies on
## through empty air satisfies it. The body-side check learned this already (see the
## `off_slab` split in `bot_sim._check_bodies`, where MEASURING it showed that every
## single `body_below_floor` row was actually a fall past the edge). The spell-side
## check never got the same treatment and kept filing those as ERROR.
##
## On the real `VersusArena` that same trajectory is a bolt leaving the stage, which
## is not a defect at any severity.
static func inside_terrain(pos: Vector2, floor_y: float, x0: float, x1: float,
		tolerance: float = 24.0) -> bool:
	if position_is_broken(pos):
		return true       # a broken coordinate is by definition not anywhere valid
	if pos.x < x0 or pos.x > x1:
		return false      # no floor here to sink through
	return pos.y > floor_y + tolerance


# ---- damage checks ---------------------------------------------------------

## A single sample-to-sample HP drop that is an implausible share of the bar.
## `drop` is positive for damage taken. Guards max_hp <= 0 so a mis-configured
## fighter reports "no outlier" instead of dividing by zero and poisoning the run.
static func damage_outlier(drop: int, max_hp: int,
		fraction: float = DAMAGE_OUTLIER_FRACTION) -> bool:
	if max_hp <= 0 or drop <= 0:
		return false
	return float(drop) / float(max_hp) >= fraction


## Died faster than a fight. Not automatically a bug — it might be a legitimately
## brutal opener — which is why the caller files it at WARN.
static func fast_kill(death_time: float, threshold: float = FAST_KILL_SECONDS) -> bool:
	return death_time >= 0.0 and death_time < threshold


## NOBODY TOOK DAMAGE. This is the headline check and the reason the harness
## exists: hero-vs-hero damage in this codebase is routed by GROUP (`"enemy"`),
## not by faction, so two heroes swinging at each other currently do literally
## nothing. That bug has exactly this signature, and a long fight with zero total
## damage is never anything but a defect.
static func no_damage_exchanged(total_damage: int, elapsed: float,
		min_elapsed: float = 8.0) -> bool:
	return total_damage <= 0 and elapsed >= min_elapsed


## HP outside its own legal range. Cheap, and catches a whole family of
## arithmetic bugs (over-heal, negative clamp missing, max_hp changed without
## re-clamping hp) that nothing else in the run would notice.
static func hp_out_of_range(hp: int, max_hp: int) -> bool:
	return hp > max_hp or hp < 0


# ---- liveness checks -------------------------------------------------------

## The fight is not progressing. `hp_window` is the total HP movement (both
## fighters, absolute) over the trailing window; below epsilon means nothing has
## landed, which is either a softlock or two bots that cannot reach each other.
## Both are worth a row and the difference is not decidable from here.
static func stalemate(hp_movement_in_window: int, window_elapsed: float,
		window: float, epsilon: int = STALEMATE_HP_EPSILON) -> bool:
	if window_elapsed < window:
		return false
	return hp_movement_in_window <= epsilon


## A fighter that has stopped acting: didn't move and didn't press anything for
## a whole window. Distinct from stalemate — this is about ONE agent's brain
## having gone quiet (a crashed decide(), a latched state it can't leave), not
## about the fight as a whole.
static func actor_idle(moved_px: float, presses: int, idle_elapsed: float,
		window: float = IDLE_SECONDS, move_epsilon: float = IDLE_MOVE_EPSILON) -> bool:
	if idle_elapsed < window:
		return false
	return moved_px <= move_epsilon and presses <= 0


# ---- ability-reachability checks -------------------------------------------

## A slot that was asked for and never came out. `attempts` counts presses made
## while the harness believed the gate was open (off cooldown, mana covered); a
## run of those with zero fires means the slot is unreachable, mis-costed, or
## silently failing — the exact shape of the recently-found unequippable beam
## family and the two ults that applied no status.
##
## The minimum-attempts floor is what keeps this a claim rather than noise: one
## failed press proves nothing (the bot may have been interrupted mid-windup).
static func never_fired(attempts: int, fires: int,
		min_attempts: int = NEVER_FIRED_MIN_ATTEMPTS) -> bool:
	return attempts >= min_attempts and fires <= 0


## A fighter that never spent a single point of mana over a whole fight: every
## cast it tried fizzled, or it never tried. Either is worth knowing, and it is
## cheap to notice.
static func never_spent_mana(mp_spent: float, elapsed: float,
		min_elapsed: float = 8.0) -> bool:
	return elapsed >= min_elapsed and mp_spent <= 0.0


# ---- record construction ---------------------------------------------------

## ONE ANOMALY IS ONE ROW. Everything the maker needs to reproduce it travels
## with it — the pairing, the seed, the game-clock timestamp — because an anomaly
## you cannot replay is a rumour, not a bug report.
static func anomaly(kind: String, severity: String, pairing: String, seed_value: int,
		at: float, detail: String, context: Dictionary = {}) -> Dictionary:
	return {
		"kind": kind,
		"severity": severity,
		"pairing": pairing,
		"seed": seed_value,
		"t": snappedf(at, 0.01),
		"detail": detail,
		"context": context,
	}


## CSV escaping for the one-row-per-anomaly export. Quotes everything and doubles
## embedded quotes, which is the whole of RFC 4180 that matters here; commas and
## newlines inside a detail string then cannot corrupt the column layout.
static func csv_cell(value: Variant) -> String:
	return "\"%s\"" % String(str(value)).replace("\"", "\"\"")


static func csv_header() -> String:
	return "kind,severity,pairing,seed,t,detail"


static func csv_row(a: Dictionary) -> String:
	return ",".join([
		csv_cell(a.get("kind", "")), csv_cell(a.get("severity", "")),
		csv_cell(a.get("pairing", "")), csv_cell(a.get("seed", 0)),
		csv_cell(a.get("t", 0.0)), csv_cell(a.get("detail", "")),
	])


## Counts by kind and by severity, for the human summary at the end of a run.
## Returns {"by_kind": {kind: count}, "errors": int, "warns": int, "total": int}.
static func summarize(anomalies: Array) -> Dictionary:
	var by_kind: Dictionary = {}
	var errors: int = 0
	var warns: int = 0
	for a: Dictionary in anomalies:
		var k: String = String(a.get("kind", "?"))
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		if String(a.get("severity", "")) == SEV_ERROR:
			errors += 1
		else:
			warns += 1
	return {"by_kind": by_kind, "errors": errors, "warns": warns, "total": anomalies.size()}
