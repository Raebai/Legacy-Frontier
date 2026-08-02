class_name MagicCircle
extends Node2D
## Procedural animated ARCANE SIGIL, in TWO orientations because this is a
## SIDE-ON 2D game and a sigil's look depends on the spell's geometry:
##
##  FACE-ON (set_orientation false) — the full summoning circle you see head-on:
##    emanating pulse rings, an outer ring + dashed summoning ring + runic ticks
##    (spin CW), a counter-rotating mid ring with radial spokes (CCW), an
##    inscribed hexagram over a counter-rotating square, orbiting glyph motes, a
##    breathing core. Used for AREA / portal spells (meteor sky sigil, summons,
##    ground AoE) — where magic pours out of a 2D disc.
##
##  EDGE-ON (set_orientation true, along the beam axis) — the sigil seen from the
##    SIDE: a thin lens/gate the beam bursts THROUGH. In side-on 2D a beam's
##    circle faces the target, so from the camera it's a LINE perpendicular to
##    the beam. Nested edge-on rings, rim glyphs orbiting (foreshortened front/
##    back), a bright central aperture, a breathing core. Used for BEAMS (the
##    Zoltraak muzzle sigil, the divine-ray sky sigil).
##
## Grows in (appear), spins + breathes, blooms out (vanish + self-free). Reusable
## by every spectacle spell. Pure Node2D draw — no scene file.
##
##
## ============================ THE CAST → SPELL HAND-OFF ======================
## ONE CONTINUOUS SIGIL PER CAST. A cast is a ritual with a beginning, a middle
## and an end; the sigil the caster opens during the windup must be the SAME
## sigil the spell erupts from. Two independent spawners used to run per cast —
## the caster opened a windup circle and dismissed it, then the spectacle opened
## its own muzzle circle — so the player watched the ritual visibly RESTART
## mid-cast. That reads as a glitch, and it was the maker's report.
##
## The fix is a hand-off, not a second construction. The caster OFFERS its live
## circle at the moment of release; the spectacle ADOPTS it — reparented,
## re-anchored to the muzzle, TRAVELLING there from wherever the windup hung it
## (over the caster's head, for the big spells), with its spin, phase and
## breathing carried straight through. No appear() replay, no blink.
##
## ---- CASTER SIDE (one line, at the moment the spell actually fires) ---------
##     MagicCircle.offer(my_circle, self)        # instead of my_circle.vanish(t)
## and on any INTERRUPTION (windup cancelled, caster hit, caster died):
##     MagicCircle.withdraw(self)                # blooms an un-taken offer out
## `withdraw` is belt-and-braces, not load-bearing: an offer nobody claims within
## OFFER_TTL_MS blooms itself out anyway (see _process). That is deliberate —
## most spells (walls, novas, dashes) open no sigil of their own, so their offers
## are MEANT to go unclaimed and must degrade to exactly the old behaviour.
##
## ---- SPECTACLE SIDE (one line, replacing `MagicCircle.new()` + appear) ------
##     _circle = MagicCircle.adopt_or_open(
##         self, caster_node, muzzle_world_pos, colour, radius, grow_time,
##         edge_on, axis_dir, thickness, travel_time)
## Returns a circle either way, so ADOPTION IS OPTIONAL AND NEVER REQUIRED: with
## no offer pending (enemy casts, boss casts, reaction-spawned spectacles, remote
## co-op peers) it constructs and appear()s one exactly as before. Every existing
## `_circle.vanish(...)` / `is_instance_valid(_circle)` call site keeps working
## untouched — an adopted circle is an ordinary MagicCircle.
##
## ---- THREE RULES THE CALL SITES MUST HONOUR --------------------------------
## 1. ORDER: offer() must run BEFORE the spell is spawned, in the SAME FRAME.
##    The spectacle adopts inside its own constructor path, so an offer made
##    after SpellCaster.cast() arrives too late and the spectacle has already
##    built its own sigil — the exact bug this seam exists to kill. In Hero that
##    means the offer belongs in the teardown that already runs ahead of the
##    cast, not after it.
## 2. LET GO: the caster must null its own reference right after offering. The
##    sigil now belongs to the spell; a caster that keeps driving its position or
##    scale per-frame will fight the travel and drag the sigil back to its head.
## 3. SUCCESS PATH ONLY: offer() on the path where the spell actually fires.
##    An interrupted windup should still vanish() (or shatter) as it always did —
##    a shattered cast has no spell to hand its sigil to, and the shatter VFX is
##    the point of that moment.
##
## THE COORDINATE TRAP: spell spectacle nodes park at the arena origin and draw
## in WORLD coordinates, so their global_position is (0,0) and is NOT where the
## effect is (SpellGeometry.gd documents this at length). A circle handed from a
## caster (real transform) to a spectacle (parked at origin) is exactly where
## that bites, so the reparent goes through Node.reparent(keep_global_transform)
## and every position in this API is WORLD space. Never pass a local offset.

const SPIN_SPEED: float = 1.15
const TICKS: int = 28
const DASH_SEGMENTS: int = 22
const SPOKES: int = 8
const MOTES: int = 7
const PULSE_RINGS: int = 3
const GROW_TIME_DEFAULT: float = 0.3
const EDGE_TICKS: int = 12


# ======================== SIGNATURE: WHICH SPELL IS THIS? ====================
## THE CIRCLE IS THE TELEGRAPH. The spec's rule for big spells is that they must be
## "loud, committal, answerable", and the only thing the opponent can read during a
## windup is the sigil hanging over the caster's head. So the sigil has to answer two
## questions at a glance, before the spell exists:
##
##   WHAT ELEMENT?  -> the GLYPH BAND. Eight hand-drawn rim vocabularies (flame
##                     tongues / crystal facets / zigzags / hooked tendrils / runes /
##                     stone slabs / radiant rays / swirls). Colour alone is not
##                     enough: fire-orange and earth-amber are neighbours, holy-gold
##                     and lightning-yellow are neighbours, and at 360 px on a phone
##                     two warm rings are the same ring. SHAPE separates them.
##
##   HOW BIG?       -> the TIER LADDER. A QUICK jab opens a thin single ring; a HEAVY
##                     adds the inner mechanism (spokes + hexagram); an ULT adds an
##                     outer summoning ring and a counter-rotating second glyph band.
##                     Same rule the impact frames and the clash weights already use
##                     (SpellTier), never a fourth scale that could disagree.
##
## Both default to "not told" and DEGRADE, they do not fail: an unset element draws
## the original generic runic ticks, and an unset tier is inferred from radius. That
## is what lets Hero's windup sigil — opened by a file this pass may not touch — pick
## up its element for free (see `_infer_element`) without a single edit over there.

##   WHICH SPELL?   -> the MOTIF. One figure drawn in the sigil's inner court, keyed
##                     off the spectacle rather than off its element or its cost. The
##                     maker's note is that "meteor should look slightly different",
##                     and colour cannot carry that: every arcane spell in the roster
##                     is the same violet, so eleven of them opened the SAME circle.
##                     The motif is the axis that separates a meteor from a beam from
##                     a wall while all three are still purple ults.
##
##                     Deliberately a SHAPE LANGUAGE and not thirty-eight bespoke
##                     drawings: thirteen figures (descent / lance / barrier /
##                     eruption / orbit / pulse / snare / blade / ward / void /
##                     spiral / summon) cover the whole roster, because what a player
##                     needs to read is what the spell is ABOUT TO DO — something
##                     falls here, a line you cannot cross, this ring expands — not
##                     which of four wall spells it was. `SpellSigil` owns the
##                     spell -> motif table; this file only knows how to draw one.
##
##                     Drawn in the INNER COURT (0.30-0.62 R), between the core and
##                     the mechanism ring, so it never fights the element band on the
##                     rim. Both reads survive together: the rim still says FIRE, the
##                     middle now says FALLING.

## Glyph counts per tier. Deliberately coprime-ish with SPOKES/TICKS so the bands
## never phase-lock into a single fat spoke as they counter-rotate.
const GLYPHS_QUICK: int = 6
const GLYPHS_HEAVY: int = 10
const GLYPHS_ULT: int = 14

## Radius bands used to GUESS a tier when nobody said (Hero's windup sigil sizes
## itself from the spell's cost: ~17 px for a cheap jab up to ~34 px for an ult, and
## spectacle muzzle sigils are bigger still). A guess, explicitly — every spectacle
## that goes through `SpellSigil` states its tier outright and never lands here.
const TIER_RADIUS_QUICK: float = 21.0
const TIER_RADIUS_HEAVY: float = 30.0

## How close a colour must sit to an element's signature colour to be recognised as
## that element (squared CHROMA distance — see `_chroma`).
##
## MEASURED, not guessed, and it sits between two hard numbers:
##   FLOOR  — the worst drift any legitimate element colour suffers is FIRE lifted to
##            `Elements.emissive`, at 0.028. Anything at or below that would start
##            rejecting the game's own HDR cores.
##   CEILING— a neutral grey normalises to chroma (1,1,1) and its nearest element is
##            HOLY at 0.165. At the first-pass value of 0.30 that matched, so every
##            washed-out or near-white effect in the game was quietly labelled HOLY
##            and drew radiant-ray glyphs. That was a real mislabel, caught by
##            tools/slice_test_sigil.gd rather than by eye.
## 0.075 clears the drift with ~2.7x headroom and rejects grey with ~2.2x margin.
## A colour outside it is not guessed at: it falls through to `-1` and the sigil draws
## the generic runic ticks, which is the honest answer for "this is nobody's element".
const ELEMENT_MATCH_TOLERANCE: float = 0.075

