class_name BotBrain
extends RefCounted
## THE BOT BRAIN — three layers of pure math over a blackboard, producing one
## intent dictionary per frame. No nodes, no tree, no signals, no LLM.
##
## ---------------------------------------------------------------------------
## THE THREE LAYERS, AND HOW THEY COMPOSE
##
##   1. REFLEX      (BotDodge)  — "is something about to hit me, and what is the
##                  shortest way out". Runs first and PREEMPTS: a bot that finishes
##                  its cast animation inside a meteor is not a bot anyone believes.
##                  Pure threat geometry; already its own module.
##   2. STEERING    (_steer)    — "where do I want to stand". A spacing band per
##                  class, blended against danger: telegraph footprints, pit rects,
##                  and cover. Flattened to move.x because this is a side-on
##                  platformer — vertical intent becomes a jump, not a Y velocity.
##   3. UTILITY     (_score_slots) — "what do I press". Every ready slot is scored
##                  against the situation and the best one wins, if it clears a
##                  threshold. This is the layer that makes the bot use its whole
##                  kit instead of throwing its damage line at the wall.
##
## They compose by PRIORITY, not by blending: the reflex layer can veto the other
## two outright (you do not cast while diving out of a blast), steering always
## contributes movement (moving is free — it never conflicts with a cast), and the
## utility layer is the only thing allowed to press a button. Guard is the one
## exception in the other direction: MeleeClash's locked rule is that guarding
## locks out attacking, so a held guard suppresses fire and cast in the same frame.
##
## WHY THIS SHAPE AND NOT GOAP OR A BEHAVIOUR TREE. Attack wind-ups here are
## 0.35-0.9 s and every telegraph RE-SNAPSHOTS its target when the wind-up starts,
## so a plan older than about a second is already describing a fight that no longer
## exists. Utility re-scores from the live blackboard every `period` seconds and
## therefore cannot hold a stale plan; a tree would encode the same decisions as
## structure, where they are far harder to retune than a weights table.
##
## ---------------------------------------------------------------------------
## FAIRNESS IS STRUCTURAL. The brain is handed a blackboard built from what is on
## screen and a profile built from BotProfile — and it has NO other input. It
## cannot query the world, cannot read a private field, cannot see an untelegraphed
## attack. Difficulty is reaction delay and error rate (BotProfile), never
## knowledge and never stats. Aim carries a bounded error at EVERY tier because
## no-auto-aim is a locked project rule: the bot points, and it can miss.
##
## COST. This runs per bot per frame. The reflex layer is a handful of dot products
## over the visible threats; the expensive layer (utility, which touches the kit
## table) is rate-limited to once per `profile.period` and LATCHED in between — so
## the per-frame cost in the common case is the reflex pass and a vector subtract.
##
## ---------------------------------------------------------------------------
## THE CONTRACT (fixed by the caller; another module builds the body seam against
## it, so nothing here may drift from it).
##
##   BotBrain.decide(bb: Dictionary, profile: Dictionary, mem: Memory = null)
##       -> Dictionary
##
## INTENT out — every key OPTIONAL, missing means "no":
##   "move": Vector2   x in [-1,1] walk; y < 0 means "wants up"
##   "aim":  Vector2   normalised world aim direction
##   "fire": bool
##   "cast_slot": int  0..3 spell slots, 4 = ult (omitted entirely = no cast)
##   "dash": bool
##   "guard": bool     HELD this frame
##   "jump": bool
##
## BLACKBOARD in — the guaranteed minimum, all of it screen-visible:
##   "self_pos", "self_vel": Vector2; "self_hp_frac", "self_mp_frac": float
##   "on_floor": bool; "facing": float
##   "foe_pos", "foe_vel": Vector2; "foe_hp_frac", "foe_facing": float
##   "threats": Array    telegraph / projectile descriptors (see _normalise)
##   "cooldowns": Array  float per slot, 0.0 = ready
##   "reach": float; "now": float
##
## ...plus these OPTIONAL enrichments. Every one of them is inert when absent, so
## a caller that supplies only the minimum gets a working bot — a duller one.
##   "class_id": int          Hero.HeroClass. Unlocks the real kit (elements, cast
##                            times, ranges, costs) via SpellLibrary, and with it
##                            the channel-safety gate and every combo set-up.
##   "hazards": Array[Rect2]  pit footprints. Without them the bot will dodge into
##                            a pit, so this is the one enrichment worth insisting on.
##   "fields": Array          live ground effects: {element:int, pos, radius, mine:bool}.
##                            The other half of the combo layer.
##   "barriers": Array        live walls: {element:int, pos, radius}.
##   "dash_ready", "blink_ready", "guard_ready": bool
##   "guard_style": int       0 BLADE / 1 SIGIL (ParryRing.Style) — different band.
##   "can_parry": bool
##   "mem": Memory            see the note on Memory below.

# ---------------------------------------------------------------- slot roles
## SLOT INDEX STILL CARRIES A ROLE MEANING, but a weaker one than it used to, and the
## difference is worth reading before touching the scorer.
##
## It used to be exact: kits were five spells emitted in `SpellLibrary.ROLE_ORDER`, so
## slot 1 was ALWAYS "control" for every class in the game. Kits are now three spells
## (the right thumb has three buttons), and which three a class carries is chosen per
## class from its fantasy — so slot 1 is "control" for the Arcanist, "answer" for the
## Brawler and "payoff" for the Shadowblade.
##
## What SURVIVES, and what the scorer actually relies on:
##   slot 0            — ALWAYS the damage line. Every class carries it.
##   slot SLOT_COUNT-1 — ALWAYS the ult. Every class carries it, and
##                       `SpellTier.slot_accepts_ult` enforces the shelf.
##   the middle slot   — the class's ONE non-damage, non-ult tool, whichever of
##                       control / answer / payoff its fantasy names.
## So "reach for my utility spell" is still a fixed index; "reach for my WALL
## specifically" is not, and never was reliable anyway — the control role answers with
## an ice wall, a shadow root or a rock pillar depending on the class. A brain that
## wants the exact role asks `SpellLibrary.slot_roles_for_class(class_id)`; the facts
## table below already carries the per-spell properties that made the role a proxy for.
const ROLE_DAMAGE: int = 0
## The single utility slot. The three old aliases all point at it because a class
## carries exactly ONE of control / answer / payoff, so "give me my control spell" and
## "give me my answer" are now the same question with the same honest answer.
const ROLE_UTILITY: int = 1
const ROLE_CONTROL: int = ROLE_UTILITY
const ROLE_ANSWER: int = ROLE_UTILITY
const ROLE_PAYOFF: int = ROLE_UTILITY
const ROLE_ULT: int = BotIntent.SLOT_ULT
## Derived, never a literal: the hand size is owned by `SpellTier.SLOT_COUNT` and a
## second copy of it here is exactly how the two would drift.
const SLOT_COUNT: int = BotIntent.SLOT_COUNT

## EXTRA COOLDOWN INDICES, past the five castable slots. The body seam publishes a
## longer `cooldowns` array than the brain strictly needs: after the five slots it
## appends the primary attack, the dash and the guard, because a brain has to know
## whether those are ready before committing to a plan — but they are NOT reachable
## through `cast_slot` (the primary is held and the dash is an edge, so folding them
## into the slot numbering would make one index mean two kinds of press).
##
## Read DEFENSIVELY and by index rather than by importing the seam's constants: the
## boundary is a plain Dictionary on purpose, and a caller that publishes only the
## five slots must keep working. See `_ready_flag`.
const CD_PRIMARY_INDEX: int = 5
const CD_DASH_INDEX: int = 6
const CD_GUARD_INDEX: int = 7

