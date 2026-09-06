# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_training.gd
#
# THE TUTORIAL TEACHES THE CLASS YOU ACTUALLY ARE, AND IT CAN BE FOUND AGAIN.
#
# Maker: *"it needs a tutorial area where the users can learn all the basic moves and
# attacks per class and the aim of the game"*.
#
# ⚠ WHAT THIS SUITE IS REALLY DEFENDING is the "per class" clause, because that is the
# half that rots silently. A tutorial that names Fireball at every player is still a
# tutorial — it opens, it ticks, it closes, and nothing goes red — it is just WRONG for
# eight of the nine classes, and wrong again the first time a kit is re-authored. So the
# assertions below are mostly about the lesson being DERIVED:
#
#   * every class's lesson names that class's OWN four spells, checked against
#     `ClassInfo.carried_spells` rather than against a list this file keeps;
#   * the movement-verb step says a different word for classes with different verbs,
#     which is the standing nine-classes-nine-verbs ruling made testable;
#   * the aim-of-the-game step exists and mentions the Tower, because the maker asked
#     for it by name and it is the one step no player action can reveal is missing.
#
# ⚠ AND THE FLAG LIVES ON THE PROFILE, NOT ON `GameState`. `GameState` is the state of a
# CLIMB — wiped and rebuilt every run — so a "seen the tutorial" flag there would re-teach
# the game to a veteran every time they died. That is asserted directly, because it is a
# one-word mistake to make and it would only ever be noticed by a player being annoyed.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ─────────
# `failed += _test_x()` IS BANNED. A dead property read is not a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function and hands the caller
# the return type's zero, which under that idiom reads as "zero failures". Failures
# accumulate on the MEMBER `_fails`, and every test records that it reached its own last
# line — a test that aborts part-way is missing from `_completed` and fails BY ABSENCE.
extends SceneTree

const COACH_PATH: String = "res://scripts/ui/TrainingCoach.gd"
const PROFILE_PATH: String = "res://scripts/PlayerProfile.gd"
const WORLD_PATH: String = "res://scripts/World.gd"
const PAUSE_PATH: String = "res://scripts/combat/PauseMenu.gd"

const TESTS: Array[String] = [
	"a_lesson_is_built_for_every_class",
	"the_lesson_names_the_class_s_own_spells",
	"the_movement_step_is_per_class",
	"the_aim_of_the_game_is_taught",
	"every_step_is_a_named_action_not_a_keycode",
	"the_seen_flag_lives_on_the_profile_not_the_climb",
	"the_hub_can_re_run_it",
]

var _fails: int = 0
var _completed: Dictionary = {}


## ⚠ `ClassInfo` IS LOADED AT RUNTIME, NOT NAMED. Writing `_class_count()` resolves the
## global class table at PARSE time, which in a `--script` harness happens BEFORE autoloads
## register — so the chain it pulls in (`SpellLibrary` -> `Sfx`, `Rank`) fails to compile
## and every assertion below aborts into a vacuous pass. Same trap, same fix, as
## `tools/slice_test_carve_capsule.gd`.
var _ci: GDScript = null


func _class_info() -> GDScript:
	if _ci == null:
		_ci = load("res://scripts/combat/ClassInfo.gd") as GDScript
	return _ci


func _class_count() -> int:
	return int(_class_info().call("count"))


func _class_name_for(i: int) -> String:
	return String(_class_info().call("name_for", i))


func _carried_spells(i: int) -> Array:
	return _class_info().call("carried_spells", i)


func _fail(msg: String) -> void:
	_fails += 1
	push_error("FAIL: " + msg)
	print("  FAIL: ", msg)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)


func _completes(name: String) -> void:
	_completed[name] = true


## ⚠ `_process`, NOT `_init`, AND THAT IS NOT A STYLE CHOICE. A `SceneTree._init` runs
## BEFORE the autoload table is populated, so anything loaded there drags its whole chain
## through a compile with `Sfx` and `Rank` undefined — `ClassInfo` -> `SpellLibrary` does
## exactly that. The assertions still passed, because the loads happen lazily and succeed
## on the second attempt, but the run emitted `Compile Error: Identifier not found` four
## times — and `run_all_tests.py` FAILS ANY SUITE THAT EMITS A SCRIPT ERROR, whatever the
## suite itself reports. Deferring one frame is what makes the tree exist. Same idiom as
## `tools/slice_test_loadout.gd`.
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_a_lesson_is_built_for_every_class()
	_test_the_lesson_names_the_class_s_own_spells()
	_test_the_movement_step_is_per_class()
	_test_the_aim_of_the_game_is_taught()
	_test_every_step_is_a_named_action_not_a_keycode()
	_test_the_seen_flag_lives_on_the_profile_not_the_climb()
	_test_the_hub_can_re_run_it()
	for t: String in TESTS:
		_expect(_completed.has(t), "test '%s' ran to completion" % t)
	if _fails == 0:
		print("Training tests: all PASS")
	else:
		print("Training tests: ", _fails, " FAILED")
	quit(1 if _fails > 0 else 0)
	return false


