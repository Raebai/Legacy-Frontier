extends Node2D
## ══ THE SPAWN TELL ═══════════════════════════════════════════════════════════
## A body used to APPEAR. `Encounter._pick_spawn_position` picked a point 190-230px
## from the hero and `add_child`ed a stick figure into it — from nothing, with no
## mark, no flash and no warning — and a wave's VANGUARD did two of those in the
## same frame. Two unreadable spawns feel like five, which is most of what "it's
## probably maybe a little too flooded" is actually describing: not the count, the
## impossibility of ANTICIPATING the count.
##
## So: ink first, body second.
##
## ── WHY A SCRIBBLE AND NOT A DANGER SIGIL ────────────────────────────────────
## This floor's conceit is that an unseen hand DRAWS the room and its mobs live
## (see the PACING block at the top of Encounter.gd, and the pencil-tip mark in
## Lobby's `_Paper`). The honest tell is therefore not a red circle — the roster
## already owns red circles, and Telegraph is the language of "an attack lands
## HERE". It is the DRAWING ITSELF, caught a beat early: a scribbled ground mark,
## then a spine, a head, legs and (on the full picture) arms hatched in, then the
## ink blots and the body is standing in it.
##
## Its LEAD (0.4s, owned by Encounter.SPAWN_TELL_LEAD) is deliberately shorter
## than every attack windup in the roster except the assassin's — Enemy's tells
## run 0.6/0.7/0.85/0.9 — so a spawn tell can never be misread as an incoming hit
## you have to dodge. Different shape, different colour source, shorter clock.
##
## ── PURE COSMETIC ────────────────────────────────────────────────────────────
## No collision, no damage, no `enemy`/`mortal` group, no gameplay state at all.
## The WAITING belongs to Encounter, which counts the still-unborn body against
## both the wave's concurrent cap and the 25-entity budget for the whole time this
## node is on screen — so a tell can never let MORE bodies exist at once than
## before it existed. If that accounting were ever dropped the tell would produce
## the exact opposite of what it is for. See Encounter._pending_tells.
##
## ── THE MOBILE DIAL ──────────────────────────────────────────────────────────
## `graphics_quality = LOW` (the phone, and the maker's desktop phone-preview)
## drops the GARNISH and never the READ: arms, torso hatching, the soft glow and
## the second lap of the ground ellipse all go, and the redraw rate halves, but
## the ground mark, spine, head and legs are drawn at full strength at every
## progress. A cheaper tell is fine; an invisible one defeats the feature.
## `stroke_plan()` is a pure static so a headless suite can assert exactly that
## without a renderer — see tools/slice_test_spawntell.gd.

# ------------------------------------------------------------------- stroke ids
const S_GROUND: int = 0
const S_SPINE: int = 1
const S_HEAD: int = 2
const S_LEGS: int = 3
const S_ARMS: int = 4
const S_HATCH: int = 5
const S_BLOT: int = 6

## THE HAND'S ORDER, and the single source of truth shared by `stroke_plan()`
## (pure, testable) and `_draw()` (the picture). Rows are:
##   [id, appears_at, complete_by, survives_LOW, min_heft]
## `appears_at`/`complete_by` are fractions of the lead, so every stroke is drawn
## PARTIALLY as it arrives rather than popping in whole — that is the difference
## between "a hand is drawing this" and "shapes are being switched on".
const STROKES: Array = [
	[S_GROUND, 0.00, 0.22, true,  0.0],
	[S_SPINE,  0.10, 0.34, true,  0.0],
	[S_HEAD,   0.28, 0.52, true,  0.0],
	[S_LEGS,   0.45, 0.72, true,  0.0],
	[S_ARMS,   0.62, 0.88, false, 0.0],
	[S_HATCH,  0.55, 0.80, false, 0.7],
]

## How long the ink stays after the body lands, in seconds. The blot deliberately
## OUTLIVES the spawn by a blink so you see the figure arrive INTO its own mark —
## which is what sells the causality ("that scribble became that thing").
const POP_TIME: float = 0.09

## Redraws per second. The stroke geometry is re-derived from `progress` each
## time, so a low rate reads as a hand working in strokes rather than as a low
## frame rate (the same trick Lobby._Paper uses at 7 Hz for its tower reveal).
## HALVED on the cheap picture: this can be on screen 5-7 times in a wave.
const REDRAW_HZ_HIGH: float = 20.0
const REDRAW_HZ_LOW: float = 10.0

## Default stick height, matching CharacterRig.height (31.0) so the mark is the
## size of the silhouette that replaces it.
const FIG_HEIGHT: float = 31.0

var _lead: float = 0.4
var _tint: Color = Color(0.95, 0.5, 0.25, 1)
var _heft: float = 0.5
var _fig_h: float = FIG_HEIGHT
var _t: float = 0.0
var _next_draw: float = 0.0
var _low: bool = false
var _redraws: int = 0
## ENTERED / COMPLETED, the `_draw` half of this repo's completion-sentinel idiom
## (tools/slice_test_loadout.gd). A runtime error inside `_draw` ABORTS the
## function and the engine emits the `draw` signal anyway, so "it drew" proves
## nothing on its own — but an abort leaves `entered > completed`, which a headless
## suite CAN see. `_draw` really does run under `--headless` (measured), so this
## turns an otherwise invisible class of bug into a failing test.
var _draw_entered: int = 0
var _draw_done: int = 0
var _seed: int = 0
var _rng := RandomNumberGenerator.new()


