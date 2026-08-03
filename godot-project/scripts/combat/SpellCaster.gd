class_name SpellCaster
extends RefCounted
## Turns a SpellDef (data) into an on-screen spectacle (behaviour). The single
## seam between the spell TREE (what the player equips) and the spell SCENES
## (BeamSpell / DivineRay / ...). Adding a new kind = one match arm here + a new
## spectacle scene; the loadout/UI/MP layers never change.
##
## Scripts are load()ed by path (never class_name) so the caller can invoke this
## from headless tools without early-compiling the autoload-referencing scenes.

const BEAM_PATH: String = "res://scripts/combat/BeamSpell.gd"
const RAY_PATH: String = "res://scripts/combat/DivineRay.gd"
const METEOR_PATH: String = "res://scripts/combat/MeteorSigil.gd"
const CONVERGENCE_PATH: String = "res://scripts/combat/StarConvergence.gd"
const RUSH_PATH: String = "res://scripts/combat/LightningRush.gd"
const NOVA_PATH: String = "res://scenes/combat/EnergyNova.tscn"
const BOULDER_PATH: String = "res://scripts/combat/BoulderHurl.gd"
const PILLAR_PATH: String = "res://scripts/combat/RockPillar.gd"
const WALL_PATH: String = "res://scripts/combat/RockWall.gd"
const ICE_WALL_PATH: String = "res://scripts/combat/IceWall.gd"
const CHAIN_PATH: String = "res://scripts/combat/ChainBolt.gd"
const ZONE_PATH: String = "res://scripts/combat/ZoneSpell.gd"
const MISSILES_PATH: String = "res://scripts/combat/RuneOrbs.gd"
const TETHER_PATH: String = "res://scripts/combat/DrainTether.gd"
const FLURRY_PATH: String = "res://scripts/combat/BladeFlurry.gd"
const BLINK_PATH: String = "res://scripts/combat/BlinkStrike.gd"
const SHADOW_ROOT_PATH: String = "res://scripts/combat/ShadowRoot.gd"
const CRAWLER_PATH: String = "res://scripts/combat/ShadowCrawler.gd"
const DAGGER_PATH: String = "res://scripts/combat/RiftDagger.gd"
const WARD_PATH: String = "res://scripts/combat/AegisWard.gd"
const ARC_PATH: String = "res://scripts/combat/HorizonArc.gd"

