class_name ClipDirector
extends Node2D
## THE CONTENT ENGINE'S CAMERA OPERATOR — the thing that decides WHEN a bot fight
## is worth filming and WHERE to point while it is.
##
## The maker's ask: *"we need really good bots to fight each other as well so that
## we can get some good content"*. Good bots are half of it. The other half is that
## a fight nobody framed is not a clip — it is footage. The existing capture tool
## starts rolling on frame zero, holds a fixed pair-framing, and runs for a fixed
## count, which produces a lot of two stick figures walking toward each other and a
## payoff that lands somewhere near the edge of shot.
##
## ---------------------------------------------------------------------------
## WHAT A GOOD CLIP NEEDS, and what each part of this file does about it.
##
##   1. IT STARTS WHERE THE FIGHT DOES.  `heat()` scores the live board — damage in
##      the last second, spells in flight, live telegraphs, how close the fighters
##      are. A capture tool waits for `is_hot()` instead of rolling on the spawn
##      poof. Two seconds of approach is 60 wasted frames out of 300.
##   2. IT POINTS AT THE PAYOFF.  The framing target is the pair's midpoint BIASED
##      toward whatever is actually happening: the fighter who just took damage, and
##      the centroid of the live spell geometry. A meteor column landing half off
##      the top of frame is the single most common failure of every capture tool in
##      this project.
##   3. IT PUNCHES IN.  Zoom is driven by the separation, then pulled tighter by
##      heat, so a big exchange reads as a close-up and a reset reads as a wide.
##   4. IT ENDS ON THE KO.  `saw_knockdown()` latches, so a tool can roll a short
##      tail and stop rather than filming the corpse. The first version of the
##      existing capture spent 340 of 400 frames watching one.
##
## ---------------------------------------------------------------------------
## ⚠ IT CHANGES NOTHING ABOUT THE FIGHT. This node reads positions, health bars and
## group membership and writes ONE property: the camera's transform. It hands no
## bot any information, adjusts no stat, and pauses nothing. A clip of a rigged
## fight is worthless for finding bugs and dishonest as marketing, and the only way
## to be sure of that is for the director to have no way to touch the fighters —
## which is why the fighters are read out of the tree by group rather than handed in
## with setters.
##
## Usable three ways, all of them through the same object: attached to a live
## `VersusArena` in showcase mode (the watchable bot-match scene), driven by
## `tools/directed_clip_capture.gd` for a rendered frame sequence, or ticked manually by
## a headless test.

## How long a damage event keeps counting toward heat. About one exchange.
const DAMAGE_MEMORY: float = 1.1
## Heat contributions, each clamped into 0..1 before weighting. They ADD and the
## total clamps, so a fight can be hot for more than one reason at once — which is
## exactly what the best moments look like.
const W_DAMAGE: float = 0.55
const W_SPELLS: float = 0.25
const W_TELEGRAPH: float = 0.20
const W_PROXIMITY: float = 0.20
## Spell count that saturates the spell term. Four live spectacles is a busy screen.
const SPELL_SATURATION: float = 4.0
## Fighters closer than this are "in each other's face", which reads as hot even
## with nothing in flight — the beat before a clash.
const CLOSE_RANGE: float = 160.0
## Heat at or above this is worth filming.
const HOT_THRESHOLD: float = 0.32
## ...and once hot, the clip does not stop the instant a bolt expires. Hysteresis,
## because a shot that cuts out mid-exchange is worse than three dull frames.
const COOL_THRESHOLD: float = 0.14

