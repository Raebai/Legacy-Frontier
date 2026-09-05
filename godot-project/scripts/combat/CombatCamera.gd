extends Camera2D

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
## A Camera2D with trauma-based screenshake (Squirrel Eiserloh model) plus a
## directional "kick" punch. Registered in group "combat_camera".
##
## Trauma model: hits add trauma (clamped <= 1), trauma decays linearly, and
## the shake offset scales with trauma^2 — small hits barely wobble, big hits
## slam. Legacy add_shake(amount) callers are normalized into trauma via
## SHAKE_TO_TRAUMA so Juice.shake_camera and existing call sites keep working.

## Resting framing pulled back from the old tight 2.2 so more of the fight reads
## (maker: "a bit too zoomed in generally"). The player can dial it in Settings
## (GameState.camera_zoom, 1.0 wide .. 2.6 tight); this is the fallback default.
const DEFAULT_ZOOM: Vector2 = Vector2(1.6, 1.6)
const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 2.6

# --- "Fit all fighters" framing (couch-brawler camera; opt-in via set_frame_all).
# Each frame, frame the bounding box of the hero + all live bots and auto-zoom so
# everyone stays on screen. Base design resolution is 640x360 (project stretch).
const FRAME_VIEWPORT: Vector2 = Vector2(640.0, 360.0)
## ══ THE BOTTOM OF THE SCREEN BELONGS TO THE HUD, AND THE CAMERA HAS TO KNOW ═══════
## Maker: *"when the camera zooms out you cant see the character, its hidden under the
## spellboxes"*.
##
## ⚠ NOTHING IN EITHER CAMERA RESERVED A SINGLE PIXEL FOR THE HUD. `FRAME_VIEWPORT`
## above is the FULL base viewport, `fit` divides by all 360 of it, and `_frame_offset`
## targets the geometric centre of the whole frame. Meanwhile `AbilityBar` sits on
## CanvasLayer 60 across the bottom: 14 px margin + 46 px slot + a 9 px class label =
## 69 px of the 360, dead centre-bottom, exactly where a grounded fighter stands.
##
## And the arithmetic is nastier than a near miss. `FRAME_PAD.y` is 140, so the framer
## leaves 70 px between the lowest fighter and the frame edge — against a 69 px bar.
## The bottom fighter lands ON the bar's top edge at every zoom level, and once `fit`
## clamps at `FRAME_ZOOM_MIN` (0.46) the box stops fitting at all and they go fully
## behind it. It was never going to be visible; the margin and the obstruction are the
## same size by coincidence.
##
## ⚠ AND THE FIX IS TWO HALVES — the first alone does nothing. Solving against a
## SHORTER rect only makes the picture smaller; the group still centres on the middle
## of the full frame, which is still behind the bar. The camera also has to move DOWN
## by half the reserve, so the group re-centres inside the band that is actually
## visible (y 0..291) instead of the band the maths thinks it has.
##
## Measured off `AbilityBar`'s own constants rather than eyeballed: BOTTOM_MARGIN 14 +
## SLOT_SIZE 46 + the label's 9 px lift. ⚠ `SLOT_SIZE` is a locked thumb-target
## (D-011) and may not shrink, so the camera is the side that yields.
## ⚠ ASKED, NOT COPIED. This was a hardcoded 69.0 — a second copy of AbilityBar's own
## arithmetic — and it went stale the moment the bar was rescaled for desktop. The bar
## owns its height and publishes it; this is the fallback for a headless run where the
## class is not reachable.
const HUD_RESERVE_FALLBACK: float = 69.0
## Cap on the upward bias applied when the group is too big to fit — as a fraction of
## the usable frame height. Without a cap, a wave spread across a full-size room would
## walk the picture off the top instead of off the bottom, which is the same bug
## wearing a hat.
const OVERFLOW_LIFT_MAX: float = 0.18
## A few px of daylight between the lowest fighter and the top edge of the hotbar.
## With the reserve alone the tightest measured case cleared by 2.8 px — positive, but
## a hairline, and `HERO_FRAME_BIAS` eats most of `FRAME_PAD` at large spreads because
## it drags the framed centre back toward the hero, who is the body ON THE FLOOR.
## A stated margin is better than a coincidence.
const HUD_CLEARANCE: float = 8.0


