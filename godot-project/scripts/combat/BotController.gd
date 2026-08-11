class_name BotController
extends RefCounted
## THE PER-INSTANCE INPUT SEAM. One of these drives one body; the human's body has
## none and keeps reading the real `Input` singleton.
##
## ⚠ WHY NOT `Input.action_press`, despite `TouchControls` doing exactly that.
## Input state is PROCESS-GLOBAL. TouchControls gets away with pressing real
## actions because there is exactly one local player, so "the virtual buttons" and
## "this player's buttons" are the same set. The moment a second agent exists that
## stops being true in both directions: two bots fight over the same buttons, and
## every button a bot presses ALSO drives the human's hero. There is no way to
## scope a global press to one node, so the seam has to be an object the body
## asks, not a singleton it polls.
##
## The body asks through six methods that mirror Godot's `Input` API 1:1
## (`pressed` / `just_pressed` / `just_released` / `axis` / `vector` /
## `aim_point`), so every call site in the body is a mechanical rename and a null
## controller resolves to the identical `Input` call it replaced. That identity is
## what keeps single-player byte-identical: no controller, no behaviour change,
## not one branch reordered.
##
## THE BRAIN IS PURE AND STAYS THAT WAY. `brain` is duck-typed — anything with
## `decide(blackboard: Dictionary, profile: Dictionary) -> Dictionary`. It never
## touches a node, never reads the tree, and never imports BotIntent. All of the
## dirty work (scanning groups, deriving press edges, translating slot indices
## into this class's actual buttons) happens here.
##
## FAIRNESS IS ENFORCED AT THIS SEAM, not by convention in the brain. The
## blackboard is assembled from things a human can see ON SCREEN: drawn telegraph
## rings, projectiles in flight, the floating HP/MP bars, the pit geometry, and
## the bot's OWN ability bar. There is deliberately no enemy-cooldown field, no
## pre-spawn foreknowledge, and no aim assist — the aim is a direction the brain
## chose, and it can miss. Difficulty belongs in the brain's reaction delay and
## whiff rate; a brain cannot cheat with information it was never handed.

# ---- action vocabulary ------------------------------------------------------
## The button every kit spell is cast through. All five slots share it: the SLOT
## is chosen by `Hero.bot_select_signature`, and then this fires whatever is
## selected — the same two-step a player performs with V and then G.
const CAST_ACTION: StringName = &"ultimate"

## The three class ABILITY buttons, one intent key each. Not `cast_slot` values:
## they are a different system from the kit (no MP, no role, no reaction
## identity), and conflating them is what made a brain unable to reason about
## either.
const ABILITY_ACTIONS: Dictionary = {
	BotIntent.ABILITY_BLAST: &"blast",   # Q
	BotIntent.ABILITY_BLINK: &"blink",   # R
	BotIntent.ABILITY_NOVA: &"nova",     # T
}

## Actions a bot may NEVER press, whatever its intent says, enforced by a hard
## `false` in `just_pressed` rather than by asking brains to behave.
##
## These are not "cosmetic and therefore pointless" — they are actively
## destructive. `switch_class` writes through to `GameState.selected_class`, so a
## bot re-rolling its class corrupts the PLAYER'S saved pick; `cycle_element` /
## `cycle_colourway` make a bot flicker through eight identities while you are
## trying to read who it is.
##
## ⚠ `cycle_signature` STAYS FORBIDDEN, and a bot still uses its whole kit. That
## looks contradictory and is worth being explicit about: cycling is the shared V
## key, it walks the selection one step per press, and driving it through global
## `Input` would move the HUMAN'S selection too. A bot picks by INDEX instead —
## `Hero.bot_select_signature(slot)` — which is instant, private to that body, and
## silent on the HUD. Forbidding the action and adding the setter are two halves
## of the same fix, not a tension.
const FORBIDDEN: Array[StringName] = [
	&"cycle_element", &"cycle_colourway", &"switch_class", &"cycle_signature",
]

# ---- perception constants ---------------------------------------------------
## Fallback travel speeds, used only when a projectile does not publish
## `travel_velocity()`. They mirror `Spell.SPEED` (460) and
## `EnemyProjectile.SPEED` (260); duplicated as literals rather than referenced,
## so this file adds no compile-chain dependency to the two hottest scripts in
## the game (the `--script` headless harness compiles the whole chain, and a
## needless edge there is how the class-cache trap bites).
const SPELL_SPEED: float = 460.0
const ENEMY_PROJECTILE_SPEED: float = 260.0
## Bolt half-extent used when a projectile is reported as a danger REGION rather
## than as a moving point. Mirrors `Spell.BOLT_RADIUS`.
const PROJECTILE_REGION_RADIUS: float = 6.0
## How far down the aim a placed spell lands when there is no foe to range off.
## Placed kinds clamp to their own reach anyway; this only decides the point.
const DEFAULT_AIM_RANGE: float = 260.0
const MIN_AIM_RANGE: float = 40.0
const MAX_AIM_RANGE: float = 900.0

