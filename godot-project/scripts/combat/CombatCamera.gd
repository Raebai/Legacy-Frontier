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

var _trauma: float = 0.0
var _noise_t: float = 0.0
var _kick_offset: Vector2 = Vector2.ZERO


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


func _process(delta: float) -> void:
	_noise_t += delta * NOISE_SPEED
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_kick_offset = _kick_offset.lerp(Vector2.ZERO, minf(KICK_RETURN_SPEED * delta, 1.0))
	var shake: float = _trauma * _trauma
	if shake <= 0.0 and _kick_offset == Vector2.ZERO:
		offset = Vector2.ZERO
		return
	# Two incommensurate sines per axis ~ cheap smooth noise (reads as a
	# rumble that settles, not per-frame random static).
	var nx: float = sin(_noise_t) * 0.6 + sin(_noise_t * 2.7 + 1.3) * 0.4
	var ny: float = cos(_noise_t * 1.3 + 0.9) * 0.6 + sin(_noise_t * 3.4) * 0.4
	offset = _kick_offset + Vector2(MAX_OFFSET.x * shake * nx, MAX_OFFSET.y * shake * ny)
