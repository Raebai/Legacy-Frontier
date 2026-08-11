# Run: godot --headless --path godot-project --script tools/slice_test_thrall.gd
#
# THE WARLOCK'S DEAD — Raise Thrall, the Thrall body, and Grave Tide.
#
# What this suite exists to pin, in order of how badly it would hurt to get wrong:
#
#   1. THE THRALL IS ON YOUR SIDE AND IN NOBODY'S WAY. It must be in `&"thrall"`
#      with a `&"thrall_owner"` meta (the interface the Thrall Swap verb is being
#      built against), in `mortal` so friendly fire can reach it, and in NEITHER
#      `"enemy"` (which is the floor-CLEAR gate — a thrall in it means the floor
#      never clears) NOR `"hero"` (which is the party-wipe count — a thrall in it
#      would satisfy "a player is still alive" and break DeathRules).
#   2. THE CAP HOLDS AND BODIES ARE ACTUALLY RAISED. ⚠ Both halves, always. "The cap
#      was never exceeded" is trivially true of a spell that raises nothing, so every
#      cap assertion below is paired with a positive one that gives it meaning.
#   3. THE TIDE CATCHES, DRAINS, AND STOPS SHORT OF ITS OWN CASTER.
#
# ── VACUOUS-PASS ARMOUR (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function, and hands the caller the return type's zero. Under
# a `failed += _test_x()` idiom that reads as "zero failures" — it silently disabled
# 64 suites in this repo once. So: failures accumulate on the MEMBER `_fails` (an
# abort cannot discard them), and every test's last line records that it reached the
# end. A test that aborts part-way is missing from `_completed` and fails BY ABSENCE.
#
# ── WHY REAL SCENES ──────────────────────────────────────────────────────────────
# `Thrall.tscn` is instantiated for real in every thrall test, and a real `Encounter`
# is used for the entity-budget test. A stub that declares members the shipped class
# lacks is a fixture more generous than reality and proves nothing about the game.
# The only stubs here are the SpellDeflect/SpellTargets victim contract (the same
# FakeEnemy shape slice_test_shadow_kit_world already uses) and a two-method arena.
#
# ── WHY IT STARTS FROM _process ──────────────────────────────────────────────────
# The spectacles reference the Sfx autoload, which is not registered until the main
# loop is up — so every script is `load()`ed by path at runtime and never named as a
# class here. Same reason the shadow-kit suite does it.
extends SceneTree

const THRALL_SCENE: String = "res://scenes/combat/Thrall.tscn"
const THRALL_SCRIPT: String = "res://scripts/combat/Thrall.gd"
const RAISE_SCRIPT: String = "res://scripts/combat/RaiseThrall.gd"
const TIDE_SCRIPT: String = "res://scripts/combat/GraveTide.gd"
const ENEMY_SCENE: String = "res://scenes/combat/Enemy.tscn"

## Fixed timestep for hand-driving the spectacles. Deterministic, which real frames
## are not.
const STEP: float = 0.02
## Hard cap so a spectacle that never resolves fails an assertion instead of hanging.
const MAX_STEPS: int = 600

## The five properties `SpellCaster._stamp` writes. `set()` on an UNDECLARED property
## is a silent no-op, so a spectacle missing one of these is quietly unowned,
## unfactioned or elementless with nothing logged — which is why this is a test and
## not a convention.
const STAMPED: Array[String] = [
	"element_id", "spell_tier", "caster_node", "target_group", "_target_group",
]

