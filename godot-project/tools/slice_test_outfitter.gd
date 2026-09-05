# Run: godot --headless --path godot-project --script tools/slice_test_outfitter.gd
#
# CUSTOMISATION — the three things a player can now decide that they could not before,
# and the one budget all three have to live inside.
#
#   1. CHOOSE YOUR THREE. `SpellLibrary.CLASS_KITS` authors five roles per class and
#      the hand holds three, so every class shipped with two spells nobody could
#      carry. The pick has to reach the HERO, obey the same four rules the authored
#      table is pinned to, and survive a scene change — so this drives a real
#      `build_for_class`, not a table read.
#   2. THE ARMORY, which was complete and unreachable behind an `if false:`, and which
#      measured 377 px tall against a 360 px phone.
#   3. THE COLOURWAY, whose only binding was a `C` key on a platform with no keys.
#
# ── Vacuous-pass armour (full write-up in tools/slice_test_loadout.gd) ──
# Failures accumulate on the MEMBER `_fails`; every test records a completion
# sentinel, so a test aborted by a dead property read fails BY ABSENCE rather than
# reporting "no failures". NEVER write `failed += _test_x()` in this file.
extends SceneTree

const TESTS: Array[String] = [
	"the_authored_hand_is_still_the_default",
	"a_pick_reaches_the_hero",
	"illegal_hands_are_refused",
	"the_ult_slot_is_not_a_choice",
	"every_class_offers_a_real_choice",
	"the_reserve_tracks_the_pick",
	"the_save_hook_no_ops_without_the_field",
	"the_outfitter_fits_a_phone",
	"the_armory_fits_a_phone",
	"the_lobby_still_fits_a_phone",
	"free_play_is_reachable_from_the_lobby",
	"the_colourway_is_reachable_without_a_keyboard",
	"the_hint_line_describes_the_spell_you_tapped",
	"the_grimoire_is_reachable_and_reaches_the_hero",
	"an_ult_only_fits_the_ult_slot",
	"reset_to_default_puts_the_whole_hand_back",
	"the_class_flow_has_no_armoury_door",
	"the_grimoire_says_what_is_earnable",
]

const LOBBY_SCENE: String = "res://scenes/ui/Lobby.tscn"
const PAUSE_SCRIPT: String = "res://scripts/combat/PauseMenu.gd"
const OUTFITTER_SCRIPT: String = "res://scripts/ui/Outfitter.gd"

## The description table. `preload` yields the SCRIPT OBJECT, so only `static func`
## entry points on it are callable -- which is the same call the Outfitter itself
## makes, so this suite exercises the real access path rather than a friendlier one.
const SpellBlurbs := preload("res://scripts/combat/SpellBlurbs.gd")

## Godot's base viewport, from project.godot. Everything a thumb touches has to live
## inside this in LANDSCAPE. Same numbers `tools/slice_test_shell.gd` pins.
const BASE_W: float = 640.0
const BASE_H: float = 360.0
const MIN_TAP_H: float = 28.0

var _fails: int = 0
var _completed: Dictionary = {}
var _lobby: Control = null


func _init() -> void:
	_test_the_authored_hand_is_still_the_default()
	_test_a_pick_reaches_the_hero()
	_test_illegal_hands_are_refused()
	_test_the_ult_slot_is_not_a_choice()
	_test_every_class_offers_a_real_choice()
	_test_the_reserve_tracks_the_pick()
	_test_the_save_hook_no_ops_without_the_field()
	await process_frame
	await _test_the_outfitter_fits_a_phone()
	await _test_the_armory_fits_a_phone()
	await _test_the_lobby_still_fits_a_phone()
	await _test_free_play_is_reachable_from_the_lobby()
	_test_the_colourway_is_reachable_without_a_keyboard()
	await _test_the_hint_line_describes_the_spell_you_tapped()
	await _test_the_grimoire_is_reachable_and_reaches_the_hero()
	_test_an_ult_only_fits_the_ult_slot()
	await _test_reset_to_default_puts_the_whole_hand_back()
	await _test_the_class_flow_has_no_armoury_door()
	await _test_the_grimoire_says_what_is_earnable()
	SpellLibrary.clear_slot_roles()
	SpellLibrary.clear_equipped()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Outfitter tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Outfitter tests: all PASS")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _ids(spells: Array) -> Array:
	var out: Array = []
	for s: Variant in spells:
		out.append(String((s as SpellDef).id))
	return out


## Indices into a `SpellLibrary.equippable()` pool whose shelf is / is not an ULT.
##
## ⚠ ASKED OF `SpellTier.of`, NEVER HARDCODED, and that is the whole reason this helper
## exists instead of two literal indices. The shelf is DERIVED from cast time, cooldown and
## mana — a spell is an ult because of what it costs, not because of a flag or a name. Pin
## "index 1 is the ult" and the first balance pass that slows a Tier 2 into ult territory,
## or speeds a Tier 3 out of it, leaves this suite still green while testing the opposite
## of the rule it claims to test. Ask the derivation and it cannot go quietly wrong.
static func _pool_indices(pool: Array, want_ult: bool) -> Array[int]:
	var out: Array[int] = []
	for i: int in pool.size():
		var is_ult: bool = SpellTier.of(pool[i] as SpellDef) == SpellTier.Tier.ULT
		if is_ult == want_ult:
			out.append(i)
	return out


# ---------------------------------------------------------------------------
# 1. Choose your three
# ---------------------------------------------------------------------------

## Nobody has picked anything, so nothing may have moved. This is the regression that
## matters most: the feature is a NEW answer to an OLD question, and every hero in the
## game — bots, puppets, headless fixtures — asks that question.
func _test_the_authored_hand_is_still_the_default() -> void:
	SpellLibrary.clear_slot_roles()
	for cls: int in SpellLibrary.CLASS_KITS.size():
		_expect(SpellLibrary.slot_roles_for_class(cls) == SpellLibrary.default_slot_roles_for_class(cls),
			"class %d still carries its authored hand when nobody has chosen" % cls)
		_expect(not SpellLibrary.has_custom_slot_roles(cls),
			"class %d reports no custom hand" % cls)
	# And the authored table is still the source of that default.
	_expect(SpellLibrary.default_slot_roles_for_class(0) == SpellLibrary.SLOT_ROLES[0],
		"the default comes from SLOT_ROLES, not from a second copy of it")
	# A class with no row still boots with a hand rather than nothing.
	var unknown: Array = SpellLibrary.default_slot_roles_for_class(999)
	_expect(unknown.size() == SpellTier.SLOT_COUNT,
		"an unknown class still gets %d slots (got %d)" % [SpellTier.SLOT_COUNT, unknown.size()])
	_completes("the_authored_hand_is_still_the_default")


## THE test. A pick is only real if it changes what a HERO ends up holding, and the
## only thing standing between the two is `build_for_class` — which is what
## `Hero._configure_class` calls for every hero in the game.
func _test_a_pick_reaches_the_hero() -> void:
	SpellLibrary.clear_slot_roles()
	# The Arcanist authors damage/control/answer/payoff/ult and carries
	# damage/control/payoff/ult. Take the blink instead of the clone.
	var before: Array = _ids(SpellLibrary.build_for_class(0))
	var ok: bool = SpellLibrary.set_slot_roles(0, ["damage", "answer", "payoff", "ult"])
	_expect(ok, "a legal hand is accepted")
	_expect(SpellLibrary.has_custom_slot_roles(0), "and is reported as custom")
	var after: Array = _ids(SpellLibrary.build_for_class(0))
	_expect(after != before, "the built kit actually changed (%s -> %s)" % [before, after])
	_expect(after.size() == SpellTier.SLOT_COUNT,
		"the hand is still %d spells (got %d)" % [SpellTier.SLOT_COUNT, after.size()])
	var kit: Dictionary = SpellLibrary.kit_for_class(0)
	_expect(after[0] == String(kit["damage"]), "slot 1 is the role that was picked for it")
	_expect(after[1] == String(kit["answer"]), "slot 2 is the role that was picked for it")
	_expect(after[2] == String(kit["payoff"]), "slot 3 is the role that was picked for it")
	_expect(after[SpellTier.ULT_SLOT] == String(kit["ult"]), "the last slot is still the ult")
	# Nobody else moved.
	_expect(SpellLibrary.slot_roles_for_class(1) == SpellLibrary.default_slot_roles_for_class(1),
		"choosing for the Arcanist did not touch the Shadowblade")
	# And it can be put back.
	SpellLibrary.clear_slot_roles(0)
	_expect(_ids(SpellLibrary.build_for_class(0)) == before, "clearing restores the authored hand")
	_completes("a_pick_reaches_the_hero")


