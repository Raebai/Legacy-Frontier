# Run: godot --headless --path godot-project --script tools/slice_test_exit_pad.gd
#
# THE EXIT PAD — the way out of a cleared floor, as a teleport pad you stand on.
#
# What this suite is defending, in order of how badly it would hurt to get wrong:
#   1. The pad is still an `ExitPortal`. `Arena._return_portal` is a TYPED field and
#      the whole confirm/re-arm/teardown path hangs off `taken`. If the pad ever
#      stops being one, the hook stops compiling — better here than in a playtest.
#   2. Its rings can SEE a hero. A `Hero` is on collision layer 2 and an `Area2D`'s
#      default mask is bit 1 alone, so a ring built without thinking about it is
#      silently, permanently blind. This suite proves the trap is real AND that the
#      pad avoids it — see `default_area_mask_is_blind_to_a_hero`.
#   3. The beam is at full brightness BEFORE `taken` is emitted. `Arena` frees this
#      node the instant it hears `taken`, so a beam played afterwards is a beam
#      nobody ever sees. This is the ordering the maker actually asked for.
#   4. A hero the pad took hold of is ALWAYS handed back when the pad is freed.
#      Getting this wrong strands a player frozen and half-transparent in mid-air.
#
# The script is reached BY PATH and everything on it by name (`.call` / `.get` /
# `.set`) — the capture-tool idiom. A `--script` harness has no autoloads and a
# brand-new script has no entry in `global_script_class_cache.cfg`, so naming
# `ExitPad` directly would be a compile error before frame one.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_one_screen.gd for the full write-up) ──
# A dead member read ABORTS the enclosing function and is not a failure by itself,
# so every test records that it reached its own last line; a name missing from
# `_completed` fails the suite BY ABSENCE.
const TESTS: Array[String] = [
	"pad_is_an_exit_portal",
	"default_area_mask_is_blind_to_a_hero",
	"pad_rings_watch_the_hero_layer",
	"walking_onto_the_pad_takes_you_once",
	"the_beam_is_at_full_when_taken_fires",
	"standing_beside_the_pad_never_fires",
	"freeing_the_pad_hands_the_hero_back",
	"the_talk_key_takes_you_too",
	"a_downed_ally_keeps_the_talk_key",
]

const PAD_PATH: String = "res://scripts/combat/ExitPad.gd"
const PORTAL_PATH: String = "res://scripts/combat/ExitPortal.gd"
## The hero's authored collision layer, restated from `scenes/combat/Hero.tscn`. If
## that ever changes, this suite is the thing that should go red.
const HERO_LAYER: int = 2
## The hero's authored hurtbox, ditto.
const HERO_BOX: Vector2 = Vector2(18.0, 18.0)

var _fails: int = 0
var _completed: Dictionary = {}
var _pad_script: GDScript = null

## Signal bookkeeping for the pad currently under test.
var _taken_count: int = 0
var _beam_at_take: float = -1.0
var _pad: Area2D = null


func _initialize() -> void:
	_pad_script = load(PAD_PATH) as GDScript
	_run()


func _run() -> void:
	await process_frame
	_test_pad_is_an_exit_portal()
	await _test_default_area_mask_is_blind_to_a_hero()
	_test_pad_rings_watch_the_hero_layer()
	await _test_walking_onto_the_pad_takes_you_once()
	await _test_the_beam_is_at_full_when_taken_fires()
	await _test_standing_beside_the_pad_never_fires()
	await _test_freeing_the_pad_hands_the_hero_back()
	await _test_the_talk_key_takes_you_too()
	await _test_a_downed_ally_keeps_the_talk_key()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Exit-pad tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Exit-pad tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ─────────────────────────────────────────────────────────── harness helpers ──

## A pad wired exactly the way `Arena._build_return_portal` wires the thing it
## replaces — same three properties, same signal connection. If the hook and this
## drift apart, this suite is testing a pad the game never builds.
func _build_pad() -> Area2D:
	_taken_count = 0
	_beam_at_take = -1.0
	var pad: Area2D = _pad_script.new() as Area2D
	pad.set("portal_label", "LEAVE THE TOWER")
	pad.set("ring_color", Color(1.0, 0.85, 0.4))
	pad.set("trigger_group", "hero")
	root.add_child(pad)
	pad.global_position = Vector2(600.0, 500.0)
	pad.connect("taken", Callable(self, "_on_taken"))
	_pad = pad
	return pad


