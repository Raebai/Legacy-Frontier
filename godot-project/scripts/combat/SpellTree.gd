class_name SpellTree
extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════════
## THE SPELL TREES. PURE DATA + PURE FUNCTIONS. NO UI, NO SCENE, NO STATE.
## ═══════════════════════════════════════════════════════════════════════════════
##
## Maker's brief: a Wizard-of-Legend-ish hub with per-class spell trees and
## "cross-class links based on semi relevant links / strategies", so you choose
## your own binds.
##
## ⚠ THE CROSS-CLASS LINKS ALREADY EXISTED IN THE DATA, and that is the single most
## important thing about this file. `CLASS_KITS` already shares spells between
## classes — `rock_pillar` is the Arcanist's payoff AND the Juggernaut's;
## `drain_tether` is in three kits; `chain_lightning` in two; `blink_strike` in
## three. So the tree does not invent a borrowing system. **It makes a sharing that
## is already true VISIBLE, and puts a price on it.**
##
## ⚠ IT GROWS YOUR OPTIONS, NEVER YOUR HAND. You carry four of five roles
## (`SpellLibrary.SLOT_ROLES`, `SpellTier.SLOT_COUNT`). Unlocking a node makes a spell
## BINDABLE, and the 4-of-5 hand — the existing balance surface — is untouched. A free
## web would let someone carry five damage spells and no answer, which is not a build,
## it is a hole.
##
## ⚠ THE TREE GOT ONE POINT CHEAPER WHEN THE FOURTH SLOT LANDED, and it is arithmetic,
## not a discount: a whole tree is (natives you do not already own) + 4 links, and you
## now start with four of the five natives instead of three. 10 points -> 9. The five
## roles the fourth slot RE-POINTED all link to the spell they used to hold, so nothing
## the old table reached became unreachable — it costs 2 points now instead of 0.

## What a node costs. A native is your own class's; a link is a strategy you went
## and got, and it should be felt.
const COST_NATIVE: int = 1
const COST_LINKED: int = 2

## The five branches, in the order `SpellLibrary.ROLE_ORDER` declares them.
const ROLES: Array[String] = ["damage", "control", "answer", "payoff", "ult"]

## ⚠ YOUR ULT IS NEVER LINKED, AND IT IS THE ONE HARD EXCEPTION.
## `heavens_wrath`, `thousand_cuts`, `fault_line`, `meteor_fist`, `horizon_cut` are
## the class fantasies. The class-identity ruling is "every class needs a unique
## signature spell", and a tradable ult is a recolour with extra steps. Your ult is
## why you picked the class.
const ULT_ROLE: String = "ult"

