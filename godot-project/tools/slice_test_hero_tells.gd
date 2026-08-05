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
]

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


func _bb() -> Dictionary:
	return {
		"self_pos": Vector2.ZERO, "self_vel": Vector2.ZERO, "on_floor": true,
		"foe_pos": Vector2(60.0, 0.0), "foe_id": 1, "can_parry": true,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0, "now": 0.0, "class_id": 2,
		"threats": [], "cooldowns": [0.0, 0.0, 0.0, 0.0], "slot_affordable": [true],
	}
