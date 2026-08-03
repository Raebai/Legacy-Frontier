# Run: godot --headless --path godot-project --script tools/slice5_test_classes.gd
# Slice 5: the EIGHT-class roster. Verifies every class configures cleanly with the
# right element / AoE variant / signature loadout, the Thunderclap (LightningRush)
# line geometry, and the three appended elements' ailment mappings.
# Hero.gd + LightningRush reference autoloads, so scenes are load()ed at runtime
# (repo test-trap idiom) and tests run on the first _process frame.
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
	"all_classes_configure",
	"class_elements_and_aoe",
	"class_primaries",
	"signature_loadouts",
	"rush_line_geometry",
	"chain_geometry",
	"new_element_ailments",
]

var _fails: int = 0
var _completed: Dictionary = {}

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
	_test_all_classes_configure()
	_test_class_elements_and_aoe()
	_test_class_primaries()
	_test_signature_loadouts()
	_test_rush_line_geometry()
	_test_chain_geometry()
	_test_new_element_ailments()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slice5 class tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slice5 class tests: all PASS")
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
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	return hero


## Every one of the 8 classes configures without error and reports its name.
func _test_all_classes_configure() -> void:
	var hero: CharacterBody2D = _make_hero()
	var names: Array = hero.CLASS_NAMES
	# DERIVED, never hardcoded. This assertion used to read `== 8`, which is the same
	# stale-count bug as Lobby.gd's `% 8`: adding a class turned a correct roster into
	# a red test and told you nothing about what was actually wrong.
	var roster: int = int(hero.HeroClass.size())
	_expect(names.size() == roster,
		"a display name per class (%d names, %d classes)" % [names.size(), roster])
	_expect(int(hero.CLASS_CONFIG.size()) == roster, "a CLASS_CONFIG row per class")
	_expect(ClassInfo.count() == roster, "a class-select card per class")
	for cls: int in range(roster):
		hero.configure_class(cls)
		_expect(int(hero._hero_class) == cls, "class %d configured" % cls)
		_expect(
			hero.class_display_name() == String(names[cls]),
			"class %d reports its display name %s" % [cls, names[cls]]
		)
	hero.queue_free()
	_completes("all_classes_configure")


## Each class auto-sets its signature element and its AoE (Q) variant.
func _test_class_elements_and_aoe() -> void:
	var hero: CharacterBody2D = _make_hero()
	# element index per class (matches CLASS_CONFIG): FIRE0 ICE1 LIGHT2 SHAD3 ARC4 EARTH5 HOLY6 WIND7
	# Arcanist..Swordsaint. The Swordsaint is ARCANE like the Arcanist, but note its
	# CLASS_CONFIG `melee_element` is -1: the element only TINTS the blade, it is
	# never applied as an ailment, which is that class's whole flavour rule.
	var expect_element: Array[int] = [4, 3, 0, 5, 6, 1, 2, 3, 4]
	# Each class has a DISTINCT Q spectacle now (no more 5 shared blasts).
	var expect_aoe: Array[String] = ["arcane_meteor", "nova", "fist_shock", "ground_slam",
		"consecrate", "ice_shards", "call_lightning", "curse_chain", "ground_slam"]
	for cls: int in range(int(hero.HeroClass.size())):
		hero.configure_class(cls)
		_expect(int(hero._element) == expect_element[cls], "class %d element = %d" % [cls, expect_element[cls]])
		_expect(String(hero._cfg["aoe"]) == expect_aoe[cls], "class %d AoE = %s" % [cls, expect_aoe[cls]])
	hero.queue_free()
	_completes("class_elements_and_aoe")


