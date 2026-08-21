# Run: Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice9_test_swordsaint.gd
# THE SWORDSAINT + THE SIGNATURE RITE.
#
# Four things are under test, and each one is a thing that has already gone wrong
# somewhere in this codebase:
#
#   1. THE ROSTER. A ninth class exists and every count is derived from the real
#      list rather than a hardcoded 8 (which is exactly what went stale in
#      slice5_test_classes and in Lobby.gd's `% 8`).
#   2. THE BLADE GUARD. Only a PERFECT read banks; a sustained one chips and earns
#      nothing; the bank pays out as a directed line, not an omni-burst; and eight
#      shipped classes are provably untouched by any of it.
#   3. THE RITE ADDS NO TIME, and its three suppression rules actually suppress.
#   4. HORIZON CUT'S HIT SHAPE IS ITS DRAWN SHAPE — including the negative cases,
#      because five drawn-vs-damaged mismatches were found in one night and the
#      only reason to trust a sixth is a test that would catch it.
#
# ⚠ WHY THE HARNESS IS SHAPED LIKE THIS (copied from tools/slice_test_loadout.gd):
# reading a member that no longer exists is NOT a failure in GDScript. It logs a
# runtime error, ABORTS the enclosing function, and hands the caller the return
# type's zero value — which under a `failed += _test_thing()` idiom reads as "zero
# failures". So failures accumulate on the MEMBER `_fails`, and every test's last
# line records that it reached the end. A test that dies half-way fails the suite
# by ABSENCE, whatever killed it.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
## load()ed by path, never by class_name: a compile-time reference to a script that
## touches autoloads is the repo's oldest test trap.
const ARC_PATH: String = "res://scripts/combat/HorizonArc.gd"

## Hero members this suite reaches DYNAMICALLY (Hero.gd has no class_name, so every
## `hero._guard` is a runtime lookup). Named once so a relocation is diagnosed
## rather than merely detected.
const HERO_MEMBERS: Array[String] = [
	"_guard", "_guard_bank", "_guard_hits", "_last_declared",
	"_melee_range", "_melee_arc_dot", "_aim_dir", "facing",
]

