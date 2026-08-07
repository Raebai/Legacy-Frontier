# THE FIVE NEW TIER 3 DROPS ACTUALLY FIRE, AND EACH BENDS ITS OWN RULE.
#
# The catalog suites already assert the SHAPE of a drop (charges, element, shelf,
# a dispatch row, the five stamped vars). None of them casts one. This does: it
# stands each spectacle up, drives its clock, and asserts the ONE rule that makes
# it different from the other eight — because a Tier 3 that resolves to "a big
# number in a circle" is the recolour the class-identity ruling forbids.
#
#   godot --headless --path godot-project --script tools/slice_test_new_drops.gd
extends SceneTree

const TESTS: Array[String] = [
	"severance_prices_itself_off_missing_health",
	"zanshin_gets_stronger_with_more_bodies",
	"teardown_prices_itself_off_the_arena",
	"siegeworks_only_ever_closes",
	"the_circuit_has_no_range_limit",
	"every_new_drop_is_pinned_to_exactly_one_class",
]

var _failures: Array[String] = []
var _ran: Dictionary = {}
var _started: bool = false


class Dummy:
	extends CharacterBody2D
	var hp: int = 100
	var max_hp: int = 100
	var taken: Array[int] = []

	func take_damage(amount: int) -> void:
		taken.append(amount)
		hp = maxi(hp - amount, 0)

	func apply_knockback(_v: Vector2) -> void:
		pass

	func hit_margin() -> float:
		return 0.0


