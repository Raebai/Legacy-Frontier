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
## Hard cap on tracked REACTANTS.
##
## ⚠ THIS IS NOT THE VFX BUDGET AND NEVER WAS — see the census below. It bounds the
## pair loop (12*11/2 = 66 tests) and nothing else. A 13th spell still spawns, still
## deals damage, still draws; it just stops being able to clash. That is a correct
## and deliberate degradation for REACTIONS, and it was being read as if it were a
## limit on how much spectacle can be alive at once. It is not, and until the census
## below there was no such limit anywhere in the game.
const MAX_LIVE: int = 12

# ------------------------------------------------------- THE LIVE-VFX BUDGET
## THE SPEC'S NUMBER: at most 8 spell effects alive at once.
##
## MEASURED JUSTIFICATION, on this desktop at the 25-entity ceiling
## (tools/stress_mobile_entities.gd ++casting=1, sweeping the cast rate):
##
##   concurrent spectacles   0     1      4      9     19
##   CPU per frame          8.7  14.2   20.9   32.3   34.3  ms
##
## That is roughly +2.6 ms of CPU for every spell effect on screen, on a machine
## 3-5x faster than the target phone, and before a single pixel is drawn. It was
## the largest single cost driver in the frame and it had no ceiling at all: the
## number of live spectacles was whatever the players' thumbs produced.
##
## LOW gets a tighter budget than HIGH. Not for looks — because the measurement
## says the cost is CPU-side and the quality dial currently only gates GPU work
## (screen-reading shaders, mote counts), so on the phone LOW was saving nothing
## on the axis that is actually over budget.
const SPECTACLE_BUDGET_HIGH: int = 8
const SPECTACLE_BUDGET_LOW: int = 5

## HOW A SPECTACLE IS RECOGNISED, and why this exact property.
##
## `SpellCaster._stamp()` writes `element_id` onto every spectacle its 21 dispatch
## arms build, and 32 scripts declare it — every spell effect in the game including
## the enemy/boss projectiles, which count against what is ON SCREEN just as much as
## the hero's do. `get()` on a property a node has not declared returns null, so this
## test is exactly "a node the spell layer built" with no group to maintain, no
## registration to forget, and no edit to any of the 32 scripts.
##
## The alternative was voluntary registration, which is what the reaction registry
## uses — and only 14 of the spectacles ever adopted it. A budget that half the
## spells opt out of is not a budget.
const SPECTACLE_MARK: StringName = &"element_id"
## A meteor barrage inside a void zone must not fire eleven reactions in one
## tick. Excess pairs are simply retried next tick.
const MAX_REACTIONS_PER_TICK: int = 2

## Emitted after an outcome has been applied. The playground HUD and the tests
## listen to this; gameplay does not depend on it.
signal reaction_fired(outcome: String, point: Vector2, a: Node, b: Node)