## ═══════════════════════════════════════════════════════════════════════════════
## THE NINE TREES
## ═══════════════════════════════════════════════════════════════════════════════
## `native` is the class's own authored kit spell for that role (from `CLASS_KITS`,
## read off the real table rather than retyped). `linked` is the reachable spell
## from elsewhere in the catalog.
##
## THE LINK GRAMMAR — what "semi-relevant" means, made a rule. A class may reach
## another class's spell when they share EITHER:
##   * an ELEMENT the class already casts, or
##   * a ROLE ARCHETYPE — the same job done a different way (a wall is a wall).
##
## ⚠ NO SPELL MAY APPEAR TWICE IN ONE CLASS'S TREE. Four of the design doc's mock
## trees violated this — the Shadowblade's answer linked to `blink_strike`, which
## is its own payoff native; the Brawler's damage linked to `boulder_hurl`, its own
## payoff native; the Cryomancer's control linked to `ice_wall`, its own answer
## native; the Warlock's damage AND control both collided with its own kit. A node
## you already own is not a choice, so those four are re-pointed below and
## `_test_no_class_can_buy_the_same_spell_twice` is why they cannot come back.
##
## Every spell named here is real and in the 49-spell catalog today.
const TREES: Array[Dictionary] = [
	# ── 0 ARCANIST — arcane zoner ───────────────────────────────────────────────
	{
		"damage":  {"native": "ordinary_spell", "linked": "frostpiercer"},   # beam kin
		"control": {"native": "mirror_image",   "linked": "chronostasis"},   # arcane control
		"answer":  {"native": "blink_strike",   "linked": "rift_dagger"},    # get-out kin
		# ⚠ SWAPPED BY THE FOURTH SLOT. Arcane Missiles is the CARRIED payoff now and the
		# Juggernaut's pillar is what you go and buy — the two changed places, and the
		# pillar is still reachable at a link price.
		"payoff":  {"native": "rune_orbs",      "linked": "rock_pillar"},    # arcane payoff
		"ult":     {"native": "meteor_sigil",   "linked": ""},
	},
	# ── 1 SHADOWBLADE — in-and-out assassin ─────────────────────────────────────
	{
		"damage":  {"native": "blade_flurry",   "linked": "iai_slash"},      # burst kin
		"control": {"native": "creeping_shade", "linked": "void_zone"},      # shadow control
		# ⚠ RE-POINTED. The design doc linked this to `blink_strike`, which is this
		# class's own payoff native two rows down — a node it would already own.
		"answer":  {"native": "rift_dagger",    "linked": "the_void"},       # shadow answer
		"payoff":  {"native": "blink_strike",   "linked": "crescent_step"},  # reposition kin
		"ult":     {"native": "thousand_cuts",  "linked": ""},
	},
	# ── 2 BRAWLER — pure melee ──────────────────────────────────────────────────
	{
		# ⚠ RE-POINTED. The doc linked this to `boulder_hurl` — its own payoff native.
		"damage":  {"native": "shockwave_stomp", "linked": "iai_slash"},     # committed-cut kin
		# ⚠ RE-POINTED BY THE FOURTH SLOT. A lightning chain was the carried control on the
		# one class whose card says "no magic"; Petrify carries it now and the chain is a
		# thing this class can deliberately go and BUY, which is a different statement.
		"control": {"native": "petrify",         "linked": "chain_lightning"}, # stone control
		"answer":  {"native": "rock_wall",       "linked": "ice_wall"},      # wall archetype
		"payoff":  {"native": "boulder_hurl",    "linked": "rock_pillar"},   # earth kin
		"ult":     {"native": "meteor_fist",     "linked": ""},
	},
	# ── 3 JUGGERNAUT — siege tank ───────────────────────────────────────────────
	{
		"damage":  {"native": "boulder_hurl",  "linked": "shockwave_stomp"}, # earth kin
		# ⚠ RE-POINTED BY THE FOURTH SLOT — the wall was the Brawler's and is a purchase now.
		"control": {"native": "gravity_flip",  "linked": "rock_wall"},       # earth control
		"answer":  {"native": "drain_tether",  "linked": "aegis_ward"},      # survival archetype
		"payoff":  {"native": "rock_pillar",   "linked": "shatter"},         # detonator archetype
		"ult":     {"native": "fault_line",    "linked": ""},
	},
	# ── 4 CLERIC — radiant lifesteal bruiser ────────────────────────────────────
	{
		# ⚠ THE LINK MOVED BY THE FOURTH SLOT: `judgment` is this class's CARRIED answer
		# now, and a node you already own is not a choice. The drain it stopped carrying
		# takes the slot — same lifesteal archetype, and still reachable.
		"damage":  {"native": "radiant_volley",  "linked": "drain_tether"},  # lifesteal archetype
		"control": {"native": "aegis_ward",      "linked": "equinox"},       # holy control
		"answer":  {"native": "judgment",        "linked": "blink_strike"},  # mobility archetype
		# ⚠ RE-POINTED. The design doc proposed «heavens_wrath» here — which is the
		# STORMCALLER'S ULT, so the doc's own §3 ("ults are never linked") was broken
		# by its own mock tree. Every other holy spell is either already in this tree
		# or is itself an ult, so the link goes to a payoff ARCHETYPE instead. It also
		# gives `colossus_pillar` — one of the seven spells the anti-recolour pass
		# orphaned out of every kit — a home.
		"payoff":  {"native": "chain_lightning", "linked": "colossus_pillar"}, # payoff archetype
		"ult":     {"native": "heavens_verdict", "linked": ""},
	},
	# ── 5 CRYOMANCER — ice control ──────────────────────────────────────────────
	{
		"damage":  {"native": "shatter",      "linked": "frostpiercer"},     # ice beam kin
		# ⚠ RE-POINTED. The doc linked this to `ice_wall` — its own answer native.
		"control": {"native": "blizzard",     "linked": "chronostasis"},     # slow archetype
		"answer":  {"native": "ice_wall",     "linked": "rock_wall"},        # wall archetype
		"payoff":  {"native": "blink_strike", "linked": "rock_pillar"},      # detonator archetype
		"ult":     {"native": "frozen_comet", "linked": ""},
	},
	# ── 6 STORMCALLER — lightning combo ─────────────────────────────────────────
	# ⚠ THIS CLASS WINS 16-0 ON THE HONEST HARNESS. The design doc's instruction was
	# "do not give it cheap links — its links should be the most expensive, or the
	# class stays a late unlock and the tree does not widen it at all." It IS a late
	# unlock (`Progression.LOCKED_CLASSES`), which is the option the doc offered, so
	# the link prices here are ordinary. If playtest says the tree widens the gap
	# anyway, the lever is a per-class link cost — not a re-point of these rows.
	{
		# ⚠ RE-POINTED. The doc linked this to `thunderclap` — its own payoff native.
		"damage":  {"native": "chain_lightning", "linked": "tempest"},       # lightning kin
		"control": {"native": "blizzard",        "linked": "creeping_shade"},# field archetype
		"answer":  {"native": "blink_strike",    "linked": "crescent_step"}, # mobility kin
		"payoff":  {"native": "thunderclap",     "linked": "rune_orbs"},     # payoff archetype
		"ult":     {"native": "heavens_wrath",   "linked": ""},
	},
	# ── 7 WARLOCK — thrall hexer ────────────────────────────────────────────────
	{
		# ⚠ RE-POINTED. The doc linked this to `void_zone` — its own answer native.
		"damage":  {"native": "drain_tether",   "linked": "umbral_lance"},   # shadow beam kin
		# ⚠ RE-POINTED. The doc linked this to `creeping_shade` — its own payoff native.
		"control": {"native": "raise_thrall",   "linked": "the_void"},       # shadow control
		"answer":  {"native": "void_zone",      "linked": "blood_pact"},     # shadow answer
		"payoff":  {"native": "creeping_shade", "linked": "arc_of_fools"},   # chaos payoff
		"ult":     {"native": "grave_tide",     "linked": ""},
	},
	# ── 8 SWORDSAINT — parry duellist ───────────────────────────────────────────
	{
		"damage":  {"native": "iai_slash",     "linked": "blade_flurry"},    # burst kin
		# ⚠ RE-POINTED BY THE FOURTH SLOT — the wall was the Brawler's. The pact is the
		# duelist's carried price; the wall is what it can go and buy.
		"control": {"native": "blood_pact",    "linked": "rock_wall"},       # duellist's price
		"answer":  {"native": "crescent_step", "linked": "rift_dagger"},     # get-out kin
		# ⚠ RE-POINTED. The doc proposed «thousand_cuts» — the SHADOWBLADE'S ULT. Same
		# violation as the Cleric's payoff above. `shockwave_stomp` is the doc's own
		# alternative for this slot and is a real finisher that belongs to nobody's ult.
		"payoff":  {"native": "boulder_hurl",  "linked": "shockwave_stomp"}, # finisher archetype
		"ult":     {"native": "horizon_cut",   "linked": ""},
	},
]


