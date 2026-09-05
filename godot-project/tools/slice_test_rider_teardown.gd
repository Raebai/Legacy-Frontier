# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_rider_teardown.gd
#
# RIDER TEARDOWN — "all these errors shouldn't be crashing the game."
#
# ── THE BUG THIS SUITE EXISTS FOR ────────────────────────────────────────────
# Reported from real play on floor 10:
#
#     E  _restore: Trying to assign invalid previously freed instance.
#        EliteHerald.gd:119 @ _restore()
#        EliteHerald.gd:129 @ _exit_tree()
#
# `_restore` ALREADY read `if e == null or not is_instance_valid(e): continue` on the
# very next line. The guard was unreachable. `var e: Node = row["n"]` binds a container
# element into a STATICALLY TYPED slot, and in Godot 4.6 that binding is what faults on
# a freed instance — before any guard can answer. Measured, not assumed:
#
#     is_instance_valid(freed)  ->  false
#     freed == null             ->  TRUE          (Godot 4.6; the repo's own comment in
#                                                  BossModRider said the opposite)
#     var n: Node = <freed>     ->  FAULTS
#     f(x: Node) with a freed x ->  FAULTS (so a callee's own guard cannot save a caller)
#
# Measurements: tools/probe_freed_semantics.gd. Reproduction: probe_elite_teardown.gd.
#
# AND IT WAS NEVER ONLY LOG SPAM. A GDScript runtime error ABORTS the enclosing
# function, so `_lifted.clear()` never ran and every body queued after the first dead
# one never got restored — the room stayed permanently quickened, which is the exact
# thing `_exit_tree` calls `_restore` to prevent. That is what test 4 pins.
#
# ── WHY THE FILE LIST IS DISCOVERED AND NOT WRITTEN DOWN ─────────────────────
# `EliteHerald` is one of a family of thirteen written to one shape. A hand-kept array
# would cover the twelve that exist and none of the one added next month, which is
# precisely how this shape spread in the first place. Everything below walks
# `DirAccess` over both rider directories, so a modifier added tomorrow is covered on
# the day it lands or the suite says which one it could not build.
#
# ── THE THREE MECHANISMS, AND WHY IT TAKES THREE ─────────────────────────────
# A GDScript runtime error is not catchable, so "assert no error" cannot be written
# directly. Each mechanism below catches a different shadow of one:
#   1. RESIDUE (test 3)  — after teardown no rider still holds a freed reference. An
#      aborted `_restore` leaves its array full, so the abort is visible as state.
#   2. BEHAVIOUR (test 4) — the survivor of a partial free is actually restored. This
#      is the regression proper, and the one that fails when the fix is reverted.
#   3. SOURCE (test 6)   — no file in either directory binds a dynamically-sourced
#      value into a typed Object slot at all. This is the only one that covers a
#      modifier nobody has written yet, and it is why it is worth its false-positive
#      surface. `slice_test_elites` already reads rider source for the HP rule, so
#      source-as-invariant is an established idiom here rather than a new one.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ───────
# Failures accumulate on the MEMBER `_fails` and each test records a COMPLETION
# SENTINEL as its last line, so a test aborted half-way — by exactly the class of fault
# this suite is about — fails the suite BY ABSENCE rather than reading as "found zero
# failures". Test 1 is occurrence-rate armour on top of that: every invariant below is
# trivially true of an empty file list.
extends SceneTree

const ELITE_DIR: String = "res://scripts/combat/elitemods/"
const BOSS_DIR: String = "res://scripts/combat/bossmods/"
const HERALD: String = ELITE_DIR + "EliteHerald.gd"

## The family as it stands. NOT the list under test — the list under test is discovered
## — but a floor under the discovery, so a `DirAccess` that silently returns nothing
## (an export template, a moved directory) fails loudly instead of passing vacuously.
const MIN_RIDERS: int = 13
## Names that must be found. If one of these disappears the discovery is broken, not
## the roster: both are read from the registries by name elsewhere in the codebase.
const MUST_FIND: Array[String] = ["EliteHerald.gd", "ModVoidTouched.gd"]

