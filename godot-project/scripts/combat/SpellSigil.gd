class_name SpellSigil
extends RefCounted
## THE ONE LINE A SPECTACLE CALLS TO SUMMON WITH A CIRCLE.
##
## The maker's ask is that every spell arrives out of a circle that reads instantly
## as THAT element and THAT spell, and that the big ones are unmistakable while they
## are still only a wind-up. Before this, four spectacles in the whole game opened a
## sigil — BeamSpell, MeteorSigil, HollowPurple and SigilGuard — and everything else
## simply appeared. Worse: the caster DOES open a wind-up sigil for every one of
## them (`Hero._open_cast_sigil`), and offers it at the moment of release, so for the
## other ~18 spells the player watched a ritual gather and then be thrown away with
## nothing coming out of it. The ceremony was already being paid for and only four
## spells were spending it.
##
## ============================ WHY THIS IS A HELPER ==========================
## Exactly the argument `SpellCaster._stamp` makes, one layer out. The circle needs
## four things — colour, ELEMENT, TIER and the caster whose wind-up sigil to adopt —
## and three of those are already stamped onto the spectacle by `_stamp`. Written by
## hand at each of ~20 call sites, the two that are easy to forget (element and
## tier) are exactly the two that carry the READ, and forgetting them fails silently:
## you get a generic magenta ring, which looks fine, so nobody notices that the
## element band and the tier ladder are missing.
##
## So this reads the stamp instead of asking the call site to repeat it. A spectacle
## calls `SpellSigil.open(self, muzzle_world_pos, colour)` and the element band, the
## tier ladder and the hand-off all follow from identity the dispatcher already set.
## Forgetting stops being expressible in the same way, and for the same reason.
##
## ⚠ AND THE COROLLARY, which is the rule that keeps finding bugs in this codebase:
## a spectacle with no `caster_node` is inert in the whole reaction system. This
## helper needs that same field, so a sigil that quietly opens un-adopted (rather
## than travelling down from the caster's hand) is a VISIBLE symptom of the invisible
## bug — the ritual restarts mid-cast exactly the way the maker reported. Treat a
## spell whose sigil pops into existence at the muzzle instead of descending into it
## as a missing caster stamp until proven otherwise.
##
## ============================== THE COORDINATE TRAP =========================
## `world_pos` is WORLD space, always. Spell spectacle nodes park at the arena origin
## and draw in world coordinates, so `spectacle.global_position` is (0, 0) and is NOT
## where the effect is. Passing it puts the sigil in the top-left of the arena. Every
## spectacle already has a real world-space origin to hand (`_origin`, `_center`,
## `_at`, ...) — use that.

## Sigil radius per SpellTier shelf, before the caller's own scaling.
##
## TUNED AGAINST A RENDERED FRAME, not reasoned: the first pass used 30/46/68 and
## tools/summon_showcase_capture.gd showed those reading as specks in the real arena
## at the real camera zoom — a QUICK gate seen edge-on is only `radius` tall, so at
## 30 px it was a scratch. These are the sizes at which the three shelves are
## actually distinguishable on screen. The ULT ring is deliberately about a third of
## the arena's height: it is supposed to be the loudest object in the frame.
const RADIUS_QUICK: float = 44.0
const RADIUS_HEAVY: float = 70.0
const RADIUS_ULT: float = 104.0

## How long the sigil takes to materialise, per shelf. Tracks the wind-up lengths in
## `CastStyle.duration` — a QUICK flick's ring must be fully formed inside the 0.18 s
## LASH, or the spell arrives before its own summon does.
const GROW_QUICK: float = 0.14
const GROW_HEAVY: float = 0.22
const GROW_ULT: float = 0.30

## The y-scale a GROUND sigil settles to: a circle inscribed on the floor, seen from
## a side-on camera. Not a projection — a stylisation. 0.34 is shallow enough to read
## as lying down and deep enough that the glyph band is still legible on the near and
## far arcs.
const GROUND_SQUASH: float = 0.34

## Seconds an un-adopted sigil lingers after its spell is done. Long enough for the
## bloom to be a beat of its own rather than the ring being switched off.
const FADE: float = 0.26


