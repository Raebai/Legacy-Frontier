class_name SpellLibrary
extends RefCounted
## The curated signature spells — the playable slice of the spell tree. Each is a
## SpellDef (pure data); build() returns them in cycle order. Hero equips one at a
## time (cycle with V, unleash with the Ultimate key), MP-gated. This is the code
## home of the tree today; any entry can move to a data/spells/*.tres later
## without touching the caster/loadout/UI (SpellDef is .tres-authorable).
##
## Flavour is the isekai / high-fantasy / divine north-star: giant sigils, screen-
## crossing beams, pillars of holy light. See docs/v2.0-spell-system-design.md
## for the full class / subclass / blend tree these are drawn from.
##
## NAMES ARE OURS. Mechanics are not ownable; named techniques from named works
## are. Nothing in this file borrows a spell name from another property — see the
## IP pass in docs/superpowers/specs/2026-07-27-swordsman-and-signature-ults.md
## §8, and the banned-string guard in tools/slice8_test_spell_kits.gd that stops
## a borrowed name quietly coming back.

## Element indices (Elements.Element): FIRE 0, ICE 1, LIGHTNING 2, SHADOW 3,
## ARCANE 4, EARTH 5, HOLY 6, WIND 7.
##
## EVERY spell declares a real element (never the SpellDef default of -1). Two
## things downstream depend on it and both fail QUIETLY when it is missing:
## SpellCaster.resolve_element() falls back to guessing from the `effect` string
## (and its "holy" arm answers LIGHTNING, a legacy from before HOLY existed as an
## element), and SpellReactor.register() drops an element-less effect out of the
## reaction system entirely. A spell with no element is therefore a spell with the
## wrong ailment AND no reactions — see the effect/element invariant test.


# ---------------------------------------------------------------- class kits
## The four spell slots + the ult slot, in the order they are handed to the hero.
## Slots 0-3 are the four spell slots and hold non-ULT spells; slot 4 is the ult
## slot (SpellTier.slot_accepts_ult). Tier is DERIVED from cast time / cooldown /
## MP, so a kit cannot lie about which shelf a spell sits on — retune a spell past
## the ult thresholds and it stops being legal in slots 0-3, loudly, in the tests.
##
## The keys are ROLES, not flavour. A kit that is four variations of one idea is a
## kit with one answer, so every class fills each role exactly once:
##   damage  — the reliable line you throw all fight
##   control — zoning: a field, a barrier, something that shapes the floor
##   answer  — the get-out: mobility, a gap-close, or a defensive / sustain tool
##   payoff  — the biggest non-ult hit in the kit, the one you set up for
##   ult     — the finisher, and the only slot a screen-crossing beam fits in
const ROLE_ORDER: Array[String] = ["damage", "control", "answer", "payoff", "ult"]

## Per-class kit, indexed by Hero.HeroClass (0 ARCANIST .. 7 WARLOCK).
##
## WHY YOU COULD ONLY EVER SEE ONE OR TWO BEAMS. Two causes stacked:
##
##   1. `_beam()` used to hand every beam the same 1.0 s channel, which is past
##      SpellTier.ULT_CAST_TIME — so all five were ULT-tier and only ONE could be
##      equipped at a time, by anyone, ever.
##   2. Only two of the five had a home in any class kit (the Arcanist's and the
##      Brawler's). `frostpiercer`, `umbral_lance` and `tempest` existed only in
##      build_all(), the review harness — unreachable in real play, while the
##      class-select cards cheerfully advertised all three.
##
## Both are fixed here. The family now spans two shelves — First Lance and
## Frostpiercer are short-channel HEAVYs that live in DAMAGE slots and get thrown
## all fight; Infernal Lance, Umbral Lance and Tempest keep the full channel and
## are their class's ULT. All five are reachable, three of them at once across the
## roster, and the clash ladder finally has a gap to work with: a HEAVY beam is
## STOPPED by an ice wall and CARVES a rock wall, where before every beam breached
## every barrier and every beam-vs-beam was a mutual annihilation.
##
## The non-ult pool is 16 spells across 8 classes x 4 slots, so tools are SHARED
## between classes on purpose (the Brawler and the Stormcaller have always shared
## the Thunderclap). What must stay distinct is the four roles WITHIN a kit. Note
## a spell's role is per-KIT, not a property of the spell: Shadowburst is the
## Arcanist's escape and the Shadowblade's finisher, which is exactly why the
## roles live in this table and not on SpellDef.
##
## TWO THINGS THE POOL CANNOT CURRENTLY GIVE, both content gaps rather than kit
## choices, and both worth fixing with new spells rather than more reshuffling:
##   - MOBILITY is the one role every class needs and Shadowburst is the only pure
##     mobility tool that is not somebody's signature, so it carries four kits.
##   - Rift Dagger stays in the SHADOWBLADE kit ONLY. Not a balance call: it is a
##     two-beat spell (throw, then press again to tear through to the anchor), and
##     `tools/slice_test_summon.gd` reconfigures ONE hero through all eight classes
##     without freeing the anchor between them — so the second class holding it
##     takes the RECALL beat and never starts a summon windup. That is a fixture
##     bug in that test, not a fact about the spell; until it resets the anchor per
##     class, a second kit holding this spell turns that suite red. See the handoff.
##
## ══ THE ANTI-RECOLOUR PASS (this table's current shape) ═══════════════════════
## The maker's ruling: "we cannot have any recolours — I want all the classes to be
## different and unique and not similar at all." What that table actually looked
## like before this pass, counted rather than felt:
##   * FIVE of nine classes carried a `BeamSpell` (the Arcanist's, the Shadowblade's,
##     the Brawler's, the Cryomancer's, the Stormcaller's) — one corridor, five tints.
##   * FOUR ults were the same `MeteorSigil.rain()` call.
##   * Blizzard sat in THREE carried hands; Drain Tether in three.
## So the roster had nine names and roughly four things to look at.
##
## Eleven bespoke spectacles were built to close it (see the factory block further
## down), and the invariant is now pinned mechanically rather than argued in a
## comment: `tools/slice_test_class_identity.gd` fails if any two classes share a
## carried spell id OR if any two carried hands resolve to the same spectacle
## script. `ordinary_spell` is the ONLY beam any class still carries — that is the
## point of it being "the first spell anyone learns".
##
## Three deliberate corrections are baked in and are worth naming, because each one
## was a bug rather than a preference:
##   * THUNDERCLAP LEFT THE BRAWLER. A LIGHTNING lance charged into the fist, on the
##     one class whose card says "pure-melee knockout — no magic". It is the
##     Stormcaller's payoff now, which is where it always belonged.
##   * MIRROR IMAGE WAS PROMOTED out of the Tier 2 floor-pickup pool into the
##     Arcanist's control slot. It is the only self-duplication in the game, which
##     makes it an identity rather than a gimmick. It is REMOVED from `build_tier2()`
##     in the same edit — a spell in both places exists twice and `SpellGrant` would
##     displace it with itself.
##   * AEGIS WARD WAS UN-ORPHANED onto the Cleric. It was in nobody's kit: exactly
##     the unreachable-spell bug this table was introduced to prevent, and the same
##     one the class cards used to advertise. Its cooldown/lifetime were retuned to
##     clear the ULT shelf so it can hold a non-ult slot — see `_aegis_ward()`.
const CLASS_KITS: Array[Dictionary] = [
	# 0 ARCANIST — ranged arcane zoner. First Lance is the damage line it was
	# always described as being. Its control is MIRROR IMAGE: a second caster that
	# repeats what you cast, one beat behind, on nobody's side. Nothing else in the
	# game duplicates you, which is why this is worth a kit slot rather than a drop.
	{"damage": "ordinary_spell", "control": "mirror_image", "answer": "blink_strike",
		"payoff": "rock_pillar", "ult": "meteor_sigil"},
	# 1 SHADOWBLADE — in-and-out assassin. Its ult was `umbral_lance`, a violet copy
	# of the Arcanist's magenta beam: a stationary channelled lance on an assassin.
	# THOUSAND CUTS is the class fantasy instead — mark one body, vanish, open it
	# from every angle. Rift Dagger is the carried get-out; Shadowburst the reserve.
	{"damage": "blade_flurry", "control": "creeping_shade", "answer": "rift_dagger",
		"payoff": "blink_strike", "ult": "thousand_cuts"},
	# 2 BRAWLER — pure melee, and it finally is. Its damage line was a LIGHTNING
	# lance and its ult a fire beam; both are gone. SHOCKWAVE STOMP is a boot into
	# the floor and METEOR FIST is a leap that lands fist-first. The Rock Wall stays
	# its "answer" for the reason no other class gets: the wall's second beat is a
	# PUNCH (the two-beat shove), so a defensive spell doubles as a brawler verb.
	{"damage": "shockwave_stomp", "control": "chain_lightning", "answer": "rock_wall",
		"payoff": "boulder_hurl", "ult": "meteor_fist"},
	# 3 JUGGERNAUT — siege tank. Its ult was the fourth placed bombardment in the
	# tree; FAULT LINE is a rupture that TRAVELS instead, which is the one shape a
	# siege tank should own. It CARRIES the payoff (Rock Pillar) rather than the
	# tether, because the tether is the Warlock's damage line and a tank borrowing
	# the hexer's signature is precisely the recolour this pass exists to delete.
	{"damage": "boulder_hurl", "control": "rock_wall", "answer": "drain_tether",
		"payoff": "rock_pillar", "ult": "fault_line"},
	# 4 CLERIC — radiant lifesteal bruiser, and the only HOLY caster. RADIANT VOLLEY
	# is the maker's "archer" ask: a rack of parallel lances where position, not aim,
	# is the damage dial. Its control is the AEGIS WARD — the game's only protective
	# spell, and previously in nobody's kit at all.
	{"damage": "radiant_volley", "control": "aegis_ward", "answer": "drain_tether",
		"payoff": "chain_lightning", "ult": "heavens_verdict"},
	# 5 CRYOMANCER — ice control. SHATTER replaces the Frostpiercer beam and makes
	# the class's own Blizzard its set-up: 0.35x on a warm body, 3.0x on a frozen
	# one. The field to chill, the charge to cash it in, the Glacial Spine as the ult.
	{"damage": "shatter", "control": "blizzard", "answer": "ice_wall",
		"payoff": "blink_strike", "ult": "frozen_comet"},
	# 6 STORMCALLER — hyper-mobile chain caster. Its ult was Tempest, a beam; it is
	# HEAVEN'S WRATH now, a drifting storm CELL that marks its own targets. And it
	# inherits the THUNDERCLAP as its payoff, off the Brawler, where a lightning
	# lance was flatly contradicting that class's "no magic" card.
	{"damage": "chain_lightning", "control": "blizzard", "answer": "blink_strike",
		"payoff": "thunderclap", "ult": "heavens_wrath"},
	# 7 WARLOCK — dark attrition. RAISE THRALL is the only summon in the game: bare
	# ground gives one thin body, a corpse gives two good ones, so the spell rewards
	# fighting where things have already died. GRAVE TIDE replaces `void_barrage`
	# (the third sky bombardment) with a floor that gives way in both directions.
	{"damage": "drain_tether", "control": "raise_thrall", "answer": "void_zone",
		"payoff": "creeping_shade", "ult": "grave_tide"},
	# 8 SWORDSAINT — the guard-and-punish duelist. Its real defensive verb is not in
	# this table at all: RMB is a held BLADE guard (ParryRing's shrinking ring) that
	# banks what it turns away and returns it as one unsheathe cut. So the kit's job
	# is only to get it INTO range and keep it there.
	#
	#   damage  IAI SLASH — one committed draw-cut at 118 px, a body and a half. It
	#           held `blade_flurry` before, which is the SHADOWBLADE's spell: the
	#           duelist was wearing the assassin's damage line. Whiffing costs five
	#           seconds, and that cost IS the counterplay.
	#   control Rock Wall — a duelist SHAPES the floor rather than zoning with magic:
	#           drop a wall across a ranged class's line and the fight has to happen
	#           where it wants it. Same reasoning as the Brawler's pick.
	#   answer  CRESCENT RUSH — for a duelist the get-out is IN, not out, and this is
	#           the only mobility tool in the tree that CUTS the lane it crossed.
	#           Shadowburst (a teleport with a burst) is a different verb and stays
	#           the Arcanist's / Cryomancer's.
	#   payoff  Boulder Hurl — the only non-magic heavy in the pool; he rips the floor
	#           up and throws it.
	#   ult     HORIZON CUT — the class's authored signature, finally equipped. It is
	#           an `ARC`-kind travelling crescent (`scripts/combat/HorizonArc.gd`) and
	#           the arm for it has existed since the Horizon Cut handoff shipped; this
	#           row is the last step of that handoff, replacing the `judgment`
	#           placeholder that used to hold the slot.
	{"damage": "iai_slash", "control": "rock_wall", "answer": "crescent_step",
		"payoff": "boulder_hurl", "ult": "horizon_cut"},
]