## Framing. MARGIN is the slack around everything being framed, so a beam or a
## meteor column has room to land INSIDE the shot.
## ⚠ THESE ARE MEASURED AGAINST THE BASE VIEWPORT (683 px wide), NOT THE WINDOW.
## The first pass used the showcase camera's own 460 / 0.58 / 1.35 and produced a
## frame with ONE fighter in it: at 0.58 the shot is 1178 world pixels across, and
## two bots that had drifted 1300 apart on this 2000 px stage simply could not both
## fit — the zoom floor, not the framing, threw one of them out. A smaller MARGIN
## means the camera only pulls back as far as it actually has to; a lower ZOOM_MIN
## means it CAN when it has to. Both fighters in frame beats a tighter shot of one.
const FRAME_MARGIN: float = 300.0
## ...and the slack a HOT moment is allowed to shrink that to. See `_frame`.
const FRAME_MARGIN_HOT: float = 170.0
## The same two numbers on y. Smaller, because a 31 px stick figure needs far less
## headroom than two fighters need shoulder room, and because the eye is already
## lifted (EYE_LIFT) to put the floor in the lower third.
const FRAME_MARGIN_V: float = 200.0
const FRAME_MARGIN_V_HOT: float = 120.0
const ZOOM_MIN: float = 0.42
const ZOOM_MAX: float = 1.15
## ⚠ HEAT NO LONGER MULTIPLIES THE SOLVED ZOOM, and that is the maker's note.
##
## *"the camera needs to follow it cinematically so the audience can see it all all
## the time"*. The old model solved a zoom that fit the pair and then multiplied it
## by `1 + HEAT_PUNCH * heat` — i.e. the hotter the moment, the further past the
## containing zoom it punched, so the single most watchable seconds of every fight
## were the ones most likely to throw a fighter out of shot. Containment is a HARD
## CONSTRAINT now: heat shrinks the MARGIN (FRAME_MARGIN -> FRAME_MARGIN_HOT), which
## tightens the shot without ever crossing the line where somebody leaves it. Heat
## drives the tightness; it does not choose the subject and it cannot overrule the
## rule that both fighters are visible.
const KO_HOLD: float = 2.2
## How hard the shot leans onto the fighter who just went down, for KO_HOLD seconds
## after the decisive beat. Higher than VICTIM_BIAS because by then there is only one
## thing in the picture worth looking at.
const KO_BIAS: float = 0.55
## Camera lerp rates. Position tracks faster than zoom: a snappy pan reads as
## camera work, a snappy zoom reads as a bug.
const POS_LERP: float = 7.0
const ZOOM_LERP: float = 2.6
## How far the framing target leans toward the fighter who just got hit.
const VICTIM_BIAS: float = 0.35
## ...and toward the live spell geometry.
const SPELL_BIAS: float = 0.30
## The eye sits above the midpoint so the floor falls in the lower third instead of
## half the frame being underground.
const EYE_LIFT: float = 50.0
## How far ABOVE the floor the eye may rise. See `_lean` — a tall spectacle must not
## be able to lift the camera off the stage.
const VERTICAL_BAND: float = 210.0
## Fraction of a horizontal lean that is applied vertically. See `_lean`.
const VERTICAL_LEAN: float = 0.25

## Groups read. All of them are things drawn on screen.
const SPELL_GROUPS: Array[StringName] = [&"player_spell", &"enemy_projectile"]

## The camera this director drives. Assigned by `bind`; a null camera makes every
## framing call a no-op, so a headless test can tick the heat model with no
## viewport at all.
var camera: Camera2D = null
## Stage bounds the eye is clamped inside, so the camera never drifts far enough
## for empty sky or the void under the terrain to fill a third of the shot.
var stage: Rect2 = Rect2(Vector2.ZERO, Vector2(2000.0, 1000.0))
## The y of the walkable floor, for the vertical clamp. ⚠ ANCHORED TO THE GROUND,
## not to absolute world y: an earlier framing pass clamped absolute, and a fighter
## launched high dragged the eye up with it — 340 of 400 captured frames came back
## as empty sky. Holding the eye within a band ABOVE THE FLOOR keeps the stage in
## shot however far a knockback throws somebody.
var ground_y: float = 780.0

var _clock: float = 0.0
var _heat: float = 0.0
var _hot: bool = false
var _hot_since: float = -1.0
var _knockdown_at: float = -1.0
var _hp_last: Dictionary = {}          # instance_id -> int
var _pct_last: Dictionary = {}         # instance_id -> float (the ring-out accumulator)
## When a fighter was last knocked off the stage. A ring-out is a decisive beat and
## a clip may end on one exactly as it may end on a knockdown.
var _ringout_at: float = -1.0
## Where the decisive beat happened, for the KO framing lean. INF until there is one
## (see `_recent_damage_centroid` for why INF and not ZERO).
var _decisive_pos: Vector2 = Vector2.INF
var _damage_events: Array[Dictionary] = []   # {"at": float, "pos": Vector2, "amount": int}
var _peak_heat: float = 0.0
var _peak_at: float = 0.0
## One row per notable beat, for the clip manifest: what happened and when. A clip
## that ships with a machine-readable list of its own highlights can be cut down
## later without re-running the fight.
var _beats: Array[Dictionary] = []


