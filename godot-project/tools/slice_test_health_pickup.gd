# Run: godot --headless --path godot-project --script tools/slice_test_health_pickup.gd
#
# THE HEALTH PACK, and the two ways it could quietly be wrong.
#
# 1. THE PHOTO FINISH. `WeaponPickup` shipped with a bug `SpellPickup` had already
#    fixed: both peers ran their own overlap test, so a dead heat armed a DIFFERENT
#    hero on each screen and the local `_consumed` latch made the disagreement
#    permanent for the floor. A third pickup family written from scratch is the most
#    likely place for that bug to be reintroduced, so the shape is pinned here:
#    joins the group `Net._client_pickup` scans, exposes `collect_by`, and
#    `collect_by` is idempotent.
#
# 2. THE GHOST. A pack must never resurrect a downed hero — that is the teammate's
#    job (`Revive`), and a pack that can do it turns dying into a shopping trip.
#    Pinned twice: the group literal this file uses must equal `GhostForm.GHOST_GROUP`
#    (a drift there would silently disable the guard), and `collect_by` must refuse a
#    ghosted body outright rather than consuming itself on it.
#
# ⚠ WHAT THIS SUITE CANNOT PROVE: convergence needs two processes. A single SceneTree
# has one MultiplayerAPI, so "the other phone agrees" is unobservable from in here.
# What IS pinned is every half that lives on one side of the wire.
#
# ⚠ THE IDIOM. Failures accumulate on the MEMBER `_fails` and every test records a
# COMPLETION SENTINEL as its last line, so a test that aborts part-way fails the suite
# BY ABSENCE. Never `_fails += _test_x()` — see tools/slice_test_loadout.gd.
extends SceneTree

## ⚠ BY PATH, never by `class_name`. `HealthPickup.gd` names `Sfx` and `CombatVfx`;
## resolving it as a compile-time global would poison this script's whole dependency
## chain with a misleading "Identifier not found" — the same rule the cover/pickup
## suite documents for `BreakablePlatform`.
const HEALTH_SCRIPT: String = "res://scripts/combat/HealthPickup.gd"
const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"

