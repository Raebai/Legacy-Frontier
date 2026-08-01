# Run: godot --headless --path godot-project --script tools/slice_test_wavechar.gd
#
# WAVE CHARACTER — "a wave should be a sentence, not a soup."
#
# `Encounter._roll_archetype` picks UNIFORMLY from `WaveDef.archetypes`, so a roster
# of [brute, charger, mage, summoner] delivers roughly one of each and four waves
# built that way are four helpings of the same soup. `FloorGen.give_character` leans
# a wave on ONE of the classes it already carries by repeating that class's entries —
# duplicates in the roster array ARE weights, so this costs no new field, no new
# system and nothing in Encounter.
#
# The two things that could go wrong, and are asserted here:
#
#   * IT COULD SMUGGLE A NEW THREAT IN. `slice_test_floorgen` already fails if a
#     redrawn wave gains a class it was not authored to carry; this suite checks the
#     character pass in isolation, because a bug there would show up in that suite
#     only on the seeds where the pass happened to fire.
#   * IT COULD DO NOTHING. A "character" that leaves the roster at one-of-each is the
#     soup with a nicer name. So the assertions are OCCURRENCE assertions: waves
#     actually come back lopsided, over the real authored tower, at a measured rate.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──────────
# Failures accumulate on the MEMBER `_fails` and each test records a COMPLETION
# SENTINEL, so a test aborted half-way fails the suite BY ABSENCE.
extends SceneTree

const GS_PATH: String = "res://scripts/GameState.gd"

