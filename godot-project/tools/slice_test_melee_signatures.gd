# Run: godot --headless --path godot-project --script tools/slice_test_melee_signatures.gd
#   (or, the way this repo runs it: python python-tools/run_all_tests.py --jobs 8 --no-import)
#
# THE FIVE MELEE / IMPACT SIGNATURES — Thousand Cuts, Iai Slash, Crescent Step,
# Shockwave Stomp, Meteor Fist. Built to end the recolour problem: five of nine
# classes were throwing a beam down the same `BeamSpell` corridor and four ults were
# one `MeteorSigil.rain()` in different skins.
#
# The spells are NOT wired into any class kit yet (`SpellLibrary.gd` and
# `ClassInfo.gd` are owned elsewhere), so every case here instantiates the spectacle
# script directly by PATH and stamps it by hand exactly as `SpellCaster._stamp` would.
# `_spell_for` looks each definition up in `SpellLibrary.build_all()` FIRST and only
# falls back to a local copy when the library does not know the id yet — so the day
# the factory blocks are pasted in, this suite silently becomes a test of the real
# ones instead of a test of a copy. Which path was taken is printed.
#
# ══════════════════════════════════════════════════════════════════════════════
# WHY THE PLUMBING IS SHAPED LIKE THIS — the two traps this file is armoured against
# ══════════════════════════════════════════════════════════════════════════════
#  1. `failed += _test_x()` IS BANNED HERE. Reading a member that no longer exists is
#     not a test failure in GDScript: it logs a runtime error, ABORTS the enclosing
#     function on the spot, and hands the caller back the return type's zero — which
#     under that idiom reads as "this test found zero failures". It silently disabled
#     64 suites in this repo once. So failures accumulate on the MEMBER `_fails`, and
#     every test's last line records that it REACHED THE END (`_completes`). A test
#     that aborts half-way therefore fails the suite BY ABSENCE, whatever the cause,
#     with nobody having to predict it in advance.
#  2. AN INVARIANT TRIVIALLY TRUE OF AN EMPTY RESULT IS NOT AN INVARIANT. "nothing
#     out of range was hit" passes perfectly when the spell did nothing at all. Every
#     case below therefore asserts a MINIMUM OCCURRENCE ("at least N cuts actually
#     landed on the marked body") in the same breath as the negative one.
#
# Autoloads are never registered under `--script`, so nothing here — and nothing the
# spectacles reach — may name `Sfx` / `SpellReactor` / `Tuning` as a global. The
# spells go through `SpellDrops.sfx` and `get_node_or_null` for exactly that reason;
# this file just has to not undo it.
extends SceneTree

const CUTS_PATH: String = "res://scripts/combat/ThousandCuts.gd"
const IAI_PATH: String = "res://scripts/combat/IaiSlash.gd"
const STEP_PATH: String = "res://scripts/combat/CrescentStep.gd"
const STOMP_PATH: String = "res://scripts/combat/ShockwaveStomp.gd"
const FIST_PATH: String = "res://scripts/combat/MeteorFist.gd"
## Read for its `BLINK_MIN_TRAVEL` constant only — never instantiated. See
# `_hero_const`.
const HERO_SCRIPT: String = "res://scripts/combat/Hero.gd"

const ALL_PATHS: Array[String] = [CUTS_PATH, IAI_PATH, STEP_PATH, STOMP_PATH, FIST_PATH]

## The five properties `SpellCaster._stamp` writes. `set()` on an undeclared property
## is a SILENT no-op in Godot 4, so a spectacle missing any of these looks perfectly
## healthy on screen and is inert in the reaction system. Listed once, asserted for
# all five scripts.
const STAMP_PROPS: Array[String] = [
	"element_id", "spell_tier", "caster_node", "target_group", "_target_group",
]

## The faction the spells are pointed at in this suite. The real game stamps the
## shared `mortal` group (friendly fire is always on); a distinct name here proves the
## spectacles read the STAMP rather than a hard-coded "enemy".
const HOSTILE: StringName = &"test_hostile"
## A body in NO faction the spell was pointed at. Nothing may ever touch this.
const BYSTANDER: StringName = &"test_bystander"

## Fixed step used to drive `advance()`. Small enough that a travelling front cannot
## skip over a body between two ticks.
const DT: float = 1.0 / 120.0

