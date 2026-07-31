# Run: Godot_v4.6.2-stable_win64_console.exe --headless --path godot-project --script tools/slice_test_slot_cooldowns.gd
#
# PER-SLOT COOLDOWNS + THE DEATH OF THE MANA GATE. Phase 2.2 and 2.4, tested together
# because they are the same press: what stops a spell button, and what does not.
#
# THE BUG THIS PINS. `Hero` ran ONE shared cooldown float for the whole kit
# (`_signature_cd_timer`). Throwing a 1.2 s jab locked the ult for 1.2 s; throwing the
# ult locked every other spell in the kit for nine seconds. With three spell buttons
# under the right thumb that is not a balance quirk — it is two of the three buttons
# being dark most of the fight for a reason the player cannot see, because the bar was
# rendering three cooldowns that were secretly one number. `HandSlots` had implemented
# real per-slot cooldowns all along and the shipped hero simply never called it.
#
# The assertions are deliberately BEHAVIOURAL — "cast A, then B still fires" — rather
# than reads of a timer field. A field read only proves a number moved house; firing
# the second spell proves the button works.
extends SceneTree

# ── Vacuous-pass armour (see tools/slice_test_loadout.gd for the full write-up) ──
# Failures accumulate on the MEMBER `_fails` and every test records a completion
# sentinel as its last line, so a test that aborts part-way fails BY ABSENCE.

const TESTS: Array[String] = [
	"slots_are_independent",
	"a_slot_recovers_on_its_own_clock",
	"class_swap_clears_every_slot",
	"no_mana_gate",
	"mp_cost_still_drives_tier",
	"hud_and_bots_read_the_same_bank",
	"loadout_bar_can_draw_the_sweep",
]

var _fails: int = 0
var _completed: Dictionary = {}
var _ran: bool = false

const HERO_PATH: String = "res://scenes/combat/Hero.tscn"


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_slots_are_independent()
	_test_slot_recovers()
	_test_class_swap_clears()
	_test_no_mana_gate()
	_test_mp_cost_still_drives_tier()
	_test_hud_and_bots()
	_test_loadout_bar_sweep()
	for t: String in TESTS:
		_expect(_completed.has(t),
			"test `%s` ran to completion (it aborted — a member it reads has moved)" % t)
	if _fails > 0:
		printerr("Slot-cooldown tests: %d FAILED" % _fails)
		quit(1)
	else:
		print("Slot-cooldown tests: all PASS")
		quit(0)
	return true


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_fails += 1


func _completes(test_name: String) -> void:
	_completed[test_name] = true


func _make_hero() -> CharacterBody2D:
	var hero: CharacterBody2D = (load(HERO_PATH) as PackedScene).instantiate()
	root.add_child(hero)
	hero.set_physics_process(false)  # no gravity drift; nothing here needs a body
	return hero


## Select signature slot `i` and press the ultimate key's code path.
func _cast_slot(hero: CharacterBody2D, i: int) -> void:
	hero.call("bot_select_signature", i)
	hero.call("_cast_signature")


# ------------------------------------------------------- 1. THE HEADLINE BUG
## Cast slot 0, then cast slot 1 IN THE SAME FRAME. Under the shared bank the second
## press was swallowed; under a per-slot bank it fires.
func _test_slots_are_independent() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)  # ARCANIST
	var kit: Array = hero.get("_signatures")
	_expect(kit.size() >= 2, "the kit has at least two slots to be independent about")
	if kit.size() < 2:
		hero.queue_free()
		return  # deliberately NOT completed: the missing sentinel fails the suite

	for i: int in kit.size():
		_expect(hero.call("signature_ready", i), "slot %d starts ready" % i)
	_cast_slot(hero, 0)
	_expect(not hero.call("signature_ready", 0), "casting slot 0 puts SLOT 0 on cooldown")
	for i: int in range(1, kit.size()):
		_expect(hero.call("signature_ready", i),
			("...and leaves slot %d READY. This is the whole fix: one shared bank meant "
			+ "a jab locked the ult and the ult locked the jab.") % i)

	# ...and the other slot genuinely FIRES, not merely reports ready.
	_cast_slot(hero, 1)
	_expect(not hero.call("signature_ready", 1),
		"the second slot actually cast (it went on its own cooldown)")
	_expect(hero.call("signature_cooldown", 0) > 0.0,
		"...without wiping the first slot's timer")
	hero.queue_free()
	_completes("slots_are_independent")


