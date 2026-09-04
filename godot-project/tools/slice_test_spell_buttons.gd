# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_spell_buttons.gd
#
# THREE REAL SPELL BUTTONS — the binding, the slot mapping, the buffer, and the seam.
#
# THE STATE THIS REPLACES. The kit had been trimmed to three slots and `HandSlots` had
# been given real per-slot cooldowns, but INPUT never caught up: there was one `cast`
# trigger plus a `cycle_signature` key, so the hotbar had to label the selected slot
# with the cast key and the other two with the cycle key. The bar was telling the truth
# about a control scheme that had not been built. Reaching slot 3 cost three presses
# and passed through two spells you did not want on the way.
#
# WHAT IS PINNED HERE, and why each one is a thing that silently breaks:
#   1. `spell_1..4` exist, are bound, and are bound to DIFFERENT buttons. An action
#      missing from the map does not error at the call site — `Input.is_action_pressed`
#      on an unknown action just reports false forever, which on a device is
#      indistinguishable from "the button does nothing".
#   2. One action per kit slot, checked against `SpellTier.SLOT_COUNT`. A kit that grows
#      to four slots with three bound actions leaves slot 4 drawn on the bar and
#      unreachable by any button.
#   3. Pressing button N casts SLOT N — behaviourally, by watching that slot's own
#      cooldown start. A mapping test that only compares indices proves nothing.
#   4. THE BOT SEAM SURVIVES. `BotController` cannot press these: input state is
#      process-global, so a per-slot key pressed through the `Input` singleton would
#      drive the human's hero too. Bots keep selecting by index and pulling `ultimate`.
#      Breaking that is invisible in single player and turns every bot into a spammer
#      of whatever spell was selected.
#   5. THE BAR IS SIX THINGS. A maker ruling, not an emergent shape — see
#      `_test_hotbar_is_six_things`. A row quietly re-added to `ability_hud_state`
#      would look like a feature and read, to the maker, as the thing they already
#      told us to delete coming back.
#   6. The buffer covers the spell buttons — a press two frames early still fires.
#   6. The touch arc's three buttons do not overlap each other's HIT BOXES. They are
#      drawn as circles and tapped as rectangles, so "they look fine" is not the test.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# A dead property read ABORTS the enclosing function and returns the type's zero, which
# `failed += _test_x()` reads as "no failures". So failures accumulate on the MEMBER
# `_fails` and every test records a completion sentinel as its last line: a test that
# aborts part-way is then missing from `_completed` and fails the suite BY ABSENCE.

const TESTS: Array[String] = [
	"actions_exist_and_are_distinct",
	"one_action_per_kit_slot",
	"button_casts_its_own_slot",
	"empty_slot_button_does_nothing",
	"hotbar_labels_are_the_real_keys",
	"hotbar_is_six_things",
	"buffer_holds_a_spell_press",
	"held_button_repeats_when_ready",
	"bot_seam_is_intact",
	"ready_flash_fires_on_the_edge",
	"touch_arc_has_no_overlapping_hitboxes",
	"socket_glyphs_are_distinct_in_every_hand",
	"every_kind_maps_to_a_motif",
	"a_socket_fits_inside_its_own_slot",
	"every_label_fits_its_box",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"
## Physical keycodes 1 / 2 / 3 / 4 (the number row), duplicated as literals rather
## than loaded so this suite pulls in no dependency chain to ask a question about
## bindings. One per `SpellTier.SLOT_COUNT`, checked below rather than assumed.
const KEY_1: int = 49
const KEY_2: int = 50
const KEY_3: int = 51
const KEY_4: int = 52


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_actions_exist()
	_test_one_action_per_slot()
	_test_button_casts_its_own_slot()
	_test_empty_slot()
	_test_hotbar_labels()
	_test_hotbar_is_six_things()
	_test_buffer_holds()
	_test_held_repeats()
	_test_bot_seam()
	_test_ready_flash()
	_test_touch_arc()
	_test_socket_glyphs_are_distinct()
	_test_every_kind_maps_to_a_motif()
	_test_socket_fits_its_slot()
	_test_labels_fit()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Spell-button tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Spell-button tests: all PASS")
		quit(0)
	return true


## Accumulates onto the MEMBER `_fails`, never a return value.
func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


## Last line of every test: "I reached the end." See TESTS.
func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.set_physics_process(false)  # no gravity drift; nothing here needs a body
	hero.set_process(false)          # ...and no render-frame press latching either
	return hero


## The PHYSICAL keycodes an action is bound to. Physical, so the scheme holds on
## AZERTY/QWERTZ as well as QWERTY.
func _keys_of(action: StringName) -> Array[int]:
	var out: Array[int] = []
	if not InputMap.has_action(action):
		return out
	for e: InputEvent in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k != null:
			out.append(k.physical_keycode)
	return out


# ------------------------------------------------------------------------- 1
func _test_actions_exist() -> void:
	var want: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4]
	for i: int in 3:
		var action: StringName = StringName("spell_%d" % (i + 1))
		_expect(InputMap.has_action(action),
			("input map has '%s' — an unbound action reports 'not pressed' forever, "
			+ "which on a device is indistinguishable from a dead button") % action)
		_expect(_keys_of(action).has(want[i]),
			"'%s' is bound to the physical '%d' key" % [action, i + 1])
	# ...and to three DIFFERENT buttons. Two slots sharing a key means one of them can
	# never be thrown deliberately.
	var seen: Dictionary = {}
	for i: int in 3:
		for k: int in _keys_of(StringName("spell_%d" % (i + 1))):
			_expect(not seen.has(k),
				"physical key %d drives spell_%s and also spell_%d"
					% [k, str(seen.get(k, "?")), i + 1])
			seen[k] = i + 1
	_completes("actions_exist_and_are_distinct")