## Every test that must run to completion. A name missing from `_completed` at the end
## means that test aborted part-way — the failure mode this file is armoured against.
const TESTS: Array[String] = [
	"stamp_contract",
	"no_recolour",
	"tier_shelves",
	"thousand_cuts",
	"iai_slash",
	"crescent_step",
	"shockwave_stomp",
	"meteor_fist",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}
var _arena: Node2D = null


# ─────────────────────────────────────────────────────────────────── the stubs
## A fighter-shaped body. DECLARED properties and real methods, never metadata:
## `set()` on an undeclared property is a silent no-op, and a stub that merely
## pretended to have `hp` would make every assertion pass while measuring nothing.
##
## `take_damage` takes ONE argument (the `Hero` signature) on purpose, so
## `SpellTargets.hurt`'s arity adaptation is exercised rather than bypassed — the
## two-signature bug is the exact class of failure that silently disarms a spell.
class Dummy extends Node2D:
	var hp: int = 1000
	var max_hp: int = 1000
	var velocity: Vector2 = Vector2.ZERO
	var damage_log: Array[int] = []
	var status_log: Array[int] = []
	var knock_log: Array[Vector2] = []

	func take_damage(amount: int) -> void:
		damage_log.append(amount)
		hp = maxi(hp - amount, 0)

	func apply_status(element: int) -> void:
		status_log.append(element)

	func apply_knockback(impulse: Vector2, _flop: bool = true) -> void:
		knock_log.append(impulse)

	func hits() -> int:
		return damage_log.size()

	func total() -> int:
		var t: int = 0
		for d: int in damage_log:
			t += d
		return t


## A caster that opts into being relocated, with the same duck-typed contract
## `Hero.blink_to` publishes. Deliberately teleports RAW (no vetting): there is no
## physics world here, and the point of the stub is to record that the spell asked.
class CasterStub extends Node2D:
	var hp: int = 1000
	var max_hp: int = 1000
	var velocity: Vector2 = Vector2.ZERO
	var damage_log: Array[int] = []
	var blinks: Array[Vector2] = []

	func take_damage(amount: int) -> void:
		damage_log.append(amount)

	func apply_status(_element: int) -> void:
		pass

	func apply_knockback(_impulse: Vector2, _flop: bool = true) -> void:
		pass

	func blink_to(dest: Vector2) -> Vector2:
		blinks.append(dest)
		global_position = dest
		return dest


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_stamp_contract()
	_test_no_recolour()
	_test_tier_shelves()
	_test_thousand_cuts()
	_test_iai_slash()
	_test_crescent_step()
	_test_shockwave_stomp()
	_test_meteor_fist()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Melee signature tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Melee signature tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort survives the abort instead of being discarded with it.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ───────────────────────────────────────────────────────────────── the fixtures
func _fresh_arena() -> Node2D:
	if _arena != null and is_instance_valid(_arena):
		_arena.free()
	_arena = Node2D.new()
	root.add_child(_arena)
	return _arena


func _dummy(at: Vector2, group: StringName = HOSTILE) -> Dummy:
	var d := Dummy.new()
	_arena.add_child(d)
	d.global_position = at
	d.add_to_group(group)
	return d


## A caster placed at `at`. It joins the HOSTILE group DELIBERATELY: under friendly
## fire the thrower really is in the group its own spell scans, and every spectacle
## here must exclude it via `SpellTargets.hostiles(self, ...)`. A caster that takes
## its own damage is the bug this placement exists to catch.
func _caster(at: Vector2) -> CasterStub:
	var c := CasterStub.new()
	_arena.add_child(c)
	c.global_position = at
	c.add_to_group(HOSTILE)
	return c


## Instantiate a spectacle by PATH (never by `class_name`: nothing may depend on the
## global class cache having been rebuilt) and stamp it exactly as
## `SpellCaster._stamp` does — all five properties, both spellings of the group.
func _spawn(path: String, spell: SpellDef, caster: Node) -> Node2D:
	var node: Node2D = (load(path) as GDScript).new()
	_arena.add_child(node)
	node.set(&"element_id", spell.element)
	node.set(&"spell_tier", SpellTier.of(spell))
	node.set(&"caster_node", caster)
	node.set(&"target_group", String(HOSTILE))
	node.set(&"_target_group", String(HOSTILE))
	# Spectacles drive themselves off `_process` in game; here the clock is ours, so
	# the whole timeline is deterministic and frame-rate independent.
	node.set_process(false)
	return node