## Point the director at a camera and a stage. Everything else it finds itself.
func bind(cam: Camera2D, bounds: Rect2, floor_y: float) -> void:
	camera = cam
	stage = bounds
	ground_y = floor_y


func _process(delta: float) -> void:
	advance(delta)


## One step of the model. Split out from `_process` so a headless test can drive it
## at a fixed timestep and so a capture tool can step it in lockstep with the frames
## it is saving.
func advance(delta: float) -> void:
	_clock += delta
	var fighters: Array[Node2D] = live_fighters()
	_sample_damage(fighters)
	_heat = compute_heat(fighters)
	if _heat > _peak_heat:
		_peak_heat = _heat
		_peak_at = _clock
	var was_hot: bool = _hot
	if _hot:
		_hot = _heat >= COOL_THRESHOLD
	else:
		_hot = _heat >= HOT_THRESHOLD
	if _hot and not was_hot:
		_hot_since = _clock
		_note("hot", "the fight caught")
	_check_knockdown(fighters)
	_frame(fighters, delta)


# ==========================================================================
# PERCEPTION — read-only, all of it drawn
# ==========================================================================

## Every living fighter on the stage. Group `hero` rather than a handed-in list, so
## the director physically cannot be given a fighter the fight does not have.
func live_fighters() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return out
	for n: Node in tree.get_nodes_in_group(&"hero"):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or not (n is Node2D):
			continue
		out.append(n as Node2D)
	return out


## Watch the health bars and remember where damage happened. Polled rather than
## signal-driven because `Hero` publishes no took-damage signal — only
## `health_changed`, which also fires on heals and on the round reset, so a listener
## would file a respawn as a 320-point hit. A RISE is never damage.
## ⚠ HP IS NOT THE ONLY DAMAGE SIGNAL ON THIS STAGE, and reading only HP made the
## director blind on the one stage it films.
##
## `VersusArena` switches `GameState.ringout_mode` on, which is the Smash model:
## hits accumulate `damage_pct` and scale knockback, and a fighter is finished by
## being launched off the rim rather than by an HP bar reaching zero. So a directed
## capture of a genuinely violent exchange reported `heat 0.06` for its whole length
## and never saw a knockdown — MEASURED, from a clip in which both fighters were
## visibly at 219% and 642%. Both signals are read now:
##   HP DROPPING      the tower model, and any HP damage in ring-out mode.
##   damage_pct RISING the ring-out model's own accumulator.
##   damage_pct RESET  a respawn, i.e. somebody just got knocked off the stage —
##                     which is the most watchable single event this game has.
func _sample_damage(fighters: Array[Node2D]) -> void:
	for f: Node2D in fighters:
		var id: int = f.get_instance_id()
		var hp: int = int(f.get("hp"))
		if _hp_last.has(id):
			var drop: int = int(_hp_last[id]) - hp
			if drop > 0:
				_damage_events.append({"at": _clock, "pos": f.global_position, "amount": drop})
		_hp_last[id] = hp
		# The ring-out accumulator. `get` returns null on a body that has no such
		# property, so it is tested rather than coerced — `float(null)` throws.
		var pct_v: Variant = f.get("damage_pct")
		if pct_v == null:
			continue
		var pct: float = float(pct_v)
		if _pct_last.has(id):
			var prev: float = float(_pct_last[id])
			var rise: float = pct - prev
			if rise > 0.01:
				# Scaled into the same units as HP damage so one weight covers both.
				_damage_events.append({"at": _clock, "pos": f.global_position,
					"amount": int(round(rise))})
			elif prev >= RINGOUT_PCT_FLOOR and pct <= 0.5:
				# Reset to zero after real accumulation: that is a respawn, and a
				# respawn on this stage means a RING-OUT.
				_ringout_at = _clock
				_decisive_pos = f.global_position
				_note("ringout", "a fighter was knocked off the stage")
		_pct_last[id] = pct
	while not _damage_events.is_empty() \
			and _clock - float(_damage_events[0]["at"]) > DAMAGE_MEMORY:
		_damage_events.pop_front()


