class_name CastStyle
extends RefCounted
## The CAST-ANIMATION vocabulary, shared by every rig that can cast.
##
## Magic-overhaul rule 4: no spell may be a plain instant spawn — each one needs a
## distinct, characterful windup on the caster. That needs a mapping from "what
## kind of spell is this" to "how does the body throw it", and both the spike rig
## (playground) and the Hero rig need the SAME answer or a spell would look like a
## different move depending on who cast it. So the mapping lives here, in one
## table, rather than being duplicated in each rig.
##
## Deliberately NOT on SpellCaster: that maps kind -> spectacle (what appears in
## the world). This maps kind -> body language (what the caster does). Keeping
## them apart means a rig can adopt cast poses without pulling in every spell
## scene, and a new spectacle can reuse an existing pose for free.

## How the body throws the spell. Rigs interpret these into their own joints, so a
## style is a piece of DIRECTION ("slam it into the ground"), not a keyframe.
enum Pose {
	POINT,    ## Two-handed thrust down the aim line. Direct, aimed, projectile-ish.
	SLAM,     ## Overhead wind-up driven into the GROUND. The earth answers.
	CIRCLE,   ## Wide outward sweep opening a magic circle. Ritual, deliberate.
	CHANNEL,  ## Arms raised and HELD while power gathers. The long tell.
	COIL,     ## Pulled tight to the chest, then released. Explosive, bodily.
	LASH,     ## One arm whips out. Snappy, organic, asymmetric.
	SWEEP,    ## Low crouch, trailing hand DRAGS the ground and flicks forward.
	THROW,    ## Over-the-shoulder overhand with a step in. The whole mass commits.
	UNSHEATHE,## Blade drawn slowly ACROSS the body, then released. The iai draw.
}


## Body language for a SpellDef.Kind. Grouped by how the spell should FEEL to
## throw, not by element — two fire spells can want different bodies, and an ice
## wall and a stone wall both want a slam.
static func for_spell(kind: int) -> int:
	match kind:
		SpellDef.Kind.WALL, SpellDef.Kind.ICE_WALL, SpellDef.Kind.PILLAR, SpellDef.Kind.BOULDER:
			return Pose.SLAM        # anything ripped OUT of the ground
		SpellDef.Kind.METEOR, SpellDef.Kind.CONVERGENCE, SpellDef.Kind.ZONE:
			return Pose.CIRCLE      # placed bombardments + fields: a ritual, not a punch
		SpellDef.Kind.DIVINE_RAY:
			return Pose.CHANNEL     # the pillar-of-light tell — arms up, hold, release
		SpellDef.Kind.RUSH, SpellDef.Kind.NOVA, SpellDef.Kind.FLURRY, SpellDef.Kind.BLINK_STRIKE:
			return Pose.COIL        # mobility + melee ultimates come from the body
		SpellDef.Kind.TETHER, SpellDef.Kind.CHAIN, SpellDef.Kind.MISSILES:
			return Pose.LASH        # whips, arcs and streams flick off one hand
		SpellDef.Kind.CRAWLER:
			return Pose.SWEEP       # it peels off the FLOOR, so the hand must go there
		SpellDef.Kind.THROWN_ANCHOR:
			return Pose.THROW       # a thrown object wants weight behind it, not a flick
		SpellDef.Kind.ARC:
			# The crescent LEAVES THE SHEATH — the cut and the draw are the same
			# motion, so any other pose makes the wall look unrelated to the body
			# that threw it. Without this arm ARC falls through to POINT, which
			# reads as pushing the crescent rather than drawing it.
			return Pose.UNSHEATHE
		_:
			return Pose.POINT       # beams and anything new: aimed two-handed thrust


## Seconds the windup should hold for a pose. Slams and channels commit the body
## for longer — that commitment is the dodge window the opponent reads (rule 2),
## so these are balance numbers, not just animation timings.
static func duration(pose: int) -> float:
	match pose:
		Pose.SLAM:
			return 0.34
		Pose.CIRCLE:
			return 0.40
		Pose.CHANNEL:
			return 0.46
		Pose.COIL:
			return 0.22   # snappy — mobility must not feel sticky
		Pose.LASH:
			return 0.18   # the flick is the whole gesture
		Pose.SWEEP:
			return 0.28   # long enough for the drag to read, short of a slam's commit
		Pose.THROW:
			return 0.20   # a dagger leaves the hand fast; the follow-through is after
		Pose.UNSHEATHE:
			# The LONGEST windup in the vocabulary, and that is the point: an iai draw
			# is slow on purpose, and this duration is the opponent's first dodge
			# window (Horizon Cut then stacks two more — the travel and the height
			# band). A fast draw would make the crescent's damage indefensible.
			return 0.50
		_:
			return 0.30
