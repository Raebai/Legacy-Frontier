# Run: godot --headless --path godot-project --script tools/slice_test_bossnet.gd
#
# DOES EVERY BOSS ACTUALLY TALK TO THE WIRE?
#
# ── the gap this exists to stop coming back ────────────────────────────────────
# `Boss.gd` grew a co-op helper — `_bfx(kind, data)` — that hands every client a
# damage-free twin of a spectacle, and the Ashen Guardian's seven attacks were
# wired through it. Then three more bosses (Scribble / Cartographer / Illuminator)
# and six modifier riders landed with ZERO network references between them. On every
# floor drawing a new artist, which is most of them, a client watched a boss attack
# invisibly — and NOTHING failed. No error, no red suite: the host's screen was
# correct, and the host is the only screen a single process has.
#
# `python-tools/coop_smoketest.sh` is what proves the packets actually cross two
# processes. This suite is the cheap half: it proves every attack and every rider
# ASKS. A new boss added without broadcasts fails here in ~2 s instead of surviving
# to a two-phone playtest.
#
# ── how it watches ────────────────────────────────────────────────────────────
# `Boss._bfx` is gated on `_net != null and _net.is_host()`. Under `--script` there
# are no autoloads, so a real boss's `_net` is null and `_bfx` is a silent no-op —
# which is exactly the seam a recording Net can be dropped into. That recorder is
# `tools/_boss_net_spy.gd`, and it SUBCLASSES the shipped `Net.gd` rather than
# re-declaring the handful of members this suite happens to think a boss uses; read
# the ⚠ block at the top of that file for what the hand-written version got wrong.
#
# ⚠ THE FIXTURE IS A REAL BOSS, NOT A HAND-WRITTEN ONE. A stub boss declaring the
# members this suite happens to read would be a fixture more generous than reality —
# the failure mode that let `SpellHandoff` ask heroes for `bot_driven`/`_bot`,
# members that exist nowhere, and abort every call silently. So every boss here is
# built through `Encounter.build_enemy_from_data`, the same function co-op replicates.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ─────────
# Failures accumulate on the MEMBER `_fails` and each test records a COMPLETION
# SENTINEL, so a test aborted half-way by a moved member fails the suite BY ABSENCE
# rather than reading as "found zero failures". Never `failed += _test_x()`.
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"
const NET_PATH: String = "res://scripts/Net.gd"
## The recording Net subclass. Loaded at RUNTIME on purpose — see the ⚠ block in
## that file for why naming it at this suite's compile time kills the whole run.
const SPY_PATH: String = "res://tools/_boss_net_spy.gd"

const GUARDIAN: String = "guardian"
const SCRIBBLE: String = "scribble"
const CARTOGRAPHER: String = "cartographer"
const ILLUMINATOR: String = "illuminator"


## Every artist that is NOT the base Ashen Guardian — i.e. every `TowerBoss`
## subclass on the roster. Read off `BossRoster` rather than listed here, so a boss
## added tomorrow is covered by this suite the moment its row lands. The Guardian is
## excluded because it has its own dedicated test above (it is the base class, and
## the question there is "did the roster break the original", not "does the new one
## broadcast").
func _new_boss_ids() -> Array[String]:
	var out: Array[String] = []
	for bid: String in BossRoster.ids():
		if bid != GUARDIAN:
			out.append(bid)
	return out

## Longest a single attack may take to put something on the wire. Lane-telegraphed
## attacks (the streak, the ruled line, the gilding sweep) only fire when their tell
## expires, and that tell is up to 0.75 s — plus the frenzy, which staggers four
## streaks 0.46 s apart. Comfortably over the worst case, and the wait breaks the
## instant a broadcast lands, so a healthy suite never spends it.
const ATTACK_DEADLINE: float = 2.6

## Boss-fx kinds that legitimately build NO node on the receiving peer: they are a
## screen beat and a rig flash. Any OTHER kind must produce something visible, or
## `Net._client_boss_fx` has no arm for it and the twin silently does nothing.
const NODELESS_KINDS: Array[String] = ["beat", "dash"]

