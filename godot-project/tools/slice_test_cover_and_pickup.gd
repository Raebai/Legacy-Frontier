# Run: godot --headless --path godot-project --script tools/slice_test_cover_and_pickup.gd
#
# THE TWO THINGS THAT USED TO BE SCORED SEPARATELY ON EACH PHONE.
#
# 1. COVER. Enemy attack twins are `visual_only`, so a crate an enemy blew up existed
#    on the host and stood untouched on the client — you take cover behind something
#    your teammate cannot see. (Hero-sourced prop damage always converged: a hero's
#    spell is rebuilt as a twin on the other peer, and although the twin's FIGHTER
#    scan is pointed at a dead group, every spectacle scans the "destructible" literal
#    as a second, un-stamped pass.) Props are now host-authoritative, with ABSOLUTE hp
#    on the wire so a client can still predict a hit without the two compounding.
#
# 2. THE PICKUP RACE. Both peers spawned the same seeded drop — solid — but collection
#    resolved locally, so a photo finish could give it to both players, or to different
#    players on the two screens. One peer reports, the host decides once, everyone
#    applies the same award.
#
# ⚠ WHAT THIS SUITE CANNOT PROVE, said plainly: convergence needs two processes. A
# single SceneTree has one MultiplayerAPI, so it can be a host or a client but never
# both, and "the other phone agrees" is unobservable from in here. What IS pinned
# below is every half that lives on one side of the wire — singleplayer taking no
# branch at all, the host applying and broadcasting, and `net_apply_prop_state` being
# exactly what a client executes on arrival. `python-tools/coop_smoketest.sh` runs the
# real two-process pair and prints COVER/PICKUP in its VERDICT line; that is the proof.
#
# ⚠ THE IDIOM. Failures accumulate on the MEMBER `_fails` and every test records a
# COMPLETION SENTINEL as its last line, so a test that aborts part-way fails the suite
# BY ABSENCE. Never `_fails += _test_x()` — see tools/slice_test_loadout.gd.
extends SceneTree

const PROP_SCENE: String = "res://scenes/combat/DestructibleProp.tscn"
const PLATFORM_SCRIPT: String = "res://scripts/combat/BreakablePlatform.gd"
const WEAPON_SCRIPT: String = "res://scripts/combat/WeaponPickup.gd"
const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"

const TESTS: Array[String] = [
	"singleplayer_prop_damage_is_unchanged",
	"prop_publishes_the_client_hook",
	"host_state_overwrites_absolutely",
	"host_state_can_shatter_outright",
	"host_applies_and_survives_broadcasting",
	"pickup_joins_the_lookup_group",
	"singleplayer_pickup_collects_on_contact",
	"pickup_ignores_everything_that_is_not_a_hero",
	"collect_by_is_idempotent",
	"pickup_routing_is_inert_without_a_session",
	"position_key_is_the_cross_peer_identity",
	"platform_publishes_the_client_hook",
	"platform_host_state_breaks_the_ground",
	"singleplayer_platform_damage_is_unchanged",
	"weapon_pickup_joins_the_lookup_group",
	"weapon_collect_by_is_idempotent",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}

const _StubHero2D: GDScript = preload("res://tools/_stub_hero2d.gd")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_singleplayer_prop_damage_is_unchanged()
	_test_prop_publishes_the_client_hook()
	_test_host_state_overwrites_absolutely()
	_test_host_state_can_shatter_outright()
	_test_host_applies_and_survives_broadcasting()
	_test_pickup_joins_the_lookup_group()
	_test_singleplayer_pickup_collects_on_contact()
	_test_pickup_ignores_everything_that_is_not_a_hero()
	_test_collect_by_is_idempotent()
	_test_pickup_routing_is_inert_without_a_session()
	_test_position_key_is_the_cross_peer_identity()
	_test_platform_publishes_the_client_hook()
	_test_platform_host_state_breaks_the_ground()
	_test_singleplayer_platform_damage_is_unchanged()
	_test_weapon_pickup_joins_the_lookup_group()
	_test_weapon_collect_by_is_idempotent()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Cover/pickup tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Cover/pickup tests: all PASS")
		quit(0)
	return true