# ------------------------------------------------------------- WHAT YOU HOLD
## WHICH THREE OF A CLASS'S FIVE AUTHORED ROLES IT ACTUALLY CARRIES, in slot order.
##
## The right thumb has THREE buttons. That is the mobile control scheme the spec is
## built around, so three is the number of spells a hand can hold — a fourth entry is
## a spell the player cannot reach.
##
## ⚠ THE OTHER TWO ROLES ARE NOT DELETED, and that is the point of splitting this
## table out rather than cutting `CLASS_KITS` down. `CLASS_KITS` stays the authored
## POOL — five roles per class, every rationale intact — and this says which three of
## them you start with. The two you do not start with are exactly the shape the Tier 2
## floor pickups and Tier 3 boss drops need in a later phase: real, tuned, role-tagged
## spells with a class already attached to them. Trimming the pool instead would have
## thrown that away to save a table.
##
## RULES THIS TABLE MUST OBEY (all pinned by tools/slice8_test_spell_kits.gd):
##   * exactly `SpellTier.SLOT_COUNT` entries per class;
##   * the LAST entry is the ult slot and must hold an ULT-shelf spell;
##   * every earlier entry must hold a NON-ult spell;
##   * a role named here must exist in that class's `CLASS_KITS` row.
##
## HOW THE THREE WERE CHOSEN — the class's fantasy, read off `ClassInfo.CLASSES`,
## rather than a uniform "keep damage/control/ult" rule. Every class keeps its DAMAGE
## line (the thing you throw all fight) and its ULT (the finisher); the middle slot is
## whichever of control / answer / payoff that class's one-line fantasy actually names.
## Zoners keep the field; assassins and duelists keep the way IN; tanks and the cleric
## keep sustain; the brawler keeps the wall whose second beat is a punch.
##
## ⚠ THE MIDDLE SLOT IS ALSO WHERE THE ANTI-RECOLOUR RULE IS WON OR LOST. The damage
## line and the ult are bespoke per class after the signature pass, so the only way
## two classes can still end up looking alike is by carrying the same middle spell.
## Every row below was re-picked with that in mind and the result is pinned by
## `tools/slice_test_class_identity.gd`: all 27 carried ids are distinct, and no two
## carried hands resolve to the same spectacle script.
const SLOT_ROLES: Array[Array] = [
	# 0 ARCANIST — "ranged arcane zoner". Mirror Image is the control pick, not the
	# Blizzard it used to carry: the field is in two other hands and the clone is in
	# nobody's. A second caster repeating your casts one beat behind, on nobody's
	# side, IS a zoning tool — it makes standing anywhere near you a decision.
	["damage", "control", "ult"],
	# 1 SHADOWBLADE — "in-and-out assassin". Rift Dagger is the ANSWER and the carried
	# middle: throw it, then tear yourself through to it. Shadowburst moves to the
	# reserve because two other classes hold it and this class's identity should not
	# be the tool three kits share.
	["damage", "answer", "ult"],
	# 2 BRAWLER — "pure-melee knockout, no magic". Rock Wall is its answer for a reason
	# no other class has: the wall's second beat is a PUNCH, so the defensive spell is
	# also a brawler verb. Nothing else in its kit is as on-fantasy.
	["damage", "answer", "ult"],
	# 3 JUGGERNAUT — "unbreakable siege tank". It carries the PAYOFF (Rock Pillar), not
	# the tether. The tether is the WARLOCK's damage line and the Cleric's sustain
	# already; a third hand holding it is the exact shape of duplication this pass is
	# deleting, and a siege tank erupting the floor under someone is more on-fantasy
	# than a shadow drain anyway. The tether stays authored, in the drop reserve.
	["damage", "payoff", "ult"],
	# 4 CLERIC — "radiant lifesteal bruiser". It carries the AEGIS WARD, the game's only
	# protective spell and previously in nobody's kit at all. That is the fix to a real
	# unreachable-spell bug, and it leaves the tether to the Warlock, whose damage line
	# it is. The lifesteal fantasy is not lost: `CLASS_CONFIG[CLERIC].bolt_heal` means
	# the class's PRIMARY heals, which is where a passive fantasy belongs.
	["damage", "control", "ult"],
	# 5 CRYOMANCER — "ice CONTROL caster". The field is the control tool AND the set-up
	# for its own damage line: Shatter pays 3.0x on a frozen body, so this kit combos
	# with itself. The wall is a stop, a different job, and moves to the pickup pool.
	["damage", "control", "ult"],
	# 6 STORMCALLER — "hyper-mobile chain caster". It carries the PAYOFF now: the
	# Thunderclap, inherited from the Brawler, which is the on-fantasy lightning lance
	# this class should always have had. Blizzard drops to the reserve because the
	# Cryomancer carries it and the self-combo argument that used to hold it here
	# (a LIGHTNING beam through an ICE field) died with Tempest — this class's ult is
	# HEAVEN'S WRATH now, a storm cell, not a beam.
	["damage", "payoff", "ult"],
	# 7 WARLOCK — "dark attrition hexer". Drain to live, RAISE THRALL to hold: the only
	# summon in the game, and the only kit that puts a second body on the floor. Shadow
	# Root moves to the reserve — a root and a thrall are both "hold them there", and
	# the thrall is the one nobody else has.
	["damage", "control", "ult"],
	# 8 SWORDSAINT — "guard-and-punish duelist". Its real defensive verb is not in this
	# table at all (RMB is a held BLADE guard that banks a parry into a cut), so the
	# kit's whole job is getting INTO range: for a duelist the get-out is IN, and
	# Crescent Rush is the only dash in the tree that cuts the lane it crossed.
	["damage", "answer", "ult"],
]


## The role -> spell-id map for a class, or {} for an unknown id. THE FULL AUTHORED
## POOL — all five roles — not the three the class carries. Public so the tests can
## assert the SHAPE of a kit without re-deriving the roles from the built SpellDefs,
## which would only prove the tests and the table agree with each other.
static func kit_for_class(class_id: int) -> Dictionary:
	if class_id < 0 or class_id >= CLASS_KITS.size():
		return {}
	return CLASS_KITS[class_id]


## The AUTHORED three for a class — the table above, untouched by any player choice.
## Falls back to the first `SpellTier.SLOT_COUNT` entries of `ROLE_ORDER` for a class
## with no row, so a new class added to `CLASS_KITS` without a `SLOT_ROLES` row still
## boots with a sane hand instead of nothing.
static func default_slot_roles_for_class(class_id: int) -> Array:
	if class_id < 0 or class_id >= SLOT_ROLES.size():
		return ROLE_ORDER.slice(0, SpellTier.SLOT_COUNT)
	return (SLOT_ROLES[class_id] as Array).duplicate()


# ═════════════════════════════════════════════════════════ CHOOSE YOUR THREE
## THE PLAYER'S PICK, and the whole reason `SLOT_ROLES` was split out from
## `CLASS_KITS` in the first place.
##
## `CLASS_KITS` authors FIVE roles per class. The hand holds THREE. Until now the
## table above decided which three, for everybody, forever — so nine classes shipped
## as nine fixed hands and the class-select screen was a blind cycler with nothing to
## decide. The other two roles were already reachable as Tier 2 / Tier 3 drops
## (`reserve_for_class`), so the substrate for a choice existed and nobody could make
## one.
##
## This is that choice, and it costs no new content: 4 non-ult roles choose 2 = SIX
## hands per class, 54 across the roster, every one of them a real, tuned, already-
## balanced spell in a slot the player picked.
##
## WHY A STATIC AND NOT AN AUTOLOAD. `Hero._configure_class` already funnels every
## hero — local, remote puppet, bot, sparring dummy, headless fixture — through
## `build_for_class`, which asks `slot_roles_for_class`. Answering that question
## differently is therefore the ENTIRE feature: no Hero edit, no HUD edit (`AbilityBar`
## polls the hero, and the hero polls this), no new plumbing. A static on a
## `class_name`d script outlives a `change_scene_to_file`, which is exactly the
## lifetime a lobby choice needs.
##
## ⚠ IT DOES NOT SURVIVE QUITTING THE APP. That needs one field on `GameState` and
## `hydrate_from_state` / `persist_to_state` below — written, tested, and waiting for
## the property to exist. See the handoff note on those two functions.
##
## ⚠ AND IT IS KEYED BY CLASS, WHICH IS A CO-OP CAVEAT. The host builds the joiner's
## puppet by class id, so a puppet is dressed in whatever THIS machine chose for that
## class. Cosmetically wrong on the host's screen if both players run the same class
## with different picks; damage is unaffected (it routes victim-authority). Fixing it
## properly means the pick riding the join handshake, which is `Net`'s to carry.
static var _chosen_roles: Dictionary = {}


## The three roles a class CARRIES, in slot order — the player's pick if they made
## one, else the authored default. This is the single question `build_for_class`
## asks, so it is deliberately cheap: everything is validated at `set_slot_roles`
## time, never here.
static func slot_roles_for_class(class_id: int) -> Array:
	var chosen: Variant = _chosen_roles.get(class_id)
	if chosen is Array and (chosen as Array).size() == SpellTier.SLOT_COUNT:
		return (chosen as Array).duplicate()
	return default_slot_roles_for_class(class_id)


## Has the player overridden this class's hand?
static func has_custom_slot_roles(class_id: int) -> bool:
	return _chosen_roles.has(class_id)


## The ROLE that holds this class's ult — the fixed last slot. Derived from the kit's
## real tiers rather than assumed to be the role literally named "ult", so a class
## whose ult moves house does not silently ship a hand with no finisher.
static func ult_role_for_class(class_id: int) -> String:
	var kit: Dictionary = kit_for_class(class_id)
	if kit.is_empty():
		return "ult"
	var by_id: Dictionary = _spell_by_id()
	for role: String in ROLE_ORDER:
		var s: Variant = by_id.get(String(kit.get(role, "")))
		if s != null and SpellTier.of(s) == SpellTier.Tier.ULT:
			return role
	return "ult"


## The roles a player may CHOOSE BETWEEN for the two open slots: every role in this
## class's kit that resolves to a real, non-ult spell. In `ROLE_ORDER` order so the
## picker never reshuffles under the thumb.
static func choosable_roles_for_class(class_id: int) -> Array:
	var kit: Dictionary = kit_for_class(class_id)
	if kit.is_empty():
		return []
	var by_id: Dictionary = _spell_by_id()
	var out: Array = []
	for role: String in ROLE_ORDER:
		var s: Variant = by_id.get(String(kit.get(role, "")))
		if s != null and SpellTier.of(s) != SpellTier.Tier.ULT:
			out.append(role)
	return out


## The SpellDef a class's role resolves to, or null. Fresh instance (build_all mints
## new Resources every call), so a picker holding one cannot mutate a live hero's kit.
static func spell_for_role(class_id: int, role: String) -> SpellDef:
	var kit: Dictionary = kit_for_class(class_id)
	if kit.is_empty():
		return null
	return _spell_by_id().get(String(kit.get(role, ""))) as SpellDef


## Why `roles` is NOT a legal hand for `class_id`, or "" if it is. The same four rules
## `tools/slice8_test_spell_kits.gd` pins on the authored table, applied to the
## player's pick — so a hand a player can build is a hand the tests would have
## accepted, and an illegal one is refused at the tap rather than discovered as an
## empty button in the middle of floor 3.
static func validate_slot_roles(class_id: int, roles: Array) -> String:
	var kit: Dictionary = kit_for_class(class_id)
	if kit.is_empty():
		return "no kit for class %d" % class_id
	if roles.size() != SpellTier.SLOT_COUNT:
		return "a hand holds exactly %d spells (got %d)" % [SpellTier.SLOT_COUNT, roles.size()]
	var seen: Dictionary = {}
	var by_id: Dictionary = _spell_by_id()
	for i: int in roles.size():
		var role: String = String(roles[i])
		if not kit.has(role):
			return "%s is not a role this class authors" % role
		if seen.has(role):
			return "%s is in the hand twice" % role
		seen[role] = true
		var s: Variant = by_id.get(String(kit.get(role, "")))
		if s == null:
			return "%s resolves to no spell" % role
		var is_ult: bool = SpellTier.of(s) == SpellTier.Tier.ULT
		if SpellTier.slot_accepts_ult(i):
			if not is_ult:
				return "the last slot is the ult slot"
		elif is_ult:
			return "an ult cannot sit in slot %d" % (i + 1)
	return ""


## Set a class's hand. Refuses an illegal one outright (returns false and changes
## nothing) — a half-applied hand is worse than no choice at all.
static func set_slot_roles(class_id: int, roles: Array) -> bool:
	if validate_slot_roles(class_id, roles) != "":
		return false
	var stored: Array = []
	for r: Variant in roles:
		stored.append(String(r))
	_chosen_roles[class_id] = stored
	return true


