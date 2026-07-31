extends CharacterBody2D
## Slice 0 combat protagonist (the mage). Move now; dash + cast added next.

signal health_changed(current: int, maximum: int)
signal mana_changed(current: float, maximum: int)
signal signature_changed(display_name: String)

const SPEED: float = 210.0
## Mana (MP): gates the big SIGNATURE spectacle spells (the magic-circle beam /
## divine ray). Regenerates over time so ultimates are a paced resource, not
## spammable. Costs + cooldowns live per-spell on the SpellDef.
const MP_REGEN: float = 20.0  # mp/sec
const DASH_SPEED: float = 620.0
const DASH_TIME: float = 0.14
const DASH_COOLDOWN: float = 0.9  # was 0.55 — chained diagonal dashes let you "fly"
## Side-on platformer physics (Stick-Fight feel): asymmetric gravity (floaty
## apex, weighty landing), snappy accel + friction, WALL-SLIDE + WALL-JUMP so you
## can cling to and scale walls. Movement is horizontal (A/D); jump; dash.
const GRAVITY: float = 1500.0          # rise gravity (floaty apex)
const GRAVITY_FALL: float = 2100.0     # heavier coming down (weighty landing)
const MAX_FALL: float = 1000.0
const JUMP_VELOCITY: float = -580.0  # slightly higher jump (maker feedback)
const DOUBLE_JUMP_VELOCITY: float = -470.0
const MAX_AIR_JUMPS: int = 0  # no mid-air double-jump — wall-jump is the air move
const COYOTE_TIME: float = 0.10      # jump slightly after leaving a ledge
const JUMP_BUFFER_TIME: float = 0.10 # jump queued slightly before landing
const GROUND_ACCEL: float = 2600.0
const GROUND_FRICTION: float = 2900.0  # crisp stop with a hint of slide
const AIR_ACCEL: float = 1450.0        # strong air control (Stick-Fight)
## Wall-slide + wall-jump (the Stick-Fight wall tech): grip a wall while falling
## into it (clamped slide speed), then kick off away+up; a slide-then-jump boosts.
const WALL_SLIDE_MAX_FALL: float = 150.0
const WALL_STICK_PUSH: float = 6.0     # tiny into-wall x so is_on_wall stays true
const WALL_JUMP_PUSH: float = 300.0    # launch away from the wall (> SPEED)
const WALL_JUMP_UP: float = -460.0     # up kick — a diagonal arc, not a rocket
const WALL_JUMP_LOCKOUT: float = 0.15  # brief horizontal-input lock after the kick
const SLIDE_JUMP_BOOST: float = 1.25   # extra push jumping straight out of a slide
const CAST_COOLDOWN: float = 0.35
const MELEE_COOLDOWN: float = 0.34
const MELEE_DAMAGE: int = 14
const MELEE_RANGE: float = 58.0  # was 46 — short fists whiffed (Brawler LMB "not working")
const MELEE_ARC_DOT: float = 0.3
## Bumped for the Stick-Fight "shove" read — a connected punch should visibly
## launch the target, not just tick it.
const MELEE_KNOCKBACK: float = 300.0
## Short forward step on EVERY plain melee swing (Stick-Fight punches step INTO
## the hit). Softer than the combo/heavy-swing lunges (200/190) since this is
## the bare-fists baseline they build on top of.
const MELEE_LUNGE_SPEED: float = 170.0
## Small always-fires hitstop/shake so a swing reads even when it misses —
## much lighter than the on-connect Juice.on_hit cluster below.
const MELEE_SWING_HIT_STOP: float = 0.02
const MELEE_SWING_SHAKE: float = 1.5
## Ragdoll shove the hero RECEIVES (bomb blast / reflected bolt / slam) — decays
## like the enemy channel so a hit displaces you, then you regain control.
const KNOCKBACK_DECAY: float = 900.0
## Melee tuning per weapon kind; the MELEE_* consts are the "fists" baseline.
const WEAPON_STATS: Dictionary = {
	"fists": {"damage": MELEE_DAMAGE, "range": MELEE_RANGE, "knockback": MELEE_KNOCKBACK},
	"sword": {"damage": 26, "range": 60.0, "knockback": 400.0},
}
## After a fire-element melee the lead fist stays LIT for this long, the flame
## trailing embers as the hand moves (item 3). Strength decays with the timer.
const FLAMING_FIST_TIME: float = 1.6
const BLAST_COOLDOWN: float = 2.0
const BLAST_FALLBACK_RANGE: float = 200.0
## Meteor is player-placed at the cursor, clamped to this reach (skill-shot, not
## a cross-stage snipe).
const BLAST_MAX_RANGE: float = 480.0
## Blink teleport: instant reposition along facing with a shadow-poof at both
## the origin and the destination (the "yin-yang shadow step").
const BLINK_DISTANCE: float = 175.0
## Blink lands you THROUGH walls but never INSIDE one: probe the endpoint against
## solids (layer 1) and relocate to the nearest clear spot if it's blocked.
const BLINK_WALL_MASK: int = 1
const BLINK_PROBE_STEP: float = 6.0
const BLINK_PROBE_EXTRA: float = 60.0
const BLINK_COOLDOWN: float = 1.3
const BLINK_IFRAME: float = 0.22
## Share of a dash that is invulnerable, measured from its START. Below 1.0 the
## dash stops being a reactive get-out-of-jail button and becomes a commitment
## you have to read early — the tail of the dash can still be hit. This is the
## primary dial for how forgiving evasion feels; 1.0 restores the old behaviour.
const DASH_IFRAME_FRACTION: float = 0.6
## You may never blink OUT of the map — a landing spot inside a ring-out PIT (or
## within this margin of one) is rejected and pulled back toward the origin (maker:
## "you shouldn't be able to teleport out of the map ... limit it to where you
## actually can teleport"). Landing inside a solid is already rejected separately.
const BLINK_PIT_MARGIN: float = 22.0
const BLINK_SHADOW_COLOR: Color = Color(0.25, 0.1, 0.35, 0.8)
## Dark-violet particle poof; end alpha 0 so it dissolves instead of popping.
const BLINK_BURST_START: Color = Color(0.4, 0.18, 0.55, 0.9)
const BLINK_BURST_END: Color = Color(0.08, 0.03, 0.15, 0.0)
## Quick bright flash on arrival so the eye snaps to the new position.
const BLINK_ARRIVAL_FLASH_COLOR: Color = Color(0.85, 0.7, 1.0)
const BLINK_ARRIVAL_FLASH_TIME: float = 0.1
## Energy nova: self-centered instant shockwave — the "get off me" button.
## Bumped 3->5s: at 3s it was spammable enough to be oppressive.
const NOVA_COOLDOWN: float = 5.0
## Perfect-timing parry (rogue only): a short ACTIVE window that REVERSES an
## incoming enemy bolt back at the enemy side. Miss the window and you eat it.
const PARRY_WINDOW: float = 0.16
const PARRY_COOLDOWN: float = 0.9
const PARRY_FLASH_COLOR: Color = Color(0.8, 1.0, 1.0)
## The directional block SHELL lingers a touch longer than the active window so
## the deflect reads (the arc is the whole tell — no omni flash).
const PARRY_SHIELD_TIME: float = 0.26

## --- THE BLADE GUARD (Swordsaint) --------------------------------------------
## THE CLASS'S WHOLE IDENTITY IN ONE MECHANIC: it is the only class whose DEFENCE
## PRODUCES ITS OFFENCE. Everyone else guards to survive a beat; the Swordsaint
## guards to be PAID, and the payment is the biggest single number in its kit.
##
## The clock is `ParryRing` in `Style.BLADE` — NOT a third scheme. That file is
## explicit that a second timing implementation is how two guard paths drift apart
## ("one gets a balance tweak, the other silently does not"), so everything about
## WHEN the guard is good — the 0.42 s shrink, the ~0.09 s perfect band, the 0.35 s
## re-arm, the offence lock — is read from there and none of it is re-declared
## here. What lives here is only what happens AFTERWARDS, which is the part that is
## this class's rather than the ring's.
##
## BLADE is also the style with a SAFE FALLBACK: overshoot the band and steel is
## still in the way, so you bottom out into a chip-reducing sustained guard. That
## asymmetry against the mage's SIGIL (tighter band, longer re-arm, and a circle
## that catches nothing simply COLLAPSES) is already built and tested in ParryRing
## and SigilGuard; this class is the BLADE half of it, wired up.
##
## Only a PERFECT read banks. A sustained guard survives; it does not earn — or
## holding the button would be both the safe option and the strong one.
const GUARD_BANK_HITS: int = 3
## Cap on the banked total. Without it, one blocked boss slam (130) would return
## 234 from a single button, which is a bigger hit than any ult in the game.
const GUARD_BANK_CAP: int = 60
## What the bank pays back on release. Above 1.0 because the read is hard and the
## commitment is real — you gave up moving and attacking to earn it. 60 banked
## returns 108.
const GUARD_RETURN_MULT: float = 1.8
## The unsheathe cut: a short LINE along the aim, not a circle. Range is deliberately
## under the class's 86 px blade reach plus a step, so cashing the bank still requires
## the attacker to be in front of you rather than merely nearby.
const GUARD_CUT_RANGE: float = 120.0
const GUARD_CUT_HALF_WIDTH: float = 18.0
const GUARD_CUT_KNOCKBACK: float = 380.0
## Reach of the guard's own deflect sweep, in px from the body. The blade is held
## out, so this is arm's length plus the blade — anything that physically travels
## and touches it while the ring is PERFECT gets turned. There is no separate timing
## window: the ring is the window.
const GUARD_DEFLECT_REACH: float = 74.0
## Input buffer: a melee/dash/blast press that lands while its gate is closed
## (cooldown running, mid-dash) is held this long and fired the moment the
## gate opens — no more silently dropped presses. `cast` is held/continuous
## and stays un-buffered.
const BUFFER_TIME: float = 0.12
## Aim-stick deadzone: how far the AIM stick (right thumb on touch, `aim_*` actions)
## must be pushed before it re-points the aim. Below this the last aim is HELD, so
## lifting the thumb to tap an ability doesn't fling the shot somewhere random.
## This is the ONE owner of that number — TouchControls deliberately publishes the raw
## stick with no deadzone of its own, because a per-axis deadzone up there would carve
## dead sectors near the axes (a 5-degree-up shot snapping flat).
## UNTESTED FEEL GUESS — no device playtest has happened yet.
const TOUCH_AIM_DEADZONE: float = 0.20
## Hit feedback when damage actually lands (not i-framed).
const HURT_FLASH_COLOR: Color = Color(1.0, 0.2, 0.2)
const HURT_FLASH_TIME: float = 0.12
const HURT_HIT_STOP: float = 0.05
const HURT_SHAKE: float = 7.0
## Weighted hitstop: melee connect sits between spell hit and enemy death.
const MELEE_HIT_STOP: float = 0.07
## Directional camera punch along facing when a melee connects (px).
const MELEE_CAMERA_KICK: float = 5.0
## Dash afterimage cadence/tint (~4-5 ghosts across the 0.14s dash).
const GHOST_INTERVAL: float = 0.03
const GHOST_COLOR: Color = Color(0.6, 0.85, 1.0, 0.72)
## Persistent "charged mage" aura (enemies get none — hero reads as hero).
## Aura COLOUR comes from the active element (see _apply_element); only the
## strength is fixed here.
const AURA_STRENGTH: float = 0.6  # re-enabled: the HDR bloom pass now carries the
# glow as a soft halo instead of a flat sprite that obscured the figure.
## Body colourways (limb palette). Independent of the element — you can be a
## Jade stickman casting Fire. Cycled with `cycle_colourway` (C).
const COLOURWAYS: Array[Color] = [
	Color(0.4, 0.7, 1.0),  # Azure (the original hero blue)
	Color(1.0, 0.55, 0.35),  # Ember
	Color(0.6, 0.4, 0.95),  # Void
	Color(0.45, 0.9, 0.55),  # Jade
	Color(0.85, 0.85, 0.9),  # Mono
]
const SPELL_SCENE: PackedScene = preload("res://scenes/combat/Spell.tscn")
const BLAST_SCENE: PackedScene = preload("res://scenes/combat/BlastSpell.tscn")
const NOVA_SCENE: PackedScene = preload("res://scenes/combat/EnergyNova.tscn")

## EIGHT playable classes over ONE mobile-first slot system (see
## docs/superpowers/specs/2026-07-13-eight-class-roster-and-abilities.md). Each
## configures the SAME 7 slots with its own flavour — element, weapon, AoE
## variant, signature loadout — so touch controls never change but each class
## FEELS distinct. Enum names MAGE/ROGUE keep indices 0/1 (Arcanist/Shadowblade
## display names) so existing saves + tests stay valid; the mage config still
## equals the old consts, so index 0 is byte-identical to before.
##
## AoE (Q) variants: "blast" (placed meteor), "nova" (self whirlwind),
## "fist_shock" (fire-punch shockwave), "ground_slam" (earth crater). `element`
## is the class's default element (auto-set on switch; X still cycles). Signature
## loadout comes from SpellLibrary.build_for_class(class_id).
## APPEND ONLY. `_cycle_class` already wraps with `% HeroClass.size()`, but two
## places in the project hardcode the old count and must be widened alongside any
## addition here — `scripts/ui/Lobby.gd:83` (`% 8`, which would silently make a new
## class unselectable in co-op) and `tools/slice5_test_classes.gd`.
enum HeroClass { MAGE, ROGUE, BRAWLER, JUGGERNAUT, CLERIC, CRYOMANCER, STORMCALLER, WARLOCK, SWORDSAINT }
const CLASS_NAMES: Array[String] = [
	"Arcanist", "Shadowblade", "Brawler", "Juggernaut",
	"Cleric", "Cryomancer", "Stormcaller", "Warlock", "Swordsaint",
]
const CLASS_CONFIG: Dictionary = {
	HeroClass.MAGE: {  # ARCANIST — ranged arcane zoner (byte-identical to the old mage)
		"preset": "mage", "weapon": "", "element": Elements.Element.ARCANE, "melee_element": -1,
		"cast_cd": CAST_COOLDOWN, "dash_cd": DASH_COOLDOWN, "blink_cd": BLINK_COOLDOWN,
		"blast_cd": BLAST_COOLDOWN,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "arcane_meteor", "has_nova": true, "can_parry": true,  # Q: arcane star-fall
	},
	HeroClass.ROGUE: {  # SHADOWBLADE — twitchy assassin; LMB = 3-dagger flurry
		"preset": "rogue", "weapon": "sword", "element": Elements.Element.SHADOW, "melee_element": Elements.Element.SHADOW,
		"primary": "bolt", "bolt_burst": 3, "bolt_spread": 0.13,
		"cast_cd": 0.30, "dash_cd": 0.70, "blink_cd": 1.0,
		"blast_cd": 2.5,
		"throw_blade": true, "blade_damage": 9,
		"dash_strike": true, "dash_strike_damage": 16, "dash_strike_range": 42.0,
		"aoe": "nova", "has_nova": false, "can_parry": true,
	},
	HeroClass.BRAWLER: {  # PURE MELEE, no magic — punch/kick combo + double-jump + Thunderclap
		"preset": "brawler", "weapon": "", "element": Elements.Element.FIRE, "melee_element": Elements.Element.FIRE,
		"primary": "melee_combo", "air_jumps": 1, "melee_cd": 0.20, "melee_knockback": 320.0,
		"cast_cd": 0.22, "dash_cd": 0.70, "blink_cd": 1.1, "blast_cd": 2.2,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": true, "dash_strike_damage": 20, "dash_strike_range": 44.0,
		"mobility2": "uppercut", "aoe": "fist_shock", "has_nova": true, "can_parry": true,
	},
	HeroClass.JUGGERNAUT: {  # slow siege tank — wide heavy hammer, BLOCK, no blink
		"preset": "juggernaut", "weapon": "sword", "element": Elements.Element.EARTH, "melee_element": Elements.Element.EARTH,
		"primary": "heavy_swing", "melee_cd": 0.55, "melee_arc_dot": 0.0, "melee_damage": 30, "melee_range": 96.0, "melee_knockback": 470.0,
		"cast_cd": 0.40, "dash_cd": 0.90, "blink_cd": 1.4, "blast_cd": 2.6,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": true, "dash_strike_damage": 22, "dash_strike_range": 48.0,
		"defense": "block", "aoe": "ground_slam", "has_nova": true, "can_parry": true,
	},
	HeroClass.CLERIC: {  # radiant sustain bruiser — LMB heal-bolt (lifesteal)
		"preset": "cleric", "weapon": "staff", "element": Elements.Element.HOLY, "melee_element": Elements.Element.HOLY,
		"primary": "bolt", "bolt_heal": 4,
		"cast_cd": 0.32, "dash_cd": 0.85, "blink_cd": 1.2, "blast_cd": 2.4,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "consecrate", "has_nova": true, "can_parry": true,  # Q: consecrated ground
	},
	HeroClass.CRYOMANCER: {  # ice control — LMB is a FROST CONE, not a bolt
		"preset": "cryomancer", "weapon": "staff", "element": Elements.Element.ICE, "melee_element": Elements.Element.ICE,
		"primary": "frost_cone",
		"cast_cd": 0.34, "dash_cd": 0.90, "blink_cd": 1.2, "blast_cd": 2.6,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "ice_shards", "has_nova": true, "can_parry": true,  # Q: homing frost shards
	},
	HeroClass.STORMCALLER: {  # hyper-mobile chain caster — LMB arcs, fast wind-dash
		"preset": "stormcaller", "weapon": "staff", "element": Elements.Element.LIGHTNING, "melee_element": Elements.Element.LIGHTNING,
		"primary": "bolt", "bolt_chain": 2,
		"cast_cd": 0.30, "dash_cd": 0.55, "blink_cd": 1.0, "blast_cd": 2.4,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "call_lightning", "has_nova": true, "can_parry": true,  # Q: lightning strike column
	},
	HeroClass.WARLOCK: {  # dark attrition hexer — LMB drain-bolt (weaken + lifesteal)
		"preset": "warlock", "weapon": "sword", "element": Elements.Element.SHADOW, "melee_element": Elements.Element.SHADOW,
		"primary": "bolt", "bolt_heal": 3,
		"cast_cd": 0.30, "dash_cd": 0.85, "blink_cd": 1.1, "blast_cd": 2.5,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": false, "dash_strike_damage": 0, "dash_strike_range": 0.0,
		"aoe": "curse_chain", "has_nova": true, "can_parry": true,  # Q: leaping shadow chain
	},
	# 8 SWORDSAINT — the DUELIST. The only class whose DEFENCE produces its OFFENCE:
	# every other class guards to survive a beat, this one guards to be paid. See the
	# BLADE-GUARD block below for the whole identity.
	#
	# `defense: "held_guard"` is the switch. It routes RMB onto ParryRing's BLADE
	# style — a visible ring you close on the hit rather than a hidden 0.16 s window —
	# and banks what it turns away into an unsheathe cut on release.
	#
	# NO BLINK (`blink_cd` is left at a real value only because `_blink()` reads it;
	# `mobility2: "uppercut"` sends R to the rising cut instead, so this class has no
	# teleport at all). It closes on foot or by dash-strike and does not teleport out
	# of its own mistakes — the same trade Juggernaut makes.
	#
	# `melee_element: -1` is deliberate and is the class's whole flavour rule: PLAIN
	# STEEL APPLIES NO AILMENT. Give the Swordsaint a burn and it becomes "the fire
	# melee class"; the point is that the blade is just a blade, and the X-cycle only
	# tints the edge (which is what still feeds the reaction layer).
	#
	# `preset: "rogue"` because CharacterRig ships no "swordsaint" arm and an
	# unmatched preset name silently leaves the PREVIOUS class's kit on the figure.
	# "rogue" is hood + sword, and `get_weapon_tip()` gives "sword" a real
	# `height * 0.5` reach. A bespoke preset with a two-handed greatsword is a
	# CharacterRig change and is reported in the handoff, not faked here.
	HeroClass.SWORDSAINT: {
		"preset": "rogue", "weapon": "sword",
		"element": Elements.Element.ARCANE, "melee_element": -1,  # plain steel: no ailment
		"primary": "heavy_swing",
		# The greatsword profile, expressed as melee overrides rather than a new
		# WEAPON_STATS row: a "greatsword" kind would have no rig texture and no
		# `get_weapon_tip` arm, so the blade would vanish and every spell would spawn
		# out of the hero's navel. Slower and wider than the Shadowblade, shorter and
		# far more controllable than the Juggernaut's 96 px hammer.
		"melee_cd": 0.42, "melee_arc_dot": 0.05, "melee_damage": 26,
		"melee_range": 86.0, "melee_knockback": 430.0,
		"cast_cd": 0.45, "dash_cd": 0.80, "blink_cd": 1.2, "blast_cd": 3.0,
		"throw_blade": false, "blade_damage": 18,
		"dash_strike": true, "dash_strike_damage": 24, "dash_strike_range": 52.0,
		"mobility2": "uppercut",  # a rising cut, not a teleport
		"defense": "held_guard", "aoe": "ground_slam",
		"has_nova": false, "can_parry": true,
	},
}

