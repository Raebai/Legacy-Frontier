extends EliteRider
## SMUDGED — "the hand smeared it sideways."
##
## It does not walk the last stretch. Every few seconds a smear-mark appears on the
## ground beside you, and a beat later the body is standing on it.
##
## ── WHAT IT CHANGES ABOUT THE FIGHT ──────────────────────────────────────────
## Distance stops being a defence. Kiting is the universal answer to nearly every
## archetype in the roster — back off, let the tell run, punish the recovery — and a
## smudged body deletes the backing-off half of that loop without touching a single
## damage number. What is left is the same fight fought at a range you did not
## choose.
##
## ── IT IS ANSWERABLE, WHICH IS THE WHOLE POINT ───────────────────────────────
## The mark lands FIRST and the body lands second, through `Enemy._emit_telegraph` —
## the same call every archetype's tell goes through, which means it is drawn in the
## same visual language the player has already learned AND it is broadcast to co-op
## clients for free (`Net.broadcast_telegraph`). Without that, a client would watch a
## body blink across the room with no warning, and "step off the mark" — the entire
## play against this affix — would not exist on that screen.
##
## ── WHY IT SKIPS TWO ARCHETYPES ──────────────────────────────────────────────
## CHARGER and ASSASSIN are excluded in `EliteRoster.EXCLUDES`: both already own a
## commit-and-close move, and a third mobility trick on top reads as noise rather
## than as an affix. See the note there.

## Seconds between smears.
const INTERVAL: float = 4.6
## The tell. Long enough to walk out of, short enough to be a threat.
const TELL: float = 0.55
const MARK_RADIUS: float = 26.0
## Closer than this and there is nothing to smear TOWARD — it is already on you.
const MIN_RANGE: float = 165.0
## How far past the hero the landing spot may sit, so it does not always arrive on
## the same side and become a metronome you can pre-dodge.
const SIDE_OFFSET: Array[float] = [-58.0, -34.0, 34.0, 58.0]

## Enemy.AttackState.CHASE. Restated rather than referenced so this rider drags no
## compile-time Enemy dependency into a headless harness.
const STATE_CHASE: int = 0

## THE VOICE BEAT: the smear itself.
##
## ⚠ IT IS DETECTED FROM THE POSITION JUMP, NOT FROM `_land`. `_land` is host-only
## (EliteRider rule 2) and a client would watch the body blink across the room in
## silence. A teleport is a position DISCONTINUITY, and position is the one thing
## every peer's puppet is synced on — so both screens hear the smear off the same
## observation with nothing broadcast. It also catches any other displacement big
## enough to read as a blink, which is the honest reading of the affix.
const SMEAR_JUMP: float = 110.0

var _timer: float = 2.4
var _moving: bool = false
var _last_pos: Vector2 = Vector2.INF


## Runs on EVERY peer — see the jump note above.
func _tick_visual(_delta: float) -> void:
	var here: Vector2 = enemy_pos()
	var was: Vector2 = _last_pos
	_last_pos = here
	if was == Vector2.INF:
		return
	if was.distance_to(here) < SMEAR_JUMP:
		return
	# Mouth only. This fires every INTERVAL (4.6 s) at most and a bubble on every
	# one of them would be a tickertape over a body that is already telegraphing.
	elite_voice(Gibberish.Mood.MUTTER, 2)


func _tick(delta: float) -> void:
	if _moving:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	# Never smear out of a windup. A blink that ate a telegraphed attack would break
	# the promise that the shape you can see is the shape that hurts.
	if int(enemy.get("_attack_state")) != STATE_CHASE:
		_timer = 0.5
		return
	var h: Node2D = nearest_hero()
	if h == null:
		_timer = 1.0
		return
	var here: Vector2 = enemy_pos()
	if here.distance_to(h.global_position) < MIN_RANGE:
		_timer = INTERVAL * 0.5
		return
	_timer = INTERVAL
	_begin(h.global_position)


func _begin(hero_at: Vector2) -> void:
	var side: float = SIDE_OFFSET[randi() % SIDE_OFFSET.size()]
	var dest := Vector2(hero_at.x + side, enemy_pos().y)
	_moving = true
	var col: Color = tint()
	# The mark, through the enemy's OWN telegraph channel — same vocabulary as every
	# other tell in the room, and replicated to clients without a line of new netcode.
	var tele: Node = enemy.call("_emit_telegraph", {
		"style": Telegraph.Style.ZONE,
		"pos": dest,
		"radius": MARK_RADIUS,
		"windup": TELL,
		"accent": col,
		"no_resolve": true,
	})
	# The smear it leaves behind: the body scribbled out where it stood.
	var host: Node = arena()
	var r: Node = rig()
	if host != null and host.is_inside_tree() and r != null:
		var ghost_col: Color = col
		ghost_col.a = 0.45
		r.call("spawn_ghost", host, ghost_col)
	if tele != null and is_instance_valid(tele) and tele.has_signal("fired"):
		tele.connect("fired", _land.bind(dest), CONNECT_ONE_SHOT)
	else:
		_land(dest)


func _land(dest: Vector2) -> void:
	_moving = false
	if not is_instance_valid(self) or enemy == null or not is_instance_valid(enemy):
		return
	if is_dead() or not is_authority():
		return
	var r: Node = rig()
	if r != null and is_instance_valid(r):
		# One more smear at the departure point so the eye can join the two dots.
		var ghost_col: Color = tint()
		ghost_col.a = 0.35
		var host: Node = arena()
		if host != null and host.is_inside_tree():
			r.call("spawn_ghost", host, ghost_col)
	(enemy as Node2D).global_position = dest
	# Landed with its cooldown nearly spent: the smear is an APPROACH, not a rest.
	enemy.set("_attack_cooldown", minf(float(enemy.get("_attack_cooldown")), 0.15))
