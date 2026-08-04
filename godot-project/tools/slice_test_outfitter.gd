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
]

const LOBBY_SCENE: String = "res://scenes/ui/Lobby.tscn"
const PAUSE_SCRIPT: String = "res://scripts/combat/PauseMenu.gd"

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
	SpellLibrary.clear_slot_roles()
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
	# damage/control/ult. Take the blink and the spire instead.
	var before: Array = _ids(SpellLibrary.build_for_class(0))
	var ok: bool = SpellLibrary.set_slot_roles(0, ["answer", "payoff", "ult"])
	_expect(ok, "a legal hand is accepted")
	_expect(SpellLibrary.has_custom_slot_roles(0), "and is reported as custom")
	var after: Array = _ids(SpellLibrary.build_for_class(0))
	_expect(after != before, "the built kit actually changed (%s -> %s)" % [before, after])
	_expect(after.size() == SpellTier.SLOT_COUNT,
		"the hand is still %d spells (got %d)" % [SpellTier.SLOT_COUNT, after.size()])
	var kit: Dictionary = SpellLibrary.kit_for_class(0)
	_expect(after[0] == String(kit["answer"]), "slot 1 is the role that was picked for it")
	_expect(after[1] == String(kit["payoff"]), "slot 2 is the role that was picked for it")
	_expect(after[2] == String(kit["ult"]), "slot 3 is still the ult")
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
		["damage", "ult"],                        # too few
		["damage", "control", "answer", "ult"],   # too many
		["damage", "damage", "ult"],              # the same spell twice
		["damage", "control", "payoff"],          # no ult in the ult slot
		["ult", "control", "ult"],                # an ult outside the ult slot
		["damage", "nonsense", "ult"],            # a role this class does not author
	]
	for roles: Array in bad:
		_expect(SpellLibrary.validate_slot_roles(0, roles) != "",
			"%s is reported as illegal" % [roles])
		_expect(not SpellLibrary.set_slot_roles(0, roles), "%s is refused" % [roles])
		_expect(SpellLibrary.slot_roles_for_class(0) == kept,
			"...and the standing hand survived the refusal")
	_expect(SpellLibrary.validate_slot_roles(0, ["damage", "control", "ult"]) == "",
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
## its "choice" is a screen with nothing on it. With 4 choosable roles and 2 open
## slots that is 6 hands per class — 54 across the roster, from zero new content.
func _test_every_class_offers_a_real_choice() -> void:
	var open_slots: int = SpellTier.SLOT_COUNT - 1
	var total: int = 0
	for cls: int in SpellLibrary.CLASS_KITS.size():
		var choosable: Array = SpellLibrary.choosable_roles_for_class(cls)
		_expect(choosable.size() > open_slots,
			"class %d offers more than %d non-ult roles (got %d) — otherwise there is nothing to pick"
				% [cls, open_slots, choosable.size()])
		# n-choose-2, which is what the picker actually exposes.
		var n: int = choosable.size()
		total += (n * (n - 1)) / 2
		# And every one of those hands must be buildable, not just countable.
		for i: int in n:
			for j: int in range(i + 1, n):
				var roles: Array = [choosable[i], choosable[j], SpellLibrary.ult_role_for_class(cls)]
				_expect(SpellLibrary.validate_slot_roles(cls, roles) == "",
					"class %d can legally carry %s" % [cls, roles])
	_expect(total >= 40, "the roster offers at least 40 distinct hands (got %d)" % total)
	SpellLibrary.clear_slot_roles()
	_completes("every_class_offers_a_real_choice")


## The two roles you DON'T carry are the Tier 2 / Tier 3 drop pool
## (`SpellDrops` reads `reserve_for_class`). Change the hand and the pool must follow,
## or a spell ends up both carried and droppable.
func _test_the_reserve_tracks_the_pick() -> void:
	SpellLibrary.clear_slot_roles()
	var before: Array = _ids(SpellLibrary.reserve_for_class(0))
	_expect(SpellLibrary.set_slot_roles(0, ["answer", "payoff", "ult"]), "pick lands")
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
	_expect(SpellLibrary.set_slot_roles(0, ["answer", "payoff", "ult"]), "pick lands")
	_expect(SpellLibrary.persist_to_state(wired), "saving into a wired GameState works")
	SpellLibrary.clear_slot_roles()
	_expect(SpellLibrary.hydrate_from_state(wired), "and it comes back")
	_expect(SpellLibrary.slot_roles_for_class(0) == ["answer", "payoff", "ult"],
		"exactly as it went in")
	SpellLibrary.clear_slot_roles()
	wired.spell_roles = {"0": ["answer", "payoff", "ult"]}   # what JSON gives back
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
	for wanted: String in ["ENTER THE TOWER", "Host Co-op", "Join"]:
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


## `cycle_colourway` has been bound to `C` for a long time. There is no `C` on a phone,
## so on the target platform the feature did not exist. It needs a row a thumb finds.
func _test_the_colourway_is_reachable_without_a_keyboard() -> void:
	var palette: Array = Outfitter.colourways()
	_expect(palette.size() >= 2, "there is a palette to choose from (%d entries)" % palette.size())
	_expect(Outfitter.colourway_name(0) != "", "entries are named for the picker")
	# Past the end of the name list is a number, not a crash or a dropped entry.
	_expect(Outfitter.colourway_name(99) != "", "an unnamed colourway still reads")
	var src: String = FileAccess.get_file_as_string(PAUSE_SCRIPT)
	_expect(src.contains("_build_appearance"), "the pause menu carries an appearance row")
	_expect(src.contains("_sync_colourway"), "...that applies the lobby-side pick to the live hero")
	# The pause menu is the ONE settings surface reachable on a touchscreen (it owns
	# the on-screen pause button), which is the whole reason the row lives there.
	_expect(src.contains("PAUSE_BTN_SIZE"), "and the pause menu is itself touch-reachable")
	_completes("the_colourway_is_reachable_without_a_keyboard")


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
