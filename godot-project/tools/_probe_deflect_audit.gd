extends SceneTree
## READ-ONLY DIAGNOSTIC. Answers three questions the static read cannot settle:
##   A. does a HERO's bolt actually reach `Hero.try_parry` (deflect path 2)?
##   B. does the press window / blade ring negate a melee-shaped hit (path 3)?
##   C. does a BEAM (a spectacle with no deflect route at all) ignore a raised guard?
## Nothing here mutates the project.

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const SPELL_PATH: String = "res://scenes/combat/Spell.tscn"
const FAR: Vector2 = Vector2(-60000.0, -60000.0)
const TICK: float = 1.0 / 60.0
const NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

var _ran: bool = false


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	print("=== DEFLECT AUDIT PROBE ===")
	_path_bolt()
	_path_beam()
	quit()
	return true


func _hero(cid: int, index: int) -> CharacterBody2D:
	var h: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(h)
	h.set_physics_process(false)
	h.global_position = FAR + Vector2(float(index) * 9000.0, 0.0)
	h.call(&"configure_class", cid)
	return h


## A brain that holds guard, so the Swordsaint's ring can actually close.
class HeldGuard extends RefCounted:
	var holding: bool = false
	func decide(_bb: Dictionary, _p: Dictionary) -> Dictionary:
		return {BotIntent.GUARD: true} if holding else {}


func _armed_hero(cid: int, index: int) -> CharacterBody2D:
	var h: CharacterBody2D = _hero(cid, index)
	var ctrl: BotController = BotController.new()
	ctrl.brain = HeldGuard.new()
	h.set(&"controller", ctrl)
	var lead: float = float((h.call(&"bot_body_state") as Dictionary).get("guard_lead", 0.0))
	(ctrl.brain as HeldGuard).holding = true
	h.call(&"_physics_process", TICK)
	for _i: int in int(round(lead / TICK)):
		h.call(&"_physics_process", TICK)
	return h


# ---------------------------------------------------------------- A + B
func _path_bolt() -> void:
	print("\n--- A: a HERO bolt meeting a raised guard (Spell -> Hero.try_parry) ---")
	print("%-12s %-6s %-9s %-9s %-9s %-8s" % ["class", "mask2", "parrying", "reflected", "hp_lost", "counted"])
	for cid: int in range(NAMES.size()):
		var victim: CharacterBody2D = _armed_hero(cid, cid)
		var attacker: CharacterBody2D = _hero(0, 40 + cid)
		SpellDeflect.reset_counts()
		var bolt: Area2D = (load(SPELL_PATH) as PackedScene).instantiate()
		root.add_child(bolt)
		bolt.global_position = victim.global_position
		bolt.set(&"caster", attacker)
		bolt.set(&"damage", 25)
		bolt.call(&"set_hostile_group", &"mortal")
		bolt.set(&"_age", 1.0)              # past REFLECT_GRACE
		var mask2: bool = (bolt.collision_mask & 2) != 0
		var parrying: bool = bool(victim.call(&"is_parrying"))
		var hp0: int = int(victim.get(&"hp"))
		bolt.call(&"_try_damage", victim)
		print("%-12s %-6s %-9s %-9s %-9d %-8d" % [
			NAMES[cid], str(mask2), str(parrying), str(bool(bolt.get(&"_reflected"))),
			hp0 - int(victim.get(&"hp")), SpellDeflect.deflect_count])
		victim.set(&"controller", null)
		if is_instance_valid(bolt):
			bolt.free()
		victim.free()
		attacker.free()


# ---------------------------------------------------------------- C
func _path_beam() -> void:
	print("\n--- C: spectacles with NO deflect route, fired at a raised guard ---")
	var cases: Array = [
		["BeamSpell", "res://scripts/combat/BeamSpell.gd"],
		["DivineRay", "res://scripts/combat/DivineRay.gd"],
		["EnergyNova", "res://scripts/combat/EnergyNova.gd"],
	]
	for c: Array in cases:
		var src: String = FileAccess.get_file_as_string(String(c[1]))
		var has_resolve: bool = src.find("SpellDeflect.resolve") >= 0
		var has_reflect: bool = src.find("func reflect(") >= 0
		print("  %-12s resolve=%s reflect=%s  -> %s" % [
			String(c[0]), str(has_resolve), str(has_reflect),
			"UNPARRYABLE" if not (has_resolve or has_reflect) else "ok"])
	# Live confirmation with the beam, which is the most-cast spectacle in the game.
	var victim: CharacterBody2D = _armed_hero(8, 70)   # Swordsaint: the guard class
	SpellDeflect.reset_counts()
	var beam: Node2D = (load("res://scripts/combat/BeamSpell.gd") as GDScript).new()
	root.add_child(beam)
	beam.set(&"target_group", "mortal")
	beam.call(&"fire", victim.global_position - Vector2(120.0, 0.0), Vector2.RIGHT,
		Color(1, 1, 1), 600.0, 40.0, 30, "arcane")
	var hp0: int = int(victim.get(&"hp"))
	var guarding: bool = bool(victim.call(&"is_parrying"))
	for _i: int in 60:
		beam.call(&"_process", TICK)
		if int(victim.get(&"hp")) != hp0:
			break
	print("  LIVE beam vs a guarding Swordsaint (is_parrying=%s): hp lost = %d, deflects counted = %d"
		% [str(guarding), hp0 - int(victim.get(&"hp")), SpellDeflect.deflect_count])
	if is_instance_valid(beam):
		beam.free()
	victim.set(&"controller", null)
	victim.free()