# ---------------------------------------------------- THE REFUSAL COUNTERS
## WHY A REACTION DID NOT HAPPEN, counted by REASON, on the same terms as
## `BotBrain.ult_gate_*` and for the same reason: this repo has already shipped one
## confident story about a slot that turned out to be wrong (the ult scorer refused
## 0 of 482 for the named cause). "The table has a row for it" is not evidence the
## row is ever reached, and a bare zero in a fired-count cannot tell you WHICH of
## the five stages said no — and the five want completely different fixes:
##
##   pair_tests          two live effects were compared at all (the denominator)
##   gate_bucket_miss    stage 2 — nobody ever wrote a rule for those two FORMS
##   gate_no_rule        stage 3 — the bucket exists, the row refused the pair
##                       (element / owner / weight / head-on)
##   gate_memo           stage 4 — this exact pair already reacted
##   gate_no_shape       stage 5 — an effect published no geometry at all
##   gate_no_overlap     stage 5 — they matched a row and never touched
##   gate_applied        the outcome ran
##
## A dead reaction whose pair never even got a `pair_test` is a REGISTRATION
## problem (nothing was in the system). One dying at `gate_no_rule` is a TABLE
## problem. One dying at `gate_no_overlap` is a GEOMETRY or a pacing problem —
## the two spells exist but never share space — and no amount of table editing
## will move it. Reading a zero without these is guessing.
##
## Process-wide and monotonic, like the BotBrain set, and they cannot be switched
## off — a counter with an off switch is a counter that is missing on the day it is
## wanted.
##
## ⚠ WHAT THEY COST, MEASURED rather than waved at (tools/probe_reaction_cost.gd,
## at the MAX_LIVE ceiling of 12 effects / 66 pair tests per tick):
##
##       no-rule load, counters WITHOUT the silence tally   637 us/tick
##       no-rule load, counters as shipped                  810 us/tick
##
## 173 us of that is `no_rule_pairs`, which is the only one that formats a STRING on
## the hot path. It is kept because that tally is what produced the whole finding
## this file's rows were rewritten from — and because 810 us is 4.9% of a 60 fps
## frame at a ceiling real play never approaches: a real duel averages 0.8-1.2 live
## effects, i.e. ONE pair test every few ticks. If a future load genuinely sits at
## twelve live reactants, this tally is the first thing to gate.
static var pair_tests: int = 0
static var gate_bucket_miss: int = 0
static var gate_no_rule: int = 0
static var gate_memo: int = 0
static var gate_no_shape: int = 0
static var gate_no_overlap: int = 0
static var gate_applied: int = 0
## outcome -> how many times the TABLE matched it, before geometry was consulted.
## The gap between this and the fired count is exactly "the row is right and the
## two spells never touch", which is invisible in every other number here.
static var rule_matched: Dictionary = {}
## "FORM Element x FORM Element" -> how many pair tests the table had NOTHING for.
## THE ACTIONABLE LIST, and the reason it is measured rather than enumerated: the
## table is silent on dozens of descriptor pairs and most of those two spells never
## share a floor, so a static sweep of the silences answers "what could be written"
## while this answers "what the player is actually watching do nothing".
## Bounded by (6 forms x 8 elements)^2 in theory and by about a dozen entries in
## practice, because a duel only has two kits in it.
static var no_rule_pairs: Dictionary = {}
## "FORM Element" -> how many effects of that description ever entered the registry,
## and how many 30 Hz ticks they were collectively ACTIVE for. The denominator for
## every zero above: a reaction between two things that were never both on the floor
## is not a table failure, and these two numbers are the only way to tell.
static var registrations: Dictionary = {}
static var live_ticks: Dictionary = {}


## For a harness measuring one run at a time.
static func reset_gate_stats() -> void:
	pair_tests = 0
	gate_bucket_miss = 0
	gate_no_rule = 0
	gate_memo = 0
	gate_no_shape = 0
	gate_no_overlap = 0
	gate_applied = 0
	rule_matched = {}
	no_rule_pairs = {}
	registrations = {}
	live_ticks = {}


## Human-readable description of one registered effect, for the tallies above.
static func describe(form: int, element: int) -> String:
	const FORMS: Array[String] = ["BEAM", "BARRIER", "FIELD", "PROJECTILE", "IMPACT", "AURA"]
	var f: String = FORMS[form] if form >= 0 and form < FORMS.size() else "?"
	return "%s %s" % [f, Elements.display_name(element)]


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

## THE CENSUS. Every live spell spectacle, newest last. Deliberately UNTYPED — it
## holds nodes that are routinely freed out from under it, and assigning an
## already-freed instance into a typed `Node` local raises "Trying to assign
## invalid previously freed instance", which in GDScript ABORTS THE ENCLOSING
## FUNCTION and returns its zero. The sweep would then quietly stop cleaning up on
## exactly the entries it exists to remove, and the budget would ratchet shut and
## put the whole game in permanent austerity. Same trap, same fix, as
## `DamageNumber._pool` and `CombatVfx._acquire`.
var _spectacles: Array = []
## Sweep once per frame, not once per asker. The cosmetic services below query this
## several times in a busy frame (every burst, every impact frame, every decal) and
## an unswept O(n) walk per query is precisely the shape of thing this file exists
## to stop adding.
var _census_frame: int = -1
var _census_count: int = 0


func _ready() -> void:
	for r: Dictionary in ReactionTable.rules():
		_buckets[ReactionTable.bucket_key(int(r["form_a"]), int(r["form_b"]))] = true
	# One global hook instead of 32 edits. `node_added` fires for every node in the
	# tree, so the callback below is written to reject a non-spectacle in a single
	# property read — see `_on_node_added`.
	get_tree().node_added.connect(_on_node_added)


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
	# Built ONCE per registration and carried on the entry. The per-tick `live_ticks`
	# tally is then a dictionary bump rather than a string format 30 times a second
	# per live effect, which is the difference between a diagnostic and a cost.
	var tag: String = describe(form, element)
	_live.append({
		"node": node, "form": form, "element": element,
		"weight": _weight_of(node), "id": id, "tag": tag,
	})
	registrations[tag] = int(registrations.get(tag, 0)) + 1


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


