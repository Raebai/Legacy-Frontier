class_name SpellReactorNode
extends Node
## Autoload "SpellReactor" — the one place that notices two live spell effects
## have met, and turns that into an authored reaction.
##
## ReactionTable says WHAT happens when two forms/elements meet; SpellGeometry
## says WHERE and WHETHER they touch. Neither of them watches the world. This
## does: live spectacles register themselves, the registry polls the pairs at
## 30 Hz, and a match fires exactly once.
##
## ⚠ THE TRAP THIS IS BUILT AROUND: ten spell scripts park their node at the
## arena ORIGIN and draw in world coordinates, so `global_position` is (0,0) and
## is NOT where the effect is. A detector that compared transforms would report
## every pair of live spectacles as touching, at the top-left of the arena — a
## bug that fails LOUD in the wrong direction. So this file NEVER reads a node's
## transform. Geometry comes only from `reaction_shape()`, and
## tools/slice6_test_reactor.gd asserts that two origin-parked stubs with
## distant shapes do not react.
##
## THE PARTICIPANT CONTRACT (duck-typed, matching the codebase's existing
## `wall_distance` / `blink_to` / `consume` idiom — a spell that does not
## implement it is simply not in the system):
##
##   reaction_shape()   -> Dictionary  world-space, built with SpellGeometry
##                                     (circle/capsule). NEVER global_position.
##   reaction_active()  -> bool        LOAD-BEARING. False while the effect is
##                                     only a telegraph: a beam must not react
##                                     during its 0.34 s charge, or two crossed
##                                     beams annihilate before either exists.
##   reaction_element() -> int         Elements.Element
##   reaction_form()    -> int         ReactionTable.Form
##   reaction_owner()   -> Node        OPTIONAL. Who cast it; null = unowned.
##                                     Lets a rule require SAME owner (one caster
##                                     combining their own two spells) or
##                                     DIFFERENT owners (two casters' effects
##                                     meeting) — a data predicate in
##                                     ReactionTable, never a branch in here.
##   reaction_weight()  -> int         OPTIONAL. A SpellTier.Tier — QUICK / HEAVY
##                                     / ULT. How much this effect WEIGHS when it
##                                     meets another head-on: two evenly matched
##                                     spells annihilate each other, a heavier one
##                                     eats the lighter and keeps going, a barrier
##                                     stops what it is not outmatched by. Like
##                                     everything else here it is only ever read
##                                     as a PREDICATE by ReactionTable.
##                                     POLLED every tick, alongside
##                                     reaction_active() rather than captured at
##                                     registration like form and element — those
##                                     two genuinely cannot change, whereas an
##                                     effect getting LIGHTER as it is spent is a
##                                     thing we want to be able to author (a ward
##                                     that has absorbed most of its budget should
##                                     stop out-weighing the next thing to hit it).
##                                     NOT IMPLEMENTED = SpellTier.DEFAULT_WEIGHT,
##                                     the middle shelf. Since every spectacle
##                                     that has not adopted this weighs the same as
##                                     every other, they all stay evenly matched
##                                     with each other and behave exactly as they
##                                     do today — which is what lets the ~15
##                                     spectacles adopt it one at a time.
##                                     The whole adoption is one method:
##                                         func reaction_weight() -> int:
##                                             return SpellTier.Tier.ULT
##   reaction_consume() -> void        the reaction spent this effect: tear down
##                                     WITHOUT the normal end-of-life beat.
##   reaction_freeze()  -> void        OPTIONAL. Pin the effect where it is,
##                                     stop its damage, keep it drawn (Hollow
##                                     Purple's SEIZE beat: you see your own
##                                     beam get caught, not deleted).
##
## Registration is one line at the end of a spell's entry function. Registered
## by nobody = provably zero behaviour change, which is what lets reactions land
## spell by spell.

## Reactions resolve at 30 Hz, not per frame: a 33 ms worst-case latency on a
## crossing nobody can perceive, for a third of the pair tests.
const TICK_HZ: float = 30.0
const TICK_PERIOD: float = 1.0 / TICK_HZ
## Hard cap on tracked reactants. 12 live effects is already far past realistic
## concurrency (1-4); the cap exists so a pathological barrage cannot turn the
## pair loop into a frame-time cliff. Worst case is 12*11/2 = 66 pair tests.
const MAX_LIVE: int = 12
## A meteor barrage inside a void zone must not fire eleven reactions in one
## tick. Excess pairs are simply retried next tick.
const MAX_REACTIONS_PER_TICK: int = 2

## Emitted after an outcome has been applied. The playground HUD and the tests
## listen to this; gameplay does not depend on it.
signal reaction_fired(outcome: String, point: Vector2, a: Node, b: Node)

## Test seam: false = match and memoize as normal but spawn no spectacle node.
## Lets the reactor's DETECTION be proven without a 1.6 s Hollow Purple and a
## camera it has no business touching inside a headless suite.
var spawn_effects: bool = true
## Total reactions fired since boot (diagnostics + tests).
var fired_count: int = 0

