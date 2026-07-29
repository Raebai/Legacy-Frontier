# Run: godot --headless --path godot-project --script tools/slice1_test_elements.gd
# Note: tests run on the first _process frame (not _init) because Hero.gd and
# Spell.gd reference autoloads (Sfx, Juice, CombatVfx), and autoload globals
# are only registered with GDScript after the main loop is set up — so both
# scenes are load()ed at runtime, never preload()ed.
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
	"element_colors_distinct_and_correct",
	"display_names_and_count",
	"cycle_wrap_math",
	"hero_element_cycling",
	"hero_colourway_cycling",
	"spell_bolt_element_tint",
]

var _fails: int = 0
var _completed: Dictionary = {}

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const SPELL_SCENE_PATH: String = "res://scenes/combat/Spell.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_element_colors_distinct_and_correct()
	_test_display_names_and_count()
	_test_cycle_wrap_math()
	_test_hero_element_cycling()
	_test_hero_colourway_cycling()
	_test_spell_bolt_element_tint()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice1 elements tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice1 elements tests: all PASS")
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


func _make_hero() -> CharacterBody2D:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	var hero: CharacterBody2D = hero_scene.instantiate()
	root.add_child(hero)  # freed with root at exit
	return hero


func _make_spell() -> Area2D:
	var spell_scene: PackedScene = load(SPELL_SCENE_PATH)
	var spell: Area2D = spell_scene.instantiate()
	root.add_child(spell)
	return spell


## The eight element colours are exactly as specced AND mutually distinct.
func _test_element_colors_distinct_and_correct() -> void:
	var expected: Array[Color] = [
		Color(1.0, 0.45, 0.15),  # FIRE
		Color(0.5, 0.85, 1.0),  # ICE
		Color(1.0, 0.9, 0.3),  # LIGHTNING
		Color(0.6, 0.35, 0.9),  # SHADOW
		Color(0.95, 0.4, 0.85),  # ARCANE
		Color(0.78, 0.55, 0.28),  # EARTH
		Color(1.0, 0.93, 0.6),  # HOLY
		Color(0.62, 0.96, 0.86),  # WIND
	]
	for e: int in range(Elements.count()):
		_expect(
			Elements.color(e) == expected[e],
			"element %d colour matches spec (got %s)" % [e, Elements.color(e)]
		)
	for a: int in range(Elements.count()):
		for b: int in range(a + 1, Elements.count()):
			_expect(
				Elements.color(a) != Elements.color(b),
				"elements %d and %d have distinct colours" % [a, b]
			)
	_completes("element_colors_distinct_and_correct")


## display_name covers all eight; count() is 8.
func _test_display_names_and_count() -> void:
	_expect(Elements.count() == 8, "count() is 8")
	var names: Array[String] = ["Fire", "Ice", "Lightning", "Shadow", "Arcane", "Earth", "Holy", "Wind"]
	for e: int in range(Elements.count()):
		_expect(
			Elements.display_name(e) == names[e],
			"display_name(%d) is %s (got %s)" % [e, names[e], Elements.display_name(e)]
		)
	_completes("display_names_and_count")


## Cycling wraps: the element after WIND (last) is FIRE (first).
func _test_cycle_wrap_math() -> void:
	_expect(
		(Elements.Element.WIND + 1) % Elements.count() == Elements.Element.FIRE,
		"(WIND + 1) %% count() wraps to FIRE"
	)
	_expect(
		(Elements.Element.FIRE + 1) % Elements.count() == Elements.Element.ICE,
		"(FIRE + 1) %% count() advances to ICE"
	)
	_expect(
		(Elements.Element.ARCANE + 1) % Elements.count() == Elements.Element.EARTH,
		"(ARCANE + 1) %% count() advances to EARTH (the first appended element)"
	)
	_completes("cycle_wrap_math")