## Back to the authored hand for one class, or (no argument) for the whole roster.
static func clear_slot_roles(class_id: int = -1) -> void:
	if class_id < 0:
		_chosen_roles.clear()
	else:
		_chosen_roles.erase(class_id)


## ── the save hook, and the one piece of this that is not yet wired ──────────
## `GameState` is where a choice that must outlive the process belongs (it already
## carries `selected_class` and `loadout` for exactly this reason), but adding a field
## to it was out of scope for the change that added this table. Both directions are
## written and covered; both no-op cleanly while the property is absent, and start
## working the moment it exists.
##
## THE WIRING LEFT: `var spell_roles: Dictionary = {}` on `GameState`, saved and
## loaded with `loadout`; then `hydrate_from_state($GameState)` once at boot and
## `persist_to_state($GameState)` after a pick. Nothing else changes.
##
## ⚠ `Object.set()` on an UNDECLARED property is a silent no-op in GDScript, so
## `persist_to_state` proves the property exists by reading it back rather than
## trusting the write — otherwise a missing field reads as a successful save.
const STATE_PROPERTY: StringName = &"spell_roles"


static func hydrate_from_state(state: Object) -> bool:
	if state == null:
		return false
	var raw: Variant = state.get(STATE_PROPERTY)
	if not (raw is Dictionary):
		return false
	var applied: bool = false
	for key: Variant in (raw as Dictionary):
		var roles: Variant = (raw as Dictionary)[key]
		# Keys arrive as floats out of JSON — the standing int/float trap.
		if roles is Array and set_slot_roles(int(key), roles as Array):
			applied = true
	return applied


static func persist_to_state(state: Object) -> bool:
	if state == null:
		return false
	if not (state.get(STATE_PROPERTY) is Dictionary):
		return false   # the field does not exist yet; see the handoff note above
	state.set(STATE_PROPERTY, _chosen_roles.duplicate(true))
	return state.get(STATE_PROPERTY) is Dictionary


## Each class's hand: `SpellTier.SLOT_COUNT` spells in slot order, ult last, so slot
## index is the hero's V-cycle index AND the loadout-bar slot. Fresh instances every
## call. Class ids match Hero.HeroClass; unknown ids fall back to the full cycle so a
## new class never boots spell-less.
static func build_for_class(class_id: int) -> Array:
	var kit: Dictionary = kit_for_class(class_id)
	if kit.is_empty():
		return build()
	var by_id: Dictionary = _spell_by_id()
	var out: Array = []
	for role: String in slot_roles_for_class(class_id):
		var s: Variant = by_id.get(String(kit.get(role, "")))
		# A typo'd id drops that slot rather than crashing the hero mid-configure;
		# the kit test is what turns it into a loud failure at build time.
		if s != null:
			out.append(s)
	return out


## Every spell a class AUTHORS but does not carry — its share of the Tier 2 / Tier 3
## drop pool. Nothing consumes this yet; it exists so the pool is derived from the one
## table rather than hand-listed somewhere else the moment pickups land, which is
## exactly how the class cards drifted out of sync with the kits last time.
static func reserve_for_class(class_id: int) -> Array:
	var kit: Dictionary = kit_for_class(class_id)
	if kit.is_empty():
		return []
	var carried: Array = slot_roles_for_class(class_id)
	var by_id: Dictionary = _spell_by_id()
	var out: Array = []
	for role: String in ROLE_ORDER:
		if carried.has(role):
			continue
		var s: Variant = by_id.get(String(kit.get(role, "")))
		if s != null:
			out.append(s)
	return out


## Every spell in the tree keyed by id. build_all() already mints new SpellDefs on
## every call, so the values here are never shared between two heroes.
static func _spell_by_id() -> Dictionary:
	var out: Dictionary = {}
	for s: SpellDef in build_all():
		out[s.id] = s
	return out


## Build the ordered signature list. Fresh instances each call (Resources are
## reference types — never share mutable state across heroes).
static func build() -> Array:
	return [
		_ordinary_spell(), _frostpiercer(), _infernal_lance(),
		_judgment(), _heavens_verdict(), _meteor_sigil(),
	]


## EVERY named spell in the tree, grouped by kind — for the spell-audit sandbox so
## each one can be reviewed individually. Fresh instances each call.
static func build_all() -> Array:
	return [
		# BEAMS (line lance). Only `ordinary_spell` is still carried by a class; the
		# other four are floor pickups now — see `unequipped_ids()`.
		_ordinary_spell(), _frostpiercer(), _infernal_lance(), _umbral_lance(), _tempest(),
		# RUSH / CHAIN (lightning lances)
		_thunderclap(), _chain_lightning(),
		# DIVINE RAY / PILLAR (single-point smite)
		_judgment(), _colossus_pillar(), _rock_pillar(),
		# CONVERGENCE (radial finisher)
		_heavens_verdict(),
		# ARC (travelling crescent wall)
		_horizon_cut(),
		# METEOR (bombardment)
		_meteor_sigil(), _void_barrage(), _avalanche(), _frozen_comet(),
		# MISSILES / BOULDER (projectiles)
		_rune_orbs(), _boulder_hurl(),
		# BLINK / FLURRY (melee bursts)
		_blink_strike(), _blade_flurry(),
		# ZONE / TETHER (fields + drain)
		_void_zone(), _blizzard(), _drain_tether(),
		# WALLS (barriers)
		_rock_wall(), _ice_wall(), _aegis_ward(),
		# NEW DELIVERY SHAPES (floor traveller + thrown anchor)
		_creeping_shade(), _rift_dagger(),
		# THE ANTI-RECOLOUR SIGNATURES — eleven bespoke spectacles, one carried by
		# each of the nine classes (the Brawler, the Swordsaint and the Warlock carry
		# two each). All `Kind.HEX`, forked on id in `SpellCaster.HEX_SCRIPTS`.
		_thousand_cuts(), _iai_slash(), _crescent_step(), _shockwave_stomp(),
		_meteor_fist(), _radiant_volley(), _shatter(), _heavens_wrath(),
		_fault_line(), _raise_thrall(), _grave_tide(),
		# MIRROR IMAGE — was a Tier 2 drop; PROMOTED into the Arcanist's control slot
		# and moved out of `build_tier2()` in the same edit, so it is listed here
		# explicitly rather than arriving via the drop block below.
		_mirror_image(),
		# THE DROP ECONOMY — never in a class kit, only ever picked up. Included
		# here so the audit sandbox can review them and so the element/effect
		# invariant test covers them like everything else.
	] + build_tier2() + build_tier3()


## Any spell in the tree by id, or null. The public form of `_spell_by_id`, added
## because `drop_by_id` is no longer a complete lookup for anything that USED to be a
## drop: Mirror Image was promoted into the Arcanist's kit, so a caller that reached
## it through the drop table now gets null. Fresh instance, like everything else here.
static func by_id(id: String) -> SpellDef:
	if id == "":
		return null
	return _spell_by_id().get(id) as SpellDef


## EVERY SPELL IN THE TREE THAT NO CLASS AUTHORS — the orphans.
##
## ⚠ THIS IS THE "NOTHING IS UNREACHABLE" DERIVATION, and it exists because the
## anti-recolour pass displaced seven fully-tuned spells out of `CLASS_KITS`
## (`frostpiercer`, `infernal_lance`, `umbral_lance`, `tempest`, `colossus_pillar`,
## `rune_orbs`, `void_barrage`) and deleting them would have thrown away real content
## to save a table. It also catches the TWO THAT WERE ALREADY ORPHANED before this
## pass and that nobody had noticed — `judgment` and `avalanche` — which is the exact
## class of bug the kit table was introduced to prevent and which had quietly come
## back anyway.
##
## Where they go: `SpellDrops._common_pool()` unions this with `reserve_for_class`,
## so an orphan is a TIER 2 FLOOR PICKUP in the common band. Deliberately the common
## band and NOT `build_tier2()`, which is the six authored SIGNATURE drops and carries
## its own balance invariants — "at most two Tier 2s sit on the ULT shelf" (a floor
## pickup must lose a clash to a class ult) and "every drop has a >= 0.35 s wind-up".
## Five of the seven orphans are ULT-shelf and `rune_orbs` has no cast time at all, so
## putting them on the signature shelf would have meant widening two real balance
## rules to accommodate bookkeeping. The common band is where "a genuine upgrade, not
## an event" already lives, which is exactly what a displaced class spell is.
##
## Derived, never hand-listed — the drop table drifting out of sync with the kits is
## the specific failure this whole file's header is about.
static func unequipped_ids() -> Array[String]:
	var authored: Dictionary = {}
	for kit: Dictionary in CLASS_KITS:
		for role: String in ROLE_ORDER:
			authored[String(kit.get(role, ""))] = true
	var drops: Dictionary = {}
	for id: String in drop_ids():
		drops[id] = true
	var out: Array[String] = []
	for s: SpellDef in build_all():
		if authored.has(s.id) or drops.has(s.id) or out.has(s.id):
			continue
		out.append(s.id)
	out.sort()   # deterministic across peers — the drop roll must agree on both screens
	return out


# ================================================================ THE DROP ECONOMY
## TIER 2 (floor pickups) and TIER 3 (boss drops). Read the header of
## `SpellDrops.gd` for how scarce each of these is and why scarcity is the whole
## balance model; this file only says what they DO.
##
## ⚠ NONE OF THESE MAY EVER ENTER `CLASS_KITS`. That is the spec's one hard rule
## about them — "never in the starting kit" — and it is pinned by
## `tools/slice_test_drops.gd`, which fails if any drop id is reachable from
## `build_for_class` on any class.
##
## SHELF / CLASH WEIGHT IS CHOSEN, NOT INHERITED. `SpellTier.of()` derives the shelf
## from cast time / cooldown / MP and that shelf IS the reaction weight, so these
## numbers decide what happens when a drop meets a spell head-on:
##   * Tier 2 mostly lands on HEAVY — it trades with a class HEAVY and LOSES to a
##     class ULT. A floor pickup is not supposed to win clashes; it is supposed to
##     be an EVENT. Meteor Storm is the deliberate exception (a 1.2 s channelled
##     bombardment is an ult by every measure the derivation uses, and pretending
##     otherwise would be the kind of lie the derivation exists to prevent).
##   * Tier 3 is ULT on every axis, so a boss drop eats anything below it.
## There is deliberately NO fourth shelf. Appending one to `SpellTier.Tier` would
## be legal (only the ORDER is load-bearing) but `Juice.tier_frame` and friends
## `match` on the three that exist and would silently draw nothing for a fourth —
## in files owned elsewhere.


## The authored Tier 2 SIGNATURE pickups, fresh instances (Resources are reference
## types). FIVE, not six: `mirror_image` was promoted into the Arcanist's control
## slot by the anti-recolour pass and a spell cannot be in both places — it would be
## rollable as a drop for the class that already starts with it, which makes
## `SpellGrant` displace a spell with itself. See `CLASS_KITS`.
##
## ⚠ THIS IS THE SIGNATURE BAND, NOT THE WHOLE TIER 2 POOL. The pool a floor actually
## rolls from is this plus `SpellDrops._common_pool()` (the class reserve + the
## orphans from `unequipped_ids()`). The distinction is load-bearing: the balance
## invariants in `tools/slice_test_tier_spells.gd` — at most two ULT shelves, a
## visible wind-up on every entry — are claims about THESE, the loud events, not
## about every spell that can ever be found on a floor.
static func build_tier2() -> Array:
	return [_arc_of_fools(), _meteor_storm(), _petrify(), _gravity_flip(),
		_blood_pact()]


## The four Tier 3 boss drops, fresh instances. Every one of them carries CHARGES.
static func build_tier3() -> Array:
	return [_the_void(), _chronostasis(), _equinox(), _roulette()]


## Every drop id, for the "no drop is ever in a starting kit" guard and for the
## pickup entity's label lookup. Order matches build_tier2() + build_tier3().
static func drop_ids() -> Array[String]:
	var out: Array[String] = []
	for s: SpellDef in (build_tier2() + build_tier3()):
		out.append(s.id)
	return out


## Look a drop up by id, or null. Used by the pickup entity (which persists an id,
## never a SpellDef — a Resource on a scene is shared mutable state) and by handoff.
static func drop_by_id(id: String) -> SpellDef:
	for s: SpellDef in (build_tier2() + build_tier3()):
		if s.id == id:
			return s
	return null


# ------------------------------------------------------------------- TIER 2

