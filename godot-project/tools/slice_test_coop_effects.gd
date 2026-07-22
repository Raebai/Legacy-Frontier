# Run: godot --headless --path godot-project --script tools/slice_test_coop_effects.gd
# Co-op ATTACK-VISUAL replication. The fairness property: a client must SEE the
# tell / bolt that can hit it, but the twin the host broadcasts must carry NO
# gameplay (all damage stays host-authoritative via the router). These are pure
# construction / behaviour checks — no session, no tree networking — so they run
# headlessly. Tests run on the first _process frame (not _init) because the combat
# scripts reference the Sfx/Elements autoloads, only registered after the main loop.
extends SceneTree

const NET_PATH: String = "res://scripts/Net.gd"
const PROJ_PATH: String = "res://scripts/combat/EnemyProjectile.gd"

const TICK: float = 1.0 / 60.0

var _ran: bool = false


class StubHero:
	extends Node2D

	var damage_calls: Array[int] = []

	func take_damage(amount: int) -> void:
		damage_calls.append(amount)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_visual_only_bolt_deals_no_damage()
	failed += _test_real_bolt_still_damages()
	failed += _test_visual_only_bolt_not_clearable()
	failed += _test_telegraph_twin_builds_from_data()
	failed += _test_projectile_twin_builds_visual_only()
	failed += _test_lane_telegraph_twin_is_a_line()
	if failed > 0:
		printerr("Coop-effects tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Coop-effects tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## A fresh isolated parent under root, so each test's built nodes never leak into
## the next test's child scans. Freed wholesale by _scrap().
func _scratch() -> Node2D:
	var s := Node2D.new()
	root.add_child(s)
	return s


func _scrap(s: Node) -> void:
	root.remove_child(s)
	s.free()  # immediate — frees children too, cancelling any queued self-free


func _first_telegraph(parent: Node) -> Telegraph:
	for c: Node in parent.get_children():
		if c is Telegraph:
			return c as Telegraph
	return null


func _first_bolt(parent: Node) -> Node:
	for c: Node in parent.get_children():
		if c.has_method("launch") and c.has_method("_check_hit"):
			return c
	return null


## A hero standing right on a VISUAL-ONLY bolt takes NO damage: _physics_process
## skips the whole clash/hit path for a twin (the host's real bolt owns damage).
func _test_visual_only_bolt_deals_no_damage() -> int:
	var f: int = 0
	var s: Node2D = _scratch()
	var hero := StubHero.new()
	hero.add_to_group("hero")
	s.add_child(hero)
	hero.global_position = Vector2.ZERO  # dead-centre inside HIT_RADIUS
	var proj: Node2D = load(PROJ_PATH).new()
	proj.set("visual_only", true)
	s.add_child(proj)
	proj.global_position = Vector2.ZERO
	proj.launch(Vector2.RIGHT)
	proj._physics_process(TICK)
	f += _expect(hero.damage_calls.is_empty(), "visual_only bolt over a hero deals no damage")
	_scrap(s)
	return f


## The control: a NORMAL (non-twin) bolt on a hero deals its DAMAGE once — proving
## the guard is what suppresses damage, not a broken hit path.
func _test_real_bolt_still_damages() -> int:
	var f: int = 0
	var s: Node2D = _scratch()
	var hero := StubHero.new()
	hero.add_to_group("hero")
	s.add_child(hero)
	hero.global_position = Vector2.ZERO
	var proj: Node2D = load(PROJ_PATH).new()
	s.add_child(proj)
	proj.global_position = Vector2.ZERO
	proj.launch(Vector2.RIGHT)
	var dmg: int = int((load(PROJ_PATH) as GDScript).get_script_constant_map().get("DAMAGE", 0))
	proj._physics_process(TICK)
	f += _expect(hero.damage_calls == [dmg], "real bolt on a hero deals DAMAGE once")
	_scrap(s)
	return f


## A twin must NOT join "enemy_projectile" (else a client's own AoE could consume it,
## diverging its lifetime from the host bolt it mirrors). A real bolt joins as before.
func _test_visual_only_bolt_not_clearable() -> int:
	var f: int = 0
	var s: Node2D = _scratch()
	var twin: Node2D = load(PROJ_PATH).new()
	twin.set("visual_only", true)
	s.add_child(twin)   # _ready runs here
	f += _expect(not twin.is_in_group("enemy_projectile"), "visual_only twin is not clearable")
	var real: Node2D = load(PROJ_PATH).new()
	s.add_child(real)
	f += _expect(real.is_in_group("enemy_projectile"), "real bolt joins enemy_projectile")
	_scrap(s)
	return f


## Net._spawn_telegraph_twin builds a source-less Telegraph at the marked spot with
## the broadcast style/geometry — the client's damage-free copy of a host tell.
func _test_telegraph_twin_builds_from_data() -> int:
	var f: int = 0
	var s: Node2D = _scratch()
	var net: Node = load(NET_PATH).new()
	root.add_child(net)
	net._spawn_telegraph_twin(s, {
		"style": Telegraph.Style.ZONE, "pos": Vector2(120, 40),
		"radius": 70.0, "windup": 0.85,
	})
	var tele: Telegraph = _first_telegraph(s)
	f += _expect(tele != null, "telegraph twin is built into the scene")
	if tele != null:
		f += _expect(tele.global_position == Vector2(120, 40), "twin sits at the marked spot")
		f += _expect(tele.source == null, "twin is source-less (no host-enemy reference)")
		# It animates + frees itself: past windup + fade it queue_frees.
		tele.advance(0.85 + Telegraph.FADE_TIME + 0.02)
		f += _expect(tele.is_queued_for_deletion(), "twin fades + frees itself")
	root.remove_child(net); net.free()
	_scrap(s)
	return f


## Net._spawn_projectile_twin builds a visual_only bolt — flagged so it never damages.
func _test_projectile_twin_builds_visual_only() -> int:
	var f: int = 0
	var s: Node2D = _scratch()
	var net: Node = load(NET_PATH).new()
	root.add_child(net)
	net._spawn_projectile_twin(s, {"pos": Vector2(10, 10), "dir": Vector2.LEFT, "element": 0})
	var proj: Node = _first_bolt(s)
	f += _expect(proj != null, "projectile twin is built into the scene")
	if proj != null:
		f += _expect(bool(proj.get("visual_only")), "twin is flagged visual_only")
		f += _expect(not proj.is_in_group("enemy_projectile"), "twin is not clearable")
	root.remove_child(net); net.free()
	_scrap(s)
	return f


## A LANE (charger) tell round-trips through the data dict as a LINE-shaped twin.
func _test_lane_telegraph_twin_is_a_line() -> int:
	var f: int = 0
	var s: Node2D = _scratch()
	var net: Node = load(NET_PATH).new()
	root.add_child(net)
	net._spawn_telegraph_twin(s, {
		"style": Telegraph.Style.LANE, "pos": Vector2.ZERO, "line": true,
		"length": 300.0, "width": 34.0, "angle": 0.0, "windup": 0.7,
	})
	var tele: Telegraph = _first_telegraph(s)
	f += _expect(tele != null, "lane twin is built")
	if tele != null:
		f += _expect(tele.get("_shape") == Telegraph.Shape.LINE, "lane twin is a LINE shape")
	root.remove_child(net); net.free()
	_scrap(s)
	return f
