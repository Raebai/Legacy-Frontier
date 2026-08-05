# Run: godot --headless --path godot-project --script tools/slice_test_bossmods.gd
#
# THE ROSTER AND THE MODIFIERS, WIRED UP. Where slice_test_bossroster.gd asserts the
# table and the dice, this one spawns real bosses and asserts that:
#   * a spawn dictionary carrying `bid` builds THAT artist, and one without it still
#     builds the Ashspire Guardian (the co-op / legacy compatibility line);
#   * the three new bosses are genuinely different fights, not one fight repainted —
#     distinct names, sizes, cadences and movesets, with no shared attack id;
#   * every modifier's rider attaches and does the thing its name claims.
#
# Bosses are reached by NAME (.get/.call) wherever it costs nothing, but the boss
# scripts themselves are `load()`ed rather than referenced at compile time — the trap
# at the top of tools/slice_test_boss.gd: naming Boss in a test script's own compile
# unit pulls the whole spell chain into early boot, before the autoloads exist.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──────────
# Failures accumulate on the MEMBER `_fails` and each test records a COMPLETION
# SENTINEL, so a test aborted half-way by a moved member fails the suite BY ABSENCE
# rather than reading as "found zero failures".
extends SceneTree

const ENCOUNTER_PATH: String = "res://scripts/combat/Encounter.gd"

