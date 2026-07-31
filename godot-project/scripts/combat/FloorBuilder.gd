class_name FloorBuilder
extends RefCounted
## Populates a floor's room from data: given a LayoutDef, instances the crates,
## weapon pickups, the floor's SPELL DROP and the machinery around it. Pure
## "data -> children" — no enemy logic, no sequencing. The one arena shell is
## parameterized by this.
##
## THE DROP ECONOMY ENTERS HERE, and this is the only place it touches the floor
## lifecycle. `Arena._rebuild_room` frees every child of the Room and calls
## `build_props` once per floor, which makes this function the exact seam for all
## four of the spec's per-floor rules:
##   * the Tier 2 pickup is placed (or not — see `SpellDrops`, it is a roll);
##   * `BossDropWatcher` is parked, ready to drop a Tier 3 when the guardian falls;
##   * `SpellHandoff` is parked, so players can pass what they find;
##   * every hero's grants are RESTORED, which is the spec's "resets each floor"
##     made literal — you carry your floor number up the tower, not your loot.
##
## ⚠ THE SIGNATURE IS UNCHANGED ON PURPOSE. `Arena.gd` calls `build_props(room,
## layout)` and is owned by another agent, so the floor number is DERIVED here
## (from `GameState`, via the container's tree) rather than added as a parameter.
## The optional third argument exists only for tests and capture tools, which have
## no GameState to ask.

const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/combat/WeaponPickup.tscn")
const DESTRUCTIBLE_SCENE: PackedScene = preload("res://scenes/combat/DestructibleProp.tscn")
## Loaded by PATH, not preloaded. `SpellPickup.gd` reaches `Sfx` / `Juice` /
## `CombatVfx`, and a `preload` here would drag all three into the compile graph of
## every headless suite that touches FloorBuilder — where autoloads do not exist.
const SPELL_PICKUP_PATH: String = "res://scenes/combat/SpellPickup.tscn"


## Build the floor's props into `container` (typically a fresh Room node that the
## arena frees + rebuilds per floor).
static func build_props(container: Node2D, layout: LayoutDef, floor_index: int = -1) -> void:
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
	build_drop_economy(container, layout, floor_index)


## The per-floor drop machinery. Split out from `build_props` so a test or a
## capture tool can stage it alone, and so the prop loop above stays the one-screen
## function it has always been.
static func build_drop_economy(container: Node2D, layout: LayoutDef,
		floor_index: int = -1) -> void:
	if container == null or not container.is_inside_tree():
		return
	var floor_no: int = _resolve_floor(container, floor_index)
	_restore_grants(container)
	_place_floor_drop(container, layout, floor_no)
	var watcher: Node2D = BossDropWatcher.new()
	watcher.name = "BossDropWatcher"
	watcher.floor_index = floor_no
	container.add_child(watcher)
	# Centred so its own `global_position` is a sane fallback drop point for a
	# guardian that somehow died without a body to ask.
	watcher.global_position = _anchor(layout, SpellDrops.BOSS_ANCHOR)
	var handoff: Node2D = SpellHandoff.new()
	handoff.name = "SpellHandoff"
	container.add_child(handoff)


## PROGRESSION RESETS EACH FLOOR. Every hero gets its class kit back at the top of
## the floor, so the Tier 1 -> Tier 2 -> Tier 3 arc happens INSIDE a floor and
## never stacks across them. Without this the spec's escalation becomes a
## stockpile, and by floor five everyone is holding two Tier 3s.
static func _restore_grants(container: Node2D) -> void:
	for h: Node in container.get_tree().get_nodes_in_group("hero"):
		SpellGrant.restore_all(h)


static func _place_floor_drop(container: Node2D, layout: LayoutDef, floor_no: int) -> void:
	var id: String = SpellDrops.roll_floor_drop(floor_no)
	if id == "":
		return   # most floors have nothing. That is what makes the rest matter.
	var pickup: Area2D = (load(SPELL_PICKUP_PATH) as PackedScene).instantiate()
	container.add_child(pickup)
	pickup.global_position = _anchor(layout, SpellDrops.DROP_ANCHOR)
	pickup.call(&"set_spell", id)


## A fraction of the room resolved to a world point. Fractions rather than pixels so
## a drop lands sensibly on any `room_size` instead of inside the wall of a small one.
static func _anchor(layout: LayoutDef, frac: Vector2) -> Vector2:
	var size: Vector2 = layout.room_size if layout != null else Vector2(960.0, 480.0)
	return Vector2(size.x * frac.x, size.y * frac.y)


## The floor number for the seeded roll: the explicit override, else GameState, else
## 1. A sandbox arena with no GameState still rolls a floor-1 table rather than
## silently never dropping anything, which would be indistinguishable from the
## feature being broken.
static func _resolve_floor(container: Node2D, floor_index: int) -> int:
	if floor_index >= 0:
		return floor_index
	var gs: Node = container.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method(&"current_floor"):
		return int(gs.call(&"current_floor"))
	return 1
