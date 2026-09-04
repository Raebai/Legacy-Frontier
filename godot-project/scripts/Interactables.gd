## NEAREST-WINS ARBITRATION FOR THE `talk` KEY.
##
## THE BUG THIS EXISTS FOR. Three unrelated things in the town listen for `talk` in
## `_unhandled_input` and each one calls `set_input_as_handled()` when it fires: the
## townsfolk (`NPC`), the teleport pads (`ArmoryStation`) and the way out
## (`TowerDoor`). Nothing arbitrated between them, so the winner was whichever node
## `_unhandled_input` happened to reach first -- and that order is TREE ORDER, which
## is decided by the order `World` adds children. Townsfolk are added after the door
## and the pads, so a townsperson silently beat both.
##
## That is not a theoretical hazard, it shipped, and the ranges guarantee it:
##
##   * `TowerDoor.PROXIMITY_RADIUS` is 150 px and the doorkeeper stood inside it, so
##     pressing E anywhere near the door TALKED TO THE DOORKEEPER instead of entering
##     the tower. Walking in still worked, which is exactly why it survived: the
##     feature was not dead, only the key was, and only sometimes.
##   * `ArmoryStation.PROXIMITY_RADIUS` is 46 px and the warden's 40 px ring reaches
##     to x=384 against the armoury pad at x=380, so for part of every lap he walks,
##     standing ON the armoury pad showed two hints and E talked to the warden.
##
## THE RULE: the CLOSEST thing that is willing to respond gets the press. That is what
## a player already believes is happening -- you press the button at the thing you are
## standing at -- so it needs no explaining, and unlike a priority table it cannot go
## stale when somebody adds a fourth kind of interactable.
##
## Only nodes that would ACTUALLY DO SOMETHING are considered. A pad 300 px away is
## not competing for the press just because it exists, so each participant answers
## `interact_ready()` with its own in-range flag and an unready node is skipped
## entirely rather than being ranked and then rejected -- otherwise a nearer node that
## is not listening would silently veto a further one that is.
##
## NO `class_name`. A new global class needs a headless `--import` before anything can
## reference it, which is a recurring trap in this repo and a hazard while other work
## is in flight. Consumers do `const Interactables := preload(...)` instead, which
## resolves at load time and needs nothing.
extends RefCounted

## Every node that competes for the `talk` press joins this. Joining is the whole
## registration: there is no list to keep in step with the scene.
const GROUP: StringName = &"interactable"


## THE RULE, AS A PURE FUNCTION. Which of `candidates` is closest to `from`?
##
## Separated from `wins` so it can be tested on the town's REAL geometry without
## waiting for anybody's `Area2D` to have ticked. Readiness is the caller's business:
## this answers a question about distance and nothing else, which is the only reason
## a test can ask it about two nodes the player is nowhere near.
##
## Ties go to whichever came first and that cannot matter — equal distance means the
## player is standing exactly between two things, and either answer is defensible.
static func nearest_of(candidates: Array, from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for c: Variant in candidates:
		var n: Node2D = c as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var d: float = n.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n
	return best


## Is `node` the nearest READY interactable to the player?
##
## ⚠ TOTAL, NOT PARTIAL: a node that is not itself ready loses, rather than winning by
## default because every rival was filtered out. In production every caller has
## already checked its own in-range flag before asking, so that branch never fires —
## which is exactly why it was missing, and exactly why it had to be added: the first
## test to ask this question WITHOUT that precondition got "yes" from all seven
## interactables in the town at once. A predicate that is only correct when the caller
## already knows the answer is not a predicate.
##
## Returns TRUE when there is no player, so a headless probe with no body in the room
## behaves exactly as the game did before this existed.
static func wins(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.has_method(&"interact_ready") and not bool(node.call(&"interact_ready")):
		return false
	var tree: SceneTree = node.get_tree()
	if tree == null:
		return true
	var player: Node2D = tree.get_first_node_in_group(&"player") as Node2D
	if player == null:
		return true
	var ready: Array = []
	for other: Node in tree.get_nodes_in_group(GROUP):
		var n: Node2D = other as Node2D
		if n == null or not is_instance_valid(n):
			continue
		if n.has_method(&"interact_ready") and not bool(n.call(&"interact_ready")):
			continue
		ready.append(n)
	var winner: Node2D = nearest_of(ready, player.global_position)
	return winner == null or winner == node
