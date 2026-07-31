# Run: godot --headless --path godot-project --script tools/slice6_test_bot_seams.gd
#
# The two PREREQUISITE seams for bots, and nothing else:
#
#   FACTIONS      — a hero can hurt another hero when the factions differ and
#                   CANNOT when they match, while single player stays exactly as
#                   it was (a spell built with no explicit group still targets
#                   "enemy"). Before this seam existed, hero-vs-hero did literally
#                   nothing in single player in either direction, so a perfectly
#                   driven bot could not fight anyone.
#   PER-INSTANCE  — an injected controller drives one hero with ZERO writes to
#   INPUT           the process-global `Input` singleton, two controllers on two
#                   heroes do not interfere (the exact failure mode that rules out
#                   `Input.action_press`, which `TouchControls` uses and which only
#                   works because there is exactly one local player), and a hero
#                   with NO controller still reads real `Input`.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# A dead member read is NOT a test failure in GDScript: it logs a runtime error,
# ABORTS the enclosing function and hands the caller the return type's zero value,
# so `failed += _test_x()` reads as "zero failures" while the suite verifies
# nothing. Failures therefore accumulate on the MEMBER `_fails`, and every test's
# last line records that it reached the end — a test that aborts part-way is
# missing from `_completed` and fails the suite BY ABSENCE.
extends SceneTree

## Every test that must run to completion. A name missing from `_completed` at the
## end means that test aborted part-way and fails the suite.
const TESTS: Array[String] = [
	"intent_is_sanitized",
	"kit_slots_match_the_spell_library",
	"kit_slot_is_selected_by_index",
	"brain_memory_is_per_bot",
	"intent_merge_can_suppress",
	"faction_bolt_hits_across_factions",
	"faction_bolt_spares_same_faction",
	"faction_default_is_unchanged",
	"faction_melee_follows_the_faction",
	"spellcaster_defaults_to_enemy",
	"spellcaster_forwards_both_spellings",
	"controller_drives_without_touching_input",
	"controller_cannot_press_forbidden_actions",
	"two_controllers_do_not_interfere",
	"input_fallback_survives",
	"blackboard_is_fair_and_complete",
	"blackboard_sees_only_drawn_threats",
]

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
const SPELL_PATH: String = "res://scenes/combat/Spell.tscn"
const TICK: float = 1.0 / 60.0
## Open space, far from any arena geometry, so nothing collides by accident.
const FAR: Vector2 = Vector2(20000.0, 20000.0)

## Hero members this suite reaches DYNAMICALLY (Hero.gd has no class_name, so
## every `hero.hostile_group` is a runtime lookup). Listed once so the existence
## check is a single call rather than a guess scattered per assertion — this is
## what NAMES the casualty when one of them moves house.
const HERO_MEMBERS: Array[String] = [
	"hp", "max_hp", "hostile_group", "faction_group", "controller", "velocity",
	"is_dashing", "_melee_range", "_bot_clock",
]
## ...and the seam methods, which are the actual subject of this file.
const HERO_METHODS: Array[String] = [
	"set_faction", "bot_body_state", "bot_select_signature", "signature_at", "_pressed", "_just", "_released",
	"_axis", "_vector", "_aim_point", "_on_melee_hit_frame",
]
## Every input action a bot could conceivably drive. Snapshotted before and after
## a bot frame to prove the seam wrote to none of them.
const ALL_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"dash", &"jump", &"cast", &"melee", &"parry", &"blast", &"blink", &"nova",
	&"ultimate", &"cycle_element", &"cycle_colourway", &"switch_class",
	&"cycle_signature",
]

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}


## A spectacle stub that declares BOTH target-group spellings the codebase uses,
## so the stamp can be observed writing each one.
class GroupStub extends Node2D:
	var target_group: String = "enemy"
	var _target_group: String = "enemy"


## The smallest thing `Spell._try_damage` will hurt: a member of a group with a
## `take_damage` method. Cheaper and more deterministic than a real Enemy, and it
## isolates the ROUTING (which is what this file tests) from combat behaviour.
class Victim extends Node2D:
	var taken: int = 0

	func take_damage(amount: int) -> void:
		taken += amount


## A brain is anything with `decide()`. This one replays a fixed intent, which is
## all the seam needs to be exercised — the thinking is somebody else's file.
class ScriptedBrain extends RefCounted:
	var intent: Dictionary = {}
	var calls: int = 0
	var last_blackboard: Dictionary = {}

	func decide(bb: Dictionary, _profile: Dictionary) -> Dictionary:
		calls += 1
		last_blackboard = bb
		return intent