## Anything with `decide(bb: Dictionary, profile: Dictionary) -> Dictionary`.
## Untyped on purpose: a brain must be able to exist without importing anything
## from this file, and a test stub is then three lines.
var brain: Object = null
## Free-form per-bot knobs (reaction delay, whiff rate, preferred spacing). Passed
## through to the brain untouched — this layer never reads it, so adding a knob is
## a brain-side change only.
var profile: Dictionary = {}
## PER-BOT, ACROSS FRAMES: the brain's own scratch state — its reaction clock, its
## decision latches, its combo/fusion window. Held here rather than inside the
## brain because a brain is a pure function and must be shareable by every bot in
## the arena; giving them one shared memory would make two bots react as one.
##
## Auto-built on the first tick from the brain's own `Memory` inner class if it
## declares one (looked up through the script constant map, so this file needs no
## compile-time dependency on any particular brain). A brain whose `decide` takes
## only two arguments simply never sees it.
var memory: Object = null
## Last sanitized intent, kept public so a debug overlay (or a test) can read what
## the brain asked for without re-running it.
var intent: Dictionary = BotIntent.empty()
## Last blackboard handed to the brain, for the same reason.
var blackboard: Dictionary = {}

## ---- ADAPTATION (optional; see BotAdapt) -----------------------------------
## What this bot has learned about the human it is fighting, as a `BotAdapt`
## record. EMPTY BY DEFAULT, and an empty record produces a bot that is
## byte-for-byte the shipped one — adaptation is opt-in, per bot, set by whoever
## spawned it.
##
## It hangs off the CONTROLLER rather than off the brain for the same reason
## `memory` does: the brain is a pure function shared by every bot on the map, so
## anything per-bot has to live on this side of the seam.
##
## ⚠ THE FAIRNESS LINE IS DRAWN IN BotAdapt, NOT HERE. This class only calls
## three of its functions; what they are allowed to change (and the four
## difficulty keys they may never touch) is documented and enforced over there.
var adapt: Dictionary = {}
## Per-bot scratch for the camp breaker — see `BotAdapt.anti_camp`.
var adapt_state: Dictionary = {}
## Middle of this bot's own preferred spacing band, in pixels, or -1 to skip the
## spacing half of the adaptation. Supplied by the spawner (which knows the
## class) so this file needs no dependency on the brain's band table.
var band_centre: float = -1.0
## The profile actually handed to the brain last tick — the shaped one when
## adaptation is on. Public so a debug overlay can show what the bot is playing
## with rather than what it was configured with.
var effective_profile: Dictionary = {}

## Held-action snapshots for this frame and the previous one. Press and release
## EDGES are derived by diffing these, so a brain only ever thinks in "held or
## not" and never has to model `just_pressed` itself.
var _held: Dictionary = {}
var _prev_held: Dictionary = {}
## Distance to project `aim_point()` along the aim direction. Tracked from the
## blackboard's foe range so a placed spell lands ON the thing the bot is pointing
## at rather than at an arbitrary fixed offset — the bot still chooses the
## DIRECTION and still misses when that direction is wrong, which is the whole of
## the no-aim-assist rule.
var _aim_range: float = DEFAULT_AIM_RANGE


# ---- the per-frame cycle ----------------------------------------------------

## Build the blackboard, ask the brain, latch the answer. Called by the body once
## per physics frame with its OWN delta.
##
## `now` must be a clock the body advanced on SCALED delta — the same clock the
## player perceives. `Juice.hit_stop` sets `Engine.time_scale = 0.05`, so a bot
## whose reaction timer ran on unscaled time would get a ~20x reflex boost every
## time anything connected. That is a difficulty cheat wearing a physics costume.
func tick(body: Object, now: float) -> Dictionary:
	blackboard = build_blackboard(body, now)
	# ADAPTATION, HALF ONE: the profile the brain thinks with. With no learned
	# record this returns the configured profile unchanged, so the no-adaptation
	# path is not merely equivalent — it is the same dictionary contents.
	effective_profile = profile
	if not adapt.is_empty():
		effective_profile = BotAdapt.shape_profile(profile, adapt, band_centre)
	var raw: Variant = null
	if brain != null and brain.has_method(&"decide"):
		_ensure_memory()
		# BELT AND BRACES: park the memory in the blackboard as well as passing it.
		# `BotBrain._resolve_memory` checks the explicit argument, then `bb["mem"]`,
		# then installs a fresh one — and only the first two survive a blackboard
		# that is rebuilt every frame, which this one is. A brain whose `decide`
		# takes two arguments (a stub, a test double, a future alternative) therefore
		# gets a PERSISTENT memory here rather than the amnesiac degradation, and the
		# arity detection below stops being load-bearing for correctness.
		if memory != null:
			blackboard["mem"] = memory
		# A three-argument brain gets its per-bot memory; a two-argument one still
		# works (and is simply duller, having no reaction clock or latches to keep).
		# The arity is measured from the brain itself rather than assumed, so a
		# stub brain in a test never has to grow a parameter it does not use.
		if _decide_arity() >= 3:
			raw = brain.call(&"decide", blackboard, effective_profile, memory)
		else:
			raw = brain.call(&"decide", blackboard, effective_profile)
	# ADAPTATION, HALF TWO: the decision itself. Runs AFTER the brain on purpose —
	# it may lean an aim or swap one already-committed cast for a different slot,
	# but it can never make the bot press when the scorer declined to. Every gate
	# that decides whether to act at all still belongs to the brain.
	if raw is Dictionary and not adapt.is_empty():
		raw = BotAdapt.shape_intent(raw as Dictionary, blackboard, adapt, effective_profile)
	# LIVENESS, not learning: refuse to settle into a no-damage stalemate. Applied
	# unconditionally (an empty record does not switch it off) because it answers a
	# measured behavioural gap, not a player habit — see BotAdapt.anti_camp.
	# ⚠ THE CAMP BREAKER MOVED INTO THE BRAIN — `BotBrain.decide`, backed by
	# `Memory.camp_state`. It was called from here, and here was the wrong place:
	# this is the INPUT SEAM, and "refuse to settle into a no-damage stalemate" is a
	# decision. Living on the controller meant it only existed for bots that were
	# built with one, so a brain driven by the sim's own seam or by a test had no
	# liveness floor at all — which is exactly where the stalemates were being
	# measured. `BotAdapt.anti_camp` remains the single definition of the rule; only
	# the call site changed. `adapt_state` is kept as a field so an external driver
	# that still wants to apply the rule itself can, and reads empty otherwise.
	_track_aim_range(blackboard)
	var out: Dictionary = drive(raw)
	_apply_signature_choice(body, out)
	return out


