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

## THE VOICE BEAT: an unimpressed grunt when a REAL hit lands and it stays put.
##
## ⚠ IT WATCHES HP, NOT `_knockback`, AND THAT IS A CO-OP DECISION. The damping
## above lives in `_tick`, which is host-only (EliteRider rule 2), so a grunt hung
## off it would exist on one phone. `hp` is synced to every peer, so a client's
## puppet sees the same drop and grunts on its own screen with nothing broadcast.
## It is also the better read: the line the player should hear is "that landed and
## it did not care", which is a damage event, not an impulse event.
const GRUNT_DAMAGE_FRACTION: float = 0.08   ## of max hp — a chip tick says nothing
const GRUNT_COOLDOWN: float = 4.0

var _last_hp: int = -1
var _grunt_cd: float = 0.0


## Runs on EVERY peer — see the hp note above.
func _tick_visual(delta: float) -> void:
	_grunt_cd = maxf(_grunt_cd - delta, 0.0)
	var now_hp: int = int(enemy.get("hp"))
	var mx: int = int(enemy.get("max_hp"))
	if _last_hp < 0 or mx <= 0:
		_last_hp = now_hp
		return
	var lost: int = _last_hp - now_hp
	_last_hp = now_hp
	if lost <= 0 or float(lost) / float(mx) < GRUNT_DAMAGE_FRACTION:
		return
	if _grunt_cd > 0.0:
		return
	# MUTTER, not HURT. The affix's whole promise is that the blow bought you
	# nothing; a yelp would say the opposite of what the body just did.
	if elite_voice(Gibberish.Mood.MUTTER, 1):
		_grunt_cd = GRUNT_COOLDOWN


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