## A hand a player can build must be a hand the authored-table tests would have
## accepted. Refusal has to be TOTAL — a half-applied hand is worse than no choice —
## so each case asserts the previous hand is still standing afterwards.
func _test_illegal_hands_are_refused() -> void:
	SpellLibrary.clear_slot_roles()
	var kept: Array = SpellLibrary.slot_roles_for_class(0)
	var bad: Array = [
		["damage", "control", "ult"],                        # too few
		["damage", "control", "answer", "payoff", "ult"],    # too many
		["damage", "damage", "answer", "ult"],               # the same spell twice
		["damage", "control", "answer", "payoff"],           # no ult in the ult slot
		["ult", "control", "answer", "ult"],                 # an ult outside the ult slot
		["damage", "nonsense", "answer", "ult"],             # a role this class does not author
	]
	for roles: Array in bad:
		_expect(SpellLibrary.validate_slot_roles(0, roles) != "",
			"%s is reported as illegal" % [roles])
		_expect(not SpellLibrary.set_slot_roles(0, roles), "%s is refused" % [roles])
		_expect(SpellLibrary.slot_roles_for_class(0) == kept,
			"...and the standing hand survived the refusal")
	_expect(SpellLibrary.validate_slot_roles(0, ["damage", "control", "answer", "ult"]) == "",
		"a legal hand validates clean")
	_completes("illegal_hands_are_refused")


## The last slot only accepts an ult and each class authors exactly one, so there is
## nothing to decide there — which is why the picker shows it and does not offer it.
func _test_the_ult_slot_is_not_a_choice() -> void:
	for cls: int in SpellLibrary.CLASS_KITS.size():
		var ult_role: String = SpellLibrary.ult_role_for_class(cls)
		var ult: SpellDef = SpellLibrary.spell_for_role(cls, ult_role)
		_expect(ult != null and SpellTier.of(ult) == SpellTier.Tier.ULT,
			"class %d's ult role (%s) really holds an ult" % [cls, ult_role])
		var choosable: Array = SpellLibrary.choosable_roles_for_class(cls)
		_expect(not choosable.has(ult_role),
			"class %d cannot pick its ult into an open slot" % cls)
		for role: Variant in choosable:
			var s: SpellDef = SpellLibrary.spell_for_role(cls, String(role))
			_expect(s != null and SpellTier.of(s) != SpellTier.Tier.ULT,
				"class %d's choosable role %s is not an ult" % [cls, role])
	_completes("the_ult_slot_is_not_a_choice")


## The point of the whole feature: every class must have MORE options than slots, or
## its "choice" is a screen with nothing on it.
##
## ⚠ THE CHOICE GOT SMALLER WHEN THE FOURTH SPELL SLOT LANDED, and this test is where
## that shows up as a number instead of a feeling. With 4 choosable roles it was
## choose-2 = 6 hands per class, 54 across the roster; it is choose-3 = 4 per class, 36
## across the roster. The pick is now "which one do I leave behind". That is a real
## cost of the fourth button and it is asserted, not assumed — if it ever drops to
## choose-4 the count goes to ONE per class and the screen stops being a decision at
## all, which is the failure this floor is guarding.
func _test_every_class_offers_a_real_choice() -> void:
	var open_slots: int = SpellTier.SLOT_COUNT - 1
	var total: int = 0
	for cls: int in SpellLibrary.CLASS_KITS.size():
		var choosable: Array = SpellLibrary.choosable_roles_for_class(cls)
		_expect(choosable.size() > open_slots,
			"class %d offers more than %d non-ult roles (got %d) — otherwise there is nothing to pick"
				% [cls, open_slots, choosable.size()])
		# Every combination of `open_slots` roles, which is what the picker exposes.
		var hands: Array = _combinations(choosable, open_slots)
		total += hands.size()
		# And every one of those hands must be buildable, not just countable.
		for hand: Variant in hands:
			var roles: Array = (hand as Array).duplicate()
			roles.append(SpellLibrary.ult_role_for_class(cls))
			_expect(SpellLibrary.validate_slot_roles(cls, roles) == "",
				"class %d can legally carry %s" % [cls, roles])
	_expect(total >= 27, "the roster offers at least 27 distinct hands (got %d)" % total)
	SpellLibrary.clear_slot_roles()
	_completes("every_class_offers_a_real_choice")


## Every `pick`-sized combination of `pool`, order preserved. Written out rather than
## hardcoded per arity so this suite keeps asking the real question when the hand
## width moves again.
static func _combinations(pool: Array, pick: int) -> Array:
	if pick <= 0:
		return [[]]
	if pool.size() < pick:
		return []
	var out: Array = []
	for i: int in pool.size():
		for rest: Variant in _combinations(pool.slice(i + 1), pick - 1):
			var one: Array = [pool[i]]
			one.append_array(rest as Array)
			out.append(one)
	return out


## The role you DON'T carry is the Tier 2 / Tier 3 drop pool
## (`SpellDrops` reads `reserve_for_class`). Change the hand and the pool must follow,
## or a spell ends up both carried and droppable.
func _test_the_reserve_tracks_the_pick() -> void:
	SpellLibrary.clear_slot_roles()
	var before: Array = _ids(SpellLibrary.reserve_for_class(0))
	_expect(SpellLibrary.set_slot_roles(0, ["damage", "answer", "payoff", "ult"]), "pick lands")
	var after: Array = _ids(SpellLibrary.reserve_for_class(0))
	_expect(after != before, "the drop pool followed the pick (%s -> %s)" % [before, after])
	var carried: Array = _ids(SpellLibrary.build_for_class(0))
	for id: Variant in after:
		_expect(not carried.has(id), "%s is not both carried and droppable" % id)
	_expect(carried.size() + after.size() == SpellLibrary.ROLE_ORDER.size(),
		"carried + reserve is still the whole authored kit")
	SpellLibrary.clear_slot_roles()
	_completes("the_reserve_tracks_the_pick")


## The save hook must be honest about not being wired. `Object.set()` on an undeclared
## property is a SILENT no-op, so a naive `persist_to_state` would report success
## against a `GameState` that has no field — and the pick would vanish on quit with
## nothing to show for it.
func _test_the_save_hook_no_ops_without_the_field() -> void:
	SpellLibrary.clear_slot_roles()
	var bare := _BareState.new()
	_expect(not SpellLibrary.persist_to_state(bare),
		"saving into a GameState with no `spell_roles` field reports FAILURE, not success")
	_expect(not SpellLibrary.hydrate_from_state(bare), "and loading from it is a clean no-op")
	_expect(not SpellLibrary.persist_to_state(null), "a null state is a clean no-op")
	_expect(not SpellLibrary.hydrate_from_state(null), "both ways")
	# ...and the moment the field exists, both directions work — including the
	# int/float key mangling a JSON round-trip does to dictionary keys.
	var wired := _WiredState.new()
	_expect(SpellLibrary.set_slot_roles(0, ["damage", "answer", "payoff", "ult"]), "pick lands")
	_expect(SpellLibrary.persist_to_state(wired), "saving into a wired GameState works")
	SpellLibrary.clear_slot_roles()
	_expect(SpellLibrary.hydrate_from_state(wired), "and it comes back")
	_expect(SpellLibrary.slot_roles_for_class(0) == ["damage", "answer", "payoff", "ult"],
		"exactly as it went in")
	SpellLibrary.clear_slot_roles()
	wired.spell_roles = {"0": ["damage", "answer", "payoff", "ult"]}   # what JSON gives back
	_expect(SpellLibrary.hydrate_from_state(wired), "a JSON-mangled key still restores")
	_expect(SpellLibrary.has_custom_slot_roles(0), "...onto the right class")
	SpellLibrary.clear_slot_roles()
	_completes("the_save_hook_no_ops_without_the_field")


