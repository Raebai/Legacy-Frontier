# Run: godot --headless --path godot-project --script tools/slice1_test_elements.gd
# Note: tests run on the first _process frame (not _init) because Hero.gd and
# Spell.gd reference autoloads (Sfx, Juice, CombatVfx), and autoload globals
# are only registered with GDScript after the main loop is set up — so both
# scenes are load()ed at runtime, never preload()ed.
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const SPELL_SCENE_PATH: String = "res://scenes/combat/Spell.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_element_colors_distinct_and_correct()
	failed += _test_display_names_and_count()
	failed += _test_cycle_wrap_math()
	failed += _test_hero_element_cycling()
	failed += _test_hero_colourway_cycling()
	failed += _test_spell_bolt_element_tint()
	if failed > 0:
		printerr("Slice1 elements tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice1 elements tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


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


## The five element colours are exactly as specced AND mutually distinct.
func _test_element_colors_distinct_and_correct() -> int:
	var failed: int = 0
	var expected: Array[Color] = [
		Color(1.0, 0.45, 0.15),  # FIRE
		Color(0.5, 0.85, 1.0),  # ICE
		Color(1.0, 0.9, 0.3),  # LIGHTNING
		Color(0.6, 0.35, 0.9),  # SHADOW
		Color(0.95, 0.4, 0.85),  # ARCANE
	]
	for e: int in range(Elements.count()):
		failed += _expect(
			Elements.color(e) == expected[e],
			"element %d colour matches spec (got %s)" % [e, Elements.color(e)]
		)
	for a: int in range(Elements.count()):
		for b: int in range(a + 1, Elements.count()):
			failed += _expect(
				Elements.color(a) != Elements.color(b),
				"elements %d and %d have distinct colours" % [a, b]
			)
	return failed


## display_name covers all five; count() is 5.
func _test_display_names_and_count() -> int:
	var failed: int = 0
	failed += _expect(Elements.count() == 5, "count() is 5")
	var names: Array[String] = ["Fire", "Ice", "Lightning", "Shadow", "Arcane"]
	for e: int in range(Elements.count()):
		failed += _expect(
			Elements.display_name(e) == names[e],
			"display_name(%d) is %s (got %s)" % [e, names[e], Elements.display_name(e)]
		)
	return failed


## Cycling wraps: the element after ARCANE (last) is FIRE (first).
func _test_cycle_wrap_math() -> int:
	var failed: int = 0
	failed += _expect(
		(Elements.Element.ARCANE + 1) % Elements.count() == Elements.Element.FIRE,
		"(ARCANE + 1) %% count() wraps to FIRE"
	)
	failed += _expect(
		(Elements.Element.FIRE + 1) % Elements.count() == Elements.Element.ICE,
		"(FIRE + 1) %% count() advances to ICE"
	)
	return failed


## Hero defaults to ARCANE (aura = arcane magenta); cycling advances to FIRE
## and recolours the aura; five cycles land back on ARCANE.
func _test_hero_element_cycling() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	failed += _expect(
		hero._element == Elements.Element.ARCANE, "hero defaults to ARCANE"
	)
	failed += _expect(
		hero._element_color == Elements.color(Elements.Element.ARCANE),
		"_element_color starts as the arcane colour"
	)
	failed += _expect(
		hero.rig.aura_color == Elements.color(Elements.Element.ARCANE),
		"aura starts as the arcane colour"
	)

	hero._cycle_element()
	failed += _expect(
		hero._element == Elements.Element.FIRE, "one cycle wraps ARCANE -> FIRE"
	)
	failed += _expect(
		hero.rig.aura_color == Elements.color(Elements.Element.FIRE),
		"aura recolours to fire on cycle"
	)
	failed += _expect(
		hero._element_color == Elements.color(Elements.Element.FIRE),
		"_element_color follows the cycle (feeds the cast bolt)"
	)

	for i: int in range(Elements.count() - 1):
		hero._cycle_element()
	failed += _expect(
		hero._element == Elements.Element.ARCANE,
		"five total cycles land back on ARCANE (full wrap)"
	)
	return failed


## Colourway palette has 5 entries; hero starts on 0 (the original blue);
## cycling retints the rig limbs and wraps over COLOURWAYS.size().
func _test_hero_colourway_cycling() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	failed += _expect(hero.COLOURWAYS.size() == 5, "five body colourways")
	failed += _expect(hero._colourway == 0, "hero starts on colourway 0")
	failed += _expect(
		hero.rig.limb_color == hero.COLOURWAYS[0],
		"rig limbs start tinted with colourway 0 (Azure)"
	)

	hero._cycle_colourway()
	failed += _expect(hero._colourway == 1, "one cycle advances to colourway 1")
	failed += _expect(
		hero.rig.limb_color == hero.COLOURWAYS[1], "rig limbs retint on cycle"
	)

	var n: int = hero.COLOURWAYS.size()
	for i: int in range(n - 1):
		hero._cycle_colourway()
	failed += _expect(
		hero._colourway == 0, "cycling COLOURWAYS.size() times wraps back to 0"
	)
	failed += _expect(
		hero.rig.limb_color == hero.COLOURWAYS[0], "wrapped rig tint is colourway 0 again"
	)
	return failed


## Spell.set_element_color forwards to the bolt visual (glow/trail take the
## element rgb, core stays near-white); an untouched spell keeps the warm
## default look.
func _test_spell_bolt_element_tint() -> int:
	var failed: int = 0
	var plain: Area2D = _make_spell()
	var plain_visual: SpellBoltVisual = plain.get_node("BoltVisual") as SpellBoltVisual
	failed += _expect(
		plain_visual._glow_color == SpellBoltVisual.GLOW_COLOR,
		"untinted bolt keeps the default warm glow"
	)
	failed += _expect(
		plain_visual._trail_color == SpellBoltVisual.TRAIL_COLOR,
		"untinted bolt keeps the default warm trail"
	)
	failed += _expect(
		plain_visual._core_color == SpellBoltVisual.CORE_COLOR,
		"untinted bolt keeps the default hot core"
	)

	var spell: Area2D = _make_spell()
	var ice: Color = Elements.color(Elements.Element.ICE)
	spell.call("set_element_color", ice)
	var visual: SpellBoltVisual = spell.get_node("BoltVisual") as SpellBoltVisual
	failed += _expect(
		visual._glow_color == Color(ice.r, ice.g, ice.b, SpellBoltVisual.GLOW_COLOR.a),
		"tinted glow takes the element rgb (alpha preserved)"
	)
	failed += _expect(
		visual._trail_color == Color(ice.r, ice.g, ice.b, SpellBoltVisual.TRAIL_COLOR.a),
		"tinted trail takes the element rgb (alpha preserved)"
	)
	failed += _expect(
		visual._core_color != SpellBoltVisual.CORE_COLOR
		and visual._core_color.r > 0.8 and visual._core_color.g > 0.8,
		"core is nudged toward the element but stays hot/bright"
	)
	return failed