# ------------------------------------------------------- THE DROP ECONOMY ARMS
## `SpellDef.Kind.HEX` and `.CATACLYSM` are the Tier 2 / Tier 3 pickup kinds, and
## unlike every kind above them they do NOT map one-to-one onto a spectacle. Ten
## drop spells share two arms and fork on the spell's ID through these tables.
##
## WHY, when every other kind here gets its own arm: a new `Kind` is not one edit,
## it is SIX — this dispatcher plus `ReactionTable.form_for_kind`,
## `CastStyle.for_spell`, `LoadoutBar._draw_glyph` and `BotBrain._effective_range`,
## none of which error on a kind they do not know. Ten new kinds would have been
## fifty places where nothing happens and nothing complains, in four files owned by
## other agents. Two kinds is two.
##
## The precedent is already here: the ZONE arm forks Shadow Root off Blizzard on
## the effect string and the METEOR arm forks Glacial Spine the same way. This is
## that, keyed by id instead — which is strictly more precise, because an id is
## unique and an effect string is shared by every spell of an element.
##
## A drop id with no entry falls through to `return false`, exactly like an unbuilt
## kind: a safe no-op, never a crash.
##
## ⚠ `HEX` NO LONGER MEANS "TIER 2 FLOOR PICKUP". It means "forked on id", and the
## anti-recolour pass made that the majority case: ELEVEN CLASS-KIT SIGNATURES ride
## this arm now, six of them carried by default. The maker's ruling was "we cannot
## have any recolours — I want all the classes to be different and unique and not
## similar at all", and five of nine classes were throwing the same `BeamSpell` down
## the same corridor. Eleven bespoke spectacles fixed that; eleven new `Kind`s would
## have been ~55 silent defaults across five files, so they fork here instead.
##
## The consequences of that are NOT free and were paid for explicitly:
##   * `BotBrain._effective_range` has a HEX branch — without it a bot reads
##     `mirror_image`'s `reach` (1.0, the echo DELAY in seconds) as a one-pixel range
##     and never casts it, and reads Radiant Volley's cast range instead of its
##     760 px travel. A class a bot cannot fight with is a class that cannot appear
##     in a recorded clip.
##   * `LoadoutBar._draw_glyph` has a HEX branch — otherwise six of the nine classes
##     draw the same fallback circle on their default hand.
##   * `CastStyle.for_spell_def` exists so a draw-cut and a stomp get their own body
##     language rather than the POINT thrust every unknown kind falls through to.
##   * `ReactionTable.form_for_kind` is DELIBERATELY left alone: it answers IMPACT
##     for HEX, and all eleven register themselves as `Form.IMPACT` in their own
##     `_ready`, so the default is already the right answer. Changing it would be
##     churn, not a fix.
const HEX_SCRIPTS: Dictionary = {
	# Tier 2 floor pickups.
	"petrify": "res://scripts/combat/Petrify.gd",
	"gravity_flip": "res://scripts/combat/GravityFlip.gd",
	"blood_pact": "res://scripts/combat/BloodPact.gd",
	# CLASS-KIT SIGNATURES. `mirror_image` was a drop and is now the Arcanist's
	# control slot; the other eleven were built for this pass. The registry is keyed
	# by id and has never cared which shelf an id belongs to.
	"mirror_image": "res://scripts/combat/MirrorImage.gd",
	"thousand_cuts": "res://scripts/combat/ThousandCuts.gd",
	"iai_slash": "res://scripts/combat/IaiSlash.gd",
	"crescent_step": "res://scripts/combat/CrescentStep.gd",
	"shockwave_stomp": "res://scripts/combat/ShockwaveStomp.gd",
	"meteor_fist": "res://scripts/combat/MeteorFist.gd",
	"radiant_volley": "res://scripts/combat/RadiantVolley.gd",
	"shatter": "res://scripts/combat/Shatter.gd",
	"heavens_wrath": "res://scripts/combat/HeavensWrath.gd",
	"fault_line": "res://scripts/combat/FaultLine.gd",
	"raise_thrall": "res://scripts/combat/RaiseThrall.gd",
	"grave_tide": "res://scripts/combat/GraveTide.gd",
}
const CATACLYSM_SCRIPTS: Dictionary = {
	"the_void": "res://scripts/combat/VoidCollapse.gd",
	"chronostasis": "res://scripts/combat/Chronostasis.gd",
	"equinox": "res://scripts/combat/Equinox.gd",
	# `roulette` is deliberately ABSENT: it has no spectacle of its own. It rolls
	# one of the three above and re-enters `cast`. See `_roll_roulette`.
}
# ------------------------------------------------------------------ WARM-UP
## Every spectacle script this dispatcher can reach, INCLUDING the ones those
## scripts reach in turn. Used only by `warm()`.
##
## ⚠ THE NESTED ONES ARE NOT OPTIONAL AND ARE EASY TO MISS. `frozen_comet` measured
## a 61 ms first cast while its own arm's script (`MeteorSigil`) was ALREADY cached
## — because MeteorSigil forks to `IceSpikeLine` by path from inside `rain()`. The
## same is true of ShadowRoot (forked off the ZONE arm), RigGhost (MirrorImage) and
## the two reaction spectacles. Warming only this file's own dispatch table would
## have left the worst offender in the roster cold and looked like it worked.
const WARM_PATHS: PackedStringArray = [
	BEAM_PATH, RAY_PATH, METEOR_PATH, CONVERGENCE_PATH, RUSH_PATH, NOVA_PATH,
	BOULDER_PATH, PILLAR_PATH, WALL_PATH, ICE_WALL_PATH, CHAIN_PATH, ZONE_PATH,
	MISSILES_PATH, TETHER_PATH, FLURRY_PATH, BLINK_PATH, SHADOW_ROOT_PATH,
	CRAWLER_PATH, DAGGER_PATH, WARD_PATH, ARC_PATH,
	# Tier 2 / Tier 3 drop spectacles (the HEX / CATACLYSM fork tables).
	"res://scripts/combat/Petrify.gd",
	"res://scripts/combat/GravityFlip.gd",
	"res://scripts/combat/BloodPact.gd",
	"res://scripts/combat/MirrorImage.gd",
	"res://scripts/combat/VoidCollapse.gd",
	"res://scripts/combat/Chronostasis.gd",
	"res://scripts/combat/Equinox.gd",
	# THE ELEVEN CLASS-KIT SIGNATURES (also HEX-forked). Six of these are carried by
	# DEFAULT, so leaving them cold would land the 44-126 ms first-cast stall inside
	# the first minute of every run on six of the nine classes.
	"res://scripts/combat/ThousandCuts.gd",
	"res://scripts/combat/IaiSlash.gd",
	"res://scripts/combat/CrescentStep.gd",
	"res://scripts/combat/ShockwaveStomp.gd",
	"res://scripts/combat/MeteorFist.gd",
	"res://scripts/combat/RadiantVolley.gd",
	"res://scripts/combat/Shatter.gd",
	"res://scripts/combat/HeavensWrath.gd",
	"res://scripts/combat/FaultLine.gd",
	"res://scripts/combat/RaiseThrall.gd",
	"res://scripts/combat/GraveTide.gd",
	# Reached BY a spectacle, not by an arm. See the warning above.
	"res://scripts/combat/IceSpikeLine.gd",   # MeteorSigil.rain() -> glacial spine
	"res://scripts/combat/RigGhost.gd",       # MirrorImage's doubles
	"res://scripts/combat/HollowPurple.gd",   # beam-fusion reaction outcome
	"res://scripts/combat/SteamCloud.gd",     # fire-meets-ice reaction outcome
	# ⚠ RAISE THRALL'S NESTED PAIR, and the reason the header's warning is repeated
	# here. A sweep of the eleven new files for `load(`/`preload(` found exactly one
	# offender and it is this spell: `RaiseThrall._spawn_thrall` load()s BOTH the
	# thrall script AND its PackedScene by path, from inside the cast. Warming only
	# `RaiseThrall.gd` would leave a summon paying full first-touch cost for two more
	# resources — the same shape of miss that measured 61 ms on `frozen_comet`. The
	# other ten name their collaborators (`BlastSpell`, `Telegraph`) as compile-time
	# globals, which the engine resolves when their own script loads.
	"res://scripts/combat/Thrall.gd",
	"res://scenes/combat/Thrall.tscn",
]