func _hud_reserve() -> float:
	# ⚠ THE HERO PLATE SITS ABOVE THE HOTBAR AND THE CAMERA HAS TO KNOW. The player's own
	# health moved out of world space into this corner, so the reserved strip grew by 24 px
	# (gap + plate + frame). Without this the camera happily frames two fighters into the
	# band their own health readout occupies.
	return AbilityBar.occupied_height() + HudStyle.HERO_PLATE_GAP + HudStyle.HERO_PLATE_SIZE.y + HudStyle.HERO_PLATE_FRAME * 2.0 + HUD_CLEARANCE


## ══ THE ROOM THE CAMERA IS ALLOWED TO SHOW, AND THE OTHER HALF OF THE BAR BUG ═════
## Maker, twice: *"I dont want the bottom bar blocking the characters when they are on
## the ground floor of the tower"*.
##
## ⚠ `Hero.tscn` SHIPPED WITH `limit_right = 1200, limit_bottom = 680` HARDCODED, and
## nothing ever updated them. Those are the dimensions of the box `Arena.tscn` used to
## hardcode before `LayoutDef.room_size` started driving the geometry — a stale copy of
## a number that moved. Every tower floor since has been framed against the wrong room.
##
## And the failure mode is exactly the report. Godot clamps the camera POSITION to the
## limits and applies `offset` AFTERWARDS, so once the limit binds, the HUD reserve
## cannot move the picture at all — it is added to a position that has already been
## pinned. Measured on the ground floor: the camera sat 104 world px above the hero and
## would not follow him down, which puts a fighter standing on the floor at the bottom
## of the frame with the hotbar drawn over him. No amount of reserve fixes that,
## because the reserve was never the thing holding the camera.
##
## So the limits track the real room, and the BOTTOM one is extended by the reserve
## converted to world units at the current zoom — that band is precisely what the bar
## covers, so the room's floor line lands on the bar's top edge instead of behind it.
## Re-applied every frame because the conversion depends on the live zoom.
var _room_size: Vector2 = Vector2.ZERO


func set_room_bounds(size: Vector2) -> void:
	_room_size = size
	_apply_room_limits()


## Godot's own "no limit" value. Used rather than 0 because 0 IS a meaningful limit.
const LIMIT_OFF: int = 10000000


## ⚠ GODOT'S LIMITS AND THIS FRAMER CANNOT BOTH OWN THE PICTURE, AND THE FRAMER WINS.
##
## `Camera2D` clamps POSITION and adds `offset` AFTERWARDS. `_frame_group_update`
## expresses its entire answer — the group centre, the hero bias, the HUD lift — as
## `offset`. So the limits were clamping the hero's raw position and the framer was
## then dragging the centre straight back outside them: measured on the ground floor,
## a legal position range of [290, 382] resolved to a camera centre of 277. The limits
## were not protecting the shot, they were adding an arbitrary bias to it, and at the
## wide end they asked for a centre at least half a view below the top AND at most half
## a view above the bottom — an empty interval, which Godot resolves by satisfying
## neither.
##
## So the engine's limits come OFF, and "stay inside the room" is solved in the same
## place and the same coordinate space as everything else the framer decides.
func _apply_room_limits() -> void:
	limit_left = -LIMIT_OFF
	limit_top = -LIMIT_OFF
	limit_right = LIMIT_OFF
	limit_bottom = LIMIT_OFF


## Hold the frame inside the room — bottom edge extended by the band the hotbar hides,
## since that band is not part of the picture anyone can see. An axis whose view is
## WIDER than the room is skipped rather than clamped: there is nothing to protect when
## the room does not fill the frame, and clamping anyway is what produced the empty
## interval above.
func _clamp_centre_to_room(centre: Vector2, z: float, view: Vector2) -> Vector2:
	if _room_size.x <= 1.0 or _room_size.y <= 1.0:
		return centre
	var half: Vector2 = view / (2.0 * maxf(z, 0.01))
	var out: Vector2 = centre
	if _room_size.x > view.x / maxf(z, 0.01):
		out.x = clampf(out.x, half.x, _room_size.x - half.x)
	var bottom: float = _room_size.y + _hud_reserve() / maxf(z, 0.01)
	if bottom > view.y / maxf(z, 0.01):
		out.y = clampf(out.y, half.y, bottom - half.y)
	return out