## A node's stable id: `<class>:<role>:<native|linked>`. This is what goes in the
## save, so it must never be derived from a spell name — re-pointing a link (which
## this file has already had to do five times) would otherwise silently orphan
## every save that had bought it.
static func node_id(hero_class: int, role: String, linked: bool) -> String:
	return "%d:%s:%s" % [hero_class, role, "linked" if linked else "native"]


static func cost_of(node: String) -> int:
	return COST_LINKED if node.ends_with(":linked") else COST_NATIVE


## The spell a node grants, or "" if the node does not exist (an ult has no link).
static func spell_of(node: String) -> String:
	var parts: PackedStringArray = node.split(":")
	if parts.size() != 3:
		return ""
	var cls: int = int(parts[0])
	if cls < 0 or cls >= TREES.size():
		return ""
	var branch: Dictionary = TREES[cls].get(parts[1], {})
	return String(branch.get("linked" if parts[2] == "linked" else "native", ""))


## Every node id in a class's tree, in branch order. The UI's whole layout.
static func nodes_for_class(hero_class: int) -> Array[String]:
	var out: Array[String] = []
	if hero_class < 0 or hero_class >= TREES.size():
		return out
	for role: String in ROLES:
		var branch: Dictionary = TREES[hero_class].get(role, {})
		if String(branch.get("native", "")) != "":
			out.append(node_id(hero_class, role, false))
		if String(branch.get("linked", "")) != "":
			out.append(node_id(hero_class, role, true))
	return out


