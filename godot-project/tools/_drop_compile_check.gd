# Throwaway: force-compile every drop-economy script so a parse error surfaces as
# a message rather than as a silent no-op at runtime. Not a test suite (no
# `test_` in the name, so run_all_tests.py never picks it up).
#   godot --headless --path godot-project --script tools/_drop_compile_check.gd
extends SceneTree

const PATHS: Array[String] = [
	"res://scripts/combat/HpWatch.gd",
	"res://scripts/combat/SpellDrops.gd",
	"res://scripts/combat/SpellGrant.gd",
	"res://scripts/combat/SpellPickup.gd",
	"res://scripts/combat/SpellHandoff.gd",
	"res://scripts/combat/BossDropWatcher.gd",
	"res://scripts/combat/Petrify.gd",
	"res://scripts/combat/GravityFlip.gd",
	"res://scripts/combat/BloodPact.gd",
	"res://scripts/combat/MirrorImage.gd",
	"res://scripts/combat/VoidCollapse.gd",
	"res://scripts/combat/Chronostasis.gd",
	"res://scripts/combat/Equinox.gd",
	"res://scripts/combat/SpellCaster.gd",
	"res://scripts/combat/SpellLibrary.gd",
	"res://scripts/combat/FloorBuilder.gd",
	"res://scripts/combat/HandSlots.gd",
]


func _initialize() -> void:
	var bad: int = 0
	for p: String in PATHS:
		var s: GDScript = load(p) as GDScript
		if s == null or not s.can_instantiate() and not s.is_tool():
			pass
		if s == null:
			printerr("FAIL: could not load ", p)
			bad += 1
			continue
		print("ok  ", p)
	print("compile check: ", "all PASS" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
