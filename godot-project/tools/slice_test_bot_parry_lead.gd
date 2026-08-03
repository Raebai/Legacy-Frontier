# THE GUARD LEAD — does a guard pressed the way the BRAIN presses it actually block?
#
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/slice_test_bot_parry_lead.gd
#
# WHY THIS SUITE EXISTS. `BotBrain` decides WHEN to press the guard from a lead time,
# and for a long while it derived that lead from `guard_style` — a field the body and
# the brain documented with OPPOSITE meanings ("0 = a press window" on `Hero`,
# "0 BLADE / 1 SIGIL" in `BotBrain`). So seven of the nine classes, which run a press
# window that opens IMMEDIATELY and lasts 0.16 s, were told to press 0.374 s early.
# The window lapsed 0.21 s before the blow landed and those classes could not convert
# a reflex parry at ANY difficulty tier. Measured across 18 duels: 50 parries
# committed, ~3 landed, and 56 of 57 hits taken within 3 s of a guard press arrived
# with the window already shut.
#
# ⚠ AND THE SUITE THAT LET IT SHIP. `slice6_test_bot_brain._test_guard_lockout` feeds
# the brain `guard_style: 0` with `tti = GUARD_BAND_BLADE` and asserts it guards — it
# ratifies the brain's OWN model and never touches a body. Green test, dead feature.
# So this suite asserts against REAL Hero scenes through the REAL `take_damage` path,
# and every number it uses is the one the brain will actually use, read back off
# `bot_body_state()` rather than restated here.
#
# THE TWO HALVES MATTER EQUALLY:
#   step 2  press, wait `guard_lead`, take a hit  -> it MUST be blocked.
#   step 3  press, wait past the tolerance, hit   -> it MUST land.
# Without step 3 the suite is satisfied by a guard that is simply always on, which is
# the degenerate "fix" this whole area invites. An invariant that is trivially true of
# an always-guarding body is not an invariant.
#
# TEST IDIOM — see the long note in tools/slice_test_loadout.gd. Failures accumulate
# on the MEMBER `_fails`; every test records a COMPLETION SENTINEL, so a test that
# aborts part-way fails BY ABSENCE rather than reading as zero failures.
extends SceneTree

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const FAR: Vector2 = Vector2(-40000.0, -40000.0)
const TICK: float = 1.0 / 60.0
## Comfortably past the tolerance, so "the window has shut" is not a rounding call.
const LATE_MARGIN: float = 0.08
const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

