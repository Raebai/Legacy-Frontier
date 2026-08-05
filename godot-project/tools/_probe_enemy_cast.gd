# Run: godot --headless --path godot-project --script tools/_probe_enemy_cast.gd
# READ-ONLY DIAGNOSTIC (investigation only, delete freely).
#
# Question: can a bare `Enemy` drive `SpellCaster.cast` the way `ModMirrored` drives
# it for a Boss? Specifically:
#   1. does cast() return true with a non-Hero caster and target_group &"hero"?
#   2. does `_stamp` actually land element_id / spell_tier / caster_node / target_group?
#   3. what group does the spectacle end up scanning under friendly fire?
#   4. is the spectacle really parked at the arena origin (the documented trap)?
#   5. do the three cast() wrapper side-effects (BloodPact / SpellGrant / MirrorImage)
#      no-op safely for an enemy caster?
extends SceneTree

const ENEMY_SCRIPT_PATH: String = "res://scripts/combat/Enemy.gd"
const RigScript: GDScript = preload("res://scripts/combat/CharacterRig.gd")

var _ran: bool = false


class StubHero:
	extends Node2D
	var hits: Array[int] = []
	func take_damage(amount: int) -> void:
		hits.append(amount)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true

	var arena := Node2D.new()
	root.add_child(arena)
	var hero := StubHero.new()
	hero.add_to_group("hero")
	hero.add_to_group("mortal")
	arena.add_child(hero)
	hero.global_position = Vector2(300, 0)

	var enemy_script: GDScript = load(ENEMY_SCRIPT_PATH)
	var enemy: CharacterBody2D = enemy_script.new()
	enemy.set("archetype", 2)  # CASTER
	var rig: CharacterRig = RigScript.new()
	rig.name = "Rig"
	enemy.add_child(rig)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 20)
	shape.shape = rect
	enemy.add_child(shape)
	arena.add_child(enemy)
	enemy.global_position = Vector2.ZERO
	enemy.set_physics_process(false)

	print("--- what an Enemy DOES / DOES NOT have that SpellCaster looks for ---")
	for m: String in ["blink_to", "growth_damage_mult", "attack_group", "take_damage",
			"body_distance", "hit_margin", "head_point", "_spawn_caster_signal",
			"_emit_telegraph", "apply_knockback"]:
		print("  has_method(%s) = %s" % [m, str(enemy.has_method(m))])
	print("  in group 'mortal' = ", enemy.is_in_group("mortal"))
	print("  in group 'enemy'  = ", enemy.is_in_group("enemy"))

	print("--- friendly fire / damage group ---")
	print("  SpellCaster.friendly_fire = ", SpellCaster.friendly_fire)
	print("  damage_group(&'hero')     = ", SpellCaster.damage_group(&"hero"))

	var ids: Array[String] = ["rock_pillar", "chain_lightning", "void_zone",
		"blizzard", "rune_orbs", "boulder_hurl", "judgment", "creeping_shade",
		"ice_wall", "rock_wall", "drain_tether", "thunderclap",
		# HEX-forked (SpellCaster.HEX_SCRIPTS) — a different entry signature.
		"shockwave_stomp", "fault_line", "radiant_volley", "heavens_wrath",
		"grave_tide", "raise_thrall", "meteor_fist", "shatter"]
	for sid: String in ids:
		var spell: SpellDef = SpellLibrary.by_id(sid)
		if spell == null:
			spell = SpellLibrary.drop_by_id(sid)
		if spell == null:
			print("  %-16s MISSING FROM LIBRARY" % sid)
			continue
		var before: int = arena.get_child_count()
		var ok: bool = SpellCaster.cast(spell, arena, enemy.global_position,
			hero.global_position, Color(0.8, 0.6, 1.0), spell.effect, enemy, &"hero")
		var made: Array[Node] = []
		for i: int in range(before, arena.get_child_count()):
			made.append(arena.get_child(i))
		var line: String = "  %-16s cast=%s spawned=%d" % [sid, str(ok), made.size()]
		if not made.is_empty():
			var n: Node = made[0]
			var scr: Script = n.get_script() as Script
			line += " script=%s" % (scr.resource_path.get_file() if scr != null else "?")
			line += " tgt=%s/%s" % [str(n.get("target_group")), str(n.get("_target_group"))]
			line += " caster=%s" % ("SET" if n.get("caster_node") != null else "null")
			line += " el=%s tier=%s" % [str(n.get("element_id")), str(n.get("spell_tier"))]
			if n is Node2D:
				line += " gpos=%s" % str((n as Node2D).global_position)
		print(line)
		print("      kind=%d dmg=%d cd=%.1f cast_time=%.2f reach=%.0f radius=%.0f len=%.0f cnt=%d el=%d" % [
			spell.kind, spell.damage, spell.cooldown, spell.cast_time,
			spell.reach, spell.radius, spell.length, spell.count, spell.element])
		for n2: Node in made:
			n2.queue_free()

	print("--- SpellTier shelves ---")
	for sid2: String in ids:
		var sp: SpellDef = SpellLibrary.by_id(sid2)
		if sp != null:
			print("  %-16s tier=%d" % [sid2, SpellTier.of(sp)])

	quit(0)
	return true
