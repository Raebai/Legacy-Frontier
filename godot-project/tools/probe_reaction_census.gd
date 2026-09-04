# WHICH REACTIONS CAN A REAL FIGHT EVEN REACH — the STATIC half of the audit.
#
# `tools/probe_reaction_count.gd` is the dynamic half: it runs real bot bouts and
# counts what actually fires. This one answers the question that has to come FIRST,
# because it decides how to read a zero: *a reaction between two spells no two
# classes can both bring is dead by construction, and no amount of fighting will
# ever make it fire.*
#
# It reports three things, all measured off the shipped data rather than asserted:
#
#   1. THE HAND. Every class's four carried spells, resolved all the way down to
#      what the reactor will actually see — the spectacle script the cast builds,
#      whether that script REGISTERS at all, and the (form, element, weight) triple
#      it registers with. A spell whose spectacle never registers cannot react with
#      anything, however good the row is.
#   2. THE REACHABLE SET. Every unordered pair of those triples, run through
#      `ReactionTable.match_rule` for both `same` (one caster combining their own
#      two spells) and `different` (a 1v1 duel, which is the mode the maker
#      watches) owners. Reported per outcome with a worked example.
#   3. THE DEAD LIST. Every authored outcome key that NO pair can reach, with the
#      reason inferred from the row: an element nobody carries, a form nobody
#      registers, a weight combination the kits cannot produce.
#
# ⚠ HEAD-ON IS DELIBERATELY ASSUMED TRUE HERE. `require_head_on` is a property of a
# MOMENT, not of a loadout, so a static reachability pass cannot answer it and
# pretending otherwise would report `bolt_fizzle` dead when it is merely rare. Rows
# that need it are marked in the output; the dynamic count is the authority on them.
#
#   Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project \
#       --script tools/probe_reaction_census.gd
#
# ⚠ NAMES NO SPECTACLE BY class_name. A `--script` tool is compiled before the
# autoloads exist and every spectacle reaches `Sfx`, so naming one kills the whole
# file with "Identifier not found: Sfx". Registration forms are read out of the
# spectacle SOURCE instead, which is also the honest thing to read: the register()
# call site is what the reactor sees, not the `reaction_form()` accessor beside it.
extends SceneTree

const CLASS_NAMES: Array[String] = [
	"ARCANIST", "SHADOWBLADE", "BRAWLER", "JUGGERNAUT", "CLERIC",
	"CRYOMANCER", "STORMCALLER", "WARLOCK", "SWORDSAINT",
]

const FORM_NAMES: Array[String] = ["BEAM", "BARRIER", "FIELD", "PROJECTILE", "IMPACT", "AURA"]
const WEIGHT_NAMES: Array[String] = ["QUICK", "HEAVY", "ULT"]

## The basic cast every class throws all fight, which is NOT in any kit table and is
## the highest-traffic reactant in the game. `Spell.gd` registers it as a PROJECTILE
## carrying the hero's own element; `SpellCaster` stamps it QUICK.
## Included by hand because it is invisible to `build_for_class` and leaving it out
## would under-report the busiest form in the census by a wide margin.
const BASIC_BOLT_FORM: int = 3   # ReactionTable.Form.PROJECTILE
const BASIC_BOLT_WEIGHT: int = 0 # SpellTier.Tier.QUICK
## ...and the Q blast, which registers through `BlastSpell` as an IMPACT of the same
## element. Also invisible to `build_for_class`, and it is the ONLY shape several
## elements ever take.
const BASIC_BLAST_FORM: int = 4  # ReactionTable.Form.IMPACT

var _reactants: Array[Dictionary] = []


func _initialize() -> void:
	_report_hands()
	_report_reachable()
	_report_silent()
	quit(0)


# ------------------------------------------------------------- silent pairs

## THE ACTIONABLE LIST: pairs of effects that are BOTH in the reaction system, can
## both be on the floor of one 1v1, and meet to no rule at all. Every row here is a
## place where the player does something deliberate and the game says nothing.
##
## Collapsed to (form, element) x (form, element) rather than listed per spell —
## the table is keyed on exactly that pair, so two spells with the same descriptor
## are the same silence twice.
func _report_silent() -> void:
	print("=== SILENT PAIRS — both registered, both reachable in one duel, no rule ===")
	var seen: Dictionary = {}
	var rows: Array[String] = []
	for i: int in _reactants.size():
		for j: int in range(i, _reactants.size()):
			var a: Dictionary = _reactants[i]
			var b: Dictionary = _reactants[j]
			var ka: String = "%d:%d" % [int(a["form"]), int(a["element"])]
			var kb: String = "%d:%d" % [int(b["form"]), int(b["element"])]
			var key: String = ka + "|" + kb if ka <= kb else kb + "|" + ka
			if seen.has(key):
				continue
			var rule: Dictionary = ReactionTable.match_rule(
				int(a["form"]), int(a["element"]), int(b["form"]), int(b["element"]),
				"different", int(a["weight"]), int(b["weight"]),
				Vector2.RIGHT, Vector2.LEFT)
			if not rule.is_empty():
				seen[key] = true
				continue
			seen[key] = true
			rows.append("%-10s %-10s  x  %-10s %-10s    e.g. %s x %s"
				% [FORM_NAMES[int(a["form"])], Elements.display_name(int(a["element"])),
					FORM_NAMES[int(b["form"])], Elements.display_name(int(b["element"])),
					String(a["id"]), String(b["id"])])
	rows.sort()
	for r: String in rows:
		print("  ", r)
	print("  (%d silent descriptor pairs)" % rows.size())