## WHICH SPECTACLE SCRIPT A SPELL ACTUALLY BUILDS — the dispatch table below, asked
## as a question instead of executed.
##
## It exists for the anti-recolour invariant (`tools/slice_test_class_identity.gd`),
## which has to be able to say "no two classes' carried hands share a spectacle" and
## therefore needs the mapping without spawning anything. Two forks make that
## genuinely non-obvious and are the reason this cannot be a plain `Kind` lookup:
## the ZONE arm forks Shadow Root off Blizzard on `effect == "shadow"`, and the
## METEOR arm forks the Glacial Spine off the bombardments on `effect == "frost"`.
## Both are mirrored here.
##
## ⚠ THIS IS A SECOND STATEMENT OF THE DISPATCH AND IT CAN DRIFT FROM IT. The tie
## that stops it drifting silently is in the identity suite: every path this returns
## must also appear in `WARM_PATHS`, which is the list `warm()` really loads. A new
## arm that forgets one of the two will fail there rather than quietly reporting a
## stale answer. `""` for a kind with no built spectacle, exactly like the `_:` arm.
static func spectacle_path(spell: SpellDef) -> String:
	if spell == null:
		return ""
	match spell.kind:
		SpellDef.Kind.BEAM: return BEAM_PATH
		SpellDef.Kind.DIVINE_RAY: return RAY_PATH
		SpellDef.Kind.METEOR:
			# The fork MeteorSigil.rain() takes on effect=="frost" (Glacial Spine).
			return "res://scripts/combat/IceSpikeLine.gd" if spell.effect == "frost" else METEOR_PATH
		SpellDef.Kind.CONVERGENCE: return CONVERGENCE_PATH
		SpellDef.Kind.RUSH: return RUSH_PATH
		SpellDef.Kind.NOVA: return NOVA_PATH
		SpellDef.Kind.BOULDER: return BOULDER_PATH
		SpellDef.Kind.PILLAR: return PILLAR_PATH
		SpellDef.Kind.WALL: return WALL_PATH
		SpellDef.Kind.ICE_WALL: return ICE_WALL_PATH
		SpellDef.Kind.CHAIN: return CHAIN_PATH
		SpellDef.Kind.ZONE:
			# The fork the ZONE arm takes on effect=="shadow" (Shadow Root).
			return SHADOW_ROOT_PATH if spell.effect == "shadow" else ZONE_PATH
		SpellDef.Kind.MISSILES: return MISSILES_PATH
		SpellDef.Kind.TETHER: return TETHER_PATH
		SpellDef.Kind.FLURRY: return FLURRY_PATH
		SpellDef.Kind.BLINK_STRIKE: return BLINK_PATH
		SpellDef.Kind.CRAWLER: return CRAWLER_PATH
		SpellDef.Kind.THROWN_ANCHOR: return DAGGER_PATH
		SpellDef.Kind.WARD: return WARD_PATH
		SpellDef.Kind.ARC: return ARC_PATH
		SpellDef.Kind.HEX: return String(HEX_SCRIPTS.get(spell.id, ""))
		SpellDef.Kind.CATACLYSM: return String(CATACLYSM_SCRIPTS.get(spell.id, ""))
	return ""

## Has `warm()` already run this session?
static var _warmed: bool = false

## ⚠ THE WARMED RESOURCES ARE HELD, AND THAT IS THE WHOLE POINT — not a leak.
##
## Godot's resource cache is a cache of LIVE references, not a record of what has
## been loaded: drop the last reference and the resource is freed and the next
## `load()` pays full price again. `warm()` originally let its locals fall out of
## scope, and `tools/slice_test_spell_warm.gd` caught it on the first run —
## `EnergyNova.tscn` came back uncached immediately after being loaded, because a
## PackedScene nothing points at does not survive the function returning. (The
## GDScripts appeared to survive only because the engine's global script cache
## happened to keep them, which is a different mechanism and not one to rely on.)
##
## Holding them is the intended end state anyway: every one of these is about to be
## instanced repeatedly for the rest of the session.
static var _warm_hold: Array[Resource] = []


## Pay the first-touch script load for every spectacle NOW, so the player does not
## pay it mid-fight.
##
## THE PROBLEM THIS SOLVES, measured by `tools/probe_cast_warmup.gd`: this file
## reaches its spectacles with `load()` by PATH rather than `preload` — deliberately,
## so headless tools can call `cast()` without early-compiling the autoload-
## referencing scenes (see the header). A path `load()` of a script nothing has
## touched yet PARSES AND COMPILES IT ON THE SPOT, and that is not cheap:
##
##   uncached first cast   44-126 ms      cached first cast   0.3-2.6 ms
##
## and 1411 ms across the whole roster. The evidence is not the timer but
## `ResourceLoader.has_cached()`: every expensive row read `no`, every cheap row
## read `YES`, and `chain_lightning` (ChainBolt, cold, 45.7 ms) versus
## `arc_of_fools` (ChainBolt, now warm, 0.51 ms) is the same script 90x apart.
##
## That cost is paid ONCE PER SPELL TYPE PER SESSION, which is the worst possible
## shape for it: it lands the FIRST time the player throws each spell — i.e. all
## through the first minute of play — as a single-frame stall of 44-126 ms on a
## desktop, so roughly 130-630 ms on the three-year-old mid-range Android this is
## aimed at. That is not a hitch, it is a visible freeze, and it lands squarely on
## the `worst`-frame number the perf overlay tells the maker to watch.
##
## Deliberately NOT a `preload` rewrite and NOT a per-cast cache. `preload` would
## break the documented reason the loads are by path; a per-cast cache would fix
## nothing, because the second cast is already fast — the first one is the problem.
## Moving WHEN the cost is paid is the entire fix.
##
## Idempotent and safe to call from anywhere, including twice. Returns how many
## scripts it actually had to load, so a caller (or a test) can see it do work the
## first time and nothing the second.
static func warm() -> int:
	if _warmed:
		return 0
	_warmed = true
	var loaded: int = 0
	for p: String in WARM_PATHS:
		# `has_cached` first so an already-warm session does no work at all, and so
		# the return value means "scripts compiled" rather than "paths visited".
		if ResourceLoader.has_cached(p):
			continue
		var res: Resource = ResourceLoader.load(p)
		if res != null:
			_warm_hold.append(res)
			loaded += 1
	return loaded


## Test hook — lets a suite prove `warm()` is idempotent by re-arming it.
static func reset_warm() -> void:
	_warmed = false
	_warm_hold.clear()


## What Roulette may roll, and how often it opens on the CASTER instead of on the
## aim. The self-cast chance is the whole reason the spell is a gamble rather than
## a free Tier 3 — with it at 0 there would be no reason ever to hold anything else.
## UNTESTED GUESS: 1-in-4. Frequent enough to be a real fear, rare enough that the
## spell is still worth casting.
const ROULETTE_POOL: Array[String] = ["the_void", "chronostasis", "equinox"]
const ROULETTE_SELF_CHANCE: float = 0.25