# ------------------------------------------------------------ body constants
## Mirrors of the hero's own numbers. They are COPIES on purpose: this module must
## stay pure (no Hero import, no autoload) so it is headless-testable and can drive
## an Enemy body as easily as a hero one. Each is annotated with its source so a
## retune over there is a one-line find here.
const DASH_DIST: float = 86.8          # Hero.DASH_SPEED 620 * DASH_TIME 0.14
const DASH_COOLDOWN: float = 0.9       # Hero.DASH_COOLDOWN
const BLINK_DIST: float = 175.0        # Hero.BLINK_DISTANCE
const BLINK_COOLDOWN: float = 1.3      # Hero.BLINK_COOLDOWN
const MELEE_COOLDOWN: float = 0.34     # Hero.MELEE_COOLDOWN
## ParryRing's shrinking-ring geometry. The guard is HELD, and its perfect band
## opens LATE in the shrink — so pressing on reaction to a hit is always too late.
## The brain must press EARLY, timed so the blow arrives inside the band; these
## are the two moments to aim impact at.
const GUARD_SHRINK: float = 0.42       # ParryRing.SHRINK_TIME
const GUARD_BAND_BLADE: float = 0.374  # midpoint of PERFECT_START 0.78 .. 1.0
const GUARD_BAND_SIGIL: float = 0.392  # midpoint of SIGIL_PERFECT_START 0.865 .. 1.0
const GUARD_REARM_BLADE: float = 0.35  # ParryRing.REARM_TIME
const GUARD_REARM_SIGIL: float = 0.55  # ParryRing.SIGIL_REARM_TIME
const GUARD_HOLD_TAIL: float = 0.06    # keep holding a hair past the band

# ------------------------------------------------------------ brain tunables
## How far past a channel's cast_time the board must stay clear before the brain
## will commit to it. A channel is interrupted by ANY landed hit, so starting one
## with a threat resolving at cast_time + epsilon is just donating the spell.
const CHANNEL_MARGIN: float = 0.25
## Minimum utility a slot must reach before the brain spends it. Below this it
## would rather walk and keep the cooldown, which is what stops a bot dumping its
## ult into an empty arena the instant it comes off cooldown.
const CAST_THRESHOLD: float = 0.20
## The anti-spam term. Re-using the slot you just used is penalised, decaying over
## RECENCY_TAU seconds. This is the single term that most visibly turns "throws its
## damage line forever" into "plays its kit".
##
## IT IS THE SECOND VARIETY SOURCE, NOT THE FIRST. Real cooldowns do most of this
## work — a kit whose slots are on 3-6 s timers cannot be spammed. What this term
## covers is the window INSIDE a cooldown where two slots are both ready and one of
## them was just thrown: without it the higher-scoring of the two wins every single
## time, measured at 21 of 24 casts on one slot in a cooldown-free scenario. 0.70 was
## picked because 0.55 left the damage line above every other role's base even while
## penalised, so the rotation never started at all.
const RECENCY_PENALTY: float = 0.70
const RECENCY_TAU: float = 2.5
## How long a chosen cast / dodge is held before the brain is allowed to change its
## mind. Re-deciding every frame is what makes bots twitch, and a cast that is
## re-picked mid-wind-up never comes out at all.
const CAST_LATCH: float = 0.22
const DODGE_LATCH: float = 0.29        # dash 0.14 + a short lockout
## Distance probed when scoring "which way should I step". A step shorter than this
## cannot leave a telegraph footprint, so scoring it would always tie.
const STEER_PROBE: float = 90.0
## Deadband on the spacing band, as a fraction of it. Without one the bot oscillates
## across the ideal distance forever, which reads as a stutter rather than a stance.
const BAND_DEADZONE: float = 0.16
## Two of the caster's own spells fusing (ReactionTable's hollow_purple, the
## headline self-combo) needs the second beam thrown inside this window.
const FUSION_WINDOW: float = 1.1
## A threat closer than this many seconds counts as "pressure" at full weight.
const PRESSURE_HORIZON: float = 1.2

## Preferred spacing band per Hero.HeroClass — {min, max} px from the foe. This is
## the class's STANCE, and it is what makes an Arcanist read as an Arcanist: it
## wants to stand where its beam works and the foe's fists do not. Aggression
## (BotProfile) pulls the whole band toward contact, so an aggressive Arcanist
## fights closer than a cautious one without needing a second table.
##
## Indexed by Hero.HeroClass — MAGE 0, ROGUE 1, BRAWLER 2, JUGGERNAUT 3, CLERIC 4,
## CRYOMANCER 5, STORMCALLER 6, WARLOCK 7, SWORDSAINT 8.
const CLASS_BAND: Array[Dictionary] = [
	{"min": 190.0, "max": 340.0},   # ARCANIST  — caster band
	{"min": 60.0, "max": 200.0},    # SHADOWBLADE — in and out
	{"min": 40.0, "max": 110.0},    # BRAWLER   — contact
	{"min": 80.0, "max": 220.0},    # JUGGERNAUT— close, but throws rocks
	{"min": 120.0, "max": 260.0},   # CLERIC    — mid, tether range
	{"min": 200.0, "max": 360.0},   # CRYOMANCER— longest poke in the roster
	{"min": 170.0, "max": 320.0},   # STORMCALLER
	{"min": 150.0, "max": 300.0},   # WARLOCK   — attrition at tether range
	{"min": 50.0, "max": 130.0},    # SWORDSAINT— guard-and-punish, wants contact
]
const DEFAULT_BAND: Dictionary = {"min": 150.0, "max": 300.0}

## ---------------------------------------------------------------------------
## THE COMBOS THE BOT CAN ACTUALLY EXECUTE.
##
## Sourced from ReactionTable's authored rows — NOT invented here. Each entry says
## "a live field of `field` element makes an attack of `then` element much better,
## so both halves are worth planning". The brain uses each row in BOTH directions:
##
##   CASHING IN  — a matching field is already on the board, so boost the slot whose
##                 element completes it. (Fire the lightning through the blizzard.)
##   SETTING UP  — no field yet, but I hold BOTH halves and both are ready, so boost
##                 the field-maker. This is the half that produces the clip: the bot
##                 drops the frost field ON PURPOSE, because of what it holds next.
##
## Weighted by `profile.combo` so a low tier plays single spells and a high tier
## plays the matrix. The `payoff` figure is the row's own relative worth, used only
## to rank two available combos against each other.
const COMBO_SETUPS: Array[Dictionary] = [
	# supercharge — LIGHTNING through an ICE field. Spends nothing on either side,
	# which is why it is the best set-up in the game: the field keeps standing and
	# the beam carries on. The Stormcaller kit is literally built around it
	# (blizzard in control, Tempest in ult).
	{"field": Elements.Element.ICE, "then": Elements.Element.LIGHTNING,
		"name": "supercharge", "payoff": 1.0},
	# steam_cloud — FIRE into an ICE field. Consumes the field and pays in VISION
	# rather than damage, so it ranks under supercharge.
	{"field": Elements.Element.ICE, "then": Elements.Element.FIRE,
		"name": "steam_cloud", "payoff": 0.6},
	# banish — HOLY into a SHADOW field. Erases the field outright; the answer to a
	# Warlock parking a Shadow Root on the floor.
	{"field": Elements.Element.SHADOW, "then": Elements.Element.HOLY,
		"name": "banish", "payoff": 0.8},
	# void_charged — anything detonating inside a SHADOW field inverts its knockback
	# into a pull. Wildcard on the attacker, so `then` is -1 = any element.
	{"field": Elements.Element.SHADOW, "then": -1,
		"name": "void_charged", "payoff": 0.5},
]

## The same idea against BARRIERS rather than fields: bringing the right element to
## a wall is the whole point of having elements. `then` = the element that answers
## `barrier`.
const COMBO_BARRIERS: Array[Dictionary] = [
	# shatter_ice_barrier / shrapnel_cone — FIRE or HOLY pops an ICE wall, and so
	# does any thrown thing.
	{"barrier": Elements.Element.ICE, "then": Elements.Element.FIRE, "payoff": 0.9},
	{"barrier": Elements.Element.ICE, "then": Elements.Element.HOLY, "payoff": 0.9},
	# shatter_ward — SHADOW pops a HOLY ward, which is the ward's own printed counter.
	{"barrier": Elements.Element.HOLY, "then": Elements.Element.SHADOW, "payoff": 0.8},
]

## ...and the one the bot must NOT walk into. ReactionTable's `ground_out` row:
## an EARTH barrier eats a LIGHTNING beam and the beam is CONSUMED. Throwing your
## lightning line into a rock wall is a spell donated to the wall, so the scorer
## takes a penalty rather than merely not taking a bonus.
const COMBO_AVOID: Array[Dictionary] = [
	{"barrier": Elements.Element.EARTH, "then": Elements.Element.LIGHTNING, "penalty": 0.5},
]