## WHAT THE SPELL IS ABOUT TO DO, as one figure. See the MOTIF paragraph above.
##
## The vocabulary is chosen by CONSEQUENCE, not by spell name — that is what keeps it
## to thirteen entries instead of thirty-eight, and it is also what makes it useful:
## two different wall spells SHOULD open the same figure, because the thing you need
## to know about both of them is identical. Anything genuinely new that does not fit
## takes NONE and simply loses this one read; it never guesses.
enum Motif {
	NONE,      ## not told — draws nothing, exactly as before this existed
	DESCENT,   ## something falls onto this spot   (meteor, convergence, call-lightning)
	LANCE,     ## it goes THAT way, in a line      (beams, rays, bolts, rushes)
	BARRIER,   ## a line you cannot cross          (walls of any material)
	ERUPTION,  ## the ground comes UP here         (pillars, spikes, slams, boulders)
	ORBIT,     ## satellites that seek             (rune orbs, homing shards, missiles)
	PULSE,     ## a ring leaves this centre        (nova, shockwave, expanding fields)
	SNARE,     ## it reaches out and holds         (root, tether, chain, crawler)
	BLADE,     ## a cut lands                      (flurry, arc, blink strike, dagger)
	WARD,      ## a volume is claimed              (aegis, zone, consecrate)
	VOID,      ## it pulls in and unmakes          (collapse, hollow purple, petrify)
	SPIRAL,    ## the rules bend                   (chronostasis, gravity, equinox, roulette)
	SUMMON,    ## another body arrives             (mirror image, blood pact)
}

## Inner-court band the motif is drawn in, as fractions of `radius`. Bounded ABOVE by
## the HEAVY mechanism ring at 0.64 and BELOW by the core's swell (0.22 x up to 1.55
## at full charge = 0.34), so the figure has a lane of its own at every tier and does
## not collide with either even at maximum gather.
const MOTIF_INNER: float = 0.30
const MOTIF_OUTER: float = 0.62


# ---------------------------------------------------------------- CHARGE / SNAP
## THE GATHER AND THE RELEASE, which is the half of "casting is a process" the sigil
## was not carrying. Before this the ring simply grew in and then span at a constant
## look for the whole windup, so a 0.5 s channel and a 0.18 s flick were visually the
## same event at different lengths — nothing accumulated, and the moment of release
## was marked only by the circle starting to travel.
##
## Now: a gather ring contracts inward and the glyph band LIGHTS UP ONE GLYPH AT A
## TIME as the charge fills, so how far through the windup a caster is can be counted
## off the rim. At release the whole band is lit and `snap()` fires a hard flare that
## recoils the ring outward and decays — attack, sustain, release, with no frame where
## anything appears or vanishes instantly.
##
## Self-driving on purpose: `_charge` advances by itself from the moment the sigil
## appears, and `snap()` is fired from `_begin_handoff` (adoption IS the release).
## That means every existing caster gets the gather and the snap without one edit at a
## call site, including the ones this pass is not allowed to touch.
## How long the gather takes, as a multiple of the sigil's grow time. >1 so the band
## is still filling after the ring has finished materialising — the growth is the
## sigil arriving, the fill is the power arriving, and they must not be the same beat.
const CHARGE_TIME_FACTOR: float = 2.2
const CHARGE_TIME_MIN: float = 0.22
## Seconds the release flare takes to fall back to nothing.
const SNAP_DECAY: float = 0.28
## How far the ring recoils outward at full snap, as a fraction of radius.
const SNAP_RECOIL: float = 0.16

## ---- hand-off tuning -------------------------------------------------------
## UNTESTED GUESSES, every one: these are reasoning about how a ritual should
## flow, not numbers anybody has felt yet. Kept together so a playtest can retune
## the whole hand-off from one place.
##
## How long the adopted sigil takes to glide from where the windup hung it (over
## the caster's head) to the spell's muzzle, morphing radius/colour/orientation
## on the way. Chosen to land WELL INSIDE a spectacle's own charge window so the
## sigil is settled and spinning at the muzzle before the shot leaves — the
## travel should read as the ritual descending into the hand, never as the sigil
## still sliding when the beam fires.
const HANDOFF_TRAVEL_TIME: float = 0.2
## Ease curve for that glide. < 1 = ease-OUT: leaves fast, settles gently, which
## is the shape of something being PULLED into the hand.
const HANDOFF_EASE: float = 0.42
## How long an offer stays claimable, in milliseconds. Adoption happens in the
## SAME FRAME as the offer (caster fires -> SpellCaster spawns -> spectacle
## adopts), so this only has to survive a few frames of slack. Deliberately tiny:
## most spells open no sigil, so their offers go unclaimed on purpose, and a long
## TTL would leave those sigils hanging past the cast they belonged to.
const OFFER_TTL_MS: int = 60
## Fade an un-taken / withdrawn offer blooms out over — matched to the 0.2 s that
## every caster passed to vanish() before the seam existed, so a spell that does
## NOT adopt looks byte-for-byte like it did.
const OFFER_EXPIRE_FADE: float = 0.2

@export var color: Color = Color(0.95, 0.4, 0.85, 1.0)
@export var radius: float = 130.0

var _phase: float = 0.0
var _alpha: float = 0.0
var _scale: float = 0.35
var _grow_time: float = GROW_TIME_DEFAULT
var _growing: bool = false
var _vanishing: bool = false
var _vanish_time: float = 0.2
var _vanish_elapsed: float = 0.0
## Orientation: face-on disc (default) or an edge-on gate aligned to an axis.
var _edge_on: bool = false
var _edge_thick: float = 0.15  # x-extent of the edge-on lens as a fraction of radius
## THE THIRD ORIENTATION: a face-on sigil SQUASHED so it lies on the floor.
##
## A placed spell (a field, a ward, an erupting pillar) and a projected one (a bolt,
## a beam) must not summon out of the same picture — the spec's read is that a
## GROUND circle tells you where the ground is about to do something and a mid-air
## circle tells you where a thing is about to come FROM. The squash is the whole
## difference and it costs nothing: the node's own y-scale, so every arc, glyph and
## mote foreshortens together and the drawing needs no second code path.
##
## Kept as a target rather than applied once because the hand-off interpolates
## `scale`, and a ground sigil adopted from an upright windup must SETTLE onto the
## floor over the glide rather than snap flat on the frame it is claimed.
var _base_scale: Vector2 = Vector2.ONE

# ---- signature (see the SIGNATURE block above) ------------------------------
## Elements.Element, or -1 for "not told" -> generic runic ticks.
var _element: int = -1
## SpellTier.Tier, or -1 for "not told" -> inferred from radius at draw time.
var _tier: int = -1
## Set once anybody calls set_signature(), so an inference never overwrites a
## deliberate answer (and a re-`appear()` on a recycled node cannot un-tell it).
var _sig_explicit: bool = false
## The spell figure in the inner court. `Motif.NONE` draws nothing, so every caller
## that never heard of this is byte-for-byte unchanged.
var _motif: int = Motif.NONE

# ---- charge / snap ----------------------------------------------------------
var _charge: float = 0.0        # 0..1 gather, advances on its own from appear()
var _charge_time: float = CHARGE_TIME_MIN
var _snap: float = 0.0          # 1 -> 0 release flare
var _handed_off: bool = false   # released; the gather is finished, stop advancing it

# ---- level of detail --------------------------------------------------------
## MOBILE BUDGET. The face-on draw is the single most segment-hungry CanvasItem in
## the game — the full stack is ~600 line segments per circle per frame, and a busy
## fight can hold four of them (two windups + two muzzle gates). Cheap on a desktop
## GPU, not cheap on a tile GPU that re-transforms every vertex.
##
## Sampled ONCE, when the sigil opens, rather than per frame: the quality dial walks
## the scene tree to find the Tuning autoload, and doing that inside `_draw` would
## put a node lookup on the hottest path in the renderer. A sigil lives well under a
## second, so a mid-life quality change simply applies to the next cast.
##
## LOW drops the emanating pulse rings entirely (three full arcs, the purest
## decoration in the drawing), drops the ULT's inner square and the rim's white
## highlight ring, halves every arc's segment count, and thins the motes. What it
## deliberately KEEPS at full strength is the GLYPH BAND and the CHARGE FILL — those
## are the READ, and the point of the mobile picture is that it stays readable and
## fun rather than pretty. Counting the primitives an ULT face-on sigil issues, that
## is roughly 900 line segments down to roughly 375: a ~2.4x cut, and no new draw
## call, no new material, no screen-texture fetch at any quality.
## (A primitive COUNT, not a profiler measurement — nobody has run this on a phone.)
var _low: bool = false
## Sampled yet? The probe walks the scene tree, and `SceneTree.root` is not a legal
## `get_node` base until the tree is ACTIVE — a capture tool that builds its world in
## `_initialize` (which several in tools/ do) would otherwise take an engine error on
## every sigil it opened. Deferring to the first `_draw` sidesteps that entirely: by
## the time anything renders, the tree is always live.
var _low_sampled: bool = false

# ---- self-timed bloom-out (see `hold`) --------------------------------------
var _hold_left: float = -1.0
var _hold_fade: float = 0.26

# ---- hand-off state (see the seam doc at the top) ---------------------------
## Circles currently OFFERED for adoption: caster instance_id -> MagicCircle.
## A Dictionary rather than a single slot because co-op has two heroes who can
## release on the same frame, and a one-slot registry would let hero B's sigil be
## adopted by hero A's beam. Keyed by instance_id (an int) so a caster that frees
## itself mid-cast can never keep this alive.
static var _offers: Dictionary = {}
## Whose offer slot this instance sits in, or 0. Kept on the instance purely so
## _exit_tree can clear the registry without scanning it.
var _offer_caster_id: int = 0
## When this instance was offered, in engine ms; 0 = not offered. Drives the TTL
## self-clean, which is what stops a cast that nobody adopts (a wall, a nova, an
## interrupted windup) from leaving an orphaned sigil floating in the world.
var _offered_at_ms: int = 0
## Hand-off glide: interpolating position / radius / colour / orientation from
## where the windup left the sigil to where the spectacle wants it. Every field
## is a FROM value captured at adoption; the TO values are the spectacle's.
var _ho_active: bool = false
var _ho_elapsed: float = 0.0
var _ho_time: float = HANDOFF_TRAVEL_TIME
var _ho_from_pos: Vector2 = Vector2.ZERO
var _ho_to_pos: Vector2 = Vector2.ZERO
var _ho_from_scale: Vector2 = Vector2.ONE
var _ho_from_radius: float = 0.0
var _ho_to_radius: float = 0.0
var _ho_from_color: Color = Color.WHITE
var _ho_to_color: Color = Color.WHITE
var _ho_from_rot: float = 0.0
var _ho_to_rot: float = 0.0
var _ho_from_thick: float = 0.15
var _ho_to_thick: float = 0.15
## Rotation is NOT interpolated when the sigil is round at the start of the glide
## (a face-on disc, or an edge-on gate opened to full thickness): with ex == ey
## the drawing is rotationally symmetric, so the angle can be snapped invisibly
## and lerping it would only risk the long way round.
var _ho_snap_rot: bool = false
## Deferred face-on flip: going edge-on -> face-on, the gate OPENS to full
## roundness first and only becomes a face-on disc at the end of the glide. The
## flip is invisible because both draws are round at that instant.
var _ho_flip_to_face: bool = false


