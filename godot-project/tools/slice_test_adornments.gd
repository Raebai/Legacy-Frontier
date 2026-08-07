# HAIR, FACE AND SHEATH — the three procedural slots, and the contracts they must
# not break.
#
# ⚠ THE SPEC THIS IMPLEMENTS WAS STALE. `2026-08-05-stick-customisation.md` says a
# new item is "a PNG plus a registry row" because it was written when `EQUIP_TEX`
# overlaid PixelLab art. That registry is GONE — the rig has been fully procedural
# since the maker's ruling that gear must REPLACE a part rather than sit on it — so
# these three slots needed no art at all, only drawing.
#
#   godot --headless --path godot-project --script tools/slice_test_adornments.gd
extends SceneTree

const TESTS: Array[String] = [
	"new_slots_are_recorded_and_clearable",
	"adornments_never_move_the_head_hitbox",
	"adornments_stay_out_of_the_gear_registry",
	"the_swordsaint_wears_its_saya",
	"every_kind_survives_a_pose",
]

var _failures: Array[String] = []
var _ran: Dictionary = {}
var _started: bool = false

const HAIR: Array[String] = ["spiky", "long", "mop"]
const FACE: Array[String] = ["shades", "visor"]
const SHEATH: Array[String] = ["saya", "scabbard"]


func _process(_d: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _run() -> void:
	_test_new_slots_are_recorded_and_clearable()
	_test_adornments_never_move_the_head_hitbox()
	_test_adornments_stay_out_of_the_gear_registry()
	_test_the_swordsaint_wears_its_saya()
	_test_every_kind_survives_a_pose()
	for n: String in TESTS:
		if not _ran.has(n):
			_failures.append("test `%s` is registered but never ran to completion" % n)
	if _failures.is_empty():
		print("Adornment tests: all PASS")
		quit(0)
	else:
		for f: String in _failures:
			print("FAIL: %s" % f)
		print("Adornment tests: %d FAILED" % _failures.size())
		quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _completes(n: String) -> void:
	_ran[n] = true


func _rig() -> Node2D:
	var r: Node2D = CharacterRig.new()
	root.add_child(r)
	return r


## `set_equipment` validates nothing and accepts any slot string — which is exactly
## why these cost no API. Assert that rather than leaving it as folklore.
func _test_new_slots_are_recorded_and_clearable() -> void:
	var rig: Node2D = _rig()
	for pair: Array in [["hair", "spiky"], ["face", "shades"], ["sheath", "saya"]]:
		rig.call("set_equipment", pair[0], pair[1])
		var eq: Dictionary = rig.get("equipment")
		_expect(String(eq.get(pair[0], "")) == String(pair[1]),
			"slot '%s' records '%s'" % [pair[0], pair[1]])
		rig.call("set_equipment", pair[0], "")
		eq = rig.get("equipment")
		_expect(not eq.has(pair[0]), "slot '%s' clears on empty" % pair[0])
	rig.queue_free()
	_completes("new_slots_are_recorded_and_clearable")


## ⚠ THE CONTRACT `_draw_head` STATES IN CAPITALS: every variant keeps a filled disc
## of exactly `r` centred on `head_center`, because that circle is what
## `Enemy.body_distance` and `SpellTargets` test against. Break it and spells start
## passing through heads again — a bug this project has already shipped once.
func _test_adornments_never_move_the_head_hitbox() -> void:
	var rig: Node2D = _rig()
	rig.set("height", 31.0)
	var base: Dictionary = rig.call("_compute_pose")
	var bc: Vector2 = base["head_center"]
	var br: float = float(base["r"])
	for h: String in HAIR:
		for f: String in FACE:
			rig.call("set_equipment", "hair", h)
			rig.call("set_equipment", "face", f)
			var pose: Dictionary = rig.call("_compute_pose")
			_expect((pose["head_center"] as Vector2).distance_to(bc) < 0.001,
				"hair '%s' + face '%s' does not move head_center" % [h, f])
			_expect(absf(float(pose["r"]) - br) < 0.001,
				"hair '%s' + face '%s' does not change the head radius" % [h, f])
	rig.queue_free()
	_completes("adornments_never_move_the_head_hitbox")


## ⚠ AND THEY MUST STAY OUT OF `GEAR_KINDS`. Every entry there is obliged to carry a
## `GearAbilities` stat bag and survive the no-strict-dominance sweep — the right bar
## for a war hammer and an absurd one for sunglasses. `"sandals"` has been drawn
## outside the registry for as long as it has existed; this follows it.
func _test_adornments_stay_out_of_the_gear_registry() -> void:
	var consts: Dictionary = (load("res://scripts/combat/CharacterRig.gd") as GDScript) \
		.get_script_constant_map()
	var kinds: Array = consts.get("GEAR_KINDS", [])
	_expect(not kinds.is_empty(), "the gear registry still exists")
	for k: String in (HAIR + FACE + SHEATH):
		_expect(not kinds.has(k),
			"'%s' is NOT in GEAR_KINDS — it is decoration, not a stat bag" % k)
	_completes("adornments_stay_out_of_the_gear_registry")


## The one preset that actually uses a sheath. An iai is a DRAW, so the class whose
## whole identity is one cut has to be visibly wearing something to draw from.
func _test_the_swordsaint_wears_its_saya() -> void:
	var rig: Node2D = _rig()
	rig.call("class_preset", "swordsaint")
	var eq: Dictionary = rig.get("equipment")
	_expect(String(eq.get("sheath", "")) == "saya",
		"the swordsaint preset wears a saya (got '%s')" % String(eq.get("sheath", "")))
	_expect(String(eq.get("weapon", "")) == "sword",
		"...and still holds the blade")
	rig.queue_free()
	_completes("the_swordsaint_wears_its_saya")


## By-absence armour: a kind that throws inside `_draw` takes the whole figure with
## it, and a rig that cannot draw is not a rig. Drive a real frame per combination.
func _test_every_kind_survives_a_pose() -> void:
	var rig: Node2D = _rig()
	rig.set("height", 31.0)
	for h: String in (HAIR + [""]):
		for f: String in (FACE + [""]):
			for sh: String in (SHEATH + [""]):
				rig.call("set_equipment", "hair", h)
				rig.call("set_equipment", "face", f)
				rig.call("set_equipment", "sheath", sh)
				rig.call("advance", 0.05)
				var pose: Dictionary = rig.call("_compute_pose")
				_expect(pose.has("head_center") and pose.has("hip"),
					"pose still computes with hair='%s' face='%s' sheath='%s'" % [h, f, sh])
				var hc: Vector2 = pose["head_center"]
				_expect(is_finite(hc.x) and is_finite(hc.y),
					"pose stays finite with hair='%s' face='%s' sheath='%s'" % [h, f, sh])
	rig.queue_free()
	_completes("every_kind_survives_a_pose")