func _on_taken() -> void:
	_taken_count += 1
	if _pad != null and is_instance_valid(_pad):
		_beam_at_take = float(_pad.get("_beam"))


func _spawn_hero(at: Vector2, downed: bool = false) -> CharacterBody2D:
	var h := _HeroStub.new()
	h.downed = downed
	root.add_child(h)
	h.global_position = at
	return h


## Tear the whole cast down between tests. `_someone_is_down` and
## `_nearest_trigger_body` both scan the "hero" group tree-wide, so a stub left
## lying around from an earlier test would quietly answer a later one's questions.
func _teardown(nodes: Array) -> void:
	for n: Node in nodes:
		if n != null and is_instance_valid(n):
			n.free()
	_pad = null
	await process_frame


## Let the world turn. `ARM_DELAY` and the beam rise are both real-time clocks, so
## the suite has to actually spend the time rather than poke the flags.
func _tick(seconds: float) -> void:
	await create_timer(seconds).timeout


## Long enough for the pad to arm AND for a full beam rise on top.
func _arm_and_rise() -> float:
	return float(_pad_script.ARM_DELAY) + 1.0 / float(_pad_script.BEAM_RISE) + 0.25


# ───────────────────────────────────────────────────────────────── the tests ──

## THE HOOK'S PRECONDITION. `Arena` holds this in a field typed `ExitPortal`, hands
## it `portal_label` / `ring_color` / `trigger_group`, and hangs the confirm card off
## `taken`. All four have to still be true of the pad.
func _test_pad_is_an_exit_portal() -> void:
	var base: Script = _pad_script.get_base_script()
	_expect(base != null and base.resource_path == PORTAL_PATH,
		"ExitPad extends ExitPortal (Arena's `_return_portal: ExitPortal` still takes it)")
	var pad: Area2D = _pad_script.new() as Area2D
	_expect(pad != null, "the pad instantiates as an Area2D")
	_expect(pad.has_signal("taken"), "the pad still carries `taken` — the one way out")
	pad.set("portal_label", "LEAVE THE TOWER")
	pad.set("ring_color", Color(1.0, 0.85, 0.4))
	pad.set("trigger_group", "hero")
	_expect(String(pad.get("portal_label")) == "LEAVE THE TOWER",
		"the pad takes the label the Arena gives it")
	_expect(String(pad.get("trigger_group")) == "hero",
		"the pad takes the trigger group the Arena gives it")
	pad.free()
	_completes("pad_is_an_exit_portal")


## THE TRAP, PROVEN RATHER THAN ASSERTED. This is the failure `ArmoryStation` and
## `TowerDoor` each carry a paragraph about: an `Area2D` left on its default mask
## cannot see a body on layer 2, and it fails SILENTLY — no error, no warning, just
## a trigger that never triggers. Documented here so the next person who "tidies up"
## `BODY_MASK` finds out immediately.
func _test_default_area_mask_is_blind_to_a_hero() -> void:
	var blind := Area2D.new()
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	cs.shape = circle
	blind.add_child(cs)
	root.add_child(blind)
	blind.global_position = Vector2(200.0, 200.0)
	var h: CharacterBody2D = _spawn_hero(Vector2(200.0, 200.0))
	await physics_frame
	await physics_frame
	_expect(blind.collision_mask == 1,
		"an Area2D's default mask really is bit 1 alone")
	_expect(blind.get_overlapping_bodies().is_empty(),
		"a default-mask Area2D is BLIND to a hero on layer %d — the silent trap" % HERO_LAYER)
	await _teardown([blind, h])
	_completes("default_area_mask_is_blind_to_a_hero")


