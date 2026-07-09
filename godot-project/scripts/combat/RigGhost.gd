class_name RigGhost
extends Node2D
## A static, fading afterimage of a CharacterRig pose (dash trail).
## Pure visual: no animation, no collision; frees itself after FADE_TIME.
## Spawned by CharacterRig.spawn_ghost, which snapshots pose + equipment
## and copies the rig's global transform (facing flip included).
## Tuning knobs: FADE_TIME for trail persistence, WIND_* for streak look.

const FADE_TIME: float = 0.34
const WIND_STREAKS: int = 2
const WIND_LENGTH: float = 26.0
const WIND_WIDTH: float = 1.2
## px/s^2 an optional launch velocity bleeds off (corpse drift).
const LAUNCH_DECAY: float = 420.0

var pose: Dictionary = {}
var equipment_slots: Dictionary = {}
var fig_height: float = 22.0
var base_color: Color = Color(0.45, 0.7, 1.0, 0.5)
## Global-space travel direction; ZERO disables the motion streaks.
var wind_dir: Vector2 = Vector2.ZERO
## Optional launch: the ghost TRANSLATES along this (decaying) velocity as it
## fades — the enemy-death "body flies" corpse. ZERO = static afterimage.
var launch_velocity: Vector2 = Vector2.ZERO
## Per-instance fade override (corpses linger longer than dash afterimages).
var fade_time: float = FADE_TIME

var _age: float = 0.0


func _ready() -> void:
	add_to_group("rig_ghost")


func _process(delta: float) -> void:
	_age += delta
	if _age >= fade_time:
		queue_free()
		return
	if launch_velocity != Vector2.ZERO:
		global_position += launch_velocity * delta
		launch_velocity = launch_velocity.move_toward(Vector2.ZERO, LAUNCH_DECAY * delta)
	queue_redraw()


func _draw() -> void:
	var fade: float = clampf(1.0 - _age / fade_time, 0.0, 1.0)
	var col: Color = Color(base_color.r, base_color.g, base_color.b, base_color.a * fade)
	CharacterRig.draw_figure(self, pose, col, equipment_slots, fig_height)
	if wind_dir != Vector2.ZERO:
		_draw_wind_streaks(col)


## Short motion lines trailing opposite the travel direction.
func _draw_wind_streaks(col: Color) -> void:
	var local_back: Vector2 = -global_transform.affine_inverse().basis_xform(wind_dir)
	if local_back == Vector2.ZERO:
		return
	local_back = local_back.normalized()
	var streak_col: Color = Color(col.r, col.g, col.b, col.a * 0.6)
	for i: int in range(WIND_STREAKS):
		var side: float = (float(i) * 2.0 - 1.0) * fig_height * 0.18  # -/+ of torso
		var origin: Vector2 = Vector2(0.0, side)
		draw_line(origin, origin + local_back * WIND_LENGTH, streak_col, WIND_WIDTH)