# ================== WHICH SPELL IS THIS? — THE MOTIF TABLE ==================
## The maker's note: "make sure the magic circle being drawn is relevant to the
## spell — meteor should be red and look slightly different — and do this for all
## the spells."
##
## Element and tier were already carried (the rim glyph band and the tier ladder).
## The axis that was missing is the SPELL, and it is the one that actually hurts:
## eleven spells in the roster are ARCANE and every one of them opened a violet
## HEAVY circle with arcane runes on it. Identical drawings. Adding a per-spell
## colour would not have fixed that either, because their colour is also identical
## and correct — arcane IS violet.
##
## So the third axis is SHAPE, in the same spirit as the element band: the rim says
## "fire" without colour, and now the inner court says "something falls here"
## without colour. `MagicCircle.Motif` is the vocabulary; this table is the mapping.
##
## ⚠ KEYED ON THE SPECTACLE'S SCRIPT FILE, ON PURPOSE, and this is the design
## decision worth defending. The obvious alternative is to stamp `SpellDef.Kind`
## onto every spectacle in `SpellCaster._stamp` and switch on that. It is a better
## key in the abstract and it is the wrong one here:
##   * A `Kind` only exists for a spell cast through `SpellCaster`. Bosses build
##     spectacles by hand (`Boss.gd`, `ScribbleBoss.gd`), the net layer rebuilds
##     them on remote peers (`Net.gd`), reactions spawn them, and the capture tools
##     instantiate them bare. Every one of those paths has a script and none of them
##     has a `SpellDef` — so a `Kind` key would silently drop the motif on exactly
##     the casts the player is most often on the receiving end of.
##   * The script IS the spectacle's identity, always present, and cannot be
##     forgotten by a call site. That is the same argument `_stamp` and this whole
##     file already make: derive the read from something that cannot go unwritten.
##
## A spectacle may override with a `sigil_motif` property (see `_motif_of`) when its
## script is reused for two different consequences.
##
## ⚠ UNLISTED IS NOT A BUG — it is `Motif.NONE`, which draws nothing and leaves the
## sigil exactly as it was before this table existed. Buffs, drops and passives
## (`BloodPact` when it is only a multiplier, `SpellDeflect`, `GhostForm`) have no
## consequence to state, and inventing a figure for them would be noise.
const MOTIF_BY_SCRIPT: Dictionary = {
	# --- something falls onto this spot -------------------------------------
	"MeteorSigil.gd": MagicCircle.Motif.DESCENT,
	"StarConvergence.gd": MagicCircle.Motif.DESCENT,
	"DivineRay.gd": MagicCircle.Motif.DESCENT,   # a column arrives from ABOVE, marked
	# --- it goes THAT way, in a line ----------------------------------------
	"BeamSpell.gd": MagicCircle.Motif.LANCE,
	"Spell.gd": MagicCircle.Motif.LANCE,
	"ChainBolt.gd": MagicCircle.Motif.LANCE,
	"LightningRush.gd": MagicCircle.Motif.LANCE,
	"HorizonArc.gd": MagicCircle.Motif.LANCE,
	# --- a line you cannot cross --------------------------------------------
	"RockWall.gd": MagicCircle.Motif.BARRIER,
	"IceWall.gd": MagicCircle.Motif.BARRIER,
	# --- the ground comes UP here -------------------------------------------
	"RockPillar.gd": MagicCircle.Motif.ERUPTION,
	"IceSpikeLine.gd": MagicCircle.Motif.ERUPTION,
	"BoulderHurl.gd": MagicCircle.Motif.ERUPTION,
	"BlastSpell.gd": MagicCircle.Motif.ERUPTION,
	# --- satellites that seek ------------------------------------------------
	"RuneOrbs.gd": MagicCircle.Motif.ORBIT,
	# --- a ring leaves this centre ------------------------------------------
	"EnergyNova.gd": MagicCircle.Motif.PULSE,
	"FlameBurst.gd": MagicCircle.Motif.PULSE,
	# --- it reaches out and holds -------------------------------------------
	"ShadowRoot.gd": MagicCircle.Motif.SNARE,
	"DrainTether.gd": MagicCircle.Motif.SNARE,
	"ShadowCrawler.gd": MagicCircle.Motif.SNARE,
	# --- a cut lands ---------------------------------------------------------
	"BladeFlurry.gd": MagicCircle.Motif.BLADE,
	"BlinkStrike.gd": MagicCircle.Motif.BLADE,
	"RiftDagger.gd": MagicCircle.Motif.BLADE,
	# --- a volume is claimed -------------------------------------------------
	"AegisWard.gd": MagicCircle.Motif.WARD,
	"ZoneSpell.gd": MagicCircle.Motif.WARD,
	"SigilGuard.gd": MagicCircle.Motif.WARD,
	# --- it pulls in and unmakes --------------------------------------------
	"VoidCollapse.gd": MagicCircle.Motif.VOID,
	"HollowPurple.gd": MagicCircle.Motif.VOID,
	"Petrify.gd": MagicCircle.Motif.VOID,
	# --- the rules bend ------------------------------------------------------
	"Chronostasis.gd": MagicCircle.Motif.SPIRAL,
	"GravityFlip.gd": MagicCircle.Motif.SPIRAL,
	"Equinox.gd": MagicCircle.Motif.SPIRAL,
	# (Roulette has no spectacle of its own — it re-enters the dispatcher with a
	#  rolled working, so it correctly inherits THAT spell's motif.)
	# --- another body arrives ------------------------------------------------
	"MirrorImage.gd": MagicCircle.Motif.SUMMON,
}


