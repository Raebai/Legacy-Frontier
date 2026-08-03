# Run: godot --headless --path godot-project --script tools/slice_test_ranged_signatures.gd
#
# THE FOUR SIGNATURES THAT STOPPED FOUR CLASSES BEING RECOLOURS — Radiant Volley
# (Cleric), Shatter (Cryomancer), Heaven's Wrath (Stormcaller) and Fault Line
# (Juggernaut). This suite exists to hold three promises that are all EASY TO
# BREAK SILENTLY:
#
#   1. THE HEX CONTRACT. Each is dispatched through `SpellCaster.Kind.HEX`, whose
#      arm calls one fixed entry `hex(caster, origin, target, spell, color, fx)`
#      and stamps five identity properties with `set()`. `set()` on a property a
#      script has NOT declared is a silent no-op in Godot 4 — the write goes
#      nowhere, nothing errors, and the spectacle is quietly unowned and inert in
#      the entire reaction system. So the declarations are asserted BY NAME.
#   2. DODGEABILITY. A locked project rule. Every one of these has a tell window
#      and a stated counterplay, and both are pinned here — including the actual
#      dodges, driven on the real per-frame loop: a body outside the volley's band
#      is never pierced, a body that leaves a storm mark is never struck, and a
#      body in the air over the fault is never thrown.
#   3. NO RECOLOURS. The maker's ruling. Asserted structurally, against the
#      SOURCE: none of the four may reach `BeamSpell`, `DivineRay` or
#      `MeteorSigil`, which is what a "different" spell that is really the old
#      corridor in a new colour would have to do.
#
# ── Vacuous-pass armour (the full write-up lives in tools/slice_test_loadout.gd) ─
# `failed += _test_x()` IS BANNED HERE. A dead property read is NOT a test failure
# in GDScript: it logs a runtime error, ABORTS the enclosing function on the spot
# and hands the caller back the return type's zero — which under that idiom reads
# as "this test found zero failures". It silently disabled 64 suites once. So:
# failures accumulate on the MEMBER `_fails` (an abort cannot discard them), and
# every test's last line records that it reached the end. A test that aborts
# part-way is missing from `_completed` and fails the suite BY ABSENCE, whatever
# the cause, with nobody having to predict it in advance.
#
# ⚠ AND THE FOUR SCRIPTS ARE `load()`ED, NEVER NAMED. Two independent reasons:
# a `--script` tool is COMPILED BEFORE THE AUTOLOADS EXIST, and — the one that
# actually bites here — these are BRAND NEW `class_name` scripts, so the global
# class cache does not know them until an `--import` has run. The sweep is run
# with `--no-import`. Naming `Shatter` here would fail to resolve while every
# assertion after it silently vanished. Constants are read out of the scripts'
# own constant maps, which has the happy side effect of proving that each
# "named constant" the design promises actually exists under that name.
extends SceneTree

const VOLLEY_PATH: String = "res://scripts/combat/RadiantVolley.gd"
const SHATTER_PATH: String = "res://scripts/combat/Shatter.gd"
const WRATH_PATH: String = "res://scripts/combat/HeavensWrath.gd"
const FAULT_PATH: String = "res://scripts/combat/FaultLine.gd"
const STATUS_PATH: String = "res://scripts/combat/StatusComponent.gd"
const ZONE_PATH: String = "res://scripts/combat/ZoneSpell.gd"
const SLAM_PATH: String = "res://scripts/combat/SlamPhysics.gd"
const CASTER_PATH: String = "res://scripts/combat/SpellCaster.gd"

## The five names `SpellCaster._stamp()` writes with `set()`, plus the motif
## override. Every one of them is a SILENT no-op when undeclared.
const STAMPED: Array[String] = [
	"element_id", "spell_tier", "caster_node", "target_group", "_target_group",
	"sigil_motif",
]

## Fixed step, so the whole suite is deterministic. The spectacles are driven by
## hand (`set_process(false)` then an explicit `_process(DT)`) rather than on real
## frames: `Performance.TIME_PROCESS` excludes `_draw` and wall-clock in this
## harness is non-monotonic by ~20x, so nothing here may depend on real time.
const DT: float = 1.0 / 60.0