const TESTS: Array[String] = [
	"guardian_still_broadcasts",
	"every_new_boss_attack_broadcasts",
	"riders_broadcast_what_only_the_host_built",
	"deterministic_riders_stay_off_the_wire",
	"every_emitted_kind_has_a_receiving_arm",
	"the_bar_carries_the_bosss_own_name",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _arena: Node2D = null
var _hero: Node2D = null
## Every kind any boss or rider emitted during this run — fed to the arm check.
var _emitted_kinds: Dictionary = {}


## Minimal hero stand-in: a Node2D in group "hero" with hp + take_damage. Same shape
## as the one in slice_test_bossmods.gd — bosses aim at it and hit it.
class HeroStub extends Node2D:
	var hp: int = 100
	var max_hp: int = 100
	func take_damage(amount: int) -> void:
		hp = maxi(hp - amount, 0)


func _initialize() -> void:
	_run()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _settle(n: int = 3) -> void:
	for i: int in n:
		await process_frame


func _run() -> void:
	_arena = Node2D.new()
	root.add_child(_arena)
	_hero = HeroStub.new()
	_hero.add_to_group("hero")
	_arena.add_child(_hero)
	_hero.global_position = Vector2(520.0, 300.0)
	await process_frame

	await _test_guardian_still_broadcasts()
	await _test_every_new_boss_attack_broadcasts()
	await _test_riders_broadcast_what_only_the_host_built()
	await _test_deterministic_riders_stay_off_the_wire()
	await _test_every_emitted_kind_has_a_receiving_arm()
	await _test_the_bar_carries_the_bosss_own_name()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Boss net tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Boss net tests: all PASS")
		quit(0)


# ------------------------------------------------------------------- utilities
## Build a boss the way the game does: through Encounter's single construction path,
## from a spawn dictionary. That is the function co-op replicates, so testing through
## it is testing the real thing rather than a convenient approximation.
func _build(bid: String, mods: Array = []) -> Node:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var data: Dictionary = {
		"boss": true, "hp": 600, "spd": 66.0, "touch": 26, "bscale": 1.0,
		"x": 900.0, "y": 300.0,
	}
	if bid != "":
		data["bid"] = bid
	if not mods.is_empty():
		data["mods"] = mods
	var e: Node = enc.build_enemy_from_data(data)
	enc.free()
	_arena.add_child(e)
	return e


## Give `boss` a recording Net and hand the spy back.
func _bug(boss: Node) -> Node:
	var spy: Node = load(SPY_PATH).new()
	spy.name = "NetSpy"
	_arena.add_child(spy)          # in the tree so `is_instance_valid` stays true
	boss.set("_net", spy)
	for c: Node in boss.get_children():
		if String(c.name).begins_with("Mod_"):
			c.set("_net", spy)     # riders read their own `_net` for the authority gate
	return spy


## Wait until the spy hears something, or the deadline expires. Returns the kinds
## recorded. Breaking early is what keeps a healthy run fast.
func _await_broadcast(spy: Node) -> Array[String]:
	var waited: float = 0.0
	while (spy.get("calls") as Array).is_empty() and waited < ATTACK_DEADLINE:
		await process_frame
		waited += 1.0 / 60.0
	await _settle(2)
	return _kinds_of(spy)


## The spy's recorded kinds, typed. Reached by `.call` because the spy is loaded at
## runtime and has no compile-time type here (see SPY_PATH).
func _kinds_of(spy: Node) -> Array[String]:
	var out: Array[String] = []
	for k in (spy.call("kinds") as Array):
		out.append(String(k))
	return out


func _note_kinds(kinds: Array[String]) -> void:
	for k: String in kinds:
		_emitted_kinds[k] = true


## Free a boss AND everything it left lying around. Spectacles hold their caster as
## `caster_node` and SpellReactor casts that reference every frame, so freeing a boss
## with live zones/beams produces a storm of "freed object" noise that buries real
## failures. Test hygiene, not a product bug.
func _kill(boss: Node) -> void:
	if is_instance_valid(boss):
		boss.free()
	for c: Node in _arena.get_children():
		if c == _hero or not is_instance_valid(c):
			continue
		if c.has_method("current_phase") or c.has_method("broadcast_boss_fx"):
			continue
		c.free()


## Every attack id this boss can choose, across all three phases, de-duplicated and
## in a stable order. Read off the boss itself so a NEW attack is covered the moment
# it is added to a phase list — which is the point.
func _all_attack_ids(boss: Node) -> Array[String]:
	var out: Array[String] = []
	for ph: int in [1, 2, 3]:
		for id in boss.call("_phase_attack_ids", ph):
			var s: String = String(id)
			if not out.has(s):
				out.append(s)
	return out


# ------------------------------------------------------------------- the tests
## REGRESSION. The Guardian was the one boss already wired, and the roster work must
## not have quietly unhooked it while re-pointing the bar and the name card.
func _test_guardian_still_broadcasts() -> void:
	var expected: Dictionary = {
		"slam": "slam", "pillars": "pillar", "beam": "beam", "rays": "ray",
		"meteor": "meteor", "convergence": "convergence", "nova": "nova",
	}
	for id in expected:
		var b: Node = _build(GUARDIAN)
		await _settle(2)
		var spy: Node = _bug(b)
		b.call("_enter_phase", 1)
		b.call("_run_attack", String(id))
		var kinds: Array[String] = await _await_broadcast(spy)
		_note_kinds(kinds)
		_expect(kinds.has(String(expected[id])),
			"the Guardian's '%s' still broadcasts '%s' (got %s)" % [id, expected[id], str(kinds)])
		_kill(b)
	# `summon` is the one Guardian attack with nothing to broadcast: adds go through
	# `Arena.spawn_extra_enemy`, i.e. the MultiplayerSpawner, so the bodies replicate
	# themselves. Asserted explicitly so nobody "fixes" it into a double spawn.
	var s: Node = _build(GUARDIAN)
	await _settle(2)
	var ssp: Node = _bug(s)
	s.call("_enter_phase", 2)
	(ssp.get("calls") as Array).clear()
	s.call("_atk_summon")
	await _settle(3)
	_expect((ssp.get("calls") as Array).is_empty(),
		"'summon' broadcasts NOTHING — the adds already replicate through the spawner")
	_kill(s)
	_completes("guardian_still_broadcasts")


## THE GAP ITSELF. Every attack of every new boss, in every phase, must put something
## on the wire. Driven off `_phase_attack_ids`, so an attack added tomorrow is covered
## the moment it joins a phase list.
func _test_every_new_boss_attack_broadcasts() -> void:
	for bid: String in _new_boss_ids():
		var probe: Node = _build(bid)
		await _settle(2)
		var ids: Array[String] = _all_attack_ids(probe)
		_kill(probe)
		_expect(ids.size() >= 4, "'%s' has a real moveset to check (%d ids)" % [bid, ids.size()])
		for id: String in ids:
			var b: Node = _build(bid)
			await _settle(2)
			var spy: Node = _bug(b)
			b.call("_enter_phase", 2)
			(spy.get("calls") as Array).clear()
			b.call("_run_attack", id)
			var kinds: Array[String] = await _await_broadcast(spy)
			_note_kinds(kinds)
			_expect(not kinds.is_empty(),
				"%s.'%s' broadcasts SOMETHING — otherwise a client fights it blind" % [bid, id])
			_kill(b)
	_completes("every_new_boss_attack_broadcasts")


## The riders whose work only ever happened on the host.
func _test_riders_broadcast_what_only_the_host_built() -> void:
	# VOID-TOUCHED: the rot field is no-go ground, and no-go ground you cannot see is
	# damage you were never shown.
	var v: Node = _build(GUARDIAN, ["void_touched"])
	await _settle(3)
	var vr: Node = v.get_node_or_null("Mod_void_touched")
	_expect(vr != null, "the void-touched rider attached")
	if vr != null:
		var spy: Node = _bug(v)
		v.call("_enter_phase", 1)
		(spy.get("calls") as Array).clear()
		vr.call("_tick", 9.0)
		await _settle(3)
		_note_kinds(_kinds_of(spy))
		_expect(_kinds_of(spy).has("zone"), "void-touched broadcasts its field (got %s)" % str(_kinds_of(spy)))
	_kill(v)

	# UNFINISHED: the destination POSITION replicates on its own, so what a client is
	# missing is the WARNING — and "step off the mark" is the whole play against it.
	var u: Node = _build(GUARDIAN, ["unfinished"])
	await _settle(3)
	var ur: Node = u.get_node_or_null("Mod_unfinished")
	_expect(ur != null, "the unfinished rider attached")
	if ur != null:
		var spy2: Node = _bug(u)
		u.call("_enter_phase", 1)
		u.set("_busy", false)
		(spy2.get("calls") as Array).clear()
		ur.call("_tick", 30.0)
		await _settle(3)
		_note_kinds(_kinds_of(spy2))
		_expect(_kinds_of(spy2).has("circle"),
			"unfinished broadcasts THE REDRAW MARK (got %s)" % str(_kinds_of(spy2)))
	_kill(u)

	# SPLIT: the copies replicate through the spawner; the BEAT that explains them did
	# not, so a client watched a boss die and two bodies appear in silence.
	var s: Node = _build(SCRIBBLE, ["split"])
	await _settle(3)
	var sr: Node = s.get_node_or_null("Mod_split")
	_expect(sr != null, "the split rider attached")
	if sr != null:
		var spy3: Node = _bug(s)
		s.call("_enter_phase", 2)
		(spy3.get("calls") as Array).clear()
		sr.call("_on_defeated")
		await _settle(3)
		_note_kinds(_kinds_of(spy3))
		_expect(_kinds_of(spy3).has("beat"), "split broadcasts its beat (got %s)" % str(_kinds_of(spy3)))
	for c: Node in _arena.get_children():
		if c != _hero and c.has_method("current_phase"):
			_kill(c)
	await _settle(2)

	# MIRRORED: the nastiest modifier in the set answering your own ult is unplayable
	# if it is invisible. Two halves — the sigil that says "your thing is coming back"
	# and the spell itself — and both were host-only spawns.
	var m: Node = _build(CARTOGRAPHER, ["mirrored"])
	await _settle(3)
	var mr: Node = m.get_node_or_null("Mod_mirrored")
	_expect(mr != null, "the mirrored rider attached")
	if mr != null:
		var spy4: Node = _bug(m)
		m.call("_enter_phase", 2)
		# Hand it something to mirror rather than waiting for a hero to cast: the
		# observation half has its own coverage in slice_test_bossmods, and what is
		# under test here is the WIRE, not the reverse spell lookup.
		var lib: GDScript = load("res://scripts/combat/SpellLibrary.gd") as GDScript
		mr.set("_spell", (lib.call("build_all") as Array)[0])
		(spy4.get("calls") as Array).clear()
		mr.call("_begin_mirror")
		await _settle(3)
		_note_kinds(_kinds_of(spy4))
		_expect(_kinds_of(spy4).has("circle"),
			"mirrored broadcasts THE TELL (got %s)" % str(_kinds_of(spy4)))
		(spy4.get("calls") as Array).clear()
		mr.call("_fire")
		await _settle(3)
		_note_kinds(_kinds_of(spy4))
		_expect(_kinds_of(spy4).has("spell"),
			"mirrored broadcasts THE ANSWER (got %s)" % str(_kinds_of(spy4)))
	_kill(m)
	await _settle(2)
	_completes("riders_broadcast_what_only_the_host_built")


## THE OTHER HALF OF THE RULE, and the easier one to get wrong: do not pay a packet
## for something both peers already compute. ENRAGED's dressing runs on every peer
## and its early gates ride `Boss._enter_phase`'s own phase broadcast; PATIENT's wash
## runs on every peer and its wake is derived from `hp`, which the enemy synchronizer
## replicates. Either one broadcasting would draw itself TWICE on the client.
func _test_deterministic_riders_stay_off_the_wire() -> void:
	var e: Node = _build(GUARDIAN, ["enraged"])
	await _settle(3)
	var er: Node = e.get_node_or_null("Mod_enraged")
	_expect(er != null, "the enraged rider attached")
	if er != null:
		var spy: Node = _bug(e)
		e.call("_enter_phase", 1)
		(spy.get("calls") as Array).clear()
		e.set("hp", int(float(int(e.get("max_hp"))) * 0.70))
		er.call("_tick", 0.016)
		await _settle(2)
		_expect(int(e.call("current_phase")) == 2, "enraged still moves the gate early")
		var noise: Array[String] = []
		for k: String in _kinds_of(spy):
			noise.append(k)
		_expect(noise.is_empty(),
			"ENRAGED sends no boss-fx — its escalation crosses on the phase wire (got %s)" % str(noise))
	_kill(e)

	var p: Node = _build(GUARDIAN, ["patient"])
	await _settle(3)
	var pr: Node = p.get_node_or_null("Mod_patient")
	_expect(pr != null, "the patient rider attached")
	if pr != null:
		var spy2: Node = _bug(p)
		p.call("_enter_phase", 1)
		(spy2.get("calls") as Array).clear()
		p.call("take_damage", 5)
		pr.call("_tick_visual", 0.016)
		await _settle(2)
		_expect(not bool(pr.get("_dormant")),
			"PATIENT wakes off replicated hp in _tick_visual, so BOTH peers see it wake")
		_expect((spy2.get("calls") as Array).is_empty(),
			"...and sends nothing, because the trigger is state both peers already hold")
	_kill(p)
	_completes("deterministic_riders_stay_off_the_wire")


## EVERY KIND THAT GOES OUT MUST HAVE AN ARM TO LAND IN. `Net._client_boss_fx` is a
## `match` on a string: a kind with no arm falls through in total silence, which is
## indistinguishable from the bug this whole pass exists to fix. So every kind
## observed above is delivered to a real Net and required to build something.
func _test_every_emitted_kind_has_a_receiving_arm() -> void:
	_expect(_emitted_kinds.size() >= 6,
		"the sweep above actually observed a vocabulary (%d kinds)" % _emitted_kinds.size())
	var net: Node = load(NET_PATH).new()
	net.name = "NetUnderTest"
	root.add_child(net)
	await process_frame
	# `_client_boss_fx` builds into `get_tree().current_scene`; there is no packed
	# scene under `--script`, so point it at the test arena.
	root.get_tree().current_scene = _arena
	var kinds: Array = _emitted_kinds.keys()
	kinds.sort()
	# ⚠ COUNT ARRIVALS, NOT SURVIVORS. `get_child_count()` before/after is the obvious
	# probe and it is wrong: a spectacle handed a world with no collision geometry can
	# resolve its ground, find nothing and free itself inside the same call — which
	# looks identical to "there was no arm at all". The entry signal cannot be fooled
	# by something that leaves again.
	#
	# ⚠ AND THE COUNTER LIVES IN AN ARRAY, NOT AN INT. GDScript lambdas capture by
	# VALUE, so `func(): n += 1` increments a copy and the outer `n` never moves —
	# a counter that silently stays zero, i.e. every arm "missing". A one-element
	# array is captured by reference.
	var arrivals: Array[int] = [0]
	var counter: Callable = func(_n: Node) -> void: arrivals[0] += 1
	_arena.child_entered_tree.connect(counter)
	for k in kinds:
		var kind: String = String(k)
		arrivals[0] = 0
		net.call("_client_boss_fx", kind, _sample_data(kind))
		await _settle(2)
		if NODELESS_KINDS.has(kind):
			continue
		_expect(arrivals[0] > 0,
			"kind '%s' has a receiving arm that BUILDS something (a missing arm is silent)" % kind)
	_arena.child_entered_tree.disconnect(counter)
	root.get_tree().current_scene = null
	net.free()
	for c: Node in _arena.get_children():
		if c != _hero and is_instance_valid(c) and not c.has_method("broadcast_boss_fx"):
			c.free()
	await _settle(2)
	_completes("every_emitted_kind_has_a_receiving_arm")


## A plausible payload for one kind. Deliberately minimal: every arm must survive a
## packet carrying only what it truly needs, because a real one can arrive from an
## older peer that did not send tomorrow's optional key.
func _sample_data(kind: String) -> Dictionary:
	var d: Dictionary = {"pos": Vector2(400.0, 300.0), "col": Color(1, 0.6, 0.2),
		"fx": "fire", "el": 0, "r": 60.0}
	match kind:
		"beam":
			d["dir"] = Vector2.RIGHT
			d["len"] = 600.0
			d["w"] = 30.0
		"root":
			d["aim"] = Vector2.RIGHT
		"circle":
			d["tier"] = 1
			d["hold"] = 0.3
		"spell":
			d["sid"] = "frostpiercer"
			d["pt"] = Vector2(700.0, 300.0)
	return d


## The bar names THIS boss. It used to name one specific boss in a `const`, and the
## roster worked around that by rewriting the label after construction — which meant
## the top of the screen briefly said the wrong name and the fifth boss's author had
## to know to do it again.
func _test_the_bar_carries_the_bosss_own_name() -> void:
	var seen: Dictionary = {}
	for bid: String in BossRoster.ids():
		var b: Node = _build(bid)
		await _settle(2)
		var bar: Node = b.get("_bar")
		_expect(bar != null, "'%s' built a boss bar" % bid)
		if bar != null:
			var title: String = String(b.call("boss_title"))
			_expect(bar.has_method("displayed_name"),
				"BossBar exposes what it is showing (no reaching for a private label)")
			if bar.has_method("displayed_name"):
				_expect(String(bar.call("displayed_name")) == title,
					"the bar says '%s', not somebody else's name (got '%s')"
						% [title, String(bar.call("displayed_name"))])
			_expect(not seen.has(title), "'%s' has its own name on the bar (%s)" % [bid, title])
			seen[title] = true
		_kill(b)
	# The trap itself: a const naming one boss in a four-boss roster.
	var bar_script: GDScript = load("res://scripts/combat/BossBar.gd") as GDScript
	_expect(bar_script != null and bar_script.get("NAME_TEXT") == null,
		"BossBar no longer carries a NAME_TEXT const naming one specific boss")
	_completes("the_bar_carries_the_bosss_own_name")
