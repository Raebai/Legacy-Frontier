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
## ⚠ 300 -> 190, BECAUSE THE FIGHTERS WERE SPECKS. Margin is pure empty space added
## around the pair before the zoom is solved, so on this 683 px base viewport 300 px
## of slack per side is most of the shot. Measured on a real 1920x1080 clip frame: the
## Stormcaller drew about 90 px tall — roughly 8% of frame height — and the whole
## procedural rig, legs included, was too small to read at all. The maker's note is
## exactly that: the figures need to be legible in a bot-vs-bot clip.
##
## The containment rule above is untouched — this only stops the camera pulling back
## further than it has to. ZOOM_MIN still lets it go wide when the pair genuinely
## spreads, which is the case that note was written about. FEEL: the maker judges the
## framing at F5, and these two numbers are the dial.
##
## ⚠ 190/200 PUT THE FIGHTERS AT ~6% OF FRAME HEIGHT. Measured on a 1:1 crop of a
## 1920x1080 delivered frame: a rig reads ~65 px tall. At that size two stick figures
## are two identically-shaped lines told apart only by colour, and the screen-space
## chromatic aberration (0.7 at idle) sits on limbs 2-3 px wide, so a real fraction of
## each figure IS colour fringe. The margin is pure slack — the containment rule in
## `_fit_zoom` still guarantees both fighters stay in shot — so cutting it costs
## nothing but empty sky.
const FRAME_MARGIN: float = 110.0
## ...and the slack a HOT moment is allowed to shrink that to. See `_frame`.
const FRAME_MARGIN_HOT: float = 70.0
## The same two numbers on y. Smaller, because a 31 px stick figure needs far less
## headroom than two fighters need shoulder room, and because the eye is already
## lifted (EYE_LIFT) to put the floor in the lower third.
const FRAME_MARGIN_V: float = 130.0
const FRAME_MARGIN_V_HOT: float = 85.0
## ⚠ 0.42 -> 0.49, AND THE FLOOR IS NOT WHERE THE FIX IS. Read to the end.
##
## Three previous passes attacked "the fighters are specks" by cutting FRAME_MARGIN
## (300 -> 190 -> 110) and raising ZOOM_MAX. None of them could work, because the
## binding constraint was never the margin: `_fit_zoom` solves containment and then
## clamps to THIS, so whenever the pair separates far enough the solved fit falls to
## the floor and the floor is where the shot sits. The margin only matters above it.
##
## The arithmetic, on this project's 640x360 base viewport with a ~31 px rig:
##
##     zoom   rig on screen   share of frame height
##     0.42       13 px              3.6%       <- measured on a delivered frame,
##     0.49       15 px              4.2%          and I could not find the fighters
##     0.66       20 px              5.7%
##
## ⚠ IT IS 0.49 AND NOT MORE, AND THE SUITE IS WHY. 0.75 was tried first and
## `a_hot_exchange_stays_in_frame` failed it honestly: a 900 px exchange with the
## victim lean applied needs 0.50 to keep the far fighter, so a 0.75 floor throws
## somebody out of the most watchable moment of the fight. Containment and legibility
## are in genuine conflict at these separations and no single constant resolves it —
## which is what `_relieve_the_lean` below is for, and it is where the real gain is.
const ZOOM_MIN: float = 0.49
## The zoom under which a rig stops being a figure and becomes a mark. Not a clamp —
## a TRIGGER: below this the camera gives up its leans to buy the shot back. See
## `_relieve_the_lean`.
const LEGIBLE_ZOOM: float = 0.72
## ⚠ THE CEILING, AND IT IS THE REAL REASON THE FIGHTERS READ SMALL. Cutting
## FRAME_MARGIN alone could not make a close duel bigger: once the solved fit passes
## this number the camera stops punching in, so at 1.15 two fighters standing near
## each other were framed exactly as loosely as two fighters standing apart.
##
## `slice7_test_clipframing` caught that directly and is the reason this moved: with
## the tighter margins BOTH the cold and the hot shot clamped to 1.15, so "a hot
## moment is a TIGHTER shot" became false — the suite was measuring the ceiling, not
## the framing.
##
## Raising it is SAFE BY CONSTRUCTION rather than by judgement: `_fit_zoom` solves the
## containment first and only then clamps, so this can never crop a fighter out. It
## binds solely on pairs that are already close together — which is exactly the case
## where the picture was too wide. At 1.45 the visible world is ~441 units across
## against a 1160-unit room, so there is no edge to reveal.
const ZOOM_MAX: float = 1.45
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

