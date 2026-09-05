# Run: godot --headless --path godot-project --script tools/slice_test_class_identity.gd
#
# THE ANTI-RECOLOUR INVARIANT, ASSERTED DIRECTLY.
#
# The maker's ruling, verbatim: "We cannot have any recolours — I want all the
# classes to be different and unique and not similar at all."
#
# That was being violated at a scale you could count. Before the signature pass:
#   * FIVE of nine classes carried a `SpellDef.Kind.BEAM` — `ordinary_spell`,
#     `frostpiercer`, `infernal_lance`, `umbral_lance`, `tempest` — all of them one
#     `BeamSpell` corridor in five tints.
#   * FOUR ults were the same `MeteorSigil.rain()` call.
#   * `blizzard` sat in THREE carried hands and `drain_tether` in three.
# Nine class cards, roughly four things to actually look at.
#
# Every one of those was a comment-level claim that nothing checked. Kit tables drift
# — this repo has the scar tissue: `ClassInfo` once advertised three beams that were
# in nobody's kit at all. So the rule is mechanical now, and it is TWO rules because
# either one alone is cheatable:
#
#   1. NO TWO CLASSES SHARE A CARRIED SPELL ID. The weaker half. Satisfiable by
#      renaming — two ids, one spectacle, identical on screen.
#   2. NO TWO CLASSES' CARRIED HANDS SHARE A SPECTACLE SCRIPT. The half that means
#      "different and not similar at all", because the spectacle IS what the player
#      sees. Resolved through `SpellCaster.spectacle_path`, which mirrors the two
#      forks the dispatcher really takes (ZONE -> ShadowRoot on effect=="shadow",
#      METEOR -> IceSpikeLine on effect=="frost"). Without those forks the Arcanist's
#      Meteor Sigil and the Cryomancer's Glacial Spine both read as `MeteorSigil.gd`
#      and this test would fail on a pair that is genuinely distinct on screen.
#
# ── CONFIRMED TO FAIL ON THE OLD TABLE ─────────────────────────────────────────
# A test nobody has seen fail is a test nobody has seen. Run against the pre-change
# kits this suite reports FIVE id collisions and SIX spectacle collisions:
#     blizzard        carried by Arcanist, Cryomancer, Stormcaller
#     drain_tether    carried by Juggernaut, Cleric
#     blink_strike    carried by Shadowblade, Swordsaint
#     blade_flurry    carried by Shadowblade, Swordsaint
#     rock_wall       carried by Brawler, Swordsaint
#   ...plus BeamSpell.gd across five classes and ZoneSpell.gd across three.
# `_test_the_old_table_would_have_failed` re-runs that check against a frozen copy of
# the old hands, INSIDE this suite, so the proof travels with the test instead of
# living in a commit message.
#
# ── Vacuous-pass armour (the full write-up lives in tools/slice_test_loadout.gd) ─
# `failed += _test_x()` IS BANNED. A dead property read is not a test failure in
# GDScript: it logs a runtime error, ABORTS the enclosing function and hands the
# caller back the return type's zero, which under that idiom reads as "zero
# failures". It silently disabled 64 suites once. So failures accumulate on the
# MEMBER `_fails`, and every test's last line records that it reached the end — a
# test that aborts part-way is missing from `_completed` and fails BY ABSENCE.
extends SceneTree

const TESTS: Array[String] = [
	"carried_ids_are_unique",
	"carried_spectacles_are_unique",
	"the_old_table_would_have_failed",
	"every_carried_spell_has_a_spectacle",
	"spectacle_paths_are_warmed",
	"signatures_are_carried_and_declared",
	"warlock_opens_the_floor_with_a_thrall",
	"every_spell_a_class_can_carry_has_a_blurb",
	"the_blurbs_are_short_enough_to_draw",
	"the_class_card_names_the_hand_it_really_holds",
]

## The description table. Reached by `preload` (it has no `class_name`), which hands
## back the SCRIPT OBJECT -- so only `static func` entry points on it are callable, and
## calling them from here is itself the check that they really are static. A plain
## `func` there fails at RUNTIME, not at parse time, which is why it is exercised by a
## suite rather than trusted to review.
const SpellBlurbs := preload("res://scripts/combat/SpellBlurbs.gd")

