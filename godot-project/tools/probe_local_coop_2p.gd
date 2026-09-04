extends SceneTree
## DOES SAME-SCREEN 2P ACTUALLY WORK, IN THE REAL ARENA, END TO END?
##
## Everything about couch co-op was BUILT and UNPLAYTESTED, and the pieces were only
## ever tested in isolation: `slice_test_local_coop` exercises the pad's deadzones and
## edges against a `FakePad`, and the party count against a `FakeHero`. Neither of
## those has ever been inside `Arena.tscn`. So this boots the real run — real floor,
## real `Encounter` trickling real waves, real `CombatCamera`, real `AbilityBar`s, real
## `Revive` — puts a second climber in it, and MEASURES the six things that decide
## whether two people can play:
##
##   1. TWO BODIES, INDEPENDENTLY DRIVEN. The whole design rests on the pad NOT being
##      in the action map (`Input.is_action_pressed` aggregates every device), so this
##      drives each player in turn and measures how far the OTHER one moved. Any
##      nonzero cross-talk is the bug that would make 2P unplayable.
##   2. TWO HOTBARS, EACH ON ITS OWN CLIMBER.
##   3. THE CAMERA FRAMES BOTH — measured on `get_screen_center_position()`, the DRAWN
##      centre, never `global_position`, which is only the target. Reports the worst
##      single-frame whip and counts frames where a player is off the visible rect or
##      behind the hotbar.
##   4. FRIENDLY FIRE resolves to a specific teammate rather than to nobody.
##   5. A DOWNED PLAYER CAN BE PICKED UP, driven through the rescuer's own controller.
##   6. A PAD PULLED OUT MID-FLOOR DOES NOT STRAND THE RUN.
##
## ⚠ HEADLESS HAS NO WINDOW, SO IT HAS NO ASPECT. `get_visible_rect()` falls back to a
## SQUARE 640x640 — 280 px taller than the maker's frame, which would make every
## "is anyone off screen" answer optimistic. `root.size` is set first, then a frame is
## waited, exactly as `probe_hud_occlusion` does.
##
## ⚠ `Encounter` TRICKLES WAVES IN WHILE THIS RUNS. Node lists are re-collected every
## frame rather than captured once; a list captured at the top of a case is a list of
## bodies that were alive then.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_local_coop_2p.gd

## The pad player's device id. Any number; nothing is plugged in.
const P2_DEVICE: int = 3
## Frames to let the arena build its floor before anything is measured.
const SETTLE: int = 90
## Frames per driving segment. 60 is a full second of physics at the default tick.
const DRIVE: int = 60
## How far apart to hold the two climbers for the camera sweep, in world px. The
## authored rooms reach 1220 wide, so this walks from "on top of each other" to "one
## at each end of the biggest floor in the tower".
const SPREADS: Array[float] = [0.0, 200.0, 450.0, 700.0, 1000.0]
## Frames held at each spread. Long enough for `FRAME_ZOOM_SPEED_IN` (2.0/s, the LAZY
## direction) to actually settle — a shorter hold measures the ease, not the answer.
const HOLD: int = 160
## ⚠ AND THE ANSWER IS ONLY READ OVER THE LAST `STEADY` OF THEM. Each case TELEPORTS
## the two climbers to a new spread, which no play ever does; the camera then legally
## spends the following ~0.5 s easing to the new solve, and counting those frames as
## "a player left the frame" measures the probe's own jump-cut. The first version of
## this table did exactly that and reported 88 offscreen frames and a 60 px whip, both
## of which were entirely inside the ease. The SETTLED reading is the honest one, and
## the transient is printed beside it rather than hidden.
const STEADY: int = 60
## Half-height of a stick fighter's drawn silhouette in world px (`probe_town_feet`).
const BODY_H: float = 31.0
## Mirrors `CombatCamera.HUD_RESERVE_FALLBACK`. `CombatCamera` declares no `class_name`,
## so its constants are not reachable by name from here; this is the same number for
## the same reason (bar margin 14 + slot 46 + the class label's 9 px lift).
const HUD_RESERVE_FALLBACK: float = 69.0


## A pad with nothing behind it. The same three overrides `slice_test_local_coop`
## uses, for the same reason.
class FakePad:
	extends PadController
	var connected: bool = true
	var buttons: Dictionary = {}
	var axes: Dictionary = {}

	func _connected() -> bool:
		return connected

	func _button_raw(b: int) -> bool:
		return bool(buttons.get(b, false))

	func _raw_axis(a: int) -> float:
		return float(axes.get(a, 0.0))


