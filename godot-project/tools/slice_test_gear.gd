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

	# Aggregation math (mirrors Hero._aggregate_gear): staff_ice + hat + robe ->
	# element=ice, max_hp x1.12, ward=0.4, melee mults untouched.
	var agg: Dictionary = _aggregate(["staff_ice", "hat", "robe"])
	failed += _expect(String(agg["element"]) == "ice", "staff_ice sets element ice")
	failed += _expect(is_equal_approx(float(agg["max_hp"]), 1.12), "hat sets max_hp x1.12")
	failed += _expect(is_equal_approx(float(agg["ward"]), 0.4), "robe sets ward 0.4")
	failed += _expect(is_equal_approx(float(agg["melee_damage"]), 1.0), "no weapon melee change here")
	# hammer stacks melee damage + knockback.
	var agg2: Dictionary = _aggregate(["hammer"])
	failed += _expect(is_equal_approx(float(agg2["melee_damage"]), 1.2), "hammer +20% melee damage")
	failed += _expect(is_equal_approx(float(agg2["melee_knockback"]), 1.4), "hammer +40% knockback")

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
