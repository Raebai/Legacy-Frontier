class_name BossDropWatcher
extends Node2D
## SPAWNS THE TIER 3 DROP WHEN THE GUARDIAN DIES.
##
## ⚠ WHY THIS IS A WATCHER AND NOT A LINE IN `Boss._die`. The obvious home for
## "boss dies -> drop something" is inside `Boss.gd`, or in `Encounter` where the
## boss is spawned. Both are owned by other agents. So this is a node that
## `FloorBuilder` parks in the room, waits for a guardian to exist, latches onto its
## `defeated` signal, and drops the reward where the body fell. It needs no edit to
## any file outside this agent's list, and it costs one group scan every
## `POLL_INTERVAL` seconds until the boss arrives.
##
## The boss is identified by DUCK TYPING (`has_signal("defeated")`), not by
## `is Boss`. Two reasons, and the second is the one that matters: a `class_name`
## reference here would pull `Boss.gd` -> `Enemy.gd` into the compile graph of
## `FloorBuilder`, which is loaded by headless test suites that have no business
## compiling the enemy AI; and `defeated` is the exact capability this file needs,
## so asking for it directly is both cheaper and more honest than asking for a type
## that happens to have it.
##
## THE DROP IS ROLLED, NOT GUARANTEED. `SpellDrops.roll_boss_drop` says no half the
## time. A guaranteed Tier 3 per floor would put four charges of catastrophe in
## every run and the shelf would stop being rare — and rarity is the balance system.

const PICKUP_SCENE: String = "res://scenes/combat/SpellPickup.tscn"
## How often the room is scanned for a guardian, in seconds. The boss arrives after
## the wave sequence, which is many seconds in, so this does not need to be tight.
const POLL_INTERVAL: float = 0.5
## How long after the guardian dies before the drop appears. Long enough for the
## death spectacle to land first — a reward that pops during the explosion is a
## reward nobody sees.
const DROP_DELAY: float = 1.1

## The floor this room is, for the seeded roll. -1 asks GameState at spawn time.
var floor_index: int = -1

var _poll: float = 0.0
var _boss: Node = null
var _spawned: bool = false


func _process(delta: float) -> void:
	if _spawned or _boss != null:
		return
	_poll += delta
	if _poll < POLL_INTERVAL:
		return
	_poll = 0.0
	_find_boss()


func _find_boss() -> void:
	for n: Node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if not n.has_signal(&"defeated"):
			continue
		_boss = n
		# One-shot: the guardian emits `defeated` once, and a second connection
		# would drop two spells.
		if not n.is_connected(&"defeated", _on_boss_down):
			n.connect(&"defeated", _on_boss_down, CONNECT_ONE_SHOT)
		return


func _on_boss_down() -> void:
	if _spawned:
		return
	_spawned = true
	# Position captured NOW: by the time the delay elapses the body has been freed
	# and `global_position` on a freed node is not a question that can be asked.
	var at: Vector2 = global_position
	# ⚠ IN CO-OP THE DROP MUST NOT LAND WHERE THE BOSS DIED, because that is not a
	# point the two peers agree on.
	#
	# A pickup's WIRE IDENTITY IS ITS POSITION (`Net.pos_key` -> `_find_at`, within
	# `Net.KEY_TOLERANCE` = 6 px). Every other user of that key is a statically
	# placed object built from shared floor data; this is the one that moves. A
	# boss's position is synced with lag, so the two peers place the pickup at
	# slightly different world points, the host awards a pickup at ITS key, and the
	# client's `_find_at` returns null past 6 px — `_client_pickup` then silently
	# returns and the guardian's reward never applies on that peer.
	#
	# It fails in the direction that still looks correct, which is the worst kind:
	# the drop is visible on both screens and simply cannot be taken on one.
	#
	# THIS NODE'S OWN POSITION IS THE DETERMINISTIC ANCHOR — it is placed from floor
	# data (`SpellDrops.BOSS_ANCHOR` via FloorBuilder), so it is byte-identical
	# across peers. Solo is left EXACTLY as it was: the drop still lands on the
	# corpse in the mode that has actually been played.
	if is_instance_valid(_boss) and _boss is Node2D and not _coop_active():
		at = (_boss as Node2D).global_position
	_drop_after(at)


## Is a live co-op session running? Guarded lookup so a headless harness with no
## `Net` autoload answers "no" and keeps the solo placement.
func _coop_active() -> bool:
	var net: Node = get_node_or_null(^"/root/Net")
	return net != null and net.has_method(&"is_active") and bool(net.call(&"is_active"))


func _drop_after(at: Vector2) -> void:
	await get_tree().create_timer(DROP_DELAY).timeout
	if not is_inside_tree():
		return   # floor was left (or the run ended) during the delay
	var id: String = SpellDrops.roll_boss_drop(_resolved_floor())
	if id == "":
		return   # the roll said no. Half of them do.
	var pickup: Area2D = (load(PICKUP_SCENE) as PackedScene).instantiate()
	get_parent().add_child(pickup)
	pickup.global_position = at
	pickup.call(&"set_spell", id)
	# A guardian's drop announces itself — this is the loudest reward in the game
	# and the moment the floor's power fantasy peaks.
	SpellDrops.sfx("charge_ult", -2.0, 0.04, 0.8)
	Juice.zoom_pull_camera(0.18, 0.9, 0.2, 0.7)
	CombatVfx.spawn_burst(get_parent(), at, Color(1.6, 1.3, 0.6, 1.0),
		Color(0.9, 0.7, 0.2, 0.0), 30, 0.7, 40.0, 200.0, 1.4, 4.0, 0.0, 0.0, true)


## The floor number, from the explicit override or from GameState. Falls back to 1
## so a sandbox arena (which has no GameState) still rolls something rather than
## silently never dropping.
func _resolved_floor() -> int:
	if floor_index >= 0:
		return floor_index
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method(&"current_floor"):
		return int(gs.call(&"current_floor"))
	return 1
