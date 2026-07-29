# Run: godot --headless --path godot-project --script tools/slice_test_summon.gd
# Phase-2 verification: every INSTANT signature routes through the epic SUMMON
# windup (spell circle + committed pose) and then ERUPTS without error, while the
# channeled (cast_time>0) spectacles still take the levitating-channel path.
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	var instant_count: int = 0
	var channel_count: int = 0
	var hero: CharacterBody2D = load(HERO_SCENE_PATH).instantiate()
	root.add_child(hero)
	hero.set_physics_process(false)
	hero.global_position = Vector2(600, 700)
	for cls: int in 8:
		# FIXTURE HYGIENE, and it is load-bearing. One hero is reconfigured through all
		# 8 classes, but a cast leaves WORLD state behind — Rift Dagger plants a thrown
		# anchor that outlives the cast. The next class holding that spell then reads an
		# anchor already in flight and takes its two-beat RECALL branch, so it never
		# starts a summon windup and the assertion fails for a reason that has nothing
		# to do with the spell under test.
		#
		# This mattered well beyond the suite: it silently constrained DESIGN. Because
		# the second kit holding Rift Dagger always failed here, the spell could only
		# ever be placed in ONE class's loadout — a data restriction invented entirely
		# by a dirty fixture. Clearing between classes is what makes the loop's
		# "one hero, 8 classes" shortcut honest.
		for anchor: Node in get_nodes_in_group("rift_anchor"):
			anchor.free()   # free(), not queue_free(): the next cast happens THIS frame
		hero.configure_class(cls)
		var sigs: Array = hero.get("_signatures")
		for i: int in sigs.size():
			var spell = sigs[i]
			# Reset per-cast state so mana + cooldown never block the cast.
			hero.set("_signature_index", i)
			hero.set("mp", float(hero.get("max_mp")))
			hero.set("_signature_cd_timer", 0.0)
			hero.set("_summoning", false)
			hero.set("_channeling", false)
			var label: String = "class %d sig %d (kind %d)" % [cls, i, int(spell.kind)]
			hero._cast_signature()
			if float(spell.cast_time) > 0.0:
				# Channeled spectacle -> the float channel, NOT the summon.
				channel_count += 1
				failed += _expect(bool(hero.get("_channeling")), "%s -> channel" % label)
				hero._end_channel()
			else:
				instant_count += 1
				failed += _expect(bool(hero.get("_summoning")), "%s -> summon windup started" % label)
				# Drive the windup to completion; it must erupt + clear without error.
				var safety: int = 0
				while bool(hero.get("_summoning")) and safety < 20:
					hero._process_summon(0.1)
					safety += 1
				failed += _expect(not bool(hero.get("_summoning")), "%s -> erupted + cleared" % label)
	print("Summon tests: %d instant, %d channeled signatures exercised" % [instant_count, channel_count])
	if failed > 0:
		printerr("Summon tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Summon tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0