## {node, form, element, weight, id}. Typed array of plain dicts — one allocation
## per registration, none per tick. `weight` is seeded here and refreshed in
## place by the tick's activity sweep, so polling it costs no allocation either.
var _live: Array[Dictionary] = []
## "idA:idB:outcome" -> true. Keyed on INSTANCE IDS, never node references, so a
## freed spectacle cannot keep this dictionary alive; the sweep prunes dead ids.
var _memo: Dictionary = {}
## bucket_key -> true. The sparse-matrix gate: built once from ReactionTable's
## authored rows, so a pair of forms nobody wrote a rule for dies on a hash miss
## having cost one integer shift, with NO geometry and no rules() rebuild.
var _buckets: Dictionary = {}
var _accum: float = 0.0
## Global one-shot: only one annihilation on screen at a time.
var _hollow_purple: Node = null


func _ready() -> void:
	for r: Dictionary in ReactionTable.rules():
		_buckets[ReactionTable.bucket_key(int(r["form_a"]), int(r["form_b"]))] = true


func _process(delta: float) -> void:
	_accum += delta
	if _accum < TICK_PERIOD:
		return
	_accum = 0.0
	resolve_now()


# ------------------------------------------------------------ registration

## Put a live effect into the reaction system. `form` is a ReactionTable.Form,
## `element` an Elements.Element. Call it from the spell's own entry function
## once the effect exists; `reaction_active()` decides when it may actually
## react, so registering during a telegraph is correct and expected.
func register(node: Node, form: int, element: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	# An elementless effect can never satisfy an opposed/same predicate and would
	# match wildcard rows as a phantom element; keep it out entirely.
	if element < 0:
		return
	var id: int = node.get_instance_id()
	for e: Dictionary in _live:
		if int(e["id"]) == id:
			return
	if _live.size() >= MAX_LIVE:
		_sweep_invalid()
		if _live.size() >= MAX_LIVE:
			return  # over budget: this effect simply does not react
	_live.append({
		"node": node, "form": form, "element": element,
		"weight": _weight_of(node), "id": id,
	})


## Remove an effect (its `_exit_tree`, or the moment it is consumed). Safe to
## call for a node that was never registered.
func unregister(node: Node) -> void:
	if node == null:
		return
	var id: int = node.get_instance_id()
	for i: int in range(_live.size() - 1, -1, -1):
		if int(_live[i]["id"]) == id:
			_live.remove_at(i)
	_prune_memo(id)


func live_count() -> int:
	return _live.size()


## True while an annihilation owns the screen. Outcomes that must be globally
## exclusive check this before spawning.
func hollow_purple_live() -> bool:
	return _hollow_purple != null and is_instance_valid(_hollow_purple)


## Take the global annihilation slot; released automatically when `node` leaves
## the tree.
func claim_hollow_purple(node: Node) -> void:
	_hollow_purple = node
	if node != null and not node.tree_exited.is_connected(_release_hollow_purple):
		node.tree_exited.connect(_release_hollow_purple)


func _release_hollow_purple() -> void:
	_hollow_purple = null


# ------------------------------------------------------------ the tick

## One full resolution sweep. Returns how many reactions fired. Public so the
## headless suite can drive it deterministically instead of racing a timer.
##
## Staged so the common case is free: with nothing cast this is one is_empty()
## check 30 times a second.
##   1. validity + activity sweep   — dead and charging effects drop out
##   2. bucket gate                 — one hash per pair, BEFORE any geometry
##   3. element predicate           — integer set tests on the bucket's rows
##   4. memo                        — this pair already reacted
##   5. geometry                    — the only Vector2 maths in the function,
##                                    with shapes cached per node per tick
func resolve_now() -> int:
	_sweep_invalid()
	if _live.size() < 2:
		return 0
	# Stage 1 — only effects that are LIVE, not merely spawned. A beam inside its
	# charge telegraph is registered but inactive.
	var active: Array[Dictionary] = []
	for e: Dictionary in _live:
		var n: Node = e["node"]
		if not n.has_method(&"reaction_active") or not bool(n.call(&"reaction_active")):
			continue
		# Weight refreshed here and NOT per pair: one duck-typed call per live
		# effect per tick (12 worst case), against up to 66 pair tests that all
		# read the result. Keeping it out of the pair loop is the whole reason
		# this sits in the activity sweep rather than next to the rule lookup.
		e["weight"] = _weight_of(n)
		active.append(e)
	if active.size() < 2:
		return 0
	var shapes: Dictionary = {}
	var fired: int = 0
	for i: int in range(active.size()):
		for j: int in range(i + 1, active.size()):
			if fired >= MAX_REACTIONS_PER_TICK:
				return fired
			var a: Dictionary = active[i]
			var b: Dictionary = active[j]
			# Stage 2 — sparse-matrix gate. Most pairs die here.
			if not _buckets.has(ReactionTable.bucket_key(int(a["form"]), int(b["form"]))):
				continue
			# Stage 3 — the authored predicate, ownership included.
			var rel: String = _owner_relation(a["node"], b["node"])
			var rule: Dictionary = ReactionTable.match_rule(
				int(a["form"]), int(a["element"]), int(b["form"]), int(b["element"]),
					rel, int(a["weight"]), int(b["weight"]))
			if rule.is_empty():
				continue
			# Stage 4 — one crossing fires once.
			var key: String = _memo_key(int(a["id"]), int(b["id"]), String(rule["outcome"]))
			if _memo.has(key):
				continue
			# Stage 5 — geometry, last and only for pairs that got this far.
			var sa: Dictionary = _shape_of(a, shapes)
			var sb: Dictionary = _shape_of(b, shapes)
			if sa.is_empty() or sb.is_empty():
				continue
			if not SpellGeometry.overlaps(sa, sb):
				continue
			if _fire(rule, a, b, sa, sb, rel):
				_memo[key] = true
				fired += 1
	return fired


func _fire(rule: Dictionary, a: Dictionary, b: Dictionary,
		sa: Dictionary, sb: Dictionary, rel: String) -> bool:
	var outcome: String = String(rule["outcome"])
	var ctx: Dictionary = {
		"reactor": self,
		"rule": rule,
		"a": a["node"], "b": b["node"],
		"element_a": int(a["element"]), "element_b": int(b["element"]),
		# The shelves the rule was matched on. An outcome that wants to scale
		# itself by how lopsided the clash was reads these rather than asking the
		# nodes again — the answer could have changed since the match.
		"weight_a": int(a["weight"]), "weight_b": int(b["weight"]),
		"shape_a": sa, "shape_b": sb,
		"owner_rel": rel,
		"owner": _owner_of(b["node"]),
		# WHERE two SEPARATE casters' effects met — the crossing itself, not
		# either caster and not the midpoint between them. A same-owner combo
		# ignores this and stages in front of its caster instead.
		"point": SpellGeometry.meeting_point(sa, sb),
		"spawn_effects": spawn_effects,
	}
	if not ReactionOutcomes.apply(outcome, ctx):
		return false
	fired_count += 1
	reaction_fired.emit(outcome, ctx["point"], ctx["a"], ctx["b"])
	return true


## The shelf an effect fights at. Duck-typed exactly like _owner_of: a spectacle
## that has not adopted reaction_weight() is not broken, it is average — and
## every un-adopted spectacle is average TOGETHER, which is why adding this
## changed nothing about how today's beams meet each other.
static func _weight_of(n: Node) -> int:
	if n != null and is_instance_valid(n) and n.has_method(&"reaction_weight"):
		return SpellTier.weight_or_default(int(n.call(&"reaction_weight")))
	return SpellTier.DEFAULT_WEIGHT


static func _owner_of(n: Node) -> Node:
	if n != null and is_instance_valid(n) and n.has_method(&"reaction_owner"):
		return n.call(&"reaction_owner") as Node
	return null


## How two effects' casters relate, in the vocabulary ReactionTable's
## `require_owner` predicate speaks. "unowned" when either side has no caster —
## it satisfies neither "same" nor "different", because there is no
## relationship to require.
static func _owner_relation(a: Node, b: Node) -> String:
	var oa: Node = _owner_of(a)
	var ob: Node = _owner_of(b)
	if oa == null or ob == null:
		return "unowned"
	return "same" if oa == ob else "different"


## Shape lookup, cached per node per tick so an effect that appears in three
## pairs builds its geometry once. NOTE the absence of any transform read: the
## node hands us world-space points it computed itself.
func _shape_of(e: Dictionary, cache: Dictionary) -> Dictionary:
	var id: int = int(e["id"])
	if cache.has(id):
		return cache[id]
	var n: Node = e["node"]
	var s: Dictionary = {}
	if n.has_method(&"reaction_shape"):
		var raw: Variant = n.call(&"reaction_shape")
		if raw is Dictionary:
			s = raw
	cache[id] = s
	return s


func _sweep_invalid() -> void:
	for i: int in range(_live.size() - 1, -1, -1):
		# Untyped on purpose: assigning an already-freed instance to a `Node`
		# variable is itself an error in GDScript, which would make the sweep
		# throw on exactly the entries it exists to remove.
		var n: Variant = _live[i]["node"]
		if n == null or not is_instance_valid(n):
			var id: int = int(_live[i]["id"])
			_live.remove_at(i)
			_prune_memo(id)


static func _memo_key(id_a: int, id_b: int, outcome: String) -> String:
	# Canonical order, so the pair memoizes the same whichever side was seen
	# first in the loop.
	return "%d:%d:%s" % [mini(id_a, id_b), maxi(id_a, id_b), outcome]


func _prune_memo(id: int) -> void:
	if _memo.is_empty():
		return
	var tag: String = str(id)
	var doomed: Array = []
	for k: String in _memo.keys():
		if k.begins_with(tag + ":") or k.contains(":" + tag + ":"):
			doomed.append(k)
	for k: String in doomed:
		_memo.erase(k)