# ══ PORTRAIT ═══════════════════════════════════════════════════════════════
## ⚠ THIS DIRECTOR HAD NO PORTRAIT BRANCH AT ALL, and every number above is sized
## for a 640x360 design box. The portrait framing work in commit b01bbd8 landed on
## `VersusArena`'s SHOWCASE camera — a different camera from the one the clip engine
## films through — so a 9:16 clip was framed as if it were 16:9.
##
## MEASURED off a real 1080x1920 render: `get_visible_rect()` answers 640x1137 in
## portrait against 640x360 in landscape. The width is identical, so `_fit_zoom`
## solves the SAME zoom — and the extra 777 units of height are spent on sky above
## and on the sub-floor below, the void under the terrain and the backdrop repeating
## beneath it. About EIGHTY PERCENT of the canvas held no fight. Maker: "when in
## verticle form for those clips all that dead space is kinda weird honestly maybe
## better camera action and panning."
##
## Landscape is untouched: every constant below is reached only when the viewport is
## actually taller than it is wide, so the framing suites keep asserting the same
## numbers they always did.

## Where the ground line sits, as a fraction of frame height. Solving for the camera
## y that puts it there — `cam_y = ground + half_h * (1 - 2f)` — is the only thing
## that works, because how much frame sits below the floor depends on the ZOOM, and
## the zoom changes every frame. A constant lift (EYE_LIFT) cannot do it.
const PORTRAIT_GROUND_AT: float = 0.72
## The band above the floor the eye may rise into. Wider than `VERTICAL_BAND`, which
## was sized for a 360-tall design box and would otherwise undo the solve above.
const PORTRAIT_BAND: float = 620.0
## ⚠ THE FLOOR ON THE ZOOM IS WHERE THE SIZE ACTUALLY COMES FROM, and it is the one
## number here that changes what the camera DECIDES rather than where it points.
##
## `_fit_zoom` solves a shot containing BOTH fighters; they spawn 560 world px apart,
## so the fit pins at ~0.95 and a rig draws ~2.6% of a 9:16 canvas — a speck on a
## phone. Refusing to pull back past this means that when the pair separates far
## enough, the shot STAYS legible and the distant fighter leaves frame instead. That
## is the trade b01bbd8 named and declined to make ("a vertical clip should follow
## the action and let a distant fighter leave frame"), and the maker has now asked
## for exactly it. At 1.25 the shot holds both while they are within ~510 px of each
## other, which is nearly all of the actual fighting, and a rig reads ~3.4%.
##
## ⚠ 1.25 -> 2.10, AND THE MEASUREMENT IS WHY. `probe_directed_framing ... portrait`
## reported the delivered vertical shot at **SUBJECT 4.4% of frame height** — on a
## 1080x1920 phone that is a 84 px figure, which is what the maker means by "the
## graphics in the video are horrible ... not good quality like the gameplay". It is
## not a fidelity problem: pulled at 1:1 the render is clean, anti-aliased linework.
## The subject is simply tiny, and h264 spends its bits on a big flat background while
## the thing worth seeing is a few dozen pixels tall.
##
## Raising the FLOOR is the only lever that moves this, per the three failed attempts
## documented above: once separation pins the fit at the floor, trimming margins buys
## nothing. The cost is paid in containment, knowingly — the maker asked for exactly
## this trade twice, most recently *"if the camera shows more of the map or follows the
## character better or zooms out where it needs to"*.
const PORTRAIT_ZOOM_MIN: float = 2.10
## ...and the ceiling, raised again so a clinch can actually fill a tall frame.
const PORTRAIT_ZOOM_MAX: float = 3.40
## Horizontal slack in portrait. Smaller than `FRAME_MARGIN`: a tall frame already
## has headroom above the fighters for a beam to land in, so paying for it sideways
## as well is paying twice.
## ⚠ 60 -> 40: slack is a fixed WORLD distance, so a tighter frame spends a bigger
## fraction of itself on it. At the old floor 120 px of slack was 23% of the visible
## width; at the new one it would have been 39%, i.e. the margin would have eaten most
## of what raising the floor just bought.
const PORTRAIT_MARGIN: float = 40.0
## How far inside the frame edge a fighter has to be before `_hold_a_subject` calls
## them "in shot". A body sliced by the border reads as lost, not as framed.
## ⚠ 110 -> 72, for the same reason and it matters MORE here: this is the recovery net
## that pulls the eye back onto somebody when the leans have walked it off everyone,
## and a tighter frame means it must fire sooner. Left at 110 against the new floor it
## would have been calling "nobody is in shot" across most of the visible width.
const PORTRAIT_HOLD_MARGIN: float = 72.0

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
## Does this director decide WHERE the shot points, or only serve the transient
## effects over somebody else's framing?
##
## A played duel and free play frame themselves in `VersusArena._update_showcase_camera`
## — that framing is tuned and is not being replaced. But those modes had the same dead
## `combat_camera` group as Watch Bots did, so they shook and punched exactly as little.
## Setting this false makes the director an OPERATOR ONLY: it still answers the group,
## still runs the trauma and zoom envelopes, and hands them back through `compose`.
var frames_the_shot: bool = true

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
	if cam != null:
		_zoom_smoothed = cam.zoom.x
		# ⚠ THE DIRECTOR DOES ITS OWN SMOOTHING, AND TWO LAGS IN SERIES IS THE BUG.
		# Maker: *"get the camera logic to work properly focussing on the two
		# fighting"*. `_frame` already lerps `global_position` at POS_LERP=7 toward a
		# target that is itself a smoothed solve; Godot's built-in smoothing then lags
		# THAT by another 4.0, so the shot trails a moving fight by enough that the
		# fighters sit off-centre for the whole exchange. `_update_free_camera` turns
		# it off for exactly this reason and has done since it was written.
		#
		# ⚠ ONLY WHEN THIS DIRECTOR IS THE ONE FRAMING. `_update_showcase_camera`
		# assigns `global_position` OUTRIGHT with no lerp of its own and gets all of
		# its smoothing from this flag — turning it off there would not un-lag that
		# camera, it would make it snap to the pair midpoint every single frame.
		if frames_the_shot:
			cam.position_smoothing_enabled = false
	# THE DIRECTOR IS THE CAMERA OPERATOR, so it answers to the camera group. See the
	# `# ---- the camera OPERATOR` block for why this is the director and not the
	# Camera2D it drives.
	if not is_in_group(&"combat_camera"):
		add_to_group(&"combat_camera")