## Each slot carries its OWN duration, so a 9 s ult and a 1.2 s jab do not share a
## clock. Ticked through the real `HandSlots.tick`, which is what `Hero._process`
## drives every frame.
func _test_slot_recovers() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	var kit: Array = hero.get("_signatures")
	if kit.size() < 2:
		hero.queue_free()
		return
	_cast_slot(hero, 0)
	var cd0: float = float(hero.call("signature_cooldown", 0))
	_expect(is_equal_approx(cd0, float((kit[0] as SpellDef).cooldown)),
		"slot 0's cooldown is that SPELL's cooldown, not a shared constant (%.2f)" % cd0)
	var hand: HandSlots = hero.get("_hand") as HandSlots
	_expect(hand != null, "the hero owns a HandSlots bank")
	if hand == null:
		hero.queue_free()
		return
	hand.tick(cd0 * 0.5)
	_expect(not hero.call("signature_ready", 0), "halfway through, the slot is still down")
	hand.tick(cd0 * 0.6)
	_expect(hero.call("signature_ready", 0), "past its own duration, the slot is back")
	_expect(is_equal_approx(float(hero.call("signature_cooldown", 0)), 0.0),
		"...and its remaining time floors at zero rather than going negative")
	hero.queue_free()
	_completes("a_slot_recovers_on_its_own_clock")


## THE BUG A PER-SLOT BANK INVITES AND A SHARED FLOAT COULD NOT HAVE: a timer left
## running from the PREVIOUS class, locking a slot of a kit the player has never cast
## with. Tab swaps classes live, so this is reachable in one keypress.
func _test_class_swap_clears() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	_cast_slot(hero, 0)
	_expect(not hero.call("signature_ready", 0), "slot 0 is down before the swap")
	hero.configure_class(3)  # JUGGERNAUT — a different kit entirely
	var kit: Array = hero.get("_signatures")
	for i: int in kit.size():
		_expect(hero.call("signature_ready", i),
			"slot %d of the NEW class starts ready (no timer survived the swap)" % i)
	hero.queue_free()
	_completes("class_swap_clears_every_slot")


# --------------------------------------------------------- 4+5. the mana gate
## Spec: "Cooldowns, not mana." Drain the pool to zero and every slot still fires.
func _test_no_mana_gate() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	hero.set("mp", 0.0)
	var kit: Array = hero.get("_signatures")
	_expect(not kit.is_empty(), "the kit is non-empty")
	_cast_slot(hero, 0)
	_expect(not hero.call("signature_ready", 0),
		"an EMPTY mana pool does not stop a cast — the cast happened and burned its cooldown")
	_expect(is_equal_approx(float(hero.get("mp")), 0.0),
		"...and nothing was deducted (mp is tracked, never spent)")
	# The ult is the expensive one, so it is the one the old gate refused first.
	var ult: int = kit.size() - 1
	hero.set("mp", 0.0)
	_cast_slot(hero, ult)
	_expect(not hero.call("signature_ready", ult),
		"the ULT casts on an empty pool too (it was the first thing the gate blocked)")
	# The hotbar must not be dimmed for a reason that no longer exists: a slot that was
	# BOTH wiped and greyed said "not yet" twice.
	hero.set("mp", 0.0)
	var slot: Dictionary = hero.call("_signature_hud_slot")
	_expect(bool(slot.get("enabled", false)),
		"the signature hotbar slot is not dimmed by mana any more")
	hero.queue_free()
	_completes("no_mana_gate")