## ...and the pad does not fall into it. Both rings, checked separately: the wide
## hint ring lives on the pad's own body, the tight step ring is a child.
func _test_pad_rings_watch_the_hero_layer() -> void:
	var pad: Area2D = _build_pad()
	var hero_bit: int = HERO_LAYER
	_expect(pad.collision_mask & hero_bit == hero_bit,
		"the pad's hint ring watches the hero layer")
	_expect(pad.collision_mask & 1 == 1,
		"...without dropping layer 1 (the hub body it shares a grammar with)")
	var step: Area2D = pad.get_node_or_null("Step") as Area2D
	_expect(step != null, "the pad has its tight `Step` ring")
	if step != null:
		_expect(step.collision_mask & hero_bit == hero_bit,
			"the pad's step ring watches the hero layer")
	# The step ring must be MUCH tighter than the hint ring, or "walk in" becomes
	# "be anywhere near it" and the middle of the room stops being walkable.
	_expect(float(_pad_script.ENTER_RADIUS) < float(_pad_script.HINT_RADIUS) * 0.5,
		"the step you take is far tighter than the ring that only lights the hint")
	_expect(float(_pad_script.ENTER_RADIUS) <= float(_pad_script.PAD_RADIUS),
		"the step ring is no wider than the disc you can actually see")
	pad.free()
	_pad = null
	_completes("pad_rings_watch_the_hero_layer")


## THE WHOLE POINT: stand on it, and it takes you — once, no matter how many frames
## the body sits there for.
func _test_walking_onto_the_pad_takes_you_once() -> void:
	var pad: Area2D = _build_pad()
	var h: CharacterBody2D = _spawn_hero(pad.global_position)
	await _tick(_arm_and_rise())
	_expect(_taken_count == 1,
		"standing on the pad emits `taken` exactly once (got %d)" % _taken_count)
	# ...and it stays once, however long a thumb rests on it.
	await _tick(0.3)
	_expect(_taken_count == 1, "the pad does not fire a second time while stood on")
	await _teardown([pad, h])
	_completes("walking_onto_the_pad_takes_you_once")


## THE ORDERING THE MAKER ASKED FOR. `Arena._on_return_taken` frees the pad on the
## emit, so the light has to be at its brightest by then or it is never seen at all.
## Also checks the hero was actually lifted on the way up, which is the other half of
## "it looks like you teleported".
func _test_the_beam_is_at_full_when_taken_fires() -> void:
	var pad: Area2D = _build_pad()
	var start := Vector2(600.0, 500.0)
	var h: CharacterBody2D = _spawn_hero(start)
	# Part-way up: the beam is burning and the hero has left the ground, but nothing
	# has been emitted yet.
	await _tick(float(_pad_script.ARM_DELAY) + 0.12)
	_expect(_taken_count == 0, "nothing is emitted while the beam is still climbing")
	_expect(float(pad.get("_beam")) > 0.0, "the beam is already burning mid-rise")
	_expect(h.global_position.y < start.y, "the hero is being lifted off the ground")
	_expect(h.modulate.a < 1.0, "the hero is fading out as the light takes them")
	await _tick(_arm_and_rise())
	_expect(_taken_count == 1, "the trip ends in exactly one `taken`")
	_expect(_beam_at_take >= 1.0,
		"the beam is at FULL when `taken` fires (was %.2f) — Arena frees the pad next"
			% _beam_at_take)
	await _teardown([pad, h])
	_completes("the_beam_is_at_full_when_taken_fires")


## The pad sits in the MIDDLE of the room, which is exactly where a player walks. So
## being near it must cost nothing: the hint lights, and that is all.
func _test_standing_beside_the_pad_never_fires() -> void:
	var pad: Area2D = _build_pad()
	# Inside the hint ring, comfortably outside the step ring (plus the hero's own
	# half-width, which is what actually decides the overlap).
	var beside: float = float(_pad_script.ENTER_RADIUS) + HERO_BOX.x + 20.0
	_expect(beside < float(_pad_script.HINT_RADIUS),
		"the test stands the hero inside the hint ring, as intended")
	var h: CharacterBody2D = _spawn_hero(pad.global_position + Vector2(beside, 0.0))
	await _tick(_arm_and_rise())
	_expect(_taken_count == 0, "standing BESIDE the pad does not end the run")
	_expect(bool(pad.get("_in_range")), "...but the hint is lit, so you know it is there")
	await _teardown([pad, h])
	_completes("standing_beside_the_pad_never_fires")