@export var max_hp: int = 100
var hp: int = 100
## SANDBOX Smash model (GameState.ringout_mode): instead of draining hp, hits pile
## onto this damage_pct, and knockback scales with it (higher % = you fly farther).
## Reset to 0 on a ring-out respawn (VersusArena._respawn). Tower mode ignores it.
var damage_pct: float = 0.0
## ⚠ MANA NO LONGER GATES ANYTHING. Per the mobile spec — "Cooldowns, not mana. Mana
## makes people hoard and play safe, which is the opposite of what this game wants" —
## `_cast_signature` no longer checks or spends it. The pool is still tracked and still
## regenerates (so it reads full, and so `mana_changed` keeps its subscribers), but
## nothing can run out of it and no cast is ever refused for it.
##
## WHY THE FIELDS SURVIVE RATHER THAN BEING DELETED. `SpellDef.mp_cost` is read by two
## systems that have nothing to do with resource management: `SpellTier.of()` uses it
## as one of three shelf thresholds (>= 70 forces ULT), which is ALSO the reaction
## clash weight and the loadout slot rule; and the cast/channel sigils scale their
## radius by it, so the tell of a big spell is literally sized from its cost. Deleting
## the field would silently reshelve spells and shrink their telegraphs — an expensive
## change to save a float per hero.
##
## There is no mana UI to hide: `CharacterBars.configure(show_mp)` defaults to false
## and no caller has ever passed true, so the bar has never been drawn.
@export var max_mp: int = 100
var mp: float = 100.0
## Equipped SIGNATURE loadout (SpellLibrary) — the spell tree the player cycles
## (V) and unleashes (Ultimate key), MP-gated with a per-spell cooldown.
var _signatures: Array = []
var _signature_index: int = 0

## PER-SLOT COOLDOWNS, owned by `HandSlots`.
##
## This used to be a single `_signature_cd_timer` float: ONE bank shared by the whole
## kit, so throwing a 1.2 s jab locked your 9 s ult for 1.2 s and — much worse —
## throwing the ult locked every other spell in the kit for nine seconds. With three
## spell buttons on the right thumb that is not a balance quirk, it is the buttons not
## working: two of the three are dark most of the fight for reasons the player cannot
## see, because the bar was showing three cooldowns that were secretly one number.
##
## `HandSlots` already implemented real per-slot cooldowns (`start_cooldown` / `tick`
## / `is_ready`), fully headless-tested, and was used by nothing but the spike
## playground and `LoadoutBar`. This is that code finally being called by the shipped
## hero rather than a second implementation of it.
##
## ⚠ THE INDEX OFFSET. `HandSlots` always keeps FISTS at index 0 so a player can never
## end up with no melee option, so signature slot `i` lives at hand index `i + 1`.
## Never index `_hand` with a signature index directly — go through `_hand_slot()`.
var _hand: HandSlots = HandSlots.new()
const HAND_SPELL_OFFSET: int = 1
## Twin-stick: `facing`/`_aim_dir` track the CURSOR (drive casts, melee arc, cast
## pose, camera peek); `_move_dir` tracks WASD (drives dash + blink dodge). They
## are decoupled so you can run one way while aiming/casting another (strafe).
var facing: Vector2 = Vector2.RIGHT

## Co-op: the class comes from the lobby (net_class >= 0), not GameState. `_net`
## caches /root/Net so the per-frame authority check is cheap. Singleplayer leaves
## net_class at -1 and _net.is_active() false, so nothing below changes SP.
var net_class: int = -1
var _net: Node = null
var _aim_dir: Vector2 = Vector2.RIGHT
var _move_dir: Vector2 = Vector2.RIGHT
var is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _ghost_timer: float = 0.0
var _cast_cooldown_timer: float = 0.0
var _melee_cooldown_timer: float = 0.0
var _melee_kick_next: bool = false
var _flaming_fist_timer: float = 0.0
var _fist_ember_timer: float = 0.0
var _last_hand_pos: Vector2 = Vector2.ZERO
var _blast_cooldown_timer: float = 0.0
var _blink_cooldown_timer: float = 0.0
var _blink_iframe_timer: float = 0.0
var _nova_cooldown_timer: float = 0.0
var _parry_window_timer: float = 0.0
var _parry_cooldown_timer: float = 0.0
var _parry_window_len: float = PARRY_WINDOW  # per-class (Juggernaut BLOCK = longer window)
## The BLADE guard ring — non-null ONLY for a class whose `defense` is
## "held_guard" (today: Swordsaint). Null everywhere else, so all eight shipped
## classes keep the press-window parry they were balanced against and nothing about
## their defensive feel moves. Migrating the other eight onto the ring is a real
## improvement and a separate change; doing it inside a new class's commit would
## retune eight classes under cover of adding a ninth.
var _guard: ParryRing = null
var _guard_bank: int = 0
var _guard_hits: int = 0
var _wall_jump_lock: float = 0.0   # horizontal-input lock after a wall-kick
var _was_wall_sliding: bool = false
var _wall_dust_timer: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _air_jumps: int = 0
var _max_air_jumps: int = 0  # per-class air jumps (Brawler double-jumps); set in configure_class
var _was_on_floor: bool = true  # for the landing-dust transition edge
var _weapon: String = "fists"
var _melee_damage: int = MELEE_DAMAGE
var _melee_range: float = MELEE_RANGE
var _melee_knockback: float = MELEE_KNOCKBACK
var _melee_cd: float = MELEE_COOLDOWN     # per-class swing cadence (Brawler fast, Juggernaut slow)
var _melee_arc_dot: float = MELEE_ARC_DOT # per-class arc width (Juggernaut swings wide)
var _buffered_action: String = ""
var _buffer_timer: float = 0.0
var _knockback: Vector2 = Vector2.ZERO  # shove received from an enemy hit / bomb
var _ragdolling: bool = false  # hold DOWN -> go limp + flop (the Stick-Fight ragdoll toy)
var _hero_class: int = HeroClass.MAGE
var _cfg: Dictionary = CLASS_CONFIG[HeroClass.MAGE]
var _dash_hit: Array = []  # enemies/props already struck this dash (rogue no-multi-hit)
## Active element (aura + ability colour). Cycled with `cycle_element` (X).
var _element: int = Elements.Element.ARCANE
var _element_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## GEAR EFFECTS (GearAbilities): aggregated from the equipped weapon/head/body and
## applied at single clean hooks — an elemental weapon overrides `_element`, melee
## mults rescale the melee profile, the hat rescales max HP, the hood rescales move
## speed, the robe wards the first hit each fight. Recomputed idempotently from the
## class BASE in _recompute_gear_effects (safe to re-run on a loadout swap).
const BASE_MAX_HP: int = 100
const GEAR_ELEMENT: Dictionary = {
	"arcane": Elements.Element.ARCANE, "ice": Elements.Element.ICE,
	"lightning": Elements.Element.LIGHTNING, "holy": Elements.Element.HOLY,
	"shadow": Elements.Element.SHADOW, "fire": Elements.Element.FIRE,
	"earth": Elements.Element.EARTH,
}
var _gear_speed_mult: float = 1.0
# Gear mitigation moved to GuardComponent (see _apply_gear / take_damage) so ward
# spells, armour and the one-shot robe all resolve through a single path.
## Class melee/HP base snapshot (captured post-class-setup incl. equip_weapon) that
## the gear mults scale FROM — so _recompute is idempotent and never clobbers the
## weapon-specific melee tuning equip_weapon already applied.
var _base_melee_damage: int = MELEE_DAMAGE
var _base_melee_knockback: float = MELEE_KNOCKBACK
var _base_melee_cd: float = MELEE_COOLDOWN
var _base_max_hp: int = BASE_MAX_HP
var _base_element: int = Elements.Element.ARCANE  # class innate element (revert target)
## The player's LOADOUT choices (from the hub Armory). Only these override the class
## and grant gear abilities — class-default gear stays cosmetic + as-tuned, so a class
## you never re-geared plays exactly as balanced. slot -> kind.
var _gear_override: Dictionary = {}
var _colourway: int = 0
## Mobile: set by TouchControls when the on-screen pad is active (or true on any
## touchscreen). Switches aim from the cursor to auto-target the nearest enemy so
## every ability works by tapping a button — no pixel-precise aiming (mobile-first).
var touch_input: bool = false

## Co-op: a died hero is DOWNED (ragdoll, no input, damage-immune) instead of
## instantly reviving — enemies ignore it and the party stays in the fight. When
## EVERY hero is downed the host drops the party a floor (revives all). Synced so
## the host + peers can read each hero's state. SP never sets this (Hero._die keeps
## the old fall/reset). Public for the MultiplayerSynchronizer property path.
var downed: bool = false

@onready var rig: CharacterRig = $Rig
var _tuning: Node = null  # cached /root/Tuning (null in headless tests -> fallbacks)

# ------------------------------------------------- FACTIONS + BOT CONTROL SEAM
## THE GROUP THIS HERO'S ATTACKS SCAN — its faction, expressed the way targeting
## already works everywhere else in this codebase.
##
## Damage routing here used to be group-HARDWIRED rather than faction-based: the
## melee/dash/uppercut sweeps iterated `get_nodes_in_group("enemy")` as a literal,
## `_fire_punch` / `_ground_slam` hard-coded `"target_group": "enemy"`, and
## `SpellCaster.cast` had no group parameter at all, so every spectacle kept its
## `"enemy"` default whoever threw it. The consequence was that a hero-shaped bot
## could be driven perfectly and still could not fight ANYONE: it ignored other
## heroes completely, and in single player hero-vs-hero did literally nothing in
## either direction.
##
## Default `&"enemy"` = exactly today's behaviour, everywhere, so single player is
## unchanged unless a caller deliberately opts in.
var hostile_group: StringName = &"enemy"
## The team group this hero ANSWERS to, joined on top of the permanent `hero`
## group. Empty = no team, which is single player.
##
## This is the half that makes "same faction cannot hurt each other" expressible
## rather than just "heroes can hurt heroes": two bots on one side share a team
## group and both point `hostile_group` at the OTHER team's, so neither one's
## attacks can find the other at all. With `hostile_group = &"hero"` alone the
## only reachable arrangement is everyone-hits-everyone.
@export var faction_group: StringName = &""
## The per-instance input source. `null` = the human path — real `Input`, real
## cursor, byte-identical to before this seam existed, which is why every helper
## below is written as `controller != null` and not the other way round.
##
## Untyped so a scripted stub (a test, a replay) only has to implement the six
## polling methods, matching how the rest of this codebase duck-types its seams.
## In practice this is a `BotController`; see that file for why global
## `Input.action_press` cannot do this job.
var controller: Object = null
## The bot's own clock, advanced on SCALED delta. It exists so a bot's reaction
## timing lives on the SAME clock the player perceives: `Juice.hit_stop` drops
## `Engine.time_scale` to 0.05, so a bot ticking on unscaled time would get a
## ~20x reflex boost every time anything connected — a difficulty cheat that
## would look like physics.
var _bot_clock: float = 0.0


## Join a faction: which team I am on, and which team I attack. One call because
## setting one without the other is always a bug — a hero with a team but no
## hostile group attacks nobody, and one with a hostile group but no team cannot
## be attacked back.
##
## Safe before OR after the node enters the tree: `_ready` re-joins the group, and
## this joins immediately when already inside.
func set_faction(team: StringName, hostile: StringName) -> void:
	faction_group = team
	hostile_group = hostile
	if team != &"" and is_inside_tree():
		add_to_group(team)


## THE GROUP THIS HERO'S ATTACKS ACTUALLY SCAN — `hostile_group` with friendly fire
## folded in. Every damage sweep in this file goes through this; nothing else does.
##
## ⚠ THE SPLIT MATTERS, and collapsing it would be the obvious wrong shortcut.
## `hostile_group` is FACTION — "whose side am I not on". It is read by `BotBrain`
## through `bot_body_state()`, by `Spell._damage_hero`'s permission ladder, and it is
## the only way "two bots on one team" is expressible at all. Overwrite it with
## `mortal` and every bot in the game immediately treats its own teammates as the
## enemy it should be walking toward.
##
## What an ATTACK asks is the narrower question — "who may this blow touch" — and
## under friendly fire the answer is *everyone with a body*. So the faction stays put
## and the attack scans widen. One consequence worth stating out loud because it is
## the entire feature: your teammate is in this group, and the spec wants them there.
func attack_group() -> StringName:
	return SpellCaster.damage_group(hostile_group)


## SELECT A KIT SPELL BY INDEX — the seam that makes a bot able to use its whole
## kit at all.
##
## `cast_slot` indexes `_signatures`, which `SpellLibrary.build_for_class` returns
## in `ROLE_ORDER` (damage / control / answer / payoff / ult), so `idx` IS the
## role for every class.
##
## ⚠ WHY THIS EXISTS RATHER THAN A BOT PRESSING `cycle_signature`. That action is
## SHARED UI: it is the player's V key, it walks the selection one step at a time
## (so reaching slot 3 takes three presses and passes through two wrong spells),
## and pressing it through global `Input` would cycle the HUMAN'S selection too.
## `BotController` therefore keeps `cycle_signature` permanently forbidden and
## comes here instead. Without this method a bot can only ever cast whichever
## signature happened to be selected — i.e. it spams one spell forever, which is
## exactly what it did before this landed.
##
## Deliberately does NOT emit `signature_changed`: that signal drives the player's
## on-screen loadout label, and a bot silently retargeting its own kit must not
## make the human's HUD flicker through spell names they did not choose.
## Returns false for an out-of-range index rather than clamping, so a brain bug
## reads as "the cast did not happen" instead of as a plausible wrong spell.
func bot_select_signature(idx: int) -> bool:
	if idx < 0 or idx >= _signatures.size():
		return false
	_signature_index = idx
	return true


## The spell currently selected for the `ultimate` button, or null.
func signature_at(idx: int) -> SpellDef:
	if idx < 0 or idx >= _signatures.size():
		return null
	return _signatures[idx] as SpellDef


## Everything a bot brain is allowed to know about THIS body, in the blackboard's
## key names. Lives here rather than in BotController so the private cooldown
## timers stay private and so any other body type (an Enemy, later) can become
## bot-drivable by implementing this one method.
##
## FAIRNESS: own state only. Every field is something the player reads off their
## own screen — their body, their floating HP/MP bars, their ability bar, their
## own class and its loadout. There is deliberately no field describing the
## OPPONENT'S cooldowns, mana or intent.
func bot_body_state() -> Dictionary:
	var cds: Array[float] = []
	for _i: int in BotIntent.CD_COUNT:
		cds.append(0.0)
	# PER-SLOT, and now genuinely so. This used to publish the single shared bank
	# under every slot index — the shape was already right ("ask cooldowns[cast_slot]")
	# and the numbers were a lie, so a brain that reasoned about which slot to reach
	# for was reasoning about one timer wearing five hats.
	#
	# Slots past the kit's size report 0.0 (ready). `slot_affordable` below is what
	# actually tells a brain those slots hold nothing, and it is the stricter answer.
	for slot: int in BotIntent.SLOT_COUNT:
		cds[slot] = signature_cooldown(slot)
	cds[BotIntent.CD_PRIMARY] = _cast_cooldown_timer
	cds[BotIntent.CD_DASH] = _dash_cooldown_timer
	cds[BotIntent.CD_BLAST] = _blast_cooldown_timer
	cds[BotIntent.CD_BLINK] = _blink_cooldown_timer
	cds[BotIntent.CD_NOVA] = _nova_cooldown_timer
	cds[BotIntent.CD_SWING] = _melee_cooldown_timer
	# The defensive slot is two different verbs behind one button, so the number
	# published is the one the ability bar shows: a press class reports its wipe,
	# a held-guard class reports its re-arm.
	cds[BotIntent.CD_GUARD] = _parry_cooldown_timer
	if _guard != null:
		cds[BotIntent.CD_GUARD] = 0.0 if _guard.is_ready() else _guard.rearm_time()
	# Per-kit-slot facts a brain cannot derive from `class_id` alone because they
	# move at runtime: can I actually throw this right now, and does it commit me to
	# an interruptible levitating channel (`cast_time > 0`) that any landed hit
	# shatters.
	#
	# ⚠ `slot_affordable` KEPT ITS NAME AND CHANGED ITS MEANING, deliberately. Mana no
	# longer gates a cast (see `_cast_signature`), so `mp >= mp_cost` was about to
	# become permanently true and the field would have quietly stopped carrying any
	# information at all — a blackboard key that always says yes is worse than no key,
	# because a brain keeps consulting it. It now means "this slot exists AND is off
	# cooldown", which is the question the old field was a proxy for, and it is the
	# answer that also stops a bot reaching for a slot its class does not have now
	# that kits are three spells and `BotIntent.SLOT_COUNT` is still five.
	var affordable: Array[bool] = []
	var cast_times: Array[float] = []
	for slot: int in BotIntent.SLOT_COUNT:
		var s: SpellDef = signature_at(slot)
		affordable.append(s != null and signature_ready(slot))
		cast_times.append(s.cast_time if s != null else 0.0)
	return {
		"self_id": get_instance_id(),
		"self_pos": global_position,
		"self_vel": velocity,
		"self_hp_frac": clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0),
		"self_mp_frac": clampf(mp / float(maxi(max_mp, 1)), 0.0, 1.0),
		"on_floor": is_on_floor(),
		"facing": signf(facing.x),
		"reach": _melee_range,
		"cooldowns": cds,
		"hostile_group": hostile_group,
		# WHICH CLASS I AM. Unlocks the kit facts, the role meanings and every
		# reaction combo for a brain that wants to look them up in SpellLibrary.
		# Fair: it is your own character, named on your own HUD.
		"class_id": _hero_class,
		"slot_affordable": affordable,
		"slot_cast_time": cast_times,
		# The defensive verb, which differs in KIND and not just in numbers: 0 = a
		# press window (most classes), 1 = a held BLADE ring with its own much
		# narrower perfect band. A brain that times a guard identically for both
		# is wrong for one of them.
		"guard_style": 1 if _guard != null else 0,
		"can_parry": bool(_cfg.get("can_parry", false)),
	}


# --- the six polling helpers every input call site in this file now goes through.
# With `controller == null` each one resolves to the IDENTICAL `Input` call it
# replaced — same order, same allocation, no branch reordering — which is the
# whole basis for claiming single player is unchanged. TouchControls also keeps
# working untouched, because it drives these same named actions through global
# `Input`, which is still exactly the null-controller path.

func _pressed(action: StringName) -> bool:
	return controller.pressed(action) if controller != null else Input.is_action_pressed(action)


func _just(action: StringName) -> bool:
	return controller.just_pressed(action) if controller != null \
		else Input.is_action_just_pressed(action)


func _released(action: StringName) -> bool:
	return controller.just_released(action) if controller != null \
		else Input.is_action_just_released(action)


func _axis(neg: StringName, pos: StringName) -> float:
	return controller.axis(neg, pos) if controller != null else Input.get_axis(neg, pos)


func _vector(nx: StringName, px: StringName, ny: StringName, py: StringName) -> Vector2:
	return controller.vector(nx, px, ny, py) if controller != null \
		else Input.get_vector(nx, px, ny, py)


## Replaces `get_global_mouse_position()`. A bot has no cursor, so its controller
## projects a point along the direction its brain chose — which is why this is a
## world POINT and not a direction: the placed spells (`_aoe_target`, the summon
## target) need real ground coordinates, and only the controller knows how far
## down the aim the bot meant.
func _aim_point() -> Vector2:
	return controller.aim_point(global_position) if controller != null \
		else get_global_mouse_position()


## Live-tunable feel value: reads res://data/tuning.tres via the Tuning autoload,
## falling back to the const default if the autoload/field is absent or unset.
func _tune(key: String, fallback: float) -> float:
	if _tuning != null and _tuning.cfg != null:
		var v: Variant = _tuning.cfg.get(key)
		if v != null:
			return float(v)
	return fallback


func _ready() -> void:
	add_to_group("hero")
	# FRIENDLY FIRE, the hero half. `mortal` is the shared "I am a damageable
	# fighter" group every spell scans once friendly fire is on (see
	# SpellCaster.MORTAL_GROUP); Enemy/Boss join it from their side.
	#
	# ADDED, never swapped. `hero` is identity and is scanned by ~40 places — the
	# camera's framing, the encounter's party-wipe check, enemy target selection,
	# Arena's spawn logic. Removing it to "clean up" would silently break all of
	# them, which is exactly the group-drift trap this codebase has been bitten by
	# twice already ("hero" the tower group vs "player" the old hub group).
	add_to_group(SpellCaster.MORTAL_GROUP)
	# Team membership, when a spawner set one before add_child(). The permanent
	# `hero` group above is identity ("I am a hero"); this one is allegiance, and a
	# hero with no team simply never joins a second group — which is single player.
	if faction_group != &"":
		add_to_group(faction_group)
	_tuning = get_node_or_null("/root/Tuning")
	hp = max_hp
	health_changed.emit(hp, max_hp)
	rig.set_tint(COLOURWAYS[_colourway])
	rig.set_aim_arm(true)  # twin-stick: the lead hand always aims at the cursor
	# Class comes from the co-op lobby (net_class) first, else GameState, else MAGE.
	_net = get_node_or_null("/root/Net")
	var gs: Node = get_node_or_null("/root/GameState")
	var start_class: int = HeroClass.MAGE
	if net_class >= 0:
		start_class = net_class
	elif gs != null:
		var sc: Variant = gs.get("selected_class")
		if sc != null:
			start_class = int(sc)
	# configure_class sets the class element, rig preset, weapon, AND the class's
	# signature loadout (SpellLibrary.build_for_class) + emits signature_changed.
	configure_class(start_class)  # also applies the hub Armory loadout (GameState.loadout)
	_setup_net_role()
	mp = float(max_mp)
	mana_changed.emit(mp, max_mp)
	# Rank drives aura TIER (elaborateness); the element keeps driving COLOUR.
	Rank.rank_changed.connect(_on_rank_changed)
	rig.set_aura_tier(Rank.tier())
	rig.hit_frame.connect(_on_melee_hit_frame)
	# Footfalls come off the RIG's own run cycle, not a timer here. The rig watches the
	# same phase expression the pose is drawn from, so the step can never drift off the
	# visible feet and retuning the stride moves the sound with it. `step_sfx` is off by
	# default because the same rig drives every enemy (eight of them ticking would be a
	# cacophony) — the HERO opts in. The parallel _footstep_timer that used to live in
	# _physics_process is GONE: two footstep clocks fighting each other sounded worse
	# than the original stacking bug.
	rig.step_sfx = true
	rig.foot_planted.connect(_on_foot_planted)
	# Floating HP + MP bars over the head.
	var bars := CharacterBars.new()
	add_child(bars)
	bars.configure(self, true, -26.0)


