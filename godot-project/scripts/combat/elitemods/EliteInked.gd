extends EliteRider
## INKED — "pressed too hard into the page."
##
## It cannot be shoved. Knockback bleeds off it almost instantly, so every
## displacement tool you own — the shove on a heavy spell, the wall-slam, the little
## bit of breathing room a hit normally buys you — stops working on this one body.
##
## ── WHY THIS IS A REAL AFFIX AND NOT A STAT ──────────────────────────────────
## Knockback is not damage in this game, it is SPACE. `Tuning.knockback_mult` exists
## because "displacement IS the feel" (Stick Fight), and the whole crowd-control loop
## on a busy floor is: hit the thing, it slides, you get a beat. An inked body takes
## the same damage on the same timeline and simply refuses to give you the beat, so
## the answer is positioning rather than a bigger number — which is exactly the kind
## of difficulty the spec asks for and an HP buff never provides.
##
## ── IT STILL REELS ───────────────────────────────────────────────────────────
## The rig FLOP is left alone on purpose. Suppressing the reel as well would read as
## "my hit did nothing" — the wrong message, since the hit landed in full. What the
## player should read is a body that jerks under the blow and does not move: a thing
## that is drawn INTO the paper.
##
## The residue (rather than a hard zero) is deliberate: a mountain-mass shove still
## nudges it a few pixels, so heavy spells stay legibly heavier than light ones.

## Fraction of the remaining knockback impulse that survives each frame.
const RESIDUE: float = 0.12


func _tick(_delta: float) -> void:
	# `_knockback` is the decaying horizontal channel Enemy integrates into
	# velocity.x every physics frame. Damping it here is one field write and needs no
	# line inside Enemy.gd. The VERTICAL half of a shove is a one-shot into
	# velocity.y and is left alone — an inked body still pops when it is truly
	# hammered, it just lands where it stood.
	var k: Vector2 = enemy.get("_knockback")
	if k == Vector2.ZERO:
		return
	enemy.set("_knockback", k * RESIDUE)
