# Run: godot --headless --path godot-project --script tools/slice_test_spectated_death.gd
#
# A SPECTATED BOUT HAS A LOSER, AND IT KEEPS ONE.
#
# Maker, watching Watch Bots: *"when they die in spectating they shouldnt stand up
# they died"* and *"the final hit to kill should have some knockback so when they die
# they get knockback and then hit the floor all ragdoll"*.
#
# TWO INDEPENDENT FAULTS PRODUCED ONE SYMPTOM, which is why looking at the ragdoll
# never explained it — the ragdoll was behaving correctly for a body that was not
# dead:
#
#   1. `Hero._die()` outside a run does `hp = max_hp` and returns, so the loser of a
#      duel was HEALED TO FULL. Correct for the F6 feel toy, which is what the arm
#      was written for; wrong for a bout somebody is watching.
#      `BotMatch._put_the_loser_down` toppled the rig separately, so the corpse was a
#      live full-health body wearing a collapsed pose, and `Hero._physics_process`
#      went on re-asserting `set_grounded` / `play()` / the limp every frame.
#
#   2. `CharacterRig.flop()` snapshots `_flop_prev_target` only ON ENTRY, and
#      `Hero.apply_knockback` flops for 0.16-0.42 s on every hit. Any blow in the
#      ~0.4 s before the fatal one therefore left a timer running with a snapshot of
#      0.0; `collapse()` set the limp to 1.0; the stale timer expired and `advance()`
#      put it straight back to 0.0. The corpse then eased upright AT `LIMP_EASE_SPEED`
#      — under the win card, because `_put_the_loser_down` sets the rig to
#      PROCESS_MODE_ALWAYS so it keeps ticking through the freeze.
#
# Fault 2 is the one no existing test could see: `slice_test_death.gd` asserts "a
# collapse never recovers on its own", but it never stages a flop BEFORE the collapse
# — which is the only ordering that reproduces it. That case is the first test here.
#
# ⚠ SCOPE. `stay_dead` is set by `BotMatch` and by nothing else, so free play, the F6
# sandbox and the human 1v1 duel keep the heal they were designed around. Asserted
# directly below, because "we did not change the sandbox" is exactly the kind of
# claim that quietly stops being true.
#
# ⚠ LOADED BY PATH, NEVER BY `class_name`. `Hero` / `CharacterRig` / `BotMatch` reach
# the Sfx / Juice / CombatVfx autoloads, and naming a class here would compile that
# chain at THIS script's parse time.
#
# ⚠ NEVER `failed += _test_x()`. Failures accumulate on `_fails`; every test records a
# COMPLETION SENTINEL so one that aborts half-way fails the suite by absence.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const HERO_PATH: String = "res://scripts/combat/Hero.gd"
const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"
const BOTMATCH_PATH: String = "res://scripts/combat/BotMatch.gd"