# ------------------------------------------------------------------------- 2
## One button per kit slot, forever. If the hand grows and this list does not, the new
## slot is drawn on the hotbar and reachable by nothing.
func _test_one_action_per_slot() -> void:
	var hero: CharacterBody2D = _make_hero()
	var actions: Array = hero.get("SPELL_ACTIONS")
	var keys: Array = hero.get("SPELL_KEYS")
	_expect(actions.size() == SpellTier.SLOT_COUNT,
		"%d spell buttons for %d kit slots" % [actions.size(), SpellTier.SLOT_COUNT])
	_expect(keys.size() == actions.size(),
		"the hotbar's key labels and the bindings are the same length")
	hero.configure_class(0)  # ARCANIST
	var kit: Array = hero.get("_signatures")
	_expect(kit.size() <= actions.size(),
		"a real class kit (%d) is not bigger than the button set (%d)"
			% [kit.size(), actions.size()])
	hero.queue_free()
	_completes("one_action_per_kit_slot")


# ------------------------------------------------------------------------- 3
## THE HEADLINE. Button N casts slot N — proved by that slot's OWN cooldown starting
## while the others stay ready, which is the same fact a player reads off the bar.
func _test_button_casts_its_own_slot() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	var kit: Array = hero.get("_signatures")
	_expect(kit.size() >= 2, "the kit has at least two slots to tell apart")
	if kit.size() < 2:
		hero.queue_free()
		return  # deliberately NOT completed: the missing sentinel fails the suite
	# Reach the LAST slot first. Under the old cycle key that was the press that cost
	# three presses and walked through two wrong spells on the way.
	var last: int = kit.size() - 1
	_expect(bool(hero.call("cast_signature_slot", last)),
		"the last slot is reachable in ONE call")
	_expect(not bool(hero.call("signature_ready", last)),
		"...and it is the LAST slot that went on cooldown")
	for i: int in last:
		_expect(bool(hero.call("signature_ready", i)),
			"slot %d is untouched by casting slot %d" % [i, last])
	# The selection follows the button, so the hotbar's lifted frame and the Rift
	# Dagger's deferred bill both land on the spell you actually threw.
	_expect(int(hero.get("_signature_index")) == last,
		"the selection followed the button that was pressed")
	# ...and the FIRST slot still fires afterwards, on its own clock.
	# Two casts in one frame: skip the global gap so this stays a question about
	# WHICH SLOT the button chose, not about the pacing lockout.
	hero.set("_cast_lockout", 0.0)
	# ⚠ AND THE COMMIT STATE, for exactly the reason above. `Hero._cast_signature`
	# now refuses a new cast while `_channeling`/`_summoning` is live (the maker's
	# "you cant cast a main spell whilst another spell is casting"). A real slot
	# reopens after 3.4 s and the longest windup is ~1.5 s, so in play the commit
	# has ALWAYS finished by then; it is still set here only because
	# `clear_cooldowns()` teleports the bank without advancing a clock.
	hero.set("_channeling", false)
	hero.set("_summoning", false)
	_expect(bool(hero.call("cast_signature_slot", 0)), "slot 0 fires next")
	_expect(not bool(hero.call("signature_ready", 0)), "slot 0 went on its own cooldown")
	hero.queue_free()
	_completes("button_casts_its_own_slot")


