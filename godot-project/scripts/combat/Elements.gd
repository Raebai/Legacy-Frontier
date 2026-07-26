class_name Elements
extends RefCounted
## Element identity for hero abilities: colour + display name per element.
## Element drives the AURA and ability (cast bolt) colour; it is independent
## of the body colourway (Hero.COLOURWAYS) — you can be a Jade stickman
## casting Fire. Static helpers only; no instances needed.

## Eight elements — one signature identity per playable class. The first five keep
## their indices (0..4) so every existing save / cast / test stays valid; EARTH,
## HOLY, WIND are appended. StatusComponent maps the three new ones onto proven
## ailment mechanics (see StatusComponent.apply) with their own tint.
enum Element { FIRE, ICE, LIGHTNING, SHADOW, ARCANE, EARTH, HOLY, WIND }


## Signature colour for an element. Unknown values fall back to ARCANE.
static func color(e: int) -> Color:
	match e:
		Element.FIRE:
			return Color(1.0, 0.45, 0.15)  # orange-red
		Element.ICE:
			return Color(0.5, 0.85, 1.0)  # cyan
		Element.LIGHTNING:
			return Color(1.0, 0.9, 0.3)  # yellow
		Element.SHADOW:
			return Color(0.6, 0.35, 0.9)  # violet
		Element.ARCANE:
			return Color(0.95, 0.4, 0.85)  # magenta
		Element.EARTH:
			return Color(0.78, 0.55, 0.28)  # amber-brown
		Element.HOLY:
			return Color(1.0, 0.93, 0.6)  # gold-white
		Element.WIND:
			return Color(0.62, 0.96, 0.86)  # teal-white
	return Color(0.95, 0.4, 0.85)


## Peak channel value for emissive() cores — >1.0 so they clear the arena
## bloom threshold (combat_glow.tres glow_hdr_threshold) and radiate.
const EMISSIVE_PEAK: float = 1.7


## HDR "hot core" companion for an element: the signature colour lifted so its
## brightest channel lands at EMISSIVE_PEAK, plus a small push toward hot white.
## Keeps the hue while guaranteeing even the dark elements (SHADOW, EARTH)
## bloom a bright core under the glow pass instead of reading muddy. Use for
## core bands / tips / flash discs; keep outer glow bands on color() so
## telegraphs and soft falloff stay controlled (only >1.0 blooms).
static func emissive(e: int) -> Color:
	var c: Color = color(e)
	var peak: float = maxf(c.r, maxf(c.g, c.b))
	var s: float = EMISSIVE_PEAK / maxf(peak, 0.001)
	var boosted := Color(c.r * s, c.g * s, c.b * s, 1.0)
	# 15% toward hot white so cores read incandescent, not neon-saturated.
	return boosted.lerp(Color(1.9, 1.9, 1.9, 1.0), 0.15)


## Human-readable name. Unknown values fall back to "Arcane".
static func display_name(e: int) -> String:
	match e:
		Element.FIRE:
			return "Fire"
		Element.ICE:
			return "Ice"
		Element.LIGHTNING:
			return "Lightning"
		Element.SHADOW:
			return "Shadow"
		Element.ARCANE:
			return "Arcane"
		Element.EARTH:
			return "Earth"
		Element.HOLY:
			return "Holy"
		Element.WIND:
			return "Wind"
	return "Arcane"


## Particle-language / effect string for an element — the token the spectacle
## scenes + ElementFx read to pick their palette (fire / frost / lightning / ...).
## Unknown values fall back to "arcane".
static func effect_name(e: int) -> String:
	match e:
		Element.FIRE:
			return "fire"
		Element.ICE:
			return "frost"
		Element.LIGHTNING:
			return "lightning"
		Element.SHADOW:
			return "shadow"
		Element.ARCANE:
			return "arcane"
		Element.EARTH:
			return "earth"
		Element.HOLY:
			return "holy"
		Element.WIND:
			return "wind"
	return "arcane"


## Number of elements — the modulus for cycle wrapping.
static func count() -> int:
	return Element.size()
