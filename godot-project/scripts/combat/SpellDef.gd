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
enum Kind { BEAM, DIVINE_RAY, NOVA, METEOR, CONVERGENCE, RUSH, BOULDER, PILLAR, WALL }

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


## Resolve the tint for a cast: an explicit colour override, else the element
## colour, else the caster's current element colour (fallback).
func resolve_color(fallback: Color) -> Color:
	if not use_element_color:
		return color
	if element >= 0:
		return Elements.color(element)
	return fallback
