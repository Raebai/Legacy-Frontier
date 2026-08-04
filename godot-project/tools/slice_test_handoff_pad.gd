# Run: godot --headless --path godot-project --script tools/slice_test_handoff_pad.gd
#
# TWO GAPS THAT MADE BUILT MECHANICS INVISIBLE ON A PHONE.
#
# 1. SPELL HANDOFF HAD NO TOUCH AFFORDANCE. `SpellHandoff` polls the `talk` action,
#    which is a keyboard binding with no pad behind it, so on a phone the whole
#    give-your-teammate-the-Void mechanic was unreachable. It is now a CONTEXTUAL
#    pad in the centre dead band, present exactly while there is an offer.
#
# 2. TIER 3 CHARGES HAD NO HUD ANYWHERE. A drop has 1–2 uses and then evaporates
#    back into your class ult. Without a count the spec's "picking one up is a
#    decision" is a surprise instead: you spend your last charge on a trash mob and
#    find out afterwards.
#
# WHAT THIS SUITE CAN AND CANNOT JUDGE. It pins WIRING — that the pad exists, hides,
# labels itself from the same state the in-world prompt uses, presses the SAME action
# the keyboard does, releases that action when the offer ends, and that the charge
# counts reaching the three HUDs are the ledger's real numbers. It cannot judge reach,
# size or whether a thumb can find it: every touch constant in `TouchControls` is a
# self-declared untested guess and stays one until a device runs it.
# `tools/handoff_pad_capture.gd` renders the pad so it can at least be LOOKED at.
#
# ⚠ THE IDIOM. Failures accumulate on the MEMBER `_fails` and every test records a
# COMPLETION SENTINEL as its last line, so a test that aborts part-way fails the suite
# BY ABSENCE. Never `_fails += _test_x()`: a dead property read aborts the enclosing
# function and hands back the type's zero, which that idiom reads as "no failures".
# `tools/slice_test_loadout.gd` is the reference.
extends SceneTree

const TESTS: Array[String] = [
	"affordance_did_not_grow_the_thumb_buttons",
	"pad_is_built_and_hidden",
	"pad_and_handoff_agree_on_group_and_action",
	"pad_appears_only_when_an_offer_exists",
	"pad_press_drives_the_keyboard_action",
	"pad_releases_the_action_when_the_offer_ends",
	"pad_reaches_the_real_transfer",
	"charges_in_slot_reports_only_drops",
	"touch_pads_show_the_charge_count",
	"loadout_bar_finds_its_own_hero",
	"local_player_marker_exists_on_a_real_hero",
]

## The property `SpellHandoff._is_local_player` duck-types to tell a human hero from
## a bot one. Named here because it is reached BY STRING and a rename is otherwise
## silent — see that function's header for the day this cost the whole mechanic.
const HERO_LOCAL_PLAYER_MEMBER: String = "controller"
const HERO_SCENE: String = "res://scenes/combat/Hero.tscn"

var _ran: bool = false
var _fails: int = 0
var _completed: Dictionary = {}

const _StubHero2D: GDScript = preload("res://tools/_stub_hero2d.gd")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_affordance_did_not_grow_the_thumb_buttons()
	_test_pad_is_built_and_hidden()
	_test_pad_and_handoff_agree_on_group_and_action()
	_test_pad_appears_only_when_an_offer_exists()
	# ⚠ ORDER IS LOAD-BEARING, and the reason is a real Godot behaviour rather than a
	# tidiness preference. Every test here runs inside ONE engine frame, and
	# `Input.is_action_just_pressed` stays true for the WHOLE frame in which the action
	# was pressed — even after it is released. So a test that presses `talk` makes the
	# next `SpellHandoff._process` in that same frame fire a handoff nobody asked for.
	# The real-transfer test therefore goes BEFORE the two press tests, which are the
	# only ones that touch the action and which do not tick the mechanic themselves.
	_test_pad_reaches_the_real_transfer()
	_test_pad_press_drives_the_keyboard_action()
	_test_pad_releases_the_action_when_the_offer_ends()
	_test_charges_in_slot_reports_only_drops()
	_test_touch_pads_show_the_charge_count()
	_test_loadout_bar_finds_its_own_hero()
	_test_local_player_marker_exists_on_a_real_hero()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Handoff pad tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Handoff pad tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


