class_name EnvTheme
extends Resource
## A tower/floor environment identity — the thing that makes floor 3 look like
## somewhere else rather than floor 2 with different enemies.
##
## Maker, 2026-08-04: "I want more diversity on the floors like a snow place
## background a sunny green one like a red room", and on the register overall:
## "the colouring the shading the lighting… dim lights and things like that on
## certain floors as you climb".
##
## ⚠ DIM IS THE REGISTER, NOT THE COLOUR. Every floor is its own HUE and only the
## exposure is pulled down. Making them all dark grey would be the easy reading of
## "dim" and the wrong one — it erases the diversity in the same breath. Keeping
## each floor saturated and underlit is also what makes a cast read as an actual
## LIGHT SOURCE, which is the whole Tower-of-God feel being chased.
##
## Still thin on purpose: it grows (backdrop art, music, hazard props) without
## touching consumers.

@export var name: String = "surface"
## Ambient wash — the floor's base hue. Drives `ArenaAtmosphere.build_wash` and the
## PostProcess grade.
@export var wash_tint: Color = Color(0.20, 0.28, 0.22)
## The floor's HIGHLIGHT. Left transparent to mean "derive it from the wash", which
## is what every floor did before biomes existed — so an EnvTheme written by hand or
## by `FloorGen._jitter_theme` behaves exactly as it always has.
@export var accent_tint: Color = Color(0, 0, 0, 0)
## Exposure. 1.0 is neutral, below is dimmer, above is glare. This is the "dim
## lights on certain floors" dial, and it is per-floor precisely so the climb has a
## shape you can feel: a bright meadow between two dark rooms reads as progress.
@export var light: float = 1.0


## The highlight to draw with — the authored accent, or the classic derived one when
## none was given. One rule, so a hand-written theme and a biome behave the same.
func accent() -> Color:
	if accent_tint.a > 0.0:
		return accent_tint
	return Color(wash_tint.r, wash_tint.g, wash_tint.b, 1.0).lightened(0.55)


## The wash with this floor's exposure applied. Kept as a method rather than baked
## into `wash_tint` so the authored hue stays readable in the inspector and in a
## diff — `light` is a treatment, not part of the colour.
func lit_wash() -> Color:
	var l: float = maxf(light, 0.0)
	return Color(wash_tint.r * l, wash_tint.g * l, wash_tint.b * l, 1.0)
