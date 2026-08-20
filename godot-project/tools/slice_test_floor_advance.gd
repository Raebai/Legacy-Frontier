# Run: godot --headless --path godot-project --script tools/slice_test_floor_advance.gd
# THE CLIMB SURVIVES THE STEP ONTO THE NEXT FLOOR.
#
# ⚠ THIS SUITE EXISTS BECAUSE OF "FLOOR 2 WILL NOT LET THE PLAYER SPAWN", and because
# every pure-geometry check that could have caught it stayed green.
#
# The bug: `Arena._on_floor_advanced` rebuilt the room for the new floor but only
# repositioned the hero inside a co-op-only branch, so a solo climber kept the position
# it held when it touched floor 1's exit while floor 2's walls were rebuilt underneath
# it. `FloorGen` rolls room height in 560..620; a GROUND exit leaves the hero's 18 px
# box centred at `h1 - 17`, and the new floor's bottom wall spans `h2 - 8 .. h2 + 8` —
# so when the next floor is ~20 px shorter, more of the box sits below the wall's
# midline, depenetration ejects it DOWNWARD, and the hero falls out of the world.
#
# ⚠ AND IT COULD NOT BE MEASURED WITHOUT STEPPING PHYSICS. The purely geometric
# question ("is the hero's box entirely below the wall?") found the fault on 2% of
# rolls. The real one ("which way will the solver push it?") needs only "is more of the
# box below the wall's midline", and that is 4 of 20 real climbs — every single ground
# exit onto a shorter room. A spawn test that does not run the solver will report this
# bug fixed while it is live. So this suite drives the REAL path and lets it settle.
#
# ⚠ IT ALSO CARRIES ITS OWN CONTROLS, because an "is the hero OK?" predicate that is
# accidentally true of everything would pass this suite forever. One known-good
# placement must read GREEN and one known-broken placement must read RED, through the
# SAME verdict function as the real measurement. If either control disagrees the suite
# fails on the instrument rather than reporting on the game.
#
# House style per `tools/slice_test_loadout.gd`: failures accumulate on a MEMBER and
# every test records a completion sentinel, so a test that aborts part-way fails the
# suite BY ABSENCE rather than passing vacuously. `failed += _test_x()` is banned.
extends SceneTree

## The climb seeds walked. 2, 6, 15 and 18 are the four that LOST THE HERO before the
## fix — they are the regression cases and must never be dropped from this list. The
## rest are ordinary passing seeds kept so a change that breaks the working majority
## cannot hide behind the four that used to fail.
const SEEDS: Array[int] = [1, 2, 3, 6, 10, 15, 18]
## Seeds that additionally run the instrument controls. Kept short: each control costs
## 100 physics ticks and proves a property of the predicate, not of the seed.
const CONTROL_SEEDS: Array[int] = [2, 6]

## Arena's wall thickness, mirrored — Encounter mirrors the same constant for the same
## reason (a test cannot reach into the scene's collision shapes cheaply).
const WALL_T: float = 16.0
## The hero's collision box, mirrored — the fixture needs it to place a body centre.
const HERO_BOX: Vector2 = Vector2(18.0, 18.0)
## How far outside the room counts as "gone". Matches Arena.FALL_OUT_MARGIN's intent:
## generous enough that a knockback arc is not a failure.
const OUT_MARGIN: float = 200.0

const CLIMBER: String = "user://climber.json"