## A coach, built and stepped without a tree. It is a `CanvasLayer`, so it needs to be in
## the tree for `_ready` to have run — added under root and freed by the caller.
func _make_coach() -> Node:
	var script: GDScript = load(COACH_PATH) as GDScript
	if script == null:
		return null
	var c: Node = script.new()
	root.add_child(c)
	return c


func _titles_for(c: Node, cls: int) -> Array[String]:
	c.call("start", cls)
	var out: Array[String] = []
	var steps: Variant = c.get("_steps")
	if steps is Array:
		for s: Variant in (steps as Array):
			out.append(String(s.get("title")))
	return out


func _test_a_lesson_is_built_for_every_class() -> void:
	var c: Node = _make_coach()
	_expect(c != null, "the coach script loads")
	if c == null:
		return
	for cls: int in _class_count():
		var titles: Array[String] = _titles_for(c, cls)
		# Move, jump, the verb, strike, four kit steps, the aim. A class that produced a
		# stub lesson would still "run" and teach nothing.
		_expect(titles.size() >= 7,
			"%s gets a real lesson (got %d steps: %s)"
				% [_class_name_for(cls), titles.size(), ", ".join(titles)])
		_expect(bool(c.call("is_running")), "%s's lesson starts running" % _class_name_for(cls))
	c.free()
	_completes("a_lesson_is_built_for_every_class")


## ⚠ THE ONE THAT MATTERS. Checked against `ClassInfo.carried_spells` — the same source
## the hand and the class card read — rather than against a list kept here, so a kit
## re-author moves both together instead of leaving this suite defending yesterday.
func _test_the_lesson_names_the_class_s_own_spells() -> void:
	var c: Node = _make_coach()
	if c == null:
		return
	for cls: int in _class_count():
		var titles: Array[String] = _titles_for(c, cls)
		var joined: String = " | ".join(titles)
		var spells: Array = _carried_spells(cls)
		_expect(not spells.is_empty(),
			"%s carries spells to teach" % _class_name_for(cls))
		for sp: Variant in spells:
			if sp == null:
				continue
			var nm: String = String(sp.display_name)
			_expect(joined.contains(nm),
				"%s's lesson names its own spell '%s' (lesson was: %s)"
					% [_class_name_for(cls), nm, joined])
	c.free()
	_completes("the_lesson_names_the_class_s_own_spells")


## The nine-classes-nine-verbs ruling, made testable. Two classes with DIFFERENT
## `move_verb` values must get different words; a lesson that said "Dash" to everyone
## would pass every other assertion in this file.
func _test_the_movement_step_is_per_class() -> void:
	var c: Node = _make_coach()
	if c == null:
		return
	var hero: GDScript = load("res://scripts/combat/Hero.gd") as GDScript
	_expect(hero != null, "Hero.gd loads (the movement-verb table's source)")
	if hero == null:
		c.free()
		return
	var cfg: Dictionary = hero.get_script_constant_map().get("CLASS_CONFIG", {})
	var verb_to_word: Dictionary = {}
	for cls: int in _class_count():
		var titles: Array[String] = _titles_for(c, cls)
		# The verb step is index 2: move, jump, VERB, strike, kit..., aim.
		_expect(titles.size() > 2, "%s's lesson has a verb step" % _class_name_for(cls))
		if titles.size() <= 2:
			continue
		var raw_verb: String = String((cfg.get(cls, {}) as Dictionary).get("move_verb", ""))
		verb_to_word[raw_verb] = titles[2]
	# At least two DISTINCT words across the roster. One word for nine classes is exactly
	# the generic-tutorial failure this whole test exists for.
	var words: Dictionary = {}
	for v: Variant in verb_to_word.values():
		words[v] = true
	_expect(words.size() >= 2,
		"the movement step says different things for different classes (got %d distinct: %s)"
			% [words.size(), ", ".join(PackedStringArray(words.keys()))])
	c.free()
	_completes("the_movement_step_is_per_class")


## The maker asked for "the aim of the game" by name. No player action can reveal that it
## is missing — they would simply never learn what the Tower is — so it is asserted here.
func _test_the_aim_of_the_game_is_taught() -> void:
	var c: Node = _make_coach()
	if c == null:
		return
	c.call("start", 0)
	var steps: Variant = c.get("_steps")
	var found: bool = false
	if steps is Array and not (steps as Array).is_empty():
		var last: Variant = (steps as Array)[(steps as Array).size() - 1]
		var body: String = String(last.get("body"))
		found = body.to_lower().contains("tower") and body.to_lower().contains("floor")
		_expect(String(last.get("action")) == "",
			"the aim card is READ, not performed — it has no input to press")
	_expect(found,
		"the last step explains the Tower and its floors — the aim of the game")
	c.free()
	_completes("the_aim_of_the_game_is_taught")