## The three-argument shape the real brain uses: `decide(bb, profile, mem)` with a
## `Memory` inner class the controller is expected to build and keep PER BOT.
class MemoryBrain extends RefCounted:
	class Memory extends RefCounted:
		var ticks: int = 0

	var seen: Object = null

	func decide(_bb: Dictionary, _profile: Dictionary, mem: Object) -> Dictionary:
		seen = mem
		if mem != null:
			mem.ticks += 1
		return {}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_intent_is_sanitized()
	_test_kit_slots_match_the_spell_library()
	_test_kit_slot_is_selected_by_index()
	_test_brain_memory_is_per_bot()
	_test_intent_merge_can_suppress()
	_test_faction_bolt_hits_across_factions()
	_test_faction_bolt_spares_same_faction()
	_test_faction_default_is_unchanged()
	_test_faction_melee_follows_the_faction()
	_test_spellcaster_defaults_to_enemy()
	_test_spellcaster_forwards_both_spellings()
	_test_controller_drives_without_touching_input()
	_test_controller_cannot_press_forbidden_actions()
	_test_two_controllers_do_not_interfere()
	_test_input_fallback_survives()
	_test_blackboard_is_fair_and_complete()
	_test_blackboard_sees_only_drawn_threats()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("bot seam tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("bot seam tests: all PASS")
		quit(0)
	return true


# ---- harness ---------------------------------------------------------------

## Accumulates onto the MEMBER `_fails`, never a return value — a failure recorded
## before an abort survives the abort instead of being discarded with it.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


## Names the casualty when a member this suite reaches has been renamed or moved.
## The completion sentinel says SOMETHING died; this says which.
func _require(obj: Object, members: Array[String], methods: Array[String], who: String) -> void:
	var props: Dictionary = {}
	for p: Dictionary in obj.get_property_list():
		props[String(p["name"])] = true
	for m: String in members:
		_expect(props.has(m), "%s still has member `%s`" % [who, m])
	for f: String in methods:
		_expect(obj.has_method(f), "%s still has method `%s`" % [who, f])


func _make_hero(at: Vector2 = FAR) -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)          # freed with root at exit
	hero.set_physics_process(false)  # drive physics by hand, one tick at a time
	hero.global_position = at
	return hero


## Every test gets its OWN patch of world, far from every other test's, and its
## own team names.
##
## ⚠ NOT COSMETIC. Heroes live in `root` for the whole run, and both the faction
## scans and the blackboard's foe search are GROUP + DISTANCE queries — so a hero
## left behind by an earlier test, standing on the same coordinates under the same
## team name, silently becomes the nearest hostile in a later one. That is a real
## bug this harness produced (the melee auto-target locked onto a corpse from two
## tests ago) and it would have been read as a fault in the seam.
func _plot(index: int) -> Vector2:
	return FAR + Vector2(float(index) * 8000.0, 0.0)


