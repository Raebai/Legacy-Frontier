extends RefCounted
## THE HUD'S ONE SET OF RULES — colour, type, outline weight, panel, zoom, layer,
## and the vertical band each piece of the combat HUD is allowed to occupy.
##
## ══ WHY THIS FILE EXISTS ══════════════════════════════════════════════════════
## Maker: *"the game is really ugly and unpolished"* and *"make this game feel
## precise and professional"* — with the explicit constraint *"dont just add random
## effects optimise the ones that currently exist"*. So nothing here is new art. It
## is a CONSOLIDATION: ten HUD files had each invented their own palette, their own
## type sizes and their own place on the screen, and a survey of the nine this
## covers measured the result:
##
##   * 56 `Color(...)` literals, 52 of them distinct, and ZERO shared between two
##     files. Thirteen different "whites", six "reds", seven "golds", eleven
##     near-blacks all doing outline/shadow work. `CharacterBars.PCT_WARM` was
##     `(1.0, 0.82, 0.35)` while `RunSummary` used `(1.0, 0.82, 0.36)` — two
##     constants, in two files, for one colour, differing by 0.01 in one channel.
##   * seven authored font sizes (9, 11, 13, 15, 20, 22, 26) plus two DYNAMIC
##     families (`Hype._shout_it` spans 22–34, `DamageNumber` spans 15–39).
##   * five outline widths (3, 4, 5, 6, 7).
##
## None of that is a bug on its own. Together it is exactly what "unpolished"
## looks like: the eye reads ten near-misses as sloppiness long before it can name
## which two greys differ.
##
## ⚠ EVERY VALUE BELOW WAS ALREADY IN THE CODEBASE. Each entry is the best
## representative of a cluster that already existed, not a new taste call — the
## brief was a consolidation, not a redesign, and a redesign would also have
## thrown away tuning that survived playtests.
##
## ══ HOW TO USE IT ═════════════════════════════════════════════════════════════
##   const HudStyle := preload("res://scripts/ui/HudStyle.gd")
##
## ⚠ NO `class_name`, DELIBERATELY. A `class_name` has to be registered in
## `.godot/global_script_class_cache.cfg`, which is rebuilt by an editor scan or a
## `--import`; a consumer compiled before that scan fails with "Could not find type
## X in the current scope" (Sessions 6/8/9 lost real time to exactly this). A
## `preload`ed script resolves at load time with no cache involved, so this file
## can be added and consumed in the same commit with no import step at all.


# ══════════════════════════════════════════════════════════════════ THE PALETTE
## Nine literals. Every other colour in the HUD is derived from one of them by a
## documented operation, so a future change to "the gold" is one edit.
##
## ⚠ ALPHA IS NOT PART OF A PALETTE ENTRY. Every entry is opaque and the alpha is
## applied at the use site (`ink()`, `frame()`, `scrim()`, `.with_a()` below). The
## eleven near-blacks in the survey were mostly ONE colour at eight alphas; storing
## the alpha in the constant is what made them look like eight colours.

## The page. The ground under every card and panel. Already shared verbatim by
## `Arena.CARD_PAPER` and `RunSummary` — the one colour in the survey that two
## files had agreed on, so it is the anchor of the whole scheme.
const PAPER: Color = Color(0.055, 0.052, 0.075)

## The dark the type is cut out of: text outlines, bar frames, screen scrims. The
## survey's eleven near-blacks clustered hard around this value; it is the modal
## outline colour (`Hype`, `FloorAffixHud`, `BossModifierHud` all wrote it, each
## with a different rounding).
const INK: Color = Color(0.04, 0.04, 0.07)

## The chalk the tower is drawn in. `Arena.CARD_CHALK` / `RunSummary`, again a
## value two files had already agreed on. Everything the player READS is this or a
## tint of it.
const CHALK: Color = Color(0.93, 0.92, 0.86)

## Chalk that is deliberately quieter — sub-lines, captions, the "and this is the
## less important exit" button. `Arena.CARD_GRAPHITE` / `RunSummary`.
const GRAPHITE: Color = Color(0.62, 0.63, 0.70)

