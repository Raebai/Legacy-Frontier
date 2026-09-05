# Run: godot --headless --path godot-project --script tools/slice_test_platform_carve.gd
#
# DO THE FLOATING PLATFORMS CARVE INTO BITS — AND DOES DOING SO LEAVE THE GROUND'S
# CARVE ROUTING ALONE?
#
# Maker: *"please make the floating platforms destroyable into bits just like the floor
# was beforehand as well"*. Two halves, and the second is the dangerous one.
#
# ⚠ THE HALF THAT COULD SINK IT. `DestructibleStage.carve_area` — the route used by
# eleven spells (Blast, Fault Line, Grave Tide, Heaven's Wrath, Ice Spike, Meteor Sigil,
# Radiant Volley, Rock Pillar, Shadow Root, Shockwave Stomp, Star Convergence) — finds
# its target by scanning `GROUP_NAME` and returning THE FIRST MEMBER. That is written for
# a world with exactly one stage. Had the ledges joined that group, every carve in the
# game would have been steered onto whichever plank sorted first: a stomp at your feet
# quietly chewing a ledge across the room while the rock under the boot kept its shape.
# It is the same fault `slice_test_destructible_sources` records costing it five false
# failures from ONE stale stage; twenty ledges would be twenty of it.
#
# So test 4 is the load-bearing one: ledges must be reachable by `carve_from_body` (which
# routes by `BODY_META` on the collider that was actually hit) and INVISIBLE to the group
# scan. `slice_test_one_screen` asserts the same invariant from the other end — that a
# tower floor leaves `GROUP_NAME` empty — and it must stay green.
#
# ⚠ THE HOUSE RULE, inherited from `slice_test_destructible_carve`. Never
# `failed += _test_x()` — a dead property read aborts the enclosing function and hands
# back the type's zero, which that idiom reads as "no failures". Failures accumulate on
# the MEMBER `_fails`; every test records a COMPLETION SENTINEL as its last line, so an
# aborted test fails BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"a_breakable_ledge_loses_chunks_where_it_was_hit",
	"a_ruin_ledge_loses_chunks_too_because_most_of_the_tower_is_one",
	"a_hole_in_the_grid_is_a_hole_in_the_collision",
	"ledges_are_reachable_by_body_and_invisible_to_the_group_scan",
	"a_ledge_carved_to_a_splinter_goes_rather_than_lingering",
	"a_carved_ledge_knits_itself_back_whole",
	"the_walking_surface_never_moves_and_the_underside_never_grows_a_third_of_a_plank",
]

var _fails: int = 0
var _done: Dictionary = {}
var _room: Node2D = null


func _init() -> void:
	# ⚠ NOT IN `_init`: the tree has no root here ([[feedback_gdscript_resolution_traps]]).
	call_deferred("_run")


