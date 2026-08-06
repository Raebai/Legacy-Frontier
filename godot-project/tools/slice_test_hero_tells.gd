# THE HERO'S SWINGS ARE VISIBLE TO THE DODGE LAYER — asserted, because their ABSENCE
# was invisible to every suite in the repo for the whole life of the project.
#
# `Hero` published no `Telegraph` at all, so the three contact classes (Brawler,
# Juggernaut, Swordsaint) produced ZERO threat descriptors when fighting each other:
# `BotBrain._reflex` returned empty on every frame, the dodge ladder was never entered
# and the parry rung under it was never reached. Nothing failed — there was simply
# never anything to see.
#
#   godot --headless --path godot-project --script tools/slice_test_hero_tells.gd
extends SceneTree

const TELEGRAPH_PATH: String = "res://scripts/combat/Telegraph.gd"

## Registered by name so a test that is never CALLED fails loudly instead of being
## silently absent — the by-absence armour this repo already relies on.
const TESTS: Array[String] = [
	"a_swing_tell_is_perceived_as_a_threat",
	"a_caster_does_not_perceive_its_own_tell",
	"a_short_tell_can_reach_the_parry_rung",
	"a_long_tell_still_uses_the_class_band",
	"a_real_hero_ability_tells_the_foe_and_not_itself",
]

const HERO_SCENE_PATH: String = "res://scenes/combat/Hero.tscn"

var _failures: Array[String] = []
var _ran: Dictionary = {}


## ⚠ DRIVEN FROM `_process`, NOT FROM `_init`. A `SceneTree` script's `_init` runs
## before `root` exists, so `root.add_child` there is a no-op against a null parent and
## every group scan comes back EMPTY. The first version of this suite did exactly that
## and two of its four tests passed on the vacuum — see the second-source assertion in
## `_test_a_caster_does_not_perceive_its_own_tell` for the armour against it.
var _started: bool = false


func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true