# ------------------------------------------------------------------ the entry point
## Summon `spectacle`'s circle at `world_pos`. Adopts the caster's live wind-up sigil
## when one is on offer (so the ritual is CONTINUOUS from the hand to the muzzle) and
## opens a fresh one when there is not — enemy casts, boss casts, reaction-spawned
## effects and capture tools all land on the fresh path and nothing else changes.
##
## Every parameter after `color` has a working default derived from the tier, so the
## common call really is one line. Returns the circle, which the caller keeps in an
## `_sigil` var and `vanish()`es when its spell is done — or simply leaves to be
## freed with the spectacle, which is also fine.
##
##   `radius_scale`  multiplies the tier's radius, for a spell whose own footprint is
##                   much larger or smaller than its shelf implies (a wall's base
##                   sigil wants to be as wide as the wall, not as wide as its cost).
##   `edge_on`       a GATE the spell bursts through, perpendicular to `axis`. For
##                   beams and lances — anything with a direction of travel.
##   `ground`        laid flat on the floor. For placed spells — fields, wards,
##                   eruptions. Mutually exclusive with `edge_on`; `edge_on` wins.
##   `hold`          seconds before the sigil blooms out on its own. Pass one for
##                   any spectacle that `queue_free()`s itself — the sigil is its
##                   CHILD, so without a shorter life of its own it is destroyed at
##                   full opacity on the frame its parent dies, which is a hard cut
##                   in the middle of the effect. 0 = the caller owns the dismissal.
static func open(
	spectacle: Node,
	world_pos: Vector2,
	color: Color,
	radius_scale: float = 1.0,
	edge_on: bool = false,
	axis: Vector2 = Vector2.RIGHT,
	ground: bool = false,
	thickness: float = 0.14,
	hold: float = 0.0,
) -> MagicCircle:
	if spectacle == null or not spectacle.is_inside_tree():
		return null
	var tier: int = _tier_of(spectacle)
	var element: int = _element_of(spectacle)
	var radius: float = radius_for(tier) * maxf(radius_scale, 0.05)
	var grow: float = grow_for(tier)
	var circle: MagicCircle = MagicCircle.adopt_or_open(
		spectacle, spectacle.get(&"caster_node") as Node, world_pos, color, radius,
		grow, edge_on, axis, thickness)
	if circle == null:
		return null
	# AFTER the adopt, never before: `adopt_or_open` re-colours and re-orients the
	# claimed sigil, and `_begin_handoff` re-infers the element from that new colour
	# when nobody has stated one. Setting the signature here makes the stated answer
	# the last word, which is the only ordering that cannot be silently overridden.
	circle.set_signature(element, tier)
	circle.set_motif(_motif_of(spectacle))
	if ground and not edge_on:
		circle.set_ground(GROUND_SQUASH)
	# BEHIND the spectacle's own drawing. A child CanvasItem draws AFTER its parent,
	# which would put the sigil ON TOP of the thing coming out of it — MeteorSigil
	# found this the hard way, with rocks disappearing inside the gate they were
	# emerging from. `z_as_relative` is on by default, so -1 is "just behind me".
	circle.z_index = -1
	if hold > 0.0:
		circle.hold(hold, FADE)
	_summon_shake(tier)
	return circle


