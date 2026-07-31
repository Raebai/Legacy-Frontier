class_name SpellGrant
extends RefCounted
## GIVING A HERO A SPELL THEY DID NOT START WITH — and taking it away again.
##
## Everything in the drop economy that touches a live hero goes through this file:
## picking a spell up off the floor, spending a Tier 3 charge, handing a spell to
## your teammate, and putting the class kit back at the start of the next floor.
##
## ══ THE RULES ══════════════════════════════════════════════════════════════════
##  1. A DROP TAKES A SEAT. The hand is three buttons and stays three buttons (see
##     `HandSlots`' note). Tier 2 replaces a non-ult slot; Tier 3 replaces the ult
##     slot. The displaced spell is remembered, never destroyed.
##  2. TIER 3 HAS CHARGES. Every cast spends one. At zero the drop evaporates and
##     the class ult comes straight back — the spec's "what happens when they run
##     out", answered without a dead button in the middle of a fight.
##  3. PROGRESSION RESETS EACH FLOOR. `restore_all` is called when the next floor's
##     props are built, so Tier 1 -> Tier 2 -> Tier 3 is an arc INSIDE a floor and
##     never a stockpile across them. That is the spec's shape exactly.
##  4. GRANTS ARE PER-HERO AND LIVE IN METADATA. `Node.set_meta` needs no member on
##     `Hero`, which this agent does not own. It survives everything a member would
##     and dies with the node, which is the right lifetime.
##
## ══ THE ONE HERO EDIT THIS WOULD LIKE, AND WHY IT IS NOT REQUIRED ══════════════
## `apply` prefers a public `Hero.receive_spell(spell, nth) -> bool` if one ever
## exists, and falls back to doing the surgery itself through `_signatures` and
## `_hand`. The fallback WORKS TODAY — that is why nothing here is blocked — but the
## clean version is two lines in `Hero.gd`:
##
##     func receive_spell(spell: SpellDef, nth: int) -> bool:
##         return SpellGrant.install(_signatures, _hand, spell, nth)
##
## Adding it makes the coupling explicit and lets `Hero` clear its ready-pulse latch
## on the swap. Until then the fallback reaches two privates by name, which is
## fragile in exactly the way this repo has been bitten by before — so
## `tools/slice_test_drops.gd` asserts both names still exist on a real Hero, and
## fails loudly the day either is renamed.

## Where the per-hero grant ledger lives.
const META_KEY: StringName = &"spell_grants"

## Which carousel spell slot a tier claims.
##   Tier 3 -> the ULT slot, because a boss drop IS your finisher for that floor
##             and because it is the slot whose loss you feel.
##   Tier 2 -> the FIRST non-ult slot, then the second, then round-robin over the
##             oldest granted one. Never the ult slot: taking a class's finisher
##             for a floor pickup would make the floor's biggest spell the thing
##             you found rather than the thing you built, and Tier 3 needs that
##             slot to be free to mean something later.
const TIER3_SLOT: int = SpellTier.ULT_SLOT


## The ledger for `hero`: `{ "slots": { nth: {"drop": SpellDef, "displaced":
## SpellDef, "charges": int} }, "order": [nth, ...] }`. Never null.
static func ledger(hero: Object) -> Dictionary:
	if hero == null or not is_instance_valid(hero):
		return {}
	var n: Node = hero as Node
	if n == null:
		return {}
	if not n.has_meta(META_KEY):
		n.set_meta(META_KEY, {"slots": {}, "order": []})
	return n.get_meta(META_KEY)


## Give `hero` a picked-up `spell`. Returns the carousel slot it landed in, or -1.
##
## Picking up a SECOND copy of a spell you already hold refills its charges instead
## of taking a second slot — otherwise a Tier 3 you found twice would cost you both
## of your other buttons for a spell you can only cast one of at a time.
static func apply(hero: Object, spell: SpellDef) -> int:
	if hero == null or not is_instance_valid(hero) or spell == null:
		return -1
	var book: Dictionary = ledger(hero)
	if book.is_empty():
		return -1
	var slots: Dictionary = book["slots"]
	# Already holding it? Refill and stop.
	for nth: int in slots.keys():
		if String((slots[nth]["drop"] as SpellDef).id) == spell.id:
			slots[nth]["charges"] = spell.charges
			return int(nth)
	var nth: int = _slot_for(spell, book)
	if nth < 0:
		return -1
	var displaced: SpellDef = _current_spell(hero, nth)
	if not _install(hero, spell, nth):
		return -1
	# A slot that already held a drop keeps the ORIGINAL displaced spell, not the
	# drop it is replacing. Otherwise picking up two Tier 2s in a row would restore
	# the first pickup at floor end instead of the class kit, and the "progression
	# resets each floor" rule would quietly stop being true.
	if not slots.has(nth):
		slots[nth] = {}
		(book["order"] as Array).append(nth)
		slots[nth]["displaced"] = displaced
	slots[nth]["drop"] = spell
	slots[nth]["charges"] = spell.charges
	return nth


