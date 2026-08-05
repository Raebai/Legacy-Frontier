# THE ANTI-OSCILLATION SUITE. Maker, watching a duel: *"the movement is weird like
# sometimes the guy is just going back and forward"*.
#
# ⚠ NOTHING IN THE REPO ASSERTED THIS BEFORE. Every bot suite checks WHAT a brain asks
# for — which slot, which dodge, which exit — and none of them check how often the
# answer CHANGES. A bot that alternates left/right at 30 Hz passes every one of them
# while being unwatchable, which is exactly the gap the maker's eye found.
#
# Two bots are driven against each other with no bodies (the steering layer integrates
# straight into position — the same loop `tools/bot_cast_probe.gd` uses) and the
# horizontal direction REVERSALS are counted.
#
#   godot --headless --path godot-project --script tools/slice_test_bot_steer.gd
extends SceneTree

const DT: float = 1.0 / 60.0
const DURATION: float = 12.0
const WALK_SPEED: float = 240.0
const CLASSES: int = 9

## Reversals per second above which the walk reads as a stutter rather than a stance.
##
## Calibrated against the mechanism, not against taste: `STEER_MIN_DWELL` is 0.24 s, so
## a latch that is working can produce at most ~4.2 reversals/s even if every single
## dwell expires into an opposite answer. Anything at or under that is the latch doing
## its job; meaningfully above it means something is bypassing the latch. Measured
## BEFORE the fix the worst pairing ran far past this — see the header note in
## `BotBrain._steer`.
const MAX_REVERSALS_PER_SEC: float = 4.2
## ...and the whole-roster average should sit well under the per-pairing ceiling, or a
## roster that is merely "not the worst case everywhere" would pass.
const MAX_MEAN_REVERSALS_PER_SEC: float = 2.0

var _failures: Array[String] = []


class Fighter extends RefCounted:
	var cid: int = 0
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var mem: BotBrain.Memory = BotBrain.Memory.new()
	var cds: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	## Last NONZERO direction, and how many times it has flipped sign.
	var last_dir: float = 0.0
	var reversals: int = 0


