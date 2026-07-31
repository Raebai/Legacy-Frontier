class_name BotIntent
extends RefCounted
## THE BOT CONTRACT, in one file: what a brain is allowed to ask a body to do.
##
## An intent is a plain `Dictionary`, never an instance of this class. That is
## deliberate and it is the whole reason this file is a bag of static helpers
## rather than an object with fields: a brain author writes
##
##     func decide(bb: Dictionary, profile: Dictionary) -> Dictionary:
##         return {"move": Vector2(1.0, 0.0), "dash": true}
##
## and imports NOTHING. No `class_name` dependency, no compile-time coupling to
## the body layer, and no chance of the class-cache trap (a new `class_name`
## consumed by another script on the same run) biting a brain author who only
## wanted to return a dictionary. Everything here — validation, merging, the slot
## table — is optional convenience for the seam, not a gate the brain must pass
## through.
##
## EVERY KEY IS OPTIONAL. A missing key means "no": no movement, no fire, no
## cast, no dash, no guard, no jump. An empty dictionary is a legal intent and
## means "stand still and do nothing", which is exactly what a brain that has not
## decided yet should produce.
##
## ⚠ WHY THE KEYS ARE NOT SIMPLY THE INPUT ACTION NAMES. The action map is the
## KEYBOARD's vocabulary — `blast`, `blink`, `nova`, `ultimate` — and it is full
## of verbs a bot must never press (`switch_class` rewrites GameState, `move_down`
## is the ragdoll-flop toy). Naming the slots by INDEX instead means a brain says
## "use ability 1" and the controller decides which button that is for this body,
## so the same brain drives a class whose R is a blink and a class whose R is an
## uppercut without knowing the difference.

# ---- intent keys ------------------------------------------------------------
## Walk / vertical wish. x in [-1, 1] is the analog walk axis (the same shape
## `Input.get_axis` produces). y < 0 means "wants up" — it is consumed as the
## VERTICAL COMPONENT OF A DASH ANGLE, never as a down-press, because down is the
## limp/flop toy on this body (see BotController.pressed).
const MOVE: StringName = &"move"
## Normalized world aim direction. The bot points; it does not lock on. A zero or
## unset aim HOLDS the last aim rather than snapping to a default, matching what
## a released thumbstick does for a human.
const AIM: StringName = &"aim"
## Primary attack, HELD (the body's own cooldown paces it, exactly as holding LMB
## auto-repeats for a player).
const FIRE: StringName = &"fire"
## Which KIT SPELL to cast this frame; NONE (-1) for no cast. See SLOT_*.
const CAST_SLOT: StringName = &"cast_slot"
const DASH: StringName = &"dash"
## The melee SWING — a real button of its own, distinct from `fire`. On a caster
## `fire` throws a bolt and this punches; on a Brawler `fire` IS a punch combo and
## this is the separate swing. Two keys because they are two buttons.
const SWING: StringName = &"swing"
## The three class ABILITY buttons (Q / R / T). Deliberately NOT folded into
## `cast_slot`: they are a different system from the kit — no MP, no role, no
## reaction identity, one fixed verb per class — and giving them slot indices was
## the mistake that made a brain unable to reason about either system.
const ABILITY_BLAST: StringName = &"ability_blast"   # Q
const ABILITY_BLINK: StringName = &"ability_blink"   # R
const ABILITY_NOVA: StringName = &"ability_nova"     # T
## HELD this frame. The controller derives the press and the release edges from
## the transition, so a held-guard class (Swordsaint's shrinking ring) and a
## press-window class both work off the one boolean.
const GUARD: StringName = &"guard"
const JUMP: StringName = &"jump"

## Every key an intent may carry. Anything else is a typo and is dropped by
## `sanitized()` and named by `problems()` — a silently-ignored misspelled key is
## the exact bug class this codebase keeps writing post-mortems about.
const KEYS: Array[StringName] = [
	MOVE, AIM, FIRE, CAST_SLOT, DASH, GUARD, JUMP, SWING,
	ABILITY_BLAST, ABILITY_BLINK, ABILITY_NOVA,
]

