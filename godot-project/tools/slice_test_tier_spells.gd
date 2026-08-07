# Run: godot --headless --path godot-project --script tools/slice_test_tier_spells.gd
#
# THE TEN DROP SPELLS themselves — their data shape, their dispatch wiring, and the
# arithmetic of the three that move health from outside a damage path.
#
# ⚠ NONE OF THEM CAN BE FOUND IN THE TOWER ANY MORE, and nothing in this file says
# otherwise. Maker's ruling, 2026-08-04: "you shouldn't be able to find spells in the
# tower." `SpellDrops.TOWER_SPELL_DROPS` is the switch; the CATALOGUE was deliberately
# left standing, which is why every assertion below still holds and still matters.
# What this suite proves is that the spells are WELL-FORMED and would work — not that
# a player can reach one. `tools/slice_test_drops.gd::_test_tower_finds_no_spells` is
# where the ruling itself is pinned.
#
# WHY THIS SUITE EXISTS AT ALL: the drop set introduces TWO new `SpellDef.Kind`s
# that fork on the spell's ID inside a Dictionary. A typo'd id in that table is not
# an error — `SpellCaster` falls through to `return false` and the spell silently
# does nothing, which is exactly the class of failure this repo keeps rediscovering.
# So the registry coverage is asserted rather than trusted.
#
# ⚠ THE IDIOM. Failures accumulate on the MEMBER `_fails`; every test records a
# COMPLETION SENTINEL as its last line, so an aborted test fails BY ABSENCE. Never
# `_fails += _test_x()`. See `tools/slice_test_loadout.gd`.
extends SceneTree

const HERO_SCRIPT: String = "res://scripts/combat/Hero.gd"
const ENEMY_SCRIPT: String = "res://scripts/combat/Enemy.gd"
const _StubBody: GDScript = preload("res://tools/_stub_body.gd")

