# Run: godot --headless --path godot-project --script tools/slice_test_loadout.gd
# Gear-ABILITY integration: a real Hero, real configure_class + set_loadout, asserting
# the wired effects actually land — weapon sets/reverts the element, hat scales max HP,
# robe wards, armour reduces, hammer scales melee — and that class DEFAULTS are
# untouched (override-only) and re-applying is idempotent. Hero.tscn is load()ed at
# runtime (autoload test-trap); tests run on the first _process frame.
#
# ⚠ THE BUG THIS FILE SHIPPED WITH, and why the plumbing below is shaped the way it
# is. Gear mitigation used to live in Hero fields (`_gear_ward_frac`); it MOVED to the
# shared GuardComponent. This suite kept asserting the dead Hero field — and kept
# printing "all PASS".
#
# Reading a member that no longer exists is NOT a test failure in GDScript. It logs a
# runtime error, ABORTS the enclosing function on the spot, and hands the caller back
# the return type's zero value. Under the old `var f: int = 0 ... f += _expect(...)` /
# `f += _test_thing()` idiom that reads as "this test found zero failures". So the
# suite was green while verifying nothing — and silently skipping every assertion
# AFTER the dead line: four of the six checks in the head/body test never ran at all.
#
# Static typing does NOT save you here, and that is worth writing down because it is
# the obvious wrong fix: `var g: GuardComponent = ...; g.renamed_field` compiles clean
# and still fails at runtime ("Invalid access to property ... on a base object of type
# 'Node (GuardComponent)'") — the same silent abort. MEASURED, not assumed. So the
# guards are runtime ones:
#
#   1. COMPLETION SENTINELS. Failures accumulate on `_fails` (a MEMBER, not a return
#      value) and every test's last line records that it reached the end. A test that
#      aborts half-way therefore fails the suite by ABSENCE — whatever the cause,
#      whichever member moved house, with nobody having to predict it in advance.
#      This is the structural guard, and it is what makes the file unable to pass
#      vacuously.
#   2. _require_props NAMES the casualty. The sentinel says "something died"; this
#      says which member did, so the next relocation is a one-line diagnosis rather
#      than a hunt.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"

## Hero members this suite reaches DYNAMICALLY (Hero.gd has no class_name, so every
## `hero.max_hp` is a runtime lookup). Listed once so the existence check is a single
## call instead of a check scattered per assertion.
const HERO_MEMBERS: Array[String] = [
	"hp", "max_hp", "_element", "_gear_speed_mult",
	"_melee_damage", "_melee_knockback",
	"_base_melee_damage", "_base_melee_knockback",
]
## ...and the GuardComponent members gear mitigation actually lives in now. This is
## the exact list whose previous home (`_gear_ward_frac` on Hero) went stale.
const GUARD_MEMBERS: Array[String] = ["oneshot_fraction", "persistent_reduction"]