# ---- the kit: `cast_slot` values --------------------------------------------
## `cast_slot` INDEXES `Hero._signatures` DIRECTLY, and that is the whole point.
##
## `Hero._signatures = SpellLibrary.build_for_class(cls)` returns exactly five
## spells in `SpellLibrary.ROLE_ORDER` — damage, control, answer, payoff, ult —
## so slot `i` IS role `ROLE_ORDER[i]` for every class in the game, with no
## translation table anywhere. That is what lets a brain reason about a class it
## has never seen: "I want my control spell" is `cast_slot = 1` whether the class
## answers with an ice wall, a shadow root or a rock pillar.
##
## All five are cast through the ONE `ultimate` button, with the selection being a
## separate act (`Hero.bot_select_signature`) — see BotController for why a bot
## selects by index instead of pressing the shared `cycle_signature` action.
##
## ⚠ THESE ARE NOT Q / R / T. Those are a separate system of class abilities and
## they have their own intent keys (ABILITY_BLAST / ABILITY_BLINK / ABILITY_NOVA).
## An earlier revision of this file put Q/R/T on 0..2, which silently pointed
## every brain at the wrong system: no MP costs, no roles, no elements, and none
## of the reaction combos, which all live in the kit.
const NONE: int = -1
const SLOT_DAMAGE: int = 0    # every class carries its damage line here
## The ONE utility slot. Kits are three spells now (the right thumb has three
## buttons) and each class carries exactly one of control / answer / payoff, chosen
## from its fantasy — so these three names are three ways of asking for the same slot,
## and they are kept as aliases rather than deleted because a brain asking for "my
## control spell" is still asking a meaningful question with a correct answer.
## For the exact role a class put here, see `SpellLibrary.slot_roles_for_class`.
const SLOT_UTILITY: int = 1
const SLOT_CONTROL: int = SLOT_UTILITY
const SLOT_ANSWER: int = SLOT_UTILITY
const SLOT_PAYOFF: int = SLOT_UTILITY
## Derived from the hand size so the ult is the LAST slot by construction. Owned by
## `SpellTier.SLOT_COUNT` — one edit moves the whole control scheme.
const SLOT_COUNT: int = SpellTier.SLOT_COUNT
const SLOT_ULT: int = SpellTier.ULT_SLOT


## The role a class actually put in `slot`, or "" for an out-of-range slot. Replaces
## the old flat `SLOT_ROLES` constant, which could only be right while every class
## laid its kit out identically.
static func role_for(class_id: int, slot: int) -> String:
	var roles: Array = SpellLibrary.slot_roles_for_class(class_id)
	return String(roles[slot]) if slot >= 0 and slot < roles.size() else ""

# ---- indices into blackboard["cooldowns"] -----------------------------------
## The first `SLOT_COUNT` entries are the kit slots above, so
## `cooldowns[intent.cast_slot]` is always the right number and always in bounds —
## the point of one shared numbering. Everything after them is offset FROM
## `SLOT_COUNT` rather than written as a literal, so shrinking the hand cannot leave
## the ability cooldowns pointing at stale indices.
##
## The kit entries are now genuinely per-slot. They used to all read the SAME timer —
## the hero ran one shared signature bank — so a brain choosing a different role was
## not dodging a cooldown, whatever these indices implied. `Hero._hand` (HandSlots)
## owns them individually now, and `slot_affordable` reports "exists and is ready".
const CD_PRIMARY: int = SLOT_COUNT       # the `fire` key
const CD_DASH: int = SLOT_COUNT + 1
const CD_GUARD: int = SLOT_COUNT + 2     # the `guard` key: parry wipe, or a held ring's re-arm
const CD_BLAST: int = SLOT_COUNT + 3     # the ABILITY_* keys
const CD_BLINK: int = SLOT_COUNT + 4
const CD_NOVA: int = SLOT_COUNT + 5
const CD_SWING: int = SLOT_COUNT + 6     # the `swing` key
const CD_COUNT: int = SLOT_COUNT + 7


## The do-nothing intent. Every key present at its "no" value, so a brain that
## builds on top of this can never accidentally inherit a stale press.
static func empty() -> Dictionary:
	return {
		MOVE: Vector2.ZERO,
		AIM: Vector2.ZERO,
		FIRE: false,
		CAST_SLOT: NONE,
		DASH: false,
		GUARD: false,
		JUMP: false,
		SWING: false,
		ABILITY_BLAST: false,
		ABILITY_BLINK: false,
		ABILITY_NOVA: false,
	}