# ---------------------------------------------------------------------------
# 2 + 3. It has to fit a phone
# ---------------------------------------------------------------------------

func _get_lobby() -> Control:
	if _lobby != null and is_instance_valid(_lobby):
		return _lobby
	_lobby = (load(LOBBY_SCENE) as PackedScene).instantiate()
	root.add_child(_lobby)
	return _lobby


func _walk(from: Node, out: Array) -> void:
	if from is Button:
		out.append(from)
	for c: Node in from.get_children():
		_walk(c, out)


func _check_fits(col: Control, what: String) -> void:
	var needed: Vector2 = col.get_combined_minimum_size()
	_expect(needed.y <= BASE_H, "the %s fits 360 px of height (needs %.0f)" % [what, needed.y])
	_expect(needed.x <= BASE_W, "the %s fits 640 px of width (needs %.0f)" % [what, needed.x])


func _test_the_outfitter_fits_a_phone() -> void:
	var lobby: Control = _get_lobby()
	lobby.size = Vector2(BASE_W, BASE_H)
	await process_frame
	lobby.call("_open_outfitter")
	await process_frame
	await process_frame
	var out: Control = lobby.get("_outfitter")
	_expect(out != null, "the Loadout button opens the outfitter")
	if out == null:
		_completes("the_outfitter_fits_a_phone")
		return
	_check_fits(out.get("_col") as Control, "outfitter")
	# The number, printed. A budget nobody can see is a budget nobody notices getting
	# tighter -- and this column has 360 px and no more, on the screen that grew a
	# description line this pass.
	var col0: Control = out.get("_col") as Control
	if col0 != null:
		print("[layout] outfitter column min %.0fx%.0f (budget %.0fx%.0f)"
			% [col0.get_combined_minimum_size().x, col0.get_combined_minimum_size().y,
				BASE_W, BASE_H])
	var buttons: Array = []
	_walk(out, buttons)
	_expect(buttons.size() >= 6,
		"it offers the roles, the armory, the colour and a way out (found %d)" % buttons.size())
	for b: Button in buttons:
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"outfitter '%s' is at least %.0f px tall (got %.0f)"
				% [b.text, MIN_TAP_H, b.custom_minimum_size.y])
		_expect(b.focus_mode == Control.FOCUS_NONE, "outfitter '%s' takes no focus ring" % b.text)
	# The list is bounded by its own constant, not by the roster: a class that
	# authored fifteen roles would scroll, not grow the panel.
	var scroll: ScrollContainer = out.get("_scroll") as ScrollContainer
	_expect(scroll != null and scroll.get_combined_minimum_size().y <= out.get("LIST_H") + 1.0,
		"the role list is bounded by LIST_H, so the roster cannot decide the panel height")
	# ⚠ THE ULT ROW MUST NOT BE IN THE SCROLL. It was, and it was the fifth row of a
	# four-row list — so the one row that makes the hand read as THREE was the row
	# that scrolled off. Caught by a capture, not by an assertion, which is why there
	# is now an assertion.
	var ult_row: Control = out.get("_ult_slot_row") as Control
	_expect(ult_row != null and scroll != null and not scroll.is_ancestor_of(ult_row),
		"the ult slot is shown in fixed space, not inside the scrolling list")
	_expect(ult_row != null and ult_row.get_child_count() > 0, "...and it is populated")
	# And a tap on a role really rewrites the hand.
	var picked: Array = SpellLibrary.choosable_roles_for_class(out.call("class_id"))
	if picked.size() >= 3:
		var before: Array = _ids(SpellLibrary.build_for_class(out.call("class_id")))
		out.call("_toggle_role", String(picked[2]))
		var after: Array = _ids(SpellLibrary.build_for_class(out.call("class_id")))
		_expect(after != before, "tapping a role changes the hand a hero would build")
	SpellLibrary.clear_slot_roles()
	_completes("the_outfitter_fits_a_phone")


## The armory measured 560x377 before this — 17 px TALLER than the whole base
## viewport, so its bottom row was off the screen on the only platform that matters.
## Nobody had noticed because nothing could open it.
func _test_the_armory_fits_a_phone() -> void:
	var lo: Node = root.get_node_or_null(^"Loadout")
	_expect(lo != null, "the Loadout autoload is registered")
	if lo == null:
		_completes("the_armory_fits_a_phone")
		return
	lo.call("open")
	await process_frame
	await process_frame
	_expect(bool(lo.call("is_open")), "it opens")
	var col: Control = lo.get("_col") as Control
	_expect(col != null, "the armory column is reachable for measurement")
	if col != null:
		_check_fits(col, "armory")
	var buttons: Array = []
	_walk(lo, buttons)
	# 11 weapons + 4 heads + 4 bodies + Done.
	_expect(buttons.size() >= 20, "every piece is offered (found %d buttons)" % buttons.size())
	for b: Button in buttons:
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"armory '%s' is at least %.0f px tall (got %.0f)"
				% [b.text, MIN_TAP_H, b.custom_minimum_size.y])
	# Gear is a LOADOUT, not a ladder: every effect bag is a per-run modifier and
	# none of them accumulate. Asserted as "no piece grants a permanent-sounding
	# key" so a future piece that does gets caught at the data level.
	const BANNED: Array[String] = ["permanent", "xp", "level", "unlock", "bonus_stack"]
	for kind: Variant in GearAbilities.ABILITIES:
		var effect: Dictionary = GearAbilities.effect(String(kind))
		for key: Variant in effect:
			_expect(not BANNED.has(String(key)),
				"gear '%s' effect key '%s' is a per-run modifier, not progression" % [kind, key])
	lo.call("close")
	_completes("the_armory_fits_a_phone")


## The whole point of pairing the four secondary actions into two rows: four new
## reachable things, and not one pixel of extra height. If a future row breaks this,
## the bottom button walks off a 360 px screen — which nobody notices on a desktop.
func _test_the_lobby_still_fits_a_phone() -> void:
	var lobby: Control = _get_lobby()
	lobby.size = Vector2(BASE_W, BASE_H)
	await process_frame
	await process_frame
	_check_fits(lobby.get("_col") as Control, "lobby column")
	var buttons: Array = []
	_walk(lobby.get("_col") as Control, buttons)
	var labels: Array[String] = []
	for b: Button in buttons:
		labels.append(b.text)
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"lobby '%s' is at least %.0f px tall (got %.0f)"
				% [b.text, MIN_TAP_H, b.custom_minimum_size.y])
	var joined: String = " | ".join(labels)
	# Free Play and Loadout MOVED INTO THE ANTECHAMBER (the ring and the rack) when
	# the maker asked twice for fewer title buttons. What a title screen still has to
	# offer is the choice it exists to ask: alone, or with someone.
	# ⚠ "ENTER THE TOWER" -> "SINGLE PLAYER" (2026-09, maker: *"reword it to Single
	# Player and Multiplayer"*). Only the string moved; the claim is still "the title
	# screen offers the choice it exists to ask — alone, or with someone".
	for wanted: String in ["SINGLE PLAYER", "Host Co-op", "Join"]:
		_expect(joined.contains(wanted), "the lobby offers '%s' (has: %s)" % [wanted, joined])
	_completes("the_lobby_still_fits_a_phone")


## Free play was in exactly the state the Lobby itself was in before it became the
## boot scene: built, tested, and reachable from nothing. It is the game's only
## no-pressure surface, so it is the game's only onboarding.
func _test_free_play_is_reachable_from_the_lobby() -> void:
	var lobby: Control = _get_lobby()
	_expect(bool(lobby.call("free_play_available")),
		"the free-play scene exists in this build")
	var script: GDScript = load(lobby.get("FREE_PLAY_SCRIPT")) as GDScript
	_expect(script != null, "the lobby's free-play path resolves")
	if script != null:
		_expect(script.get_script_method_list().any(
			func(m: Dictionary) -> bool: return String(m.get("name", "")) == "enter"),
			"and it offers the static `enter` the lobby calls")
	# ⚠ MOVED INTO THE ANTECHAMBER on 2026-08-04. Maker, twice: "the tower intro
	# still has too many buttons". The room owns these now — the RING is free play,
	# the RACK is the armoury, the STATUE is class. `slice_test_town` asserts the
	# stations exist there; asserting them HERE would re-pin the duplication that
	# was the complaint.
	_expect(lobby.get("_free_btn") == null,
		"free play is NOT a title button any more — it is the sparring ring")
	# Reached by PATH, never by the bare class identifier — a hard reference from the
	# boot scene would drag the versus arena's dependency chain into its compile.
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/Lobby.gd")
	_expect(src.contains("FREE_PLAY_SCRIPT"), "by path, so a build without it hides the button")
	await process_frame
	_completes("free_play_is_reachable_from_the_lobby")


