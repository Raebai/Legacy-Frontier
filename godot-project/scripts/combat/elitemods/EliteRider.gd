class_name EliteRider
extends Node
## Base class for an ELITE AFFIX RIDER — the Node an EliteModifier parents onto an
## ordinary `Enemy` so it can rewrite that enemy's behaviour from OUTSIDE it.
##
## Deliberately the same shape as `BossModRider`, because the constraint is the same:
## `Enemy.gd` composes eight archetypes already and must not grow a branch per
## variant. See `EliteModifier.gd` for the full argument.
##
## ── THE THREE RULES EVERY ELITE RIDER OBEYS ──────────────────────────────────
##
## 1. SETUP IS DEFERRED TO THE FIRST FRAME. Riders are attached before the enemy
##    enters the tree, and Godot runs a child's `_ready` BEFORE its parent's — so at
##    `_ready` time the enemy has no rig, no hurtbox, no archetype defaults and no
##    difficulty scaling. Worse, `Enemy._apply_difficulty()` MULTIPLIES `move_speed`
##    and writes `_cd_speed` outright, so an affix that scaled speed in `_ready`
##    would be silently overwritten a moment later. `_setup()` runs from the first
##    `_process`, after all of it.
##
## 2. ANYTHING THAT SPAWNS OR DAMAGES IS HOST-ONLY. Enemies are host-authoritative
##    (`Enemy._physics_process` returns early on a client puppet) but riders tick on
##    every peer, so a rider that spawned a blast on both machines would deal the
##    damage twice. `_tick` is authority-gated; `_tick_visual` is not, because a
##    client that cannot SEE an affix cannot play around it.
##
## 3. NEVER TOUCH HP. Not `hp`, not `max_hp`, not a damage multiplier standing in for
##    one. `tools/slice_test_elites.gd` reads the source of every file in this
##    directory and fails the suite if one of them mentions an hp field. An affix
##    earns its place by changing what the body DOES.

## Set by EliteModifier.attach before the node enters the tree.
var affix_id: String = ""
## The spawn dictionary the enemy was built from. Present for symmetry with the boss
## riders (Split needs it there); nothing here reads it yet.
var affix_ctx: Dictionary = {}

var enemy: Node = null
var _net: Node = null
var _set_up: bool = false

# ═══════════════════════════════════════════════════════════════ THE MOUTH
## ── WHY AN ELITE TALKS AT ALL ────────────────────────────────────────────────
## The aura, the word and the 12% height say "this one is different" to the EYE.
## None of them says it to the ear, and on a phone the eye is busy. A named body
## that announces itself is the cheapest possible extra reading channel, and for
## HERALD it is not decoration at all — the howl is the co-op callout that says
## "burn the glowing one first".
##
## ── THE FLOOR-AFFIX GATE, WHICH IS THE WHOLE RATE LIMIT ──────────────────────
## `EliteModifier.attach(..., dressed)` puts the SAME riders on EVERY body when a
## floor carries a rule. Sixteen bodies announcing themselves is not a mix, it is a
## crowd scene, and it would bury the hero's own gibberish — which is the thing the
## player is actually listening for. So every line below is gated on
## `is_named_elite()`: a body with no `EliteMark` has the behaviour and NO voice.
## An affix is heard only when it is a NAMED EVENT in the wave.
##
## ── THE BUDGET, STATED ──────────────────────────────────────────────────────
## A floor holds at most `EliteRoster.MAX_PER_FLOOR` (2) named elites, and 25 live
## entities. Against that:
##   * ANNOUNCE — once per elite, ever. Two lines per floor.
##   * a REACTION beat — at most one per `VOICE_GAP` (1.4 s) per elite, and at most
##     one per `ROOM_GAP` (0.55 s) across every elite in the room, so two elites can
##     never talk over each other.
##   * `Bark.COOLDOWN` (3 s) independently limits the ones that also show a bubble.
##   * `Sfx.speak`'s own 140 ms per-seed floor is underneath all of it.
## Worst case is therefore under two utterances a second with both elites alive and
## both constantly triggering, and the realistic figure is well under one. A voice
## is TICK weight with no sub/tail/crack layers, so three syllables costs three of
## the 32 pool slots for about a third of a second.
##
## NONE OF THIS HAS BEEN HEARD. The gaps, the moods and the syllable counts are
## reasoning about a mix nobody has listened to, not tuning.

## Minimum seconds between two utterances from the SAME elite.
const VOICE_GAP: float = 1.4
## Minimum seconds between two utterances from ANY elite, room-wide. Deliberately
## static: the point is that two named bodies do not double-talk, and per-instance
## state cannot express "somebody else just spoke".
const ROOM_GAP: float = 0.55
## Billing. A named body sits a couple of dB over the wave it walks in with —
## enough to be picked out, far too little to fight a spell (`Gibberish.MAX_DB`
## and the TICK class trim are both still above this).
const VOICE_DB: float = 2.0
## Seconds after setup before the announce lands, so it reads as the body arriving
## rather than as a spawn blip, and so two elites in one wave do not speak on the
## same frame (the stagger comes off the voice seed — see `_announce_delay`).
const ANNOUNCE_BASE: float = 0.45
const ANNOUNCE_SPREAD: float = 0.75