# ------------------------------------------------------------------ helpers
func _pad() -> TouchControls:
	var p := TouchControls.new()
	p.force_visible = true
	root.add_child(p)
	return p


## A hero-shaped Node2D in the "hero" group at `at`, carrying class `cls`'s real kit.
func _hero(cls: int, at: Vector2) -> Node2D:
	var n := Node2D.new()
	n.set_script(_StubHero2D)
	var sigs: Array = SpellLibrary.build_for_class(cls)
	var hand := HandSlots.new()
	hand.rebuild([], sigs)
	n.set("_signatures", sigs)
	n.set("_hand", hand)
	n.add_to_group("hero")
	n.global_position = at
	root.add_child(n)
	return n


## The first Tier 3 drop in the library — a real spell with a real charge count,
## rather than a hand-made SpellDef that could disagree with the shipped one.
func _tier3() -> SpellDef:
	var all: Array = SpellLibrary.build_tier3()
	return null if all.is_empty() else all[0] as SpellDef


## A minimal stand-in for `SpellHandoff` when the test is about the PAD, not the
## mechanic: the two methods the pad calls, and nothing else.
class OfferStub extends Node:
	var offering: bool = false
	var label: String = ""

	func can_hand_over() -> bool:
		return offering

	func offer_label() -> String:
		return label


func _offer(offering: bool, label: String) -> Node:
	var s := OfferStub.new()
	s.offering = offering
	s.label = label
	s.add_to_group(TouchControls.HANDOFF_GROUP)
	root.add_child(s)
	return s