const TESTS: Array[String] = [
	"a_flop_taken_before_death_cannot_undo_the_collapse",
	"a_live_flop_still_recovers",
	"a_spectated_loser_stays_at_zero",
	"the_sandbox_still_heals",
	"the_killing_blow_throws_the_body",
	"a_corpse_stops_thinking",
	"a_corpse_keeps_falling_through_the_freeze",
	"botmatch_marks_both_fighters",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_flop_before_death()
	_test_live_flop_recovers()
	_test_loser_stays_dead()
	_test_sandbox_heals()
	_test_launch()
	_test_corpse_stops_thinking()
	_test_corpse_is_always_processed()
	_test_botmatch_marks_fighters()

	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("spectated_death: TEST DID NOT COMPLETE — %s (aborted part-way)" % name)
	if _fails == 0:
		print("spectated death tests: all PASS")
	else:
		printerr("spectated death tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("spectated_death: FAIL — %s" % what)


func _new_rig() -> Node2D:
	var gs: GDScript = load(RIG_PATH) as GDScript
	if gs == null:
		return null
	var rig: Node2D = gs.new() as Node2D
	root.add_child(rig)
	return rig


## A real Hero from the shipped scene, parked on nothing. Returns null if the scene
## cannot be built headlessly, and every caller treats that as a FAILURE rather than
## a skip — a suite that silently tests nothing is the failure mode this repo has
## already been bitten by.
func _new_hero() -> Node2D:
	var ps: PackedScene = load(HERO_SCENE) as PackedScene
	if ps == null:
		return null
	var h: Node2D = ps.instantiate() as Node2D
	if h == null:
		return null
	root.add_child(h)
	return h


# --------------------------------------------------------------------------- 1
## THE RACE, STAGED IN THE ONLY ORDER THAT REPRODUCES IT: flop first (as a
## not-quite-fatal hit does), THEN collapse, then let the stale timer expire.
func _test_flop_before_death() -> void:
	var rig: Node2D = _new_rig()
	_expect(rig != null, "could not construct a CharacterRig")
	if rig == null:
		_completed["a_flop_taken_before_death_cannot_undo_the_collapse"] = true
		return
	# A hit lands. `apply_knockback` flops for up to 0.42 s with the resting limp (0)
	# captured as the recovery target.
	rig.call("flop", 0.6, 0.30)
	_expect(float(rig.get("_flop_prev_target")) <= 0.001,
		"the flop should have captured a resting limp of 0")
	# The next hit kills.
	rig.call("collapse", Vector2.LEFT)
	_expect(float(rig.get("_limp_target")) >= 0.999, "collapse did not go fully limp")
	_expect(bool(rig.get("_collapsed")), "collapse did not set _collapsed")
	# Now run the stale flop timer out, and well past it.
	for i: int in 40:
		rig.call("advance", 0.05)
	_expect(float(rig.get("_limp_target")) >= 0.999,
		"THE CORPSE STOOD BACK UP: a flop taken before death restored _limp_target "
		+ "to %.2f after the collapse" % float(rig.get("_limp_target")))
	_expect(float(rig.get("_limp")) >= 0.9,
		"the corpse eased out of full limp (%.2f)" % float(rig.get("_limp")))
	rig.queue_free()
	_completed["a_flop_taken_before_death_cannot_undo_the_collapse"] = true


# --------------------------------------------------------------------------- 2
## AND THE FIX MUST NOT HAVE BROKEN THE LIVING. A flop on a body that is still alive
## has to recover exactly as it always did, or every hit in the game becomes a
## permanent ragdoll.
func _test_live_flop_recovers() -> void:
	var rig: Node2D = _new_rig()
	_expect(rig != null, "could not construct a CharacterRig")
	if rig == null:
		_completed["a_live_flop_still_recovers"] = true
		return
	rig.call("flop", 0.8, 0.20)
	_expect(float(rig.get("_limp_target")) >= 0.79, "the flop did not go limp")
	for i: int in 20:
		rig.call("advance", 0.05)
	_expect(float(rig.get("_limp_target")) <= 0.001,
		"a LIVE flop failed to recover (target %.2f) — the corpse guard is catching "
			% float(rig.get("_limp_target")) + "bodies that never died")
	rig.queue_free()
	_completed["a_live_flop_still_recovers"] = true


# --------------------------------------------------------------------------- 3
func _test_loser_stays_dead() -> void:
	var h: Node2D = _new_hero()
	_expect(h != null, "could not instance Hero.tscn")
	if h == null:
		_completed["a_spectated_loser_stays_at_zero"] = true
		return
	h.set("stay_dead", true)
	h.call("take_damage", int(h.get("max_hp")) + 50)
	_expect(int(h.get("hp")) == 0,
		"a spectated loser was healed back to %d — it must stay at 0"
			% int(h.get("hp")))
	_expect(bool(h.get("defeated")), "the loser was not marked defeated")
	_expect(not bool(h.get("downed")),
		"a duel loser must not enter the RUN death path (ghost form + revive)")
	var rig: Variant = h.get("rig")
	if rig != null and rig is Object:
		_expect(bool((rig as Object).get("_collapsed")),
			"the loser's rig was not collapsed")
	h.queue_free()
	_completed["a_spectated_loser_stays_at_zero"] = true


# --------------------------------------------------------------------------- 4
## ⚠ THE SCOPE ASSERTION. The heal arm exists so the F6 feel toy never stops, and
## `VersusArena._poll_showcase_end` resets BOTH bodies whenever it sees an hp of 0 —
## so a death that stuck in free play would put the duel into a reset loop.
func _test_sandbox_heals() -> void:
	var h: Node2D = _new_hero()
	_expect(h != null, "could not instance Hero.tscn")
	if h == null:
		_completed["the_sandbox_still_heals"] = true
		return
	# stay_dead deliberately NOT set — this is the sandbox / free-play body.
	var full: int = int(h.get("max_hp"))
	h.call("take_damage", full + 50)
	_expect(int(h.get("hp")) == full,
		"the sandbox stopped healing on death (hp %d of %d) — the feel toy now stops"
			% [int(h.get("hp")), full])
	_expect(not bool(h.get("defeated")),
		"a sandbox death marked the body defeated")
	h.queue_free()
	_completed["the_sandbox_still_heals"] = true


# --------------------------------------------------------------------------- 5
## The launch. Asserted as a real speed and a real direction rather than "non-zero":
## a 5 px/s nudge would satisfy non-zero and would not read as anything at all.
func _test_launch() -> void:
	var h: Node2D = _new_hero()
	_expect(h != null, "could not instance Hero.tscn")
	if h == null:
		_completed["the_killing_blow_throws_the_body"] = true
		return
	h.set("stay_dead", true)
	h.set("facing", Vector2.RIGHT)     # looking at whoever just killed them
	h.call("take_damage", int(h.get("max_hp")) + 50)
	var v: Vector2 = h.get("velocity")
	_expect(v.length() > 200.0,
		"the killing blow barely moved the body (%.0f px/s)" % v.length())
	_expect(v.x < 0.0,
		"the body was thrown TOWARD the killer (vx %.0f) — it must go away" % v.x)
	_expect(v.y < 0.0,
		"the body was driven into the floor (vy %.0f) — a death launches UP first"
			% v.y)
	h.queue_free()
	_completed["the_killing_blow_throws_the_body"] = true


# --------------------------------------------------------------------------- 6
## A corpse must not think. If the bot tick still ran, a dead body would keep
## steering, casting and paying cooldowns for the rest of the bout.
func _test_corpse_stops_thinking() -> void:
	var hero: String = FileAccess.get_file_as_string(HERO_PATH)
	_expect(not hero.is_empty(), "could not read Hero.gd")
	var gate: int = hero.find("if defeated:")
	var tick: int = hero.find("controller.tick(self, _bot_clock)")
	_expect(gate >= 0, "the defeated early-out is gone from _physics_process")
	_expect(tick >= 0, "could not find the bot tick — this test is now measuring nothing")
	_expect(gate >= 0 and tick >= 0 and gate < tick,
		"the defeated early-out must come BEFORE the bot tick, or a corpse keeps "
		+ "thinking for the rest of the bout")
	# ...and it must not re-pose the rig, which is the whole bug.
	var body: int = hero.find("func _process_defeated")
	_expect(body >= 0, "_process_defeated is gone")
	if body >= 0:
		var chunk: String = hero.substr(body, 900)
		_expect(not chunk.contains("rig.play("),
			"_process_defeated calls rig.play() — that is what stood the corpse up")
		_expect(not chunk.contains("set_limp("),
			"_process_defeated calls set_limp() — that is what stood the corpse up")
	_completed["a_corpse_stops_thinking"] = true


# --------------------------------------------------------------------------- 7
## `BotMatch._decide` pauses the tree inside the same frame as the fatal
## `health_changed`, which lands BEFORE `_die` runs. A pausable corpse is launched and
## then hangs in mid-air under the win card.
func _test_corpse_is_always_processed() -> void:
	var h: Node2D = _new_hero()
	_expect(h != null, "could not instance Hero.tscn")
	if h == null:
		_completed["a_corpse_keeps_falling_through_the_freeze"] = true
		return
	h.set("stay_dead", true)
	h.call("take_damage", int(h.get("max_hp")) + 50)
	_expect(h.process_mode == Node.PROCESS_MODE_ALWAYS,
		"a defeated body is still pausable — it will freeze in mid-air the frame "
		+ "BotMatch pauses the tree, which is the same frame it was launched")
	h.queue_free()
	_completed["a_corpse_keeps_falling_through_the_freeze"] = true


# --------------------------------------------------------------------------- 8
## And the flag actually gets set, on BOTH sides. Checked by source text because
## staging a whole BotMatch needs the arena, four autoloads and two bot brains.
func _test_botmatch_marks_fighters() -> void:
	var bm: String = FileAccess.get_file_as_string(BOTMATCH_PATH)
	_expect(not bm.is_empty(), "could not read BotMatch.gd")
	_expect(bm.contains("\"stay_dead\""),
		"BotMatch no longer marks its fighters stay_dead — the loser will be healed "
		+ "to full again and the corpse will stand up")
	# It must be inside the per-side loop in _adopt_fighters, not on one fighter.
	var adopt: int = bm.find("func _adopt_fighters")
	var mark: int = bm.find("\"stay_dead\"")
	_expect(adopt >= 0 and mark > adopt,
		"stay_dead is not set from _adopt_fighters — both sides must be marked")
	_completed["botmatch_marks_both_fighters"] = true
