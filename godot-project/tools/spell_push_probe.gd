# What every routed spectacle now shoves at, against what it shoved at before, and
# against the one threshold that decides whether the world answers the hit.
#
#   godot --headless --path godot-project --script tools/spell_push_probe.gd
extends SceneTree

# name, damage, tier_mult, the retired hand-tuned constant
const ROWS: Array = [
	["BladeFlurry", 18.0, 1.0, 150.0],
	["CrescentStep", 34.0, 1.0, 190.0],
	["EnergyNova", 30.0, 1.30, 275.0],
	["BeamSpell", 46.0, 1.30, 235.0],
	["BlinkStrike", 50.0, 1.30, 280.0],
	["BoulderHurl", 52.0, 1.30, 300.0],
	["HeavensWrath", 42.0, 1.70, 190.0],
	["DivineRay", 95.0, 1.70, 210.0],
]


## Distance a decaying knockback channel actually carries a body, per the curve
## documented on `SpellTier`: roughly I^2 / 1800 px.
func _px(impulse: float) -> float:
	return impulse * impulse / 1800.0


func _init() -> void:
	var slam: float = SlamPhysics.MIN_SLAM_SPEED
	print("=== SPELL PUSH (slam threshold = %.0f) ===" % slam)
	print("%-14s %6s | %8s %7s %6s | %8s %7s %6s" %
		["spell", "dmg", "was", "px", "slam?", "now", "px", "slam?"])
	var was_below: int = 0
	var now_below: int = 0
	for r: Array in ROWS:
		var was: float = float(r[3])
		var now: float = SpellTier.push_for_spectacle(float(r[1]), float(r[2]))
		if was < slam:
			was_below += 1
		if now < slam:
			now_below += 1
		print("%-14s %6.0f | %8.0f %7.0f %6s | %8.0f %7.0f %6s" %
			[r[0], r[1], was, _px(was), "no" if was < slam else "YES",
				now, _px(now), "no" if now < slam else "YES"])
	print("\ncould not crack a wall: %d of %d  ->  %d of %d"
		% [was_below, ROWS.size(), now_below, ROWS.size()])
	quit(0)