## Called BEFORE `add_child` (the house pattern for riders — see
## Encounter.build_enemy_from_data) so the first frame already has final values.
func configure(lead: float, tint: Color, heft: float, fig_height: float = FIG_HEIGHT) -> void:
	_lead = maxf(lead, 0.01)
	_tint = tint
	_heft = clampf(heft, 0.0, 1.0)
	_fig_h = maxf(fig_height, 6.0)
	# Per-instance, re-applied at the top of every _draw: the wobble is then STABLE
	# across redraws (a 20 Hz re-roll would read as noise, not ink) while two tells
	# in the same burst are still visibly two different scribbles.
	_seed = hash(Vector2(_heft, float(get_instance_id() & 0xFFFF)))


func _ready() -> void:
	_low = TuningConfig.quality_is_low()
	z_index = -1        # under the bodies: the body must land ON its mark
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# SELF-FREEING. Encounter frees this when it emits the body (guarded by
	# is_instance_valid), but the co-op TWIN on a client has no owner at all, so
	# the node has to be able to end itself or every replicated spawn leaks one.
	if _t >= _lead + POP_TIME:
		queue_free()
		return
	_next_draw -= delta
	if _next_draw <= 0.0:
		_next_draw = 1.0 / redraw_hz(_low)
		_redraws += 1
		queue_redraw()


# ------------------------------------------------------------------ pure plan
## Which strokes are on the page at `progress` (0..1 of the lead; >= 1.0 is the
## blot). PURE — no tree, no renderer, no instance state — so the LOW-degradation
## and readability contracts are assertable in a headless suite.
##
## The invariant that matters: this is NEVER empty for progress >= 0, and the LOW
## list always still contains S_GROUND, and by 0.30 also S_SPINE and S_HEAD.
static func stroke_plan(progress: float, heft: float, low: bool) -> Array[int]:
	var out: Array[int] = []
	if progress < 0.0:
		return out
	for row: Array in STROKES:
		if low and not bool(row[3]):
			continue
		if heft < float(row[4]):
			continue
		if progress >= float(row[1]):
			out.append(int(row[0]))
	if progress >= 1.0:
		out.append(S_BLOT)
	return out


static func redraw_hz(low: bool) -> float:
	return REDRAW_HZ_LOW if low else REDRAW_HZ_HIGH


## How HEAVY this archetype's scrawl reads. Cheap archetype hinting: a BRUTE is
## drawn with a wider stance, a fatter line and cross-hatched weight; an ASSASSIN
## is a thin fast scratch. Legibility first — every value still produces the same
## READABLE mark, only its weight changes.
## Archetype ids match Enemy.Archetype / GameState's A_* constants.
static func heft_for_archetype(kind: int) -> float:
	match kind:
		1: return 1.0    # BRUTE    — the heaviest thing in the trash roster
		6: return 0.85   # BOMBER   — squat and loaded
		4: return 0.70   # SUMMONER — reads as "more is coming"
		3: return 0.60   # CHARGER
		2: return 0.50   # CASTER
		7: return 0.50   # MAGE
		5: return 0.30   # ASSASSIN — a thin fast scratch
		_: return 0.42   # CHASER


## Redraw count so far. Read by the headless suite (deterministic work, unlike a
## millisecond timer — and note Performance.TIME_PROCESS excludes _draw entirely,
## so wall-clock could never have proved this cheap).
func redraws() -> int:
	return _redraws


func progress() -> float:
	return clampf(_t / _lead, 0.0, 2.0)


## `_draw` calls started / finished. Equal means no draw has ever aborted part-way.
func draw_counts() -> Vector2i:
	return Vector2i(_draw_entered, _draw_done)


