class_name SteamCloud
extends Node2D
## What is LEFT when fire boils a frost field off — the `steam_cloud` reaction's
## payoff, and the only reaction in ReactionTable whose reward is VISION rather
## than damage.
##
## It deals nothing, applies nothing and stops nothing. It is a bank of steam
## standing where the field was, thick enough in the middle to HIDE what walks
## into it, thinning at the rim, drifting up and coming apart over a couple of
## seconds. If it ever gains damage it stops being the matrix's one non-damage
## answer, so: don't.
##
## ⚠ PARKED AT THE ARENA ORIGIN, DRAWN IN WORLD COORDINATES — the trap
## SpellGeometry, SpellWorld, SpellTargets and SpellReactor all shout about. This
## node's `global_position` is (0, 0) and is NOT where the steam is; the steam is
## at `_at`, which `boil()` was handed and `_draw()` builds every lobe from.
##
## NOT a reaction participant, deliberately. Registering it would put a FIELD-ish
## shape into the reactor with no authored row on any side of it, which buys
## nothing and risks a surprise the day someone writes a wildcard FIELD row. If
## steam should conduct lightning, that is a ROW plus a registration, decided
## together.
##
## THE CONCEALMENT SEAM. `conceals()` is a pure static function, so "is this point
## hidden right now" is answerable without a scene and without reading a transform.
## Nothing consumes it yet — enemy perception is another agent's file — but it is
## the honest place for a bot to ask, and it means the drawn cloud and any future
## "they can't see you in there" rule are built from ONE number instead of two that
## drift apart.

## ---------------------------------------------------------------------------
## STEAM TUNING. Every number here is REASONED, NOT FELT — nothing in this file
## has been playtested. They are grouped so one pass can retune the whole cloud.
## ---------------------------------------------------------------------------

## How long the bank stands before it has fully dispersed. UNTESTED GUESS: 2.6 s
## is long enough to actually reposition behind it (a dash is 0.14 s and a
## reload-and-reposition beat is around a second) and short enough that it cannot
## be used to simply delete a fight.
const LIFETIME: float = 2.6
## Fraction of the life spent billowing outward before the cloud starts thinning.
## UNTESTED GUESS: a third — steam expands fast and lingers slow.
const BILLOW_FRAC: float = 0.34
## Radius multipliers over the life: it starts as a tight burst at the field's
## centre and swells past the field's own edge, because boiling water occupies
## more space than the ice did. UNTESTED GUESSES.
const RADIUS_START_FRAC: float = 0.42
const RADIUS_END_FRAC: float = 1.18
## How fast the whole bank rises, px/s. Steam goes UP; a cloud that sat still
## would read as smoke on the floor. UNTESTED GUESS.
const RISE_SPEED: float = 26.0
## Peak opacity of the cloud's core. HIGH ON PURPOSE — this is the one effect in
## the game whose job is to be in the way, and a tasteful 30% haze would make the
## reaction's entire payoff invisible. UNTESTED GUESS, and the first knob to touch
## if the arena becomes unreadable.
const CORE_ALPHA: float = 0.82
## Number of overlapping lobes the bank is built from. Enough that the silhouette
## is lumpy rather than a circle; few enough that this is cheap to draw.
const LOBES: int = 9
## Each lobe's radius as a fraction of the bank's, and how far off centre it sits.
## UNTESTED GUESSES — tuned by eye in the capture, not by play.
const LOBE_RADIUS_FRAC: float = 0.46
const LOBE_OFFSET_FRAC: float = 0.58
## Lobes churn slowly around the centre so the bank is never a still image.
const CHURN_SPEED: float = 0.55
## Drawn above the fighters so it genuinely occludes them. Spell spectacles sit
## around 0 by default; this is the only effect in the game that WANTS to be on
## top of a character. UNTESTED GUESS.
const Z_ABOVE_FIGHTERS: int = 40

## Steam is white-grey, not tinted: it is water, and the fire that made it is
## already gone by the time this exists. A tinted cloud would read as a lingering
## fire effect and re-attach the payoff to the attacker.
const STEAM_CORE: Color = Color(0.92, 0.94, 0.96)
const STEAM_RIM: Color = Color(0.72, 0.78, 0.84)

## Where the bank is, in WORLD space. Never read from `global_position` — see the
## trap note in the class docs.
var _at: Vector2 = Vector2.ZERO
## The radius the reaction handed us: the frost field's own footprint.
var _base_radius: float = 160.0
var _elapsed: float = -1.0     # < 0 = not boiled yet


## Public entry: a bank of steam at world point `at`, sized to the field that was
## boiled off. Instantiate .new(), add as a child of the arena, then call this.
func boil(at: Vector2, radius: float) -> void:
	_at = at
	_base_radius = maxf(radius, 1.0)
	# We draw in world coordinates from `_at`; the node itself sits at the origin.
	global_position = Vector2.ZERO
	z_index = Z_ABOVE_FIGHTERS
	_elapsed = 0.0
	queue_redraw()


# --------------------------------------------------------- the pure geometry

## The bank's radius at `t01` (0..1 through its life). Pure and static so the
## drawn extent and any future "am I hidden" test are the SAME number rather than
## two that drift — the two-schemes bug this codebase keeps finding.
static func radius_at(base_radius: float, t01: float) -> float:
	var t: float = clampf(t01, 0.0, 1.0)
	# Billow fast, then hold: the swell is over in the first third, and after that
	# the cloud thins rather than growing, which is what steam does.
	var u: float = minf(t / BILLOW_FRAC, 1.0)
	var eased: float = 1.0 - (1.0 - u) * (1.0 - u)   # ease-out
	return base_radius * lerpf(RADIUS_START_FRAC, RADIUS_END_FRAC, eased)


