# Run: godot --headless --path godot-project --script tools/slice_test_gear.gd
# Gear customization coverage: the pixel-art overlay registry (CharacterRig.EQUIP_TEX),
# the ability registry (GearAbilities), and the enemy archetype gear map must stay in
# sync — every equipped piece needs a texture that exists AND a defined ability, and
# every archetype/class weapon kind must be a real registered piece. Pure data checks
# (no tree/autoloads), so headless. Runs on first _process (autoload-safe).
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
	var equip_tex: Dictionary = rig_consts["EQUIP_TEX"]

	# Every registered pixel piece: texture exists + has a unique ability + a label.
	for kind: String in equip_tex:
		var path: String = equip_tex[kind]
		failed += _expect(ResourceLoader.exists(path), "texture exists for '%s' (%s)" % [kind, path])
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
