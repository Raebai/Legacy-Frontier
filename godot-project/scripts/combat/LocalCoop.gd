class_name LocalCoop
extends Node

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
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
##   * Nothing here is PLAYTESTED. Two pads have never been held in front of this.
##
## Closed since the first slice: player two now has their own ability bar, pinned to
## their own climber and docked to the opposite corner (`_build_bar_for`), and either
## player can revive the other — `Revive` reads the rescuer's OWN controller instead of
## the shared global `Input`, and picks the closest rescuer/ghost PAIR rather than
## whichever body happened to be first in the group.
##
## ══ CLOSED THIS PASS ═══════════════════════════════════════════════════════════════
##   * PLAYER TWO PICKS THEIR OWN CLASS (`_open_class_menu`). The old note here said
##     the only route was `switch_class` on BACK, which CYCLES — nine presses to reach
##     the ninth class, with the body rebuilt on every one of them, and no way to see
##     what you were about to become. BACK now opens the real chooser
##     (`ClassSelect.open_for_pad`) driven entirely by the pad, writes
##     `GameState.set_local_class(device, i)` so the pick survives a respawn, and
##     re-configures that player's live body — and ONLY that body.
##   * A PAD PULLED OUT MID-FLOOR NO LONGER STRANDS THE RUN (`_drop`). Nothing watched
##     for a departed device, so an unplugged player two left a body standing in the
##     room for ever: still counted by `Encounter.party_size` (so the floor stayed
##     scaled for two), still counted by `Arena._check_party_wipe` (so if it was
##     DOWNED at the time, the run could neither be lost nor won by the person still
##     holding a pad), and still holding its device id, so plugging back in spawned a
##     THIRD body rather than resuming. See `_drop` for what each half of that costs.

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
signal player_left(device: int)

var heroes_root: Node = null
var spawn_origin: Vector2 = Vector2.ZERO

var _claimed: Dictionary = {}          ## device id -> PadController
var _bodies: Dictionary = {}           ## device id -> Node (the climber it drives)
var _bars: Dictionary = {}             ## device id -> CanvasLayer (that climber's hotbar)
var _keyboard_seen: bool = false
var _p1_adopted: bool = false
## Which device, if any, ADOPTED the keyboard hero. Needed by `_drop`: that body is the
## arena's own and must be handed BACK rather than freed.
var _adopted_device: int = -1


func setup(root: Node, origin: Vector2) -> void:
	heroes_root = root
	spawn_origin = origin


func _process(_delta: float) -> void:
	if not _keyboard_seen and _keyboard_active():
		_keyboard_seen = true
	var live: Array[int] = _connected_devices()
	for device: int in live:
		if _claimed.has(device):
			continue
		if _join_pressed(device):
			_join(device)
	# ⚠ AND THE OTHER DIRECTION, WHICH NOTHING WATCHED FOR. A pad that has left the
	# machine is not a player any more, and every system downstream counts BODIES.
	# Iterated over a COPY of the keys because `_drop` mutates the dictionary.
	for device: int in _claimed.keys():
		if not live.has(device):
			_drop(device)


## ⚠ THE CLASS-MENU POLL LIVES IN PHYSICS, AND `_process` WAS THE BUG. Everything above
## is LEVEL-triggered — "is this button down", "is this device still plugged in" — and
## does not care which clock asks. The class menu is EDGE-triggered, and a
## `PadController` edge exists for exactly one PHYSICS frame.
##
## Godot runs up to `max_physics_steps_per_frame` (8) physics steps per idle frame, and
## a busy tower floor is slow enough to use several of them. The Hero reads its pad on
## every one of those steps, which rolls the snapshot every time — so by the time an
## idle-frame `_process` looked, the edge from the first step of that frame was two or
## three rolls in the past and simply gone. Measured in the real arena: the suite passed
## and `BACK -> chooser open = false` in the game, three runs running, with no error
## anywhere. Solo play never noticed because nothing else here reads an edge.
##
## Ask on the clock the edge is defined on.
func _physics_process(_delta: float) -> void:
	_poll_class_menus()


## ---- the one device read, isolated so a headless probe can fake a couch ----------
## Same idiom, and the same reason, as `PadController`'s three overridable reads: there
## is no controller plugged into a headless box, so the JOIN path — adoption, spawn
## ordering, the second hotbar, the camera silencing, and now the LEAVE path — could
## not otherwise be exercised at all. Everything else in this file is the real thing.
##
## ⚠ A FIELD RATHER THAN AN OVERRIDDEN METHOD, ON PURPOSE. A probe that subclasses this
## has to REPLACE the node `Arena` built, and would then be measuring its own object
## instead of the one the game wired up — which is how a co-op bug hides in the ten
## lines of `Arena._setup_heroes` that the test never reaches. Empty means "ask the
## hardware", so the shipped path is one comparison away from byte-identical.
var device_override: Array[int] = []


