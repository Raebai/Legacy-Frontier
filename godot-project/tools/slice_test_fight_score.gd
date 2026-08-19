# FightScore — is this bout worth publishing?
#   godot --headless --path godot-project --script tools/slice_test_fight_score.gd
#
# A quality GATE is only worth having if it actually rejects things, so this suite is
# built around that: every axis gets a bout that should FAIL on it alone, and the
# canonical good fight has to pass. A gate that passes everything is the same as no
# gate, and it fails silently — the pipeline just publishes the demolitions.
extends SceneTree

const TESTS: Array[String] = [
	"a_good_fight_passes",
	"a_demolition_is_rejected",
	"a_short_bout_is_rejected",
	"a_long_bout_is_rejected",
	"a_one_button_fight_is_rejected",
	"lead_changes_are_counted_once_each",
	"the_score_is_bounded",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_a_good_fight_passes()
	_test_a_demolition_is_rejected()
	_test_a_short_bout_is_rejected()
	_test_a_long_bout_is_rejected()
	_test_a_one_button_fight_is_rejected()
	_test_lead_changes_are_counted_once_each()
	_test_the_score_is_bounded()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted part-way)" % t)
	if _fails > 0:
		printerr("FightScore tests: %d FAILED" % _fails)
	else:
		print("FightScore tests: all PASS")
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("  FAIL: %s" % what)


## A bout that swung, went the distance and ended close.
func _good() -> FightScore:
	var f := FightScore.new()
	f.seconds = 17.0
	# Four lead changes, ending with side 0 barely ahead.
	f.record_health(1.0, 0.9)
	f.record_health(0.6, 0.8)
	f.record_health(0.7, 0.4)
	f.record_health(0.2, 0.5)
	f.record_health(0.08, 0.0)
	for id: String in ["bolt", "lance", "wall", "blizzard", "shatter", "nova"]:
		f.record_spell(id, false)
	f.record_spell("glacial_spine", true)
	return f


func _test_a_good_fight_passes() -> void:
	var v: Dictionary = _good().verdict()
	_expect(bool(v["pass"]),
		"the canonical good fight passes (score %.1f, why: %s)" % [v["score"], v["why"]])
	_expect(int(v["lead_changes"]) >= 3, "...and its swings were counted (%d)" % v["lead_changes"])
	_completed["a_good_fight_passes"] = true


## The failure mode the maker named: a fight the winner barely felt.
func _test_a_demolition_is_rejected() -> void:
	var f := FightScore.new()
	f.seconds = 16.0
	f.record_health(1.0, 1.0)
	f.record_health(0.95, 0.4)
	f.record_health(0.92, 0.0)
	for id: String in ["bolt", "lance", "wall", "nova"]:
		f.record_spell(id, false)
	f.record_spell("meteor", true)
	var v: Dictionary = f.verdict()
	_expect(not bool(v["pass"]),
		"a bout won with 92%% health left is rejected (score %.1f)" % v["score"])
	_expect((v["why"] as Array).any(func(r: String) -> bool: return r.contains("demolition")),
		"...and says it was a demolition (why: %s)" % [v["why"]])
	_completed["a_demolition_is_rejected"] = true


## The hard floor: nothing under it publishes, however well it scored elsewhere.
func _test_a_short_bout_is_rejected() -> void:
	var f: FightScore = _good()
	f.seconds = 4.0
	var v: Dictionary = f.verdict()
	_expect(not bool(v["pass"]), "a 4-second bout is rejected whatever else it did")
	_expect((v["why"] as Array).any(func(r: String) -> bool: return r.contains("too short")),
		"...and names the floor")
	_completed["a_short_bout_is_rejected"] = true


## ...and the opposite failure, which a naive "longer is better" score walks into.
func _test_a_long_bout_is_rejected() -> void:
	var f: FightScore = _good()
	f.seconds = 42.0
	var v: Dictionary = f.verdict()
	_expect(not bool(v["pass"]), "a 42-second bout is rejected — it is not short-form")
	_expect((v["why"] as Array).any(func(r: String) -> bool: return r.contains("too long")),
		"...and names the ceiling")
	_completed["a_long_bout_is_rejected"] = true


## A game about spells, advertised with one button.
func _test_a_one_button_fight_is_rejected() -> void:
	var f := FightScore.new()
	f.seconds = 17.0
	f.record_health(1.0, 1.0)
	f.record_health(0.5, 0.6)
	f.record_health(0.1, 0.0)
	f.record_spell("bolt", false)
	var v: Dictionary = f.verdict()
	_expect(not bool(v["pass"]), "a fight with one spell and no ult is rejected")
	_expect((v["why"] as Array).any(func(r: String) -> bool: return r.contains("distinct spells")),
		"...and says the kit never showed up")
	_completed["a_one_button_fight_is_rejected"] = true


## The axis most likely to be miscounted: a lead that wobbles inside the deadband, or
## a run of samples on the same side, must not inflate the drama.
func _test_lead_changes_are_counted_once_each() -> void:
	var f := FightScore.new()
	f.record_health(1.0, 0.5)      # 0 ahead
	f.record_health(0.9, 0.4)      # still 0 — no change
	f.record_health(0.8, 0.3)      # still 0
	_expect(f.lead_changes == 0, "a steady lead is not a swing (got %d)" % f.lead_changes)
	f.record_health(0.3, 0.8)      # 1 ahead — one change
	_expect(f.lead_changes == 1, "one real swing counts once (got %d)" % f.lead_changes)
	# Inside the deadband: level, not a change, and it must not reset the run either.
	f.record_health(0.5, 0.5)
	_expect(f.lead_changes == 1, "a dead-level sample is not a swing (got %d)" % f.lead_changes)
	f.record_health(0.9, 0.2)      # back to 0 — second change
	_expect(f.lead_changes == 2, "the swing back counts (got %d)" % f.lead_changes)
	_completed["lead_changes_are_counted_once_each"] = true


## It is a percentage and callers will treat it as one.
func _test_the_score_is_bounded() -> void:
	var empty := FightScore.new()
	_expect(empty.score() >= 0.0, "an empty tally scores at or above 0")
	var maxed := FightScore.new()
	maxed.seconds = FightScore.IDEAL_SECONDS
	maxed.record_health(1.0, 0.0)
	for i: int in 40:
		maxed.record_health(0.0 if i % 2 == 0 else 1.0, 1.0 if i % 2 == 0 else 0.0)
		maxed.record_spell("spell_%d" % i, true)
	maxed.record_health(0.01, 0.0)
	_expect(maxed.score() <= 100.0, "a maximal tally cannot exceed 100 (got %.1f)" % maxed.score())
	_expect(maxed.score() > FightScore.PASS_MARK, "...and it passes")
	_completed["the_score_is_bounded"] = true