## ---------------------------------------------------------------------------
## PER-BOT MEMORY. The brain is otherwise stateless, but three things genuinely
## cannot be recomputed from one frame's blackboard:
##
##   · WHEN a threat was first seen — the entire reaction-delay model. Recomputing
##     it per frame would mean the bot has always-just-noticed everything, i.e. no
##     reaction time at all, i.e. the difficulty dial silently does nothing.
##   · WHAT it decided last — the latches that stop it twitching, and the recency
##     term that stops it spamming one slot.
##   · WHAT IT LAST THREW — the fusion window for the self-combo.
##
## Hand the same instance back every frame. `decide` will also accept one parked in
## the blackboard under "mem", and will install one there if it finds neither — so
## a caller that reuses its blackboard dictionary gets full behaviour for free, and
## a caller that rebuilds it every frame degrades SAFELY (see the note in decide).
class Memory extends RefCounted:
	## First-sighting clock + whiff rolls. Owned by BotDodge so the dodge module and
	## the brain can never disagree about what this bot has noticed.
	var reactions: BotDodge.Reactions = BotDodge.Reactions.new()
	## Deterministic under test: set `rng.seed` and the same fight replays exactly.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	var next_decision_at: float = -1.0
	var latched_slot: int = -1
	var latched_until: float = 0.0
	var dodge_until: float = 0.0
	var dodge_action: String = ""
	var dodge_dir: Vector2 = Vector2.ZERO

	## Self-imposed cooldowns. The blackboard MAY tell us what is ready; when it does
	## not, we hold ourselves to the body's real numbers rather than assuming we can
	## dash every frame. Assuming readiness is a cheat by omission.
	var last_dash_at: float = -99.0
	var last_blink_at: float = -99.0
	var last_guard_at: float = -99.0
	var last_fire_at: float = -99.0
	var guard_hold_until: float = 0.0

	## Slot -> time last cast, for the recency (anti-spam) term.
	var last_slot_at: Dictionary = {}
	## The self-combo window: what element the last BEAM-shaped spell carried.
	var last_beam_element: int = -1
	var last_beam_at: float = -99.0

	## Aim scatter is sampled once per decision, not per frame — a per-frame sample
	## would average out to perfect aim over a beam's channel, which is exactly the
	## auto-aim this must not become.
	var aim_error: float = 0.0

	func _init() -> void:
		rng.randomize()


## Cached kit facts per class id. build_for_class mints fresh Resources on every
## call (correctly — they are mutable), so calling it per frame per bot would be
## pure garbage. The facts we derive are immutable, so one build per class for the
## whole process is right.
static var _kit_cache: Dictionary = {}


# =========================================================================
# THE ENTRY POINT
# =========================================================================

## One frame of thinking. Pure: same blackboard + same profile + same memory state
## produces the same intent, which is what makes the whole brain provable headlessly.
##
## ON THE MISSING-MEMORY CASE. `mem` is optional so the 2-argument contract call
## works verbatim. When it is absent we look in the blackboard, and failing that
## install a fresh one there. If the caller rebuilds its blackboard every frame the
## install is lost each time — and the degradation is deliberately the SAFE one: a
## brand-new Reactions has seen nothing, so the bot does not react to threats it has
## not had time to notice. It gets duller, never cheaper to beat itself against.
static func decide(bb: Dictionary, profile: Dictionary, mem: Memory = null) -> Dictionary:
	var m: Memory = _resolve_memory(bb, mem)
	var now: float = float(bb.get("now", 0.0))
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var my_vel: Vector2 = bb.get("self_vel", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)

	var intent: Dictionary = {}

	# ---- perception: only the threats this bot is ALLOWED to have noticed yet.
	var seen: Array = _visible_threats(bb, profile, m, now)
	var evaluated: Array = []
	for t: Dictionary in seen:
		evaluated.append(_evaluate(me, my_vel, t))
	var pressure: float = _pressure(evaluated, me, foe, float(bb.get("reach", 58.0)))
	var soonest: float = _soonest_tti(evaluated)

	# ---- aim is free and never conflicts with anything else, so it is resolved
	# first and survives every early return below. A bot that stops aiming while it
	# dodges looks like it stopped thinking.
	intent["aim"] = _aim(bb, profile, m, now)

	# ---- LAYER 1: the reflex. Preempts, and may end the frame outright.
	var reflex: Dictionary = _reflex(bb, profile, m, now, evaluated)
	if not reflex.is_empty():
		for k: String in reflex.keys():
			intent[k] = reflex[k]
		# Guard is HELD, and MeleeClash's locked rule is that guarding locks out
		# attacking — so a guarding frame is a guarding frame and nothing else.
		# A dash/blink/jump frame still gets its movement from the reflex exit
		# vector, which the steering layer must not then fight.
		return intent

	# ---- LAYER 2: steering. Always contributes; movement costs nothing.
	intent["move"] = _steer(bb, profile, m, evaluated, pressure)

	# ---- LAYER 3: utility. Rate-limited and latched — see CAST_LATCH.
	var slot: int = _pick_slot(bb, profile, m, now, pressure, soonest)
	if slot >= 0:
		intent["cast_slot"] = slot
		_note_cast(bb, m, slot, now)
	elif _wants_fire(bb, profile, m, now, evaluated):
		intent["fire"] = true
		m.last_fire_at = now
	return intent


# =========================================================================
# PERCEPTION
# =========================================================================

## Everything on the board, filtered down to what this bot has had time to see and
## did not fumble. This is the ONLY place threats enter the brain, which is what
## makes the fairness claim checkable: there is one door and the reaction delay is
## nailed to it.
static func _visible_threats(bb: Dictionary, profile: Dictionary, m: Memory,
		now: float) -> Array:
	var raw: Array = bb.get("threats", [])
	var delay: float = BotProfile.get_f(profile, "react")
	var jitter: float = BotProfile.get_f(profile, "jitter")
	var p_miss: float = BotProfile.get_f(profile, "p_miss")
	var out: Array = []
	var live: Array = []
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = _normalise(entry)
		var id: int = int(t["id"])
		live.append(id)
		# Two independent rolls: one jitters WHEN it is noticed, one decides whether
		# this particular threat is fumbled. Both are taken ONCE, at first sighting —
		# hence the `knows` guard, without which the draws would be spent every frame
		# and a seeded bot would stop being reproducible.
		if not m.reactions.knows(id):
			var jitter_roll: float = m.rng.randf_range(-jitter, jitter)
			m.reactions.observe(id, now, maxf(delay + jitter_roll, 0.0), m.rng.randf(), p_miss)
		if m.reactions.visible(id, now):
			out.append(t)
	# A threat that no longer exists must be forgotten, or Godot recycling its
	# instance id hands a brand-new threat an already-elapsed reveal time — a free
	# instant reaction, and the exact shape of bug that quietly voids a fairness
	# guarantee.
	m.reactions.forget_missing(live)
	return out


## One threat descriptor, in whatever shape the perception layer happened to build
## it, reduced to the one shape this brain reasons about.
##
## TWO SHAPES ARE ACCEPTED ON PURPOSE. The build plan's threat record uses a `kind`
## field; Telegraph.danger_shape() — which is what the live telegraphs actually
## publish — uses `shape` with "circle" / "line". Rather than force one caller to
## translate for the other (and drift), both are read here.
static func _normalise(t: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"id": int(t.get("id", 0)),
		"tti": float(t.get("tti", t.get("time_to_impact", 0.0))),
		"damage": int(t.get("damage", 0)),
		# Unknown parryability is treated as PARRYABLE: guessing "no" would make the
		# bot never guard against anything a caller forgot to annotate, which is a
		# silent loss of a whole defensive verb.
		"parryable": bool(t.get("parryable", true)),
		"pos": t.get("pos", t.get("center", t.get("from", Vector2.ZERO))),
		"vel": t.get("vel", Vector2.ZERO),
		"radius": float(t.get("radius", 0.0)),
		"width": float(t.get("width", 0.0)),
		"length": float(t.get("length", 0.0)),
		"angle": float(t.get("angle", 0.0)),
		"form": "",
	}
	var shape: String = String(t.get("shape", ""))
	if shape == "line" or (t.has("from") and t.has("to")):
		# A published line gives two endpoints; the lane solver wants an origin plus
		# an angle and a length, so derive them once here.
		var a: Vector2 = t.get("from", Vector2.ZERO)
		var b: Vector2 = t.get("to", a)
		var seg: Vector2 = b - a
		out["pos"] = a
		out["angle"] = seg.angle()
		out["length"] = seg.length()
		out["form"] = "lane"
	elif shape == "circle":
		out["form"] = "circle"
	else:
		var kind: Variant = t.get("kind", null)
		var kind_s: String = String(kind).to_lower() if typeof(kind) == TYPE_STRING else ""
		if kind_s == "lane" or out["length"] > 0.0 and out["radius"] <= 0.0:
			out["form"] = "lane"
		elif kind_s == "projectile" or Vector2(out["vel"]).length_squared() > 0.01:
			out["form"] = "projectile"
		else:
			out["form"] = "circle"
	return out