## Drive `seconds` of spell time in `DT` slices, stopping early if the node frees
## itself. Returns the time actually advanced.
func _run(node: Node2D, seconds: float) -> float:
	var t: float = 0.0
	while t < seconds:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			return t
		node.call(&"advance", DT)
		t += DT
	return t


## A constant off a script that has no `class_name`, read without instantiating it.
## Returns `fallback` and FAILS LOUDLY when the script or the constant is not there,
## so a rename in a file this workstream does not own is reported rather than
## silently papered over with a literal.
func _script_const(path: String, name: String, fallback: float) -> float:
	var gd: GDScript = load(path) as GDScript
	if gd == null:
		_expect(false, "%s could not be loaded to read `%s` (it may be mid-write in "
			% [path, name] + "another workstream — re-run before attributing this here)")
		return fallback
	var consts: Dictionary = gd.get_script_constant_map()
	if not consts.has(name):
		_expect(false, "%s still declares `%s` (it moved or was renamed)" % [path, name])
		return fallback
	return float(consts[name])


## THE SPELL DEFINITION UNDER TEST — the library's if it has landed there, else the
## local copy from the handoff report. Printed either way, so a green run always says
## which of the two it proved.
func _spell_for(id: String, local: SpellDef) -> SpellDef:
	for s: SpellDef in SpellLibrary.build_all():
		if s.id == id:
			print("  [%s] read from SpellLibrary" % id)
			return s
	print("  [%s] not in SpellLibrary yet — using the handoff copy" % id)
	return local


# ───────────────────────────────────────────────── the five SpellDefs (handoff)
# ⚠ THESE MUST STAY EQUIVALENT TO THE FACTORY BLOCKS IN `SpellLibrary`, which is
# where all five now live — they were wired into the kit table by the anti-recolour
# pass, so `_spell_for` reads the LIBRARY and these copies are the dead fallback.
# They are kept (a) so this suite still runs if the ids are ever pulled back out and
# (b) because a stale fallback is a file telling a lie about what it proves: two
# DAMAGE numbers were raised by the DPS-floor pass and are mirrored here. The COSTS
# are untouched, which is what `_test_tier_shelves` pins — the SHELF each lands on,
# which is also its reaction clash weight.
func _def_thousand_cuts() -> SpellDef:
	var s := SpellDef.new()
	s.id = "thousand_cuts"
	s.display_name = "Thousand Cuts"
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 72
	s.cooldown = 8.0
	s.damage = 16
	s.count = 7
	s.reach = 300.0
	return s


func _def_iai_slash() -> SpellDef:
	var s := SpellDef.new()
	s.id = "iai_slash"
	s.display_name = "Iai Slash"
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = "arcane"
	s.mp_cost = 44
	s.cooldown = 5.0
	s.damage = 96
	s.reach = 118.0
	s.width = 52.0
	return s


func _def_crescent_step() -> SpellDef:
	var s := SpellDef.new()
	s.id = "crescent_step"
	s.display_name = "Crescent Step"
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = "arcane"
	s.mp_cost = 40
	s.cooldown = 4.6
	s.damage = 58
	s.reach = 240.0
	s.width = 44.0
	return s


func _def_shockwave_stomp() -> SpellDef:
	var s := SpellDef.new()
	s.id = "shockwave_stomp"
	s.display_name = "Shockwave Stomp"
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = "earth"
	s.mp_cost = 42
	s.cooldown = 4.0
	s.damage = 88   # was 54 — raised by the DPS-floor pass, see SpellLibrary
	s.reach = 300.0
	return s


func _def_meteor_fist() -> SpellDef:
	var s := SpellDef.new()
	s.id = "meteor_fist"
	s.display_name = "Meteor Fist"
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = "earth"
	s.mp_cost = 78
	s.cooldown = 8.5
	s.damage = 165  # was 120 — raised by the DPS-floor pass, see SpellLibrary
	s.radius = 110.0
	s.reach = 260.0
	return s


