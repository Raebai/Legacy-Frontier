# "REWORK SHADOW SO IT ROOTS IN PLACE" — is the root actually a ROOT?
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice_test_shadow_root_pins.gd
#
# The maker's ask is mechanically specific: *"rework shadow so it roots in place"* —
# the target STOPS MOVING, as opposed to being slowed, dragged or pulled. `ShadowRoot.gd`
# claims to do exactly that, and its header even describes pinning out "the residual
# 32% freeze-drift" by easing the victim back to a catch anchor.
#
# ⚠ A CLAIM IN A HEADER IS NOT A MEASUREMENT. This codebase's recorded lesson is that
# "a confident comment described scoring that was never written", so the pin is
# measured here against a victim that FIGHTS IT: the dummy below re-writes its own
# position every single frame, away from the anchor, at a full walking speed. If the
# root only stopped a body that was already standing still it would pass a naive
# test and fail in the one situation the spell exists for.
#
# The number that matters is DRIFT: how far the victim ends up from where it was
# caught, over the whole grip. A slow is not a root, so the bar is px, not "less than
# it would have been".
#
# ⚠ NO class_name FOR ShadowRoot — its cast path names the `Sfx` autoload, which is
# not a global identifier at compile time in a `--script` harness. Load by path.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_spell_buttons.gd for the write-up) ──
const TESTS: Array[String] = [
	"the_grasp_catches_at_all",
	"a_caught_body_cannot_walk_away",
	"stepping_off_the_mark_dodges_it",
	"jumping_the_tendrils_dodges_it",
]

const SHADOW_ROOT_PATH: String = "res://scripts/combat/ShadowRoot.gd"

## The ground plane's surface. Bodies stand `STAND_LIFT` above it, the way a real
## fighter's origin sits above its feet.
const FLOOR_Y: float = 0.0
const STAND_LIFT: float = 10.0
const STAGE := Vector2(600.0, FLOOR_Y - STAND_LIFT)
## The shipped `void_zone` SpellDef's radius — the grasp half-width at the mark.
const GRASP_RADIUS: float = 64.0
const GRASP_DAMAGE: int = 26
## How hard the victim below fights the pin, px/s. Hero.SPEED, i.e. a body running
## flat out for the whole grip.
const ESCAPE_SPEED: float = 210.0
## What counts as ROOTED. A body walking freely covers 210 px/s for the 1.5 s grip =
## 315 px, so anything in this range is a root and not a slow. Deliberately not zero:
## the pin is an ease (`lerpf(..., 14.0 * delta)`), so a body shoving itself sideways
## every frame settles a few px off the anchor rather than exactly on it.
const ROOTED_PX: float = 24.0

var _fails: int = 0
var _completed: Dictionary = {}
var _root: GDScript = null
var _arena: Node2D = null


## A body that ACTIVELY RUNS from the anchor every frame. The root has to beat this,
## not merely coexist with a body that was not going anywhere.
class Runner extends Node2D:
	var hp: int = 900
	var statuses: int = 0
	var escape_per_frame: float = 0.0

	func take_damage(amount: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
		hp -= amount

	func apply_status(_element: int, _hard: bool = true) -> void:
		statuses += 1

	func apply_knockback(_v: Vector2) -> void:
		pass

	## Runs AFTER ShadowRoot's own pin: the spell sets `process_priority` high for
	## exactly this reason (a hero writes its position in its own step, and whoever
	## runs last wins). Fighting the pin from the later slot is the harder case and
	## the realistic one.
	func _process(delta: float) -> void:
		global_position.x += escape_per_frame * delta


func _initialize() -> void:
	root.size = Vector2i(1366, 768)
	create_timer(180.0).timeout.connect(func() -> void:
		printerr("FAIL: harness watchdog fired — a test coroutine died before the end")
		quit(1))
	_run()


func _run() -> void:
	await process_frame
	_root = load(SHADOW_ROOT_PATH) as GDScript
	_arena = Node2D.new()
	_arena.name = "Arena"
	root.add_child(_arena)
	_build_floor()
	# ⚠ AND THE PHYSICS SERVER HAS TO SEE IT. A collider added this frame is not in
	# the space until the next physics step, so the FIRST test — and only the first —
	# ran its ground walk against an empty world and got the caster's-feet fallback.
	# The symptom was "the grasp caught nobody" in test one while an identical body in
	# test four was caught fine, which reads as a catch-band bug and is not one.
	await physics_frame
	await physics_frame
	await _test_the_grasp_catches_at_all()
	await _test_a_caught_body_cannot_walk_away()
	await _test_stepping_off_the_mark_dodges_it()
	await _test_jumping_the_tendrils_dodges_it()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Shadow root pin tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Shadow root pin tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ---- harness ----------------------------------------------------------------

## ⚠ THE FLOOR IS LOAD-BEARING, AND ITS ABSENCE COST A DEBUG CYCLE. ShadowRoot
## resolves its grasp point through `SpellWorld.ground_path`, which walks the floor
## from the caster and stops at the first sample with nothing beneath it. In an empty
## headless arena there is nothing beneath ANY sample, so the path comes back empty
## and the documented degenerate case fires: "no floor anywhere along the run — grasp
## at the caster's feet". The mark then lands 200 px from where the test aimed it and
## the grasp catches nobody — which reads exactly like a broken catch band.
##
## So this suite gives the world a floor. It is not scenery: this spell is defined by
## running ALONG the ground, and testing it without ground tests a different spell.
func _build_floor() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_arena.add_child(body)
	body.global_position = Vector2(STAGE.x, FLOOR_Y + 40.0)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4000.0, 80.0)   # top surface lands exactly on FLOOR_Y
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.add_child(cs)