## How far the bank has drifted upward by `t01`.
static func rise_at(t01: float) -> float:
	return -RISE_SPEED * LIFETIME * clampf(t01, 0.0, 1.0)


## Is world point `p` hidden inside the bank at `t01`?
##
## ⚠ THE NEGATIVE CASE IS THE POINT. "The spells shouldn't be able to get out the
## radius" applies to concealment too — a cloud that hid things outside its own
## drawn silhouette would be the same bug wearing a friendlier hat. This is the
## one test, `_draw` builds its lobes inside the same radius, and the ward suite
## asserts a point just outside is NOT concealed.
static func conceals(at: Vector2, base_radius: float, t01: float, p: Vector2) -> bool:
	if t01 < 0.0 or t01 > 1.0:
		return false
	var centre: Vector2 = at + Vector2(0.0, rise_at(t01))
	return centre.distance_to(p) <= radius_at(base_radius, t01)


## 0..1 through the cloud's life, or -1 before it has boiled.
func progress() -> float:
	return _elapsed / LIFETIME if _elapsed >= 0.0 else -1.0


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return
	queue_redraw()


## Deterministic 0..1 from an int — stable garnish with no RNG state, so a redraw
## does not make the lobes pop to new places. Same helper BeamSpell uses.
static func _hash01(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0)


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var t: float = clampf(_elapsed / LIFETIME, 0.0, 1.0)
	var r: float = radius_at(_base_radius, t)
	# Opacity: full through the billow, then a long even thinning. The cloud never
	# snaps off — a concealment effect that vanishes on a frame reads as a bug in
	# whatever the player was hiding from.
	var fade: float = 1.0 if t < BILLOW_FRAC else 1.0 - (t - BILLOW_FRAC) / (1.0 - BILLOW_FRAC)
	var alpha: float = CORE_ALPHA * clampf(fade, 0.0, 1.0)
	if alpha <= 0.01:
		return
	var centre: Vector2 = _at + Vector2(0.0, rise_at(t))
	# A soft outer haze first, so the bank has a rim instead of a hard circle edge.
	draw_circle(centre, r, Color(STEAM_RIM.r, STEAM_RIM.g, STEAM_RIM.b, alpha * 0.22),
		true, -1.0, true)
	# Then the lobes. Every one is kept INSIDE `r` by construction — offset plus
	# lobe radius never exceeds the bank radius — which is what makes `conceals()`
	# an honest description of the silhouette rather than an approximation of it.
	var lobe_r: float = r * LOBE_RADIUS_FRAC
	var spread: float = r * LOBE_OFFSET_FRAC * minf(1.0, r / maxf(_base_radius, 1.0) + 0.35)
	for i: int in LOBES:
		var seed: float = _hash01(i * 37 + 11)
		var ang: float = TAU * (float(i) / float(LOBES) + seed * 0.18) \
			+ _elapsed * CHURN_SPEED * (0.6 + seed * 0.8)
		# The middle lobe stays put so the core never opens a hole in itself.
		var dist: float = 0.0 if i == 0 else spread * (0.35 + 0.65 * seed)
		var p: Vector2 = centre + Vector2.from_angle(ang) * dist
		var rr: float = lobe_r * (0.72 + 0.5 * _hash01(i * 91 + 5))
		# Clamp so no lobe can bulge past the bank's own edge (the reach contract).
		rr = minf(rr, r - dist)
		if rr <= 1.0:
			continue
		# THREE rings per lobe, each smaller and brighter. draw_circle has hard
		# edges, so a single disc per lobe reads as a soap bubble — which is exactly
		# what the first capture showed: a cluster of crisp circles rather than a
		# bank of steam. Stacking a falloff fakes the gradient, and the low
		# per-ring alpha means the density comes from lobes OVERLAPPING rather than
		# from any one of them being opaque.
		draw_circle(p, rr, Color(STEAM_RIM.r, STEAM_RIM.g, STEAM_RIM.b, alpha * 0.16),
			true, -1.0, true)
		draw_circle(p, rr * 0.74, Color(STEAM_CORE.r, STEAM_CORE.g, STEAM_CORE.b,
			alpha * 0.22), true, -1.0, true)
		draw_circle(p, rr * 0.44, Color(1.0, 1.0, 1.0, alpha * 0.26), true, -1.0, true)
	# A few wisps curling through the top of the bank — the read that this is
	# RISING rather than sitting.
	#
	# ⚠ KEPT INSIDE `r`, DELIBERATELY. The first version threw them up to 1.3x the
	# bank radius and the capture showed them clearly outside the silhouette that
	# `conceals()` describes. Nothing consumes concealment yet, so it was not a
	# damage bug — it was the SAME bug one step earlier, drawing an effect outside
	# its own tested extent, and that is how the next drawn-vs-real mismatch gets
	# in. The bank radius is the authority; nothing is drawn past it.
	for i: int in 5:
		var seed2: float = _hash01(i * 53 + 3)
		var wt: float = fposmod(seed2 + _elapsed * 0.5, 1.0)
		var wx: float = (seed2 * 2.0 - 1.0) * r * 0.42
		var wr: float = r * 0.13 * (0.5 + wt)
		# Height is capped so the wisp's own rim cannot cross the bank's edge.
		var lift: float = minf(r * (0.30 + 0.42 * wt), r - wr - absf(wx))
		if lift <= 0.0:
			continue
		var wp: Vector2 = centre + Vector2(wx, -lift)
		draw_circle(wp, wr, Color(1.0, 1.0, 1.0, alpha * 0.34), true, -1.0, true)
