class_name LocalCoop
extends Node
## SAME-SCREEN CO-OP: press a button on a pad, a climber walks in.
##
## Maker: *"one on keyboard for example one on controller or both on controller"*.
##
## ⚠ NO LOBBY, NO MENU, NO DEVICE-ASSIGNMENT SCREEN. Couch co-op is a social act — the
## second person picks up a pad because they are already sitting there — and a join
## screen puts a form between them and the game. So the pad IS the join: press A or
## START on any pad nobody is holding and you are in, mid-floor, no pause.
##
## ⚠ WHY A PAD CAN TAKE OVER PLAYER ONE. `Arena` always spawns a keyboard hero, which is
## correct for a game that is solo by default — but it means "both of us on pads" would
## otherwise leave an idle keyboard climber standing in the room being counted by the
## floor. So the FIRST pad to join adopts the existing keyboard hero, and only if the
## keyboard has actually been used since this arena loaded does it spawn a body of its
## own instead. "Whoever picked up a pad first is player one" is a rule people already
## expect; it needs no UI and it cannot be got wrong by accident.
##
## ⚠ WHAT THIS DOES NOT DO YET, said out loud rather than discovered in play:
##   * P2 takes the class already selected in the hub — there is no per-player pick.
##     They can change it in-game with `switch_class` (BACK on the pad), which is a
##     workaround and not the feature.
##   * Nothing here is PLAYTESTED. Two pads have never been held in front of this.
##
## Closed since the first slice: player two now has their own ability bar, pinned to
## their own climber and docked to the opposite corner (`_build_bar_for`), and either
## player can revive the other — `Revive` reads the rescuer's OWN controller instead of
## the shared global `Input`, and picks the closest rescuer/ghost PAIR rather than
## whichever body happened to be first in the group.

## Ceiling on bodies. The maker asked about 4P; the floor scaling in
## `Encounter.party_size` is already written for any count, so this is the only line
## that would have to move.
const MAX_PLAYERS: int = 4

## Buttons that mean "I am here". A on an Xbox pad, START for anyone whose muscle memory
## says a join is a START.
const JOIN_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_START]

## How far apart a joining climber lands from the last one, so nobody spawns inside
## somebody else's collider.
const SPAWN_STEP: Vector2 = Vector2(60.0, 0.0)

signal player_joined(device: int, hero: Node)

var heroes_root: Node = null
var spawn_origin: Vector2 = Vector2.ZERO

var _claimed: Dictionary = {}          ## device id -> true
var _keyboard_seen: bool = false
var _p1_adopted: bool = false


func setup(root: Node, origin: Vector2) -> void:
	heroes_root = root
	spawn_origin = origin


func _process(_delta: float) -> void:
	if not _keyboard_seen and _keyboard_active():
		_keyboard_seen = true
	for device: int in Input.get_connected_joypads():
		if _claimed.has(device):
			continue
		if _join_pressed(device):
			_join(device)


## Has the person on the keyboard actually played? Only the movement keys count — a
## stray F11 or a pause is not "I am the keyboard player".
func _keyboard_active() -> bool:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"jump", &"cast"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


func _join_pressed(device: int) -> bool:
	for b: int in JOIN_BUTTONS:
		if Input.is_joy_button_pressed(device, b):
			return true
	return false


func _join(device: int) -> void:
	_claimed[device] = true
	var pad := PadController.new(device)

	# THE ADOPTION CASE: nobody has touched the keyboard, so this pad is player one and
	# the hero already standing in the room becomes theirs. No second body, no idle
	# climber inflating the floor.
	if not _p1_adopted and not _keyboard_seen:
		var existing: Node = _first_undriven_hero()
		if existing != null:
			_p1_adopted = true
			existing.set(&"controller", pad)
			player_joined.emit(device, existing)
			print("[local-coop] pad %d took over player 1" % device)
			return

	if _player_count() >= MAX_PLAYERS:
		return
	var hero: Node = _spawn_hero(pad)
	if hero != null:
		player_joined.emit(device, hero)
		print("[local-coop] pad %d joined as player %d" % [device, _player_count()])


func _first_undriven_hero() -> Node:
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if is_instance_valid(h) and h.get(&"controller") == null:
			return h
	return null


func _player_count() -> int:
	return get_tree().get_nodes_in_group("hero").size()


func _spawn_hero(pad: PadController) -> Node:
	if heroes_root == null or not is_instance_valid(heroes_root):
		return null
	var scene: PackedScene = load("res://scenes/combat/Hero.tscn") as PackedScene
	if scene == null:
		return null
	var h: Node = scene.instantiate()
	h.name = "Hero_local_%d" % pad.device
	(h as Node2D).position = spawn_origin + SPAWN_STEP * float(_player_count())
	heroes_root.add_child(h)
	# ⚠ CONTROLLER AFTER add_child, CAMERA AFTER THAT. `Hero._ready` reads `net_class`
	# and builds the rig, and it is `_ready` that puts the body in the "hero" group —
	# so the camera below cannot be found until the node is actually in the tree.
	h.set(&"controller", pad)
	_silence_camera(h)
	_build_bar_for(h)
	return h


## ⚠ A SECOND BAR, NOT A SHARED ONE. `AbilityBar` found its hero with
## `get_first_node_in_group("hero")`, so before it learned `bound_hero` it drew player
## one's cooldowns to both players — which is worse than no bar at all, because it looks
## right. This one is pinned to the climber it belongs to and hugs the opposite corner.
func _build_bar_for(hero: Node) -> void:
	var layer := CanvasLayer.new()
	# Same layer the arena gives player one's bar, so the two read as one HUD.
	layer.layer = 60
	add_child(layer)
	var bar := AbilityBar.new()
	bar.bound_hero = hero
	bar.dock_right = true
	# Player two owns the bottom of the right-hand side; three and four stack above.
	bar.dock_row = maxi(_player_count() - 2, 0)
	layer.add_child(bar)


## ⚠ EVERY Hero.tscn CARRIES A Camera2D, AND OFFLINE NOTHING TURNS THE SPARE ONES OFF.
## `Hero._setup_net_role` disables a non-authority camera, but it early-returns when
## there is no network session (`Hero.gd:6823`) — so a second local hero's camera fights
## the first for "current" and the view can snap between them. `VersusArena._spawn_duel`
## hit this first and solved it the same way; the group removal matters as much as the
## disable, because `Arena._apply_floor_camera` drives every member of "combat_camera"
## on each floor and would otherwise keep waking this one up.
func _silence_camera(hero: Node) -> void:
	for child: Node in hero.get_children():
		if child is Camera2D:
			var cam: Camera2D = child as Camera2D
			cam.enabled = false
			cam.remove_from_group("combat_camera")