# ------------------------------------------------------------- THE SUMMON SHAKE
## The maker: *"add some slight screen shake for the bigger spells, makes it cooler
## — very slight."* Said "slight" twice, so it is taken literally.
##
## THE LADDER, in camera units on the existing `Juice.shake_camera` scale (where the
## nova's own hard clap is 14.0 and a crate shattering is ~6.0):
##   QUICK  0.0 — NOTHING. The primary bolt fires several times a second; a rattle on
##                every one of them is not "cooler", it is a broken suspension. The
##                zero is the most important number in the ladder.
##   HEAVY  1.7 — under a third of a crate breaking. Present, not reportable.
##   ULT    3.4 — about a quarter of the nova's clap.
##
## ⚠ WHY IT LIVES HERE AND NOT IN THIRTY SPECTACLES. This function is already the
## one place every spell passes through with its TIER in hand — the whole argument
## for `SpellSigil` existing. Putting the shake anywhere else means thirty call sites
## that can each be forgotten, and `spell_tier` is exactly the field the codebase has
## twice found silently unwritten. One caller, one ladder, no drift.
##
## ⚠ IT CALLS THE EXISTING API AND OWNS NO STATE ABOUT THE CAMERA. `CombatCamera`
## converts this to trauma, clamps trauma at 1.0, and scales the result by the
## accessibility `shake_scale` setting. All three of those are honoured for free
## precisely because nothing here reimplements them.
##
## ⚠ AND IT IS RATE-LIMITED, which is the part a naive version gets wrong. A meteor
## barrage, a multi-orb volley or a reaction cascade can open several sigils inside a
## few frames; without the gate those sum straight to the trauma ceiling and the ask
## for "very slight" becomes a blur. The window is one frame's worth of slack, so a
## genuine second cast still shakes and a single spell's own spray does not.
const SHAKE_HEAVY: float = 1.7
const SHAKE_ULT: float = 3.4
const SHAKE_MIN_GAP_MS: int = 90
static var _last_shake_ms: int = -100000

static func _summon_shake(tier: int) -> void:
	var amount: float = 0.0
	match tier:
		SpellTier.Tier.ULT:
			amount = SHAKE_ULT
		SpellTier.Tier.HEAVY:
			amount = SHAKE_HEAVY
		_:
			return   # QUICK and anything unknown: silent. See the ladder above.
	var now: int = Time.get_ticks_msec()
	if now - _last_shake_ms < SHAKE_MIN_GAP_MS:
		return
	_last_shake_ms = now
	Juice.shake_camera(amount)


## Radius for a shelf. Public so a spectacle can size its own geometry against the
## sigil it is about to open rather than guessing.
static func radius_for(tier: int) -> float:
	match tier:
		SpellTier.Tier.ULT:
			return RADIUS_ULT
		SpellTier.Tier.HEAVY:
			return RADIUS_HEAVY
	return RADIUS_QUICK


## Materialise time for a shelf.
static func grow_for(tier: int) -> float:
	match tier:
		SpellTier.Tier.ULT:
			return GROW_ULT
		SpellTier.Tier.HEAVY:
			return GROW_HEAVY
	return GROW_QUICK


## Dismiss a sigil safely from anywhere, including a `null` or already-freed one, so
## a spectacle's teardown never needs the `is_instance_valid` dance.
static func close(circle: MagicCircle, fade: float = FADE) -> void:
	if circle != null and is_instance_valid(circle):
		circle.vanish(fade)


# -------------------------------------------------------------- reading the stamp
## The shelf `spectacle` was stamped with, defaulting to HEAVY — the same middle
## default `SpellTier.DEFAULT_WEIGHT` uses, and for the same reason: an un-stamped
## effect should be neither the loudest nor the quietest thing on screen.
static func _tier_of(spectacle: Node) -> int:
	var raw: Variant = spectacle.get(&"spell_tier")
	if raw == null:
		return SpellTier.DEFAULT_WEIGHT
	return SpellTier.weight_or_default(int(raw))


## The motif for `spectacle`: its own stated answer if it has one, else the table,
## else `Motif.NONE`.
##
## The override exists for the case the table cannot express — ONE script that is
## genuinely two different consequences depending on how it was configured. A
## spectacle opts in by declaring `var sigil_motif: int = MagicCircle.Motif.X`, and
## (per the trap this codebase keeps re-learning) a spectacle that has NOT declared
## it answers `null` from `get()` rather than erroring, which lands on the table.
static func _motif_of(spectacle: Node) -> int:
	var stated: Variant = spectacle.get(&"sigil_motif")
	if stated != null and int(stated) != MagicCircle.Motif.NONE:
		return int(stated)
	var script: Script = spectacle.get_script() as Script
	if script == null or script.resource_path.is_empty():
		return MagicCircle.Motif.NONE
	return int(MOTIF_BY_SCRIPT.get(script.resource_path.get_file(), MagicCircle.Motif.NONE))


## The element `spectacle` was stamped with, or -1 for "not told" — which the circle
## degrades to generic runic ticks rather than guessing an element from.
static func _element_of(spectacle: Node) -> int:
	var raw: Variant = spectacle.get(&"element_id")
	if raw == null:
		return -1
	var e: int = int(raw)
	return e if e >= 0 and e < Elements.count() else -1