## Every test that must run to completion. A name missing from `_completed` at the end
## means that test aborted part-way — the failure mode this file is armoured against —
## and fails the suite.
const TESTS: Array[String] = [
	"defaults_untouched", "weapon_element", "head_body_melee",
	"gear_mitigation_is_real", "idempotent_recompute",
	"signature_short_name",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_pin_level_one()
	_test_defaults_untouched()
	_test_weapon_sets_and_reverts_element()
	_test_head_body_and_melee_effects()
	_test_gear_mitigation_is_real()
	_test_idempotent_recompute()
	_test_signature_short_name()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Loadout tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Loadout tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort, instead of being thrown away with the
## aborted function's discarded result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## ⚠ PIN THE CLIMBER AT LEVEL 1, OR THIS SUITE TESTS THE TESTER'S SAVE FILE.
##
## Every gear multiplier below is asserted against the class base, and Hero now
## composes LEVEL GROWTH on top of that base through the SAME aggregate. GameState
## loads the real `user://climber.json` and its node IS on the tree under `--script`
## (the autoload IDENTIFIER is not — that is the trap that hides this), so on a
## machine whose owner has played, "no gear -> speed x1" is false through no fault
## of the gear code.
##
## Growth's own behaviour is asserted by `tools/slice_test_progression.gd` and by
## `slice_test_class_movement`'s `level_growth_actually_moves_the_stats`.
func _pin_level_one() -> void:
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs == null:
		return
	gs.set("_xp", 0)
	if gs.has_method("clear_party_level"):
		gs.call("clear_party_level")


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	return hero


## Assert the dynamically-reached members are all still THERE, by name. The completion
## sentinel already catches a relocation; this says WHICH member relocated.
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


## A class with NO loadout override plays exactly at its tuned base (override-only).
func _test_defaults_untouched() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.CRYOMANCER)  # default weapon staff_ice, element ICE
	_require_props(hero, HERO_MEMBERS, "Hero")
	_expect(int(hero._element) == int(Elements.Element.ICE), "cryomancer default element ICE")
	# ⚠ NOT `== 100` ANY MORE. `CLASS_CONFIG` carries a per-class `hp` now (nine
	# different bodies — see tools/slice_test_class_movement.gd), so a literal here
	# would be pinning the Cryomancer's number in a suite that is about GEAR. What this
	# line has always meant is "with nothing equipped, max_hp IS the class base" — so
	# it asks the class base rather than restating one class's value.
	_expect(int(hero.max_hp) == int(hero._base_max_hp),
		"no gear -> max_hp is the class base (%d vs %d)"
			% [int(hero.max_hp), int(hero._base_max_hp)])
	_expect(int(hero.max_hp) != 100,
		"the Cryomancer no longer shares the old universal 100 HP (got %d)" % int(hero.max_hp))
	_expect(is_equal_approx(float(hero._gear_speed_mult), 1.0), "no gear -> speed x1")
	_expect(is_equal_approx(float(hero._melee_knockback), float(hero._base_melee_knockback)),
		"no gear -> base melee kb")
	# Mitigation now lives on the shared guard, which configure_class attaches via
	# _recompute_gear_effects -> GuardComponent.of(self).
	var guard: GuardComponent = GuardComponent.peek(hero)
	_expect(guard != null, "configuring a class attaches a GuardComponent")
	_require_props(guard, GUARD_MEMBERS, "GuardComponent")
	_expect(guard != null and guard.has_method("mitigate"), "GuardComponent still exposes mitigate()")
	if guard != null:
		_expect(is_equal_approx(guard.oneshot_fraction, 0.0), "no gear -> no ward")
		_expect(is_equal_approx(guard.persistent_reduction, 0.0), "no gear -> no armour")
		_expect(guard.mitigate(100) == 100, "no gear -> a 100 hit lands in full")
	hero.queue_free()
	_completes("defaults_untouched")


## The flagship: an elemental weapon sets the element; a non-elemental one reverts to
## the class innate; clearing the slot also reverts.
func _test_weapon_sets_and_reverts_element() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.MAGE)  # innate ARCANE
	_expect(int(hero._element) == int(Elements.Element.ARCANE), "mage base ARCANE")
	hero.set_loadout("weapon", "staff_ice")
	_expect(int(hero._element) == int(Elements.Element.ICE), "staff_ice -> ICE")
	hero.set_loadout("weapon", "staff_storm")
	_expect(int(hero._element) == int(Elements.Element.LIGHTNING), "staff_storm -> LIGHTNING")
	hero.set_loadout("weapon", "hammer")  # non-elemental
	_expect(int(hero._element) == int(Elements.Element.ARCANE), "hammer reverts to innate ARCANE")
	hero.set_loadout("weapon", "")  # cleared
	_expect(int(hero._element) == int(Elements.Element.ARCANE), "cleared weapon reverts to innate")
	hero.queue_free()
	_completes("weapon_element")