## ⚠ NAMED ACTIONS ONLY. This is D-011, the mobile-first input rule: the coach's steps
## must be satisfiable by the on-screen touch buttons, and a step waiting on a KEYCODE
## could only ever be completed on a keyboard — which would make the tutorial impossible
## to finish on the platform this game is actually for.
func _test_every_step_is_a_named_action_not_a_keycode() -> void:
	var c: Node = _make_coach()
	if c == null:
		return
	for cls: int in _class_count():
		c.call("start", cls)
		var steps: Variant = c.get("_steps")
		if not (steps is Array):
			continue
		for s: Variant in (steps as Array):
			var a: String = String(s.get("action"))
			if a == "":
				continue  # a read-me card
			_expect(InputMap.has_action(StringName(a)),
				"step '%s' waits on a real named action ('%s')" % [String(s.get("title")), a])
			var a2: String = String(s.get("second_action"))
			if a2 != "":
				_expect(InputMap.has_action(StringName(a2)),
					"step '%s' second action '%s' is real" % [String(s.get("title")), a2])
	c.free()
	_completes("every_step_is_a_named_action_not_a_keycode")


## ⚠ THE FLAG MUST NOT LIVE ON `GameState`. That object is the state of a CLIMB and is
## wiped and rebuilt every run, so a tutorial flag there would re-teach the game to a
## veteran every time they died — a one-word mistake that only ever shows up as a player
## being annoyed. It belongs on the profile, which outlives every climb.
func _test_the_seen_flag_lives_on_the_profile_not_the_climb() -> void:
	var prof: GDScript = load(PROFILE_PATH) as GDScript
	_expect(prof != null, "PlayerProfile loads")
	if prof == null:
		return
	_expect(prof.has_method("has_been_taught"), "PlayerProfile answers has_been_taught()")
	_expect(prof.has_method("mark_taught"), "PlayerProfile can record mark_taught()")

	# It ROUND-TRIPS. A flag that is read and parsed but never WRITTEN is `false` for
	# ever, and the feature it gates silently never changes state — the exact bug shape
	# this repo keeps paying for (`GameState.colourway` has no writer to this day).
	var saved: Dictionary = prof.build_profile_save("Tester", "", true)
	_expect(bool(saved.get("taught", false)),
		"build_profile_save WRITES the taught flag (got %s)" % str(saved.get("taught")))
	var parsed: Dictionary = prof.parse_profile_save(saved)
	_expect(bool(parsed.get("taught", false)),
		"parse_profile_save reads it back (got %s)" % str(parsed.get("taught")))
	# Default-off, so a brand-new player is taught rather than skipped.
	var fresh: Dictionary = prof.parse_profile_save({})
	_expect(not bool(fresh.get("taught", true)),
		"a profile with no flag means NOT yet taught, so a new player gets the lesson")
	# JSON hands numbers back as floats; a `1` where `true` was written must still read
	# as taught, or that player is re-taught for ever.
	var numeric: Dictionary = prof.parse_profile_save({"taught": 1})
	_expect(bool(numeric.get("taught", false)),
		"a numeric 1 counts as taught (the JSON int/float trap)")

	var gs: GDScript = load("res://scripts/GameState.gd") as GDScript
	if gs != null:
		var gs_src: String = ""
		var f: FileAccess = FileAccess.open("res://scripts/GameState.gd", FileAccess.READ)
		if f != null:
			gs_src = f.get_as_text()
			f.close()
		_expect(not gs_src.contains("has_been_taught"),
			"the taught flag did NOT migrate into GameState, which is per-climb state")
	_completes("the_seen_flag_lives_on_the_profile_not_the_climb")


## The tutorial has to be findable again. `World` exposes `teach_now`, and `PauseMenu`
## offers it — without that, the one chance to learn a nine-class roster is the first
## thirty seconds you ever played.
func _test_the_hub_can_re_run_it() -> void:
	var world: GDScript = load(WORLD_PATH) as GDScript
	_expect(world != null, "World.gd loads")
	if world != null:
		var names: Array[String] = []
		for m: Dictionary in world.get_script_method_list():
			names.append(String(m.get("name", "")))
		_expect(names.has("teach_now"), "World exposes teach_now() so the lesson can repeat")
		_expect(names.has("is_teaching"), "World reports whether it is teaching")

	# The menu row, read from source: it is built inside a group lookup that cannot run
	# headlessly without a hub, so the reachable claim here is that the row EXISTS and
	# calls the right thing.
	var f: FileAccess = FileAccess.open(PAUSE_PATH, FileAccess.READ)
	_expect(f != null, "PauseMenu.gd is readable")
	if f != null:
		var src: String = f.get_as_text()
		f.close()
		_expect(src.contains("HOW TO PLAY"),
			"the pause menu offers HOW TO PLAY")
		_expect(src.contains("teach_now"),
			"...and that row actually calls teach_now, rather than being a label")
		_expect(src.contains("hub_world"),
			"...and finds the hub by group, so it is simply absent mid-climb")
	_completes("the_hub_can_re_run_it")