func _connected_devices() -> Array[int]:
	return device_override if not device_override.is_empty() else Input.get_connected_joypads()


func _make_pad(device: int) -> PadController:
	return PadController.new(device)


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
	join_with(device, _make_pad(device))


## THE JOIN, with the pad handed in. Public and pad-taking because that is the ONLY
## seam a headless run can reach: `_join` above builds a real `PadController`, which on
## a machine with no controller reads neutral for ever, so every line below — adoption,
## the spawn offset, the second hotbar, the camera silencing — would be untestable.
## The game only ever calls `_join`.
func join_with(device: int, pad: PadController) -> Node:
	if pad == null or _claimed.has(device):
		return null
	_claimed[device] = pad

	# THE ADOPTION CASE: nobody has touched the keyboard, so this pad is player one and
	# the hero already standing in the room becomes theirs. No second body, no idle
	# climber inflating the floor.
	if not _p1_adopted and not _keyboard_seen:
		var existing: Node = _first_undriven_hero()
		if existing != null:
			_p1_adopted = true
			_adopted_device = device
			existing.set(&"controller", pad)
			_bodies[device] = existing
			player_joined.emit(device, existing)
			print("[local-coop] pad %d took over player 1" % device)
			return existing

	# ⚠ HUMANS, NOT BODIES — the same rule `Encounter.party_size` had to learn. This
	# counted every member of the "hero" group, so two bot allies standing in the room
	# would have refused a real person's join at MAX_PLAYERS while contributing nobody
	# to the couch. The cap is on PEOPLE.
	if _human_count() >= MAX_PLAYERS:
		_claimed.erase(device)
		return null
	var hero: Node = _spawn_hero(pad)
	if hero == null:
		_claimed.erase(device)
		return null
	_bodies[device] = hero
	player_joined.emit(device, hero)
	print("[local-coop] pad %d joined as player %d" % [device, _human_count()])
	return hero


## ══ A PAD LEFT THE MACHINE ═══════════════════════════════════════════════════════
## Three separate things go wrong if nobody notices, and they are worth naming because
## only the first is visible:
##   1. `Encounter.party_size` keeps counting the abandoned body, so the floor stays
##      scaled for two — guardian HP x1.70, wave budget x1.60 — against one player.
##   2. `Arena._check_party_wipe` returns early on any hero that is NOT downed, and
##      ends the run when they ALL are. An idle body therefore either blocks the wipe
##      for ever (it never dies) or, if it was already a ghost when the cable went,
##      holds a run open that nobody can revive it out of.
##   3. `_claimed` still held the id, so plugging the pad back in was not a rejoin —
##      the device was simply ignored, and there was no way back into the game.
##
## The ADOPTED player-one body is handed BACK to the keyboard instead of freed: it is
## the arena's own hero, freeing it would empty the room, and "the pad died, use the
## keyboard" is the only recovery that leaves a game to keep playing. `_p1_adopted`
## reopens so the next pad to press A adopts it again.
func _drop(device: int) -> void:
	# ⚠ CLOSE THE CHOOSER FIRST, WHILE THE CLAIM STILL EXISTS. `_close_class_menu` looks
	# the pad up in `_claimed` to lift its suspend; erasing first would leave a
	# suspended pad behind — which matters on the ADOPTED path below, where that same
	# object is about to be handed back to a hero that would then be unable to move.
	_close_class_menu(device)
	var pad: Variant = _claimed.get(device)
	_claimed.erase(device)
	var body: Node = _bodies.get(device) as Node
	_bodies.erase(device)
	if device == _adopted_device:
		_adopted_device = -1
		_p1_adopted = false
		if is_instance_valid(body):
			body.set(&"controller", null)
		print("[local-coop] pad %d left — player 1 is back on the keyboard" % device)
		player_left.emit(device)
		return
	var bar: Node = _bars.get(device) as Node
	_bars.erase(device)
	if is_instance_valid(bar):
		bar.queue_free()
	if is_instance_valid(body):
		# ⚠ FREED, NOT PARKED. A parked body is exactly the stranding this fixes: it
		# still stands in the wave's line of fire, still soaks the friendly fire that
		# is always on, and still votes in both counts above. `queue_free` lands at the
		# end of the frame and `_check_party_wipe` already skips a node that is
		# `is_queued_for_deletion`, so there is no tick where the leaving body can
		# decide the run.
		body.queue_free()
	if pad is PadController:
		(pad as PadController).suspended = true
	print("[local-coop] pad %d left — their climber has been removed from the floor" % device)
	player_left.emit(device)