func appear(circle_color: Color, circle_radius: float, grow_time: float = GROW_TIME_DEFAULT) -> void:
	color = circle_color
	radius = circle_radius
	_grow_time = maxf(grow_time, 0.01)
	_growing = true
	_alpha = 0.0
	_scale = 0.35
	_charge = 0.0
	_snap = 0.0
	_handed_off = false
	_charge_time = maxf(_grow_time * CHARGE_TIME_FACTOR, CHARGE_TIME_MIN)
	_low_sampled = false
	# THE FREE UPGRADE. A caster that never heard of the signature API still passes a
	# colour, and a colour is very nearly an element already — so recognise it. This
	# is what gives Hero's windup sigil a fire band when the hero is casting fire,
	# from a file this pass does not touch. Unrecognised colours stay at -1 and draw
	# the original generic runes, so nothing regresses to a wrong answer.
	if not _sig_explicit:
		_element = _infer_element(circle_color)
	queue_redraw()


## Tell the sigil WHICH SPELL it belongs to. `element` is an `Elements.Element`
## (or -1 for none), `tier` a `SpellTier.Tier` (or -1 to keep inferring from
## radius). Overrides colour inference permanently for this instance — an explicit
## answer must survive the re-colour a hand-off performs.
func set_signature(element: int, tier: int = -1) -> void:
	_element = element
	_tier = tier
	_sig_explicit = true
	queue_redraw()


## Tell the sigil WHAT THE SPELL DOES — the third signature axis, alongside element
## and tier. A `Motif` value; `Motif.NONE` clears it. Survives a hand-off re-colour
## for the same reason `set_signature` does: a stated answer is the last word.
func set_motif(motif: int) -> void:
	_motif = motif if motif > Motif.NONE and motif <= Motif.SUMMON else Motif.NONE
	queue_redraw()


## The motif this sigil is drawing. Public so a headless test can assert the third
## axis without rendering a frame — same reason `effective_tier()` is public.
func motif() -> int:
	return _motif


## Make the glyph band fill over EXACTLY `seconds` instead of the default derived
## from the grow time.
##
## Exists because the fill is a PROMISE: the band lighting one glyph at a time is
## how an opponent counts how long they have left, so a sigil whose band is half lit
## when the spell fires has lied to them. The default (`grow x 2.2`) is right for a
## sigil handed off at the end of a caster's windup, and wrong for a spectacle that
## holds its own gather for a duration only it knows — `EnergyNova` is the first, and
## any future charge-then-release spell is the next. Clamped above `CHARGE_TIME_MIN`
## so a zero can never produce a divide-by-zero in `_process`.
##
## ⚠ CALL IT AFTER `SpellSigil.open()`. `appear()` recomputes `_charge_time` from the
## grow time, so a call made before the sigil is opened is silently discarded.
func set_charge_time(seconds: float) -> void:
	_charge_time = maxf(seconds, 0.01)


## The tier this sigil is drawing at, resolved. Public so a spectacle can ask what
## it is going to get before it decides on a radius, and so a headless test can
## assert the ladder without rendering a frame.
func effective_tier() -> int:
	if _tier >= 0:
		return _tier
	if radius < TIER_RADIUS_QUICK:
		return SpellTier.Tier.QUICK
	if radius < TIER_RADIUS_HEAVY:
		return SpellTier.Tier.HEAVY
	return SpellTier.Tier.ULT


## Glyphs in the rim band for the resolved tier — the tier ladder's whole visible
## expression on the rim, and what makes "this is an ult" countable rather than
## merely brighter.
func glyph_count() -> int:
	match effective_tier():
		SpellTier.Tier.ULT:
			return GLYPHS_ULT
		SpellTier.Tier.HEAVY:
			return GLYPHS_HEAVY
	return GLYPHS_QUICK


## Nearest `Elements.Element` to `c`, or -1 when nothing is close enough. Compares
## HUE-NORMALISED colour: the same element arrives at wildly different brightnesses
## across the codebase (`Elements.color` for telegraphs, `Elements.emissive` — up to
## 1.9 per channel — for cores, plus per-spell tints), so raw RGB distance would
## match almost nothing. Normalising by the brightest channel throws the intensity
## away and compares the chroma, which is the part that identifies the element.
static func _infer_element(c: Color) -> int:
	var best: int = -1
	var best_d: float = ELEMENT_MATCH_TOLERANCE
	var want: Vector3 = _chroma(c)
	for e: int in Elements.count():
		var d: float = want.distance_squared_to(_chroma(Elements.color(e)))
		if d < best_d:
			best_d = d
			best = e
	return best


## A colour reduced to its chroma: divided through by its brightest channel, so
## Color(1.0, 0.45, 0.15) and Color(1.9, 0.86, 0.29) are the same point.
static func _chroma(c: Color) -> Vector3:
	var peak: float = maxf(c.r, maxf(c.g, c.b))
	if peak <= 0.001:
		return Vector3.ZERO
	return Vector3(c.r / peak, c.g / peak, c.b / peak)


## Bloom out on a timer instead of waiting to be told. THE ANTI-POP: most spell
## spectacles are short-lived nodes that `queue_free()` themselves, and a sigil
## parented to one disappears on the frame its parent does — an instant vanish at
## full opacity, which is exactly the kind of hard cut this pass exists to remove.
## Giving the sigil its own shorter life means it always leaves by blooming.
##
## `seconds` counts from now and runs on unscaled `_process` delta like everything
## else here; a later call replaces an earlier one rather than stacking.
func hold(seconds: float, fade: float = 0.26) -> void:
	_hold_left = maxf(seconds, 0.0)
	_hold_fade = maxf(fade, 0.01)


## Lay this sigil DOWN on the floor. `squash` is the y-scale it settles to — ~0.34
## reads as a circle inscribed on the ground under a side-on camera, 1.0 stands it
## back up. See `_base_scale` for why this is a target and not an assignment.
func set_ground(squash: float = 0.34) -> void:
	_base_scale = Vector2(1.0, clampf(squash, 0.05, 1.0))
	if not _ho_active:
		scale = _base_scale
	queue_redraw()


## Fire the RELEASE flare. Called automatically at adoption (adoption is the moment
## the spell fires), and available to any spectacle that wants to punctuate a beat
## on a sigil it already owns. `strength` scales the recoil and the flash.
func snap(strength: float = 1.0) -> void:
	_snap = clampf(strength, 0.0, 1.5)
	_charge = 1.0
	_handed_off = true
	queue_redraw()


## Orient the sigil. `edge_on` true = a thin gate seen from the side, aligned so
## `axis_dir` (the beam direction) passes through its centre; the node rotates so
## the gate is perpendicular to the beam. false = a full face-on circle.
func set_orientation(edge_on: bool, axis_dir: Vector2 = Vector2.RIGHT, thickness: float = 0.15) -> void:
	_edge_on = edge_on
	_edge_thick = clampf(thickness, 0.04, 0.5)
	rotation = axis_dir.angle() if edge_on and axis_dir != Vector2.ZERO else 0.0
	queue_redraw()


# ========================= HAND-OFF SEAM: CASTER SIDE ========================

## Offer this caster's live windup sigil to whatever spectacle the cast is about
## to spawn. Call this INSTEAD of vanish() at the moment the spell actually fires
## — and only on the success path; an interrupted windup should still vanish (or
## shatter) as it always did.
##
## Safe to call for spells that open no sigil of their own: an offer nobody
## claims within OFFER_TTL_MS blooms itself out, which is exactly the vanish()
## it replaced, just a few frames later.
static func offer(circle: MagicCircle, caster: Node) -> void:
	if circle == null or not is_instance_valid(circle) or caster == null:
		return
	if circle._vanishing:
		return  # already dying — offering it would hand over a corpse
	var id: int = caster.get_instance_id()
	# A caster with a stale offer still pending (a cast that spawned nothing,
	# fired again inside the TTL) must not leak the first sigil.
	_expire_offer(id)
	_offers[id] = circle
	circle._offer_caster_id = id
	circle._offered_at_ms = Time.get_ticks_msec()


## Cancel an un-taken offer from `caster` and bloom the sigil out now. Call from
## every interruption path — windup cancelled, caster hit, caster died, co-op
## down — so a shattered cast can never leave a sigil hanging in the world. A
## no-op if the offer was already adopted, so it is safe to call unconditionally.
static func withdraw(caster: Node) -> void:
	if caster == null:
		return
	_expire_offer(caster.get_instance_id())


## Internal: drop `id`'s offer and bloom its circle out if it is still alive.
static func _expire_offer(id: int) -> void:
	var c: Variant = _offers.get(id)
	_offers.erase(id)
	if c is MagicCircle and is_instance_valid(c):
		(c as MagicCircle)._offer_caster_id = 0
		(c as MagicCircle)._offered_at_ms = 0
		(c as MagicCircle).vanish(OFFER_EXPIRE_FADE)


# ======================= HAND-OFF SEAM: SPECTACLE SIDE =======================