## THE COLOURWAY IS NOT ON THIS SCREEN ANY MORE -- AND ITS STATE SURVIVED THE CUT.
##
## Maker: *"remove that azure ember etc. options within the class selection"*. So the
## picker row is gone from the Outfitter. What this test now pins is the thing that is
## easy to get wrong when a UI row is deleted: `Outfitter.chosen_colourway`,
## `colourways()` and `colourway_name()` are read by THREE files outside this one --
## `scripts/combat/PauseMenu.gd`, `scripts/Settings.gd` and
## `tools/slice_test_settings.gd` -- and deleting the statics along with the button
## would have been a parse-time break in files this pass does not own.
##
## So: the button is gone, the API is not, and the colourway is still reachable on a
## touchscreen -- through the pause menu's appearance row, which is where a cosmetic
## belongs and where it already was.
func _test_the_colourway_is_reachable_without_a_keyboard() -> void:
	var palette: Array = Outfitter.colourways()
	_expect(palette.size() >= 2, "there is a palette to choose from (%d entries)" % palette.size())
	_expect(Outfitter.colourway_name(0) != "", "entries are still named for the picker")
	# Past the end of the name list is a number, not a crash or a dropped entry.
	_expect(Outfitter.colourway_name(99) != "", "an unnamed colourway still reads")

	# THE ROW IS GONE FROM THIS SCREEN. Asserted against the source rather than by
	# walking the tree, because "no button whose text happens to contain a colour name"
	# is a check that passes for the wrong reason the moment a colour is renamed.
	var out_src: String = FileAccess.get_file_as_string(OUTFITTER_SCRIPT)
	_expect(out_src != "", "the Outfitter source is readable")
	_expect(not out_src.contains("_cycle_colour("),
		"the Outfitter no longer builds a colourway picker -- it is noise on the one "
		+ "screen whose question is which of nine fighters you are about to be")
	# ...and the static the OTHER three files read is still declared here.
	_expect(out_src.contains("static var chosen_colourway"),
		"but `chosen_colourway` survives: PauseMenu.gd, Settings.gd and "
		+ "slice_test_settings.gd all read it, and none of them is ours to change")

	var src: String = FileAccess.get_file_as_string(PAUSE_SCRIPT)
	_expect(src.contains("_build_appearance"), "the pause menu carries an appearance row")
	_expect(src.contains("_sync_colourway"), "...that applies the picked colourway to the live hero")
	# The pause menu is the ONE settings surface reachable on a touchscreen (it owns
	# the on-screen pause button), which is why the colourway can leave this screen
	# without leaving the game.
	_expect(src.contains("PAUSE_BTN_SIZE"), "and the pause menu is itself touch-reachable")
	_completes("the_colourway_is_reachable_without_a_keyboard")


## EVERY SPELL SAYS WHAT IT DOES, ON THE SCREEN WHERE YOU PICK IT.
##
## Maker: *"each spell should have a description of what it does, short and sweet but
## in an epic way and clear what it does"*. The Outfitter is where a hand is actually
## chosen, and until this pass it listed four role rows as bare names -- so choosing
## between them was choosing between words. The header line, which used to be a
## one-off instruction nobody re-reads, now carries the blurb for whichever role was
## last tapped.
##
## Driven, not inspected: the real `_toggle_role` is called and the real Label is read
## back, because a `_refresh_blurb` that exists and is never reached is exactly the
## shape of a screen that ships blank.
##
## CONFIRMED TO FAIL: dropping the `_refresh_blurb()` call out of `_redraw()` reports
##   FAIL: tapping the damage role puts its description on screen (line was ...)
func _test_the_hint_line_describes_the_spell_you_tapped() -> void:
	var out: Control = load(OUTFITTER_SCRIPT).new() as Control
	root.add_child(out)
	await process_frame
	out.call("set_class", 8)          # Swordsaint -- four distinct, well-described spells
	await process_frame
	var hint: Label = out.get("_hint") as Label
	_expect(hint != null, "the Outfitter still has a header line to write into")
	if hint == null:
		out.queue_free()
		_completes("the_hint_line_describes_the_spell_you_tapped")
		return

	# ON OPEN it describes the ULT. The finisher is the most interesting line on any
	# hand and the one row that is NOT a choice, so it is the only default that cannot
	# also read as a hint about what you should carry.
	var ult_role: String = String(out.get("_ult_role"))
	var ult: SpellDef = SpellLibrary.spell_for_role(8, ult_role)
	_expect(ult != null and hint.text == SpellBlurbs.for_spell(ult),
		"the screen opens describing the ult (line was: %s)" % hint.text)

	# ...and tapping a role re-points it at that role's spell.
	for role: Variant in SpellLibrary.choosable_roles_for_class(8):
		var r: String = String(role)
		out.call("_toggle_role", r)
		await process_frame
		var spell: SpellDef = SpellLibrary.spell_for_role(8, r)
		_expect(spell != null, "the Swordsaint authors a `%s` spell" % r)
		if spell == null:
			continue
		var want: String = SpellBlurbs.for_spell(spell)
		_expect(want != "", "`%s` has a description at all" % spell.id)
		_expect(hint.text == want,
			"tapping the %s role puts ITS description on screen (wanted: %s / line was: %s)"
				% [r, want, hint.text])

	# AND THE LINE IS BOUNDED. It reserves two lines of height so the panel measures the
	# same for every class; a blurb long enough to need three would push a 360 px screen
	# off a phone, and only a capture would ever show it.
	_expect(hint.custom_minimum_size.y >= 20.0,
		"the blurb line reserves its two lines (%.0f px) so the panel height is a "
			% hint.custom_minimum_size.y
		+ "constant rather than a function of which role is selected")
	out.queue_free()
	SpellLibrary.clear_slot_roles()
	_completes("the_hint_line_describes_the_spell_you_tapped")