static var _room_last_voice: float = -99.0

var _voice_seed: int = 0
var _last_voice: float = -99.0
var _announce_t: float = -1.0
var _announced: bool = false


func _ready() -> void:
	enemy = get_parent()
	_net = get_node_or_null("/root/Net")


func _process(delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not _set_up:
		_set_up = true
		_install_voice()
		_setup()
		return                      # setup gets its own frame; ticking starts next
	if is_dead():
		return
	_tick_announce(delta)
	_tick_visual(delta)
	if is_authority():
		_tick(delta)


# ------------------------------------------------------------------- overrides
## One-shot, on the first frame after the enemy's own `_ready` (and therefore after
## `_apply_archetype_defaults` and `_apply_difficulty` have finished writing).
func _setup() -> void:
	pass


## Host-only per-frame work. Spawning, damaging, teleporting, buffing others.
func _tick(_delta: float) -> void:
	pass


## Runs on every peer. Tints, auras, marks — never anything with consequences.
func _tick_visual(_delta: float) -> void:
	pass


# ----------------------------------------------------------------- the mouth
## True only for a DRESSED elite — a named body with the word over its head.
## A floor-wide affix rides every body in the room and must stay silent; see the
## budget block at the top of this file.
func is_named_elite() -> bool:
	return enemy != null and is_instance_valid(enemy) and enemy.has_node(^"EliteMark")


## THE VOICE IDENTITY, and the reason it is not derived from the node name.
##
## `Gibberish.voice_of` reads `name`, and a node's name is handed out by whichever
## parent adopts it — two peers' arenas need not agree on it. Everything here comes
## instead out of `affix_ctx`, which IS the spawn dictionary that
## `Encounter.build_enemy_from_data` was handed, is replicated verbatim, and is
## already locked byte-identical across peers by `tools/slice_test_coop.gd`. Same
## dict on both phones -> same seed -> the same mouth on both phones, with nothing
## broadcast and nothing stored.
##
## ⚠ THE PARTS ARE FOLDED WITH `Gibberish.seed_combine`, NOT ADDED. Spawn
## coordinates in one room are neighbours by construction, and this file's own
## history is the argument: deriving a voice by dividing a DJB2-flavoured hash gave
## a whole wave three cadences between them. `seed_combine` avalanches each part
## before combining, so two elites twenty pixels apart are unrelated voices.
##
## ⚠ AND THE AFFIX ID IS DELIBERATELY NOT IN IT. A QUICKENED+KEEN elite carries TWO
## riders on ONE body; folding the affix in would give that body two different
## mouths, which is worse than any correlation bug.
func elite_voice_seed() -> int:
	if _voice_seed != 0:
		return _voice_seed
	var ctx: Dictionary = affix_ctx
	if ctx.is_empty():
		# No spawn dict (a hand-built body, a harness): fall back to the same
		# name-derived identity every ordinary mob uses. Degrades, never breaks.
		_voice_seed = int(Gibberish.voice_of(enemy).get("seed", 1))
		return _voice_seed
	_voice_seed = Gibberish.seed_combine([
		int(round(float(ctx.get("x", 0.0)))),
		int(round(float(ctx.get("y", 0.0)))),
		int(ctx.get("arch", 0)),
		int(ctx.get("hp", 0)),
	])
	if _voice_seed == 0:
		_voice_seed = 1                                  # 0 is the "unset" sentinel
	return _voice_seed


## Stamp the mouth onto the BODY (not onto this rider) so `Bark` finds it however
## the body is asked to speak — including through `VoiceDirector`'s death cry, which
## knows nothing about elites. Two riders on one body stamp the same value, and the
## second stamp is a no-op.
func _install_voice() -> void:
	if not is_named_elite():
		return
	enemy.set_meta(Bark.SEED_META, elite_voice_seed())
	enemy.set_meta(Bark.BAND_META, Gibberish.BAND_ELITE)
	enemy.set_meta(Bark.DB_META, VOICE_DB)
	# ONE MOUTH PER BODY. Two affixes means two riders; the first to arrive claims
	# the announce so the body introduces itself once rather than twice.
	if not enemy.has_meta(&"elite_voice_owner"):
		enemy.set_meta(&"elite_voice_owner", get_instance_id())
	if int(enemy.get_meta(&"elite_voice_owner")) == get_instance_id():
		_announce_t = _announce_delay()


## Deterministic per-body stagger, so two elites spawned into the same wave do not
## announce on the same frame. Off the seed rather than `randf()` because the two
## peers must stay in step and because a test can pin it.
func _announce_delay() -> float:
	var t: float = float(elite_voice_seed() % 1000) / 999.0
	return ANNOUNCE_BASE + ANNOUNCE_SPREAD * t


func _tick_announce(delta: float) -> void:
	if _announced or _announce_t < 0.0:
		return
	_announce_t -= delta
	if _announce_t > 0.0:
		return
	_announced = true
	# ANNOUNCE IS EXEMPT FROM THE ROOM GAP. There are at most two of them on a whole
	# floor and they are already staggered; a dropped introduction is worse than a
	# half-second of overlap, and a "maybe" introduction is indistinguishable in play
	# from a broken hook.
	if Bark.say(enemy, StringName("elite_" + affix_id), true):
		_mark_spoke()


## ONE LINE, over the body's head, in the body's own voice. Returns whether it
## landed. `always` bypasses Bark's flavour roll — reserve it for beats that are a
## MECHANIC (the herald's howl, the volatile's warning), never for colour.
func elite_bark(event: StringName, always: bool = false) -> bool:
	if not _can_speak():
		return false
	if not Bark.say(enemy, event, always):
		return false
	_mark_spoke()
	return true


## Mouth only, no bubble. For the beats that fire often enough that a line would be
## a tickertape: shrugging off a shove, reading a bolt, smearing sideways.
func elite_voice(mood: int, syllables: int = 0) -> bool:
	if not _can_speak():
		return false
	Bark.voice_only(enemy, mood, syllables)
	_mark_spoke()
	return true


## Speak HERE and on every other peer — for a voice whose trigger only exists on
## the host, so no client will ever reach it on its own.
##
## Use this ONLY when the trigger has no synced twin. When it does — `velocity` for
## Quickened, `hp` for Volatile — riding the synced value costs no packet and is
## strictly better. See `Net.broadcast_voice` for why these two are the exceptions.
func elite_bark_everywhere(event: StringName, always: bool = true) -> bool:
	var spoke: bool = elite_bark(event, always)
	if spoke and _net != null and _net.is_active() and _net.is_host():
		_net.call(&"broadcast_voice", enemy, event)
	return spoke


## The `elite_voice` half: mouth only, on every peer.
func elite_voice_everywhere(mood: int, syllables: int = 0) -> bool:
	var spoke: bool = elite_voice(mood, syllables)
	if spoke and _net != null and _net.is_active() and _net.is_host():
		_net.call(&"broadcast_voice_only", enemy, mood, syllables)
	return spoke


func _can_speak() -> bool:
	if not is_named_elite() or is_dead():
		return false
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - _last_voice < VOICE_GAP:
		return false
	if now - _room_last_voice < ROOM_GAP:
		return false
	return true


func _mark_spoke() -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	_last_voice = now
	_room_last_voice = now


# --------------------------------------------------------------------- helpers
## True in single player and on the host; false on a co-op client's puppet.
func is_authority() -> bool:
	if _net == null or not _net.is_active():
		return true
	return enemy != null and enemy.is_multiplayer_authority()


## An enemy at 0 hp is mid-death: `Enemy._die()` has already run and `queue_free` is
## pending. Riders stop ticking there so nothing fires out of a corpse.
func is_dead() -> bool:
	# ⚠ A FREED ENEMY IS DEAD, and `.get()` on one is a fault rather than an answer.
	# This function's whole job is "stop ticking out of a corpse", and the most corpse-y
	# state of all — already freed — was the one it could not survive being asked about.
	if not is_instance_valid(enemy):
		return true
	return int(enemy.get("hp")) <= 0


func enemy_pos() -> Vector2:
	# ⚠ UNGUARDED `is` ON A STORED REF — see `is_dead`.
	if not is_instance_valid(enemy):
		return Vector2.ZERO
	return (enemy as Node2D).global_position if enemy is Node2D else Vector2.ZERO


func rig() -> Node:
	return enemy.get_node_or_null(^"Rig") if enemy != null else null


## The arena everything (spectacles included) is parented to.
func arena() -> Node:
	return enemy.get_parent() if enemy != null else null


## Nearest live hero, or null. Group "hero" is the TOWER group — "player" is the old
## v0.0 hub group and finds nothing here.
func nearest_hero() -> Node2D:
	var tree: SceneTree = get_tree()
	if tree == null or enemy == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	var here: Vector2 = enemy_pos()
	for h: Node in tree.get_nodes_in_group("hero"):
		if not (h is Node2D) or not is_instance_valid(h):
			continue
		var d: float = here.distance_squared_to((h as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = h as Node2D
	return best


## Stamp a spectacle so it hurts heroes and is OWNED by this enemy.
##
## ⚠ THE OWNERSHIP LINE IS LOAD-BEARING, NOT BOOKKEEPING — the reaction layer asks a
## spectacle `reaction_owner()`, and a null owner satisfies neither `require_owner:
## "same"` nor `"different"`, so an un-owned effect matches NO clash row and is
## silently inert in the entire reaction system. Nothing errors. (The boss riders
## carry the same note; it cost this repo two sessions once already.)
func stamp_hostile(node: Node, element: int = -1, tier: int = -1) -> void:
	node.set("target_group", "hero")
	node.set("_target_group", "hero")
	node.set("caster_node", enemy)
	if element >= 0:
		node.set("element_id", element)
	if tier >= 0:
		node.set("spell_tier", tier)


## This affix's colour, for anything a rider wants to draw in it.
func tint() -> Color:
	return EliteModifier.tint_for(affix_id)