## ARC OF FOOLS — the spec's Chain Lightning. REUSED, NOT REBUILT: same
## `SpellDef.Kind.CHAIN`, same `ChainBolt` spectacle, retuned to a floor-pickup
## shelf (six links instead of five, 300 px hop range instead of 240, 62 damage
## instead of 46, on a 6 s cooldown instead of 3).
##
## ⚠ THE HONEST VERSION OF "IT ARCS TO YOUR TEAMMATE, ALWAYS". It does not
## literally seek your friend — `ChainBolt.build_chain` hops to the NEAREST
## unvisited body in the shared `mortal` group, and under friendly fire your
## teammate is in that group. In a two-player fight standing anywhere near each
## other, the nearest body to whatever you just hit is very often them. So the
## spec's promise lands as a consequence of the hop rule rather than as a special
## case, and the description says the true thing rather than the tidy thing. The
## widened 300 px hop range is what makes it reliable enough to read as a rule.
static func _arc_of_fools() -> SpellDef:
	var s := SpellDef.new()
	s.id = "arc_of_fools"
	s.display_name = "Arc of Fools"
	s.description = "A bolt that will not be told whose side it is on. It leaps "\
		+ "six times to whatever body is nearest — and in a crowded room the "\
		+ "nearest body is usually the one you came in with."
	s.kind = SpellDef.Kind.CHAIN
	s.element = Elements.Element.LIGHTNING
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.LIGHTNING)
	s.mp_cost = 58
	s.cooldown = 6.0
	s.damage = 62
	s.count = 6        # hops
	s.reach = 300.0    # hop range — wider than the class chain's 240
	s.cast_time = 0.5  # HEAVY: a real tell, not an instant
	return s


## METEOR STORM — the spec's Meteor. REUSED, NOT REBUILT: `SpellDef.Kind.METEOR`
## and the existing `MeteorSigil` spectacle, retuned from the Arcanist's 11-rock
## 140 px ult into a 16-rock 210 px floor-shaker with a 1.2 s channel.
##
## The spec asks for "long telegraph, large radius, escapable if they notice", and
## all three are one number each: cast_time is the channel you can see across the
## room, radius is the footprint, and `MeteorSigil` staggers its rocks over the
## fall so standing at the edge and walking out is a real answer.
static func _meteor_storm() -> SpellDef:
	var s := _meteor("meteor_storm", "Meteor Storm",
		"A sigil the width of the room opens overhead and the sky comes down in "\
		+ "pieces. You will hear it start. Whether you move is up to you.",
		Elements.Element.FIRE, 78, 9.0, 30, 210.0, 16)
	s.reach = 340.0
	s.cast_time = 1.2  # ULT shelf, deliberately — see the section header
	return s


## PETRIFY — turn a body to stone, then throw it. The spec's "turns a mob into a
## throwable statue — works on teammates", and the second half is the whole joke:
## the spell scans the shared `mortal` group like everything else, so your friend
## is a perfectly good rock.
##
## `radius` is the catch footprint at the aimed point; `length` is how long the
## stone lasts if nobody touches it. Damage is 0 ON THE CAST — a statue takes no
## damage while it is stone (`Petrify.gd` swallows it) and the whole payout is
## `Petrify.THROW_DAMAGE` when someone hits it hard enough to launch it.
static func _petrify() -> SpellDef:
	var s := SpellDef.new()
	s.id = "petrify"
	s.display_name = "Petrify"
	s.description = "Stone crawls up the first thing it reaches and stops it "\
		+ "mid-stride. It cannot be hurt while it is a statue. It can be THROWN."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.EARTH)
	s.mp_cost = 60
	s.cooldown = 6.5
	s.damage = 0       # the payout is the THROW, not the casting
	s.radius = 92.0    # catch footprint
	s.reach = 300.0
	s.length = 4.5     # how long the stone holds
	s.cast_time = 0.55
	return s


## GRAVITY FLIP — invert gravity for everyone, caster included. The spec is
## explicit about the last three words and they are the entire design: this is not
## a debuff you aim, it is a rule you change, and you are standing inside it.
##
## `length` is the duration. There is no `radius` because there is no edge —
## reaching for the arena wall to get out from under it would make this a zone,
## and a zone is a completely different (and much safer) spell.
static func _gravity_flip() -> SpellDef:
	var s := SpellDef.new()
	s.id = "gravity_flip"
	s.display_name = "Gravity Flip"
	s.description = "Up stops meaning up. Everything with feet leaves the floor — "\
		+ "yours included — until it wears off and the room comes down at once."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.WIND
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.WIND)
	s.mp_cost = 62
	s.cooldown = 6.8
	s.damage = 0
	s.length = 5.0     # seconds inverted — the spec's number
	s.cast_time = 0.45
	return s


## BLOOD PACT — a damage buff that bills you in HP. The spec's shape exactly: the
## cost is not MP and not a cooldown, it is the resource you need to survive.
##
## `radius` carries the MULTIPLIER (1.75x) and `count` the HP DRAINED PER SECOND,
## which is the field-doubling this codebase already does everywhere (ZONE reuses
## `length` as a lifetime, THROWN_ANCHOR reuses it as an anchor timer). Both are
## read in exactly one place, `BloodPact.gd`, and named there.
##
## ⚠ IT BUFFS SPELLS, NOT PUNCHES. The multiplier is applied in `SpellCaster.cast`,
## which is the one seam every spell goes through and the only one this agent owns.
## Melee damage lives on Hero and is untouched. That is a real limitation, not a
## design choice, and it is written on the spell: "everything you CAST".
static func _blood_pact() -> SpellDef:
	var s := SpellDef.new()
	s.id = "blood_pact"
	s.display_name = "Blood Pact"
	s.description = "Open a vein and everything you CAST hits far harder for a "\
		+ "while. The bleeding does not stop because the fight is going badly."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.SHADOW)
	s.mp_cost = 34          # cheap in MP on purpose — the price is paid in blood
	s.cooldown = 12.0
	s.damage = 0
	s.length = 8.0          # seconds of pact
	s.radius = 1.75         # OUTGOING SPELL DAMAGE MULTIPLIER (see BloodPact.gd)
	s.count = 5             # HP drained per second
	s.cast_time = 0.4
	return s


## MIRROR IMAGE — a clone that repeats your casts on a delay, WITH friendly fire.
##
## ⚠ NO LONGER A DROP. It is the ARCANIST'S CONTROL SLOT (`CLASS_KITS[0]`), promoted
## out of `build_tier2()` by the anti-recolour pass: it is the only self-duplication
## in the game, which makes it an identity rather than a floor event, and the
## Arcanist's old control pick (Blizzard) was a spell two other classes carried. It
## still lives in `SpellCaster.HEX_SCRIPTS` — that registry is keyed by id and has
## never cared whether an id is a drop — but `SpellLibrary.drop_by_id("mirror_image")`
## now correctly answers NULL. Use `SpellLibrary.by_id()` for a whole-tree lookup.
##
## THE IMPLEMENTATION IS NOT INPUT RECORDING, and the difference matters. Reading
## the hero's input would need a hook inside `Hero.gd`; instead the clone listens
## at `SpellCaster.cast()` — the one seam every spell in the game already passes
## through — and re-casts what it heard, `reach` seconds later, from where the
## clone is standing. So it mimics the thing the player actually did rather than
## an approximation of the buttons they pressed, it works for bots and future
## co-op peers for free, and it needs no edit to a file this agent does not own.
##
## `length` is the clone's lifetime, `reach` its echo delay in seconds.
static func _mirror_image() -> SpellDef:
	var s := SpellDef.new()
	s.id = "mirror_image"
	s.display_name = "Mirror Image"
	s.description = "A second you, one beat behind, casting everything you cast "\
		+ "from where it happens to be standing. It is not on anybody's side."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.ARCANE)
	s.mp_cost = 66
	s.cooldown = 6.9
	s.damage = 0
	s.length = 9.0     # clone lifetime
	s.reach = 1.0      # echo delay, seconds
	s.cast_time = 0.6
	return s


# ------------------------------------------------------------------- TIER 3
## All four are ULT on every axis of `SpellTier.of()` — a long channel, a long
## cooldown and a high MP cost — so a boss drop outweighs everything in the game
## in a clash. All four carry CHARGES, so the cooldown is the SECOND limit and the
## charge count is the first. When the last charge is spent the drop evaporates and
## your class ult comes back (see `SpellGrant.consume_charge`).

## THE VOID — a collapsing singularity that deletes what is inside it, allies
## included. The plainest of the four, and deliberately so: it is the one you can
## explain to somebody in one sentence, which is what makes the other three feel
## like gambles by comparison.
static func _the_void() -> SpellDef:
	var s := SpellDef.new()
	s.id = "the_void"
	s.display_name = "The Void"
	s.description = "A point of nothing opens where you mark, drags the room "\
		+ "into itself, and closes. Whatever it closed on is not there any more."
	s.kind = SpellDef.Kind.CATACLYSM
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.SHADOW)
	s.mp_cost = 90
	s.cooldown = 24.0
	s.damage = 260
	s.radius = 185.0
	s.reach = 320.0
	s.cast_time = 1.5
	s.charges = 1
	return s


## CHRONOSTASIS — freeze a radius for 3 s; everything dealt to a frozen body is
## BANKED and lands at once when time restarts. Your teammate is frozen too, which
## is the decision: the freeze is also a 3 s immunity, so catching your friend in
## it either saves them or wastes the only window you had.
##
## `length` is the freeze duration; `radius` the footprint.
static func _chronostasis() -> SpellDef:
	var s := SpellDef.new()
	s.id = "chronostasis"
	s.display_name = "Chronostasis"
	s.description = "Three seconds stop inside the ring. Nothing moves, nothing "\
		+ "lands — and then all of it lands in the same instant. Your friend "\
		+ "is in there too."
	s.kind = SpellDef.Kind.CATACLYSM
	s.element = Elements.Element.ICE
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.ICE)
	s.mp_cost = 90
	s.cooldown = 26.0
	s.damage = 0       # the banked total IS the damage
	s.radius = 235.0
	s.reach = 300.0
	s.length = 3.0     # the spec's three seconds
	s.cast_time = 1.4
	s.charges = 1
	return s


## EQUINOX — THE SWAP FOR REWIND. Every living thing in the room, friend and foe,
## is dragged to the SAME share of its own health. The full verdict is in this
## agent's report and in `tools/rewind_spike.gd`; the short version is that a
## 4-second state rewind across two peers is not a spell, it is a netcode
## architecture, and half of one is worse than none.
##
## It keeps everything Rewind was FOR. It is catastrophic (it can hand a guardian
## a third of its bar back). It is decision-shaped (cast it dying and you live;
## cast it while your teammate is healthy and you have just mugged them). And it
## can absolutely lose you the floor. What it is not is a time machine.
##
## Mechanically it is the cleanest of the four in co-op, which is the other half of
## why it won: it moves HP and nothing else, and HP already has an
## authority-correct route in this codebase.
static func _equinox() -> SpellDef:
	var s := SpellDef.new()
	s.id = "equinox"
	s.display_name = "Equinox"
	s.description = "The scales come level. Every living thing in the room — you, "\
		+ "your friend, the thing you are fighting — is dragged to the same "\
		+ "fraction of itself. Somebody always loses by it."
	s.kind = SpellDef.Kind.CATACLYSM
	s.element = Elements.Element.HOLY
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.HOLY)
	s.mp_cost = 88
	s.cooldown = 24.0
	s.damage = 0       # it moves HP toward a mean; it does not deal damage
	s.radius = 900.0   # the whole room — there is no standing outside it
	s.cast_time = 1.6
	s.charges = 1
	return s


## ROULETTE — one of the other three, chosen at random, and sometimes centred on
## YOU instead of on your aim. Two charges, because a gamble you take once is a
## decision and a gamble you take twice is a habit.
static func _roulette() -> SpellDef:
	var s := SpellDef.new()
	s.id = "roulette"
	s.display_name = "Roulette"
	s.description = "One of the great workings, and you do not get to say which. "\
		+ "Sometimes it does not open where you pointed. It opens on you."
	s.kind = SpellDef.Kind.CATACLYSM
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.ARCANE)
	s.mp_cost = 70
	s.cooldown = 18.0
	s.damage = 0       # inherited from whatever it rolls
	s.radius = 200.0
	s.reach = 300.0
	s.cast_time = 1.0
	s.charges = 2
	return s