func _process(delta: float) -> void:
	advance(delta)


# ---- the camera OPERATOR ------------------------------------------------------
# ⚠ EVERY `Juice.*_camera` CALL IN A BOT DUEL WAS A SILENT NO-OP, and that is most of
# what "the camera does not follow the fight" feels like from the couch — the shot
# never flinches, never punches in on a kill, never rattles on a hit.
#
# The cause was structural, not a missing `add_to_group`. `Juice` walks the
# `combat_camera` group and calls `add_shake` / `kick` / `zoom_punch` / `zoom_pull`
# behind `has_method` guards; the only class implementing them is `CombatCamera`,
# which lives on the HERO scene. A bot duel builds a bare `Camera2D.new()` for its
# pair framing and disables both hero cameras — so the group contained two disabled,
# invisible cameras and the one being looked through was in no group at all. Adding
# the raw camera to the group would have changed nothing: it has none of the methods.
#
# ⚠ AND PUTTING `CombatCamera` ON IT WOULD FIGHT THIS FILE, which is why it is not the
# answer either. That script writes `zoom` every frame from its own `_zoom_base`, and
# clamps it to [1.0, 2.6] — the director frames a duel between 0.49 and 1.45, so the
# first frame would have snapped the shot to more than double its correct zoom.
# `set_base_zoom` also persists to `GameState.camera_zoom`, i.e. it would overwrite the
# player's saved Settings preference sixty times a second.
#
# So the OPERATOR answers instead of the camera. The director already owns the
# transform and already writes it every frame, so a punch composes into its own
# solution BY CONSTRUCTION rather than racing it — there is no second writer to
# arbitrate with. Shake rides `offset`, which `_frame` never touches and which
# therefore cannot feed back into the position lerp.

## Shake energy, 0..1, decaying. Same trauma model + the same constants as
## `CombatCamera`, so a hit shakes a duel by the amount it already shakes a run.
const SHAKE_TO_TRAUMA: float = 0.085
const TRAUMA_DECAY: float = 1.6
const MAX_SHAKE_OFFSET: Vector2 = Vector2(18.0, 12.0)
const NOISE_SPEED: float = 26.0
const KICK_MAX: float = 22.0
const KICK_RETURN_SPEED: float = 9.0

var _trauma: float = 0.0
var _noise_t: float = 0.0
var _kick: Vector2 = Vector2.ZERO
## The director's OWN smoothed zoom, never read back off the camera. Reading back
## would make a punch feed into the next frame's framing solve and slowly drag the
## whole shot in; keeping it here means punch and pull are strictly a presentation
## layer over a framing decision they cannot influence.
var _zoom_smoothed: float = 1.0
## ⚠ HAS THE SHOT BEEN ESTABLISHED YET? Maker, on the finished clips: *"why does the
## video always start in the random top left corner or something the camera"*.
##
## Both channels below EASE toward their solve — position at `POS_LERP` 7, zoom at
## `ZOOM_LERP` 2.6 — which is right for every frame except the first one, because on
## the first frame there is nothing behind them to ease FROM. The camera is a bare
## `Camera2D.new()` sitting whereever it was added, and `_zoom_smoothed` is seeded in
## `bind()` from that camera's default zoom (1.0) while a duel actually frames between
## 0.49 and 1.45. So every clip opened on an off-stage camera at the wrong zoom and
## spent its first ~0.5 s travelling to the fight — over the VS card, i.e. across the
## thumbnail and the whole hook.
##
## A lerp cannot fix this by being faster; the fault is the STARTING VALUE, not the
## rate. So the first framed frame ESTABLISHES the shot outright and every frame after
## it eases exactly as before. This is the same idea as `Camera2D.reset_smoothing()`,
## done on the director's own state because the director owns the transform
## (`bind` turns the built-in smoothing off whenever `frames_the_shot`).
var _established: bool = false
var _punch_amount: float = 0.0
var _punch_timer: float = 0.0
var _punch_duration: float = 0.18
var _pull_amount: float = 0.0
var _pull_elapsed: float = 0.0
var _pull_ein: float = 0.12
var _pull_hold: float = 0.5
var _pull_eout: float = 0.55
var _pull_active: bool = false