## THE ONE LINE every spectacle needs. Adopt the caster's windup sigil if one is
## on offer — reparenting it under `host`, gliding it to `world_pos` and morphing
## it to this spell's colour/radius/orientation while its spin and phase run on
## unbroken — otherwise construct a fresh one and appear() it exactly as before.
##
## `world_pos` is WORLD space (the muzzle / focus). Spectacles park at the arena
## origin and draw in world coordinates, so passing anything derived from the
## host's transform would put the sigil at the top-left of the arena — see the
## coordinate-trap note in the class doc.
##
## `caster` may be null: with no identity to match, an offer is still adopted if
## exactly ONE is pending (the overwhelmingly common single-caster case), and
## declined if several are, because guessing wrong in co-op would steal the other
## player's sigil. Declining just means a fresh circle — never a missing one.
static func adopt_or_open(
	host: Node,
	caster: Node,
	world_pos: Vector2,
	circle_color: Color,
	circle_radius: float,
	grow_time: float = GROW_TIME_DEFAULT,
	edge_on: bool = false,
	axis_dir: Vector2 = Vector2.RIGHT,
	thickness: float = 0.15,
	travel_time: float = HANDOFF_TRAVEL_TIME,
) -> MagicCircle:
	var adopted: MagicCircle = _take(caster)
	if adopted != null and host != null and host.is_inside_tree():
		# keep_global_transform: the sigil must not jump when it crosses from the
		# caster's transform into a spectacle parked at (0, 0).
		adopted.reparent(host, true)
		adopted._begin_handoff(world_pos, circle_color, circle_radius,
			edge_on, axis_dir, thickness, travel_time)
		return adopted
	if adopted != null:
		# Host not in the tree yet — cannot reparent, so let the offer die its
		# normal death rather than stranding it half-handed-over.
		adopted.vanish(OFFER_EXPIRE_FADE)
	var fresh: MagicCircle = MagicCircle.new()
	host.add_child(fresh)
	fresh.global_position = world_pos
	fresh.appear(circle_color, circle_radius, grow_time)
	fresh.set_orientation(edge_on, axis_dir, thickness)
	return fresh


## Internal: claim `caster`'s pending offer, or the single pending offer when
## `caster` is null. Returns null when there is nothing safe to claim.
static func _take(caster: Node) -> MagicCircle:
	_sweep_offers()
	var id: int = 0
	if caster != null:
		id = caster.get_instance_id()
		if not _offers.has(id):
			return null
	elif _offers.size() == 1:
		id = int(_offers.keys()[0])
	else:
		return null
	var c: Variant = _offers.get(id)
	_offers.erase(id)
	if not (c is MagicCircle) or not is_instance_valid(c):
		return null
	var circle: MagicCircle = c as MagicCircle
	# Cleared BEFORE the reparent: reparent() fires _exit_tree, which clears the
	# registry, and we must not have it clear a slot we have already claimed.
	circle._offer_caster_id = 0
	circle._offered_at_ms = 0
	return circle


## Internal: drop registry entries whose circle has been freed. Cheap (the
## dictionary holds at most one entry per live caster) and it keeps a null-caster
## adoption honest — a stale corpse must not count toward "exactly one pending".
static func _sweep_offers() -> void:
	for id: Variant in _offers.keys():
		var c: Variant = _offers[id]
		if not (c is MagicCircle) or not is_instance_valid(c):
			_offers.erase(id)


## Internal: start the glide from wherever the windup left this sigil to the
## spectacle's muzzle. Deliberately does NOT touch `_phase` — the spin and the
## breathing carry straight through, which is the whole point of adopting rather
## than rebuilding.
func _begin_handoff(
	world_pos: Vector2, new_color: Color, new_radius: float,
	edge_on: bool, axis_dir: Vector2, thickness: float, travel_time: float,
) -> void:
	# The ritual is at FULL power at the moment of release: cancel any residual
	# grow-in, and defensively cancel a vanish (offer() refuses vanishing circles,
	# but a spectacle could be handed one by some future caller).
	_growing = false
	_vanishing = false
	_alpha = 1.0
	_scale = 1.0
	# ADOPTION IS THE RELEASE. The spell exists as of this instant, so the gather is
	# complete and the flare fires here rather than at some later "the beam actually
	# left" moment — a sigil that snapped after the projectile had already gone would
	# read as a second, unrelated event.
	snap(1.0)
	# A hand-off re-tints the sigil to the spell's colour. If nobody stated the
	# element outright, re-read it from the colour the spell is arriving with — the
	# spectacle's tint is a better answer than the caster's was.
	if not _sig_explicit:
		_element = _infer_element(new_color)
	_ho_active = true
	_ho_elapsed = 0.0
	_ho_time = maxf(travel_time, 0.001)
	_ho_from_pos = global_position
	_ho_to_pos = world_pos
	# The caster scales the NODE while the sigil charges (it grows as it gathers);
	# the spectacle owns the radius instead, so the node scale eases back to 1.
	_ho_from_scale = scale
	_ho_from_radius = radius
	_ho_to_radius = maxf(new_radius, 1.0)
	_ho_from_color = color
	_ho_to_color = new_color
	_ho_from_thick = _edge_thick
	_ho_to_thick = clampf(thickness, 0.04, 1.0)
	_ho_from_rot = rotation
	_ho_to_rot = axis_dir.angle() if edge_on and axis_dir != Vector2.ZERO else 0.0
	_ho_snap_rot = false
	_ho_flip_to_face = false
	# ORIENTATION WITHOUT A FLICKER. A hard switch between the two draw routines
	# would read as a SECOND glitch, so a mode change is animated as the sigil
	# TURNING: an edge-on gate at thickness 1.0 is round, which is the same
	# silhouette a face-on disc presents, so that roundness is the hinge both
	# directions pivot through.
	if _edge_on != edge_on:
		if edge_on:
			# Face-on disc -> edge-on gate: become edge-on immediately but fully
			# ROUND, then FOLD closed to the target thickness. Reads as the disc
			# swinging round to face the target. Rotation can be snapped now
			# because a round gate draws identically at any angle.
			_edge_on = true
			_ho_from_thick = 1.0
			_edge_thick = 1.0
			rotation = _ho_to_rot
			_ho_snap_rot = true
		else:
			# Edge-on gate -> face-on disc: OPEN to round over the glide, then
			# flip the draw at the end, where the two are indistinguishable.
			_ho_to_thick = 1.0
			_ho_flip_to_face = true
			_ho_snap_rot = true
	queue_redraw()


## Per-frame hand-off glide. Split out of _process so the ordering is explicit:
## this runs BEFORE the grow/vanish block, so a circle consumed by a reaction
## mid-glide still dissolves normally on top of wherever the glide had it.
func _process_handoff(delta: float) -> void:
	_ho_elapsed += delta
	var t: float = clampf(_ho_elapsed / _ho_time, 0.0, 1.0)
	var e: float = ease(t, HANDOFF_EASE)
	global_position = _ho_from_pos.lerp(_ho_to_pos, e)
	scale = _ho_from_scale.lerp(_base_scale, e)
	radius = lerpf(_ho_from_radius, _ho_to_radius, e)
	color = _ho_from_color.lerp(_ho_to_color, e)
	_edge_thick = lerpf(_ho_from_thick, _ho_to_thick, e)
	if not _ho_snap_rot:
		# lerp_angle, not lerpf: an aim that crosses ±PI between the windup and
		# the release must take the SHORT way round, or the gate spins wildly.
		rotation = lerp_angle(_ho_from_rot, _ho_to_rot, e)
	if t >= 1.0:
		_ho_active = false
		if _ho_flip_to_face:
			_edge_on = false
			rotation = 0.0


func vanish(fade_time: float = 0.2) -> void:
	if _vanishing:
		return
	_vanishing = true
	_growing = false
	_vanish_time = maxf(fade_time, 0.01)
	_vanish_elapsed = 0.0


## Registry hygiene. reparent() fires this too, but _take() clears the slot
## before it reparents, so an adoption never trips over its own hand-off; this
## only ever fires for a sigil that leaves the tree while STILL on offer.
func _exit_tree() -> void:
	if _offer_caster_id != 0 and _offers.get(_offer_caster_id) == self:
		_offers.erase(_offer_caster_id)
	_offer_caster_id = 0
	_offered_at_ms = 0


func _process(delta: float) -> void:
	_phase += delta
	if _ho_active:
		_process_handoff(delta)
	# TTL self-clean. THE INTERRUPTION SAFETY NET: a caster who offers and then
	# spawns nothing — a wall, a nova, a windup shattered by a hit, a caster who
	# died on the release frame — leaves this sigil unclaimed, and without this it
	# would hang in the world forever. Adoption happens the same frame as the
	# offer, so anything still pending after OFFER_TTL_MS is never coming.
	if _offered_at_ms != 0 and Time.get_ticks_msec() - _offered_at_ms > OFFER_TTL_MS:
		_expire_offer(_offer_caster_id)
	# THE GATHER, advancing on its own. Stops at the release so the band stays lit
	# under the flare instead of continuing to fill something already spent.
	if not _handed_off and not _vanishing:
		_charge = minf(_charge + delta / _charge_time, 1.0)
	# THE RELEASE, falling back to nothing. Never cut off — a snap that ended on a
	# hard frame would undo the whole reason this exists.
	if _snap > 0.0:
		_snap = maxf(_snap - delta / SNAP_DECAY, 0.0)
	if _hold_left >= 0.0 and not _vanishing:
		_hold_left -= delta
		if _hold_left <= 0.0:
			_hold_left = -1.0
			vanish(_hold_fade)
	if _growing:
		_alpha = minf(_alpha + delta / _grow_time, 1.0)
		var e: float = ease(_alpha, 0.4)
		# SMOOTH. This used to be `lerpf(0.35, 1.08, ...)` followed by a hard
		# `_scale = 1.0` on the frame the growth completed — a 7% snap-down on one
		# frame, at full opacity, on every single cast in the game. It read as a
		# flicker, and it was the most-repeated pop in the whole VFX layer.
		#
		# The replacement is C0-continuous at both ends BY CONSTRUCTION: the first
		# term is 0.35 at e=0 and exactly 1.0 at e=1, and the overshoot term is a
		# half-sine that is zero at both ends. So the ring still punches past its
		# target (peaking ~1.03 around e=0.8, which is the life in it) and then
		# SETTLES into 1.0 rather than being yanked there.
		_scale = 1.0 - 0.65 * pow(1.0 - e, 1.8) + 0.11 * sin(PI * e)
		if _alpha >= 1.0:
			_scale = 1.0
			_growing = false
	if _vanishing:
		_vanish_elapsed += delta
		var v: float = clampf(_vanish_elapsed / _vanish_time, 0.0, 1.0)
		# Hold bright, then fall away fast — a bloom, not a dimmer. Linear alpha made
		# every dismissal read as the sigil being switched off half-way through.
		_alpha = 1.0 - v * v
		_scale = lerpf(1.0, 1.5, ease(v, 0.6))
		if v >= 1.0:
			queue_free()
			return
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	if not _low_sampled:
		_low_sampled = true
		_low = TuningConfig.quality_is_low()
	_work_sigils += 1
	if _edge_on:
		_draw_edge()
	else:
		_draw_face()


