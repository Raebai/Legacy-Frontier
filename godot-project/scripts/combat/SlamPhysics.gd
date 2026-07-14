class_name SlamPhysics
extends RefCounted
## Shared "a hard-knockback body slams into something" impact check for any
## CharacterBody2D carrying a decaying knockback channel (Enemy._knockback,
## Hero._knockback). Call immediately after move_and_slide(). Craters the floor
## cosmetically on any qualifying slam (unchanged feel from the old Enemy-only
## version); ADDITIONALLY damages any "destructible" body actually collided with
## this frame (crate / terrain block / breakable platform), so a hard hit into
## cover visibly cracks it. Returns the spent (zeroed) knockback when a slam
## fired, else the value unchanged — GDScript statics can't write back to the
## caller's field, so the caller re-assigns: `_knockback = SlamPhysics.check(...)`.

const MIN_SLAM_SPEED: float = 250.0   # the threshold the old crater-only check used
const DAMAGE_SCALE: float = 0.12      # impact speed -> damage
const DAMAGE_MIN: int = 15
const DAMAGE_MAX: int = 60


static func check(body: CharacterBody2D, knockback: Vector2) -> Vector2:
	if knockback.length() < MIN_SLAM_SPEED or body.get_slide_collision_count() <= 0:
		return knockback
	var dmg: int = clampi(int(knockback.length() * DAMAGE_SCALE), DAMAGE_MIN, DAMAGE_MAX)
	var dir: Vector2 = knockback.normalized()
	var hit_destructible: bool = false
	for i: int in body.get_slide_collision_count():
		var col: KinematicCollision2D = body.get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider is Node and (collider as Node).is_in_group("destructible"):
			if collider.has_method("damage_at"):
				collider.call("damage_at", dmg, col.get_position(), dir)
				hit_destructible = true
			elif collider.has_method("take_damage"):
				collider.call("take_damage", dmg)
				hit_destructible = true
	CombatVfx.spawn_burst(
		body.get_parent(), body.global_position,
		Color(0.72, 0.7, 0.68, 0.7), Color(0.72, 0.7, 0.68, 0.0),
		12, 0.32, 40.0, 130.0
	)
	ScorchDecal.spawn(body.get_parent(), body.global_position, 15.0, "crack", Color(0.2, 0.2, 0.22, 0.5))
	GroundCrater.spawn(body.get_parent(), body.global_position, 20.0, true)  # gouge where a hard slam lands
	Juice.shake_camera(5.0 if hit_destructible else 3.0)
	return Vector2.ZERO