## hat -> +12% HP, robe -> ward, hood -> speed (and replaces the hat), hammer ->
## melee mults (from the class base). Every line below the ward assertion used to be
## unreachable: the dead `_gear_ward_frac` read aborted the function before them.
func _test_head_body_and_melee_effects() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.MAGE)
	var base_kb: float = float(hero._base_melee_knockback)
	var base_dmg: int = int(hero._base_melee_damage)
	# DERIVED FROM THE CLASS BASE, not a literal 112. The hat is +12% of whatever this
	# class's body is, and that is now a per-class number — the point of the assertion
	# is that gear MULTIPLIES the class rather than replacing it.
	var base_hp: int = int(hero._base_max_hp)
	hero.set_loadout("head", "hat")
	_expect(int(hero.max_hp) == int(round(float(base_hp) * 1.12)),
		"hat -> +12%% of the class base (%d -> %d, wanted %d)"
			% [base_hp, int(hero.max_hp), int(round(float(base_hp) * 1.12))])
	_expect(int(hero.hp) <= int(hero.max_hp), "hp within new max")
	hero.set_loadout("body", "robe")
	var guard: GuardComponent = GuardComponent.peek(hero)
	_expect(guard != null, "the hero has a GuardComponent after a loadout swap")
	if guard != null:
		_expect(is_equal_approx(guard.oneshot_fraction, 0.4), "robe -> ward 0.4")
	hero.set_loadout("head", "hood")
	_expect(is_equal_approx(float(hero._gear_speed_mult), 1.12), "hood -> speed x1.12")
	# ⚠ THE POINT OF THIS ASSERTION IS IDEMPOTENCE, NOT THE NUMBER. It exists to
	# prove a swap RE-BASES off the class table instead of compounding on whatever
	# the last piece left behind — and it read `== base_hp` only because `hood` used
	# to touch nothing but speed. It pays -6% max HP now (every piece pays something
	# as of 2026-08-04), so the honest expectation is the class base times the hood's
	# own multiplier, and it is DERIVED from the table so a retune cannot make this
	# test lie in either direction.
	#
	# The compounding bug it guards against would show as hat x hood (1.12 x 0.94)
	# rather than hood alone, which this still catches.
	# ⚠ THE ROBE IS STILL IN THE BODY SLOT (set eight lines up) AND IT ALSO COSTS
	# max HP now. My first pass at this expectation forgot that and asserted the hood
	# alone — which is the same class of mistake the assertion is guarding against,
	# just made by the test instead of the code. The whole equipped BAG is what
	# composes, so the whole bag is what the expectation multiplies.
	var hood_hp: float = float(GearAbilities.effect("hood").get("max_hp", 1.0))
	var robe_hp: float = float(GearAbilities.effect("robe").get("max_hp", 1.0))
	var expect_hp: int = maxi(int(round(float(base_hp) * hood_hp * robe_hp)), 1)
	_expect(int(hero.max_hp) == expect_hp,
		"hood replaced hat -> max_hp re-based off the CLASS base, not compounded (%d, base %d)"
			% [expect_hp, base_hp])
	_expect(hood_hp < 1.0, "...and the hood genuinely costs max HP, or the check above is vacuous")
	# The compounding bug this guards against would leave the HAT's +12% in the
	# product. Asserted explicitly so the claim in the comment is actually tested.
	var hat_hp: float = float(GearAbilities.effect("hat").get("max_hp", 1.0))
	_expect(int(hero.max_hp) != maxi(int(round(float(base_hp) * hat_hp * hood_hp * robe_hp)), 1),
		"...and the replaced HAT is gone from the product, not compounded into it")
	hero.set_loadout("weapon", "hammer")
	_expect(is_equal_approx(float(hero._melee_knockback), base_kb * 1.4),
		"hammer -> +40% knockback from base")
	_expect(int(hero._melee_damage) == int(round(float(base_dmg) * 1.2)),
		"hammer -> +20% damage from base")
	hero.queue_free()
	_completes("head_body_melee")