## Reward, currency, the thing you want. Representative of the seven-gold cluster,
## and specifically the value `CharacterBars.PCT_WARM` and `RunSummary` were each
## storing to one decimal place apart.
const GOLD: Color = Color(1.0, 0.82, 0.35)

## The accent of a stopped screen: the death card's rule, a boss's default accent,
## the portal you leave by. `Arena.CARD_ASH` / `RunSummary.accent_for(WIPED)`.
##
## ⚠ KEPT SEPARATE FROM `DANGER` ON PURPOSE, even though both are "red". Ember is
## a brand accent on a still page; danger is an alarm on a moving bar. Collapsing
## them would make the death card read as a warning siren, which is the one thing
## a card the player has already lost to must not do.
const EMBER: Color = Color(0.96, 0.42, 0.36)

## You are about to die. The hot end of the HP ramp, the low-health ring, the
## damage-% saturation. Representative of `(0.95,0.16,0.12)`, `(1.0,0.24,0.2)` and
## `(0.92,0.25,0.2)`, which were three files' answers to one question.
const DANGER: Color = Color(0.95, 0.22, 0.17)

## Alive, healed, won. ONE green, not two: the survey's four greens
## (`(0.3,0.85,0.35)` full HP, `(0.5,1.0,0.65)` heal rim, `(0.55,1.0,0.7)` wave
## cleared, `(0.85,0.95,0.7)` the affirmative button) sat within 0.25 of each other
## in every channel and all four mean the same thing to the player.
const MINT: Color = Color(0.45, 0.92, 0.55)

## Mana, and every cool-side callout (a wave opening, a close call survived, the
## neutral button). Representative of `CharacterBars.MP_COLOR`; the four pale blues
## in the survey are this lerped toward CHALK — see `SKY`.
const AZURE: Color = Color(0.45, 0.68, 1.0)


# ─────────────────────────────────────────────────────── derived, not authored
## Pale blue TEXT. The survey had `(0.72,0.86,1.0)`, `(0.55,0.95,1.0)` and
## `(0.88,0.94,1.0)` doing this job in three files; all three are AZURE on its way
## to CHALK, so that is how it is written.
const SKY: Color = Color(0.71, 0.81, 0.94)      # AZURE.lerp(CHALK, 0.55)
## The chip bar: the health you just lost, held on screen a beat. Chalk warmed
## toward gold — it must read as "was health" without reading as "is health".
const CHIP: Color = Color(0.95, 0.89, 0.68)     # CHALK.lerp(GOLD, 0.32)
## The interior of any bar track. PAPER lifted just clear of the page so an empty
## bar is still a SHAPE rather than a hole.
const TRACK: Color = Color(0.085, 0.082, 0.11)  # PAPER.lightened(0.03)


## `INK` at the alpha a given job wants. Named calls rather than eight constants,
## because the survey's near-blacks differed almost entirely in alpha.
static func ink(a: float = 0.95) -> Color:
	return Color(INK.r, INK.g, INK.b, a)


## The frame around a bar. Thinner alpha than a text outline: a bar already has a
## hard edge, so the frame is there to separate it from a LIT floor, not to carry
## the shape on its own.
static func frame() -> Color:
	return ink(0.78)


## A full-screen dim behind a modal. One value; the survey had 0.66 and 0.72 for
## the same job in the same file.
static func scrim() -> Color:
	return ink(0.70)


## Any palette entry at an alpha. `Color.a` is not settable on a `const`, and
## `Color(c.r, c.g, c.b, a)` written inline forty times is how the palette drifted
## in the first place.
static func with_a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## The HP ramp: MINT (full) → GOLD (half) → DANGER (empty). The same three-stop
## shape `CharacterBars._hp_color` always had, now built from the palette so the
## bar and the rest of the HUD cannot drift apart.
static func hp_color(t: float) -> Color:
	if t > 0.5:
		return MINT.lerp(GOLD, (1.0 - t) * 2.0)
	return GOLD.lerp(DANGER, (0.5 - t) * 2.0)