# ------------------------------------------- breakable platform (collision geometry)
## The platform is a HARDER case than the crate and had the SAME hole: `_break`
## disables the collider, so a desynced platform is solid ground on one screen and
## open air on the other while both draw the hero at the same coordinates.
func _test_platform_publishes_the_client_hook() -> void:
	var p: Node2D = _platform()
	_expect(p.has_method(&"net_apply_prop_state"),
		"BreakablePlatform exposes net_apply_prop_state")
	_expect(p.is_in_group("destructible"), "…and is findable in the group Net scans")
	_kill(p)
	_completes("platform_publishes_the_client_hook")


## Asserts the COLLIDER, not just hp — hp converging while the collision state did
## not is precisely the bug that would still be invisible from a health check.
func _test_platform_host_state_breaks_the_ground() -> void:
	var p: Node2D = _platform()
	p.call(&"damage_at", 5, p.global_position, Vector2.UP)   # a local prediction
	_expect(not bool(p.get("_broken")), "a non-fatal hit does not break it")
	p.call(&"net_apply_prop_state", 0, true)
	_expect(bool(p.get("_broken")), "the host's shatter verdict breaks it here too")
	var col: Node = p.get("_collider")
	_expect(col != null and bool(col.get("disabled")),
		"THE GROUND: the collider is actually disabled, not just the hp zeroed")
	p.call(&"net_apply_prop_state", 50, false)
	_expect(bool(p.get("_broken")), "…and a late state for a broken platform is ignored")
	_kill(p)
	_completes("platform_host_state_breaks_the_ground")


## Singleplayer must be byte-identical — no Net node, so the guard falls straight
## through to the original path.
func _test_singleplayer_platform_damage_is_unchanged() -> void:
	var p: Node2D = _platform()
	var full: int = int(p.get("hp"))
	p.call(&"take_damage", 10)
	_expect(int(p.get("hp")) == full - 10, "solo: hp drops by exactly the amount")
	p.call(&"take_damage", 10000)
	_expect(bool(p.get("_broken")), "solo: a fatal hit still breaks it locally")
	_kill(p)
	_completes("singleplayer_platform_damage_is_unchanged")


# ------------------------------------------------------- weapon pickup (the race)
func _test_weapon_pickup_joins_the_lookup_group() -> void:
	var w: Node2D = _weapon()
	_expect(w.is_in_group("weapon_pickup"),
		"WeaponPickup is findable by the group Net._client_pickup scans")
	_expect(w.has_method(&"collect_by"),
		"…and exposes collect_by, so ONE host decision drives every peer")
	_kill(w)
	_completes("weapon_pickup_joins_the_lookup_group")


## The award may arrive twice (host `call_local` plus a re-entered overlap). The
## second must be a no-op, or a photo finish arms two heroes.
## A REAL Hero, not the Node2D stub the other tests use. `collect_by` gates on
## `equip_weapon`, which the stub does not have — and a stub taught that method just
## to satisfy this would be a fixture more generous than the shipped class, which is
## how a green suite ends up proving nothing.
func _test_weapon_collect_by_is_idempotent() -> void:
	var w: Node2D = _weapon()
	var h: CharacterBody2D = (load(HERO_SCENE) as PackedScene).instantiate()
	root.add_child(h)
	h.global_position = Vector2(9000, 9000)
	w.weapon_kind = "sword"
	_expect(bool(w.call(&"collect_by", h)), "first award is taken")
	_expect(String(h.get("_weapon")) == "sword", "…and it actually armed the hero")
	_expect(not bool(w.call(&"collect_by", h)), "second award is refused")
	_kill(h)
	_kill(w)
	_completes("weapon_collect_by_is_idempotent")