## Float-channel: the 4 big spectacles (beam/ray/meteor/convergence) become a
## committed levitating cast. Press G -> the hero lifts off + a build-up sigil
## grows for cast_time; if a hit lands the channel is INTERRUPTED (cast lost, mana
## + cooldown already spent). Survive it and the ultimate unleashes.
const CHANNEL_LIFT_HEIGHT: float = 34.0
const CHANNEL_LIFT_SPEED: float = 180.0
var _channeling: bool = false
var _channel_timer: float = 0.0
var _channel_total: float = 0.0
var _channel_spell: SpellDef = null
var _channel_target: Vector2 = Vector2.ZERO
var _channel_sky: bool = false
var _channel_lift: float = 0.0
var _channel_base_y: float = 0.0

## Epic SUMMON windup: every INSTANT signature (ice_wall / chain / rune_orbs /
## flurry / void_zone / tether / boulder / pillar / wall / rush / blink) blooms a
## spell-circle + a committed cast pose + gather motes for a short beat, THEN
## ERUPTS (maker: "ice is cringe — no spell circle, no summoning animation; they
## ALL need that for the G's ESPECIALLY"). Interruptible by a hit (ult lost, MP/cd
## spent — like the channel).
##
## The windup is no longer one length and one gesture for every spell: it comes
## from CastStyle (kind -> body language) scaled by SpellTier (how much the spell
## costs you). The two hand-tuned constants this replaces — a 0.42 s planted windup
## and a 0.22 s fast one for rush/blink — now fall out of the table instead of
## being special-cased: RUSH and BLINK_STRIKE are COIL poses, and COIL is 0.22 s
## precisely because mobility must not feel sticky.
const SUMMON_NORMAL: int = 0
const SUMMON_RUSH: int = 1
const SUMMON_BLINK: int = 2
## load()ed by path, never class_name: this file is compiled by headless tools
## that have no autoloads, and RiftDagger touches Sfx/Juice at parse time.
const RIFT_DAGGER_PATH: String = "res://scripts/combat/RiftDagger.gd"
var _summoning: bool = false
var _summon_timer: float = 0.0
var _summon_total: float = 0.0
var _summon_spell: SpellDef = null
var _summon_sky: bool = false
var _summon_special: int = 0
var _summon_aim: Vector2 = Vector2.RIGHT
var _summon_target: Vector2 = Vector2.ZERO
var _summon_pose: int = CastStyle.Pose.POINT
var _summon_tier: int = SpellTier.Tier.HEAVY
## Levitation bookkeeping for the windup. `_summon_lift` is a pure POSITION offset
## from the y we lifted off at — never a velocity — so it cannot fight the gravity
## integration in _physics_process, and _end_summon can always put the hero back on
## exactly the ground they left.
var _summon_lift: float = 0.0
var _summon_lift_target: float = 0.0
var _summon_base_y: float = 0.0
## spell.id -> the timestamp its name card was last shown at. Feeds
## SignatureRite's repeat-suppression rule; per-hero so co-op players do not share
## a clock. See _declare_signature.
var _last_declared: Dictionary = {}

## --- THE CASTING PROCESS (CastStyle + SpellTier) -----------------------------
## A cast is a PROCESS, not a spawn: the body winds up, a sigil opens, and only
## then does the spectacle exist. The length of that windup is the opponent's
## DODGE WINDOW (CastStyle's own rule), so these are balance numbers dressed as
## animation timings — which is why the windup has to gate the spawn rather than
## play alongside it.
##
## THE WINDUP LADDER NOW LIVES IN `SignatureRite.TIER_WINDUP`, and the length of
## any one cast comes from `SignatureRite.windup_for(spell)`. It moved because the
## windup is not private bookkeeping — it IS the opponent's dodge budget, and the
## rite has to be able to report that number for a caster that is not this file
## (a boss, the playground rig). One table, read from both sides, rather than two
## that drift.
## Slight levitation (px) held during the windup, indexed by SpellTier.Tier. QUICK
## never leaves the floor: the maker asked for "SLIGHT levitation when casting the
## MORE POWERFUL spells", and a kit where every jab hops reads floaty, not weighty.
## UNTESTED FEEL GUESS — this is the "is it a flourish or a jump" dial.
const CAST_TIER_LIFT: Array[float] = [0.0, 6.0, 11.0]
## How fast the lift eases in (px/s). Fast enough to be at full height inside even
## the shortest non-quick windup (LASH, 0.18 s), slow enough to read as gathering
## rather than popping. UNTESTED FEEL GUESS.
const CAST_LIFT_SPEED: float = 70.0
## How airborne the RIG is told it is at full lift (0..1). Not 1.0: the legs should
## dangle a little, not fully unweight like the float-channel does. UNTESTED.
const CAST_LIFT_AIRBORNE: float = 0.35
## The sigil hangs ABOVE the caster (maker: "the circle should sit ABOVE"). The rise
## is this much from the hero origin (which sits at the figure's MIDDLE, so ~24 px
## already clears the head) PLUS a share of the sigil's own radius — a bigger ring
## has to float HIGHER or it sinks back onto the caster, and "above" would only be
## true for the smallest spell. Not the full radius: a little overlap keeps the ring
## reading as attached to the caster rather than as scenery floating nearby.
##
## This offset is only authoritative WHILE the caster still owns the sigil. Once a
## spectacle claims it (see the hand-off seam below) the claimer is free to travel
## it down/forward to the muzzle, and this file stops touching its position at all.
## UNTESTED FEEL GUESSES.
const CAST_CIRCLE_ABOVE: float = 24.0
const CAST_CIRCLE_CLEARANCE: float = 0.9
## Windup-sigil radius: a base plus a part that scales with the spell's MP cost, so
## the ring's SIZE is how the picture says "this one is expensive".
##
## Deliberately small against the ~40 px figure. The numbers these replace (34 + 22,
## and 44 + 26 for the channel) were tuned for a sigil that sat at the caster's FEET
## as a ground aura; hung above the head at that size it drew a portal that
## swallowed the caster whole — visible in tools/cast_windup_capture.gd. The channel
## still runs bigger because it is the screen-filler ceremony. UNTESTED FEEL GUESSES.
const CAST_SIGIL_RADIUS: float = 17.0
const CAST_SIGIL_RADIUS_PER_COST: float = 11.0
const CHANNEL_SIGIL_RADIUS: float = 21.0
const CHANNEL_SIGIL_RADIUS_PER_COST: float = 13.0

## --- ONE SIGIL PER CAST: THE CASTER SIDE OF THE HAND-OFF ---------------------
## Maker, mid-playtest: "there should be no spells where I summon a circle, it goes
## away, and then another circle spawns which the spell comes out of."
##
## That bug is two independent spawners with no knowledge of each other: the caster
## opens a windup sigil and dismisses it, and then the spectacle opens its OWN
## muzzle sigil. The player watches the ritual visibly restart mid-cast.
##
## The protocol lives in MagicCircle.gd (read its hand-off block — it owns both
## halves). This file is only the CASTER side, which is two calls:
##
##     MagicCircle.offer(_cast_sigil, self)   # at the moment the spell fires
##     MagicCircle.withdraw(self)             # on ANY interruption
##
## Offering does not dismiss: the spectacle spawned on the same frame adopts the
## live node, reparents it and glides it to the muzzle with its spin and phase
## running on unbroken. An offer nobody takes blooms itself out after MagicCircle's
## own TTL, which is what most spells want — a wall or a nova opens no sigil of its
## own, so its offer is MEANT to go unclaimed and degrade to the old behaviour.
## `withdraw` is therefore belt-and-braces rather than load-bearing, but a shattered
## cast should not wait out a TTL to clear its ring.
##
## Because adoption happens in the SAME FRAME as the offer, offering must be the
## last thing that happens before SpellCaster.cast() — which is why _end_summon /
## _end_channel take a `handoff` flag rather than always doing one or the other.
##
## The live windup sigil, while the CASTER still owns it. One variable for both
## ceremonies (summon windup and float-channel) precisely so there is a single
## thing to hand over — and the beam case, which is the duplicate-circle bug the
## maker actually reported, goes through the channel.
var _cast_sigil: MagicCircle = null
## Rise above the hero origin for the CURRENT sigil, computed when it opens because
## it depends on that sigil's radius (see CAST_CIRCLE_CLEARANCE).
var _cast_sigil_rise: float = CAST_CIRCLE_ABOVE


## Open the windup sigil above the caster. `radius` scales with the spell's cost so
## the ring's SIZE carries how expensive the thing coming out of it is.
##
## Orientation is deliberately left FACE-ON — the maker asked for a circle sitting
## ABOVE the caster, and a summoning ring read head-on is what that picture is. An
## edge-on gate belongs at the MUZZLE, pointed down the shot, and that is the
## adopting spectacle's business: BeamSpell.adopt_or_open() passes edge_on and the
## sigil FOLDS into the gate as it travels down. Setting it edge-on here produced a
## tall vertical lens hanging over the head that read as a bug, not a ritual.
func _open_cast_sigil(radius: float, grow_time: float) -> void:
	_discard_cast_sigil()  # a cast can be interrupted but never queued — never stack two
	_cast_sigil_rise = CAST_CIRCLE_ABOVE + radius * CAST_CIRCLE_CLEARANCE
	var sigil := MagicCircle.new()
	get_parent().add_child(sigil)
	sigil.global_position = _cast_sigil_pos()
	sigil.appear(_element_color, radius, grow_time)
	_cast_sigil = sigil


## Offer the sigil to whichever spectacle is about to spawn. Deliberately does NOT
## vanish it — dismissing here is precisely the duplicate-circle bug. Hero drops its
## own reference immediately: from this instant the node belongs to the protocol,
## and this file must never move or rescale it again.
func _release_cast_sigil() -> void:
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		MagicCircle.offer(_cast_sigil, self)
	_cast_sigil = null


## Dismiss the sigil outright. For a cast that produces NO spectacle — an
## interrupted windup, a shattered channel — where there is nothing to hand it to.
## The withdraw() covers the narrow case of a cast that already offered and is then
## torn down before anything adopted; it is a no-op otherwise, so it is safe to call
## unconditionally.
func _discard_cast_sigil() -> void:
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		_cast_sigil.vanish(0.2)
	_cast_sigil = null
	MagicCircle.withdraw(self)


## Where the sigil hangs while the CASTER still owns it: clear above the head,
## tracking them upward as they levitate. Once offered, this file stops positioning
## it entirely so the adopting spectacle can travel it down to the muzzle.
func _cast_sigil_pos() -> Vector2:
	return global_position + Vector2(0.0, -_cast_sigil_rise)


## True when aim should auto-target (mobile): the TouchControls pad is active, or the
## device is a touchscreen. Cached DisplayServer call is cheap.
func _touch_aim() -> bool:
	return touch_input or DisplayServer.is_touchscreen_available()