# ------------------------------------------------------------- FRIENDLY FIRE
## THE SHARED GROUP EVERY DAMAGEABLE FIGHTER JOINS. Heroes join it in `Hero._ready`
## (on TOP of `hero` and any faction group — nothing is removed, because a lot of
## code scans those); Enemy/Boss join it on their side.
##
## WHY A GROUP AND NOT A FLAG. Every spell spectacle in this codebase resolves its
## victims with exactly one call — `get_nodes_in_group(target_group)` — and that
## string is written in exactly one place, `_stamp()` below. So "friendly fire" is
## a policy change at ONE function rather than an edit to 21 dispatch arms and ~23
## spectacle scripts: point the stamp at a group that contains everybody and the
## spectacles change behaviour without changing a line.
##
## ⚠ DESTRUCTIBLES ARE DELIBERATELY *NOT* IN THIS GROUP, and that is a correction to
## the plan rather than an oversight. Every spectacle that scans `target_group` for
## fighters ALSO scans the `"destructible"` literal separately, right underneath, for
## crates. Putting crates in `mortal` too would make both scans find the same crate
## and every spell in the game would deal DOUBLE damage to cover. Cover is already
## faction-blind (it is a literal in every spectacle, hit by everyone), so it gains
## nothing from joining and loses correctness by doing so. `mortal` means FIGHTER.
const MORTAL_GROUP: StringName = &"mortal"

## Is friendly fire live? Per the mobile spec this is ON and stays on — it is the
## social engine of the whole game, not an option. It exists as a `static var`
## rather than a `const` for exactly two reasons: a headless test needs to assert
## the OLD faction-strict behaviour is still expressible (otherwise the test would
## have nothing to compare against), and a bisect needs a one-line off switch. It is
## NOT a gameplay setting and nothing in the UI writes it.
static var friendly_fire: bool = true

## The group an attack should actually scan, given the attacker's FACTION.
##
## Faction (`Hero.hostile_group`) stays the truth about who is on whose side — bots
## steer by it, `Spell._damage_hero` reasons about it, and "two bots on one team"
## is only expressible with it. What this does is separate that question ("who is my
## enemy") from the narrower one every damage scan actually asks ("who may this
## effect touch"), which under friendly fire is *everyone with a body*.
##
## Idempotent: `damage_group(MORTAL_GROUP) == MORTAL_GROUP`, so a caller that has
## already converted (Hero passes `attack_group()` into `cast()`) is not punished for
## it and the conversion can safely happen at more than one layer.
static func damage_group(faction: StringName) -> StringName:
	return MORTAL_GROUP if friendly_fire else faction


## Stamp the four pieces of IDENTITY every spectacle is entitled to, in ONE place:
## what it is made of, how much it WEIGHS in a clash, WHOSE it is, and WHO it is
## allowed to hurt.
##
## WHY A HELPER AND NOT THREE LINES PER ARM. A missing caster fails SILENTLY. The
## reaction layer asks a spectacle `reaction_owner()`; a null owner reports as
## "unowned"; and "unowned" satisfies neither `require_owner: "same"` nor
## `"different"`. So an un-stamped spectacle matches NO clash row at all and is quietly
## inert in the entire reaction system — nothing errors, nothing warns, the spell just
## never reacts with anything. That exact omission is what made Hollow Purple look
## broken for two whole sessions, and what left ZoneSpell unable to reach the
## steam_cloud / supercharge / field_merge rows already authored for it. With one
## dispatch seam and eighteen arms, "remember to add the line" is not a strategy —
## calling this from every arm is, because then forgetting is not expressible.
##
## `set()` on a property a spectacle has not declared yet is a silent no-op (verified
## against 4.6.2, not assumed), which is what makes this safe to land ahead of the ~15
## spectacles adopting `caster_node` / `spell_tier` one at a time. An arm whose
## spectacle lacks a field today simply starts working the day that field appears.
##
## The one thing this does NOT do is displacement: a spell that MOVES its caster still
## has to consume `caster` itself (see the BLINK_STRIKE arm), because that is
## behaviour, not identity.
##
## `target_group` is the FOURTH piece of identity, added for the same reason the
## other three are stamped here: thirteen spectacles already declare a
## `target_group` var (the Boss flips them to "hero"), but nothing on the CASTING
## side ever set it, so every spell this dispatcher built kept the `"enemy"`
## default no matter who threw it. That is why a hero-shaped bot could not hurt
## another hero with anything: the aim worked, the spectacle spawned, and then it
## scanned a group its target was not in.
##
## Two property names are written because the codebase uses both spellings: the
## public `target_group` (BeamSpell, BlastSpell, DivineRay, MeteorSigil,
## StarConvergence, RockPillar, EnergyNova, BoulderHurl, IceSpikeLine) and the
## private `_target_group` (DrainTether, HorizonArc, RiftDagger, ShadowCrawler),
## which those four flip themselves on a deflect. `set()` on a property a
## spectacle has not declared is a silent no-op (the same fact the stamps above
## rely on), so writing both is safe and neither name is lost.
##
## FRIENDLY FIRE ENTERS HERE, and only here. The group written is not the caller's
## faction but `damage_group(faction)` — the shared `mortal` group while friendly
## fire is on. That single substitution is the whole of the feature on the spell
## side: every spectacle keeps scanning `target_group` exactly as it always did and
## simply finds more bodies in it, including the caster's own teammates.
##
## The caster's OWN body is in that group too, which is what makes the per-spectacle
## self-exclusion audit load-bearing rather than paranoid — see
## `SpellTargets.hostiles()` / `SpellTargets.owner_of()`, which is where the
## exclusion is enforced now that "the caster is not in the group I scan" has
## stopped being true by construction.
static func _stamp(node: Node, elem: int, spell: SpellDef, caster: Node,
		target_group: StringName = &"enemy") -> void:
	var group: StringName = damage_group(target_group)
	node.set("element_id", elem)                  # elemental ailment applied on hit
	node.set("spell_tier", SpellTier.of(spell))   # SpellTier.Tier = its reaction WEIGHT
	node.set("caster_node", caster)               # the ownership predicate's whole input
	node.set("target_group", String(group))       # WHO it is allowed to hurt
	node.set("_target_group", String(group))      # ...under its other spelling


