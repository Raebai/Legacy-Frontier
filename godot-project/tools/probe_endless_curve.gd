extends SceneTree
## ═══════════════════════════════════════════════════════════════════════════════
## WHAT DOES THE ENDLESS TOWER ACTUALLY DO TO YOU? — the curve, READ not trusted.
## ═══════════════════════════════════════════════════════════════════════════════
##
## Run:
##   godot-engine/Godot_v4.6.2-stable_win64_console.exe --headless \
##       --path godot-project --script tools/probe_endless_curve.gd
##   ... --script tools/probe_endless_curve.gd -- --to=80 --seeds=5
##
## Options (`--key=value`, order-independent):
##   --to=N       climb to this floor. Default 50.
##   --seeds=N    how many climb seeds to sweep for the VARIANCE block. Default 3.
##   --seed=N     pin the seed the per-floor table is printed from. Default 12345,
##                so the table is reproducible and a change to it is a real change.
##
## ── WHY THIS EXISTS ───────────────────────────────────────────────────────────
## The tower is infinite now (`TowerDef.endless`), and an infinite difficulty curve
## has exactly two ways to be wrong, both of which are invisible from the source:
##
##     it becomes UNWINNABLE around floor 12   (a step nobody survives)
##     it becomes TRIVIAL around floor 40      (a plateau reached far too early)
##
## Neither is findable by reading `GameState.ascent_floor_def` — the numbers there
## are per-floor and the failure is in their SHAPE. So this walks the real path the
## game walks (`GameState._load_or_build_tower` -> `floor_def_for`, including the
## `FloorGen` redraw, the ascent's floor affixes, and the health-pack stamping) and
## prints what each floor actually contains.
##
## ⚠ WHAT IT MEASURES IS CONTENT, NOT DIFFICULTY. Nobody is playing; there is no
## hero, no AI and no dodge. `tools/floor_sim.gd` and `tools/floorgen_sim.gd` already
## estimate DURATION and its spread, and every caveat on those applies here. What
## this tool can say that they cannot is whether the tower's shape ESCALATES, where
## each axis stops, and whether any floor is easier than the one below it.
##
## ⚠ AND THE COMPOSITE INDEX IS A READ, NOT A MEASUREMENT. Its weights are printed
## with it precisely so nobody mistakes it for physics. The RAW COLUMNS are the
## evidence; the index exists so the shape can be seen at a glance and so an
## inversion has something to be an inversion of.

const GS_PATH: String = "res://scripts/GameState.gd"
## ⚠ RUNTIME `load()`, never named — `FloorBuilder` reaches `DestructibleProp.gd`,
## which calls the `Sfx` AUTOLOAD, and an autoload cannot resolve while this script is
## compiling. Naming it puts a compile error into every run of this probe.
const FLOOR_BUILDER_PATH: String = "res://scripts/combat/FloorBuilder.gd"

## Composite weights. Printed in the header, for the reason above. Chosen so that on
## the AUTHORED spine — which is hand-tuned and therefore the only ground truth this
## file has — the index rises monotonically from floor 1 to floor 10. Anything that
## makes the authored ten stop rising is a wrong weight, not a wrong tower.
const W_BODIES: float = 0.06        # per body
const W_CAP: float = 1.60           # per concurrent slot — what you feel, not count
const W_CLASSES: float = 2.20       # per distinct threat class fielded
const W_AFFIX: float = 3.00         # per floor-wide rule riding every body
const W_ELITE: float = 0.80         # per (elite x word over its head)
const W_NOHEAL: float = 1.50        # per health pack the floor does NOT give you
const W_BOSS: float = 1.20          # per unit of guardian HP multiplier

const CLASS_NAMES: Dictionary = {0: "pressure", 1: "heavy", 2: "ranged", 4: "odd"}
const ARCH_NAMES: Array[String] = ["chaser", "brute", "caster", "charger",
	"summoner", "assassin", "bomber", "mage"]
const TYPE_NAMES: Array[String] = ["COMBAT", "ELITE", "BOSS", "REST", "PVP"]