func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


## The live `Tuning` autoload's config, or the fallback when there isn't one (every
## headless suite and capture tool). Mirrors `CombatCamera._tune` exactly — reached
## through the tree rather than by `class_name`, because a `--script` tool compiles
## this file before any autoload exists.
func _tune(key: String, fallback: float) -> float:
	var t: Node = get_node_or_null(^"/root/Tuning")
	if t != null:
		var cfg: Variant = t.get(&"cfg")
		if cfg != null:
			var v: Variant = (cfg as Object).get(key)
			if v != null:
				return float(v)
	return fallback


## The legacy pixel-ish API every existing call site passes (~2..12).
func add_shake(amount: float) -> void:
	add_trauma(amount * SHAKE_TO_TRAUMA)


## Read by `PostProcess` so the screen-space aberration tracks the same energy as
## the shake. Without this the grade goes flat for the whole duel.
func trauma() -> float:
	return _trauma


func kick(dir: Vector2, amount: float) -> void:
	_kick = (_kick + dir.normalized() * amount).limit_length(KICK_MAX)


func zoom_punch(amount: float = 0.1, duration: float = 0.18) -> void:
	if duration <= 0.0:
		return
	_punch_amount = amount
	_punch_duration = duration
	_punch_timer = duration


func zoom_pull(amount: float = 0.16, hold: float = 0.5, ease_in: float = 0.12,
		ease_out: float = 0.55) -> void:
	if amount <= 0.0:
		return
	_pull_amount = maxf(_pull_amount, amount) if _pull_active else amount
	_pull_ein = maxf(ease_in, 0.001)
	_pull_hold = maxf(hold, 0.0)
	_pull_eout = maxf(ease_out, 0.001)
	_pull_elapsed = 0.0
	_pull_active = true


## Punch factor (>1 tightens) — a spike that eases straight back out.
func _punch_factor(delta: float) -> float:
	if _punch_timer <= 0.0:
		return 1.0
	_punch_timer = maxf(_punch_timer - delta, 0.0)
	if _punch_timer <= 0.0:
		return 1.0
	return 1.0 + _punch_amount * (_punch_timer / _punch_duration)


## Pull factor (<1 widens) across the ease-in / hold / ease-out envelope.
func _pull_factor(delta: float) -> float:
	if not _pull_active:
		return 1.0
	_pull_elapsed += delta
	var total: float = _pull_ein + _pull_hold + _pull_eout
	if _pull_elapsed >= total:
		_pull_active = false
		return 1.0
	var p: float = 1.0
	if _pull_elapsed < _pull_ein:
		p = smoothstep(0.0, 1.0, _pull_elapsed / _pull_ein)
	elif _pull_elapsed < _pull_ein + _pull_hold:
		p = 1.0
	else:
		p = 1.0 - smoothstep(0.0, 1.0, (_pull_elapsed - _pull_ein - _pull_hold) / _pull_eout)
	return 1.0 - _pull_amount * p


## Lay the transient effects over a framing decision. Returns the zoom to write and
## writes `camera.offset` itself.
##
## ⚠ CALL THIS EXACTLY ONCE PER FRAME AND FROM ONE PLACE. It ADVANCES the envelopes,
## so a second caller in the same frame would run every punch at double speed. That is
## why `_update_showcase_camera` skips itself entirely when this director is framing:
## the two are alternatives, never a pair.
func compose(base_zoom: float, delta: float) -> float:
	if camera != null:
		# Shake rides `offset` — a channel `_frame` never reads — so a rattling camera
		# cannot feed itself back into the position lerp and drift the framing.
		camera.offset = _shake_offset(delta)
	return base_zoom * _punch_factor(delta) * _pull_factor(delta)