## Threat geometry, dispatched to the right solver in BotDodge. All three return the
## same {threatening, tti, exit, exit_len, degenerate} shape, which is what lets the
## response ladder be written once for every attack in the game.
static func _evaluate(me: Vector2, my_vel: Vector2, t: Dictionary) -> Dictionary:
	var r: Dictionary
	match String(t["form"]):
		"projectile":
			r = BotDodge.threat_from_projectile(me, t["pos"], t["vel"])
		"lane":
			r = BotDodge.threat_from_lane(me, my_vel, t["pos"], float(t["angle"]),
				float(t["length"]), float(t["width"]), float(t["tti"]))
		_:
			r = BotDodge.threat_from_circle(me, my_vel, t["pos"], float(t["radius"]),
				float(t["tti"]))
	r["id"] = t["id"]
	r["parryable"] = t["parryable"]
	r["damage"] = t["damage"]
	r["form"] = t["form"]
	r["pos"] = t["pos"]
	r["radius"] = t["radius"]
	return r


## How hard this bot is being pressed, 0..1 — the term that turns the "answer" slot
## from a mobility toy into an escape button and that talks the bot out of long
## channels. Counts imminent threats AND the plain fact of a foe standing inside
## melee reach, because a fist is a threat with no telegraph to perceive.
static func _pressure(evaluated: Array, me: Vector2, foe: Vector2, reach: float) -> float:
	var p: float = 0.0
	for e: Dictionary in evaluated:
		if not bool(e.get("threatening", false)):
			continue
		var tti: float = float(e.get("tti", PRESSURE_HORIZON))
		p += clampf(1.0 - tti / PRESSURE_HORIZON, 0.0, 1.0)
	if me.distance_to(foe) <= reach * 1.35:
		p += 0.5
	return clampf(p, 0.0, 1.0)


## Seconds until the NEXT thing lands, or a large number when the board is clear.
## The channel-safety gate is a comparison against this and nothing else.
static func _soonest_tti(evaluated: Array) -> float:
	var soonest: float = 99.0
	for e: Dictionary in evaluated:
		if bool(e.get("threatening", false)):
			soonest = minf(soonest, float(e.get("tti", 99.0)))
	return soonest


# =========================================================================
# LAYER 1 — THE REFLEX
# =========================================================================

## Returns a COMPLETE intent (movement included) when the bot is answering a threat,
## or {} to let the other two layers run. Latched: once an answer is chosen it is
## held for the action's duration, because re-deciding mid-dash is how a bot ends up
## dashing nowhere, repeatedly.
static func _reflex(bb: Dictionary, profile: Dictionary, m: Memory, now: float,
		evaluated: Array) -> Dictionary:
	# Still committed to the last answer.
	if now < m.dodge_until and m.dodge_action != "":
		return _reflex_intent(m.dodge_action, m.dodge_dir, now, m)
	# A held guard runs on its own clock: it was pressed EARLY on purpose and must
	# stay down until the blow it was pressed for has arrived.
	if now < m.guard_hold_until:
		return {"guard": true, "move": Vector2.ZERO}

	var worst: Dictionary = {}
	var worst_tti: float = 99.0
	for e: Dictionary in evaluated:
		if not bool(e.get("threatening", false)):
			continue
		if float(e.get("tti", 99.0)) < worst_tti:
			worst_tti = float(e.get("tti", 99.0))
			worst = e
	if worst.is_empty():
		return {}

	# The exit BotDodge solved may point into a pit or into a second live telegraph,
	# so it is re-scored against everything else on the board before being trusted.
	var exit: Vector2 = worst.get("exit", Vector2.ZERO)
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var need: float = float(worst.get("exit_len", 0.0))
	# THE DEGENERATE CASE, AND WHY IT IS THE COMMON ONE. Every telegraph in this game
	# SNAPSHOTS the target's position and plants its circle there — so at the instant
	# it blooms, a bot standing still is exactly at the centre and there is no
	# "shortest way out": every direction is equally long. BotDodge reports that
	# rather than inventing a direction, and here is where it gets answered, by open
	# ground instead of by geometry. Left untreated the ladder returns `none` and the
	# bot stands in the blast it was told about — the single most visible way this
	# whole layer could fail.
	var candidates: Array[Vector2]
	if bool(worst.get("degenerate", false)) or exit.length_squared() <= 0.01:
		# Ordered AWAY FROM THE FOE first. safest_exit breaks ties by shortness and
		# then by order, so with equal-length options this is what decides — and
		# "when every direction is the same length, do not dive toward the person
		# hitting you" is the right tiebreak, as well as the one that stops every
		# bot in the game dodging left forever.
		var foe_pos: Vector2 = bb.get("foe_pos", me + Vector2.RIGHT)
		var away: float = signf(me.x - foe_pos.x)
		if away == 0.0:
			away = 1.0
		candidates = [Vector2(away, 0.0) * need, Vector2(-away, 0.0) * need,
			Vector2(0.0, -need)]
	else:
		# The mirrored exit is a genuine second option, not a fallback: for a lane or
		# a circle, stepping out the other side is equally valid geometry and is often
		# the only one that is not over a pit.
		candidates = [exit, -exit]
	var safe_exit: Vector2 = _safest(bb, me, candidates, worst)
	worst = worst.duplicate()
	worst["exit"] = safe_exit
	worst["exit_len"] = safe_exit.length()

	var caps: Dictionary = _caps(bb, profile, m, now, worst)
	var choice: Dictionary = BotDodge.choose_response(worst, caps)
	var action: String = String(choice.get("action", "none"))
	var dir: Vector2 = choice.get("dir", Vector2.ZERO)

	# THE CLASH READ. Nothing in the ladder was affordable and the threat is a body
	# in my face — so an aggressive bot answers a swing with a swing rather than
	# standing there. MeleeClash resolves two blows declared in the same window by
	# throwing both fighters apart, which is both the correct play and the single
	# most watchable thing two bots can do to each other.
	if action == "none" or action == "walk":
		if _clash_worthwhile(bb, profile, m, now, worst):
			m.dodge_action = "clash"
			m.dodge_until = now + MELEE_COOLDOWN
			m.dodge_dir = dir
			m.last_fire_at = now
			return _reflex_intent("clash", dir, now, m)
	if action == "none":
		return {}
	if action == "walk":
		# Walking out is not an ANSWER, it is an interest override handed to the
		# steering layer — so it must not preempt the utility layer. A bot that
		# stopped casting because it was strafing would never cast at all.
		return {}

	# ⚠ NEVER LATCH AN ANSWER THE BODY CANNOT EXPRESS. `_reflex_intent` turns a dash
	# or a blink into a movement-key press, and `_flatten` has to drop any purely
	# vertical component because there is no "walk down" on this body. If that leaves
	# an EMPTY movement vector the press goes out with no direction, the bot burns a
	# cooldown, and — far worse — `dodge_until` freezes the whole reflex layer for the
	# length of the latch while the bot stands in the attack. Falling through to the
	# steering layer is strictly better than a latched no-op: at least the bot keeps
	# walking out. Belt-and-braces behind the ladder's own ordering fix in BotDodge.
	if (action == "dash" or action == "blink") and _flatten(dir) == Vector2.ZERO:
		return {}

	m.dodge_action = action
	m.dodge_dir = dir
	m.dodge_until = now + DODGE_LATCH
	if action == "dash" or action == "dash_iframe":
		m.last_dash_at = now
	elif action == "blink":
		m.last_blink_at = now
	elif action == "parry":
		m.last_guard_at = now
		# Press EARLY and hold. The perfect band opens ~0.37 s into the shrink, so
		# a guard pressed on contact has already lost; guard_hold_until is what
		# carries the press across the frames until the blow lands.
		m.guard_hold_until = now + GUARD_SHRINK + GUARD_HOLD_TAIL
	return _reflex_intent(action, dir, now, m)


