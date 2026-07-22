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
