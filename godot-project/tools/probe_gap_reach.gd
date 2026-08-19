extends SceneTree
## SLICE 0 OF THE DESTRUCTIBLE MAP — HOW WIDE A HOLE CAN A FIGHTER ACTUALLY CROSS?
##
## The load-bearing number for the feature. The maker has ruled that an uncrossable gap
## is an ACCEPTED outcome, which means the game is allowed to sever the stage — but the
## rule for how many 16 px chunks a hit may remove, and everything the bots are taught
## about crossing, is calibrated against this distance. The spec says nothing after
## slice 0 may use a derived number.
##
## ⚠ FOUR THINGS BROKE THIS PROBE BEFORE IT READ ANYTHING. All four are real facts
## about the engine and the codebase, recorded so nobody pays for them twice:
##
##   1. `Input.action_press` DOES NOT DRIVE A HERO. `Hero` reads global `Input` only
##      when its `controller` is null. The seam is `controller`, the one `BotController`
##      uses. Install a scripted one.
##   2. THAT CONTROLLER MUST IMPLEMENT `tick(body, clock)`. `Hero._physics_process`
##      calls it at the top of the step; a missing method aborts the whole physics tick
##      and the body never moves at all.
##   3. `tick` MUST NOT AGE THE JUST-PRESSED EDGE. It runs before the hero polls
##      anything, so copying held-into-prev there makes `just_pressed` compare a set
##      with itself — and the jump is read with `_just(&"jump")`, so it never fires.
##      The edge is aged by `press()`, at the moment the caller changes the buttons.
##   4. THE JUMP MUST BE HELD. `Hero` has VARIABLE JUMP HEIGHT: it halves upward
##      velocity on the frame jump is RELEASED while still rising. A one-frame press
##      therefore measures a THIRD of the real arc — this is the same fault that once
##      capped every bot in the game at a 36 px jump against a human's 105 px, and
##      `BotController._hold_the_jump` exists solely to answer it.
##
## Run:
##   godot --headless --path godot-project --script tools/probe_gap_reach.gd

const ARENA := "res://scenes/combat/VersusArena.tscn"
const CHUNK: float = 16.0
## Room to reach top speed before the lip. `Hero.SPEED` is 210 px/s and acceleration is
## not instant, so a short run-up would measure the acceleration curve, not the jump.
const RUNUP: float = 460.0
## Hold the jump at least this long — see fault 4. `BotController` holds 18.
const JUMP_HOLD: int = 18
## Cap on the settle loop. The body is dropped a little way onto the floor and we wait
## for the engine to agree it has landed; this only bounds a hang.
const SETTLE_MAX: int = 120
const FLIGHT: int = 240
const CLASSES: Array[int] = [0, 2, 3, 6, 8]
const CLASS_NAMES: Array[String] = [
	"Arcanist", "Brawler", "Juggernaut", "Stormcaller", "Swordsaint",
]

## ⚠ FAULT 6, AND IT IS WHY THIS MEASURES ON ITS OWN FLOOR INSTEAD OF THE STAGE.
## Measured on the real duel stage the numbers were nonsense in two different ways at
## once: the Arcanist read 359 px with an airtime of 0.000 s (it never came back down —
## it LANDED ON THE MID PLATFORM, which is higher than the floor it left, so the
## "returned to takeoff height" test could never fire), while the Brawler read 112 px
## because its arc happened to clear cleanly. A stage with terraces and three breakable
## ledges cannot answer "how far is a flat jump" — the geometry is the confound.
##
## So the bench: one long flat slab in empty air well above the stage, on the same
## collision layer the terrain uses. Nothing overhead, nothing to land on early,
## nothing to clip a head on. The number that comes off it is a property of the BODY,
## which is what the destructible-map rule actually needs.
const BENCH_Y: float = 300.0
const BENCH_X0: float = 60.0
const BENCH_X1: float = 1500.0
const BENCH_THICK: float = 60.0


