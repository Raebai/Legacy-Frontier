# Run: godot --headless --path godot-project --script tools/slice_test_death.gd
# THE DEATH BEAT — does a body actually go down, and does it clean up after itself.
#
# The maker's complaint this suite exists to keep fixed: *"where is the ragdoll when
# they die"*. At the KO the loser stood BOLT UPRIGHT, and every dead enemy left a
# static, upright silhouette skating sideways. Two mechanisms now answer that, and
# they are different on purpose (see the header of `scripts/combat/DeathSmudge.gd`):
#
#   * `CharacterRig.collapse()` for a body that STAYS  (downed hero, bot-match loser)
#   * `DeathSmudge`             for a body that is FREED (every `Enemy`)
#
# ⚠ THE HOUSE RULE. Never `failed += _test_x()` — a dead property read aborts the
# enclosing function and hands back the type's zero, which that idiom reads as "no
# failures"; it silently disabled 64 suites here once. Failures accumulate on the
# MEMBER `_fails`, and every test records a COMPLETION SENTINEL as its last line, so a
# test that aborts part-way fails BY ABSENCE, whatever moved house.
#
# ⚠ AND THE SECOND RULE: an invariant that is trivially true of an empty result is not
# an invariant. "No enemy died without a death animation" passes gloriously when
# nothing died. `_test_every_enemy_death_animates` therefore asserts a MINIMUM
# OCCURRENCE RATE — it kills a known number of real `Enemy` bodies and requires a
# smudge for a stated fraction of them — so a wiring break that silently produces zero
# deaths fails instead of passing.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const SMUDGE_PATH: String = "res://scripts/combat/DeathSmudge.gd"
const ENEMY_SCENE: String = "res://scenes/combat/Enemy.tscn"
const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"
const BOTMATCH_SCRIPT: String = "res://scripts/combat/BotMatch.gd"

## How many real enemies the occurrence-rate test kills. Small enough to stay under
## `DeathSmudge.MAX_ALIVE` (so the cap is not what is being measured) and large enough
## that "one lucky one worked" is not a passing grade.
const DEATHS_TO_STAGE: int = 5
## ...and the fraction of them that MUST have produced a death animation. 1.0 — there
## is no legitimate reason for a death under the cap to skip it.
const MIN_DEATH_ANIM_RATE: float = 1.0

## Members `DeathSmudge` is reached through dynamically (it is loaded by path, never by
## `class_name`, so every access is a runtime lookup). Named once so a relocation is a
## one-line diagnosis instead of a hunt.
const SMUDGE_MEMBERS: Array[String] = [
	"pose", "fig_height", "base_color", "fall_dir", "duration", "_age", "_heap", "_low",
]
## ...and the rig members / methods the collapse contract depends on.
const RIG_MEMBERS: Array[String] = [
	"_limp", "_limp_target", "_flash_timer", "_lean_cap", "_collapsed",
]