func _runner(where: Vector2, escape: float = 0.0) -> Runner:
	var r := Runner.new()
	r.escape_per_frame = escape
	# Priority above the spell's own pin, so the victim's write is the LAST one each
	# frame. See Runner._process.
	r.process_priority = 300
	_arena.add_child(r)
	r.global_position = where
	r.add_to_group("enemy")
	return r


## Erupt a root from `from` aimed so the grasp lands on `at`. `aim` is a VECTOR whose
## x-magnitude is the run length (see ShadowRoot.erupt), not a unit direction — the
## one genuinely surprising thing about this spell's signature.
func _erupt(from: Vector2, at: Vector2) -> Node2D:
	var s: Node2D = _root.new()
	_arena.add_child(s)
	s.set("element_id", Elements.Element.SHADOW)
	s.set("spell_tier", SpellTier.Tier.HEAVY)
	s.call("erupt", from, at - from, Color(0.6, 0.35, 0.9), GRASP_RADIUS, GRASP_DAMAGE)
	return s


## Run the spell until it frees itself, or until `limit` seconds of ITS OWN clock
## have passed. The headless loop is uncapped, so a frame count is not a duration.
func _run_spell(s: Node2D, limit: float) -> void:
	for i in 4000:
		if not is_instance_valid(s) or float(s.get("_elapsed")) >= limit:
			return
		await process_frame


## Tear down between tests — but NEVER the floor, which every test needs and which
## is built once. Identified by type rather than by name so a rename cannot silently
## start deleting it (and a deleted floor fails as "the grasp caught nobody", which
## is the least informative failure this suite can produce).
func _clear() -> void:
	for child: Node in _arena.get_children():
		if child is StaticBody2D:
			continue
		child.free()


# ---- the tests --------------------------------------------------------------

## THE INSTRUMENT CHECK. Every assertion below is about a body being HELD, and a
## grasp that caught nobody would make all of them pass vacuously — "it didn't move"
## is trivially true of a body the spell never touched.
func _test_the_grasp_catches_at_all() -> void:
	var v: Runner = _runner(STAGE)
	var s: Node2D = _erupt(STAGE - Vector2(200.0, 0.0), STAGE)
	await _run_spell(s, 0.7)   # past SURGE_TIME (0.5), inside the grip
	var victims: Array = s.get("_victims") as Array
	_expect(victims.size() == 1, "the grasp caught the body standing on the mark (%d)"
		% victims.size())
	_expect(v.hp < 900, "...and it hurt (hp %d)" % v.hp)
	_expect(v.statuses >= 2,
		"...and applied BOTH channels — EARTH is the root, SHADOW is the weaken + tint (%d)"
			% v.statuses)
	_clear()
	_completes("the_grasp_catches_at_all")


