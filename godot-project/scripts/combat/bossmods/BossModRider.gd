class_name BossModRider
extends Node
## Base class for a BOSS MODIFIER RIDER — the Node a BossModifier parents onto a
## boss so it can rewrite that boss's behaviour from OUTSIDE it.
##
## See BossModifier.gd for why modifiers are riders rather than subclasses. The
## short version: a modifier must compose with ANY boss including the Ashen Tower
## Guardian, whose script may not be edited, so the only legal seam is "a child node
## that pokes fields the boss already has".
##
## ── THE TWO RULES EVERY RIDER OBEYS ──────────────────────────────────────────
##
## 1. SETUP IS DEFERRED TO THE FIRST FRAME. Riders are attached before the boss
##    enters the tree (the only point both the single-player and the co-op spawn
##    paths pass through), and Godot runs a child's `_ready` BEFORE its parent's.
##    So at `_ready` time the boss has no rig, no bar and no phase. `_setup()` is
##    called from the first `_process` instead, where all of that exists.
##
## 2. ANYTHING THAT SPAWNS OR DAMAGES IS HOST-ONLY. Riders tick on every peer, and
##    the boss itself is host-authoritative (`Boss._physics_process` returns early
##    on a puppet). A rider that spawned zones on both machines would spawn them
##    twice. `_tick` is therefore authority-gated; `_tick_visual` is not, because a
##    client that cannot SEE a modifier cannot play around it.

## Set by BossModifier.attach before the node enters the tree.
var modifier_id: String = ""
## The spawn dictionary the boss was built from. Split needs it to rebuild copies;
## everything else ignores it.
var modifier_ctx: Dictionary = {}

var boss: Node = null
var _net: Node = null
var _set_up: bool = false

## Boss.BPhase, restated here so a rider never needs a compile-time Boss reference
## (which would drag the whole spell chain into early boot — see the note at the
## top of tools/slice_test_boss.gd).
const PHASE_INTRO: int = 0
const PHASE_DEAD: int = 4


func _ready() -> void:
	boss = get_parent()
	_net = get_node_or_null("/root/Net")


func _process(delta: float) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	if not _set_up:
		_set_up = true
		_setup()
		return                      # setup gets its own frame; ticking starts next
	if boss_phase() == PHASE_DEAD:
		return
	_tick_visual(delta)
	if is_authority():
		_tick(delta)


# ------------------------------------------------------------------- overrides
## One-shot, on the first frame after the boss's own `_ready`.
func _setup() -> void:
	pass


## Host-only per-frame work. Spawning, damaging, phase forcing, teleporting.
func _tick(_delta: float) -> void:
	pass


## Runs on every peer. Tints, auras, HUD — never anything with consequences.
func _tick_visual(_delta: float) -> void:
	pass


# --------------------------------------------------------------------- helpers
## ⚠ THE ONE SAFE WAY TO TAKE A NODE BACK OUT OF A CONTAINER OR A `get()`.
##
## THE BUG THIS EXISTS TO END, measured rather than remembered (the measurements are
## in `tools/probe_freed_semantics.gd`, the reproduction in `probe_elite_teardown.gd`):
##
##   is_instance_valid(freed)  ->  false
##   freed == null             ->  TRUE      (yes, really -- Godot 4.6)
##   var n: Node = <freed>     ->  FAULTS: "Trying to assign invalid previously freed
##                                 instance."
##
## The third line is the whole problem, and it is why guarding did not help. A
## STATICALLY TYPED slot -- a typed local, a typed member, a typed function PARAMETER --
## type-checks the value as it is bound, and that check faults on a freed instance
## instead of quietly yielding null. So in
##
##     var e: Node = row["n"]          # line 119: faults HERE
##     if e == null or not is_instance_valid(e):   # line 120: never reached
##
## the guard is unreachable, and worse: a GDScript runtime error ABORTS the enclosing
## function, so everything after the fault -- the `_lifted.clear()` that made the
## teardown idempotent -- silently does not happen. That is exactly the floor-10
## crash, and it left the whole room permanently buffed on top of the log spam.
##
## Two consequences worth stating, because both have already bitten this repo:
##   * A CALLEE CANNOT DEFEND ITSELF. `MagicCircle.offer(circle: MagicCircle, ...)`
##     opens with `is_instance_valid(circle)` and that guard is *still* unreachable,
##     because the parameter binds before the body runs. The CALLER owns the check.
##   * `!= null` IS NOT A SUBSTITUTE, even though it happens to answer correctly here.
##     It is right for the wrong reason and it does nothing about the binding fault.
##
## So: never let a value whose provenance is a container, a `get()`, a `call()` or a
## replicated dictionary land in a typed slot directly. Launder it through here. The
## parameter is `Variant` precisely so the binding cannot fault, and it answers `null`
## for a freed instance, for a never-set entry, and for a non-Object alike.
static func live_node(v: Variant) -> Node:
	if not is_instance_valid(v):
		return null
	return v as Node


## True in single player and on the host; false on a co-op client's puppet boss.
func is_authority() -> bool:
	if _net == null or not _net.is_active():
		return true
	return boss != null and boss.is_multiplayer_authority()


