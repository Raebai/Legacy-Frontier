extends SceneTree
## GEAR THAT REPLACES A BODY PART — the drawing rules, not the stats.
##
## Maker, 2026-09-05, verbatim: *"please make mock versions of like helmets and stuff that
## replace the character head are not work on top and other items that emphasise what they
## do"*. Three separate claims live in that sentence and each one gets a test:
##
##   1. The pieces DRAW at all. `draw_clothing` was false, so nothing did.
##   2. They REPLACE rather than overlay — which means the hitbox the spells test against
##      must be untouched, exactly as it is for the shipped `helmet` / `robe`.
##   3. The look you were ISSUED and the look you CHOSE are different things. The earlier
##      ruling (*"I just want to see STICKMEN"*) is about class-preset cosmetics and still
##      stands; the new one is about armoury gear. If those two ever collapse back into one
##      flag, every mage is wearing a robe again and nobody notices until a playtest.
##
## ⚠ WHAT THIS CANNOT TEST, SAID PLAINLY: headless Godot runs the DUMMY renderer, so no
## pixel comes out of `_draw` and no suite here can tell a good silhouette from a bad one.
## It proves the decision layer and proves the draw path executes without erroring. Whether
## a bucket helm reads as heavy is a maker's-eyes question and always was.
##
## Run: godot --headless --path godot-project --script tools/slice_test_gear_look.gd

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"

var _ran: bool = false
var _failed: int = 0
## The live-draw pass runs ONE combination PER FRAME rather than in a loop with `await`.
## `SceneTree._process` returns a bool ("quit now?"), and an `await` inside it turns the
## function into a coroutine that returns a signal instead — the suite would then run
## exactly one frame and report all-PASS having tested nothing, which is the silent-green
## failure mode this repo has been bitten by before.
var _combos: Array = []
var _combo_i: int = -1
var _rig: Node2D = null


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_test_every_worn_piece_has_a_silhouette()
		_test_issued_gear_and_chosen_gear_are_different_questions()
		_test_the_preset_mark_survives_a_ghost_copy()
		_test_mock_gear_does_not_move_the_hitbox()
		_begin_draw_pass()
		return false
	if _combo_i < _combos.size():
		_step_draw_pass()
		return false
	if _rig != null:
		# Torn down a frame BEFORE the summary, not in the same one. Freeing a node that
		# the tree is still mid-draw on is how a green suite ends with "resources still in
		# use at exit" — an ERROR line under an all-PASS, which this repo counts as a
		# failure whether or not it changed the result.
		_end_draw_pass()
		return false
	if _failed == 0:
		print("Gear look tests: all PASS")
	else:
		printerr("Gear look tests: %d FAILED" % _failed)
	quit(1 if _failed > 0 else 0)
	return true


func _rig_consts() -> Dictionary:
	return (load(RIG_PATH) as GDScript).get_script_constant_map()


func _make_rig() -> Node2D:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", 31.0)
	rig.call("set_grounded", true)
	rig.call("play", 0)   # State.IDLE
	return rig


## CLAIM 1. Every piece the armoury offers for a BODY slot draws something; every
## spellement draws nothing (it attaches to a spell, not to a hand).
func _test_every_worn_piece_has_a_silhouette() -> void:
	var c: Dictionary = _rig_consts()
	for kind: String in (c["MOCK_HEAD"] as Array) + (c["MOCK_BODY"] as Array) + (c["LEG_GEAR"] as Array):
		_expect(CharacterRig.draws_kind(kind), "mock piece '%s' has a silhouette" % kind)
	for kind2: String in GearAbilities.options_for("weapon"):
		_expect(not CharacterRig.draws_kind(kind2),
			"spellement '%s' draws nothing on the body" % kind2)
	# The three armoury body slots and the rig's three drawable families must agree in
	# SIZE, or a piece has been added to one list and forgotten in the other — which
	# shows up as a slot that equips and then does not appear.
	_expect((c["MOCK_HEAD"] as Array).size() == GearAbilities.options_for("head").size(),
		"every offered helm has a mock shape")
	_expect((c["MOCK_BODY"] as Array).size() == GearAbilities.options_for("body").size(),
		"every offered armour has a mock shape")
	_expect((c["LEG_GEAR"] as Array).size() == GearAbilities.options_for("legs").size(),
		"every offered greave has a mock shape")


## CLAIM 3, AND THE ONE MOST LIKELY TO REGRESS. `draw_clothing` is FALSE and must stay
## false: a class preset dresses every mage in a robe and hat, and the maker asked twice
## for plain stickmen. `draw_equipped_gear` is TRUE: a piece you chose in the armoury is
## the whole reason you chose it.
func _test_issued_gear_and_chosen_gear_are_different_questions() -> void:
	var rig: Node2D = _make_rig()
	rig.call("class_preset", "mage")
	var eq: Dictionary = rig.get("equipment")
	_expect(String(eq.get("head", "")) == "hat", "the mage preset still SETS a hat")
	_expect(CharacterRig._visible_gear(eq, "head") == "",
		"...and it is NOT DRAWN - a hero who equipped nothing is a plain stickman")
	_expect(CharacterRig._visible_gear(eq, "weapon") == "staff",
		"the held weapon is never suppressed - a stickman with a staff is still a stickman")
	# Now the player chooses one in the armoury. Same slot, opposite answer.
	rig.call("set_equipment", "head", "pl_ironbrow")
	var eq2: Dictionary = rig.get("equipment")
	_expect(CharacterRig._visible_gear(eq2, "head") == "pl_ironbrow",
		"a helm the PLAYER equipped is drawn")
	# ...and re-running the preset takes the slot back and re-suppresses it, so walking the
	# roster cannot leave a stale chosen piece marked as chosen.
	rig.call("class_preset", "cryomancer")
	_expect(CharacterRig._visible_gear(rig.get("equipment"), "head") == "",
		"re-applying a preset re-claims the slot it authored")
	rig.free()


