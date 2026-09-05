extends RefCounted
## THE TOUCH LAYOUT MATHS, pulled out of `TouchControls` so it can be MEASURED without
## building a pad, and so the pad and the probe can never disagree about where a thumb
## target actually is.
##
## ⚠ NO `class_name`, AND EVERY ENTRY POINT IS `static func`. Consumers reach this via
## `const TouchLayout := preload("res://scripts/combat/TouchLayout.gd")`, and a preload
## of a .gd yields the SCRIPT OBJECT, not an instance — a plain `func` here would
## compile cleanly and then die at RUNTIME with "Nonexistent function ... in base
## 'GDScript'". Four agents have paid for that trap in this project already.
##
## ⚠ AND NOTHING IN HERE MAY TOUCH AN AUTOLOAD OR LOAD A SCENE. `tools/` suites run
## under `--script`, where no autoload exists and one autoload identifier anywhere in a
## file's compile chain fails the WHOLE chain. That is why this file preloads nothing,
## extends `RefCounted`, and takes every number it needs as an argument.
##
## WHAT THIS FILE IS FOR, in one sentence: a phone screen is not 640x360, the pixels
## are not square millimetres, and the operating system owns some of them. Every one of
## those three facts was unmodelled before this file existed.


# ═══════════════════════════════════════════════════ 1. THE LOGICAL VIEWPORT

## The project's base viewport (`project.godot` window/size/viewport_{width,height}).
const BASE: Vector2 = Vector2(640.0, 360.0)

## What `window/stretch/aspect="expand"` actually does, as arithmetic.
##
## ⚠ THIS IS THE FACT THE WHOLE TASK TURNS ON, AND IT IS COUNTER-INTUITIVE: a TALLER
## phone does not get letterboxed and does not get a taller picture. `expand` picks the
## uniform scale that makes the base fit (`min` of the two ratios) and then hands the
## surplus back as EXTRA LOGICAL PIXELS on the roomy axis. In landscape that axis is
## always X, because every phone is wider than 16:9. So a 20:9 device does not run at
## 640x360 — it runs at 800x360, and everything anchored to the RIGHT edge moves 160
## logical pixels away from everything anchored to the LEFT edge.
##
## A layout checked only at 640x360 is therefore checked at the ONE aspect no modern
## phone has.
static func logical_size(device: Vector2, base: Vector2 = BASE) -> Vector2:
	if device.x <= 0.0 or device.y <= 0.0:
		return base
	var scale: float = minf(device.x / base.x, device.y / base.y)
	if scale <= 0.0:
		return base
	return Vector2(device.x / scale, device.y / scale)


## Device pixels per logical (base-space) pixel — the number every "in base units"
## measurement has to be multiplied by before it means anything about a real screen.
static func device_scale(device: Vector2, base: Vector2 = BASE) -> float:
	if device.x <= 0.0 or device.y <= 0.0:
		return 1.0
	return minf(device.x / base.x, device.y / base.y)


# ═══════════════════════════════════════════════════ 2. MILLIMETRES

## ⚠ THE UNIT A THUMB IS ACTUALLY MEASURED IN. "46 px" and "60 px" are meaningless as
## thumb targets: the same 60 base-space pixels are 10.6 mm on a 6.1" phone and 15 mm on
## a tablet. Every human-factors number that exists for touch — Apple's 44 pt, Google's
## 48 dp, the Parhi/Karlson finger-pad studies — is a PHYSICAL size in disguise, so this
## file converts to millimetres before it judges anything.
##
## Contact width of a thumb pad pressing a screen. Below this a target is smaller than
## the finger hitting it, which is the definition of a mis-tap.
const THUMB_CONTACT_MM: float = 11.0
## The floor a target may not go under. 9 mm is the widely-replicated 95%-success size
## for a thumb on a held device; Google's 48 dp is 8.5 mm and Apple's 44 pt is 7.8 mm,
## so this is the STRICTEST of the three and deliberately so — this game asks for taps
## during a fight, not during a form fill.
const THUMB_MIN_MM: float = 9.0
## How far a thumb sweeps from its knuckle without the hand regripping. Past COMFORT it
## is a stretch; past MAX the hand has to move, which in a fight means it does not
## happen at all.
const THUMB_COMFORT_MM: float = 45.0
const THUMB_MAX_MM: float = 62.0
## Where the thumb PIVOTS, as an inset from the bottom corner of the SAFE area, in mm.
## A landscape grip puts the knuckle just inboard and just above the corner.
const THUMB_PIVOT_MM: Vector2 = Vector2(12.0, 10.0)

const MM_PER_INCH: float = 25.4