# ------------------------------------------------------------------------- 4
## A button that reaches nothing must report "nothing happened" rather than clamping
## onto a plausible wrong spell. Same rule as `bot_select_signature`.
func _test_empty_slot() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	var kit: Array = hero.get("_signatures")
	_expect(not bool(hero.call("cast_signature_slot", kit.size())),
		"casting one past the end of the kit refuses instead of clamping")
	_expect(not bool(hero.call("cast_signature_slot", -1)),
		"...and a negative slot refuses too")
	_expect(int(hero.get("_signature_index")) == 0,
		"a refused press left the selection alone")
	hero.queue_free()
	_completes("empty_slot_button_does_nothing")


# ------------------------------------------------------------------------- 5
## THE LABELS ARE THE BINDINGS. They used to read "G" on the selected slot and "V" on
## the other two — the bar honestly describing a scheme with one trigger and a cycle
## key. Every slot has its own key now, so every slot prints its own.
func _test_hotbar_labels() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	var keys: Array = hero.get("SPELL_KEYS")
	var bar: Array = hero.call("ability_hud_state")
	var found: Dictionary = {}
	for entry: Variant in bar:
		if entry is Dictionary:
			found[String((entry as Dictionary).get("key", ""))] = true
	for i: int in keys.size():
		var slot: Dictionary = hero.call("_signature_hud_slot", i)
		_expect(String(slot.get("key", "")) == String(keys[i]),
			"spell slot %d is labelled '%s' (got '%s')"
				% [i, String(keys[i]), String(slot.get("key", ""))])
		_expect(found.has(String(keys[i])),
			"...and that label reaches the hotbar the player actually sees")
	_expect(not found.has("V"),
		("no hotbar slot still advertises the CYCLE key — it is a selection nudge now, "
		+ "not the way you reach a spell"))
	hero.queue_free()
	_completes("hotbar_labels_are_the_real_keys")


# ------------------------------------------------------------------------ 5b
## THE BAR IS SIX THINGS, AND THAT IS A RULING RATHER THAN AN EMERGENT SHAPE.
##
## Mid-playtest the maker cut the hotbar down in one line: **"4 spells, deflect and
## basic attack — that's all there should be to all of them."** So `ability_hud_state`
## publishes the basic attack, the defensive verb and `SpellTier.SLOT_COUNT` sockets —
## and the four rows that used to pad it (the movement verb on Spc, the class AoE on Q,
## Blink on R, Nova on T) publish nothing at all.
##
## Pinned as an EQUALITY and by KEY LABEL, for the same reason the arc-overlap test is
## an equality: a row added back would not error, it would simply appear, and the next
## person to read the bar has no way to tell a feature from the thing the maker already
## asked to have deleted. Checked on EVERY class, because the removed rows were the
## class-dependent ones ("consecrate and the one next to it" was the Cleric's Q and the
## Nova beside it) and a per-class regression would hide behind class 0.
##
## ⚠ THIS DOES NOT PIN THE VERBS AS DEAD. `blast` / `blink` / `nova` / `dash` still
## fire on their keys — bots, the rebind menu and several harnesses drive them. What
## is pinned is the SCREEN, which is what the maker was looking at.
func _test_hotbar_is_six_things() -> void:
	var hero: CharacterBody2D = _make_hero()
	var want: int = SpellTier.SLOT_COUNT + 2   # the four sockets + deflect + dash
	# ⚠ THE LAYOUT WAS CORRECTED AFTER THE FIRST CUT, AND THIS LIST MOVED WITH IT.
	# Shown the six-square bar (LMB + RMB + four sockets), the maker said: "no no, it
	# should be RMB parry, Space to dash with its cooldown on the left, then 1 2 3 4 on
	# the right, and the 4 ultra should have that special border." So the BASIC ATTACK
	# lost its square and DASH got one back — the left cluster is the two buttons with
	# a cooldown worth watching, and LMB's 0.34 s square was always full.
	# ⚠ "T" LEFT THIS LIST. Maker, after the cut: "I really like Nova and its
	# equivalent, so make sure those spells are one of the 4 — and if not, then one of
	# the 5, including Nova." It is published again, in the left cluster, and only on
	# the classes whose `has_nova` is true — so the bar is 6 or 7 things, not a fixed
	# count, and the assertion below counts the SOCKETS and the cut keys instead.
	const GONE: Array[String] = ["LMB", "Q", "R"]
	var classes: int = int(hero.get("CLASS_NAMES").size())
	_expect(classes > 0, "there is at least one class to check")
	for c: int in classes:
		hero.configure_class(c)
		var bar: Array = hero.call("ability_hud_state")
		var has_nova: bool = bool(hero.get("_cfg").get("has_nova", false))
		_expect(bar.size() == want + (1 if has_nova else 0),
			"class %d's hotbar is deflect + dash (+ Nova) + %d sockets (got %d)"
				% [c, SpellTier.SLOT_COUNT, bar.size()])
		var keys: Dictionary = {}
		for entry: Variant in bar:
			if entry is Dictionary:
				keys[String((entry as Dictionary).get("key", ""))] = true
		_expect(keys.has("Spc"), "class %d still draws the DASH and its cooldown" % c)
		_expect(keys.has("RMB"), "class %d still draws the DEFLECT" % c)
		for k: String in GONE:
			_expect(not keys.has(k),
				("class %d's hotbar draws a '%s' row again — the movement verb, the class "
				+ "AoE, Blink and Nova were cut from the bar by ruling, not by accident")
					% [c, k])
	hero.queue_free()
	_completes("hotbar_is_six_things")


