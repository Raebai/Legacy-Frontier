class_name PostProcess
extends Node
## Reactive screen-space grade ("the look"). Owns a full-screen ColorRect + the
## post_process.gdshader on a CanvasLayer above the world (below the HUD), and
## feeds the shader live uniforms each frame so the picture REACTS to gameplay:
## chromatic aberration tracks the camera trauma (hits smear the screen), a
## shockwave ring fires on epic moments, and heat-haze pulses on fire beats.
## Cosmetic only — no gameplay logic. Built in code, mirroring Atmosphere.add_glow.
##
## Wiring: PostProcess.add(arena) once per combat arena. The static pokes
## (pulse_heat / shock / set_theme) find the node via the "post_process" group and
## no-op when it's absent (e.g. the calm hub), so call sites never need a guard.

const SHADER_PATH: String = "res://scenes/combat/post_process.gdshader"

# Reaction tuning.
const HEAT_DECAY: float = 1.6          # heat units shed per second
const SHOCK_DURATION: float = 0.85     # seconds a ripple lives
const SHOCK_BASE_AMP: float = 0.012
## The least screen distortion a saturated fight keeps. Not zero: the grade going
## completely flat mid-fight would read as the effect breaking rather than as calm.
## `austerity()` bottoms out at 0.25, so this only bites at its lowest step.
const CLARITY_FLOOR: float = 0.35
## Concurrent spectacles at or below which the grade is untouched. The measured median
## fight sits here, so a normal exchange looks exactly as it always did.
const CLARITY_FULL_AT: float = 2.0
## ...and where the grade bottoms out. Just past the measured peak of 5.
const CLARITY_FLOOR_AT: float = 6.0    # UV displacement at full strength

var _mat: ShaderMaterial
var _rect: ColorRect
var _heat: float = 0.0
var _shock_age: float = -1.0           # <0 = no active ripple
var _shock_amp: float = 0.0
var _shock_center: Vector2 = Vector2(0.5, 0.5)


## Idempotent: add one PostProcess under `parent` (a combat arena). Safe to call
## once per arena _ready; a second call is a no-op.
static func add(parent: Node) -> void:
	if parent == null:
		return
	for c: Node in parent.get_children():
		if c is PostProcess:
			return
	parent.add_child(PostProcess.new())


func _ready() -> void:
	add_to_group("post_process")
	var layer := CanvasLayer.new()
	layer.layer = 8  # above world (0) + atmosphere vignette (1), below HUD (50/60/100)
	add_child(layer)
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat touch/click
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_rect.material = _mat
	layer.add_child(_rect)


func _process(delta: float) -> void:
	# Live enable toggle (accessibility / low-end): hidden = zero cost.
	var on: bool = _enabled()
	_rect.visible = on
	if not on:
		return
	# ══ THE PICTURE CALMS DOWN AS THE FIGHT GETS BUSY ══════════════════════════
	# Maker: *"find a way to still make it feel a little less crowded and crazy like
	# mid way through the fight or at least clearer to what is going on"*.
	#
	# ⚠ THIS WAS A COMPOUNDING LOOP AND IT RAN THE WRONG WAY. Aberration, the 40 Hz
	# micro-warp below it in the shader, and the camera shake are all pure functions of
	# ONE number — `CombatCamera.trauma()` — which accumulates additively per hit and
	# clamps at 1.0. So the more was happening, the harder the screen was distorted,
	# and mid-fight (the exact moment the maker named) all three sat pinned at maximum
	# on top of the busiest picture. The presentation was loudest precisely when the
	# read was hardest.
	#
	# ⚠ AND THE PROJECT ALREADY HAD THE ANSWER, UNPLUGGED. `SpellReactor.austerity()`
	# returns 1.0 / 0.75 / 0.5 / 0.25 as live spectacles go over budget, and it already
	# thins particles, debris, decals and swing arcs. The screen-space and camera layers
	# never asked it — `PostProcess`, `CombatCamera` and `Juice` contained no call to it
	# at all. Feeding it in here inverts the loop: a quiet exchange keeps the full
	# grade, and a screen with five spectacles on it stops shouting over them.
	#
	# It scales the trauma the SHADER sees only. The camera's own trauma is untouched,
	# so hit weight, decay and every other consumer read exactly what they did before.
	_mat.set_shader_parameter(&"trauma", _camera_trauma() * _clarity())
	# Heat-haze decays back to calm.
	if _heat > 0.0:
		_heat = maxf(_heat - HEAT_DECAY * delta, 0.0)
		_mat.set_shader_parameter(&"heat", _heat)
	# Shockwave ring advances + fades.
	if _shock_age >= 0.0:
		_shock_age += delta
		var k: float = 1.0 - clampf(_shock_age / SHOCK_DURATION, 0.0, 1.0)
		_shock_amp = SHOCK_BASE_AMP * k * k  # ease-out fade
		_mat.set_shader_parameter(&"shock", Vector3(_shock_center.x, _shock_center.y, _shock_age))
		_mat.set_shader_parameter(&"shock_amp", _shock_amp)
		if _shock_age >= SHOCK_DURATION:
			_shock_age = -1.0
			_shock_amp = 0.0
			_mat.set_shader_parameter(&"shock_amp", 0.0)