## Point the body's ONE cast button at the kit slot the brain asked for, before
## the body reads that button later in the same frame.
##
## This is the half of the kit seam that is not an input press: `cast_slot` is a
## SELECTION and `ultimate` is the TRIGGER, exactly as a player does V-then-G. It
## goes through `Hero.bot_select_signature` — an index setter — and never through
## the `cycle_signature` action, which is shared UI (see FORBIDDEN).
##
## A refused selection (index past the end of this class's kit) also drops the
## press, so a brain bug reads as "nothing happened" rather than as the wrong
## spell being fired on its behalf.
func _apply_signature_choice(body: Object, i: Dictionary) -> void:
	var slot: int = int(i.get(BotIntent.CAST_SLOT, BotIntent.NONE))
	if slot < 0:
		return
	if body == null or not body.has_method(&"bot_select_signature"):
		return
	if not bool(body.call(&"bot_select_signature", slot)):
		_held.erase(CAST_ACTION)


## Build the brain's per-bot scratch state from its own `Memory` inner class, if
## it declares one. Looked up through the script constant map so this file carries
## no compile-time dependency on any particular brain — which is what keeps a
## brain a plain object that imports nothing.
func _ensure_memory() -> void:
	if memory != null or brain == null:
		return
	# ⚠ `brain` IS USUALLY THE SCRIPT ITSELF, NOT AN INSTANCE — and this function
	# assumed the opposite, which silently disabled the entire reflex layer.
	#
	# Every caller in the game does `ctrl.set("brain", load("res://.../BotBrain.gd"))`
	# and relies on `decide` being STATIC. For that object, `get_script()` returns
	# null (a GDScript has no script of its own), so the lookup bailed, `memory`
	# stayed null, and every bot fell back to the "install a fresh Memory in the
	# blackboard" path — into a blackboard that `build_blackboard` rebuilds from
	# scratch every frame. So the bot got a brand-new memory sixty times a second:
	# `reactions` had never seen any threat, `visible()` was false for everything,
	# and NO bot in the game ever dodged, jumped or parried. MEASURED: 36 sim
	# matches across the whole roster reported zero dash, zero guard and zero jump
	# presses. It also re-scored the ability layer every frame instead of once per
	# `profile.period`, which is why slot usage was far more concentrated than the
	# recency term should ever allow.
	var sc: Script = brain as Script
	if sc == null:
		sc = brain.get_script() as Script
	if sc == null:
		return
	var consts: Dictionary = sc.get_script_constant_map()
	var mem_class: Variant = consts.get("Memory")
	if mem_class is GDScript:
		memory = (mem_class as GDScript).new()


## Cached argument count of `brain.decide`. -1 = not measured yet.
var _arity: int = -1


func _decide_arity() -> int:
	if _arity >= 0:
		return _arity
	_arity = 2
	for m: Dictionary in brain.get_method_list():
		if String(m.get("name", "")) == "decide":
			_arity = (m.get("args", []) as Array).size()
			break
	return _arity


## Latch an intent directly, skipping the brain. This is the seam a scripted
## controller (a test, a replay, a cutscene) uses, and it is why `brain` is
## allowed to be null: a controller with no brain is a perfectly good puppet.
func drive(raw: Variant) -> Dictionary:
	intent = BotIntent.sanitized(raw)
	_prev_held = _held
	_held = _actions_of(intent)
	return intent