const TESTS: Array[String] = [
	"pack_joins_the_lookup_group",
	"ghost_group_literal_matches_ghostform",
	"full_health_hero_is_not_reported",
	"hurt_hero_is_reported",
	"collect_heals_and_is_idempotent",
	"heal_is_capped_at_max_hp",
	"collect_refuses_a_ghost",
	"routing_is_inert_without_a_session",
	"layout_carries_health_positions",
	"builder_places_a_fallback_pack",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_pack_joins_the_lookup_group()
	_test_ghost_group_literal_matches_ghostform()
	_test_full_health_hero_is_not_reported()
	_test_hurt_hero_is_reported()
	_test_collect_heals_and_is_idempotent()
	_test_heal_is_capped_at_max_hp()
	_test_collect_refuses_a_ghost()
	_test_routing_is_inert_without_a_session()
	_test_layout_carries_health_positions()
	_test_builder_places_a_fallback_pack()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Health pickup tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Health pickup tests: all PASS")
		quit(0)
	return true


# ------------------------------------------------------------------ the race shape
func _test_pack_joins_the_lookup_group() -> void:
	var p: Node2D = _pack()
	_expect(p.is_in_group(&"health_pickup"),
		"HealthPickup is findable by the group Net._client_pickup scans")
	_expect(p.has_method(&"collect_by"),
		"…and exposes collect_by, so ONE host decision drives every peer")
	_kill(p)
	_completes("pack_joins_the_lookup_group")


## The guard is only as good as the string. `HealthPickup` spells the group out as a
## literal (naming `GhostForm` would drag its compile graph in), so the agreement has
## to be asserted rather than assumed.
func _test_ghost_group_literal_matches_ghostform() -> void:
	var gs: GDScript = load(HEALTH_SCRIPT) as GDScript
	var lit: Variant = gs.get(&"GHOST_GROUP")
	_expect(StringName(lit) == GhostForm.GHOST_GROUP,
		"HealthPickup.GHOST_GROUP == GhostForm.GHOST_GROUP (got %s)" % lit)
	_completes("ghost_group_literal_matches_ghostform")


# ------------------------------------------------------ what may even be requested
## Walking over a pack at full health and burning it is the single most annoying
## thing a pickup can do — and the refusal must live BEFORE the host is told, or the
## host latches an award this peer then declines and the pack becomes unspendable.
func _test_full_health_hero_is_not_reported() -> void:
	var p: Node2D = _pack()
	var h: CharacterBody2D = _hero()
	_expect(not bool(p.call(&"_wants_healing", h)), "a full-health hero does not want it")
	p.call(&"_on_body_entered", h)
	_expect(not p.is_queued_for_deletion(), "…so walking over it leaves it standing")
	_kill(h)
	_kill(p)
	_completes("full_health_hero_is_not_reported")


func _test_hurt_hero_is_reported() -> void:
	var p: Node2D = _pack()
	var h: CharacterBody2D = _hero()
	h.set(&"hp", int(h.get(&"max_hp")) / 2)
	_expect(bool(p.call(&"_wants_healing", h)), "a half-health hero wants it")
	var not_a_hero := Node2D.new()
	root.add_child(not_a_hero)
	_expect(not bool(p.call(&"_wants_healing", not_a_hero)),
		"…and a non-hero body never does (an enemy must not vacuum the floor)")
	_kill(not_a_hero)
	_kill(h)
	_kill(p)
	_completes("hurt_hero_is_reported")


# --------------------------------------------------------------------- the award
## The award may arrive twice (the host's `call_local` plus a re-entered overlap).
## The second must be a no-op, or one pack heals for two.
func _test_collect_heals_and_is_idempotent() -> void:
	var p: Node2D = _pack()
	var h: CharacterBody2D = _hero()
	var mx: int = int(h.get(&"max_hp"))
	h.set(&"hp", 1)
	_expect(bool(p.call(&"collect_by", h)), "the first award is taken")
	var after: int = int(h.get(&"hp"))
	_expect(after > 1, "…and it actually healed the hero (1 -> %d of %d)" % [after, mx])
	_expect(not bool(p.call(&"collect_by", h)), "a second award on a spent pack does nothing")
	_expect(int(h.get(&"hp")) == after, "…and did not heal a second time")
	_kill(h)
	_kill(p)
	_completes("collect_heals_and_is_idempotent")


## ⚠ THE CAP. `HpWatch.gain` routes through the body's own `heal()`, which clamps —
## but the clamp is the load-bearing promise here, so it is asserted rather than
## inherited on trust.
func _test_heal_is_capped_at_max_hp() -> void:
	var p: Node2D = _pack()
	var h: CharacterBody2D = _hero()
	var mx: int = int(h.get(&"max_hp"))
	h.set(&"hp", mx - 1)
	_expect(bool(p.call(&"collect_by", h)), "the award lands on a barely-hurt hero")
	_expect(int(h.get(&"hp")) == mx,
		"hp is capped at max_hp (got %d of %d)" % [int(h.get(&"hp")), mx])
	_kill(h)
	_kill(p)
	_completes("heal_is_capped_at_max_hp")


## A pack must NEVER put a ghost back in the fight.
func _test_collect_refuses_a_ghost() -> void:
	var p: Node2D = _pack()
	var h: CharacterBody2D = _hero()
	h.set(&"hp", 1)
	h.add_to_group(GhostForm.GHOST_GROUP)
	_expect(not bool(p.call(&"collect_by", h)), "a ghosted body is refused the award")
	_expect(int(h.get(&"hp")) == 1, "…and is not healed by a single point")
	_expect(not p.is_queued_for_deletion(), "…and the pack is not consumed on it")
	_kill(h)
	_kill(p)
	_completes("collect_refuses_a_ghost")


## Singleplayer must take no branch at all, or every solo pack takes a trip through
## a host that does not exist.
func _test_routing_is_inert_without_a_session() -> void:
	var net: Node = root.get_node_or_null(^"/root/Net")
	if net == null:
		_expect(false, "no Net autoload")
		return
	var p: Node2D = _pack(Vector2(4321.0, 4321.0))
	net.call(&"request_pickup", p, 1)
	_expect(not p.is_queued_for_deletion(),
		"request_pickup with no session does nothing at all")
	_kill(p)
	_completes("routing_is_inert_without_a_session")


# ------------------------------------------------------------------- the authoring
func _test_layout_carries_health_positions() -> void:
	var l := LayoutDef.new()
	_expect(l.health_pickups.is_empty(), "a fresh LayoutDef authors no packs")
	l.health_pickups = [Vector2(100.0, 200.0)]
	_expect(l.health_pickups.size() == 1, "…and the array takes authored positions")
	_completes("layout_carries_health_positions")


## ⚠ THE FALLBACK IS THE REASON PACKS EXIST ON THE NEXT F5. Every authoring table
## (`GameState`, `FloorGen`) is owned elsewhere and none of them names
## `health_pickups` yet, so an authored-only builder would ship a tower with no
## healing in it and no error anywhere. Both branches are pinned.
func _test_builder_places_a_fallback_pack() -> void:
	var room := Node2D.new()
	root.add_child(room)
	var l := LayoutDef.new()
	FloorBuilder.build_health_packs(room, l)
	_expect(room.get_child_count() == FloorBuilder.DEFAULT_HEALTH_PACKS.size(),
		"an unauthored layout still gets %d packs (got %d)"
			% [FloorBuilder.DEFAULT_HEALTH_PACKS.size(), room.get_child_count()])
	for c: Node in room.get_children():
		_expect(c.is_in_group(&"health_pickup"), "…and each one joined the lookup group")
	for c: Node in room.get_children():
		room.remove_child(c)
		c.free()
	l.health_pickups = [Vector2(300.0, 120.0)]
	FloorBuilder.build_health_packs(room, l)
	_expect(room.get_child_count() == 1,
		"an authored layout takes over completely (got %d)" % room.get_child_count())
	_kill(room)
	_completes("builder_places_a_fallback_pack")


# ------------------------------------------------------------------------ fixtures
## A real pack from the real script. The `_ready` group join and the collision setup
## both matter, and a hand-built Area2D would prove neither.
func _pack(at: Vector2 = Vector2(7000.0, 7000.0)) -> Node2D:
	var p: Node2D = (load(HEALTH_SCRIPT) as GDScript).new() as Node2D
	root.add_child(p)
	p.global_position = at
	return p


## A REAL Hero, not a stub. `collect_by` routes through `HpWatch.gain` -> `heal()`,
## and a stub taught `heal` just to satisfy this would be a fixture more generous than
## the shipped class — which is how a green suite ends up proving nothing.
func _hero(at: Vector2 = Vector2(9000.0, 9000.0)) -> CharacterBody2D:
	var h: CharacterBody2D = (load(HERO_SCENE) as PackedScene).instantiate()
	root.add_child(h)
	h.global_position = at
	return h


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Immediate, not `queue_free`: every test here runs inside ONE frame, so a queued
## free leaves the fixture in its group for the next test to trip over.
func _kill(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	for g: StringName in n.get_groups():
		n.remove_from_group(g)
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.free()