## THE GRIMOIRE — THE ELEVEN SPELLS ONLY BOTS COULD CAST, PUT IN A PLAYER'S HAND.
##
## `SpellLibrary` grew `equippable` / `set_equipped` / `equipped_id` / `clear_equipped`
## and NOTHING CALLED THEM: the nine Tier 3s and both Tier 2s were reachable from no
## screen in the game, so the mechanism was fully tested and completely unreachable —
## which is the same shape the Armory was in before it got a button.
##
## DRIVEN THROUGH THE REAL BUTTONS, never through the handlers. Every step below reaches
## a `Button` in the live tree and emits its `pressed` signal, because the failure this
## suite exists to catch is not "the handler is wrong" — it is "the handler is right and
## nothing is connected to it", which is precisely the bug being fixed.
##
## CONFIRMED TO FAIL: dropping the `SpellLibrary.set_equipped(...)` call out of
## `Outfitter._toggle_equip` reports
##   FAIL: tapping a grimoire row equips it into the aimed slot (slot 0 holds '')
##   FAIL: ...and a hero built for this class actually casts it
##   FAIL: the equipped spell reaches GameState.spell_equipped, so it survives a quit
##   FAIL: the equipped row is drawn in HudStyle.GOLD ...
func _test_the_grimoire_is_reachable_and_reaches_the_hero() -> void:
	SpellLibrary.clear_slot_roles()
	SpellLibrary.clear_equipped()
	var out: Control = load(OUTFITTER_SCRIPT).new() as Control
	root.add_child(out)
	await process_frame
	out.call("set_class", 0)
	await process_frame

	# THE POOL EXISTS AND IS THE THING THE MAKER ASKED FOR.
	#
	# ⚠ IT WAS ELEVEN AND IS NOW THE WHOLE LIBRARY ABOVE THE JAB SHELF, and the earlier
	# claim is narrowed rather than dropped. It read "eleven spells, every one of them a
	# Tier 2 or a Tier 3" — true while `equippable()` was exactly `build_tier2() +
	# build_tier3()`. Maker, 2026-09: *"it shouldnt prevent any player for taking any
	# spell"*, so `equippable()` now unions in the ORPHANS (`unequipped_ids()` — spells no
	# class authors), which is ~18-20 rows. Eleven is therefore a FLOOR, not the count: the
	# number is not written down here because a number copied out of a derivation is a
	# number that goes stale the next time a spell is authored.
	var pool: Array = SpellLibrary.equippable()
	_expect(pool.size() >= 11, "the grimoire offers the showcase pool (%d spells)" % pool.size())
	_expect(pool.size() > 11,
		"...and the orphans too, so no spell in the game is unreachable (%d spells)"
			% pool.size())
	# Named against the real derivation, so "the orphans are in" cannot pass by coincidence.
	var pool_ids: Array = _ids(pool)
	for orphan: Variant in SpellLibrary.unequipped_ids():
		_expect(pool_ids.has(String(orphan)),
			"the orphan '%s' is offered — 'no class happens to carry it' is a fact about "
				% orphan
			+ "the kits, not a reason to hide it from the screen whose job is choosing")
	for s: Variant in pool:
		var tier: int = SpellTier.of(s as SpellDef)
		_expect(tier != SpellTier.Tier.QUICK,
			"'%s' is a HEAVY or an ULT — the pool is the loud things, not the jabs"
				% (s as SpellDef).id)
		_expect(SpellBlurbs.for_spell(s as SpellDef) != "",
			"'%s' says what it does before you choose it" % (s as SpellDef).id)

	# ── THE DOOR ────────────────────────────────────────────────────────────────
	var door: Button = out.get("_grim_btn") as Button
	_expect(door != null, "the Outfitter carries a grimoire door")
	if door == null:
		out.queue_free()
		_completes("the_grimoire_is_reachable_and_reaches_the_hero")
		return
	_expect(door.custom_minimum_size.y >= MIN_TAP_H,
		"the door is a real tap target (%.0f px)" % door.custom_minimum_size.y)
	door.pressed.emit()
	await process_frame
	var list: VBoxContainer = out.get("_list") as VBoxContainer
	var rows: Array = []
	_walk(list, rows)
	_expect(rows.size() == pool.size(),
		"the bounded scroll now shows the pool, one row each (%d rows / %d spells)"
			% [rows.size(), pool.size()])
	# ⚠ AND THE PANEL DID NOT GROW. Eleven 30px rows is 363px of content in a 132px
	# scroll; if the list were ever allowed to size the panel this is the screen that
	# would walk off the bottom of a phone. Measured here rather than assumed, because
	# the mode swap is the only thing standing between the two.
	_check_fits(out.get("_col") as Control, "outfitter in grimoire mode")
	var gscroll: ScrollContainer = out.get("_scroll") as ScrollContainer
	_expect(gscroll != null and gscroll.get_combined_minimum_size().y <= out.get("LIST_H") + 1.0,
		"the pool is bounded by LIST_H like the role list — eleven rows scroll, "
		+ "they do not grow the panel (scroll needs %.0f)"
			% [gscroll.get_combined_minimum_size().y if gscroll != null else -1.0])
	var col: Control = out.get("_col") as Control
	print("[layout] outfitter grimoire column min %.0fx%.0f (budget %.0fx%.0f)"
		% [col.get_combined_minimum_size().x, col.get_combined_minimum_size().y,
			BASE_W, BASE_H])
	var all_btns: Array = []
	_walk(out, all_btns)
	for b: Button in all_btns:
		_expect(b.custom_minimum_size.y >= MIN_TAP_H,
			"grimoire '%s' is at least %.0f px tall (got %.0f)"
				% [b.text, MIN_TAP_H, b.custom_minimum_size.y])
		_expect(b.focus_mode == Control.FOCUS_NONE, "grimoire '%s' takes no focus ring" % b.text)

	# ── THE PICK ────────────────────────────────────────────────────────────────
	# ⚠ THE SPELL IS CHOSEN BY ITS SHELF, NOT BY ITS INDEX. This block used to take
	# `pool[0]` and the one below took `pool[1]`, which worked only for as long as the pool
	# happened to start with two non-ults. Slot 0 is not the ult slot, so what belongs here
	# is "the first row that is not an ult" — see `_pool_indices`.
	var open_idx: Array[int] = _pool_indices(pool, false)
	var ult_idx: Array[int] = _pool_indices(pool, true)
	_expect(open_idx.size() >= 2,
		"the pool offers at least two non-ults, or the open slots have nothing to hold (%d)"
			% open_idx.size())
	_expect(ult_idx.size() >= 1,
		"...and at least one ult, or the ult-slot rule is untestable (%d)" % ult_idx.size())
	if open_idx.size() < 2 or ult_idx.is_empty():
		out.queue_free()
		_completes("the_grimoire_is_reachable_and_reaches_the_hero")
		return
	var before: Array = _ids(SpellLibrary.build_for_class(0))
	var want: SpellDef = pool[open_idx[0]] as SpellDef
	(rows[open_idx[0]] as Button).pressed.emit()
	await process_frame
	_expect(SpellLibrary.equipped_id(0, 0) == String(want.id),
		"tapping a grimoire row equips it into the aimed slot (slot 0 holds '%s')"
			% SpellLibrary.equipped_id(0, 0))
	var after: Array = _ids(SpellLibrary.build_for_class(0))
	_expect(after.has(String(want.id)),
		"...and a hero built for this class actually casts it (%s)" % [after])
	_expect(after.size() == SpellTier.SLOT_COUNT, "the hand is still %d spells" % SpellTier.SLOT_COUNT)
	_expect(after[0] == String(want.id), "in the slot it was aimed at, not another one")
	# YOU CAN SEE WHAT IT DOES. The blurb line follows the tap, which is the whole reason
	# a list of eleven names is a choice rather than a guess.
	var hint: Label = out.get("_hint") as Label
	_expect(hint != null and hint.text == SpellBlurbs.for_spell(want),
		"the description line follows the pick (wanted: %s / line was: %s)"
			% [SpellBlurbs.for_spell(want), hint.text if hint != null else "<none>"])
	# IT SAVES. `GameState` carries `spell_equipped`, so `persist_to_state` is not a
	# no-op any more — a pick that did not reach it would vanish on quit with nothing
	# on screen to say so.
	var gs: Node = root.get_node_or_null(^"GameState")
	_expect(gs != null, "the GameState autoload is registered")
	if gs != null:
		var saved: Variant = gs.get(&"spell_equipped")
		_expect(saved is Dictionary and (saved as Dictionary).has(0),
			"the equipped spell reaches GameState.spell_equipped, so it survives a quit (%s)"
				% [saved])

	# ── IT READS AS THE RARE THING ──────────────────────────────────────────────
	var rows2: Array = []
	_walk(out.get("_list"), rows2)
	_expect((rows2[open_idx[0]] as Button).get_theme_color(&"font_color") == HudStyle_GOLD(),
		"the equipped row is drawn in HudStyle.GOLD (got %s)"
			% [(rows2[open_idx[0]] as Button).get_theme_color(&"font_color")])
	_expect((rows2[open_idx[1]] as Button).get_theme_color(&"font_color") != HudStyle_GOLD(),
		"...and an unequipped one is not, so the badge means something")

	# ── THE SLOT CURSOR ─────────────────────────────────────────────────────────
	# Equipping by INDEX needs a slot before it needs a spell. The fixed row under the
	# list is that cursor; it must be a real button and it must move.
	var cursor_holder: Control = out.get("_ult_slot_row") as Control
	_expect(cursor_holder != null and cursor_holder.get_child_count() > 0,
		"the fixed row carries the slot cursor in grimoire mode")
	var cursor: Button = cursor_holder.get_child(0) as Button
	_expect(cursor != null, "...and it is pressable")
	if cursor != null:
		cursor.pressed.emit()
		await process_frame
		_expect(int(out.get("_grim_slot")) == 1, "tapping the cursor aims at the next slot")
		var rows3: Array = []
		_walk(out.get("_list"), rows3)
		# ⚠ THIS ASSERTION USED TO SAY THE OPPOSITE, AND THE RULING THAT CHANGED IT IS
		# NAMED RATHER THAN DELETED. It read `want2 = pool[1]` / `rows3[1]` and claimed
		# "a second pick lands in the newly aimed slot" for ANY pool row — which was true
		# while the only restriction on `set_equipped` was "an id inside the pool".
		#
		# Maker, 2026-09: *"all the ults in the grimoire should only be able to be swapped
		# with the existing ult, no one can have multiple ults"*. `SpellLibrary.set_equipped`
		# now returns FALSE for an ult-shelf spell aimed at any slot but `SpellTier.ULT_SLOT`,
		# so the old assertion was aiming an ult at slot 1 and asserting it landed. The claim
		# survives, narrowed to the spells the rule still allows there: a NON-ult lands in the
		# newly aimed non-ult slot.
		var want2: SpellDef = pool[open_idx[1]] as SpellDef
		(rows3[open_idx[1]] as Button).pressed.emit()
		await process_frame
		_expect(SpellLibrary.equipped_id(0, 1) == String(want2.id),
			"a second NON-ULT pick lands in the newly aimed slot (slot 1 holds '%s')"
				% SpellLibrary.equipped_id(0, 1))
		_expect(SpellLibrary.equipped_id(0, 0) == String(want.id),
			"...and the first one is still there — slots are independent")

		# ── AND THE OTHER DIRECTION: AN ULT AIMED AT SLOT 1 IS NOT OFFERED ───────
		# The rule is only half kept if the library refuses the pick; the other half is
		# that the SCREEN must not present a row it knows will be refused. Driven through
		# the real Button, because "the handler is right and nothing is connected" is the
		# bug class this suite exists for — and here the *absence* of the connection IS
		# the feature, so emitting `pressed` must move nothing.
		# ⚠ RE-WALKED. The `pressed.emit()` above ran a real `_redraw`, which frees every
		# row and rebuilds the list — so `rows3` is a list of freed objects by now, and
		# reading it is a script error rather than a failing assertion (which this suite's
		# completion sentinels catch, but only as "the test aborted").
		var rows3b: Array = []
		_walk(out.get("_list"), rows3b)
		var ult_row: Button = rows3b[ult_idx[0]] as Button
		var ult_spell: SpellDef = pool[ult_idx[0]] as SpellDef
		_expect(ult_row.disabled,
			"aiming slot 1, the ult row '%s' is drawn as unavailable, not as a live button"
				% ult_row.text)
		_expect(ult_row.text.contains("slot %d only" % (SpellTier.ULT_SLOT + 1)),
			"...and the row itself says WHERE it can go — a phone has no hover to ask "
			+ "(row was: %s)" % ult_row.text)
		var held_before_ult: String = SpellLibrary.equipped_id(0, 1)
		ult_row.pressed.emit()
		await process_frame
		_expect(SpellLibrary.equipped_id(0, 1) == held_before_ult,
			"...and tapping it moves NOTHING — slot 1 still holds '%s'"
				% SpellLibrary.equipped_id(0, 1))
		# The tap is refused; the QUESTION is not. Same rule the fixed ult ROLE row obeys:
		# the one row a player cannot act on must not also be the one row that says nothing.
		var blocked_hint: Label = out.get("_hint") as Label
		out.call("_on_blocked_row_input",
			_press_event(), String(ult_spell.id))
		await process_frame
		_expect(blocked_hint != null and blocked_hint.text.contains("slot %d"
				% (SpellTier.ULT_SLOT + 1)),
			"tapping a blocked row explains itself on the description line (line was: %s)"
				% [blocked_hint.text if blocked_hint != null else "<none>"])

		# ── AIM THE ULT SLOT AND THE SAME SPELL IS TAKEABLE ──────────────────────
		# One ult, in the ult slot. This is the direction the maker asked FOR, and without
		# it the rule above is indistinguishable from "ults cannot be equipped at all".
		# ⚠ THE CURSOR IS RE-FETCHED EVERY TAP, for the same reason the rows are re-walked:
		# `_cycle_grim_slot` redraws, and the redraw frees and rebuilds the fixed row. The
		# `cursor` captured above is a freed object from its first press onward. Driven
		# through the live button each time rather than by calling `_cycle_grim_slot`,
		# because "nothing is connected to it" is the bug this suite is for.
		while int(out.get("_grim_slot")) != SpellTier.ULT_SLOT:
			var holder: Control = out.get("_ult_slot_row") as Control
			(holder.get_child(0) as Button).pressed.emit()
			await process_frame
		var rows_ult: Array = []
		_walk(out.get("_list"), rows_ult)
		var ult_row2: Button = rows_ult[ult_idx[0]] as Button
		_expect(not ult_row2.disabled,
			"aiming the ult slot, the same ult row IS live (row was: %s)" % ult_row2.text)
		ult_row2.pressed.emit()
		await process_frame
		_expect(SpellLibrary.equipped_id(0, SpellTier.ULT_SLOT) == String(ult_spell.id),
			"an ult equips into the ult slot (slot %d holds '%s')"
				% [SpellTier.ULT_SLOT + 1, SpellLibrary.equipped_id(0, SpellTier.ULT_SLOT)])
		_expect(_ids(SpellLibrary.build_for_class(0)).has(String(ult_spell.id)),
			"...and a hero built for this class actually casts it")
		SpellLibrary.clear_equipped(0, SpellTier.ULT_SLOT)

	# ── AND YOU CAN TAKE IT BACK OUT ────────────────────────────────────────────
	# Tap-again-to-undo, the same gesture the role list uses. There is deliberately no
	# separate Clear button for ONE slot: on a phone that is a second target for a decision
	# the player's thumb is already on. (The Reset Hand button is a different question —
	# it puts the WHOLE class back, and is covered by its own test below.)
	SpellLibrary.clear_equipped(0, 1)
	while int(out.get("_grim_slot")) != 0:
		out.call("_cycle_grim_slot")      # ...back round onto the equipped slot
	await process_frame
	var rows4: Array = []
	_walk(out.get("_list"), rows4)
	(rows4[open_idx[0]] as Button).pressed.emit()
	await process_frame
	_expect(SpellLibrary.equipped_id(0, 0) == "",
		"tapping the equipped row again takes it back out")
	_expect(_ids(SpellLibrary.build_for_class(0)) == before,
		"...and the authored hand comes back exactly as it was")

	# ── THE ROLE LIST STILL WORKS, AND IT TELLS THE TRUTH ───────────────────────
	# Both mechanisms coexist by design: roles pick WHICH of the authored five you carry,
	# the grimoire lays a Tier 3 over a slot INDEX. What the role row must never do is go
	# on naming the authored spell for a slot the grimoire has taken over.
	_expect(SpellLibrary.set_equipped(0, 0, String(want.id)), "re-equip for the role check")
	door.pressed.emit()                   # back to the hand
	await process_frame
	_expect(not bool(out.get("_grimoire")), "the door goes both ways")
	var role_rows: Array = []
	_walk(out.get("_list"), role_rows)
	var slot0_role: String = String(SpellLibrary.slot_roles_for_class(0)[0])
	var found: bool = false
	for b: Button in role_rows:
		if not b.text.to_lower().contains(slot0_role.to_lower()):
			continue
		found = true
		_expect(b.text.contains(String(want.display_name)),
			"the role row for the overridden slot names what it ACTUALLY casts (%s)" % b.text)
		_expect(b.get_theme_color(&"font_color") == HudStyle_GOLD(),
			"...and is badged gold like everything else the grimoire touched")
	_expect(found, "the '%s' role row is still in the hand list" % slot0_role)
	# The summary is one colour by construction (it is a plain Label whose height must be
	# a constant), so the badge there is a glyph.
	var summary: Label = out.get("_summary") as Label
	_expect(summary != null and summary.text.contains("◈"),
		"the carried-hand line marks the rare one (line was: %s)"
			% [summary.text if summary != null else "<none>"])
	# And the panel still fits with a grimoire spell in the hand.
	_check_fits(out.get("_col") as Control, "outfitter with a grimoire spell equipped")

	out.queue_free()
	SpellLibrary.clear_equipped()
	SpellLibrary.clear_slot_roles()
	_completes("the_grimoire_is_reachable_and_reaches_the_hero")