## HOW WORTH FILMING IS THIS MOMENT, 0..1.
##
## Public and pure-ish (it reads the tree but writes nothing) so a test can assert
## the SHAPE of the judgement — that an exchange outscores an approach — rather than
## only its outcome, which would pass for the wrong reason as easily as the right one.
func compute_heat(fighters: Array[Node2D]) -> float:
	var h: float = 0.0
	# --- damage. The strongest single signal that something is happening.
	var recent: int = 0
	for e: Dictionary in _damage_events:
		recent += int(e["amount"])
	h += W_DAMAGE * clampf(float(recent) / 45.0, 0.0, 1.0)
	# --- things in flight.
	var spells: int = 0
	var tree: SceneTree = get_tree()
	if tree != null:
		for g: StringName in SPELL_GROUPS:
			spells += tree.get_nodes_in_group(g).size()
		h += W_SPELLS * clampf(float(spells) / SPELL_SATURATION, 0.0, 1.0)
		# --- a live telegraph is a PROMISE of a payoff, which is worth starting to
		# roll for: by the time the payoff lands, a tool that waited for the damage
		# has already missed the wind-up that made it readable.
		var armed: int = 0
		for t: Node in tree.get_nodes_in_group(&"telegraph"):
			if t.has_method(&"is_armed") and bool(t.call(&"is_armed")):
				armed += 1
		h += W_TELEGRAPH * clampf(float(armed) / 2.0, 0.0, 1.0)
	# --- proximity. Two fighters in each other's face is hot with nothing in flight.
	if fighters.size() >= 2:
		var d: float = fighters[0].global_position.distance_to(fighters[1].global_position)
		h += W_PROXIMITY * clampf(1.0 - d / maxf(CLOSE_RANGE * 2.5, 1.0), 0.0, 1.0)
	return clampf(h, 0.0, 1.0)


## How much accumulated damage must have been on the clock before a reset to zero
## counts as a ring-out rather than as a round starting.
const RINGOUT_PCT_FLOOR: float = 25.0


## Latch the first knockdown. A clip should end shortly after one, not keep rolling.
##
## ⚠ THIS POLL CANNOT SEE THE ONE THAT MATTERS, and that is why `note_knockdown`
## exists beside it. `Hero._die()` outside a run does `hp = max_hp` IN THE SAME CALL
## as the fatal hit — so a fighter's HP never rests at or below zero for a single
## frame, and a once-per-frame poll of `hp` therefore never fires on this stage. It
## is kept because it is correct wherever a corpse does stay down (and because it is
## free), but the authority on "somebody went down" is whoever holds the
## `health_changed` signal, which reports `hp == 0` BEFORE `_die` heals it back.
func _check_knockdown(fighters: Array[Node2D]) -> void:
	if _knockdown_at >= 0.0:
		return
	for f: Node2D in fighters:
		if int(f.get("hp")) <= 0:
			_knockdown_at = _clock
			_decisive_pos = f.global_position
			_note("ko", "a fighter went down")
			return


## A decisive beat, reported by something that can actually see it. Latches exactly
## like the poll above — first one wins, and it never clears, because a tool reads it
## once a frame and must not miss the beat because a body was freed or healed.
##
## `at` is where it happened, for the KO framing lean; omit it and the camera simply
## does not lean.
func note_knockdown(at: Vector2 = Vector2.INF, detail: String = "a fighter went down") -> void:
	if _knockdown_at >= 0.0:
		return
	_knockdown_at = _clock
	if at != Vector2.INF:
		_decisive_pos = at
	_note("ko", detail)


## The same, for a fighter that went off the rim rather than down. Separate only so
## the clip manifest can say which of the two ended the fight.
func note_ringout(at: Vector2 = Vector2.INF) -> void:
	if _ringout_at >= 0.0:
		return
	_ringout_at = _clock
	if at != Vector2.INF:
		_decisive_pos = at
	_note("ringout", "a fighter was knocked off the stage")


