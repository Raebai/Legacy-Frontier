class_name Telegraph
extends Node2D
## Pre-attack danger indicator — redesigned into distinct, animated "prep noters"
## that read as a signal FROM the caster instead of a flat red shape planted on
## the target. Each archetype gets its own sigil built from the arcane-circle
## vocabulary (rings, runic ticks, stars, apertures, charge lanes), tinted with a
## per-archetype accent, and a bright TETHER back to the caster (`source`) so you
## always see WHO is doing it and WHAT. Pairs with CasterSignal (the charge-glow
## on the body). Emits `fired` once when the windup elapses, draws a brief fade,
## then frees itself.
##
## Geometry (Shape CIRCLE/LINE) + timing are UNCHANGED so the "snapshot the spot,
## dodge the tell" grammar and the headless tests still hold; only the visuals +
## the `style`/`accent`/`source`/`aim_dir` reads are new. Primitive-drawn.
##
## ══ THE TELL LANGUAGE — THE THREE RULES THIS FILE ENFORCES ═══════════════════
## The tells were audited style-by-style against the geometry that actually deals
## the damage (`tools/probe_tell_audit.gd`). Three rules came out of it, and the
## file now obeys all three where it is able to. Where the RULE is broken by a
## CALLER rather than by this file, the probe names the caller — this file cannot
## reach into `Enemy.gd` / `Hero.gd`.
##
##   1. COLOUR CARRIES ELEMENT. `accent` is the whole colour statement. Three of
##      the eight styles used to paint hard-coded red/orange OVER the accent —
##      ZONE's charge fill, BOMB's countdown arc and inner fill, and LANE's fired
##      flash. So an ice mage's ground zone and a shadow mage's ground zone were
##      the same orange picture, and the ring around them disagreed with its own
##      middle. Every one of those now derives from `accent`; the only colours
##      still written literally are WHITE hot-cores and leading edges, which are
##      an intensity statement (this is at full charge) and not a hue statement.
##   2. SHAPE CARRIES CONSEQUENCE. CIRCLE = "this ground". LINE = "this corridor".
##      FIST / CRESCENT = "this blow, arriving". The drawn extent must not claim
##      more ground than `danger_shape()` reports, because `danger_shape()` is what
##      the dodge layer answers — `_work_reach` measures exactly that and the
##      budget suite pins it.
##   3. WINDUP IS PROPORTIONAL TO DANGER. Owned by the callers (they pass it), but
##      `tools/probe_tell_audit.gd` tables every windup in the game against the
##      damage behind it so a new attack that tells for less than the ladder says
##      is visible rather than merely wrong.
##
## ══ COST ════════════════════════════════════════════════════════════════════
## A tell is on screen for every single attack in the game, so it is a per-frame
## tax on the whole roster the way `MagicCircle` is a tax on every cast. It had NO
## instrumentation and NO `graphics_quality` gate at all — the one layer that must
## stay readable on a phone was also the one layer that never got cheaper on one.
## Both now exist, in `MagicCircle`'s idiom (see the WORK COUNTERS block) and with
## `SpawnTell`'s pure-static plan functions so the LOW contract is assertable in a
## headless suite with no renderer.
##
## ⚠ CHEAPER, NEVER QUIETER. The tell is the fairness contract. Nothing below
## changes what a tell SAYS — no radius, no timing, no colour meaning, no ghost
## count at HIGH. What changed is how many draw commands say it.

signal fired

const FADE_TIME: float = 0.15
## Crisp danger-red baseline (this-will-hurt). Per-archetype accents tint toward
## the enemy's element so casters/chargers/assassins read distinct at a glance.
const RING_COLOR: Color = Color(0.95, 0.16, 0.13, 0.9)

## ══ THE CRESCENT'S SWEEP ═══════════════════════════════════════════════════
## How many fading copies trail the blade of air. Three is the point where the eye
## reads a SWEEP rather than a stack; four starts to read as separate blades. They
## are drawn at decreasing reach, so together they trace where the edge has been.
const CRESCENT_GHOSTS: int = 3
## The same at `graphics_quality = LOW`. ONE ghost, not zero: the leading blade
## plus a single trail still reads as a sweep, and dropping to the bare blade
## would change what the tell says (a cut that appeared rather than travelled) on
## the one device where the read matters most. Each ghost is a 45-vertex polygon
## plus two polylines, so this is the single biggest saving in the file.
const CRESCENT_GHOSTS_LOW: int = 1
## How far back each ghost sits, as a fraction of the arc's own span. Tied to the
## span rather than to the lane so a bigger cut trails proportionally further.
const CRESCENT_GHOST_STEP: float = 0.30
## Alpha multiplier per ghost. Steep on purpose — a slow falloff reads as smearing.
const CRESCENT_GHOST_FALLOFF: float = 0.45
## Vertices along one half of a crescent's belly. 22 at HIGH; a crescent is at most
## ~40 px across on a 640x360 frame, so 11 is still under a pixel per step at LOW.
const CRESCENT_STEPS: int = 22
const CRESCENT_STEPS_LOW: int = 11

## Runic ticks around the ring, per style, and the LOW floor. Ticks are a COUNT the
## eye reads as "arcane" rather than a resolution, so they thin rather than vanish —
## a ring with no ticks is a different picture, not a cheaper one.
const TICKS_LOW_FACTOR: float = 0.5
const TICKS_MIN: int = 4

## Energy pulses sliding down the caster tether. Two at HIGH, one at LOW: the
## travel direction is the whole message and one pulse still states it.
const TETHER_PULSES: int = 2
const TETHER_PULSES_LOW: int = 1

## Chevron spacing down a charge lane, in px. Wider at LOW = fewer chevrons over
## the same lane, and the scroll speed is unchanged so the lane still rushes.
const CHEVRON_SPACING: float = 26.0
const CHEVRON_SPACING_LOW: float = 44.0

## ══ THE CONE ═══════════════════════════════════════════════════════════════
## Full segment budget for a cone's rim arc, before `MagicCircle.seg_of`'s sagitta
## rule and the arc's own angular FRACTION cut it down. 48 is ZONE's ring budget:
## a cone is a ring with a bite taken out of it and must not look coarser than one.
const CONE_ARC_SEGMENTS: int = 48
## Floor under the tessellation. Three points still make a wedge; two make a
## triangle that lies about a curved rim.
const CONE_ARC_MIN: int = 3
## The two alpha weights a cone can be drawn at.
##
## ⚠ THIS CONSTANT IS THE ANSWER TO "A HONEST CONE IS A LOT OF SCREEN". The melee
## swing publishes a 66-90 degree wedge three times a second; the frost cone and the
## uppercut publish one about once every two seconds. Drawn at the same weight, the
## melee wedge would be the loudest thing in a fight that the maker has separately
## called *"too much going on"*. So a cone has two weights and the caller picks:
##
##   FULL  — a growing wedge fill + rim + limit rays + apex core. For a deliberate,
##           telegraphed ability with a real lead (0.10 s here). 4 draw calls.
##   LIGHT — rim arc + the two limit rays, and NOTHING inside them. 2 draw calls,
##           at the alpha the FIST tell's old lane hint already used. The strike
##           figure (the fist / the crescent) stays the bright read and the wedge is
##           a boundary under it, which is the exact weight the thing deserves: a
##           0.077 s flick is not a 0.9 s bomb.
##
## The LIGHT cone is not a compromise on rule 2 — it claims EXACTLY the ground the
## damage query sweeps, to the degree. It is quieter, not smaller.
const CONE_LIGHT_ALPHA: float = 0.10
const CONE_LIGHT_ALPHA_ARMED: float = 0.26