const TESTS: Array[String] = [
	"roster_is_derived", "swordsaint_config", "blade_guard_is_the_ring",
	"guard_banks_only_perfect", "unsheathe_pays_the_bank",
	"rite_adds_no_time", "rite_suppression_rules",
	"arc_drawn_equals_damaged", "arc_polygon_matches_hitbox",
	"arc_reflect_severs_ownership", "arc_shape_is_not_the_arena_origin",
	"melee_measures_the_silhouette", "swordsaint_kit", "cards_do_not_lie",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


## A target with a DRAWN BODY: a spine from the origin up to a head, plus a small
## head circle. This is the shape `SpellTargets` duck-types against, and the whole
## point of the melee test — its silhouette reaches places its origin does not.
class RigStub:
	extends Node2D
	var hp: int = 100
	var hits: Array[int] = []
	var head_offset: float = -20.0
	var head_radius: float = 4.0
	var margin: float = 3.7

	func body_distance(p: Vector2) -> float:
		return SpellGeometry.point_segment_distance(p, global_position, head_point()) - head_radius

	func head_point() -> Vector2:
		return global_position + Vector2(0.0, head_offset)

	func hit_margin() -> float:
		return margin

	func take_damage(amount: int, _tint: Color = Color.WHITE) -> void:
		hits.append(amount)
		hp -= amount

	func apply_knockback(_v: Vector2, _flop: bool = true) -> void:
		pass

	func apply_status(_e: int) -> void:
		pass


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_roster_is_derived()
	_test_swordsaint_config()
	_test_blade_guard_is_the_ring()
	_test_guard_banks_only_perfect()
	_test_unsheathe_pays_the_bank()
	_test_rite_adds_no_time()
	_test_rite_suppression_rules()
	_test_arc_drawn_equals_damaged()
	_test_arc_polygon_matches_hitbox()
	_test_arc_reflect_severs_ownership()
	_test_arc_shape_is_not_the_arena_origin()
	_test_melee_measures_the_silhouette()
	_test_swordsaint_kit()
	_test_cards_do_not_lie()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Swordsaint tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Swordsaint tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER, never a return value — a failure recorded before an
## abort survives the abort instead of being discarded with the function's result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _require_props(obj: Object, names: Array[String], owner_label: String) -> void:
	if obj == null:
		_expect(false, "%s exists (cannot check its members)" % owner_label)
		return
	var present: Dictionary = {}
	for p: Dictionary in obj.get_property_list():
		present[String(p["name"])] = true
	for n: String in names:
		_expect(present.has(n),
			"%s still declares `%s` (moved or renamed — assertions reading it are dead)"
				% [owner_label, n])


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	return hero


# ------------------------------------------------------------------ the roster

## Every count comes from the REAL list. A hardcoded 8 here would be the same bug
## that made the ninth class silently unselectable in the co-op lobby.
func _test_roster_is_derived() -> void:
	var hero: CharacterBody2D = _make_hero()
	var names: Array = hero.CLASS_NAMES
	var enum_size: int = int(hero.HeroClass.size())
	_expect(names.size() == enum_size,
		"CLASS_NAMES (%d) and HeroClass (%d) agree" % [names.size(), enum_size])
	_expect(ClassInfo.count() == enum_size,
		"ClassInfo has a card per class (%d vs %d)" % [ClassInfo.count(), enum_size])
	_expect(int(hero.CLASS_CONFIG.size()) == enum_size,
		"CLASS_CONFIG has a row per class")
	# Every class must still configure without error and report its own name.
	for cls: int in range(enum_size):
		hero.configure_class(cls)
		_expect(int(hero._hero_class) == cls, "class %d configured" % cls)
		_expect(hero.class_display_name() == String(names[cls]),
			"class %d reports %s" % [cls, names[cls]])
		_expect(ClassInfo.name_for(cls) == String(names[cls]),
			"class card %d names the same class as the hero does" % cls)
	hero.queue_free()
	_completes("roster_is_derived")


## The class's identity, as data. Each of these is a design decision that would be
## invisible if it silently reverted.
func _test_swordsaint_config() -> void:
	var hero: CharacterBody2D = _make_hero()
	var idx: int = int(hero.HeroClass.SWORDSAINT)
	var cfg: Dictionary = hero.CLASS_CONFIG[idx]
	_expect(String(cfg.get("defense", "")) == "held_guard",
		"the Swordsaint's defence is the held guard, not a press-window parry")
	_expect(int(cfg.get("melee_element", 0)) == -1,
		"PLAIN STEEL: the blade applies no ailment (a burn would make it the fire melee class)")
	_expect(String(cfg.get("mobility2", "")) == "uppercut",
		"no blink — R is a rising cut, the same trade Juggernaut makes")
	_expect(not bool(cfg.get("has_nova", true)), "no nova — it has no panic button")
	_expect(float(cfg.get("melee_range", 0.0)) > 58.0,
		"a greatsword outreaches fists")
	hero.queue_free()
	_completes("swordsaint_config")


# ------------------------------------------------------------- the blade guard

## The ring exists for the Swordsaint and for NOBODY ELSE. This is what keeps the
## eight shipped classes on the defensive feel they were balanced against.
func _test_blade_guard_is_the_ring() -> void:
	var hero: CharacterBody2D = _make_hero()
	_require_props(hero, HERO_MEMBERS, "Hero")
	hero.configure_class(hero.HeroClass.SWORDSAINT)
	var ring: ParryRing = hero._guard as ParryRing
	_expect(ring != null, "the Swordsaint gets a ParryRing")
	if ring != null:
		_expect(ring.style == ParryRing.Style.BLADE,
			"...in the BLADE style (a blade bottoms out; only a sigil collapses)")
		_expect(ring.has_sustain(), "BLADE keeps its safe fallback")
	for cls: int in range(int(hero.HeroClass.size())):
		if cls == int(hero.HeroClass.SWORDSAINT):
			continue
		hero.configure_class(cls)
		_expect(hero._guard == null,
			"class %d keeps its press-window parry — the ring is not retrofitted" % cls)
	# ...and a swap can never leave a ring half-held, which would lock the next
	# class out of attacking entirely.
	hero.configure_class(hero.HeroClass.SWORDSAINT)
	var _p: bool = (hero._guard as ParryRing).press()
	hero.configure_class(hero.HeroClass.SWORDSAINT)
	_expect(not (hero._guard as ParryRing).held,
		"re-configuring rebuilds the ring rather than inheriting a held one")
	hero.queue_free()
	_completes("blade_guard_is_the_ring")


## ONLY A PERFECT READ BANKS. A sustained guard survives; it does not earn — or
## holding the button would be both the safe option and the strong one.
func _test_guard_banks_only_perfect() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.SWORDSAINT)
	var ring: ParryRing = hero._guard as ParryRing
	if ring == null:
		_expect(false, "no ring to drive")
		_completes("guard_banks_only_perfect")
		hero.queue_free()
		return
	# PERFECT: close the ring into its band, then eat a hit.
	var _p1: bool = ring.press()
	ring.tick(ParryRing.SHRINK_TIME * 0.9)
	_expect(ring.quality() == ParryRing.Quality.PERFECT, "the ring is in its perfect band")
	var hp_before: int = int(hero.hp)
	hero.take_damage(40)
	_expect(int(hero.hp) == hp_before, "a perfect read takes NO damage")
	_expect(int(hero._guard_bank) == 40, "...and banks the whole hit")
	_expect(int(hero._guard_hits) == 1, "...and counts toward the auto-cash limit")
	# The bank is CAPPED, so one blocked boss slam cannot load a bigger hit than any
	# ult in the game.
	hero.take_damage(200)
	_expect(int(hero._guard_bank) == hero.GUARD_BANK_CAP,
		"the bank is capped at %d" % int(hero.GUARD_BANK_CAP))
	# SUSTAIN: overshoot the band. Steel is still in the way, so it chips — but it
	# earns nothing.
	ring.release()
	ring.tick(ParryRing.REARM_TIME + 0.01)
	var _p2: bool = ring.press()
	ring.tick(ParryRing.SHRINK_TIME + 0.05)
	_expect(ring.quality() == ParryRing.Quality.SUSTAIN, "overshooting bottoms out into a sustain")
	hero.set("_guard_bank", 0)
	hp_before = int(hero.hp)
	hero.take_damage(40)
	_expect(int(hero.hp) < hp_before, "a sustained guard still takes damage")
	_expect(hp_before - int(hero.hp) < 40, "...but less than the full hit")
	_expect(int(hero._guard_bank) == 0, "a sustained guard banks NOTHING")
	hero.queue_free()
	_completes("guard_banks_only_perfect")