## Cast `spell` from `caster_pos` toward `target_pos`, parented under `arena`.
## `fallback_color` is the caster's current element colour (used when the SpellDef
## inherits). Returns true if a spectacle was spawned.
##
## `caster` is optional but is now stamped onto EVERY spectacle (see _stamp), not
## just the kinds that MOVE the caster. Two separate jobs share the one argument:
##   IDENTITY  — whose effect this is. Read by the reaction layer's ownership
##               predicate, and the difference between a spell that can clash/fuse
##               and one that is silently inert in that system. Every arm.
##   DISPLACEMENT — a spell that relocates the caster (today just BLINK_STRIKE)
##               consumes it directly; see the `blink_to` duck-typed contract on
##               that arm below.
## Omitting it still works — a null caster just means an unowned effect, exactly as
## before — so headless tools and capture scripts need not care.
##
## `target_group` names the group the spectacle is allowed to damage. It defaults
## to `&"enemy"` — the value every spectacle already hard-defaults to — so every
## existing caller, capture script and test is byte-identical and single player
## does not change by one branch. A caller only passes something else when it
## deliberately wants a different faction, which today means a bot-driven hero
## (see `Hero.hostile_group`).
## ⚠ THIS IS A WRAPPER. The 21-arm dispatch moved to `_dispatch` below, byte for
## byte, and this function is now the THREE THINGS THAT MUST HAPPEN AROUND EVERY
## CAST IN THE GAME rather than around some of them. All three come from the drop
## economy, and every one of them would have been a bug if bolted onto individual
## arms:
##
##   BEFORE — BLOOD PACT. `BloodPact.multiplier_for` is asked once, here, and the
##            spell is dispatched as a boosted DUPLICATE. Doing it per-arm would
##            have meant twenty-one chances to forget; doing it in place on the
##            SpellDef would have left the hero permanently buffed, because a
##            SpellDef is a Resource the hero keeps.
##   AFTER  — CHARGES. A Tier 3 boss drop has 1-2 uses. The charge is spent HERE,
##            on a cast that actually produced a spectacle, so a cast that fizzled
##            on a bad kind does not cost the player their only Void.
##   AFTER  — MIRROR IMAGE. A live clone repeats what its owner cast. Listening at
##            this one seam is what makes the clone work for heroes, bots and any
##            future co-op peer without any of them knowing clones exist.
##
## Signature, defaults and return value are unchanged, so every existing caller,
## capture script and test is byte-identical.
static func cast(
	spell: SpellDef, arena: Node, caster_pos: Vector2, target_pos: Vector2,
	fallback_color: Color, effect: String = "", caster: Node = null,
	target_group: StringName = &"enemy"
) -> bool:
	if spell == null or arena == null or not arena.is_inside_tree():
		return false
	var thrown: SpellDef = _blood_pacted(spell, caster, arena)
	if not _dispatch(thrown, arena, caster_pos, target_pos, fallback_color,
			effect, caster, target_group):
		return false
	# The ORIGINAL is what the charge is spent against and what the clone repeats —
	# never the boosted duplicate, which is a throwaway with the same id but a lie
	# for a damage number.
	SpellGrant.consume_charge(caster, spell)
	MirrorImage.echo(caster, spell, target_pos, spell.resolve_color(fallback_color),
		effect if effect != "" else spell.effect, arena)
	return true


## The spell as it should actually be thrown, given any Blood Pact its caster is
## under. Returns `spell` UNCHANGED when there is no pact, so the common path
## allocates nothing.
static func _blood_pacted(spell: SpellDef, caster: Node, ctx: Node) -> SpellDef:
	var mult: float = BloodPact.multiplier_for(caster, ctx)
	if mult <= 1.0 or spell.damage <= 0:
		return spell
	var boosted: SpellDef = spell.duplicate() as SpellDef
	boosted.damage = int(round(float(spell.damage) * mult))
	return boosted