func _run() -> void:
	_room = Node2D.new()
	root.add_child(_room)
	for t: String in TESTS:
		call("_test_" + t)
	for t: String in TESTS:
		if not _done.has(t):
			_fail("test '%s' never reached its completion sentinel — it aborted" % t)
	if _fails == 0:
		print("PlatformCarve tests: all PASS")
	else:
		printerr("PlatformCarve tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _fail(msg: String) -> void:
	_fails += 1
	printerr("FAIL: " + msg)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


## A ledge of `cls`, parented and positioned, with one frame run so `_ready` has fired.
func _ledge(cls: GDScript, size: Vector2, at: Vector2) -> StaticBody2D:
	var n: StaticBody2D = cls.new() as StaticBody2D
	n.set(&"platform_size", size)
	_room.add_child(n)
	n.global_position = at
	return n


func _grid_of(n: StaticBody2D) -> DestructibleStage:
	return n.get_node_or_null(^"CarveGrid") as DestructibleStage


func _shape_count(body: StaticBody2D) -> int:
	var c: int = 0
	for ch: Node in body.get_children():
		if ch is CollisionShape2D:
			c += 1
	return c


# ───────────────────────────────────────────────────────────────────────────
func _test_a_breakable_ledge_loses_chunks_where_it_was_hit() -> void:
	var p: StaticBody2D = _ledge(load("res://scripts/combat/BreakablePlatform.gd"),
		Vector2(190.0, 24.0), Vector2(500.0, 300.0))
	p.set(&"max_hp", 9999)   # isolate the CARVE from the whole-slab break
	p.set(&"hp", 9999)
	var g: DestructibleStage = _grid_of(p)
	_expect(g != null, "a BreakablePlatform builds no carve grid at all")
	if g == null:
		return
	var before: int = g.solid_count()
	_expect(before > 0, "the ledge's grid was born empty (%d cells)" % before)
	# A hit at the ledge's LEFT third, in world coordinates — which is what every spell
	# call site speaks, and the conversion into the body's local grid is the thing under
	# test as much as the carve is.
	p.call(&"damage_at", 40, Vector2(440.0, 300.0), Vector2.DOWN)
	var after: int = g.solid_count()
	_expect(after < before,
		"a 40-damage hit on a ledge removed nothing (%d -> %d cells)" % [before, after])
	# ...and it came out WHERE IT WAS HIT, not at the centre. If the world->local
	# conversion were missing, a hit at world 440 would land at grid 440 — far off a grid
	# whose columns run -95..95 — and carve nothing at all, or worse, carve the wrong end.
	var cell: float = DestructibleStage.CHUNK
	var hit_col: int = int((p.to_local(Vector2(440.0, 300.0)).x - g.origin.x) / cell)
	var far_col: int = int((p.to_local(Vector2(590.0, 300.0)).x - g.origin.x) / cell)
	var hit_gone: bool = not g.is_solid(hit_col, int(g.rows / 2))
	var far_gone: bool = not g.is_solid(far_col, int(g.rows / 2))
	_expect(hit_gone, "the hole is not under the hit (col %d still solid)" % hit_col)
	_expect(not far_gone,
		"the far end of the ledge (col %d) lost rock to a hit 150 px away" % far_col)
	p.queue_free()
	_done["a_breakable_ledge_loses_chunks_where_it_was_hit"] = true


func _test_a_ruin_ledge_loses_chunks_too_because_most_of_the_tower_is_one() -> void:
	# ⚠ WHY THIS TEST EXISTS AT ALL. `FloorGen._try_add` authors `"breakable"` EXPLICITLY
	# as `rng.randf() < break_chance`, and that chance is 0.0 on floors 1-2 and caps at
	# 0.5. So `FloorBuilder`'s `p.get("breakable", true)` default almost never applies on
	# a generated floor: at least half of every floor's ledges are RuinPlatforms, and the
	# first two floors are entirely RuinPlatforms. Carving only the amber ones would ship
	# a fix invisible on the floors the maker starts on.
	var p: StaticBody2D = _ledge(load("res://scripts/combat/RuinPlatform.gd"),
		Vector2(190.0, 24.0), Vector2(900.0, 300.0))
	var g: DestructibleStage = _grid_of(p)
	_expect(g != null, "a RuinPlatform builds no carve grid at all")
	if g == null:
		return
	var before: int = g.solid_count()
	# A ruin ledge has no `damage_at` of its own ON PURPOSE — it is deliberately out of
	# the `"destructible"` group (`SpellWorld.is_smashable` would blind every floor query
	# to it). It is reached the one way that needs no group: the meta on the body a bolt
	# actually hit.
	var carved: int = DestructibleStage.carve_from_body(p, 60, Vector2(880.0, 300.0),
		Vector2.DOWN, 20.0)
	_expect(carved > 0, "carve_from_body took nothing off a RuinPlatform")
	_expect(g.solid_count() < before,
		"a RuinPlatform's grid did not shrink (%d cells both sides)" % before)
	p.queue_free()
	_done["a_ruin_ledge_loses_chunks_too_because_most_of_the_tower_is_one"] = true


func _test_a_hole_in_the_grid_is_a_hole_in_the_collision() -> void:
	# The one failure mode that matters and cannot be seen from a screenshot: solid-looking
	# rock you fall through, or a visible hole you cannot fall into. A ledge is ONE block
	# (24 px tall is 6 cells; `BLOCK_H` is 48), so the re-merge is not deferred and the
	# shapes must reflect the carve on the very next `_process`.
	var p: StaticBody2D = _ledge(load("res://scripts/combat/RuinPlatform.gd"),
		Vector2(200.0, 24.0), Vector2(1400.0, 300.0))
	var g: DestructibleStage = _grid_of(p)
	if g == null:
		_fail("no grid to test collision against")
		return
	# ⚠ MEASURED, AND IT IS NOT THE ROUND NUMBER THE FIRST GUESS GAVE. A ledge is
	# `ceil(h/CHUNK)` = 6 cells DEEP against a `BLOCK_H` of 48, so it is always exactly
	# ONE BLOCK TALL — but `BLOCK_W` is 48 cells = 192 px, and `FloorGen` ledges run
	# 100-210 px wide (`_span` can scale them further), so a wide one is TWO blocks
	# across. 1-2 blocks either way, against the ground stage's 30. That is the whole
	# rebuild-cost argument in `attach_ledge`, and it is what this pins.
	_expect(g.block_count() <= 2,
		"a 24 px ledge should be 1-2 blocks (one row of them), got %d — the rebuild"
			% g.block_count() + " cost argument in attach_ledge no longer holds")
	var one_rect: int = _shape_count(p)
	_expect(one_rect <= 2,
		"an untouched ledge should merge to 1 rectangle per block (<=2), got %d"
			% one_rect)
	# Punch clean through the middle, full depth, so the plank is cut in two.
	DestructibleStage.carve_from_body(p, 200, Vector2(1400.0, 300.0), Vector2.DOWN, 60.0)
	g._process(0.016)
	var split: int = _shape_count(p)
	_expect(split >= 2,
		"a ledge cut through the middle still has %d collision rectangle(s) — the hole"
			% split + " is in the picture and not in the physics")
	p.queue_free()
	_done["a_hole_in_the_grid_is_a_hole_in_the_collision"] = true


func _test_ledges_are_reachable_by_body_and_invisible_to_the_group_scan() -> void:
	# THE LOAD-BEARING TEST. See the header.
	var a: StaticBody2D = _ledge(load("res://scripts/combat/BreakablePlatform.gd"),
		Vector2(160.0, 24.0), Vector2(200.0, 700.0))
	var b: StaticBody2D = _ledge(load("res://scripts/combat/RuinPlatform.gd"),
		Vector2(160.0, 24.0), Vector2(600.0, 700.0))
	_expect(a.has_meta(DestructibleStage.BODY_META),
		"a BreakablePlatform carries no BODY_META — every carve_from_body site misses it")
	_expect(b.has_meta(DestructibleStage.BODY_META),
		"a RuinPlatform carries no BODY_META — every carve_from_body site misses it")
	var members: int = 0
	for n: Node in root.get_tree().get_nodes_in_group(DestructibleStage.GROUP_NAME):
		if is_instance_valid(n):
			members += 1
	_expect(members == 0,
		"%d ledge grid(s) joined %s. `stage_in` returns the FIRST member, so every"
			% [members, DestructibleStage.GROUP_NAME]
		+ " carve_area in the game (11 spells) would be steered onto one arbitrary"
		+ " plank. They must route by BODY_META only.")
	# And the corollary, stated positively: an area carve with no ground stage present
	# finds NOTHING, rather than finding a ledge.
	_expect(DestructibleStage.carve_area(_room, 200, Vector2(200.0, 700.0), Vector2.UP,
		40.0) == 0,
		"carve_area found a target with no ground stage in the world — it reached a ledge")
	# Neither may join `"destructible_stage"`; only the BREAKABLE one may be in
	# `"destructible"` (it always has been). A RuinPlatform joining it would blind
	# `SpellWorld.is_smashable`-gated floor queries to every stone ledge in the tower.
	_expect(a.is_in_group("destructible"), "a BreakablePlatform left the destructible group")
	_expect(not b.is_in_group("destructible"),
		"a RuinPlatform joined the `destructible` group — SpellWorld.is_smashable now"
		+ " returns true for it and every floor query stops seeing stone ledges")
	a.queue_free()
	b.queue_free()
	_done["ledges_are_reachable_by_body_and_invisible_to_the_group_scan"] = true


func _test_a_ledge_carved_to_a_splinter_goes_rather_than_lingering() -> void:
	# A plank chewed to a sliver you can still technically balance on is worse than a
	# clean break: it reads as broken and is not. `MIN_STANDABLE_RUN` is 24 px — the
	# 18 px body collider under the 31 px rig, plus a margin.
	var p: StaticBody2D = _ledge(load("res://scripts/combat/BreakablePlatform.gd"),
		Vector2(120.0, 24.0), Vector2(2000.0, 300.0))
	p.set(&"max_hp", 100000)   # hp must NOT be what ends it — the SHAPE must
	p.set(&"hp", 100000)
	var g: DestructibleStage = _grid_of(p)
	if g == null:
		_fail("no grid on the splinter ledge")
		return
	# ⚠ THE 24.0 IS A LITERAL AND MAY NOT BECOME `BreakablePlatform.MIN_STANDABLE_RUN`.
	# Naming the class forces COMPILE-TIME resolution of everything that file names —
	# including the `Sfx` and `Juice` AUTOLOADS, which do not exist while a `--script`
	# SceneTree suite is being compiled. The whole suite then fails to load and every
	# test in it aborts. [[feedback_gdscript_resolution_traps]]. The ledges are reached
	# by `load()` at runtime for exactly the same reason, and it is why `FloorBuilder`
	# loads both platform scripts BY PATH.
	_expect(g.widest_standable_run() > 24.0,
		"a whole 120 px ledge already reads as a splinter (%.1f px run)"
			% g.widest_standable_run())
	# Walk a heavy carve across it. `CARVE_RADIUS_MAX` is 46 px, wider than the plank is
	# tall twice over, so this is what one ult does to a ledge.
	for i: int in 8:
		if bool(p.get(&"_broken")):
			break
		p.call(&"damage_at", 300, Vector2(1945.0 + float(i) * 14.0, 300.0),
			Vector2.DOWN, 200.0, null)
	_expect(bool(p.get(&"_broken")),
		"a ledge carved down to %.1f px of standable run (%.0f%% rock left) is still"
			% [g.widest_standable_run(), g.solid_fraction() * 100.0]
		+ " standing at full hp — the splinter rule never fired")
	_expect(p.collision_layer == 0,
		"a broken ledge still has collision layer %d — it is invisible and solid"
			% p.collision_layer)
	p.queue_free()
	_done["a_ledge_carved_to_a_splinter_goes_rather_than_lingering"] = true


func _test_a_carved_ledge_knits_itself_back_whole() -> void:
	# ⚠ WHY IT MAY NOT STAY HOLED. `FloorGen` reasons about REACHABLE SURFACES when it
	# lays a floor out, so a permanently holed ledge can strand a spawn point or a pickup
	# above a gap nothing can cross — and unlike a shattered ledge, a holed one shows no
	# amber "it is coming back" outline, so the stranding would be silent.
	var p: StaticBody2D = _ledge(load("res://scripts/combat/BreakablePlatform.gd"),
		Vector2(190.0, 24.0), Vector2(2600.0, 300.0))
	p.set(&"max_hp", 9999)
	p.set(&"hp", 9999)
	p.set(&"regen_time", 0.25)
	var g: DestructibleStage = _grid_of(p)
	if g == null:
		_fail("no grid on the repair ledge")
		return
	var whole: int = g.solid_count()
	p.call(&"damage_at", 80, Vector2(2600.0, 300.0), Vector2.DOWN, 30.0, null)
	_expect(g.solid_count() < whole, "nothing was carved, so nothing can knit back")
	p._process(0.3)              # past regen_time -> the repair fires
	_expect(g.solid_count() == whole,
		"a carved ledge did not come back whole (%d of %d cells)"
			% [g.solid_count(), whole])
	g._process(0.016)
	_expect(_shape_count(p) == 1,
		"a repaired ledge is still %d collision rectangles — the old shapes were left"
			% _shape_count(p) + " parented on the body as invisible solid air")
	p.queue_free()
	_done["a_carved_ledge_knits_itself_back_whole"] = true


func _test_the_walking_surface_never_moves_and_the_underside_never_grows_a_third_of_a_plank() -> void:
	# The seam rule, applied to a thing that is 24 px tall. `SEAM_GROW_DOWN` is 8 px — a
	# THIRD of a plank of invisible solid air hanging under it, which a fighter jumping up
	# from below bonks on early. Ledges trim it. What may NEVER move, at any value, is the
	# TOP edge: that is the walking surface, and moving it moves every fighter's feet
	# ([[feedback_rig_feet_vs_collider]]).
	var size := Vector2(190.0, 24.0)
	var p: StaticBody2D = _ledge(load("res://scripts/combat/RuinPlatform.gd"),
		size, Vector2(3200.0, 300.0))
	var top: float = INF
	var bottom: float = -INF
	for ch: Node in p.get_children():
		var cs: CollisionShape2D = ch as CollisionShape2D
		if cs == null:
			continue
		var r: RectangleShape2D = cs.shape as RectangleShape2D
		if r == null:
			continue
		top = minf(top, cs.position.y - r.size.y * 0.5)
		bottom = maxf(bottom, cs.position.y + r.size.y * 0.5)
	_expect(absf(top - (-size.y * 0.5)) < 0.001,
		"the ledge's walking surface is at local y %.3f, the slab says %.3f"
			% [top, -size.y * 0.5])
	var overhang: float = bottom - size.y * 0.5
	_expect(overhang <= 4.0,
		"the collider hangs %.1f px below the drawn ledge — invisible solid air"
			% overhang)
	p.queue_free()
	_done["the_walking_surface_never_moves_and_the_underside_never_grows_a_third_of_a_plank"] = true
