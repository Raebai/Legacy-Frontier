# THE ROCK WALL TWO-BEAT: "the first left click summons it, the second left click
# should be the punch that sends it."
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice_test_wall_two_beat.gd
#
# The shove itself was never the broken part — tools/shove_punch_check.gd already
# proved a punch sends the wall. What was broken was INPUT ARBITRATION: while a
# spell is held the use button means CAST, so the second press raised a SECOND
# wall and the punch path was unreachable. So this suite asserts on the decision,
# not on the physics: given a wall standing there, what does the next press mean?
#
# Every case drives the real press path (_input with the real "cast" action), so a
# regression in the wiring fails here rather than in a playtest.
extends SceneTree

## RockWall is reached by PATH and never by class_name, and its statics are called
## through this GDScript object. A --script harness compiles before the autoloads
## are registered, and RockWall's raise path names Sfx — writing `RockWall.` here
## fails the WHOLE harness at compile time with "Identifier not found: Sfx", and
## poisons the class for the scene too. Same reason SpellCaster load()s its
## spectacle scripts by path instead of naming them.
const ROCK_WALL: String = "res://scripts/combat/RockWall.gd"
const ROCK_WALL_ID: String = "rock_wall"
const SETTLE_FRAMES: int = 70            # the figure has to land before anything is meaningful
const RISE_FRAMES: int = 60              # RockWall.RISE_TIME at 120 Hz, with slack

var _scene: Node
var _fig: Node
var _slots: HandSlots
var _rw: GDScript
var _fails: int = 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	root.size = Vector2i(1280, 720)
	# A GDScript error inside a coroutine kills that coroutine silently, so quit()
	# would never fire and the harness would spin forever. Fail loudly instead.
	create_timer(180.0).timeout.connect(func() -> void:
		printerr("FAIL: harness watchdog fired — a test coroutine died before the end")
		quit(1))
	_rw = load(ROCK_WALL)
	_scene = load("res://scenes/spike/SpellPlayground.tscn").instantiate()
	root.add_child(_scene)
	_run()