func _physics_process(delta: float) -> void:
	# Co-op: you only drive YOUR hero. Remote heroes follow the synchronizer and
	# just animate (no Input, no move_and_slide).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		_remote_visual(delta)
		return
	# Co-op: downed = a limp ragdoll on the ground, no input/abilities, until the party
	# falls or clears the floor and everyone revives.
	if downed:
		_process_downed(delta)
		return
	# BOT: decide this frame's intent before anything reads input. Above the
	# cooldown ticks so the brain sees the same cooldowns the player's ability bar
	# showed at the end of last frame, and `delta` is the SCALED one every other
	# timer in this function uses — see `_bot_clock`.
	if controller != null:
		_bot_clock += delta
		controller.tick(self, _bot_clock)
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)
	_cast_cooldown_timer = max(_cast_cooldown_timer - delta, 0.0)
	_melee_cooldown_timer = max(_melee_cooldown_timer - delta, 0.0)
	_blast_cooldown_timer = max(_blast_cooldown_timer - delta, 0.0)
	_blink_cooldown_timer = maxf(_blink_cooldown_timer - delta, 0.0)
	_blink_iframe_timer = maxf(_blink_iframe_timer - delta, 0.0)
	_nova_cooldown_timer = maxf(_nova_cooldown_timer - delta, 0.0)
	_parry_window_timer = maxf(_parry_window_timer - delta, 0.0)
	_parry_cooldown_timer = maxf(_parry_cooldown_timer - delta, 0.0)
	# The BLADE ring is ticked HERE, above the channel/summon early-returns, so its
	# re-arm keeps running while the hero is committed to something else. A guard
	# whose recovery paused whenever you were busy would silently re-arm instantly
	# after every cast.
	if _guard != null:
		_guard.tick(delta)
	# Every kit slot recovers independently, and they all recover WHILE you are
	# committed to something else — same reasoning as the guard ring above.
	_hand.tick(delta)
	_wall_jump_lock = maxf(_wall_jump_lock - delta, 0.0)
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_update_flaming_fist(delta)
	# Mana regenerates every frame (even mid-dash) so ultimates stay paced.
	if mp < float(max_mp):
		mp = minf(mp + MP_REGEN * delta, float(max_mp))
		mana_changed.emit(mp, max_mp)
	# FLOAT-CHANNEL: while casting a big spectacle the hero levitates + is fully
	# committed (no movement/input) until the cast fires or a hit interrupts it.
	if _channeling:
		_process_channel(delta)
		return
	# SUMMON WINDUP: while the spell circle blooms the hero is committed (grounded,
	# no movement/input) until it erupts or a hit interrupts it.
	if _summoning:
		_process_summon(delta)
		return
	# Landing dust: white puff the instant we touch down after being airborne (not
	# while gliding). At the top so it fires even on dash frames. is_on_floor()
	# here reflects the previous frame's move_and_slide.
	if is_on_floor() and not _was_on_floor:
		_spawn_foot_puff()
		Juice.shake_camera(2.5)  # a little land thud (Stick-Fight juice)
	_was_on_floor = is_on_floor()
	_update_input_buffer(delta)
	# Aim resolution. LOCKED RULE: no auto-aim, no homing — on EVERY platform the aim
	# is the direction the player is actually pointing, and landing a spell is their
	# skill, not the game's. On desktop that's the cursor, tracked every frame so
	# casts / cast-pose / camera peek use it even mid-dash.
	# On MOBILE there is no cursor, so the aim is the RIGHT THUMB STICK'S own direction
	# (the `aim_*` actions, published by TouchControls). It used to snap to the nearest
	# enemy here, which quietly handed the phone player a targeting computer the desktop
	# player is denied — exactly the auto-aim the rule forbids.
	#
	# It then briefly read the MOVE stick, which was worse than it looked: that layer
	# published no upward component at all, so a touch player could not aim above the
	# horizon at anything, ever. Aim now has its own stick and its own actions, fully
	# decoupled from movement (pushing move-down ducks you; it does not aim at the
	# floor). A released thumb HOLDS the last aim rather than resetting to a default,
	# so letting go to tap an ability button doesn't fling the shot somewhere else.
	#
	# The stick is checked BEFORE the platform test on purpose: any device that can
	# push `aim_*` past the deadzone (touch pad, a gamepad's right stick, the IJKL
	# keyboard fallback) steers the aim, and the mouse only takes over when the stick
	# is at rest. That keeps one code path for every input device instead of three.
	#
	# A CONTROLLER WINS OVER BOTH. It is checked first and returns before the stick
	# and the cursor are consulted, because both of those read PROCESS-GLOBAL state:
	# a bot sharing a machine with a player would otherwise inherit the human's
	# thumbstick and the human's cursor as its own aim. The same "hold the last aim
	# rather than snap to a default" rule applies, so a brain that declines to aim
	# on a frame keeps pointing where it was.
	if controller != null:
		var to_aim: Vector2 = _aim_point() - global_position
		if to_aim.length() > 1.0:
			_aim_dir = to_aim.normalized()
	else:
		var aim_stick: Vector2 = Vector2(
			Input.get_action_strength("aim_right") - Input.get_action_strength("aim_left"),
			Input.get_action_strength("aim_down") - Input.get_action_strength("aim_up")
		)
		if aim_stick.length() > TOUCH_AIM_DEADZONE:
			_aim_dir = aim_stick.normalized()
		elif not _touch_aim():
			var to_mouse: Vector2 = get_global_mouse_position() - global_position
			if to_mouse.length() > 1.0:
				_aim_dir = to_mouse.normalized()
	facing = _aim_dir
	# Feed groundedness to the rig so a limp (hold-DOWN) ragdoll clamps to the floor
	# instead of drooping through it. Set every frame; cheap.
	rig.set_grounded(is_on_floor())
	# Hold DOWN to go LIMP — the Stick-Fight ragdoll flop. Abilities + walking are
	# suspended; the active-ragdoll rig droops and gravity/friction bring you to the
	# ground. Release to snap back up.
	if _pressed(&"move_down") and not is_dashing:
		if not _ragdolling:
			_ragdolling = true
			rig.set_limp(1.0)
			rig.apply_impulse(Vector2(0.0, 1.0), 220.0)  # a little flop-down kick
		velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta) + _knockback.x
		velocity.y = 0.0 if (is_on_floor() and velocity.y >= 0.0) else minf(velocity.y + GRAVITY_FALL * delta, MAX_FALL)
		move_and_slide()
		rig.play(CharacterRig.State.HURT)
		rig.set_body_velocity(velocity)
		return
	elif _ragdolling:
		_ragdolling = false
		rig.set_limp(0.0)
	# Cosmetic + class toggles: instant, un-buffered, legal even mid-dash.
	if _just(&"cycle_element"):
		_cycle_element()
	if _just(&"cycle_colourway"):
		_cycle_colourway()
	if _just(&"switch_class"):
		_cycle_class()
	if _just(&"cycle_signature"):
		_cycle_signature()
	# THE DEFENSIVE VERB. Two shapes behind one button: eight classes press for a
	# fixed window, the Swordsaint HOLDS a shrinking ring. `_guard != null` is the
	# only switch, so nothing about the press path changed for anyone else.
	if _guard != null:
		_process_blade_guard(delta)
	elif _just(&"parry") and not is_dashing:
		_try_parry_start()
	# GUARDING LOCKS OUT ATTACKING — ParryRing's own rule, and a balance one rather
	# than a UI limitation: a sustained guard that cost nothing offensively would be
	# a permanent free damage reduction. It also removes the platform asymmetry where
	# a desktop player could hold guard and swing but a thumb cannot.
	var guard_locked: bool = _guard != null and _guard.blocks_attack()
	if _just(&"ultimate") and not is_dashing and not guard_locked:
		_cast_signature()
	if _pressed(&"cast") and _cast_cooldown_timer <= 0.0 and not is_dashing \
			and not guard_locked:
		_cast()

	if is_dashing:
		_dash_timer -= delta
		velocity = _dash_dir * _tune("dash_speed", DASH_SPEED)
		move_and_slide()
		if _cfg["dash_strike"]:
			_dash_strike_sweep()  # rogue: dash deals melee damage through enemies
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_INTERVAL
			rig.spawn_ghost(get_parent(), GHOST_COLOR, _dash_dir)
		if _dash_timer <= 0.0:
			is_dashing = false
			# Skid-to-a-stop dust puff — the "come down to the ground" kick-up.
			CombatVfx.spawn_burst(
				get_parent(), global_position,
				Color(0.82, 0.82, 0.88, 0.6), Color(0.82, 0.82, 0.88, 0.0),
				8, 0.25, 30.0, 95.0
			)
		rig.play(CharacterRig.State.DASH)
		rig.set_facing(_dash_dir)  # body faces where the dash is going
		# The dash branch returns early, so the rig used to spend the whole burst on a
		# stale velocity: no inertial limb trail, and (since the body springs landed)
		# no way to tell a horizontal dash from a vertical one. Feeding it here gives
		# the rig the dash's true DIRECTION, which is what SpikeFigure leans off
		# (`lean = _dash_dir.x * DASH_LEAN` — a straight-up dash does not pitch).
		rig.set_body_velocity(velocity)
		return

	# --- Side-on movement: horizontal input, gravity, jumping ---
	var move_x: float = _axis(&"move_left", &"move_right")
	# A HELD BLADE GUARD ROOTS YOU. The blade is planted, not carried, and that is
	# what makes walking away the clean counter to it: an opponent who simply
	# declines to swing beats the guard outright, and the Swordsaint has spent the
	# hold for nothing. Rooting is also what keeps the bank honest — you cannot chase
	# someone down while holding a loaded return.
	if _guard != null and _guard.blocks_attack():
		move_x = 0.0
		_jump_buffer = 0.0
	if move_x != 0.0:
		_move_dir = Vector2(signf(move_x), 0.0)  # dash/blink dodge direction
	if _just(&"jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	if _try_fire_buffered():
		return  # a dash started this frame — the dash branch owns movement now

	# Coyote window + air-jump refill while grounded (per-class: Brawler double-jumps).
	if is_on_floor():
		_coyote = COYOTE_TIME
		_air_jumps = _max_air_jumps
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	# --- Wall-slide: gripping a wall while falling INTO it (is_on_wall_only so a
	# grounded corner never counts). get_wall_normal points AWAY from the wall. ---
	var wall_normal: Vector2 = get_wall_normal()
	var pushing_into_wall: bool = move_x != 0.0 and is_on_wall_only() \
			and signf(move_x) == -signf(wall_normal.x)
	var wall_sliding: bool = is_on_wall_only() and velocity.y > 0.0 and pushing_into_wall

	# Vertical: asymmetric gravity (floaty apex, weighty fall); wall-slide clamps it.
	if is_on_floor() and velocity.y >= 0.0:
		velocity.y = 0.0  # guard: an upward knockback pop must beat the floor-zero
	else:
		var g: float = _tune("move_gravity_rise", GRAVITY) if velocity.y < 0.0 else _tune("move_gravity_fall", GRAVITY_FALL)
		velocity.y = minf(velocity.y + g * delta, _tune("move_max_fall", MAX_FALL))
		if wall_sliding:
			velocity.y = minf(velocity.y, WALL_SLIDE_MAX_FALL)
	# Variable jump height: releasing jump while rising cuts the ascent short.
	if _released(&"jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	# Jump (buffered): ground/coyote, else a WALL-JUMP off a gripped wall.
	if _jump_buffer > 0.0:
		if is_on_floor() or _coyote > 0.0:
			velocity.y = _tune("move_jump_velocity", JUMP_VELOCITY)
			_jump_buffer = 0.0
			_coyote = 0.0
			_spawn_foot_puff()
		elif is_on_wall_only():
			# Kick away from the wall + up; a slide-then-jump gets a speed boost.
			var boost: float = SLIDE_JUMP_BOOST if _was_wall_sliding else 1.0
			velocity.x = wall_normal.x * WALL_JUMP_PUSH * boost
			velocity.y = WALL_JUMP_UP
			_wall_jump_lock = WALL_JUMP_LOCKOUT
			_jump_buffer = 0.0
			_spawn_foot_puff()
		elif _air_jumps > 0:
			# Air (double) jump — classes with air_jumps > 0 (Brawler). A puff + a
			# quick flip-flourish sells the mid-air kick.
			velocity.y = DOUBLE_JUMP_VELOCITY
			_air_jumps -= 1
			_jump_buffer = 0.0
			_spawn_foot_puff()

	# Horizontal: accel toward input, friction to a stop. The wall-jump lockout
	# briefly preserves the kick-off so it can't be cancelled back into the wall.
	var spd: float = _tune("hero_speed", SPEED) * _gear_speed_mult  # gear: hood = fleet-footed
	if _wall_jump_lock <= 0.0:
		if move_x != 0.0:
			var accel: float = GROUND_ACCEL if is_on_floor() else _tune("move_air_accel", AIR_ACCEL)
			velocity.x = move_toward(velocity.x, move_x * spd, accel * delta)
		else:
			var fric: float = GROUND_FRICTION if is_on_floor() else _tune("move_air_accel", AIR_ACCEL)
			velocity.x = move_toward(velocity.x, 0.0, fric * delta)
	# Tiny push into the wall so move_and_slide keeps registering the slide.
	if wall_sliding:
		velocity.x = -wall_normal.x * WALL_STICK_PUSH
	velocity.x += _knockback.x  # ragdoll shove from an enemy hit / bomb
	move_and_slide()
	_check_wall_slam()  # crack a breakable we were slammed into
	_was_wall_sliding = wall_sliding
	rig.set_body_velocity(velocity)  # ragdoll: limbs trail when you launch/stop

	# Rig: a distinct WALL-SLIDE cling (so you read as ON the wall) with friction
	# dust; otherwise run/idle with grounded footsteps.
	if wall_sliding:
		rig.play(CharacterRig.State.WALL_SLIDE)
		rig.set_facing(Vector2(-wall_normal.x, 0.0))  # turn to face the wall
		_wall_dust_timer -= delta
		if _wall_dust_timer <= 0.0:
			_wall_dust_timer = 0.09
			CombatVfx.spawn_burst(
				get_parent(), global_position + Vector2(-wall_normal.x * 9.0, 8.0),
				Color(0.85, 0.85, 0.9, 0.6), Color(0.85, 0.85, 0.9, 0.0),
				5, 0.25, 20.0, 70.0
			)
		rig.set_aim(_aim_dir)
		return
	var moving: bool = absf(move_x) > 0.01
	# Airborne: drive the loose-air ragdoll regime (NO canned jump pose — the limbs
	# trail/flail via _step_sim's air looseness). Grounded: settle into RUN/IDLE with
	# the foot-plant. rising = velocity.y < 0.0 (ascending) biases the looseness only.
	if not is_on_floor():
		rig.play(CharacterRig.State.AIR)
		rig.set_air_phase(velocity.y < 0.0, is_on_floor())
	else:
		rig.play(CharacterRig.State.RUN if moving else CharacterRig.State.IDLE)
	# NOTE: no footstep/dust block here any more. Both are driven by the rig's
	# `foot_planted` signal (see _on_foot_planted) so the crunch and the puff land on
	# the frame the foot visibly hits the ground, instead of on a timer that slowly
	# slid out of phase with the animation.
	# Stick-Fight decouple: the BODY faces MOVEMENT (idle keeps the last facing —
	# set_facing ignores x==0); the cast arm/weapon aims at the true cursor. The
	# figure is FACELESS (no eyes) — aim reads from the body + the pointed weapon +
	# the parry shield, the Stick-Fight way. During a melee strike the body turns
	# to the aim so the punch points at the target.
	if rig.is_striking():
		rig.set_facing(_aim_dir)
	else:
		rig.set_facing(Vector2(move_x, 0.0))
	rig.set_aim(_aim_dir)


## Record melee/dash/blast presses into a single-slot buffer (newest press
## wins) and expire the slot after BUFFER_TIME.
func _update_input_buffer(delta: float) -> void:
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	if _buffer_timer <= 0.0:
		_buffered_action = ""
	for action: String in ["melee", "dash", "blast", "blink", "nova"]:
		if _just(StringName(action)):
			_buffered_action = action
			_buffer_timer = BUFFER_TIME


## Fire the buffered action if its gate is now open, consuming the buffer so
## nothing double-fires. Only called from the not-dashing path, so the old
## `not is_dashing` gates are implicit. Returns true if a dash started (the
## caller must yield the rest of the frame to the dash branch).
func _try_fire_buffered() -> bool:
	if _buffered_action.is_empty():
		return false
	# A held BLADE guard locks out the offence (ParryRing.blocks_attack). The press
	# is deliberately NOT dropped, only held: the buffer already exists so a press
	# through a closed gate fires the moment the gate opens, and that is exactly the
	# right feel here — let go of guard and the swing you asked for comes out.
	if _guard != null and _guard.blocks_attack():
		return false
	match _buffered_action:
		"melee":
			if _melee_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_melee()
		"blast":
			if _blast_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_blast()
		"dash":
			if _dash_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_start_dash()
				return true
		"blink":
			if _blink_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_blink()
		"nova":
			if _nova_cooldown_timer <= 0.0:
				_clear_input_buffer()
				_nova()
	return false


func _clear_input_buffer() -> void:
	_buffered_action = ""
	_buffer_timer = 0.0


## Advance to the next element (wraps) and re-apply aura + ability colour.
func _cycle_element() -> void:
	_element = (_element + 1) % Elements.count()
	_apply_element()


## Element = aura + ability colour. The aura recolours instantly (the colour
## change IS the feedback); _element_color feeds every subsequent cast.
func _apply_element() -> void:
	_element_color = Elements.color(_element)
	rig.set_aura(_element_color, AURA_STRENGTH)


## Rank-up: the aura escalates a tier (more layers/motes/ring) plus a quick
## element-coloured pop on the figure. No menus — this IS the feedback.
func _on_rank_changed(new_tier: int, _title: String) -> void:
	rig.set_aura_tier(new_tier)
	rig.flash_color(_element_color, 0.18)


## Advance to the next body colourway (wraps) and retint the rig limbs.
## Purely cosmetic — independent of the element.
func _cycle_colourway() -> void:
	_colourway = (_colourway + 1) % COLOURWAYS.size()
	rig.set_tint(COLOURWAYS[_colourway])


## Configure the hero for a class: rig preset + weapon + per-class ability
## tuning (_cfg). Called at _ready and on the debug switch. Clears cooldowns +
## buffer so a mid-fight swap can't double-fire.
func configure_class(cls: int) -> void:
	_hero_class = cls
	_cfg = CLASS_CONFIG[cls]
	rig.class_preset(_cfg["preset"])
	if String(_cfg["weapon"]) != "":
		equip_weapon(String(_cfg["weapon"]))  # rogue: sword overlay + melee retune
	else:
		# Mage: keep the preset's staff overlay; melee falls back to fists stats.
		_weapon = "fists"
		_melee_damage = MELEE_DAMAGE
		_melee_range = MELEE_RANGE
		_melee_knockback = MELEE_KNOCKBACK
	# Per-class melee tuning (cadence + arc width + optional stat overrides) so a
	# Brawler jabs fast/narrow and a Juggernaut swings slow/wide/hard.
	_melee_cd = float(_cfg.get("melee_cd", MELEE_COOLDOWN))
	_melee_arc_dot = float(_cfg.get("melee_arc_dot", MELEE_ARC_DOT))
	if _cfg.has("melee_damage"):
		_melee_damage = int(_cfg["melee_damage"])
	if _cfg.has("melee_range"):
		_melee_range = float(_cfg["melee_range"])
	if _cfg.has("melee_knockback"):
		_melee_knockback = float(_cfg["melee_knockback"])
	_dash_cooldown_timer = 0.0
	_cast_cooldown_timer = 0.0
	_blink_cooldown_timer = 0.0
	_blast_cooldown_timer = 0.0
	_nova_cooldown_timer = 0.0
	_parry_window_timer = 0.0
	_parry_cooldown_timer = 0.0
	_clear_input_buffer()
	# Per-class movement identity: air (double) jumps refill count.
	_max_air_jumps = int(_cfg.get("air_jumps", 0))
	_air_jumps = _max_air_jumps
	# Juggernaut BLOCK = a longer, more forgiving defensive window than a parry.
	var defense: String = String(_cfg.get("defense", "parry"))
	_parry_window_len = 0.40 if defense == "block" else PARRY_WINDOW
	# HELD GUARD: swap the press-window parry for ParryRing's BLADE style. Rebuilt
	# (not merely reset) on every class change so a ring can never survive a swap
	# half-held — a stuck `held` would silently lock the next class out of attacking.
	_guard = ParryRing.for_style(ParryRing.Style.BLADE) if defense == "held_guard" else null
	_guard_bank = 0
	_guard_hits = 0
	# Auto-set the class's signature element (X still cycles from here) + swap in
	# the class's themed signature loadout (its hero-fantasy ultimate first).
	if _cfg.has("element"):
		_element = int(_cfg["element"])
		_apply_element()
	_signatures = SpellLibrary.build_for_class(cls)
	_signature_index = 0
	# Rebuild the cooldown bank FROM the new kit, which also clears every timer. A
	# per-slot bank makes this load-bearing in a way the old single float was not: a
	# leftover timer would otherwise lock a slot of a class the player has never cast
	# with, and Tab swaps classes live.
	_hand.rebuild([], _signatures)
	if not _signatures.is_empty():
		signature_changed.emit(_signatures[_signature_index].display_name)
	# Snapshot the fully-tuned class base (post equip_weapon) so gear mults scale from
	# it idempotently, then apply any loadout overrides' abilities.
	_base_melee_damage = _melee_damage
	_base_melee_knockback = _melee_knockback
	_base_melee_cd = _melee_cd
	_base_max_hp = max_hp
	_base_element = _element  # class innate element (a non-elemental weapon reverts here)
	_gear_override.clear()  # a fresh class = a fresh loadout base...
	_recompute_gear_effects()
	_apply_gamestate_loadout(get_node_or_null("/root/GameState"))  # ...then re-apply the hub loadout


# ---------------------------------------------------------------- gear abilities
## Public loadout hook (the loadout UI): swap the piece in `slot` ("weapon"/"head"/
## "body") to `kind` ("" clears), update the rig overlay, and re-apply the gear
## abilities. Idempotent — the effects recompute from the class base every time.
func set_loadout(slot: String, kind: String) -> void:
	if kind == "":
		_gear_override.erase(slot)
	else:
		_gear_override[slot] = kind
	rig.set_equipment(slot, kind)  # cosmetic overlay follows the choice
	_recompute_gear_effects()


## Apply the hub Armory's loadout override (GameState.loadout) after the class base:
## any non-empty slot swaps the class-default piece for the player's choice, then the
## gear abilities recompute once. No-op when nothing is overridden (default classes).
func _apply_gamestate_loadout(gs: Node) -> void:
	if gs == null:
		return
	var lo: Variant = gs.get("loadout")
	if not (lo is Dictionary):
		return
	var changed: bool = false
	for slot: String in ["weapon", "head", "body"]:
		var kind: String = String((lo as Dictionary).get(slot, ""))
		if kind != "":
			_gear_override[slot] = kind
			rig.set_equipment(slot, kind)
			changed = true
	if changed:
		_recompute_gear_effects()


## Aggregate the equipped gear's effect bags (weapon/head/body) into one modifier
## set. Mults multiply, ward takes the strongest, an elemental weapon wins the element.
func _aggregate_gear() -> Dictionary:
	var out: Dictionary = {
		"melee_damage": 1.0, "melee_knockback": 1.0, "melee_cd": 1.0,
		"max_hp": 1.0, "speed": 1.0, "ward": 0.0, "damage_reduction": 0.0, "element": -1,
	}
	for slot: String in ["weapon", "head", "body"]:
		var kind: String = String(_gear_override.get(slot, ""))  # only player CHOICES grant abilities
		if kind == "":
			continue
		var e: Dictionary = GearAbilities.effect(kind)
		for k: String in ["melee_damage", "melee_knockback", "melee_cd", "max_hp", "speed"]:
			if e.has(k):
				out[k] *= float(e[k])
		for k: String in ["ward", "damage_reduction"]:
			if e.has(k):
				out[k] = maxf(out[k], float(e[k]))
		if e.has("element"):
			out["element"] = int(GEAR_ELEMENT.get(String(e["element"]), -1))
	return out


## Apply the aggregated gear effects from the class BASE (idempotent). Called on
## class config + every loadout swap; safe to re-run.
func _recompute_gear_effects() -> void:
	var g: Dictionary = _aggregate_gear()
	# Melee profile from the captured class base * gear mult (idempotent).
	_melee_damage = int(round(float(_base_melee_damage) * float(g["melee_damage"])))
	_melee_knockback = _base_melee_knockback * float(g["melee_knockback"])
	_melee_cd = _base_melee_cd * float(g["melee_cd"])
	# Max HP from the class base * gear mult (keep the current fill ratio).
	var new_max: int = maxi(int(round(float(_base_max_hp) * float(g["max_hp"]))), 1)
	if new_max != max_hp:
		var ratio: float = float(hp) / float(maxi(max_hp, 1))
		max_hp = new_max
		hp = clampi(int(round(float(new_max) * ratio)), 1, new_max)
		health_changed.emit(hp, max_hp)
	_gear_speed_mult = float(g["speed"])
	# Gear mitigation lives on the shared guard, not in local fields, so ward
	# spells and armour resolve through ONE path instead of two that disagree.
	# Re-applying also re-arms the one-shot robe: a fresh loadout = a fresh ward.
	GuardComponent.of(self).set_gear(float(g["damage_reduction"]), float(g["ward"]))
	# Element follows the WEAPON: an elemental weapon (staff_ice, scythe, ...) sets it;
	# a non-elemental weapon reverts to the class's innate element (never sticks).
	var ge: int = int(g["element"])
	_element = ge if ge >= 0 else _base_element
	_apply_element()


## Debug: cycle class live (Tab) and persist the choice to GameState so the hub
## selection and the next run stay in sync.
func _cycle_class() -> void:
	configure_class((_hero_class + 1) % HeroClass.size())
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.selected_class = _hero_class


## Live class cycle for a test button (mirrors the Tab press).
func cycle_class_next() -> void:
	_cycle_class()


func current_class_name() -> String:
	return CLASS_NAMES[_hero_class] if _hero_class < CLASS_NAMES.size() else "Class"


## Unleash the equipped SIGNATURE spectacle toward the aim, if THAT SLOT is off
## cooldown. SpellCaster picks the spectacle (magic-circle beam / divine ray / ...).
## Not buffered — a deliberate press.
##
## ⚠ NO MANA GATE. Deleted deliberately, per the spec: "Cooldowns, not mana. Mana
## makes people hoard and play safe, which is the opposite of what this game wants."
## A pool you can run dry teaches you to stop pressing buttons, and a co-op brawler
## whose social engine is friendly fire needs people pressing buttons. `mp_cost`
## SURVIVES on `SpellDef` and is still read — `SpellTier.of()` uses it as one of its
## three shelf thresholds, and the cast/channel sigils scale their radius by it — so
## deleting the field would silently reshelve spells and shrink their tells. It costs
## nothing to keep; it just no longer stops a cast.
func _cast_signature() -> void:
	if _signatures.is_empty():
		return
	var spell: SpellDef = _signatures[_signature_index]
	# Second beat of a THROWN_ANCHOR: with a dagger already out, this press means
	# RECALL, and it must be free. This branch has to sit ABOVE the gate below —
	# the cooldown is running from the throw.
	if spell.kind == SpellDef.Kind.THROWN_ANCHOR \
			and (load(RIFT_DAGGER_PATH) as GDScript).try_recall(get_tree(), self):
		return
	var slot: int = _hand_slot(_signature_index)
	if not _hand.is_ready(slot):
		# THIS slot is still recovering. A different slot may well be ready, which is
		# the entire point of the per-slot bank.
		rig.flash_color(Color(0.5, 0.5, 0.6), 0.08)
		Sfx.play("melee_swing", -14.0, 0.0)
		return
	_hand.start_cooldown(slot, spell.cooldown)
	# Sky spells (meteor / divine row) raise the staff UP and place from the hero;
	# beams emanate FROM the staff tip toward the aim.
	var sky: bool = spell.kind == SpellDef.Kind.METEOR or spell.kind == SpellDef.Kind.DIVINE_RAY \
			or spell.kind == SpellDef.Kind.CONVERGENCE
	# Big spectacles LEVITATE + channel for cast_time, THEN fire — they carry their
	# own float ceremony already.
	if spell.cast_time > 0.0:
		_begin_channel(spell, sky)
		return
	# Every OTHER signature now blooms an epic SUMMON windup (spell circle + committed
	# cast pose + gather motes) before it erupts. Rush + blink keep their special
	# fire logic (lunge / teleport), routed through _finish_summon.
	var special: int = SUMMON_NORMAL
	if spell.kind == SpellDef.Kind.RUSH:
		special = SUMMON_RUSH
	elif spell.kind == SpellDef.Kind.BLINK_STRIKE:
		special = SUMMON_BLINK
	_begin_summon(spell, sky, special)


## Start the summon windup: freeze committed, throw the spell's OWN body language,
## and (for anything above a jab) open a sigil overhead + lift slightly off the
## floor. The actual spell fires in _finish_summon, after the windup elapses — the
## delay is the point, not a side effect.
func _begin_summon(spell: SpellDef, sky: bool, special: int) -> void:
	_summoning = true
	_summon_spell = spell
	_summon_sky = sky
	_summon_special = special
	# BODY LANGUAGE comes from the spell's KIND, not from one gesture reused for
	# everything: a wall gets slammed out of the ground, a bombardment gets a ritual
	# circle, a lightning rush gets coiled into the chest. Same table the playground rig
	# reads, so a spell looks like ITSELF regardless of who throws it.
	_summon_pose = CastStyle.for_spell(spell.kind)
	_summon_tier = SpellTier.of(spell)
	_summon_total = SignatureRite.windup_for(spell)
	_summon_timer = _summon_total
	# THE DECLARE BEAT rides the windup that is already being spent — it adds no
	# time, and the suppression rules keep it from becoming a tax (see SignatureRite).
	_declare_signature(spell, _summon_total, _summon_tier)
	_summon_aim = _aim_dir
	_summon_target = _aim_point()
	velocity = Vector2.ZERO
	# Levitation is armed here but applied per-frame in _process_summon, so a windup
	# that is cancelled on its very first frame never leaves the hero off the ground.
	_summon_lift = 0.0
	_summon_base_y = global_position.y
	_summon_lift_target = CAST_TIER_LIFT[_summon_tier]
	rig.set_aim(Vector2.UP if sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	# Intensity rises with the tier so the arms commit harder for the expensive
	# spells — the same escalation the windup length and the lift already carry.
	rig.cast_gesture(_pose_gesture(_summon_pose), 0.5 + 0.25 * float(_summon_tier), _element)
	# A QUICK spell gets NO sigil: the maker's ask was a circle for the MORE POWERFUL
	# spells, and a summoning ring opening for a throwaway would cheapen the ones
	# that matter. (Nothing in the shipped library is QUICK yet — this is the gate
	# for when cheap signatures land.)
	if _summon_tier != SpellTier.Tier.QUICK:
		_open_cast_sigil(
			CAST_SIGIL_RADIUS + CAST_SIGIL_RADIUS_PER_COST * clampf(spell.mp_cost / 90.0, 0.0, 1.0),
			_summon_total)
	Sfx.play("charge_up", -6.0, 0.05)


## Play the DECLARE beat for a signature, if the rite's three suppression rules
## allow it. `_last_declared` is PER HERO on purpose: two co-op players must not
## share a repeat clock, or one of them ulting would silence the other's card.
##
## The card is tinted with the SPELL's resolved colour rather than the caster's
## current element, so a spell that overrides its tint announces itself in its own
## colour and the card is class-legible before any of the spell exists.
func _declare_signature(spell: SpellDef, windup: float, tier: int) -> void:
	if spell == null:
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if not SignatureRite.should_declare(tier, spell.id, _last_declared, now,
			SignatureRite.card_live()):
		return
	if SignatureRite.announce(self, spell.display_name.to_upper(),
			spell.resolve_color(_element_color), windup):
		_last_declared[spell.id] = now


## CastStyle.Pose -> the rig's cast-gesture vocabulary. CastStyle names EIGHT body
## languages; CharacterRig ships SIX limb-isolated verbs, so this is a deliberate
## lossy translation that picks the verb whose MOTION is closest to the pose's
## intent. That is exactly the split CastStyle documents: a pose is DIRECTION, and
## each rig interprets it with the joints it actually has.
static func _pose_gesture(pose: int) -> int:
	match pose:
		CastStyle.Pose.SLAM:
			return CharacterRig.GestureKind.STOMP       # fist drives down + foot plant
		CastStyle.Pose.CIRCLE, CastStyle.Pose.CHANNEL, CastStyle.Pose.THROW:
			return CharacterRig.GestureKind.RAISE       # the arm goes overhead first
		CastStyle.Pose.LASH:
			return CharacterRig.GestureKind.FLICK       # one sharp snap off one hand
		CastStyle.Pose.SWEEP:
			return CharacterRig.GestureKind.IGNITE_DROP # the hand has to go LOW
		_:
			# POINT and COIL are the two-handed ones: hands to the chest, then drive
			# out along the aim. GATHER is the rig's only both-hands verb.
			return CharacterRig.GestureKind.GATHER


## Hold the committed summon each frame: stay put, ease the slight levitation, grow
## the sigil, gather converging motes, then erupt when the windup elapses.
func _process_summon(delta: float) -> void:
	velocity = Vector2.ZERO
	# SLIGHT levitation: the toes leaving the floor as the power gathers. Written as
	# an absolute offset from the take-off y (not an upward velocity) so gravity —
	# which this branch skips entirely — has nothing to fight, and so the restore in
	# _end_summon is exact rather than "fall back down eventually".
	if _summon_lift_target > 0.0:
		_summon_lift = move_toward(_summon_lift, _summon_lift_target, CAST_LIFT_SPEED * delta)
		global_position.y = _summon_base_y - _summon_lift
		rig.set_airborne(CAST_LIFT_AIRBORNE * (_summon_lift / _summon_lift_target))
	move_and_slide()  # hold position (gravity zeroed -> committed in place)
	rig.set_body_velocity(Vector2.ZERO)
	rig.play(CharacterRig.State.CAST)  # keep the committed cast pose held
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		_cast_sigil.global_position = _cast_sigil_pos()
		var prog: float = 1.0 - _summon_timer / maxf(_summon_total, 0.001)
		_cast_sigil.scale = Vector2.ONE * (0.55 + 0.7 * prog)  # sigil grows as it charges
	# Energy motes converge inward on the caster (the wind-up).
	if fmod(_summon_timer, 0.09) < delta:
		CombatVfx.spawn_burst(get_parent(), global_position,
			Color(_element_color.r, _element_color.g, _element_color.b, 0.75),
			Color(_element_color.r, _element_color.g, _element_color.b, 0.0),
			5, 0.26, 48.0, 100.0, 0.5, 1.4, 0.0, 0.0, true)
	_summon_timer -= delta
	if _summon_timer <= 0.0:
		_finish_summon()


## The eruption: run the signature's real fire logic, then fire ONE synchronized
## epic beat (camera reveal + punch + shake + hitstop) as the payoff.
func _finish_summon() -> void:
	var spell: SpellDef = _summon_spell
	var special: int = _summon_special
	var sky: bool = _summon_sky
	var aim: Vector2 = _summon_aim
	var target: Vector2 = _summon_target
	# handoff: OFFER the windup sigil instead of dismissing it, so the spectacle
	# spawned on this same frame adopts and continues it. Every SpellCaster.cast()
	# below therefore passes `self` — that is the key MagicCircle.adopt_or_open()
	# looks the pending offer up by.
	_end_summon(true)
	if spell == null:
		# Nothing will spawn, so nothing can adopt the offer. Withdraw it rather than
		# leaving a ring hanging over a cast that never happened.
		_discard_cast_sigil()
		return
	match special:
		SUMMON_RUSH:
			# Thunderclap / rush: LUNGE forward as the lance rips out.
			rig.set_aim(aim)
			rig.play(CharacterRig.State.PUNCH)
			rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.9, _element)
			if aim.x != 0.0:
				velocity.x = signf(aim.x) * 360.0
			SpellCaster.cast(spell, get_parent(), rig.get_weapon_tip(), target, _element_color, spell.effect, self, hostile_group)
		SUMMON_BLINK:
			# Shadow-step: TELEPORT to the marked point mid-slash. The displacement
			# itself lives in blink_to() below, which SpellCaster calls back into —
			# so blink now goes through the same data->dispatch seam as every other
			# spell instead of being hand-rolled here.
			SpellCaster.cast(spell, get_parent(), global_position, target, _element_color, spell.effect, self, hostile_group)
			rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
			rig.play(CharacterRig.State.CAST)
		_:
			rig.set_aim(Vector2.UP if sky else aim)
			rig.play(CharacterRig.State.CAST)
			var origin: Vector2 = global_position if sky else rig.get_weapon_tip()
			# `self` is passed on the plain path too now: a deferred-resolution
			# spell (Rift Dagger) needs to know whose anchor it is, and the arg is
			# ignored by every kind that doesn't move or own the caster.
			SpellCaster.cast(spell, get_parent(), origin, target, _element_color, spell.effect, self, hostile_group)
			_self_recoil(110.0)  # the ultimate shoves you back
	_notify_element_used()
	# THE PAYOFF — the crescendo after the anticipation. Blink already flashes, so
	# skip the heavy speed-line frame on it; the planted/rush eruptions get it.
	Juice.epic_moment({"strength": 1.0, "frame": special != SUMMON_BLINK})


## Shared summon teardown: put the hero back on the ground, clear state, and either
## hand the sigil on or dismiss it.
##
## EVERY exit runs through here — the spell firing, a hit shattering the windup, a
## co-op down, a revive — which is the whole reason the levitation is undone here
## and nowhere else. The windup branch returns before gravity is integrated, so a
## cast that ended mid-lift without this restore would leave the hero parked in
## mid-air with no force to bring them back down.
##
## `handoff` true = a spectacle is about to spawn and should CONTINUE this sigil
## (no dismissal — dismissing is the duplicate-circle bug). False = the cast died,
## so there is nothing to hand it to and it goes out.
func _end_summon(handoff: bool = false) -> void:
	_summoning = false
	_summon_spell = null
	if _summon_lift != 0.0:
		global_position.y = _summon_base_y
		_summon_lift = 0.0
	_summon_lift_target = 0.0
	if is_instance_valid(rig):
		rig.set_airborne(0.0)
	if handoff:
		_release_cast_sigil()
	else:
		_discard_cast_sigil()


## A landed hit shatters the summon — sigil breaks, the ult is lost (MP + cooldown
## already spent, like the channel). Lighter feedback than the channel interrupt.
func _cancel_summon() -> void:
	var pos: Vector2 = global_position
	_end_summon()
	# The name goes with the cast. A card left hanging over a shattered windup reads
	# as "the ult went off" at the exact moment the player needs to know it did not.
	SignatureRite.dismiss(self)
	CombatVfx.spawn_burst(get_parent(), pos,
		Color(_element_color.r, _element_color.g, _element_color.b, 0.9),
		Color(_element_color.r, _element_color.g, _element_color.b, 0.0),
		14, 0.4, 60.0, 200.0, 1.0, 3.0)
	rig.flash_color(Color(0.7, 0.4, 0.9), 0.12)
	Juice.shake_camera(6.0)
	Sfx.play("melee_swing", -8.0, 0.0)


## Enter the levitating cast: lift off, lock the aim, grow a build-up sigil, hold
## a committed CAST pose. MP + cooldown are already spent (interrupt = no refund).
func _begin_channel(spell: SpellDef, sky: bool) -> void:
	_channeling = true
	_channel_spell = spell
	_channel_sky = sky
	_channel_timer = spell.cast_time
	_channel_total = spell.cast_time
	_channel_target = _aim_point()
	# The channelled tier is where the rite reads best: a 1.0-1.3 s windup gives the
	# card its full 0.30-0.39 s DECLARE and still leaves the longest CHARGE — i.e.
	# the longest dodge window — in the game.
	_declare_signature(spell, spell.cast_time, SpellTier.of(spell))
	_channel_base_y = global_position.y
	_channel_lift = 0.0
	velocity = Vector2.ZERO
	rig.set_aim(Vector2.UP if sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.set_airborne(true)  # legs dangle while floating
	# The channel gets the spell's own body language too, so a channelled wall still
	# reads as a slam and a beam still reads as a thrust. The channel's LENGTH stays
	# the spell's authored cast_time — that number is already the balance-tuned dodge
	# window, so it is never scaled by CastStyle/tier on top.
	rig.cast_gesture(_pose_gesture(CastStyle.for_spell(spell.kind)), 1.0, _element)
	# Build-up sigil that grows ABOVE the caster over the channel (maker: "the circle
	# should sit ABOVE"), opened through the SAME seam as the summon windup. This is
	# the path the reported duplicate-circle bug lives on — a channelled BEAM used to
	# dismiss this ring and then BeamSpell.fire() opened a second one at the muzzle —
	# so it matters most here that the sigil is handed over rather than dismissed.
	_open_cast_sigil(
		CHANNEL_SIGIL_RADIUS + CHANNEL_SIGIL_RADIUS_PER_COST * clampf(spell.mp_cost / 90.0, 0.0, 1.0),
		spell.cast_time)
	Sfx.play("charge_up", -2.0, 0.04)  # anime beam/ult power-up swell
	# Pull the camera WIDE for the whole build-up + release so the "insane spell"
	# reads (maker: "when these insane spells are being cast we should zoom out to
	# see the spell"). Hold spans the channel; the fire-time pull in SpellCaster
	# composes on top (max-of-amounts), and it eases back after the cast lands.
	Juice.zoom_pull_camera(0.26, spell.cast_time + 0.55, 0.2, 0.7)


## Per-frame while channeling: ease the levitation, hold the pose, count down, and
## on completion fire the spell (or the physics loop already returned early on cancel).
func _process_channel(delta: float) -> void:
	_channel_lift = move_toward(_channel_lift, CHANNEL_LIFT_HEIGHT, CHANNEL_LIFT_SPEED * delta)
	var bob: float = sin((_channel_total - _channel_timer) * 6.0) * 2.0
	global_position.y = _channel_base_y - _channel_lift + bob
	velocity = Vector2.ZERO
	rig.set_airborne(true)
	rig.set_body_velocity(Vector2.ZERO)
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		_cast_sigil.global_position = _cast_sigil_pos()
		# The sigil GROWS as the cast charges — small at first, large at release.
		var prog: float = 1.0 - _channel_timer / maxf(_channel_total, 0.001)
		_cast_sigil.scale = Vector2.ONE * (0.5 + 0.85 * prog)
	# Gather motes now and then — energy converging on the caster.
	if fmod(_channel_timer, 0.12) < delta:
		CombatVfx.spawn_burst(get_parent(), global_position, Color(_element_color.r, _element_color.g, _element_color.b, 0.7),
			Color(_element_color.r, _element_color.g, _element_color.b, 0.0), 6, 0.3, 40.0, 90.0, 0.5, 1.4, 0.0, 0.0, true)
	_channel_timer -= delta
	if _channel_timer <= 0.0:
		_finish_channel()


## Channel completed uninterrupted — unleash the spectacle, then settle back down.
func _finish_channel() -> void:
	var spell: SpellDef = _channel_spell
	# handoff: the build-up sigil survives the end of the channel so the spectacle
	# below can adopt it instead of opening a second ring at the muzzle.
	_end_channel(true)
	if spell == null:
		_discard_cast_sigil()  # nothing will spawn, so nothing can adopt it
		return
	rig.set_aim(Vector2.UP if _channel_sky else _aim_dir)
	rig.play(CharacterRig.State.CAST)
	var origin: Vector2 = global_position if _channel_sky else rig.get_weapon_tip()
	# `self` is the key MagicCircle.adopt_or_open() looks the pending offer up by, so
	# BeamSpell continues THIS sigil rather than opening a second one at the muzzle.
	# Kinds that don't want a caster ignore the argument.
	SpellCaster.cast(spell, get_parent(), origin, _channel_target, _element_color, spell.effect, self, hostile_group)
	_notify_element_used()
	_self_recoil(90.0)
	# The biggest beat in the game — the full synchronized epic payoff (the channeled
	# ults are the screen-fillers, so strength + speed-lines are dialed up).
	Juice.epic_moment({"strength": 1.25, "frame": true})


## A hit landed mid-channel — the ultimate is DISRUPTED (mana/cooldown stay spent).
## Make this UNMISTAKABLE (maker: "the interrupt isn't quite working properly" —
## it fired but read as nothing happening): the growing sigil SHATTERS in the
## element hue, the screen flashes + shakes hard, and the caster is flung out of
## the float. You should never wonder whether the ult got cut.
func _cancel_channel() -> void:
	if not _channeling:
		return
	var burst_pos: Vector2 = global_position
	if _cast_sigil != null and is_instance_valid(_cast_sigil):
		burst_pos = _cast_sigil.global_position
	var ec: Color = _element_color
	_end_channel()  # no handoff — an interrupted channel spawns nothing to adopt it
	SignatureRite.dismiss(self)  # the announcement dies with the cast it announced
	# Sigil shatter: a bright element-hued blowout ring of shards where the circle was.
	CombatVfx.spawn_burst(get_parent(), burst_pos,
		Color(ec.r, ec.g, ec.b, 0.95), Color(ec.r, ec.g, ec.b, 0.0),
		26, 0.45, 90.0, 280.0, 1.5, 3.2, 0.0, 0.0, true)
	# A grey "fizzle" puff over the caster reads as the spell collapsing.
	CombatVfx.spawn_burst(get_parent(), global_position, Color(0.7, 0.6, 0.75, 0.85),
		Color(0.3, 0.25, 0.4, 0.0), 14, 0.4, 50.0, 150.0)
	rig.flash_color(Color(0.85, 0.55, 1.0), 0.18)  # violet disrupt flash
	rig.apply_impulse(Vector2(-facing.x, 0.6), 260.0)  # flung out of the float
	# SILHOUETTE, not the white blow-out: this cut's payoff is a READABLE SHAPE, and
	# white erases the very crescent the beat exists to show off. The black cut keeps
	# the arc and both fighters lit against near-nothing.
	Juice.frame({"style": ImpactFrame.Style.SILHOUETTE, "strength": 0.95,
		"at": global_position + _aim_dir * 40.0})
	Juice.shake_camera(9.0)
	Sfx.play("hero_hurt", 0.0, 0.1)
	Sfx.play("melee_swing", -6.0, 0.14)


## Shared channel teardown: drop the float, restore physics, and either hand the
## sigil to the spectacle about to spawn (`handoff`) or put it out.
func _end_channel(handoff: bool = false) -> void:
	_channeling = false
	_channel_spell = null
	if is_instance_valid(rig):
		rig.set_airborne(false)
	if handoff:
		_release_cast_sigil()
	else:
		_discard_cast_sigil()


## Swap to the next equipped signature (the loadout cycle — V). On mobile this is
## a loadout selector, not a per-cast key, so the in-combat input set stays small.
func _cycle_signature() -> void:
	if _signatures.is_empty():
		return
	_signature_index = (_signature_index + 1) % _signatures.size()
	signature_changed.emit(_signatures[_signature_index].display_name)
	Sfx.play("footstep", -3.0, 0.25)


## Active signature (or null) — for the HUD label + cooldown/MP readout.
func current_signature() -> SpellDef:
	if _signatures.is_empty():
		return null
	return _signatures[_signature_index]


## Hand index of signature slot `i`. See `_hand`'s note: FISTS permanently occupies
## hand index 0, so the kit starts one along. Never do this arithmetic inline.
func _hand_slot(sig_index: int) -> int:
	return sig_index + HAND_SPELL_OFFSET


## Seconds left on signature slot `i` — the per-slot replacement for reading the old
## shared `_signature_cd_timer`. Public so the HUD, the bots and the tests all ask the
## same question of the same owner instead of three of them keeping their own copy.
func signature_cooldown(sig_index: int) -> float:
	return _hand.cooldown(_hand_slot(sig_index))


func signature_ready(sig_index: int) -> bool:
	return _hand.is_ready(_hand_slot(sig_index))


func signature_cooldown_ratio() -> float:
	var s: SpellDef = current_signature()
	if s == null or s.cooldown <= 0.0:
		return 0.0
	return clampf(signature_cooldown(_signature_index) / s.cooldown, 0.0, 1.0)


## Rogue dash-strike: every enemy/crate the dash passes within range takes melee
## damage once per dash (dedupe via _dash_hit). Mirrors _on_melee_hit_frame.
func _dash_strike_sweep() -> void:
	var rng: float = _cfg["dash_strike_range"]
	var dmg: int = _cfg["dash_strike_damage"]
	var hit_any: bool = false
	# SILHOUETTE, NOT ORIGIN. This used to be `distance_to(enemy.global_position)`,
	# a zero-size point test against a node origin that sits ~10 px BELOW the drawn
	# head (19 px on the 1.9x sparring dummies) — the maker's "spells pass through
	# heads without registering" bug, in its melee form. `SpellTargets` measures the
	# drawn body and adds the target's OWN published forgiveness, and it filters
	# line-of-sight so a dash can no longer strike through a wall it passed beside.
	#
	# ⚠ The reach GROWS as a result — up to about half a rig height on the vertical
	# axis — and that growth is the fix, not a side effect. If dash-strike ever feels
	# too generous the knob is `dash_strike_range` in CLASS_CONFIG or
	# `Enemy.HIT_MARGIN_FACTOR`, never both, and never a third margin added here.
	for enemy: Node in SpellTargets.in_radius(global_position, rng,
			get_tree().get_nodes_in_group(attack_group()), [self], self):
		if enemy in _dash_hit:
			continue
		_dash_hit.append(enemy)
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(_dash_dir * _melee_knockback)
		hit_any = true
	for prop: Node in SpellTargets.in_radius(global_position, rng,
			get_tree().get_nodes_in_group("destructible"), [self], self):
		if prop in _dash_hit:
			continue
		_dash_hit.append(prop)
		if prop.has_method("take_damage"):
			prop.take_damage(dmg)
		hit_any = true
	if hit_any:
		Juice.hit_stop(0.05)
		Juice.shake_camera(4.0)
		Sfx.play("melee_hit")


func _start_dash() -> void:
	is_dashing = true
	_dash_timer = _tune("dash_time", DASH_TIME)
	_dash_cooldown_timer = _cfg["dash_cd"]
	# Dash the EXACT angle of the held movement keys (true 8-way): W+D -> up-right,
	# S+A -> down-left, D alone -> flat right. Accurate to which keys are down,
	# including vertical. Falls back to live velocity, then the last walk dir /
	# facing, only when no direction key is held (a standing dash).
	var keys: Vector2 = _vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if keys.length() > 0.1:
		_dash_dir = keys.normalized()
	elif velocity.length() > 40.0:
		_dash_dir = velocity.normalized()
	elif _move_dir != Vector2.ZERO:
		_dash_dir = _move_dir
	else:
		_dash_dir = Vector2(signf(facing.x), 0.0) if facing.x != 0.0 else Vector2.RIGHT
	_ghost_timer = 0.0  # first afterimage lands this frame
	_dash_hit.clear()


## Shadow blink: instant teleport BLINK_DISTANCE along the MOVEMENT direction,
## phasing THROUGH walls (no clamp — mobile-friendly, no aim needed). Leaves a
## dark silhouette + violet poof at the origin, another poof + bright flash at
## the destination, and grants BLINK_IFRAME seconds of invulnerability. Buffered
## like dash/melee/blast; only reachable from the not-dashing path.
func _blink() -> void:
	# Brawler can't teleport — its R is a launcher UPPERCUT that pops enemies into
	# the air (double-jump after them to juggle).
	if String(_cfg.get("mobility2", "blink")) == "uppercut":
		_uppercut()
		return
	if _blink_cooldown_timer > 0.0:
		return
	_blink_cooldown_timer = _cfg["blink_cd"]
	_blink_iframe_timer = BLINK_IFRAME
	var origin: Vector2 = global_position
	# Blink along the MOVEMENT/walk direction (mobile-friendly — no aim needed),
	# phasing THROUGH walls a fixed BLINK_DISTANCE. _move_dir persists the last
	# walk direction, so a standing blink still fires (falls back to RIGHT).
	var dir: Vector2 = _move_dir
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	# Land THROUGH walls but never INSIDE one (relocate a blocked endpoint).
	var dest: Vector2 = _safe_blink_destination(origin, origin + dir.normalized() * BLINK_DISTANCE)
	# Shadow-poof where we WERE: dark fading silhouette + violet burst.
	rig.spawn_ghost(get_parent(), BLINK_SHADOW_COLOR, Vector2.ZERO, Vector2.ZERO, 0.35)
	CombatVfx.spawn_burst(
		get_parent(), origin, BLINK_BURST_START, BLINK_BURST_END,
		18, 0.35, 40.0, 110.0, 1.5, 3.0
	)
	global_position = dest
	velocity.y = 0.0  # don't inherit fall speed -> no "heavy gravity" right after a blink
	# Arrival poof: bigger burst + a quick bright flash on the rig.
	CombatVfx.spawn_burst(
		get_parent(), dest, BLINK_BURST_START, BLINK_BURST_END,
		24, 0.4, 60.0, 140.0, 1.5, 3.5
	)
	rig.flash_color(BLINK_ARRIVAL_FLASH_COLOR, BLINK_ARRIVAL_FLASH_TIME)
	rig.play(CharacterRig.State.CAST)
	Sfx.play("blink", 0.0, 0.1)  # dedicated synth "vwip" teleport sound


## BRAWLER uppercut (R) — a rising launcher: the hero hops and everything in a
## short forward range is popped UP (sets up an air-juggle with the double-jump).
func _uppercut() -> void:
	if _blink_cooldown_timer > 0.0:
		return
	_blink_cooldown_timer = maxf(_cfg["blink_cd"], 1.1)
	rig.set_facing(_aim_dir)
	rig.play(CharacterRig.State.KICK)
	velocity.y = -320.0  # the hero rises with the uppercut
	var face_x: float = signf(_aim_dir.x) if _aim_dir.x != 0.0 else 1.0
	var hit_any: bool = false
	# A launcher is the one melee move whose whole point is VERTICAL, so an
	# origin-point test was the worst possible fit: it measured to a spot below the
	# head of the very thing it is trying to pop into the air. Silhouette-measured
	# now, in a wedge that is the forward half plus a small overlap behind — which is
	# what the old `signf(to.x) != face_x and absf(to.x) > 10.0` clause was
	# approximating for a body standing directly on top of you.
	const UPPERCUT_REACH: float = 70.0
	const UPPERCUT_DOT: float = -0.2
	for enemy: Node in SpellTargets.in_cone(global_position, Vector2(face_x, 0.0),
			UPPERCUT_REACH, UPPERCUT_DOT, get_tree().get_nodes_in_group(attack_group()),
			[self], self):
		if enemy.has_method("take_damage"):
			enemy.take_damage(18)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(Vector2(face_x * 120.0, -470.0))  # POP up + slight away
		if enemy.has_method("apply_status"):
			enemy.apply_status(_element)
		hit_any = true
	CombatVfx.spawn_burst(
		get_parent(), global_position + Vector2(face_x * 20.0, -6.0),
		Color(1.0, 0.9, 0.5, 0.8), Color(1.0, 0.5, 0.15, 0.0), 12, 0.3, 60.0, 180.0
	)
	Sfx.play("melee_hit")
	if hit_any:
		Juice.hit_stop(0.06)
		Juice.shake_camera(5.0)


## Blink landing safety: the endpoint may never rest INSIDE a solid. Test the
## destination against layer-1 solids; if blocked, probe forward past a thin wall,
## then back toward the origin, returning the first clear spot. Phasing THROUGH a
## wall mid-blink stays fine — only the resting spot matters.
## SpellCaster's BLINK_STRIKE callback (duck-typed `blink_to`): vet the requested
## landing spot, actually move, and return where we ENDED UP so the slash is drawn
## to the real destination. Hero's own rule — never blink into a pit or a wall —
## stays owned here rather than leaking into the generic dispatcher.
func blink_to(dest: Vector2) -> Vector2:
	var safe: Vector2 = _safe_blink_destination(global_position, dest)
	global_position = safe
	velocity.y = 0.0
	_blink_iframe_timer = BLINK_IFRAME
	return safe


func _safe_blink_destination(origin: Vector2, dest: Vector2) -> Vector2:
	var world: World2D = get_world_2d()
	if world == null:
		return dest  # headless / no physics world — leave as-is
	var shape: Shape2D = _blink_shape()
	if shape == null:
		return dest
	var space: PhysicsDirectSpaceState2D = world.direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = BLINK_WALL_MASK
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	var span: Vector2 = dest - origin
	if span.length() < 1.0:
		return dest
	var dir: Vector2 = span.normalized()
	q.transform = Transform2D(0.0, dest)
	if space.intersect_shape(q, 1).is_empty() and not _dest_in_pit(dest):
		return dest  # clear — the common case
	# Blocked (solid OR over the void): look for daylight just PAST a thin wall first...
	var d: float = BLINK_PROBE_STEP
	while d <= BLINK_PROBE_EXTRA:
		var pf: Vector2 = dest + dir * d
		q.transform = Transform2D(0.0, pf)
		if space.intersect_shape(q, 1).is_empty() and not _dest_in_pit(pf):
			return pf
		d += BLINK_PROBE_STEP
	# ...else fall back toward the origin (which is on the map) — this is what
	# "limits it to where you can actually teleport": you slide back onto solid map.
	var max_back: float = span.length()
	d = BLINK_PROBE_STEP
	while d <= max_back:
		var pb: Vector2 = dest - dir * d
		q.transform = Transform2D(0.0, pb)
		if space.intersect_shape(q, 1).is_empty() and not _dest_in_pit(pb):
			return pb
		d += BLINK_PROBE_STEP
	return origin  # nowhere clear — don't move


## True if `pos` lands inside a ring-out PIT (a StageHazard in PIT mode), plus a
## margin off the lip. Loose group + property lookup so Hero doesn't hard-depend on
## StageHazard. Headless (no stage_hazard group) -> always false, so blink tests
## are unaffected. Mode.PIT == 0.
func _dest_in_pit(pos: Vector2) -> bool:
	for h: Node in get_tree().get_nodes_in_group("stage_hazard"):
		if not h is Node2D or int(h.get("mode")) != 0:
			continue
		var size_v: Variant = h.get("zone_size")
		if not size_v is Vector2:
			continue
		var half: Vector2 = (size_v as Vector2) * 0.5 + Vector2(BLINK_PIT_MARGIN, BLINK_PIT_MARGIN)
		var rel: Vector2 = pos - (h as Node2D).global_position
		if absf(rel.x) <= half.x and absf(rel.y) <= half.y:
			return true
	return false


## The hero's own collision shape (found at runtime — no hard-coded node name).
func _blink_shape() -> Shape2D:
	for c: Node in get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null:
			return (c as CollisionShape2D).shape
	return null


## The LMB PRIMARY — dispatched per class so no two classes attack the same way:
## melee_combo (Brawler punch/kick, no magic), heavy_swing (Juggernaut wide slow
## hammer), frost_cone (Cryomancer chilling cone), or a bolt with per-class flavour
## flags (plain / heal / drain / chain / burst). This is the core "classes feel
## different, not just different spells" fix.
func _cast() -> void:
	match String(_cfg.get("primary", "bolt")):
		"melee_combo":
			_primary_melee_combo()
		"heavy_swing":
			_primary_heavy_swing()
		"frost_cone":
			_primary_frost_cone()
		_:
			_primary_bolt()


## Ranged bolt with per-class flavour: bolt_heal (Cleric/Warlock lifesteal),
## bolt_chain (Stormcaller arc), bolt_burst (Shadowblade flurry, spread shots).
func _primary_bolt() -> void:
	_cast_cooldown_timer = _cfg["cast_cd"]
	# The bolt goes EXACTLY where the player is pointing. It used to be bent toward
	# an enemy inside a forgiveness cone, which is aim assist by another name: the
	# locked rule is that hitting is the shooter's skill and dodging is the target's,
	# and a cone that quietly corrects a near-miss steals from both sides of that.
	# Forgiveness now has to come from the spell's SHAPE (width/arc/burst spread),
	# never from the engine steering it after release.
	var base_dir: Vector2 = _aim_dir.normalized() if _aim_dir != Vector2.ZERO else facing
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.5, _element)  # quick hand-flick tell
	var origin: Vector2 = rig.get_weapon_tip()
	var burst: int = int(_cfg.get("bolt_burst", 1))
	var spread: float = float(_cfg.get("bolt_spread", 0.0))
	for i: int in maxi(burst, 1):
		# Fan a burst symmetrically around the aim (single shot -> no offset).
		var off: float = 0.0 if burst <= 1 else (float(i) - float(burst - 1) * 0.5) * spread
		var dir: Vector2 = base_dir.rotated(off)
		var spell: Area2D = SPELL_SCENE.instantiate()
		get_parent().add_child(spell)
		spell.global_position = origin
		spell.launch(dir)
		if spell.has_method("set_element_color"):
			spell.call("set_element_color", _element_color)
		spell.set("element_id", _element)
		if bool(_cfg["throw_blade"]):
			spell.set("damage", int(_cfg["blade_damage"]))
		# WHOSE SIDE THE BOLT IS ON. A method rather than a field write because
		# it also opens the hero collision layer on the projectile: a
		# hero-hostile bolt that never gets that mask bit passes clean through
		# its target with damage code that looks perfectly correct.
		spell.call("set_hostile_group", attack_group())
		# Caster is set for EVERY class's bolt (not just heal-flavoured ones) so the
		# friendly-fire guard in Spell.gd can always exclude the caster from their
		# own bolt — MAGE/STORMCALLER/ROGUE bolts were previously spawning with
		# caster == null and could hit their own thrower.
		spell.set("caster", self)
		# ...and its WEIGHT. Without this the bolt reports SpellTier.DEFAULT_WEIGHT
		# (HEAVY), so a free, spammable primary would trade evenly in a clash against
		# a committed heavy spell, and would be read as HEAVY by the deflect window
		# fraction. A basic cast belongs on the QUICK shelf.
		spell.set("spell_tier", SpellTier.Tier.QUICK)
		# Flavour flags.
		var heal: int = int(_cfg.get("bolt_heal", 0))
		if heal > 0:
			spell.set("heal_on_hit", heal)
		var chain: int = int(_cfg.get("bolt_chain", 0))
		if chain > 0:
			spell.set("chain_count", chain)
	Sfx.play("cast", 0.0, 0.08)
	Juice.shake_camera(1.0)
	_notify_element_used()


## BRAWLER primary — a punch→punch→KICK melee combo that steps you forward. No
## projectile. The melee cooldown gates the cadence, so holding LMB auto-combos;
## every 3rd swing is a launcher kick. Reuses the rig PUNCH/KICK + hit_frame path.
func _primary_melee_combo() -> void:
	if _melee_cooldown_timer > 0.0:
		return
	rig.set_facing(_aim_dir)
	_melee()  # alternates PUNCH/KICK via _melee_kick_next, sets _melee_cooldown, swing sfx
	# Step INTO the combo so the boxer walks his punches forward.
	if _aim_dir.x != 0.0:
		velocity.x = signf(_aim_dir.x) * 200.0


## JUGGERNAUT primary — a slow, wide overhead hammer swing that staggers a crowd.
## Wide arc + big knockback come from the per-class melee params (configure_class);
## the slow _melee_cd is the commitment.
func _primary_heavy_swing() -> void:
	if _melee_cooldown_timer > 0.0:
		return
	rig.set_facing(_aim_dir)
	rig.play(CharacterRig.State.PUNCH)
	# Smaller wind-up (maker: "make the charge up for the heavys just slightly smaller").
	rig.cast_gesture(CharacterRig.GestureKind.STOMP, 0.4, _element)
	# STEP INTO the swing so the heavy actually closes + CONNECTS (maker: the heavy
	# attacks "aren't working" — they were whiffing at its short reach). The lunge +
	# the wider reach (CLASS_CONFIG) make the hammer land instead of swinging air.
	if _aim_dir.x != 0.0:
		velocity.x = signf(_aim_dir.x) * 190.0
	_melee_cooldown_timer = _melee_cd
	Sfx.play("melee_swing", 0.0, 0.12)


## CRYOMANCER primary — a short-range FROST CONE (no projectile): every enemy in
## the forward arc is chilled (2nd stack freezes) + lightly shoved. Forces mid-range.
func _primary_frost_cone() -> void:
	if _cast_cooldown_timer > 0.0:
		return
	_cast_cooldown_timer = _cfg["cast_cd"]
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.6, _element)  # frost coats the hand
	const CONE_RANGE: float = 118.0
	const CONE_COS: float = 0.5  # ~60° half-angle
	const CONE_DAMAGE: int = 12
	var hit_any: bool = false
	# The cone is now measured against the DRAWN body and line-of-sight filtered,
	# through the same selector every spell uses. It was the clearest instance of the
	# head bug in a primary attack: a frost cone aimed at head height resolved
	# against an origin ~10 px lower and simply did not connect.
	for enemy: Node in SpellTargets.in_cone(global_position, _aim_dir, CONE_RANGE,
			CONE_COS, get_tree().get_nodes_in_group(attack_group()), [self], self):
		var to: Vector2 = (enemy as Node2D).global_position - global_position
		if enemy.has_method("take_damage"):
			enemy.take_damage(CONE_DAMAGE)
		if enemy.has_method("apply_status"):
			enemy.apply_status(_element)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(to.normalized() * 160.0)
		hit_any = true
	# Frost fan VFX along the aim.
	var fan_at: Vector2 = global_position + _aim_dir * CONE_RANGE * 0.55
	CombatVfx.spawn_burst(
		get_parent(), fan_at, Color(0.85, 0.97, 1.0, 0.9), Color(0.5, 0.8, 1.0, 0.0),
		20, 0.32, 120.0, 260.0, 0.6, 1.8
	)
	Sfx.play("cast", -2.0, 0.06)
	if hit_any:
		Juice.shake_camera(2.0)
	_notify_element_used()


## Heal the hero (Cleric/Warlock lifesteal, Cleric heal-nova). Clamps to max_hp.
func heal(amount: int) -> void:
	if amount <= 0 or hp >= max_hp:
		return
	hp = mini(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)
	rig.flash_color(Color(0.6, 1.0, 0.7), 0.08)  # a soft green heal tick


## The Q slot — dispatched on the class's AoE variant. Every variant carries the
## hero's ACTIVE element (so a Brawler who cycles to Ice throws an ice-punch).
func _blast() -> void:
	_blast_cooldown_timer = _cfg["blast_cd"]
	_self_recoil(80.0)  # the giant blast kicks the caster back
	match String(_cfg["aoe"]):
		"nova":
			_spawn_nova()          # rogue whirlwind
		"fist_shock":
			_fire_punch()          # brawler — lunging elemental shockwave
		"ground_slam":
			_ground_slam()         # juggernaut — self-centred crater
		"arcane_meteor":
			_arcane_meteor()       # arcanist — arcane star-fall barrage
		"consecrate":
			_consecrate()          # cleric — hallowed ground field
		"ice_shards":
			_ice_shards()          # cryomancer — homing frost shard spray
		"call_lightning":
			_call_lightning()      # stormcaller — lightning strike column
		"curse_chain":
			_curse_chain()         # warlock — leaping shadow chain
		_:
			_meteor_blast()        # placed giant blast (fallback)


## Placed giant blast: lands where the cursor points, clamped to a max cast range
## so it stays a skill-shot, not a whole-stage snipe.
func _meteor_blast() -> void:
	var to_target: Vector2 = _aim_point() - global_position
	if to_target.length() > BLAST_MAX_RANGE:
		to_target = to_target.normalized() * BLAST_MAX_RANGE
	var target_pos: Vector2 = global_position + to_target
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.set("element_id", _element)
	_stamp_faction(blast)
	# OWNERSHIP. A spectacle with no caster reports as "unowned", which satisfies
	# neither `require_owner: "same"` nor `"different"` — so it matches NO clash row
	# and is silently inert in the entire reaction system. Nothing errors; the spell
	# simply never reacts with anything, which is the single most repeated bug in
	# this codebase.
	blast.set("caster_node", self)
	blast.detonate_at(target_pos)
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.65, _element)  # arm gathers, lobs the blast