## ⚠ THIS IS ALSO THE TIGHTEST THE CAMERA EVER GOES. The pad is added to the FIGHTER
## bounding box, so when two bodies are on top of each other the framing is decided
## almost entirely by this number. Cutting it to buy a bigger arena would have bought
## the space by zooming further IN, which is the complaint already on record ("a bit
## too zoomed in generally") arriving from the other direction. Left alone on purpose.
## ⚠ TIGHTENED 300x220 -> 168x140, AND IT BUYS THE ZOOM FLOOR. Maker: "the map is cool
## but the camera should be more focussed on the player themselves, not too zoomed out."
##
## The arithmetic is the whole reason this is the knob and `FRAME_ZOOM_MIN` is not.
## The biggest room that fits on one screen is `640 / zoom - FRAME_PAD.x`, and the
## authored rooms reach 1210 px wide — so at the old pad, holding those rooms REQUIRES
## `zoom <= 640 / (1210 + 300) = 0.424`. There was no room to zoom in at all without
## shrinking the map, which the maker likes.
##
## Cutting the pad moves the constraint instead of fighting it: at 180 the same rooms
## need only `zoom <= 640 / (1220 + 168) = 0.461`, so the widest shot comes in ~10%
## with every floor still fitting.
##
## WHAT IT COSTS, plainly: at FULL fighter spread the group sits closer to the screen
## edge — 168 px of margin instead of 300. That is the trade, and it is the honest one
## to make here, because the alternative is a smaller map.
const FRAME_PAD: Vector2 = Vector2(168.0, 140.0)
## How far back the framing may pull. THIS IS THE ARENA SIZE CAP, not just a camera
## knob: the biggest room that can fit on one screen is
## `FRAME_VIEWPORT / FRAME_ZOOM_MIN - FRAME_PAD`, and `FloorGen.MAX_ROOM` is required
## by `slice_test_floorgen` to stay inside it.
##
## ⚠ 0.5 -> 0.42 BECAUSE THE MAKER SAID THE MAP WAS TOO SMALL, TWICE. At 0.5 the
## ceiling was 980x500 and no amount of work inside FloorGen could raise it. At 0.42
## it is 1523x857, which is what lets the tower rooms grow to 1220x560.
##
## WHAT IT COSTS, stated plainly rather than discovered in play: at FULL fighter
## spread the picture is ~16% smaller than it used to be — a 31 px hero draws at
## ~13 viewport px instead of ~15.5. It costs nothing at any other moment, because
## this is a FLOOR on the zoom and the camera only reaches it when the group is
## genuinely strung out across the whole room; close-quarters framing is set by
## FRAME_PAD and ZOOM_MAX and is byte-identical to before. If the wide shot turns out
## to read as "tiny ants", this number is the one to walk back — and the room sizes in
## `FloorGen.MAX_ROOM` must come back with it or the arena stops fitting on one screen.
## Raised with the pad above — 0.42 -> 0.46, the tightest the authored rooms allow.
const FRAME_ZOOM_MIN: float = 0.46
const FRAME_SPEED: float = 3.5     # ease rate toward the framed centroid (position)
# ASYMMETRIC ZOOM EASE — the framing camera as a PRESSURE instrument.
# Waves now open with a vanguard that lands as a GROUP, so the framed box can
# double in one frame. At a single symmetric 3.5 rate the camera spent the first
# half-second of every wave catching up, with the arrivals clipping the edge of
# the screen exactly when you most needed to see them. Widening is therefore
# urgent and tightening is lazy: the room OPENS to receive a wave, and closes
# back slowly as you thin it out, so the frame never breathes in and out around a
# straggler wandering across the arena.
const FRAME_ZOOM_SPEED_OUT: float = 7.0
const FRAME_ZOOM_SPEED_IN: float = 2.0
# How far the framed center leans from the HERO (0) toward the geometric centroid
# of all fighters (1). 0.55 keeps the player weighted-center while bots still pull.
const HERO_FRAME_BIAS: float = 0.55

