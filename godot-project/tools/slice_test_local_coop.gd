# Run: godot --headless --path godot-project --script tools/slice_test_local_coop.gd
#
# SAME-SCREEN LOCAL CO-OP: the pad that drives player two, and the floor knowing there
# ARE two of them.
#
# ⚠ THE HARDWARE IS FAKED, AND THAT IS THE ONLY WAY THIS IS TESTABLE. There is no
# controller plugged into a headless CI box, so `PadController`'s three device reads
# (`_connected`, `_button_raw`, `_raw_axis`) are overridden by `FakePad` below. Every
# other line of the class — the layout, the deadzone rescale, the diagonal clamp, and
# above all the press EDGES — is the real thing. Edges are DERIVED state: they are
# computed by diffing this frame against the last one, so "the file compiles" says
# nothing whatever about whether `just_pressed` fires once or on every frame of a hold.
# That is the bug this suite exists to catch.
#
# ⚠ HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the enclosing
# function and hands back the type's zero, which that idiom reads as "no failures".
# Failures accumulate on `_fails`; every test records a COMPLETION SENTINEL as its last
# line, so an aborted test fails BY ABSENCE.
extends SceneTree

const ENCOUNTER_SCRIPT: String = "res://scripts/combat/Encounter.gd"

const TESTS: Array[String] = [
	"the_layout_covers_every_action_a_hero_reads",
	"a_resting_stick_walks_nobody_and_a_pushed_one_rescales",
	"a_diagonal_is_not_faster_than_a_cardinal",
	"a_held_button_is_just_pressed_exactly_once",
	"an_unplugged_pad_reads_as_neutral_rather_than_stuck",
	"party_size_counts_people_in_the_room_not_the_network",
	"party_size_counts_humans_not_bodies",
	"a_second_climber_actually_scales_the_floor",
	"a_bound_bar_draws_its_own_climber_and_nobody_else",
	"a_bound_bar_whose_climber_died_draws_nothing",
	"a_pad_player_can_be_a_rescuer_and_a_bot_cannot",
	"player_two_has_a_class_of_their_own_that_does_not_leak",
]

## Everything `Hero` reads through the controller seam. If the pad cannot produce one of
## these, that verb is dead for player two — which is a silent loss, because the Hero
## simply never sees the press.
const HERO_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
	&"jump", &"dash", &"melee", &"cast", &"parry", &"ultimate",
	&"blast", &"blink", &"nova",
	&"spell_1", &"spell_2", &"spell_3", &"spell_4",
]

var _fails: int = 0
var _completed: Dictionary = {}


## A pad with no hardware behind it. Buttons and axes are set by the test.
class FakePad:
	extends PadController
	var connected: bool = true
	var buttons: Dictionary = {}     # button index -> bool
	var axes: Dictionary = {}        # axis index -> float

	func _connected() -> bool:
		return connected

	func _button_raw(b: int) -> bool:
		return bool(buttons.get(b, false))

	func _raw_axis(a: int) -> float:
		return float(axes.get(a, 0.0))


## A stand-in Hero: the only thing `party_size` asks of one is its `controller`.
class FakeHero:
	extends Node2D
	var controller: Variant = null
	var label: String = ""

	## The bar asks for exactly these two. An empty slot list is enough: it makes the
	## signature/charge stampers early-return, so this stays a test of the BINDING
	## decision rather than of the whole draw path.
	func ability_hud_state() -> Array:
		return []

	func class_display_name() -> String:
		return label