## `mp_cost` SURVIVES on SpellDef and is still load-bearing — it is one of
## `SpellTier`'s three shelf thresholds, and the shelf is also the reaction clash
## weight and the loadout slot rule. Deleting the field to "finish the job" would have
## silently reshelved spells.
func _test_mp_cost_still_drives_tier() -> void:
	var cheap := SpellDef.new()
	cheap.cast_time = 0.0
	cheap.cooldown = 1.0
	cheap.mp_cost = 10
	_expect(SpellTier.of(cheap) == SpellTier.Tier.QUICK, "a cheap fast spell is QUICK")
	var pricey := SpellDef.new()
	pricey.cast_time = 0.0
	pricey.cooldown = 1.0
	pricey.mp_cost = SpellTier.ULT_MP
	_expect(SpellTier.of(pricey) == SpellTier.Tier.ULT,
		"mp_cost alone still promotes a spell to the ULT shelf (%d)" % SpellTier.ULT_MP)
	# ...and a real library spell still lands where the kit table expects it.
	var any_ult: bool = false
	for s: SpellDef in SpellLibrary.build_all():
		if SpellTier.of(s) == SpellTier.Tier.ULT:
			any_ult = true
			break
	_expect(any_ult, "the library still contains ULT-shelf spells at all")
	_completes("mp_cost_still_drives_tier")


# ------------------------------------------------------ 6+7. everyone agrees
## The HUD and the bot blackboard must read the SAME bank, not keep private copies —
## three readers of one truth was the shape the old code got right and the numbers
## wrong.
func _test_hud_and_bots() -> void:
	var hero: CharacterBody2D = _make_hero()
	hero.configure_class(0)
	_cast_slot(hero, 0)
	var slot: Dictionary = hero.call("_signature_hud_slot")
	_expect(is_equal_approx(float(slot.get("remaining", -1.0)),
			float(hero.call("signature_cooldown", 0))),
		"the hotbar's `remaining` IS the selected slot's cooldown")
	var state: Dictionary = hero.call("bot_body_state")
	var cds: Array = state["cooldowns"]
	_expect(cds[0] > 0.0, "a bot sees slot 0 down")
	_expect(is_equal_approx(float(cds[1]), 0.0),
		"...and slot 1 up — the blackboard publishes per-slot truth, not one number in five hats")
	# `slot_affordable` changed MEANING when the mana gate died: it now answers "this
	# slot exists and is off cooldown". A key that always says yes is worse than no key.
	var afford: Array = state["slot_affordable"]
	_expect(not bool(afford[0]), "slot_affordable is false for a slot on cooldown")
	_expect(bool(afford[1]), "...and true for a ready one")
	# Kits are three spells while BotIntent.SLOT_COUNT is still five, so the tail slots
	# must read as unusable or a brain will keep reaching for spells nobody owns.
	var kit_size: int = (hero.get("_signatures") as Array).size()
	for i: int in range(kit_size, BotIntent.SLOT_COUNT):
		_expect(not bool(afford[i]),
			"slot %d holds no spell and reports unusable to a bot" % i)
	hero.queue_free()
	_completes("hud_and_bots_read_the_same_bank")


## `LoadoutBar` draws the League-style sweep as `cooldown / cooldown_total`, and
## NOTHING had ever written `cooldown_total` — the `.get(..., cd)` fallback made total
## == remaining, so the fraction was 1.0 every frame and the veil sat at full height
## for the whole cooldown and then vanished. The bar was never broken; it was being
## handed a number that did not exist.
func _test_loadout_bar_sweep() -> void:
	var hand := HandSlots.new()
	var spell := SpellDef.new()
	spell.id = "probe"
	spell.display_name = "Probe"
	hand.rebuild([], [spell])
	hand.start_cooldown(1, 4.0)
	_expect(is_equal_approx(hand.cooldown_total(1), 4.0),
		"start_cooldown records what the cooldown STARTED at")
	hand.tick(3.0)
	var entry: Dictionary = hand.slots[1]
	var frac: float = float(entry["cooldown"]) / maxf(float(entry.get("cooldown_total", 0.001)), 0.001)
	_expect(absf(frac - 0.25) < 0.001,
		"the sweep fraction is a real fraction (%.3f, expected 0.25)" % frac)
	hand.clear_cooldowns()
	_expect(hand.is_ready(1) and is_equal_approx(hand.cooldown(1), 0.0),
		"clear_cooldowns puts every slot back to ready")
	_completes("loadout_bar_can_draw_the_sweep")