## Which carousel slot this spell claims. See `TIER3_SLOT`'s note.
static func _slot_for(spell: SpellDef, book: Dictionary) -> int:
	if spell.kind == SpellDef.Kind.CATACLYSM:
		return TIER3_SLOT
	var slots: Dictionary = book["slots"]
	# First empty non-ult slot...
	for i: int in TIER3_SLOT:
		if not slots.has(i):
			return i
	# ...otherwise the one granted longest ago, so a third pickup overwrites the
	# first rather than always clobbering slot 0.
	var order: Array = book["order"]
	for nth: Variant in order:
		if int(nth) != TIER3_SLOT:
			return int(nth)
	return 0


## Spend one charge of `spell` if `caster` holds it as a granted drop. A spell with
## `charges < 0` (everything in every class kit) is untouched, so this is a no-op
## for the overwhelming majority of casts in the game.
##
## Called from `SpellCaster.cast` on a cast that actually produced a spectacle.
static func consume_charge(caster: Object, spell: SpellDef) -> void:
	if caster == null or not is_instance_valid(caster) or spell == null:
		return
	if spell.charges < 0:
		return
	var n: Node = caster as Node
	if n == null or not n.has_meta(META_KEY):
		return
	var slots: Dictionary = (n.get_meta(META_KEY) as Dictionary)["slots"]
	for nth: int in slots.keys():
		var row: Dictionary = slots[nth]
		if String((row["drop"] as SpellDef).id) != spell.id:
			continue
		row["charges"] = int(row["charges"]) - 1
		if int(row["charges"]) <= 0:
			# Spent. The class spell comes straight back rather than leaving a dead
			# button on the bar — a slot you cannot press and cannot explain is the
			# worst possible way to learn a spell ran out.
			revoke(caster, int(nth))
		return


## How many charges of `spell_id` `hero` has left; -1 for unlimited, 0 for a spell
## they do not hold. For the HUD and for the tests.
static func charges_left(hero: Object, spell_id: String) -> int:
	var n: Node = hero as Node
	if n == null or not is_instance_valid(n) or not n.has_meta(META_KEY):
		return 0
	var slots: Dictionary = (n.get_meta(META_KEY) as Dictionary)["slots"]
	for nth: int in slots.keys():
		if String((slots[nth]["drop"] as SpellDef).id) == spell_id:
			return int(slots[nth]["charges"])
	return 0


## The same answer keyed by CAROUSEL SLOT rather than by spell id — what every HUD
## actually has in hand. Returns -1 for "no granted drop in that slot", which reads
## as "nothing to draw" rather than as "zero charges left" (a real 0 never persists:
## `consume_charge` revokes the moment it hits zero).
##
## Exists because the bars know a slot INDEX and not an id: `Hero.spell_button_state`
## and `ability_hud_state` are both slot-keyed, and asking them to dig a SpellDef out
## so they could call `charges_left` would have every HUD reaching into the hand.
static func charges_in_slot(hero: Object, nth: int) -> int:
	var n: Node = hero as Node
	if n == null or not is_instance_valid(n) or not n.has_meta(META_KEY):
		return -1
	var slots: Dictionary = (n.get_meta(META_KEY) as Dictionary)["slots"]
	if not slots.has(nth):
		return -1
	var spell: SpellDef = (slots[nth] as Dictionary)["drop"]
	# A kit spell handed over (or an unlimited drop) has no count to show.
	if spell == null or spell.charges < 0:
		return -1
	return int((slots[nth] as Dictionary)["charges"])


## The granted drop `hero` is currently holding, or {} — `{"nth": int, "spell":
## SpellDef, "charges": int}`. The most recently picked-up one wins, which is what
## "hand over what you just found" should mean.
static func held(hero: Object) -> Dictionary:
	var n: Node = hero as Node
	if n == null or not is_instance_valid(n) or not n.has_meta(META_KEY):
		return {}
	var book: Dictionary = n.get_meta(META_KEY)
	var order: Array = book["order"]
	var slots: Dictionary = book["slots"]
	for i: int in range(order.size() - 1, -1, -1):
		var nth: int = int(order[i])
		if slots.has(nth):
			return {"nth": nth, "spell": slots[nth]["drop"],
				"charges": int(slots[nth]["charges"])}
	return {}