const ARENA_PATH: String = "res://scripts/combat/Arena.gd"
const RAISE_PATH: String = "res://scripts/combat/RaiseThrall.gd"

## THE HANDS AS THEY WERE, before the anti-recolour pass — the fixture that proves
## this suite can go red. Frozen literals on purpose: the whole point is that they no
## longer exist anywhere else, so there is nothing to derive them from.
const OLD_HANDS: Array[Array] = [
	["ordinary_spell", "blizzard", "meteor_sigil"],       # 0 Arcanist
	["blade_flurry", "blink_strike", "umbral_lance"],     # 1 Shadowblade
	["thunderclap", "rock_wall", "infernal_lance"],       # 2 Brawler
	["boulder_hurl", "drain_tether", "colossus_pillar"],  # 3 Juggernaut
	["rune_orbs", "drain_tether", "heavens_verdict"],     # 4 Cleric
	["frostpiercer", "blizzard", "frozen_comet"],         # 5 Cryomancer
	["chain_lightning", "blizzard", "tempest"],           # 6 Stormcaller
	["drain_tether", "void_zone", "void_barrage"],        # 7 Warlock
	["blade_flurry", "blink_strike", "horizon_cut"],      # 8 Swordsaint
]

## The eleven spectacles built for this pass, and the class each one belongs to.
## Named rather than derived so that quietly dropping one from the table is a
## failure: a derived list would simply stop asking about whatever went missing.
const SIGNATURES: Dictionary = {
	"thousand_cuts": 1, "shockwave_stomp": 2, "meteor_fist": 2, "fault_line": 3,
	"radiant_volley": 4, "shatter": 5, "heavens_wrath": 6, "raise_thrall": 7,
	"grave_tide": 7, "iai_slash": 8, "crescent_step": 8,
}

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_carried_ids_are_unique()
	_test_carried_spectacles_are_unique()
	_test_the_old_table_would_have_failed()
	_test_every_carried_spell_has_a_spectacle()
	_test_spectacle_paths_are_warmed()
	_test_signatures_are_carried_and_declared()
	_test_warlock_opens_the_floor_with_a_thrall()
	_test_every_spell_a_class_can_carry_has_a_blurb()
	_test_the_blurbs_are_short_enough_to_draw()
	_test_the_class_card_names_the_hand_it_really_holds()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Class identity tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Class identity tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ══════════════════════════════════════════════════════════ 1. ids are unique
## RULE 1. Every one of the 27 carried slots holds a spell no other class holds.
func _test_carried_ids_are_unique() -> void:
	var owner_of: Dictionary = {}
	var carried_total: int = 0
	for cls: int in range(ClassInfo.count()):
		for s: SpellDef in SpellLibrary.build_for_class(cls):
			carried_total += 1
			var prev: Variant = owner_of.get(s.id)
			_expect(prev == null,
				"'%s' is carried by %s AND by %s — the classes are recolours of each other"
					% [s.id, ClassInfo.name_for(int(prev if prev != null else cls)),
						ClassInfo.name_for(cls)])
			if prev == null:
				owner_of[s.id] = cls
	# An invariant that is trivially true of an empty result is not an invariant: if
	# `build_for_class` ever returned nothing the loop above would pass in silence.
	_expect(carried_total == ClassInfo.count() * SpellTier.SLOT_COUNT,
		"every class really handed over %d carried spells (%d of an expected %d)"
			% [SpellTier.SLOT_COUNT, carried_total,
				ClassInfo.count() * SpellTier.SLOT_COUNT])
	_expect(owner_of.size() == carried_total,
		"all %d carried slots hold distinct spells (got %d distinct)"
			% [carried_total, owner_of.size()])
	_completes("carried_ids_are_unique")


