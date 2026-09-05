# READ-ONLY DIAGNOSTIC. Does an ABILITY that happens to play a PUNCH/KICK animation
# also land a free MELEE hit?
#
#   godot --headless --path godot-project --script tools/hero_hitframe_probe.gd
#
# `Hero._ready` connects `rig.hit_frame` -> `_on_melee_hit_frame` ONCE, and that
# handler has no gate asking whether a melee swing was actually initiated — its only
# early-out is `MeleeClash.consume_spent`. The rig emits `hit_frame` for ANY PUNCH or
# KICK one-shot. So every ability that plays one of those two states for FLAVOUR is
# also, silently, a melee swing.
#
#   _fire_punch   (Brawler Q) plays State.PUNCH
#   _uppercut     (Brawler R) plays State.KICK
#
# Neither consumes `_melee_cooldown_timer`, so neither is paying melee's cadence for
# it either. This prints what each ability actually deals against a recorder.
extends SceneTree

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"
const TICK: float = 1.0 / 60.0

var _ran: bool = false
var _tells_seen: int = 0


class Recorder:
	extends CharacterBody2D
	var hits: Array[int] = []

	func take_damage(amount: int) -> void:
		hits.append(amount)

	func apply_knockback(_v: Vector2) -> void:
		pass

	func hit_margin() -> float:
		return 0.0


## ⚠ MUST NOT RETURN TRUE. `_run` is a coroutine full of `await physics_frame`, and a
## `SceneTree._process` that returns true quits the loop on THAT frame — so the whole
## measurement was torn down before its first await resumed, and the probe printed its
## header and nothing else. `_run` calls `quit` itself when it is genuinely finished.
func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _make_hero(cls: int) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.global_position = Vector2.ZERO
	if hero.has_method("configure_class"):
		hero.call("configure_class", cls)
	hero.set("facing", Vector2.RIGHT)
	hero.set("_aim_dir", Vector2.RIGHT)
	return hero


func _make_target(at: Vector2) -> Recorder:
	var r := Recorder.new()
	root.add_child(r)
	r.global_position = at
	r.add_to_group("enemy")
	r.add_to_group(SpellCaster.MORTAL_GROUP)
	return r


## Fire `what` on a fresh hero and report every damage instance the target took over
## the next 30 frames — long enough to cover the 0.077 s hit frame plus any blast.
func _measure(cls: int, what: String) -> void:
	var hero: CharacterBody2D = _make_hero(cls)
	var target: Recorder = _make_target(Vector2(34.0, 0.0))
	await physics_frame
	target.hits.clear()
	match what:
		"uppercut":
			hero.call("_uppercut")
		"fire_punch":
			hero.call("_fire_punch")
		"frost_shards":
			hero.call("_primary_frost_shards")
		"melee":
			hero.call("_melee")
		"unsheathe":
			hero.call("_unsheathe_cut", 40)
	# ⚠ SAMPLED EVERY FRAME, not once at the end. A tell lives for its lead plus a
	# 0.15 s fade and then FREES ITSELF, so a single check after the fact would report
	# zero for a telegraph that was on screen the whole time — which would read exactly
	# like the bug this whole wave is about.
	_tells_seen = 0
	for _i: int in 30:
		await physics_frame
		var seen: Array = BotController.perceive_threats(self, target.global_position, target)
		_tells_seen = maxi(_tells_seen, seen.size())
	var total: int = 0
	for h: int in target.hits:
		total += h
	print("  %-12s class %d -> %d hit(s) %s  total %d | tells seen by the foe: %d"
		% [what, cls, target.hits.size(), str(target.hits), total, _tells_seen])
	hero.queue_free()
	target.queue_free()
	await physics_frame


func _run() -> void:
	print("=== HERO HIT-FRAME PROBE ===")
	print("  (a second hit of the class's melee damage = the ability also swung)")
	# class ids per BotBrain.CLASS_BAND ordering: 2 = BRAWLER, 5 = CRYOMANCER
	await _measure(2, "melee")
	await _measure(2, "uppercut")
	await _measure(2, "fire_punch")
	await _measure(5, "frost_shards")   # was "frost_cone" — the cone is gone
	# 8 = SWORDSAINT. Its guard-return cut also plays PUNCH for the draw.
	await _measure(8, "unsheathe")
	quit(0)