var _to: int = 50
var _seeds: int = 3
var _seed: int = 12345
var _ran: bool = false


func _process(_delta: float) -> bool:
	# ⚠ `_initialize()` runs BEFORE the tree exists and `FloorGen._coop_active()`
	# reaches through the main loop's root, so everything here waits a frame.
	if _ran:
		return false
	_ran = true
	_parse_args()

	print("")
	print("════════════════════════════════════════════════════════════════════════")
	print(" THE ENDLESS TOWER — content curve, floors 1..%d, seed %d" % [_to, _seed])
	print(" Floors 1-10 are the AUTHORED spine. 11+ are the ASCENT.")
	print(" index = %.2f*bodies + %.2f*cap + %.2f*classes + %.2f*affixes"
		% [W_BODIES, W_CAP, W_CLASSES, W_AFFIX])
	print("       + %.2f*(elites*words) + %.2f*(2-packs) + %.2f*bossHP   (a READ, not a measurement)"
		% [W_ELITE, W_NOHEAL, W_BOSS])
	print("════════════════════════════════════════════════════════════════════════")

	var rows: Array[Dictionary] = _walk(_seed, _to)
	_print_table(rows)
	_print_plateaus(rows)
	_print_inversions(rows)
	_print_hp_rule(rows)
	_print_variance()
	print("")
	quit(0)
	return true


# ══════════════════════════════════════════════════════════════════════════════
# THE WALK — the real path, not a reimplementation of it
# ══════════════════════════════════════════════════════════════════════════════
## Climb one tower and collect a row per floor.
##
## ⚠ IT DRIVES `GameState.floor_def_for`, WHICH IS THE POINT. A probe that rebuilt
## the ascent from `ascent_floor_def` alone would measure the BLUEPRINT and miss
## everything `FloorGen.vary_floor` does to it — the reshaped wave budgets, the
## swapped/widened/characterised rosters, the re-cut pressure caps and the ascent's
## own floor affixes. That is most of what a player meets.
func _walk(seed_value: int, to_floor: int) -> Array[Dictionary]:
	var GS: GDScript = load(GS_PATH) as GDScript
	var gs: Node = GS.new()
	# Pin the climb seed so the table is reproducible. `FloorGen.climb_seed` is the
	# documented override `resolve_seed()` honours ahead of everything else.
	FloorGen.climb_seed = seed_value
	gs.active_tower = gs._load_or_build_tower()
	var out: Array[Dictionary] = []
	for f: int in range(1, to_floor + 1):
		out.append(_read_floor(gs, f))
	FloorGen.climb_seed = 0
	gs.free()
	return out