# ------------------------------------------------------------------------- 6
## THE RESPONSIVENESS ONE. A spell press made while its slot is still recovering must
## be HELD and fired the moment the slot opens — otherwise the answer to "does a cast
## pressed two frames before the cooldown ends still fire" is no, and the button reads
## as dropped input at exactly the moment the player is pressing hardest.
func _test_buffer_holds() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	var kit: Array = hero.get("_signatures")
	if kit.is_empty():
		hero.queue_free()
		return  # deliberately NOT completed
	var hand: HandSlots = hero.get("_hand") as HandSlots
	_expect(hand != null, "the hero owns a HandSlots bank")
	if hand == null:
		hero.queue_free()
		return  # deliberately NOT completed
	hero.call("cast_signature_slot", 0)
	_expect(not bool(hero.call("signature_ready", 0)), "slot 0 is recovering")
	# The press lands early: latch it exactly as `_update_input_buffer` would.
	hero.call("_latch_buffer", hero.call("spell_buffer_key", 0), 5.0, false)
	_expect(not bool(hero.call("_try_fire_buffered")),
		"a buffered spell does not fire while its slot is down")
	_expect(String(hero.get("_buffered_action")) != "",
		"...and the press is HELD rather than thrown away")
	# The slot opens. The very next attempt must spend the buffer.
	hand.clear_cooldowns()
	# The global cast gap is cleared with the slot bank, and that is faithful
	# rather than convenient: `GLOBAL_CAST_LOCKOUT` is 0.35 s and the shortest
	# cooldown is 3.4 s, so in real play the gap has ALWAYS expired by the time a
	# slot reopens. `clear_cooldowns()` teleports the bank to ready without
	# advancing any clock, which is the only reason it would still be armed here.
	hero.set("_cast_lockout", 0.0)
	# ⚠ AND THE COMMIT STATE, for exactly the reason above. `Hero._cast_signature`
	# now refuses a new cast while `_channeling`/`_summoning` is live (the maker's
	# "you cant cast a main spell whilst another spell is casting"). A real slot
	# reopens after 3.4 s and the longest windup is ~1.5 s, so in play the commit
	# has ALWAYS finished by then; it is still set here only because
	# `clear_cooldowns()` teleports the bank without advancing a clock.
	hero.set("_channeling", false)
	hero.set("_summoning", false)
	hero.call("_try_fire_buffered")
	_expect(not bool(hero.call("signature_ready", 0)),
		"the moment the slot opened, the held press fired it")
	_expect(String(hero.get("_buffered_action")) == "",
		"...and the buffer was consumed, so it cannot fire twice")
	# The encoding round-trips, so the buffer and the reader agree about what "slot 2"
	# looks like as a string.
	for i: int in 3:
		_expect(int(hero.call("spell_buffer_slot", hero.call("spell_buffer_key", i))) == i,
			"the buffer encoding round-trips for slot %d" % i)
	_expect(int(hero.call("spell_buffer_slot", "dash")) == -1,
		"a non-spell buffer entry is not mistaken for a slot")
	hero.queue_free()
	_completes("buffer_holds_a_spell_press")


