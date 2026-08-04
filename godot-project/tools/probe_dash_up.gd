# Run headless:
#   godot --headless --path godot-project --script tools/probe_dash_up.gd
#
# CAN EVERY CLASS DASH UPWARD, AND DOES SPACE FOLLOW THE STICK?
#
# Maker: "make sure that the blink when you press space is in the direction of movement,
# not where we are facing, and that all of the classes can dash up, even the juggernaut."
#
# Two failures would each produce that complaint and they live on DIFFERENT code paths,
# which is why both are measured here rather than reasoned about:
#
#   * TRAVEL verbs (dash / charge / surge / ice_slide / ...) go through
#     `_begin_travel`, which reads the 8-way movement vector. Their old hazard was
#     `GROUNDED_VERBS`, which FLATTENED three of them to a pure horizontal.
#   * TELEPORT verbs (`lightning_blink`, `thrall_swap`) resolve inside `_start_dash`
#     and never touch `_begin_travel` at all — so a fix applied there does not reach
#     them. `_lightning_blink` read `_aim_dir` until this was measured.
#
# The hero is driven by a stub controller holding UP+RIGHT, so this asks the question
# the way a player does: the stick is up-right and nothing else is.
extends SceneTree

const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"
const CLASSES: int = 9


class Stick extends RefCounted:
	## UP+RIGHT held, aim pointing the OPPOSITE way (down-left). If a verb follows the
	## aim instead of the stick, its result comes out negative-x / positive-y and the
	## disagreement is unmissable.
	func pressed(_a: StringName) -> bool: return false
	func just_pressed(_a: StringName) -> bool: return false
	func just_released(_a: StringName) -> bool: return false
	func axis(_n: StringName, _p: StringName) -> float: return 0.0
	func vector(_a: StringName, _b: StringName, _c: StringName, _d: StringName) -> Vector2:
		return Vector2(0.707, -0.707)
	func aim_point(from: Vector2) -> Vector2: return from + Vector2(-100.0, 100.0)
	func tick(_body: Node, _clock: float) -> void: pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load(HERO_SCENE)
	print("cls  verb              dir/travel        up?   follows stick?")
	for c: int in CLASSES:
		var h: CharacterBody2D = scene.instantiate()
		root.add_child(h)
		h.set_physics_process(false)
		h.global_position = Vector2(3000.0, 3000.0)
		h.configure_class(c)
		h.controller = Stick.new()
		h.set("_aim_dir", Vector2(-0.707, 0.707))
		var verb: String = String(h.call("movement_verb_name"))
		var before: Vector2 = h.global_position
		h.call("_start_dash")
		var result: Vector2 = h.get("_dash_dir")
		# A teleport resolves instantly and never sets a travel direction — read the
		# actual displacement instead, which is the only honest answer for that path.
		if h.global_position.distance_to(before) > 1.0:
			result = (h.global_position - before).normalized()
		var up: bool = result.y < -0.2
		var stick: bool = result.x > 0.2 and result.y < -0.2
		print("%3d  %-16s  %-16s  %-4s  %s" % [
			c, verb, "(%.2f, %.2f)" % [result.x, result.y],
			"yes" if up else "NO", "yes" if stick else "NO — follows aim/facing"])
		h.queue_free()
		await process_frame
	quit(0)