# ═══════════════════════════════════════════════════ 2. spectacles are unique
## RULE 2, and the one that actually means "not similar at all". Two ids pointing at
## one script are one spell wearing two names, which is exactly the recolour the
## maker ruled against.
func _test_carried_spectacles_are_unique() -> void:
	var owner_of: Dictionary = {}
	var resolved: int = 0
	for cls: int in range(ClassInfo.count()):
		for s: SpellDef in SpellLibrary.build_for_class(cls):
			var path: String = SpellCaster.spectacle_path(s)
			if path == "":
				continue   # reported by _test_every_carried_spell_has_a_spectacle
			resolved += 1
			var prev: Variant = owner_of.get(path)
			_expect(prev == null,
				"%s is thrown by %s AND by %s ('%s') — same spectacle, two classes"
					% [path.get_file(),
						ClassInfo.name_for(int(prev if prev != null else cls)),
						ClassInfo.name_for(cls), s.id])
			if prev == null:
				owner_of[path] = cls
	_expect(resolved == ClassInfo.count() * SpellTier.SLOT_COUNT,
		"every carried spell resolved to a spectacle (%d of %d)"
			% [resolved, ClassInfo.count() * SpellTier.SLOT_COUNT])
	_expect(owner_of.size() == resolved,
		"all %d carried spells draw distinct spectacles (got %d distinct)"
			% [resolved, owner_of.size()])
	_completes("carried_spectacles_are_unique")


# ═════════════════════════════════════════ 3. the proof that it can go red
## THE FIXTURE RUN. The same two checks, against `OLD_HANDS` — the kits as they were
## before the signature pass. It must find collisions, or the two tests above are
## proving nothing and would pass on the very table they were written to reject.
func _test_the_old_table_would_have_failed() -> void:
	var id_owner: Dictionary = {}
	var path_owner: Dictionary = {}
	var id_clashes: int = 0
	var path_clashes: int = 0
	for cls: int in range(OLD_HANDS.size()):
		for id: String in OLD_HANDS[cls]:
			var s: SpellDef = SpellLibrary.by_id(id)
			_expect(s != null, "the old-table fixture id '%s' still resolves" % id)
			if s == null:
				continue
			if id_owner.has(id):
				id_clashes += 1
			else:
				id_owner[id] = cls
			var path: String = SpellCaster.spectacle_path(s)
			if path == "":
				continue
			if path_owner.has(path):
				path_clashes += 1
			else:
				path_owner[path] = cls
	_expect(id_clashes >= 5,
		"the OLD kit table shares at least 5 carried ids across classes (found %d) — "
			% id_clashes + "if this drops to 0 the uniqueness tests above are vacuous")
	_expect(path_clashes >= 6,
		"the OLD kit table shares at least 6 carried spectacles across classes (found %d)"
			% path_clashes)
	# ...and the new table finds NONE, stated here beside the old one so the contrast
	# is the assertion rather than something a reader has to reconstruct.
	var new_ids: Dictionary = {}
	var new_clashes: int = 0
	for cls2: int in range(ClassInfo.count()):
		for s2: SpellDef in SpellLibrary.build_for_class(cls2):
			if new_ids.has(s2.id):
				new_clashes += 1
			new_ids[s2.id] = true
	_expect(new_clashes == 0,
		"...and the CURRENT table shares none (found %d)" % new_clashes)
	_completes("the_old_table_would_have_failed")


# ══════════════════════════════════ 4. nothing carried is a silent no-op cast
## `SpellCaster._dispatch` returns false for a kind it cannot build and for a HEX /
## CATACLYSM id missing from its registry. That is a SAFE no-op, which is the problem:
## the MP is spent, the cooldown starts, the windup plays, and nothing appears. A
## carried spell that cannot resolve to a script is a dead button.
func _test_every_carried_spell_has_a_spectacle() -> void:
	for cls: int in range(ClassInfo.count()):
		for s: SpellDef in SpellLibrary.build_for_class(cls):
			var path: String = SpellCaster.spectacle_path(s)
			_expect(path != "",
				"%s's '%s' resolves to a spectacle script (an unregistered id casts nothing)"
					% [ClassInfo.name_for(cls), s.id])
			if path == "":
				continue
			_expect(ResourceLoader.exists(path),
				"%s's '%s' points at a script that exists (%s)"
					% [ClassInfo.name_for(cls), s.id, path])
	_completes("every_carried_spell_has_a_spectacle")