## FIRE PUNCH — the Brawler's Q. A lunging straight that erupts an elemental
## shockwave just in front of the fist: instant (no windup), tight radius, HUGE
## knockback + the active element's ailment. Reads as a committed melee blast.
func _fire_punch() -> void:
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.PUNCH)
	rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.8, _element)  # the FIST ignites
	# A short forward lunge so the punch drives INTO the target.
	velocity.x = signf(_aim_dir.x) * 300.0 if _aim_dir.x != 0.0 else velocity.x
	var center: Vector2 = global_position + _aim_dir.normalized() * 44.0
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.call("configure", {
		"target_group": String(attack_group()), "damage": 30, "radius": 66.0,
		"knockback": 430.0, "element_id": _element,
	})
	blast.set("caster_node", self)  # unowned = inert in the reaction layer (see _blast)
	blast.call("detonate_now", center)
	# The PUNCH beat, graded off the shared tier ladder rather than a bare 0.8 — a
	# punch is a physical concussion, so it lands on BLOWOUT, and it now reads as
	# lighter than an ult instead of matching one. Localized on the blast, because
	# an unpositioned frame whites out screen centre wherever the hit actually was.
	Juice.tier_frame(SpellTier.Tier.HEAVY, center, _element)


## GROUND SLAM — the Juggernaut's Q. A small hop then a self-centred crater: wide
## radius, heavy knockback + the active element's ailment (Stagger by default).
func _ground_slam() -> void:
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.STOMP, 0.8, _element)  # fist drives down
	velocity.y = -240.0  # a small hop into the slam
	var blast: Node2D = BLAST_SCENE.instantiate()
	get_parent().add_child(blast)
	blast.call("configure", {
		"target_group": String(attack_group()), "damage": 34, "radius": 98.0,
		"knockback": 380.0, "element_id": _element,
	})
	blast.set("caster_node", self)  # unowned = inert in the reaction layer (see _blast)
	blast.call("detonate_now", global_position)


