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
	# 4 Cleric(bolt) 5 Cryomancer(shard volley) 6 Stormcaller(bolt) 7 Warlock(bolt)
	for cls: int in range(8):
		var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
		root.add_child(hero)
		hero.configure_class(cls)
		var e := StubEnemy.new()
		e.add_to_group("enemy")
		# ...and `mortal`, the shared damageable-fighter group every hero attack scans
		# now that friendly fire is on. A real `Enemy` joins both; a stub that joined only
		# `enemy` would be invisible to every hero spell and swing in the game.
		e.add_to_group(SpellCaster.MORTAL_GROUP)
		e.global_position = hero.global_position + Vector2(38.0, 0.0)  # in front, close
		root.add_child(e)
		hero.set("_aim_dir", Vector2.RIGHT)
		hero.set("facing", Vector2.RIGHT)
		hero.call("_cast")
		# Advance the rig so a melee PUNCH fires its hit_frame synchronously (emit ->
		# _on_melee_hit_frame runs inline; no real frame needed).
		#
		# ⚠ AND ADVANCE THE TELLS TOO, or a telegraphed primary never resolves here.
		# The Cryomancer's frost cone used to hit on the press frame; it now waits out
		# `Hero.ABILITY_TELL_LEAD` on a `Telegraph`, and a Telegraph is a NODE with its
		# own clock. This loop passes NO real frames — that is the whole point of the
		# synchronous style — so anything driven by frames simply never elapses. This
		# test caught exactly that and is the reason the lead is hung on a Telegraph
		# rather than on a `SceneTreeTimer`, which a test cannot step at all.
		var rig: Node = hero.get_node("Rig")
		for i in 24:
			rig.call("advance", 0.02)
			for tell: Node in get_nodes_in_group(&"telegraph"):
				if is_instance_valid(tell) and tell.has_method("advance"):
					tell.call("advance", 0.02)
		# Bolt classes fire a Spell projectile synchronously in _cast (it flies later).
		var projectile_fired: bool = not get_nodes_in_group("player_spell").is_empty()
		var landed: bool = e.hp < 100
		failed += _expect(landed or projectile_fired,
			"class %d primary did SOMETHING (enemy hp=%d, projectile=%s)" % [cls, e.hp, projectile_fired])
		# For the pure-melee classes (2, 3) the hit must actually LAND (no projectile).
		#
		# ⚠ CLASS 5 LEFT THIS SET, AND THAT IS THE CHANGE RATHER THAN A RELAXATION.
		# The Cryomancer's primary was a hitscan CONE, so it belonged here with the two
		# melee classes: nothing flew, so if the enemy's hp did not move, nothing had
		# happened. Maker: *"cryomancers left click attack the cone is weird and too big
		# just change it all shoot out some crystal ice shards or something instead"* —
		# it is a shard VOLLEY now (`Hero._primary_frost_shards`), and a projectile that
		# dealt its damage on the press frame would not be a projectile.
		#
		# It is NOT simply dropped to the weaker `landed or projectile_fired` check
		# above: that reads the `player_spell` group, which only `Spell.gd` joins, so
		# class 5 would pass it vacuously. The volley is asserted by identity instead.
		if cls == 2 or cls == 3:
			failed += _expect(landed, "MELEE class %d primary dealt damage (hp=%d)" % [cls, e.hp])
		if cls == 5:
			var volley: Node = null
			for n: Node in root.get_children():
				if n is FrostShards:
					volley = n
			failed += _expect(volley != null,
				"class 5 threw a FrostShards volley (the cone is gone; nothing can land "
				+ "on the press frame any more)")
			if volley != null:
				volley.free()   # this loop passes no frames, so queue_free never runs
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