func _run() -> void:
	_fails += _t_handslots_claim()          # pure, no scene needed
	for i in SETTLE_FRAMES:
		await physics_frame
	_fig = _scene.get("_fig")
	_slots = _scene.get("_slots")
	_select_rock_wall()
	await _t_cast_stamps_ownership()
	await _t_second_press_punches()
	await _t_window_expiry_gives_the_button_back()
	await _t_aiming_away_still_casts()
	await _t_someone_elses_wall_never_claims()
	if _fails > 0:
		printerr("Wall two-beat tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Wall two-beat tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


# ---- harness ----------------------------------------------------------------

## Point the fighter's aim and resolve the claim in ONE synchronous block.
##
## There is no mouse headlessly, and _physics_process overwrites ctrl_aim from
## get_global_mouse_position() every tick — so the aim can only be held still
## between physics frames. Everything from here to the press therefore avoids
## `await`, and the arbitration is kicked by hand rather than waited for.
func _aim_at(target: Vector2) -> void:
	_fig.set("ctrl_aim", target)
	_scene.call("_update_shove_claim")


## The real press path: the same InputEventAction the "cast" binding produces.
func _press_use() -> void:
	var ev := InputEventAction.new()
	ev.action = "cast"
	ev.pressed = true
	_scene.call("_input", ev)


func _torso_pos() -> Vector2:
	return (_fig.get("_torso") as Node2D).global_position


func _walls() -> Array:
	return get_nodes_in_group("shoveable")


## Raise a wall to the fighter's RIGHT the way the controller's own cast does —
## bracketed, so it comes out owned. `owned = false` skips the stamp to fake a
## wall somebody else raised.
func _raise_wall_right(owned: bool = true) -> Node2D:
	var origin: Vector2 = _torso_pos()
	var spell: SpellDef = _rock_wall()
	# `self` IS the SceneTree in a --script harness — there is no get_tree() here.
	var before: Array = _rw.call("snapshot_shoveable", self)
	SpellCaster.cast(spell, _scene, origin, origin + Vector2(300.0, 0.0),
		Color(0.78, 0.84, 1.0), "")
	if owned:
		_rw.call("adopt_new_shoveable", self, before, _fig)
	for i in RISE_FRAMES:
		await physics_frame
	for w: Node in _walls():
		if not before.has(w):
			return w as Node2D
	return null


func _rock_wall() -> SpellDef:
	for s: SpellDef in (_scene.get("_spells") as Array):
		if s.id == ROCK_WALL_ID:
			return s
	return null


## Put rock wall in the hand, so the BASE answer to a press is "cast" and any
## "punch" we observe can only have come from the two-beat claim.
func _select_rock_wall() -> void:
	var spells: Array = _scene.get("_spells")
	_scene.set("_sidx", spells.find(_rock_wall()))
	_slots.slots[1]["spell"] = _rock_wall()
	_slots.select(1)


## Walls crumble on their own after 4.5 s; tests should not have to wait that out.
func _clear_walls() -> void:
	_scene.call("_set_primed_wall", null)
	for w: Node in _walls():
		w.queue_free()
	await physics_frame
	await physics_frame


# ---- tests ------------------------------------------------------------------

## The seam itself, with no world attached: a claim overrides the carousel and
## then gives it back, without ever disturbing what is actually held.
func _t_handslots_claim() -> int:
	var ok: int = 0
	var h := HandSlots.new()
	h.rebuild([], SpellLibrary.build())
	h.select(1)
	ok += _expect(h.primary_action() == "cast", "a spell slot casts by default")
	ok += _expect(not h.has_contextual_primary(), "a fresh hand has no contextual claim")
	h.claim_primary("punch")
	ok += _expect(h.primary_action() == "punch", "a claim overrides the held spell")
	ok += _expect(h.has_contextual_primary(), "the claim is visible to the tell")
	ok += _expect(h.selected == 1 and h.spell() != null,
		"a claim does not disturb the selection — the bar keeps showing what you hold")
	h.claim_primary("")
	ok += _expect(h.primary_action() == "cast", "releasing the claim restores the cast")
	# Fists already punch, so a claim there is a no-op rather than a special case.
	h.select(0)
	h.claim_primary("punch")
	ok += _expect(h.primary_action() == "punch", "claiming over fists changes nothing")
	h.claim_primary("")
	return ok


## Ownership is the basis of the whole rule, and SpellCaster does not forward the
## caster — so the controller's own cast path has to stamp it. Driven through
## _cast() (not the bracket helpers) precisely to prove THAT path does it.
func _t_cast_stamps_ownership() -> void:
	await _clear_walls()
	await _scene.call("_cast")
	for i in RISE_FRAMES:
		await physics_frame
	var walls: Array = _walls()
	_fails += _expect(walls.size() == 1, "the cast raised exactly one wall (got %d)" % walls.size())
	if walls.is_empty():
		return
	var w: Node = walls[0]
	_fails += _expect(w.get("caster_node") == _fig,
		"the controller's cast stamped the wall as the fighter's")
	_fails += _expect(bool(w.call("is_raised_by", _fig)), "is_raised_by agrees")
	_fails += _expect(not bool(w.call("is_raised_by", _scene)),
		"is_raised_by rejects a node that did not raise it")
	await _clear_walls()


## THE ASK. Wall standing, facing it, spell still in hand: the next press must be
## the punch that sends it — NOT a second wall.
func _t_second_press_punches() -> void:
	await _clear_walls()
	var wall: Node2D = await _raise_wall_right()
	_fails += _expect(wall != null, "setup: a wall was raised to the right")
	if wall == null:
		return
	var start_x: float = (wall.get("_floor_base") as Vector2).x
	_aim_at(_torso_pos() + Vector2(300.0, 0.0))
	_fails += _expect(_slots.primary_action() == "punch",
		"with your own wall in front of you the use button means PUNCH")
	_fails += _expect(_scene.get("_primed_wall") == wall,
		"the primed tell is on the wall that took the button")
	_fails += _expect(bool(wall.get("_primed")), "the wall itself knows it is primed")
	_press_use()
	for i in 40:
		await physics_frame
	# It either slid clear off the map (freed) or is visibly on its way.
	if not is_instance_valid(wall):
		_fails += _expect(_walls().is_empty(), "the shoved wall left no second wall behind")
	else:
		var moved: float = absf((wall.get("_floor_base") as Vector2).x - start_x)
		_fails += _expect(moved > 20.0,
			"the second press shoved the wall (moved %.1f px, expected > 20)" % moved)
		_fails += _expect(_walls().size() <= 1,
			"the second press did NOT raise a second wall (%d standing)" % _walls().size())
	await _clear_walls()


## The escape hatch: once the combo window lapses the wall hands the button back,
## so a wall left standing as cover stops eating your casts and you can raise
## another one. This is the case that stops the feature being a lockout.
func _t_window_expiry_gives_the_button_back() -> void:
	await _clear_walls()
	var wall: Node2D = await _raise_wall_right()
	if wall == null:
		_fails += _expect(false, "setup: window test needs a wall")
		return
	_aim_at(_torso_pos() + Vector2(300.0, 0.0))
	_fails += _expect(_slots.primary_action() == "punch", "setup: the claim started armed")
	# Wait past SHOVE_CLAIM_WINDOW while the wall is still comfortably alive
	# (RockWall.LIFETIME is 4.5 s, so it is still standing at 2.6 s).
	var window: float = _scene.get_script().get_script_constant_map()["SHOVE_CLAIM_WINDOW"]
	for i in int(window * 120.0) + 20:
		await physics_frame
	_fails += _expect(is_instance_valid(wall) and bool(wall.call("can_shove")),
		"setup: the wall is still standing after the window lapsed")
	_aim_at(_torso_pos() + Vector2(300.0, 0.0))
	_fails += _expect(_slots.primary_action() == "cast",
		"once the window lapses the use button goes back to casting")
	_fails += _expect(_scene.get("_primed_wall") == null, "and the tell goes out")
	# F (melee) is the promised fallback: the lapsed wall is still punchable.
	_fig.set("_punch_cd", 0.0)
	var start_x: float = (wall.get("_floor_base") as Vector2).x
	_fig.call("punch")
	for i in 40:
		await physics_frame
	var shoved: bool = not is_instance_valid(wall) \
		or absf((wall.get("_floor_base") as Vector2).x - start_x) > 20.0
	_fails += _expect(shoved, "melee still shoves a wall whose two-beat window has lapsed")
	await _clear_walls()


## Punching away from your wall must still CAST — that is the other way to get a
## second wall, and the reason the facing gate exists at all.
func _t_aiming_away_still_casts() -> void:
	await _clear_walls()
	var wall: Node2D = await _raise_wall_right()
	if wall == null:
		_fails += _expect(false, "setup: facing test needs a wall")
		return
	_aim_at(_torso_pos() + Vector2(-300.0, 0.0))
	_fails += _expect(_slots.primary_action() == "cast",
		"aiming away from the wall leaves the use button on the spell")
	_fails += _expect(_scene.get("_primed_wall") == null, "and the tell is off")
	# And prove the press really does cast: a second wall appears.
	_scene.set("_cast_cd", 0.0)
	_press_use()
	for i in RISE_FRAMES + 40:
		await physics_frame
	_fails += _expect(_walls().size() >= 2,
		"pressing while aimed away raised a second wall (%d standing)" % _walls().size())
	await _clear_walls()


## A wall you did not raise never takes YOUR button — the co-op rule. It is still
## punchable with melee, it just cannot hijack the press.
func _t_someone_elses_wall_never_claims() -> void:
	await _clear_walls()
	var wall: Node2D = await _raise_wall_right(false)
	if wall == null:
		_fails += _expect(false, "setup: ownership test needs a wall")
		return
	_fails += _expect(wall.get("caster_node") == null, "setup: the wall is unowned")
	_aim_at(_torso_pos() + Vector2(300.0, 0.0))
	_fails += _expect(_slots.primary_action() == "cast",
		"an unowned wall in reach does NOT claim the use button")
	_fails += _expect(_scene.get("_primed_wall") == null, "and does not light the tell")
	# But the fist still lands on it — ownership gates the CLAIM, not the shove.
	_fig.set("_punch_cd", 0.0)
	var start_x: float = (wall.get("_floor_base") as Vector2).x
	_fig.call("punch")
	for i in 40:
		await physics_frame
	var shoved: bool = not is_instance_valid(wall) \
		or absf((wall.get("_floor_base") as Vector2).x - start_x) > 20.0
	_fails += _expect(shoved, "melee still shoves an unowned wall")
	await _clear_walls()