const TESTS: Array[String] = [
	"thrall_joins_the_contract_groups",
	"thrall_is_never_a_living_player",
	"thrall_targets_enemies_not_heroes",
	"thrall_turns_feral_at_the_end_and_only_then",
	"thrall_expires_and_leaves_the_board",
	"raise_stands_a_real_body_up",
	"raise_on_a_grave_is_the_better_case",
	"raise_never_exceeds_the_owner_cap",
	"raise_respects_the_floor_entity_budget",
	"raise_declares_every_stamped_property",
	"tide_declares_every_stamped_property",
	"tide_catches_a_real_body_and_drains_it",
	"tide_never_catches_its_own_caster",
	"tide_heal_is_capped_by_body_count",
	"tide_front_travels_and_stops",
	"spectacles_draw_without_aborting",
	"entry_points_match_the_hex_arm",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _started: bool = false


# ---------------------------------------------------------------------- fixtures

## The duck-typed victim contract every spell in this codebase resolves against,
## silhouette seam included. Same shape as slice_test_shadow_kit_world's fixture.
class FakeBody:
	extends Node2D

	const SPINE: float = 20.0

	var taken: int = 0
	var statuses: int = 0
	var guarding: bool = false

	func _ready() -> void:
		add_to_group(&"mortal")
		add_to_group("enemy")

	func take_damage(amount: int, _tint: Color = Color.WHITE) -> void:
		taken += amount

	func apply_status(_element_id: int, _can_chain: bool = true) -> void:
		statuses += 1

	func apply_knockback(_impulse: Vector2) -> void:
		pass

	func head_point() -> Vector2:
		return global_position + Vector2(0.0, -SPINE)

	func hit_margin() -> float:
		return 6.0

	func body_distance(p: Vector2) -> float:
		return SpellGeometry.closest_point_on_segment(
			p, global_position, head_point()).distance_to(p)

	func is_parrying() -> bool:
		return guarding

	func parry_freshness() -> float:
		return 1.0


## A hero-flavoured body: same surface, the `hero` group instead of `enemy`, and the
## `heal` the drain feeds. It is deliberately in `mortal` too — that is what makes
## "the tide takes your partner but never you" a testable claim.
class FakeHero:
	extends FakeBody

	var healed: int = 0

	func _ready() -> void:
		add_to_group(&"mortal")
		add_to_group("hero")

	func heal(amount: int) -> void:
		healed += amount

	func is_downed() -> bool:
		return false


## The two methods `RaiseThrall._headroom` duck-types off the Arena — the same two
## `Enemy._spawn_headroom` reads. The Encounter under it is REAL.
class FakeArena:
	extends Node2D

	var enc: Node = null

	func encounter() -> Node:
		return enc


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()   # fire-and-forget: awaits inside, quits when done
	return false


func _run() -> void:
	await _test_thrall_joins_the_contract_groups()
	await _test_thrall_is_never_a_living_player()
	await _test_thrall_targets_enemies_not_heroes()
	await _test_thrall_turns_feral_at_the_end_and_only_then()
	await _test_thrall_expires_and_leaves_the_board()
	await _test_raise_stands_a_real_body_up()
	await _test_raise_on_a_grave_is_the_better_case()
	await _test_raise_never_exceeds_the_owner_cap()
	await _test_raise_respects_the_floor_entity_budget()
	_test_raise_declares_every_stamped_property()
	_test_tide_declares_every_stamped_property()
	await _test_tide_catches_a_real_body_and_drains_it()
	await _test_tide_never_catches_its_own_caster()
	await _test_tide_heal_is_capped_by_body_count()
	await _test_tide_front_travels_and_stops()
	await _test_spectacles_draw_without_aborting()
	_test_entry_points_match_the_hex_arm()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Thrall tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Thrall tests: all PASS")
		quit(0)


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort survives the abort.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end."
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------- scaffolding
func _arena() -> FakeArena:
	var a := FakeArena.new()
	root.add_child(a)
	var enc_script: GDScript = load("res://scripts/combat/Encounter.gd") as GDScript
	if enc_script != null:
		a.enc = enc_script.new()
		a.add_child(a.enc)
	return a


func _floor_slab(from_x: float, to_x: float, top_y: float) -> StaticBody2D:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	var w: float = to_x - from_x
	shape.size = Vector2(w, 40.0)
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	body.global_position = Vector2(from_x + w * 0.5, top_y + 20.0)
	return body


func _thrall(parent: Node, at: Vector2, owner_node: Node, life: float) -> Node:
	var scene: PackedScene = load(THRALL_SCENE) as PackedScene
	if scene == null:
		return null
	var t: Node = scene.instantiate()
	t.set(&"owner_hero", owner_node)
	t.set(&"thrall_life", life)
	parent.add_child(t)
	(t as Node2D).global_position = at
	return t


func _body(parent: Node, at: Vector2) -> FakeBody:
	var b := FakeBody.new()
	parent.add_child(b)
	b.global_position = at
	return b


func _hero_body(parent: Node, at: Vector2) -> FakeHero:
	var h := FakeHero.new()
	parent.add_child(h)
	h.global_position = at
	return h


## Build a spectacle and fire its fixed HEX entry point.
func _cast(script_path: String, arena: Node, caster: Node, origin: Vector2,
		target: Vector2, spell: SpellDef, col: Color = Color(0.6, 0.44, 0.88)) -> Node2D:
	var gs: GDScript = load(script_path) as GDScript
	if gs == null:
		return null
	var n: Node2D = gs.new()
	arena.add_child(n)
	# The four identity pieces SpellCaster._stamp writes, by hand — this suite is
	# testing the spectacles, not the dispatcher.
	n.set("element_id", Elements.Element.SHADOW)
	n.set("spell_tier", SpellTier.of(spell))
	n.set("caster_node", caster)
	n.set("target_group", "mortal")
	n.set("_target_group", "mortal")
	n.call(&"hex", caster, origin, target, spell, col, "shadow")
	return n


## A minimal SpellDef, since the library's own factories are wired by another agent.
func _spell(dmg: int, reach: float, length: float, mp: int, cd: float) -> SpellDef:
	var s := SpellDef.new()
	s.id = "test_spell"
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.SHADOW
	s.effect = "shadow"
	s.damage = dmg
	s.reach = reach
	s.length = length
	s.mp_cost = mp
	s.cooldown = cd
	return s


## Drive a node by hand. Engine physics is switched off first so this loop is the
## only clock — a spectacle stepped by both advances at an unknown rate and every
## timing assertion becomes a coin toss.
func _step(node: Node, steps: int, dt: float = STEP) -> void:
	if node == null:
		return
	node.set_physics_process(false)
	for _i: int in steps:
		if not is_instance_valid(node):
			return
		node.call(&"_physics_process", dt)


func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if n is Node and is_instance_valid(n as Node):
			(n as Node).queue_free()
	await physics_frame
	await physics_frame


func _live_thralls(owner_node: Node) -> int:
	var script: GDScript = load(THRALL_SCRIPT) as GDScript
	if script == null:
		return -1
	return (script.call(&"live_for", self, owner_node) as Array).size()


# ══════════════════════════════════════════════════════════════════ THE BODY
## THE MANDATORY INTERFACE, plus the two group memberships that would break the
## floor-clear gate and the party-wipe count if they were ever gained.
func _test_thrall_joins_the_contract_groups() -> void:
	var arena: FakeArena = _arena()
	var owner_node: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	var t: Node = _thrall(arena, Vector2(40.0, 0.0), owner_node, 9.0)
	await physics_frame
	_expect(t != null, "Thrall.tscn instantiates")
	if t == null:
		return
	_expect(t.is_in_group(&"thrall"), "thrall joins &\"thrall\" (the swap verb's group)")
	_expect(t.has_meta(&"thrall_owner"), "thrall carries the &\"thrall_owner\" meta")
	# The line above already pinned that the key exists, so read it plainly — a null
	# default is not a default at all (Godot errors instead of returning it), which is
	# the trap `CastName._heavy_label` and `Lobby._btn_scale` were both caught in.
	_expect(t.has_meta(&"thrall_owner") and t.get_meta(&"thrall_owner") == owner_node,
		"the meta points at the Hero that raised it")
	_expect(t.is_in_group(&"mortal"),
		"thrall stays in `mortal` — friendly fire must be able to reach it")
	_expect(not t.is_in_group("enemy"),
		"thrall is NOT in `enemy` (that group is the floor-CLEAR gate)")
	await _cleanup([arena])
	_completes("thrall_joins_the_contract_groups")


## DeathRules: all dead = game over. A thrall must never be counted as a body still
## standing, which means it must be invisible to both halves of `Arena._check_party_wipe`
## — the `hero` group scan AND the `is_downed()` probe inside it.
func _test_thrall_is_never_a_living_player() -> void:
	var arena: FakeArena = _arena()
	var t: Node = _thrall(arena, Vector2(0.0, 0.0), null, 9.0)
	await physics_frame
	if t == null:
		return
	_expect(not t.is_in_group("hero"),
		"thrall is NOT in `hero` — it must never satisfy 'a player is still alive'")
	_expect(get_nodes_in_group("hero").is_empty(),
		"a live thrall leaves the `hero` group EMPTY (the party-wipe count sees nothing)")
	await _cleanup([arena])
	_completes("thrall_is_never_a_living_player")


## THE FACTION FLIP. A bound thrall picks the FAR enemy over the NEAR hero — if the
## override were missing it would inherit Enemy's `"hero"` scan and pick the hero,
## so the distances are chosen to make that failure unmistakable.
func _test_thrall_targets_enemies_not_heroes() -> void:
	var arena: FakeArena = _arena()
	var owner_node: FakeHero = _hero_body(arena, Vector2(20.0, 0.0))   # NEAR
	var foe: FakeBody = _body(arena, Vector2(260.0, 0.0))              # FAR
	var t: Node = _thrall(arena, Vector2(0.0, 0.0), owner_node, 9.0)
	await physics_frame
	if t == null:
		return
	t.call(&"_retarget")
	var picked: Variant = t.get(&"_hero")
	_expect(picked == foe,
		"a bound thrall targets the FAR enemy, never the NEAR hero (got %s)" % [picked])
	_expect(not t.call(&"is_feral"), "a freshly raised thrall is not feral")
	await _cleanup([arena])
	_completes("thrall_targets_enemies_not_heroes")


## THE NAMED FRIENDLY-FIRE ANSWER: it turns on you, but ONLY in the last
## `FERAL_WINDOW` seconds. Both halves are asserted — a thrall that is feral from
## birth would pass the second assertion alone.
func _test_thrall_turns_feral_at_the_end_and_only_then() -> void:
	var arena: FakeArena = _arena()
	var owner_node: FakeHero = _hero_body(arena, Vector2(20.0, 0.0))
	var foe: FakeBody = _body(arena, Vector2(260.0, 0.0))
	var script: GDScript = load(THRALL_SCRIPT) as GDScript
	var window: float = float(script.get(&"FERAL_WINDOW")) if script != null else 1.6
	# Well clear of the window: still bound.
	var t: Node = _thrall(arena, Vector2(0.0, 0.0), owner_node, window + 4.0)
	await physics_frame
	if t == null:
		return
	t.call(&"_tick_binding", 0.02)
	_expect(not t.call(&"is_feral"),
		"a thrall with %.1fs left is still BOUND" % (window + 4.0))
	t.call(&"_retarget")
	_expect(t.get(&"_hero") == foe, "...and is still hunting the enemy")
	# Inside the window: the binding fails.
	t.set(&"thrall_life", window * 0.5)
	t.call(&"_tick_binding", 0.02)
	_expect(bool(t.call(&"is_feral")),
		"a thrall inside the last %.1fs has gone feral" % window)
	t.call(&"_retarget")
	_expect(t.get(&"_hero") == owner_node,
		"...and now picks the NEAREST body, its own master included")
	await _cleanup([arena])
	_completes("thrall_turns_feral_at_the_end_and_only_then")


## THEY EXPIRE. And when they do they leave the board IMMEDIATELY — the group and the
## meta go on the same frame the sink starts, one frame before the node itself, so
## the swap verb and the cap can never pick a corpse.
func _test_thrall_expires_and_leaves_the_board() -> void:
	var arena: FakeArena = _arena()
	var owner_node: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	var t: Node = _thrall(arena, Vector2(40.0, 0.0), owner_node, 0.05)
	await physics_frame
	if t == null:
		return
	_expect(_live_thralls(owner_node) == 1, "the thrall is alive before its clock runs out")
	t.call(&"_tick_binding", 0.2)
	_expect(not t.is_in_group(&"thrall"), "an expired thrall leaves the &\"thrall\" group")
	_expect(not t.has_meta(&"thrall_owner"), "...and drops its owner meta")
	_expect(_live_thralls(owner_node) == 0, "...and stops counting against the cap")
	await _cleanup([arena])
	_completes("thrall_expires_and_leaves_the_board")


# ══════════════════════════════════════════════════════════════ THE CEREMONY
## ⚠ THE POSITIVE HALF OF THE CAP TEST. A spell that raises nothing satisfies every
## cap assertion in this file, so this runs first and on its own: one cast, at least
## one REAL body standing, wearing the owner and the group.
func _test_raise_stands_a_real_body_up() -> void:
	var raise_gs: GDScript = load(RAISE_SCRIPT) as GDScript
	if raise_gs != null:
		raise_gs.call(&"clear_graves")
	var arena: FakeArena = _arena()
	var owner_node: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	var rt: Node2D = _cast(RAISE_SCRIPT, arena, owner_node, Vector2(0.0, 0.0),
		Vector2(90.0, 0.0), _spell(0, 260.0, 0.0, 58, 6.4))
	_expect(rt != null, "RaiseThrall instantiates and casts")
	if rt == null:
		return
	_step(rt, 60)   # 1.2 s — well past the windup
	var n: int = int(rt.call(&"raised_count"))
	_expect(n >= 1, "a raise on bare ground stands at least ONE body up (got %d)" % n)
	_expect(_live_thralls(owner_node) == n,
		"every raised body is bound to the caster and in the thrall group")
	await _cleanup([arena])
	_completes("raise_stands_a_real_body_up")


## THE GRAVE IS THE POINT. A raise aimed at a reported death is the better case, in
## the direction the design says: more bodies. Paired with the bare-ground control so
## the assertion cannot pass because both are the same.
func _test_raise_on_a_grave_is_the_better_case() -> void:
	var raise_gs: GDScript = load(RAISE_SCRIPT) as GDScript
	if raise_gs == null:
		return
	var bare_want: int = int(raise_gs.get(&"RAISE_COUNT_BARE"))
	var grave_want: int = int(raise_gs.get(&"RAISE_COUNT_GRAVE"))
	_expect(grave_want > bare_want,
		"a grave raise is authored to yield MORE than bare ground (%d vs %d)"
			% [grave_want, bare_want])
	# --- bare ground control ---
	raise_gs.call(&"clear_graves")
	var arena: FakeArena = _arena()
	var owner_node: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	var bare: Node2D = _cast(RAISE_SCRIPT, arena, owner_node, Vector2(0.0, 0.0),
		Vector2(90.0, 0.0), _spell(0, 260.0, 0.0, 58, 6.4))
	if bare == null:
		return
	_step(bare, 60)
	_expect(not bool(bare.call(&"on_grave")), "no corpse nearby -> the bare case")
	var bare_n: int = int(bare.call(&"raised_count"))
	await _cleanup([arena])
	# --- the grave ---
	raise_gs.call(&"clear_graves")
	var arena2: FakeArena = _arena()
	var owner2: FakeHero = _hero_body(arena2, Vector2(0.0, 0.0))
	var grave_at := Vector2(96.0, 0.0)
	raise_gs.call(&"note_grave", grave_at)
	var onit: Node2D = _cast(RAISE_SCRIPT, arena2, owner2, Vector2(0.0, 0.0),
		Vector2(90.0, 0.0), _spell(0, 260.0, 0.0, 58, 6.4))
	if onit == null:
		return
	_expect(bool(onit.call(&"on_grave")), "a reported death within reach IS found")
	var marks: Array = onit.call(&"marks") as Array
	_expect(not marks.is_empty() and (marks[0] as Vector2).distance_to(grave_at) < 1.0,
		"the first body comes up ON the grave, not beside it")
	_step(onit, 60)
	var grave_n: int = int(onit.call(&"raised_count"))
	_expect(grave_n > bare_n,
		"a grave raise really stands more bodies up than a bare one (%d vs %d)"
			% [grave_n, bare_n])
	raise_gs.call(&"clear_graves")
	await _cleanup([arena2])
	_completes("raise_on_a_grave_is_the_better_case")


## ⚠ BOTH HALVES. The cap is never exceeded across five casts AND the fifth cast
## still stands a body up — the recycle policy means a Warlock at cap must never get
## a dead press, and a cap enforced by fizzling would pass the first half alone.
func _test_raise_never_exceeds_the_owner_cap() -> void:
	var raise_gs: GDScript = load(RAISE_SCRIPT) as GDScript
	if raise_gs == null:
		return
	raise_gs.call(&"clear_graves")
	var cap: int = int(raise_gs.get(&"THRALL_MAX_ALIVE"))
	var arena: FakeArena = _arena()
	var owner_node: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	var peak: int = 0
	var raised_ever: int = 0
	var last: int = 0
	for i: int in 5:
		var rt: Node2D = _cast(RAISE_SCRIPT, arena, owner_node, Vector2(0.0, 0.0),
			Vector2(90.0 + float(i) * 12.0, 0.0), _spell(0, 260.0, 0.0, 58, 6.4))
		if rt == null:
			return
		_step(rt, 60)
		last = int(rt.call(&"raised_count"))
		raised_ever += last
		await physics_frame   # let the recycled bodies' queue_free land
		peak = maxi(peak, _live_thralls(owner_node))
	_expect(raised_ever >= cap,
		"five casts really raised bodies (%d total) — the cap test is not vacuous"
			% raised_ever)
	_expect(last >= 1,
		"the FIFTH cast still stands a body up: at cap the oldest is recycled, never fizzled")
	_expect(peak <= cap,
		"never more than THRALL_MAX_ALIVE (%d) alive at once (peaked at %d)" % [cap, peak])
	await _cleanup([arena])
	_completes("raise_never_exceeds_the_owner_cap")


## THE FLOOR'S BUDGET IS ABSOLUTE. A real `Encounter` with the room already full
## reports zero headroom, and the raise must take that answer — otherwise a Warlock
## walks straight through MAX_LIVE_ENTITIES and tanks the frame rate.
func _test_raise_respects_the_floor_entity_budget() -> void:
	var raise_gs: GDScript = load(RAISE_SCRIPT) as GDScript
	if raise_gs == null:
		return
	raise_gs.call(&"clear_graves")
	var arena: FakeArena = _arena()
	_expect(arena.enc != null, "a real Encounter is available as the budget authority")
	if arena.enc == null:
		return
	var owner_node: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	# Fill the room to MAX_LIVE_ENTITIES with real group members.
	var filler: Array = []
	var cap_total: int = int(load("res://scripts/combat/Encounter.gd").get(&"MAX_LIVE_ENTITIES"))
	for i: int in cap_total:
		var n := Node2D.new()
		n.add_to_group("enemy")
		arena.add_child(n)
		filler.append(n)
	await physics_frame
	_expect(int(arena.enc.call(&"spawn_headroom")) == 0,
		"the Encounter reports a FULL room (headroom 0)")
	var rt: Node2D = _cast(RAISE_SCRIPT, arena, owner_node, Vector2(0.0, 0.0),
		Vector2(90.0, 0.0), _spell(0, 260.0, 0.0, 58, 6.4))
	if rt == null:
		return
	_step(rt, 60)
	_expect(int(rt.call(&"raised_count")) == 0,
		"a full floor raises NOTHING — the entity budget wins over the spell")
	_expect(_live_thralls(owner_node) == 0, "...and no thrall snuck onto the board")
	await _cleanup([arena])
	_completes("raise_respects_the_floor_entity_budget")


# ══════════════════════════════════════════════════ THE SPECTACLE CONTRACT
## `set()` on an undeclared property is a SILENT no-op. A spectacle missing
## `caster_node` is unowned — and for Raise Thrall the caster is also the OWNER, so
## a missing declaration means thralls that answer to nobody and count against no cap.
func _test_raise_declares_every_stamped_property() -> void:
	_assert_stamped(RAISE_SCRIPT, "RaiseThrall")
	_completes("raise_declares_every_stamped_property")


func _test_tide_declares_every_stamped_property() -> void:
	_assert_stamped(TIDE_SCRIPT, "GraveTide")
	_completes("tide_declares_every_stamped_property")


func _assert_stamped(path: String, label: String) -> void:
	var gs: GDScript = load(path) as GDScript
	_expect(gs != null, "%s loads" % label)
	if gs == null:
		return
	var n: Node2D = gs.new()
	var declared: Dictionary = {}
	for p: Dictionary in n.get_property_list():
		declared[String(p.get("name", ""))] = true
	for prop: String in STAMPED:
		_expect(declared.has(prop),
			"%s DECLARES `%s` (set() on an undeclared property is a silent no-op)"
				% [label, prop])
	_expect(int(n.get("element_id")) == Elements.Element.SHADOW,
		"%s declares a REAL element — -1 would drop it out of the reaction system"
			% label)
	n.free()


## The HEX arm calls one fixed entry point on every script in its table. A spectacle
## with a different arity is dispatched into silence — nothing errors, nothing warns.
func _test_entry_points_match_the_hex_arm() -> void:
	for path: String in [RAISE_SCRIPT, TIDE_SCRIPT]:
		var gs: GDScript = load(path) as GDScript
		if gs == null:
			continue
		var n: Node2D = gs.new()
		var found: bool = false
		for m: Dictionary in n.get_method_list():
			if String(m.get("name", "")) != "hex":
				continue
			found = true
			_expect((m.get("args", []) as Array).size() == 6,
				"%s.hex takes the arm's SIX arguments (caster, origin, target, spell, color, fx)"
					% path)
		_expect(found, "%s exposes `hex` — the HEX arm's fixed entry point" % path)
		n.free()
	_completes("entry_points_match_the_hex_arm")


# ══════════════════════════════════════════════════════════════ THE TIDE
## The ULT does its job: it CATCHES bodies the front crosses, roots them, bleeds them
## and feeds the caster. Every one of those is asserted positively — an empty catch
## satisfies "the caster was never caught" and would be a passing test that proves
## the spell inert.
func _test_tide_catches_a_real_body_and_drains_it() -> void:
	var arena: FakeArena = _arena()
	var caster: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	var near: FakeBody = _body(arena, Vector2(140.0, 0.0))
	var far: FakeBody = _body(arena, Vector2(-260.0, 0.0))
	var high: FakeBody = _body(arena, Vector2(220.0, -180.0))   # airborne: dodged
	await physics_frame
	var tide: Node2D = _cast(TIDE_SCRIPT, arena, caster, Vector2(0.0, 0.0),
		Vector2(200.0, 0.0), _spell(40, 520.0, 0.0, 74, 9.0))
	_expect(tide != null, "GraveTide instantiates and casts")
	if tide == null:
		return
	_step(tide, 90)   # 1.8 s — past the lead, past the travel, into the grip
	_expect(int(tide.call(&"caught_count")) >= 2,
		"the tide sweeps BOTH ways and catches both grounded bodies (got %d)"
			% int(tide.call(&"caught_count")))
	_expect(near.taken > 0 and far.taken > 0, "both caught bodies took damage")
	_expect(near.statuses >= 2, "a caught body is ROOTED and WEAKENED (earth + shadow)")
	_expect(high.taken == 0,
		"a body 180 px above the floor is NOT caught — a jump clears the tide")
	_expect(int(tide.call(&"drained_total")) > 0, "the grip bleeds its victims over time")
	_expect(caster.healed > 0, "...and the blood goes into the caster")
	_expect(int(tide.call(&"healed_total")) == caster.healed,
		"the spell's own drain readout agrees with what the caster actually received")
	await _cleanup([arena])
	_completes("tide_catches_a_real_body_and_drains_it")


## The one body the tide may never take. Structural rather than a special case —
## `SpellTargets.hostiles()` subtracts the spectacle's own `caster_node` — but the
## whole spell is worthless if the stamp is ever dropped, so it is pinned.
func _test_tide_never_catches_its_own_caster() -> void:
	var arena: FakeArena = _arena()
	var caster: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	var partner: FakeHero = _hero_body(arena, Vector2(150.0, 0.0))
	await physics_frame
	var tide: Node2D = _cast(TIDE_SCRIPT, arena, caster, Vector2(0.0, 0.0),
		Vector2(200.0, 0.0), _spell(40, 520.0, 0.0, 74, 9.0))
	if tide == null:
		return
	_step(tide, 90)
	_expect(caster.taken == 0, "the tide NEVER catches the necromancer who opened it")
	_expect(partner.taken > 0,
		"...but it does take the other hero — friendly fire is the social engine")
	await _cleanup([arena])
	_completes("tide_never_catches_its_own_caster")


## THE HEAL CAP IS THE BALANCE OF THE SPELL. Six bodies must not feed six bodies'
## worth — otherwise the ult is a full heal on a 9 s cooldown.
func _test_tide_heal_is_capped_by_body_count() -> void:
	var tide_gs: GDScript = load(TIDE_SCRIPT) as GDScript
	if tide_gs == null:
		return
	var max_bodies: int = int(tide_gs.get(&"MAX_HEAL_BODIES"))
	var per_tick: int = int(tide_gs.get(&"HEAL_PER_TICK"))
	var arena: FakeArena = _arena()
	var caster: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	for i: int in 6:
		_body(arena, Vector2(80.0 + float(i) * 40.0, 0.0))
	await physics_frame
	var tide: Node2D = _cast(TIDE_SCRIPT, arena, caster, Vector2(0.0, 0.0),
		Vector2(200.0, 0.0), _spell(40, 520.0, 0.0, 74, 9.0))
	if tide == null:
		return
	_step(tide, 90)
	var caught: int = int(tide.call(&"caught_count"))
	_expect(caught > max_bodies,
		"more bodies were caught (%d) than the heal cap allows (%d) — the cap is exercised"
			% [caught, max_bodies])
	# One grip's worth of ticks, capped: the total must never exceed the cap * per
	# tick * the number of ticks that could physically have fired.
	var ticks: int = int(ceil(float(tide_gs.get(&"HOLD_TIME"))
		/ float(tide_gs.get(&"DRAIN_EVERY")))) + 1
	_expect(caster.healed <= max_bodies * per_tick * ticks,
		"the heal is capped at %d bodies per tick (healed %d, ceiling %d)"
			% [max_bodies, caster.healed, max_bodies * per_tick * ticks])
	_expect(caster.healed > 0, "...and it still heals for something")
	await _cleanup([arena])
	_completes("tide_heal_is_capped_by_body_count")


## The front is a real moving thing that stops where the geometry says. With a real
## floor slab under it the tide walks the ground path; with nothing it degrades to a
## flat line rather than refusing to exist (the headless case).
func _test_tide_front_travels_and_stops() -> void:
	var arena: FakeArena = _arena()
	var slab: StaticBody2D = _floor_slab(-700.0, 700.0, 0.0)
	var caster: FakeHero = _hero_body(arena, Vector2(0.0, -10.0))
	await physics_frame
	await physics_frame
	var tide: Node2D = _cast(TIDE_SCRIPT, arena, caster, Vector2(0.0, 0.0),
		Vector2(200.0, 0.0), _spell(40, 400.0, 0.0, 74, 9.0))
	if tide == null:
		return
	var spans: Array = tide.call(&"span_totals") as Array
	_expect(spans.size() == 2, "the tide opens BOTH ways — two fronts, not a lane")
	_step(tide, 8)
	var early: Array = tide.call(&"front_distances") as Array
	_step(tide, 90)
	var late: Array = tide.call(&"front_distances") as Array
	if early.size() == 2 and late.size() == 2 and spans.size() == 2:
		_expect(float(late[0]) > float(early[0]), "the front actually advances")
		_expect(float(late[0]) <= float(spans[0]) + 0.01,
			"...and never runs past the span the world allowed it")
		_expect(float(spans[0]) > 100.0,
			"the span is a real crossing of the room, not a stub (%.0f px)" % float(spans[0]))
	await _cleanup([arena, slab])
	_completes("tide_front_travels_and_stops")


## `_draw` really does run under --headless (measured, see SpawnTell), and a runtime
## error inside it ABORTS the function while the engine emits `draw` anyway — so
## "it drew" proves nothing and `entered > completed` is the only observable symptom.
func _test_spectacles_draw_without_aborting() -> void:
	var arena: FakeArena = _arena()
	var caster: FakeHero = _hero_body(arena, Vector2(0.0, 0.0))
	_body(arena, Vector2(150.0, 0.0))
	await physics_frame
	var rt: Node2D = _cast(RAISE_SCRIPT, arena, caster, Vector2(0.0, 0.0),
		Vector2(90.0, 0.0), _spell(0, 260.0, 0.0, 58, 6.4))
	var tide: Node2D = _cast(TIDE_SCRIPT, arena, caster, Vector2(0.0, 0.0),
		Vector2(200.0, 0.0), _spell(40, 520.0, 0.0, 74, 9.0))
	if rt == null or tide == null:
		return
	# Engine physics OFF, or both spectacles run on two clocks at once and free
	# themselves before the redraws have been counted.
	rt.set_physics_process(false)
	tide.set_physics_process(false)
	for _i: int in 25:
		if is_instance_valid(rt):
			rt.call(&"_physics_process", STEP)
			rt.queue_redraw()
		if is_instance_valid(tide):
			tide.call(&"_physics_process", STEP)
			tide.queue_redraw()
		await physics_frame
	for pair: Array in [[rt, "RaiseThrall"], [tide, "GraveTide"]]:
		# `is_instance_valid` BEFORE the cast: casting an already-freed object is
		# itself a runtime error, which would abort this test rather than skip a row.
		if not is_instance_valid(pair[0]):
			continue
		var n: Node2D = pair[0]
		var counts: Vector2i = n.call(&"draw_counts") as Vector2i
		_expect(counts.x > 0, "%s._draw ran at all (%d entries)" % [pair[1], counts.x])
		_expect(counts.x == counts.y,
			"%s._draw never aborted part-way (%d entered, %d completed)"
				% [pair[1], counts.x, counts.y])
	await _cleanup([arena])
	_completes("spectacles_draw_without_aborting")