## Every test that must run to completion. A name missing from `_completed` at the
## end means that test aborted part-way — the failure mode this file is armoured
## against — and fails the suite.
const TESTS: Array[String] = [
	"hex_entry_contract",
	"elements_are_declared_not_guessed",
	"volley_escalates_in_waves",
	"volley_pierces_a_rank",
	"volley_band_is_the_dodge",
	"shatter_multiplier_ladder",
	"shatter_reads_cold_state",
	"shatter_breaks_the_frozen_and_taps_the_warm",
	"wrath_repeats_and_commits_its_marks",
	"wrath_marks_are_dodgeable",
	"fault_travels_and_throws",
	"fault_is_jumpable",
	"every_signature_has_a_tell",
	"no_recolours",
	"low_quality_thins_garnish_only",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _arena: Node2D = null


# ---------------------------------------------------------------------- stubs
## A body with everything a spectacle actually touches, and a LOG of what was done
## to it. DECLARED properties, never metadata: `set()` on an undeclared property is
## a silent no-op, so a stub that merely pretended to have `hp` would make every
## assertion about it pass while measuring nothing.
##
## `take_damage` takes ONE argument (the `Hero` signature) on purpose, so
## `SpellTargets.hurt`'s arity adaptation is exercised rather than bypassed — the
## two-signature trap is one of the things these spells had to get right.
class Fighter extends Node2D:
	var hp: int = 5000
	var max_hp: int = 5000
	var velocity: Vector2 = Vector2.ZERO
	var damage_log: Array[int] = []
	var knockbacks: Array[Vector2] = []
	var applied: Array[int] = []
	## The real `StatusComponent`, attached from outside (never `preload`ed in
	## here — it draws through `CharacterRig`, a file another agent owns).
	var status: Node2D = null

	func take_damage(amount: int) -> void:
		damage_log.append(amount)
		hp = maxi(hp - amount, 0)

	func apply_status(element: int, can_chain: bool = true) -> void:
		applied.append(element)
		if status != null and is_instance_valid(status):
			status.call("apply", element, can_chain)

	func apply_knockback(v: Vector2) -> void:
		knockbacks.append(v)

	func total() -> int:
		var t: int = 0
		for d: int in damage_log:
			t += d
		return t


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_arena = Node2D.new()
	root.add_child(_arena)
	_test_hex_entry_contract()
	_test_elements_are_declared_not_guessed()
	_test_volley_escalates_in_waves()
	_test_volley_pierces_a_rank()
	_test_volley_band_is_the_dodge()
	_test_shatter_multiplier_ladder()
	_test_shatter_reads_cold_state()
	_test_shatter_breaks_the_frozen_and_taps_the_warm()
	_test_wrath_repeats_and_commits_its_marks()
	_test_wrath_marks_are_dodgeable()
	_test_fault_travels_and_throws()
	_test_fault_is_jumpable()
	_test_every_signature_has_a_tell()
	_test_no_recolours()
	_test_low_quality_thins_garnish_only()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — something it reads has moved)" % t)
	if _fails > 0:
		printerr("Ranged signature tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Ranged signature tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort therefore survives the abort instead of being thrown away with
## the aborted function's discarded result.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------- plumbing
func _script(path: String) -> GDScript:
	var s: GDScript = load(path) as GDScript
	_expect(s != null, "%s loads" % path)
	return s


func _consts(path: String) -> Dictionary:
	var s: GDScript = _script(path)
	return s.get_script_constant_map() if s != null else {}


## A spectacle, parented to the arena and taken OFF the engine's process loop so
## the suite can step it by hand at a fixed `DT`.
func _spawn(path: String) -> Node2D:
	var s: GDScript = _script(path)
	if s == null:
		return null
	var n: Node2D = s.new()
	_arena.add_child(n)
	n.set_process(false)
	n.set_physics_process(false)
	return n


## Step a spectacle `steps` frames, stopping early if it has freed itself.
func _step(spec: Node2D, steps: int) -> void:
	for _i: int in steps:
		if spec == null or not is_instance_valid(spec) or spec.is_queued_for_deletion():
			return
		spec.call("_process", DT)


func _fighter(at: Vector2, with_status: bool = false) -> Fighter:
	var f := Fighter.new()
	_arena.add_child(f)
	f.global_position = at
	if with_status:
		var sc: Node2D = (_script(STATUS_PATH)).new()
		f.add_child(sc)
		sc.set_process(false)   # ailment timers stepped only when a test wants them
		f.status = sc
	return f


func _spell(fields: Dictionary) -> SpellDef:
	var s := SpellDef.new()
	for k: String in fields:
		s.set(k, fields[k])
	return s


## Property names a spectacle must DECLARE, checked against its real property
## list. The completion sentinel says "something died"; this says which name did.
func _require_props(obj: Object, names: Array[String], label: String) -> void:
	if obj == null:
		_expect(false, "%s exists (cannot check its members)" % label)
		return
	var present: Dictionary = {}
	for p: Dictionary in obj.get_property_list():
		present[String(p["name"])] = true
	for n: String in names:
		_expect(present.has(n),
			"%s DECLARES `%s` — `set()` on an undeclared property is a silent no-op" % [label, n])


func _source(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_expect(false, "%s is readable as source" % path)
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


# ---------------------------------------------------------------- THE CONTRACT
## Every one of the four takes the ONE entry function the HEX arm calls, with the
## six arguments it passes, and declares all five properties `_stamp()` writes.
func _test_hex_entry_contract() -> void:
	for path: String in [VOLLEY_PATH, SHATTER_PATH, WRATH_PATH, FAULT_PATH]:
		var spec: Node2D = _spawn(path)
		if spec == null:
			continue
		var found: int = -1
		for m: Dictionary in spec.get_method_list():
			if String(m.get("name", "")) == "hex":
				found = (m.get("args", []) as Array).size()
				break
		_expect(found == 6,
			"%s implements hex(caster, origin, target, spell, color, fx) — got %d args"
				% [path.get_file(), found])
		_require_props(spec, STAMPED, path.get_file())
		spec.free()
	_completes("hex_entry_contract")


## ⚠ THE TRAP THIS PINS. `SpellCaster.resolve_element()` maps the effect string
## "holy" onto LIGHTNING — a fallback from before HOLY existed as an element — so
## a def that leaves `element` at -1 lands a Shock instead of a Radiance burn AND
## drops out of every HOLY reaction row. Both halves are asserted: the trap is
## real, and stating the element defeats it.
func _test_elements_are_declared_not_guessed() -> void:
	var caster: GDScript = _script(CASTER_PATH)
	if caster != null:
		var guessed: SpellDef = _spell({"effect": "holy", "element": -1})
		_expect(int(caster.call("resolve_element", guessed)) == int(Elements.Element.LIGHTNING),
			"the trap is real: effect=\"holy\" with element=-1 still resolves to LIGHTNING")
		var stated: SpellDef = _spell({"effect": "holy", "element": Elements.Element.HOLY})
		_expect(int(caster.call("resolve_element", stated)) == int(Elements.Element.HOLY),
			"...and declaring the element defeats it")
	# Each spectacle's own default must already be a real element, so a bare
	# instantiation (capture tool, reaction respawn, this suite) behaves like a
	# real cast rather than falling through to a guess.
	var want: Dictionary = {
		VOLLEY_PATH: Elements.Element.HOLY,
		SHATTER_PATH: Elements.Element.ICE,
		WRATH_PATH: Elements.Element.LIGHTNING,
		FAULT_PATH: Elements.Element.EARTH,
	}
	for path: String in want:
		var spec: Node2D = _spawn(path)
		if spec == null:
			continue
		var e: Variant = spec.get(&"element_id")
		_expect(e != null and int(e) >= 0,
			"%s declares a real element (never -1)" % path.get_file())
		_expect(e != null and int(e) == int(want[path]),
			"%s is element %d" % [path.get_file(), int(want[path])])
		spec.free()
	_completes("elements_are_declared_not_guessed")


# ------------------------------------------------------------- RADIANT VOLLEY
func _test_volley_escalates_in_waves() -> void:
	var k: Dictionary = _consts(VOLLEY_PATH)
	var scr: GDScript = _script(VOLLEY_PATH)
	var waves: Array = k.get("WAVES", [])
	_expect(waves.size() >= 3, "the volley is at least three waves (got %d)" % waves.size())
	var strictly_up: bool = true
	var summed: int = 0
	for i: int in waves.size():
		summed += int(waves[i])
		if i > 0 and int(waves[i]) <= int(waves[i - 1]):
			strictly_up = false
	_expect(strictly_up, "each wave is bigger than the last — the volley ESCALATES")
	if scr != null:
		_expect(int(scr.call("volley_size")) == summed,
			"volley_size() is derived from WAVES, not restated (%d vs %d)"
				% [int(scr.call("volley_size")), summed])
		var first: float = float(scr.call("wave_launch_time", 0))
		var last: float = float(scr.call("wave_launch_time", waves.size() - 1))
		_expect(last - first >= 0.5,
			"the volley has a shape in TIME, not one instant (%.2f s across)" % (last - first))
	_completes("volley_escalates_in_waves")


## THE REWARD. A lance PIERCES, so a rank of bodies lined up along the aim is what
## this spell is for. Asserted structurally rather than by totals: at least one
## single lance must carry three separate victims in its own hit-set, which a
## non-piercing volley of any size cannot produce.
func _test_volley_pierces_a_rank() -> void:
	var vol: Node2D = _spawn(VOLLEY_PATH)
	if vol == null:
		_completes("volley_pierces_a_rank")
		return
	var rank: Array[Fighter] = [
		_fighter(Vector2(300.0, 0.0)),
		_fighter(Vector2(430.0, 0.0)),
		_fighter(Vector2(560.0, 0.0)),
	]
	for f: Fighter in rank:
		f.add_to_group("volley_rank")
	vol.set("target_group", "volley_rank")
	vol.call("hex", null, Vector2.ZERO, Vector2(700.0, 0.0),
		_spell({"damage": 14, "length": 760.0}), Color(1.0, 0.92, 0.55), "")
	_step(vol, 140)
	var scr: GDScript = _script(VOLLEY_PATH)
	var expected: int = int(scr.call("volley_size")) if scr != null else 0
	# MINIMUM OCCURRENCE FIRST. "No lance misbehaved" is trivially true of a volley
	# that never fired, so an invariant that cannot fail on an empty result is not
	# an invariant — everything below is only meaningful because of this line.
	_expect(int(vol.get(&"lances_fired")) == expected,
		"every lance actually launched (%d of %d)" % [int(vol.get(&"lances_fired")), expected])
	_expect(int(vol.get(&"lances_expired")) + int(vol.get(&"lances_blocked"))
			== int(vol.get(&"lances_fired")),
		"every launched lance is accounted for — none leaked")
	var deepest: int = 0
	var pierce_total: int = 0
	for lance: Dictionary in (vol.get(&"_lances") as Array):
		var n: int = (lance["hit"] as Dictionary).size()
		pierce_total += n
		deepest = maxi(deepest, n)
	_expect(deepest >= 3,
		"a single lance carried a whole rank — %d bodies on its deepest hit-set" % deepest)
	_expect(pierce_total == int(vol.get(&"pierce_hits")),
		"the pierce tally matches the per-lance hit-sets (%d vs %d)"
			% [pierce_total, int(vol.get(&"pierce_hits"))])
	for i: int in rank.size():
		var f: Fighter = rank[i]
		_expect(f.damage_log.size() >= 1, "rank body %d was hit at all" % i)
		# ...and never twice by the SAME lance: the per-lance hit-set is what makes
		# piercing a reward for lining a rank up rather than a free multi-hit.
		var by_lances: int = 0
		for lance: Dictionary in (vol.get(&"_lances") as Array):
			if (lance["hit"] as Dictionary).has(f.get_instance_id()):
				by_lances += 1
		_expect(f.damage_log.size() == by_lances,
			"rank body %d took exactly one hit per lance (%d hits, %d lances)"
				% [i, f.damage_log.size(), by_lances])
	_cleanup()
	_completes("volley_pierces_a_rank")


## THE COUNTERPLAY. The band never widens, so one sidestep perpendicular to the
## aim leaves it for good. `band_half()` is DERIVED from the rack geometry, and
## the dodge is measured against that derivation rather than against a copied
## number — so retuning the rack moves the test with the spell.
func _test_volley_band_is_the_dodge() -> void:
	var scr: GDScript = _script(VOLLEY_PATH)
	var k: Dictionary = _consts(VOLLEY_PATH)
	if scr == null:
		_completes("volley_band_is_the_dodge")
		return
	var half: float = float(scr.call("band_half"))
	_expect(half > 20.0 and half < float(k.get("RACK_RADIUS", 96.0)),
		"the band is a real width bounded by the rack radius (%.1f px)" % half)
	var vol: Node2D = _spawn(VOLLEY_PATH)
	if vol == null:
		_completes("volley_band_is_the_dodge")
		return
	var inside: Fighter = _fighter(Vector2(400.0, 0.0))
	# Just outside the band plus the lance's own hit radius: one sidestep.
	var outside: Fighter = _fighter(
		Vector2(400.0, half + float(k.get("HIT_RADIUS", 13.0)) + 12.0))
	inside.add_to_group("volley_band")
	outside.add_to_group("volley_band")
	vol.set("target_group", "volley_band")
	vol.call("hex", null, Vector2.ZERO, Vector2(700.0, 0.0),
		_spell({"damage": 14, "length": 760.0}), Color(1.0, 0.92, 0.55), "")
	_step(vol, 140)
	_expect(inside.damage_log.size() > 0, "a body ON the band is pierced")
	_expect(outside.damage_log.is_empty(),
		"a body one sidestep OFF the band is never touched (took %d hits)"
			% outside.damage_log.size())
	_cleanup()
	_completes("volley_band_is_the_dodge")


# --------------------------------------------------------------------- SHATTER
## The whole balance claim of the class's two-button combo, as pure statics.
func _test_shatter_multiplier_ladder() -> void:
	var k: Dictionary = _consts(SHATTER_PATH)
	var scr: GDScript = _script(SHATTER_PATH)
	if scr == null:
		_completes("shatter_multiplier_ladder")
		return
	var warm: float = float(k.get("WARM_MULT", -1.0))
	var rimed: float = float(k.get("RIMED_MULT", -1.0))
	var frozen: float = float(k.get("FROZEN_MULT", -1.0))
	_expect(warm > 0.0 and rimed > 0.0 and frozen > 0.0,
		"WARM_MULT / RIMED_MULT / FROZEN_MULT all exist as NAMED constants")
	_expect(warm < 0.6, "a warm target is a weak thump (x%.2f) — opening with it is a mistake" % warm)
	_expect(frozen >= 2.5, "a frozen target is the payoff (x%.2f)" % frozen)
	_expect(warm < rimed and rimed < frozen, "the ladder is strictly ordered warm < rimed < frozen")
	_expect(frozen / warm >= 6.0,
		"freeze-then-break is worth %.1fx a cold open — the combo is the identity"
			% (frozen / warm))
	var cold: Dictionary = k.get("Cold", {})
	_expect(cold.has("WARM") and cold.has("RIMED") and cold.has("FROZEN"),
		"the Cold enum names all three states")
	if cold.has("WARM"):
		# `damage_for` must be derived from `multiplier_for`, never a second ladder.
		for state: String in ["WARM", "RIMED", "FROZEN"]:
			var s: int = int(cold[state])
			_expect(int(scr.call("damage_for", 100, s))
					== maxi(int(round(100.0 * float(scr.call("multiplier_for", s)))), 1),
				"damage_for() reads multiplier_for() for %s — one ladder, not two" % state)
	_completes("shatter_multiplier_ladder")


## The condition is read out of two places nobody publishes a getter for: the
## body's own `StatusComponent`, and a live Blizzard's rime table. Both paths are
## driven here, because "it degrades to warm" is exactly what a silent break looks
## like and only a positive assertion catches it.
func _test_shatter_reads_cold_state() -> void:
	var sh: Node2D = _spawn(SHATTER_PATH)
	var k: Dictionary = _consts(SHATTER_PATH)
	var cold: Dictionary = k.get("Cold", {})
	if sh == null or not cold.has("FROZEN"):
		_completes("shatter_reads_cold_state")
		return
	var warm: Fighter = _fighter(Vector2(0.0, 0.0), true)
	_expect(int(sh.call("cold_state", warm)) == int(cold["WARM"]), "an untouched body is WARM")
	var chilled: Fighter = _fighter(Vector2(40.0, 0.0), true)
	chilled.status.call("apply", Elements.Element.ICE, false)
	_expect(int(sh.call("cold_state", chilled)) == int(cold["RIMED"]),
		"one ice application chills — RIMED")
	var frozen: Fighter = _fighter(Vector2(80.0, 0.0), true)
	frozen.status.call("apply", Elements.Element.ICE, false)
	frozen.status.call("apply", Elements.Element.ICE, false)
	_expect(int(sh.call("cold_state", frozen)) == int(cold["FROZEN"]),
		"a second application on a chilled body FREEZES it — FROZEN")
	# ...and the Blizzard path, off a real field's `_rime` table. The field is
	# parked (no `open()`, no processing) — only the shape of its state matters.
	var zone: Node2D = _spawn(ZONE_PATH)
	var zk: Dictionary = _consts(ZONE_PATH)
	if zone != null and zk.has("RIME_TO_ENCASE"):
		var full: float = float(zk["RIME_TO_ENCASE"])
		var rimed: Fighter = _fighter(Vector2(140.0, 0.0))
		zone.set("_rime", {rimed.get_instance_id():
			{"node": rimed, "t": full * 0.6, "enc": -1.0, "ref": 0.0}})
		_expect(int(sh.call("cold_state", rimed)) == int(cold["RIMED"]),
			"a part-filled rime meter reads as RIMED")
		zone.set("_rime", {rimed.get_instance_id():
			{"node": rimed, "t": full, "enc": 0.5, "ref": 0.0}})
		_expect(int(sh.call("cold_state", rimed)) == int(cold["FROZEN"]),
			"an ENCASED body reads as FROZEN — Blizzard's third beat, fired on demand")
		# Below the floor the frost has barely started; calling that cold would make
		# the fuse meaningless.
		zone.set("_rime", {rimed.get_instance_id():
			{"node": rimed, "t": full * float(k.get("RIME_MIN", 0.15)) * 0.5,
			"enc": -1.0, "ref": 0.0}})
		_expect(int(sh.call("cold_state", rimed)) == int(cold["WARM"]),
			"a barely-started meter is still WARM (RIME_MIN is a real threshold)")
	else:
		_expect(false, "ZoneSpell still publishes RIME_TO_ENCASE (the fuse length moved)")
	_cleanup()
	_completes("shatter_reads_cold_state")


## End to end on the real loop: two bodies in one blast, one frozen, one warm.
func _test_shatter_breaks_the_frozen_and_taps_the_warm() -> void:
	var sh: Node2D = _spawn(SHATTER_PATH)
	var scr: GDScript = _script(SHATTER_PATH)
	var k: Dictionary = _consts(SHATTER_PATH)
	var cold: Dictionary = k.get("Cold", {})
	if sh == null or scr == null or not cold.has("FROZEN"):
		_completes("shatter_breaks_the_frozen_and_taps_the_warm")
		return
	var frozen: Fighter = _fighter(Vector2(0.0, 0.0), true)
	frozen.status.call("apply", Elements.Element.ICE, false)
	frozen.status.call("apply", Elements.Element.ICE, false)
	var warm: Fighter = _fighter(Vector2(60.0, 0.0), true)
	frozen.add_to_group("shatter_mob")
	warm.add_to_group("shatter_mob")
	sh.set("target_group", "shatter_mob")
	var base: int = 42
	sh.call("hex", null, Vector2.ZERO, Vector2.ZERO,
		_spell({"damage": base, "radius": 104.0}), Color(0.55, 0.85, 1.0), "")
	# Nothing may happen during the fuse — that window IS the tell.
	_step(sh, int(float(k.get("FUSE", 0.28)) / DT) - 2)
	_expect(frozen.damage_log.is_empty() and warm.damage_log.is_empty(),
		"nothing is hurt during the fuse — the tell is a real window")
	_step(sh, 6)
	_expect(int(sh.get(&"bodies_hit")) == 2, "both bodies in the footprint were caught")
	_expect(int(sh.get(&"frozen_breaks")) == 1, "exactly one casing broke")
	_expect(frozen.damage_log.size() > 0 and warm.damage_log.size() > 0,
		"both took a hit (the assertions below are only meaningful if they did)")
	if frozen.damage_log.size() > 0:
		_expect(frozen.damage_log[0] == int(scr.call("damage_for", base, int(cold["FROZEN"]))),
			"the frozen body took the FROZEN multiplier (%d)" % frozen.damage_log[0])
	if warm.damage_log.size() > 0:
		_expect(warm.damage_log[0] == int(scr.call("damage_for", base, int(cold["WARM"]))),
			"the warm body took the WARM multiplier (%d)" % warm.damage_log[0])
	_expect(int(sh.get(&"shard_hits")) == 1,
		"the broken casing splashed its neighbour — the crowd payoff")
	# ⚠ THE ANTI-STUNLOCK RULE. A second ICE application on an already-chilled body
	# is a FREEZE, so a spell that re-iced on every hit would rebuild exactly the
	# chill->freeze->chill lock Blizzard's rework deleted. Shatter CONSUMES cold.
	_expect(frozen.applied.is_empty(),
		"an already-frozen body is NOT re-iced (would be a stunlock)")
	_expect(warm.applied.size() == 1 and warm.applied[0] == int(Elements.Element.ICE),
		"...but a warm body is chilled — the spell sets up its own next cast")
	_cleanup()
	_completes("shatter_breaks_the_frozen_and_taps_the_warm")


# -------------------------------------------------------------- HEAVEN'S WRATH
## It is WEATHER, not a bolt: repeating, and every strike commits its landing
## point a fixed window ahead of arriving there.
func _test_wrath_repeats_and_commits_its_marks() -> void:
	var k: Dictionary = _consts(WRATH_PATH)
	var scr: GDScript = _script(WRATH_PATH)
	var wr: Node2D = _spawn(WRATH_PATH)
	if wr == null or scr == null:
		_completes("wrath_repeats_and_commits_its_marks")
		return
	var strikes: int = int(k.get("STRIKES", 0))
	var life: float = float(k.get("LIFE", 0.0))
	var tell: float = float(k.get("MARK_TELL", 0.0))
	_expect(strikes >= 4, "the storm strikes more than once (%d)" % strikes)
	_expect(float(scr.call("land_time", strikes - 1)) <= life,
		"the whole schedule fits inside the cell's life")
	_expect(float(scr.call("land_time", strikes - 1)) - float(scr.call("land_time", 0)) >= 1.5,
		"the strikes are spread over seconds — this is a period of danger, not a flash")
	var victim: Fighter = _fighter(Vector2(0.0, 0.0))
	victim.add_to_group("wrath_mob")
	wr.set("target_group", "wrath_mob")
	wr.call("hex", null, Vector2(-400.0, 0.0), Vector2.ZERO,
		_spell({"damage": 42}), Color(0.55, 0.75, 1.0), "")
	_step(wr, int(life / DT) + 4)
	_expect(int(wr.get(&"marks_placed")) == strikes,
		"every strike placed a mark (%d of %d)" % [int(wr.get(&"marks_placed")), strikes])
	_expect(int(wr.get(&"bolts_fired")) == strikes,
		"...and every mark became a bolt (%d of %d)" % [int(wr.get(&"bolts_fired")), strikes])
	_expect(int(wr.get(&"marks_on_bodies")) >= 1,
		"the storm tracked a body under it at least once")
	_expect(int(wr.get(&"bodies_struck")) >= 1,
		"a body that stood still through a whole storm was actually hit")
	_expect(tell >= 0.3,
		"a mark is committed a readable window before it lands (%.2f s)" % tell)
	_cleanup()
	_completes("wrath_repeats_and_commits_its_marks")


## THE COUNTERPLAY, and the proof that tracking is not homing: a mark is a
## SNAPSHOT of a world point, so leaving it after it is placed beats the bolt.
func _test_wrath_marks_are_dodgeable() -> void:
	var k: Dictionary = _consts(WRATH_PATH)
	var scr: GDScript = _script(WRATH_PATH)
	var wr: Node2D = _spawn(WRATH_PATH)
	if wr == null or scr == null:
		_completes("wrath_marks_are_dodgeable")
		return
	var victim: Fighter = _fighter(Vector2(0.0, 0.0))
	victim.add_to_group("wrath_dodge")
	wr.set("target_group", "wrath_dodge")
	wr.call("hex", null, Vector2(-400.0, 0.0), Vector2.ZERO,
		_spell({"damage": 42}), Color(0.55, 0.75, 1.0), "")
	# Step just past the first mark being committed...
	_step(wr, int(float(scr.call("mark_time", 0)) / DT) + 2)
	_expect(int(wr.get(&"marks_placed")) == 1, "the first mark is down")
	_expect(int(wr.get(&"bolts_fired")) == 0, "...and has not landed yet — the window is open")
	var marks: Array = wr.get(&"_marks") as Array
	if marks.size() == 1:
		var committed: Vector2 = (marks[0] as Dictionary)["pos"]
		_expect(committed.distance_to(victim.global_position) < 40.0,
			"the mark was placed where the body WAS")
	# ...then walk away, well past the cell.
	victim.global_position = Vector2(3000.0, 0.0)
	_step(wr, int(float(k.get("MARK_TELL", 0.45)) / DT) + 4)
	_expect(int(wr.get(&"bolts_fired")) >= 1, "the bolt fell anyway — it is weather")
	_expect(victim.damage_log.is_empty(),
		"...but it fell where you WERE, not where you are (took %d hits)"
			% victim.damage_log.size())
	_cleanup()
	_completes("wrath_marks_are_dodgeable")


# ------------------------------------------------------------------ FAULT LINE
func _test_fault_travels_and_throws() -> void:
	var scr: GDScript = _script(FAULT_PATH)
	var k: Dictionary = _consts(FAULT_PATH)
	var slam: Dictionary = _consts(SLAM_PATH)
	var fl: Node2D = _spawn(FAULT_PATH)
	if fl == null or scr == null:
		_completes("fault_travels_and_throws")
		return
	# The impulse is DERIVED from the shared slam threshold, not picked: a rupture
	# that threw bodies slower than `MIN_SLAM_SPEED` would hurl them into walls
	# with no impact registered at all, and nothing would look wrong.
	_expect(float(scr.call("knockback")) > float(slam.get("MIN_SLAM_SPEED", 250.0)),
		"a thrown body is guaranteed to register a slam when it lands")
	var on_seam: Fighter = _fighter(Vector2(300.0, 0.0))
	var off_seam: Fighter = _fighter(Vector2(500.0, 240.0))
	on_seam.add_to_group("fault_mob")
	off_seam.add_to_group("fault_mob")
	fl.set("target_group", "fault_mob")
	fl.call("hex", null, Vector2.ZERO, Vector2(900.0, 0.0),
		_spell({"damage": 105, "length": 760.0}), Color(0.78, 0.55, 0.28), "")
	# Nothing moves during the seam tell — the spell shows its whole future first.
	_step(fl, int(float(k.get("SEAM_TELL", 0.34)) / DT) - 2)
	_expect(int(fl.get(&"crest_steps")) == 0,
		"the crest has not moved during the tell — the seam is a real window")
	_expect(on_seam.damage_log.is_empty(), "...and nothing has been thrown yet")
	var total_steps: int = int((float(scr.call("travel_time", 760.0))
		+ float(k.get("SEAM_TELL", 0.34))) / DT) + 10
	_step(fl, total_steps)
	_expect(int(fl.get(&"crest_steps")) > 40,
		"the rupture TRAVELLED — %d crest steps, not a placed eruption"
			% int(fl.get(&"crest_steps")))
	_expect(int(fl.get(&"bodies_thrown")) == 1,
		"exactly the body on the seam was thrown (%d)" % int(fl.get(&"bodies_thrown")))
	_expect(on_seam.damage_log.size() == 1,
		"...once, not once per frame it was overlapped (%d hits)" % on_seam.damage_log.size())
	_expect(on_seam.knockbacks.size() == 1 and on_seam.knockbacks[0].y < 0.0,
		"it was thrown UP — the floor opened underneath it")
	_expect(off_seam.damage_log.is_empty(),
		"a body off the line is untouched (took %d hits)" % off_seam.damage_log.size())
	_expect(int(fl.get(&"terrain_bites")) >= 3,
		"the floor was torn along the way (%d gouges)" % int(fl.get(&"terrain_bites")))
	_cleanup()
	_completes("fault_travels_and_throws")


## THE COUNTERPLAY that separates a ground wave from a beam: `AIR_CLEAR` is the
## jump dodge, and it is asserted from the constant so retuning it moves the test.
func _test_fault_is_jumpable() -> void:
	var k: Dictionary = _consts(FAULT_PATH)
	var scr: GDScript = _script(FAULT_PATH)
	var fl: Node2D = _spawn(FAULT_PATH)
	if fl == null or scr == null:
		_completes("fault_is_jumpable")
		return
	var clear: float = float(k.get("AIR_CLEAR", 46.0))
	_expect(clear > 0.0 and clear < 140.0,
		"AIR_CLEAR is a real ceiling a jump can beat (%.0f px)" % clear)
	var grounded: Fighter = _fighter(Vector2(280.0, 0.0))
	var airborne: Fighter = _fighter(Vector2(420.0, -clear - 30.0))
	grounded.add_to_group("fault_jump")
	airborne.add_to_group("fault_jump")
	fl.set("target_group", "fault_jump")
	fl.call("hex", null, Vector2.ZERO, Vector2(900.0, 0.0),
		_spell({"damage": 105, "length": 760.0}), Color(0.78, 0.55, 0.28), "")
	_step(fl, int((float(scr.call("travel_time", 760.0))
		+ float(k.get("SEAM_TELL", 0.34))) / DT) + 10)
	# Minimum occurrence first: the dodge assertion below means nothing unless the
	# rupture demonstrably hurt the body that did NOT jump.
	_expect(grounded.damage_log.size() == 1, "the grounded body was thrown")
	_expect(airborne.damage_log.is_empty(),
		"the airborne body cleared it — a jump beats a ground wave (took %d hits)"
			% airborne.damage_log.size())
	_cleanup()
	_completes("fault_is_jumpable")


# ------------------------------------------------------------- CROSS-CUTTING
## "Everything must be dodgeable" is a locked project rule, and a tell of zero is
## how it gets broken without anyone noticing. Each spell's tell is a named
## constant and each one is a window a human can act inside.
func _test_every_signature_has_a_tell() -> void:
	var tells: Array = [
		[VOLLEY_PATH, "RACK_HOLD"],
		[SHATTER_PATH, "FUSE"],
		[WRATH_PATH, "MARK_TELL"],
		[FAULT_PATH, "SEAM_TELL"],
	]
	for row: Array in tells:
		var k: Dictionary = _consts(row[0] as String)
		var name: String = row[1] as String
		_expect(k.has(name), "%s names its tell `%s`" % [(row[0] as String).get_file(), name])
		if k.has(name):
			_expect(float(k[name]) >= 0.15,
				"%s's tell is a real window (%s = %.2f s)"
					% [(row[0] as String).get_file(), name, float(k[name])])
	_completes("every_signature_has_a_tell")


## THE MAKER'S RULING, as a structural guard: "we cannot have any recolours".
## Five classes shared one `BeamSpell` corridor and four "different" ults shared
## one `MeteorSigil.rain()`. A new spell that quietly reached for either would be
## the same bug wearing a new name, so reaching for them is made unexpressible.
func _test_no_recolours() -> void:
	var banned: Array[String] = ["BeamSpell", "DivineRay", "MeteorSigil", "StarConvergence"]
	for path: String in [VOLLEY_PATH, SHATTER_PATH, WRATH_PATH, FAULT_PATH]:
		var src: String = _source(path)
		if src.is_empty():
			continue
		# Comments explain what these spells are NOT, so only real CODE references
		# count: the `.gd` path form and the bare-identifier call form.
		for b: String in banned:
			_expect(not src.contains(b + ".gd\"") and not src.contains(b + "."),
				"%s does not reach for %s — no recolours" % [path.get_file(), b])
	_completes("no_recolours")


## ⚠ MUST DEGRADE AT `graphics_quality = LOW` — the phone preview, and a hard
## rule. Each of these can flood the effect budget (21 lances, a 5-bolt storm, a
## travelling rupture), so each must consult the quality probe, and its cheap path
## must actually be cheaper. What may NOT thin is the telegraph; that is asserted
## by the tell test above, which reads the same constants at both settings.
func _test_low_quality_thins_garnish_only() -> void:
	for path: String in [VOLLEY_PATH, SHATTER_PATH, WRATH_PATH, FAULT_PATH]:
		var src: String = _source(path)
		if src.is_empty():
			continue
		_expect(src.contains("TuningConfig.quality_is_low()"),
			"%s consults the quality probe (never OS.has_feature directly)" % path.get_file())
	var sk: Dictionary = _consts(SHATTER_PATH)
	_expect(int(sk.get("FRACTURES_LOW", 99)) < int(sk.get("FRACTURES", 0)),
		"Shatter draws fewer fracture blades at LOW")
	var wk: Dictionary = _consts(WRATH_PATH)
	_expect(int(wk.get("LOBES_LOW", 99)) < int(wk.get("LOBES", 0)),
		"Heaven's Wrath draws a thinner cloud at LOW")
	var fk: Dictionary = _consts(FAULT_PATH)
	_expect(float(fk.get("CRATER_STRIDE_LOW", 0.0)) > float(fk.get("CRATER_STRIDE", 99999.0)),
		"Fault Line lays craters at a sparser stride at LOW")
	_completes("low_quality_thins_garnish_only")


## Free everything the arena is holding between tests, so one test's bodies can
## never be found by the next one's group scan.
func _cleanup() -> void:
	for child: Node in _arena.get_children():
		_arena.remove_child(child)
		child.free()