## Ladder action -> the buttons that express it. The mapping is the only place the
## brain knows what a "dash" costs a body, which is what keeps the ladder itself
## body-agnostic.
static func _reflex_intent(action: String, dir: Vector2, _now: float,
		_m: Memory) -> Dictionary:
	match action:
		"dash", "dash_iframe":
			# The dash fires along the MOVEMENT vector, not the aim — so the move
			# key has to be set in the same frame as the dash press or the dash goes
			# wherever the bot happened to already be walking.
			return {"dash": true, "move": _flatten(dir)}
		"blink":
			return {"dash": true, "move": _flatten(dir)}
		"parry":
			return {"guard": true, "move": Vector2.ZERO}
		"jump":
			return {"jump": true, "move": Vector2(_flatten(dir).x, -1.0)}
		"clash":
			return {"fire": true, "move": _flatten(dir) * 0.4}
	return {}


## What this body can currently do, in the shape BotDodge.choose_response reads.
##
## READINESS IS ASSUMED PESSIMISTICALLY. When the blackboard does not publish a
## cooldown we hold ourselves to the body's real one from our own last press,
## rather than assuming ready — assuming ready is a cheat by omission and would
## show up in play as a bot dashing four times a second.
static func _caps(bb: Dictionary, profile: Dictionary, m: Memory, now: float,
		threat: Dictionary) -> Dictionary:
	var dash_ready: bool = _ready_flag(bb, "dash_ready", CD_DASH_INDEX,
		now - m.last_dash_at >= DASH_COOLDOWN)
	var blink_ready: bool = bool(bb.get("blink_ready", now - m.last_blink_at >= BLINK_COOLDOWN))
	var sigil: bool = int(bb.get("guard_style", 0)) == 1
	var rearm: float = GUARD_REARM_SIGIL if sigil else GUARD_REARM_BLADE
	var guard_ready: bool = _ready_flag(bb, "guard_ready", CD_GUARD_INDEX,
		now - m.last_guard_at >= GUARD_SHRINK + rearm)
	# THE GUARD IS PRESSED EARLY, SO ITS "WINDOW" IS A LEAD TIME, NOT A REACTION
	# WINDOW. We want the blow to arrive in the middle of the shrinking ring's
	# perfect band; guard skill decides how near that middle we aim, and the
	# remainder becomes a real mistiming that really eats the hit.
	var band: float = GUARD_BAND_SIGIL if sigil else GUARD_BAND_BLADE
	var skill: float = BotProfile.get_f(profile, "guard")
	var slack: float = lerpf(0.16, 0.03, clampf(skill, 0.0, 1.0))
	var tti: float = float(threat.get("tti", 99.0))
	var in_lead: bool = absf(tti - band) <= slack
	return {
		"dash_ready": dash_ready,
		"dash_dist": DASH_DIST,
		"blink_ready": blink_ready,
		"blink_dist": BLINK_DIST,
		"can_parry": bool(bb.get("can_parry", true)) and bool(threat.get("parryable", true)),
		"parry_ready": guard_ready and in_lead,
		# choose_response gates the parry rung on `tti <= parry_window`, and the lead
		# test above has already decided the timing — so pass a value that lets it
		# through iff we meant it to.
		"parry_window": 99.0 if in_lead else -1.0,
		"grounded": bool(bb.get("on_floor", true)),
		"allow_iframe": BotProfile.get_b(profile, "iframe"),
	}


## Candidate exits, re-scored against pits and every OTHER live danger footprint,
## and the best one returned. Dodging out of a blast into a pit is the most
## embarrassing thing a bot can do and it is entirely avoidable, so nothing gets
## trusted until it has been through here.
static func _safest(bb: Dictionary, me: Vector2, candidates: Array[Vector2],
		threat: Dictionary) -> Vector2:
	var hazards: Array[Rect2] = []
	for h: Variant in bb.get("hazards", []):
		if typeof(h) == TYPE_RECT2:
			hazards.append(h)
	var regions: Array[Dictionary] = []
	for t: Variant in bb.get("threats", []):
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = t
		# Skip the threat we are already solving for: it is the thing we are leaving,
		# and counting it would score every exit as landing in danger.
		if int(d.get("id", 0)) == int(threat.get("id", -1)):
			continue
		if d.has("shape"):
			regions.append(d)
		elif float(d.get("radius", 0.0)) > 0.0:
			regions.append({"shape": "circle", "center": d.get("pos", Vector2.ZERO),
				"radius": float(d.get("radius", 0.0))})
	var first: Vector2 = candidates[0] if not candidates.is_empty() else Vector2.ZERO
	if hazards.is_empty() and regions.is_empty():
		return first
	var best: Vector2 = BotDodge.safest_exit(me, candidates, hazards, regions)
	# safest_exit returns ZERO when EVERY option lands somewhere lethal. That is a
	# real answer — "there is nowhere good" — and the caller reads it as such rather
	# than being handed a bad exit dressed up as a good one.
	return best


## Should the bot answer a swing with a swing? Only when it genuinely cannot get
## out (the ladder already failed), the threat is at body range, and the profile is
## aggressive enough to want the trade. A timid bot eats the hit instead, which is
## the correct read for it.
static func _clash_worthwhile(bb: Dictionary, profile: Dictionary, m: Memory,
		now: float, threat: Dictionary) -> bool:
	if now - m.last_fire_at < MELEE_COOLDOWN:
		return false
	if BotProfile.get_f(profile, "aggression") < 0.5:
		return false
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var reach: float = float(bb.get("reach", 58.0))
	if me.distance_to(foe) > reach * 1.2:
		return false
	return float(threat.get("tti", 99.0)) <= 0.25


# =========================================================================
# LAYER 2 — CONTEXT STEERING
# =========================================================================

## Where to stand, as a move vector. Interest is the class's spacing band; danger is
## every footprint and pit on the board. This is context steering flattened to one
## axis, which is the right shape for a side-on platformer: the vertical half of the
## decision is a jump, not a Y velocity.
static func _steer(bb: Dictionary, profile: Dictionary, _m: Memory, evaluated: Array,
		pressure: float) -> Vector2:
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var dist: float = me.distance_to(foe)
	var toward: float = signf(foe.x - me.x)
	if toward == 0.0:
		toward = 1.0

	var band: Dictionary = _band(bb, profile)
	var lo: float = float(band["min"])
	var hi: float = float(band["max"])
	var centre: float = (lo + hi) * 0.5
	var width: float = maxf(hi - lo, 1.0)

	var want: float = 0.0
	if dist > hi + width * BAND_DEADZONE:
		want = toward                    # too far — close in
	elif dist < lo - width * BAND_DEADZONE:
		want = -toward                   # too close — back off
	# Inside the band the bot HOLDS. A deadband is what turns "oscillates across the
	# ideal distance forever" into a stance you can read.

	# COVER. A wall between me and the foe is worth standing behind when I am hurt,
	# so the urge to cross it is damped rather than vetoed — vetoed would leave a
	# low bot cowering behind a wall that is about to expire.
	var hp: float = float(bb.get("self_hp_frac", 1.0))
	if hp < 0.4 and _cover_between(bb, me, foe):
		want *= 0.25

	# DANGER. Score the two lateral steps (and standing still) against the pits and
	# the live footprints, and take the best. Reusing the dodge module's scorer here
	# is deliberate: "never walk into a pit" and "never dodge into a pit" must be the
	# same rule or the bot will learn to stroll into the one it just dived out of.
	var probe: Vector2 = Vector2(want, 0.0) * STEER_PROBE
	if probe != Vector2.ZERO:
		var options: Array[Vector2] = [probe, -probe]
		var vetted: Vector2 = _safest(bb, me, options, {})
		# ZERO here means BOTH directions land somewhere lethal, so the answer is
		# "hold this spot" — walking off a ledge to maintain a spacing band is not a
		# spacing band worth maintaining.
		want = signf(vetted.x) if absf(vetted.x) > 0.01 else 0.0

	# Under real pressure with nowhere useful to be, drift AWAY rather than stand
	# still: a stationary target is the easiest thing in the game to telegraph onto.
	if want == 0.0 and pressure > 0.7:
		want = -toward

	# A vertical exit that the reflex layer did not take (it was not urgent enough to
	# preempt) still deserves a jump — the ledge geometry is the same either way.
	var up: float = 0.0
	for e: Dictionary in evaluated:
		if not bool(e.get("threatening", false)):
			continue
		var ex: Vector2 = e.get("exit", Vector2.ZERO)
		if ex.length_squared() > 0.01 and ex.normalized().dot(Vector2.UP) >= BotDodge.VERTICAL_EXIT_DOT:
			up = -1.0
			break
	return Vector2(clampf(want, -1.0, 1.0), up)