## Remember how far the foe is so `aim_point()` projects to a useful distance.
func _track_aim_range(bb: Dictionary) -> void:
	if int(bb.get("foe_id", 0)) == 0:
		_aim_range = DEFAULT_AIM_RANGE
		return
	var me: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var foe: Vector2 = bb.get("foe_pos", Vector2.ZERO)
	_aim_range = clampf(me.distance_to(foe), MIN_AIM_RANGE, MAX_AIM_RANGE)


## Which named actions this intent holds down this frame. The one and only place
## slot indices become button names.
func _actions_of(i: Dictionary) -> Dictionary:
	var held: Dictionary = {}
	if bool(i.get(BotIntent.FIRE, false)):
		held[&"cast"] = true
	if bool(i.get(BotIntent.DASH, false)):
		held[&"dash"] = true
	if bool(i.get(BotIntent.JUMP, false)):
		held[&"jump"] = true
	if bool(i.get(BotIntent.GUARD, false)):
		held[&"parry"] = true
	if bool(i.get(BotIntent.SWING, false)):
		held[&"melee"] = true
	for key: StringName in ABILITY_ACTIONS:
		if bool(i.get(key, false)):
			held[ABILITY_ACTIONS[key]] = true
	# Any kit slot holds the ONE cast button; which spell that fires was decided by
	# `_apply_signature_choice`, which runs against the body immediately after this.
	var slot: int = int(i.get(BotIntent.CAST_SLOT, BotIntent.NONE))
	if slot >= 0 and slot < BotIntent.SLOT_COUNT:
		held[CAST_ACTION] = true
	var move: Vector2 = i.get(BotIntent.MOVE, Vector2.ZERO)
	if move.x < 0.0:
		held[&"move_left"] = true
	elif move.x > 0.0:
		held[&"move_right"] = true
	if move.y < 0.0:
		held[&"move_up"] = true
	# ⚠ `move_down` is NEVER held, whatever `move.y` says. On this body holding
	# down is not "walk downward" — it is the limp/ragdoll FLOP toy, which
	# suspends abilities and drops the bot on the floor until released. The
	# downward component still reaches the dash-angle solver through `vector()`,
	# which reads the intent directly instead of going through the held set.
	return held


# ---- the polling API the body talks to (mirrors Input 1:1) ------------------

func pressed(action: StringName) -> bool:
	if FORBIDDEN.has(action) or action == &"move_down":
		return false
	return bool(_held.get(action, false))


func just_pressed(action: StringName) -> bool:
	if FORBIDDEN.has(action) or action == &"move_down":
		return false
	return bool(_held.get(action, false)) and not bool(_prev_held.get(action, false))


func just_released(action: StringName) -> bool:
	if FORBIDDEN.has(action) or action == &"move_down":
		return false
	return bool(_prev_held.get(action, false)) and not bool(_held.get(action, false))


## Analog axis, the shape `Input.get_axis` returns. Only the movement pairs mean
## anything to a bot; everything else reads as centred.
func axis(neg: StringName, pos: StringName) -> float:
	var move: Vector2 = intent.get(BotIntent.MOVE, Vector2.ZERO)
	if neg == &"move_left" and pos == &"move_right":
		return move.x
	if neg == &"move_up" and pos == &"move_down":
		# Read straight off the intent, not off `_held` — this is the path that
		# lets a bot dash DOWNWARD without being able to press the flop button.
		return move.y
	return 0.0


func vector(nx: StringName, px: StringName, ny: StringName, py: StringName) -> Vector2:
	return Vector2(axis(nx, px), axis(ny, py))


## Replaces `get_global_mouse_position()`. Returns a world point along the aim,
## ranged off the foe — see `_aim_range`. A zero aim returns the body's own
## position, which every consumer already treats as "no aim this frame" and which
## makes a brain that forgot to aim visibly do nothing rather than fire right.
func aim_point(from: Vector2) -> Vector2:
	var aim: Vector2 = intent.get(BotIntent.AIM, Vector2.ZERO)
	if aim.length_squared() <= 0.000001:
		return from
	return from + aim.normalized() * _aim_range


# ---- perception: the blackboard --------------------------------------------