# ------------------------------------------------------------- named signatures
## ══ THE DISPLAY-NAME PASS, AND THE ONE THING IT DID NOT TOUCH ════════════════
## Maker's ruling: "the ordinary is an awful name, change that — and this, I mean
## for all classes, no need for step or cast." Three display names moved for it.
##
## ⚠ ONLY `display_name` MOVED. Every `id` in this file is byte-identical across
## that pass, and that is the whole safety argument for doing it in one edit: an id
## is the currency everywhere else in the game — `SpellCaster.HEX_SCRIPTS` forks on
## it, `CLASS_KITS` / `SLOT_ROLES` address spells by it, `SpellGrant` and the pickup
## entity PERSIST it, and the drop tables are derived from it. A display name is
## read by the HUD and the class cards and by nothing that makes a decision. So
## renaming an id to match a nicer label would have been the same edit across nine
## files plus a save-compat break, bought for a cosmetic win.
##
## The three, and why each was filler rather than a name: `ordinary_spell` (the
## maker's "awful name"), plus `blink_strike` and `crescent_step`, which both wore
## "Step" as a trailing noun. "Step" named the MECHANIC, not the spell, which is
## what makes a name fail the bar this game is held to — it has to read at a glance
## on a hotbar, and a word that four other spells could equally have worn reads as
## nothing at all.
##
## "Cast" was swept for in the same pass and appears in NO display name in this
## file, so nothing was owed there. Recorded because a later reader finding no
## "Cast" should know it was checked, not overlooked.


## FIRST LANCE — Arcanist's damage line. TWO renames, and they are separate events.
## The IP pass took it off a name borrowed from another work (that string is
## deliberately still not written here — the sweep in slice8_test_spell_kits.gd
## scans this file's SOURCE, comments included, precisely so a borrowed name cannot
## creep back in as an explanation of itself). This pass takes it off the
## placeholder that rename left behind. The FANTASY survives both untouched and is
## not anyone's property: the most basic offensive magic there is, practised until
## it is the only one you need.
##
## WHY "FIRST" AND NOT A GRANDER WORD. The identity IS that it is the one you learn
## first and never stop throwing, so the adjective carries the idea and the family
## noun says what it does — the same shape as its two shelf-mates, Infernal Lance
## and Umbral Lance, which is honest because all three are the one `Kind.BEAM`
## corridor.
##
## It also retires a HUD bug rather than dodging it. The old name led with an
## ARTICLE; `Hero._signature_hud_slot` shortens with `split(" ")[0]`; so the maker's
## signature beam has been labelled "The" on the hotbar, and `AbilityBar` carries a
## whole repair path for that one string. "First Lance" shortens to "First" under
## the naive rule AND under `AbilityBar.short_spell_name`, so the two agree without
## the repair needing to fire at all.
##
## Rejected: "Arcane Bolt" — `ClassInfo.CLASSES[ARCANIST]` already calls this class's
## LMB primary an "arcane bolt", so the card would advertise one name for two
## different buttons. "Mana Lance" names the resource instead of the idea.
##
## The IP rename also fixed a shelf that disagreed with the fantasy. At cast_time 1.0
## this was an ULT — a "basic spell" you could throw once a fight — so it is the
## short-channel HEAVY of the beam family and sits in the Arcanist's DAMAGE slot,
## which is what "the last one you need" is supposed to mean.
static func _ordinary_spell() -> SpellDef:
	return _beam("ordinary_spell", "First Lance",
		"The first spell anyone learns, practised until it is the last one you "
		+ "need. A sigil blooms and a lance of mana crosses the whole arena.",
		# 78 -> 88 in the DPS-floor pass; same reason as the Meteor Sigil above.
		4, 45, 3.2, 88, 1150.0, 30.0, 0.55)       # ARCANE / magenta — HEAVY


## FROSTPIERCER — Cryomancer. The thinnest, longest, cheapest beam in the family,
## so it is the other HEAVY: a precision poke you throw all fight, not a finisher.
static func _frostpiercer() -> SpellDef:
	return _beam("frostpiercer", "Frostpiercer",
		"A long, thin spear of absolute cold — pierces a whole rank in a line.",
		1, 40, 3.0, 58, 1250.0, 22.0, 0.5)        # ICE / cyan — HEAVY


## INFERNAL LANCE — Brawler's ult. The fattest, hardest-hitting beam (width 42),
## so it keeps the full 1.0 s channel and stays ULT: it out-weighs both HEAVY
## beams in a head-on clash instead of trading with them.
static func _infernal_lance() -> SpellDef:
	return _beam("infernal_lance", "Infernal Lance",
		"A fat, roaring beam of fire. Shorter reach, brutal width.",
		0, 55, 4.0, 74, 900.0, 42.0)              # FIRE / orange — ULT


## JUDGMENT — a single holy pillar. `_ray()` leaves `element` at the SpellDef
## default of -1, which was NOT harmless: SpellCaster.resolve_element() then guesses
## from effect=="holy" and answers LIGHTNING (a fallback from before HOLY existed
## as an element), so a pillar of holy light was applying a Shock, opposing EARTH
## instead of SHADOW, and failing the `elements_a: [FIRE, HOLY]` predicate on
## ReactionTable's own shatter_ice_barrier row. Declared explicitly, exactly as
## _colossus_pillar() already declares EARTH. The gold tint is unaffected —
## `_ray()` sets use_element_color = false, so `color` still wins the visual.
## HORIZON CUT — Swordsaint ult. A crescent wall of edge that widens as it travels
## and cuts at the HEIGHT you aimed at. Deflectable: a turned cut comes back.
##
## THREE SEPARATE DODGE WINDOWS, stacked, which is why it can hit this hard: the
## 1.25 s channel, then ~1.4 s of visible approach as it crosses the arena, then
## the height band itself — it cuts where you aimed, so ducking or jumping the band
## beats it outright. `length` is a travel BUDGET, not a range clamp, and `reach` is
## the half-height at full extension rather than a cast range; SpellCaster's ARC arm
## documents why it must not clamp them the way the placed bombardments do.
static func _horizon_cut() -> SpellDef:
	var s := SpellDef.new()
	s.id = "horizon_cut"
	s.display_name = "Horizon Cut"
	s.description = "Draw the blade slowly and a crescent leaves the sheath with "\
		+ "it — a curved wall of edge that widens as it crosses the arena and cuts "\
		+ "everything at the height you chose. Duck it, or be somewhere else."
	s.kind = SpellDef.Kind.ARC
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = "arcane"
	s.mp_cost = 78
	s.cooldown = 6.5
	s.damage = 110
	s.cast_time = 1.25   # channel tier — the first of its three dodge windows
	s.length = 900.0     # travel budget (px)
	s.width = 30.0       # thickness ALONG travel = the whole damaging depth
	s.radius = 90.0      # half-height at launch
	s.reach = 300.0      # half-height at full extension
	return s


static func _judgment() -> SpellDef:
	var s := _ray("judgment", "Judgment · Divine Ray",
		"A seal opens in the heavens and a SINGLE pillar of holy light smites the "
		+ "exact ground you mark. Precise, punishing — dodge the tell or take the hit.",
		Color(1.0, 0.92, 0.55), 40, 2.6, 95, 70.0)
	s.element = Elements.Element.HOLY  # Radiance burn, and opposes SHADOW
	return s


## HEAVEN'S VERDICT — Cleric's ult. Same missing-element bug as Judgment, with an
## extra bite: StarConvergence gates its ailment on `element_id >= 0`, so the
## biggest spell in the tree was landing 130 damage and applying NOTHING.
static func _heavens_verdict() -> SpellDef:
	var s := _convergence("heavens_verdict", "Heaven's Verdict",
		"The sky closes in a ring of radiant lances that slam together as one "
		+ "cataclysmic nova. The longest telegraph in the tree — and the hardest-hitting.",
		Color(1.0, 0.86, 0.4), 85, 7.0, 130, 160.0)
	s.element = Elements.Element.HOLY
	return s


static func _meteor_sigil() -> SpellDef:
	return _meteor("meteor_sigil", "Meteor Sigil",
		"A colossal sigil opens in the sky and a barrage of meteors rains over "
		+ "the marked ground. The isekai bombardment.",
		# 30 -> 36 per meteor in the DPS-floor pass: the Arcanist traded a damaging
		# control slot (Blizzard) for Mirror Image, which deals nothing directly.
		0, 72, 6.0, 36, 140.0, 11)                # FIRE / orange, 11 meteors


## THUNDERCLAP — the Brawler's lightning lance, and the Stormcaller's payoff. A
## jagged bolt rips down the aim from a charged fist.
##
## Renamed in the IP pass: the id was a named technique from a named work. Ids are
## checked (nothing persists spell ids — GameState saves the class and the gear
## slots, never a spell) so this one was safe to change outright rather than
## leaving a borrowed string load-bearing. `tools/lightning_agent_capture.gd`
## looks this up by id and needs the same edit; it is a throwaway capture tool
## owned elsewhere — see the handoff notes.
static func _thunderclap() -> SpellDef:
	var s := SpellDef.new()
	s.id = "thunderclap"
	s.display_name = "Thunderclap"
	s.description = "Charge lightning into the fist, then RIP a jagged lance down "\
		+ "the aim — everything on the line is shocked and thrown, and the bolt forks to a straggler."
	s.kind = SpellDef.Kind.RUSH
	s.element = Elements.Element.LIGHTNING
	s.use_element_color = true
	s.effect = "lightning"
	s.mp_cost = 50
	s.cooldown = 3.4
	s.damage = 90
	s.length = 620.0
	s.width = 26.0
	return s


## UMBRAL LANCE — Shadowblade's ult. Kept on the full 1.0 s channel (ULT): it is
## the class's only ranged threat, so it has to be the one that wins the clash.
static func _umbral_lance() -> SpellDef:
	return _beam("umbral_lance", "Umbral Lance",
		"A lance of condensed shadow — pierces a line and leaves the struck WEAKENED.",
		Elements.Element.SHADOW, 46, 3.4, 50, 1100.0, 30.0)   # ULT


## VOID BARRAGE — Warlock / Shadowblade. A shadow meteor bombardment (Unstable pops).
static func _void_barrage() -> SpellDef:
	return _meteor("void_barrage", "Void Barrage",
		"A rift tears open and a rain of collapsing void-shards hammers the marked ground.",
		Elements.Element.SHADOW, 70, 6.2, 22, 135.0, 11)


## COLOSSUS PILLAR — Juggernaut. A titanic stone spire slams the marked spot (Stagger).
static func _colossus_pillar() -> SpellDef:
	var s := _ray("colossus_pillar", "Colossus Pillar",
		"The earth answers: a titanic stone spire erupts on the marked ground, "
		+ "staggering everything caught beneath it.",
		Elements.color(Elements.Element.EARTH), 42, 2.8, 96, 74.0)
	s.element = Elements.Element.EARTH  # Stagger ailment (not the holy default)
	# ...and the SPECTACLE must be stone too. `_ray()` hardcodes effect="holy" for
	# Judgment's sake, which this spell was silently inheriting — so a "titanic
	# stone spire" rendered as a holy light column wearing an earth-brown tint.
	s.effect = "earth"
	return s


## AVALANCHE — Juggernaut. An earth meteor bombardment (falling boulders, Stagger).
static func _avalanche() -> SpellDef:
	return _meteor("avalanche", "Avalanche",
		"A cliff-face of boulders rains down over the marked ground.",
		Elements.Element.EARTH, 72, 6.4, 22, 145.0, 11)


## TEMPEST — Stormcaller's ult. Full channel (ULT) because its kit is built to set
## it up: fire it through the Blizzard in the same kit's control slot and
## ReactionTable's `supercharge` row (LIGHTNING beam x ICE field) fires.
static func _tempest() -> SpellDef:
	return _beam("tempest", "Tempest",
		"A screaming beam of raw storm — everything on the line is shocked.",
		Elements.Element.LIGHTNING, 48, 3.2, 66, 1200.0, 28.0)   # ULT


## GLACIAL SPINE — Cryomancer. A crest of ice that erupts from the FLOOR at the
## aimed point and races outward along it (Chill → Freeze). Was "Frozen Comet",
## the fourth of four identical sky bombardments; the maker's playtest verdict
## was that the frost family "reads as more an AoE spell — I don't think it would
## be used much, let's change it so it's not just a random zone of frost". So it
## stopped being an area you drop and became a line you have to JUMP.
##
## AIM, NOT AUTO-AIM. The intended play is "aim at their feet and the spine comes
## up under them", but the spell never looks for a target: it erupts wherever the
## player pointed, and on empty ground if that is where they pointed. IceSpikeLine
## has the long version of this note — it is exactly the distinction a future
## reader will get wrong.
##
## Built by hand rather than through _meteor() because the shared factory's
## `radius`/`count` mean "bombardment footprint" and "how many meteors", and here
## they mean something else entirely (below). The KIND still has to be METEOR:
## SpellCaster's Kind->spectacle table is owned elsewhere, its METEOR arm already
## passes the aimed ground point clamped to reach, and MeteorSigil forks on
## effect=="frost" into IceSpikeLine. The other three meteors are untouched.
static func _frozen_comet() -> SpellDef:
	var s := SpellDef.new()
	s.id = "frozen_comet"          # id unchanged — loadouts/saves reference it
	s.display_name = "Glacial Spine"
	s.description = "Ice tears out of the ground where you aim and races along "\
		+ "the floor in both directions. It cannot be side-stepped — it is jumped."
	s.kind = SpellDef.Kind.METEOR
	s.element = Elements.Element.ICE
	s.use_element_color = true
	s.effect = "frost"             # THE fork key (see MeteorSigil.rain)
	s.mp_cost = 65
	s.cooldown = 6.0
	# Per SPIKE, and a body is speared by one spike, not by a stack of eleven
	# overlapping meteors — so this is the whole hit, not a share of it.
	s.damage = 48
	# Half-length of the crest, i.e. its declared extent to either side. The
	# spectacle floors the spike count so the DRAWN and DAMAGING extent is always
	# <= this: "the spells shouldn't be able to get out the radius" made literal.
	s.radius = 210.0
	s.count = 0                    # unused: spike count comes from radius/spacing
	s.reach = 300.0                # how far from the caster the mark can be placed
	s.cast_time = 1.1              # levitating windup, unchanged
	return s