## ⚠ BOTH LOADED BY PATH, NEVER BY `class_name`. Writing `BreakablePlatform.new()`
## names a global class identifier, which makes THIS script depend on it at COMPILE
## time — and it reaches `Sfx`/`StageLayers`, autoloads that are not registered as
## globals until the main loop is up. The failure does not report as "too early": it
## reports as `Identifier not found: Sfx`, and it poisons the whole compile chain,
## so the unrelated `WeaponPickup` load fails too. Same rule as PROP_SCENE above.
func _platform(at: Vector2 = Vector2(5000, 5000)) -> Node2D:
	var p: Node2D = (load(PLATFORM_SCRIPT) as GDScript).new()
	root.add_child(p)
	p.global_position = at
	return p


func _weapon(at: Vector2 = Vector2(8000, 8000)) -> Node2D:
	var w: Node2D = (load(WEAPON_SCRIPT) as GDScript).new()
	root.add_child(w)
	w.global_position = at
	return w


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ helpers
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


## A real crate from the real scene — the collision layers, the hp export and the
## `_ready` group join all matter, and a hand-built StaticBody2D would prove none
## of them.
func _crate(at: Vector2 = Vector2.ZERO) -> Node2D:
	var c: Node2D = (load(PROP_SCENE) as PackedScene).instantiate()
	root.add_child(c)
	c.global_position = at
	return c


func _hero(cls: int, at: Vector2) -> Node2D:
	var n := Node2D.new()
	n.set_script(_StubHero2D)
	var sigs: Array = SpellLibrary.build_for_class(cls)
	var hand := HandSlots.new()
	hand.rebuild([], sigs)
	n.set("_signatures", sigs)
	n.set("_hand", hand)
	n.add_to_group("hero")
	n.global_position = at
	root.add_child(n)
	return n


func _pickup(id: String, at: Vector2) -> SpellPickup:
	var p := SpellPickup.new()
	root.add_child(p)
	p.global_position = at
	p.set_spell(id)
	return p


## The id of a real drop, so the pickup resolves to a real SpellDef.
func _drop_id() -> String:
	var all: Array = SpellLibrary.build_tier2()
	return "" if all.is_empty() else String((all[0] as SpellDef).id)


func _net() -> Node:
	return root.get_node_or_null(^"/root/Net")


# ------------------------------------------------------------------- tests
## SINGLEPLAYER TAKES NO BRANCH. `Net.is_active()` is false (Godot's
## `OfflineMultiplayerPeer` exclusion is load-bearing — it once left ~40 co-op gates
## silently open in SP) so `take_damage` is the code that always ran.
func _test_singleplayer_prop_damage_is_unchanged() -> void:
	var net: Node = _net()
	_expect(net != null and not bool(net.call(&"is_active")),
		"no session -> Net.is_active() is false")
	var c: Node2D = _crate()
	var full: int = int(c.get("max_hp"))
	c.call(&"take_damage", 5)
	_expect(int(c.get("hp")) == full - 5, "a non-fatal hit takes hp locally (%d)" % int(c.get("hp")))
	c.call(&"take_damage", 9999)
	_expect(c.is_queued_for_deletion(), "a fatal hit shatters it there and then")
	_expect(not c.is_in_group("destructible"),
		"…and it leaves the group immediately, so a same-frame radius query cannot re-hit it")
	_completes("singleplayer_prop_damage_is_unchanged")


## The hook the host's broadcast calls on every other peer. Without it `Net` silently
## drops the state and cover diverges exactly as before — with no error anywhere.
func _test_prop_publishes_the_client_hook() -> void:
	var c: Node2D = _crate()
	_expect(c.has_method(&"net_apply_prop_state"),
		"DestructibleProp exposes net_apply_prop_state")
	_expect(c.is_in_group("destructible"), "…and is findable in the group Net scans")
	_expect(not c.is_in_group(&"mortal"),
		"…and is still NOT in `mortal` (being in both means every hit lands twice)")
	_kill(c)
	_completes("prop_publishes_the_client_hook")