func _run() -> void:
	_test_a_swing_tell_is_perceived_as_a_threat()
	_test_a_caster_does_not_perceive_its_own_tell()
	_test_a_short_tell_can_reach_the_parry_rung()
	_test_a_long_tell_still_uses_the_class_band()
	_test_a_real_hero_ability_tells_the_foe_and_not_itself()
	for name: String in TESTS:
		if not _ran.has(name):
			_failures.append("test `%s` is registered but was never called" % name)
	if _failures.is_empty():
		print("Hero tell tests: all PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("FAIL: %s" % f)
		print("Hero tell tests: %d FAILED" % _failures.size())
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _completes(name: String) -> void:
	_ran[name] = true


## A stand-in swinger. `perceive_threats` only ever reads identity off `source`, so a
## bare Node2D is the honest fixture — using a real `Hero` would drag in the autoloads
## the nova suite's header warns about.
func _swinger() -> Node2D:
	var n := Node2D.new()
	root.add_child(n)
	return n


func _tell(at: Vector2, radius: float, windup: float, src: Node2D) -> Node2D:
	var t: Node2D = (load(TELEGRAPH_PATH) as GDScript).new() as Node2D
	root.add_child(t)
	t.global_position = at
	t.set("source", src)
	t.call("start", radius, windup)
	return t


# ─────────────────────────────────────────────────────────────────────── the tests

func _test_a_swing_tell_is_perceived_as_a_threat() -> void:
	var swinger: Node2D = _swinger()
	var victim: Node2D = _swinger()
	var t: Node2D = _tell(Vector2(40.0, 0.0), 32.0, 0.077, swinger)
	var seen: Array = BotController.perceive_threats(self, Vector2.ZERO, victim)
	var mine: Array = seen.filter(func(d: Dictionary) -> bool:
		return int(d.get("id", 0)) == t.get_instance_id())
	_expect(mine.size() == 1,
		"a swing tell is perceived by the other fighter (saw %d)" % mine.size())
	if mine.size() == 1:
		var d: Dictionary = mine[0]
		_expect(String(d.get("kind", "")) == "circle", "a swing tell reads as a circle")
		_expect(bool(d.get("parryable", false)), "a swing tell is parryable")
		# THE FIELD THE WHOLE PARRY FIX RESTS ON.
		_expect(absf(float(d.get("lead", -1.0)) - 0.077) < 0.001,
			"the tell publishes its TOTAL lead (got %s)" % d.get("lead", "missing"))
	_completes("a_swing_tell_is_perceived_as_a_threat")


## ⚠ THE TRAP. There was no owner filter on telegraphs at all, so the first hero tell
## in the game would have made its own caster dodge it every frame it existed.
func _test_a_caster_does_not_perceive_its_own_tell() -> void:
	var swinger: Node2D = _swinger()
	var other: Node2D = _swinger()
	var t: Node2D = _tell(Vector2(400.0, 0.0), 32.0, 0.077, swinger)
	# ⚠ A SECOND TELL FROM SOMEBODY ELSE, and it is the whole reason this test means
	# anything. "I did not see my own tell" is also what a scan that sees NOTHING says,
	# and the first version of this suite reported a clean pass while perceiving an
	# empty world. The other tell must survive the same call that drops mine.
	var theirs: Node2D = _tell(Vector2(420.0, 0.0), 32.0, 0.077, other)
	var seen: Array = BotController.perceive_threats(self, Vector2(400.0, 0.0), swinger)
	var mine: Array = seen.filter(func(d: Dictionary) -> bool:
		return int(d.get("id", 0)) == t.get_instance_id())
	var not_mine: Array = seen.filter(func(d: Dictionary) -> bool:
		return int(d.get("id", 0)) == theirs.get_instance_id())
	_expect(mine.is_empty(), "a fighter does not perceive its OWN tell as a threat")
	_expect(not_mine.size() == 1,
		"...while somebody ELSE'S tell in the same scan is still perceived (saw %d) — "
		% not_mine.size() + "without this the test passes on an empty world")
	_completes("a_caster_does_not_perceive_its_own_tell")


## The arithmetic that made the contact roster unparryable: a 0.077 s tell against a
## ~0.37 s class guard band can never satisfy `|tti - band| <= slack`, on any frame.
func _test_a_short_tell_can_reach_the_parry_rung() -> void:
	var profile: Dictionary = BotProfile.of(2)
	var reached: bool = false
	# Walk the tell down its whole life at 60 Hz and ask whether the rung EVER opens.
	for step: int in 6:
		var tti: float = 0.077 - float(step) * (1.0 / 60.0)
		if tti <= 0.0:
			break
		var threat: Dictionary = {
			"threatening": true, "tti": tti, "lead": 0.077, "parryable": true,
			"exit": Vector2(0.0, -18.0), "exit_len": 18.0, "degenerate": false,
		}
		var caps: Dictionary = BotBrain._caps(_bb(), profile, BotBrain.Memory.new(), 0.0, threat)
		if bool(caps.get("parry_ready", false)):
			reached = true
			break
	_expect(reached,
		"a 0.077 s melee tell can reach the parry rung on at least one frame — "
		+ "without the band collapsing onto the tell's own lead it never can")
	_completes("a_short_tell_can_reach_the_parry_rung")


## ⚠ THE BY-ABSENCE ARM. Collapsing the band must only ever TIGHTEN it. A tell longer
## than the class band must still be judged against the class band, or this would have
## quietly made every slow enemy wind-up parryable from the first frame it appeared.
func _test_a_long_tell_still_uses_the_class_band() -> void:
	var profile: Dictionary = BotProfile.of(2)
	var threat: Dictionary = {
		"threatening": true, "tti": 0.90, "lead": 0.90, "parryable": true,
		"exit": Vector2(0.0, -18.0), "exit_len": 18.0, "degenerate": false,
	}
	var caps: Dictionary = BotBrain._caps(_bb(), profile, BotBrain.Memory.new(), 0.0, threat)
	_expect(not bool(caps.get("parry_ready", false)),
		"a 0.90 s tell with 0.90 s still to run is NOT in the guard lead — the band "
		+ "collapse must never widen the window, only tighten it")
	_completes("a_long_tell_still_uses_the_class_band")


## END TO END, ON A REAL `Hero`, FOR THE FOUR ABILITIES THAT USED TO HIT ON THE PRESS.
##
## The unit tests above use bare `Telegraph`s, so they prove the perception CONTRACT
## and nothing about whether the game actually honours it. These four abilities each
## reach the tell by a different route — two through `BlastSpell.detonate_at`, two
## through `Hero._telegraphed_ability` — and only one of those four paths stamps
## `source` in code this file can see. A route that forgot the stamp would make its own
## caster dodge its own ability for the whole lead, every time, forever.
func _test_a_real_hero_ability_tells_the_foe_and_not_itself() -> void:
	for row: Array in [[2, "_uppercut"], [2, "_fire_punch"], [5, "_primary_frost_cone"],
			[3, "_ground_slam"]]:
		var cls: int = row[0]
		var call_name: String = row[1]
		var hero: CharacterBody2D = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
		root.add_child(hero)
		hero.global_position = Vector2(float(cls) * 4000.0, 0.0)  # each pair far from the rest
		if hero.has_method("configure_class"):
			hero.call("configure_class", cls)
		hero.set("facing", Vector2.RIGHT)
		hero.set("_aim_dir", Vector2.RIGHT)
		var foe: Node2D = Node2D.new()
		root.add_child(foe)
		foe.global_position = hero.global_position + Vector2(40.0, 0.0)
		# ⚠ SCOPED TO THE TELLS THIS CALL CREATES. `perceive_threats` applies NO distance
		# cull — deliberately, a telegraph anywhere on the stage is a telegraph — so a
		# naive count here also counts every tell the PREVIOUS iterations left alive,
		# and the first version of this test read 3 / 4 / 5 / 6 and blamed the code.
		# Moving the fighters apart does not help; only identity does.
		var before: Dictionary = {}
		for t: Node in get_nodes_in_group(&"telegraph"):
			before[t.get_instance_id()] = true
		hero.call(call_name)
		var by_foe: int = _fresh(
			BotController.perceive_threats(self, foe.global_position, foe), before)
		var by_self: int = _fresh(
			BotController.perceive_threats(self, hero.global_position, hero), before)
		_expect(by_foe >= 1, "%s publishes a tell the foe can see (saw %d)" % [call_name, by_foe])
		_expect(by_self == 0,
			"%s does NOT make its own caster dodge it (caster saw %d)" % [call_name, by_self])
		hero.queue_free()
		foe.queue_free()
		for t: Node in get_nodes_in_group(&"telegraph"):
			t.free()   # immediate, so the next row starts from a clean board
	_completes("a_real_hero_ability_tells_the_foe_and_not_itself")


## How many of `seen` were created since the `before` snapshot.
func _fresh(seen: Array, before: Dictionary) -> int:
	var n: int = 0
	for d: Dictionary in seen:
		if not before.has(int(d.get("id", 0))):
			n += 1
	return n


func _bb() -> Dictionary:
	return {
		"self_pos": Vector2.ZERO, "self_vel": Vector2.ZERO, "on_floor": true,
		"foe_pos": Vector2(60.0, 0.0), "foe_id": 1, "can_parry": true,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0, "now": 0.0, "class_id": 2,
		"threats": [], "cooldowns": [0.0, 0.0, 0.0, 0.0], "slot_affordable": [true],
	}