## The smallest thing satisfying what `Hero` asks of a controller.
class ScriptedController extends RefCounted:
	var held: Dictionary = {}
	var _prev: Dictionary = {}

	## Required (fault 2), and deliberately empty (fault 3).
	func tick(_body: Node, _clock: float) -> void:
		pass

	## Set this frame's buttons, remembering last frame's so `just_pressed` has an edge.
	func press(next: Dictionary) -> void:
		_prev = held
		held = next

	func pressed(action: StringName) -> bool:
		return bool(held.get(action, false))

	func just_pressed(action: StringName) -> bool:
		return bool(held.get(action, false)) and not bool(_prev.get(action, false))

	func just_released(action: StringName) -> bool:
		return not bool(held.get(action, false)) and bool(_prev.get(action, false))

	func axis(neg: StringName, pos: StringName) -> float:
		return (1.0 if pressed(pos) else 0.0) - (1.0 if pressed(neg) else 0.0)

	func vector(nx: StringName, px: StringName, ny: StringName, py: StringName) -> Vector2:
		return Vector2(axis(nx, px), axis(ny, py))

	func aim_point(from: Vector2) -> Vector2:
		return from + Vector2.RIGHT * 100.0


var _rows: Array[String] = []
var _ctl: ScriptedController = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var arena: Node = (load(ARENA) as PackedScene).instantiate()
	root.add_child(arena)
	for _i in 40:
		await physics_frame
	var heroes: Array = root.get_tree().get_nodes_in_group(&"hero")
	if heroes.is_empty():
		print("PROBE ABORTED: no hero in the arena scene")
		quit()
		return
	var h: Node2D = heroes[0]
	# ⚠ PARK the other fighter, do NOT free it — `VersusArena._update_showcase_camera`
	# and `_poll_showcase_end` both assign through a held reference every frame and
	# throw "invalid previously freed instance" twice a tick if it is gone.
	for other: Node in heroes:
		if other != h and other is Node2D:
			(other as Node2D).global_position = Vector2(1850.0, 400.0)
			other.set_physics_process(false)
	for e: Node in root.get_tree().get_nodes_in_group(&"enemy"):
		e.queue_free()
	_ctl = ScriptedController.new()
	h.set("controller", _ctl)
	_build_bench(arena)

	# ══ CONTROLS ═══════════════════════════════════════════════════════════════
	# Two of them, because "0 px" has been the wrong answer twice for two different
	# reasons and a single control could not tell them apart.
	var ran: float = await _control_run(h)
	print("CONTROL 1 — run:  holding move_right 40 ticks moved the body %.1f px (~%.0f px/s)"
		% [ran, ran / (40.0 / 60.0)])
	var rise: float = await _control_jump(h)
	print("CONTROL 2 — jump: a held jump reached %.1f px of apex" % rise)
	if ran < 40.0:
		print("PROBE ABORTED: the controller is not driving the body.")
		quit()
		return
	if rise < 40.0:
		print("PROBE ABORTED: the body is not leaving the ground — measure nothing.")
		quit()
		return

	for i in CLASSES.size():
		var r: Dictionary = await _arc(h, CLASSES[i])
		_rows.append("  %-12s flat %6.1f px (%4.1f chunks)   apex %5.1f px   airtime %.3f s"
			% [CLASS_NAMES[i], r["flat"], float(r["flat"]) / CHUNK, r["apex"], r["air"]])

	print("\n== FLAT-GAP REACH, MEASURED THROUGH THE REAL CONTROLLER SEAM ==")
	for r in _rows:
		print(r)
	print("\nA hole wider than a class's FLAT figure cannot be crossed by that class.")
	print("At 16 px per chunk, that is the chunk count a single hit may not exceed if")
	print("the stage is to stay connected — which the maker has ruled is optional.")
	quit()


## One long flat slab in clear air — see the note on BENCH_Y.
func _build_bench(arena: Node) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(BENCH_X1 - BENCH_X0, BENCH_THICK)
	shape.shape = rect
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = Vector2(
		(BENCH_X0 + BENCH_X1) * 0.5, BENCH_Y + BENCH_THICK * 0.5)