# ══════════════════════════════════════════════════════════════ THE TYPE SCALE
## Five steps, replacing seven authored sizes. The steps are the sizes that were
## already carrying the most weight (11 appeared eight times; 20 and 26 twice
## each); 13 and 15 collapse into 14 and 22 collapses into 20, because at a 640x360
## base a two-pixel difference is not a distinction the eye can use — it is only
## enough to look like a mistake.
##
## ⚠ THE BASE VIEWPORT IS 640x360. These are small numbers on purpose. A "14" here
## is a comfortable body size, not a caption.
const MICRO: int = 9    # a bark over a body — the smallest type the game has
const SMALL: int = 11   # captions, affix lines, modifier chips, the rank title
const BODY: int = 14    # banners, buttons, menu rows, a boss's name
const LEAD: int = 20    # a card's headline, the chain counter
const TITLE: int = 26   # the shout — the only type allowed to be loud


## Outline weight for a given type size. Five widths (3/4/5/6/7) collapse to two:
## small type needs the outline to carry its SHAPE, large type only needs it to
## separate the glyph from the floor, and anything between reads as neither.
static func outline_for(font_size: int) -> int:
	return 3 if font_size <= SMALL else 5


## Apply the house treatment to a `Label` in one call: size, colour, the matching
## outline weight, and INK as the outline. Six files were writing these four lines
## by hand, which is how three of them ended up with a different near-black.
static func label(l: Label, font_size: int, color: Color) -> void:
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", ink(0.95))
	l.add_theme_constant_override(&"outline_size", outline_for(font_size))


