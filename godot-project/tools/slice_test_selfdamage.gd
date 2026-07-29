# Run: godot --headless --path godot-project --script tools/slice_test_selfdamage.gd
# Task 5: (a) a bolt must NEVER damage its own caster — MAGE/ROGUE/STORMCALLER
# bolts previously spawned with Spell.caster == null (spell.set("caster", self)
# only ran inside the `if bolt_heal > 0` block), so with co-op friendly-fire
# collision live (Net active) they could self-hit; (b) a melee swing auto-
# targets the nearest in-range enemy even when the cursor isn't aimed at them.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead member read (a field that was renamed or moved) is NOT a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function, and hands the
# caller back the return type's zero value. Under the old `failed += _test_x()`
# idiom that reads as "zero failures", so the suite printed all PASS while
# silently skipping every assertion after the dead line. Static typing does not
# help — a typed reference to a renamed field compiles clean and dies the same way.
# So: failures accumulate on the MEMBER `_fails` (an abort cannot discard them),
# and every test's last line records that it reached the end. A test that aborts
# part-way is then missing from `_completed` and fails the suite BY ABSENCE.

## Every test that must run to completion. A name missing from `_completed`
## at the end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"bolt_sets_caster_for_every_class",
	"try_damage_never_hits_caster",
	"melee_autotargets_nearest_enemy",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const SPELL_PATH: String = "res://scripts/combat/Spell.gd"

var _ran: bool = false


class StubEnemy:
	extends Node2D
	var hp: int = 100
	var hit_count: int = 0
	func take_damage(a: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		hp -= a
		hit_count += 1
	func apply_knockback(_v: Vector2) -> void:
		pass
	func apply_status(_e: int, _c: bool = true) -> void:
		pass


## Minimal stand-in for the /root/Net autoload: reports an active co-op session
## without spinning up a real ENet loopback. Spell._ready() and Hero._ready()
## only ever call is_active() on it during these tests (the self-damage guard
## fix short-circuits before anything else on Net would be touched).
class FakeNet:
	extends Node
	func is_active() -> bool:
		return true


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_bolt_sets_caster_for_every_class()
	_test_try_damage_never_hits_caster()
	_test_melee_autotargets_nearest_enemy()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("selfdamage tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("selfdamage tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being discarded with the
## aborted function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." A name missing from `_completed`
## means that test aborted part-way. See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Swaps the live /root/Net autoload for a FakeNet reporting is_active()==true,
## so Spell._ready()'s co-op friendly-fire collision_mask branch (the branch the
## self-damage bug actually lived in) is exercised. Returns the real node so it
## can be restored — the whole swap is synchronous, single-threaded GDScript
## with no awaits in between, so nothing else ever observes the substitution.
func _force_net_active() -> Node:
	var real_net: Node = root.get_node_or_null("/root/Net")
	if real_net != null:
		root.remove_child(real_net)
	var fake := FakeNet.new()
	fake.name = "Net"
	root.add_child(fake)
	return real_net


func _restore_net(real_net: Node) -> void:
	var fake: Node = root.get_node_or_null("/root/Net")
	if fake != null:
		root.remove_child(fake)
		fake.free()
	if real_net != null:
		root.add_child(real_net)


## MAGE(0) / ROGUE(1) / STORMCALLER(6) are the three bolt classes with no
## bolt_heal flavour (Hero.gd's enum HeroClass) — the ones that previously
## fired with Spell.caster == null. Fires each class's real primary bolt via
## _cast(), confirms the spawned spell's caster is the hero, then feeds the
## bolt back at its own caster through the real _try_damage hit path and
# confirms it never lands.
func _test_bolt_sets_caster_for_every_class() -> void:
	var real_net: Node = _force_net_active()
	for cls: int in [0, 1, 6]:
		var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
		root.add_child(hero)
		hero.configure_class(cls)
		hero.set("_aim_dir", Vector2.RIGHT)
		hero.set("facing", Vector2.RIGHT)
		var hp_before: int = int(hero.get("hp"))
		var pct_before: float = float(hero.get("damage_pct"))
		hero.call("_cast")
		var spells: Array = get_nodes_in_group("player_spell")
		_expect(not spells.is_empty(), "class %d bolt spawned a player_spell" % cls)
		if not spells.is_empty():
			var spell: Node = spells[spells.size() - 1]
			_expect(spell.get("caster") == hero, "class %d bolt caster == hero" % cls)
			# The bolt spawns overlapping its own caster; drive the real hit
			# handler with the caster as the "hit" node and confirm nothing lands.
			spell.call("_try_damage", hero)
			_expect(int(hero.get("hp")) == hp_before, "class %d bolt never drops caster hp" % cls)
			_expect(float(hero.get("damage_pct")) == pct_before, "class %d bolt never raises caster damage_pct" % cls)
			_expect(not bool(spell.get("_dead")), "class %d bolt isn't consumed hitting its own caster" % cls)
		for s: Node in spells:
			s.queue_free()
		hero.queue_free()
	_restore_net(real_net)
	_completes("bolt_sets_caster_for_every_class")


## Defensive backstop: Spell._try_damage must no-op whenever node == caster,
## regardless of the node's group — belt-and-suspenders even if some future
## call site forgets to set caster in time, independent of Net's live state.
func _test_try_damage_never_hits_caster() -> void:
	var s := Node2D.new()
	root.add_child(s)
	var stub := StubEnemy.new()
	stub.add_to_group("hero")  # standing in for the caster's own hero body
	s.add_child(stub)
	var spell: Area2D = (load(SPELL_PATH) as GDScript).new()
	s.add_child(spell)  # runs _ready() (group + collision mask)
	spell.set("caster", stub)
	spell.call("_try_damage", stub)
	_expect(stub.hit_count == 0, "_try_damage never calls take_damage on its own caster")
	_expect(not bool(spell.get("_dead")), "spell isn't consumed by hitting its own caster")
	root.remove_child(s)
	s.free()
	_completes("try_damage_never_hits_caster")


## Melee auto-target: the cursor points RIGHT (facing = RIGHT) but the only
## enemy in range sits directly BEHIND (LEFT) — well outside the old strict
## facing.dot(toward) <= _melee_arc_dot cone (dot ~ -1.0 <<= 0.3). The swing
## must still connect because the nearest in-range enemy always auto-targets.
func _test_melee_autotargets_nearest_enemy() -> void:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.configure_class(2)  # BRAWLER — default MELEE_ARC_DOT (0.3), no override
	hero.global_position = Vector2.ZERO
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.set("facing", Vector2.RIGHT)
	var enemy := StubEnemy.new()
	enemy.add_to_group("enemy")
	enemy.global_position = Vector2(-20.0, 0.0)  # within _melee_range, opposite the cursor
	root.add_child(enemy)
	hero.call("_on_melee_hit_frame")
	_expect(enemy.hit_count > 0, "melee auto-targets the nearest enemy even when the cursor isn't aimed at them")
	# Control: with no enemy at all in range, nothing should hit or crash.
	enemy.global_position = Vector2(500.0, 500.0)  # out of _melee_range
	hero.call("_on_melee_hit_frame")
	_expect(enemy.hit_count == 1, "no false hit once the enemy leaves melee range")
	hero.queue_free()
	enemy.queue_free()
	_completes("melee_autotargets_nearest_enemy")