## The payment is a DIRECTED LINE. An omni-burst would make the guard a panic
## button that punishes whoever happened to be nearby; a line means you must still
## be pointed at the thing you blocked.
func _test_unsheathe_pays_the_bank() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.SWORDSAINT)
	hero.global_position = Vector2.ZERO
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.set("facing", Vector2.RIGHT)
	var front := RigStub.new()
	front.add_to_group("enemy")
	front.add_to_group(SpellCaster.MORTAL_GROUP)  # see the note in slice1_test_nova.gd
	front.global_position = Vector2(70.0, 0.0)
	root.add_child(front)
	var behind := RigStub.new()
	behind.add_to_group("enemy")
	behind.add_to_group(SpellCaster.MORTAL_GROUP)  # see the note in slice1_test_nova.gd
	behind.global_position = Vector2(-70.0, 0.0)
	root.add_child(behind)
	hero.call("_unsheathe_cut", 60)
	# ⚠ + `_melee_damage`. The draw's PUNCH animation used to land a free undeclared
	# melee hit on top of the cut (measured [72, 37]); that coupling is gone and the
	# value is folded into the cut explicitly, so the move deals what it always did.
	var expected: int = int(round(60.0 * float(hero.GUARD_RETURN_MULT))) 		+ int(hero.get("_melee_damage"))
	_expect(front.hits.size() == 1, "the cut lands on what you are pointed at")
	if front.hits.size() == 1:
		_expect(front.hits[0] == expected,
			"the bank pays %d (60 x %.1f), got %d" % [expected, float(hero.GUARD_RETURN_MULT), front.hits[0]])
	_expect(behind.hits.is_empty(), "the cut is a LINE — it does not punish behind you")
	front.queue_free()
	behind.queue_free()
	hero.queue_free()
	_completes("unsheathe_pays_the_bank")


# --------------------------------------------------------------- the rite

