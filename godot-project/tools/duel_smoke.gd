# Run: godot --headless --path godot-project --script tools/duel_smoke.gd
#
# HEADLESS SMOKE TEST FOR THE HUMAN-VS-BOT DUEL. The suite in
# `slice_test_botfight.gd` proves the learning maths; this proves the SCENE — that
# `VersusArena` in duel mode spawns two heroes on opposing factions, that exactly
# one camera is current, that the bot is driven by a real BotController while the
# human's `controller` stays null (so the maker's Input still reaches it), that
# the observation loop actually accumulates, and that the probe writes a report.
#
# It cannot prove FEEL. Nothing headless can — the bot's aggression, whether the
# framing reads, whether a fight against Hard is fun: those need the maker's
# hands. This proves the wiring is not broken before they spend that time.
#
# ⚠ The scene is reached BY PATH, never by `class_name VersusArena`: naming it
# would compile the whole combat chain (and its autoload references) at
# `--script` load time, which is the class-cache trap this project keeps hitting.
extends SceneTree

const SCENE: String = "res://scenes/combat/VersusArena.tscn"
## Long enough for `_ready`, the first physics ticks, and a few hundred
## observation samples to accumulate.
const RUN_FRAMES: int = 240

var _frames: int = 0
var _arena: Node = null
var _fails: int = 0
## Names every check must reach. Missing = the check aborted part-way, which is a
## failure by ABSENCE rather than a silent zero. See slice_test_loadout.gd.
const CHECKS: Array[String] = ["spawned", "factions", "camera", "control", "learning"]
var _completed: Dictionary = {}


func _initialize() -> void:
	print("=== duel smoke ===")
	var scene_res: PackedScene = load(SCENE) as PackedScene
	if scene_res == null:
		printerr("  FAIL could not load %s" % SCENE)
		quit(1)
		return
	var script: GDScript = load("res://scripts/combat/VersusArena.gd") as GDScript
	# The statics ARE the configuration: the scene has no instance to poke before
	# `_ready` runs, which is why they are statics in the first place.
	script.set("duel_human", true)
	script.set("duel_bot_class", 5)        # CRYOMANCER — a ranged kit, so the
	script.set("duel_difficulty", 2)       # spacing + camp-breaker paths get used
	script.set("duel_learning", true)
	_arena = scene_res.instantiate()
	root.add_child(_arena)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < RUN_FRAMES:
		return false
	_check()
	for name: String in CHECKS:
		if not _completed.has(name):
			_fails += 1
			printerr("ABORTED (never completed): %s" % name)
	if _fails == 0:
		print("duel smoke: all PASS")
	else:
		printerr("duel smoke: %d FAILURE(S)" % _fails)
	# Leave the mode off so a later editor F6 lands in the practice arena unless
	# the maker asks for the duel — a test must not change how the game boots.
	(load("res://scripts/combat/VersusArena.gd") as GDScript).set("duel_human", false)
	quit(0 if _fails == 0 else 1)
	return true   # SceneTree._process must return "stop the loop" on every path


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("  ok   %s" % what)
	else:
		_fails += 1
		printerr("  FAIL %s" % what)


func _check() -> void:
	var heroes: Array = root.get_tree().get_nodes_in_group("hero")
	_expect(heroes.size() == 2, "duel mode spawns exactly two heroes (got %d)" % heroes.size())
	var human: Node = _arena.get("_p1")
	var bot: Node = _arena.get("_duel_bot")
	_expect(human != null and bot != null and human != bot, "one human, one bot, distinct")
	_completed["spawned"] = true

	# FACTION — without this the two heroes swing at each other and connect with
	# nothing, which is the single easiest way for this mode to look "built" and be
	# completely inert.
	_expect(StringName(str(human.get("hostile_group"))) == &"duel_bot",
		"the human is hostile to the bot's team")
	_expect(StringName(str(bot.get("hostile_group"))) == &"duel_human",
		"the bot is hostile to the human's team")
	_expect(bot.is_in_group("duel_bot"), "the bot joined its own faction group")
	_expect(human.is_in_group("duel_human"), "the human joined its own faction group")
	_completed["factions"] = true

	# CAMERA — Hero.tscn carries one, and Hero._setup_net_role only disables it in
	# a NETWORKED session. Offline, two live cameras fight over the viewport.
	var live: int = 0
	for h: Node in [human, bot]:
		for c: Node in h.get_children():
			if c is Camera2D and (c as Camera2D).enabled:
				live += 1
	_expect(live == 0, "both hero cameras are disabled (%d still live)" % live)
	_expect(_arena.get("_show_cam") != null, "the arena's pair-framing camera exists")
	_completed["camera"] = true

	# CONTROL — the whole point of the mode. The human must have NO controller, so
	# `Hero._pressed` falls through to the real `Input`.
	_expect(human.get("controller") == null, "the human reads real Input (no controller)")
	var ctrl: Variant = bot.get("controller")
	_expect(ctrl != null, "the bot has a controller")
	if ctrl != null:
		_expect(ctrl.get("brain") != null, "...with the shipped brain attached")
		_expect(not (ctrl.get("profile") as Dictionary).is_empty(),
			"...and a difficulty profile")
		_expect(float(ctrl.get("band_centre")) > 0.0,
			"...and its own spacing band, so the spacing adaptation has a reference")
	_completed["control"] = true

	# LEARNING — the observation loop has to be accumulating, or the feature is a
	# button that does nothing.
	var rec: Dictionary = _arena.get("_learn_rec")
	_expect(not rec.is_empty(), "a learned record was loaded/created")
	_expect(int(rec.get("samples", 0)) > 0,
		"the observation loop is running (%d samples)" % int(rec.get("samples", 0)))
	_expect(int(rec.get("sessions", 0)) >= 1, "the session was counted")
	_expect(float(rec.get("range_sum", 0.0)) > 0.0, "separation is being sampled")
	if ctrl != null:
		_expect(not (ctrl.get("adapt") as Dictionary).is_empty(),
			"the record is attached to the bot")
	_completed["learning"] = true
