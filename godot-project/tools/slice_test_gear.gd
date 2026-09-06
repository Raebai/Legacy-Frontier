# Run: godot --headless --path godot-project --script tools/slice_test_gear.gd
# Gear customization coverage: the drawable-piece registry (CharacterRig.GEAR_KINDS),
# the ability registry (GearAbilities), and the enemy archetype gear map must stay in
# sync — every equipped piece needs a defined ability, and every archetype/class weapon
# kind must be a real registered piece. Pure data checks (no tree/autoloads), so
# headless. Runs on first _process (autoload-safe).
#
# The old EQUIP_TEX pixel-overlay map this used to walk is GONE: gear is drawn
# procedurally and REPLACES the head/torso rather than being blitted over it (maker:
# "replace the torso or head etc., not be on top of them"), so there are no texture
# files left to assert the existence of. The registry it checks is now the list of
# kinds the rig can actually draw.
#
# ⚠ THE ARMOURY'S NINETEEN ARE REAL ITEMS NOW, AND THIS SUITE CHANGED SIDES.
# It used to assert the opposite of what it asserts today: that every offered piece was
# a NAMED PROMISE with an empty effect bag. That guard existed so a stub could not
# quietly become balance before anyone designed it — a good rule, and it has been
# retired the only legitimate way, by DOING the design rather than by deleting the rule.
# What replaced it is strictly stronger, because "the bag is empty" only ever proved the
# items were harmless. These prove they are GOOD:
#   * every offered piece carries live stats, inside a stated budget envelope;
#   * no offered piece strictly dominates another in its slot (unpickable == dead);
#   * every offered piece is worse than the EMPTY slot somewhere (or equipping is a
#     chore, not a choice);
#   * every element string it names is one the Hero can actually map;
#   * a piece whose SLOT the Hero does not read is flagged, and the flag and the Hero
#     are asserted to move together.
extends SceneTree

const RIG_PATH: String = "res://scripts/combat/CharacterRig.gd"
const ENEMY_PATH: String = "res://scripts/combat/Enemy.gd"
const HERO_PATH: String = "res://scripts/combat/Hero.gd"

# ── THE AXES, AND THE DIRECTION EACH ONE POINTS ─────────────────────────────────
# File-scope rather than inline, because dominance and pricing are the SAME comparison
# asked twice (is a better than b / is a better than nothing) and two copies of the
# direction logic is two chances to get `melee_cd` backwards. `_axis` is the single
# place that knows a duration is better when it is smaller.
const AXES: Array = ["melee_damage", "melee_knockback", "melee_cd", "max_hp",
	"speed", "ward", "damage_reduction"]
const LOWER_IS_BETTER: Array = ["melee_cd"]
# The value an axis has when the slot is EMPTY. Mults sit at 1.0; the two mitigation
# axes are additive-from-zero, so their neutral is 0.0.
const ZERO_BASED: Array = ["ward", "damage_reduction"]