## Geometry, depended on by the archetype tests. CIRCLE = a zone/point sigil;
## LINE = a charge lane; CONE = a wedge swept from an apex.
## ⚠ APPEND ONLY, for the same reason `Style` is — `Shape` is stored as an int the
## moment anything serialises or forwards it.
enum Shape { CIRCLE, LINE, CONE }
## Visual flavour, chosen per archetype. ZONE = ground danger ring (brute + the
## default for the plain tests); the rest are the distinct sigils.
## ⚠ APPEND ONLY — callers set these by name but `Enemy._emit_telegraph` passes them
## through a Dictionary as ints, so reordering would silently repaint every archetype.
## FIST / CRESCENT are the HERO's melee strikes: not a place on the floor, a thing
## coming out of the hand. See `Hero._publish_swing_tell`.
## CONE = a wedge swept out of a body: "this arc, from where I am standing". It is
## the style the file was MISSING, and its absence was the largest lie left in the
## tell layer — see `_draw_cone`.
enum Style { ZONE, MUZZLE, LANE, DART, GATHER, BOMB, FIST, CRESCENT, CONE }

## What each style PROMISES, as machine-readable text, so the audit probe and any
## future suite can state the rule rather than re-deriving it from the drawings.
## "ground" = a place you must not be standing. "corridor" = a line you must be off.
## "blow" = a strike arriving out of a hand, dodged laterally.
const STYLE_CONSEQUENCE: Dictionary = {
	Style.ZONE: "ground", Style.MUZZLE: "corridor", Style.LANE: "corridor",
	Style.DART: "ground", Style.GATHER: "ground", Style.BOMB: "ground",
	Style.FIST: "blow", Style.CRESCENT: "blow",
	# "wedge" = an arc of ground swept from a body. Distinct from "ground" (a place
	# you must not be standing, which you leave in any direction) and from "corridor"
	# (a line you step off): the answer to a wedge is to get BEHIND it or OUT of it,
	# and those are different dodges, so it needs its own word.
	Style.CONE: "wedge",
}

var _radius: float = 0.0
var _windup: float = 0.0
var _elapsed: float = 0.0
var _running: bool = false
var _has_fired: bool = false
var _shape: Shape = Shape.CIRCLE
var _length: float = 0.0
var _width: float = 0.0
var _angle: float = 0.0
## Half-opening of a CONE tell, in RADIANS, measured off `_angle`. Stored as an
## angle rather than as a dot product on purpose: `acos` is done ONCE at the call
## site, from the very `min_dot` the damage query uses, so the drawn wedge and the
## queried wedge cannot be two independently-typed numbers. That is the whole point
## of the style existing.
var _half_angle: float = 0.0
## Draw the cone as a boundary only (see `CONE_LIGHT_ALPHA`). Set by the melee tell.
var _cone_light: bool = false
## `graphics_quality = LOW` snapshot, taken once at `_ready` (the same moment
## SpawnTell / DeathSmudge / GraveTide take theirs) rather than per `_draw`: a tell
## lives well under a second and the setting cannot change inside one.
## ⚠ DECLARED, so a headless suite can `t.set("_low", true)` and get the cheap
## picture without a Tuning autoload — the SpawnTell idiom, and the reason the LOW
## contract is testable at all.
var _low: bool = false

## Set by the caster before start(): the enemy this tell emanates from (drawn as
## a tether), the accent colour, the aim direction + reach for muzzle/dart lines.
var source: Node2D = null
var accent: Color = RING_COLOR
var style: Style = Style.ZONE
var aim_dir: Vector2 = Vector2.RIGHT
var reach: float = 120.0

## Keep the tell's APEX on its `source` for as long as it lives.
##
## ⚠ OFF BY DEFAULT, AND IT MUST STAY OFF FOR THE ENEMY TELLS. `_emit_telegraph` /
## `_emit_hero_telegraph` deliberately parent a tell to the ARENA, not to the caster,
## so a placed ground danger (a brute's snapshot spot, a bomber's fuse) stays where
## it was planted even if the caster is knocked across the room. That is correct for
## everything whose danger is a PLACE.
##
## A melee cone's danger is not a place — it is an arc measured from the swinger's
## own body at the frame the swing lands. `Hero._on_melee_hit_frame` apexes at
## `global_position` AT THAT MOMENT, so a tell nailed to the ground where the swing
## STARTED is wrong by however far the body travelled during the wind-up. Measured:
## the Juggernaut's heavy swing sets `velocity.x = ±190` and tells for 0.077 s, so
## the apex drifts 14.6 px — a quarter of the swing's own reach — and every degree
## of the drawn wedge is displaced with it. Following the source closes that to zero.
var follow_source: bool = false

## Every live telegraph joins this group so a dodging brain can find the set of
## things currently threatening it in one scan. See the perception block below.
const GROUP: StringName = &"telegraph"


func _ready() -> void:
	add_to_group(GROUP)
	_low = TuningConfig.quality_is_low()


func start(radius: float, windup: float) -> void:
	_radius = radius
	_windup = maxf(windup, 0.001)
	_elapsed = 0.0
	_running = true
	_has_fired = false
	queue_redraw()


## Line telegraph: a charge lane from the origin along `angle`. Reuses ALL of
## start()'s timing / advance() / fired logic — only _draw branches on the shape.
func start_line(length: float, width: float, angle: float, windup: float) -> void:
	_shape = Shape.LINE
	_length = length
	_width = width
	_angle = angle
	if style == Style.ZONE:
		style = Style.LANE
	start(maxf(width, 1.0), windup)


## Cone telegraph: a wedge with its APEX on this node, opening `half_angle` radians
## either side of `angle` and reaching `reach_px`.
##
## ⚠ THE ARGUMENTS ARE THE DAMAGE QUERY'S OWN ARGUMENTS, AND THAT IS THE POINT.
## `SpellTargets.in_cone(origin, dir, reach, min_dot, ...)` is what every wide melee
## attack in the game sweeps with; a caller passes `reach` straight through and
## `acos(min_dot)` as `half_angle`. There is no second set of numbers to keep in
## step, which is how the lane-vs-cone drift this style exists to kill got in.
##
## `width_px` sizes the STRIKE FIGURE only (the fist's glove, the crescent's belly)
## for FIST / CRESCENT styles; it has no bearing on the danger footprint.
## `light` picks the boundary-only weight — see `CONE_LIGHT_ALPHA`.
func start_cone(reach_px: float, half_angle: float, angle: float, windup: float,
		width_px: float = 0.0, light: bool = false) -> void:
	_shape = Shape.CONE
	_angle = angle
	# Clamped to a real wedge. 0 would be a ray with no area (nothing to dodge off)
	# and > PI would wrap past itself and double-count the ground behind.
	_half_angle = clampf(half_angle, 0.02, PI)
	_length = maxf(reach_px, 0.0)
	_width = maxf(width_px, 0.0)
	_cone_light = light
	aim_dir = Vector2.from_angle(angle)
	reach = _length
	if style == Style.ZONE:
		style = Style.CONE
	start(_length, windup)


func _process(delta: float) -> void:
	advance(delta)


## Deterministic time-step so headless tests can drive the bloom frame-free.
func advance(delta: float) -> void:
	if not _running:
		return
	# A cone that apexes on a body has to travel with the body — see `follow_source`.
	# In `advance` rather than in `_process` so the headless suites, which step tells
	# with `advance(0.02)` and never let a frame pass, measure the same apex the game
	# does.
	if follow_source and source != null and is_instance_valid(source):
		global_position = source.global_position
	_elapsed += delta
	if not _has_fired and _elapsed >= _windup:
		_has_fired = true
		fired.emit()
	if _has_fired and _elapsed >= _windup + FADE_TIME:
		_running = false
		queue_free()
	queue_redraw()


