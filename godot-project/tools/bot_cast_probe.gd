# DIAGNOSTIC (not a suite — `run_all_tests.py` only collects `*test_*`).
#
# THE QUESTION THE EXISTING HARNESS CANNOT ASK. `bot_sim.gd` rotates through a
# hero's signatures ON A TIMER and reports which asks did not come out of the BODY —
# so it measures emission, and is blind to a slot the BRAIN never asks for at all.
# `_score_slots` skips any slot whose `_range_fit` is 0.0 (it `continue`s, it does not
# score it low), so an unreachable slot leaves no trace anywhere.
#
# So: drive two BotBrains against each other in a closed loop with NO bodies — the
# steering layer moves them, the utility layer picks slots, cooldowns tick — and
# histogram what each brain actually asked for. Pure math, deterministic, ~1 s.
#
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/bot_cast_probe.gd
extends SceneTree

const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]
const DT: float = 1.0 / 60.0
const DURATION: float = 30.0
const WALK_SPEED: float = 240.0
## A slot goes on this long a cooldown after a cast, so the scorer has to reach for
## something else in between rather than leaning on one slot forever.
const FAKE_COOLDOWN: float = 4.0
## ⚠ WAS A HARDCODED 3, AND THE HAND IS 4. Every kit's slot 3 is its ULT, so this
## probe never offered the ult to the brain (it builds `slot_affordable` and the
## cooldown array over this range), never counted an ult cast, and computed its
## headline "0 of 27 kit slots NEVER asked for" over 9 classes x 3 -- silently
## excluding every ultimate in the game from a report whose entire job is finding
## slots nobody reaches for.
##
## Found while answering the maker's *"I havent seen many ults in these stick
## battles"*: the instrument said 3/3 slots used for all nine classes, which reads
## as a clean bill of health and was a blind spot.
##
## DERIVED now, never a literal, so shrinking or growing the hand cannot leave this
## measuring a different game than the one that ships.
const SLOTS: int = BotIntent.SLOT_COUNT


class Fighter extends RefCounted:
	var cid: int = 0
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var mem: BotBrain.Memory = BotBrain.Memory.new()
	var cds: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var casts: Dictionary = {}
	var fires: int = 0
	var swings: int = 0
	var guards: int = 0
	var dashes: int = 0


func _init() -> void:
	var totals: Dictionary = {}
	for cid: int in range(CLASS_NAMES.size()):
		totals[cid] = {}
	# Round-robin every pairing, so a class is never judged on one matchup.
	for a: int in range(CLASS_NAMES.size()):
		for b: int in range(CLASS_NAMES.size()):
			if a == b:
				continue
			var res: Array = _duel(a, b, a * 31 + b)
			_merge(totals[a], res[0])
			_merge(totals[b], res[1])

	print("=".repeat(92))
	print("BOT CAST PROBE — what the BRAIN asks for, over %d pairings of %.0fs"
		% [CLASS_NAMES.size() * (CLASS_NAMES.size() - 1), DURATION])
	print("=".repeat(92))
	var silent_classes: int = 0
	var silent_slots: int = 0
	for cid: int in range(CLASS_NAMES.size()):
		var facts: Array = BotBrain._kit_facts(cid)
		var t: Dictionary = totals[cid]
		var used: int = 0
		var line: String = ""
		for i: int in range(SLOTS):
			var n: int = int(t.get(i, 0))
			if n > 0:
				used += 1
			else:
				silent_slots += 1
			var id: String = String(facts[i]["id"]) if i < facts.size() else "?"
			line += "  slot%d %-18s %5d" % [i, id, n]
		if used == 0:
			silent_classes += 1
		print("%-12s casts:%s   [%d/%d slots used]" % [CLASS_NAMES[cid], line, used, SLOTS])
	print("\n" + "=".repeat(92))
	print("TOTAL: %d of %d kit slots NEVER asked for; %d classes cast nothing at all"
		% [silent_slots, CLASS_NAMES.size() * SLOTS, silent_classes])
	quit(0)


func _merge(into: Dictionary, from: Dictionary) -> void:
	for k: Variant in from.keys():
		into[k] = int(into.get(k, 0)) + int(from[k])


## One headless duel. No bodies: the steering layer's move vector integrates
## straight into position, which is exactly the loop the band lives in.
func _duel(a_id: int, b_id: int, seed_value: int) -> Array:
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
		_step(a, b, profile, t)
		_step(b, a, profile, t)
		t += DT
	return [a.casts, b.casts]


func _step(me: Fighter, foe: Fighter, profile: Dictionary, now: float) -> void:
	for i: int in range(me.cds.size()):
		me.cds[i] = maxf(me.cds[i] - DT, 0.0)
	var affordable: Array[bool] = []
	for i: int in range(SLOTS):
		affordable.append(me.cds[i] <= 0.0)
	var bb: Dictionary = {
		"self_pos": me.pos, "self_vel": me.vel,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0,
		"on_floor": true, "facing": signf(foe.pos.x - me.pos.x),
		"foe_pos": foe.pos, "foe_vel": foe.vel,
		"foe_hp_frac": 1.0, "foe_facing": signf(me.pos.x - foe.pos.x),
		"foe_id": 1,
		"threats": [], "cooldowns": me.cds,
		"slot_affordable": affordable,
		"reach": 58.0, "now": now,
		"class_id": me.cid,
		"mem": me.mem,
	}
	var intent: Dictionary = BotBrain.decide(bb, profile, me.mem)
	if intent.has("cast_slot"):
		var s: int = int(intent["cast_slot"])
		me.casts[s] = int(me.casts.get(s, 0)) + 1
		me.cds[s] = FAKE_COOLDOWN
	if bool(intent.get("fire", false)):
		me.fires += 1
	if bool(intent.get("swing", false)):
		me.swings += 1
	if bool(intent.get("guard", false)):
		me.guards += 1
	if bool(intent.get("dash", false)):
		me.dashes += 1
	var mv: Vector2 = intent.get("move", Vector2.ZERO)
	me.vel = Vector2(mv.x * WALK_SPEED, 0.0)
	me.pos += me.vel * DT