var _pad: FakePad = null
var _coop: Node = null
var _arena: Node = null
var _p1: Node2D = null
var _p2: Node2D = null
var _verdicts: Array[String] = []


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	await process_frame
	root.size = Vector2i(1366, 768)
	await process_frame
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("2P FAIL no GameState autoload")
		quit(1)
		return
	gs.call("enter_run")
	for _i: int in SETTLE:
		await process_frame
	_arena = current_scene
	var view: Vector2 = Vector2(root.get_visible_rect().size)
	print("2P view=%.0fx%.0f  arena=%s" % [view.x, view.y, "null" if _arena == null else _arena.name])
	if _arena == null:
		print("2P FAIL the run did not load an arena")
		quit(1)
		return

	# ── 0. THE ARENA'S OWN LocalCoop, not one this probe built. See `device_override`.
	_coop = _arena.get_node_or_null("LocalCoop")
	if _coop == null:
		print("2P FAIL Arena built no LocalCoop — same-screen co-op is unreachable")
		quit(1)
		return
	print("  LocalCoop wired: heroes_root=%s spawn_origin=%s"
		% [str(_coop.get("heroes_root")), str(_coop.get("spawn_origin"))])

	await _join_player_two()
	if _p1 == null or _p2 == null:
		print("2P FAIL only %d climber(s) after the join" % _heroes().size())
		quit(1)
		return

	await _measure_independence()
	_measure_bars()
	await _measure_camera(view)
	await _measure_camera_walk(view)
	_measure_friendly_fire()
	await _measure_class_pick()
	await _measure_revive()
	await _measure_disconnect()

	print("")
	print("2P VERDICTS")
	for v: String in _verdicts:
		print("  %s" % v)
	quit(0)


func _say(ok: bool, line: String) -> void:
	_verdicts.append("%s  %s" % ["PASS" if ok else "**FAIL**", line])


# ═══════════════════════════════════════════════════════════════════ the join
func _join_player_two() -> void:
	var before: int = _heroes().size()
	# The keyboard hero must be found and NOT adopted, because a probe that let the pad
	# adopt player one would end up measuring one body and calling it two. The keyboard
	# is marked as used the way a person marks it: by pressing a movement key.
	Input.action_press(&"move_right")
	await process_frame
	await process_frame
	Input.action_release(&"move_right")
	await process_frame

	_pad = FakePad.new(P2_DEVICE)
	_coop.set("device_override", [P2_DEVICE] as Array[int])
	var hero: Variant = _coop.call("join_with", P2_DEVICE, _pad)
	for _i: int in 20:
		await process_frame
	var heroes: Array[Node2D] = _heroes()
	print("")
	print("2P JOIN  heroes %d -> %d   joined=%s" % [before, heroes.size(), str(hero)])
	for h: Node2D in heroes:
		var c: Variant = h.get(&"controller")
		print("    %-22s controller=%s  pos=%s"
			% [h.name, "keyboard" if c == null else str(c), str(h.global_position)])
	_say(heroes.size() == before + 1, "a pad join adds exactly one climber (%d -> %d)"
		% [before, heroes.size()])
	for h: Node2D in heroes:
		if h.get(&"controller") == null:
			_p1 = h
		elif h.get(&"controller") == _pad:
			_p2 = h
	_say(_p1 != null and _p2 != null,
		"one climber is on the keyboard and one is on the pad")

	var enc: Node = _arena.get_node_or_null("Encounter")
	if enc == null:
		for n: Node in _arena.get_children():
			if n.get_script() != null and n.has_method("party_size"):
				enc = n
				break
	if enc != null:
		var party: int = int(enc.call("party_size"))
		print("  Encounter.party_size = %d  (guardian HP x%.2f, budget x%.2f)"
			% [party, Encounter.party_boss_hp_mult(party), Encounter.party_budget_mult(party)])
		_say(party == 2, "the floor knows there are two of them (party_size=%d)" % party)
	else:
		_say(false, "could not reach the arena's Encounter to check party_size")