# -------------------------------------------------------------- EDGE-ON (beams)
## A thin gate seen from the side (local +x = beam axis after the node rotation;
## the gate spans local y). The beam bursts through the centre along +x.
func _draw_edge() -> void:
	var a: float = _alpha
	var c: Color = color
	var s: float = _scale
	var R: float = radius * s
	var ex: float = maxf(R * _edge_thick, 3.0)   # half-thickness (along the beam)
	var ring: Color = Color(c.r, c.g, c.b, 0.9 * a)
	var soft: Color = Color(c.r, c.g, c.b, 0.5 * a)
	var white: Color = Color(1.7, 1.7, 1.8, a)  # HDR aperture/core blooms
	var breath: float = 1.0 + 0.04 * sin(_phase * 4.0)
	var tier: int = effective_tier()

	# Emanating edge-on ripples, expanding along the gate.
	if not _low:
		for i: int in PULSE_RINGS:
			var t: float = fposmod(_phase * 0.55 + float(i) / float(PULSE_RINGS), 1.0)
			var k: float = 0.75 + t * 0.9
			draw_polyline(_ellipse_pts(ex * k, R * k, _seg(48, R * k)), Color(c.r, c.g, c.b, (1.0 - t) * 0.2 * a), 2.0, true)

	# The ULT summoning band, edge-on: a second gate standing outside the first. Same
	# "an ult changes the OUTLINE" rule as the face-on draw.
	if tier >= SpellTier.Tier.ULT:
		draw_polyline(_ellipse_pts(ex * 1.5, R * 1.18, _seg(48, R * 1.18)), Color(c.r, c.g, c.b, 0.4 * a), 2.0, true)

	# Nested edge-on rings.
	draw_polyline(_ellipse_pts(ex * breath, R * breath, _seg(56, R * breath)), ring, 3.0, true)
	draw_polyline(_ellipse_pts(ex * 0.72 * breath, R * 0.72 * breath, _seg(48, R * 0.72 * breath)), soft, 2.0, true)
	if tier >= SpellTier.Tier.HEAVY:
		draw_polyline(_ellipse_pts(ex * 0.46, R * 0.46, _seg(40, R * 0.46)), soft, 1.5, true)

	# Rim glyphs orbiting the edge-on ring — foreshortened, brighter at the front.
	var motes: int = MOTES if not _low else 3
	_work_blobs += motes * 2 + 2          # rim motes (2 each) + the hot core pair
	for i: int in motes:
		var th: float = _phase * 1.6 + TAU * float(i) / float(motes)
		var pos: Vector2 = Vector2(ex * cos(th), R * 0.94 * sin(th))
		var depth: float = 0.45 + 0.55 * (0.5 + 0.5 * cos(th))  # front (cos>0) bigger/brighter
		var ma: float = clampf(0.35 + 0.5 * depth, 0.12, 1.0) * a
		draw_circle(pos, maxf(2.0, R * 0.03) * depth, Color(c.r, c.g, c.b, ma * 0.5), true, -1.0, true)
		draw_circle(pos, maxf(1.2, R * 0.02) * depth, Color(1.0, 1.0, 1.0, ma), true, -1.0, true)

	# THE ELEMENT BAND, foreshortened onto the gate's rim. Same glyphs as the face-on
	# sigil and the same progressive lighting, so a beam's muzzle gate and the windup
	# circle it was adopted FROM are recognisably the same ritual seen from two
	# angles — which is the entire premise of the hand-off.
	var gn: int = glyph_count()
	for i: int in gn:
		var f: float = float(i) / float(gn)
		var th2: float = _phase * 1.6 + TAU * f
		var at: Vector2 = Vector2(ex * 1.25 * cos(th2), R * 1.02 * sin(th2))
		var depth2: float = 0.45 + 0.55 * (0.5 + 0.5 * cos(th2))
		var on: bool = f <= _charge + 0.0001
		var gcol: Color = Color(c.r * 1.35, c.g * 1.35, c.b * 1.35, 0.9 * a * depth2) if on \
			else Color(c.r, c.g, c.b, 0.28 * a * depth2)
		if _element < 0:
			# Unset element: the original plain radial tick, unchanged.
			draw_line(Vector2(ex * cos(th2), R * sin(th2)),
				Vector2(ex * 1.7 * cos(th2), R * 1.07 * sin(th2)), gcol, 1.5, true)
		else:
			# `sin(th2)` is the position ALONG the gate, so the outward normal at that
			# point is straight up or down the gate — not radial. Using the radial angle
			# here would have every glyph pointing at the centre of a lens it is sitting
			# on the edge of, which reads as debris rather than inscription.
			_draw_glyph(at, PI * 0.5 if sin(th2) >= 0.0 else -PI * 0.5,
				maxf(R * 0.20, 3.0) * depth2, gcol, on)

	# Central APERTURE — the bright slit the beam bursts from (pulses, and swells with
	# the gather so the gate is visibly loading before it fires).
	var pulse: float = (0.8 + 0.2 * sin(_phase * 8.0)) * (1.0 + 0.35 * _charge + 0.7 * _snap)
	draw_line(Vector2(0.0, -R * 0.62), Vector2(0.0, R * 0.62), Color(c.r, c.g, c.b, 0.55 * a), maxf(3.0, ex * 1.3) * pulse, true)
	draw_line(Vector2(0.0, -R * 0.5), Vector2(0.0, R * 0.5), white, maxf(1.5, ex * 0.5) * pulse, true)
	# Hot core.
	draw_circle(Vector2.ZERO, R * 0.12 * pulse, Color(c.r, c.g, c.b, 0.3 * a), true, -1.0, true)
	draw_circle(Vector2.ZERO, R * 0.07 * pulse, white, true, -1.0, true)

	# The release flare, as an expanding GATE rather than a circle.
	if _snap > 0.001:
		var k2: float = 1.0 - _snap
		var fs: float = 1.0 + 0.7 * ease(k2, 0.4)
		var fa: float = _snap * _snap * a
		var flare_pts: PackedVector2Array = _ellipse_pts(ex * fs, R * fs, _seg(48, R * fs))
		# ONE point array for both passes. The bright core is the same ellipse as the
		# body of the flare, and building it twice built identical geometry twice.
		draw_polyline(flare_pts, Color(c.r, c.g, c.b, 0.85 * fa), 3.0 + 5.0 * _snap, true)
		draw_polyline(flare_pts, Color(1.6, 1.6, 1.7, 0.6 * fa), 1.5 + 2.0 * _snap, true)