## Each class has a STRUCTURALLY distinct primary (LMB) + movement identity — the
## maker's "classes must feel different, not just different spells" requirement.
func _test_class_primaries() -> void:
	var hero: CharacterBody2D = _make_hero()
	# Expected LMB primary per class (default "bolt" when unset).
	var expect_primary: Array[String] = [
		"bolt", "bolt", "melee_combo", "heavy_swing", "bolt", "frost_cone", "bolt", "bolt",
		"heavy_swing",
	]
	for cls: int in range(int(hero.HeroClass.size())):
		hero.configure_class(cls)
		var prim: String = String(hero._cfg.get("primary", "bolt"))
		_expect(prim == expect_primary[cls], "class %d primary = %s (got %s)" % [cls, expect_primary[cls], prim])
	# Brawler (2): melee primary + no magic + a double-jump + an uppercut mobility.
	hero.configure_class(2)
	_expect(int(hero._max_air_jumps) == 1, "Brawler double-jumps (air_jumps 1)")
	_expect(String(hero._cfg.get("mobility2", "")) == "uppercut", "Brawler R is the uppercut")
	# Juggernaut (3): wide slow swing + a long BLOCK window.
	hero.configure_class(3)
	_expect(hero._melee_arc_dot <= 0.0, "Juggernaut swings a wide (>=180deg) arc")
	_expect(hero._parry_window_len > 0.3, "Juggernaut BLOCK has a long defensive window")
	# Cleric (4) heal-bolt + Stormcaller (6) chain-bolt flags present.
	hero.configure_class(4)
	_expect(int(hero._cfg.get("bolt_heal", 0)) > 0, "Cleric bolt lifesteals")
	hero.configure_class(6)
	_expect(int(hero._cfg.get("bolt_chain", 0)) > 0, "Stormcaller bolt chains")
	hero.queue_free()
	_completes("class_primaries")