# ═════════════════════════════════════════════════ 1. independently driven
## THE ONE THAT MATTERS MOST. `Input.is_action_pressed` is aggregated across every
## device, which is why the pad is deliberately absent from the action map — so this
## drives one player and measures the OTHER. Both directions, because they fail for
## different reasons: a pad bound into `[input]` walks player one, and a keyboard read
## leaking into the pad path walks player two.
func _measure_independence() -> void:
	print("")
	print("2P INDEPENDENCE  (px moved by each climber while ONE of them is driven)")
	# --- the pad drives player two ---
	_pad.axes[JOY_AXIS_LEFT_X] = 1.0
	var a: Array[Vector2] = await _drive(DRIVE)
	_pad.axes[JOY_AXIS_LEFT_X] = 0.0
	print("    pad right       p1 moved %6.1f   p2 moved %6.1f" % [a[0].x, a[1].x])
	_say(absf(a[1].x) > 8.0, "the pad actually walks player two (%.1f px)" % a[1].x)
	_say(absf(a[0].x) < 4.0,
		"the pad does NOT walk player one (%.1f px of cross-talk)" % a[0].x)

	# ⚠ LET THE COAST DIE FIRST. A released stick does not stop a body dead — `Hero`
	# decelerates over several frames — so starting the next segment immediately
	# credited player two's own leftover momentum to the keyboard and read as 6.7 px of
	# cross-talk that did not exist. The instrument has to stop before it measures.
	await _drive(30)

	# --- the keyboard drives player one ---
	Input.action_press(&"move_left")
	var b: Array[Vector2] = await _drive(DRIVE)
	Input.action_release(&"move_left")
	await process_frame
	print("    keyboard left   p1 moved %6.1f   p2 moved %6.1f" % [b[0].x, b[1].x])
	_say(absf(b[0].x) > 8.0, "the keyboard actually walks player one (%.1f px)" % b[0].x)
	_say(absf(b[1].x) < 4.0,
		"the keyboard does NOT walk player two (%.1f px of cross-talk)" % b[1].x)


## Run `n` frames and return how far each climber travelled. Enemies are pushed away
## first: a mob walking into a hero shoves it, and that shove would read exactly like
## cross-talk.
func _drive(n: int) -> Array[Vector2]:
	var p1a: Vector2 = _p1.global_position
	var p2a: Vector2 = _p2.global_position
	for _i: int in n:
		_shoo_enemies()
		await process_frame
	return [_p1.global_position - p1a, _p2.global_position - p2a] as Array[Vector2]


## Take every live enemy out of the measurement, every frame, so nothing here is
## reading a collision or a mob's contribution to the framing. Re-collected each frame
## because `Encounter` keeps trickling waves in.
##
## ⚠ PARKED ON THE PARTY, NOT SHOVED OFF TO (-4000, -4000), WHICH IS WHAT THE FIRST
## VERSION DID AND WHICH BROKE THE CAMERA TABLE OUTRIGHT. `_frame_group_update` folds
## the whole "enemy" group into the bounding box it solves against, so an enemy parked
## four thousand pixels away made the framer try to fit a 4000 px room: it pinned at
## `FRAME_ZOOM_MIN` and dragged the centre miles off the players. The probe was
## measuring a shot no game will ever produce and blaming the camera for it. Parked on
## the party's own midpoint, a neutralised enemy adds nothing to the box.
##
## Physics, processing AND both collision masks go off: pinning a position is not
## enough on its own, because the HERO is the body doing the moving and it would still
## collide with a frozen mob standing in the way.
func _shoo_enemies() -> void:
	var mid: Vector2 = Vector2.ZERO
	if is_instance_valid(_p1) and is_instance_valid(_p2):
		mid = (_p1.global_position + _p2.global_position) * 0.5
	elif is_instance_valid(_p1):
		mid = _p1.global_position
	for e: Node in get_nodes_in_group("enemy"):
		if not (e is Node2D) or not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var b: Node2D = e as Node2D
		b.set_physics_process(false)
		b.set_process(false)
		if b is CollisionObject2D:
			(b as CollisionObject2D).collision_layer = 0
			(b as CollisionObject2D).collision_mask = 0
		b.global_position = mid


# ═══════════════════════════════════════════════════════════ 2. the two hotbars
func _measure_bars() -> void:
	print("")
	print("2P HOTBARS")
	var bars: Array[Node] = []
	_collect_bars(root, bars)
	for b: Node in bars:
		var bound: Variant = b.get(&"bound_hero")
		print("    bar  bound=%-22s dock_right=%s row=%d"
			% ["(group lookup)" if bound == null else str((bound as Node).name),
				str(b.get(&"dock_right")), int(b.get(&"dock_row"))])
	_say(bars.size() == 2, "there are exactly two hotbars on screen, got %d" % bars.size())
	var bound_to_p2: int = 0
	var unbound: int = 0
	for b: Node in bars:
		var bound: Variant = b.get(&"bound_hero")
		if bound == null:
			unbound += 1
		elif bound == _p2:
			bound_to_p2 += 1
	_say(bound_to_p2 == 1, "exactly one hotbar is pinned to player two's climber")
	# ⚠ THE ARENA'S OWN BAR IS UNBOUND AND TAKES `get_first_node_in_group("hero")`.
	# That is player one only while player one happens to be first in the group — an
	# ordering nothing guarantees. Measured rather than assumed.
	var first: Node = get_first_node_in_group("hero")
	_say(unbound == 1 and first == _p1,
		"the unbound (player one) hotbar resolves to player one, not player two — group[0]=%s"
			% ("null" if first == null else first.name))


