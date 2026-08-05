# DIAGNOSTIC ONLY — read-only probe for the Gravity Well redesign. Safe to delete.
# Run: godot --headless --path godot-project --script tools/_probe_gravity.gd
extends SceneTree

const HERO_SCRIPT: String = "res://scripts/combat/Hero.gd"
const ENEMY_SCRIPT: String = "res://scripts/combat/Enemy.gd"

var _ran: bool = false


func _k(s: String, name: String, fallback: float) -> float:
	var gd: GDScript = load(s) as GDScript
	if gd == null:
		return fallback
	var m: Dictionary = gd.get_script_constant_map()
	return float(m.get(name, fallback))


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true

	var hero_g: float = _k(HERO_SCRIPT, "GRAVITY_FALL", -1.0)
	var hero_maxfall: float = _k(HERO_SCRIPT, "MAX_FALL", -1.0)
	var hero_air: float = _k(HERO_SCRIPT, "AIR_ACCEL", -1.0)
	var hero_ground: float = _k(HERO_SCRIPT, "GROUND_ACCEL", -1.0)
	var hero_spd: float = _k(HERO_SCRIPT, "SPEED", -1.0)
	var en_g: float = _k(ENEMY_SCRIPT, "GRAVITY", -1.0)
	var en_maxfall: float = _k(ENEMY_SCRIPT, "MAX_FALL", -1.0)
	print("[consts] Hero GRAVITY_FALL=%.0f MAX_FALL=%.0f AIR_ACCEL=%.0f GROUND_ACCEL=%.0f SPEED=%.0f"
		% [hero_g, hero_maxfall, hero_air, hero_ground, hero_spd])
	print("[consts] Enemy GRAVITY=%.0f MAX_FALL=%.0f" % [en_g, en_maxfall])

	var lay: Resource = (load("res://scripts/tower/LayoutDef.gd") as GDScript).new()
	print("[room] LayoutDef.room_size=%s  RoomShell default=%s"
		% [str(lay.get("room_size")), str(Vector2(1160.0, 540.0))])

	var lib: GDScript = load("res://scripts/combat/SpellLibrary.gd") as GDScript
	var gf: Resource = lib.call("by_id", "gravity_flip")
	if gf != null:
		print("[spelldef] gravity_flip radius=%.1f reach=%.1f length=%.2f cd=%.2f mp=%d dmg=%d"
			% [float(gf.get("radius")), float(gf.get("reach")), float(gf.get("length")),
			float(gf.get("cooldown")), int(gf.get("mp_cost")), int(gf.get("damage"))])
	else:
		print("[spelldef] gravity_flip NOT FOUND via drop_by_id/all_spells")

	# --- 1. CURRENT SPELL: how long a hero takes to reach the ceiling, and how much
	#        of the 5 s is spent pinned there.
	var lift: float = 3400.0
	var max_rise: float = 520.0
	var tick: float = 1.0 / 60.0
	for room_h: float in [540.0, 500.0]:
		var y: float = room_h - 24.0   # standing on the floor
		var vy: float = 0.0
		var t: float = 0.0
		var top: float = 16.0
		while t < 5.0 and y > top:
			vy = maxf(vy - lift * tick, -max_rise)
			vy = minf(vy + hero_g * tick, hero_maxfall)   # its own gravity still runs
			y += vy * tick
			t += tick
		print("[current] room_h=%.0f -> ceiling reached at t=%.2fs, pinned for %.2fs of 5.0s (%.0f%%)"
			% [room_h, t, maxf(5.0 - t, 0.0), 100.0 * maxf(5.0 - t, 0.0) / 5.0])

	# --- 2. THE COLLAPSE: fall time and impact speed from a given height.
	for h: float in [120.0, 200.0, 260.0, 320.0, 420.0, 520.0]:
		var y2: float = 0.0
		var v2: float = 0.0
		var t2: float = 0.0
		while y2 < h and t2 < 6.0:
			v2 = minf(v2 + hero_g * tick, hero_maxfall)
			y2 += v2 * tick
			t2 += tick
		print("[collapse] fall %.0f px -> %.2fs, impact %.0f px/s" % [h, t2, v2])

	# --- 3. Does hostiles() with a NULL caster return the raw group unchanged?
	var probe := Node2D.new()
	root.add_child(probe)
	var a := Node2D.new()
	var b := Node2D.new()
	root.add_child(a)
	root.add_child(b)
	a.add_to_group("probe_grp")
	b.add_to_group("probe_grp")
	var raw: Array = get_nodes_in_group("probe_grp")
	var filtered: Array = SpellTargets.hostiles(probe, &"probe_grp")
	print("[hostiles] null caster: raw=%d filtered=%d (equal=%s)"
		% [raw.size(), filtered.size(), str(raw.size() == filtered.size())])
	probe.set("caster_node", a)
	var filtered2: Array = SpellTargets.hostiles(probe, &"probe_grp")
	print("[hostiles] caster set (undeclared prop, set() is a no-op on Node2D): filtered=%d"
		% filtered2.size())

	# --- 4. The test stub's geometry: is the vacuous-pass claim true?
	var stub: Node2D = (load("res://tools/_stub_body.gd") as GDScript).new()
	root.add_child(stub)
	print("[stub] _stub_body position=%s ; a bare GravityFlip.new() has _center=%s ; dist=%.1f"
		% [str(stub.global_position), str(Vector2.ZERO),
		stub.global_position.distance_to(Vector2.ZERO)])
	print("[stub] has is_on_floor=%s has apply_status=%s has take_damage=%s"
		% [str(stub.has_method("is_on_floor")), str(stub.has_method("apply_status")),
		str(stub.has_method("take_damage"))])

	# --- 5. StatusComponent EARTH -> stagger numbers (the landing stun).
	var sc: GDScript = load("res://scripts/combat/StatusComponent.gd") as GDScript
	var scm: Dictionary = sc.get_script_constant_map()
	print("[stun] EARTH=%s STAGGER_DURATION=%.2f FREEZE_SLOW=%.2f"
		% [str(scm.get("EARTH")), float(scm.get("STAGGER_DURATION", -1.0)),
		float(scm.get("FREEZE_SLOW", -1.0))])

	# --- 6. BotBrain range today vs. with a real reach.
	var bb: GDScript = load("res://scripts/combat/BotBrain.gd") as GDScript
	var bbm: Dictionary = bb.get_script_constant_map()
	print("[bot] HEX_SELF_CAST=%s HEX_SELF_RANGE=%.0f"
		% [str(bbm.get("HEX_SELF_CAST")), float(bbm.get("HEX_SELF_RANGE", -1.0))])

	quit(0)
	return true
