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

	# THE POOL EXISTS AND IS THE THING THE MAKER ASKED FOR: eleven spells, every one of
	# them a Tier 2 or a Tier 3, none of them in any class's authored hand.
	var pool: Array = SpellLibrary.equippable()
	_expect(pool.size() >= 11, "the grimoire offers the showcase pool (%d spells)" % pool.size())
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
	var before: Array = _ids(SpellLibrary.build_for_class(0))
	var want: SpellDef = pool[0] as SpellDef
	(rows[0] as Button).pressed.emit()
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
	_expect((rows2[0] as Button).get_theme_color(&"font_color") == HudStyle_GOLD(),
		"the equipped row is drawn in HudStyle.GOLD (got %s)"
			% [(rows2[0] as Button).get_theme_color(&"font_color")])
	if rows2.size() > 1:
		_expect((rows2[1] as Button).get_theme_color(&"font_color") != HudStyle_GOLD(),
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
		var want2: SpellDef = pool[1] as SpellDef
		(rows3[1] as Button).pressed.emit()
		await process_frame
		_expect(SpellLibrary.equipped_id(0, 1) == String(want2.id),
			"a second pick lands in the newly aimed slot")
		_expect(SpellLibrary.equipped_id(0, 0) == String(want.id),
			"...and the first one is still there — slots are independent")

	# ── AND YOU CAN TAKE IT BACK OUT ────────────────────────────────────────────
	# Tap-again-to-undo, the same gesture the role list uses. There is deliberately no
	# separate Clear button: on a phone that is a second target for a decision the
	# player's thumb is already on.
	SpellLibrary.clear_equipped(0, 1)
	out.call("_cycle_grim_slot")          # 1 -> 2
	out.call("_cycle_grim_slot")          # 2 -> 3
	out.call("_cycle_grim_slot")          # 3 -> 0, back on the equipped slot
	await process_frame
	var rows4: Array = []
	_walk(out.get("_list"), rows4)
	(rows4[0] as Button).pressed.emit()
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