## Millimetres per logical pixel, from a device's diagonal and its native resolution.
## Everything else in the mm block is derived from this one number.
static func mm_per_unit(diagonal_inches: float, device: Vector2, base: Vector2 = BASE) -> float:
	if diagonal_inches <= 0.0 or device.length() <= 0.0:
		return 0.0
	# Physical pixel pitch first (mm per DEVICE pixel), then out through the stretch.
	var px_diag: float = device.length()
	var mm_per_device_px: float = (diagonal_inches * MM_PER_INCH) / px_diag
	return mm_per_device_px * device_scale(device, base)


# ═══════════════════════════════════════════════════ 3. WHAT THE OS OWNS

## Insets the operating system has a claim on, in LOGICAL pixels, as
## (left, top, right, bottom).
##
## ⚠ NOTHING IN THIS PROJECT READ THE SAFE AREA BEFORE THIS FUNCTION. Not one call to
## `DisplayServer.get_display_safe_area()` anywhere in `scripts/` or `tools/`. The
## export preset sets `screen/immersive_mode=true`, which hides the bars but does NOT
## give the pixels back on a phone with a display cutout: Godot's Android manifest asks
## for `shortEdges`, so in LANDSCAPE the notch eats a vertical strip off whichever end
## of the long axis happens to be up. Which end that is depends on which way the player
## turned the phone, so a layout can only be correct if it reads the inset rather than
## assuming a side.
static func safe_insets(viewport: Vector2) -> Vector4:
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0 or viewport.x <= 0.0 or viewport.y <= 0.0:
		return Vector4.ZERO
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	# ⚠ THE SAFE AREA IS IN WINDOW PIXELS AND THE LAYOUT IS IN LOGICAL ONES. Converting
	# with `device_scale` would be wrong on a desktop window that is not phone-shaped;
	# the honest conversion is the ratio the viewport ACTUALLY ended up at.
	var kx: float = viewport.x / float(win.x)
	var ky: float = viewport.y / float(win.y)
	return Vector4(
		maxf(0.0, float(safe.position.x) * kx),
		maxf(0.0, float(safe.position.y) * ky),
		maxf(0.0, float(win.x - (safe.position.x + safe.size.x)) * kx),
		maxf(0.0, float(win.y - (safe.position.y + safe.size.y)) * ky))


## ⚠ THE GESTURE BAR IS NOT IN THE SAFE AREA, AND THAT IS THE POINT. Android reports a
## safe area that already excludes a VISIBLE nav bar — but this game ships
## `screen/immersive_mode=true`, so the bar is hidden, the safe area grows to the full
## screen, and the swipe-up-from-the-bottom-edge gesture KEEPS WORKING. A control whose
## rect reaches into that strip is a control the operating system will sometimes steal
## the drag from, and the safe area will never tell you.
##
## 24 dp is the Android system gesture inset (`WindowInsets.Type.systemGestures`,
## bottom) on every device that has gesture navigation. Expressed in mm here — 24 dp is
## 24/160 inch = 3.81 mm — because dp does not survive the trip through Godot's stretch
## and mm does.
const GESTURE_STRIP_MM: float = 3.81
## The left/right edge swipe (back gesture) claims the same 24 dp off each long end.
## Cheaper to honour than to argue with: nothing in this layout wants those columns.
const EDGE_SWIPE_MM: float = 3.81


## The bottom strip the system may steal a drag from, in logical pixels.
static func gesture_strip(viewport: Vector2, mm_unit: float) -> Rect2:
	var h: float = GESTURE_STRIP_MM / maxf(mm_unit, 0.0001)
	return Rect2(0.0, viewport.y - h, viewport.x, h)


# ═══════════════════════════════════════════════════ 4. PLACING A CONTROL

## Corner-anchored placement, in the same (distance from the side, distance UP from the
## bottom) shape `TouchControls._button_layout()` already speaks — plus the safe-area
## insets, which is the part that was missing.
##
## `corner` is "bl" or "br". Returns the rect in LOGICAL pixels.
static func corner_rect(viewport: Vector2, insets: Vector4, corner: String,
		off: Vector2, size: Vector2) -> Rect2:
	var bottom: float = viewport.y - insets.w
	var y: float = bottom - off.y - size.y
	var x: float = 0.0
	if corner == "br":
		x = (viewport.x - insets.z) - off.x - size.x
	else:
		x = insets.x + off.x
	return Rect2(x, y, size.x, size.y)


## Where spell button `i` sits on the thumb arc, as (from the side, up from the bottom).
##
## ⚠ THE ARC IS SWEPT, NOT HAND-PLACED, so a device pass moves every button coherently
## by changing one radius instead of four offsets. Lives here rather than on
## `TouchControls` so the geometry suite can ask the question without building a pad —
## `TouchControls.spell_button_offset` now forwards to this and stays the public name
## that `tools/slice_test_spell_buttons.gd` already calls.
static func arc_offset(pivot: Vector2, radius: float, angles: Array[float], i: int) -> Vector2:
	if angles.is_empty():
		return pivot
	var a: float = deg_to_rad(angles[clampi(i, 0, angles.size() - 1)])
	return pivot + Vector2(cos(a), sin(a)) * radius