# ---- perception ------------------------------------------------------------
# A telegraph IS the game's promise that something is about to happen at a place.
# Every field describing that promise was private and the node joined no group, so
# an AI could not see the one thing it is supposed to dodge. These expose the
# danger as world-space geometry plus a countdown — nothing a human player cannot
# already read off the screen, which keeps a dodging bot fair by construction
# rather than by convention.
#
# Unlike the spell spectacles (which park at the arena origin and draw in world
# coordinates), a Telegraph node sits AT the danger point and draws in local
# space, so global_position is genuinely meaningful here.

## World-space danger footprint. Circle: {shape, center, radius}.
## Line: {shape, from, to, width}.
## Cone: {shape:"circle", center, radius} — the SMALLEST CIRCLE CONTAINING THE WEDGE
## — plus a `cone` sub-dictionary carrying the exact wedge.
##
## ⚠ A CONE REPORTS ITSELF AS A CIRCLE ON PURPOSE, AND THE REASON IS NOT LAZINESS.
## Six things read this dictionary and none of them are this file's to change:
## `BotDodge.contains` / `_escape_dir`, `BotController.perceive_threats`,
## `BotBrain`, `Enemy.gd:1129`, `tools/bot_sim.gd` and two suites. Every one of them
## branches on `shape == "circle"` or `"line"` and has no third case. Publishing a
## `"cone"` string would make each of them fall through to "not a threat" — i.e. the
## day melee got an honest DRAWING would be the day every bot in the game stopped
## dodging melee, silently, with all suites green.
##
## So the perception contract is widened CONSERVATIVELY (the enclosing circle warns
## about slightly more ground than the wedge sweeps — over-warning, which costs a
## dodge nobody needed rather than health somebody was promised) and the exact wedge
## is attached alongside for whoever wants it next. `_draw` uses the exact wedge; it
## is only the machine-readable summary that rounds outward.
##
## ⚠ FOR A CONSUMER TO PICK THIS UP LATER, in a file this agent does not own:
## `shape["cone"]` is `{apex: Vector2, dir: Vector2, half_angle: float, radius: float}`
## in world space, and the containment test is
## `to.length() <= radius and dir.dot(to.normalized()) >= cos(half_angle)`.
func danger_shape() -> Dictionary:
	if _shape == Shape.CONE:
		var dirv: Vector2 = Vector2.from_angle(_angle)
		var bound: Vector2 = cone_bound(_length, _half_angle)
		return {
			"shape": "circle",
			"center": global_position + dirv * bound.x,
			"radius": bound.y,
			"cone": {
				"apex": global_position, "dir": dirv,
				"half_angle": _half_angle, "radius": _length,
			},
		}
	if _shape == Shape.LINE:
		return {
			"shape": "line",
			"from": global_position,
			"to": global_position + Vector2.from_angle(_angle) * _length,
			"width": _width,
		}
	return {"shape": "circle", "center": global_position, "radius": _radius}


## Seconds until this fires. <= 0.0 means it has already gone off.
func time_to_impact() -> float:
	return _windup - _elapsed


## The TOTAL warning this tell ever gave, as opposed to what is left of it.
##
## A dodging brain needs both. `time_to_impact` answers "how long have I got"; this
## answers "how much was I ever going to get", which is what a guard band has to be
## measured against — see `BotBrain._caps`. A hero melee swing tells for 0.077 s, and a
## class whose preferred guard lead is 0.37 s can never satisfy a band it cannot reach,
## on any frame, however well it reacts.
func windup() -> float:
	return _windup


## Still worth dodging: running and not yet fired.
func is_armed() -> bool:
	return _running and not _has_fired


# ------------------------------------------------------------- WORK COUNTERS
## Deterministic draw-work counters, in `MagicCircle`'s idiom and for the reason
## its own block states at length: **wall-clock cannot measure this headlessly.**
## A frame absorbs extra work into idle time until it crosses the pacing budget,
## at which point the whole cost appears at once — so a millisecond figure here is
## a coin toss and a primitive count is a fact.
##
##   `calls`    draw_* commands issued. THE PRIMARY NUMBER. Every batching change
##              in this file moves this and nothing else, which is what makes a
##              before/after mean "same picture, fewer commands".
##   `segments` line/arc/polyline segments rasterised. Moves when the sagitta rule
##              or the LOW gate thins geometry.
##   `tells`    `_draw` bodies that ran, so everything is readable per-tell.
##   `reach`    the furthest px from the tell's own origin that any primitive
##              reached. THIS IS THE HONESTY NUMBER, not a cost one: rule 2 says a
##              tell may not claim more ground than `danger_shape()` reports, and
##              this is the only way to check the claim without a renderer.
static var _work_calls: int = 0
static var _work_segments: int = 0
static var _work_tells: int = 0
static var _work_reach: float = 0.0


static func work_stats() -> Dictionary:
	return {
		"calls": _work_calls, "segments": _work_segments,
		"tells": _work_tells, "reach": _work_reach,
	}


## Test hook.
static func reset_work() -> void:
	_work_calls = 0
	_work_segments = 0
	_work_tells = 0
	_work_reach = 0.0


## Record one issued draw command covering `segs` segments and reaching `r` px from
## this tell's origin. Inlined at every draw site rather than wrapping the draw
## calls themselves: a wrapper would have to take a colour, a width and an
## antialias flag for eight different primitive shapes, and the wrapper would then
## be the thing that has to be kept honest.
func _bump(segs: int, r: float) -> void:
	_work_calls += 1
	_work_segments += segs
	if r > _work_reach:
		_work_reach = r


# --------------------------------------------------------------- THE LOW PLAN
# Pure statics, deliberately — `SpawnTell.stroke_plan`'s argument exactly. A LOW
# contract asserted through a renderer is a screenshot diff; asserted through a
# pure function it is arithmetic, and `tools/slice_test_tell_budget.gd` runs it
# with no tree, no window and no Tuning autoload.

## Segments for a ring of radius `r`, capped at the artistic `full`. Delegates to
## `MagicCircle.seg_of` rather than re-deriving the sagitta rule, so the two layers
## that draw circles in this game cannot drift apart on what "round enough" means.
## `count_work: false` — MagicCircle's counters must keep meaning MagicCircle.
static func seg_for(full: int, r: float, low: bool) -> int:
	return MagicCircle.seg_of(full, r, low, false)


## Runic ticks around a ring. Thins at LOW, never empties (see TICKS_MIN).
static func ticks_for(full: int, low: bool) -> int:
	if not low:
		return full
	return maxi(int(float(full) * TICKS_LOW_FACTOR), TICKS_MIN)


static func ghosts_for(low: bool) -> int:
	return CRESCENT_GHOSTS_LOW if low else CRESCENT_GHOSTS


static func crescent_steps(low: bool) -> int:
	return CRESCENT_STEPS_LOW if low else CRESCENT_STEPS


static func tether_pulses(low: bool) -> int:
	return TETHER_PULSES_LOW if low else TETHER_PULSES


static func chevron_spacing(low: bool) -> float:
	return CHEVRON_SPACING_LOW if low else CHEVRON_SPACING


## Segments along a cone's rim arc.
##
## A cone is a ring with a bite out of it, so it gets the RING's sagitta budget for
## its radius (`seg_for`) scaled by the fraction of a full turn it actually covers.
## Deriving it that way rather than picking a number means a 66-degree melee wedge
## and a 203-degree uppercut wedge are tessellated to the same smoothness per unit of
## rim, and both get cheaper on a phone through the one rule the rest of the file
## already uses.
static func cone_steps(full: int, r: float, half_angle: float, low: bool) -> int:
	var frac: float = clampf(half_angle / PI, 0.0, 1.0)
	return maxi(int(ceil(float(seg_for(full, r, low)) * frac)), CONE_ARC_MIN)


