# == A BASIC ATTACK MUST NOT WEAR A DEFENSIVE FLOURISH - AND DEFLECTING MUST SURVIVE ==
#
# Maker, twice: *"Don't show the deflect thing when punching with brawler. Any and
# every left-click attack, there shouldn't be a deflect thing shown ... But you can
# still keep the fact that they can deflect the attacks, just don't show that little
# white bar on a deflect"* and *"Swordsaint - remove that goofy large pink barrier
# thing as well in its left-click attack"*.
#
# THE LOAD-BEARING DISTINCTION IS VISUAL-VS-BEHAVIOUR, and it is the whole reason
# this file exists rather than a comment. "The effect is gone" and "the mechanic is
# gone" look identical from the couch, and the second one is a silent regression
# that no existing suite would catch: `slice6_test_spell_deflect` and
# `slice3_test_parry` assert that a deflect HAPPENS, and would stay green if a
# basic attack started drawing a shield again tomorrow.
#
# WHAT IS ASSERTED, in three halves:
#
#   HALF 1 - THE PRESS IS NAKED. For all nine classes, one LMB primary must arm
#            NO parry shell (`CharacterRig._parry_timer`, the literal white curved
#            band `_draw_parry_shield` paints), open NO guard (ParryRing /
#            SigilGuard), and register NO deflect. A basic attack is an offensive
#            verb; anything defensive on screen during it is unearned.
#
#   HALF 2 - THE TELL SURVIVES AS PERCEPTION, NOT AS DECORATION. The melee swing
#            tell is the ONLY thing that makes a committed swing dodgeable -
#            `BotController.perceive_threats` reads the `telegraph` group and
#            nothing else. So this pins the CONTRACT (group membership, a positive
#            `windup()`, a `danger_shape()` with real reach) while leaving the
#            DRAWING free to be cut down. Whoever removes the cone's boundary arc
#            can do it without deleting the tell by accident.
#
#   HALF 3 - THE DEFLECT COUNTER IS INDEPENDENT OF ANY DRAWING. The same deflect
#            is resolved twice: once with the swing tell alive on screen, once with
#            every tell destroyed first. Identical counts and identical damage on
#            both runs is the proof that removing a visual cannot remove the
#            mechanic - which is the exact claim the maker's "you can still keep
#            the fact that they can deflect" asks us not to break.
#
# WHAT REMAINS TO COMMUNICATE A DEFLECT once the flourish is cut, checked in
# `_test_deflect_still_reads`: `SpellDeflect.beat` is sfx (`ding` + body), a hitstop
# freeze, a camera shake/zoom, a LOCAL impact frame and a spark CONE fired down the
# exit line - none of which is a bar, a ring or a barrier. Plus, on the travelling
# half, the spell VISIBLY CHANGES DIRECTION. That is four channels of feedback
# without a single defensive-looking shape, so nothing here replaces one flourish
# with another.
#
# Run: godot --headless --path godot-project --script tools/slice_test_basic_attack_no_guard_visual.gd
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const CLASS_COUNT: int = 9
## Classes whose LMB primary is a melee swing, and therefore the ones that publish a
## swing tell at all. Named rather than derived so a class silently losing its tell
## is a FAILURE here instead of a quietly smaller loop.
const MELEE_CLASSES: Array[int] = [2, 3, 8]  # Brawler, Juggernaut, Swordsaint