## The one panel shape: PAPER ground, a one-pixel accent rule, a 3px radius. Taken
## verbatim from `Arena`'s game-over card, which is the only panel in the HUD the
## maker has signed off on. The survey found four different panel fills, four
## alphas and three border widths; this is the survivor.
static func panel(accent: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = accent
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.content_margin_top = 16.0
	box.content_margin_bottom = 16.0
	return box


# ═══════════════════════════════════════════════════════ THE ONE ZOOM RULE
## ⚠ READ THIS BEFORE ADDING ANYTHING TO THE HUD.
##
## The combat camera runs from `FRAME_ZOOM_MIN` 0.46 (whole room in frame) to
## `ZOOM_MAX` 2.6 (tight on one fighter) — a **5.6x** swing, and it moves during
## a fight rather than between them. There are exactly two kinds of HUD element
## and the rule for each is different:
##
##   1. **SCREEN-SPACE HUD** — anything under a `CanvasLayer`/`Control`: the boss
##      bar, the rank title, the floor banner, the affix card, the modifier row,
##      Hype's shout and counter, the ability bar, the pause menu. A CanvasLayer is
##      not transformed by the camera, so these are already immune. Nothing to do
##      except keep them there. **Never put a readable HUD element in world space
##      to "make it follow something" — attach a world ANCHOR and draw the readout
##      on the layer.**
##
##   2. **BODY-ATTACHED HUD** — a `Node2D` that must travel with a fighter:
##      `CharacterBars`, `DamageNumber`, a `Bark` bubble. These cannot leave world
##      space without losing the thing that makes them work. So every drawn
##      dimension in one of them — width, height, padding, font size, ring radius —
##      is multiplied by `ui_scale()`, which holds its ON-SCREEN size constant.
##
## What that fixed, measured at the two zoom extremes against a 360-tall viewport:
##
##   enemy HP bar     1.8 px tall at 0.46 → 6.4 px, the size it is at rest
##   hero HP bar      grew while the enemy bars shrank, in the same frame → both hold
##   ringout "%"      5 px at 0.46 / 29 px at 2.6 → 17.6 px throughout
##   damage number    7 px at 0.46 / 101 px at 2.6 → 29 px (62 px for a crit pop)
##
## ⚠ THE REFERENCE IS 1.6, NOT 1.0. `CombatCamera.DEFAULT_ZOOM` is 1.6, so 1.6 is
## the zoom every one of these widgets was actually TUNED at. Compensating toward
## 1.0 (which is what `CharacterBars._ui_scale` used to do, by clamping its low end
## there) would have shrunk the hero's health bar by 38% on screen at rest — against
## a maker note that said, in as many words, "I cannot read my health". Using 1.6 as
## the reference means every widget is pixel-identical to today at rest and merely
## stops changing size when the camera moves.
##
## ⚠ APPLY IT TO THE DRAWING, NEVER TO `Node2D.scale`. Scaling the node also scales
## its `position` offset in the parent's space, which drags a head-mounted bar down
## through the head as the camera pulls back.

## `CombatCamera.DEFAULT_ZOOM.x`. Restated rather than imported: naming
## `CombatCamera` here would bolt a 500-line camera onto the compile of every file
## that draws a HUD pixel, for three floats. `Arena` restates `RunSummary`'s
## palette for the same class of reason. If the camera's range moves, these move.
const ZOOM_REF: float = 1.6
## `CombatCamera.ZOOM_MAX` — tightest the camera ever gets.
const ZOOM_TIGHT: float = 2.6
## `CombatCamera.FRAME_ZOOM_MIN` — widest.
const ZOOM_WIDE: float = 0.46


## The multiplier that holds a body-attached widget's ON-SCREEN size constant.
##
## on-screen = world_size * camera_zoom * ui_scale, and ui_scale = ZOOM_REF / zoom,
## so on-screen = world_size * ZOOM_REF — independent of the camera. The clamp is
## two-sided and its bounds are the camera's own limits, so it never binds during
## real play and only catches a camera that has been driven somewhere impossible
## (a capture tool, a test harness, a future zoom range nobody updated here).
##
## Returns 1.0 — i.e. "draw it as authored" — for a node with no camera, which is
## every headless suite. That is deliberate: a suite measuring world geometry must
## not have its numbers moved by whether a camera happened to exist.
static func ui_scale(node: Node) -> float:
	if node == null or not node.is_inside_tree():
		return 1.0
	var vp: Viewport = node.get_viewport()
	if vp == null:
		return 1.0
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return 1.0
	var z: float = minf(cam.zoom.x, cam.zoom.y)
	if z <= 0.01:
		return 1.0
	return clampf(ZOOM_REF / z, ZOOM_REF / ZOOM_TIGHT, ZOOM_REF / ZOOM_WIDE)


## The frame/padding around a bar, in world px, at a given `ui_scale`. One weight
## for every bar in the game: the survey found the hero's HP bar carrying a
## 2.0–4.8px frame while the MP bar directly beneath it — same widget, same
## column — carried a hardcoded 1.0px one.
const FRAME_PAD: float = 1.5


static func frame_pad(ui: float) -> float:
	return maxf(FRAME_PAD * ui, 1.0)


# ══════════════════════════════════════════════════════ LAYERS AND BANDS
## ⚠ THE COMBAT HUD IS A FIXED ALLOCATION, NOT A NEGOTIATION. Every piece below
## used to pick its own `CanvasLayer` index and its own `offset_top`, and the
## survey measured what that produced. Four collisions, none of them rare:
##
##   * `Hype.HUD_LAYER` and the boss bar were BOTH 55, so which one drew on top
##     depended on whether the Arena built Hype before the boss spawned. Hype's
##     shout (y 62–96) and the boss bar strip (y 64–79) then overlapped on EVERY
##     boss fight.
##   * the chain counter (x 480–628, y 34+) sat on top of the pause BUTTON
##     (x 586–630, y 10–54) — the only pause affordance a phone has.
##   * the rank title (y ~2–25) and the floor banner (y ~18–41) were both on layer
##     50 and their outline bands overlapped, both centred on x=320.
##   * the affix card (y 54–84) crossed the boss bar, and a THIRD affix spilled
##     into the modifier row at y 84.
##
## Layers 90 (pause menu), 120 (brightness) and 200 (perf overlay) belong to other
## files and are listed here only so nobody reuses them.
const LAYER_HUD: int = 50        # persistent: hero bars, ability bar, pause BUTTON
const LAYER_BANNER: int = 52     # floor banner + rank title
const LAYER_BOSS_BAR: int = 55
const LAYER_BOSS_MODS: int = 56
const LAYER_AFFIX: int = 57
const LAYER_SHOUT: int = 60      # transient shouts / combo — ABOVE the boss bar, deliberately

## Z-INDEX, for the two world-space HUD nodes. Same problem one layer down: damage
## numbers were at 60 and the health bars at 30, so a number could sit on top of
## the bar it was explaining. The bar is the persistent readout and wins.
const Z_DAMAGE_NUMBER: int = 60
const Z_CHARACTER_BARS: int = 64

## The vertical strips, in BASE-VIEWPORT pixels (640x360). Each is
## `[top, bottom]`, they are full-width, and **no two may overlap** —
## `tools/slice_test_hud_layout.gd` measures the live nodes and fails if any
## element leaves its strip or any two strips intersect.
##
## ⚠ THE SHOUT MOVED FROM y 62 TO y 150, which is the one change here that a player
## will notice. It had to leave the top: the boss bar needs a contiguous 40px for a
## name plus a bar, and the shout is the only piece of the top stack that is
## transient, centred, and therefore able to live over the fight without hiding a
## readout. y 150–190 is above the arena floor line and below every persistent
## readout.
## ⚠ THREE OF THESE ARE 2px LOWER THAN THE ALLOCATION THEY WERE DRAFTED FROM, and
## the reason is a measurement rather than a preference. The fallback font's minimum
## LABEL HEIGHT is 16px at SMALL, 20px at BODY and 42px at 30 — so an 18px strip
## cannot hold a BODY-sized floor banner, and the draft's 22-40 failed the layout
## test by exactly 2 pixels on the first run. The banner band grew to 20 and the
## three bands under it moved down with it. Nothing overlaps, which is the rule the
## allocation actually exists to enforce.
const BAND_RANK: Array[float] = [2.0, 20.0]
const BAND_FLOOR_BANNER: Array[float] = [22.0, 42.0]
const BAND_BOSS_BAR: Array[float] = [44.0, 84.0]
const BAND_BOSS_MODS: Array[float] = [86.0, 106.0]
const BAND_AFFIX: Array[float] = [110.0, 142.0]
const BAND_SHOUT: Array[float] = [150.0, 190.0]

## The pause button's reserved corner, in base-viewport pixels: a 44x44 target at a
## 10px margin from the top-right of a 640-wide screen, plus slack. NOTHING may be
## drawn into it. Owned by `PauseMenu`; restated here because the rule is about
## everyone ELSE staying out.
const PAUSE_CORNER: Rect2 = Rect2(580.0, 0.0, 60.0, 60.0)

## The base viewport the bands are expressed in (`project.godot`
## `window/size/viewport_{width,height}`).
const BASE_VIEWPORT: Vector2 = Vector2(640.0, 360.0)


# ══════════════════════════════════════════════ THE PLAYER'S OWN HEALTH PLATE
## ⚠ THE PLAYER'S HEALTH LEFT THE PLAYER'S HEAD. Maker: *"the health bar is blocking
## the stick figure, the main one — put that somewhere else so that it's clear and
## more professional"*. It was a 52x7 bar floating over a 31px figure, and on a
## screen that frames two fighters it covered the one thing the player is looking at.
##
## WHY THE BOTTOM CORNER AND NOT THE TOP.
##   * **The top of the screen is the ROOM's stack.** Every band above — rank, floor
##     banner, boss bar, boss modifiers, affixes, shout — describes the FLOOR you are
##     on. All of it is contextual and most of it is transient. The bottom is the
##     PLAYER's stack: the hotbar, and now this. Health next to cooldowns is one
##     glance; health at the top and cooldowns at the bottom is two.
##   * **The top corners are both spoken for.** Top-right is `pause_corner()`, the only
##     pause affordance a phone has. Top-left is free of the CENTRED text up there but
##     not of the boss bar, which at `BossBar.WIDTH_FRAC` 0.62 of a 640 base runs
##     x 121..519 — so a second player's mirrored plate would land on it during exactly
##     the fight where both readouts matter most.
##   * **Co-op is already solved down here.** `AbilityBar.dock_right` / `dock_row`
##     hands player two the opposite corner and stacks three and four upward. The plate
##     reuses that rule rather than inventing a second one, so the plate and the hotbar
##     it belongs to are always in the same corner as each other.
##
## ⚠ AND IT IS SCREEN-SPACE, WHICH IS THE WHOLE POINT. The head bar was a `Node2D`, so
## the ONE ZOOM RULE above had to fight for it: its on-screen size was its world size
## times a camera zoom that swings 5.6x DURING a fight, and `ui_scale()` existed to
## cancel that out. A `CanvasLayer` is not transformed by the camera at all, so the
## plate is simply the same number of pixels always — the zoom problem is not
## compensated for, it is gone. Enemy bars stay body-attached and stay compensated:
## with six enemies on screen, "which one of those is hurt" is a question only a bar
## over that specific body can answer.

## The plate's shape, in base-viewport pixels. Wider and shorter than the head bar it
## replaces (52x7): a screen-anchored bar never has to compete with a rig for space, so
## the extra length buys resolution — 1% of health is 1.6px here against 0.5px before.
const HERO_PLATE_SIZE: Vector2 = Vector2(156.0, 13.0)
## Matches `AbilityBar.SIDE_MARGIN`, so the plate's edge and the hotbar's edge are the
## same edge. Two margins 2px apart in one corner is the near-miss this palette file
## exists to stop.
const HERO_PLATE_MARGIN_X: float = 16.0
## Clear air between the plate and the top of the hotbar underneath it.
const HERO_PLATE_GAP: float = 7.0
## A tick every quarter. Four segments is the most a bar can carry and still be read as
## a SHAPE rather than counted — inherited verbatim from the head bar, which is the one
## part of it that was working.
const HERO_PLATE_SEGMENTS: int = 4
## The frame weight, matching `BossBar.FRAME`. A screen-space bar does not use
## `frame_pad()` — that function scales a WORLD bar by the camera, and there is no
## camera in this coordinate space.
const HERO_PLATE_FRAME: float = 2.0


## Where one player's health plate goes.
##
## `bottom_reserved` is how far up from the bottom edge that player's own hotbar
## already reaches — `AbilityBar.occupied_height()` plus whatever `dock_row` has
## pushed it. Passed IN rather than read here on purpose: naming `AbilityBar` from this
## file would bolt the hotbar's whole compile onto every file that draws a HUD pixel,
## and it would make this function untestable without standing one up.
##
## ⚠ `view`, NOT `BASE_VIEWPORT`. `project.godot` runs `aspect="expand"`, so a 20:9
## phone hands the HUD a logical viewport about 800x360 rather than 640x360 — the
## HEIGHT is what stays fixed. Anything anchored to the left edge is safe as a
## constant; anything anchored to the right edge is not, and a right-docked player two
## computed off 640 would sit 160px inside the screen. See `pause_corner`, which is the
## same bug, already shipped.
static func hero_plate_rect(view: Vector2, dock_right: bool,
		bottom_reserved: float) -> Rect2:
	var y: float = view.y - bottom_reserved - HERO_PLATE_GAP - HERO_PLATE_SIZE.y
	var x: float = HERO_PLATE_MARGIN_X
	if dock_right:
		x = view.x - HERO_PLATE_MARGIN_X - HERO_PLATE_SIZE.x
	return Rect2(Vector2(x, y), HERO_PLATE_SIZE)


## The pause button's reserved corner FOR A GIVEN VIEWPORT.
##
## ⚠ `PAUSE_CORNER` BELOW IS A FIXED RECT AND THE BUTTON IS NOT. `PauseMenu` anchors
## its 44x44 button to the RIGHT EDGE at a 10px margin, so on the expanded 800-wide
## viewport a 20:9 phone actually gets, the button is at x 746..790 and the constant
## points at empty screen 160px away. Two tool files
## (`tools/probe_touch_layout.gd`, `tools/slice_test_touch_layout.gd`) had each already
## written that fault down in a comment and worked around it by restating the button's
## two numbers as local literals — which is the codebase telling you, twice, that the
## constant is the wrong shape. This is the right shape; the const stays as the 16:9
## case so existing callers do not change meaning underneath them, and every new check
## should call this instead.
static func pause_corner(view: Vector2) -> Rect2:
	return Rect2(view.x - PAUSE_CORNER.size.x, PAUSE_CORNER.position.y,
		PAUSE_CORNER.size.x, PAUSE_CORNER.size.y)