## A press, as the blocked-row handler wants it. `_on_blocked_row_input` gates on a
## PRESSED mouse/touch event exactly like `_on_locked_row_input` does, so a bare
## `InputEvent.new()` would be silently ignored and the assertion under it would then be
## measuring nothing.
static func _press_event() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


## ══ ONE ULT, AND IT GOES IN THE ULT SLOT ═════════════════════════════════════
## Maker: *"all the ults in the grimoire should only be able to be swapped with the
## existing ult, no one can have multiple ults"*.
##
## The test above drives this through the real buttons; this one asks the LIBRARY
## directly, across the whole pool and every slot, because the UI can only ever exercise
## the rows a player happens to tap. Between them: the screen does not offer it, and the
## thing underneath would refuse it anyway.
##
## ⚠ EVERY SPELL IS CLASSIFIED BY `SpellTier.of`, NEVER BY ID. See `_pool_indices`.
##
## CONFIRMED TO FAIL: removing the `SpellTier.of(picked) == ULT` guard from
## `SpellLibrary.set_equipped` reports
##   FAIL: the ult 'the_void' is REFUSED in slot 0 — a hand carries one finisher
func _test_an_ult_only_fits_the_ult_slot() -> void:
	SpellLibrary.clear_equipped()
	var pool: Array = SpellLibrary.equippable()
	var ults: int = 0
	var opens: int = 0
	for s: Variant in pool:
		var spell: SpellDef = s as SpellDef
		var id: String = String(spell.id)
		var is_ult: bool = SpellTier.of(spell) == SpellTier.Tier.ULT
		for slot: int in SpellTier.SLOT_COUNT:
			var ok: bool = SpellLibrary.set_equipped(0, slot, id)
			if is_ult and slot != SpellTier.ULT_SLOT:
				_expect(not ok,
					"the ult '%s' is REFUSED in slot %d — a hand carries one finisher"
						% [id, slot])
				_expect(SpellLibrary.equipped_id(0, slot) != id,
					"...and nothing was half-applied into slot %d" % slot)
			else:
				# THE OTHER DIRECTION, and it is not decoration. A rule enforced by
				# refusing everything is not a rule, it is a broken screen — so every
				# legal placement is asserted to still land.
				_expect(ok, "'%s' is accepted in slot %d" % [id, slot])
				_expect(SpellLibrary.equipped_id(0, slot) == id,
					"...and slot %d really holds it (holds '%s')"
						% [slot, SpellLibrary.equipped_id(0, slot)])
			SpellLibrary.clear_equipped(0, slot)
		if is_ult:
			ults += 1
		else:
			opens += 1
	# A pool of all-ults or no-ults would make both halves above vacuous.
	_expect(ults >= 1, "the pool contains at least one ult (%d)" % ults)
	_expect(opens >= 1, "...and at least one non-ult (%d)" % opens)
	# ⚠ AND A NON-ULT IS STILL WELCOME IN THE ULT SLOT. The maker asked that nobody carry
	# FOUR finishers, not that the last slot refuse anything ordinary — the asymmetry is
	# deliberate and is asserted so a future "tidy-up" that makes the rule symmetric gets
	# caught here rather than as a slot a player cannot fill.
	var open_idx: Array[int] = _pool_indices(pool, false)
	if not open_idx.is_empty():
		var plain: String = String((pool[open_idx[0]] as SpellDef).id)
		_expect(SpellLibrary.set_equipped(0, SpellTier.ULT_SLOT, plain),
			"a NON-ult may still be equipped into the ult slot ('%s')" % plain)
	SpellLibrary.clear_equipped()
	_completes("an_ult_only_fits_the_ult_slot")