static func _dispatch(
	spell: SpellDef, arena: Node, caster_pos: Vector2, target_pos: Vector2,
	fallback_color: Color, effect: String = "", caster: Node = null,
	target_group: StringName = &"enemy"
) -> bool:
	if spell == null or arena == null or not arena.is_inside_tree():
		return false
	var col: Color = spell.resolve_color(fallback_color)
	var fx: String = effect if effect != "" else spell.effect  # elemental character
	var elem: int = resolve_element(spell)  # ailment applied on hit
	var aim: Vector2 = (target_pos - caster_pos)
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	match spell.kind:
		SpellDef.Kind.BEAM:
			var beam: Node2D = (load(BEAM_PATH) as GDScript).new()
			arena.add_child(beam)
			# Two beams from the SAME caster inside the combo window fuse (Hollow
			# Purple's self-combo row); two casters' beams meeting is a separate,
			# rarer row. Both of those are unreachable without the caster stamp.
			_stamp(beam, elem, spell, caster, target_group)
			beam.fire(caster_pos, aim.normalized(), col, spell.length, spell.width, spell.damage, fx)
			return true
		SpellDef.Kind.DIVINE_RAY:
			# Lands on the ground point the player aims at, clamped to reach.
			var to: Vector2 = aim
			if to.length() > spell.reach:
				to = to.normalized() * spell.reach
			var ray: Node2D = (load(RAY_PATH) as GDScript).new()
			arena.add_child(ray)
			_stamp(ray, elem, spell, caster, target_group)
			ray.strike(caster_pos + to, col, spell.radius, spell.damage, fx)
			Juice.zoom_pull_camera(0.15, 0.45, 0.16, 0.55)  # pull back to reveal the pillar
			return true
		SpellDef.Kind.METEOR:
			# Rains on the ground point the player aims at, clamped to reach.
			var mto: Vector2 = aim
			if mto.length() > spell.reach:
				mto = mto.normalized() * spell.reach
			var meteor: Node2D = (load(METEOR_PATH) as GDScript).new()
			arena.add_child(meteor)
			_stamp(meteor, elem, spell, caster, target_group)
			meteor.rain(caster_pos + mto, col, spell.radius, spell.damage, spell.count, fx)
			Juice.zoom_pull_camera(0.2, 0.9, 0.2, 0.7)  # widest pull — the bombardment
			return true
		SpellDef.Kind.CONVERGENCE:
			# Converges on the ground point the player aims at, clamped to reach.
			var cto: Vector2 = aim
			if cto.length() > spell.reach:
				cto = cto.normalized() * spell.reach
			var conv: Node2D = (load(CONVERGENCE_PATH) as GDScript).new()
			arena.add_child(conv)
			_stamp(conv, elem, spell, caster, target_group)
			conv.converge(caster_pos + cto, col, spell.radius, spell.damage, fx)
			Juice.zoom_pull_camera(0.22, 1.0, 0.3, 0.8)  # longest tell, biggest reveal
			return true
		SpellDef.Kind.RUSH:
			# Chidori: a jagged lightning lance ripping along the aim from the caster.
			var rush: Node2D = (load(RUSH_PATH) as GDScript).new()
			arena.add_child(rush)
			_stamp(rush, elem, spell, caster, target_group)
			rush.call("rush", caster_pos, aim.normalized(), col, spell.length, spell.width, spell.damage, fx)
			return true
		SpellDef.Kind.NOVA:
			var nova: Node2D = (load(NOVA_PATH) as PackedScene).instantiate()
			arena.add_child(nova)
			_stamp(nova, elem, spell, caster, target_group)
			nova.call("activate_at", caster_pos)
			return true
		SpellDef.Kind.BOULDER:
			# Rips a boulder from the ground and hurls it along the aim.
			var b: Node2D = (load(BOULDER_PATH) as GDScript).new()
			arena.add_child(b)
			_stamp(b, elem, spell, caster, target_group)
			b.call("hurl", caster_pos, aim.normalized(), col, spell.radius, spell.damage, fx)
			return true
		SpellDef.Kind.PILLAR:
			# Erupts a stone pillar under the marked ground point (uppercut launch).
			var pto: Vector2 = aim
			if pto.length() > spell.reach:
				pto = pto.normalized() * spell.reach
			var pil: Node2D = (load(PILLAR_PATH) as GDScript).new()
			arena.add_child(pil)
			_stamp(pil, elem, spell, caster, target_group)
			pil.call("erupt", caster_pos + pto, col, spell.radius, spell.damage, fx)
			Juice.zoom_pull_camera(0.13, 0.4, 0.14, 0.5)
			return true
		SpellDef.Kind.WALL:
			# Raises a temporary blocking stone wall in the aim direction.
			var wl: Node2D = (load(WALL_PATH) as GDScript).new()
			arena.add_child(wl)
			# The rock-wall TWO-BEAT ("first press summons it, second press is the
			# punch that sends it") is built on RockWall.is_raised_by(), so the
			# wall has to know whose it is. It used to learn that from the caster
			# bracketing every cast with snapshot_shoveable()/adopt_new_shoveable()
			# — a workaround for this seam not forwarding the caster. Stamping it
			# here is the real answer; the bracket stays correct either way, since
			# adopt_new_shoveable() skips walls that already have an owner.
			_stamp(wl, elem, spell, caster, target_group)
			wl.call("raise_wall", caster_pos, aim.normalized(), col, fx)
			return true
		SpellDef.Kind.ICE_WALL:
			# Raises a temporary blocking ICE wall in the aim direction (chills on touch).
			var iw: Node2D = (load(ICE_WALL_PATH) as GDScript).new()
			arena.add_child(iw)
			_stamp(iw, elem, spell, caster, target_group)
			iw.call("raise_wall", caster_pos, aim.normalized(), col, fx)
			return true
		SpellDef.Kind.CHAIN:
			# A jagged bolt that leaps enemy-to-enemy from the caster along the aim.
			var ch: Node2D = (load(CHAIN_PATH) as GDScript).new()
			arena.add_child(ch)
			_stamp(ch, elem, spell, caster, target_group)
			ch.call("chain", caster_pos, aim.normalized(), col, spell.count, spell.reach, spell.damage, fx)
			return true
		SpellDef.Kind.ZONE:
			# Shadow is no longer a placed puddle recoloured from blizzard — it ERUPTS
			# from the caster's feet and races along the ground to ROOT whoever the
			# tendrils catch, with a real dodge window before the grip locks. Same
			# ZONE kind (so loadouts/saves are untouched); the spectacle forks here.
			if fx == "shadow":
				var sr: Node2D = (load(SHADOW_ROOT_PATH) as GDScript).new()
				arena.add_child(sr)
				_stamp(sr, elem, spell, caster, target_group)
				sr.call("erupt", caster_pos, aim, col, spell.radius, spell.damage, fx)
				Juice.zoom_pull_camera(0.12, 0.4, 0.14, 0.5)
				return true
			# A persistent ground field placed at the marked point (clamped to reach).
			var zto: Vector2 = aim
			if zto.length() > spell.reach:
				zto = zto.normalized() * spell.reach
			var zn: Node2D = (load(ZONE_PATH) as GDScript).new()
			arena.add_child(zn)
			# A FIELD is the side of steam_cloud / supercharge / field_merge that had
			# no implementor at all until ZoneSpell became a reaction participant.
			# Those rows are reachable only with an owner on the field.
			_stamp(zn, elem, spell, caster, target_group)
			# `length` doubles as the field lifetime for a ZONE (cast_time must stay 0
			# so it doesn't trigger the levitating channel); default 4.5s.
			var zlife: float = spell.length if spell.length > 0.5 and spell.length < 20.0 else 4.5
			zn.call("open", caster_pos + zto, col, spell.radius, spell.damage, fx, zlife)
			Juice.zoom_pull_camera(0.14, 0.5, 0.16, 0.55)
			return true
		SpellDef.Kind.MISSILES:
			# A fan of homing rune-orbs launched along the aim from the weapon tip.
			var mo: Node2D = (load(MISSILES_PATH) as GDScript).new()
			arena.add_child(mo)
			_stamp(mo, elem, spell, caster, target_group)
			mo.call("launch", caster_pos, aim.normalized(), col, spell.count, spell.damage, fx)
			return true
		SpellDef.Kind.TETHER:
			# A life-drain tether locking the nearest enemy in the aim direction.
			var te: Node2D = (load(TETHER_PATH) as GDScript).new()
			arena.add_child(te)
			_stamp(te, elem, spell, caster, target_group)
			# The caster goes in TWICE here, and the second one is not redundant.
			# The stamp above is IDENTITY (whose effect is this, for the reaction
			# layer's ownership predicate); this trailing argument is BEHAVIOUR — a
			# life-drain has to know whose health bar to fill. Without it DrainTether
			# falls back to _resolve_caster's "nearest node in group `hero` within
			# 140 px", which is right in single-player and WRONG in co-op: standing
			# close to your partner hands them your drain. Guessing the beneficiary
			# is the same shape of mistake as auto-aim guessing the victim, and not
			# guessing is a locked rule.
			#
			# ⚠ THE GENERAL POINT, because _stamp() does NOT cover this: caster
			# identity reaches a spectacle by two different mechanisms in this file —
			# as a PROPERTY (`caster_node`, uniform via _stamp) and as a positional
			# ARGUMENT to the entry function. Only three entry functions take one:
			# `tether(...)` here, `strike(...)` on BLINK_STRIKE, and
			# `throw_dagger(...)` on THROWN_ANCHOR. An arm can look fully stamped and
			# still be handing its spectacle no caster where it actually needs one,
			# so a new spectacle that adds a caster parameter needs a matching edit
			# HERE — the stamp will not cover it.
			te.call("tether", caster_pos, aim.normalized(), col, spell.damage, fx, caster)
			return true
		SpellDef.Kind.BLINK_STRIKE:
			# Shadow-step: the caster TELEPORTS to the marked point mid-slash, and the
			# cut lands along the path travelled. Previously this had no arm here at
			# all — Hero special-cased it, so blink was dead in every other caster
			# (the playground included). The displacement is delegated: a caster that
			# implements `blink_to(dest) -> Vector2` vets the landing spot (Hero
			# refuses to blink into a pit) and returns where it ACTUALLY ended up, so
			# the slash is drawn to the real destination. Casters without the method
			# still get the cut, they just don't move.
			var bto: Vector2 = aim
			if bto.length() > spell.reach:
				bto = bto.normalized() * spell.reach
			var dest: Vector2 = caster_pos + bto
			if caster != null and caster.has_method("blink_to"):
				dest = caster.call("blink_to", dest)
			var bs: Node2D = (load(BLINK_PATH) as GDScript).new()
			arena.add_child(bs)
			_stamp(bs, elem, spell, caster, target_group)
			# The trailing `caster` is what lets the blink rescue a BURIED body.
			# `Hero.blink_to` already refuses an illegal destination, but the
			# playground rig's `blink_to` teleports raw — so without this the
			# spell would correct where its BLAST lands while leaving the caster
			# standing inside terrain. Passing the caster arms `_rescue_caster()`,
			# which is written and documented in BlinkStrike but inert until it
			# has someone to rescue.
			bs.call("strike", caster_pos, dest, col, spell.damage, fx, caster)
			return true
		SpellDef.Kind.FLURRY:
			# A burst of dashing crescent slashes in front of the caster.
			var fl: Node2D = (load(FLURRY_PATH) as GDScript).new()
			arena.add_child(fl)
			_stamp(fl, elem, spell, caster, target_group)
			fl.call("flurry", caster_pos, aim.normalized(), col, spell.damage, spell.count, fx)
			return true
		SpellDef.Kind.CRAWLER:
			# A ground-hugging traveller launched from the caster's feet along the
			# aim. Nothing is clamped to reach here (unlike every placed spell
			# above): the strike point is EMERGENT, and `reach` is the crawler's own
			# travel budget rather than a distance to the cursor.
			var cr: Node2D = (load(CRAWLER_PATH) as GDScript).new()
			arena.add_child(cr)
			_stamp(cr, elem, spell, caster, target_group)
			cr.call("crawl", caster_pos, aim.normalized(), col, spell.reach,
				spell.radius, spell.damage, fx)
			Juice.zoom_pull_camera(0.10, 0.5, 0.12, 0.5)
			return true
		SpellDef.Kind.THROWN_ANCHOR:
			# One button, two beats: with a live anchor out, the press means RECALL.
			# Doing it here rather than only in Hero means every caster — playground
			# figure, bots, a future co-op peer — gets the second beat for free.
			if (load(DAGGER_PATH) as GDScript).try_recall(arena.get_tree(), caster):
				return true
			var dg: Node2D = (load(DAGGER_PATH) as GDScript).new()
			arena.add_child(dg)
			_stamp(dg, elem, spell, caster, target_group)
			dg.call("throw_dagger", caster, caster_pos, aim.normalized(), col,
				spell.reach, spell.radius, spell.damage, spell.length, spell.cooldown, fx)
			return true
		SpellDef.Kind.ARC:
			# A travelling curved WALL of edge that occupies a vertical BAND chosen by
			# the aim. Nothing is clamped to `reach` the way the placed bombardments
			# are: for this kind `length` is its own travel budget and `reach` is the
			# half-height it widens to, so clamping would silently truncate the sweep.
			var ha: Node2D = (load(ARC_PATH) as GDScript).new()
			arena.add_child(ha)
			_stamp(ha, elem, spell, caster, target_group)
			ha.call("sweep", caster_pos, aim.normalized(), col, spell.length,
				spell.width, spell.radius, spell.reach, spell.damage, fx)
			Juice.zoom_pull_camera(0.18, 0.9, 0.18, 0.65)  # pull back to reveal the crescent
			return true
		SpellDef.Kind.WARD:
			# Plants a protective gate on the ground along the aim. The caster is
			# LOAD-BEARING here rather than merely nice-to-have as it is for most
			# kinds: the ward publishes reaction_owner() AND excludes the caster's own
			# body from its floor/occupancy probes, so a ward cast without one can
			# refuse to plant on the very ground its caster is standing on.
			var wd: Node2D = (load(WARD_PATH) as GDScript).new()
			arena.add_child(wd)
			_stamp(wd, elem, spell, caster, target_group)
			wd.call("raise_ward", caster_pos, aim.normalized(), col, fx)
			return true
		SpellDef.Kind.HEX:
			# TIER 2 FLOOR PICKUP. One arm, four spells, forked on id (see
			# HEX_SCRIPTS). Every one of them takes the same entry function so the
			# arm never has to know which it built:
			#     hex(caster, origin, target, spell, color, fx)
			# `target` is clamped to reach here — the hex that places itself
			# (Petrify) wants that, and the ones that ignore position entirely
			# (Blood Pact, Mirror Image) are free to discard it.
			var hx_path: String = String(HEX_SCRIPTS.get(spell.id, ""))
			if hx_path == "":
				return false
			var hto: Vector2 = aim
			if spell.reach > 0.0 and hto.length() > spell.reach:
				hto = hto.normalized() * spell.reach
			var hx: Node2D = (load(hx_path) as GDScript).new()
			arena.add_child(hx)
			_stamp(hx, elem, spell, caster, target_group)
			hx.call("hex", caster, caster_pos, caster_pos + hto, spell, col, fx)
			return true
		SpellDef.Kind.CATACLYSM:
			# TIER 3 BOSS DROP. Roulette has no spectacle of its own — it rolls one
			# of the others and re-enters, which is why it is handled before the
			# table lookup rather than being a row in it.
			if spell.id == "roulette":
				return _roll_roulette(spell, arena, caster_pos, target_pos,
					fallback_color, effect, caster, target_group)
			var ct_path: String = String(CATACLYSM_SCRIPTS.get(spell.id, ""))
			if ct_path == "":
				return false
			var kto: Vector2 = aim
			if spell.reach > 0.0 and kto.length() > spell.reach:
				kto = kto.normalized() * spell.reach
			var ct: Node2D = (load(ct_path) as GDScript).new()
			arena.add_child(ct)
			_stamp(ct, elem, spell, caster, target_group)
			ct.call("cataclysm", caster, caster_pos, caster_pos + kto, spell, col, fx)
			Juice.zoom_pull_camera(0.24, 1.0, 0.24, 0.8)  # a boss drop reveals the room
			return true
		_:
			# Any unbuilt kind: safe no-op until its scene exists.
			return false