# ══════════════════════════════════════════════════════════════════════ TEST 1
## Every one of the five declares all five stamped properties, declares a REAL
## element, and states a summoning-circle motif.
##
## All three are silent failures in production: an undeclared property swallows its
## `set()`, an element of -1 makes `SpellCaster.resolve_element` guess AND makes
## `SpellReactor.register` drop the effect outright, and a NONE motif falls back to
## `SpellSigil.MOTIF_BY_SCRIPT` — a table in a file this workstream does not own and
## therefore has no entry for any of these.
func _test_stamp_contract() -> void:
	_fresh_arena()
	for path: String in ALL_PATHS:
		var gd: GDScript = load(path) as GDScript
		_expect(gd != null, "%s loads" % path)
		if gd == null:
			continue
		var node: Node2D = gd.new()
		_arena.add_child(node)
		var present: Dictionary = {}
		for p: Dictionary in node.get_property_list():
			present[String(p["name"])] = true
		for prop: String in STAMP_PROPS:
			_expect(present.has(prop),
				"%s declares `%s` (an undeclared property swallows its stamp silently)"
					% [path.get_file(), prop])
		# ...and the write actually lands, which is the thing that matters.
		node.set(&"caster_node", node)
		_expect(node.get(&"caster_node") == node,
			"%s: setting `caster_node` is not a no-op" % path.get_file())
		var elem: int = int(node.get(&"element_id"))
		_expect(elem >= 0 and elem < Elements.count(),
			"%s declares a real element (got %d — -1 is silently DROPPED by "
				% [path.get_file(), elem] + "SpellReactor.register)")
		_expect(int(node.get(&"sigil_motif")) != MagicCircle.Motif.NONE,
			"%s states a sigil motif (NONE falls through to a table with no entry for it)"
				% path.get_file())
		_expect(node.has_method(&"hex"),
			"%s declares the fixed HEX entry point `hex(caster, origin, target, spell, "
				% path.get_file() + "color, fx)`")
		node.queue_free()
	_completes("stamp_contract")


# ══════════════════════════════════════════════════════════════════════ TEST 2
## THE MAKER'S RULING, AS A REGRESSION GUARD: "we cannot have any recolours".
##
## None of the five may reach for the spectacles they exist to replace. This reads
## the SOURCE rather than the behaviour on purpose — a behavioural test could not
## tell a bespoke crescent from a `BeamSpell` retinted, which is precisely the failure
## being guarded against, and the day someone "simplifies" one of these into a beam
## the diff will be exactly a new mention of one of these names.
##
## `BlastSpell` and `SlamPhysics` are the deliberate EXCEPTION and are asserted the
## other way round: Meteor Fist is supposed to compose them.
func _test_no_recolour() -> void:
	var banned: Array[String] = ["BeamSpell", "MeteorSigil", "DivineRay", "StarConvergence"]
	for path: String in ALL_PATHS:
		var src: String = FileAccess.get_file_as_string(path)
		_expect(src.length() > 0, "%s is readable" % path)
		for name: String in banned:
			_expect(not src.contains(name + "."), "%s does not reuse %s's spectacle"
				% [path.get_file(), name])
	var fist: String = FileAccess.get_file_as_string(FIST_PATH)
	_expect(fist.contains("BlastSpell.new()"),
		"MeteorFist COMPOSES BlastSpell for its detonation rather than rebuilding one")
	_expect(fist.contains("SlamPhysics.check"),
		"MeteorFist COMPOSES SlamPhysics for the body's own impact")
	# ...and having composed a BlastSpell, it must NOT also register itself with the
	# reactor: two entries for one detonation would let the impact clash with itself.
	var fist_node: Node2D = (load(FIST_PATH) as GDScript).new()
	_expect(not fist_node.has_method(&"reaction_shape"),
		"MeteorFist does not publish its own reaction shape (the BlastSpell it spawns "
		+ "is the registered effect — a second entry would double-register one impact)")
	fist_node.free()
	# The other four DO carry the contract themselves.
	for path: String in [CUTS_PATH, IAI_PATH, STEP_PATH, STOMP_PATH]:
		var n: Node2D = (load(path) as GDScript).new()
		for m: String in ["reaction_shape", "reaction_active", "reaction_element",
				"reaction_form", "reaction_owner", "reaction_weight", "reaction_consume"]:
			_expect(n.has_method(StringName(m)),
				"%s implements the reaction contract method `%s`" % [path.get_file(), m])
		n.free()
	_completes("no_recolour")