## Coerce a brain's raw return into a well-formed intent: every key present,
## every type right, every value in range, unknown keys DROPPED.
##
## This runs on the seam rather than trusting the brain, for the same reason the
## damage layer re-checks its own caster: a bot that quietly walks at x = 47.0
## because a brain forgot to normalize is a bug that surfaces as "the AI teleports
## sideways", three files away from its cause.
static func sanitized(raw: Variant) -> Dictionary:
	var out: Dictionary = empty()
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw as Dictionary
	if d.has(MOVE):
		var m: Vector2 = _as_vector(d[MOVE])
		out[MOVE] = Vector2(clampf(m.x, -1.0, 1.0), clampf(m.y, -1.0, 1.0))
	if d.has(AIM):
		var a: Vector2 = _as_vector(d[AIM])
		# Normalized here so a brain may hand over a raw "toward the foe" vector
		# and still get an aim, without every consumer re-normalizing.
		out[AIM] = a.normalized() if a.length_squared() > 0.000001 else Vector2.ZERO
	if d.has(FIRE):
		out[FIRE] = bool(d[FIRE])
	if d.has(CAST_SLOT):
		var s: int = int(d[CAST_SLOT])
		# Out-of-range collapses to NONE rather than clamping into a real slot: a
		# brain that computed slot 7 has a bug, and firing the ult on its behalf
		# would hide it behind plausible-looking behaviour.
		out[CAST_SLOT] = s if s >= 0 and s < SLOT_COUNT else NONE
	for flag: StringName in [DASH, GUARD, JUMP, SWING, ABILITY_BLAST, ABILITY_BLINK, ABILITY_NOVA]:
		if d.has(flag):
			out[flag] = bool(d[flag])
	return out


## Human-readable complaints about a raw intent: unknown keys and wrong types.
## Returns an empty array for a clean intent. Used by the test suite and worth
## printing behind a debug flag while authoring a brain — `sanitized()` silently
## repairs these, so without this they are invisible.
static func problems(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (raw is Dictionary):
		out.append("intent is not a Dictionary (got %s)" % type_string(typeof(raw)))
		return out
	var d: Dictionary = raw as Dictionary
	for k: Variant in d.keys():
		var name: StringName = StringName(str(k))
		if not KEYS.has(name):
			out.append("unknown key `%s` (dropped)" % name)
	if d.has(MOVE) and not (d[MOVE] is Vector2):
		out.append("`move` is not a Vector2")
	if d.has(AIM) and not (d[AIM] is Vector2):
		out.append("`aim` is not a Vector2")
	if d.has(CAST_SLOT):
		var s: int = int(d[CAST_SLOT])
		if s != NONE and (s < 0 or s >= SLOT_COUNT):
			out.append("`cast_slot` %d is outside 0..%d (collapsed to none)" % [s, SLOT_COUNT - 1])
	return out


## Layer `over` on top of `base`: any key PRESENT in `over` replaces the one in
## `base`, whether or not its value is "no".
##
## Replace and not OR, because the layers are a priority ladder, not a vote. The
## reflex layer preempting the plan layer must be able to say "do NOT fire this
## frame, you are dodging" — an OR merge makes suppression inexpressible and the
## bot casts into its own dodge.
static func merge(base: Variant, over: Variant) -> Dictionary:
	var out: Dictionary = sanitized(base)
	if not (over is Dictionary):
		return out
	var d: Dictionary = over as Dictionary
	for k: StringName in KEYS:
		if d.has(k):
			out[k] = sanitized(d)[k]
	return out


## True when this intent asks for nothing at all — useful as a "the brain
## declined" test without inspecting seven keys.
static func is_idle(intent: Dictionary) -> bool:
	var i: Dictionary = sanitized(intent)
	if i[MOVE] != Vector2.ZERO or int(i[CAST_SLOT]) != NONE:
		return false
	for flag: StringName in [FIRE, DASH, GUARD, JUMP, SWING,
			ABILITY_BLAST, ABILITY_BLINK, ABILITY_NOVA]:
		if bool(i[flag]):
			return false
	return true


## Vector2 from whatever a brain handed over. A brain that returns a float for
## `move` most likely meant the walk axis, so that reading is honoured; anything
## else is zero.
static func _as_vector(v: Variant) -> Vector2:
	if v is Vector2:
		return v as Vector2
	if v is float or v is int:
		return Vector2(float(v), 0.0)
	return Vector2.ZERO
