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


func _ready() -> void:
	enemy = get_parent()
	_net = get_node_or_null("/root/Net")


func _process(delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not _set_up:
		_set_up = true
		_setup()
		return                      # setup gets its own frame; ticking starts next
	if is_dead():
		return
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


# --------------------------------------------------------------------- helpers
## True in single player and on the host; false on a co-op client's puppet.
func is_authority() -> bool:
	if _net == null or not _net.is_active():
		return true
	return enemy != null and enemy.is_multiplayer_authority()


## An enemy at 0 hp is mid-death: `Enemy._die()` has already run and `queue_free` is
## pending. Riders stop ticking there so nothing fires out of a corpse.
func is_dead() -> bool:
	return int(enemy.get("hp")) <= 0


func enemy_pos() -> Vector2:
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