# ------------------------------------------------------ the live-VFX budget
## Every node added anywhere in the tree passes through here, so the first line is
## the whole performance story: one `get()` on a property a non-spectacle has not
## declared, which answers null and returns. Damage numbers, particle emitters, rig
## limbs and UI all die on that read.
func _on_node_added(node: Node) -> void:
	if node.get(SPECTACLE_MARK) == null:
		return
	_spectacles.append(node)
	# INVALIDATE THE PER-FRAME CACHE. Without this, several spells arriving inside a
	# single frame — a boss opening a phase, a co-op peer rebuilding a remote cast,
	# a Roulette that re-enters `cast` — are all invisible to every budget query made
	# later in that same frame, because the first query cached the count from before
	# any of them existed. Caching is for repeat askers, not for hiding new arrivals.
	_census_frame = -1


## Live spell spectacles right now. Swept (dead entries dropped) at most once per
## frame; repeat callers in the same frame get the cached answer.
func spectacle_count() -> int:
	var f: int = Engine.get_process_frames()
	if f == _census_frame:
		return _census_count
	for i: int in range(_spectacles.size() - 1, -1, -1):
		# Variant first — see the ⚠ on `_spectacles`.
		var raw: Variant = _spectacles[i]
		if raw == null or not is_instance_valid(raw):
			_spectacles.remove_at(i)
	_census_frame = f
	_census_count = _spectacles.size()
	return _census_count


## How many spell effects may be alive before the cosmetics start giving way.
func vfx_budget() -> int:
	return SPECTACLE_BUDGET_LOW if TuningConfig.quality_is_low() else SPECTACLE_BUDGET_HIGH


## THE ONE THING THE REST OF THE COMBAT LAYER ASKS. 1.0 = spend freely. Below 1.0 =
## the screen is already carrying its budget of spell effects, so anything OPTIONAL
## should cost proportionally less.
##
## ⚠ WHAT "OVER BUDGET" DOES **NOT** MEAN, and this is the design decision:
##
##   IT NEVER DROPS A SPELL. Not the 9th, not the 20th. A spell that does not spawn
##   is a spell that does not damage, and in co-op every peer rebuilds every spell
##   locally — so a peer that silently skipped one would show a teammate dying to
##   nothing. Worse, this game is about reading a telegraph and dodging it: an
##   invisible spell that still hits you is the least fair thing it could possibly
##   do. Culling the OLDEST live spell was considered for the same reason and
##   rejected for the same reason — the oldest effect on screen is usually the zone
##   somebody is currently standing out of.
##
##   IT NEVER TOUCHES DAMAGE, HITBOXES, KNOCKBACK, HIT-STOP OR TELEGRAPH TIMING.
##   Those are gameplay and several of them are hand-tuned feel numbers.
##
## What it does instead is make the SHARED GARNISH cheaper: fewer particles in a
## burst, a local impact ring instead of a full-screen plate, no extra debris or
## scorch. Every spell still spawns, still draws its own geometry, still reads.
## The screen gets busier and slightly plainer at exactly the moment it is already
## too busy to notice — which is the cheapest possible thing to lose.
##
## FOUR STEPS, NOT A CONTINUOUS RAMP, and the steps are the point rather than a
## rounding convenience. `CombatVfx` keys its emitter pool on the particle COUNT —
## a recycled emitter given a different count reallocates its GPU buffer, which is
## the exact cost the pool exists to avoid — so a smoothly varying scale factor
## would mint a fresh pool bucket per burst and quietly turn the pool back into an
## allocator. Four levels means at most four buckets per call site.
##
## The first version of this ramped by 0.12 per spell over and then let CombatVfx
## round to quarters. At one spell over that gave 0.88, which rounds to 4/4, which
## is no cut at all — so the budget measurably did nothing in the most common
## over-budget case (measured: 3-5% of particles cut when the harness sat at 9 live
## against a budget of 8). Quantising HERE instead means one spell over is a real
## 25% trim and the caller cannot round it away.
func austerity() -> float:
	var over: int = spectacle_count() - vfx_budget()
	if over <= 0:
		return 1.0
	if over <= 2:
		return 0.75
	if over <= 5:
		return 0.5
	return 0.25


## True while the screen is at or past its spell-effect budget. The boolean form,
## for callers whose choice is on/off rather than a scale (a decal either spawns or
## it does not).
func over_vfx_budget() -> bool:
	return spectacle_count() > vfx_budget()


## Static convenience so the cosmetic helpers — which are all `RefCounted` statics
## with no node to reach the tree from — can ask without each hand-rolling the
## autoload lookup.
##
## ⚠ MAY NOT NAME THE AUTOLOAD DIRECTLY. Naming `SpellReactor` inside a STATIC
## function is a compile error that takes the whole dependency chain down with a
## misleading "missing method" message (the trap documented on
## `TuningConfig.quality_is_low` and `SpellDeflect._sfx`). The tree lookup is the
## house idiom, and it also means this answers 1.0 under `--script`, where autoloads
## are never registered — so a headless suite sees no austerity and stays
## deterministic.
static func vfx_austerity() -> float:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1.0
	var r: Node = tree.root.get_node_or_null(^"/root/SpellReactor")
	return 1.0 if r == null else float(r.call(&"austerity"))