## ICE WALL — Cryomancer. A temporary blocking barrier of ice that CHILLS on touch.
## Bespoke zoning identity (replaces the Frostpiercer beam-clone).
## AEGIS WARD — the first PROTECTIVE spell. A standing gate of holy light planted
## in the aim direction that EATS magic aimed through it and visibly wears out
## doing it: three rune plates, one per spell it stops.
##
## ⚠ THE ELEMENT IS LOAD-BEARING, NOT FLAVOUR. ReactionTable identifies this ward
## by HOLY — the one element no other barrier carries, which is what let four ward
## rows be added to a live reaction matrix without touching the rock or ice walls.
## A ward authored on any other element is a ward with NO reaction rows at all: it
## would stand there and stop nothing, silently.
##
## ⚠ RETUNED OFF THE ULT SHELF, AND THE WARD'S LIFETIME MOVED WITH IT.
##
## This used to be costed as an ult on purpose (11 s cooldown -> `SpellTier` derives
## ULT) so that it would compete with the class's finisher. The problem was that it
## was in NOBODY'S KIT: the Cleric's ult slot is Heaven's Verdict, so "competes with
## the finisher" resolved to "is never equipped by anyone". That is the exact
## unreachable-spell bug `CLASS_KITS` exists to prevent, and the only protective
## spell in the game was sitting inside it.
##
## The anti-recolour pass puts it in the Cleric's CONTROL slot, which is a non-ult
## slot (`SpellTier.slot_accepts_ult` is false for anything before the last), so the
## shelf had to come down. Both rules from
## docs/superpowers/specs/2026-07-27-protection-spells.md §6 are still satisfied and
## they are what fixed the numbers rather than taste:
##   * `cooldown >= 2x duration`  ->  6.8 >= 2 x 3.0 = 6.0  ✔
##   * uptime <= 45%              ->  3.0 / 6.8 = 44%        ✔
## `AegisWard.LIFETIME` came down 4.0 -> 3.0 in the same edit; the two numbers are
## one balance statement and moving only the cooldown would have taken uptime to 59%.
## Charges (3 spells eaten) and the reach are untouched.
static func _aegis_ward() -> SpellDef:
	var s := SpellDef.new()
	s.id = "aegis_ward"
	s.display_name = "Aegis Ward"
	s.description = "Plant a standing gate of light. It EATS spells aimed through "\
		+ "it three times — you can count what is left on its face — then breaks. "\
		+ "Anything heavier than it gets through; shadow pops it outright."
	s.kind = SpellDef.Kind.WARD
	s.element = Elements.Element.HOLY
	s.use_element_color = true
	s.effect = "holy"
	s.mp_cost = 46
	s.cooldown = 6.8   # HEAVY, not ULT — see the note above
	s.damage = 0
	s.reach = 108.0
	return s


static func _ice_wall() -> SpellDef:
	var s := SpellDef.new()
	s.id = "ice_wall"
	s.display_name = "Ice Wall"
	s.description = "Raise a crystalline wall of ice in the aim direction — it blocks "\
		+ "enemy bodies and projectiles for a few seconds and CHILLS anything pressed "\
		+ "against it, then shatters."
	s.kind = SpellDef.Kind.ICE_WALL
	s.element = Elements.Element.ICE
	s.use_element_color = true
	s.effect = "frost"
	s.mp_cost = 40
	s.cooldown = 5.0
	s.damage = 0
	s.reach = 90.0
	return s


## CHAIN LIGHTNING — Stormcaller. A jagged bolt that leaps enemy-to-enemy.
## Bespoke mobile-chain identity (replaces the Tempest beam-clone). `count` = hops,
## `reach` = hop range.
static func _chain_lightning() -> SpellDef:
	var s := SpellDef.new()
	s.id = "chain_lightning"
	s.display_name = "Chain Lightning"
	s.description = "Loose a bolt that LEAPS from foe to foe — up to five links, "\
		+ "shocking each, the damage falling off with every jump."
	s.kind = SpellDef.Kind.CHAIN
	s.element = Elements.Element.LIGHTNING
	s.use_element_color = true
	s.effect = "lightning"
	s.mp_cost = 44
	s.cooldown = 3.0
	s.damage = 60
	s.count = 5      # max hops
	s.reach = 240.0  # hop range
	return s


## ARCANE MISSILES — a staggered fan of rune-orbs. The description used to say the
## orbs HOME onto your foes; the homing was removed under the no-auto-aim rule and
## RuneOrbs.gd is now explicit that the ribboning "never changes where the orb ends
## up" — the spread is the caster's aim and the stagger between launches is the
## target's dodge window. Saying "home" made the spell read as a spell that hits
## for you, which is the one promise this kit must not make.
static func _rune_orbs() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rune_orbs"
	s.display_name = "Arcane Missiles"
	s.description = "Loose a fan of spinning rune-orbs down the aim — they ribbon "\
		+ "apart as they fly and pop in precise arcane bursts."
	s.kind = SpellDef.Kind.MISSILES
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = "arcane"
	s.mp_cost = 50
	s.cooldown = 3.4
	s.damage = 24  # per orb
	s.count = 6
	return s


## SHADOWBURST — the reposition-and-punctuate blink. Renamed off "Shadow Step" in
## the display-name pass (see the block above `_ordinary_spell`; the `blink_strike`
## id is unchanged). The new name is not just a de-fillering: it is the only one of
## the three that the CODE had already outgrown. When the travel corridor was the
## damage, "Step" described the spell; now that BlinkStrike.gd resolves everything
## in one radius query at the destination, the burst IS the spell and the step is
## just how it gets there.
##
## The description used to
## promise "everything on the crossed line is cut and left WEAKENED", which was
## true of the old version: a 300 px damage corridor along the path travelled.
## BlinkStrike.gd was rewritten (maker: "it should just teleport instantly and then
## do a small explosion where it teleports to") — the corridor, the after-image
## band and the slash are all gone, and the whole damage model is now one radius
## query at the destination inside a telegraphed BLAST_RADIUS of 64 px.
##
## DAMAGE DELIBERATELY LEFT AT 85. It was raised 55 -> 85 by hand ("not strong"),
## and dropping it back would be a second nerf on top of one the maker did not
## ask for: losing the corridor already cut this spell from "everything on a
## 300 px line" to "whatever is inside 64 px of where I landed", which is most of
## its output gone. 85 on a single body is also in band for a HEAVY (Thunderclap
## 62, Rock Pillar 58) and it is the kits' PAYOFF pick precisely because it is the
## biggest non-ult number in the tree. Flagged for the maker: if it over-performs
## in play, 60 is the lever — one number, this line.
static func _blink_strike() -> SpellDef:
	var s := SpellDef.new()
	s.id = "blink_strike"
	s.display_name = "Shadowburst"
	s.description = "Step through shadow to the marked point — the dark you "\
		+ "dragged with you collapses into a burst at your feet."
	s.kind = SpellDef.Kind.BLINK_STRIKE
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 48
	s.cooldown = 3.2
	s.damage = 85  # was 55 — the assassin's signature should HURT (maker: "not strong")
	s.reach = 300.0  # blink distance
	return s


## BLADE FLURRY — Shadowblade alt. A burst of crescent slashes (replaces Void Barrage).
static func _blade_flurry() -> SpellDef:
	var s := SpellDef.new()
	s.id = "blade_flurry"
	s.display_name = "Blade Flurry"
	s.description = "A blur of dashing slashes fans across the front — every foe in "\
		+ "the arc is cut again and again."
	s.kind = SpellDef.Kind.FLURRY
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 44
	s.cooldown = 3.0
	s.damage = 16  # per slash
	s.count = 6
	return s


## SHADOW ROOT — Warlock signature. Shadows erupt FROM the caster and race along the
## ground; dodge the converging mark or be ROOTED in place and weakened.
##
## Was "Void Zone", a straight recolour of Blizzard's ground ellipse. Kept on the
## ZONE kind and the `void_zone` id so loadouts and saved cycles keep resolving —
## SpellCaster's ZONE arm forks on effect=="shadow" to the eruption spectacle.
static func _void_zone() -> SpellDef:
	var s := SpellDef.new()
	s.id = "void_zone"
	s.display_name = "Shadow Root"
	s.description = "Shadows erupt from your feet and race along the ground — dodge "\
		+ "the converging mark or be ROOTED in place, weakened, while the dark grips."
	s.kind = SpellDef.Kind.ZONE
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 55
	s.cooldown = 6.5
	s.damage = 26   # one-shot damage on the catch (no longer a per-tick field)
	s.radius = 64.0  # grasp half-width at the lock point
	s.reach = 300.0
	return s


## DRAIN TETHER — the Warlock's damage line and the Cleric's sustain. The
## description used to say it snaps to "the nearest foe", which is auto-aim, and
## DrainTether.gd was rewritten precisely because that version was undodgeable
## (maker: "is this dodgeable? I don't like it"). It is now a coiled windup and a
## real travelling hook lashed down the aim that "never bends to find a target".
static func _drain_tether() -> SpellDef:
	var s := SpellDef.new()
	s.id = "drain_tether"
	s.display_name = "Drain Tether"
	s.description = "Coil the dark at your hand, then LASH a writhing hook down the "\
		+ "aim — whatever it catches bleeds its life into you until the cable breaks."
	s.kind = SpellDef.Kind.TETHER
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 46
	s.cooldown = 3.4
	# Per tick, five ticks per cast if the cable is never broken. 11 -> 17 in the
	# DPS-floor pass: this is the WARLOCK'S ONLY DIRECT DAMAGE now that its control slot
	# is a summon and its ult a once-a-fight tide, and at 55 per cast the class's whole
	# hand lost to bare fists. Deliberately the smaller half of that fix (the ult took
	# the rest) because this spell also HEALS, so its damage number is two levers.
	s.damage = 17
	return s


## BLIZZARD — Cryomancer alt. A persistent frost field (replaces the Frozen Comet meteor).
static func _blizzard() -> SpellDef:
	var s := SpellDef.new()
	s.id = "blizzard"
	s.display_name = "Blizzard"
	s.description = "Call a swirling snow field over the marked ground — everything "\
		+ "inside is chilled toward a FREEZE."
	s.kind = SpellDef.Kind.ZONE
	s.element = Elements.Element.ICE
	s.use_element_color = true
	s.effect = "frost"
	s.mp_cost = 58
	s.cooldown = 6.0
	s.damage = 8   # per tick
	s.radius = 135.0
	s.reach = 300.0
	s.length = 4.2  # field lifetime
	return s


## CREEPING SHADE — Shadowblade third signature. A shadow peels off the caster's
## feet and RACES ALONG THE FLOOR, hugging terrain, until it reaches a body — then
## it rears into a spike and launches them. Passes UNDER walls; dies in pits.
##
## `reach` is the travel BUDGET (not a distance to the cursor — the strike point
## is emergent) and `radius` the catch half-width. cast_time stays 0 so it goes
## through the summon path: the levitating channel would lift the caster off the
## floor the spell is supposed to leave from.
static func _creeping_shade() -> SpellDef:
	var s := SpellDef.new()
	s.id = "creeping_shade"
	s.display_name = "Creeping Shade"
	s.description = "Peel your own shadow off the ground and send it racing along "\
		+ "the floor — it follows every slope, slips under walls, and SPIKES the "\
		+ "first thing it reaches into the air. Jump it or wear it."
	s.kind = SpellDef.Kind.CRAWLER
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 52
	s.cooldown = 5.5
	s.damage = 60
	s.reach = 620.0
	s.radius = 26.0
	return s