## Everything one floor contains, as plain numbers.
func _read_floor(gs: Node, floor_no: int) -> Dictionary:
	var fd: FloorDef = gs.floor_def_for(floor_no)
	var bodies: int = 0
	var peak_cap: int = 0
	var class_hits: Dictionary = {}     # class key -> roster entries in that class
	var arch_hits: Dictionary = {}      # archetype id -> roster entries
	var elite_waves: int = 0
	# ⚠ THE BREADTH THAT COUNTS IS PER-WAVE, NOT PER-FLOOR, and the first version of
	# this probe measured the wrong one. Summed across a floor, breadth hit 4 by floor
	# 3 and never moved again — not because the floor was maximally broad, but because
	# consecutive waves rotate to different class pairs, so ANY four-wave floor touches
	# all four classes eventually. What a player actually meets is how many different
	# problems are on screen AT ONCE, which is one wave's roster. The floor total is
	# kept below as `floor_classes` because it is what the mix block prints.
	var wave_cls_sum: int = 0
	var wave_cls_max: int = 0
	for w: WaveDef in fd.waves:
		bodies += maxi(w.enemy_budget, 0)
		peak_cap = maxi(peak_cap, w.concurrent_cap)
		if w.elite_wave:
			elite_waves += 1
		var in_wave: Dictionary = {}
		for a: int in w.archetypes:
			var key: int = FloorGen.threat_class(a)[0]
			class_hits[key] = int(class_hits.get(key, 0)) + 1
			arch_hits[a] = int(arch_hits.get(a, 0)) + 1
			in_wave[key] = true
		# An EMPTY roster is the floor's weighted roll over all eight archetypes, which
		# is genuinely four classes wide. Counting it as zero would report the
		# synthesized fallback as the easiest thing in the tower.
		var here: int = in_wave.size() if not in_wave.is_empty() else 4
		wave_cls_sum += here
		wave_cls_max = maxi(wave_cls_max, here)
	# ⚠ THE MEAN, NOT THE MAX, AND THAT IS THE SECOND TIME THIS COLUMN MOVED. Once
	# every ascent floor's FINALE fields four classes (which is the fix for the seam
	# step-down — see GameState's ASCENT_BREADTH block), the MAX is 4 on every floor
	# from 11 upward and the column stops carrying any signal at all. What escalates
	# is how much OF the floor is wide, i.e. how few narrow waves you get to settle
	# into — and the mean is exactly that number.
	var distinct: float = float(wave_cls_sum) / float(maxi(fd.waves.size(), 1))
	var floor_classes: int = class_hits.size() if not class_hits.is_empty() else 4
	var affixes: Array[String] = EliteRoster.parse_floor_affixes(fd.special_tags)
	var packs: int = _pack_count(fd)
	var mods: int = BossRoster.modifier_count(maxi(fd.depth, floor_no))
	var e_budget: int = EliteRoster.budget(maxi(fd.depth, floor_no))
	var e_words: int = EliteRoster.affix_count(maxi(fd.depth, floor_no))
	var index: float = (
		W_BODIES * float(bodies)
		+ W_CAP * float(peak_cap)
		+ W_CLASSES * distinct
		+ W_AFFIX * float(affixes.size())
		+ W_ELITE * float(e_budget * e_words)
		+ W_NOHEAL * float(maxi(2 - packs, 0))
		+ W_BOSS * fd.boss_hp_multiplier
	)
	return {
		"floor": floor_no,
		"authored": floor_no <= gs.total_floors(),
		"type": int(fd.floor_type),
		"waves": fd.waves.size(),
		"bodies": bodies,
		"cap": peak_cap,
		"classes": distinct,
		"classes_max": wave_cls_max,
		"floor_classes": floor_classes,
		"class_hits": class_hits,
		"arch_hits": arch_hits,
		"elite_waves": elite_waves,
		"elite_budget": e_budget,
		"elite_words": e_words,
		"affixes": affixes,
		"packs": packs,
		"boss_hp": fd.boss_hp_multiplier,
		"mods": mods,
		"trash_hp": fd.hp_multiplier,
		"index": index,
	}


## How many health packs the floor will actually build. Mirrors the branch in
## `FloorBuilder.build_health_packs` rather than guessing at it: an empty-and-silent
## layout gets the default pair, an empty-and-AUTHORED one gets nothing.
func _pack_count(fd: FloorDef) -> int:
	var defaults: int = ((load(FLOOR_BUILDER_PATH) as GDScript).DEFAULT_HEALTH_PACKS as Array).size()
	if fd.layout == null:
		return defaults
	if not fd.layout.health_pickups.is_empty():
		return fd.layout.health_pickups.size()
	if fd.layout.health_packs_authored:
		return 0
	return defaults