func _collect_bars(n: Node, out: Array[Node]) -> void:
	if n is AbilityBar:
		out.append(n)
	for c: Node in n.get_children():
		_collect_bars(c, out)


# ══════════════════════════════════════════════════════════════ 3. the camera
## ⚠ `get_screen_center_position()` IS THE PICTURE; `global_position` IS ONLY THE
## TARGET, and `CombatCamera` expresses its whole framing answer as `offset`, which the
## target does not include. Measuring the wrong one here would report a camera that
## never moves.
func _measure_camera(view: Vector2) -> void:
	print("")
	print("2P CAMERA  (drawn centre, not the target)")
	var cam: Camera2D = _live_camera()
	if cam == null:
		_say(false, "no current camera in the arena")
		return
	print("    parent=%s  frame_all=%s" % [cam.get_parent().name, str(cam.get("_frame_all"))])
	var bar_h: float = _bar_height()
	print("    (settled = the last %d of %d frames; transient = the ease after the jump-cut)"
		% [STEADY, HOLD])
	print("    spread   zoom   centre.x   centre.y   margin_p1  margin_p2  whip  off  bar  [transient off]")
	var total_off: int = 0
	var total_bar: int = 0
	var worst_whip_all: float = 0.0
	var worst_margin: float = 1e9
	var transient_off: int = 0
	# ⚠ SPREAD SYMMETRICALLY ABOUT THE ROOM'S MIDDLE, AND CLAMPED INSIDE IT. Walking
	# player two out from wherever player one happened to be standing put him OUTSIDE
	# the room at the widest case — and `_clamp_centre_to_room` then correctly refuses
	# to follow a body out through the wall, which the table read as the camera losing
	# him (margin -104.8 px, 54 offscreen frames). A body outside the room is not a
	# case the camera owes anything to; the room is the whole world.
	var room: Vector2 = _room_size()
	var floor_y: float = _p1.global_position.y
	for s: float in SPREADS:
		var half: float = minf(s, room.x - 80.0) * 0.5
		var base: Vector2 = Vector2(clampf(room.x * 0.5 - half, 40.0, room.x - 40.0), floor_y)
		var far: Vector2 = Vector2(clampf(room.x * 0.5 + half, 40.0, room.x - 40.0), floor_y)
		var prev: Vector2 = cam.get_screen_center_position()
		var whip: float = 0.0
		var off: int = 0
		var behind: int = 0
		var pre_off: int = 0
		var zoom: float = 0.0
		var centre: Vector2 = Vector2.ZERO
		# The smallest distance either body ever had to the nearest frame edge. A
		# margin is worth more than a boolean: "on screen by 3 px" and "on screen by
		# 90 px" are the same PASS and very different cameras.
		var margin1: float = 1e9
		var margin2: float = 1e9
		for i: int in HOLD:
			_shoo_enemies()
			# Held apart by hand: physics would otherwise walk them back together and
			# the "spread" on the left of the table would be a spread that never was.
			_p1.set_physics_process(false)
			_p2.set_physics_process(false)
			_p1.global_position = base
			_p2.global_position = far
			await process_frame
			centre = cam.get_screen_center_position()
			var settled: bool = i >= HOLD - STEADY
			if settled:
				whip = maxf(whip, prev.distance_to(centre))
			prev = centre
			zoom = cam.zoom.x
			var x: Transform2D = root.get_canvas_transform()
			var s1: Vector2 = x * _p1.global_position
			var s2: Vector2 = x * _p2.global_position
			if not settled:
				pre_off += (1 if _off_frame(s1, view) else 0) + (1 if _off_frame(s2, view) else 0)
				continue
			off += (1 if _off_frame(s1, view) else 0) + (1 if _off_frame(s2, view) else 0)
			margin1 = minf(margin1, _margin(s1, view, bar_h))
			margin2 = minf(margin2, _margin(s2, view, bar_h))
			# A body drawn under the hotbar is not "on screen" in any sense the player
			# cares about — the same standard `probe_hud_occlusion` holds the solo
			# camera to.
			if s1.y > view.y - bar_h or s2.y > view.y - bar_h:
				behind += 1
		total_off += off
		total_bar += behind
		transient_off += pre_off
		worst_whip_all = maxf(worst_whip_all, whip)
		worst_margin = minf(worst_margin, minf(margin1, margin2))
		print("    %6.0f  %5.2f  %9.1f  %9.1f  %10.1f %10.1f %5.1f %4d %4d  %14d"
			% [far.x - base.x, zoom, centre.x, centre.y, margin1, margin2, whip, off,
				behind, pre_off])
	_p1.set_physics_process(true)
	_p2.set_physics_process(true)
	_say(total_off == 0,
		"neither climber ever leaves the settled frame at any spread the %.0f px room allows (%d offscreen frames, %d during the ease)"
			% [room.x, total_off, transient_off])
	_say(total_bar == 0,
		"neither climber is ever drawn behind the hotbar (%d frames)" % total_bar)
	print("    worst margin to a frame edge across every spread: %.1f px" % worst_margin)
	# A whip is a per-frame jump of the drawn centre. The framer eases at
	# `FRAME_SPEED` 3.5/s, so a settled frame moves a few px at most; a SNAP between
	# two players would be tens to hundreds.
	_say(worst_whip_all < 8.0,
		"the settled camera never snaps between the two of them (worst single-frame move %.1f px)"
			% worst_whip_all)


