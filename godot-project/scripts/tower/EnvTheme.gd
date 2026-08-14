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

## The floor's AIR — what is falling, drifting or rising through it.
##
## Maker, 2026-08-14: "a beautiful sunset an eclipse falling leaves in a forest like
## all that stuff". The back wall (`FloorDecor`) already says WHERE you are; this
## says what the place is DOING while you fight in it, which is the half that moves.
##
## ⚠ THIS IS GARNISH AND IT IS ON THE AUSTERITY RAMP. `ElementFx` draws the same
## distinction and comes down on the other side of it (`ElementFx.gd:61-65`: the
## element read "is information, not garnish, and it is not on the austerity ramp").
## Weather carries no information a player must react to, so it thins on LOW and may
## vanish entirely — see `Atmosphere.WEATHER_AMOUNT_LOW`.
enum Weather {
	NONE,      ## still air
	ASH,       ## grey flakes, slow, falling         — Ashfall Verge
	LEAVES,    ## broad, tumbling, warm              — Verdant Tier
	SNOW,      ## white, slow, wide drift            — Frostmarch
	EMBERS,    ## small, RISING, hot                 — Crimson Room / Emberworks
	BUBBLES,   ## round, rising, slow                — Drowned Gallery
	RAIN,      ## fast, steep, thin                  — Stormreach
	GLINT,     ## sparse hanging motes, pale         — Glasswood / Sunken Vault
	STARFALL,  ## slow gold drift, sparse            — The Apex
}

@export var weather: int = Weather.NONE

## What is BEYOND this floor — the sky seen through the clerestory band `SkyVista`
## opens in the back wall. Most floors are sealed rooms and take NONE, which costs
## nothing at all (no node process, no draw); a tower is mostly interiors, and that
## is exactly what makes the three floors that DO open onto a sky land.
## ⚠ NAMED `SkyKind`, NOT `Sky`. `Sky` is a NATIVE Godot class (the 3D environment
## resource), and an enum of that name fails to compile with "The member \"Sky\"
## shadows a native class" — which then cascades: GameState fails to parse, the
## autoload fails to instantiate, and the first visible symptom is the whole game
## refusing to boot rather than anything pointing at this line.
enum SkyKind {
	NONE,     ## a sealed room
	SUNSET,   ## a low sun crossing, four parallax cloud layers, light on the sill
	ECLIPSE,  ## a black disc with a living corona, stars out in the middle of the day
}

@export var sky: int = SkyKind.NONE

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