const TESTS: Array[String] = [
	"collapse_goes_fully_limp",
	"collapse_topples_the_way_it_sprawls",
	"collapse_is_a_hold_not_a_flop",
	"clear_flash_restores_the_tint",
	"a_corpse_does_not_flash",
	"smudge_folds_then_erases",
	"smudge_frees_itself",
	"smudge_is_capped",
	"smudge_survives_a_paused_tree",
	"low_quality_is_a_strict_subset",
	"every_enemy_death_animates",
	"hero_death_leaves_a_body_and_stays_revivable",
	"botmatch_puts_the_loser_down",
	"the_card_waits_for_a_quiet_screen",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _smudge_script: GDScript = null


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_smudge_script = load(SMUDGE_PATH) as GDScript
	_require_smudge_members()
	_require_rig_members()
	_test_collapse_goes_fully_limp()
	_test_collapse_topples_the_way_it_sprawls()
	_test_collapse_is_a_hold_not_a_flop()
	_test_clear_flash_restores_the_tint()
	_test_a_corpse_does_not_flash()
	_test_smudge_folds_then_erases()
	_test_smudge_frees_itself()
	_test_smudge_is_capped()
	_test_smudge_survives_a_paused_tree()
	_test_low_quality_is_a_strict_subset()
	_test_every_enemy_death_animates()
	_test_hero_death_leaves_a_body_and_stays_revivable()
	_test_botmatch_puts_the_loser_down()
	_test_the_card_waits_for_a_quiet_screen()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Death tests: %d FAILED" % _fails)
		quit(1)
		return true
	print("Death tests: all PASS")
	quit(0)
	return true


# ══════════════════════════════════════════════════════ collapse — the body that STAYS

## Full ragdoll, held. Not "a bit loose": `_limp_target` at 1 is what drops the ride
## height toward `RIDE_PRONE`, and that is the thing that puts a body ON THE FLOOR.
func _test_collapse_goes_fully_limp() -> void:
	var rig: Node2D = _make_rig()
	rig.call("collapse", Vector2(1.0, -0.4))
	_expect(float(rig.get("_limp_target")) >= 0.999,
		"collapse holds the limp target at 1 (got %.2f)" % float(rig.get("_limp_target")))
	# ...and is ALREADY past the sprawl threshold on the frame it dies, without waiting
	# for the ease — which runs on the scaled clock and so is 20x slower under the
	# hit-stop that fires on the killing blow. That wait is what kept the bot-match
	# loser standing through its own KO.
	_expect(float(rig.get("_limp")) > 0.35,
		"the body is loose on the death frame itself (%.2f)" % float(rig.get("_limp")))
	_expect(float(rig.get("_limp")) < 1.0,
		"...but not snapped to full — the rest still melts (%.2f)"
			% float(rig.get("_limp")))
	_step(rig, 30)
	_expect(float(rig.get("_limp")) >= 0.95,
		"...and the eased value gets there (got %.2f)" % float(rig.get("_limp")))
	rig.queue_free()
	_completes("collapse_goes_fully_limp")


## THE MEASURED BUG. `_step_body` sprawls toward `facing * PRONE_LEAN`, but
## `apply_impulse` spins in WORLD space — so a blow from the front used to start the
## torso rotating AWAY from the fall it was about to do, and at `PITCH_GAIN_LIMP` 0.22
## the spring spent most of a second cancelling itself. The body must tip the way it
## sprawls no matter which side the killing blow came from.
func _test_collapse_topples_the_way_it_sprawls() -> void:
	for face_right: bool in [true, false]:
		for from_x: float in [1.0, -1.0]:
			var rig: Node2D = _make_rig()
			rig.call("set_facing", Vector2.RIGHT if face_right else Vector2.LEFT)
			rig.call("collapse", Vector2(from_x, -0.4))
			var want: float = 1.0 if face_right else -1.0
			_step(rig, 24)
			var pitch: float = rig.rotation
			_expect(signf(pitch) == want and absf(pitch) > 0.35,
				"facing %s, blow from x=%+.0f: topples toward the sprawl (pitch %+.2f)"
					% ["R" if face_right else "L", from_x, pitch])
			rig.queue_free()
	_completes("collapse_topples_the_way_it_sprawls")


## A death is a HOLD, not a flop. `flop()` auto-recovers to the pre-hit limp after its
## hold window — a dead body that stands back up is the bug this distinguishes.
func _test_collapse_is_a_hold_not_a_flop() -> void:
	var rig: Node2D = _make_rig()
	rig.call("collapse", Vector2(1.0, 0.0))
	_step(rig, 120)                      # two full seconds, well past any flop hold
	_expect(float(rig.get("_limp_target")) >= 0.999,
		"a collapse never recovers on its own (target %.2f)"
			% float(rig.get("_limp_target")))
	# ...and `set_limp(0)` — what `Hero.revive` calls — still lets it back up.
	rig.call("set_limp", 0.0)
	_step(rig, 60)
	_expect(float(rig.get("_limp")) <= 0.05,
		"...and a revive clears it (limp %.2f)" % float(rig.get("_limp")))
	rig.queue_free()
	_completes("collapse_is_a_hold_not_a_flop")


## The RED-KO bug: `_flash_timer` only ticks inside `advance()`, so on a paused tree a
## hit-flash never expires and `_draw` keeps preferring it over `limb_color`.
## `clear_flash` is what `BotMatch` uses to stop the KO frame recording flat red.
func _test_clear_flash_restores_the_tint() -> void:
	var rig: Node2D = _make_rig()
	rig.call("set_tint", Color(1.0, 0.82, 0.22))
	rig.call("flash_color", Color(1.0, 0.2, 0.2), 0.12)
	_expect(float(rig.get("_flash_timer")) > 0.0, "a flash is live before clearing")
	rig.call("clear_flash")
	_expect(float(rig.get("_flash_timer")) <= 0.0,
		"clear_flash ends it (timer %.3f)" % float(rig.get("_flash_timer")))
	rig.call("clear_flash")              # idempotent
	_expect(float(rig.get("_flash_timer")) <= 0.0, "...and is idempotent")
	_expect(Color(rig.get("limb_color")).is_equal_approx(Color(1.0, 0.82, 0.22)),
		"...and never touches the tint itself")
	rig.queue_free()
	_completes("clear_flash_restores_the_tint")


## A CORPSE DOES NOT FLASH. Clearing the flash once a frame was not enough: a dead body
## keeps getting hit (leftover projectiles, a lingering zone, a spectacle that outlives
## its caster), and anything that damages LATER in the same frame than the clear repaints
## the whole figure red for that draw. Photographed at +1.60 s of a frozen KO. So the
## suppression lives on the rig and covers every path, not just the bot match.
func _test_a_corpse_does_not_flash() -> void:
	var rig: Node2D = _make_rig()
	rig.call("set_tint", Color(0.3, 0.64, 1.0))
	rig.call("collapse", Vector2(1.0, 0.0))
	_expect(float(rig.get("_flash_timer")) <= 0.0, "collapsing ends any live flash")
	rig.call("flash_color", Color(1.0, 0.2, 0.2), 0.12)
	_expect(float(rig.get("_flash_timer")) <= 0.0,
		"...and a hit on the corpse cannot start a new one (timer %.3f)"
			% float(rig.get("_flash_timer")))
	# ...but a REVIVED body flashes again, or the hero would lose its hit feedback
	# permanently after the first death of a run.
	rig.call("set_limp", 0.0)
	rig.call("flash_color", Color(1.0, 0.2, 0.2), 0.12)
	_expect(float(rig.get("_flash_timer")) > 0.0,
		"a revived body gets its hit feedback back (timer %.3f)"
			% float(rig.get("_flash_timer")))
	rig.queue_free()
	_completes("a_corpse_does_not_flash")


# ═══════════════════════════════════════════════ DeathSmudge — the body that is FREED

## The two halves of the beat, measured rather than assumed: the pose must MOVE toward
## the heap (a body that folds), and the figure must END invisible (a body that is
## rubbed out). A smudge that renders the death pose and then simply vanishes is the
## old static corpse with extra steps.
func _test_smudge_folds_then_erases() -> void:
	var rig: Node2D = _make_rig()
	_step(rig, 2)
	var s: Node2D = _spawn_smudge(rig)
	if s == null:
		_expect(false, "a smudge spawns from a live rig")
		return
	var start: Dictionary = s.get("pose")
	var head0: Vector2 = start["head_center"]
	var foot_y: float = maxf(Vector2(start["foot_lead"]).y, Vector2(start["foot_off"]).y)
	# Fold: sampled through the PUBLIC blend, so this tests the drawn pose.
	var folded: Dictionary = s.call("_blend_pose", 1.0)
	var head1: Vector2 = folded["head_center"]
	_expect(head1.y > head0.y + 1.0,
		"the head DROPS as the body folds (%.1f -> %.1f)" % [head0.y, head1.y])
	_expect(head1.y >= foot_y - float(s.get("fig_height")) * 0.35,
		"...to somewhere near the ground line, not to a standing height")
	_expect(absf(head1.x - head0.x) > 1.0, "...and the body topples sideways, not straight down")
	# Erase: the figure's alpha must actually reach zero inside the beat.
	_expect(float(s.call("_erase_amount", 0.0)) == 0.0, "nothing is erased at t=0")
	_expect(float(s.call("_erase_amount", 1.0)) >= 0.999,
		"the figure is fully erased by the end (got %.2f)" % float(s.call("_erase_amount", 1.0)))
	_expect(float(s.call("_fold_amount", 1.0)) >= 0.95, "the fold completes")
	s.queue_free()
	rig.queue_free()
	_completes("smudge_folds_then_erases")


## It must not leak. A wave kills five bodies at a time and the arena runs for minutes.
func _test_smudge_frees_itself() -> void:
	var rig: Node2D = _make_rig()
	_step(rig, 2)
	var s: Node2D = _spawn_smudge(rig, 0.12)
	if s == null:
		_expect(false, "a smudge spawns")
		return
	_expect(get_nodes_in_group("death_smudge").size() >= 1, "it joins the group while alive")
	var began: int = Time.get_ticks_msec()
	while is_instance_valid(s) and Time.get_ticks_msec() - began < 3000:
		# Real-time clocked, so this waits on the WALL and not on frames.
		root.get_tree().root.propagate_notification(0)
		OS.delay_msec(10)
		s.call("_process", 0.01)
	_expect(not is_instance_valid(s) or s.is_queued_for_deletion(),
		"it frees itself once the beat is over")
	rig.queue_free()
	_completes("smudge_frees_itself")


## Five bodies dying in one frame must not become five bodies' worth of unbounded work.
func _test_smudge_is_capped() -> void:
	var rig: Node2D = _make_rig()
	_step(rig, 2)
	var cap: int = int(_smudge_script.get("MAX_ALIVE"))
	var made: Array[Node2D] = []
	for _i: int in cap + 6:
		var s: Node2D = _spawn_smudge(rig, 9.0)   # long beat: none expire mid-test
		if s != null:
			made.append(s)
	_expect(made.size() <= cap,
		"the concurrency cap holds (%d made, cap %d)" % [made.size(), cap])
	_expect(made.size() >= mini(cap, 4),
		"...and is not so tight that ordinary waves lose the beat (%d made)" % made.size())
	# ⚠ `free()`, NOT `queue_free()`. A queued free is deferred to the end of the frame,
	# and every test in this file runs inside ONE frame — so a dozen 9-second smudges
	# left queued here still occupy the cap, and the next test that spawns one gets
	# `null` and fails for a reason that has nothing to do with what it is testing.
	# That is exactly what happened on this suite's first run.
	for s: Node2D in made:
		s.free()
	rig.queue_free()
	_completes("smudge_is_capped")


## ⚠ LOAD-BEARING FOR THE BOT MATCH. `BotMatch._freeze()` pauses the whole tree on the
## decisive frame, and `Juice.hit_stop` drops `Engine.time_scale` to 0.05 on the same
## blow. A death animation driven by `delta` would be frozen, or play at 1/20 speed,
## exactly where it is recorded.
func _test_smudge_survives_a_paused_tree() -> void:
	var rig: Node2D = _make_rig()
	_step(rig, 2)
	var s: Node2D = _spawn_smudge(rig)
	if s == null:
		_expect(false, "a smudge spawns")
		return
	_expect(s.process_mode == Node.PROCESS_MODE_ALWAYS,
		"the smudge processes on a paused tree (mode %d)" % s.process_mode)
	# ...and its clock is the WALL, not the frame. Ticking it with a zero delta must
	# still age it, which is only true of a real-time clock.
	var age0: float = float(s.get("_age"))
	OS.delay_msec(60)
	s.call("_process", 0.0)
	_expect(float(s.get("_age")) > age0,
		"...and ages on real time, not on delta (%.3f -> %.3f)"
			% [age0, float(s.get("_age"))])
	s.queue_free()
	rig.queue_free()
	_completes("smudge_survives_a_paused_tree")


## LOW must be a STRICT NON-BLANK SUBSET: fewer garnish elements, never zero of the
## thing that carries the read. The fold and the fade are not allowed to thin.
func _test_low_quality_is_a_strict_subset() -> void:
	var strokes_hi: int = int(_smudge_script.get("STROKES"))
	var strokes_lo: int = int(_smudge_script.get("STROKES_LOW"))
	var crumbs_hi: int = int(_smudge_script.get("CRUMBS"))
	var crumbs_lo: int = int(_smudge_script.get("CRUMBS_LOW"))
	var cap_hi: int = int(_smudge_script.get("MAX_ALIVE"))
	var cap_lo: int = int(_smudge_script.get("MAX_ALIVE_LOW"))
	_expect(strokes_lo < strokes_hi and strokes_lo >= 1,
		"LOW thins the eraser strokes but keeps at least one (%d of %d)"
			% [strokes_lo, strokes_hi])
	_expect(crumbs_lo < crumbs_hi, "LOW drops the graphite crumbs (%d of %d)"
		% [crumbs_lo, crumbs_hi])
	_expect(cap_lo < cap_hi and cap_lo >= 4,
		"LOW tightens the concurrency cap but still shows a wave's worth (%d of %d)"
			% [cap_lo, cap_hi])
	# The read itself is quality-independent: a LOW smudge must still fold and still
	# fade. Both are computed from constants, never from `_low`.
	var rig: Node2D = _make_rig()
	_step(rig, 2)
	var s: Node2D = _spawn_smudge(rig)
	if s == null:
		_expect(false, "a smudge spawns")
		return
	s.set("_low", true)
	_expect(float(s.call("_fold_amount", 1.0)) >= 0.95, "LOW still folds the body")
	_expect(float(s.call("_erase_amount", 1.0)) >= 0.999, "LOW still erases it")
	s.queue_free()
	rig.queue_free()
	_completes("low_quality_is_a_strict_subset")


# ═══════════════════════════════════════════════════════ the three real death paths

## ⚠ A MINIMUM OCCURRENCE RATE, not "nothing died without an animation". The latter is
## true of an empty arena, and this repo has shipped exactly that kind of vacuous
## invariant before. Real `Enemy` bodies, really killed, and the count is asserted.
func _test_every_enemy_death_animates() -> void:
	var scene: PackedScene = load(ENEMY_SCENE) as PackedScene
	if scene == null:
		_expect(false, "the Enemy scene loads")
		return
	var host: Node2D = Node2D.new()
	root.add_child(host)
	for s: Node in get_nodes_in_group("death_smudge"):
		s.queue_free()
	await_free()
	var killed: int = 0
	for i: int in DEATHS_TO_STAGE:
		var e: Node2D = scene.instantiate() as Node2D
		e.position = Vector2(float(i) * 90.0, 0.0)
		host.add_child(e)
		if not e.has_method("_die"):
			_expect(false, "Enemy still has the death entry point this suite drives")
			host.queue_free()
			return
		e.set("passive", false)
		e.call("_die")
		killed += 1
	var animated: int = get_nodes_in_group("death_smudge").size()
	_expect(killed == DEATHS_TO_STAGE,
		"the suite actually staged %d deaths (got %d)" % [DEATHS_TO_STAGE, killed])
	_expect(float(animated) >= float(killed) * MIN_DEATH_ANIM_RATE,
		"every enemy death produced a death animation (%d of %d)" % [animated, killed])
	host.queue_free()
	_completes("every_enemy_death_animates")


## A hero death is a TRANSITION INTO THE GHOST, not a corpse: the body left behind is a
## separate node, and nothing about it may block the revive the whole rule depends on.
func _test_hero_death_leaves_a_body_and_stays_revivable() -> void:
	var scene: PackedScene = load(HERO_SCENE) as PackedScene
	if scene == null:
		_expect(false, "the Hero scene loads")
		return
	for s: Node in get_nodes_in_group("death_smudge"):
		s.queue_free()
	await_free()
	var host: Node2D = Node2D.new()
	root.add_child(host)
	var hero: Node2D = scene.instantiate() as Node2D
	host.add_child(hero)
	if not hero.has_method("_enter_downed") or not hero.has_method("revive"):
		_expect(false, "Hero still has the downed/revive pair this suite drives")
		host.queue_free()
		return
	hero.call("_enter_downed")
	_expect(bool(hero.get("downed")), "the hero is a ghost")
	_expect(get_nodes_in_group("death_smudge").size() >= 1,
		"...and a body is left behind to be rubbed out")
	var rig: Variant = hero.get("rig")
	_expect(rig != null and float((rig as Object).get("_limp_target")) >= 0.999,
		"...and the live body itself went limp (the flop/limp system, not a new one)")
	# THE THING THAT MUST NOT BREAK.
	hero.call("revive", 0.45)
	_expect(not bool(hero.get("downed")), "a revive still brings the hero back up")
	_expect(int(hero.get("hp")) > 0, "...with hp on the board (%s)" % str(hero.get("hp")))
	_expect(rig != null and float((rig as Object).get("_limp_target")) <= 0.001,
		"...and clears the death ragdoll")
	host.queue_free()
	_completes("hero_death_leaves_a_body_and_stays_revivable")


## The KO frame is the one that gets RECORDED, so the two things wrong with it are
## asserted structurally: the loser must be put down BEFORE the freeze (nothing
## pausable moves after it), and the corner colours must be re-asserted EVERY frame
## (the killing blow's red flash is set AFTER `_decide` returns).
## THE CARD USED TO LAND ON THE KILL. `FREEZE_BEAT` (0.55 s) was the whole gate,
## but the finisher taunt holds 1.9 s and the killing blow's damage number runs up
## to 0.864 s — and is spawned onto an already-paused tree, so it begins AFTER the
## freeze. The card came down over both.
##
## Asserts the GATE, not the constant: a test that pinned a bigger number would go
## green and rot the moment a taunt or an effect lifetime moved.
func _test_the_card_waits_for_a_quiet_screen() -> void:
	var script: GDScript = load(BOTMATCH_SCRIPT) as GDScript
	if script == null:
		_expect(false, "BotMatch.gd loads")
		return
	var bm: Object = script.new()
	_expect(bm.has_method(&"_screen_is_quiet"),
		"BotMatch asks the screen whether it is quiet")
	# A live taunt bubble is the long pole, and it is the one thing with no count
	# and no lifetime query anywhere — so `_taunt` latches its own expiry.
	bm.set("_taunt_until", bm.call(&"_real_seconds") + 5.0)
	_expect(not bool(bm.call(&"_screen_is_quiet")),
		"a taunt bubble still on screen is NOT quiet")
	bm.set("_taunt_until", 0.0)
	_expect(bool(bm.call(&"_screen_is_quiet")),
		"…and with nothing left alive, it is")
	# The backstop: a stuck effect must never be able to eat the card entirely.
	_expect(float(script.get(&"RESULT_MAX_WAIT")) > float(script.get(&"FREEZE_BEAT")),
		"the ceiling is above the minimum beat, so the gate has room to wait")
	_expect(float(script.get(&"RESULT_MAX_WAIT")) <= 4.0,
		"…and is still short enough that a hung effect does not strand the player")
	bm.free()
	_completes("the_card_waits_for_a_quiet_screen")


func _test_botmatch_puts_the_loser_down() -> void:
	var script: GDScript = load(BOTMATCH_SCRIPT) as GDScript
	var scene: PackedScene = load(HERO_SCENE) as PackedScene
	if script == null or scene == null:
		_expect(false, "the BotMatch script and the Hero scene both load")
		return
	# A BotMatch NOT added to the tree, so `_ready` never builds the whole versus arena
	# (which would mean a real 15-second bot fight inside a unit suite). The two things
	# under test read `_fighters` and nothing else.
	var bm: Node = script.new() as Node
	var host: Node2D = Node2D.new()
	root.add_child(host)
	var fighters: Array[Node2D] = []
	for i: int in 2:
		var h: Node2D = scene.instantiate() as Node2D
		h.position = Vector2(float(i) * 300.0, 0.0)
		host.add_child(h)
		fighters.append(h)
	bm.set("_fighters", fighters)
	var winner: int = 0
	var loser_rig: Object = fighters[1].get("rig") as Object
	var winner_rig: Object = fighters[0].get("rig") as Object
	if loser_rig == null or winner_rig == null:
		_expect(false, "both fighters have a rig")
		host.queue_free()
		bm.free()
		return

	# 1. THE LOSER GOES DOWN — and it is the flop/limp machinery, not a new pose.
	bm.call("_put_the_loser_down", winner)
	_expect(float(loser_rig.get("_limp_target")) >= 0.999,
		"the loser is put into full ragdoll (target %.2f)"
			% float(loser_rig.get("_limp_target")))
	_expect(bool(loser_rig.get("_grounded")),
		"...and is asserted grounded, or it sprawls in mid-air (see the note there)")
	_expect((loser_rig as Node).process_mode == Node.PROCESS_MODE_ALWAYS,
		"...and keeps ticking through the freeze that happens on the next line")
	_expect(float(winner_rig.get("_limp_target")) <= 0.001,
		"the WINNER is untouched — one standing, one down, is the shot")
	var bars_hidden: bool = true
	for c: Node in fighters[1].get_children():
		if c is CharacterBars and (c as CanvasItem).visible:
			bars_hidden = false
	_expect(bars_hidden,
		"...and the corpse is not wearing a full green health bar (Hero._die heals to "
		+ "max outside a run, and CharacterBars polls hp every frame)")

	# 2. THE CORNER COLOURS SURVIVE THE FREEZE. The killing blow's red flash is set
	# AFTER `_decide` returns, so this has to be re-asserted every frame, not once.
	loser_rig.call("set_tint", Color(0.3, 0.64, 1.0))
	winner_rig.call("set_tint", Color(1.0, 0.82, 0.22))
	loser_rig.call("flash_color", Color(1.0, 0.2, 0.2), 0.12)
	winner_rig.call("flash_color", Color(1.0, 0.2, 0.2), 0.12)
	bm.call("_hold_corner_colours")
	_expect(float(loser_rig.get("_flash_timer")) <= 0.0,
		"the loser is not left painted red (timer %.3f)"
			% float(loser_rig.get("_flash_timer")))
	_expect(float(winner_rig.get("_flash_timer")) <= 0.0,
		"...nor the winner (timer %.3f)" % float(winner_rig.get("_flash_timer")))
	_expect(Color(loser_rig.get("limb_color")).is_equal_approx(Color(0.3, 0.64, 1.0))
			and Color(winner_rig.get("limb_color")).is_equal_approx(Color(1.0, 0.82, 0.22)),
		"...and both keep the corner colour `_paint_corners` gave them")

	# 3. ORDERING, which is the one thing no runtime probe can see: the loser must be
	# put down BEFORE the tree is paused, or nothing pausable ever moves again. Source
	# read, CRLF-normalised — this repo's .gd files are CRLF and a `\n\t` needle silently
	# finds nothing here.
	var src: String = FileAccess.get_file_as_string(BOTMATCH_SCRIPT).replace("\r\n", "\n")
	_expect(src != "", "the BotMatch source is readable")
	var down: int = src.find("_put_the_loser_down(winner)")
	var freeze: int = src.find("\t_freeze()\n\t_sting()")
	_expect(down >= 0, "`_decide` puts the loser down")
	_expect(freeze >= 0, "`_decide` still freezes")
	_expect(down >= 0 and freeze >= 0 and down < freeze,
		"...and does it BEFORE the freeze")
	_expect(src.find("func _tick_result") >= 0
			and src.find("_hold_corner_colours()\n\tvar age") >= 0,
		"the corner colours are re-asserted every frame of the result beat, not once")

	host.queue_free()
	bm.free()
	_completes("botmatch_puts_the_loser_down")


# ══════════════════════════════════════════════════════════════════════ plumbing

func _make_rig() -> Node2D:
	var rig: Node2D = (load(RIG_PATH) as GDScript).new() as Node2D
	rig.set("height", 26.0)
	root.add_child(rig)
	rig.call("set_grounded", true)
	rig.call("play", 0)          # State.IDLE, by ordinal — see `tools/death_capture.gd`
	return rig


func _spawn_smudge(rig: Node2D, beat: float = 0.52) -> Node2D:
	var v: Variant = _smudge_script.call("spawn", root, rig, Color(1, 1, 1), Vector2.RIGHT,
		Vector2.ZERO, beat)
	return v as Node2D


func _step(rig: Node2D, frames: int) -> void:
	for _i: int in frames:
		rig.call("advance", 1.0 / 60.0)


## Let queued frees actually happen, so a group count is not polluted by the previous
## test's corpses. `queue_free` is deferred; a same-frame group query still sees them.
func await_free() -> void:
	for _i: int in 2:
		root.propagate_notification(Node.NOTIFICATION_PROCESS)
	# The group is the thing being counted, so verify it emptied rather than assuming.
	for s: Node in get_nodes_in_group("death_smudge"):
		if is_instance_valid(s):
			s.free()


## Name the casualty when a member relocates. The completion sentinels above say
## "something died"; these say which.
func _require_smudge_members() -> void:
	var rig: Node2D = _make_rig()
	rig.call("advance", 1.0 / 60.0)
	var s: Node2D = _spawn_smudge(rig)
	if s == null:
		_expect(false, "_require_smudge_members: a smudge could not be spawned at all")
		rig.queue_free()
		return
	for m: String in SMUDGE_MEMBERS:
		_expect(m in s, "DeathSmudge still has `%s`" % m)
	s.free()
	rig.queue_free()


func _require_rig_members() -> void:
	var rig: Node2D = _make_rig()
	for m: String in RIG_MEMBERS:
		_expect(m in rig, "CharacterRig still has `%s`" % m)
	for m: String in ["collapse", "clear_flash", "snapshot_pose"]:
		_expect(rig.has_method(m), "CharacterRig still has `%s()`" % m)
	rig.free()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: %s" % what)


func _completes(name: String) -> void:
	_completed[name] = true