## Energy nova: instant self-centered shockwave. No telegraph — the panic
## button fires the moment the press lands (buffered like blast/blink). Mage
## only; the rogue's whirlwind reuses _spawn_nova through _blast.
func _nova() -> void:
	if not bool(_cfg["has_nova"]):
		return
	if _nova_cooldown_timer > 0.0:
		return
	_nova_cooldown_timer = NOVA_COOLDOWN
	_spawn_nova()


func _spawn_nova() -> void:
	var nova: Node2D = NOVA_SCENE.instantiate()
	get_parent().add_child(nova)
	nova.set("element_id", _element)
	_stamp_faction(nova)
	nova.call("activate_at", global_position)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.6, _element)  # arms fling out the nova


## Point a spectacle this file spawned DIRECTLY at this hero's faction.
##
## The per-class Q's below bypass `SpellCaster.cast` (they hand-build their
## spectacle from a `load()`ed script), so they miss `SpellCaster._stamp` and
## would otherwise keep the `"enemy"` default forever — the exact silent gap that
## made hero-vs-hero inert. Both property spellings are written for the same
## reason and with the same safety as the stamp: `set()` on a property a
## spectacle has not declared is a silent no-op, so a spectacle that hard-codes
## its target group today simply starts obeying this the day it grows the field.
func _stamp_faction(node: Node) -> void:
	node.set("target_group", String(attack_group()))
	node.set("_target_group", String(attack_group()))


## Cursor target for a placed Q, clamped to BLAST_MAX_RANGE so it stays a skill-shot.
func _aoe_target() -> Vector2:
	var to_target: Vector2 = _aim_point() - global_position
	if to_target.length() > BLAST_MAX_RANGE:
		to_target = to_target.normalized() * BLAST_MAX_RANGE
	return global_position + to_target


# ---- Per-class DISTINCT Q spectacles (maker: "Q's are just reworks of each other
# — give each CLASS a distinct epic Q, not a recolored blast"). Each reuses a
# proven spectacle scene in a config distinct from that class's G signature, and
# carries the hero's ACTIVE element. Runtime-load()ed (never preload) so the
# headless slice harness that compiles Hero doesn't early-compile these.

## ARCANIST Q — Arcane Storm: a short barrage of arcane meteors rains on the cursor.
func _arcane_meteor() -> void:
	var meteor: Node2D = (load("res://scripts/combat/MeteorSigil.gd") as GDScript).new()
	get_parent().add_child(meteor)
	meteor.set("element_id", _element)
	_stamp_faction(meteor)
	meteor.call("rain", _aoe_target(), _element_color, 92.0, 22, 5, Elements.effect_name(_element))
	rig.set_aim(Vector2.UP)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.7, _element)