func _process(_d: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _run() -> void:
	_test_severance_prices_itself_off_missing_health()
	_test_zanshin_gets_stronger_with_more_bodies()
	_test_teardown_prices_itself_off_the_arena()
	_test_siegeworks_only_ever_closes()
	_test_the_circuit_has_no_range_limit()
	_test_every_new_drop_is_pinned_to_exactly_one_class()
	for n: String in TESTS:
		if not _ran.has(n):
			_failures.append("test `%s` is registered but never ran to completion" % n)
	if _failures.is_empty():
		print("New drop tests: all PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("FAIL: %s" % f)
		print("New drop tests: %d FAILED" % _failures.size())
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _completes(n: String) -> void:
	_ran[n] = true


## A spectacle, stood up and cast the way `SpellCaster` does it.
func _cast(script_path: String, spell_id: String, at: Vector2) -> Node2D:
	var spell: SpellDef = SpellLibrary.drop_by_id(spell_id)
	var node: Node2D = (load(script_path) as GDScript).new() as Node2D
	root.add_child(node)
	node.set("target_group", "enemy")
	node.set("_target_group", "enemy")
	node.set("caster_node", null)
	node.call("cataclysm", null, at, at, spell, Color.WHITE, "")
	return node


func _dummy(at: Vector2, hp: int = 100) -> Dummy:
	var d := Dummy.new()
	root.add_child(d)
	d.global_position = at
	d.hp = hp
	d.add_to_group("enemy")
	d.add_to_group(SpellCaster.MORTAL_GROUP)
	return d


# ─────────────────────────────────────────────────────────────────────── tests

## THE RULE: every other damage number in the game is flat. This one is not.
func _test_severance_prices_itself_off_missing_health() -> void:
	var n: Node2D = _cast("res://scripts/combat/Severance.gd", "severance", Vector2(0, -9000))
	var healthy: int = int(n.call("toll_for", 100, 100))
	var hurt: int = int(n.call("toll_for", 5, 100))
	_expect(hurt > healthy * 3,
		"severance hits a dying body far harder than a healthy one (%d vs %d)"
		% [hurt, healthy])
	_expect(healthy > 0, "...but a healthy target is still worth casting on (%d)" % healthy)
	n.free()
	_completes("severance_prices_itself_off_missing_health")


## THE RULE: every other area spell splits or stays flat. This one multiplies.
func _test_zanshin_gets_stronger_with_more_bodies() -> void:
	var n: Node2D = _cast("res://scripts/combat/Zanshin.gd", "zanshin", Vector2(0, -9000))
	var one: int = int(n.call("toll_for", 1))
	var four: int = int(n.call("toll_for", 4))
	_expect(four > one, "zanshin pays MORE per body as bodies gather (%d -> %d)" % [one, four])
	_expect(int(n.call("toll_for", 0)) == 0, "an empty stance pays nothing")
	n.free()
	_completes("zanshin_gets_stronger_with_more_bodies")


## THE RULE: its damage comes from the arena, not from the spell.
func _test_teardown_prices_itself_off_the_arena() -> void:
	var n: Node2D = _cast("res://scripts/combat/Teardown.gd", "teardown", Vector2(0, -9000))
	var bare: int = int(n.call("toll_for", 0))
	var full: int = int(n.call("toll_for", 6))
	_expect(full > bare * 2, "teardown is worth far more in a room with cover (%d -> %d)"
		% [bare, full])
	_expect(bare > 0, "...and an empty room is still not literally nothing (%d)" % bare)
	# The cap is real, or a crate farm becomes the highest damage in the game.
	_expect(int(n.call("toll_for", 999)) == int(n.call("toll_for", 8)),
		"the per-piece scaling is capped")
	n.free()
	_completes("teardown_prices_itself_off_the_arena")


## THE RULE: the arena shrinks. It must NEVER widen — a wall that backed off would
## hand back ground the fight had already been priced on.
func _test_siegeworks_only_ever_closes() -> void:
	var n: Node2D = _cast("res://scripts/combat/Siegeworks.gd", "siegeworks", Vector2(0, -9000))
	var prev: float = 1e9
	var shrank: bool = false
	for i: int in 33:
		var t: float = float(i) * 0.1
		var g: float = float(n.call("half_gap_at", t))
		_expect(g <= prev + 0.001, "the gap never widens (t=%.1f: %.1f after %.1f)"
			% [t, g, prev])
		if g < prev - 0.001:
			shrank = true
		prev = g
	_expect(shrank, "...and it genuinely closes rather than holding still")
	_expect(float(n.call("half_gap_at", 99.0)) > 0.0,
		"a fully closed siege still leaves standing room — zero would grind bodies "
		+ "against each other with no legal position at all")
	n.free()
	_completes("siegeworks_only_ever_closes")


## THE RULE: no radius. A body absurdly far away must still be in the queue —
## this is the one line most likely to be "fixed" later by adding a sensible range.
func _test_the_circuit_has_no_range_limit() -> void:
	var near: Dummy = _dummy(Vector2(60.0, 0.0))
	var far: Dummy = _dummy(Vector2(4200.0, 0.0))
	var n: Node2D = _cast("res://scripts/combat/TheCircuit.gd", "the_circuit", Vector2.ZERO)
	_expect(int(n.call("link_count")) == 2,
		"the circuit queues BOTH bodies, 60 px and 4200 px away (got %d)"
		% int(n.call("link_count")))
	n.free()
	near.free()
	far.free()
	_completes("the_circuit_has_no_range_limit")


## ⚠ THE POINT OF THE WHOLE BUILD. Nine classes, nine drops, no sharing — the
## class-identity ruling forbids two classes reaching the same boss reward.
func _test_every_new_drop_is_pinned_to_exactly_one_class() -> void:
	var seen: Dictionary = {}
	for id: String in BotMatch.CLASS_DROP:
		_expect(not seen.has(id), "no class drop is shared — '%s' appears twice" % id)
		seen[id] = true
		_expect(SpellLibrary.drop_by_id(id) != null, "'%s' is a real drop" % id)
	_expect(BotMatch.CLASS_DROP.size() == 9, "all nine classes have a drop")
	for id: String in ["severance", "zanshin", "teardown", "siegeworks", "the_circuit"]:
		_expect(seen.has(id), "the new drop '%s' is actually pinned to a class" % id)
		var s: SpellDef = SpellLibrary.drop_by_id(id)
		_expect(s != null and s.kind == SpellDef.Kind.CATACLYSM, "'%s' is a CATACLYSM" % id)
		_expect(String(SpellCaster.CATACLYSM_SCRIPTS.get(id, "")) != "",
			"'%s' has a dispatch row — without one the cast spends a CHARGE and does "
			% id + "nothing at all")
	_completes("every_new_drop_is_pinned_to_exactly_one_class")