# ══════════════════════════════════════════════════════════════════════ TEST 3
## The shelf each spell lands on. Tier is DERIVED from cast_time / cooldown / mp
## (`SpellTier.of`), so this is not restating a tag — it is pinning that the tuning
## still produces the intended shelf. The shelf is ALSO the reaction clash weight, so
## a spell that drifts off it starts losing fights it used to win.
func _test_tier_shelves() -> void:
	var want: Array = [
		["thousand_cuts", _def_thousand_cuts(), SpellTier.Tier.ULT],
		["iai_slash", _def_iai_slash(), SpellTier.Tier.HEAVY],
		["crescent_step", _def_crescent_step(), SpellTier.Tier.HEAVY],
		["shockwave_stomp", _def_shockwave_stomp(), SpellTier.Tier.HEAVY],
		["meteor_fist", _def_meteor_fist(), SpellTier.Tier.ULT],
	]
	for row: Array in want:
		var spell: SpellDef = _spell_for(String(row[0]), row[1] as SpellDef)
		var got: int = SpellTier.of(spell)
		_expect(got == int(row[2]),
			"%s sits on the %s shelf (got %s — check cast_time/cooldown/mp against "
				% [row[0], SpellTier.display_name(int(row[2])), SpellTier.display_name(got)]
				+ "SpellTier's thresholds)")
		_expect(spell.kind == SpellDef.Kind.HEX,
			"%s dispatches through the HEX fork (a brand-new Kind is six edits across "
				% row[0] + "six files, none of which error when one is missed)")
	_completes("tier_shelves")


# ══════════════════════════════════════════════════════════════════════ TEST 4
## THOUSAND CUTS — one body, many angles. The marked body must take a cut from
## EVERY orbit position plus the finisher; a body out on the rim takes only the arcs
## that face it; nothing outside the drawn ring is touched, and the caster is never
## cut by its own ult even though it stands in the group the ult scans.
func _test_thousand_cuts() -> void:
	_fresh_arena()
	var spell: SpellDef = _spell_for("thousand_cuts", _def_thousand_cuts())
	var caster: CasterStub = _caster(Vector2(-180.0, 0.0))
	var marked: Dummy = _dummy(Vector2.ZERO)
	var rim: Dummy = _dummy(Vector2(120.0, 0.0))
	var outside: Dummy = _dummy(Vector2(400.0, 0.0))
	var bystander: Dummy = _dummy(Vector2.ZERO, BYSTANDER)
	var node: Node2D = _spawn(CUTS_PATH, spell, caster)
	node.call(&"hex", caster, caster.global_position, Vector2.ZERO, spell,
		Color(0.6, 0.35, 0.9), "shadow")

	# The tell is a promise and nothing else: no damage may exist during it.
	var tell: float = float((load(CUTS_PATH) as GDScript).get_script_constant_map()["LOCK_TELL"])
	_run(node, tell * 0.8)
	_expect(marked.hits() == 0,
		"Thousand Cuts deals nothing during its tell (got %d hits)" % marked.hits())

	_run(node, 2.5)
	# MINIMUM OCCURRENCE, not merely "nothing wrong was hit": the whole point of the
	# spell is that the marked body is opened from every angle.
	_expect(marked.hits() >= spell.count,
		"the marked body takes at least one cut per orbit position (%d cuts, expected >= %d)"
			% [marked.hits(), spell.count])
	_expect(marked.hits() >= spell.count + 1,
		"...plus the heavier finisher (got %d)" % marked.hits())
	# The finisher really is heavier — otherwise "a heavier final cut" is decoration.
	_expect(marked.damage_log.max() > spell.damage,
		"the finisher hits harder than an orbiting cut (biggest %d vs cut %d)"
			% [marked.damage_log.max(), spell.damage])
	_expect(marked.status_log.size() >= 1,
		"the marked body is Weakened (SHADOW ailment applied at least once)")
	# ...and the asymmetry that makes it "ONE body from many angles" rather than a
	# ring AoE: the rim is clipped by some arcs, never by all of them.
	_expect(rim.hits() >= 1, "a body on the rim is caught by the arcs facing it (got %d)"
		% rim.hits())
	_expect(rim.hits() < marked.hits(),
		"...but by strictly fewer than the marked body at the centre (%d vs %d) — "
			% [rim.hits(), marked.hits()] + "otherwise this is a ring AoE, not an orbit")
	_expect(outside.hits() == 0, "nothing outside the drawn ring is cut")
	_expect(bystander.hits() == 0, "a body outside the stamped faction is never cut")
	_expect(caster.damage_log.is_empty(),
		"the caster is not cut by its own ult despite standing in the group it scans")
	_expect(caster.blinks.size() >= spell.count,
		"the caster is relocated to each orbit position through its own `blink_to` "
		+ "vetting (got %d moves)" % caster.blinks.size())
	_completes("thousand_cuts")