# ------------------------------------------------------------------ the hand

func _report_hands() -> void:
	print("=== THE HAND — what each class actually puts into the reactor ===")
	print("%-13s %-6s %-17s %-11s %-7s %-6s %s"
		% ["class", "slot", "spell", "element", "weight", "form", "spectacle"])
	for c: int in CLASS_NAMES.size():
		var kit: Array = SpellLibrary.build_for_class(c)
		var elem: int = _class_element(c)
		# The basic bolt first — it is slot-less and it is thrown more than the
		# other four put together — and then the Q BLAST, which is the same story:
		# not in any kit table, carried by every class, and it registers as an
		# IMPACT of the class's own element. Leaving it out is what let the first
		# version of this census report `steam_cloud` unreachable when the pair it
		# needs (a FIRE blast, an ICE field) is two classes away from each other.
		_note(CLASS_NAMES[c], "bolt", "basic cast", elem, BASIC_BOLT_WEIGHT,
			BASIC_BOLT_FORM, "Spell.gd")
		_note(CLASS_NAMES[c], "blast", "Q blast", elem, BASIC_BOLT_WEIGHT,
			BASIC_BLAST_FORM, "BlastSpell.gd")
		for i: int in kit.size():
			var s: SpellDef = kit[i] as SpellDef
			if s == null:
				continue
			var path: String = SpellCaster.spectacle_path(s)
			var form: int = _registered_form(path)
			var w: int = SpellTier.of(s)
			_note(CLASS_NAMES[c], "s%d" % i, s.id, s.element, w, form,
				path.get_file() if path != "" else "(no spectacle)")
	print("")


## One row of the hand table, and one entry in the reachable-set population.
## An unregistered spell is PRINTED (that is the finding) but never added to the
## population — it genuinely cannot meet anything.
func _note(cls: String, slot: String, id: String, element: int, weight: int,
		form: int, spectacle: String) -> void:
	var form_txt: String = FORM_NAMES[form] if form >= 0 else "—"
	print("%-13s %-6s %-17s %-11s %-7s %-6s %s"
		% [cls, slot, id, Elements.display_name(element),
			WEIGHT_NAMES[clampi(weight, 0, 2)], form_txt, spectacle])
	if form < 0 or element < 0:
		return
	_reactants.append({
		"cls": cls, "id": id, "form": form, "element": element, "weight": weight,
	})


## The element a class's basic cast AND its Q blast carry — `Hero._element`, set
## from that class's preset row in `Hero.CLASS_PRESETS` and cycled by X.
##
## ⚠ IT IS NOT THE DAMAGE-LINE SPELL'S ELEMENT, and the first version of this probe
## read it there and was WRONG about a whole element. The BRAWLER's damage line is
## `shockwave_stomp` (EARTH) but its class element is FIRE, so this file reported
## FIRE as absent from the reaction system entirely — while a real 36-bout sweep
## measured `IMPACT Fire` registering ELEVEN times, all of them the Brawler's blast.
## A census that infers what a class brings from the wrong field is exactly the
## "confident comment describing something never written" failure this repo has
## been bitten by; the numbers here now come from the table Hero actually reads.
##
## Transcribed rather than reached for: `Hero.CLASS_PRESETS` is a 200-line-per-entry
## dictionary of rig presets, and a `--script` tool that named `Hero` would compile
## the whole hero chain (and its autoloads) at parse time. `tools/probe_reaction_count.gd`
## is the cross-check — it reports what really registered, from real bouts.
const CLASS_ELEMENT: Array[int] = [
	Elements.Element.ARCANE,     # 0 ARCANIST
	Elements.Element.SHADOW,     # 1 SHADOWBLADE
	Elements.Element.FIRE,       # 2 BRAWLER   ⚠ not EARTH — see above
	Elements.Element.EARTH,      # 3 JUGGERNAUT
	Elements.Element.HOLY,       # 4 CLERIC
	Elements.Element.ICE,        # 5 CRYOMANCER
	Elements.Element.LIGHTNING,  # 6 STORMCALLER
	Elements.Element.SHADOW,     # 7 WARLOCK
	Elements.Element.ARCANE,     # 8 SWORDSAINT (plain steel; the X-cycle tints it)
]


func _class_element(class_id: int) -> int:
	if class_id >= 0 and class_id < CLASS_ELEMENT.size():
		return CLASS_ELEMENT[class_id]
	return Elements.Element.ARCANE