const TESTS: Array[String] = [
	"press_is_naked", "tell_survives_as_perception", "deflect_is_independent",
	"deflect_still_reads",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


## The minimum a victim needs to be deflect-capable under `SpellDeflect`'s duck-typed
## contract. Deliberately NOT a Hero: this half of the suite is about the STATIC
## resolve path, and a stub cannot accidentally pass because some unrelated Hero
## field happened to be set.
class ParryingVictim:
	extends Node2D
	var hp: int = 100
	var parrying: bool = true
	var deflected_dirs: Array[Vector2] = []
	func is_parrying() -> bool:
		return parrying
	func take_damage(a: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		hp -= a
	func on_spell_deflected(dir: Vector2) -> void:
		deflected_dirs.append(dir)


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
	_test_press_is_naked()
	_test_tell_survives_as_perception()
	_test_deflect_is_independent()
	_test_deflect_still_reads()
	# VACUOUS-PASS ARMOUR (the `slice_test_spell_buttons` idiom): a test that aborted
	# half way through - because a member it reads was renamed - prints nothing and
	# would otherwise be indistinguishable from a test that passed.
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted - a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Basic-attack guard-visual tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Basic-attack guard-visual tests: all PASS")
		quit(0)
	return true


# ------------------------------------------------------- HALF 1: the press is naked
## One LMB primary on every class in the roster, and nothing defensive may appear.
##
## /!\ ALL NINE, NOT THE TWO THE MAKER NOTICED. The instruction was "check which ones
## have that", and the Brawler and the Swordsaint are simply the two that were being
## played at the time. A loop over the roster is the difference between answering the
## question and confirming the example.
func _test_press_is_naked() -> void:
	var pressed: int = 0
	for cls: int in CLASS_COUNT:
		var hero: CharacterBody2D = _spawn_hero(cls)
		var target := StubEnemy.new()
		target.add_to_group("enemy")
		target.add_to_group(SpellCaster.MORTAL_GROUP)
		target.global_position = hero.global_position + Vector2(38.0, 0.0)
		root.add_child(target)
		var rig: Node = hero.get_node("Rig")
		_expect(float(rig.get("_parry_timer")) == 0.0,
			"class %d starts with no parry shell (baseline - otherwise the reading below is noise)" % cls)
		var deflects_before: int = SpellDeflect.deflect_count
		hero.call("_cast")
		pressed += 1
		# The white curved band. `CharacterRig.set_parry` is the ONLY thing that arms
		# it and `_draw_parry_shield` early-outs on a zero timer, so this number being
		# zero IS "no white bar was drawn".
		_expect(float(rig.get("_parry_timer")) == 0.0,
			"class %d LMB armed NO parry shell (white bar) - timer=%.3f"
				% [cls, float(rig.get("_parry_timer"))])
		# No guard object opened either: a ParryRing that reports any quality, or a
		# SigilGuard magic circle summoned onto the body.
		var ring: Variant = hero.get("_guard")
		var ring_open: bool = ring != null and (ring as Object).has_method("quality") \
			and int(ring.call("quality")) != 0
		_expect(not ring_open, "class %d LMB opened no ParryRing" % cls)
		_expect(hero.get_node_or_null("SigilGuard") == null,
			"class %d LMB summoned no SigilGuard circle" % cls)
		_expect(SpellDeflect.deflect_count == deflects_before,
			"class %d LMB registered no deflect (%d -> %d)"
				% [cls, deflects_before, SpellDeflect.deflect_count])
		hero.queue_free()
		target.queue_free()
	_expect(pressed == CLASS_COUNT,
		"every class was actually pressed (%d of %d - a short loop would pass vacuously)"
			% [pressed, CLASS_COUNT])
	_completed["press_is_naked"] = true


# ------------------------------------- HALF 2: the tell is perception, not decoration
## The swing tell may lose its DRAWING; it may not lose its CONTRACT.
##
## This is the guard rail for the actual cut. `Hero._publish_swing_tell`'s own header
## records that deleting the tell would make a heavy swing invisible to every bot in
## the game, because `BotController.perceive_threats` reads the `telegraph` group and
## nothing else. So the safe removal is "stop drawing the boundary", and these
## assertions are what tells the two apart.
func _test_tell_survives_as_perception() -> void:
	var checked: int = 0
	for cls: int in MELEE_CLASSES:
		var hero: CharacterBody2D = _spawn_hero(cls)
		var before: Dictionary = _telegraph_ids()
		hero.call("_cast")
		var tell: Node = _new_telegraph(before)
		if tell == null:
			_expect(false, "melee class %d published a swing tell at all" % cls)
			hero.queue_free()
			continue
		checked += 1
		_expect(tell.is_in_group(&"telegraph"),
			"class %d swing tell joined the perception group" % cls)
		_expect(tell.has_method("danger_shape") and tell.has_method("windup"),
			"class %d swing tell publishes danger_shape + windup" % cls)
		_expect(float(tell.call("windup")) > 0.0,
			"class %d swing tell has a positive lead (%.3f s)" % [cls, float(tell.call("windup"))])
		var shape: Dictionary = tell.call("danger_shape")
		_expect(not shape.is_empty(), "class %d swing tell's danger_shape is populated" % cls)
		hero.queue_free()
		for n: Node in get_nodes_in_group(&"telegraph"):
			n.queue_free()
	_expect(checked == MELEE_CLASSES.size(),
		"all %d melee classes published a tell (%d did - a short loop would pass vacuously)"
			% [MELEE_CLASSES.size(), checked])
	_completed["tell_survives_as_perception"] = true


# ---------------------------- HALF 3: the counter does not care what is drawn
## THE BEFORE/AFTER THAT MATTERS. The same deflect, resolved twice: once with the
## swing tell alive on screen, once with every telegraph destroyed first. If the
## counts or the damage differ, then some drawing is load-bearing for the mechanic
## and cutting it would silently disarm deflecting - which is precisely the failure
## the maker asked us not to trade for.
func _test_deflect_is_independent() -> void:
	var with_tell: Dictionary = _resolve_one_deflect(false)
	var without_tell: Dictionary = _resolve_one_deflect(true)
	# PRINTED, not just asserted. The report on this change has to carry a number
	# somebody can re-run, and "all PASS" is not that number.
	print("  deflect counts | with tell drawn: +%d deflect, %d damage through (%d tells live)"
		% [int(with_tell["gained"]), int(with_tell["dealt"]), int(with_tell["tells_alive"])])
	print("                 | tells destroyed: +%d deflect, %d damage through (%d tells live)"
		% [int(without_tell["gained"]), int(without_tell["dealt"]), int(without_tell["tells_alive"])])
	_expect(int(with_tell["gained"]) == 1,
		"a parried spell counted as one deflect WITH the tell drawn (gained=%d)"
			% int(with_tell["gained"]))
	_expect(int(without_tell["gained"]) == 1,
		"a parried spell counted as one deflect WITHOUT any tell drawn (gained=%d)"
			% int(without_tell["gained"]))
	_expect(int(with_tell["gained"]) == int(without_tell["gained"]),
		"deflect COUNT is unchanged by the drawing (%d vs %d)"
			% [int(with_tell["gained"]), int(without_tell["gained"])])
	_expect(int(with_tell["dealt"]) == int(without_tell["dealt"]),
		"deflect DAMAGE is unchanged by the drawing (%d vs %d)"
			% [int(with_tell["dealt"]), int(without_tell["dealt"])])
	_expect(int(with_tell["dealt"]) == 0,
		"a clean parry still fully negates (dealt=%d)" % int(with_tell["dealt"]))
	_expect(int(with_tell["tells_alive"]) > 0,
		"the WITH-tell run really had a tell on screen (%d - otherwise both runs are the same run)"
			% int(with_tell["tells_alive"]))
	_expect(int(without_tell["tells_alive"]) == 0,
		"the WITHOUT-tell run really had none (%d)" % int(without_tell["tells_alive"]))
	_completed["deflect_is_independent"] = true


## Press a Brawler's LMB (so a swing tell exists), optionally destroy every tell, then
## resolve one deflect against a parrying victim. Returns the counter delta, the
## damage that got through, and how many tells were live at resolve time.
func _resolve_one_deflect(strip_tells: bool) -> Dictionary:
	var hero: CharacterBody2D = _spawn_hero(2)  # Brawler - the class the maker named
	hero.call("_cast")
	if strip_tells:
		for n: Node in get_nodes_in_group(&"telegraph"):
			if is_instance_valid(n):
				n.free()  # free(), not queue_free(): no frames pass in this loop
	var alive: int = 0
	for n: Node in get_nodes_in_group(&"telegraph"):
		if is_instance_valid(n):
			alive += 1
	var victim := ParryingVictim.new()
	root.add_child(victim)
	victim.global_position = Vector2(200.0, 0.0)
	var before: int = SpellDeflect.deflect_count
	var dealt: int = SpellDeflect.resolve(victim, 30, Vector2.RIGHT, victim.global_position)
	var out: Dictionary = {
		"gained": SpellDeflect.deflect_count - before,
		"dealt": dealt,
		"tells_alive": alive,
	}
	hero.queue_free()
	victim.queue_free()
	for n: Node in get_nodes_in_group(&"telegraph"):
		n.queue_free()
	return out


## WHAT STILL SAYS "you deflected that" once the flourish is gone.
##
## A deflect is meaningful information and must stay legible, so this pins the
## channels that carry it and checks that NONE of them is a drawn defensive shape:
## the victim is told (so it can strike a pose), the counter moves, the damage is
## eaten, and `SpellDeflect.beat` runs its audio + freeze + directional spark cone.
## `beat` is called for its side effects; the assertion is that it is reachable and
## does not throw with no arena present, which is the headless shape of "it fires".
func _test_deflect_still_reads() -> void:
	var victim := ParryingVictim.new()
	root.add_child(victim)
	var before: int = SpellDeflect.deflect_count
	var dealt: int = SpellDeflect.resolve(victim, 40, Vector2.RIGHT, Vector2.ZERO)
	_expect(dealt == 0, "the hit was eaten (dealt=%d)" % dealt)
	_expect(SpellDeflect.deflect_count == before + 1, "the deflect was counted")
	_expect(victim.deflected_dirs.size() == 1,
		"the victim was told which way it came, so it can still strike a pose (%d calls)"
			% victim.deflected_dirs.size())
	# The audible/kinetic half. No drawn shield anywhere in it - see this file's header.
	SpellDeflect.beat(Vector2.ZERO, Vector2.RIGHT, Color(1, 1, 1, 1))
	_expect(SpellDeflect.DEFLECTED_DAMAGE_MULT == 0.0,
		"a clean parry is still a full negate (mult=%.2f)" % SpellDeflect.DEFLECTED_DAMAGE_MULT)
	victim.queue_free()
	_completed["deflect_still_reads"] = true


# ------------------------------------------------------------------------ helpers
func _spawn_hero(cls: int) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.configure_class(cls)
	hero.set("_aim_dir", Vector2.RIGHT)
	hero.set("facing", Vector2.RIGHT)
	return hero


## Instance ids of every live telegraph, so one press's tell can be told apart from
## anything an earlier press left standing. `queue_free` never lands in this
## synchronous loop (no frames pass), so identity - not emptiness - is the only
## reliable way to scope a reading. A probe written without this reported the
## Brawler's tell as though it belonged to six other classes.
func _telegraph_ids() -> Dictionary:
	var out: Dictionary = {}
	for n: Node in get_nodes_in_group(&"telegraph"):
		if is_instance_valid(n):
			out[n.get_instance_id()] = true
	return out


func _new_telegraph(before: Dictionary) -> Node:
	for n: Node in get_nodes_in_group(&"telegraph"):
		if is_instance_valid(n) and not before.has(n.get_instance_id()):
			return n
	return null


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1