# ── THE BUDGET THE ARMOURY IS AUTHORED INSIDE ───────────────────────────────────
# The envelope the RETIRED sixteen already established, which the balance pass has
# already been played against. Asserting it here is what stops the armoury from
# power-creeping one "just slightly stronger" row at a time — a drift that no
# individual edit looks wrong enough to catch in review.
const BUDGET: Dictionary = {
	"max_hp": [0.94, 1.20],
	"speed": [0.92, 1.12],
	"melee_damage": [0.82, 1.30],
	"melee_cd": [0.70, 1.30],
	"melee_knockback": [0.88, 1.40],
	"ward": [0.40, 0.40],              # one-shot first-hit reduction, one size only
	"damage_reduction": [0.15, 0.15],  # flat, every hit, one size only
}

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failed: int = 0
	var rig_consts: Dictionary = (load(RIG_PATH) as GDScript).get_script_constant_map()
	var equip_tex: Array = rig_consts["GEAR_KINDS"]

	# Every drawable piece has a unique ability + a label.
	for kind: String in equip_tex:
		failed += _expect(GearAbilities.has_ability(kind), "ability defined for '%s'" % kind)
		failed += _expect(GearAbilities.label(kind) != "", "label non-empty for '%s'" % kind)

	# Every enemy archetype's weapon kind must be a real registered piece.
	var enemy_consts: Dictionary = (load(ENEMY_PATH) as GDScript).get_script_constant_map()
	var arch_gear: Dictionary = enemy_consts["ARCHETYPE_GEAR"]
	for arch: int in arch_gear:
		var wk: String = arch_gear[arch]
		failed += _expect(equip_tex.has(wk), "archetype %d gear '%s' is registered" % [arch, wk])

	# The magic-circle aura emblem asset exists.
	failed += _expect(ResourceLoader.exists(rig_consts["AURA_CIRCLE_PATH"]), "aura magic-circle asset exists")

	# ── EVERY ELEMENT STRING MUST BE ONE THE HERO CAN MAP ───────────────────────
	# ⚠ A SPELLING THE HERO DOES NOT KNOW IS THE QUIETEST BUG THIS FILE CAN SHIP.
	# `Hero._aggregate_gear` does `GEAR_ELEMENT.get(str, -1)` and a -1 means "keep the
	# class's own element" — so `"fire "` or `"flame"` does not error, does not warn,
	# and does not apply. The item simply stops being an elemental item while its
	# description goes on claiming otherwise. Asserted against HERO'S OWN TABLE rather
	# than a list typed here, because a list typed here could agree with the registry
	# and still disagree with the only reader that matters.
	var hero_consts: Dictionary = (load(HERO_PATH) as GDScript).get_script_constant_map()
	var gear_element: Dictionary = hero_consts["GEAR_ELEMENT"]
	failed += _expect(gear_element.size() >= 5,
		"Hero.GEAR_ELEMENT was actually found (got %d entries)" % gear_element.size())
	var elems_seen: int = 0
	for kind: String in GearAbilities.ABILITIES:
		var eff: Dictionary = GearAbilities.effect(kind)
		if not eff.has("element"):
			continue
		failed += _expect(gear_element.has(String(eff["element"])),
			"'%s' names element '%s', which Hero.GEAR_ELEMENT can map" % [kind, String(eff["element"])])
		elems_seen += 1
	failed += _expect(elems_seen >= 10, "elemental pieces were actually swept (got %d)" % elems_seen)

	# Every effect bag is well-formed: mults are positive, ward/DR are 0..1 fractions.
	# Guards against a typo silently no-op'ing an ability.
	const MULT_KEYS: Array = ["melee_damage", "melee_knockback", "melee_cd", "max_hp", "speed"]
	for kind: String in GearAbilities.ABILITIES:
		var e: Dictionary = GearAbilities.effect(kind)
		for mk: String in MULT_KEYS:
			if e.has(mk):
				failed += _expect(float(e[mk]) > 0.0, "positive %s mult for '%s'" % [mk, kind])
		for fk: String in ZERO_BASED:
			if e.has(fk):
				failed += _expect(float(e[fk]) >= 0.0 and float(e[fk]) <= 1.0,
					"%s is a 0..1 fraction for '%s'" % [fk, kind])
		# ⚠ NO KEY OUTSIDE THE VOCABULARY. An unknown key is not a future feature, it is
		# an inert one: nothing reads it, every sweep above skips it, and the item's
		# description promises it forever. This is the assertion that makes the "wire it
		# to the closest REAL axis" rule in GearAbilities.gd's header enforceable.
		for k: String in e:
			failed += _expect(k == "element" or AXES.has(k),
				"'%s' carries only known effect keys - '%s' would be read by nobody" % [kind, k])

	# ── NO ITEM MAY STRICTLY DOMINATE ANOTHER IN THE SAME SLOT ──────────────────
	# A dominated item is not weak, it is UNPICKABLE — better on nothing, worse on
	# nothing, so no hero in no situation ever wants it. Two shipped that way
	# (`hat` under `helmet`, `sword` under `hammer`) and nothing noticed, because
	# every existing gear assertion pins individual VALUES and dominance is a
	# relation BETWEEN values.
	#
	# ⚠ TWO CATALOGUES, SWEPT BY THE SAME CODE, FOR DIFFERENT REASONS. The RETIRED list
	# is off the menu but still read by the rig and the enemy roster, so it is held to
	# the rule it was fixed to satisfy. The OFFERED list is what a player actually picks
	# between, so it is the one where a dominated row is a live defect.
	const RETIRED_SLOT_ITEMS: Dictionary = {
		"weapon": ["sword", "dagger", "hammer", "greatsword"],
		"head": ["hat", "hood", "helmet"],
		"body": ["robe", "cape", "armor"],
	}
	failed += _sweep_dominance(RETIRED_SLOT_ITEMS, "retired")
	failed += _sweep_dominance(GearAbilities.PLACEHOLDER_SLOTS, "armoury")

	# ── EVERY PLAYER PIECE MUST PAY SOMETHING ───────────────────────────────────
	# Maker, 2026-08-04: "please do all the stuff you need to do". The standing
	# complaint this closes is that most pieces beat the EMPTY slot for free, so
	# "equip something" was a checklist even after "equip WHICH" became a real choice.
	#
	# A piece that is better on some axis and worse on none is not a decision, it is
	# a chore: the correct play is always to fill the slot, and the only question left
	# is which flavour of free.
	#
	# ⚠ THE CASTER WEAPONS ARE EXEMPT, AND THAT IS NOT A LOOPHOLE. A staff grants no
	# power at all — it OVERRIDES your element, and your class already has one. So it
	# is a lateral trade (holy for ice) rather than a free gain, and there is no axis
	# on which to charge it without inventing one.
	#
	# ⚠ AND THE EXEMPTION LIST DID NOT GROW FOR THE ARMOURY. Six of the eight new
	# spellements also override your element and could have claimed the same exemption;
	# they were each given a real cost instead, so the offered catalogue is swept with
	# NO exemptions at all. An exemption list is a place where dead content hides, and
	# the shorter it stays the more the rule means.
	const PAYS_NOTHING_OK: Array = ["staff", "staff_ice", "staff_storm", "staff_holy",
		"scythe", "orb", "club", "spear", "bomb", "crown"]
	var priced: int = 0
	for slot2: String in RETIRED_SLOT_ITEMS:
		for kind2: String in (RETIRED_SLOT_ITEMS[slot2] as Array):
			if PAYS_NOTHING_OK.has(kind2):
				continue
			failed += _expect(_pays_something(kind2),
				"'%s' is worse than the EMPTY slot somewhere - otherwise equipping it is a chore, not a choice" % kind2)
			priced += 1
	# ⚠ An invariant that is trivially true of an empty sweep is not an invariant.
	# Ten retired player-equippable pieces across the three slots.
	failed += _expect(priced == 10,
		"all ten retired player-equippable pieces were priced (got %d)" % priced)

	# Aggregation math (mirrors Hero._aggregate_gear): staff_ice + hat + robe ->
	# element=ice, ward=0.4, melee mults untouched — and max_hp COMPOSES.
	#
	# ⚠ THIS ASSERTION USED TO READ `max_hp == 1.12`, i.e. "the hat sets it", which
	# was only ever true because every other piece in the bag left max_hp alone. Now
	# that each piece pays a cost, the robe's -6% multiplies against the hat's +12%
	# and the honest answer is 1.0528. Asserted as a PRODUCT of the two pieces rather
	# than as a typed-in 1.0528, so re-tuning either number keeps this test true
	# without anyone having to recompute it by hand.
	var agg: Dictionary = _aggregate(["staff_ice", "hat", "robe"])
	failed += _expect(String(agg["element"]) == "ice", "staff_ice sets element ice")
	var hat_hp: float = float(GearAbilities.effect("hat").get("max_hp", 1.0))
	var robe_hp: float = float(GearAbilities.effect("robe").get("max_hp", 1.0))
	failed += _expect(is_equal_approx(float(agg["max_hp"]), hat_hp * robe_hp),
		"hat and robe COMPOSE on max_hp (%.4f x %.4f = %.4f, got %.4f)"
			% [hat_hp, robe_hp, hat_hp * robe_hp, float(agg["max_hp"])])
	failed += _expect(hat_hp * robe_hp > 1.0,
		"...and the pair is still a net gain, or the head slot would be a trap")
	failed += _expect(is_equal_approx(float(agg["ward"]), 0.4), "robe sets ward 0.4")
	failed += _expect(is_equal_approx(float(agg["melee_damage"]), 1.0), "no weapon melee change here")
	# hammer stacks melee damage + knockback.
	var agg2: Dictionary = _aggregate(["hammer"])
	failed += _expect(is_equal_approx(float(agg2["melee_damage"]), 1.2), "hammer +20% melee damage")
	failed += _expect(is_equal_approx(float(agg2["melee_knockback"]), 1.4), "hammer +40% knockback")

	# ── AND THE SAME MATH ON A REAL ARMOURY SET ─────────────────────────────────
	# A full kit the player can actually assemble today, so the composition rules are
	# proved on the catalogue that ships rather than only on the retired one.
	# ⚠ THE TWO WARDS ARE THE POINT OF THIS CASE. `pl_sunmote` (0.40) and `pl_stormcoat`
	# (0.40) do NOT add up to 0.80 — Hero combines ward with `maxf`, so wearing both
	# wastes one. Asserting it here is what stops someone "fixing" the duplicate 0.40s
	# by making one of them 0.55 and quietly inventing a best-in-slot.
	var agg3: Dictionary = _aggregate(["pl_sunmote", "pl_ironbrow", "pl_stormcoat"])
	failed += _expect(String(agg3["element"]) == "holy", "pl_sunmote sets element holy")
	failed += _expect(is_equal_approx(float(agg3["ward"]), 0.4),
		"two 0.40 wards do NOT stack - maxf takes one (got %.4f)" % float(agg3["ward"]))
	# Read from the registry rather than typed in, so re-tuning either row keeps this
	# true without anyone having to recompute the product by hand.
	var brow_hp: float = float(GearAbilities.effect("pl_ironbrow").get("max_hp", 1.0))
	var coat_hp: float = float(GearAbilities.effect("pl_stormcoat").get("max_hp", 1.0))
	failed += _expect(is_equal_approx(float(agg3["max_hp"]), brow_hp * coat_hp),
		"ironbrow and stormcoat COMPOSE on max_hp (%.4f x %.4f = %.4f, got %.4f)"
			% [brow_hp, coat_hp, brow_hp * coat_hp, float(agg3["max_hp"])])
	var mote_dmg: float = float(GearAbilities.effect("pl_sunmote").get("melee_damage", 1.0))
	failed += _expect(is_equal_approx(float(agg3["melee_damage"]), mote_dmg),
		"pl_sunmote's melee-damage cost survives the aggregate")
	var agg4: Dictionary = _aggregate(["pl_ashplate"])
	failed += _expect(is_equal_approx(float(agg4["damage_reduction"]), 0.15),
		"pl_ashplate grants the flat 15%% mitigation via the key Hero actually reads")

	# -- THE ARMOURY MENU AND THE RIG REGISTRY ARE TWO DIFFERENT LISTS ------------
	# What that split has to survive is a well-meaning tidy-up in either direction, and
	# both directions are silent failures:
	#   * A retired piece creeping back into `PLACEHOLDER_SLOTS` puts a SECOND stat bag
	#     on the menu the maker curated by hand.
	#   * An armoury piece creeping into `GEAR_KINDS` puts it in the registry that drives
	#     the rig's drawable sweep, which is a different question from "is it equippable".
	#
	# /!\ THE "NO ART, SO DRAWABLE WOULD MEAN INVISIBLE" RULING IS DEAD, AND THE MAKER
	# KILLED IT: *"please make mock versions of like helmets and stuff that replace the
	# character head"*. Every worn piece now HAS a silhouette (`CharacterRig.MOCK_HEAD` /
	# `MOCK_BODY` / `LEG_GEAR`), so the assertion is INVERTED rather than deleted — a worn
	# piece MUST draw, or the slot claims to be filled and the body says otherwise.
	var offered: Dictionary = GearAbilities.PLACEHOLDER_SLOTS
	failed += _expect(offered.size() == 4, "the armoury offers four slots (got %d)" % offered.size())
	var swept: int = 0
	for slot3: String in offered:
		var list: Array = offered[slot3]
		failed += _expect(list.size() >= 3, "slot '%s' offers a real menu (got %d)" % [slot3, list.size()])
		for kind3: String in list:
			var a3: Dictionary = GearAbilities.of(kind3)
			var desc3: String = String(a3.get("desc", ""))
			# ── THE PROMISES ARE KEPT: live stats, and no COMING SOON left behind ──
			# ⚠ THE DESCRIPTION CHECK IS NOT COSMETIC. These rows shipped for weeks
			# captioned "COMING SOON — will chill on contact", and a working item still
			# wearing that caption is a worse bug than a broken one: the player reads it,
			# believes the slot does nothing, and never equips a piece that is live.
			failed += _expect(not GearAbilities.is_placeholder(kind3),
				"'%s' is a REAL item now, not a flagged promise" % kind3)
			failed += _expect(not (GearAbilities.effect(kind3) as Dictionary).is_empty(),
				"offered piece '%s' carries live stats - an empty bag is an unpickable item" % kind3)
			failed += _expect(not desc3.contains("COMING SOON"),
				"'%s' no longer advertises itself as unimplemented (desc: '%s')" % [kind3, desc3])
			failed += _expect(String(a3.get("name", "")) != "",
				"'%s' has a name to put on its button" % kind3)
			failed += _expect(desc3 != "", "'%s' has a description to explain itself" % kind3)
			# Inside the stated budget, per axis.
			var eff3: Dictionary = GearAbilities.effect(kind3)
			for ax3: String in BUDGET:
				if not eff3.has(ax3):
					continue
				var v3: float = float(eff3[ax3])
				var lo3: float = float((BUDGET[ax3] as Array)[0])
				var hi3: float = float((BUDGET[ax3] as Array)[1])
				failed += _expect(v3 >= lo3 - 0.0001 and v3 <= hi3 + 0.0001,
					"'%s' %s = %.3f is inside the authored budget %.2f..%.2f"
						% [kind3, ax3, v3, lo3, hi3])
			# Every offered piece pays. NO exemption list here - see the note above.
			failed += _expect(_pays_something(kind3),
				"'%s' is worse than the EMPTY slot somewhere - otherwise equipping it is a chore, not a choice" % kind3)
			failed += _expect(not equip_tex.has(kind3),
				"'%s' is not in GEAR_KINDS - that registry answers a different question" % kind3)
			# A WORN slot must be VISIBLE; a spellement must NOT be. A spellement attaches
			# to a spell, so drawing one would put back the sticker-on-a-stickman that the
			# replacement scheme exists to remove.
			if slot3 == "weapon":
				failed += _expect(not CharacterRig.draws_kind(kind3),
					"spellement '%s' draws NOTHING on the body - it attaches to a spell" % kind3)
			else:
				failed += _expect(CharacterRig.draws_kind(kind3),
					"worn piece '%s' has a silhouette - a filled slot the body does not show is a lie" % kind3)
			swept += 1
	# An invariant that is trivially true of an empty sweep is not an invariant.
	failed += _expect(swept == 19, "all nineteen offered pieces were swept (got %d)" % swept)

	failed += _test_unwired_slots_match_the_hero()

	# ...and the retired catalogue is off the menu, not merely re-ordered on it.
	for retired: String in ["hat", "hood", "helmet", "robe", "armor", "cape", "sword",
			"dagger", "hammer", "greatsword", "staff", "staff_ice", "staff_storm",
			"staff_holy", "scythe", "orb"]:
		for slot4: String in offered:
			failed += _expect(not (offered[slot4] as Array).has(retired),
				"retired piece '%s' is not offered in slot '%s'" % [retired, slot4])
		# ...while its ROW survives, because the rig, the enemy roster and two suites
		# that are not this one read it. Removing the rows is what would break things.
		failed += _expect(GearAbilities.has_ability(retired),
			"retired piece '%s' keeps its registry row (the rig and Enemy read it)" % retired)

	if failed > 0:
		printerr("Gear tests: %d FAILED" % failed)
		quit(1)
	else:
		print("Gear tests: all PASS (%d pieces, %d offered)" % [equip_tex.size(), swept])
		quit(0)
	return true