## Trauma^2 shake plus the directional kick, as a camera OFFSET. Squared so small
## hits barely wobble and big ones slam, and built from two incommensurate sines per
## axis so it reads as a rumble that settles rather than per-frame static.
func _shake_offset(delta: float) -> Vector2:
	_noise_t += delta * NOISE_SPEED
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_kick = _kick.lerp(Vector2.ZERO, minf(KICK_RETURN_SPEED * delta, 1.0))
	# ⚠ THE ACCESSIBILITY SLIDER DID NOTHING IN A DUEL. Maker: *"im worried the screen
	# shake may be too strong like some instagram / tiktok viewers may be
	# uncomfortable"*. `Tuning.cfg.shake_scale` exists, defaults to 0.7 on an earlier
	# "the screen shake is a little too much", and is wired to the Screenshake slider
	# in the pause menu — but only `CombatCamera` ever read it. This director is the
	# operator for EVERY versus mode (Watch Bots, the directed duel, every clip
	# capture), so in exactly the footage that goes to an audience the setting was
	# inert and the shake ran at 100%.
	#
	# Same expression as `CombatCamera._apply_camera`, deliberately, so the two
	# operators cannot drift: one slider, one meaning, whichever camera is live.
	var shake: float = _trauma * _trauma * _tune("shake_scale", 1.0)
	if shake <= 0.0 and _kick == Vector2.ZERO:
		return Vector2.ZERO
	var nx: float = sin(_noise_t) * 0.6 + sin(_noise_t * 2.7 + 1.3) * 0.4
	var ny: float = cos(_noise_t * 1.3 + 0.9) * 0.6 + sin(_noise_t * 3.4) * 0.4
	return _kick + Vector2(MAX_SHAKE_OFFSET.x * shake * nx, MAX_SHAKE_OFFSET.y * shake * ny)


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
	if frames_the_shot:
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
		# ⚠ STILL BLEED THE EFFECTS. `compose` is what decays the trauma and closes the
		# zoom envelopes, so returning outright here leaves a camera that was shaking
		# when the last fighter left the scan frozen at whatever offset it happened to
		# hold — permanently, because nothing else writes that channel.
		if camera != null:
			var held: float = compose(_zoom_smoothed, delta)
			camera.zoom = Vector2(held, held)
		return
	# ⚠ A BODY THAT HAS LEFT THE MAP MUST NOT OWN THE SHOT. `showcase_ringout` is on,
	# so a big enough hit launches a fighter clean off the stage — and every solve
	# below (the midpoint, the leans, and `_fit_zoom`'s containment) would then be
	# working to keep a body nobody can see inside the frame, which widens the shot
	# until the fighters who ARE visible are specks. The same fault was found and fixed
	# in `VersusArena._update_showcase_camera`; this is the copy that films the clips.
	# If every body has left the stage, keep them all rather than framing on nothing.
	var pts: Array[Vector2] = []
	for f: Node2D in fighters:
		var q: Vector2 = f.global_position
		if q.x >= stage.position.x and q.x <= stage.end.x:
			pts.append(q)
	if pts.is_empty():
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
	# ⚠ ZOOM-AWARE, BECAUSE 340 IS A CONSTANT AND THE FRAME'S WIDTH IS NOT.
	# This was `stage.position.x + 340.0 .. stage.end.x - 340.0`. 340 is the world
	# half-width of the shot at ONE zoom (0.94); the director lives between ZOOM_MIN
	# 0.49 and ZOOM_MAX 1.45, where the half-width runs 653 down to 221 px. So the rail
	# was too loose when the shot was wide (it let the void past the rim in) and too
	# TIGHT when it was close — and close is the common case, which is when the camera
	# stops following and the pair slide off centre. That is the maker's *"it drifts to
	# the side sometimes"*, and the identical constant was already fixed in
	# `VersusArena`; this is the copy that actually frames a bot fight, since
	# `BotMatch` always runs the director and `_update_showcase_camera` steps aside.
	#
	# Solved off `_zoom_smoothed` (last frame's answer) because the eye is clamped
	# BEFORE the zoom is fitted and the two cannot both go first. `_eye_y` already
	# takes exactly this approach in portrait, for exactly this reason.
	var half_w: float = _view().x / (2.0 * maxf(_zoom_smoothed, 0.01))
	var lo: float = stage.position.x + half_w
	var hi: float = stage.end.x - half_w
	var eye_x: float = stage.get_center().x if lo >= hi else clampf(target.x, lo, hi)
	var eye: Vector2 = Vector2(eye_x, _eye_y(target.y))
	# ⚠ AND SOMEBODY HAS TO BE IN IT. See `_hold_a_subject`.
	eye = _hold_a_subject(eye, pts)

	var want: float = _fit_zoom(pts, eye)
	# ⚠ THE LEANS ARE A LUXURY, AND THIS IS WHERE THEY ARE BILLED FOR IT.
	#
	# Every lean above (victim, spell, KO) moves the eye OFF the pair's midpoint, and
	# an off-centre eye has to cover a bigger half-width to keep everybody in — so the
	# containment solve answers with a wider shot, and the fighters get smaller. On a
	# 900 px hot exchange the victim lean alone costs 0.66 -> 0.50 of zoom, which is a
	# quarter off the size of both figures, spent on WHERE the picture is centred.
	#
	# That is a good trade when there is room and a bad one when there is not. So
	# below `LEGIBLE_ZOOM` the leans are given back: re-solve from the plain midpoint
	# and take whichever eye frames bigger. It can only ever tighten the shot, and
	# containment stays exact because the fit is re-solved AT the eye actually used —
	# the same "clamp first, fit second" rule the block above rests on.
	# ⚠ NOT IN PORTRAIT. Maker: *"the camera in the clip doesnt follow the characters
	# fighting"*, and this line is why.
	#
	# `_relieve_the_lean` gives the victim/spell/KO leans BACK whenever the shot has
	# gone illegible, by re-solving from the pair's plain MIDPOINT and keeping whichever
	# frames bigger. In landscape that is right: the shot still contains both fighters,
	# so re-centring costs nothing and buys size.
	#
	# In portrait it is exactly backwards. `PORTRAIT_ZOOM_MIN` deliberately refuses to
	# pull back far enough to hold a separated pair, so the midpoint is no longer a
	# place either fighter is standing — it is the empty air BETWEEN them. Relieving
	# the lean therefore walks the camera off the action and points it at that gap,
	# which is the "doesn't follow" the maker is describing. The lean IS the follow.
	if not is_portrait():
		var relieved: Array = _relieve_the_lean(pts, mid, eye, want)
		eye = relieved[0]
		want = relieved[1]
	else:
		eye = _recentre_if_the_pair_fits(pts, mid, eye, want)
	_sample_zoom(want)
	# The FRAMING decision, smoothed on the director's own state. See `_zoom_smoothed`
	# for why this is not read back off the camera.
	if _established:
		_zoom_smoothed = lerpf(_zoom_smoothed, want, clampf(delta * ZOOM_LERP, 0.0, 1.0))
	else:
		# See `_established`. Nothing to ease from on the opening frame.
		_zoom_smoothed = want
	# ...then the PRESENTATION on top of it. Both factors are 1.0 whenever nothing is
	# playing, so a settled shot is byte-identical to the framing solve and the
	# framing suite still asserts against `camera.zoom` directly.
	var z: float = compose(_zoom_smoothed, delta)
	camera.zoom = Vector2(z, z)
	if _established:
		camera.global_position = camera.global_position.lerp(eye,
			clampf(delta * POS_LERP, 0.0, 1.0))
	else:
		camera.global_position = eye
		_established = true