## Each class equips its curated 4+1 kit (non-empty SpellDefs) in ROLE_ORDER —
## damage, control, answer, payoff, ult. The per-class spot checks below name the
## SLOT they expect, so a kit reshuffle fails loudly here rather than silently
## handing a class somebody else's identity. The kit's structural invariants
## (exactly 5, tiers legal, roles distinct) are pinned in slice8_test_spell_kits.
func _test_signature_loadouts() -> void:
	# EVERY class boots with a playable loadout, whether or not SpellLibrary has an
	# authored kit for it — `build_for_class` falls back to the review cycle so a new
	# class is never spell-less. (`slice8_test_spell_kits.gd` is the suite that
	# demands an AUTHORED kit per class; this one only demands a working one.)
	for cls: int in range(int(ClassInfo.count())):
		var loadout: Array = SpellLibrary.build_for_class(cls)
		_expect(not loadout.is_empty(), "class %d has a signature loadout" % cls)
		for s in loadout:
			_expect(s is SpellDef and s.display_name != "", "class %d loadout entries are named SpellDefs" % cls)
	# Brawler (2) opens on the SHOCKWAVE STOMP. It used to open on the Thunderclap — a
	# LIGHTNING lance charged into the fist, on the one class whose card reads
	# "pure-melee knockout, NO MAGIC". The anti-recolour pass moved the Thunderclap to
	# the Stormcaller, where a lightning lance belongs, and gave this class a boot
	# driven into the floor: no projectile, no corridor, a ridge that runs the ground.
	var brawler: Array = SpellLibrary.build_for_class(2)
	_expect(brawler[0].id == "shockwave_stomp", "Brawler's damage slot is the Shockwave Stomp")
	_expect(int(brawler[0].kind) == int(SpellDef.Kind.HEX), "Shockwave Stomp is an id-forked HEX")
	# ...and the class really has NO magic in its hand any more. Stated positively so
	# that "the thunderclap left" cannot be satisfied by swapping in a different bolt.
	for bs in brawler:
		_expect(int(bs.element) != int(Elements.Element.LIGHTNING),
			"the pure-MELEE class carries no lightning (%s)" % bs.id)
	_expect(brawler[SpellTier.ULT_SLOT].id == "meteor_fist",
		"Brawler's ult is the Meteor Fist, not a beam")
	# Cleric (4) finishes on Heaven's Verdict (convergence) — the LAST slot is the ult
	# slot, and the hand is three spells now rather than five.
	var cleric: Array = SpellLibrary.build_for_class(4)
	_expect(cleric[SpellTier.ULT_SLOT].id == "heavens_verdict", "Cleric's ult is Heaven's Verdict")
	# RADIANT VOLLEY replaced the rune-orb fan: a rack of PARALLEL lances where the
	# band's width is fixed and position is the damage dial, rather than a spread.
	_expect(cleric[0].id == "radiant_volley" and int(cleric[0].kind) == int(SpellDef.Kind.HEX),
		"Cleric's damage line is the Radiant Volley")
	_expect(int(cleric[0].element) == int(Elements.Element.HOLY),
		"...and it is HOLY — the Cleric is the only holy caster in the roster")
	# The AEGIS WARD, the game's only protective spell, was in NOBODY's kit. It is the
	# Cleric's carried control slot now, which is the fix to that unreachable-spell bug.
	_expect(cleric[BotIntent.SLOT_UTILITY].id == "aegis_ward",
		"Cleric's utility slot is the Aegis Ward (previously equipped by no class at all)")
	# Juggernaut (3) keeps the full earthbending kit; Rift Dagger is its one
	# off-school pick (the tank had no way to close).
	var jugg: Array = SpellLibrary.build_for_class(3)
	_expect(jugg[0].id == "boulder_hurl", "Juggernaut's damage slot is Boulder Hurl")
	_expect(int(jugg[0].element) == 5, "Boulder Hurl carries the EARTH element (Stagger)")
	# The tank CARRIES the tether (sustain — a tank's answer is not dying); the wall
	# and the pillar are the two roles it authors but leaves to the drop pool.
	# The tank now CARRIES ITS PAYOFF, not the tether. The tether is the WARLOCK's
	# damage line and was also the Cleric's sustain; three hands holding one spell is
	# the duplication the anti-recolour pass exists to delete, and a siege tank
	# erupting the floor under someone is more on-fantasy than a shadow drain.
	_expect(jugg[BotIntent.SLOT_UTILITY].id == "rock_pillar",
		"Juggernaut's utility slot is the Rock Pillar (its payoff, not a borrowed drain)")
	_expect(jugg[SpellTier.ULT_SLOT].id == "fault_line",
		"Juggernaut's ult is the Fault Line — a rupture that TRAVELS, not a fourth placed bombardment")
	var jugg_reserve: Array = SpellLibrary.reserve_for_class(3)
	var reserve_ids: Array[String] = []
	for s in jugg_reserve:
		reserve_ids.append(String(s.id))
	_expect(reserve_ids.has("rock_wall") and reserve_ids.has("drain_tether"),
		"...and the two roles it does not carry are preserved as its drop-pool reserve")
	# Cryomancer (5): the Frostpiercer BEAM is its damage line (short channel, HEAVY
	# shelf), the Ice Wall its defensive answer, and the Glacial Spine its ult.
	var cryo: Array = SpellLibrary.build_for_class(5)
	# SHATTER replaced the Frostpiercer beam (one of five classes throwing the same
	# corridor). It is the only spell in the game that combos with its OWN kit: 0.35x
	# on a warm body, 3.0x on one the class's Blizzard has already frozen.
	_expect(cryo[0].id == "shatter" and int(cryo[0].kind) == int(SpellDef.Kind.HEX),
		"Cryomancer's damage line is Shatter")
	# The ICE CONTROL caster carries the FIELD, not the wall: the field is the control
	# tool the class name is about, and the wall is a stop, which is a different job.
	_expect(cryo[BotIntent.SLOT_UTILITY].id == "blizzard",
		"Cryomancer's utility slot is the frost field (it is the ice CONTROL caster)")
	_expect(cryo[SpellTier.ULT_SLOT].id == "frozen_comet", "Cryomancer's ult is the Glacial Spine")
	# Stormcaller (6) opens on the chain leap, not a recoloured beam.
	var storm: Array = SpellLibrary.build_for_class(6)
	_expect(storm[0].id == "chain_lightning" and int(storm[0].kind) == int(SpellDef.Kind.CHAIN), "Stormcaller's damage line is Chain Lightning")
	_expect(storm[SpellTier.ULT_SLOT].id == "heavens_wrath",
		"Stormcaller's ult is Heaven's Wrath — a drifting storm CELL, not the Tempest beam")
	# It inherited the Thunderclap from the Brawler, which is where a lightning lance
	# always belonged.
	_expect(storm[BotIntent.SLOT_UTILITY].id == "thunderclap",
		"Stormcaller carries the Thunderclap (moved off the pure-melee Brawler)")
	# Arcanist (0): The Ordinary Spell is its damage line, not a once-a-fight ult —
	# the point of the rename was that the fantasy and the shelf now agree.
	var arc: Array = SpellLibrary.build_for_class(0)
	_expect(arc[0].id == "ordinary_spell" and int(arc[0].kind) == int(SpellDef.Kind.BEAM), "Arcanist's damage line is The Ordinary Spell")
	_expect(arc[SpellTier.ULT_SLOT].id == "meteor_sigil", "Arcanist's ult is the Meteor Sigil")
	# Shadowblade (1): flurry to pressure, Shadow Step as the finisher.
	var shadow: Array = SpellLibrary.build_for_class(1)
	_expect(int(shadow[0].kind) == int(SpellDef.Kind.FLURRY), "Shadowblade's damage line is the blade flurry")
	# The assassin CARRIES its payoff in the utility slot: Shadow Step is both its
	# biggest non-ult hit and its in-and-out, which is the class fantasy in one button.
	# The assassin carries the RIFT DAGGER as its get-out. Shadow Step moved to its
	# reserve: two other classes hold it, and a class's identity must not be the tool
	# three kits share.
	_expect(shadow[BotIntent.SLOT_UTILITY].id == "rift_dagger"
			and int(shadow[BotIntent.SLOT_UTILITY].kind) == int(SpellDef.Kind.THROWN_ANCHOR),
		"Shadowblade's utility slot is the Rift Dagger")
	_expect(shadow[SpellTier.ULT_SLOT].id == "thousand_cuts",
		"Shadowblade's ult is Thousand Cuts — the Umbral Lance was a violet copy of the Arcanist's beam")
	# Warlock (7): tether to sustain, Shadow Root to hold.
	var lock: Array = SpellLibrary.build_for_class(7)
	_expect(int(lock[0].kind) == int(SpellDef.Kind.TETHER), "Warlock's damage line is the drain tether")
	# RAISE THRALL is the only summon in the game — the only kit that puts a second
	# body on the floor. Shadow Root moved to the reserve (a root and a thrall are both
	# "hold them there"; the thrall is the one nobody else has).
	_expect(lock[1].id == "raise_thrall" and int(lock[1].kind) == int(SpellDef.Kind.HEX),
		"Warlock's control is Raise Thrall, the roster's only summon")
	_expect(lock[SpellTier.ULT_SLOT].id == "grave_tide", "Warlock's ult is the Grave Tide")
	# Cryomancer's control slot is the Blizzard ZONE (not a meteor).
	_expect(int(cryo[1].kind) == int(SpellDef.Kind.ZONE), "Cryomancer's control is the Blizzard field")
	# A BEAM is either a DAMAGE line (the two short-channel HEAVY beams) or an ULT,
	# and nothing in between — the rule that stopped three of the five beams being
	# unreachable. So: never in the UTILITY slot, which is every slot between the
	# damage line and the ult. With a three-button hand that is exactly slot 1, but it
	# is written as a range so the assertion survives the next control-scheme change.
	# Only classes with an AUTHORED kit are held to the slot rules — the fallback
	# cycle is the review harness, not a curated kit, and holding it to kit rules
	# would assert something nobody designed.
	for cls2: int in range(int(ClassInfo.count())):
		if SpellLibrary.kit_for_class(cls2).is_empty():
			continue
		var lo: Array = SpellLibrary.build_for_class(cls2)
		for i: int in range(1, mini(SpellTier.ULT_SLOT, lo.size())):
			_expect(int(lo[i].kind) != int(SpellDef.Kind.BEAM),
				"class %d slot %d is not a beam (got %s)" % [cls2, i, lo[i].id])
	_completes("signature_loadouts")