## Player two's class, or -1 to inherit player one's. Guarded lookup: the store lives
## on an autoload, and a headless harness that builds a `LocalCoop` without one must get
## the inherit answer rather than abort.
func _class_for(device: int) -> int:
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs == null or not gs.has_method(&"local_class_of"):
		return -1
	return int(gs.call(&"local_class_of", device))


func _first_undriven_hero() -> Node:
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if is_instance_valid(h) and h.get(&"controller") == null:
			return h
	return null


func _player_count() -> int:
	return get_tree().get_nodes_in_group("hero").size()


## PEOPLE in the room. Deliberately the same test as `Encounter.party_size` — a body
## with no driver is the keyboard player (or a remote puppet), and a driver that says
## it is a person is a person; `BotController` answers no by not having the method.
## Kept as its own function rather than calling into `Encounter` because this node has
## no handle on one and must work in the F6 sandbox, where there is none.
func _human_count() -> int:
	var n: int = 0
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if not is_instance_valid(h) or h.is_queued_for_deletion():
			continue
		var ctrl: Variant = h.get(&"controller")
		if ctrl == null:
			n += 1
		elif ctrl is Object and (ctrl as Object).has_method(&"is_human") \
				and bool((ctrl as Object).call(&"is_human")):
			n += 1
	return n


# ══════════════════════════════════════════════ PLAYER TWO PICKS THEIR OWN CLASS
## ⚠ WHY THIS IS NOT `switch_class`. BACK used to be mapped straight through to the
## Hero's own `switch_class`, which CYCLES: to play the ninth class you press it nine
## times, rebuilding the rig, the weapon and the whole spell config on each press, with
## nothing on screen naming what you are about to become. That is a debug key, not a
## class pick, and it was the standing known gap in this file's header.
##
## The pad's BACK is bound to `class_menu` instead (see `PadController.BUTTONS`) — an
## action name NOTHING else in the game reads, so a pad can never trip the cycle by
## accident and the keyboard's own `switch_class` binding is untouched. Solo is
## byte-identical: with no pad joined this whole section never runs.
var _menus: Dictionary = {}            ## device id -> true while its chooser is open
## device id -> the physics frame its chooser last closed on. The MIRROR of
## `ClassSelect._opened_frame`, and needed for the same reason from the other side: BACK
## also backs OUT of the chooser, and the edge that closed it is still live for the rest
## of that frame — so without this the next `_process` of the same frame reads it again
## and re-opens the screen the player just dismissed, for ever.
var _menu_closed_frame: Dictionary = {}


func _poll_class_menus() -> void:
	# SOLO IS BYTE-IDENTICAL, and this is the line that keeps it that way: with nobody
	# joined there is not even an autoload lookup, let alone a poll.
	if _claimed.is_empty():
		return
	var cs: Node = get_node_or_null(^"/root/ClassSelect")
	if cs == null or not cs.has_method(&"open_for_pad"):
		return
	for device: int in _claimed.keys():
		var pad: Variant = _claimed[device]
		if not (pad is PadController):
			continue
		var p: PadController = pad as PadController
		if _menus.has(device):
			# The chooser owns the pad while it is up; it tells us when it is done.
			if not bool(cs.call(&"is_open_for", device)):
				_close_class_menu(device)
			continue
		# ⚠ `just_pressed`, THE HERO-FACING READ, IS CORRECT HERE. While no menu is up
		# the pad is not suspended, so it answers normally; and if one somehow were, the
		# branch above has already `continue`d. The chooser uses `menu_just_pressed` on
		# this same object to read through its own suspend.
		if int(_menu_closed_frame.get(device, -1)) == Engine.get_physics_frames():
			continue
		if p.just_pressed(&"class_menu"):
			_open_class_menu(device, cs, p)


func _open_class_menu(device: int, cs: Node, pad: PadController) -> void:
	# ⚠ SUSPEND FIRST, THEN HAND THE SAME OBJECT OVER. The chooser reads through the
	# suspend (`PadController.menu_pressed`); the hero, holding the same object, reads
	# neutral. One pad, one truth about what is being held, two sides of a gate.
	pad.suspended = true
	_menus[device] = true
	# The SEAT, not the device id — "player 2", never "player 5" because their pad
	# happened to enumerate as joypad 3.
	cs.call(&"open_for_pad", device, pad, Callable(self, "_on_class_picked"),
		_seat_of(device))