## The SMALLEST CIRCLE CONTAINING a wedge with its apex at the origin, reaching
## `reach` px, opening `half_angle` either side of the axis. Returned as
## `(offset along the axis, radius)`.
##
## ⚠ THIS DERIVATION MOVED HERE FROM `Hero._cone_tell_circle`, WHICH IS DELETED.
## It was written there as a stop-gap while `Telegraph` had no CONE style — a circle
## standing in for a cone, sized so it could never UNDER-draw. Two of Hero's wide
## attacks used it and both now draw real wedges, so the only surviving consumer is
## `danger_shape()`, which needs it for the perception summary. Keeping one copy, in
## the file that publishes the number, is the point: two copies is how the lane and
## the cone drifted apart in the first place.
##
## Three cases, and each one is a different point being the binding one:
##   a <= 45 deg   the APEX is the far point, so the circle is the circumcircle of
##                 the apex and the two arc ends:   c = r = reach / (2 cos a)
##   45 < a <= 90  the two arc ENDS are the far pair and their chord is the
##                 diameter:                        c = reach cos a, r = reach sin a
##   a > 90 deg    the arc wraps behind the apex and the axis TIP becomes binding, so
##                 the honest answer is apex-centred: c = 0, r = reach
static func cone_bound(reach_px: float, half_angle: float) -> Vector2:
	var a: float = clampf(half_angle, 0.0, PI)
	if a > PI * 0.5:
		return Vector2(0.0, maxf(reach_px, 0.0))
	if a > PI * 0.25:
		return Vector2(reach_px * cos(a), reach_px * sin(a))
	var c: float = reach_px / maxf(2.0 * cos(a), 0.0001)
	return Vector2(c, c)


## Does the fist tell draw its knuckle flare?
##
## ⚠ THIS IS THE ONE PLACE A FIGURE IS DROPPED RATHER THAN THINNED, and it needs
## the argument. FIST is the highest-frequency tell in the game — every melee swing
## by every class publishes one — and it was the only style with NOTHING to shed:
## four flat primitives and a two-segment flare, no arcs to tessellate and no
## ghosts to trail, so it ignored `graphics_quality` entirely. (The budget suite
## found that; it was not noticed by reading.)
##
## The flare is two 1.4 px strokes off the leading edge of a glove whose radius is
## `max(width/2, 3)` — 5.2 px for the stock 58 px swing. On the phone that is a
## sub-pixel ornament on a five-pixel object, which is the same "below the visible
## threshold on the target device" argument `MagicCircle.MAX_SAGITTA_PX` already
## makes for tessellation. What survives at LOW is the whole message: the travel
## hint (where this goes), the motion streak (it is thrown), the element-tinted
## glove and its hot centre. The blow still reads; the stitching on it does not.
static func fist_knuckles(low: bool) -> bool:
	return not low


# ------------------------------------------------------------ THE COLOUR RULE
# Rule 1 (colour carries element) made assertable. These three were WRITTEN OUT
# INLINE as literal oranges and reds — `Color(1.0, lerpf(0.5, 0.14, t), ...)` in
# the zone, `Color(1.0, 0.5, 0.15, 0.85)` on the bomb's countdown,
# `Color(1.0, 0.5, 0.2, ...)` on the lane's payoff — over rings that were already
# accent-coloured. A green summoner and a violet mage drew the same orange middle.
#
# Pulled out as pure functions for the same reason `SpawnTell.stroke_plan` is one:
# a colour contract checked through a renderer is a screenshot diff, and checked
# through a function it is arithmetic. `slice_test_tell_budget` asserts that each
# one tracks its accent's hue rather than overwriting it.
#
# The SHAPE of each ramp is preserved exactly — washed-out and wide early, hot and
# saturated late — because that ramp is the charge read and the charge read is the
# dodge window. Only the hue it is built from changed.

## The zone's charge fill at `t` (0 = tell just started, 1 = about to land).
static func zone_fill(accent_col: Color, t: float) -> Color:
	var c: Color = accent_col.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.55 * (1.0 - t))
	c.a = lerpf(0.16, 0.5, t)
	return c


## The bomb's inner fill. Same ramp, shallower whitening: a fuse is meant to look
## hot from the start, where a zone begins as a cold outline.
static func bomb_fill(accent_col: Color, t: float) -> Color:
	var c: Color = accent_col.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.4 * (1.0 - t))
	c.a = 0.2 + 0.4 * t
	return c


## The fuse's countdown sweep — the hottest LINE in the bomb figure, so it is the
## accent pushed toward white rather than a second hue.
static func bomb_countdown(accent_col: Color) -> Color:
	return accent_col.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.35)


## The charge lane's payoff flash.
static func lane_flash(accent_col: Color, fade: float) -> Color:
	var c: Color = accent_col.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.3)
	c.a = 0.4 * fade
	return c


func _draw() -> void:
	if _radius <= 0.0:
		return
	_work_tells += 1
	if _shape == Shape.CONE:
		var ct: float = clampf(_elapsed / _windup, 0.0, 1.0)
		var cfade: float = 1.0
		if _has_fired:
			ct = 1.0
			cfade = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		# ⚠ THE BOUNDARY IS DRAWN FIRST, UNDER THE STRIKE FIGURE, NOT INSTEAD OF IT.
		# FIST / CRESCENT keep the picture the maker asked for by name — *"a little
		# fire fist ... in the direction being punched"* — and what changes is only
		# the faint hint UNDER it: it used to be a 10.4 px lane, which claimed a
		# tenth of the ground the swing actually swept, and it is now the swing's
		# own wedge. Same weight, same call count budget, no new effect.
		_draw_cone(ct, cfade)
		if style == Style.FIST:
			_draw_fist()
		elif style == Style.CRESCENT:
			_draw_crescent()
		return
	if _shape == Shape.LINE:
		# The hero's melee strikes are lanes too, but they are drawn as the STRIKE
		# rather than as a runic charge corridor — a punch is not a charger.
		if style == Style.FIST:
			_draw_fist()
		elif style == Style.CRESCENT:
			_draw_crescent()
		else:
			_draw_lane()
		return
	if _has_fired:
		_draw_fired_circle()
		return
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	match style:
		Style.MUZZLE:
			_draw_muzzle(t)
		Style.GATHER:
			_draw_gather(t)
		Style.BOMB:
			_draw_bomb(t)
		Style.DART:
			_draw_dart(t)
		_:
			_draw_zone(t)
	# Every off-body tell draws a tether back to its caster so the read is always
	# "that enemy is doing this," never a free-floating marker.
	if style == Style.ZONE or style == Style.DART:
		_draw_tether(t)