## THE SAFETY NET. This node does not choose when it dies — `Arena` frees it to raise
## the confirm card, and frees it again when the floor is torn down. A hero left
## frozen and transparent in mid-air is the worst bug this file can ship.
func _test_freeing_the_pad_hands_the_hero_back() -> void:
	var pad: Area2D = _build_pad()
	var start := Vector2(600.0, 500.0)
	var h: CharacterBody2D = _spawn_hero(start)
	await _tick(float(_pad_script.ARM_DELAY) + 0.12)
	_expect(not h.is_physics_processing(), "the pad froze the hero it took hold of")
	_expect(h.global_position != start, "...and had actually moved them")
	pad.queue_free()
	await process_frame
	await process_frame
	_expect(h.is_physics_processing(),
		"freeing the pad gives the hero their legs back")
	_expect(h.global_position.is_equal_approx(start),
		"...puts them back exactly where they stood (%s vs %s)"
			% [str(h.global_position), str(start)])
	_expect(is_equal_approx(h.modulate.a, 1.0), "...and gives them their body back")
	await _teardown([h])
	_completes("freeing_the_pad_hands_the_hero_back")


## Walking in is the maker's ask; the key is what a controller and the touch pad
## press. Both land in the same guarded `_enter`.
func _test_the_talk_key_takes_you_too() -> void:
	var pad: Area2D = _build_pad()
	var beside: float = float(_pad_script.ENTER_RADIUS) + HERO_BOX.x + 20.0
	var h: CharacterBody2D = _spawn_hero(pad.global_position + Vector2(beside, 0.0))
	await _tick(_arm_and_rise())
	_expect(_taken_count == 0, "still nothing, from standing alone")
	pad.call("_unhandled_input", _talk_press())
	await _tick(_arm_and_rise())
	_expect(_taken_count == 1, "pressing the interact key from inside the hint ring takes you")
	await _teardown([pad, h])
	_completes("the_talk_key_takes_you_too")


## ⚠ `talk` IS ALSO `Revive`'s CHANNEL KEY. A cleared floor can still have a downed
## teammate on it, and stealing their pick-up key to end the run for the party is the
## worst possible misfire. The fallback stands down entirely while anyone is down.
func _test_a_downed_ally_keeps_the_talk_key() -> void:
	var pad: Area2D = _build_pad()
	var beside: float = float(_pad_script.ENTER_RADIUS) + HERO_BOX.x + 20.0
	var up: CharacterBody2D = _spawn_hero(pad.global_position + Vector2(beside, 0.0))
	var down: CharacterBody2D = _spawn_hero(
		pad.global_position + Vector2(beside + 60.0, 0.0), true)
	await _tick(_arm_and_rise())
	pad.call("_unhandled_input", _talk_press())
	await _tick(_arm_and_rise())
	_expect(_taken_count == 0,
		"the interact key belongs to the revive while a teammate is down")
	# ...and the moment they are back up, the key is the pad's again.
	down.downed = false
	pad.call("_unhandled_input", _talk_press())
	await _tick(_arm_and_rise())
	_expect(_taken_count == 1, "once nobody is down, the key takes you again")
	await _teardown([pad, up, down])
	_completes("a_downed_ally_keeps_the_talk_key")


func _talk_press() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"talk"
	ev.pressed = true
	return ev


## Stand-in hero: the authored layer, the authored hurtbox, the "hero" group, and a
## real `_physics_process` so "did the pad freeze them" is a question with an answer.
class _HeroStub extends CharacterBody2D:
	var downed: bool = false

	func _init() -> void:
		collision_layer = 2
		collision_mask = 1
		var cs := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(18.0, 18.0)
		cs.shape = box
		add_child(cs)

	func _ready() -> void:
		add_to_group(&"hero")

	func _physics_process(_delta: float) -> void:
		pass

	func is_downed() -> bool:
		return downed
