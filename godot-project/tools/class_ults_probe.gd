# Run: godot --headless --path godot-project --script tools/class_ults_probe.gd
#
# DOES EVERY CLASS ACTUALLY GET ITS ULT IN HAND?
#
# The maker: *"maybe the default class needs its ult spell"*. `CLASS_KITS` authors an
# `ult` role for all nine, and every class's default slot list includes "ult" — so on
# paper nobody is missing one. Paper is not the hand. This asks the same function the
# Hero asks (`SpellLibrary.build_for_class`) and prints what actually lands in each of
# the four slots, with the ULT SLOT called out by name.
extends SceneTree

const LIB: String = "res://scripts/combat/SpellLibrary.gd"
const TIER: String = "res://scripts/combat/SpellTier.gd"


func _initialize() -> void:
	var lib: GDScript = load(LIB) as GDScript
	var tier: GDScript = load(TIER) as GDScript
	var slot_count: int = int(tier.get_script_constant_map().get("SLOT_COUNT", 4))
	var ult_slot: int = int(tier.get_script_constant_map().get("ULT_SLOT", slot_count - 1))
	print("\n== what each class actually carries ==")
	print("  SLOT_COUNT=%d  ULT_SLOT=%d" % [slot_count, ult_slot])

	var names: Array = lib.get_script_constant_map().get("CLASS_NAMES", [])
	for cls: int in 9:
		var hand: Array = lib.call("build_for_class", cls)
		var label: String = str(names[cls]) if cls < names.size() else "class %d" % cls
		var ids: Array[String] = []
		for i: int in hand.size():
			var d: Object = hand[i] as Object
			var sid: String = "(empty)"
			if d != null:
				sid = String(d.get("id")) if d.get("id") != null else "(no id)"
			ids.append(("**%s**" % sid) if i == ult_slot else sid)
		var ult_ok: bool = hand.size() > ult_slot and hand[ult_slot] != null
		print("  %-14s %-2d slots: %s   ULT %s"
			% [label, hand.size(), ", ".join(ids), "OK" if ult_ok else "MISSING"])
	quit(0)