## CLERIC Q — Consecrate: hallowed ground pulses holy damage where the cursor points.
func _consecrate() -> void:
	var zone: Node2D = (load("res://scripts/combat/ZoneSpell.gd") as GDScript).new()
	get_parent().add_child(zone)
	zone.set("element_id", _element)
	_stamp_faction(zone)
	zone.call("open", _aoe_target(), _element_color, 98.0, 11, Elements.effect_name(_element), 4.0)
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.6, _element)


## CRYOMANCER Q — Ice Shards: a spray of homing frost shards toward the aim.
func _ice_shards() -> void:
	var orbs: Node2D = (load("res://scripts/combat/RuneOrbs.gd") as GDScript).new()
	get_parent().add_child(orbs)
	orbs.set("element_id", _element)
	_stamp_faction(orbs)
	orbs.call("launch", rig.get_weapon_tip(), _aim_dir.normalized(), _element_color, 6, 18, Elements.effect_name(_element))
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.7, _element)


## STORMCALLER Q — Call Lightning: a bolt column crashes down on the cursor.
func _call_lightning() -> void:
	var ray: Node2D = (load("res://scripts/combat/DivineRay.gd") as GDScript).new()
	get_parent().add_child(ray)
	ray.set("element_id", _element)
	_stamp_faction(ray)
	ray.call("strike", _aoe_target(), _element_color, 74.0, 34, Elements.effect_name(_element))
	rig.set_aim(Vector2.UP)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.RAISE, 0.7, _element)


## WARLOCK Q — Curse Chain: a shadow bolt leaps enemy-to-enemy from the aim.
func _curse_chain() -> void:
	var ch: Node2D = (load("res://scripts/combat/ChainBolt.gd") as GDScript).new()
	get_parent().add_child(ch)
	ch.set("element_id", _element)
	_stamp_faction(ch)
	ch.call("chain", rig.get_weapon_tip(), _aim_dir.normalized(), _element_color, 4, 240.0, 30, Elements.effect_name(_element))
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.cast_gesture(CharacterRig.GestureKind.FLICK, 0.7, _element)


## Open the perfect-timing parry window (rogue only, off cooldown). The reward
## (ding + reflect) only fires if a bolt actually arrives during the window —
## see try_parry(). The opening itself is a quick blade-flash tell.
func _try_parry_start() -> void:
	if not bool(_cfg["can_parry"]):
		return  # class can't parry (mage)
	if _parry_cooldown_timer > 0.0:
		return
	_parry_window_timer = _parry_window_len
	_parry_cooldown_timer = PARRY_COOLDOWN
	# The Stick-Fight block: a white curved shield SHELL thrown up in the aim
	# direction (the tell), plus an arm-raise. No omni flash/burst.
	rig.set_aim(_aim_dir)
	rig.play(CharacterRig.State.CAST)
	rig.set_parry(_aim_dir, PARRY_SHIELD_TIME)
	Sfx.play("melee_swing", -2.0, 0.1)


## Called by an incoming enemy bolt as it reaches the hero. If the parry window is
## open, send the bolt back out ALONG THE SHIELD'S FACING — i.e. wherever the
## player is aiming — pay out the reward juice (bright ding + hitstop + flash), and
## return true; the bolt keeps flying, now hostile to enemies. One reflect per window.
##
## It used to redirect at the nearest enemy, which made a parry a homing missile:
## you only had to get the TIMING right and the engine picked the victim. Two
## honest options were on the table — bounce it straight back along the incoming
## line (return-to-sender), or send it along the defender's aim. The aim wins,
## because the incoming line is chosen by the ATTACKER, so return-to-sender still
## leaves the defender with nothing to steer. Aim makes a parry two skills stacked:
## time the window AND have the shield pointed where you want the bolt to go. It
## also matches what is already on screen — _try_parry_start throws the shell up in
## _aim_dir, so the bolt leaving along that same line is the picture you just saw.
func try_parry(proj: Node) -> bool:
	# Two guards, one answer. The press-window classes consume their window on a
	# reflect (one per press); the BLADE ring does NOT — its ~0.09 s perfect band is
	# already the whole limit, and consuming on top would mean a wall of arrows costs
	# a Swordsaint one deflect and then hits them with the rest, which is the
	# opposite of what holding a blade in the way looks like.
	var ring_perfect: bool = _guard != null and _guard.can_reflect()
	if _parry_window_timer <= 0.0 and not ring_perfect:
		return false
	if not is_instance_valid(proj) or not proj.has_method("reflect"):
		return false
	var dir: Vector2 = _aim_dir.normalized() if _aim_dir != Vector2.ZERO else facing
	proj.reflect(dir, _element_color)
	Sfx.play("ding", 2.0, 0.02)  # the whole payoff — a crisp, loud parry ding
	Juice.hit_stop(0.09)
	Juice.shake_camera(4.0)
	# Snap the shield toward where the bolt was sent — a bright deflect flourish.
	rig.set_parry(dir, PARRY_SHIELD_TIME)
	rig.flash_color(PARRY_FLASH_COLOR, 0.1)
	if not ring_perfect:
		_parry_window_timer = 0.0
	return true


## SpellDeflect's victim contract. A held BLADE guard reports as parrying whenever
## it is doing ANYTHING — a perfect read or the weaker sustained bottom-out — so a
## spell that only chips through a sustain still routes through the deflect path
## and still reads as "I blocked that".
func is_parrying() -> bool:
	if _parry_window_timer > 0.0:
		return true
	return _guard != null and _guard.quality() != ParryRing.Quality.NONE


## SpellDeflect's optional freshness hook, and the ONE place the two guard shapes
## genuinely differ in outcome.
##
## The press-window classes return 1.0 whenever their window is open. That is not
## laziness — it preserves TODAY'S behaviour exactly: Hero previously had no
## `parry_freshness` at all, and `SpellDeflect.would_deflect` treats a missing
## method as fully lenient. Returning a decaying value here would silently make
## every ult in the game far harder for eight shipped classes to block, under cover
## of adding a ninth.
##
## The BLADE ring reports `ParryRing.freshness()`, which is 1.0 on a PERFECT read
## and 0.0 on a SUSTAIN. Against `SpellDeflect.WINDOW_ULT` (0.22) only the perfect
## read clears the bar, so the asymmetry falls out of the ring rather than being
## invented here: a Swordsaint can eat an ult, but only by closing the ring exactly
## on it — holding a guard up will never do it.
func parry_freshness() -> float:
	if _parry_window_timer > 0.0:
		return 1.0
	return _guard.freshness() if _guard != null else 0.0


## A non-travelling spell was eaten by the guard (SpellDeflect's optional hook).
## Strike the pose toward it; the bank is handled in take_damage, which is the only
## place that knows how much was turned away.
func on_spell_deflected(dir: Vector2) -> void:
	if is_instance_valid(rig):
		rig.set_parry(dir if dir != Vector2.ZERO else _aim_dir, PARRY_SHIELD_TIME)
		rig.flash_color(PARRY_FLASH_COLOR, 0.1)


# --------------------------------------------------------------- BLADE GUARD
## Per-frame guard handling for a `defense: "held_guard"` class. Press to bloom the
## ring, hold to close it, release to cash whatever it banked.
##
## The ring's own clock is ticked at the top of `_physics_process` (so the re-arm
## runs even while committed); this is only input, pose and the deflect sweep.
func _process_blade_guard(delta: float) -> void:
	if is_dashing:
		return
	if _just(&"parry"):
		if _guard.press():
			_guard_bank = 0
			_guard_hits = 0
			# The tell is the same Stick-Fight shell every other class throws up, so
			# an opponent reads "they are guarding" identically whoever it is. What
			# differs is what happens next, not what it looks like starting.
			rig.set_aim(_aim_dir)
			rig.set_parry(_aim_dir, ParryRing.SHRINK_TIME + 0.2)
			Sfx.play("melee_swing", -4.0, 0.14)
	elif _released(&"parry"):
		_release_blade_guard()
	if _guard.held:
		# Hold the plant: the blade tracks the aim so the guard is directional, and
		# the shell is refreshed so it never blinks out mid-hold.
		rig.set_aim(_aim_dir)
		rig.set_parry(_aim_dir, 0.12)
		rig.play(CharacterRig.State.CAST)
		_guard_deflect_sweep()
		# Auto-cash at the bank limit. Holding past three turned hits would let a
		# Swordsaint stand in a barrage and walk out with a capped return for free;
		# forcing the release makes the third block the DECISION point.
		if _guard_hits >= GUARD_BANK_HITS:
			_release_blade_guard()


## Let go. Cash the bank as an unsheathe cut, then start the ring's re-arm.
func _release_blade_guard() -> void:
	if _guard == null or not _guard.held:
		return
	var banked: int = _guard_bank
	_guard.release()
	_guard_bank = 0
	_guard_hits = 0
	if banked > 0:
		_unsheathe_cut(banked)


## THE PAYMENT. A short line along the aim carrying `banked * GUARD_RETURN_MULT`.
##
## A LINE and not a circle, on purpose: an omni-burst would make the guard a
## panic button that punishes everyone who happened to be nearby, whereas a line
## means you must still be pointed at the thing you blocked. It is aimed with
## `_aim_dir`, so it is a real aim decision and never an auto-target.
func _unsheathe_cut(banked: int) -> void:
	var dmg: int = int(round(float(banked) * GUARD_RETURN_MULT))
	var dir: Vector2 = _aim_dir.normalized() if _aim_dir != Vector2.ZERO else facing
	rig.set_aim(dir)
	rig.play(CharacterRig.State.PUNCH)
	var pool: Array = get_tree().get_nodes_in_group(attack_group())
	pool.append_array(get_tree().get_nodes_in_group("destructible"))
	# Silhouette-aware, line-of-sight filtered — the same selector every spell now
	# uses, so the cut cannot reach a body through a wall and cannot pass through a
	# head without registering.
	var hit_any: bool = false
	for n: Node in SpellTargets.on_line(global_position, dir, GUARD_CUT_RANGE,
			GUARD_CUT_HALF_WIDTH, pool, [self], self):
		if n.is_in_group("destructible"):
			if n.has_method("take_damage"):
				n.call("take_damage", dmg)
			hit_any = true
			continue
		if n.has_method("take_damage"):
			n.call("take_damage", dmg)
		if n.has_method("apply_knockback"):
			n.call("apply_knockback", dir * GUARD_CUT_KNOCKBACK)
		hit_any = true
	CombatVfx.spawn_burst(get_parent(), global_position + dir * GUARD_CUT_RANGE * 0.55,
		Color(1.0, 0.98, 0.9, 0.95), Color(_element_color.r, _element_color.g, _element_color.b, 0.0),
		20, 0.3, 140.0, 340.0, 0.8, 2.4, 0.0, 0.0, true)
	Sfx.play("melee_hit", 2.0, 0.08)
	Juice.on_hit({
		"hitstop": 0.08 if hit_any else 0.03, "shake": 9.0 if hit_any else 3.0,
		"dir": dir, "kick": MELEE_CAMERA_KICK,
	})


## THE DRAG IS THE DEFLECT. While the ring is in its PERFECT band, anything that
## physically travels and touches the blade is turned — no separate button, no
## second timer. Only travelling things: a beam or a meteor has nothing to send
## back, so those go through `SpellDeflect.resolve()` on the damage path instead
## (that file's doctrine, and why both groups are not swept here).
func _guard_deflect_sweep() -> void:
	if not _guard.can_reflect():
		return
	var dir: Vector2 = _aim_dir.normalized() if _aim_dir != Vector2.ZERO else facing
	for group: String in ["enemy_projectile", "deflectable_spell"]:
		for proj: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(proj) or not proj.has_method("reflect"):
				continue
			if bool(proj.get("_reflected")):
				continue
			# A spectacle parks at the arena origin, so its transform is a lie —
			# ask it where it actually is (the house `deflect_point` contract) and
			# only fall back to the transform for a genuine moving body.
			var at: Vector2 = (proj as Node2D).global_position if proj is Node2D else global_position
			if proj.has_method("deflect_point"):
				at = proj.call("deflect_point") as Vector2
			if global_position.distance_to(at) > GUARD_DEFLECT_REACH:
				continue
			proj.call("reflect", dir, _element_color)
			Sfx.play("ding", 2.0, 0.02)
			Juice.hit_stop(0.09)
			Juice.shake_camera(4.0)
			rig.set_parry(dir, PARRY_SHIELD_TIME)
			rig.flash_color(PARRY_FLASH_COLOR, 0.1)


## One foot has hit the ground on the rig's run cycle — kick up the Stick-Fight walk
## dust behind it. The rig fires this twice per stride, only while grounded, running,
## un-frozen and not ragdolled, so there is nothing to re-gate here; it also owns the
## STEP SOUND (rig.step_sfx, enabled in _ready), so this handler is purely the visual
## half. Trails behind the direction of travel, hence the -signf on the live velocity.
func _on_foot_planted() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position + Vector2(-signf(velocity.x) * 6.0, 12.0),
		Color(0.85, 0.85, 0.9, 0.45), Color(0.85, 0.85, 0.9, 0.0),
		4, 0.24, 14.0, 52.0
	)


## Small white dust puff at the feet — jump kick-off + landing touchdown. The
## Stick-Fight jump/land dust; spawned a touch below the origin so it sits at the
## ground contact, not the torso.
func _spawn_foot_puff() -> void:
	CombatVfx.spawn_burst(
		get_parent(), global_position + Vector2(0.0, 12.0),
		Color(1.0, 1.0, 1.0, 0.72), Color(1.0, 1.0, 1.0, 0.0),
		9, 0.28, 22.0, 95.0
	)


## Cooldown snapshot for the AbilityBar HUD — one dict per slot, in bar order.
## `enabled` false = the slot is dimmed (class can't use it): mage shows Nova,
## rogue shows Parry.
func ability_hud_state() -> Array:
	return [
		{"name": "Cast", "key": "LMB", "remaining": _cast_cooldown_timer, "total": float(_cfg["cast_cd"]), "enabled": true},
		{"name": "Dash", "key": "Spc", "remaining": _dash_cooldown_timer, "total": float(_cfg["dash_cd"]), "enabled": true},
		{"name": _aoe_slot_name(), "key": "Q", "remaining": _blast_cooldown_timer, "total": float(_cfg["blast_cd"]), "enabled": true},
		{"name": "Blink", "key": "R", "remaining": _blink_cooldown_timer, "total": float(_cfg["blink_cd"]), "enabled": true},
		{"name": "Nova", "key": "T", "remaining": _nova_cooldown_timer, "total": NOVA_COOLDOWN, "enabled": bool(_cfg["has_nova"])},
		_defense_hud_slot(),
		# Signature ultimate — name updates as you cycle the loadout (V). Dimmed
		# when mana can't cover the cast; the floating MP bar shows the fill.
		_signature_hud_slot(),
	]


## The defensive slot, which is two different verbs behind one button.
##
## A press-window class shows PARRY and its cooldown wipe. A held-guard class shows
## GUARD and its RE-ARM — different word because it is a different act, and the bar
## is where a player learns that. ParryRing does not publish the remaining re-arm
## (only `is_ready()`), so the wipe is full-or-empty: it answers "can I guard yet",
## which is the only question the bar is actually being asked here.
func _defense_hud_slot() -> Dictionary:
	if _guard != null:
		return {
			"name": "Guard", "key": "RMB",
			"remaining": 0.0 if _guard.is_ready() else _guard.rearm_time(),
			"total": _guard.rearm_time(), "enabled": true,
		}
	return {
		"name": "Parry", "key": "RMB", "remaining": _parry_cooldown_timer,
		"total": PARRY_COOLDOWN, "enabled": bool(_cfg["can_parry"]),
	}


## Short HUD label for the Q slot, per the class's AoE variant.
func _aoe_slot_name() -> String:
	match String(_cfg["aoe"]):
		"nova": return "Whirl"
		"fist_shock": return "FirePunch"
		"ground_slam": return "Slam"
		"arcane_meteor": return "ArcaneStorm"
		"consecrate": return "Consecrate"
		"ice_shards": return "IceShards"
		"call_lightning": return "CallLightning"
		"curse_chain": return "CurseChain"
		_: return "Meteor"


## Class display name (Arcanist / Brawler / ...) for HUD / debug.
func class_display_name() -> String:
	return CLASS_NAMES[_hero_class] if _hero_class < CLASS_NAMES.size() else "Class"


## Start the CURRENTLY SELECTED signature's cooldown from OUTSIDE. A
## deferred-resolution spell (the Rift Dagger) only "completes" when its anchor
## resolves or expires, so it — not _cast_signature — decides when the timer starts.
## Never allowed to SHORTEN a running timer, which is why the maxf survives the move
## to a per-slot bank: `HandSlots.start_cooldown` assigns, so the guard has to live
## on this side of it.
##
## ⚠ Charges the SELECTED slot, which is the honest reading of the old shared bank
## and is right for its one caller — the dagger resolves while you still hold it. A
## spell that could resolve after you had switched away would need the slot INDEX
## plumbed through it; nothing does that today, and guessing which slot to bill would
## be worse than not offering it.
func start_signature_cooldown(seconds: float) -> void:
	var slot: int = _hand_slot(_signature_index)
	if seconds > _hand.cooldown(slot):
		_hand.start_cooldown(slot, seconds)


## Hotbar slot for the equipped signature: short name (first word of the spell),
## the Ultimate key, its cooldown wipe, and dimmed when mana can't cover it.
##
## With a live rift anchor out, the slot changes MEANING rather than gaining a
## second binding — so the bar shows RECALL, ready, for as long as the press
## would recall. AbilityBar renders from this dictionary alone, so nothing on the
## UI side needs to know the spell has two beats.
func _signature_hud_slot() -> Dictionary:
	var sig: SpellDef = current_signature()
	if sig == null:
		return {"name": "Ult", "key": "G", "remaining": 0.0, "total": 0.0, "enabled": false}
	if sig.kind == SpellDef.Kind.THROWN_ANCHOR \
			and (load(RIFT_DAGGER_PATH) as GDScript).find_anchor(get_tree(), self) != null:
		return {"name": "RECALL", "key": "G", "remaining": 0.0, "total": 0.01, "enabled": true}
	# Not split(" ")[0]: the IP rename made zoltraak "The Ordinary Spell", so the
	# ability bar proudly read **The**. short_spell_name() drops leading articles
	# and takes the first real word.
	var short_name: String = AbilityBar.short_spell_name(sig.display_name)
	return {
		"name": short_name, "key": "G",
		"remaining": signature_cooldown(_signature_index),
		"total": maxf(sig.cooldown, 0.01),
		# Was `mp >= sig.mp_cost`. With the mana gate gone, "enabled" means the slot
		# exists and is yours — the cooldown wipe above is what says "not yet", and a
		# slot that was BOTH dimmed and wiped said the same thing twice.
		"enabled": true,
	}


## Equip a weapon kind: swaps the rig's weapon overlay AND retunes the melee
## attack ("gear = visual + ability"). Unknown kinds fall back to fists.
func equip_weapon(kind: String) -> void:
	if not WEAPON_STATS.has(kind):
		kind = "fists"
	_weapon = kind
	var stats: Dictionary = WEAPON_STATS[kind]
	_melee_damage = stats["damage"]
	_melee_range = stats["range"]
	_melee_knockback = stats["knockback"]
	rig.set_equipment("weapon", kind)


func _melee() -> void:
	_melee_cooldown_timer = _melee_cd
	if _melee_kick_next:
		rig.play(CharacterRig.State.KICK)
	else:
		rig.play(CharacterRig.State.PUNCH)
		rig.cast_gesture(CharacterRig.GestureKind.IGNITE_DROP, 0.4, _element)  # fist ignites on the punch
	_melee_kick_next = not _melee_kick_next
	# A fire-element punch LIGHTS the fist: it stays lit + trails embers for ~1.6s.
	if int(_cfg.get("melee_element", -1)) == Elements.Element.FIRE:
		_flaming_fist_timer = FLAMING_FIST_TIME
	# Short forward lunge on EVERY swing, not just the combo/heavy-swing primaries
	# (maker: the plain click/melee "feels weird" — it used to just plant the
	# figure in place). _primary_melee_combo()/_primary_heavy_swing() set
	# velocity.x again right after calling into this, so this is simply
	# overwritten there — no double-step / compounding for those callers.
	if _aim_dir.x != 0.0:
		velocity.x = signf(_aim_dir.x) * MELEE_LUNGE_SPEED
	Sfx.play("melee_swing", 0.0, 0.08)
	# DECLARE the swing for the clash layer — at the COMMIT, not at contact. That
	# ordering is the whole trick: declaring on contact means this blow has already
	# hurt the other fighter before they swing, and fixing THAT would mean holding
	# every punch in the game for the clash window (~90 ms of latency on every
	# swing) to pay for a rare event. Declaring here decides the clash while both
	# fighters are still in wind-up, at zero cost to the ones that never clash.
	MeleeClash.declare(self, _aim_dir, _melee_range, _melee_damage)