## THE RITE ADDS NO TIME. This is the one property that makes the ceremony free,
## and the one that would be quietly lost by "just a little longer on the card".
func _test_rite_adds_no_time() -> void:
	for windup: float in [0.22, 0.42, 1.0, 1.25, 1.9, 2.6]:
		var d: float = SignatureRite.declare_time(windup)
		var c: float = SignatureRite.charge_time(windup)
		var r: float = SignatureRite.release_time(windup)
		_expect(is_equal_approx(d + c + r, windup),
			"the three beats sum to the windup at %.2f s (got %.4f)" % [windup, d + c + r])
		_expect(d <= SignatureRite.DECLARE_MAX + 0.0001,
			"declare is capped at %.2f s even at a %.2f s windup" % [SignatureRite.DECLARE_MAX, windup])
		_expect(is_equal_approx(SignatureRite.dodge_window(windup), c),
			"the CHARGE is the published dodge window at %.2f s" % windup)
	# The beats are in order and cover the whole windup.
	_expect(SignatureRite.beat_at(1.0, 0.05) == SignatureRite.Beat.DECLARE, "0.05s into a 1.0s cast is DECLARE")
	_expect(SignatureRite.beat_at(1.0, 0.5) == SignatureRite.Beat.CHARGE, "0.50s in is CHARGE")
	_expect(SignatureRite.beat_at(1.0, 0.97) == SignatureRite.Beat.RELEASE, "0.97s in is RELEASE")
	# A longer cast must buy a longer dodge window, never a shorter one — this is
	# the locked rule the whole ladder exists to express.
	var prev: float = -1.0
	for w: float in [0.42, 1.0, 1.25, 1.9, 2.6]:
		var dw: float = SignatureRite.dodge_window(w)
		_expect(dw > prev, "a %.2f s cast buys a longer dodge window than the one below it" % w)
		prev = dw
	_completes("rite_adds_no_time")


## All three suppression rules, as pure predicates. Declare fatigue is the number
## one risk to the whole idea, and these are the only thing standing against it.
func _test_rite_suppression_rules() -> void:
	var seen: Dictionary = {}
	# Baseline: a fresh heavy signature announces.
	_expect(SignatureRite.should_declare(SpellTier.Tier.ULT, "horizon_cut", seen, 100.0, false),
		"a fresh ult declares")
	# 1. ⚠ A QUICK CAST NOW DECLARES, and this assertion was inverted on purpose.
	# It used to read "a QUICK signature never declares", on the reasoning that a name
	# card on a blink is a name card nobody reads. That was true of the only
	# presentation that existed — a full-width card. The maker asked for the other one:
	# *"all of these spells need titles ... showing next to the character or in big
	# depending on the spell ... otherwise its confusing for the players"*. A small name
	# above the caster costs nothing to ignore, and a cast that arrives unlabelled is
	# the confusion being reported. The suppression rules below still guard the BIG
	# card, which is the one that can genuinely collide.
	_expect(SignatureRite.should_declare(SpellTier.Tier.QUICK, "blink_strike", seen, 100.0, false),
		"a QUICK signature declares too, with the small presentation")
	# ...and the loud one is still refused to a quick cast even while a card is live,
	# because the rules that follow only govern the ULT shelf.
	_expect(SignatureRite.should_declare(SpellTier.Tier.QUICK, "blink_strike", seen, 100.0, true),
		"a QUICK signature is not silenced by another fighter's card")
	# 2. never a repeat inside the window.
	seen["horizon_cut"] = 100.0
	_expect(not SignatureRite.should_declare(SpellTier.Tier.ULT, "horizon_cut", seen,
			100.0 + SignatureRite.REPEAT_WINDOW - 0.5, false),
		"the same signature does not re-introduce itself inside the repeat window")
	_expect(SignatureRite.should_declare(SpellTier.Tier.ULT, "horizon_cut", seen,
			100.0 + SignatureRite.REPEAT_WINDOW + 0.5, false),
		"...and does declare again once the window has passed")
	_expect(SignatureRite.should_declare(SpellTier.Tier.ULT, "meteor_sigil", seen, 100.5, false),
		"a DIFFERENT signature is unaffected by another's repeat clock")
	# 3. never while another card is up (co-op: two heroes ulting on one frame).
	_expect(not SignatureRite.should_declare(SpellTier.Tier.ULT, "meteor_sigil", seen, 100.5, true),
		"a second card never stacks over a live one")
	_completes("rite_suppression_rules")