## Assemble what this bot is allowed to know, from what is drawn on screen.
##
## The body contributes its OWN state through `bot_body_state()` (so the private
## cooldown timers stay private and any future body type can implement the same
## one method); this function adds everything that requires looking at the world.
##
## FAIRNESS, field by field — every entry is something a human player reads off
## the screen at a glance:
##   self_* / on_floor / facing / reach / cooldowns  your own body and your own
##       ability bar. Note there is NO foe-cooldown field: what the enemy has
##       ready is exactly the hidden information that would make a bot unbeatable.
##   class_id / slot_affordable / slot_cast_time / guard_style / can_parry
##       your own character sheet and your own mana bar — the things a player
##       knows about the class they picked.
##   fields / barriers  live elemental zones and walls, which are large drawn
##       objects. The combo layer reads the same picture you do.
##   foe_pos / foe_vel / foe_facing   where they are, which way they are moving
##       and which way they are turned — all drawn.
##   foe_hp_frac  the floating health bar over their head (CharacterBars).
##   threats      ONLY live drawn tells (`telegraph`) and projectiles already in
##       flight. Nothing that has not spawned yet, and no attack that has no
##       on-screen tell — a boss spectacle that draws its own marker instead of a
##       Telegraph is invisible to a bot exactly as it is hard for a player.
##   hazards      the pit rects, which are drawn stage geometry.
##   now          the bot's own clock, advanced on SCALED delta so hitstop slows
##       its reflexes precisely as much as it slows yours.
static func build_blackboard(body: Object, now: float) -> Dictionary:
	var bb: Dictionary = {
		"self_pos": Vector2.ZERO, "self_vel": Vector2.ZERO,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0,
		"on_floor": true, "facing": 1.0,
		# Defaults for a body that publishes no wall state (a stub, a dummy, an
		# `Enemy`): NOT against anything. Fails OPEN deliberately — a brain that
		# believed it was walled in by default would refuse to walk at all.
		"on_wall": false, "wall_dir": 0.0,
		"self_id": 0,
		"foe_pos": Vector2.ZERO, "foe_vel": Vector2.ZERO,
		"foe_hp_frac": 0.0, "foe_facing": 0.0, "foe_id": 0,
		"threats": [], "hazards": [], "fields": [], "barriers": [],
		"cooldowns": _zero_cooldowns(),
		"reach": 0.0, "now": now,
	}
	if body == null or not (body is Node):
		return bb
	if body.has_method(&"bot_body_state"):
		var own: Dictionary = body.call(&"bot_body_state")
		for k: Variant in own.keys():
			bb[k] = own[k]
	bb["now"] = now
	var node: Node = body as Node
	var tree: SceneTree = node.get_tree()
	if tree == null:
		return bb  # detached body (a bare instance under test) — no world to perceive
	var here: Vector2 = bb.get("self_pos", Vector2.ZERO)
	var hostile: StringName = StringName(str(bb.get("hostile_group", &"enemy")))
	var foe: Node2D = _nearest_in_group(tree, hostile, here, node)
	if foe != null:
		bb["foe_id"] = foe.get_instance_id()
		bb["foe_pos"] = foe.global_position
		bb["foe_vel"] = _velocity_of(foe)
		bb["foe_hp_frac"] = _hp_frac_of(foe)
		bb["foe_facing"] = _facing_of(foe)
		# IS THEIR GUARD UP RIGHT NOW? A ParryRing is a large drawn ring around the
		# fighter — it is the single most visible thing a body can be doing, and
		# "do not swing into a raised guard" is the first read any human makes.
		# Present tense only: this says the ring is on screen this frame, never
		# whether the guard is off cooldown or when it will drop, which would be
		# the hidden information the fairness rule forbids.
		bb["foe_guarding"] = _guarding(foe)
	bb["threats"] = perceive_threats(tree, here, node)
	# ⚠ HAZARDS ARE NOT OPTIONAL. Without them a brain solves a perfectly good exit
	# vector straight into a ring-out pit, which reads as the bot killing itself
	# rather than as a missing blackboard key.
	bb["hazards"] = perceive_hazards(tree)
	# LOOSE SPELLS ON THE FLOOR. Tier 2 floor drops and Tier 3 boss drops are the
	# whole reason a kit changes mid-run, and a bot that cannot see them fights the
	# rest of the floor with the loadout it walked in with while the human upgrades.
	# A `SpellPickup` is a drawn, glowing, stationary object — the most visible thing
	# in the arena — so this costs nothing against the fairness rule.
	bb["pickups"] = perceive_pickups(tree)
	var elemental: Dictionary = perceive_elemental(tree)
	# .get() with a default, not ["..."]. A missing key on a Dictionary is a hard
	# error in GDScript, and an error here ABORTS blackboard construction — the bot
	# then decides on a half-built world rather than merely losing the combo layer.
	bb["fields"] = elemental.get("fields", [])
	bb["barriers"] = elemental.get("barriers", [])
	return bb