## Distance from a drawn point to the nearest edge of the part of the frame the player
## can actually see — the hotbar band is not part of it. Negative means outside.
func _margin(p: Vector2, view: Vector2, bar_h: float) -> float:
	return minf(minf(p.x, view.x - p.x), minf(p.y + BODY_H, (view.y - bar_h) - p.y))


func _off_frame(p: Vector2, view: Vector2) -> bool:
	return p.x < 0.0 or p.x > view.x or p.y + BODY_H < 0.0 or p.y > view.y


func _live_camera() -> Camera2D:
	for c: Node in get_nodes_in_group("combat_camera"):
		if c is Camera2D and (c as Camera2D).is_current():
			return c as Camera2D
	return root.get_camera_2d()


## ⚠ AND THE SAME QUESTION AT A SPEED A PLAYER CAN ACTUALLY PRODUCE. The table above
## TELEPORTS the party from one spread to the next, which is why it has to throw away
## the ease — but "does anybody leave the frame" is a question about play, and the
## honest version of it is one climber WALKING away from the other, continuously, at
## the speed their own legs move. The framer widens at `FRAME_ZOOM_SPEED_OUT` 7.0/s,
## which is the number that either keeps up with a running body or does not.
func _measure_camera_walk(view: Vector2) -> void:
	print("")
	print("2P CAMERA — WALKING APART (no jump-cuts; the pad is simply held right)")
	var cam: Camera2D = _live_camera()
	if cam == null:
		_say(false, "no current camera for the walk-apart sweep")
		return
	var bar_h: float = _bar_height()
	# ⚠ BOUNDED BY THE ROOM, AND THE FIRST VERSION WAS NOT — it just held the stick and
	# let player two run to x = 9665, four thousand px past the far wall, then reported
	# 802 offscreen frames as if that were a camera fault. It is not: `FRAME_ZOOM_MIN`
	# 0.46 caps the widest shot at `640 / 0.46 - FRAME_PAD.x` = 1223 px of separation,
	# which is a stated, deliberate cap and is three px WIDER than the widest authored
	# room. A separation the room cannot produce is not a case the camera has to hold.
	# The honest question is whether the camera holds them INSIDE the room, so the walk
	# is clamped to it and the analytic cap is printed beside the reading.
	var room: Vector2 = _room_size()
	var cap: float = 640.0 / 0.46 - 168.0   # FRAME_VIEWPORT.x / FRAME_ZOOM_MIN - FRAME_PAD.x
	print("    room %.0f x %.0f   widest separation the framer can hold: %.0f px"
		% [room.x, room.y, cap])
	# Stand them together, let the camera settle on that, THEN walk.
	var base: Vector2 = _p1.global_position
	for _i: int in 60:
		_shoo_enemies()
		_p1.set_physics_process(false)
		_p1.global_position = base
		await process_frame
	_pad.axes[JOY_AXIS_LEFT_X] = 1.0
	var off: int = 0
	var worst_margin: float = 1e9
	var worst_gap: float = 0.0
	var samples: int = 0
	var right_edge: float = maxf(room.x - 24.0, base.x + 40.0)
	for _i: int in 420:
		_shoo_enemies()
		_p1.global_position = base       # player one holds still; player two runs
		await process_frame
		if not is_instance_valid(_p2):
			break
		# Held inside the room by hand. Physics ought to do this — there is a wall —
		# but a probe that depends on a collider to bound its own sweep is a probe that
		# reports the collider's bugs as the camera's.
		if _p2.global_position.x > right_edge:
			_p2.global_position.x = right_edge
		samples += 1
		var x: Transform2D = root.get_canvas_transform()
		var s1: Vector2 = x * _p1.global_position
		var s2: Vector2 = x * _p2.global_position
		worst_gap = maxf(worst_gap, absf(_p2.global_position.x - _p1.global_position.x))
		worst_margin = minf(worst_margin, minf(_margin(s1, view, bar_h), _margin(s2, view, bar_h)))
		off += (1 if _off_frame(s1, view) else 0) + (1 if _off_frame(s2, view) else 0)
	_pad.axes[JOY_AXIS_LEFT_X] = 0.0
	_p1.set_physics_process(true)
	print("    %d frames, gap grew to %.0f px, zoom %.2f, worst margin %.1f px, offscreen %d"
		% [samples, worst_gap, cam.zoom.x, worst_margin, off])
	_say(off == 0,
		"walking apart to %.0f px (room is %.0f wide) never puts either climber off screen — %d offscreen frames"
			% [worst_gap, room.x, off])