# ------------------------------------------------------------ the horizon cut

## DRAWN == DAMAGED, including the cases that would be a lie. Every constant below
## is chosen so a failure names the exact edge that moved.
func _test_arc_drawn_equals_damaged() -> void:
	var o := Vector2.ZERO
	var dir := Vector2.RIGHT
	var travelled: float = 400.0
	var hh: float = 200.0
	var bow: float = HorizonArc.BOW
	var thick: float = 30.0
	# The centre of the crescent TRAILS the tips by `bow` — that is what makes the
	# hollow face forward, and it is the first thing a "simplification" would flatten.
	var centre: Vector2 = HorizonArc.arc_point(o, dir, travelled, hh, bow, 0.0)
	var tip: Vector2 = HorizonArc.arc_point(o, dir, travelled, hh, bow, 1.0)
	_expect(is_equal_approx(centre.x, travelled - bow), "the centre trails by the bow")
	_expect(is_equal_approx(tip.x, travelled), "the tips lead")
	_expect(is_equal_approx(tip.y, hh), "the tip sits exactly at the half-height")
	# INSIDE.
	_expect(HorizonArc.contains_point(o, dir, travelled, hh, bow, thick, centre),
		"the drawn centre is damaged")
	_expect(HorizonArc.contains_point(o, dir, travelled, hh, bow, thick, tip),
		"the drawn tip is damaged")
	_expect(HorizonArc.contains_point(o, dir, travelled, hh, bow, thick,
			centre + Vector2(thick * 0.5 - 0.5, 0.0)),
		"just inside the leading face is damaged")
	# OUTSIDE — the negative cases. These are the ones that catch a spell damaging
	# wider than it draws.
	_expect(not HorizonArc.contains_point(o, dir, travelled, hh, bow, thick,
			centre + Vector2(thick * 0.5 + 1.0, 0.0)),
		"one pixel past the leading face is NOT damaged")
	_expect(not HorizonArc.contains_point(o, dir, travelled, hh, bow, thick,
			centre - Vector2(thick * 0.5 + 1.0, 0.0)),
		"one pixel behind the trailing face is NOT damaged")
	_expect(not HorizonArc.contains_point(o, dir, travelled, hh, bow, thick,
			Vector2(travelled, hh + 1.0)),
		"ONE PIXEL OUTSIDE THE HEIGHT BAND IS NOT DAMAGED — the band IS the spell")
	_expect(not HorizonArc.contains_point(o, dir, travelled, hh, bow, thick,
			Vector2(travelled, -hh - 1.0)),
		"...symmetrically, above the band")
	# A body standing where the wall ALREADY WAS is not still being cut.
	_expect(not HorizonArc.contains_point(o, dir, travelled, hh, bow, thick, Vector2(100.0, 0.0)),
		"the wall damages where it IS, not where it has been")
	# The band is a real height choice: the same target is hit or missed purely by
	# where the caster aimed, which is audit gap C.3 in one assertion.
	var grounded := Vector2(360.0, 0.0)
	_expect(HorizonArc.contains_point(o, dir, travelled, hh, bow, thick, grounded),
		"aimed level, a grounded body is cut")
	_expect(not HorizonArc.contains_point(o + Vector2(0.0, -400.0), dir, travelled, hh, bow,
			thick, grounded),
		"AIMED HIGH, the same grounded body passes under the cut")
	# The widening is monotonic and hits its authored endpoints.
	_expect(is_equal_approx(HorizonArc.half_height_at(0.0, 90.0, 300.0), 90.0),
		"the cut launches at its start half-height")
	_expect(is_equal_approx(HorizonArc.half_height_at(1.0, 90.0, 300.0), 300.0),
		"...and reaches its end half-height")
	_completes("arc_drawn_equals_damaged")