# ══════════════════════════════════════════════════════════════════════ TEST 5
## IAI SLASH — one committed cut down a narrow corridor, and PLAIN STEEL: it must
## apply no ailment at all. `element_id` is still ARCANE (an element-less effect is
## dropped by the reactor) — the flavour rule lives in the missing `apply_status`
## call, and this is the assertion that keeps it missing.
func _test_iai_slash() -> void:
	_fresh_arena()
	var spell: SpellDef = _spell_for("iai_slash", _def_iai_slash())
	var caster: CasterStub = _caster(Vector2.ZERO)
	var consts: Dictionary = (load(IAI_PATH) as GDScript).get_script_constant_map()
	var lift: float = float(consts["MUZZLE_LIFT"])
	var draw_time: float = float(consts["DRAW_TIME"])
	# In the lane, off the lane (well outside the half-width), and past the tip.
	var in_lane: Dummy = _dummy(Vector2(70.0, lift))
	var beside: Dummy = _dummy(Vector2(70.0, lift - (spell.width * 0.5 + 45.0)))
	var beyond: Dummy = _dummy(Vector2(spell.reach + 70.0, lift))
	var bystander: Dummy = _dummy(Vector2(70.0, lift), BYSTANDER)
	var node: Node2D = _spawn(IAI_PATH, spell, caster)
	node.call(&"hex", caster, Vector2.ZERO, Vector2(200.0, 0.0), spell,
		Color(0.95, 0.4, 0.85), "arcane")

	_run(node, draw_time * 0.8)
	_expect(in_lane.hits() == 0,
		"Iai Slash deals nothing during the draw — the whole tell is the dodge budget")
	_run(node, 1.5)

	_expect(in_lane.hits() == 1,
		"a body in the lane takes exactly ONE cut (got %d — a committed draw-cut that "
			% in_lane.hits() + "multi-hits is a different spell)")
	_expect(in_lane.total() == spell.damage,
		"...at the spell's full damage (%d, expected %d)" % [in_lane.total(), spell.damage])
	_expect(in_lane.knock_log.size() == 1, "...and is thrown by it")
	# PLAIN STEEL. The Swordsaint's `melee_element` is -1 on purpose.
	_expect(in_lane.status_log.is_empty(),
		"PLAIN STEEL: the cut applies NO ailment (got %s) — the class's stated flavour "
			% str(in_lane.status_log) + "rule lives in this absence")
	_expect(beside.hits() == 0, "a body beside the corridor is not cut")
	_expect(beyond.hits() == 0, "a body past the tip is not cut — this is not a beam")
	_expect(bystander.hits() == 0, "a body outside the stamped faction is never cut")
	_expect(caster.damage_log.is_empty(), "the caster does not cut itself")
	_completes("iai_slash")