func _room_size() -> Vector2:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		return Vector2(1220.0, 620.0)
	var fd: Variant = gs.call("floor_def_for", int(gs.call("current_floor")))
	if fd == null:
		return Vector2(1220.0, 620.0)
	var lay: Variant = fd.get("layout")
	return Vector2(1220.0, 620.0) if lay == null else (lay.get("room_size") as Vector2)


# ═══════════════════════════════════════════════ PLAYER TWO PICKS THEIR CLASS
## The gap this pass closes: a joining pad inherited player one's class and the only
## way out was `switch_class`, which cycles. BACK now opens the real chooser and drives
## it from the same pad. The three things that have to be true are (a) it opens at all
## from a pad, (b) it changes PLAYER TWO's body, and (c) it does not touch player one's
## class — which is the leak, because `GameState.selected_class` is a single global
## written by six other paths.
func _measure_class_pick() -> void:
	print("")
	print("2P CLASS PICK (pad only)")
	var gs: Node = root.get_node_or_null("/root/GameState")
	var cs: Node = root.get_node_or_null("/root/ClassSelect")
	if gs == null or cs == null:
		_say(false, "GameState or ClassSelect autoload missing")
		return
	var p1_class_before: int = int(gs.get("selected_class"))
	var p1_name_before: String = String(_p1.call("class_display_name"))
	var p2_name_before: String = String(_p2.call("class_display_name"))

	# ⚠ PHYSICS FRAMES, NOT IDLE ONES, AND THE FIRST VERSION OF THIS GOT IT WRONG.
	# `PadController`'s snapshot rolls on `Engine.get_physics_frames()`, and a headless
	# run is UNCAPPED: twelve `await process_frame`s take microseconds, physics never
	# ticks, the snapshot never rolls, and no edge is ever produced. The probe reported
	# "BACK does not open the chooser" for two runs on that alone. Interleaved, so real
	# time actually passes.
	_pad.buttons[JOY_BUTTON_BACK] = true
	for _i: int in 4:
		await physics_frame
		await process_frame
	_pad.buttons[JOY_BUTTON_BACK] = false
	for _i: int in 3:
		await physics_frame
		await process_frame
	var opened: bool = bool(cs.call("is_open_for", P2_DEVICE))
	print("    BACK -> chooser open for device %d = %s" % [P2_DEVICE, str(opened)])
	_say(opened, "BACK on the pad opens a real class chooser for that player")
	if not opened:
		return
	# ⚠ AND THE HERO'S HANDS ARE TIED WHILE IT IS UP. Same stick, same A button.
	var suspended: bool = bool(_pad.get("suspended"))
	var moved_while_choosing: Vector2 = _p2.global_position
	_pad.axes[JOY_AXIS_LEFT_X] = 1.0
	for _i: int in 20:
		_shoo_enemies()
		await physics_frame
		await process_frame
	var drift: float = _p2.global_position.distance_to(moved_while_choosing)
	print("    hero pad suspended = %s   body drifted %.1f px while choosing"
		% [str(suspended), drift])
	_say(suspended and drift < 6.0,
		"player two does not run across the floor while reading their own class grid (%.1f px)"
			% drift)
	# Walk the cursor one card, then confirm with A.
	# ⚠ LEFT, NOT RIGHT, AND THE REASON IS THE TEST ABOVE. Holding the stick right for
	# twenty frames to prove the body does not move ALSO walked the cursor — to column
	# 2 of 3, where `_move_cursor` correctly CLAMPS rather than wrapping. A further push
	# right then legitimately changes nothing, and the probe read that as "the stick
	# does not move the cursor". Push away from the edge the previous step parked on.
	_pad.axes[JOY_AXIS_LEFT_X] = 0.0
	await physics_frame
	await process_frame
	var cursor_before: int = int(cs.get("_cursor"))
	_pad.axes[JOY_AXIS_LEFT_X] = -1.0
	for _i: int in 2:
		await physics_frame
		await process_frame
	_pad.axes[JOY_AXIS_LEFT_X] = 0.0
	await physics_frame
	await process_frame
	var cursor_after: int = int(cs.get("_cursor"))
	print("    stick left -> cursor %d -> %d" % [cursor_before, cursor_after])
	_say(cursor_after != cursor_before, "the stick moves the cursor")

	_pad.buttons[JOY_BUTTON_A] = true
	for _i: int in 3:
		await physics_frame
		await process_frame
	_pad.buttons[JOY_BUTTON_A] = false
	for _i: int in 3:
		await physics_frame
		await process_frame
	var stored: int = int(gs.call("local_class_of", P2_DEVICE))
	var p1_after: int = int(gs.get("selected_class"))
	print("    A -> stored P2 class = %d (cursor was %d) | P1 selected_class %d -> %d"
		% [stored, cursor_after, p1_class_before, p1_after])
	print("    P1 body: %s -> %s     P2 body: %s -> %s"
		% [p1_name_before, String(_p1.call("class_display_name")),
			p2_name_before, String(_p2.call("class_display_name"))])
	_say(not bool(cs.call("is_open_for", P2_DEVICE)), "confirming closes the chooser")
	_say(stored == cursor_after,
		"the pick is stored against THAT PAD (local_class_of=%d, wanted %d)"
			% [stored, cursor_after])
	_say(p1_after == p1_class_before,
		"player two's pick does NOT overwrite player one's class (%d -> %d)"
			% [p1_class_before, p1_after])
	_say(String(_p1.call("class_display_name")) == p1_name_before,
		"player one's BODY is untouched by player two's pick")
	_say(String(_p2.call("class_display_name")) != p2_name_before,
		"player two's body actually becomes the class they chose (%s -> %s)"
			% [p2_name_before, String(_p2.call("class_display_name"))])
	_say(not bool(_pad.get("suspended")),
		"the pad goes back to the hero once the chooser closes")


