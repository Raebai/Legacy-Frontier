# Reproduction: does each class's DEFAULT (LMB primary) attack actually deal damage?
# Run: godot --headless --path godot-project --script tools/test_class_attacks.gd
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
var _ran: bool = false


class StubEnemy:
	extends Node2D
	var hp: int = 100
	func take_damage(a: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		hp -= a
	func apply_knockback(_v: Vector2) -> void:
		pass
	func apply_status(_e: int, _c: bool = true) -> void:
		pass


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	# 0 Arcanist(bolt) 1 Shadowblade(bolt) 2 Brawler(melee) 3 Juggernaut(heavy)
	# 4 Cleric(bolt) 5 Cryomancer(cone) 6 Stormcaller(bolt) 7 Warlock(bolt)
	for cls: int in range(8):
		var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
		root.add_child(hero)
		hero.configure_class(cls)
		var e := StubEnemy.new()
		e.add_to_group("enemy")
		e.global_position = hero.global_position + Vector2(38.0, 0.0)  # in front, close
		root.add_child(e)
		hero.set("_aim_dir", Vector2.RIGHT)
		hero.set("facing", Vector2.RIGHT)
		hero.call("_cast")
		# Advance the rig so a melee PUNCH fires its hit_frame synchronously (emit ->
		# _on_melee_hit_frame runs inline; no real frame needed).
		var rig: Node = hero.get_node("Rig")
		for i in 24:
			rig.call("advance", 0.02)
		# Bolt classes fire a Spell projectile synchronously in _cast (it flies later).
		var projectile_fired: bool = not get_nodes_in_group("player_spell").is_empty()
		var landed: bool = e.hp < 100
		failed += _expect(landed or projectile_fired,
			"class %d primary did SOMETHING (enemy hp=%d, projectile=%s)" % [cls, e.hp, projectile_fired])
		# For the pure-melee/cone classes (2,3,5) the hit must actually LAND (no projectile).
		if cls == 2 or cls == 3 or cls == 5:
			failed += _expect(landed, "MELEE class %d primary dealt damage (hp=%d)" % [cls, e.hp])
		hero.queue_free()
		e.queue_free()

	if failed > 0:
		printerr("Class-attack tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Class-attack tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0