# ------------------------------------------------------------------------- 7
## HOLD = REPEAT, with one exception. A held button re-latches once the buffer is spent
## so the spell re-fires the instant its slot recovers — "always something to do".
## The exception is the Rift Dagger's free RECALL beat, which lives ABOVE the cooldown
## gate: a HELD button must never take it, or throwing the dagger would yank it
## straight back on the next frame. Recall is a second decision, not a continuation.
func _test_held_repeats() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	var hand: HandSlots = hero.get("_hand") as HandSlots
	if hand == null:
		hero.queue_free()
		return  # deliberately NOT completed
	hero.call("cast_signature_slot", 0)
	# A HOLD-sourced latch on a slot that is still down: it waits, exactly as a fresh
	# press does...
	hero.call("_latch_buffer", hero.call("spell_buffer_key", 0), 5.0, true)
	_expect(not bool(hero.call("_try_fire_buffered")), "a held button waits its turn")
	_expect(bool(hero.get("_buffer_from_hold")), "...and is still flagged as a hold")
	# ...and fires on recovery, which is the repeat.
	hand.clear_cooldowns()
	# The global cast gap is cleared with the slot bank, and that is faithful
	# rather than convenient: `GLOBAL_CAST_LOCKOUT` is 0.35 s and the shortest
	# cooldown is 3.4 s, so in real play the gap has ALWAYS expired by the time a
	# slot reopens. `clear_cooldowns()` teleports the bank to ready without
	# advancing any clock, which is the only reason it would still be armed here.
	hero.set("_cast_lockout", 0.0)
	# ⚠ AND THE COMMIT STATE, for exactly the reason above. `Hero._cast_signature`
	# now refuses a new cast while `_channeling`/`_summoning` is live (the maker's
	# "you cant cast a main spell whilst another spell is casting"). A real slot
	# reopens after 3.4 s and the longest windup is ~1.5 s, so in play the commit
	# has ALWAYS finished by then; it is still set here only because
	# `clear_cooldowns()` teleports the bank without advancing a clock.
	hero.set("_channeling", false)
	hero.set("_summoning", false)
	hero.call("_try_fire_buffered")
	_expect(not bool(hero.call("signature_ready", 0)),
		"a held button re-fires the moment the slot comes back")
	_expect(not bool(hero.get("_buffer_from_hold")),
		"consuming the buffer clears the hold flag")
	hero.queue_free()
	_completes("held_button_repeats_when_ready")


# ------------------------------------------------------------------------- 8
## THE SEAM. `BotController` drives bodies through an object, never through the global
## `Input` singleton, because input state is process-global: a per-slot key pressed by
## a bot would drive the human's hero too. So the three new actions must be things a
## bot never holds, and `cast_slot` must still resolve to the ONE shared `ultimate`
## trigger it always did.
func _test_bot_seam() -> void:
	_expect(BotController.CAST_ACTION == &"ultimate",
		"a bot still casts through the shared `ultimate` trigger")
	var ctrl := BotController.new()
	var intent: Dictionary = BotIntent.empty()
	intent[BotIntent.CAST_SLOT] = 2
	ctrl.drive(intent)
	_expect(ctrl.pressed(BotController.CAST_ACTION),
		"a `cast_slot` intent still holds the trigger a bot can actually reach")
	for i: int in 3:
		var action: StringName = StringName("spell_%d" % (i + 1))
		_expect(not ctrl.pressed(action),
			("a bot never holds '%s' — a per-slot key pressed through the global Input "
			+ "singleton would drive the human's hero as well") % action)
		_expect(not ctrl.just_pressed(action), "...nor reports an edge on it")
	# ...and the SELECTION half of the seam is still an index setter, not a key press.
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	_expect(bool(hero.call("bot_select_signature", 1)),
		"bot_select_signature still picks a slot by index")
	_expect(int(hero.get("_signature_index")) == 1, "...and it took effect")
	hero.queue_free()
	_completes("bot_seam_is_intact")


# ------------------------------------------------------------------------- 9
## "YOU CAN ACT NOW", said once, at the moment it becomes true.
##
## The resting ready-glow answers "is this usable" for a player LOOKING at the bar. It
## cannot answer "it just came back" for a player looking at the fight, because a
## static border has no event in it. So the hero catches the not-ready -> ready EDGE
## and publishes a decaying `pulse` that every HUD draws as a flare.
##
## The edge is easy to lose in a refactor and impossible to notice: nothing errors, the
## flash simply stops happening. Pinned here on the three things that must hold —
## it fires on the edge, it fires ONCE, and it decays.
func _test_ready_flash() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	var hand: HandSlots = hero.get("_hand") as HandSlots
	if hand == null:
		hero.queue_free()
		return  # deliberately NOT completed
	# Seed the edge detector from the live (all-ready) state.
	hero.call("_tick_ready_pulse", 0.0)
	_expect(is_zero_approx(float(hero.call("spell_button_state", 0)["pulse"])),
		"a slot that was ready all along does not flash for nothing")
	# Slot 0 goes down: still no flash — the flash is for coming BACK.
	hero.call("cast_signature_slot", 0)
	hero.call("_tick_ready_pulse", 0.0)
	_expect(is_zero_approx(float(hero.call("spell_button_state", 0)["pulse"])),
		"going ON cooldown does not flash")
	# ...and back up.
	hand.clear_cooldowns()
	# The global cast gap is cleared with the slot bank, and that is faithful
	# rather than convenient: `GLOBAL_CAST_LOCKOUT` is 0.35 s and the shortest
	# cooldown is 3.4 s, so in real play the gap has ALWAYS expired by the time a
	# slot reopens. `clear_cooldowns()` teleports the bank to ready without
	# advancing any clock, which is the only reason it would still be armed here.
	hero.set("_cast_lockout", 0.0)
	# ⚠ AND THE COMMIT STATE, for exactly the reason above. `Hero._cast_signature`
	# now refuses a new cast while `_channeling`/`_summoning` is live (the maker's
	# "you cant cast a main spell whilst another spell is casting"). A real slot
	# reopens after 3.4 s and the longest windup is ~1.5 s, so in play the commit
	# has ALWAYS finished by then; it is still set here only because
	# `clear_cooldowns()` teleports the bank without advancing a clock.
	hero.set("_channeling", false)
	hero.set("_summoning", false)
	hero.call("_tick_ready_pulse", 0.0)
	_expect(float(hero.call("spell_button_state", 0)["pulse"]) > 0.9,
		"the slot flashes on the frame it becomes ready")
	# Once, not every frame it happens to be ready.
	hero.call("_tick_ready_pulse", 999.0)
	_expect(is_zero_approx(float(hero.call("spell_button_state", 0)["pulse"])),
		"the flash decays instead of latching on")
	hero.call("_tick_ready_pulse", 0.0)
	_expect(is_zero_approx(float(hero.call("spell_button_state", 0)["pulse"])),
		"...and does not re-fire while the slot simply stays ready")
	# The hotbar reads it from the same publisher rather than latching its own copy.
	_expect((hero.call("_signature_hud_slot", 0) as Dictionary).has("pulse"),
		"the hotbar slot dictionary carries the pulse the bar draws")
	hero.queue_free()
	_completes("ready_flash_fires_on_the_edge")