## ══ RESET TO DEFAULT ═════════════════════════════════════════════════════════
## Maker: *"also add a reset to default button to the grimoire"*.
##
## What "default" means here is the decision worth testing, not the button. The screen
## carries TWO mechanisms that both move the hand — the role picks (`_chosen_roles`) and
## the grimoire overlay (`_equipped`) — and `_summary` is drawn from `build_for_class`,
## which carries both. So a reset that cleared only the grimoire would leave that line
## showing a non-default hand one row under a button claiming it had restored the default.
## Both tables, one class: asserted below in the only way that can catch a half-reset,
## which is to dirty BOTH before pressing it.
##
## Driven through the real Button, never through `_reset_to_defaults` — the failure this
## suite exists to catch is "the handler is right and nothing is connected to it".
##
## CONFIRMED TO FAIL: dropping the `clear_slot_roles` line out of
## `Outfitter._reset_to_defaults` reports
##   FAIL: ...and the role picks too — a half-reset leaves the summary line lying
func _test_reset_to_default_puts_the_whole_hand_back() -> void:
	SpellLibrary.clear_slot_roles()
	SpellLibrary.clear_equipped()
	var out: Control = load(OUTFITTER_SCRIPT).new() as Control
	root.add_child(out)
	await process_frame
	out.call("set_class", 0)
	await process_frame
	var authored: Array = _ids(SpellLibrary.build_for_class(0))

	# DIRTY BOTH HALVES. A role pick AND a grimoire overlay, so a reset that only clears
	# one of them cannot pass by clearing the half this test happened to set.
	_expect(SpellLibrary.set_slot_roles(0, ["damage", "answer", "payoff", "ult"]),
		"a role pick lands, so there is something to reset")
	var pool: Array = SpellLibrary.equippable()
	var open_idx: Array[int] = _pool_indices(pool, false)
	_expect(not open_idx.is_empty(), "the pool offers a non-ult to overlay slot 0 with")
	if open_idx.is_empty():
		out.queue_free()
		_completes("reset_to_default_puts_the_whole_hand_back")
		return
	var overlay: String = String((pool[open_idx[0]] as SpellDef).id)
	_expect(SpellLibrary.set_equipped(0, 0, overlay), "a grimoire pick lands too")
	# ...and the class NEXT DOOR is dirtied as well, because the one thing a reset must
	# NOT do is reach past the class being edited. There is no undo on this screen and the
	# very next line persists to disk.
	_expect(SpellLibrary.set_slot_roles(1, ["damage", "answer", "payoff", "ult"]),
		"the Shadowblade is dirtied so the blast radius is measurable")
	out.call("refresh")
	await process_frame
	_expect(_ids(SpellLibrary.build_for_class(0)) != authored,
		"the hand really is off-default before the reset")

	# ── THE BUTTON ──────────────────────────────────────────────────────────────
	var reset: Button = out.get("_reset_btn") as Button
	_expect(reset != null, "the Outfitter carries a reset button")
	if reset == null:
		out.queue_free()
		_completes("reset_to_default_puts_the_whole_hand_back")
		return
	_expect(reset.custom_minimum_size.y >= MIN_TAP_H,
		"it is a real tap target (%.0f px)" % reset.custom_minimum_size.y)
	# HONEST ABOUT ITS SCOPE, on the button itself. "Reset" alone on a screen carrying a
	# class button, a role list, a grimoire and an armoury door is a button whose blast
	# radius a player has to discover by pressing it.
	_expect(reset.text.to_lower().contains("reset")
			and reset.text.to_lower().contains("hand"),
		"...and it says WHAT it resets (label was: %s)" % reset.text)
	reset.pressed.emit()
	await process_frame

	_expect(SpellLibrary.equipped_id(0, 0) == "",
		"the reset clears the grimoire overlay (slot 0 holds '%s')"
			% SpellLibrary.equipped_id(0, 0))
	_expect(not SpellLibrary.has_custom_slot_roles(0),
		"...and the role picks too — a half-reset leaves the summary line lying")
	_expect(_ids(SpellLibrary.build_for_class(0)) == authored,
		"...so the hand is exactly what the class was authored with (%s)"
			% [_ids(SpellLibrary.build_for_class(0))])
	# SCOPED TO ONE CLASS.
	_expect(SpellLibrary.has_custom_slot_roles(1),
		"the reset did NOT reach the class next door — one class was being edited")
	# AND THE SCREEN'S OWN WORKING COPY FOLLOWED. `_carried` is seeded in `refresh` and
	# never re-read by `_redraw`, so a reset that redrew without refreshing would leave the
	# old hand standing in this screen and commit it straight back on the next role tap.
	var carried: Array = out.get("_carried") as Array
	var default_roles: Array = SpellLibrary.default_slot_roles_for_class(0)
	for role: Variant in carried:
		_expect(default_roles.has(String(role)),
			"the screen's working hand followed the reset (stale role '%s')" % role)
	# IT SAVED. Same `_persist` path every other pick takes — a reset that did not reach
	# `GameState` would come back from the dead on the next launch.
	var gs: Node = root.get_node_or_null(^"GameState")
	if gs != null:
		var saved: Variant = gs.get(&"spell_equipped")
		_expect(not (saved is Dictionary and (saved as Dictionary).get(0, {}) is Dictionary
				and not ((saved as Dictionary).get(0, {}) as Dictionary).is_empty()),
			"the cleared grimoire reached GameState.spell_equipped, so it stays cleared "
			+ "across a quit (%s)" % [saved])

	out.queue_free()
	SpellLibrary.clear_slot_roles()
	SpellLibrary.clear_equipped()
	_completes("reset_to_default_puts_the_whole_hand_back")


