extends Camera2D
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
## ⚠ THIS IS ALSO THE TIGHTEST THE CAMERA EVER GOES. The pad is added to the FIGHTER
## bounding box, so when two bodies are on top of each other the framing is decided
## almost entirely by this number. Cutting it to buy a bigger arena would have bought
## the space by zooming further IN, which is the complaint already on record ("a bit
## too zoomed in generally") arriving from the other direction. Left alone on purpose.
const FRAME_PAD: Vector2 = Vector2(300.0, 220.0)  # breathing room around the group
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
const FRAME_ZOOM_MIN: float = 0.42
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
const TRAUMA_DECAY: float = 1.4  # trauma units shed per second
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
	var centroid: Vector2 = hero_pos.lerp(geo_center, HERO_FRAME_BIAS)
	var span: Vector2 = (mx - mn) + FRAME_PAD
	var fit: float = minf(FRAME_VIEWPORT.x / maxf(span.x, 1.0), FRAME_VIEWPORT.y / maxf(span.y, 1.0))
	fit = clampf(fit, FRAME_ZOOM_MIN, ZOOM_MAX)
	_frame_offset = _frame_offset.lerp(centroid - hero_pos, ease)
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
