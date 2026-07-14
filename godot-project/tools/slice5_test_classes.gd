# Run: godot --headless --path godot-project --script tools/slice5_test_classes.gd
# Slice 5: the EIGHT-class roster. Verifies every class configures cleanly with the
# right element / AoE variant / signature loadout, the Chidori (LightningRush) line
# geometry, and the three appended elements' ailment mappings.
# Hero.gd + LightningRush reference autoloads, so scenes are load()ed at runtime
# (repo test-trap idiom) and tests run on the first _process frame.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
# LightningRush calls Sfx.* directly, so it must be load()ed at RUNTIME (autoloads
# aren't registered at parse time — the repo preload trap). StatusComponent looks
# Sfx up by node path, so it preloads safely.
const RUSH_PATH: String = "res://scripts/combat/LightningRush.gd"
const CHAIN_PATH: String = "res://scripts/combat/ChainBolt.gd"  # runtime-load (autoload-safe)
const StatusScript: GDScript = preload("res://scripts/combat/StatusComponent.gd")

var _ran: bool = false


class Dummy:
	extends Node2D
	var dmg: Array[int] = []
	func take_damage(a: int) -> void:
		dmg.append(a)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	failed += _test_all_classes_configure()
	failed += _test_class_elements_and_aoe()
	failed += _test_class_primaries()
	failed += _test_signature_loadouts()
	failed += _test_rush_line_geometry()
	failed += _test_chain_geometry()
	failed += _test_new_element_ailments()
	if failed > 0:
		printerr("Slice5 class tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Slice5 class tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	return hero


## Every one of the 8 classes configures without error and reports its name.
func _test_all_classes_configure() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	var names: Array = hero.CLASS_NAMES
	failed += _expect(names.size() == 8, "8 class display names")
	failed += _expect(int(hero.HeroClass.size()) == 8, "8 HeroClass enum values")
	for cls: int in range(8):
		hero.configure_class(cls)
		failed += _expect(int(hero._hero_class) == cls, "class %d configured" % cls)
		failed += _expect(
			hero.class_display_name() == String(names[cls]),
			"class %d reports its display name %s" % [cls, names[cls]]
		)
	hero.queue_free()
	return failed


## Each class auto-sets its signature element and its AoE (Q) variant.
func _test_class_elements_and_aoe() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	# element index per class (matches CLASS_CONFIG): FIRE0 ICE1 LIGHT2 SHAD3 ARC4 EARTH5 HOLY6 WIND7
	var expect_element: Array[int] = [4, 3, 0, 5, 6, 1, 2, 3]  # Arcanist..Warlock
	var expect_aoe: Array[String] = ["blast", "nova", "fist_shock", "ground_slam", "blast", "blast", "blast", "blast"]
	for cls: int in range(8):
		hero.configure_class(cls)
		failed += _expect(int(hero._element) == expect_element[cls], "class %d element = %d" % [cls, expect_element[cls]])
		failed += _expect(String(hero._cfg["aoe"]) == expect_aoe[cls], "class %d AoE = %s" % [cls, expect_aoe[cls]])
	hero.queue_free()
	return failed


## Each class has a STRUCTURALLY distinct primary (LMB) + movement identity — the
## maker's "classes must feel different, not just different spells" requirement.
func _test_class_primaries() -> int:
	var failed: int = 0
	var hero: CharacterBody2D = _make_hero()
	# Expected LMB primary per class (default "bolt" when unset).
	var expect_primary: Array[String] = [
		"bolt", "bolt", "melee_combo", "heavy_swing", "bolt", "frost_cone", "bolt", "bolt"
	]
	for cls: int in range(8):
		hero.configure_class(cls)
		var prim: String = String(hero._cfg.get("primary", "bolt"))
		failed += _expect(prim == expect_primary[cls], "class %d primary = %s (got %s)" % [cls, expect_primary[cls], prim])
	# Brawler (2): melee primary + no magic + a double-jump + an uppercut mobility.
	hero.configure_class(2)
	failed += _expect(int(hero._max_air_jumps) == 1, "Brawler double-jumps (air_jumps 1)")
	failed += _expect(String(hero._cfg.get("mobility2", "")) == "uppercut", "Brawler R is the uppercut")
	# Juggernaut (3): wide slow swing + a long BLOCK window.
	hero.configure_class(3)
	failed += _expect(hero._melee_arc_dot <= 0.0, "Juggernaut swings a wide (>=180deg) arc")
	failed += _expect(hero._parry_window_len > 0.3, "Juggernaut BLOCK has a long defensive window")
	# Cleric (4) heal-bolt + Stormcaller (6) chain-bolt flags present.
	hero.configure_class(4)
	failed += _expect(int(hero._cfg.get("bolt_heal", 0)) > 0, "Cleric bolt lifesteals")
	hero.configure_class(6)
	failed += _expect(int(hero._cfg.get("bolt_chain", 0)) > 0, "Stormcaller bolt chains")
	hero.queue_free()
	return failed


## Each class equips its themed loadout (non-empty SpellDefs); the Brawler leads
## with the Chidori RUSH, the Cleric with Heaven's Verdict.
func _test_signature_loadouts() -> int:
	var failed: int = 0
	for cls: int in range(8):
		var loadout: Array = SpellLibrary.build_for_class(cls)
		failed += _expect(not loadout.is_empty(), "class %d has a signature loadout" % cls)
		for s in loadout:
			failed += _expect(s is SpellDef and s.display_name != "", "class %d loadout entries are named SpellDefs" % cls)
	# Brawler (2) leads with the Chidori lightning RUSH.
	var brawler: Array = SpellLibrary.build_for_class(2)
	failed += _expect(brawler[0].id == "chidori", "Brawler's first signature is the Chidori")
	failed += _expect(int(brawler[0].kind) == int(SpellDef.Kind.RUSH), "Chidori is a RUSH-kind spell")
	# Cleric (4) leads with Heaven's Verdict (convergence).
	var cleric: Array = SpellLibrary.build_for_class(4)
	failed += _expect(cleric[0].id == "heavens_verdict", "Cleric's first signature is Heaven's Verdict")
	# Juggernaut (3) now leads with the full earthbending kit (Boulder Hurl first).
	var jugg: Array = SpellLibrary.build_for_class(3)
	failed += _expect(jugg[0].id == "boulder_hurl", "Juggernaut's first signature is Boulder Hurl")
	failed += _expect(int(jugg[0].element) == 5, "Boulder Hurl carries the EARTH element (Stagger)")
	failed += _expect(jugg.size() >= 5, "Juggernaut has the 3 earth-kit spells + 2 legacy ults")
	failed += _expect(jugg[1].id == "rock_pillar" and jugg[2].id == "rock_wall", "earth kit: pillar then wall")
	# Cryomancer (5) + Stormcaller (6) now lead with BESPOKE kits, not beam-clones.
	var cryo: Array = SpellLibrary.build_for_class(5)
	failed += _expect(cryo[0].id == "ice_wall" and int(cryo[0].kind) == int(SpellDef.Kind.ICE_WALL), "Cryomancer leads with the Ice Wall (not a beam)")
	var storm: Array = SpellLibrary.build_for_class(6)
	failed += _expect(storm[0].id == "chain_lightning" and int(storm[0].kind) == int(SpellDef.Kind.CHAIN), "Stormcaller leads with Chain Lightning (not a beam)")
	# Arcanist keeps Zoltraak (the one legit beam) but its meteor-clone -> rune-orbs.
	var arc: Array = SpellLibrary.build_for_class(0)
	failed += _expect(arc[1].id == "rune_orbs" and int(arc[1].kind) == int(SpellDef.Kind.MISSILES), "Arcanist's alt is homing rune-orbs (not a meteor)")
	# Shadowblade: teleport-strike + blade flurry (no beam, no meteor).
	var shadow: Array = SpellLibrary.build_for_class(1)
	failed += _expect(shadow[0].id == "blink_strike" and int(shadow[0].kind) == int(SpellDef.Kind.BLINK_STRIKE), "Shadowblade leads with the teleport-strike")
	failed += _expect(int(shadow[1].kind) == int(SpellDef.Kind.FLURRY), "Shadowblade's alt is the blade flurry")
	# Warlock: void zone + drain tether (no beam, no meteor).
	var lock: Array = SpellLibrary.build_for_class(7)
	failed += _expect(lock[0].id == "void_zone" and int(lock[0].kind) == int(SpellDef.Kind.ZONE), "Warlock leads with the Void Zone field")
	failed += _expect(int(lock[1].kind) == int(SpellDef.Kind.TETHER), "Warlock's alt is the drain tether")
	# Cryomancer's alt is now a Blizzard ZONE (not the frozen-comet meteor).
	failed += _expect(int(cryo[1].kind) == int(SpellDef.Kind.ZONE), "Cryomancer's alt is the Blizzard field (not a meteor)")
	# No class still leads with a plain BEAM except Arcanist's canonical Zoltraak.
	for cls2: int in range(8):
		var lo: Array = SpellLibrary.build_for_class(cls2)
		if int(lo[0].kind) == int(SpellDef.Kind.BEAM):
			failed += _expect(lo[0].id == "zoltraak", "class %d's signature beam is only the legit Zoltraak (got %s)" % [cls2, lo[0].id])
	return failed


## ChainBolt.build_chain: target 1 is the nearest enemy in the aim direction; each
## hop is the nearest unvisited within hop range; behind-the-origin is skipped.
func _test_chain_geometry() -> int:
	var failed: int = 0
	var a := Dummy.new(); a.global_position = Vector2(120, 0)    # first target (ahead)
	var b := Dummy.new(); b.global_position = Vector2(260, 40)   # within hop of a
	var c := Dummy.new(); c.global_position = Vector2(1000, 0)   # too far for hop 2
	var behind := Dummy.new(); behind.global_position = Vector2(-200, 0)  # behind origin
	var chain_script: GDScript = load(CHAIN_PATH)
	var links: Array = chain_script.build_chain(Vector2.ZERO, Vector2.RIGHT, 560.0, 240.0, 5, [a, b, c, behind])
	failed += _expect(links.size() == 2, "chain hits the reachable pair (a -> b), stops at the gap")
	failed += _expect(links.size() >= 1 and links[0] == a, "first link is the nearest forward target")
	failed += _expect(not links.has(behind), "a target behind the origin is never chained")
	failed += _expect(not links.has(c), "a target beyond hop range is not reached")
	a.free(); b.free(); c.free(); behind.free()
	return failed


## LightningRush.targets_on_line: only nodes whose centre lies on the segment
## within the half-width are struck (pure geometry, mirrors the beam test).
func _test_rush_line_geometry() -> int:
	var failed: int = 0
	var on_line := Dummy.new()
	on_line.global_position = Vector2(200, 0)   # straight ahead, on the line
	var off_line := Dummy.new()
	off_line.global_position = Vector2(200, 80)  # far off the line
	var behind := Dummy.new()
	behind.global_position = Vector2(-50, 0)     # behind the origin
	var rush_script: GDScript = load(RUSH_PATH)  # runtime load (autoload-safe)
	var hit: Array = rush_script.targets_on_line(
		Vector2.ZERO, Vector2.RIGHT, 620.0, 20.0, [on_line, off_line, behind]
	)
	failed += _expect(hit.has(on_line), "a target on the lance line is struck")
	failed += _expect(not hit.has(off_line), "a target off the line is missed")
	failed += _expect(not hit.has(behind), "a target behind the origin is missed")
	on_line.free(); off_line.free(); behind.free()
	return failed


## The three appended elements map onto proven ailments: EARTH staggers (hard CC),
## HOLY burns (active DoT), WIND stuns (hard CC).
func _test_new_element_ailments() -> int:
	var failed: int = 0
	var holder := Node2D.new()
	root.add_child(holder)

	var earth: StatusComponent = StatusScript.new()
	holder.add_child(earth)
	earth.apply(StatusScript.EARTH)
	failed += _expect(earth.is_hard_cc(), "EARTH applies a Stagger (hard CC / root)")

	var holy: StatusComponent = StatusScript.new()
	holder.add_child(holy)
	holy.apply(StatusScript.HOLY)
	failed += _expect(holy.is_active() and not holy.is_hard_cc(), "HOLY applies a Radiance burn (active, not CC)")

	var wind: StatusComponent = StatusScript.new()
	holder.add_child(wind)
	wind.apply(StatusScript.WIND)
	failed += _expect(wind.is_hard_cc(), "WIND applies a Gale stun (hard CC)")

	holder.queue_free()
	return failed