# ═══════════════════════════════════════════ 5. the tie between the two tables
## `spectacle_path` is a SECOND statement of the dispatch and can drift from it. This
## is the tie that stops the drift being silent: every path it claims a spell builds
## must also be in `SpellCaster.WARM_PATHS`, the list `warm()` really loads. A new arm
## that updates one and not the other fails here.
##
## It is also the miss that costs real frames. A spectacle absent from WARM_PATHS
## pays its parse-and-compile on the FIRST cast — measured at 44-126 ms on desktop,
## i.e. a visible freeze on the phone this is aimed at — and `frozen_comet` shipped
## exactly that way once, via a nested `load()` its own arm's warm entry did not cover.
func _test_spectacle_paths_are_warmed() -> void:
	var warm: Array[String] = []
	for p: String in SpellCaster.WARM_PATHS:
		warm.append(p)
	_expect(warm.size() > 20, "WARM_PATHS is populated (%d entries)" % warm.size())
	var checked: int = 0
	for s: SpellDef in SpellLibrary.build_all():
		var path: String = SpellCaster.spectacle_path(s)
		if path == "":
			continue
		checked += 1
		_expect(warm.has(path),
			"'%s' builds %s, which is NOT in WARM_PATHS — its first cast pays a "
				% [s.id, path.get_file()] + "44-126 ms compile stall mid-fight")
	_expect(checked >= 30,
		"the warm sweep really examined the library (%d spells resolved)" % checked)
	# RAISE THRALL'S NESTED PAIR, named because a sweep of the eleven new files for
	# `load(` found exactly one offender and a generic loop cannot see inside it: the
	# summon load()s both the thrall script AND its PackedScene from inside the cast.
	for nested: String in ["res://scripts/combat/Thrall.gd",
			"res://scenes/combat/Thrall.tscn"]:
		_expect(warm.has(nested),
			"%s is warmed — RaiseThrall load()s it by path from inside the cast"
				% nested.get_file())
	_completes("spectacle_paths_are_warmed")


# ═══════════════════════════════════════════ 6. the eleven really are equipped
## The eleven bespoke spectacles were built and then wired to NOTHING for a while —
## no SpellDef, no registry entry, no kit — which is a more expensive version of the
## unreachable-spell bug: content that exists, costs review, and cannot be played.
## Each one is asserted to be a real SpellDef, in its class's hand, with a declared
## element (a spell at element -1 makes `resolve_element` guess and makes
## `SpellReactor.register` DROP the effect out of the reaction system entirely).
func _test_signatures_are_carried_and_declared() -> void:
	for id: String in SIGNATURES:
		var cls: int = int(SIGNATURES[id])
		var s: SpellDef = SpellLibrary.by_id(id)
		_expect(s != null, "'%s' is a real SpellDef in the library" % id)
		if s == null:
			continue
		_expect(int(s.kind) == int(SpellDef.Kind.HEX),
			"'%s' is a HEX (the id-forked kind these eleven share)" % id)
		_expect(SpellCaster.HEX_SCRIPTS.has(id),
			"'%s' has a HEX_SCRIPTS entry — without one the cast is a silent no-op" % id)
		_expect(s.element >= 0,
			"'%s' declares a real element (not the -1 default)" % id)
		_expect(s.effect == Elements.effect_name(s.element),
			"'%s': effect '%s' matches its element" % [id, s.effect])
		# The channel routing: a positive cast_time would put a stomp / draw-cut /
		# dash on Hero's LEVITATING channel, which lifts the caster off the floor the
		# spell needs. They go through the summon path and telegraph themselves.
		_expect(is_zero_approx(s.cast_time),
			"'%s' has no levitating channel (cast_time %.2f) — it owns its own tell"
				% [id, s.cast_time])
		var carried: Array[String] = []
		for c: SpellDef in SpellLibrary.build_for_class(cls):
			carried.append(c.id)
		_expect(carried.has(id),
			"%s CARRIES '%s' (hand is %s)" % [ClassInfo.name_for(cls), id, str(carried)])
	_expect(SIGNATURES.size() == 11,
		"all eleven signatures are still being checked (got %d)" % SIGNATURES.size())
	_completes("signatures_are_carried_and_declared")