## The class's spacing band, pulled toward contact by aggression. One table plus one
## scalar rather than a band per class per difficulty.
static func _band(bb: Dictionary, profile: Dictionary) -> Dictionary:
	var cid: int = int(bb.get("class_id", -1))
	var b: Dictionary = DEFAULT_BAND
	if cid >= 0 and cid < CLASS_BAND.size():
		b = CLASS_BAND[cid]
	var aggr: float = BotProfile.get_f(profile, "aggression")
	# 0.5 aggression = the authored band. 1.0 pulls it 30% closer, 0.0 pushes it 30%
	# further out — the same class, played by two different temperaments.
	var scale: float = lerpf(1.3, 0.7, clampf(aggr, 0.0, 1.0))
	return {"min": float(b["min"]) * scale, "max": float(b["max"]) * scale}


## Is a barrier sitting on the line between me and the foe? Approximate on purpose —
## a point-to-segment distance against each barrier's radius. Precision here would
## buy nothing: the question is "is there something to hide behind", not "by how many
## pixels".
static func _cover_between(bb: Dictionary, me: Vector2, foe: Vector2) -> bool:
	var seg: Vector2 = foe - me
	var len2: float = seg.length_squared()
	if len2 <= 0.01:
		return false
	for b: Variant in bb.get("barriers", []):
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = b
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var t: float = clampf((p - me).dot(seg) / len2, 0.0, 1.0)
		if p.distance_to(me + seg * t) <= float(d.get("radius", 40.0)):
			return true
	return false


# =========================================================================
# LAYER 3 — THE UTILITY SCORER
# =========================================================================

## Which slot to press, or -1 for none. Rate-limited to once per `profile.period`
## and latched in between, so the expensive pass runs a handful of times a second
## and the bot actually finishes the cast it started.
static func _pick_slot(bb: Dictionary, profile: Dictionary, m: Memory, now: float,
		pressure: float, soonest: float) -> int:
	if now < m.latched_until:
		return -1     # already spent this decision; the press was emitted on the frame it was made
	if now < m.next_decision_at:
		return -1
	m.next_decision_at = now + BotProfile.get_f(profile, "period")
	# Re-sample the aim scatter on the same beat as the decision. Per-frame sampling
	# would average to a perfect shot over a channel; per-decision sampling means the
	# bot commits to one wrong angle, which is what missing looks like.
	var err: float = BotProfile.get_f(profile, "aim_error")
	m.aim_error = m.rng.randf_range(-err, err)

	var scores: Array = score_slots(bb, profile, m, now, pressure, soonest)
	var best: int = -1
	var best_score: float = CAST_THRESHOLD
	for i: int in range(scores.size()):
		if float(scores[i]) > best_score:
			best_score = float(scores[i])
			best = i
	return best


## Every slot scored. Public so the tests can assert the SHAPE of a decision — that
## the escape outscores the ult when the bot is cornered — rather than only its
## outcome, which would pass for the wrong reason as easily as the right one.
##
## IAUS-shaped: each consideration is a normalised 0..1 factor and they MULTIPLY, so
## any single hard "no" (on cooldown, cannot afford it, out of range, would be
## interrupted) zeroes the slot without needing to out-shout the other terms. The
## role weight and the combo bonus are the only additive parts, and both sit on top
## of the product.
static func score_slots(bb: Dictionary, profile: Dictionary, m: Memory, now: float,
		pressure: float, soonest: float) -> Array:
	var cooldowns: Array = bb.get("cooldowns", [])
	var facts: Array = _kit_facts(int(bb.get("class_id", -1)))
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var foe_vel: Vector2 = bb.get("foe_vel", Vector2.ZERO)
	var dist: float = me.distance_to(foe)
	var hp: float = float(bb.get("self_hp_frac", 1.0))
	var mp: float = float(bb.get("self_mp_frac", 1.0))
	var foe_hp: float = float(bb.get("foe_hp_frac", 1.0))
	var risk: float = BotProfile.get_f(profile, "risk")
	var aggr: float = BotProfile.get_f(profile, "aggression")
	var combo_w: float = BotProfile.get_f(profile, "combo")
	# Is the foe committing toward me? A closing foe is a predictable foe, which is
	# what makes a payoff or an ult worth spending rather than saving.
	var to_me: Vector2 = (me - foe)
	var closing: float = 0.0
	if to_me.length() > 1.0 and foe_vel.length() > 1.0:
		closing = clampf(foe_vel.normalized().dot(to_me.normalized()), 0.0, 1.0)

	var out: Array = []
	for i: int in range(SLOT_COUNT):
		out.append(0.0)
	for i: int in range(SLOT_COUNT):
		# --- hard gates. Any one of these makes the slot unavailable, full stop.
		if i < cooldowns.size() and float(cooldowns[i]) > 0.0:
			continue
		if i >= cooldowns.size():
			continue
		var f: Dictionary = facts[i] if i < facts.size() else _default_facts(i)
		if mp * 100.0 < float(f["mp_cost"]):
			continue
		var range_fit: float = _range_fit(dist, float(f["range"]), bool(f["close_ok"]))
		if range_fit <= 0.0:
			continue
		# THE CHANNEL GATE, and the reason it is a gate rather than a weight. A
		# levitating channel is interrupted by ANY landed hit, so starting one with
		# something already resolving inside the cast time is not a risky play, it is
		# a spell thrown away. `risk` only decides how much CLEAR AIR past the cast
		# time the bot insists on — never whether the rule applies.
		var ct: float = float(f["cast_time"])
		var safety: float = 1.0
		if ct > 0.01:
			if soonest < ct + CHANNEL_MARGIN:
				continue
			safety = lerpf(0.55, 1.0, clampf(risk, 0.0, 1.0))

		# --- role weight: the situational half of the score.
		#
		# ⚠ MATCHED ON THE ROLE, NOT ON THE SLOT INDEX, and that changed when the hand
		# shrank to three buttons. Slot index used to BE the role for every class, so
		# `match i:` was exact. Now each class carries its damage line, its ult, and
		# ONE utility spell chosen from control / answer / payoff — so slot 1 is
		# zoning for the Arcanist and an escape for the Brawler, and matching on the
		# index would have scored every class's utility slot with whichever arm
		# happened to be written first. (It did, briefly: with the three role
		# constants aliased to the same index, GDScript's `match` silently took the
		# CONTROL arm for every class and the ANSWER and PAYOFF arms became dead code
		# that nothing reported.) `_kit_facts` carries the authored role per slot, so
		# the honest question is cheap to ask.
		var role: float = 0.0
		match String(f.get("role", "")):
			"damage":
				# The reliable line, and the default answer to "nothing special is
				# happening". Devalued under pressure — when things are landing on
				# you the answer slot should be winning, not this.
				role = (0.50 + 0.15 * aggr) * (0.60 + 0.40 * (1.0 - pressure))
			"control":
				# Zoning is worth most against a foe who is COMING TO YOU: a field
				# dropped on empty floor is a field nobody has to walk through. That
				# is the whole term — the base is deliberately under the damage line
				# so a bot does not zone at a foe who is standing still.
				role = 0.35 + 0.30 * closing
			"answer":
				# The get-out. Scales with BOTH how hurt and how pressed we are, so a
				# healthy bot keeps its escape and a cornered one spends it.
				role = 0.20 + 0.80 * maxf(pressure, 1.0 - hp)
			"payoff":
				# The biggest non-ult hit, and the one you set up for: worth spending
				# only when the foe is committed and I am not the one under pressure.
				role = 0.55 * clampf(0.30 + 0.45 * closing + 0.20 * (1.0 - pressure), 0.0, 1.0)
			"ult":
				# WILL IT LAND? A finisher against a hurt foe, a punish against a
				# closing one, and worth much less thrown at a healthy foe who is
				# keeping their distance. This is what stops the ult being dumped into
				# an empty arena the instant it comes off cooldown — and what makes it
				# beat everything else in the kit when the kill is actually there.
				var finisher: float = clampf(1.15 - foe_hp, 0.0, 1.0)
				role = 0.95 * clampf(0.15 + 0.55 * finisher + 0.35 * closing, 0.0, 1.0)
		var score: float = role * range_fit * safety

		# --- the anti-spam term. Decays over RECENCY_TAU, so a slot is not banned,
		# only devalued while it is still fresh in the fight.
		var last: float = float(m.last_slot_at.get(i, -99.0))
		var since: float = now - last
		if since < RECENCY_TAU:
			score *= 1.0 - RECENCY_PENALTY * exp(-since / RECENCY_TAU)

		# --- combos, both directions. Weighted by the profile so a low tier fights
		# with single spells and a high tier plays the reaction matrix.
		score += _combo_bonus(bb, m, now, i, f, facts, cooldowns, mp) * combo_w
		score -= _combo_penalty(bb, me, foe, f)
		out[i] = maxf(score, 0.0)
	return out