# ══════════════════════════════════════════════════════════════════════════════
# THE OUTPUT
# ══════════════════════════════════════════════════════════════════════════════
func _print_table(rows: Array[Dictionary]) -> void:
	print("")
	print(" fl  kind    type   wv  bodies  cap  cls̲  elite  affixes            pk  bossHP mods  index")
	print(" ──  ──────  ─────  ──  ──────  ───  ────  ─────  ─────────────────  ──  ────── ────  ─────")
	for r: Dictionary in rows:
		var kind: String = "spine " if bool(r["authored"]) else "ASCENT"
		var aff: String = ", ".join(r["affixes"] as Array[String])
		if aff == "":
			aff = "-"
		var elite: String = "%dx%d%s" % [int(r["elite_budget"]), int(r["elite_words"]),
			("*" if int(r["elite_waves"]) > 0 else " ")]
		print(" %2d  %s  %-5s  %2d  %6d  %3d  %4.1f  %-5s  %-17s  %2d  %5.2fx %3d  %5.1f" % [
			int(r["floor"]), kind, TYPE_NAMES[int(r["type"])], int(r["waves"]),
			int(r["bodies"]), int(r["cap"]), float(r["classes"]), elite,
			aff.substr(0, 17), int(r["packs"]), float(r["boss_hp"]), int(r["mods"]),
			float(r["index"]),
		])
	print("")
	print(" cls̲ is the MEAN threat classes in one wave — how much of the floor is wide, not how wide it ever gets.")
	print(" elite column is budget x words-per-elite; * = the floor concentrates it into one wave.")
	print("")
	print(" ── THE MIX, as the uniform spawn roll actually sees it ──────────────")
	# Every 5th floor only: the whole table would be unreadable, and the band
	# boundary is where the composition is supposed to have moved.
	for r: Dictionary in rows:
		var f: int = int(r["floor"])
		if f % 5 != 0 and f != 1 and f != 11:
			continue
		var parts: Array[String] = []
		var hits: Dictionary = r["class_hits"]
		for k in hits.keys():
			parts.append("%s %d" % [String(CLASS_NAMES.get(int(k), "?")), int(hits[k])])
		parts.sort()
		var arch: Array[String] = []
		var ah: Dictionary = r["arch_hits"]
		for k2 in ah.keys():
			arch.append("%s%d" % [ARCH_NAMES[int(k2)].substr(0, 4), int(ah[k2])])
		arch.sort()
		print(" f%-3d %-38s  %s" % [f, "  ".join(parts), " ".join(arch)])


## WHERE EACH AXIS STOPS. The design note claims specific plateau floors; this is
## what makes that claim checkable rather than a paragraph.
func _print_plateaus(rows: Array[Dictionary]) -> void:
	print("")
	print(" ── PLATEAUS — the floor after which an axis never moves again ───────")
	for key: String in ["bodies", "cap", "waves", "classes", "boss_hp", "packs"]:
		var last_change: int = 1
		for i: int in range(1, rows.size()):
			if not is_equal_approx(float(rows[i][key]), float(rows[i - 1][key])):
				last_change = int(rows[i]["floor"])
		var final_v: float = float(rows[rows.size() - 1][key])
		print("   %-8s last moves at floor %3d, settles at %.2f" % [key, last_change, final_v])
	# Affix count is a list length, so it needs its own read.
	var aff_last: int = 1
	for i2: int in range(1, rows.size()):
		if (rows[i2]["affixes"] as Array).size() != (rows[i2 - 1]["affixes"] as Array).size():
			aff_last = int(rows[i2]["floor"])
	print("   %-8s last moves at floor %3d, settles at %d" % ["affixes", aff_last,
		(rows[rows.size() - 1]["affixes"] as Array).size()])


## ⚠ THE ONE THAT MATTERS. A floor easier than the floor below it is a step DOWN in
## a tower whose whole premise is that it goes up, and it is invisible in the source
## because each floor's numbers are individually reasonable.
##
## ⚠ THE COMPARISON IS WITHIN A FLOOR TYPE, and the first version was not — it
## exempted BOSS and compared everything else in one sequence, which reported floor 7
## and floor 13 as inversions. Both are ELITE floors following a COMBAT floor, and an
## ELITE floor is SUPPOSED to trade bodies and pressure for meaner ones: floor 7's own
## authored comment is "fewer bodies than 6 on purpose — this one is about attention,
## not volume". Calling that a defect is the probe misreading the design.
##
## So COMBAT is compared against the previous COMBAT, ELITE against ELITE, BOSS
## against BOSS. That is the sequence a player experiences as "this kind of floor,
## again, higher up" — and it is the only sequence in which a step DOWN is a fault
## rather than a change of subject.
func _print_inversions(rows: Array[Dictionary]) -> void:
	print("")
	print(" ── INVERSIONS — a floor EASIER than the previous floor OF ITS KIND ────")
	var found: int = 0
	var prev_of: Dictionary = {}      # floor type -> the last row of that type
	for r: Dictionary in rows:
		var t: int = int(r["type"])
		var prev: Dictionary = prev_of.get(t, {})
		if not prev.is_empty() and float(r["index"]) < float(prev["index"]) - 0.001:
			found += 1
			print("   ⚠ %s floor %d (index %.1f) is easier than %s floor %d (index %.1f)  Δ%.1f" % [
				TYPE_NAMES[t], int(r["floor"]), float(r["index"]),
				TYPE_NAMES[t], int(prev["floor"]),
				float(prev["index"]), float(r["index"]) - float(prev["index"])])
		prev_of[t] = r
	if found == 0:
		print("   none — every kind of floor rises monotonically from 1 to %d."
			% int(rows[rows.size() - 1]["floor"]))
	else:
		print("   %d inversion(s). Each one is a floor that reads as a rest you did not earn." % found)