## Which player on the couch this device is: 2 for the first joiner after player one,
## then 3 and 4. Derived from join order, which is the order `_claimed` was filled in.
func _seat_of(device: int) -> int:
	var seat: int = 2
	for d: int in _claimed.keys():
		if d == device:
			return seat
		if d != _adopted_device:
			seat += 1
	return seat


func _close_class_menu(device: int) -> void:
	if not _menus.has(device):
		return
	_menus.erase(device)
	_menu_closed_frame[device] = Engine.get_physics_frames()
	var pad: Variant = _claimed.get(device)
	if pad is PadController:
		(pad as PadController).suspended = false
	var cs: Node = get_node_or_null(^"/root/ClassSelect")
	if cs != null and cs.has_method(&"close_for"):
		cs.call(&"close_for", device)


## The chooser's answer. Two writes, and the split is the whole point: the STORE keeps
## the pick for every future body this device spawns (`_class_for` reads it, and
## `Arena._place_heroes_on_floor` never rebuilds a hero so the live one is the one that
## matters), and `configure_class` re-dresses the body they are standing in RIGHT NOW.
##
## ⚠ AND IT TOUCHES EXACTLY ONE BODY. `ClassSelect._apply_feedback` re-configures the
## whole "player" group and writes `GameState.selected_class` — correct for the hub
## altar, and for player two it would silently turn player ONE into a Cryomancer too.
## That path is not taken in pad mode; this is.
func _on_class_picked(device: int, index: int) -> void:
	var gs: Node = get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method(&"set_local_class"):
		gs.call(&"set_local_class", device, index)
	var body: Node = _bodies.get(device) as Node
	if is_instance_valid(body) and body.has_method(&"configure_class"):
		body.call(&"configure_class", index)
	_close_class_menu(device)


func _spawn_hero(pad: PadController) -> Node:
	if heroes_root == null or not is_instance_valid(heroes_root):
		return null
	var scene: PackedScene = load("res://scenes/combat/Hero.tscn") as PackedScene
	if scene == null:
		return null
	var h: Node = scene.instantiate()
	h.name = "Hero_local_%d" % pad.device
	(h as Node2D).position = spawn_origin + SPAWN_STEP * float(_human_count())
	# ⚠ BEFORE add_child, BECAUSE `_ready` IS WHAT READS IT. `Hero._ready` resolves its
	# class as `net_class` (when >= 0) else `GameState.selected_class`, so a class set
	# after the body is in the tree is a class set too late - the rig, weapon and spell
	# config are already built. This is the same field and the same ordering the
	# networked spawner uses at `Arena.gd:1219`; -1 falls through to player one's pick,
	# which is exactly the behaviour this had before there was anywhere to store a
	# second choice.
	h.set(&"net_class", _class_for(pad.device))
	heroes_root.add_child(h)
	# ⚠ CONTROLLER AFTER add_child, CAMERA AFTER THAT. `Hero._ready` reads `net_class`
	# and builds the rig, and it is `_ready` that puts the body in the "hero" group —
	# so the camera below cannot be found until the node is actually in the tree.
	h.set(&"controller", pad)
	_silence_camera(h)
	_build_bar_for(h, pad.device)
	return h


## ⚠ A SECOND BAR, NOT A SHARED ONE. `AbilityBar` found its hero with
## `get_first_node_in_group("hero")`, so before it learned `bound_hero` it drew player
## one's cooldowns to both players — which is worse than no bar at all, because it looks
## right. This one is pinned to the climber it belongs to and hugs the opposite corner.
func _build_bar_for(hero: Node, device: int) -> void:
	var layer := CanvasLayer.new()
	# Same layer the arena gives player one's bar, so the two read as one HUD.
	# ⚠ 60 IS `LAYER_SHOUT`. Player one's hotbar is on LAYER_HUD (50), so this put the two
	# players' bars on different layers AND put P2's on the same index as the Hype shouts —
	# the exact two-CanvasLayers-on-one-index collision the allocation was written to stop,
	# reintroduced. Two layers on one index resolve by tree order, i.e. by accident.
	layer.layer = HudStyle.LAYER_HUD
	add_child(layer)
	var bar := AbilityBar.new()
	bar.bound_hero = hero
	bar.dock_right = true
	# Player two owns the bottom of the right-hand side; three and four stack above.
	# ⚠ HUMANS, NOT BODIES: with a bot ally in the room a body count would push player
	# two's bar up a row and leave a gap where nobody's hotbar is.
	bar.dock_row = maxi(_human_count() - 2, 0)
	layer.add_child(bar)
	# Kept so `_drop` can take the bar down with the climber. A bar outliving its
	# climber draws nothing (`AbilityBar._bound`), which is correct but is still a
	# stripe of dead HUD in the corner of a game that is now one player again.
	_bars[device] = layer


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