# ═══════════════════════════════════ 7. the start-of-floor thrall
## "A WARLOCK SHOULD BEGIN A FLOOR WITH ONE THRALL ALREADY UP." The maker's explicit
## ask. `RaiseThrall.raise_opening_thralls` implements it and is deliberately public
## and static so that the ONE line calling it can live in `Arena` — which means the
## whole feature hangs on that one line existing, in a file the spell knows nothing
## about. A hook nobody calls is the quietest possible way to ship nothing.
##
## Checked from both ends: the call site really is in `Arena._setup_floor` (source,
## because instancing an Arena drags the entire combat graph and every autoload into
## a `--script` harness), and the function really stands a body up for a Warlock and
## no-ops for everyone else.
func _test_warlock_opens_the_floor_with_a_thrall() -> void:
	var src: String = FileAccess.get_file_as_string(ARENA_PATH)
	_expect(src != "", "Arena.gd is readable")
	_expect(src.contains("raise_opening_thralls"),
		"Arena calls raise_opening_thralls — without that line the maker's ask ships as nothing")
	# AFTER the floor's own wave, not before: the spell asks the Encounter whether the
	# floor is under MAX_LIVE_ENTITIES, and asking first would hand the Warlock a body
	# the budget never accounted for.
	var run_at: int = src.find("_encounter.run_floor")
	var raise_at: int = src.find("_raise_opening_thralls()")
	_expect(run_at >= 0 and raise_at > run_at,
		"...and it is called AFTER run_floor, so the entity budget already knows about the wave")

	var scr: GDScript = load(RAISE_PATH) as GDScript
	_expect(scr != null, "RaiseThrall.gd loads")
	if scr == null:
		_completes("warlock_opens_the_floor_with_a_thrall")
		return
	# A WARLOCK gets a body; anyone else gets nothing. `_carries` reads the hero's
	# class through `SpellLibrary`, i.e. the same source the hero builds its hand from,
	# so this also proves `raise_thrall` really is in the Warlock's carried hand.
	var arena := Node2D.new()
	root.add_child(arena)
	var warlock: Node2D = _StubHero.new()
	warlock.set(&"_hero_class", 7)
	arena.add_child(warlock)
	warlock.add_to_group("hero")
	_expect(int(scr.call(&"raise_opening_thralls", null)) == 0,
		"a null arena raises nothing rather than crashing")
	_expect(int(scr.call(&"raise_opening_thralls", arena)) == 1,
		"a Warlock standing on a fresh floor gets ONE opening thrall")
	warlock.set(&"_hero_class", 0)   # Arcanist — does not carry the spell
	_expect(int(scr.call(&"raise_opening_thralls", arena)) == 0,
		"...and a class that does not carry Raise Thrall gets none")
	arena.queue_free()
	_completes("warlock_opens_the_floor_with_a_thrall")


## The two members `RaiseThrall._carries` reaches for by name. A bare Node2D answers
## `null` to `get(&"_hero_class")` and would make the Warlock case pass for the wrong
## reason (no thrall, because no class, rather than no thrall because no spell).
class _StubHero:
	extends Node2D
	var _hero_class: int = 7


# ---------------------------------------------------------------------------
# THE DESCRIPTIONS
# ---------------------------------------------------------------------------

## EVERY ID A CLASS CAN ACTUALLY END UP HOLDING.
##
## Not the carried hand -- the whole authored POOL. `SpellLibrary.CLASS_KITS` authors
## five roles per class and `SLOT_ROLES` starts you with four of them; the fifth is the
## reserve, and the Outfitter lets a player swap it in with one tap. So all five are
## reachable, all five are inspectable, and all five need a description.
##
## Derived from the library rather than typed, so a kit re-point is covered the moment
## it lands. `SpellLibrary.reserve_for_class` is deliberately NOT used: it answers what
## is out of the CURRENT hand, which moves as the player chooses, and this wants the
## union.
func _carriable_ids() -> Array[String]:
	var out: Array[String] = []
	for i: int in ClassInfo.count():
		var kit: Dictionary = SpellLibrary.kit_for_class(i)
		for role: Variant in kit.keys():
			var id: String = String(kit[role])
			if id != "" and not out.has(id):
				out.append(id)
	out.sort()
	return out