const TESTS: Array[String] = [
	"advance_keeps_the_hero_in_the_room",
	"instrument_controls_agree",
	"clearing_a_floor_heals_you",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _climber_backup: String = ""
var _had_climber: bool = false
## Set false by a control that reads the wrong way. Checked by its own test so the
## failure is reported as "the instrument is broken", not as "the game is broken".
var _instrument_ok: bool = true
## One row per walked climb: what the hero was cut down to, and what it arrived with.
var _heals: Array[Dictionary] = []
var _controls_run: int = 0


## ⚠ `_initialize` + `call_deferred`, NOT `_process`. Driving this from the first
## `_process` frame puts the whole walk one frame ahead of the scene swap `enter_run`
## performs, and the hero then spends its settle loop falling through a room that has
## not been built yet. Measured: from `_process` the hero left the world on floor 1 on
## every seed and no portal ever fired.
func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	# ⚠ THE REAL SAVE IS ON THE LINE. `enter_run()` / `advance_floor()` persist, and a
	# test run that banks xp into the player's climb has bitten this repo three times
	# (heroes then spawn at level 2 and unrelated class-stat suites drift red). The
	# `_save_climber` guard covers a bare `GameState.new()`; this suite drives the REAL
	# autoload, which that guard deliberately does not cover — so it snapshots and
	# restores by hand, and asserts the restore was byte-exact.
	_snapshot_climber()
	await _test_advance_keeps_the_hero_in_the_room()
	_test_instrument_controls_agree()
	_test_clearing_a_floor_heals_you()
	_restore_climber()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("  test '%s' did not run to completion — it aborted part-way" % name)
	if _fails > 0:
		printerr("Floor advance tests: %d FAILED" % _fails)
		quit(1)
		return
	print("Floor advance tests: all PASS")
	quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("  FAIL: " + msg)


func _completes(name: String) -> void:
	_completed[name] = true


# ══════════════════════════════════════════════════════════════════════════════
## Walk the genuine climb path — `enter_run` builds the tower and loads Arena, the
## floor is cleared, the hero is stood on the exit, the portal's own overlap poll fires
## the advance — then let physics settle and ask where the body ended up.
func _test_advance_keeps_the_hero_in_the_room() -> void:
	var gs: Node = root.get_node_or_null(^"/root/GameState")
	# Autoloads are NOT global identifiers under `--script`; the NODE is on the tree.
	if gs == null:
		_expect(false, "GameState autoload node is not on the tree")
		_completes("advance_keeps_the_hero_in_the_room")
		return
	var lost: Array[int] = []
	for s: int in SEEDS:
		var r: Dictionary = await _walk_one(gs, s)
		if not bool(r.get("reached", false)):
			_expect(false, "seed %d: the advance never happened — the climb path is blocked before the rebuild" % s)
			continue
		if not bool(r.get("ok", false)):
			lost.append(s)
		_heals.append(r)
	_expect(lost.is_empty(),
		"the hero fell out of the world on climb seed(s) %s — Arena._on_floor_advanced must stand every hero on the new floor's own hero_start, in single player too" % str(lost))
	_completes("advance_keeps_the_hero_in_the_room")


## The controls ran and both read the way a working predicate must.
func _test_instrument_controls_agree() -> void:
	_expect(_controls_run == CONTROL_SEEDS.size() * 2,
		"expected %d control placements, ran %d — the controls did not execute, so nothing here is trustworthy"
			% [CONTROL_SEEDS.size() * 2, _controls_run])
	_expect(_instrument_ok,
		"a control read the wrong way: this suite's 'is the hero OK' predicate is broken, so its verdict on the real path means nothing")
	_completes("instrument_controls_agree")


# ══════════════════════════════════════════════════════════════════════════════
func _walk_one(gs: Node, seed_value: int) -> Dictionary:
	FloorGen.climb_seed = seed_value
	gs.set(&"active_tower", null)
	gs.set(&"_run_active", false)
	gs.set(&"_floor", 1)
	gs.set(&"tower_conquered", false)
	gs.call(&"enter_run")
	for _i: int in 6:
		await process_frame
	var arena: Node = current_scene
	if arena == null:
		return {"reached": false, "ok": false}
	for _i2: int in 90:
		await physics_frame
	var hero: Node2D = _hero()
	if hero == null:
		return {"reached": false, "ok": false}
	var l1: LayoutDef = arena.get(&"_current_floor_def").layout

	# Clear the room the way a cleared floor does, then stand on the exit.
	for e: Node in get_nodes_in_group(&"enemy"):
		e.queue_free()
	arena.call(&"_on_floor_cleared")
	await physics_frame
	# ⚠ WOUND IT FIRST. Maker: *"when you pass a floor in the tower you can fully heal
	# as entering the next floor"*. A hero that walks onto the exit at full health
	# proves nothing about a heal, so take it to a third of its bar and let the real
	# advance decide what it arrives with.
	var maxhp: int = int(hero.get(&"max_hp"))
	hero.set(&"hp", maxi(1, int(round(float(maxhp) * 0.33))))
	var hurt: int = int(hero.get(&"hp"))
	hero.global_position = _stance_at_exit(l1)
	var reached: bool = false
	# ⚠ SAMPLE THE HEAL ON THE FRAME IT ARRIVES, NOT AFTER THE SETTLE LOOP. The first
	# version of this read hp 150 ticks later and reported 118..128 of 133 — the heal
	# HAD fired and the new floor's enemies were already chipping it back down, and on
	# two seeds the hero was dead (0/133) by the time it looked. That is a measurement
	# bug that reads exactly like a broken heal.
	var arrived_hp: int = -1
	var arrived_max: int = -1
	for _i3: int in 120:
		await physics_frame
		if int(gs.call(&"current_floor")) == 2:
			reached = true
			arrived_hp = int(hero.get(&"hp"))
			# ⚠ MAX IS READ AT THE SAME INSTANT AS HP, not before the advance. Clearing
			# a floor can raise `max_hp` (a level-up on the way through), and comparing
			# a fresh hp against a stale max reported "arrived 134/133" — a hero at FULL
			# health failing a full-health assertion by one point.
			arrived_max = int(hero.get(&"max_hp"))
			break
	if not reached:
		return {"reached": false, "ok": false}

	var l2: LayoutDef = arena.get(&"_current_floor_def").layout
	# 150 ticks = 2.5 s. A hero in the void falls; one inside a wall is pushed out or
	# sticks. Either way the answer is only visible after the solver has had its say.
	for _i4: int in 150:
		await physics_frame
	var ok: bool = _is_in_room(hero, l2)

	if CONTROL_SEEDS.has(seed_value):
		await _run_controls(hero, l2)
	return {"reached": true, "ok": ok,
		"hp": arrived_hp, "max_hp": arrived_max if arrived_max > 0 else maxhp,
		"hurt": hurt}


## One placement that MUST read green and one that MUST read red, both through
## `_is_in_room` — the same predicate the real measurement used.
func _run_controls(hero: Node2D, l2: LayoutDef) -> void:
	hero.global_position = l2.hero_start
	hero.set(&"velocity", Vector2.ZERO)
	for _i: int in 90:
		await physics_frame
	_controls_run += 1
	if not _is_in_room(hero, l2):
		_instrument_ok = false
		printerr("  CONTROL A FAILED: a hero placed on the floor's own hero_start reads as lost")

	hero.global_position = Vector2(5000.0, 5000.0)
	hero.set(&"velocity", Vector2.ZERO)
	for _i2: int in 10:
		await physics_frame
	_controls_run += 1
	if _is_in_room(hero, l2):
		_instrument_ok = false
		printerr("  CONTROL B FAILED: a hero teleported far outside the room reads as fine")


## Where a body standing on the floor's exit actually sits. The exit MARKER is drawn
## 38 px above the surface it belongs to, so the body centre is that much down, less
## half its own box — which is true of a ledge exit and a ground exit alike, and is why
## there is no branch here.
##
## ⚠ GETTING THIS WRONG LOOKS EXACTLY LIKE THE BUG UNDER TEST. A first cut derived the
## stance from the room's ground plane instead (`room_h - 8 + 20`), which is BELOW the
## bottom wall's underside — so the hero was placed in the void, fell, and no portal
## ever fired. The suite reported "the climb path is blocked" on every seed, which is
## indistinguishable from a real regression. The fixture must stand the hero where the
## game would.
func _stance_at_exit(l: LayoutDef) -> Vector2:
	return Vector2(l.exit_point.x, l.exit_point.y + 38.0 - HERO_BOX.y * 0.5)


## Can this body actually STAND on the floor it was just moved to? Two questions, and
## both matter: inside the room's bounds, and resting on something. `is_on_floor()`
## alone would accept a hero standing on a ledge in the wrong room; bounds alone would
## accept one still falling through it.
func _is_in_room(hero: Node2D, l: LayoutDef) -> bool:
	var p: Vector2 = hero.global_position
	if p.y > l.room_size.y + OUT_MARGIN or p.y < -OUT_MARGIN:
		return false
	if p.x < -OUT_MARGIN or p.x > l.room_size.x + OUT_MARGIN:
		return false
	if hero.has_method(&"is_on_floor") and not bool(hero.call(&"is_on_floor")):
		return false
	return true


func _hero() -> Node2D:
	for h: Node in get_nodes_in_group(&"hero"):
		if h is Node2D:
			return h as Node2D
	return null


func _snapshot_climber() -> void:
	_had_climber = FileAccess.file_exists(CLIMBER)
	if not _had_climber:
		return
	var f: FileAccess = FileAccess.open(CLIMBER, FileAccess.READ)
	if f != null:
		_climber_backup = f.get_as_text()
		f.close()


func _restore_climber() -> void:
	if not _had_climber:
		# The run created one where the player had none — remove it rather than leave
		# a save this suite invented.
		if FileAccess.file_exists(CLIMBER):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CLIMBER))
		return
	var f: FileAccess = FileAccess.open(CLIMBER, FileAccess.WRITE)
	if f == null:
		_fails += 1
		printerr("  FAIL: could not restore the player's climber.json — it may be dirty")
		return
	f.store_string(_climber_backup)
	f.close()
	var g: FileAccess = FileAccess.open(CLIMBER, FileAccess.READ)
	if g != null:
		var back: String = g.get_as_text()
		g.close()
		if back != _climber_backup:
			_fails += 1
			printerr("  FAIL: climber.json did not restore byte-for-byte")