## How well the foe's distance suits this slot.
##
## The far end is the same for everything: at the edge of a spell's range the foe
## only has to take one step, so the fit falls away well before the hard cut-off.
##
## THE NEAR END IS SHAPE-DEPENDENT, and getting that wrong is the difference between
## a bot that fights and one that backs off to cast a lance it could have fired
## point-blank. A lance, a rush, a wall and a nova all START AT THE CASTER and are
## perfectly good in your face. A PLACED bombardment — a meteor, a ray, a pillar, a
## field — is a telegraphed circle you drop on the ground, so dropping it at your own
## feet means standing in it. Only those are penalised close in (`close_ok` false).
static func _range_fit(dist: float, usable: float, close_ok: bool) -> float:
	if usable <= 0.0:
		return 0.5
	var r: float = dist / usable
	if r > 1.0:
		return 0.0
	if not close_ok:
		if r < 0.15:
			return 0.35
		if r < 0.30:
			return lerpf(0.35, 1.0, (r - 0.15) / 0.15)
	if r <= 0.85:
		return 1.0
	return lerpf(1.0, 0.15, (r - 0.85) / 0.15)


## The combo layer, and the thing that produces the clip. Two directions:
##   CASH IN  — the field is already down, so complete it.
##   SET UP   — no field yet, but I hold both halves and both are ready, so lay the
##              first one BECAUSE of the second. This is the bot deciding to drop a
##              frost field so it can fire lightning through it, which is exactly the
##              behaviour that makes a bot fight look designed rather than random.
static func _combo_bonus(bb: Dictionary, m: Memory, now: float, slot: int,
		f: Dictionary, facts: Array, cooldowns: Array, mp: float) -> float:
	var elem: int = int(f["element"])
	var bonus: float = 0.0

	# --- cash in a live FIELD.
	for fld: Variant in bb.get("fields", []):
		if typeof(fld) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = fld
		for row: Dictionary in COMBO_SETUPS:
			if int(d.get("element", -1)) != int(row["field"]):
				continue
			if int(row["then"]) != -1 and int(row["then"]) != elem:
				continue
			bonus = maxf(bonus, 0.70 * float(row["payoff"]))

	# --- cash in against a live BARRIER: bring the element that answers it.
	for bar: Variant in bb.get("barriers", []):
		if typeof(bar) != TYPE_DICTIONARY:
			continue
		var d2: Dictionary = bar
		for row: Dictionary in COMBO_BARRIERS:
			if int(d2.get("element", -1)) == int(row["barrier"]) and int(row["then"]) == elem:
				bonus = maxf(bonus, 0.55 * float(row["payoff"]))

	# --- SET UP: is this slot the first half of a combo whose second half I am
	# holding, ready and affordable? Only field-shaped slots can set one up.
	if bool(f["makes_field"]):
		for row: Dictionary in COMBO_SETUPS:
			if int(row["field"]) != elem:
				continue
			for j: int in range(facts.size()):
				if j == slot:
					continue
				if j < cooldowns.size() and float(cooldowns[j]) > 0.0:
					continue
				var other: Dictionary = facts[j]
				if int(row["then"]) != -1 and int(other["element"]) != int(row["then"]):
					continue
				# No point laying half a combo whose other half I cannot pay for.
				# Checked against CURRENT mana rather than the sum of both costs: mana
				# regenerates, and demanding both up front would make the two most
				# expensive halves in any kit un-comboable forever.
				if mp * 100.0 < float(other["mp_cost"]):
					continue
				bonus = maxf(bonus, 0.50 * float(row["payoff"]))

	# --- THE SELF-COMBO. Two of my OWN beams of opposing elements inside the fusion
	# window fuse into ReactionTable's headline outcome. It is weight-blind and
	# same-owner, so it is available in every fight to any kit holding two beams —
	# the biggest single thing a bot can choose to do on purpose.
	if bool(f["is_beam"]) and m.last_beam_element >= 0 \
			and now - m.last_beam_at <= FUSION_WINDOW \
			and ReactionTable.opposed(m.last_beam_element, elem):
		bonus = maxf(bonus, 0.85)
	return bonus


## The mirror image: spells that a live barrier would EAT. ReactionTable's
## `ground_out` consumes a lightning beam against an earth wall outright, so this is
## a penalty rather than an absent bonus — the bot must actively avoid donating the
## spell, not merely fail to be rewarded for it.
static func _combo_penalty(bb: Dictionary, me: Vector2, foe: Vector2,
		f: Dictionary) -> float:
	var seg: Vector2 = foe - me
	var len2: float = seg.length_squared()
	if len2 <= 0.01:
		return 0.0
	for bar: Variant in bb.get("barriers", []):
		if typeof(bar) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = bar
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var t: float = clampf((p - me).dot(seg) / len2, 0.0, 1.0)
		if p.distance_to(me + seg * t) > float(d.get("radius", 40.0)):
			continue    # not on the firing line, so it eats nothing
		for row: Dictionary in COMBO_AVOID:
			if int(d.get("element", -1)) == int(row["barrier"]) \
					and int(f["element"]) == int(row["then"]):
				return float(row["penalty"])
	return 0.0


## Book-keeping after a cast is committed: the recency term, the fusion window, and
## the latch that stops the brain immediately re-deciding.
static func _note_cast(bb: Dictionary, m: Memory, slot: int, now: float) -> void:
	m.last_slot_at[slot] = now
	m.latched_slot = slot
	m.latched_until = now + CAST_LATCH
	var facts: Array = _kit_facts(int(bb.get("class_id", -1)))
	if slot < facts.size() and bool(facts[slot]["is_beam"]):
		m.last_beam_element = int(facts[slot]["element"])
		m.last_beam_at = now


## The basic attack. Deliberately dumb and deliberately constant: a bot that only
## acts when a spell is off cooldown reads as idle between casts, and the fists are
## what keep pressure on in the gaps. Rate-limited to the body's own melee cooldown
## so it is not spamming a button the body would ignore anyway.
static func _wants_fire(bb: Dictionary, _profile: Dictionary, m: Memory, now: float,
		_evaluated: Array) -> bool:
	if not _ready_flag(bb, "fire_ready", CD_PRIMARY_INDEX,
			now - m.last_fire_at >= MELEE_COOLDOWN):
		return false
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	return me.distance_to(foe) <= float(bb.get("reach", 58.0)) * 1.1


# =========================================================================
# AIM
# =========================================================================