# ═══════════════════════════════════════════════════ 5. JUDGING A LAYOUT

## Do two HIT rectangles overlap? Named rather than inlined because the whole reason
## `tools/slice_test_spell_buttons.gd` exists is that this project draws round buttons
## and taps square ones, and "they look fine" kept being offered as the test.
static func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b)


## Distance from a landscape grip's thumb knuckle to a control's centre, in mm.
## `side` is "l" or "r".
static func thumb_reach_mm(viewport: Vector2, insets: Vector4, mm_unit: float,
		side: String, centre: Vector2) -> float:
	var pivot: Vector2 = thumb_pivot(viewport, insets, mm_unit, side)
	return centre.distance_to(pivot) * mm_unit


static func thumb_pivot(viewport: Vector2, insets: Vector4, mm_unit: float,
		side: String) -> Vector2:
	var inx: float = THUMB_PIVOT_MM.x / maxf(mm_unit, 0.0001)
	var iny: float = THUMB_PIVOT_MM.y / maxf(mm_unit, 0.0001)
	var y: float = viewport.y - insets.w - iny
	if side == "r":
		return Vector2(viewport.x - insets.z - inx, y)
	return Vector2(insets.x + inx, y)


## Is this rect clear of the strip the system gesture owns?
static func clears_gesture_strip(r: Rect2, viewport: Vector2, mm_unit: float) -> bool:
	return not r.intersects(gesture_strip(viewport, mm_unit))


## Is this rect clear of the OS-owned insets on all four sides?
static func inside_safe_area(r: Rect2, viewport: Vector2, insets: Vector4) -> bool:
	var safe := Rect2(insets.x, insets.y,
		viewport.x - insets.x - insets.z, viewport.y - insets.y - insets.w)
	return safe.encloses(r)


# ═══════════════════════════════════════════════════ 6. THE DEVICE TABLE

## Real phones, so the probe reports numbers a person can check against a shop listing
## rather than against an abstraction. `[name, native w, native h (landscape), diagonal
## inches]`. Native size is given LANDSCAPE because `window/handheld/orientation` is
## locked to landscape, so this is the orientation the game will ever see.
##
## Chosen to bracket the range rather than to be exhaustive: the oldest aspect still
## shipping (16:9), the two that dominate current Android (19.5:9, 20:9), and the
## widest a phone goes (21:9) — which is where a corner-anchored layout drifts furthest.
const DEVICES: Array[Dictionary] = [
	{"name": "16:9  1280x720  (budget/older)", "size": Vector2(1280.0, 720.0), "diag": 5.0},
	{"name": "19.5:9 2340x1080 (Pixel-class)", "size": Vector2(2340.0, 1080.0), "diag": 6.1},
	{"name": "20:9  2400x1080 (most Android)", "size": Vector2(2400.0, 1080.0), "diag": 6.5},
	{"name": "21:9  2520x1080 (Xperia-class)", "size": Vector2(2520.0, 1080.0), "diag": 6.5},
]

## A MODELLED cutout inset for the probe, in mm, applied to ONE long end. The real one
## comes from `safe_insets()` on the device; this exists so the geometry can be judged
## against a plausible budget before a phone is in hand.
##
## 8 mm is a punch-hole camera plus its margin — the common case. A wide notch is worse
## and a flat-top phone is zero, so this is the middle of the range it has to survive.
const MODELLED_CUTOUT_MM: float = 8.0


## The insets the probe assumes: a cutout on one long end (which end depends on which
## way the player turned the phone, so both are worth a run), the edge-swipe columns,
## and the bottom home-swipe strip. `cutout_side` is "l", "r" or "" for none.
##
## ⚠ THE BOTTOM ENTRY MUST MATCH WHAT `TouchControls._refresh_insets` ACTUALLY DOES,
## which is `ins.w = max(safe_bottom, gesture_lift)`. It did not, for one commit, and
## the suite caught it: the model said the bottom was free while the runtime was lifting
## the whole cluster by ~21 px, so every measurement taken against the model was of a
## layout the device would never draw. A model that does not mirror the runtime is a
## more expensive way of guessing.
static func modelled_insets(mm_unit: float, cutout_side: String) -> Vector4:
	var edge: float = EDGE_SWIPE_MM / maxf(mm_unit, 0.0001)
	var cut: float = MODELLED_CUTOUT_MM / maxf(mm_unit, 0.0001)
	return Vector4(
		edge + (cut if cutout_side == "l" else 0.0),
		0.0,
		edge + (cut if cutout_side == "r" else 0.0),
		GESTURE_STRIP_MM / maxf(mm_unit, 0.0001))