# ════════════════════════════════════════════════════════ 4. friendly fire
func _measure_friendly_fire() -> void:
	print("")
	print("2P FRIENDLY FIRE  dial=%s" % FriendlyFire.status_text())
	var other: Node = FriendlyFire.other_hero(self, _p2)
	print("    other_hero(p2) = %s" % ("null" if other == null else other.name))
	_say(other == _p1,
		"a hit on player two is attributed to player one, not to nobody")
	var was: bool = FriendlyFire.enabled()
	_say(not FriendlyFire.blocks_bolt() if was else FriendlyFire.blocks_bolt(),
		"the dial and the bolt gate agree (enabled=%s, blocks_bolt=%s)"
			% [str(was), str(FriendlyFire.blocks_bolt())])
	# Flip it and check the gate follows, then put it back — a probe that leaves a
	# global switch moved is a probe that breaks whatever runs next.
	FriendlyFire.set_enabled(not was)
	var flipped_ok: bool = FriendlyFire.blocks_bolt() == was
	FriendlyFire.set_enabled(was)
	_say(flipped_ok, "flipping the dial flips the bolt gate with it")
	var landed: bool = FriendlyFire.report(_p2, _p1, 12)
	_say(landed, "a hero-on-hero hit fires the attribution beat")


# ═══════════════════════════════════════════════════════════════ 5. the revive
## Player two goes down; player one walks over and holds the revive. Driven through
## the RESCUER'S OWN input path — the keyboard player reads the global action, which
## is what `Revive._holding_revive` falls through to when a hero has no controller.
func _measure_revive() -> void:
	print("")
	print("2P REVIVE")
	var rev: Node = _arena.get_node_or_null("Revive")
	if rev == null:
		_say(false, "the arena built no Revive node")
		return
	if not _p2.has_method("kill_out_of_world"):
		_say(false, "player two's body has no way to be put down")
		return
	# ⚠ BOTH BODIES ARE PINNED FOR THE WHOLE OF THIS TEST, AND THE FIRST VERSION WAS
	# NOT. A ghost keeps falling; `Arena._catch_fallen_heroes` kills anything past
	# `room.y + FALL_OUT_MARGIN`; and this probe was parking the RESCUER on the ghost —
	# so player one followed player two out of the bottom of the room, both went down,
	# the party wipe fired, and the run ended mid-measurement. That read as "the
	# disconnect removed both climbers". It was the harness walking them off a cliff.
	var mark_p1: Vector2 = _p1.global_position
	var mark_p2: Vector2 = mark_p1 + Vector2(20.0, 0.0)
	_p1.set_physics_process(false)
	_p2.set_physics_process(false)
	_p2.call("kill_out_of_world")
	for _i: int in 30:
		_shoo_enemies()
		_p1.global_position = mark_p1
		_p2.global_position = mark_p2
		await process_frame
	var downed: bool = _p2.has_method("is_downed") and bool(_p2.call("is_downed"))
	print("    p2 downed = %s" % str(downed))
	_say(downed, "player two goes down rather than vanishing")
	if not downed:
		_p1.set_physics_process(true)
		_p2.set_physics_process(true)
		return
	# Player one is already standing 20 px away — well inside `Revive.RANGE` (92).
	Input.action_press(Revive.REVIVE_ACTION)
	var offered: bool = false
	# ⚠ FRAMES ARE NOT SECONDS HERE. `Revive` channels on `delta`, and a headless run
	# is UNCAPPED — the measured tick is ~7 ms, not 16.7 — so a loop sized as
	# "CHANNEL_TIME x 60" ran barely a second of game time and reported progress 0.69
	# and a failed revive. It was the harness that ran out, not the mechanic. Sized
	# generously and broken out the moment they are up.
	var frames: int = 1500
	var peak: float = 0.0
	for _i: int in frames:
		_shoo_enemies()
		_p1.global_position = mark_p1
		if bool(_p2.call("is_downed")):
			_p2.global_position = mark_p2
		await process_frame
		offered = offered or bool(rev.call("can_revive"))
		peak = maxf(peak, float(rev.call("revive_progress")))
		if not bool(_p2.call("is_downed")):
			break
	Input.action_release(Revive.REVIVE_ACTION)
	_p1.set_physics_process(true)
	_p2.set_physics_process(true)
	var up: bool = not bool(_p2.call("is_downed"))
	print("    offer seen = %s   back up = %s   peak channel progress = %.2f"
		% [str(offered), str(up), peak])
	_say(offered, "the game offers the revive when a living player stands over a ghost")
	_say(up, "holding the revive for %.1fs actually stands player two back up"
		% Revive.CHANNEL_TIME)