## ══ THE ARMOURY DOOR IS GONE FROM THE CLASS-CHANGING FLOW ════════════════════
## Maker, twice, most recently 2026-09-05: *"no need for an armoury button within the
## chaning class selection"*.
##
## ⚠ THE TEST IS THE PAIR, NOT THE ABSENCE. "There is no Armory button" alone would also
## pass if the button vanished from EVERY Outfitter — which would delete the room rather
## than the duplicate door, and would strand the title screen with no way into the
## armoury at all. So both halves are asserted against the same screen built two ways.
func _test_the_class_flow_has_no_armoury_door() -> void:
	for picker: bool in [true, false]:
		var out: Control = (load(OUTFITTER_SCRIPT) as GDScript).new() as Control
		out.set("show_class_picker", picker)
		root.add_child(out)
		await process_frame
		var btns: Array = []
		_walk(out, btns)
		var doors: int = 0
		for b: Button in btns:
			if b.text.contains("Armory") or b.text.contains("Armoury"):
				doors += 1
		if picker:
			_expect(doors == 0,
				"the class-changing Outfitter has NO armoury door (found %d) - the town has its own rack pad" % doors)
		else:
			_expect(doors == 1,
				"the Lobby Outfitter keeps its armoury door (found %d) - it is the only way in from the title screen" % doors)
		# ...and the row that lost an occupant must not have grown the column. The budget
		# is 22 px and a new row costs 34, so this is the number that actually bites.
		var col: Control = out.get("_col") as Control
		if col != null:
			var mn: Vector2 = col.get_combined_minimum_size()
			print("[layout] outfitter column (show_class_picker=%s) min %.0fx%.0f (budget %.0fx%.0f)"
				% [str(picker), mn.x, mn.y, BASE_W, BASE_H])
			_expect(mn.y <= BASE_H,
				"the outfitter (show_class_picker=%s) fits 360 px (needs %.0f)" % [str(picker), mn.y])
		# The grimoire is the taller of the two modes (it grows a slot-cursor row), so it
		# is the one the budget is actually judged on.
		out.call("_toggle_grimoire")
		await process_frame
		if col != null:
			var mg: Vector2 = col.get_combined_minimum_size()
			print("[layout] outfitter GRIMOIRE (show_class_picker=%s) min %.0fx%.0f"
				% [str(picker), mg.x, mg.y])
			_expect(mg.y <= BASE_H,
				"the grimoire mode (show_class_picker=%s) fits 360 px (needs %.0f)" % [str(picker), mg.y])
		out.queue_free()
		await process_frame
	_completes("the_class_flow_has_no_armoury_door")


## ══ "STILL NOT CLEAR WHAT IS UNLOCKABLE AND WHAT ISNT" ═══════════════════════
## Every grimoire row must be in one of the three states and must SAY which. The state
## itself is `Progression`'s and is pinned by `slice_test_unlocks`; what is pinned HERE is
## that the screen actually draws it — a correct table nobody can read was the bug.
func _test_the_grimoire_says_what_is_earnable() -> void:
	# ⚠ THE DEVELOPER'S OWN SAVE IS A FIXTURE, AND IT LIED. `GameState` hydrates from
	# `user://climber.json` on `_ready`, so this ran against whatever floor the machine had
	# reached — on this one, deep enough that every row was HELD and the whole sweep below
	# tested NOTHING while reporting green. Pinned to floor 1 (a brand-new climber, the
	# state the screen has to be legible in) and restored, so the suite means the same
	# thing on a fresh checkout as on a played one.
	var gs: Node = root.get_node_or_null(^"GameState")
	var saved_floor: int = int(gs.get("_highest_floor")) if gs != null else 1
	if gs != null:
		gs.set("_highest_floor", 1)
	var out: Control = (load(OUTFITTER_SCRIPT) as GDScript).new() as Control
	root.add_child(out)
	await process_frame
	out.call("_toggle_grimoire")
	await process_frame
	var pool: Array = SpellLibrary.equippable()
	_expect(pool.size() >= 5, "there is a pool to gate (%d spells)" % pool.size())
	var earnable: int = 0
	var held: int = 0
	for s: SpellDef in pool:
		var st: int = int(out.call("_spell_state", s))
		if st == Progression.Owned.HELD:
			held += 1
		elif st == Progression.Owned.EARNABLE:
			earnable += 1
			# THE VERB, on the row itself. A dim row that does not say why is the exact
			# thing the maker could not read.
			var row: Button = out.call("_pool_row", s) as Button
			_expect(row.text.contains("🔒") or row.text.contains("slot"),
				"'%s' is locked and its ROW says so ('%s')" % [s.display_name, row.text])
			_expect(row.disabled, "'%s' refuses the tap rather than doing nothing" % s.display_name)
			# ⚠ TWO REASONS CAN APPLY AT ONCE AND THE SHELF WINS THE SENTENCE — which is
			# the design (the slot rule is the one a player clears in one tap of the
			# cursor), so an ult aimed at slot 1 correctly says "slot 4 only" and not
			# "reach floor 8". Asserting "floor" unconditionally would have been asserting
			# my own preference over the shipped precedence.
			var reason: String = String(out.call("_row_reason", s))
			if bool(out.call("_can_equip_here", s)):
				_expect(reason.contains("floor"), "'%s' names the floor that opens it (%s)" % [s.display_name, reason])
			else:
				_expect(reason.contains("slot"), "'%s' names the slot rule first (%s)" % [s.display_name, reason])
			row.free()
		# CLASS_LOCKED must never appear for a spell — the maker's standing ruling is
		# that no class is prevented from taking any spell. `slice_test_unlocks` proves
		# it from the table; this proves the SCREEN never produces it either.
		_expect(st != Progression.Owned.CLASS_LOCKED,
			"'%s' is not class-locked - the roster never walls the library" % s.display_name)
	print("[grimoire] %d held, %d earnable of %d" % [held, earnable, pool.size()])
	# An invariant true of an empty sweep is not an invariant: on a fresh save (floor 1)
	# the deep shelves MUST be showing as earnable, or nothing is being tested.
	_expect(earnable >= 1, "at least one row reads EARNABLE on a fresh climber (got %d)" % earnable)
	_expect(held >= 1, "...and at least one reads HELD (got %d)" % held)
	out.queue_free()
	await process_frame
	if gs != null:
		gs.set("_highest_floor", saved_floor)
	_completes("the_grimoire_says_what_is_earnable")


## `HudStyle` has no `class_name` (see its header), so it is reached the same way every
## consumer reaches it: `preload`, script object, `static` members only.
static func HudStyle_GOLD() -> Color:
	return (preload("res://scripts/ui/HudStyle.gd") as GDScript).get_script_constant_map()["GOLD"]


# ---------------------------------------------------------------------------
# Stubs. Deliberately minimal: a stub that declares more than the real thing is a
# fixture more generous than reality, which is how a suite passes against a class
# that could never work.
# ---------------------------------------------------------------------------

## A GameState as it is TODAY — no `spell_roles` field.
class _BareState:
	extends Node


## A GameState as it will be once the one-line wiring lands.
class _WiredState:
	extends Node
	var spell_roles: Dictionary = {}