# ══════════════════════════════════════════════════════════════════════ TEST 6
## CRESCENT STEP — he MOVES, cutting each body he crosses exactly once, and the body
## really is carried through the caster's own vetting contract.
func _test_crescent_step() -> void:
	_fresh_arena()
	var spell: SpellDef = _spell_for("crescent_step", _def_crescent_step())
	var consts: Dictionary = (load(STEP_PATH) as GDScript).get_script_constant_map()
	var steps: int = int(consts["STEP_COUNT"])
	var windup: float = float(consts["WINDUP"])

	# THE DERIVED INVARIANT, not a copied literal: one sub-step must travel further
	# than `Hero.BLINK_MIN_TRAVEL` or every hop is refused and the dash does not move.
	var min_travel: float = _script_const(HERO_SCRIPT, "BLINK_MIN_TRAVEL", 24.0)
	var step_len: float = spell.reach / float(steps)
	_expect(step_len > min_travel,
		"one Crescent Step sub-step (%.1f px) clears Hero.BLINK_MIN_TRAVEL (%.1f) — "
			% [step_len, min_travel]
			+ "below it every hop is refused and the dash silently does not move")

	var caster: CasterStub = _caster(Vector2.ZERO)
	var lane: Array[Dummy] = [
		_dummy(Vector2(60.0, -14.0)),
		_dummy(Vector2(140.0, -14.0)),
		_dummy(Vector2(220.0, -14.0)),
	]
	var beside: Dummy = _dummy(Vector2(140.0, -14.0 - (spell.width * 0.5 + 60.0)))
	var beyond: Dummy = _dummy(Vector2(spell.reach + 90.0, -14.0))
	var bystander: Dummy = _dummy(Vector2(140.0, -14.0), BYSTANDER)
	var node: Node2D = _spawn(STEP_PATH, spell, caster)
	node.call(&"hex", caster, Vector2.ZERO, Vector2(400.0, 0.0), spell,
		Color(0.95, 0.4, 0.85), "arcane")

	_run(node, windup * 0.8)
	_expect(lane[0].hits() == 0, "Crescent Step deals nothing during the windup")
	_run(node, 1.5)

	var cut_count: int = 0
	for d: Dummy in lane:
		cut_count += d.hits()
		_expect(d.hits() == 1,
			"each body the lane crosses is cut EXACTLY once (a body at %s took %d) — "
				% [str(d.global_position), d.hits()]
				+ "overlapping sub-step corridors must not double-dip")
	_expect(cut_count == lane.size(),
		"...and every one of them was crossed (%d cuts over %d bodies)"
			% [cut_count, lane.size()])
	_expect(lane[2].hits() == 1,
		"the dash PASSES THROUGH bodies — the third body is reached even though two "
		+ "stood in the way")
	_expect(lane[0].status_log.is_empty(),
		"PLAIN STEEL: the pass applies no ailment (got %s)" % str(lane[0].status_log))
	_expect(beside.hits() == 0, "a body beside the lane is not cut")
	_expect(beyond.hits() == 0, "a body past the lane's end is not cut")
	_expect(bystander.hits() == 0, "a body outside the stamped faction is never cut")
	_expect(caster.damage_log.is_empty(), "the caster does not cut itself")
	# HE MOVES, and every resting point went through the caster's own rules.
	_expect(caster.blinks.size() == steps,
		"the body is carried in %d vetted sub-steps (got %d) — this is travel, not a "
			% [steps, caster.blinks.size()] + "teleport")
	_expect(caster.global_position.x > spell.reach * 0.9,
		"...and ends up down the lane (x=%.1f, lane %.1f)"
			% [caster.global_position.x, spell.reach])
	_completes("crescent_step")


# ══════════════════════════════════════════════════════════════════════ TEST 7
## SHOCKWAVE STOMP — grounded force, both ways, with JUMPING as the counterplay.
func _test_shockwave_stomp() -> void:
	_fresh_arena()
	var spell: SpellDef = _spell_for("shockwave_stomp", _def_shockwave_stomp())
	var consts: Dictionary = (load(STOMP_PATH) as GDScript).get_script_constant_map()
	var windup: float = float(consts["WINDUP"])
	var bite: float = float(consts["RIDGE_BITE"])

	var caster: CasterStub = _caster(Vector2.ZERO)
	var right: Dummy = _dummy(Vector2(200.0, 0.0))
	var left: Dummy = _dummy(Vector2(-200.0, 0.0))
	# THE COUNTERPLAY, asserted: same x as a body that IS hit, but airborne by more
	# than the bite. Derived from the constant, never a guessed height.
	var airborne: Dummy = _dummy(Vector2(200.0, -(bite + 45.0)))
	var beyond: Dummy = _dummy(Vector2(spell.reach + 120.0, 0.0))
	var bystander: Dummy = _dummy(Vector2(200.0, 0.0), BYSTANDER)
	var node: Node2D = _spawn(STOMP_PATH, spell, caster)
	node.call(&"hex", caster, Vector2.ZERO, Vector2(300.0, 0.0), spell,
		Color(0.78, 0.55, 0.28), "earth")

	# THE FLAT FALLBACK MUST HAVE FIRED. With no physics world every floor probe
	# misses and `ground_path` returns nothing; without the fallback both ridges would
	# be empty and every assertion below would pass vacuously.
	var paths: Array = node.get(&"_paths") as Array
	_expect(paths.size() == 2, "a stomp builds one ridge path per side (got %d)" % paths.size())
	for p: PackedVector2Array in paths:
		_expect(p.size() >= 2,
			"the flat fallback produced a usable path with no physics world (got %d "
				% p.size() + "points) — without it this whole test would be vacuous")

	_run(node, windup * 0.8)
	_expect(right.hits() == 0, "the stomp deals nothing during the windup")
	_run(node, 2.0)

	_expect(right.hits() == 1, "a grounded body to the RIGHT is caught once (got %d)"
		% right.hits())
	_expect(left.hits() == 1, "a grounded body to the LEFT is caught once (got %d) — "
		% left.hits() + "the ridge runs both ways")
	_expect(right.total() == spell.damage,
		"...at the spell's full damage (%d, expected %d)" % [right.total(), spell.damage])
	_expect(right.status_log.size() == 1, "...and the EARTH ailment lands")
	_expect(right.knock_log.size() == 1 and right.knock_log[0].y < 0.0,
		"...and the shove is UPWARD — a shockwave pops you off the floor")
	# THE JUMP ANSWER.
	_expect(airborne.hits() == 0,
		"an AIRBORNE body at the same x is untouched (got %d) — jumping is the "
			% airborne.hits() + "counterplay and it falls out of measuring from the floor")
	_expect(beyond.hits() == 0, "a body past the reach is untouched")
	_expect(bystander.hits() == 0, "a body outside the stamped faction is never hit")
	_expect(caster.damage_log.is_empty(), "the caster does not stomp itself")
	_completes("shockwave_stomp")