## PORTRAIT ONLY. Pull the eye back toward the pair's midpoint, but ONLY on the frames
## where both fighters would then still be in shot.
##
## ⚠ THIS IS THE OTHER HALF OF THE "NOT IN PORTRAIT" RULE ABOVE, AND WITHOUT IT
## RAISING `PORTRAIT_ZOOM_MIN` MAKES THE CLIP WORSE. That rule is right about the case
## it was written for: when the pair is too far apart to contain, their midpoint is
## empty air and re-centring there is the "camera doesn't follow" bug. But it was
## applied to EVERY frame, including the ones where the pair fits easily — and there,
## an eye leaned off the midpoint pushes a fighter out of a frame that had room for
## them both.
##
## MEASURED, `probe_directed_framing ... portrait` at the raised zoom floor: mean
## separation was only ~135 world px against a ~287 px visible width, yet a fighter was
## out of frame on 40-65% of samples. The leans were doing that, not the zoom.
##
## So the test is containment, not legibility: if the plain midpoint holds both, use it;
## otherwise keep the lean, because then the lean genuinely IS the follow.
func _recentre_if_the_pair_fits(pts: Array[Vector2], mid: Vector2, eye: Vector2,
		want: float) -> Vector2:
	if pts.size() < 2 or want <= 0.0:
		return eye
	var half_view: float = (_view().x / want) * 0.5 - PORTRAIT_MARGIN
	if half_view <= 0.0:
		return eye
	var reach: float = 0.0
	for p: Vector2 in pts:
		reach = maxf(reach, absf(p.x - mid.x))
	if reach > half_view:
		return eye          # cannot hold both from the midpoint — the lean is the follow
	# Both fit. Keep the eye's solved height (the ground anchor owns y) and take the
	# midpoint's x, clamped exactly the way `_frame` clamps its own eye so the camera
	# still cannot travel past the painted world.
	var lo: float = stage.position.x + half_view
	var hi: float = stage.end.x - half_view
	if lo > hi:
		return eye
	return Vector2(clampf(mid.x, lo, hi), eye.y)