## ABSOLUTE hp, not a delta. That is the whole reason a client may keep predicting its
## own hits: the host's number OVERWRITES the prediction instead of compounding with
## it, so a mispredicted crate is corrected rather than doubly damaged.
func _test_host_state_overwrites_absolutely() -> void:
	var c: Node2D = _crate()
	c.call(&"take_damage", 7)          # a local prediction
	c.call(&"net_apply_prop_state", 21, false)
	_expect(int(c.get("hp")) == 21, "the host's absolute hp wins (got %d)" % int(c.get("hp")))
	c.call(&"net_apply_prop_state", 21, false)
	_expect(int(c.get("hp")) == 21, "…and re-applying the same state is not a second hit")
	_kill(c)
	_completes("host_state_overwrites_absolutely")


## The kill is the host's to call. A client never shatters on its own arithmetic —
## there is no way to put cover back once it has burst.
func _test_host_state_can_shatter_outright() -> void:
	var c: Node2D = _crate()
	c.call(&"net_apply_prop_state", 0, true)
	_expect(c.is_queued_for_deletion(), "the host's shatter verdict destroys it")
	_expect(not c.is_in_group("destructible"), "…and drops it out of the scan group")
	_completes("host_state_can_shatter_outright")


## With a live session this peer IS the host, so `take_damage` runs its normal
## arithmetic AND broadcasts. Nobody is listening on a one-peer server, which is the
## point: the broadcast must be harmless, not merely correct.
func _test_host_applies_and_survives_broadcasting() -> void:
	var net: Node = _net()
	if net == null:
		_expect(false, "no Net autoload")
		return
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(24999, 1)
	if err != OK:
		# A blocked port is an environment failure, not a code failure. Say so out loud
		# rather than passing quietly, and rather than failing the tree for it.
		print("  (skipped host branch: could not bind test port, err=%d)" % err)
		_completes("host_applies_and_survives_broadcasting")
		return
	root.multiplayer.multiplayer_peer = peer
	_expect(bool(net.call(&"is_active")), "a live peer -> is_active()")
	_expect(bool(net.call(&"is_host")), "…and this peer is the host")
	var c: Node2D = _crate(Vector2(120.0, 80.0))
	c.call(&"take_damage", 4)
	_expect(int(c.get("hp")) == int(c.get("max_hp")) - 4,
		"the host still applies its own damage (got %d)" % int(c.get("hp")))
	c.call(&"take_damage", 9999)
	_expect(c.is_queued_for_deletion(), "…and still shatters on the fatal one")
	root.multiplayer.multiplayer_peer = null
	peer.close()
	_expect(not bool(net.call(&"is_active")), "session torn down -> back to singleplayer")
	_completes("host_applies_and_survives_broadcasting")


## The group is how `Net` finds this pickup on the other peer. Crates and drops are
## built per-peer rather than spawned, so their auto-names differ between the two
## phones and a NodePath would resolve to null — or to the wrong node.
func _test_pickup_joins_the_lookup_group() -> void:
	var id: String = _drop_id()
	_expect(id != "", "the library has a Tier 2 to drop")
	var p: SpellPickup = _pickup(id, Vector2(300.0, 200.0))
	_expect(p.is_in_group(SpellPickup.PICKUP_GROUP),
		"the pickup joins '%s'" % SpellPickup.PICKUP_GROUP)
	_expect(p.has_method(&"collect_by"), "…and exposes collect_by for the award")
	_kill(p)
	_completes("pickup_joins_the_lookup_group")