## Hero defaults to ARCANE (aura = arcane magenta); cycling advances to FIRE
## and recolours the aura; five cycles land back on ARCANE.
func _test_hero_element_cycling() -> void:
	var hero: CharacterBody2D = _make_hero()
	_expect(
		hero._element == Elements.Element.ARCANE, "hero defaults to ARCANE"
	)
	_expect(
		hero._element_color == Elements.color(Elements.Element.ARCANE),
		"_element_color starts as the arcane colour"
	)
	_expect(
		hero.rig.aura_color == Elements.color(Elements.Element.ARCANE),
		"aura starts as the arcane colour"
	)

	hero._cycle_element()
	_expect(
		hero._element == Elements.Element.EARTH, "one cycle advances ARCANE -> EARTH"
	)
	_expect(
		hero.rig.aura_color == Elements.color(Elements.Element.EARTH),
		"aura recolours to earth on cycle"
	)
	_expect(
		hero._element_color == Elements.color(Elements.Element.EARTH),
		"_element_color follows the cycle (feeds the cast bolt)"
	)

	for i: int in range(Elements.count() - 1):
		hero._cycle_element()
	_expect(
		hero._element == Elements.Element.ARCANE,
		"count() total cycles land back on ARCANE (full wrap)"
	)
	_completes("hero_element_cycling")


## Colourway palette has 5 entries; hero starts on 0 (the original blue);
## cycling retints the rig limbs and wraps over COLOURWAYS.size().
func _test_hero_colourway_cycling() -> void:
	var hero: CharacterBody2D = _make_hero()
	_expect(hero.COLOURWAYS.size() == 5, "five body colourways")
	_expect(hero._colourway == 0, "hero starts on colourway 0")
	_expect(
		hero.rig.limb_color == hero.COLOURWAYS[0],
		"rig limbs start tinted with colourway 0 (Azure)"
	)

	hero._cycle_colourway()
	_expect(hero._colourway == 1, "one cycle advances to colourway 1")
	_expect(
		hero.rig.limb_color == hero.COLOURWAYS[1], "rig limbs retint on cycle"
	)

	var n: int = hero.COLOURWAYS.size()
	for i: int in range(n - 1):
		hero._cycle_colourway()
	_expect(
		hero._colourway == 0, "cycling COLOURWAYS.size() times wraps back to 0"
	)
	_expect(
		hero.rig.limb_color == hero.COLOURWAYS[0], "wrapped rig tint is colourway 0 again"
	)
	_completes("hero_colourway_cycling")


## Spell.set_element_color forwards to the bolt visual (glow/trail take the
## element rgb, core stays near-white); an untouched spell keeps the warm
## default look.
func _test_spell_bolt_element_tint() -> void:
	var plain: Area2D = _make_spell()
	var plain_visual: SpellBoltVisual = plain.get_node("BoltVisual") as SpellBoltVisual
	_expect(
		plain_visual._glow_color == SpellBoltVisual.GLOW_COLOR,
		"untinted bolt keeps the default warm glow"
	)
	_expect(
		plain_visual._trail_color == SpellBoltVisual.TRAIL_COLOR,
		"untinted bolt keeps the default warm trail"
	)
	_expect(
		plain_visual._core_color == SpellBoltVisual.CORE_COLOR,
		"untinted bolt keeps the default hot core"
	)

	var spell: Area2D = _make_spell()
	var ice: Color = Elements.color(Elements.Element.ICE)
	spell.call("set_element_color", ice)
	var visual: SpellBoltVisual = spell.get_node("BoltVisual") as SpellBoltVisual
	_expect(
		visual._glow_color == Color(ice.r, ice.g, ice.b, SpellBoltVisual.GLOW_COLOR.a),
		"tinted glow takes the element rgb (alpha preserved)"
	)
	_expect(
		visual._trail_color == Color(ice.r, ice.g, ice.b, SpellBoltVisual.TRAIL_COLOR.a),
		"tinted trail takes the element rgb (alpha preserved)"
	)
	_expect(
		visual._core_color != SpellBoltVisual.CORE_COLOR
		and visual._core_color.r > 0.8 and visual._core_color.g > 0.8,
		"core is nudged toward the element but stays hot/bright"
	)
	_completes("spell_bolt_element_tint")