## ...plus the floor pickups and the boss drops, which a player is HANDED mid-run and
## has to decide about in the same breath. A spell you were just given with no
## description is the same failure as one on a class card with no description.
func _droppable_ids() -> Array[String]:
	var out: Array[String] = []
	for arr: Array in [SpellLibrary.build_tier2(), SpellLibrary.build_tier3()]:
		for s: Variant in arr:
			var d: SpellDef = s as SpellDef
			if d != null and d.id != "" and not out.has(d.id):
				out.append(d.id)
	out.sort()
	return out


## THE COVERAGE CHECK THE MAKER'S ASK NEEDS.
##
## A description table that silently covers 40 of 54 is the same class of failure as
## the rotted `ClassInfo.kit` strings this suite's neighbours are about: the screen
## looks finished and a seventh of the roster reads blank. So the table is diffed
## against the library's OWN id list, both for what a class can carry and for what a
## floor can hand you.
##
## CONFIRMED TO FAIL: deleting the "iai_slash" row from `SpellBlurbs.BLURBS` reports
##   FAIL: 1 spell(s) a class can carry have no description: iai_slash
func _test_every_spell_a_class_can_carry_has_a_blurb() -> void:
	var carriable: Array[String] = _carriable_ids()
	# A zero-length sweep would pass every assertion below by having nothing to check,
	# which is how a coverage test ships covering nothing.
	_expect(carriable.size() >= 30,
		"the sweep found a real kit pool to check (%d ids)" % carriable.size())
	var missing: Array[String] = SpellBlurbs.missing_ids(carriable)
	_expect(missing.is_empty(),
		"%d spell(s) a class can carry have no description: %s"
			% [missing.size(), ", ".join(missing)])

	var drops: Array[String] = _droppable_ids()
	_expect(drops.size() >= 8, "the drop sweep found a real pool (%d ids)" % drops.size())
	var missing_drops: Array[String] = SpellBlurbs.missing_ids(drops)
	_expect(missing_drops.is_empty(),
		"%d spell(s) a floor can hand you have no description: %s"
			% [missing_drops.size(), ", ".join(missing_drops)])

	# And the accessors are really static -- see the note on the `preload` above. Called
	# on the SCRIPT here, exactly as `ClassSelect` and `Outfitter` call them.
	_expect(SpellBlurbs.for_id("iai_slash") != "", "for_id answers on the script object")
	_expect(SpellBlurbs.for_id("no_such_spell_id") == "",
		"...and answers EMPTY for an unknown id rather than inventing a placeholder")
	_expect(not SpellBlurbs.has_blurb("no_such_spell_id"), "has_blurb agrees")
	var built: SpellDef = SpellLibrary.by_id("iai_slash")
	_expect(built != null and SpellBlurbs.for_spell(built) != "",
		"for_spell resolves a built SpellDef")
	_expect(SpellBlurbs.for_spell(null) == "", "...and a null def is a clean empty string")
	_completes("every_spell_a_class_can_carry_has_a_blurb")


## AN OVER-LONG BLURB DOES NOT ERROR -- IT WRAPS.
##
## Both consumers reserve exactly two lines for it (`ClassSelect`'s detail rows and the
## `Outfitter`'s header line), because a reserved height is what makes those screens
## measure the same for every class. A third line does not overflow visibly; it pushes
## the panel it sits in down, and the 360 px budget is 19 px of headroom on the class
## screen. So the ceiling is a test, not an intention.
func _test_the_blurbs_are_short_enough_to_draw() -> void:
	var ids: Array[String] = SpellBlurbs.ids()
	_expect(ids.size() >= 40, "the blurb table is populated (%d entries)" % ids.size())
	var over: Array[String] = SpellBlurbs.overlong_ids()
	_expect(over.is_empty(),
		"%d blurb(s) exceed the %d-character ceiling and would wrap to a third line: %s"
			% [over.size(), SpellBlurbs.MAX_LEN, ", ".join(over)])
	for id: String in ids:
		var text: String = SpellBlurbs.for_id(id)
		# The bar the maker set is "clear what it does", and the shortest honest way to
		# check that mechanically is that the line is a SENTENCE rather than a tagline.
		_expect(text.length() >= 24, "blurb for `%s` is too thin to say anything: %s"
			% [id, text])
	# AND THE LONG FORM NEVER REACHES THESE SCREENS. `SpellDef.description` is populated
	# on all 54 spells and 46 of them are longer than this ceiling -- they are long-form
	# paragraphs, three or four lines each at the size a 30 px row draws at. `for_spell`
	# therefore prefers the TABLE and keeps the def as a fallback only. That order was a
	# bug before it was a decision (it deferred to the def first, on the assumption the
	# field was empty), so it is pinned rather than remembered.
	var long_form: int = 0
	for id2: String in _carriable_ids():
		var built2: SpellDef = SpellLibrary.by_id(id2)
		if built2 == null:
			continue
		if built2.description.length() > SpellBlurbs.MAX_LEN:
			long_form += 1
		_expect(SpellBlurbs.for_spell(built2).length() <= SpellBlurbs.MAX_LEN,
			"`%s` resolves to the SHORT form for a UI row (got %d chars)"
				% [id2, SpellBlurbs.for_spell(built2).length()])
	_expect(long_form > 0,
		"the fixture is real: at least one carriable spell has a long-form description "
		+ "that this ordering has to be keeping off a 30 px row (found %d)" % long_form)
	_completes("the_blurbs_are_short_enough_to_draw")