## Drive the persistent flaming fist: decay the timer, feed the rig the current
## fire strength, and trail small embers from the moving hand. Runs every frame.
func _update_flaming_fist(delta: float) -> void:
	if _flaming_fist_timer <= 0.0:
		return
	_flaming_fist_timer = maxf(_flaming_fist_timer - delta, 0.0)
	var s: float = clampf(_flaming_fist_timer / FLAMING_FIST_TIME, 0.0, 1.0)
	rig.set_hand_fire(s, Elements.Element.FIRE)
	var hand_pos: Vector2 = rig.get_lead_hand_global()
	_fist_ember_timer -= delta
	if _fist_ember_timer <= 0.0 and _last_hand_pos != Vector2.ZERO \
			and hand_pos.distance_to(_last_hand_pos) > 4.0:
		_fist_ember_timer = 0.045
		CombatVfx.spawn_burst(
			get_parent(), hand_pos,
			Color(1.3, 0.55, 0.15, 0.8 * s), Color(0.8, 0.2, 0.05, 0.0),
			3, 0.4, 20.0, 75.0, 0.6, 1.5, 0.0, 0.0, true
		)
	_last_hand_pos = hand_pos
	if _flaming_fist_timer <= 0.0:
		rig.set_hand_fire(0.0, Elements.Element.FIRE)  # snuff out


## The nearest HOSTILE within _melee_range (or null) — the melee auto-target.
##
## ⚠ This is aim assist and it predates the locked no-aim-assist rule. It survives
## deliberately (`slice_test_selfdamage.gd` asserts it: an enemy directly BEHIND
## you still eats the swing) and it only ever ADDS a guaranteed hit, never removes
## an arc-gated one — but it is in genuine tension with that rule and stays
## flagged rather than quietly deleted. What changed here is only WHOSE nearest
## body it finds: the scan is the caster's faction now, so a bot-driven hero
## auto-targets the hero it is fighting instead of ignoring it and hunting for
## monsters that are not in this arena.
##
## ⚠ THIS SCAN DELIBERATELY STAYS ON `hostile_group`, NOT `attack_group()`, and that
## asymmetry is the whole answer to "friendly fire must not turn the melee
## auto-target into a teammate-killer". The arc sweep in `_on_melee_hit_frame`
## widened to `mortal` — you CAN punch your friend, and under this spec you should
## be able to — but the auto-target is the game aiming FOR you, and a game that
## silently redirects your fist onto the person standing next to you is not friendly
## fire, it is a bug that feels like betrayal. So: aim at your teammate and you hit
## them; do not aim at them and nothing reaches for them on your behalf. True
## hostiles keep the free hit exactly as before, which is what the existing
## regression test pins.
func _nearest_enemy_in_melee_range() -> Node2D:
	# Nearest measured to the SILHOUETTE, so a tall enemy whose head is closer than a
	# short enemy's origin wins — which is what the eye expects, and which is what
	# `SpellTargets.nearest` is documented as the seam for.
	return SpellTargets.nearest(global_position, _melee_range,
		get_tree().get_nodes_in_group(hostile_group), [self], self)


func _on_melee_hit_frame() -> void:
	# The swing was spent meeting another blow head-on, so it must NOT also land.
	# A clash that still dealt its damage would read as "we both hit each other"
	# rather than "our blows cancelled", and the whole beat is the cancellation.
	if MeleeClash.consume_spent(self):
		return
	var hit_any: bool = false
	var melee_el: int = int(_cfg.get("melee_element", -1))  # class element on the strike
	# Auto-target (Stick-Fight punches don't need pixel-perfect aim): the single
	# NEAREST enemy within _melee_range always connects, regardless of the facing
	# cone below — a click near an enemy shouldn't whiff just because the cursor
	# isn't exactly on them. Wide swings (Juggernaut's soft _melee_arc_dot) still
	# additionally cleave every OTHER enemy that IS inside the strict arc, so
	# that crowd-hit behaviour is unchanged; auto-target only adds a guaranteed
	# hit, it never removes the arc-gated ones.
	var nearest_enemy: Node2D = _nearest_enemy_in_melee_range()
	# THE ARC IS NOW MEASURED AGAINST THE DRAWN BODY. All three loops below used to
	# be `distance_to(node.global_position)` — a point test against an origin that
	# sits ~10 px under the head being aimed at (19 px on the 1.9x dummies), which is
	# the maker's "spells pass through heads without registering" bug in the form the
	# player meets it most often. `SpellTargets.in_cone` keeps the exact same
	# `facing.dot(toward) > _melee_arc_dot` predicate (strict, so no swing silently
	# widens) but measures REACH to the silhouette, adds the target's own published
	# `hit_margin`, and filters line-of-sight so a punch cannot land through a wall.
	#
	# ⚠ THE STACKING CAVEAT: reach therefore grows, by up to about half a rig height
	# on the vertical axis. That IS the fix. If melee starts feeling too long, tune
	# `MELEE_RANGE` / the per-class `melee_range` OR `Enemy.HIT_MARGIN_FACTOR` —
	# never both, and never a third margin at this call site.
	var enemies_in_arc: Array = SpellTargets.in_cone(global_position, facing,
		_melee_range, _melee_arc_dot, get_tree().get_nodes_in_group(attack_group()),
		[self], self)
	# The auto-target is PRESERVED deliberately, not reintroduced: it predates this
	# change, `slice_test_selfdamage.gd` asserts it explicitly (an enemy directly
	# BEHIND you still eats the swing), and it only ever ADDS a guaranteed hit — it
	# never removes an arc-gated one. It is, however, in genuine tension with the
	# locked no-aim-assist rule, and it is flagged in the handoff rather than
	# silently deleted here.
	if nearest_enemy != null and not enemies_in_arc.has(nearest_enemy):
		enemies_in_arc.append(nearest_enemy)
	for enemy: Node in enemies_in_arc:
		var toward: Vector2 = ((enemy as Node2D).global_position - global_position).normalized()
		if enemy.has_method("take_damage"):
			enemy.take_damage(_melee_damage)
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(toward * _melee_knockback)
		if melee_el >= 0 and enemy.has_method("apply_status"):
			enemy.apply_status(melee_el)  # burning / staggering / etc. fists
		hit_any = true
	# Crates break under melee too — same range/arc gate as enemies.
	for prop: Node in SpellTargets.in_cone(global_position, facing, _melee_range,
			_melee_arc_dot, get_tree().get_nodes_in_group("destructible"), [self], self):
		if prop.has_method("take_damage"):
			prop.take_damage(_melee_damage)
		hit_any = true
	# A swing also SWATS enemy bolts out of the air (punch-fizzles-bolt): same
	# range + facing-arc gate, so a well-timed punch is a melee "parry". LOS is off
	# for this one — a bolt is IN FLIGHT between you and whatever fired it, and
	# culling it for cover it is currently passing would make the swat unreliable
	# in exactly the cluttered rooms where it matters.
	# BOTH bolt groups. Scanning only "enemy_projectile" meant a hero could never
	# swat a RIVAL HERO's bolt, which joins "player_spell" — invisible while every
	# fight was hero-vs-enemy, and a hole the moment factions let two heroes fight.
	# The blade guard could already catch them (it scans "deflectable_spell"), so
	# the punch-parry was the odd one out rather than the rule.
	var bolts: Array = get_tree().get_nodes_in_group("enemy_projectile")
	bolts.append_array(get_tree().get_nodes_in_group("player_spell"))
	for proj: Node in SpellTargets.in_cone(global_position, facing, _melee_range,
			_melee_arc_dot, bolts, [self], self, false):
		# Never swat your own shot out of the air on the follow-through.
		if proj.get("caster") == self or proj.get("caster_node") == self:
			continue
		if proj.has_method("consume"):
			proj.call("consume")
			hit_any = true
	if hit_any:
		# Unified hit juice (study §4) — heavier freeze than a spell hit + a punch
		# INTO the strike direction, all in sync.
		Juice.on_hit({
			"sfx": "melee_hit", "hitstop": _tune("melee_hit_stop", MELEE_HIT_STOP),
			"shake": 4.0, "dir": facing, "kick": MELEE_CAMERA_KICK,
		})
		Sfx.play("ding", -3.0, 0.05)  # the bright Stick-Fight "clean hit" ding
	else:
		# Every swing reads even on a MISS — a small hitstop/shake so the punch
		# still has weight when it doesn't land (much lighter than the on-connect
		# cluster above). The melee_swing whoosh SFX + rig slash-arc already fire
		# unconditionally at swing-start, so this is just the missing impact beat.
		Juice.on_hit({"hitstop": MELEE_SWING_HIT_STOP, "shake": MELEE_SWING_SHAKE, "dir": facing})


## SANDBOX Smash: the knockback multiplier at a given damage %. Pure + static so
## it's headless-testable: 0% -> 1.0x, 100% -> 2.0x, and it grows linearly beyond.
static func ringout_knockback_scale(pct: float) -> float:
	return 1.0 + pct / 100.0


## True when the sandbox ring-out model is active (GameState.ringout_mode). Guarded
## lookup so headless contexts / a bare instance without the autoload read false.
func _is_ringout_mode() -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	return gs != null and bool(gs.get("ringout_mode"))


## Receive a shove (bomb blast / reflected bolt / slam). Same i-frame contract as
## take_damage — a dashing or just-blinked hero shrugs it off. The .y lands once as
## a real impulse; .x rides the decaying channel (added into velocity each frame).
func apply_knockback(impulse: Vector2, do_flop: bool = true) -> void:
	# Co-op: a shove computed on another peer is forwarded to this hero's owner.
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_apply_knockback", impulse)
		return
	if is_dashing or _blink_iframe_timer > 0.0:
		return
	# THE knockback knob (TuningConfig.knockback_mult). Fallback must MATCH the
	# exported default — 1.6 -> 1.0 with the "knockback is too much" pass, or a
	# context without the Tuning autoload silently keeps the old launch feel.
	impulse *= _tune("knockback_mult", 1.0)
	# Smash sandbox: the higher THIS fighter's damage %, the farther the same hit
	# sends them (that's how a ring-out becomes reachable). No-op in tower mode.
	if _is_ringout_mode():
		impulse *= ringout_knockback_scale(damage_pct)
	_knockback = impulse
	velocity.y += impulse.y
	# Reel from the blow (skip while the manual hold-DOWN ragdoll owns the limp,
	# and skip for self-recoil which passes do_flop=false).
	if do_flop and rig != null and impulse.length() > 12.0 and not _ragdolling:
		var mag: float = impulse.length()
		rig.flop(clampf(mag / 800.0, 0.2, 0.7), 0.18)
		rig.apply_impulse(impulse.normalized(), minf(mag, 800.0) * 0.85)


## Firing a big spell shoves the caster back (Stick-Fight recoil = power is
## dangerous). Horizontal-only + opposite the aim, so directed beams push you
## back while sky-aimed spells (aim.x ~ 0) barely recoil and vertical hops
## aren't fought. Routes through apply_knockback with do_flop=false (no self-flop).
func _self_recoil(amount: float) -> void:
	if absf(_aim_dir.x) < 0.15:
		return
	apply_knockback(Vector2(-signf(_aim_dir.x) * amount, 0.0), false)


## Slammed hard into a destructible/breakable this frame? Crack it (shared helper).
func _check_wall_slam() -> void:
	_knockback = SlamPhysics.check(self, _knockback)


## True only during the opening slice of a dash. _dash_timer counts DOWN from the
## dash duration, so "early" is a HIGH remaining time.
func _dash_invulnerable() -> bool:
	if not is_dashing:
		return false
	var total: float = _tune("dash_time", DASH_TIME)
	return _dash_timer >= total * (1.0 - DASH_IFRAME_FRACTION)


func take_damage(amount: int) -> void:
	# Co-op: a hit computed on another peer (e.g. the host's enemy AI striking THIS
	# hero, whom the host only holds as a puppet) is forwarded to this hero's owner,
	# where its i-frames / parry / channel-break all resolve authoritatively. SP /
	# owner -> fall through and apply locally (byte-identical to before).
	if _net != null and _net.is_active() and not is_multiplayer_authority():
		rpc_id(get_multiplayer_authority(), &"_net_take_damage", amount)
		return
	# Co-op: a downed hero is out of the fight — immune until revived.
	if downed:
		return
	# Dash i-frames cover only the EARLY part of the dash, not all of it. Full-
	# duration invulnerability made dash a free "delete that attack" button: you
	# could react late, dash into a hit that had already connected, and take
	# nothing. Now a dash must be started BEFORE the hit lands, so it is a read
	# rather than a panic button, and a late dash still gets punished.
	if _dash_invulnerable():
		return
	# Blink grants a brief post-teleport i-frame window (BLINK_IFRAME).
	if _blink_iframe_timer > 0.0:
		return
	# Perfect-parry window also BLOCKS a melee / contact / charge hit (deflect
	# punches, not just projectiles) — the reward is the same crisp ding + flash.
	if _parry_window_timer > 0.0:
		Sfx.play("ding", 2.0, 0.02)
		rig.flash_color(PARRY_FLASH_COLOR, 0.1)
		rig.set_parry(_aim_dir, PARRY_SHIELD_TIME)
		# The DEFLECT beat — anime freeze-frame localized AT the hero, biased a
		# touch toward the attacker (aim side) so the burst reads at the clash.
		Juice.frame({"style": ImpactFrame.Style.LOCAL, "strength": 0.7,
			"at": global_position + _aim_dir * 18.0})
		_parry_window_timer = 0.0
		return
	# THE BLADE GUARD. Resolved ABOVE ordinary mitigation because its outcome is
	# categorical rather than a percentage: a perfect read is a total negate plus a
	# BANK, and banking a number that gear had already shaved would pay the
	# Swordsaint less for the same read the better armoured they were, which is
	# backwards. A sustained (overshot) guard only chips, and banks nothing — see
	# the BLADE-GUARD constants block for why holding must never earn.
	if _guard != null:
		match _guard.quality():
			ParryRing.Quality.PERFECT:
				_guard_bank = mini(_guard_bank + amount, GUARD_BANK_CAP)
				_guard_hits += 1
				Sfx.play("ding", 2.0, 0.02)
				rig.flash_color(PARRY_FLASH_COLOR, 0.1)
				rig.set_parry(_aim_dir, PARRY_SHIELD_TIME)
				Juice.frame({"style": ImpactFrame.Style.LOCAL, "strength": 0.7,
			"at": global_position + _aim_dir * 18.0})
				return
			ParryRing.Quality.SUSTAIN:
				amount = int(round(float(amount) * _guard.damage_mult()))
	# MITIGATION RUNS BEFORE THE INTERRUPT. It used to run after, so a hit your
	# gear soaked entirely still shattered a 1.3 s channel — the ward paid for
	# nothing. Maker's rule: only a hit that actually LANDS breaks your cast.
	# GuardComponent is the single mitigation path (gear armour, the one-shot
	# warding robe, and ward spells), replacing three fields that were inlined
	# here and invisible to every other body in the game.
	var guard: GuardComponent = GuardComponent.peek(self)
	if guard != null:
		amount = guard.mitigate(amount)
	# A hit that got through shatters a float-channel OR a summon windup — the ult
	# is lost with its mana and cooldown already spent. Fully absorbed = cast survives.
	if amount > 0:
		if _channeling:
			_cancel_channel()
		if _summoning:
			_cancel_summon()
		rig.flash_color(Color(0.75, 0.85, 1.0), 0.14)  # a pale ward shimmer
	# Smash sandbox: pile onto the damage % (no hp drain, no hp-death — the only
	# way out is a ring-out). Tower mode: drain hp and die at 0 (unchanged).
	# pct_per_damage is read from Tuning (single shared source with Enemy — see
	# TuningConfig.pct_per_damage) so a retune can't silently diverge the two.
	var ringout: bool = _is_ringout_mode()
	if ringout:
		damage_pct += float(amount) * _tune("pct_per_damage", 0.8)
	else:
		hp = max(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, -18.0), amount, Color(1.0, 0.35, 0.35), amount >= 18)
	rig.play(CharacterRig.State.HURT)
	rig.flash_color(HURT_FLASH_COLOR, HURT_FLASH_TIME)
	rig.apply_impulse(Vector2(-facing.x, -0.7), 300.0)  # ragdoll flinch on the hit
	Juice.hit_stop(_tune("hurt_hit_stop", HURT_HIT_STOP))
	Juice.shake_camera(_tune("hurt_shake", HURT_SHAKE))
	Sfx.play("hero_hurt")
	if not ringout and hp == 0:
		_die()


func _die() -> void:
	# In a run: a death is a FALL — drop 2 floors but stay in the tower (GameState
	# ticks the fall counter + saves; the Arena rebuilds the dropped floor in place
	# and revives us). In the standalone sandbox: just reset to full so the feel
	# loop never stops.
	# Co-op: go DOWNED (out of the fight, not gone). The Arena host watches for a full
	# party wipe -> drops the party a floor + revives everyone; a floor advance also
	# revives the downed. The owner drives its own downed state; it syncs to the others.
	if _net != null and _net.is_active():
		_enter_downed()
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.fall()
		return
	hp = max_hp
	health_changed.emit(hp, max_hp)


## Co-op: fall limp and drop out of the fight (immune, no input). hp stays 0. Cancels
## any in-flight channel/summon so nothing fires from a corpse.
func _enter_downed() -> void:
	downed = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	if _channeling:
		_cancel_channel()
	if _summoning:
		_cancel_summon()
	if is_instance_valid(rig):
		rig.set_limp(1.0)
		rig.apply_impulse(Vector2(-facing.x, -0.6), 260.0)  # a death flop
		rig.play(CharacterRig.State.HURT)
	Sfx.play("hero_hurt", 0.0, 0.1)


## Downed physics: just slump — gravity + friction to a stop, limp rig, no abilities.
func _process_downed(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, GROUND_FRICTION * delta)
	if is_on_floor() and velocity.y >= 0.0:
		velocity.y = 0.0
	else:
		velocity.y = minf(velocity.y + GRAVITY_FALL * delta, MAX_FALL)
	move_and_slide()
	if is_instance_valid(rig):
		rig.set_body_velocity(velocity)
		rig.play(CharacterRig.State.HURT)


func is_downed() -> bool:
	return downed


## Full clean reset after a FALL (Arena calls this on the fell-respawn) so you
## resume upright — not mid-channel, on-cooldown, knocked-back, or ragdolling.
func revive() -> void:
	downed = false
	hp = max_hp
	health_changed.emit(hp, max_hp)
	_dash_cooldown_timer = 0.0
	_cast_cooldown_timer = 0.0
	_melee_cooldown_timer = 0.0
	_blast_cooldown_timer = 0.0
	_blink_cooldown_timer = 0.0
	_nova_cooldown_timer = 0.0
	_parry_cooldown_timer = 0.0
	_hand.clear_cooldowns()  # every kit slot, not one shared bank
	if _channeling:
		_cancel_channel()
	if _summoning:
		_cancel_summon()
	_ragdolling = false
	_knockback = Vector2.ZERO
	velocity = Vector2.ZERO
	# CLEAR A HELD BLADE GUARD. `_physics_process` returns early while downed, so a
	# player who was holding guard when they went down never gets their RELEASE seen
	# — and a ring left `held` blocks attacking and rooting FOREVER after the revive.
	# A genuine softlock, and the only place it can be reached.
	if _guard != null:
		_guard.release()
		_guard_bank = 0
		_guard_hits = 0
	if is_instance_valid(rig):
		rig.set_limp(0.0)   # clear the downed ragdoll
		rig.play(CharacterRig.State.IDLE)


# ------------------------------------------------------------- co-op networking
## Camera + synchronizer role. Only in a live session; SP leaves the camera as-is.
func _setup_net_role() -> void:
	if _net == null or not _net.is_active():
		return
	_setup_net_sync()
	var cam := get_node_or_null("Camera2D") as Camera2D
	if is_multiplayer_authority():
		if cam != null:
			cam.make_current()   # the local hero owns the viewport
	elif cam != null:
		cam.enabled = false      # remote heroes never steal the view


## A MultiplayerSynchronizer that streams this hero's transform + state from its
## owner to every peer. Built in code (no .tscn surgery).
func _setup_net_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for p: String in [":position", ":velocity", ":facing", ":hp", ":net_class", ":downed"]:
		cfg.add_property(NodePath(p))
	cfg.property_set_replication_mode(NodePath(":position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(NodePath(":velocity"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	sync.root_path = NodePath("..")   # relative to this Hero
	sync.replication_config = cfg
	add_child(sync)
	sync.set_multiplayer_authority(get_multiplayer_authority())


## Remote heroes animate from replicated velocity/facing; no input, no physics.
func _remote_visual(_delta: float) -> void:
	if not is_instance_valid(rig):
		return
	if downed:
		rig.set_limp(1.0)
		rig.play(CharacterRig.State.HURT)
		return
	rig.set_limp(0.0)
	rig.set_body_velocity(velocity)
	rig.set_facing(facing)
	rig.play(CharacterRig.State.RUN if absf(velocity.x) > 8.0 else CharacterRig.State.IDLE)


@rpc("any_peer", "call_remote", "reliable")
func _net_take_damage(amount: int, _tint: Color = Color(1, 1, 1, 0)) -> void:
	take_damage(amount)


@rpc("any_peer", "call_remote", "reliable")
func _net_apply_knockback(impulse: Vector2) -> void:
	apply_knockback(impulse)


## Record the element behind an actual thrown ability into the run outcome
## (guarded — no-op in the sandbox).
func _notify_element_used() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.is_run_active():
		gs.notify_element_used(Elements.display_name(_element))