## Give the leans back when the shot has gone illegible. Returns [eye, zoom].
##
## PUBLIC AND PURE-ISH so the suite can put the two eyes side by side rather than
## inferring the rule from a settled camera: the assertion worth making is "the
## returned zoom is never smaller than the leaned one", which is what makes this
## safe to run on every frame.
func _relieve_the_lean(pts: Array[Vector2], mid: Vector2, eye: Vector2,
		want: float) -> Array:
	if want >= LEGIBLE_ZOOM:
		return [eye, want]
	var plain: Vector2 = Vector2(
		clampf(mid.x, stage.position.x + 340.0, stage.end.x - 340.0),
		_eye_y(mid.y))
	var plain_fit: float = _fit_zoom(pts, plain)
	if plain_fit <= want:
		return [eye, want]
	# Only travel as far off the lean as the legibility actually needed. A full snap
	# to the midpoint every time the shot tightens reads as the camera flinching;
	# this keeps some of the lean whenever some of it was affordable.
	var t: float = clampf((LEGIBLE_ZOOM - want) / maxf(LEGIBLE_ZOOM - ZOOM_MIN, 0.001),
		0.0, 1.0)
	var blended: Vector2 = eye.lerp(plain, t)
	return [blended, _fit_zoom(pts, blended)]


## THE HARD CONSTRAINT: the widest zoom that still contains every fighter, seen
## from `eye`, with slack that a hot moment is allowed to shrink.
##
## Public and pure so a test can assert the rule directly rather than inferring it
## from a rendered frame — see `tools/slice7_test_clipframing.gd`, which is the
## assertion behind the maker's *"so the audience can see it all all the time"*.
func _fit_zoom(pts: Array[Vector2], eye: Vector2) -> float:
	var view: Vector2 = _view()
	# Heat tightens by eating the slack, NEVER by punching past containment.
	var slack_x: float = lerpf(FRAME_MARGIN, FRAME_MARGIN_HOT, clampf(_heat, 0.0, 1.0))
	var slack_y: float = lerpf(FRAME_MARGIN_V, FRAME_MARGIN_V_HOT, clampf(_heat, 0.0, 1.0))
	if is_portrait():
		slack_x = PORTRAIT_MARGIN
	var need_x: float = 0.0
	var need_y: float = 0.0
	for p: Vector2 in pts:
		need_x = maxf(need_x, absf(p.x - eye.x))
		need_y = maxf(need_y, absf(p.y - eye.y))
	var fit: float = minf(
		view.x / maxf(need_x * 2.0 + slack_x, 1.0),
		view.y / maxf(need_y * 2.0 + slack_y, 1.0))
	if is_portrait():
		# ⚠ THE FLOOR HERE DELIBERATELY BREAKS CONTAINMENT, which every other line in
		# this file works to preserve. See PORTRAIT_ZOOM_MIN: in a 9:16 frame holding
		# both fighters costs so much zoom that neither is legible, so past a certain
		# separation the shot stops widening and the far fighter leaves instead.
		return clampf(fit, PORTRAIT_ZOOM_MIN, PORTRAIT_ZOOM_MAX)
	return clampf(fit, ZOOM_MIN, ZOOM_MAX)


## The viewport's visible rect, in the design-space units every framing constant in
## this file is written in. 640x360 in landscape, 640x1137 at 1080x1920.
func _view() -> Vector2:
	var vp: Viewport = get_viewport()
	var v: Vector2 = Vector2(1280.0, 720.0)
	if vp != null:
		v = Vector2(vp.get_visible_rect().size)
	return Vector2(maxf(v.x, 1.0), maxf(v.y, 1.0))


## True when the frame is meaningfully taller than it is wide. Read from the VIEWPORT
## rather than from a flag, so a clip shoot, a phone export and a resized window all
## agree without anyone remembering to set anything. The 1.15 is slack, not a guess:
## it keeps a merely-squarish window on the landscape path it was tuned for.
func is_portrait() -> bool:
	var v: Vector2 = _view()
	return v.y > v.x * 1.15