## Live elemental FIELDS (ground zones) and BARRIERS (rock / ice walls), each as
## `{element, pos, radius}`. This is the combo layer: lightning through a frost
## field, fire into an ice wall.
##
## Read out of the `SpellReactor` autoload's live registry rather than by group
## scan, because that registry is the only place that knows an effect's ELEMENT
## and its reaction FORM, and because the spectacles themselves are not in any
## group that distinguishes the two. A missing reactor (a bare headless harness)
## yields empty arrays rather than failing.
##
## FAIRNESS: a frost field and an ice wall are large, drawn, obvious things — this
## is the same information a player uses to set up the same combo.
##
## ⚠ Positions come from `reaction_shape()`, never from `global_position`. Nearly
## every spectacle in this family parks at the arena origin and draws in world
## coordinates, so its transform says (0, 0) and would put every field in the
## corner of the map.
static func perceive_elemental(tree: SceneTree) -> Dictionary:
	var out: Dictionary = {"fields": [], "barriers": []}
	var reactor: Node = tree.root.get_node_or_null(^"/root/SpellReactor")
	if reactor == null:
		return out
	var live: Variant = reactor.get(&"_live")
	if not (live is Array):
		return out
	for e: Variant in live as Array:
		if not (e is Dictionary):
			continue
		var entry: Dictionary = e
		var node: Variant = entry.get("node")
		# VALIDITY FIRST, then the type test — the order is the whole fix. `is` on a
		# previously-freed instance THROWS ("Left operand of 'is' is a previously
		# freed instance"), so `node is Node` was evaluated before anything had
		# established the object still existed. The reactor's live registry is
		# swept lazily, so a spectacle freed this frame is still in it — which made
		# this fire on every Swordsaint pairing in the bot sim.
		#
		# Untyped Variant on purpose: assigning an already-freed instance to a
		# typed `Node` variable is itself an error, so the guard would throw on
		# exactly the entries it exists to skip. Same idiom as
		# SpellReactor._sweep_invalid().
		if node == null or not is_instance_valid(node):
			continue
		if not (node is Node):
			continue
		if not (node as Node).has_method(&"reaction_shape"):
			continue
		var form: int = int(entry.get("form", -1))
		var bucket: String = ""
		if form == ReactionTable.Form.FIELD:
			bucket = "fields"
		elif form == ReactionTable.Form.BARRIER:
			bucket = "barriers"
		else:
			continue
		var circle: Dictionary = _bounding_circle((node as Node).call(&"reaction_shape"))
		if circle.is_empty():
			continue
		(out[bucket] as Array).append({
			"element": int(entry.get("element", -1)),
			"pos": circle["pos"],
			"radius": circle["radius"],
		})
	return out


## Collapse a SpellGeometry shape to the `{pos, radius}` a brain reasons with. A
## line becomes the circle that bounds it — deliberately conservative, because a
## brain planning a combo wants "is my target near that wall", not a millimetre
## containment test the reaction layer will re-run properly anyway.
static func _bounding_circle(shape: Dictionary) -> Dictionary:
	match String(shape.get("shape", "")):
		"circle":
			return {"pos": shape.get("center", Vector2.ZERO),
				"radius": float(shape.get("radius", 0.0))}
		"line":
			var a: Vector2 = shape.get("from", Vector2.ZERO)
			var b: Vector2 = shape.get("to", Vector2.ZERO)
			return {"pos": (a + b) * 0.5,
				"radius": a.distance_to(b) * 0.5 + float(shape.get("width", 0.0)) * 0.5}
	return {}