## The form a spectacle script REGISTERS with, or -1 for one that never registers.
##
## Read out of the source text on purpose. Two other answers were available and
## both are wrong: `ReactionTable.form_for_kind` is a table the spectacles do not
## consult, and `reaction_form()` is an accessor that a script can declare while
## never calling `register` at all (which is exactly the state a spell has to be
## in for a row about it to be silently dead).
func _registered_form(path: String) -> int:
	if path == "":
		return -1
	var src: String = _read(path)
	if src == "":
		return -1
	var marker: String = "&\"register\""
	var at: int = src.find(marker)
	if at < 0:
		return -1
	var tail: String = src.substr(at, 220)
	for f: int in FORM_NAMES.size():
		if tail.contains("Form." + FORM_NAMES[f]):
			return f
	return -1


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


# -------------------------------------------------------------- reachability

func _report_reachable() -> void:
	print("=== THE REACHABLE SET — every pair of carried effects, both owner relations ===")
	var hits: Dictionary = {}       # outcome -> {count, example, rel, head_on}
	var same_class_only: Dictionary = {}  # outcome -> true while every hit shares a class
	for i: int in _reactants.size():
		for j: int in range(i, _reactants.size()):
			var a: Dictionary = _reactants[i]
			var b: Dictionary = _reactants[j]
			for rel: String in ["same", "different"]:
				# A "same owner" pair must come from ONE hand; a "different owner"
				# pair is two fighters, so any two classes may bring it. i == j is
				# the mirror case and is legal for both.
				if rel == "same" and String(a["cls"]) != String(b["cls"]):
					continue
				var rule: Dictionary = ReactionTable.match_rule(
					int(a["form"]), int(a["element"]), int(b["form"]), int(b["element"]),
					rel, int(a["weight"]), int(b["weight"]),
					# See the ⚠ at the top: head-on is a moment, not a loadout.
					Vector2.RIGHT, Vector2.LEFT)
				if rule.is_empty():
					continue
				var key: String = String(rule["outcome"])
				if not hits.has(key):
					hits[key] = {
						"count": 0,
						"example": "%s %s(%s) x %s %s(%s)  [%s]"
							% [a["cls"], a["id"], Elements.display_name(int(a["element"])),
								b["cls"], b["id"], Elements.display_name(int(b["element"])),
								rel],
						"head_on": bool(rule.get("require_head_on", false)),
					}
					same_class_only[key] = true
				hits[key]["count"] = int(hits[key]["count"]) + 1
				if String(a["cls"]) != String(b["cls"]):
					same_class_only[key] = false
	var authored: Array[String] = _authored_outcomes()
	print("%-22s %-8s %s" % ["outcome", "pairs", "example / why dead"])
	for key: String in authored:
		if hits.has(key):
			var h: Dictionary = hits[key]
			var flags: String = ""
			if bool(h["head_on"]):
				flags += " ⚠needs-head-on"
			if bool(same_class_only.get(key, false)):
				flags += " ⚠same-class-only"
			print("%-22s %-8d %s%s" % [key, int(h["count"]), String(h["example"]), flags])
		else:
			print("%-22s %-8d DEAD — %s" % [key, 0, _why_dead(key)])
	print("")


## Every outcome key the table names, in first-authored order and de-duplicated.
func _authored_outcomes() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in ReactionTable.rules():
		var k: String = String(r["outcome"])
		if k != "none" and not out.has(k):
			out.append(k)
	return out


## Why a key was unreachable, inferred from its rows against the population. Three
## causes are distinguishable and they want different fixes, so they are named
## separately rather than lumped into "no pair matched":
##   FORM      — nobody registers one of the two shapes the row needs.
##   ELEMENT   — the forms exist but no carried spell carries the element.
##   PREDICATE — both sides exist with the right elements, so the row was refused
##               by owner / weight / opposed, which is a TUNING finding.
func _why_dead(key: String) -> String:
	var forms_present: Dictionary = {}
	var pairs_present: Dictionary = {}
	for e: Dictionary in _reactants:
		forms_present[int(e["form"])] = true
		pairs_present["%d:%d" % [int(e["form"]), int(e["element"])]] = true
	var missing_form: String = ""
	var missing_elem: String = ""
	for r: Dictionary in ReactionTable.rules():
		if String(r["outcome"]) != key:
			continue
		for side: String in ["a", "b"]:
			var form: int = int(r["form_" + side])
			if not forms_present.has(form):
				missing_form = FORM_NAMES[form]
				continue
			var allowed: Array = r["elements_" + side]
			if allowed.is_empty():
				continue
			var any: bool = false
			for el: int in allowed:
				if pairs_present.has("%d:%d" % [form, el]):
					any = true
					break
			if not any:
				missing_elem = "%s as %s" % [
					Elements.display_name(int(allowed[0])), FORM_NAMES[form]]
	if missing_form != "":
		return "no carried spell registers as %s" % missing_form
	if missing_elem != "":
		return "no carried spell brings %s" % missing_elem
	return "both sides exist; the row's owner/weight/opposed predicate refused every pair"