# ---------------------------------------------------------------------- picture
func _draw() -> void:
	_draw_entered += 1
	_rng.seed = _seed
	var p: float = _t / _lead
	var plan: Array[int] = stroke_plan(p, _heft, _low)
	if plan.is_empty():
		_draw_done += 1
		return
	# The hand tightens as the drawing resolves: loose at the start, steady at the
	# end. This is most of what makes it read as DRAWN rather than as an animation.
	var wobble: float = lerpf(3.2, 0.7, clampf(p, 0.0, 1.0))
	var w: float = lerpf(1.1, 2.4, _heft)
	var ink: Color = _tint
	ink.a = lerpf(0.40, 0.95, clampf(p, 0.0, 1.0))

	var hip_y: float = -_fig_h * 0.46
	var neck_y: float = -_fig_h * 0.76
	var head_y: float = -_fig_h * 0.87
	var head_r: float = _fig_h * 0.14
	var stance: float = _fig_h * (0.10 + 0.09 * _heft)
	var shoulder: float = _fig_h * (0.11 + 0.06 * _heft)

	for id: int in plan:
		var f: float = _stroke_fill(id, p)
		match id:
			S_GROUND:
				var rx: float = _fig_h * 0.34 * (0.75 + 0.5 * _heft)
				# GARNISH: the soft glow and the second, tighter lap are the first
				# things the cheap picture gives up. The lap itself never is.
				if not _low:
					var glow: Color = _tint
					glow.a = 0.16 * f
					draw_circle(Vector2.ZERO, rx * 1.15, glow)
				_scribble_ellipse(rx * f, rx * 0.42 * f, ink, w, wobble)
				if not _low:
					_scribble_ellipse(rx * 0.66 * f, rx * 0.28 * f, ink, w * 0.7, wobble * 0.7)
			S_SPINE:
				_scribble(Vector2(0.0, hip_y), Vector2(0.0, neck_y), ink, w, wobble, f)
				_scribble(Vector2.ZERO, Vector2(0.0, hip_y), ink, w, wobble, f)
			S_HEAD:
				_scribble_ellipse_at(Vector2(0.0, head_y), head_r * f, head_r * f, ink, w, wobble)
			S_LEGS:
				_scribble(Vector2(0.0, hip_y), Vector2(-stance, 0.0), ink, w, wobble, f)
				_scribble(Vector2(0.0, hip_y), Vector2(stance, 0.0), ink, w, wobble, f)
			S_ARMS:
				var arm_y: float = neck_y + _fig_h * 0.06
				_scribble(Vector2(0.0, neck_y), Vector2(-shoulder * 1.5, arm_y + _fig_h * 0.18),
					ink, w * 0.85, wobble, f)
				_scribble(Vector2(0.0, neck_y), Vector2(shoulder * 1.5, arm_y + _fig_h * 0.18),
					ink, w * 0.85, wobble, f)
			S_HATCH:
				# WEIGHT. Only the heavy archetypes get cross-hatched, and only on
				# the full picture — this is the "a BRUTE's scrawl reads heavier"
				# hint, and it is pure garnish by construction.
				for i: int in 3:
					var t: float = 0.25 + 0.25 * float(i)
					var y: float = lerpf(hip_y, neck_y, t)
					_scribble(Vector2(-shoulder * 0.9, y), Vector2(shoulder * 0.9, y - _fig_h * 0.05),
						ink, w * 0.6, wobble * 0.6, f)
			S_BLOT:
				# THE INK LANDS. A quick expanding ring the body arrives inside of.
				var bt: float = clampf((_t - _lead) / POP_TIME, 0.0, 1.0)
				var blot: Color = _tint
				blot.a = (1.0 - bt) * 0.85
				draw_arc(Vector2(0.0, hip_y), _fig_h * (0.28 + 0.5 * bt), 0.0, TAU, 14, blot, w * 1.2, true)
	_draw_done += 1   # LAST LINE. See _draw_entered.


## Fraction of stroke `id` that is on the page at `progress`.
func _stroke_fill(id: int, progress: float) -> float:
	if id == S_BLOT:
		return 1.0
	for row: Array in STROKES:
		if int(row[0]) != id:
			continue
		var a: float = float(row[1])
		var b: float = maxf(float(row[2]), a + 0.001)
		return clampf((progress - a) / (b - a), 0.0, 1.0)
	return 1.0


## One hand-drawn stroke: jittered along its length, no jitter at the endpoints
## (or the figure falls apart where strokes meet). `fill` draws only the first
## `fill` of it, which is what "being drawn" looks like.
func _scribble(p0: Vector2, p1: Vector2, col: Color, width: float, wobble: float,
		fill: float = 1.0) -> void:
	var end: Vector2 = p0.lerp(p1, clampf(fill, 0.0, 1.0))
	var segments: int = 4
	var pts := PackedVector2Array()
	for s: int in segments + 1:
		var t: float = float(s) / float(segments)
		var p: Vector2 = p0.lerp(end, t)
		var jitter: float = wobble * sin(PI * t)
		p += Vector2(_rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter, jitter))
		pts.append(p)
	if pts.size() >= 2:
		draw_polyline(pts, col, width, true)


func _scribble_ellipse(rx: float, ry: float, col: Color, width: float, wobble: float) -> void:
	_scribble_ellipse_at(Vector2.ZERO, rx, ry, col, width, wobble)


func _scribble_ellipse_at(c: Vector2, rx: float, ry: float, col: Color, width: float,
		wobble: float) -> void:
	if rx <= 0.5 or ry <= 0.5:
		return
	var steps: int = 9 if _low else 13
	var pts := PackedVector2Array()
	for s: int in steps + 1:
		var a: float = TAU * float(s) / float(steps)
		# The overshoot on the last step is what makes a drawn circle look drawn.
		var p: Vector2 = c + Vector2(cos(a) * rx, sin(a) * ry)
		p += Vector2(_rng.randf_range(-wobble, wobble), _rng.randf_range(-wobble, wobble) * 0.5)
		pts.append(p)
	draw_polyline(pts, col, width, true)