## ══════════════════════════════════════════════════════════════════════════════
## CLEARING A FLOOR HEALS YOU. Maker: *"when you pass a floor in the tower you can
## fully heal as entering the next floor please"*.
##
## Rides the SAME genuine climb the test above walks — `enter_run`, clear the room,
## stand on the exit, let the portal's own overlap poll fire the advance — with the
## hero cut to a third of its bar on the way in. No shortcut: if the heal were wired
## to some path other than the one a player actually takes, this would still be red.
func _test_clearing_a_floor_heals_you() -> void:
	_expect(not _heals.is_empty(),
		"at least one climb was walked, or there is nothing to judge")
	for r: Dictionary in _heals:
		if not bool(r.get("reached", false)):
			continue
		var hurt: int = int(r.get("hurt", 0))
		var maxhp: int = int(r.get("max_hp", 0))
		var got: int = int(r.get("hp", 0))
		# The control: the wound really was applied, or "arrived at full" is vacuous.
		_expect(hurt > 0 and hurt < maxhp,
			"the hero was actually wounded before the advance (%d/%d)" % [hurt, maxhp])
		_expect(got >= maxhp,
			"arrived on the next floor at FULL health — went in at %d/%d, arrived %d/%d"
				% [hurt, maxhp, got, maxhp])
	_completes("clearing_a_floor_heals_you")