## The mark rides INSIDE the equipment dict because every ghost / afterimage / corpse is
## seeded from `equipment.duplicate()`. A mark held on the instance would be lost by
## exactly the copies that must not disagree with the body they trail.
func _test_the_preset_mark_survives_a_ghost_copy() -> void:
	var rig: Node2D = _make_rig()
	rig.call("class_preset", "mage")
	var copy: Dictionary = (rig.get("equipment") as Dictionary).duplicate()
	_expect(CharacterRig._visible_gear(copy, "head") == "",
		"a duplicated equipment dict still knows the hat was issued, not chosen")
	rig.call("set_equipment", "body", "pl_ashplate")
	var copy2: Dictionary = (rig.get("equipment") as Dictionary).duplicate()
	_expect(CharacterRig._visible_gear(copy2, "body") == "pl_ashplate",
		"...and still knows the armour was chosen")
	rig.free()


## CLAIM 2. `Enemy.body_distance` / `SpellTargets` measure the head disc and the neck->hip
## segment. Gear may only ADD mass around them. Break this and "spells pass through heads"
## comes straight back — which is the bug the shipped `helmet`/`robe` contract was written
## after, so the mocks are held to the same one.
func _test_mock_gear_does_not_move_the_hitbox() -> void:
	var c: Dictionary = _rig_consts()
	var rig: Node2D = _make_rig()
	for i: int in 3:
		rig.call("advance", 1.0 / 60.0)
	var bare: Dictionary = rig.call("_compute_pose")
	for kind: String in (c["MOCK_HEAD"] as Array):
		rig.call("set_equipment", "head", kind)
		var g: Dictionary = rig.call("_compute_pose")
		_expect((g["head_center"] as Vector2).distance_to(bare["head_center"] as Vector2) < 0.001
				and is_equal_approx(float(g["r"]), float(bare["r"])),
			"mock helm '%s' leaves the head disc exactly where it was" % kind)
	rig.call("set_equipment", "head", "")
	for kind2: String in (c["MOCK_BODY"] as Array):
		rig.call("set_equipment", "body", kind2)
		var g2: Dictionary = rig.call("_compute_pose")
		_expect((g2["neck"] as Vector2).distance_to(bare["neck"] as Vector2) < 0.001
				and (g2["hip"] as Vector2).distance_to(bare["hip"] as Vector2) < 0.001,
			"mock armour '%s' leaves the spine segment where it was" % kind2)
	rig.call("set_equipment", "body", "")
	for kind3: String in (c["LEG_GEAR"] as Array):
		rig.call("set_equipment", "legs", kind3)
		var g3: Dictionary = rig.call("_compute_pose")
		_expect((g3["hip"] as Vector2).distance_to(bare["hip"] as Vector2) < 0.001,
			"greave '%s' leaves the hip where it was" % kind3)
	rig.free()


## The draw path itself, wearing each mock in turn. Headless renders nothing, so what this
## proves is that no polygon in the new code is malformed enough to throw — which is the
## whole class of failure a pose-only test cannot see, and the reason this suite exists at
## all rather than living inside `slice_test_rig_gait`.
func _begin_draw_pass() -> void:
	var c: Dictionary = _rig_consts()
	for h: String in (c["MOCK_HEAD"] as Array):
		_combos.append({"head": h})
	for b: String in (c["MOCK_BODY"] as Array):
		_combos.append({"body": b})
	for l: String in (c["LEG_GEAR"] as Array):
		_combos.append({"legs": l})
	# ...and one figure wearing all three at once, because the interaction (a torso that
	# flares past the hip over a greave that starts at the knee) is where an overlap would
	# show and no single-slot pass would ever produce it.
	_combos.append({"head": "pl_ironbrow", "body": "pl_tideweave", "legs": "pl_ironmarch"})
	_rig = _make_rig()
	root.add_child(_rig)
	_combo_i = 0


func _step_draw_pass() -> void:
	var combo: Dictionary = _combos[_combo_i]
	for slot: String in ["head", "body", "legs"]:
		_rig.call("set_equipment", slot, String(combo.get(slot, "")))
	_rig.call("advance", 1.0 / 60.0)
	_rig.queue_redraw()
	_combo_i += 1


func _end_draw_pass() -> void:
	_expect(_combo_i == _combos.size() and _combos.size() >= 12,
		"every mock combination reached a draw (%d of %d)" % [_combo_i, _combos.size()])
	if _rig != null:
		# `free`, not `queue_free`: the very next line quits the tree, so a QUEUED free
		# never runs and Godot reports "resources still in use at exit" — noise in a
		# suite whose whole contract is that its output is trustworthy.
		root.remove_child(_rig)
		_rig.free()
		_rig = null
	# ⚠ AND SILENCE THE MUSIC AUTOLOAD, WHICH IS NOT THIS SUITE'S CODE AND IS THIS SUITE'S
	# PROBLEM. Almost every other suite runs its assertions in ONE `_process` and quits;
	# this one has to TICK REAL FRAMES to get `_draw` called at all, which is long enough
	# for `Music` to open an ogg stream — and an ogg still open at `quit()` prints
	# "2 resources still in use at exit", an ERROR line under an all-PASS. The repo counts
	# that as a failure, correctly, so the stream is closed rather than the line ignored.
	var music: Node = root.get_node_or_null("Music")
	if music != null and music.has_method("stop"):
		music.call("stop")


func _expect(cond: bool, msg: String) -> void:
	if cond:
		return
	printerr("FAIL: %s" % msg)
	_failed += 1