## A closed ellipse polyline with x half-extent `ex`, y half-extent `ey`.
func _ellipse_pts(ex: float, ey: float, n: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n + 1:
		var t: float = TAU * float(i) / float(n)
		pts.append(Vector2(ex * cos(t), ey * sin(t)))
	return pts


# ------------------------------------------------------------ FACE-ON (portals)
## Drawn as FOUR readable layers, outermost first, each gated by the tier ladder so
## a QUICK jab and an ULT are different DRAWINGS rather than the same drawing at
## different sizes:
##   1. summoning ring   (ULT only)   the outer band that says "this is the big one"
##   2. the rim          (all tiers)  main ring + dashed ring + the ELEMENT GLYPH BAND
##   3. the mechanism    (HEAVY+)     counter-rotating spokes, hexagram, square
##   4. the heart        (all tiers)  gather ring, motes, core, release flare
func _draw_face() -> void:
	var a: float = _alpha
	var c: Color = color
	var s: float = _scale
	var tier: int = effective_tier()
	var heavy: bool = tier >= SpellTier.Tier.HEAVY
	var ult: bool = tier >= SpellTier.Tier.ULT
	# The release RECOIL: the whole rim kicks outward on the snap and eases back in
	# as the flare decays, so the moment of firing is felt in the ring itself and not
	# only in the flash laid over it.
	var recoil: float = 1.0 + SNAP_RECOIL * _snap
	var R: float = radius * s * recoil
	var ring: Color = Color(c.r, c.g, c.b, 0.9 * a)
	var soft: Color = Color(c.r, c.g, c.b, 0.5 * a)
	var white: Color = Color(1.7, 1.7, 1.8, a)  # HDR aperture/core blooms
	var breath: float = 1.0 + 0.03 * sin(_phase * 4.0)
	var seg: int = _seg(84, radius * s * breath * recoil)

	# --- 1. pulse rings + the ULT summoning band ----------------------------
	if not _low:
		for i: int in PULSE_RINGS:
			var t: float = fposmod(_phase * 0.55 + float(i) / float(PULSE_RINGS), 1.0)
			var rr: float = R * (0.75 + t * 0.9)
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, _seg(60, rr), Color(c.r, c.g, c.b, (1.0 - t) * 0.22 * a), 2.0, true)
	if ult:
		# A second, WIDER ring outside the main one, spinning the other way. This is
		# the single clearest "an ult is being cast" read available before the spell
		# exists, because it changes the sigil's OUTLINE rather than its brightness —
		# and an outline survives a busy screen where brightness does not.
		draw_arc(Vector2.ZERO, R * 1.20, 0.0, TAU, _seg(72, R * 1.20), Color(c.r, c.g, c.b, 0.42 * a), 2.0, true)
		draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.45, Vector2.ONE)
		_draw_dashed_ring(radius * s * recoil * 1.13, _dashes(), 0.32,
			Color(c.r, c.g, c.b, 0.5 * a), 2.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- 2. the rim: main ring, dashed ring, ELEMENT GLYPH BAND -------------
	draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED, Vector2(s, s) * breath * recoil)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, seg, ring, 3.5, true)
	if not _low:
		draw_arc(Vector2.ZERO, radius * 0.965, 0.0, TAU, seg, Color(1, 1, 1, 0.2 * a), 1.5, true)
	_draw_dashed_ring(radius * 0.88, _dashes(), 0.55, Color(c.r, c.g, c.b, 0.75 * a), 3.0)
	_draw_glyph_band(radius * 0.76, glyph_count(), a, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- 3. the mechanism: only spells that cost you get moving parts -------
	#
	# ⚠ THE MECHANISM YIELDS TO THE MOTIF, and this is the one place the three
	# signature axes actually compete for pixels. The hexagram sits at 0.55 R and the
	# spokes span 0.34-0.60 — dead centre of the motif's lane. Rendered together the
	# first time, a DESCENT sigil and a motif-less one were indistinguishable: the
	# six-pointed star is a much louder shape than three chevrons and it simply won.
	#
	# So when a spell has something to SAY, the generic furniture gets out of its way:
	# the hexagram is dropped and the spokes retract to a short collar at the rim.
	# Nothing is lost by it — the hexagram never carried information. "This is a
	# HEAVY" is already said, twice, by the mechanism ring being present at all and by
	# the glyph count on the band. The star was texture, and the motif is meaning.
	#
	# A sigil with NO motif is byte-identical to before, which is what keeps this a
	# strictly-additive change for the ~7 spectacles the table does not cover and for
	# every hand-opened circle in the game.
	var yields_to_motif: bool = _motif != Motif.NONE
	if heavy:
		draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.7, Vector2(s, s) * breath)
		draw_arc(Vector2.ZERO, radius * 0.64, 0.0, TAU, _seg(60, radius * 0.64 * s * breath), soft, 2.0, true)
		var spoke_in: float = radius * (0.56 if yields_to_motif else 0.34)
		for i: int in SPOKES:
			var sd: Vector2 = Vector2.from_angle(TAU * float(i) / float(SPOKES))
			draw_line(sd * spoke_in, sd * radius * 0.63, Color(c.r, c.g, c.b, 0.4 * a), 1.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		if not yields_to_motif:
			draw_set_transform(Vector2.ZERO, _phase * SPIN_SPEED * 0.35, Vector2(s, s))
			_draw_star(radius * 0.55, 3, 0.0, ring)
			_draw_star(radius * 0.55, 3, PI / 3.0, ring)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# The ULT's four-point star lands at 0.4 R, also inside the motif's lane — same
	# ruling, same reason.
	if ult and not _low and not yields_to_motif:
		draw_set_transform(Vector2.ZERO, -_phase * SPIN_SPEED * 0.5, Vector2(s, s))
		_draw_star(radius * 0.4, 4, PI / 4.0, soft)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- 3b. THE MOTIF: which spell is this? --------------------------------
	# Drawn in the sigil's UNROTATED frame on purpose. Everything above this spins,
	# and a figure that means "that way" or "a line across here" is destroyed by
	# spin — a rotating arrow points everywhere. The still figure inside moving
	# rings is also the strongest possible contrast: the eye goes to the one thing
	# holding position.
	_draw_motif(radius * s * breath, a, c)

	# --- 4. the heart: gather ring, motes, core, release flare --------------
	_draw_gather_ring(R, a, c)

	var motes: int = MOTES if not _low else 3
	_work_blobs += motes * 2 + 2          # orbiting motes (2 each) + core fill/white
	for i: int in motes:
		var ang: float = _phase * 1.5 + TAU * float(i) / float(motes)
		var pos: Vector2 = Vector2.from_angle(ang) * R * 0.72
		var ma: float = clampf(0.55 + 0.35 * sin(_phase * 5.0 + float(i) * 1.6), 0.15, 1.0) * a
		draw_circle(pos, maxf(2.0, radius * 0.03), Color(c.r, c.g, c.b, ma * 0.4), true, -1.0, true)
		draw_circle(pos, maxf(1.2, radius * 0.018), Color(1, 1, 1, ma), true, -1.0, true)

	# The core swells with the gather so the middle of the sigil is filling too, not
	# only the rim — a ring that lights up around a dead centre reads as a dial.
	var pulse: float = 0.82 + 0.18 * sin(_phase * 7.5)
	var swell: float = 1.0 + 0.55 * _charge + 0.9 * _snap
	draw_circle(Vector2.ZERO, radius * 0.22 * s * pulse * swell, Color(c.r, c.g, c.b, 0.28 * a), true, -1.0, true)
	draw_arc(Vector2.ZERO, radius * 0.15 * s * swell, 0.0, TAU, _seg(28, radius * 0.15 * s * swell), ring, 2.0, true)
	draw_circle(Vector2.ZERO, radius * 0.09 * s * pulse * swell, white, true, -1.0, true)

	_draw_snap_flare(R, a, c)


# ------------------------------------------------------- shared sigil furniture
## THE TESSELLATION BUDGET, stated as a VISUAL ERROR rather than as a segment
## count or a chord length.
##
## A polyline circle deviates from the true circle by its sagitta — the gap at the
## middle of each chord — and that is the only thing an eye can actually see. Fixing
## the SEGMENT COUNT (what this file did) over-tessellates small rings absurdly and
## under-tessellates big ones; fixing the CHORD LENGTH is better but still lets the
## error grow as rings shrink. Fixing the SAGITTA makes every ring in the game wrong
## by the same invisible amount, which is the correct invariant.
##
## 0.25 px is a quarter of one pixel at native resolution — a quarter of the width
## of the thinnest line here, on a game that ships with MSAA on precisely because
## its fighters are drawn as procedural lines. Doubling it to 0.5 would still be
## sub-pixel; a quarter is chosen so that the sigil looks identical even when the
## camera pulls in and the effective radius grows past what these numbers assume.
const MAX_SAGITTA_PX: float = 0.25
## Never below this, however small the ring: a heptagon reads as a shape rather
## than a circle, and the sigil's job is to be recognised instantly.
const MIN_SEGMENTS: int = 12

## Arc segment count for this sigil's level of detail. One place so a future
## quality tier is a change to this function and nothing else.
##
## ⚠ `r` IS THE ARC'S ACTUAL RADIUS, AND PASSING IT IS THE SINGLE BIGGEST SAVING IN
## THIS FILE. Measured: `MagicCircle` is **87.9% of all spell-spectacle `_draw`
## cost** in the roster (`tools/profile_spectacles.gd`) — it opens on 31 of 38
## spells, so it is a tax on nearly every cast rather than one expensive spell.
##
## The cost is dominated by the NUMBER OF LINE SEGMENTS the draw commands carry,
## and this function used to return a flat 84 (or 60, or 52) regardless of how big
## the ring being drawn was. Hero's windup sigil sizes itself ~17-34 px, so the main
## rim was being tessellated at **one segment every 1.5 px** — geometry nobody can
## see at any resolution this game ships at, on the single most repeated drawing in
## the frame.
##
## Scaling by circumference makes the fidelity CONSTANT instead of the segment count
## constant, which is the correct invariant: a small sigil gets cheaper and a big one
## is untouched (the `full` cap still applies, so an ULT's wide summoning band draws
## exactly the geometry it always did). This is a fidelity change strictly below the
## visible threshold, never a change to what the sigil SAYS — radius, timing, colour,
## tier ladder, glyph count and spin are all identical. The sigil is the telegraph
## and the telegraph is the fairness contract; it may get cheaper, it may not get
## quieter.
func _seg(full: int, r: float = -1.0) -> int:
	var n: int = full
	if r > 0.0:
		n = clampi(segments_for_radius(absf(r)), MIN_SEGMENTS, full)
	n = maxi(n / 2, 12) if _low else n
	_work_segments += n
	return n


## Segments needed to keep a circle of radius `r` within `MAX_SAGITTA_PX` of round.
##
## From the sagitta identity for a chord subtending angle θ: s = r·(1 − cos(θ/2)),
## so θ = 2·acos(1 − s/r) and n = TAU/θ. Exposed (and static) so
## `tools/profile_magic_circle.gd` and any future quality tier can reason about the
## same rule rather than re-deriving a second one that disagrees.
static func segments_for_radius(r: float) -> int:
	if r <= MAX_SAGITTA_PX:
		return MIN_SEGMENTS
	var half: float = acos(clampf(1.0 - MAX_SAGITTA_PX / r, -1.0, 1.0))
	if half <= 0.0001:
		return MIN_SEGMENTS
	return int(ceil(TAU / (2.0 * half)))


# ------------------------------------------------------------- WORK COUNTERS
## Deterministic draw-work counters, in the same idiom and for the same reason as
## `CombatVfx` / `DebrisChunk` / `ScorchDecal`: **wall-clock on this machine cannot
## measure this.** Two identical seeded runs of the crowd harness timed 33 ms and
## 57 ms, and at the sub-millisecond scale a single sigil lives at it is worse than
## that — an A/B probe drawing 250 rings of 60 segments each reported a delta of
## 0.42 µs/node, while the same probe at 200 segments reported 9.14 µs/node, which
## is not a measurement, it is a coin toss. (The cause is that a headless frame
## absorbs extra work into idle time until it exceeds the pacing budget, so cost is
## invisible right up until it is not — the same trap that once had a harness
## confidently reporting a perfect 16.67 ms.)
##
## Segments issued per frame is the right invariant anyway: it is what the CPU
## builds commands for AND what the GPU rasterises, it is EXACTLY linear in the
## thing being cut, and it is identical on every machine. A before/after on this
## number is a fact; a before/after on milliseconds here is an opinion.
##
## `segments` counts polyline/arc segments, `dashes` the summoning-ring ticks,
## `glyphs` element marks, `blobs` filled circles. `sigils` is how many `_draw`
## bodies ran, so every figure can be read per-sigil.
static var _work_segments: int = 0
static var _work_dashes: int = 0
static var _work_glyphs: int = 0
static var _work_blobs: int = 0
static var _work_sigils: int = 0


static func work_stats() -> Dictionary:
	return {
		"segments": _work_segments, "dashes": _work_dashes,
		"glyphs": _work_glyphs, "blobs": _work_blobs, "sigils": _work_sigils,
	}


## Test hook.
static func reset_work() -> void:
	_work_segments = 0
	_work_dashes = 0
	_work_glyphs = 0
	_work_blobs = 0
	_work_sigils = 0


## THE GATHER RING — a ring OUTSIDE the sigil that contracts inward as the charge
## fills and lands exactly on the rim at full. It is the clearest possible statement
## of "something is coming and it is nearly here", and it costs one arc.
##
## Drawn only while charging: at full charge it has arrived and would be a second
## ring sitting on top of the main one.
func _draw_gather_ring(R: float, a: float, c: Color) -> void:
	if _charge >= 0.999 or R <= 0.0:
		return
	var k: float = ease(_charge, 0.55)
	var gr: float = R * lerpf(1.62, 1.0, k)
	# Brightens as it closes, so the last frames before release are the brightest.
	var ga: float = (0.18 + 0.55 * k) * a
	draw_arc(Vector2.ZERO, gr, 0.0, TAU, _seg(52, gr), Color(c.r, c.g, c.b, ga), 2.0 + 1.5 * k, true)


## THE RELEASE FLARE — a hard bright ring thrown outward from the rim, fading as it
## goes. Fires on `snap()`, decays over SNAP_DECAY, and is the only thing in this
## drawing that is allowed to be near-white: the ritual has ended and the spell has
## started, and that transition earns one flash.
func _draw_snap_flare(R: float, a: float, c: Color) -> void:
	if _snap <= 0.001:
		return
	var k: float = 1.0 - _snap            # 0 at the instant of release -> 1 when spent
	var fr: float = R * (1.0 + 0.75 * ease(k, 0.4))
	var fa: float = _snap * _snap * a     # squared: slams, then gets out of the way
	var fseg: int = _seg(60, fr)
	draw_arc(Vector2.ZERO, fr, 0.0, TAU, fseg, Color(c.r, c.g, c.b, 0.85 * fa), 3.0 + 5.0 * _snap, true)
	draw_arc(Vector2.ZERO, fr, 0.0, TAU, fseg, Color(1.6, 1.6, 1.7, 0.6 * fa), 1.5 + 2.0 * _snap, true)


## THE SPELL MOTIF — one still figure in the inner court saying what is about to
## happen. `R` is the sigil's live outer radius (already scaled and breathing).
##
## THE THREE RULES EVERY FIGURE HERE OBEYS, because they are what make thirteen
## drawings a language rather than thirteen doodles:
##   1. IT LIVES IN THE LANE. Every stroke sits between MOTIF_INNER and MOTIF_OUTER,
##      so it cannot collide with the core's charge swell or the mechanism ring.
##   2. IT DOES NOT SPIN. The caller draws this outside the rotating transforms.
##   3. IT RESOLVES WITH THE GATHER. Alpha ramps with `_charge`, so the figure fades
##      IN as the spell locks in — the motif is part of the wind-up's information,
##      not a label stuck on the front of it.
##
## ⚠ SURVIVES `graphics_quality = LOW` AT FULL STRENGTH, deliberately, and that is
## the same split the glyph band and the charge fill already get: LOW halves the
## DECORATION (pulse rings, the inner white liner, the ult's 4-point star) and keeps
## everything that carries a READ. The motif is the read. What LOW does drop is the
## second-order detail inside a figure — the guide rails on LANCE, the end-caps on
## BARRIER — which is texture, not meaning.
##
## Budget: every figure below is <= ~34 line segments, against ~200-400 for the rings
## and band it sits inside. It is drawn once per sigil per frame with no arcs wider
## than a third of a turn, so it does not interact with the sagitta tessellation
## budget (`MAX_SAGITTA_PX`) that a previous pass bought 55% of this file's cost with.
func _draw_motif(R: float, a: float, c: Color) -> void:
	if _motif == Motif.NONE or R <= 4.0:
		return
	# The figure resolves as the spell locks in: 45% -> 100% across the gather, then
	# rides the release flare up. A motif at flat opacity reads as a decal.
	var ma: float = a * (0.45 + 0.55 * _charge) * (1.0 + 0.6 * _snap)
	var col := Color(c.r * 1.25, c.g * 1.25, c.b * 1.25, clampf(0.9 * ma, 0.0, 1.0))
	var lo: float = R * MOTIF_INNER
	var hi: float = R * MOTIF_OUTER
	var w: float = 2.0
	_work_glyphs += 1
	match _motif:
		Motif.DESCENT:
			# Three chevrons pointing INWARD at the centre, plus a small cross on the
			# spot. The unambiguous "it lands HERE" figure — the same read the game's
			# ground markers already use, so it needs no learning.
			_work_segments += 8
			for i: int in 3:
				var d: Vector2 = Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 3.0)
				var t: Vector2 = d.orthogonal()
				var tip: Vector2 = d * lo
				var back: Vector2 = d * hi
				draw_polyline(PackedVector2Array([
					back + t * R * 0.14, tip, back - t * R * 0.14,
				]), col, w, true)
			var x: float = R * 0.12
			draw_line(Vector2(-x, 0.0), Vector2(x, 0.0), col, w * 0.7, true)
			draw_line(Vector2(0.0, -x), Vector2(0.0, x), col, w * 0.7, true)
		Motif.LANCE:
			# A barbed shaft along local +x. The one figure with a HEADING, and the
			# reason the motif is drawn unspun: this is the arrow that says which way
			# the beam leaves. (Edge-on gates get their direction from the gate
			# itself and never reach this code — see `_draw_edge`.)
			_work_segments += 6
			draw_line(Vector2(-hi, 0.0), Vector2(hi, 0.0), col, w + 0.4, true)
			draw_polyline(PackedVector2Array([
				Vector2(hi * 0.55, -R * 0.13), Vector2(hi, 0.0), Vector2(hi * 0.55, R * 0.13),
			]), col, w, true)
			if not _low:
				var g: float = R * 0.20
				draw_line(Vector2(-hi * 0.7, -g), Vector2(hi * 0.2, -g), col, 1.0, true)
				draw_line(Vector2(-hi * 0.7, g), Vector2(hi * 0.2, g), col, 1.0, true)
		Motif.BARRIER:
			# One hard chord straight across, with end-caps. Reads as a fence at any
			# size, and is the only figure in the set that is a single straight line —
			# which is what makes it unmistakable next to LANCE's barbed shaft.
			_work_segments += 3
			draw_line(Vector2(-hi, 0.0), Vector2(hi, 0.0), col, w + 1.4, true)
			if not _low:
				var e: float = R * 0.16
				draw_line(Vector2(-hi, -e), Vector2(-hi, e), col, w, true)
				draw_line(Vector2(hi, -e), Vector2(hi, e), col, w, true)
		Motif.ERUPTION:
			# Five spikes driving OUTWARD from the inner ring. The exact inverse of
			# DESCENT, and the pairing is intentional: the two most common big-spell
			# consequences in the roster are "it falls on you" and "it comes up under
			# you", and they must never be confused with each other.
			_work_segments += 15
			for i: int in 5:
				var d2: Vector2 = Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 5.0)
				var t2: Vector2 = d2.orthogonal()
				draw_polyline(PackedVector2Array([
					d2 * lo + t2 * R * 0.10, d2 * hi, d2 * lo - t2 * R * 0.10,
				]), col, w, true)
		Motif.ORBIT:
			# A thin track with three bodies on it. Says "these seek you" — the read a
			# homing spell needs and a placed one must not have.
			var mid: float = (lo + hi) * 0.5
			draw_arc(Vector2.ZERO, mid, 0.0, TAU, _seg(40, mid), Color(col.r, col.g, col.b, col.a * 0.45), 1.0, true)
			_work_blobs += 3
			for i: int in 3:
				var p: Vector2 = Vector2.from_angle(_phase * 1.9 + TAU * float(i) / 3.0) * mid
				draw_circle(p, maxf(1.8, R * 0.05), col, true, -1.0, true)
		Motif.PULSE:
			# Three concentric arcs, each cut open at a different angle so they read
			# as a wave leaving rather than as three more rings. This is the figure
			# that lets a nova state its own radius (see `EnergyNova`).
			for i: int in 3:
				var rr2: float = lerpf(lo, hi, float(i) / 2.0)
				var off: float = float(i) * 0.7
				draw_arc(Vector2.ZERO, rr2, off, off + TAU * 0.78, _seg(30, rr2),
					Color(col.r, col.g, col.b, col.a * (1.0 - 0.22 * float(i))), w, true)
		Motif.SNARE:
			# Three hooks that curl back on themselves. Shares shadow's "reaching"
			# language on purpose — but at the CENTRE, where it means the spell grabs,
			# not merely that it is shadow-flavoured.
			_work_segments += 18
			for i: int in 3:
				var base: float = TAU * float(i) / 3.0
				var pts := PackedVector2Array()
				for k: int in 7:
					var tt: float = float(k) / 6.0
					var rr3: float = lerpf(lo, hi, tt)
					pts.append(Vector2.from_angle(base + tt * 1.5) * rr3)
				draw_polyline(pts, col, w, true)
		Motif.BLADE:
			# Two crossed cuts with tapered tails. Short, hard, asymmetric — a slash
			# rather than an X, which is why the two strokes are not the same length.
			_work_segments += 4
			var d3: Vector2 = Vector2.from_angle(-0.55)
			var d4: Vector2 = Vector2.from_angle(0.75)
			draw_line(-d3 * hi, d3 * hi, col, w + 0.8, true)
			draw_line(-d4 * hi * 0.72, d4 * hi * 0.72, Color(col.r, col.g, col.b, col.a * 0.7), w, true)
		Motif.WARD:
			# A closed hexagon. The only closed convex figure in the set, and closure
			# IS the meaning: this volume is claimed and held.
			_work_segments += 6
			var hex := PackedVector2Array()
			for i: int in 7:
				hex.append(Vector2.from_angle(TAU * float(i % 6) / 6.0) * hi * 0.88)
			draw_polyline(hex, col, w, true)
		Motif.VOID:
			# The one INVERTED figure: a hole punched in the sigil with a bright lip.
			# Everything else here adds light to the middle; this takes it away, which
			# is the only way "it unmakes things" can be said in a drawing made of
			# glowing lines.
			_work_blobs += 1
			draw_circle(Vector2.ZERO, hi * 0.8, Color(0.0, 0.0, 0.0, 0.55 * a), true, -1.0, true)
			draw_arc(Vector2.ZERO, hi * 0.8, 0.0, TAU, _seg(40, hi * 0.8), col, w + 0.6, true)
		Motif.SPIRAL:
			# One arm winding out. Reserved for the spells that change the RULES
			# rather than deal damage — time, gravity, chance — so an unfamiliar
			# spiral is at least a reliable "something strange is about to happen".
			var sp := PackedVector2Array()
			var steps: int = 10 if _low else 16
			_work_segments += steps
			for k2: int in steps + 1:
				var tt2: float = float(k2) / float(steps)
				sp.append(Vector2.from_angle(_phase * 0.5 + tt2 * TAU * 0.9) * lerpf(lo * 0.6, hi, tt2))
			draw_polyline(sp, col, w, true)
		Motif.SUMMON:
			# Triangle inscribed in a ring — the oldest conjuration mark there is, and
			# used here for exactly that: another body is about to be standing there.
			_work_segments += 3
			_draw_star(hi * 0.9, 3, 0.0, col)
			draw_arc(Vector2.ZERO, lo * 0.8, 0.0, TAU, _seg(24, lo * 0.8),
				Color(col.r, col.g, col.b, col.a * 0.5), 1.0, true)