## ⚠ THE ONE ASSERTION THAT SPANS TWO FILES, AND THE ONLY WAY THE GREAVES STAY HONEST.
##
## `Hero._aggregate_gear` iterates a hard-coded slot list. It reads "weapon"/"head"/
## "body" and NOT "legs", so the three greaves carry fully-designed stats that reach
## nobody. They are flagged `unwired` and the armoury captions them accordingly.
##
## The failure this guards is the flag rotting out of sync with the engine, in EITHER
## direction, and both are silent:
##   * Hero gains "legs" and nobody clears the flags -> three live items are captioned
##     "SLOT NOT LIVE YET" forever, and players skip them.
##   * The flags are cleared as tidy-up while Hero still reads three -> the armoury sells
##     three stat lines that never fire, which is the exact lie this whole change set was
##     about removing.
## So the two are asserted to MOVE TOGETHER. Whoever adds "legs" to Hero's literal will
## be told, by a red suite, to delete the three flags in the same commit.
##
## ⚠ IT REFLECTS OVER `Hero.GEAR_SLOTS` RATHER THAN SCRAPING HERO'S SOURCE TEXT, and the
## change is the fix this assertion was written to force. The list used to be an inline
## array literal repeated inside TWO functions — which is exactly how it came to say
## "weapon"/"head"/"body" in both while `GameState.LOADOUT_SLOTS` had said four for a very
## long time. Scraping was the only channel that could see a literal; now that both loops
## walk one named const, the const is the channel, and reading it is strictly better: it
## cannot be defeated by whitespace, by the literal moving to a third function, or by one
## of the two copies being updated and the other missed.
##
## If the const ever stops being readable this FAILS rather than skipping — a cross-file
## contract that silently stops checking is worse than one that was never written.
func _test_unwired_slots_match_the_hero() -> int:
	var failed: int = 0
	var hero_script: GDScript = load(HERO_PATH) as GDScript
	failed += _expect(hero_script != null, "Hero.gd could be loaded to read its gear slots")
	if hero_script == null:
		return failed
	var consts: Dictionary = hero_script.get_script_constant_map()
	failed += _expect(consts.has("GEAR_SLOTS"),
		"Hero.GEAR_SLOTS exists — both gear loops must walk one named list, not a literal")
	if not consts.has("GEAR_SLOTS"):
		return failed
	var hero_slots: Array = consts["GEAR_SLOTS"]
	var hero_reads_legs: bool = hero_slots.has("legs")

	var unwired: int = 0
	var wired: int = 0
	for slot: String in GearAbilities.PLACEHOLDER_SLOTS:
		# A slot Hero DOES read must carry no unwired flags; a slot it does not read
		# must carry nothing BUT unwired flags.
		var slot_is_live: bool = (slot != "legs") or hero_reads_legs
		for kind: String in (GearAbilities.PLACEHOLDER_SLOTS[slot] as Array):
			var flagged: bool = GearAbilities.is_unwired(kind)
			failed += _expect(flagged != slot_is_live,
				"'%s' (slot '%s'): unwired flag is %s, but Hero %s that slot - the flag and the engine must move together"
					% [kind, slot, str(flagged), "READS" if slot_is_live else "does NOT read"])
			if flagged:
				unwired += 1
			else:
				wired += 1
	# An invariant true of an empty sweep is not an invariant. Exactly one of these is
	# non-zero-by-design at any time; both being counted means the sweep really ran.
	failed += _expect(wired + unwired == 19,
		"every offered piece was checked against Hero's slot loop (got %d)" % (wired + unwired))
	failed += _expect(wired >= 16,
		"the sixteen pieces in slots Hero reads are all live (got %d)" % wired)
	return failed


