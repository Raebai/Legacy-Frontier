# Run: godot --headless --path godot-project --script tools/slice_test_ult_punctuation.gd
#
# EVERY ULTIMATE MUST END ON A MARK, AND NOT ALL ON THE SAME ONE.
#
# Two of the nine class ultimates ended on nothing at all. Heaven's Wrath (Stormcaller)
# and Fault Line (Juggernaut) both called `Juice.epic_moment`, which spends the camera
# pull, the punch, the shake and the shock ripple — and which takes a `frame` flag
# neither of them ever passed. So the single loudest punctuation mark in the game
# skipped two classes' identity moments, and nothing noticed, because "no frame" is
# indistinguishable from "a frame the arbiter declined" unless you go looking.
#
# A third, Grave Tide (Warlock), fired the LEGACY `Juice.impact_frame` — the pre-Style
# white blow-out — once per victim caught. So the Warlock's ultimate ended on the same
# screen as every ordinary heavy attack in the game.
#
# ⚠ RULE 2 IS THE ONE WITH TEETH, AND IT IS NOT "DO THEY HAVE A FRAME". Read
# ImpactFrame's own header: StarConvergence, EnergyNova and HollowPurple each DELETED
# their impact frame, and the recorded reason was that every ult ended in the same
# white speed-line wash, "so the most identity-bearing moment of each spell was the
# moment they were most identical". A suite that only checked for presence would have
# been fully green while that was true. So this also asserts the marks are SPREAD.
#
# ⚠ THE TABLE BELOW IS HAND-MAINTAINED AND RULE 3 IS WHY THAT IS SAFE. Ult id -> script
# cannot be resolved statically: some ults reach their spectacle through
# `SpellCaster.HEX_SCRIPTS` (a real registry, read here), and the rest through a `Kind`
# arm in a `match` that only exists at runtime. Rule 3 asserts the table covers every
# ult named in `CLASS_KITS`, so changing a class's ultimate fails this suite until the
# table is updated rather than silently dropping that class out of coverage.
#
# ⚠ NEVER `failed += _test_x()`. A dead property read aborts the enclosing function and
# hands back the return type's zero, which reads as "no failures". Failures accumulate
# on the MEMBER `_fails`, and every test records a COMPLETION SENTINEL.
extends SceneTree

const LIBRARY_PATH: String = "res://scripts/combat/SpellLibrary.gd"
const CASTER_PATH: String = "res://scripts/combat/SpellCaster.gd"

## Ult id -> the script that draws its payoff. Kept beside the reason it is manual.
const ULT_SCRIPTS: Dictionary = {
	"meteor_sigil": "res://scripts/combat/MeteorSigil.gd",      # Arcanist   (Kind.METEOR)
	"thousand_cuts": "res://scripts/combat/ThousandCuts.gd",    # Shadowblade (HEX)
	"meteor_fist": "res://scripts/combat/MeteorFist.gd",        # Brawler     (HEX)
	"fault_line": "res://scripts/combat/FaultLine.gd",          # Juggernaut  (HEX)
	"heavens_verdict": "res://scripts/combat/StarConvergence.gd",  # Cleric (Kind.CONVERGENCE)
	"frozen_comet": "res://scripts/combat/IceSpikeLine.gd",     # Cryomancer (METEOR frost fork)
	"heavens_wrath": "res://scripts/combat/HeavensWrath.gd",    # Stormcaller (HEX)
	"grave_tide": "res://scripts/combat/GraveTide.gd",          # Warlock     (HEX)
	"horizon_cut": "res://scripts/combat/HorizonArc.gd",        # Swordsaint  (Kind.ARC)
}

## Nine classes, nine ultimates. A scan that finds three has broken, not shrunk.
const MIN_ULTS: int = 9

## The marks a payoff may end on. `impact_frame` is the LEGACY white blow-out and is
## deliberately NOT in this list — a new ult reaching for it should have to justify
## ending on the same screen as every heavy attack.
## ⚠ `call("frame"` IS NOT A TYPO. `HorizonArc` reaches Juice through a node lookup
## instead of the global — its own header says so at :513 — so a list that only knew
## the `Juice.` spelling reported the Swordsaint's ultimate as having no mark at all.
const FRAME_CALLS: Array[String] = [
	"Juice.tier_frame", "Juice.frame(", "\"frame\": true", "call(\"frame\"",
]

## Ults whose payoff is COMPOSED rather than drawn in place: the named script spawns
## another that owns the detonation, and the frame lives there. MeteorFist documents
## exactly this ("The whole payoff is delegated: BlastSpell for the shockwave"), and
## checking only the named script reported the Brawler's ultimate as unmarked.
const DELEGATES: Dictionary = {
	"meteor_fist": "res://scripts/combat/BlastSpell.gd",
}