## ⚠ IMMEDIATE, NOT `queue_free`. These tests all run inside ONE `_process` call, and
## a queued free does not happen until the frame ends — so a stub "cleaned up" at the
## end of one test is still in its group for the next one, and
## `get_first_node_in_group` hands the following test the PREVIOUS test's fixture.
## That is not a hypothetical: it initially cross-contaminated four tests here,
## including leaving `talk` held so the real handoff fired before it was pressed.
func _kill(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	for g: StringName in n.get_groups():
		n.remove_from_group(g)
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.free()


func _clear_talk() -> void:
	if Input.is_action_pressed(TouchControls.HANDOFF_ACTION):
		Input.action_release(TouchControls.HANDOFF_ACTION)


# ------------------------------------------------------------------- tests
## The consolidation rule holds: the phone has SEVEN persistent thumb buttons —
## `SpellTier.SLOT_COUNT` spells plus dash, jump and parry. A contextual prompt is not
## the button set growing back, and the count is DERIVED so the pad and the hand can
## never disagree; a literal here went stale the moment the fourth spell slot landed.
func _test_affordance_did_not_grow_the_thumb_buttons() -> void:
	var pad := _pad()
	var buttons: int = 0
	for c: Node in pad.get_children():
		if c is Button:
			buttons += 1
	var want: int = SpellTier.SLOT_COUNT + 3   # + dash, jump, parry
	_expect(buttons == want,
		"still %d persistent thumb buttons — the hand plus dash/jump/parry (got %d)"
			% [want, buttons])
	_kill(pad)
	_completes("affordance_did_not_grow_the_thumb_buttons")


## Built up front (no allocation hitch the moment a teammate walks into range) and
## invisible until there is something to give.
func _test_pad_is_built_and_hidden() -> void:
	var pad := _pad()
	var found: bool = false
	for c: Node in pad.get_children():
		if c is TouchControls.HandoffPad:
			found = true
	_expect(found, "the pad builds a HandoffPad child")
	pad.refresh()
	_expect(not pad.handoff_visible(), "…hidden with no handoff in the scene")
	_kill(pad)
	_completes("pad_is_built_and_hidden")


## The pad finds the handoff by a LITERAL group name (naming the class would drag the
## drop economy into this file's compile graph, and `slice_test_touch` runs under
## `--script` where that chain has no autoloads). This is the assertion that keeps the
## duplicated literal honest — and the same for the action, so the pad can never end
## up pressing a button the mechanic is not listening to.
func _test_pad_and_handoff_agree_on_group_and_action() -> void:
	_expect(TouchControls.HANDOFF_GROUP == SpellHandoff.HANDOFF_GROUP,
		"pad group '%s' == SpellHandoff.HANDOFF_GROUP '%s'" % [
			TouchControls.HANDOFF_GROUP, SpellHandoff.HANDOFF_GROUP])
	_expect(TouchControls.HANDOFF_ACTION == String(SpellHandoff.HANDOFF_ACTION),
		"pad action '%s' == SpellHandoff.HANDOFF_ACTION '%s'" % [
			TouchControls.HANDOFF_ACTION, SpellHandoff.HANDOFF_ACTION])
	_expect(InputMap.has_action(TouchControls.HANDOFF_ACTION),
		"'%s' is a real action" % TouchControls.HANDOFF_ACTION)
	_completes("pad_and_handoff_agree_on_group_and_action")


## Contextual means contextual: no offer, no pad. And the label is the SPELL'S name,
## because what you are about to lose is the whole decision.
func _test_pad_appears_only_when_an_offer_exists() -> void:
	var pad := _pad()
	var offer: Node = _offer(false, "Meteor Storm")
	pad.refresh()
	_expect(not pad.handoff_visible(), "no offer -> no pad")
	offer.set("offering", true)
	pad.refresh()
	_expect(pad.handoff_visible(), "an offer -> the pad appears")
	_expect(pad.handoff_label() == "Meteor Storm",
		"…labelled with the spell (got '%s')" % pad.handoff_label())
	_kill(offer)
	_kill(pad)
	_completes("pad_appears_only_when_an_offer_exists")


## The pad presses the SAME action the keyboard handoff polls — one input path, so a
## change to when a handoff is legal cannot land on desktop and miss the phone.
func _test_pad_press_drives_the_keyboard_action() -> void:
	var pad := _pad()
	var offer: Node = _offer(true, "The Void")
	pad.refresh()
	var hp: TouchControls.HandoffPad = null
	for c: Node in pad.get_children():
		if c is TouchControls.HandoffPad:
			hp = c as TouchControls.HandoffPad
	_expect(hp != null, "found the pad to press")
	if hp != null:
		hp.press()
		_expect(Input.is_action_pressed(TouchControls.HANDOFF_ACTION),
			"pressing the pad holds '%s'" % TouchControls.HANDOFF_ACTION)
		hp.release()
		_expect(not Input.is_action_pressed(TouchControls.HANDOFF_ACTION),
			"lifting releases it")
	_kill(offer)
	_kill(pad)
	_clear_talk()
	_completes("pad_press_drives_the_keyboard_action")


## THE STUCK-BUTTON CASE. Your teammate walks away mid-press: the pad vanishes, and
## if it vanished while still holding `talk` that action would be held forever — every
## later handoff would fire on the frame it became legal, without anyone pressing
## anything.
func _test_pad_releases_the_action_when_the_offer_ends() -> void:
	var pad := _pad()
	var offer: Node = _offer(true, "The Void")
	pad.refresh()
	for c: Node in pad.get_children():
		if c is TouchControls.HandoffPad:
			(c as TouchControls.HandoffPad).press()
	_expect(Input.is_action_pressed(TouchControls.HANDOFF_ACTION), "held mid-press")
	offer.set("offering", false)
	pad.refresh()
	_expect(not pad.handoff_visible(), "the offer ended -> the pad goes away")
	_expect(not Input.is_action_pressed(TouchControls.HANDOFF_ACTION),
		"…and it does NOT leave the action held")
	_kill(offer)
	_kill(pad)
	_clear_talk()
	_completes("pad_releases_the_action_when_the_offer_ends")


## END TO END, against the real `SpellHandoff`: two heroes in range, the giver holding
## a Tier 3, the pad visible because the mechanic says there is an offer — press it and
## the spell is actually on the other hero. This is the assertion that the phone can
## reach the mechanic at all, which is the gap this task exists to close.
func _test_pad_reaches_the_real_transfer() -> void:
	var giver: Node2D = _hero(0, Vector2.ZERO)
	var taker: Node2D = _hero(1, Vector2(40.0, 0.0))   # inside SpellHandoff.RANGE
	var drop: SpellDef = _tier3()
	_expect(drop != null, "the library has a Tier 3 to hand over")
	if drop == null:
		return
	_expect(SpellGrant.apply(giver, drop) >= 0, "giver picked the drop up")
	var handoff := SpellHandoff.new()
	root.add_child(handoff)
	var pad := _pad()
	# One tick of the mechanic resolves who is next to whom; then the pad reads it.
	handoff._process(0.016)
	pad.refresh()
	_expect(handoff.can_hand_over(), "the mechanic reports a live offer")
	_expect(pad.handoff_visible(), "…so the touch affordance is on screen")
	_expect(pad.handoff_label() == drop.display_name,
		"…naming the spell (got '%s')" % pad.handoff_label())
	# Press the pad, then tick the mechanic — exactly the order a thumb produces.
	for c: Node in pad.get_children():
		if c is TouchControls.HandoffPad:
			(c as TouchControls.HandoffPad).press()
	handoff._process(0.016)
	_expect(SpellGrant.held(giver).is_empty(), "the giver no longer holds it")
	var got: Dictionary = SpellGrant.held(taker)
	_expect(not got.is_empty() and String((got.get("spell") as SpellDef).id) == drop.id,
		"the taker holds '%s'" % drop.id)
	_kill(handoff)
	_kill(pad)
	_kill(giver)
	_kill(taker)
	_clear_talk()
	_completes("pad_reaches_the_real_transfer")


## The count only means something if it is absent everywhere else. A class spell must
## report -1 ("draw nothing"), a drop its remaining charges, and an expired drop -1
## again — because `consume_charge` revokes at zero, so a literal 0 never persists and
## a HUD that drew one would be showing a state the game cannot be in.
func _test_charges_in_slot_reports_only_drops() -> void:
	var hero: Node2D = _hero(0, Vector2.ZERO)
	var drop: SpellDef = _tier3()
	if drop == null:
		_expect(false, "no Tier 3 in the library")
		return
	for i: int in SpellTier.SLOT_COUNT:
		_expect(SpellGrant.charges_in_slot(hero, i) == -1,
			"kit slot %d shows no pips before any pickup" % i)
	var nth: int = SpellGrant.apply(hero, drop)
	_expect(nth == SpellGrant.TIER3_SLOT, "a Tier 3 takes the ult slot (got %d)" % nth)
	_expect(SpellGrant.charges_in_slot(hero, nth) == drop.charges,
		"the drop shows its full count (%d)" % drop.charges)
	for i: int in drop.charges:
		SpellGrant.consume_charge(hero, drop)
	_expect(SpellGrant.charges_in_slot(hero, nth) == -1,
		"a spent drop shows nothing — the class ult is back")
	_kill(hero)
	_completes("charges_in_slot_reports_only_drops")


## ON A PHONE THIS PAD IS THE ONLY READOUT THERE IS — the desktop hotbar stands down
## when the pad is live — so a count that never reaches the veil is a count nobody in
## the target platform can see.
func _test_touch_pads_show_the_charge_count() -> void:
	var hero: Node2D = _hero(0, Vector2.ZERO)
	var drop: SpellDef = _tier3()
	if drop == null:
		_expect(false, "no Tier 3 in the library")
		return
	var pad := _pad()
	pad.refresh()
	for i: int in SpellTier.SLOT_COUNT:
		_expect(pad.spell_pad_charges(i) == -1, "pad %d draws no pips on a kit spell" % i)
	var nth: int = SpellGrant.apply(hero, drop)
	pad.refresh()
	_expect(pad.spell_pad_charges(nth) == drop.charges,
		"pad %d draws %d pips (got %d)" % [nth, drop.charges, pad.spell_pad_charges(nth)])
	SpellGrant.consume_charge(hero, drop)
	pad.refresh()
	var want: int = drop.charges - 1
	_expect(pad.spell_pad_charges(nth) == (want if want > 0 else -1),
		"spending one drops the count (got %d)" % pad.spell_pad_charges(nth))
	_kill(pad)
	_kill(hero)
	_completes("touch_pads_show_the_charge_count")


## The bar must resolve its hero by MATCHING THE HAND it was handed, never by taking
## the first hero in the group — in co-op there are two, and the wrong one's charge
## count is a confident lie rather than a missing readout.
func _test_loadout_bar_finds_its_own_hero() -> void:
	var mine: Node2D = _hero(0, Vector2.ZERO)
	var theirs: Node2D = _hero(1, Vector2(400.0, 0.0))
	var bar := LoadoutBar.new()
	bar.slots = theirs.get(&"_hand")
	root.add_child(bar)
	_expect(bar._owner_hero() == theirs,
		"the bar resolved the hero whose hand it renders, not the first in the group")
	var drop: SpellDef = _tier3()
	if drop != null:
		var nth: int = SpellGrant.apply(theirs, drop)
		_expect(SpellGrant.charges_in_slot(bar._owner_hero(), nth) == drop.charges,
			"…so its pip count is that hero's")
		_expect(SpellGrant.charges_in_slot(mine, nth) == -1,
			"…and the other hero's bar would show nothing")
	_kill(bar)
	_kill(mine)
	_kill(theirs)
	_completes("loadout_bar_finds_its_own_hero")


## THE ASSERTION THAT WOULD HAVE CAUGHT THE BUG THAT KILLED THIS MECHANIC.
##
## `SpellHandoff._is_local_player` asks a hero, BY STRING, whether it has an input
## source. It used to ask for `bot_driven` and `_bot` — names that exist nowhere in
## this codebase. `get()` on an absent property returns a null Variant, `bool(null)`
## is an illegal conversion, and an illegal conversion ABORTS the enclosing function
## and hands back `false`. So every hero answered "not the local player", no giver
## was ever resolved, and the handoff has never worked in a real game — silently,
## with nothing in the log.
##
## Every other test in this suite passed throughout, because the STUB declared the
## members the real Hero does not. A fixture more generous than reality is exactly
## how a duck-typed seam gets to lie, so the check has to be against the real scene.
func _test_local_player_marker_exists_on_a_real_hero() -> void:
	var scene: PackedScene = load(HERO_SCENE) as PackedScene
	if scene == null:
		_expect(false, "Hero.tscn did not load — cannot verify the handoff's seam")
		_completes("local_player_marker_exists_on_a_real_hero")
		return
	var hero: Node = scene.instantiate()
	var props: Dictionary = {}
	for p: Dictionary in hero.get_property_list():
		props[String(p.get("name", ""))] = true
	_expect(props.has(HERO_LOCAL_PLAYER_MEMBER),
		"Hero still declares '%s' (SpellHandoff reaches it by name to tell a human from a bot)"
			% HERO_LOCAL_PLAYER_MEMBER)
	# And the stub must not be more generous than the real thing — that gap IS the bug.
	var stub := Node2D.new()
	stub.set_script(_StubHero2D)
	var stub_props: Dictionary = {}
	for p: Dictionary in stub.get_property_list():
		stub_props[String(p.get("name", ""))] = true
	_expect(stub_props.has(HERO_LOCAL_PLAYER_MEMBER),
		"the stub declares '%s' under the REAL name" % HERO_LOCAL_PLAYER_MEMBER)
	_expect(not stub_props.has("bot_driven") and not stub_props.has("_bot"),
		"…and no longer carries the two invented names that hid this bug")
	_expect(stub.get(HERO_LOCAL_PLAYER_MEMBER) == null,
		"the stub declares '%s' too, and defaults it to the human path"
			% HERO_LOCAL_PLAYER_MEMBER)
	stub.free()
	hero.free()
	_completes("local_player_marker_exists_on_a_real_hero")