## ROULETTE. Rolls one of the three built Tier 3 workings and casts it, sometimes
## centred on the CASTER instead of on the aim.
##
## The rolled spell keeps its OWN stats — Roulette is not a cheap copy of The Void,
## it IS The Void when it rolls The Void, at full damage and full radius. What
## Roulette costs you instead is control: a quarter of the time it opens under your
## feet, and neither the roll nor the target is shown before it commits.
##
## Re-enters `_dispatch`, NOT `cast`: going back through the wrapper would spend a
## second charge and hand the mirror a second echo for one press.
static func _roll_roulette(
	spell: SpellDef, arena: Node, caster_pos: Vector2, target_pos: Vector2,
	fallback_color: Color, effect: String, caster: Node, target_group: StringName
) -> bool:
	var rolled_id: String = ROULETTE_POOL[randi() % ROULETTE_POOL.size()]
	var rolled: SpellDef = SpellLibrary.drop_by_id(rolled_id)
	if rolled == null:
		return false
	# The roll is announced by the SPECTACLE that arrives, not by a label — you
	# find out what you got the way everyone else in the room does.
	var at: Vector2 = target_pos
	if randf() < ROULETTE_SELF_CHANCE:
		# ...on YOU. Nudged off the caster's exact feet so the aim vector inside the
		# spectacle is never zero (a zero aim degrades to Vector2.RIGHT and would
		# quietly place the working to the caster's right instead of on them).
		at = caster_pos + Vector2(0.0, -1.0)
	return _dispatch(rolled, arena, caster_pos, at, fallback_color, effect,
		caster, target_group)


## Elemental ailment index (Elements.Element) a signature applies on hit: the
## SpellDef's explicit element if set, else mapped from its `effect` character.
static func resolve_element(spell: SpellDef) -> int:
	if spell.element >= 0:
		return spell.element
	match spell.effect:
		"frost":
			return Elements.Element.ICE
		"fire":
			return Elements.Element.FIRE
		"holy":
			return Elements.Element.LIGHTNING  # divine smite reads as a shock
		"arcane":
			return Elements.Element.ARCANE
		"lightning":
			return Elements.Element.LIGHTNING
		"shadow":
			return Elements.Element.SHADOW
		"earth":
			return Elements.Element.EARTH
		"wind":
			return Elements.Element.WIND
	return Elements.Element.ARCANE
