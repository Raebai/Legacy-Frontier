class_name FloorBuilder
extends RefCounted
## Populates a floor's room from data: given a LayoutDef, instances the crates
## and weapon pickups at their authored points. Pure "data -> children" — no
## enemy logic, no sequencing. The one arena shell is parameterized by this.

const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/combat/WeaponPickup.tscn")
const DESTRUCTIBLE_SCENE: PackedScene = preload("res://scenes/combat/DestructibleProp.tscn")


## Build the floor's props into `container` (typically a fresh Room node that the
## arena frees + rebuilds per floor).
static func build_props(container: Node2D, layout: LayoutDef) -> void:
	if layout == null:
		return
	for pos: Vector2 in layout.weapon_pickups:
		var pickup: Area2D = WEAPON_PICKUP_SCENE.instantiate()
		pickup.weapon_kind = "sword"
		container.add_child(pickup)
		pickup.global_position = pos
	for pos: Vector2 in layout.crate_positions:
		var crate: StaticBody2D = DESTRUCTIBLE_SCENE.instantiate()
		container.add_child(crate)
		crate.global_position = pos