## THE ROT THIS FILE'S NEIGHBOUR WAS ALWAYS ABOUT, TURNED INTO AN ASSERTION.
##
## `ClassInfo`'s own header records that its `kit` strings drifted from the real kits
## and advertised three beams that were in NOBODY's kit -- and that it was "caught by
## hand, not by a test". Measured again during this pass: ALL NINE strings named only
## THREE spells while the hand has held FOUR since `SpellTier.SLOT_COUNT` became 4.
## Both drifts are the same bug, which is that a string cannot be wrong, only stale.
##
## So both directions are pinned:
##   * every spell the class REALLY carries is named on the card -- an omission is how
##     the fourth slot went unadvertised on nine cards for months;
##   * no spell the class does NOT carry is named on it -- an addition is how the card
##     advertised beams nobody held, which is the failure that reached a player.
##
## CONFIRMED TO FAIL: putting "Blizzard" back into the Brawler's row reports
##   FAIL: the Brawler's card names Blizzard, which that class does NOT carry
func _test_the_class_card_names_the_hand_it_really_holds() -> void:
	# Every display name in the game, so "named on the card" can be checked against a
	# closed set rather than against a guess.
	var all_names: Array[String] = []
	for s: Variant in SpellLibrary.build_all():
		var d: SpellDef = s as SpellDef
		if d != null and not all_names.has(String(d.display_name)):
			all_names.append(String(d.display_name))
	_expect(all_names.size() >= 30, "there is a real name set to check against (%d)"
		% all_names.size())
	for i: int in ClassInfo.count():
		var card: String = String((ClassInfo.CLASSES[i] as Dictionary).get("kit", ""))
		var cls: String = ClassInfo.name_for(i)
		_expect(card != "", "%s has a kit line at all" % cls)
		var held: Array[String] = []
		for s2: Variant in SpellLibrary.build_for_class(i):
			var d2: SpellDef = s2 as SpellDef
			if d2 != null:
				held.append(String(d2.display_name))
		for spell_name: String in held:
			_expect(card.contains(spell_name),
				"the %s card must name %s, which that class actually carries (card: %s)"
					% [cls, spell_name, card])
		for other: String in all_names:
			if held.has(other):
				continue
			# Substring, so a name that is a substring of a CARRIED one is not a false
			# positive: "Judgment" sits inside "Judgment - Divine Ray", and the Cleric
			# carries the latter, so this guard skips it.
			var swallowed: bool = false
			for h: String in held:
				if h.contains(other):
					swallowed = true
					break
			if swallowed:
				continue
			_expect(not card.contains(other),
				"the %s card names %s, which that class does NOT carry (card: %s)"
					% [cls, other, card])
		# And the DERIVED line agrees with the authored one about which spells exist.
		# `ClassInfo.kit_for` is what `ClassSelect` actually draws, so a disagreement
		# here is the screen and the string having different opinions about the game.
		var derived: String = ClassInfo.kit_for(i)
		for third: String in held:
			_expect(derived.contains(third),
				"the DERIVED %s line names %s (derived: %s)" % [cls, third, derived])
	_completes("the_class_card_names_the_hand_it_really_holds")
