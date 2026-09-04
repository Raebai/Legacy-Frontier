class_name Vfx
extends RefCounted
## Spawn helper for the stylized shader EXPLOSION (from the open-source godot-4-VFX
## pack, vendored under effects/2d_explosion/). A big fiery blast that self-manages —
## plays its AnimationPlayer then queue_free()s itself. The shader reads its own fire
## gradient (ignores modulate), so it's used at FIRE / energy big-impact beats where
## the orange fireball always reads right, LAYERED over the procedural element FX
## (ElementFx / FlameBurst) — not on ice/holy/etc where it would clash.
##
## (The pack's cheap pixel-particle scenes were evaluated + rejected: they looked
## worse than the game's own additive/HDR-bloom procedural VFX. This shader
## explosion was the one genuine quality win.)

const EXPLOSION: String = "res://effects/2d_explosion/source/explosion.tscn"


## Spawn a fiery explosion at `world_pos`. The raw scene is ~1000px across, so
## `size` ~0.25-0.4 fits a spell blast. Self-frees when its animation ends.
##
## ⚠ NOT ON A PHONE, and this was the only effect in this file's remit with no
## `graphics_quality` gate at all. It is the one vendored SHADER effect in the game:
## a ~1000 px quad running a fire shader with an AnimationPlayer driving it, and on
## a tile GPU a large alpha-blended shaded quad is the expensive kind of object —
## the same argument `PostProcess._enabled` already makes for the screen grade.
##
## It is safe to drop precisely because of what this file's own header says: it is
## a LAYER over the procedural element FX, never the effect itself. Its only caller
## (`ElementFx`) has already spawned its own burst by the time it gets here, so LOW
## keeps the fire and loses the shader on top of it — a degradation, not a deletion.
static func explosion(parent: Node, world_pos: Vector2, size: float = 0.32) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if TuningConfig.quality_is_low():
		return
	var packed: PackedScene = load(EXPLOSION) as PackedScene
	if packed == null:
		return
	var ex: Node2D = packed.instantiate() as Node2D
	if ex == null:
		return
	parent.add_child(ex)
	ex.global_position = world_pos
	ex.scale = Vector2.ONE * size
	ex.z_index = 4  # above the fighters, below the HUD
	PostProcess.pulse_heat(clampf(size * 1.6, 0.2, 0.7))  # fire beat -> heat-haze shimmer