const TESTS: Array[String] = [
	"every_ult_ends_on_a_mark",
	"the_marks_are_spread",
	"the_table_covers_every_class_ult",
	"no_ult_uses_the_legacy_white_blowout",
	"gravity_flip_is_announced_without_becoming_an_ult",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _src_cache: Dictionary = {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_every_ult_ends_on_a_mark()
	_test_the_marks_are_spread()
	_test_the_table_covers_every_class_ult()
	_test_no_ult_uses_the_legacy_white_blowout()
	_test_gravity_flip_is_announced_without_becoming_an_ult()
	for name: String in TESTS:
		if not _completed.has(name):
			_fails += 1
			printerr("ult_punctuation: TEST DID NOT COMPLETE — %s (it aborted part-way)" % name)
	if _fails == 0:
		print("ult punctuation tests: all PASS")
	else:
		printerr("ult punctuation tests: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
		printerr("ult_punctuation: FAIL — %s" % what)


## ⚠ COMMENT LINES ARE STRIPPED, AND THAT IS LOAD-BEARING. The first run of this suite
## failed Grave Tide for calling `Juice.impact_frame` — matching the text inside the
## comment that explains it no longer does. A scanner that reads prose as code will
## keep finding whatever a comment happens to mention, and the comments in this repo
## name the thing they replaced on purpose.
##
## Only whole-line comments are dropped, which is the honest limit of a text scan: a
## trailing `# ... Juice.impact_frame(...)` on a live line would still match. Nothing
## in the tree does that today, and the alternative is parsing GDScript.
func _src(path: String) -> String:
	if _src_cache.has(path):
		return String(_src_cache[path])
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var raw: String = "" if f == null else f.get_as_text()
	if f != null:
		f.close()
	var kept: PackedStringArray = PackedStringArray()
	for line: String in raw.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	var text: String = "\n".join(kept)
	_src_cache[path] = text
	return text


## The source that decides whether an ult is marked: its own, plus its delegate's.
func _payoff_src(id: String) -> String:
	var text: String = _src(String(ULT_SCRIPTS[id]))
	if DELEGATES.has(id):
		text += "\n" + _src(String(DELEGATES[id]))
	return text


## The ult id of every class kit, straight out of the library.
func _class_ults() -> Array[String]:
	var lib: GDScript = load(LIBRARY_PATH) as GDScript
	if lib == null:
		return []
	var kits: Array = lib.get_script_constant_map().get("CLASS_KITS", []) as Array
	var out: Array[String] = []
	for row: Variant in kits:
		var d: Dictionary = row as Dictionary
		if d != null and d.has("ult"):
			out.append(String(d["ult"]))
	return out


# --------------------------------------------------------------------------- 1
func _test_every_ult_ends_on_a_mark() -> void:
	for id: String in ULT_SCRIPTS.keys():
		var path: String = String(ULT_SCRIPTS[id])
		var src: String = _payoff_src(id)
		_expect(not src.is_empty(), "could not read %s (ult '%s')" % [path, id])
		if src.is_empty():
			continue
		var found: bool = false
		for call: String in FRAME_CALLS:
			if src.contains(call):
				found = true
				break
		_expect(found,
			"ult '%s' (%s) fires NO impact frame. `epic_moment` spends the camera and "
				% [id, path.get_file()]
			+ "the freeze but takes a `frame` flag — passing it, or calling "
			+ "`Juice.tier_frame` at the payoff, is what makes an ultimate land.")
	_completed["every_ult_ends_on_a_mark"] = true


# --------------------------------------------------------------------------- 2
## Presence is not enough — see the ⚠ block at the top. Count the DISTINCT styles the
## nine payoffs name. All nine agreeing is the exact failure ImpactFrame was rebuilt
## to end, and it would sail through rule 1.
func _test_the_marks_are_spread() -> void:
	var styles: Dictionary = {}
	for id: String in ULT_SCRIPTS.keys():
		var src: String = _payoff_src(id)
		if src.is_empty():
			continue
		for style: String in ["BLOWOUT", "SILHOUETTE", "COLOR_FIELD", "INVERT",
				"CUT_IN", "LOCAL"]:
			if src.contains("Style.%s" % style):
				styles[style] = int(styles.get(style, 0)) + 1
		# A payoff that overrides no style takes the ladder's own choice, which for an
		# ULT carrying an element is COLOR_FIELD. That counts as a distinct mark.
		if src.contains("Juice.tier_frame") and not src.contains("\"style\""):
			styles["COLOR_FIELD(ladder)"] = int(styles.get("COLOR_FIELD(ladder)", 0)) + 1
	_expect(styles.size() >= 3,
		"the nine ultimates name only %d distinct impact-frame styles. Every ult "
			% styles.size()
		+ "ending on one mark is the failure ImpactFrame's vocabulary exists to "
		+ "prevent — read its header before relaxing this.")
	_completed["the_marks_are_spread"] = true


# --------------------------------------------------------------------------- 3
## THE COVERAGE GUARD that makes the hand-maintained table safe. Also proves the HEX
## registry still resolves the ids it is supposed to, so a moved script is caught.
func _test_the_table_covers_every_class_ult() -> void:
	var ults: Array[String] = _class_ults()
	_expect(ults.size() >= MIN_ULTS,
		"CLASS_KITS returned %d ults, expected at least %d — the scan has broken "
			% [ults.size(), MIN_ULTS] + "rather than the roster having shrunk")
	for id: String in ults:
		_expect(ULT_SCRIPTS.has(id),
			"class ult '%s' is not in this suite's ULT_SCRIPTS table, so it is NOT "
				% id
			+ "being checked. Add it (see the note at the top on why the table is "
			+ "manual) rather than deleting this assertion.")
	# And every path in the table must exist — a rename would otherwise read as a pass.
	var caster: GDScript = load(CASTER_PATH) as GDScript
	if caster != null:
		var hex: Dictionary = caster.get_script_constant_map().get("HEX_SCRIPTS", {})
		for id: String in ULT_SCRIPTS.keys():
			if hex.has(id):
				_expect(String(hex[id]) == String(ULT_SCRIPTS[id]),
					"ult '%s' resolves to %s in SpellCaster.HEX_SCRIPTS but this suite "
						% [id, String(hex[id])]
					+ "checks %s — the table has gone stale" % String(ULT_SCRIPTS[id]))
	for id: String in ULT_SCRIPTS.keys():
		_expect(FileAccess.file_exists(String(ULT_SCRIPTS[id])),
			"ult '%s' points at %s, which does not exist" % [id, String(ULT_SCRIPTS[id])])
	_completed["the_table_covers_every_class_ult"] = true


# --------------------------------------------------------------------------- 4
## `Juice.impact_frame` is the legacy pre-Style entry point and always paints the white
## blow-out. Its own docstring says new call sites should prefer `tier_frame`. Grave
## Tide used it, once per victim caught, and ended the Warlock's ultimate on the same
## screen as an ordinary heavy hit.
func _test_no_ult_uses_the_legacy_white_blowout() -> void:
	for id: String in ULT_SCRIPTS.keys():
		var src: String = _payoff_src(id)
		if src.is_empty():
			continue
		_expect(not src.contains("Juice.impact_frame("),
			"ult '%s' calls the LEGACY `Juice.impact_frame`, which is always the white "
				% id
			+ "blow-out — the same mark every heavy attack ends on. Use "
			+ "`Juice.tier_frame` so it lands on the ladder and can carry its own style.")
	_completed["no_ult_uses_the_legacy_white_blowout"] = true


## THE BANNER WITHOUT THE TIER. Maker: *"GravityFlip needs the big ult banner"*.
##
## Gravity Flip inverts gravity for the whole arena for five seconds from the
## JUGGERNAUT'S CONTROL SLOT, and it was announcing itself with the small
## name-over-the-head label. It misses `SpellTier.Tier.ULT` by 0.2 s of cooldown and
## 8 MP — so the tempting fix is to nudge those numbers, and that fix is a trap: the
## tier also drives reaction weight, the `PUSH_TIER` shove multiplier, the hotbar
## badge and `slot_accepts_ult`, whose rule is that an ult may not sit in a non-ult
## slot. This asserts BOTH halves: it gets the banner, and its tier did not move.
func _test_gravity_flip_is_announced_without_becoming_an_ult() -> void:
	var spell: SpellDef = SpellLibrary.by_id("gravity_flip")
	_expect(spell != null, "gravity_flip is still in the library")
	if spell == null:
		return
	_expect(spell.announce_as_ult, "gravity_flip asks for the big banner")
	# The trap: buying the banner with stats instead of the flag.
	_expect(SpellTier.of(spell) != SpellTier.Tier.ULT,
		"...and is STILL NOT tier ULT — the flag is presentation, not promotion")
	# It sits in a control slot, and that has to stay legal.
	var kit: Dictionary = SpellLibrary.CLASS_KITS[3]   # Juggernaut
	_expect(String(kit.get("control", "")) == "gravity_flip",
		"gravity_flip is still the Juggernaut's CONTROL slot")
	_expect(String(kit.get("ult", "")) != "gravity_flip",
		"...and has not quietly become anybody's ult")

	# The flag is opt-in: nothing else in the catalog picked it up by default.
	var flagged: Array[String] = []
	for sp: SpellDef in SpellLibrary.build_all():
		if sp != null and sp.announce_as_ult and SpellTier.of(sp) != SpellTier.Tier.ULT:
			flagged.append(sp.id)
	_expect(flagged.size() == 1 and flagged[0] == "gravity_flip",
		"gravity_flip is the ONLY non-ult wearing the banner flag (got %s)" % [flagged])
	_completed["gravity_flip_is_announced_without_becoming_an_ult"] = true