## `a` dominates `b` iff a is better somewhere and worse nowhere. Sweeps every ordered
## pair inside every slot of `catalogue`.
func _sweep_dominance(catalogue: Dictionary, label: String) -> int:
	var failed: int = 0
	var pairs: int = 0
	for slot: String in catalogue:
		var items: Array = catalogue[slot]
		# ⚠ An invariant that is trivially true of an empty list is not an invariant.
		failed += _expect(items.size() >= 3,
			"%s slot '%s' actually has items to compare (got %d)" % [label, slot, items.size()])
		for a: String in items:
			for b: String in items:
				if a == b:
					continue
				var ea: Dictionary = GearAbilities.effect(a)
				var eb: Dictionary = GearAbilities.effect(b)
				var a_better_anywhere: bool = false
				var b_better_anywhere: bool = false
				for ax: String in AXES:
					var va: float = _axis(ea, ax)
					var vb: float = _axis(eb, ax)
					if is_equal_approx(va, vb):
						continue
					var a_wins: bool = (va < vb) if LOWER_IS_BETTER.has(ax) else (va > vb)
					if a_wins:
						a_better_anywhere = true
					else:
						b_better_anywhere = true
				failed += _expect(not (a_better_anywhere and not b_better_anywhere),
					"[%s] '%s' strictly dominates '%s' in slot '%s' - '%s' is unpickable"
						% [label, a, b, slot, b])
				pairs += 1
	failed += _expect(pairs > 0, "%s dominance sweep actually compared something" % label)
	return failed