func _init() -> void:
	_test_no_stutter_in_any_pairing()
	_test_no_stutter_with_a_live_threat_on_the_board()
	_test_the_latch_actually_holds()
	_test_a_latchless_brain_still_answers()
	if _failures.is_empty():
		print("Bot steer tests: all PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("FAIL: %s" % f)
		print("Bot steer tests: %d FAILED" % _failures.size())
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


# ─────────────────────────────────────────────────────────────────────── the tests

## Every pairing in the roster, each judged on its own worst side.
func _test_no_stutter_in_any_pairing() -> void:
	var total: float = 0.0
	var pairs: int = 0
	var worst: float = 0.0
	var worst_name: String = ""
	for a: int in CLASSES:
		for b: int in CLASSES:
			if a == b:
				continue
			var res: Array = _duel(a, b, a * 31 + b)
			var ra: float = float(res[0]) / DURATION
			var rb: float = float(res[1]) / DURATION
			var hi: float = maxf(ra, rb)
			if hi > worst:
				worst = hi
				worst_name = "%d vs %d" % [a, b]
			total += ra + rb
			pairs += 2
	var mean: float = total / maxf(float(pairs), 1.0)
	print("  steer reversals/s: mean %.2f, worst %.2f (%s)" % [mean, worst, worst_name])
	_expect(worst <= MAX_REVERSALS_PER_SEC,
		"worst pairing %s stutters at %.2f reversals/s (ceiling %.2f)"
		% [worst_name, worst, MAX_REVERSALS_PER_SEC])
	_expect(mean <= MAX_MEAN_REVERSALS_PER_SEC,
		"roster mean %.2f reversals/s (ceiling %.2f)" % [mean, MAX_MEAN_REVERSALS_PER_SEC])


## ⚠ THE PAIRING TEST ABOVE RUNS ON A CLEAN BOARD, AND THAT IS THE HALF IT CANNOT SEE.
##
## With `threats` empty, `BotBrain._safest` short-circuits to `candidates[0]` and the
## steering direction survives untouched — so the clean-board numbers were IDENTICAL
## with the dwell latch disabled and with it on (measured: mean 0.04 either way). That
## is precisely the maker's *"SOMETIMES the guy is just going back and forward"*: the
## reversal source only exists once the fight has something in the air, because two
## equal-length probe steps get re-ranked against a MOVING footprint every frame.
##
## So this one puts a live danger region on the board and sweeps it across the fight.
func _test_no_stutter_with_a_live_threat_on_the_board() -> void:
	var worst: float = 0.0
	var worst_name: String = ""
	var total: float = 0.0
	var runs: int = 0
	for a: int in CLASSES:
		var b: int = (a + 4) % CLASSES
		var res: Array = _duel(a, b, a * 977 + 13, true)
		for i: int in 2:
			var r: float = float(res[i]) / DURATION
			total += r
			runs += 1
			if r > worst:
				worst = r
				worst_name = "%d vs %d (side %d)" % [a, b, i]
	var mean: float = total / maxf(float(runs), 1.0)
	print("  with a live threat: mean %.2f, worst %.2f (%s)" % [mean, worst, worst_name])
	_expect(worst <= MAX_REVERSALS_PER_SEC,
		"with a threat on the board %s stutters at %.2f reversals/s (ceiling %.2f)"
		% [worst_name, worst, MAX_REVERSALS_PER_SEC])


## THE MECHANISM, asserted directly rather than inferred from the aggregate above.
## A brain handed a foe that teleports across the band every frame must still refuse
## to reverse faster than the dwell allows — this is the assertion that fails loudly if
## someone removes the latch while the roster averages happen to stay quiet.
func _test_the_latch_actually_holds() -> void:
	var m: BotBrain.Memory = BotBrain.Memory.new()
	m.rng.seed = 4242
	var profile: Dictionary = BotProfile.of(2)
	var last: float = 0.0
	var reversals: int = 0
	var t: float = 0.0
	var step: int = 0
	while t < 6.0:
		# Alternate the foe between far outside and far inside the band every frame:
		# the most hostile input a spacing rule can be handed.
		var gap: float = 900.0 if step % 2 == 0 else 20.0
		var bb: Dictionary = _bb(0, Vector2.ZERO, Vector2(gap, 0.0), t, m)
		var mv: Vector2 = BotBrain.decide(bb, profile, m).get("move", Vector2.ZERO)
		if absf(mv.x) > 0.01:
			if last != 0.0 and signf(mv.x) != last:
				reversals += 1
			last = signf(mv.x)
		t += DT
		step += 1
	var per_sec: float = float(reversals) / 6.0
	print("  worst-case alternating foe: %.2f reversals/s" % per_sec)
	_expect(per_sec <= MAX_REVERSALS_PER_SEC,
		"a foe alternating across the band every frame drove %.2f reversals/s — the "
		% per_sec + "dwell latch is not holding (ceiling %.2f)" % MAX_REVERSALS_PER_SEC)


## ⚠ THE BY-ABSENCE ARM. A latch that answers "hold" forever would ace both tests
## above while making every bot stand still, which is a worse bug than the stutter.
## So: a bot that starts a long way outside its band must actually CLOSE.
func _test_a_latchless_brain_still_answers() -> void:
	var m: BotBrain.Memory = BotBrain.Memory.new()
	m.rng.seed = 99
	var profile: Dictionary = BotProfile.of(2)
	var pos: Vector2 = Vector2(-900.0, 0.0)
	var foe: Vector2 = Vector2(900.0, 0.0)
	var t: float = 0.0
	var moved_frames: int = 0
	while t < 3.0:
		var bb: Dictionary = _bb(0, pos, foe, t, m)
		var mv: Vector2 = BotBrain.decide(bb, profile, m).get("move", Vector2.ZERO)
		if absf(mv.x) > 0.01:
			moved_frames += 1
		pos.x += mv.x * WALK_SPEED * DT
		t += DT
	_expect(moved_frames > 60,
		"a bot 1800 px from its foe only moved on %d frames — the latch is jamming it "
		% moved_frames + "still, which is worse than the stutter it replaced")
	_expect(pos.x > -900.0 + 100.0,
		"a bot 1800 px from its foe closed only %.0f px in 3 s" % (pos.x + 900.0))


# ───────────────────────────────────────────────────────────────────────── helpers

func _bb(cid: int, me: Vector2, foe: Vector2, now: float, mem: BotBrain.Memory) -> Dictionary:
	return {
		"self_pos": me, "self_vel": Vector2.ZERO,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0,
		"on_floor": true, "facing": signf(foe.x - me.x),
		"foe_pos": foe, "foe_vel": Vector2.ZERO,
		"foe_hp_frac": 1.0, "foe_facing": signf(me.x - foe.x),
		"foe_id": 1, "threats": [], "cooldowns": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"slot_affordable": [true, true, true],
		"reach": 58.0, "now": now, "class_id": cid, "mem": mem,
	}


## A danger region that SWEEPS across the fight, so the two probe steps are re-ranked
## against a moving footprint — the input that made the old tie-break flip.
func _threats_at(now: float) -> Array:
	var x: float = sin(now * 1.7) * 260.0
	return [{
		"id": 991, "kind": "circle", "shape": "circle",
		"pos": Vector2(x, 0.0), "center": Vector2(x, 0.0),
		"vel": Vector2.ZERO, "radius": 150.0, "tti": 0.5, "parryable": false,
		"region": {"shape": "circle", "center": Vector2(x, 0.0), "radius": 150.0},
	}]


## One headless duel; returns [a_reversals, b_reversals].
func _duel(a_id: int, b_id: int, seed_value: int, threats: bool = false) -> Array:
	var a: Fighter = Fighter.new()
	var b: Fighter = Fighter.new()
	a.cid = a_id
	b.cid = b_id
	a.pos = Vector2(-260.0, 0.0)
	b.pos = Vector2(260.0, 0.0)
	a.mem.rng.seed = seed_value
	b.mem.rng.seed = seed_value + 7777
	var profile: Dictionary = BotProfile.of(2)
	var t: float = 0.0
	while t < DURATION:
		_step(a, b, profile, t, threats)
		_step(b, a, profile, t, threats)
		t += DT
	return [a.reversals, b.reversals]


func _step(me: Fighter, foe: Fighter, profile: Dictionary, now: float,
		threats: bool = false) -> void:
	for i: int in me.cds.size():
		me.cds[i] = maxf(me.cds[i] - DT, 0.0)
	var bb: Dictionary = _bb(me.cid, me.pos, foe.pos, now, me.mem)
	bb["cooldowns"] = me.cds
	bb["self_vel"] = me.vel
	if threats:
		bb["threats"] = _threats_at(now)
	var mv: Vector2 = BotBrain.decide(bb, profile, me.mem).get("move", Vector2.ZERO)
	if absf(mv.x) > 0.01:
		var d: float = signf(mv.x)
		if me.last_dir != 0.0 and d != me.last_dir:
			me.reversals += 1
		me.last_dir = d
	me.vel = Vector2(mv.x * WALK_SPEED, 0.0)
	me.pos += me.vel * DT