const TESTS: Array[String] = [
	"bid_picks_the_artist",
	"bosses_are_different_fights",
	"attach_wires_riders_and_hud",
	"patient_holds_then_wakes",
	"enraged_moves_the_gates",
	"split_carves_and_multiplies",
	"void_touched_opens_ground",
	"unfinished_repositions",
	"quiet_gives_up_the_bar",
	"spawn_boss_carries_the_roll",
	"every_boss_satisfies_the_roster_contract",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _arena: Node2D = null
var _hero: Node2D = null


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
	_hero = _HeroStub.new()
	_hero.add_to_group("hero")
	_arena.add_child(_hero)
	_hero.global_position = Vector2(500.0, 300.0)
	await process_frame

	await _test_bid_picks_the_artist()
	await _test_bosses_are_different_fights()
	await _test_attach_wires_riders_and_hud()
	await _test_patient_holds_then_wakes()
	await _test_enraged_moves_the_gates()
	await _test_split_carves_and_multiplies()
	await _test_void_touched_opens_ground()
	await _test_unfinished_repositions()
	await _test_quiet_gives_up_the_bar()
	await _test_spawn_boss_carries_the_roll()
	await _test_every_boss_satisfies_the_roster_contract()

	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Boss mods tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Boss mods tests: all PASS")
		quit(0)


# ------------------------------------------------------------------- utilities
## Build a boss the way the game does: through Encounter's single construction
## path, from a spawn dictionary. This is the function co-op replicates, so testing
## through it is testing the real thing.
func _build(bid: String, mods: Array = [], extra: Dictionary = {}) -> Node:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var data: Dictionary = {
		"boss": true, "hp": 600, "spd": 66.0, "touch": 26, "bscale": 1.0,
		"x": 900.0, "y": 300.0,
	}
	if bid != "":
		data["bid"] = bid
	if not mods.is_empty():
		data["mods"] = mods
	for k in extra:
		data[k] = extra[k]
	var e: Node = enc.build_enemy_from_data(data)
	enc.free()
	_arena.add_child(e)
	return e


func _rider(boss: Node, mod_id: String) -> Node:
	return boss.get_node_or_null("Mod_" + mod_id)


## Free a boss AND everything it left lying around. Spectacles hold their caster as
## `caster_node`, and SpellReactor casts that reference every frame — so freeing a
## boss while its own zones/beams are still live produces a storm of "trying to cast
## a freed object" out of the reactor. That is test hygiene, not a product bug (in
## the game a boss `_die`s and its spectacles expire on their own timers), but it
## makes real failures unreadable, so tests tidy up after themselves.
func _kill(boss: Node) -> void:
	if is_instance_valid(boss):
		boss.free()
	_clear_spectacles()


## Everything in the arena that is not the hero stub or a live boss.
func _clear_spectacles() -> void:
	for c: Node in _arena.get_children():
		if c == _hero or not is_instance_valid(c):
			continue
		if c.has_method("current_phase"):
			continue
		c.free()


func _count_of_class(cls: String) -> int:
	var n: int = 0
	for c: Node in _arena.get_children():
		var s: Script = c.get_script() as Script
		if s != null and s.resource_path.ends_with(cls + ".gd"):
			n += 1
	return n


# ------------------------------------------------------------------- the tests
## `bid` in the spawn data picks the scene. A dict WITHOUT one still builds the
## Guardian — that is the compatibility line every pre-roster caller (the boss-rush
## path, hand-written harness dicts, old replicated data) depends on.
func _test_bid_picks_the_artist() -> void:
	var cases: Dictionary = {
		BossRoster.SCRIBBLE: "ScribbleBoss.gd",
		BossRoster.CARTOGRAPHER: "CartographerBoss.gd",
		BossRoster.ILLUMINATOR: "IlluminatorBoss.gd",
		BossRoster.GUARDIAN: "Boss.gd",
	}
	for bid in cases:
		var b: Node = _build(String(bid))
		await _settle(2)
		var s: Script = b.get_script() as Script
		_expect(s != null and s.resource_path.ends_with(String(cases[bid])),
			"bid '%s' builds %s (got %s)" % [bid, cases[bid], s.resource_path if s != null else "<none>"])
		_expect(b.has_method("current_phase"),
			"bid '%s' is a Boss (Encounter's clear gate finds it by current_phase)" % bid)
		_expect(b.is_in_group("enemy"), "bid '%s' joins the enemy group" % bid)
		_kill(b)
	var legacy: Node = _build("")
	await _settle(2)
	var ls: Script = legacy.get_script() as Script
	_expect(ls != null and ls.resource_path.ends_with("Boss.gd"),
		"a spawn dict with NO bid still builds the Ashspire Guardian (legacy/co-op line)")
	_kill(legacy)
	# An id that is not in the roster must degrade, never crash a floor.
	var junk: Node = _build("not_a_boss")
	await _settle(2)
	_expect(junk != null and junk.has_method("current_phase"),
		"an unknown bid falls back to a working boss instead of breaking the spawn")
	_kill(junk)
	_completes("bid_picks_the_artist")


## THE POINT OF THE ROSTER. Four bosses only "read as more variety than twenty
## generated ones" if they actually fight differently — so this asserts the things
## that make a fight different rather than the things that make a sprite different.
func _test_bosses_are_different_fights() -> void:
	# THE WHOLE ROSTER, read off the table. This used to be a hand-listed three, which
	# meant a new artist was never asked the question this test exists to ask — and the
	# two size assertions below were literals that had to be bumped by hand, which is
	# how a suite gets edited to accept work instead of judging it.
	var ids: Array[String] = BossRoster.ids()
	var titles: Dictionary = {}
	var heights: Dictionary = {}
	var movesets: Dictionary = {}
	var cadences: Dictionary = {}
	for bid: String in ids:
		var b: Node = _build(bid)
		await _settle(2)
		var title: String = String(b.call("boss_title"))
		_expect(title != "" and not titles.has(title), "'%s' has its own name (%s)" % [bid, title])
		titles[title] = true
		_expect(String(b.call("boss_artist")) != "",
			"'%s' names the artist who drew it — the lore beat is on the card" % bid)
		var rig: Node = b.get_node_or_null("Rig")
		var h: float = float(rig.get("height")) if rig != null else 0.0
		_expect(h > 30.0, "'%s' has a real rig height (%.0f)" % [bid, h])
		heights[snappedf(h, 1.0)] = true
		# Every phase must be a real phase, and the three phases must not be the
		# same list three times.
		var per_phase: Array[String] = []
		for ph: int in [1, 2, 3]:
			var atk: Array = b.call("_phase_attack_ids", ph)
			_expect(atk.size() >= 2, "'%s' phase %d has >= 2 attacks (got %d)" % [bid, ph, atk.size()])
			per_phase.append(",".join(PackedStringArray(atk)))
			for id in atk:
				movesets[String(id)] = bid
		_expect(per_phase[0] != per_phase[2], "'%s' phase 3 is not phase 1 again" % bid)
		# Cadence is the knob that separates constant pressure from committed casts.
		cadences[bid] = float(b.call("phase_cooldown", 3))
		_expect(float(b.call("phase_cooldown", 3)) < float(b.call("phase_cooldown", 1)),
			"'%s' tightens its cadence with its phases" % bid)
		_kill(b)
	_expect(heights.size() == ids.size(),
		"every artist draws a body of its own size (%d distinct across %d bosses)"
			% [heights.size(), ids.size()])
	# No shared attack id across the roster: a moveset that overlapped would mean two
	# bosses doing the same thing under different names.
	var owners: Dictionary = {}
	for id in movesets:
		owners[String(movesets[id])] = true
	_expect(owners.size() == ids.size(),
		"each attack id belongs to exactly one artist (%d owners across %d bosses)"
			% [owners.size(), ids.size()])
	# The Scribble is the pressure boss and the Illuminator is the committed one —
	# their cadences must be at opposite ends, or the rhythms are not distinct.
	_expect(float(cadences[BossRoster.SCRIBBLE]) != float(cadences[BossRoster.ILLUMINATOR]),
		"the pressure boss and the committed boss do not share a cadence")
	_expect(float(load("res://scripts/combat/IlluminatorBoss.gd").get("PAGE_WINDUP")) >= 1.2,
		"the Illuminator's biggest cast has an unmistakable wind-up (spec: loud, committal)")
	_completes("bosses_are_different_fights")


func _test_attach_wires_riders_and_hud() -> void:
	var mods: Array = [BossModifier.ENRAGED, BossModifier.VOID_TOUCHED]
	var b: Node = _build(BossRoster.GUARDIAN, mods)
	await _settle(3)
	for m in mods:
		_expect(_rider(b, String(m)) != null, "rider for '%s' is parented to the boss" % m)
	var hud: Node = b.get_node_or_null("ModifierHud")
	_expect(hud != null, "the modifier HUD is attached (a silent modifier reads as a bug)")
	if hud != null:
		_expect((hud.get("modifier_ids") as Array).size() == mods.size(),
			"the HUD names every live modifier")
	# Duplicates and unknowns must not produce duplicate or broken riders.
	_kill(b)
	var b2: Node = _build(BossRoster.GUARDIAN,
		[BossModifier.PATIENT, BossModifier.PATIENT, "not_a_modifier"])
	await _settle(3)
	var patient_riders: int = 0
	for c: Node in b2.get_children():
		if String(c.name).begins_with("Mod_"):
			patient_riders += 1
	_expect(patient_riders == 1, "a repeated / unknown modifier list yields exactly one rider")
	_kill(b2)
	# No modifiers -> no rider, no HUD: an unmodified boss is byte-for-byte what it
	# was before the roster existed.
	var plain: Node = _build(BossRoster.GUARDIAN)
	await _settle(2)
	_expect(plain.get_node_or_null("ModifierHud") == null, "an unmodified boss gets no HUD")
	_kill(plain)
	_completes("attach_wires_riders_and_hud")


## PATIENT: it does nothing until struck, then it does everything at once.
func _test_patient_holds_then_wakes() -> void:
	var b: Node = _build(BossRoster.GUARDIAN, [BossModifier.PATIENT])
	await _settle(3)
	var r: Node = _rider(b, BossModifier.PATIENT)
	_expect(r != null, "the patient rider attached")
	if r == null:
		_completes("patient_holds_then_wakes")
		return
	b.call("_enter_phase", 1)
	r.call("_tick", 0.016)
	_expect(bool(b.get("_busy")), "a patient boss is held still")
	_expect(int(b.get("touch_damage")) == 0, "...and cannot hurt you by walking into it")
	# The banked cooldown: the boss keeps counting down while it is not allowed to
	# act, so the first exchange after waking is immediate.
	b.set("_attack_cd", -3.0)
	b.call("take_damage", 5)
	r.call("_tick", 0.016)
	_expect(not bool(b.get("_busy")), "striking it wakes it")
	_expect(int(b.get("touch_damage")) > 0, "...and its contact damage comes back")
	_expect(float(b.get("_attack_cd")) <= 0.0, "...with an attack already banked")
	r.call("_tick", 0.016)
	_expect(not bool(b.get("_busy")), "a woken boss is not re-held on the next tick")
	_kill(b)
	_completes("patient_holds_then_wakes")


## ENRAGED: the phase gates move EARLIER (never more HP) and the cadence quickens.
func _test_enraged_moves_the_gates() -> void:
	var b: Node = _build(BossRoster.GUARDIAN, [BossModifier.ENRAGED])
	await _settle(3)
	var r: Node = _rider(b, BossModifier.ENRAGED)
	_expect(r != null, "the enraged rider attached")
	if r == null:
		_completes("enraged_moves_the_gates")
		return
	var mx: int = int(b.get("max_hp"))
	_expect(mx == 600, "ENRAGED DID NOT TOUCH THE HP POOL (spec: modifiers, not HP)")
	b.call("_enter_phase", 1)
	# 70% health: past the enraged 80% gate, but still well clear of the base 66%
	# one — so a transition here can only have come from the modifier.
	b.set("hp", int(float(mx) * 0.70))
	r.call("_tick", 0.016)
	_expect(int(b.call("current_phase")) == 2, "crossing 80%% enrages into P2 early")
	b.set("hp", int(float(mx) * 0.55))
	r.call("_tick", 0.016)
	_expect(int(b.call("current_phase")) == 2, "...and does not skip straight to P3")
	b.set("hp", int(float(mx) * 0.45))
	r.call("_tick", 0.016)
	_expect(int(b.call("current_phase")) == 3, "crossing 50%% enrages into P3 early")
	# The cadence half: an extra drain on top of the boss's own.
	b.set("_attack_cd", 1.0)
	r.call("_tick", 1.0)
	_expect(float(b.get("_attack_cd")) < 1.0, "the attack cooldown drains faster than real time")
	_expect(int(b.get("max_hp")) == mx, "...still without adding a point of HP")
	_kill(b)
	_completes("enraged_moves_the_gates")


## SPLIT: the pool is CARVED at spawn and REDISTRIBUTED at death. The total health
## across the whole encounter is unchanged — see the block at the top of ModSplit.
func _test_split_carves_and_multiplies() -> void:
	var b: Node = _build(BossRoster.SCRIBBLE, [BossModifier.SPLIT, BossModifier.VOID_TOUCHED])
	await _settle(3)
	var r: Node = _rider(b, BossModifier.SPLIT)
	_expect(r != null, "the split rider attached")
	if r == null:
		_completes("split_carves_and_multiplies")
		return
	var carved: int = int(b.get("max_hp"))
	_expect(carved < 600 and carved > 250,
		"the parent's pool is carved down, not added to (600 -> %d)" % carved)
	var before: int = _count_bosses()
	b.call("_enter_phase", 2)
	b.call("take_damage", int(b.get("hp")) + 50)
	await _settle(4)
	var after: int = _count_bosses()
	_expect(after == before + 1,
		"one dead parent leaves TWO live copies (%d bosses before, %d after)" % [before, after])
	var copies: Array[Node] = _live_bosses()
	var total_copy_hp: int = 0
	for c: Node in copies:
		total_copy_hp += int(c.get("max_hp"))
		_expect(c.get_node_or_null("Mod_" + BossModifier.SPLIT) == null,
			"a copy cannot split again (the recursion guard)")
		_expect(c.get_node_or_null("Mod_" + BossModifier.VOID_TOUCHED) != null,
			"a copy inherits the parent's other modifiers")
		_expect(float(c.get("body_scale")) < 1.0, "a copy is physically smaller")
	_expect(carved + total_copy_hp <= 620,
		"parent + copies conserve the original 600 pool (got %d)" % (carved + total_copy_hp))
	for c: Node in copies:
		_kill(c)
	await _settle(2)
	_completes("split_carves_and_multiplies")


## VOID-TOUCHED: the ground rots where it stands, and the rot is capped so the room
## can never become unwalkable.
func _test_void_touched_opens_ground() -> void:
	var b: Node = _build(BossRoster.GUARDIAN, [BossModifier.VOID_TOUCHED])
	await _settle(3)
	var r: Node = _rider(b, BossModifier.VOID_TOUCHED)
	_expect(r != null, "the void-touched rider attached")
	if r == null:
		_completes("void_touched_opens_ground")
		return
	b.call("_enter_phase", 1)
	var before: int = _count_of_class("ZoneSpell")
	r.call("_tick", 9.0)
	await _settle(2)
	var after: int = _count_of_class("ZoneSpell")
	_expect(after > before, "a field opens under the boss (%d -> %d)" % [before, after])
	# The cap is the fairness: "the arena fills up" is a mechanic, "the arena is
	# full" is a soft-lock.
	for i: int in 12:
		r.call("_tick", 9.0)
	await _settle(2)
	var zones: Array = r.get("_zones")
	_expect(zones.size() <= 4, "live fields are capped (got %d)" % zones.size())
	# Ask the RIDER for its own fields rather than scanning the arena: a scan would
	# also pick up leftovers from an earlier test and assert against the wrong boss.
	_expect(zones.size() > 0, "the rider is tracking its live fields")
	for z in zones:
		if not is_instance_valid(z):
			continue
		_expect(String(z.get("target_group")) == "hero",
			"a boss field hurts heroes, not the boss's own side")
		_expect(z.get("caster_node") == b,
			"a boss field is OWNED by the boss (an unowned effect is inert in the reaction system)")
	_kill(b)
	await _settle(2)
	_completes("void_touched_opens_ground")


## UNFINISHED (the sixth): erased and redrawn somewhere else, with the mark landing
## on the page before the body does.
func _test_unfinished_repositions() -> void:
	var b: Node = _build(BossRoster.GUARDIAN, [BossModifier.UNFINISHED])
	await _settle(3)
	var r: Node = _rider(b, BossModifier.UNFINISHED)
	_expect(r != null, "the unfinished rider attached")
	if r == null:
		_completes("unfinished_repositions")
		return
	b.call("_enter_phase", 1)
	b.set("_busy", false)
	var marks_before: int = _count_of_class("MagicCircle")
	r.call("_tick", 30.0)
	await _settle(2)
	_expect(bool(b.get("_busy")),
		"the boss is ROOTED for the tell — that rooted beat is the punish window")
	_expect(_count_of_class("MagicCircle") > marks_before,
		"THE REDRAW MARK lands on the page first, so the play against it is 'step off the mark'")
	# It must never interrupt the boss's own cast: a redraw that ate a telegraphed
	# attack would break the promise that the shape you see is the shape that hurts.
	var r2: Node = _rider(_build(BossRoster.GUARDIAN, [BossModifier.UNFINISHED]), BossModifier.UNFINISHED)
	await _settle(3)
	var b2: Node = r2.get_parent()
	b2.call("_enter_phase", 1)
	b2.set("_busy", true)
	var before2: int = _count_of_class("MagicCircle")
	r2.call("_tick", 30.0)
	await _settle(2)
	_expect(_count_of_class("MagicCircle") == before2, "a busy boss is not interrupted by a redraw")
	_kill(b)
	_kill(b2)
	await _settle(2)
	_completes("unfinished_repositions")


## A quiet boss body (today: a split copy) gives up the top bar and the name card
## and starts already fighting.
func _test_quiet_gives_up_the_bar() -> void:
	var loud: Node = _build(BossRoster.GUARDIAN)
	await _settle(3)
	_expect(loud.get("_bar_layer") != null, "an ordinary boss owns the top-screen bar")
	_kill(loud)
	var quiet: Node = _build(BossRoster.GUARDIAN, [], {"quiet": true, "qphase": 3})
	await _settle(3)
	_expect(quiet.get("_bar_layer") == null, "a quiet boss body gives up the bar and its name card")
	_expect(int(quiet.call("current_phase")) == 3,
		"...and starts in the phase it was told, skipping the 2.6 s intro")
	_kill(quiet)
	await _settle(2)
	_completes("quiet_gives_up_the_bar")


## `spawn_boss` is where the host's roll becomes spawn DATA. Everything downstream
## is pure construction, which is what keeps the two phones honest.
func _test_spawn_boss_carries_the_roll() -> void:
	var enc: Node = load(ENCOUNTER_PATH).new()
	var holder := Node2D.new()
	root.add_child(holder)
	holder.add_child(enc)
	await process_frame
	var built: Node = enc.spawn_boss(1.0, 1.0, BossRoster.ILLUMINATOR,
		[BossModifier.MIRRORED], 12345)
	await _settle(2)
	_expect(built != null, "spawn_boss returns the built guardian in single player")
	if built != null:
		var s: Script = built.get_script() as Script
		_expect(s != null and s.resource_path.ends_with("IlluminatorBoss.gd"),
			"spawn_boss honours the rolled boss id")
		_expect(built.get_node_or_null("Mod_" + BossModifier.MIRRORED) != null,
			"spawn_boss carries the rolled modifiers through to the body")
		# hp_scale is per-boss IDENTITY. The DEPTH curve is hp_mult, which is 1.0
		# here — so any difference from BOSS_BASE_HP came from the roster row.
		var base: int = int(load(ENCOUNTER_PATH).get("BOSS_BASE_HP"))
		var want: int = int(round(float(base) * BossRoster.hp_scale(BossRoster.ILLUMINATOR)))
		_expect(int(built.get("max_hp")) == want,
			"the roster's per-boss hp_scale is applied (%d, wanted %d)" % [int(built.get("max_hp")), want])
		_expect(float(built.get("move_speed")) > 0.0, "the roster's speed_scale produced a real speed")
	# A default call (the boss-rush path) is unchanged: Guardian, no modifiers.
	var legacy: Node = enc.spawn_boss(1.0)
	await _settle(2)
	if legacy != null:
		var ls: Script = legacy.get_script() as Script
		_expect(ls != null and ls.resource_path.ends_with("Boss.gd"),
			"spawn_boss(hp) with no roster arguments is the plain Guardian, as before")
		_expect(legacy.get_node_or_null("ModifierHud") == null, "...with no modifiers")
	holder.free()
	await process_frame
	_completes("spawn_boss_carries_the_roll")


## ══ THE ROSTER CONTRACT ══════════════════════════════════════════════════════
## A boss that misses any of these is SILENTLY broken — no error, no red suite, it
## just quietly does less than it was written to do. That list used to live only in
## a design doc, which meant it was a thing an author had to remember; here it is a
## thing they cannot forget. Every clause is driven off `BossRoster.ids()`, so the
## next artist is held to it the moment its row lands and costs zero suite edits.
##
## What is NOT here, deliberately: the wire (`slice_test_bossnet` owns it — it puts
## every attack of every boss on a real Net spy), the voice (`slice_test_bossvoice`
## owns the bark rows and the redraw hands), and the fight-shape clauses, which are
## `bosses_are_different_fights` above. Duplicating them here would give the roster
## two places to be wrong about the same thing.
func _test_every_boss_satisfies_the_roster_contract() -> void:
	var ids: Array[String] = BossRoster.ids()
	var epithets: Dictionary = {}
	var suffixes: Dictionary = {}
	for bid: String in ids:
		var entry: Dictionary = BossRoster.entry(bid)
		_expect(String(entry["id"]) == bid,
			"'%s' resolves to its OWN row and not the index-1 fallback" % bid)
		var b: Node = _build(bid)
		await _settle(2)
		# 1 · IDENTITY. An epithet is the billing line under the name card; an empty
		#     one silently falls back to the material note, and a DUPLICATE one bills
		#     two different artists as the same thing.
		var ep: String = String(b.call("boss_epithet"))
		_expect(ep != "", "'%s' has a billing line" % bid)
		_expect(not epithets.has(ep), "'%s' is billed as itself (%s)" % [bid, ep])
		epithets[ep] = true
		# 2 · THE VOICE KEY. `Bark.say_variant` tries `<event>_<suffix>` and falls
		#     back to the generic guardian row, so a shared suffix is not an error —
		#     it is two bosses speaking with one mouth, which is worse.
		var sfx: String = String(b.call("bark_suffix"))
		_expect(sfx != "", "'%s' names a bark row" % bid)
		_expect(not suffixes.has(sfx), "'%s' has its own voice (%s)" % [bid, sfx])
		suffixes[sfx] = true
		# 3 · PRESET + TINT. `class_preset` silently does nothing on an unknown name,
		#     which ships a boss wearing the default kit and reports no fault.
		_expect(CharacterRig.new().has_method("class_preset"), "the rig still takes a preset")
		var preset: String = String(b.call("boss_preset"))
		_expect(preset != "", "'%s' names a rig preset" % bid)
		# 4 · THE BODY. `_fit_box_to_scale` needs a RectangleShape2D or the body is
		#     born inside the floor, and it cannot report that it did not find one.
		var cs: Node = b.get_node_or_null("CollisionShape2D")
		_expect(cs != null, "'%s' has a CollisionShape2D" % bid)
		if cs != null:
			_expect(cs.get("shape") is RectangleShape2D,
				"'%s' carries a RectangleShape2D (_fit_box_to_scale cannot see any other)" % bid)
		# 5 · THE ATTACK TABLE IS ANSWERABLE. Every id a phase list names must have a
		#     duration, or the busy timer runs on the 0.8-1.2 s fallback and the
		#     attack's own tell outlives the window it was supposed to fill.
		for ph: int in [1, 2, 3]:
			for id in b.call("_phase_attack_ids", ph):
				_expect(float(b.call("_attack_duration", String(id))) > 0.0,
					"'%s' gives attack '%s' a real duration" % [bid, String(id)])
		_kill(b)
	_completes("every_boss_satisfies_the_roster_contract")


# ------------------------------------------------------------------- helpers
func _live_bosses() -> Array[Node]:
	var out: Array[Node] = []
	for e: Node in root.get_tree().get_nodes_in_group("enemy"):
		if e.has_method("current_phase") and is_instance_valid(e):
			out.append(e)
	return out


func _count_bosses() -> int:
	return _live_bosses().size()


## Minimal hero stand-in: a Node2D in group "hero" with hp + take_damage.
class _HeroStub extends Node2D:
	var hp: int = 100
	var max_hp: int = 100
	func take_damage(amount: int) -> void:
		hp = maxi(hp - amount, 0)