## 0 INTRO · 1/2/3 the fight phases · 4 DEAD. Reads the Boss's own accessor by
## name, so it works on every boss in the roster without a class reference.
func boss_phase() -> int:
	if boss == null or not is_instance_valid(boss) or not boss.has_method("current_phase"):
		return PHASE_INTRO
	return int(boss.call("current_phase"))


## True while the boss is mid-attack (its own `_busy` flag). A rider that wants to
## interrupt the boss should wait for this to clear rather than fight it.
func boss_busy() -> bool:
	return bool(boss.get("_busy"))


func set_boss_busy(v: bool) -> void:
	boss.set("_busy", v)


func hp_fraction() -> float:
	var mx: int = int(boss.get("max_hp"))
	if mx <= 0:
		return 1.0
	return clampf(float(boss.get("hp")) / float(mx), 0.0, 1.0)


## The arena the boss (and every spell spectacle) is parented to.
func arena() -> Node:
	return boss.get_parent() if is_instance_valid(boss) else null


# ⚠ GUARDED. This used to dereference `boss` unconditionally -- the only accessor in
# either rider family with no check at all -- so a rider that outlived its boss by a
# frame turned every caller into "Attempt to call function on a previously freed
# instance". Reachable today only through signal handlers (where the boss is alive by
# construction), which is why it had never fired; that is luck, not a design.
func rig() -> Node:
	return boss.get_node_or_null("Rig") if is_instance_valid(boss) else null


## Nearest live hero, or null. Group "hero" is the TOWER group — "player" is the
## old v0.0 hub group and finds nothing here (that drift has silently killed two
## mechanics in this codebase already).
func nearest_hero() -> Node2D:
	var tree: SceneTree = get_tree()
	# ⚠ VALIDITY, NOT NULLITY -- and the reason is not the one this comment used to give.
	# It claimed "a freed Object is not null". MEASURED, that is false: in Godot 4.6 a
	# freed instance DOES compare equal to null (tools/probe_freed_semantics.gd), so
	# `boss == null` happens to catch this case. It is right for the wrong reason, and
	# the reason matters: what nullity does NOT catch is a freed instance being bound to
	# a statically typed slot, which faults outright. See `live_node` above.
	if tree == null or not is_instance_valid(boss):
		return null
	var best: Node2D = null
	var best_d: float = INF
	var here: Vector2 = (boss as Node2D).global_position
	for h: Node in tree.get_nodes_in_group("hero"):
		if not (h is Node2D) or not is_instance_valid(h):
			continue
		var d: float = here.distance_squared_to((h as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = h as Node2D
	return best


func boss_pos() -> Vector2:
	# ⚠ VALIDITY ON A STORED REF — `boss` is a member that outlives nothing in
	# particular. See the note in `nearest_hero` for what nullity does and does not buy.
	if not is_instance_valid(boss):
		return Vector2.ZERO
	return (boss as Node2D).global_position if boss is Node2D else Vector2.ZERO


## CO-OP: hand every client a damage-free twin of something this rider just built.
##
## ⚠ WHICH RIDERS NEED THIS, AND WHICH MUST NOT USE IT. Riders tick on every peer,
## so a lot of a modifier already converges for free and broadcasting it would draw
## it TWICE on the client. The rule is: broadcast what only the HOST built.
##
##   ENRAGED      nothing. Its dressing is `_setup`/`_on_phase`, which run on every
##                peer, and its early phase gates go out through
##                `Boss._enter_phase` -> `Net.broadcast_boss_phase` already.
##   PATIENT      nothing. Its wash runs everywhere, and the WAKE is derived from
##                `hp`, which the enemy synchronizer replicates — so both peers can
##                compute it. See the visual/authority split in ModPatient.
##   SPLIT        the beat only. The copies go through `Arena.spawn_extra_enemy`,
##                i.e. the MultiplayerSpawner, so the bodies already replicate.
##   UNFINISHED   the mark and the puffs. The destination POSITION replicates, so
##                without the mark a client sees an unannounced teleport — and "step
##                off the mark" is the entire play against this modifier.
##   VOID-TOUCHED the fields. Host-only spawns, and they are no-go ground.
##   MIRRORED     the tell and the answer. Both are host-only spawns.
##
## Routed through the boss's own `_bfx`, which is host-gated inside — so this is a
## no-op in single player and on a client, and there is exactly one mechanism.
func bfx(kind: String, data: Dictionary) -> void:
	if boss != null and is_instance_valid(boss) and boss.has_method("_bfx"):
		boss.call("_bfx", kind, data)


## Stamp a spectacle so it hurts heroes and is OWNED by the boss.
##
## ⚠ THE OWNERSHIP LINE IS LOAD-BEARING, NOT BOOKKEEPING. The reaction layer asks a
## spectacle `reaction_owner()`; a null owner reports "unowned", which satisfies
## neither `require_owner: "same"` nor `"different"`, so an un-owned effect matches
## NO clash row at all and is silently inert in the entire reaction system. Nothing
## errors. That single omission cost this repo two sessions once already.
func stamp_hostile(node: Node, element: int = -1, tier: int = -1) -> void:
	node.set("target_group", "hero")
	node.set("_target_group", "hero")
	node.set("caster_node", boss)
	if element >= 0:
		node.set("element_id", element)
	if tier >= 0:
		node.set("spell_tier", tier)
