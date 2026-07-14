class_name FlameBurst
extends Node2D
## A short-lived organic FLAME plume for the BIG fire spectacles (meteor impacts,
## the fire blast) — the maker's "the fire effect is so corny" fix carried onto the
## big spells. Reuses the shared CharacterRig.draw_flame (layered licking tongues +
## white-hot HDR core + rising embers) as a cluster that flares up then dies. Draw-
## time only (no autoloads); parent it to the arena so it outlives the caster.

const LIFE: float = 0.6

var _size: float = 40.0
var _phase: float = 0.0
var _elapsed: float = 0.0


## Spawn a flame plume of ~`size` at `world_pos` under `parent` (the arena).
static func spawn(parent: Node, world_pos: Vector2, size: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var fb := FlameBurst.new()
	fb._size = size
	parent.add_child(fb)
	fb.global_position = world_pos
	fb.z_index = 40


func _process(delta: float) -> void:
	_elapsed += delta
	_phase += delta
	if _elapsed >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = _elapsed / LIFE
	# Flare up fast, then fade out.
	var strength: float = clampf(t * 5.0, 0.0, 1.0) * (1.0 - smoothstep(0.4, 1.0, t))
	var grow: float = 0.7 + 0.55 * smoothstep(0.0, 0.35, t)
	# A cluster of flames = a big plume (each licks independently).
	CharacterRig.draw_flame(self, Vector2(0.0, 0.0), _size * grow, strength, _phase)
	CharacterRig.draw_flame(self, Vector2(-_size * 0.55, _size * 0.12), _size * 0.62 * grow, strength * 0.85, _phase * 1.2 + 1.0)
	CharacterRig.draw_flame(self, Vector2(_size * 0.55, _size * 0.16), _size * 0.58 * grow, strength * 0.8, _phase * 0.9 + 2.3)
