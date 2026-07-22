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
const SHOCK_BASE_AMP: float = 0.012    # UV displacement at full strength

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
	# Aberration follows the camera trauma exactly (it already decays there), so a
	# hit smears the screen for free — no hit-path call site needed.
	_mat.set_shader_parameter(&"trauma", _camera_trauma())
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