## Static form of `over_vfx_budget`. Same autoload caveat as above.
static func vfx_over_budget() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var r: Node = tree.root.get_node_or_null(^"/root/SpellReactor")
	return false if r == null else bool(r.call(&"over_vfx_budget"))


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
		var tag: String = String(e.get("tag", ""))
		live_ticks[tag] = int(live_ticks.get(tag, 0)) + 1
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
			pair_tests += 1
			# Stage 2 — sparse-matrix gate. Most pairs die here.
			if not _buckets.has(ReactionTable.bucket_key(int(a["form"]), int(b["form"]))):
				gate_bucket_miss += 1
				continue
			# Stage 3 — the authored predicate, ownership included.
			var rel: String = _owner_relation(a["node"], b["node"])
			var rule: Dictionary = ReactionTable.match_rule(
				int(a["form"]), int(a["element"]), int(b["form"]), int(b["element"]),
					rel, int(a["weight"]), int(b["weight"]),
					_heading_of(a["node"]), _heading_of(b["node"]))
			if rule.is_empty():
				gate_no_rule += 1
				var silence: String = "%s x %s [%s]" % [
					String(a.get("tag", "?")), String(b.get("tag", "?")), rel]
				no_rule_pairs[silence] = int(no_rule_pairs.get(silence, 0)) + 1
				continue
			var outcome: String = String(rule["outcome"])
			rule_matched[outcome] = int(rule_matched.get(outcome, 0)) + 1
			# Stage 4 — one crossing fires once.
			var key: String = _memo_key(int(a["id"]), int(b["id"]), outcome)
			if _memo.has(key):
				gate_memo += 1
				continue
			# Stage 5 — geometry, last and only for pairs that got this far.
			var sa: Dictionary = _shape_of(a, shapes)
			var sb: Dictionary = _shape_of(b, shapes)
			if sa.is_empty() or sb.is_empty():
				gate_no_shape += 1
				continue
			if not SpellGeometry.overlaps(sa, sb):
				gate_no_overlap += 1
				continue
			if _fire(rule, a, b, sa, sb, rel):
				gate_applied += 1
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
## Which way an effect is travelling, or ZERO for anything that does not travel.
## OPTIONAL on the participant contract: only rows carrying `require_head_on` read it,
## and those fail closed on a ZERO heading — so a wall, a field or a beam simply
## cannot match them, which is the correct answer for something that has no heading.
static func _heading_of(n: Node) -> Vector2:
	if n == null or not is_instance_valid(n) or not n.has_method(&"reaction_heading"):
		return Vector2.ZERO
	return n.call(&"reaction_heading") as Vector2


static func _weight_of(n: Node) -> int:
	if n != null and is_instance_valid(n) and n.has_method(&"reaction_weight"):
		return SpellTier.weight_or_default(int(n.call(&"reaction_weight")))
	return SpellTier.DEFAULT_WEIGHT


## ⚠ THE RETURNED OWNER NEEDS ITS OWN VALIDITY CHECK, NOT JUST `n`. A spectacle
## routinely outlives the body that cast it — the caster dies to the very exchange the
## effect is still resolving — so `reaction_owner()` hands back a freed instance, and
## `as Node` on a freed object is a hard `SCRIPT ERROR: Trying to cast a freed object`.
## MEASURED at 20 occurrences across 10 bouts, firing every duel from
## `_process -> resolve_now -> _owner_relation -> _owner_of`.
##
## A dead caster is correctly "unowned": `_owner_relation` already treats a null owner
## as the unowned case, which is the right answer — a rule that asks for SAME or
## DIFFERENT casters cannot meaningfully match a caster that no longer exists.
static func _owner_of(n: Node) -> Node:
	if n == null or not is_instance_valid(n) or not n.has_method(&"reaction_owner"):
		return null
	var o: Variant = n.call(&"reaction_owner")
	# ⚠ VALIDITY BEFORE `is`. `is` THROWS on a previously freed instance, so the old
	# `o is Node and is_instance_valid(o)` could never reach its own guard — and the
	# block above documents that a freed owner here was MEASURED, repeatedly. Same
	# fault as `CastName._heavy_label`.
	if is_instance_valid(o) and o is Node:
		return o as Node
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