## Something bot-shaped: drives a body, but is NOT a person. Deliberately has no
## `is_human` — that absence is exactly how `party_size` tells it apart.
class FakeBrain:
	extends RefCounted
	func pressed(_a: StringName) -> bool:
		return false


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	the_layout_covers_every_action_a_hero_reads()
	a_resting_stick_walks_nobody_and_a_pushed_one_rescales()
	a_diagonal_is_not_faster_than_a_cardinal()
	await a_held_button_is_just_pressed_exactly_once()
	an_unplugged_pad_reads_as_neutral_rather_than_stuck()
	await party_size_counts_people_in_the_room_not_the_network()
	await party_size_counts_humans_not_bodies()
	a_second_climber_actually_scales_the_floor()
	await a_bound_bar_draws_its_own_climber_and_nobody_else()
	await a_bound_bar_whose_climber_died_draws_nothing()
	await a_pad_player_can_be_a_rescuer_and_a_bot_cannot()
	player_two_has_a_class_of_their_own_that_does_not_leak()

	for t: String in TESTS:
		_expect(_completed.has(t), "%s ran to completion" % t)
	print("local co-op tests: %s (%d failure(s))"
		% ["all PASS" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("local_coop: FAIL — %s" % what)


func _done(t: String) -> void:
	_completed[t] = true


# ------------------------------------------------------------------- the pad

func the_layout_covers_every_action_a_hero_reads() -> void:
	var mapped: Array[StringName] = PadController.mapped_actions()
	var missing: Array[String] = []
	for a: StringName in HERO_ACTIONS:
		if not mapped.has(a):
			missing.append(String(a))
	_expect(missing.is_empty(),
		"the pad layout has no binding for: %s — those verbs are dead for player two"
			% ", ".join(missing))
	print("  pad layout covers %d of the %d actions a hero reads"
		% [HERO_ACTIONS.size() - missing.size(), HERO_ACTIONS.size()])
	_done("the_layout_covers_every_action_a_hero_reads")


func a_resting_stick_walks_nobody_and_a_pushed_one_rescales() -> void:
	var pad := FakePad.new(0)
	# Drift well inside the deadzone: a worn stick that never quite centres.
	pad.axes[JOY_AXIS_LEFT_X] = 0.15
	_expect(is_zero_approx(pad.strength(&"move_right")),
		"a stick resting at 0.15 must read as centred, got %.3f"
			% pad.strength(&"move_right"))
	# Hard over is full speed, not "full minus the deadzone".
	pad.axes[JOY_AXIS_LEFT_X] = 1.0
	_expect(is_equal_approx(pad.strength(&"move_right"), 1.0),
		"a stick hard over must read 1.0, got %.3f" % pad.strength(&"move_right"))
	# And the opposite direction of the same axis stays silent.
	_expect(is_zero_approx(pad.strength(&"move_left")),
		"pushing right must not also press left")
	# Half over reads as MORE than half, because the deadzone is rescaled away rather
	# than simply subtracted — otherwise the first fifth of travel is thrown away.
	pad.axes[JOY_AXIS_LEFT_X] = 0.5
	var half: float = pad.strength(&"move_right")
	_expect(half > 0.3 and half < 0.5,
		"half a stick should rescale to ~0.36 of speed, got %.3f" % half)
	_done("a_resting_stick_walks_nobody_and_a_pushed_one_rescales")


func a_diagonal_is_not_faster_than_a_cardinal() -> void:
	var pad := FakePad.new(0)
	pad.axes[JOY_AXIS_LEFT_X] = 1.0
	pad.axes[JOY_AXIS_LEFT_Y] = 1.0
	var v: Vector2 = pad.vector(&"move_left", &"move_right", &"move_up", &"move_down")
	_expect(v.length() <= 1.0001,
		"a stick jammed into its corner must not exceed unit length, got %.3f" % v.length())
	_done("a_diagonal_is_not_faster_than_a_cardinal")


## THE ONE THAT MATTERS. A dash that fires every frame it is held is not a dash.
func a_held_button_is_just_pressed_exactly_once() -> void:
	var pad := FakePad.new(0)
	pad.buttons[JOY_BUTTON_B] = false
	# Establish a baseline frame with the button UP, so the press below is a real edge.
	pad.pressed(&"dash")
	await physics_frame

	pad.buttons[JOY_BUTTON_B] = true
	var edges: int = 0
	var held: int = 0
	for _i: int in 4:
		if pad.just_pressed(&"dash"):
			edges += 1
		if pad.pressed(&"dash"):
			held += 1
		await physics_frame
	_expect(edges == 1, "a button held for 4 frames must read just_pressed ONCE, got %d" % edges)
	_expect(held == 4, "the same button must read pressed on all 4 frames, got %d" % held)

	# And releasing is an edge of its own, exactly once.
	pad.buttons[JOY_BUTTON_B] = false
	var releases: int = 0
	for _i: int in 3:
		if pad.just_released(&"dash"):
			releases += 1
		await physics_frame
	_expect(releases == 1, "a released button must read just_released ONCE, got %d" % releases)
	_done("a_held_button_is_just_pressed_exactly_once")


## A pad yanked out mid-run must not leave the hero sprinting into a wall forever.
func an_unplugged_pad_reads_as_neutral_rather_than_stuck() -> void:
	var pad := FakePad.new(0)
	pad.axes[JOY_AXIS_LEFT_X] = 1.0
	pad.buttons[JOY_BUTTON_A] = true
	pad.connected = false
	_expect(is_zero_approx(pad.strength(&"move_right")),
		"an unplugged pad must read no movement")
	_expect(is_zero_approx(pad.strength(&"jump")), "an unplugged pad must read no buttons")
	_done("an_unplugged_pad_reads_as_neutral_rather_than_stuck")


# -------------------------------------------------------------- the party count

func _encounter() -> Node:
	var scr: GDScript = load(ENCOUNTER_SCRIPT) as GDScript
	var e: Node = scr.new() as Node
	root.add_child(e)
	return e


func _add_hero(ctrl: Variant) -> Node:
	var h := FakeHero.new()
	h.controller = ctrl
	h.add_to_group("hero")
	root.add_child(h)
	return h


## The bug this fixes: `party_size` returned 1 unless a NETWORKED session was live, so
## two people on one couch were scaled as one climber.
func party_size_counts_people_in_the_room_not_the_network() -> void:
	var e: Node = _encounter()
	await process_frame
	_expect(int(e.call("party_size")) == 1, "an empty room is a party of 1 (the floor scales by nothing)")

	var h1: Node = _add_hero(null)
	await process_frame
	_expect(int(e.call("party_size")) == 1, "one hero is a party of 1")

	var h2: Node = _add_hero(null)
	await process_frame
	var got: int = int(e.call("party_size"))
	_expect(got == 2,
		"two local heroes must be a party of 2 with NO network session, got %d" % got)

	h1.queue_free()
	h2.queue_free()
	e.queue_free()
	await process_frame
	_done("party_size_counts_people_in_the_room_not_the_network")


## A bot ally is a body, not a player, and must not inflate the floor it is helping on.
func party_size_counts_humans_not_bodies() -> void:
	var e: Node = _encounter()
	var human: Node = _add_hero(null)
	var pad_player: Node = _add_hero(FakePad.new(1))
	var bot: Node = _add_hero(FakeBrain.new())
	await process_frame

	var got: int = int(e.call("party_size"))
	_expect(got == 2,
		"keyboard + pad + BOT is a party of 2, got %d — a bot ally must not scale the floor"
			% got)

	human.queue_free()
	pad_player.queue_free()
	bot.queue_free()
	e.queue_free()
	await process_frame
	_done("party_size_counts_humans_not_bodies")


func _bar_for(hero: Node) -> Node:
	var bar := AbilityBar.new()
	bar.bound_hero = hero
	root.add_child(bar)
	return bar


## Before `bound_hero`, both players' bars showed player ONE's cooldowns — which is
## worse than showing nothing, because it looks correct.
func a_bound_bar_draws_its_own_climber_and_nobody_else() -> void:
	var first := FakeHero.new()
	first.label = "FIRST"
	first.add_to_group("hero")
	root.add_child(first)
	var second := FakeHero.new()
	second.label = "SECOND"
	second.add_to_group("hero")
	root.add_child(second)
	await process_frame

	var bound: Node = _bar_for(second)
	var loose: Node = _bar_for(null)          # null = the shipped, group-lookup default
	await process_frame
	bound.call("_process", 0.0)
	loose.call("_process", 0.0)

	_expect(String(bound.get("_class_name")) == "SECOND",
		"a bound bar must draw ITS climber, got '%s'" % String(bound.get("_class_name")))
	_expect(String(loose.get("_class_name")) == "FIRST",
		"an unbound bar must still take the first hero in the group (the solo path), got '%s'"
			% String(loose.get("_class_name")))

	bound.queue_free()
	loose.queue_free()
	first.queue_free()
	second.queue_free()
	await process_frame
	_done("a_bound_bar_draws_its_own_climber_and_nobody_else")


## ⚠ IT MUST NOT FALL BACK. A bar that quietly repoints at the surviving player looks
## like it is working, which is the one failure mode a HUD must never have.
func a_bound_bar_whose_climber_died_draws_nothing() -> void:
	var alive := FakeHero.new()
	alive.label = "ALIVE"
	alive.add_to_group("hero")
	root.add_child(alive)
	var doomed := FakeHero.new()
	doomed.label = "DOOMED"
	doomed.add_to_group("hero")
	root.add_child(doomed)
	await process_frame

	var bar: Node = _bar_for(doomed)
	root.remove_child(doomed)
	doomed.free()
	await process_frame
	bar.call("_process", 0.0)

	_expect(String(bar.get("_class_name")) == "",
		"a bar whose climber died must draw nothing, not the survivor's bar — got '%s'"
			% String(bar.get("_class_name")))

	bar.queue_free()
	alive.queue_free()
	await process_frame
	_done("a_bound_bar_whose_climber_died_draws_nothing")


## `Revive._is_local_player` returned false for ANYTHING with a controller, which was
## right while a controller could only be a bot — and silently meant player two on a pad
## could never pick anybody up.
func a_pad_player_can_be_a_rescuer_and_a_bot_cannot() -> void:
	var scr: GDScript = load("res://scripts/combat/Revive.gd") as GDScript
	var rev: Node = scr.new() as Node
	root.add_child(rev)
	await process_frame

	var keyboard := FakeHero.new()
	var pad_player := FakeHero.new()
	pad_player.controller = FakePad.new(1)
	var bot := FakeHero.new()
	bot.controller = FakeBrain.new()

	_expect(bool(rev.call("_is_local_player", keyboard)),
		"the keyboard player is a rescuer")
	_expect(bool(rev.call("_is_local_player", pad_player)),
		"a PAD player must be able to rescue — this is the bug the fix exists for")
	_expect(not bool(rev.call("_is_local_player", bot)),
		"a bot-driven hero must NOT be treated as a local rescuer")

	keyboard.free()
	pad_player.free()
	bot.free()
	rev.queue_free()
	await process_frame
	_done("a_pad_player_can_be_a_rescuer_and_a_bot_cannot")


## ⚠ THE LEAK IS THE POINT OF THE TEST. `GameState.selected_class` is a single global
## written by the hub altar, the in-run class switch, the versus arena and four Lobby
## paths — so parking player two's pick in it would quietly overwrite player one's the
## next time anybody switched. A separate store is only worth having if it stays separate.
func player_two_has_a_class_of_their_own_that_does_not_leak() -> void:
	var gs: Node = root.get_node_or_null(^"/root/GameState")
	if gs == null:
		_expect(false, "GameState autoload is missing — cannot test the P2 class store")
		return
	var p1_before: int = int(gs.get(&"selected_class"))

	_expect(int(gs.call(&"local_class_of", 7)) == -1,
		"an unset pad must inherit player one's class (-1), got %d"
			% int(gs.call(&"local_class_of", 7)))

	gs.call(&"set_local_class", 7, 3)
	_expect(int(gs.call(&"local_class_of", 7)) == 3,
		"player two's class must read back as set, got %d"
			% int(gs.call(&"local_class_of", 7)))
	# A second pad is a second player, not the same one.
	_expect(int(gs.call(&"local_class_of", 8)) == -1,
		"setting pad 7 must not decide pad 8's class")
	_expect(int(gs.get(&"selected_class")) == p1_before,
		"setting player two's class must NOT touch player one's (%d -> %d)"
			% [p1_before, int(gs.get(&"selected_class"))])

	# Leave the autoload as we found it — a suite that mutates shared state and walks
	# away is a suite that fails whichever test happens to run after it.
	(gs.get(&"local_class") as Dictionary).erase(7)
	_done("player_two_has_a_class_of_their_own_that_does_not_leak")


## The count is only worth anything if it moves the numbers the player feels.
func a_second_climber_actually_scales_the_floor() -> void:
	var scr: GDScript = load(ENCOUNTER_SCRIPT) as GDScript
	var solo_hp: float = float(scr.call("party_boss_hp_mult", 1))
	var duo_hp: float = float(scr.call("party_boss_hp_mult", 2))
	var solo_budget: float = float(scr.call("party_budget_mult", 1))
	var duo_budget: float = float(scr.call("party_budget_mult", 2))
	var solo_cap: int = int(scr.call("party_cap", 4, 1))
	var duo_cap: int = int(scr.call("party_cap", 4, 2))

	_expect(is_equal_approx(solo_hp, 1.0), "solo must scale the guardian by exactly 1.0")
	_expect(duo_hp > solo_hp, "a second climber must give the guardian more HP")
	_expect(is_equal_approx(solo_budget, 1.0), "solo must scale the wave budget by exactly 1.0")
	_expect(duo_budget > solo_budget, "a second climber must widen the wave budget")
	_expect(duo_cap > solo_cap, "a second climber must raise the concurrent cap")
	print("  2P scaling: guardian HP x%.2f, wave budget x%.2f, concurrent cap %d -> %d"
		% [duo_hp, duo_budget, solo_cap, duo_cap])
	_done("a_second_climber_actually_scales_the_floor")