## ⚠ THE PORTRAIT SHOT CAN LOSE EVERY FIGHTER, AND IT DID.
##
## Rendered and looked at: six seconds into a live bout, both health bars moving, the
## frame held an empty stretch of stage with one fighter's sigil clipping the left
## margin and neither body on screen at all.
##
## Two things this file does on purpose combine into that. `PORTRAIT_ZOOM_MIN` refuses
## to widen past 1.25, and the portrait path skips `_relieve_the_lean` — which was the
## only thing that ever pulled the eye back onto the pair. So the eye is free to ride
## the victim/spell leans, and `_spell_centroid` includes tall, distant spectacles: a
## Stormcaller's lightning column is hundreds of pixels from the man who cast it. The
## lean walks the camera onto the SPELL and the narrow frame leaves the FIGHTERS
## outside it.
##
## Rather than weaken either (a wider shot is what made everyone a speck, and killing
## the lean is what stopped it following), this is a floor under both: whatever the
## leans decide, the eye is pulled back until at least ONE fighter is inside the
## frame. Nothing happens while somebody is already in shot, so a well-framed
## exchange is untouched — this only fires on the frames that had nobody in them.
##
## Landscape returns unchanged: containment there is exact, so this can never trigger.
func _hold_a_subject(eye: Vector2, pts: Array[Vector2]) -> Vector2:
	if not is_portrait() or pts.is_empty():
		return eye
	var half_w: float = _view().x / (2.0 * maxf(_zoom_smoothed, 0.01))
	# Not the very edge — a fighter sliced by the frame border reads as lost too.
	var keep: float = maxf(half_w - PORTRAIT_HOLD_MARGIN, 40.0)
	var nearest: Vector2 = pts[0]
	var best: float = INF
	for p: Vector2 in pts:
		var d: float = absf(p.x - eye.x)
		if d <= keep:
			return eye                       # somebody is already in shot
		if d < best:
			best = d
			nearest = p
	# Nobody. Slide the eye along x until the closest fighter is just inside.
	return Vector2(nearest.x - signf(nearest.x - eye.x) * keep, eye.y)


## Where the eye sits vertically. Landscape keeps the constant lift it always had.
##
## ⚠ PORTRAIT SOLVES FOR THE GROUND LINE INSTEAD, because the amount of frame below
## the floor depends on the zoom and the zoom moves every frame — so no constant can
## hold it. Solving `f = (ground - (cam_y - half_h)) / (2*half_h)` for `cam_y` puts
## the floor at `PORTRAIT_GROUND_AT` of frame height at ANY zoom.
##
## `minf` against the old lift, so a fighter launched high still pulls the eye up:
## whichever wants to be HIGHER (smaller y) wins. The zoom used is last frame's
## smoothed value — the true one is solved from this eye, so using it here would be
## circular, and one frame of lag on a camera is invisible.
func _eye_y(target_y: float) -> float:
	var lifted: float = target_y - EYE_LIFT
	if not is_portrait():
		return clampf(lifted, ground_y - VERTICAL_BAND, ground_y - 40.0)
	var half_h: float = _view().y / (2.0 * maxf(_zoom_smoothed, 0.01))
	var anchored: float = ground_y + half_h * (1.0 - 2.0 * PORTRAIT_GROUND_AT)
	return clampf(minf(lifted, anchored), ground_y - PORTRAIT_BAND, ground_y - 40.0)


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
## ⚠ THE ONE MEASURE OF "ARE THE FIGHTERS BIG ENOUGH TO SEE" THAT IS NOT A PROXY.
##
## `python-tools/clip_review.py` scores a delivered mp4 and can count a blowout
## honestly, because a bloomed fill IS a luminance fact. It CANNOT count this one:
## pixels cannot tell a fighter from a crate, so a wide empty shot full of background
## furniture scores as busy. Its first attempt at this metric passed the very frame
## it had been calibrated on.
##
## The camera knows exactly. `zoom * RIG_WORLD_PX / viewport_height` is the share of
## the picture a fighter occupies, so it goes in the clip's own paperwork and the
## pixel tool is demoted to corroboration.
const RIG_WORLD_PX: float = 31.0

var _zoom_lo: float = 99.0
var _zoom_hi: float = 0.0
var _zoom_sum: float = 0.0
var _zoom_n: int = 0


func _sample_zoom(z: float) -> void:
	_zoom_lo = minf(_zoom_lo, z)
	_zoom_hi = maxf(_zoom_hi, z)
	_zoom_sum += z
	_zoom_n += 1


## What share of frame height a fighter fills at `z`. The number the maker is
## actually judging when they say the figures are too small.
func subject_share(z: float) -> float:
	var vh: float = 360.0
	var vp: Viewport = get_viewport()
	if vp != null:
		vh = maxf(float(vp.get_visible_rect().size.y), 1.0)
	return z * RIG_WORLD_PX / vh


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
		"zoom_min": snappedf(_zoom_lo if _zoom_n > 0 else 0.0, 0.001),
		"zoom_max": snappedf(_zoom_hi, 0.001),
		"zoom_mean": snappedf(_zoom_sum / maxf(float(_zoom_n), 1.0), 0.001),
		"subject_share_min": snappedf(subject_share(_zoom_lo if _zoom_n > 0 else 0.0), 0.0001),
		"subject_share_mean": snappedf(
			subject_share(_zoom_sum / maxf(float(_zoom_n), 1.0)), 0.0001),
	}