## SINGLEPLAYER IS A DIRECT CALL. No round trip, no host, no latency — the same code
## that always ran.
func _test_singleplayer_pickup_collects_on_contact() -> void:
	var id: String = _drop_id()
	var hero: Node2D = _hero(0, Vector2.ZERO)
	var p: SpellPickup = _pickup(id, Vector2.ZERO)
	p._on_body_entered(hero)
	_expect(p.is_queued_for_deletion(), "walking over it takes it")
	var got: Dictionary = SpellGrant.held(hero)
	_expect(not got.is_empty() and String((got.get("spell") as SpellDef).id) == id,
		"…and the hero is holding '%s'" % id)
	_kill(hero)
	_completes("singleplayer_pickup_collects_on_contact")


## An enemy, a crate or a stray projectile body must not vacuum the floor's drop.
func _test_pickup_ignores_everything_that_is_not_a_hero() -> void:
	var id: String = _drop_id()
	var p: SpellPickup = _pickup(id, Vector2.ZERO)
	var not_a_hero := Node2D.new()
	root.add_child(not_a_hero)
	p._on_body_entered(not_a_hero)
	_expect(not p.is_queued_for_deletion(), "a non-hero body leaves the pickup standing")
	_kill(not_a_hero)
	_kill(p)
	_completes("pickup_ignores_everything_that_is_not_a_hero")


## THE PHOTO FINISH'S LAST LINE OF DEFENCE. The host awards once, but RPCs are not a
## promise about how many times a method is entered — a re-sent award, or a second
## overlap that beat the free, must not mint a second copy of the spell.
func _test_collect_by_is_idempotent() -> void:
	var id: String = _drop_id()
	var a: Node2D = _hero(0, Vector2.ZERO)
	var b: Node2D = _hero(1, Vector2(50.0, 0.0))
	var p: SpellPickup = _pickup(id, Vector2.ZERO)
	_expect(bool(p.collect_by(a)), "the first award lands")
	_expect(not bool(p.collect_by(b)), "a second award on a spent pickup does nothing")
	_expect(SpellGrant.held(b).is_empty(), "…and the loser of the race holds nothing")
	_kill(a)
	_kill(b)
	_completes("collect_by_is_idempotent")


## The routing must be a NO-OP without a session, or every solo pickup would take a
## trip through a host that does not exist.
func _test_pickup_routing_is_inert_without_a_session() -> void:
	var net: Node = _net()
	if net == null:
		_expect(false, "no Net autoload")
		return
	var id: String = _drop_id()
	var p: SpellPickup = _pickup(id, Vector2(88.0, 88.0))
	net.call(&"request_pickup", p, 1)
	_expect(not p.is_queued_for_deletion(),
		"request_pickup with no session does nothing at all")
	_kill(p)
	_completes("pickup_routing_is_inert_without_a_session")


## THE WIRE IDENTITY. Both peers place a crate at the same world point from the same
## `LayoutDef`, and neither crates nor pickups ever move — so the rounded position is
## a name both phones already agree on, without a packet spent agreeing.
func _test_position_key_is_the_cross_peer_identity() -> void:
	var net: Node = _net()
	if net == null:
		_expect(false, "no Net autoload")
		return
	var a: Node2D = _crate(Vector2(240.0, 130.0))
	var b: Node2D = _crate(Vector2(720.0, 130.0))
	var ka: Vector2i = net.call(&"pos_key", a)
	var kb: Vector2i = net.call(&"pos_key", b)
	_expect(ka == Vector2i(240, 130), "the key is the rounded position (got %s)" % ka)
	_expect(ka != kb, "two crates on a floor have different keys")
	# Sub-pixel drift between peers (float maths on two machines) must still match.
	var c: Node2D = _crate(Vector2(240.3, 129.8))
	_expect(net.call(&"pos_key", c) == ka, "a sub-pixel difference rounds to the same key")
	_kill(a)
	_kill(b)
	_kill(c)
	_completes("position_key_is_the_cross_peer_identity")
