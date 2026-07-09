extends Camera2D
## A Camera2D with trauma-based screenshake (Squirrel Eiserloh model) plus a
## directional "kick" punch. Registered in group "combat_camera".
##
## Trauma model: hits add trauma (clamped <= 1), trauma decays linearly, and
## the shake offset scales with trauma^2 — small hits barely wobble, big hits
## slam. Legacy add_shake(amount) callers are normalized into trauma via
## SHAKE_TO_TRAUMA so Juice.shake_camera and existing call sites keep working.

## Tight Stick Fight-style framing — the ~22px figures fill the screen.
const DEFAULT_ZOOM: Vector2 = Vector2(2.2, 2.2)

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

# --- Lookahead tuning (GMTK: camera drifts toward where the hero faces) ---
const LOOKAHEAD_DIST: float = 22.0  # px of drift at full facing
const LOOKAHEAD_SPEED: float = 4.0  # ease rate toward the facing target

var _trauma: float = 0.0
var _noise_t: float = 0.0
var _kick_offset: Vector2 = Vector2.ZERO
var _lookahead: Vector2 = Vector2.ZERO

# --- Punch-zoom state (quick zoom-in kick that eases back to base) ---
var _zoom_base: Vector2 = DEFAULT_ZOOM
var _zoom_timer: float = 0.0
var _zoom_duration: float = 0.0
var _zoom_amount: float = 0.0


func _ready() -> void:
	add_to_group("combat_camera")
	zoom = DEFAULT_ZOOM


## Add shake energy directly in trauma units (0..1).
func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


## Legacy pixel-ish API (existing callers pass ~2..12); routed into trauma.
func add_shake(amount: float) -> void:
	add_trauma(amount * SHAKE_TO_TRAUMA)


## Directional camera punch: instant offset along `dir`, eases back to zero.
func kick(dir: Vector2, amount: float) -> void:
	_kick_offset = (_kick_offset + dir.normalized() * amount).limit_length(KICK_MAX)


## Quick zoom-IN kick that eases back to whatever the zoom was at call time.
## Base is captured at call time (demo harness and game use different zooms);
## a punch landing mid-punch keeps the original un-punched base and just
## re-arms the timer/amount so stacked blasts never ratchet the zoom.
func zoom_punch(amount: float = 0.1, duration: float = 0.18) -> void:
	if duration <= 0.0:
		return
	if _zoom_timer <= 0.0:
		_zoom_base = zoom
	_zoom_amount = amount
	_zoom_duration = duration
	_zoom_timer = duration


func _process(delta: float) -> void:
	# --- Punch-zoom: quick zoom-in that eases back (e runs 1 -> 0). ---
	if _zoom_timer > 0.0:
		_zoom_timer = maxf(_zoom_timer - delta, 0.0)
		if _zoom_timer <= 0.0:
			zoom = _zoom_base  # restore exactly, once
		else:
			var e: float = _zoom_timer / _zoom_duration
			zoom = _zoom_base * (1.0 + _zoom_amount * e)
	# --- Lookahead: drift toward where the hero is facing. ---
	var lookahead_target: Vector2 = Vector2.ZERO
	var p: Node = get_parent()
	if p != null and "facing" in p:
		var facing_value: Variant = p.get("facing")
		if facing_value is Vector2:
			lookahead_target = (facing_value as Vector2).normalized() * LOOKAHEAD_DIST
	_lookahead = _lookahead.lerp(lookahead_target, minf(LOOKAHEAD_SPEED * delta, 1.0))
	# --- Trauma shake + kick, composed with the lookahead drift. ---
	_noise_t += delta * NOISE_SPEED
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_kick_offset = _kick_offset.lerp(Vector2.ZERO, minf(KICK_RETURN_SPEED * delta, 1.0))
	var shake: float = _trauma * _trauma
	var shake_offset: Vector2 = Vector2.ZERO
	if shake > 0.0 or _kick_offset != Vector2.ZERO:
		# Two incommensurate sines per axis ~ cheap smooth noise (reads as a
		# rumble that settles, not per-frame random static).
		var nx: float = sin(_noise_t) * 0.6 + sin(_noise_t * 2.7 + 1.3) * 0.4
		var ny: float = cos(_noise_t * 1.3 + 0.9) * 0.6 + sin(_noise_t * 3.4) * 0.4
		shake_offset = _kick_offset + Vector2(MAX_OFFSET.x * shake * nx, MAX_OFFSET.y * shake * ny)
	offset = _lookahead + shake_offset