# ------------------------------------------------------------------------ 10
## THE ARC IS GEOMETRY, AND GEOMETRY IS TESTABLE WITHOUT A DEVICE. Reach and comfort
## are the maker's on-hardware pass; two buttons whose TAP RECTANGLES overlap is a bug
## you can prove from a desk. Buttons are drawn as circles, so eyeballing the render
## would not have caught it — a corner of one rect can sit inside its neighbour while
## the circles clearly clear each other.
func _test_touch_arc() -> void:
	var n: int = TouchControls.SPELL_ARC_ANGLES.size()
	_expect(n == SpellTier.SLOT_COUNT,
		"the arc has one button per kit slot (%d vs %d)" % [n, SpellTier.SLOT_COUNT])
	var size: float = TouchControls.SPELL_BTN_SIZE
	# 44 px is the smallest tap target that survives contact with a real hand, and the
	# base viewport is only 360 tall, so this is a floor rather than a preference.
	_expect(size >= 44.0, "a spell button is at least 44 px across (got %.0f)" % size)
	var rects: Array[Rect2] = []
	for i: int in n:
		var off: Vector2 = TouchControls.spell_button_offset(i)
		_expect(off.x >= 0.0 and off.y >= 0.0,
			"spell button %d is inside the screen (offset %s)" % [i, off])
		rects.append(Rect2(off, Vector2(size, size)))
	for i: int in n:
		for j: int in range(i + 1, n):
			_expect(not rects[i].intersects(rects[j]),
				("spell buttons %d and %d have OVERLAPPING tap rectangles (%s vs %s) — "
				+ "widen SPELL_ARC_RADIUS or spread SPELL_ARC_ANGLES")
					% [i, j, rects[i], rects[j]])
	# The dash button shares the corner with the arc and must not sit under any of them.
	var dash := Rect2(TouchControls.DASH_BTN_OFFSET,
		Vector2(TouchControls.DASH_BTN_SIZE, TouchControls.DASH_BTN_SIZE))
	for i: int in n:
		_expect(not dash.intersects(rects[i]),
			"DASH does not overlap spell button %d" % i)
	_completes("touch_arc_has_no_overlapping_hitboxes")