const TESTS: Array[String] = [
	"character_never_invents_a_threat",
	"character_actually_leans",
	"a_one_note_wave_is_left_alone",
	"the_roster_is_bounded_and_never_empties",
	"the_pass_is_pure",
	"the_real_tower_gains_identity",
	"the_floor_still_spawns_the_same_fight",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _tower: Resource = null


func _initialize() -> void:
	# ⚠ NOT the bare `GameState` identifier: an autoload name is not a global under
	# `--script`, and naming one is a COMPILE error that takes the whole suite down.
	_tower = (load(GS_PATH) as GDScript).build_default_tower()
	_test_character_never_invents_a_threat()
	_test_character_actually_leans()
	_test_a_one_note_wave_is_left_alone()
	_test_the_roster_is_bounded_and_never_empties()
	_test_the_pass_is_pure()
	_test_the_real_tower_gains_identity()
	_test_the_floor_still_spawns_the_same_fight()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Wave-character tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Wave-character tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func mini_f(a: float, b: float) -> float:
	return a if a < b else b


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _classes(roster: Array) -> Dictionary:
	var out: Dictionary = {}
	for a in roster:
		out[FloorGen.threat_class(int(a))[0]] = true
	return out


## The share of the roster held by its most-represented class.
func _dominance(roster: Array) -> float:
	if roster.is_empty():
		return 0.0
	var counts: Dictionary = {}
	for a in roster:
		var k: int = FloorGen.threat_class(int(a))[0]
		counts[k] = int(counts.get(k, 0)) + 1
	var best: int = 0
	for k2 in counts:
		best = maxi(best, int(counts[k2]))
	return float(best) / float(roster.size())


const SAMPLES: Array = [
	[0, 1, 3],                # chaser + brute + charger   (floor 1, wave 3)
	[1, 3, 7, 4],             # brute + charger + mage + summoner (floor 3, wave 4)
	[5, 5, 7],                # assassin x2 + mage         (floor 3, wave 3)
	[0, 1, 3, 5, 6, 7],       # the floor-5 finale
	[2, 1],                   # caster + brute
]


func _test_character_never_invents_a_threat() -> void:
	var bad: int = 0
	var walked: int = 0
	for src: Array in SAMPLES:
		var typed: Array[int] = []
		for a in src:
			typed.append(int(a))
		var allowed: Dictionary = _classes(typed)
		for s: int in range(0, 300):
			var got: Array[int] = FloorGen.give_character(_rng(s * 7919 + 3), typed)
			walked += 1
			for g: int in got:
				if not allowed.has(FloorGen.threat_class(g)[0]):
					bad += 1
	_expect(walked > 0, "the character pass was actually walked (%d rolls)" % walked)
	_expect(bad == 0,
		"a wave never gains a threat class it was not authored to carry (%d violations)" % bad)
	_completes("character_never_invents_a_threat")


## THE OCCURRENCE ASSERTION. A pass that leaves the roster even is the soup with a
## nicer name.
func _test_character_actually_leans() -> void:
	for src: Array in SAMPLES:
		var typed: Array[int] = []
		for a in src:
			typed.append(int(a))
		if _classes(typed).size() < 2:
			continue
		var start: float = _dominance(typed)
		var leaned: int = 0
		var trials: int = 200
		var leads: Dictionary = {}
		for s: int in trials:
			var got: Array[int] = FloorGen.give_character(_rng(s * 31 + 7), typed)
			# ⚠ THE TEST IS "IT LEANS MORE THAN IT STARTED", NOT "IT REACHES
			# CHARACTER_DOMINANCE". A six-entry roster across four classes cannot reach
			# 0.65 inside CHARACTER_MAX_ROSTER, and that is the bound doing its job
			# rather than a failure: the floor-5 finale's identity IS "everything the
			# tower has", and leaning it from 33% to ~56% is the right size of nudge.
			if _dominance(got) >= mini_f(FloorGen.CHARACTER_DOMINANCE - 0.01, start + 0.08):
				leaned += 1
			# ...and which class it leans on has to vary, or every wave of every
			# climb ends up being about the same thing.
			var counts: Dictionary = {}
			for g: int in got:
				var k: int = FloorGen.threat_class(g)[0]
				counts[k] = int(counts.get(k, 0)) + 1
			var best_k: int = -1
			for k2 in counts:
				if best_k < 0 or int(counts[k2]) > int(counts[best_k]):
					best_k = int(k2)
			leads[best_k] = true
		_expect(float(leaned) / float(trials) > 0.85,
			"%s comes back lopsided (%d/%d)" % [str(src), leaned, trials])
		_expect(leads.size() >= 2,
			"%s does not always lean the same way (%d distinct leads)" % [str(src), leads.size()])
	_completes("character_actually_leans")


func _test_a_one_note_wave_is_left_alone() -> void:
	# Floor 1 wave 1 is [CHASER] — pure pressure, nothing to read. It is already the
	# most characterful thing a wave can be, and the pass must not pad it.
	for src: Array in [[0], [5, 5], [0, 5], [1, 3]]:
		var typed: Array[int] = []
		for a in src:
			typed.append(int(a))
		if _classes(typed).size() > 1:
			continue
		for s: int in 60:
			var got: Array[int] = FloorGen.give_character(_rng(s * 13 + 1), typed)
			_expect(str(got) == str(typed),
				"a single-class wave %s is returned untouched (got %s)" % [str(typed), str(got)])
	_completes("a_one_note_wave_is_left_alone")


func _test_the_roster_is_bounded_and_never_empties() -> void:
	for src: Array in SAMPLES:
		var typed: Array[int] = []
		for a in src:
			typed.append(int(a))
		for s: int in 300:
			var got: Array[int] = FloorGen.give_character(_rng(s * 97 + 11), typed)
			_expect(not got.is_empty(), "the roster never empties")
			_expect(got.size() >= typed.size(),
				"the pass only ADDS copies — every authored pressure survives")
			_expect(got.size() <= FloorGen.CHARACTER_MAX_ROSTER,
				"the roster stays readable (%d > %d)" % [got.size(), FloorGen.CHARACTER_MAX_ROSTER])
	_completes("the_roster_is_bounded_and_never_empties")


func _test_the_pass_is_pure() -> void:
	for src: Array in SAMPLES:
		var typed: Array[int] = []
		for a in src:
			typed.append(int(a))
		for s: int in 120:
			var a1: Array[int] = FloorGen.give_character(_rng(s * 5 + 2), typed)
			var a2: Array[int] = FloorGen.give_character(_rng(s * 5 + 2), typed)
			_expect(str(a1) == str(a2),
				"same seed -> same wave, on every machine (%s vs %s)" % [str(a1), str(a2)])
	_completes("the_pass_is_pure")


## End-to-end over the REAL authored tower: climbs come back with waves that are
## ABOUT something, and the difficulty band still holds.
func _test_the_real_tower_gains_identity() -> void:
	var total: int = 0
	var lopsided: int = 0
	var out_of_band: int = 0
	for s: int in range(0, 80):
		var t: Resource = FloorGen.vary_tower(_tower, s * 61 + 17)
		for i: int in (t.floors as Array).size():
			var src: Array = _tower.floors[i].waves
			var got: Array = t.floors[i].waves
			for k: int in mini(src.size(), got.size()):
				var authored: Array = src[k].archetypes as Array
				var rolled: Array = got[k].archetypes as Array
				if authored.is_empty():
					continue
				total += 1
				var allowed: Dictionary = {}
				for a in authored:
					for m: int in FloorGen.threat_class(int(a)):
						allowed[m] = true
				for r in rolled:
					if not allowed.has(int(r)):
						out_of_band += 1
				# Multi-class waves that came back leaning hard on one class.
				if _classes(authored).size() >= 2 and _dominance(rolled) >= 0.6:
					lopsided += 1
	_expect(total > 0, "the authored tower's waves were actually walked (%d)" % total)
	_expect(out_of_band == 0,
		"no wave in a real climb gains a threat it was not authored to carry (%d)" % out_of_band)
	var rate: float = float(lopsided) / float(maxi(total, 1))
	_expect(rate > 0.2,
		"climbs really do produce waves with a character (%.0f%% of waves lean)" % (rate * 100.0))
	_expect(rate < 0.8,
		"...but not EVERY wave, or lopsided becomes the new uniform (%.0f%%)" % (rate * 100.0))
	print("[wavechar] %d waves walked, %.1f%% came back leaning" % [total, rate * 100.0])
	_completes("the_real_tower_gains_identity")


## THE REGRESSION. FloorGen's core promise is that two rolls of floor 3 are the same
## AMOUNT of fight. The character pass touches the roster only; if it ever touched a
## budget, a cap or an hp multiplier, this is where it would show.
func _test_the_floor_still_spawns_the_same_fight() -> void:
	for s: int in range(0, 60):
		var t: Resource = FloorGen.vary_tower(_tower, s * 43 + 9)
		for i: int in (t.floors as Array).size():
			var want: int = 0
			for w in (_tower.floors[i].waves as Array):
				want += maxi(int(w.enemy_budget), 0)
			var have: int = 0
			for w2 in (t.floors[i].waves as Array):
				have += maxi(int(w2.enemy_budget), 0)
				_expect(float(w2.hp_multiplier) < 0.0,
					"a redrawn wave never carries an hp multiplier (floor %d)" % i)
			_expect(have == want,
				"floor %d still spawns exactly %d bodies (got %d)" % [i, want, have])
			_expect((t.floors[i].waves as Array).size() == (_tower.floors[i].waves as Array).size(),
				"floor %d still has the same number of waves" % i)
	_completes("the_floor_still_spawns_the_same_fight")
