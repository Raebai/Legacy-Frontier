# DIAGNOSTIC (not a suite — `run_all_tests.py` only collects `*test_*`).
#
# THE QUESTION: can a bot standing in its own authored spacing band actually REACH
# the spells it is holding? `BotBrain._score_slots` calls `_range_fit`, and a fit of
# 0.0 makes the slot `continue` — it is not scored low, it is not scored at all. So a
# class whose band sits outside its own kit's range holds spells it can never ask for,
# and the utility scorer reports nothing, because it never sees them.
#
# Prints, per class: the band, and each slot's effective range and its fit at the
# band's near edge / centre / far edge.
#   Godot_v4.6.2-stable_win64_console.exe --path godot-project --headless --script tools/bot_range_probe.gd
extends SceneTree

const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]


func _init() -> void:
	print("=".repeat(96))
	print("BOT RANGE PROBE — kit reach vs authored spacing band")
	print("=".repeat(96))
	var dead_slots: int = 0
	var dead_classes: int = 0
	for cid: int in range(CLASS_NAMES.size()):
		var band: Dictionary = BotBrain.CLASS_BAND[cid] if cid < BotBrain.CLASS_BAND.size() \
			else BotBrain.DEFAULT_BAND
		var lo: float = float(band["min"])
		var hi: float = float(band["max"])
		var mid: float = (lo + hi) * 0.5
		var facts: Array = BotBrain._kit_facts(cid)
		print("\n%-12s band %.0f..%.0f  (centre %.0f)" % [CLASS_NAMES[cid], lo, hi, mid])
		var reachable_here: int = 0
		for i: int in range(facts.size()):
			var f: Dictionary = facts[i]
			var rng: float = float(f["range"])
			var ok: bool = bool(f["close_ok"])
			var fit_lo: float = BotBrain._range_fit(lo, rng, ok)
			var fit_mid: float = BotBrain._range_fit(mid, rng, ok)
			var fit_hi: float = BotBrain._range_fit(hi, rng, ok)
			# The honest test is the CENTRE: the deadband parks the bot there and it
			# only leaves the band under danger or a pickup pull.
			var verdict: String = "ok"
			if fit_mid <= 0.0:
				verdict = "DEAD AT CENTRE"
				dead_slots += 1
			elif fit_hi <= 0.0:
				verdict = "dead at far edge"
			else:
				reachable_here += 1
			print("   slot %d  %-18s %-9s range %6.0f  close_ok=%-5s  fit lo/mid/hi %.2f %.2f %.2f  %s"
				% [i, String(f["id"]), String(f["role"]), rng, str(ok),
					fit_lo, fit_mid, fit_hi, verdict])
		if reachable_here <= 1:
			dead_classes += 1
			print("   ^^ only %d of %d slots reachable from its own stance" % [reachable_here, facts.size()])
	print("\n" + "=".repeat(96))
	print("TOTAL: %d slots unreachable at band centre; %d classes with <=1 reachable slot"
		% [dead_slots, dead_classes])
	quit(0)