## ChainBolt.build_chain: target 1 must be ON the aim ray (no seek — overhaul rule
## 1); each hop is the nearest unvisited within hop range; behind-origin is skipped.
func _test_chain_geometry() -> void:
	var a := Dummy.new(); a.global_position = Vector2(120, 0)    # first target (on the line)
	var b := Dummy.new(); b.global_position = Vector2(260, 40)   # within hop of a
	var c := Dummy.new(); c.global_position = Vector2(1000, 0)   # too far for hop 2
	var behind := Dummy.new(); behind.global_position = Vector2(-200, 0)  # behind origin
	var chain_script: GDScript = load(CHAIN_PATH)
	var links: Array = chain_script.build_chain(Vector2.ZERO, Vector2.RIGHT, 560.0, 240.0, 5, [a, b, c, behind])
	_expect(links.size() == 2, "chain hits the reachable pair (a -> b), stops at the gap")
	_expect(links.size() >= 1 and links[0] == a, "first link is the target on the aim line")
	_expect(not links.has(behind), "a target behind the origin is never chained")
	_expect(not links.has(c), "a target beyond hop range is not reached")
	# NO SEEK: an enemy that is forward and close but OFF the aim corridor is missed
	# entirely — the bolt does not bend to find it, and nothing chains off a whiff.
	var off_line := Dummy.new(); off_line.global_position = Vector2(150, 300)
	var missed: Array = chain_script.build_chain(Vector2.ZERO, Vector2.RIGHT, 560.0, 240.0, 5, [off_line])
	_expect(missed.is_empty(), "an off-corridor target is never sought — the aim just misses")
	a.free(); b.free(); c.free(); behind.free(); off_line.free()
	_completes("chain_geometry")