## THE ASK, MEASURED. A body running flat out for the whole grip, against the pin.
func _test_a_caught_body_cannot_walk_away() -> void:
	# ⚠ IT STANDS STILL THROUGH THE SURGE AND ONLY THEN RUNS, and that ordering is
	# the spell working rather than the test being kind. The surge is a 0.5 s
	# telegraph; a body already running at 210 px/s covers 105 px in it and is out of
	# the 64 px band before the claws close — which is the ADVERTISED dodge, asserted
	# on its own two tests below. Starting the sprint at the snap is the only way to
	# ask the question this test is about: once the dark HAS you, can you walk out?
	var v: Runner = _runner(STAGE, 0.0)
	var s: Node2D = _erupt(STAGE - Vector2(200.0, 0.0), STAGE)
	await _run_spell(s, 0.55)          # just past the snap: the anchor is set
	v.escape_per_frame = ESCAPE_SPEED
	# ⚠ THE MEASUREMENT IS VACUOUS WITHOUT THIS. "It did not move far" is trivially
	# true of a body the grasp never caught, and a missed catch is exactly how this
	# suite failed while it was being written.
	_expect((s.get("_victims") as Array).size() == 1,
		"the runner was actually CAUGHT before its drift is measured")
	var anchor: Vector2 = v.global_position
	var t0: float = float(s.get("_elapsed")) if is_instance_valid(s) else 0.0
	var worst: float = 0.0
	for i in 4000:
		if not is_instance_valid(s):
			break
		var t: float = float(s.get("_elapsed"))
		if t >= t0 + 1.2:
			break
		worst = maxf(worst, absf(v.global_position.x - anchor.x))
		await process_frame
	var drift: float = absf(v.global_position.x - anchor.x)
	var free_run: float = ESCAPE_SPEED * 1.2
	print("[measure] shadow root: victim ran at %.0f px/s for 1.20 s of grip — "
		% ESCAPE_SPEED
		+ "drifted %.1f px (worst %.1f px) against %.0f px unrooted"
		% [drift, worst, free_run])
	print("[measure] shadow root: the pin removes %.1f%% of the escape"
		% (100.0 * (1.0 - worst / free_run)))
	_expect(worst < ROOTED_PX,
		"a rooted body STOPS — it wandered %.1f px, and a root that lets you drift is a slow"
			% worst)
	_clear()
	_completes("a_caught_body_cannot_walk_away")


## THE DODGE, half one: the surge is 0.5 s of tell and the mark is drawn on the
## floor. Step off it and the claws close on empty air. This is the assertion that
## keeps the root honest under the "everything must be dodgeable" directive — a root
## you cannot avoid is the worst possible spell to make unavoidable.
func _test_stepping_off_the_mark_dodges_it() -> void:
	# Just outside the grasp half-width, plus the default forgiveness ring the band
	# test adds for the target's own size.
	var out: float = GRASP_RADIUS + SpellTargets.hit_margin(null) + 8.0
	var v: Runner = _runner(STAGE + Vector2(out, 0.0))
	var s: Node2D = _erupt(STAGE - Vector2(200.0, 0.0), STAGE)
	await _run_spell(s, 0.7)
	_expect((s.get("_victims") as Array).is_empty(),
		"a body %.0f px off the mark is NOT caught" % out)
	_expect(v.hp == 900, "...and takes nothing (hp %d)" % v.hp)
	_clear()
	_completes("stepping_off_the_mark_dodges_it")


## THE DODGE, half two: the tendrils reach CATCH_HEIGHT and no higher, and that
## constant feeds the DRAWING as well as the catch (they were 46 vs 100 once — the
## grasp reached more than twice as high as any picture of it). A jump clears it.
func _test_jumping_the_tendrils_dodges_it() -> void:
	var h: float = float(_root.get_script_constant_map()["CATCH_HEIGHT"])
	var v: Runner = _runner(STAGE - Vector2(0.0, h + 20.0))
	var s: Node2D = _erupt(STAGE - Vector2(200.0, 0.0), STAGE)
	await _run_spell(s, 0.7)
	_expect((s.get("_victims") as Array).is_empty(),
		"a body above CATCH_HEIGHT (%.0f px) has jumped the tendrils" % h)
	_clear()
	# ...and a body just INSIDE that height is still caught, so the assertion above
	# is about the height and not about the test standing somewhere unreachable.
	var low: Runner = _runner(STAGE - Vector2(0.0, h * 0.4))
	var s2: Node2D = _erupt(STAGE - Vector2(200.0, 0.0), STAGE)
	await _run_spell(s2, 0.7)
	_expect((s2.get("_victims") as Array).size() == 1,
		"...while a body still inside that height IS caught")
	_expect(low.hp < 900, "...and takes the grasp")
	_clear()
	_completes("jumping_the_tendrils_dodges_it")
