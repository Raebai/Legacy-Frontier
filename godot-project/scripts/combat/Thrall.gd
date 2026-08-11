extends "res://scripts/combat/Enemy.gd"
## ══ THE RISEN ═════════════════════════════════════════════════════════════════
## The game's first persistent ALLY. A body the Warlock pulls out of the floor that
## fights for him and then falls apart again.
##
## ── WHY THIS IS AN `Enemy` SUBCLASS AND NOT A NEW BODY ───────────────────────
## The cheapest correct actor really is `Enemy.gd` with its hostility flipped, and
## the reason is one variable. Every aggressive thing an Enemy does — the chase, the
## chase-jump, the ledge leap, the pounce, the brute windup, the caster's aim, the
## charger's lane, the assassin's lunge, the bomber's fuse and the contact damage —
## reads `_hero`, and `_hero` is written in exactly ONE place: `_retarget()`, which
## asks `_nearest_hero()`. Override that single function and the entire 2000-line
## behaviour set re-points at a different faction with no other edit. Nothing else
## in that file decides who the enemy is.
##
## What that inheritance buys, none of which would exist in a hand-rolled ally:
##   * side-on gravity, floor contact, wall-slam craters and the shared knockback
##     channel, so a thrall is shoved by the same forces everything else is;
##   * the SILHOUETTE hurtbox (`body_distance` / `hit_margin` / `head_point`), which
##     is what makes spells hit a drawn head — a bespoke ally would have re-created
##     the "spells pass through heads" bug on its own body;
##   * `StatusComponent`, so a thrall burns, chills and is rooted like anything else;
##   * `CharacterBars`, `CharacterRig`, the death spectacle and the corpse fold;
##   * `_setup_enemy_net()` — a code-built `MultiplayerSynchronizer` streaming
##     position/velocity/hp — so a replicated thrall is already solved.
##
## THE COST, stated plainly, because it is real: five inherited behaviours reference
## the `"hero"` / `"enemy"` groups as literals and each one needs its own override
## below (`_ready`'s group join, `_nearest_hero`, `_retarget`, `_die`, `_accent`).
## They are all small, and they are all in THIS file, which is the trade: five short
## overrides here against ~400 lines of duplicated physics/hurtbox/status/net there.
##
## ── WHAT IT IS NOT ───────────────────────────────────────────────────────────
## NOT in group `"enemy"`. That group is the floor-CLEAR gate (`Encounter.gd:428`),
## the sandbox trickle (`Arena.gd:172`), the camera framing and every bot scan — a
## thrall in it would mean the floor never clears while your minion is alive.
## NOT in group `"hero"`. `Arena._check_party_wipe` counts that group, and
## `DeathRules` says all-dead = game over: a thrall must NEVER satisfy "a player is
## still alive". It is in `mortal` (inherited), which is the friendly-fire group, so
## everything can hurt it — including its master.
##
## ── THE MANDATORY INTERFACE (another agent's Thrall Swap builds on this) ──────
## Group `&"thrall"`, node meta `&"thrall_owner"` pointing at the raising Hero.
## Both are set in `_ready` before the first frame and hold for the whole life.

# ═════════════════════════════════════════════════════════ THE CONTRACT
## The group the swap verb, the cap and the entity budget all key on.
const GROUP: StringName = &"thrall"
## Node meta carrying the Hero that raised this body. May go invalid if the owner
## dies — every reader must `is_instance_valid()` it (see `owner_of`).
const OWNER_META: StringName = &"thrall_owner"