const TESTS: Array[String] = [
	"drop_data_shape",
	"shelves_are_deliberate",
	"dispatch_registry_covers_every_drop",
	"roulette_rolls_only_real_workings",
	"hpwatch_moves_health_safely",
	"chronostasis_banks_and_pays",
	"equinox_levels_toward_the_mean",
	"gravity_flip_overpowers_real_gravity",
	"blood_pact_is_per_caster_and_never_stacks",
	"mirror_refuses_recursion_and_tier3",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_drop_data_shape()
	_test_shelves_are_deliberate()
	_test_dispatch_registry_covers_every_drop()
	_test_roulette_rolls_only_real_workings()
	_test_hpwatch_moves_health_safely()
	_test_chronostasis_banks_and_pays()
	_test_equinox_levels_toward_the_mean()
	_test_gravity_flip_overpowers_real_gravity()
	_test_blood_pact_is_per_caster_and_never_stacks()
	_test_mirror_refuses_recursion_and_tier3()
	for name: String in TESTS:
		if not _completed.has(name):
			_fail("test '%s' never reached its completion sentinel (it aborted)" % name)
	if _fails == 0:
		print("Tier spells tests: all PASS")
	else:
		printerr("Tier spells tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fail(what)


func _fail(what: String) -> void:
	_fails += 1
	printerr("FAIL: ", what)


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ 1. the data

func _test_drop_data_shape() -> void:
	var t2: Array = SpellLibrary.build_tier2()
	var t3: Array = SpellLibrary.build_tier3()
	# TWO. It was six, then five when `mirror_image` was promoted into the Arcanist's
	# control slot, and it is two now because the FOURTH spell slot promoted three more
	# — Petrify to the Brawler, Gravity Flip to the Juggernaut, Blood Pact to the
	# Swordsaint. `build_tier2()` is the authored SIGNATURE band (the loud floor events),
	# and every invariant in this suite is a claim about those, not about every spell a
	# floor can produce (that pool is this plus `SpellDrops._common_pool()`).
	#
	# ⚠ THE NUMBER IS PINNED SO SHRINKING IT AGAIN IS A DECISION. Each promotion is
	# defensible on its own and the floor pool has quietly gone from six loud events to
	# two; a seventh class wanting a fourth slot filled from here should have to come
	# through this line.
	_expect(t2.size() == 2, "two Tier 2 signature spells (got %d)" % t2.size())
	# 4 -> 9: every class now has its OWN boss drop. See SpellLibrary.build_tier3().
	_expect(t3.size() == 9, "nine Tier 3 spells, one per class (got %d)" % t3.size())
	# Fresh instances every call. A shared Resource between two heroes is how a
	# Blood Pact buff would end up permanent on somebody else's spell.
	_expect(SpellLibrary.build_tier2()[0] != t2[0], "build_tier2 mints fresh instances")
	for s: SpellDef in t2:
		_expect(s.charges == -1, "'%s' (Tier 2) has unlimited charges" % s.id)
		_expect(s.description.length() > 40, "'%s' has a real description" % s.id)
	for s: SpellDef in t3:
		_expect(s.charges >= 1 and s.charges <= 2,
			"'%s' (Tier 3) carries 1-2 charges (got %d)" % [s.id, s.charges])
		_expect(s.kind == SpellDef.Kind.CATACLYSM, "'%s' is a CATACLYSM" % s.id)
	# The element/effect invariant, restated here rather than left to the kit suite:
	# a drop is never in a kit, so nothing else in the repo iterates it directly.
	for s: SpellDef in (t2 + t3):
		_expect(s.element >= 0, "'%s' declares a real element" % s.id)
		_expect(s.effect == Elements.effect_name(s.element),
			"'%s': effect '%s' matches its element" % [s.id, s.effect])
		_expect(SpellLibrary.drop_by_id(s.id) != null, "'%s' is reachable by id" % s.id)
	_expect(SpellLibrary.drop_by_id("no_such_spell") == null, "an unknown id resolves to null")
	# REUSE, NOT REBUILD: the spec's Chain Lightning and Meteor ride the existing
	# spectacles. If either grew its own Kind, this is where that would be caught.
	var by: Dictionary = {}
	for s: SpellDef in t2:
		by[s.id] = s
	_expect(by["arc_of_fools"].kind == SpellDef.Kind.CHAIN,
		"Arc of Fools reuses the CHAIN spectacle")
	_expect(by["meteor_storm"].kind == SpellDef.Kind.METEOR,
		"Meteor Storm reuses the METEOR spectacle")
	_completes("drop_data_shape")


## Shelf IS clash weight (`SpellTier.of` doubles as `reaction_weight`), so these
## assertions are balance statements and not bookkeeping: a Tier 3 must outweigh
## everything, and a Tier 2 must NOT be a free clash win.
func _test_shelves_are_deliberate() -> void:
	for s: SpellDef in SpellLibrary.build_tier3():
		_expect(SpellTier.of(s) == SpellTier.Tier.ULT,
			"'%s' is ULT-shelf, so a boss drop wins its clashes" % s.id)
	for s: SpellDef in SpellLibrary.build_tier2():
		_expect(SpellTier.of(s) != SpellTier.Tier.QUICK,
			"'%s' is not a QUICK spell — a floor pickup commits you" % s.id)
	# Meteor Storm is the deliberate ULT among the Tier 2s (a 1.2 s channelled
	# bombardment is an ult by every axis the derivation reads).
	var storm: SpellDef = SpellLibrary.drop_by_id("meteor_storm")
	_expect(SpellTier.of(storm) == SpellTier.Tier.ULT,
		"Meteor Storm is honestly ULT-shelf rather than pretending to be a HEAVY")
	# ...and it is the ONLY one, or the "Tier 2 loses to a class ult" rule is dead.
	var ults: int = 0
	for s: SpellDef in SpellLibrary.build_tier2():
		if SpellTier.of(s) == SpellTier.Tier.ULT:
			ults += 1
	_expect(ults <= 2, "at most two Tier 2 spells sit on the ULT shelf (got %d)" % ults)
	# Every drop has a real telegraph. The spec's rule for big spells is an
	# "unmistakable wind-up"; a zero cast time is no wind-up at all.
	for s: SpellDef in (SpellLibrary.build_tier2() + SpellLibrary.build_tier3()):
		_expect(s.cast_time >= 0.35,
			"'%s' has a visible wind-up (cast_time %.2f)" % [s.id, s.cast_time])
	_completes("shelves_are_deliberate")


# -------------------------------------------------------------- 2. the dispatch

## THE SILENT-NO-OP GUARD. A drop whose id is missing from its registry falls
## through `SpellCaster`'s `_:` arm and does nothing, with no error anywhere.
func _test_dispatch_registry_covers_every_drop() -> void:
	for s: SpellDef in SpellLibrary.build_tier2():
		if s.kind != SpellDef.Kind.HEX:
			continue
		var p: String = String(SpellCaster.HEX_SCRIPTS.get(s.id, ""))
		_expect(p != "", "HEX '%s' has a dispatch entry" % s.id)
		_expect(ResourceLoader.exists(p), "HEX '%s' points at a real script (%s)" % [s.id, p])
		var scr: GDScript = load(p) as GDScript
		_expect(scr != null and _declares_method(scr, "hex"),
			"HEX '%s' implements hex()" % s.id)
	for s: SpellDef in SpellLibrary.build_tier3():
		if s.id == "roulette":
			_expect(not SpellCaster.CATACLYSM_SCRIPTS.has("roulette"),
				"Roulette has no spectacle of its own — it re-enters the dispatcher")
			continue
		var p2: String = String(SpellCaster.CATACLYSM_SCRIPTS.get(s.id, ""))
		_expect(p2 != "", "CATACLYSM '%s' has a dispatch entry" % s.id)
		_expect(ResourceLoader.exists(p2), "CATACLYSM '%s' points at a real script" % s.id)
		var scr2: GDScript = load(p2) as GDScript
		_expect(scr2 != null and _declares_method(scr2, "cataclysm"),
			"CATACLYSM '%s' implements cataclysm()" % s.id)
	# ...and nothing in a registry that is not a real spell, which would be an entry
	# nobody can ever reach.
	#
	# ⚠ THIS USED TO SAY "IS NOT A DROP" AND CANNOT ANY MORE, because `Kind.HEX`
	# stopped meaning "Tier 2 floor pickup". The anti-recolour pass put ELEVEN CLASS
	# SIGNATURES on that arm — one new `SpellDef.Kind` each would have been ~55 silent
	# defaults across five files that fall through rather than erroring — so the
	# registry is now mostly kit spells. The invariant that actually matters is
	# unchanged and is the one being asserted: every registry key resolves to a real
	# SpellDef somewhere in the tree. It is only the LOOKUP that widened, from the drop
	# table to the whole library, because the set being described genuinely grew.
	for id: Variant in SpellCaster.HEX_SCRIPTS.keys():
		_expect(SpellLibrary.by_id(String(id)) != null,
			"HEX registry entry '%s' is a real spell" % id)
	for id2: Variant in SpellCaster.CATACLYSM_SCRIPTS.keys():
		_expect(SpellLibrary.by_id(String(id2)) != null,
			"CATACLYSM registry entry '%s' is a real spell" % id2)
	# The CATACLYSM half is still drops-only, and saying so keeps the widening above
	# from quietly becoming a licence for boss drops to leak into kits.
	for id3: Variant in SpellCaster.CATACLYSM_SCRIPTS.keys():
		_expect(SpellLibrary.drop_by_id(String(id3)) != null,
			"CATACLYSM registry entry '%s' is still a Tier 3 DROP" % id3)
	# ...and the eleven signatures really are on the HEX arm, asserted positively so
	# the loop above cannot pass by describing an empty or shrunken registry.
	for sig: String in ["thousand_cuts", "iai_slash", "crescent_step", "shockwave_stomp",
			"meteor_fist", "radiant_volley", "shatter", "heavens_wrath", "fault_line",
			"raise_thrall", "grave_tide"]:
		_expect(SpellCaster.HEX_SCRIPTS.has(sig),
			"class signature '%s' has a HEX dispatch entry" % sig)
	# THE STAMP CONTRACT. `set()` on an undeclared property is a silent no-op, so a
	# spectacle that does not DECLARE these is a spectacle `SpellCaster._stamp`
	# writes nothing to — unowned, inert in the whole reaction system, and silent.
	var required: Array[String] = ["element_id", "spell_tier", "caster_node",
		"target_group", "_target_group"]
	var all_paths: Array = SpellCaster.HEX_SCRIPTS.values() + SpellCaster.CATACLYSM_SCRIPTS.values()
	for path: Variant in all_paths:
		var src: String = FileAccess.get_file_as_string(String(path))
		for prop: String in required:
			_expect(src.contains("var %s" % prop),
				"%s DECLARES `%s` (an unstamped spectacle is silently inert)" % [path, prop])
	_completes("dispatch_registry_covers_every_drop")


## Roulette must only ever roll workings that exist, or a quarter of its casts are
## an expensive nothing.
func _test_roulette_rolls_only_real_workings() -> void:
	_expect(SpellCaster.ROULETTE_POOL.size() >= 2, "Roulette has something to choose between")
	for id: String in SpellCaster.ROULETTE_POOL:
		var s: SpellDef = SpellLibrary.drop_by_id(id)
		_expect(s != null, "Roulette's '%s' is a real spell" % id)
		if s == null:
			continue
		_expect(s.kind == SpellDef.Kind.CATACLYSM, "Roulette only rolls Tier 3 ('%s')" % id)
		_expect(SpellCaster.CATACLYSM_SCRIPTS.has(id),
			"Roulette's '%s' has a spectacle to build" % id)
		_expect(id != "roulette", "Roulette cannot roll itself")
	_expect(SpellCaster.ROULETTE_SELF_CHANCE > 0.0 and SpellCaster.ROULETTE_SELF_CHANCE < 0.6,
		"Roulette's self-cast chance is a real risk but not a coin flip (%.2f)"
			% SpellCaster.ROULETTE_SELF_CHANCE)
	_completes("roulette_rolls_only_real_workings")


# ------------------------------------------------------------ 3. the arithmetic

func _test_hpwatch_moves_health_safely() -> void:
	var b: Node2D = _StubBody.new()
	root.add_child(b)
	b.hp = 40
	_expect(HpWatch.hp_of(b) == 40, "hp is read")
	_expect(HpWatch.max_hp_of(b) == 100, "max hp is read")
	_expect(is_equal_approx(HpWatch.fraction_of(b), 0.4), "fraction is hp/max")
	_expect(HpWatch.is_alive(b), "a body above zero is alive")
	# THE FLOOR OF 1. A restore that could write 0 would leave a body at zero health
	# that never ran its death path — a corpse still walking around.
	HpWatch.restore(b, 0)
	_expect(b.hp == 1, "restore can never write zero (got %d)" % b.hp)
	HpWatch.restore(b, 9999)
	_expect(b.hp == 100, "restore clamps to max")
	b.hp = 90
	HpWatch.gain(b, 50)
	_expect(b.hp == 100, "gain clamps to max")
	HpWatch.gain(b, -10)
	_expect(b.hp == 100, "gain never lowers")
	# A body with no health at all contributes nothing rather than reading as full.
	var plain := Node2D.new()
	root.add_child(plain)
	_expect(HpWatch.hp_of(plain) == -1, "a body with no hp reports -1, not 0")
	_expect(HpWatch.fraction_of(plain) < 0.0, "...and no fraction")
	_expect(not HpWatch.is_alive(plain), "...and is not a target")
	_expect(not HpWatch.is_alive(null), "null is not alive")
	b.free()
	plain.free()
	_completes("hpwatch_moves_health_safely")


## The banking, on the real `_hold` loop rather than on a re-implementation of it.
func _test_chronostasis_banks_and_pays() -> void:
	var stasis: Node2D = (load("res://scripts/combat/Chronostasis.gd") as GDScript).new()
	root.add_child(stasis)
	var victim: Node2D = _StubBody.new()
	root.add_child(victim)
	victim.hp = 100
	victim.global_position = Vector2(50.0, 50.0)
	# TYPED on purpose. `_held` is an `Array[Dictionary]`, and assigning a plain
	# `Array` through `set()` is REFUSED silently in Godot 4 — the property keeps its
	# old empty value and every assertion below would then be measuring nothing.
	var rows: Array[Dictionary] = [{"node": victim, "pos": Vector2(50.0, 50.0),
		"hp": 100, "banked": 0}]
	stasis.set("_held", rows)
	_expect((stasis.get("_held") as Array).size() == 1,
		"the fixture actually landed on the spectacle (typed-array assignment)")
	# Something hits the frozen body for 30.
	victim.take_damage(30)
	_expect(victim.hp == 70, "the hit landed before the freeze noticed")
	stasis.call("_hold")
	_expect(victim.hp == 100, "the freeze GAVE IT BACK — nothing lands while time is stopped")
	_expect(stasis.call("banked_total") == 30, "...and banked it (got %d)"
		% stasis.call("banked_total"))
	# A second hit accumulates rather than replacing.
	victim.take_damage(25)
	stasis.call("_hold")
	_expect(victim.hp == 100, "the second hit is swallowed too")
	_expect(stasis.call("banked_total") == 55, "the ledger accumulates (got %d)"
		% stasis.call("banked_total"))
	# THE PIN. A frozen body does not move and does not carry velocity.
	victim.global_position = Vector2(400.0, 400.0)
	victim.velocity = Vector2(300.0, -300.0)
	stasis.call("_hold")
	_expect(victim.global_position.is_equal_approx(Vector2(50.0, 50.0)),
		"a frozen body is pinned where it was caught")
	_expect(victim.velocity == Vector2.ZERO, "...with no velocity to carry out of the freeze")
	# A HEAL during the freeze must not be banked as damage.
	victim.hp = 100
	stasis.call("_hold")
	_expect(stasis.call("banked_total") == 55, "healing is not banked as damage")
	stasis.free()
	victim.free()
	_completes("chronostasis_banks_and_pays")


## Equinox's arithmetic. Fractions, not absolute HP — see the file header for why
## levelling raw HP would give the spell exactly one outcome every time.
func _test_equinox_levels_toward_the_mean() -> void:
	_expect(is_equal_approx(Equinox.mean_fraction(1.0 + 0.2, 2), 0.6),
		"the mean of 100%% and 20%% is 60%%")
	_expect(is_equal_approx(Equinox.mean_fraction(0.0, 0), 0.0),
		"no participants means no mean rather than a divide by zero")
	_expect(Equinox.target_hp(0.6, 100) == 60, "60%% of a 100 HP hero is 60")
	_expect(Equinox.target_hp(0.6, 2000) == 1200, "...and of a 2000 HP guardian, 1200")
	# THE FLOOR OF 1: the levelling can never itself be the kill.
	_expect(Equinox.target_hp(0.0, 100) == 1, "a zero mean still leaves 1 HP")
	_expect(Equinox.target_hp(-5.0, 100) == 1, "a nonsense mean cannot go below 1")
	_expect(Equinox.target_hp(5.0, 100) == 100, "...or above max")
	_expect(Equinox.target_hp(0.5, 0) == 0, "a body with no max HP is not levelled")
	# THE DESIGN CLAIM, stated as a test: a healthy body LOSES and a dying one GAINS.
	# That is the whole reason it is a decision and not a heal.
	var mean: float = Equinox.mean_fraction(1.0 + 0.1, 2)
	_expect(Equinox.target_hp(mean, 100) < 100, "the healthy body pays")
	_expect(Equinox.target_hp(mean, 100) > 10, "the dying body gains")
	_completes("equinox_levels_toward_the_mean")


## GRAVITY FLIP is tuned against constants that live in files this agent does not
## own. If either gravity grows past `LIFT`, the spell silently becomes a hover —
## so the relationship is pinned here rather than left to be discovered in play.
func _test_gravity_flip_overpowers_real_gravity() -> void:
	var hero_g: float = _script_const(HERO_SCRIPT, "GRAVITY_FALL", 2100.0)
	var enemy_g: float = _script_const(ENEMY_SCRIPT, "GRAVITY", 1500.0)
	_expect(GravityFlip.LIFT > hero_g,
		"LIFT (%.0f) beats Hero.GRAVITY_FALL (%.0f)" % [GravityFlip.LIFT, hero_g])
	_expect(GravityFlip.LIFT > enemy_g,
		"LIFT (%.0f) beats Enemy.GRAVITY (%.0f)" % [GravityFlip.LIFT, enemy_g])
	_expect(GravityFlip.LIFT - hero_g > 600.0,
		"the NET rise is decisive, not a drift (net %.0f)" % (GravityFlip.LIFT - hero_g))
	# The lift itself, on the real loop.
	var flip: Node2D = (load("res://scripts/combat/GravityFlip.gd") as GDScript).new()
	root.add_child(flip)
	flip.set("target_group", "mortal_test")
	var body: Node2D = _StubBody.new()
	root.add_child(body)
	body.add_to_group("mortal_test")
	body.velocity = Vector2(0.0, 400.0)   # falling
	flip.call("_lift_everyone", 1.0 / 60.0)
	_expect(body.velocity.y < 400.0, "a falling body is decelerated (%.1f)" % body.velocity.y)
	for i: int in 60:
		flip.call("_lift_everyone", 1.0 / 60.0)
	_expect(body.velocity.y < 0.0, "...and is soon RISING (%.1f)" % body.velocity.y)
	_expect(body.velocity.y >= -GravityFlip.MAX_RISE - 1.0,
		"the rise is clamped so nobody leaves the camera (%.1f)" % body.velocity.y)
	# A body with no velocity property is skipped rather than erroring.
	var plain := Node2D.new()
	root.add_child(plain)
	plain.add_to_group("mortal_test")
	flip.call("_lift_everyone", 1.0 / 60.0)

	# ══ THE RADIUS EXISTS, AND EVERYTHING ABOVE THIS LINE WAS BLIND TO IT ═════════
	# ⚠ EVERY ASSERTION ABOVE PASSES VACUOUSLY ON THE QUESTION OF REACH. `_StubBody`
	# sits at (0,0) and a bare `GravityFlip.new()` has `_anchor` (0,0), so the distance
	# is 0 — inside ANY radius, at any hysteresis, forever. When this spell had no edge
	# that was fine; now that it does, the old test would go on printing PASS against a
	# well that still lifted the entire room. This is the assertion that catches that,
	# and it is the whole reason the 2026-08-05 reversal is testable at all.
	var out: Node2D = _StubBody.new()
	root.add_child(out)
	out.add_to_group("mortal_test")
	out.global_position = Vector2(flip.get("_radius") + 140.0, 0.0)
	out.velocity = Vector2(0.0, 400.0)   # falling, well outside the rim
	for i2: int in 10:
		flip.call("_lift_everyone", 1.0 / 60.0)
	_expect(is_equal_approx(out.velocity.y, 400.0),
		"a body OUTSIDE the well is untouched (%.1f, expected 400)" % out.velocity.y)

	# ...and the HYSTERESIS: caught at `_radius`, released only past `EXIT_MARGIN`, so a
	# body pacing the rim cannot flicker between ground- and air-grade steering once a
	# frame. A single-threshold implementation fails the second half of this.
	var rim: Node2D = _StubBody.new()
	root.add_child(rim)
	rim.add_to_group("mortal_test")
	rim.global_position = Vector2(float(flip.get("_radius")) - 1.0, 0.0)
	rim.velocity = Vector2(0.0, 400.0)
	flip.call("_lift_everyone", 1.0 / 60.0)
	_expect(rim.velocity.y < 400.0, "a body just inside the rim IS caught")
	rim.global_position = Vector2(float(flip.get("_radius")) + GravityFlip.EXIT_MARGIN * 0.5, 0.0)
	rim.velocity = Vector2(0.0, 400.0)
	flip.call("_lift_everyone", 1.0 / 60.0)
	_expect(rim.velocity.y < 400.0,
		"...and is STILL held inside the exit margin (%.1f)" % rim.velocity.y)
	rim.global_position = Vector2(float(flip.get("_radius")) + GravityFlip.EXIT_MARGIN + 8.0, 0.0)
	rim.velocity = Vector2(0.0, 400.0)
	flip.call("_lift_everyone", 1.0 / 60.0)
	_expect(is_equal_approx(rim.velocity.y, 400.0),
		"...and is RELEASED past it (%.1f, expected 400)" % rim.velocity.y)

	# THE BILL SCALES, and the free rung is real. `COLLAPSE_FLOOR` is the whole skill
	# expression — a body that spent the five seconds getting low pays nothing.
	var hurt: Node2D = _StubBody.new()
	root.add_child(hurt)
	flip.set("_damage", 100)
	flip.call("_land", hurt, GravityFlip.COLLAPSE_FLOOR - 10.0)
	_expect(hurt.damage_log.is_empty(), "a short drop costs nothing (the free rung)")
	flip.call("_land", hurt, GravityFlip.CEILING_LIFT)
	_expect(hurt.damage_log.size() == 1 and int(hurt.damage_log[0]) == 100,
		"a full-height drop bills the whole authored damage (%s)" % str(hurt.damage_log))

	flip.free()
	body.free()
	plain.free()
	out.free()
	rim.free()
	hurt.free()
	_completes("gravity_flip_overpowers_real_gravity")


## The pact buffs its OWN caster's spells and nobody else's, and two pacts on one
## body do not stack.
func _test_blood_pact_is_per_caster_and_never_stacks() -> void:
	var a := Node2D.new()
	var b := Node2D.new()
	root.add_child(a)
	root.add_child(b)
	_expect(is_equal_approx(BloodPact.multiplier_for(a, a), 1.0),
		"no pact means no multiplier")
	var pact: Node2D = (load("res://scripts/combat/BloodPact.gd") as GDScript).new()
	root.add_child(pact)
	pact.set("caster_node", a)
	pact.set("_mult", 1.75)
	pact.add_to_group(BloodPact.PACT_GROUP)
	_expect(is_equal_approx(BloodPact.multiplier_for(a, a), 1.75), "the pact's owner is buffed")
	_expect(is_equal_approx(BloodPact.multiplier_for(b, b), 1.0),
		"...and their teammate is NOT")
	var pact2: Node2D = (load("res://scripts/combat/BloodPact.gd") as GDScript).new()
	root.add_child(pact2)
	pact2.set("caster_node", a)
	pact2.set("_mult", 1.5)
	pact2.add_to_group(BloodPact.PACT_GROUP)
	_expect(is_equal_approx(BloodPact.multiplier_for(a, a), 1.75),
		"two pacts do NOT stack — the largest wins")
	_expect(is_equal_approx(BloodPact.multiplier_for(null, a), 1.0), "a null caster is unbuffed")
	pact.free()
	pact2.free()
	a.free()
	b.free()
	_completes("blood_pact_is_per_caster_and_never_stacks")


## The clone must refuse two things: itself (a clone that summons clones is an
## allocation bug) and Tier 3 (echoing a one-charge boss drop would double it for
## free, because charges are spent by the HERO at the dispatcher).
func _test_mirror_refuses_recursion_and_tier3() -> void:
	_expect(MirrorImage.MUTE_IDS.has("mirror_image"), "the clone will not summon clones")
	var owner_node := Node2D.new()
	root.add_child(owner_node)
	var clone: Node2D = (load("res://scripts/combat/MirrorImage.gd") as GDScript).new()
	root.add_child(clone)
	clone.set("caster_node", owner_node)
	# `by_id`, not `drop_by_id`: Mirror Image is the Arcanist's control slot now, not
	# a drop, so the drop table correctly answers null for it.
	MirrorImage.echo(owner_node, SpellLibrary.by_id("mirror_image"),
		Vector2.ZERO, Color.WHITE, "arcane", clone)
	_expect((clone.get("_pending") as Array).is_empty(), "a mirrored Mirror Image is dropped")
	MirrorImage.echo(owner_node, SpellLibrary.drop_by_id("the_void"),
		Vector2.ZERO, Color.WHITE, "shadow", clone)
	_expect((clone.get("_pending") as Array).is_empty(), "a mirrored Tier 3 is dropped")
	# ...and an ordinary spell IS queued, or the mute list has eaten everything.
	MirrorImage.echo(owner_node, SpellLibrary.drop_by_id("arc_of_fools"),
		Vector2.ZERO, Color.WHITE, "lightning", clone)
	_expect((clone.get("_pending") as Array).size() == 1,
		"an ordinary spell IS repeated (got %d queued)" % (clone.get("_pending") as Array).size())
	# A clone owned by somebody else does not hear your casts.
	var stranger := Node2D.new()
	root.add_child(stranger)
	MirrorImage.echo(stranger, SpellLibrary.drop_by_id("arc_of_fools"),
		Vector2.ZERO, Color.WHITE, "lightning", clone)
	_expect((clone.get("_pending") as Array).size() == 1,
		"a clone only repeats ITS OWN owner")
	clone.free()
	owner_node.free()
	stranger.free()
	_completes("mirror_refuses_recursion_and_tier3")


# -------------------------------------------------------------------- helpers

## Does `scr` declare `method`? `has_method` needs an instance and these scripts
## reach autoloads on construction, so the script's own method list is asked instead.
func _declares_method(scr: GDScript, method: String) -> bool:
	for m: Dictionary in scr.get_script_method_list():
		if String(m.get("name", "")) == method:
			return true
	return false


## A constant out of a script that has no `class_name` (Hero.gd and Enemy.gd both
## lack one, so `Hero.GRAVITY_FALL` will not compile from here).
func _script_const(path: String, name: String, fallback: float) -> float:
	var scr: GDScript = load(path) as GDScript
	if scr == null:
		return fallback
	var consts: Dictionary = scr.get_script_constant_map()
	return float(consts.get(name, fallback))