## True when `kind` is worse than the EMPTY slot on at least one axis the hero reads.
func _pays_something(kind: String) -> bool:
	var eff: Dictionary = GearAbilities.effect(kind)
	for ax: String in AXES:
		var neutral: float = _neutral(ax)
		var v: float = _axis(eff, ax)
		if is_equal_approx(v, neutral):
			continue
		# Worse than the empty slot on this axis? `melee_cd` inverts.
		if (v > neutral) if LOWER_IS_BETTER.has(ax) else (v < neutral):
			return true
	return false


## The value an absent axis takes: 1.0 for a multiplier, 0.0 for the two additive
## mitigation axes. One definition, so dominance and pricing can never disagree.
func _neutral(axis: String) -> float:
	return 0.0 if ZERO_BASED.has(axis) else 1.0


func _axis(effect: Dictionary, axis: String) -> float:
	return float(effect.get(axis, _neutral(axis)))


func _expect(cond: bool, msg: String) -> int:
	if not cond:
		printerr("FAIL: ", msg)
		return 1
	return 0


## Mirror of Hero._aggregate_gear (element kept as a string here for the assertion).
## ⚠ Takes a KIND LIST rather than a slot dict on purpose: this exercises the COMBINING
## rules (multiply the mults, maxf the mitigations, last element wins), which is the part
## that has bitten before. Hero's slot filtering is asserted separately, against Hero's
## own source, in `_test_unwired_slots_match_the_hero`.
func _aggregate(kinds: Array) -> Dictionary:
	var out: Dictionary = {
		"melee_damage": 1.0, "melee_knockback": 1.0, "melee_cd": 1.0,
		"max_hp": 1.0, "speed": 1.0, "ward": 0.0, "damage_reduction": 0.0, "element": "",
	}
	for kind: String in kinds:
		var e: Dictionary = GearAbilities.effect(kind)
		for k: String in ["melee_damage", "melee_knockback", "melee_cd", "max_hp", "speed"]:
			if e.has(k):
				out[k] *= float(e[k])
		for k: String in ["ward", "damage_reduction"]:
			if e.has(k):
				out[k] = maxf(float(out[k]), float(e[k]))
		if e.has("element"):
			out["element"] = String(e["element"])
	return out