func _note(kind: String, detail: String) -> void:
	_beats.append({"at": snappedf(_clock, 0.01), "kind": kind,
		"heat": snappedf(_heat, 0.01), "detail": detail})


# ==========================================================================
# FRAMING
# ==========================================================================

## Where to point and how far to zoom, then move the camera part of the way there.
##
## The target is not simply the midpoint. It is the midpoint LEANED toward whatever
## the audience is actually looking at: the fighter who just took a hit, and the
## centroid of the live spell geometry. Those two biases are the difference between
## "both fighters are technically in shot" and "the thing that just happened is in
## the middle of the picture".
func _frame(fighters: Array[Node2D], delta: float) -> void:
	if camera == null or fighters.is_empty():
		return
	var pts: Array[Vector2] = []
	for f: Node2D in fighters:
		pts.append(f.global_position)
	var mid: Vector2 = Vector2.ZERO
	for p: Vector2 in pts:
		mid += p
	mid /= float(pts.size())

	var target: Vector2 = mid
	var victim: Vector2 = _recent_damage_centroid()
	if victim != Vector2.INF:
		target = _lean(target, victim, VICTIM_BIAS)
	var spells: Vector2 = _spell_centroid()
	if spells != Vector2.INF:
		target = _lean(target, spells, SPELL_BIAS)
	# ...and hard onto the loser for the beat after a decisive hit. This is the
	# payoff frame; there is nothing else in the picture worth looking at.
	var ko_age: float = seconds_since_knockdown()
	if _decisive_pos != Vector2.INF and ko_age >= 0.0 and ko_age <= KO_HOLD:
		target = _lean(target, _decisive_pos, KO_BIAS)

	# THE EYE FIRST, then a zoom that is solved FROM it. Solving the zoom off the
	# pair's midpoint (as the first pass did) is subtly wrong whenever the target has
	# leaned away from that midpoint or been clamped to the stage: the shot is then
	# centred somewhere the zoom was never computed for, and the far fighter is
	# outside it. Clamp first, fit second, and the two can never disagree.
	var eye: Vector2 = Vector2(
		clampf(target.x, stage.position.x + 340.0, stage.end.x - 340.0),
		clampf(target.y - EYE_LIFT, ground_y - VERTICAL_BAND, ground_y - 40.0))

	var want: float = _fit_zoom(pts, eye)
	var z: float = lerpf(camera.zoom.x, want, clampf(delta * ZOOM_LERP, 0.0, 1.0))
	camera.zoom = Vector2(z, z)
	camera.global_position = camera.global_position.lerp(eye,
		clampf(delta * POS_LERP, 0.0, 1.0))


## THE HARD CONSTRAINT: the widest zoom that still contains every fighter, seen
## from `eye`, with slack that a hot moment is allowed to shrink.
##
## Public and pure so a test can assert the rule directly rather than inferring it
## from a rendered frame — see `tools/slice7_test_clipframing.gd`, which is the
## assertion behind the maker's *"so the audience can see it all all the time"*.
func _fit_zoom(pts: Array[Vector2], eye: Vector2) -> float:
	var view: Vector2 = Vector2(1280.0, 720.0)
	var vp: Viewport = get_viewport()
	if vp != null:
		view = Vector2(vp.get_visible_rect().size)
	view.x = maxf(view.x, 1.0)
	view.y = maxf(view.y, 1.0)
	# Heat tightens by eating the slack, NEVER by punching past containment.
	var slack_x: float = lerpf(FRAME_MARGIN, FRAME_MARGIN_HOT, clampf(_heat, 0.0, 1.0))
	var slack_y: float = lerpf(FRAME_MARGIN_V, FRAME_MARGIN_V_HOT, clampf(_heat, 0.0, 1.0))
	var need_x: float = 0.0
	var need_y: float = 0.0
	for p: Vector2 in pts:
		need_x = maxf(need_x, absf(p.x - eye.x))
		need_y = maxf(need_y, absf(p.y - eye.y))
	var fit: float = minf(
		view.x / maxf(need_x * 2.0 + slack_x, 1.0),
		view.y / maxf(need_y * 2.0 + slack_y, 1.0))
	return clampf(fit, ZOOM_MIN, ZOOM_MAX)