# --- Shake tuning ---
const MAX_OFFSET: Vector2 = Vector2(28.0, 20.0)  # px at full (1.0) trauma
## ⚠ 1.4 -> 2.2. Trauma is ADDITIVE per hit and clamps at 1.0, so during a busy
## exchange it was pinned at the ceiling and every consumer of it — shake here,
## aberration and the micro-warp in the shader — sat at maximum continuously. Bleeding
## it off faster means a single heavy hit still reads at full weight while a rapid
## sequence stops summing into one permanent shudder. One number, whole picture.
const TRAUMA_DECAY: float = 2.2  # trauma units shed per second
# add_shake amount -> trauma. With MAX_OFFSET above: cast (2) is barely a
# tremble, melee (4-7) a firm bump, blast (12) a slam, and stacked hits
# accumulate toward the full-trauma ceiling.
const SHAKE_TO_TRAUMA: float = 1.0 / 16.0
const NOISE_SPEED: float = 28.0  # wobble frequency of the pseudo-noise

# --- Kick tuning ---
const KICK_RETURN_SPEED: float = 10.0  # how fast the punch eases back
const KICK_MAX: float = 26.0  # px cap on stacked kicks

# --- Lookahead tuning (GMTK: camera drifts toward where the hero AIMS) ---
# Default trimmed 22 -> 8: at 2.2x zoom the old 22px drift read as the screen
# lurching every time you changed direction ("shake when I move"). Live-tunable
# via Tuning.lookahead_dist. Lookahead now tracks aim, not movement, so strafing
# doesn't jerk the frame.
const LOOKAHEAD_DIST: float = 8.0
const LOOKAHEAD_SPEED: float = 4.0  # ease rate toward the aim target

var _trauma: float = 0.0
var _noise_t: float = 0.0
var _kick_offset: Vector2 = Vector2.ZERO
var _lookahead: Vector2 = Vector2.ZERO
var _tuning: Node = null  # cached /root/Tuning (null in headless -> const fallbacks)

# --- Punch-zoom state (quick zoom-IN kick that eases back to base) ---
var _zoom_base: Vector2 = DEFAULT_ZOOM
var _zoom_timer: float = 0.0
var _zoom_duration: float = 0.0
var _zoom_amount: float = 0.0
# --- Pull-zoom state (temporary zoom-OUT that eases out, HOLDS, eases back) so a
# big spell reveals the whole play — the maker's "zoom out on meteor" ask. The
# envelope runs ease_in -> hold -> ease_out; composed multiplicatively with the
# punch so a blast can punch-in AND the ult pulls-out without fighting. ---
var _pull_amount: float = 0.0    # fraction to widen (0.16 = show ~16% more)
var _pull_ein: float = 0.12
var _pull_hold: float = 0.5
var _pull_eout: float = 0.55
var _pull_elapsed: float = 0.0
var _pull_active: bool = false

# --- Fit-all framing state ---
var _frame_all: bool = false
var _frame_offset: Vector2 = Vector2.ZERO


## Enable the couch-brawler "keep everyone on screen" camera (practice arena).
func set_frame_all(enabled: bool) -> void:
	_frame_all = enabled


