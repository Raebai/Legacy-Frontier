class_name SpellDef
extends Resource
## Data shape for a SIGNATURE spell — one row of the spell tree. A SpellDef is
## pure data: which spectacle to cast (kind), what it costs (MP/cooldown), how
## hard it hits, and its geometry. SpellCaster turns a SpellDef + a caster into
## the actual on-screen spell. New spell = new SpellDef (.tres-authorable, or the
## curated code library in SpellLibrary.gd) — no new casting code unless it needs
## a brand-new spectacle scene.
##
## Mirrors the project's data-driven ethos (NPCData / TowerDef / FloorDef).

## The spectacle this spell casts. Reserve values for spells designed but not yet
## built (see docs/v2.0-spell-system-design.md); SpellCaster falls back safely.
## APPEND new kinds only (never insert) — kinds are referenced by ordinal in the
## code library; inserting would renumber BOULDER/PILLAR/WALL and break their arms.
## HEX and CATACLYSM are the DROP-ECONOMY kinds and they are deliberately two
## kinds rather than eight. Every new Kind costs FIVE silent defaults elsewhere —
## `ReactionTable.form_for_kind` (falls through to IMPACT), `CastStyle.for_spell`,
## `LoadoutBar._draw_glyph`, `BotBrain._effective_range` and `SpellCaster`'s own
## dispatch — none of which error when a kind is missing. Eight new behaviours
## would have meant forty places where nothing happens and nothing complains, in
## files owned by other agents. So the ten Tier 2 / Tier 3 spells fork inside ONE
## arm each, off `SpellDrops.HEX_SCRIPTS` / `CATACLYSM_SCRIPTS` — the same shape
## the ZONE arm already uses to fork Shadow Root off Blizzard, and the METEOR arm
## to fork Glacial Spine, only keyed by id instead of by effect string.
##   HEX       — Tier 2 floor pickups whose behaviour is a STATE change on bodies
##               (petrify / gravity_flip / blood_pact / mirror_image). Chain
##               Lightning and Meteor are NOT here: they reuse CHAIN and METEOR.
##   CATACLYSM — Tier 3 boss drops. One shelf, one arm, four rituals.
enum Kind { BEAM, DIVINE_RAY, NOVA, METEOR, CONVERGENCE, RUSH, BOULDER, PILLAR, WALL, ICE_WALL, CHAIN, ZONE, MISSILES, BLINK_STRIKE, TETHER, FLURRY, CRAWLER, THROWN_ANCHOR, WARD, ARC, HEX, CATACLYSM }

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: int = Kind.BEAM
## Element index (Elements.Element) for the tint, or -1 to inherit the caster's
## current element colour. `color` overrides both when use_element_color is off.
@export var element: int = -1
@export var use_element_color: bool = true
@export var color: Color = Color(0.7, 0.5, 1.0, 1.0)
## Elemental CHARACTER of the spectacle ("arcane" | "frost" | "fire" | "holy") —
## picks the particle language / palette so each legendary reads distinct.
@export var effect: String = "arcane"
## Cost + pacing. mp_cost gates the cast; cooldown is the per-spell reuse timer.
@export var mp_cost: int = 45
@export var cooldown: float = 3.5
@export var damage: int = 46
## Geometry (used per-kind): beam length/width; divine-ray / aoe radius; reach is
## how far from the caster a placed spell (divine ray) lands toward the aim.
@export var length: float = 1100.0
@export var width: float = 30.0
@export var radius: float = 90.0
@export var reach: float = 260.0
@export var count: int = 10  # projectiles for a barrage kind (Meteor Sigil)
## Float-channel windup (seconds). >0 = the caster LEVITATES + channels for this
## long before the spell fires (interruptible by a hit). 0 = instant cast.
@export var cast_time: float = 0.0
## HOW MANY TIMES A PICKED-UP SPELL MAY BE CAST BEFORE IT IS GONE. -1 = unlimited,
## which is what every spell in a class kit is and therefore the default: nothing
## that existed before the drop economy changes by one branch.
##
## Only Tier 3 boss drops set this (1, or 2 for Roulette). It lives on the DEF and
## not on the grant record because the number is a property of the spell — Roulette
## gets two rolls because Roulette is a gamble, not because of who picked it up —
## and because a `.tres`-authored drop then declares its own charges with no code.
##
## The counter itself is per-HERO and lives on `HandSlots` (a SpellDef instance is
## shared by nobody, but it IS rebuilt fresh on every `SpellLibrary` call, so a
## count stored here would reset every time anything asked the library a question).
@export var charges: int = -1


## Resolve the tint for a cast: an explicit colour override, else the element
## colour, else the caster's current element colour (fallback).
func resolve_color(fallback: Color) -> Color:
	if not use_element_color:
		return color
	if element >= 0:
		return Elements.color(element)
	return fallback