## Take the drop out of slot `nth` and put the displaced class spell back. Returns
## the drop that was removed, or null.
static func revoke(hero: Object, nth: int) -> SpellDef:
	var n: Node = hero as Node
	if n == null or not is_instance_valid(n) or not n.has_meta(META_KEY):
		return null
	var book: Dictionary = n.get_meta(META_KEY)
	var slots: Dictionary = book["slots"]
	if not slots.has(nth):
		return null
	var row: Dictionary = slots[nth]
	var drop: SpellDef = row["drop"]
	var back: SpellDef = row["displaced"]
	if back != null:
		_install(hero, back, nth)
	slots.erase(nth)
	(book["order"] as Array).erase(nth)
	return drop


## Put every class spell back. Called at the start of every floor — the spec's
## "resets each floor" — and safe to call on a hero that has no grants.
static func restore_all(hero: Object) -> void:
	var n: Node = hero as Node
	if n == null or not is_instance_valid(n) or not n.has_meta(META_KEY):
		return
	var slots: Dictionary = (n.get_meta(META_KEY) as Dictionary)["slots"]
	for nth: int in slots.keys().duplicate():
		revoke(hero, nth)


# ------------------------------------------------------------------- HANDOFF
## PLAYER-TO-PLAYER SPELL HANDOFF — the spec's "build this", and the reason is that
## it produces both the generous play and the betrayal, and both get clipped.
##
## It is deliberately the WHOLE grant that moves, charges included, and the giver is
## left with their class spell back. So handing your last Void charge to the player
## who can actually reach the boss is a real sacrifice, and "I'll take that" is a
## real theft. There is no confirmation and no undo.
##
## Returns true if anything moved.
static func hand_over(giver: Object, taker: Object) -> bool:
	if giver == null or taker == null or giver == taker:
		return false
	if not is_instance_valid(giver) or not is_instance_valid(taker):
		return false
	var have: Dictionary = held(giver)
	if have.is_empty():
		return false
	var spell: SpellDef = have["spell"]
	var charges: int = int(have["charges"])
	if revoke(giver, int(have["nth"])) == null:
		return false
	if apply(taker, spell) < 0:
		# Could not land it — give it back rather than deleting it. A handoff that
		# eats the item is the single worst bug this feature could ship with.
		apply(giver, spell)
		return false
	# Charges travel with the spell. `apply` seeds them from the SpellDef's full
	# count, so a half-spent Void handed over would otherwise arrive refilled.
	_set_charges(taker, spell.id, charges)
	return true


static func _set_charges(hero: Object, spell_id: String, value: int) -> void:
	var n: Node = hero as Node
	if n == null or not n.has_meta(META_KEY):
		return
	var slots: Dictionary = (n.get_meta(META_KEY) as Dictionary)["slots"]
	for nth: int in slots.keys():
		if String((slots[nth]["drop"] as SpellDef).id) == spell_id:
			slots[nth]["charges"] = value
			return


# -------------------------------------------------------------- the hand surgery

## What is in carousel spell slot `nth` right now.
static func _current_spell(hero: Object, nth: int) -> SpellDef:
	var hand: Variant = (hero as Object).get(&"_hand")
	if hand != null and hand is HandSlots:
		var s: Variant = (hand as HandSlots).spell_at(nth)
		if s is SpellDef:
			return s as SpellDef
	var sigs: Variant = (hero as Object).get(&"_signatures")
	if sigs is Array and nth >= 0 and nth < (sigs as Array).size():
		return (sigs as Array)[nth] as SpellDef
	return null


## Write `spell` into slot `nth` of a live hero. Prefers a public hook, falls back
## to the two privates (see this file's header for why that fallback exists and
## what guards it).
static func _install(hero: Object, spell: SpellDef, nth: int) -> bool:
	if hero.has_method(&"receive_spell"):
		return bool(hero.call(&"receive_spell", spell, nth))
	var sigs: Variant = hero.get(&"_signatures")
	var hand: Variant = hero.get(&"_hand")
	if not (sigs is Array) or not (hand is HandSlots):
		return false
	return install(sigs as Array, hand as HandSlots, spell, nth)


## The surgery itself, on plain data — no tree, no Hero, headless-testable, and the
## exact body the recommended `Hero.receive_spell` would have.
##
## BOTH halves are needed and they are not redundant. `_signatures` is what
## `Hero.cast_signature_slot` reads to decide WHAT to cast; `_hand` is what owns the
## per-slot cooldown and what the loadout bar draws. Writing one and not the other
## produces a bar showing a spell that casts something else, which is the exact
## class of two-sources-of-truth bug this codebase has a scar from.
static func install(signatures: Array, hand: HandSlots, spell: SpellDef, nth: int) -> bool:
	if spell == null or hand == null:
		return false
	if nth < 0 or nth >= signatures.size():
		return false
	signatures[nth] = spell
	return hand.replace_spell(nth, spell)