func _ready() -> void:
	add_to_group("combat_camera")
	_tuning = get_node_or_null("/root/Tuning")
	# Resting zoom comes from the player's saved preference (Settings), falling
	# back to DEFAULT_ZOOM. _zoom_base is captured so punch/pull compose onto it.
	var z: float = DEFAULT_ZOOM.x
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var v: Variant = gs.get("camera_zoom")
		if v != null:
			z = clampf(float(v), ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	_zoom_base = zoom


## Set the resting zoom live from the Settings slider: update the base (and the
## visible zoom when no transient effect is running) and persist to GameState so
## the choice survives scene changes.
func set_base_zoom(z: float) -> void:
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_zoom_base = Vector2(z, z)
	if _zoom_timer <= 0.0 and not _pull_active:
		zoom = _zoom_base
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("camera_zoom", z)


## Live feel value from the Tuning autoload (falls back to the const default
## when the autoload/field is absent, e.g. in headless tests).
func _tune(key: String, fallback: float) -> float:
	if _tuning != null and _tuning.cfg != null:
		var v: Variant = _tuning.cfg.get(key)
		if v != null:
			return float(v)
	return fallback


## Add shake energy directly in trauma units (0..1).
func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


## Current trauma (0..1). Read by PostProcess so the screen-space aberration
## tracks the exact same energy that drives the shake — hits smear the picture.
func trauma() -> float:
	return _trauma


## Legacy pixel-ish API (existing callers pass ~2..12); routed into trauma.
func add_shake(amount: float) -> void:
	add_trauma(amount * SHAKE_TO_TRAUMA)


## Directional camera punch: instant offset along `dir`, eases back to zero.
func kick(dir: Vector2, amount: float) -> void:
	_kick_offset = (_kick_offset + dir.normalized() * amount).limit_length(KICK_MAX)


## Capture the resting zoom as the base ONLY when no zoom effect is running, so
## punch + pull compose onto the true resting zoom instead of ratcheting off a
## mid-effect value (demo harness + game use different resting zooms).
func _capture_base_if_idle() -> void:
	if _zoom_timer <= 0.0 and not _pull_active:
		_zoom_base = zoom


## Quick zoom-IN kick that eases back. Re-arming mid-punch keeps the base + just
## resets the timer/amount so stacked blasts never ratchet the zoom.
func zoom_punch(amount: float = 0.1, duration: float = 0.18) -> void:
	if duration <= 0.0:
		return
	_capture_base_if_idle()
	_zoom_amount = amount
	_zoom_duration = duration
	_zoom_timer = duration


## Temporary zoom-OUT that eases wide, HOLDS, then eases back — the "camera pulls
## back to show the spell" beat for big spectacles (meteor / divine ray / ult).
## amount is the widen fraction (0.16 shows ~16% more). Re-arming restarts the
## envelope; the wider of two overlapping pulls wins via max on amount.
func zoom_pull(amount: float = 0.16, hold: float = 0.5, ease_in: float = 0.12, ease_out: float = 0.55) -> void:
	if amount <= 0.0:
		return
	_capture_base_if_idle()
	_pull_amount = maxf(_pull_amount, amount) if _pull_active else amount
	_pull_ein = maxf(ease_in, 0.001)
	_pull_hold = maxf(hold, 0.0)
	_pull_eout = maxf(ease_out, 0.001)
	_pull_elapsed = 0.0
	_pull_active = true


## Current pull widen factor (0..1 of _pull_amount) across the ease/hold/ease
## envelope. Clears _pull_active when the envelope completes.
func _pull_progress(delta: float) -> float:
	if not _pull_active:
		return 0.0
	_pull_elapsed += delta
	var total: float = _pull_ein + _pull_hold + _pull_eout
	if _pull_elapsed >= total:
		_pull_active = false
		return 0.0
	if _pull_elapsed < _pull_ein:
		return smoothstep(0.0, 1.0, _pull_elapsed / _pull_ein)
	if _pull_elapsed < _pull_ein + _pull_hold:
		return 1.0
	var t: float = (_pull_elapsed - _pull_ein - _pull_hold) / _pull_eout
	return smoothstep(1.0, 0.0, t)


## Fit-all: frame the hero + all live bots, easing the base zoom + a centering
## offset so every fighter stays on screen. Drives _zoom_base (punch/pull compose
## on top) and _frame_offset (added to the final camera offset).
func _frame_group_update(delta: float) -> void:
	var p: Node = get_parent()
	if p == null or not (p is Node2D):
		return
	var hero_pos: Vector2 = (p as Node2D).global_position
	var mn: Vector2 = hero_pos
	var mx: Vector2 = hero_pos
	var count: int = 1
	# ⚠ THE OTHER PLAYERS PULL THE FRAME TOO. This solve used to fold in the "enemy"
	# group and nothing else, which was complete while there was only ever one hero: the
	# camera hangs off its own hero, so that hero was the frame by construction. On a
	# couch that is exactly how player two walks off the side of the screen and stays
	# there. Heroes are folded in FIRST, on the same footing as enemies.
	#
	# ⚠ SOLO IS UNCHANGED, and that is checked rather than hoped: with one hero the
	# loop body never runs, `focus` is `hero_pos` to the bit, and `count` stays 1 so the
	# empty-room early-return below still fires exactly when it used to.
	var focus_sum: Vector2 = hero_pos
	var focus_n: int = 1
	for h: Node in get_tree().get_nodes_in_group("hero"):
		if h == p or not is_instance_valid(h) or not (h is Node2D):
			continue
		var hp: Vector2 = (h as Node2D).global_position
		mn = mn.min(hp)
		mx = mx.max(hp)
		count += 1
		focus_sum += hp
		focus_n += 1
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if e is Node2D and is_instance_valid(e):
			var q: Vector2 = (e as Node2D).global_position
			mn = mn.min(q)
			mx = mx.max(q)
			count += 1
	var ease: float = minf(FRAME_SPEED * delta, 1.0)
	if count <= 1:
		# Only the hero left — ease back to the resting default. Tightening is the
		# LAZY direction, so this uses the slow rate: an emptied room settles in
		# rather than snapping shut the instant the last body drops.
		_frame_offset = _frame_offset.lerp(Vector2.ZERO, ease)
		_zoom_base = _zoom_base.lerp(DEFAULT_ZOOM, minf(FRAME_ZOOM_SPEED_IN * delta, 1.0))
		return
	# Bias the framed center toward the HERO (maker: "keep the PLAYER the focus").
	# The bots still pull the frame + drive the auto-zoom, but the hero is weighted
	# ~55% toward center so you never lose track of who you are.
	var geo_center: Vector2 = (mn + mx) * 0.5
	# The bias pulls toward THE PLAYERS' midpoint, not toward this camera's own hero —
	# weighting one of two co-op players as "the" focus would shove the other toward the
	# edge on every spread. With one player the midpoint IS that player.
	var focus: Vector2 = focus_sum / float(focus_n)
	var centroid: Vector2 = focus.lerp(geo_center, HERO_FRAME_BIAS)
	var span: Vector2 = (mx - mn) + FRAME_PAD
	# ⚠ THE LIVE VIEWPORT, NOT THE HARDCODED ONE. `FRAME_VIEWPORT` is the 640x360 base,
	# but the project stretches `canvas_items`/`expand`, which means a non-16:9 window
	# GROWS the logical viewport rather than letterboxing it — 853x360 on a 21:9
	# fullscreen. Solving against a constant there frames for a screen shape the player
	# is not looking at. Falls back to the constant when there is no viewport (headless).
	var view: Vector2 = FRAME_VIEWPORT
	var vp: Viewport = get_viewport()
	if vp != null:
		var live: Vector2 = vp.get_visible_rect().size
		if live.x > 1.0 and live.y > 1.0:
			view = live
	# HALF the frame is solved against a SHORTER rect — the part the HUD does not cover.
	var reserve: float = _hud_reserve()
	var usable_h: float = maxf(view.y - reserve, 1.0)
	var fit: float = minf(view.x / maxf(span.x, 1.0), usable_h / maxf(span.y, 1.0))
	fit = clampf(fit, FRAME_ZOOM_MIN, ZOOM_MAX)
	# ...and the OTHER half moves the camera DOWN, so the group rises out of the bar.
	#
	# ⚠ THE SIGN, BECAUSE IT WAS WRONG AND IT MADE THE BUG WORSE, NOT BETTER.
	# `Camera2D` renders about `position + offset`, so a body's screen y is
	#
	#     view.y * 0.5 + (body.y - cam_center.y) * zoom,  cam_center.y = centroid.y + shift
	#
	# A NEGATIVE shift lifts the camera, which pushes the WORLD DOWN the screen — the
	# opposite of what a bottom reserve is for. This shipped as `-hud_shift`, against
	# the paragraph directly above it, so the "fix" moved every fighter half a
	# bar-height FURTHER under the bar and the maker reported the bar still blocking
	# them.
	#
	# ⚠ AND IT IS SOLVED, NOT TAXED. The first version lifted by half the reserve on
	# every frame of every fight. That is a flat 12% of the picture surrendered
	# whether or not anybody is near the bar — and it is measurably the WRONG amount:
	# widening it made the tightest cases worse, because `HERO_FRAME_BIAS` drags the
	# framed centre back toward the hero, who is the body standing ON THE FLOOR, and a
	# blanket constant cannot know that. So ask the real question instead — where does
	# the LOWEST body actually land — and lift by exactly the shortfall, which is zero
	# most of the time and reclaims the band the bar is not using.
	var bar_top: float = view.y - reserve
	var lowest: float = mx.y
	# A body's screen y is `view.y*0.5 + (body.y - centre.y) * zoom`, so keeping the
	# LOWEST body off the hotbar means pushing the centre DOWN by the shortfall.
	var need: float = (lowest - centroid.y) - (bar_top - view.y * 0.5) / maxf(fit, 0.01)
	# Capped so a wave too big to fit cannot walk the picture off the TOP instead —
	# which is the same bug wearing a hat.
	var lift_cap: float = (reserve + usable_h * OVERFLOW_LIFT_MAX) / maxf(fit, 0.01)
	var hud_shift: float = clampf(need, 0.0, lift_cap)
	var centre: Vector2 = _clamp_centre_to_room(
		centroid + Vector2(0.0, hud_shift), fit, view)
	_frame_offset = _frame_offset.lerp(centre - hero_pos, ease)
	# A LOWER zoom is a WIDER view, so "fit < base" means the group just grew and
	# the camera has to open up NOW; the other direction can take its time.
	var zoom_rate: float = FRAME_ZOOM_SPEED_OUT if fit < _zoom_base.x else FRAME_ZOOM_SPEED_IN
	_zoom_base = _zoom_base.lerp(Vector2(fit, fit), minf(zoom_rate * delta, 1.0))


func _process(delta: float) -> void:
	if _frame_all:
		_frame_group_update(delta)
	# --- Compose zoom: resting base * punch-IN factor * pull-OUT factor. When both
	# effects are idle, restore the base exactly. ---
	var punch_factor: float = 1.0
	if _zoom_timer > 0.0:
		_zoom_timer = maxf(_zoom_timer - delta, 0.0)
		if _zoom_timer > 0.0:
			punch_factor = 1.0 + _zoom_amount * (_zoom_timer / _zoom_duration)
	var pull_p: float = _pull_progress(delta)
	var pull_factor: float = 1.0 - _pull_amount * pull_p  # < 1 widens the view
	if _zoom_timer > 0.0 or _pull_active:
		zoom = _zoom_base * punch_factor * pull_factor
	elif punch_factor == 1.0 and pull_p == 0.0:
		zoom = _zoom_base  # restore exactly, once both effects finish
	# --- Lookahead: gentle peek toward where the hero AIMS (falls back to
	# facing). Tracking aim not movement means strafing doesn't jerk the frame. ---
	var lookahead_target: Vector2 = Vector2.ZERO
	var p: Node = get_parent()
	if p != null:
		var dir_value: Variant = null
		if "_aim_dir" in p:
			dir_value = p.get("_aim_dir")
		elif "facing" in p:
			dir_value = p.get("facing")
		if dir_value is Vector2 and (dir_value as Vector2) != Vector2.ZERO:
			lookahead_target = (dir_value as Vector2).normalized() * _tune("lookahead_dist", LOOKAHEAD_DIST)
	_lookahead = _lookahead.lerp(lookahead_target, minf(LOOKAHEAD_SPEED * delta, 1.0))
	# --- Trauma shake + kick, composed with the lookahead drift. ---
	_noise_t += delta * NOISE_SPEED
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_kick_offset = _kick_offset.lerp(Vector2.ZERO, minf(KICK_RETURN_SPEED * delta, 1.0))
	var shake: float = _trauma * _trauma * _tune("shake_scale", 1.0)
	var shake_offset: Vector2 = Vector2.ZERO
	if shake > 0.0 or _kick_offset != Vector2.ZERO:
		# Two incommensurate sines per axis ~ cheap smooth noise (reads as a
		# rumble that settles, not per-frame random static).
		var nx: float = sin(_noise_t) * 0.6 + sin(_noise_t * 2.7 + 1.3) * 0.4
		var ny: float = cos(_noise_t * 1.3 + 0.9) * 0.6 + sin(_noise_t * 3.4) * 0.4
		shake_offset = _kick_offset + Vector2(MAX_OFFSET.x * shake * nx, MAX_OFFSET.y * shake * ny)
	offset = _lookahead + shake_offset + _frame_offset
	# The bottom limit is a function of the zoom that was just composed, so it is
	# refreshed here rather than once when the floor is built.
	_apply_room_limits()