## ⚠ WHAT YOU ALREADY OWN, FOR FREE. A class starts carrying three of its five
## roles (`SpellLibrary.SLOT_ROLES`), so those three natives are yours the moment
## you pick the class. Charging for a spell already in your hand would mean a fresh
## climber's first purchase buys them nothing they did not have.
##
## This is a FUNCTION of SLOT_ROLES rather than a second table, so changing a
## class's starting hand cannot leave the tree charging for it.
static func free_nodes(hero_class: int) -> Array[String]:
	var out: Array[String] = []
	# THE AUTHORED hand, not the player's current pick. `SpellLibrary` also exposes a
	# live chosen-roles lookup, and reading THAT here would make what you OWN change
	# every time you re-bind at the lectern — a player who swapped their hand would
	# find nodes they had paid for turned back into free ones, and their spent points
	# silently refunded.
	for role in SpellLibrary.default_slot_roles_for_class(hero_class):
		out.append(node_id(hero_class, String(role), false))
	return out


static func is_free(node: String) -> bool:
	var parts: PackedStringArray = node.split(":")
	if parts.size() != 3:
		return false
	return free_nodes(int(parts[0])).has(node)


## Is this node bought (or free)?
static func is_unlocked(node: String, owned: Array) -> bool:
	if is_free(node):
		return true
	for o in owned:
		if str(o) == node:
			return true
	return false


## What a class's whole tree costs to complete. 5 natives (3 free) + 4 links = 10.
##
## ⚠ AND THAT NUMBER IS NOT A COINCIDENCE WORTH LOSING. One Skill Point per level
## means a class tree completes at level 11, and one full climb of the ten-floor
## tower lands a climber at level 12 — so "climb the tower once" and "master one
## class" are the same size of commitment. If either curve moves, check this still
## reads that way; `_test_a_tree_is_about_one_climb` is the pin.
static func total_cost(hero_class: int) -> int:
	var sum: int = 0
	for n: String in nodes_for_class(hero_class):
		if not is_free(n):
			sum += cost_of(n)
	return sum


## Points spent, DERIVED by summing what is owned. Never stored — a stored balance
## can drift from the thing it is a balance of, which is the same reason Growth is
## derived from level rather than banked.
static func points_spent(owned: Array) -> int:
	var sum: int = 0
	for o in owned:
		var node: String = str(o)
		# ⚠ `spell_of` IS THE VALIDITY CHECK, and it has to be. `cost_of` answers from
		# the id's SUFFIX alone, so any string that does not end in ":linked" reads as
		# a 1-point native — meaning a corrupt save (or a renamed node id) would bill
		# the player a point for a node that grants nothing, and permanently.
		if node == "" or spell_of(node) == "" or is_free(node):
			continue
		sum += cost_of(node)
	return sum


## Points EARNED over a career: one per level, so level 1 has none.
static func points_earned(level: int) -> int:
	return maxi(level - 1, 0)


static func points_available(level: int, owned: Array) -> int:
	return maxi(points_earned(level) - points_spent(owned), 0)


## May this node be bought right now? A node is buyable when it exists, is not
## already owned, is not free, and the climber can afford it.
##
## ⚠ NO PREREQUISITE CHAIN, DELIBERATELY. A branch's link does not require its
## native first: the native may already be free (three of five are), and gating the
## interesting half of the tree behind the half you were given is a click, not a
## decision. The PRICE is the gate.
static func can_buy(node: String, hero_class: int, level: int, owned: Array) -> bool:
	if spell_of(node) == "":
		return false
	if not nodes_for_class(hero_class).has(node):
		return false
	if is_unlocked(node, owned):
		return false
	return points_available(level, owned) >= cost_of(node)


## Every spell a class can currently BIND: its free hand plus everything bought.
static func bindable_spells(hero_class: int, owned: Array) -> Array[String]:
	var out: Array[String] = []
	for n: String in nodes_for_class(hero_class):
		if is_unlocked(n, owned):
			var s: String = spell_of(n)
			if s != "" and not out.has(s):
				out.append(s)
	return out