# ═════════════════════════════════════════════ 6. the pad leaves mid-floor
## The failure this is looking for is not a crash — it is a body that stays. See
## `LocalCoop._drop` for the three things an abandoned climber goes on doing.
func _measure_disconnect() -> void:
	print("")
	print("2P DISCONNECT")
	var before: int = _heroes().size()
	_pad.connected = false
	_coop.set("device_override", [] as Array[int])   # the pad is gone from the machine
	for _i: int in 20:
		await process_frame
	var after: Array[Node2D] = _heroes()
	var p2_gone: bool = not is_instance_valid(_p2) or _p2.is_queued_for_deletion()
	print("    heroes %d -> %d   p2 removed = %s" % [before, after.size(), str(p2_gone)])
	_say(p2_gone and after.size() == before - 1,
		"an unplugged pad takes its climber off the floor (%d -> %d)"
			% [before, after.size()])
	var enc: Node = _arena.get_node_or_null("Encounter")
	if enc != null:
		var party: int = int(enc.call("party_size"))
		print("    party_size back to %d" % party)
		_say(party == 1,
			"the floor stops being scaled for two once the second pad is gone (party_size=%d)"
				% party)
	# And plugging back in is a REJOIN, not a dead device.
	var pad2 := FakePad.new(P2_DEVICE)
	_coop.set("device_override", [P2_DEVICE] as Array[int])
	var rejoined: Variant = _coop.call("join_with", P2_DEVICE, pad2)
	for _i: int in 20:
		await process_frame
	print("    rejoin -> %s  (heroes now %d)" % [str(rejoined), _heroes().size()])
	_say(rejoined != null, "plugging the pad back in puts the player back in the game")


# ══════════════════════════════════════════════════════════════════ helpers
## The band at the bottom the hotbar covers — asked of the bar rather than copied, the
## same rule `CombatCamera._hud_reserve` follows. `HUD_RESERVE_FALLBACK` is what this
## reading is worth sanity-checking against if the bar is ever rescaled again.
func _bar_height() -> float:
	return float(AbilityBar.occupied_height())


func _heroes() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for n: Node in get_nodes_in_group("hero"):
		if n is Node2D and is_instance_valid(n) and not n.is_queued_for_deletion():
			out.append(n as Node2D)
	return out