## THE STANDING RULE, COUNTED. "higher floors add modifiers, not HP."
func _print_hp_rule(rows: Array[Dictionary]) -> void:
	print("")
	print(" ── THE HP RULE — trash hp_multiplier must be 1.0 at every depth ─────")
	var bad: int = 0
	for r: Dictionary in rows:
		if not is_equal_approx(float(r["trash_hp"]), 1.0):
			bad += 1
			print("   ⚠ floor %d runs trash at %.2fx" % [int(r["floor"]), float(r["trash_hp"])])
	if bad == 0:
		print("   clean — %d floors, every one at 1.0x. Depth is carried by the mix." % rows.size())
	print("   guardian HP is the one legitimate curve: %.2fx at floor %d, capped at %.2fx."
		% [float(rows[rows.size() - 1]["boss_hp"]), int(rows[rows.size() - 1]["floor"]),
			GameState.ASCENT_BOSS_HP_CAP])


## HOW MUCH DOES THE SEED MOVE IT? A generator's real risk is the OUTLIER, not the
## average — a floor that occasionally comes back a third smaller is a broken promise
## in a way a slightly-off average never is.
func _print_variance() -> void:
	if _seeds <= 1:
		return
	print("")
	print(" ── VARIANCE across %d climb seeds (ascent floors only) ──────────────" % _seeds)
	var by_floor: Dictionary = {}      # floor -> Array[int] of body counts
	for s: int in _seeds:
		var rows: Array[Dictionary] = _walk(_seed + s * 7919, _to)
		for r: Dictionary in rows:
			var f: int = int(r["floor"])
			if not by_floor.has(f):
				by_floor[f] = [] as Array[int]
			(by_floor[f] as Array).append(int(r["bodies"]))
	var worst_ratio: float = 1.0
	var worst_floor: int = 0
	for f2 in by_floor.keys():
		var vals: Array = by_floor[f2]
		var lo: int = vals[0]
		var hi: int = vals[0]
		for v in vals:
			lo = mini(lo, int(v))
			hi = maxi(hi, int(v))
		var ratio: float = float(hi) / float(maxi(lo, 1))
		if ratio > worst_ratio:
			worst_ratio = ratio
			worst_floor = int(f2)
	# ⚠ "floor 0" IS NOT A FLOOR. When every ratio is 1.00 nothing ever beat the
	# initial `worst_ratio`, so `worst_floor` is still its sentinel — and a harness
	# that prints a floor number it never found is a harness quietly lying about what
	# it measured. Say "none" instead.
	if worst_floor <= 0:
		print("   body-count spread: 1.00x on every floor — no seed changes how much fight a floor is.")
	else:
		print("   widest body-count spread: floor %d at %.2fx (min:max across seeds)"
			% [worst_floor, worst_ratio])
	print("   ⚠ FloorGen._reshape conserves each floor's SUM, so this should be 1.00x.")
	print("      Anything above it means a floor's total body count is seed-dependent,")
	print("      which would make 'floor 30' a different promise on two machines.")


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"--to": _to = clampi(int(kv[1]), 2, 400)
			"--seeds": _seeds = clampi(int(kv[1]), 1, 30)
			"--seed": _seed = maxi(int(kv[1]), 1)