## How much of the screen-space distortion survives, given how much is already on
## screen. 1.0 when the stage is calm, down to CLARITY_FLOOR when it is busy.
##
## ⚠ THIS USED TO READ `austerity()` AND THAT WAS DEAD CODE. Measured over a real bot
## fight (`tools/probe_fight_density.gd`, 100 samples): live spectacles run at a MEAN
## OF 1.9 AND PEAK AT 5, against a VFX budget of 8. `austerity()` only leaves 1.0 once
## the budget is EXCEEDED, so it returned 1.0 on every single sample and the calm-down
## never engaged once. The idea was right and the signal was wrong — that budget exists
## to protect frame rate, and a fight can be perfectly unreadable while comfortably
## inside it.
##
## So this reads the census directly against its own thresholds, chosen from the
## measurement: full grade at or below 2 concurrent spectacles (which is the median
## fight), ramping to the floor by 6 (just past the observed peak). It now moves during
## exactly the moments the maker described and is flat the rest of the time.
##
## Degrades to 1.0 if the reactor autoload is absent, which is what a headless suite
## sees.
func _clarity() -> float:
	var reactor: Node = get_node_or_null(^"/root/SpellReactor")
	if reactor == null or not reactor.has_method("spectacle_count"):
		return 1.0
	var live: float = float(reactor.call("spectacle_count"))
	if live <= CLARITY_FULL_AT:
		return 1.0
	var t: float = (live - CLARITY_FULL_AT) / maxf(CLARITY_FLOOR_AT - CLARITY_FULL_AT, 1.0)
	return lerpf(1.0, CLARITY_FLOOR, clampf(t, 0.0, 1.0))

func _camera_trauma() -> float:
	var cam: Node = get_tree().get_first_node_in_group("combat_camera")
	if cam != null and cam.has_method("trauma"):
		return float(cam.trauma())
	return 0.0


func _begin_shock(strength: float, center: Vector2) -> void:
	_shock_center = center
	_shock_age = 0.0
	_shock_amp = SHOCK_BASE_AMP * clampf(strength, 0.0, 2.0)


func _bump_heat(amount: float) -> void:
	_heat = clampf(_heat + amount, 0.0, 1.0)


func _apply_theme(tint: Color) -> void:
	if _mat == null:
		return
	# Re-tint the frame per floor band: cool the vignette + shadows toward the theme.
	_mat.set_shader_parameter(&"vignette_tint", Vector3(tint.r * 0.14, tint.g * 0.14, tint.b * 0.2 + 0.02))
	_mat.set_shader_parameter(&"shadow_tint", Vector3(tint.r * 0.10, tint.g * 0.10, tint.b * 0.16 + 0.02))


func _enabled() -> bool:
	# MOBILE: off by default, and this is the biggest single renderer saving in the
	# game. post_process.gdshader does 3 `hint_screen_texture` fetches — one of them
	# `filter_linear_mipmap`, which forces a full mipmap CHAIN to be generated from
	# the framebuffer every frame — plus ~5 transcendentals and 3 `pow` per pixel.
	# On a tile GPU the mipmap generation alone is a per-frame resolve + downsample
	# pyramid over the whole screen. Hidden = genuinely zero cost (see _process),
	# so this gate is the whole optimisation.
	#
	# A mobile player on a strong phone can still have it: set graphics_quality to
	# HIGH. That is why this is a quality dial and not an `OS.has_feature` test.
	if not TuningConfig.screen_shaders_allowed():
		return false
	var t: Node = get_node_or_null(^"/root/Tuning")
	if t != null and t.get(&"cfg") != null:
		var v: Variant = t.cfg.get(&"post_process_enabled")
		return v == null or bool(v)
	return true


# ------------------------------------------------------------ static pokes
## Find the active grade (group "post_process"). null in the hub / headless tests
## with no arena -> every poke below is a silent no-op (call sites stay guard-free).
static func _find() -> PostProcess:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("post_process") as PostProcess


## Fire beat: pulse the heat-haze (scaled by the effect's size).
static func pulse_heat(amount: float) -> void:
	var pp: PostProcess = _find()
	if pp != null:
		pp._bump_heat(amount)


## Epic moment / big impact: fire an expanding shockwave ripple. `center` is a
## screen UV (default the middle — where the camera frames the action).
static func shock(strength: float = 1.0, center: Vector2 = Vector2(0.5, 0.5)) -> void:
	var pp: PostProcess = _find()
	if pp != null:
		pp._begin_shock(strength, center)


## Floor band changed: re-tint the grade to match the theme.
static func set_theme(tint: Color) -> void:
	var pp: PostProcess = _find()
	if pp != null:
		pp._apply_theme(tint)
