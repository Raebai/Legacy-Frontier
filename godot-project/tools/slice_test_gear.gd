# Run: godot --headless --path godot-project --script tools/slice_test_gear.gd
# Gear customization coverage: the drawable-piece registry (CharacterRig.GEAR_KINDS),
# the ability registry (GearAbilities), and the enemy archetype gear map must stay in
# sync — every equipped piece needs a defined ability, and every archetype/class weapon
# kind must be a real registered piece. Pure data checks (no tree/autoloads), so
# headless. Runs on first _process (autoload-safe).
#
# The old EQUIP_TEX pixel-overlay map this used to walk is GONE: gear is drawn
# procedurally and REPLACES the head/torso rather than being blitted over it (maker:
# "replace the torso or head etc., not be on top of them"), so there are no texture
# files left to assert the existence of. The registry it checks is now the list of
# kinds the rig can actually draw.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	var rig_consts: Dictionary = (load(RIG_PATH) as GDScript).get_script_constant_map()
	var equip_tex: Array = rig_consts["GEAR_KINDS"]

	# Every drawable piece has a unique ability + a label.
	for kind: String in equip_tex:
		failed += _expect(GearAbilities.has_ability(kind), "ability defined for '%s'" % kind)
		failed += _expect(GearAbilities.label(kind) != "", "label non-empty for '%s'" % kind)

	# Every enemy archetype's weapon kind must be a real registered piece.
	var enemy_consts: Dictionary = (load(ENEMY_PATH) as GDScript).get_script_constant_map()
	var arch_gear: Dictionary = enemy_consts["ARCHETYPE_GEAR"]
	for arch: int in arch_gear:
		var wk: String = arch_gear[arch]
		failed += _expect(equip_tex.has(wk), "archetype %d gear '%s' is registered" % [arch, wk])

	# The magic-circle aura emblem asset exists.
	failed += _expect(ResourceLoader.exists(rig_consts["AURA_CIRCLE_PATH"]), "aura magic-circle asset exists")

	# Every effect bag is well-formed: element strings are known, mults are positive,
	# ward is a 0..1 fraction. Guards against a typo silently no-op'ing an ability.
	const KNOWN_ELEMS: Array = ["arcane", "ice", "lightning", "holy", "shadow", "fire", "earth"]
	const MULT_KEYS: Array = ["melee_damage", "melee_knockback", "melee_cd", "max_hp", "speed"]
	for kind: String in equip_tex:
		var e: Dictionary = GearAbilities.effect(kind)
		if e.has("element"):
			failed += _expect(KNOWN_ELEMS.has(String(e["element"])), "known element for '%s'" % kind)
		for mk: String in MULT_KEYS:
			if e.has(mk):
				failed += _expect(float(e[mk]) > 0.0, "positive %s mult for '%s'" % [mk, kind])
		if e.has("ward"):
			failed += _expect(float(e["ward"]) >= 0.0 and float(e["ward"]) <= 1.0, "ward 0..1 for '%s'" % kind)

	# ── NO ITEM MAY STRICTLY DOMINATE ANOTHER IN THE SAME SLOT ──────────────────
	# A dominated item is not weak, it is UNPICKABLE — better on nothing, worse on
	# nothing, so no hero in no situation ever wants it. Two shipped that way
	# (`hat` under `helmet`, `sword` under `hammer`) and nothing noticed, because
	# every existing gear assertion pins individual VALUES and dominance is a
	# relation BETWEEN values.
	#
	# Compares the axes as the hero actually reads them, including direction:
	# `melee_cd` is the one axis where lower is better.
	const SLOT_ITEMS: Dictionary = {
		"weapon": ["sword", "dagger", "hammer", "greatsword"],
		"head": ["hat", "hood", "helmet"],
		"body": ["robe", "cape", "armor"],
	}
	const AXES: Array = ["melee_damage", "melee_knockback", "melee_cd", "max_hp",
		"speed", "ward", "damage_reduction"]
	const LOWER_IS_BETTER: Array = ["melee_cd"]
	for slot: String in SLOT_ITEMS:
		var items: Array = SLOT_ITEMS[slot]
		# ⚠ An invariant that is trivially true of an empty list is not an invariant.
		failed += _expect(items.size() >= 3, "slot '%s' actually has items to compare" % slot)
		for a: String in items:
			for b: String in items:
				if a == b:
					continue
				var ea: Dictionary = GearAbilities.effect(a)
				var eb: Dictionary = GearAbilities.effect(b)
				var a_better_anywhere: bool = false
				var b_better_anywhere: bool = false
				for ax: String in AXES:
					var neutral: float = 1.0 if not (ax in ["ward", "damage_reduction"]) else 0.0
					var va: float = float(ea.get(ax, neutral))
					var vb: float = float(eb.get(ax, neutral))
					if is_equal_approx(va, vb):
						continue
					var a_wins: bool = (va < vb) if LOWER_IS_BETTER.has(ax) else (va > vb)
					if a_wins:
						a_better_anywhere = true
					else:
						b_better_anywhere = true
				# `a` dominates `b` iff a is better somewhere and worse nowhere.
				failed += _expect(not (a_better_anywhere and not b_better_anywhere),
					"'%s' strictly dominates '%s' in slot '%s' — '%s' is unpickable"
						% [a, b, slot, b])

	# ── EVERY PLAYER PIECE MUST PAY SOMETHING ───────────────────────────────────
	# Maker, 2026-08-04: "please do all the stuff you need to do". The standing
	# complaint this closes is that 17 of 19 pieces beat the EMPTY slot for free, so
	# "equip something" was a checklist even after "equip WHICH" became a real choice.
	#
	# A piece that is better on some axis and worse on none is not a decision, it is
	# a chore: the correct play is always to fill the slot, and the only question left
	# is which flavour of free. Every equippable piece is now worse than nothing on at
	# least one axis the hero actually reads.
	#
	# ⚠ THE CASTER WEAPONS ARE EXEMPT, AND THAT IS NOT A LOOPHOLE. A staff grants no
	# power at all — it OVERRIDES your element, and your class already has one. So it
	# is a lateral trade (holy for ice) rather than a free gain, and there is no axis
	# on which to charge it without inventing one.
	const PAYS_NOTHING_OK: Array = ["staff", "staff_ice", "staff_storm", "staff_holy",
		"scythe", "orb", "club", "spear", "bomb", "crown"]
	var priced: int = 0
	for slot2: String in SLOT_ITEMS:
		for kind2: String in (SLOT_ITEMS[slot2] as Array):
			if PAYS_NOTHING_OK.has(kind2):
				continue
			var eff: Dictionary = GearAbilities.effect(kind2)
			var costs_something: bool = false
			for ax2: String in AXES:
				var neutral2: float = 1.0 if not (ax2 in ["ward", "damage_reduction"]) else 0.0
				var v2: float = float(eff.get(ax2, neutral2))
				if is_equal_approx(v2, neutral2):
					continue
				# Worse than the empty slot on this axis? `melee_cd` inverts.
				if (v2 > neutral2) if LOWER_IS_BETTER.has(ax2) else (v2 < neutral2):
					costs_something = true
			failed += _expect(costs_something,
				"'%s' is worse than the EMPTY slot somewhere - otherwise equipping it is a chore, not a choice" % kind2)
			priced += 1
	# ⚠ An invariant that is trivially true of an empty sweep is not an invariant.
	# Ten player-equippable pieces across the three slots.
	failed += _expect(priced == 10,
		"all ten player-equippable pieces were priced (got %d)" % priced)

	# Aggregation math (mirrors Hero._aggregate_gear): staff_ice + hat + robe ->
	# element=ice, ward=0.4, melee mults untouched — and max_hp COMPOSES.
	#
	# ⚠ THIS ASSERTION USED TO READ `max_hp == 1.12`, i.e. "the hat sets it", which
	# was only ever true because every other piece in the bag left max_hp alone. Now
	# that each piece pays a cost, the robe's -6% multiplies against the hat's +12%
	# and the honest answer is 1.0528. Asserted as a PRODUCT of the two pieces rather
	# than as a typed-in 1.0528, so re-tuning either number keeps this test true
	# without anyone having to recompute it by hand.
	var agg: Dictionary = _aggregate(["staff_ice", "hat", "robe"])
	failed += _expect(String(agg["element"]) == "ice", "staff_ice sets element ice")
	var hat_hp: float = float(GearAbilities.effect("hat").get("max_hp", 1.0))
	var robe_hp: float = float(GearAbilities.effect("robe").get("max_hp", 1.0))
	failed += _expect(is_equal_approx(float(agg["max_hp"]), hat_hp * robe_hp),
		"hat and robe COMPOSE on max_hp (%.4f x %.4f = %.4f, got %.4f)"
			% [hat_hp, robe_hp, hat_hp * robe_hp, float(agg["max_hp"])])
	failed += _expect(hat_hp * robe_hp > 1.0,
		"...and the pair is still a net gain, or the head slot would be a trap")
	failed += _expect(is_equal_approx(float(agg["ward"]), 0.4), "robe sets ward 0.4")
	failed += _expect(is_equal_approx(float(agg["melee_damage"]), 1.0), "no weapon melee change here")
	# hammer stacks melee damage + knockback.
	var agg2: Dictionary = _aggregate(["hammer"])
	failed += _expect(is_equal_approx(float(agg2["melee_damage"]), 1.2), "hammer +20% melee damage")
	failed += _expect(is_equal_approx(float(agg2["melee_knockback"]), 1.4), "hammer +40% knockback")

	# -- THE ARMOURY MENU AND THE RIG REGISTRY ARE TWO DIFFERENT LISTS ------------
	# Maker, verbatim: "Armoury - remove all of the options right now [...] add
	# placeholder cool names of stuff that we can then introduce later."
	#
	# What that split has to survive is a well-meaning tidy-up in either direction, and
	# both directions are silent failures:
	#   * A retired piece creeping back into `PLACEHOLDER_SLOTS` puts a LIVE stat bag
	#     back on the menu the maker just emptied.
	#   * A placeholder creeping into `GEAR_KINDS` puts it in the registry that OBLIGES a
	#     stat bag and the no-strict-dominance sweep, which is the wrong bar for a promise.
	#
	# /!\ THE "NO ART, SO DRAWABLE WOULD MEAN INVISIBLE" HALF OF THAT RULING IS DEAD, AND
	# THE MAKER KILLED IT: *"please make mock versions of like helmets and stuff that
	# replace the character head"*. Every worn placeholder now HAS a silhouette
	# (`CharacterRig.MOCK_HEAD` / `MOCK_BODY` / `LEG_GEAR`), so the assertion is INVERTED
	# rather than deleted — a worn piece MUST draw, or the slot claims to be filled and
	# the body says otherwise, which is the exact failure the old line was guarding.
	# `GEAR_KINDS` membership is still forbidden; drawable and registered are now two
	# different questions and `CharacterRig.draws_kind` is the one that means "visible".
	var offered: Dictionary = GearAbilities.PLACEHOLDER_SLOTS
	failed += _expect(offered.size() == 4, "the armoury offers four slots (got %d)" % offered.size())
	var placeholders: int = 0
	for slot3: String in offered:
		var list: Array = offered[slot3]
		failed += _expect(list.size() >= 3, "slot '%s' offers a real menu (got %d)" % [slot3, list.size()])
		for kind3: String in list:
			failed += _expect(GearAbilities.is_placeholder(kind3), "'%s' is flagged a placeholder" % kind3)
			failed += _expect((GearAbilities.effect(kind3) as Dictionary).is_empty(),
				"offered piece '%s' carries NO stat effect" % kind3)
			failed += _expect(not equip_tex.has(kind3),
				"placeholder '%s' is not in GEAR_KINDS - that registry obliges a live stat bag" % kind3)
			# A WORN slot must be VISIBLE; a spellement must NOT be. A spellement attaches
			# to a spell, so drawing one would put back the sticker-on-a-stickman that the
			# replacement scheme exists to remove.
			if slot3 == "weapon":
				failed += _expect(not CharacterRig.draws_kind(kind3),
					"spellement '%s' draws NOTHING on the body - it attaches to a spell" % kind3)
			else:
				failed += _expect(CharacterRig.draws_kind(kind3),
					"worn piece '%s' has a silhouette - a filled slot the body does not show is a lie" % kind3)
			placeholders += 1
	# An invariant that is trivially true of an empty sweep is not an invariant.
	failed += _expect(placeholders == 19,
		"all nineteen placeholders were swept (got %d)" % placeholders)
	# ...and the retired catalogue is off the menu, not merely re-ordered on it.
	for retired: String in ["hat", "hood", "helmet", "robe", "armor", "cape", "sword",
			"dagger", "hammer", "greatsword", "staff", "staff_ice", "staff_storm",
			"staff_holy", "scythe", "orb"]:
		for slot4: String in offered:
			failed += _expect(not (offered[slot4] as Array).has(retired),
				"retired piece '%s' is not offered in slot '%s'" % [retired, slot4])
		# ...while its ROW survives, because the rig, the enemy roster and two suites
		# that are not this one read it. Removing the rows is what would break things.
		failed += _expect(GearAbilities.has_ability(retired),
			"retired piece '%s' keeps its registry row (the rig and Enemy read it)" % retired)

	if failed > 0:
		printerr("Gear tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Gear tests: all PASS (%d pieces)" % equip_tex.size())
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## Mirror of Hero._aggregate_gear (element kept as a string here for the assertion).
func _aggregate(kinds: Array) -> Dictionary:
	var out: Dictionary = {
		"melee_damage": 1.0, "melee_knockback": 1.0, "melee_cd": 1.0,
		"max_hp": 1.0, "speed": 1.0, "ward": 0.0, "element": "",
	}
	for kind: String in kinds:
		var e: Dictionary = GearAbilities.effect(kind)
		for k: String in ["melee_damage", "melee_knockback", "melee_cd", "max_hp", "speed"]:
			if e.has(k):
				out[k] *= float(e[k])
		if e.has("ward"):
			out["ward"] = maxf(out["ward"], float(e["ward"]))
		if e.has("element"):
			out["element"] = String(e["element"])
	return out