## ══ THE SOCKET GLYPH — this assertion IS the maker's complaint ═══════════════
## "visually the spell slots are kinda boring." Colour cannot carry it (a class
## whose spells share an element shows four of the same colour) and tier cannot
## (three weights across four slots), so the FIGURE is what tells them apart. If
## two slots in a hand wear the same figure, that hand is back where it started.
##
## ⚠ EVERY REACHABLE HAND, NOT THE DEFAULT ONE. The player leaves one non-ult role
## behind at class-select, so each class has C(4,3) = 4 hands. The first version of
## the glyph map passed on all nine DEFAULT hands and collided on six of the others.
##
## ⚠ `_spell_by_id()`, NOT `build()`. `build()` omits the HEX-forked class
## signatures, which produced an EMPTY hand for eight of nine classes — and an
## empty hand has nothing to compare, so it passes. Hence the two size assertions
## before any comparison: a harness that cannot fail is not a harness.
func _test_socket_glyphs_are_distinct() -> void:
	var by_id: Dictionary = SpellLibrary._spell_by_id()
	_expect(by_id.size() >= 40,
		"the spell pool is real (%d spells — an empty pool would pass vacuously)" % by_id.size())
	var hands_checked: int = 0
	for c: int in SpellLibrary.CLASS_KITS.size():
		var kit: Dictionary = SpellLibrary.kit_for_class(c)
		var non_ult: Array[String] = []
		for role: String in SpellLibrary.ROLE_ORDER:
			if role != "ult" and kit.has(role):
				non_ult.append(role)
		for drop: int in non_ult.size():
			var roles: Array[String] = []
			for i: int in non_ult.size():
				if i != drop:
					roles.append(non_ult[i])
			roles.append("ult")
			var seen: Dictionary = {}
			var built: int = 0
			for role: String in roles:
				var sig: SpellDef = by_id.get(String(kit.get(role, ""))) as SpellDef
				if sig == null:
					continue
				built += 1
				var g: int = AbilityBar.glyph_for(sig)
				_expect(g != MagicCircle.Motif.NONE,
					"class %d slot '%s' (%s) wears a figure — NONE draws NOTHING, which is the flat socket back"
						% [c, role, sig.id])
				_expect(not seen.has(g),
					"class %d without '%s': '%s' does not repeat '%s's figure (%d)"
						% [c, non_ult[drop], sig.id, String(seen.get(g, "")), g])
				seen[g] = sig.id
			_expect(built >= 3,
				"class %d without '%s' built a real hand (%d spells)" % [c, non_ult[drop], built])
			hands_checked += 1
	_expect(hands_checked >= 30,
		"every reachable hand was checked (%d — nine classes give 36)" % hands_checked)
	_completes("socket_glyphs_are_distinct_in_every_hand")


## The fallback must cover the WHOLE enum. Iterating the TABLE would only prove the
## table agrees with itself; iterating the ENUM is what catches a Kind added
## tomorrow, which would otherwise resolve to NONE and draw nothing at all.
func _test_every_kind_maps_to_a_motif() -> void:
	var kinds: Dictionary = SpellDef.Kind
	_expect(kinds.size() >= 22, "the Kind enum is real (%d kinds)" % kinds.size())
	for name: String in kinds:
		var k: int = int(kinds[name])
		_expect(AbilityBar.MOTIF_BY_KIND.has(k),
			"SpellDef.Kind.%s has a fallback figure (a missing row resolves to NONE, silently)" % name)
	_completes("every_kind_maps_to_a_motif")


# ------------------------------------------------------------------------- 14
## NOTHING A SOCKET DRAWS MAY LEAVE ITS OWN CELL -- CHECKED AT BOTH SCALES.
##
## THE GUARD THAT USED TO LIVE HERE COULD NOT HAVE CAUGHT THE BUG IT WAS WRITTEN
## NEXT TO, and that is the part worth keeping. It asserted
## `GLYPH_RADIUS * MOTIF_OUTER < SOCKET_RADIUS` -- both sides absolute, both sides
## socket constants, a statement about the socket in terms of itself. It passed
## happily while the socket was 32.00 px wide inside a 28.52 px slot, because it
## never once compared a socket length to a SLOT length. A guard that only relates a
## thing to itself is decoration.
##
## So this one relates the socket to the two lengths that actually constrain it:
##   * the SLOT it is drawn in   -- or the circle bursts out of its own square
##   * half the SLOT PITCH       -- or it reaches into the neighbouring square
## and it does so at BOTH scales, because the shipped fault existed at only one of
## them: at the 46 px thumb size everything fitted exactly as designed, so anybody
## checking a touch build saw a correct picture. `slot_scale()` answers with whichever
## one this machine is, so iterating the pair explicitly is the only way to cover the
## one the runner is not.
func _test_socket_fits_its_slot() -> void:
	for k: float in [1.0, AbilityBar.DESKTOP_SCALE]:
		var slot: float = AbilityBar.SLOT_SIZE * k
		var half_pitch: float = (slot + AbilityBar.SLOT_GAP * k) * 0.5
		var w: float = slot / AbilityBar.SLOT_SIZE
		var disc: float = slot * AbilityBar.SOCKET_DISC_FRAC
		var ring: float = slot * AbilityBar.SOCKET_RING_FRAC
		var heaviest: float = float(AbilityBar.TIER_RING_WIDTH[AbilityBar.TIER_RING_WIDTH.size() - 1]) * w
		# The disc IS the slot's inscribed circle: it may touch the edge, not pass it.
		_expect(disc <= slot * 0.5 + 0.001,
			"k=%.2f: the socket disc (r=%.2f) fits the %.2f px slot" % [k, disc, slot])
		# The ULT's crown is drawn at rest, outside the element ring, inside the disc.
		var crown: float = ring * AbilityBar.ULT_OUTER_R + 1.0 * w
		_expect(crown <= disc + 0.001,
			"k=%.2f: the ULT crown (r=%.2f) stays inside the disc (r=%.2f)" % [k, crown, disc])
		# The element ring AT FULL CAST PUNCH is the outermost transient mark there is.
		# This is the number that read 21.6 px against a 16.12 px half-pitch on the day
		# the maker said the slots looked random.
		var punched: float = ring * (1.0 + AbilityBar.SOCKET_PUNCH) + heaviest * 0.5
		_expect(punched <= half_pitch + 0.001,
			("k=%.2f: a socket at full cast punch (r=%.2f) does not reach its neighbour "
			+ "(half pitch %.2f)") % [k, punched, half_pitch])
		# ...and the figure inside still clears the ring it sits in, which is what the
		# old assertion was reaching for and is still worth having.
		var reach: float = ring * AbilityBar.GLYPH_R_OVER_RING * MagicCircle.MOTIF_OUTER
		_expect(reach < ring,
			"k=%.2f: the figure (r=%.2f) stays inside the tier ring (r=%.2f)" % [k, reach, ring])
	_completes("a_socket_fits_inside_its_own_slot")