## Where to point. A LEAD on the foe's current velocity plus a bounded error.
##
## THE ERROR IS THE POINT, not a concession. No-auto-aim is a locked design rule:
## the bot points a direction and the shot goes there whether or not anyone is
## standing in it. The lead makes it a competent shot; the error, sampled once per
## decision and held, makes it a shot that can miss. Both halves are needed — lead
## with no error is a homing missile, error with no lead is a bot that cannot hit a
## moving target at all.
static func _aim(bb: Dictionary, _profile: Dictionary, m: Memory, _now: float) -> Vector2:
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	var foe_vel: Vector2 = bb.get("foe_vel", Vector2.ZERO)
	var to_foe: Vector2 = foe - me
	# Flight time against the hero bolt speed (Spell.SPEED 460). Close enough for
	# every projectile in the game and irrelevant for the instant ones.
	var lead_t: float = clampf(to_foe.length() / 460.0, 0.0, 0.5)
	var aim: Vector2 = (foe + foe_vel * lead_t) - me
	if aim.length_squared() < 0.01:
		aim = Vector2(signf(float(bb.get("facing", 1.0))), 0.0)
		if aim == Vector2.ZERO:
			aim = Vector2.RIGHT
	return aim.normalized().rotated(m.aim_error)


# =========================================================================
# KIT FACTS
# =========================================================================

## The five slots of a class, reduced to what the scorer needs. Read from
## SpellLibrary rather than restated here: a second copy of the kit table would be
## wrong the first time a spell is retuned, and this brain would go on confidently
## scoring a spell that no longer exists.
##
## Cached per class for the process. build_for_class mints fresh Resources each call
## (correctly — they are mutable), so calling it per bot per frame would be pure
## garbage collection.
static func _kit_facts(class_id: int) -> Array:
	if class_id < 0:
		return _generic_facts()
	if _kit_cache.has(class_id):
		return _kit_cache[class_id]
	var spells: Array = SpellLibrary.build_for_class(class_id)
	var roles: Array = SpellLibrary.slot_roles_for_class(class_id)
	var out: Array = []
	for i: int in range(SLOT_COUNT):
		if i >= spells.size():
			out.append(_default_facts(i))
			continue
		var s: SpellDef = spells[i]
		var form: int = ReactionTable.form_for_kind(s.kind)
		out.append({
			"id": s.id,
			# WHICH ROLE THIS CLASS PUT HERE. The situational scorer matches on this
			# rather than on the slot index, because with a three-spell hand the
			# middle slot is control / answer / payoff depending on the class.
			"role": String(roles[i]) if i < roles.size() else "",
			"element": s.element,
			"kind": s.kind,
			"cast_time": s.cast_time,
			"mp_cost": float(s.mp_cost),
			"tier": SpellTier.of(s),
			"range": _effective_range(s),
			# A FIELD or a BARRIER is a thing that stays on the floor, which is what
			# the combo layer means by "sets one up".
			"makes_field": form == ReactionTable.Form.FIELD or form == ReactionTable.Form.BARRIER,
			"is_beam": form == ReactionTable.Form.BEAM,
			"close_ok": not _is_placed(s.kind),
		})
	_kit_cache[class_id] = out
	return out


## HOW FAR THIS SPELL ACTUALLY WORKS — and the one place `SpellDef.reach` must not
## be read uniformly, because it is three different things depending on the kind:
##   · a CAST-RANGE clamp for the placed bombardments (meteor, ray, pillar, zone,
##     blink-strike) — the only case where "reach" means what it sounds like;
##   · a HOP range for CHAIN, a TRAVEL BUDGET for CRAWLER / THROWN_ANCHOR / ARC;
##   · the SIZE of the thing for WALL / ICE_WALL / WARD, where it says nothing at
##     all about range. Reading it as range there would have the bot standing 90 px
##     from the foe to drop a wall, which is the opposite of what a wall is for.
## Getting this wrong is invisible in code review and obvious in play, which is why
## it is one function with the cases named.
static func _effective_range(s: SpellDef) -> float:
	match s.kind:
		SpellDef.Kind.BEAM, SpellDef.Kind.RUSH, SpellDef.Kind.ARC:
			return s.length
		SpellDef.Kind.WALL, SpellDef.Kind.ICE_WALL, SpellDef.Kind.WARD:
			# Cast at arm's length, between me and the thing I am shaping the floor
			# against. `reach` here is the wall's own size.
			return 220.0
		SpellDef.Kind.FLURRY:
			return 110.0     # a melee arc across the front
		SpellDef.Kind.TETHER:
			return 320.0     # the lashed hook's travel
		SpellDef.Kind.MISSILES:
			return 600.0     # thrown orbs, no declared range
		SpellDef.Kind.BOULDER:
			return 560.0
		SpellDef.Kind.NOVA:
			return maxf(s.radius, 120.0)   # self-centred: aim is ignored entirely
	# Everything else — the placed bombardments, CHAIN, CRAWLER, THROWN_ANCHOR —
	# genuinely uses `reach`.
	return s.reach if s.reach > 0.0 else 300.0


## Is this spell DROPPED ON A SPOT rather than fired from the hand? The distinction
## the near-range penalty turns on: these all plant a telegraphed footprint on the
## ground, so casting one at your own feet means standing in your own spell.
## BLINK_STRIKE is placed but deliberately absent — it puts you AT the point, which
## is the one case where "on top of it" is the intended outcome.
static func _is_placed(kind: int) -> bool:
	match kind:
		SpellDef.Kind.METEOR, SpellDef.Kind.DIVINE_RAY, SpellDef.Kind.CONVERGENCE, \
		SpellDef.Kind.PILLAR, SpellDef.Kind.ZONE:
			return true
	return false


## What the scorer assumes when the blackboard did not say which class this is. The
## bot still fights — it just cannot reason about elements (so combos are inert) or
## about channels (so nothing is gated as a channel), and its ranges are the
## role's typical shape rather than its actual spell's.
## Stand-in facts for a slot with no real spell behind it (an unknown class, or a
## hand that came up short). The role names are the DEFAULT three-button layout —
## damage, one utility spell, the ult — which is what a class with no authored
## `SLOT_ROLES` row falls back to in `SpellLibrary.slot_roles_for_class`.
static func _default_facts(role: int) -> Dictionary:
	const ROLE_NAMES: Array[String] = ["damage", "control", "ult"]
	var ranges: Array[float] = [520.0, 300.0, 640.0]
	var costs: Array[float] = [45.0, 55.0, 72.0]
	var idx: int = clampi(role, 0, ROLE_NAMES.size() - 1)
	return {
		"id": "", "element": -1, "kind": SpellDef.Kind.BEAM, "role": ROLE_NAMES[idx],
		"cast_time": 0.0, "mp_cost": costs[idx],
		"tier": SpellTier.Tier.HEAVY, "range": ranges[idx],
		"makes_field": ROLE_NAMES[idx] == "control", "is_beam": false,
		"close_ok": true,
	}


static func _generic_facts() -> Array:
	var out: Array = []
	for i: int in range(SLOT_COUNT):
		out.append(_default_facts(i))
	return out


# =========================================================================
# SMALL HELPERS
# =========================================================================

## Is a button ready? Three sources, in order of how much they are trusted:
##   1. an explicit boolean on the blackboard — the caller said so outright;
##   2. the extra cooldown index the body seam publishes past the five slots, if the
##      array is long enough to have one (see CD_*_INDEX);
##   3. our OWN book-keeping against the body's real cooldown constant.
##
## Case 3 is the one that matters for fairness: when nobody has told us, we hold
## ourselves to the real timer instead of assuming ready. Assuming ready is a cheat
## by omission, and it would show up in play as a bot dashing four times a second.
static func _ready_flag(bb: Dictionary, key: String, cd_index: int,
		fallback: bool) -> bool:
	if bb.has(key):
		return bool(bb[key])
	var cds: Array = bb.get("cooldowns", [])
	if cd_index < cds.size():
		return float(cds[cd_index]) <= 0.0
	return fallback


## A 2D exit vector expressed the way the intent contract wants it: x is the walk
## axis, y < 0 means "wants up". Flattening rather than passing the raw vector is
## the honest translation for a side-on platformer, where there is no such thing as
## walking upward.
static func _flatten(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.ZERO
	var x: float = clampf(dir.x * 2.0, -1.0, 1.0)
	var y: float = -1.0 if dir.y < -0.5 else 0.0
	return Vector2(x, y)


## Find the memory: the explicit argument, then one parked in the blackboard, then a
## fresh one installed there. See the note on decide() for why the last case is the
## safe degradation and not a silent bug.
static func _resolve_memory(bb: Dictionary, mem: Memory) -> Memory:
	if mem != null:
		return mem
	var parked: Variant = bb.get("mem", null)
	if parked is Memory:
		return parked
	var fresh: Memory = Memory.new()
	bb["mem"] = fresh
	return fresh