## Lean the framing target toward a point of interest — FULLY on x, but only
## `VERTICAL_LEAN` of that on y.
##
## ⚠ THE ASYMMETRY IS THE FIX, and a symmetric lerp is what broke the first directed
## clip. `_spell_centroid` includes tall spectacles: a Stormcaller's lightning column
## is a node hundreds of pixels above the floor, so a full-weight vertical lean
## dragged the eye to the top of its clamp and the fight itself ended up in the
## bottom 7% of frame — MEASURED, from a captured frame that is almost entirely sky
## with two fighters' heads at the very bottom edge. Horizontally the same lean is
## exactly right: it is what puts the payoff in the middle of the picture. Fighters
## stand on a floor; spells go up. The camera should follow them sideways and barely
## follow them upward.
static func _lean(from: Vector2, toward: Vector2, weight: float) -> Vector2:
	return Vector2(
		lerpf(from.x, toward.x, weight),
		lerpf(from.y, toward.y, weight * VERTICAL_LEAN))


## Where the recent damage happened, or INF for none. INF rather than ZERO because
## (0, 0) is a real world position — the top-left of the stage — and using it as the
## "no data" value points the camera at the corner of the map.
func _recent_damage_centroid() -> Vector2:
	if _damage_events.is_empty():
		return Vector2.INF
	var sum: Vector2 = Vector2.ZERO
	var weight: float = 0.0
	for e: Dictionary in _damage_events:
		var w: float = float(e["amount"])
		sum += (e["pos"] as Vector2) * w
		weight += w
	return sum / maxf(weight, 0.001) if weight > 0.0 else Vector2.INF


## Centroid of everything in flight, or INF. ⚠ ONLY the projectile groups are read
## through their transform: `Spell.gd` is the one spectacle where the node genuinely
## IS the effect. Every other spectacle in this codebase parks at the arena origin
## and draws in world coordinates, so reading `global_position` off one would drag
## the camera to (0, 0) every time a beam existed.
func _spell_centroid() -> Vector2:
	var tree: SceneTree = get_tree()
	if tree == null:
		return Vector2.INF
	var sum: Vector2 = Vector2.ZERO
	var n: int = 0
	for g: StringName in SPELL_GROUPS:
		for s: Node in tree.get_nodes_in_group(g):
			if not is_instance_valid(s) or not (s is Node2D):
				continue
			sum += (s as Node2D).global_position
			n += 1
	return Vector2.INF if n == 0 else sum / float(n)


# ==========================================================================
# THE CAPTURE TOOL'S QUESTIONS
# ==========================================================================

func heat() -> float:
	return _heat


## Is this worth filming right now? Hysteretic: HOT_THRESHOLD to start, the lower
## COOL_THRESHOLD to keep going, because a shot that cuts out mid-exchange is worse
## than three dull frames.
func is_hot() -> bool:
	return _hot


## A DECISIVE BEAT — the thing a clip should end on. Either model counts: an HP
## knockdown (the tower's rule) or a ring-out (this stage's rule). Reading only the
## first is what made a directed capture run to its full frame budget through two
## fighters repeatedly launching each other off the rim.
func saw_knockdown() -> bool:
	return _knockdown_at >= 0.0 or _ringout_at >= 0.0


func _decisive_at() -> float:
	if _knockdown_at >= 0.0 and _ringout_at >= 0.0:
		return minf(_knockdown_at, _ringout_at)
	return maxf(_knockdown_at, _ringout_at)


func seconds_since_knockdown() -> float:
	var at: float = _decisive_at()
	return -1.0 if at < 0.0 else _clock - at


func clock() -> float:
	return _clock


## The machine-readable story of the fight, for a clip manifest.
func report() -> Dictionary:
	return {
		"duration": snappedf(_clock, 0.01),
		"peak_heat": snappedf(_peak_heat, 0.01),
		"peak_at": snappedf(_peak_at, 0.01),
		"hot_since": snappedf(_hot_since, 0.01),
		"knockdown_at": snappedf(_knockdown_at, 0.01),
		"ringout_at": snappedf(_ringout_at, 0.01),
		"decisive_at": snappedf(_decisive_at(), 0.01),
		"beats": _beats,
	}