# ══════════════════════════════════════════════════════════════════════ TEST 8
## METEOR FIST — the leap really carries the body, and the detonation really is a
## configured `BlastSpell` carrying this spell's identity.
func _test_meteor_fist() -> void:
	_fresh_arena()
	var spell: SpellDef = _spell_for("meteor_fist", _def_meteor_fist())
	var consts: Dictionary = (load(FIST_PATH) as GDScript).get_script_constant_map()
	var windup: float = float(consts["WINDUP"])
	var leap_steps: int = int(consts["LEAP_STEPS"])
	var landing := Vector2(200.0, 0.0)

	var caster: CasterStub = _caster(Vector2.ZERO)
	var under: Dummy = _dummy(landing)
	var edge: Dummy = _dummy(landing + Vector2(spell.radius + 90.0, 0.0))
	var bystander: Dummy = _dummy(landing, BYSTANDER)
	var node: Node2D = _spawn(FIST_PATH, spell, caster)
	node.call(&"hex", caster, Vector2.ZERO, landing, spell,
		Color(0.78, 0.55, 0.28), "earth")

	_run(node, windup * 0.8)
	_expect(under.hits() == 0,
		"Meteor Fist deals nothing while the ring is still a promise")
	_run(node, 2.0)

	_expect(caster.blinks.size() == leap_steps,
		"the leap carries the body in %d vetted hops (got %d)"
			% [leap_steps, caster.blinks.size()])
	_expect(caster.global_position.distance_to(landing) < 1.0,
		"...and sets it down on the marked point (at %s, marked %s)"
			% [str(caster.global_position), str(landing)])
	# THE ARC IS REAL: at least one hop must be meaningfully above the straight line
	# between the two ends, or this is a slide wearing a leap's name.
	var apex: float = 0.0
	for b: Vector2 in caster.blinks:
		apex = maxf(apex, -b.y)
	_expect(apex > 40.0,
		"the leap actually leaves the floor (apex %.1f px up) — with a flat path this "
			% apex + "would be a dash, not a dive")

	# THE COMPOSITION, checked on the real node rather than on the source: a live
	# BlastSpell under the arena carrying THIS spell's identity.
	var blast: Node = null
	for child: Node in _arena.get_children():
		if child.get_script() != null \
				and String((child.get_script() as Script).resource_path).get_file() == "BlastSpell.gd":
			blast = child
			break
	_expect(blast != null, "the impact spawns a real BlastSpell under the arena")
	if blast != null:
		_expect(int(blast.get(&"element_id")) == spell.element,
			"...carrying this spell's element (EARTH)")
		_expect(int(blast.get(&"spell_tier")) == SpellTier.of(spell),
			"...and its clash weight (ULT) — an unweighted blast loses fights it should win")
		_expect(blast.get(&"caster_node") == caster,
			"...and its caster (a blast with no owner is inert in the reaction system)")
		_expect(is_equal_approx(float(blast.get(&"radius")), spell.radius),
			"...at exactly the radius the danger ring was drawn at")
		_expect(String(blast.get(&"target_group")) == String(HOSTILE),
			"...pointed at the stamped faction, not a hard-coded \"enemy\"")

	_expect(under.hits() >= 1, "a body under the landing point is hit (got %d)" % under.hits())
	_expect(under.total() >= spell.damage,
		"...for at least the spell's damage (%d, expected >= %d)"
			% [under.total(), spell.damage])
	_expect(edge.hits() == 0, "a body outside the drawn radius is untouched")
	_expect(bystander.hits() == 0, "a body outside the stamped faction is never hit")
	_expect(caster.damage_log.is_empty(), "the Brawler does not crater himself")
	_completes("meteor_fist")
