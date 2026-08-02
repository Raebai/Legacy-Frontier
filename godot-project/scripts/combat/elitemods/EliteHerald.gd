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
	for e: Node in tree.get_nodes_in_group("enemy"):
		if e == enemy or not is_instance_valid(e) or not (e is Node2D):
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
		var e2: Node = picks[i]["n"]
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
	# ⚠ HOST-ONLY, AND SAY SO. `_call_out` is reached from `_tick`, which
	# `EliteRider._process` gates on authority — so on a co-op CLIENT the surge is
	# felt (the bodies really are faster there) but not heard. The other five affixes
	# hang their voices off synced state (hp, velocity, position) precisely to avoid
	# this; the herald's trigger has no synced twin, and closing it properly is one
	# `broadcast_voice` line in `Net.gd`, which is another agent's file. Flagged in
	# the handoff rather than papered over with a clock that would drift.
	elite_bark(&"elite_herald_call", true)
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
func _restore() -> void:
	for row in _lifted:
		var e: Node = row["n"]
		if e == null or not is_instance_valid(e):
			continue
		e.set("move_speed", float(row["spd"]))
		e.set("_cd_speed", float(row["cd"]))
	_lifted.clear()


## The herald dying mid-surge must not leave the room permanently quickened.
func _exit_tree() -> void:
	_restore()