## The POLYGON the spell draws and the SHAPE it damages are generated by the same
## function, so this asserts they still are — measured off the real node, not a
## reimplementation of it.
func _test_arc_polygon_matches_hitbox() -> void:
	var arc: Node2D = (load(ARC_PATH) as GDScript).new()
	root.add_child(arc)
	arc.call("sweep", Vector2.ZERO, Vector2.RIGHT, Color.WHITE, 900.0, 30.0, 200.0, 200.0, 110)
	arc.set("_travelled", 400.0)
	var poly: PackedVector2Array = arc.call("_band_polygon", 1.0)
	_expect(poly.size() > 4, "the drawn band is a real polygon")
	var max_y: float = -INF
	var max_x: float = -INF
	var min_x: float = INF
	for p: Vector2 in poly:
		max_y = maxf(max_y, p.y)
		max_x = maxf(max_x, p.x)
		min_x = minf(min_x, p.x)
	# The drawn extremes must be exactly the damaged extremes.
	_expect(is_equal_approx(max_y, 200.0),
		"the drawn band reaches exactly the half-height it damages (got %.2f)" % max_y)
	_expect(is_equal_approx(max_x, 400.0 + 15.0),
		"the drawn leading face is exactly half the thickness ahead of the tips (got %.2f)" % max_x)
	_expect(is_equal_approx(min_x, 400.0 - HorizonArc.BOW - 15.0),
		"the drawn trailing face is exactly half the thickness behind the centre (got %.2f)" % min_x)
	# ...and a point just outside the DRAWN polygon is not damaged.
	_expect(not HorizonArc.contains_point(Vector2.ZERO, Vector2.RIGHT, 400.0, 200.0,
			HorizonArc.BOW, 30.0, Vector2(max_x + 1.0, 0.0)),
		"one pixel past the drawn leading face is not damaged")
	arc.queue_free()
	_completes("arc_polygon_matches_hitbox")


## A deflected cut turns around AND LOSES ITS OWNER. Severing ownership is the
## point: an unowned effect matches no same-owner/different-owner clash row, which
## is the honest report for a spell nobody is casting any more.
func _test_arc_reflect_severs_ownership() -> void:
	var owner_stub := Node2D.new()
	root.add_child(owner_stub)
	var arc: Node2D = (load(ARC_PATH) as GDScript).new()
	root.add_child(arc)
	arc.set("caster_node", owner_stub)
	arc.call("sweep", Vector2.ZERO, Vector2.RIGHT, Color.WHITE, 900.0, 30.0, 90.0, 300.0, 110)
	_expect(arc.is_in_group("deflectable_spell"),
		"the cut joins the group the guard scans — nothing is unparryable")
	_expect(String(arc.get("_target_group")) == "enemy", "it starts out hostile to enemies")
	arc.call("reflect", Vector2.LEFT, Color.RED)
	_expect(bool(arc.get("_reflected")), "it records that it was turned")
	_expect(arc.get("caster_node") == null,
		"OWNERSHIP IS SEVERED — a turned spell is nobody's")
	_expect(String(arc.get("_target_group")) == "hero",
		"...and it now cuts whoever threw it")
	# One deflect only: a second reflect must not reset its travel budget again.
	arc.set("_travelled", 300.0)
	arc.call("reflect", Vector2.RIGHT, Color.BLUE)
	_expect(is_equal_approx(float(arc.get("_travelled")), 300.0),
		"a second deflect is refused — one turn per cut")
	arc.queue_free()
	owner_stub.queue_free()
	_completes("arc_reflect_severs_ownership")


## THE REACTOR'S OWN NEGATIVE CASE, applied to this spell. Spectacles park at the
## arena origin and draw in world coordinates, so a reaction shape built from
## `global_position` would report every pair as touching at the top-left of the
## arena — a bug that fails LOUD in the wrong direction.
func _test_arc_shape_is_not_the_arena_origin() -> void:
	var arc: Node2D = (load(ARC_PATH) as GDScript).new()
	root.add_child(arc)
	arc.call("sweep", Vector2(2000.0, 500.0), Vector2.RIGHT, Color.WHITE, 900.0, 30.0, 90.0, 300.0, 110)
	arc.set("_travelled", 250.0)
	_expect(arc.global_position.is_equal_approx(Vector2.ZERO),
		"the node itself parks at the arena origin (the trap this guards)")
	var shape: Dictionary = arc.call("reaction_shape")
	var probe: Vector2 = HorizonArc.arc_point(Vector2(2000.0, 500.0), Vector2.RIGHT,
		250.0, arc.call("_half_height"), HorizonArc.BOW, 0.0)
	_expect(probe.distance_to(Vector2.ZERO) > 1000.0, "the effect is nowhere near the origin")
	_expect(not SpellGeometry.contains_point(shape, Vector2.ZERO),
		"the reaction shape does NOT sit at the arena origin")
	_expect(SpellGeometry.contains_point(shape, arc.call("centre")),
		"...it sits where the cut actually is (the crescent's trailing middle)")
	var hh_now: float = arc.call("_half_height")
	_expect(SpellGeometry.contains_point(shape,
			HorizonArc.arc_point(Vector2(2000.0, 500.0), Vector2.RIGHT, 250.0, hh_now,
				HorizonArc.BOW, 1.0)),
		"...and covers the leading tips too — a capsule that missed either end would "
		+ "let two spells visibly cross with no reaction")
	_expect(int(arc.call("reaction_form")) == int(ReactionTable.Form.PROJECTILE),
		"a travelling, reflectable body reacts as a PROJECTILE")
	_expect(arc.call("reaction_active"), "an in-flight cut is an active reactant")
	arc.call("_begin_dissipate")
	_expect(not arc.call("reaction_active"),
		"a spent cut stops reacting — it cannot annihilate something on its way out")
	arc.queue_free()
	_completes("arc_shape_is_not_the_arena_origin")