# ------------------------------------------------------------------------- 15
## EVERY LABEL THE BAR CAN DRAW FITS ITS BOX, AT A SIZE STILL WORTH READING.
##
## `fit_text` fits by construction, so "does it fit" is not a question worth asking
## it -- the answer is yes by definition, which is the shape of a test that proves
## nothing. What CAN still go wrong is the two ways fitting DEGRADES: the size walking
## down to the illegibility floor, and a name long enough to need ellipsising. Both
## are silent, and both mean a label somebody added has outgrown the HUD it went into.
## So those are what is pinned.
##
## Driven off REAL heroes rather than a list of strings, because the strings are the
## thing that changes: `Hero._move_slot_name()` alone answers with eleven different
## words and a twelfth arrives with the next class.
func _test_labels_fit() -> void:
	var font: Font = ThemeDB.fallback_font
	var slot: float = AbilityBar.SLOT_SIZE * AbilityBar.DESKTOP_SCALE
	var checked: int = 0
	for cls: int in ClassInfo.CLASSES.size():
		var hero: CharacterBody2D = _make_hero()
		hero.configure_class(cls)
		var state: Array = hero.ability_hud_state()
		# The verb rows are everything before the kit; only they draw a name.
		var verbs: int = state.size() - SpellTier.SLOT_COUNT
		for i: int in range(maxi(verbs, 0)):
			if not state[i] is Dictionary:
				continue
			var d: Dictionary = state[i]
			var nm: String = String(d.get("name", ""))
			var ky: String = String(d.get("key", ""))
			for pair: Array in [[nm, AbilityBar.NAME_FONT_SIZE], [ky, AbilityBar.KEY_FONT_SIZE]]:
				var label: String = String(pair[0])
				if label.is_empty():
					continue
				var fit: Array = AbilityBar.fit_text(font, label, slot, int(pair[1]))
				checked += 1
				_expect(not String(fit[1]).ends_with("\u2026"),
					("label '%s' on %s cannot fit a %.1f px slot even at the floor, so it "
					+ "is being ellipsised") % [label, String(ClassInfo.CLASSES[cls]["name"]), slot])
				# mini(), not the floor alone: a preferred size already BELOW the floor
				# is returned untouched, and asserting against the floor there would
				# fail on a config that is perfectly correct. The invariant is "fitting
				# never took this below the floor", not "every label is at least 6pt".
				_expect(int(fit[0]) >= mini(int(pair[1]), AbilityBar.FIT_FLOOR_SIZE),
					"label '%s' fitted below the legibility floor (%d)" % [label, int(fit[0])])
			# The cooldown numeral is drawn at its own, much larger size. "10.5" is
			# 30 px of a 28.5 px slot, so every ability with a ten-second-or-longer
			# cooldown was losing its last digit -- on a timer, worse than useless.
			var secs: String = "%.1f" % float(d.get("total", 0.0))
			var tfit: Array = AbilityBar.fit_text(font, secs, slot, AbilityBar.TIMER_FONT_SIZE)
			checked += 1
			_expect(not String(tfit[1]).ends_with("\u2026"),
				"cooldown numeral '%s' cannot fit a %.1f px slot" % [secs, slot])
		hero.queue_free()
	_expect(checked >= 40, "every class's labels were measured (%d checks)" % checked)
	_completes("every_label_fits_its_box")