## RIFT DAGGER — Shadowblade / Arcanist. Throw a dagger that sticks where it lands
## (wall, crate, or a body that walks away with it); press again to TEAR yourself
## through to it. Two beats, one button.
##
## Damage is deliberately low on BOTH halves: this is a positioning tool, and a
## teleport that also killed would make the second beat automatic. `length` is the
## anchor lifetime (the same double-duty ZONE already gives it), and the cooldown
## does not start until the anchor resolves.
static func _rift_dagger() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rift_dagger"
	s.display_name = "Rift Dagger"
	s.description = "Hurl a dagger down the aim — it sticks in whatever it reaches. "\
		+ "Press again and the rift tears you through to it, bursting on arrival."
	s.kind = SpellDef.Kind.THROWN_ANCHOR
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = "shadow"
	s.mp_cost = 46
	s.cooldown = 4.5
	s.damage = 34
	s.reach = 700.0
	s.radius = 70.0
	s.length = 4.0
	return s


## BOULDER HURL — Juggernaut earth. Rip a boulder from the ground and throw it.
static func _boulder_hurl() -> SpellDef:
	var s := SpellDef.new()
	s.id = "boulder_hurl"
	s.display_name = "Boulder Hurl"
	s.description = "Rip a boulder from the earth and HURL it down the aim — it shatters on impact, throwing everything back."
	s.kind = SpellDef.Kind.BOULDER
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = "earth"
	s.mp_cost = 50
	s.cooldown = 3.4
	s.damage = 52
	s.radius = 84.0
	return s


## ROCK PILLAR — Juggernaut earth. A telegraphed eruption that launches skyward.
static func _rock_pillar() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rock_pillar"
	s.display_name = "Rock Pillar"
	s.description = "A telegraphed stone spire ERUPTS from the ground, launching everything in its footprint skyward."
	s.kind = SpellDef.Kind.PILLAR
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = "earth"
	s.mp_cost = 52
	s.cooldown = 4.0
	s.damage = 58
	s.radius = 66.0
	s.reach = 280.0
	return s


## ROCK WALL — Juggernaut earth. A temporary blocking barrier of stone (no damage).
static func _rock_wall() -> SpellDef:
	var s := SpellDef.new()
	s.id = "rock_wall"
	s.display_name = "Rock Wall"
	s.description = "Raise a temporary wall of stone in the aim direction — it blocks enemy bodies and projectiles for a few seconds, then crumbles."
	s.kind = SpellDef.Kind.WALL
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = "earth"
	s.mp_cost = 40
	s.cooldown = 5.0
	s.damage = 0
	s.reach = 90.0
	return s


# ═════════════════════════════════════════════ THE ANTI-RECOLOUR SIGNATURES
## ELEVEN SPELLS, ELEVEN SPECTACLES, AND THE RULING THAT PRODUCED THEM.
##
## The maker's words were "we cannot have any recolours — I want all the classes to
## be different and unique and not similar at all", and the table above used to fail
## that on its face: FIVE of nine classes threw a `BeamSpell` down the same corridor
## (ordinary_spell / frostpiercer / infernal_lance / umbral_lance / tempest), FOUR
## ults were one `MeteorSigil.rain()` (meteor_sigil / void_barrage / avalanche /
## frozen_comet), Blizzard sat in three carried hands and Drain Tether in three.
## Nine classes, but far fewer than nine THINGS TO WATCH.
##
## These eleven are the fix. Each one is its own spectacle script and each one is
## carried by exactly ONE class, which is what `tools/slice_test_class_identity.gd`
## now pins directly: no two classes share a carried spell id, and no two classes'
## carried hands resolve to the same spectacle script.
##
## ⚠ EVERY ONE OF THEM IS `Kind.HEX` AND THAT IS DELIBERATE, not laziness. A new
## `SpellDef.Kind` is not one edit, it is five — this file, `SpellCaster`'s dispatch,
## `ReactionTable.form_for_kind`, `CastStyle.for_spell`, `LoadoutBar._draw_glyph` and
## `BotBrain._effective_range` — and four of those five fall through to a DEFAULT
## rather than erroring. Eleven new kinds would have been fifty-odd places where
## nothing happens and nothing complains. The HEX arm forks on ID
## (`SpellCaster.HEX_SCRIPTS`), which is strictly more precise than a kind anyway
## because an id is unique. The consequence is that HEX stopped meaning "a Tier 2
## floor pickup" and now means "forked on id" — `BotBrain` and `LoadoutBar` were
## given per-ID handling for exactly that reason.
##
## ⚠ AND EVERY ONE OF THEM DECLARES `cast_time = 0.0`. Not an oversight: a positive
## cast_time routes the cast through `Hero._begin_channel`, the LEVITATING channel,
## which is exactly wrong for a boot driven into the floor, a draw-cut, a dash or a
## tide that comes out of the ground. They go through the SUMMON path instead, and
## each spectacle owns its own telegraph (`Telegraph` rings, `LOCK_TELL`, `MARK_TELL`,
## `SURGE_LEAD`, the drawn ridge lanes) — read the headers, every one states its tell
## and its counterplay. The ULT shelf is therefore reached through COOLDOWN and MP,
## which `SpellTier.of()` accepts as independently sufficient.
##
## The five melee defs below came from the handoff copies in
## `tools/slice_test_melee_signatures.gd` (which is what that suite falls back to
## while an id is absent from this file). Their COSTS are byte-identical; two of
## their DAMAGE numbers moved, for the reason below, and the handoff copies moved
## with them so the file does not lie about which numbers it is proving.
##
## ══ THE DPS-FLOOR PASS, AND WHY EIGHT DAMAGE NUMBERS MOVED WITH THIS TABLE ═════
## `tools/slice_test_melee_economy.gd` pins a real design rule: EVERY CLASS'S THREE
## SPELL BUTTONS MUST OUT-DAMAGE BARE FISTS ON A SINGLE TARGET (41.2 dps). It exists
## because the fun audit found the dominant play for a caster was "grab the sword,
## hold melee, cast as garnish", which is the wrong dominant strategy for a game
## about absurd magic.
##
## THE NEW KIT TABLE BROKE IT FOR FIVE CLASSES, measured rather than guessed:
##   Arcanist 45.0 -> 39.7, Brawler 42.5 -> 29.5, Cleric 52.1 -> 39.1,
##   Cryomancer 48.7 -> 39.8, Warlock 43.7 -> 24.0.
## The cause is structural and is the price of the anti-recolour picks: FOUR classes
## now carry a middle slot that deals no direct damage at all (Mirror Image, Rock
## Wall, Aegis Ward, Raise Thrall) where before only the Brawler did. A class whose
## utility slot is free of damage has to make it back on the other two.
##
## So eight `damage` values moved and NOTHING ELSE DID. That is deliberate:
## `SpellTier.of()` reads cast_time / cooldown / mp_cost and never damage, and that
## shelf is also the reaction CLASH WEIGHT — so a "damage tune" that touched a
## timing would have silently re-decided every spell-vs-spell interaction in the
## game. Each moved number is annotated at its own factory with its peer comparison.
## Post-pass: 45.9 / 44.0 / 44.0 / 44.1 / 44.7 / 44.8 / 63.8 / 44.5 / 47.5.
##
## ⚠ THE MODEL UNDERSTATES TWO SPELLS AND THAT IS LEFT ALONE ON PURPOSE. The
## rotation only counts `SpellDef.damage`, so `raise_thrall` (which puts a fighting
## body on the floor for 9-15 s) and `mirror_image` (a clone that re-casts
## everything you cast) both score ZERO. Their real contribution is not zero, so the
## floor above is a CONSERVATIVE one: a kit that clears it in the model clears it in
## play. Modelling them would mean inventing a dps number for a summon, which is a
## guess dressed as data — and it would let a genuinely weak kit pass.
##
## ⚠ AND NONE OF IT IS PLAYTESTED. A rotation sim is not a playtest: it says nothing
## about whether the numbers FEEL right, whether the windup gets you killed, or
## whether Meteor Fist at 165 is obnoxious to be hit by. These are the numbers that
## satisfy a floor, not numbers anyone has felt.


## THOUSAND CUTS — Shadowblade ULT. Replaces `umbral_lance`, a violet copy of the
## Arcanist's magenta beam. Marks ONE body and opens it from `count` angles walked
## around it: the exact inverse of Chain Lightning (one hit on many) and not the
## same class's forward-cone Blade Flurry either. `count` is the number of cuts.
static func _thousand_cuts() -> SpellDef:
	var s := SpellDef.new()
	s.id = "thousand_cuts"
	s.display_name = "Thousand Cuts"
	s.description = "Mark one body, step out of the world, and come back at it from "\
		+ "every angle at once. The ring shows you exactly where it will happen — "\
		+ "the only way out is to not be standing in it."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.SHADOW)
	s.mp_cost = 72       # ULT by MP and by cooldown, with no levitating channel
	s.cooldown = 8.0
	s.damage = 16        # per cut; the finisher is a multiple of one cut
	s.count = 7          # cuts walked around the anchor
	s.reach = 300.0      # how far out the mark may be placed
	return s


## IAI SLASH — Swordsaint DAMAGE. Replaces `blade_flurry`, which is the SHADOWBLADE's
## spell worn by a second class. One committed draw-cut at 118 px — a body and a half
## — and a five-second wait if it whiffs. The whiff IS the counterplay.
static func _iai_slash() -> SpellDef:
	var s := SpellDef.new()
	s.id = "iai_slash"
	s.display_name = "Iai Slash"
	s.description = "Draw and cut in one motion. The corridor is drawn before the "\
		+ "blade leaves the sheath, and it is barely longer than you are. Bait it "\
		+ "and the duelist has no damage for five seconds."
	s.kind = SpellDef.Kind.HEX
	# ARCANE, not "no element". `Hero.CLASS_CONFIG[SWORDSAINT].melee_element` is -1
	# because plain steel applies no ailment — but a SpellDef with element -1 makes
	# `SpellCaster.resolve_element` GUESS and makes `SpellReactor.register` DROP the
	# effect out of the reaction system entirely. The blade stays ailment-free by not
	# calling apply_status, not by lying about its element.
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.ARCANE)
	s.mp_cost = 44
	s.cooldown = 5.0     # the whiff punishment, not a balance rounding
	s.damage = 96
	s.reach = 118.0      # the blade's length — emphatically not a beam
	s.width = 52.0       # corridor width at its widest
	return s


## CRESCENT RUSH — Swordsaint ANSWER. A travelling forward dash that CUTS the lane
## behind it, as opposed to `Hero._blink` (instant, no damage) and Shadowburst
## (teleport, burst at the destination). For a duelist the get-out is IN.
##
## Renamed off "Crescent Step" in the display-name pass (the `crescent_step` id is
## unchanged, and so is the `CrescentStep.gd` spectacle script that serves it — a
## script rename would have been a real edit in a file this pass has no business
## touching, for zero player-visible gain). "Crescent" is the shape it cuts and
## "Rush" is the verb; the filler noun carried neither.
##
## Rejected "Crosscut", which is snappier: this class already ults with HORIZON CUT,
## and two "Cut" names inside one five-spell kit is the naming version of the exact
## recolour problem the table above spends two hundred lines undoing.
static func _crescent_step() -> SpellDef:
	var s := SpellDef.new()
	s.id = "crescent_step"
	s.display_name = "Crescent Rush"
	s.description = "Step through the guard, cutting the whole lane you crossed. "\
		+ "The lane is drawn at full length before you move — its width, its angle, "\
		+ "all of it. Leave the lane, or wear the cut."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.ARCANE
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.ARCANE)
	s.mp_cost = 40
	s.cooldown = 4.6
	s.damage = 58
	s.reach = 240.0      # lane length (the travel budget, not a cursor distance)
	s.width = 44.0       # corridor width
	return s


## SHOCKWAVE STOMP — Brawler DAMAGE. Replaces `thunderclap`, a LIGHTNING lance on the
## class whose whole card reads "pure-melee knockout — no magic". No projectile, no
## corridor: one boot into the floor and a ridge that RUNS ALONG THE GROUND to either
## side, so it is jumped, out-ranged, or stood across a pit from.
static func _shockwave_stomp() -> SpellDef:
	var s := SpellDef.new()
	s.id = "shockwave_stomp"
	s.display_name = "Shockwave Stomp"
	s.description = "Drive a boot into the floor and a ridge of broken ground runs "\
		+ "out both ways. It follows the terrain, so it stops at a ledge — and it "\
		+ "travels, so you can see it coming. Jump it."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.EARTH)
	s.mp_cost = 42
	s.cooldown = 4.0
	# 54 -> 88 in the DPS-floor pass (see `_thousand_cuts`'s block comment). 88 on a
	# 4.0 s HEAVY sits between the Thunderclap it replaced (90 / 3.4 s) and the
	# Swordsaint's draw-cut (96 / 5.0 s); 54 made the Brawler's DAMAGE LINE weaker than
	# the Juggernaut's payoff, which is not what a damage line is.
	s.damage = 88
	s.reach = 300.0      # how far each ridge runs
	return s