# ------------------------------------------------------------------ shared bits
## A bright animated link from the caster to this danger spot: a faint beam with a
## pulse of energy travelling along it toward the target.
##
## ⚠ THE TETHER IS EXEMPT FROM THE REACH RULE, and it is the one deliberate
## exemption in the file. It reaches all the way back to the caster, which is
## further than the danger footprint by design — it is a statement about WHO, not
## about WHERE the damage is. So it is counted as work but its distance is not fed
## into `_work_reach`; a tether that fed the honesty number would make every ZONE
## tell in the game look like it was lying about a caster standing 300 px away.
func _draw_tether(t: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	var from: Vector2 = to_local(source.global_position)
	var to: Vector2 = Vector2.ZERO
	if from.distance_to(to) < 4.0:
		return
	var c: Color = accent
	draw_line(from, to, Color(c.r, c.g, c.b, (0.12 + 0.22 * t)), 1.5)
	_bump(1, 0.0)
	# Energy pulses sliding toward the target end.
	var pulses: int = tether_pulses(_low)
	for i: int in pulses:
		var f: float = fposmod(_elapsed * 2.2 + (1.0 / float(pulses)) * float(i), 1.0)
		var p: Vector2 = from.lerp(to, f)
		draw_circle(p, 2.4, Color(c.r, c.g, c.b, (0.7 * t) * (1.0 - f * 0.4)))
		_bump(1, 0.0)


func _draw_fired_circle() -> void:
	# Accent-tinted muzzle/detonation flash (was a hard red disc — read as a stray
	# "red circle on the target"). A caster's flash is now its own hue.
	var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
	var c: Color = accent
	draw_circle(Vector2.ZERO, _radius, Color(c.r, c.g, c.b, 0.4 * fade))
	_bump(1, _radius)
	var seg: int = seg_for(48, _radius, _low)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, seg, Color(1.0, 1.0, 1.0, 0.7 * fade), 3.0)
	_bump(seg, _radius)


## Rotating runic ticks around a ring — the shared "arcane" flourish.
##
## ⚠ ONE `draw_multiline`, NOT `count` `draw_line`s. This is the same batching the
## repo has already measured elsewhere: sixteen dashes issued as one multiline cost
## ~24 µs where the same sixteen as separate calls cost ~298 µs — a 12x difference
## for an identical picture. BOMB draws sixteen of these every frame of a 0.9 s
## fuse, MUZZLE eight, GATHER ten, and a room can hold several at once.
func _draw_runic_ticks(r: float, count: int, spin: float, col: Color) -> void:
	if count <= 0:
		return
	var pts := PackedVector2Array()
	pts.resize(count * 2)
	for i: int in count:
		var th: float = spin + TAU * float(i) / float(count)
		var dirv: Vector2 = Vector2.from_angle(th)
		pts[i * 2] = dirv * r * 0.82
		pts[i * 2 + 1] = dirv * r
	draw_multiline(pts, col, 1.5)
	_bump(count, r)


# ----------------------------------------------------------------- ZONE (brute)
## The classic ground danger ring + inner charge fill (kept, so the default/test
## path is unchanged), now accent-tinted with the caster tether added on top.
##
## ⚠ THE FILL WAS HARD-CODED ORANGE-RED OVER AN ACCENT-COLOURED RING. Rule 1: a
## MAGE's violet zone, a SUMMONER's green zone and a BRUTE's red zone were three
## different rings around one identical orange middle, so the colour that carries
## "which of the seven bodies in this room is doing it" stopped at the outline. The
## ramp itself is unchanged in SHAPE — it still starts pale and wide and closes to
## saturated and hot — it is just built out of `accent` now. White stays white: the
## hot core is an intensity statement, not a hue one.
func _draw_zone(t: float) -> void:
	var danger: Color = accent
	var ring_seg: int = seg_for(48, _radius, _low)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, ring_seg,
		Color(danger.r, danger.g, danger.b, 0.85), 2.0)
	_bump(ring_seg, _radius)
	var pulse: float = 1.0 + 0.05 * sin(_elapsed * 26.0) * t
	var inner_r: float = minf(_radius * t * pulse, _radius)
	# Pale -> saturated as the charge fills: lerp the accent toward white by the
	# INVERSE of t, which reproduces the old fill's read (washed out early, hot and
	# solid late) in whatever hue the caster actually is.
	draw_circle(Vector2.ZERO, inner_r, zone_fill(danger, t))
	_bump(1, inner_r)
	if inner_r > 2.0:
		var in_seg: int = seg_for(40, inner_r, _low)
		draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, in_seg,
			Color(danger.r, danger.g, danger.b, 0.25 + 0.65 * t), 2.0)
		_bump(in_seg, inner_r)