## A bolt parked in the tree, wired the way `Hero._primary_bolt` wires one, but
## kept on the QUICK shelf so `_punctuate` does not fire an impact frame at a
## headless renderer.
func _make_bolt(caster: Node, hostile: StringName) -> Area2D:
	var bolt: Area2D = (load(SPELL_PATH) as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.set("caster", caster)
	bolt.set("spell_tier", SpellTier.Tier.QUICK)
	bolt.call("set_hostile_group", hostile)
	return bolt


func _hp_of(hero: CharacterBody2D) -> int:
	return int(hero.get("hp"))


# ---- the intent contract ---------------------------------------------------

## The seam repairs a brain's output rather than trusting it, and NAMES what it
## repaired. A silently-ignored misspelled key is the bug class this codebase
## keeps writing post-mortems about, so `problems()` has to actually see it.
func _test_intent_is_sanitized() -> void:
	var raw: Dictionary = {
		"move": Vector2(4.0, -9.0),      # out of range on both axes
		"aim": Vector2(3.0, 0.0),        # unnormalized
		"cast_slot": 47,                 # not a slot
		"dashh": true,                   # typo
		"fire": 1,                       # truthy non-bool
	}
	var clean: Dictionary = BotIntent.sanitized(raw)
	_expect(clean[BotIntent.MOVE] == Vector2(1.0, -1.0),
		"move is clamped per-axis (got %s)" % [clean[BotIntent.MOVE]])
	_expect((clean[BotIntent.AIM] as Vector2).is_equal_approx(Vector2.RIGHT),
		"aim is normalized (got %s)" % [clean[BotIntent.AIM]])
	_expect(int(clean[BotIntent.CAST_SLOT]) == BotIntent.NONE,
		"an out-of-range slot collapses to NONE rather than firing something plausible")
	_expect(bool(clean[BotIntent.FIRE]), "a truthy `fire` is coerced to true")
	_expect(not clean.has(&"dashh"), "an unknown key is dropped")
	_expect(not bool(clean[BotIntent.DASH]), "...and the typo does NOT become a dash")

	var complaints: Array[String] = BotIntent.problems(raw)
	var named: bool = false
	for c: String in complaints:
		if c.contains("dashh"):
			named = true
	_expect(named, "problems() NAMES the unknown key (got %s)" % [complaints])
	_expect(BotIntent.problems({"move": Vector2.ZERO}).is_empty(),
		"a clean intent produces no complaints")
	_expect(BotIntent.is_idle({}), "an empty dictionary is a legal, idle intent")
	_completes("intent_is_sanitized")


## THE CONTRACT THAT LETS A BRAIN REASON ABOUT A CLASS IT HAS NEVER SEEN:
## `cast_slot` i IS `SpellLibrary.ROLE_ORDER[i]` IS `Hero._signatures[i]`, for
## every class. Asserted against the real library rather than restated, so the two
## orders cannot quietly drift apart — which is exactly what happened once already
## (an earlier revision numbered Q/R/T here and silently pointed brains at a
## different system entirely).
func _test_kit_slots_match_the_spell_library() -> void:
	_expect(BotIntent.SLOT_COUNT == SpellLibrary.ROLE_ORDER.size(),
		"the kit has exactly as many slots as there are roles")
	for i: int in BotIntent.SLOT_COUNT:
		_expect(BotIntent.SLOT_ROLES[i] == SpellLibrary.ROLE_ORDER[i],
			"slot %d is role `%s` (library says `%s`)"
			% [i, BotIntent.SLOT_ROLES[i], SpellLibrary.ROLE_ORDER[i]])
	_expect(BotIntent.SLOT_ULT == BotIntent.SLOT_COUNT - 1, "the ult is the last slot")
	# Every shipped class must actually FILL the kit, or a brain asking for its
	# control spell on that class gets nothing.
	for cls: int in 8:
		var kit: Array = SpellLibrary.build_for_class(cls)
		_expect(kit.size() == BotIntent.SLOT_COUNT,
			"class %d builds all %d kit slots (got %d)" % [cls, BotIntent.SLOT_COUNT, kit.size()])
	_completes("kit_slots_match_the_spell_library")


## THE BLOCKER THIS FIXES: `cycle_signature` is forbidden to a bot (it is the
## shared V key and would move the human's selection too), so without an index
## setter a bot could only ever cast whichever spell happened to be selected —
## i.e. spam one spell forever. Selection by index is what makes the kit usable.
func _test_kit_slot_is_selected_by_index() -> void:
	var hero: CharacterBody2D = _make_hero(_plot(12))
	for slot: int in BotIntent.SLOT_COUNT:
		_expect(bool(hero.call("bot_select_signature", slot)),
			"slot %d is selectable by index" % slot)
		_expect(int(hero.get("_signature_index")) == slot,
			"...and the selection actually moved to %d" % slot)
		_expect(hero.call("signature_at", slot) != null, "slot %d holds a real spell" % slot)
	_expect(not bool(hero.call("bot_select_signature", BotIntent.SLOT_COUNT)),
		"an out-of-range slot is REFUSED, not clamped onto a plausible wrong spell")
	_expect(not bool(hero.call("bot_select_signature", -1)), "...and so is a negative one")
	_expect(int(hero.get("_signature_index")) == BotIntent.SLOT_COUNT - 1,
		"a refused selection leaves the previous one alone")

	# ...and the controller wires the two halves together: choosing a slot selects
	# that signature on THIS body and holds the one shared cast button.
	var brain := ScriptedBrain.new()
	brain.intent = {"cast_slot": BotIntent.SLOT_CONTROL}
	var ctrl := BotController.new()
	ctrl.brain = brain
	ctrl.tick(hero, 0.0)
	_expect(int(hero.get("_signature_index")) == BotIntent.SLOT_CONTROL,
		"the controller selected the control spell on the body")
	_expect(ctrl.just_pressed(BotController.CAST_ACTION),
		"...and pressed the one button every kit spell is cast through")
	_expect(not ctrl.just_pressed(&"cycle_signature"),
		"...without ever touching the shared cycle action")
	_completes("kit_slot_is_selected_by_index")


## A brain is a PURE function and is therefore shareable by every bot in the
## arena — so its scratch state (reaction clock, latches, fusion window) must live
## on the CONTROLLER, one per bot. Sharing one memory would make two bots react as
## a single organism, which is the tell-tale sign of a bot swarm rather than a
## roster of opponents.
func _test_brain_memory_is_per_bot() -> void:
	var brain := MemoryBrain.new()   # ONE brain, deliberately, driving two bots
	var ca := BotController.new()
	var cb := BotController.new()
	ca.brain = brain
	cb.brain = brain

	ca.tick(null, 0.0)
	var mem_a: Object = ca.memory
	_expect(mem_a != null, "the controller built the brain's own Memory class for it")
	_expect(brain.seen == mem_a, "...and handed it to the three-argument decide()")
	ca.tick(null, 0.1)
	_expect(ca.memory == mem_a, "the SAME memory survives across frames")
	_expect(int(mem_a.get("ticks")) == 2, "...so the brain's own counter accumulated")

	cb.tick(null, 0.0)
	_expect(cb.memory != null and cb.memory != mem_a,
		"a second bot gets its OWN memory, not a shared one")

	# ...and a two-argument brain still works, just without memory.
	var plain := ScriptedBrain.new()
	var cc := BotController.new()
	cc.brain = plain
	cc.tick(null, 0.0)
	_expect(plain.calls == 1, "a two-argument brain is still consulted")
	_completes("brain_memory_is_per_bot")


## Merge REPLACES per key rather than OR-ing, because the layers are a priority
## ladder: a reflex layer must be able to say "do NOT fire, you are dodging".
func _test_intent_merge_can_suppress() -> void:
	var plan: Dictionary = {"fire": true, "move": Vector2.RIGHT}
	var reflex: Dictionary = {"fire": false, "dash": true}
	var out: Dictionary = BotIntent.merge(plan, reflex)
	_expect(not bool(out[BotIntent.FIRE]), "the higher layer can suppress a press")
	_expect(bool(out[BotIntent.DASH]), "...while adding its own")
	_expect(out[BotIntent.MOVE] == Vector2.RIGHT, "keys the higher layer omits survive")
	_completes("intent_merge_can_suppress")


# ---- seam 1: factions ------------------------------------------------------

## True when a multiplayer session reads as live. Consulted rather than assumed
## because of a quirk that changes what "unchanged" MEANS for the default bolt:
## `Net.is_active()` is documented as false in single player, but it reads TRUE
## whenever the SceneTree holds its default `OfflineMultiplayerPeer`, whose
## connection status is CONNECTED. So the co-op friendly-fire path is live in
## single player too, and an un-factioned hero bolt already damaged heroes before
## this seam existed. The seam preserves that exactly; this helper is how the
## suite asserts "unchanged" against reality instead of against the docstring.
func _session_reads_live() -> bool:
	var net: Node = root.get_node_or_null("/root/Net")
	return net != null and bool(net.call("is_active"))


## DIFFERENT factions: hero A's bolt hurts hero B.
func _test_faction_bolt_hits_across_factions() -> void:
	var home: Vector2 = _plot(1)
	var a: CharacterBody2D = _make_hero(home)
	var b: CharacterBody2D = _make_hero(home + Vector2(120.0, 0.0))
	_require(a, HERO_MEMBERS, HERO_METHODS, "Hero")
	a.set_faction(&"f1_a", &"f1_b")
	b.set_faction(&"f1_b", &"f1_a")
	_expect(b.is_in_group("f1_b"), "set_faction joins the team group when already in tree")

	var before: int = _hp_of(b)
	var bolt: Area2D = _make_bolt(a, &"f1_b")
	bolt.call("_try_damage", b)
	_expect(_hp_of(b) < before, "a bolt hostile to the other faction damages that hero")

	# ...and never its own caster, whichever faction it is on.
	var a_before: int = _hp_of(a)
	var bolt2: Area2D = _make_bolt(a, &"f1_b")
	bolt2.call("_try_damage", a)
	_expect(_hp_of(a) == a_before, "a bolt never damages its own caster")
	_completes("faction_bolt_hits_across_factions")


## SAME faction: two heroes on one team, both hostile to the other. Neither one's
## attacks can even find the other, which is what makes teams expressible rather
## than just "heroes can now hurt heroes".
##
## This is also the assertion that proves the faction test is not being bypassed
## by the friendly-fire clause: the session reads live in this harness, so a bolt
## that had merely been "allowed because a session exists" would land here.
func _test_faction_bolt_spares_same_faction() -> void:
	var home: Vector2 = _plot(2)
	var a: CharacterBody2D = _make_hero(home)
	var mate: CharacterBody2D = _make_hero(home + Vector2(120.0, 0.0))
	a.set_faction(&"f2_a", &"f2_b")
	mate.set_faction(&"f2_a", &"f2_b")

	var before: int = _hp_of(mate)
	var bolt: Area2D = _make_bolt(a, &"f2_b")
	bolt.call("_try_damage", mate)
	_expect(_hp_of(mate) == before, "a team-mate takes NOTHING from an ally's bolt")
	_completes("faction_bolt_spares_same_faction")


## THE DEFAULT IS UNCHANGED. A bolt nobody re-pointed behaves exactly as it did
## before the seam: it damages `enemy`, and what it does to a hero is decided by
## the session, not by the new faction field.
func _test_faction_default_is_unchanged() -> void:
	var home: Vector2 = _plot(3)
	var hero: CharacterBody2D = _make_hero(home)
	var other: CharacterBody2D = _make_hero(home + Vector2(120.0, 0.0))
	_expect(StringName(str(hero.get("hostile_group"))) == &"enemy",
		"a hero defaults to hostile_group `enemy`")
	_expect(StringName(str(hero.get("faction_group"))) == &"",
		"...and to no team at all")

	var mob := Victim.new()
	mob.add_to_group("enemy")
	root.add_child(mob)

	# A bolt built exactly as _primary_bolt builds one, with no faction opt-in.
	var bolt: Area2D = (load(SPELL_PATH) as PackedScene).instantiate()
	root.add_child(bolt)
	bolt.set("caster", hero)
	bolt.set("spell_tier", SpellTier.Tier.QUICK)
	_expect(StringName(str(bolt.get("hostile_group"))) == &"enemy",
		"a bolt defaults to hostile_group `enemy`")
	bolt.call("_try_damage", mob)
	_expect(mob.taken > 0, "the default bolt still damages an `enemy`")

	var before: int = _hp_of(other)
	var bolt2: Area2D = (load(SPELL_PATH) as PackedScene).instantiate()
	root.add_child(bolt2)
	bolt2.set("caster", hero)
	bolt2.set("spell_tier", SpellTier.Tier.QUICK)
	bolt2.call("_try_damage", other)
	if _session_reads_live():
		_expect(_hp_of(other) < before,
			"an un-factioned bolt still friendly-fires while a session reads live (unchanged)")
	else:
		_expect(_hp_of(other) == before,
			"an un-factioned bolt still cannot touch a hero with no session (unchanged)")
	_completes("faction_default_is_unchanged")


## MELEE follows the faction too — the sweeps used to iterate a literal "enemy"
## group, so a bot hero swung straight through the hero it was fighting. Nothing
## in melee ever went through `Net`, so this half was inert in every mode.
func _test_faction_melee_follows_the_faction() -> void:
	var home: Vector2 = _plot(4)
	var a: CharacterBody2D = _make_hero(home)
	var b: CharacterBody2D = _make_hero(home + Vector2(24.0, 0.0))  # inside MELEE_RANGE
	a.set_faction(&"f4_a", &"f4_b")
	b.set_faction(&"f4_b", &"f4_a")
	a.set("facing", Vector2.RIGHT)

	_expect(a.call("_nearest_enemy_in_melee_range") == b,
		"the melee auto-target finds a HOSTILE hero (it is faction-scanned now)")
	var before: int = _hp_of(b)
	a.call("_on_melee_hit_frame")
	_expect(_hp_of(b) < before, "a swing lands on the hostile hero")

	# ⚠ THE TEAM-MATE HALF CHANGED WHEN FRIENDLY FIRE LANDED, and it changed into the
	# more interesting assertion. It used to say "the scan cannot even see them"; the
	# spec now says friendly fire is the social engine of the whole game, so a swing
	# aimed at your team-mate MUST land. What must NOT change is the assist: the melee
	# auto-target is the game aiming FOR you, and a game that silently redirects your
	# fist onto the person beside you is not friendly fire, it is betrayal. So the two
	# halves now pull in opposite directions ON PURPOSE, and that is the sanity rule:
	#
	#   arc  (you pointed at them)  -> lands
	#   auto-target (you did not)   -> never reaches for a team-mate
	var away: Vector2 = _plot(5)
	var c: CharacterBody2D = _make_hero(away)
	var mate: CharacterBody2D = _make_hero(away + Vector2(24.0, 0.0))
	c.set_faction(&"f5_a", &"f5_b")
	mate.set_faction(&"f5_a", &"f5_b")
	c.set("facing", Vector2.RIGHT)
	_expect(c.call("_nearest_enemy_in_melee_range") == null,
		"the auto-target does NOT lock onto a team-mate")
	var mate_before: int = _hp_of(mate)
	c.call("_on_melee_hit_frame")
	_expect(_hp_of(mate) < mate_before,
		"FRIENDLY FIRE: a swing you aimed at a team-mate DOES land on them")

	# ...and the assist's refusal is not just "nothing was in range": put a team-mate
	# BEHIND the swinger, outside the arc, where only an auto-target could reach them.
	var behind_home: Vector2 = _plot(6)
	var d: CharacterBody2D = _make_hero(behind_home)
	var mate_behind: CharacterBody2D = _make_hero(behind_home + Vector2(-24.0, 0.0))
	d.set_faction(&"f6_a", &"f6_b")
	mate_behind.set_faction(&"f6_a", &"f6_b")
	d.set("facing", Vector2.RIGHT)
	var behind_before: int = _hp_of(mate_behind)
	d.call("_on_melee_hit_frame")
	_expect(_hp_of(mate_behind) == behind_before,
		"a team-mate BEHIND you is never dragged into the swing by the auto-target")
	_completes("faction_melee_follows_the_faction")


## The dispatcher's default. Every capture script, headless tool and shipped
## caster omits the new argument, so the omission has to mean exactly what the
## code did before.
func _test_spellcaster_defaults_to_enemy() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var spell := SpellDef.new()
	spell.id = "test_beam"
	spell.kind = SpellDef.Kind.BEAM
	spell.damage = 10
	spell.effect = "arcane"

	# ⚠ UPDATED WHEN FRIENDLY FIRE LANDED, deliberately and not because it failed.
	# `_stamp` no longer writes the caller's faction verbatim: it writes
	# `SpellCaster.damage_group(faction)`, which is the shared `mortal` group while
	# friendly fire is on. So there are now TWO contracts to pin, and the old one is
	# still a contract — turning friendly fire off must restore faction-strict
	# targeting exactly, or the switch is decorative and a bisect through it proves
	# nothing.
	var was_ff: bool = SpellCaster.friendly_fire

	# --- friendly fire ON (the shipping default): everyone with a body is fair game.
	SpellCaster.friendly_fire = true
	var ok: bool = SpellCaster.cast(spell, arena, Vector2.ZERO, Vector2(300.0, 0.0),
		Color.WHITE, "arcane")
	_expect(ok, "a BEAM still dispatches with no target group given")
	_expect(_group_of_last_spectacle(arena) == String(SpellCaster.MORTAL_GROUP),
		"friendly fire on -> a spectacle targets `mortal` whatever faction cast it (got %s)"
		% [_group_of_last_spectacle(arena)])
	SpellCaster.cast(spell, arena, Vector2.ZERO, Vector2(300.0, 0.0), Color.WHITE,
		"arcane", null, &"team_b")
	_expect(_group_of_last_spectacle(arena) == String(SpellCaster.MORTAL_GROUP),
		"...and an explicit faction is widened too, not honoured (got %s)"
		% [_group_of_last_spectacle(arena)])

	# --- friendly fire OFF: byte-identical to the pre-friendly-fire behaviour.
	SpellCaster.friendly_fire = false
	SpellCaster.cast(spell, arena, Vector2.ZERO, Vector2(300.0, 0.0), Color.WHITE, "arcane")
	_expect(_group_of_last_spectacle(arena) == "enemy",
		"friendly fire off -> no explicit group still means `enemy` (got %s)"
		% [_group_of_last_spectacle(arena)])
	SpellCaster.cast(spell, arena, Vector2.ZERO, Vector2(300.0, 0.0), Color.WHITE,
		"arcane", null, &"team_b")
	_expect(_group_of_last_spectacle(arena) == "team_b",
		"...and an explicit faction is forwarded verbatim (got %s)"
		% [_group_of_last_spectacle(arena)])
	SpellCaster.friendly_fire = was_ff
	_completes("spellcaster_defaults_to_enemy")


## The target group of the most recently spawned spectacle under `arena`.
##
## Searched backwards for a child that ACTUALLY declares the property rather than
## just taking the last child: a spectacle routinely adds companion nodes to the
## same arena (a MagicCircle handed off from the caster's windup, for one), so
## "the last child" is not reliably the spell.
func _group_of_last_spectacle(arena: Node) -> String:
	for i: int in range(arena.get_child_count() - 1, -1, -1):
		var g: Variant = arena.get_child(i).get("target_group")
		if g != null:
			return String(g)
	return "<no spectacle declared target_group>"


## The stamp writes BOTH spellings, because the codebase uses both: the public
## `target_group` and the private `_target_group` that four spectacles flip
## themselves on a deflect. Writing only one silently leaves those four hostile to
## whatever they were born with.
func _test_spellcaster_forwards_both_spellings() -> void:
	var stub := GroupStub.new()
	root.add_child(stub)
	var spell := SpellDef.new()
	spell.kind = SpellDef.Kind.BEAM
	# Friendly fire forced OFF for this one: what is under test here is that BOTH
	# SPELLINGS are written, and pinning it against the verbatim faction keeps the
	# assertion about the two names rather than about the group policy (which the
	# test above owns). Both halves would pass under either setting; this one just
	# says what it means.
	var was_ff: bool = SpellCaster.friendly_fire
	SpellCaster.friendly_fire = false
	SpellCaster._stamp(stub, 0, spell, null, &"team_b")
	_expect(stub.target_group == "team_b", "the public spelling is stamped")
	_expect(stub._target_group == "team_b", "the private spelling is stamped too")
	SpellCaster.friendly_fire = true
	SpellCaster._stamp(stub, 0, spell, null, &"team_b")
	_expect(stub.target_group == String(SpellCaster.MORTAL_GROUP),
		"...and friendly fire widens BOTH, not just the public one (public)")
	_expect(stub._target_group == String(SpellCaster.MORTAL_GROUP),
		"...and friendly fire widens BOTH, not just the public one (private)")
	SpellCaster.friendly_fire = was_ff
	_completes("spellcaster_forwards_both_spellings")


# ---- seam 2: per-instance input --------------------------------------------

## Snapshot of every action's global press state, used to prove the seam is
## invisible to `Input`.
func _input_snapshot() -> Dictionary:
	var snap: Dictionary = {}
	for a: StringName in ALL_ACTIONS:
		snap[a] = Input.is_action_pressed(a)
	return snap


## The load-bearing claim: a controller drives its hero and writes NOTHING to the
## process-global input singleton. If it did, the bot would also be driving the
## human's hero — which is precisely why `Input.action_press` (the mechanism
## TouchControls uses) is not a usable seam for more than one agent.
func _test_controller_drives_without_touching_input() -> void:
	var hero: CharacterBody2D = _make_hero(_plot(6))
	var brain := ScriptedBrain.new()
	# Every button at once — the maximal case, so nothing can leak unnoticed.
	brain.intent = {
		"move": Vector2(1.0, -1.0), "aim": Vector2.RIGHT, "fire": true,
		"cast_slot": BotIntent.SLOT_PAYOFF, "dash": true, "guard": true, "jump": true,
		"swing": true, "ability_blast": true, "ability_blink": true, "ability_nova": true,
	}
	var ctrl := BotController.new()
	ctrl.brain = brain
	hero.set("controller", ctrl)

	var before: Dictionary = _input_snapshot()
	for _i: int in 4:
		hero._physics_process(TICK)
	var after: Dictionary = _input_snapshot()
	var leaked: Array[String] = []
	for a: StringName in ALL_ACTIONS:
		if bool(before[a]) != bool(after[a]):
			leaked.append(String(a))
	_expect(leaked.is_empty(), "a bot frame wrote to global Input: %s" % [leaked])
	_expect(brain.calls >= 4, "the brain was actually consulted (calls=%d)" % brain.calls)
	_expect(float(hero.get("_bot_clock")) > 0.0, "the bot clock advanced on the body's delta")
	_expect(ctrl.aim_point(Vector2.ZERO).x > 0.0,
		"the aim resolves to a world point along the brain's chosen direction")

	# The "it actually drives the body" half is asserted on its OWN hero with a
	# movement-only intent, deliberately. The maximal intent above also fires the Q,
	# and a Q pays `_self_recoil` — a leftward shove for a rightward aim — so a
	# combined assertion would be testing recoil, not the seam.
	var walker: CharacterBody2D = _make_hero(_plot(6) + Vector2(1500.0, 0.0))
	var quiet := ScriptedBrain.new()
	quiet.intent = {"move": Vector2.RIGHT}
	var walk_ctrl := BotController.new()
	walk_ctrl.brain = quiet
	walker.set("controller", walk_ctrl)
	for _i: int in 4:
		walker._physics_process(TICK)
	_expect(float(walker.get("velocity").x) > 0.0,
		"the hero actually moved under controller drive (vx=%.1f)"
		% float(walker.get("velocity").x))
	_completes("controller_drives_without_touching_input")


## A bot must never re-roll its own class or loadout mid-fight. `switch_class`
## writes through to `GameState.selected_class`, so a bot pressing it corrupts the
## PLAYER'S saved pick. Enforced by a hard `false` at the seam, not by asking
## brains to behave — so the guard is poked directly rather than via an intent.
func _test_controller_cannot_press_forbidden_actions() -> void:
	var ctrl := BotController.new()
	ctrl.drive({"move": Vector2.RIGHT})
	for a: StringName in BotController.FORBIDDEN:
		ctrl._held[a] = true    # simulate the worst case: something DID hold it
		_expect(not ctrl.pressed(a), "`%s` can never read as pressed" % a)
		_expect(not ctrl.just_pressed(a), "`%s` can never read as just-pressed" % a)
		_expect(not ctrl.just_released(a), "`%s` can never read as just-released" % a)
	# Down is the limp/ragdoll FLOP toy on this body, not "walk downward": a bot
	# holding it would drop to the floor and lose its abilities. The downward
	# component must still reach the dash-angle solver, though.
	ctrl.drive({"move": Vector2(0.0, 1.0)})
	_expect(not ctrl.pressed(&"move_down"), "a bot can never hold the flop button")
	_expect(is_equal_approx(ctrl.vector(&"move_left", &"move_right",
		&"move_up", &"move_down").y, 1.0),
		"...but a downward dash angle still gets through `vector()`")
	_completes("controller_cannot_press_forbidden_actions")


## THE C2 FAILURE MODE, asserted directly. Under global input these two intents
## are the same set of virtual buttons, so one bot's press would drive the other
## and the second write would simply win. Per-instance state means both hold in
## the SAME frame.
func _test_two_controllers_do_not_interfere() -> void:
	var a: CharacterBody2D = _make_hero(_plot(7))
	var b: CharacterBody2D = _make_hero(_plot(7) + Vector2(600.0, 0.0))
	var brain_a := ScriptedBrain.new()
	var brain_b := ScriptedBrain.new()
	brain_a.intent = {"move": Vector2.RIGHT, "dash": true}
	brain_b.intent = {"move": Vector2.LEFT}
	var ca := BotController.new()
	var cb := BotController.new()
	ca.brain = brain_a
	cb.brain = brain_b
	a.set("controller", ca)
	b.set("controller", cb)

	for _i: int in 3:
		a._physics_process(TICK)
		b._physics_process(TICK)

	_expect(ca.pressed(&"move_right") and not ca.pressed(&"move_left"),
		"bot A holds right only")
	_expect(cb.pressed(&"move_left") and not cb.pressed(&"move_right"),
		"bot B holds left only — the two do not share a button set")
	_expect(float(a.get("velocity").x) > 0.0 or bool(a.get("is_dashing")),
		"bot A went right in the same frame bot B went left")
	_expect(float(b.get("velocity").x) < 0.0, "bot B went left")
	_expect(not bool(b.get("is_dashing")),
		"bot A's dash press did NOT dash bot B (the whole point of per-instance input)")
	_completes("two_controllers_do_not_interfere")


## And the default path, which is the human's: no controller, real `Input`. This
## is what keeps single player byte-identical and what `slice_test_movement.gd` /
## `slice_test_touch.gd` depend on.
func _test_input_fallback_survives() -> void:
	var hero: CharacterBody2D = _make_hero(_plot(8))
	_expect(hero.get("controller") == null, "a hero has no controller by default")
	Input.action_press("move_right")
	_expect(bool(hero.call("_pressed", &"move_right")),
		"with no controller, _pressed() reads the real Input singleton")
	for _i: int in 4:
		hero._physics_process(TICK)
	var moved: float = float(hero.get("velocity").x)
	Input.action_release("move_right")
	_expect(moved > 0.0, "a keyboard press still drives the hero (got vx=%.1f)" % moved)
	_expect(not bool(hero.call("_pressed", &"move_right")),
		"...and the release is seen too")
	_completes("input_fallback_survives")


# ---- the blackboard --------------------------------------------------------

## FAIRNESS IS STRUCTURAL. The blackboard must carry only what a human reads off
## the screen — and in particular must carry NOTHING about the opponent's
## cooldowns, which is the one piece of hidden state that would make a bot
## unbeatable rather than merely hard.
func _test_blackboard_is_fair_and_complete() -> void:
	var home: Vector2 = _plot(9)
	var hero: CharacterBody2D = _make_hero(home)
	var foe: CharacterBody2D = _make_hero(home + Vector2(300.0, 0.0))
	hero.set_faction(&"f9_a", &"f9_b")
	foe.set_faction(&"f9_b", &"f9_a")
	foe.call("take_damage", 20)

	var bb: Dictionary = BotController.build_blackboard(hero, 1.25)
	for k: String in ["self_pos", "self_vel", "self_hp_frac", "self_mp_frac", "on_floor",
			"facing", "foe_pos", "foe_vel", "foe_hp_frac", "foe_facing", "threats",
			"cooldowns", "reach", "now",
			# ...and the fields the brain layer depends on. `hazards` is first
			# because without it a solved exit vector walks into a ring-out pit.
			"hazards", "class_id", "fields", "barriers", "guard_style", "can_parry",
			"slot_affordable", "slot_cast_time"]:
		_expect(bb.has(k), "the blackboard publishes `%s`" % k)
	_expect(bb["hazards"] is Array, "`hazards` reaches the brain as an array of pit rects")
	_expect(int(bb["class_id"]) >= 0, "`class_id` names the bot's own class")
	_expect((bb["slot_affordable"] as Array).size() == BotIntent.SLOT_COUNT,
		"`slot_affordable` is one entry per kit slot")
	_expect((bb["slot_cast_time"] as Array).size() == BotIntent.SLOT_COUNT,
		"`slot_cast_time` is one entry per kit slot (the channel gate)")
	_expect(is_equal_approx(float(bb["now"]), 1.25), "`now` is the caller's scaled clock")
	_expect(bb["self_pos"] == hero.global_position, "self_pos is the body's own position")
	_expect(int(bb["foe_id"]) == foe.get_instance_id(),
		"the nearest member of the hostile group is the foe")
	_expect(bb["foe_pos"] == foe.global_position, "foe_pos is where they are drawn")
	_expect(float(bb["foe_hp_frac"]) < 1.0,
		"foe_hp_frac reads the floating health bar (got %.2f)" % float(bb["foe_hp_frac"]))
	_expect((bb["cooldowns"] as Array).size() == BotIntent.CD_COUNT,
		"cooldowns is indexed by the same numbering the intent uses")
	_expect(is_equal_approx(float(bb["reach"]), float(hero.get("_melee_range"))),
		"reach is the body's own melee range")

	# The structural fairness assertion: no key describes the opponent's readiness.
	var unfair: Array[String] = []
	for k: Variant in bb.keys():
		var name: String = String(k)
		if name.begins_with("foe_") and (name.contains("cooldown") or name.contains("cd")
				or name.contains("intent") or name.contains("mp")):
			unfair.append(name)
	_expect(unfair.is_empty(),
		"the blackboard leaks hidden opponent state: %s" % [unfair])

	# ...and a bot that is alone perceives no foe rather than an imaginary one.
	var lonely: CharacterBody2D = _make_hero(_plot(10))
	lonely.set_faction(&"f10_a", &"f10_b")
	var solo: Dictionary = BotController.build_blackboard(lonely, 0.0)
	_expect(int(solo["foe_id"]) == 0, "no hostile in the world = no foe")
	_completes("blackboard_is_fair_and_complete")


## Threat perception is limited to things DRAWN on screen: an armed telegraph ring
## and a projectile already in flight. A tell that has already fired is a picture
## of the past, and a bot's own bolt is not a threat to it.
func _test_blackboard_sees_only_drawn_threats() -> void:
	var hero: CharacterBody2D = _make_hero(_plot(11))
	hero.set_faction(&"f11_a", &"f11_b")

	var live := Telegraph.new()
	live.position = hero.global_position + Vector2(40.0, 0.0)
	root.add_child(live)
	live.start(64.0, 0.5)

	var idle := Telegraph.new()          # never started -> not armed -> invisible
	idle.position = hero.global_position + Vector2(-40.0, 0.0)
	root.add_child(idle)

	var mine: Area2D = _make_bolt(hero, &"f11_b")
	mine.global_position = hero.global_position + Vector2(10.0, 0.0)
	mine.call("launch", Vector2.RIGHT)

	var threats: Array = BotController.perceive_threats(self, hero.global_position, hero)
	var ids: Dictionary = {}
	var circle: Dictionary = {}
	for t: Variant in threats:
		var d: Dictionary = t
		ids[int(d["id"])] = true
		if int(d["id"]) == live.get_instance_id():
			circle = d
	_expect(ids.has(live.get_instance_id()), "an ARMED telegraph is perceived")
	_expect(not ids.has(idle.get_instance_id()), "an unstarted telegraph is NOT perceived")
	_expect(not ids.has(mine.get_instance_id()), "a bot does not perceive its OWN bolt")
	_expect(String(circle.get("kind", "")) == "circle", "a zone tell reports as a circle")
	_expect(circle.get("pos") == live.global_position,
		"the circle centre is world space (dodging toward (0,0) is worse than no brain)")
	_expect(float(circle.get("tti", -1.0)) > 0.0, "the tell publishes a live countdown")
	_expect(BotDodge.point_in_region(live.global_position, circle["region"]),
		"the region drops straight into BotDodge.point_in_region")

	# A bolt somebody ELSE threw is a threat, and reports a real travel velocity.
	var other: CharacterBody2D = _make_hero(_plot(11) + Vector2(400.0, 0.0))
	var incoming: Area2D = _make_bolt(other, &"f11_a")
	incoming.global_position = hero.global_position + Vector2(200.0, 0.0)
	incoming.call("launch", Vector2.LEFT)
	var t2: Array = BotController.perceive_threats(self, hero.global_position, hero)
	var found: Dictionary = {}
	for t: Variant in t2:
		if int((t as Dictionary)["id"]) == incoming.get_instance_id():
			found = t
	_expect(not found.is_empty(), "somebody else's bolt IS perceived")
	_expect((found.get("vel", Vector2.ZERO) as Vector2).x < 0.0,
		"...travelling the way it was launched (got %s)" % [found.get("vel")])
	_expect(bool(found.get("parryable", false)), "a catchable bolt reports as parryable")

	var hazards: Array[Rect2] = BotController.perceive_hazards(self)
	_expect(hazards.is_empty(), "no stage hazards in an empty test world")
	_completes("blackboard_sees_only_drawn_threats")