## Settle the body onto the floor and return the y it rests at. Waits for the engine to
## agree rather than assuming: the previous version waited a fixed 10 ticks while an
## 80 px drop takes ~15, captured the lip height MID-FALL, and then failed its own
## "still at or above takeoff" test on every subsequent frame — reporting 0.0 px.
func _settle(h: Node2D, at: Vector2) -> float:
	h.global_position = at
	h.set("velocity", Vector2.ZERO)
	h.set("hp", h.get("max_hp"))
	for _i in SETTLE_MAX:
		_ctl.press({})
		await physics_frame
		if bool(h.call("is_on_floor")):
			break
	return h.global_position.y


func _control_run(h: Node2D) -> float:
	await _settle(h, Vector2(600.0, BENCH_Y - 120.0))
	var x0: float = h.global_position.x
	for _i in 40:
		_ctl.press({&"move_right": true})
		await physics_frame
	_ctl.press({})
	return h.global_position.x - x0


func _control_jump(h: Node2D) -> float:
	var y0: float = await _settle(h, Vector2(600.0, BENCH_Y - 120.0))
	var apex: float = 0.0
	for i in 90:
		_ctl.press({&"jump": true} if i < JUMP_HOLD else {})
		await physics_frame
		apex = maxf(apex, y0 - h.global_position.y)
	_ctl.press({})
	return apex


## Run at full tilt, jump at the lip holding the button, and measure how far the body
## travels before it drops back to the height it left from. That distance IS the flat
## gap it can cross — no binary search and no far-edge geometry to get wrong.
func _arc(h: Node2D, cls: int) -> Dictionary:
	if h.has_method("configure_class"):
		h.call("configure_class", cls)
	var lip_x: float = 700.0
	# ⚠ THE TAKEOFF HEIGHT IS READ AT THE LIP, NOT AT THE START OF THE RUN-UP. Fault 5,
	# and the subtlest of them: a 460 px run-up from x=640 begins at x=180, which is on
	# the stage's LEFT MOUND (surface 700, x 40..250). The body settles up there, runs
	# off it, and lands on the main floor 80 px lower — so a takeoff height sampled at
	# the start is 70 px ABOVE where the jump actually happens, and the "back down to
	# takeoff height" test then fires on the third frame of every jump. That is what
	# produced flat readings of 11-19 px with an apex of 0.0 while the debug trace
	# showed a perfectly healthy jump (velocity -740, y climbing).
	await _settle(h, Vector2(lip_x - RUNUP, BENCH_Y - 120.0))
	var lip_y: float = 0.0

	var jumped_at: int = -1
	var flat: float = 0.0
	var apex: float = 0.0
	for i in FLIGHT:
		var held: Dictionary = {&"move_right": true}
		if jumped_at < 0 and h.global_position.x >= lip_x:
			jumped_at = i
			lip_y = h.global_position.y      # the surface it is ACTUALLY leaving
		# Held for JUMP_HOLD frames from takeoff — see fault 4.
		if jumped_at >= 0 and i - jumped_at < JUMP_HOLD:
			held[&"jump"] = true
		_ctl.press(held)
		await physics_frame
		if jumped_at < 0:
			continue
		apex = maxf(apex, lip_y - h.global_position.y)
		# ⚠ LANDING IS DETECTED BY THE FLOOR, NOT BY A HEIGHT COMPARISON. Fault 7:
		# `y >= lip_y` never became true because landing depenetration leaves the body
		# a fraction of a pixel HIGHER than it took off from, so every class ran out
		# the full flight loop and reported its run distance instead of its jump.
		if i > jumped_at + 4 and bool(h.call("is_on_floor")):
			flat = h.global_position.x - lip_x
			return {"flat": flat, "apex": apex,
				"air": float(i - jumped_at) / 60.0}
	_ctl.press({})
	return {"flat": h.global_position.x - lip_x, "apex": apex, "air": 0.0}