## METEOR FIST — Brawler ULT. Replaces `infernal_lance`, the class's beam. He LEAPS
## and comes down fist-first; the danger ring is drawn at exactly the blast radius
## before he leaves the floor, so walking out of a circle you were shown is the
## counterplay. Fires a `BlastSpell` on landing, carrying this def's element.
static func _meteor_fist() -> SpellDef:
	var s := SpellDef.new()
	s.id = "meteor_fist"
	s.display_name = "Meteor Fist"
	s.description = "Leave the floor and come back down through it. The ring is "\
		+ "drawn at the exact width of the crater before he jumps — it does not "\
		+ "track, so walk out of it."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.EARTH)
	s.mp_cost = 78
	s.cooldown = 8.5
	# 120 -> 165 in the DPS-floor pass. The longest cooldown of any class ult and the
	# only one that has to physically land on somebody, so it carries the biggest single
	# number (Heaven's Verdict 130 / 7.0 s, Horizon Cut 110 / 6.5 s).
	s.damage = 165
	s.radius = 110.0     # blast radius == the drawn ring, 1:1
	s.reach = 260.0      # how far he may leap
	return s


## RADIANT VOLLEY — Cleric DAMAGE. Replaces `rune_orbs`. A RACK of holy lances fired
## PARALLEL from an arc of origins, so the band is a fixed width and position is the
## damage dial: stand in the middle of the band and take every lance, clip the edge
## and take one. HOLY is load-bearing — the Cleric is the only holy caster.
static func _radiant_volley() -> SpellDef:
	var s := SpellDef.new()
	s.id = "radiant_volley"
	s.display_name = "Radiant Volley"
	s.description = "A rack of light opens at your shoulder and looses in waves — "\
		+ "parallel lances, a band the same width the whole way down. Stand in the "\
		+ "middle of it and every one lands. Clip the edge and one does."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.HOLY
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.HOLY)
	s.mp_cost = 46
	s.cooldown = 4.2
	# PER LANCE — the volley's total is a positioning question. 14 -> 18 in the
	# DPS-floor pass; a body clipping the EDGE of the band still takes only one.
	s.damage = 18
	s.length = 760.0     # each lance's travel budget
	s.reach = 300.0
	return s


## SHATTER — Cryomancer DAMAGE. Replaces `frostpiercer`, the class's beam. A charge
## HURLED at the ground that pays 0.35x on a warm body, 1.0x on a chilled one and
## 3.0x on a frozen one — so the class's own Blizzard is its set-up, and the whole
## spell is an argument for having chilled the target first.
##
## ⚠ NO NUMBER ON THIS SPELL MOVED IN THE "ice isn't damaging" PASS, deliberately.
## 62 x 3.0 = 186 on a frozen body already makes a landed Shatter the single
## biggest hit in the roster (Heaven's Wrath is 130 across five strikes; this
## class's own ult is 48 a spike), on a 4 s cooldown, on the DAMAGE slot. The spell
## was not weak — it was ILLEGIBLE: it threw no projectile at all, and it gave the
## player no way to tell a 22 from a 186 before it went off. Both of those are
## fixed in `Shatter.gd`. Raising the number too would have been the wrong lever
## twice over, and into a build where hero HP just went up 1.4x.
static func _shatter() -> SpellDef:
	var s := SpellDef.new()
	s.id = "shatter"
	s.display_name = "Shatter"
	s.description = "Hurl a frost charge at the ground and let the fracture lattice "\
		+ "spread. It barely scratches something warm. It TRIPLES on something "\
		+ "frozen, and the casing shards cut everything stood near it. Chill them "\
		+ "first, or do not bother."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.ICE
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.ICE)
	s.mp_cost = 44
	s.cooldown = 4.0
	# BEFORE the state multiplier (0.35 / 1.0 / 3.0). 42 -> 62 in the DPS-floor pass —
	# and note what that pass measures: a WARM body, i.e. 0.35x = 22. The 3.0x frozen
	# case is a set-up the rotation model cannot express, so the floor is cleared on the
	# spell's WORST case, which is the conservative direction.
	s.damage = 62
	s.radius = 104.0
	s.reach = 300.0
	return s


## HEAVEN'S WRATH — Stormcaller ULT. Replaces `tempest`, the class's beam. A storm
## CELL rather than a bolt: a cloud that drifts over a footprint and drops five
## marked strikes, each with its own tell, so leaving a mark is always possible.
static func _heavens_wrath() -> SpellDef:
	var s := SpellDef.new()
	s.id = "heavens_wrath"
	s.display_name = "Heaven's Wrath"
	s.description = "Open a storm cell over the ground you chose. It drifts, and it "\
		+ "picks its targets one at a time — each strike marks the floor before it "\
		+ "falls. Standing still under it is the mistake."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.LIGHTNING
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.LIGHTNING)
	s.mp_cost = 74
	s.cooldown = 8.0
	s.damage = 26        # per strike, five of them
	# ⚠ 42 -> 26 ON A TOTAL-CONNECT BASIS, not a per-strike one. Five strikes at 42
	# is 210 damage into a roster whose max HP runs 78-145 — a one-shot kill from
	# full health, and by a wide margin the biggest ult in the game (fault_line 105,
	# grave_tide 130, meteor_fist 165, frozen_comet 48). MEASURED: the Stormcaller
	# went 15-0-1 across two full-roster sweeps. 26 x 5 = 130 puts a full connect in
	# line with the other ults while keeping what makes the spell ITS spell — five
	# separate strikes you can be caught by more than once.
	s.radius = 210.0     # the CELL's footprint (a strike's own radius is much smaller)
	s.reach = 320.0
	return s


## FAULT LINE — Juggernaut ULT. Replaces `colossus_pillar`, the fourth placed
## bombardment. A rupture that TRAVELS along the floor from the caster, splitting
## cover as it goes and stopping at the lip of a pit — which is the counterplay: the
## crest can be out-run, jumped, or separated from you by a hole in the world.
static func _fault_line() -> SpellDef:
	var s := SpellDef.new()
	s.id = "fault_line"
	s.display_name = "Fault Line"
	s.description = "Split the floor and send the crack running. It takes the "\
		+ "ground with it, and everything standing on the seam goes up. It cannot "\
		+ "cross a pit, and it cannot catch what is in the air."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.EARTH
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.EARTH)
	s.mp_cost = 76
	s.cooldown = 8.0
	s.damage = 105
	s.length = 760.0     # travel budget along the floor
	s.reach = 320.0
	return s


## RAISE THRALL — Warlock CONTROL. The only SUMMON in the game, which is the whole
## point: nothing else in any kit puts a second body on the floor. Bare ground gives
## one thin thrall; a corpse within `GRAVE_RADIUS` gives two better ones, so the
## spell rewards fighting where things have already died. `length` is the thrall's
## lifetime. A Warlock also starts every floor with one already up — see
## `RaiseThrall.raise_opening_thralls`, called from `Arena._setup_floor`.
static func _raise_thrall() -> SpellDef:
	var s := SpellDef.new()
	s.id = "raise_thrall"
	s.display_name = "Raise Thrall"
	s.description = "Reach into the floor and pull something out of it. Bare ground "\
		+ "gives you a thin one. Where a body fell, you get two, and they last. "\
		+ "They are on your side, and they are not on anybody else's."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.SHADOW)
	s.mp_cost = 58
	s.cooldown = 6.4
	s.damage = 0         # the thrall does the damage, not the casting
	s.length = 9.0       # thrall lifetime (the grave case extends it itself)
	s.reach = 300.0      # how far out a grave still counts as the one you meant
	return s


## GRAVE TIDE — Warlock ULT. Replaces `void_barrage`, the third sky bombardment. The
## floor gives way in BOTH directions at once and hands come out of it; whatever the
## front reaches is held where it stands and bled into the caster while it struggles.
## Cleared by being in the air when the front passes — height is the whole answer.
static func _grave_tide() -> SpellDef:
	var s := SpellDef.new()
	s.id = "grave_tide"
	s.display_name = "Grave Tide"
	s.description = "The floor of the room gives way both ways at once and the "\
		+ "hands come up. What they reach is held where it stands and bled into "\
		+ "you while it struggles. Be off the ground when it passes."
	s.kind = SpellDef.Kind.HEX
	s.element = Elements.Element.SHADOW
	s.use_element_color = true
	s.effect = _effect_for_element(Elements.Element.SHADOW)
	s.mp_cost = 76
	s.cooldown = 9.0
	# 40 -> 130 in the DPS-floor pass. The catch hit only — the hold also drains
	# (`GraveTide.DRAIN_PER_TICK` over `HOLD_TIME`), so the real single-target total is
	# higher again. In band with the other ults (Heaven's Verdict 130 / 7.0 s) and
	# cleared outright by being off the ground when the front passes.
	s.damage = 130
	s.reach = 520.0      # how far the front runs each way
	return s


static func _meteor(
	id: String, name: String, desc: String, element: int,
	mp: int, cd: float, dmg: int, radius: float, count: int
) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.kind = SpellDef.Kind.METEOR
	s.element = element
	s.use_element_color = true
	s.effect = _effect_for_element(element)
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.radius = radius
	s.count = count
	s.reach = 300.0
	s.cast_time = 1.1  # levitating windup
	return s


## CAST TIME IS THE BEAM FAMILY'S ONE REAL DESIGN AXIS, so it is a parameter and
## not the flat 1.0 every beam used to share. It buys two different things at once
## and they point the same way:
##
##   1. The DODGE WINDOW. cast_time is the levitating channel (Hero._begin_channel)
##      — the seconds the opponent gets to read the sigil and leave. Longer wind-up
##      = more warning = a spell that has to be worth the warning.
##   2. The CLASH WEIGHT. SpellTier.of() derives QUICK/HEAVY/ULT from cast time,
##      cooldown and MP, and that shelf is now also what a spell WEIGHS when two
##      spells meet: equal shelves annihilate, a heavier one overpowers and keeps
##      going, and a barrier stops what it is not outmatched by.
##
## So "commit longer, hit through more" is one number saying one thing twice. When
## every beam shared cast_time = 1.0 they were all ULT, which made beam-vs-beam
## *always* mutual annihilation (overpower unreachable) and beam-vs-wall *always*
## a breach (no wall could ever stop a beam). Spreading the family across two
## shelves is what makes that ladder reachable at all.
##
## The floor is deliberately NOT zero. SpellTier.QUICK requires cast_time <= 0.01,
## i.e. no channel — and an instant screen-crossing lance has no tell, which
## breaks the locked "every ability needs a real telegraph and a dodge window"
## rule. So no beam is QUICK: the family spans HEAVY and ULT only.
static func _beam(
	id: String, name: String, desc: String, element: int,
	mp: int, cd: float, dmg: int, length: float, width: float,
	cast_time: float = 1.0
) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.kind = SpellDef.Kind.BEAM
	s.element = element
	s.use_element_color = true
	s.effect = _effect_for_element(element)
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.length = length
	s.width = width
	s.cast_time = cast_time  # levitating windup — see the note above
	return s


## Elemental particle CHARACTER from the element index (see Elements.Element).
## Every element now has its own bespoke spectacle skin (was: only fire/frost/
## arcane; shadow/earth/wind/lightning fell through to arcane garnish).
static func _effect_for_element(element: int) -> String:
	match element:
		0: return "fire"       # FIRE
		1: return "frost"      # ICE
		2: return "lightning"  # LIGHTNING — jagged crackle + sparks
		3: return "shadow"     # SHADOW — inky violet tendrils
		5: return "earth"      # EARTH — chunky amber debris + dust
		6: return "holy"       # HOLY
		7: return "wind"       # WIND — fast teal wisps
		_: return "arcane"     # ARCANE (4) + anything unmapped


static func _ray(
	id: String, name: String, desc: String, color: Color,
	mp: int, cd: float, dmg: int, radius: float
) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.kind = SpellDef.Kind.DIVINE_RAY
	s.use_element_color = false
	s.color = color
	s.effect = "holy"
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.radius = radius
	s.reach = 280.0
	s.cast_time = 1.0  # levitating windup
	return s


## Heaven's Verdict's spectacle: a radial star-convergence nova (SpellDef.Kind
## .CONVERGENCE). Holy, no element tint; the longest telegraph + biggest single hit.
static func _convergence(
	id: String, name: String, desc: String, color: Color,
	mp: int, cd: float, dmg: int, radius: float
) -> SpellDef:
	var s := SpellDef.new()
	s.id = id
	s.display_name = name
	s.description = desc
	s.kind = SpellDef.Kind.CONVERGENCE
	s.use_element_color = false
	s.color = color
	s.effect = "holy"
	s.mp_cost = mp
	s.cooldown = cd
	s.damage = dmg
	s.radius = radius
	s.reach = 320.0
	s.cast_time = 1.3  # the finisher: longest levitating windup
	return s