# --------------------------------------------------------------- MUZZLE (caster)
## A small face-on sigil at the staff tip + a brightening aim-tracer along the
## shot line — "it's charging a bolt, aimed there."
##
## ⚠ THE TRACER IS WHY `MUZZLE`'S CONSEQUENCE IS "corridor" AND ITS `danger_shape`
## IS A CIRCLE, which is the one place in this file where the drawing and the
## perception contract genuinely disagree. The picture is right (the bolt goes
## THAT way, `reach` px of it) and the reported footprint is a small circle on the
## caster, so a dodging brain sidesteps the sigil rather than the shot. Not changed
## here: `danger_shape()` is answered by `BotDodge` / `BotBrain`, which are not this
## file's to retune, and a silent widening of every caster's perceived threat is a
## difficulty change wearing a legibility change's clothes. `probe_tell_audit`
## prints it as a finding with the exact edit.
func _draw_muzzle(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	var spin: float = _elapsed * 2.2
	# Aim tracer: a faint full line + a bright leading edge that grows over the tell.
	var dir: Vector2 = aim_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var end: Vector2 = dir * reach
	draw_line(Vector2.ZERO, end, Color(c.r, c.g, c.b, 0.12 + 0.2 * t), 1.5)
	_bump(1, reach)
	draw_line(Vector2.ZERO, dir * reach * (0.2 + 0.8 * t), Color(1.0, 1.0, 1.0, 0.25 + 0.45 * t), 1.5)
	_bump(1, reach)
	# Reticle at the aim end.
	var ret_r: float = 5.0 + 2.0 * sin(_elapsed * 8.0)
	var ret_seg: int = seg_for(16, ret_r, _low)
	draw_arc(end, ret_r, 0.0, TAU, ret_seg, Color(c.r, c.g, c.b, 0.5 + 0.4 * t), 1.5)
	_bump(ret_seg, reach + ret_r)
	# Face-on muzzle sigil: two counter-rotating rings + runic ticks + core.
	var outer_seg: int = seg_for(32, R, _low)
	draw_arc(Vector2.ZERO, R, 0.0, TAU, outer_seg, Color(c.r, c.g, c.b, 0.8), 2.0)
	_bump(outer_seg, R)
	_draw_runic_ticks(R * 0.92, ticks_for(8, _low), spin, Color(c.r, c.g, c.b, 0.5))
	var mid_seg: int = seg_for(24, R * 0.6, _low)
	draw_arc(Vector2.ZERO, R * 0.6, 0.0, TAU, mid_seg, Color(c.r, c.g, c.b, 0.4), 1.5)
	_bump(mid_seg, R * 0.6)
	var core: float = R * (0.18 + 0.22 * t)
	draw_circle(Vector2.ZERO, core, Color(c.r, c.g, c.b, 0.4))
	_bump(1, core)
	draw_circle(Vector2.ZERO, core * 0.5, Color(1.0, 1.0, 1.0, 0.5 + 0.4 * t))
	_bump(1, core * 0.5)


# -------------------------------------------------------------- GATHER (summoner)
## A face-on summoning circle — a growing vortex that pulls energy inward, runic
## ticks + an inscribed triangle-star, brightening core. "It's calling something."
func _draw_gather(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	# Rings pulled inward toward the centre (the "gathering" read).
	# Three different alphas, so these genuinely cannot be one command — the ring
	# COUNT is the animation. They are seg-scaled instead.
	for i: int in 3:
		var f: float = fposmod(-_elapsed * 0.6 + float(i) / 3.0, 1.0)
		var rr: float = R * (0.4 + f * 1.1)
		var seg: int = seg_for(40, rr, _low)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, seg, Color(c.r, c.g, c.b, (1.0 - f) * 0.3), 2.0)
		_bump(seg, rr)
	var spin: float = _elapsed * 1.6
	var rim_seg: int = seg_for(48, R, _low)
	draw_arc(Vector2.ZERO, R, 0.0, TAU, rim_seg, Color(c.r, c.g, c.b, 0.85), 2.5)
	_bump(rim_seg, R)
	_draw_runic_ticks(R * 0.9, ticks_for(10, _low), spin, Color(c.r, c.g, c.b, 0.5))
	# Two opposed triangles (a hexagram-ish summoning star), counter-spinning.
	# ⚠ ONE COMMAND, NOT TWO POLYLINES. Both triangles are the same colour and the
	# same width — they were only two calls because they were written as two calls.
	_draw_hexagram(R * 0.62, -spin * 0.8, Color(c.r, c.g, c.b, 0.7))
	var core: float = R * (0.14 + 0.26 * t)
	draw_circle(Vector2.ZERO, core, Color(c.r, c.g, c.b, 0.35))
	_bump(1, core)
	draw_circle(Vector2.ZERO, core * 0.5, Color(1.0, 1.0, 1.0, 0.4 + 0.5 * t))
	_bump(1, core * 0.5)


## Two opposed triangles as a single `draw_multiline` — six segments, one command.
## Replaces the old `_draw_star` called twice (two `draw_polyline`s, eight
## segments' worth of vertices between them and two commands). Same figure.
func _draw_hexagram(r: float, offset: float, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.resize(12)
	for tri: int in 2:
		var base: float = offset + PI * float(tri)
		for i: int in 3:
			var a: Vector2 = Vector2.from_angle(base - PI / 2.0 + TAU * float(i) / 3.0) * r
			var b: Vector2 = Vector2.from_angle(base - PI / 2.0 + TAU * float(i + 1) / 3.0) * r
			pts[tri * 6 + i * 2] = a
			pts[tri * 6 + i * 2 + 1] = b
	draw_multiline(pts, col, 2.0)
	_bump(6, r)


# ---------------------------------------------------------------- BOMB (bomber)
## A big pulsing rune ring centred on the bomber with a COUNTDOWN arc that fills
## as the fuse burns + an intensifying red core. "This thing is about to blow."
##
## ⚠ THE COUNTDOWN AND THE INNER FILL WERE HARD-CODED ORANGE-RED. Rule 1 again,
## and it matters more here than anywhere: BOMB is the biggest, slowest, most
## lethal tell in the roster, so it is the one the player has most time to read.
## Both now derive from `accent` (which for the stock bomber IS orange, so the
## stock body is unchanged on screen — what changes is that an elementally-tinted
## or modded bomber stops arguing with itself).
func _draw_bomb(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	# Outer danger boundary (what's about to hurt).
	var rim_seg: int = seg_for(56, R, _low)
	draw_arc(Vector2.ZERO, R, 0.0, TAU, rim_seg, Color(c.r, c.g, c.b, 0.8), 2.5)
	_bump(rim_seg, R)
	_draw_runic_ticks(R * 0.94, ticks_for(16, _low), _elapsed * 0.8, Color(c.r, c.g, c.b, 0.4))
	# Countdown: an arc that sweeps all the way round as the fuse burns out. Brightened
	# off the accent rather than painted orange, so it still reads as the hottest line
	# in the figure in any hue.
	var cd_r: float = R * 0.8
	var cd_seg: int = maxi(int(ceil(float(seg_for(48, cd_r, _low)) * t)), 1)
	draw_arc(Vector2.ZERO, cd_r, -PI / 2.0, -PI / 2.0 + TAU * t, cd_seg,
		bomb_countdown(c), 4.0)
	_bump(cd_seg, cd_r)
	# Inner fill reddening + a fast pulse as it nears zero.
	var pulse: float = 1.0 + 0.08 * sin(_elapsed * (10.0 + 30.0 * t))
	var inner_r: float = R * (0.15 + 0.5 * t) * pulse
	draw_circle(Vector2.ZERO, inner_r, bomb_fill(c, t))
	_bump(1, inner_r)
	draw_circle(Vector2.ZERO, R * 0.1 * pulse, Color(1.0, 0.95, 0.8, 0.5 + 0.5 * t))
	_bump(1, R * 0.1 * pulse)


# -------------------------------------------------------------- DART (assassin)
## A crosshair reticle at the marked strike point + the tether does the rest
## (drawn by the caller) — "the silver one is about to dart HERE, from over there."
func _draw_dart(t: float) -> void:
	var c: Color = accent
	var R: float = _radius
	var spin: float = _elapsed * 4.0
	var arc_seg: int = maxi(int(float(seg_for(24, R, _low)) * 0.9), 1)
	draw_arc(Vector2.ZERO, R, spin, spin + TAU * 0.9, arc_seg, Color(c.r, c.g, c.b, 0.6 + 0.3 * t), 2.0)
	_bump(arc_seg, R)
	# Snapping crosshair ticks that close in as the (fast) tell fills.
	# ⚠ ONE COMMAND. Four identically-coloured, identically-wide lines were four
	# calls; the DART is the FASTEST tell in the roster (0.35 s) so it is also the
	# one most likely to be on screen several times at once during a pack fight.
	var gap: float = R * (1.4 - 0.5 * t)
	var ticks := PackedVector2Array()
	ticks.resize(8)
	for i: int in 4:
		var dirv: Vector2 = Vector2.from_angle(float(i) * PI * 0.5 + spin)
		ticks[i * 2] = dirv * gap
		ticks[i * 2 + 1] = dirv * (gap + R * 0.5)
	draw_multiline(ticks, Color(c.r, c.g, c.b, 0.5 + 0.4 * t), 2.0)
	_bump(4, gap + R * 0.5)
	draw_circle(Vector2.ZERO, R * 0.12, Color(1.0, 1.0, 1.0, 0.4 + 0.5 * t))
	_bump(1, R * 0.12)


# --------------------------------------------------------------- LANE (charger)
## A runic charge lane that ORIGINATES at the charger and fills with chevrons of
## energy rushing toward the target end, capped by an arrowhead — replaces the
## old flat red rectangle "line I don't know what it does."
func _draw_lane() -> void:
	var c: Color = accent
	if _has_fired:
		var fade: float = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
		# ⚠ WAS A HARD-CODED ORANGE FLASH over an accent-coloured lane, so every
		# charger in the game — whatever hue it wound up in — paid off in the same
		# colour. Rule 1: the flash is the same statement as the lane, louder.
		draw_rect(Rect2(0.0, -_width * 0.5, _length, _width), lane_flash(c, fade), true)
		_bump(1, _length)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	var hw: float = _width * 0.5
	# Faint full-lane boundary (where it WILL reach), then a filling body.
	draw_rect(Rect2(0.0, -hw, _length, _width), Color(c.r, c.g, c.b, 0.1 + 0.12 * t), false)
	_bump(4, _length)
	var grow: float = _length * (0.15 + 0.85 * t)
	draw_rect(Rect2(0.0, -hw, grow, _width), Color(c.r, c.g, c.b, 0.14 + 0.28 * t), true)
	_bump(1, grow)
	# Chevrons of energy rushing down the lane toward the target.
	# ⚠ ONE `draw_multiline` FOR THE WHOLE RUSH. A 300 px lane at 26 px spacing is
	# up to twelve chevrons, and every one of them was its own `draw_polyline` — the
	# exact shape of the batching win already measured in this repo. Identical
	# picture: a chevron is two segments, and a multiline is a list of segments.
	var spacing: float = chevron_spacing(_low)
	var scroll: float = fposmod(_elapsed * 160.0, spacing)
	var chevrons := PackedVector2Array()
	var x: float = scroll
	while x < grow:
		chevrons.append(Vector2(x - 8.0, -hw * 0.7))
		chevrons.append(Vector2(x, 0.0))
		chevrons.append(Vector2(x, 0.0))
		chevrons.append(Vector2(x - 8.0, hw * 0.7))
		x += spacing
	if not chevrons.is_empty():
		draw_multiline(chevrons, Color(1.0, 1.0, 1.0, 0.3 + 0.4 * t), 2.0)
		_bump(chevrons.size() / 2, grow)
	# Bright core line + an arrowhead at the leading edge.
	draw_line(Vector2.ZERO, Vector2(grow, 0.0), Color(1.0, 1.0, 1.0, 0.35 + 0.4 * t), 2.0)
	_bump(1, grow)
	draw_colored_polygon(PackedVector2Array([
		Vector2(grow + 10.0, 0.0), Vector2(grow - 4.0, -hw), Vector2(grow - 4.0, hw),
	]), Color(c.r, c.g, c.b, 0.6 + 0.35 * t))
	_bump(3, grow + 10.0)
	# Origin burst sigil at the charger.
	var burst_seg: int = seg_for(20, hw * 1.1, _low)
	draw_arc(Vector2.ZERO, hw * 1.1, 0.0, TAU, burst_seg, Color(c.r, c.g, c.b, 0.6 + 0.3 * t), 2.0)
	_bump(burst_seg, hw * 1.1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------- CONE (a wedge)
## THE ARC THIS ATTACK ACTUALLY SWEEPS, DRAWN AS THE ARC IT ACTUALLY SWEEPS.
##
## ══ WHY THIS STYLE EXISTS ═══════════════════════════════════════════════════
## Three of the game's attacks query `SpellTargets.in_cone` and none of them could
## draw one, so all three drew something else and all three were measured lying:
##
##   melee swing    cone r58, half-angle 66-90 deg   drawn as a 10.4 px LANE
##   uppercut       cone r70, half-angle 101.5 deg   drawn as a circle r42 at +24
##   frost cone     cone r118, half-angle 60 deg     drawn as a circle r59 at +59
##
## The melee row is the worst of them and the most important: the drawn lane is
## 10.2-11.1x narrower than the cone that damages, and since melee auto-target was
## deleted the cone IS the whole swing. Both obvious repairs were rejected before
## this one was written: a cone-sized LANE is wider than the swing is long and the
## maker vetoed that look directly (*"i hate that circle thing for brawler"*), and a
## lane-sized CONE is a needle that would gut melee. The remaining option was to
## teach this file the shape, which is what this is.
##
## ══ WHAT IS DRAWN ═══════════════════════════════════════════════════════════
## Rule 2 (shape carries consequence): a wedge says "this arc, from my body". So the
## figure is the wedge's own outline — the rim arc at full reach, closed back to the
## apex down the two limit rays — and nothing that reaches past it. `_bump`'s reach
## is fed the rim, so the honesty number equals `danger_shape()`'s radius by
## construction rather than by inspection.
##
## Rule 1 (colour carries element): every stroke is `accent`. The apex core is white,
## which is the file's standing intensity-not-hue exception.
##
## ⚠ AND THE FILL IS A SINGLE POLYGON THAT GROWS, NOT A STACK OF ARCS. `_draw_zone`
## already established the charge read — pale and wide early, saturated and hot late
## — and it costs one `draw_colored_polygon` here because a wedge is a triangle fan
## the rasteriser can take in one command. A cone drawn as N arcs at N radii would be
## the same picture at N times the price, on a style that fires three times a second.
func _draw_cone(t: float, fade: float) -> void:
	# ⚠ A LIGHT CONE DRAWS NOTHING AT ALL, and this return sits FIRST on purpose.
	#
	# It used to sit four lines down, after the rim arc and the two limit rays, so a
	# "light" cone still drew its boundary. Measured, that boundary is what the maker was
	# objecting to twice over: on the Swordsaint it is an 86 px, 174-degree arc in ARCANE
	# MAGENTA wrapped around the body — *"that goofy large pink barrier thing in its left
	# click attack"* — and on the Brawler the same object at 58 px is the little pale bar
	# they read as a deflect. One shape, both complaints, on an OFFENSIVE verb where a
	# shell around the body says "defending" to anyone who has played anything.
	#
	# `_cone_light` is set in exactly one place in the whole codebase — the swing tell —
	# so this cut reaches basic attacks and nothing else BY CONSTRUCTION. The Cryomancer's
	# frost cone and the uppercut are full cones and keep their drawing.
	#
	# ⚠ THE TELL ITSELF IS NOT DELETED, only its picture. `BotController.perceive_threats`
	# finds melee by walking the `telegraph` group; removing the node would make every
	# heavy swing invisible to every bot, silently, with all suites green. The strike
	# figure drawn on top — the fist, the crescent — is now the whole read.
	if _cone_light:
		return
	var c: Color = accent
	var dirv: Vector2 = Vector2.from_angle(_angle)
	var steps: int = cone_steps(CONE_ARC_SEGMENTS, _radius, _half_angle, _low)
	# The two limit rays, as ONE command. They are the same colour and the same width
	# and were only ever going to be two calls because they are two lines — the same
	# batching argument `_draw_runic_ticks` and the DART's crosshair already make.
	var a0: float = _angle - _half_angle
	var a1: float = _angle + _half_angle
	var edge_a: float = CONE_LIGHT_ALPHA + (CONE_LIGHT_ALPHA_ARMED - CONE_LIGHT_ALPHA) * t
	var rays := PackedVector2Array()
	rays.resize(4)
	rays[0] = Vector2.ZERO
	rays[1] = Vector2.from_angle(a0) * _radius
	rays[2] = Vector2.ZERO
	rays[3] = Vector2.from_angle(a1) * _radius
	draw_multiline(rays, Color(c.r, c.g, c.b, edge_a * 2.0 * fade), 1.5)
	_bump(2, _radius)
	# The rim: where the swing stops. This is the single most useful line in the
	# figure, because "am I inside the arc" is answered by which side of it you are on.
	draw_arc(Vector2.ZERO, _radius, a0, a1, steps,
		Color(c.r, c.g, c.b, (edge_a * 3.0) * fade), 2.0)
	_bump(steps, _radius)
	# The charge fill, as one growing wedge. `zone_fill` is reused rather than
	# re-derived so a cone and a ground zone at the same charge are the same colour —
	# they are the same statement about time, differing only in shape.
	var fill_r: float = _radius * (0.12 + 0.88 * t)
	var fan := PackedVector2Array()
	fan.resize(steps + 2)
	fan[0] = Vector2.ZERO
	for i: int in steps + 1:
		fan[i + 1] = Vector2.from_angle(a0 + (a1 - a0) * float(i) / float(steps)) * fill_r
	var fc: Color = zone_fill(c, t)
	fc.a *= fade
	draw_colored_polygon(fan, fc)
	_bump(steps + 2, fill_r)
	# The apex: a hot point that says WHERE the wedge is hinged. Small deliberately —
	# a wedge's danger is its area, and a bright apex would pull the eye to the one
	# spot inside it that is always safe to be standing on (your own body).
	draw_circle(Vector2.ZERO, maxf(_radius * 0.06, 2.0),
		Color(1.0, 1.0, 1.0, (0.3 + 0.5 * t) * fade))
	_bump(1, maxf(_radius * 0.06, 2.0))


# ------------------------------------------------------- FIST / CRESCENT (hero melee)
## A SMALL GLOVE-SIZED FIST THAT TRAVELS OUT ALONG THE PUNCH.
##
## Maker: *"just show like a little fire fist or something coming out when I punch,
## small, the size of the glove, in the direction being punched, that can be dodged"*.
##
## It is drawn at where the strike HAS REACHED, not across the whole lane, so the
## thing on screen is the blow arriving rather than a corridor being reserved. The
## faint line behind it is the only "where this goes" hint, and it is deliberately
## thin — the fist is the read.
func _draw_fist() -> void:
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	var dir: Vector2 = Vector2.from_angle(_angle)
	var fade: float = 1.0
	if _has_fired:
		fade = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		t = 1.0
	var c: Color = accent
	var reach_now: float = _length * (0.12 + 0.88 * t)
	var at: Vector2 = dir * reach_now
	var rr: float = maxf(_width * 0.5, 3.0)
	# The travel hint: where it is going, at a weight that cannot be mistaken for
	# the strike itself.
	# ⚠ SUPPRESSED ON A CONE, AND THIS IS THE SWAP THAT MAKES THE MELEE TELL HONEST.
	# This line WAS the lane claim — a 58 px thread down the aim, against a swing that
	# damages 66-90 degrees either side of it. `_draw_cone` has already drawn the real
	# wedge underneath at the same weight, so drawing this too would be a second,
	# narrower claim inside the true one. Net call count for the melee tell: -1 here,
	# +2 there.
	if _shape != Shape.CONE:
		draw_line(Vector2.ZERO, dir * _length, Color(c.r, c.g, c.b, 0.10 * fade), 1.0, true)
		_bump(1, _length)
	# A short motion streak BEHIND the fist — this is what makes it read as thrown
	# rather than as a dot sliding along a line.
	draw_line(at - dir * rr * 2.2, at, Color(c.r, c.g, c.b, 0.35 * fade), rr * 0.9, true)
	_bump(1, reach_now)
	# THE GLOVE. Element-tinted core with a hot centre, so a fire fist is a fire fist
	# and an ice one is not the same picture in a different hue.
	draw_circle(at, rr * fade, Color(c.r, c.g, c.b, 0.85 * fade))
	_bump(1, reach_now + rr)
	draw_circle(at, rr * 0.55 * fade, Color(1.0, 1.0, 1.0, 0.7 * fade))
	_bump(1, reach_now + rr * 0.55)
	# Knuckle flare on the leading edge. One command: same colour, same width, and a
	# fist tell fires on every single melee swing in the game — the highest-frequency
	# tell there is, so its two-call version was the most-repeated waste in the file.
	# Dropped entirely on the phone; see `fist_knuckles` for why this one is a drop
	# rather than a thinning.
	if not fist_knuckles(_low):
		return
	var perp: Vector2 = dir.orthogonal()
	var flare := PackedVector2Array()
	flare.resize(4)
	for i: int in 2:
		var sgn: float = -1.0 if i == 0 else 1.0
		flare[i * 2] = at + perp * rr * 0.55 * sgn
		flare[i * 2 + 1] = at + dir * rr * 0.9 + perp * rr * 0.3 * sgn
	draw_multiline(flare, Color(c.r, c.g, c.b, 0.6 * fade), 1.4)
	_bump(2, reach_now + rr * 0.9)


## A THIN CURVE OF AIR OFF A BLADE — the same idea as the fist, cut differently.
## Sweeps out along the lane as an arc whose belly leads, so it reads as a slash
## leaving the sword rather than as a projectile.
func _draw_crescent() -> void:
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	var dir: Vector2 = Vector2.from_angle(_angle)
	var fade: float = 1.0
	if _has_fired:
		fade = clampf(1.0 - (_elapsed - _windup) / FADE_TIME, 0.0, 1.0)
		t = 1.0
	var c: Color = accent
	var perp: Vector2 = dir.orthogonal()
	var reach_now: float = _length * (0.10 + 0.90 * t)
	# ⚠ 0.9 -> 1.5 ON THE SPAN. Maker: *"the sword curve ... is good make it look more
	# epic"*. The curve was the right IDEA at the wrong size — a 15 px arc on an 86 px
	# lane, i.e. a scratch. A cut should be wider than the thing that made it.
	var half: float = maxf(_width * 1.5, 11.0) * (0.45 + 0.55 * t)
	# Suppressed on a cone for the reason spelled out in `_draw_fist`: the wedge under
	# this figure is already the honest claim, and this thread would be a narrower one
	# drawn inside it.
	if _shape != Shape.CONE:
		draw_line(Vector2.ZERO, dir * _length, Color(c.r, c.g, c.b, 0.10 * fade), 1.0, true)
		_bump(1, _length)
	# ══ THE CUT IS A TAPERED BLADE OF AIR, NOT A LINE ═════════════════════════
	# It was two constant-width `draw_polyline`s, and a constant-width band reads as a
	# ribbon — the comment above them already said the taper was the point, and there
	# was no taper. Now it is a real polygon: fat through the belly, closing to nothing
	# at both tips, which is the shape of a slash.
	#
	# Three ghosts trail behind it at decreasing reach and alpha, so the eye sees the
	# edge SWEEP rather than appear. That is the whole of what "more epic" buys here —
	# no new colours, no full-screen anything, and it costs four polygons.
	#
	# ⚠ AND FOUR POLYGONS IS WHY THIS IS THE MOST EXPENSIVE TELL IN THE GAME. At HIGH
	# it is 4 x (45-vertex polygon + 22-segment polyline) plus a white core, and it
	# fires on EVERY blade swing. `CRESCENT_GHOSTS_LOW` cuts the ghost count and
	# `CRESCENT_STEPS_LOW` halves the tessellation on the phone; the leading blade,
	# the taper, the white edge and one trail all survive, so the picture still says
	# "an edge moved through here".
	var steps: int = crescent_steps(_low)
	var ghost_count: int = ghosts_for(_low)
	for ghost: int in ghost_count + 1:
		var back: float = float(ghost) * CRESCENT_GHOST_STEP
		var lead: float = reach_now - half * back
		if lead <= 0.0:
			continue
		var g_fade: float = fade * pow(CRESCENT_GHOST_FALLOFF, float(ghost))
		var g_half: float = half * (1.0 - 0.16 * float(ghost))
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		var spine := PackedVector2Array()
		var far: float = 0.0
		for i: int in steps + 1:
			var off: float = (float(i) / float(steps) - 0.5) * 2.0
			var belly: float = 1.0 - off * off          # 1 at the middle, 0 at the tips
			var bow: float = belly * g_half * 0.9
			var thick: float = belly * maxf(_width * 0.5, 3.5) * (0.4 + 0.6 * t)
			var mid: Vector2 = dir * (lead + bow) + perp * off * g_half
			spine.append(mid)
			outer.append(mid + dir * thick)
			inner.append(mid - dir * thick)
			far = maxf(far, mid.length() + thick)
		# Trailing edge back along the inside closes the blade into one shape.
		for i: int in inner.size():
			outer.append(inner[inner.size() - 1 - i])
		draw_colored_polygon(outer, Color(c.r, c.g, c.b, 0.42 * g_fade))
		_bump(outer.size(), far)
		# The lit edge. Only the leading ghost gets the white core — every ghost
		# carrying it would read as four blades rather than one that moved.
		draw_polyline(spine, Color(c.r, c.g, c.b, 0.85 * g_fade), 2.2 * g_fade + 0.4, true)
		_bump(steps, far)
		if ghost == 0:
			draw_polyline(spine, Color(1.6, 1.6, 1.6, 0.7 * g_fade), 1.2 * fade + 0.3, true)
			_bump(steps, far)
