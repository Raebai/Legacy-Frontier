extends EliteRider
## HERALD — "it calls the rest of the page."
##
## Every few seconds it howls, and for a moment every other body in earshot moves and
## swings faster. Kill the herald and the room slows back down.
##
## ── WHY IT DOES NOT SUMMON ANYTHING ──────────────────────────────────────────
## The obvious "threat multiplier" is more bodies, and the SUMMONER archetype already
## is that. It is also the one shape that fights the hard constraint: the floor is
## capped at 25 live entities (`Encounter.MAX_LIVE_ENTITIES`) and everything that
## spawns has to ask `can_spawn()` first. A herald asks for nothing, so it composes
## with a full room — the moment a swarm floor is at cap is precisely the moment this
## affix is most dangerous, which is a much better curve than one that switches
## itself off there.
##
## ── IT IS A PRIORITY TARGET, WHICH IS THE INTERACTION ────────────────────────
## The surge is temporary and re-fires on a timer, so the whole floor becomes an
## argument about target selection: burn the glowing one first and the wave is
## ordinary, ignore it and every other body is playing a faster game than the one you
## learned. In co-op that is a callout — the cheapest possible source of the "shout at
## your friend" moment the brief is built around.
##
## ── WHAT IT NEVER TOUCHES ────────────────────────────────────────────────────
## HP, damage, the boss. Speed and attack cadence only, restored in full when the
## window closes, and skipped entirely on anything carrying `current_phase` (the
## Boss's own signature method) so a floor guardian is never buffed by its own trash.

const CALL_INTERVAL: float = 7.5
const SURGE_TIME: float = 2.6
const RANGE: float = 330.0
const SPEED_MULT: float = 1.35
const CD_MULT: float = 1.3
## Above this many bodies the herald only lifts the nearest few — a whole capped room
## surging at once is unreadable, and unreadable is what makes hard feel unfair.
const MAX_TARGETS: int = 6

var _timer: float = 3.0
var _surge_left: float = 0.0
## [{node, spd, cd}] — the originals, restored verbatim when the window closes.
var _lifted: Array = []


func _tick(delta: float) -> void:
	if _surge_left > 0.0:
		_surge_left -= delta
		if _surge_left <= 0.0:
			_restore()
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CALL_INTERVAL
	_call_out()


func _call_out() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var here: Vector2 = enemy_pos()
	var picks: Array = []
	for raw in tree.get_nodes_in_group("enemy"):
		# ⚠ UNTYPED LOOP VARIABLE, DELIBERATELY. `for e: Node in ...` binds each element
		# into a typed slot BEFORE the guard on the next line can run, and binding a freed
		# instance is a FAULT, not a false -- the same opcode that produced the floor-10
		# crash in `_restore`. A group does drop its nodes as they are freed, so this one
		# is defence rather than a live bug; it reads this way so the shape is never
		# copied out of here in the form that does bite.
		var e: Node = live_node(raw)
		if e == null or e == enemy or not (e is Node2D):
			continue
		# Never the floor's guardian: `current_phase` is the Boss's signature method
		# and no ordinary enemy has it (the same test Encounter uses to spot a boss).
		if e.has_method("current_phase"):
			continue
		var d: float = here.distance_to((e as Node2D).global_position)
		if d > RANGE:
			continue
		picks.append({"n": e, "d": d})
	if picks.is_empty():
		return
	picks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var col: Color = tint()
	for i: int in mini(picks.size(), MAX_TARGETS):
		# Laundered for the same reason, though `picks` is built and drained inside this
		# one synchronous function and so cannot go stale mid-loop. Consistency is the
		# point: this file is where the pattern gets read from.
		var e2: Node = live_node(picks[i]["n"])
		if e2 == null:
			continue
		var spd: float = float(e2.get("move_speed"))
		var cd: float = float(e2.get("_cd_speed"))
		e2.set("move_speed", spd * SPEED_MULT)
		e2.set("_cd_speed", cd * CD_MULT)
		_lifted.append({"n": e2, "spd": spd, "cd": cd})
		var r2: Node = e2.get_node_or_null(^"Rig")
		if r2 != null and is_instance_valid(r2):
			r2.call("flash_color", Color(col.r * 1.5 + 0.2, col.g * 1.5 + 0.2, col.b * 1.5 + 0.2), 0.22)
	_surge_left = SURGE_TIME
	# THE HOWL. This is the one elite line that is a MECHANIC rather than colour, so
	# it is `always` — never sampled — and it carries a bubble: it is the answer to
	# "why did everything speed up" and, in co-op, the cheapest shout-at-your-friend
	# moment in the game. The room-wide gap in EliteRider is what stops a second
	# herald talking over it.
	#
	# ⚠ THE HOWL HAS TO CROSS THE WIRE, and this is the one affix where it does.
	# `_call_out` is reached from `_tick`, which `EliteRider._process` gates on
	# authority — so a co-op CLIENT used to FEEL the surge (the bodies really are
	# faster there, `move_speed` is synced) with no audible or visible cause. The
	# other five affixes hang their voices off synced state (hp, velocity, position)
	# precisely to avoid needing this; the herald's trigger has no synced twin, so
	# the host says it out loud for everyone. See `Net.broadcast_voice`.
	elite_bark_everywhere(&"elite_herald_call")
	# The herald's own tell: a hard pulse of its colour, so the answer to "why did
	# everything speed up" is on screen at the moment it happens.
	var r: Node = rig()
	if r != null and is_instance_valid(r):
		r.call("flash_color", Color(col.r * 1.9 + 0.3, col.g * 1.9 + 0.3, col.b * 1.9 + 0.3), 0.3)
	var host: Node = arena()
	if host != null and host.is_inside_tree():
		CombatVfx.spawn_burst(host, here + Vector2(0.0, -14.0),
			Color(col.r, col.g, col.b, 0.85), Color(col.r, col.g, col.b, 0.0),
			16, 0.42, 90.0, 210.0, 0.7, 1.8, 0.0, 0.0, true)


