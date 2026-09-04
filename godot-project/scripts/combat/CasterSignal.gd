class_name CasterSignal
extends Node2D
## A charge-up glow that rides ON the caster's body while it winds up an attack —
## the "signal FROM the caster" the maker asked for: energy gathers, motes spiral
## inward, a core brightens as the tell fills, so your eye goes to the DANGEROUS
## enemy, not to an abstract shape planted on the ground. Purely cosmetic; grows
## over the windup, briefly blooms, and self-frees. Reused by every archetype
## (accent-tinted), spawned as a child of the Enemy so it follows a shoved body.
## Pure Node2D draw — no scene file, headless-safe (only _process/_draw).

const FADE: float = 0.12
## Motes spiralling into the core. SEVEN reads as "energy gathering"; three still
## reads as it and four fewer motes is four fewer `draw_circle` PAIRS per frame.
## ⚠ NOT ZERO at LOW. The motes are the only part of this figure that MOVES
## inward, and the inward movement is the whole statement ("something is being
## gathered, and it is nearly gathered"). A still glow says nothing.
const MOTES: int = 7
const MOTES_LOW: int = 3
## Segments on the contracting ring. Scaled by radius through the shared sagitta
## rule rather than pinned, for the reason `MagicCircle._seg` gives at length: a
## 13 px ring at 32 segments is one segment every 2.5 px, which is geometry nobody
## can see at any resolution this game ships at.
const RING_SEGMENTS: int = 32

var _color: Color = Color(1.0, 0.3, 0.2, 1.0)
var _windup: float = 0.6
var _elapsed: float = 0.0
var _running: bool = false
var _base_r: float = 13.0
## ⚠ THIS CLASS IGNORED `graphics_quality` ENTIRELY, and it is not a small one to
## miss: a CasterSignal is spawned alongside EVERY enemy telegraph in the game
## (`Enemy._spawn_caster_signal`, called from all seven windups), so on a busy
## floor it is one of these per winding-up body on top of the tell itself.
## DECLARED so a headless suite can set it — the `SpawnTell` idiom.
var _low: bool = false


## The LOW plan as pure functions, so the degradation is arithmetic a test can
## check rather than a picture somebody has to look at.
static func motes_for(low: bool) -> int:
	return MOTES_LOW if low else MOTES


static func ring_segments(r: float, low: bool) -> int:
	return MagicCircle.seg_of(RING_SEGMENTS, r, low, false)


func _ready() -> void:
	_low = TuningConfig.quality_is_low()


## Begin the gather. `base_radius` scales the whole effect (small for a caster's
## bolt, bigger for a bomber's fuse). Auto-frees after windup + FADE.
func charge(color: Color, windup: float, base_radius: float = 13.0) -> void:
	_color = color
	_windup = maxf(windup, 0.05)
	_base_r = base_radius
	_elapsed = 0.0
	_running = true
	queue_redraw()


## ══ DEAD AIR AT THE MOMENT OF THE PAYOFF ══════════════════════════════════════
## THE GLOW IS SWITCHED OFF, NOT RELEASED, and this class was built to bloom.
## `_draw` already computes a `fade` for the `FADE` seconds after the windup and
## `_process` frees the node at `_windup + FADE` — so left alone the gather flares
## and lets go. It is never left alone: `Enemy._on_telegraph_fired` calls
## `_free_caster_signal()`, which `queue_free()`s on the exact frame the tell
## fires. The bloom has therefore never once been seen in the game.
##
## The maker's bar is "no dead air anywhere", and this is the opposite fault — a
## hard cut precisely where the release should be, on the BODY, at the frame the
## danger lands. The tell's own fired flash covers the danger POINT; nothing covers
## the caster.
##
## ⚠ THE FIX IS TWO FILES AND THE OTHER HALF IS NOT MINE. `Enemy.gd`'s
## `_free_caster_signal` must call `release()` instead of `queue_free()` — but ONLY
## from `_on_telegraph_fired`. `_abort_attack` uses the same helper and an
## INTERRUPTED charge must still snap off: a windup that was cancelled blooming out
## like a completed one would say the attack happened when it did not, which is a
## worse lie than the missing bloom. So the caller needs the two paths split.
## Until that lands this method is unreferenced, deliberately, and this block is
## the record of why.
func release() -> void:
	if not _running:
		queue_free()
		return
	# Jump the clock to the start of the bloom and let `_process` finish the job.
	# Not a second timer: the fade curve, its length and the self-free already exist
	# below, and a release that re-implemented them could drift from the draw.
	_elapsed = maxf(_elapsed, _windup)
	queue_redraw()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	if _elapsed >= _windup + FADE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if not _running:
		return
	var t: float = clampf(_elapsed / _windup, 0.0, 1.0)
	var fade: float = 1.0
	if _elapsed > _windup:
		fade = clampf(1.0 - (_elapsed - _windup) / FADE, 0.0, 1.0)
	var c: Color = _color
	var pulse: float = 0.85 + 0.15 * sin(_elapsed * 24.0)

	# Soft gathering glow, growing with the charge.
	var glow_r: float = _base_r * (0.55 + 0.85 * t) * pulse
	draw_circle(Vector2.ZERO, glow_r, Color(c.r, c.g, c.b, 0.13 * fade))
	draw_circle(Vector2.ZERO, glow_r * 0.6, Color(c.r, c.g, c.b, 0.16 * fade))

	# A ring that contracts inward — energy being pulled into the body.
	var ring_r: float = _base_r * (1.5 - 0.85 * t)
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, ring_segments(ring_r, _low),
		Color(c.r, c.g, c.b, 0.45 * t * fade), 2.0)

	# Motes spiralling in toward the core. The angular SPREAD is divided by the live
	# count, not by the constant, so three motes at LOW still ring the core evenly
	# instead of bunching into the first 3/7 of the circle.
	var motes: int = motes_for(_low)
	for i: int in motes:
		var ang: float = _elapsed * 3.2 + TAU * float(i) / float(motes)
		var mr: float = maxf(_base_r * (1.55 - 1.15 * t) + 2.0 * sin(_elapsed * 6.0 + float(i)), 1.0)
		var pos: Vector2 = Vector2.from_angle(ang) * mr
		var a: float = clampf(0.35 + 0.5 * t, 0.0, 1.0) * fade
		draw_circle(pos, 2.0, Color(c.r, c.g, c.b, a * 0.5))
		draw_circle(pos, 1.1, Color(1.0, 1.0, 1.0, a))

	# Hot core, brightening as the tell fills.
	var core: float = _base_r * (0.1 + 0.26 * t) * pulse
	draw_circle(Vector2.ZERO, core, Color(c.r, c.g, c.b, 0.5 * fade))
	draw_circle(Vector2.ZERO, core * 0.55, Color(1.0, 1.0, 1.0, (0.45 + 0.45 * t) * fade))
