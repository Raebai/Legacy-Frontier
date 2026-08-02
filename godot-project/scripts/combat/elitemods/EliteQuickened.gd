extends EliteRider
## QUICKENED — "drawn in haste."
##
## The hand was in a hurry. It moves faster and its attacks come round faster, and it
## leaves a smear of itself behind when it runs.
##
## ── WHAT IT CHANGES ABOUT THE FIGHT ──────────────────────────────────────────
## Your spacing, and only your spacing. Every archetype in the roster is balanced
## around a distance you are allowed to hold: the caster's kite band, the brute's
## walk-up, the charger's lane. Quickened does not make any of those hit harder — it
## shortens the time you have to be somewhere else, which is the one difficulty axis
## on a phone that does not also make the fight longer.
##
## ── WHY IT IS CAPPED ─────────────────────────────────────────────────────────
## The ASSASSIN already moves at 175 and lunges at 620. A flat multiplier would put a
## quickened one at a speed the camera cannot frame and the eye cannot read, which is
## not "hard", it is "unfair and probably a bug". SPEED_CAP is the ceiling for every
## archetype, so the affix is a big deal on a brute (62 -> 90) and a small one on an
## assassin (175 -> 235) — which is the correct shape: the slow thing catching you is
## the surprise.

const SPEED_MULT: float = 1.45
const SPEED_CAP: float = 235.0
## Attack cooldowns tick down at this rate. `_cd_speed` is the same field the
## difficulty ladder writes, so this composes with it rather than fighting it.
const CD_MULT: float = 1.35
## Afterimage cadence while it is actually moving. The trail IS the tell that this
## body is not obeying the speed you learned for its archetype.
const GHOST_INTERVAL: float = 0.085
const GHOST_MIN_SPEED: float = 55.0

## THE VOICE BEAT: a gabble while it is actually running. Its whole affix is that it
## arrives sooner than the archetype taught you, so the sound it makes is the sound
## of something that will not stop moving. Gated on a sustained sprint rather than
## on a single fast frame — a body clipping a crate should not chirp.
const SPRINT_TO_SPEAK: float = 0.5
const SPEAK_COOLDOWN: float = 5.5

var _ghost_timer: float = 0.0
var _sprint_t: float = 0.0
var _speak_cd: float = 0.0


func _setup() -> void:
	# AFTER Enemy._apply_difficulty, which multiplies move_speed and WRITES _cd_speed
	# outright — a _ready-time edit would be silently overwritten. See EliteRider.
	var spd: float = float(enemy.get("move_speed"))
	enemy.set("move_speed", minf(spd * SPEED_MULT, maxf(spd, SPEED_CAP)))
	enemy.set("_cd_speed", float(enemy.get("_cd_speed")) * CD_MULT)


## Visual only, and therefore on every peer: a client watching a teammate's screen
## has to see the same body moving impossibly fast, or the affix does not exist there.
func _tick_visual(delta: float) -> void:
	var r: Node = rig()
	if r == null or not is_instance_valid(r):
		return
	var v: Vector2 = enemy.get("velocity")
	# THE VOICE RIDES `velocity`, WHICH IS WHY IT WORKS IN CO-OP. Everything in
	# `_tick` is host-only (see EliteRider rule 2), but velocity is part of the
	# puppet sync — so a client's copy of this body runs the same check off the same
	# numbers and speaks on its own screen with nothing broadcast.
	_speak_cd = maxf(_speak_cd - delta, 0.0)
	if absf(v.x) >= GHOST_MIN_SPEED:
		_sprint_t += delta
		if _sprint_t >= SPRINT_TO_SPEAK and _speak_cd <= 0.0:
			if elite_voice(Gibberish.Mood.LAUGH, 2):
				_speak_cd = SPEAK_COOLDOWN
	else:
		_sprint_t = 0.0
	if absf(v.x) < GHOST_MIN_SPEED:
		return
	_ghost_timer -= delta
	if _ghost_timer > 0.0:
		return
	_ghost_timer = GHOST_INTERVAL
	var col: Color = tint()
	col.a = 0.30
	r.call("spawn_ghost", arena(), col)