# ---------------------------------------------------------- the head hitbox

## THE BUG THE MAKER REPORTED: "spells pass through heads without registering."
## A rig's node origin sits ~10 px below its drawn head, so a melee arc that tested
## `distance_to(enemy.global_position)` measured to a point the player was not
## aiming at. `far` below is positioned so its ORIGIN is out of melee range while
## its DRAWN BODY is not — under the old point test it was untouchable.
##
## `near` exists so the assertion cannot be satisfied by the nearest-enemy
## auto-target: with a closer enemy present, `far` can only be reached by the cone.
func _test_melee_measures_the_silhouette() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.MAGE)  # fists: MELEE_RANGE 58, arc dot 0.3
	hero.global_position = Vector2.ZERO
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.set("facing", Vector2.RIGHT)
	var reach: float = float(hero._melee_range)
	var near := RigStub.new()
	near.add_to_group("enemy")
	near.add_to_group(SpellCaster.MORTAL_GROUP)  # see the note in slice1_test_nova.gd
	near.global_position = Vector2(30.0, 0.0)
	root.add_child(near)
	var far := RigStub.new()
	far.add_to_group("enemy")
	far.add_to_group(SpellCaster.MORTAL_GROUP)  # see the note in slice1_test_nova.gd
	far.global_position = Vector2(56.0, 30.0)   # origin 63.5 px away — outside `reach`
	root.add_child(far)
	_expect(hero.global_position.distance_to(far.global_position) > reach,
		"the far stub's ORIGIN really is out of melee range (the old test would miss it)")
	_expect(SpellTargets.body_distance(far, hero.global_position) <= reach,
		"...while its DRAWN BODY reaches inside — this is the whole bug")
	# ⚠ DECLARE THE SWING. `_on_melee_hit_frame` now refuses to land unless one was
	# actually declared — the rig fires `hit_frame` for ANY punch or kick, and four
	# abilities played one without meaning to swing. Driving the handler directly is a
	# harness shortcut, so the harness opens the window the real path opens.
	hero.set("_swing_window", hero.SWING_WINDOW)
	hero.call("_on_melee_hit_frame")
	_expect(not near.hits.is_empty(), "the swing lands on the near enemy")
	_expect(not far.hits.is_empty(),
		"THE SWING REGISTERS ON A HEAD WHOSE ORIGIN IS OUT OF RANGE")
	# ...and nothing behind you is swept in, so the arc predicate is still honest.
	var back := RigStub.new()
	back.add_to_group("enemy")
	back.add_to_group(SpellCaster.MORTAL_GROUP)  # see the note in slice1_test_nova.gd
	back.global_position = Vector2(-400.0, 0.0)
	root.add_child(back)
	near.hits.clear()
	far.hits.clear()
	hero.call("_on_melee_hit_frame")
	_expect(back.hits.is_empty(), "a body 400 px behind you is still not hit")
	near.queue_free()
	far.queue_free()
	back.queue_free()
	hero.queue_free()
	_completes("melee_measures_the_silhouette")


# --------------------------------------------------------------------- the kit