## THE ELEMENT GLYPH BAND. `n` marks around radius `r`, each oriented outward, each
## LIT progressively as the charge fills — so the windup can be counted off the rim
## rather than merely watched. Unlit glyphs stay drawn but dim, which is what makes
## the fill legible: a band that spawned its glyphs one at a time would read as the
## sigil still being built.
##
## An unset element (-1) falls back to the original plain radial ticks, so a caller
## that never heard of this is byte-for-byte unchanged.
func _draw_glyph_band(r: float, n: int, a: float, c: Color) -> void:
	if _element < 0:
		_work_segments += (TICKS if not _low else 10)
		for i: int in (TICKS if not _low else 10):
			var dirv: Vector2 = Vector2.from_angle(TAU * float(i) / float(TICKS if not _low else 10))
			draw_line(dirv * r, dirv * r * 1.24, Color(c.r, c.g, c.b, 0.5 * a), 1.5, true)
		return
	var size: float = maxf(r * 0.26, 3.0)
	_work_glyphs += n
	var dim := Color(c.r, c.g, c.b, 0.30 * a)
	var lit := Color(c.r * 1.35, c.g * 1.35, c.b * 1.35, 0.95 * a)
	for i: int in n:
		var f: float = float(i) / float(n)
		var ang: float = TAU * f
		var at: Vector2 = Vector2.from_angle(ang) * r
		# `<=` on the fraction rather than `<` so the LAST glyph lights at full charge
		# — an off-by-one here means the band never completes and the release always
		# looks a beat early.
		var on: bool = f <= _charge + 0.0001
		_draw_glyph(at, ang, size, lit if on else dim, on)