# ═════════════════════════════════════════════════════════ FRIENDLY FIRE
## ⚠ THE NAMED ANSWER TO "CAN A THRALL HURT ITS MASTER". YES — BUT ONLY AT THE END.
##
## Friendly fire is this game's social engine and it is always on, so the question
## is not whether a thrall CAN clip you (it is in `mortal`; your own Grave Tide will
## catch it) but whether it ever CHOOSES to. Three answers were available:
##
##   A. NEVER. A clean pet. Safe, and completely free of the thing that makes this
##      game funny — you would never once be killed by your own dead.
##   B. ALWAYS, at some %. A minion that randomly turns is not unstable, it is
##      BROKEN: you cannot plan around a coin flip, and the maker's rule is that
##      everything must be readable.
##   C. AT THE END, ON A TELL.   <- SHIPPED
##
## C is the one the fantasy already argues for. The expiry IS the fantasy ("risen,
## unstable, their expiry is part of it"), so the last `FERAL_WINDOW` seconds of a
## thrall's life are when the binding fails: it stops telling friend from foe and
## goes for the nearest body, its master included. It is BOUNDED (1.6 s of a 13 s
## life ≈ 12%), TELEGRAPHED (the body goes bone-white and flashes, and every strike
## it throws still carries the full Enemy windup circle), and AVOIDABLE (walk away,
## or kill it — a thrall in the feral window is on 1 hp of clock).
##
## It can never dominate: it holds no more than `THRALL_MAX_ALIVE` bodies, each of
## which threatens for at most `FERAL_WINDOW`, with a 0.6 s telegraph on every swing.
const THRALL_CAN_HURT_ALLIES: bool = true
## How long before expiry the binding fails. Kept under two seconds deliberately —
## long enough to be a real moment, short enough that it is a punchline and not a
## phase of the fight.
const FERAL_WINDOW: float = 1.6
## The tint the body takes when it turns. Bone, not the owner's violet: the whole
## point is that it stops reading as YOURS.
const FERAL_TINT: Color = Color(0.93, 0.90, 0.82, 1.0)

# ═════════════════════════════════════════════════════════ THE BODY
## Signature colour of a bound thrall — a desaturated grave-violet, deliberately
## nothing like the CHASER orange it would otherwise inherit, so "that one is mine"
## is a glance and not a guess.
const BOUND_TINT: Color = Color(0.52, 0.38, 0.72, 1.0)
## Telegraph accent for a BOUND thrall's swing. Enemy tells are danger-red because
## red means "this will hit YOU"; a thrall's circle must never make you dodge your
## own minion, so it wears the owner's violet instead. A FERAL thrall gets the red
## back — see `_accent()` — which is the same information channel telling the truth
## in both directions.
const BOUND_TELE: Color = Color(0.62, 0.45, 0.88)

## Default seconds a thrall stands before it comes apart. Overwritten per-raise by
## `RaiseThrall` (a corpse-raised body lasts longer than one dragged out of bare
## ground), so this is only the value a bare `Thrall.tscn` boots with.
const DEFAULT_LIFE: float = 13.0
## How long a thrall outlives an owner that has been freed. Not zero — popping every
## minion the frame its master dies looks like a bug rather than a rule — and not
## long, because an ownerless body is unswappable, uncapped-against and confusing.
const ORPHAN_GRACE: float = 2.0
## The un-raising: how long the sink beat runs before the node frees itself.
const SINK_TIME: float = 0.28

## Seconds of life left. Ticked ONLY on the authority (see `_physics_process`) so a
## co-op client never expires a body the host still believes in.
var thrall_life: float = DEFAULT_LIFE
## The Hero this body answers to. Set by the raiser BEFORE `add_child` on the local
## path; resolved from `owner_path` on the replicated one.
var owner_hero: Node = null
## Replicated spawns cannot carry a node reference, only values — so the co-op path
## passes the owner's `NodePath` as a string and `_ready` resolves it on each peer.
var owner_path: String = ""

var _feral: bool = false
var _sinking: bool = false


# ─────────────────────────────────────────────────────────────────── lifecycle
## `super._ready()` runs the WHOLE Enemy boot — archetype defaults, difficulty, hp,
## rig tint, gear, hurtbox, HP bar, net sync — and then this undoes the one thing
## that boot got wrong for an ally: membership of `"enemy"`.
##
## ⚠ THE ORDER IS LOAD-BEARING. `remove_from_group("enemy")` must come AFTER
## `super._ready()`, because that is where the join happens. `add_to_group(&"mortal")`
## is deliberately left alone: `mortal` is the friendly-fire group every damageable
## fighter is in, and a thrall you cannot hit would be a thrall you cannot answer.
func _ready() -> void:
	super._ready()
	remove_from_group("enemy")
	add_to_group(GROUP)
	if owner_hero == null and owner_path != "":
		owner_hero = get_node_or_null(NodePath(owner_path))
	set_meta(OWNER_META, owner_hero)
	# The tint the spawner asked for wins; a bare scene gets the signature violet.
	if tint == Color(0.9, 0.35, 0.3, 1) or tint == Color(0.95, 0.5, 0.25, 1):
		tint = BOUND_TINT
	if is_instance_valid(rig):
		rig.set_tint(tint)
	# Re-aim immediately: `super._ready()` left `_hero` pointing at a HERO (its own
	# boot grabs `get_nodes_in_group("hero")[0]`), which for a thrall is the one body
	# it must not walk toward.
	_retarget()