## Every danger currently DRAWN on screen, in the descriptor shape `BotDodge`
## consumes. Three kinds:
##   "circle" — a zone telegraph. Feed to `BotDodge.threat_from_circle` with
##              pos / radius / tti.
##   "lane"   — a line telegraph (the charger's locked lane). Feed to
##              `BotDodge.threat_from_lane` with pos / angle / length / width / tti.
##   "projectile" — something already in flight. Feed to
##              `BotDodge.threat_from_projectile` with pos / vel.
## Every record also carries `region`, the `Telegraph.danger_shape()` form, so the
## whole array drops straight into `BotDodge.safest_exit` as the "do not dodge
## into a second danger" set.
##
## `owner` is the perceiving body: its own projectiles are skipped, because
## knowing where your own bolt is going is not information you had to earn.
static func perceive_threats(tree: SceneTree, here: Vector2, owner: Node) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for t: Node in tree.get_nodes_in_group(&"telegraph"):
		if not is_instance_valid(t) or not (t is Node2D):
			continue
		# Only ARMED tells. A fired or fading ring is a picture of something that
		# already happened; dodging it is the tell-tale sign of a bot reading
		# state instead of the screen.
		if t.has_method(&"is_armed") and not bool(t.call(&"is_armed")):
			continue
		if not t.has_method(&"danger_shape"):
			continue
		# ⚠ NOT MY OWN TELL. There was no owner filter here at all, and until now that
		# was harmless only by accident: the sole class that spawned telegraphs was
		# `Enemy`, and enemies run their own private dodge scan (which DOES filter, by
		# `tg.source.is_in_group("enemy")`) rather than this one. The moment `Hero`
		# starts publishing tells for its swings, a bot-driven hero perceives its own
		# wind-up as incoming danger and dodges away from its own punch — every frame,
		# forever, because the tell follows the swing.
		#
		# Filtered by IDENTITY, not by faction. A team-mate's blast genuinely is worth
		# dodging in this game (friendly fire is always on), so the rule is only ever
		# "the thing I am doing myself is not a surprise to me" — the same principle the
		# projectile arm below already applies to a bot's own bolt.
		if owner != null and t.get(&"source") == owner:
			continue
		var shape: Dictionary = t.call(&"danger_shape")
		var tti: float = float(t.call(&"time_to_impact")) if t.has_method(&"time_to_impact") else 0.0
		# The TOTAL warning this tell ever gave, carried alongside what is left of it.
		# `BotBrain._caps` collapses a class's guard band onto this when the tell is
		# shorter than the band — without it the whole contact half of the roster is
		# unparryable by arithmetic. 0.0 means "not published", and is left alone.
		var lead: float = float(t.call(&"windup")) if t.has_method(&"windup") else 0.0
		var id: int = t.get_instance_id()
		seen[id] = true
		# ⚠ A TELL IS PARRYABLE. Both branches below read `false`, and that one word
		# deleted the defensive verb for the entire family it was built for.
		#
		# `BotBrain._caps` ANDs `threat.parryable` into `can_parry`, and
		# `BotDodge.choose_response` gates its parry rung on exactly that — so a
		# `false` here did not make a bot parry LESS, it made the rung UNREACHABLE.
		# And telegraphs are precisely the non-travelling spells (beams, meteors,
		# zones, pillars, walls) that `SpellDeflect` exists to let a guard EAT; that
		# file's header settles the policy as "nothing is unparryable", and BotDodge's
		# parry rung already carries the comment "answers melee, contact and charge
		# hits too — so it is a legitimate reply to a charger lane". Perception was the
		# only place that disagreed with both.
		#
		# It holds on the ENEMY side too, which is what makes this safe rather than
		# optimistic: a telegraphed enemy attack lands through `Hero.take_damage`,
		# which returns early on `_parry_window_timer` and on a PERFECT `ParryRing`.
		# Both damage paths already honour a raised guard.
		#
		# MEASURED before this changed: 1 deflect across 18 duels. The guard was held
		# for ~7% of frames and had nothing it was permitted to answer.
		if String(shape.get("shape", "")) == "line":
			var from: Vector2 = shape.get("from", Vector2.ZERO)
			var to: Vector2 = shape.get("to", Vector2.ZERO)
			var seg: Vector2 = to - from
			out.append({
				"id": id, "kind": "lane", "pos": from, "vel": Vector2.ZERO,
				"radius": 0.0, "length": seg.length(), "width": float(shape.get("width", 0.0)),
				"angle": seg.angle(), "tti": tti, "lead": lead,
				"parryable": true, "region": shape,
			})
		else:
			out.append({
				"id": id, "kind": "circle", "pos": shape.get("center", Vector2.ZERO),
				"vel": Vector2.ZERO, "radius": float(shape.get("radius", 0.0)),
				"length": 0.0, "width": 0.0, "angle": 0.0,
				"tti": tti, "lead": lead, "parryable": true, "region": shape,
			})
	# Both projectile families, because who is shooting at you depends on which
	# faction you are on: an `enemy_projectile` from a monster and a `player_spell`
	# from a rival hero are the same problem to the body dodging them.
	for group: StringName in [&"enemy_projectile", &"player_spell"]:
		var fallback: float = ENEMY_PROJECTILE_SPEED if group == &"enemy_projectile" else SPELL_SPEED
		for p: Node in tree.get_nodes_in_group(group):
			if not is_instance_valid(p) or not (p is Node2D):
				continue
			var pid: int = p.get_instance_id()
			if seen.has(pid):
				continue  # a bolt in two groups (deflectable_spell) is still one bolt
			# Your own shot is not a threat to you, and pretending otherwise makes
			# a bot dodge its own bolt the instant it fires.
			if owner != null and p.get(&"caster") == owner:
				continue
			seen[pid] = true
			var at: Vector2 = (p as Node2D).global_position
			var vel: Vector2 = _travel_velocity_of(p, fallback)
			out.append({
				"id": pid, "kind": "projectile", "pos": at, "vel": vel,
				"radius": PROJECTILE_REGION_RADIUS, "length": 0.0, "width": 0.0,
				"angle": vel.angle(),
				# A projectile's "time to impact" is not knowable without solving
				# against the body's own position, which is BotDodge's job — the
				# perception layer reports the raw motion and nothing more.
				"tti": 0.0,
				"parryable": p.has_method(&"reflect"),
				"region": {"shape": "circle", "center": at, "radius": PROJECTILE_REGION_RADIUS},
			})
	return out


## World-space Rect2 for every ring-out pit, in the form `BotDodge.safest_exit`
## takes. Uses the same `stage_hazard` group + `mode == 0` (PIT) + `zone_size`
## idiom `Hero._dest_in_pit` already reads, so a bot's idea of "that is a hole"
## cannot drift from the engine's — including the mode filter, without which a
## bot would refuse to walk through a non-pit hazard the engine happily allows.
static func perceive_hazards(tree: SceneTree) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for h: Node in tree.get_nodes_in_group(&"stage_hazard"):
		if not is_instance_valid(h) or not (h is Node2D):
			continue
		if int(h.get(&"mode")) != 0:  # StageHazard.Mode.PIT
			continue
		var size: Variant = h.get(&"zone_size")
		if not (size is Vector2):
			continue
		var half: Vector2 = (size as Vector2) * 0.5
		out.append(Rect2((h as Node2D).global_position - half, size as Vector2))
	return out