## The class holds an AUTHORED kit, not the review-harness fallback, and its damage
## line is the blade. `slice8_test_spell_kits` already checks the generic 4+1 shape
## for every class; this checks the INTENT, which is the part a reshuffle silently
## loses.
func _test_swordsaint_kit() -> void:
	var idx: int = 8  # Hero.HeroClass.SWORDSAINT
	var kit: Dictionary = SpellLibrary.kit_for_class(idx)
	_expect(not kit.is_empty(),
		"the Swordsaint has an authored kit (an empty one falls back to the review "
		+ "cycle, which is 6 spells and fails the 4+1 slot rule)")
	if kit.is_empty():
		_completes("swordsaint_kit")
		return
	var loadout: Array = SpellLibrary.build_for_class(idx)
	# THREE, not five: the right thumb has three buttons. The two roles this class
	# authors but does not carry are its share of the Tier 2 / Tier 3 drop pool.
	_expect(loadout.size() == SpellTier.SLOT_COUNT,
		"the hand is %d spells (got %d)" % [SpellTier.SLOT_COUNT, loadout.size()])
	if loadout.size() != SpellTier.SLOT_COUNT:
		_completes("swordsaint_kit")
		return
	# THE DAMAGE LINE IS THE BLADE, and it is now the duelist's OWN blade. It used to
	# be `blade_flurry`, which is the SHADOWBLADE's spell: two classes throwing one
	# `BladeFlurry.gd`, i.e. exactly the recolour the anti-recolour pass deleted. IAI
	# SLASH is the punish half of "guard and punish" — one committed draw-cut at 118 px
	# with a five-second wait if it whiffs, which is the counterplay rather than a
	# balance rounding.
	_expect(String(loadout[0].id) == "iai_slash",
		"the damage line is the BLADE — a class whose damage is the path of the "
		+ "weapon must not open on a bolt")
	_expect(int(loadout[0].kind) == int(SpellDef.Kind.HEX),
		"the Iai Slash is an id-forked HEX, not a corridor spell")
	# ...and the cut is SHORT. The whole reason this is not just another beam: a
	# reach anywhere near a beam's would delete the "get into range" problem the
	# class's entire kit exists to solve.
	_expect(loadout[0].reach < 200.0,
		"the draw-cut reaches %.0f px — a body and a half, not a lance" % loadout[0].reach)
	# Only the LAST slot may hold an ult.
	for i: int in SpellTier.SLOT_COUNT:
		var is_ult: bool = SpellTier.of(loadout[i]) == SpellTier.Tier.ULT
		_expect(is_ult == SpellTier.slot_accepts_ult(i),
			"slot %d (%s) sits on the right shelf" % [i, loadout[i].id])
	# The gap-close is a SIGNATURE, not the R button: this class has no blink.
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(idx)
	_expect(String(hero._cfg.get("mobility2", "")) == "uppercut",
		"R is a rising cut — the kit's Crescent Step is the only gap-close it gets")
	hero.queue_free()
	_completes("swordsaint_kit")


## THE CARD MUST NOT PROMISE A SPELL THE CLASS DOES NOT HOLD.
##
## This is the bug the ClassInfo header is about: the blurbs advertised beams that
## lived only in `build_all()` (the review harness) and were in nobody's kit, which
## is a direct cause of the maker's "where are those cool heavy beams, why can I
## only see one or two". A card is a promise; this is the test that keeps it.
##
## Prefix rather than equality, because a card says "Ult Judgment" where the spell
## is "Judgment · Divine Ray" — the short form is deliberate, the WRONG spell is not.
func _test_cards_do_not_lie() -> void:
	for cls: int in ClassInfo.count():
		var blurb: String = String(ClassInfo.CLASSES[cls]["kit"])
		var marker: int = blurb.rfind("Ult ")
		_expect(marker >= 0, "class %d's card names an ult" % cls)
		if marker < 0:
			continue
		var claimed: String = blurb.substr(marker + 4).strip_edges()
		var loadout: Array = SpellLibrary.build_for_class(cls)
		_expect(loadout.size() == SpellTier.SLOT_COUNT,
			"class %d has a full hand to check against" % cls)
		if loadout.size() != SpellTier.SLOT_COUNT:
			continue
		var real: String = String(loadout[SpellTier.ULT_SLOT].display_name)
		_expect(real.begins_with(claimed),
			"class %d's card promises ult '%s' but it equips '%s'" % [cls, claimed, real])
	_completes("cards_do_not_lie")