## Difficulty still scales a thrall's hp/speed (symmetry: the same dial that makes
## the room harder makes what you drag out of its floor tougher), but the two SMART
## behaviours it unlocks at Hard+ are switched back off.
##
## WHY. `Enemy._try_evade` dodges bodies out of the way of `player_spell` bolts and
## deflects them point-blank. On an enemy that is difficulty; on a body standing next
## to you it is the opposite of this game — friendly fire is the social engine, and a
## minion that ninja-dodges your own Grave Tide deletes the joke. A DEFLECTING thrall
## is worse still: it would fling your bolts back at you, from a body you do not
## control, with no tell you authored.
const THRALL_DODGES_YOUR_SPELLS: bool = false
func _apply_difficulty() -> void:
	super._apply_difficulty()
	if not THRALL_DODGES_YOUR_SPELLS:
		_smart_dodge = false
		_can_deflect = false


## The clock, then everything Enemy already does.
##
## The tick is AUTHORITY-ONLY, matching how Enemy gates its whole AI: a co-op client
## holds thralls as puppets driven by the synchroniser, and a client that ran its own
## expiry timer would free a body the host still has standing — the exact class of
## desync the co-op rules forbid. The client's copy goes away when the host's
## `queue_free` despawns it through the `MultiplayerSpawner`.
func _physics_process(delta: float) -> void:
	if _sinking:
		return
	var remote: bool = _net != null and _net.is_active() and not is_multiplayer_authority()
	if not remote:
		_tick_binding(delta)
		if _sinking:
			return
	super._physics_process(delta)


## The binding failing, in one place: the orphan check, the feral flip, the expiry.
func _tick_binding(delta: float) -> void:
	# An owner that has been freed cannot be swapped with, cannot be counted against
	# a per-owner cap and cannot be blamed — so the body is given a short grace and
	# then let go.
	if not is_instance_valid(owner_hero):
		thrall_life = minf(thrall_life, ORPHAN_GRACE)
	thrall_life -= delta
	if thrall_life <= 0.0:
		_unravel()
		return
	if THRALL_CAN_HURT_ALLIES and not _feral and thrall_life <= FERAL_WINDOW:
		_turn_feral()


## The binding snaps. A visible, one-shot change of state: the body goes bone, it
## flashes, and it drops its target so the very next `_retarget()` re-picks from
## everything alive rather than only from the enemies.
func _turn_feral() -> void:
	_feral = true
	tint = FERAL_TINT
	if is_instance_valid(rig):
		rig.set_tint(FERAL_TINT)
		rig.flash()
	_abort_attack()   # never let a BOUND-coloured circle resolve as a FERAL strike
	_hero = null
	Sfx.play("shadow_root", -4.0, 0.12, 1.25)