## Put every lifted body back EXACTLY where it was. Storing the originals rather than
## dividing back out is deliberate: two overlapping surges (a second herald in the
## same wave) would otherwise compound into a permanent speed drift.
##
## ── THE FLOOR-10 CRASH LIVED HERE, AND THE GUARD WAS NOT THE PROBLEM ───────────
## Reported from real play:
##
##     E  _restore: Trying to assign invalid previously freed instance.
##        EliteHerald.gd:119 @ _restore()   <- var e: Node = row["n"]
##        EliteHerald.gd:129 @ _exit_tree()
##
## The old body already read `if e == null or not is_instance_valid(e): continue`, and
## that line was UNREACHABLE. `var e: Node = row["n"]` binds a container element into a
## STATICALLY TYPED slot, and that binding is what faults on a freed instance -- one
## line before any guard could answer. See `EliteRider.live_node` for the measurements.
##
## The teardown order that reaches it is the ordinary one: on a floor transition the
## wave's bodies are freed, and the elite's rider leaves the tree after them, still
## holding originals it borrowed from bodies that no longer exist.
##
## AND IT WAS NOT ONLY LOG SPAM. A GDScript runtime error ABORTS the enclosing
## function, so `_lifted.clear()` never ran, and neither did the restore for any body
## queued after the first dead one -- which defeats the entire reason `_exit_tree`
## calls this: the room stayed permanently quickened. The reproduction prints
## `_lifted AFTER _restore -> 1` against the old code and `-> 0` against this one.
##
## ── WHY IT DRAINS BEFORE IT WALKS ────────────────────────────────────
## `_lifted` is emptied FIRST and the old rows walked from a local. That makes this
## IDEMPOTENT by construction -- calling it twice restores once, which is load-bearing
## rather than theoretical: `_tick` calls it when the surge window closes and
## `_exit_tree` calls it again on the way out, so a herald that dies on the same frame
## its window expires runs both. It is also the fail-safe shape: if anything in the
## loop below ever faults again, the state is already consistent rather than
## half-restored and replayable.
func _restore() -> void:
	if _lifted.is_empty():
		return                      # nothing borrowed: safe and free to call at any time
	var rows: Array = _lifted
	_lifted = []
	for row in rows:
		# LAUNDERED, never bound directly -- this is the fault site described above.
		var e: Node = live_node(row.get("n"))
		if e == null:
			continue                # the body died before the herald did; nothing to undo
		e.set("move_speed", float(row["spd"]))
		e.set("_cd_speed", float(row["cd"]))


## The herald dying mid-surge must not leave the room permanently quickened.
func _exit_tree() -> void:
	_surge_left = 0.0
	_restore()