## Variant (value) types, which cannot hold a freed instance and so cannot fault.
## Everything NOT in here is checked against ClassDB and the global class list.
const VALUE_TYPES: Array[String] = [
	"Variant", "Array", "Dictionary", "String", "StringName", "NodePath", "Color",
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Rect2", "Rect2i",
	"Transform2D", "Transform3D", "Basis", "Quaternion", "AABB", "Plane", "RID",
	"Callable", "Signal", "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
	"PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
	"PackedVector2Array", "PackedVector3Array", "PackedColorArray",
]

const TESTS: Array[String] = [
	"discovery_found_the_whole_family",
	"every_rider_instantiates_and_tears_down",
	"no_rider_holds_a_freed_reference_after_teardown",
	"herald_restores_the_survivors_when_a_target_dies",
	"restore_is_idempotent_and_safe_when_empty",
	"no_rider_binds_a_dynamic_value_into_a_typed_slot",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false
var _files: Array[String] = []          # ["res://.../EliteHerald.gd", ...]
var _arena: Node2D = null


## A body just enemy-shaped enough for a rider to ride: the fields the affixes borrow
## and the two signals they connect to.
##
## ⚠ IT MUST NOT HAVE `current_phase`. That method is how BOTH families spot a boss —
## `EliteHerald._call_out` skips anything carrying it ("never the floor's guardian: no
## ordinary enemy has it"), and `Encounter` uses the same test. A single shared stub
## with `current_phase` on it therefore made the herald lift NOTHING and quietly turned
## the regression test below into a test of an empty room. The boss half gets its own
## subclass instead, which is also the more faithful shape.
class _BodyStub extends Node2D:
	signal phase_changed(p: int)
	signal defeated()
	var hp: int = 100
	var max_hp: int = 100
	var move_speed: float = 100.0
	var touch_damage: int = 5
	var body_scale: float = 1.0
	var _cd_speed: float = 1.0
	var _attack_cd: float = 1.0
	var _attack_cooldown: float = 1.0
	var _attack_state: int = 0
	var _busy: bool = false
	var _knockback: Vector2 = Vector2.ZERO
	var _evade_cd: float = 0.0
	var _smart_dodge: bool = false
	var _can_deflect: bool = false
	var _evade_reflex: float = 1.0
	var _react_delay: float = 0.1


## The boss half: the same body plus the accessor every boss rider probes for by name.
class _BossStub extends _BodyStub:
	func current_phase() -> int:
		return 1


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _run() -> void:
	_arena = Node2D.new()
	_arena.name = "Arena"
	root.add_child(_arena)

	_files = _discover()
	_test_discovery()
	_test_every_rider_tears_down()
	_test_no_freed_residue()
	_test_herald_restores_survivors()
	_test_restore_is_idempotent()
	_test_source_has_no_typed_binds()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Rider teardown tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Rider teardown tests: all PASS")
		quit(0)


# ═════════════════════════════════════════════════════════════════════ discovery
func _discover() -> Array[String]:
	var out: Array[String] = []
	for dir: String in [ELITE_DIR, BOSS_DIR]:
		var d: DirAccess = DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var n: String = d.get_next()
		while n != "":
			if n.ends_with(".gd"):
				out.append(dir + n)
			n = d.get_next()
		d.list_dir_end()
	out.sort()
	return out


## OCCURRENCE-RATE ARMOUR. Every other test here iterates `_files`; all of them are
## vacuously green if it is empty. This repo has already shipped a floor-geometry suite
## that stayed green through three bugs which deleted the whole ledge skyline, for
## exactly that reason.
func _test_discovery() -> void:
	_expect(_files.size() >= MIN_RIDERS,
		"discovery found %d rider scripts, expected at least %d — DirAccess returned nothing "
		% [_files.size(), MIN_RIDERS] + "or a directory moved, and every test below is "
		+ "vacuously green when this list is empty")
	for want: String in MUST_FIND:
		var found: bool = false
		for f: String in _files:
			if f.ends_with(want):
				found = true
		_expect(found, "discovery did not find %s" % want)
	_completes("discovery_found_the_whole_family")


## Build one rider of `path`, parented to a fresh stub body inside the arena, and give
## it frames so its deferred `_setup` runs (both base classes defer setup to the first
## `_process` — see the rule blocks at the top of EliteRider / BossModRider).
func _mount(path: String) -> Array:
	var gs: GDScript = load(path) as GDScript
	if gs == null:
		return []
	# Boss riders get the boss-shaped stub; elite riders must NOT (see _BodyStub).
	var body: _BodyStub = _BossStub.new() if path.begins_with(BOSS_DIR) else _BodyStub.new()
	body.add_to_group("enemy")
	_arena.add_child(body)
	var rider: Node = gs.new()
	rider.name = "Rider_" + path.get_file().get_basename()
	# Both attach paths stamp these before the node enters the tree; a rider that reads
	# `affix_id` / `modifier_id` in `_setup` must find the same shape a real one does.
	rider.set("affix_id", "herald")
	rider.set("modifier_id", "void_touched")
	rider.set("affix_ctx", {})
	rider.set("modifier_ctx", {})
	body.add_child(rider)
	return [body, rider]


# ══════════════════════════════════════════════ 2. it survives losing its target
## THE TEARDOWN ORDER THAT BROKE THE HERALD, applied to every rider in the family: the
## body a rider is riding is freed FIRST, and the rider leaves the tree afterwards. On
## a floor transition that is not an edge case, it is the normal sequence.
func _test_every_rider_tears_down() -> void:
	var built: int = 0
	for path: String in _files:
		var pair: Array = _mount(path)
		if pair.is_empty():
			_expect(false, "could not load rider script %s" % path)
			continue
		built += 1
		var body: Node = pair[0]
		var rider: Node = pair[1]
		# The rider's target dies out from under it, then the rider goes. `free()` rather
		# than `queue_free()` so the ordering is deterministic instead of frame-dependent.
		body.remove_child(rider)
		body.free()
		rider.free()
	_expect(built == _files.size(),
		"every discovered rider was built (%d of %d)" % [built, _files.size()])
	_completes("every_rider_instantiates_and_tears_down")


# ═══════════════════════════════════════════ 3. nothing keeps a dead reference
## THE GENERIC RESIDUE CHECK, and the reason it catches an abort it cannot see.
##
## A GDScript runtime error is not catchable, so this suite cannot assert "no error was
## printed". What it CAN assert is the state an aborted teardown leaves behind: the old
## `_restore` faulted on its first dead row, which aborted the function, which meant
## `_lifted.clear()` never ran — so the array was still full afterwards. Any rider that
## caches nodes and fails to drain them on the way out fails here the same way, without
## this file knowing that rider exists or what its members are called.
func _test_no_freed_residue() -> void:
	var checked: int = 0
	for path: String in _files:
		var pair: Array = _mount(path)
		if pair.is_empty():
			continue
		var body: Node = pair[0]
		var rider: Node = pair[1]
		# Give the herald something to hold, through its own real code path, so this is
		# not a test of an empty container. Riders with nothing to cache simply pass.
		if rider.has_method("_call_out"):
			var victim := _BodyStub.new()
			victim.add_to_group("enemy")
			_arena.add_child(victim)
			victim.global_position = body.global_position + Vector2(60.0, 0.0)
			rider.call("_call_out")
			victim.free()
		body.remove_child(rider)
		body.free()
		checked += 1
		var residue: Array[String] = _freed_residue(rider)
		_expect(residue.is_empty(),
			"%s still holds freed references after teardown: %s — a teardown that "
			% [path.get_file(), ", ".join(residue)]
			+ "faults part-way ABORTS and leaves its cache full, which is how the "
			+ "floor-10 crash also left the room permanently buffed")
		rider.free()
	_expect(checked >= MIN_RIDERS, "residue was checked on %d riders" % checked)
	_completes("no_rider_holds_a_freed_reference_after_teardown")


## Every script member of `rider` that still points at a freed instance, named. Walks
## `get_property_list()` rather than a hand-written member list so it needs no knowledge
## of any particular rider — including one added after this file was written.
func _freed_residue(rider: Node) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in rider.get_property_list():
		# ⚠ `enemy` / `boss` ARE EXEMPT, AND THAT IS THE FAMILY'S ACTUAL CONTRACT.
		# A rider never nulls its own target pointer on the way out; it guards every
		# single use of it instead (`EliteRider._process` returns early on an invalid
		# enemy, `is_dead()` answers true, every accessor checks). Requiring it to be
		# nulled would fail all thirteen riders for obeying the design. What this test
		# is looking for is a rider's own CACHE of OTHER bodies — the `_lifted` shape —
		# surviving a teardown, because that is what an aborted `_restore` leaves behind.
		if String(p.get("name", "")) in ["enemy", "boss"]:
			continue
		# Script members only: `usage` carries STORAGE for `var` declarations, and the
		# engine's own Node properties are neither ours nor interesting here.
		if int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name: String = String(p.get("name", ""))
		var v: Variant = rider.get(name)
		match typeof(v):
			TYPE_OBJECT:
				# ⚠ NOT `v == null` — that is true for a freed instance too (measured),
				# which would hide exactly what this is looking for.
				if not is_instance_valid(v):
					out.append(name)
			TYPE_ARRAY:
				for item: Variant in (v as Array):
					if _is_dead_ref(item):
						out.append(name)
						break
			TYPE_DICTIONARY:
				for k: Variant in (v as Dictionary):
					if _is_dead_ref((v as Dictionary)[k]):
						out.append(name)
						break
	return out


## True for a value that IS an object reference and is dead. Rows in these caches are
## usually dictionaries (`_lifted` holds `{n, spd, cd}`), so one level of nesting is
## unwrapped — the herald's residue lives there and nowhere else.
func _is_dead_ref(item: Variant) -> bool:
	if typeof(item) == TYPE_OBJECT:
		return not is_instance_valid(item)
	if typeof(item) == TYPE_DICTIONARY:
		for k: Variant in (item as Dictionary):
			var inner: Variant = (item as Dictionary)[k]
			if typeof(inner) == TYPE_OBJECT and not is_instance_valid(inner):
				return true
	return false


# ══════════════════════════════════════════════════ 4. THE REGRESSION PROPER
## Two bodies lifted, ONE of them freed. This is the case the shipped code got wrong in
## the way that mattered: the fault on the dead row aborted `_restore`, so the SURVIVOR
## was never put back and stayed quickened for the rest of the run.
##
## ⚠ THIS IS THE TEST TO REVERT AGAINST. Put `var e: Node = row["n"]` back in
## `EliteHerald._restore` and this fails on both assertions; the residue test above
## fails alongside it.
func _test_herald_restores_survivors() -> void:
	var pair: Array = _mount(HERALD)
	if pair.is_empty():
		_expect(false, "could not mount EliteHerald")
		return
	var body: Node = pair[0]
	var rider: Node = pair[1]

	var doomed := _BodyStub.new()
	doomed.add_to_group("enemy")
	_arena.add_child(doomed)
	doomed.global_position = body.global_position + Vector2(40.0, 0.0)
	var survivor := _BodyStub.new()
	survivor.add_to_group("enemy")
	_arena.add_child(survivor)
	survivor.global_position = body.global_position + Vector2(80.0, 0.0)
	var base_speed: float = survivor.move_speed
	var base_cd: float = survivor._cd_speed

	rider.call("_call_out")
	var lifted: Array = rider.get("_lifted")
	_expect(lifted.size() >= 2,
		"the herald lifted both bodies (got %d) — with fewer than two this test cannot "
		% lifted.size() + "distinguish 'restored the survivor' from 'had nothing to do'")
	_expect(survivor.move_speed > base_speed,
		"the survivor was actually sped up before the teardown (%.1f vs %.1f)"
		% [survivor.move_speed, base_speed])

	# THE ORDER THAT BROKE IT: a lifted body dies, then the rider leaves the tree.
	doomed.free()
	body.remove_child(rider)          # -> _exit_tree -> _restore

	_expect(is_equal_approx(survivor.move_speed, base_speed),
		"the SURVIVOR's move_speed was restored (%.1f, expected %.1f) — a fault on the "
		% [survivor.move_speed, base_speed] + "dead row aborts _restore and everything "
		+ "queued behind it stays buffed for the rest of the run")
	_expect(is_equal_approx(survivor._cd_speed, base_cd),
		"the survivor's _cd_speed was restored (%.2f, expected %.2f)"
		% [survivor._cd_speed, base_cd])
	_expect((rider.get("_lifted") as Array).is_empty(),
		"_lifted was drained by _restore — a non-empty one means the function aborted "
		+ "before its clear, which is the floor-10 signature")

	rider.free()
	survivor.free()
	body.free()
	_completes("herald_restores_the_survivors_when_a_target_dies")


# ═══════════════════════════════════════ 5. safe to call twice, safe with nothing
## `_tick` calls `_restore` when the surge window closes and `_exit_tree` calls it again
## on the way out, so a herald that dies on the same frame its window expires runs both.
## Restoring twice from stored originals is harmless only if the second call is a no-op:
## if the rows survived the first pass they would be re-applied, and any future variant
## that stored deltas instead would drift. Pinned so the drain-first shape cannot be
## quietly refactored back into a walk-then-clear.
func _test_restore_is_idempotent() -> void:
	var pair: Array = _mount(HERALD)
	if pair.is_empty():
		_expect(false, "could not mount EliteHerald")
		return
	var body: Node = pair[0]
	var rider: Node = pair[1]

	# Safe with nothing to restore, before anything has been lifted at all.
	rider.call("_restore")
	_expect((rider.get("_lifted") as Array).is_empty(),
		"_restore on a herald that has lifted nothing is a no-op")

	var target := _BodyStub.new()
	target.add_to_group("enemy")
	_arena.add_child(target)
	target.global_position = body.global_position + Vector2(50.0, 0.0)
	var base_speed: float = target.move_speed

	rider.call("_call_out")
	rider.call("_restore")
	var after_one: float = target.move_speed
	rider.call("_restore")
	rider.call("_restore")
	_expect(is_equal_approx(target.move_speed, after_one),
		"a second and third _restore changed nothing (%.1f -> %.1f)"
		% [after_one, target.move_speed])
	_expect(is_equal_approx(target.move_speed, base_speed),
		"one _restore put the body back exactly (%.1f, expected %.1f)"
		% [target.move_speed, base_speed])

	rider.free()
	target.free()
	body.free()
	_completes("restore_is_idempotent_and_safe_when_empty")


# ══════════════════════════════════════════ 6. the shape itself, at source level
## THE ONLY TEST HERE THAT COVERS A MODIFIER NOBODY HAS WRITTEN YET.
##
## Tests 2–5 can only exercise riders that exist and paths this file knows how to
## drive. This one reads every discovered file and forbids the CONSTRUCT, so the next
## rider is covered whether or not anyone remembers to test it.
##
## THE RULE: a value whose provenance is dynamic — a container subscript, a `pop_*`, a
## `call()`, a `get()`, a `get_meta()` — may not be bound into a statically typed
## OBJECT-derived slot. That binding faults on a freed instance instead of yielding
## null, one line before any guard, and it is the entire floor-10 bug.
##
## The sanctioned escape is `EliteRider.live_node` / `BossModRider.live_node`, which
## takes a Variant (so the binding cannot fault) and answers null for a freed instance.
##
## ── WHAT THIS DELIBERATELY DOES NOT CATCH, stated so nobody trusts it too far ──
##   * Object-typed slots written from a helper this file cannot see through. If a
##     future rider wraps its own accessor, the lint reads it as safe.
##   * Value-typed targets (`var v: Vector2 = enemy.get("velocity")`). Correct to skip:
##     a Variant type cannot hold a freed instance, so the binding cannot fault.
##   * Typed slots assigned inside a lambda body on one line.
## It is a shape check, not a proof. Tests 3 and 4 are the behavioural half.
func _test_source_has_no_typed_binds() -> void:
	var decl := RegEx.new()
	decl.compile("^\\s*(?:@\\w+\\s+)?var\\s+(\\w+)\\s*:\\s*([A-Za-z_]\\w*)\\s*(?:=\\s*(.+?))?\\s*$")
	var assign := RegEx.new()
	assign.compile("^\\s*(\\w+)\\s*=\\s*(.+?)\\s*$")
	var prov := RegEx.new()
	prov.compile("\\]\\s*$|\\.pop_front\\(\\)|\\.pop_back\\(\\)|\\.pop_at\\(|\\.call\\(|\\.get\\(|\\.get_meta\\(")

	var scanned: int = 0
	var flagged: int = 0
	for path: String in _files:
		var src: String = _read(path)
		if src.is_empty():
			_expect(false, "could not read %s for the source scan" % path)
			continue
		scanned += 1
		# Object-typed names declared in THIS file, so a bare re-assignment to one of
		# them later (`node = host.call(...)`) is caught as well as its declaration.
		var typed: Dictionary = {}
		var line_no: int = 0
		for line: String in src.split("\n"):
			line_no += 1
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#") or stripped.is_empty():
				continue
			var rhs: String = ""
			var tname: String = ""
			var dm: RegExMatch = decl.search(line)
			if dm != null:
				tname = dm.get_string(2)
				if _is_object_type(tname):
					typed[dm.get_string(1)] = tname
				rhs = dm.get_string(3)
			else:
				var am: RegExMatch = assign.search(line)
				if am == null or not typed.has(am.get_string(1)):
					continue
				tname = String(typed[am.get_string(1)])
				rhs = am.get_string(2)
			if rhs.is_empty() or not _is_object_type(tname):
				continue
			if rhs.contains("live_node("):
				continue                       # the sanctioned laundering
			if prov.search(rhs) == null:
				continue
			flagged += 1
			_expect(false,
				("%s:%d binds a dynamically-sourced value into a typed `%s` slot: `%s`. "
				+ "That binding FAULTS on a freed instance instead of yielding null, one "
				+ "line before any is_instance_valid guard can run — it is the floor-10 "
				+ "crash. Wrap it: `live_node(...)`.")
				% [path.get_file(), line_no, tname, rhs.substr(0, 60)])
	_expect(scanned >= MIN_RIDERS,
		"the source scan actually read %d files (an unread file is a silent pass)" % scanned)
	_expect(flagged == 0, "%d typed binds found across the family" % flagged)
	_completes("no_rider_binds_a_dynamic_value_into_a_typed_slot")


## True when `t` names an Object-derived type — the only kind that can hold a freed
## instance and therefore the only kind whose binding can fault.
##
## Two sources, both automatic. ClassDB covers engine classes (and cleanly excludes the
## Variant value types, which are not in it at all — `ClassDB.class_exists("Vector2")`
## is false). `ProjectSettings.get_global_class_list()` covers every `class_name` in the
## project, all of which are Object-derived by definition since a script must extend
## Object. Nothing here is hand-listed, so a new project class is understood on sight.
func _is_object_type(t: String) -> bool:
	if VALUE_TYPES.has(t):
		return false
	if ClassDB.class_exists(t):
		return true
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if String(entry.get("class", "")) == t:
			return true
	return false


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s
