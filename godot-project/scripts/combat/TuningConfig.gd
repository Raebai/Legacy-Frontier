class_name TuningConfig
extends Resource
## Single live-tunable feel surface for the highest-traffic "how heavy does it
## feel" knobs. Edit res://data/tuning.tres in the inspector, or drag these in
## Remote -> Tuning while the game runs, to tune WITHOUT a relaunch.
##
## Only hero-local movement/feel constants live here (the ones the maker re-touches
## every session). Per-class ability tuning stays in Hero.CLASS_CONFIG; the long
## tail of colours/particles/anim constants stays as `const` in its owning script.
## Any field left unset falls back to the code default at the read site, so a
## missing/renamed field never crashes.

@export_group("Hero movement")
@export var hero_speed: float = 210.0    # base walk speed
@export var dash_speed: float = 620.0    # dash burst velocity (distance = speed*time)
@export var dash_time: float = 0.14      # dash duration AND i-frame window length
@export var move_gravity_rise: float = 2600.0  # rise gravity (real weight, not floaty apex)
@export var move_gravity_fall: float = 3000.0  # fall gravity (heavier coming down)
@export var move_jump_velocity: float = -740.0 # jump launch velocity (a committed hop, not a float)
@export var move_air_accel: float = 750.0      # air accel/decel (low = no mid-air free-steer)
@export var move_max_fall: float = 1400.0      # terminal fall speed clamp

@export_group("Hero feel")
@export var hurt_hit_stop: float = 0.05  # freeze when the hero takes a hit
@export var hurt_shake: float = 7.0      # shake when the hero takes a hit
@export var melee_hit_stop: float = 0.07 # freeze when a melee connects
@export var move_accel: float = 2600.0   # px/s^2 velocity ramp (weight/flow); high = snappy

@export_group("Camera")
@export var lookahead_dist: float = 8.0  # px the camera peeks toward aim (was 22 — the "shake when I move")
@export var shake_scale: float = 1.0     # global multiplier on screenshake magnitude (0 = off). Screenshake slider drives this.

@export_group("Combat feel")
## THE knockback knob. Multiplies EVERY impulse — melee, spells, blasts, guard-cut —
## for both Hero and Enemy, so it is the one number to turn when hits feel wrong.
## Cut 1.6 -> 1.0 on the maker's "the knockback is too much": at 1.6 a plain 300-unit
## fist was shoving 480 units and a juggernaut swing 750, which reads as a launch
## rather than an impact. At 1.0 every KNOCKBACK constant in the codebase finally
## means what it says, and the per-weapon SHAPE (fists 300 < swordsaint 430 <
## juggernaut 470) is untouched — this was never a per-weapon problem.
##
## ⚠ Deliberately NOT the same thing as the Smash ring-out scaling, which multiplies
## on top of this AFTER damage % is read (see Hero/Enemy.ringout_knockback_scale) and
## is the core mechanic of the arena. Cutting the base does not flatten that curve —
## a 100%-damage fighter still takes 2x whatever this knob says.
## UNTESTED GUESS. If it now reads floaty rather than punchy, come back HERE first.
@export var knockback_mult: float = 1.0
@export var pct_per_damage: float = 0.8  # SANDBOX Smash model (GameState.ringout_mode): % gained per point of incoming damage. Single source of truth for Hero + Enemy so they can't silently diverge on retune; ~0.8 keeps a typical 12-28 dmg hit in the single-to-low-double-digit % range
@export var hit_stop_enabled: bool = true  # accessibility: off = no time-freeze on hits

@export_group("Graphics")
## THE MOBILE DIAL. Everything expensive enough to matter on a phone asks
## `TuningConfig.quality_is_low()` rather than testing the platform itself, so
## there is exactly one place to flip and — critically — the maker can PREVIEW
## the phone's picture on the desktop by setting this to LOW. That preview matters
## more than usual here: no APK has ever been built, so LOW on desktop is the only
## way to see what the phone build will look like before one exists.
##   AUTO — LOW on an Android/iOS export, HIGH everywhere else. The shipping default.
##   HIGH — force the full picture (a mobile player on a flagship may want this).
##   LOW  — force the cheap picture (desktop preview, or a struggling phone).
enum Quality { AUTO, HIGH, LOW }
@export var graphics_quality: Quality = Quality.AUTO

@export var post_process_enabled: bool = true  # the reactive screen-space grade ("the look"); off = raw render (low-end / accessibility). AND-ed with quality_is_low() — see PostProcess._enabled()
## PHOTOSENSITIVITY option. On = every full-screen impact frame (the white
## blow-out, the black silhouette cut, the colour field, the negative, the
## cut-in) DOWNGRADES to ImpactFrame.Style.LOCAL — a small, low-contrast ring
## around the hit — instead of a large-area high-contrast flash. Hit-stop,
## screenshake, camera punch and the screen ripple all still fire, so the game
## keeps every bit of its weight; only the flashing goes.
## Note this is the OPT-IN softening: a hard flash-rate ceiling
## (ImpactFrame.MAX_FULLSCREEN_FLASHES_PER_SECOND) applies to everyone either way.
@export var reduce_flashing: bool = false


# ------------------------------------------------------------ the quality probe
## Is the cheap picture in force? Read this, never `OS.has_feature("mobile")`
## directly, so the desktop LOW preview works everywhere the phone build does.
##
## ⚠ STATIC, and therefore it may NOT name the `Tuning` autoload. Naming an
## autoload inside a static function is a COMPILE error in GDScript that takes the
## whole dependency chain down with a misleading "missing method" message — the
## trap is documented on ImpactFrame.reduce_flashing() and SpellDeflect._sfx().
## The tree lookup below is the house idiom. It also means this answers correctly
## under `--script`, where autoloads are never registered: no Tuning -> AUTO ->
## desktop -> HIGH, which is exactly what the headless suites should see.
static func quality_is_low() -> bool:
	match _quality_setting():
		Quality.HIGH:
			return false
		Quality.LOW:
			return true
	# AUTO. `mobile` is the feature tag Godot sets on Android + iOS exports.
	return OS.has_feature("mobile")


## Raw enum value from the live config, defaulting to AUTO when there is no
## Tuning autoload (headless `--script`) or no `graphics_quality` field (an older
## data/tuning.tres — every field here is override-only by design).
static func _quality_setting() -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return Quality.AUTO
	var t: Node = tree.root.get_node_or_null(^"/root/Tuning")
	if t == null or t.get(&"cfg") == null:
		return Quality.AUTO
	var v: Variant = t.cfg.get(&"graphics_quality")
	return Quality.AUTO if v == null else int(v)


## May a full-screen SHADER that reads back the rendered frame run right now?
##
## On a tile-based mobile GPU a `hint_screen_texture` fetch is not a texture read,
## it is a framebuffer RESOLVE — the tile is flushed to main memory and loaded
## back — and it costs the same whether one pixel or every pixel samples it. The
## game has three such shaders (post_process.gdshader plus ImpactFrame's INVERT
## and SILHOUETTE plates) and they can all be live in the same frame during a big
## fight. That is the single largest avoidable cost in the renderer on a phone.
static func screen_shaders_allowed() -> bool:
	return not quality_is_low()
