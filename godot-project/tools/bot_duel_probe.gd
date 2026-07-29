extends SceneTree
## LIVE-DUEL SEAM PROBE — not a unit test. Reproduces the geometry of the maker's
## complaint ("the bot never dashes away from attacks") by feeding BotBrain a
## blackboard in EXACTLY the shape BotController.build_blackboard emits for a
## hero-vs-hero duel, then reporting what came out the other end of the whole
## chain: brain intent -> BotIntent.sanitized -> the held action set the body polls.
##
## WHY A PROBE AND NOT A TEST: the unit suites are green and the bot still looks
## like a noob, so the failure is at a seam. A probe prints the chain; a test only
## says pass.

const FRAME: float = 1.0 / 60.0


func _init() -> void:
	print("=== BOT DUEL PROBE ===")
	_scenario("bolt travelling RIGHT (bot stands to the right of the human)", 1.0)
	_scenario("bolt travelling LEFT  (bot stands to the left of the human)", -1.0)
	_zone()
	quit()


## THE ZONE CASE — an armed circle telegraph snapped onto the bot, which is what
## every placed spell in the game plants. Verifies the reflex still answers this
## with a real horizontal DASH (the jump hoist must not have eaten it).
func _zone() -> void:
	print("\n--- armed circle telegraph centred on the bot ---")
	var me: Vector2 = Vector2(400.0, 300.0)
	var foe: Vector2 = Vector2(180.0, 300.0)
	var profile: Dictionary = BotProfile.with_overrides(1, {"p_miss": 0.0})
	var mem: Object = BotBrain.Memory.new()
	var ctrl: BotController = BotController.new()
	var now: float = 0.0
	var fuse: float = 0.9
	for frame: int in 90:
		now += FRAME
		fuse -= FRAME
		if fuse <= 0.0:
			print("  telegraph fired; never answered.")
			return
		var bb: Dictionary = _blackboard(me, foe, me, Vector2.ZERO, now)
		bb["threats"] = [{
			"id": 4321, "kind": "circle", "pos": me, "vel": Vector2.ZERO,
			"radius": 70.0, "length": 0.0, "width": 0.0, "angle": 0.0,
			"tti": fuse, "parryable": false,
			"region": {"shape": "circle", "center": me, "radius": 70.0},
		}]
		var raw: Variant = BotBrain.decide(bb, profile, mem)
		var intent: Dictionary = ctrl.drive(raw)
		if bool(intent[BotIntent.DASH]) or bool(intent[BotIntent.JUMP]):
			print("  f%02d t=%.3f fuse=%.2f -> %s | HELD=%s" % [
				frame, now, fuse, _fmt(raw), str(ctrl._held.keys())])
			return


## One duel: a hero bolt crossing the gap at Spell.SPEED, bot standing on the
## ground at the same height, which is the overwhelmingly common duel picture.
func _scenario(label: String, dir_x: float) -> void:
	print("\n--- %s ---" % label)
	var me: Vector2 = Vector2(400.0, 300.0) if dir_x > 0.0 else Vector2(100.0, 300.0)
	var foe: Vector2 = Vector2(100.0, 300.0) if dir_x > 0.0 else Vector2(400.0, 300.0)
	var bolt: Vector2 = foe + Vector2(40.0 * dir_x, 0.0)
	var bolt_vel: Vector2 = Vector2(460.0 * dir_x, 0.0)

	# p_miss zeroed so the probe measures the SEAM, not the deliberate 28%% whiff roll.
	var profile: Dictionary = BotProfile.with_overrides(1, {"p_miss": 0.0})
	var mem: Object = BotBrain.Memory.new()
	var ctrl: BotController = BotController.new()

	var now: float = 0.0
	for frame: int in 90:
		now += FRAME
		bolt += bolt_vel * FRAME
		# Stop once the bolt is past the bot: everything after is noise.
		if (bolt.x - me.x) * dir_x > 60.0:
			break
		var bb: Dictionary = _blackboard(me, foe, bolt, bolt_vel, now)
		var raw: Variant = BotBrain.decide(bb, profile, mem)
		var intent: Dictionary = ctrl.drive(raw)
		var held: Dictionary = ctrl._held
		var seen: int = int(mem.reactions.tracked())
		var visible: bool = mem.reactions.visible(1234, now)
		var evaluated: Dictionary = BotDodge.threat_from_projectile(me, bolt, bolt_vel)
		# Print only frames where something interesting happened, plus the moment
		# the threat becomes actionable — a per-frame dump buries the answer.
		if frame % 6 == 0:
			print("  .f%02d t=%.2f gap=%4.0f vis=%s thr=%s tti=%.2f exit=%s tracked=%d" % [
				frame, now, absf(bolt.x - me.x), visible, evaluated["threatening"],
				evaluated["tti"], str(evaluated["exit"].round()), seen])
		if visible and bool(evaluated["threatening"]):
			print("  f%02d t=%.3f gap=%4.0f | threatening=%s tti=%.2f exit=%s" % [
				frame, now, absf(bolt.x - me.x), evaluated["threatening"],
				evaluated["tti"], str(evaluated["exit"].round())])
			print("      brain-> %s" % _fmt(raw))
			print("      intent move=%s dash=%s jump=%s | HELD=%s" % [
				str(intent[BotIntent.MOVE]), intent[BotIntent.DASH],
				intent[BotIntent.JUMP], str(held.keys())])
			break
		if frame == 89:
			print("  never became actionable. tracked=%d" % seen)


func _fmt(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "<not a dict>"
	var d: Dictionary = raw
	var parts: PackedStringArray = []
	for k: Variant in d.keys():
		parts.append("%s=%s" % [k, d[k]])
	return ", ".join(parts)


## The blackboard shape BotController.build_blackboard produces for a hero body,
## with ONE live `player_spell` threat in the exact record shape
## BotController.perceive_threats appends for a projectile.
func _blackboard(me: Vector2, foe: Vector2, bolt: Vector2, bolt_vel: Vector2,
		now: float) -> Dictionary:
	var cds: Array[float] = []
	for _i: int in BotIntent.CD_COUNT:
		cds.append(0.0)
	return {
		"self_id": 1, "self_pos": me, "self_vel": Vector2.ZERO,
		"self_hp_frac": 1.0, "self_mp_frac": 1.0,
		"on_floor": true, "facing": signf(foe.x - me.x),
		"foe_id": 2, "foe_pos": foe, "foe_vel": Vector2.ZERO,
		"foe_hp_frac": 1.0, "foe_facing": signf(me.x - foe.x),
		"threats": [{
			"id": 1234, "kind": "projectile", "pos": bolt, "vel": bolt_vel,
			"radius": 6.0, "length": 0.0, "width": 0.0, "angle": bolt_vel.angle(),
			"tti": 0.0, "parryable": true,
			"region": {"shape": "circle", "center": bolt, "radius": 6.0},
		}],
		"hazards": [], "fields": [], "barriers": [],
		"cooldowns": cds, "reach": 58.0, "now": now,
		"class_id": 0, "guard_style": 0, "can_parry": true,
		"slot_affordable": [true, true, true, true, true],
		"slot_cast_time": [0.0, 0.0, 0.0, 0.0, 0.0],
	}