## The BEHAVIOURAL half — assertions that break if mitigation stops WORKING, not
## merely if a number stops being stored. Reading a field only proves the registry was
## copied across; running mitigate() proves a hit is actually softened.
func _test_gear_mitigation_is_real() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.MAGE)
	hero.set_loadout("body", "robe")
	var guard: GuardComponent = GuardComponent.peek(hero)
	_expect(guard != null, "robe attaches/updates the guard")
	if guard == null:
		hero.queue_free()
		return  # deliberately NOT completed: the missing sentinel fails the suite
	_expect(is_equal_approx(guard.oneshot_fraction, 0.4), "robe -> one-shot ward 0.4")
	# 100 * (1 - 0.4) = 60. No percentage stack is in play, so MIN_DAMAGE_MULT never
	# binds here — the one-shot soak is applied on top of the floor by design.
	_expect(guard.mitigate(100) == 60, "robe wards the FIRST hit (100 -> 60)")
	_expect(guard.mitigate(100) == 100, "...and only the first (100 -> 100)")
	# Re-applying a loadout re-arms the robe — documented behaviour of set_gear
	# ("a fresh loadout = a fresh ward"), and the reason set_loadout is safe to spam.
	hero.set_loadout("body", "robe")
	_expect(guard.mitigate(100) == 60, "re-applying the loadout re-arms the one-shot ward")
	# armor is the other half of the gear-mitigation story: PERSISTENT, not one-shot.
	hero.set_loadout("body", "armor")
	_expect(is_equal_approx(guard.persistent_reduction, 0.15), "armor -> 15% off every hit")
	_expect(is_equal_approx(guard.oneshot_fraction, 0.0), "armor replaced the robe -> ward gone")
	_expect(guard.mitigate(100) == 85, "armour softens every hit (100 -> 85)")
	_expect(guard.mitigate(100) == 85, "...and keeps doing it (100 -> 85)")
	hero.set_loadout("body", "")
	_expect(is_equal_approx(guard.persistent_reduction, 0.0), "clearing the body slot drops the armour")
	_expect(guard.mitigate(100) == 100, "no body gear -> the hit lands in full again")
	hero.queue_free()
	_completes("gear_mitigation_is_real")


## Re-applying the same loadout must not compound (idempotent from the class base).
func _test_idempotent_recompute() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(hero.HeroClass.JUGGERNAUT)  # explicit melee tuning + hammer default
	hero.set_loadout("weapon", "hammer")
	var kb1: float = float(hero._melee_knockback)
	hero.set_loadout("weapon", "hammer")  # same again
	hero.set_loadout("weapon", "hammer")
	_expect(is_equal_approx(float(hero._melee_knockback), kb1),
		"re-equip hammer doesn't compound knockback")
	hero.queue_free()
	_completes("idempotent_recompute")


## THE BIG BEAM'S NAME ON THE HOTBAR. `Hero._signature_hud_slot()` labels the
## signature slot with `display_name.split(" ")[0]` — the FIRST word — which was
## silently correct until the IP pass renamed `zoltraak` to "The Ordinary Spell".
## First word of that is "The", so the maker's signature beam has been reading
## `The` on the bar. AbilityBar re-derives the label from the full name instead,
## and this pins the rule: drop leading articles, then take the first real word.
##
## Every beam in the library is checked, not just the one that broke, because the
## next rename is the one nobody tests.
func _test_signature_short_name() -> void:
	_expect(AbilityBar.short_spell_name("The Ordinary Spell") == "Ordinary",
		"the big beam is `Ordinary`, not `The` (got '%s')"
			% AbilityBar.short_spell_name("The Ordinary Spell"))
	_expect(AbilityBar.short_spell_name("Infernal Lance") == "Infernal",
		"names that already opened with their noun are unchanged")
	_expect(AbilityBar.short_spell_name("Frostpiercer") == "Frostpiercer",
		"a one-word name survives intact")
	_expect(AbilityBar.short_spell_name("Thunderclap") == "Thunderclap",
		"the renamed lightning rush is intact too")
	# A pathological name must never blank the slot: a wrong label is
	# recoverable, an empty one is not.
	_expect(AbilityBar.short_spell_name("The") == "The", "an all-article name falls back whole")
	_expect(AbilityBar.short_spell_name("") == "", "an empty name stays empty rather than erroring")
	# And no spell currently in the library shortens to a bare article.
	const ARTICLES: Array[String] = ["The", "A", "An", "Of"]
	for s: SpellDef in SpellLibrary.build_all():
		_expect(not ARTICLES.has(AbilityBar.short_spell_name(s.display_name)),
			"`%s` does not shorten to an article" % s.display_name)
	_completes("signature_short_name")