const TESTS: Array[String] = [
	"body_publishes_guard_timing",
	"a_guard_pressed_at_the_lead_blocks",
	"a_guard_pressed_too_early_has_lapsed",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_body_publishes_guard_timing()
	_test_a_guard_pressed_at_the_lead_blocks()
	_test_a_guard_pressed_too_early_has_lapsed()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Bot parry-lead tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Bot parry-lead tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(name: String) -> void:
	_completed[name] = true


## A real Hero of `cid`, parked far from every other test's patch of world and driven
## one physics tick at a time.
func _hero(cid: int, index: int) -> CharacterBody2D:
	var h: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(h)
	h.set_physics_process(false)
	h.global_position = FAR + Vector2(float(index) * 8000.0, 0.0)
	# `configure_class` is the real entry point — it sets `_cfg`, and `_cfg` is what
	# decides `_parry_window_len` (0.16 s, or 0.40 s for the Juggernaut's "block") and
	# whether `_guard` exists at all. Poking `_hero_class` alone leaves every body on
	# the default config, which is exactly how this suite first reported all nine
	# classes with an identical 0.080 s lead and 90 hp.
	h.call(&"configure_class", cid)
	return h


## A brain that guards for exactly one frame and then does nothing.
##
## ⚠ IT HAS TO BE A BRAIN, NOT A `ctrl.drive()` CALL. `Hero._physics_process` ticks
## its controller BEFORE anything reads input, and `BotController.tick` re-drives the
## intent every frame — with no brain attached that is `sanitized(null)`, an EMPTY
## intent. So a guard latched from outside is wiped before the body ever sees it, and
## the suite silently measured a press that was never made.
## ⚠ AND IT HOLDS, because the two guard shapes need opposite fixtures and the brain
## holds for BOTH. A press window is edge-triggered, so holding neither extends it nor
## re-opens it (PARRY_COOLDOWN is 0.9 s). The Swordsaint's BLADE ring is the opposite:
## it SHRINKS while held and `_process_blade_guard` cancels it on release, so a
## one-frame tap gave that class no guard at all — which is exactly how this suite
## first reported eight passes and one failure.
class HeldGuard extends RefCounted:
	var holding: bool = false

	func decide(_bb: Dictionary, _profile: Dictionary) -> Dictionary:
		return {BotIntent.GUARD: true} if holding else {}


## Press the guard through the CONTROLLER SEAM, exactly as a bot does — never by
## poking the private timer, or the suite would be testing its own shortcut.
func _press_guard(h: CharacterBody2D, ctrl: BotController) -> void:
	(ctrl.brain as HeldGuard).holding = true
	h.call(&"_physics_process", TICK)


func _advance(h: CharacterBody2D, seconds: float) -> void:
	var n: int = int(round(seconds / TICK))
	for _i: int in n:
		h.call(&"_physics_process", TICK)


# ───────────────────────────────────────────────────────── the timing is published
func _test_body_publishes_guard_timing() -> void:
	for cid: int in range(CLASS_NAMES.size()):
		var h: CharacterBody2D = _hero(cid, cid)
		var st: Dictionary = h.call(&"bot_body_state")
		_expect(st.has("guard_lead"),
			"%s publishes `guard_lead` (the brain must not infer it from a style enum)"
				% CLASS_NAMES[cid])
		_expect(st.has("guard_tolerance"), "%s publishes `guard_tolerance`" % CLASS_NAMES[cid])
		_expect(float(st.get("guard_lead", -1.0)) > 0.0,
			"%s: guard_lead is a positive number of seconds" % CLASS_NAMES[cid])
		_expect(float(st.get("guard_tolerance", -1.0)) > 0.0,
			"%s: guard_tolerance is a positive number of seconds" % CLASS_NAMES[cid])
		h.free()
	_completes("body_publishes_guard_timing")


# ───────────────────────────────────────────── pressed at the lead -> it must block
func _test_a_guard_pressed_at_the_lead_blocks() -> void:
	for cid: int in range(CLASS_NAMES.size()):
		var h: CharacterBody2D = _hero(cid, cid)
		var ctrl: BotController = BotController.new()
		ctrl.brain = HeldGuard.new()
		h.set(&"controller", ctrl)
		var lead: float = float((h.call(&"bot_body_state") as Dictionary).get("guard_lead", 0.0))
		SpellDeflect.reset_counts()
		var hp_before: int = int(h.get(&"hp"))
		_press_guard(h, ctrl)
		_advance(h, lead)
		h.call(&"take_damage", 10)
		_expect(int(h.get(&"hp")) == hp_before,
			"%s: a guard pressed %.3fs early BLOCKS the hit (hp %d -> %d)"
				% [CLASS_NAMES[cid], lead, hp_before, int(h.get(&"hp"))])
		_expect(SpellDeflect.deflect_count > 0,
			"%s: ...and the block is COUNTED, so a sweep can measure it" % CLASS_NAMES[cid])
		h.set(&"controller", null)
		h.free()
	_completes("a_guard_pressed_at_the_lead_blocks")


# ────────────────────────────── pressed far too early -> the window must have shut
## THE OTHER HALF. Step 2 alone is satisfied by a guard that never closes, which is
## exactly the shape of "fix" that would make bots unbeatable and this suite green.
func _test_a_guard_pressed_too_early_has_lapsed() -> void:
	for cid: int in range(CLASS_NAMES.size()):
		var h: CharacterBody2D = _hero(cid, cid)
		var ctrl: BotController = BotController.new()
		ctrl.brain = HeldGuard.new()
		h.set(&"controller", ctrl)
		var st: Dictionary = h.call(&"bot_body_state")
		var late: float = float(st.get("guard_lead", 0.0)) \
			+ float(st.get("guard_tolerance", 0.0)) + LATE_MARGIN
		var hp_before: int = int(h.get(&"hp"))
		_press_guard(h, ctrl)
		_advance(h, late)
		h.call(&"take_damage", 10)
		_expect(int(h.get(&"hp")) < hp_before,
			"%s: a guard pressed %.3fs early has LAPSED and the hit lands (hp stayed %d)"
				% [CLASS_NAMES[cid], late, hp_before])
		h.set(&"controller", null)
		h.free()
	_completes("a_guard_pressed_too_early_has_lapsed")