## World positions of every uncollected spell pickup, as plain Vector2s.
##
## Reported as bare positions rather than as records because the brain's only
## question is "is there something worth walking to, and where" — WHICH spell it is
## is not knowable by looking at it in this game (the pickup draws a generic sigil),
## so publishing an id would hand the bot information a player does not have.
##
## Group name comes from `SpellPickup.PICKUP_GROUP` (`&"spell_pickup"`), read as a
## literal here for the same no-extra-compile-chain-edge reason as SPELL_SPEED.
static func perceive_pickups(tree: SceneTree) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p: Node in tree.get_nodes_in_group(&"spell_pickup"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		# A pickup already claimed this frame is still in the tree for a beat while it
		# plays its collect flourish; walking at it is walking at nothing.
		# Tested as `is bool` rather than `bool(...)`: `Object.get` returns NULL for a
		# property that does not exist and `bool(null)` is a hard "nonexistent
		# constructor" error that ABORTS the enclosing function — the same trap
		# `_nearest_in_group` documents for `downed`.
		var taken: Variant = p.get(&"_consumed")
		if taken is bool and taken:
			continue
		out.append((p as Node2D).global_position)
	return out


## The `region` footprints out of a threat array — the second argument
## `BotDodge.safest_exit` wants. Kept as a helper rather than a blackboard key so
## there is exactly one array of threats and no chance of the two drifting.
static func danger_regions(threats: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Variant in threats:
		if t is Dictionary and (t as Dictionary).has("region"):
			out.append((t as Dictionary)["region"])
	return out


# ---- perception helpers -----------------------------------------------------

static func _zero_cooldowns() -> Array[float]:
	var out: Array[float] = []
	for _i: int in BotIntent.CD_COUNT:
		out.append(0.0)
	return out


## Nearest live member of `group`, excluding the perceiver. Plain origin distance
## rather than `SpellTargets` silhouette measuring: this is "who am I looking at",
## a decision a player makes by eye, not a hit test that has to agree with a
## collider.
static func _nearest_in_group(tree: SceneTree, group: StringName, here: Vector2,
		exclude: Node) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for n: Node in tree.get_nodes_in_group(group):
		if n == exclude or not is_instance_valid(n) or not (n is Node2D):
			continue
		# A downed co-op hero is out of the fight, and visibly so. Tested as
		# `is bool` rather than `bool(...)`: `Object.get` returns NULL for a
		# property that does not exist (an Enemy has no `downed`), and `bool(null)`
		# is a hard "nonexistent constructor" error, not a falsy value.
		var out: Variant = n.get(&"downed")
		if out is bool and out:
			continue
		var d: float = here.distance_squared_to((n as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node2D
	return best


## Is this body currently holding a guard up? Duck-typed through `is_parrying()`
## (Hero publishes it; an Enemy does not), so a body without the method simply
## reads as not guarding rather than breaking perception.
static func _guarding(n: Node) -> bool:
	if n.has_method(&"is_parrying"):
		return bool(n.call(&"is_parrying"))
	return false


static func _velocity_of(n: Node) -> Vector2:
	var v: Variant = n.get(&"velocity")
	return v as Vector2 if v is Vector2 else Vector2.ZERO


## Fraction of the floating health bar that is still filled. Reads `hp`/`max_hp`,
## which is precisely what CharacterBars draws over the head.
static func _hp_frac_of(n: Node) -> float:
	var hp: Variant = n.get(&"hp")
	var mx: Variant = n.get(&"max_hp")
	if hp == null or mx == null or float(mx) <= 0.0:
		return 1.0
	return clampf(float(hp) / float(mx), 0.0, 1.0)


## -1 / 0 / +1 for which way a body is turned. Hero publishes a `facing` vector;
## an Enemy does not — it mirrors its rig's scale.x instead, which is literally
## the thing drawn on screen, so that is what gets read.
static func _facing_of(n: Node) -> float:
	var f: Variant = n.get(&"facing")
	if f is Vector2:
		return signf((f as Vector2).x)
	var rig: Variant = n.get(&"rig")
	if is_instance_valid(rig) and rig is Node2D:
		return signf((rig as Node2D).scale.x)
	return 0.0


## A projectile's world velocity. Prefers the body's own `travel_velocity()`
## accessor; falls back to the universal "these things fly along their rotation at
## a fixed speed" contract (`launch()` writes `rotation = dir.angle()` on both
## families) so perception is never BLOCKED on a script this seam does not own.
static func _travel_velocity_of(p: Node, fallback_speed: float) -> Vector2:
	if p.has_method(&"travel_velocity"):
		return p.call(&"travel_velocity") as Vector2
	if p is Node2D:
		return Vector2.from_angle((p as Node2D).rotation) * fallback_speed
	return Vector2.ZERO