## One element mark, centred at `at`, pointing along `ang` (outward from the sigil).
## Every shape is authored in a local frame where +x is OUTWARD and +y is tangential,
## then rotated — so a glyph is designed once and works at any point on any ring,
## face-on or foreshortened on an edge-on rim.
func _draw_glyph(at: Vector2, ang: float, size: float, col: Color, lit: bool) -> void:
	var ux: Vector2 = Vector2.from_angle(ang)      # outward
	var uy: Vector2 = ux.orthogonal()              # tangential
	var w: float = 1.6 if lit else 1.2
	match _element:
		Elements.Element.FIRE:
			# A flame TONGUE: a tapered curl leaning off the tangent. Fire is the only
			# element in the set whose glyph is asymmetric, which is what stops it
			# reading as earth's slab when both are drawn in warm amber.
			var f := PackedVector2Array([
				at - ux * size * 0.45 + uy * size * 0.34,
				at + ux * size * 0.05 + uy * size * 0.16,
				at + ux * size * 0.95 + uy * size * 0.10,
				at + ux * size * 0.20 - uy * size * 0.22,
				at - ux * size * 0.45 - uy * size * 0.30,
			])
			draw_polyline(f, col, w, true)
		Elements.Element.ICE:
			# A crystal FACET — a hard four-sided diamond. Closed and straight-edged,
			# the opposite of fire's open curl.
			var d := PackedVector2Array([
				at + ux * size * 0.9, at + uy * size * 0.4,
				at - ux * size * 0.5, at - uy * size * 0.4, at + ux * size * 0.9,
			])
			draw_polyline(d, col, w, true)
			if lit:
				draw_line(at - ux * size * 0.5, at + ux * size * 0.9, col, 1.0, true)
		Elements.Element.LIGHTNING:
			# A BOLT: two hard doglegs. Reads at a glance even at 3 px because the
			# direction reversals survive downsampling where a smooth curve does not.
			draw_polyline(PackedVector2Array([
				at - ux * size * 0.55 + uy * size * 0.30,
				at + ux * size * 0.10 + uy * size * 0.02,
				at - ux * size * 0.10 - uy * size * 0.06,
				at + ux * size * 0.90 - uy * size * 0.34,
			]), col, w + 0.4, true)
		Elements.Element.SHADOW:
			# A hooked TENDRIL — a curl that turns back on itself. Shadow's whole
			# visual language in this game is "reaching", so the glyph reaches.
			var t := PackedVector2Array()
			for k: int in 6:
				var tt: float = float(k) / 5.0
				t.append(at + ux * size * (tt * 1.0 - 0.5) + uy * size * 0.42 * sin(tt * PI * 1.25))
			draw_polyline(t, col, w, true)
		Elements.Element.EARTH:
			# A stone SLAB, filled. The only solid glyph in the set: earth is the one
			# element that has never had a light of its own, and a filled shape is how
			# that reads without giving it one.
			var q := PackedVector2Array([
				at - ux * size * 0.42 + uy * size * 0.34,
				at + ux * size * 0.72 + uy * size * 0.22,
				at + ux * size * 0.72 - uy * size * 0.26,
				at - ux * size * 0.42 - uy * size * 0.32,
			])
			draw_colored_polygon(q, Color(col.r, col.g, col.b, col.a * 0.75))
			draw_polyline(q + PackedVector2Array([q[0]]), col, 1.0, true)
		Elements.Element.HOLY:
			# A radiant RAY with a crossbar — the one glyph with a hard right angle in
			# it, so holy never collapses into lightning's yellow at small sizes.
			draw_line(at - ux * size * 0.5, at + ux * size * 0.95, col, w + 0.3, true)
			draw_line(at + ux * size * 0.15 + uy * size * 0.40,
				at + ux * size * 0.15 - uy * size * 0.40, col, w, true)
		Elements.Element.WIND:
			# A comma SWIRL: a spiral arc that tightens outward.
			var s2 := PackedVector2Array()
			for k: int in 7:
				var tt2: float = float(k) / 6.0
				var rr: float = size * (0.85 - 0.62 * tt2)
				var aa: float = tt2 * TAU * 0.72
				s2.append(at + (ux * cos(aa) + uy * sin(aa)) * rr)
			draw_polyline(s2, col, w, true)
		_:
			# ARCANE (and anything new): a three-stroke RUNE — a stem with two bars.
			draw_line(at - ux * size * 0.45, at + ux * size * 0.9, col, w, true)
			draw_line(at + ux * size * 0.10 + uy * size * 0.34,
				at + ux * size * 0.42 - uy * size * 0.10, col, w * 0.8, true)
			draw_line(at - ux * size * 0.18 + uy * size * 0.30,
				at + ux * size * 0.12 - uy * size * 0.12, col, w * 0.8, true)


## HOW MANY DASHES the summoning ring is cut into.
##
## Deliberately NOT routed through `_seg(r)`: the dash count is a LOOK property —
## it is the pattern the player reads — where the segment count is tessellation
## nobody can see. Scaling it with radius would make a small sigil a visibly
## different drawing rather than a cheaper one. Byte-identical to the previous
## `_seg(DASH_SEGMENTS)` at both quality levels; only the name changed, so that the
## radius-aware `_seg` cannot be applied here by accident later.
func _dashes() -> int:
	return maxi(DASH_SEGMENTS / 2, 12) if _low else DASH_SEGMENTS


func _draw_dashed_ring(r: float, count: int, fill: float, col: Color, width: float) -> void:
	var slot: float = TAU / float(count)
	# Points PER DASH, from the dash's own arc length. A dash on a 17 px sigil spans
	# under 3 px; drawing it with a fixed 6-point arc spent five segments on a stroke
	# barely longer than the line is wide. 2 is a straight tick, which is what a dash
	# that short already looks like.
	var pts: int = clampi(int(ceil(float(segments_for_radius(r)) * slot * fill / TAU)) + 1, 2, 6)
	_work_dashes += count
	_work_segments += count * maxi(pts - 1, 1)
	for i: int in count:
		var start: float = slot * float(i)
		draw_arc(Vector2.ZERO, r, start, start + slot * fill, pts, col, width, true)


func _draw_star(r: float, points: int, offset: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in points:
		pts.append(Vector2.from_angle(offset - PI / 2.0 + TAU * float(i) / float(points)) * r)
	pts.append(pts[0])
	draw_polyline(pts, col, 2.0, true)
