class_name Elements
extends RefCounted
## Element identity for hero abilities: colour + display name per element.
## Element drives the AURA and ability (cast bolt) colour; it is independent
## of the body colourway (Hero.COLOURWAYS) — you can be a Jade stickman
## casting Fire. Static helpers only; no instances needed.

enum Element { FIRE, ICE, LIGHTNING, SHADOW, ARCANE }


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
	return Color(0.95, 0.4, 0.85)


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
	return "Arcane"


## Number of elements — the modulus for cycle wrapping.
static func count() -> int:
	return Element.size()