# ────────────────────────────────────────────────────────────── THE FACTION FLIP
## ⚠ THIS FUNCTION IS THE ENTIRE ALLEGIANCE OF THE BODY.
##
## `Enemy._retarget()` is the only writer of `_hero`, and it asks this. Everything
## downstream — chase, jump, leap, pounce, windup, strike, contact damage, the rig's
## facing — consumes `_hero` and asks nothing about factions, so re-pointing this one
## function is a complete faction flip with no other behavioural edit.
##
## BOUND: the nearest live thing in `"enemy"`. Never a hero, ever, at any distance:
## the deliberate attacks of a bound thrall cannot reach its own side.
## FERAL: the nearest live thing in `mortal` that is not itself and not another
## thrall — i.e. enemies AND heroes, master included. Thralls are excluded from each
## other's list on purpose; a knot of minions eating each other in the last second is
## noise, not comedy.
##
## Returns null when there is nothing to fight, which `Enemy._physics_process`
## already handles gracefully (it idles under gravity rather than crashing).
func _nearest_hero() -> Node2D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var pool: Array = tree.get_nodes_in_group(SpellCaster.MORTAL_GROUP if _feral else &"enemy")
	var best: Node2D = null
	var best_d: float = INF
	for n: Node in pool:
		if not (n is Node2D) or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n == self or n.is_in_group(GROUP):
			continue
		# A downed hero is out of the fight; kicking a ghost is not a threat.
		if n.has_method("is_downed") and n.call("is_downed"):
			continue
		var d: float = global_position.distance_squared_to((n as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node2D
	return best


## Unlike the base, this assigns NULL through. `Enemy._retarget` keeps the last
## target when the scan comes back empty, which is right for a mob (there is always
## a hero somewhere) and wrong here: a thrall whose last enemy just died must go
## idle rather than keep charging a freed node's stale position.
func _retarget() -> void:
	_hero = _nearest_hero()


## Telegraph colour. Red on an enemy means "this will hit you", and a bound thrall's
## swing will not — so it wears the owner's violet and stops making the player dodge
## their own minion. The instant it turns, the red comes back, which is the same
## channel telling the truth about a body that IS now a threat.
func _accent() -> Color:
	return Telegraph.RING_COLOR if _feral else BOUND_TELE


# ───────────────────────────────────────────────────────────────────── endings
## KILLED. Deliberately NOT `super._die()`: that grants rank power, ticks the run's
## kill counter and feeds the Hype streak, and none of those are true of your own
## minion falling over. The spectacle is kept (the burst, the folded corpse, the
## shake) because a body dying should always read as a body dying.
func _die() -> void:
	_abort_attack()
	_spawn_death_burst()
	_spawn_corpse()
	Sfx.play("enemy_death", -3.0, 0.06, 0.85)
	Juice.shake_camera(DEATH_SHAKE * 0.5)
	_release()


## EXPIRED. A different read from a kill on purpose — the expiry is part of the
## fantasy, so it must not look like something killed it. The body is not rubbed out;
## it SINKS, dragged back down by whatever let it up, leaving a closing dark ring.
func _unravel() -> void:
	if _sinking:
		return
	_sinking = true
	set_physics_process(false)
	if is_instance_valid(rig):
		rig.set_limp(1.0)
		rig.apply_impulse(Vector2.DOWN, 240.0)
	CombatVfx.spawn_burst(get_parent(), global_position,
		Color(BOUND_TINT.r, BOUND_TINT.g, BOUND_TINT.b, 0.85),
		Color(BOUND_TINT.r * 0.3, BOUND_TINT.g * 0.2, BOUND_TINT.b * 0.4, 0.0),
		14, SINK_TIME + 0.2, 20.0, 70.0, 0.9, 2.4)
	Sfx.play("rx_ground_out", -6.0, 0.1, 0.8)
	# The body is off the board the moment the sink starts — the group and the meta
	# go NOW, not at free time, so the swap verb and the cap can never pick a corpse.
	_release()


## Leave the board. Called by both endings so "no longer a thrall" happens in exactly
## one place, one frame before the node actually goes.
func _release() -> void:
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	if has_meta(OWNER_META):
		remove_meta(OWNER_META)
	queue_free()


# ─────────────────────────────────────────────────────────────────────── public
## Seconds left, for a HUD / the swap verb / a test. Never negative.
func life_remaining() -> float:
	return maxf(thrall_life, 0.0)


## Has the binding failed? Public because "do not swap into a feral one" is a
## decision the swap verb is entitled to make, and it should not have to read a
## private.
func is_feral() -> bool:
	return _feral


## End this body early — what the cap recycle calls when a fourth raise arrives.
## Idempotent.
func dismiss() -> void:
	_unravel()


# ────────────────────────────────────────────────────────────────────── statics
## The Hero a thrall answers to, or null. THE reader every other file should use, so
## "check the meta is valid first" is written once instead of at four call sites.
static func owner_of(thrall: Node) -> Node:
	if thrall == null or not is_instance_valid(thrall):
		return null
	if not thrall.has_meta(OWNER_META):
		return null
	var v: Variant = thrall.get_meta(OWNER_META)
	# ⚠ VALIDITY BEFORE `is`. This helper exists so "check the meta is valid first" is
	# written once — and the check it centralised was unreachable, because `is` throws
	# on a freed instance before the guard runs. A thrall routinely outlives its Hero.
	if is_instance_valid(v) and v is Node:
		return v as Node
	return null


## Every live thrall bound to `who`, oldest first (group order is insertion order).
## Skips bodies already queued for deletion — `queue_free` lands at the END of the
## frame, so a recycled thrall is still in the group for the rest of it and would
## otherwise be counted against the cap it was freed to make room in.
static func live_for(tree: SceneTree, who: Node) -> Array:
	var out: Array = []
	if tree == null or who == null:
		return out
	for t: Node in tree.get_nodes_in_group(GROUP):
		if not is_instance_valid(t) or t.is_queued_for_deletion():
			continue
		if owner_of(t) == who:
			out.append(t)
	return out