## LightningRush.targets_on_line: only nodes whose centre lies on the segment
## within the half-width are struck (pure geometry, mirrors the beam test).
func _test_rush_line_geometry() -> void:
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
	_expect(hit.has(on_line), "a target on the lance line is struck")
	_expect(not hit.has(off_line), "a target off the line is missed")
	_expect(not hit.has(behind), "a target behind the origin is missed")
	on_line.free(); off_line.free(); behind.free()
	_completes("rush_line_geometry")


## The three appended elements map onto proven ailments: EARTH staggers (hard CC),
## HOLY burns (active DoT), WIND stuns (hard CC).
func _test_new_element_ailments() -> void:
	var holder := Node2D.new()
	root.add_child(holder)

	var earth: StatusComponent = StatusScript.new()
	holder.add_child(earth)
	earth.apply(StatusScript.EARTH)
	_expect(earth.is_hard_cc(), "EARTH applies a Stagger (hard CC / root)")

	var holy: StatusComponent = StatusScript.new()
	holder.add_child(holy)
	holy.apply(StatusScript.HOLY)
	_expect(holy.is_active() and not holy.is_hard_cc(), "HOLY applies a Radiance burn (active, not CC)")

	var wind: StatusComponent = StatusScript.new()
	holder.add_child(wind)
	wind.apply(StatusScript.WIND)
	_expect(wind.is_hard_cc(), "WIND applies a Gale stun (hard CC)")

	holder.queue_free()
	_completes("new_element_ailments")
